--!strict
-- Resolve Roblox username / display name / headshot for leaderboard rows.
-- Hot path uses module cache + batched UserService lookups to avoid per-row
-- 1-id storms on every workspace leaderboard rebuild.
--
-- Best approach (v2.4.29+): treat DN==username as needsResolve only when
-- displayNameVerified is not set; after a successful resolve, optional write-back
-- persists displayNameVerified into DonationLeaderboardMetadata_v1 (one-shot heal).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HttpApi = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApi)

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
local writeBackHandler: ((userId: number, resolved: ResolvedIdentity) -> ())? = nil

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

-- Legacy helper. Prefer entry.displayNameVerified for durable DN==UN handling.
function LeaderboardIdentity.isStaleDisplayName(_displayName: string?, _username: string?): boolean
	return false
end

function LeaderboardIdentity.setWriteBackHandler(handler: ((userId: number, resolved: ResolvedIdentity) -> ())?)
	writeBackHandler = handler
end

local function maybeWriteBack(userId: number, resolved: ResolvedIdentity)
	if not writeBackHandler then
		return
	end
	if LeaderboardIdentity.looksLikeFallbackName(resolved.username) then
		return
	end
	if LeaderboardIdentity.looksLikeFallbackName(resolved.displayName) then
		return
	end
	local handler = writeBackHandler
	task.defer(function()
		handler(userId, resolved)
	end)
end

function LeaderboardIdentity.fetchUserInfos(userIds: { number }): { any }
	if #userIds == 0 then
		return {}
	end

	-- Prefer HttpApi (admission + shared Cache when ENABLED). Returns map; normalize to list.
	local byId = HttpApi.getUserInfosByUserIdsAsync(userIds)
	local infos: { any } = {}
	if type(byId) ~= "table" then
		return infos
	end
	for _, userId in ipairs(userIds) do
		local info = byId[userId]
		if type(info) == "table" then
			table.insert(infos, info)
		end
	end
	return infos
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
		local fetched = false
		for _, info in ipairs(infos) do
			if LeaderboardIdentity.readInfoUserId(info) == userId then
				local fromInfo = identityFromInfo(userId, info)
				username = fromInfo.username
				displayName = fromInfo.displayName
				resolvedOk = not LeaderboardIdentity.looksLikeFallbackName(username)
				fetched = true
				break
			end
		end
		-- If UserService failed/empty, do NOT call GetNameFromUserIdAsync in the same
		-- window — negative-cache and retry later instead of doubling API pressure.
		if not fetched then
			writeNegativeCache(userId)
			return {
				username = fallbackUsername,
				displayName = fallbackUsername,
				thumbnail = LeaderboardIdentity.getUserThumbnail(userId, 150),
			}
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
	local verified = entry.displayNameVerified == true

	-- DN==UN is valid on Roblox AND also the fingerprint of poisoned seeder metadata.
	-- Only re-resolve until metadata is marked displayNameVerified (one-shot heal).
	local displayMatchesUsername = username ~= ""
		and displayName ~= ""
		and username:lower() == displayName:lower()
	local needsResolve = LeaderboardIdentity.looksLikeFallbackName(username)
		or LeaderboardIdentity.looksLikeFallbackName(displayName)
		or thumbnail == ""
		or (displayMatchesUsername and not verified)

	return needsResolve, userId
end

local function applyResolved(entry: any, resolved: ResolvedIdentity)
	local username = if type(entry.username) == "string" then entry.username else ""
	local displayName = if type(entry.displayName) == "string" then entry.displayName else ""
	local thumbnail = if type(entry.thumbnail) == "string" then entry.thumbnail else ""

	if LeaderboardIdentity.looksLikeFallbackName(username) then
		username = resolved.username
	end
	local displayMatchesUsername = username ~= ""
		and displayName ~= ""
		and username:lower() == displayName:lower()
	local verified = entry.displayNameVerified == true
	if LeaderboardIdentity.looksLikeFallbackName(displayName)
		or (displayMatchesUsername and not verified)
	then
		displayName = resolved.displayName
	end
	if thumbnail == "" then
		thumbnail = resolved.thumbnail
	end

	entry.username = username
	entry.displayName = displayName
	entry.thumbnail = thumbnail
	-- Only mark verified after a real identity (never persist "User N" as verified).
	if not LeaderboardIdentity.looksLikeFallbackName(resolved.username)
		and not LeaderboardIdentity.looksLikeFallbackName(resolved.displayName)
	then
		entry.displayNameVerified = true
	end
	return entry
end

function LeaderboardIdentity.enrichPlayerEntry(entry: any): any
	local needsResolve, userId = entryNeedsResolve(entry)
	if not needsResolve or not userId then
		return entry
	end

	local resolved = LeaderboardIdentity.resolveUserIdentity(userId)
	local applied = applyResolved(entry, resolved)
	if not LeaderboardIdentity.looksLikeFallbackName(resolved.username) then
		maybeWriteBack(userId, resolved)
	end
	return applied
end

function LeaderboardIdentity.enrichEntryList(entries: any): any
	if type(entries) ~= "table" then
		return entries
	end

	local needOfflineIds: { number } = {}
	local needOfflineSet: { [number]: boolean } = {}
	local pendingIndexes: { number } = {}
	local writeBackIds: { [number]: ResolvedIdentity } = {}

	for index, entry in ipairs(entries) do
		local needsResolve, userId = entryNeedsResolve(entry)
		if needsResolve and userId then
			local cached = readPositiveCache(userId)
			if cached then
				entries[index] = applyResolved(entry, cached)
				writeBackIds[userId] = cached
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
					writeBackIds[userId] = resolved
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
		for userId, resolved in pairs(writeBackIds) do
			maybeWriteBack(userId, resolved)
		end
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
				writeBackIds[userId] = resolved
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

	for userId, resolved in pairs(writeBackIds) do
		maybeWriteBack(userId, resolved)
	end

	return entries
end

return LeaderboardIdentity
