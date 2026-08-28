--!strict
-- GroupMotion — Roblox-facing adapter over Shared/UI/GroupMotionPolicy (ADR 0005).
-- Builds the class-shape descriptor for a GuiObject and answers "scale or size-stable?".
-- Every scale-animation site in the client (AnimationHelper, toast controllers, overhead
-- pop) routes its UIScale keyframes through `scaleTarget` so CanvasGroup textures keep a
-- static size. Keep this module free of tween logic — it only decides.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local GroupMotionPolicy = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.UI.GroupMotionPolicy)

export type TargetShape = GroupMotionPolicy.TargetShape
export type Mode = GroupMotionPolicy.Mode

local GroupMotion = {}

local function motionConfig(): GroupMotionPolicy.MotionConfig
	local uiMotion = (Config :: any).UIMotion
	if type(uiMotion) == "table" then
		return uiMotion
	end
	return nil
end

local function hasGroupAncestor(inst: Instance): boolean
	local parent = inst.Parent
	while parent and not parent:IsA("LayerCollector") do
		if parent:IsA("CanvasGroup") then
			return true
		end
		parent = parent.Parent
	end
	return false
end

--- Descriptor for the policy. Descendant walk is bounded by the target's own subtree
--- (modals are ~50–200 nodes) and runs once per open/close, not per frame.
function GroupMotion.describe(inst: Instance): TargetShape
	return {
		isCanvasGroup = inst:IsA("CanvasGroup"),
		hasCanvasGroupAncestor = hasGroupAncestor(inst),
		hasCanvasGroupDescendant = inst:FindFirstChildWhichIsA("CanvasGroup", true) ~= nil,
	}
end

function GroupMotion.mode(inst: Instance): Mode
	return GroupMotionPolicy.mode(GroupMotion.describe(inst), motionConfig())
end

function GroupMotion.isStable(inst: Instance): boolean
	return GroupMotion.mode(inst) == "stable"
end

--- UIScale value to drive toward for `inst`. Collapses to `resting` (default 1) when the
--- target rasterizes through a CanvasGroup and size-stable motion is enabled.
function GroupMotion.scaleTarget(inst: Instance, desired: number, resting: number?): number
	return GroupMotionPolicy.scaleTarget(GroupMotion.describe(inst), motionConfig(), desired, resting)
end

return GroupMotion
