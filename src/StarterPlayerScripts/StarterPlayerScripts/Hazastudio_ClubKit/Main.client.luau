--!strict
-- PATH: StarterPlayerScripts/Main.client.lua (LocalScript)
-- Entry point client. Wiring semua client controller di sini.
-- Hot-reload safety: semua listener di luar Lifecycle di-track ke
-- _clientConnections dan di-disconnect di script.Destroying.

local MAIN_BOOT_OWNER_KEY = "Hazastudio_ClubKit_ClientMain"
local CLIENT_MAIN_BUILD_ID = "hazastudio-clubkit-client-main-v1"
script:SetAttribute("ClientMainBuildId", CLIENT_MAIN_BUILD_ID)

local function mainHasSyncMarker(mainScript: LocalScript): boolean
	if mainScript:GetAttribute("ClientMainBuildId") == CLIENT_MAIN_BUILD_ID then
		return true
	end
	local ok, source = pcall(function()
		return mainScript.Source
	end)
	if ok and type(source) == "string" then
		return string.find(source, CLIENT_MAIN_BUILD_ID, 1, true) ~= nil
			or string.find(source, "TopMenuController.blockTopbarPlusMenu", 1, true) ~= nil
	end
	return false
end

local function mainPreferenceScore(mainScript: LocalScript): number
	local score = 0
	-- Rojo syncs the real entry point as Main.client
	if mainScript.Name == "Main.client" then
		score += 100
	end
	if mainHasSyncMarker(mainScript) then
		score += 10
	end
	return score
end

local function preferMainScript(selfScript: LocalScript, otherScript: LocalScript): LocalScript
	local selfScore = mainPreferenceScore(selfScript)
	local otherScore = mainPreferenceScore(otherScript)
	if selfScore ~= otherScore then
		return if selfScore > otherScore then selfScript else otherScript
	end
	return selfScript
end

local function claimClientMainOwnership(): boolean
	local parent = script.Parent
	if parent then
		for _, child in ipairs(parent:GetChildren()) do
			if child:IsA("LocalScript") and child ~= script and string.sub(child.Name, 1, 4) == "Main" then
				local childIsCanonical = mainHasSyncMarker(child)
				local selfIsCanonical = mainHasSyncMarker(script)
				if selfIsCanonical and not childIsCanonical then
					warn("[Main] Destroying stale duplicate Main:", child:GetFullName())
					child:Destroy()
				elseif not selfIsCanonical and childIsCanonical then
					warn("[Main] Stale Main exiting — canonical copy already running:", child:GetFullName())
					return false
				elseif childIsCanonical and selfIsCanonical then
					local preferred = preferMainScript(script, child)
					if preferred == script then
						warn("[Main] Destroying duplicate canonical Main:", child:GetFullName())
						child:Destroy()
					else
						warn("[Main] Duplicate canonical Main exiting — prefer:", preferred:GetFullName())
						return false
					end
				end
			end
		end
	end

	local existing = shared[MAIN_BOOT_OWNER_KEY]
	if existing == script then
		return true
	end
	if existing and existing:IsA("LocalScript") and existing.Parent then
		local existingIsCanonical = mainHasSyncMarker(existing)
		local selfIsCanonical = mainHasSyncMarker(script)
		if selfIsCanonical and not existingIsCanonical then
			existing:Destroy()
		elseif existing ~= script then
			if selfIsCanonical and existingIsCanonical then
				local preferred = preferMainScript(script, existing)
				if preferred == script then
					warn("[Main] Replacing duplicate canonical Main owner:", existing:GetFullName())
					existing:Destroy()
				else
					warn("[Main] Duplicate canonical Main suppressed — prefer:", preferred:GetFullName())
					return false
				end
			else
				warn(
					"[Main] Duplicate client boot suppressed — hapus LocalScript Main duplikat di StarterPlayerScripts"
				)
				return false
			end
		end
	end

	shared[MAIN_BOOT_OWNER_KEY] = script
	print("[Main] Client boot owner:", script:GetFullName(), "build:", CLIENT_MAIN_BUILD_ID)
	return true
end

if not claimClientMainOwnership() then
	return
end

local _clientConnections: { RBXScriptConnection } = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local kitRoot = ReplicatedStorage:WaitForChild("Hazastudio_ClubKit", 30)
if not kitRoot then
	warn("[Main] ReplicatedStorage.Hazastudio_ClubKit not found")
	return
end
local Shared = kitRoot:WaitForChild("Shared")
local SharedConstants = Shared:WaitForChild("Constants")
local SharedDomain = Shared:WaitForChild("Domain")
local SharedUI = Shared:WaitForChild("UI")
local Config = require(SharedConstants:WaitForChild("Config"))
local PermissionDomain = require(SharedDomain:WaitForChild("PermissionDomain"))
local LoadingScreenUI = require(SharedUI:WaitForChild("LoadingScreenUI"))

do
	local utilsFolder = Shared:FindFirstChild("Utils")
	local brandLogoModule = utilsFolder and utilsFolder:FindFirstChild("BrandLogoApplier")
	if brandLogoModule and brandLogoModule:IsA("ModuleScript") then
		local ok, BrandLogoApplier = pcall(require, brandLogoModule)
		if ok and BrandLogoApplier then
			local function applyBrandLogos(root: Instance)
				BrandLogoApplier.applyToInstance(root, Config)
				table.insert(_clientConnections, BrandLogoApplier.watch(root, Config))
			end
			applyBrandLogos(StarterGui)
			task.spawn(function()
				local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
				applyBrandLogos(playerGui)
			end)
		end
	end
end

type LoadingConfigType = {
	BOOTSTRAP_WAIT_TIMEOUT: number,
	CONTROLLER_WAIT_TIMEOUT: number,
	CONTROLLER_POLL_INTERVAL: number,
	MINIMUM_DURATION: number,
	FALLBACK_FINISH_DELAY: number,
	INITIAL_PROGRESS: number,
	PROGRESS_PULSE_DURATION: number,
	PROGRESS_PULSE_INTERVAL: number,
}
local LoadingConfig = (Config :: any).Loading :: LoadingConfigType
local ClientBootConfig = (Config :: any).ClientBoot or {}
local LOADING_SCREEN_ENABLED = Config.FeatureFlags.LoadingScreenEnabled == true
local ClientBootScheduler = require(script.Parent.Client.Services.ClientBootScheduler)
local clientBootScheduler = ClientBootScheduler.create({
	maxConcurrentInteractive = ClientBootConfig.MAX_CONCURRENT_INTERACTIVE,
	maxConcurrentPostGameplay = ClientBootConfig.MAX_CONCURRENT_POST_GAMEPLAY
		or ClientBootConfig.MAX_CONCURRENT_DEFERRED,
})
local PhoneLayout = require(script.Parent.Client.Utils.PhoneLayout)
local AvatarPrewarmShared = require(script.Parent.Client.Utils.AvatarPrewarmShared)
local syncDanceController: any = nil
local syncLeadTopbarController: any = nil
local giftController: any = nil
local carryController: any = nil
local danceWarmupService: any = nil
local musicPlayerController: any = nil
local loadingScreen: any? = nil
local loadingBootReady = false
local loadingFinished = false
local LOADING_MINIMUM_DURATION: number = LoadingConfig.MINIMUM_DURATION
local LOADING_MINIMUM_AFTER_READY: number = (LoadingConfig :: any).MINIMUM_AFTER_READY or 1.5
local loadingStartClock: number? = nil
local loadingFinishScheduled = false
-- Pending boot tasks that must settle before the loading screen can close.
local loadingBootPending = 0
local loadingBootTasksTotal = 0
local loadingBootTasksDone = 0
local loadingOverheadReady = if LOADING_SCREEN_ENABLED then false else true
local loadingMilestonesReadyAt: number? = nil
local maybeFinishLoadingScreen: (() -> ())? = nil
local gameplayEnteredFired = false

local function enterGameplay()
	if gameplayEnteredFired then
		return
	end
	gameplayEnteredFired = true
	clientBootScheduler:notifyGameplayEntered()
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	local readyRemoteName = tostring(ClientBootConfig.CLIENT_GAMEPLAY_READY_REMOTE or "ClientGameplayReady")
	if remotesFolder then
		local readyRemote = remotesFolder:FindFirstChild(readyRemoteName)
		if readyRemote and readyRemote:IsA("RemoteEvent") then
			pcall(function()
				(readyRemote :: RemoteEvent):FireServer()
			end)
		end
	end
end

local function updateLoadingProgress()
	if not loadingScreen or loadingFinished then
		return
	end
	local bootFraction = if loadingBootTasksTotal > 0
		then loadingBootTasksDone / loadingBootTasksTotal
		else 1
	local progress = 0.08 + (bootFraction * 0.62)
	if loadingOverheadReady then
		progress = math.max(progress, 0.88)
	end
	loadingScreen:setProgress(progress)
end

local function requestFinishLoadingScreen()
	local finish = maybeFinishLoadingScreen
	if finish then
		finish()
	end
end

