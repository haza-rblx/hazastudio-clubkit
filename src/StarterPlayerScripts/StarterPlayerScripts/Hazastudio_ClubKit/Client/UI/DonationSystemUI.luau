--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GeneralNotificationCenterService = require(script.Parent.Parent.Services.GeneralNotificationCenterService)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local DonationProviderDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.DonationProviderDomain)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local DonationAmountFormat = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DonationAmountFormat)

type DonorProfilePayload = Types.DonorProfilePayload
local DonationSystemGuiRefs = require(script.Parent.DonationSystemGuiRefs)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
local AvatarViewport3D = require(script.Parent.Parent.Utils.AvatarViewport3D)
local AvatarPrewarmShared = require(script.Parent.Parent.Utils.AvatarPrewarmShared)

type Refs = DonationSystemGuiRefs.Refs

export type Product = {
	key: string,
	name: string,
	price: number,
	productId: number,
}

export type DonationSystemUI = {
	show: (self: DonationSystemUI) -> (),
	hide: (self: DonationSystemUI) -> (),
	closeAll: (self: DonationSystemUI) -> (),
	bindClose: (self: DonationSystemUI, callback: () -> ()) -> (),
	bindDonateRequested: (self: DonationSystemUI, callback: (product: Product, message: string) -> ()) -> (),
	populateProducts: (self: DonationSystemUI, products: { Product }) -> (),
	refreshProducts: (self: DonationSystemUI, fetchProducts: (() -> { Product })?) -> (),
	applyDonorProfile: (self: DonationSystemUI, profile: DonorProfilePayload?) -> (),
	refreshDonorProfile: (self: DonationSystemUI, fetchProfile: (() -> DonorProfilePayload?)?) -> (),
	bindProfileRefresh: (self: DonationSystemUI, fetchProfile: () -> DonorProfilePayload?) -> (),
	setDonationResult: (self: DonationSystemUI, ok: boolean, message: string?) -> (),
}

local DonationSystemUI = {}
DonationSystemUI.__index = DonationSystemUI

local function getExternalProviderName(): string
	return DonationProviderDomain.getName()
end

local function getExternalProviderLink(): string
	return tostring(Config.Donation.PROVIDER_LINK or Config.Donation.BAGIBAGI_LINK or Config.Donation.SAWERIA_LINK or "")
end

local function isCashDonationEnabled(): boolean
	local cashEnabled = Config.FeatureFlags.DonationCashEnabled
	if cashEnabled == nil then
		cashEnabled = Config.FeatureFlags.DonationSaweriaEnabled ~= false
	end
	return cashEnabled ~= false
end

local function findAncestorNamed(instance: Instance?, name: string): Instance?
	local current = instance
	while current do
		if current.Name == name then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function setGuiVisible(gui: Instance?, visible: boolean)
	if gui and gui:IsA("GuiObject") then
		gui.Visible = visible
	end
end

local function applyCashFeatureVisibility(refs: Refs, cashEnabled: boolean)
	setGuiVisible(refs.saweriaTabButton, cashEnabled)
	if not cashEnabled then
		setGuiVisible(refs.saweriaTab, false)
	end
	setGuiVisible(refs.copyLinkButton, cashEnabled)

	local tabSwitcher = if refs.robuxTabButton then refs.robuxTabButton.Parent else nil
	if tabSwitcher and tabSwitcher:IsA("GuiObject") then
		tabSwitcher.Visible = cashEnabled
	end
	setGuiVisible(refs.backgroundPill, cashEnabled)

	local cashStatsRoot = findAncestorNamed(refs.saweriaRankLabel, "SaweriaDonations")
		or findAncestorNamed(refs.saweriaValueLabel, "SaweriaDonations")
	setGuiVisible(cashStatsRoot, cashEnabled)
end

local function setDisplayText(target: GuiObject?, text: string)
	if not target then
		return
	end
	if target:IsA("TextLabel") or target:IsA("TextButton") then
		target.Text = text
		return
	end
	local childLabel = target:FindFirstChildWhichIsA("TextLabel", true)
		or target:FindFirstChildWhichIsA("TextButton", true)
	if childLabel and (childLabel:IsA("TextLabel") or childLabel:IsA("TextButton")) then
		childLabel.Text = text
	end
