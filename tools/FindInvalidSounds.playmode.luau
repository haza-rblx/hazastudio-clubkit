--!nocheck
-- ============================================================
-- Find invalid / blocked Sound asset sources (Play Mode)
-- ============================================================
-- PENTING: Command Bar harus di context SERVER (bukan Client).
--   Command Bar > dropdown kiri > pilih "Server"
--   Lalu paste script ini > Enter
--
-- Hasil:
--   1. Output window (tab Server) — filter: FindInvalidSounds
--   2. ServerStorage.FindInvalidSoundsReport (StringValue, bisa dibaca di Explorer)
-- ============================================================

local RunService = game:GetService("RunService")
if not RunService:IsServer() then
	warn("[FindInvalidSounds] SALAH CONTEXT — pilih Server di Command Bar, bukan Client/All")
	return
end

local TARGET_IDS = {
	"8578316223",
	"9009370950",
	"93611960870847",
}

local targetSet: { [string]: boolean } = {}
for _, id in ipairs(TARGET_IDS) do
	targetSet[id] = true
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
pcall(function()
	local sanitizer = require(ReplicatedStorage.Shared.Utils.SoundAssetSanitizer)
	if sanitizer.getBlockedSoundIds then
		for _, id in ipairs(sanitizer.getBlockedSoundIds()) do
			targetSet[id] = true
		end
	end
end)

local function normalizeAssetId(value: any): string
	local text = tostring(value or "")
	local id = string.match(text, "(%d+)")
	return id or ""
end

local function isTarget(value: any): boolean
	local id = normalizeAssetId(value)
	return id ~= "" and targetSet[id] == true
end

local hits: { string } = {}

local function report(kind: string, detail: string)
	local line = string.format("[%s] %s", kind, detail)
	table.insert(hits, line)
	print("[FindInvalidSounds] " .. line)
end

local function saveReport()
	local folder = game:GetService("ServerStorage"):FindFirstChild("FindInvalidSoundsReport")
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "FindInvalidSoundsReport"
	folder.Parent = game:GetService("ServerStorage")

	local summary = Instance.new("StringValue")
	summary.Name = "Summary"
	summary.Value = table.concat(hits, "\n")
	summary.Parent = folder

	local meta = Instance.new("StringValue")
	meta.Name = "Meta"
	meta.Value = string.format(
		"generatedAt=%s\nhitCount=%d\ntargetIds=%s",
		os.date("%Y-%m-%d %H:%M:%S"),
		#hits,
		table.concat(TARGET_IDS, ", ")
	)
	meta.Parent = folder

	for index, line in ipairs(hits) do
		local entry = Instance.new("StringValue")
		entry.Name = string.format("%03d_%s", index, string.match(line, "^%[([^%]]+)%]") or "LINE")
		entry.Value = line
		entry.Parent = folder
	end

	report("REPORT", "Saved to ServerStorage.FindInvalidSoundsReport (Summary + per-line StringValues)")
end

report("META", "Running on Server — scan place + DataStore")

-- 1) Scan semua Sound instance
report("SCAN", "Scanning existing Sound instances...")
for _, inst in ipairs(game:GetDescendants()) do
	if inst:IsA("Sound") and isTarget(inst.SoundId) then
		report("SOUND_INSTANCE", inst:GetFullName() .. " | SoundId=" .. tostring(inst.SoundId))
	end
end

-- 2) Scan string / attribute
report("SCAN", "Scanning rbxassetid strings in descendants...")
for _, inst in ipairs(game:GetDescendants()) do
	if not inst:IsA("Sound") then
		local ok, value = pcall(function()
			return (inst :: any).Value
		end)
		if ok and type(value) == "string" and isTarget(value) then
			report("STRING_PROP", inst:GetFullName() .. ".Value = " .. value)
		end
		for attrName, attrValue in pairs(inst:GetAttributes()) do
			if type(attrValue) == "string" and isTarget(attrValue) then
				report("ATTRIBUTE", inst:GetFullName() .. " @" .. attrName .. " = " .. attrValue)
			end
		end
	end
end

