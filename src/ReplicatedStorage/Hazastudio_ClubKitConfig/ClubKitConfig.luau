--!strict
--[[
  CLUB KIT CONFIG — the single file buyers edit per place.
  Path: ReplicatedStorage.Hazastudio_ClubKitConfig.ClubKitConfig

  QUICK START (fill these in before publishing):
  ┌─────────────────────────────────────────────────────────────────┐
  │ 1. Group.GroupId      → your Roblox group ID (numeric)          │
  │ 2. Group.OwnerUserId  → owner userId (rank 255 / owner cmds)    │
  │ 3. Donation.ApiUrl    → Bagi-Bagi worker URL (empty = no live)  │
  │ 4. Shop.Products      → BuyGamePassId (buy) + GiftId (gift Dev Product) │
  │ 5. PaidBroadcast      → paid broadcast ProductId (Robux)        │
  │ 6. Membership           → VIP/VVIP/Supreme tier names (section below)│
  │ 7. RoleCategories       → group roles, ranks, colors, privileges│
  │ 8. Secrets.luau       → API secret (Hazastudio_ClubKitSecrets folder) │
  └─────────────────────────────────────────────────────────────────┘

  Live mode: default (ClubKitShowcase not in engine tree).
  Demo mode: manually inject ModuleScript Shared/Config/ClubKitShowcase (from tools/dev/).
]]

local ClubKitConfig = {}

-- =============================================================================
-- BRANDING
-- =============================================================================
ClubKitConfig.Branding = {
	GameName = "Club", -- shown on donation VFX / general labels
	WelcomeMessage = "Welcome to the club, %s", -- tap to continue (%s = player name)
	Greeting = "Welcome to the club, %s", -- initial loading screen
	-- Change once here → loading, poster, leaderboard, Join Community modal.
	-- Replace the kit default ID with your community logo.
	LogoImage = "rbxassetid://79426970537296",
	-- Top Menu → Community row (15-TopMenuGUI). Empty = keep placeholder, link box hidden.
	-- Accepts "discord.gg/invite", "https://discord.gg/invite", or invite code only.
	DiscordInvite = "", -- example: "discord.gg/your-invite"
}

-- =============================================================================
-- GROUP & ADMIN
-- =============================================================================
ClubKitConfig.Group = {
	GroupId = 0, -- example: 12345678  ← required before go-live
	OwnerUserId = 0, -- example: 987654321  ← place owner / /showcase; required before go-live
	OwnerGroupRank = 255, -- Roblox rank treated as owner in the group
}

ClubKitConfig.AdminUserIds = {
	-- backup admins without group rank; example: [111111] = true,
} :: { [number]: boolean }

