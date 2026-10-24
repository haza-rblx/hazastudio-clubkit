--!strict
-- Deck brake: slows a deck's Sound down like a turntable being switched off (speed drops, treble
-- and mids roll off, optional click, hum, dust, needle and thump). It runs on this client's own copy
-- of the deck's Sound, started from the deck's state (`brake` in the server's deck, ADR 0021). When the
-- record stops, the client pauses that Sound itself, restores it, and calls onDone so the caller can
-- put the playhead where the deck says.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.HazaDJ.Shared
local DeckBrakeConfig = require(Shared.DeckBrakeConfig)

local DeckBrake = {}

type Run = {
	baseSpeed: number,
	baseVolume: number,
	eq: EqualizerSoundEffect,
	hum: Sound?,
	dust: Sound?,
	onDone: (() -> ())?,
	beat: RBXScriptConnection?,
	swap: RBXScriptConnection?,
	gone: RBXScriptConnection?,
}

local active: { [Sound]: Run } = {}

-- a layer beside the deck: looped ones are kept by the run, one-shots clean themselves up
local function sfx(sound: Sound, id: number, looped: boolean, volume: number): Sound?
	if id == 0 or volume <= 0 then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. string.format("%d", id)
	s.Looped = looped
	s.Volume = volume
	s.SoundGroup = sound.SoundGroup
	s.Parent = sound.Parent
	s:Play()
	if not looped then
		s.Ended:Once(function()
			s:Destroy()
		end)
		task.delay(10, function()
			if s.Parent then
				s:Destroy()
			end
		end)
	end
	return s
end

-- put the deck back as it was and drop everything the brake made
local function restore(sound: Sound, run: Run)
	if run.beat then
		run.beat:Disconnect()
	end
	if run.swap then
		run.swap:Disconnect()
	end
	if run.gone then
		run.gone:Disconnect()
	end
	run.eq:Destroy()
	if run.hum then
		run.hum:Destroy()
	end
	if run.dust then
		run.dust:Destroy()
	end
	sound.PlaybackSpeed = run.baseSpeed
	sound.Volume = run.baseVolume
	active[sound] = nil
end

-- the record has stopped: pause the Sound, put it back as it was, and let the caller land the playhead
local function finish(sound: Sound, run: Run, p: DeckBrakeConfig.BrakePreset)
	if run.beat then
		run.beat:Disconnect()
		run.beat = nil
	end
	if run.hum then
		run.hum:Destroy()
		run.hum = nil
	end
	if run.dust then
		run.dust:Destroy()
		run.dust = nil
	end
	sound:Pause()
	local onDone = run.onDone
	restore(sound, run)
	local assets = DeckBrakeConfig.Assets
	sfx(sound, assets.EndNeedle, false, p.needle / 100)
	sfx(sound, assets.EndThump, false, p.thump / 100)
	if onDone then
		onDone()
	end
end

local function step(sound: Sound, run: Run, p: DeckBrakeConfig.BrakePreset, t0: number)
	local t = os.clock() - t0
	local x = math.clamp(t / p.duration, 0, 1)
	local r = math.max((1 - x) ^ p.shape, 0.02)
	local wow = 2 ^ ((p.wow * 2.5 / 1200) * math.sin(2 * math.pi * 0.55 * t))
	sound.PlaybackSpeed = run.baseSpeed * r * wow
	sound.Volume = run.baseVolume * r ^ 0.7
	local d = p.damp / 100
	run.eq.HighGain = math.clamp(-60 * d * (1 - r), -80, 10)
	run.eq.MidGain = math.clamp(-12 * d * (1 - r), -80, 10)
	if run.hum then
		run.hum.PlaybackSpeed = r
		run.hum.Volume = 0.35 * p.hum / 100 * r
	end
	if run.dust then
		run.dust.Volume = 0.5 * p.dust / 100 * r
	end
	if x >= 1 then
		finish(sound, run, p)
	end
end

-- drop any brake running on this sound and restore it (no end sounds, no onDone)
function DeckBrake.cancel(sound: Sound)
	local run = active[sound]
	if run then
		restore(sound, run)
	end
end

-- true while a brake is coasting this sound down (the caller leaves its speed and volume alone)
function DeckBrake.isActive(sound: Sound): boolean
	return active[sound] ~= nil
end

-- slow the sound to a stop; config defaults to the chosen preset. No preset (or the sound is not
-- playing) means no brake: onDone runs straight away. When the brake ends, the Sound is paused.
function DeckBrake.stop(sound: Sound, config: DeckBrakeConfig.BrakePreset?, onDone: (() -> ())?)
	DeckBrake.cancel(sound)
	local p = config or DeckBrakeConfig.Presets[DeckBrakeConfig.Preset]
	if not sound.IsPlaying or not p or p.duration <= 0 then
		if onDone then
			onDone()
		end
		return
	end
	local eq = Instance.new("EqualizerSoundEffect")
	eq.Name = "HazaDJ_Brake"
	eq.Priority = 10
	eq.LowGain = 0
	eq.MidGain = 0
	eq.HighGain = 0
	eq.Parent = sound
	local assets = DeckBrakeConfig.Assets
	local run: Run = {
		baseSpeed = sound.PlaybackSpeed,
		baseVolume = sound.Volume,
		eq = eq,
		onDone = onDone,
	}
	active[sound] = run
	sfx(sound, assets.PowerClick, false, p.click / 100)
	run.hum = sfx(sound, assets.HumLoop, true, 0.35 * p.hum / 100)
	run.dust = sfx(sound, assets.DustLoop, true, 0.5 * p.dust / 100)
	local t0 = os.clock()
	run.beat = RunService.Heartbeat:Connect(function()
		step(sound, run, p, t0)
	end)
	-- a track swapped mid-brake, or a sound that goes away, ends the brake
	run.swap = sound:GetPropertyChangedSignal("SoundId"):Connect(function()
		DeckBrake.cancel(sound)
	end)
	run.gone = sound.Destroying:Connect(function()
		DeckBrake.cancel(sound)
	end)
end

return DeckBrake
