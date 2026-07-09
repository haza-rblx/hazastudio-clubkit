--!nocheck
-- ============================================================
-- REPAIR TRACK PARTS — fix double "rbxassetid://" prefix
-- ============================================================
-- KENAPA: Migrasi awal nyimpen track.parts dengan format ber-prefix
-- ("rbxassetid://123"). Padahal kit (MusicPlayerController) nambahin
-- prefix "rbxassetid://" sendiri pas bikin Sound.SoundId. Hasilnya jadi
-- dobel ("rbxassetid://rbxassetid://123") -> HTTP 404, lagu gak bunyi.
--
-- Kit native nyimpen parts sebagai ANGKA MENTAH ("123"). Script ini
-- benerin semua track yang udah terlanjur ke-commit: strip semua prefix
-- jadi angka mentah aja.
--
-- CARA PAKAI:
-- 1. Set MODE = "dry_run" -> Play (F5) -> cek Output. Lihat berapa
--    track yang bakal di-fix dan contoh before/after.
-- 2. Kalau OK, set MODE = "commit" -> Play lagi -> tulis ke DataStore.
-- 3. Stop, fresh Play, verify lagu bunyi (gak ada "Failed to load sound").
-- 4. HAPUS script ini setelah selesai.
--
-- SAFETY:
-- - Dry-run by default. Gak nyentuh DataStore kecuali MODE=="commit".
-- - IDEMPOTENT: track yang parts-nya udah angka mentah di-skip (gak diubah).
-- - Cuma nyentuh field `parts`. Field lain (id, name, creator, playlistId,
--   playbackSpeed, totalDuration, sync*) gak disentuh sama sekali.
-- - Gak ngutak-atik Playlists key sama sekali.
-- ============================================================

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- "dry_run" = preview only. "commit" = tulis ke DataStore.
local MODE: string = "commit"

-- Harus match Config.Music / MigrateMusic.
local DATASTORE_NAME = "MusicLibrary_v1"
local TRACK_KEY = "Tracks"

local LOG_PREFIX = "[RepairParts]"

local function info(msg: string, ...)
	print(LOG_PREFIX, string.format(msg, ...))
end

local function warnLog(msg: string, ...)
	warn(LOG_PREFIX, string.format(msg, ...))
end

-- Strip SEMUA occurrence prefix, sisain angka mentah aja.
-- "rbxassetid://rbxassetid://123" -> "123"
-- "rbxassetid://123"              -> "123"
-- "123"                           -> "123"
local function toRawDigits(raw: any): string?
	if raw == nil then
		return nil
	end
	local s = tostring(raw):gsub("%s", "")
	if s == "" then
		return nil
	end
	s = s:gsub("rbxassetid://", "")
	s = s:gsub("rbxasset://", "")
	s = s:gsub("rbx://", "")
	local digits = s:match("(%d+)")
	if not digits or digits == "" then
		return nil
	end
	return digits
end

local function jsonDecode(raw: string): (boolean, any)
	return pcall(function()
		return HttpService:JSONDecode(raw)
	end)
end

local function main()
	info("=== START === mode=%s", MODE)

	if MODE ~= "dry_run" and MODE ~= "commit" then
		warnLog("MODE invalid (%s). Harus 'dry_run' atau 'commit'. Abort.", MODE)
		return
	end

	if not RunService:IsServer() then
		warnLog("Butuh server context. Run dari Play Mode (F5), bukan client.")
		return
	end

	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if not ok or not store then
		warnLog("GetDataStore failed: %s", tostring(store))
		return
	end

	local getOk, raw = pcall(function()
		return store:GetAsync(TRACK_KEY)
	end)
	if not getOk then
		warnLog("GetAsync(%s) failed: %s", TRACK_KEY, tostring(raw))
		return
	end

	local tracks: { [string]: any }
	local storedAsTable = false
	if type(raw) == "string" then
		local decodeOk, decoded = jsonDecode(raw)
		if not decodeOk or type(decoded) ~= "table" then
			warnLog("JSONDecode failed for key %s", TRACK_KEY)
			return
		end
		tracks = decoded
	elseif type(raw) == "table" then
		-- Value kesimpen sebagai raw table (BUKAN JSON string). Ini format korup
		-- — MusicRepository expect JSON string, jadi dia gagal decode -> tracks=0.
		-- Kita harus re-encode jadi JSON string walaupun parts udah bersih.
		tracks = raw
		storedAsTable = true
		warnLog("Value key '%s' kesimpen sebagai RAW TABLE (format korup). Bakal di-re-encode jadi JSON string.", TRACK_KEY)
	else
		warnLog("Key %s kosong / format tak terduga (type=%s). Gak ada yang di-repair.", TRACK_KEY, typeof(raw))
		return
	end

	local total = 0
	local fixed = 0
	local alreadyClean = 0
	local emptyParts = 0
	local examplesShown = 0

	for _, track in pairs(tracks) do
		total += 1
		if type(track) == "table" and type(track.parts) == "table" then
			local newParts: { string } = {}
			local changed = false
			for i, p in ipairs(track.parts) do
				local rawDigits = toRawDigits(p)
				if rawDigits then
					newParts[i] = rawDigits
					if rawDigits ~= tostring(p) then
						changed = true
					end
				else
					-- pertahankan apa adanya kalau gak bisa di-parse (jangan buang data)
					newParts[i] = tostring(p)
				end
			end

			if #newParts == 0 then
				emptyParts += 1
			elseif changed then
				fixed += 1
				if examplesShown < 5 then
					examplesShown += 1
					info(
						"FIX '%s': '%s' -> '%s'",
						tostring(track.name),
						tostring(track.parts[1]),
						tostring(newParts[1])
					)
				end
				track.parts = newParts
			else
				alreadyClean += 1
			end
		end
	end

	info("=== SUMMARY ===")
	info("Total tracks   : %d", total)
	info("Fixed          : %d", fixed)
	info("Already clean  : %d", alreadyClean)
	info("Empty parts    : %d", emptyParts)

	if MODE == "dry_run" then
		info("DRY RUN — no writes. Set MODE='commit' untuk apply.")
		return
	end

	local needWrite = (fixed > 0) or storedAsTable
	if not needWrite then
		info("Gak ada yang perlu di-fix dan format udah JSON string. DataStore dibiarin apa adanya.")
		return
	end

	if storedAsTable then
		info("Re-encoding %d tracks jadi JSON string (benerin format korup)...", total)
	else
		info("Writing %d repaired tracks to DataStore...", fixed)
	end

	-- PENTING: MusicRepository nyimpen value sebagai JSON STRING (JSONEncode dulu),
	-- lalu JSONDecode saat baca. Jadi kita HARUS encode dulu, bukan return raw table.
	local encodeOk, encoded = pcall(function()
		return HttpService:JSONEncode(tracks)
	end)
	if not encodeOk then
		warnLog("JSONEncode failed: %s", tostring(encoded))
		return
	end

	local setOk, err = pcall(function()
		store:UpdateAsync(TRACK_KEY, function()
			return encoded
		end)
	end)
	if setOk then
		info("COMMIT SUCCESS — tracks repaired & disimpan sebagai JSON string (fixed=%d, total=%d).", fixed, total)
	else
		warnLog("COMMIT FAILED: %s", tostring(err))
	end
end

main()
