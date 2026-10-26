--!strict
-- This player's deck engine (ADR 0021). Every client builds its own deck Sounds and effect chains
-- into a local master bus, keeps them loaded with a self-healing load loop, and plays them against the
-- server's deck state (the anchor `pos` at server time `at`). The server creates no audio. Nothing
-- here is destroyed or reparented once built; live Sounds and effects are changed in place.
local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.HazaDJ.Packages.Charm)
local Janitor = require(ReplicatedStorage.HazaDJ.Packages.Janitor)
local Shared = ReplicatedStorage.HazaDJ.Shared
local DeckBrakeConfig = require(Shared.DeckBrakeConfig)
local DeckClock = require(Shared.DeckClock)
local DeckParams = require(Shared.DeckParams)
local LoadPolicy = require(Shared.LoadPolicy)
local Types = require(Shared.Types)
local DeckBrake = require(script.Parent.DeckBrake)
local Net = require(script.Parent.Net)
local Store = require(script.Parent.Store)

local Audio = {}

local FX = DeckParams.FX_DEFAULTS
local TAU = 0.06 -- seconds: the time constant continuous parameters ease toward their targets
local EDGE = 0.5 -- seconds before the end where a deck will not start
local PAD_MAX_TIME = 60 -- a pad sound is destroyed after this, even if it never ends

type Cur = { volume: number, high: number, mid: number, low: number, echo: number, reverb: number, flange: number }

type Deck = {
	n: number,
	sound: Sound,
	eq: EqualizerSoundEffect,
	echo: EchoSoundEffect,
	reverb: ReverbSoundEffect,
	flange: FlangeSoundEffect,
	shift: PitchShiftSoundEffect,
	out: DeckParams.DeckOut?, -- targets from the server state
	cur: Cur?, -- the eased values written to the Sound
	wanted: number?, -- asset id the deck's track needs (nil = none, or unavailable)
	gen: number, -- bumps whenever `wanted` changes; a load loop quits once it is stale
	running: number?, -- the generation a load loop is running for
	loaded: boolean, -- the wanted asset has loaded into `sound`
	loader: typeof(Janitor.new()), -- holds the running load loop; a new loop replaces (cancels) the old one
	anchorPos: number?, -- the anchor last applied to the Sound
	anchorAt: number?,
}

local folder: Folder
local master: SoundGroup
local limiter: CompressorSoundEffect
local masterOut: DeckParams.MasterOut?
local masterCur: number?
local decks: { [number]: Deck } = {}
local isTouch = false
local started = false

-- ── helpers ──

local function setIf(obj: any, prop: string, v: any)
	if obj[prop] ~= v then
		obj[prop] = v
	end
end

local function setId(sound: Sound, id: string)
	if sound.SoundId ~= id then
		sound.SoundId = id
	end
end

local function trackOf(dk: Types.Deck): Types.Track?
	-- the stage reaches every player; the library only those who may open the panel
	local id = dk.trackId
	if not id then
		return nil
	end
	return Store.stageAtom().tracks[id] or Store.libraryAtom().tracks[id]
end

-- the asset a deck needs: its track's asset, unless there is no track or Roblox can't load it
local function wantedOf(dk: Types.Deck): number?
	local t = trackOf(dk)
	if not t or t.status == "unavailable" then
		return nil
	end
	return t.assetId
end

-- the brake preset while a deck's record is still coasting down (nil once it has stopped)
local function brakeOf(dk: Types.Deck, now: number): DeckBrakeConfig.BrakePreset?
	local b = dk.brake
	if not b then
		return nil
	end
	local p = DeckBrakeConfig.Presets[b.preset]
	if p and p.duration > 0 and now < b.at + p.duration then
		return p
	end
	return nil
end

-- where the deck's playhead should be on its Sound now, and whether it is too close to the end to start
local function timing(sound: Sound, dk: Types.Deck, now: number): (number, boolean)
	local t = trackOf(dk)
	local len = DeckClock.length(t, sound.TimeLength)
	local raw = DeckClock.position(dk, t, now)
	if not len then
		return raw, false
	end
	return math.clamp(raw, 0, math.max(0, len - EDGE)), raw >= len - EDGE
end

-- a deck's Sound, for meters and the brake (nil before Audio.start)
function Audio.sound(n: number): Sound?
	local d = decks[n]
	return if d then d.sound else nil
end

-- ── building ──