if LOADING_SCREEN_ENABLED then
	task.spawn(function()
		-- Loading controller dibuat dari ReplicatedFirst; di sini kita hanya menempel ke instance yang sama.
		local ui = LoadingScreenUI.get()
		local waited = 0
		while not ui and waited < LoadingConfig.CONTROLLER_WAIT_TIMEOUT do
			task.wait(LoadingConfig.CONTROLLER_POLL_INTERVAL)
			waited += LoadingConfig.CONTROLLER_POLL_INTERVAL
			ui = LoadingScreenUI.get()
		end

		if not ui then
			warn("[LoadingScreenUI] bootstrap controller not ready")
			enterGameplay()
			return
		end

		loadingScreen = ui
		loadingStartClock = os.clock()
		loadingFinishScheduled = false
		if type(ui.onGameplayEntered) == "function" then
			ui:onGameplayEntered(enterGameplay)
		end
		ui:start(Players.LocalPlayer.DisplayName)
		if ui:isFinished() then
			loadingFinished = true
			enterGameplay()
			return
		end
		if loadingFinished then
			ui:finish()
			return
		end
		ui:setProgress(LoadingConfig.INITIAL_PROGRESS)
		updateLoadingProgress()
	end)
end

local function finishLoadingScreen()
	if loadingFinished then
		return
	end

	loadingFinished = true
	if loadingScreen and not loadingScreen:isFinished() then
		loadingScreen:finish()
	end
	-- When loading UI is disabled or never attached, unlock gameplay here.
	-- When UI is present, enterGameplay fires via onGameplayEntered after dismiss.
	if not LOADING_SCREEN_ENABLED or not loadingScreen then
		enterGameplay()
	end
end

maybeFinishLoadingScreen = function()
	if
		loadingFinished
		or (loadingScreen and loadingScreen:isFinished())
		or not loadingBootReady
		or loadingBootPending > 0
		or not loadingOverheadReady
	then
		return
	end

	loadingMilestonesReadyAt = loadingMilestonesReadyAt or os.clock()
	if loadingScreen and type((loadingScreen :: any).setSkipAvailable) == "function" then
		(loadingScreen :: any):setSkipAvailable(true)
	end

	local readyAt = loadingMilestonesReadyAt
	local holdAfterReady = math.max(tonumber(LOADING_MINIMUM_AFTER_READY) or 0, LOADING_MINIMUM_DURATION)
	local elapsedSinceReady = os.clock() - readyAt
	if elapsedSinceReady < holdAfterReady then
		if not loadingFinishScheduled then
			loadingFinishScheduled = true
			task.delay(math.max(holdAfterReady - elapsedSinceReady, 0), function()
				loadingFinishScheduled = false
				if loadingFinished or (loadingScreen and loadingScreen:isFinished()) then
					return
				end
				if not loadingBootReady or loadingBootPending > 0 or not loadingOverheadReady then
					return
				end
				finishLoadingScreen()
			end)
		end
		return
	end

	finishLoadingScreen()
end

local function syncBootCounters()
	loadingBootTasksTotal = clientBootScheduler:getInteractiveTotal()
	loadingBootPending = clientBootScheduler:getInteractivePending()
	loadingBootTasksDone = clientBootScheduler:getInteractiveDone()
end

clientBootScheduler:onInteractiveProgress(function()
	syncBootCounters()
	updateLoadingProgress()
end)

clientBootScheduler:onInteractiveSettled(function()
	requestFinishLoadingScreen()
end)

local function trackBootTask(name: string, fn: () -> ())
	clientBootScheduler:track(name, "interactive", fn)
	syncBootCounters()
end

local function trackPostGameplayBootTask(name: string, fn: () -> ())
	clientBootScheduler:track(name, "postGameplay", fn)
end

local function trackDeferredBootTask(name: string, fn: () -> ())
	trackPostGameplayBootTask(name, fn)
end

local function hardenScreenGui(instance: Instance?)
	if instance and instance:IsA("ScreenGui") then
		instance.ResetOnSpawn = false
	end
end

local function hardenStarterGuiTemplates()
	for _, child in ipairs(StarterGui:GetChildren()) do
		hardenScreenGui(child)
	end
	-- M-01: track ke _clientConnections agar di-disconnect saat script.Destroying
	table.insert(_clientConnections, StarterGui.ChildAdded:Connect(function(child)
		hardenScreenGui(child)
	end))
end

local function bindPlayerGuiResetGuard(playerGui: PlayerGui)
	for _, child in ipairs(playerGui:GetChildren()) do
		hardenScreenGui(child)
	end
	-- M-02: track ke _clientConnections agar di-disconnect saat script.Destroying
	table.insert(_clientConnections, playerGui.ChildAdded:Connect(function(child)
		hardenScreenGui(child)
	end))
end

task.spawn(hardenStarterGuiTemplates)

local function ensurePlayerGuiChild(playerGui: PlayerGui, childName: string, timeout: number, log: any): Instance?
	local child = playerGui:WaitForChild(childName, timeout)
	if child then
		hardenScreenGui(child)
		return child
	end

	local starterChild = StarterGui:FindFirstChild(childName)
	if not starterChild then
		return nil
	end
	hardenScreenGui(starterChild)

	local clonedChild = starterChild:Clone()
	hardenScreenGui(clonedChild)
	clonedChild.Parent = playerGui
	log:warn("GUI tidak ditemukan di PlayerGui; clone dari StarterGui", {
		name = childName,
		className = starterChild.ClassName,
	})
	return clonedChild
end

local MobileScaleService = require(script.Parent.Client.Services.MobileScaleService)
local MobilePanelManager = require(script.Parent.Client.Services.MobilePanelManager)
task.spawn(function()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	bindPlayerGuiResetGuard(playerGui)
	MobileScaleService.init(playerGui)
	MobilePanelManager.init(playerGui)
end)

local SharedContextModule = Shared:WaitForChild("ContextModule", LoadingConfig.BOOTSTRAP_WAIT_TIMEOUT)
local SharedUtils = Shared:WaitForChild("Utils", LoadingConfig.BOOTSTRAP_WAIT_TIMEOUT)
local Remotes = ReplicatedStorage:WaitForChild("Remotes", LoadingConfig.BOOTSTRAP_WAIT_TIMEOUT)
local iconModule = kitRoot:WaitForChild("Icon", LoadingConfig.BOOTSTRAP_WAIT_TIMEOUT)

if
	not (SharedContextModule and SharedContextModule:IsA("Folder"))
	or not (SharedUtils and SharedUtils:IsA("Folder"))
	or not (Remotes and Remotes:IsA("Folder"))
	or not (iconModule and iconModule:IsA("ModuleScript"))
then
	warn("[LoadingScreen] Critical client dependencies were not replicated in time")
	finishLoadingScreen()
	enterGameplay()
	return
end

-- Subscribe OverheadUpdate ASAP so loading screen is not blocked by later controller inits.
local OverheadController = require(script.Parent.Client.Controllers.OverheadController)
OverheadController.init({})
if LOADING_SCREEN_ENABLED then
	task.spawn(function()
		local localPlayer = Players.LocalPlayer
		local overheadCfg = Config.Overhead
		local timeout = (tonumber(overheadCfg.CHARACTER_READY_DELAY) or 0.5)
			+ (tonumber(overheadCfg.GROUP_RANK_SETTLE_DELAY) or 4)
			+ (tonumber(overheadCfg.REMOTE_READY_TIMEOUT) or 45) * 0.25
			+ 6
		local deadline = os.clock() + timeout
		while os.clock() < deadline and not loadingOverheadReady do
			if OverheadController.getCachedPayload(localPlayer.UserId) then
				loadingOverheadReady = true
				updateLoadingProgress()
				requestFinishLoadingScreen()
				return
			end
			task.wait(0.15)
		end
		if not loadingOverheadReady then
			warn("[LoadingScreen] Local overhead payload timeout; continuing boot")
			loadingOverheadReady = true
			updateLoadingProgress()
			requestFinishLoadingScreen()
		end
	end)
end

