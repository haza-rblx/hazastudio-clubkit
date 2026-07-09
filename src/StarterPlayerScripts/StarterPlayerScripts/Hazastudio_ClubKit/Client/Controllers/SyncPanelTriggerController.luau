--!strict

local Players = game:GetService("Players")

local TriggerController = {}
TriggerController.__index = TriggerController

function TriggerController.create(deps: {
	config: any,
	logger: any,
	onTriggered: () -> (),
})
	local self = setmetatable({}, TriggerController)
	self.config = deps.config.Sync
	self.logger = deps.logger
	self.onTriggered = deps.onTriggered
	self.boundButtons = {} :: { [Instance]: boolean }
	self.connections = {} :: { RBXScriptConnection }
	return self
end

function TriggerController:_matches(button: Instance): boolean
	if not button:IsA("ImageButton") then
		return false
	end

	if button:GetAttribute(self.config.TRIGGER_ATTRIBUTE) == true then
		return true
	end

	for _, allowedName in ipairs(self.config.TRIGGER_BUTTON_NAMES) do
		if button.Name == allowedName then
			return true
		end
	end

	return false
end

function TriggerController:_bindButton(button: ImageButton)
	if self.boundButtons[button] then
		return
	end

	self.boundButtons[button] = true
	table.insert(self.connections, button.Activated:Connect(function()
		self.onTriggered()
	end))
end

function TriggerController:init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if self:_matches(descendant) then
			self:_bindButton(descendant :: ImageButton)
		end
	end

	table.insert(self.connections, playerGui.DescendantAdded:Connect(function(descendant)
		if self:_matches(descendant) then
			self:_bindButton(descendant :: ImageButton)
		end
	end))

	self.logger:info("Sync panel trigger controller initialized")
end

function TriggerController:destroy()
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}
	self.boundButtons = {}
end

return TriggerController
