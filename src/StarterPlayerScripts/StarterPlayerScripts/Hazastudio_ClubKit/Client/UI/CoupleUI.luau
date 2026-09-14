--!strict
-- Client/UI/CoupleUI.lua
-- DISPLAY ONLY. Zero logic. Zero remotes.
-- Semua callbacks diset from CoupleController.
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
local UIMotion = require(script.Parent.Parent.Utils.UIMotion)

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

	-- Re-opening the panel re-applies the active tab; the pill is already there.
	if backgroundPill.AnchorPoint == targetAnchorPoint and backgroundPill.Position == targetPosition then
		return
	end

	-- Set anchor point immediately, animate position with smooth easing.
	backgroundPill.AnchorPoint = targetAnchorPoint
	-- Layout safety (ADR 0011): the pill sits absolutely positioned behind the laid-out tab
	-- buttons, so its own parent must have no layout for a Position tween to mean anything. If a
	-- buyer design ever puts it under one, snap instead of tweening against the layout.
	local pillParent = backgroundPill.Parent
	if pillParent == nil or pillParent:FindFirstChildWhichIsA("UIGridStyleLayout") then
		backgroundPill.Position = targetPosition
		return
	end
	UIMotion.tween(backgroundPill, 0.32, { Position = targetPosition }, Enum.EasingStyle.Quint)
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
	-- Callbacks diset from controller
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
	destroy: (self: CoupleUIImpl) -> (),
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
	
	-- Press/hover feedback this panel owns, plus the designed transparency of every element it
	-- fades (cards, notification content), captured once before the first fade touches it. Weak
	-- keys: player cards are destroyed and re-cloned on every populatePlayers.
	self._connections = {} :: { RBXScriptConnection }
	self._fadeBases = (setmetatable({}, { __mode = "k" }) :: any) :: { [GuiObject]: number }
	self._activeContent = nil :: string?
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
-- Press squash + hover lift on any kit button, with the connections owned by this panel.
function CoupleUI:_bindButtonMotion(button: Instance?)
	if not button or not button:IsA("GuiObject") then
		return
	end
	for _, connection in ipairs(UIMotion.bindPress(button :: GuiObject)) do
		table.insert(self._connections, connection)
	end
	for _, connection in ipairs(UIMotion.bindHover(button :: GuiObject)) do
		table.insert(self._connections, connection)
	end
end
-- The element a confirm/send button should pop. UIMotion picks the button itself when that is
-- layout-safe, else its icon/label, and nothing at all under a CanvasGroup (ADR 0005).
function CoupleUI:_popTargetOf(button: Instance?): GuiObject?
	if not button or not button:IsA("GuiObject") then
		return nil
	end
	return UIMotion.scaleTargetOf(button :: GuiObject)
end
-- Text/images UIMotion can fade: everything else (Frames, layouts) has no transparency channel.
function CoupleUI:_fadeTargetsOf(root: Instance): { GuiObject }
	local targets: { GuiObject } = {}
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("TextLabel") or desc:IsA("ImageLabel") then
			table.insert(targets, desc :: GuiObject)
		end
	end
	return targets
end
-- Fades a group's text/images in, capturing each element's designed transparency the first
-- time it is seen. `delay` lets the content land after the dialog has finished travelling.
function CoupleUI:_fadeInGroup(root: Instance, delay: number?)
	local targets = self:_fadeTargetsOf(root)
	local pending: { GuiObject } = {}
	for _, element in ipairs(targets) do
		if self._fadeBases[element] == nil then
			table.insert(pending, element)
		end
	end
	if #pending > 0 then
		UIMotion.captureBases(pending, self._fadeBases)
	end
	UIMotion.fadeIn(targets, self._fadeBases, delay)
