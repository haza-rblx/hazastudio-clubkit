--!strict
-- Client/UI/CustomTitleUI.luau
-- Drives the buyer-installed `1000-01-CT-ADDON` ScreenGui: the self-service custom
-- title panel plus its color-preset and typeface pickers.
--
-- The GUI is place data, not engine, so a buyer can be running the feature flag
-- with an older StarterGui. `tryCreate` returns nil whenever the ScreenGui or any
-- ref it cannot work without is missing, and the caller falls back to the old
-- text-only modal rather than presenting a dead button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local TitleColorPreset = require(ReplicatedStorage.Hazastudio_ClubKit.OverheadEffects.TitleColorPreset)
local AnimationModes = TitleColorPreset.AnimationModes
local TitleFontUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.TitleFontUtil)
local TitleEventDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.TitleEventDomain)
local DonationAmountFormat = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DonationAmountFormat)
local PresetPreview = require(script.Parent.Parent.Utils.PresetPreview)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
local MotionPresets = require(script.Parent.Parent.Utils.MotionPresets)

local CustomTitleUI = {}
CustomTitleUI.__index = CustomTitleUI

export type TitleForm = {
	title: string,
	size: string,
	preset: string?,
	font: string?,
}

local DEFAULT_SIZE = "M"
-- Grace period after a dismissal's own duration before the handoff gives up on
-- its callback and shows the incoming frame itself.
local HANDOFF_SAFETY = 0.12
-- Shown on the preset/typeface buttons when the player has picked neither; the
-- overhead falls back to the nametag template's own look in that case.
local NO_PRESET_LABEL = "DEFAULT"
local NO_FONT_LABEL = "DEFAULT"

local function findChild(parent: Instance?, name: string): Instance?
	return if parent then parent:FindFirstChild(name) else nil
end

-- Pull a template out of the layout and keep it in memory to clone from.
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
local function resetModalVisual(frame: Frame)
	local uiScale = frame:FindFirstChildWhichIsA("UIScale")
	if uiScale then
		uiScale.Scale = 1
	end
	frame.Visible = false
end

