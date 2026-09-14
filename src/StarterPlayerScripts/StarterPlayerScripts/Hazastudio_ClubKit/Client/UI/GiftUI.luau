--!strict
-- Client/UI/GiftUI.lua
-- Display only. Manages 03-GiftSystemGUI.
-- Tabs: VIP / VVIP / ELITE. Player list. Notification.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local ShopDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.ShopDomain)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
local UIMotion = require(script.Parent.Parent.Utils.UIMotion)
-- ============================================================
-- Mapping tier -> GUI elements
-- ============================================================
local TAB_FRAME: { [string]: string } = {
}
local TAB_BTN: { [string]: string } = {
}
local GIFT_BTN: { [string]: string } = {
}
local NOTIF_FRAME: { [string]: string } = {
}
-- Gradient name enabled when tab is active
local ACTIVE_GRADIENT: { [string]: string } = {
}
local TIERS = Config.Membership.SHOP_TIERS
for _, tier in ipairs(TIERS or {}) do
	local cfg = Config.Membership.Tiers[tier]
	if cfg then
		TAB_FRAME[tier] = cfg.giftTabFrame
		TAB_BTN[tier] = cfg.giftTabButton
		GIFT_BTN[tier] = cfg.giftButton
		NOTIF_FRAME[tier] = cfg.shopNotif
		ACTIVE_GRADIENT[tier] = cfg.giftActiveGradient
	end
end
local DEFAULT_TIER = TIERS[1] or "Tier1"
local function normalizeTier(tier: string?): string?
	if type(tier) ~= "string" or tier == "" then
		return nil
	end
	local normalized = ShopDomain.parseShopTier(tier)
	return if normalized and TAB_FRAME[normalized] ~= nil then normalized else nil
end

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
	-- Layout safety (ADR 0011): the pill is absolutely positioned behind the laid-out buttons,
	-- so its own parent must have no layout for a Position tween to mean anything. If a buyer
	-- design ever puts it under one, snap instead of tweening against the layout.
	local pillParent = backgroundPill.Parent
	if pillParent == nil or pillParent:FindFirstChildWhichIsA("UIGridStyleLayout") then
		backgroundPill.Position = targetPosition
		return
	end
	UIMotion.tween(backgroundPill, 0.32, { Position = targetPosition }, Enum.EasingStyle.Quint)
end

-- ============================================================
local GiftUI = {} :: any
GiftUI.__index = GiftUI
local WAIT_TIMEOUT = 10 -- seconds max wait for GUI elements
local SEARCH_HIGHLIGHT_COLOR = "#FF7EB6"
local EMPTY_STATE_DEFAULT_TITLE = "No one is eligible right now"
local EMPTY_STATE_DEFAULT_SUBTITLE = "When a player is ready to receive, they'll appear here."
local EMPTY_STATE_SEARCH_TITLE = "No match this time"
local EMPTY_STATE_SEARCH_SUBTITLE = "Try another display name or username."
type PlayerListEntry = {
	button: TextButton,
	connection: RBXScriptConnection?,
	alpha: number?,
}
local function escapeRichText(text: string): string
	return text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end
local function highlightFirstMatch(text: string, query: string): string
	local safeText = escapeRichText(text)
	if query == "" then
		return safeText
	end
	local lowerText = string.lower(text)
	local lowerQuery = string.lower(query)
	local startIndex = string.find(lowerText, lowerQuery, 1, true)
	if not startIndex then
		return safeText
	end
	local endIndex = startIndex + #query - 1
	local beforeText = escapeRichText(string.sub(text, 1, startIndex - 1))
	local matchText = escapeRichText(string.sub(text, startIndex, endIndex))
	local afterText = escapeRichText(string.sub(text, endIndex + 1))
	return string.format(
		'%s<font color="%s"><b>%s</b></font>%s',
		beforeText,
		SEARCH_HIGHLIGHT_COLOR,
		matchText,
		afterText
	)
end
local function setNotFoundCardText(card: GuiObject, titleText: string, subtitleText: string)
	local info = card:FindFirstChild("PlayerInformation") :: Frame?
	if not info then
		return
	end
	local titleLabel = info:FindFirstChild("1-Title") :: TextLabel?
	local subtitleLabel = info:FindFirstChild("2-SubTitle") :: TextLabel?
	if titleLabel then
		titleLabel.RichText = false
		titleLabel.Text = titleText
	end
	if subtitleLabel then
		subtitleLabel.RichText = false
		subtitleLabel.Text = subtitleText
	end