end

local function focusAndSelectLink(textBox: TextBox, link: string)
	textBox.Text = link
	textBox.TextEditable = true
	textBox.ClearTextOnFocus = false
	textBox:CaptureFocus()
	textBox.CursorPosition = #link + 1
	textBox.SelectionStart = 1
end

local function configureReadOnlySelectableLink(textBox: TextBox, getLink: () -> string)
	local restoring = false
	local function restoreLink()
		local link = getLink()
		if textBox.Text == link then
			return
		end
		restoring = true
		textBox.Text = link
		textBox.CursorPosition = #link + 1
		textBox.SelectionStart = 1
		restoring = false
	end

	textBox.Active = true
	textBox.Selectable = true
	textBox.TextEditable = true
	textBox.ClearTextOnFocus = false
	textBox.Text = getLink()

	textBox.Focused:Connect(function()
		focusAndSelectLink(textBox, getLink())
	end)
	textBox.FocusLost:Connect(function()
		restoreLink()
	end)
	textBox:GetPropertyChangedSignal("Text"):Connect(function()
		if restoring then
			return
		end
		restoreLink()
	end)
end

local function setButtonLabel(button: TextButton?, text: string)
	if not button then
		return
	end
	if button.Text ~= "" then
		button.Text = text
	end
	local label = button:FindFirstChild("TextLabel", true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function applyExternalProviderText(root: Instance)
	DonationProviderDomain.applyDisplayText(root)
end

local ACTIVE_GRADIENT = "UIGradient-Gold"
local NORMAL_GRADIENT = "UIGradient-Normal"
local TAB_SWITCH_TIME = 0.14
local TAB_ACTIVE_SCALE = 1
local TAB_INACTIVE_SCALE = 0.96
local SAFE_EMOJIS = {
	"😀",
	"😃",
	"😄",
	"😁",
	"😆",
	"😅",
	"😂",
	"🤣",
	"😊",
	"😇",
	"🙂",
	"🙃",
	"😉",
	"😍",
	"😘",
	"😎",
	"🤩",
	"🥳",
	"😜",
	"😋",
	"🤗",
	"🤔",
	"😴",
	"😈",
	"👑",
	"💎",
	"🔥",
	"✨",
	"🌟",
	"⭐",
	"⚡",
	"💯",
	"🎉",
	"🎁",
	"🏆",
	"🥇",
	"🥈",
	"🥉",
	"🎵",
	"🎶",
	"🎧",
	"🎤",
	"💃",
	"🕺",
	"❤️",
	"🧡",
	"💛",
	"💚",
	"💙",
	"💜",
	"🤍",
	"🖤",
	"💕",
	"💞",
	"💓",
	"💗",
	"💖",
	"💘",
	"💝",
	"💟",
	"🌹",
	"🌺",
	"🌸",
	"🌼",
	"🌻",
	"🍀",
	"🌈",
	"☀️",
	"🌙",
	"☁️",
	"🌊",
	"🍓",
	"🍒",
	"🍑",
	"🍭",
	"🍬",
	"🍼",
	"🧸",
	"🎮",
	"🕹️",
	"🚀",
	"🛸",
	"🏝️",
	"🏖️",
	"💼",
	"🛡️",
	"⚔️",
	"🗡️",
	"🔮",
	"🪄",
	"📌",
	"✅",
}

local function formatRobux(value: number): string
	local s = tostring(math.floor(value))
	local result = ""
	local len = #s
	for i = 1, len do
		if i > 1 and (len - i + 1) % 3 == 0 then
			result ..= "."
		end
		result ..= s:sub(i, i)
	end
	return result
end

local function trim(text: string): string
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function truncateUtf8(text: string, maxChars: number): string
	if maxChars <= 0 then
		return ""
	end

	local ok, length = pcall(utf8.len, text)
	if not ok or type(length) ~= "number" or length <= maxChars then
		return text
	end

	local byteIndex = utf8.offset(text, maxChars + 1)
	if not byteIndex then
		return text
	end
	return string.sub(text, 1, byteIndex - 1)
end

local function getPointerPosition(): Vector2
	local mouse = UserInputService:GetMouseLocation()
	return Vector2.new(mouse.X, mouse.Y)
end

local function placeNearPointer(panel: GuiObject, pointer: Vector2, screenGui: ScreenGui)
	local screenSize = screenGui.AbsoluteSize
	local panelSize = panel.AbsoluteSize
	local scale = 1
	local uiScale = screenGui:FindFirstChildWhichIsA("UIScale")
	if uiScale then
		scale = math.max(uiScale.Scale, 0.01)
	end

	local x = math.clamp((pointer.X + 14) / scale, 8, math.max(8, (screenSize.X - panelSize.X - 8) / scale))
	local y = math.clamp((pointer.Y + 14) / scale, 8, math.max(8, (screenSize.Y - panelSize.Y - 8) / scale))

	panel.AnchorPoint = Vector2.new(0, 0)
	panel.Position = UDim2.fromOffset(x, y)
end

local function setTabButtonActive(button: TextButton, active: boolean)
	-- Remove active gradient instantly
	for _, child in ipairs(button:GetChildren()) do
		if child.Name == ACTIVE_GRADIENT then
			child.Parent = nil
		end
	end

	-- Add gradient if active
	if active then
		local activeGradient = button:FindFirstChild(NORMAL_GRADIENT)
		if activeGradient and activeGradient:IsA("UIGradient") then
			local activeClone = activeGradient:Clone()
			activeClone.Name = ACTIVE_GRADIENT
			activeClone.Parent = button
		end
	end
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
	
	-- Set anchor point immediately, animate position with spring smooth
	backgroundPill.AnchorPoint = targetAnchorPoint
	local tween = TweenService:Create(
		backgroundPill,
		TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = targetPosition }
	)
	tween:Play()
