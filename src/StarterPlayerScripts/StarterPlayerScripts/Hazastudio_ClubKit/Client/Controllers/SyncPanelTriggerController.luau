--!strict

local Players = game:GetService("Players")

local UIMotion = require(script.Parent.Parent.Utils.UIMotion)

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
	self.animatedButtons = {} :: { [Instance]: boolean }
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
	self:_bindMotion(button)
end

-- Press squash + hover lift (ADR 0011), owned here so it dies with the controller.
-- The topbar pill is a button inside a button (IconGroup.DancePanelButton.DancePanelButton) and
-- one tap bubbles through both, so exactly one of them squashes: the inner one when UIMotion can
-- scale it — the outer already carries MobileScaleService's UIScale, and Roblox honours only one
-- UIScale per instance — otherwise this one.
function TriggerController:_bindMotion(button: ImageButton)
	local ancestor: Instance? = button.Parent
	while ancestor do
		if self.animatedButtons[ancestor] then
			return
		end
		ancestor = ancestor.Parent
	end

	for _, descendant in ipairs(button:GetDescendants()) do
		if self:_matches(descendant) and UIMotion.scaleTargetOf(descendant :: ImageButton) ~= nil then
			return
		end
	end

	self.animatedButtons[button] = true
	for _, connection in ipairs(UIMotion.bindPress(button)) do
		table.insert(self.connections, connection)
	end
	for _, connection in ipairs(UIMotion.bindHover(button)) do
		table.insert(self.connections, connection)
	end
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
	self.animatedButtons = {}
end

return TriggerController