end
local function setPrimaryLabel(root: Instance?, text: string)
	if not root then
		return
	end
	if root:IsA("TextButton") or root:IsA("TextLabel") or root:IsA("TextBox") then
		(root :: TextLabel).Text = text
	end
	local label = root:FindFirstChildWhichIsA("TextLabel", true)
	if label then
		label.Text = text
	end
end
local function getThumbnail(userId: number): string
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=100&h=100", userId)
end
local function setThumbnailAsync(imageLabel: ImageLabel, userId: number)
	imageLabel.Image = getThumbnail(userId)
end
-- ============================================================
-- Private helper: find all RotatingBackground under root
-- ============================================================
-- Text/images UIMotion can fade: everything else (Frames, layouts) has no transparency channel.
local function collectFadeTargets(root: Instance): { GuiObject }
	local result: { GuiObject } = {}
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("TextLabel") or desc:IsA("ImageLabel") then
			table.insert(result, desc :: GuiObject)
		end
	end
	return result
end
local function collectRotatingBgs(root: Instance): { ImageLabel }
	local result: { ImageLabel } = {}
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("ImageLabel") and desc.Name == "RotatingBackground" then
			table.insert(result, desc)
		end
	end
	return result
end
function GiftUI.new(gui: ScreenGui)
	local self = setmetatable({}, GiftUI) :: any
	local mainWrapper = gui:WaitForChild("MainWrapper", WAIT_TIMEOUT) :: Frame
	if not mainWrapper then
		warn("[GiftUI] MainWrapper not found di " .. gui.Name)
		return self
	end
	local contentWrapper = mainWrapper:WaitForChild("02-MainContentWrapper", WAIT_TIMEOUT) :: Frame
	local headerWrapper = mainWrapper:WaitForChild("01-HeaderWrapper", WAIT_TIMEOUT) :: Frame
	local notifWrapper = gui:WaitForChild("NotificationWrapper", WAIT_TIMEOUT) :: Frame
	if not (contentWrapper and headerWrapper and notifWrapper) then
		warn("[GiftUI] Elemen required not found di " .. gui.Name)
		return self
	end
	local selectorRaw = headerWrapper:WaitForChild("2-SliderSelector", WAIT_TIMEOUT) :: Frame
	-- Flexible: handle nested 2-SliderSelector
	local selectorInner = selectorRaw and selectorRaw:FindFirstChild("2-SliderSelector") :: Frame?
	local selector = if selectorInner and selectorInner:IsA("Frame") then selectorInner else selectorRaw
	
	-- Get BackgroundPill and tab buttons for animation (optional)
	-- BackgroundPill is always in OUTER selector
	local backgroundPill = selectorRaw and selectorRaw:FindFirstChild("BackgroundPill") :: GuiObject?
	local tabButtons = {}
	if selector then
		-- Collect all TextButtons by position
		local allButtons: { TextButton } = {}
		for _, child in ipairs(selector:GetChildren()) do
			if child:IsA("TextButton") then
				table.insert(allButtons, child :: TextButton)
			end
		end
		-- 3-pass: config name → OptionN → position
		for i, tier in ipairs(TIERS) do
			local btn: TextButton? = nil
			local cfgBtnName = TAB_BTN[tier]
			if cfgBtnName then
				btn = selector:FindFirstChild(cfgBtnName) :: TextButton?
			end
			if not btn then
				btn = selector:FindFirstChild("Option" .. i) :: TextButton?
			end
			if not btn and i <= #allButtons then
				btn = allButtons[i]
			end
			if btn then
				table.insert(tabButtons, btn)
				local cfg = Config.Membership.Tiers[tier]
				if cfg then
					local label = btn:FindFirstChildWhichIsA("TextLabel", true) or btn
					if label:IsA("TextButton") or label:IsA("TextLabel") then
						(label :: TextLabel).Text = tostring(cfg.label or tier)
					end
				end
			end
		end
		-- Tiers the buyer switched off (Membership.TierN.Enabled = false) are gone
		-- from TIERS, so the loop above binds only the first #TIERS buttons. The
		-- selector still SHIPS one button per tier, and the last resolution pass is
		-- positional (allButtons[i]) — so the surplus buttons would stay on screen,
		-- correctly labelled and completely inert. Hide whatever went unbound.
		local boundButtons: { [TextButton]: true } = {}
		for _, btn in ipairs(tabButtons) do
			boundButtons[btn] = true
		end
		for _, btn in ipairs(allButtons) do
			if not boundButtons[btn] then
				btn.Visible = false
			end
		end
		-- Same for the tab frames behind them: a disabled tier can never become
		-- active (normalizeTier rejects it), but leave nothing half-shown.
		for tier, cfg in pairs(Config.Membership.Tiers or {}) do
			if TAB_FRAME[tier] == nil and type(cfg) == "table" and type(cfg.giftTabFrame) == "string" then
				local frame = contentWrapper:FindFirstChild(cfg.giftTabFrame)
				if frame and frame:IsA("GuiObject") then
					frame.Visible = false
				end
			end
		end
	end

	local selectFrame = contentWrapper:WaitForChild("4-SelectPlayerFrame", WAIT_TIMEOUT) :: Frame
	local closeBtn = headerWrapper:FindFirstChild("3-CloseModalButton") :: TextButton?
	local searchBox = selectFrame and selectFrame:FindFirstChild("01-SearchBox") :: TextBox?
	local scrollFrame = selectFrame
		and (
			selectFrame:FindFirstChild("02-ScrollablePlayerList")
			or selectFrame:FindFirstChild("ScrollablePlayerList")
		) :: ScrollingFrame?
	self._gui = gui
	self._mainWrapper = mainWrapper
	self._contentWrapper = contentWrapper
	self._notifWrapper = notifWrapper
	self._selector = selector
	self._backgroundPill = backgroundPill
	self._tabButtons = tabButtons
	self._selectFrame = selectFrame
	self._closeBtn = closeBtn
	self._searchBox = searchBox
	self._scrollFrame = scrollFrame
	self._anim = AnimationHelper.new()
	self._activeTier = DEFAULT_TIER
	-- Build tier → index mapping for flexible lookup
	self._tierIndex = {} :: { [string]: number }
	for i, tier in ipairs(TIERS) do
		self._tierIndex[tier] = i
	end
	self._selectedPlayer = nil :: { userId: number, displayName: string, username: string }?
	self._allPlayers = {} :: { { userId: number, displayName: string, username: string } }
	self._playerCardPool = {} :: { PlayerListEntry }
	self._isClosing = false
	-- Designed transparency of every element UIMotion fades here (cards, empty state, notif),
	-- captured once before the first fade touches it.
	self._fadeBases = {} :: { [GuiObject]: number }
	self._connections = {} :: { RBXScriptConnection }
	-- RotatingBackground: only notification preserved
	self._notifRotBgs = collectRotatingBgs(notifWrapper)
	self._notifRotHandles = {} :: { any }
	-- Tab button labels already set above during button collection
	-- Hide all on init
	gui.Enabled = false
	notifWrapper.Visible = false
	mainWrapper.Visible = false
	if searchBox then
		table.insert(self._connections, searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			self:_applyPlayerSearch()
		end))
	end
	return self
