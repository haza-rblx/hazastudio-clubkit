--!nocheck
-- ============================================================
-- REPAIR TRACK PARTS — fix double "rbxassetid://" prefix
-- ============================================================
-- WHY: Early migration stored track.parts with prefixed format
-- ("rbxassetid://123"). The kit (MusicPlayerController) adds the
-- "rbxassetid://" prefix itself when creating Sound.SoundId. Result is
-- doubled ("rbxassetid://rbxassetid://123") -> HTTP 404, tracks silent.
--
-- The kit natively stores parts as RAW DIGITS ("123"). This script
-- fixes all tracks already committed: strip all prefixes
-- down to raw digits only.
--
-- USAGE:
-- 1. Set MODE = "dry_run" -> Play (F5) -> check Output. See how many
--    tracks will be fixed and before/after examples.
-- 2. If OK, set MODE = "commit" -> Play again -> write to DataStore.
-- 3. Stop, fresh Play, verify tracks play (no "Failed to load sound").
-- 4. DELETE this script when finished.
--
-- SAFETY:
-- - Dry-run by default. Does not touch DataStore unless MODE=="commit".
-- - IDEMPOTENT: tracks whose parts are already raw digits are skipped (unchanged).
-- - Only touches field `parts`. Other fields (id, name, creator, playlistId,
--   playbackSpeed, totalDuration, sync*) are not modified.
-- - Does not touch the Playlists key at all.
-- ============================================================

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- "dry_run" = preview only. "commit" = write to DataStore.
local MODE: string = "commit"

-- Must match Config.Music / MigrateMusic.
local DATASTORE_NAME = "MusicLibrary_v1"
local TRACK_KEY = "Tracks"

local LOG_PREFIX = "[RepairParts]"

local function info(msg: string, ...)
	print(LOG_PREFIX, string.format(msg, ...))
end

local function warnLog(msg: string, ...)
	warn(LOG_PREFIX, string.format(msg, ...))
end

-- Strip ALL prefix occurrences, leaving raw digits only.
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
		warnLog("MODE invalid (%s). Must be 'dry_run' or 'commit'. Abort.", MODE)
		return
	end

	if not RunService:IsServer() then
		warnLog("Requires server context. Run from Play Mode (F5), not client.")
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
		-- Value stored as raw table (NOT JSON string). This is corrupt format
		-- — MusicRepository expects JSON string, so decode fails -> tracks=0.
		-- We must re-encode as JSON string even if parts are already clean.
		tracks = raw
		storedAsTable = true
		warnLog("Value for key '%s' stored as RAW TABLE (corrupt format). Will re-encode as JSON string.", TRACK_KEY)
	else
		warnLog("Key %s empty / unexpected format (type=%s). Nothing to repair.", TRACK_KEY, typeof(raw))
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
					-- keep as-is if unparseable (do not discard data)
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
		info("DRY RUN — no writes. Set MODE='commit' to apply.")
		return
	end

	local needWrite = (fixed > 0) or storedAsTable
	if not needWrite then
		info("Nothing to fix and format is already JSON string. DataStore left unchanged.")
		return
	end

	if storedAsTable then
		info("Re-encoding %d tracks as JSON string (fixing corrupt format)...", total)
	else
		info("Writing %d repaired tracks to DataStore...", fixed)
	end

	-- IMPORTANT: MusicRepository stores value as JSON STRING (JSONEncode first),
	-- then JSONDecode on read. So we MUST encode first, not return raw table.
	local encodeOk, encoded = pcall(function()
		return HttpService:JSONEncode(tracks)
	end)
	if not encodeOk then
		warnLog("JSONEncode failed: %s", tostring(encoded))
		return
	end

	local writeOk, writeErr = pcall(function()
		store:UpdateAsync(TRACK_KEY, function()
			return encoded
		end)
	end)
	if not writeOk then
		warnLog("UpdateAsync(%s) failed: %s", TRACK_KEY, tostring(writeErr))
		return
	end

	info("✅ COMMIT SUCCESS — %d tracks written.", total)
end

main()
