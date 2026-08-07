--!nocheck
-- ============================================================
-- ROBUX LEADERBOARD MIGRATION (LEGACY -> NEW SYSTEM)  v2
-- ============================================================
-- Migrate per-user total Robux donations from legacy DataStore to
-- the new system DataStore. DataStores are per-UNIVERSE, so this script
-- (run in a new place, same universe) can read legacy keys.
--
-- SOURCE (legacy): OrderedDataStore "RobuxLstatsData"  key=userId value=robux
-- TARGET (new):    OrderedDataStore "RobuxDonationLeaderboard_User_v1"
--                  DataStore        "DonationLeaderboardMetadata_v1" (optional)
--
-- ============================================================
-- v2 CHANGES (important — read):
--   Legacy dataset is VERY large (>11,000 entries). Migrating all one-by-one
--   via SetAsync is not realistic (DataStore budget ~70 writes/min) and
--   triggers TooManyRequests. Leaderboard only shows TOP N, and the new
--   system repo resolves names on read. Therefore:
--     - Default migrates only TOP `MAX_ENTRIES` spenders (enough for leaderboard).
--     - DRY-RUN no longer reads target store (old bug: GetAsync per entry).
--     - All calls go through BUDGET GATE (wait when budget exhausted).
--     - Metadata default OFF (repo self-heals names on read). Enable if
--       you want cached names for top entries.
--
-- BEFORE RUN:
--   * DISABLE third-party "VIDEOSCREEN LICENSE" script first — in testing
--     it SHUTDOWN the server mid-migration (license verification failed).
--     Disable/remove temporarily so migration is not interrupted.
--   * Game Settings > Security > Enable Studio Access to API Services = ON.
--   * Run in PLAY MODE (F5), not Edit.
--
-- USAGE:
--   1. MODE="dry_run" -> check count & top preview (no writes).
--   2. MODE="commit"  -> write to new store. Idempotent (safe re-run).
--   3. Remove script when finished.
-- ============================================================

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- ============================================================
-- CONFIG
-- ============================================================
local MODE: string = "commit" -- "dry_run" | "commit"
local STRATEGY: string = "max" -- "max" | "overwrite" | "skip_existing"

-- Migrate only TOP N spenders (enough for leaderboard + significant donors).
-- OrderedDataStore desc, so this reads from highest values first.
-- Set 0 to migrate ALL (NOT recommended: >11k entries, severe throttling,
-- but takes hours + multiple sessions).
local MAX_ENTRIES = 500

-- Skip entries below this value (small donations, not important for boards).
local MIN_VALUE = 1

-- Write username metadata for migrated entries. Default false:
-- new system repo resolves names automatically on read (self-heal). Set true
-- only if you want cached names (adds ~2 API calls per entry).
local WRITE_METADATA = false

-- Store names (must match Config.Leaderboards in new system).
local LEGACY_ROBUX_STORE = "RobuxLstatsData"
local NEW_ROBUX_STORE = "RobuxDonationLeaderboard_User_v1"
local NEW_METADATA_STORE = "DonationLeaderboardMetadata_v1"

local PAGE_SIZE = 100
local BUDGET_WAIT = 4 -- seconds to wait when budget is exhausted

-- ============================================================
-- STATE
-- ============================================================
local stats = {
	read = 0,
	considered = 0,
	migrated = 0,
	skippedZero = 0,
	skippedExisting = 0,
	unchanged = 0,
	metaWritten = 0,
	errors = 0,
}
local LOG = "[RobuxMigration]"
local function info(msg, ...) print(LOG, string.format(msg, ...)) end
local function warnLog(msg, ...) warn(LOG, string.format(msg, ...)); stats.errors += 1 end

-- ============================================================
-- BUDGET GATE
-- ============================================================
local function waitForBudget(requestType, label)
	local guard = 0
	while DataStoreService:GetRequestBudgetForRequestType(requestType) < 1 do
		guard += 1
		if guard == 1 then
			info("Budget %s exhausted, waiting...", label)
		end
		task.wait(BUDGET_WAIT)
		if guard > 60 then -- ~4 minutes, breathe
			info("Still waiting for budget %s (%ds elapsed)...", label, guard * BUDGET_WAIT)
			guard = 1
		end
	end
end

-- ============================================================
-- STORES
-- ============================================================
local function getStores()
	if not RunService:IsServer() then
		warnLog("Requires server context. Run from Play Mode (F5).")
		return nil
	end
	local okL, legacy = pcall(function()
		return DataStoreService:GetOrderedDataStore(LEGACY_ROBUX_STORE)
	end)
	if not okL then
		warnLog("GetOrderedDataStore(legacy) failed: %s", tostring(legacy))
		return nil
	end
	return {
		legacy = legacy,
		new = DataStoreService:GetOrderedDataStore(NEW_ROBUX_STORE),
		meta = DataStoreService:GetDataStore(NEW_METADATA_STORE),
	}
end

