--!strict

local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

local TOGGLE_INPUT_PRIORITY = Enum.ContextActionPriority.Low.Value
local UNGRAVITY_MACRO_KB = { Enum.KeyCode.LeftShift, Enum.KeyCode.G }
local GRAVITY_MACRO_KB = { Enum.KeyCode.LeftShift, Enum.KeyCode.U }
local FREECAM_ENABLED_ATTRIBUTE = "FreecamEnabled"

local function createGravityController(_deps: { freecamScript: ModuleScript? }?)
	local log = Logger.new("GravityController")
	local gravityConfig = Config.Gravity
	local localPlayer = Players.LocalPlayer

	local commandRemote: RemoteEvent? = nil
	local moduleConnections: { RBXScriptConnection } = {}
	local freecamScript = _deps and _deps.freecamScript

	local function isFreecamActive(): boolean
		if freecamScript then
			local value = freecamScript:GetAttribute(FREECAM_ENABLED_ATTRIBUTE)
			if typeof(value) == "boolean" and value then
				return true
			end
		end
		return false
	end

	local function fireCommand(action: string, speed: number?): ()
		if commandRemote == nil then
			return
		end
		commandRemote:FireServer({
			requestId = HttpService:GenerateGUID(false),
			action = action,
			speed = speed,
		})
	end

	local function checkMacro(macro: { Enum.KeyCode }, onMatch: () -> ())
		for index = 1, #macro - 1 do
			if not UserInputService:IsKeyDown(macro[index]) then
				return
			end
		end
		onMatch()
	end

	local function handleActivationInput(_name: string, state: Enum.UserInputState, input: InputObject)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if isFreecamActive() then
			return Enum.ContextActionResult.Pass
		end

		if input.KeyCode == UNGRAVITY_MACRO_KB[#UNGRAVITY_MACRO_KB] then
			checkMacro(UNGRAVITY_MACRO_KB, function()
				fireCommand("enable_default")
			end)
		elseif input.KeyCode == GRAVITY_MACRO_KB[#GRAVITY_MACRO_KB] then
			checkMacro(GRAVITY_MACRO_KB, function()
				fireCommand("disable")
			end)
		end

		return Enum.ContextActionResult.Pass
	end

	local function bindInput(): ()
		ContextActionService:BindActionAtPriority(
			"ClubKitGravityToggle",
			handleActivationInput,
			false,
			TOGGLE_INPUT_PRIORITY,
			UNGRAVITY_MACRO_KB[#UNGRAVITY_MACRO_KB],
			GRAVITY_MACRO_KB[#GRAVITY_MACRO_KB]
		)
	end

	local function unbindInput(): ()
		ContextActionService:UnbindAction("ClubKitGravityToggle")
	end

	local controller = {}

	function controller:init(): ()
		if Config.FeatureFlags.GravityEnabled ~= true then
			return
		end

		local remotesFolder = ReplicatedStorage:WaitForChild(gravityConfig.REMOTE_FOLDER, 15)
		if remotesFolder == nil then
			log:warn("Gravity remotes folder missing")
			return
		end

		local remote = remotesFolder:WaitForChild(gravityConfig.COMMAND_REMOTE, 10)
		if remote and remote:IsA("RemoteEvent") then
			commandRemote = remote
		else
			log:warn("Gravity command remote missing")
			return
		end

		bindInput()
		log:info("Gravity keybinds ready (Shift+G / Shift+U)")
	end

	function controller:destroy(): ()
		unbindInput()
		for _, conn in ipairs(moduleConnections) do
			conn:Disconnect()
		end
		table.clear(moduleConnections)
		commandRemote = nil
	end

	return controller
end

return createGravityController
