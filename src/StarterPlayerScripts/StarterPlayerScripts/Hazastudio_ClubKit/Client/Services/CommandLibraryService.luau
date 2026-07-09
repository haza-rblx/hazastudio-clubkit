--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

type CommandLibraryExecuteResponse = Types.CommandLibraryExecuteResponse

local REMOTE_WAIT_TIMEOUT = 15

local function createCommandLibraryService()
	local log = Logger.new("Client.CommandLibraryService")
	local remotes = ReplicatedStorage:WaitForChild("Remotes", REMOTE_WAIT_TIMEOUT)
	if not remotes then
		log:warn("Remotes folder unavailable; command library execute disabled")
		return {
			execute = function(_commandText: string) end,
		}
	end

	local executeRemote = remotes:WaitForChild(Config.CommandLibrary.REMOTE_EXECUTE, REMOTE_WAIT_TIMEOUT)
	local resultRemote = remotes:WaitForChild(Config.CommandLibrary.REMOTE_EXECUTE_RESULT, REMOTE_WAIT_TIMEOUT)
	if not executeRemote or not resultRemote or not executeRemote:IsA("RemoteEvent") or not resultRemote:IsA("RemoteEvent") then
		log:warn("Command library remotes unavailable; execute disabled", {
			execute = Config.CommandLibrary.REMOTE_EXECUTE,
			result = Config.CommandLibrary.REMOTE_EXECUTE_RESULT,
		})
		return {
			execute = function(_commandText: string) end,
		}
	end

	local executeRE = executeRemote :: RemoteEvent
	local resultRE = resultRemote :: RemoteEvent

	local pending = {} :: {[string]: true}
	local _connections: { RBXScriptConnection } = {}
	local self = {}

	local function track(conn: RBXScriptConnection): RBXScriptConnection
		table.insert(_connections, conn)
		return conn
	end

	function self:destroy()
		for _, conn in ipairs(_connections) do
			conn:Disconnect()
		end
		table.clear(_connections)
	end

	track(resultRE.OnClientEvent:Connect(function(response: CommandLibraryExecuteResponse)
		pending[response.requestId] = nil
		if not response.ok then
			log:warn("Command library execute failed", {
				requestId = response.requestId,
				error = response.error,
			})
			return
		end

		log:info("Command library execute succeeded", {
			requestId = response.requestId,
		})
	end))

	function self:execute(commandText: string)
		local requestId = HttpService:GenerateGUID(false)
		pending[requestId] = true
		executeRE:FireServer({
			requestId = requestId,
			commandText = commandText,
		})
	end

	return self
end

return createCommandLibraryService
