--!strict
-- Client/UI/GiftUI.lua
-- Display only. Manages 03-GiftSystemGUI.
-- Tabs: VIP / VVIP / ELITE. Player list. Notification.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local ShopDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.ShopDomain)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
-- ============================================================
-- Mapping tier -> elemen GUI
-- ============================================================
local TAB_FRAME: { [string]: string } = {
}
local TAB_BTN: { [string]: string } = {
}
local GIFT_BTN: { [string]: string } = {
}
local NOTIF_FRAME: { [string]: string } = {
}
-- Gradient name yang di-enable saat tab aktif
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
	
	-- Set anchor point immediately, animate position with smooth easing
	backgroundPill.AnchorPoint = targetAnchorPoint
	local tween = TweenService:Create(
		backgroundPill,
		TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = targetPosition }
	)
	tween:Play()
end

-- ============================================================
local GiftUI = {} :: any
GiftUI.__index = GiftUI
local WAIT_TIMEOUT = 10 -- detik maksimal menunggu elemen GUI
local SEARCH_HIGHLIGHT_COLOR = "#FF7EB6"
local EMPTY_STATE_DEFAULT_TITLE = "No one is eligible right now"
local EMPTY_STATE_DEFAULT_SUBTITLE = "When a player is ready to receive, they'll appear here."
local EMPTY_STATE_SEARCH_TITLE = "No match this time"
local EMPTY_STATE_SEARCH_SUBTITLE = "Try another display name or username."
type PlayerListEntry = {
	button: TextButton,
	connection: RBXScriptConnection?,
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
-- Private helper: cari semua RotatingBackground di bawah root
-- ============================================================
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
		warn("[GiftUI] MainWrapper tidak ditemukan di " .. gui.Name)
		return self
	end
	local contentWrapper = mainWrapper:WaitForChild("02-MainContentWrapper", WAIT_TIMEOUT) :: Frame
	local headerWrapper = mainWrapper:WaitForChild("01-HeaderWrapper", WAIT_TIMEOUT) :: Frame
	local notifWrapper = gui:WaitForChild("NotificationWrapper", WAIT_TIMEOUT) :: Frame
	if not (contentWrapper and headerWrapper and notifWrapper) then
		warn("[GiftUI] Elemen wajib tidak ditemukan di " .. gui.Name)
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
	-- RotatingBackground: hanya notif yang dipertahankan
	self._notifRotBgs = collectRotatingBgs(notifWrapper)
	self._notifRotHandles = {} :: { any }
	-- Tab button labels already set above during button collection
	-- Sembunyikan semua saat init
	gui.Enabled = false
	notifWrapper.Visible = false
	mainWrapper.Visible = false
	if searchBox then
		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			self:_applyPlayerSearch()
		end)
	end
	return self
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
	self._activeTier = normalizedTier
	self._selectedPlayer = nil -- reset selected saat ganti tab
	-- Show/hide tab frames
	for _, t in ipairs(TIERS) do
		local frameName = TAB_FRAME[t]
		local frame = self._contentWrapper:FindFirstChild(frameName) :: Frame?
		if frame then
			frame.Visible = (t == normalizedTier)
		end
		self:_setTabActive(t, t == normalizedTier)
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
	entry = {
		button = card,
		connection = nil,
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
		entry.button.BackgroundTransparency = 1
	end
end
function GiftUI:_refreshPlayerCardSelection()
	for _, entry in ipairs(self._playerCardPool) do
		local userId = entry.button:GetAttribute("PlayerUserId")
		local isSelected = self._selectedPlayer ~= nil
			and type(userId) == "number"
			and self._selectedPlayer.userId == userId
		entry.button.BackgroundTransparency = if isSelected then Config.Gift.CARD_SELECTED_ALPHA else 1
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
		notFoundCard.Visible = (#players == 0)
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
	for index, pd in ipairs(players) do
		local entry = self:_ensurePlayerCard(index, template)
		local card = entry.button
		if entry.connection then
			entry.connection:Disconnect()
			entry.connection = nil
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
			self:_refreshPlayerCardSelection()
		end)
		if self._selectedPlayer and self._selectedPlayer.userId == uid then
			selectedStillExists = true
		end
	end
	self:_hideUnusedPlayerCards(#players + 1)
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
-- Ambil userId target: dari selected player list, atau dari textbox input
function GiftUI:getTarget(): (number?, string?)
	if self._selectedPlayer then
		return self._selectedPlayer.userId, nil
	end
	-- Coba dari username input field active tab
	local inputBox = self:_getActiveInputBox()
	if inputBox and #inputBox.Text > 0 then
		return nil, inputBox.Text -- kembalikan username, perlu di-resolve dulu
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
-- Set teks input field aktif (untuk loading/error feedback)
function GiftUI:setInputText(text: string)
	local inputBox = self:_getActiveInputBox()
	if inputBox then
		inputBox.Text = text
	end
end
-- Notifikasi untuk giftee (diterima dari server setelah mendapat gift)
function GiftUI:showNotification(tier: string, senderName: string)
	local normalizedTier = normalizeTier(tier)
	if not normalizedTier then
		return
	end
	-- Pastikan ScreenGui aktif (bisa sedang tersembunyi karena gift panel ditutup)
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
	-- Start rotasi RotatingBackground di notifikasi
	for _, img in ipairs(self._notifRotBgs) do
		table.insert(self._notifRotHandles, self._anim:startRotation(img))
	end
	-- swingIn animasi
	if content then
		self._anim:swingIn(content :: Frame, self._notifWrapper, nil)
	end
end
function GiftUI:hideNotification()
	-- Stop rotasi notifikasi
	for _, h in ipairs(self._notifRotHandles) do
		self._anim:stopRotation(h)
	end
	self._notifRotHandles = {}
	self._notifWrapper.Visible = false
	-- Disable gui hanya kalau mainWrapper juga tidak tampil
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
		btn.MouseButton1Click:Connect(callback)
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
		btn.MouseButton1Click:Connect(callback)
	end
end
function GiftUI:bindClose(callback: () -> ())
	if self._closeBtn then
		self._closeBtn.Activated:Connect(callback)
	end
end
function GiftUI:bindNotifClose(callback: () -> ())
	for _, t in ipairs(TIERS) do
		local notif = self._notifWrapper:FindFirstChild(NOTIF_FRAME[t]) :: Frame?
		local content = notif and notif:FindFirstChild("1-RequestContent") :: Frame?
		local inputArea = content and content:FindFirstChild("InputArea") :: Frame?
		local btn = inputArea and inputArea:FindFirstChildWhichIsA("TextButton") :: TextButton?
		if btn then
			btn.MouseButton1Click:Connect(callback)
		end
	end
end
return GiftUI