local function build(n: number): Deck
	local sound = Instance.new("Sound")
	sound.Name = if n == 1 then "DeckA" else "DeckB"
	sound.Looped = false
	sound.Volume = 0
	sound.SoundGroup = master
	sound.Parent = folder

	local eq = Instance.new("EqualizerSoundEffect")
	eq.Priority = FX.priority.eq
	eq.Parent = sound

	local echo = Instance.new("EchoSoundEffect")
	echo.Priority = FX.priority.echo
	echo.DryLevel = FX.echo.DryLevel
	echo.Feedback = FX.echo.Feedback
	echo.Enabled = false
	echo.Parent = sound

	local reverb = Instance.new("ReverbSoundEffect")
	reverb.Priority = FX.priority.reverb
	reverb.DryLevel = FX.reverb.DryLevel
	reverb.DecayTime = FX.reverb.DecayTime
	reverb.Enabled = false
	reverb.Parent = sound

	local flange = Instance.new("FlangeSoundEffect")
	flange.Priority = FX.priority.flange
	flange.Depth = FX.flange.Depth
	flange.Rate = FX.flange.Rate
	flange.Enabled = false
	flange.Parent = sound

	local shift = Instance.new("PitchShiftSoundEffect")
	shift.Priority = FX.priority.shift
	shift.Octave = 1
	shift.Enabled = false
	shift.Parent = sound

	return {
		n = n,
		sound = sound,
		eq = eq,
		echo = echo,
		reverb = reverb,
		flange = flange,
		shift = shift,
		gen = 0,
		loaded = false,
		loader = Janitor.new(),
	}
end

-- ── targets (from the server state, through Charm) ──

local function snapshot(o: DeckParams.DeckOut): Cur
	return {
		volume = o.volume,
		high = o.high,
		mid = o.mid,
		low = o.low,
		echo = o.echoWet,
		reverb = o.reverbWet,
		flange = o.flangeMix,
	}
end

local function retarget()
	local s = Store.sessionAtom()
	local settings = Store.settingsAtom()
	masterOut = DeckParams.master(s, settings)
	for n = 1, 2 do
		local d = decks[n]
		local dk = s.decks[n]
		local o = DeckParams.deck(n, dk, trackOf(dk), s, settings)
		d.out = o
		if not d.cur then
			d.cur = snapshot(o) -- the first targets are taken as they are, no fade in from zero
		end
	end
end

-- ── loading (ADR 0021 §3) ──

local applyTransport

-- a deck that is still in the loop's wait is never touched by a later cycle: every wait checks gen
local function loadLoop(d: Deck, gen: number)
	d.running = gen
	local assetId = d.wanted
	while assetId and d.gen == gen do
		local sound = d.sound
		local warned = false
		for attempt = 1, LoadPolicy.MAX_ATTEMPTS do
			if d.gen ~= gen then
				break
			end
			setId(sound, "")
			task.wait()
			if d.gen ~= gen then
				break
			end
			setId(sound, LoadPolicy.contentId(assetId, attempt))
			-- a preload only warms the cache; never wait on it (it can hang). The Sound, not its id string:
			-- a bare string is fetched as an image
			task.spawn(function()
				pcall(ContentProvider.PreloadAsync, ContentProvider, { sound })
			end)
			local t0 = os.clock()
			local limit = LoadPolicy.timeout(isTouch)
			while d.gen == gen and not sound.IsLoaded and os.clock() - t0 < limit do
				task.wait(0.05)
			end
			if d.gen ~= gen then
				break
			end
			if sound.IsLoaded then
				d.loaded = true
				if d.running == gen then
					d.running = nil
				end
				d.loader:RemoveNoClean("loop")
				applyTransport(d)
				return
			end
			setId(sound, "")
			if not warned then
				warned = true
				warn("[HazaDJ] deck " .. d.n .. " is still loading its track; retrying")
			end
			task.wait(LoadPolicy.backoff(attempt))
		end
		if d.gen ~= gen then
			break
		end
		-- every attempt failed: wait, then start a new cycle (never give up while the track is wanted)
		task.wait(LoadPolicy.CYCLE_DELAY)
	end
	if d.running == gen then
		d.running = nil
	end
	d.loader:RemoveNoClean("loop")
end

