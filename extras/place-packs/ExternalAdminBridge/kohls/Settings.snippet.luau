--[[
	Kohl's Admin (NEW loader) Settings checklist (External Admin Bridge pack)
	=======================================================================
	Apply in: Kohl's Admin > Config > Settings  (NOT Config > Legacy > Settings).
	These are SNIPPETS/COMMENTS — merge into the existing Settings module,
	do not replace the whole file. Docs: https://docs.kohl.gg/docs/getting-started/configuration

	Rank philosophy: Club Kit owns club roles/membership; Kohl's owns
	moderation (ban/kick/mute). Mirror only staff roles. NEVER map Club Kit
	membership (VIP/VVIP/Supreme) to the Kohl's "vip" role — Kohl's "vip" is
	a paid cosmetic tier, not club membership.
--]]

-- 1. De-ads / de-noise --------------------------------------------------------
addToCharts = false,          -- Kohl's Admin Charts / HTTP promo surface
vip = false,                  -- VIP upsell features (required false when addToCharts is false)
getKohlsAdminPopup = false,   -- "Get Kohl's Admin" popup
joinNotificationRank = false, -- no join-rank spam for guests (false = disable)
-- optional noise:
-- dashboardButtonRank = false, -- or raise to 2+ so guests don't see the button
-- onlyShowUsableCommands = true,

-- 1b. Sound de-noise — in Kohl's Admin > Config > Themes > Default (theme module,
--     NOT this Settings module). IMPORTANT for music games: Kohl's plays a loud
--     (volume 1.5-2.0) keyboard "clack" per keystroke in ANY textbox/chat, plus
--     hover/snap SFX on its UI — over playing music this clips the mixer and
--     sounds like crackling audio. Kill them:
-- SoundEnabled = false,            -- master switch for all Kohl's SFX
-- TypingSounds = false,            -- keyboard clack while typing
-- TypingSoundsOnEveryTextBox = false,

-- 2. Prefix — keep Kohl's on ";" and Adonis-style ":" documented; Club Kit chat
--    commands use "/" so there is no clash.
prefix = { ";" },

-- 3. Roles — mirror Club Kit staff (defaults match ClubKitConfig.ExternalAdmin.RankMap)
-- userRoles = {
--     creator = { --[[ OwnerUserId from ClubKitConfig.Group.OwnerUserId ]] },
--     superadmin = { --[[ Club Kit CoOwner userIds (optional) ]] },
--     admin = { --[[ Club Kit Staff userIds (optional; live sync covers this) ]] },
--     mod = {},
-- },
-- groupRoles = {
--     [GroupId] = { -- ClubKitConfig.Group.GroupId
--         { rank = 255, roles = { "creator" }, exactRank = false },
--     },
-- },
-- Prefer live sync (ClubKitAddon) over static lists for staff: /setrole Staff
-- in Club Kit auto-assigns the mapped Kohl's role (non-persistent).

-- 4. Custom low-power role for content (OPTIONAL, off by default) -------------
-- Only if ClubKitConfig.ExternalAdmin.SyncContentRoles = true and RankMap
-- includes e.g. DJ = { kohls = "content" }:
-- roles = { ..., {
--     _key = "content",
--     name = "Content",
--     color = "#c8f",
--     groups = { "utility" }, -- safe basics only — NO moderation/fun abuse
--     limits = { cooldown = 4, commands = 16, targets = 1 },
--     permissions = {},
--     onlyTargetSelf = true,
-- } },
