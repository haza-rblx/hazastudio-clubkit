--!strict
-- Mixer maths shared by the audio engine (server) and the readouts (client).
local Mix = {}

Mix.PITCH_RANGES = { 0.08, 0.16, 0.5 }
Mix.PITCH_LABELS = { "±8%", "±16%", "±50%" }

-- an EQ knob (0..1, 0.5 = flat) in dB: -12 .. +12, and the label under it
function Mix.eqDb(v: number): number
	return (v - 0.5) * 2 * 12
end

function Mix.eqLabel(v: number): (string, boolean)
	local x = Mix.eqDb(v)
	if math.abs(x) < 0.05 then
		return "0 dB", false
	end
	return string.format("%+.1f dB", x), true
end

-- the bipolar filter: 0.5 off, below = low-pass, above = high-pass, both in 0..100 %
function Mix.filterLabel(v: number): string
	if math.abs(v - 0.5) < 0.005 then
		return "OFF"
	elseif v < 0.5 then
		return "LPF " .. math.floor((0.5 - v) * 200 + 0.5) .. "%"
	end
	return "HPF " .. math.floor((v - 0.5) * 200 + 0.5) .. "%"
end

-- EqualizerSoundEffect gains for a deck: the three EQ bands plus the filter folded in
function Mix.eqGains(eq: { number }, filter: number): (number, number, number)
	local function band(v: number): number
		if v <= 0.001 then
			return -80 -- a kill
		end
		return Mix.eqDb(v)
	end
	local high, mid, low = band(eq[1]), band(eq[2]), band(eq[3])
	if filter < 0.5 then
		local f = (0.5 - filter) * 2 -- 0..1 low-pass depth
		high -= f * 60
		mid -= math.max(0, f - 0.4) * 50
	elseif filter > 0.5 then
		local f = (filter - 0.5) * 2 -- 0..1 high-pass depth
		low -= f * 60
		mid -= math.max(0, f - 0.4) * 50
	end
	return math.max(high, -80), math.max(mid, -80), math.max(low, -80)
end

-- crossfader 0 (A) .. 1 (B) to the two deck gains. curve 0 = smooth (constant power), 1 = cut.
function Mix.crossfade(x: number, curve: number): (number, number)
	x = math.clamp(x, 0, 1)
	-- dead zone at each end and a magnet in the middle, as in the prototype
	if x < 0.03 then
		x = 0
	elseif x > 0.97 then
		x = 1
	elseif math.abs(x - 0.5) < 0.03 then
		x = 0.5
	end
	local a = math.cos(x * math.pi / 2)
	local b = math.sin(x * math.pi / 2)
	if curve > 0 then
		-- sharpen towards a cut: both decks stay full until near the far end
		local k = 1 + curve * 12
		a = math.clamp((1 - x) * k, 0, 1) * curve + a * (1 - curve)
		b = math.clamp(x * k, 0, 1) * curve + b * (1 - curve)
	end
	return a, b
end

function Mix.curveLabel(curve: number): string
	if curve < 0.34 then
		return "Smooth"
	elseif curve < 0.67 then
		return "Linear"
	end
	return "Cut"
end

-- dB to a linear volume factor
function Mix.dbToGain(db: number): number
	return 10 ^ (db / 20)
end

-- pitch as the deck's readout: "+1.6%"
function Mix.pitchLabel(p: number): string
	return string.format("%+.1f%%", p * 100)
end

-- a jog's "2.3X": the deck's speed relative to the track's tempo
function Mix.speedLabel(p: number): string
	return string.format("%.1fX", 1 + p)
end

return Mix
