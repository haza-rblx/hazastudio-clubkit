--!strict

local SyncStatusPanel = {}
SyncStatusPanel.__index = SyncStatusPanel

function SyncStatusPanel.new(frame: Frame)
	local self = setmetatable({}, SyncStatusPanel)
	self.frame = frame
	self._onUnsync = nil

	local unsyncButton = frame:FindFirstChild("UnsyncBtn")
	if unsyncButton and unsyncButton:IsA("GuiButton") then
		unsyncButton.Activated:Connect(function()
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

	self.frame.Visible = true
end

function SyncStatusPanel:hide()
	self.frame.Visible = false
end

function SyncStatusPanel:updateAnimName(animName: string)
	local animLabel = self.frame:FindFirstChild("AnimLabel")
	if animLabel and animLabel:IsA("TextLabel") then
		animLabel.Text = animName ~= "" and ("Dancing: " .. animName) or ""
	end
end

function SyncStatusPanel:bindUnsync(callback: () -> ())
	self._onUnsync = callback
end

return SyncStatusPanel
