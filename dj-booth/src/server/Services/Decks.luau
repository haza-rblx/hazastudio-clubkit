--!strict
-- The transport. Deck state (track, play / pause, cue, pitch, mixer) and the anchor (`pos` at server
-- time `at`) live in State.session; the server creates no Sound. Every client builds its own deck
-- Sounds and draws time with DeckClock (ADR 0021). Deck end and auto crossfade are timed from the
-- anchor, every change re-anchors the position, and nothing here yields for audio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.CosmicDJ.Shared
local Dict = require(Shared.Dict)
local DeckClock = require(Shared.DeckClock)
local Mix = require(Shared.Mix)
local QueueLogic = require(Shared.Queue)
local Types = require(Shared.Types)
local DeckBrakeConfig = require(Shared.DeckBrakeConfig)
local State = require(script.Parent.State)

local Decks = {}

-- a deck-off brake in progress per deck: the thread that finishes it, and where the record ends up
local braking: { thread? } = { nil, nil }
-- when the running brake's finish lands (os.clock), so a second stop can ride it instead of restarting
local brakeEnd: { number } = { 0, 0 }

local function cancelBrake(n: number)
	local th = braking[n]
	brakeEnd[n] = 0
	if th then
		task.cancel(th)
		braking[n] = nil
	end
end

-- the deck-off preset, when the brake is on
local function brakePreset(): (string?, DeckBrakeConfig.BrakePreset?)
	local name = State.settings().deckOff
	if name == nil then
		name = DeckBrakeConfig.Preset
	end
	local p = DeckBrakeConfig.Presets[name]
	if p and p.duration > 0 then
		return name, p
	end
	return nil, nil
end

local function deckState(n: number): Types.Deck
	return State.session().decks[n]
end

local function setDeck(n: number, patch: { [string]: any })
	State.update(State.session, function(s)
		return Dict.merge(s, { decks = Dict.set(s.decks, n, Dict.merge(s.decks[n], patch)) })
	end)
end

local function trackOf(n: number): Types.Track?
	local id = deckState(n).trackId
	return if id then State.library().tracks[id] else nil
end

-- the track position of a deck at server time `now`
local function positionAt(n: number, now: number): number
	return DeckClock.position(deckState(n), trackOf(n), now)
end

-- the position of a deck now (track seconds)
function Decks.position(n: number): number
	return positionAt(n, State.now())
end

-- re-anchors a deck. A move (play state or position) ends any brake in progress; a brake stop passes
-- its own `brake` in the patch, so the client sees the stop and the brake in one state.
local function anchor(n: number, patch: { [string]: any }?)
	local now = State.now()
	local d = deckState(n)
	local p = {
		pos = positionAt(n, now),
		at = now,
	}
	if patch == nil or patch.playing ~= nil or patch.pos ~= nil or d.playing then
		p.brake = Dict.None
	end
	if patch then
		for k, v in patch do
			p[k] = v
		end
	end
	setDeck(n, p)
end

-- the pitch that makes deck n match the other deck: the same BPM when both tracks have one,
-- otherwise the same playback rate (owner, 2026-10-23: sync is about speed, not a BPM gate)
local function syncPitch(t: Types.Track, other: Types.Track, otherPitch: number): number
	local lo, hi = Mix.pitchBounds(State.settings().pitch)
	local target, own
	if t.bpm and other.bpm then
		target, own = other.bpm * other.speed * (1 + otherPitch), t.bpm * t.speed
	else
		target, own = other.speed * (1 + otherPitch), t.speed
	end
	return math.clamp(target / own - 1, lo, hi)
end

function Decks.load(n: number, trackId: string): (boolean, string?)
	cancelBrake(n)
	local t = State.library().tracks[trackId]
	if not t then
		return false, "That track is gone."
	end
	if t.status == "unavailable" then
		return false, "Roblox can't load this track."
	end
	local d = deckState(n)
	if d.playing and State.settings().busyDeck == 2 then
		return false, "The deck is playing; stop it first."
	end
	local start = t.start or 0
	-- a new track breaks any existing link
	if deckState(3 - n).synced then
		setDeck(3 - n, { synced = false })
	end
	local pitch = d.pitch
	local synced = false
	-- sync on load: match the other deck's tempo
	local other = trackOf(3 - n)
	if State.settings().syncOnLoad and other then
		pitch = syncPitch(t, other, deckState(3 - n).pitch)
		synced = true
	end
	setDeck(n, {
		trackId = trackId,
		playing = false,
		pos = start,
		at = State.now(),
		cue = start,
		pitch = pitch,
		synced = synced,
		lastCue = Dict.None,
		brake = Dict.None,
	})
	return true