end

local function getOrCreateUIScale(frame: GuiObject, name: string): UIScale
	local existing = frame:FindFirstChild(name)
	if existing and existing:IsA("UIScale") then
		return existing
	end

	local scale = Instance.new("UIScale")
	scale.Name = name
	scale.Scale = 1
	scale.Parent = frame
	return scale
end

local function popOpenFromTopCenter(anim: AnimationHelper.AnimationHelper, panel: GuiObject)
	local position = panel.Position
	local size = panel.Size
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(
		position.X.Scale + size.X.Scale * 0.5,
		position.X.Offset + size.X.Offset * 0.5,
		position.Y.Scale,
		position.Y.Offset
	)
	anim:scalePop((panel :: any) :: Frame)
end

local function findTextLabel(root: Instance, name: string): TextLabel?
	local found = root:FindFirstChild(name, true)
	if found and found:IsA("TextLabel") then
		return found
	end
	return nil
end

local function isWithinGuiObject(gui: GuiObject, screenPosition: Vector2): boolean
	local position = gui.AbsolutePosition
	local size = gui.AbsoluteSize
	return screenPosition.X >= position.X
		and screenPosition.X <= position.X + size.X
		and screenPosition.Y >= position.Y
		and screenPosition.Y <= position.Y + size.Y
end

local function _clipRotatingBackground_unused(image: ImageLabel)
	local parent = image.Parent
	if parent and parent:IsA("GuiObject") then
		parent.ClipsDescendants = true
	end
end

local ROBUX_TEMPLATE_NAME = "ProductCardTemplate"
local ROBUX_NOT_FOUND_NAME = "NotFoundCard"

local function isRobuxScrollChrome(child: Instance, template: Instance?, notFoundCard: GuiObject?): boolean
	if child == template or child == notFoundCard then
		return true
	end
	if child.Name == ROBUX_TEMPLATE_NAME or child.Name == ROBUX_NOT_FOUND_NAME then
		return true
	end
	if child:IsA("UIListLayout") or child:IsA("UIPadding") or child:IsA("UIScale") or child:IsA("UIStroke") then
		return true
	end
	return false
end

local function hideDesignTimeProductCards(scroll: ScrollingFrame, template: Instance?, notFoundCard: GuiObject?)
	for _, child in ipairs(scroll:GetChildren()) do
		if isRobuxScrollChrome(child, template, notFoundCard) then
			continue
		end
		if child:IsA("GuiObject") then
			child.Visible = false
		end
	end
