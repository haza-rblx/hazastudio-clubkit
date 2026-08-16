--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local AfkGuardDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.AfkGuardDomain)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local TTLSet = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.TTLSet)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)

type Result<T> = Types.Result<T>

-- in-flight guard entry: nil = free, number = os.clock() timestamp when set.
-- Stale entries (> timeout + retries + buffer) are reaped so a teleport that
-- resolved without a PlayerRemoving never latches the player forever.
local function inFlightStaleAfterSec(): number
	local cfg = Config.AfkGuard
	local timeout = tonumber(cfg.TELEPORT_INIT_TIMEOUT_SEC) or 10
	local retryDelay = tonumber(cfg.RETRY_DELAY_SEC) or 30
	local maxRetry = tonumber(cfg.MAX_RETRY) or 1
	return timeout + retryDelay * (maxRetry + 1) + 30
end

local function createAfkGuardService(deps: {
	notify: any,
	sessionCommandService: any,
	carryService: any?,
	remotes: Folder,
	responseRemote: RemoteEvent?,
})
	local notify = deps.notify
	local sessionCommandService = deps.sessionCommandService
	local carryService = deps.carryService
	local remotes = deps.remotes
	local responseRemote = deps.responseRemote
	local log = Logger.new("AfkGuardService")

	local afkConfig = Config.AfkGuard
	local limiter = RateLimiter.new(
		tonumber(afkConfig.AUTO_REJOIN_RATE_MAX) or 1,
		tonumber(afkConfig.AUTO_REJOIN_RATE_WINDOW) or 900
	)
	local processedRequests = TTLSet.create({
		ttl = tonumber(afkConfig.AUTO_REJOIN_RATE_WINDOW) or 900,
		maxSize = Config.Security.MAX_REQUEST_CACHE or 500,
	})
	local inFlightAfkRejoin: { [number]: number } = {}

	local _connections: { RBXScriptConnection } = {}
	local service = {}

	local function track(conn: RBXScriptConnection): RBXScriptConnection
		table.insert(_connections, conn)
		return conn
	end

	local function respond(player: Player, requestId: string, outcome: AfkGuardDomain.RejoinOutcome, retryAfterSec: number?)
		if responseRemote and responseRemote:IsA("RemoteEvent") then
			responseRemote:FireClient(player, {
				requestId = requestId,
				outcome = outcome,
				retryAfterSec = retryAfterSec,
			})
		end
	end

	local function deny(player: Player, requestId: string, reason: string, outcome: AfkGuardDomain.RejoinOutcome, retryAfterSec: number?)
		log:info("afk_rejoin_denied", {
			player = player.Name,
			userId = player.UserId,
			reason = reason,
			requestId = requestId,
		})
		respond(player, requestId, outcome, retryAfterSec)
	end

	local function isBlockedState(player: Player): (boolean, string?)
		if carryService and type(carryService.getPartnerId) == "function" then
			local partnerId = carryService:getPartnerId(player.UserId)
			if partnerId ~= nil then
				return true, "carry_active"
			end
		end
		return false, nil
	end

	local function handleRequest(player: Player, raw: any)
		if afkConfig.ENABLED ~= true or Config.FeatureFlags.AfkGuardEnabled ~= true then
			return
		end

		local validated = AfkGuardDomain.validateRejoinRequest(raw)
		if not validated.ok then
			deny(player, "", validated.error, "denied_invalid", 60)
			return
		end

		local request = validated.value
		if processedRequests:contains(request.requestId) then
			log:info("afk_rejoin_denied", {
				player = player.Name,
				userId = player.UserId,
				reason = "duplicate_request",
				requestId = request.requestId,
			})
			return
		end
		processedRequests:add(request.requestId)

		-- Free server-state checks run before the rate limiter: a token is an
		-- attempt budget for genuine teleports, not a request budget. Transitory
		-- denials (in-flight, carry) must not burn the 15-minute window.
		local inFlightAt = inFlightAfkRejoin[player.UserId]
		if inFlightAt ~= nil then
			local staleAfter = inFlightStaleAfterSec()
			if os.clock() - inFlightAt > staleAfter then
				inFlightAfkRejoin[player.UserId] = nil
				log:warn("afk_rejoin_inflight_reaped", {
					player = player.Name,
					userId = player.UserId,
					staleAfterSec = staleAfter,
				})
			else
				deny(player, request.requestId, "in_flight", "denied_in_flight", 30)
				return
			end
		end

		local blocked, blockReason = isBlockedState(player)
		if blocked then
			deny(player, request.requestId, blockReason or "carry_active", "denied_carry_active", 60)
			notify.player(player, afkConfig.MSG_REJOIN_FAILED, "WARNING")
			return
		end

		local allowed, _reason, waitSec = limiter:check(player.UserId)
		if not allowed then
			deny(player, request.requestId, "rate_limited", "denied_rate_limited", waitSec)
			notify.player(player, afkConfig.MSG_REJOIN_FAILED, "WARNING")
			return
		end

		if not sessionCommandService or type(sessionCommandService.handleAfkRejoin) ~= "function" then
			deny(player, request.requestId, "service_unavailable", "denied_service_unavailable", 60)
			notify.player(player, afkConfig.MSG_REJOIN_FAILED, "ERROR")
			return
		end

		inFlightAfkRejoin[player.UserId] = os.clock()
		log:info("afk_rejoin_approved", {
			player = player.Name,
			userId = player.UserId,
			requestId = request.requestId,
			reportedIdleSec = request.reportedIdleSec,
		})
		respond(player, request.requestId, "allowed", nil)

		local ok, resultOrErr = pcall(function()
			return sessionCommandService:handleAfkRejoin(player, request.reportedIdleSec)
		end)
		inFlightAfkRejoin[player.UserId] = nil
		if not ok then
			log:error("afk_teleport_throw", {
				player = player.Name,
				userId = player.UserId,
				error = tostring(resultOrErr),
			})
			respond(player, request.requestId, "rejoin_failed", 60)
			notify.player(player, afkConfig.MSG_REJOIN_FAILED, "ERROR")
			return
		end
		local result: Result<nil> = resultOrErr
		if not result.ok then
			log:warn("afk_teleport_failed", {
				player = player.Name,
				userId = player.UserId,
				reason = result.error,
			})
			respond(player, request.requestId, "rejoin_failed", 60)
			notify.player(player, afkConfig.MSG_REJOIN_FAILED, "ERROR")
		end
	end

	function service:init()
		if afkConfig.ENABLED ~= true or Config.FeatureFlags.AfkGuardEnabled ~= true then
			return
		end

		local remoteName = afkConfig.REMOTE_REQUEST or "AfkRejoinRequest"
		local requestRemote = remotes:FindFirstChild(remoteName)
		if not requestRemote or not requestRemote:IsA("RemoteEvent") then
			requestRemote = Instance.new("RemoteEvent")
			requestRemote.Name = remoteName
			requestRemote.Parent = remotes
		end

		if not responseRemote then
			local responseName = afkConfig.REMOTE_RESPONSE or "AfkRejoinResponse"
			local found = remotes:FindFirstChild(responseName)
			if found and found:IsA("RemoteEvent") then
				responseRemote = found
			else
				local created = Instance.new("RemoteEvent")
				created.Name = responseName
				created.Parent = remotes
				responseRemote = created
			end
		end

		track((requestRemote :: RemoteEvent).OnServerEvent:Connect(function(player: Player, raw: any)
			if not player or not player.Parent then
				return
			end
			handleRequest(player, raw)
		end))

		log:info("AfkGuardService initialized")
	end

	function service:onPlayerRemoving(player: Player)
		inFlightAfkRejoin[player.UserId] = nil
	end

	function service:destroy()
		for _, conn in ipairs(_connections) do
			conn:Disconnect()
		end
		table.clear(_connections)
		table.clear(inFlightAfkRejoin)
	end

	return service
end

return createAfkGuardService
