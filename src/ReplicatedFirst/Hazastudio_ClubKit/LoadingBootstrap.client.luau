--!strict

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local DEFAULT_BOOTSTRAP_WAIT_TIMEOUT = 30

local kitRoot = ReplicatedStorage:WaitForChild("Hazastudio_ClubKit", DEFAULT_BOOTSTRAP_WAIT_TIMEOUT)
if not kitRoot then
	warn("[LoadingBootstrap] ReplicatedStorage.Hazastudio_ClubKit not found")
	ReplicatedFirst:RemoveDefaultLoadingScreen()
	return
end

local sharedRoot = kitRoot:WaitForChild("Shared", DEFAULT_BOOTSTRAP_WAIT_TIMEOUT)
if not sharedRoot then
	warn("[LoadingBootstrap] ReplicatedStorage.Hazastudio_ClubKit.Shared not found")
	ReplicatedFirst:RemoveDefaultLoadingScreen()
	return
end

local constantsFolder = sharedRoot:WaitForChild("Constants", DEFAULT_BOOTSTRAP_WAIT_TIMEOUT)
if not constantsFolder then
	warn("[LoadingBootstrap] ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants not found")
	ReplicatedFirst:RemoveDefaultLoadingScreen()
	return
end

local configModule = constantsFolder:WaitForChild("Config", DEFAULT_BOOTSTRAP_WAIT_TIMEOUT)
if not (configModule and configModule:IsA("ModuleScript")) then
	warn("[LoadingBootstrap] ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config not found")
	ReplicatedFirst:RemoveDefaultLoadingScreen()
	return
end

local Config = require(configModule)
local LoadingConfig = Config.Loading
if Config.FeatureFlags.LoadingScreenEnabled ~= true then
	ReplicatedFirst:RemoveDefaultLoadingScreen()
	return
end
local bootstrapWaitTimeout = LoadingConfig.BOOTSTRAP_WAIT_TIMEOUT

local uiFolder = sharedRoot:WaitForChild("UI", bootstrapWaitTimeout)
if not uiFolder then
	warn("[LoadingBootstrap] ReplicatedStorage.Hazastudio_ClubKit.Shared.UI not found")
	ReplicatedFirst:RemoveDefaultLoadingScreen()
	return
end

local loadingScreenModule = uiFolder:WaitForChild("LoadingScreenUI", bootstrapWaitTimeout)
if not (loadingScreenModule and loadingScreenModule:IsA("ModuleScript")) then
	warn("[LoadingBootstrap] ReplicatedStorage.Hazastudio_ClubKit.Shared.UI.LoadingScreenUI not found")
	ReplicatedFirst:RemoveDefaultLoadingScreen()
	return
end

local LoadingScreenUI = require(loadingScreenModule)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Clone template Studio sekarang supaya loading screen muncul sebelum client bootstrap lain jalan.
local runtimeRoot = playerGui:FindFirstChild("00-LoadingScreen")
if not (runtimeRoot and runtimeRoot:IsA("ScreenGui")) then
	local template = StarterGui:WaitForChild("00-LoadingScreen", LoadingConfig.TEMPLATE_WAIT_TIMEOUT)
	if template and template:IsA("ScreenGui") then
		runtimeRoot = template:Clone()
		runtimeRoot.Parent = playerGui
		pcall(function()
			template.Parent = nil
		end)
	else
		warn("[LoadingBootstrap] StarterGui.00-LoadingScreen not found")
		ReplicatedFirst:RemoveDefaultLoadingScreen()
		return
	end
end

local ui = LoadingScreenUI.attach(runtimeRoot :: ScreenGui, {
	-- Keep the cinematic visible long enough for the intro shot.
	minimumDuration = LoadingConfig.MINIMUM_DURATION,
})
if not ui or not ui:isAvailable() then
	if ui then
		ui:destroy()
	end
	warn("[LoadingBootstrap] 00-LoadingScreen is incomplete or invalid")
	ReplicatedFirst:RemoveDefaultLoadingScreen()
	return
end

ui:hidePlayerGui(playerGui)
ui:start(player.DisplayName)
ReplicatedFirst:RemoveDefaultLoadingScreen()