end

function DonationSystemUI.new(refs: Refs): DonationSystemUI
	local self = setmetatable({}, DonationSystemUI) :: any
	self._refs = refs
	self._activeTab = "robux"
	self._selectedProduct = nil :: Product?
	self._donateRequested = nil :: ((Product, string) -> ())?
	self._closeCallback = nil :: (() -> ())?
	self._productConnections = {} :: { RBXScriptConnection }
	self._anim = AnimationHelper.new()
	self._avatarViewport3D = nil :: any
	self._avatarThumbnail = nil :: ImageLabel?
	self._avatarModelReadyUnsub = nil :: (() -> ())?
	self._avatarPool = AvatarPrewarmShared.getPool()
	self._isMainVisible = false
	self._isClosingMain = false
	self._profileRefreshToken = 0
	self._profileRefreshHandler = nil :: (() -> DonorProfilePayload?)?
	self._lastDonorProfile = nil :: DonorProfilePayload?
	self._productRefreshToken = 0
	self._productRefreshHandler = nil :: (() -> { Product })?
	self._emojiPicker = nil :: GuiObject?
	self._emojiConnections = {} :: { RBXScriptConnection }
	self._cashDonationEnabled = isCashDonationEnabled()

	refs.root.Enabled = false
	refs.mainWrapper.Visible = false
	refs.inputModal.Visible = false
	refs.robuxTab.ClipsDescendants = true
	refs.saweriaTab.ClipsDescendants = true
	refs.robuxScroll.ClipsDescendants = true
	refs.messageBox.ClearTextOnFocus = false
	refs.messageBox.Text = ""
	if refs.emojiPicker then
		refs.emojiPicker.Visible = false
	end
	if refs.emojiTemplate then
		refs.emojiTemplate.Visible = false
	end
	if refs.productTemplate then
		refs.productTemplate.Visible = false
	end
	-- Default empty state sampai refreshProducts selesai (template tidak pernah ditampilkan langsung).
	if refs.notFoundCard then
		refs.notFoundCard.Visible = true
	end
	applyExternalProviderText(refs.root)
	DonationProviderDomain.applyCashTabBrand(refs.saweriaTab)

	if refs.saweriaLink then
		configureReadOnlySelectableLink(refs.saweriaLink, getExternalProviderLink)
	end
	setButtonLabel(refs.saweriaTabButton, getExternalProviderName())

	if refs.avatarViewport then
		-- Pool dipanggil sebagai side effect (AvatarPrewarmShared.getPool()) saat
		-- init state di atas — saat itu self._avatarPool sudah ter-set. Defer
		-- pemanggilan showAvatar ke akhir resumption cycle agar queue prewarm self
		-- punya kesempatan jalan dulu, sehingga pool hit di kesempatan kedua.
		local localUserId = Players.LocalPlayer.UserId
		task.defer(function()
			self:_showDonationAvatar(localUserId)
		end)
	end

	refs.robuxTabButton.Activated:Connect(function()
		self:_setTab("robux")
	end)
	refs.saweriaTabButton.Activated:Connect(function()
		self:_setTab("saweria")
	end)
	refs.cancelButton.Activated:Connect(function()
		self:_hideMessageModal(true)
	end)
	refs.continueButton.Activated:Connect(function()
		self:_confirmDonation()
	end)
	if refs.closeButton then
		refs.closeButton.Activated:Connect(function()
			self:hide()
			if self._closeCallback then
				self._closeCallback()
			end
		end)
	end
	if refs.copyLinkButton then
		refs.copyLinkButton.Activated:Connect(function()
			self:_handleCopySaweriaLink()
		end)
	end
	if refs.addEmojiButton then
		self:_setupEmojiPicker(refs.addEmojiButton)
	end

	applyCashFeatureVisibility(refs, self._cashDonationEnabled)
	if not self._cashDonationEnabled then
		self._activeTab = "robux"
	end

	self:_setTab(self._activeTab)
	return self
end