end
-- Press squash + hover lift on any kit button, with the connections owned by this panel.
function GiftUI:_bindButtonMotion(button: GuiObject)
	for _, connection in ipairs(UIMotion.bindPress(button)) do
		table.insert(self._connections, connection)
	end
	for _, connection in ipairs(UIMotion.bindHover(button)) do
		table.insert(self._connections, connection)
	end
end
-- Fades a group in, capturing any element's designed transparency the first time it is seen.
function GiftUI:_fadeInGroup(root: Instance)
	local targets = collectFadeTargets(root)
	local pending: { GuiObject } = {}
	for _, element in ipairs(targets) do
		if self._fadeBases[element] == nil then
			table.insert(pending, element)
		end
	end
	if #pending > 0 then
		UIMotion.captureBases(pending, self._fadeBases)
	end
	UIMotion.fadeIn(targets, self._fadeBases)
end
-- ============================================================
-- Tab helpers
-- ============================================================
function GiftUI:_setTabActive(tier: string, active: boolean)
	if not self._selector or not self._tabButtons then
		return
	end
	local tierIndex = self._tierIndex[tier]
	local btn = tierIndex and self._tabButtons[tierIndex]
	if not btn then
		return
	end
	local activeName = ACTIVE_GRADIENT[tier]
	for _, child in ipairs(btn:GetChildren()) do
		if child:IsA("UIGradient") then
			child.Enabled = (child.Name == activeName) == active or (child.Name == "UIGradient-Normal") == not active
		end
	end
