--!strict
local RunService = game:GetService("RunService")
local IS_STUDIO = RunService:IsStudio()
-- false = Studio & live pakai key production yang sama (intentional for this kit workflow).
-- true = Studio Play pakai prefix Studio_* (terisolasi dari live).
local USE_STUDIO_DATASTORE_ISOLATION = false
local DATASTORE_SCOPE_PREFIX = if IS_STUDIO and USE_STUDIO_DATASTORE_ISOLATION then "Studio_" else ""

local function scopedDataStoreKey(baseKey: string): string
	if baseKey == "" or DATASTORE_SCOPE_PREFIX == "" then
		return baseKey
	end
	return DATASTORE_SCOPE_PREFIX .. baseKey
end

local Config = {}

local function studioWritesToLiveDatastore(): boolean
	return IS_STUDIO and not USE_STUDIO_DATASTORE_ISOLATION
end

Config.DataStoreScope = {
	IS_STUDIO = IS_STUDIO,
	USE_STUDIO_ISOLATION = USE_STUDIO_DATASTORE_ISOLATION,
	PREFIX = DATASTORE_SCOPE_PREFIX,
	scopedKey = scopedDataStoreKey,
	-- true = Play di Studio menulis ke key production (bahaya untuk /setrobux dll.).
	writesToLive = studioWritesToLiveDatastore,
}

-- ============================================================
-- GROUP SETTINGS
-- ============================================================
Config.Group = {
	GROUP_ID = 0,
	OWNER_USER_ID = 0,
	OWNER_GROUP_RANK = 255,
	-- Filled from Shared/Config/Roles.luau via RolesDomain.applyDerivedConfig.
	RANK_MAP = {} :: { [number]: string },
	-- S5 (quota-efficiency-pass-2026-06, Phase 1): extended from 120s to 300s.
	-- Scaling 100→200 CCU: extended to 600s (10 min). Group ranks change hourly, not per-minute.
	-- Expected HTTP API reduction: 3/m baseline → 1.5/m baseline.
	RANK_CACHE_TTL = 600,
}

-- Branding (ClubKitConfig.Branding → ConfigBootstrap). Logo applied at boot via BrandLogoApplier.
Config.Branding = {
	GAME_NAME = "",
	-- Kit default baked into loading/poster/board ImageLabels; used as match key.
	DEFAULT_LOGO_IMAGE = "rbxassetid://79426970537296",
	-- Buyer override from ClubKitConfig.Branding.LogoImage (same as default until changed).
	LOGO_IMAGE = "rbxassetid://79426970537296",
}
-- ============================================================
-- MEMBERSHIP TIERS (system-wide presentation config)
-- ============================================================
Config.Membership = {
	DEFAULT_TIER = "Guest",
	USE_LABEL_FOR_RANK_TEXT = true,
	USE_LABEL_FOR_CHAT_TAG = true,
	SHOP_TIERS = { "Tier1", "Tier2", "Tier3" },
	PAID_TIERS = {
		Tier1 = true,
		Tier2 = true,
		Tier3 = true,
	},
	-- VIP=Tier1, VVIP=Tier2, Supreme=Tier3.
	ALIASES = {
		guest = "Guest",
		Guest = "Guest",
		member = "Member",
		Member = "Member",
		vip = "Tier1",
		VIP = "Tier1",
		vipmember = "Tier1",
		VIPMember = "Tier1",
		tier1 = "Tier1",
		Tier1 = "Tier1",
		vvip = "Tier2",
		VVIP = "Tier2",
		vvipmember = "Tier2",
		VVIPMember = "Tier2",
		tier2 = "Tier2",
		Tier2 = "Tier2",
		supreme = "Tier3",
		Supreme = "Tier3",
		suprememember = "Tier3",
		SupremeMember = "Tier3",
		elite = "Tier3",
		Elite = "Tier3",
		elitemember = "Tier3",
		ELITEMember = "Tier3",
		exclusive = "Tier3",
		Exclusive = "Tier3",
		tier3 = "Tier3",
		Tier3 = "Tier3",
	},
	Tiers = {
		Guest = {
			value = 0,
			label = "Guest",
			rankText = "GUEST",
			chatTag = "GUEST",
			badgeFrame = nil,
			badgeSettingKey = nil,
			badgeImage = "",
			gradientName = "UIGradientGuest",
			roleColor = { primary = "#6B7280", secondary = "#9CA3AF" },
			rankGradient = false,
		},
		Member = {
			value = 1,
			label = "Member",
			rankText = "MEMBER",
			chatTag = "MEMBER",
			badgeFrame = "04-MemberBadge",
			badgeSettingKey = "Member",
			badgeImage = "rbxassetid://115696416196138",
			gradientName = "UIGradientMember",
			roleColor = { primary = "#2563EB", secondary = "#60A5FA" },
			rankGradient = false,
		},
		Tier1 = {
			value = 2,
			label = "VIP",
			rankText = "VIP MEMBER",
			chatTag = "VIP",
			badgeFrame = "05-VIPMemberBadge",
			badgeSettingKey = "VIP",
			badgeImage = "rbxassetid://120181247918895",
			gradientName = "UIGradientVIP",
			roleColor = { primary = "#F97316", secondary = "#FDBA74" },
			rankGradient = false,
			shopCard = "1-VIP",
			shopNotif = "VIPNotification",
			guiSuffix = "VIP",
			giftTabFrame = "1-VIPTab",
			giftTabButton = "VIPTabButton",
			giftButton = "VIPGiftButton",
			giftActiveGradient = "UIGradient-Gold",
		},
		Tier2 = {
			value = 3,
			label = "VVIP",
			rankText = "VVIP MEMBER",
			chatTag = "VVIP",
			badgeFrame = "06-VVIPMemberBagde",
			badgeSettingKey = "VVIP",
			badgeImage = "rbxassetid://118196125326891",
			gradientName = "UIGradientVVIP",
			roleColor = { primary = "#94A3B8", secondary = "#CBD5E1" },
			rankGradient = true,
			shopCard = "2-VVIP",
			shopNotif = "VVIPNotification",
			guiSuffix = "VVIP",
			giftTabFrame = "2-VVIPTab",
			giftTabButton = "VVIPTabButton",
			giftButton = "VVIPGiftButton",
			giftActiveGradient = "UIGradientSilver",
		},
		Tier3 = {
			value = 4,
			label = "Supreme",
			rankText = "Supreme",
			chatTag = "Supreme",
			badgeFrame = "07-ELITEMemberBadge",
			badgeSettingKey = "Supreme",
			badgeImage = "rbxassetid://107629225021909",
			gradientName = "UIGradientElite",
			roleColor = { primary = "#EF4444", secondary = "#FCA5A5" },
			rankGradient = true,
			shopCard = "3-ELITE",
			shopNotif = "ELITENotification",
			guiSuffix = "ELITE",
			giftTabFrame = "3-EliteTab",
			giftTabButton = "EliteTabButton",
			giftButton = "ELITEGiftButton",
			giftActiveGradient = "UIGradientRed",
		},
	},
}
local function membershipRankText(tierKey: string): string
	local tier = Config.Membership.Tiers[tierKey]
	if not tier then
		return tierKey
	end
	if Config.Membership.USE_LABEL_FOR_RANK_TEXT == true then
		if tierKey == "Tier1" or tierKey == "Tier2" or tierKey == "Tier3" then
			return string.upper(tostring(tier.label)) .. " MEMBER"
		end
		return string.upper(tostring(tier.label))
	end
	return tostring(tier.rankText)
end
local function membershipChatTag(tierKey: string): string
	local tier = Config.Membership.Tiers[tierKey]
	if not tier then
		return tierKey
	end
	if Config.Membership.USE_LABEL_FOR_CHAT_TAG == true then
		return string.upper(tostring(tier.label))
	end
	return tostring(tier.chatTag)
end
-- ============================================================
-- NOTIFY (warna per tipe notifikasi)
-- ============================================================
Config.Notify = {
	COLOR_INFO = Color3.fromRGB(100, 200, 255),
	COLOR_SUCCESS = Color3.fromRGB(100, 255, 150),
	COLOR_WARNING = Color3.fromRGB(255, 220, 80),
	COLOR_ERROR = Color3.fromRGB(255, 100, 100),
	COLOR_SYSTEM = Color3.fromRGB(200, 200, 200),
}
Config.Announcement = {
	REMOTE_BROADCAST = "GenericBroadcast",
	CMD_ALIAS_ANNOUNCE = "announce",
	CMD_ALIAS_ANNOUNCE_SHORT = "a",
	MIN_GROUP_RANK = 40, -- Tier2+
	MAX_MESSAGE_LENGTH = 180,
	RATE_MAX = 2,
	RATE_WINDOW = 30,
	SHOW_DURATION = 8,
	ENTER_SOUND_ID = "rbxassetid://74687624322129",
	ENTER_SOUND_VOLUME = 0.65,
	MAX_QUEUE = 8,
	MSG_USAGE = "[Announcement] Use /announce <message> or /a <message>.",
	MSG_NO_PERM = "[Announcement] This command is " .. Config.Membership.Tiers.Tier2.label .. "-only and above.",
	MSG_RATE_LIMIT = "[Announcement] Chill bro, wait a sec before announcing again.",
	MSG_FILTER_FAILED = "[Announcement] Roblox could not review that message. Try different wording.",
	MSG_SENT = "[Announcement] Broadcast sent.",
	-- GenericBroadcast wrapper offset while donation notification is visible.
	BROADCAST_WRAPPER_POSITION_DURING_DONATION = UDim2.new(0.5, 0, 0.87, 0),
	BROADCAST_WRAPPER_ANCHOR_DURING_DONATION = Vector2.new(0.5, 1),
}
-- ============================================================
-- JOIN GREETINGS (toast when Owner / Leadership / Content / top-10 spender joins)
-- ============================================================
-- ============================================================
-- JOIN COMMUNITY PROMPT (custom 16-JoinCommunPrompt modal)
-- ============================================================
Config.JoinCommunityPrompt = {
	REMOTE_REQUEST = "JoinCommunityMembersRequest",
	REMOTE_RESPONSE = "JoinCommunityMembersResponse",
	-- Client → server after PromptJoinAsync (or anytime): re-check IsInGroup + grant VIP if flag on.
	REMOTE_VIP_RECHECK = "CommunityVipRecheck",
	-- Client may fire immediate + delayed retries after PromptJoinAsync (group lag).
	VIP_RECHECK_RATE_MAX = 8,
	VIP_RECHECK_RATE_WINDOW = 60,
	SAMPLE_LIMIT = 8,
	POOL_SIZE = 40, -- in-experience / MemoryStore pool cap (bonus thumbs only — not the community total)
	CACHE_TTL = 300, -- seconds; successful MemberCount + users-page cache
	MEMBER_COUNT_FAIL_TTL = 45, -- short negative cache when total unresolved
	-- GroupService:GetGroupInfoAsync docs omit MemberCount (often absent → expected engine behavior).
	-- Preference for real total + thumbs:
	--   1) GroupService MemberCount / EmblemUrl when present
	--   2) game-data-api GET /game/:gameKey/community/:groupId (Secrets.GameDataApiSecret + Config.GameDataApi)
	--   3) MEMBER_INFO_URL / MEMBER_USERS_URL (default roproxy) or ClubKitConfig.JoinCommunity.MemberInfoUrl
	-- Studio without GameDataApiSecret skips worker and uses (3) — same pattern as Overhead/ProfileSocial.
	-- Supports "%d" or "{groupId}". Expected JSON: { "memberCount": N, "members"?: [...], "emblemUrl"?: "..." }
	MEMBER_INFO_URL = "https://groups.roproxy.com/v1/groups/%d",
	-- Fallback page of group members for avatar thumbs when worker community is unavailable.
	-- Roblox Groups API only accepts limit ∈ {10, 25, 50, 100}; kit clamps any other value (was 40 → HTTP 400).
	-- Default Asc: Desc has been seen to 400 on some huge groups / proxy paths; service also retries Asc + roles/{id}/users.
	-- Expected JSON: { "data": [ { "user": { "userId", "displayName"|"username" } } ] }
	-- Role-users fallback may return flat { userId, displayName } rows in data[].
	-- Skipped when game-data community returns members[].
	MEMBER_USERS_URL = "https://groups.roproxy.com/v1/groups/%d/users?limit=50&sortOrder=Asc",
	-- Cross-server thumb pool via MemoryStore (bonus samples only).
	MEMORY_STORE_ENABLED = true,
	MEMORY_STORE_TTL = 86400,
	MEMORY_STORE_NAME = nil, -- default: KitProduct.MemoryStorePrefix .. "JoinCommunityPool"
	REQUEST_RATE_MAX = 4,
	REQUEST_RATE_WINDOW = 30,
	-- Headline = VIP incentive; social strip = community members (not VIP framing).
	TITLE = "Join our community, and get free VIP.",
	SUBHEADLINE = "Limited time, save up to 50 Robux.",
	-- CTA: always show modal; label depends on IsInGroup (already joined → no PromptJoinAsync).
	BUTTON_JOIN = "Join Community",
	BUTTON_ALREADY_JOINED = "Already joined",
	-- Social strip: subtitle qualitative (no huge number); body carries compact count once.
	SUBTITLE_WITH_COUNT = "Players already in this community.",
	SUBTITLE_FALLBACK = "Join players already here.",
	SUBTITLE_WITH_SAMPLE = "Players already in this community.",
	-- Body when no name sample: pick lightly from pool (%s = compact count e.g. 10.6M / 1.2k).
	BODY_EMPTY_WITH_COUNT = "Over %s players already joined.",
	BODY_EMPTY_WITH_COUNT_ALT = {
		"Over %s players already joined.",
		"Join %s others already here.",
		"%s players are already in — join them.",
	},
	BODY_EMPTY = "Be among the first to join this community.",
	BODY_NO_COUNT = "Join players already in this community.",
	BODY_ONE = "%s already joined this community.",
	BODY_TWO = "%s and %s already joined this community.",
	BODY_THREE = "%s, %s, and %s already joined this community.",
	-- First %s = up to 3 names (Oxford "and"); second %s = compact remaining (k/M/B, not +99-capped).
	BODY_WITH_NAMES = "%s and %s others already joined this community.",
}

