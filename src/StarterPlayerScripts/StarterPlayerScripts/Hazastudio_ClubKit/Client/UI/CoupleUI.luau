--!strict
-- Client/UI/CoupleUI.lua
-- DISPLAY ONLY. Zero logic. Zero remotes.
-- Semua callbacks diset dari CoupleController.
local TweenService = game:GetService("TweenService")
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)

local function animateSlidingPill(backgroundPill: GuiObject, selectedButton: TextButton, allButtons: {TextButton})
	if not backgroundPill then
		return
	end
	
	-- Find selected button index
	local selectedIndex = 0
	local totalButtons = #allButtons
	for i, btn in ipairs(allButtons) do
		if btn == selectedButton then
			selectedIndex = i
			break
		end
	end
	
	if selectedIndex == 0 or totalButtons == 0 then
		return
	end
	
	-- Calculate normalized position (0 for first, 0.5 for middle, 1 for last)
	local normalizedPos = if totalButtons > 1 then (selectedIndex - 1) / (totalButtons - 1) else 0.5
	
	-- Target position and anchor point
	local targetAnchorPoint = Vector2.new(normalizedPos, 0.5)
	local targetPosition = UDim2.new(normalizedPos, 0, 0.5, 0)
	
	-- Set anchor point immediately, animate position with smooth easing
	backgroundPill.AnchorPoint = targetAnchorPoint
	local tween = TweenService:Create(
		backgroundPill,
		TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = targetPosition }
	)
	tween:Play()
end

local CoupleUI = {}
CoupleUI.__index = CoupleUI
type Callback = () -> ()
type PlayerData = { userId: number, displayName: string, username: string }
type CoupleUIImpl = {
	_gui: ScreenGui,
	_mainWrapper: Frame,
	_notifWrapper: Frame,
	_anim: any,
	-- Callbacks diset dari controller
	onSendRequest: ((targetUserId: number) -> ())?,
	onAccept: Callback?,
	onReject: Callback?,
	onBreakup: Callback?,
	onClose: Callback?,
	-- Methods
	show: (self: CoupleUIImpl) -> (),
	hide: (self: CoupleUIImpl) -> (),
	showRequest: (self: CoupleUIImpl) -> (),
	showBreakup: (self: CoupleUIImpl) -> (),
	showIncoming: (self: CoupleUIImpl, fromName: string) -> (),
	showWaiting: (self: CoupleUIImpl, targetName: string) -> (),
	showRejected: (self: CoupleUIImpl, fromName: string) -> (),
	populatePlayers: (self: CoupleUIImpl, players: { PlayerData }) -> (),
	setProfilePic: (self: CoupleUIImpl, imageId: string, isCouple: boolean) -> (),
	setCurrentCouple: (self: CoupleUIImpl, partnerName: string?) -> (),
}
function CoupleUI.new(gui: ScreenGui): CoupleUIImpl
	local self = setmetatable({}, CoupleUI) :: any
	self._gui = gui
	self._mainWrapper = gui:FindFirstChild("MainWrapper") :: Frame
	self._notifWrapper = gui:FindFirstChild("NotificationWrapper") :: Frame
	self._anim = AnimationHelper.new()
	
	-- Get BackgroundPill and buttons for animation
	local header = self._mainWrapper:FindFirstChild("01-HeaderWrapper")
	local selector = header and header:FindFirstChild("2-SliderSelector")
	self._backgroundPill = selector and selector:FindFirstChild("BackgroundPill") :: GuiObject?
	
	-- Use generic Option buttons from copied selector
	self._requestButton = selector and selector:FindFirstChild("Option1") :: TextButton?
	self._breakupButton = selector and selector:FindFirstChild("Option2") :: TextButton?
	
	if self._requestButton and self._breakupButton then
		self._tabButtons = {self._requestButton, self._breakupButton}
	else
		self._tabButtons = {}
	end
	
	self.onSendRequest = nil
	self.onAccept = nil
	self.onReject = nil
	self.onBreakup = nil
	self.onClose = nil
	self._mainWrapper.Visible = false
	self._mainWrapper.Active = true
	self._notifWrapper.Visible = false
	self._notifWrapper.Active = true
	self:_wireButtons()
	return self
