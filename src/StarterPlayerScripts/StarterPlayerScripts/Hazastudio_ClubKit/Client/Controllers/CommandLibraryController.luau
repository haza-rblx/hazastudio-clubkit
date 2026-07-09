--!strict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local CommandLibraryDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.CommandLibraryDomain)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local OverheadController = require(script.Parent.OverheadController)

type RoleKey = Types.RoleKey
type CommandLibraryEntry = Types.CommandLibraryEntry
type ILogger = Types.ILogger

local function createCommandLibraryController(deps: {
	logger: ILogger,
	ui: any,
	store: any,
	executeCommand: ((string) -> ())?,
	icon: any?,
})
	local log = deps.logger
	local ui = deps.ui
	local store = deps.store
	local executeCommand = deps.executeCommand
	local icon = deps.icon

	local player = Players.LocalPlayer
	local isSettingInput = false
	local visibleEntries = {} :: {CommandLibraryEntry}
	local currentRole: RoleKey = "Guest"

	local controller = {}

	local function isMobileDevice(): boolean
		return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	end

	local function resolveRole(): RoleKey
		local cachedRole = OverheadController.getPlayerRole(player.UserId)
		local cachedMembership = OverheadController.getPlayerEffectiveMembership(player.UserId)
		if type(cachedMembership) == "string" and (cachedRole == nil or cachedRole == "Guest" or cachedRole == "Member") then
			return (cachedMembership :: any) :: RoleKey
		end
		if type(cachedRole) == "string" then
			return (cachedRole :: any) :: RoleKey
		end
		local rank = player:GetRankInGroup(Config.Group.GROUP_ID)
		return OverheadDomain.resolveRole(rank, player.UserId)
	end

	local function canExecute(text: string): boolean
		local alias = CommandLibraryDomain.getTypedAlias(text)
		return alias ~= ""
	end

	local function executeNormalized(commandText: string)
		if not canExecute(commandText) then
			return
		end

		if executeCommand then
			executeCommand(commandText)
		else
			log:info("CommandLibrary execute requested before execute bridge is wired", {
				commandText = commandText,
			})
		end
	end

	local function syncDerivedState(rawText: string)
		local normalizedInput = CommandLibraryDomain.normalizeInput(rawText)
		local query = CommandLibraryDomain.getTypedAlias(normalizedInput)
		local filtered = CommandLibraryDomain.filterEntries(visibleEntries, normalizedInput)

		store:set({
			rawInput = normalizedInput,
			normalizedQuery = query,
			visibleCommands = filtered,
			bestSuggestion = nil,
			canExecute = canExecute(normalizedInput),
		})

		ui:renderCommands(filtered, query)
	end

	local function refreshVisibleEntries()
		currentRole = resolveRole()
		local membership = OverheadController.getPlayerEffectiveMembership(player.UserId)
		visibleEntries = CommandLibraryDomain.getVisibleEntries(currentRole, membership)
		syncDerivedState(store:get().rawInput)
	end

	local function setInputText(text: string)
		isSettingInput = true
		ui:setInputText(text)
		isSettingInput = false
		syncDerivedState(text)
	end

	local function closePanel()
		if not ui:isPanelOpen() then
			return
		end

		store:set({
			isOpen = false,
			rawInput = "",
			normalizedQuery = "",
			visibleCommands = visibleEntries,
			bestSuggestion = nil,
			transientClickedId = nil,
		})

		ui:hide()

		if icon and type(icon.deselect) == "function" then
			icon:deselect()
		end
	end

	local function openPanel()
		store:set({ rawInput = "", isOpen = true })
		refreshVisibleEntries()
		ui:show()
		ui:setPhoneButtonVisible(isMobileDevice())
	end

	function controller:toggle()
		if ui:isPanelOpen() then
			closePanel()
			return
		end
		openPanel()
	end

	function controller:open()
		openPanel()
	end

	function controller:close()
		closePanel()
	end

	function controller:init()
		store:set({
			rawInput = "",
			isMobile = isMobileDevice(),
		})

		ui:setInputText("")
		ui:setPhoneButtonVisible(isMobileDevice())
		refreshVisibleEntries()

		ui:bindInputFocused(function()
			if not store:get().isOpen then
				return
			end
			if ui:getInputText() == "" then
				setInputText("/")
			end
		end)

		ui:bindInputChanged(function(rawText: string)
			if not store:get().isOpen then
				return
			end
			if isSettingInput then
				return
			end

			if rawText == "" then
				setInputText("/")
				return
			end

			local normalizedInput = CommandLibraryDomain.normalizeInput(rawText)
			if normalizedInput ~= rawText then
				setInputText(normalizedInput)
				return
			end

			syncDerivedState(normalizedInput)
		end)

		ui:bindCardFilled(function(entry: CommandLibraryEntry)
			if not entry.needsArguments then
				executeNormalized(entry.display)
				closePanel()
				return
			end

			local fillText = CommandLibraryDomain.formatFillText(entry)
			setInputText(fillText)
			ui:focusInput()
		end)

		ui:bindExecute(function(commandText: string)
			local normalizedInput = CommandLibraryDomain.normalizeInput(commandText)
			executeNormalized(normalizedInput)
		end)

		if icon then
			icon.selected:Connect(function()
				if ui:isPanelOpen() then
					closePanel()
					return
				end
				openPanel()
			end)

			if type(icon.deselected) == "table" and type(icon.deselected.Connect) == "function" then
				icon.deselected:Connect(function()
					closePanel()
				end)
			elseif icon.deselected and type(icon.deselected.Connect) == "function" then
				icon.deselected:Connect(function()
					closePanel()
				end)
			end
		end

		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed or not ui:isPanelOpen() then
				return
			end

			if input.UserInputType == Enum.UserInputType.Keyboard then
				if input.KeyCode == Enum.KeyCode.Escape then
					closePanel()
					return
				end
			end

			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end

			local inputPosition = input.Position
			local guiObjects = player.PlayerGui:GetGuiObjectsAtPosition(inputPosition.X, inputPosition.Y)
			for _, guiObject in ipairs(guiObjects) do
				if guiObject:IsDescendantOf(ui:getScreenGui()) then
					return
				end
			end

			closePanel()
		end)

		log:info("CommandLibraryController initialized", {
			role = currentRole,
			isMobile = isMobileDevice(),
		})
	end

	return controller
end

return createCommandLibraryController
