--!strict
-- Resolves the notification center ScreenGui for the four notification binders
-- (CONTEXT.md "Notification center"). `99-NotificationCenterV2` wins when present;
-- `99-NotificationCenter` is the V1 fallback. `isV2` tells a binder whether to follow the
-- designer's values (V2) or keep its frozen V1 behaviour.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

export type Resolved = {
	gui: ScreenGui,
	isV2: boolean,
}

local POLL_INTERVAL = 0.1

local NotificationCenterGui = {}

local function names(): (string, string)
	local cfg = (Config :: any).NotificationCenter or {}
	return tostring(cfg.GUI_NAME_V2 or "99-NotificationCenterV2"), tostring(cfg.GUI_NAME or "99-NotificationCenter")
end

local function prepareV2(gui: ScreenGui)
	-- A redesign left at the default DisplayOrder sits under every panel; lift it once.
	-- A value the designer chose on purpose is left alone.
	if gui.DisplayOrder == 0 then
		local order = tonumber(((Config :: any).NotificationCenter or {}).V2_DISPLAY_ORDER)
		if order then
			gui.DisplayOrder = order
		end
	end
end

--- Immediate lookup, no waiting.
function NotificationCenterGui.find(playerGui: Instance?): Resolved?
	if not playerGui then
		return nil
	end
	local v2Name, v1Name = names()
	local v2 = playerGui:FindFirstChild(v2Name)
	if v2 and v2:IsA("ScreenGui") then
		prepareV2(v2)
		return { gui = v2, isV2 = true }
	end
	local v1 = playerGui:FindFirstChild(v1Name)
	if v1 and v1:IsA("ScreenGui") then
		return { gui = v1, isV2 = false }
	end
	return nil
end

--- Waits up to `timeout` seconds for either GUI to replicate into PlayerGui.
function NotificationCenterGui.resolve(timeout: number?): Resolved?
	local player = Players.LocalPlayer
	local playerGui = player and (player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5))
	local found = NotificationCenterGui.find(playerGui)
	if found or not playerGui then
		return found
	end
	local deadline = os.clock() + math.max(tonumber(timeout) or 0, 0)
	while os.clock() < deadline do
		task.wait(POLL_INTERVAL)
		found = NotificationCenterGui.find(playerGui)
		if found then
			return found
		end
	end
	return nil
end

return NotificationCenterGui
