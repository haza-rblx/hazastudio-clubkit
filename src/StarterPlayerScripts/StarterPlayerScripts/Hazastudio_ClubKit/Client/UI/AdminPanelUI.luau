--!strict
-- Display adapter for 04-AdminPanelv2 (title color preset + font + size).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local TitleStyleDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.TitleStyleDomain)
local TitleFontUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.TitleFontUtil)
local TitleColorPreset = require(ReplicatedStorage.Hazastudio_ClubKit.OverheadEffects.TitleColorPreset)
local AnimationModes = TitleColorPreset.AnimationModes
local SpecialTitleRenderer = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.SpecialTitleRenderer)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)

type PlayerData = {
	userId: number,
	displayName: string,
	username: string,
}

type PlayerListEntry = {
	button: TextButton,
	connection: RBXScriptConnection?,
}

export type TitleEditorSnapshot = {
	specialTitle: string?,
	specialTitlePreset: string?,
	specialTitleFont: string?,
	specialTitleSize: string?,
}

local SEARCH_HIGHLIGHT_COLOR = "#FF7EB6"
local EMPTY_STATE_DEFAULT_TITLE = "No one is waiting for a custom title"
local EMPTY_STATE_DEFAULT_SUBTITLE = "Pick a player when someone else joins the room."
local EMPTY_STATE_SEARCH_TITLE = "No match this time"
local EMPTY_STATE_SEARCH_SUBTITLE = "Try another display name or username."
local FLOATING_PANEL_ZINDEX = 120
local AVATAR_PREVIEW_ZINDEX = 500
local PREVIEW_SAMPLE_TEXT = "PREVIEW"
local PRESET_CARD_SPEED = Config.Admin.TITLE_PRESET_CARD_SPEED or 0.55
local PRESET_CARD_SIZE = Config.Admin.TITLE_PRESET_SIZE or 1.5

local SAFE_EMOJIS = {
	"😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "😊", "😇",
	"🙂", "🙃", "😉", "😍", "😘", "😎", "🤩", "🥳", "😜", "😋",
	"🤗", "🤔", "😴", "😈", "👑", "💎", "🔥", "✨", "🌟", "⭐",
	"💫", "⚡", "💥", "💯", "🎉", "🎊", "🎀", "🎁", "🏆", "🥇",
	"🥈", "🥉", "🎵", "🎶", "🎧", "🎤", "💃", "🕺", "❤️", "🧡",
	"💛", "💚", "💙", "💜", "🤍", "🖤", "💕", "💞", "💓", "💗",
	"💖", "💘", "💝", "💟", "🌹", "🌺", "🌸", "🌼", "🌻", "🍀",
	"🌈", "☀️", "🌙", "☁️", "🌊", "🍓", "🍒", "🍑", "🍭", "🍬",
	"🍼", "🧸", "🎮", "🕹️", "🚀", "🛸", "🏝️", "🏖️", "💼", "🛡️",
	"⚔️", "🗡️", "🔮", "🪄", "📌", "✅",
}

local AdminPanelUI = {} :: any
AdminPanelUI.__index = AdminPanelUI

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
	return string.format(
		'%s<font color="%s"><b>%s</b></font>%s',
		escapeRichText(string.sub(text, 1, startIndex - 1)),
		SEARCH_HIGHLIGHT_COLOR,
		escapeRichText(string.sub(text, startIndex, endIndex)),
		escapeRichText(string.sub(text, endIndex + 1))
	)
end

local function trim(text: string): string
	return string.gsub(text, "^%s*(.-)%s*$", "%1")
end

local function resolveTitleSize(sizeKey: string?): string
	if type(sizeKey) == "string" and TitleStyleDomain.isValidTitleSize(sizeKey) then
		return sizeKey
	end
	return "M"
end

local function resolveTitleFont(fontName: string?): string
	return TitleFontUtil.resolveName(fontName)
end

local function resolveTitlePreset(presetMode: string?): string
	if type(presetMode) == "string" and presetMode ~= "" and AnimationModes.IsPreset(presetMode) then
		return presetMode
	end
	local presets = AnimationModes.GetPresetModes()
	return presets[1] or "Rainbow"
end

local function applyTitleFontToLabel(label: TextLabel, fontName: string)
	TitleFontUtil.applyToTextLabel(label, fontName)
end

local function resolveFontStateTemplates(fontFrame: Instance): (TextButton?, TextButton?)
	local normal = fontFrame:FindFirstChild("NormalState")
	local selected = fontFrame:FindFirstChild("SelectedlState") or fontFrame:FindFirstChild("SelectedState")
	local normalButton = if normal and normal:IsA("TextButton") then normal else nil
	local selectedButton = if selected and selected:IsA("TextButton") then selected else nil
	return normalButton, selectedButton
end

local function syncScrollCanvas(scroll: ScrollingFrame)
	local layout = scroll:FindFirstChildWhichIsA("UIListLayout")
	if not layout then
		return
	end
	scroll.CanvasSize = UDim2.fromOffset(layout.AbsoluteContentSize.X, layout.AbsoluteContentSize.Y)
end

local function getThumbnail(userId: number): string
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=100&h=100", userId)
end

local function setNotFoundCardText(card: TextButton, titleText: string, subtitleText: string)
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

local function findDescendant(root: Instance?, name: string, className: string?): Instance?
	if not root then
		return nil
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Name == name and (not className or descendant.ClassName == className) then
			return descendant
		end
	end
	return nil
end

local function getPointerPosition(): Vector2
	local mouse = UserInputService:GetMouseLocation()
	return Vector2.new(mouse.X, mouse.Y)
end

local function inputPosition(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y)
end

