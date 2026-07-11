--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local function splitArgs(rawText: string): { string }
	local args: { string } = {}
	for token in string.gmatch(rawText, "%S+") do
		table.insert(args, token)
	end
	return args
end

local function createGravityController(deps: {
	service: any,
	commandExecutionService: any?,
	notify: any,
	logger: any,
	rateLimiter: any,
})
	local service = deps.service
	local commandExecutionService = deps.commandExecutionService
	local notify = deps.notify
	local logger = deps.logger
	local rateLimiter = deps.rateLimiter
	local gravityConfig = Config.Gravity

	local remotesFolder = ReplicatedStorage:FindFirstChild(gravityConfig.REMOTE_FOLDER)
	if remotesFolder == nil then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = gravityConfig.REMOTE_FOLDER
		remotesFolder.Parent = ReplicatedStorage
	end

	local commandRemote = remotesFolder:FindFirstChild(gravityConfig.COMMAND_REMOTE)
	if commandRemote == nil or not commandRemote:IsA("RemoteEvent") then
		if commandRemote ~= nil then
			commandRemote:Destroy()
		end
		commandRemote = Instance.new("RemoteEvent")
		commandRemote.Name = gravityConfig.COMMAND_REMOTE
		commandRemote.Parent = remotesFolder
	end

	local processedRequests: { [string]: number } = {}
	local PROCESSED_TTL = 30

	local function pruneProcessed(now: number): ()
		for requestId, createdAt in pairs(processedRequests) do
			if now - createdAt > PROCESSED_TTL then
				processedRequests[requestId] = nil
			end
		end
	end

	local function registerChatCommands(): ()
		if commandExecutionService == nil then
			return
		end

		commandExecutionService:registerRawHandler(gravityConfig.CMD_ALIAS, function(player: Player, rawText: string)
			local args = splitArgs(rawText)
			table.remove(args, 1)
			local argText = table.concat(args, " ")
			service:handleCommand(player, argText)
		end)

		commandExecutionService:registerRawHandler(gravityConfig.CMD_ALIAS_UNGRAVITY, function(player: Player, rawText: string)
			local args = splitArgs(rawText)
			table.remove(args, 1)
			local speedText = args[1]
			if speedText and speedText ~= "" then
				local speed = tonumber(speedText)
				if speed == nil then
					notify.player(player, gravityConfig.MSG_INVALID_SPEED, "WARNING")
					return
				end
				service:setSpeed(player, speed)
				return
			end
			service:enableDefault(player)
		end)
	end

	local function handleRemote(player: Player, payload: any): ()
		if Config.FeatureFlags.GravityEnabled ~= true then
			return
		end
		if type(payload) ~= "table" then
			return
		end
		if not rateLimiter:check(player.UserId) then
			notify.player(player, gravityConfig.MSG_RATE_LIMIT, "WARNING")
			return
		end

		local requestId = payload.requestId
		if type(requestId) ~= "string" or requestId == "" then
			return
		end

		local now = os.clock()
		pruneProcessed(now)
		if processedRequests[requestId] ~= nil then
			return
		end
		processedRequests[requestId] = now

		local action = payload.action
		if action == "disable" then
			service:disable(player)
			return
		end
		if action == "enable_default" then
			service:enableDefault(player)
			return
		end
		if action == "set" then
			local speed = payload.speed
			if type(speed) ~= "number" then
				return
			end
			service:setSpeed(player, speed)
		end
	end

	local controller = {}

	function controller:init(): ()
		registerChatCommands()
		commandRemote.OnServerEvent:Connect(handleRemote)
		logger:info("GravityController ready")
	end

	return controller
end

return createGravityController
