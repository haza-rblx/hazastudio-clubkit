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
	SwitchFadeIn = 0.55, -- dance A→B: B fades in
	SwitchFadeOut = 0.55, -- dance A→B: A fades out (match SwitchFadeIn)
	SyncJoinFade = 0.4, -- join / sync to leader
	SwitchInputCooldown = 0.55, -- emote click cooldown; >= SwitchFade*
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
	-- true = place uses extras/place-packs/SyncBhms (ACM Sync Dance → BHMS).
	-- Disables Club Kit dance panel + SyncService. false = SyncBhmsGate no-ops pack (hide topbar Dance).
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
	VipOnCommunityJoin = true,
	-- Toast when Owner / Leadership / Content / top-10 Robux or cash spender joins (once per session).
	JoinGreetings = true,
	-- Global Nuke / Smite / BlackHole on cash donations. false = no world explosion VFX; Settings “World Effects” row hidden.
	DonationWorldEffects = true,
	-- UIGradient animation on #N ROBUX / #N RUPIAH chips in overhead (RobuxRankWrapper / RupiahRankWrapper).
	DonationRankGradientAnim = true,
}

return ClubKitConfig
