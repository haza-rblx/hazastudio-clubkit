--!strict
-- Routes all chat commands through CommandExecutionService.

local Logger = require(game:GetService("ReplicatedStorage").Hazastudio_ClubKit.Shared.Utils.Logger)

local function createChatCommandController(deps: {
	chatCommandService: any,
	commandExecutionService: any,
})
	local chatCommandService = deps.chatCommandService
	local commandExecutionService = deps.commandExecutionService
	local log = Logger.new("ChatCommandController")

	local controller = {}

	function controller:init()
		if type(commandExecutionService.bindChatCommands) ~= "function" then
			log:warn("CommandExecutionService missing bindChatCommands")
			return
		end
		commandExecutionService:bindChatCommands(chatCommandService)
		log:info("Chat commands bound to CommandExecutionService")
	end

	return controller
end

return createChatCommandController
