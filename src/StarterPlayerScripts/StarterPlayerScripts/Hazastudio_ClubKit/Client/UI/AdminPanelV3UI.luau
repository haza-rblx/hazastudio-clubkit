--!strict
-- Client/UI/AdminPanelV3UI.luau
-- Binds the `04-AdminPanelv3` ScreenGui: pick a player, then give them either a
-- text custom title or an image custom title.
--
-- A separate module from AdminPanelUI rather than a second mode inside it: v3
-- renamed every outer container, dropped the emoji picker and the inline preset
-- grid, and added an image tab, so one file trying to serve both structures would
-- be mostly branching. v2 keeps working untouched for places still on it.
--
-- `tryCreate` returns nil when the ScreenGui or a ref it cannot work without is
-- missing, so the caller can fall back to the v2 panel instead of binding a
-- half-resolved one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local TitleColorPreset = require(ReplicatedStorage.Hazastudio_ClubKit.OverheadEffects.TitleColorPreset)
local AnimationModes = TitleColorPreset.AnimationModes
local TitleFontUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.TitleFontUtil)
local TitleImageDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.TitleImageDomain)
local SliderSelectorUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.SliderSelectorUtil)
local PresetPreview = require(script.Parent.Parent.Utils.PresetPreview)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
local MotionPresets = require(script.Parent.Parent.Utils.MotionPresets)

local AdminPanelV3UI = {}
AdminPanelV3UI.__index = AdminPanelV3UI

export type TitleForm = {
	targetUsername: string,
	title: string,
	titleSize: string,
	presetMode: string?,
	titleFont: string?,
}

export type ImageForm = {
	targetUsername: string,
	imageId: string,
}

export type PlayerEntry = {
	userId: number,
	displayName: string,
	username: string,
}

local DEFAULT_SIZE = "M"
local NO_PRESET_LABEL = "DEFAULT"
local NO_FONT_LABEL = "DEFAULT"
local TAB_TEXT = "text"
local TAB_IMAGE = "image"
-- Grace period after a dismissal's own duration before the handoff gives up on
-- its callback and shows the incoming frame itself.
local HANDOFF_SAFETY = 0.12

local function findChild(parent: Instance?, name: string): Instance?
	return if parent then parent:FindFirstChild(name) else nil
end

local function takeTemplate(parent: Instance?, name: string): GuiObject?
	local found = findChild(parent, name)
	if not found or not found:IsA("GuiObject") then
		return nil
	end
	local template = found:Clone()
	found:Destroy()
	return template
end

local function asFrame(instance: Instance?): Frame?
	return if instance and instance:IsA("Frame") then instance :: Frame else nil
end

-- Matches the menu shell's own modal reset: an interrupted tween can leave a
-- UIScale mid-pop, so the resting state is restored alongside the hide.
local function resetModalVisual(target: GuiObject)
	local uiScale = target:FindFirstChildWhichIsA("UIScale")
	if uiScale then
		uiScale.Scale = 1
	end
	target.Visible = false
end

local function setLabelText(root: Instance?, text: string)
	if not root then
		return
	end
	local label = root:FindFirstChildWhichIsA("TextLabel")
	if label then
		label.Text = text
	end
end

local function bindButton(instance: Instance?, callback: () -> ())
	if instance and instance:IsA("GuiButton") then
		instance.AutoButtonColor = false
		instance.Activated:Connect(callback)
	end
end