-- 3) Runtime Sound (music prefetch, donation VFX)
local SoundService = game:GetService("SoundService")
SoundService.ChildAdded:Connect(function(child)
	if not child:IsA("Sound") then
		return
	end
	task.defer(function()
		if not child.Parent or not isTarget(child.SoundId) then
			return
		end
		report(
			"DYNAMIC_SOUND",
			child:GetFullName()
				.. " | SoundId="
				.. tostring(child.SoundId)
				.. "\n"
				.. debug.traceback("created here", 2)
		)
		saveReport()
	end)
end)

-- 4) Asset fetch failure hook
local ContentProvider = game:GetService("ContentProvider")
if ContentProvider.AssetFetchFailed then
	ContentProvider.AssetFetchFailed:Connect(function(assetId: string, errorMessage: string)
		if isTarget(assetId) then
			report(
				"ASSET_FETCH_FAILED",
				tostring(assetId) .. " | " .. tostring(errorMessage) .. "\n" .. debug.traceback("fetch failed", 2)
			)
			saveReport()
		end
	end)
	report("HOOK", "ContentProvider.AssetFetchFailed listener active")
else
	report("HOOK", "AssetFetchFailed not available")
end

local function scanTrackBucket(label: string, tracks: { [string]: any }?)
	if type(tracks) ~= "table" then
		return 0
	end
	local found = 0
	for trackId, track in pairs(tracks) do
		if type(track) == "table" and type(track.parts) == "table" then
			for partIndex, assetId in ipairs(track.parts) do
				if isTarget(assetId) then
					found += 1
					report(
						"MUSIC_TRACK",
						string.format(
							"%s trackId=%s name=%s playlistId=%s part[%d]=%s",
							label,
							tostring(trackId),
							tostring(track.name or "?"),
							tostring(track.playlistId or "?"),
							partIndex,
							tostring(assetId)
						)
					)
				end
			end
		end
	end
	return found
end

-- 5) MusicRepository (active + tombstone tracks)
local okMusic, musicErr = pcall(function()
	local ServerScriptService = game:GetService("ServerScriptService")
	local repoModule = ServerScriptService:WaitForChild("Server", 5):WaitForChild("Repositories", 5)
	local MusicRepository = require(repoModule:WaitForChild("MusicRepository"))
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Config = require(ReplicatedStorage.Shared.Constants.Config)
	local Logger = require(ReplicatedStorage.Shared.Utils.Logger)
	local musicConfig = Config.Music
	if type(musicConfig) ~= "table" then
		error("Config.Music missing")
	end
	local repo = MusicRepository.new({
		config = musicConfig,
		logger = Logger.new("FindInvalidSounds.MusicRepo"),
	})
	local loadResult = repo:loadAll()
	if not loadResult.ok then
		error("loadAll failed: " .. tostring((loadResult :: any).error))
	end
	local tracksResult = repo:getTracks()
	if not tracksResult.ok or type(tracksResult.value) ~= "table" then
		error("getTracks failed: " .. tostring((tracksResult :: any).error))
	end
	local activeFound = scanTrackBucket("active", tracksResult.value)
	local tombstoneFound = scanTrackBucket("tombstone", (repo :: any)._trackTombstones)
	local total = activeFound + tombstoneFound
	if total == 0 then
		report("MUSIC", "No target IDs in MusicRepository (active or tombstone)")
	else
		report("MUSIC", string.format("Found %d part(s): active=%d tombstone=%d", total, activeFound, tombstoneFound))
	end
end)

if not okMusic then
	report("MUSIC", "MusicRepository scan failed: " .. tostring(musicErr))
end

local findingCount = 0
for _, line in ipairs(hits) do
	if not line:match("^%[SCAN%]") and not line:match("^%[HOOK%]") and not line:match("^%[META%]") and not line:match("^%[DONE%]") and not line:match("^%[REPORT%]") and not line:match("^%[MUSIC%] No target") then
		if line:match("^%[SOUND_INSTANCE%]") or line:match("^%[MUSIC_TRACK%]") or line:match("^%[STRING_PROP%]") or line:match("^%[ATTRIBUTE%]") or line:match("^%[DYNAMIC_SOUND%]") or line:match("^%[ASSET_FETCH_FAILED%]") or (line:match("^%[MUSIC%]") and line:match("Found %d")) then
			findingCount += 1
		end
	end
end

report("DONE", string.format("Scan complete. Real findings=%d. Report folder updated.", findingCount))
saveReport()
