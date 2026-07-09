--!strict
-- PATH: ServerScriptService/Server/Main.server.lua
-- Entry point server. Wire semua dependencies di sini.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local KitProduct = require(ReplicatedStorage.Hazastudio_ClubKit.KitProduct)

-- Services
local createOverheadService = require(script.Parent.Services.OverheadService)
local createGiftService = require(script.Parent.Services.GiftService)
local createStreakService = require(script.Parent.Services.StreakService)
local createLevelService = require(script.Parent.Services.LevelService)
local createCoupleService = require(script.Parent.Services.CoupleService)
local createShopService = require(script.Parent.Services.ShopService)
local createPlayerLookupService = require(script.Parent.Services.PlayerLookupService)
local createChatCommandService = require(script.Parent.Services.ChatCommandService)
local createMembershipCommandService = require(script.Parent.Services.MembershipCommandService)
local createCommunityCommandService = require(script.Parent.Services.CommunityCommandService)
local createProfileSocialService = require(script.Parent.Services.ProfileSocialService)
local createAvatarContextService = require(script.Parent.Services.AvatarContextService)
local createAvatarLikeService = require(script.Parent.Services.AvatarLikeService)
local createCarryService = require(script.Parent.Services.CarryService)
local createProfileCommandService = require(script.Parent.Services.ProfileCommandService)
local createProfileMenuService = require(script.Parent.Services.ProfileMenuService)
local createSessionCommandService = require(script.Parent.Services.SessionCommandService)
local createAfkGuardService = require(script.Parent.Services.AfkGuardService)
local createCommandExecutionService = require(script.Parent.Services.CommandExecutionService)
local createSyncService = require(script.Parent.Services.SyncService)
local createDonationService = require(script.Parent.Services.DonationService)
local LicenseService = require(script.Parent.Services.LicenseService)
local createDonationEffectService = require(script.Parent.Services.DonationEffectService)
local createStickerService = require(script.Parent.Services.StickerService)
local createMusicService = require(script.Parent.Services.MusicService)
local createZoneTrackerService = require(script.Parent.Services.ZoneTrackerService)
local createSettingsService = require(script.Parent.Services.SettingsService)
local RoleToolService = require(script.Parent.Services.RoleToolService)
local createPlayerSnapshotService = require(script.Parent.Services.PlayerSnapshotService)
local createBackgroundJobScheduler = require(script.Parent.Services.BackgroundJobScheduler)
-- Interest management (P0-1: wires up the pre-built but previously dead InterestManager)
local InterestManager = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.InterestManager)
local createProximityInterestService = require(script.Parent.Services.ProximityInterestService)
-- Controllers
local createOverheadController = require(script.Parent.Controllers.OverheadController)
local createCoupleController = require(script.Parent.Controllers.CoupleController)
local createShopController = require(script.Parent.Controllers.ShopController)
local createStreakController = require(script.Parent.Controllers.StreakController)
local createLevelController = require(script.Parent.Controllers.LevelController)
local createAdminController = require(script.Parent.Controllers.AdminController)
local createAvatarContextController = require(script.Parent.Controllers.AvatarContextController)
local createAvatarLikeController = require(script.Parent.Controllers.AvatarLikeController)
local createCarryController = require(script.Parent.Controllers.CarryController)
local createProfileMenuController = require(script.Parent.Controllers.ProfileMenuController)
local createCommandLibraryController = require(script.Parent.Controllers.CommandLibraryController)
local createChatCommandController = require(script.Parent.Controllers.ChatCommandController)
local createSyncController = require(script.Parent.Controllers.SyncController)
local createDonationController = require(script.Parent.Controllers.DonationController)
local createStickerController = require(script.Parent.Controllers.StickerController)
local createMusicController = require(script.Parent.Controllers.MusicController)
local createSettingsController = require(script.Parent.Controllers.SettingsController)
local createGenericBroadcastService = require(script.Parent.Services.GenericBroadcastService)
local createPaidBroadcastController = require(script.Parent.Controllers.PaidBroadcastController)
local createCinematicDockController = require(script.Parent.Controllers.CinematicDockController)
-- Repository
local OverheadRepository = require(script.Parent.Repositories.OverheadRepository)
local ProfileRepository = require(script.Parent.Repositories.ProfileRepository)
local createAboutRosterRepository = require(script.Parent.Repositories.AboutRosterRepository)
local AvatarLikeRepository = require(script.Parent.Repositories.AvatarLikeRepository)
local DonationLeaderboardRepository = require(script.Parent.Repositories.DonationLeaderboardRepository)
local GiftPendingRepository = require(script.Parent.Repositories.GiftPendingRepository)
local ManualBagibagiRepository = require(script.Parent.Repositories.ManualBagibagiRepository)
local StickerRepository = require(script.Parent.Repositories.StickerRepository)
local SettingsRepository = require(script.Parent.Repositories.SettingsRepository)
local FavoritesRepository = require(script.Parent.Repositories.FavoritesRepository)
local MusicRepository = require(script.Parent.Repositories.MusicRepository)
local MusicFavoritesRepository = require(script.Parent.Repositories.MusicFavoritesRepository)
local ProfileLoader = require(script.Parent.Repositories.ProfileLoader)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local Lifecycle = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Lifecycle)
local HttpApiCounter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApiCounter)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Validator = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Validator)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local TaskQueue = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.TaskQueue)
local EventBus = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.EventBus)
local CarryDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.CarryDomain)
local SyncDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.SyncDomain)
local NetworkManager = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkManager)
local AnimationLoader = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.ContextModule.AnimationLoader)
local provisionEarlyRemotes = require(script.Parent.Init.EarlyRemotes)
local Cleaner = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cleaner)
local Cache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cache)
local log = Logger.new(KitProduct.LogTag)
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
if Config.DataStoreScope.USE_STUDIO_ISOLATION then
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
	LicenseService.start({
		apiUrl = donationApiUrl,
		secret = Secrets.DonationApiSecret,
	})
	LicenseService.awaitInitialCheck(10)
	local licenseState = LicenseService.getState()
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
local eventBus = EventBus.new()

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
-- ============================================================
-- SETUP REMOTE: Notify
-- FireClient = side effect, bukan pure util -> wire di entry point.
-- ============================================================
local NotifyRemote = ensureRemoteEvent(Remotes, "Notify")
-- Dibuat awal agar client OverheadController bisa subscribe sebelum boot server berat selesai.
ensureRemoteEvent(Remotes, "OverheadUpdate")
ensureRemoteEvent(Remotes, (Config.ClientBoot :: any).CLIENT_GAMEPLAY_READY_REMOTE or "ClientGameplayReady")
local GenericBroadcastRemote = ensureRemoteEvent(Remotes, Config.Announcement.REMOTE_BROADCAST)
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
-- World-position nuke VFX (Nuke/Smite/BlackHole). Pre-created here so client-side
-- NukeEffectController can :WaitForChild() without yielding during gameplay.
ensureRemoteEvent(Remotes, (Config.Donation :: any).NUKE_REMOTE or "DonationEffect")
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

