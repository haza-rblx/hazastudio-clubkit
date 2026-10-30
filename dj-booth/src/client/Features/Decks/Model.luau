--!strict
-- Per-deck view model: the deck's synced state and track, its live position (from the anchor, on a
-- frame clock), and the readouts the surface prints. Also sends the deck's controls.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Vide = require(ReplicatedStorage.CosmicDJ.Packages.Vide)
local Shared = ReplicatedStorage.CosmicDJ.Shared
local DeckBrakeConfig = require(Shared.DeckBrakeConfig)
local Format = require(Shared.Format)
local Mix = require(Shared.Mix)
local Types = require(Shared.Types)
local Actions = require(script.Parent.Parent.Parent.Actions)
local Audio = require(script.Parent.Parent.Parent.Audio)
local Store = require(script.Parent.Parent.Parent.Store)

local source, derive, untrack = Vide.source, Vide.derive, Vide.untrack

local Model = {}

-- one frame clock for every time readout; ticks only while the decks are on screen. It sums the
-- engine's frame times (not os.clock at the callback, which lands at a different point of each frame),
-- so a playhead advanced by it moves the same amount per drawn frame
Model.clock = source(0)
local ticking = 0
local frameTime = 0
local conn: RBXScriptConnection? = nil
function Model.tick(on: boolean)
	ticking += if on then 1 else -1
	if ticking > 0 and not conn then
		conn = RunService.RenderStepped:Connect(function(dt: number)
			frameTime += dt
			Model.clock(frameTime)
		end)
	elseif ticking <= 0 and conn then
		conn:Disconnect()
		conn = nil
	end
end

-- the deck's Sound (this client's own, see Audio), for meters
function Model.sound(n: number): Sound?
	return Audio.sound(n)
end

-- a deck's loudness for meters, 0..1
function Model.level(n: number): number
	local s = Model.sound(n)
	if s and s.IsPlaying then
		return math.clamp(s.PlaybackLoudness * s.Volume / 400, 0, 1)
	end
	return 0
end

export type Deck = {
	n: number,
	deck: () -> Types.Deck,
	track: () -> Types.Track?,
	position: () -> number, -- seconds into the track (track time)
	length: () -> number?, -- seconds (track time)
	rate: () -> number, -- track speed x (1 + pitch)
	live: () -> boolean, -- playing and heard
	color: () -> Color3,
	-- controls
	set: (param: string, v: number) -> (),
	value: (param: string, synced: () -> number) -> () -> number,
	run: (action: string) -> (),
	nudge: (seconds: number) -> (), -- jog scratch: sent to the server, drawn at once
}

function Model.new(n: number, coverColor: (string) -> Color3): Deck
	local deck = derive(function()
		return Store.session().decks[n]
	end)
	local track = derive(function()
		local id = deck().trackId
		return if id then Store.library().tracks[id] else nil
	end)
	local rate = derive(function()
		local t = track()
		return (if t then t.speed else 1) * (1 + deck().pitch)
	end)
	-- scratch nudges the server has not re-anchored for yet: drawn locally so the platter follows the
	-- hand instead of waiting a round trip; the next anchor (it carries them) clears the offset
	local scratch = source(0)
	local anchoredAt = untrack(deck).at
	Vide.effect(function()
		local at = deck().at
		if at ~= anchoredAt then
			anchoredAt = at
			scratch(0)
		end
	end)
	-- the drawn playhead while playing: advanced by the frame clock at the deck's rate and eased toward
	-- the anchor's position (server time is read at a different moment each frame, which shakes the
	-- platter by a degree or so); a jump bigger than SNAP (seek, cue, scratch, a new track) lands at once
	local SNAP, EASE = 0.25, 0.08
	local shown: number?, shownAt = nil, 0
	local function position(): number
		local d = deck()
		if d.playing then
			local now = Model.clock()
			local target = Store.position(d, track()) + scratch()
			-- several readouts ask in one frame: they all get that frame's value
			if shown ~= nil and now == shownAt then
				return shown :: number
			end
			-- no frame clock (decks off screen) or a fresh start: the anchor as it is
			if ticking <= 0 or shown == nil or now < shownAt then
				shown, shownAt = target, now
				return target
			end
			local predicted = (shown :: number) + (now - shownAt) * rate()
			local err = target - predicted
			shown = if math.abs(err) > SNAP then target else predicted + err * EASE
			shownAt = now
			return shown :: number
		end
		shown = nil
		-- braking: the record coasts down on the same curve as the sound, (1 - x) ^ shape, from where
		-- the server's brake began (deck.brake, on the same server clock)
		local b = d.brake
		local p = if b then DeckBrakeConfig.Presets[b.preset] else nil
		if b and p and d.trackId then
			Model.clock()
			local x = math.clamp((Store.now() - b.at) / p.duration, 0, 1)
			if x < 1 then
				local k = p.shape + 1
				return b.from + rate() * p.duration * (1 - (1 - x) ^ k) / k
			end
		end
		return d.pos + scratch()
	end
	local m: Deck = {
		n = n,
		deck = deck,
		track = track,
		position = position,
		length = function()
			local t = track()
			return t and t.len
		end,
		rate = rate,
		live = function()
			local s = Store.session()
			local d = deck()
			local a, b = Mix.crossfade(s.xfader, s.curve)
			return d.playing and d.vol > 0.01 and (if n == 1 then a else b) > 0.05
		end,
		color = function()
			local id = deck().trackId
			return if id then coverColor(id) else Color3.fromHex("2a2a2a")
		end,
		set = function(param: string, v: number)
			Actions.live(n, param :: any, v)
		end,
		value = function(param: string, synced: () -> number)
			return function()
				return Store.localOr(n .. param, synced())
			end
		end,
		run = function(action: string)
			Actions.send({ Kind = "Deck", Deck = n, Action = action :: any })
		end,
		nudge = function(seconds: number)
			scratch(untrack(scratch) + seconds)
			Actions.nudge(n, seconds)
		end,
	}
	return m
end

-- readouts
function Model.remaining(m: Deck): number?
	local len = m.length()
	if not len then
		return nil
	end
	return math.max(0, (len - m.position()) / m.rate())
end

-- the header counts in the track's own time (its playback speed, not the pitch fader)
function Model.headerLeft(m: Deck): string
	local len = m.length()
	local t = m.track()
	if not len or not t then
		return "—"
	end
	return "-" .. Format.mmss(math.max(0, len - m.position()) / t.speed)
end

function Model.headerAt(m: Deck): string
	local len = m.length()
	if not len then
		return "— / —"
	end
	local t = m.track() :: Types.Track
	return Format.mmss(m.position() / t.speed) .. " / " .. Format.mmss(len / t.speed)
end

function Model.progress(m: Deck): number
	local len = m.length()
	return if len and len > 0 then math.clamp(m.position() / len, 0, 1) else 0
end

return Model
