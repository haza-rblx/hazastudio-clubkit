--!strict
-- Server-side HTTP API wrapper (quota-efficiency-pass-2026-06, Phase 2).
-- Setiap fungsi Roblox API (GroupService:GetGroupsAsync, Players:GetNameFromUserIdAsync,
-- etc.) di-wrap dengan: in-flight dedup + cache check + counter + cache set.
--
-- Kill switch: Config.HttpApi.ENABLED = false → semua call bypass wrapper dan call
-- direct Roblox API (zero behavior change, default).
-- Set ENABLED = true setelah 2.6 parallel-run verification passed.
--
-- Soft-defer + coalesce queue di-defer ke Phase 3. Phase 2 fokus: dedup + cache saja.
local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")
local UserService = game:GetService("UserService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Cache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cache)
local HttpApiCounter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApiCounter)

-- Module-level state. Per-server, persists for server lifetime.
-- In-flight dedup: BindableEvent per cache key. Caller kedua wait on the event.
local inFlight: { [string]: BindableEvent } = {}

-- withCache: generic wrapper. If ENABLED=false, call direct. If ENABLED=true:
-- 1. Cache check (return cached if hit)
-- 2. In-flight dedup (wait if another caller is fetching same key)
-- 3. Counter record
-- 4. Direct call (pcall-wrapped)
-- 5. Cache set
-- 6. Resolve in-flight event so waiters can read the cached value
local function withCache<T>(bucket: string, cacheKey: string, cacheTtl: number, directCall: () -> T): T?
	if not (Config.HttpApi and Config.HttpApi.ENABLED) then
		return directCall()
	end

	-- Cache check
	local cached = Cache.get(cacheKey)
	if cached ~= nil then
		return cached :: T
	end

	-- In-flight dedup: if another caller is fetching same key, wait + return cached
	if inFlight[cacheKey] then
		inFlight[cacheKey].Event:Wait()
		local afterWait = Cache.get(cacheKey)
		if afterWait ~= nil then
			return afterWait :: T
		end
		-- Fallthrough if wait completed but cache empty (direct call failed)
	end

	-- Register in-flight
	local event = Instance.new("BindableEvent")
	inFlight[cacheKey] = event

	-- Counter: increments each time we actually call the API
	if Config.HttpApi.COUNTERS_ENABLED then
		HttpApiCounter.record(bucket)
	end

	local ok, result = pcall(directCall)

	-- Clear in-flight BEFORE firing event (so waiters can re-check cache cleanly)
	inFlight[cacheKey] = nil
	event:Fire()
	event:Destroy()

	if ok and result ~= nil then
		Cache.set(cacheKey, result, cacheTtl)
		return result :: T
	end
	return nil
end

local HttpApi = {}

-- Players:GetNameFromUserIdAsync
function HttpApi.getNameFromUserIdAsync(userId: number): string?
	return withCache("httpapi_getname", "name:" .. tostring(userId), Config.HttpApi.GET_NAME_TTL, function()
		local ok, name = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		if ok and type(name) == "string" and name ~= "" then
			return name
		end
		return nil
	end)
end

-- Players:GetUserIdFromNameAsync
function HttpApi.getUserIdFromNameAsync(username: string): number?
	return withCache("httpapi_getuserid", "userid:" .. username, Config.HttpApi.GET_USER_ID_TTL, function()
		local ok, id = pcall(function()
			return Players:GetUserIdFromNameAsync(username)
		end)
		if ok and type(id) == "number" then
			return id
		end
		return nil
	end)
end

