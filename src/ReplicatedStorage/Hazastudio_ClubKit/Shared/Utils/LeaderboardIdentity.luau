--!strict
-- Resolve Roblox username / display name / headshot for leaderboard rows.
-- Hot path uses module cache + batched UserService lookups to avoid per-row
-- 1-id storms on every workspace leaderboard rebuild.

local Players = game:GetService("Players")
local UserService = game:GetService("UserService")

export type ResolvedIdentity = {
	username: string,
	displayName: string,
	thumbnail: string,
}

local IDENTITY_TTL_SEC = 600
local NEGATIVE_CACHE_TTL_SEC = 45

type CacheEntry = {
	value: ResolvedIdentity?,
	exp: number,
}

local identityCache: { [number]: CacheEntry } = {}

local LeaderboardIdentity = {}

function LeaderboardIdentity.normalizeUsername(value: string?): string
	if type(value) ~= "string" then
		return ""
	end
	return value:gsub("^@", ""):lower()
end

function LeaderboardIdentity.looksLikeFallbackName(name: string?): boolean
	if type(name) ~= "string" or name == "" then
		return true
	end
	return name:match("^User%s*%d+$") ~= nil
end

-- Legacy helper kept for callers. DisplayName == Username is valid on Roblox and
-- must NOT force re-resolve on every rebuild (that caused UserService storms).
-- Returns false always; true-fallback detection uses looksLikeFallbackName.
function LeaderboardIdentity.isStaleDisplayName(_displayName: string?, _username: string?): boolean
	return false
end

function LeaderboardIdentity.fetchUserInfos(userIds: { number }): { any }
	if #userIds == 0 then
		return {}
	end

	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(userIds)
	end)
	if ok and type(infos) == "table" then
		return infos
	end

	local legacyOk, legacyInfos = pcall(function()
		return (Players :: any):GetUserInfosByUserIdsAsync(userIds)
	end)
	if legacyOk and type(legacyInfos) == "table" then
		return legacyInfos
	end

	return {}
end

function LeaderboardIdentity.readInfoUserId(info: any): number?
	if type(info) ~= "table" then
		return nil
	end
	return tonumber(info.Id or info.UserId)
end

-- Prefer rbxthumb:// — avoids Players:GetUserThumbnailAsync storms (Network tab
-- "Players" failures). Boards already render rbxthumb headshots fine.
function LeaderboardIdentity.getUserThumbnail(userId: number, size: number?): string
	local px = if size == 420 then 420 else 150
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=%d&h=%d", userId, px, px)
end

local function readPositiveCache(userId: number): ResolvedIdentity?
	local entry = identityCache[userId]
	if not entry then
		return nil
	end
	if entry.exp <= os.clock() then
		identityCache[userId] = nil
		return nil
	end
	return entry.value
end

local function isNegativeCached(userId: number): boolean
	local entry = identityCache[userId]
	if not entry then
		return false
	end
	if entry.exp <= os.clock() then
		identityCache[userId] = nil
		return false
	end
	return entry.value == nil
end

local function writePositiveCache(userId: number, value: ResolvedIdentity)
	identityCache[userId] = {
		value = value,
		exp = os.clock() + IDENTITY_TTL_SEC,
	}
end

local function writeNegativeCache(userId: number)
	identityCache[userId] = {
		value = nil,
		exp = os.clock() + NEGATIVE_CACHE_TTL_SEC,
	}
end

local function identityFromInfo(userId: number, info: any): ResolvedIdentity
	local fallbackUsername = "User " .. tostring(userId)
	local username = fallbackUsername
	local displayName = fallbackUsername
	if type(info) == "table" then
		if type(info.Username) == "string" and info.Username ~= "" then
			username = info.Username
		end
		if type(info.DisplayName) == "string" and info.DisplayName ~= "" then
			displayName = info.DisplayName
		else
			displayName = username
		end
	end
	return {
		username = username,
		displayName = displayName,
		thumbnail = LeaderboardIdentity.getUserThumbnail(userId, 150),
	}
end

function LeaderboardIdentity.resolveUserIdentity(userId: number): ResolvedIdentity
	local cached = readPositiveCache(userId)
	if cached then
		return cached
	end
	if isNegativeCached(userId) then
		return {
			username = "User " .. tostring(userId),
			displayName = "User " .. tostring(userId),
			thumbnail = LeaderboardIdentity.getUserThumbnail(userId, 150),
		}
	end

	local fallbackUsername = "User " .. tostring(userId)
	local username = fallbackUsername
	local displayName = fallbackUsername
	local resolvedOk = false

	local player = Players:GetPlayerByUserId(userId)
	if player then
		username = player.Name
		displayName = player.DisplayName
		resolvedOk = true
	else
		local infos = LeaderboardIdentity.fetchUserInfos({ userId })
		for _, info in ipairs(infos) do
			if LeaderboardIdentity.readInfoUserId(info) == userId then
				local fromInfo = identityFromInfo(userId, info)
				username = fromInfo.username
				displayName = fromInfo.displayName
				resolvedOk = not LeaderboardIdentity.looksLikeFallbackName(username)
				break
			end
		end
	end

	if LeaderboardIdentity.looksLikeFallbackName(username) then
		local nameOk, resolvedName = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		if nameOk and type(resolvedName) == "string" and resolvedName ~= "" then
			username = resolvedName
			if LeaderboardIdentity.looksLikeFallbackName(displayName) then
				displayName = resolvedName
			end
			resolvedOk = true
		end
	end

	local resolved: ResolvedIdentity = {
		username = username,
		displayName = displayName,
		thumbnail = LeaderboardIdentity.getUserThumbnail(userId, 150),
	}

	if resolvedOk and not LeaderboardIdentity.looksLikeFallbackName(username) then
		writePositiveCache(userId, resolved)
	else
		writeNegativeCache(userId)
	end

	return resolved
