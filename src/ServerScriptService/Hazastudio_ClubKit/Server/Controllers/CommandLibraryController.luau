--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local NetworkManager = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkManager)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local Validator = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Validator)

type CommandLibraryExecuteRequest = Types.CommandLibraryExecuteRequest
type CommandLibraryExecuteResponse = Types.CommandLibraryExecuteResponse

local function createCommandLibraryController(deps: {
	service: any,
	remotes: Folder,
})
	local service = deps.service
	local remotes = deps.remotes
	local log = Logger.new("CommandLibraryController")
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