local function setButtonSelected(button: GuiButton?, selected: boolean)
	if not button then
		return
	end
	button.Visible = true
	button.BackgroundTransparency = selected and 0 or 0.95

	if button:IsA("ImageButton") then
		local stroke = button:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			stroke.Transparency = selected and 0 or 0.5
		end
		return
	end

	local textButton = button :: TextButton
	local contentColor = selected and Color3.fromRGB(12, 12, 12) or Color3.fromRGB(255, 255, 255)
	textButton.TextColor3 = contentColor
	for _, child in ipairs(textButton:GetDescendants()) do
		if child:IsA("TextLabel") then
			child.TextColor3 = contentColor
		elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
			(child :: ImageLabel).ImageColor3 = contentColor
		end
	end
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

local function getScreenScale(screenGui: ScreenGui): number
	local uiScale = screenGui:FindFirstChildWhichIsA("UIScale")
	if uiScale then
		return math.max(uiScale.Scale, 0.01)
	end
	return 1
end

local function clampPanelPosition(panel: GuiObject, screenGui: ScreenGui, position: UDim2): UDim2
	local scale = getScreenScale(screenGui)
	local screenSize = screenGui.AbsoluteSize / scale
	local panelSize = panel.AbsoluteSize / scale
	local anchor = panel.AnchorPoint
	local x = position.X.Scale * screenSize.X + position.X.Offset
	local y = position.Y.Scale * screenSize.Y + position.Y.Offset
	local minX = 8 + panelSize.X * anchor.X
	local minY = 8 + panelSize.Y * anchor.Y
	local maxX = math.max(minX, screenSize.X - 8 - panelSize.X * (1 - anchor.X))
	local maxY = math.max(minY, screenSize.Y - 8 - panelSize.Y * (1 - anchor.Y))
	return UDim2.fromOffset(math.clamp(x, minX, maxX), math.clamp(y, minY, maxY))
end

local function setSiblingDragDetectorsEnabled(screenGui: ScreenGui, activePanel: GuiObject, enabled: boolean)
	for _, descendant in ipairs(screenGui:GetDescendants()) do
		if descendant:IsA("UIDragDetector") and not descendant:IsDescendantOf(activePanel) then
			descendant.Enabled = enabled
		end
	end
end

local function bindDraggablePanel(
	panel: GuiObject,
	handle: GuiObject?,
	screenGui: ScreenGui,
	exclusive: boolean?
): { RBXScriptConnection }
	local connections = {}
	local dragging = false
	local dragInputType: Enum.UserInputType? = nil
	local dragStart = Vector2.zero
	local startPosition = panel.Position
	local dragHandle = handle or panel
	dragHandle.Active = true
	table.insert(
		connections,
		dragHandle.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			dragging = true
			dragInputType = input.UserInputType
			dragStart = inputPosition(input)
			startPosition = panel.Position
			if exclusive then
				setSiblingDragDetectorsEnabled(screenGui, panel, false)
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if not dragging then
				return
			end
			if dragInputType == Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.MouseMovement then
				return
			end
			if dragInputType == Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			local delta = (inputPosition(input) - dragStart) / getScreenScale(screenGui)
			panel.Position = clampPanelPosition(
				panel,
				screenGui,
				UDim2.new(
					startPosition.X.Scale,
					startPosition.X.Offset + delta.X,
					startPosition.Y.Scale,
					startPosition.Y.Offset + delta.Y
				)
			)
		end)
	)
	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == dragInputType then
				dragging = false
				dragInputType = nil
				if exclusive then
					setSiblingDragDetectorsEnabled(screenGui, panel, true)
				end
			end
		end)
	)
	return connections
end

