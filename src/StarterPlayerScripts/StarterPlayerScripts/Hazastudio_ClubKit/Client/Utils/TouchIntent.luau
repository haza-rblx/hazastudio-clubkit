--!strict
-- Client/Utils/TouchIntent.luau
-- Tap-vs-scroll and slider-vs-scroll decisions for touch input inside a ScrollingFrame.
-- A control that acts on touch-down steals the finger from the scroll; these helpers wait for
-- the finger to show its intent first (same idea as Android touch slop / iOS delaysContentTouches).
--
--   TouchIntent.resolveAxis(delta, "x")  -- slider: "pending" | "slider" | "scroll"
--   TouchIntent.isTap(delta, elapsed)    -- button: did the finger stay put, briefly?
local TouchIntent = {}

-- Finger travel (px) before intent is decided. Below this a touch is still a possible tap.
TouchIntent.SLOP = 10
-- Longer than this is a press-and-hold, not a tap.
TouchIntent.TAP_MAX_SECONDS = 0.5

export type Axis = "x" | "y"
export type Verdict = "pending" | "slider" | "scroll"

-- `axis` is the direction the slider moves along. Travel mostly along it = the player is
-- dragging the slider; mostly across it = the player is scrolling the list.
function TouchIntent.resolveAxis(delta: Vector2, axis: Axis): Verdict
	local along = math.abs(if axis == "x" then delta.X else delta.Y)
	local across = math.abs(if axis == "x" then delta.Y else delta.X)
	if math.max(along, across) < TouchIntent.SLOP then
		return "pending"
	end
	if along > across then
		return "slider"
	end
	return "scroll"
end

function TouchIntent.isTap(delta: Vector2, elapsed: number): boolean
	return delta.Magnitude <= TouchIntent.SLOP and elapsed <= TouchIntent.TAP_MAX_SECONDS
end

return TouchIntent