end
function GiftUI:setTab(tier: string)
	local normalizedTier = normalizeTier(tier) or DEFAULT_TIER
	if TAB_FRAME[normalizedTier] == nil then
		normalizedTier = DEFAULT_TIER
	end
	local previousTier = self._activeTier
	self._activeTier = normalizedTier
	self._selectedPlayer = nil -- reset selected when switching tab
	-- Show/hide tab frames
	local activeFrame: Frame? = nil
	for _, t in ipairs(TIERS) do
		local frameName = TAB_FRAME[t]
		local frame = self._contentWrapper:FindFirstChild(frameName) :: Frame?
		if frame then
			frame.Visible = (t == normalizedTier)
			if t == normalizedTier then
				activeFrame = frame
			end
		end
		self:_setTabActive(t, t == normalizedTier)
	end

	-- A real switch inside an open panel slides the incoming tier's form in from the direction
	-- of travel and pops the tab that won. Opening plays the panel pop instead (MainWrapper is
	-- still hidden when show() calls setTab).
	local activeIndex = self._tierIndex[normalizedTier]
	if previousTier ~= normalizedTier and self._mainWrapper.Visible then
		if activeFrame then
			local previousIndex = self._tierIndex[previousTier] or 0
			UIMotion.slideIn(activeFrame, if (activeIndex or 0) >= previousIndex then 1 else -1)
		end
		local activeButton = activeIndex and self._tabButtons[activeIndex]
		if activeButton then
			local badge = (
				activeButton:FindFirstChildWhichIsA("ImageLabel")
				or activeButton:FindFirstChildWhichIsA("TextLabel")
			) :: GuiObject?
			UIMotion.pop(badge, 1.12)
		end
	end


	-- Animate BackgroundPill to active tab
	if self._backgroundPill and #self._tabButtons > 0 then
		-- Find active button by tier index
		local tierIndex = 0
		for i, t in ipairs(TIERS) do
			if t == normalizedTier then
				tierIndex = i
				break
			end
		end
		if tierIndex > 0 and tierIndex <= #self._tabButtons then
			animateSlidingPill(self._backgroundPill, self._tabButtons[tierIndex], self._tabButtons)
		end
	end
	
	-- SelectPlayerFrame selalu visible
	self._selectFrame.Visible = true
end
function GiftUI:_getActiveInputBox(): TextBox?
	local frameName = TAB_FRAME[self._activeTier]
	if frameName == nil then
		return nil
	end
	local tabFrame = self._contentWrapper:FindFirstChild(frameName) :: Frame?
	local inputArea = tabFrame and tabFrame:FindFirstChild("InputArea") :: Frame?
	return inputArea and inputArea:FindFirstChild("UsernameInputField") :: TextBox?
end
function GiftUI:_clearSelectedPlayer()
	self._selectedPlayer = nil
	local inputBox = self:_getActiveInputBox()
	if inputBox then
		inputBox.Text = ""
	end
	self:_refreshPlayerCardSelection()
end
function GiftUI:_ensurePlayerCard(index: number, template: TextButton): PlayerListEntry
	local entry = self._playerCardPool[index]
	if entry then
		if entry.button.Parent ~= self._scrollFrame then
			entry.button.Parent = self._scrollFrame
		end
		return entry
	end
	local card = template:Clone()
	card.Visible = false
	card.Parent = self._scrollFrame
	-- Bases are captured at creation, before any stagger has touched this card's labels.
	UIMotion.captureBases(collectFadeTargets(card), self._fadeBases)
	entry = {
		button = card,
		connection = nil,
		alpha = nil,
	}
	self._playerCardPool[index] = entry
	return entry
end
function GiftUI:_hideUnusedPlayerCards(firstUnusedIndex: number)
	for index = firstUnusedIndex, #self._playerCardPool do
		local entry = self._playerCardPool[index]
		if entry.connection then
			entry.connection:Disconnect()
			entry.connection = nil
		end
		entry.button.Visible = false
		-- Snap (and cancel any highlight mid-fade) — the card is off screen.
		entry.alpha = 1
		UIMotion.tween(entry.button, 0, { BackgroundTransparency = 1 })
	end