-- ── NetworkManager — per-frame batched transport ─────────────
-- Batches all outbound FireClient calls within a frame into a
-- single Heartbeat flush. Reduces per-call overhead at high CCU.
-- See: Guidelines/REF_ARCHITECTURE.md (Network Transport section)
local networkManager = NetworkManager.create({
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
		-- v2.1: batched via NetworkManager
		networkManager:fireClient(player, payload)
	end,
	all = function(messageOrPayload: NotifyInput, notifType: string?)
		local payload = normalizeNotifyPayload(messageOrPayload, notifType, "SYSTEM")
		if not payload then
			return
		end
		-- v2.1: batched via NetworkManager
		networkManager:fireAllClients(payload)
	end,
}
-- ============================================================
-- WIRING DEPENDENCIES
-- ============================================================
local repo = OverheadRepository
local aboutRosterRepository = createAboutRosterRepository()
local profileRepo = ProfileRepository.new({ logger = Logger.new("ProfileRepository") })
local avatarLikeRepository = AvatarLikeRepository.new({ logger = Logger.new("AvatarLikeRepository") })
local donationLeaderboardRepository =
	DonationLeaderboardRepository.new({ logger = Logger.new("DonationLeaderboardRepository") })
local giftPendingRepository = GiftPendingRepository.create({
	logger = Logger.new("GiftPendingRepository"),
})
local manualBagibagiRepository = ManualBagibagiRepository.create({
	logger = Logger.new("ManualBagibagiRepository"),
})

-- DonationEffectService is constructed after CinematicDockController so the
-- camera trigger callback can be wired in.
local profileSocialService = createProfileSocialService({ logger = Logger.new("ProfileSocialService") })
local settingsRepo = SettingsRepository
local settingsService = createSettingsService({
	logger = Logger.new("SettingsService"),
	repo = settingsRepo,
})
local profileCommandService = createProfileCommandService({
	logger = Logger.new("ProfileCommandService"),
	profileRepository = profileRepo,
})
-- PlayerSnapshotService: in-memory cache for fast ACM lookups
local playerSnapshotService = createPlayerSnapshotService.create({
	logger = Logger.new("PlayerSnapshotService"),
})
-- BackgroundJobScheduler: centralized periodic job management
local backgroundJobScheduler = createBackgroundJobScheduler.create({
	logger = Logger.new("BackgroundJobScheduler"),
})
local overheadService = createOverheadService({
	repo = repo,
	avatarLikeRepository = avatarLikeRepository,
	profileRepository = profileRepo,
	profileCommandService = profileCommandService,
	aboutRosterRepository = aboutRosterRepository,
	donationLeaderboardRepository = donationLeaderboardRepository,
	donationService = nil :: any, -- assigned post-init via overheadService:setDonationService
})
local profileMenuService = createProfileMenuService({
	logger = Logger.new("ProfileMenuService"),
	profileRepository = profileRepo,
	overheadRepository = repo,
	profileCommandService = profileCommandService,
})
local avatarContextService = createAvatarContextService({
	logger = Logger.new("AvatarContextService"),
	overheadService = overheadService,
	profileSocialService = profileSocialService,
	profileRepository = profileRepo,
	profileCommandService = profileCommandService,
	avatarLikeRepository = avatarLikeRepository,
	playerSnapshotService = playerSnapshotService,
})
local avatarLikeService = createAvatarLikeService({
	logger = Logger.new("AvatarLikeService"),
	avatarLikeRepository = avatarLikeRepository,
})
local carryService = trackLifecycle(
	"CarryService",
	createCarryService({
		config = Config,
		domain = CarryDomain,
		logger = Logger.new("CarryService"),
	})
)
local stickerService = trackLifecycle(
	"StickerService",
	createStickerService.new({
		logger = Logger.new("StickerService"),
		repository = StickerRepository,
	})
)
trackLifecycle(
	"RoleToolService",
	RoleToolService.new({
		logger = Logger.new("RoleToolService"),
		eventBus = eventBus,
		overheadService = overheadService,
	})
)
local _giftService = createGiftService({
	repo = repo,
	overheadService = overheadService,
})
local streakService = createStreakService({ repo = repo })
local levelService: any = nil
if Config.FeatureFlags.LevelSystemEnabled then
	levelService = createLevelService({ repo = repo })
end
local coupleService = trackLifecycle("CoupleService", createCoupleService({ repo = repo }))
local playerLookupService = createPlayerLookupService()
local chatCommandService = createChatCommandService()
local genericBroadcastNetwork = NetworkManager.create({
	reliable = GenericBroadcastRemote,
	logger = Logger.new("GenericBroadcastNetwork"),
	isServer = true,
})
local genericBroadcastService = createGenericBroadcastService({
	broadcastNetwork = genericBroadcastNetwork,
	overheadService = overheadService,
	logger = Logger.new("GenericBroadcastService"),
})
local giftGrantNetwork = NetworkManager.create({
	reliable = ShopGrantRemote,
	logger = Logger.new("GiftGrantNetwork"),
	isServer = true,
})
local paidBroadcastResultNetwork = NetworkManager.create({
	reliable = _PaidBroadcastResultRemote,
	logger = Logger.new("PaidBroadcastResultNetwork"),
	isServer = true,
})
local _paidBroadcastController = createPaidBroadcastController({
	remotes = Remotes,
	notify = Notify,
	genericBroadcastService = genericBroadcastService,
	resultNetwork = paidBroadcastResultNetwork,
})
_paidBroadcastController:init()
local _cinematicDockController = createCinematicDockController({
	remotes = Remotes,
	notify = Notify,
	overheadService = overheadService,
})
-- DonationEffectService relies on CinematicDockController for the camera
-- trigger. The callback runs whenever a tier has `cameraDuration > 0`.
local donationEffectService = createDonationEffectService({
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
local interestManager = InterestManager.create({
	logger = Logger.new("InterestManager"),
})
local proximityService = createProximityInterestService.create({
	interest = interestManager,
	config = Config.Interest,
	logger = Logger.new("ProximityInterestService"),
})
local overheadController = createOverheadController({
	service = overheadService,
	remotes = Remotes, -- inject Remotes folder ke factory
	eventBus = eventBus,
	proximity = proximityService,   -- R1.3: shared ProximityInterestService
	interest = interestManager,     -- R1.3: shared InterestManager
	playerSnapshotService = playerSnapshotService,
})
local streakController = createStreakController({
	streakService = streakService,
	overheadController = overheadController,
	remotes = Remotes,
})
-- Join-time DataStore read serialization. All heavy per-player reads that run on
-- PlayerAdded go through this single queue so a join storm does not fan out
-- hundreds of concurrent DataStore requests and saturate the per-server budget.
local sharedProfileLoader = ProfileLoader.create({
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
local OVERHEAD_JOIN_RETRY_DELAYS = { 2, 5, 10 }

local function isRetryableOverheadLoadError(err: string?): boolean
	if type(err) ~= "string" or err == "" then
		return false
	end
	return err == "budget_exhausted"
		or err == "ds_throttled"
		or string.find(err, "Timeout") ~= nil
		or string.find(err, "InternalError") ~= nil
		or string.find(err, "ServiceUnavailable") ~= nil
		or string.find(err, "RequestThrottled") ~= nil
end

local function scheduleOverheadJoinRetry(player: Player)
	task.spawn(function()
		for _, delaySec in ipairs(OVERHEAD_JOIN_RETRY_DELAYS) do
			task.wait(delaySec)
			if not player.Parent then
				return
			end
			local retry = repo:loadStrict(player.UserId)
			if retry.ok then
				overheadController:onPlayerDataReady(player)
				overheadController:refreshPlayer(player, "recovery")
				streakController:processLoginForPlayer(player)
				log:info("Overhead join retry succeeded", {
					userId = player.UserId,
					delaySec = delaySec,
				})
				return
			end
			if not isRetryableOverheadLoadError(retry.error) then
				log:warn("Overhead join retry stopped (non-retryable)", {
					userId = player.UserId,
					error = retry.error,
				})
				return
			end
		end
		log:warn("Overhead join retry exhausted", { userId = player.UserId })
	end)
end

sharedProfileLoader:onLoaded(function(event)
	if event.kind ~= "overhead" or not event.player.Parent then
		return
	end
	if event.result.ok then
		overheadController:onPlayerDataReady(event.player)
		streakController:processLoginForPlayer(event.player)
	else
		scheduleOverheadJoinRetry(event.player)
	end
end)
-- Enqueue players already in the game and all future joiners.
for _, player in ipairs(Players:GetPlayers()) do
	sharedProfileLoader:enqueue(player)
end
connectionCleaner:add(Players.PlayerAdded:Connect(function(player)
	sharedProfileLoader:enqueue(player)
end))
-- warmPlayerSocialSnapshot is defined after AvatarContextController (needs pushContextUpdate).
local shopService = createShopService({
	repo = repo,
	logger = Logger.new("ShopService"),
	giftPendingRepository = giftPendingRepository,
})
local membershipCommandService = createMembershipCommandService({
	repo = repo,
	overheadService = overheadService,
})
local communityCommandService = createCommunityCommandService({
	repo = repo,
	overheadService = overheadService,
})
-- Late-bound bridge so AdminController can push a live profile-menu refresh
-- after it mutates overhead-backed profile fields (e.g. specialTitle). The
-- ProfileMenuController is constructed later; we populate `syncPlayer` then.
local profileMenuSync: { syncPlayer: ((Player) -> ())? } = { syncPlayer = nil }
local _adminController = createAdminController({
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
	createCoupleController({
		coupleService = coupleService,
		overheadController = overheadController,
		repo = repo,
		notify = Notify,
		remotes = Remotes,
	})
end
-- DonationService is constructed before ShopController because ShopController
-- needs `recordRobuxDonationDaily()` to update the daily Robux leaderboard.
local workspaceLeaderboardRefresh: { refresh: (() -> ())? } = { refresh = nil }
local donationLeaderboardNetwork = NetworkManager.create({
	reliable = DonationLeaderboardRemote,
	logger = Logger.new("DonationLeaderboardNetwork"),
	isServer = true,
})
local donationNotifNetwork = NetworkManager.create({
	reliable = DonationNotifRemote,
	logger = Logger.new("DonationNotifNetwork"),
	isServer = true,
})
local donationService = createDonationService({
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
	end)
end
-- Register background jobs via scheduler instead of inline loops
if backgroundJobScheduler then
	-- Donation notification polling - respects NOTIF_POLL_INTERVAL from config
	if donationService and type(donationService.pollDonations) == "function" then
		local notifInterval = (Config.Donation and Config.Donation.NOTIF_POLL_INTERVAL) or 15
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
				log:info("HttpApi counter snapshot", HttpApiCounter.snapshot())
			end,
			intervalMin = 60,
			intervalMax = 60,
			enabled = Config.HttpApi.COUNTERS_ENABLED,
		})
	end
end
do
	if Config.FeatureFlags.ShopEnabled ~= false then
		local shopController = createShopController({
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
-- Persists XP/level via OverheadRepository (schema already supports level/xp fields).
if Config.FeatureFlags.LevelSystemEnabled and levelService then
	createLevelController({
		levelService = levelService,
		overheadService = overheadService,
		overheadController = overheadController,
		repo = repo,
	})
end
local _avatarContextController = createAvatarContextController({
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
	local avatarLikeController = createAvatarLikeController({
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
createCarryController({
	service = carryService,
	config = Config,
	validator = Validator,
	taskQueue = TaskQueue.new(),
	logger = Logger.new("CarryController"),
	rateLimiters = {
		REQUEST = RateLimiter.new(Config.Carry.RATE_LIMITS.REQUEST.max, Config.Carry.RATE_LIMITS.REQUEST.window),
		ACCEPT = RateLimiter.new(Config.Carry.RATE_LIMITS.ACCEPT.max, Config.Carry.RATE_LIMITS.ACCEPT.window),
		REJECT = RateLimiter.new(Config.Carry.RATE_LIMITS.REJECT.max, Config.Carry.RATE_LIMITS.REJECT.window),
		END = RateLimiter.new(Config.Carry.RATE_LIMITS.END.max, Config.Carry.RATE_LIMITS.END.window),
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
do
	local profileMenuController = createProfileMenuController({
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
		createSettingsController({
			logger = Logger.new("SettingsController"),
			remotes = Remotes,
			settingsService = settingsService,
			notify = Notify,
			overheadRepository = repo,
			overheadController = overheadController,
		})
	)
	settingsController:init()
end
if Config.FeatureFlags.StickersEnabled ~= false then
	trackLifecycle(
		"StickerController",
		createStickerController.new({
			logger = Logger.new("StickerController"),
			remotes = Remotes,
			service = stickerService,
			rateLimiters = {
				SET = RateLimiter.new(Config.Sticker.RATE_LIMITS.SET.max, Config.Sticker.RATE_LIMITS.SET.window),
				CLEAR = RateLimiter.new(Config.Sticker.RATE_LIMITS.CLEAR.max, Config.Sticker.RATE_LIMITS.CLEAR.window),
				ADD = RateLimiter.new(Config.Sticker.RATE_LIMITS.ADD.max, Config.Sticker.RATE_LIMITS.ADD.window),
				REQUEST = RateLimiter.new(
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
-- Start the proximity recompute loop (drives InterestManager channel membership).
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
end))
local _sessionCommandController
if Config.FeatureFlags.SyncDanceEnabled then
	syncFavoritesRepo = FavoritesRepository.new({
		config = Config.Favorites,
		logger = Logger.new("FavoritesRepository"),
	})
	-- Favorites load is part of the shared join-time read queue instead of a
	-- separate ProfileLoader, so all join-time DataStore reads share one budget.
	sharedProfileLoader:register("favorites", function(player: Player)
		syncFavoritesRepo:onPlayerAdded(player)
		return Result.Ok(true)
	end)
	syncService = createSyncService({
		config = Config.Sync,
		domain = SyncDomain,
		logger = Logger.new("SyncService"),
		animationLoader = AnimationLoader,
		proximity = proximityService,  -- R1.3: shared ProximityInterestService
		interest = interestManager,    -- R1.3: shared InterestManager
	})
	local syncController = createSyncController({
		service = syncService,
		config = Config,
		validator = Validator,
		taskQueue = TaskQueue.new(),
		logger = Logger.new("SyncController"),
		favoritesRepository = syncFavoritesRepo,
		rateLimiters = {
			ANIM_START = RateLimiter.new(Config.SyncRateLimit.ANIM_START.max, Config.SyncRateLimit.ANIM_START.window),
			WUTWUT_RESTART = RateLimiter.new(
				Config.SyncRateLimit.WUTWUT_RESTART.max,
				Config.SyncRateLimit.WUTWUT_RESTART.window
			),
			SYNC_REQUEST = RateLimiter.new(
				Config.SyncRateLimit.SYNC_REQUEST.max,
				Config.SyncRateLimit.SYNC_REQUEST.window
			),
			SPEED_CHANGE = RateLimiter.new(
				Config.SyncRateLimit.SPEED_CHANGE.max,
				Config.SyncRateLimit.SPEED_CHANGE.window
			),
			FAVORITES_UPDATE = RateLimiter.new(
				Config.SyncRateLimit.FAVORITES_UPDATE.max,
				Config.SyncRateLimit.FAVORITES_UPDATE.window
			),
		},
	})
	for _, player in ipairs(Players:GetPlayers()) do
		syncService:onPlayerAdded(player)
		sharedProfileLoader:enqueue(player)
		if player.Character then
			syncService:onCharacterAdded(player, player.Character)
		end
	end
	connectionCleaner:add(Players.PlayerAdded:Connect(function(player)
		syncService:onPlayerAdded(player)
		sharedProfileLoader:enqueue(player)
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
		syncFavoritesRepo:onPlayerRemoving(player)
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
		syncNotificationNetwork = NetworkManager.create({
			reliable = syncNotificationRemote,
			logger = Logger.new("AfkSyncNotificationNetwork"),
			isServer = true,
		})
	end
end
sessionCommandService = createSessionCommandService({
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
		createAfkGuardService({
			notify = Notify,
			sessionCommandService = sessionCommandService,
			carryService = carryService,
			remotes = Remotes,
		})
	)
	afkGuardService:init()
end
commandExecutionService = createCommandExecutionService({
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
_commandLibraryController = createCommandLibraryController({
	service = commandExecutionService,
	remotes = Remotes,
})
_commandLibraryController:init()
-- ============================================================
-- DONATION SERVICE + CONTROLLER
-- ============================================================
createDonationController({
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
-- ============================================================
if Config.FeatureFlags.MusicPlayerEnabled then
	do
		local musicRepo = MusicRepository.new({
			config = Config.Music,
			logger = Logger.new("MusicRepository"),
		})
		musicFavoritesRepo = MusicFavoritesRepository.new({
			config = Config.Music,
			logger = Logger.new("MusicFavoritesRepository"),
		})
		local musicService = createMusicService({
			repo = musicRepo,
			favoritesRepository = musicFavoritesRepo,
			overheadRepository = repo,
			eventBus = eventBus,
			logger = Logger.new("MusicService"),
			config = Config.Music,
			groupId = Config.Group.GROUP_ID,
		})
		_musicService = musicService
		local musicInitOk, musicInitErr = pcall(function()
			musicService:init()
		end)
		if not musicInitOk then
			log:error("MusicService init failed", { error = tostring(musicInitErr) })
		end
		local musicController = createMusicController({
			service = musicService,
			remotes = Remotes,
			logger = Logger.new("MusicController"),
			config = Config.Music,
			notify = Notify,
		})
		local musicControllerOk, musicControllerErr = pcall(function()
			musicController:init()
		end)
		if not musicControllerOk then
			log:error("MusicController init failed", { error = tostring(musicControllerErr) })
		end

		-- Zone tracker: detects which tagged BasePart each player is inside and
		-- routes them to the matching MusicSession. No-op when Music.MODE = "global".
		trackLifecycle(
			"ZoneTrackerService",
			createZoneTrackerService.create({
				musicService = musicService,
				logger = Logger.new("ZoneTrackerService"),
			})
		)
		-- Sync state ke player yang baru join (client polls get_state; push is best-effort).
		connectionCleaner:add(Players.PlayerAdded:Connect(function(player)
			task.defer(function()
				if player and player.Parent then
					musicService:onPlayerAdded(player)
				end
			end)
		end))
		-- Sync state ke player yang sudah ada saat server start
		for _, existingPlayer in Players:GetPlayers() do
			task.defer(function()
				if existingPlayer and existingPlayer.Parent then
					musicService:onPlayerAdded(existingPlayer)
				end
			end)
		end
	end
end
local _chatCommandController = createChatCommandController({
	chatCommandService = chatCommandService,
	commandExecutionService = commandExecutionService,
})
_chatCommandController:init()
log:info(
	"Server initialized. Overhead + Gift + Streak + Level + Couple + Shop + Sticker + Notify + AvatarContext + AvatarLike + Carry + CommandRouter + CommandLibrary + Settings ready."
)
-- ============================================================
-- AUTOSAVE — periodic flush of session-buffered data so a non-graceful
-- server crash (process kill / OOM) cannot lose an entire session of XP,
-- settings, and favorites. Without this, those buffers only flush on
-- PlayerRemoving / BindToClose, so a crash between events loses everything.
-- ============================================================
local autosaveActive = true
task.spawn(function()
	while autosaveActive do
		task.wait(60)
		if not autosaveActive then
			break
		end
		pcall(function()
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
		end)
	end
end)
-- ============================================================
-- SCRIPT DESTROYING - cleanup saat Rojo hot-reload di Studio
-- Mencegah accumulation NetworkManager + scheduler di Studio
-- ============================================================
script.Destroying:Connect(function()
	log:info("Server script destroying — cleaning up resources...")
	LicenseService.stop()
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
	-- Tear down MusicService (poll loop, EventBus sub, PlayerRemoving, sessions).
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
	-- Stop DonationService polling threads sebelum NetworkManager destroy,
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
	-- Stop proximity recompute loop and release all InterestManager subscriptions.
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