end
-- ============================================================
-- Wire all button - callbacks diset from controller
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
				self:_bindButtonMotion(reqBtn)
				reqBtn.MouseButton1Click:Connect(function()
					self:showRequest()
				end)
			end
			if brkBtn then
				self:_bindButtonMotion(brkBtn)
				brkBtn.MouseButton1Click:Connect(function()
					self:showBreakup()
				end)
			end
		end
		local closeBtn = header:FindFirstChild("CloseModalButton") :: TextButton?
		if closeBtn then
			self:_bindButtonMotion(closeBtn)
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
					self:_bindButtonMotion(sendBtn)
					local sendIcon = self:_popTargetOf(sendBtn)
					sendBtn.MouseButton1Click:Connect(function()
						-- Ambil from selected player (diset via populatePlayers)
						if self._selectedUserId and self.onSendRequest then
							UIMotion.pop(sendIcon, 1.25)
							self.onSendRequest(self._selectedUserId)
						else
							-- Nothing picked: shake the button the player just pressed in vain.
							UIMotion.wiggle(sendBtn :: GuiObject, 6)
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
					self:_bindButtonMotion(brkBtn)
					local brkIcon = self:_popTargetOf(brkBtn)
					brkBtn.MouseButton1Click:Connect(function()
						UIMotion.pop(brkIcon, 1.2)
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
				self:_bindButtonMotion(acceptBtn)
				local acceptIcon = self:_popTargetOf(acceptBtn)
				acceptBtn.MouseButton1Click:Connect(function()
					UIMotion.pop(acceptIcon, 1.3)
					if self.onAccept then
						self.onAccept()
					end
					self:_hideNotif()
				end)
			end
			if rejectBtn then
				self:_bindButtonMotion(rejectBtn)
				local rejectIcon = self:_popTargetOf(rejectBtn)
				rejectBtn.MouseButton1Click:Connect(function()
					UIMotion.pop(rejectIcon, 1.18)
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
			if closeBtn then
				self:_bindButtonMotion(closeBtn)
			end
			if tryAgainBtn then
				self:_bindButtonMotion(tryAgainBtn)
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
				self:_bindButtonMotion(okBtn)
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
	local shown: Frame? = nil
	for _, child in ipairs(wrapper:GetChildren()) do
		if child:IsA("Frame") then
			(child :: Frame).Visible = child.Name == panelName
			if child.Name == panelName then
				shown = child :: Frame
			end
		end
	end
	if self._notifWrapper.Visible then
		if shown then
			self:_fadeInGroup(shown)
		end
		return
	end
	self._anim:presentDialog(self._notifWrapper, nil)
	-- The dialog travels first; its content is held invisible and fades up as it lands.
	if shown then
		self:_fadeInGroup(shown, 0.12)
	end
end
function CoupleUI:_hideNotif()
	if not self._notifWrapper.Visible then
		return
	end
	self._anim:dismissDialog(self._notifWrapper, nil)
end
function CoupleUI:_showContentPanel(panelName: string, direction: number?)
	local wrapper = self._mainWrapper:FindFirstChild("02-MainContentWrapper")
	if not wrapper then
		return
	end
	-- Couple status echoes re-assert the active tab; only a real switch animates.
	local changed = self._activeContent ~= panelName
	self._activeContent = panelName
	local shown: Frame? = nil
	for _, child in ipairs(wrapper:GetChildren()) do
		if child:IsA("Frame") then
			(child :: Frame).Visible = child.Name == panelName
			if child.Name == panelName then
				shown = child :: Frame
			end
		end
	end
	-- slideIn moves the page through equal and opposite UIPadding, so the laid-out content
	-- wrapper never changes size (ADR 0011).
	if changed and shown and direction and self._mainWrapper.Visible then
		UIMotion.slideIn(shown :: GuiObject, direction)
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
	-- Request is the left tab: its form arrives from the left.
	self:_showContentPanel("1-RequestContent", -1)

	-- Animate BackgroundPill to Request button
	if self._backgroundPill and self._requestButton and #self._tabButtons > 0 then
		animateSlidingPill(self._backgroundPill, self._requestButton, self._tabButtons)
	end
end
function CoupleUI:showBreakup()
	self:show()
	self:_showContentPanel("2-BreakupContent", 1)

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
		local text = partnerName and ("Your current couple: %s"):format(partnerName) or "You are currently single."
		-- The controller re-asserts couple status on every sync; only a real change re-fades.
		if label.Text == text then
			return
		end
		label.Text = text
		if self._fadeBases[label] == nil then
			UIMotion.captureBases({ label :: GuiObject }, self._fadeBases)
		end
		UIMotion.fadeIn({ label :: GuiObject }, self._fadeBases)
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
	-- Bersihkan card old (kecuali template)
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("TextButton") and child ~= template then
			child:Destroy()
		end
	end
	-- Buat card for tiap player
	local rows: { GuiObject } = {}
	for _, playerData in ipairs(players) do
		local card = template:Clone() :: TextButton
		card.Visible = true
		-- Fresh clone: bases are captured once, here, before any stagger has touched its labels.
		UIMotion.captureBases(self:_fadeTargetsOf(card), self._fadeBases)
		table.insert(rows, card :: GuiObject)
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
			-- The card's avatar (or whatever UIMotion deems scalable on it) pops; under a
			-- CanvasGroup list it refuses and the highlight alone carries the choice.
			local popTarget = self:_popTargetOf(card)
			if self._selectedUserId == playerData.userId then
				UIMotion.pop(popTarget, 1.18)
				return
			end
			self._selectedUserId = playerData.userId
			-- Visual feedback: highlight selected card. Transparency only — the cards are laid
			-- out in the scrolling list, so nothing here may change their size.
			for _, c in ipairs(scrollFrame:GetChildren()) do
				if c:IsA("TextButton") and c ~= template and c ~= card then
					UIMotion.tween(c, 0.18, { BackgroundTransparency = 1 })
				end
			end
			UIMotion.tween(card, 0.18, { BackgroundTransparency = 0.8 })
			UIMotion.pop(popTarget, 1.18)
		end)
		card.Parent = scrollFrame
		-- Bound once per clone, and only after parenting: UIMotion decides what may carry a
		-- UIScale from the card's real ancestry (a CanvasGroup list must never get one).
		self:_bindButtonMotion(card)
	end
	-- A real re-render: the list cascades in.
	UIMotion.stagger(rows, self._fadeBases)
end
-- Cleanup path for every connection this panel owns (press/hover feedback on the header,
-- confirm and player-card buttons).
function CoupleUI:destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
end
return CoupleUI
