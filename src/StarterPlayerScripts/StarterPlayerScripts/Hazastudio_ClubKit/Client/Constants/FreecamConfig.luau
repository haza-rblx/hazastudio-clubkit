--!strict
--[[
	═══════════════════════════════════════════════════════════════════
	FREECAM CONFIG (Desktop — Shift+P)
	═══════════════════════════════════════════════════════════════════
	Freecam cinematic tuning. Edit numbers in the `Values` table below,
	then test in-game (rejoin / restart client in Studio).

	All values are clamped to safe ranges when used by the controller.
	Do not change `Ranges` unless you understand the impact.

	Toggle: Shift + P (configured in FreecamController, not this file)
	Mobile: separate MobileFreecamController.
	═══════════════════════════════════════════════════════════════════
]]

export type FreecamConfigValues = {
	USE_CUSTOM_FREECAM: boolean,
	BASE_SPEED: number,
	SPEED_MIN: number,
	SPEED_MAX: number,
	SCROLL_SPEED_ADJUST_ENABLED: boolean,
	SCROLL_FACTOR: number,
	LOOK_SENSITIVITY: number,
	TOUCH_SENSITIVITY: number,
	PITCH_LIMIT_DEGREES: number,
	ROT_STIFFNESS: number,
	SPRING_STIFFNESS: number,
	FAST_MULT: number,
	SLOW_MULT: number,
	ROLL_SPEED_DEG_PER_SEC: number,
	ROLL_SLOW_MULT: number,
	ROLL_RESET_WINDOW: number,
	FOV_DEFAULT: number,
	FOV_MIN: number,
	FOV_MAX: number,
	FOV_STEP: number,
	FOV_LERP: number,
	BOB_ENABLED: boolean,
	BOB_FREQ: number,
	BOB_Y_AMP: number,
	BOB_ROLL: number,
}

export type ResolvedFreecamConfig = {
	USE_CUSTOM_FREECAM: boolean,
	BASE_SPEED: number,
	SPEED_MIN: number,
	SPEED_MAX: number,
	SCROLL_SPEED_ADJUST_ENABLED: boolean,
	SCROLL_FACTOR: number,
	LOOK_SENSITIVITY: number,
	TOUCH_SENSITIVITY: number,
	PITCH_LIMIT: number,
	ROT_STIFFNESS: number,
	ROT_DAMPING: number,
	SPRING_STIFFNESS: number,
	SPRING_DAMPING: number,
	FAST_MULT: number,
	SLOW_MULT: number,
	ROLL_SPEED: number,
	ROLL_SLOW_MULT: number,
	ROLL_RESET_WINDOW: number,
	FOV_DEFAULT: number,
	FOV_MIN: number,
	FOV_MAX: number,
	FOV_STEP: number,
	FOV_LERP: number,
	BOB_ENABLED: boolean,
	BOB_FREQ: number,
	BOB_Y_AMP: number,
	BOB_ROLL: number,
}

local function clampNumber(value: any, fallback: number, minValue: number, maxValue: number): number
	if type(value) ~= "number" or value ~= value then
		return fallback
	end
	return math.clamp(value, minValue, maxValue)
end

local function clampBool(value: any, fallback: boolean): boolean
	if type(value) == "boolean" then
		return value
	end
	return fallback
end

