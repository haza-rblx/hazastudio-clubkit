--!strict
-- SyncController - Remote handler layer for sync/dance.
--
-- Refactored 2026-05-23: stripped visual state replication. Server is now the
-- only source for animations, and Roblox handles cross-client replication
-- automatically. The notification channel still exists for UX feedback
-- (sync_success, leader_left, anim_result, etc.).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local NetworkManager = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkManager)
local TTLSet = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.TTLSet)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

local function createSyncController(deps: {
	service: any,
	config: any,
	validator: any,
	taskQueue: any,
	logger: any,
	favoritesRepository: any,
	rateLimiters: { [string]: any },
})
	local config = deps.config.Sync
	local securityConfig = deps.config.Security
	local validator = deps.validator
	local taskQueue = deps.taskQueue
	local logger = deps.logger
	local service = deps.service
	local favoritesRepository = deps.favoritesRepository
	local rateLimiters = deps.rateLimiters
	
	local processedFavoritesReqs = TTLSet.create({
		ttl = securityConfig.REQUEST_DEDUPE_WINDOW,
		maxSize = securityConfig.MAX_REQUEST_CACHE or 500,
	})

	local syncRemotes = ReplicatedStorage:FindFirstChild(config.REMOTE_FOLDER)
	if not syncRemotes then
		syncRemotes = Instance.new("Folder")
		syncRemotes.Name = config.REMOTE_FOLDER
		syncRemotes.Parent = ReplicatedStorage
	end

	local function getOrCreateRemote(name: string, className: "RemoteEvent")
		local existing = syncRemotes:FindFirstChild(name)
		if existing then
			if existing.ClassName == className then
				return existing
			end
			existing:Destroy()
		end
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = syncRemotes
		return remote
	end

	local animationStartRE = getOrCreateRemote(config.REMOTE_ANIMATION_START, "RemoteEvent") :: RemoteEvent
	local startSyncRE = getOrCreateRemote(config.REMOTE_START_SYNC, "RemoteEvent") :: RemoteEvent
	local changeSpeedRE = getOrCreateRemote(config.REMOTE_CHANGE_SPEED, "RemoteEvent") :: RemoteEvent
	local updateFavoritesRE = getOrCreateRemote(config.REMOTE_UPDATE_FAVORITES, "RemoteEvent") :: RemoteEvent
	local syncNotificationRE = getOrCreateRemote(config.REMOTE_NOTIFICATION, "RemoteEvent") :: RemoteEvent

	-- Clean up legacy visual state remote left behind from the dual-render era.
	local staleVisual = syncRemotes:FindFirstChild(config.REMOTE_VISUAL_STATE)
	if staleVisual then
		staleVisual:Destroy()
	end

	-- Per-frame batched transport for SyncController responses.
	local networkManager = NetworkManager.create({
		reliable = syncNotificationRE,
		logger = Logger.new("SyncNetworkManager"),
		isServer = true,
	})

	-- ============================================================
	-- animationStartRE: client requests play/stop
	-- ============================================================
	animationStartRE.OnServerEvent:Connect(
		function(player: Player, animation: any, shouldPlay: any, speed: any, intent: any)
			local actionIntent = if type(intent) == "string" then intent else "play"

			-- Payload guard
			local animSize = if typeof(animation) == "Instance" and animation:IsA("Animation")
				then #tostring((animation :: Animation).AnimationId or "")
				else 0
			local totalSize = animSize + #actionIntent + 16
			if totalSize > config.MAX_PAYLOAD_BYTES then
				logger:warn("Payload too large", {
					player = player.Name,
					size = totalSize,
					maxAllowed = config.MAX_PAYLOAD_BYTES,
				})
				return
			end

			local validation = validator.animStart(animation, shouldPlay, speed, actionIntent)
			if not validation.valid then
				return
			end

			if not rateLimiters.ANIM_START:check(player.UserId) then
				networkManager:fireClient(player, { type = "anim_result", result = "rate_limited" })
				return
			end

			taskQueue:enqueue(function()
				local result = service:executeAnimation(player, animation, shouldPlay, speed, actionIntent)
				local animName = typeof(animation) == "Instance" and animation:IsA("Animation") and animation.Name
					or nil
				networkManager:fireClient(player, {
					type = "anim_result",
					result = result.ok and result.value or result.error,
					animationName = animName,
				})
			end)
		end
	)

	-- ============================================================
	-- startSyncRE: client requests sync/unsync
	-- ============================================================
	startSyncRE.OnServerEvent:Connect(function(player: Player, targetPlayer: any, shouldSync: any, transferLead: any)
		if shouldSync then
			if not targetPlayer or typeof(targetPlayer) ~= "Instance" or not targetPlayer:IsA("Player") then
				logger:warn("Invalid targetPlayer in sync request", {
					player = player.Name,
					targetType = typeof(targetPlayer),
				})
				return
			end
		end

		local validation = validator.syncRequest(targetPlayer or player, shouldSync, transferLead)
		if not validation.valid then
			logger:warn("Invalid sync request", { player = player.Name })
			return
		end

		-- Force unsync to operate on self only (anti-exploit)
		local resolvedTarget = if shouldSync then targetPlayer else player
		local isTransfer = shouldSync == true and transferLead == true

		if not rateLimiters.SYNC_REQUEST:check(player.UserId) then
			networkManager:fireClient(player, { type = "rate_limited" })
			return
		end

		taskQueue:enqueue(function()
			local result
			if isTransfer then
				result = service:handleTransferLead(player, resolvedTarget)
			else
				result = service:handleSyncRequest(player, resolvedTarget, shouldSync)
			end
			if result.ok then
				if shouldSync then
					local leaderName = result.value
					networkManager:fireClient(player, {
						type = if isTransfer then "transfer_success" else "sync_success",
						leaderName = leaderName,
						leaderDisplay = service:getLeaderDisplayName(leaderName),
						currentAnim = service:getCurrentAnimationName(leaderName),
						targetUserId = resolvedTarget.UserId,
					})
				else
					networkManager:fireClient(player, { type = "unsync_success" })
				end
				return
			end
			networkManager:fireClient(player, { type = result.error })
		end)
	end)

	-- ============================================================
	-- changeSpeedRE: client adjusts playback speed
	-- ============================================================
	changeSpeedRE.OnServerEvent:Connect(function(player: Player, speed: any)
		local validation = validator.speedChange(speed)
		if not validation.valid then
			return
		end
		if not rateLimiters.SPEED_CHANGE:check(player.UserId) then
			return
		end
		taskQueue:enqueue(function()
			service:adjustSpeed(player, speed)
		end)
	end)

	-- ============================================================
	-- updateFavoritesRE: client updates favorites JSON
	-- Five-gate pattern: envelope, size, rate, idempotency, authorization.
	-- ============================================================
	updateFavoritesRE.OnServerEvent:Connect(function(player: Player, raw: any)
		local jsonData: string? = nil
		local requestId: string? = nil

		if type(raw) == "string" then
			jsonData = raw
		elseif type(raw) == "table" then
			if type(raw.data) == "string" then
				jsonData = raw.data
			end
			if type(raw.requestId) == "string" then
				requestId = raw.requestId
			end
		end

		if not jsonData then
			logger:warn("Favorites update rejected: missing data", { player = player.Name })
			return
		end
		if not requestId or #requestId < 8 then
			logger:warn("Favorites update rejected: missing requestId", { player = player.Name })
			return
		end

		local validation = validator.favoritesUpdate(jsonData)
		if not validation.valid then
			logger:warn("Favorites update rejected: invalid data", { player = player.Name })
			return
		end

		if not rateLimiters.FAVORITES_UPDATE:check(player.UserId) then
			logger:warn("Favorites update rate limited", { player = player.Name })
			return
		end

		local dedupeKey = player.UserId .. ":" .. requestId
		if processedFavoritesReqs:contains(dedupeKey) then
			return
		end
		processedFavoritesReqs:add(dedupeKey)

		local decodeOk, incoming = pcall(function()
			return HttpService:JSONDecode(jsonData)
		end)
		if not decodeOk or type(incoming) ~= "table" then
			logger:warn("Favorites update rejected: invalid json", { player = player.Name })
			return
		end

		local merged = favoritesRepository:loadDecoded(player)
		for animationName, favorited in pairs(incoming) do
			if type(animationName) == "string" and favorited == true then
				merged[animationName] = true
			elseif type(animationName) == "string" then
				merged[animationName] = nil
			end
		end

		local compact: { [string]: boolean } = {}
		for animationName, favorited in pairs(merged) do
			if favorited == true then
				compact[animationName] = true
			end
		end

		local encodeOk, encoded = pcall(function()
			return HttpService:JSONEncode(compact)
		end)
		if not encodeOk or type(encoded) ~= "string" then
			logger:warn("Favorites update rejected: encode failed", { player = player.Name })
			return
		end

		local favoritesMax = (deps.config.Favorites and deps.config.Favorites.MAX_PAYLOAD_BYTES) or 32 * 1024
		if #encoded > favoritesMax then
			logger:warn("Favorites update rejected: merged payload too large", {
				player = player.Name,
				bytes = #encoded,
				maxAllowed = favoritesMax,
			})
			return
		end

		player:SetAttribute(deps.config.Favorites.ATTRIBUTE_KEY, encoded)
		local result = favoritesRepository:save(player.UserId, encoded)
		if not result.ok then
			logger:error("Favorites update failed", { player = player.Name, error = result.error })
		end
	end)

	logger:info("SyncController initialized")

	-- ============================================================
	-- Leader-left fan-out (called from Main.server when a leader
	-- disconnects or hard-unsyncs after respawn).
	-- ============================================================
	local function notifyLeaderDisconnected(leaderName: string, followerNames: { string })
		if type(leaderName) ~= "string" or type(followerNames) ~= "table" then
			return
		end
		for _, followerName in ipairs(followerNames) do
			local follower = Players:FindFirstChild(followerName)
			if follower then
				networkManager:fireClient(follower, {
					type = "leader_left",
					leaderName = leaderName,
				})
			end
		end
	end

	return {
		syncRemotes = syncRemotes,
		notifyLeaderDisconnected = notifyLeaderDisconnected,
	}
end

return createSyncController