end

function Decks.play(n: number): (boolean, string?)
	cancelBrake(n)
	local d = deckState(n)
	if not d.trackId then
		return false, "Load a track first."
	end
	anchor(n, { playing = true })
	return true
end

-- brake: the clients slow their own Sounds for the preset's duration, and the deck's state stops at
-- the distance the record covers meanwhile
function Decks.pause(n: number, brake: boolean?): (boolean, string?)
	-- already coasting down: a second stop changes nothing (restarting would spin it back up)
	if brake and braking[n] then
		return true
	end
	cancelBrake(n)
	local name, p = brakePreset()
	local d = deckState(n)
	if brake and d.playing and name and p then
		local pos = Decks.position(n)
		local final = pos + DeckClock.rate(d, trackOf(n)) * p.duration / (p.shape + 1)
		anchor(n, { playing = false, pos = final, brake = { preset = name, at = State.now(), from = pos } })
		brakeEnd[n] = os.clock() + p.duration
		braking[n] = task.delay(p.duration, function()
			braking[n] = nil
		end)
		return true
	end
	anchor(n, { playing = false })
	return true
end

-- CUE, as on a CDJ: paused away from the cue point sets it there; paused on it previews while held;
-- playing jumps back to it and stops
local previewing = { false, false }
function Decks.cueDown(n: number, brake: boolean?): (boolean, string?)
	if brake and braking[n] then
		return true
	end
	cancelBrake(n)
	local d = deckState(n)
	if not d.trackId then
		return false, "Load a track first."
	end
	if d.playing then
		local name, p = brakePreset()
		if brake and name and p then
			local pos = Decks.position(n)
			anchor(n, { playing = false, pos = d.cue, brake = { preset = name, at = State.now(), from = pos } })
			brakeEnd[n] = os.clock() + p.duration
			braking[n] = task.delay(p.duration, function()
				braking[n] = nil
			end)
		else
			anchor(n, { playing = false, pos = d.cue })
		end
	elseif math.abs(Decks.position(n) - d.cue) < 0.05 then
		previewing[n] = true
		anchor(n, { playing = true })
	else
		anchor(n, { cue = Decks.position(n) })
	end
	return true
end

function Decks.cueUp(n: number): (boolean, string?)
	if previewing[n] then
		previewing[n] = false
		anchor(n, { playing = false, pos = deckState(n).cue })
	end
	return true
end

function Decks.seek(n: number, seconds: number): (boolean, string?)
	cancelBrake(n)
	local t = trackOf(n)
	if not t then
		return false
	end
	local len = DeckClock.length(t, seconds) or 0
	anchor(n, { pos = math.clamp(seconds, 0, len) })
	return true
end

function Decks.nudge(n: number, delta: number)
	if not deckState(n).trackId then
		return
	end
	anchor(n, { pos = math.max(0, Decks.position(n) + delta) })
end

function Decks.hotCue(n: number, k: number, clear: boolean): (boolean, string?)
	local d = deckState(n)
	local id = d.trackId
	if not id then
		return false, "Load a track first."
	end
	local key = tostring(k)
	local t = State.library().tracks[id]
	local cues = (t and t.cues) or {}
	if clear then
		State.update(State.library, function(lib)
			local tr = lib.tracks[id]
			if not tr then
				return lib
			end
			return Dict.merge(
				lib,
				{ tracks = Dict.set(lib.tracks, id, Dict.merge(tr, { cues = Dict.set(tr.cues or {}, key, nil) })) }
			)
		end)
		return true
	end
	local at = cues[key]
	if at == nil then
		local pos = Decks.position(n)
		State.update(State.library, function(lib)
			local tr = lib.tracks[id]
			if not tr then
				return lib
			end
			return Dict.merge(
				lib,
				{ tracks = Dict.set(lib.tracks, id, Dict.merge(tr, { cues = Dict.set(tr.cues or {}, key, pos) })) }
			)
		end)
		setDeck(n, { lastCue = k })
	else
		anchor(n, { pos = at, lastCue = k })
	end
	return true
