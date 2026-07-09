--!strict
-- ServerScriptService/Server/Controllers/AvatarContextController.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Validator = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Validator)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local NetworkManager = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkManager)
type AvatarContextRequest = Types.AvatarContextRequest
type AvatarContextResponse = Types.AvatarContextResponse
type AvatarContextUpdatedPayload = Types.AvatarContextUpdatedPayload
type ILogger = Types.ILogger
local function createAvatarContextController(deps: {
	logger: ILogger,
	avatarContextService: any,
	profileUpdatedRemote: RemoteEvent,
	updatedRemote: RemoteEvent,
	closeRemote: RemoteEvent,
})
	local log = deps.logger
	local service = deps.avatarContextService
	local profileUpdatedRemote = deps.profileUpdatedRemote
	local updatedRemote = deps.updatedRemote
	local closeRemote = deps.closeRemote
	-- NetworkManagers batch per-Heartbeat. Even when each viewer gets a
	-- distinct payload (build per-viewer), batching coalesces multiple fires
	-- in the same frame into one wire flush.
	local profileUpdatedNetwork = NetworkManager.create({
		reliable = profileUpdatedRemote,
		logger = log,
		isServer = true,
	})
	local updatedNetwork = NetworkManager.create({
		reliable = updatedRemote,
		logger = log,
		isServer = true,
	})
	-- Response NetworkManager initializes lazily inside init() once the
	-- WaitForChild remote resolves.
	local responseNetwork: any = nil
	local rateLimiter = RateLimiter.new(
		Config.AvatarContext.REQUEST_RATE_MAX,
		Config.AvatarContext.REQUEST_RATE_WINDOW
	)
	-- TTL-based dedup agar tidak memory leak saat server hidup lama
	local processedRequests = {} :: { [string]: number }
	local viewersByTarget = {} :: {[number]: {[number]: Player}}
	local targetByViewer = {} :: {[number]: number}

	local controller = {}
	local function unregisterViewer(viewerUserId: number)
		local targetUserId = targetByViewer[viewerUserId]
		if not targetUserId then
			return
		end
		targetByViewer[viewerUserId] = nil
		local viewers = viewersByTarget[targetUserId]
		if viewers then
			viewers[viewerUserId] = nil
			if next(viewers) == nil then
				viewersByTarget[targetUserId] = nil
			end
		end
	end
	local function registerViewer(viewer: Player, targetUserId: number)
		unregisterViewer(viewer.UserId)
		targetByViewer[viewer.UserId] = targetUserId
		viewersByTarget[targetUserId] = viewersByTarget[targetUserId] or {}
		viewersByTarget[targetUserId][viewer.UserId] = viewer
	end

	function controller:init()
		local remoteRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Config.AvatarContext.REMOTE_REQUEST)
		local remoteResponse = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Config.AvatarContext.REMOTE_RESPONSE)

		responseNetwork = NetworkManager.create({
			reliable = remoteResponse,
			logger = log,
			isServer = true,
		})

		remoteRequest.OnServerEvent:Connect(function(player: Player, raw: any)
			controller:_handleRequest(player, raw, remoteResponse)
		end)
		closeRemote.OnServerEvent:Connect(function(player: Player)
			unregisterViewer(player.UserId)
		end)
		Players.PlayerRemoving:Connect(function(player: Player)
			unregisterViewer(player.UserId)
			viewersByTarget[player.UserId] = nil
			-- Drop cached payloads where this player was target or viewer.
			if type(service.invalidateForTarget) == "function" then
				service:invalidateForTarget(player.UserId)
			end
			if type(service.invalidateForViewer) == "function" then
				service:invalidateForViewer(player.UserId)
			end
		end)

		log:info("AvatarContextController initialized")
	end

	function controller:_handleRequest(player: Player, raw: any, remoteResponse: RemoteEvent)
		-- size check dulu sebelum akses field apapun
		if not Validator.checkSize(raw) then
			log:warn("Payload terlalu besar", { player = player.Name })
			return
		end

		-- Validate schema
		if type(raw) ~= "table" then
			log:warn("Invalid request: not a table", { player = player.Name })
			return
		end

		if type(raw.targetUserId) ~= "number" then
			log:warn("Invalid request: targetUserId not a number", { player = player.Name })
			return
		end

		if type(raw.requestId) ~= "string" then
			log:warn("Invalid request: requestId not a string", { player = player.Name })
			return
		end

		local request = raw :: AvatarContextRequest

		-- Rate limit
		if not rateLimiter:check(player.UserId) then
			-- Demote ke debug: client spam adalah pola normal, warn level
			-- bikin developer console banjir saat 70-80 player main bareng.
			log:debug("Rate limit hit", { player = player.Name })
			local response: AvatarContextResponse = {
				requestId = request.requestId,
				ok = false,
				error = "Rate limit exceeded",
			}
			responseNetwork:fireClient(player, response)
			return
		end

		-- TTL-based idempotency check + expired entries cleanup
		local now = os.clock()
		for key, expiresAt in pairs(processedRequests) do
			if expiresAt <= now then
				processedRequests[key] = nil
			end
		end
		if processedRequests[request.requestId] then
			log:debug("Duplicate request ignored", { requestId = request.requestId })
			return
		end
		processedRequests[request.requestId] = now + Config.Security.REQUEST_DEDUPE_WINDOW

		-- Validate target exists in game
		local targetPlayer = Players:GetPlayerByUserId(request.targetUserId)
		if not targetPlayer then
			local response: AvatarContextResponse = {
				requestId = request.requestId,
				ok = false,
				error = "Target player not found",
			}
			responseNetwork:fireClient(player, response)
			return
		end

		-- Build payload - dijalankan di thread terpisah agar tidak blocking
		-- handler lain sementara menunggu network/DataStore calls.
		task.spawn(function()
			local result = service:buildPayload(targetPlayer, player)

			if not result.ok then
				local response: AvatarContextResponse = {
					requestId = request.requestId,
					ok = false,
					error = result.error,
				}
				responseNetwork:fireClient(player, response)
				return
			end

			-- Send success response
			registerViewer(player, targetPlayer.UserId)
			local response: AvatarContextResponse = {
				requestId = request.requestId,
				ok = true,
				payload = result.value,
			}
			responseNetwork:fireClient(player, response)
		end)
	end
	function controller:pushProfileUpdate(targetUserId: number)
		local targetPlayer = Players:GetPlayerByUserId(targetUserId)
		if not targetPlayer then
			viewersByTarget[targetUserId] = nil
			return
		end
		-- Profile berubah: invalidate cache supaya rebuild fresh.
		if type(service.invalidateForTarget) == "function" then
			service:invalidateForTarget(targetUserId)
		end
		local viewers = viewersByTarget[targetUserId]
		if not viewers then
			return
		end
		for viewerUserId, viewer in pairs(viewers) do
			if viewer.Parent == Players then
				-- task.spawn per viewer agar tidak blocking saat banyak viewers
				task.spawn(function()
					local result = service:buildPayload(targetPlayer, viewer)
					if result.ok then
						profileUpdatedNetwork:fireClient(viewer, {
							targetUserId = targetUserId,
							bio = result.value.bio,
							statusText = result.value.statusText,
						})
					end
				end)
			else
				viewers[viewerUserId] = nil
				targetByViewer[viewerUserId] = nil
			end
		end
		if next(viewers) == nil then
			viewersByTarget[targetUserId] = nil
		end
	end
	function controller:pushContextUpdate(targetUserId: number)
		local targetPlayer = Players:GetPlayerByUserId(targetUserId)
		if not targetPlayer then
			viewersByTarget[targetUserId] = nil
			return
		end
		-- Context berubah (overhead/like/etc): invalidate cache.
		if type(service.invalidateForTarget) == "function" then
			service:invalidateForTarget(targetUserId)
		end
		local viewers = viewersByTarget[targetUserId]
		if not viewers then
			return
		end
		for viewerUserId, viewer in pairs(viewers) do
			if viewer.Parent == Players then
				-- task.spawn per viewer agar tidak blocking saat banyak viewers
				task.spawn(function()
					local result = service:buildPayload(targetPlayer, viewer)
					if result.ok then
						local payload: AvatarContextUpdatedPayload = {
							targetUserId = targetUserId,
							payload = result.value,
						}
						updatedNetwork:fireClient(viewer, payload)
					end
				end)
			else
				viewers[viewerUserId] = nil
				targetByViewer[viewerUserId] = nil
			end
		end
		if next(viewers) == nil then
			viewersByTarget[targetUserId] = nil
		end
	end

	return controller
end
return createAvatarContextController
