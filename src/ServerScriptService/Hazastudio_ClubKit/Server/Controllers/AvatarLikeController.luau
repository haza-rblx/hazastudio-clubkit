--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local NetworkManager = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkManager)
local Validator = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Validator)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
type AvatarContextLikeRequest = Types.AvatarContextLikeRequest
type AvatarContextLikeResult = Types.AvatarContextLikeResult
type AvatarLikeEffectPayload = Types.AvatarLikeEffectPayload
type ILogger = Types.ILogger
local function createAvatarLikeController(deps: {
	logger: ILogger,
	avatarLikeService: any,
	avatarContextController: any,
	overheadController: any,
	notify: any,
	likeRequestRemote: RemoteEvent,
	likeResultRemote: RemoteEvent,
	likeEffectRemote: RemoteEvent,
})
	local log = deps.logger
	local service = deps.avatarLikeService
	local avatarContextController = deps.avatarContextController
	local overheadController = deps.overheadController
	local notify = deps.notify
	local likeRequestRemote = deps.likeRequestRemote
	local likeResultRemote = deps.likeResultRemote
	local likeEffectRemote = deps.likeEffectRemote
	-- NetworkManager batches per-Heartbeat fires for like results.
	local resultNetwork = NetworkManager.create({
		reliable = likeResultRemote,
		logger = log,
		isServer = true,
	})
	-- Like effects (cosmetic VFX) get their own batched channel. Multiple
	-- nearby viewers receive the same payload in a single Heartbeat flush
	-- instead of one packet per recipient (V1 anti-pattern N3).
	local effectNetwork = NetworkManager.create({
		reliable = likeEffectRemote,
		logger = log,
		isServer = true,
	})
	local rateLimiter = RateLimiter.new(
		Config.AvatarContext.LIKE_RATE_MAX,
		Config.AvatarContext.LIKE_RATE_WINDOW
	)
	local processedRequests = {} :: {[string]: number}
	local controller = {}
	local function cleanupProcessedRequests()
		local now = os.clock()
		for requestId, expiresAt in pairs(processedRequests) do
			if expiresAt <= now then
				processedRequests[requestId] = nil
			end
		end
	end
	local function fireError(player: Player, requestId: string, targetUserId: number, message: string)
		local response: AvatarContextLikeResult = {
			requestId = requestId,
			ok = false,
			targetUserId = targetUserId,
			error = message,
		}
		resultNetwork:fireClient(player, response)
	end
	local function getRootPart(player: Player): BasePart?
		local character = player.Character
		if not character then
			return nil
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return root
		end
		return nil
	end
	function controller:_broadcastLikeEffect(fromPlayer: Player, targetPlayer: Player)
		local payload: AvatarLikeEffectPayload = {
			fromUserId = fromPlayer.UserId,
			toUserId = targetPlayer.UserId,
			heartCount = Config.AvatarContext.LIKE_HEART_COUNT,
		}
		local recipients = {} :: {[Player]: true}
		local fromRoot = getRootPart(fromPlayer)
		local targetRoot = getRootPart(targetPlayer)
		recipients[fromPlayer] = true
		recipients[targetPlayer] = true
		if fromRoot or targetRoot then
			for _, otherPlayer in ipairs(Players:GetPlayers()) do
				local otherRoot = getRootPart(otherPlayer)
				if otherRoot then
					local withinFrom = fromRoot and (otherRoot.Position - fromRoot.Position).Magnitude <= Config.AvatarContext.LIKE_EFFECT_RADIUS
					local withinTarget = targetRoot and (otherRoot.Position - targetRoot.Position).Magnitude <= Config.AvatarContext.LIKE_EFFECT_RADIUS
					if withinFrom or withinTarget then
						recipients[otherPlayer] = true
					end
				end
			end
		end
		local recipientList: { Player } = {}
		for player in pairs(recipients) do
			table.insert(recipientList, player)
		end
		effectNetwork:fireList(recipientList, payload)
	end
	function controller:_handleRequest(player: Player, raw: any)
		if not Validator.checkSize(raw) then
			log:warn("AvatarLike payload too large", { player = player.Name })
			fireError(player, "", 0, "Invalid payload")
			return
		end
		local validation = Validator.avatarContextLike(raw)
		if not validation.valid then
			log:warn("AvatarLike invalid request", {
				player = player.Name,
				errors = table.concat(validation.errors, ", "),
			})
			local requestId = type(raw) == "table" and type(raw.requestId) == "string" and raw.requestId or ""
			local targetUserId = type(raw) == "table" and type(raw.targetUserId) == "number" and raw.targetUserId or 0
			fireError(player, requestId, targetUserId, "Invalid payload")
			return
		end
		local request = raw :: AvatarContextLikeRequest
		if not rateLimiter:check(player.UserId) then
			fireError(player, request.requestId, request.targetUserId, Config.AvatarContext.MSG_LIKE_RATE_LIMIT)
			return
		end
		cleanupProcessedRequests()
		if processedRequests[request.requestId] then
			log:debug("AvatarLike duplicate request ignored", {
				player = player.Name,
				requestId = request.requestId,
			})
			return
		end
		processedRequests[request.requestId] = os.clock() + Config.Security.REQUEST_DEDUPE_WINDOW
		local targetPlayer = Players:GetPlayerByUserId(request.targetUserId)
		if not targetPlayer then
			fireError(player, request.requestId, request.targetUserId, "Target player not found")
			return
		end
		-- task.spawn: service:toggle melakukan write persistence di repository layer.
		-- Jangan block OnServerEvent handler - concurrent like dari player lain bisa tetap diproses.
		task.spawn(function()
			local toggleResult = service:toggle(player, targetPlayer, request.action)
			if not toggleResult.ok then
				fireError(player, request.requestId, request.targetUserId, toggleResult.error)
				return
			end
			local response: AvatarContextLikeResult = {
				requestId = request.requestId,
				ok = true,
				targetUserId = request.targetUserId,
				likesCount = toggleResult.value.likesCount,
				viewerHasLiked = toggleResult.value.viewerHasLiked,
				transition = toggleResult.value.transition,
			}
			resultNetwork:fireClient(player, response)
			if overheadController and type(overheadController.refreshPlayer) == "function" then
				overheadController:refreshPlayer(targetPlayer)
			end
			if avatarContextController and type(avatarContextController.pushContextUpdate) == "function" then
				avatarContextController:pushContextUpdate(targetPlayer.UserId)
			end
			if toggleResult.value.transition == "first_like" then
				notify.player(
					targetPlayer,
					string.format(Config.AvatarContext.LIKE_NOTIF_MESSAGE, player.DisplayName),
					"SUCCESS"
				)
				controller:_broadcastLikeEffect(player, targetPlayer)
			end
		end)
	end
	function controller:init()
		likeRequestRemote.OnServerEvent:Connect(function(player: Player, raw: any)
			controller:_handleRequest(player, raw)
		end)
		log:info("AvatarLikeController initialized")
	end
	return controller
end
return createAvatarLikeController