local NotifController = require(script.Parent.Client.Controllers.NotifController)
local ChatTagsController = require(script.Parent.Client.Controllers.ChatTagsController)
local CoupleController = require(script.Parent.Client.Controllers.CoupleController)
local createShopController = require(script.Parent.Client.Controllers.ShopController)
local createShopService = require(script.Parent.Client.Services.ShopService)
local createDonationRobuxService = require(script.Parent.Client.Services.DonationRobuxService)
local createCommandLibraryService = require(script.Parent.Client.Services.CommandLibraryService)
local createDanceWarmupService = require(script.Parent.Client.Services.DanceWarmupService)
local StreakController = require(script.Parent.Client.Controllers.StreakController)
local AfkGuardController = require(script.Parent.Client.Controllers.AfkGuardController)
local GiftController = require(script.Parent.Client.Controllers.GiftController)
local AdminController = require(script.Parent.Client.Controllers.AdminController)
local createAvatarContextController = require(script.Parent.Client.Controllers.AvatarContextController)
local createCarryController = require(script.Parent.Client.Controllers.CarryController)
local createCommandLibraryController = require(script.Parent.Client.Controllers.CommandLibraryController)
local createSettingsController = require(script.Parent.Client.Controllers.SettingsController)
local createSyncController = require(script.Parent.Client.Controllers.SyncController)
local createSyncPanelTriggerController = require(script.Parent.Client.Controllers.SyncPanelTriggerController)
local HotbarController = require(script.Parent.Client.Controllers.HotbarController)
local StickerController = require(script.Parent.Client.Controllers.StickerController)
local DonationLeaderboardController = require(script.Parent.Client.Controllers.DonationLeaderboardController)
local DonationNotificationController = require(script.Parent.Client.Controllers.DonationNotificationController)
local DonationSystemController = require(script.Parent.Client.Controllers.DonationSystemController)
local DonationSystemBootstrap = require(script.Parent.Client.DonationSystemBootstrap)
local GenericBroadcastController = require(script.Parent.Client.Controllers.GenericBroadcastController)
local PaidBroadcastController = require(script.Parent.Client.Controllers.PaidBroadcastController)
local CinematicDockController = require(script.Parent.Client.Controllers.CinematicDockController)
local TopMenuController = require(script.Parent.Client.Controllers.TopMenuController)
local createFreecamController = require(script.Parent.Client.Controllers.FreecamController)
local createGravityController = require(script.Parent.Client.Controllers.GravityController)
local createMobileFreecamController = require(script.Parent.Client.Controllers.MobileFreecamController)
local createSyncLeadTopbarController = require(script.Parent.Client.Controllers.SyncLeadTopbarController)
local createAvatarContextUI = require(script.Parent.Client.UI.AvatarContextUI)
local createCarryUI = require(script.Parent.Client.UI.CarryUI)
local createCommandLibraryUI = require(script.Parent.Client.UI.CommandLibraryUI)
local createSettingsMenuUI = require(script.Parent.Client.UI.SettingsMenuUI)
local HotbarGuiRefs = require(script.Parent.Client.UI.HotbarGuiRefs)
local HotbarUIBinder = require(script.Parent.Client.UI.HotbarUIBinder)
local BackpackGuiRefs = require(script.Parent.Client.UI.BackpackGuiRefs)
local BackpackUIBinder = require(script.Parent.Client.UI.BackpackUIBinder)
local InventoryDragController = require(script.Parent.Client.UI.InventoryDragController)
local DancePanelGuiRefs = require(script.Parent.Client.UI.DancePanelGuiRefs)
local DancePanelUIBinder = require(script.Parent.Client.UI.DancePanelUIBinder)
local UISoundHelper = require(script.Parent.Client.Utils.UISoundHelper)
local AvatarLikeWorldEffect = require(script.Parent.Client.Utils.AvatarLikeWorldEffect)
local _NukeEffectController = require(script.Parent.Client.Utils.NukeEffectController)
local StickerBillboardAnimator = require(script.Parent.Client.Utils.StickerBillboardAnimator)
local CommandLibraryStore = require(script.Parent.Client.State.CommandLibraryStore)
local CarryStore = require(script.Parent.Client.State.CarryStore)
local InventoryStore = require(script.Parent.Client.State.InventoryStore)
local SyncStore = require(script.Parent.Client.State.SyncStore)
local MusicPlayerStore = require(script.Parent.Client.State.MusicPlayerStore)
local MusicPlayerController = require(script.Parent.Client.Controllers.MusicPlayerController)
local MusicPlayerGuiRefs = require(script.Parent.Client.UI.MusicPlayerGuiRefs)
local MusicPlayerUIBinder = require(script.Parent.Client.UI.MusicPlayerUIBinder)
local MusicTopbarIcon = require(script.Parent.Client.UI.MusicTopbarIcon)
local HotbarInventoryService = require(script.Parent.Client.Services.HotbarInventoryService)
local NotifService = require(script.Parent.Client.Services.NotifService)
local AnimationLoader = require(SharedContextModule:WaitForChild("AnimationLoader"))
local CarryDomain = require(SharedDomain:WaitForChild("CarryDomain"))
-- TopbarPlus
local Icon = require(iconModule) :: any
local Logger = require(SharedUtils:WaitForChild("Logger"))
local Lifecycle = require(SharedUtils:WaitForChild("Lifecycle"))
local Cache = require(SharedUtils:WaitForChild("Cache"))
local clientLifecycle = Lifecycle.new(Logger.new("ClientLifecycle"))

local function trackClientLifecycle(name: string, module: any): any
	return clientLifecycle:register(name, module)
end

-- Register modules with destroy() for hot-reload teardown (init may run later).
trackClientLifecycle("OverheadController", OverheadController)
trackClientLifecycle("NotifController", NotifController)
trackClientLifecycle("GenericBroadcastController", GenericBroadcastController)
trackClientLifecycle("ChatTagsController", ChatTagsController)
trackClientLifecycle("StreakController", StreakController)
trackClientLifecycle("AfkGuardController", AfkGuardController)
trackClientLifecycle("CoupleController", CoupleController)
trackClientLifecycle("CinematicDockController", CinematicDockController)
trackClientLifecycle("DonationLeaderboardController", DonationLeaderboardController)
trackClientLifecycle("DonationNotificationController", DonationNotificationController)
trackClientLifecycle("DonationSystemController", DonationSystemController)
trackClientLifecycle("PaidBroadcastController", PaidBroadcastController)
trackClientLifecycle("AdminController", AdminController)
trackClientLifecycle("AvatarLikeWorldEffect", AvatarLikeWorldEffect)
trackClientLifecycle("TopMenuController", TopMenuController)
trackClientLifecycle("StickerBillboardAnimator", StickerBillboardAnimator)

local function createSubscriptionGroup(name: string): any
	local groupLog = Logger.new(name)
	local unsubscribers = {} :: { () -> () }
	local group = {}

	function group:subscribe(store: any, key: string, callback: (any, any) -> ())
		local unsubscribe = store:subscribe(key, callback)
		if type(unsubscribe) == "function" then
			table.insert(unsubscribers, unsubscribe)
		end
	end

	function group:destroy()
		for index = #unsubscribers, 1, -1 do
			local unsubscribe = unsubscribers[index]
			-- xpcall: hapus type annotation agar return count tidak mismatch
			local ok, err = xpcall(unsubscribe :: () -> (), debug.traceback)
			if not ok then
				groupLog:warn("Subscription cleanup failed", {
					error = tostring(err),
				})
			end
		end
		table.clear(unsubscribers)
	end

	return group
end

script.Destroying:Connect(function()
	if shared[MAIN_BOOT_OWNER_KEY] == script then
		shared[MAIN_BOOT_OWNER_KEY] = nil
	end
	clientLifecycle:destroyAll()
	-- Disconnect semua listener yang di-track di luar Lifecycle
	for _, conn in ipairs(_clientConnections) do
		conn:Disconnect()
	end
	table.clear(_clientConnections)
	-- Tear down the shared avatar prewarm pool (Heartbeat + PlayerAdded/Removing
	-- connections + live 3D avatar models) so a hot-reload does not orphan it.
	AvatarPrewarmShared.destroy()
	-- Cancel Cache singleton sweeper + clear store (mirrors Main.server Destroying).
	Cache.destroy()
end)

task.defer(function()
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end
	local legacyOverlay = playerGui:FindFirstChild("CoreTopbarOutlineOverlay")
	if legacyOverlay then
		legacyOverlay:Destroy()
	end
end)
local function placeTopbarIcon(icon: any, order: number)
	icon:setOrder(order)
	-- Beberapa versi TopbarPlus menyediakan API alignment explicit.
	-- Fallback aman: kalau method tidak ada, urutan icon tetap dipakai.
	if type(icon.setRight) == "function" then
		icon:setRight()
	elseif type(icon.align) == "function" then
		icon:align("Right")
	elseif type(icon.setAlignment) == "function" then
		icon:setAlignment("Right")
	end
end
local function placeTopbarIconLeft(icon: any, order: number)
	icon:setOrder(order)
	if type(icon.setLeft) == "function" then
		icon:setLeft()
	elseif type(icon.align) == "function" then
		icon:align("Left")
	elseif type(icon.setAlignment) == "function" then
		icon:setAlignment("Left")
	end
end
local function setCompactTopbarWidth(icon: any, minimumWidth: number)
	if type(icon.setWidth) == "function" then
		icon:setWidth(minimumWidth)
	elseif type(icon.modifyTheme) == "function" then
		local themePatch = {} :: any
		themePatch[1] = "Widget"
		themePatch[2] = "MinimumWidth"
		themePatch[3] = minimumWidth
		icon:modifyTheme(themePatch)
	end
end
local function removeTopbarInnerPadding(icon: any)
	if type(icon.modifyTheme) == "function" then
		local leftPatch = {} :: any
		leftPatch[1] = "PaddingLeft"
		leftPatch[2] = "Size"
		leftPatch[3] = UDim2.fromScale(0, 1)
		local rightPatch = {} :: any
		rightPatch[1] = "PaddingRight"
		rightPatch[2] = "Size"
		rightPatch[3] = UDim2.fromScale(0, 1)
		local themePatch = {} :: any
		themePatch[1] = leftPatch
		themePatch[2] = rightPatch
		icon:modifyTheme(themePatch)
	end
