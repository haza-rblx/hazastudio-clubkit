--!strict
--[[
  CLUB KIT CONFIG — satu file ini yang buyer edit per place.
  Path: ReplicatedStorage.Hazastudio_ClubKitConfig.ClubKitConfig

  QUICK START (isi dulu sebelum publish):
  ┌─────────────────────────────────────────────────────────────────┐
  │ 1. Group.GroupId      → angka ID group Roblox kamu              │
  │ 2. Group.OwnerUserId  → userId owner (rank 255 / owner cmds)    │
  │ 3. Donation.ApiUrl    → URL worker Bagi-Bagi (kosong = no live) │
  │ 4. Shop.Products      → Developer Product ID (Creator Dashboard)│
  │ 5. PaidBroadcast      → ProductId broadcast berbayar (Robux)    │
  │ 6. Membership           → nama tier VIP/VVIP/Supreme (section bawah)│
  │ 7. RoleCategories       → role group, rank, warna, privilege    │
  │ 8. Secrets.luau       → API secret (folder Hazastudio_ClubKitSecrets) │
  └─────────────────────────────────────────────────────────────────┘

  Live mode: hapus ClubKitShowcase.luau dari engine (auto real mode).
  Demo mode: biarkan ClubKitShowcase.luau ada (auto showcase leaderboard).
]]

local ClubKitConfig = {}

-- =============================================================================
-- BRANDING
-- =============================================================================
ClubKitConfig.Branding = {
	GameName = "Club", -- tampil di VFX donasi / label umum
	WelcomeMessage = "Welcome to the club, %s", -- tap to continue (%s = nama player)
	Greeting = "Welcome to the club, %s", -- loading screen awal
	-- Diganti sekali di sini → loading, poster, leaderboard, Join Community modal.
	-- Ganti dari ID bawaan kit ke logo community kamu.
	LogoImage = "rbxassetid://79426970537296",
}

-- =============================================================================
-- GROUP & ADMIN
-- =============================================================================
ClubKitConfig.Group = {
	GroupId = 0, -- contoh: 12345678  ← WAJIB sebelum live
	OwnerUserId = 8842050215, -- contoh: 987654321  ← owner place / /showcase
	OwnerGroupRank = 255, -- rank Roblox yang dianggap owner di group
}

ClubKitConfig.AdminUserIds = {
	[8842050215] = true, -- backup admin tanpa group rank; contoh: [111111] = true,
} :: { [number]: boolean }

-- Sementara leaderboard warm-up (opsional): [userId] = rank
ClubKitConfig.TopSpenders = {} :: { [number]: number }

ClubKitConfig.GameDataApi = {
	GameKey = "the-basic", -- must match D1/wrangler SECRET_<GAME_KEY> (community open to all authenticated keys)
}

-- =============================================================================
-- DONASI (Bagi-Bagi / Saweria + threshold aura)
-- =============================================================================
ClubKitConfig.Donation = {
	Provider = "bagibagi", -- "bagibagi" | "saweria" — nama & label donor otomatis
	ProviderLink = "", -- contoh: "https://bagibagi.co/halaman-kamu"
	ApiUrl = "https://hazastudio-donation-api.hazastudio.workers.dev/game/the-basic",
	Cash = { Enabled = true },
	Robux = { Enabled = true },
	-- Opsional: daftar product donasi Robux manual. Kosong = auto dari dashboard.
	RobuxProducts = {} :: { { ProductId: number, Name: string?, Price: number? } },

	-- Min IDR agar masuk notif + leaderboard (bukan tier aura).
	MinAmount = 1000,

	-- Posisi stage world VFX Rocket / Hammer / BlackHole (impact / anchor).
	-- Rocket descends to this Vector3. Optional workspace.NukeModel = launch pad only.
	NukeWorldPosition = Vector3.new(-262.2, 1.285, 64.9),

	-- Aura per player (folder ServerStorage.DonationEffects/LevelN).
	-- min = Robux | idrMin/idrMax = range Bagi-Bagi | effect/sound = nama folder asset.
	AuraTiers = {
		{ level = 1, min = 10, idrMin = 0, idrMax = 9999, effect = "Level1", sound = "Level1", duration = 4, cameraDuration = 0 },
		{ level = 3, min = 80, idrMin = 10000, idrMax = 19999, effect = "Level3", sound = "Level3", duration = 4, cameraDuration = 0 },
		{ level = 4, min = 150, idrMin = 20000, idrMax = 29999, effect = "Level4", sound = "Level4", duration = 4, cameraDuration = 0 },
		{ level = 5, min = 250, idrMin = 30000, idrMax = 49999, effect = "Level5", sound = "Level5", duration = 5, cameraDuration = 0 },
		{ level = 6, min = 500, idrMin = 50000, idrMax = 99999, effect = "Level6", sound = "Level6", duration = 5, cameraDuration = 6 },
		{ level = 7, min = 1000, idrMin = 100000, idrMax = 199999, effect = "Level7", sound = "Level7", duration = 6, cameraDuration = 8 },
		{ level = 8, min = 2000, idrMin = 200000, idrMax = 299999, effect = "Level8", sound = "Level8", duration = 6, cameraDuration = 7 },
		{ level = 9, min = 3000, idrMin = 300000, idrMax = 499999, effect = "Level9", sound = "Level9", duration = 8, cameraDuration = 8 },
		{ level = 10, min = 5000, idrMin = 500000, idrMax = 999999, effect = "Level10", sound = "Level10", duration = 8, cameraDuration = 8 },
		{ level = 11, min = 10000, idrMin = 1000000, idrMax = math.huge, effect = "Level11", sound = "Level11", duration = 8, cameraDuration = 8 },
	},

	-- World VFX Bagi-Bagi (model di ReplicatedStorage.WorldEffects). Robux tidak pakai ini.
	WorldEffectTiers = {
		{ min = 500000, effect = "BlackHole" }, -- 500k+ IDR
		{ min = 250000, effect = "Smite4" }, -- 250k+ IDR (hammer)
		{ min = 100000, effect = "Nuke" }, -- 100k+ IDR (rocket)
	},
}