Config.JoinGreeting = {
	REMOTE = "JoinGreeting",
	SPENDER_TOP_N = 10,
	GREETING_CATEGORY_IDS = {
		Leadership = 1,
		Content = 3,
	},
	-- Visible card ≈ 7s: MESSAGE_HOLD + (MESSAGE_FADE * 2) + WELCOME_HOLD
	MESSAGE_HOLD = 3.7,
	MESSAGE_FADE = 0.25,
	WELCOME_HOLD = 2.8,
	-- EXIT/ENTER match GenericBroadcastController toast timings (0.22 / 0.28).
	EXIT = 0.22,
	ENTER = 0.28,
	-- Client holds toast until Main enterGameplay (after loading click + camera reveal).
	WAIT_FOR_GAMEPLAY = true,
	MAX_VISIBLE_CARDS = 2,
	-- Second-line toast after creative message (placeholders: {Gelar}, {DisplayName}).
	ENTERED_SPACE_TEMPLATE = "{Gelar} {DisplayName} has entered the space!",
	-- Spender gelar templates only (#{N}/{N}). Role-based gelar uses Roles DEFINITIONS.label.
	GELAR_TITLES = {
		SpenderRobux = "Top Robux Donator #{N}",
		SpenderCash = "Top Rupiah Spender #{N}",
	},
	CHIP_LABELS = {
		Owner = "The Owner",
		Staff = "Staff",
		DJ = "DJ",
		LeadDance = "Lead Dance",
		Streamer = "Streamer",
		Influencer = "Influencer",
		_Leadership = "Staff",
		_Content = "Content",
		RoyaleSpender = "Top Robux Donator #{N}",
		TopSpender = "Top Rupiah Spender #{N}",
	},
	MESSAGE_POOLS = {
		Owner = {
			"The house just got its keyholder.",
			"Owner in the building, lights up.",
			"The club's compass just walked in.",
			"Keys to the kingdom just arrived.",
			"The booth salutes its owner.",
			"House rules just walked through the door.",
			"The main chair is occupied again.",
			"Owner energy just entered the lobby.",
		},
		Staff = {
			"Ops just hit the floor.",
			"Leadership on site, keep it clean.",
			"The floor crew just checked in.",
			"Staff in, chaos has adult supervision.",
			"Someone who actually has the keys is here.",
			"The radio just got louder.",
			"Backstage just got backup.",
			"Staff badge spotted in the wild.",
		},
		_Leadership = {
			"Ops just hit the floor.",
			"Leadership on site, keep it clean.",
			"The floor crew just checked in.",
			"Someone who actually has the keys is here.",
			"The radio just got louder.",
			"Backstage just got backup.",
			"Leadership just walked in.",
			"The house just got more supervision.",
		},
		DJ = {
			"Decks just got dangerous.",
			"The booth is no longer empty.",
			"Somebody bring the drops, DJ's here.",
			"Frequency incoming.",
			"The night just found its pilot.",
			"Bass is about to get personal.",
			"Cue the lights, the DJ pulled up.",
			"Playlist destiny just arrived.",
		},
		LeadDance = {
			"Formation just found its captain.",
			"The circle's about to tighten.",
			"Lead Dance stepped in, watch the floor.",
			"Sync just got serious.",
			"The pack leader just joined the set.",
			"Count it in, Lead Dance is here.",
			"The floor just got a director.",
			"Choreo energy just entered the room.",
		},
		Streamer = {
			"Cameras up, a streamer's in.",
			"You're on someone's livestream now.",
			"Content just went live in the room.",
			"Chat is about to spam HI.",
			"Stream mode: ON.",
			"Red light, camera, club.",
			"Someone's about to clip this.",
			"Live chat just got a venue.",
		},
		Influencer = {
			"Clout just pulled up.",
			"The timeline just got a guest star.",
			"Influencer in, screenshots incoming.",
			"Soft launch: main character energy.",
			"The For You page just walked in.",
			"Aesthetic just entered the lobby.",
			"Trend alert just checked in.",
			"Camera roll is about to eat.",
		},
		_Content = {
			"Content just entered the room.",
			"The stage just got louder.",
			"Creative energy just pulled up.",
			"The set just found more talent.",
			"Spotlight incoming.",
			"The feed just got a new guest.",
		},
		RoyaleSpender = {
			"Top Robux Donator #{N}, the room noticed.",
			"Wallet royalty #{N} just rolled in.",
			"#{N} on the Robux board just arrived.",
			"Robux donator #{N} pulled up with that bag energy.",
			"The Robux board's #{N} is in the club.",
			"Top Robux Donator #{N} just lit up the lobby.",
			"Board rank #{N} just walked in with Robux vibes.",
		},
		["RoyaleSpender#1"] = {
			"The Robux throne just sat down.",
			"Number one on the Robux board just arrived.",
			"Top Robux Donator #1 pulled up, the room noticed.",
			"The Robux crown just entered the club.",
		},
		TopSpender = {
			"Cash crown #{N} just entered.",
			"Top Rupiah Spender #{N}, VIP energy unlocked.",
			"#{N} on the Rupiah board just walked in.",
			"Rupiah spender #{N} just made the lobby richer.",
			"The Rupiah board's #{N} is here.",
			"Top Rupiah Spender #{N} just checked into the house.",
			"Board rank #{N} just arrived with Rupiah energy.",
		},
		["TopSpender#1"] = {
			"The house's biggest Rupiah spender just landed.",
			"Number one on the Rupiah board just arrived.",
			"Cash crown #1 just entered.",
			"Top Rupiah Spender #1 just made the lobby richer.",
		},
	},
}
Config.PaidBroadcast = {
	GUI_NAME = "13-PaidBroadcast",
	GUI_SCALE_MOBILE = 0.75,
	GUI_SCALE_DESKTOP = 0.88,
	PRODUCT_ID = 0, -- diisi ConfigBootstrap dari ClubKitConfig.PaidBroadcast.ProductId
	REMOTE_SUBMIT = "PaidBroadcastSubmit",
	REMOTE_RESULT = "PaidBroadcastResult",
	MAX_MESSAGE_LENGTH = 180,
	MODAL_TITLE_MAX_LENGTH = 120,
	PENDING_TIMEOUT = 120,
	PROMPT_DELAY = 0.35,
	RATE_MAX = 1,
	RATE_WINDOW = 60,
	SHOW_DURATION = 8,
	TOPBAR_LABEL = "Broadcast",
	TOPBAR_ORDER = 10,
	TOPBAR_ICON = "rbxassetid://101268994273611",
	CONTINUE_TEXT_TEMPLATE = "Send a broadcast message - %d Robux",
	CONTINUE_TEXT_FREE = "Send broadcast",
	MODAL_TITLE_FALLBACK = "What's on your mind?",
	MODAL_TITLE_VARIANTS = {
		"Sup, {name}! What's on your mind?",
		"Hey {name} — what's on your mind?",
		"Yo {name}, drop a broadcast message.",
		"What's good, {name}?",
		"Hey there, {name}! Got something to share?",
		"Hi {name}! What are you thinking?",
		"Welcome back, {name} — say something loud.",
		"Ready to go live, {name}?",
		"Time to broadcast, {name}.",
		"Got a message for everyone, {name}?",
		"The whole server is listening, {name}.",
		"Make it count, {name} — what's the message?",
		"Spotlight's on you, {name}. What do you say?",
		"Say it to the world, {name}.",
		"What's on your mind, {name}?",
		"What do you want to tell everyone, {name}?",
		"Care to announce something, {name}?",
		"Got news for the club, {name}?",
		"Anything you want the server to hear, {name}?",
		"Mic check — {name}, you're up.",
		"{name}, your broadcast moment starts here.",
		"Don't be shy, {name}. Type it out.",
		"One message, whole server — go, {name}.",
		"Your voice, {name}. One broadcast away.",
		"Halo {name}! Mau broadcast apa hari ini?",
		"Yuk {name}, spill isi pikiranmu.",
		"Siap-siap live, {name}?",
		"Ada yang mau disampaikan ke server, {name}?",
		"Hai {name} — mau ngomong apa nih?",
		"Panggungmu nih, {name}. Ketik pesannya.",
	},
	MSG_EMPTY = "[Broadcast] Type a message first.",
	MSG_TOO_LONG = "[Broadcast] Message is too long.",
	MSG_FILTER_FAILED = "[Broadcast] Roblox could not review that message. Try different wording.",
	MSG_RATE_LIMIT = "[Broadcast] Please wait before sending another broadcast.",
	MSG_SENT = "[Broadcast] Your message was sent to the server.",
	MSG_PRODUCT_NOT_CONFIGURED = "[Broadcast] Paid broadcast is not available yet.",
	MSG_PURCHASE_FAILED = "[Broadcast] Purchase could not be completed.",
}
Config.CinematicDock = {
	REMOTE_REQUEST = "CinematicDockRequest",
	REMOTE_BROADCAST = "CinematicDockBroadcast",
	REMOTE_TARGETS = "CinematicDockTargets",
	GUI_NAME = "12-CinematicDockGUI",
	-- Bottom chrome slide (CinematicDock panel + hotbar) — CinematicDockController.setDockVisible
	DOCK_CHROME_HIDE_DURATION = 0.18,
	DOCK_CHROME_SHOW_DURATION = 0.28,
	DOCK_CHROME_SLIDE_OFFSET_Y = 70,
	DOCK_CHROME_START_SCALE = 0.96,
	DOCK_MAGNIFIER_ENABLED = false,
	CCTV_ATTRIBUTE = "CCTV",
	CCTV_ID_ATTRIBUTE = "CCTVId",
	CCTV_NAME_ATTRIBUTE = "DisplayName",
	-- Optional: set to "360" on a rig part to force the wide 360 movement set.
	CCTV_PROFILE_ATTRIBUTE = "CCTVProfile",
	-- Runtime visual policy untuk rig CCTV (BasePart target kamera).
	-- 1 = fully hidden, 0 = fully visible.
	CCTV_RUNTIME_TRANSPARENCY = 1,
	-- Semua BasePart di bawah folder ini (di workspace) otomatis jadi target CCTV.
	CCTV_FOLDER_NAMES = { "CCTV" },
	DEFAULT_DURATION = 12,
	MAX_DURATION = 30,
	MIN_DURATION = 4,
	DEFAULT_SPEED = 1,
	ALLOWED_SPEEDS = { 0.5, 1, 1.25, 1.5, 2 },
	-- Rate limit untuk broadcast (selain stop). 3 broadcast / 12 detik per admin.
	RATE_MAX = 3,
	RATE_WINDOW = 12,
	-- Movement options yang diiklankan ke UI client.
	-- `targetType` filter: "character" hanya muncul saat target = player,
	-- "part" hanya muncul saat target = CCTV. "any" muncul di kedua kasus.
	-- Urutan di list = urutan tampil di panel dock.
	MOVEMENT_OPTIONS = {
		-- Character orbit modes
		{ value = "PendulumOrbit", label = "Pendulum Orbit", targetType = "character" },
		{ value = "DonationOrbit", label = "Donation Orbit", targetType = "character" },
		{ value = "SlowOrbit", label = "Slow Orbit", targetType = "character" },
		{ value = "FastOrbit", label = "Fast Orbit", targetType = "character" },
		{ value = "HighOrbit", label = "High Orbit", targetType = "character" },
		{ value = "LowOrbit", label = "Low Orbit", targetType = "character" },
		-- Dolly & truck shots
		{ value = "DollyIn", label = "Dolly In", targetType = "character" },
		{ value = "DollyOut", label = "Dolly Out", targetType = "character" },
		{ value = "TruckLeft", label = "Truck Left", targetType = "character" },
		{ value = "TruckRight", label = "Truck Right", targetType = "character" },
		{ value = "CraneUp", label = "Crane Up", targetType = "character" },
		{ value = "CraneDown", label = "Crane Down", targetType = "character" },
		-- Locked angles
		{ value = "CloseUp", label = "Close Up", targetType = "character" },
		{ value = "WideShot", label = "Wide Shot", targetType = "character" },
		{ value = "OverShoulder", label = "Over The Shoulder", targetType = "character" },
		{ value = "PointOfView", label = "Point Of View", targetType = "character" },
		{ value = "WormsEye", label = "Worm's Eye", targetType = "character" },
		{ value = "BirdsEye", label = "Bird's Eye", targetType = "character" },
		{ value = "DutchAngle", label = "Dutch Angle", targetType = "character" },
		-- Effects & dynamics
		{ value = "Handheld", label = "Handheld", targetType = "character" },
		{ value = "Drift", label = "Drift", targetType = "character" },
		{ value = "ZoomBurst", label = "Zoom Burst", targetType = "character" },
		{ value = "Vertigo", label = "Vertigo", targetType = "character" },
		{ value = "Heartbeat", label = "Heartbeat", targetType = "character" },
		{ value = "Earthquake", label = "Earthquake", targetType = "character" },
		-- Path-based
		{ value = "SpiralIn", label = "Spiral In", targetType = "character" },
		{ value = "SpiralOut", label = "Spiral Out", targetType = "character" },
		{ value = "FigureEight", label = "Figure Eight", targetType = "character" },
		{ value = "Helix", label = "Helix", targetType = "character" },
		{ value = "ChaseCam", label = "Chase Cam", targetType = "character" },
		{ value = "DroneFlyby", label = "Drone Flyby", targetType = "character" },
		-- Genre / mood
		{ value = "NoirShadow", label = "Noir Shadow", targetType = "character" },
		{ value = "RomanticGlide", label = "Romantic Glide", targetType = "character" },
		{ value = "EpicReveal", label = "Epic Reveal", targetType = "character" },
		{ value = "MusicVideoSpin", label = "Music Video Spin", targetType = "character" },
		-- CCTV / static rig modes
		{ value = "CCTVView", label = "CCTV View", targetType = "part" },
		{ value = "CCTVPan", label = "CCTV Pan", targetType = "part" },
		{ value = "CCTVTilt", label = "CCTV Tilt", targetType = "part" },
		{ value = "CCTVPanTilt", label = "CCTV Pan + Tilt", targetType = "part" },
		{ value = "CCTVSweepWide", label = "CCTV Sweep Wide", targetType = "part" },
		{ value = "CCTVZoom", label = "CCTV Zoom", targetType = "part" },
		{ value = "CCTVPushIn", label = "CCTV Push In", targetType = "part" },
		{ value = "CCTVFocusPulse", label = "CCTV Focus Pulse", targetType = "part" },
		{ value = "CCTVStatic", label = "CCTV Static", targetType = "part" },
		{ value = "CCTVMicroShake", label = "CCTV Micro Shake", targetType = "part" },
		{ value = "CCTVGlitch", label = "CCTV Glitch", targetType = "part" },
		-- 360 venue rig (wide FOV, center spin — only on rigs matched as 360)
		{ value = "CCTV360Overview", label = "360 Overview", targetType = "part360" },
		{ value = "CCTV360Spin", label = "360 Spin", targetType = "part360" },
		{ value = "CCTV360HalfSweep", label = "360 Half Sweep", targetType = "part360" },
		{ value = "CCTV360Patrol", label = "360 Patrol", targetType = "part360" },
		{ value = "CCTV360Pulse", label = "360 Atmosphere Pulse", targetType = "part360" },
		{ value = "CCTV360StaticWide", label = "360 Static Wide", targetType = "part360" },
	},
	MSG_NO_PERM = "You don't have permission to use this feature.",
	MSG_INVALID_TARGET = "[Cinematic] Invalid target.",
	MSG_INVALID_MOVEMENT = "[Cinematic] Invalid movement.",
	MSG_SENT = "[Cinematic] Broadcast started.",
	MSG_RATE_LIMIT = "[Cinematic] Wait a moment before broadcasting again.",
}
-- ============================================================
-- DATASTORE KEYS (versioned)
-- ============================================================
Config.DataStore = {
	OVERHEAD_KEY = scopedDataStoreKey("Overhead_v1"),
	ABOUT_ROSTER_KEY = scopedDataStoreKey("AboutRoster_v1"),
	ABOUT_ROSTER_ENTRY_KEY = "team",
	CACHE_TTL = 120,  -- Scaling 100→200 CCU: extended from 60s to 120s to reduce DataStore GetAsync by 50%
	GROUP_CACHE_TTL = 120,
	-- Likes summary rarely changes (once per like action), safe to cache longer.
	-- Reduces DataStore GetAsync burst at 30 CCU refreshAll (30 concurrent reads → 1 per TTL window).
	LIKE_SUMMARY_CACHE_TTL = 300, -- 5 min (was 60s via CACHE_TTL fallback)
	RETRY_ATTEMPTS = 3,
	-- Join/load GetAsync: keep 1 attempt inside DataStoreScheduler slot so throttle
	-- backoff (2s/4s/8s) does not hold MAX_INFLIGHT. ProfileLoader retries outside the slot.
	-- Writes/UpdateAsync keep RETRY_ATTEMPTS. Set to 3 to A/B the pre-fix behavior.
	JOIN_READ_RETRY_ATTEMPTS = 1,
	-- Leaderboard GetSortedAsync only: 1 attempt inside BudgetGate slot (no 2s/4s/8s storm).
	LB_READ_RETRY_ATTEMPTS = 1,
	-- Owner-only favorites write-behind (music + dance).
	FAVORITES_SAVE_DEBOUNCE_SEC = 8,
}
-- ============================================================
-- BADGE VISIBILITY PER ROLE
-- ============================================================
-- Filled from Shared/Config/Roles.luau (plus membership tier badges).
Config.BadgeVisibility = {} :: { [string]: { string } }
-- ============================================================
-- SPECIAL RANK (04-SpecialRank)
-- ============================================================
Config.SpecialRank = {} :: { [string]: { text: string, gradient: boolean } }
-- ============================================================
-- RANK BIASA (07-Rank)
-- ============================================================
Config.RankDisplay = {
	ELITEMember = { text = membershipRankText("Tier3"), gradient = Config.Membership.Tiers.Tier3.rankGradient },
	VVIPMember = { text = membershipRankText("Tier2"), gradient = Config.Membership.Tiers.Tier2.rankGradient },
	VIPMember = { text = membershipRankText("Tier1"), gradient = Config.Membership.Tiers.Tier1.rankGradient },
	Tier3 = { text = membershipRankText("Tier3"), gradient = Config.Membership.Tiers.Tier3.rankGradient },
	Tier2 = { text = membershipRankText("Tier2"), gradient = Config.Membership.Tiers.Tier2.rankGradient },
	Tier1 = { text = membershipRankText("Tier1"), gradient = Config.Membership.Tiers.Tier1.rankGradient },
	Member = { text = membershipRankText("Member"), gradient = Config.Membership.Tiers.Member.rankGradient },
	Guest = { text = membershipRankText("Guest"), gradient = Config.Membership.Tiers.Guest.rankGradient },
}
-- ============================================================
-- SETROLE COMMAND
-- ============================================================
Config.SetRole = {
	ROLE_ALIASES = {} :: { [string]: string },
	RATE_MAX = 5,
	RATE_WINDOW = 60,
	MSG_SUCCESS = "[SetRole] %s is now assigned to %s.",
	MSG_REMOVED = "[SetRole] Removed %s from %s.",
	MSG_REMOVE_NONE = "[SetRole] %s does not have a gifted role right now.",
	MSG_NOT_FOUND = "[SetRole] I could not find '%s' in this server.",
	MSG_QUERY_SHORT = "[SetRole] Give me at least 3 letters, or use the full name.",
	MSG_AMBIGUOUS = "[SetRole] '%s' matches a few people: %s.",
	MSG_INVALID_ROLE = "[SetRole] '%s' is not a role I can use.",
	MSG_NO_PERM = "[SetRole] This one is admin-only.",
	MSG_RATE_LIMIT = "[SetRole] Slow down for a second.",
	MSG_SAVE_FAILED = "[SetRole] Could not save that change. Try again.",
	CMD_ALIAS_SET = "setrole",
	CMD_ALIAS_UNSET = "unsetrole",
}
-- ============================================================
-- HARDCODED SPECIAL DATA
-- ============================================================
Config.Hardcoded = {
	-- [userId] = { specialTitle = "teks", specialRank = "teks" }
}
-- ============================================================
-- SECURITY
-- ============================================================
Config.Security = {
	REFRESH_MAX = 3,
	REFRESH_WINDOW = 10,
	MAX_REQUEST_CACHE = 500,
	CHAT_COMMAND_DEDUPE_WINDOW = 2,
	MAX_PAYLOAD_BYTES = 1024, -- 1KB untuk commands
	-- TTL-based dedup windows - cegah wipe-all cache issue
	REQUEST_DEDUPE_WINDOW = 10, -- detik dedup untuk admin/couple commands
	PURCHASE_DEDUPE_WINDOW = 3600, -- 1 jam dedup untuk PurchaseId receipt
}
-- ============================================================
-- OVERHEAD CONTROLLER TIMING
-- ============================================================
Config.Overhead = {
	GUI_TYPE = "V4",
	-- Perf-scaling feature flags (R4 / R8). Flip to false to roll back the optimization instantly.
	-- R4: build badge/effect rows lazily on show + pool on hide so hidden rows cost 0 instances.
	ENABLE_LAZY_ROWS = true,
	-- R8: cache the per-nametag {label -> effectConfig} map at build time; delta updates never re-walk the tree.
	ENABLE_EFFECT_CACHE = true,
	-- Opt-in: animate UIGradient on 00-DonationLayers RobuxRankWrapper / RupiahRankWrapper.
	-- Safe when wrappers lack UIGradient (no-op). Buyer toggle: ClubKitConfig.Features.DonationRankGradientAnim.
	ANIMATE_DONATION_RANK_GRADIENT = false,
	BATCH_MESSAGE_KIND = "overhead_batch",
	DELTA_MESSAGE_KIND = "overhead_delta",
	EXISTING_PAYLOAD_BATCH_SIZE = 25,
	EXISTING_PAYLOAD_BATCH_DELAY = 0.03,
	ROSTER_REQUEST_RATE_MAX = 2,
	ROSTER_REQUEST_RATE_WINDOW = 10,
	-- Soft ceiling for AdornReady wait before first join broadcast (signal gate;
	-- usually instant after stable-Head attach). No longer an unconditional sleep.
	CHARACTER_READY_DELAY = 0.5,
	-- Detik setelah broadcast pertama untuk kirim broadcast kedua (deferred re-broadcast).
	-- Memberi waktu GroupService:GetGroupsAsync() selesai di live server (biasanya 1-3 detik).
	-- Broadcast kedua memastikan role yang benar (Owner/Admin/dll.) sampai ke client.
	-- S4 (quota-efficiency-pass-2026-06, Phase 1, Q1=extend): extended from 4s to 15s.
	-- 2nd broadcast dipertahankan untuk UX role-settle, tapi dipindah ke window yang
	-- cukup jauh dari join storm (default 4s tumpang tindih dengan peak load).
	-- Revert to 4 via Config if UX requires faster settle.
	GROUP_RANK_SETTLE_DELAY = 5,
	-- Live rank resolve via getRobuxLeaderboard: defer until DonationController LB pre-warm
	-- (~25s) has populated robux cache. Stored topDonateRank still shows at join.
	RANK_RESOLVE_DELAY_SEC = 30,
	RANK_RESOLVE_JITTER_SEC = 5,
	-- Client tunggu OverheadUpdate (detik). Server boot berat bisa >10s di Studio.
	REMOTE_READY_TIMEOUT = 45,
	-- Timeout WaitForChild saat attach GUI ke Head (detik)
	HEAD_WAIT_TIMEOUT = 5,
	-- After Head appears, prefer AppearanceLoaded (CharacterReady); debounce below
	-- is fallback when CAL never fires (some StarterCharacters).
	HEAD_STABLE_DEBOUNCE = 0.35,
	-- Cap for stable-Head wait (AppearanceLoaded wait + debounce fallback).
	HEAD_STABLE_TIMEOUT = 8,
	-- Batas maksimal tunggu in-flight GroupService call (detik)
	INFLIGHT_WAIT_MAX = 5,
	-- Timeout WaitForChild Humanoid/HumanoidRootPart saat restore session (detik)
	CHARACTER_PART_WAIT_TIMEOUT = 5,
	-- S1 (quota-efficiency-pass-2026-06, Phase 1): short-circuit buildAndCachePayload
	-- kalau input cache state (groups, grouprank, stored data, leaderboard ranks) tidak
	-- berubah sejak last build. Skip service:buildPayload() entirely. Kill switch:
	-- set S1_SHORTCIRCUIT = false to revert to always-build behavior.
	S1_SHORTCIRCUIT = true,
	-- S2 (quota-efficiency-pass-2026-06, Phase 1): debounce refreshAll. Skip kalau
	-- <S2_DEBOUNCE_MS dari last call. Coalesce donation burst jadi 1 broadcast. Set
	-- to 0 to disable (default on, 1000ms).
	S2_DEBOUNCE_MS = 1000,
}
Config.OverheadGuiVariants = {
	V1 = {
		templateName = "OverheadGUIMainTemplate",
		renderer = "V1",
		wrapperName = "OverheadGUIMainWrapper",
		preserveLayoutOrder = false,
	},
	V2 = {
		templateName = "OverheadGUIMainTemplateV2",
		renderer = "V2",
		wrapperName = "Frame",
		preserveLayoutOrder = true,
	},
	V3 = {
		templateName = "OverheadGUIMainTemplateV3",
		renderer = "V3",
		wrapperName = "Frame",
		preserveLayoutOrder = true,
	},
	V4 = {
		templateName = "OverheadGUIMainTemplateV4",
		renderer = "V4",
		wrapperName = "Frame",
		preserveLayoutOrder = true,
	},
}
-- ============================================================
-- RATE LIMITER
-- ============================================================
Config.RateLimiter = {
	-- Interval cleanup bucket (detik) - expired entries dihapus secara periodik
	CLEANUP_INTERVAL = 300,
}
-- ============================================================
-- TEMPLATE
-- ============================================================
local activeOverheadGuiVariant = Config.OverheadGuiVariants[Config.Overhead.GUI_TYPE] or Config.OverheadGuiVariants.V1
Config.Template = {
	TEMPLATE_NAME = activeOverheadGuiVariant.templateName,
}
-- ============================================================
-- STREAK
-- ============================================================
Config.Streak = {
	MIN_DAYS = 1,
	-- Hari yang dianggap milestone (animasi lebih dramatis)
	MILESTONE_DAYS = { 7, 14, 30, 60, 100, 365 },
	-- Remote name
	REMOTE_NOTIF = "StreakNotif", -- Server -> Client
	-- Timing
	SHOW_DURATION = 3.0, -- detik ditampilkan sebelum auto-dismiss
	COUNTER_DURATION = 1.2, -- durasi counter animate 0 -> angka
	CLIENT_READY_DELAY = 1.5, -- tunggu client siap sebelum fire notif
	-- Glow pulse
	GLOW_PULSE_COUNT = 3,
	GLOW_PULSE_SIZE_OUT = 430, -- px saat pulse mengembang
	GLOW_PULSE_SIZE_IN = 400, -- px saat pulse menyusut
	-- Overlay backdrop
	OVERLAY_TRANSPARENCY = 0.45,
	-- Particles
	PARTICLE_COUNT = 45,
	PARTICLE_SIZE_MIN = 3,
	PARTICLE_SIZE_MAX = 8,
	PARTICLE_DIST_MIN = 0.22, -- jarak minimal dalam scale
	PARTICLE_DIST_MAX = 0.44, -- jarak maksimal (DIST_MIN + 0.22)
	PARTICLE_DELAY_MAX = 0.25, -- delay burst maks per partikel
	PARTICLE_DUR_MIN = 1.8, -- durasi terbang minimal
	PARTICLE_DUR_VAR = 0.8, -- variasi tambahan (random * ini)
}
-- ============================================================
-- MEMBERSHIP BADGE
-- ============================================================
Config.MembershipBadgeOrder = {
	"Tier3",
	"Tier2",
	"Tier1",
	"ELITEMember",
	"VVIPMember",
	"VIPMember",
	"Member",
}
Config.MembershipBadgeFrame = {
	Tier3 = Config.Membership.Tiers.Tier3.badgeFrame,
	Tier2 = Config.Membership.Tiers.Tier2.badgeFrame,
	Tier1 = Config.Membership.Tiers.Tier1.badgeFrame,
	ELITEMember = Config.Membership.Tiers.Tier3.badgeFrame,
	VVIPMember = Config.Membership.Tiers.Tier2.badgeFrame, -- typo di template dipertahankan
	VIPMember = Config.Membership.Tiers.Tier1.badgeFrame,
	Member = Config.Membership.Tiers.Member.badgeFrame,
}
Config.MembershipTierValue = {
	Guest = Config.Membership.Tiers.Guest.value,
	Member = Config.Membership.Tiers.Member.value,
	Tier1 = Config.Membership.Tiers.Tier1.value,
	Tier2 = Config.Membership.Tiers.Tier2.value,
	Tier3 = Config.Membership.Tiers.Tier3.value,
	VIPMember = Config.Membership.Tiers.Tier1.value,
	VVIPMember = Config.Membership.Tiers.Tier2.value,
	ELITEMember = Config.Membership.Tiers.Tier3.value,
}
Config.MembershipChatLabel = {
	Guest = Config.Membership.Tiers.Guest.label,
	Member = Config.Membership.Tiers.Member.label,
	Tier1 = Config.Membership.Tiers.Tier1.label,
	Tier2 = Config.Membership.Tiers.Tier2.label,
	Tier3 = Config.Membership.Tiers.Tier3.label,
	VIPMember = Config.Membership.Tiers.Tier1.label,
	VVIPMember = Config.Membership.Tiers.Tier2.label,
	ELITEMember = Config.Membership.Tiers.Tier3.label,
}
-- Derived from Shared/Config/Roles.luau (see RolesDomain.applyDerivedConfig).
Config.ChatPrimaryTagPriority = {} :: { [string]: number }
Config.ChatPrimaryTagLabel = {} :: { [string]: string }
Config.RoleColorPalette = {} :: { [string]: { primary: string, secondary: string } }
Config.ChatPrimaryTagColor = {} :: { [string]: string }
Config.ChatCoupleTagColor = "#FF7EB6"
Config.PlayerList = {
	RANK_STAT_NAME = "Rank",
	STREAK_STAT_NAME = "Streak",
	LEVEL_STAT_NAME = "Level",
	LIKES_STAT_NAME = "Likes",
	ROBUX_STAT_NAME = "Robux",
	CASH_STAT_NAME = "Cash",
	-- BrickColor names untuk PlayerList built-in Roblox
	-- Team.TeamColor = BrickColor (limited palette ~63 preset)
	-- BrickColor.new(Color3) snap ke preset terdekat -> sering jadi abu-abu
	-- Solusi: pakai BrickColor name langsung biar warna konsisten
	TEAM_COLORS = {} :: { [string]: string },
}
-- ============================================================
-- COUPLE SYSTEM
-- ============================================================
Config.Couple = {
	-- Berapa lama request couple aktif sebelum expired (detik)
	REQUEST_TIMEOUT = 60,
	-- Rate limit request
	RATE_MAX = 3,
	RATE_WINDOW = 60,
	-- Topbar
	TOPBAR_ORDER = 3,
	-- Announce ke semua player
	ANNOUNCE_COUPLED = "%s dan %s sekarang sudah berpasangan! 💕",
	ANNOUNCE_BREAKUP = "%s dan %s telah berpisah. 💔",
	ANNOUNCE_COLOR = "rgb(255,180,255)",
	ANNOUNCE_MAX_ATTEMPTS = 5,
	ANNOUNCE_RETRY_WAIT = 0.3,
	-- Chat / notif feedback
	MSG_ALREADY_COUPLED = "[Couple] You are already paired up.",
	MSG_TARGET_COUPLED = "[Couple] That player is already paired up.",
	MSG_REQUEST_SENT = "[Couple] Request sent to %s.",
	MSG_REQUEST_PENDING = "[Couple] You already have a request waiting.",
	MSG_NOT_FOUND = "[Couple] I could not find that player.",
	MSG_SELF = "[Couple] Pick someone else, not yourself.",
	MSG_RATE_LIMIT = "[Couple] Give it a second before trying again.",
	MSG_BREAKUP_DONE = "[Couple] You and %s are no longer paired.",
	MSG_NO_COUPLE = "[Couple] No couple to break right now.",
}
-- ============================================================
-- LEVEL & XP SYSTEM
-- ============================================================
Config.Level = {
	XP_PER_MINUTE = 8,
	XP_PER_CHAT = 6,
	CHAT_COOLDOWN = 4,
	XP_BASE = 25,
	XP_INCREMENT = 12,
	MAX_LEVEL = 100,
	ONLINE_INTERVAL = 10,
	SAVE_BATCH_SIZE = 2,
	-- Overhead row "03-Level" label format (%d = level number).
	OVERHEAD_TEXT = "Lv.%d",
}

-- ============================================================
-- SYNC DANCE
-- ============================================================
Config.Sync = {
	REMOTE_FOLDER = "SyncRemotes",
	REMOTE_ANIMATION_START = "animationStart",
	REMOTE_START_SYNC = "startSync",
	REMOTE_CHANGE_SPEED = "changeSpeed",
	REMOTE_UPDATE_FAVORITES = "updateFavoritedAnimationsEvent",
	REMOTE_SYNC_FAVORITES = "syncFavoritedAnimationsToClient",
	REMOTE_NOTIFICATION = "SyncNotification",
	REMOTE_VISUAL_STATE = "SyncVisualState",
	MAX_CHAIN_DEPTH = 100,
	MAX_PAYLOAD_BYTES = 512, -- Max payload size for sync remotes
	ANIM_PRIORITY = Enum.AnimationPriority.Action4,
	-- Natural transitions (owner request). Legacy used 0; raise if too sluggish.
	FADE_IN = 0.18,
	FADE_OUT = 0.14,
	SWITCH_FADE_IN = 0.22,
	SWITCH_FADE_OUT = 0.28,
	SYNC_JOIN_FADE_IN = 0.12,
	SWITCH_TRANSITION_LEAD_TIME = 0.06,
	DANCE_WALK_SPEED = 16,
	MIN_SPEED = 0,
	MAX_SPEED = 2.0,
	DEFAULT_SPEED = 1.0,
	SWITCH_INPUT_COOLDOWN = 0.15,
	WUTWUT_STOP_ARM_WINDOW = 0.24,
	WUTWUT_CHAIN_WINDOW = 0.32,
	WUTWUT_RESTART_FADE = 0,
	WUTWUT_MIN_REQUEST_INTERVAL = 0.05,
	WUTWUT_CLIENT_MIN_FIRE_INTERVAL = 0.04,
	-- Phase 1: legacy feel — asset preload on, mass track warmup stays off.
	DANCE_PRELOAD_ENABLED = true,
	-- When false: Cap ContentProvider PreloadAsync to MAX_ASSETS (tier1+tier2).
	-- When true: tier1 still uses budgets below for early isDanceReady; tier2/background
	-- PreloadAsync continues for the remainder of the catalog (content cache only —
	-- never mass LoadAnimation). Dense kits use more join bandwidth; batch/queue
	-- watermarks still throttle. Kill switch: set false to restore 32-asset envelope.
	DANCE_PRELOAD_FULL_CATALOG = true,
	-- Caps tier1/tier2 when FULL_CATALOG is false. With FULL_CATALOG, still clamps tier1 budget.
	DANCE_PRELOAD_MAX_ASSETS = 32,
	-- Phase 4: per-tier budgets inside MAX_ASSETS (tier1 ready signal + tier2 remainder).
	-- Kill switch: USE_LEGACY_FLAT_PRELOAD_BUDGET = true → flat MAX_ASSETS (pre-2.4.25).
	DANCE_PRELOAD_TIER1_BUDGET = 12,
	DANCE_PRELOAD_TIER2_BUDGET = 20,
	USE_LEGACY_FLAT_PRELOAD_BUDGET = false,
	-- Client: legacy DanceClientService-style LoadAnimation per asset ID (no mass trackCache).
	-- Disabled for 100 CCU: replaced by single once-per-session ContentProvider batch (perf-scaling R11).
	DANCE_CLIENT_LEGACY_STYLE_PRELOAD = false,
	DANCE_PRELOAD_READY_AFTER = 12,
	DANCE_LEGACY_PRELOAD_READY_AFTER = 24,
	DANCE_LEGACY_PRELOAD_YIELD_EVERY = 5,
	-- Sync join: snap follower phase from leader's live track (legacy SyncServerService).
	SYNC_JOIN_USE_LEADER_TRACK_TIME = true,
	DANCE_PRELOAD_DEVICE_AWARE = true,
	DANCE_PRELOAD_QUEUE_HIGH_WATERMARK = 30,
	DANCE_PRELOAD_QUEUE_PAUSE = 0.16,
	DANCE_PRELOAD_BATCH_SIZE_AGGRESSIVE = 12,
	DANCE_PRELOAD_BATCH_SIZE_BALANCED = 6,
	DANCE_PRELOAD_BATCH_SIZE_CONSERVATIVE = 3,
	DANCE_PRELOAD_BATCH_DELAY_AGGRESSIVE = 0.02,
	DANCE_PRELOAD_BATCH_DELAY_BALANCED = 0.06,
	DANCE_PRELOAD_BATCH_DELAY_CONSERVATIVE = 0.14,
	-- Keep off: mass track warmup duplicates Animation children under Animator (instance spike).
	DANCE_TRACK_WARMUP_ENABLED = false,
	SERVER_DANCE_TRACK_PREWARM_ENABLED = true,
	DANCE_TRACK_WARMUP_MAX = 64,
	DANCE_TRACK_WARMUP_MAX_AGGRESSIVE = 72,
	DANCE_TRACK_WARMUP_MAX_BALANCED = 48,
	DANCE_TRACK_WARMUP_MAX_CONSERVATIVE = 24,
	-- Server headroom: 10→8 tracks/character (client Animation RAM is driven by DANCE_PRELOAD_MAX_ASSETS).
	SERVER_DANCE_TRACK_PREWARM_MAX = 8,
	SERVER_DANCE_TRACK_PREWARM_BATCH_DELAY = 0.03,
	-- Phase 4: global admission — join wave must not LoadAnimation every character at once.
	SERVER_DANCE_TRACK_PREWARM_MAX_CONCURRENT = 2,
	SERVER_DANCE_TRACK_PREWARM_MAX_LOADS_PER_SEC = 24,
	-- Dance panel UI selection. Use "v1" for DancePanelGUIWrapper or "v2" for DancePanelGUIWrapperv2.
	-- Phone layout (short viewport + touch) uses DANCE_PANEL_UI_ROOTS.v2Mobile when USE_MOBILE_LAYOUT is true.
	DANCE_PANEL_UI_VERSION = "v2",
	DANCE_PANEL_USE_MOBILE_LAYOUT = true,
	DANCE_PANEL_UI_LABELS = {
		v1 = "Dance Panel",
		v2 = "Dance Panel V2",
		v2Mobile = "Dance Panel V2 Mobile",
	},
	DANCE_PANEL_UI_ROOTS = {
		v1 = "DancePanelGUIWrapper",
		v2 = "DancePanelGUIWrapperv2",
		v2Mobile = "DancePanelGUIWrapperv2Mobile",
	},
	-- IconGroup: panel v2 UIScale + 03-MainContentWrapper height (root IconGroup UIScale stays 1).
	DANCE_PANEL_V2_SCALE_MOBILE = 0.75,
	DANCE_PANEL_V2_SCALE_DESKTOP = 0.9,
	DANCE_MAIN_CONTENT_WRAPPER_HEIGHT_MOBILE = 270,
	DANCE_MAIN_CONTENT_WRAPPER_HEIGHT_DESKTOP = 330,
	TRIGGER_ATTRIBUTE = "OpensDancePanel",
	TRIGGER_BUTTON_NAMES = {
		"DanceButton",
		"SyncDanceButton",
		"OpenDancePanelButton",
		"DancePanelButton",
		"EmoteButton",
	},
}
Config.Favorites = {
	DATASTORE_NAME = scopedDataStoreKey("FavoritedAnimations_v2"),
	KEY_PREFIX = "Player_",
	ATTRIBUTE_KEY = "SavedFavoritedAnimations",
	-- Full favorites JSON dump (not command payloads). Security.MAX_PAYLOAD_BYTES
	-- stays 1KB for commands; DataStore allows far more than this.
	MAX_PAYLOAD_BYTES = 32 * 1024, -- 32KB ≈ 1k–1.5k short anim names
}
Config.SyncRateLimit = {
	ANIM_START = { max = 5, window = 2 },
	WUTWUT_RESTART = { max = 20, window = 2 },
	SYNC_REQUEST = { max = 10, window = 5 },
	SPEED_CHANGE = { max = 20, window = 2 },
	FAVORITES_UPDATE = { max = 15, window = 5 }, -- was 5/5s; too tight for rapid star toggles
}
-- ============================================================
-- CARRY SYSTEM (6 styles — weld, offsets, animations)
-- ============================================================
Config.Carry = {
	GUI_NAME = "08-CarryGUI",
	REMOTE_FOLDER = "CarryRemotes",
	COMMAND_REMOTE = "CarryCommand",
	NOTIFY_REMOTE = "CarryNotify",
	DEBUG_REMOTE = "CarryDebug",
	DEBUG_CALIBRATION_ENABLED = true,
	DEBUG_CALIBRATION_ALLOWED_USER_IDS = {} :: { [number]: boolean },
	REQUEST_TIMEOUT = 10,
	MAX_DISTANCE = 30,
	WELD_NAME = "CarryWeld",
	PHYSICS = {
		SET_NETWORK_OWNER = true,
		ATTACH_PART = "UpperTorso",
		-- Carried BaseParts (incl. HRP): Massless + CanCollide false while welded.
		-- Carrier JumpPower/WalkSpeed left unchanged so jump/dance stay normal.
	},
	DISPLAY_ORDER = 70,
	PANEL_TWEEN_TIME = 0.22,
	STYLE_ORDER = {
		"Piggyback",
		"Bridal",
		"Hug",
		"Tandem",
		"Fireman",
		"Choke",
	},
	STYLES = {
		Piggyback = {
			displayName = "Piggyback",
			offset = { 0, 0.6, 1.04 },
			rotation = { 0, 0, 0 },
			inverse = false,
			animations = { carrier = 100680878521066, carried = 134195163719419 },
		},
		Bridal = {
			displayName = "Bridal",
			offset = { -0.3, -0.3, -1 },
			rotation = { 90, -40, 80 },
			inverse = false,
			animations = { carrier = 108674288910239, carried = 121866484178761 },
		},
		Hug = {
			displayName = "Hug",
			offset = { 0, 0.6, -1.2 },
			rotation = { -25, 180, 0 },
			inverse = false,
			animations = { carrier = 137142302026916, carried = 127943982866081 },
		},
		Tandem = {
			displayName = "Tandem",
			offset = { 0, 2.5, 1.13 },
			rotation = { 0, 0, 0 },
			inverse = false,
			animations = { carrier = 75449515406553, carried = 89868439132766 },
		},
		Fireman = {
			displayName = "Fireman",
			offset = { 0, 0, 0 },
			rotation = { 0, 0, 0 },
			inverse = false,
			c0Kind = "fireman",
			animations = { carrier = 98708688263724, carried = 133752137189341 },
		},
		Choke = {
			displayName = "Choke",
			offset = { 0, 1.15, -1.7 },
			rotation = { -25, 180, 0 },
			inverse = false,
			animations = { carrier = 122051026974293, carried = 109898535522217 },
		},
	},
	RATE_LIMITS = {
		REQUEST = { max = 5, window = 5 },
		ACCEPT = { max = 8, window = 5 },
		REJECT = { max = 8, window = 5 },
		END = { max = 10, window = 5 },
	},
}
-- ============================================================
-- HOTBAR / INVENTORY
-- ============================================================
Config.Hotbar = {
	GUI_NAMES = {
		"10-HotbarGUI",
		"HotbarGUI",
	},
	HOTBAR_WRAPPER_NAME = "HotbarWrapper",
	HOTBAR_CHROME_ROOT_NAME = "HotbarChromeRoot",
	STICKER_WRAPPER_NAME = "StickerButtonWrapper",
	STICKER_TRIGGER_NAME = "StickerPanelTrigger",
	MAX_SLOTS = 10,
	-- PhoneLayout uses this cap for hotbar slot count (club mobile layout).
	MAX_SLOTS_MOBILE = 7,
	DISPLAY_ORDER = 50,
	TOOL_ICON_ATTRIBUTE = "Icon",
	TOOL_DISPLAY_NAME_ATTRIBUTE = "DisplayName",
	TOOL_HANDLE_NAME = "Handle",
	-- Proximity scale on hotbar slots + Settings "Dock Zoom" STATE_B/C tuning.
	DOCK_ZOOM_ENABLED = false,
	MAGNIFIER_RADIUS = 96,
	MAGNIFIER_FALLOFF = 1.55,
	SMOOTHING = 18,
	ZINDEX_BUMP = 6,
	LABEL_SHOW_THRESHOLD = 0.18,
	-- true: drag-reorder hotbar and cross-drop with backpack; tap-to-equip unchanged.
	INVENTORY_DRAG_ENABLED = true,
	DRAG_REORDER_ENABLED = true,
	BACKPACK_BUTTON_NAME = "BackpackButton",
	REMOTE_TOOLS_SYNCED = "HotbarToolsSynced",
	REMOTE_TOOLS_REQUEST_SYNC = "HotbarToolsRequestSync",
	-- Client re-scan Backpack after spawn (role tools arrive after Overhead payload).
	TOOL_SYNC_REFRESH_DELAYS = { 0, 0.35, 1, 2, 4, 8, 12, 16, 20 },
	DRAG_START_THRESHOLD = 6,
	DRAG_OVERLAY_NAME = "RuntimeHotbarDragOverlay",
	DRAG_OVERLAY_DISPLAY_ORDER_OFFSET = 50,
	DRAG_LIFT_ZINDEX = 100,
	-- Lift scale during hotbar drag preview (HotbarUIBinder); not read by InventoryDragController.
	DRAG_LIFT_SCALE = 1.16,
	DRAG_PLACEHOLDER_TRANSPARENCY = 0.72,
	EMPTY_IMAGE = "",
	EQUIPPED_BACKGROUND_COLOR = Color3.fromRGB(255, 255, 255),
	DRAG_PLACEHOLDER_COLOR = Color3.new(0, 0, 0),
	STATE_A = {
		SCALE = 1.0,
		STROKE = 0.4,
		LABEL_TRANSPARENCY = 1,
	},
	STATE_B = {
		SCALE = 1.12,
		STROKE = 0.6,
		LABEL_TRANSPARENCY = 0.35,
	},
	STATE_C = {
		SCALE = 1.34,
		STROKE = 1,
		LABEL_TRANSPARENCY = 0,
	},
	-- Optional hotbar/inventory audit (chat command + WARN dumps). Off in production.
	AUDIT_COMMAND_ENABLED = false,
	AUDIT_COMMAND = "hotbaraudit",
	AUDIT_COMMAND_ALIASES = { "hotbaraudit", "hbaudit" },
}
-- ============================================================
-- BACKPACK GUI (custom inventory panel)
-- ============================================================
Config.Backpack = {
	GUI_NAME = "14-BackpackGUI",
	WRAPPER_NAME = "HotbarWrapper",
	SCROLL_NAME = "ScrollingFrame",
	ITEM_TEMPLATE_NAME = "Item",
	MAX_GRID_SLOTS = 48,
	GUI_SCALE_MOBILE = 0.9,
	GUI_SCALE_DESKTOP = 0.9,
}
Config.RoleTools = {
	ROOT_FOLDER = "Tools",
	GRANT_ATTRIBUTE = "KitRoleTool",
	SOURCE_ATTRIBUTE = "KitRoleToolSource",
	-- Diisi oleh RolesDomain.applyDerivedConfig (satu folder per role = chatTag).
	FOLDERS_BY_ROLE = {} :: { [string]: { string } },
	FOLDERS_BY_MEMBERSHIP = {} :: { [string]: { string } },
	FOLDER_PRIORITY = {} :: { [string]: number },
	ROYALE_SPENDER_FOLDER = "TOP ROBUX DONATOR",
	TOP_SPENDER_FOLDER = "TOP RUPIAH SPENDER",
	TOP_DONATE_FOLDER = "TOP ROBUX DONATOR",
}
-- ============================================================
-- STICKER SYSTEM
-- ============================================================
Config.Sticker = {
	GUI_NAME = "11-StickerSystemGUI",
	DISPLAY_ORDER = 60,
	BILLBOARD_GUI_NAME = "ShoulderStickerGUI",
	BILLBOARD_IMAGE_NAME = "Sticker",
	STICKER_IMAGE_ATTRIBUTE = "StickerImage",
	STICKER_CLEAR_ATTRIBUTE = "StickerClear",
	DATASTORE_NAME = scopedDataStoreKey("StickerCollection_v1"),
	KEY_PREFIX = "Player_",
	-- Shared pool: satu upload tampil di picker semua player (DataStore key terpisah dari Player_*).
	GLOBAL_POOL_KEY = "GlobalPool_v1",
	REMOTE_SET = "StickerSet",
	REMOTE_CLEAR = "StickerClear",
	REMOTE_ADD = "StickerAdd",
	REMOTE_REQUEST = "StickerRequest",
	REMOTE_SYNC = "StickerSync",
	REMOTE_READY_TIMEOUT = 10,
	MAX_COLLECTION_SIZE = 80,
	DEFAULT_COLLECTION = {
		"rbxassetid://84494880468556",
	},
	DEFAULT_ADORNEE_PRIORITY = {
		"UpperTorso",
		"Torso",
		"HumanoidRootPart",
		"Head",
	},
	BILLBOARD_SIZE = UDim2.new(2.5, 0, 1.5, 0),
	BILLBOARD_STUDS_OFFSET = Vector3.new(2.1, 1.8, 0),
	BILLBOARD_MAX_DISTANCE = 40,
	BILLBOARD_LIGHT_INFLUENCE = 1,
	IMAGE_TRANSPARENCY = 0,
	DISPLAY_DURATION_SECONDS = 5,
	-- Klik picker hanya tampilkan di pundak (session); DataStore hanya saat upload (ADD).
	PERSIST_SELECTION_ON_SET = false,
	PANEL_TWEEN_TIME = 0.22,
	PANEL_CLOSED_OFFSET = 32,
	MODAL_TWEEN_TIME = 0.18,
	MODAL_CLOSED_SCALE = 0.94,
	DEBUG = false,
	-- Rate limits per remote command (server-side, per player)
	RATE_LIMITS = {
		SET = { max = 8, window = 5 },
		CLEAR = { max = 8, window = 5 },
		ADD = { max = 5, window = 10 },
		REQUEST = { max = 3, window = 5 },
	},
}
-- ============================================================
-- STICKER BILLBOARD ANIMATION (client-side visual)
-- ============================================================
Config.StickerAnim = {
	-- Entrance (pop-in bounce)
	ENTRANCE_DURATION = 0.38, -- total entrance time (seconds)
	ENTRANCE_OVERSHOOT = 1.18, -- scale overshoot before settling to 1.0
	-- Exit (fade-out + scale down)
	EXIT_DURATION = 0.32,
	EXIT_SCALE = 0.7, -- final scale before hiding
	-- Idle float (sinusoidal Y offset)
	FLOAT_SPEED = 2.2, -- radians per second
	FLOAT_AMPLITUDE = 0.12, -- studs up/down
	-- Idle wobble (subtle rotation)
	WOBBLE_SPEED = 1.8, -- radians per second
	WOBBLE_AMPLITUDE = 2.5, -- degrees
	-- Sparkle particles on entrance
	SPARKLE_COUNT = 5,
	SPARKLE_SIZE_MIN = 10,
	SPARKLE_SIZE_MAX = 16,
	SPARKLE_DELAY_MAX = 0.2, -- stagger delay per sparkle
	SPARKLE_FADE_IN = 0.25,
	SPARKLE_HOLD = 0.3, -- hold visible before fading out
	SPARKLE_FADE_OUT = 0.35,
}
-- ============================================================
-- FEATURE FLAGS
-- ============================================================
Config.FeatureFlags = {
	STUDIO_GIFT_BYPASS = IS_STUDIO,
	SyncDanceEnabled = true,
	MusicPlayerEnabled = true,
	SettingsEnabled = true,
	HotbarEnabled = true,
	LoadingScreenEnabled = true,
	LevelSystemEnabled = true,
	ShopEnabled = true,
	CouplesEnabled = true,
	StickersEnabled = true,
	LeaderboardEnabled = true,
	DonationCashEnabled = true,
	DonationSaweriaEnabled = true,
	DonationRobuxEnabled = true,
	AfkGuardEnabled = true,
	GravityEnabled = true,
	PromptJoinCommunityOnLoadEnabled = true,
	-- Grant Tier1 (VIP) membershipBadge when player IsInGroup(Group.GROUP_ID). Default off.
	VipOnCommunityJoinEnabled = false,
	JoinGreetingsEnabled = true,
}
-- ============================================================
-- DEMO MODE
-- ============================================================
Config.Demo = {
	-- Master switch. When true, leaderboards use fake showcase data (friend list + fallbacks).
	-- Production: keep false. Toggle at runtime with /showcase on|off (owner).
	ENABLED = false,
	-- When true, showcase leaderboards use Group.OWNER_USER_ID only (owner + their friends).
	-- Ignores SOURCE_USER_ID, players in server, and fallback Profiles list.
	LEADERBOARD_USE_OWNER_ONLY = false,
	-- UserId whose friend list populates demo data. 0 = use first player who joins.
	SOURCE_USER_ID = 0,
	-- Random donation amount range (IDR / Bagi-Bagi)
	MIN_AMOUNT = 100000,
	MAX_AMOUNT = 10000000,
	-- Random Robux donation range
	ROBUX_MIN_AMOUNT = 100,
	ROBUX_MAX_AMOUNT = 50000,
	-- Entries per board
	LEADERBOARD_LIMIT = 10,
	-- Seconds before re-randomizing values
	REFRESH_INTERVAL = 300,
}
-- ============================================================
-- LOADING SCREEN
-- ============================================================
Config.Loading = {
	BOOTSTRAP_WAIT_TIMEOUT = 30,
	TEMPLATE_WAIT_TIMEOUT = 10,
	CONTROLLER_WAIT_TIMEOUT = 30,
	CONTROLLER_POLL_INTERVAL = 0.1,
	-- Minimum tampil setelah boot + overhead siap (bukan fake 30s tunggu).
	MINIMUM_DURATION = 2,
	MINIMUM_AFTER_READY = 1.5,
	SKIP_PROMPT_DELAY = 0,
	FALLBACK_FINISH_DELAY = 45,
	INITIAL_PROGRESS = 0.01,
	PROGRESS_PULSE_DURATION = 28,
	PROGRESS_PULSE_INTERVAL = 1 / 30,
	FINAL_HOLD_DURATION = 0.4,
	WATCHDOG_BUFFER = 2,
	PROGRESS_SMOOTH_SPEED = 3,
	CORE_TOPBAR_RETRY_COUNT = 30,
	CORE_TOPBAR_RETRY_INTERVAL = 0.1,
	COLOR_FADE_IN_DURATION = 1.5,
	COLOR_FADE_OUT_DURATION = 0.4,
	BLACKOUT_TO_LOADING_DELAY = 0.2,
	-- Soft intro before cinematic camera/dance (lighter join feel).
	-- Blank + centered Branding.LOGO_IMAGE + BlurEffect that clears with progress.
	INTRO_ENABLED = true,
	INTRO_MIN_DURATION = 5,
	INTRO_END_PROGRESS = 0.28,
	INTRO_BLUR_SIZE = 28,
	INTRO_LOGO_SIZE_PX = 160,
	INTRO_FADE_OUT_DURATION = 0.55,
	INTRO_LOGO_FADE_IN_DURATION = 0.45,
	TIPS_FADE_DELAY = 0.6,
	TIPS_FADE_DURATION = 0.7,
	GREETING_FADE_IN_DURATION = 0.45,
	GREETING_FADE_OUT_DURATION = 0.35,
	GREETING_VISIBLE_DURATION = 4.2,
	GREETING_FADE_GAP = 0.4,
	TIPS_CYCLE_DURATION = 8,
	CLICK_BLACKOUT_DURATION = 0.6,
	CLICK_REVEAL_DURATION = 1.4,
	WELCOME_DISMISS_FORMAT = "Welcome to the club, %s",
	-- PRIMARY_GREETING: diisi ConfigBootstrap dari ClubKitConfig.Branding.Greeting
	CINEMATIC = {
		BIND_NAME = "LoadingCinematicCamera",
		BIND_PRIORITY_OFFSET = 100,
		CFRAME_LERP = 5,
		FOV_LERP = 4,
		EASE_DURATION = 0.7,
		BREATHE_AMP = 0.006,
		FALLBACK_DISTANCE = 8,
		DEFAULT_FIELD_OF_VIEW = 70,
		ANIMATION_ID = "rbxassetid://78416657618448",
		HUMANOID_WAIT_TIMEOUT = 5,
		ANIMATOR_WAIT_TIMEOUT = 3,
		DANCE_STOP_FADE = 0.3,
	},
}
-- ============================================================
-- CLIENT BOOT (join performance)
-- ============================================================
Config.ClientBoot = {
	-- Cap parallel interactive inits so join does not stampede the main thread.
	MAX_CONCURRENT_INTERACTIVE = 2,
	MAX_CONCURRENT_POST_GAMEPLAY = 1,
	MAX_CONCURRENT_DEFERRED = 1, -- backward-compat alias for POST_GAMEPLAY
	-- Stagger ScreenGui restore after tap dismiss (avoid single-frame layout burst).
	GUI_RESTORE_BATCH_SIZE = 3,
	GUI_RESTORE_BATCH_DELAY = 0, -- 0 = one batch per deferred step
	-- Post-gameplay pacing (after tap dismiss, not loading bar 100%).
	POST_GAMEPLAY_MUSIC_ENGINE = true,
	POST_GAMEPLAY_DANCE_WARMUP = true,
	MUSIC_ENGINE_DELAY_AFTER_GAMEPLAY = 4,
	DANCE_TIER1_DELAY_AFTER_GAMEPLAY = 0.5,
	-- Start dance ContentProvider warm during loading (tier1), not only after dismiss.
	DANCE_WARMUP_DURING_LOADING = true,
	-- Keep loading finish gated until tier1 warm marks ready (with existing boot/overhead gates).
	HOLD_LOADING_FOR_DANCE_TIER1 = true,
	-- Backward-compat aliases (pre-lifecycle-gate names).
	DEFER_MUSIC_PLAYER = true,
	DEFER_DANCE_WARMUP = true,
	DANCE_WARMUP_IDLE_DELAY = 1.5,
	CLIENT_GAMEPLAY_READY_REMOTE = "ClientGameplayReady",
	GAMEPLAY_READY_SERVER_TIMEOUT = 15,
}
Config.Debug = {
	BOOT_PROFILE_MARKERS = false,
}
-- ============================================================
-- UI SFX
-- ============================================================
Config.UISFX = {
	-- Master switch buat hover & click UI SFX. Set false biar UI fully senyap.
	ENABLED = false,
	-- Ganti dengan asset id UI sound kamu.
	HOVER_SOUND_ID = "rbxassetid://132401905689089",
	CLICK_SOUND_ID = "rbxassetid://109847084382411",
	HOVER_VOLUME = 0.2,
	CLICK_VOLUME = 0.35,
	HOVER_PLAYBACK_SPEED = 1,
	CLICK_PLAYBACK_SPEED = 1,
	ROLLOFF_MAX_DISTANCE = 35,
}
-- Shared frosted backdrop for shop/gift/couple/donation/admin/music modals, etc.
Config.PanelBlur = {
	ENABLED = false, -- Lighting BlurEffect (berat); zoom kamera tetap jalan.
	SIZE = 36,
	FADE_IN = 0.32,
	FADE_OUT = 0.22,
	-- BackdropBlur GUI frames: lower = lebih gelap = terasa lebih frosted.
	MODAL_BACKDROP_TRANSPARENCY = 0.38,
}
-- ============================================================
-- SHOP SYSTEM
-- ============================================================
Config.Shop = {
	-- Self-buy = Game Pass (one-time). Gift = Developer Product (can repurchase).
	-- BUY_GAMEPASS_ID — PromptGamePassPurchase + UserOwnsGamePassAsync sync
	-- GIFT_ID         — PromptProductPurchase + ProcessReceipt
	-- BUY_ID          — legacy Developer Product self-buy (ProcessReceipt only; optional)
	PRODUCTS = {
		Tier1 = {
			BUY_GAMEPASS_ID = 0,
			GIFT_ID = 0,
			BUY_ID = 0,
		},
		Tier2 = {
			BUY_GAMEPASS_ID = 0,
			GIFT_ID = 0,
			BUY_ID = 0,
		},
		Tier3 = {
			BUY_GAMEPASS_ID = 0,
			GIFT_ID = 0,
			BUY_ID = 0,
		},
	},
	-- Source of truth katalog membership untuk Shop + Admin Giftcard
	CATALOG = {
		Tier1 = {
			name = Config.Membership.Tiers.Tier1.label,
			price = 1,
			image = "rbxassetid://84120496876687",
		},
		Tier2 = {
			name = Config.Membership.Tiers.Tier2.label,
			price = 100,
			image = "rbxassetid://84120496876687",
		},
		Tier3 = {
			name = Config.Membership.Tiers.Tier3.label,
			price = 500,
			image = "rbxassetid://84120496876687",
		},
	},
	-- Benefits per tier - setiap entry = 1 slide carousel
	-- { icon, title, description }
	BENEFITS = {
		Tier1 = {
			{
				icon = "rbxassetid://120181247918895",
				title = "2x faster level growth.",
				description = "Level up faster every session.",
			},
			{
				icon = "rbxassetid://120181247918895",
				title = "Exclusive " .. Config.Membership.Tiers.Tier1.label .. " chat badge.",
				description = "Stand out in every conversation.",
			},
			{
				icon = "rbxassetid://120181247918895",
				title = "Early access perks.",
				description = "Try rewards before everyone else.",
			},
		},
		Tier2 = {
			{
				icon = "rbxassetid://118196125326891",
				title = "Top 10% of players.",
				description = "Get noticed the moment you join.",
			},
			{
				icon = "rbxassetid://118196125326891",
				title = "Premium visual flair.",
				description = "Look sharper across the whole game.",
			},
			{
				icon = "rbxassetid://118196125326891",
				title = "Priority social status.",
				description = "Feel more exclusive at a glance.",
			},
		},
		Tier3 = {
			{
				icon = "rbxassetid://107629225021909",
				title = "Maximum prestige.",
				description = "Own the highest tier available.",
			},
			{
				icon = "rbxassetid://107629225021909",
				title = Config.Membership.Tiers.Tier3.label .. "-only identity.",
				description = "Carry the rarest membership vibe.",
			},
			{
				icon = "rbxassetid://107629225021909",
				title = "Ultimate flex tier.",
				description = "Built for the boldest players.",
			},
		},
	},
	-- Carousel animation
	CAROUSEL_INTERVAL = 3, -- detik per slide
	CAROUSEL_FADE_TIME = 0.3, -- durasi fade dasar (detik)
	CAROUSEL_STAGGER_TIME = 0.1, -- jeda antar elemen (icon -> title -> desc)
	CAROUSEL_SLIDE_OFFSET = 0.08, -- offset horizontal relatif terhadap parent
	-- Topbar
	TOPBAR_ORDER = 2, -- urutan di topbar (1 = paling kiri)
	-- Remote names
	REMOTE_GRANT = "ShopGrantNotif", -- Server -> Client setelah purchase berhasil
	REMOTE_GIFT_INIT = "ShopGiftPending", -- Client -> Server sebelum prompt gift purchase
	-- Gift pending timeout - kalau terlalu lama tidak jadi purchase, hapus pending
	GIFT_PENDING_TIMEOUT = 120,
	-- Durable gift intent (DataStore) — survives server restart until ProcessReceipt.
	GIFT_PENDING_PERSIST_TIMEOUT = 1800,
	GIFT_PENDING_DATASTORE_KEY = scopedDataStoreKey("ShopGiftPending_v1"),
	-- Rate limit untuk ShopGiftPending remote
	GIFT_RATE_MAX = 3,
	GIFT_RATE_WINDOW = 60,
	-- Timeout menunggu remote siap di client (detik)
	REMOTE_READY_TIMEOUT = 30,
	-- Delay antara shop panel tutup dan notif muncul (detik)
	NOTIF_SHOW_DELAY = 0.35,
}
-- ============================================================
-- GIFT SYSTEM GUI
-- ============================================================
Config.Gift = {
	-- GUI
	GUI_NAME = "03-GiftSystemGUI",
	TOPBAR_ORDER = 3,
	BLUR_SIZE = 36,
	BLUR_FADE_IN = 0.3,
	BLUR_FADE_OUT = 0.2,
	GIFT_PROMPT_DELAY = 0.3,
	-- UI constants (mengganti magic numbers di GiftUI)
	CARD_SELECTED_ALPHA = 0.8, -- transparansi card saat dipilih dari player list
	NOTIF_HIDE_DELAY = 0.25, -- delay (detik) sebelum notifWrapper benar-benar tersembunyi
	-- Rate limiting (/gift command)
	RATE_MAX = 5,
	RATE_WINDOW = 60,
	-- Tier aliases untuk /gift command
	TIER_ALIASES = {
		vip = "Tier1",
		vipmember = "Tier1",
		tier1 = "Tier1",
		vvip = "Tier2",
		vvipmember = "Tier2",
		tier2 = "Tier2",
		supreme = "Tier3",
		suprememember = "Tier3",
		elite = "Tier3",
		elitemember = "Tier3",
		exclusive = "Tier3",
		tier3 = "Tier3",
	},
	-- Pesan sistem /gift command
	MSG_RATE_LIMIT = "[Gift] Give it a moment before sending another gift.",
	MSG_NO_PERM = "[Gift] You do not have permission to send memberships.",
	MSG_NOT_FOUND = "[Gift] I could not find '%s' in this server.",
	MSG_INVALID = "[Gift] '%s' is not a tier. Use "
		.. string.lower(Config.Membership.Tiers.Tier1.label)
		.. ", "
		.. string.lower(Config.Membership.Tiers.Tier2.label)
		.. ", or "
		.. string.lower(Config.Membership.Tiers.Tier3.label)
		.. ".",
	MSG_SUCCESS = "[Gift] %s Membership sent to %s. Their active status is now %s.",
	MSG_UNGIFT = "[Gift] Removed %s from %s. Their active status is now %s.",
	MSG_UNGIFT_NONE = "[Gift] %s does not have an active %s gift.",
	MSG_QUERY_SHORT = "[Gift] Give me at least 3 letters, or use the full name.",
	MSG_AMBIGUOUS = "[Gift] '%s' matches a few people. Be more specific: %s.",
	MSG_ALREADY_HAS = "[Gift] %s already has %s or something higher.",
	MSG_SAVE_FAILED = "[Gift] Could not save the gift. Try again.",
	MSG_TARGET_GOT_GIFT = "[Gift] %s Membership just landed from %s. Your active status is now %s.",
	MSG_TARGET_GIFT_REMOVED = "[Gift] Your %s gift was removed. Your active status is now %s.",
	MSG_UNGIFT_USAGE = "[Gift] Try /ungift <player> <tier>.",
	-- Bulk /gift all <tier>
	ALL_TARGET_ALIAS = "all",
	MSG_ALL_USAGE = "[Gift] Try /gift all <tier> to gift everyone in the server.",
	MSG_ALL_NO_TARGETS = "[Gift] Nobody else is in the server to gift right now.",
	MSG_ALL_SUMMARY = "[Gift] Sent %s Membership to %d player(s). Skipped %d, failed %d.",
	MSG_ALL_NO_GRANTS = "[Gift] Nobody received %s Membership. Skipped %d, failed %d.",
	CMD_ALIAS_GIFT = "gift",
	CMD_ALIAS_UNGIFT = "ungift",
}
Config.Chat = {
	COUPLE_TAG_EMOJI = "💕",
}
-- Dynamic bubble offset above overhead (Attachment + BubbleChatConfiguration.AdorneeName).
Config.ChatBubble = {
	ENABLED = true,
	ADORNEE_NAME = "ClubKitChatBubble",
	-- Parent part for ClubKitChatBubble (HRP = stable, no head pitch; Head = legacy).
	ADORNEE_PART = "HumanoidRootPart",
	-- Small gap above top of overhead stack (studs). Bubble sits on Attachment.
	EXTRA_STUDS = 0,
	-- StudsOffset is billboard center; multiply measured height by this (0.5 = geometric top).
	HEIGHT_FACTOR = 0.25,
	-- Additive studs after formula (negative lowers bubble). Tunable live via /height nudge.
	-- Locked from live tune: /height -0.5 felt right above overhead stack.
	NUDGE_STUDS = -0.5,
	-- Fallback when AbsoluteSize not ready yet: contentPx * PX_TO_STUDS.
	PX_TO_STUDS = 0.018,
	MIN_STUDS = 0.5,
	MAX_STUDS = 6,
	-- Skip Attachment write when delta below this (studs).
	SKIP_DELTA_STUDS = 0.05,
	-- Client tune commands: /bh /height /bubbleheight (local preview only).
	TUNE_COMMAND_ENABLED = true,
}
Config.Community = {
	CMD_ALIAS_SET = "setcommun",
	CMD_ALIAS_CLEAR = "clearcommun",
	RATE_MAX = 5,
	RATE_WINDOW = 60,
	MSG_USAGE = "[Community] Try /setcommun <communityId>.",
	MSG_CLEAR_NONE = "[Community] No community badge is showing right now.",
	MSG_INVALID_ID = "[Community] That community ID does not look right.",
	MSG_NOT_MEMBER = "[Community] Join that community first, then try again.",
	MSG_NOT_FOUND = "[Community] I could not find '%s' in your communities.",
	MSG_AMBIGUOUS = "[Community] '%s' matches a few communities: %s.",
	MSG_RATE_LIMIT = "[Community] Give it a second before changing badges again.",
	MSG_SAVE_FAILED = "[Community] Could not save your badge. Try again.",
	MSG_SET_SUCCESS = "[Community] Your badge now shows %s.",
	MSG_CLEAR_SUCCESS = "[Community] Community badge removed. Clean look.",
	MSG_LOOKUP_FAILED = "[Community] Could not check your communities yet. Try again soon.",
	MSG_ALREADY_ACTIVE = "[Community] That community is already on your profile.",
	PRIMARY_FALLBACK_ENABLED = true,
}
Config.AfkGuard = {
	ENABLED = true,
	IDLE_WARN_SEC = 120,
	IDLE_THRESHOLD_SEC = 17 * 60,
	IDLE_TOLERANCE_SEC = 30,
	AUTO_REJOIN_RATE_MAX = 1,
	AUTO_REJOIN_RATE_WINDOW = 900,
	RETRY_DELAY_SEC = 30,
	MAX_RETRY = 1,
	SYNC_FALLBACK_TOP_LEADER = true,
	SYNC_REQUIRE_LEADER_DANCING = true,
	TELEPORT_PREFER_SAME_SERVER = true,
	TELEPORT_FALLBACK_NEW_SERVER = true,
	REMOTE_REQUEST = "AfkRejoinRequest",
	MSG_WARN = "[Session] You're AFK. Move to stay, or we'll rejoin you automatically.",
	MSG_REJOINING = "[Session] AFK rejoin in progress...",
	MSG_REJOIN_FAILED = "[Session] AFK rejoin failed. Move your mouse to stay connected.",
	MSG_SYNC_RESTORED = "[Session] Synced back to %s.",
	MSG_SYNC_FALLBACK = "[Session] %s left — synced to %s.",
	MSG_SYNC_SOLO = "[Session] Rejoined. Dance sync could not be restored.",
	MSG_FALLBACK_SERVER = "[Session] Rejoined on a new server — your friends may be on a different one.",
}
Config.Session = {
	CMD_ALIAS_REFRESH = "re",
	CMD_ALIAS_REJOIN = "rejoin",
	CMD_ALIAS_BRING = "bring",
	CMD_ALIAS_TO = "to",
	RATE_MAX = 10,
	RATE_WINDOW = 30,
	RESTORE_Y_OFFSET = 0,
	TELEPORT_Y_OFFSET = 3,
	TELEPORT_FORWARD_OFFSET = 4,
	-- Max seconds a /re in-flight lock may stick if CharacterAdded restore never finishes.
	REFRESH_LOCK_TIMEOUT = 12,
	-- Client reads this on CharacterRemoving to snapshot camera across LoadCharacter.
	PENDING_REFRESH_ATTRIBUTE = "ClubKitPendingCharacterRefresh",
	MSG_REFRESHING = "[Session] Refreshing your character.",
	MSG_REFRESH_BUSY = "[Session] Refresh already in progress — wait a moment.",
	MSG_REJOINING = "[Session] Rejoining this server and bringing your spot back.",
	MSG_RESTORE_FAILED = "[Session] I could not read your last position, so I stopped there.",
	MSG_REJOIN_FAILED = "[Session] Rejoin did not go through. Try again soon.",
	MSG_RATE_LIMIT = "[Session] Give it a second before trying again.",
	MSG_USAGE_REFRESH = "[Session] Just use /re.",
	MSG_USAGE_REJOIN = "[Session] Just use /rejoin.",
	MSG_USAGE_BRING = "[Teleport] Use /bring <player>.",
	MSG_USAGE_TO = "[Teleport] Use /to <player>.",
	MSG_TELEPORT_NO_PERM = "[Teleport] This command is " .. Config.Membership.Tiers.Tier3.label .. "-only and above.",
	MSG_TELEPORT_SELF = "[Teleport] Pick another player.",
	MSG_TELEPORT_TARGET_NOT_READY = "[Teleport] That player is not ready yet.",
	MSG_TELEPORT_SUCCESS_BRING = "[Teleport] Brought %s to you.",
	MSG_TELEPORT_SUCCESS_TO = "[Teleport] Moved you to %s.",
}
-- ============================================================
-- GRAVITY / UNGRAVITY — server-wide float (staff+ only)
-- /ungravity = float ALL players, /gravity = restore ALL
-- Keybinds: Shift+U float, Shift+G restore (same permission gate)
-- ============================================================
Config.Gravity = {
	REMOTE_FOLDER = "GravityRemotes",
	COMMAND_REMOTE = "GravityCommand",
	CMD_ALIAS = "gravity",
	CMD_ALIAS_UNGRAVITY = "ungravity",
	DEFAULT_SPEED = 3,
	MIN_SPEED = 1,
	MAX_SPEED = 10,
	FLOAT_SPEED_AT_MIN = 3,
	FLOAT_SPEED_AT_MAX = 18,
	-- Saat /gravity: kick ke bawah (studs/s) supaya tidak "ngambang" dulu.
	RESTORE_DOWNWARD_VELOCITY = -45,
	RESTORE_HORIZONTAL_DAMP = 0.35,
	RATE_MAX = 12,
	RATE_WINDOW = 5,
	MSG_USAGE = "[Gravity] Staff only. /ungravity or /ungravity 1-10 = float everyone. /gravity or Shift+G = restore. Shift+U = float.",
	MSG_STATUS = "[Ungravity] Server floating at speed %d. Use /gravity or Shift+G to restore.",
	MSG_ENABLED = "[Ungravity] Everyone floating at speed %d.",
	MSG_DISABLED = "[Gravity] Gravity restored for everyone.",
	MSG_BLOCKED_CARRY = "[Ungravity] Cannot float while carrying or being carried.",
	MSG_RATE_LIMIT = "[Gravity] Slow down — try again in a moment.",
	MSG_INVALID_SPEED = "[Ungravity] Speed must be a number from 1 to 10.",
	MSG_NO_PERM = "[Gravity] Only Owner / Leadership (admin panel) can use this.",
}
-- ============================================================
-- ADMIN PANEL
-- ============================================================
Config.Admin = {
	GUI_NAME = "04-AdminPanelv2",
	GUI_NAME_CANDIDATES = { "04-AdminPanelv2", "04-AdminPanel" },
	GUI_WAIT_TIMEOUT = 30, -- timeout WaitForChild GUI (detik)
	GUI_SCALE_BAKED = 0.82,
	GUI_SCALE_MOBILE = 0.54,
	GUI_SCALE_DESKTOP = 0.84,
	TOPBAR_ORDER = 3,
	REMOTE_SET_TITLE = "AdminSetTitle",
	REMOTE_SEND_GIFTCARD = "AdminSendGiftcard",
	REMOTE_GIFTCARD_RESULT = "AdminGiftcardResult", -- Server->Client setelah grant
	REMOTE_RESET_TITLE = "AdminResetTitle",
	RATE_MAX = 5,
	RATE_WINDOW = 30,
	TITLE_MAX_LENGTH = 32,
	TITLE_PRESET_COUNT = 33,
	TITLE_FONTS = {
		-- Bold / display
		"GothamBold",
		"GothamBlack",
		"ArimoBold",
		"Bangers",
		"LuckiestGuy",
		"Oswald",
		"DenkOne",
		"Sarpanch",
		-- Playful
		"FredokaOne",
		"Cartoon",
		"ComicNeueAngular",
		"PatrickHand",
		"IndieFlower",
		"Kalam",
		"AmaticSC",
		-- Retro / tech
		"PressStart2P",
		"Arcade",
		"SciFi",
		"Michroma",
		"Jura",
		"Codystar",
		-- Handwritten / marker
		"PermanentMarker",
		"Fondamento",
		"SpecialElite",
		-- Serif / elegant
		"Bodoni",
		"Garamond",
		"Merriweather",
		-- Gothic / edgy
		"Creepster",
		"GrenzeGotisch",
		-- Clean modern
		"Roboto",
		"RobotoCondensed",
		"SourceSansBold",
		"JosefinSans",
		"TitilliumWeb",
		"Ubuntu",
		-- Distinctive
		"Highway",
	},
	TITLE_SIZE_ORDER = { "S", "M", "L", "XL", "XXL" },
	TITLE_SIZE_HEIGHT_SCALE = {
		S = 0.075,
		M = 0.095,
		L = 0.115,
		XL = 0.135,
		XXL = 0.155,
	},
	TITLE_SIZE_TEXT_SCALE = {
		S = 0.82,
		M = 1.0,
		L = 1.14,
		XL = 1.28,
		XXL = 1.42,
	},
	-- Title color preset on overhead custom title (lower speed = slower, more flowing motion).
	TITLE_PRESET_SPEED = 0.42,
	TITLE_PRESET_SIZE = 1.5,
	TITLE_PRESET_CARD_SPEED = 0.55,
	-- "Top" = title near top of overhead (name sort). "Stacked" = template layout order.
	DEFAULT_SPECIAL_TITLE_POSITION = "Top",
	TITLE_SUGGESTIONS = {
		"🍼 DEDE IMUP 🍼",
		"👑 KANJENG MAMI 👑",
		"🌴 BOS SAWIT 🌴",
		"💎 NYONYA MUDA 💎",
		"💼 CEO WIJAYA 💼",
		"🔥 BANDIT MADURA 🔥",
		"🤴 PRINCE 🤴",
		"🤴 KING 🤴",
		"👸 QUEEN ELISABETH 👸",
		"💃 LEAD DANCE 💃",
		"🎀 LEAD GEMOY 🎀",
		"✨ SPPG MPG ✨",
		"⚔️ KETUA PSHT ⚔️",
	},
	-- Messages - Gift
	MSG_GIFT_SUCCESS = "[Admin] %s Membership sent to %s.",
	MSG_GIFT_ALREADY_HAS = "[Admin] %s already has %s or something higher.",
	MSG_GIFT_FAILED = "[Admin] Could not save the gift. Try again.",
	MSG_GIFT_NO_PERM = "[Admin] This action is not available for your role.",
	MSG_GIFT_RATE_LIMIT = "[Admin] Give it a second before sending another one.",
	MSG_GIFT_INVALID_TIER = "[Admin] That tier is not available.",
	MSG_GIFT_NOT_FOUND = "[Admin] I could not find '%s'.",
	-- Messages - Set Title
	MSG_TITLE_NO_TARGET = "[Admin] Pick a player first.",
	MSG_TITLE_EMPTY = "[Admin] Give the title some text.",
	MSG_TITLE_TOO_LONG = "[Admin] That title is a bit too long.",
	MSG_TITLE_INVALID_SIZE = "[Admin] That title size is not available.",
	MSG_TITLE_INVALID_STYLE = "[Admin] That title style is not available.",
	MSG_TITLE_NOT_FOUND = "[Admin] I could not find '%s'.",
	MSG_TITLE_SAVE_FAILED = "[Admin] Could not save the title. Try again.",
	MSG_TITLE_SUCCESS = "[Admin] %s has a fresh title now.",
	MSG_TITLE_RESET_SUCCESS = "[Admin] %s is back to the default title.",
	MSG_TITLE_RESET_NOT_FOUND = "[Admin] I could not find '%s'.",
	-- AdminService retry config (client-side)
	RETRY_MAX_ATTEMPTS = 3,
	RETRY_BACKOFF = { 2, 4, 8 }, -- detik backoff per attempt
	NETWORK_TIMEOUT = 5, -- detik timeout per attempt
	-- Confirmation dialog
	CONFIRM_GIFT_TITLE = "Confirm Gift",
	CONFIRM_GIFT_MESSAGE = "Are you sure you want to send %s Membership to %s?",
	CONFIRM_YES = "Yes",
	CONFIRM_NO = "No",
}
-- ============================================================
-- UI SHADOW
-- ============================================================
Config.UIShadow = {
	ENABLED = false,
	STREAK_GLOW = {
		BlurRadius = UDim.new(0, 40),
		Offset = UDim2.fromOffset(0, 0),
		Spread = UDim2.new(0, 10, 0, 10),
		Transparency = 0.3,
		PulseMin = 0.45,
		PulseMax = 0.15,
	},
	OVERHEAD_TEXT = {
		BlurRadius = UDim.new(0, 7),
		Offset = UDim2.fromOffset(2, 3),
		Spread = UDim2.new(0, 0, 0, 0),
		Color = Color3.fromRGB(0, 0, 0),
		Transparency = 0.24,
	},
	STREAK_COLORS = {
		normal = Color3.fromRGB(255, 140, 30),
		milestone = Color3.fromRGB(255, 60, 60),
		reset = Color3.fromRGB(120, 120, 120),
	},
}
-- ============================================================
-- AVATAR CONTEXT MENU
-- ============================================================
Config.AvatarContext = {
	-- Rate limits
	REQUEST_RATE_MAX = 5,
	REQUEST_RATE_WINDOW = 10, -- seconds
	LIKE_RATE_MAX = 6,
	LIKE_RATE_WINDOW = 10,

	BIO_UPDATE_COOLDOWN = 60, -- seconds
	STATUS_UPDATE_COOLDOWN = 60, -- seconds

	-- Text limits
	BIO_MAX_LENGTH = 80,
	STATUS_MAX_LENGTH = 50,

	-- Cache
	SOCIAL_PROOF_CACHE_TTL = 300, -- 5 minutes
	-- Rate limiting for GetFriendsAsync calls (avoid saturating API)
	SOCIAL_PROOF_RATE_LIMIT = 30, -- max fetches per window
	SOCIAL_PROOF_RATE_WINDOW = 60, -- rate limit window in seconds

	-- Viewport pool: pre-warm all players + local player for instant 3D preview.
	-- Pool size 15 cukup untuk proximity 30 studs di 100 CCU (rata-rata 5-10
	-- player terlihat, 15 memberikan headroom untuk spawn baru + LRU protection).
	VIEWPORT_POOL_SIZE = 15,
	VIEWPORT_PREWARM_SELF = true,

	-- Timeouts
	REQUEST_TIMEOUT = 15, -- seconds (parallel fetch ~2-4s, buffer untuk network lambat)
	BUILD_DEADLINE = 5, -- seconds: max wait for parallel ACM fetches on server

	-- 3D Avatar
	AUTO_ROTATE_SPEED = 30, -- degrees per second
	CAMERA_DISTANCE = 6,
	CAMERA_HEIGHT = 1,
	CAMERA_FOV = 40,

	-- DataStore
	PROFILE_DATASTORE_KEY = scopedDataStoreKey("Profile_v1"),
	LIKE_DATASTORE_KEY = scopedDataStoreKey("AvatarLikes_v1"),
	LIKE_SHARD_COUNT = 128,

	-- Remote names
	REMOTE_REQUEST = "AvatarContextRequest",
	REMOTE_RESPONSE = "AvatarContextResponse",
	REMOTE_PROFILE_UPDATED = "ProfileUpdated",
	REMOTE_UPDATED = "AvatarContextUpdated",
	REMOTE_LIKE_REQUEST = "AvatarContextLikeRequest",
	REMOTE_LIKE_RESULT = "AvatarContextLikeResult",
	REMOTE_LIKE_EFFECT = "AvatarLikeEffect",
	REMOTE_CLOSE = "AvatarContextClose",

	-- Commands
	CMD_SET_BIO = "setbio",
	CMD_CLEAR_BIO = "clearbio",
	CMD_SET_STATUS = "status",
	CMD_CLEAR_STATUS = "clearstatus",

	-- Messages
	MSG_BIO_SET = "[Profile] Bio is live.",
	MSG_BIO_CLEARED = "[Profile] Bio cleared.",
	MSG_STATUS_SET = "[Profile] Status set.",
	MSG_STATUS_CLEARED = "[Profile] Status cleared.",
	MSG_TOO_LONG = "[Profile] Keep it short: max %d characters.",
	MSG_RATE_LIMIT = "[Profile] Give it a moment before editing again.",
	MSG_SAVE_FAILED = "[Profile] Could not save that. Try again.",
	MSG_FILTER_FAILED = "[Profile] Roblox could not review that text yet. Try different wording.",
	MSG_LIKE_RATE_LIMIT = "[Profile] Give it a moment before liking again.",
	LIKE_NOTIF_MESSAGE = "[Profile] %s liked your profile.",
	-- World 3D like effect
	LIKE_EFFECT_RADIUS = 80,
	LIKE_HEART_COUNT = 12,
	LIKE_TRAVEL_TIME = 0.9,
	LIKE_HEART_IMAGE = "",
}
-- ============================================================
-- GAME DATA API (Cloudflare Worker)
-- ============================================================
Config.GameDataApi = {
	BASE_URL = "https://hazastudio-game-data-api.hazastudio.workers.dev",
	GAME_KEY = "clubkit",
	-- SECRET moved to Server/Secrets.luau (server-only, not replicated to clients)
	SECRET = "SET_VIA_SERVER_SECRETS",
	-- HTTP request timeout in seconds
	HTTP_TIMEOUT = 5,
	-- Production: Worker only. GetFriendsAsync pagination is dev/emergency fallback.
	ALLOW_GET_FRIENDS_FALLBACK = false,
	-- Feature flag: enable Worker-based group rank resolution (Open Cloud API).
	-- Set to false to disable without deploy (falls back to GroupService).
	GROUPS_ENDPOINT_ENABLED = true,
	-- Feature flag: Join Commun memberCount + thumbs via Worker /community (Open Cloud).
	-- Requires Secrets.GameDataApiSecret; without it the kit falls back to roproxy.
	COMMUNITY_ENDPOINT_ENABLED = true,
}
Config.CommandLibrary = {
	GUI_NAME = "CommandLibraryGUI",
	TOPBAR_LABEL = "",
	TOPBAR_ORDER = 2,
	REMOTE_EXECUTE = "CommandLibraryExecute",
	REMOTE_EXECUTE_RESULT = "CommandLibraryExecuteResult",
	REQUEST_RATE_MAX = 6,
	REQUEST_RATE_WINDOW = 10,
	INPUT_PLACEHOLDER = "input your command",
	NOT_FOUND_TEXT = "Command not found.",
	AUTOCOMPLETE_ACCEPT_KEY = Enum.KeyCode.Tab,
}
Config.Icons = {
	Topbar = {
		Menu = "rbxassetid://135193838429269",
		Settings = "rbxassetid://134937924523939",
		Shop = "rbxassetid://73049045961531",
		Gift = "rbxassetid://119219253317473",
		Couple = "rbxassetid://114074615085456",
		Admin = "rbxassetid://73598133071651",
		-- Gunakan placeholder yang lebih jelas daripada 0
		Command = "rbxassetid://70457204831369", -- Empty string = no icon (lebih jelas daripada rbxassetid://0)
		Music = "rbxassetid://109703706311990",
		Camera = "rbxassetid://131545412033411", -- Freecam / cinematic topbar (HP)
		Broadcast = "rbxassetid://101268994273611",
	},
	Admin = {
		-- Gunakan placeholder yang lebih jelas daripada 0
		CursorForbidden = "", -- Empty string = no icon
	},
	Avatar = {
		IdleR15 = "rbxassetid://507766388",
		IdleR6 = "rbxassetid://180435571",
	},
}
Config.CinematicDock.TOPBAR_ICON = Config.Icons.Topbar.Camera
-- ============================================================
-- TOPBAR MENU
-- ============================================================
Config.TopbarMenu = {
	GUI_NAME = "15-TopMenuGUI",
	DESKTOP_FRAME_NAME = "TopBarMenu",
	PHONE_FRAME_NAME = "TopBarMenuPhone",
	LABEL = "Menu",
	ORDER = 4,
	-- Inter (TopbarPlus IconLabel via styleTopbarPill / setTextFont)
	FONT_ASSET_ID = 12187365364,
	SHOP_LABEL = "Shop",
	GIFT_LABEL = "Gift",
	COUPLE_LABEL = "Couple",
	ADMIN_LABEL = "Admin",
	SETTINGS_LABEL = "Settings",
	BACKDROP_BLUR_NAME = "TopMenuUIBlur",
	BUTTONS = {
		COUPLE = "CoupleButton",
		GIFT = "GiftButton",
		DONATIONS = "DonationsButton",
		BROADCAST = "BroadcastButton",
		SHOP = "ShopButton",
		CINEMATIC_DOCK = "CinematicDockButton",
		PROFILE = "ProfileButton",
		SETTINGS = "SettingsButton",
		COMMUNITY = "CommunityButton",
	},
}
-- ============================================================
-- SETTINGS MENU
-- ============================================================
Config.Graphics = {
	-- CollectionService tags (Studio): venue VFX / geometry that respect graphics presets.
	SCALABLE_VFX_TAG = "ScalableVfx",
	SCALABLE_GEOMETRY_TAG = "ScalableGeometry",
	-- Direct Workspace child folder names when ScalableGeometry tags are not set yet.
	-- Never scans full Workspace. Empty = skip venue geometry pass (safe, no CPU spike).
	-- Example: { "Map", "Club", "Venue" }
	GEOMETRY_FALLBACK_ROOT_NAMES = {},
	WORKSPACE_VFX_RATE = {
		-- Low should still keep some ambience; do not hard-disable everything.
		Off = 0.2,
		Reduced = 0.55,
		Full = 1,
	},
	ORIGINAL_PARTICLE_RATE_ATTRIBUTE = "RuntimeSettingsOriginalParticleRate",
	ORIGINAL_LIGHT_RANGE_ATTRIBUTE = "RuntimeSettingsOriginalLightRange",
	ORIGINAL_POSTFX_ENABLED_ATTRIBUTE = "RuntimeSettingsOriginalPostFxEnabled",
	DONATION_EFFECT_NAME_PREFIX = "HazastudioDonationEffect_",
}
Config.Settings = {
	GUI_NAME = "07-MenuGUI",
	BACKDROP_BLUR_NAME = "SettingsUIBlur",
	DATASTORE_KEY = scopedDataStoreKey("Settings_v1"),
	REMOTE_REQUEST = "SettingsRequest",
	REMOTE_SYNC = "SettingsSync",
	REMOTE_UPDATE = "SettingsUpdate",
	REMOTE_RESET = "SettingsReset",
	UPDATE_RATE_MAX = 10,
	UPDATE_RATE_WINDOW = 10,
	-- Full settings blob (overhead maps + graphicsOverrides). Security.MAX_PAYLOAD_BYTES
	-- is 1KB for short commands and rejects legitimate SettingsUpdate saves.
	MAX_PAYLOAD_BYTES = 8 * 1024,
}
Config.ProfileMenu = {
	REMOTE_REQUEST = "ProfileMenuRequest",
	REMOTE_SYNC = "ProfileMenuSync",
	REMOTE_UPDATE = "ProfileMenuUpdate",
	DISPLAY_NAME_MAX_LENGTH = 24,
	MSG_DISPLAY_NAME_TOO_LONG = "[Profile] Keep the display name short and clean.",
	MSG_TITLE_EMPTY = "[Profile] Your custom title cannot be empty.",
	MSG_TITLE_TOO_LONG = "[Profile] That custom title is a bit too long.",
	MSG_TITLE_LOCKED = "[Profile] You do not have a custom title to edit yet.",
	MSG_SINGLE_DUMB = "[Profile] You are single dumb.",
}
-- ============================================================
-- DONATION / BAGI-BAGI INTEGRATION
-- ============================================================
Config.Donation = {
	GUI_NAME = "09-DonationSystemGUI",
	-- Perf-scaling R7: route every OrderedDataStore IncrementAsync (community/user/adjust) through
	-- BudgetGate (2 credits each) with donationId idempotency. Flip to false to roll back to direct calls.
	ENABLE_GATED_INCREMENTS = true,
	-- Budget protection: minimum SetIncrementAsync budget required before processing a donation.
	-- Each donation consumes ~10 credits (receipt + leaderboard + metadata + overhead).
	-- When budget is below this threshold, donation writes are refused and retried on next poll.
	-- Set to 0 to disable (not recommended at 150+ CCU).
	MIN_BUDGET_FOR_DONATION = 8,
	TOPBAR_LABEL = "Donate",
	TOPBAR_ORDER = 4,
	PROVIDER_KEY = "bagibagi",
	PROVIDER_NAME = "Bagibagi",
	PROVIDER_DONOR_LABEL = "nama Bagibagi",
	PROVIDER_LINK = "", -- REPLACE: e.g. "https://bagibagi.co/yourname"
	BAGIBAGI_LINK = "", -- REPLACE: same as PROVIDER_LINK
	SAWERIA_LINK = "", -- legacy alias (Saweria kit templates)
	REMOTE_ROBUX_INIT = "DonationRobuxPending",
	REMOTE_ROBUX_RESULT = "DonationRobuxResult",
	REMOTE_ROBUX_PRODUCTS = "DonationRobuxProducts",
	REMOTE_ROBUX_PRODUCTS_RESPONSE = "DonationRobuxProductsResponse",
	REMOTE_DONOR_PROFILE = "DonationDonorProfile",
	REMOTE_DONOR_PROFILE_RESPONSE = "DonationDonorProfileResponse",
	DONOR_PROFILE_CACHE_TTL = 45,
	DONOR_PROFILE_RANK_LOOKUP_LIMIT = 100,
	-- Phase 3: Skip API call ke donor_profile untuk player yang belum pernah donasi.
	-- Marked as known donor via: notif broadcast, manual adjustment, atau cash stats > 0.
	-- Set false untuk force API call setiap refresh (debugging / new data import).
	SKIP_API_FOR_UNKNOWN_DONORS = true,
	-- 30s: matches Leaderboards timeout. Donation Robux init dan products
	-- response also yields through external HTTP + DataStore on cold start.
	REMOTE_REQUEST_TIMEOUT = 30,
	ROBUX_PROMPT_DELAY = 0.25,
	ROBUX_PENDING_TIMEOUT = 120,
	ROBUX_MESSAGE_MAX_LENGTH = 120,
	ROBUX_PENDING_RATE_MAX = 6,
	ROBUX_PENDING_RATE_WINDOW = 60,
	ROBUX_PRODUCTS_RATE_MAX = 10,
	ROBUX_PRODUCTS_RATE_WINDOW = 30,
	-- Optional explicit Robux donation products (ClubKitConfig.Donation.RobuxProducts).
	-- When empty, server auto-loads Developer Products except shop membership IDs.
	ROBUX_PRODUCTS = {} :: { { ProductId: number, Name: string?, Price: number? } },
	-- Hide creator Developer Products that are offsale (IsForSale ~= true) from donation panel.
	HIDE_OFFSALE_ROBUX_PRODUCTS = true,
	-- Extra ProductIds to hide from donation panel (PaidBroadcast is always excluded separately).
	EXCLUDED_ROBUX_PRODUCT_IDS = {} :: { number },
	-- Donation API base URL (Cloudflare Worker v2): https://host/game/{gameKey}
	-- REST routes live under {ApiUrl}/v2/*. Secret in Server/Secrets.luau only.
	SHEETS_WEB_APP_URL = "",
	LEGACY_SAWERIA_SEED = {},
	-- Polling interval leaderboard (detik) - jarang, karena leaderboard tidak perlu real-time
	-- Testing: 30 | Production: 120
	POLL_INTERVAL = 120,
	-- Polling interval notifikasi (detik) - CEPAT, ini yang mempengaruhi delay setelah bayar
	-- Semakin kecil = notif lebih cepat muncul, tapi lebih banyak HTTP request
	-- Min rekomendasi: 3s | Max: 30s
	NOTIF_POLL_INTERVAL = 15,
	-- Adaptive burst polling — wired via BackgroundJobScheduler:setInterval after each
	-- donation_poll completes (idle = NOTIF_POLL_INTERVAL; hot = NOTIF_BURST_INTERVAL).
	NOTIF_BURST_INTERVAL = 5, -- detik polling saat burst mode (setelah donasi terdeteksi)
	NOTIF_BURST_WINDOW = 45, -- detik sebelum kembali ke NOTIF_POLL_INTERVAL normal
	-- Client: when pending queue is at least half full, shorten notif display (no drops).
	NOTIF_BACKLOG_DISPLAY_SCALE = 0.6,
	-- Backoff saat endpoint error beruntun (exponential, lebih kecil agar recovery cepat)
	NOTIF_FAILURE_BACKOFF_STEP = 5, -- base delay per failure step (detik)
	NOTIF_FAILURE_BACKOFF_MAX = 20, -- cap maksimum backoff (detik)
	-- Retry sekali sebelum dihitung failure - handle transient Worker errors
	-- Worker cold start biasanya <1s, tapi retry tetap berguna untuk network hiccups
	NOTIF_RETRY_ENABLED = true,
	NOTIF_RETRY_DELAY = 2, -- detik tunggu sebelum retry (Worker lebih cepat dari GAS)
	-- HTTP request timeout (detik) - dinaikin dari 10 ke 20 karena query notifikasi
	-- perlu waktu untuk full table scan pertama (index baru jalan setelah fix query)
	HTTP_TIMEOUT = 20,
	-- Keep-warm ping - optional untuk Worker (Worker tidak memiliki cold start seperti GAS)
	-- Bisa dinonaktifkan jika menggunakan Cloudflare Worker (selalu warm)
	KEEP_WARM_ENABLED = false,
	KEEP_WARM_INTERVAL = 240, -- 4 menit - legacy dari GAS, tidak diperlukan untuk Worker
	-- DataStore throttle lockout (P0): saat DataStoreService emit StandardReadExperienceThrottled
	-- atau OrderedListExperienceThrottled, semua DS-bound ops (repo:getRobuxLeaderboard,
	-- recordRobuxDonation, dll) short-circuit dan return Err("ds_throttled") selama detik ini.
	-- Caller fall back ke TTL cache. 60s cukup untuk Roblox BudgetGate re-budget.
	DATASTORE_THROTTLE_COOLDOWN = 60,
	-- Minimum jumlah donasi (Rupiah) untuk diproses notif/leaderboard
	MIN_AMOUNT = 1000,
	-- Jumlah entry leaderboard yang di-track
	LEADERBOARD_LIMIT = 10,
	-- Remote names
	REMOTE_NOTIFICATION = "DonationNotification",
	REMOTE_LEADERBOARD_UPDATED = "DonationLeaderboardUpdated",
	-- Slim signal on DonationLeaderboardUpdated (revision only); set false to rollback full table broadcast.
	SHEETS_REFRESH_SIGNAL_ONLY = true,
	REMOTE_ADMIN_COMMAND = "DonationAdminCommand",
	-- Legacy overhead row "05-TopSpender" (#N INVESTOR). Off = pakai 00-DonationLayers saja.
	SHOW_LEGACY_TOP_SPENDER_ROW = false,
	-- External donation top spender display text (05-TopSpender row, hanya jika SHOW_LEGACY_TOP_SPENDER_ROW).
	TOP_SPENDER_TEXTS = {
		[1] = "#1 INVESTOR",
		[2] = "#2 INVESTOR",
		[3] = "#3 INVESTOR",
		[4] = "#4 INVESTOR",
		[5] = "#5 INVESTOR",
		[6] = "#6 INVESTOR",
		[7] = "#7 INVESTOR",
		[8] = "#8 INVESTOR",
		[9] = "#9 INVESTOR",
		[10] = "#10 INVESTOR",
	},
	-- Tambahan nilai manual (delta), di-merge ke leaderboard utama saat poll/refresh.
	-- Persisted via ManualBagibagiRepository (DataStore). Runtime cache di MANUAL_BAGIBAGI_ADJUSTMENTS.
	MANUAL_BAGIBAGI_DATASTORE_KEY = scopedDataStoreKey("ManualBagibagiAdjustments_v1"),
	-- Robux: increment OrderedDataStore (scoped via DataStoreScope — Studio_* when isolated).
	MANUAL_ROBUX_ADJUSTMENTS = {} :: { [number]: number },
	MANUAL_BAGIBAGI_ADJUSTMENTS = {} :: { [number]: number },
	MSG_STUDIO_LIVE_DATASTORE_BLOCKED = "[Donation] Studio writes live DataStore keys (USE_STUDIO_DATASTORE_ISOLATION=false). /setrobux is blocked; use /removerobux to clear live totals, or set isolation=true for Studio_* sandbox.",
	-- Owner-only manual donation commands (Studio bypass permission check).
	CMD_ADD_ROBUX = "setrobux", -- /setrobux <username|userId> <robux amount>
	CMD_REMOVE_ROBUX = "removerobux", -- /removerobux <username|userId|me> [robux]; `me` = clear self (Studio only)
	CMD_TEST_CASH = "testcash", -- /testcash <idr amount> (admin test preview: notif + aura + world VFX, no persist)
	CMD_DONATE_CASH = "donatecash", -- /donatecash <username|userId> <idr> [message]
	CMD_ADD_CASH = "addcash", -- /addcash <username|userId> <idr amount> (leaderboard only)
	CMD_REMOVE_CASH = "removecash", -- /removecash <username|userId|me> [idr]; `me` = clear self (Studio only)
	CMD_ADD_BAGIBAGI = "addbagibagi", -- legacy alias → addcash
	CMD_DONATE_BAGIBAGI = "donatebagibagi", -- legacy alias → donatecash
	CMD_REMOVE_BAGIBAGI = "removebagibagi", -- legacy alias → removecash
	CMD_SET_BAGIBAGI = "setbagibagi", -- legacy alias → addcash
	CMD_LIST_BAGIBAGI = "listbagibagi",
	CMD_LIST_ROBUX = "listrobux",
	CMD_LEGACY_ALIASES = {
		setbagibagi = "addcash",
		setspender = "addcash",
		donatebagi = "donatecash",
		donatebagi2 = "donatecash",
		donatebagibagi = "donatecash",
		addbagibagi = "addcash",
		removebagibagi = "removecash",
		testsaweria = "testcash",
		testdonate = "testcash",
		dumpsaweria = "dumpbagibagi",
	} :: { [string]: string },
	-- Admin commands
	CMD_LINK_DONOR = "linkdonor", -- /linkdonor <bagiBagiName> <robloxUsername>
	CMD_CLAIM_DONOR = "claimdonor", -- /claimdonor <bagiBagiName>
	-- Messages
	MSG_LINK_SUCCESS = "[Donation] '%s' is now linked to %s.",
	MSG_LINK_NOT_FOUND = "[Donation] I could not find '%s' on the donor list.",
	MSG_LINK_NO_PERM = "[Donation] This action is not available for your role.",
	MSG_CLAIM_SUCCESS = "[Donation] '%s' claimed. Your overhead tag is updated.",
	MSG_CLAIM_NOT_FOUND = "[Donation] I could not find '%s', or it is already assigned.",
	MSG_CLAIM_RATE_LIMIT = "[Donation] You already claimed today. Come back tomorrow.",
	MSG_SHEETS_ERROR = "[Donation] Could not reach the donation server.",
	-- Rate limit claimdonor per player
	CLAIM_COOLDOWN = 86400, -- 24 jam (detik)
	-- SurfaceGui path di workspace (set setelah kamu buat Part-nya di Studio)
	-- Contoh: "Workspace.DonationBoard.SurfaceGui"
	LEADERBOARD_SURFACE_GUI_PATH = "",
	-- Notifikasi toast / notification center
	NOTIF_SHOW_DURATION = 20, -- detik sebelum auto-dismiss (sedikit lebih lama agar sempat dibaca)
	NOTIF_MAX_QUEUE = 20, -- max notif yang boleh antre di client
	NOTIF_SLIDE_DURATION = 0.45, -- durasi animasi masuk (detik)
	NOTIF_GAP_DURATION = 0.18, -- jeda antar notif agar transisi terasa terpisah
	WORKSPACE_RESTORE_DELAY = 60,
	-- CollectionService tag applied to Workspace roots that host donation SurfaceGuis.
	-- TagDonationDisplayRoots.server.luau applies this at runtime so the tag survives
	-- place reloads without a manual Studio Command Bar step.
	DISPLAY_ROOT_TAG = "DonationDisplayRoot",
	-- Workspace instance names searched when building WorkspaceSurfaceRefs.
	LIVE_CHAT_ROOT_NAME = "LiveChatDonations",
	RUNNING_TEXT_ROOT_NAME = "RunningText",
	-- Studio: set true + /donationRunningTextDebug (client) to print marquee layout each ~2s
	RUNNING_TEXT_DEBUG = false,
	-- Donation aura/effect assets live in ServerStorage.DonationEffects / DonationSounds.
	-- Folder structure: ServerStorage > DonationEffects (Model) > DonationEffects (Folder) > Level1..Level11
	-- Aura tier resolution (AURA_TIERS): highest `min` for Robux; idrMin..idrMax for Bagi-Bagi/Saweria.
	-- Konversi ~1 Robux = Rp 100. Robux cinematic mulai Level3 (80 Robux).
	ROBUX_EFFECTS_FOLDER = "DonationEffects",
	ROBUX_EFFECT_SOUNDS_FOLDER = "DonationSounds",
	-- World-position VFX (Rocket/Hammer/Blackhole) for Bagi-Bagi/Saweria only (WORLD_EFFECT_TIERS).
	-- Robux donations use per-player aura (AURA_TIERS) — no world VFX.
	-- Client plays via WorldEffectDispatch when donation notif starts showing.
	NUKE_REMOTE = "DonationEffect",
	-- Folder in ReplicatedStorage that holds the world-position VFX models
	-- (one Model per effect name: Nuke / Smite / BlackHole).
	NUKE_EFFECTS_FOLDER = "WorldEffects",
	-- Stage world position for Nuke / Smite / BlackHole EffectDonate VFX.
	-- Buyer override: ClubKitConfig.Donation.NukeWorldPosition → ConfigBootstrap.
	NUKE_WORLD_POSITION = Vector3.new(-262.2, 1.285, 64.9),
	-- Legacy: was used for server serial world-VFX queue pacing. Unused now —
	-- world effects follow donation notif show cadence (client WorldEffectDispatch).
	NUKE_DEFAULT_DURATION = 90,
	-- Legacy per-effect durations (unused for queue pacing).
	WORLD_EFFECT_DURATIONS = {
		Nuke = 90,
		Smite4 = 180,
		BlackHole = 240,
	},
	-- Saweria/Bagi-Bagi IDR thresholds for world VFX (highest match wins).
	-- Nuke = Rocket (100k–249k), Smite4 = Hammer (250k–499k), BlackHole = 500k+.
	WORLD_EFFECT_TIERS = {
		{ min = 500000, effect = "BlackHole" },
		{ min = 250000, effect = "Smite4" },
		{ min = 100000, effect = "Nuke" },
	},
	-- Unused: Robux path does not broadcast world VFX (aura only).
	ROBUX_NUKE_TIERS = {},
	-- Per-tier durations: `duration` covers aura/notif/cycle, `cameraDuration` is
	-- camera-specific (0 disables camera).
	AURA_TIERS = {
		{
			level = 1,
			min = 10,
			idrMin = 0,
			idrMax = 9999,
			effect = "Level1",
			sound = "Level1",
			duration = 4,
			cameraDuration = 0,
		},
		{
			level = 3,
			min = 80,
			idrMin = 10000,
			idrMax = 19999,
			effect = "Level3",
			sound = "Level3",
			duration = 4,
			cameraDuration = 0,
		},
		{
			level = 4,
			min = 150,
			idrMin = 20000,
			idrMax = 29999,
			effect = "Level4",
			sound = "Level4",
			duration = 4,
			cameraDuration = 0,
		},
		{
			level = 5,
			min = 250,
			idrMin = 30000,
			idrMax = 49999,
			effect = "Level5",
			sound = "Level5",
			duration = 5,
			cameraDuration = 0,
		},
		{
			level = 6,
			min = 500,
			idrMin = 50000,
			idrMax = 99999,
			effect = "Level6",
			sound = "Level6",
			duration = 5,
			cameraDuration = 6,
		},
		{
			level = 7,
			min = 1000,
			idrMin = 100000,
			idrMax = 199999,
			effect = "Level7",
			sound = "Level7",
			duration = 6,
			cameraDuration = 8,
		},
		{
			level = 8,
			min = 2000,
			idrMin = 200000,
			idrMax = 299999,
			effect = "Level8",
			sound = "Level8",
			duration = 6,
			cameraDuration = 7,
		},
		{
			level = 9,
			min = 3000,
			idrMin = 300000,
			idrMax = 499999,
			effect = "Level9",
			sound = "Level9",
			duration = 8,
			cameraDuration = 8,
		},
		{
			level = 10,
			min = 5000,
			idrMin = 500000,
			idrMax = 999999,
			effect = "Level10",
			sound = "Level10",
			duration = 8,
			cameraDuration = 8,
		},
		{
			level = 11,
			min = 10000,
			idrMin = 1000000,
			idrMax = math.huge,
			effect = "Level11",
			sound = "Level11",
			duration = 8,
			cameraDuration = 8,
		},
	},
	-- RoleBadge image per role (tampil di donation notif saat donator ada di server)

	ROLE_BADGE_IMAGE = {
		Owner = "rbxassetid://126866972878520",
		CoOwner = "rbxassetid://126866972878520",
		Developer = "rbxassetid://70692404618828",
		Admin = "rbxassetid://104368298266529",
		Tier3 = Config.Membership.Tiers.Tier3.badgeImage,
		ELITEMember = Config.Membership.Tiers.Tier3.badgeImage,
		Tier2 = Config.Membership.Tiers.Tier2.badgeImage,
		VVIPMember = Config.Membership.Tiers.Tier2.badgeImage,
		Tier1 = Config.Membership.Tiers.Tier1.badgeImage,
		VIPMember = Config.Membership.Tiers.Tier1.badgeImage,
		Member = Config.Membership.Tiers.Member.badgeImage,
	},
}
Config.Donation.ROBUX_EFFECT_TIERS = Config.Donation.AURA_TIERS
Config.Donation.SAWERIA_NUKE_TIERS = Config.Donation.WORLD_EFFECT_TIERS
Config.Leaderboards = {
	-- Server writes static text/images to Workspace SurfaceGuis (replicates to joiners).
	SERVER_PAINT_WORKSPACE = true,
	-- Client repaints on REMOTE_UPDATED (fallback when server paint ran before boards streamed in).
	CLIENT_PAINT_DATA = false,
	-- Client runs podium/gradient/daily motion only.
	CLIENT_PLAY_ANIMATIONS = true,
	-- Daily boards: Bagi-Bagi (Rupiah) only; DailyDonationsRobux SurfaceGui is not placed.
	DAILY_ROBUX_ENABLED = false,
	REVISION_ATTRIBUTE = "LeaderboardRevision",
	REMOTE_UPDATED = "WorkspaceLeaderboardsUpdated",
	REMOTE_SNAPSHOT = "WorkspaceLeaderboardsSnapshot",
	REMOTE_SNAPSHOT_RESPONSE = "WorkspaceLeaderboardsSnapshotResponse",
	-- 30s timeout: cold-start scenario stacks pre-warm + 2x GetSortedAsync +
	-- per-entry GetAsync metadata + Bagi-Bagi HTTP poll. 10s was tight enough
	-- that healthy cold boots tripped timeouts.
	REMOTE_REQUEST_TIMEOUT = 30,
	-- 60s: workspace payload only changes on donation events (handled via
	-- explicit invalidate in onLeaderboardUpdated). 10s caused near-constant
	-- cold rebuilds on each client snapshot request.
	WORKSPACE_CACHE_TTL = 60,
	-- Phase 4: coalesce donation-driven rebuild+paint (trailing window).
	-- Admin/manual refresh can still force immediate via scheduleWorkspace(immediate).
	WORKSPACE_REBUILD_COALESCE_SEC = 5,
	-- Skip paint when fingerprint unchanged (net was already skipped).
	SKIP_PAINT_WHEN_FINGERPRINT_UNCHANGED = true,
	-- Bound missing-board paint retries (board streamed late).
	PAINT_MISSING_RETRY_MAX = 3,
	PAINT_MISSING_RETRY_DELAY = 5,
	-- Delay sebelum kick-off pertama leaderboard refresh saat server start.
	-- Menghindari DataStore throttle dari burst reads di pre-warm + overhead init.
	INITIAL_REFRESH_DELAY = 30,
	SNAPSHOT_RATE_MAX = 2,
	SNAPSHOT_RATE_WINDOW = 15,
	ADMIN_REFRESH_RATE_MAX = 2,
	ADMIN_REFRESH_RATE_WINDOW = 30,
	CMD_REFRESH = "refreshleaderboard",
	CMD_SHOWCASE = "showcase",
	DEFAULT_LIMIT = 10,
	MAX_LIMIT = 100,
	-- Patch #2 R1: Unify robux leaderboard cache key. Sebelumnya ROBUX_LIMIT=10 dipakai
	-- untuk overhead top-donate, sedangkan DONOR_PROFILE_RANK_LOOKUP_LIMIT=100 dipakai
	-- untuk donor profile lookup — 2 limit = 2 cache key = 2x miss per invalidate.
	-- Set ke MAX_LIMIT supaya semua caller share satu cache entry (robux:100).
	ROBUX_LIMIT = 100,
	-- Workspace SurfaceGui rows painted (fetch may still use ROBUX_LIMIT for DS/cache).
	ROBUX_PAINT_LIMIT = 20,
	COMMUNITY_LIMIT = 10,
	SAWERIA_LIMIT = 10,
	LIKES_LIMIT = 50,
	LIKES_PAINT_LIMIT = 20,
	LIKES_BACKFILL_MAX_KEYS = 500,
	LIKES_BACKFILL_COOLDOWN = 300,
	ROBUX_USER_ORDERED_KEY = scopedDataStoreKey("RobuxDonationLeaderboard_User_v1"),
	ROBUX_COMMUNITY_ORDERED_KEY = scopedDataStoreKey("RobuxDonationLeaderboard_Community_v1"),
	METADATA_KEY = scopedDataStoreKey("DonationLeaderboardMetadata_v1"),
	RECEIPT_KEY = scopedDataStoreKey("DonationRobuxReceipts_v1"),
	LIKE_ORDERED_KEY = scopedDataStoreKey("AvatarLikesLeaderboard_v1"),
	-- P1: MemoryStoreService cross-server cache untuk leaderboard. Default ON
	-- karena MemoryStore quota lebih murah dari DataStore GetSortedAsync
	-- per-experience (10/min). Semua server share key yang sama dengan TTL
	-- 60s - drops N×servers GetSortedAsync jadi 1×60s untuk leaderboard miss.
	-- Fallback otomatis ke DataStore kalau MemoryStore error/disabled.
	MEMORY_STORE_CACHE_ENABLED = true,
	MEMORY_STORE_LEADERBOARD_TTL = 60,
	MEMORY_STORE_STORE_NAME = "ClubKitLeaderboardCache",
	-- Developer/test accounts: hidden dari leaderboard paint, overhead donation ranks,
	-- dan Robux OrderedDS (session-only di Shop). Kosongkan / comment ID saat testing di Studio.
	HIDDEN_ROBUX_USER_IDS = {
		-- [8842050215] = true, -- dev account; uncomment untuk sembunyikan dari board Robux
	} :: { [number]: boolean },
	MSG_REFRESH_USAGE = "[Leaderboard] Try /refreshleaderboard <robux|community|bagibagi|likes|all|audit>.",
	MSG_REFRESH_NO_PERM = "[Leaderboard] This command is owner-only.",
	MSG_REFRESH_OK = "[Leaderboard] Refresh requested for %s.",
	MSG_REFRESH_FAILED = "[Leaderboard] Refresh failed for %s.",
	MSG_SHOWCASE_USAGE = "[Showcase] Try /showcase <on|off|status>. Fake leaderboard data for screenshots.",
	MSG_SHOWCASE_NO_PERM = "[Showcase] This command is owner-only.",
	MSG_SHOWCASE_ON = "[Showcase] ON — leaderboards now use fake showcase data.",
	MSG_SHOWCASE_OFF = "[Showcase] OFF — leaderboards back to live data.",
	MSG_SHOWCASE_STATUS = "[Showcase] Mode is %s.",
	-- Workspace SurfaceGui loading chrome (LoadingOverlay + MainContentWrapper).
	LOADING_OVERLAY_NAME = "LoadingOverlay",
	MAIN_CONTENT_WRAPPER_NAME = "MainContentWrapper",
	DEFAULT_LOADING_MESSAGE = "Loading leaderboard",
	LOADING_TEXT_FADE_DURATION = 0.38,
	LOADING_TEXT_HOLD_DURATION = 2.4,
	LOADING_MESSAGES = {
		robux = "Fetching top Robux donors",
		community = "Fetching community rankings",
		saweria = "Fetching Bagi-Bagi donations",
		likes = "Fetching top likes",
	},
	LOADING_MESSAGE_CYCLES = {
		robux = { "Syncing donation data", "Almost ready" },
		community = { "Loading group rankings", "Almost ready" },
		saweria = { "Syncing donor data", "Almost ready" },
		likes = { "Updating rankings", "Almost ready" },
	},
	-- Top{1,2,3}{Cash,Robux} posters: hide CanvasGroup while loading (Wrapper alone can flash sibling frames).
	POSTER_CONTENT_ROOT_PATH = { "CanvasGroup" },
	POSTER_CONTENT_WRAPPER_PATH = { "CanvasGroup", "Wrapper" },
	DEFAULT_POSTER_LOADING_MESSAGE = "Loading poster",
	POSTER_LOADING_MESSAGES = {
		robux = "Loading top Robux poster",
		saweria = "Loading top donor poster",
	},
	POSTER_LOADING_CYCLES = {
		robux = { "Syncing top donor", "Almost ready" },
		saweria = { "Syncing rankings", "Almost ready" },
	},
	SAWERIA_WAITING_MESSAGES = {
		board = "Waiting for the first Bagi-Bagi donor",
		poster = "Waiting for the first donor",
	},
	SAWERIA_WAITING_CYCLES = {
		board = { "Leaderboard will appear here", "Be the first to donate" },
		poster = { "Poster will appear here", "Be the first to donate" },
	},
	-- Idle overlay when live data is empty, API missing, or fetch failed (not blank hide).
	EMPTY_STATE_MESSAGES = {
		board = {
			robux = "No Robux donors yet",
			community = "No community donations yet",
			likes = "No likes yet",
			saweria = "Waiting for the first Bagi-Bagi donor",
		},
		poster = {
			robux = "No top Robux donor yet",
			saweria = "Waiting for the first donor",
		},
	},
	EMPTY_STATE_CYCLES = {
		board = {
			robux = { "Leaderboard updates after the first purchase" },
			community = { "Community rankings will appear here" },
			likes = { "Like players to fill this board" },
		},
		poster = {
			robux = { "Poster updates after the first purchase" },
		},
	},
	NOT_CONFIGURED_MESSAGES = {
		board = {
			saweria = "Donation API not configured yet",
		},
		poster = {
			saweria = "Donation API not configured yet",
		},
	},
	NOT_CONFIGURED_CYCLES = {
		board = {
			saweria = { "Set Donation.ApiUrl in ClubKitConfig", "Add API secret in Secrets.luau" },
		},
		poster = {
			saweria = { "Configure donation API to enable posters" },
		},
	},
	ERROR_STATE_MESSAGES = {
		board = {
			default = "Could not load leaderboard",
			robux = "Could not load Robux leaderboard",
			community = "Could not load community leaderboard",
			likes = "Could not load likes leaderboard",
			saweria = "Could not load Bagi-Bagi leaderboard",
		},
		poster = {
			default = "Could not load poster",
			robux = "Could not load Robux poster",
			saweria = "Could not load donor poster",
		},
	},
	ERROR_STATE_CYCLES = {
		board = {
			default = { "Try again in a moment" },
		},
		poster = {
			default = { "Try again in a moment" },
		},
	},
}
-- ============================================================
-- MUSIC PLAYER
-- ============================================================
Config.Music = {
	-- GUI
	GUI_NAME = "06-MusicPlayerGUI",
	TOPBAR_LABEL = "",
	TOPBAR_ORDER = 1, -- Right strip: leftmost, immediately left of Command
	TOPBAR_ICON = Config.Icons.Topbar.Music,
	-- Horizontal setMenu children under the music topbar icon
	TOPBAR_MENU_OPEN_PLAYER_LABEL = "Music Player",
	TOPBAR_MENU_LOAD_TRACK_LABEL = "Load Track",
	MSG_RELOAD_OK = "Track loaded.",
	MSG_RELOAD_WAIT = "Still loading audio. Check music volume in Settings.",
	MSG_RELOAD_VOLUME_MUTED = "Music volume is at 0 in Settings. Raise it to hear the track.",
	MSG_RELOAD_COOLDOWN = "Wait a moment before loading again.",
	MSG_RELOAD_SYNC_FAILED = "Couldn't sync with the server. Try again in a moment.",
	MSG_RELOAD_IDLE = "Nothing is playing on the server right now.",
	-- Header 2-SliderSelector tab buttons (Option1..4 fallback + legacy names)
	TAB_LEGACY_BUTTON_NAMES = {
		nowPlaying = "1-NowPlayingTab",
		reqSong = "2-ReqSongTab",
		dj = "3-DJTab",
		manage = "4-ManageTracksTab",
	},
	TAB_LABELS = {
		nowPlaying = "Now Playing",
		reqSong = "Library",
		dj = "DJ",
		manage = "Manage",
	},

	SPECIAL_PLAYLIST_FAVORITES_ID = "__favorites__",
	SPECIAL_PLAYLIST_NEW_DROPS_ID = "__new_drops__",
	SPECIAL_PLAYLIST_REQUEST_HISTORY_ID = "__request_history__",
	SPECIAL_PLAYLIST_REQUEST_HISTORY_NAME = "Requested",
	-- Mode: "global" (single server-wide session, every player hears the same
	-- track) atau "zone" (per-tagged-zone sessions, players only hear music
	-- when inside a tagged BasePart). "global" recommended untuk club games,
	-- "zone" untuk world games dengan multiple distinct areas.
	MODE = "global",
	-- Music zones (cuma dipakai kalau MODE = "zone")
	ZONE_TAG = "MusicZone",
	ZONE_ID_ATTRIBUTE = "ZoneId",
	ZONE_DISPLAY_NAME_ATTRIBUTE = "DisplayName",
	ZONE_TICK_INTERVAL = 0.2,
	DEFAULT_ZONE_DISPLAY_NAME = "Music Zone",
	MSG_NOT_IN_ZONE = "You're not in a music zone yet. Step into one to start listening.",
	-- Rank yang boleh akses Manage tab
	-- Owner=255, CoOwner=254, Developer=200, Admin=100
	-- DJ rank ditambahkan di sini saat role-nya dibuat
	MANAGE_ALLOWED_RANKS = { 255, 251, 250},
	MANAGE_ALLOWED_EXACT_RANKS = { 60 },
	MANAGE_ALLOWED_INTERNAL_ROLES = {
		Owner = true,
		Staff = true,
		Moderator = true,
		LeadDance = false,
		DJ = true,
		CoOwner = true, -- legacy
		AfterTeam = true, -- legacy
		Developer = true, -- legacy
		Admin = false, -- legacy
		Investor = true, -- legacy alias → Staff
	},

	-- DataStore
	DATASTORE_NAME = scopedDataStoreKey("MusicLibrary_v1"),
	PLAYLIST_KEY = scopedDataStoreKey("Playlists"),
	TRACK_KEY = scopedDataStoreKey("Tracks"),
	FAVORITES_DATASTORE_NAME = scopedDataStoreKey("MusicFavorites_v1"),
	FAVORITES_KEY_PREFIX = scopedDataStoreKey("MusicFavorites_"),
	FAVORITES_ATTRIBUTE_KEY = "MusicFavoriteTrackIds",
	REMOTE_VOTE_STATE = "MusicVoteState",
	-- Remote names
	REMOTE_TRACK_CHANGED = "MusicTrackChanged", -- S->C
	REMOTE_QUEUE_UPDATED = "MusicQueueUpdated", -- S->C
	REMOTE_STATE_SYNC = "MusicStateSync", -- S->C (pada join)
	REMOTE_TIMING_UPDATED = "MusicTimingUpdated", -- S->C
	REMOTE_PLAYBACK_FINISHED = "MusicPlaybackFinished", -- C->S
	REMOTE_DURATION_REPORT = "MusicDurationReport", -- C->S
	REMOTE_VOTE_SKIP = "MusicVoteSkip", -- C->S
	REMOTE_REQUEST_TRACK = "MusicRequestTrack", -- C->S
	REMOTE_ADMIN_SKIP = "MusicAdminSkip", -- C->S
	REMOTE_REPORT_FAILURE = "MusicReportFailure", -- C->S (asset load failed)
	REMOTE_RESPONSE = "MusicResponse", -- S->C response callback
	REMOTE_GET_STATE = "MusicGetState", -- C->S (RE)
	REMOTE_GET_PLAYLISTS = "MusicGetPlaylists", -- C->S (RE)
	REMOTE_GET_TRACKS = "MusicGetTracks", -- C->S (RE)
	REMOTE_FAVORITE_TRACK = "MusicFavoriteTrack", -- C->S (RE)
	REMOTE_FAVORITES_SYNC = "MusicFavoritesSync", -- S->C owner-only
	REMOTE_SET_DJ_MODE = "MusicSetDjMode", -- C->S (RE)
	REMOTE_DJ_EFFECT = "MusicDjEffect", -- C->S (DJ effect change)
	REMOTE_MANAGE_PLAYLIST = "MusicManagePlaylist", -- C->S (admin only, RE)
	REMOTE_MANAGE_TRACK = "MusicManageTrack", -- C->S (admin only, RE)
	REMOTE_RESOLVE_REQUEST_ASSET = "MusicResolveRequestAsset", -- C->S (RE)
	REMOTE_ZONE_CHANGED = "MusicZoneChanged", -- S->C
	-- 30s: get_state / get_playlists / get_tracks yield through MusicRepository
	-- (DataStore cache miss = ~500ms, BudgetGate defer up to 5s) plus per-track
	-- thumbnail resolution. 10s tripped on cold boot.
	REMOTE_REQUEST_TIMEOUT = 30,
	VIRTUAL_TRACK_ROW_BUFFER = 6,
	VIRTUAL_TRACK_MAX_RENDERED_ROWS = 60,
	THUMBNAIL_CACHE_MAX = 100,
	-- Playback
	VOTE_SKIP_DURATION = 1,
	-- Max audio asset IDs per track. GUI 4-AddorEditTrackModal
	-- saat ini menyediakan 9 slot (2-TrackIDPart1..9). Naikin nilai
	-- ini perlu nambah frame baru di GUI juga.
	MAX_TRACK_PARTS = 9,
	NEW_DROPS_WINDOW_SECONDS = 7 * 24 * 60 * 60,
	VOTE_SKIP_THRESHOLD = 0.5, -- 50% of players must vote
	-- Default playback speed untuk music GUI saat track gak punya
	-- per-track override (track.playbackSpeed = nil).
	-- Controller dan binder membaca nilai ini saat pertama kali load.
	PLAYBACK_SPEED = 0.625,
	MSG_DJ_MODE_REQUIRED = "Enable DJ mode first to adjust sound effects and playback. Settings were reset.",
	PITCH_SEMITONES = 0,
	TRACK_FADE_IN_TIME = 2,
	TRACK_FADE_OUT_TIME = 5,
	-- Client incident watchdog: detect silent playback and self-heal via resync.
	INCIDENT = {
		ENABLED = true,
		CLIENT_WATCHDOG_INTERVAL = 8,
		CLIENT_NO_AUDIO_GRACE = 35,
		INCIDENT_SELF_HEAL_ENABLED = true,
		SELF_HEAL_COOLDOWN_SECONDS = 90,
	},
	-- Server: auto-advance when track duration unknown (seconds). Cancelled once client reports duration.
	AUTO_ADVANCE_UNKNOWN_DURATION_SECONDS = 180,
	-- Client: skip hanya jika ContentProvider mengonfirmasi gagal (bukan timer).
	-- Load lambat hanya log stall — tidak auto-skip.
	ASSET_LOAD_STALL_LOG_SECONDS = 120,
	-- Server: extra seconds before auto-advance on track start (client load window).
	ASSET_LOAD_GRACE_SECONDS = 90,
	-- Server: ignore client duration reports that would leave less than this many seconds on the clock.
	CLIENT_DURATION_MIN_REMAINING_SECONDS = 45,
	-- Server: quorum advance when enough clients report local playback finished.
	PLAYBACK_FINISH_QUORUM_RATIO = 0.5,
	PLAYBACK_FINISH_ADVANCE_TOLERANCE_SECONDS = 15,
	PLAYBACK_FINISHED_RATE_MAX = 8,
	PLAYBACK_FINISHED_RATE_WINDOW = 30,
	-- Client: min seconds after join before incident self-heal runs (HP slow load).
	INCIDENT_JOIN_GRACE_SECONDS = 45,
	-- Client: longer no-audio grace on touch-first devices.
	INCIDENT_MOBILE_NO_AUDIO_GRACE = 55,
	-- Client: log-only asset failures (server never skips globally for one client).
	ASSET_FAILURE_REPORT_TO_SERVER = false,
	-- Client: min seconds after playback start before reporting asset failure to server.
	ASSET_FAILURE_SKIP_MIN_STALL_SECONDS = 60,
	-- Client: retry TimedOut/transient CP failures before definitive report.
	ASSET_FAILURE_RETRY_ATTEMPTS = 3,
	ASSET_FAILURE_RETRY_BACKOFF = { 3, 8, 15 },
	-- When false, TimedOut triggers retry instead of immediate skip report.
	ASSET_FAILURE_TIMEDOUT_IS_DEFINITIVE = false,
	-- Deprecated: server does not global-skip on client failure reports.
	-- Server advanceQueue: validasi format asset ID saja (bukan PreloadAsync).
	ASSET_VALIDATE_ON_SERVER = true,
	ASSET_VALIDATE_USE_PRELOAD = false,
	-- Client audio prefetch (lookahead cache). Set PREFETCH_ENABLED = false to revert to legacy load-at-transition.
	PREFETCH_ENABLED = true,
	PREFETCH_TRACKS_AHEAD = 2,
	PREFETCH_MAX_CONCURRENT = 6,
	PREFETCH_QUEUE_HIGH_WATERMARK = 16,
	PREFETCH_QUEUE_PAUSE = 0.12,
	PREFETCH_PROFILE_CONSERVATIVE = 4,
	PREFETCH_PROFILE_BALANCED = 4,
	PREFETCH_PROFILE_AGGRESSIVE = 12,
	-- Max unique prefetched audio assets kept in client MusicAssetCache (ready + failed).
	-- Evicts LRU holders when exceeded; does not affect active playback sounds.
	PREFETCH_MAX_CACHE_ENTRIES = 48,
	-- Server: hidden auto prefetch buffer depth (not shown in Next up; DJ off).
	AUTO_QUEUE_DEPTH = 3,
	-- Refill auto buffer when visible user queue has at most this many tracks (0 or 1).
	AUTO_BUFFER_REFILL_MAX_USER_QUEUE = 1,
	DJ = {
		-- Soundboard entries are template-driven. Fill `soundId` with the real
		-- audio asset when available; the controller falls back to a local click
		-- SFX so the GUI remains testable in Studio.
		SOUND_BOARD_FALLBACK_SOUND_ID = Config.UISFX.CLICK_SOUND_ID,
		SOUND_BOARD_ITEMS = {
			{ id = "honk", label = "Honk", soundId = "" },
			{ id = "airhorn", label = "Airhorn", soundId = "" },
			{ id = "applause", label = "Applause", soundId = "" },
			{ id = "boo", label = "Boo", soundId = "" },
		},
		PLAYBACK_SPEED_PRESETS = {
			{ value = 0.25, label = "0.25x" },
			{ value = 0.5, label = "0.5x" },
			{ value = 1.0, label = "1x" },
			{ value = 1.5, label = "1.5x" },
			{ value = 2.0, label = "2x" },
		},
		EFFECTS = {
			{
				id = "equalizer",
				className = "EqualizerSoundEffect",
				sectionName = "EQ",
				toggleLabel = "Enable",
				defaultEnabled = false,
				items = {
					{
						id = "low",
						label = "Low",
						property = "LowGain",
						min = -12,
						max = 10,
						step = 1,
						defaultValue = 0,
						suffix = "db",
					},
					{
						id = "mid",
						label = "Mid",
						property = "MidGain",
						min = -12,
						max = 10,
						step = 1,
						defaultValue = 0,
						suffix = "db",
					},
					{
						id = "high",
						label = "High",
						property = "HighGain",
						min = -12,
						max = 10,
						step = 1,
						defaultValue = 0,
						suffix = "db",
					},
				},
			},
			{
				id = "echo",
				className = "EchoSoundEffect",
				sectionName = "Echo",
				toggleLabel = "Enable",
				defaultEnabled = false,
				items = {
					{
						id = "delay",
						label = "Delay",
						property = "Delay",
						min = 0.01,
						max = 1.5,
						step = 0.01,
						defaultValue = 0.25,
						suffix = "s",
					},
					{
						id = "feedback",
						label = "Feedback",
						property = "Feedback",
						min = 0,
						max = 0.95,
						step = 0.05,
						defaultValue = 0.35,
						suffix = "",
					},
					{
						id = "wet",
						label = "Wet",
						property = "WetLevel",
						min = -40,
						max = 10,
						step = 1,
						defaultValue = -10,
						suffix = "db",
					},
					{
						id = "dry",
						label = "Dry",
						property = "DryLevel",
						min = -40,
						max = 10,
						step = 1,
						defaultValue = 0,
						suffix = "db",
					},
				},
			},
			{
				id = "reverb",
				className = "ReverbSoundEffect",
				sectionName = "Reverb",
				toggleLabel = "Enable",
				defaultEnabled = false,
				items = {
					{
						id = "decay",
						label = "Decay",
						property = "DecayTime",
						min = 0.1,
						max = 8,
						step = 0.1,
						defaultValue = 1.5,
						suffix = "s",
					},
					{
						id = "density",
						label = "Density",
						property = "Density",
						min = 0,
						max = 1,
						step = 0.05,
						defaultValue = 1,
						suffix = "",
					},
					{
						id = "diffusion",
						label = "Diffusion",
						property = "Diffusion",
						min = 0,
						max = 1,
						step = 0.05,
						defaultValue = 1,
						suffix = "",
					},
					{
						id = "wet",
						label = "Wet",
						property = "WetLevel",
						min = -40,
						max = 10,
						step = 1,
						defaultValue = -8,
						suffix = "db",
					},
					{
						id = "dry",
						label = "Dry",
						property = "DryLevel",
						min = -40,
						max = 10,
						step = 1,
						defaultValue = 0,
						suffix = "db",
					},
				},
			},
			{
				id = "chorus",
				className = "ChorusSoundEffect",
				sectionName = "Chorus",
				toggleLabel = "Enable",
				defaultEnabled = false,
				items = {
					{
						id = "depth",
						label = "Depth",
						property = "Depth",
						min = 0,
						max = 1,
						step = 0.05,
						defaultValue = 0.2,
						suffix = "",
					},
					{
						id = "mix",
						label = "Mix",
						property = "Mix",
						min = 0,
						max = 1,
						step = 0.05,
						defaultValue = 0.5,
						suffix = "",
					},
					{
						id = "rate",
						label = "Rate",
						property = "Rate",
						min = 0,
						max = 8,
						step = 0.1,
						defaultValue = 0.5,
						suffix = "hz",
					},
				},
			},
			{
				id = "distortion",
				className = "DistortionSoundEffect",
				sectionName = "Distortion",
				toggleLabel = "Enable",
				defaultEnabled = false,
				items = {
					{
						id = "level",
						label = "Level",
						property = "Level",
						min = 0,
						max = 1,
						step = 0.05,
						defaultValue = 0.25,
						suffix = "",
					},
				},
			},
			{
				id = "pitch",
				className = "PitchShiftSoundEffect",
				sectionName = "Pitch",
				toggleLabel = "Enable",
				defaultEnabled = false,
				items = {
					{
						id = "octave",
						label = "Octave",
						property = "Octave",
						min = 0.5,
						max = 2,
						step = 0.01,
						defaultValue = 1,
						suffix = "x",
					},
				},
			},
		},
	},
	-- Idle fallback: saat tidak ada request aktif, sistem akan assign lagu otomatis.
	-- Fallback ini dimatikan saat DJ mode aktif.
	IDLE_SYSTEM_FALLBACK_ENABLED = true,
	SYSTEM_ASSIGNER_LABEL = "Assigned by System",
	-- Rate limits
	VOTE_SKIP_RATE_MAX = 1,
	VOTE_SKIP_RATE_WINDOW = 30,
	REQUEST_TRACK_RATE_MAX = 100,
	REQUEST_TRACK_RATE_WINDOW = 30,
	REQUEST_TRACK_MAX_PER_USER_QUEUE = 100,
	READ_RATE_MAX = 8,
	READ_RATE_WINDOW = 10,
	DURATION_REPORT_RATE_MAX = 4,
	DURATION_REPORT_RATE_WINDOW = 10,
	FAVORITE_RATE_MAX = 8,
	FAVORITE_RATE_WINDOW = 30,
	MANAGE_RATE_MAX = 10,
	MANAGE_RATE_WINDOW = 60,
	RESOLVE_REQUEST_ASSET_RATE_MAX = 6,
	RESOLVE_REQUEST_ASSET_RATE_WINDOW = 30,
	-- DJ ops are separate from admin manage: sliders fire often; sharing MANAGE_* blocked toggles.
	DJ_MODE_RATE_MAX = 30,
	DJ_MODE_RATE_WINDOW = 60,
	DJ_EFFECT_RATE_MAX = 150,
	DJ_EFFECT_RATE_WINDOW = 60,
	-- D2 (quota-efficiency-pass-2026-06, Phase 1): extended from 15s to 30s.
	-- Music library rarely changes. Revert to 15s via Config if admin upload track UX issue.
	-- DataStore-heavy path, not HTTP-API culprit. Default OK.
	SYNC_POLL_INTERVAL = 30,
	-- Cover gradient presets (untuk ColorTemplateList)
	-- Format: { color0, color1, rotation }
	COVER_GRADIENTS = {
		{ Color3.fromRGB(34, 10, 32), Color3.fromRGB(92, 18, 66), 90 }, -- Neon Wine
		{ Color3.fromRGB(24, 13, 44), Color3.fromRGB(67, 25, 103), 90 }, -- Night Violet
		{ Color3.fromRGB(12, 29, 45), Color3.fromRGB(25, 87, 112), 90 }, -- Deep Cyan
		{ Color3.fromRGB(11, 33, 31), Color3.fromRGB(25, 88, 78), 90 }, -- Dark Teal
		{ Color3.fromRGB(39, 15, 17), Color3.fromRGB(94, 36, 24), 90 }, -- Ember
		{ Color3.fromRGB(36, 24, 10), Color3.fromRGB(92, 64, 24), 90 }, -- Muted Gold
		{ Color3.fromRGB(26, 28, 36), Color3.fromRGB(67, 70, 86), 90 }, -- Club Slate
		{ Color3.fromRGB(23, 18, 31), Color3.fromRGB(60, 38, 69), 90 }, -- Smoky Plum
	} :: { { Color3 | number } },
	-- Font presets (curated list dari Roblox fonts)
	FONT_PRESETS = {
		"Original",
		"Montserrat",
		"GothamSSm",
		"BuilderSans",
		"Roboto",
		"SourceSansPro",
		"Oswald",
		"Bangers",
		"Creepster",
		"FredokaOne",
		"JosefinSans",
		"Merriweather",
		"Nunito",
		"PatrickHand",
		"PermanentMarker",
		"RobotoCondensed",
		"TitilliumWeb",
	},
}
-- ============================================================
-- MOBILE PANEL MANAGER
-- Exclusive-focus panel system for mobile devices.
-- ============================================================
Config.MobilePanelManager = {
	OVERLAY_TRANSPARENCY = 0.55,
	OVERLAY_TWEEN_IN = 0.18,
	OVERLAY_TWEEN_OUT = 0.15,
	OVERLAY_DISPLAY_ORDER = 200,
	-- Hotbar chrome slide — same as CinematicDock setDockVisible (Quad In hide, Quint Out show).
	HOTBAR_HIDE_DURATION = Config.CinematicDock.DOCK_CHROME_HIDE_DURATION,
	HOTBAR_SHOW_DURATION = Config.CinematicDock.DOCK_CHROME_SHOW_DURATION,
	HOTBAR_SHOW_START_SCALE = Config.CinematicDock.DOCK_CHROME_START_SCALE,
	HOTBAR_SLIDE_OFFSET = Config.CinematicDock.DOCK_CHROME_SLIDE_OFFSET_Y,
	-- PC: auto-hide hotbar after no mouse/keyboard input. Set false to keep hotbar always visible.
	HOTBAR_IDLE_HIDE_ENABLED = false,
	HOTBAR_IDLE_TIMEOUT = 3,
	-- Minimum shorter viewport dimension (px) to be treated as a tablet.
	-- Devices at or above this threshold use desktop behaviour (no mobile scaling).
	TABLET_MIN_SHORT_SIDE = 600,
	-- GUI names that lack their own Config section
	COUPLE_GUI_NAME = "01-CoupleSystemGUI",
	SHOP_GUI_NAME = "02-ShopGUI",
	STREAK_GUI_NAME = "05-StreakGUI",
}
-- ============================================================
-- MOBILE UI SCALES
-- Per-GUI UIScale value applied on touch-only devices.
-- The ACM entry also removes its designer Y-offset (baked in Studio).
-- ============================================================
Config.MobileScale = {
	COUPLE_GUI = 0.68, -- 01-CoupleSystemGUI
	SHOP_GUI = 0.6, -- 02-ShopGUI
	GIFT_GUI = 0.68, -- 03-GiftSystemGUI
	STREAK_GUI = 0.6, -- 05-StreakGUI
	MUSIC_GUI = 0.62, -- 06-MusicPlayerGUI
	MENU_GUI = 0.7, -- 07-MenuGUI
	DONATION_GUI = 0.65, -- 09-DonationSystemGUI
	HOTBAR_GUI = 0.8, -- 10-HotbarGUI / HotbarGUI
	BACKPACK_GUI = 0.9, -- 14-BackpackGUI HotbarWrapper.UIScale
	ADMIN_GUI = 0.54, -- 04-AdminPanel root UIScale on phone layout
	STICKER_GUI = 0.8, -- 11-StickerSystemGUI
	NOTIF_GUI = 0.75, -- 99-NotificationCenter
	COMMAND_GUI = 0.8, -- CommandLibraryGUI
	ACM_GUI = 0.68, -- AvatarContextMenu (+ remove Y offset on MainWrapper)
	ICON_GROUP = 0.6, -- DancePanelGUIWrapper (v1) inside IconGroup ScreenGui
	ICON_GROUP_IGNORE_GUI_INSET = true, -- IconGroup ScreenGui full-bleed (no topbar inset gap)
	DANCE_PANEL_V2_SCALE = 0.63, -- DancePanelGUIWrapperv2 on touch-only phones
	DANCE_TRIGGER_SCALE = 0.9, -- DancePanelButton trigger inside IconGroup ScreenGui
}
-- ============================================================
-- SCROLL INDICATOR
-- ============================================================
Config.ScrollIndicator = {
	-- Detik tanpa scroll sebelum scroll bar transparansi di-fade ke tersembunyi
	FADEOUT_DELAY = 3,
	FADEOUT_DURATION = 0.4,
	FADEIN_DURATION = 0.15,
	HIDDEN_TRANSPARENCY = 1,
	VISIBLE_TRANSPARENCY = 0,
}
-- ============================================================
-- PERFORMANCE SCALING — 100 CCU TARGET
-- Capacity, interest-filtering, and feature flags for the
-- performance-scaling-100ccu remediation program.
-- ============================================================
-- Documented server capacity target. The whole remediation program is tuned to run
-- stable at 100 concurrent players per server (perf-scaling R3.1).
Config.Server = {
	CCU_TARGET = 100,
}
-- DataStore budget allocation re-tuned from the old 70-80 CCU targets to 100 CCU
-- (perf-scaling R3.2, R3.3, R3.6). Consumed by BudgetGate / DataStoreScheduler.
Config.Budget = {
	WRITE_PER_MIN_TARGET = 110, -- R3.2: >=110 writes/min/server at 100 CCU
	READ_PER_MIN_TARGET = 80, -- R3.3: >=80 reads/min/server at 100 CCU
	DEFER_SECONDS = 8, -- Scaling 100→200 CCU: extended from 5s to 8s to give budget more time to recover during load spikes
	POLL_INTERVAL = 0.5, -- budget replenishment poll cadence (seconds)
	NEGATIVE_CACHE_TTL = 10, -- seconds to skip retrying a DataStore read after budget_exhausted
}
-- Persistence Fabric (DataStoreScheduler + session write-behind + InvalidateBus).
-- Kill switch: USE_LEGACY_PER_REPO_BUDGET_GATE = true restores pre-fabric BudgetGate races.
Config.Persistence = {
	USE_LEGACY_PER_REPO_BUDGET_GATE = false,
	HEADROOM = 2, -- keep this many spare credits beyond minBudget before dispatch
	MAX_INFLIGHT_PER_TYPE = 4, -- concurrent DS ops per RequestType across all repos
	KEY_MUTEX_ENABLED = true, -- serialize UpdateAsync/GetAsync on same store::key
	DEFER_SECONDS = 8, -- scheduler wait window (falls back to Config.Budget.DEFER_SECONDS)
	POLL_INTERVAL = 0.5,
	-- PlayerSessionStore write-behind
	SESSION_FLUSH_DEBOUNCE = 3, -- seconds coalesce dirty Overhead/Settings writes
	SESSION_WRITE_BEHIND_ENABLED = true,
	USE_LEGACY_IMMEDIATE_OVERHEAD_WRITES = false, -- true → skip session store (direct UpdateAsync)
	-- InvalidateBus (CrossServerCache upgrade)
	USE_LEGACY_CROSS_SERVER_CACHE = false, -- true → 1s per-user debounce only
	INVALIDATE_COALESCE_SEC = 0.75,
	INVALIDATE_TOKEN_BUCKET_RATE = 8, -- publishes/sec soft cap per server
	INVALIDATE_TOKEN_BUCKET_BURST = 12,
	INVALIDATE_SKIP_ORIGIN = true,
	METRICS_LOG_INTERVAL = 60, -- server DEBUG summary interval (0 = off)
}
-- HTTP API wrapper — dedup + cache for GroupService/Players at 100 CCU.
Config.HttpApi = {
	COUNTERS_ENABLED = false,
	-- Enabled: in-flight dedup + TTL cache for GroupService/Players/UserService wrappers.
	-- LeaderboardIdentity has its own cache (does not rely on this flag).
	ENABLED = true,
	-- Phase 1 perf: negative-cache failures + global concurrency (kill switch ADMISSION_ENABLED).
	ADMISSION_ENABLED = true,
	MAX_CONCURRENT = 4,
	NEGATIVE_CACHE_TTL = 30,
	ADMISSION_WAIT_MAX = 5,
	GET_NAME_TTL = 600,
	GET_USER_ID_TTL = 600,
	GET_USER_INFOS_TTL = 600,
	GET_FRIENDS_TTL = 300,
	GET_THUMB_TTL = 600,
	GET_GROUPS_TTL = 300,
	GET_HUMANOID_DESCRIPTION_TTL = 600,
}
-- Client-side HTTP API wrapper (StarterPlayer/StarterPlayerScripts/Client/Utils/ClientHttpApi.luau).
-- Independent from server Config.HttpApi — client has separate rate limits (300/m).
Config.ClientHttpApi = {
	ENABLED = false,
	GET_THUMB_TTL = 600,
	-- Max seconds to wait on an in-flight thumbnail fetch before giving up.
	THUMB_INFLIGHT_WAIT_SEC = 15,
	GET_HUMANOID_DESCRIPTION_TTL = 600,
	GET_USER_ID_TTL = 600,
}
-- Join-time DataStore read serialization (perf-scaling R3.7 / R10.1). Consumed by ProfileLoader.
-- Persistence Fabric: default 4 (safer with global scheduler HEADROOM); was 8 for 100→200 join storms.
Config.ProfileLoader = {
	MAX_CONCURRENCY = 4,
	PER_PLAYER_CONCURRENCY = 1, -- R10.1: per-player reads run sequentially through one queue
	-- Critical join kinds (overhead/profile) enqueue immediately; secondary kinds wait this long.
	SECONDARY_JOIN_DELAY_SEC = 4,
	-- Retries outside the DS scheduler slot; first delay >= Budget.NEGATIVE_CACHE_TTL.
	RETRY_DELAYS = { 10, 15, 25 },
}
-- TitleColorPreset animation tick (Phase 3): shared ~30Hz loop for Gradient/Stroke/Dropshadow.
-- Kill switch: USE_LEGACY_PER_INSTANCE_HEARTBEAT = true → one Heartbeat per effect instance (pre-2.4.24).
Config.TitleColorPreset = {
	SHARED_TICK_ENABLED = true,
	TICK_HZ = 30,
	SKIP_HIDDEN = true, -- skip ticks when GuiObject/LayerCollector ancestor is hidden
	USE_LEGACY_PER_INSTANCE_HEARTBEAT = false,
}

-- InterestManager / ProximityInterestService View_Range tuning (perf-scaling R1.9-R1.11).
-- Phase 2: tighter default radius cuts overhead/sync Recv at high CCU. Enter covers
-- Medium nametag distance (48 studs) with margin; leave = RADIUS + BUFFER (hysteresis).
-- Far (unlimited client cull) still only gets server subscribe within this radius.
-- Kill switch: USE_LEGACY_VIEW_RANGE = true restores pre-2.4.23 80 / 20.
Config.Interest = {
	USE_LEGACY_VIEW_RANGE = false,
	VIEW_RANGE_RADIUS = 55, -- enter subscribe radius (studs); legacy was 80
	HYSTERESIS_BUFFER = 15, -- leave only past RADIUS + BUFFER; legacy was 20
	RECOMPUTE_INTERVAL = 0.5, -- R1.9: recompute cadence (seconds, must be <= 1.0)
	LEGACY_VIEW_RANGE_RADIUS = 80,
	LEGACY_HYSTERESIS_BUFFER = 20,
}
-- NetworkManager shared-flush scheduler (perf-scaling R9). Flip to false to roll back to
-- one RunService.Heartbeat connection per NetworkManager instance.
Config.Network = {
	ENABLE_SHARED_FLUSH = true,
	-- Per-frame coalesce: same (target, optional data.kind) keep last payload before flush.
	-- Immediate paths still flushNow(); coalesce only merges duplicate keys within that flush.
	ENABLE_FRAME_COALESCE = true,
}

-- Network + client FPS stabilization (Recv/ping/FPS). Kill switches for A/B; real fixes default ON.
-- Counters are no-op when ENABLE_COUNTERS = false (hot path must stay cheap).
Config.NetworkPerf = {
	ENABLE_COUNTERS = false,
	-- Debug: skip OverheadUI:apply (caches/bridges still update) — isolate FPS vs Recv.
	SKIP_OVERHEAD_UI_APPLY = false,
	-- Join: send nearby overhead payloads only; distant covered by Snapshot-on-enter.
	OVERHEAD_JOIN_PROXIMITY_ONLY = true,
	-- DJ knob: effects-only MusicStateSync (no full getState fan-out).
	DJ_EFFECTS_DELTA_ONLY = true,
	-- Coalesce S→C DJ effect packets (~DJ_EFFECTS_SYNC_HZ trailing keep-last).
	DJ_STATE_SYNC_THROTTLE = true,
	DJ_EFFECTS_SYNC_HZ = 12,
	-- Kind field on MusicStateSync for effects-only packets.
	MUSIC_STATE_KIND_DJ_EFFECTS = "djEffects",
	-- Cap concurrent world nuke/aura VFX (0 = disable world VFX enqueue).
	DONATION_VFX_MAX_CONCURRENT = 1,
	-- Debug: pause workspace SurfaceGui LB paint (net fingerprint path unchanged).
	WORKSPACE_LB_PAINT_PAUSE = false,
	-- DeltaCompressor: deep-equal nested tables (visibleBadges, title style, etc.).
	DEEP_DELTA_NESTED = true,
}
-- ============================================================
-- CONFIG VALIDATION
-- ============================================================
local function validateConfig()
	-- Shop IDs: Game Pass (buy) + Developer Product (gift); placeholder 0 until ClubKitConfig filled
	if Config.Shop and Config.Shop.PRODUCTS then
		for tier, product in pairs(Config.Shop.PRODUCTS) do
			if type(product) == "table" then
				if product.BUY_GAMEPASS_ID == 0 or product.BUY_GAMEPASS_ID == nil then
					warn(
						("[Config] Shop.PRODUCTS.%s.BUY_GAMEPASS_ID masih 0/nil — isi ClubKitConfig.Shop.Products.%s.BuyGamePassId."):format(
							tostring(tier),
							tostring(tier)
						)
					)
				end
				if product.GIFT_ID == 0 or product.GIFT_ID == nil then
					warn(
						("[Config] Shop.PRODUCTS.%s.GIFT_ID masih 0/nil — ganti dengan Developer Product ID aktual."):format(
							tostring(tier)
						)
					)
				end
			end
		end
	end
	if Config.PaidBroadcast and (Config.PaidBroadcast.PRODUCT_ID == 0 or Config.PaidBroadcast.PRODUCT_ID == nil) then
		warn("[Config] PaidBroadcast.PRODUCT_ID masih 0/nil — isi ClubKitConfig.PaidBroadcast.ProductId.")
	end
	-- Group ID harus valid (skip saat showcase/demo — tidak butuh group live)
	if Config.Group.GROUP_ID <= 0 and not (Config.Demo and Config.Demo.ENABLED == true) then
		warn("[Config] Group.GROUP_ID tidak valid (harus > 0).")
	end
end
local ConfigBootstrap = require(script.Parent.Parent.Config.ConfigBootstrap)
local RolesDomain = require(script.Parent.Parent.Domain.RolesDomain)
ConfigBootstrap.apply(Config)
RolesDomain.applyDerivedConfig(Config)

validateConfig()
table.freeze(Config)
return Config