end
local function setTopbarHorizontalPadding(icon: any, horizontalPadding: number)
	if type(icon.modifyTheme) == "function" then
		local leftPatch = {} :: any
		leftPatch[1] = "PaddingLeft"
		leftPatch[2] = "Size"
		leftPatch[3] = UDim2.new(0, horizontalPadding, 1, 0)
		local rightPatch = {} :: any
		rightPatch[1] = "PaddingRight"
		rightPatch[2] = "Size"
		rightPatch[3] = UDim2.new(0, horizontalPadding, 1, 0)
		local themePatch = {} :: any
		themePatch[1] = leftPatch
		themePatch[2] = rightPatch
		icon:modifyTheme(themePatch)
	end
end
local function resolveTopbarWidget(icon: any): GuiObject?
	local function resolveWidget(candidate: any): GuiObject?
		if typeof(candidate) == "Instance" and candidate:IsA("GuiObject") then
			return candidate :: GuiObject
		end
		return nil
	end
	local directCandidates = {
		icon.widget,
		icon._widget,
		icon.widgetInstance,
		icon._widgetInstance,
		icon.buttonInstance,
		icon._buttonInstance,
	}
	for _, candidate in ipairs(directCandidates) do
		local widget = resolveWidget(candidate)
		if widget then
			return widget
		end
	end
	local methodCandidates = {
		"getInstance",
		"getWidget",
		"getButton",
		"getIconInstance",
	}
	for _, methodName in ipairs(methodCandidates) do
		local method = icon[methodName]
		if type(method) == "function" then
			local ok, result = pcall(function()
				return method(icon, "Widget")
			end)
			if ok then
				local widget = resolveWidget(result)
				if widget then
					return widget
				end
			end
			ok, result = pcall(function()
				return method(icon)
			end)
			if ok then
				local widget = resolveWidget(result)
				if widget then
					return widget
				end
			end
		end
	end
	return nil
end
local function resolveTopbarGuiObject(icon: any, instanceName: string): GuiObject?
	local method = icon.getInstance
	if type(method) ~= "function" then
		return nil
	end

	local ok, result = pcall(function()
		return method(icon, instanceName)
	end)
	if ok and typeof(result) == "Instance" and result:IsA("GuiObject") then
		return result :: GuiObject
	end
	return nil
end
local function hideTopbarMenuScrollbar(icon: any)
	local candidateNames = {
		"Menu",
		"Dropdown",
		"MenuContainer",
		"DropdownContainer",
		"MenuCanvas",
	}
	local visited = {} :: { [Instance]: boolean }
	local roots = {} :: { GuiObject }

	for _, name in ipairs(candidateNames) do
		local root = resolveTopbarGuiObject(icon, name)
		if root and not visited[root] then
			visited[root] = true
			table.insert(roots, root)
		end
	end

	local widget = resolveTopbarWidget(icon)
	if widget and not visited[widget] then
		visited[widget] = true
		table.insert(roots, widget)
	end

	for _, root in ipairs(roots) do
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("ScrollingFrame") then
				local scroller = descendant :: ScrollingFrame
				scroller.ScrollBarThickness = 0
				scroller.VerticalScrollBarInset = Enum.ScrollBarInset.None
			end
		end
	end
end
local function scheduleTopbarMenuScrollbarPatch(icon: any)
	task.defer(function()
		hideTopbarMenuScrollbar(icon)
	end)
	task.delay(0.25, function()
		hideTopbarMenuScrollbar(icon)
	end)
	task.delay(1, function()
		hideTopbarMenuScrollbar(icon)
	end)
end
local function bindTopbarMenuScrollbarPatch(icon: any)
	scheduleTopbarMenuScrollbarPatch(icon)
	if icon.selected and type(icon.selected.Connect) == "function" then
		icon.selected:Connect(function()
			scheduleTopbarMenuScrollbarPatch(icon)
		end)
	end
end
local TOPBAR_FILL_COLOR = Color3.fromRGB(7, 7, 7)
local TOPBAR_FILL_TRANSPARENCY = 0
local TOPBAR_OUTLINE_OVERLAY_NAME = "CodexTopbarOutlineOverlay"
local topbarOutlineIdByWidget = setmetatable({}, { __mode = "k" }) :: { [GuiObject]: string }
local function setTopbarFill(icon: any, color: Color3)
	if type(icon.modifyTheme) == "function" then
		icon:modifyTheme({
			{ "Widget", "BackgroundTransparency", 1 },
			{ "IconButton", "BackgroundColor3", color },
			{ "IconButton", "BackgroundTransparency", TOPBAR_FILL_TRANSPARENCY },
		})
	end

	local widget = resolveTopbarWidget(icon)
	if widget then
		widget.BackgroundTransparency = 1
		local iconButton = widget:FindFirstChild("IconButton")
		if iconButton and iconButton:IsA("GuiObject") then
			iconButton.BackgroundColor3 = color
			iconButton.BackgroundTransparency = TOPBAR_FILL_TRANSPARENCY
		end
	end
end

local function clearLegacyTopbarOutlineHosts(guiObject: GuiObject)
	for _, child in ipairs(guiObject:GetChildren()) do
		if child.Name == "CodexTopbarOutlineHost" or (child.Name == "CodexTopbarOutline" and child:IsA("UIStroke")) then
			child:Destroy()
		end
	end

	local outlineParent = guiObject.Parent
	if outlineParent then
		for _, child in ipairs(outlineParent:GetChildren()) do
			if child.Name == "CodexTopbarOutlineHost" then
				child:Destroy()
			end
		end
	end
end

local function removeTopbarOutline(icon: any)
	local widget = resolveTopbarWidget(icon)
	if not widget then
		return
	end

	clearLegacyTopbarOutlineHosts(widget)
	local existingOutline = widget:FindFirstChild("CodexTopbarOutline")
	if existingOutline then
		existingOutline:Destroy()
	end

	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local overlay = playerGui:FindFirstChild(TOPBAR_OUTLINE_OVERLAY_NAME)
	if not overlay then
		return
	end
	local hostName = topbarOutlineIdByWidget[widget]
	if hostName then
		local host = overlay:FindFirstChild(hostName)
		if host then
			host:Destroy()
		end
		topbarOutlineIdByWidget[widget] = nil
	end
end

local function scheduleTopbarOutline(icon: any)
	removeTopbarOutline(icon)
	task.defer(function()
		removeTopbarOutline(icon)
	end)
	task.delay(0.25, function()
		removeTopbarOutline(icon)
	end)
	task.delay(1, function()
		removeTopbarOutline(icon)
	end)
end
local function styleTopbarPill(icon: any)
	setTopbarFill(icon, TOPBAR_FILL_COLOR)
	scheduleTopbarOutline(icon)
end
local function enlargeTopbarIcon(icon: any, _widgetWidth: number, iconSize: number)
	if type(icon.setImageScale) == "function" then
		icon:setImageScale(iconSize / 16)
	end
end

local function _disableTopbarHoverLabel(icon: any)
	if type(icon.setLabel) == "function" then
		icon:setLabel("")
	end
end
-- NOTE: _disableTopbarHoverLabel tersedia untuk topbar icon future usage
-- ShopService shared - satu instance, dipakai oleh GiftController & ShopController
local sharedShopService = trackClientLifecycle(
	"ShopService",
	createShopService({ remotes = Remotes })
)
local donationLog = Logger.new("DonationSystem")
local donationRobuxService = trackClientLifecycle(
	"DonationRobuxService",
	createDonationRobuxService({
		remotes = Remotes,
		logger = donationLog,
	})
)
local uiSoundHelper = trackClientLifecycle(
	"UISoundHelper",
	UISoundHelper.new({
		config = Config.UISFX,
	})
)
-- === Notif ===
NotifController.init({
	notifyRemote = Remotes:WaitForChild("Notify") :: RemoteEvent,
})
GenericBroadcastController.init()
-- === UI SFX ===
uiSoundHelper:init()
AvatarLikeWorldEffect.init({
	logger = Logger.new("AvatarLikeWorldEffect"),
	remote = Remotes:WaitForChild(Config.AvatarContext.REMOTE_LIKE_EFFECT) :: RemoteEvent,
})
-- World-position nuke VFX (Nuke/Smite/BlackHole). The remote itself is
-- resolved inside the controller so we don't need to thread it here.
-- Disabled: world-position VFX is handled by legacy EffectDonate scripts for Bagi-Bagi.
-- NukeEffectController.init({
-- 	logger = Logger.new("NukeEffectController"),
-- })
-- === Sticker Billboard Animations ===
if Config.FeatureFlags.StickersEnabled ~= false then
	StickerBillboardAnimator.init({
		logger = Logger.new("StickerBillboardAnimator"),
	})
