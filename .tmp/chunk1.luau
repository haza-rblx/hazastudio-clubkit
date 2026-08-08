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
}

-- =============================================================================
-- GROUP & ADMIN
-- =============================================================================
ClubKitConfig.Group = {
	GroupId = 0, -- example: 12345678  ← required before go-live
	OwnerUserId = 8842050215, -- example: 987654321  ← place owner / /showcase
	OwnerGroupRank = 255, -- Roblox rank treated as owner in the group
}

ClubKitConfig.AdminUserIds = {
	[8842050215] = true, -- backup admins without group rank; example: [111111] = true,
} :: { [number]: boolean }

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
	Cash = { Enabled = true },
	Robux = { Enabled = true },
	-- Optional: manual Robux donation product list. Empty = auto from dashboard.
	RobuxProducts = {} :: { { ProductId: number, Name: string?, Price: number? } },

	-- Min IDR to appear in notifications + leaderboard (not aura tier).
	MinAmount = 1000,

	-- World stage position for Rocket / Hammer / BlackHole VFX (impact / anchor).
	-- Rocket descends to this Vector3. Optional workspace.NukeModel = launch pad only.
	NukeWorldPosition = Vector3.new(-262.2, 1.285, 64.9),

	-- Aura per player (folder ServerStorage.DonationEffects/LevelN).
	-- min = Robux | idrMin/idrMax = Bagi-Bagi range | effect/sound = asset folder name.
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

	-- World VFX for Bagi-Bagi (models in ReplicatedStorage.WorldEffects). Robux does not use this.
	WorldEffectTiers = {
		{ min = 500000, effect = "BlackHole" }, -- 500k+ IDR
		{ min = 250000, effect = "Smite4" }, -- 250k+ IDR (hammer)
		{ min = 100000, effect = "Nuke" }, -- 100k+ IDR (rocket)
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
-- MEMBERSHIP (shop tier names)
-- Label = UI/chat display. Tier1/2/3 = internal keys (do not change).
-- If you rename Label, update CommandAliases below (vip/supreme/etc.).
-- =============================================================================
ClubKitConfig.Membership = {
	Tier1 = { Label = "VIP", Enabled = true, Priority = 40 },
	Tier2 = { Label = "VVIP", Enabled = true, Priority = 50 },