-- `anim` lets a caller share its AnimationHelper; this panel has no shell to take
-- one from, so it builds its own by default. Safe either way — the helper is
-- stateless and its tween bookkeeping is module-level, keyed per instance.
function AdminPanelV3UI.tryCreate(playerGui: Instance, anim: any?): any?
	local gui = playerGui:FindFirstChild(Config.Admin.GUI_NAME_V3)
	if not gui or not gui:IsA("ScreenGui") then
		return nil
	end

	local mainWrapper = findChild(gui, "MainWrapper")
	local mainContent = findChild(mainWrapper, "MainContent")
	local selectFrame = findChild(mainContent, "SelectPlayerFrame")
	local titleWrapper = findChild(mainContent, "CustomTitleWrapper")
	local wrapper = findChild(titleWrapper, "Wrapper")
	local textTab = findChild(wrapper, "CustomTitleTab")
	local imageTab = findChild(wrapper, "ImageCustomTitleTab")
	local overlay = findChild(titleWrapper, "OverlayWrapper")

	local searchBox = findChild(selectFrame, "02-SearchBox")
	local playerList = findChild(selectFrame, "ScrollablePlayerList")
	if
		not (mainWrapper and mainWrapper:IsA("GuiObject"))
		or not (textTab and imageTab)
		or not (searchBox and searchBox:IsA("TextBox"))
		or not (playerList and playerList:IsA("ScrollingFrame"))
	then
		return nil
	end

	local playerCard = takeTemplate(playerList, "PlayerSelectorCard")
	local notFoundCard = takeTemplate(playerList, "NotFoundCard")
	if not playerCard then
		return nil
	end

	local self = setmetatable({}, AdminPanelV3UI) :: any
	self._anim = anim or AnimationHelper.new()
	self._gui = gui
	self._mainWrapper = mainWrapper
	self._searchBox = searchBox
	self._playerList = playerList
	self._playerCardTemplate = playerCard
	self._notFoundTemplate = notFoundCard
	self._playerRows = {} :: { GuiObject }

	self._textTab = textTab
	self._imageTab = imageTab
	self._activeTab = TAB_TEXT

	-- Text tab refs
	local sizeRow = findChild(findChild(textTab, "SelectSize"), "02-SelectSizeInput")
	self._sizeRow = sizeRow
	self._sizeNormal = takeTemplate(sizeRow, "NormalState")
	self._sizeSelected = takeTemplate(sizeRow, "SelectedState")
	self._sizeButtons = {} :: { [string]: GuiObject }
	self._presetButton = findChild(findChild(textTab, "SelectStyle"), "SelectPresetButton")
	self._typefaceButton = findChild(findChild(textTab, "SelectFontStyle"), "SelectTypefraceButton")
		or findChild(findChild(textTab, "SelectFontStyle"), "SelectTypefaceButton")
	self._titleInput = findChild(findChild(textTab, "InputTitleWrapper"), "02-InputCustomTitle")

	-- Image tab refs
	self._imageInput = findChild(findChild(imageTab, "InputTitleWrapper"), "02-InputCustomTitle")
	local existingWrapper = findChild(findChild(imageTab, "orSelectExistingImage"), "Wrapper")
	self._imageGrid = existingWrapper
	self._imageNormal = takeTemplate(existingWrapper, "ImageButtonNormal")
	self._imageSelected = takeTemplate(existingWrapper, "ImageButtonSelected")
	self._imageRows = {} :: { GuiObject }
	self._selectedImage = ""

	-- Shared chrome
	self._saveButton = findChild(overlay, "SaveButton")
	self._removeButton = findChild(overlay, "RemoveButton")
	-- Both buttons act on whichever tab is open, so their labels follow it. The
	-- template's own wording is the text-tab wording and is kept to restore.
	self._saveLabel = if self._saveButton then self._saveButton:FindFirstChildWhichIsA("TextLabel") else nil
	self._saveLabelText = if self._saveLabel then self._saveLabel.Text else nil
	self._removeLabel = if self._removeButton then self._removeButton:FindFirstChildWhichIsA("TextLabel") else nil
	self._removeLabelText = if self._removeLabel then self._removeLabel.Text else nil
	self._closeButton = findChild(findChild(mainWrapper, "Header"), "99-CloseModalButton")
		or findChild(findChild(mainWrapper, "TabSwitcher"), "3-CloseModalButton")

	-- Header tabs, resolved the way every other slider header in the kit is: the
	-- outer `2-SliderSelector` owns the pill, an inner one of the same name (when
	-- present) owns the option buttons.
	local sliderOuter = findChild(findChild(mainWrapper, "Header"), "2-SliderSelector")
	self._slider = sliderOuter
	if sliderOuter and sliderOuter:IsA("GuiObject") then
		local container = SliderSelectorUtil.getOptionsContainer(sliderOuter)
		local allButtons = SliderSelectorUtil.collectTabButtons(container)
		local labels = Config.Admin.V3_TAB_LABELS or {}
		self._tabPill = SliderSelectorUtil.getBackgroundPill(sliderOuter)
		self._tabButtonOrder = {} :: { TextButton }
		self._tabButtons = {} :: { [string]: TextButton }
		for index, key in ipairs({ TAB_TEXT, TAB_IMAGE }) do
			local button = SliderSelectorUtil.resolveTabButton(container, { optionIndex = index }, allButtons)
			if button then
				self._tabButtons[key] = button
				table.insert(self._tabButtonOrder, button)
				local label = labels[key]
				if type(label) == "string" and label ~= "" then
					SliderSelectorUtil.applyTabLabel(button, label)
				end
			end
		end
	else
		self._tabButtonOrder = {} :: { TextButton }
		self._tabButtons = {} :: { [string]: TextButton }
	end

	self._presetModal = asFrame(findChild(gui, "SelectPresetModal"))
	self._typefaceModal = asFrame(findChild(gui, "SelectTypefaceModal"))
	self._pickerState = {} :: any
	self._rowEffects = {} :: { any }
	self._presetSummaryEffect = nil :: any

	self._selectedSize = DEFAULT_SIZE
	self._selectedPreset = nil :: string?
	self._selectedFont = nil :: string?
	self._selectedPlayer = nil :: PlayerEntry?
	self._allPlayers = {} :: { PlayerEntry }

	self._applyTitleCallback = nil :: ((TitleForm) -> ())?
	self._applyImageCallback = nil :: ((ImageForm) -> ())?
	self._removeCallback = nil :: ((PlayerEntry) -> ())?
	self._imageListCallback = nil :: (() -> ())?
	self._closeCallback = nil :: (() -> ())?
	self._playerSelectedCallback = nil :: ((PlayerEntry) -> ())?

	self:_wire()
	self:setTab(TAB_TEXT)
	self:refreshPlayers()
	return self
