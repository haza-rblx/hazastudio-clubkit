--!nocheck
-- Manifest aset Club Kit v1.3 untuk export / unpack otomatis.

local ClubKitManifest = {}

ClubKitManifest.PACKAGE_NAME = "HazastudioClubKit_Package"
ClubKitManifest.MANIFEST_NAME = "_ClubKitManifest"
ClubKitManifest.PRODUCT_ID = "hazastudioclubkit"
ClubKitManifest.KIT_VERSION = "2.0.0"

-- Folder engine per service (seluruh subtree di-clone).
ClubKitManifest.SERVICE_ROOTS = {
	{ service = "ReplicatedFirst", name = "Hazastudio_ClubKit" },
	{ service = "ReplicatedStorage", name = "Hazastudio_ClubKit" },
	{ service = "ReplicatedStorage", name = "Icon" },
	{ service = "ServerScriptService", name = "Hazastudio_ClubKit" },
	{ service = "StarterPlayerScripts", name = "Hazastudio_ClubKit" },
}

-- Opsional — buyer config & secrets (bisa di-skip saat export update).
ClubKitManifest.OPTIONAL_ROOTS = {
	{ service = "ReplicatedStorage", name = "Hazastudio_ClubKitConfig", key = "config" },
	{ service = "ServerScriptService", name = "Hazastudio_ClubKitSecrets", key = "secrets" },
}

ClubKitManifest.STARTER_GUI_EXACT = {
	"01-CoupleSystemGUI",
	"02-ShopGUI",
	"03-GiftSystemGUI",
	"04-AdminPanelv2",
	"04-AdminPanel",
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
	"99-NotificationCenter",
	"CommandLibraryGUI",
	"HotbarGUI",
	"IconGroup",
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

-- Bisa ada banyak instance dengan nama sama (mis. beberapa RunningText).
ClubKitManifest.WORKSPACE_MULTI = {
	"LiveChatDonations",
	"RunningText",
}

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

return ClubKitManifest
