--!nocheck
-- Hierapolis ClubKitConfig patch (idempotent). Normally run via apply.luau in this folder:
--   loadstring(HttpService:GetAsync("http://127.0.0.1:8798/repo/extras/place-packs/Hierapolis/apply.luau"))()
-- Replaces RoleCategories / SystemRoles.Owner / LegacyAliases+CommandAliases spans and flips
-- Features.LoadingScreen = false. Buyer values outside those spans are untouched.
local mod = game:GetService("ReplicatedStorage").Hazastudio_ClubKitConfig.ClubKitConfig
local src = mod.Source
local log = {}

local function spanReplace(startAnchor, endAnchor, replacement, label, keepEnd)
	local s = string.find(src, startAnchor, 1, true)
	assert(s, "start anchor not found: " .. label)
	local e1, e2 = string.find(src, endAnchor, s, true)
	assert(e1, "end anchor not found: " .. label)
	local cutEnd = if keepEnd then e1 - 1 else e2
	src = string.sub(src, 1, s - 1) .. replacement .. string.sub(src, cutEnd + 1)
	table.insert(log, label)
end

-- 1. RoleCategories (Leadership: Archon | DPC: Emperor, Echoborn, Minister, Senator | Content)
spanReplace("ClubKitConfig.RoleCategories = {", "} :: { any }", [[ClubKitConfig.RoleCategories = {
	-- Hierapolis Theatre catalog. All roles here are /setrole roles (the COMA Studio group only
	-- has Member / Dev / Admin / Owner ranks). The four DPC roles share chatTag "DPC" (Rank row,
	-- chat tag, player list) while their unique name lives in the overhead chip
	-- (specialRank.chip = true, painted with roleColor.stops; hides that role's #N rank chips).
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
				roleColor = { stops = { "301a9e", "5141d7", "5fec4c", "fafa3e", "e61b23" } }, -- last was "e61b2" (typo) → #E61B23 from old accent
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
} :: { any }]], "RoleCategories")

-- 2. SystemRoles.Owner → The President (whole block, wherever it sits inside SystemRoles)
do
	local sysStart = string.find(src, "ClubKitConfig.SystemRoles = {", 1, true)
	assert(sysStart, "SystemRoles block not found")
	local ownerStart = string.find(src, "Owner = {", sysStart, true)
	assert(ownerStart, "SystemRoles.Owner not found")
	-- match the brace that opens Owner's table
	local braceOpen = string.find(src, "{", ownerStart, true)
	local depth, i, braceClose = 0, braceOpen, nil
	while i <= #src do
		local ch = string.sub(src, i, i)
		if ch == "{" then depth += 1 elseif ch == "}" then depth -= 1 if depth == 0 then braceClose = i break end end
		i += 1
	end
	assert(braceClose, "SystemRoles.Owner brace mismatch")
	-- include the trailing comma if present
	local after = braceClose
	if string.sub(src, braceClose + 1, braceClose + 1) == "," then after = braceClose + 1 end
	src = string.sub(src, 1, ownerStart - 1) .. [[Owner = { -- rank row / chat tag stay OWNER; "THE PRESIDENT" lives in the chip
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
	},]] .. string.sub(src, after + 1)
	table.insert(log, "SystemRoles.Owner")
end

-- 3. Aliases
spanReplace("ClubKitConfig.LegacyAliases = {", "-- =============================================================================\n-- JOIN COMMUNITY", [[ClubKitConfig.LegacyAliases = {
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
}

ClubKitConfig.CommandAliases = {
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
}

]], "Aliases", true)

-- 4. Kit loading screen off → CinematicLoading pack owns boot
if string.find(src, "\tLoadingScreen = true,", 1, true) then
	src = string.gsub(src, "\tLoadingScreen = true,", "\tLoadingScreen = false, -- CinematicLoading place pack owns boot (ReplicatedFirst.CinematicLoading)", 1)
	table.insert(log, "Features.LoadingScreen")
end

local fn, err = loadstring(src, "=ClubKitConfig")
assert(fn, "patched source does not compile: " .. tostring(err))
setfenv(fn, setmetatable({ script = mod }, { __index = getfenv() }))
local cfg = fn()
assert(cfg.SystemRoles.Owner.chatTag == "OWNER" and cfg.SystemRoles.Owner.specialRank.text == "THE PRESIDENT" and cfg.Features.LoadingScreen == false and cfg.CommandAliases.senator == "LeadDance", "sanity failed")
local keys = {}
for _, cat in ipairs(cfg.RoleCategories) do
	for _, r in ipairs(cat.roles) do table.insert(keys, cat.label .. "/" .. r.key .. ":" .. r.chatTag) end
end
mod.Source = src
print("[hierapolis-config-apply] " .. table.concat(log, ", ") .. " | " .. table.concat(keys, ", "))
return table.concat(keys, ", ")