end

-- ============================================================
-- Player list
-- ============================================================

function AdminPanelV3UI:_clearPlayerRows()
	for _, row in ipairs(self._playerRows) do
		row:Destroy()
	end
	table.clear(self._playerRows)
end

function AdminPanelV3UI:_renderPlayers(entries: { PlayerEntry })
	self:_clearPlayerRows()

	if #entries == 0 then
		if self._notFoundTemplate then
			local card = self._notFoundTemplate:Clone()
			card.Name = "NotFound"
			card.Parent = self._playerList
			table.insert(self._playerRows, card)
		end
		return
	end

	for index, entry in ipairs(entries) do
		local card = self._playerCardTemplate:Clone()
		card.Name = "Player_" .. entry.userId
		card.LayoutOrder = index

		local info = card:FindFirstChild("PlayerInformation")
		local title = info and info:FindFirstChild("1-Title")
		local subtitle = info and info:FindFirstChild("2-SubTitle")
		if title and title:IsA("TextLabel") then
			title.Text = entry.displayName
		end
		if subtitle and subtitle:IsA("TextLabel") then
			subtitle.Text = "@" .. entry.username
		end
		local picture = card:FindFirstChild("PlayerProfilePicture")
		if picture and picture:IsA("ImageLabel") then
			picture.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", entry.userId)
		end

		if card:IsA("GuiButton") then
			card.AutoButtonColor = false
			card.Activated:Connect(function()
				self:selectPlayer(entry)
			end)
		end
		card.Parent = self._playerList
		table.insert(self._playerRows, card)
	end
end

-- Rebuild the roster from who is actually on the server, then re-apply the search
-- filter so a player joining or leaving never silently changes the visible list.
function AdminPanelV3UI:refreshPlayers()
	local entries: { PlayerEntry } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(entries, {
			userId = player.UserId,
			displayName = player.DisplayName,
			username = player.Name,
		})
	end
	table.sort(entries, function(a, b)
		return a.displayName:lower() < b.displayName:lower()
	end)
	self._allPlayers = entries
	self:_applySearch(self._searchBox.Text)