-- =============================================================================
-- EXTERNAL ADMIN BRIDGE (optional — Adonis / Kohl's)
-- =============================================================================
ClubKitConfig.ExternalAdmin = {
	-- Which external admin system is bridged to Club Kit. Runtime gate only:
	-- it never installs/removes the admin itself (setup: extras/place-packs/ExternalAdminBridge).
	Provider = "None", -- "Adonis" | "Kohls" | "None"
	SyncStaffRoles = true, -- /setrole of staff roles also ranks up in the external admin
	SyncContentRoles = false, -- opt-in: also sync content roles like DJ (add them to RankMap first)
	-- Club Kit role → external rank. Membership (VIP/VVIP/Supreme) and Spender
	-- roles are never synced, even if added here (Kohl's "vip" collision).
	RankMap = {
		Owner = { adonis = 900, kohls = "creator" },
		CoOwner = { adonis = 300, kohls = "superadmin" },
		Staff = { adonis = 200, kohls = "admin" },
		Moderator = { adonis = 100, kohls = "mod" },
		-- DJ = { adonis = 50, kohls = "content" }, -- opt-in low-power example (needs SyncContentRoles = true)
	},
}

-- Temporary leaderboard warm-up (optional): [userId] = rank
ClubKitConfig.TopSpenders = {} :: { [number]: number }

ClubKitConfig.GameDataApi = {
	GameKey = "the-basic", -- must match D1/wrangler SECRET_<GAME_KEY> (community open to all authenticated keys)
}

-- =============================================================================
-- DONATION (Bagi-Bagi / Saweria + aura thresholds)
-- =============================================================================
ClubKitConfig.Donation = {
	Provider = "bagibagi", -- "bagibagi" | "saweria" | "sociabuzz" — donor name & label auto-set
	ProviderLink = "", -- example: "https://bagibagi.co/your-page" or "https://sociabuzz.com/username"
	ApiUrl = "https://hazastudio-donation-api.hazastudio.workers.dev/game/the-basic",
	-- Cash display currency: "IDR" (Rp), "PHP" (₱), or "CASH" (neutral "Cash" labels).
	-- Saweria supports IDR/PHP (register with the matching account currency); Bagi-Bagi is
	-- IDR-only; SociaBuzz settles per creator country. Display-only (symbol/grouping/chip
	-- word) — amounts are NOT converted, so MinAmount / AuraTiers idrMin/idrMax /
	-- WorldEffectTiers below must be retuned in the new unit yourself when switching currencies.
	Currency = "IDR",
	Cash = { Enabled = true },
	Robux = { Enabled = true },
	-- Optional: manual Robux donation product list. Empty = auto from dashboard.
	RobuxProducts = {} :: { { ProductId: number, Name: string?, Price: number? } },

	-- Min amount (in Currency above) to appear in notifications + leaderboard (not aura tier).
	MinAmount = 1000,

	-- World stage position for Rocket / Hammer / BlackHole VFX (impact / anchor).
	-- Rocket descends to this Vector3. Optional workspace.NukeModel = launch pad only.
	NukeWorldPosition = Vector3.new(-262.2, 1.285, 64.9),

	-- Aura per player (folder ServerStorage.DonationEffects/LevelN).
	-- min = Robux | idrMin/idrMax = cash range in Currency above (field name kept for
	-- compatibility) | effect/sound = asset folder name.
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

	-- World VFX for cash donations (models in ReplicatedStorage.WorldEffects). Robux does not use this.
	-- Thresholds are in Currency above — retune these when switching currency.
	WorldEffectTiers = {
		{ min = 500000, effect = "BlackHole" }, -- 500k+
		{ min = 250000, effect = "Smite4" }, -- 250k+ (hammer)
		{ min = 100000, effect = "Nuke" }, -- 100k+ (rocket)
	},
}

-- =============================================================================
-- CARRY (replace carrier/carried with your animation asset IDs)
-- =============================================================================
ClubKitConfig.Carry = {
	MaxDistance = 30, -- studs, max carry request distance
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
	CinematicAnimationId = "rbxassetid://78416657618448", -- dance animation during cinematic loading
}

-- =============================================================================
-- SHOP MEMBERSHIP
-- BuyGamePassId = self-buy (Game Pass, one-time). GiftId = gift (Developer Product).
-- BuyId = legacy self-buy Developer Product (optional; ProcessReceipt still honors).
-- =============================================================================
ClubKitConfig.Shop = {
	Products = {
		Tier1 = { BuyGamePassId = 0, GiftId = 3608406587, BuyId = 3608406407, Price = 1 }, -- VIP
		Tier2 = { BuyGamePassId = 0, GiftId = 3608406626, BuyId = 3608406452, Price = 1 }, -- VVIP
		Tier3 = { BuyGamePassId = 0, GiftId = 3608406664, BuyId = 3608406486, Price = 1 }, -- Supreme
	},
}

-- =============================================================================
-- PAID BROADCAST (Developer Product — broadcast message to entire server)
-- =============================================================================
ClubKitConfig.PaidBroadcast = {
	ProductId = 3503700307, -- replace with Product ID from Creator Dashboard
}

-- =============================================================================
-- ANNOUNCEMENT (free /announce + free broadcast panel gate)
-- MinMembership = lowest paid tier that can announce free without Robux.
-- "Tier1"/"VIP", "Tier2"/"VVIP", "Tier3"/"Supreme". Staff+ / top spenders still free.
-- =============================================================================
ClubKitConfig.Announcement = {
	MinMembership = "Tier2", -- default VVIP+; set "Tier3" / "Supreme" for Supreme-only free announce
}

-- =============================================================================
-- MEMBERSHIP (shop tier names)
-- Label = UI/chat display. Tier1/2/3 = internal keys (do not change).
-- If you rename Label, update CommandAliases below (vip/supreme/etc.).
-- =============================================================================
ClubKitConfig.Membership = {
	Tier1 = { Label = "VIP", Enabled = true, Priority = 40 },
	Tier2 = { Label = "VVIP", Enabled = true, Priority = 50 },
	Tier3 = { Label = "Supreme", Enabled = true, Priority = 60 },
}

-- =============================================================================
-- ROLE CATEGORIES (group rank → role; match your Roblox group)
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
				key = "CoOwner",
				label = "Co-Owner",
				chatTag = "CO-OWNER",
				toolFolder = "STAFF",
				teamColor = "New Yeller",
				enabled = true,
				specialRank = { text = "CO-OWNER", gradient = true },
				badgeFrames = { "01-OwnerCoOwnerBadge" }, -- same badge frame as Owner
				roleColor = { primary = "#FBBF24", secondary = "#FDE68A" },
			},
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
-- SPENDER ROLES (donor leaderboard — label/chatTag freely editable)
-- =============================================================================
ClubKitConfig.SpenderRoles = {
	CashSpender = {
		Enabled = true,
		Key = "TopSpender",
		Label = "Top Rupiah Spender",
		ChatTag = "TOP RUPIAH SPENDER",
		ToolFolder = "TOP RUPIAH SPENDER",
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
		Label = "Top Robux Donator",
		ChatTag = "TOP ROBUX DONATOR",
		ToolFolder = "TOP ROBUX DONATOR",
		MaxRank = 10,
		Priority = 90,
		TeamColor = "Bright bluish green",
		roleColor = { primary = "#14B8A6", secondary = "#5EEAD4" },
		SpecialRank = { text = "TOP ROBUX DONATOR", gradient = true },
		Privileges = {
			canAnnounce = true,
			canTeleport = true,
		},
	},
}

-- =============================================================================
-- SYSTEM ROLES (Owner/Guest — groupRanks = Roblox group rank)
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
-- ALIAS (update when renaming roles/membership — for commands & legacy data)
-- =============================================================================
ClubKitConfig.LegacyAliases = {
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
	["Co-Owner"] = "CoOwner",
	["co-owner"] = "CoOwner",
	coowner = "CoOwner",
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
	["top rupiah spender"] = "TopSpender",
	toprupiahspender = "TopSpender",
	["top supporter"] = "RoyaleSpender",
	topsupporter = "RoyaleSpender",
	["top robux donator"] = "RoyaleSpender",
	toprobuxdonator = "RoyaleSpender",
	["royale spender"] = "RoyaleSpender",
	royalespender = "RoyaleSpender",
	["top spender"] = "TopSpender",
	topspender = "TopSpender",
	vvip = "VVIP",
	vip = "VIP",
	guest = "Guest",
	coowner = "CoOwner",
	["co-owner"] = "CoOwner",
	afterteam = "Staff",
	["after-team"] = "Staff",
	after = "Staff",
	developer = "Staff",
	dev = "Staff",
	admin = "Staff",
	investor = "Staff",
	creator = "Streamer",
	spender = "RoyaleSpender",
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
-- SYNC DANCE (crossfade transitions, seconds)
-- =============================================================================
-- All values = blend duration (seconds). Higher = softer; lower = snappier.
--
-- When each is used:
--   FadeIn / FadeOut
--     Start dance from idle, or stop dance back to idle.
--     FadeIn  = new dance weight rises.
--     FadeOut = old dance weight falls.
--
--   SwitchFadeIn / SwitchFadeOut
--     Switch dance A → B while already dancing (not from idle).
--     SwitchFadeOut = A fades out; SwitchFadeIn = B fades in.
--     Ideally use matching values for a salon-style blend without a hard cut.
--     Usually slightly longer than FadeIn/Out because two dances cross over.
--
--   SyncJoinFade
--     Player joins sync with leader (or leadership transfer). One value used
--     for Stop+Play matching when following the leader's dance.
--
--   SwitchInputCooldown
--     Minimum delay between emote clicks (seconds). Set >= SwitchFadeIn/Out so
--     spam clicks do not stack tracks (avoids broken-arm artifacts).
--
ClubKitConfig.Sync = {
	FadeIn = 0.45, -- idle → dance (fade in)
	FadeOut = 0.45, -- dance → idle (fade out)
	SwitchFadeIn = 0.45, -- dance A→B: B fades in
	SwitchFadeOut = 0.45, -- dance A→B: A fades out (match SwitchFadeIn)
	SyncJoinFade = 0.4, -- join / sync to leader
	SwitchInputCooldown = 0.45, -- emote click cooldown; >= SwitchFade*
}

-- =============================================================================
-- FEATURES (disable modules you do not use)
-- =============================================================================
ClubKitConfig.Features = {
	MusicPlayer = true,
	-- Bulk seed from Hazastudio_ClubKitConfig/MusicCatalog.luau into DataStore on boot.
	-- false = skip merge (tracks already seeded stay in library).
	MusicCatalogSeed = true,
	SyncDance = true,
	-- Rapid re-click of the PLAYING emote hard-restarts it (fade 0 "wutwut" stutter).
	-- false = classic behavior (same-emote click toggles the dance off). Default false.
	WutwutDance = false,
	-- true = place uses extras/place-packs/SyncBhms (ACM Sync Dance → BHMS).
	-- Disables Club Kit dance panel + SyncService. false = SyncBhmsGate no-ops pack (hide topbar Dance).
	-- THE BASIC TEST 1.3: set true only when playtesting SyncBhms pack.
	LegacySyncBhms = false,
	-- WIP Admin Hub (04-AdminHub). false = classic Admin Panel owns topbar icon.
	AdminHub = false,
	Hotbar = true,
	LoadingScreen = true,
	LevelSystem = true,
	Settings = true,
	Shop = true,
	Couples = true,
	Stickers = true,
	Leaderboards = true,
	DonationCash = true,
	DonationSaweria = true, -- legacy alias for DonationCash
	DonationRobux = true,
	Gravity = true,
	-- After loading: show custom Join Community modal (always if GroupId > 0; already-joined CTA = "Already joined").
	PromptJoinCommunityOnLoad = true,
	-- If true and Group.GroupId > 0: players already in the community group get VIP (Tier1)
	-- on join; after JoinCommunity PromptJoinAsync, server re-checks and grants if now a member.
	-- Default false — existing places unchanged until buyer enables.
	VipOnCommunityJoin = false,
	-- Toast when Owner / Leadership / Content / top-10 Robux or cash spender joins (once per session).
	JoinGreetings = true,
	-- Global Nuke / Smite / BlackHole on cash donations. false = no world explosion VFX; Settings “World Effects” row hidden.
	DonationWorldEffects = true,
	-- UIGradient animation on #N ROBUX / #N RUPIAH chips in overhead (RobuxRankWrapper / RupiahRankWrapper).
	-- Default false — existing places without UIGradient on wrapper stay safe; set true after adding gradient in Studio.
	DonationRankGradientAnim = false,
}

return ClubKitConfig
