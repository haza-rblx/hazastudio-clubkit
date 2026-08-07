--!nocheck
--[[
  ONE-TIME LEADERBOARD SEEDER (third-party / standalone)
  ====================================================
  Third-party script — NOT part of Hazastudio_ClubKit runtime.
  Writes manual seed data to leaderboard DataStores: Cash (IDR), Robux, Likes.

  USAGE:
    1. Copy folder `tools/OneTimeLeaderboardSeeder/` to ServerScriptService.
    2. Edit `LeaderboardSeedData.luau` (userId/username + values).
    3. Game Settings > Security > Enable Studio Access to API Services = ON.
    4. Set ENABLED = true, MODE = "dry_run" → Play (F5) → check output.
    5. MODE = "commit" → Play again → verify boards in-game.
    6. Set ENABLED = false or delete this folder when done.

  AFTER COMMIT:
    - Restart server (or re-publish) so DonationService hydrates the manual cash map.
    - In-game: /refreshleaderboard all (owner) to refresh client boards.

  DATASTORE KEYS (must match Config.luau Club Kit):
    - Cash manual : DataStore  ManualBagibagiAdjustments_v1  (doc key manual_v1)
    - Robux board : OrderedDS RobuxDonationLeaderboard_User_v1
    - Likes board : OrderedDS AvatarLikesLeaderboard_v1
    - Likes count : DataStore  AvatarLikes_v1  key likes:summary:{userId}
    - Metadata    : DataStore  DonationLeaderboardMetadata_v1  key user:{userId}

-- Studio isolation: default Studio_ prefix (same as Config USE_STUDIO_DATASTORE_ISOLATION).
-- Set USE_STUDIO_DATASTORE_ISOLATION = false ONLY when intentionally writing live keys from Studio.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")

-- =============================================================================
-- CONFIG — disable after use
-- =============================================================================
local ENABLED = false -- true = run seeder on server boot
local MODE = "dry_run" -- "dry_run" | "commit"

-- Studio isolation: keep false so seeder writes the same live keys as Config (production).
local USE_STUDIO_DATASTORE_ISOLATION = false

local SEED_CASH = true
local SEED_ROBUX = true
local SEED_LIKES = true

-- "set" = write absolute value | "max" = max(with existing) | "add" = add to existing
local STRATEGY = "set"

local WRITE_METADATA = true -- username/thumbnail in DonationLeaderboardMetadata_v1
local PACE_SECONDS = 0.12 -- delay between writes (avoid throttle)
local BUDGET_WAIT = 4

-- Base production keys (scoped below when Studio isolation is on)
local KEY_MANUAL_CASH = "ManualBagibagiAdjustments_v1"
local KEY_ROBUX_ORDERED = "RobuxDonationLeaderboard_User_v1"
local KEY_LIKES_ORDERED = "AvatarLikesLeaderboard_v1"
local KEY_LIKES_SUMMARY = "AvatarLikes_v1"
local KEY_METADATA = "DonationLeaderboardMetadata_v1"
local MANUAL_CASH_DOCUMENT = "manual_v1"

-- =============================================================================
local LOG = "[LeaderboardSeeder]"
local stats = {
	cashEntries = 0,
	robuxEntries = 0,
	likesEntries = 0,
	written = 0,
	skipped = 0,
	errors = 0,
}

local function info(msg: string, ...)
	print(LOG, string.format(msg, ...))
end

local function warnLog(msg: string, ...)
	warn(LOG, string.format(msg, ...))
	stats.errors += 1
end

local function scopedKey(baseKey: string): string
	if USE_STUDIO_DATASTORE_ISOLATION and RunService:IsStudio() then
		return "Studio_" .. baseKey
	end
	return baseKey
end

local function waitForBudget(requestType: Enum.DataStoreRequestType, label: string)
	local guard = 0
	while DataStoreService:GetRequestBudgetForRequestType(requestType) < 1 do
		guard += 1
		if guard == 1 then
			info("Budget %s exhausted, waiting...", label)
		end
		task.wait(BUDGET_WAIT)
	end
end

local function resolveUserId(entry: any): number?
	if type(entry) ~= "table" then
		return nil
	end
	local userId = tonumber(entry.userId)
	if userId and userId > 0 then
		return userId
	end
	local username = entry.username
	if type(username) == "string" and username ~= "" then
		local ok, resolved = pcall(function()
			return Players:GetUserIdFromNameAsync(username)
		end)
		if ok and type(resolved) == "number" and resolved > 0 then
			return resolved
		end
	end
	return nil
end

local function pickAmount(entry: any, fieldName: string): number
	if type(entry) ~= "table" then
		return 0
	end
	local raw = entry[fieldName]
	if raw == nil and fieldName ~= "amount" then
		raw = entry.amount
	end
	return math.max(0, math.floor(tonumber(raw) or 0))
end

local function mergeValue(strategy: string, existing: number, target: number): number
	if strategy == "add" then
		return existing + target
	end
	if strategy == "max" then
		return math.max(existing, target)
	end
	return target
end

local function getUserIdentity(userId: number): (string, string)
	local username = "User" .. tostring(userId)
	local displayName = username
	-- Players:GetUserDisplayNameAsync does not exist — use UserService (same as Club Kit).
	local okInfos, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync({ userId })
	end)
	if okInfos and type(infos) == "table" then
		for _, info in ipairs(infos) do
			if type(info) == "table" and tonumber(info.Id) == userId then
				if type(info.Username) == "string" and info.Username ~= "" then
					username = info.Username
				end
				if type(info.DisplayName) == "string" and info.DisplayName ~= "" then
					displayName = info.DisplayName
				else
					displayName = username
				end
				return username, displayName
			end
		end
	end
	local okName, resolvedName = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if okName and type(resolvedName) == "string" and resolvedName ~= "" then
		username = resolvedName
		displayName = resolvedName
	end
	return username, displayName
end

local function getUserThumbnail(userId: number): string
	local ok, content = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	if ok and type(content) == "string" then
		return content
	end
	return ""
end

local function writeMetadata(metaStore: GlobalDataStore, userId: number): boolean
	if not WRITE_METADATA then
		return false
	end
	local username, displayName = getUserIdentity(userId)
	local thumbnail = getUserThumbnail(userId)
	waitForBudget(Enum.DataStoreRequestType.UpdateAsync, "UpdateAsync(meta)")
	local ok, err = pcall(function()
		metaStore:UpdateAsync("user:" .. tostring(userId), function()
			return {
				userId = userId,
				username = username,
				displayName = displayName,
				thumbnail = thumbnail,
				displayNameVerified = true,
				updatedAt = os.time(),
			}
		end)
	end)
	if not ok then
		warnLog("Metadata userId=%d failed: %s", userId, tostring(err))
		return false
	end
	return true
end

local function loadSeedData(): any?
	local parent = script.Parent
	local module = parent and parent:FindFirstChild("LeaderboardSeedData")
	if not module or not module:IsA("ModuleScript") then
		warnLog("LeaderboardSeedData ModuleScript not found at %s", tostring(parent))
		return nil
	end
	local ok, data = pcall(require, module)
	if not ok then
		warnLog("require LeaderboardSeedData failed: %s", tostring(data))
		return nil
	end
	if type(data) ~= "table" then
		warnLog("LeaderboardSeedData must return a table")
		return nil
	end
	return data
end

local function seedCash(data: any)
	if not SEED_CASH then
		info("Cash: SKIP (SEED_CASH = false)")
		return
	end
	local entries = data.Cash
	if type(entries) ~= "table" or #entries == 0 then
		info("Cash: no entries in LeaderboardSeedData.Cash")
		return
	end

	local resolved: { [number]: number } = {}
	for index, entry in ipairs(entries) do
		local userId = resolveUserId(entry)
		local idr = pickAmount(entry, "idr")
		if not userId then
			warnLog("Cash[%d]: invalid userId/username", index)
			stats.skipped += 1
			continue
		end
		if idr <= 0 then
			warnLog("Cash[%d]: idr <= 0 (userId=%d)", index, userId)
			stats.skipped += 1
			continue
		end
		resolved[userId] = idr
		stats.cashEntries += 1
	end

	info("Cash: %d entries ready (strategy=%s)", stats.cashEntries, STRATEGY)
	for userId, idr in pairs(resolved) do
		info("  userId=%d idr=%d", userId, idr)
	end

	if MODE ~= "commit" then
		return
	end

	local store = DataStoreService:GetDataStore(scopedKey(KEY_MANUAL_CASH))
	waitForBudget(Enum.DataStoreRequestType.UpdateAsync, "UpdateAsync(cash)")
	local ok, err = pcall(function()
		store:UpdateAsync(MANUAL_CASH_DOCUMENT, function(current: any)
			local map = if type(current) == "table" then current else {}
			for userId, target in pairs(resolved) do
				local key = tostring(userId)
				local existing = math.max(0, math.floor(tonumber(map[key]) or 0))
				local nextValue = mergeValue(STRATEGY, existing, target)
				if nextValue > 0 then
					map[key] = nextValue
				else
					map[key] = nil
				end
			end
			return map
		end)
	end)
	if not ok then
		warnLog("Cash bulk write failed: %s", tostring(err))
		return
	end
	stats.written += stats.cashEntries
	info("Cash: commit OK (%d user)", stats.cashEntries)
end

local function seedRobux(data: any)
	if not SEED_ROBUX then
		info("Robux: SKIP (SEED_ROBUX = false)")
		return
	end
	local entries = data.Robux
	if type(entries) ~= "table" or #entries == 0 then
		info("Robux: no entries in LeaderboardSeedData.Robux")
		return
	end

	local store = DataStoreService:GetOrderedDataStore(scopedKey(KEY_ROBUX_ORDERED))
	local metaStore = DataStoreService:GetDataStore(scopedKey(KEY_METADATA))

	for index, entry in ipairs(entries) do
		local userId = resolveUserId(entry)
		local robux = pickAmount(entry, "robux")
		if not userId or robux <= 0 then
			warnLog("Robux[%d]: invalid entry", index)
			stats.skipped += 1
			continue
		end
		stats.robuxEntries += 1
		info("Robux[%d]: userId=%d robux=%d", index, userId, robux)

		if MODE ~= "commit" then
			continue
		end

		local target = robux
		if STRATEGY ~= "set" then
			waitForBudget(Enum.DataStoreRequestType.GetAsync, "GetAsync(robux)")
			local readOk, existing = pcall(function()
				return store:GetAsync(tostring(userId))
			end)
			local current = if readOk then math.max(0, math.floor(tonumber(existing) or 0)) else 0
			target = mergeValue(STRATEGY, current, robux)
		end

		waitForBudget(Enum.DataStoreRequestType.SetIncrementSortedAsync, "SetAsync(robux)")
		local writeOk, writeErr = pcall(function()
			store:SetAsync(tostring(userId), target)
		end)
		if not writeOk then
			warnLog("Robux userId=%d failed: %s", userId, tostring(writeErr))
			continue
		end
		writeMetadata(metaStore, userId)
		stats.written += 1
		task.wait(PACE_SECONDS)
	end
end

local function seedLikes(data: any)
	if not SEED_LIKES then
		info("Likes: SKIP (SEED_LIKES = false)")
		return
	end
	local entries = data.Likes
	if type(entries) ~= "table" or #entries == 0 then
		info("Likes: no entries in LeaderboardSeedData.Likes")
		return
	end

	local summaryStore = DataStoreService:GetDataStore(scopedKey(KEY_LIKES_SUMMARY))
	local leaderboardStore = DataStoreService:GetOrderedDataStore(scopedKey(KEY_LIKES_ORDERED))
	local metaStore = DataStoreService:GetDataStore(scopedKey(KEY_METADATA))

	for index, entry in ipairs(entries) do
		local userId = resolveUserId(entry)
		local likes = pickAmount(entry, "likes")
		if not userId or likes <= 0 then
			warnLog("Likes[%d]: invalid entry", index)
			stats.skipped += 1
			continue
		end
		stats.likesEntries += 1
		info("Likes[%d]: userId=%d likes=%d", index, userId, likes)

		if MODE ~= "commit" then
			continue
		end

		local target = likes
		local summaryKey = ("likes:summary:%d"):format(userId)
		if STRATEGY ~= "set" then
			waitForBudget(Enum.DataStoreRequestType.GetAsync, "GetAsync(likes summary)")
			local readOk, existingSummary = pcall(function()
				return summaryStore:GetAsync(summaryKey)
			end)
			local current = 0
			if readOk and type(existingSummary) == "table" then
				current = math.max(0, math.floor(tonumber(existingSummary.totalLikes) or 0))
			end
			target = mergeValue(STRATEGY, current, likes)
		end

		waitForBudget(Enum.DataStoreRequestType.UpdateAsync, "UpdateAsync(likes summary)")
		local summaryOk, summaryErr = pcall(function()
			summaryStore:SetAsync(summaryKey, {
				totalLikes = target,
				_version = 1,
			})
		end)
		if not summaryOk then
			warnLog("Likes summary userId=%d failed: %s", userId, tostring(summaryErr))
			continue
		end

		waitForBudget(Enum.DataStoreRequestType.SetIncrementSortedAsync, "SetAsync(likes board)")
		local boardOk, boardErr = pcall(function()
			leaderboardStore:SetAsync(tostring(userId), target)
		end)
		if not boardOk then
			warnLog("Likes board userId=%d failed: %s", userId, tostring(boardErr))
			continue
		end

		writeMetadata(metaStore, userId)
		stats.written += 1
		task.wait(PACE_SECONDS)
	end
end

local function main()
	if not ENABLED then
		return
	end
	if not RunService:IsServer() then
		return
	end
	if MODE ~= "dry_run" and MODE ~= "commit" then
		warnLog("MODE invalid (%s). Use dry_run or commit.", tostring(MODE))
		return
	end
	if STRATEGY ~= "set" and STRATEGY ~= "max" and STRATEGY ~= "add" then
		warnLog("STRATEGY invalid (%s)", tostring(STRATEGY))
		return
	end

	local data = loadSeedData()
	if not data then
		return
	end

	info("=== START === mode=%s strategy=%s studioPrefix=%s", MODE, STRATEGY, tostring(USE_STUDIO_DATASTORE_ISOLATION and RunService:IsStudio()))
	info("Keys: cash=%s robux=%s likes=%s", scopedKey(KEY_MANUAL_CASH), scopedKey(KEY_ROBUX_ORDERED), scopedKey(KEY_LIKES_ORDERED))

	seedCash(data)
	seedRobux(data)
	seedLikes(data)

	info("=== SUMMARY ===")
	info("Cash entries   : %d", stats.cashEntries)
	info("Robux entries  : %d", stats.robuxEntries)
	info("Likes entries  : %d", stats.likesEntries)
	info("Written (commit): %d", stats.written)
	info("Skipped        : %d", stats.skipped)
	info("Errors         : %d", stats.errors)
	if MODE == "dry_run" then
		info("DRY RUN complete — no writes. Set MODE='commit' then Play again.")
	else
		info("COMMIT complete. Restart server + /refreshleaderboard all to verify.")
		info("Set ENABLED=false or delete seeder folder — no longer needed.")
	end
end

main()