end

function AdminPanelV3UI:_applySearch(query: string)
	local needle = (query or ""):lower():match("^%s*(.-)%s*$") or ""
	if needle == "" then
		self:_renderPlayers(self._allPlayers)
		return
	end
	local matches: { PlayerEntry } = {}
	for _, entry in ipairs(self._allPlayers) do
		if entry.displayName:lower():find(needle, 1, true) or entry.username:lower():find(needle, 1, true) then
			table.insert(matches, entry)
		end
	end
	self:_renderPlayers(matches)
end

function AdminPanelV3UI:selectPlayer(entry: PlayerEntry)
	self._selectedPlayer = entry
	self:_paintSelectedPlayer()
	if self._playerSelectedCallback then
		self._playerSelectedCallback(entry)
	end
end

function AdminPanelV3UI:getSelectedPlayer(): PlayerEntry?
	return self._selectedPlayer
end

-- Load the target's stored title into the editor. Called on selection, so the
-- admin edits what the player actually has instead of a blank form.
--
-- Deliberately not called from the live overhead refresh: that would reload the
-- form under an admin who is mid-edit, the same way the self-service panel used
-- to lose a player's typing. The live path only repaints the current-title line.
function AdminPanelV3UI:applyTargetSnapshot(snapshot: any)
	local data = if type(snapshot) == "table" then snapshot else {}
	self:setCurrentTitle(data.specialTitle)

	if self._titleInput and self._titleInput:IsA("TextBox") then
		self._titleInput.Text = data.specialTitle or ""
	end
	self._selectedSize = data.specialTitleSize or DEFAULT_SIZE
	self._selectedPreset = data.specialTitlePreset
	self._selectedFont = data.specialTitleFont
	self:_buildSizeButtons()
	self:_refreshChoiceLabels()

	self._selectedImage = if type(data.specialTitleImage) == "string" then data.specialTitleImage else ""
	if self._imageInput and self._imageInput:IsA("TextBox") then
		self._imageInput.Text = self._selectedImage
	end
end

-- Both tabs carry their own copy of the selected-player header, so paint whichever
-- ones the GUI actually has.
function AdminPanelV3UI:_paintSelectedPlayer()
	local entry = self._selectedPlayer
	for _, tab in ipairs({ self._textTab, self._imageTab }) do
		local selectedInfo = findChild(tab, "SelectedPlayerInfo")
		local firstInfo = findChild(tab, "SelectPlayerFirstInfo")
		if selectedInfo and selectedInfo:IsA("GuiObject") then
			selectedInfo.Visible = entry ~= nil
		end
		if firstInfo and firstInfo:IsA("GuiObject") then
			firstInfo.Visible = entry == nil
		end
		if entry and selectedInfo then
			local picture = selectedInfo:FindFirstChild("TargetProfilePicture")
			if picture and picture:IsA("ImageLabel") then
				picture.Visible = true
				picture.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=420&h=420", entry.userId)
			end
			local infoWrapper = selectedInfo:FindFirstChild("TargetInfoWrapper")
			local playerInfo = infoWrapper and infoWrapper:FindFirstChild("1-PlayerInformation")
			if playerInfo then
				local title = playerInfo:FindFirstChild("1-Title")
				local subtitle = playerInfo:FindFirstChild("1-SubTitle")
				if title and title:IsA("TextLabel") then
					title.Text = entry.displayName
				end
				if subtitle and subtitle:IsA("TextLabel") then
					subtitle.Text = "@" .. entry.username
				end
			end
		end
	end
end

-- Whatever the target's current title is, shown on the text tab's header row.
function AdminPanelV3UI:setCurrentTitle(text: string?)
	for _, tab in ipairs({ self._textTab, self._imageTab }) do
		local selectedInfo = findChild(tab, "SelectedPlayerInfo")
		local infoWrapper = selectedInfo and selectedInfo:FindFirstChild("TargetInfoWrapper")
		local playerInfo = infoWrapper and infoWrapper:FindFirstChild("1-PlayerInformation")
		local current = playerInfo and playerInfo:FindFirstChild("3-CurrentTitle")
		if current and current:IsA("TextLabel") then
			current.Text = if text and text ~= "" then '"' .. text .. '"' else "No title yet"
		end
	end
