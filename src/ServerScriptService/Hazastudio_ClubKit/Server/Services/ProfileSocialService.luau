--!strict
-- ServerScriptService/Server/Services/ProfileSocialService.luau
--
-- Social proof (connections count) via Cloudflare game-data-api Worker.
-- Do NOT use GetFriendsAsync on hot paths — Worker uses friends/count API + KV cache.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Secrets = require(ServerScriptService.Hazastudio_ClubKitSecrets.Secrets)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Cache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cache)
local HttpApiCounter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApiCounter)
local HttpApi = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApi)

type Result<T> = Types.Result<T>
type SocialProofData = Types.SocialProofData
type ILogger = Types.ILogger

local EMPTY_SOCIAL: SocialProofData = {
	followersCount = nil,
	connectionsCount = nil,
}

local function createProfileSocialService(deps: { logger: ILogger })
	local log = deps.logger
	local inFlight = {} :: { [number]: BindableEvent? }
	local service = {}

	local function getApiConfig()
		return Config.GameDataApi
	end

	local function tryWorkerFetch(userId: number): (boolean, number?)
		local apiConfig = getApiConfig()
		local secret = Secrets.GameDataApiSecret
		if not apiConfig or not apiConfig.BASE_URL or apiConfig.BASE_URL == ""
			or type(secret) ~= "string" or secret == ""
		then
			return false, nil
		end

		local url = ("%s/game/%s/social/%d?secret=%s"):format(
			apiConfig.BASE_URL,
			apiConfig.GAME_KEY,
			userId,
			secret
		)
		local timeout = tonumber(apiConfig.HTTP_TIMEOUT) or 5
		local ok, response = pcall(function()
			return HttpService:RequestAsync({
				Url = url,
				Method = "GET",
				Timeout = timeout,
			})
		end)
		if not ok or type(response) ~= "table" or response.Success ~= true or type(response.Body) ~= "string" then
			return false, nil
		end

		local decodeOk, decoded = pcall(function()
			return HttpService:JSONDecode(response.Body)
		end)
		if not decodeOk or type(decoded) ~= "table" or decoded.ok ~= true then
			return false, nil
		end
		if type(decoded.connectionsCount) ~= "number" then
			return true, nil
		end

		return true, decoded.connectionsCount
	end

	local function fetchViaGetFriendsAsync(userId: number): number?
		-- HTTP API telemetry counter (quota-efficiency-pass-2026-06, Phase 0).
		-- Only fire when wrapper disabled (when enabled, wrapper's internal counter handles it).
		if (not (Config.HttpApi and Config.HttpApi.ENABLED)) and Config.HttpApi and Config.HttpApi.COUNTERS_ENABLED then
			HttpApiCounter.record("friendsasync_attempt")
		end
		local count = HttpApi.getFriendsCountAsync(userId)
		if not count then
			log:warn("ProfileSocialService: GetFriendsAsync failed", { userId = userId })
		end
		return count
	end

	local function shouldUseFriendsFallback(): boolean
		local apiConfig = getApiConfig()
		if apiConfig and apiConfig.ALLOW_GET_FRIENDS_FALLBACK == true then
			return true
		end
		return RunService:IsStudio()
	end

	-- Push connectionsCount ke Worker KV setelah berhasil resolve.
	-- Worker tidak bisa fetch Roblox friends API dari Cloudflare IPs,
	-- jadi game server yang push data supaya subsequent GET dari Worker
	-- langsung hit KV cache.
	local function pushToWorker(userId: number, connectionsCount: number)
		local apiConfig = getApiConfig()
		local secret = Secrets.GameDataApiSecret
		if not apiConfig or not apiConfig.BASE_URL or apiConfig.BASE_URL == ""
			or type(secret) ~= "string" or secret == ""
		then
			return
		end

		local url = ("%s/game/%s/social/%d?secret=%s"):format(
			apiConfig.BASE_URL,
			apiConfig.GAME_KEY,
			userId,
			secret
		)
		local timeout = tonumber(apiConfig.HTTP_TIMEOUT) or 5
		task.spawn(function()
			local ok, response = pcall(function()
				return HttpService:RequestAsync({
					Url = url,
					Method = "POST",
					Headers = { ["Content-Type"] = "application/json" },
					Body = HttpService:JSONEncode({ connectionsCount = connectionsCount }),
					Timeout = timeout,
				})
			end)
			if ok and response and response.Success then
				log:debug("ProfileSocialService: Pushed to Worker KV", {
					userId = userId,
					connectionsCount = connectionsCount,
				})
			else
				log:debug("ProfileSocialService: Worker push failed (non-critical)", {
					userId = userId,
				})
			end
		end)
	end

	local function resolveConnectionsCount(userId: number): (SocialProofData, string)
		local workerCount: number? = nil
		local workerOk = false
		for attempt = 1, 3 do
			workerOk, workerCount = tryWorkerFetch(userId)
			if workerOk and workerCount ~= nil then
				break
			end
			if attempt < 3 then
				task.wait(0.35 * attempt)
			end
		end

		if workerOk and workerCount ~= nil then
			log:debug("ProfileSocialService: Worker proxy", {
				userId = userId,
				connectionsCount = workerCount,
			})
			return {
				followersCount = nil,
				connectionsCount = workerCount,
			}, "worker"
		end

		-- Worker reachable tapi data kosong (KV belum di-seed), atau Worker unavailable.
		-- Fallback ke GetFriendsAsync untuk seed cycle pertama.
		-- Di production, ini hanya terjadi sekali per-user sampai KV ter-populate.
		local useFallback = shouldUseFriendsFallback()
			or (workerOk and workerCount == nil) -- Worker reachable tapi KV kosong
		if useFallback then
			local friendsCount = fetchViaGetFriendsAsync(userId)
			if friendsCount ~= nil then
				log:debug("ProfileSocialService: GetFriendsAsync fallback", {
					userId = userId,
					connectionsCount = friendsCount,
					workerOk = workerOk,
				})
				-- Push ke Worker KV supaya subsequent requests langsung hit cache
				pushToWorker(userId, friendsCount)
				return {
					followersCount = nil,
					connectionsCount = friendsCount,
				}, "friends_async"
			end
		end

		if workerOk then
			log:debug("ProfileSocialService: Worker null connectionsCount", { userId = userId })
		else
			log:debug("ProfileSocialService: Worker unavailable, returning empty social proof", {
				userId = userId,
			})
		end
		return table.clone(EMPTY_SOCIAL), if workerOk then "worker_null" else "none"
	end

	function service:fetch(userId: number): Result<SocialProofData>
		local key = "social_" .. tostring(userId)
		local cached = Cache.get(key)
		if cached then
			return Result.Ok(cached)
		end

		local existingBarrier = inFlight[userId]
		if existingBarrier then
			existingBarrier.Event:Wait()
			local fresh = Cache.get(key)
			if fresh then
				return Result.Ok(fresh)
			end
			return Result.Ok(table.clone(EMPTY_SOCIAL))
		end

		local barrier = Instance.new("BindableEvent")
		inFlight[userId] = barrier

		local data, source = resolveConnectionsCount(userId)
		-- Do not cache empty/null — transient Worker/Roblox failures should retry.
		if data.connectionsCount ~= nil then
			Cache.set(key, data, Config.AvatarContext.SOCIAL_PROOF_CACHE_TTL)
		end
		log:debug("ProfileSocialService: fetch complete", {
			userId = userId,
			source = source,
			connectionsCount = data.connectionsCount,
		})

		inFlight[userId] = nil
		barrier:Fire()
		barrier:Destroy()
		return Result.Ok(data)
	end

	-- Background warm: Worker + cache only, safe for PlayerAdded.
	function service:warm(userId: number): Result<SocialProofData>
		return service:fetch(userId)
	end

	function service:getCached(userId: number): SocialProofData?
		local cached = Cache.get("social_" .. tostring(userId))
		if type(cached) == "table" then
			return cached
		end
		return nil
	end

	return service
end

return createProfileSocialService