--[[
	── Values ────────────────────────────────────────────────────────
	Edit only this section for day-to-day tuning.
]]
local Values: FreecamConfigValues = {
	-- false = Shift+P uses Roblox developer camera (not custom freecam)
	USE_CUSTOM_FREECAM = true,

	-- Base WASD/QE/Space movement speed (studs/sec, before Ctrl/Shift modifiers)
	BASE_SPEED = 30,

	-- Speed multiplier bounds when scroll speed adjust is ON (rarely used)
	SPEED_MIN = 0.1,
	SPEED_MAX = 12,

	-- true = scroll wheel changes speed while movement keys held; false = off
	SCROLL_SPEED_ADJUST_ENABLED = false,

	-- Speed change per scroll tick (exponential), range 0.05–0.5
	SCROLL_FACTOR = 0.22,

	-- Mouse look sensitivity (higher = faster), range 0.0005–0.01
	LOOK_SENSITIVITY = 0.0025,

	-- Touch trackpad/tablet look sensitivity, range 0.001–0.02
	TOUCH_SENSITIVITY = 0.0038,

	-- Pitch up/down limit (degrees), range 45–89
	PITCH_LIMIT_DEGREES = 88,

	-- Camera rotation stiffness (spring), range 10–120 — higher = more responsive
	ROT_STIFFNESS = 60,

	-- Movement acceleration stiffness (spring velocity), range 5–80
	SPRING_STIFFNESS = 25,

	-- Ctrl = fast (BASE_SPEED multiplier), range 1.5–8
	FAST_MULT = 3.0,

	-- Shift = slow/precise, range 0.05–0.5
	SLOW_MULT = 0.15,

	-- Camera roll while Z/C held (deg/sec), range 15–180
	ROLL_SPEED_DEG_PER_SEC = 75,

	-- Roll while Shift held (% of ROLL_SPEED), range 0.1–1
	ROLL_SLOW_MULT = 0.30,

	-- Double-tap Z window for roll reset (seconds), range 0.15–0.8
	ROLL_RESET_WINDOW = 0.35,

	-- FOV when entering freecam (degrees), range 40–90
	FOV_DEFAULT = 70,

	-- Scroll zoom bounds (degrees)
	FOV_MIN = 5,
	FOV_MAX = 130,

	-- FOV change per scroll tick, range 1–15
	FOV_STEP = 5,

	-- FOV glide speed toward target; low = smooth, high = snappy, range 0.5–12
	FOV_LERP = 3,

	-- Camera bob while moving (may feel wobbly); default false
	BOB_ENABLED = false,

	-- Frekuensi bob (Hz), range 0.5–4
	BOB_FREQ = 1.6,

	-- Amplitudo bob vertikal (studs), range 0–0.5
	BOB_Y_AMP = 0.10,

	-- Amplitudo bob roll (radian kecil), range 0–0.02
	BOB_ROLL = 0.005,
}

local Ranges = {
	BASE_SPEED = { 1, 200 },
	SPEED_MIN = { 0.05, 1 },
	SPEED_MAX = { 2, 24 },
	SCROLL_FACTOR = { 0.05, 0.5 },
	LOOK_SENSITIVITY = { 0.0005, 0.01 },
	TOUCH_SENSITIVITY = { 0.001, 0.02 },
	PITCH_LIMIT_DEGREES = { 45, 89 },
	ROT_STIFFNESS = { 10, 120 },
	SPRING_STIFFNESS = { 5, 80 },
	FAST_MULT = { 1.5, 8 },
	SLOW_MULT = { 0.05, 0.5 },
	ROLL_SPEED_DEG_PER_SEC = { 15, 180 },
	ROLL_SLOW_MULT = { 0.1, 1 },
	ROLL_RESET_WINDOW = { 0.15, 0.8 },
	FOV_DEFAULT = { 40, 90 },
	FOV_MIN = { 1, 89 },
	FOV_MAX = { 71, 140 },
	FOV_STEP = { 1, 15 },
	FOV_LERP = { 0.5, 12 },
	BOB_FREQ = { 0.5, 4 },
	BOB_Y_AMP = { 0, 0.5 },
	BOB_ROLL = { 0, 0.02 },
}

