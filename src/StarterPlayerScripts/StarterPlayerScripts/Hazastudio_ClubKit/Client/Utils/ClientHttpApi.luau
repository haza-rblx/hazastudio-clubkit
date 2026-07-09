--!strict
-- Client-side HTTP API wrapper (quota-efficiency-pass-2026-06, Phase 2, task 2.2).
-- Subset dari server HttpApi.luau — 3 functions untuk client.
-- Kill switch: Config.ClientHttpApi.ENABLED = false → direct call.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Cache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cache)

local inFlight: { [string]: BindableEvent } = {}

local function withCache<T>(_bucket: string, cacheKey: string, cacheTtl: number, directCall: () -> T): T?
	if not (Config.ClientHttpApi and Config.ClientHttpApi.ENABLED) then
		return directCall()
	end

	local cached = Cache.get(cacheKey)
	if cached ~= nil then
		return cached :: T
	end

	if inFlight[cacheKey] then
		inFlight[cacheKey].Event:Wait()
		local afterWait = Cache.get(cacheKey)
		if afterWait ~= nil then
			return afterWait :: T
		end
	end

	local event = Instance.new("BindableEvent")
	inFlight[cacheKey] = event

	local ok, result = pcall(directCall)

	inFlight[cacheKey] = nil
	event:Fire()
	event:Destroy()

	if ok and result ~= nil then
		Cache.set(cacheKey, result, cacheTtl)
		return result :: T
	end
	return nil
end

local ClientHttpApi = {}

-- Players:GetUserThumbnailAsync
-- Return type: Content (table with string fields) or nil. Use any to avoid strict typing issues.
function ClientHttpApi.getUserThumbnailAsync(
	userId: number,
	thumbType: Enum.ThumbnailType,
	thumbSize: Enum.ThumbnailSize
): any
	return withCache(
		"clienthttpapi_getthumb",
		"clientthumb:" .. tostring(userId) .. ":" .. thumbType.Name .. ":" .. thumbSize.Name,
		Config.ClientHttpApi.GET_THUMB_TTL,
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

-- Players:GetHumanoidDescriptionFromUserIdAsync
function ClientHttpApi.getHumanoidDescriptionFromUserIdAsync(userId: number): HumanoidDescription?
	return withCache(
		"clienthttpapi_gethd",
		"clienthd:" .. tostring(userId),
		Config.ClientHttpApi.GET_HUMANOID_DESCRIPTION_TTL,
		function()
			local ok, desc = pcall(function()
				return Players:GetHumanoidDescriptionFromUserIdAsync(userId)
			end)
			if ok and desc ~= nil then
				return desc
			end
			return nil
		end
	)
end

-- Players:GetUserIdFromNameAsync
function ClientHttpApi.getUserIdFromNameAsync(username: string): number?
	return withCache(
		"clienthttpapi_getuserid",
		"clientuserid:" .. username,
		Config.ClientHttpApi.GET_USER_ID_TTL,
		function()
			local ok, id = pcall(function()
				return Players:GetUserIdFromNameAsync(username)
			end)
			if ok and type(id) == "number" then
				return id
			end
			return nil
		end
	)
end

return ClientHttpApi