end

local function entryNeedsResolve(entry: any): (boolean, number?)
	if type(entry) ~= "table" then
		return false, nil
	end
	local userId = tonumber(entry.userId)
	if not userId or userId <= 0 then
		return false, nil
	end

	local username = if type(entry.username) == "string" then entry.username else ""
	local displayName = if type(entry.displayName) == "string" then entry.displayName else ""
	local thumbnail = if type(entry.thumbnail) == "string" then entry.thumbnail else ""

	-- Do NOT treat DisplayName == Username as stale (Roblox allows it).
	local needsResolve = LeaderboardIdentity.looksLikeFallbackName(username)
		or LeaderboardIdentity.looksLikeFallbackName(displayName)
		or thumbnail == ""

	return needsResolve, userId
end

local function applyResolved(entry: any, resolved: ResolvedIdentity)
	local username = if type(entry.username) == "string" then entry.username else ""
	local displayName = if type(entry.displayName) == "string" then entry.displayName else ""
	local thumbnail = if type(entry.thumbnail) == "string" then entry.thumbnail else ""

	if LeaderboardIdentity.looksLikeFallbackName(username) then
		username = resolved.username
	end
	if LeaderboardIdentity.looksLikeFallbackName(displayName) then
		displayName = resolved.displayName
	end
	if thumbnail == "" then
		thumbnail = resolved.thumbnail
	end

	entry.username = username
	entry.displayName = displayName
	entry.thumbnail = thumbnail
	return entry
end

function LeaderboardIdentity.enrichPlayerEntry(entry: any): any
	local needsResolve, userId = entryNeedsResolve(entry)
	if not needsResolve or not userId then
		return entry
	end

	local resolved = LeaderboardIdentity.resolveUserIdentity(userId)
	return applyResolved(entry, resolved)
end

function LeaderboardIdentity.enrichEntryList(entries: any): any
	if type(entries) ~= "table" then
		return entries
	end

	local needOfflineIds: { number } = {}
	local needOfflineSet: { [number]: boolean } = {}
	local pendingIndexes: { number } = {}

	for index, entry in ipairs(entries) do
		local needsResolve, userId = entryNeedsResolve(entry)
		if needsResolve and userId then
			local cached = readPositiveCache(userId)
			if cached then
				entries[index] = applyResolved(entry, cached)
			elseif isNegativeCached(userId) then
				entries[index] = applyResolved(entry, {
					username = "User " .. tostring(userId),
					displayName = "User " .. tostring(userId),
					thumbnail = LeaderboardIdentity.getUserThumbnail(userId, 150),
				})
			else
				local online = Players:GetPlayerByUserId(userId)
				if online then
					local resolved: ResolvedIdentity = {
						username = online.Name,
						displayName = online.DisplayName,
						thumbnail = LeaderboardIdentity.getUserThumbnail(userId, 150),
					}
					writePositiveCache(userId, resolved)
					entries[index] = applyResolved(entry, resolved)
				else
					table.insert(pendingIndexes, index)
					if not needOfflineSet[userId] then
						needOfflineSet[userId] = true
						table.insert(needOfflineIds, userId)
					end
				end
			end
		end
	end

	if #needOfflineIds == 0 then
		return entries
	end

	local infos = LeaderboardIdentity.fetchUserInfos(needOfflineIds)
	local infoByUserId: { [number]: any } = {}
	for _, info in ipairs(infos) do
		local id = LeaderboardIdentity.readInfoUserId(info)
		if id then
			infoByUserId[id] = info
		end
	end

	for _, userId in ipairs(needOfflineIds) do
		local info = infoByUserId[userId]
		if info then
			local resolved = identityFromInfo(userId, info)
			if not LeaderboardIdentity.looksLikeFallbackName(resolved.username) then
				writePositiveCache(userId, resolved)
			else
				writeNegativeCache(userId)
			end
		else
			writeNegativeCache(userId)
		end
	end

	for _, index in ipairs(pendingIndexes) do
		local entry = entries[index]
		local userId = tonumber(entry and entry.userId)
		if userId then
			local cached = readPositiveCache(userId)
			if cached then
				entries[index] = applyResolved(entry, cached)
			else
				entries[index] = applyResolved(entry, {
					username = "User " .. tostring(userId),
					displayName = "User " .. tostring(userId),
					thumbnail = LeaderboardIdentity.getUserThumbnail(userId, 150),
				})
			end
		end
	end

	return entries
end

return LeaderboardIdentity