end
-- ============================================================
-- Wire semua button - callbacks diset dari controller
-- ============================================================
function CoupleUI:_wireButtons()
	local main = self._mainWrapper
	local notif = self._notifWrapper
	-- Header buttons
	local header = main:FindFirstChild("01-HeaderWrapper")
	if header then
		local selector = header:FindFirstChild("Selector")
		if selector then
			local reqBtn = selector:FindFirstChild("RequestButton") :: TextButton?
			local brkBtn = selector:FindFirstChild("BreakUpButton") :: TextButton?
			if reqBtn then
				reqBtn.MouseButton1Click:Connect(function()
					self:showRequest()
				end)
			end
			if brkBtn then
				brkBtn.MouseButton1Click:Connect(function()
					self:showBreakup()
				end)
			end
		end
		local closeBtn = header:FindFirstChild("CloseModalButton") :: TextButton?
		if closeBtn then
			closeBtn.MouseButton1Click:Connect(function()
				self:hide()
				if self.onClose then
					self.onClose()
				end
			end)
		end
	end
	-- Request content
	local content = main:FindFirstChild("02-MainContentWrapper")
	if content then
		local reqContent = content:FindFirstChild("1-RequestContent")
		if reqContent then
			local inputWrapper = reqContent:FindFirstChild("InputWrapper")
			if inputWrapper then
				local sendBtn = inputWrapper:FindFirstChild("TextButton") :: TextButton?
				if sendBtn then
					sendBtn.MouseButton1Click:Connect(function()
						-- Ambil dari selected player (diset via populatePlayers)
						if self._selectedUserId and self.onSendRequest then
							self.onSendRequest(self._selectedUserId)
						end
					end)
				end
			end
		end
		-- Breakup content
		local brkContent = content:FindFirstChild("2-BreakupContent")
		if brkContent then
			local inputArea = brkContent:FindFirstChild("InputArea")
			if inputArea then
				local brkBtn = inputArea:FindFirstChild("2-BrokeupButton") :: TextButton?
				if brkBtn then
					brkBtn.MouseButton1Click:Connect(function()
						if self.onBreakup then
							self.onBreakup()
						end
					end)
				end
			end
		end
	end
	-- Notification: Accept
	local confirmation = notif:FindFirstChild("02-MainContentWrapper")
		and notif:FindFirstChild("02-MainContentWrapper"):FindFirstChild("Confirmation")
	if confirmation then
		local inputArea = confirmation:FindFirstChild("InputArea")
		if inputArea then
			local acceptBtn = inputArea:FindFirstChild("AcceptCoupleButton") :: TextButton?
			local rejectBtn = inputArea:FindFirstChild("RejectButton") :: TextButton?
			if acceptBtn then
				acceptBtn.MouseButton1Click:Connect(function()
					if self.onAccept then
						self.onAccept()
					end
					self:_hideNotif()
				end)
			end
			if rejectBtn then
				rejectBtn.MouseButton1Click:Connect(function()
					if self.onReject then
						self.onReject()
					end
					self:_hideNotif()
				end)
			end
		end
	end
	-- Notification: Rejected - Try Again / Close
	local rejected = notif:FindFirstChild("02-MainContentWrapper")
		and notif:FindFirstChild("02-MainContentWrapper"):FindFirstChild("Rejected")
	if rejected then
		local inputArea = rejected:FindFirstChild("InputArea")
		if inputArea then
			local tryAgainBtn = inputArea:FindFirstChild("TryAgainButton") :: TextButton?
			local closeBtn = inputArea:FindFirstChild("CloseButton") :: TextButton?
			if tryAgainBtn then
				tryAgainBtn.MouseButton1Click:Connect(function()
					self:_hideNotif()
					self:show()
					self:showRequest()
				end)
			end
			if closeBtn then
				closeBtn.MouseButton1Click:Connect(function()
					self:_hideNotif()
				end)
			end
		end
	end
	-- Notification: Waiting - Okay
	local waiting = notif:FindFirstChild("02-MainContentWrapper")
		and notif:FindFirstChild("02-MainContentWrapper"):FindFirstChild("Waiting")
	if waiting then
		local inputArea = waiting:FindFirstChild("InputArea")
		if inputArea then
			local okBtn = inputArea:FindFirstChild("TextButton") :: TextButton?
			if okBtn then
				okBtn.MouseButton1Click:Connect(function()
					self:_hideNotif()
				end)
			end
		end
	end
end
-- ============================================================
-- Helpers
-- ============================================================
function CoupleUI:_showNotifPanel(panelName: string)
	local wrapper = self._notifWrapper:FindFirstChild("02-MainContentWrapper")
	if not wrapper then
		return
	end
	for _, child in ipairs(wrapper:GetChildren()) do
		if child:IsA("Frame") then
			(child :: Frame).Visible = child.Name == panelName
		end
	end
	if self._notifWrapper.Visible then
		return
	end
	self._anim:presentDialog(self._notifWrapper, nil)
end
function CoupleUI:_hideNotif()
	if not self._notifWrapper.Visible then
		return
	end
	self._anim:dismissDialog(self._notifWrapper, nil)
end
function CoupleUI:_showContentPanel(panelName: string)
	local wrapper = self._mainWrapper:FindFirstChild("02-MainContentWrapper")
	if not wrapper then
		return
	end
	for _, child in ipairs(wrapper:GetChildren()) do
		if child:IsA("Frame") then
			(child :: Frame).Visible = child.Name == panelName
		end
	end
end
-- ============================================================
-- Public API
-- ============================================================
function CoupleUI:show()
	if self._mainWrapper.Visible then
		return
	end
	self._anim:presentCenterPanel(self._mainWrapper, nil)
end
function CoupleUI:hide()
	if not self._mainWrapper.Visible then
		return
	end
	self._anim:dismissCenterPanel(self._mainWrapper, nil)
end
function CoupleUI:showRequest()
	self:show()
	self:_showContentPanel("1-RequestContent")
	
	-- Animate BackgroundPill to Request button
	if self._backgroundPill and self._requestButton and #self._tabButtons > 0 then
		animateSlidingPill(self._backgroundPill, self._requestButton, self._tabButtons)
	end
