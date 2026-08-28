--!strict
-- GroupMotionPolicy — pure decision table for "may this UI target be scale-animated?".
--
-- Why this exists (ADR 0005): a CanvasGroup is rasterized to a GPU texture sized by its
-- AbsoluteSize. Roblox docs: "It's recommended to use CanvasGroup with static sizes,
-- otherwise a new texture would need to be created to accommodate new sizes" and
-- "when exceeding the memory cap, CanvasGroup will render as a blank texture". A UIScale
-- tween on a group — or on ANY ancestor of a group — changes that size every frame, so
-- each frame reallocates the texture; under memory pressure that is the blank/flicker
-- buyers report. This module decides, from a class-shape descriptor, whether the scale
-- motion is kept ("scale") or collapsed to a size-stable variant ("stable").
--
-- Pure: no Roblox globals, so it is unit-testable headless. The Roblox-facing wrapper that
-- builds the descriptor from an Instance lives in Client/Utils/GroupMotion.luau.

local GroupMotionPolicy = {}

export type TargetShape = {
	isCanvasGroup: boolean,
	hasCanvasGroupAncestor: boolean,
	hasCanvasGroupDescendant: boolean,
}

export type Mode = "scale" | "stable"

-- Accepts Config.UIMotion (or nil). Only CANVAS_GROUP_SIZE_STABLE is read.
export type MotionConfig = { [string]: any }?

--- Safe default is ON: an older engine Config.luau (pre-fill-forward) or a junk value
--- must never silently re-enable the per-frame reallocation.
function GroupMotionPolicy.isSizeStableEnabled(config: MotionConfig): boolean
	if type(config) ~= "table" then
		return true
	end
	local flag = (config :: { [string]: any }).CANVAS_GROUP_SIZE_STABLE
	if flag == false then
		return false
	end
	return true
end

--- Whether the shape rasterizes through a CanvasGroup anywhere on its axis.
function GroupMotionPolicy.touchesGroup(shape: TargetShape): boolean
	return shape.isCanvasGroup or shape.hasCanvasGroupAncestor or shape.hasCanvasGroupDescendant
end

function GroupMotionPolicy.mode(shape: TargetShape, config: MotionConfig): Mode
	if not GroupMotionPolicy.isSizeStableEnabled(config) then
		return "scale"
	end
	if GroupMotionPolicy.touchesGroup(shape) then
		return "stable"
	end
	return "scale"
end

--- Resolve the UIScale value an animation should drive toward. In "stable" mode every
--- keyframe collapses to `resting` (default 1) so the group's AbsoluteSize never moves;
--- in "scale" mode the desired value passes through untouched.
function GroupMotionPolicy.scaleTarget(shape: TargetShape, config: MotionConfig, desired: number, resting: number?): number
	if GroupMotionPolicy.mode(shape, config) == "stable" then
		return resting or 1
	end
	return desired
end

return GroupMotionPolicy