local function makeFloatingPanelInputOpaque(panel: GuiObject)
	panel.Active = true
	panel.ZIndex = math.max(panel.ZIndex, FLOATING_PANEL_ZINDEX)
	for _, descendant in ipairs(panel:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.Active = true
			descendant.ZIndex = math.max(descendant.ZIndex, FLOATING_PANEL_ZINDEX + 1)
		end
	end
end

local function popOpen(anim: AnimationHelper.AnimationHelper, panel: GuiObject)
	makeFloatingPanelInputOpaque(panel)
	anim:scalePop((panel :: any) :: Frame, nil)
end

local function resolvePreviewLabel(host: GuiObject): TextLabel?
	local label = host:FindFirstChildWhichIsA("TextLabel", true)
	return if label and label:IsA("TextLabel") then label else nil
end

function AdminPanelUI.new(gui: ScreenGui)
	local self = setmetatable({}, AdminPanelUI) :: any

	local mainWrapper = gui:WaitForChild("MainWrapper") :: Frame
	local headerWrapper = mainWrapper:WaitForChild("01-HeaderWrapper") :: Frame
	local selector = headerWrapper:WaitForChild("2-Selector") :: Frame
	local contentWrapper = mainWrapper:WaitForChild("02-MainContentWrapper") :: CanvasGroup
	local selectFrame = contentWrapper:WaitForChild("1-SelectPlayerFrame") :: Frame
	local inputTitleFrame = contentWrapper:WaitForChild("2-InputTitle") :: Frame

	local searchBox = selectFrame:WaitForChild("02-SearchBox") :: TextBox
	local scrollCanvas = selectFrame:WaitForChild("CanvasGroup") :: CanvasGroup
	local scrollFrame = scrollCanvas:WaitForChild("ScrollablePlayerList") :: ScrollingFrame
	local playerTemplate = scrollFrame:WaitForChild("PlayerSelectorCard") :: TextButton
	local notFoundCard = scrollFrame:WaitForChild("NotFoundCard") :: TextButton

	local inputCanvas = inputTitleFrame:WaitForChild("CanvasGroup") :: CanvasGroup
	local inputScroll = inputCanvas:WaitForChild("01-ScrollingFrame") :: ScrollingFrame
	local selectedPlayerInfo = inputScroll:WaitForChild("SelectedPlayerInfo") :: Frame
	local selectPlayerFirstInfo = inputScroll:WaitForChild("SelectPlayerFirstInfo") :: Frame
	local targetInfoWrapper = selectedPlayerInfo:WaitForChild("TargetInfoWrapper") :: Frame
	local playerInfo = targetInfoWrapper:WaitForChild("1-PlayerInformation") :: Frame
	local buttonGroup = targetInfoWrapper:WaitForChild("2-ButtonGroup") :: CanvasGroup
	local deleteTitleButton = buttonGroup:WaitForChild("DeleteTitleButton") :: ImageButton
	local selectedUsernameLabel = playerInfo:WaitForChild("1-SubTitle") :: TextLabel
	local selectedNameLabel = playerInfo:WaitForChild("1-Title") :: TextLabel
	local selectedCurrentTitleLabel = playerInfo:WaitForChild("3-CurrentTitle") :: TextLabel
	local selectedProfilePicture = selectedPlayerInfo:WaitForChild("TargetProfilePicture") :: ImageLabel

	local inputTitleWrapper = inputScroll:WaitForChild("InputTitleWrapper") :: Frame
	local titleInput = inputTitleWrapper:WaitForChild("02-InputCustomTitle") :: TextBox
	local addEmojiButton = titleInput:WaitForChild("AddEmojiButton") :: TextButton

	local selectSizeRoot = inputScroll:WaitForChild("SelectSize") :: Frame
	local sizeFrame = selectSizeRoot:WaitForChild("02-SelectSizeInput") :: Frame
	local sizeNormal = sizeFrame:WaitForChild("NormalState") :: TextButton
	local sizeSelected = sizeFrame:WaitForChild("SelectedState") :: TextButton

	local selectStyleRoot = inputScroll:WaitForChild("SelectStyle") :: Frame
	local presetInput = selectStyleRoot:WaitForChild("02-SelectPresetInput") :: Frame
	local presetTemplate = presetInput:WaitForChild("Template") :: ImageButton

	local selectFontRoot = inputScroll:WaitForChild("SelectFontStyle") :: Frame
	local fontFrame = selectFontRoot:WaitForChild("02-SelectFontSize") :: ScrollingFrame
	local fontNormal, fontSelected = resolveFontStateTemplates(fontFrame)

	local overlayWrapper = inputTitleFrame:WaitForChild("OverlayWrapper") :: CanvasGroup
	local saveTitleButton = overlayWrapper:WaitForChild("SaveButton") :: ImageButton
	local closeButton = headerWrapper:WaitForChild("3-CloseModalButton") :: TextButton

	local emojiPicker = gui:WaitForChild("EmojiPicker") :: CanvasGroup
	local emojiDragHandle = emojiPicker:FindFirstChild("DraggableIcon") :: GuiObject?
	local emojiList = emojiPicker:WaitForChild("EmojiList") :: ScrollingFrame
	local emojiTemplate = emojiList:WaitForChild("EmojiButtonTemplate") :: TextButton
	local emojiCloseButton = emojiPicker:WaitForChild("CloseModalButton") :: TextButton

	local avatarPreview = gui:WaitForChild("AvatarPreview") :: Frame
	local illustrationSection = avatarPreview:FindFirstChild("IllustrationSection")
	local overheadPreviewHost: GuiObject = if illustrationSection and illustrationSection:IsA("GuiObject")
		then illustrationSection :: GuiObject
		else avatarPreview
	local viewport = overheadPreviewHost:FindFirstChildWhichIsA("ViewportFrame", true)
		or avatarPreview:FindFirstChildWhichIsA("ViewportFrame", true)
	if viewport and viewport:IsA("ViewportFrame") then
		viewport.Visible = false
	end

	local inputBlocker = Instance.new("Frame")
	inputBlocker.Name = "RuntimeInputBlocker"
	inputBlocker.Size = UDim2.fromScale(1, 1)
	inputBlocker.BackgroundTransparency = 1
	inputBlocker.Active = true
	inputBlocker.ZIndex = AVATAR_PREVIEW_ZINDEX - 2
	inputBlocker.Parent = avatarPreview

	local avatarDragStrip = Instance.new("Frame")
	avatarDragStrip.Name = "RuntimeDragStrip"
	avatarDragStrip.Size = UDim2.new(1, 0, 0, 44)
	avatarDragStrip.BackgroundTransparency = 1
	avatarDragStrip.ZIndex = AVATAR_PREVIEW_ZINDEX - 1
	avatarDragStrip.Active = true
	avatarDragStrip.Parent = avatarPreview

	local mainDragDetector = mainWrapper:FindFirstChildWhichIsA("UIDragDetector")

	self._gui = gui
	self._mainWrapper = mainWrapper
	self._selector = selector
	self._inputTitleFrame = inputTitleFrame
	self._searchBox = searchBox
	self._scrollFrame = scrollFrame
	self._playerTemplate = playerTemplate
	self._notFoundCard = notFoundCard
	self._selectedPlayerInfo = selectedPlayerInfo
	self._selectPlayerFirstInfo = selectPlayerFirstInfo
	self._selectedNameLabel = selectedNameLabel
	self._selectedUsernameLabel = selectedUsernameLabel
	self._selectedCurrentTitleLabel = selectedCurrentTitleLabel
	self._selectedProfilePicture = selectedProfilePicture
	self._buttonGroup = buttonGroup
	self._deleteTitleButton = deleteTitleButton
	self._titleInput = titleInput
	self._addEmojiButton = addEmojiButton
	self._sizeFrame = sizeFrame
	self._sizeNormal = sizeNormal
	self._sizeSelected = sizeSelected
	self._sizeButtons = {} :: { [string]: TextButton }
	self._presetInput = presetInput
	self._presetTemplate = presetTemplate
	self._presetButtons = {} :: { ImageButton }
	self._presetCardEffects = {} :: { [ImageButton]: any }
	self._fontFrame = fontFrame
	self._fontNormal = fontNormal
	self._fontSelected = fontSelected
	self._fontButtons = {} :: { [string]: TextButton }
	self._saveTitleButton = saveTitleButton
	self._closeButton = closeButton
	self._emojiPicker = emojiPicker
	self._emojiList = emojiList
	self._emojiTemplate = emojiTemplate
	self._emojiCloseButton = emojiCloseButton
	self._avatarPreview = avatarPreview
	self._overheadPreviewHost = overheadPreviewHost
	self._viewport = if viewport and viewport:IsA("ViewportFrame") then viewport :: ViewportFrame else nil
	self._mainDragDetector = if mainDragDetector and mainDragDetector:IsA("UIDragDetector") then mainDragDetector else nil
	self._mainDragDetectorDefaultEnabled = if self._mainDragDetector then self._mainDragDetector.Enabled else true
	self._previewUserId = nil :: number?
	self._previewOverlayRow = nil :: Frame?

	self._activeTab = "GiveTitle"
	self._anim = AnimationHelper.new()
	self._allPlayers = {} :: { PlayerData }
	self._playerCardPool = {} :: { PlayerListEntry }
	self._selectedPlayer = nil :: PlayerData?
	self._currentTitleSnapshot = nil :: TitleEditorSnapshot?
	self._selectedSize = "M"
	self._selectedPresetMode = AnimationModes.GetPresetModes()[1] or "Rainbow"
	self._selectedFont = TitleFontUtil.getBoldestConfiguredFont()
	self._onPlayerSelected = nil :: ((PlayerData) -> ())?
	self._onPlayerDeselected = nil :: (() -> ())?
	self._previewConnections = {} :: { RBXScriptConnection }
	self._emojiConnections = {} :: { RBXScriptConnection }
	self._panelDragConnections = {} :: { RBXScriptConnection }

	gui.Enabled = false
	mainWrapper.Visible = false
	emojiPicker.Visible = false
	avatarPreview.Visible = false
	makeFloatingPanelInputOpaque(emojiPicker)
	makeFloatingPanelInputOpaque(avatarPreview)
	playerTemplate.Visible = false
	notFoundCard.Visible = false
	sizeNormal.Visible = false
	sizeSelected.Visible = false
	if fontNormal then
		fontNormal.Visible = false
	end
	if fontSelected then
		fontSelected.Visible = false
	end
	local fontLayout = fontFrame:FindFirstChildWhichIsA("UIListLayout")
	if fontLayout then
		fontLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			syncScrollCanvas(fontFrame)
		end)
	end
	presetTemplate.Visible = false
	emojiTemplate.Visible = false

	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		self:_applyPlayerSearch()
	end)
	titleInput:GetPropertyChangedSignal("Text"):Connect(function()
		self:_syncRealtimePreview()
	end)
	addEmojiButton.MouseButton1Click:Connect(function()
		self:_openEmojiPicker(getPointerPosition())
	end)
	emojiCloseButton.MouseButton1Click:Connect(function()
		emojiPicker.Visible = false
	end)

	self:_populateEmojiButtons()
	self:_renderSizeOptions()
	self:_renderFontOptions()
	self:_populatePresetCards()
	self:_setSelectedPlayerInfo(nil, nil)

	for _, connection in ipairs(bindDraggablePanel(mainWrapper, headerWrapper, gui, false)) do
		table.insert(self._panelDragConnections, connection)
	end
	do
		local emojiHandle: GuiObject = (emojiDragHandle or emojiPicker) :: GuiObject
		for _, connection in ipairs(bindDraggablePanel(emojiPicker, emojiHandle, gui, true)) do
			table.insert(self._panelDragConnections, connection)
		end
	end
	for _, connection in ipairs(bindDraggablePanel(avatarPreview, avatarDragStrip, gui, true)) do
		table.insert(self._panelDragConnections, connection)
	end

	return self
