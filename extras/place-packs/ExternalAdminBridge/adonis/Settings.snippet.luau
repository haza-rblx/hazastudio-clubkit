--[[
	Adonis Settings checklist (External Admin Bridge pack)
	======================================================
	Official loader only: https://www.roblox.com/library/7510622625/
	Current Adonis splits settings by category under Adonis_Loader >
	Config > Settings (General / Ranks / _GAPI / ...). Key names match the
	classic flat Settings module — edit them in the matching category
	module. These are SNIPPETS/COMMENTS — merge, do not replace.

	Rank philosophy: Club Kit owns club roles/membership; Adonis owns
	moderation (ban/kick/mute). Mirror only staff ranks. NEVER put Club Kit
	membership (VIP/VVIP/Supreme) or Spender roles into Adonis ranks.
--]]

-- 1. API + storage ------------------------------------------------------------
-- In Config > Settings > _GAPI:    G_API = true   -- exposes _G.Adonis (bridge detection uses it)
-- In Config > Settings > General:  DataStoreKey = "<random string>"  -- change from default!

-- 2. Ranks (Config > Settings > Ranks) — mirror Club Kit staff
--    (defaults match ClubKitConfig.ExternalAdmin.RankMap):
--   Creators   (900) → { "Group:<GroupId>:-255" }  -- group rank >= 255 = Club Kit Owner
--   HeadAdmins (300) → Club Kit CoOwner (optional; usually via live sync instead)
--   Admins     (200) → Club Kit Staff
--   Moderators (100) → Club Kit Moderator
-- Prefer live sync (Server-ClubKitBridge plugin) over static Users lists for
-- staff: /setrole Staff in Club Kit then auto-ranks in Adonis (temp/session).

-- 3. Permissions — keep moderation powerful, club commands admin-only ---------
-- :ck* commands are registered at AdminLevel "Admins" by the plugin.
-- Optionally lock ban/kick to Admins+ if previously lowered.

-- 4. De-noise for club branding (Config > Settings > General / related) -------
-- FunCommands = false,       -- club vibe: no disco/explode abuse
-- DonorCommands = false,     -- no donor perks colliding with Club Kit shop
-- OnStartup = {},            -- avoid auto-:cmds spam
-- Join-message hints: keep minimal; Club Kit has its own greeting.

-- 5. Custom low-power rank for content roles (OPTIONAL, off by default) -------
-- Only if ClubKitConfig.ExternalAdmin.SyncContentRoles = true and RankMap
-- includes e.g. DJ = { adonis = 50 }:
--   Ranks: add a custom rank at Level 50; Permissions: only harmless commands.
