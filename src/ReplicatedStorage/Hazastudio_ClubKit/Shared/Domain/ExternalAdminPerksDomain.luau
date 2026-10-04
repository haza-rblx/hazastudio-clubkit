--!strict
-- Shared/Domain/ExternalAdminPerksDomain.luau
--
-- Pure decision logic for external-admin bridge perks (place-pack addon:
-- Kohl's fly / smite gating). No services, no state — every dependency is
-- injected so this module is harness-testable (Lune).
--
-- Perk config shape (ClubKitConfig.ExternalAdmin.Perks.<Perk>):
--   { Tier2 = true }   -- tiers at/above the highest matching configured key
--   { Tier3 = 3 }      -- get the perk; number = weekly quota, true = unlimited
-- The HIGHEST configured tier the player qualifies for decides, so a buyer can
-- graduate quotas ({ Tier2 = 1, Tier3 = 3 }) without a Tier3 player being
-- capped by the Tier2 entry.
--
-- Weekly quotas use ISO-8601 calendar weeks: reset Monday 00:00 UTC.

export type PerkGate = {
	allowed: boolean,
	reason: string, -- "staff_bypass" | "tier" | "below_tier" | "not_configured"
	tier: string?, -- matched tier (reason = "tier")
	minTier: string?, -- lowest configured tier (reason = "below_tier")
	quota: number?, -- nil = unlimited (fly-style), number = per ISO week
}

export type GateContext = {
	isStaff: boolean,
	staffBypass: boolean,
	-- hasAtLeast("Tier3") -> does the player hold this tier or higher?
	hasAtLeast: (tier: string) -> boolean,
	-- tierValue("Tier3") -> comparable numeric tier value (ordering only)
	tierValue: (tier: string) -> number,
}

local ExternalAdminPerksDomain = {}

--- Resolve whether a player may use a perk. Never throws: unknown config
--- shapes resolve to denied.
function ExternalAdminPerksDomain.resolvePerk(perkConfig: any, ctx: GateContext): PerkGate
	if ctx.isStaff and ctx.staffBypass then
		return { allowed = true, reason = "staff_bypass", quota = nil }
	end
	if type(perkConfig) ~= "table" then
		return { allowed = false, reason = "not_configured" }
	end
	local tiers: { { tier: string, value: any } } = {}
	for tier, value in pairs(perkConfig) do
		if type(tier) == "string" and (type(value) == "number" or type(value) == "boolean") then
			table.insert(tiers, { tier = tier, value = value })
		end
	end
	if #tiers == 0 then
		return { allowed = false, reason = "not_configured" }
	end
	-- Descending by tier value: the highest tier the player qualifies for wins.
	table.sort(tiers, function(a, b)
		return ctx.tierValue(a.tier) > ctx.tierValue(b.tier)
	end)
	for _, entry in ipairs(tiers) do
		if ctx.hasAtLeast(entry.tier) then
			if entry.value == false then
				return { allowed = false, reason = "below_tier", minTier = entry.tier }
			end
			local quota = tonumber(entry.value)
			return {
				allowed = true,
				reason = "tier",
				tier = entry.tier,
				quota = if quota and quota > 0 then math.floor(quota) else nil,
			}
		end
	end
	return { allowed = false, reason = "below_tier", minTier = tiers[#tiers].tier }
end

--- ISO-8601 week key ("2026-W01"), Monday-based, UTC. Used both as the DataStore
--- rotation key and in buyer-facing reset messaging.
function ExternalAdminPerksDomain.isoWeekKey(unixSec: number): string
	local utc = os.date("!*t", unixSec) :: any
	-- os.date wday: Sun=1..Sat=7 → ISO weekday Mon=1..Sun=7
	local isoWday = if utc.wday == 1 then 7 else utc.wday - 1
	-- ISO week 1 is the week containing the first Thursday; anchor on this
	-- week's Thursday noon UTC (noon is immune to any date-boundary rounding).
	local thursday = os.time({
		year = utc.year,
		month = utc.month,
		day = utc.day,
		hour = 12,
	}) - (isoWday - 4) * 86400
	local thu = os.date("!*t", thursday) :: any
	local jan1 = os.time({ year = thu.year, month = 1, day = 1, hour = 12 })
	local week = math.floor((thursday - jan1) / 86400 / 7) + 1
	return string.format("%04d-W%02d", thu.year, week)
end

--- Unix timestamp of the NEXT Monday 00:00 UTC (when the current weekly quota
--- resets). Always strictly greater than unixSec.
function ExternalAdminPerksDomain.weekResetAt(unixSec: number): number
	local utc = os.date("!*t", unixSec) :: any
	local isoWday = if utc.wday == 1 then 7 else utc.wday - 1
	local midnightOffset = utc.hour * 3600 + utc.min * 60 + utc.sec
	local thisMonday = unixSec - midnightOffset - (isoWday - 1) * 86400
	return thisMonday + 7 * 86400
end

--- DataStore key fragment for one perk quota counter.
function ExternalAdminPerksDomain.quotaKey(perk: string, userId: number, weekKey: string): string
	return `perkquota:{perk}:{userId}:{weekKey}`
end

return ExternalAdminPerksDomain