end

function AdminPanelUI:_destroyPresetCardEffects()
	for button, effect in pairs(self._presetCardEffects) do
		if effect then
			pcall(function()
				effect:Destroy()
			end)
		end
		self._presetCardEffects[button] = nil
	end
end

function AdminPanelUI:_applyPresetCardPreview(button: ImageButton, presetMode: string)
	local existing = self._presetCardEffects[button]
	if existing then
		pcall(function()
			existing:Destroy()
		end)
		self._presetCardEffects[button] = nil
	end

	local label = resolvePreviewLabel(button)
	if not label then
		label = Instance.new("TextLabel")
		label.Name = "PresetPreviewLabel"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.TextScaled = true
		label.Text = PREVIEW_SAMPLE_TEXT
		label.Parent = button
	end
	label.Text = PREVIEW_SAMPLE_TEXT

	local ok, effect = pcall(function()
		return TitleColorPreset.new(label, presetMode, PRESET_CARD_SPEED, PRESET_CARD_SIZE, true)
	end)
	if ok and effect then
		self._presetCardEffects[button] = effect
	end
end

function AdminPanelUI:_populatePresetCards()
	self:_destroyPresetCardEffects()
	for _, button in ipairs(self._presetButtons) do
		button:Destroy()
	end
	table.clear(self._presetButtons)

	local presets = AnimationModes.GetPresetModes()
	for index, presetMode in ipairs(presets) do
		local card = self._presetTemplate:Clone() :: ImageButton
		card.Name = "Preset_" .. presetMode
		card.Visible = true
		card.LayoutOrder = index
		card.Parent = self._presetInput

		local titleLabel = card:FindFirstChildWhichIsA("TextLabel")
		if titleLabel then
			titleLabel.Text = presetMode
		end

		self:_applyPresetCardPreview(card, presetMode)
		setButtonSelected(card, presetMode == self._selectedPresetMode)

		card.MouseButton1Click:Connect(function()
			self._selectedPresetMode = presetMode
			self:_renderPresetSelection()
			self:_syncRealtimePreview()
		end)

		table.insert(self._presetButtons, card)
	end
