--!strict
-- PATH: ServerScriptService/Server/Main.server.lua
-- Entry point server. Wire semua dependencies di sini.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local KitProduct = require(ReplicatedStorage.Hazastudio_ClubKit.KitProduct)

-- Module bag: keeps Main under Luau 200-local register limit.
local ServerMods = require(script.Parent.Init.ServerModuleBag)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local ConsoleBanner = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.ConsoleBanner)
local Lifecycle = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Lifecycle)
local provisionEarlyRemotes = require(script.Parent.Init.EarlyRemotes)
local Cleaner = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cleaner)
local Cache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cache)
-- Persistence Fabric: one Main local only (Luau register limit). Internals live in Init/.
local PersistenceFabricHooks = require(script.Parent.Init.PersistenceFabricHooks)
local log = Logger.new(KitProduct.LogTag)
ConsoleBanner.printOnce(KitProduct)
-- Tracks top-level Players.PlayerAdded/PlayerRemoving connections so a Rojo
-- hot-reload (which fires script.Destroying) can disconnect them. Without this
-- each reload stacked duplicate handlers that leaked stale service closures.
local connectionCleaner = Cleaner.new()
log:info("Hazastudio Clubkit server boot", {
	productId = KitProduct.ProductId,
	version = KitProduct.KitVersion,
	buildId = KitProduct.BuildId,
})
do
	local kitFolder = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKit")
	if kitFolder then
		kitFolder:SetAttribute("ProductId", KitProduct.ProductId)
		kitFolder:SetAttribute("KitVersion", KitProduct.KitVersion)
		kitFolder:SetAttribute("Vendor", KitProduct.Vendor)
	end
end
if Config.DataStoreScope.IS_STUDIO and Config.DataStoreScope.USE_STUDIO_ISOLATION then
	log:info("DataStore scope: Studio (isolated from live, persists across Studio restarts)", {
		prefix = Config.DataStoreScope.PREFIX,
		robuxLeaderboard = Config.Leaderboards.ROBUX_USER_ORDERED_KEY,
		overhead = Config.DataStore.OVERHEAD_KEY,
		settings = Config.Settings.DATASTORE_KEY,
	})
elseif Config.DataStoreScope.IS_STUDIO then
	log:warn("DataStore scope: LIVE production keys from Studio — testing akan mengubah data player asli", {
		robuxLeaderboard = Config.Leaderboards.ROBUX_USER_ORDERED_KEY,
		overhead = Config.DataStore.OVERHEAD_KEY,
		settings = Config.Settings.DATASTORE_KEY,
	})
else
	log:info("DataStore scope: Live (production keys)", {
		isStudioSession = Config.DataStoreScope.IS_STUDIO,
		robuxLeaderboard = Config.Leaderboards.ROBUX_USER_ORDERED_KEY,
		overhead = Config.DataStore.OVERHEAD_KEY,
		settings = Config.Settings.DATASTORE_KEY,
	})
end

do
	local BrandLogoApplier = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BrandLogoApplier)
	local Workspace = game:GetService("Workspace")
	local StarterGui = game:GetService("StarterGui")
	local stats = BrandLogoApplier.applyRoots({ Workspace, StarterGui }, Config)
	connectionCleaner:add(BrandLogoApplier.watch(Workspace, Config))
	connectionCleaner:add(BrandLogoApplier.watch(StarterGui, Config))
	log:info("Brand logo applied", {
		matched = stats.matched,
		mutated = stats.mutated,
		targetLogo = stats.targetLogo,
		defaultLogo = stats.defaultLogo,
		sameAsDefault = stats.targetLogo == stats.defaultLogo,
	})
	if stats.targetLogo == stats.defaultLogo then
		log:warn("Branding.LogoImage masih ID bawaan kit — ganti di ClubKitConfig.Branding.LogoImage supaya logo berubah")
	end
end

local Secrets = require(ServerScriptService.Hazastudio_ClubKitSecrets.Secrets)
local donationApiUrl = if type(Config.Donation) == "table" then Config.Donation.SHEETS_WEB_APP_URL else ""
if type(donationApiUrl) == "string" and donationApiUrl ~= "" then
	if type(Secrets.DonationApiSecret) ~= "string" or Secrets.DonationApiSecret == "" then
		log:warn("Donation ApiUrl configured but Secrets.DonationApiSecret is empty — HTTP calls will be skipped")
	end
end
local gameDataApi = Config.GameDataApi
if type(gameDataApi) == "table" and type(gameDataApi.BASE_URL) == "string" and gameDataApi.BASE_URL ~= ""
	and gameDataApi.GROUPS_ENDPOINT_ENABLED == true
then
	if type(Secrets.GameDataApiSecret) ~= "string" or Secrets.GameDataApiSecret == "" then
		log:debug("GameDataApi secret kosong — worker calls akan di-skip (normal di Studio tanpa Secrets)")
	end
end

local donationApiReady = type(donationApiUrl) == "string"
	and donationApiUrl ~= ""
	and type(Secrets.DonationApiSecret) == "string"
	and Secrets.DonationApiSecret ~= ""

if KitProduct.LicenseEnforcementEnabled == true then
	ServerMods.LicenseService.start({
		apiUrl = donationApiUrl,
		secret = Secrets.DonationApiSecret,
	})
	ServerMods.LicenseService.awaitInitialCheck(10)
	local licenseState = ServerMods.LicenseService.getState()
	if licenseState.lastError then
		log:warn("License verify on boot", {
			status = licenseState.status,
			error = licenseState.lastError,
		})
	else
		log:info("License verify on boot", { status = licenseState.status })
	end
end

local serverLifecycle = Lifecycle.new(Logger.new("ServerLifecycle"))
local eventBus = ServerMods.EventBus.new()

local function trackLifecycle(name: string, module: any): any
	return serverLifecycle:register(name, module)
end
-- ============================================================
-- SETUP FOLDER REMOTES
-- ============================================================
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
Remotes = Remotes :: Folder