end
ChatTagsController.init({})
-- === Shared Topbar Icons ===
-- Dibuat SEBELUM controller init agar icon sudah ada
-- saat controller mencoba bind .selected/.deselected
local menuIcon = Icon.new()
menuIcon:setImage(Config.Icons.Topbar.Menu, "Deselected")
menuIcon:setLabel("")
placeTopbarIcon(menuIcon, Config.TopbarMenu.ORDER)
setCompactTopbarWidth(menuIcon, 36)
removeTopbarInnerPadding(menuIcon)
styleTopbarPill(menuIcon)
enlargeTopbarIcon(menuIcon, 36, 10)
-- Admin + Command Center icons are placed early so they stay visible even if later boot steps fail.
local adminIcon = Icon.new()
adminIcon:setImage(Config.Icons.Topbar.Admin)
adminIcon:setLabel("")
placeTopbarIcon(adminIcon, Config.Admin.TOPBAR_ORDER)
setCompactTopbarWidth(adminIcon, 36)
removeTopbarInnerPadding(adminIcon)
styleTopbarPill(adminIcon)
enlargeTopbarIcon(adminIcon, 36, 10)
local commandLibraryIcon = Icon.new()
commandLibraryIcon:setImage(Config.Icons.Topbar.Command)
commandLibraryIcon:setLabel(Config.CommandLibrary.TOPBAR_LABEL)
placeTopbarIcon(commandLibraryIcon, Config.CommandLibrary.TOPBAR_ORDER)
setCompactTopbarWidth(commandLibraryIcon, 36)
removeTopbarInnerPadding(commandLibraryIcon)
styleTopbarPill(commandLibraryIcon)
enlargeTopbarIcon(commandLibraryIcon, 36, 10)
do
	local function bindExclusivePanelIcon(icon: any, panelId: string)
		icon.selected:Connect(function()
			MobilePanelManager.open(panelId)
		end)
		icon.deselected:Connect(function()
			MobilePanelManager.close(panelId)
		end)
	end
	MobilePanelManager.register("admin", Config.Admin.GUI_NAME, function()
		adminIcon:deselect()
	end)
	MobilePanelManager.register("command", Config.CommandLibrary.GUI_NAME, function()
		commandLibraryIcon:deselect()
	end)
	bindExclusivePanelIcon(adminIcon, "admin")
	bindExclusivePanelIcon(commandLibraryIcon, "command")
end
local shopIcon = Icon.new()
shopIcon:setImage(Config.Icons.Topbar.Shop)
shopIcon:setLabel(Config.TopbarMenu.SHOP_LABEL)
shopIcon:setOrder(Config.Shop.TOPBAR_ORDER)
local donationIcon = Icon.new()
donationIcon:setImage(Config.Icons.Topbar.Shop)
donationIcon:setLabel(Config.Donation.TOPBAR_LABEL)
donationIcon:setOrder(Config.Donation.TOPBAR_ORDER)
local giftIcon = Icon.new()
giftIcon:setImage(Config.Icons.Topbar.Gift)
giftIcon:setLabel(Config.TopbarMenu.GIFT_LABEL)
giftIcon:setOrder(Config.Gift.TOPBAR_ORDER)
local coupleIcon = Icon.new()
coupleIcon:setImage(Config.Icons.Topbar.Couple)
coupleIcon:setLabel(Config.TopbarMenu.COUPLE_LABEL)
coupleIcon:setOrder(Config.Couple.TOPBAR_ORDER)
local settingsIcon = Icon.new()
settingsIcon:setImage(Config.Icons.Topbar.Settings)
settingsIcon:setLabel(Config.TopbarMenu.SETTINGS_LABEL)
settingsIcon:setOrder(Config.TopbarMenu.ORDER + 1)
local cinematicIcon = Icon.new()
cinematicIcon:setImage(Config.CinematicDock.TOPBAR_ICON)
cinematicIcon:setLabel("")
cinematicIcon:setOrder(Config.TopbarMenu.ORDER + 2)
local paidBroadcastIcon = Icon.new()
paidBroadcastIcon:setImage(Config.PaidBroadcast.TOPBAR_ICON)
paidBroadcastIcon:setLabel(Config.PaidBroadcast.TOPBAR_LABEL)
paidBroadcastIcon:setOrder(Config.PaidBroadcast.TOPBAR_ORDER)

-- Keep trigger icons off the topbar strip; they only fire panel logic via select().
local attachOk, attachErr = pcall(function()
	TopMenuController.hideTopbarTriggerIcons({
		shopIcon,
		donationIcon,
		giftIcon,
		coupleIcon,
		settingsIcon,
		cinematicIcon,
		paidBroadcastIcon,
	})
	TopMenuController.blockTopbarPlusMenu(menuIcon)
end)
if not attachOk then
	warn("[Main] TopMenuController hidden menu triggers failed:", attachErr)
end

local function roleCanUseCinematicDock(): boolean
	local player = Players.LocalPlayer
	local role = OverheadController.getPlayerRole(player.UserId)
	return PermissionDomain.canUseAdminPanel(role, player.UserId)
end

task.defer(function()
	TopMenuController.init({
		menuIcon = menuIcon,
		icons = {
			shop = shopIcon,
			donation = donationIcon,
			gift = giftIcon,
			couple = coupleIcon,
			settings = settingsIcon,
			cinematic = cinematicIcon,
			broadcast = paidBroadcastIcon,
		},
		settingsUI = nil,
		isCinematicVisible = roleCanUseCinematicDock,
	})
end)
-- Desktop freecam: Shift+P only (no topbar icon). Touch devices use MobileFreecam.
local freecamIcon: any = nil
local musicTopbarIcon: any = nil

if Config.FeatureFlags.MusicPlayerEnabled then
	-- Music topbar icon is owned by a dedicated wrapper that creates/destroys
	-- the TopbarPlus instance on zone enter/leave. This is the only reliable
	-- way to fully hide it across TopbarPlus versions — setEnabled(false) does
	-- not work consistently on every build, and widget-resolver hides depend on
	-- internal property names that vary. The controller calls show()/hide()
	-- through this wrapper as a single source of truth.
	musicTopbarIcon = MusicTopbarIcon.new({
		iconFactory = function()
			return Icon.new()
		end,
		applyStyling = function(icon: any)
			if Config.Music.TOPBAR_ICON ~= "rbxassetid://0" then
				icon:setImage(Config.Music.TOPBAR_ICON)
			end
			icon:setLabel(Config.Music.TOPBAR_LABEL)
			placeTopbarIcon(icon, Config.Music.TOPBAR_ORDER)
			setCompactTopbarWidth(icon, 36)
			removeTopbarInnerPadding(icon)
			styleTopbarPill(icon)
			enlargeTopbarIcon(icon, 36, 10)
		end,
		logger = Logger.new("MusicTopbarIcon"),
	})
end
local paidBroadcastOk, paidBroadcastErr = pcall(function()
	PaidBroadcastController.init({
		icon = paidBroadcastIcon,
		remotes = Remotes,
	})
end)
if not paidBroadcastOk then
	warn("[Main] PaidBroadcastController.init failed:", paidBroadcastErr)
end
local cinematicOk, cinematicErr = pcall(function()
	CinematicDockController.init({
		icon = cinematicIcon,
	})
end)
if not cinematicOk then
	warn("[Main] CinematicDockController.init failed:", cinematicErr)
end
-- Pakai custom freecam (bukan Roblox dev fly). Desktop = Shift+P; mobile = MobileFreecam GUI.
pcall(function()
	StarterPlayer.DevComputerCameraMovementMode = Enum.DevComputerCameraMovementMode.UserInput
	StarterPlayer.DevTouchCameraMovementMode = Enum.DevTouchCameraMovementMode.Follow
end)
local _freecamController = trackClientLifecycle(
	"FreecamController",
	createFreecamController({
		icon = freecamIcon,
		iconApi = Icon,
	})
)
if Config.FeatureFlags.GravityEnabled ~= false then
	local gravityController = createGravityController({
		freecamScript = script.Parent.Client.Controllers.FreecamController,
	})
	trackClientLifecycle("GravityController", gravityController)
	gravityController:init()
