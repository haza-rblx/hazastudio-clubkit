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

local function createAfkGuardService(deps: {
	notify: any,
	sessionCommandService: any,
	carryService: any?,
	remotes: Folder,
})
	local notify = deps.notify
	local sessionCommandService = deps.sessionCommandService
	local carryService = deps.carryService
	local remotes = deps.remotes
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
	local inFlightAfkRejoin: { [number]: boolean } = {}

	local _connections: { RBXScriptConnection } = {}
	local service = {}

	local function track(conn: RBXScriptConnection): RBXScriptConnection
		table.insert(_connections, conn)
		return conn
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
			log:info("afk_rejoin_denied", {
				player = player.Name,
				userId = player.UserId,
				reason = validated.error,
			})
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

		if not limiter:check(player.UserId) then
			log:info("afk_rejoin_denied", {
				player = player.Name,
				userId = player.UserId,
				reason = "rate_limited",
			})
			notify.player(player, afkConfig.MSG_REJOIN_FAILED, "WARNING")
			return
		end

		if inFlightAfkRejoin[player.UserId] then
			log:info("afk_rejoin_denied", {
				player = player.Name,
				userId = player.UserId,
				reason = "in_flight",
			})
			return
		end

		local blocked, blockReason = isBlockedState(player)
		if blocked then
			log:info("afk_rejoin_denied", {
				player = player.Name,
				userId = player.UserId,
				reason = blockReason,
			})
			notify.player(player, afkConfig.MSG_REJOIN_FAILED, "WARNING")
			return
		end

		if not sessionCommandService or type(sessionCommandService.handleAfkRejoin) ~= "function" then
			log:warn("afk_rejoin_denied", {
				player = player.Name,
				userId = player.UserId,
				reason = "service_unavailable",
			})
			notify.player(player, afkConfig.MSG_REJOIN_FAILED, "ERROR")
			return
		end

		inFlightAfkRejoin[player.UserId] = true
		log:info("afk_rejoin_approved", {
			player = player.Name,
			userId = player.UserId,
			requestId = request.requestId,
			reportedIdleSec = request.reportedIdleSec,
		})

		local result: Result<nil> = sessionCommandService:handleAfkRejoin(player, request.reportedIdleSec)
		if not result.ok then
			inFlightAfkRejoin[player.UserId] = nil
			log:warn("afk_teleport_failed", {
				player = player.Name,
				userId = player.UserId,
				reason = result.error,
			})
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
