--!strict
-- Deck and master parameters as plain numbers: the maths the server's applyDeck / applyMaster used
-- to do inline. Pure, so each client can apply them to its own Sounds (ADR 0021).
local DeckClock = require(script.Parent.DeckClock)
local Mix = require(script.Parent.Mix)
local Types = require(script.Parent.Types)

local DeckParams = {}

export type DeckOut = {
	volume: number,
	speed: number, -- PlaybackSpeed, clamped 0.2 .. 5
	shiftEnabled: boolean,
	octave: number, -- 1 when the shift is off
	high: number,
	mid: number,
	low: number,
	echoEnabled: boolean,
	echoWet: number,
	echoDelay: number,
	reverbEnabled: boolean,
	reverbWet: number,
	flangeEnabled: boolean,
	flangeMix: number,
}

export type MasterOut = {
	volume: number,
	limiterEnabled: boolean,
	threshold: number,
	ratio: number,
	gainMakeup: number,
	attack: number,
	release: number,
}

-- fixed settings of the effect chain, applied once when a Sound's chain is built
DeckParams.FX_DEFAULTS = table.freeze({
	echo = { DryLevel = 0, Feedback = 0.35 },
	reverb = { DryLevel = 0, DecayTime = 1.6 },
	flange = { Depth = 0.45, Rate = 0.6 },
	-- effect order on the Sound: the highest runs first
	priority = { eq = 5, echo = 4, reverb = 3, flange = 2, shift = 1 },
})

-- deck n (1 or 2): crossfader gain, track gain, key lock and the effect values
function DeckParams.deck(
	n: number,
	deck: Types.Deck,
	track: Types.Track?,
	session: Types.Session,
	settings: Types.Settings
): DeckOut
	local a, b = Mix.crossfade(session.xfader, session.curve)
	local x = if n == 1 then a else b
	local gain = if track then Mix.dbToGain(track.gain) else 1
	local volume = math.clamp(deck.vol * x * gain, 0, 10)
	local rate = DeckClock.rate(deck, track)
	local speed = math.clamp(rate, 0.2, 5)
	-- key lock: shift back by the tempo change so the key stays (PitchShift spans 0.5 .. 2)
	local keep = settings.keyLock and math.abs(deck.pitch) > 0.0005
	local octave = if keep then math.clamp(1 / (1 + deck.pitch), 0.5, 2) else 1
	local high, mid, low = Mix.eqGains(deck.eq, deck.filter)
	local echo, reverb, flange = deck.fx[1], deck.fx[2], deck.fx[3]
	local bpm = if track then track.bpm else nil
	local echoDelay = if bpm then math.clamp(60 / (bpm * rate) * 0.75, 0.05, 1) else 0.375
	return {
		volume = volume,
		speed = speed,
		shiftEnabled = keep,
		octave = octave,
		high = high,
		mid = mid,
		low = low,
		echoEnabled = echo > 0.001,
		echoWet = -30 + echo * 30,
		echoDelay = echoDelay,
		reverbEnabled = reverb > 0.001,
		reverbWet = -40 + reverb * 40,
		flangeEnabled = flange > 0.001,
		flangeMix = flange,
	}
end

-- the master bus: master fader times the volume setting, and the limiter (or the gentler normalize)
function DeckParams.master(session: Types.Session, settings: Types.Settings): MasterOut
	local volume = math.clamp(session.master * settings.volume / 100, 0, 10)
	local enabled = settings.limiter or settings.normalize
	if settings.normalize then
		return {
			volume = volume,
			limiterEnabled = enabled,
			threshold = -18,
			ratio = 4,
			gainMakeup = 6,
			attack = 0.01,
			release = 0.2,
		}
	end
	return {
		volume = volume,
		limiterEnabled = enabled,
		threshold = -1,
		ratio = 20,
		gainMakeup = 0,
		attack = 0.003,
		release = 0.1,
	}
end

return DeckParams