end

function Decks.sync(n: number): (boolean, string?)
	-- either deck linked: SYNC again unlinks both, each keeps its current pitch
	if deckState(1).synced or deckState(2).synced then
		setDeck(1, { synced = false })
		setDeck(2, { synced = false })
		return true
	end
	local t, other = trackOf(n), trackOf(3 - n)
	if not (t and other) then
		return false, "Load a track on both decks to sync."
	end
	setDeck(3 - n, { synced = false })
	anchor(n, { pitch = syncPitch(t, other, deckState(3 - n).pitch), synced = true })
	return true
end

function Decks.eject(n: number, brake: boolean?): (boolean, string?)
	-- `keep` is the brake the deck is already coasting on (nil = none)
	local function clear(keep: any?)
		-- ejecting breaks the link on both decks
		if deckState(3 - n).synced then
			setDeck(3 - n, { synced = false })
		end
		setDeck(n, {
			trackId = Dict.None,
			playing = false,
			pos = 0,
			at = State.now(),
			cue = 0,
			lastCue = Dict.None,
			synced = false,
			brake = keep or Dict.None,
		})
	end
	-- ejecting while it coasts down: the clients' brake runs on, the state waits for its end
	local running = braking[n]
	if brake and running then
		task.cancel(running)
		clear(deckState(n).brake)
		braking[n] = task.delay(math.max(0, brakeEnd[n] - os.clock()), function()
			braking[n] = nil
		end)
		return true
	end
	cancelBrake(n)
	local name, p = brakePreset()
	local d = deckState(n)
	if brake and d.playing and name and p then
		local pos = Decks.position(n)
		clear({ preset = name, at = State.now(), from = pos })
		brakeEnd[n] = os.clock() + p.duration
		braking[n] = task.delay(p.duration, function()
			braking[n] = nil
		end)
	else
		clear()
	end
	return true
end

-- a continuous control
function Decks.live(n: number, param: string, v: number)
	local lo, hi = Mix.pitchBounds(State.settings().pitch)
	if param == "Pitch" then
		-- a follower moving its own pitch unlinks; the leader moving drags the follower along
		local leader = deckState(3 - n).synced
		anchor(n, { pitch = math.clamp(v, lo, hi), synced = false })
		local t, other = trackOf(3 - n), trackOf(n)
		if leader and t and other then
			anchor(3 - n, { pitch = syncPitch(t, other, deckState(n).pitch) })
		end
	elseif param == "Vol" then
		setDeck(n, { vol = math.clamp(v, 0, 1) })
	elseif param == "Filter" then
		setDeck(n, { filter = math.clamp(v, 0, 1) })
	elseif param == "EqHigh" or param == "EqMid" or param == "EqLow" then
		local i = if param == "EqHigh" then 1 elseif param == "EqMid" then 2 else 3
		setDeck(n, { eq = Dict.set(deckState(n).eq, i, math.clamp(v, 0, 1)) })
	elseif param == "Echo" or param == "Reverb" or param == "Flanger" then
		local i = if param == "Echo" then 1 elseif param == "Reverb" then 2 else 3
		setDeck(n, { fx = Dict.set(deckState(n).fx, i, math.clamp(v, 0, 1)) })
	elseif param == "Xfader" then
		State.update(State.session, function(s)
			return Dict.merge(s, { xfader = math.clamp(v, 0, 1) })
		end)
	elseif param == "Curve" then
		State.update(State.session, function(s)
			return Dict.merge(s, { curve = math.clamp(v, 0, 1) })
		end)
	elseif param == "Master" then
		State.update(State.session, function(s)
			return Dict.merge(s, { master = math.clamp(v, 0, 1) })
		end)
	end
end

