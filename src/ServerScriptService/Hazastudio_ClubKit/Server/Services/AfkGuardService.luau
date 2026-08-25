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
-- Stale entries are reaped so a teleport that resolved without a
-- PlayerRemoving never latches the player forever. One request now performs at
-- most one teleport attempt (the client ladder owns retry timing), so the
-- window is just the confirmation wait plus slack.
local function inFlightStaleAfterSec(): number
	local cfg = Config.AfkGuard
	local confirm = tonumber(cfg.TELEPORT_CONFIRM_TIMEOUT_SEC) or 15
	local init = tonumber(cfg.TELEPORT_INIT_TIMEOUT_SEC) or 10
	return math.max(confirm, init) + 20
end

-- One rate token opens one AFK cycle (idle streak). Every rung of the ladder
-- inside that cycle reuses it, so retries can never be starved by the limiter
-- the way they were when a token was charged per request.
type CycleEntry = {
	cycleId: string,
	openedAt: number,
	rejoinConfirmed: boolean,
}

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
	local activeCycles: { [number]: CycleEntry } = {}

	local _connections: { RBXScriptConnection } = {}
	local service = {}

	local function track(conn: RBXScriptConnection): RBXScriptConnection
		table.insert(_connections, conn)
		return conn
	end

	local function respond(
		player: Player,
		requestId: string,
		outcome: AfkGuardDomain.RejoinOutcome,
		retryAfterSec: number?,
		stepIndex: number?
	)
		if responseRemote and responseRemote:IsA("RemoteEvent") then
			responseRemote:FireClient(player, {
				requestId = requestId,
				outcome = outcome,
				retryAfterSec = retryAfterSec,
				-- Echoed so the client knows WHICH rung to un-fire on a
				-- transient denial instead of guessing.
				stepIndex = stepIndex,
			})
		end
	end

	local function deny(
		player: Player,
		requestId: string,
		reason: string,
		outcome: AfkGuardDomain.RejoinOutcome,
		retryAfterSec: number?,
		stepIndex: number?
	)
		log:info("afk_rejoin_denied", {
			player = player.Name,
			userId = player.UserId,
			reason = reason,
			requestId = requestId,
			stepIndex = stepIndex,
		})
		respond(player, requestId, outcome, retryAfterSec, stepIndex)
	end

	-- Returns true when this request may proceed without charging a new token:
	-- either it continues the currently-open cycle, or a fresh token is granted.
	local function admitCycle(player: Player, cycleId: string): (boolean, number?)
		local ttl = tonumber(afkConfig.AUTO_REJOIN_CYCLE_TTL_SEC) or 600
		local existing = activeCycles[player.UserId]
		if existing ~= nil then
			if existing.cycleId == cycleId and (os.clock() - existing.openedAt) <= ttl then
				return true, nil
			end
			-- Different or expired cycle: it is over, so drop it and re-admit.
			activeCycles[player.UserId] = nil
		end

		local allowed, _reason, waitSec = limiter:check(player.UserId)
		if not allowed then
			return false, waitSec
		end

		activeCycles[player.UserId] = {
			cycleId = cycleId,
			openedAt = os.clock(),
			rejoinConfirmed = false,
		}
		log:info("afk_cycle_opened", {
			player = player.Name,
			userId = player.UserId,
			cycleId = cycleId,
		})
		return true, nil
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

		-- Free server-state checks run before cycle admission: transient denials
		-- (in-flight, carry) must never consume a cycle token.
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
				deny(player, request.requestId, "in_flight", "denied_in_flight", 30, request.stepIndex)
				return
			end
		end

		local blocked, blockReason = isBlockedState(player)
		if blocked then
			deny(player, request.requestId, blockReason or "carry_active", "denied_carry_active", 60, request.stepIndex)
			notify.player(player, afkConfig.MSG_REJOIN_FAILED, "WARNING")
			return
		end

		local admitted, waitSec = admitCycle(player, request.cycleId)
		if not admitted then
			deny(player, request.requestId, "rate_limited", "denied_rate_limited", waitSec, request.stepIndex)
			notify.player(player, afkConfig.MSG_REJOIN_FAILED, "WARNING")
			return
		end

		if not sessionCommandService or type(sessionCommandService.handleAfkRejoin) ~= "function" then
			deny(player, request.requestId, "service_unavailable", "denied_service_unavailable", 60, request.stepIndex)
			notify.player(player, afkConfig.MSG_REJOIN_FAILED, "ERROR")
			return
		end

		local ladder = AfkGuardDomain.getLadder()
		local step = ladder[request.stepIndex]
		local sameServer = if step ~= nil then step.sameServer else true

		inFlightAfkRejoin[player.UserId] = os.clock()
		log:info("afk_rejoin_approved", {
			player = player.Name,
			userId = player.UserId,
			requestId = request.requestId,
			cycleId = request.cycleId,
			stepIndex = request.stepIndex,
			sameServer = sameServer,
			reportedIdleSec = request.reportedIdleSec,
		})
		respond(player, request.requestId, "allowed", nil, request.stepIndex)

		local ok, resultOrErr = pcall(function()
			return sessionCommandService:handleAfkRejoin(player, request.reportedIdleSec, sameServer)
		end)
		inFlightAfkRejoin[player.UserId] = nil
		if not ok then
			log:error("afk_teleport_throw", {
				player = player.Name,
				userId = player.UserId,
				stepIndex = request.stepIndex,
				error = tostring(resultOrErr),
			})
			respond(player, request.requestId, "rejoin_failed", 60, request.stepIndex)
			notify.player(player, afkConfig.MSG_REJOIN_FAILED, "ERROR")
			return
		end
		local result: Result<nil> = resultOrErr
		if not result.ok then
			log:warn("afk_teleport_failed", {
				player = player.Name,
				userId = player.UserId,
				stepIndex = request.stepIndex,
				reason = result.error,
			})
			respond(player, request.requestId, "rejoin_failed", 60, request.stepIndex)
			notify.player(player, afkConfig.MSG_REJOIN_FAILED, "ERROR")
			return
		end

		-- Confirmed: the player actually left as a result of this rejoin.
		local cycleEntry = activeCycles[player.UserId]
		if cycleEntry ~= nil then
			cycleEntry.rejoinConfirmed = true
		end
		log:info("afk_rejoin_confirmed", {
			player = player.Name,
			userId = player.UserId,
			cycleId = request.cycleId,
			stepIndex = request.stepIndex,
			sameServer = sameServer,
			reportedIdleSec = request.reportedIdleSec,
		})
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

	-- The leak metric. Without this you cannot tell "left because the rejoin
	-- worked" from "left because Roblox idle-kicked them" — which is exactly why
	-- the old failure mode was only ever visible as user complaints.
	function service:onPlayerRemoving(player: Player)
		inFlightAfkRejoin[player.UserId] = nil

		local cycleEntry = activeCycles[player.UserId]
		if cycleEntry ~= nil then
			if cycleEntry.rejoinConfirmed then
				log:info("afk_cycle_closed_rejoined", {
					player = player.Name,
					userId = player.UserId,
					cycleId = cycleEntry.cycleId,
				})
			else
				-- Left during an open AFK cycle with no confirmed rejoin: the
				-- ladder ran out or every rung failed. Treat as a leak.
				log:warn("afk_cycle_lost_player", {
					player = player.Name,
					userId = player.UserId,
					cycleId = cycleEntry.cycleId,
					cycleAgeSec = os.clock() - cycleEntry.openedAt,
				})
			end
			activeCycles[player.UserId] = nil
		end
	end

	function service:destroy()
		for _, conn in ipairs(_connections) do
			conn:Disconnect()
		end
		table.clear(_connections)
		table.clear(inFlightAfkRejoin)
		table.clear(activeCycles)
	end

	return service
end

return createAfkGuardService
