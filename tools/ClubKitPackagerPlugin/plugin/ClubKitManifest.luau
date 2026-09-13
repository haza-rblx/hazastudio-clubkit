--!nocheck
-- Club Kit asset manifest for automated export / unpack.

local ClubKitManifest = {}

ClubKitManifest.PACKAGE_NAME = "HazastudioClubKit_Package"
ClubKitManifest.MANIFEST_NAME = "_ClubKitManifest"
ClubKitManifest.PRODUCT_ID = "hazastudioclubkit"
ClubKitManifest.KIT_VERSION = "2.12.0"
-- Soft-update version for the Studio dock (may diverge from KIT_VERSION for plugin-only fixes).
ClubKitManifest.PLUGIN_VERSION = "2.12.0"

-- Soft-update: fetch these Luau modules from GitHub tags (exclude bootstrap).
ClubKitManifest.PLUGIN_SOURCE_PREFIX = "tools/ClubKitPackagerPlugin/plugin/"
ClubKitManifest.PLUGIN_BOOTSTRAP = "HazastudioClubKit.plugin.luau"
ClubKitManifest.PLUGIN_APPLIED_TAG_SETTING = "ClubKit_PluginAppliedTag"

-- Engine folder per service (entire subtree cloned).
ClubKitManifest.SERVICE_ROOTS = {
	{ service = "ReplicatedFirst", name = "Hazastudio_ClubKit" },
	{ service = "ReplicatedStorage", name = "Hazastudio_ClubKit" },
	{ service = "ReplicatedStorage", name = "Icon" },
	{ service = "ServerScriptService", name = "Hazastudio_ClubKit" },
	{ service = "StarterPlayerScripts", name = "Hazastudio_ClubKit" },
}

-- Optional — buyer config & secrets (can be skipped on export update).
ClubKitManifest.OPTIONAL_ROOTS = {
	{ service = "ReplicatedStorage", name = "Hazastudio_ClubKitConfig", key = "config" },
	{ service = "ServerScriptService", name = "Hazastudio_ClubKitSecrets", key = "secrets" },
}

ClubKitManifest.STARTER_GUI_EXACT = {
	"00-LoadingScreen",
	"01-CoupleSystemGUI",
	"02-ShopGUI",
	"03-GiftSystemGUI",
	"04-AdminPanel",
	"04-AdminPanelv2",
	"04-AdminPanelv3",
	"04-AdminHub",
	"05-StreakGUI",
	"06-MusicPlayerGUI",
	"07-MenuGUI",
	"08-CarryGUI",
	"09-DonationSystemGUI",
	"10-HotbarGUI",
	"11-StickerSystemGUI",
	"12-CinematicDockGUI",
	"13-PaidBroadcast",
	"14-BackpackGUI",
	"15-TopMenuGUI",
	"16-JoinCommunPrompt",
	"99-NotificationCenter",
	"99-NotificationCenterV2",
	"1000-01-CT-ADDON",
	"AvatarContextMenu",
	"CommandLibraryGUI",
	"HotbarGUI",
	"IconGroup",
	"MobileFreecam",
	"SignGui",
}

-- Workspace: board + poster + donation display roots.
ClubKitManifest.WORKSPACE_EXACT = {
	"RobuxDonationBoard",
	"CommunityDonationBoard",
	"SaweriaDonationBoard",
	"LikesLeaderboard",
	"Top1Robux",
	"Top2Robux",
	"Top3Robux",
	"Top1Cash",
	"Top2Cash",
	"Top3Cash",
}

-- Multiple instances may share the same name (e.g. several RunningText).
ClubKitManifest.WORKSPACE_MULTI = {
	"LiveChatDonations",
	"RunningText",
}

-- Pack entire board folder (preserves hazastudioBoard layout). Individual WORKSPACE_EXACT
-- entries under this folder are skipped when the folder is packed.
ClubKitManifest.WORKSPACE_BOARD_FOLDER = "hazastudioBoard"

-- Never ship in the main template pack (SyncBhms place-pack — see extras/place-packs/SyncBhms/).
ClubKitManifest.BHMS_EXCLUDE_NAMES = {
	"SyncBhmsGate",
	"SyncBhmsAcmBridge",
	"Remotes2",
	"StoredAnimations",
	"SyncSettings",
	"SyncBhmsRemotes",
	"SyncServer",
	"DanceGui",
	"SyncBhms",
	"TopbarDance",
	"danceDraging",
	"danceDraging1",
	"BeatDanceClient",
}

-- Legacy per-service exclude table (unpack / docs); BHMS_EXCLUDE_NAMES is authoritative for template pack.
ClubKitManifest.COLLECT_EXCLUDE = {
	{ service = "ReplicatedStorage", names = { "SyncBhmsGate", "SyncBhmsAcmBridge", "Remotes2", "StoredAnimations", "SyncSettings" } },
	{ service = "ServerScriptService", names = { "SyncBhmsRemotes", "SyncServer" } },
	{ service = "StarterGui", names = { "DanceGui" } },
	{ service = "StarterPlayerScripts", names = { "TopbarDance", "danceDraging", "danceDraging1", "BeatDanceClient" } },
	{ service = "Workspace", names = { "SyncBhms" } },
}

