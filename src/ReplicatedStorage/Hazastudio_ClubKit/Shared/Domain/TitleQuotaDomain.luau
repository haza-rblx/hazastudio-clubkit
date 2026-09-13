--!strict
-- Shared/Domain/TitleQuotaDomain.luau
-- Rolling-window quota for self-service custom title changes (Features.SelfCustomTitle).
--
-- Pure: no Roblox services and no Config require — the caller passes
-- ClubKitConfig.CustomTitle in, so the same logic runs on the server, in the
-- client panel (to paint the quota label) and in a headless harness.
--
-- History is a list of epoch seconds, one per spent change. It is read straight
-- back from the player's stored overhead data, so every entry is treated as
-- untrusted: non-numbers are dropped rather than trusted or errored on.

local TitleQuotaDomain = {}

local SECONDS_PER_DAY = 86400
-- Used when ClubKitConfig.CustomTitle is missing or malformed; mirrors the
-- schema defaults so a broken buyer config degrades instead of unlocking.
local FALLBACK_MAX = 5
local FALLBACK_WINDOW_DAYS = 7

export type QuotaConfig = {
	MaxChangesPerWindow: number?,
	WindowDays: number?,
	-- false runs the feature with no rolling limit. Opt-in: only the boolean
	-- `false` turns it off, so a typo or a stray string cannot unlock it.
	QuotaEnabled: boolean?,
}

export type QuotaState = {
	allowed: boolean,
	remaining: number,
	-- When the oldest spent change ages out and a slot returns. nil when the
	-- player has spent nothing, so there is nothing to wait for.
	resetsAt: number?,
	-- The limit is switched off: `remaining` is not a countdown and callers should
	-- say so rather than print a number that never moves.
	unlimited: boolean,
}

local function resolveMax(cfg: any): number
	local raw = if type(cfg) == "table" then tonumber(cfg.MaxChangesPerWindow) else nil
	if raw == nil then
		return FALLBACK_MAX
	end
	-- A buyer writing 0 (or a negative) would lock the feature out entirely
	-- while the panel still shows as unlocked; clamp instead.
	return math.max(1, math.floor(raw))
end

-- Only a literal `false` disables the quota. Anything else — nil, a string, a
-- number a buyer typed instead of a boolean — leaves it enforced.
local function isQuotaOff(cfg: any): boolean
	return type(cfg) == "table" and cfg.QuotaEnabled == false
end

local function resolveWindowSeconds(cfg: any): number
	local raw = if type(cfg) == "table" then tonumber(cfg.WindowDays) else nil
	local days = if raw == nil then FALLBACK_WINDOW_DAYS else math.max(1, math.floor(raw))
	return days * SECONDS_PER_DAY
end

-- Timestamps still inside the window, oldest first. An entry exactly `window`
-- old has aged out. Future stamps (only reachable through a server-side clock
-- jump) still count, so a skew can never hand out extra changes.
local function activeEntries(history: any, now: number, window: number): { number }
	local active: { number } = {}
	if type(history) ~= "table" then
		return active
	end
	local cutoff = now - window
	for _, entry in pairs(history) do
		if type(entry) == "number" and entry == entry and entry > cutoff then
			table.insert(active, entry)
		end
	end
	table.sort(active)
	return active
end

-- Read-only: what the player may do right now. Drives both the server's accept
-- or reject and the panel's quota label.
function TitleQuotaDomain.evaluate(history: any, now: number, cfg: QuotaConfig?): QuotaState
	local max = resolveMax(cfg)
	if isQuotaOff(cfg) then
		-- `remaining` is still a positive number so an older caller that only reads
		-- `remaining > 0` keeps working; `unlimited` is what callers should show.
		return {
			allowed = true,
			remaining = max,
			resetsAt = nil,
			unlimited = true,
		}
	end
	local active = activeEntries(history, now, resolveWindowSeconds(cfg))
	local remaining = math.max(0, max - #active)
	return {
		allowed = remaining > 0,
		remaining = remaining,
		resetsAt = if #active > 0 then active[1] + resolveWindowSeconds(cfg) else nil,
		unlimited = false,
	}
end

-- The history to store after a change is accepted: expired stamps pruned, `now`
-- appended, and the list capped at `max` so a long-lived profile cannot grow it
-- without bound. Call only after evaluate() allowed the change.
--
-- With the limit off nothing is banked — the stored list is returned untouched.
-- A change that was free when it was made should not count against the quota if
-- the buyer switches the limit back on later.
function TitleQuotaDomain.record(history: any, now: number, cfg: QuotaConfig?): { number }
	local max = resolveMax(cfg)
	if isQuotaOff(cfg) then
		local kept: { number } = {}
		if type(history) == "table" then
			for _, entry in pairs(history) do
				if type(entry) == "number" and entry == entry then
					table.insert(kept, entry)
				end
			end
			table.sort(kept)
		end
		return kept
	end
	local active = activeEntries(history, now, resolveWindowSeconds(cfg))
	table.insert(active, now)
	while #active > max do
		table.remove(active, 1)
	end
	return active
end

return TitleQuotaDomain