end
function GiftUI:_refreshPlayerCardSelection()
	for _, entry in ipairs(self._playerCardPool) do
		local userId = entry.button:GetAttribute("PlayerUserId")
		local isSelected = self._selectedPlayer ~= nil
			and type(userId) == "number"
			and self._selectedPlayer.userId == userId
		local alpha = if isSelected then Config.Gift.CARD_SELECTED_ALPHA else 1
		-- Every render re-asserts the whole list's selection: only the card that changed moves.
		if entry.alpha ~= alpha then
			local first = entry.alpha == nil
			entry.alpha = alpha
			UIMotion.tween(entry.button, if first then 0 else 0.18, { BackgroundTransparency = alpha })
		end
	end
end
function GiftUI:_isPlayerMatch(
	playerData: { userId: number, displayName: string, username: string },
	query: string
): boolean
	if query == "" then
		return true
	end
	local normalizedQuery = string.lower(query)
	return string.find(string.lower(playerData.displayName), normalizedQuery, 1, true) ~= nil
		or string.find(string.lower(playerData.username), normalizedQuery, 1, true) ~= nil
end
function GiftUI:_applyPlayerSearch()
	local query = ""
	if self._searchBox then
		query = string.gsub(self._searchBox.Text, "^%s*(.-)%s*$", "%1")
	end
	local filteredPlayers = table.create(#self._allPlayers)
	for _, pd in ipairs(self._allPlayers) do
		if self:_isPlayerMatch(pd, query) then
			table.insert(filteredPlayers, pd)
		end
	end
	self:_renderPlayerList(filteredPlayers)
end
function GiftUI:_renderPlayerList(players: { { userId: number, displayName: string, username: string } })
	local scrollFrame = self._scrollFrame
	if not scrollFrame then
		return
	end
	local template = scrollFrame:FindFirstChild("PlayerSelectorCard") :: TextButton?
	local notFoundCard = scrollFrame:FindFirstChild("NotFoundCard") :: TextButton?
	if not template then
		return
	end
	local selectedStillExists = false
	template.Visible = false
	if notFoundCard then
		-- Fade the empty state in only when it actually appears, not on every keystroke.
		if notFoundCard.Visible ~= (#players == 0) then
			notFoundCard.Visible = (#players == 0)
			if notFoundCard.Visible then
				self:_fadeInGroup(notFoundCard)
			end
		end
		if #players == 0 then
			if #self._allPlayers == 0 then
				setNotFoundCardText(notFoundCard, EMPTY_STATE_DEFAULT_TITLE, EMPTY_STATE_DEFAULT_SUBTITLE)
			else
				setNotFoundCardText(notFoundCard, EMPTY_STATE_SEARCH_TITLE, EMPTY_STATE_SEARCH_SUBTITLE)
			end
		end
	end
	local currentQuery = ""
	if self._searchBox then
		currentQuery = string.gsub(self._searchBox.Text, "^%s*(.-)%s*$", "%1")
	end
	-- Cards the search just revealed cascade in; cards that were already on screen stay put.
	local entering: { GuiObject } = {}
	for index, pd in ipairs(players) do
		local entry = self:_ensurePlayerCard(index, template)
		local card = entry.button
		if entry.connection then
			entry.connection:Disconnect()
			entry.connection = nil
		end
		if not card.Visible then
			table.insert(entering, card :: GuiObject)
		end
		card.Visible = true
		card.Parent = scrollFrame
		card.LayoutOrder = index
		card:SetAttribute("PlayerUserId", pd.userId)
		local info = card:FindFirstChild("PlayerInformation") :: Frame?
		if info then
			local nameLabel = info:FindFirstChild("1-Title") :: TextLabel?
			local userLabel = info:FindFirstChild("2-SubTitle") :: TextLabel?
			if nameLabel then
				nameLabel.RichText = true
				nameLabel.Text = highlightFirstMatch(pd.displayName, currentQuery)
			end
			if userLabel then
				userLabel.RichText = true
				userLabel.Text = "@" .. highlightFirstMatch(pd.username, currentQuery)
			end
		end
		local profilePicture = card:FindFirstChild("PlayerProfilePicture") :: ImageLabel?
		if profilePicture then
			setThumbnailAsync(profilePicture, pd.userId)
		end
		local uid = pd.userId
		local disp = pd.displayName
		local user = pd.username
		entry.connection = card.MouseButton1Click:Connect(function()
			self._selectedPlayer = { userId = uid, displayName = disp, username = user }
			local inputBox = self:_getActiveInputBox()
			if inputBox then
				inputBox.Text = user
			end
			-- The chosen card's avatar pops (UIMotion refuses it if the card is laid out).
			UIMotion.pop(profilePicture, 1.18)
			self:_refreshPlayerCardSelection()
		end)
		if self._selectedPlayer and self._selectedPlayer.userId == uid then
			selectedStillExists = true
		end
	end
	self:_hideUnusedPlayerCards(#players + 1)
	UIMotion.stagger(entering, self._fadeBases)
	if self._selectedPlayer and not selectedStillExists then
		self:_clearSelectedPlayer()
		return
	end
	self:_refreshPlayerCardSelection()
end
-- ============================================================
-- Player list
-- ============================================================
function GiftUI:populatePlayers(players: { { userId: number, displayName: string, username: string } })
	self._allPlayers = players
	if self._searchBox then
		self._searchBox.Text = ""
	end
	self:_clearSelectedPlayer()
	self:_applyPlayerSearch()
end

function GiftUI:selectPlayerByUserId(userId: number): boolean
	for _, playerData in ipairs(self._allPlayers) do
		if playerData.userId == userId then
			self._selectedPlayer = {
				userId = playerData.userId,
				displayName = playerData.displayName,
				username = playerData.username,
			}
			local inputBox = self:_getActiveInputBox()
			if inputBox then
				inputBox.Text = playerData.username
			end
			self:_refreshPlayerCardSelection()
			return true
		end
	end

	return false
end
-- ============================================================
-- Public API
-- ============================================================
function GiftUI:show(tierHint: string?)
	self._gui.Enabled = true
	self:setTab(tierHint or DEFAULT_TIER)
	self._anim:presentCenterPanel(self._mainWrapper, nil, {
		enableBlur = true,
		blurName = "GiftUIBlur",
		enableZoom = true
	})
	-- The controller refreshes the list before show(), so the cards are already on screen and
	-- would not count as "entering". Cascade whatever is listed as the panel pops open.
	local rows: { GuiObject } = {}
	for _, entry in ipairs(self._playerCardPool) do
		if entry.button.Visible then
			table.insert(rows, entry.button :: GuiObject)
		end
	end
	UIMotion.stagger(rows, self._fadeBases)
end
function GiftUI:hide()
	if self._isClosing then
		return
	end
	
	self._isClosing = true
	
	-- Hide notification if showing
	if self._notifWrapper.Visible then
		self:hideNotification()
	end
	
	self._anim:dismissCenterPanel(self._mainWrapper, function()
		self._isClosing = false
		self._gui.Enabled = false
	end, {
		enableBlur = true,
		blurName = "GiftUIBlur",
		enableZoom = true
	})
end
function GiftUI:isVisible(): boolean
	return self._gui.Enabled
end
-- Get target userId: from selected player list, or from textbox input
function GiftUI:getTarget(): (number?, string?)
	if self._selectedPlayer then
		return self._selectedPlayer.userId, nil
	end
	-- Coba from username input field active tab
	local inputBox = self:_getActiveInputBox()
	if inputBox and #inputBox.Text > 0 then
		return nil, inputBox.Text -- return username, needs resolution first
	end
	return nil, nil
end
function GiftUI:getActiveTier(): string
	return self._activeTier
end
function GiftUI:clearInput()
	local inputBox = self:_getActiveInputBox()
	if inputBox then
		inputBox.Text = ""
	end
	self._selectedPlayer = nil
end
-- Set input field text (for loading/error feedback)
function GiftUI:setInputText(text: string)
	local inputBox = self:_getActiveInputBox()
	if inputBox then
		inputBox.Text = text
	end
end
-- Notification for giftee (received from server after gift)
function GiftUI:showNotification(tier: string, senderName: string)
	local normalizedTier = normalizeTier(tier)
	if not normalizedTier then
		return
	end
	-- Ensure ScreenGui active (may be hidden because gift panel closed)
	self._gui.Enabled = true
	for _, t in ipairs(TIERS) do
		local n = self._notifWrapper:FindFirstChild(NOTIF_FRAME[t]) :: Frame?
		if n then
			n.Visible = false
		end
	end
	local notifName = NOTIF_FRAME[normalizedTier]
	local notif = notifName and self._notifWrapper:FindFirstChild(notifName) :: Frame?
	if not notif then
		return
	end
	-- Update title text
	local content = notif:FindFirstChild("1-RequestContent") :: Frame?
	local jumbotron = content and content:FindFirstChild("JumbotronTextandImage") :: Frame?
	local infoFrame = jumbotron and jumbotron:FindFirstChild("Frame") :: Frame?
	local titleLabel = infoFrame and infoFrame:FindFirstChild("1-Title") :: TextLabel?
	if titleLabel then
		local cfg = Config.Membership.Tiers[normalizedTier]
		local tierName = (cfg and cfg.label) or normalizedTier
		titleLabel.Text = "You received a " .. tierName .. " Giftcard from " .. senderName
	end
	notif.Visible = true
	self._notifWrapper.Visible = true
	-- Start RotatingBackground rotation on notification
	for _, img in ipairs(self._notifRotBgs) do
		table.insert(self._notifRotHandles, self._anim:startRotation(img))
	end
	-- swingIn animation
	if content then
		self._anim:swingIn(content :: Frame, self._notifWrapper, nil)
		-- The card swings in; its contents drop in under it and fade up. slideInVertical moves
		-- them with equal and opposite UIPadding, so the card itself never changes size.
		UIMotion.slideInVertical(content :: Frame, -1, 14)
		self:_fadeInGroup(content)
	end
end
function GiftUI:hideNotification()
	-- Stop notification rotation
	for _, h in ipairs(self._notifRotHandles) do
		self._anim:stopRotation(h)
	end
	self._notifRotHandles = {}
	self._notifWrapper.Visible = false
	-- Disable gui only if mainWrapper also not visible
	if not self._mainWrapper.Visible then
		self._gui.Enabled = false
	end
end
-- Bind events
function GiftUI:bindTabButton(tier: string, callback: () -> ())
	local normalizedTier = normalizeTier(tier)
	if not normalizedTier then
		return
	end
	local tierIndex = self._tierIndex[normalizedTier]
	local btn = tierIndex and self._tabButtons[tierIndex]
	if btn then
		self:_bindButtonMotion(btn)
		table.insert(self._connections, btn.MouseButton1Click:Connect(callback))
	end
end
function GiftUI:bindGiftButton(tier: string, callback: () -> ())
	local normalizedTier = normalizeTier(tier)
	if not normalizedTier then
		return
	end
	local frameName = TAB_FRAME[normalizedTier]
	local tabFrame = self._contentWrapper:FindFirstChild(frameName) :: Frame?
	local inputArea = tabFrame and tabFrame:FindFirstChild("InputArea") :: Frame?
	local btn = inputArea and inputArea:FindFirstChild(GIFT_BTN[normalizedTier]) :: TextButton?
	if btn then
		self:_bindButtonMotion(btn)
		local icon = btn:FindFirstChildWhichIsA("ImageLabel")
		table.insert(self._connections, btn.MouseButton1Click:Connect(function()
			-- Display-only read of the same target the controller is about to ask for: a send
			-- pops the button's icon, nothing to send shakes the field the player must fill.
			local userId, username = self:getTarget()
			if userId == nil and (username == nil or #username == 0) then
				UIMotion.wiggle((self:_getActiveInputBox() or btn) :: GuiObject, 6)
			else
				UIMotion.pop(icon :: GuiObject?, 1.25)
			end
			callback()
		end))
	end
end
function GiftUI:bindClose(callback: () -> ())
	if self._closeBtn then
		self:_bindButtonMotion(self._closeBtn)
		table.insert(self._connections, self._closeBtn.Activated:Connect(callback))
	end
end
function GiftUI:bindNotifClose(callback: () -> ())
	for _, t in ipairs(TIERS) do
		local notif = self._notifWrapper:FindFirstChild(NOTIF_FRAME[t]) :: Frame?
		local content = notif and notif:FindFirstChild("1-RequestContent") :: Frame?
		local inputArea = content and content:FindFirstChild("InputArea") :: Frame?
		local btn = inputArea and inputArea:FindFirstChildWhichIsA("TextButton") :: TextButton?
		if btn then
			self:_bindButtonMotion(btn)
			table.insert(self._connections, btn.MouseButton1Click:Connect(callback))
		end
	end
end
-- Cleanup path for every connection this panel owns (press/hover feedback, click handlers,
-- the search listener) plus the notification's rotation handles.
function GiftUI:destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	for _, entry in ipairs(self._playerCardPool) do
		if entry.connection then
			entry.connection:Disconnect()
			entry.connection = nil
		end
	end
	self:hideNotification()
end
return GiftUI
