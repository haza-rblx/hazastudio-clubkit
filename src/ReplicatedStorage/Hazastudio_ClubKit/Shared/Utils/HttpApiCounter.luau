--!strict
-- Shared/Utils/HttpApiCounter.lua
--
-- Per-bucket counter for Roblox HTTP API calls (GroupService:GetGroupsAsync,
-- Players:GetNameFromUserIdAsync, Players:GetUserThumbnailAsync, etc.).
-- Used by the quota-efficiency-pass-2026-06 plan (Phase 0 telemetry) to
-- measure actual call rates per function before applying wrapper/coalesce fixes.
--
-- Design:
--   - Module-level singleton state (`counters`). All callers observe the same map.
--   - `record(bucket, n?)` increments the counter for `bucket` by `n` (default 1).
--   - `snapshot()` returns a shallow copy so the caller can log without races.
--   - `reset()` clears all counters (used by tests, or to reset between telemetry runs).
--   - Auto no-op when `Config.HttpApi.COUNTERS_ENABLED` is false. The caller MAY also
--     gate the call with the same check (defensive; recommended for hot paths).
--
-- Thread safety: Roblox Luau scripts run on a single actor per script instance, so
-- no lock is needed. Snapshot() copies to a new table; concurrent record/snapshot is
-- safe because pairs() iteration over the same table is sequential.
--
-- Typical call site (server):
--   local HttpApiCounter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApiCounter)
--   if Config.HttpApi and Config.HttpApi.COUNTERS_ENABLED then
--       HttpApiCounter.record("overhead_getgroups_total")
--   end
--
-- Snapshot + log (Main.server.luau, every 60s while COUNTERS_ENABLED):
--   log:info("HttpApi counter snapshot", HttpApiCounter.snapshot())

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local HttpApiCounter = {}

-- Module-level state (process-wide singleton).
local counters: { [string]: number } = {}

-- Increment the counter for `bucket` by `n` (or 1 if n is nil).
-- No-op when the telemetry toggle is off. Safe to call from any actor.
function HttpApiCounter.record(bucket: string, n: number?): ()
	if not (Config.HttpApi and Config.HttpApi.COUNTERS_ENABLED) then
		return
	end
	counters[bucket] = (counters[bucket] or 0) + (n or 1)
end

-- Return a shallow copy of all bucket counters. The caller can iterate/send
-- without worrying about concurrent mutations.
function HttpApiCounter.snapshot(): { [string]: number }
	return table.clone(counters) :: { [string]: number }
end

-- Clear all counters. Used by tests and by the periodic log emitter if you want
-- a "per-interval" reading (record rate, not cumulative). Default usage is
-- cumulative since server start.
function HttpApiCounter.reset(): ()
	counters = {}
end

return HttpApiCounter
