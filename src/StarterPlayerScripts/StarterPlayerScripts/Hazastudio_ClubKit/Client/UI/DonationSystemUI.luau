--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local UIMotion = require(script.Parent.Parent.Utils.UIMotion)

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
	destroy: (self: DonationSystemUI) -> (),
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

-- The display setDisplayText actually paints. countTo and the transparency tweens resolve through
-- the same helper so a rolling number and its fade can never land on two different labels.
local function textDisplayOf(target: GuiObject?): GuiObject?
	if not target then
		return nil
	end
	if target:IsA("TextLabel") or target:IsA("TextButton") then
		return target
	end
	local childLabel = target:FindFirstChildWhichIsA("TextLabel", true)
		or target:FindFirstChildWhichIsA("TextButton", true)
	if childLabel and (childLabel:IsA("TextLabel") or childLabel:IsA("TextButton")) then
		return childLabel :: GuiObject
	end
	return nil
end

-- A button's centred icon: what pop/spin/wiggle target when the button itself sits in a layout.
-- Read at press time, after the button was bound, so it looks inside the UIMotionIconSlot the
-- icon tier may have moved the icon into — a direct lookup on the button then finds nothing.
local function iconOf(button: GuiObject?): GuiObject?
	if not button then
		return nil
	end
	local host = button:FindFirstChild("UIMotionIconSlot") or button
	return host:FindFirstChildWhichIsA("ImageLabel") or host:FindFirstChildWhichIsA("ImageButton")
end