-- Tampilkan avatar 3D di donation panel donor profile.
-- Pakai pola pool-or-thumbnail yang sama dengan AvatarContextUI.showAvatar:
--   1. Coba ambil model dari prewarm pool (instant kalau hit).
--   2. Kalau miss, tampilkan ImageLabel thumbnail instan (no YIELD).
--   3. Subscribe ke pool.subscribeModelReady untuk upgrade seamless ke 3D.
--   4. Trigger pool.prewarmOnDemand supaya load berikutnya instant.
-- Tanpa fallback path, race condition antara pool init + viewport load()
-- akan bikin viewport kosong selamanya (lihat investigasi 2026-06-17).
function DonationSystemUI:_showDonationAvatar(userId: number)
	local viewport = self._refs.avatarViewport
	if not viewport then return end

	-- Bersihkan subscription upgrade lama (kalau show() dipanggil dua kali).
	if self._avatarModelReadyUnsub then
		self._avatarModelReadyUnsub()
		self._avatarModelReadyUnsub = nil
	end

	viewport.Visible = true
	if self._avatarThumbnail then
		self._avatarThumbnail.Visible = false
	end

	if not self._avatarViewport3D then
		self._avatarViewport3D = AvatarViewport3D.new(viewport)
		self._avatarViewport3D:setPrewarmPool(self._avatarPool)
	else
		self._avatarViewport3D:cleanup()
	end

	local success = self._avatarViewport3D:load(userId)
	if success then return end

	-- Pool miss: tampilkan thumbnail ImageLabel instan.
	local thumbUrl = ("rbxthumb://type=AvatarBust&id=%d&w=420&h=420"):format(userId)
	if not self._avatarThumbnail then
		self._avatarThumbnail = Instance.new("ImageLabel")
	end
	local thumb = self._avatarThumbnail :: ImageLabel
	thumb.Name = "AvatarThumbnailFallback"
	thumb.Size = UDim2.fromScale(1, 1)
	thumb.Position = UDim2.fromScale(0.5, 0.5)
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.BackgroundTransparency = 1
	thumb.Image = thumbUrl
	thumb.ScaleType = Enum.ScaleType.Fit
	thumb.Visible = true
	thumb.Parent = viewport

	if self._avatarPool and type(self._avatarPool.subscribeModelReady) == "function" then
		self._avatarModelReadyUnsub = self._avatarPool:subscribeModelReady(userId, function()
			-- Guard: viewport masih hidup & visible (mungkin panel ditutup
			-- atau GUI di-destroy saat loading).
			if not viewport.Parent or not viewport.Visible then return end
			if not self._avatarViewport3D then
				self._avatarViewport3D = AvatarViewport3D.new(viewport)
				self._avatarViewport3D:setPrewarmPool(self._avatarPool)
			else
				self._avatarViewport3D:cleanup()
			end
			local reloaded = self._avatarViewport3D:load(userId)
			if reloaded and self._avatarThumbnail then
				self._avatarThumbnail.Visible = false
			end
		end)
	end

	-- Trigger background prewarm supaya click berikutnya instant.
	if self._avatarPool and type(self._avatarPool.prewarmOnDemand) == "function" then
		self._avatarPool:prewarmOnDemand(userId)
	end
end

function DonationSystemUI:_setTab(tabName: string)
	if tabName ~= "robux" and not self._cashDonationEnabled then
		tabName = "robux"
	end
	self._activeTab = tabName
	local isRobux = tabName == "robux"
	local activeFrame = if isRobux then self._refs.robuxTab else self._refs.saweriaTab
	local inactiveFrame = if isRobux then self._refs.saweriaTab else self._refs.robuxTab

	inactiveFrame.Visible = false
	activeFrame.Visible = true

	setTabButtonActive(self._refs.robuxTabButton, isRobux)
	setTabButtonActive(self._refs.saweriaTabButton, not isRobux)
	
	-- Animate sliding pill to selected tab
	if self._refs.backgroundPill then
		local selectedButton = if isRobux then self._refs.robuxTabButton else self._refs.saweriaTabButton
		animateSlidingPill(self._refs.backgroundPill, selectedButton, {
			self._refs.robuxTabButton,
			self._refs.saweriaTabButton,
		})
	end
end

