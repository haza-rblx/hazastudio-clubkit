--!strict

local UIMotion = require(script.Parent.Parent.Utils.UIMotion)

local SyncStatusPanel = {}
SyncStatusPanel.__index = SyncStatusPanel

function SyncStatusPanel.new(frame: Frame)
	local self = setmetatable({}, SyncStatusPanel) :: any
	self.frame = frame
	self._onUnsync = nil

	-- Buyer-authored frame: every ref is optional, and the designed transparencies are read
	-- once here, before any fade has touched them.
	local elements: { GuiObject } = { frame }
	for _, descendant in ipairs(frame:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			table.insert(elements, descendant)
		end
	end
	self._fadeElements = elements
	self._fadeBases = UIMotion.captureBases(elements)

	local unsyncButton = frame:FindFirstChild("UnsyncBtn")
	if unsyncButton and unsyncButton:IsA("GuiButton") then
		local button = unsyncButton :: GuiButton
		UIMotion.bindPress(button)
		UIMotion.bindHover(button)
		button.Activated:Connect(function()
			if self._onUnsync then
				self._onUnsync()
			end
		end)
	end

	frame.Visible = false
	return self
end

function SyncStatusPanel:show(leaderDisplay: string?, animName: string?)
	local danceLabel = self.frame:FindFirstChild("DanceLabel")
	local leaderLabel = self.frame:FindFirstChild("LeaderLabel")
	local animLabel = self.frame:FindFirstChild("AnimLabel")

	if danceLabel and danceLabel:IsA("TextLabel") then
		danceLabel.Text = "Sync active"
	end
	if leaderLabel and leaderLabel:IsA("TextLabel") then
		leaderLabel.Text = "Synced to: " .. (leaderDisplay or "-")
	end
	if animLabel and animLabel:IsA("TextLabel") then
		animLabel.Text = animName and animName ~= "" and ("Dancing: " .. animName) or ""
	end

	-- Sync state re-broadcasts while the panel is already up; only a real show fades in.
	if self.frame.Visible then
		return
	end
	self.frame.Visible = true
	UIMotion.fadeIn(self._fadeElements, self._fadeBases)
end

function SyncStatusPanel:hide()
	if not self.frame.Visible then
		return
	end
	self.frame.Visible = false
end

function SyncStatusPanel:updateAnimName(animName: string)
	local animLabel = self.frame:FindFirstChild("AnimLabel")
	if animLabel and animLabel:IsA("TextLabel") then
		local text = animName ~= "" and ("Dancing: " .. animName) or ""
		if animLabel.Text ~= text then
			animLabel.Text = text
		end
	end
end

function SyncStatusPanel:bindUnsync(callback: () -> ())
	self._onUnsync = callback
end

return SyncStatusPanel