-- Template place: clone every child in these services (not manifest pick-list).
ClubKitManifest.FULL_SERVICE_PACK = {
	"ReplicatedFirst",
	"ReplicatedStorage",
	"ServerScriptService",
	"ServerStorage",
	"StarterGui",
	"Workspace",
	"Lighting",
}

ClubKitManifest.WORKSPACE_SKIP = {
	"Camera",
	"Terrain",
}

-- Buyer-place pack (PackagerCore.collectFromBuyerPlace). FULL_SERVICE_PACK is right for the
-- template place, where everything present IS the kit; a buyer place is full of systems the kit
-- does not own (ETH*, Cenz*, Paanz, admin loaders, migration scratch, and the venue map itself),
-- and shipping one of those to another buyer is a licensing problem, not a cosmetic one. So this
-- mode is an **allowlist**: anything not named here is left behind by construction, and a new
-- non-kit system added to a venue tomorrow cannot leak into a pack built the day after.
--
-- StarterGui uses STARTER_GUI_EXACT. Workspace is never taken wholesale — only the board folder
-- and the donation/leaderboard roots (WORKSPACE_BOARD_FOLDER / WORKSPACE_EXACT / WORKSPACE_MULTI).
-- Lighting is skipped entirely: it carries the venue's own look (Sky, Atmosphere, colour grading),
-- which is place data, not kit data.
ClubKitManifest.PLACE_PACK_ALLOW = {
	ReplicatedFirst = { "Hazastudio_ClubKit" },
	ReplicatedStorage = {
		"Hazastudio_ClubKit",
		"Icon",
		"TopbarPlus",
		"WorldEffects",
		"Emotes",
		"Carry",
		"OverheadGUIMainTemplateV4",
		"OverheadGUIMainTemplateV5",
	},
	ServerScriptService = { "Hazastudio_ClubKit" },
	ServerStorage = { "DonationEffects", "DonationSounds", "Tools" },
	StarterPlayerScripts = { "Hazastudio_ClubKit" },
}

-- Services a buyer-place pack never reads at all.
ClubKitManifest.PLACE_PACK_SKIP_SERVICES = { "Lighting" }

-- In a buyer-place pack the buyer's own `ClubKitConfig` and `Secrets` must never ship: they carry
-- that venue's group id, product ids, donation URL and branding. The pack carries the kit template
-- instead, fetched from the repo at build time (see PackagerCore.collectFromBuyerPlace).
ClubKitManifest.PLACE_PACK_TEMPLATE_SOURCES = {
	config = "src/ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau",
	secrets = "src/ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau",
}

ClubKitManifest.SYNC_BHMS_ADDON_PACKAGE_NAME = "HazastudioClubKit_SyncBhmsAddon"

-- Deprecated alias (was Group config — add-on is SyncBhms only).
ClubKitManifest.GROUP_ADDON_PACKAGE_NAME = ClubKitManifest.SYNC_BHMS_ADDON_PACKAGE_NAME

ClubKitManifest.SERVER_STORAGE_EXACT = {
	"Tools",
	"DonationEffects",
	"DonationSounds",
}

ClubKitManifest.WORLD_EFFECTS = {
	"Nuke",
	"BlackHole",
	"Smite3",
	"Smite4",
}

ClubKitManifest.SERVICE_ALIASES = {
	StarterPlayerScripts = "StarterPlayerScripts",
	Workspace = "Workspace",
}

-- Source-sync updater (GitHub tag → set Script.Source in place).
ClubKitManifest.UPDATER = {
	githubOwner = "haza-rblx",
	githubRepo = "hazastudio-clubkit",
	defaultBranch = "main",
	versionFile = "VERSION",
	changelogFile = "CHANGELOG.md",
}

-- Repo paths allowed for Luau engine sync (under src/).
ClubKitManifest.ENGINE_SOURCE_PREFIXES = {
	"src/ReplicatedFirst/Hazastudio_ClubKit/",
	"src/ReplicatedStorage/Hazastudio_ClubKit/",
	"src/ReplicatedStorage/Icon/",
	"src/ServerScriptService/Hazastudio_ClubKit/",
	"src/StarterPlayerScripts/StarterPlayerScripts/Hazastudio_ClubKit/",
}

-- Never fetch or overwrite these repo paths.
ClubKitManifest.PROTECTED_SOURCE_PREFIXES = {
	"src/ReplicatedStorage/Hazastudio_ClubKitConfig/",
	"src/ServerScriptService/Hazastudio_ClubKitSecrets/",
}

-- Engine paths under ENGINE_SOURCE_PREFIXES that must NOT ship to buyers (dev/demo only).
-- ClubKitShowcase lives under tools/dev/ (outside ENGINE_SOURCE_PREFIXES); keep exclude
-- for any legacy path still present on older tags / stale places.
ClubKitManifest.ENGINE_SOURCE_EXCLUDES = {
	"src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ClubKitShowcase.luau",
}

return ClubKitManifest