-- the track for deck `to`: one the DJ cued there by hand, else the head of the queue (loaded there).
-- Entries that won't load are dropped. True when the deck now has a track ready.
local function nextUp(to: number): boolean
	local d = deckState(to)
	if d.trackId and not d.playing then
		return true
	end
	while true do
		local entry, rest = QueueLogic.pop(State.session().queue)
		if not entry then
			return false
		end
		State.update(State.session, function(s)
			return Dict.merge(s, { queue = rest })
		end)
		if Decks.load(to, entry.trackId) then
			return true
		end
	end
	return false
end

-- a deck ran out: with auto mix on, the other deck takes over (its next track, if there is one) and
-- the fader goes to it; either way this deck ejects. With auto mix off the queue is left alone.
local function ended(n: number)
	anchor(n, { playing = false })
	local to = 3 - n
	if State.session().automix and not deckState(to).playing and nextUp(to) then
		Decks.play(to)
		Decks.live(1, "Xfader", if to == 2 then 1 else 0)
	end
	Decks.eject(n)
end

-- auto crossfade: when the deck the fader favours is about to run out and the other deck has a
-- track ready, start it and sweep the fader across. With auto mix on the next queued track is
-- loaded 30 s early (only when the other deck is empty, so each transition pops the queue once);
-- the sweep itself still starts at `secs` left.
local sweeping = false
local unknownWarned: { string? } = { nil, nil } -- the track each deck last warned about (no length)
local function autoCrossfade()
	local secs = State.settings().crossfade
	if secs <= 0 or sweeping then
		return
	end
	local s = State.session()
	local from = if s.xfader <= 0.5 then 1 else 2
	local to = 3 - from
	local d = s.decks[from]
	if not (d.playing and d.trackId) then
		return
	end
	local left = DeckClock.timeLeft(d, trackOf(from), State.now())
	if left == nil then
		-- no length yet: skip the tick, keep checking, say so once per track
		if unknownWarned[from] ~= d.trackId then
			unknownWarned[from] = d.trackId
			warn("[CosmicDJ] deck " .. from .. " has no track length; auto crossfade waits for one")
		end
		return
	end
	if s.automix and not s.decks[to].trackId and left <= secs + 30 then
		nextUp(to)
	end
	local o = deckState(to)
	if not (o.trackId and not o.playing) or left > secs then
		return
	end
	sweeping = true
	local start, target = s.xfader, if to == 2 then 1 else 0
	local t0 = os.clock()
	task.spawn(function()
		-- sweeping clears however the sweep ends
		local ok, err = pcall(function()
			Decks.play(to)
			while os.clock() - t0 < secs do
				local k = (os.clock() - t0) / secs
				Decks.live(1, "Xfader", start + (target - start) * k)
				task.wait(0.05)
			end
			Decks.live(1, "Xfader", target)
		end)
		sweeping = false
		if not ok then
			warn("[CosmicDJ] crossfade sweep failed: " .. tostring(err))
		end
	end)
end

-- the set ends: the room fades out (clients draw `fade` on their own master), then both decks stop.
-- No wait: the stop is a delayed call, and a later fade replaces it.
local fadeToken = 0
function Decks.fadeOutAll()
	fadeToken += 1
	local token = fadeToken
	local secs = State.settings().fadeOut
	local function stop()
		if token ~= fadeToken then
			return
		end
		-- stop first, then lift the fade: a client must never get full volume on a still-playing deck
		for n = 1, 2 do
			if deckState(n).playing then
				Decks.pause(n)
			end
		end
		State.update(State.session, function(s)
			return Dict.merge(s, { fade = Dict.None })
		end)
	end
	if secs > 0 then
		State.update(State.session, function(s)
			return Dict.merge(s, { fade = { at = State.now(), dur = secs } })
		end)
		task.delay(secs, stop)
	else
		stop()
	end
end

function Decks.start()
	-- a fade left in the session would hold the room silent; start clean
	State.update(State.session, function(s)
		return Dict.merge(s, { fade = Dict.None })
	end)
	-- auto crossfade runs every frame; deck end is checked every 0.1 s
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		autoCrossfade()
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		local now = State.now()
		for n = 1, 2 do
			if DeckClock.ended(deckState(n), trackOf(n), now) then
				ended(n)
			end
		end
	end)
end

return Decks
