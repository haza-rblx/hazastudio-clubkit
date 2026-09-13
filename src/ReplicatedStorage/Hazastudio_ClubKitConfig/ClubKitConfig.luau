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
-- privileges per category: canGift, canAnnounce, canTeleport, adminPanel, musicManage, musicControl
-- musicManage = edit the music library; musicControl = live control (DJ mode, effects, speed,
-- soundboard, skip, private playlists). Leave musicControl out and it follows musicManage.
-- roleColor = { primary, secondary } drives chat/tag colors. Optional `stops = { hex, ... }`
-- (2..5 colors) paints a multi-color gradient on the overhead special-rank text; when set,
-- primary/secondary may be omitted (default to first/last stop).
-- A role may carry its own `privileges = { ... }` to override its category's (one category,
-- different powers per member). `specialRank = { text, gradient, chip = true }` also shows
-- the text as a chip in the overhead donation-chip row and hides that role's #N rank chips.
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
			musicControl = true,
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
			musicControl = false,
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
			musicControl = true,
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
		Label = "Top Cash Spender",
		ChatTag = "TOP CASH SPENDER",
		ToolFolder = "TOP CASH SPENDER",
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
		Label = "Top Robux Spender",
		ChatTag = "TOP ROBUX SPENDER",
		ToolFolder = "TOP ROBUX SPENDER",
		MaxRank = 10,
		Priority = 90,
		TeamColor = "Bright bluish green",
		roleColor = { primary = "#14B8A6", secondary = "#5EEAD4" },
		SpecialRank = { text = "TOP ROBUX SPENDER", gradient = true },
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
-- OVERHEAD NAMETAG TEMPLATE
-- =============================================================================
--   GuiType
--     Which OverheadGUIMainTemplate* this place uses. The template itself lives
--     in ReplicatedStorage (place data), so only set a version you have actually
--     installed — an unknown or missing one falls back to V1.
--       "V4" (default) — the standard nametag.
--       "V5"           — V4 plus the image-title row `02-AddOnCustomImageBadge`,
--                        an extra banner under the text title. Needed for the
--                        admin panel's image title to show up at all.
--
--   DefaultLayers / DefaultBadges
--     What each nametag layer and badge does in your venue. Three values per key:
--
--       true    Shown. A player can still hide it from Settings → Overhead.
--       false   Hidden to begin with, but a player may switch it back on. A
--               DEFAULT, not a lock. For example, to drop the status chip unless
--               someone opts in:  DefaultLayers = { SpecialStatus = false }
--       "off"   Not part of this venue. Off for EVERYONE, always — and the
--               layer's row disappears from the Settings menu, so nobody is left
--               with a switch that does nothing. For example, to run nametags
--               with no badges at all:  DefaultLayers = { BadgeGroup = "off" }
--
--     Keys you leave out keep the kit's own value, so you only write what you
--     want to change. An unknown key is ignored rather than creating a layer, and
--     a value that is none of the three above is ignored with a warning in the
--     output window (the kit keeps its own value rather than guessing).
--
--     NOTE: true / false decide a player's *first* stored record only. Players who
--     already have one keep whatever is stored for them — changing true or false
--     here does not reach back and rewrite existing players. "off" is different:
--     it is enforced every time a nametag is built, so it applies to everyone
--     immediately. Nothing stored is erased, so deleting the "off" later brings
--     every player back exactly as they had it.
--
--     "off" also beats the kit's own overrides: an admin granting someone a custom
--     title will not resurface a SpecialTitle layer you switched off, and a couple
--     forming will not resurface CoupleName.
--
--   ShowSupporterChip
--     The generic "SUPPORTER" chip a donor gets while they have no ranked chip
--     yet. false = only donors who actually hold a rank get a chip.
--     Note this is NOT the same as DefaultLayers.TopSpender: that layer also
--     carries the ranked "#N RUPIAH" chip, so switching the layer off would take
--     the ranked chip away too.
--
ClubKitConfig.Overhead = {
	GuiType = "V4",
	ShowSupporterChip = true,
	DefaultLayers = {
		SpecialTitle = true,
		BadgeGroup = true,
		Level = true,
		SpecialRank = true,
		SpecialStatus = true,
		TopSpender = true,
		TopDonate = true,
		Rank = true,
		DisplayName = true,
		CoupleName = false,
	},
	DefaultBadges = {
		OwnerCoOwner = true,
		Developer = true,
		Admin = true,
		Member = true,
		VIP = true,
		VVIP = true,
		Elite = true,
		Streak = true,
		LikeCounter = true,
		Community = true,
	},
}