-- start a load loop unless one is already running for the current generation. A stale loop is
-- cancelled where it waits (it only ever waits between setting ids, so the Sound is left as is; the
-- new loop sets its own id). The gen checks stay as the second guard.
local function startLoop(d: Deck)
	if d.running ~= d.gen then
		d.loader:Add(task.spawn(loadLoop, d, d.gen), true, "loop")
	end
end

-- ── transport (ADR 0021 §4) ──

-- the record's brake has landed: the Sound is paused and restored; put the playhead where the deck is
local function landBrake(d: Deck)
	local dk = Store.sessionAtom().decks[d.n]
	if dk.playing then
		return
	end
	if d.wanted == nil then
		setId(d.sound, "")
		return
	end
	if d.loaded then
		d.sound.TimePosition = (timing(d.sound, dk, Store.now()))
	end
end

-- make the Sound match the deck state. Runs on every state change and after a load.
applyTransport = function(d: Deck)
	local sound = d.sound
	local dk = Store.sessionAtom().decks[d.n]
	local now = Store.now()
	local expected, atEnd = timing(sound, dk, now)
	local anchorMoved = dk.pos ~= d.anchorPos or dk.at ~= d.anchorAt
	d.anchorPos, d.anchorAt = dk.pos, dk.at

	if dk.playing then
		if DeckBrake.isActive(sound) then
			DeckBrake.cancel(sound)
		end
		if not d.loaded then
			return
		end
		if not sound.IsPlaying then
			if atEnd then
				return
			end
			sound.TimePosition = expected
			sound:Play()
		elseif anchorMoved and math.abs(sound.TimePosition - expected) > 0.1 then
			sound.TimePosition = expected -- an explicit jump (seek, cue, hot cue, scratch)
		end
		return
	end

	-- stopped: a brake in effect runs the record down first, and its end lands the playhead
	local brake = brakeOf(dk, now)
	if brake and sound.IsPlaying and not DeckBrake.isActive(sound) then
		DeckBrake.stop(sound, brake, function()
			landBrake(d)
		end)
		return
	end
	if DeckBrake.isActive(sound) then
		if brake then
			return
		end
		DeckBrake.cancel(sound) -- stopped with no brake (a plain pause): stop now
	end
	if sound.IsPlaying then
		sound:Pause()
	end
	if d.loaded and math.abs(sound.TimePosition - expected) > 0.01 then
		sound.TimePosition = expected
	end
end

-- wanted changed, or the state moved: the single place a deck is re-synced
local function sync(d: Deck)
	local dk = Store.sessionAtom().decks[d.n]
	local want = wantedOf(dk)
	if want ~= d.wanted then
		d.wanted = want
		d.gen += 1
		d.loaded = false
		if want then
			startLoop(d)
		elseif not (brakeOf(dk, Store.now()) and d.sound.IsPlaying) then
			-- an ejected deck still coasting down keeps its Sound until the brake lands
			setId(d.sound, "")
		end
	end
	applyTransport(d)
end

-- the watchdog (ADR 0021 §5): recover what the loop and the transport may have missed
local function watch(d: Deck)
	if d.wanted == nil then
		return
	end
	local sound = d.sound
	if not d.loaded then
		startLoop(d)
		return
	end
	local id = string.match(sound.SoundId, "(%d+)$")
	if not id or tonumber(id) ~= d.wanted then
		d.loaded = false
		startLoop(d)
		return
	end
	local dk = Store.sessionAtom().decks[d.n]
	if not dk.playing or DeckBrake.isActive(sound) then
		return
	end
	local expected, atEnd = timing(sound, dk, Store.now())
	if not sound.IsPlaying then
		if not atEnd then
			sound.TimePosition = expected
			sound:Play()
		end
	elseif DeckClock.drifted(sound.TimePosition, expected) then
		sound.TimePosition = expected
	end
end

-- ── per-frame: eased targets (continuous) and direct values (discrete) ──

-- snaps once close, so a settled value stops being rewritten every frame
local function ease(cur: number, target: number, alpha: number): number
	local v = cur + (target - cur) * alpha
	return if math.abs(target - v) < 1e-3 then target else v
end