local function resolve(overrides: FreecamConfigValues?): ResolvedFreecamConfig
	local raw = overrides or Values
	local v = Values
	if overrides then
		v = overrides
	end

	local rotStiffness = clampNumber(v.ROT_STIFFNESS, Values.ROT_STIFFNESS, Ranges.ROT_STIFFNESS[1], Ranges.ROT_STIFFNESS[2])
	local springStiffness =
		clampNumber(v.SPRING_STIFFNESS, Values.SPRING_STIFFNESS, Ranges.SPRING_STIFFNESS[1], Ranges.SPRING_STIFFNESS[2])

	local fovMin = clampNumber(v.FOV_MIN, Values.FOV_MIN, Ranges.FOV_MIN[1], Ranges.FOV_MIN[2])
	local fovMax = clampNumber(v.FOV_MAX, Values.FOV_MAX, Ranges.FOV_MAX[1], Ranges.FOV_MAX[2])
	if fovMin > fovMax then
		fovMin, fovMax = fovMax, fovMin
	end

	local fovDefault = clampNumber(v.FOV_DEFAULT, Values.FOV_DEFAULT, Ranges.FOV_DEFAULT[1], Ranges.FOV_DEFAULT[2])
	fovDefault = math.clamp(fovDefault, fovMin, fovMax)

	return {
		USE_CUSTOM_FREECAM = clampBool(v.USE_CUSTOM_FREECAM, Values.USE_CUSTOM_FREECAM),
		BASE_SPEED = clampNumber(v.BASE_SPEED, Values.BASE_SPEED, Ranges.BASE_SPEED[1], Ranges.BASE_SPEED[2]),
		SPEED_MIN = clampNumber(v.SPEED_MIN, Values.SPEED_MIN, Ranges.SPEED_MIN[1], Ranges.SPEED_MIN[2]),
		SPEED_MAX = clampNumber(v.SPEED_MAX, Values.SPEED_MAX, Ranges.SPEED_MAX[1], Ranges.SPEED_MAX[2]),
		SCROLL_SPEED_ADJUST_ENABLED = clampBool(v.SCROLL_SPEED_ADJUST_ENABLED, Values.SCROLL_SPEED_ADJUST_ENABLED),
		SCROLL_FACTOR = clampNumber(v.SCROLL_FACTOR, Values.SCROLL_FACTOR, Ranges.SCROLL_FACTOR[1], Ranges.SCROLL_FACTOR[2]),
		LOOK_SENSITIVITY =
			clampNumber(v.LOOK_SENSITIVITY, Values.LOOK_SENSITIVITY, Ranges.LOOK_SENSITIVITY[1], Ranges.LOOK_SENSITIVITY[2]),
		TOUCH_SENSITIVITY = clampNumber(
			v.TOUCH_SENSITIVITY,
			Values.TOUCH_SENSITIVITY,
			Ranges.TOUCH_SENSITIVITY[1],
			Ranges.TOUCH_SENSITIVITY[2]
		),
		PITCH_LIMIT = math.rad(
			clampNumber(
				v.PITCH_LIMIT_DEGREES,
				Values.PITCH_LIMIT_DEGREES,
				Ranges.PITCH_LIMIT_DEGREES[1],
				Ranges.PITCH_LIMIT_DEGREES[2]
			)
		),
		ROT_STIFFNESS = rotStiffness,
		ROT_DAMPING = 2 * math.sqrt(rotStiffness),
		SPRING_STIFFNESS = springStiffness,
		SPRING_DAMPING = 2 * math.sqrt(springStiffness),
		FAST_MULT = clampNumber(v.FAST_MULT, Values.FAST_MULT, Ranges.FAST_MULT[1], Ranges.FAST_MULT[2]),
		SLOW_MULT = clampNumber(v.SLOW_MULT, Values.SLOW_MULT, Ranges.SLOW_MULT[1], Ranges.SLOW_MULT[2]),
		ROLL_SPEED = math.rad(
			clampNumber(
				v.ROLL_SPEED_DEG_PER_SEC,
				Values.ROLL_SPEED_DEG_PER_SEC,
				Ranges.ROLL_SPEED_DEG_PER_SEC[1],
				Ranges.ROLL_SPEED_DEG_PER_SEC[2]
			)
		),
		ROLL_SLOW_MULT =
			clampNumber(v.ROLL_SLOW_MULT, Values.ROLL_SLOW_MULT, Ranges.ROLL_SLOW_MULT[1], Ranges.ROLL_SLOW_MULT[2]),
		ROLL_RESET_WINDOW = clampNumber(
			v.ROLL_RESET_WINDOW,
			Values.ROLL_RESET_WINDOW,
			Ranges.ROLL_RESET_WINDOW[1],
			Ranges.ROLL_RESET_WINDOW[2]
		),
		FOV_DEFAULT = fovDefault,
		FOV_MIN = fovMin,
		FOV_MAX = fovMax,
		FOV_STEP = clampNumber(v.FOV_STEP, Values.FOV_STEP, Ranges.FOV_STEP[1], Ranges.FOV_STEP[2]),
		FOV_LERP = clampNumber(v.FOV_LERP, Values.FOV_LERP, Ranges.FOV_LERP[1], Ranges.FOV_LERP[2]),
		BOB_ENABLED = clampBool(v.BOB_ENABLED, Values.BOB_ENABLED),
		BOB_FREQ = clampNumber(v.BOB_FREQ, Values.BOB_FREQ, Ranges.BOB_FREQ[1], Ranges.BOB_FREQ[2]),
		BOB_Y_AMP = clampNumber(v.BOB_Y_AMP, Values.BOB_Y_AMP, Ranges.BOB_Y_AMP[1], Ranges.BOB_Y_AMP[2]),
		BOB_ROLL = clampNumber(v.BOB_ROLL, Values.BOB_ROLL, Ranges.BOB_ROLL[1], Ranges.BOB_ROLL[2]),
	}
end

return {
	Values = Values,
	Ranges = Ranges,
	resolve = resolve,
	get = function(): ResolvedFreecamConfig
		return resolve(nil)
	end,
}