end

-- ============================================================
-- Text tab
-- ============================================================

function AdminPanelV3UI:_buildSizeButtons()
	if not self._sizeRow or not self._sizeNormal or not self._sizeSelected then
		return
	end
	for _, button in pairs(self._sizeButtons) do
		button:Destroy()
	end
	table.clear(self._sizeButtons)

	for index, sizeKey in ipairs(Config.Admin.TITLE_SIZE_ORDER or { DEFAULT_SIZE }) do
		local selected = sizeKey == self._selectedSize
		local button = (if selected then self._sizeSelected else self._sizeNormal):Clone()
		button.Name = "Size_" .. sizeKey
		button.LayoutOrder = index
		if button:IsA("TextButton") then
			button.Text = sizeKey
			button.AutoButtonColor = false
			button.Activated:Connect(function()
				if self._selectedSize ~= sizeKey then
					self._selectedSize = sizeKey
					self:_buildSizeButtons()
				end
			end)
		end
		button.Parent = self._sizeRow
		self._sizeButtons[sizeKey] = button
	end
end

function AdminPanelV3UI:_destroyRowEffects()
	PresetPreview.destroyAll(self._rowEffects)
end

function AdminPanelV3UI:_buildPicker(modal: Instance, entries: { string }, current: string?, decorate: any, onPick: (string) -> ())
	local scroll = findChild(modal, "ScrollingFrame")
	if not scroll then
		return
	end
	local state = self._pickerState[modal]
	if not state then
		local normal = takeTemplate(scroll, "NormalState")
		local selected = takeTemplate(scroll, "SelectedState")
		if not normal or not selected then
			return
		end
		state = { normal = normal, selected = selected, rows = {} }
		self._pickerState[modal] = state
	end

	self:_destroyRowEffects()
	for _, row in ipairs(state.rows) do
		row:Destroy()
	end
	table.clear(state.rows)

	for index, value in ipairs(entries) do
		local row = (if value == current then state.selected else state.normal):Clone()
		row.Name = "Entry_" .. value
		row.LayoutOrder = index
		setLabelText(row, value)
		if decorate then
			decorate(row, value)
		end
		if row:IsA("GuiButton") then
			row.AutoButtonColor = false
			row.Activated:Connect(function()
				onPick(value)
			end)
		end
		row.Parent = scroll
		table.insert(state.rows, row)
	end
end

-- ============================================================
-- Motion — the same center pop the menu shell gives its own modals, so this
-- panel does not invent a second motion vocabulary.
-- ============================================================

function AdminPanelV3UI:_present(target: GuiObject?, onDone: (() -> ())?)
	if not target then
		if onDone then
			onDone()
		end
		return
	end
	local frame = asFrame(target)
	if not frame then
		-- Not a Frame (the helper only tweens those): show it plainly rather than
		-- leaving the surface stuck closed.
		target.Visible = true
		if onDone then
			onDone()
		end
		return
	end
	self._anim:cancelPanel(frame)
	self._anim:presentCenterPanel(frame, onDone)
end

-- `immediate` skips the tween for state resets (the controller's start-closed
-- call, an already-hidden surface), where a dismissal would otherwise flash the
-- frame on screen just to play it.
function AdminPanelV3UI:_dismiss(target: GuiObject?, immediate: boolean?, onDone: (() -> ())?)
	local frame = if target then asFrame(target) else nil
	if not target or not frame or immediate or not target.Visible then
		if frame then
			self._anim:cancelPanel(frame)
		end
		if target then
			resetModalVisual(target)
		end
		if onDone then
			onDone()
		end
		return
	end
	self._anim:dismissCenterPanel(frame, function()
		resetModalVisual(frame)
		if onDone then
			onDone()
		end
	end)
end