local function paintMaster(alpha: number, now: number)
	local m = masterOut
	if not m then
		return
	end
	local fade = 1
	local f = Store.sessionAtom().fade
	if f then
		fade = 1 - math.clamp((now - f.at) / f.dur, 0, 1)
	end
	local target = m.volume * fade
	if masterCur == nil then
		masterCur = target
	else
		masterCur = ease(masterCur, target, alpha)
	end
	setIf(master, "Volume", masterCur)
	setIf(limiter, "Enabled", m.limiterEnabled)
	setIf(limiter, "Threshold", m.threshold)
	setIf(limiter, "Ratio", m.ratio)
	setIf(limiter, "GainMakeup", m.gainMakeup)
	setIf(limiter, "Attack", m.attack)
	setIf(limiter, "Release", m.release)
end

local function paintDeck(d: Deck, alpha: number)
	local o = d.out
	local c = d.cur
	if not o or not c then
		return
	end
	c.volume = ease(c.volume, o.volume, alpha)
	c.high = ease(c.high, o.high, alpha)
	c.mid = ease(c.mid, o.mid, alpha)
	c.low = ease(c.low, o.low, alpha)
	c.echo = ease(c.echo, o.echoWet, alpha)
	c.reverb = ease(c.reverb, o.reverbWet, alpha)
	c.flange = ease(c.flange, o.flangeMix, alpha)

	local sound = d.sound
	-- a brake owns the Sound's speed and volume while it runs; they are written again once it lands
	if not DeckBrake.isActive(sound) then
		setIf(sound, "Volume", c.volume)
		setIf(sound, "PlaybackSpeed", o.speed)
	end
	setIf(d.eq, "HighGain", c.high)
	setIf(d.eq, "MidGain", c.mid)
	setIf(d.eq, "LowGain", c.low)
	setIf(d.shift, "Enabled", o.shiftEnabled)
	setIf(d.shift, "Octave", o.octave)
	setIf(d.echo, "Enabled", o.echoEnabled)
	setIf(d.echo, "Delay", o.echoDelay)
	setIf(d.echo, "WetLevel", c.echo)
	setIf(d.reverb, "Enabled", o.reverbEnabled)
	setIf(d.reverb, "WetLevel", c.reverb)
	setIf(d.flange, "Enabled", o.flangeEnabled)
	setIf(d.flange, "Mix", c.flange)
end

-- ── pad sounds (ADR 0021 §5): each client plays its own one-shot ──

local function playPad(assetId: number, volume: number, nearBooth: boolean)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. string.format("%d", assetId)
	s.Volume = volume
	local booth = if nearBooth then CollectionService:GetTagged("HazaDJ_Booth")[1] else nil
	if booth and booth:IsA("BasePart") then
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 15
		s.RollOffMaxDistance = 80
		s.Parent = booth
	else
		s.Parent = SoundService
	end
	-- a one-shot: whichever comes first (it ends, or the time cap) cleans the Sound and the other
	local shot = Janitor.new()
	shot:Add(s, "Destroy")
	shot:Add(
		s.Ended:Once(function()
			shot:Destroy()
		end),
		"Disconnect"
	)
	shot:Add(
		task.delay(PAD_MAX_TIME, function()
			shot:Destroy()
		end),
		true
	)
	s:Play()
end

-- ── start ──

local function build2D()
	folder = Instance.new("Folder")
	folder.Name = "HazaDJ_Audio"
	folder.Parent = SoundService
	master = Instance.new("SoundGroup")
	master.Name = "HazaDJ_Master"
	master.Parent = folder
	limiter = Instance.new("CompressorSoundEffect")
	limiter.Name = "HazaDJ_Limiter"
	limiter.Parent = master
end

function Audio.start()
	if started then
		return
	end
	started = true
	isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	build2D()
	decks[1] = build(1)
	decks[2] = build(2)

	-- targets and transport follow the state; reading the atoms subscribes this effect to them
	-- pcall: an error here must not break the subscription (the watchdog would be the only path left)
	Charm.effect(function()
		local ok, err = pcall(function()
			retarget()
			for n = 1, 2 do
				sync(decks[n])
			end
		end)
		if not ok then
			warn("[HazaDJ] deck sync: " .. tostring(err))
		end
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		local alpha = 1 - math.exp(-dt / TAU)
		local now = Store.now()
		paintMaster(alpha, now)
		for n = 1, 2 do
			paintDeck(decks[n], alpha)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(LoadPolicy.WATCHDOG_INTERVAL)
			for n = 1, 2 do
				local ok, err = pcall(watch, decks[n])
				if not ok then
					warn("[HazaDJ] deck watchdog: " .. tostring(err))
				end
			end
		end
	end)

	Net.PadSfx.On(playPad)
end

return Audio
