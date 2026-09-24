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
local BackendClient = require(script.Parent.Parent.Net.BackendClient)
local PlayerLookupBatcher = require(script.Parent.Parent.Net.PlayerLookupBatcher)

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

	local function tryWorkerFetch(userId: number, allowBatch: boolean): (boolean, number?)
		-- Production hardening P3 (C2): the join warm is batched through GET /v2/players/lookup
		-- (want=connections) when the donation API is configured; an explicit fetch (profile
		-- opened) keeps the direct route. "lookup_unavailable" → the per-user route below.
		if allowBatch and PlayerLookupBatcher.isAvailable() then
			local player = Players:GetPlayerByUserId(userId)
			local lookupOk, record = PlayerLookupBatcher.lookup(userId, if player then player.Name else nil, "connections")
			if lookupOk and type(record) == "table" and record.connectionsKnown then
				return true, record.connectionsCount
			end
			if record ~= "lookup_unavailable" then
				return false, nil
			end
		end

		local apiConfig = getApiConfig()
		local secret = Secrets.GameDataApiSecret
		if not apiConfig or not apiConfig.BASE_URL or apiConfig.BASE_URL == ""
			or type(secret) ~= "string" or secret == ""
		then
			return false, nil
		end

		-- Secret as Authorization: Bearer (legacy switch: ?secret= as before).
		local url = ("%s/game/%s/social/%d"):format(apiConfig.BASE_URL, apiConfig.GAME_KEY, userId)
		local timeout = tonumber(apiConfig.HTTP_TIMEOUT) or 5
		local ok, response = BackendClient.request({
			endpoint = "gamedata:social_get",
			url = url,
			method = "GET",
			auth = "gamedata",
			priority = "bulk",
			timeoutSec = timeout,
			legacyQuerySecret = true,
		})
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

	-- Push connectionsCount to Worker KV after successful resolve.
	-- Worker cannot fetch Roblox friends API from Cloudflare IPs,
	-- so game server pushes data so subsequent GET from Worker
	-- directly hit KV cache.
	local function pushToWorker(userId: number, connectionsCount: number)
		local apiConfig = getApiConfig()
		local secret = Secrets.GameDataApiSecret
		if not apiConfig or not apiConfig.BASE_URL or apiConfig.BASE_URL == ""
			or type(secret) ~= "string" or secret == ""
		then
			return
		end

		local url = ("%s/game/%s/social/%d"):format(apiConfig.BASE_URL, apiConfig.GAME_KEY, userId)
		local timeout = tonumber(apiConfig.HTTP_TIMEOUT) or 5
		task.spawn(function()
			local ok, response = BackendClient.request({
				endpoint = "gamedata:social_push",
				url = url,
				method = "POST",
				auth = "gamedata",
				headers = { ["Content-Type"] = "application/json" },
				body = HttpService:JSONEncode({ connectionsCount = connectionsCount }),
				priority = "bulk",
				timeoutSec = timeout,
				legacyQuerySecret = true,
			})
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

	local function resolveConnectionsCount(userId: number, allowBatch: boolean): (SocialProofData, string)
		local workerCount: number? = nil
		local workerOk = false
		-- Pre-P3: 3 attempts per fetch, even when the VPS answered "no count yet". With BackendClient:
		-- a retry only after a transport failure, and one fewer (production hardening P3).
		local attempts = if BackendClient.isEnabled() then 2 else 3
		for attempt = 1, attempts do
			workerOk, workerCount = tryWorkerFetch(userId, allowBatch and attempt == 1)
			if workerOk and workerCount ~= nil then
				break
			end
			if BackendClient.isEnabled() and workerOk then
				break -- an answer without a count is not fixed by asking again
			end
			if attempt < attempts then
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

		-- Worker reachable but data empty (KV not yet seeded), or Worker unavailable.
		-- Fallback to GetFriendsAsync for first seed cycle.
		-- In production, this only happens once per user until KV is populated.
		local useFallback = shouldUseFriendsFallback()
			or (workerOk and workerCount == nil) -- Worker reachable but KV empty
		if useFallback then
			local friendsCount = fetchViaGetFriendsAsync(userId)
			if friendsCount ~= nil then
				log:debug("ProfileSocialService: GetFriendsAsync fallback", {
					userId = userId,
					connectionsCount = friendsCount,
					workerOk = workerOk,
				})
				-- Push to Worker KV so subsequent requests directly hit cache
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

	local function fetchSocial(userId: number, allowBatch: boolean): Result<SocialProofData>
		local key = "social_" .. tostring(userId)
		local cached = Cache.get(key)
		if cached then
			return Result.Ok(cached)
		end
		-- Negative cache (production hardening P3): no count anywhere a moment ago → do not ask
		-- again for SOCIAL_NEGATIVE_TTL_SEC (Main's join warm retries twice 10 s apart).
		if BackendClient.isEnabled() and Cache.get("social_neg_" .. tostring(userId)) then
			return Result.Ok(table.clone(EMPTY_SOCIAL))
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

		local data, source = resolveConnectionsCount(userId, allowBatch)
		-- Do not cache empty/null — transient Worker/Roblox failures should retry.
		if data.connectionsCount ~= nil then
			Cache.set(key, data, Config.AvatarContext.SOCIAL_PROOF_CACHE_TTL)
		elseif BackendClient.isEnabled() then
			local negativeTtl = (Config.BackendClient and tonumber(Config.BackendClient.SOCIAL_NEGATIVE_TTL_SEC)) or 300
			Cache.set("social_neg_" .. tostring(userId), true, negativeTtl)
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

	function service:fetch(userId: number): Result<SocialProofData>
		return fetchSocial(userId, false)
	end

	-- Background warm: Worker + cache only, safe for PlayerAdded. Batched (production hardening P3).
	function service:warm(userId: number): Result<SocialProofData>
		return fetchSocial(userId, true)
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
