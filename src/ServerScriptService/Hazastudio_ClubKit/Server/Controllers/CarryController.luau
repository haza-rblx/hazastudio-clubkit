--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PROCESSED_REQUEST_TTL = 60
local PROCESSED_REQUEST_MAX = 500

local NetworkManager = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkManager)

local function createCarryController(deps: {
	service: any,
	config: any,
	validator: any,
	taskQueue: any,
	logger: any,
	rateLimiters: { [string]: any },
})
	local service = deps.service
	local config = deps.config
	local carryConfig = config.Carry
	local validator = deps.validator
	local taskQueue = deps.taskQueue
	local logger = deps.logger
	local rateLimiters = deps.rateLimiters

	local remotesFolder = ReplicatedStorage:FindFirstChild(carryConfig.REMOTE_FOLDER)
	if remotesFolder == nil then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = carryConfig.REMOTE_FOLDER
		remotesFolder.Parent = ReplicatedStorage
	end

	local commandRemote = remotesFolder:FindFirstChild(carryConfig.COMMAND_REMOTE)
	if commandRemote == nil or not commandRemote:IsA("RemoteEvent") then
		if commandRemote ~= nil then
			commandRemote:Destroy()
		end
		commandRemote = Instance.new("RemoteEvent")
		commandRemote.Name = carryConfig.COMMAND_REMOTE
		commandRemote.Parent = remotesFolder
	end

	local notifyRemote = remotesFolder:FindFirstChild(carryConfig.NOTIFY_REMOTE)
	if notifyRemote == nil or not notifyRemote:IsA("RemoteEvent") then
		if notifyRemote ~= nil then
			notifyRemote:Destroy()
		end
		notifyRemote = Instance.new("RemoteEvent")
		notifyRemote.Name = carryConfig.NOTIFY_REMOTE
		notifyRemote.Parent = remotesFolder
	end

	local debugRemote = remotesFolder:FindFirstChild(carryConfig.DEBUG_REMOTE)
	if debugRemote == nil or not debugRemote:IsA("RemoteEvent") then
		if debugRemote ~= nil then
			debugRemote:Destroy()
		end
		debugRemote = Instance.new("RemoteEvent")
		debugRemote.Name = carryConfig.DEBUG_REMOTE
		debugRemote.Parent = remotesFolder
	end

	local processedRequests: { [string]: number } = {}

	-- NetworkManagers batch per-Heartbeat. Carry sessions fire request +
	-- accept/reject + end notifications, often in rapid succession; batching
	-- coalesces the burst onto one wire flush per recipient.
	local notifyNetwork = NetworkManager.create({
		reliable = notifyRemote :: RemoteEvent,
		logger = logger,
		isServer = true,
	})
	local debugNetwork = NetworkManager.create({
		reliable = debugRemote :: RemoteEvent,
		logger = logger,
		isServer = true,
	})

	local function pruneProcessedRequests(now: number): ()
		local count = 0
		for requestId, createdAt in pairs(processedRequests) do
			count += 1
			if now - createdAt > PROCESSED_REQUEST_TTL then
				processedRequests[requestId] = nil
				count -= 1
			end
		end

		if count <= PROCESSED_REQUEST_MAX then
			return
		end

		local oldestRequestId: string? = nil
		local oldestCreatedAt = math.huge
		for requestId, createdAt in pairs(processedRequests) do
			if createdAt < oldestCreatedAt then
				oldestCreatedAt = createdAt
				oldestRequestId = requestId
			end
		end
		if oldestRequestId ~= nil then
			processedRequests[oldestRequestId] = nil
		end
	end

	local function notify(player: Player, notificationType: string, payload: any?): ()
		notifyNetwork:fireClient(player, notificationType, payload or {})
	end

	local function isDebugAllowed(player: Player): boolean
		if carryConfig.DEBUG_CALIBRATION_ENABLED ~= true then
			return false
		end
		if RunService:IsStudio() then
			return true
		end
		local allowed = carryConfig.DEBUG_CALIBRATION_ALLOWED_USER_IDS
		return type(allowed) == "table" and allowed[player.UserId] == true
	end

	local function fireDebugState(player: Player, calibration: any?): ()
		debugNetwork:fireClient(player, "State", calibration or {})
	end

	local function resolveTarget(payload: any): Player?
		local targetUserId = payload.targetUserId
		if type(targetUserId) ~= "number" and type(payload.targetId) == "number" then
			targetUserId = payload.targetId
		end
		if type(targetUserId) == "number" then
			local byId = Players:GetPlayerByUserId(targetUserId)
			if byId ~= nil then
				return byId
			end
		end
		if type(payload.targetName) == "string" and payload.targetName ~= "" then
			return Players:FindFirstChild(payload.targetName)
		end
		return nil
	end

	local handlers: { [string]: (Player, any) -> () } = {
		REQUEST = function(player: Player, payload: any)
			local target = resolveTarget(payload)
			if target == nil then
				notify(player, "RequestFailed", { reason = "target_not_found" })
				return
			end

			local result = service:requestCarry(player, target, payload.style)
			if not result.ok then
				notify(player, "RequestFailed", { reason = result.error })
				return
			end

			notify(target, "ShowRequest", {
				carrierUserId = player.UserId,
				carrierName = player.DisplayName,
				carrierUsername = player.Name,
				style = payload.style,
			})
			notify(player, "RequestSent", {
				targetUserId = target.UserId,
				targetName = target.DisplayName,
				style = payload.style,
			})
		end,
		ACCEPT = function(player: Player, _payload: any)
			local request = service:getPendingRequest(player.UserId)
			local result = service:acceptCarry(player)
			if not result.ok then
				notify(player, "RequestFailed", { reason = result.error })
				return
			end

			local carrier = if request then Players:GetPlayerByUserId(request.carrierId) else nil
			if carrier ~= nil then
				notify(carrier, "CarryStarted", {
					partnerUserId = player.UserId,
					partnerName = player.DisplayName,
					style = request.style,
				})
			end
			notify(player, "BeingCarried", {
				partnerUserId = request and request.carrierId or nil,
				partnerName = carrier and carrier.DisplayName or nil,
				style = request and request.style or nil,
			})
		end,
		REJECT = function(player: Player, _payload: any)
			local request = service:getPendingRequest(player.UserId)
			local result = service:rejectCarry(player)
			if not result.ok then
				return
			end
			local carrier = if request then Players:GetPlayerByUserId(request.carrierId) else nil
			if carrier ~= nil then
				notify(carrier, "RequestRejected", {
					targetUserId = player.UserId,
					targetName = player.DisplayName,
				})
			end
		end,
		END = function(player: Player, _payload: any)
			local partnerId = service:getPartnerId(player.UserId)
			local result = service:endCarry(player)
			if not result.ok then
				return
			end
			notify(player, "CarryEnded", {})
			if partnerId ~= nil then
				local partner = Players:GetPlayerByUserId(partnerId)
				if partner ~= nil then
					notify(partner, "CarryEnded", {})
				end
			end
		end,
	}

	(commandRemote :: RemoteEvent).OnServerEvent:Connect(function(player: Player, raw: any)
		if type(raw) ~= "table" then
			return
		end

		local sizeOk, encodedOrErr = pcall(function()
			return HttpService:JSONEncode(raw)
		end)
		if not sizeOk or #encodedOrErr > config.Security.MAX_PAYLOAD_BYTES then
			logger:warn("Carry payload rejected", {
				player = player.Name,
				size = if sizeOk then #encodedOrErr else -1,
			})
			return
		end

		local validation = validator.carryCommand(raw)
		if not validation.valid then
			logger:warn("Invalid carry command", {
				player = player.Name,
				type = tostring(raw.type),
				requestId = tostring(raw.requestId),
				errors = table.concat(validation.errors, "; "),
			})
			return
		end

		local limiter = rateLimiters[raw.type]
		if limiter ~= nil and not limiter:check(player.UserId) then
			notify(player, "RequestFailed", { reason = "rate_limited" })
			return
		end

		local now = os.clock()
		pruneProcessedRequests(now)

		if processedRequests[raw.requestId] ~= nil then
			return
		end
		processedRequests[raw.requestId] = now

		local handler = handlers[raw.type]
		if handler == nil then
			return
		end

		taskQueue:enqueue(function()
			handler(player, raw.payload)
		end)
	end)
	local debugRemoteEvent = debugRemote :: RemoteEvent
	debugRemoteEvent.OnServerEvent:Connect(function(player: Player, raw: any)
		if not isDebugAllowed(player) or type(raw) ~= "table" then
			return
		end

		local action = raw.action
		local calibration = nil
		if action == "snapshot" then
			calibration = service:getCalibration(player)
		elseif action == "adjust" then
			if type(raw.axis) ~= "string" or type(raw.amount) ~= "number" then
				return
			end
			if math.abs(raw.amount) > 10 then
				return
			end
			calibration = service:adjustCalibration(player, raw.axis, raw.amount)
		elseif action == "inverse" then
			calibration = service:toggleCalibrationInverse(player)
		elseif action == "print" then
			calibration = service:printCalibration(player)
		end

		fireDebugState(player, calibration)
	end)

	logger:info("CarryController initialized")
	return {
		commandRemote = commandRemote,
		notifyRemote = notifyRemote,
		debugRemote = debugRemote,
	}
end

return createCarryController