end
local _mobileFreecamController = trackClientLifecycle(
	"MobileFreecamController",
	createMobileFreecamController({
	icon = nil,
	iconFactory = function()
		return Icon.new()
	end,
	applyTopbarStyle = function(icon: any)
		placeTopbarIconLeft(icon, 1)
		setCompactTopbarWidth(icon, 36)
		removeTopbarInnerPadding(icon)
		styleTopbarPill(icon)
		enlargeTopbarIcon(icon, 36, 10)
	end,
	})
)
-- Music topbar visibility is owned end-to-end by MusicPlayerController via the
-- MusicTopbarIcon wrapper. No store subscriber is needed here — the previous
-- `applyMusicTopbarVisibility` retry pattern relied on `setEnabled(false)` and
-- a heuristic widget resolver, neither of which fully removed the icon on this
-- TopbarPlus build. Create/destroy via the wrapper is the reliable contract.
-- === Mobile Panel Focus (mobile-only; no-op on desktop) ===
do
	local mpmCfg = Config.MobilePanelManager
	-- Helper: bind TopbarPlus icon selected/deselected to panel manager
	local function bindPanelIcon(icon: any, panelId: string): ()
		icon.selected:Connect(function()
			MobilePanelManager.open(panelId)
		end)
		icon.deselected:Connect(function()
			MobilePanelManager.close(panelId)
		end)
	end
	MobilePanelManager.register("couple", mpmCfg.COUPLE_GUI_NAME, function()
		coupleIcon:deselect()
	end)
	MobilePanelManager.register("shop", mpmCfg.SHOP_GUI_NAME, function()
		shopIcon:deselect()
	end)
	MobilePanelManager.register("gift", Config.Gift.GUI_NAME, function()
		giftIcon:deselect()
	end)
	MobilePanelManager.register("donation", Config.Donation.GUI_NAME, function()
		donationIcon:deselect()
	end)
	MobilePanelManager.register("settings", Config.Settings.GUI_NAME, function()
		settingsIcon:deselect()
	end)
	MobilePanelManager.register("broadcast", Config.PaidBroadcast.GUI_NAME, function()
		paidBroadcastIcon:deselect()
	end)
	bindPanelIcon(coupleIcon, "couple")
	bindPanelIcon(shopIcon, "shop")
	bindPanelIcon(giftIcon, "gift")
	bindPanelIcon(donationIcon, "donation")
	bindPanelIcon(paidBroadcastIcon, "broadcast")
	trackBootTask("Donation.bootstrap", function()
		DonationSystemBootstrap.start({
			icon = donationIcon,
			service = donationRobuxService,
			logger = donationLog,
			ensureGui = function(playerGui: PlayerGui, guiName: string, timeout: number): Instance?
				return ensurePlayerGuiChild(playerGui, guiName, timeout, donationLog)
			end,
		})
	end)
	bindPanelIcon(settingsIcon, "settings")
	if musicTopbarIcon ~= nil then
		MobilePanelManager.register("music", Config.Music.GUI_NAME, function()
			musicTopbarIcon:deselect()
		end)
		-- Mobile focus integration. Controller owns its own panel open/close logic
		-- through a separate onSelected/onDeselected subscription on the same wrapper.
		musicTopbarIcon:onSelected(function()
			MobilePanelManager.open("music")
		end)
		musicTopbarIcon:onDeselected(function()
			MobilePanelManager.close("music")
		end)
	end
end
-- === Couple ===
if Config.FeatureFlags.CouplesEnabled ~= false then
	trackBootTask("CoupleController.init", function()
		CoupleController.init({
			icon = coupleIcon,
		})
	end)