-- ============================================================
-- READ TOP-N (budget-aware, stops after MAX_ENTRIES)
-- ============================================================
local function readTopLegacy(legacyStore)
	local results = {}
	waitForBudget(Enum.DataStoreRequestType.GetSortedAsync, "GetSortedAsync")
	local ok, pages = pcall(function()
		return legacyStore:GetSortedAsync(false, PAGE_SIZE) -- desc
	end)
	if not ok then
		warnLog("GetSortedAsync(legacy) failed: %s", tostring(pages))
		return results
	end

	local cap = (MAX_ENTRIES > 0) and MAX_ENTRIES or math.huge
	while true do
		local page = pages:GetCurrentPage()
		for _, entry in ipairs(page) do
			local userId = tonumber(entry.key)
			local value = tonumber(entry.value) or 0
			if userId then
				table.insert(results, { userId = userId, value = value })
				stats.read += 1
			end
			if #results >= cap then
				return results
			end
		end
		if pages.IsFinished then
			break
		end
		-- Budget-gated pagination + delay to avoid throttling.
		waitForBudget(Enum.DataStoreRequestType.GetSortedAsync, "GetSortedAsync(page)")
		task.wait(0.2)
		local advOk, advErr = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if not advOk then
			warnLog("AdvanceToNextPageAsync stopped: %s", tostring(advErr))
			break
		end
	end
	return results
end

-- ============================================================
-- WRITE HELPERS (budget-gated)
-- ============================================================
local function readExisting(newStore, userId)
	waitForBudget(Enum.DataStoreRequestType.GetAsync, "GetAsync")
	local ok, existing = pcall(function()
		return newStore:GetAsync(tostring(userId))
	end)
	return (ok and tonumber(existing)) or 0
end

local function writeValue(newStore, userId, value)
	waitForBudget(Enum.DataStoreRequestType.SetIncrementSortedAsync, "SetSorted")
	local ok, err = pcall(function()
		newStore:SetAsync(tostring(userId), value)
	end)
	if not ok then
		warnLog("SetAsync(%d) failed: %s", userId, tostring(err))
		return false
	end
	return true
end

local function writeMetadata(metaStore, userId)
	local okN, username = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if not okN or type(username) ~= "string" or username == "" then
		return false
	end
	local thumb = ""
	local okT, content = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	if okT and type(content) == "string" then
		thumb = content
	end
	waitForBudget(Enum.DataStoreRequestType.UpdateAsync, "UpdateAsync(meta)")
	local ok, err = pcall(function()
		metaStore:UpdateAsync("user:" .. tostring(userId), function()
			return {
				userId = userId,
				username = username,
				displayName = username,
				thumbnail = thumb,
				updatedAt = os.time(),
			}
		end)
	end)
	if not ok then
		warnLog("Metadata(%d) failed: %s", userId, tostring(err))
		return false
	end
	return true
end

-- ============================================================
-- MAIN
-- ============================================================
local function main()
	info("=== START === mode=%s strategy=%s maxEntries=%s meta=%s",
		MODE, STRATEGY, tostring(MAX_ENTRIES), tostring(WRITE_METADATA))
	if MODE ~= "dry_run" and MODE ~= "commit" then
		warnLog("MODE invalid. Abort."); return
	end
	if STRATEGY ~= "max" and STRATEGY ~= "overwrite" and STRATEGY ~= "skip_existing" then
		warnLog("STRATEGY invalid. Abort."); return
	end

	local stores = getStores()
	if not stores then return end

	info("Reading top %s from '%s'...", (MAX_ENTRIES > 0 and tostring(MAX_ENTRIES) or "ALL"), LEGACY_ROBUX_STORE)
	local entries = readTopLegacy(stores.legacy)
	info("Read %d entries (sorted desc).", #entries)

	info("--- Top 10 preview ---")
	for i = 1, math.min(10, #entries) do
		info("  #%d userId=%d robux=%d", i, entries[i].userId, entries[i].value)
	end

	for _, e in ipairs(entries) do
		if e.value < MIN_VALUE then
			stats.skippedZero += 1
			continue
		end
		stats.considered += 1

		if MODE == "dry_run" then
			-- Do not touch target store at all.
			stats.migrated += 1
			continue
		end

		-- COMMIT
		local target = e.value
		if STRATEGY == "overwrite" then
			target = e.value
		else
			local existing = readExisting(stores.new, e.userId)
			if STRATEGY == "skip_existing" and existing > 0 then
				stats.skippedExisting += 1
				continue
			end
			if STRATEGY == "max" then
				target = math.max(existing, e.value)
				if target == existing and existing > 0 then
					stats.unchanged += 1
					continue
				end
			end
		end

		if writeValue(stores.new, e.userId, target) then
			stats.migrated += 1
			if stats.migrated % 25 == 0 then
				info("Progress: %d/%d written...", stats.migrated, stats.considered)
			end
			if WRITE_METADATA and writeMetadata(stores.meta, e.userId) then
				stats.metaWritten += 1
			end
		end
	end

	info("=== SUMMARY ===")
	info("Read            : %d", stats.read)
	info("Considered      : %d", stats.considered)
	info("Migrated        : %d", stats.migrated)
	info("Skipped (zero)  : %d", stats.skippedZero)
	info("Skipped (exist) : %d", stats.skippedExisting)
	info("Unchanged (max) : %d", stats.unchanged)
	info("Metadata written: %d", stats.metaWritten)
	info("Errors          : %d", stats.errors)
	if MODE == "dry_run" then
		info("DRY RUN complete — no writes. Set MODE='commit' to apply.")
	else
		info("COMMIT complete. Check Robux leaderboard in game.")
	end
end

main()
