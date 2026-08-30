--!strict
--[[
  Hierapolis Theatre custom overlay — ModuleScript
  Parent: ReplicatedStorage.Hazastudio_ClubKitConfig.HierapolisCustom  (buyer-owned folder; never
  touched by Update Engine).

  Switched on/off by ONE flag in the buyer config, like every other kit feature:
      ClubKitConfig.Features.HierapolisCustom = true | false
  ConfigBootstrap (engine) merges this table over the buyer config at boot when the flag is true.
  false = the place runs the stock kit catalog + kit loading screen; this module is ignored.

  Merge rules (ConfigBootstrap.applyHierapolisCustom):
    RoleCategories / LegacyAliases / CommandAliases  → replaced wholesale
    SystemRoles.<key>                                → that entry replaced wholesale
    Features                                         → merged key by key
  ClubKitConfig.luau itself is never rewritten. Edit THIS file to change the catalog.
]]

local HierapolisCustom = {}

-- Hierapolis Theatre catalog. All roles here are /setrole roles (the COMA Studio group only
-- has Member / Dev / Admin / Owner ranks). The four DPC roles share chatTag "DPC" (Rank row,
-- chat tag, player list) while their unique name lives in the overhead chip
-- (specialRank.chip = true, painted with roleColor.stops; hides that role's #N rank chips).
HierapolisCustom.RoleCategories = {
	{
		id = 1,
		label = "Leadership",
		priority = 140,
		enabled = true,
		privileges = { canGift = true, canAnnounce = true, canTeleport = true, adminPanel = true, musicManage = true },
		roles = {
			{
				key = "CoOwner", -- rank row / chat tag stay CO-OWNER; "THE ARCHON" lives in the chip
				label = "Co-Owner",
				chatTag = "CO-OWNER",
				toolFolder = "CO-OWNER",
				teamColor = "Ghost grey",
				enabled = true,
				specialRank = { text = "THE ARCHON", gradient = true, chip = true },
				badgeFrames = { "01-OwnerCoOwnerBadge" },
				roleColor = { stops = { "000000", "2b2b2b", "808080", "c0c0c0", "f1f4f4" } }, -- chat = first stop (owner call)
			},
		},
	},
	{
		-- DPC: one category, four functions. Category = the Admin set; roles that do less
		-- override it with their own `privileges`.
		id = 2,
		label = "DPC",
		priority = 130,
		enabled = true,
		privileges = { canGift = true, canAnnounce = true, canTeleport = true, adminPanel = true, musicManage = true },
		roles = {
			{
				key = "Emperor", -- Scripter: full
				label = "The Emperor",
				chatTag = "DPC",
				toolFolder = "THE EMPEROR",
				teamColor = "Really red",
				enabled = true,
				specialRank = { text = "THE EMPEROR", gradient = true, chip = true },
				badgeFrames = { "02-DeveloperBadge" },
				-- Red ramp derived from the old RoleConfig accent #DE3B20 (buyer did not supply stops).
				roleColor = { stops = { "7f1d1d", "b91c1c", "de3b20", "f87171", "fca5a5" } },
			},
			{
				key = "Echoborn", -- Operational: announce + teleport + music, no gift / admin panel
				label = "The Echoborn",
				chatTag = "DPC",
				toolFolder = "THE ECHOBORN",
				teamColor = "Royal purple",
				enabled = true,
				privileges = { canGift = false, adminPanel = false },
				specialRank = { text = "THE ECHOBORN", gradient = true, chip = true },
				badgeFrames = { "03-AdminBadge" },
				roleColor = { stops = { "4b0082", "8a2be2", "e086d1", "8a2be2", "d388e0" } },
			},
			{
				key = "Minister", -- Admin: full
				label = "The Minister",
				chatTag = "DPC",
				toolFolder = "THE MINISTER",
				teamColor = "Deep orange",
				enabled = true,
				specialRank = { text = "THE MINISTER", gradient = true, chip = true },
				badgeFrames = { "03-AdminBadge" },
				roleColor = { stops = { "fa6c14", "f18e37", "f59b21", "f7a640", "ffdd00" } },
			},
			{
				key = "LeadDance", -- Lead Dancer (engine key for the Lead Dance topbar / sync lead): music + announce
				label = "The Senator",
				chatTag = "DPC",
				toolFolder = "THE SENATOR",
				teamColor = "Bright violet",
				enabled = true,
				privileges = { canGift = false, canTeleport = false, adminPanel = false },
				specialRank = { text = "THE SENATOR", gradient = true, chip = true },
				showSpecialStatus = true,
				roleColor = { stops = { "301a9e", "5141d7", "5fec4c", "fafa3e", "e61b23" } }, -- form said "e61b2" (typo) → #E61B23 from old accent
			},
		},
	},
	{
		id = 3,
		label = "Content",
		priority = 120,
		enabled = true,
		privileges = { canGift = false, canAnnounce = false, canTeleport = false, adminPanel = false, musicManage = true },
		roles = {
			{
				key = "DJ",
				label = "DJ",
				chatTag = "DJ",
				toolFolder = "DJ",
				teamColor = "Cyan",
				enabled = true,
				specialRank = { text = "DJ", gradient = true },
				showSpecialStatus = true,
				roleColor = { primary = "#06B6D4", secondary = "#67E8F9" },
			},
			{
				key = "Streamer",
				label = "Streamer",
				chatTag = "STREAMER",
				toolFolder = "STREAMER",
				teamColor = "Magenta",
				enabled = true,
				specialRank = { text = "STREAMER", gradient = true },
				showSpecialStatus = true,
				roleColor = { primary = "#C026D3", secondary = "#E879F9" },
			},
			{
				key = "Influencer",
				label = "Influencer",
				chatTag = "INFLUENCER",
				toolFolder = "INFLUENCER",
				teamColor = "Hot pink",
				enabled = true,
				specialRank = { text = "INFLUENCER", gradient = true },
				showSpecialStatus = true,
				roleColor = { primary = "#DB2777", secondary = "#F9A8D4" },
			},
		},
	},
} :: { any }

HierapolisCustom.SystemRoles = {
	Owner = { -- rank row / chat tag stay OWNER; "THE PRESIDENT" lives in the chip
		label = "Owner",
		chatTag = "OWNER",
		priority = 15000,
		groupRanks = { 255 },
		specialRank = { text = "THE PRESIDENT", gradient = true, chip = true },
		roleColor = { stops = { "daad18", "ffed2a", "fdff90", "daad18", "f4e628" } },
		teamColor = "Gold",
		badgeFrames = { "01-OwnerCoOwnerBadge" },
		canGift = true,
		giftable = false,
	},
} :: { [string]: any }

HierapolisCustom.LegacyAliases = {
	-- Stored role names from the kit's stock catalog (this place ran 2.9.0 with Staff/Moderator).
	Staff = "Minister",
	Moderator = "Minister",
	Admin = "Minister",
	AfterTeam = "Minister",
	Investor = "Minister",
	Developer = "Emperor",
	Scripter = "Emperor",
	Spender = "RoyaleSpender",
	Tier1 = "VIP",
	Tier2 = "VVIP",
	Tier3 = "Supreme",
	VIPMember = "VIP",
	VVIPMember = "VVIP",
	SupremeMember = "Supreme",
	ELITEMember = "Supreme",
	Exclusive = "Supreme",
	Member = "Guest",
	["The President"] = "Owner",
	["THE PRESIDENT"] = "Owner",
	["The Archon"] = "CoOwner",
	["THE ARCHON"] = "CoOwner",
	["Co-Owner"] = "CoOwner",
	["co-owner"] = "CoOwner",
	coowner = "CoOwner",
	["The Emperor"] = "Emperor",
	["THE EMPEROR"] = "Emperor",
	["The Echoborn"] = "Echoborn",
	["THE ECHOBORN"] = "Echoborn",
	["The Minister"] = "Minister",
	["THE MINISTER"] = "Minister",
	["The Senator"] = "LeadDance",
	["THE SENATOR"] = "LeadDance",
	["Lead Dance"] = "LeadDance",
	["lead dance"] = "LeadDance",
	["Top Donor"] = "TopSpender",
	["top donor"] = "TopSpender",
	["Top Rupiah Spender"] = "TopSpender",
	["top rupiah spender"] = "TopSpender",
	["Top Spender"] = "TopSpender",
	["top spender"] = "TopSpender",
	["Top Supporter"] = "RoyaleSpender",
	["top supporter"] = "RoyaleSpender",
	["Top Robux Donator"] = "RoyaleSpender",
	["top robux donator"] = "RoyaleSpender",
	["Royale Spender"] = "RoyaleSpender",
	["royale spender"] = "RoyaleSpender",
} :: { [string]: string }

HierapolisCustom.CommandAliases = {
	owner = "Owner",
	president = "Owner",
	["the president"] = "Owner",
	archon = "CoOwner",
	["the archon"] = "CoOwner",
	coowner = "CoOwner",
	["co-owner"] = "CoOwner",
	emperor = "Emperor",
	["the emperor"] = "Emperor",
	scripter = "Emperor",
	developer = "Emperor",
	dev = "Emperor",
	minister = "Minister",
	["the minister"] = "Minister",
	admin = "Minister",
	staff = "Minister",
	mod = "Minister",
	moderator = "Minister",
	echoborn = "Echoborn",
	["the echoborn"] = "Echoborn",
	operational = "Echoborn",
	senator = "LeadDance",
	["the senator"] = "LeadDance",
	["lead dancer"] = "LeadDance",
	["lead dance"] = "LeadDance",
	leaddance = "LeadDance",
	lead = "LeadDance",
	dj = "DJ",
	streamer = "Streamer",
	influencer = "Influencer",
	creator = "Streamer",
	supreme = "Supreme",
	exclusive = "Supreme",
	elite = "Supreme",
	suprememember = "Supreme",
	elitemember = "Supreme",
	tier3 = "Supreme",
	vvip = "VVIP",
	vvipmember = "VVIP",
	tier2 = "VVIP",
	vip = "VIP",
	vipmember = "VIP",
	tier1 = "VIP",
	["top donor"] = "TopSpender",
	topdonor = "TopSpender",
	["top rupiah spender"] = "TopSpender",
	toprupiahspender = "TopSpender",
	["top spender"] = "TopSpender",
	topspender = "TopSpender",
	["top supporter"] = "RoyaleSpender",
	topsupporter = "RoyaleSpender",
	["top robux donator"] = "RoyaleSpender",
	toprobuxdonator = "RoyaleSpender",
	["royale spender"] = "RoyaleSpender",
	royalespender = "RoyaleSpender",
	spender = "RoyaleSpender",
	guest = "Guest",
	member = "Guest",
	none = "none",
	remove = "none",
} :: { [string]: string }

-- Kit loading screen off → ReplicatedFirst.CinematicLoading (place pack) owns boot.
HierapolisCustom.Features = {
	LoadingScreen = false,
} :: { [string]: boolean }

return HierapolisCustom