-- UserService:GetUserInfosByUserIdsAsync — real multi-id batch for misses.
-- Returns map: userId -> { Username, DisplayName } (partial OK)
function HttpApi.getUserInfosByUserIdsAsync(userIds: { number }): { [number]: any }
	local result: { [number]: any } = {}
	local missing: { number } = {}
	local missingSet: { [number]: boolean } = {}
	local ttl = Config.HttpApi.GET_USER_INFOS_TTL

	for _, userId in ipairs(userIds) do
		if type(userId) == "number" and userId > 0 and not missingSet[userId] then
			local cacheKey = "userinfo:" .. tostring(userId)
			if Config.HttpApi and Config.HttpApi.ENABLED then
				local cached = Cache.get(cacheKey)
				if cached ~= nil then
					result[userId] = cached
				else
					missingSet[userId] = true
					table.insert(missing, userId)
				end
			else
				missingSet[userId] = true
				table.insert(missing, userId)
			end
		end
	end

	if #missing == 0 then
		return result
	end

	if Config.HttpApi and Config.HttpApi.COUNTERS_ENABLED then
		HttpApiCounter.record("httpapi_getuserinfos")
	end

	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and type(infos) == "table" then
		for _, info in ipairs(infos) do
			if type(info) == "table" then
				local id = tonumber(info.Id or info.UserId)
				if id then
					result[id] = info
					if Config.HttpApi and Config.HttpApi.ENABLED then
						Cache.set("userinfo:" .. tostring(id), info, ttl)
					end
				end
			end
		end
	end

	return result
end

-- Players:GetFriendsAsync (returns count only; pagination handled internally)
function HttpApi.getFriendsCountAsync(userId: number): number?
	return withCache(
		"httpapi_getfriendscount",
		"friendscount:" .. tostring(userId),
		Config.HttpApi.GET_FRIENDS_TTL,
		function()
			local ok, friendsList = pcall(function()
				return Players:GetFriendsAsync(userId)
			end)
			if not ok or not friendsList then
				return nil
			end
			-- Iterate pages, return total count. Same MAX_PAGES as ProfileSocialService fallback.
			local MAX_PAGES = 15
			local total = 0
			local pageCount = 0
			while true do
				local page = friendsList:GetCurrentPage()
				total += #page
				pageCount += 1
				if friendsList.IsFinished or pageCount >= MAX_PAGES then
					break
				end
				local advOk = pcall(function()
					friendsList:AdvanceToNextPageAsync()
				end)
				if not advOk then
					break
				end
			end
			return total
		end
	)
end

-- Players:GetUserThumbnailAsync
-- Return type: Content (table with string fields) or nil. Use any to avoid strict typing issues.
function HttpApi.getUserThumbnailAsync(
	userId: number,
	thumbType: Enum.ThumbnailType,
	thumbSize: Enum.ThumbnailSize
): any
	return withCache(
		"httpapi_getthumb",
		"thumb:" .. tostring(userId) .. ":" .. thumbType.Name .. ":" .. thumbSize.Name,
		Config.HttpApi.GET_THUMB_TTL,
		function()
			local ok, content = pcall(function()
				return Players:GetUserThumbnailAsync(userId, thumbType, thumbSize)
			end)
			if ok and content ~= nil then
				return content
			end
			return nil
		end
	)
end

-- GroupService:GetGroupsAsync
function HttpApi.getGroupsAsync(userId: number): { any }?
	return withCache("httpapi_getgroups", "groups:" .. tostring(userId), Config.HttpApi.GET_GROUPS_TTL, function()
		local ok, groups = pcall(function()
			return GroupService:GetGroupsAsync(userId)
		end)
		if ok and type(groups) == "table" then
			return groups
		end
		return nil
	end)
end

-- Players:GetHumanoidDescriptionFromUserIdAsync
function HttpApi.getHumanoidDescriptionFromUserIdAsync(userId: number): HumanoidDescription?
	return withCache("httpapi_gethd", "hd:" .. tostring(userId), Config.HttpApi.GET_HUMANOID_DESCRIPTION_TTL, function()
		local ok, desc = pcall(function()
			return Players:GetHumanoidDescriptionFromUserIdAsync(userId)
		end)
		if ok and desc ~= nil then
			return desc
		end
		return nil
	end)
end

return HttpApi