-- =============================================================================
-- GRAPHICS
-- =============================================================================
--   DefaultPreset
--     The Settings → Graphics preset a player starts on: "Low" | "Balanced" |
--     "High". Also what Settings → Reset goes back to.
--       "Low" (default) — no shadows at all, reduced effects; the map keeps its
--                         textures. Smoothest on phones and weak PCs.
--       "Balanced"      — sun shadows only; club lights cast no shadows.
--       "High"          — the map exactly as built.
--
--     NOTE: only players who have never saved their settings get this. Anyone who
--     has already picked a preset (or changed any other setting, which saves the
--     whole panel) keeps what is stored for them.
--
ClubKitConfig.Graphics = {
	DefaultPreset = "Low",
}

-- =============================================================================
-- PROFILE LIKES
-- =============================================================================
--   DailyLikeReset
--     true (default) — a player may like someone once per day, and the counter
--                      resets at midnight WIB (the same day boundary the daily
--                      streak uses). Every daily like adds +1 to that player's
--                      lifetime total, so the Likes board becomes a measure of
--                      how active a venue is, not how many different people
--                      passed through. Likes cannot be taken back: once given
--                      today, the button reads "Liked today" until midnight.
--     false          — the older rule: one standing like per person, ever, with
--                      an Unlike button that takes the count back down.
--
--     Switching this off later changes nothing that is stored — every like stays
--     and the old toggle starts working on it again. Switching it on does not
--     reset anybody's total either; existing likes simply stop being the last
--     word, and everyone may like again the next day.
--
ClubKitConfig.AvatarContext = {
	DailyLikeReset = true,
}

-- =============================================================================
-- CUSTOM TITLE (self-service overhead title)
-- =============================================================================
--   Only used when Features.SelfCustomTitle = true. With the flag off the
--   profile "Title" row keeps the old text-only modal and these are ignored.
--
--   MinLevel
--     Level a player must reach to create their own title. Players who already
--     hold a title given by an admin can always edit it, whatever their level.
--     Requires Features.LevelSystem — with levels off nobody reaches MinLevel,
--     so only admin-granted title holders can open the panel.
--
--   MaxChangesPerWindow / WindowDays
--     Rolling quota: at most MaxChangesPerWindow updates in any WindowDays
--     period. One "Update Title" press that changes anything (text, size,
--     preset or font) costs one slot. Removing a title is always free.
--
--   QuotaEnabled
--     false = no limit at all: players change their title as often as they
--     like and the panel says "Unlimited" instead of counting down. MinLevel
--     still applies. Changes made while this is false are not counted, so
--     turning the quota back on does not find everyone already spent.
--
--   FreeFirstTitle
--     true = every player gets ONE free title, whatever their level. It is spent
--     by creating a title, not by keeping one: removing it afterwards does not
--     give the slot back, and a title an admin gives them never consumes it.
--     Once spent they are locked again until they reach MinLevel or qualify for
--     the Free Title event. Their title stays on their head either way.
--
ClubKitConfig.CustomTitle = {
	MinLevel = 50,
	MaxChangesPerWindow = 5,
	WindowDays = 7,
	QuotaEnabled = true,
	FreeFirstTitle = false,
}

