--!strict
--[[
  Fill-forward schema for ClubKitConfig.

  Keep in sync with Hazastudio_ClubKitConfig/ClubKitConfig.luau template defaults
  for fillable keys. Buyer values always win; missing keys come from here.

  Runtime: ConfigBootstrap.fillForward(defaults, buyer)
  Plugin: ConfigPatchCore uses this module after Update Engine to patch Source.
  Plugin Config Features panel: FEATURE_MANIFEST + getFeatureKeys/getFeatureGroups.
]]

local ClubKitConfigSchema = {}

-- List / ordered fields: if buyer has a table at this key, keep buyer wholesale
-- (do not merge element-by-element).
ClubKitConfigSchema.ARRAY_REPLACE_KEYS = {
	AuraTiers = true,
	WorldEffectTiers = true,
	RobuxProducts = true,
	RobuxAuraTiers = true,
	SaweriaWorldTiers = true,
	RoleCategories = true,
	StyleOrder = true,
	groupRanks = true,
	badgeFrames = true,
	Profiles = true,
	Communities = true,
	TopSpenders = true,
}

-- Mirror of buyer template fillable defaults (safe additive keys + section shapes).
ClubKitConfigSchema.defaults = {
	Branding = {
		GameName = "Club",
		WelcomeMessage = "Welcome to the club, %s",
		Greeting = "Welcome to the club, %s",
		LogoImage = "rbxassetid://79426970537296",
		DiscordInvite = "",
	},
	Group = {
		GroupId = 0,
		OwnerUserId = 0,
		OwnerGroupRank = 255,
	},
	AdminUserIds = {} :: { [number]: boolean },
	TopSpenders = {} :: { [number]: number },
	ExternalAdmin = {
		Provider = "None", -- "Adonis" | "Kohls" | "None"
		SyncStaffRoles = true,
		SyncContentRoles = false,
		RankMap = {
			Owner = { adonis = 900, kohls = "creator" },
			CoOwner = { adonis = 300, kohls = "superadmin" },
			Staff = { adonis = 200, kohls = "admin" },
			Moderator = { adonis = 100, kohls = "mod" },
		},
	},
	GameDataApi = {
		GameKey = "the-basic",
	},
	Donation = {
		Provider = "bagibagi", -- "bagibagi" | "saweria" | "sociabuzz"
		ProviderLink = "",
		ApiUrl = "",
		-- Enterprise-grade notification reliability (delivery ledger + client ack +
		-- server retry + DLQ audit). Requires donation-api Worker >= v3. Default off
		-- so existing buyers keep legacy fire-and-forget until they opt in.
		ReliabilityV2 = false,
		-- Cash display currency ("IDR" | "PHP" | "CASH"). Saweria supports IDR/PHP natively;
		-- Bagi-Bagi is IDR-only; SociaBuzz settles per creator country. "CASH" = neutral
		-- "Cash" labels (no currency name). Display-only — amounts are not converted;
		-- MinAmount/AuraTiers/WorldEffectTiers stay in this unit.
		Currency = "IDR",
		Cash = { Enabled = true },
		Robux = { Enabled = true },
		RobuxProducts = {} :: { { ProductId: number, Name: string?, Price: number? } },
		MinAmount = 1000,
		NukeWorldPosition = Vector3.new(-262.2, 1.285, 64.9),
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
		WorldEffectTiers = {
			{ min = 500000, effect = "BlackHole" },
			{ min = 250000, effect = "Smite4" },
			{ min = 100000, effect = "Nuke" },
		},
	},
	Carry = {
		MaxDistance = 30,
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
	},
	Loading = {
		CinematicAnimationId = "rbxassetid://78416657618448",
	},
	Shop = {
		Products = {
			Tier1 = { BuyGamePassId = 0, GiftId = 0, BuyId = 0, Price = 1 },
			Tier2 = { BuyGamePassId = 0, GiftId = 0, BuyId = 0, Price = 1 },
			Tier3 = { BuyGamePassId = 0, GiftId = 0, BuyId = 0, Price = 1 },
		},
	},
	PaidBroadcast = {
		ProductId = 0,
	},
	-- Free /announce + free broadcast UI. Tier1=VIP, Tier2=VVIP, Tier3=Supreme (or label).
	Announcement = {
		MinMembership = "Tier2",
		-- Per-role-group cooldown for /announce. Partial override OK — unspecified
		-- groups fall back to engine defaults. Omit the whole table to keep the
		-- legacy single budget (Config.Announcement.RATE_MAX/RATE_WINDOW).
		RateLimits = {
			Leadership = { Max = 10, Window = 60 }, -- Staff and above
			Spender = { Max = 5, Window = 60 }, -- RoyaleSpender / TopSpender / Spender
			Member = { Max = 3, Window = 60 }, -- membership >= MinMembership
			Player = { Max = 1, Window = 60 }, -- everyone else who can announce
		},
	},
	Membership = {
		Tier1 = { Label = "VIP", Enabled = true, Priority = 40 },
		Tier2 = { Label = "VVIP", Enabled = true, Priority = 50 },
		Tier3 = { Label = "Supreme", Enabled = true, Priority = 60 },
	},
	RoleCategories = {
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
					badgeFrames = { "01-OwnerCoOwnerBadge" },
					-- roleColor.stops (optional, 2..5 hex): multi-color gradient on the overhead
					-- special-rank text; primary/secondary then default to first/last stop.
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
	} :: { any },
	SpenderRoles = {
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
	},
	SystemRoles = {
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
	},
	LegacyAliases = {
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
		["Top Cash Spender"] = "TopSpender",
		["top cash spender"] = "TopSpender",
		["Top Spender"] = "TopSpender",
		["top spender"] = "TopSpender",
		["Top Supporter"] = "RoyaleSpender",
		["top supporter"] = "RoyaleSpender",
		["Top Robux Spender"] = "RoyaleSpender",
		["top robux spender"] = "RoyaleSpender",
		["Royale Spender"] = "RoyaleSpender",
		["royale spender"] = "RoyaleSpender",
		["Co-Owner"] = "CoOwner",
		["co-owner"] = "CoOwner",
		coowner = "CoOwner",
	},
	CommandAliases = {
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
		["top cash spender"] = "TopSpender",
		topcashspender = "TopSpender",
		["top supporter"] = "RoyaleSpender",
		topsupporter = "RoyaleSpender",
		["top robux spender"] = "RoyaleSpender",
		toprobuxspender = "RoyaleSpender",
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
	},
	JoinCommunity = {
		MemberInfoUrl = nil :: string?,
	},
	Sync = {
		FadeIn = 0.45,
		FadeOut = 0.45,
		SwitchFadeIn = 0.45,
		SwitchFadeOut = 0.45,
		SyncJoinFade = 0.4,
		SwitchInputCooldown = 0.45,
	},
	Features = {
		MusicPlayer = true,
		MusicCatalogSeed = true,
		-- Read-only music library: skip DataStore entirely; library comes from MusicCatalog
		-- + in-game requests (kept in memory only, lost on restart). Manage tab hidden.
		-- false (default) = editable mode (DataStore read/write, in-game edits persist).
		MusicReadOnlyLibrary = false,
		SyncDance = true,
		-- Place-only BHMS dance/sync pack. When true: skip Club Kit dance panel + SyncService;
		-- ACM Sync Dance routes to ReplicatedStorage.SyncBhmsAcmBridge.
		-- When false: SyncBhmsGate makes pack scripts no-op (topbar Dance / DanceGui off). Default false.
		LegacySyncBhms = false,
		-- Wutwut: rapid same-emote re-click hard-restarts the playing dance (fade 0 stutter).
		-- Default false — classic same-emote click toggles the dance off.
		WutwutDance = false,
		-- WIP Admin Hub UI. Default false — classic 04-AdminPanelv2 until hub is ready.
		AdminHub = false,
		-- Avatar Context Menu v2 (redesign: static ProfilePicture + backdrop zoom/blur).
		-- false (default) = legacy v1 GUI (3D ViewportFrame avatar). true = v2.
		AvatarContextMenuV2 = false,
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
		DonationSaweria = true,
		DonationRobux = true,
		Gravity = true,
		PromptJoinCommunityOnLoad = true,
		VipOnCommunityJoin = false,
		JoinGreetings = true,
		DonationWorldEffects = true,
		DonationRankGradientAnim = false,
	},
}