end
-- === Gift + Shop + Streak + Admin ===
-- Semua controller yang memuat GUI dari PlayerGui dijalankan di trackBootTask
-- agar WaitForChild di dalam tidak blocking icon setup topbar
trackBootTask("GiftShopInit", function()
	-- === Gift ===
	local giftCtrl = GiftController.init({
		shopService = sharedShopService,
		remotes = Remotes,
		icon = giftIcon,
	})
	trackClientLifecycle("GiftController", giftCtrl)
	giftController = giftCtrl
	if Config.FeatureFlags.ShopEnabled == false then
		return
	end
	-- === Shop ===
	local shopGui = Players.LocalPlayer.PlayerGui:WaitForChild("02-ShopGUI", 10)
	if not shopGui then
		warn("[LoadingScreen] Shop GUI not found; shop panel disabled")
		return
	end
	local shopCtrl = createShopController({
		gui = shopGui :: ScreenGui,
		remotes = Remotes,
		shopService = sharedShopService,
		giftController = giftCtrl,
		icon = shopIcon,
	})
	shopCtrl:init()
	trackClientLifecycle("ShopController", shopCtrl)
end)
-- === Streak ===
trackBootTask("StreakController.init", function()
	StreakController.init({ remotes = Remotes })
end)
trackBootTask("AfkGuardController.init", function()
	if Config.FeatureFlags.AfkGuardEnabled ~= false and Config.AfkGuard.ENABLED == true then
		AfkGuardController.init({ remotes = Remotes })
	end
end)
-- === Admin Panel ===
trackBootTask("AdminController.init", function()
	AdminController.init({
		remotes = Remotes,
		icon = adminIcon,
	})
end)
trackBootTask("CommandLibraryController.init", function()
	local commandLibraryService = trackClientLifecycle(
		"CommandLibraryService",
		createCommandLibraryService()
	)
	local commandLibraryUI = createCommandLibraryUI({ logger = Logger.new("CommandLibraryUI") })
	local commandLibraryCtrl = createCommandLibraryController({
		logger = Logger.new("CommandLibraryController"),
		ui = commandLibraryUI,
		store = CommandLibraryStore,
		executeCommand = function(commandText: string)
			commandLibraryService:execute(commandText)
		end,
		icon = commandLibraryIcon,
	})
	commandLibraryCtrl:init()
end)
trackBootTask("SettingsController.init", function()
	if Config.FeatureFlags.SettingsEnabled == false then
		settingsIcon:setEnabled(false)
		return
	end
	local settingsUI = createSettingsMenuUI({})
	TopMenuController.setSettingsUI(settingsUI)
	local settingsCtrl = trackClientLifecycle(
		"SettingsController",
		createSettingsController({
			logger = Logger.new("SettingsController"),
			ui = settingsUI,
			icon = settingsIcon,
			remotes = Remotes,
		})
	)
	settingsCtrl:init()
end)
-- Hotbar + backpack: InventoryStore, HotbarInventoryService, InventoryDragController, binders.
-- Slot cap from PhoneLayout.getHotbarMaxSlots() (Config.Hotbar.MAX_SLOTS_MOBILE on phone).
trackBootTask("HotbarController.init", function()
	if not Config.FeatureFlags.HotbarEnabled then
		return
	end

	MobilePanelManager.setInventoryChromeCallbacks({
		onHiddenChanged = function(hidden: boolean)
			InventoryStore:set({ inventoryChromeHidden = hidden })
		end,
		isBackpackOpen = function(): boolean
			return InventoryStore:get().isBackpackOpen
		end,
	})

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	local hotbarLog = Logger.new("Hotbar")
	local hotbarGui: Instance? = nil
	for _, guiName in ipairs(Config.Hotbar.GUI_NAMES) do
		hotbarGui = ensurePlayerGuiChild(playerGui, guiName, 10, hotbarLog)
		if hotbarGui then
			break
		end
	end
	if not hotbarGui then
		hotbarLog:warn("GUI not found; hotbar disabled", {
			name = table.concat(Config.Hotbar.GUI_NAMES, ", "),
		})
		return
	end

	local refsResult = HotbarGuiRefs.resolve(playerGui)
	if not refsResult.ok then
		hotbarLog:error("Hotbar GUI resolve failed", {
			error = refsResult.error,
		})
		return
	end

	local service = HotbarInventoryService.new({
		store = InventoryStore,
		logger = Logger.new("HotbarInventoryService"),
		slotCount = PhoneLayout.getHotbarMaxSlots(),
	})

	ensurePlayerGuiChild(playerGui, Config.Backpack.GUI_NAME, 10, hotbarLog)
	local backpackRefsResult = BackpackGuiRefs.resolve(playerGui)
	local backpackBinder = nil
	if backpackRefsResult.ok then
		MobileScaleService.applyBackpackLayout(backpackRefsResult.value.root)
	else
		hotbarLog:warn("Backpack GUI resolve failed; hotbar drag only", {
			error = backpackRefsResult.error,
		})
	end

	local inventoryDrag = InventoryDragController.new({
		root = refsResult.value.root,
		hotbarWrapper = refsResult.value.hotbarWrapper,
		backpackScroll = if backpackRefsResult.ok then backpackRefsResult.value.scrollFrame else nil,
		getHotbarSlots = function()
			return InventoryStore:get().hotbarSlots
		end,
		getBackpackSlots = function()
			return InventoryStore:get().backpackSlots
		end,
		onReorderHotbar = function(toolKey: string, toIndex: number)
			service:reorder(toolKey, toIndex)
		end,
		onAssignToHotbar = function(toolKey: string, toIndex: number): boolean
			return service:assignToolToHotbar(toolKey, toIndex)
		end,
		onSnapshotOrder = function(): { string }
			return service:snapshotOrder()
		end,
		onRestoreOrder = function(snapshot: { string })
			service:restoreOrder(snapshot)
		end,
		onRemoveFromHotbar = function(toolKey: string)
			service:removeToolFromHotbar(toolKey)
		end,
		onEquip = function(toolKey: string)
			service:equip(toolKey)
		end,
		onHotbarAssignRejected = function()
			local maxSlots = PhoneLayout.getHotbarMaxSlots()
			NotifService.warn(("Hotbar holds at most %d items"):format(maxSlots), {
				dedupeKey = "hotbar-full",
			})
		end,
		onUnequipAll = function()
			local character = Players.LocalPlayer.Character
			if character then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid:UnequipTools()
					service:refresh()
				end
			end
		end,
	})

	local binder = HotbarUIBinder.new({
		refs = refsResult.value,
		store = InventoryStore,
		logger = Logger.new("HotbarUIBinder"),
		inventoryDrag = inventoryDrag,
	})

	if inventoryDrag then
		inventoryDrag:setHotbarPreviewCallback(function(slots)
			binder:renderHotbarSlots(slots, InventoryStore:get().hasTools)
		end)
	end

	if inventoryDrag then
		-- Track backpack open/close for reorder mode
		InventoryStore:subscribe("isBackpackOpen", function(isOpen: boolean)
			inventoryDrag:setBackpackOpen(isOpen)
		end)
	end

	if backpackRefsResult.ok then
		backpackBinder = BackpackUIBinder.new({
			refs = backpackRefsResult.value,
			store = InventoryStore,
			logger = Logger.new("BackpackUIBinder"),
			inventoryDrag = inventoryDrag,
		})
	end
	if Config.FeatureFlags.StickersEnabled == false and refsResult.value.stickerButtonWrapper then
		refsResult.value.stickerButtonWrapper.Visible = false
	end
	ensurePlayerGuiChild(playerGui, Config.Sticker.GUI_NAME, 10, hotbarLog)

	local stickerCtrl = nil
	if Config.FeatureFlags.StickersEnabled ~= false then
		stickerCtrl = trackClientLifecycle(
			"StickerController",
			StickerController.create({
				remotes = Remotes,
				logger = Logger.new("StickerController"),
			})
		)
		stickerCtrl:init()
		-- Register sticker panel here (stickerCtrl available in this scope)
		MobilePanelManager.register("sticker", Config.Sticker.GUI_NAME, function()
			stickerCtrl:closePanel()
		end)
	end
	binder:bindStickerRequested(function()
		if Config.FeatureFlags.StickersEnabled == false or not stickerCtrl then
			return
		end
		if stickerCtrl:isOpen() then
			stickerCtrl:closePanel()
			MobilePanelManager.close("sticker")
		else
			stickerCtrl:openPanel()
			MobilePanelManager.open("sticker")
		end
	end)
	local controller = trackClientLifecycle(
		"HotbarController",
		HotbarController.new({
			logger = Logger.new("HotbarController"),
			service = service,
			binder = binder,
			backpackBinder = backpackBinder,
			backpackButton = refsResult.value.backpackButton,
			inventoryDrag = inventoryDrag,
		})
	)
	controller:onStart()

	-- M-03: track ke _clientConnections agar di-disconnect saat script.Destroying
	table.insert(_clientConnections, Players.LocalPlayer.CharacterAdded:Connect(function()
		task.delay(0.4, function()
			if refsResult.value.root and refsResult.value.root.Parent then
				refsResult.value.root.ResetOnSpawn = false
				refsResult.value.root.Enabled = true
				if refsResult.value.stickerButtonWrapper then
					refsResult.value.stickerButtonWrapper.Visible = Config.FeatureFlags.StickersEnabled ~= false
				end
			end
			service:refresh()
		end)
	end))
end)
-- Sync dance + Lead Dance topbar: controller and requestSync handler must init in the same boot task.
if Config.FeatureFlags.SyncDanceEnabled then
	trackBootTask("SyncDanceBootstrap", function()
		local deferDanceWarmup = ClientBootConfig.DEFER_DANCE_WARMUP ~= false
		danceWarmupService = trackClientLifecycle(
			"DanceWarmupService",
			createDanceWarmupService.create({
				store = SyncStore,
				config = Config,
				logger = Logger.new("DanceWarmupService"),
				animationLoader = AnimationLoader,
				autoStart = not deferDanceWarmup,
			})
		)
		syncDanceController = trackClientLifecycle(
			"SyncController",
			createSyncController.create({
				store = SyncStore,
				config = Config,
				logger = Logger.new("SyncController"),
				danceWarmupService = danceWarmupService,
				animationLoader = AnimationLoader,
			})
		)

		local syncLeadIcon = Icon.new()
		syncLeadIcon:setLabel("Lead Dance")
		placeTopbarIconLeft(syncLeadIcon, Config.Music.TOPBAR_ORDER + 2)
		setCompactTopbarWidth(syncLeadIcon, 96)
		removeTopbarInnerPadding(syncLeadIcon)
		if type(syncLeadIcon.modifyTheme) == "function" then
			syncLeadIcon:modifyTheme({
				{ "IconImage", "Visible", false },
				{ "PaddingLeft", "Size", UDim2.fromScale(0, 1) },
			})
		end
		styleTopbarPill(syncLeadIcon)

		local function requestLeadDanceSync(targetUserId: number)
			task.spawn(function()
				local deadline = os.clock() + 8
				while os.clock() < deadline do
					if syncDanceController and type(syncDanceController.requestSyncByUserId) == "function" then
						syncDanceController:requestSyncByUserId(targetUserId)
						return
					end
					task.wait(0.1)
				end
				Logger.new("SyncDanceBootstrap"):warn("Lead Dance sync handler unavailable", {
					targetUserId = targetUserId,
				})
			end)
		end

		syncLeadTopbarController = trackClientLifecycle(
			"SyncLeadTopbarController",
			createSyncLeadTopbarController({
				icon = syncLeadIcon,
				iconFactory = function()
					return Icon.new()
				end,
				onRequestSyncToLeader = requestLeadDanceSync,
			})
		)
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local refs = DancePanelGuiRefs.resolve(playerGui, Config)
		local emotePanel = trackClientLifecycle(
			"DancePanelUIBinder",
			DancePanelUIBinder.new({
				refs = refs,
				config = Config,
			})
		)
		emotePanel:bindUnsyncRequested(function()
			syncDanceController:onUnsync()
		end)
		emotePanel:bindEmoteSelected(function(animation)
			syncDanceController:onEmoteSelected(animation)
			-- Important: Force UI update after state change to work around hot reload issues
			-- Get state directly from controller's store instance
			task.defer(function()
				local visualAnim = syncDanceController:getVisualAnimName()
				emotePanel:updateSyncAnimName(visualAnim)
			end)
		end)
		emotePanel:bindFavoriteToggle(function(animationName)
			syncDanceController:onFavoriteToggled(animationName)
			emotePanel:setFavorites(SyncStore:get().favoritedAnims)
		end)
		emotePanel:bindSpeedChanged(function(speed)
			syncDanceController:onSpeedChanged(speed)
		end)
		local function applySavedFavoritesAttribute(raw: any)
			if type(raw) ~= "string" then
				return
			end
			local ok, decoded = pcall(function()
				return HttpService:JSONDecode(raw)
			end)
			if ok and type(decoded) == "table" then
				SyncStore:set({ favoritedAnims = decoded })
				emotePanel:setFavorites(decoded, true)
			end
		end

		local localPlayer = Players.LocalPlayer
		applySavedFavoritesAttribute(localPlayer:GetAttribute(Config.Favorites.ATTRIBUTE_KEY))
		local favoritesAttrConn = localPlayer:GetAttributeChangedSignal(Config.Favorites.ATTRIBUTE_KEY):Connect(function()
			applySavedFavoritesAttribute(localPlayer:GetAttribute(Config.Favorites.ATTRIBUTE_KEY))
		end)
		trackClientLifecycle("FavoritesAttribute", {
			destroy = function()
				favoritesAttrConn:Disconnect()
			end,
		})
		emotePanel:setEmotes(
			AnimationLoader.getAnimationsByCategory("Dance"),
			AnimationLoader.getAnimationsByCategory("Pose")
		)
		emotePanel:setFavorites(SyncStore:get().favoritedAnims, true)
		local syncDanceSubscriptions =
			trackClientLifecycle("SyncDanceSubscriptions", createSubscriptionGroup("SyncDanceSubscriptions"))
		local function refreshSyncOverlay()
			local state = SyncStore:get()
			emotePanel:setSyncOverlay(state.isSyncing, state.leaderDisplay, state.visualAnim)
		end
		-- Dance panel stays above other UI; it does not use MobilePanelManager focus hiding.
		syncDanceSubscriptions:subscribe(SyncStore, "isPanelOpen", function(isOpen)
			emotePanel:setOpen(isOpen)
		end)
		syncDanceSubscriptions:subscribe(SyncStore, "favoritedAnims", function(favorites)
			emotePanel:setFavorites(favorites, true)
		end)
		syncDanceSubscriptions:subscribe(SyncStore, "isDancePreparing", function(isPreparing)
			emotePanel:setPreparingState(isPreparing)
		end)
		syncDanceSubscriptions:subscribe(SyncStore, "isSyncing", refreshSyncOverlay)
		syncDanceSubscriptions:subscribe(SyncStore, "syncTargetUserId", refreshSyncOverlay)
		emotePanel:setPreparingState(SyncStore:get().isDancePreparing)
		emotePanel:setCurrentSpeed(SyncStore:get().currentSpeed, true)
		emotePanel:setOpen(SyncStore:get().isPanelOpen, true)
		refreshSyncOverlay()
		syncDanceSubscriptions:subscribe(SyncStore, "visualAnim", function(animName)
			emotePanel:updateSyncAnimName(animName)
		end)
		syncDanceSubscriptions:subscribe(SyncStore, "leaderDisplay", function(leaderDisplay)
			if SyncStore:get().isSyncing then
				emotePanel:setSyncOverlay(true, leaderDisplay, SyncStore:get().visualAnim)
			end
		end)
		local triggerController = trackClientLifecycle(
			"SyncPanelTriggerController",
			createSyncPanelTriggerController.create({
				config = Config,
				logger = Logger.new("SyncPanelTriggerController"),
				onTriggered = function()
					syncDanceController:togglePanel()
				end,
			})
		)
		triggerController:init()
	end)