-- One frame steps aside, then the other pops: the two are never both mid-tween.
--
-- The dismissal's own callback is the happy path, but AnimationHelper skips it
-- whenever that tween is cancelled or superseded by another animation on the same
-- frame — and a handoff chained only off that callback would then leave *both*
-- frames hidden, with nothing on screen to click. So the arrival is also armed on
-- a timer: whichever runs first shows `to`, the other finds it already visible and
-- does nothing. The generation counter keeps a stale timer from re-opening
-- something after a newer interaction has moved on.
function AdminPanelV3UI:_handoff(from: GuiObject?, to: GuiObject?)
	self:_bumpMotion()
	local gen = self._motionGen
	local function arrive()
		if gen ~= self._motionGen or not to or to.Visible then
			return
		end
		self:_present(to)
	end
	self:_dismiss(from, false, arrive)
	task.delay(MotionPresets.centerClose().time + HANDOFF_SAFETY, arrive)
end

-- Anything that decides what should be on screen invalidates a pending handoff.
function AdminPanelV3UI:_bumpMotion()
	self._motionGen = (self._motionGen or 0) + 1
end

-- A picker takes over the screen rather than stacking on the panel.
function AdminPanelV3UI:_openPicker(modal: Frame, build: () -> ())
	build()
	self:_handoff(self._mainWrapper, modal)
end

-- Back out of a picker: it hands the screen back to the panel it came from, and
-- its preset animations stop with it.
function AdminPanelV3UI:_closePicker(modal: Frame)
	self:_destroyRowEffects()
	self:_handoff(modal, self._mainWrapper)
end

function AdminPanelV3UI:_openPresetPicker()
	local modal = self._presetModal
	if not modal then
		return
	end
	local presets = AnimationModes.GetPresetModes()
	local function decorate(row: GuiObject, value: string)
		local label = row:FindFirstChildWhichIsA("TextLabel")
		if label then
			local effect = PresetPreview.paint(label, value)
			if effect then
				table.insert(self._rowEffects, effect)
			end
		end
	end
	local rebuild: () -> ()
	rebuild = function()
		self:_buildPicker(modal, presets, self._selectedPreset, decorate, function(value)
			self._selectedPreset = value
			self:_refreshChoiceLabels()
			rebuild()
		end)
	end
	self:_openPicker(modal, rebuild)
end

function AdminPanelV3UI:_openTypefacePicker()
	local modal = self._typefaceModal
	if not modal then
		return
	end
	local fonts = TitleFontUtil.getConfiguredFonts()
	local function decorate(row: GuiObject, value: string)
		local label = row:FindFirstChildWhichIsA("TextLabel")
		if label then
			TitleFontUtil.applyToTextLabel(label, value)
		end
	end
	local rebuild: () -> ()
	rebuild = function()
		self:_buildPicker(modal, fonts, self._selectedFont, decorate, function(value)
			self._selectedFont = value
			self:_refreshChoiceLabels()
			rebuild()
		end)
	end
	self:_openPicker(modal, rebuild)
end

function AdminPanelV3UI:_refreshChoiceLabels()
	if self._presetButton then
		local name = self._presetButton:FindFirstChild("PresetName")
		if name and name:IsA("TextLabel") then
			name.Text = self._selectedPreset or NO_PRESET_LABEL
			if self._presetSummaryEffect then
				pcall(function()
					self._presetSummaryEffect:Destroy()
				end)
				self._presetSummaryEffect = nil
			end
			if self._selectedPreset then
				self._presetSummaryEffect = PresetPreview.paint(name, self._selectedPreset)
			end
		end
	end
	if self._typefaceButton then
		local name = self._typefaceButton:FindFirstChild("TypefaceName")
		if name and name:IsA("TextLabel") then
			name.Text = self._selectedFont or NO_FONT_LABEL
			TitleFontUtil.applyToTextLabel(name, self._selectedFont)
		end
	end
end

-- ============================================================
-- Image tab
-- ============================================================