export type FeatureManifestItem = {
	key: string,
	label: string,
}

export type FeatureManifestGroup = {
	name: string,
	items: { FeatureManifestItem },
}

-- Plugin Config panel + FEATURE_KEYS derive from this (not a duplicate hardcoded list).
-- Keys must exist in `defaults.Features`. Omit legacy aliases hidden from UI (e.g. DonationSaweria).
ClubKitConfigSchema.FEATURE_MANIFEST = {
	{
		name = "Music & dance",
		items = {
			{ key = "MusicPlayer", label = "Music player" },
			{ key = "MusicCatalogSeed", label = "Default playlist" },
			{ key = "MusicReadOnlyLibrary", label = "Read-only music library (no DataStore)" },
			{ key = "SyncDance", label = "Sync dance" },
			{ key = "LegacySyncBhms", label = "Legacy SyncBhms place-pack" },
			{ key = "WutwutDance", label = "Wutwut dance restart" },
		},
	},
	{
		name = "Interface",
		items = {
			{ key = "Hotbar", label = "Hotbar" },
			{ key = "LoadingScreen", label = "Loading screen" },
			{ key = "Settings", label = "Settings menu" },
			{ key = "JoinGreetings", label = "Join greetings" },
			{ key = "PromptJoinCommunityOnLoad", label = "Join community prompt" },
			{ key = "AdminHub", label = "Admin Hub (04-AdminHub)" },
			{ key = "AvatarContextMenuV2", label = "Avatar context menu v2 (redesign)" },
		},
	},
	{
		name = "Social & progression",
		items = {
			{ key = "Couples", label = "Couple system" },
			{ key = "ShowCoupleChatTag", label = "Couple chat tag (General)" },
			{ key = "Stickers", label = "Stickers" },
			{ key = "LevelSystem", label = "Level & XP" },
		},
	},
	{
		name = "Monetization",
		items = {
			{ key = "Shop", label = "Shop" },
			{ key = "Leaderboards", label = "Donation boards" },
			{ key = "DonationCash", label = "Cash donations" },
			{ key = "DonationRobux", label = "Robux donations" },
			{ key = "DonationWorldEffects", label = "Donation world effects" },
		},
	},
	{
		name = "More",
		items = {
			{ key = "Gravity", label = "Gravity tool" },
			{ key = "VipOnCommunityJoin", label = "Free VIP for group members" },
			{ key = "DonationRankGradientAnim", label = "Donor rank animation" },
		},
	},
} :: { FeatureManifestGroup }

