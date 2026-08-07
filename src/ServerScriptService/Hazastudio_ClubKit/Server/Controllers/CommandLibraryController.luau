--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local NetworkManager = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkManager)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local Validator = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Validator)
local PermissionDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.PermissionDomain)

type CommandLibraryExecuteRequest = Types.CommandLibraryExecuteRequest
type CommandLibraryExecuteResponse = Types.CommandLibraryExecuteResponse

-- Aliases that are either fully self-service (bio/status/community/session) or
-- already gated inside their own handler by a membership/role tier that is
-- narrower than admin (teleport, announce) or equal to it (gift/setrole –
-- CommandExecutionService checks PermissionDomain.canGift there already).
-- Anything NOT listed here falls back to the adminPanel-tier gate below, so a
-- future command wired into CommandExecutionService without its own
-- permission check does not become open to every player by default.
local OPEN_ALIASES: { [string]: boolean } = {
	[Config.AvatarContext.CMD_SET_BIO] = true,
	[Config.AvatarContext.CMD_CLEAR_BIO] = true,
	[Config.AvatarContext.CMD_SET_STATUS] = true,
	[Config.AvatarContext.CMD_CLEAR_STATUS] = true,
	[Config.Community.CMD_ALIAS_SET] = true,
	[Config.Community.CMD_ALIAS_CLEAR] = true,
	[Config.Session.CMD_ALIAS_REFRESH] = true,
	[Config.Session.CMD_ALIAS_REJOIN] = true,
	[Config.Session.CMD_ALIAS_BRING] = true,
	[Config.Session.CMD_ALIAS_TO] = true,
	[Config.Announcement.CMD_ALIAS_ANNOUNCE] = true,
	[Config.Announcement.CMD_ALIAS_ANNOUNCE_SHORT] = true,
	[Config.Gift.CMD_ALIAS_GIFT] = true,
	[Config.Gift.CMD_ALIAS_UNGIFT] = true,
	[Config.SetRole.CMD_ALIAS_SET] = true,
	[Config.SetRole.CMD_ALIAS_UNSET] = true,
}

-- Mirrors CommandExecutionService's own splitCommandText just enough to read
-- the alias for the permission check below; the service still does its own
-- authoritative parsing afterwards.
local function extractAlias(commandText: string): string?
	local trimmed = commandText:match("^%s*(.-)%s*$") or ""
	if trimmed == "" or string.sub(trimmed, 1, 1) ~= "/" then
		return nil
	end
	local alias = trimmed:match("^/(%S+)")
	if not alias then
		return nil
	end
	return string.lower(alias)
end

local function createCommandLibraryController(deps: {
	service: any,
	remotes: Folder,
	overheadService: any?,
})
	local service = deps.service
	local remotes = deps.remotes
	local overheadService = deps.overheadService
	local log = Logger.new("CommandLibraryController")

	-- Same gate as Admin panel (Gravity/Drone/Crowd controllers): Owner +
	-- Leadership category (adminPanel/canGift) + AdminUserIds.
	local function canUseAdminGatedCommand(player: Player): boolean
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

	local function isAllowedToExecute(player: Player, commandText: string): boolean
		local alias = extractAlias(commandText)
		if not alias or OPEN_ALIASES[alias] then
			return true
		end
		return canUseAdminGatedCommand(player)
	end
	local limiter = RateLimiter.new(
		Config.CommandLibrary.REQUEST_RATE_MAX,
		Config.CommandLibrary.REQUEST_RATE_WINDOW
	)
	local processedRequests = {} :: {[string]: number}
	local function rememberRequest(requestId: string): boolean
		local now = os.clock()
		for key, expiresAt in pairs(processedRequests) do
			if expiresAt <= now then
				processedRequests[key] = nil
			end
		end
		if processedRequests[requestId] then
			return false
		end
		processedRequests[requestId] = now + Config.Security.REQUEST_DEDUPE_WINDOW
		return true
	end

	local function getOrCreateRemote(name: string): RemoteEvent
		local existing = remotes:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotes
		return remote
	end

	local executeRemote = getOrCreateRemote(Config.CommandLibrary.REMOTE_EXECUTE)
	local resultRemote = getOrCreateRemote(Config.CommandLibrary.REMOTE_EXECUTE_RESULT)
	-- NetworkManager batches per-Heartbeat. Command results fire one-per-execute,
	-- but a burst of commands from autocomplete + execute would otherwise produce
	-- back-to-back wire fires.
	local resultNetwork = NetworkManager.create({
		reliable = resultRemote,
		logger = log,
		isServer = true,
	})

	local controller = {}

	function controller:init()
		executeRemote.OnServerEvent:Connect(function(player: Player, raw: any)
			if type(raw) ~= "table" then
				return
			end
			if type(raw.requestId) ~= "string" or raw.requestId == "" then
				return
			end
			if type(raw.commandText) ~= "string" then
				return
			end

			local okSize = Validator.checkSize(raw)
			if not okSize then
				local response: CommandLibraryExecuteResponse = {
					requestId = raw.requestId,
					ok = false,
					error = "Payload too large.",
				}
				resultNetwork:fireClient(player, response)
				return
			end

			local request = raw :: CommandLibraryExecuteRequest
			if not rememberRequest(request.requestId) then
				return
			end
			if not limiter:check(player.UserId) then
				local response: CommandLibraryExecuteResponse = {
					requestId = request.requestId,
					ok = false,
					error = "Rate limit exceeded.",
				}
				resultNetwork:fireClient(player, response)
				return
			end

			if not isAllowedToExecute(player, request.commandText) then
				log:warn("Blocked command for non-privileged player", { player = player.Name })
				local response: CommandLibraryExecuteResponse = {
					requestId = request.requestId,
					ok = false,
					error = "No permission.",
				}
				resultNetwork:fireClient(player, response)
				return
			end

			local result = service:execute(player, request.commandText)
			local response: CommandLibraryExecuteResponse
			if result.ok then
				response = {
					requestId = request.requestId,
					ok = true,
				}
			else
				response = {
					requestId = request.requestId,
					ok = false,
					error = result.error,
				}
			end
			resultNetwork:fireClient(player, response)
		end)

		log:info("CommandLibraryController initialized")
	end

	return controller
end

return createCommandLibraryController
