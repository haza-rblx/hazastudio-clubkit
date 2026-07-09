--!strict
-- Hides Roblox built-in PlayerList (leaderstats column) while kit menus are open.
-- Restores the previous CoreGui state when all suppressors release.

local StarterGui = game:GetService("StarterGui")

local LeaderstatsVisibilityService = {}

local suppressDepth = 0
local savedPlayerListEnabled: boolean? = nil

local function getPlayerListEnabled(): boolean
	local ok, enabled = pcall(function()
		return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
	end)
	if ok and type(enabled) == "boolean" then
		return enabled
	end
	return true
end

local function setPlayerListEnabled(enabled: boolean)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, enabled)
	end)
end

function LeaderstatsVisibilityService.pushHidden()
	suppressDepth += 1
	if suppressDepth > 1 then
		return
	end
	savedPlayerListEnabled = getPlayerListEnabled()
	setPlayerListEnabled(false)
end

function LeaderstatsVisibilityService.popHidden()
	if suppressDepth <= 0 then
		return
	end
	suppressDepth -= 1
	if suppressDepth > 0 then
		return
	end
	local restore = savedPlayerListEnabled
	savedPlayerListEnabled = nil
	setPlayerListEnabled(if type(restore) == "boolean" then restore else true)
end

function LeaderstatsVisibilityService.isSuppressed(): boolean
	return suppressDepth > 0
end

return LeaderstatsVisibilityService