function ClubKitConfigSchema.getFeatureGroups(): { FeatureManifestGroup }
	return ClubKitConfigSchema.FEATURE_MANIFEST
end

function ClubKitConfigSchema.getFeatureKeys(): { string }
	local keys: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, group in ClubKitConfigSchema.FEATURE_MANIFEST do
		for _, item in group.items do
			if not seen[item.key] then
				seen[item.key] = true
				table.insert(keys, item.key)
			end
		end
	end
	return keys
end

local function deepClone(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = table.clone(value)
	for key, child in pairs(result) do
		if type(child) == "table" then
			result[key] = deepClone(child)
		end
	end
	return result
end

local function joinPath(prefix: string, key: any): string
	local keyText = tostring(key)
	if prefix == "" then
		return keyText
	end
	return prefix .. "." .. keyText
end

--[[
  fillForward(schema, buyer) — buyer wins on existing keys; missing filled from schema.
  Arrays listed in ARRAY_REPLACE_KEYS: if buyer has a table, use buyer wholesale.
  Optional filledPaths collects dotted paths that were taken from schema.
]]
function ClubKitConfigSchema.fillForward(schema: any, buyer: any, filledPaths: { string }?, pathPrefix: string?): any
	local filled = filledPaths or {}
	local prefix = pathPrefix or ""

	if type(schema) ~= "table" then
		if buyer ~= nil then
			return buyer
		end
		return schema
	end

	if type(buyer) ~= "table" then
		if buyer == nil then
			local cloned = deepClone(schema)
			if prefix ~= "" then
				table.insert(filled, prefix)
			end
			return cloned
		end
		return buyer
	end

	local result: { [any]: any } = {}
	local seen: { [any]: boolean } = {}

	for key, schemaValue in pairs(schema) do
		seen[key] = true
		local buyerValue = buyer[key]
		local subPath = joinPath(prefix, key)

		if ClubKitConfigSchema.ARRAY_REPLACE_KEYS[key] == true then
			if type(buyerValue) == "table" then
				result[key] = buyerValue
			elseif type(schemaValue) == "table" then
				result[key] = deepClone(schemaValue)
				table.insert(filled, subPath)
			else
				result[key] = schemaValue
				table.insert(filled, subPath)
			end
		elseif buyerValue == nil then
			result[key] = if type(schemaValue) == "table" then deepClone(schemaValue) else schemaValue
			table.insert(filled, subPath)
		elseif type(schemaValue) == "table" and type(buyerValue) == "table" then
			result[key] = ClubKitConfigSchema.fillForward(schemaValue, buyerValue, filled, subPath)
		else
			result[key] = buyerValue
		end
	end

	-- Preserve buyer-only keys (not in schema).
	for key, buyerValue in pairs(buyer) do
		if not seen[key] then
			result[key] = buyerValue
		end
	end

	return result
end

ClubKitConfigSchema.deepClone = deepClone

return ClubKitConfigSchema
