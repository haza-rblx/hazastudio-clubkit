--!strict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

type CarryStyleEntry = {
	name: string,
	displayName: string,
}

type CarryUIDeps = {
	logger: any,
}

local OUTSIDE_TAP_GRACE = 0.12

local function setButtonLabel(button: TextButton, text: string): ()
	local label = button:FindFirstChildWhichIsA("TextLabel", true)
	if label then
		label.Text = text
	end
	button.Text = ""
end

local function isPointInside(guiObject: GuiObject, position: Vector2): boolean
	local absolutePosition = guiObject.AbsolutePosition
	local absoluteSize = guiObject.AbsoluteSize
	return position.X >= absolutePosition.X
		and position.X <= absolutePosition.X + absoluteSize.X
		and position.Y >= absolutePosition.Y
		and position.Y <= absolutePosition.Y + absoluteSize.Y
end

local function createDisabledCarryUI(): any
	local ui = {}

	function ui:setStyles(_styles: { CarryStyleEntry }) end
	function ui:showStylePicker(_targetName: string) end
	function ui:hideStylePicker() end
	function ui:showConfirmation(_carrierName: string, _styleName: string) end
	function ui:hideConfirmation() end
	function ui:showDropButton() end
	function ui:hideDropButton() end
	function ui:hideAll() end
	function ui:bindStyleSelected(_callback: (string) -> ()) end
	function ui:bindStyleClosed(_callback: () -> ()) end
	function ui:bindAccept(_callback: () -> ()) end
	function ui:bindReject(_callback: () -> ()) end
	function ui:bindDrop(_callback: () -> ()) end
	function ui:destroy() end

	return ui
end

local function createCarryUI(deps: CarryUIDeps)
	local log = deps.logger
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local gui = playerGui:WaitForChild(Config.Carry.GUI_NAME, 10)
	if not gui or not gui:IsA("ScreenGui") then
		warn("[CarryUI] GUI tidak ditemukan; carry UI disabled")
		return createDisabledCarryUI()
	end

	gui.ResetOnSpawn = false
	gui.DisplayOrder = Config.Carry.DISPLAY_ORDER

	local carryTypes = gui:WaitForChild("CarryTypes") :: Frame
	local carryConfirmation = gui:WaitForChild("CarryConfirmation") :: Frame
	local dropButton = gui:WaitForChild("DropButton") :: Frame
	local styleTemplate = carryTypes:WaitForChild("CarryType") :: TextButton
	local confirmationTitle = carryConfirmation
		:WaitForChild("TrackWrapperTemplate")
		:WaitForChild("TrackInformationWrapper")
		:WaitForChild("TrackTitle") :: TextLabel
	local acceptButton = carryConfirmation:WaitForChild("AcceptCarry") :: TextButton
	local rejectButton = carryConfirmation:WaitForChild("RejectCarry") :: TextButton
	local dropAction = dropButton:WaitForChild("RejectCarry") :: TextButton
	local anim = AnimationHelper.new()

	local ui = {}
	local connections: { RBXScriptConnection } = {}
	local styleButtons: { TextButton } = {}
	local openedAt = 0
	local styleSelectedCallback: ((string) -> ())? = nil
	local styleClosedCallback: (() -> ())? = nil
	local acceptCallback: (() -> ())? = nil
	local rejectCallback: (() -> ())? = nil
	local dropCallback: (() -> ())? = nil

	carryTypes.Visible = false
	carryConfirmation.Visible = false
	dropButton.Visible = false
	styleTemplate.Visible = false
	setButtonLabel(dropAction, "Drop from carry")

	local function track(connection: RBXScriptConnection): ()
		table.insert(connections, connection)
	end

	local function closeStylePickerFromOutside(): ()
		ui:hideStylePicker()
		if styleClosedCallback then
			styleClosedCallback()
		end
	end

	track(UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or not carryTypes.Visible then
			return
		end
		if os.clock() - openedAt < OUTSIDE_TAP_GRACE then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		local pointerPosition = Vector2.new(input.Position.X, input.Position.Y)
		if isPointInside(carryTypes, pointerPosition) then
			return
		end
		closeStylePickerFromOutside()
	end))

	track(acceptButton.Activated:Connect(function()
		if acceptCallback then
			acceptCallback()
		end
	end))

	track(rejectButton.Activated:Connect(function()
		if rejectCallback then
			rejectCallback()
		end
	end))

	track(dropAction.Activated:Connect(function()
		if dropCallback then
			dropCallback()
		end
	end))

	function ui:setStyles(styles: { CarryStyleEntry }): ()
		for _, button in ipairs(styleButtons) do
			button:Destroy()
		end
		table.clear(styleButtons)

		for index, style in ipairs(styles) do
			local button = styleTemplate:Clone()
			button.Name = "CarryType_" .. style.name
			button.LayoutOrder = index
			button.Visible = true
			setButtonLabel(button, style.displayName)
			button.Parent = carryTypes
			table.insert(styleButtons, button)

			track(button.Activated:Connect(function()
				if styleSelectedCallback then
					styleSelectedCallback(style.name)
				end
			end))
		end
	end

	function ui:showStylePicker(targetName: string): ()
		openedAt = os.clock()
		log:debug("Show carry style picker", { target = targetName })
		anim:presentCenterPanel(carryTypes)
	end

	function ui:hideStylePicker(): ()
		if carryTypes.Visible then
			anim:dismissCenterPanel(carryTypes)
		end
	end

	function ui:showConfirmation(carrierName: string, styleName: string): ()
		confirmationTitle.Text = string.format("%s wants to carry you with %s!", carrierName, styleName)
		anim:presentCenterPanel(carryConfirmation)
	end

	function ui:hideConfirmation(): ()
		if carryConfirmation.Visible then
			anim:dismissCenterPanel(carryConfirmation)
		end
	end

	function ui:showDropButton(): ()
		anim:presentCenterPanel(dropButton)
	end

	function ui:hideDropButton(): ()
		if dropButton.Visible then
			anim:dismissCenterPanel(dropButton)
		end
	end

	function ui:hideAll(): ()
		ui:hideStylePicker()
		ui:hideConfirmation()
		ui:hideDropButton()
	end

	function ui:bindStyleSelected(callback: (string) -> ()): ()
		styleSelectedCallback = callback
	end

	function ui:bindStyleClosed(callback: () -> ()): ()
		styleClosedCallback = callback
	end

	function ui:bindAccept(callback: () -> ()): ()
		acceptCallback = callback
	end

	function ui:bindReject(callback: () -> ()): ()
		rejectCallback = callback
	end

	function ui:bindDrop(callback: () -> ()): ()
		dropCallback = callback
	end

	function ui:destroy(): ()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
		for _, button in ipairs(styleButtons) do
			button:Destroy()
		end
		table.clear(styleButtons)
	end

	return ui
end

return createCarryUI