local function ensureRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing:IsA("RemoteEvent") then
			return existing
		end
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function ensureUnreliableRemoteEvent(parent: Instance, name: string): UnreliableRemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing:IsA("UnreliableRemoteEvent") then
			return existing
		end
		existing:Destroy()
	end

	local remote = Instance.new("UnreliableRemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end
-- ============================================================
-- SETUP REMOTE: Notify
-- FireClient = side effect, bukan pure util -> wire di entry point.
-- ============================================================
local NotifyRemote = ensureRemoteEvent(Remotes, "Notify")
-- Dibuat awal agar client OverheadController bisa subscribe sebelum boot server berat selesai.
ensureRemoteEvent(Remotes, "OverheadUpdate")
ensureRemoteEvent(Remotes, (Config.ClientBoot :: any).CLIENT_GAMEPLAY_READY_REMOTE or "ClientGameplayReady")
local GenericBroadcastRemote = ensureRemoteEvent(Remotes, Config.Announcement.REMOTE_BROADCAST)
local JoinGreetingRemote = ensureRemoteEvent(Remotes, (Config.JoinGreeting and Config.JoinGreeting.REMOTE) or "JoinGreeting")
local joinCommunityPromptCfg = Config.JoinCommunityPrompt or {}
ensureRemoteEvent(Remotes, tostring(joinCommunityPromptCfg.REMOTE_REQUEST or "JoinCommunityMembersRequest"))
ensureRemoteEvent(Remotes, tostring(joinCommunityPromptCfg.REMOTE_RESPONSE or "JoinCommunityMembersResponse"))
ensureRemoteEvent(Remotes, tostring(joinCommunityPromptCfg.REMOTE_VIP_RECHECK or "CommunityVipRecheck"))
ensureRemoteEvent(Remotes, Config.PaidBroadcast.REMOTE_SUBMIT)
local _PaidBroadcastResultRemote = ensureRemoteEvent(Remotes, Config.PaidBroadcast.REMOTE_RESULT)
-- Create UnreliableRemoteEvent untuk cosmetic data (particles, VFX hints)
local CosmeticRemote: UnreliableRemoteEvent
do
	local existing = Remotes:FindFirstChild("Cosmetic")
	if existing and existing:IsA("UnreliableRemoteEvent") then
		CosmeticRemote = existing :: UnreliableRemoteEvent
	else
		if existing then
			existing:Destroy()
		end
		local r = Instance.new("UnreliableRemoteEvent")
		r.Name = "Cosmetic"
		r.Parent = Remotes
		CosmeticRemote = r
	end
end
local ShopGrantRemote = ensureRemoteEvent(Remotes, "ShopGrantNotif")
ensureRemoteEvent(Remotes, "ShopGiftPending")
-- Donation remotes
ensureRemoteEvent(Remotes, Config.Hotbar.REMOTE_TOOLS_SYNCED)
ensureRemoteEvent(Remotes, Config.Hotbar.REMOTE_TOOLS_REQUEST_SYNC)
local DonationNotifRemote = ensureRemoteEvent(Remotes, Config.Donation.REMOTE_NOTIFICATION)
local DonationLeaderboardRemote = ensureRemoteEvent(Remotes, Config.Donation.REMOTE_LEADERBOARD_UPDATED)
ensureRemoteEvent(Remotes, Config.Donation.REMOTE_ROBUX_INIT)
ensureRemoteEvent(Remotes, Config.Donation.REMOTE_ROBUX_RESULT)
ensureRemoteEvent(Remotes, Config.Donation.REMOTE_ROBUX_PRODUCTS)
ensureRemoteEvent(Remotes, Config.Donation.REMOTE_ROBUX_PRODUCTS_RESPONSE)
ensureRemoteEvent(Remotes, Config.Donation.REMOTE_DONOR_PROFILE)
ensureRemoteEvent(Remotes, Config.Donation.REMOTE_DONOR_PROFILE_RESPONSE)
-- World-position nuke VFX (Nuke/Smite/BlackHole). Unreliable — cosmetic-only, may drop under congestion.
ensureUnreliableRemoteEvent(Remotes, (Config.Donation :: any).NUKE_REMOTE or "DonationEffect")
local WorkspaceLeaderboardsRemote = ensureRemoteEvent(Remotes, Config.Leaderboards.REMOTE_UPDATED)
local WorkspaceLeaderboardsSnapshotRemote = ensureRemoteEvent(Remotes, Config.Leaderboards.REMOTE_SNAPSHOT)
local WorkspaceLeaderboardsSnapshotResponseRemote =
	ensureRemoteEvent(Remotes, Config.Leaderboards.REMOTE_SNAPSHOT_RESPONSE)
-- AvatarContext remotes
ensureRemoteEvent(Remotes, "AvatarContextRequest")
ensureRemoteEvent(Remotes, "AvatarContextResponse")
local ProfileUpdatedRemote = ensureRemoteEvent(Remotes, Config.AvatarContext.REMOTE_PROFILE_UPDATED)
local AvatarContextCloseRemote = ensureRemoteEvent(Remotes, Config.AvatarContext.REMOTE_CLOSE)
local AvatarContextUpdatedRemote = ensureRemoteEvent(Remotes, Config.AvatarContext.REMOTE_UPDATED)
local AvatarContextLikeRequestRemote = ensureRemoteEvent(Remotes, Config.AvatarContext.REMOTE_LIKE_REQUEST)
local AvatarContextLikeResultRemote = ensureRemoteEvent(Remotes, Config.AvatarContext.REMOTE_LIKE_RESULT)
local AvatarLikeEffectRemote = ensureRemoteEvent(Remotes, Config.AvatarContext.REMOTE_LIKE_EFFECT)
ensureRemoteEvent(Remotes, Config.Sticker.REMOTE_SET)
ensureRemoteEvent(Remotes, Config.Sticker.REMOTE_CLEAR)
ensureRemoteEvent(Remotes, Config.Sticker.REMOTE_ADD)
ensureRemoteEvent(Remotes, Config.Sticker.REMOTE_REQUEST)
ensureRemoteEvent(Remotes, Config.Sticker.REMOTE_SYNC)
ensureRemoteEvent(Remotes, Config.AfkGuard.REMOTE_REQUEST or "AfkRejoinRequest")
-- Settings remotes
ensureRemoteEvent(Remotes, Config.Settings.REMOTE_REQUEST)
ensureRemoteEvent(Remotes, Config.Settings.REMOTE_SYNC)
ensureRemoteEvent(Remotes, Config.Settings.REMOTE_UPDATE)
ensureRemoteEvent(Remotes, Config.Settings.REMOTE_RESET)
ensureRemoteEvent(Remotes, Config.ProfileMenu.REMOTE_REQUEST)
ensureRemoteEvent(Remotes, Config.ProfileMenu.REMOTE_SYNC)
ensureRemoteEvent(Remotes, Config.ProfileMenu.REMOTE_UPDATE)
-- Music remotes (early so client MusicPlayerController can bind before MusicService loads)
if Config.FeatureFlags.MusicPlayerEnabled then
	local musicConfig = Config.Music
	ensureRemoteEvent(Remotes, musicConfig.REMOTE_TRACK_CHANGED)
	ensureRemoteEvent(Remotes, musicConfig.REMOTE_QUEUE_UPDATED)
	ensureRemoteEvent(Remotes, musicConfig.REMOTE_STATE_SYNC)
	ensureRemoteEvent(Remotes, musicConfig.REMOTE_VOTE_STATE)
	ensureRemoteEvent(Remotes, musicConfig.REMOTE_DURATION_REPORT)
	ensureRemoteEvent(Remotes, musicConfig.REMOTE_VOTE_SKIP)
	ensureRemoteEvent(Remotes, musicConfig.REMOTE_REQUEST_TRACK)
	ensureRemoteEvent(Remotes, musicConfig.REMOTE_ADMIN_SKIP)
	ensureRemoteEvent(Remotes, musicConfig.REMOTE_REPORT_FAILURE)
	ensureRemoteEvent(Remotes, musicConfig.REMOTE_RESPONSE)
	ensureRemoteEvent(Remotes, musicConfig.REMOTE_GET_STATE)
	ensureRemoteEvent(Remotes, musicConfig.REMOTE_GET_PLAYLISTS)
	ensureRemoteEvent(Remotes, musicConfig.REMOTE_GET_TRACKS)
	ensureRemoteEvent(Remotes, musicConfig.REMOTE_FAVORITE_TRACK)
	ensureRemoteEvent(Remotes, musicConfig.REMOTE_FAVORITES_SYNC)
	ensureRemoteEvent(Remotes, musicConfig.REMOTE_SET_DJ_MODE)
	ensureRemoteEvent(Remotes, musicConfig.REMOTE_DJ_EFFECT)
	ensureRemoteEvent(Remotes, musicConfig.REMOTE_MANAGE_PLAYLIST)
	ensureRemoteEvent(Remotes, musicConfig.REMOTE_MANAGE_TRACK)
	ensureRemoteEvent(Remotes, musicConfig.REMOTE_ZONE_CHANGED)
end
-- Late-bound controller remotes: create early so client boot does not wait on heavy server wiring.
provisionEarlyRemotes(ReplicatedStorage, Remotes, Config)
-- Interface Notify - inject ke controller sebagai deps
type NotifyPayload = {
	message: string,
	notifType: string?,
	title: string?,
	description: string?,
	domain: string?,
	dedupeKey: string?,
	duration: number?,
	iconImage: string?,
}

type NotifyInput = string | NotifyPayload

export type INotify = {
	player: (player: Player, messageOrPayload: NotifyInput, notifType: string?) -> (),
	all: (messageOrPayload: NotifyInput, notifType: string?) -> (),
}

local function normalizeNotifyPayload(
	messageOrPayload: NotifyInput,
	notifType: string?,
	defaultType: string
): NotifyPayload?
	if type(messageOrPayload) == "string" then
		if messageOrPayload == "" then
			return nil
		end

		return {
			message = messageOrPayload,
			notifType = notifType or defaultType,
		}
	end

	if type(messageOrPayload) ~= "table" then
		return nil
	end

	local rawMessage = messageOrPayload.message
	if type(rawMessage) ~= "string" or rawMessage == "" then
		return nil
	end

	local payload = table.clone(messageOrPayload) :: NotifyPayload
	payload.notifType = notifType or payload.notifType or defaultType
	return payload
end

-- ── ServerMods.NetworkManager — per-frame batched transport ─────────────
-- Batches all outbound FireClient calls within a frame into a
-- single Heartbeat flush. Reduces per-call overhead at high CCU.
-- See: Guidelines/REF_ARCHITECTURE.md (Network Transport section)
local networkManager = ServerMods.NetworkManager.create({
	reliable = NotifyRemote,
	unreliable = CosmeticRemote,
	logger = Logger.new("NetworkManager"),
	isServer = true,
})

local Notify: INotify = {
	player = function(player: Player, messageOrPayload: NotifyInput, notifType: string?)
		local payload = normalizeNotifyPayload(messageOrPayload, notifType, "INFO")
		if not payload then
			return
		end
		-- v2.1: batched via ServerMods.NetworkManager
		networkManager:fireClient(player, payload)
	end,
	all = function(messageOrPayload: NotifyInput, notifType: string?)
		local payload = normalizeNotifyPayload(messageOrPayload, notifType, "SYSTEM")
		if not payload then
			return
		end
		-- v2.1: batched via ServerMods.NetworkManager
		networkManager:fireAllClients(payload)
	end,
}
-- ============================================================
-- WIRING DEPENDENCIES
-- ============================================================
local repo = ServerMods.OverheadRepository
local aboutRosterRepository = ServerMods.createAboutRosterRepository()
local profileRepo = ServerMods.ProfileRepository.new({ logger = Logger.new("ProfileRepository") })
local avatarLikeRepository = ServerMods.AvatarLikeRepository.new({ logger = Logger.new("AvatarLikeRepository") })
local donationLeaderboardRepository =
	ServerMods.DonationLeaderboardRepository.new({ logger = Logger.new("DonationLeaderboardRepository") })
local giftPendingRepository = ServerMods.GiftPendingRepository.create({
	logger = Logger.new("GiftPendingRepository"),
})
local manualBagibagiRepository = ServerMods.ManualBagibagiRepository.create({
	logger = Logger.new("ManualBagibagiRepository"),
})

-- DonationEffectService is constructed after CinematicDockController so the
-- camera trigger callback can be wired in.
local profileSocialService = ServerMods.createProfileSocialService({ logger = Logger.new("ProfileSocialService") })
local settingsRepo = ServerMods.SettingsRepository
local settingsService = ServerMods.createSettingsService({
	logger = Logger.new("SettingsService"),
	repo = settingsRepo,
})
local profileCommandService = ServerMods.createProfileCommandService({
	logger = Logger.new("ProfileCommandService"),
	profileRepository = profileRepo,
})
-- PlayerSnapshotService: in-memory cache for fast ACM lookups
local playerSnapshotService = ServerMods.createPlayerSnapshotService.create({
	logger = Logger.new("PlayerSnapshotService"),
})
-- BackgroundJobScheduler: centralized periodic job management
local backgroundJobScheduler = ServerMods.createBackgroundJobScheduler.create({
	logger = Logger.new("BackgroundJobScheduler"),
})
local overheadService = ServerMods.createOverheadService({
	repo = repo,
	avatarLikeRepository = avatarLikeRepository,
	profileRepository = profileRepo,
	profileCommandService = profileCommandService,
	aboutRosterRepository = aboutRosterRepository,
	donationLeaderboardRepository = donationLeaderboardRepository,
	donationService = nil :: any, -- assigned post-init via overheadService:setDonationService
})
local profileMenuService = ServerMods.createProfileMenuService({
	logger = Logger.new("ProfileMenuService"),
	profileRepository = profileRepo,
	overheadRepository = repo,
	profileCommandService = profileCommandService,
})
local avatarContextService = ServerMods.createAvatarContextService({
	logger = Logger.new("AvatarContextService"),
	overheadService = overheadService,
	profileSocialService = profileSocialService,
	profileRepository = profileRepo,
	profileCommandService = profileCommandService,
	avatarLikeRepository = avatarLikeRepository,
	playerSnapshotService = playerSnapshotService,
})
local avatarLikeService = ServerMods.createAvatarLikeService({
	logger = Logger.new("AvatarLikeService"),
	avatarLikeRepository = avatarLikeRepository,
})
local carryService = trackLifecycle(
	"CarryService",
	ServerMods.createCarryService({
		config = Config,
		domain = ServerMods.CarryDomain,
		logger = Logger.new("CarryService"),
	})
)
local gravityService: any = nil
if Config.FeatureFlags.GravityEnabled ~= false then
	gravityService = trackLifecycle(
		"GravityService",
		ServerMods.createGravityService({
			carryService = carryService,
			notify = Notify,
		})
	)
end
local stickerService = trackLifecycle(
	"StickerService",
	ServerMods.createStickerService.new({
		logger = Logger.new("StickerService"),
		repository = ServerMods.StickerRepository,
		-- profileLoader wired after SharedProfileLoader is created (before startAll).
	})
)
trackLifecycle(
	"RoleToolService",
	ServerMods.RoleToolService.new({
		logger = Logger.new("RoleToolService"),
		eventBus = eventBus,
		overheadService = overheadService,
	})
)
local _giftService = ServerMods.createGiftService({
	repo = repo,
	overheadService = overheadService,
})
local streakService = ServerMods.createStreakService({ repo = repo })
local levelService: any = nil
if Config.FeatureFlags.LevelSystemEnabled then
	levelService = ServerMods.createLevelService({ repo = repo })
end
local coupleService = trackLifecycle("CoupleService", ServerMods.createCoupleService({ repo = repo }))
local playerLookupService = ServerMods.createPlayerLookupService()
local chatCommandService = ServerMods.createChatCommandService()
local genericBroadcastNetwork = ServerMods.NetworkManager.create({
	reliable = GenericBroadcastRemote,
	logger = Logger.new("GenericBroadcastNetwork"),
	isServer = true,
})
local genericBroadcastService = ServerMods.createGenericBroadcastService({
	broadcastNetwork = genericBroadcastNetwork,
	overheadService = overheadService,
	logger = Logger.new("GenericBroadcastService"),
})
local joinGreetingNetwork = ServerMods.NetworkManager.create({
	reliable = JoinGreetingRemote,
	logger = Logger.new("JoinGreetingNetwork"),
	isServer = true,
})
local joinGreetingService = trackLifecycle(
	"JoinGreetingService",
	ServerMods.createJoinGreetingService({
		broadcastNetwork = joinGreetingNetwork,
		overheadService = overheadService,
		logger = Logger.new("JoinGreetingService"),
	})
)
trackLifecycle(
	"JoinCommunityMembersService",
	ServerMods.createJoinCommunityMembersService({
		remotes = Remotes,
		logger = Logger.new("JoinCommunityMembersService"),
	})
)
local giftGrantNetwork = ServerMods.NetworkManager.create({
	reliable = ShopGrantRemote,
	logger = Logger.new("GiftGrantNetwork"),
	isServer = true,
})
local paidBroadcastResultNetwork = ServerMods.NetworkManager.create({
	reliable = _PaidBroadcastResultRemote,
	logger = Logger.new("PaidBroadcastResultNetwork"),
	isServer = true,
})
local _paidBroadcastController = ServerMods.createPaidBroadcastController({
	remotes = Remotes,
	notify = Notify,
	genericBroadcastService = genericBroadcastService,
	resultNetwork = paidBroadcastResultNetwork,
})
_paidBroadcastController:init()
local _cinematicDockController = ServerMods.createCinematicDockController({
	remotes = Remotes,
	notify = Notify,
	overheadService = overheadService,
})
-- DonationEffectService relies on CinematicDockController for the camera
-- trigger. The callback runs whenever a tier has `cameraDuration > 0`.
local donationEffectService = ServerMods.createDonationEffectService({
	logger = Logger.new("DonationEffectService"),
	cameraTrigger = function(targetPlayer: Player, durationSeconds: number)
		if _cinematicDockController and type(_cinematicDockController.focusOnPlayer) == "function" then
			_cinematicDockController.focusOnPlayer(targetPlayer, durationSeconds)
		end
	end,
})

local syncService = nil
local syncFavoritesRepo = nil
local musicFavoritesRepo = nil
-- Hoisted so script.Destroying can call musicService:destroy() (MusicService is
-- created inside the MusicPlayerEnabled block and not registered via trackLifecycle).
local _musicService = nil
-- ============================================================
-- INTEREST MANAGER + PROXIMITY SERVICE (P0-1, R1.3)
-- Exactly ONE shared instance injected into both OverheadController
-- and SyncService (composition-root rule — never instantiated elsewhere).
-- ============================================================
local interestManager = ServerMods.InterestManager.create({
	logger = Logger.new("InterestManager"),
})
local proximityService = ServerMods.createProximityInterestService.create({
	interest = interestManager,
	config = Config.Interest,
	logger = Logger.new("ProximityInterestService"),
})
local overheadController = ServerMods.createOverheadController({
	service = overheadService,
	remotes = Remotes, -- inject Remotes folder ke factory
	eventBus = eventBus,
	proximity = proximityService,   -- R1.3: shared ProximityInterestService
	interest = interestManager,     -- R1.3: shared ServerMods.InterestManager
	playerSnapshotService = playerSnapshotService,
})
local communityVipService = trackLifecycle(
	"CommunityVipService",
	ServerMods.createCommunityVipService({
		repo = repo,
		overheadController = overheadController,
		overheadService = overheadService,
		remotes = Remotes,
		logger = Logger.new("CommunityVipService"),
	})
)
local streakController = ServerMods.createStreakController({
	streakService = streakService,
	overheadController = overheadController,
	remotes = Remotes,
})
-- Join-time DataStore read serialization. All heavy per-player reads that run on
-- PlayerAdded go through this single queue so a join storm does not fan out
-- hundreds of concurrent DataStore requests and saturate the per-server budget.
local sharedProfileLoader = ServerMods.ProfileLoader.create({
	logger = Logger.new("SharedProfileLoader"),
	concurrency = Config.ProfileLoader.MAX_CONCURRENCY,
	perPlayerConcurrency = Config.ProfileLoader.PER_PLAYER_CONCURRENCY,
})
sharedProfileLoader:register("overhead", function(player: Player)
	return repo:loadStrict(player.UserId)
end)
sharedProfileLoader:register("profile", function(player: Player)
	return profileRepo:load(player.UserId)
end)
sharedProfileLoader:register("likes_summary", function(player: Player)
	return avatarLikeRepository:getSummary(player.UserId)
end)
-- Dance favorites must be registered before the first enqueue so SyncDance join
-- does not need a second sharedProfileLoader:enqueue (which duplicated reads).
if Config.FeatureFlags.SyncDanceEnabled then
	syncFavoritesRepo = ServerMods.FavoritesRepository.new({
		config = Config.Favorites,
		logger = Logger.new("FavoritesRepository"),
	})
	sharedProfileLoader:register("favorites", function(player: Player)
		syncFavoritesRepo:onPlayerAdded(player)
		return ServerMods.Result.Ok(true)
	end)
end
-- Overhead join recovery: re-enqueue through ProfileLoader only (no parallel
-- repo:loadStrict). ProfileLoader already retries transient errors with delays
-- >= NEGATIVE_CACHE_TTL; this path covers a final deferred requeue after those
-- in-job retries are exhausted.
local OVERHEAD_JOIN_REQUEUE_DELAY_SEC = 10
local overheadJoinRequeueCount: { [number]: number } = {}
local OVERHEAD_JOIN_REQUEUE_MAX = 2

sharedProfileLoader:onLoaded(function(event)
	if event.kind ~= "overhead" or not event.player.Parent then
		return
	end
	if event.result.ok then
		overheadJoinRequeueCount[event.player.UserId] = nil
		overheadController:onPlayerDataReady(event.player)
		streakController:processLoginForPlayer(event.player)
		if joinGreetingService and type(joinGreetingService.onPlayerReady) == "function" then
			joinGreetingService:onPlayerReady(event.player)
		end
		if communityVipService and type(communityVipService.onPlayerReady) == "function" then
			communityVipService:onPlayerReady(event.player)
		end
		return
	end

	local userId = event.player.UserId
	local attempts = overheadJoinRequeueCount[userId] or 0
	if attempts >= OVERHEAD_JOIN_REQUEUE_MAX then
		log:warn("Overhead join requeue exhausted", {
			userId = userId,
			error = event.result.error,
		})
		return
	end
	overheadJoinRequeueCount[userId] = attempts + 1
	local player = event.player
	task.delay(OVERHEAD_JOIN_REQUEUE_DELAY_SEC, function()
		if not player.Parent then
			overheadJoinRequeueCount[userId] = nil
			return
		end
		log:info("Overhead join requeue via ProfileLoader", {
			userId = userId,
			attempt = overheadJoinRequeueCount[userId],
			error = event.result.error,
		})
		sharedProfileLoader:enqueueKind(player, "overhead")
	end)
end)
-- Critical join kinds only (overhead + profile). Secondary kinds
-- (likes_summary, favorites, settings, stickers, music_favorites) are deferred
-- so join storms do not saturate DataStoreScheduler GetAsync slots.
local function enqueueCriticalJoinLoads(player: Player)
	sharedProfileLoader:enqueueKind(player, "overhead")
	sharedProfileLoader:enqueueKind(player, "profile")
end

local function enqueueSecondaryJoinLoads(player: Player)
	sharedProfileLoader:enqueueKindDeferred(player, "likes_summary")
	if Config.FeatureFlags.SyncDanceEnabled then
		sharedProfileLoader:enqueueKindDeferred(player, "favorites")
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	enqueueCriticalJoinLoads(player)
	enqueueSecondaryJoinLoads(player)
end
connectionCleaner:add(Players.PlayerAdded:Connect(function(player)
	enqueueCriticalJoinLoads(player)
	enqueueSecondaryJoinLoads(player)
end))
connectionCleaner:add(Players.PlayerRemoving:Connect(function(player)
	overheadJoinRequeueCount[player.UserId] = nil
end))
-- warmPlayerSocialSnapshot is defined after AvatarContextController (needs pushContextUpdate).
local shopService = ServerMods.createShopService({
	repo = repo,
	logger = Logger.new("ShopService"),
	giftPendingRepository = giftPendingRepository,
})
local membershipCommandService = ServerMods.createMembershipCommandService({
	repo = repo,
	overheadService = overheadService,
})
local communityCommandService = ServerMods.createCommunityCommandService({
	repo = repo,
	overheadService = overheadService,
})
-- Late-bound bridge so AdminController can push a live profile-menu refresh
-- after it mutates overhead-backed profile fields (e.g. specialTitle). The
-- ProfileMenuController is constructed later; we populate `syncPlayer` then.
local profileMenuSync: { syncPlayer: ((Player) -> ())? } = { syncPlayer = nil }
local _adminController = ServerMods.createAdminController({
	repo = repo,
	overheadService = overheadService,
	overheadController = overheadController,
	grantRemote = ShopGrantRemote,
	notify = Notify,
	remotes = Remotes,
	membershipCommandService = membershipCommandService,
	playerLookupService = playerLookupService, -- DI fixed: inject lookup service
	profileMenuSync = profileMenuSync,
})
if Config.FeatureFlags.CouplesEnabled ~= false then
	ServerMods.createCoupleController({
		coupleService = coupleService,
		overheadController = overheadController,
		repo = repo,
		notify = Notify,
		remotes = Remotes,
		profileRepository = profileRepo,
		profileMenuSync = profileMenuSync,
	})
end
-- DonationService is constructed before ShopController because ShopController
-- needs `recordRobuxDonationDaily()` to update the daily Robux leaderboard.
local workspaceLeaderboardRefresh: { refresh: (() -> ())? } = { refresh = nil }
local donationLeaderboardNetwork = ServerMods.NetworkManager.create({
	reliable = DonationLeaderboardRemote,
	logger = Logger.new("DonationLeaderboardNetwork"),
	isServer = true,
})
local donationNotifNetwork = ServerMods.NetworkManager.create({
	reliable = DonationNotifRemote,
	logger = Logger.new("DonationNotifNetwork"),
	isServer = true,
})
local donationService = ServerMods.createDonationService({
		repo = repo,
		overheadController = overheadController,
		overheadService = overheadService,
		leaderboardNetwork = donationLeaderboardNetwork,
		notifNetwork = donationNotifNetwork,
		notify = Notify,
		donationEffectService = donationEffectService,
		donationLeaderboardRepository = donationLeaderboardRepository,
		profileRepository = profileRepo,
		manualBagibagiRepository = manualBagibagiRepository,
		backgroundJobScheduler = backgroundJobScheduler,
		donationPollJobName = "donation_poll",
	})
if type(overheadService.setDonationService) == "function" then
	overheadService:setDonationService(donationService)
end
-- Wire async cash-donation updates back into the overhead refresh loop.
if type(overheadService.setCashStatsReadyCallback) == "function" then
	overheadService:setCashStatsReadyCallback(function(userId: number)
		local player = Players:GetPlayerByUserId(userId)
		if player and overheadController and type(overheadController.refreshPlayer) == "function" then
			overheadController:refreshPlayer(player)
		end
		if player and joinGreetingService and type(joinGreetingService.onPayloadUpdated) == "function" then
			joinGreetingService:onPayloadUpdated(player)
		end
	end)
end
-- Register background jobs via scheduler instead of inline loops
if backgroundJobScheduler then
	-- Donation notification polling - respects NOTIF_POLL_INTERVAL from config
	if donationService and type(donationService.pollDonations) == "function" then
		local notifInterval = (Config.Donation and Config.Donation.NOTIF_POLL_INTERVAL) or 5
		local cashEnabled = Config.FeatureFlags.DonationCashEnabled
		if cashEnabled == nil then
			cashEnabled = Config.FeatureFlags.DonationSaweriaEnabled ~= false
		end
		backgroundJobScheduler:register({
			name = "donation_poll",
			callback = function()
				donationService:pollDonations()
			end,
			intervalMin = notifInterval,
			intervalMax = notifInterval + 3,
			enabled = cashEnabled == true
				and donationApiReady
				and Config.Donation
				and Config.Donation.POLL_ENABLED ~= false,
		})
	end
	if donationService and type(donationService.refreshLeaderboard) == "function" then
		local cashEnabled = Config.FeatureFlags.DonationCashEnabled
		if cashEnabled == nil then
			cashEnabled = Config.FeatureFlags.DonationSaweriaEnabled ~= false
		end
		backgroundJobScheduler:register({
			name = "leaderboard_refresh",
			callback = function()
				donationService:refreshLeaderboard()
			end,
			intervalMin = 120,
			intervalMax = 150,
			enabled = cashEnabled == true
				and Config.FeatureFlags.LeaderboardEnabled ~= false
				and donationApiReady,
		})
	end
	-- Keep-warm ping (240s)
	if donationService and type(donationService.keepWarmPing) == "function" then
		backgroundJobScheduler:register({
			name = "keep_warm",
			callback = function()
				donationService:keepWarmPing()
			end,
			intervalMin = 240,
			intervalMax = 300,
			enabled = Config.Donation and Config.Donation.KEEP_WARM_ENABLED == true,
		})
	end
	-- Likes backfill (300s, defer when high player count)
	if avatarLikeRepository and type(avatarLikeRepository.backfillLeaderboardFromSummaries) == "function" then
		backgroundJobScheduler:register({
			name = "likes_backfill",
			callback = function()
				avatarLikeRepository:backfillLeaderboardFromSummaries()
			end,
			intervalMin = 300,
			intervalMax = 360,
			deferThreshold = 15,
		})
	end
	-- Persistence Fabric metrics (DEBUG). Interval 0 disables.
	local metricsInterval = (Config.Persistence and Config.Persistence.METRICS_LOG_INTERVAL) or 60
	PersistenceFabricHooks.registerMetricsJob(backgroundJobScheduler, log, metricsInterval)
	-- Start the scheduler
	backgroundJobScheduler:start()
	log:info("BackgroundJobScheduler started with registered jobs")

	-- Initial leaderboard refresh kick-off REMOVED.
	-- The DonationController pre-warm already builds the workspace cache at
	-- init, and the 120s periodic leaderboard_refresh handles ongoing updates.
	-- The task.delay kick-off was causing a second DataStore burst that
	-- collided with cold-start overhead/profile loads, triggering
	-- StandardReadExperienceThrottled even with 1 player.
	-- HTTP API telemetry: log counter snapshot every 60s (Phase 0, quota-efficiency-pass-2026-06).
	-- Auto no-op when COUNTERS_ENABLED = false.
	-- Registered via the scheduler (not a bare task.spawn) so backgroundJobScheduler:stop()
	-- in script.Destroying / BindToClose cancels it instead of orphaning the thread.
	if Config.HttpApi and Config.HttpApi.COUNTERS_ENABLED then
		backgroundJobScheduler:register({
			name = "httpapi_snapshot",
			callback = function()
				log:info("HttpApi counter snapshot", ServerMods.HttpApiCounter.snapshot())
			end,
			intervalMin = 60,
			intervalMax = 60,
			enabled = Config.HttpApi.COUNTERS_ENABLED,
		})
	end
end
do
	if Config.FeatureFlags.ShopEnabled ~= false then
		local shopController = ServerMods.createShopController({
				shopService = shopService,
				overheadController = overheadController,
				logger = Logger.new("ShopController"),
				remotes = Remotes,
				notify = Notify,
				notifRemote = DonationNotifRemote,
				leaderboardRepository = donationLeaderboardRepository,
				donationEffectService = donationEffectService,
				donationService = donationService,
				overheadRepository = repo,
				overheadService = overheadService,
				workspaceLeaderboardRefresh = workspaceLeaderboardRefresh,
				paidBroadcastController = _paidBroadcastController,
				leaderboardNetwork = donationLeaderboardNetwork,
			})
		shopController:init()
	end
end
-- Level system gated by FeatureFlag. Default off; opt-in per game.
-- Persists XP/level via ServerMods.OverheadRepository (schema already supports level/xp fields).
if Config.FeatureFlags.LevelSystemEnabled and levelService then
	ServerMods.createLevelController({
		levelService = levelService,
		overheadService = overheadService,
		overheadController = overheadController,
		repo = repo,
	})
end
local _avatarContextController = ServerMods.createAvatarContextController({
	logger = Logger.new("AvatarContextController"),
	avatarContextService = avatarContextService,
	profileUpdatedRemote = ProfileUpdatedRemote,
	updatedRemote = AvatarContextUpdatedRemote,
	closeRemote = AvatarContextCloseRemote,
})
_avatarContextController:init()

local SOCIAL_WARM_MAX_ATTEMPTS = 3
local SOCIAL_WARM_RETRY_DELAY_SEC = 10

local function warmPlayerSocialSnapshot(userId: number, attempt: number?)
	local tryNum = attempt or 1
	task.defer(function()
		if not profileSocialService or type(profileSocialService.warm) ~= "function" then
			return
		end
		local result = profileSocialService:warm(userId)
		if not result.ok then
			return
		end

		local connectionsCount = result.value.connectionsCount
		if connectionsCount ~= nil and playerSnapshotService and type(playerSnapshotService.updateFromSocial) == "function" then
			playerSnapshotService:updateFromSocial(userId, result.value)
			if type(avatarContextService.invalidateForTarget) == "function" then
				avatarContextService:invalidateForTarget(userId)
			end
			if type(_avatarContextController.pushContextUpdate) == "function" then
				_avatarContextController:pushContextUpdate(userId)
			end
			return
		end

		if tryNum < SOCIAL_WARM_MAX_ATTEMPTS then
			task.delay(SOCIAL_WARM_RETRY_DELAY_SEC, function()
				warmPlayerSocialSnapshot(userId, tryNum + 1)
			end)
		end
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	warmPlayerSocialSnapshot(player.UserId)
end
connectionCleaner:add(Players.PlayerAdded:Connect(function(player)
	warmPlayerSocialSnapshot(player.UserId)
end))

do
	local avatarLikeController = ServerMods.createAvatarLikeController({
		logger = Logger.new("AvatarLikeController"),
		avatarLikeService = avatarLikeService,
		avatarContextController = _avatarContextController,
		overheadController = overheadController,
		notify = Notify,
		likeRequestRemote = AvatarContextLikeRequestRemote,
		likeResultRemote = AvatarContextLikeResultRemote,
		likeEffectRemote = AvatarLikeEffectRemote,
	})
	avatarLikeController:init()
end
ServerMods.createCarryController({
	service = carryService,
	config = Config,
	validator = ServerMods.Validator,
	taskQueue = ServerMods.TaskQueue.new(),
	logger = Logger.new("CarryController"),
	rateLimiters = {
		REQUEST = ServerMods.RateLimiter.new(Config.Carry.RATE_LIMITS.REQUEST.max, Config.Carry.RATE_LIMITS.REQUEST.window),
		ACCEPT = ServerMods.RateLimiter.new(Config.Carry.RATE_LIMITS.ACCEPT.max, Config.Carry.RATE_LIMITS.ACCEPT.window),
		REJECT = ServerMods.RateLimiter.new(Config.Carry.RATE_LIMITS.REJECT.max, Config.Carry.RATE_LIMITS.REJECT.window),
		END = ServerMods.RateLimiter.new(Config.Carry.RATE_LIMITS.END.max, Config.Carry.RATE_LIMITS.END.window),
	},
})
for _, player in ipairs(Players:GetPlayers()) do
	carryService:onPlayerAdded(player)
end
connectionCleaner:add(Players.PlayerAdded:Connect(function(player)
	carryService:onPlayerAdded(player)
end))
connectionCleaner:add(Players.PlayerRemoving:Connect(function(player)
	carryService:onPlayerRemoving(player)
end))
if gravityService then
	for _, player in ipairs(Players:GetPlayers()) do
		gravityService:onPlayerAdded(player)
	end
	connectionCleaner:add(Players.PlayerAdded:Connect(function(player)
		gravityService:onPlayerAdded(player)
	end))
	connectionCleaner:add(Players.PlayerRemoving:Connect(function(player)
		gravityService:onPlayerRemoving(player)
	end))
end
do
	local profileMenuController = ServerMods.createProfileMenuController({
		logger = Logger.new("ProfileMenuController"),
		remotes = Remotes,
		profileMenuService = profileMenuService,
		notify = Notify,
		overheadController = overheadController,
		avatarContextController = _avatarContextController,
	})
	profileMenuController:init()
	-- Wire the late-bound bridge used by AdminController to live-refresh the
	-- profile menu after a title grant/reset (no rejoin required).
	profileMenuSync.syncPlayer = function(player: Player)
		profileMenuController:syncPlayer(player)
	end
end
do
	local settingsController = trackLifecycle(
		"SettingsController",
		ServerMods.createSettingsController({
			logger = Logger.new("SettingsController"),
			remotes = Remotes,
			settingsService = settingsService,
			notify = Notify,
			overheadRepository = repo,
			overheadController = overheadController,
			profileLoader = sharedProfileLoader,
		})
	)
	settingsController:init()
end
if Config.FeatureFlags.StickersEnabled ~= false then
	-- Stickers join load folds into SharedProfileLoader (registered in onStart).
	stickerService._profileLoader = sharedProfileLoader
	trackLifecycle(
		"StickerController",
		ServerMods.createStickerController.new({
			logger = Logger.new("StickerController"),
			remotes = Remotes,
			service = stickerService,
			rateLimiters = {
				SET = ServerMods.RateLimiter.new(Config.Sticker.RATE_LIMITS.SET.max, Config.Sticker.RATE_LIMITS.SET.window),
				CLEAR = ServerMods.RateLimiter.new(Config.Sticker.RATE_LIMITS.CLEAR.max, Config.Sticker.RATE_LIMITS.CLEAR.window),
				ADD = ServerMods.RateLimiter.new(Config.Sticker.RATE_LIMITS.ADD.max, Config.Sticker.RATE_LIMITS.ADD.window),
				REQUEST = ServerMods.RateLimiter.new(
					Config.Sticker.RATE_LIMITS.REQUEST.max,
					Config.Sticker.RATE_LIMITS.REQUEST.window
				),
			},
		})
	)
end
-- serverLifecycle:startAll() dipanggil setelah semua module ter-register (di bawah)
-- ── Lifecycle startAll ──────────────────────────────────────
-- Panggil onStart() untuk semua module yang terdaftar via trackLifecycle.
-- StickerService dan StickerController ikut di-start di sini.
serverLifecycle:startAll()
-- Start the proximity recompute loop (drives ServerMods.InterestManager channel membership).
-- Must be called AFTER serverLifecycle:startAll() so all other services are live.
-- The loop connects its own RunService.Heartbeat and Players.PlayerRemoving inside
-- onStart; the PlayerRemoving wire below also forwards the call for ordering safety.
proximityService:onStart()
local sessionCommandService: any = nil
local commandExecutionService = nil
local _commandLibraryController = nil
connectionCleaner:add(Players.PlayerRemoving:Connect(function(player)
	-- R1.7: remove from all channels + clear per-pair delta baselines on disconnect.
	-- proximityService:removePlayer already delegates to interest:removePlayer.
	proximityService:removePlayer(player)
	-- OverheadService holds per-UserId caches (cashDonatedCache,
	-- rankResolutionScheduled, inFlight). Without clearing them here they leak
	-- for the entire server lifetime at sustained CCU+churn.
	if overheadService and type(overheadService.onPlayerRemoving) == "function" then
		overheadService:onPlayerRemoving(player)
	end
	-- Persistence Fabric: flush dirty Overhead/Settings session docs before drop.
	pcall(function()
		PersistenceFabricHooks.onPlayerRemoving(player)
	end)
	-- Cancel any outgoing couple requests from this player so they don't
	-- linger in the pending table (self-healing via 30s expiry, but clearing
	-- on leave frees the target's UI immediately and avoids stale accepts).
	if coupleService and type(coupleService.cancelPendingFrom) == "function" then
		coupleService:cancelPendingFrom(player.UserId)
	end
	if type(profileCommandService.onPlayerRemoving) == "function" then
		profileCommandService:onPlayerRemoving(player)
	end
	if sessionCommandService and type(sessionCommandService.onPlayerRemoving) == "function" then
		sessionCommandService:onPlayerRemoving(player)
	end
	if afkGuardService and type(afkGuardService.onPlayerRemoving) == "function" then
		afkGuardService:onPlayerRemoving(player)
	end
	donationEffectService:onPlayerRemoving(player)
	if streakController and type(streakController.onPlayerRemoving) == "function" then
		streakController:onPlayerRemoving(player)
	end
	if joinGreetingService and type(joinGreetingService.onPlayerRemoving) == "function" then
		joinGreetingService:onPlayerRemoving(player)
	end
end))
local _sessionCommandController
if Config.FeatureFlags.SyncDanceEnabled then
	-- syncFavoritesRepo + "favorites" kind already registered before first enqueue.
	syncService = ServerMods.createSyncService({
		config = Config.Sync,
		domain = ServerMods.SyncDomain,
		logger = Logger.new("SyncService"),
		animationLoader = ServerMods.AnimationLoader,
		proximity = proximityService,  -- R1.3: shared ProximityInterestService
		interest = interestManager,    -- R1.3: shared ServerMods.InterestManager
		favoritesRepository = syncFavoritesRepo,
	})
	local syncController = ServerMods.createSyncController({
		service = syncService,
		config = Config,
		validator = ServerMods.Validator,
		taskQueue = ServerMods.TaskQueue.new(),
		logger = Logger.new("SyncController"),
		favoritesRepository = syncFavoritesRepo,
		rateLimiters = {
			ANIM_START = ServerMods.RateLimiter.new(Config.SyncRateLimit.ANIM_START.max, Config.SyncRateLimit.ANIM_START.window),
			WUTWUT_RESTART = ServerMods.RateLimiter.new(
				Config.SyncRateLimit.WUTWUT_RESTART.max,
				Config.SyncRateLimit.WUTWUT_RESTART.window
			),
			SYNC_REQUEST = ServerMods.RateLimiter.new(
				Config.SyncRateLimit.SYNC_REQUEST.max,
				Config.SyncRateLimit.SYNC_REQUEST.window
			),
			SPEED_CHANGE = ServerMods.RateLimiter.new(
				Config.SyncRateLimit.SPEED_CHANGE.max,
				Config.SyncRateLimit.SPEED_CHANGE.window
			),
			FAVORITES_UPDATE = ServerMods.RateLimiter.new(
				Config.SyncRateLimit.FAVORITES_UPDATE.max,
				Config.SyncRateLimit.FAVORITES_UPDATE.window
			),
		},
	})
	-- Wire sync session only — do NOT re-enqueue SharedProfileLoader (favorites
	-- already queued on the first join enqueue above).
	for _, player in ipairs(Players:GetPlayers()) do
		syncService:onPlayerAdded(player)
		if player.Character then
			syncService:onCharacterAdded(player, player.Character)
		end
	end
	connectionCleaner:add(Players.PlayerAdded:Connect(function(player)
		syncService:onPlayerAdded(player)
	end))
	-- v2.2: route respawn-triggered hard unsync through the same notification
	-- pipeline used for player-leave. This is what unsticks followers after
	-- leader respawn so they can switch to a new leader instead of getting
	-- visually re-bound when the old leader dances again.
	if syncService and syncController and type(syncController.notifyLeaderDisconnected) == "function" then
		syncService:setOnFollowersHardUnsynced(function(leaderName, followerNames)
			syncController.notifyLeaderDisconnected(leaderName, followerNames)
		end)
	end
	connectionCleaner:add(Players.PlayerRemoving:Connect(function(player)
		local removalInfo = syncService:onPlayerRemoving(player)
		if syncFavoritesRepo then
			syncFavoritesRepo:onPlayerRemoving(player)
		end
		if
			removalInfo
			and syncController
			and type(syncController.notifyLeaderDisconnected) == "function"
		then
			syncController.notifyLeaderDisconnected(removalInfo.leaderName, removalInfo.followerNames)
		end
	end))
end
local syncNotificationNetwork: any = nil
if Config.FeatureFlags.SyncDanceEnabled and syncService then
	local syncRemotesFolder = ReplicatedStorage:FindFirstChild(Config.Sync.REMOTE_FOLDER)
	local syncNotificationRemote = if syncRemotesFolder
		then syncRemotesFolder:FindFirstChild(Config.Sync.REMOTE_NOTIFICATION)
		else nil
	if syncNotificationRemote and syncNotificationRemote:IsA("RemoteEvent") then
		syncNotificationNetwork = ServerMods.NetworkManager.create({
			reliable = syncNotificationRemote,
			logger = Logger.new("AfkSyncNotificationNetwork"),
			isServer = true,
		})
	end
end
sessionCommandService = ServerMods.createSessionCommandService({
	notify = Notify,
	syncService = syncService,
	eventBus = eventBus,
	syncNotify = if syncNotificationNetwork
		then function(player: Player, payload: { [string]: any })
			syncNotificationNetwork:fireClient(player, payload)
		end
		else nil,
})
sessionCommandService:init() -- wire wirePlayer agar rejoin position restore berfungsi
local afkGuardService: any = nil
if Config.FeatureFlags.AfkGuardEnabled ~= false and Config.AfkGuard.ENABLED == true then
	afkGuardService = trackLifecycle(
		"AfkGuardService",
		ServerMods.createAfkGuardService({
			notify = Notify,
			sessionCommandService = sessionCommandService,
			carryService = carryService,
			remotes = Remotes,
		})
	)
	afkGuardService:init()
end
commandExecutionService = ServerMods.createCommandExecutionService({
	profileCommandService = profileCommandService,
	communityCommandService = communityCommandService,
	membershipCommandService = membershipCommandService,
	giftService = _giftService,
	playerLookupService = playerLookupService,
	overheadController = overheadController,
	sessionCommandService = sessionCommandService,
	overheadService = overheadService,
	notify = Notify,
	avatarContextController = _avatarContextController,
	genericBroadcastService = genericBroadcastService,
	grantNetwork = giftGrantNetwork,
})
if gravityService then
	local gravityController = ServerMods.createGravityController({
		service = gravityService,
		commandExecutionService = commandExecutionService,
		overheadService = overheadService,
		notify = Notify,
		logger = Logger.new("GravityController"),
		rateLimiter = ServerMods.RateLimiter.new(Config.Gravity.RATE_MAX, Config.Gravity.RATE_WINDOW),
	})
	gravityController:init()
end
_commandLibraryController = ServerMods.createCommandLibraryController({
	service = commandExecutionService,
	remotes = Remotes,
})
_commandLibraryController:init()
-- ============================================================
-- DONATION SERVICE + CONTROLLER
-- ============================================================
ServerMods.createDonationController({
	donationService = donationService,
	overheadService = overheadService,
	commandExecutionService = commandExecutionService,
	notify = Notify,
	remotes = Remotes,
	leaderboardRepository = donationLeaderboardRepository,
	avatarLikeRepository = avatarLikeRepository,
	leaderboardsRemote = WorkspaceLeaderboardsRemote,
	leaderboardsSnapshotRemote = WorkspaceLeaderboardsSnapshotRemote,
	leaderboardsSnapshotResponseRemote = WorkspaceLeaderboardsSnapshotResponseRemote,
	workspaceLeaderboardRefresh = workspaceLeaderboardRefresh,
})
-- Assign overhead tag ke player yang join + sudah ada di leaderboard
connectionCleaner:add(Players.PlayerAdded:Connect(function(player)
	donationService:onPlayerAdded(player)
end))
-- ============================================================
-- MUSIC SERVICE + CONTROLLER
-- Bootstrapped in Init/MusicBootstrap so Music locals do not inflate
-- Main.server's Luau register peak (limit 200).
-- ============================================================
if Config.FeatureFlags.MusicPlayerEnabled then
	local musicBoot = require(script.Parent.Init.MusicBootstrap).start({
		musicConfig = Config.Music,
		groupId = Config.Group.GROUP_ID,
		overheadRepository = repo,
		eventBus = eventBus,
		remotes = Remotes,
		notify = Notify,
		sharedProfileLoader = sharedProfileLoader,
		connectionCleaner = connectionCleaner,
		trackLifecycle = trackLifecycle,
		Result = ServerMods.Result,
		Logger = Logger,
		log = log,
	})
	musicFavoritesRepo = musicBoot.musicFavoritesRepo
	_musicService = musicBoot.musicService
end
local _chatCommandController = ServerMods.createChatCommandController({
	chatCommandService = chatCommandService,
	commandExecutionService = commandExecutionService,
})
_chatCommandController:init()
log:info(
	"Server initialized. Overhead + Gift + Streak + Level + Couple + Shop + Sticker + Notify + AvatarContext + AvatarLike + Carry + CommandRouter + CommandLibrary + Settings ready."
)
-- ============================================================
-- AUTOSAVE + ServerRestartScheduled early flush
-- Periodic flush so a non-graceful crash cannot lose a full session of XP /
-- settings / favorites. Same path runs early when Creator Hub schedules a
-- delayed restart (before BindToClose's 30s window).
-- ============================================================
local function flushSessionBuffersEarly()
	for _, player in ipairs(Players:GetPlayers()) do
		if levelService and type(levelService.flushPlayer) == "function" then
			pcall(function()
				levelService:flushPlayer(player.UserId)
			end)
		end
		if settingsService and type(settingsService.flushStored) == "function" then
			pcall(function()
				settingsService:flushStored(player)
			end)
		end
	end
	if settingsService and type(settingsService.flushShutdown) == "function" then
		pcall(function()
			settingsService:flushShutdown()
		end)
	end
	if syncFavoritesRepo then
		pcall(function()
			syncFavoritesRepo:flushAll()
		end)
	end
	if musicFavoritesRepo then
		pcall(function()
			musicFavoritesRepo:flushAll()
		end)
	end
	pcall(function()
		PersistenceFabricHooks.flushAll()
	end)
end

local autosaveActive = true
task.spawn(function()
	while autosaveActive do
		task.wait(60)
		if not autosaveActive then
			break
		end
		pcall(flushSessionBuffersEarly)
	end
end)

do
	local ServerRestartHooks = require(script.Parent.Init.ServerRestartHooks)
	ServerRestartHooks.connect({
		log = log,
		notify = Notify,
		flushEarly = flushSessionBuffersEarly,
		connectionCleaner = connectionCleaner,
	})
end
-- ============================================================
-- SCRIPT DESTROYING - cleanup saat Rojo hot-reload di Studio
-- Mencegah accumulation ServerMods.NetworkManager + scheduler di Studio
-- ============================================================
script.Destroying:Connect(function()
	log:info("Server script destroying — cleaning up resources...")
	ServerMods.LicenseService.stop()
	-- Stop the autosave loop so it doesn't keep firing against tearing-down services.
	autosaveActive = false
	-- Disconnect top-level Players.PlayerAdded/PlayerRemoving handlers so a
	-- hot-reload does not stack duplicate handlers with stale service closures.
	connectionCleaner:clean()
	-- Cancel the shared Cache singleton cleanup thread + clear its store so the
	-- old module's thread doesn't orphan across hot-reloads.
	Cache.destroy()
	if sharedProfileLoader and type(sharedProfileLoader.destroy) == "function" then
		pcall(function()
			sharedProfileLoader:destroy()
		end)
	end
	-- Tear down MusicService (poll loop, ServerMods.EventBus sub, PlayerRemoving, sessions).
	-- Not registered via trackLifecycle, so destroyed here explicitly.
	if _musicService and type(_musicService.destroy) == "function" then
		pcall(function()
			_musicService:destroy()
		end)
	end
	-- Tear down SyncService scavenge thread (cancels the 120s `while true` loop).
	if syncService and type(syncService.destroy) == "function" then
		pcall(function()
			syncService:destroy()
		end)
	end
	-- Stop DonationService polling threads sebelum ServerMods.NetworkManager destroy,
	-- agar loop tidak melanjutkan HTTP request saat resource sudah invalid.
	if donationService and type(donationService.stopPolling) == "function" then
		donationService:stopPolling()
	end
	if backgroundJobScheduler then
		backgroundJobScheduler:stop()
	end
	if donationLeaderboardRepository and type(donationLeaderboardRepository.destroy) == "function" then
		pcall(function()
			donationLeaderboardRepository:destroy()
		end)
	end
	if playerSnapshotService and type(playerSnapshotService.destroy) == "function" then
		pcall(function()
			playerSnapshotService:destroy()
		end)
	end
	-- Stop proximity recompute loop and release all ServerMods.InterestManager subscriptions.
	proximityService:onDestroy()
	interestManager:destroy()
	networkManager:destroy()
	genericBroadcastNetwork:destroy()
	if giftGrantNetwork and type(giftGrantNetwork.destroy) == "function" then
		giftGrantNetwork:destroy()
	end
	donationLeaderboardNetwork:destroy()
	donationNotifNetwork:destroy()
	paidBroadcastResultNetwork:destroy()
	serverLifecycle:destroyAll()
end)
-- ============================================================
-- BIND TO CLOSE - flush semua data player saat server shutdown
-- Wajib ada agar data tidak hilang saat server mati mendadak
-- ============================================================
game:BindToClose(function()
	if donationService and type(donationService.stopPolling) == "function" then
		donationService:stopPolling()
	end
	-- Stop the autosave loop so it can't race with the shutdown flush.
	autosaveActive = false
	if backgroundJobScheduler then
		backgroundJobScheduler:stop()
	end
	networkManager:destroy()
	log:info("Server shutting down — flushing all player data...")

	local players = Players:GetPlayers()
	local pendingSaves = 0

	-- R12.1-R12.4: Shutdown completion guard — register every outstanding write
	-- before proceeding, complete within 25s of the 30s BindToClose budget.
	-- Per-player fav writes are tracked via the counter; flushAll() calls add
	-- their own expected write count.

	if #players == 0 then
		log:info("BindToClose: no players online, flushing repos...")
	else
		pendingSaves = #players
		for _, player in ipairs(players) do
			task.spawn(function()
				if levelService and type(levelService.flushPlayer) == "function" then
					local flushResult = levelService:flushPlayer(player.UserId)
					if not flushResult.ok then
						log:warn("BindToClose: level XP flush failed", {
							userId = player.UserId,
							error = flushResult.error,
						})
					end
				end
				if settingsService and type(settingsService.flushStored) == "function" then
					settingsService:flushStored(player)
				end
				if syncFavoritesRepo then
					syncFavoritesRepo:onPlayerRemoving(player)
				end
				if musicFavoritesRepo then
					musicFavoritesRepo:onPlayerRemoving(player)
				end

				pendingSaves -= 1
			end)
		end
	end

	pendingSaves += 1
	task.spawn(function()
		local remaining = 0
		-- Run the repo-wide flushAll calls in PARALLEL (they touch different
		-- stores/keys) instead of sequentially. A single save can take up to
		-- ~19s under budget pressure (5s defer + 3 retries with backoff); doing
		-- them sequentially could blow the 25s shutdown budget and lose data.
		local done = 0
		local total = 0
		local function launchRepo(fn: () -> ())
			total += 1
			task.spawn(function()
				pcall(fn)
				done += 1
			end)
		end
		if settingsService and type(settingsService.flushShutdown) == "function" then
			launchRepo(function()
				remaining += settingsService:flushShutdown()
			end)
		end
		launchRepo(function()
			remaining += PersistenceFabricHooks.flushAll()
		end)
		if syncFavoritesRepo then
			launchRepo(function()
				remaining += syncFavoritesRepo:flushAll()
			end)
		end
		if musicFavoritesRepo then
			launchRepo(function()
				remaining += musicFavoritesRepo:flushAll()
			end)
		end
		-- Wait for all parallel repo flushes (bounded by the 25s outer budget).
		local waited = 0
		while done < total and waited < 25 do
			task.wait(0.1)
			waited += 0.1
		end
		if remaining > 0 then
			log:warn("BindToClose: repo flush incomplete", { remaining = remaining })
		end
		pendingSaves -= 1
	end)

	-- R12.2, R12.4: Wait for all writes up to 25s (within 30s BindToClose budget).
	-- On overflow, log each unsaved entry and proceed without blocking past 30s.
	local elapsed = 0
	local lastReportedRemaining = pendingSaves
	while pendingSaves > 0 and elapsed < 25 do
		task.wait(0.5)
		elapsed += 0.5
		if pendingSaves ~= lastReportedRemaining and elapsed >= 10 then
			log:info("BindToClose: saving in progress...", {
				remaining = pendingSaves,
				elapsed = elapsed,
			})
			lastReportedRemaining = pendingSaves
		end
	end

	if pendingSaves > 0 then
		log:warn("BindToClose: timeout — beberapa player/repo mungkin tidak tersave", {
			remaining = pendingSaves,
			elapsed = elapsed,
		})
	else
		log:info("BindToClose complete — all player data flushed.")
	end
	serverLifecycle:destroyAll()
end)
return overheadController
