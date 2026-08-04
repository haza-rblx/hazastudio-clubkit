--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local PermissionDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.PermissionDomain)

local function splitArgs(rawText: string): { string }
	local args: { string } = {}
	for token in string.gmatch(rawText, "%S+") do
		table.insert(args, token)
	end
	return args
end

local function createDroneController(deps: {
	service: any,
	commandExecutionService: any?,
	overheadService: any?,
	notify: any,
	logger: any,
	rateLimiter: any,
	cameraRateLimiter: any,
	remotes: Folder,
})
	local service = deps.service
	local commandExecutionService = deps.commandExecutionService
	local overheadService = deps.overheadService
	local notify = deps.notify
	local logger = deps.logger
	local rateLimiter = deps.rateLimiter
	local cameraRateLimiter = deps.cameraRateLimiter
	local remotes = deps.remotes
	local droneConfig = Config.Drone

	local requestRemote = remotes:FindFirstChild(droneConfig.REMOTE_REQUEST) :: RemoteEvent?
	local cameraRemote = remotes:FindFirstChild(droneConfig.REMOTE_CAMERA) :: RemoteEvent?

	local function canUse(player: Player): boolean
		if overheadService and type(overheadService.getEffectivePayload) == "function" then
			local payloadResult = overheadService:getEffectivePayload(player)
			if payloadResult.ok then
				return PermissionDomain.canUseAdminPanel(payloadResult.value.role, player.UserId)
			end
		end
		if overheadService and type(overheadService.getRawGroupRole) == "function" then
			return PermissionDomain.canUseAdminPanel(overheadService:getRawGroupRole(player), player.UserId)
		end
		return PermissionDomain.canUseAdminPanel(nil, player.UserId)
	end

	local function denyIfUnauthorized(player: Player): boolean
		if canUse(player) then
			return false
		end
		notify.player(player, droneConfig.MSG_NO_PERM, "WARNING")
		return true
	end

	local function tryStart(player: Player)
		if denyIfUnauthorized(player) then
			return
		end
		if not rateLimiter:check(player.UserId) then
			notify.player(player, droneConfig.MSG_RATE_LIMIT, "WARNING")
			return
		end
		local ok, err = service:start(player)
		if not ok then
			notify.player(player, err or droneConfig.MSG_ALREADY, "WARNING")
			return
		end
		notify.player(player, droneConfig.MSG_STARTED, "SUCCESS")
		notify.all(string.format(droneConfig.MSG_STARTED_ALL, player.DisplayName), "INFO")
	end

	local function tryStop(player: Player)
		if denyIfUnauthorized(player) then
			return
		end
		if not rateLimiter:check(player.UserId) then
			notify.player(player, droneConfig.MSG_RATE_LIMIT, "WARNING")
			return
		end
		local pilot = service:getPilot()
		if pilot == nil then
			notify.player(player, droneConfig.MSG_NOT_ACTIVE, "WARNING")
			return
		end
		-- Pilot or any staff with admin panel can stop.
		if not service:stop("command") then
			notify.player(player, droneConfig.MSG_NOT_ACTIVE, "WARNING")
			return
		end
		notify.all(droneConfig.MSG_STOPPED, "INFO")
	end

	local function handleChat(player: Player, rawText: string)
		local args = splitArgs(rawText)
		table.remove(args, 1) -- drop /drone
		local sub = string.lower(tostring(args[1] or ""))
		if sub == "start" then
			tryStart(player)
		elseif sub == "stop" then
			tryStop(player)
		else
			notify.player(player, droneConfig.MSG_USAGE, "INFO")
		end
	end

	local function registerChatCommands()
		if commandExecutionService == nil then
			return
		end
		commandExecutionService:registerRawHandler(droneConfig.CMD_ALIAS, handleChat)
	end

	local controller = {}

	function controller:init()
		if Config.FeatureFlags.DroneEnabled ~= true then
			logger:info("Drone disabled by feature flag")
			return
		end
		registerChatCommands()

		if requestRemote and requestRemote:IsA("RemoteEvent") then
			requestRemote.OnServerEvent:Connect(function(player: Player, payload: any)
				if type(payload) ~= "table" then
					return
				end
				local action = string.lower(tostring(payload.action or ""))
				if action == "start" then
					tryStart(player)
				elseif action == "stop" then
					tryStop(player)
				end
			end)
		end

		if cameraRemote and cameraRemote:IsA("RemoteEvent") then
			cameraRemote.OnServerEvent:Connect(function(player: Player, payload: any)
				if type(payload) ~= "table" then
					return
				end
				if service:getPilot() ~= player then
					return
				end
				if not cameraRateLimiter:check(player.UserId) then
					return
				end
				service:pushFrame(player, {
					c = payload.c,
					fov = payload.fov,
				})
			end)
		end

		logger:info("DroneController ready")
	end

	return controller
end

return createDroneController
