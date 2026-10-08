--!strict
-- Onboarding launcher (CONTEXT.md "Onboarding"). Main.client registers the Settings controller and
-- menu once they exist, and queues `autoOpen` as a post-gameplay boot task. With
-- `Config.Onboarding.ENABLED` on, the modal opens once per session after the loading screen is
-- done. `open()` shows it on demand whatever the flag says (Studio tests: require this module from
-- a client eval and call `.open()`).
--
-- Picks are applied for real through SettingsController's seams, the same paths the Settings tab
-- (accent, graphicsPreset) and the Profile tab (relationshipMode) take.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local LoadingScreenUI = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.UI.LoadingScreenUI)

type ILogger = Types.ILogger

export type Deps = {
	logger: ILogger,
	-- The object createSettingsController returned (needs applySetting / applyProfileField).
	settingsController: any,
	-- The menu UI (MenuShellUI), used to build the Settings tab rows the previews clone.
	menuUI: any,
}

-- Seconds after the loading screen is done before the modal appears, and the longest wait for it.
local OPEN_DELAY = 1.5
local LOADING_WAIT_TIMEOUT = 60

-- The modal's labels versus the stored values (profile "Fun", preset "Balanced").
local STATUS_TO_KEY: { [string]: string } = { Single = "Single", Taken = "Taken", ["For Fun"] = "Fun" }
local KEY_TO_STATUS: { [string]: string } = { Single = "Single", Taken = "Taken", Fun = "For Fun" }
local QUALITY_TO_PRESET: { [string]: string } = { Low = "Low", Balance = "Balanced", High = "High" }
local PRESET_TO_QUALITY: { [string]: string } = { Low = "Low", Balanced = "Balance", High = "High" }

local deps: Deps? = nil
local session: any = nil
local opening = false
local autoOpened = false
local placeNameCache: string? = nil
local missingLogged = false

local OnboardingController = {}

function OnboardingController.register(newDeps: Deps)
	deps = newDeps
end

local function resolvePlaceName(): string
	if placeNameCache then
		return placeNameCache
	end
	local name = game.Name
	pcall(function()
		name = MarketplaceService:GetProductInfo(game.PlaceId).Name
	end)
	placeNameCache = name
	return name
end

function OnboardingController.isOpen(): boolean
	return session ~= nil or opening
end

-- Shows the modal now. Returns false when it is already open, not registered yet, or the place
-- lacks the design pieces it is built from (logged once).
function OnboardingController.open(): boolean
	local d = deps
	if d == nil or session ~= nil or opening then
		return false
	end
	local sc = d.settingsController
	if type(sc) ~= "table" or type(sc.applySetting) ~= "function" or type(sc.applyProfileField) ~= "function" then
		-- SettingsController soft-disabled itself (its remotes never arrived): nothing to apply to.
		return false
	end
	opening = true
	-- The previews clone Settings rows, which the menu builds lazily on first open.
	pcall(function()
		d.menuUI:ensureTabBuilt("settings")
	end)
	local placeName = resolvePlaceName()
	local status = KEY_TO_STATUS[tostring(sc:getProfileField("relationshipMode"))] or "Single"
	local quality = PRESET_TO_QUALITY[tostring(sc:getSetting("graphicsPreset"))] or "Balance"
	local OnboardingUI = require(script.Parent.Parent.UI.Onboarding.OnboardingUI)
	local ran, opened, missing = pcall(OnboardingUI.open, {
		apply = {
			theme = function(id)
				sc:applySetting("accent", id)
			end,
			status = function(label)
				local key = STATUS_TO_KEY[label]
				if key then
					sc:applyProfileField("relationshipMode", key)
				end
			end,
			quality = function(name)
				local preset = QUALITY_TO_PRESET[name]
				if preset then
					sc:applySetting("graphicsPreset", preset)
				end
			end,
			dismiss = function(dismissed)
				sc:applySetting("onboardingDismissed", dismissed)
			end,
			currentStatus = status,
			currentQuality = quality,
		},
		placeName = placeName,
		onClosed = function()
			session = nil
		end,
	})
	opening = false
	if not ran then
		d.logger:error("Onboarding failed to open", { err = tostring(opened) })
		return false
	end
	if not opened then
		if not missingLogged then
			missingLogged = true
			d.logger:warn("Onboarding not opened, design piece missing", { missing = missing })
		end
		return false
	end
	session = opened
	return true
end

local function waitForLoadingScreen()
	local deadline = os.clock() + LOADING_WAIT_TIMEOUT
	while os.clock() < deadline do
		local ui: any = LoadingScreenUI.get()
		if ui == nil or (ui:isFinished() and not ui:isBlockingGameplay()) then
			return
		end
		task.wait(0.25)
	end
end

-- Post-gameplay boot task: once per session, only with the flag on. Returns at once; the wait for
-- the loading screen (and its character intro) runs on its own thread so the boot queue is free.
function OnboardingController.autoOpen()
	if Config.Onboarding.ENABLED ~= true or autoOpened then
		return
	end
	autoOpened = true
	task.spawn(function()
		waitForLoadingScreen()
		task.wait(OPEN_DELAY)
		if Players.LocalPlayer.Parent == nil then
			return
		end
		local d = deps
		if d and d.settingsController and d.settingsController:getSetting("onboardingDismissed") == true then
			return
		end
		OnboardingController.open()
	end)
end

return OnboardingController