function DonationSystemUI:_showMessageModal(product: Product)
	self._selectedProduct = product
	self._refs.messageBox.Text = ""
	if self._refs.continueText then
		self._refs.continueText.Text = ("Continue donate - %s Robux"):format(formatRobux(product.price))
	end

	if self._emojiPicker then
		self._emojiPicker.Visible = false
	end

	local function showInputModal()
		self._anim:presentCenterPanel(self._refs.inputModal, function()
			self._refs.messageBox:CaptureFocus()
		end)
	end

	if self._refs.mainWrapper.Visible then
		self._anim:dismissCenterPanel(self._refs.mainWrapper, showInputModal, {
			enableBlur = true,
			blurName = "DonationUIBlur",
			enableZoom = true
		})
	else
		showInputModal()
	end
end

function DonationSystemUI:_hideMessageModal(restoreMain: boolean?)
	self._selectedProduct = nil
	if self._emojiPicker then
		self._emojiPicker.Visible = false
	end
	self._anim:dismissCenterPanel(self._refs.inputModal, function()
		self._refs.messageBox.Text = ""
		if restoreMain == true and self._isMainVisible then
			self._anim:presentCenterPanel(self._refs.mainWrapper, nil, {
				enableBlur = true,
				blurName = "DonationUIBlur",
				enableZoom = true
			})
		end
	end)
end

function DonationSystemUI:_confirmDonation()
	local product = self._selectedProduct
	if not product then
		return
	end

	local message = trim(self._refs.messageBox.Text)
	message = truncateUtf8(message, Config.Donation.ROBUX_MESSAGE_MAX_LENGTH)

	self:_hideMessageModal(false)
	if self._donateRequested then
		self._donateRequested(product, message)
	end
end

function DonationSystemUI:_handleCopySaweriaLink()
	local providerName = getExternalProviderName()
	local link = getExternalProviderLink()
	if self._refs.saweriaLink then
		focusAndSelectLink(self._refs.saweriaLink, link)
	end

	GeneralNotificationCenterService.show({
		title = providerName,
		description = link,
		message = "Link selected. Press Ctrl+C to copy.",
		notifType = "INFO",
		domain = "donation",
		dedupeKey = "donation-provider-link",
	})
end

function DonationSystemUI:populateProducts(products: { Product })
	for _, connection in ipairs(self._productConnections) do
		connection:Disconnect()
	end
	table.clear(self._productConnections)

	local refs = self._refs
	local template = refs.productTemplate
	local notFoundCard = refs.notFoundCard

	for _, child in ipairs(refs.robuxScroll:GetChildren()) do
		if child:IsA("TextButton") and child:GetAttribute("DonationRuntimeCard") == true then
			child:Destroy()
		end
	end
	hideDesignTimeProductCards(refs.robuxScroll, template, notFoundCard)

	if template then
		template.Visible = false
	end

	local configuredProducts = table.clone(products)
	local hasProducts = #configuredProducts > 0 and template ~= nil

	if hasProducts and template then
		for index, product in ipairs(configuredProducts) do
			local card = template:Clone()
			card.Name = "DonationProduct_" .. product.key
			card:SetAttribute("DonationRuntimeCard", true)
			card.LayoutOrder = template.LayoutOrder + index
			card.Visible = true
			card.Parent = refs.robuxScroll

			local productName = findTextLabel(card, "ProductName")
			if productName then
				productName.Text = product.name
			end
			local productPrice = findTextLabel(card, "DonationProductPrice")
			if productPrice then
				productPrice.Text = formatRobux(product.price)
			end

			local donationButton = card:FindFirstChild("DonationButton", true)
			if donationButton and donationButton:IsA("TextButton") then
				table.insert(
					self._productConnections,
					donationButton.Activated:Connect(function()
						self:_showMessageModal(product)
					end)
				)
			else
				table.insert(
					self._productConnections,
					card.Activated:Connect(function()
						self:_showMessageModal(product)
					end)
				)
			end
		end
	end

	if notFoundCard then
		notFoundCard.Visible = not hasProducts
	end
end

function DonationSystemUI:bindProductRefresh(fetchProducts: () -> { Product })
	self._productRefreshHandler = fetchProducts
end

