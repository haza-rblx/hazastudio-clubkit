--!strict
-- Shared/Domain/AnnouncementRateLimitDomain.luau
--
-- Resolves which /announce rate-limit budget applies to a player, based on
-- role + effective membership. Pure domain logic — no networking, no state.
--
-- Resolution order (first match wins):
--   1. Leadership — role priority >= Staff
--   2. Spender    — RoyaleSpender / TopSpender / Spender
--   3. Member     — effectiveMembership >= Config.Announcement.MIN_MEMBERSHIP_TIER
--   4. Player     — everyone else who passed the canAnnounce permission gate
--
-- Buyer overrides live in ClubKitConfig.Announcement.RateLimits (partial) and
-- are fill-forwarded onto Config.Announcement.RATE_LIMIT_* by ConfigBootstrap.
-- When the whole RateLimits table is absent, the legacy single budget
-- (RATE_MAX/RATE_WINDOW) is used — backward compatible with pre-v2 configs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local RolesDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.RolesDomain)

export type RateBudget = {
	max: number,
	window: number,
	group: string,
}

local AnnouncementRateLimitDomain = {}

local SPENDER_ROLES: { [string]: boolean } = {
	RoyaleSpender = true,
	TopSpender = true,
	Spender = true,
}

local function readBudget(maxKey: string, windowKey: string, group: string): RateBudget
	local announcement = Config.Announcement :: any
	local max = tonumber(announcement[maxKey]) or 1
	local window = tonumber(announcement[windowKey]) or 60
	return {
		max = math.max(1, math.floor(max)),
		window = math.max(1, math.floor(window)),
		group = group,
	}
end

--- Resolve the rate budget for a player. roleKey / effectiveMembership may be
--- nil (caller failed to resolve overhead) — they fall through to Player.
function AnnouncementRateLimitDomain.resolve(roleKey: string?, effectiveMembership: string?): RateBudget
	if OverheadDomain.hasRolePriorityAtLeast(roleKey, "Staff") then
		return readBudget("RATE_LIMIT_LEADERSHIP_MAX", "RATE_LIMIT_LEADERSHIP_WINDOW", "Leadership")
	end
	local normalizedRole = RolesDomain.normalizeRoleKey(roleKey)
	if normalizedRole and SPENDER_ROLES[normalizedRole] then
		return readBudget("RATE_LIMIT_SPENDER_MAX", "RATE_LIMIT_SPENDER_WINDOW", "Spender")
	end
	local minTierRaw = Config.Announcement and Config.Announcement.MIN_MEMBERSHIP_TIER
	local minTier = OverheadDomain.normalizeMembershipTier(minTierRaw) or "Tier2"
	if OverheadDomain.hasMembershipAtLeast(effectiveMembership, minTier) then
		return readBudget("RATE_LIMIT_MEMBER_MAX", "RATE_LIMIT_MEMBER_WINDOW", "Member")
	end
	return readBudget("RATE_LIMIT_PLAYER_MAX", "RATE_LIMIT_PLAYER_WINDOW", "Player")
end

--- Legacy single-budget fallback (pre-RateLimits configs).
function AnnouncementRateLimitDomain.legacyBudget(): RateBudget
	local announcement = Config.Announcement :: any
	return {
		max = math.max(1, tonumber(announcement.RATE_MAX) or 2),
		window = math.max(1, tonumber(announcement.RATE_WINDOW) or 30),
		group = "Legacy",
	}
end

return AnnouncementRateLimitDomain