-- `list` is the place-global registry of images assigned before, newest first.
function AdminPanelV3UI:setImageList(list: { string })
	if not self._imageGrid or not self._imageNormal or not self._imageSelected then
		return
	end
	for _, row in ipairs(self._imageRows) do
		row:Destroy()
	end
	table.clear(self._imageRows)

	for index, assetId in ipairs(TitleImageDomain.sanitizeList(list, Config.TitleImage.REGISTRY_MAX)) do
		local button = (if assetId == self._selectedImage then self._imageSelected else self._imageNormal):Clone()
		button.Name = "Image_" .. index
		button.LayoutOrder = index
		if button:IsA("ImageButton") then
			button.Image = assetId
			button.AutoButtonColor = false
			button.Activated:Connect(function()
				self._selectedImage = assetId
				if self._imageInput and self._imageInput:IsA("TextBox") then
					self._imageInput.Text = assetId
				end
				self:setImageList(list)
			end)
		end
		button.Parent = self._imageGrid
		table.insert(self._imageRows, button)
	end
end

-- ============================================================
-- Tabs, wiring, visibility
-- ============================================================

-- Save/Remove name the thing they will actually do on the open tab. The image
-- wording comes from config; the text wording is whatever the template shipped, so
-- a buyer who renamed those buttons keeps their own words on the text tab.
function AdminPanelV3UI:_paintActionLabels()
	local labels = Config.Admin.V3_ACTION_LABELS or {}
	local isImage = self._activeTab == TAB_IMAGE
	if self._saveLabel then
		local imageText = labels.saveImage
		self._saveLabel.Text = if isImage and type(imageText) == "string" and imageText ~= ""
			then imageText
			else self._saveLabelText or self._saveLabel.Text
	end
	if self._removeLabel then
		local imageText = labels.removeImage
		self._removeLabel.Text = if isImage and type(imageText) == "string" and imageText ~= ""
			then imageText
			else self._removeLabelText or self._removeLabel.Text
	end
end

function AdminPanelV3UI:setTab(tab: string)
	self._activeTab = if tab == TAB_IMAGE then TAB_IMAGE else TAB_TEXT
	if self._textTab and self._textTab:IsA("GuiObject") then
		self._textTab.Visible = self._activeTab == TAB_TEXT
	end
	if self._imageTab and self._imageTab:IsA("GuiObject") then
		self._imageTab.Visible = self._activeTab == TAB_IMAGE
	end
	self:_paintActionLabels()

	-- The pill slides under whichever option is live, on the same tween every other
	-- slider header in the kit uses. The old code copied the option's own
	-- `Position`, which could never move it: a UIListLayout arranges those buttons,
	-- so both of them read `{0,0},{0,0}`.
	for key, button in pairs(self._tabButtons) do
		SliderSelectorUtil.setTabButtonSelected(button, key == self._activeTab)
	end
	local selectedButton = self._tabButtons[self._activeTab]
	if self._tabPill and selectedButton then
		SliderSelectorUtil.animateSlidingPill(self._tabPill, selectedButton, self._tabButtonOrder)
	end
	if self._activeTab == TAB_IMAGE and self._imageListCallback then
		self._imageListCallback()
	end
end

function AdminPanelV3UI:getTab(): string
	return self._activeTab
end

function AdminPanelV3UI:_submit()
	local entry = self._selectedPlayer
	if not entry then
		return
	end
	if self._activeTab == TAB_IMAGE then
		if not self._applyImageCallback then
			return
		end
		local raw = if self._imageInput and self._imageInput:IsA("TextBox") then self._imageInput.Text else ""
		self._applyImageCallback({
			targetUsername = entry.username,
			imageId = TitleImageDomain.normalizeAssetId(raw),
		} :: ImageForm)
		return
	end

	if not self._applyTitleCallback then
		return
	end
	self._applyTitleCallback({
		targetUsername = entry.username,
		title = if self._titleInput and self._titleInput:IsA("TextBox") then self._titleInput.Text else "",
		titleSize = self._selectedSize,
		presetMode = self._selectedPreset,
		titleFont = self._selectedFont,
	} :: TitleForm)
end