function DonationSystemUI:refreshProducts(fetchProducts: (() -> { Product })?)
	local resolver = fetchProducts or self._productRefreshHandler
	if not resolver then
		return
	end
	self._productRefreshToken += 1
	local token = self._productRefreshToken
	task.spawn(function()
		local products = resolver()
		if token ~= self._productRefreshToken then
			return
		end
		self:populateProducts(products)
	end)
end

function DonationSystemUI:_setupEmojiPicker(addEmojiButton: TextButton)
	local picker = self._refs.emojiPicker
	local emojiList = self._refs.emojiList
	local emojiTemplate = self._refs.emojiTemplate
	if not picker or not emojiList or not emojiTemplate then
		return
	end

	picker.Visible = false
	emojiTemplate.Visible = false

	for _, child in ipairs(emojiList:GetChildren()) do
		if child:IsA("TextButton") and child:GetAttribute("DonationEmojiRuntime") == true then
			child:Destroy()
		end
	end

	for index, emoji in ipairs(SAFE_EMOJIS) do
		local button = emojiTemplate:Clone() :: TextButton
		button.Name = "EmojiButton" .. index
		button:SetAttribute("DonationEmojiRuntime", true)
		button.Visible = true
		button.LayoutOrder = index
		local label = button:FindFirstChildWhichIsA("TextLabel")
		if label then
			label.Text = emoji
		else
			button.Text = emoji
		end
		button.Parent = emojiList

		table.insert(
			self._emojiConnections,
			button.MouseButton1Click:Connect(function()
				self:_appendMessageEmoji(emoji)
				picker.Visible = false
			end)
		)
	end

	if self._refs.emojiCloseButton then
		table.insert(
			self._emojiConnections,
			self._refs.emojiCloseButton.Activated:Connect(function()
				picker.Visible = false
			end)
		)
	end

	table.insert(
		self._emojiConnections,
		addEmojiButton.Activated:Connect(function()
			if picker.Visible then
				picker.Visible = false
				return
			end

			placeNearPointer(picker, getPointerPosition(), self._refs.root)
			popOpenFromTopCenter(self._anim, picker)
			self._refs.messageBox:CaptureFocus()
		end)
	)

	table.insert(
		self._emojiConnections,
		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed or not picker.Visible then
				return
			end
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end

			local position = Vector2.new(input.Position.X, input.Position.Y)
			if not isWithinGuiObject(picker, position) and not isWithinGuiObject(addEmojiButton, position) then
				picker.Visible = false
			end
		end)
	)

	self._emojiPicker = picker
end

function DonationSystemUI:_appendMessageEmoji(emoji: string)
	local current = trim(self._refs.messageBox.Text)
	local nextText = if current == "" then emoji else current .. " " .. emoji
	self._refs.messageBox.Text = truncateUtf8(nextText, Config.Donation.ROBUX_MESSAGE_MAX_LENGTH)
	self._refs.messageBox.CursorPosition = -1
end

function DonationSystemUI:setDonationResult(ok: boolean, message: string?)
	GeneralNotificationCenterService.show({
		title = if ok then "Donation" else "Donation",
		description = message or (if ok then "Thank you for the support." else "Donation could not be started."),
		message = message or "",
		notifType = if ok then "SUCCESS" else "WARNING",
		domain = "donation",
		dedupeKey = if ok then "donation-robux-success" else "donation-robux-warning",
	})
end

function DonationSystemUI:applyDonorProfile(profile: DonorProfilePayload?)
	if profile then
		self._lastDonorProfile = profile
	end
	local refs = self._refs
	DonationSystemGuiRefs.refreshStatLabelRefs(refs)
	local data = profile or self._lastDonorProfile
	if not data then
		return
	end

	local displayName = tostring(data.displayName or "")
	if displayName == "" then
		displayName = tostring(data.username or "")
	end
	if refs.displayNameLabel then
		refs.displayNameLabel.Text = displayName
	end
	if refs.usernameLabel then
		local username = tostring(data.username or "")
		refs.usernameLabel.Text = if username ~= "" then "@" .. username else ""
	end
	setDisplayText(refs.robuxRankLabel, DonationAmountFormat.formatRank(data.robuxRank))
	setDisplayText(refs.robuxValueLabel, DonationAmountFormat.formatCompact(data.robuxTotal))
	if self._cashDonationEnabled then
		setDisplayText(refs.saweriaRankLabel, DonationAmountFormat.formatRank(data.cashRank))
		setDisplayText(refs.saweriaValueLabel, DonationAmountFormat.formatCompact(data.cashTotal))
	end
