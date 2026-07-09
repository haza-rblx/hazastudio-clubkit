--!nocheck
-- ============================================================
-- ROBUX LEADERBOARD MIGRATION (LEGACY -> NEW SYSTEM)  v2
-- ============================================================
-- Pindahkan total donasi Robux per-user dari DataStore legacy ke
-- DataStore new system. DataStore per-UNIVERSE, jadi script ini
-- (dijalankan di place baru, universe sama) bisa baca key legacy.
--
-- SUMBER  (legacy): OrderedDataStore "RobuxLstatsData"  key=userId value=robux
-- TUJUAN  (new):    OrderedDataStore "RobuxDonationLeaderboard_User_v1"
--                   DataStore        "DonationLeaderboardMetadata_v1" (opsional)
--
-- ============================================================
-- PERUBAHAN v2 (penting, baca):
--   Dataset legacy SANGAT besar (>11.000 entry). Migrasi semua satu-satu
--   via SetAsync tidak realistis (budget DataStore ~70 write/menit) dan
--   memicu TooManyRequests. Leaderboard hanya menampilkan TOP N, dan repo
--   new system resolve nama saat read. Jadi:
--     - Default migrasi hanya TOP `MAX_ENTRIES` spender (cukup utk leaderboard).
--     - DRY-RUN tidak lagi membaca store tujuan (dulu bug: GetAsync per entry).
--     - Semua call dilewatkan BUDGET GATE (nunggu kalau budget habis).
--     - Metadata default OFF (repo self-heal nama saat read). Nyalakan kalau
--       mau nama ter-cache utk top entries.
--
-- SEBELUM RUN:
--   * MATIKAN dulu script pihak ketiga "VIDEOSCREEN LICENSE" — di test
--     terakhir dia SHUTDOWN server di tengah migrasi (gagal verifikasi
--     lisensi). Disable/keluarkan sementara biar migrasi tidak terputus.
--   * Game Settings > Security > Enable Studio Access to API Services = ON.
--   * Jalankan di PLAY MODE (F5), bukan Edit.
--
-- CARA PAKAI:
--   1. MODE="dry_run" -> cek jumlah & Top preview (tanpa write apa pun).
--   2. MODE="commit"  -> tulis ke store baru. Idempotent (aman re-run).
--   3. Hapus script setelah selesai.
-- ============================================================

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- ============================================================
-- CONFIG
-- ============================================================
local MODE: string = "commit" -- "dry_run" | "commit"
local STRATEGY: string = "max" -- "max" | "overwrite" | "skip_existing"

-- Hanya migrasi TOP N spender (cukup untuk leaderboard + donor signifikan).
-- OrderedDataStore desc, jadi ini baca dari nilai tertinggi.
-- Set 0 untuk migrasi SEMUA (TIDAK disarankan: >11k entry, throttle parah,
-- butuh berjam-jam + beberapa sesi).
local MAX_ENTRIES = 500

-- Abaikan entry di bawah nilai ini (donasi receh, tidak penting untuk board).
local MIN_VALUE = 1

-- Tulis metadata username utk entry yang dimigrasi. Default false:
-- repo new system resolve nama otomatis saat read (self-heal). Set true
-- hanya kalau mau nama ter-cache (menambah ~2 API call per entry).
local WRITE_METADATA = false

-- Store names (harus match Config.Leaderboards di new system).
local LEGACY_ROBUX_STORE = "RobuxLstatsData"
local NEW_ROBUX_STORE = "RobuxDonationLeaderboard_User_v1"
local NEW_METADATA_STORE = "DonationLeaderboardMetadata_v1"

local PAGE_SIZE = 100
local BUDGET_WAIT = 4 -- detik tunggu kalau budget habis

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
			info("Budget %s habis, menunggu...", label)
		end
		task.wait(BUDGET_WAIT)
		if guard > 60 then -- ~4 menit, kasih napas
			info("Masih menunggu budget %s (sudah %ds)...", label, guard * BUDGET_WAIT)
			guard = 1
		end
	end
end

-- ============================================================
-- STORES
-- ============================================================
local function getStores()
	if not RunService:IsServer() then
		warnLog("Butuh server context. Run dari Play Mode (F5).")
		return nil
	end
	local okL, legacy = pcall(function()
		return DataStoreService:GetOrderedDataStore(LEGACY_ROBUX_STORE)
	end)
	if not okL then
		warnLog("GetOrderedDataStore(legacy) gagal: %s", tostring(legacy))
		return nil
	end
	return {
		legacy = legacy,
		new = DataStoreService:GetOrderedDataStore(NEW_ROBUX_STORE),
		meta = DataStoreService:GetDataStore(NEW_METADATA_STORE),
	}
end

-- ============================================================
-- READ TOP-N (budget-aware, berhenti setelah MAX_ENTRIES)
-- ============================================================
local function readTopLegacy(legacyStore)
	local results = {}
	waitForBudget(Enum.DataStoreRequestType.GetSortedAsync, "GetSortedAsync")
	local ok, pages = pcall(function()
		return legacyStore:GetSortedAsync(false, PAGE_SIZE) -- desc
	end)
	if not ok then
		warnLog("GetSortedAsync(legacy) gagal: %s", tostring(pages))
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
		-- Budget-gated pagination + jeda biar tidak throttle.
		waitForBudget(Enum.DataStoreRequestType.GetSortedAsync, "GetSortedAsync(page)")
		task.wait(0.2)
		local advOk, advErr = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if not advOk then
			warnLog("AdvanceToNextPageAsync berhenti: %s", tostring(advErr))
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
		warnLog("SetAsync(%d) gagal: %s", userId, tostring(err))
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
		warnLog("Metadata(%d) gagal: %s", userId, tostring(err))
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

	info("Membaca top %s dari '%s'...", (MAX_ENTRIES > 0 and tostring(MAX_ENTRIES) or "ALL"), LEGACY_ROBUX_STORE)
	local entries = readTopLegacy(stores.legacy)
	info("Terbaca %d entry (sudah terurut desc).", #entries)

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
			-- Tidak menyentuh store tujuan sama sekali.
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
				info("Progress: %d/%d ditulis...", stats.migrated, stats.considered)
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
		info("DRY RUN selesai — tidak ada write. Set MODE='commit' untuk apply.")
	else
		info("COMMIT selesai. Cek leaderboard Robux di game.")
	end
end

main()