end

function AdminPanelUI:_renderPresetSelection()
	for _, button in ipairs(self._presetButtons) do
		local mode = string.match(button.Name, "^Preset_(.+)$")
		setButtonSelected(button, mode == self._selectedPresetMode)
	end
end

function AdminPanelUI:_renderSizeOptions()
	for _, button in pairs(self._sizeButtons) do
		button:Destroy()
	end
	table.clear(self._sizeButtons)

	local sizeOrder = Config.Admin.TITLE_SIZE_ORDER or { "S", "M", "L", "XL", "XXL" }
	for index, sizeKey in ipairs(sizeOrder) do
		local selected = sizeKey == self._selectedSize
		local template = selected and self._sizeSelected or self._sizeNormal
		local button = template:Clone() :: TextButton
		button.Name = "Size" .. sizeKey
		button.Text = sizeKey
		button.Visible = true
		button.LayoutOrder = index
		setButtonSelected(button, selected)
		button.Parent = self._sizeFrame
		self._sizeButtons[sizeKey] = button
		button.MouseButton1Click:Connect(function()
			self._selectedSize = sizeKey
			self:_renderSizeOptions()
			self:_syncRealtimePreview()
		end)
	end
end

function AdminPanelUI:_renderFontOptions()
	if (not self._fontNormal or not self._fontSelected) and self._fontFrame then
		self._fontNormal, self._fontSelected = resolveFontStateTemplates(self._fontFrame)
	end
	if not self._fontNormal or not self._fontSelected then
		return
	end
	for _, button in pairs(self._fontButtons) do
		button:Destroy()
	end
	table.clear(self._fontButtons)

	local fonts = TitleFontUtil.getConfiguredFonts()
	for index, fontName in ipairs(fonts) do
		local selected = fontName == self._selectedFont
		local template = selected and self._fontSelected or self._fontNormal
		local button = template:Clone() :: TextButton
		button.Name = "Font_" .. fontName
		button.Text = fontName
		button.Visible = true
		applyTitleFontToLabel(button, fontName)
		button.LayoutOrder = index
		setButtonSelected(button, selected)
		button.Parent = self._fontFrame
		self._fontButtons[fontName] = button
		button.MouseButton1Click:Connect(function()
			self._selectedFont = fontName
			self:_renderFontOptions()
			self:_syncRealtimePreview()
		end)
	end
	if self._fontFrame and self._fontFrame:IsA("ScrollingFrame") then
		syncScrollCanvas(self._fontFrame)
	end
end

function AdminPanelUI:_populateEmojiButtons()
	if not self._emojiConnections then
		self._emojiConnections = {}
	end
	if not self._emojiList or not self._emojiTemplate then
		return
	end
	for _, connection in ipairs(self._emojiConnections) do
		connection:Disconnect()
	end
	table.clear(self._emojiConnections)
	for _, child in ipairs(self._emojiList:GetChildren()) do
		if child:IsA("TextButton") and child ~= self._emojiTemplate then
			child:Destroy()
		end
	end
	for index, emoji in ipairs(SAFE_EMOJIS) do
		local button = self._emojiTemplate:Clone() :: TextButton
		button.Name = "EmojiButton" .. index
		button.Visible = true
		button.LayoutOrder = index
		local label = button:FindFirstChildWhichIsA("TextLabel")
		if label then
			label.Text = emoji
		else
			button.Text = emoji
		end
		button.Parent = self._emojiList
		table.insert(
			self._emojiConnections,
			button.MouseButton1Click:Connect(function()
				self:_wrapTitleWithEmoji(emoji)
			end)
		)
	end
end

function AdminPanelUI:_wrapTitleWithEmoji(emoji: string)
	local title = trim(self._titleInput.Text)
	if title == "" then
		self._titleInput.Text = emoji .. " " .. emoji
	else
		self._titleInput.Text = emoji .. " " .. title .. " " .. emoji
	end
	self:_syncRealtimePreview()
end

function AdminPanelUI:_openEmojiPicker(pointer: Vector2)
	placeNearPointer(self._emojiPicker, pointer, self._gui)
	popOpen(self._anim, self._emojiPicker)
end

function AdminPanelUI:_clearViewport()
	if self._viewport then
		for _, child in ipairs(self._viewport:GetChildren()) do
			child:Destroy()
		end
	end
	self._previewUserId = nil
end

function AdminPanelUI:_clearPreviewOverlay()
	if self._previewOverlayRow then
		SpecialTitleRenderer.destroy(self._previewOverlayRow)
		self._previewOverlayRow = nil
	end
	local existing = self._overheadPreviewHost:FindFirstChild("AdminPreviewOverheadOverlay")
	if existing then
		existing:Destroy()
	end
end

function AdminPanelUI:_setAvatarPreviewInputCapture(enabled: boolean)
	self._avatarPreview.ZIndex = if enabled then AVATAR_PREVIEW_ZINDEX else FLOATING_PANEL_ZINDEX
	if self._mainDragDetector then
		self._mainDragDetector.Enabled = if enabled then false else self._mainDragDetectorDefaultEnabled
	end
end