function AdminPanelV3UI:_wire()
	if self._searchBox and self._searchBox:IsA("TextBox") then
		self._searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			self:_applySearch(self._searchBox.Text)
		end)
	end
	Players.PlayerAdded:Connect(function()
		self:refreshPlayers()
	end)
	Players.PlayerRemoving:Connect(function()
		self:refreshPlayers()
	end)

	bindButton(self._presetButton, function()
		self:_openPresetPicker()
	end)
	bindButton(self._typefaceButton, function()
		self:_openTypefacePicker()
	end)
	bindButton(self._saveButton, function()
		self:_submit()
	end)
	bindButton(self._removeButton, function()
		local entry = self._selectedPlayer
		if entry and self._removeCallback then
			self._removeCallback(entry)
		end
	end)
	bindButton(self._closeButton, function()
		self:hide()
		if self._closeCallback then
			self._closeCallback()
		end
	end)

	bindButton(self._tabButtons[TAB_TEXT], function()
		self:setTab(TAB_TEXT)
	end)
	bindButton(self._tabButtons[TAB_IMAGE], function()
		self:setTab(TAB_IMAGE)
	end)

	for _, modal in ipairs({ self._presetModal, self._typefaceModal }) do
		if modal then
			local function hidePicker()
				self:_closePicker(modal)
			end
			bindButton(findChild(modal, "BackButton"), hidePicker)
			bindButton(findChild(modal, "ConfirmButton"), hidePicker)
		end
	end
end

function AdminPanelV3UI:bindApplyTitle(callback: (TitleForm) -> ())
	self._applyTitleCallback = callback
end

function AdminPanelV3UI:bindApplyImage(callback: (ImageForm) -> ())
	self._applyImageCallback = callback
end

function AdminPanelV3UI:bindRemoveTitle(callback: (PlayerEntry) -> ())
	self._removeCallback = callback
end

function AdminPanelV3UI:bindRequestImageList(callback: () -> ())
	self._imageListCallback = callback
end

function AdminPanelV3UI:bindClose(callback: () -> ())
	self._closeCallback = callback
end

function AdminPanelV3UI:bindPlayerSelected(callback: (PlayerEntry) -> ())
	self._playerSelectedCallback = callback
end

function AdminPanelV3UI:show()
	self:_bumpMotion()
	self._gui.Enabled = true
	-- Fill the panel before presenting it, so the pop plays over the finished
	-- layout instead of one that reflows mid-tween.
	self:refreshPlayers()
	self:_buildSizeButtons()
	self:_refreshChoiceLabels()
	self:_present(self._mainWrapper)
end

function AdminPanelV3UI:hide(immediate: boolean?)
	self:_bumpMotion()
	self:_destroyRowEffects()
	if self._presetSummaryEffect then
		pcall(function()
			self._presetSummaryEffect:Destroy()
		end)
		self._presetSummaryEffect = nil
	end

	-- Whichever of the three is on screen plays the dismissal; the others take the
	-- immediate path. The ScreenGui only goes dark once every one of them has
	-- finished, or a closing picker would be cut off mid-flight.
	local pending = 3
	local done = false
	local function step()
		pending -= 1
		if pending <= 0 and not done then
			done = true
			self._gui.Enabled = false
		end
	end
	self:_dismiss(self._presetModal, immediate, step)
	self:_dismiss(self._typefaceModal, immediate, step)
	self:_dismiss(self._mainWrapper, immediate, step)
end

-- True while any of the three surfaces is up — a picker is on its own once it has
-- taken over from the panel, so the wrapper alone no longer answers this.
function AdminPanelV3UI:isVisible(): boolean
	if self._gui.Enabled ~= true then
		return false
	end
	-- Built with an explicit index so a place missing one picker does not cut the
	-- scan short the way a nil hole in an ipairs list would.
	local surfaces = { self._mainWrapper, self._presetModal, self._typefaceModal }
	for i = 1, 3 do
		local target = surfaces[i]
		if target and target:IsA("GuiObject") and target.Visible then
			return true
		end
	end
	return false
end

return AdminPanelV3UI