-- One requirement, worded for a player: "Reach Lv 25", "donate 100 R$",
-- "donate Rp 50.000" (cash follows the venue's own currency).
local function describeRequirement(entry: any): string
	local amount = math.max(1, math.floor(tonumber(entry.requirement) or 1))
	if entry.axis == "robux" then
		return string.format(Config.CustomTitle.UNLOCK_ROBUX, amount)
	elseif entry.axis == "cash" then
		return string.format(Config.CustomTitle.UNLOCK_CASH, DonationAmountFormat.formatCash(amount))
	end
	return string.format(Config.CustomTitle.UNLOCK_LEVEL, amount)
end

-- The whole locked line, built from the routes the server said exist: clauses
-- inside a route joined by "and", the routes themselves by "or". With no event
-- configured there is exactly one route and this reads as it always did.
local function describeUnlock(payload: any): string
	local routes = TitleEventDomain.describeRoutes({
		active = payload.titleEventActive == true,
		mode = tostring(payload.titleEventMode),
		met = payload.titleEventMet == true,
		requirements = if type(payload.titleEventRequirements) == "table"
			then payload.titleEventRequirements
			else {},
	} :: any, payload.customTitleMinLevel or Config.CustomTitle.MIN_LEVEL)

	local phrases: { string } = {}
	for _, route in ipairs(routes) do
		local clauses: { string } = {}
		for _, entry in ipairs(route) do
			table.insert(clauses, describeRequirement(entry))
		end
		table.insert(phrases, table.concat(clauses, Config.CustomTitle.UNLOCK_AND))
	end
	local sentence = table.concat(phrases, Config.CustomTitle.UNLOCK_OR)
	sentence = sentence:gsub("^%l", string.upper)
	return string.format(Config.CustomTitle.MSG_LOCKED_PANEL, sentence)
end

local function setLabelText(root: Instance?, label: string)
	if not root then
		return
	end
	local text = root:FindFirstChildWhichIsA("TextLabel")
	if text then
		text.Text = label
	end
end

local paintPreset = PresetPreview.paint

-- `anim` is the menu shell's own AnimationHelper, so this panel opens and closes
-- with the same motion as the modal it replaces. A fresh one is harmless if a
-- caller has none: the helper is stateless and its tween bookkeeping is
-- module-level, keyed per instance.
function CustomTitleUI.tryCreate(playerGui: Instance, anim: any?): any?
	local gui = playerGui:FindFirstChild(Config.CustomTitle.GUI_NAME)
	if not gui or not gui:IsA("ScreenGui") then
		return nil
	end

	local panel = findChild(gui, "CustomTitleModal")
	local mainFrame = findChild(panel, "MainFrame")
	local content = findChild(mainFrame, "MainContentWrapper")
	local input = findChild(content, "InputTitleText")
	local submit = findChild(mainFrame, "SubmitButton")
	if
		not (panel and panel:IsA("Frame"))
		or not (input and input:IsA("TextBox"))
		or not (submit and submit:IsA("GuiButton"))
	then
		return nil
	end

	local sizeRow = findChild(content, "02-SelectSizeInput")
	local sizeNormal = takeTemplate(sizeRow, "NormalState")
	local sizeSelected = takeTemplate(sizeRow, "SelectedState")
	if not sizeNormal or not sizeSelected then
		return nil
	end

	local self = setmetatable({}, CustomTitleUI) :: any
	self._anim = anim or AnimationHelper.new()
	self._gui = gui
	self._panel = panel
	self._content = content
	self._input = input
	self._submit = submit
	self._remove = findChild(content, "RemoveButton")
	self._quotaLabel = findChild(content, "QuotaLabel")
	self._lockedState = findChild(mainFrame, "LockedState")
	self._presetButton = findChild(content, "SelectPresetButton")
	self._typefaceButton = findChild(content, "SelectTypefaceButton")
	self._sizeRow = sizeRow
	self._sizeNormal = sizeNormal
	self._sizeSelected = sizeSelected
	self._sizeButtons = {} :: { [string]: GuiObject }

	self._presetModal = asFrame(findChild(gui, "SelectPresetModal"))
	self._typefaceModal = asFrame(findChild(gui, "SelectTypefaceModal"))

	self._selectedSize = DEFAULT_SIZE
	self._selectedPreset = nil :: string?
	self._selectedFont = nil :: string?
	self._submitCallback = nil :: ((TitleForm) -> ())?
	self._removeCallback = nil :: (() -> ())?
	self._built = false

	self:_wire()
	-- Start from a known-closed state whatever the template was saved as, so a
	-- panel left `Visible = true` in StarterGui does not sit on screen. No tween
	-- here — nothing has been shown yet.
	self:close(true)
	return self
end

-- ============================================================
-- Build
-- ============================================================

function CustomTitleUI:_buildSizeButtons()
	for _, button in pairs(self._sizeButtons) do
		button:Destroy()
	end
	table.clear(self._sizeButtons)

	local order = Config.Admin.TITLE_SIZE_ORDER or { DEFAULT_SIZE }
	for index, sizeKey in ipairs(order) do
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

-- Fill one picker's scroll from `entries`, marking `current` selected. `decorate`
-- gets the row and its value so each picker can paint itself: the typeface one
-- renders every name in its own face, the preset one in its own preset.
function CustomTitleUI:_buildPicker(
	modal: Instance,
	entries: { string },
	current: string?,
	decorate: ((GuiObject, string) -> ())?,
	onPick: (string) -> ()
)
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

	-- Each live preset effect owns a RenderStepped loop, so they must be torn
	-- down before the rows they paint are destroyed, or a rebuild leaks one
	-- animation per row.
	self:_destroyRowEffects()
	for _, row in ipairs(state.rows) do
		row:Destroy()
	end
	table.clear(state.rows)

	for index, value in ipairs(entries) do
		local isCurrent = value == current
		local row = (if isCurrent then state.selected else state.normal):Clone()
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
-- Wiring
-- ============================================================

function CustomTitleUI:_wire()
	self._pickerState = {} :: any
	self._rowEffects = {} :: { any }
	self._presetSummaryEffect = nil :: any

	if self._submit:IsA("GuiButton") then
		self._submit.AutoButtonColor = false
		self._submit.Activated:Connect(function()
			self:_submitForm()
		end)
	end

	if self._remove and self._remove:IsA("GuiButton") then
		self._remove.AutoButtonColor = false
		self._remove.Activated:Connect(function()
			if self._removeCallback then
				self._removeCallback()
			end
			self:close()
		end)
	end

	if self._presetButton and self._presetButton:IsA("GuiButton") then
		self._presetButton.AutoButtonColor = false
		self._presetButton.Activated:Connect(function()
			self:_openPresetPicker()
		end)
	end

	if self._typefaceButton and self._typefaceButton:IsA("GuiButton") then
		self._typefaceButton.AutoButtonColor = false
		self._typefaceButton.Activated:Connect(function()
			self:_openTypefacePicker()
		end)
	end

	-- Optional chrome the buyer may not have added yet. Resolved by descendant
	-- rather than direct child: the close control lives in whatever header or drag
	-- bar the buyer builds around the panel, so its depth is theirs to change.
	self:_bindIfButton(self._panel:FindFirstChild("CloseButton", true), function()
		self:close()
	end)
	for _, modal in ipairs({ self._presetModal, self._typefaceModal }) do
		if modal then
			local function hidePicker()
				self:_closePicker(modal)
			end
			self:_bindIfButton(findChild(modal, "BackButton"), hidePicker)
			self:_bindIfButton(findChild(modal, "ConfirmButton"), hidePicker)
		end
	end
	local backdrop = findChild(self._gui, "Backdrop")
	self:_bindIfButton(backdrop, function()
		self:close()
	end)
	self._backdrop = if backdrop and backdrop:IsA("GuiObject") then backdrop else nil
end

function CustomTitleUI:_destroyRowEffects()
	for _, effect in ipairs(self._rowEffects) do
		pcall(function()
			effect:Destroy()
		end)
	end
	table.clear(self._rowEffects)
end

-- Paint one preset row, tracking the effect with the rest of the picker's rows.
function CustomTitleUI:_applyPresetPreview(row: GuiObject, presetMode: string)
	local label = row:FindFirstChildWhichIsA("TextLabel")
	if not label then
		return
	end
	local effect = paintPreset(label, presetMode)
	if effect then
		table.insert(self._rowEffects, effect)
	end
end

-- The preset name on the main panel gets the same treatment as a picker row, so
-- the summary reads as the preset rather than as plain text — the typeface button
-- beside it already shows its own face. Its effect is tracked on its own, apart
-- from the picker rows, so closing the picker does not strip it.
function CustomTitleUI:_paintPresetSummary(label: TextLabel)
	if self._presetSummaryEffect then
		pcall(function()
			self._presetSummaryEffect:Destroy()
		end)
		self._presetSummaryEffect = nil
	end
	if self._selectedPreset then
		self._presetSummaryEffect = paintPreset(label, self._selectedPreset)
	end
end

function CustomTitleUI:_bindIfButton(instance: Instance?, callback: () -> ())
	if instance and instance:IsA("GuiButton") then
		instance.AutoButtonColor = false
		instance.Activated:Connect(callback)
	end
end

-- ============================================================
-- Motion — the same center-panel pop the menu shell gives the modal this panel
-- replaces, so the three frames read as one family.
-- ============================================================

function CustomTitleUI:_present(frame: Frame, onDone: (() -> ())?)
	self._anim:cancelPanel(frame)
	self._anim:presentCenterPanel(frame, onDone)
end

-- `immediate` skips the tween for state resets (creation, an already-hidden
-- frame), where a dismissal would otherwise flash the frame on screen to play it.
function CustomTitleUI:_dismiss(frame: Frame?, immediate: boolean?, onDone: (() -> ())?)
	if not frame then
		if onDone then
			onDone()
		end
		return
	end
	if immediate or not frame.Visible then
		self._anim:cancelPanel(frame)
		resetModalVisual(frame)
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
function CustomTitleUI:_handoff(from: Frame?, to: Frame?)
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
function CustomTitleUI:_bumpMotion()
	self._motionGen = (self._motionGen or 0) + 1
end

-- A picker takes over the screen rather than stacking on top of the panel.
function CustomTitleUI:_openPicker(modal: Frame, build: () -> ())
	build()
	self:_handoff(self._panel, modal)
end

-- Back out of a picker: it hands the screen back to the panel it was opened
-- from. Its preset animations stop with it — only the preset picker creates any,
-- so this is a no-op for the typeface one.
function CustomTitleUI:_closePicker(modal: Frame)
	self:_destroyRowEffects()
	self:_handoff(modal, self._panel)
end

function CustomTitleUI:_openPresetPicker()
	local modal = self._presetModal
	if not modal then
		return
	end
	local presets = AnimationModes.GetPresetModes()
	local function decorate(row: GuiObject, value: string)
		self:_applyPresetPreview(row, value)
	end
	-- Rebuild through the same closure after a pick, so the newly drawn rows keep
	-- working handlers and the selection can be changed again without reopening.
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

function CustomTitleUI:_openTypefacePicker()
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

function CustomTitleUI:_refreshChoiceLabels()
	if self._presetButton then
		local name = self._presetButton:FindFirstChild("PresetName")
		if name and name:IsA("TextLabel") then
			name.Text = self._selectedPreset or NO_PRESET_LABEL
			self:_paintPresetSummary(name)
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

function CustomTitleUI:_submitForm()
	if not self._submitCallback then
		return
	end
	self._submitCallback({
		title = self._input.Text,
		size = self._selectedSize,
		preset = self._selectedPreset,
		font = self._selectedFont,
	} :: TitleForm)
	self:close()
end

-- ============================================================
-- Public
-- ============================================================

function CustomTitleUI:bindSubmit(callback: (TitleForm) -> ())
	self._submitCallback = callback
end

function CustomTitleUI:bindRemove(callback: () -> ())
	self._removeCallback = callback
end

-- Load the stored title into the form. Only on a fresh open: this is the half of
-- the panel the player edits, and the server echoes a payload after *any* profile
-- change — an admin action, a couple event, another field's update — so repainting
-- it live would wipe text they are still typing and picks they have not saved yet.
function CustomTitleUI:_paintForm(payload: any)
	self._input.Text = payload.specialTitle or ""
	self._selectedSize = payload.specialTitleSize or DEFAULT_SIZE
	self._selectedPreset = payload.specialTitlePreset
	self._selectedFont = payload.specialTitleFont
	self:_buildSizeButtons()
	self:_refreshChoiceLabels()
end

-- Paint the panel from a ProfileMenuPayload. Safe to call while it is closed.
--
-- `resetForm` loads the stored values into the form; without it only the parts
-- the player does not edit are repainted (quota line, locked state, whether
-- Remove applies), so a live refresh never fights whoever is typing.
function CustomTitleUI:applyPayload(payload: any, resetForm: boolean?)
	if type(payload) ~= "table" then
		return
	end

	if resetForm then
		self:_paintForm(payload)
	end

	if self._quotaLabel and self._quotaLabel:IsA("TextLabel") then
		local remaining = tonumber(payload.customTitleRemaining) or 0
		local max = Config.CustomTitle.MAX_CHANGES_PER_WINDOW
		local text = string.format("%d of %d title changes left this week.", remaining, max)
		local resetsAt = tonumber(payload.customTitleResetsAt)
		if payload.customTitleFreeAvailable == true then
			-- The free slot is what is opening the panel: the rolling quota is not
			-- what they are spending, so counting it down would mislead.
			text = Config.CustomTitle.MSG_FREE_TITLE
		elseif payload.customTitleUnlimited == true then
			-- The buyer runs without a quota: counting down would be a lie.
			text = "Change your title as often as you like."
		elseif remaining <= 0 and resetsAt then
			local hours = math.max(1, math.ceil((resetsAt - os.time()) / 3600))
			text = if hours >= 24
				then string.format("No changes left. One returns in %d day(s).", math.ceil(hours / 24))
				else string.format("No changes left. One returns in %d hour(s).", hours)
		end
		self._quotaLabel.Text = text
	end

	-- Locked = the player may not edit at all. The message spells out every way in
	-- the buyer has actually configured, rather than the hardcoded level the
	-- template ships with.
	local locked = payload.canEditSpecialTitle ~= true
	if self._lockedState and self._lockedState:IsA("GuiObject") then
		self._lockedState.Visible = locked
		local message = self._lockedState:FindFirstChild("LockedMessage")
		if locked and message and message:IsA("TextLabel") then
			message.Text = describeUnlock(payload)
		end
	end
	if self._remove and self._remove:IsA("GuiObject") then
		self._remove.Visible = payload.specialTitle ~= nil
	end
end

function CustomTitleUI:open(payload: any)
	self:_bumpMotion()
	-- A fresh open starts from what is stored, so the form is loaded here and
	-- nowhere else.
	self:applyPayload(payload, true)
	if self._backdrop then
		self._backdrop.Visible = true
	end
	self:_present(self._panel)
end

function CustomTitleUI:close(immediate: boolean?)
	self:_bumpMotion()
	-- Stop the preset animations rather than leaving 33 RenderStepped loops
	-- running behind a closed panel. The summary's effect goes too; open() repaints
	-- it through applyPayload.
	self:_destroyRowEffects()
	if self._presetSummaryEffect then
		pcall(function()
			self._presetSummaryEffect:Destroy()
		end)
		self._presetSummaryEffect = nil
	end
	-- Whichever of the three is on screen plays the same dismissal; the other two
	-- take the immediate path, since _dismiss no-ops on an already-hidden frame.
	self:_dismiss(self._presetModal, immediate)
	self:_dismiss(self._typefaceModal, immediate)
	self:_dismiss(self._panel, immediate)
	if self._backdrop then
		self._backdrop.Visible = false
	end
end

function CustomTitleUI:isOpen(): boolean
	return self._panel.Visible == true
end

return CustomTitleUI