end
-- === AvatarContext ===
trackBootTask("CarryController.init", function()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local carryLog = Logger.new("Carry")
	local guiExists = ensurePlayerGuiChild(playerGui, Config.Carry.GUI_NAME, 10, carryLog)
	if not guiExists then
		carryLog:warn("GUI tidak ditemukan; carry disabled", { name = Config.Carry.GUI_NAME })
		return
	end

	local carryUI = trackClientLifecycle("CarryUI", createCarryUI({ logger = Logger.new("CarryUI") }))
	carryController = trackClientLifecycle(
		"CarryController",
		createCarryController.create({
			config = Config,
			logger = Logger.new("CarryController"),
			ui = carryUI,
			store = CarryStore,
			domain = CarryDomain,
		})
	)
	carryController:init()
end)

trackBootTask("AvatarContextController.init", function()
	local avatarContextUI = createAvatarContextUI({ logger = Logger.new("AvatarContextUI") })
	local avatarContextCtrl = trackClientLifecycle(
		"AvatarContextController",
		createAvatarContextController({
			logger = Logger.new("AvatarContextController"),
			ui = avatarContextUI,
			getCachedOverheadPayload = OverheadController.getCachedPayload,
		})
	)
	avatarContextUI:setCloseCallback(function()
		avatarContextCtrl:closePanel()
	end)
	avatarContextUI:setSyncDanceCallback(function(targetUserId: number)
		if not syncDanceController then
			return
		end
		-- When the viewer is a de facto lead and not syncing, route to transfer lead;
		-- otherwise run normal sync (including toggle-off when target is current leader).
		local localPlayer = Players.LocalPlayer
		local character = localPlayer and localPlayer.Character
		local isLeader = character and character:GetAttribute("IsLeader") == true
		local state = SyncStore:get()
		if isLeader and not state.isSyncing
			and type(syncDanceController.requestTransferLeadByUserId) == "function"
		then
			syncDanceController:requestTransferLeadByUserId(targetUserId)
		else
			syncDanceController:requestSyncByUserId(targetUserId)
		end
	end)
	avatarContextUI:setInvestigateAvatarCallback(function(targetUserId: number)
		avatarContextCtrl:inspectAvatar(targetUserId)
	end)
	avatarContextUI:setSendFriendRequestCallback(function(targetUserId: number)
		avatarContextCtrl:promptFriendRequest(targetUserId)
	end)
	avatarContextUI:setSendGiftCallback(function(targetUserId: number)
		if giftController and type(giftController.openForTarget) == "function" then
			giftController.openForTarget(targetUserId)
		end
	end)
	avatarContextUI:setCarryCallback(function(targetUserId: number)
		avatarContextCtrl:closePanel()
		local deadline = os.clock() + 2
		while carryController == nil and os.clock() < deadline do
			task.wait(0.05)
		end
		if carryController and type(carryController.requestCarryByUserId) == "function" then
			carryController:requestCarryByUserId(targetUserId)
		end
	end)
	avatarContextUI:setBeforeOpenCallback(function(): number
		return MobilePanelManager.notifyAcmOpen()
	end)
	if Config.FeatureFlags.SyncDanceEnabled and type(avatarContextUI.setSyncState) == "function" then
		local avatarSyncSubscriptions = trackClientLifecycle(
			"AvatarContextSyncSubscriptions",
			createSubscriptionGroup("AvatarContextSyncSubscriptions")
		)
		local function refreshAvatarSyncState()
			local state = SyncStore:get()
			avatarContextUI:setSyncState(state.isSyncing, state.syncTargetUserId)
		end
		avatarSyncSubscriptions:subscribe(SyncStore, "isSyncing", refreshAvatarSyncState)
		avatarSyncSubscriptions:subscribe(SyncStore, "syncTargetUserId", refreshAvatarSyncState)
		refreshAvatarSyncState()

		-- Mirror Character.IsLeader so Avatar Context sync action switches to Transfer Lead when followers exist.
		if type(avatarContextUI.setViewerIsLeader) == "function" then
			local localPlayer = Players.LocalPlayer
			local characterConn: RBXScriptConnection? = nil
			local function refreshLeaderFlag()
				local character = localPlayer.Character
				local isLeader = character ~= nil and character:GetAttribute("IsLeader") == true
				avatarContextUI:setViewerIsLeader(isLeader)
			end
			local function attachToCharacter(character: Model)
				if characterConn then
					characterConn:Disconnect()
				end
				characterConn = character:GetAttributeChangedSignal("IsLeader"):Connect(refreshLeaderFlag)
				refreshLeaderFlag()
			end
			if localPlayer.Character then
				attachToCharacter(localPlayer.Character)
			end
			-- Track via _clientConnections so a Rojo/Argon hot-reload disconnects
			-- this (otherwise the old closure kept firing attachToCharacter into a
			-- stale avatarContextUI/characterConn across reloads).
			table.insert(_clientConnections, localPlayer.CharacterAdded:Connect(attachToCharacter))
		end
	end
	avatarContextCtrl:init()
end)
-- Leaderboard tidak blocking loading screen — diinisialisasi di background
if Config.FeatureFlags.LeaderboardEnabled ~= false then
	task.spawn(function()
		DonationLeaderboardController.init({})
	end)
end

-- === Music Player ===
if Config.FeatureFlags.MusicPlayerEnabled then
	local _musicLog = Logger.new("MusicPlayer")
	local function createMusicPlayerController()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local guiExists = ensurePlayerGuiChild(playerGui, Config.Music.GUI_NAME, 10, _musicLog)
		if not guiExists then
			_musicLog:warn("GUI tidak ditemukan — panel disabled", { name = Config.Music.GUI_NAME })
			return nil
		end
		local refs = MusicPlayerGuiRefs.resolve(playerGui)
		local binder = MusicPlayerUIBinder.new({
			refs = refs,
			store = MusicPlayerStore,
			config = Config.Music,
		})
		return trackClientLifecycle(
			"MusicPlayerController",
			MusicPlayerController.create({
				refs = refs,
				store = MusicPlayerStore,
				binder = binder,
				remotes = Remotes,
				config = Config.Music,
				topbarIcon = musicTopbarIcon,
				logger = Logger.new("MusicPlayerController"),
			})
		)
	end
	local function runMusicEngineInit()
		_musicLog:info("Music boot task started")
		if musicPlayerController == nil then
			local ok, createdOrErr = pcall(createMusicPlayerController)
			if not ok then
				_musicLog:warn("Music controller create failed", { error = tostring(createdOrErr) })
				return
			end
			musicPlayerController = createdOrErr
		end
		if not musicPlayerController then
			_musicLog:warn("Music controller unavailable — skipping engine/panel init")
			return
		end
		if type(musicPlayerController.initEngine) == "function" then
			musicPlayerController:initEngine()
		end
		-- Panel bind + topbar icon wiring live in initPanel; deferred boot used to
		-- call initEngine only, so the Music topbar never appeared.
		if type(musicPlayerController.initPanel) == "function" then
			musicPlayerController:initPanel()
		elseif type(musicPlayerController.init) == "function" then
			musicPlayerController:init()
		end
		_musicLog:info("Music boot task finished", {
			engineInitialized = musicPlayerController._engineInitialized == true,
			panelInitialized = musicPlayerController._panelInitialized == true,
		})
	end
	-- Do not queue behind Hotbar/SyncDance (boot slot 12). Spawn directly so init
	-- is not blocked by slower interactive tasks ahead in the scheduler.
	task.spawn(function()
		local delaySeconds = 0
		if ClientBootConfig.DEFER_MUSIC_PLAYER ~= false then
			delaySeconds = math.max(0, tonumber(ClientBootConfig.MUSIC_ENGINE_DELAY_AFTER_GAMEPLAY) or 0)
		end
		if delaySeconds > 0 then
			task.wait(delaySeconds)
		end
		runMusicEngineInit()
	end)
end
if Config.FeatureFlags.SyncDanceEnabled then
	local deferDanceWarmup = ClientBootConfig.POST_GAMEPLAY_DANCE_WARMUP ~= false
		and ClientBootConfig.DEFER_DANCE_WARMUP ~= false
	if deferDanceWarmup then
		trackPostGameplayBootTask("DanceWarmup.tier1", function()
			local delaySeconds = math.max(0, tonumber(ClientBootConfig.DANCE_TIER1_DELAY_AFTER_GAMEPLAY) or 0.5)
			if delaySeconds > 0 then
				task.wait(delaySeconds)
			end
			if danceWarmupService and type(danceWarmupService.beginWarmup) == "function" then
				danceWarmupService:beginWarmup(nil, "tier1")
			end
		end)
		trackPostGameplayBootTask("DanceWarmup.tier2", function()
			local deadline = os.clock() + 30
			while danceWarmupService and danceWarmupService.tier1Complete ~= true and os.clock() < deadline do
				task.wait(0.1)
			end
			if danceWarmupService and type(danceWarmupService.beginWarmup) == "function" then
				danceWarmupService:beginWarmup(nil, "tier2")
			end
		end)
	end
end
loadingBootReady = true
clientBootScheduler:setInteractiveComplete()
requestFinishLoadingScreen()
if LOADING_SCREEN_ENABLED then
	task.delay(LoadingConfig.FALLBACK_FINISH_DELAY, function()
		if not loadingFinished then
			warn("[LoadingScreen] Fallback finish triggered")
			finishLoadingScreen()
		end
	end)
end
