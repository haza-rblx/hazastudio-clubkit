--!strict
-- Server-side HTTP API wrapper (quota-efficiency-pass-2026-06, Phase 2 + Phase 1 admission).
-- Setiap fungsi Roblox API di-wrap dengan: in-flight dedup + cache + negative-cache
-- on failure + optional global concurrency cap.
--
-- Kill switch: Config.HttpApi.ENABLED = false → bypass wrapper (direct call).
-- Admission kill switch: Config.HttpApi.ADMISSION_ENABLED = false → no concurrency gate.

local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")
local UserService = game:GetService("UserService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Cache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cache)
local HttpApiCounter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApiCounter)

local inFlight: { [string]: BindableEvent } = {}
local activeCalls = 0

local function negativeTtl(): number
	return math.max(5, math.floor(tonumber(Config.HttpApi.NEGATIVE_CACHE_TTL) or 30))
end

local function maxConcurrent(): number
	return math.max(1, math.floor(tonumber(Config.HttpApi.MAX_CONCURRENT) or 4))
end

local function admissionWaitMax(): number
	return math.max(0.5, tonumber(Config.HttpApi.ADMISSION_WAIT_MAX) or 5)
end

local function acquireAdmission(): boolean
	if not (Config.HttpApi and Config.HttpApi.ADMISSION_ENABLED) then
		return true
	end
	local deadline = os.clock() + admissionWaitMax()
	while activeCalls >= maxConcurrent() do
		if os.clock() >= deadline then
			return false
		end
		task.wait(0.05 + math.random() * 0.05)
	end
	activeCalls += 1
	return true
end

local function releaseAdmission()
	if not (Config.HttpApi and Config.HttpApi.ADMISSION_ENABLED) then
		return
	end
	activeCalls = math.max(0, activeCalls - 1)
end

-- withCache: ENABLED=false → direct. ENABLED=true:
-- 1. Negative cache → nil (no re-fire)
-- 2. Positive cache hit
-- 3. In-flight dedup (waiters return nil if leader failed — no fallthrough retry)
-- 4. Admission slot (or negative-cache + nil)
-- 5. Call + positive set / negative set on fail
local function withCache<T>(bucket: string, cacheKey: string, cacheTtl: number, directCall: () -> T): T?
	if not (Config.HttpApi and Config.HttpApi.ENABLED) then
		return directCall()
	end

	if Cache.getNegative(cacheKey) then
		return nil
	end

	local cached = Cache.get(cacheKey)
	if cached ~= nil then
		return cached :: T
	end

	if inFlight[cacheKey] then
		inFlight[cacheKey].Event:Wait()
		if Cache.getNegative(cacheKey) then
			return nil
		end
		local afterWait = Cache.get(cacheKey)
		if afterWait ~= nil then
			return afterWait :: T
		end
		-- Leader failed without leaving a usable value — do not retry in this waiter.
		return nil
	end

	local event = Instance.new("BindableEvent")
	inFlight[cacheKey] = event

	if not acquireAdmission() then
		Cache.setNegative(cacheKey, negativeTtl())
		inFlight[cacheKey] = nil
		event:Fire()
		event:Destroy()
		return nil
	end

	if Config.HttpApi.COUNTERS_ENABLED then
		HttpApiCounter.record(bucket)
	end

	local ok, result = pcall(directCall)
	releaseAdmission()

	inFlight[cacheKey] = nil
	event:Fire()
	event:Destroy()

	if ok and result ~= nil then
		Cache.set(cacheKey, result, cacheTtl)
		return result :: T
	end

	Cache.setNegative(cacheKey, negativeTtl())
	return nil
end

local HttpApi = {}

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

-- UserService batch. On batch failure, negative-cache every miss id (no legacy fallback here).
function HttpApi.getUserInfosByUserIdsAsync(userIds: { number }): { [number]: any }
	local result: { [number]: any } = {}
	local missing: { number } = {}
	local missingSet: { [number]: boolean } = {}
	local ttl = Config.HttpApi.GET_USER_INFOS_TTL
	local useCache = Config.HttpApi and Config.HttpApi.ENABLED == true

	for _, userId in ipairs(userIds) do
		if type(userId) == "number" and userId > 0 and not missingSet[userId] then
			local cacheKey = "userinfo:" .. tostring(userId)
			if useCache then
				if not Cache.getNegative(cacheKey) then
					local cached = Cache.get(cacheKey)
					if cached ~= nil then
						result[userId] = cached
					else
						missingSet[userId] = true
						table.insert(missing, userId)
					end
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

	if not acquireAdmission() then
		if useCache then
			local failTtl = negativeTtl()
			for _, userId in ipairs(missing) do
				Cache.setNegative("userinfo:" .. tostring(userId), failTtl)
			end
		end
		return result
	end

	if Config.HttpApi and Config.HttpApi.COUNTERS_ENABLED then
		HttpApiCounter.record("httpapi_getuserinfos")
	end

	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	releaseAdmission()

	if ok and type(infos) == "table" then
		local got: { [number]: boolean } = {}
		for _, info in ipairs(infos) do
			if type(info) == "table" then
				local id = tonumber(info.Id or info.UserId)
				if id then
					got[id] = true
					result[id] = info
					if useCache then
						Cache.set("userinfo:" .. tostring(id), info, ttl)
					end
				end
			end
		end
		if useCache then
			local failTtl = negativeTtl()
			for _, userId in ipairs(missing) do
				if not got[userId] and result[userId] == nil then
					Cache.setNegative("userinfo:" .. tostring(userId), failTtl)
				end
			end
		end
	elseif useCache then
		local failTtl = negativeTtl()
		for _, userId in ipairs(missing) do
			Cache.setNegative("userinfo:" .. tostring(userId), failTtl)
		end
	end

	return result
end

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
