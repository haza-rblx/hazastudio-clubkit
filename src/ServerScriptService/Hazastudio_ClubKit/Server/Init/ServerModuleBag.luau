--!strict
--[[
	Bundles Main.server requires so the entry chunk stays under Luau's
	~200-local register limit. Main holds one local (`ServerMods`) and
	indexes this table — load order/behavior unchanged (ModuleScript cache).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = script.Parent.Parent
local Kit = ReplicatedStorage.Hazastudio_ClubKit

return {
	-- Services
	createOverheadService = require(Server.Services.OverheadService),
	createGiftService = require(Server.Services.GiftService),
	createStreakService = require(Server.Services.StreakService),
	createLevelService = require(Server.Services.LevelService),
	createCoupleService = require(Server.Services.CoupleService),
	createShopService = require(Server.Services.ShopService),
	createPlayerLookupService = require(Server.Services.PlayerLookupService),
	createChatCommandService = require(Server.Services.ChatCommandService),
	createMembershipCommandService = require(Server.Services.MembershipCommandService),
	createCommunityCommandService = require(Server.Services.CommunityCommandService),
	createProfileSocialService = require(Server.Services.ProfileSocialService),
	createAvatarContextService = require(Server.Services.AvatarContextService),
	createAvatarLikeService = require(Server.Services.AvatarLikeService),
	createCarryService = require(Server.Services.CarryService),
	createGravityService = require(Server.Services.GravityService),
	createProfileCommandService = require(Server.Services.ProfileCommandService),
	createProfileMenuService = require(Server.Services.ProfileMenuService),
	createSessionCommandService = require(Server.Services.SessionCommandService),
	createAfkGuardService = require(Server.Services.AfkGuardService),
	createCommandExecutionService = require(Server.Services.CommandExecutionService),
	createSyncService = require(Server.Services.SyncService),
	createDonationService = require(Server.Services.DonationService),
	LicenseService = require(Server.Services.LicenseService),
	createDonationEffectService = require(Server.Services.DonationEffectService),
	createStickerService = require(Server.Services.StickerService),
	createSettingsService = require(Server.Services.SettingsService),
	RoleToolService = require(Server.Services.RoleToolService),
	createPlayerSnapshotService = require(Server.Services.PlayerSnapshotService),
	createBackgroundJobScheduler = require(Server.Services.BackgroundJobScheduler),
	InterestManager = require(Kit.Shared.Utils.InterestManager),
	createProximityInterestService = require(Server.Services.ProximityInterestService),
	createGenericBroadcastService = require(Server.Services.GenericBroadcastService),
	createJoinGreetingService = require(Server.Services.JoinGreetingService),
	createJoinCommunityMembersService = require(Server.Services.JoinCommunityMembersService),
	createCommunityVipService = require(Server.Services.CommunityVipService),

	-- Controllers
	createOverheadController = require(Server.Controllers.OverheadController),
	createCoupleController = require(Server.Controllers.CoupleController),
	createShopController = require(Server.Controllers.ShopController),
	createStreakController = require(Server.Controllers.StreakController),
	createLevelController = require(Server.Controllers.LevelController),
	createAdminController = require(Server.Controllers.AdminController),
	createAvatarContextController = require(Server.Controllers.AvatarContextController),
	createAvatarLikeController = require(Server.Controllers.AvatarLikeController),
	createCarryController = require(Server.Controllers.CarryController),
	createGravityController = require(Server.Controllers.GravityController),
	createProfileMenuController = require(Server.Controllers.ProfileMenuController),
	createCommandLibraryController = require(Server.Controllers.CommandLibraryController),
	createChatCommandController = require(Server.Controllers.ChatCommandController),
	createSyncController = require(Server.Controllers.SyncController),
	createDonationController = require(Server.Controllers.DonationController),
	createStickerController = require(Server.Controllers.StickerController),
	createSettingsController = require(Server.Controllers.SettingsController),
	createPaidBroadcastController = require(Server.Controllers.PaidBroadcastController),
	createCinematicDockController = require(Server.Controllers.CinematicDockController),

	-- Repositories
	OverheadRepository = require(Server.Repositories.OverheadRepository),
	ProfileRepository = require(Server.Repositories.ProfileRepository),
	createAboutRosterRepository = require(Server.Repositories.AboutRosterRepository),
	AvatarLikeRepository = require(Server.Repositories.AvatarLikeRepository),
	DonationLeaderboardRepository = require(Server.Repositories.DonationLeaderboardRepository),
	GiftPendingRepository = require(Server.Repositories.GiftPendingRepository),
	ManualBagibagiRepository = require(Server.Repositories.ManualBagibagiRepository),
	StickerRepository = require(Server.Repositories.StickerRepository),
	SettingsRepository = require(Server.Repositories.SettingsRepository),
	FavoritesRepository = require(Server.Repositories.FavoritesRepository),
	ProfileLoader = require(Server.Repositories.ProfileLoader),

	-- Shared helpers used by Main wiring
	HttpApiCounter = require(Kit.Shared.Utils.HttpApiCounter),
	Result = require(Kit.Shared.Utils.Result),
	Validator = require(Kit.Shared.Utils.Validator),
	RateLimiter = require(Kit.Shared.Utils.RateLimiter),
	TaskQueue = require(Kit.Shared.Utils.TaskQueue),
	EventBus = require(Kit.Shared.Utils.EventBus),
	CarryDomain = require(Kit.Shared.Domain.CarryDomain),
	SyncDomain = require(Kit.Shared.Domain.SyncDomain),
	NetworkManager = require(Kit.Shared.Utils.NetworkManager),
	AnimationLoader = require(Kit.Shared.ContextModule.AnimationLoader),
}