local function setDisplayText(target: GuiObject?, text: string)
	local display = textDisplayOf(target)
	if display then
		(display :: any).Text = text
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
	-- The old build watched `TextChanged` and `FocusLost` and re-wrote the link on both.
	-- That machinery is what makes the box fragile for copying: it fires on the very input
	-- the player types to test or to copy, repositions the cursor, and — on some clients —
	-- releases keyboard focus (proven by isolating the handlers against a clean TextBox
	-- in a live playtest, 2026-09-24). The box's own text is set once here and again on
	-- every payload refresh (the refresh path sets `Text` via `applyExternalProviderText`),
	-- so nothing else is needed for the value to stay correct.
	textBox.Active = true
	textBox.Selectable = true
	textBox.TextEditable = true
	textBox.ClearTextOnFocus = false
	textBox.Text = getLink()

	-- Clicking the link box itself selects all of it once, so a player who wants the link
	-- without the copy button is one click away from Ctrl+A → Ctrl+C.
	textBox.Focused:Connect(function()
		focusAndSelectLink(textBox, getLink())
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
local TAB_INACTIVE_FADE = 0.3
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

-- countTo hands the format function a mid-roll float; a rank below 1 is "no rank yet".
local function rankDigits(value: number): string
	return DonationAmountFormat.formatRank(if value >= 1 then math.floor(value) else nil)
end

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
	-- Position is layout-safe here only because the pill is an absolutely-positioned overlay in
	-- the selector, a sibling of the tab-button container. If a layout ever owns it, the layout
	-- wins over Position anyway, so snap and skip the tween rather than fight it (ADR 0011).
	local pillParent = backgroundPill.Parent
	if pillParent and pillParent:FindFirstChildWhichIsA("UIGridStyleLayout") then
		backgroundPill.Position = targetPosition
		return
	end
	UIMotion.tween(
		backgroundPill,
		0.5,
		{ Position = targetPosition },
		Enum.EasingStyle.Quint,
		Enum.EasingDirection.Out
	)
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
	-- Calm center open (no Back overshoot) for floating donation subpanels.
	anim:presentCenterPanel((panel :: any) :: Frame)
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
	self._motionConnections = {} :: { RBXScriptConnection }
	-- Designed transparencies, captured once per instance so a re-open mid-fade cannot bake an
	-- intermediate value in as "designed". Strong keys on purpose (ADR 0011 addendum, 2026-09-17):
	-- a weak entry is dropped while the element is alive, which is exactly the mid-fade re-capture
	-- this table exists to prevent. Stat label refs are re-resolved at runtime; the elements live
	-- with the panel.
	self._fadeBases = {} :: { [GuiObject]: number }
	self._shownStats = {} :: { [string]: { value: number, display: GuiObject? } }
	self._shownTab = nil :: string?
	self._ctaPulseStop = nil :: (() -> ())?
	-- Copy-link button states: idle (the design's own label) → armed (link selected, "press Ctrl+C")
	-- → copied. Roblox gives games no clipboard access; the focused TextBox does the actual copy.
	self._copyConnections = {} :: { RBXScriptConnection }
	self._copyIdleText = nil :: string?
	self._copyArmed = false
	self._copyGeneration = 0
	-- Sticky-selection window: true while the copy hint is up because the copy button was
	-- pressed; a lost selection is then re-selected automatically (see _bindCopyFeedback).
	self._copyKeepSelection = false

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
	-- Default empty state until refreshProducts finishes (template never shown directly).
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
		-- Pool invoked as side effect (AvatarPrewarmShared.getPool()) when
		-- init state above — by then self._avatarPool already set. Defer
		-- showAvatar call to end of resumption cycle so self prewarm queue
		-- runs first, improving pool hit on second open.
		-- Client footprint: with LAZY_PANEL_ROWS the 3D model (~400 instances) loads on the
		-- first show() instead, so a player who never opens the panel never holds it.
		local localUserId = Players.LocalPlayer.UserId
		if require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config).ClientFootprint.LAZY_PANEL_ROWS ~= true then
			self._donationAvatarRequested = true
			task.defer(function()
				self:_showDonationAvatar(localUserId)
			end)
		end
	end

	refs.robuxTabButton.Activated:Connect(function()
		self:_setTab("robux")
	end)
	refs.saweriaTabButton.Activated:Connect(function()
		self:_setTab("saweria")
	end)
	refs.cancelButton.Activated:Connect(function()
		UIMotion.pop(iconOf(refs.cancelButton))
		self:_hideMessageModal(true)
	end)
	refs.continueButton.Activated:Connect(function()
		self:_confirmDonation()
	end)
	if refs.closeButton then
		refs.closeButton.Activated:Connect(function()
			UIMotion.pop(iconOf(refs.closeButton))
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
		self:_bindCopyFeedback()
	end
	if refs.addEmojiButton then
		self:_setupEmojiPicker(refs.addEmojiButton)
	end

	self:_bindButtonMotion(refs.robuxTabButton)
	self:_bindButtonMotion(refs.saweriaTabButton)
	self:_bindButtonMotion(refs.cancelButton)
	self:_bindButtonMotion(refs.continueButton)
	self:_bindButtonMotion(refs.closeButton)
	self:_bindButtonMotion(refs.copyLinkButton)
	self:_bindButtonMotion(refs.addEmojiButton)

	applyCashFeatureVisibility(refs, self._cashDonationEnabled)
	if not self._cashDonationEnabled then
		self._activeTab = "robux"
	end

	self:_setTab(self._activeTab)
	return self
end

-- ============================================================
-- Motion (ADR 0011 vocabulary only)
-- ============================================================

-- Press squash + hover lift. UIMotion refuses unsafe targets (laid-out buttons, CanvasGroup
-- descendants) and hands back an empty list, so these calls cost nothing where scale is illegal.
function DonationSystemUI:_bindButtonMotion(button: GuiObject?, into: { RBXScriptConnection }?)
	if button == nil then
		return
	end
	local sink = into or self._motionConnections
	for _, connection in ipairs(UIMotion.bindPress(button)) do
		table.insert(sink, connection)
	end
	for _, connection in ipairs(UIMotion.bindHover(button)) do
		table.insert(sink, connection)
	end
end

function DonationSystemUI:_fadeElements(elements: { GuiObject })
	if #elements == 0 then
		return
	end
	local pending: { GuiObject } = {}
	for _, element in ipairs(elements) do
		if self._fadeBases[element] == nil then
			table.insert(pending, element)
		end
	end
	if #pending > 0 then
		UIMotion.captureBases(pending, self._fadeBases)
	end
	UIMotion.fadeIn(elements, self._fadeBases)
end

-- Fades a revealed section's text/images back in. Capped: a long section must not take seconds.
function DonationSystemUI:_fadeSection(root: GuiObject, limit: number?)
	local elements: { GuiObject } = {}
	local cap = limit or 40
	for _, descendant in ipairs(root:GetDescendants()) do
		if
			descendant:IsA("ImageLabel")
			or descendant:IsA("ImageButton")
			or descendant:IsA("TextLabel")
			or descendant:IsA("TextButton")
			or descendant:IsA("TextBox")
		then
			table.insert(elements, descendant :: GuiObject)
			if #elements >= cap then
				break
			end
		end
	end
	self:_fadeElements(elements)
end

-- The incoming page slides in from the side of travel (UIMotion slides through the page's own
-- design padding, offset from its designed values) while its content fades in.
function DonationSystemUI:_revealPage(page: GuiObject, direction: number)
	UIMotion.slideIn(page, direction)
	self:_fadeSection(page)
end

-- Selection highlight: the gradient swap stays, but the inactive tab's label eases out instead
-- of snapping. The designed transparency is the active target, so a hidden label stays hidden.
function DonationSystemUI:_paintTabButton(button: TextButton, active: boolean)
	setTabButtonActive(button, active)
	local display: GuiObject = button
	if button.Text == "" then
		local label = button:FindFirstChildWhichIsA("TextLabel", true)
		if label then
			display = label :: GuiObject
		end
	end
	local base = self._fadeBases[display]
	if base == nil then
		base = (display :: any).TextTransparency
		self._fadeBases[display] = base
	end
	local target = if active then base else math.min(1, base + TAB_INACTIVE_FADE)
	if math.abs((display :: any).TextTransparency - target) < 0.001 then
		return
	end
	UIMotion.tween(display, 0.18, { TextTransparency = target })
end

-- One breathing loop per panel, on the confirm CTA, started only once the modal has finished
-- presenting (so `pulse` reads the resting value, not a mid-present one) and stopped on close.
function DonationSystemUI:_startCtaPulse()
	self:_stopCtaPulse()
	local button = self._refs.continueButton
	if not button.Parent then
		return
	end
	local stroke = button:FindFirstChildWhichIsA("UIStroke")
	if stroke then
		self._ctaPulseStop = UIMotion.pulse(stroke, "Transparency", math.min(1, stroke.Transparency + 0.55), 1.4)
	elseif button.BackgroundTransparency < 1 then
		self._ctaPulseStop =
			UIMotion.pulse(button, "BackgroundTransparency", math.min(0.9, button.BackgroundTransparency + 0.16), 1.6)
	end
end

function DonationSystemUI:_stopCtaPulse()
	if self._ctaPulseStop then
		self._ctaPulseStop()
		self._ctaPulseStop = nil
	end
end

-- Show 3D avatar in donation panel donor profile.
-- Same pool-or-thumbnail pattern as AvatarContextUI.showAvatar:
--   1. Try fetch model from prewarm pool (instant if hit).
--   2. On miss, show instant ImageLabel thumbnail (no YIELD).
--   3. Subscribe to pool.subscribeModelReady for seamless 3D upgrade.
--   4. Trigger pool.prewarmOnDemand so the next load is instant.
-- Without a fallback path, a race between pool init and viewport load()
-- will leave viewport empty forever (see investigation 2026-06-17).
function DonationSystemUI:_showDonationAvatar(userId: number)
	local viewport = self._refs.avatarViewport
	if not viewport then return end

	-- Clean up old subscription upgrade (if show() called twice).
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
		-- Same cursor gaze as the ACM, anywhere over the donation panel.
		self._avatarViewport3D:setGazeFollow(true, self._refs.mainWrapper)
	else
		self._avatarViewport3D:cleanup()
	end

	local success = self._avatarViewport3D:load(userId)
	if success then return end

	-- Pool miss: show instant ImageLabel thumbnail.
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
			-- Guard: viewport still alive & visible (panel may have been closed
			-- or the GUI was destroyed while loading).
			if not viewport.Parent or not viewport.Visible then return end
			if not self._avatarViewport3D then
				self._avatarViewport3D = AvatarViewport3D.new(viewport)
				self._avatarViewport3D:setPrewarmPool(self._avatarPool)
				self._avatarViewport3D:setGazeFollow(true, self._refs.mainWrapper)
			else
				self._avatarViewport3D:cleanup()
			end
			local reloaded = self._avatarViewport3D:load(userId)
			if reloaded and self._avatarThumbnail then
				self._avatarThumbnail.Visible = false
			end
		end)
	end

	-- Trigger background prewarm so the next click is instant.
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

	-- Slide only on a real switch inside an open panel; opening plays the panel pop instead, and
	-- show() re-asserts the current tab on every open (unchanged repaint must not re-animate).
	local previousTab = self._shownTab
	self._shownTab = tabName
	if previousTab ~= nil and previousTab ~= tabName and self._refs.mainWrapper.Visible then
		self:_revealPage(activeFrame, if isRobux then -1 else 1)
	end

	self:_paintTabButton(self._refs.robuxTabButton, isRobux)
	self:_paintTabButton(self._refs.saweriaTabButton, not isRobux)

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
	local continueText = self._refs.continueText
	if continueText then
		-- Fresh user action every time the modal opens, so the price is free to roll up.
		UIMotion.countTo(continueText, 0, product.price, nil, function(value: number): string
			return ("Continue donate - %s Robux"):format(formatRobux(value))
		end)
	end

	if self._emojiPicker then
		self._emojiPicker.Visible = false
	end

	local function showInputModal()
		self._anim:presentCenterPanel(self._refs.inputModal, function()
			self._refs.messageBox:CaptureFocus()
			self:_startCtaPulse()
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
	self:_stopCtaPulse()
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
		-- Nothing selected: the press is refused, so say so instead of dying silently.
		UIMotion.wiggle(self._refs.continueButton, 6)
		return
	end
	UIMotion.pop(iconOf(self._refs.continueButton))

	local message = trim(self._refs.messageBox.Text)
	message = truncateUtf8(message, Config.Donation.ROBUX_MESSAGE_MAX_LENGTH)

	self:_hideMessageModal(false)
	if self._donateRequested then
		self._donateRequested(product, message)
	end
end

local COPY_HINT_KEYBOARD = "Press Ctrl+C / Cmd+C"
local COPY_HINT_TOUCH = "Hold the link, then tap Copy"
local COPY_DONE = "Copied ✓"
local COPY_DONE_SECONDS = 2
local COPY_MODIFIERS = {
	Enum.KeyCode.LeftControl,
	Enum.KeyCode.RightControl,
	Enum.KeyCode.LeftSuper,
	Enum.KeyCode.RightSuper,
	Enum.KeyCode.LeftMeta,
	Enum.KeyCode.RightMeta,
}

local function copyModifierDown(): boolean
	for _, key in ipairs(COPY_MODIFIERS) do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

function DonationSystemUI:_setCopyLabel(text: string)
	-- The design's words live in the button's child TextLabel (the button's own Text is empty);
	-- textDisplayOf would return the TextButton itself and paint a second, overlapping line.
	local button = self._refs.copyLinkButton
	if not button then
		return
	end
	local display: GuiObject = button:FindFirstChildWhichIsA("TextLabel", true) or button
	if self._copyIdleText == nil then
		self._copyIdleText = (display :: any).Text
	end
	(display :: any).Text = text
end

function DonationSystemUI:_resetCopyLabel()
	self._copyArmed = false
	self._copyGeneration += 1
	if self._copyIdleText ~= nil then
		self:_setCopyLabel(self._copyIdleText)
	end
end

-- The link is selected and focused: tell the player the one key press that copies it (a phone
-- has no keyboard, so its hint is the system's own long-press Copy).
function DonationSystemUI:_armCopy()
	self._copyArmed = true
	self._copyGeneration += 1
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	self:_setCopyLabel(if touchOnly then COPY_HINT_TOUCH else COPY_HINT_KEYBOARD)
end

function DonationSystemUI:_markCopied()
	self._copyArmed = false
	self._copyGeneration += 1
	local generation = self._copyGeneration
	self:_setCopyLabel(COPY_DONE)
	UIMotion.pop(iconOf(self._refs.copyLinkButton))
	task.delay(COPY_DONE_SECONDS, function()
		if self._copyGeneration == generation and self._copyIdleText ~= nil then
			self:_setCopyLabel(self._copyIdleText)
		end
	end)
end

function DonationSystemUI:_bindCopyFeedback()
	local linkBox = self._refs.saweriaLink
	if not linkBox then
		return
	end
	local connections = self._copyConnections
	-- Clicking the link box itself selects it too, so it arms the same hint.
	table.insert(connections, linkBox.Focused:Connect(function()
		if not self._copyArmed then
			self:_armCopy()
		end
	end))
	-- Sticky selection (production hardening of the copy flow): the player presses the copy
	-- button, reads "press Ctrl+C", presses Ctrl — and the selection is gone. Something can
	-- take the TextBox's keyboard focus straight back with no input event at all (a Studio
	-- plugin does it here; a busy server could in-game), and losing focus clears the
	-- selection. While the copy hint is armed, a lost selection is re-selected automatically
	-- (bounded, and stopped by any real mouse press — the player clicking elsewhere means
	-- they moved on).
	self._copyKeepSelection = false
	table.insert(connections, linkBox:GetPropertyChangedSignal("SelectionStart"):Connect(function()
		if
			self._copyKeepSelection
			and self._copyArmed
			and linkBox.SelectionStart < 0
			and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
		then
			task.defer(function()
				if self._copyKeepSelection and self._copyArmed and linkBox.SelectionStart < 0 then
					focusAndSelectLink(linkBox, getExternalProviderLink())
				end
			end)
		end
	end))
	table.insert(connections, linkBox.Focused:Connect(function()
		if not self._copyArmed then
			self:_armCopy()
		end
	end))
	-- A real mouse press anywhere ends the sticky-selection window.
	table.insert(connections, UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self._copyKeepSelection = false
		end

		-- The key press still reaches InputBegan while the TextBox has focus
		-- (gameProcessed = true); the TextBox has already copied its selection by then.
		if self._copyArmed and input.KeyCode == Enum.KeyCode.C and copyModifierDown() and linkBox:IsFocused() then
			self:_markCopied()
			self._copyKeepSelection = false
		end
	end))
	-- Leaving without copying puts the design's label back.
	table.insert(connections, linkBox.FocusLost:Connect(function()
		if self._copyArmed then
			self:_resetCopyLabel()
		end
	end))
end

function DonationSystemUI:_handleCopySaweriaLink()
	UIMotion.spin(iconOf(self._refs.copyLinkButton))
	if self._refs.saweriaLink then
		-- Deferred past the click (a CaptureFocus inside the button's own Activated handler
		-- races the engine's focus handling). The sticky-selection watcher in
		-- _bindCopyFeedback keeps the selection alive afterwards: something (a Studio
		-- plugin; a busy client in-game) can take keyboard focus back with no input event
		-- at all, and losing focus clears the selection — so while the hint is up, a lost
		-- selection is re-selected automatically until the player clicks elsewhere or
		-- copies.
		task.defer(function()
			local linkBox = self._refs.saweriaLink
			if not linkBox then
				return
			end
			focusAndSelectLink(linkBox, getExternalProviderLink())
			self:_armCopy()
			self._copyKeepSelection = true
		end)
	end
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

	-- Freshly cloned cards carry the template's designed transparencies, so bases are correct
	-- every time and the table is replaced wholesale (no reference kept to a destroyed card).
	local cards: { GuiObject } = {}
	local cardFadeTargets: { GuiObject } = {}

	if hasProducts and template then
		for index, product in ipairs(configuredProducts) do
			local card = template:Clone()
			card.Name = "DonationProduct_" .. product.key
			card:SetAttribute("DonationRuntimeCard", true)
			card.LayoutOrder = template.LayoutOrder + index
			card.Visible = true
			card.Parent = refs.robuxScroll

			table.insert(cards, card)
			for _, descendant in ipairs(card:GetDescendants()) do
				if descendant:IsA("GuiObject") then
					table.insert(cardFadeTargets, descendant)
				end
			end

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
				local cardButton = donationButton :: TextButton
				table.insert(
					self._productConnections,
					cardButton.Activated:Connect(function()
						UIMotion.pop(iconOf(cardButton))
						self:_showMessageModal(product)
					end)
				)
				self:_bindButtonMotion(cardButton, self._productConnections)
			else
				table.insert(
					self._productConnections,
					card.Activated:Connect(function()
						UIMotion.pop(iconOf(card))
						self:_showMessageModal(product)
					end)
				)
			end
			-- The card is a button in its own right and is what the finger actually lands on; the
			-- inner DonationButton has no scalable target of its own, so without this the whole
			-- product tile stayed dead. UIMotion never picks a target inside a nested button, so
			-- the two binds cannot fight over one UIScale. Per-render connections, dropped above.
			self:_bindButtonMotion(card, self._productConnections)
		end
	end

	if #cards > 0 then
		UIMotion.stagger(cards, UIMotion.captureBases(cardFadeTargets), 0.035, 10)
	end

	if notFoundCard then
		local showNotFound = not hasProducts
		if notFoundCard.Visible ~= showNotFound then
			notFoundCard.Visible = showNotFound
			if showNotFound then
				self:_fadeSection(notFoundCard, 12)
			end
		end
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

		-- ~90 emoji cells: a pop on the picked glyph costs one tween, while bindPress/bindHover
		-- here would mean hundreds of live connections (one of them on UserInputService) for a
		-- grid child that UIMotion cannot scale anyway.
		table.insert(
			self._emojiConnections,
			button.MouseButton1Click:Connect(function()
				UIMotion.pop(if label then label :: GuiObject else button)
				self:_appendMessageEmoji(emoji)
				picker.Visible = false
			end)
		)
	end

	if self._refs.emojiCloseButton then
		local closeButton = self._refs.emojiCloseButton
		table.insert(
			self._emojiConnections,
			closeButton.Activated:Connect(function()
				UIMotion.pop(iconOf(closeButton))
				picker.Visible = false
			end)
		)
		self:_bindButtonMotion(closeButton, self._emojiConnections)
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
	local accepted = truncateUtf8(nextText, Config.Donation.ROBUX_MESSAGE_MAX_LENGTH)
	if accepted ~= nextText then
		-- Message already at the limit: the emoji got cut, so refuse it visibly.
		UIMotion.wiggle(self._refs.messageBox, 5)
	end
	self._refs.messageBox.Text = accepted
	self._refs.messageBox.CursorPosition = -1
end

function DonationSystemUI:setDonationResult(ok: boolean, message: string?)
	if not ok and self._refs.mainWrapper.Visible then
		-- Rotation never touches layout, so the whole panel can shake safely (ADR 0011).
		UIMotion.wiggle(self._refs.mainWrapper, 2.5)
	end
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
	if refs.displayNameLabel and refs.displayNameLabel.Text ~= displayName then
		refs.displayNameLabel.Text = displayName
	end
	if refs.usernameLabel then
		local username = tostring(data.username or "")
		local usernameText = if username ~= "" then "@" .. username else ""
		if refs.usernameLabel.Text ~= usernameText then
			refs.usernameLabel.Text = usernameText
		end
	end
	self:_paintStat(refs.robuxRankLabel, "robuxRank", tonumber(data.robuxRank) or -1, rankDigits)
	self:_paintStat(
		refs.robuxValueLabel,
		"robuxTotal",
		tonumber(data.robuxTotal) or 0,
		DonationAmountFormat.formatCompact
	)
	if self._cashDonationEnabled then
		self:_paintStat(refs.saweriaRankLabel, "cashRank", tonumber(data.cashRank) or -1, rankDigits)
		self:_paintStat(
			refs.saweriaValueLabel,
			"cashTotal",
			tonumber(data.cashTotal) or 0,
			DonationAmountFormat.formatCompact
		)
	end
end

-- The server echoes the whole leaderboard payload on every push, so this runs dozens of times a
-- minute with identical numbers (the 2026-09-02 repaint storm). Only a real change is painted,
-- and only an open panel rolls the digits — a closed one just takes the value.
function DonationSystemUI:_paintStat(target: GuiObject?, key: string, value: number, format: (number) -> string)
	local display = textDisplayOf(target)
	local previous = self._shownStats[key]
	if previous ~= nil and previous.value == value and previous.display == display then
		return
	end
	if display == nil then
		return
	end
	local rollFrom = if previous ~= nil and previous.display == display and previous.value >= 0 and value >= 0
		then previous.value
		else nil
	self._shownStats[key] = { value = value, display = display }
	if rollFrom ~= nil and self._refs.mainWrapper.Visible then
		UIMotion.countTo(display :: any, rollFrom, value, nil, format)
		return
	end
	(display :: any).Text = format(value)
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
	if self._refs.avatarViewport and not self._donationAvatarRequested then
		self._donationAvatarRequested = true
		self:_showDonationAvatar(Players.LocalPlayer.UserId)
	end
	self:_playEntrance()
	if self._profileRefreshHandler then
		self:refreshDonorProfile(self._profileRefreshHandler)
	end
	if self._productRefreshHandler then
		self:refreshProducts(self._productRefreshHandler)
	end
	self:_setTab(self._activeTab)
	-- Re-trigger avatar load on each open. If pool already ready, 3D
	-- show instantly; if not yet (e.g. opened before pool prewarm finishes
	-- on first boot), fallback thumbnail + seamless upgrade subscribe.
	if self._refs.avatarViewport then
		self:_showDonationAvatar(Players.LocalPlayer.UserId)
		-- No-op unless the viewport is centred and outside any layout/CanvasGroup (canScale).
		UIMotion.popIn(self._refs.avatarViewport, 0.82)
	end
end

-- Panel open: donor identity and stat chips fade back in behind the AnimationHelper pop.
function DonationSystemUI:_playEntrance()
	local refs = self._refs
	local elements: { GuiObject } = {}
	local function add(candidate: GuiObject?)
		if candidate then
			table.insert(elements, candidate)
		end
	end
	add(refs.displayNameLabel)
	add(refs.usernameLabel)
	add(refs.robuxRankLabel)
	add(refs.robuxValueLabel)
	if self._cashDonationEnabled then
		add(refs.saweriaRankLabel)
		add(refs.saweriaValueLabel)
	end
	self:_fadeElements(elements)
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
	self:_stopCtaPulse()
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
	self:_stopCtaPulse()
	self._refs.mainWrapper.Visible = false
	self._refs.inputModal.Visible = false
	self._refs.messageBox.Text = ""
	if self._emojiPicker then
		self._emojiPicker.Visible = false
	end
	self._refs.root.Enabled = false
	self:_stopRotatingBackgrounds()
end

-- Single teardown for everything this panel owns. Nothing calls it today (the controller keeps
-- one UI for the session), but every motion connection and the CTA loop land here rather than
-- leaking if a caller ever does.
function DonationSystemUI:destroy()
	self:closeAll()
	for _, connections in
		ipairs({
			self._motionConnections,
			self._productConnections,
			self._emojiConnections,
			self._copyConnections,
		} :: { { RBXScriptConnection } })
	do
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
	end
end

return DonationSystemUI