-- =============================================================================
-- FREE TITLE EVENT (the ADDON-FreeTitleEventTrigger card)
-- =============================================================================
--   An event card that floats on screen and opens the custom title panel. It is
--   a second, easier door to the same panel: a player who meets the event
--   requirement may create a title even if they have not reached
--   CustomTitle.MinLevel. Nobody ever loses access they already had, and the
--   change quota still applies.
--
--   Needs Features.SelfCustomTitle = true and the ADDON-FreeTitleEventTrigger
--   frame installed inside your IconGroup. Without either, there is no card.
--
--   There are three possible requirements. Set a number above 0 to switch one on,
--   leave it 0 to ignore it:
--
--     RequiredLevel       reach this level (usually lower than
--                         CustomTitle.MinLevel — that is the point of the event)
--     MinDonationRobux    donated at least this many Robux, lifetime total
--     MinDonationCash     donated at least this much cash, lifetime total, in
--                         your Donation.Currency
--
--   Mode says how the ones you switched on are combined:
--
--     "Disabled"  no card, no rule change. This is the off switch.
--     "Any"       meeting ONE of them is enough
--     "All"       every one of them has to be met
--
--   Examples:
--     level only        Mode = "Any",  RequiredLevel = 25
--     donation only     Mode = "Any",  MinDonationRobux = 100
--     either one        Mode = "Any",  RequiredLevel = 25, MinDonationRobux = 100
--     both required     Mode = "All",  RequiredLevel = 25, MinDonationRobux = 100
--
--   A player who does not qualify still sees the card, showing the first thing
--   they are missing. Anything Mode does not recognise counts as "Disabled", and
--   so does a Mode with every threshold left at 0.
--
ClubKitConfig.FreeTitleEvent = {
	Mode = "Disabled",
	RequiredLevel = 0,
	MinDonationRobux = 0,
	MinDonationCash = 0,
}

-- =============================================================================
-- FEATURES (disable modules you do not use)
-- =============================================================================
ClubKitConfig.Features = {
	MusicPlayer = true,
	-- Bulk seed from Hazastudio_ClubKitConfig/MusicCatalog.luau into DataStore on boot.
	-- false = skip merge (tracks already seeded stay in library).
	MusicCatalogSeed = true,
	-- Read-only music library: no DataStore at all (fast boot, no DataStore errors).
	-- Library = MusicCatalog + in-game requests (kept in memory only, lost on restart).
	-- Manage tab hidden. In-game edits are NOT saved. false (default) = editable mode.
	MusicReadOnlyLibrary = false,
	-- Music library from the web: edit playlists and tracks at customer.hazastudio.id;
	-- the game fetches them on boot and every minute, and keeps a DataStore copy so music
	-- still plays if the web is unreachable. Manage tab hidden. Needs Donation.ApiUrl +
	-- Secrets.DonationApiSecret. Wins over MusicReadOnlyLibrary. false (default) = in-game library.
	MusicWebLibrary = false,
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
	-- Avatar Context Menu v2 (redesign: static profile picture + camera zoom/blur backdrop).
	-- false (default) = legacy v1 (3D rotating avatar ViewportFrame). true = v2.
	AvatarContextMenuV2 = false,
	-- Self-service custom title: profile "Title" row opens the 1000-01-CT-ADDON panel
	-- (text + size + color preset + typeface), gated by CustomTitle.MinLevel and a
	-- rolling change quota. false (default) = old text-only modal, admin-granted titles
	-- only. Needs the 1000-01-CT-ADDON ScreenGui installed in StarterGui; without it the
	-- old modal is used even when this is true.
	SelfCustomTitle = false,
	-- Custom-title panel v3 (04-AdminPanelv3) owns the admin topbar icon instead of
	-- the classic 04-AdminPanelv2. Needs that ScreenGui installed in StarterGui.
	AdminPanelV3 = false,
	Hotbar = true,
	LoadingScreen = true,
	LevelSystem = true,
	Settings = true,
	Shop = true,
	Couples = true,
	-- Show the couple chat tag (💕 partner) in the General/chat prefix. Default true.
	-- false hides the tag in chat only; the couple system + overhead couple name stay on.
	ShowCoupleChatTag = true,
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
	-- Hierapolis Theatre place pack: true = merge Hazastudio_ClubKitConfig.HierapolisCustom
	-- (role catalog, aliases, LoadingScreen off) over this config at boot. Default false.
	HierapolisCustom = false,
}

return ClubKitConfig
