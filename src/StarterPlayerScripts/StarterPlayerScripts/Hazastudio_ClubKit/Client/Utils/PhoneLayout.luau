--!strict
-- Shared phone vs tablet/desktop layout detection (viewport + touch).

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local mpm = Config.MobilePanelManager

local PhoneLayout = {}

local function getViewportShortSide(): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 1080
	end
	local vp = camera.ViewportSize
	return math.min(vp.X, vp.Y)
end

-- Phone layout: touch + short viewport. In Studio, trust emulator viewport (not KeyboardEnabled).
function PhoneLayout.isPhoneLayout(): boolean
	if not UserInputService.TouchEnabled then
		return false
	end

	local shortSide = getViewportShortSide()
	local tabletMin = tonumber(mpm.TABLET_MIN_SHORT_SIDE) or 600

	if RunService:IsStudio() then
		return shortSide < tabletMin
	end

	if UserInputService.KeyboardEnabled and shortSide >= tabletMin then
		return false
	end

	return shortSide < tabletMin
end

function PhoneLayout.getHotbarMaxSlots(): number
	local hotbar = Config.Hotbar
	if PhoneLayout.isPhoneLayout() then
		return math.max(1, math.floor(tonumber(hotbar.MAX_SLOTS_MOBILE) or 7))
	end
	return math.max(1, math.floor(tonumber(hotbar.MAX_SLOTS) or 10))
end

return PhoneLayout