function AdminPanelUI:_getOriginalOverheadWrapper(): GuiObject?
	local variant = Config.OverheadGuiVariants[Config.Overhead.GUI_TYPE] or Config.OverheadGuiVariants.V1
	local wrapperName = if type(variant.wrapperName) == "string" then variant.wrapperName else "OverheadGUIMainWrapper"
	local function findWrapper(gui: BillboardGui): GuiObject?
		local wrapper = gui:FindFirstChild(wrapperName) or gui:FindFirstChild("OverheadGUIMainWrapper") or gui:FindFirstChild("Frame")
		if wrapper and wrapper:IsA("GuiObject") then
			return wrapper :: GuiObject
		end
		for _, child in ipairs(gui:GetChildren()) do
			if child:IsA("GuiObject") then
				return child :: GuiObject
			end
		end
		return nil
	end
	local selectedPlayer = self._selectedPlayer
	if selectedPlayer then
		local player = Players:GetPlayerByUserId(selectedPlayer.userId)
		local character = player and player.Character
		local head = character and character:FindFirstChild("Head")
		local liveGui = head and head:FindFirstChild(Config.Template.TEMPLATE_NAME)
		if liveGui and liveGui:IsA("BillboardGui") then
			return findWrapper(liveGui)
		end
	end
	local template = ReplicatedStorage:FindFirstChild(Config.Template.TEMPLATE_NAME)
	if template and template:IsA("BillboardGui") then
		return findWrapper(template)
	end
	return nil
end

function AdminPanelUI:_setPreviewRowText(row: Instance?, text: string)
	if not row then
		return
	end
	local label = row:FindFirstChildWhichIsA("TextLabel", true)
	if label then
		label.Text = text
	end
end

function AdminPanelUI:_renderAvatarPreview()
	local selectedPlayer = self._selectedPlayer
	if not selectedPlayer then
		self:_clearViewport()
		self:_setAvatarPreviewInputCapture(false)
		self._avatarPreview.Visible = false
		return
	end
	local wasVisible = self._avatarPreview.Visible
	self._avatarPreview.Visible = true
	self:_setAvatarPreviewInputCapture(true)
	if not wasVisible then
		popOpen(self._anim, self._avatarPreview)
	end
	self:_clearViewport()
	self._previewUserId = selectedPlayer.userId
	self:_createPreviewOverheadOverlay()
end