-- =============================================================================
-- CARRY (ganti carrier/carried = animation asset ID kamu)
-- =============================================================================
ClubKitConfig.Carry = {
	MaxDistance = 30, -- stud, max jarak request carry
	StyleOrder = { "Piggyback", "Bridal", "Hug", "Tandem", "Fireman", "Choke" },
	Styles = {
		Piggyback = {
			displayName = "Piggyback",
			offset = { 0, 0.6, 1.04 },
			rotation = { 0, 0, 0 },
			inverse = false,
			animations = { carrier = 115515926107349, carried = 115582640665333 },
		},
		Bridal = {
			displayName = "Bridal",
			offset = { -0.3, -0.3, -1 },
			rotation = { 90, -40, 80 },
			inverse = false,
			animations = { carrier = 124694567927517, carried = 86225400469700 },
		},
		Hug = {
			displayName = "Hug",
			offset = { 0, 0.6, -1.2 },
			rotation = { -25, 180, 0 },
			inverse = false,
			animations = { carrier = 109164859945110, carried = 104481004729845 },
		},
		Tandem = {
			displayName = "Tandem",
			offset = { 0, 2.5, 1.13 },
			rotation = { 0, 0, 0 },
			inverse = false,
			animations = { carrier = 127862988109007, carried = 81159906003051 },
		},
		Fireman = {
			displayName = "Fireman",
			offset = { 0, 0, 0 },
			rotation = { 0, 0, 0 },
			inverse = false,
			c0Kind = "fireman",
			animations = { carrier = 79382117962204, carried = 81566698560357 },
		},
		Choke = {
			displayName = "Choke",
			offset = { 0, 1.15, -1.7 },
			rotation = { -25, 180, 0 },
			inverse = false,
			animations = { carrier = 119666059337986, carried = 72170969732590 },
		},
	},
}

-- =============================================================================
-- LOADING SCREEN
-- =============================================================================
ClubKitConfig.Loading = {
	CinematicAnimationId = "rbxassetid://78416657618448", -- anim dance saat loading cinematic
}

-- =============================================================================
-- SHOP MEMBERSHIP (Developer Products — aktifkan di Creator Dashboard)
-- =============================================================================
ClubKitConfig.Shop = {
	Products = {
		Tier1 = { BuyId = 3608406407, GiftId = 3608406587, Price = 1 }, -- VIP
		Tier2 = { BuyId = 3608406452, GiftId = 3608406626, Price = 1 }, -- VVIP
		Tier3 = { BuyId = 3608406486, GiftId = 3608406664, Price = 1 }, -- Supreme
	},
}

-- =============================================================================
-- PAID BROADCAST (Developer Product — pesan broadcast ke seluruh server)
-- =============================================================================
ClubKitConfig.PaidBroadcast = {
	ProductId = 3503700307, -- ganti dengan Product ID dari Creator Dashboard
}