end
function CoupleUI:showBreakup()
	self:show()
	self:_showContentPanel("2-BreakupContent")
	
	-- Animate BackgroundPill to Breakup button
	if self._backgroundPill and self._breakupButton and #self._tabButtons > 0 then
		animateSlidingPill(self._backgroundPill, self._breakupButton, self._tabButtons)
	end
end
function CoupleUI:setCurrentCouple(partnerName: string?)
	local brkContent = self._mainWrapper:FindFirstChild("02-MainContentWrapper"):FindFirstChild("2-BreakupContent")
	if not brkContent then
		return
	end
	local inputArea = brkContent:FindFirstChild("InputArea")
	if not inputArea then
		return
	end
	local currentCouple = inputArea:FindFirstChild("1-CurrentCouple")
	if not currentCouple then
		return
	end
	local label = currentCouple:FindFirstChildWhichIsA("TextLabel") :: TextLabel?
	if label then
		label.Text = partnerName and ("Your current couple: %s"):format(partnerName) or "You are currently single."
	end
end
function CoupleUI:showIncoming(fromName: string)
	local wrapper = self._notifWrapper:FindFirstChild("02-MainContentWrapper")
	if not wrapper then
		return
	end
	local confirmation = wrapper:FindFirstChild("Confirmation")
	if confirmation then
		local label = confirmation:FindFirstChild("JumbotronTextandImage")
			and confirmation:FindFirstChild("JumbotronTextandImage"):FindFirstChildWhichIsA("TextLabel") :: TextLabel?
		if label then
			label.Text = ("%s mengirim couple request!"):format(fromName)
		end
	end
	self:_showNotifPanel("Confirmation")
end
function CoupleUI:showWaiting(targetName: string)
	local wrapper = self._notifWrapper:FindFirstChild("02-MainContentWrapper")
	if not wrapper then
		return
	end
	local waiting = wrapper:FindFirstChild("Waiting")
	if waiting then
		local label = waiting:FindFirstChild("JumbotronTextandImage")
			and waiting:FindFirstChild("JumbotronTextandImage"):FindFirstChildWhichIsA("TextLabel") :: TextLabel?
		if label then
			label.Text = ("Menunggu %s menerima request..."):format(targetName)
		end
	end
	self:_showNotifPanel("Waiting")
end
function CoupleUI:showRejected(fromName: string)
	local wrapper = self._notifWrapper:FindFirstChild("02-MainContentWrapper")
	if not wrapper then
		return
	end
	local rejected = wrapper:FindFirstChild("Rejected")
	if rejected then
		local label = rejected:FindFirstChild("JumbotronTextandImage")
			and rejected:FindFirstChild("JumbotronTextandImage"):FindFirstChildWhichIsA("TextLabel") :: TextLabel?
		if label then
			label.Text = ("%s menolak request kamu."):format(fromName)
		end
	end
	self:_showNotifPanel("Rejected")
end
function CoupleUI:populatePlayers(players: { { userId: number, displayName: string, username: string } })
	local content = self._mainWrapper:FindFirstChild("02-MainContentWrapper")
	if not content then
		return
	end
	local reqContent = content:FindFirstChild("1-RequestContent")
	if not reqContent then
		return
	end
	local selectFrame = content:FindFirstChild("3-SelectPlayerFrame")
	if not selectFrame then
		return
	end
	local scrollFrame = selectFrame:FindFirstChild("ScrollablePlayerList") :: ScrollingFrame?
	if not scrollFrame then
		return
	end
	-- Template card
	local template = scrollFrame:FindFirstChild("PlayerSelectorCard") :: TextButton?
	if not template then
		return
	end
	template.Visible = false
	-- Bersihkan card lama (kecuali template)
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("TextButton") and child ~= template then
			child:Destroy()
		end
	end
	-- Buat card untuk tiap player
	for _, playerData in ipairs(players) do
		local card = template:Clone() :: TextButton
		card.Visible = true
		local info = card:FindFirstChild("PlayerInformation")
		if info then
			local nameLabel = info:FindFirstChild("1-Send couple request") :: TextLabel?
			local userLabel = info:FindFirstChild("2-SubTitle") :: TextLabel?
			if nameLabel then
				nameLabel.Text = playerData.displayName
			end
			if userLabel then
				userLabel.Text = "@" .. playerData.username
			end
		end
		-- Set avatar thumbnail
		local pfp = card:FindFirstChild("PlayerProfilePicture") :: ImageLabel?
		if pfp then
			pfp.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=100&h=100"):format(playerData.userId)
		end
		-- Select handler
		card.MouseButton1Click:Connect(function()
			self._selectedUserId = playerData.userId
			-- Visual feedback: highlight selected card
			for _, c in ipairs(scrollFrame:GetChildren()) do
				if c:IsA("TextButton") and c ~= template then
					c.BackgroundTransparency = 1
				end
			end
			card.BackgroundTransparency = 0.8
		end)
		card.Parent = scrollFrame
	end
end
return CoupleUI