end

function DonationSystemUI:bindProfileRefresh(fetchProfile: () -> DonorProfilePayload?)
	self._profileRefreshHandler = fetchProfile
end

function DonationSystemUI:refreshDonorProfile(fetchProfile: (() -> DonorProfilePayload?)?)
	local resolver = fetchProfile or self._profileRefreshHandler
	if not resolver then
		return
	end
	self._profileRefreshToken += 1
	local token = self._profileRefreshToken
	task.spawn(function()
		local profile = resolver()
		if token ~= self._profileRefreshToken then
			return
		end
		if profile then
			self:applyDonorProfile(profile)
		end
	end)
end

function DonationSystemUI:bindClose(callback: () -> ())
	self._closeCallback = callback
end

function DonationSystemUI:bindDonateRequested(callback: (product: Product, message: string) -> ())
	self._donateRequested = callback
end

function DonationSystemUI:_startRotatingBackgrounds() end

function DonationSystemUI:_stopRotatingBackgrounds() end

function DonationSystemUI:show()
	self._cashDonationEnabled = isCashDonationEnabled()
	applyCashFeatureVisibility(self._refs, self._cashDonationEnabled)
	if not self._cashDonationEnabled and self._activeTab ~= "robux" then
		self._activeTab = "robux"
	end
	self._refs.root.Enabled = true
	self._isMainVisible = true
	self._isClosingMain = false
	self:_startRotatingBackgrounds()
	self._anim:presentCenterPanel(self._refs.mainWrapper, nil, {
		enableBlur = true,
		blurName = "DonationUIBlur",
		enableZoom = true
	})
	DonationSystemGuiRefs.refreshStatLabelRefs(self._refs)
	if self._profileRefreshHandler then
		self:refreshDonorProfile(self._profileRefreshHandler)
	end
	if self._productRefreshHandler then
		self:refreshProducts(self._productRefreshHandler)
	end
	self:_setTab(self._activeTab)
	-- Re-trigger avatar load di setiap buka. Kalau pool sudah ready, 3D
	-- tampil instan; kalau belum (mis. dibuka sebelum pool prewarm selesai
	-- di boot pertama), fallback thumbnail + subscribe upgrade seamless.
	if self._refs.avatarViewport then
		self:_showDonationAvatar(Players.LocalPlayer.UserId)
	end
end

function DonationSystemUI:hide()
	if not self._refs.root.Enabled and not self._refs.mainWrapper.Visible and not self._refs.inputModal.Visible then
		return
	end
	if self._isClosingMain then
		return
	end

	self._isMainVisible = false
	self._isClosingMain = true
	if self._refs.inputModal.Visible then
		self._refs.inputModal.Visible = false
	end
	if self._emojiPicker then
		self._emojiPicker.Visible = false
	end

	if not self._refs.mainWrapper.Visible then
		self._isClosingMain = false
		self._refs.root.Enabled = false
		self:_stopRotatingBackgrounds()
		return
	end

	self._anim:dismissCenterPanel(self._refs.mainWrapper, function()
		self._isClosingMain = false
		if not self._isMainVisible then
			self._refs.root.Enabled = false
			self:_stopRotatingBackgrounds()
		end
	end, {
		enableBlur = true,
		blurName = "DonationUIBlur",
		enableZoom = true
	})
end

function DonationSystemUI:closeAll()
	self._isMainVisible = false
	self._isClosingMain = false
	self._selectedProduct = nil
	self._refs.mainWrapper.Visible = false
	self._refs.inputModal.Visible = false
	self._refs.messageBox.Text = ""
	if self._emojiPicker then
		self._emojiPicker.Visible = false
	end
	self._refs.root.Enabled = false
	self:_stopRotatingBackgrounds()
end

return DonationSystemUI