function AdminPanelUI:_createPreviewOverheadOverlay()
	self:_clearPreviewOverlay()
	local source = self:_getOriginalOverheadWrapper()
	if not source then
		return
	end

	local wrapper = source:Clone()
	wrapper.Name = "AdminPreviewOverheadOverlay"
	wrapper.AnchorPoint = Vector2.new(0.5, 0)
	wrapper.Position = UDim2.fromScale(0.5, 0.08)
	wrapper.Size = UDim2.new(0.92, 0, 0, 220)
	wrapper.BackgroundTransparency = 1
	if wrapper:IsA("CanvasGroup") then
		(wrapper :: CanvasGroup).GroupTransparency = 0
	end
	wrapper.ZIndex = AVATAR_PREVIEW_ZINDEX
	wrapper.Parent = self._overheadPreviewHost

	local previewScale = wrapper:FindFirstChild("AdminPreviewScale") :: UIScale?
	if not previewScale then
		previewScale = Instance.new("UIScale")
		previewScale.Name = "AdminPreviewScale"
		previewScale.Parent = wrapper
	end
	previewScale.Scale = 1.84

	for _, descendant in ipairs(wrapper:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = math.max(descendant.ZIndex, 100)
		end
	end

	local specialTitleRow = wrapper:FindFirstChild("01-SpecialTitle")
	if not specialTitleRow or not specialTitleRow:IsA("Frame") then
		local created = Instance.new("Frame")
		created.Name = "01-SpecialTitle"
		created.BackgroundTransparency = 1
		created.BorderSizePixel = 0
		created.LayoutOrder = 1
		created.Size = UDim2.new(1, 0, Config.Admin.TITLE_SIZE_HEIGHT_SCALE.M or 0.2, 0)
		created.Parent = wrapper
		local label = Instance.new("TextLabel")
		label.Name = "SpecialTitleText"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.Parent = created
		specialTitleRow = created
	end

	local draftTitle = trim(self:getTitleText())
	if specialTitleRow and specialTitleRow:IsA("Frame") then
		specialTitleRow.Visible = draftTitle ~= ""
		SpecialTitleRenderer.applyRowSize(specialTitleRow, self._selectedSize)

		self._previewOverlayRow = specialTitleRow
		if draftTitle ~= "" then
			SpecialTitleRenderer.apply(specialTitleRow, {
				text = draftTitle,
				font = self._selectedFont,
				size = self._selectedSize,
				presetMode = self._selectedPresetMode,
			})
		else
			SpecialTitleRenderer.destroy(specialTitleRow)
		end
	end

	if self._selectedPlayer then
		local displayNameRow = wrapper:FindFirstChild("08-DisplayName") or wrapper:FindFirstChild("08-DisplayNameAndMembership")
		self:_setPreviewRowText(displayNameRow, self._selectedPlayer.displayName)
	end
end

function AdminPanelUI:applyTitleEditorState(snapshot: TitleEditorSnapshot?, loadTitleIntoInput: boolean?)
	if snapshot then
		self._selectedSize = resolveTitleSize(snapshot.specialTitleSize)
		if type(snapshot.specialTitleFont) == "string" and snapshot.specialTitleFont ~= "" then
			self._selectedFont = resolveTitleFont(snapshot.specialTitleFont)
		else
			self._selectedFont = TitleFontUtil.getBoldestConfiguredFont()
		end
		self._selectedPresetMode = resolveTitlePreset(snapshot.specialTitlePreset)
		if loadTitleIntoInput and type(snapshot.specialTitle) == "string" and snapshot.specialTitle ~= "" then
			self._titleInput.Text = snapshot.specialTitle
		end
	else
		self._selectedSize = "M"
		self._selectedFont = TitleFontUtil.getBoldestConfiguredFont()
		self._selectedPresetMode = resolveTitlePreset(nil)
	end

	self:_renderSizeOptions()
	self:_renderFontOptions()
	self:_renderPresetSelection()
	self:_syncRealtimePreview()
end

function AdminPanelUI:_syncRealtimePreview()
	if self._selectedPlayer then
		self:_renderAvatarPreview()
	end
end

function AdminPanelUI:_applyPlayerInfoContent(playerData: PlayerData?, currentTitle: string?)
	if not playerData then
		self._selectedNameLabel.Text = "Select a player"
		self._selectedUsernameLabel.Text = "@readywhenyouare"
		self._selectedCurrentTitleLabel.Text = "No custom title yet"
		self._selectedProfilePicture.Image = ""
		self._buttonGroup.Visible = false
		self:_setAvatarPreviewInputCapture(false)
		self._avatarPreview.Visible = false
		return
	end
	self._selectedNameLabel.Text = playerData.displayName
	self._selectedUsernameLabel.Text = "@" .. playerData.username
	self._selectedCurrentTitleLabel.Text = currentTitle and ("Current title: " .. currentTitle) or "No custom title yet"
	self._selectedProfilePicture.Image = getThumbnail(playerData.userId)
	self._buttonGroup.Visible = currentTitle ~= nil and currentTitle ~= ""
end

function AdminPanelUI:_setSelectedPlayerInfo(playerData: PlayerData?, snapshot: TitleEditorSnapshot?)
	self._selectedPlayer = playerData
	self._currentTitleSnapshot = snapshot
	self:_refreshPlayerCardSelection()
	self:_applyPlayerInfoContent(playerData, snapshot and snapshot.specialTitle or nil)
	if playerData then
		self:applyTitleEditorState(snapshot, true)
	else
		self:applyTitleEditorState(nil, false)
		self._titleInput.Text = ""
	end
	self._selectedPlayerInfo.Visible = playerData ~= nil
	self._selectPlayerFirstInfo.Visible = playerData == nil
end

function AdminPanelUI:updateSelectedPlayerSnapshot(playerData: PlayerData?, snapshot: TitleEditorSnapshot?)
	self:_setSelectedPlayerInfo(playerData, snapshot)
end

function AdminPanelUI:_isPlayerMatch(playerData: PlayerData, query: string): boolean
	if query == "" then
		return true
	end
	local normalized = string.lower(query)
	return string.find(string.lower(playerData.displayName), normalized, 1, true) ~= nil
		or string.find(string.lower(playerData.username), normalized, 1, true) ~= nil
end

function AdminPanelUI:_ensurePlayerCard(index: number): PlayerListEntry
	local entry = self._playerCardPool[index]
	if entry then
		entry.button.Parent = self._scrollFrame
		return entry
	end
	local button = self._playerTemplate:Clone() :: TextButton
	button.Visible = false
	button.Parent = self._scrollFrame
	entry = { button = button, connection = nil }
	self._playerCardPool[index] = entry
	return entry
end

function AdminPanelUI:_hideUnusedPlayerCards(firstUnusedIndex: number)
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

function AdminPanelUI:_refreshPlayerCardSelection()
	for _, entry in ipairs(self._playerCardPool) do
		local userId = entry.button:GetAttribute("PlayerUserId")
		local isSelected = self._selectedPlayer ~= nil
			and type(userId) == "number"
			and self._selectedPlayer.userId == userId
		entry.button.BackgroundTransparency = if isSelected then Config.Gift.CARD_SELECTED_ALPHA else 1
	end
end

function AdminPanelUI:_renderPlayerList(players: { PlayerData })
	self._playerTemplate.Visible = false
	self._notFoundCard.Visible = #players == 0
	if #players == 0 then
		if #self._allPlayers == 0 then
			setNotFoundCardText(self._notFoundCard, EMPTY_STATE_DEFAULT_TITLE, EMPTY_STATE_DEFAULT_SUBTITLE)
		else
			setNotFoundCardText(self._notFoundCard, EMPTY_STATE_SEARCH_TITLE, EMPTY_STATE_SEARCH_SUBTITLE)
		end
	end
	local query = trim(self._searchBox.Text)
	for index, playerData in ipairs(players) do
		local entry = self:_ensurePlayerCard(index)
		local card = entry.button
		if entry.connection then
			entry.connection:Disconnect()
			entry.connection = nil
		end
		card.Visible = true
		card.LayoutOrder = index
		card:SetAttribute("PlayerUserId", playerData.userId)
		local info = card:FindFirstChild("PlayerInformation") :: Frame?
		local profilePicture = card:FindFirstChild("PlayerProfilePicture") :: ImageLabel?
		if info then
			local nameLabel = info:FindFirstChild("1-Title") :: TextLabel?
			local subtitleLabel = info:FindFirstChild("2-SubTitle") :: TextLabel?
			if nameLabel then
				nameLabel.RichText = true
				nameLabel.Text = highlightFirstMatch(playerData.displayName, query)
			end
			if subtitleLabel then
				subtitleLabel.RichText = true
				subtitleLabel.Text = "@" .. highlightFirstMatch(playerData.username, query)
			end
		end
		if profilePicture then
			profilePicture.Image = getThumbnail(playerData.userId)
		end
		entry.connection = card.MouseButton1Click:Connect(function()
			if self._selectedPlayer and self._selectedPlayer.userId == playerData.userId then
				self._selectedPlayer = nil
				self:_refreshPlayerCardSelection()
				if self._onPlayerDeselected then
					self._onPlayerDeselected()
				end
				return
			end
			self._selectedPlayer = table.clone(playerData)
			self:_refreshPlayerCardSelection()
			if self._onPlayerSelected then
				self._onPlayerSelected(self._selectedPlayer)
			end
		end)
	end
	self:_hideUnusedPlayerCards(#players + 1)
	self:_refreshPlayerCardSelection()
end

function AdminPanelUI:_applyPlayerSearch()
	local query = trim(self._searchBox.Text)
	local filteredPlayers = table.create(#self._allPlayers)
	for _, playerData in ipairs(self._allPlayers) do
		if self:_isPlayerMatch(playerData, query) then
			table.insert(filteredPlayers, playerData)
		end
	end
	self:_renderPlayerList(filteredPlayers)
end

function AdminPanelUI:populatePlayers(players: { PlayerData })
	self._allPlayers = players
	self._searchBox.Text = ""
	self:_applyPlayerSearch()
end

function AdminPanelUI:setTab(tab: string)
	self._activeTab = "GiveTitle"
	self._inputTitleFrame.Visible = true
	local button = self._selector:FindFirstChild("GiveTitleTabButton")
	if button then
		for _, child in ipairs(button:GetChildren()) do
			if child:IsA("UIGradient") then
				child.Enabled = child.Name == "UIGradient-Selected"
			end
		end
	end
end

function AdminPanelUI:getSelectedPlayer(): PlayerData?
	return self._selectedPlayer
end

function AdminPanelUI:getActiveTab(): string
	return self._activeTab
end

function AdminPanelUI:getSelectedPresetMode(): string
	return self._selectedPresetMode
end

function AdminPanelUI:getSelectedFont(): string
	return self._selectedFont
end

function AdminPanelUI:getSelectedSize(): string
	return self._selectedSize
end

function AdminPanelUI:getTitleText(): string
	return self._titleInput.Text
end

function AdminPanelUI:setTitleInputText(text: string)
	self._titleInput.Text = text
end

function AdminPanelUI:loadCurrentTitleIntoEditor()
	if not self._currentTitleSnapshot then
		return
	end
	self:applyTitleEditorState(self._currentTitleSnapshot, true)
end

function AdminPanelUI:bindPlayerSelected(callback: (PlayerData) -> ())
	self._onPlayerSelected = callback
end

function AdminPanelUI:bindPlayerDeselected(callback: () -> ())
	self._onPlayerDeselected = callback
end

function AdminPanelUI:bindTabButton(tab: string, callback: () -> ())
	if tab ~= "GiveTitle" then
		return
	end
	local button = self._selector:FindFirstChild("GiveTitleTabButton") :: TextButton?
	if button then
		button.MouseButton1Click:Connect(callback)
	end
end

function AdminPanelUI:bindApplyTitle(callback: () -> ())
	self._saveTitleButton.MouseButton1Click:Connect(callback)
end

function AdminPanelUI:bindDeleteTitle(callback: () -> ())
	self._deleteTitleButton.MouseButton1Click:Connect(callback)
end

function AdminPanelUI:bindEditTitle(_callback: () -> ()) end

function AdminPanelUI:bindClose(callback: () -> ())
	self._closeButton.MouseButton1Click:Connect(callback)
end

function AdminPanelUI:show()
	self._emojiPicker.Visible = false
	self:_setAvatarPreviewInputCapture(false)
	self._avatarPreview.Visible = false
	self._gui.Enabled = true
	self._anim:presentCenterPanel(self._mainWrapper, nil, {
		enableBlur = true,
		blurName = "AdminPanelUIBlur",
		enableZoom = true,
	})
end

function AdminPanelUI:hide()
	self._emojiPicker.Visible = false
	self:_setAvatarPreviewInputCapture(false)
	self._avatarPreview.Visible = false
	if not self._mainWrapper.Visible and not self._gui.Enabled then
		return
	end
	self._anim:dismissCenterPanel(self._mainWrapper, function()
		self._gui.Enabled = false
	end, {
		enableBlur = true,
		blurName = "AdminPanelUIBlur",
		enableZoom = true,
	})
end

function AdminPanelUI:isVisible(): boolean
	return self._gui.Enabled and self._mainWrapper.Visible
end

function AdminPanelUI:generateTitleStyles(_seed: number) end

function AdminPanelUI:showPackageList() end
function AdminPanelUI:hidePackageList() end
function AdminPanelUI:getSelectedPackage(): string? return nil end
function AdminPanelUI:setPackageSelected(_tier: string) end
function AdminPanelUI:showConfirmation(_playerData: PlayerData, _tier: string?) end
function AdminPanelUI:hideConfirmation() end
function AdminPanelUI:showConfirmDialog(_message: string, _onYes: () -> (), _onNo: () -> ()) end
function AdminPanelUI:hideConfirmDialog() end
function AdminPanelUI:showSuccessMessage(_message: string, _duration: number) end
function AdminPanelUI:setLoadingState(_isLoading: boolean) end
function AdminPanelUI:bindPackageSelected(_callback: (string) -> ()) end
function AdminPanelUI:bindSendGift(_callback: (PlayerData, string) -> ()) end
function AdminPanelUI:bindConfirmationSendGift(_callback: () -> ()) end
function AdminPanelUI:bindConfirmDialog(_callback: (boolean) -> ()) end
function AdminPanelUI:getFSMState(): string return "IDLE" end
function AdminPanelUI:transitionToPlayerSelected(_playerData: PlayerData) end
function AdminPanelUI:transitionToConfirmation(_playerData: PlayerData, _tier: string) end
function AdminPanelUI:transitionToConfirmDialog(_message: string, _onYes: () -> (), _onNo: () -> ()) end
function AdminPanelUI:transitionBackToConfirmation() end
function AdminPanelUI:transitionToSending() end
function AdminPanelUI:transitionToSuccess(_message: string) end
function AdminPanelUI:transitionToConfirmationWithError(_errorMessage: string) end
function AdminPanelUI:transitionToIdle() end

return AdminPanelUI