-- =============================================================================
-- MEMBERSHIP (nama tier shop)
-- Label = tampilan di UI/chat. Tier1/2/3 = key internal (jangan diubah).
-- Kalau ganti Label, update CommandAliases di bawah (vip/supreme/dll).
-- =============================================================================
ClubKitConfig.Membership = {
	Tier1 = { Label = "VIP", Enabled = true, Priority = 40 },
	Tier2 = { Label = "VVIP", Enabled = true, Priority = 50 },
	Tier3 = { Label = "Supreme", Enabled = true, Priority = 60 },
}

-- =============================================================================
-- ROLE CATEGORIES (group rank → role; sesuaikan dengan group Roblox kamu)
-- privileges per category: canGift, canAnnounce, canTeleport, adminPanel, musicManage
-- =============================================================================
ClubKitConfig.RoleCategories = {
	{
		id = 1,
		label = "Leadership",
		priority = 140,
		enabled = true,
		privileges = {
			canGift = true,
			canAnnounce = true,
			canTeleport = true,
			adminPanel = true,
			musicManage = true,
		},
		roles = {
			{
				key = "Staff",
				label = "Staff",
				chatTag = "STAFF",
				toolFolder = "STAFF",
				teamColor = "Royal purple",
				enabled = true,
				specialRank = { text = "STAFF", gradient = true },
				badgeFrames = { "03-AdminBadge" },
				roleColor = { primary = "#7C3AED", secondary = "#A78BFA" },
			},
		},
	},
	{
		id = 2,
		label = "Moderation",
		priority = 130,
		enabled = true,
		privileges = {
			canGift = false,
			canAnnounce = true,
			canTeleport = true,
			adminPanel = false,
			musicManage = false,
		},
		roles = {
			{
				key = "Moderator",
				label = "Moderator",
				chatTag = "MODERATOR",
				toolFolder = "MODERATOR",
				teamColor = "Bright violet",
				enabled = true,
				specialRank = { text = "MODERATOR", gradient = true },
				roleColor = { primary = "#8B5CF6", secondary = "#C4B5FD" },
			},
		},
	},
	{
		id = 3,
		label = "Content",
		priority = 120,
		enabled = true,
		privileges = {
			canGift = false,
			canAnnounce = false,
			canTeleport = false,
			adminPanel = false,
			musicManage = true,
		},
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
				key = "LeadDance",
				label = "Lead Dance",
				chatTag = "LEAD DANCE",
				toolFolder = "LEAD DANCE",
				teamColor = "Really red",
				enabled = true,
				specialRank = { text = "LEAD DANCE", gradient = true },
				showSpecialStatus = true,
				roleColor = { primary = "#BE123C", secondary = "#FB7185" },
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

-- =============================================================================
-- SPENDER ROLES (leaderboard donor — label/chatTag bebas diedit)
-- =============================================================================
ClubKitConfig.SpenderRoles = {
	Donatur = {
		Enabled = true,
		Key = "Donatur",
		Label = "Donor",
		ChatTag = "DONOR",
		ToolFolder = "DONOR",
		Priority = 70,
		TeamColor = "Bright green",
		roleColor = { primary = "#22C55E", secondary = "#86EFAC" },
		giftable = true,
	},
	CashSpender = {
		Enabled = true,
		Key = "TopSpender",
		Label = "Top Donor",
		ChatTag = "TOP DONOR",
		ToolFolder = "TOP DONOR",
		MaxRank = 10,
		Priority = 80,
		TeamColor = "Lime green",
		roleColor = { primary = "#84CC16", secondary = "#BEF264" },
		Privileges = {
			canAnnounce = true,
			canTeleport = true,
		},
	},
	RobuxSpender = {
		Enabled = true,
		Key = "RoyaleSpender",
		Label = "Top Supporter",
		ChatTag = "TOP SUPPORTER",
		ToolFolder = "TOP SUPPORTER",
		MaxRank = 100,
		Priority = 90,
		TeamColor = "Bright bluish green",
		roleColor = { primary = "#14B8A6", secondary = "#5EEAD4" },
		SpecialRank = { text = "TOP SUPPORTER", gradient = true },
		Privileges = {
			canAnnounce = true,
			canTeleport = true,
		},
	},
}

-- =============================================================================
-- SYSTEM ROLES (Owner/Guest — groupRanks = rank Roblox group)
-- =============================================================================
ClubKitConfig.SystemRoles = {
	Owner = {
		label = "Owner",
		chatTag = "OWNER",
		priority = 15000,
		groupRanks = { 255 },
		specialRank = { text = "OWNER", gradient = true },
		roleColor = { primary = "#FFD700", secondary = "#FFF0A0" },
		teamColor = "Gold",
		badgeFrames = { "01-OwnerCoOwnerBadge" },
		canGift = true,
		giftable = false,
	},
	Guest = {
		label = "Guest",
		chatTag = "GUEST",
		priority = 10,
		groupRanks = { 0 },
		roleColor = { primary = "#6B7280", secondary = "#9CA3AF" },
		teamColor = "Medium stone grey",
		giftable = false,
	},
}

-- =============================================================================
-- ALIAS (update kalau rename role/membership — untuk command & data lama)
-- =============================================================================
ClubKitConfig.LegacyAliases = {
	CoOwner = "Staff",
	AfterTeam = "Staff",
	Developer = "Staff",
	Admin = "Staff",
	Investor = "Staff",
	Influencer = "Influencer",
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
	["Lead Dance"] = "LeadDance",
	["lead dance"] = "LeadDance",
	["Top Donor"] = "TopSpender",
	["top donor"] = "TopSpender",
	["Top Spender"] = "TopSpender",
	["top spender"] = "TopSpender",
	["Top Supporter"] = "RoyaleSpender",
	["top supporter"] = "RoyaleSpender",
	["Royale Spender"] = "RoyaleSpender",
	["royale spender"] = "RoyaleSpender",
	Donor = "Donatur",
	donor = "Donatur",
	donatur = "Donatur",
}

ClubKitConfig.CommandAliases = {
	owner = "Owner",
	staff = "Staff",
	mod = "Moderator",
	moderator = "Moderator",
	["lead dance"] = "LeadDance",
	leaddance = "LeadDance",
	lead = "LeadDance",
	dj = "DJ",
	streamer = "Streamer",
	influencer = "Influencer",
	supreme = "Supreme",
	exclusive = "Supreme",
	elite = "Supreme",
	["top donor"] = "TopSpender",
	topdonor = "TopSpender",
	["top supporter"] = "RoyaleSpender",
	topsupporter = "RoyaleSpender",
	["royale spender"] = "RoyaleSpender",
	royalespender = "RoyaleSpender",
	["top spender"] = "TopSpender",
	topspender = "TopSpender",
	vvip = "VVIP",
	vip = "VIP",
	guest = "Guest",
	coowner = "Staff",
	["co-owner"] = "Staff",
	afterteam = "Staff",
	["after-team"] = "Staff",
	after = "Staff",
	developer = "Staff",
	dev = "Staff",
	admin = "Staff",
	investor = "Staff",
	creator = "Streamer",
	spender = "RoyaleSpender",
	donor = "Donatur",
	donatur = "Donatur",
	suprememember = "Supreme",
	elitemember = "Supreme",
	tier3 = "Supreme",
	vvipmember = "VVIP",
	tier2 = "VVIP",
	vipmember = "VIP",
	tier1 = "VIP",
	member = "Guest",
	none = "none",
	remove = "none",
}

-- =============================================================================
-- JOIN COMMUNITY (optional — real MemberCount proxy fallback)
-- =============================================================================
-- Preference: Secrets.GameDataApiSecret + GameDataApi → worker
--   GET {BASE_URL}/game/{GameKey}/community/{groupId}?secret=...
-- Without secret (typical Studio), kit falls back to MEMBER_INFO_URL / MEMBER_USERS_URL
-- (engine default roproxy). Leave MemberInfoUrl nil for kit default; "" = off;
-- or set your own worker URL with {groupId} / %d (legacy override only).
ClubKitConfig.JoinCommunity = {
	MemberInfoUrl = nil :: string?, -- nil = kit default; "" = off; else e.g. "https://your.proxy/groups/%d"
}

-- =============================================================================
-- FITUR (matikan modul yang tidak dipakai)
-- =============================================================================
ClubKitConfig.Features = {
	MusicPlayer = true,
	SyncDance = true,
	Hotbar = true,
	LoadingScreen = true,
	LevelSystem = true,
	Settings = true,
	Shop = true,
	Couples = true,
	Stickers = true,
	Leaderboards = true,
	DonationCash = true,
	DonationSaweria = true, -- legacy alias untuk DonationCash
	DonationRobux = true,
	Gravity = true,
	-- After loading: show custom Join Community modal (always if GroupId > 0; already-joined CTA = "Already joined").
	PromptJoinCommunityOnLoad = true,
	-- Toast when Owner / Leadership / Content / top-10 Robux or cash spender joins (once per session).
	JoinGreetings = true,
}

return ClubKitConfig
