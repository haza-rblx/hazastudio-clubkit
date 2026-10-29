--!strict
-- Client/UI/CustomTitleUI.luau
-- Drives the buyer-installed `1000-01-CT-ADDON` ScreenGui: the self-service custom
-- title panel plus its color-preset and typeface pickers, which open as a stacked
-- sheet over the card.
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
local UIMotion = require(script.Parent.Parent.Utils.UIMotion)

local CustomTitleUI = {}
CustomTitleUI.__index = CustomTitleUI

export type TitleForm = {
	title: string,
	size: string,
	preset: string?,
	font: string?,
}

local DEFAULT_SIZE = "M"
-- Grace period after the close's own duration before the exit hook runs anyway, since
-- AnimationHelper can skip the dismissal callback it was waiting on.
local HANDOFF_SAFETY = 0.12
-- Shown on the preset/typeface buttons when the player has picked neither; the
-- overhead falls back to the nametag template's own look in that case.
local NO_PRESET_LABEL = "DEFAULT"
local NO_FONT_LABEL = "DEFAULT"
-- Picker navigation (stacked sheet): a picker rises over the main card while the card
-- shrinks and dims behind it, and drops back the same way.
local PUSH_TIME = 0.45
local POP_TIME = 0.3
-- Picker centre sits this many gui px below the card centre, and the push starts this far below that.
local STACK_DROP = 44
local STACK_FROM = 420
local STACK_SHRINK = 0.92
local STACK_DIM = 0.55

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

	-- The shipped GUI can be built narrower than its card (281 vs 320), which overhangs the
	-- close button; the card's width wins. The list is centred so a shrunk card stays centred.
	local panelFrame = panel :: Frame
	local cardFrame = mainFrame :: GuiObject
	local panelList = panelFrame:FindFirstChildWhichIsA("UIListLayout")
	if panelList then
		panelList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	end
	if panelFrame.Size.X.Offset < cardFrame.Size.X.Offset then
		panelFrame.Size = UDim2.new(
			panelFrame.Size.X.Scale,
			cardFrame.Size.X.Offset,
			panelFrame.Size.Y.Scale,
			panelFrame.Size.Y.Offset
		)
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
	self._mainFrame = asFrame(mainFrame)
	-- Picker sheet state: live tweens keyed by instance, the picker on screen (nil when the
	-- card is showing), each picker's own UIScale, the card's shrink scale and dim, and the
	-- confirm label's designed text (captured once per label, before its first overwrite).
	self._slideTweens = {} :: { [Instance]: any }
	self._activePicker = nil :: Frame?
	self._pickerScale = {} :: { [Frame]: UIScale }
	self._stackScale = nil :: UIScale?
	self._stackDim = nil :: Frame?
	self._confirmText = {} :: { [TextLabel]: string }

	self._selectedSize = DEFAULT_SIZE
	self._selectedPreset = nil :: string?
	self._selectedFont = nil :: string?
	self._submitCallback = nil :: ((TitleForm) -> ())?
	self._removeCallback = nil :: (() -> ())?
	-- Owner hook (menu shell): its phone focus release. Nil until bindClose.
	self._onExit = nil :: (() -> ())?
	self._built = false

	-- Designed transparencies for every fade this panel plays, captured once per element. Strong
	-- keys on purpose (ADR 0011 addendum, 2026-09-17): a weak entry is dropped while the element is
	-- alive, and the next capture would then record a mid-cascade transparency as the design.
	-- Rebuilt picker rows keep their entries here until the panel goes — bytes per row.
	self._fadeBases = {} :: { [GuiObject]: number }
	-- What is currently painted: the server echoes a whole payload after any profile
	-- change, so both painters compare against these before they animate.
	self._choiceKey = nil :: string?
	self._quotaShown = nil :: number?

	self:_stackPickers()
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
			self:_bindMotion(button)
			button.Activated:Connect(function()
				if self._selectedSize ~= sizeKey then
					self._selectedSize = sizeKey
					self:_buildSizeButtons()
					-- The row was just rebuilt, so what pops is the fresh selected-state
					-- clone, not the button that was pressed.
					local chosen = self._sizeButtons[sizeKey]
					if chosen then
						UIMotion.pop(UIMotion.scaleTargetOf(chosen), 1.18)
					end
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
			self:_bindMotion(row)
			row.Activated:Connect(function()
				onPick(value)
			end)
		end
		-- Rows are cloned fresh on every (re)build, so their designed transparencies are
		-- recorded here, once per clone, before any fade touches them.
		self:_captureFades(row)
		row.Parent = scroll
		table.insert(state.rows, row)
	end
end

-- The picker's rows cascade in as it rises over the card, once its push has started.
function CustomTitleUI:_staggerPicker(modal: Instance)
	local state = self._pickerState[modal]
	if state and #state.rows > 0 then
		UIMotion.stagger(state.rows, self._fadeBases)
	end
end

-- A pick rebuilds the list, so the chosen row is a brand new selected-state clone:
-- fade its highlight up over the row it replaced and pop whatever inside it can scale
-- (the rows themselves sit in a UIListLayout, so they are never scaled or moved).
function CustomTitleUI:_flashPickedRow(modal: Instance, value: string)
	local row = findChild(findChild(modal, "ScrollingFrame"), "Entry_" .. value)
	if not row or not row:IsA("GuiObject") then
		return
	end
	local base = row.BackgroundTransparency
	row.BackgroundTransparency = 1
	UIMotion.tween(row, 0.18, { BackgroundTransparency = base })
	UIMotion.fadeIn(self:_captureFades(row), self._fadeBases)
	UIMotion.pop(UIMotion.scaleTargetOf(row), 1.12)
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
		self:_bindMotion(self._submit)
		self._submit.Activated:Connect(function()
			self:_submitForm()
		end)
	end

	if self._remove and self._remove:IsA("GuiButton") then
		self._remove.AutoButtonColor = false
		self:_bindMotion(self._remove)
		self._remove.Activated:Connect(function()
			-- The owner's remove callback releases the phone focus before the write goes out, so
			-- the panel is not left sitting under the dim overlay while the server answers.
			if self._removeCallback then
				self._removeCallback()
			end
			self:close()
		end)
	end

	if self._presetButton and self._presetButton:IsA("GuiButton") then
		self._presetButton.AutoButtonColor = false
		self:_bindMotion(self._presetButton)
		self._presetButton.Activated:Connect(function()
			self:_openPresetPicker()
		end)
	end

	if self._typefaceButton and self._typefaceButton:IsA("GuiButton") then
		self._typefaceButton.AutoButtonColor = false
		self:_bindMotion(self._typefaceButton)
		self._typefaceButton.Activated:Connect(function()
			self:_openTypefacePicker()
		end)
	end

	-- Optional chrome the buyer may not have added yet. Resolved by descendant
	-- rather than direct child: the close control lives in whatever header or drag
	-- bar the buyer builds around the panel, so its depth is theirs to change.
	-- Both of these close the panel from inside it, where the dim overlay cannot see
	-- the tap, so each hands the phone focus back once its dismissal has landed.
	self:_bindIfButton(self._panel:FindFirstChild("CloseButton", true), function()
		CustomTitleUI.close(self, false, self._onExit)
	end)
	for _, modal in ipairs({ self._presetModal, self._typefaceModal }) do
		if modal then
			local function hidePicker()
				self:_closePicker(modal)
			end
			self:_bindIfButton(modal:FindFirstChild("BackButton", true), hidePicker)
			self:_bindIfButton(findChild(modal, "ConfirmButton"), hidePicker)
		end
	end
	local backdrop = findChild(self._gui, "Backdrop")
	self:_bindIfButton(backdrop, function()
		CustomTitleUI.close(self, false, self._onExit)
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
		self:_bindMotion(instance)
		instance.Activated:Connect(callback)
	end
end

-- Press squash + hover lift (ADR 0011). UIMotion hands its connections back and one of
-- them lives on UserInputService, so each button owns its own: a picker row destroyed
-- by the next rebuild must not leave a listener behind.
function CustomTitleUI:_bindMotion(button: GuiObject)
	local connections = UIMotion.bindPress(button)
	for _, connection in ipairs(UIMotion.bindHover(button)) do
		table.insert(connections, connection)
	end
	if #connections == 0 then
		return
	end
	button.Destroying:Once(function()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
	end)
end

-- The designed transparency of every text/image element under `root` (UIMotion ignores
-- the rest), recorded once per element so a second fade never fades to invisible.
-- Returns the elements, ready to hand to `fadeIn`.
function CustomTitleUI:_captureFades(root: Instance): { GuiObject }
	local elements: { GuiObject } = {}
	if root:IsA("GuiObject") then
		table.insert(elements, root)
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			table.insert(elements, descendant)
		end
	end
	local fresh: { GuiObject } = {}
	for _, element in ipairs(elements) do
		if self._fadeBases[element] == nil then
			table.insert(fresh, element)
		end
	end
	UIMotion.captureBases(fresh, self._fadeBases)
	return elements
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
-- `onClosed` is the exit hook of the owner-driven close() alone: it runs whichever
-- way the frame leaves the screen (tween done, tween cancelled, already hidden),
-- once per close(), so a caller can hand back phone panel focus without depending
-- on a callback AnimationHelper is free to skip.
function CustomTitleUI:_dismiss(
	frame: Frame?,
	immediate: boolean?,
	onDone: (() -> ())?,
	onClosed: (() -> ())?
)
	if not frame then
		if onDone then
			onDone()
		end
		if onClosed then
			onClosed()
		end
		return
	end
	if immediate or not frame.Visible then
		self._anim:cancelPanel(frame)
		resetModalVisual(frame)
		if onDone then
			onDone()
		end
		if onClosed then
			onClosed()
		end
		return
	end
	self._anim:dismissCenterPanel(frame, function()
		resetModalVisual(frame)
		if onDone then
			onDone()
		end
		if onClosed then
			onClosed()
		end
	end)
end

-- Anything that decides what should be on screen invalidates a pending hide.
function CustomTitleUI:_bumpMotion()
	self._motionGen = (self._motionGen or 0) + 1
end

function CustomTitleUI:_pickerModals(): { Frame }
	local modals: { Frame } = {}
	if self._presetModal then
		table.insert(modals, self._presetModal)
	end
	if self._typefaceModal then
		table.insert(modals, self._typefaceModal)
	end
	return modals
end

-- Stack both pickers as sheets over the main card. Each picker is parented to the
-- ScreenGui rather than the card, so it rises above the card's own clipping and layout.
-- The card gets a shrink scale and a dim overlay that the push drives; the dim is only
-- visible (and so only takes input) while a picker is up.
function CustomTitleUI:_stackPickers()
	local main = self._mainFrame
	if not main then
		return
	end
	for _, modal in ipairs(self:_pickerModals()) do
		modal.Parent = self._gui
		modal.AnchorPoint = Vector2.new(0.5, 0.5)
		modal.ZIndex = 20
		modal.Active = true
		modal.Visible = false
		local uiScale = modal:FindFirstChildWhichIsA("UIScale")
		if not uiScale then
			uiScale = Instance.new("UIScale")
			uiScale.Parent = modal
		end
		uiScale.Scale = 1
		self._pickerScale[modal] = uiScale
	end

	local stack = Instance.new("UIScale")
	stack.Name = "StackScale"
	stack.Scale = 1
	stack.Parent = main
	self._stackScale = stack

	local dim = Instance.new("Frame")
	dim.Name = "StackDim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.ZIndex = 50
	dim.Active = true
	dim.Visible = false
	local cardCorner = main:FindFirstChildWhichIsA("UICorner")
	local corner = Instance.new("UICorner")
	corner.CornerRadius = if cardCorner then cardCorner.CornerRadius else UDim.new(0, 24)
	corner.Parent = dim
	dim.Parent = main
	self._stackDim = dim
end

-- Where a picker's centre rests, in ScreenGui pixels: the card's centre (measured while
-- the card is still at rest), dropped by STACK_DROP. Divided by the ScreenGui's own root
-- UIScale, since offsets in the gui are scaled by it.
function CustomTitleUI:_pickerBase(): Vector2
	local main = self._mainFrame :: GuiObject
	local rootScale = self._gui:FindFirstChildWhichIsA("UIScale")
	local root = if rootScale then rootScale.Scale else 1
	local centre = (main.AbsolutePosition + main.AbsoluteSize / 2 - self._gui.AbsolutePosition) / root
	return Vector2.new(centre.X, centre.Y + STACK_DROP)
end

-- Stop whatever tween is running on an instance, leaving it where it is.
function CustomTitleUI:_cancelTween(inst: Instance)
	local previous = self._slideTweens[inst]
	if previous then
		previous:Cancel()
		self._slideTweens[inst] = nil
	end
end

-- Tween one instance's properties, cancelling whatever tween it was already running.
function CustomTitleUI:_tween(
	inst: Instance,
	props: { [string]: any },
	time: number,
	style: Enum.EasingStyle,
	dir: Enum.EasingDirection
): any
	self:_cancelTween(inst)
	local tween = game:GetService("TweenService"):Create(inst, TweenInfo.new(time, style, dir), props)
	self._slideTweens[inst] = tween
	tween:Play()
	return tween
end

-- Put both pickers away and the card back at rest, with no animation. Used on open and
-- close so no picker is ever left mid-sheet.
function CustomTitleUI:_resetPickers()
	self._activePicker = nil
	for _, tween in pairs(self._slideTweens) do
		tween:Cancel()
	end
	table.clear(self._slideTweens)
	for _, modal in ipairs(self:_pickerModals()) do
		modal.Visible = false
		local uiScale = self._pickerScale[modal]
		if uiScale then
			uiScale.Scale = 1
		end
	end
	if self._stackScale then
		self._stackScale.Scale = 1
	end
	if self._stackDim then
		self._stackDim.BackgroundTransparency = 1
		self._stackDim.Visible = false
	end
end

-- A picker rises over the card: the card shrinks and dims behind it, and the picker's
-- rows cascade in once it has arrived.
function CustomTitleUI:_openPicker(modal: Frame, build: () -> ())
	build()
	self:_bumpMotion()
	-- Measured while the card is still at rest, before its shrink tween starts.
	local base = self:_pickerBase()
	local uiScale = self._pickerScale[modal]
	if uiScale then
		self:_cancelTween(uiScale)
		uiScale.Scale = 1
	end
	modal.Position = UDim2.fromOffset(base.X, base.Y + STACK_FROM)
	modal.Visible = true
	local quint = Enum.EasingStyle.Quint
	local out = Enum.EasingDirection.Out
	self:_tween(modal, { Position = UDim2.fromOffset(base.X, base.Y) }, PUSH_TIME, quint, out)
	if self._stackScale then
		self:_tween(self._stackScale, { Scale = STACK_SHRINK }, PUSH_TIME, quint, out)
	end
	if self._stackDim then
		self._stackDim.Visible = true
		self:_tween(self._stackDim, { BackgroundTransparency = STACK_DIM }, PUSH_TIME, quint, out)
	end
	self:_setPicked(modal, false)
	self:_staggerPicker(modal)
	self._activePicker = modal
end

-- Back out of a picker: it shrinks away, and the card rises back to rest. Its preset
-- animations stop with it — only the preset picker creates any, so this is a no-op for
-- the typeface one. The picker is hidden once the shrink lands, unless a newer
-- interaction has moved on first.
function CustomTitleUI:_closePicker(modal: Frame)
	self:_destroyRowEffects()
	self:_bumpMotion()
	local gen = self._motionGen
	local cubic = Enum.EasingStyle.Cubic
	local inDir = Enum.EasingDirection.In
	-- A push still rising is stopped where it is, so the picker shrinks in place.
	self:_cancelTween(modal)
	local uiScale = self._pickerScale[modal]
	if uiScale then
		local tween = self:_tween(uiScale, { Scale = 0 }, POP_TIME, cubic, inDir)
		tween.Completed:Once(function()
			if gen == self._motionGen then
				modal.Visible = false
				uiScale.Scale = 1
			end
		end)
	else
		modal.Visible = false
	end
	if self._stackScale then
		self:_tween(self._stackScale, { Scale = 1 }, POP_TIME, cubic, inDir)
	end
	if self._stackDim then
		local dim = self._stackDim
		local tween = self:_tween(dim, { BackgroundTransparency = 1 }, POP_TIME, cubic, inDir)
		tween.Completed:Once(function()
			if gen == self._motionGen then
				dim.Visible = false
			end
		end)
	end
	self._activePicker = nil
end

-- The confirm button doubles as the picker's way back until a choice is made: it reads
-- the back label, then the designed text once the player has picked. A change of text
-- gets a small pop.
function CustomTitleUI:_setPicked(modal: Frame, picked: boolean)
	local confirm = findChild(modal, "ConfirmButton")
	local label = if confirm then confirm:FindFirstChildWhichIsA("TextLabel") else nil
	if not label then
		return
	end
	local designed = self._confirmText[label]
	if designed == nil then
		designed = label.Text
		self._confirmText[label] = designed
	end
	local goal = if picked then designed else (Config.CustomTitle.PICKER_BACK_LABEL or "Back")
	if label.Text == goal then
		return
	end
	label.Text = goal
	if picked and confirm and confirm:IsA("GuiButton") then
		UIMotion.pop(UIMotion.scaleTargetOf(confirm), 1.12)
	end
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
			self:_setPicked(modal, true)
			rebuild()
			self:_flashPickedRow(modal, value)
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
			self:_setPicked(modal, true)
			rebuild()
			self:_flashPickedRow(modal, value)
		end)
	end
	self:_openPicker(modal, rebuild)
end

-- The two summary labels are this panel's preview of the title being built. An
-- unchanged pick returns early: repainting the preset would tear down and rebuild its
-- RenderStepped effect for nothing. `close()` clears the key, because it destroys the
-- effect this would then skip.
function CustomTitleUI:_refreshChoiceLabels()
	local key = (self._selectedPreset or "") .. "|" .. (self._selectedFont or "")
	if self._choiceKey == key then
		return
	end
	local first = self._choiceKey == nil
	self._choiceKey = key

	local faded: { GuiObject } = {}
	if self._presetButton then
		local name = self._presetButton:FindFirstChild("PresetName")
		if name and name:IsA("TextLabel") then
			self:_captureFades(name)
			table.insert(faded, name)
			name.Text = self._selectedPreset or NO_PRESET_LABEL
			self:_paintPresetSummary(name)
		end
	end
	if self._typefaceButton then
		local name = self._typefaceButton:FindFirstChild("TypefaceName")
		if name and name:IsA("TextLabel") then
			self:_captureFades(name)
			table.insert(faded, name)
			name.Text = self._selectedFont or NO_FONT_LABEL
			TitleFontUtil.applyToTextLabel(name, self._selectedFont)
		end
	end
	-- A pick made on screen reads in; the first paint and the one open() does before
	-- the panel is up just land.
	if not first and self:isOpen() then
		UIMotion.fadeIn(faded, self._fadeBases)
	end
end

function CustomTitleUI:_submitForm()
	if not self._submitCallback then
		return
	end
	-- The server answers an empty title with MSG_TITLE_EMPTY and spends no quota on it,
	-- so the refusal is shown where it happened — the field shakes and the panel stays
	-- open — instead of closing and surfacing a toast. Remove is what clears a title.
	if self._input.Text:match("^%s*$") then
		UIMotion.wiggle(self._input, 6)
		return
	end
	-- No acknowledgement comes back to this panel, so the pop is on the form being
	-- sendable; it plays over the closing panel. On a phone the focus goes back as the
	-- dismissal lands, so the other GUIs are not left disabled while the form settles.
	UIMotion.pop(UIMotion.scaleTargetOf(self._submit), 1.2)
	self._submitCallback({
		title = self._input.Text,
		size = self._selectedSize,
		preset = self._selectedPreset,
		font = self._selectedFont,
	} :: TitleForm)
	CustomTitleUI.close(self, false, self._onExit)
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

-- The owner (the menu shell) is the only one that knows what the panel is sitting on — on a
-- phone the panel takes the shared mobile panel focus, which has to come back when the panel
-- goes. `onExit` runs as the dismissal lands, never on the creation-time close(true), so wiring
-- it here is safe at any time.
function CustomTitleUI:bindClose(onExit: (() -> ())?)
	self._onExit = onExit
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
		local function render(value: number): string
			return string.format("%d of %d title changes left this week.", value, max)
		end
		-- Only the plain countdown is a number rolling; every other line is a sentence.
		local counts = true
		local text = render(remaining)
		local resetsAt = tonumber(payload.customTitleResetsAt)
		if payload.customTitleFreeAvailable == true then
			-- The free slot is what is opening the panel: the rolling quota is not
			-- what they are spending, so counting it down would mislead.
			text = Config.CustomTitle.MSG_FREE_TITLE
			counts = false
		elseif payload.customTitleUnlimited == true then
			-- The buyer runs without a quota: counting down would be a lie.
			text = "Change your title as often as you like."
			counts = false
		elseif remaining <= 0 and resetsAt then
			local hours = math.max(1, math.ceil((resetsAt - os.time()) / 3600))
			text = if hours >= 24
				then string.format("No changes left. One returns in %d day(s).", math.ceil(hours / 24))
				else string.format("No changes left. One returns in %d hour(s).", hours)
			counts = false
		end
		-- A slot spent while the panel is up counts down instead of jumping. Any other
		-- payload — and every one that arrives behind a closed panel — is written
		-- straight in, and an unchanged line is not touched at all.
		local previous = self._quotaShown
		if counts and previous ~= nil and previous ~= remaining and self:isOpen() then
			UIMotion.countTo(self._quotaLabel, previous, remaining, 0.5, render)
		elseif self._quotaLabel.Text ~= text then
			self._quotaLabel.Text = text
		end
		self._quotaShown = if counts then remaining else nil
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
	self:_resetPickers()
	-- A fresh open starts from what is stored, so the form is loaded here and
	-- nowhere else.
	self:applyPayload(payload, true)
	if self._backdrop then
		self._backdrop.Visible = true
	end
	self:_present(self._panel)

	-- The form arrives under the panel's own pop: its rows drop in through the
	-- content's own UIPadding (equal and opposite, so nothing resizes) and cascade.
	if self._content and self._content:IsA("GuiObject") then
		UIMotion.slideInVertical(self._content, -1, 14)
		local rows: { GuiObject } = {}
		for _, child in ipairs(self._content:GetChildren()) do
			if child:IsA("GuiObject") and child.Visible then
				table.insert(rows, child)
				self:_captureFades(child)
			end
		end
		UIMotion.stagger(rows, self._fadeBases)
	end
end

function CustomTitleUI:close(immediate: boolean?, onClosed: (() -> ())?)
	self:_bumpMotion()
	-- The exit hook belongs to this close alone. A reopen bumps the same counter, so a slow
	-- dismissal that a newer open superseded cannot release the fresh panel's phone focus.
	local gen = self._motionGen
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
	-- The summary effect went with it, so the next open() has to repaint even when the
	-- preset and typeface did not change.
	self._choiceKey = nil
	-- Whichever of the three is on screen plays the same dismissal; the other two
	-- take the immediate path, since _dismiss no-ops on an already-hidden frame.
	-- The exit hook fires on the first of them to land, with a timer as the floor:
	-- AnimationHelper drops a dismissal callback whenever that tween is cancelled or
	-- superseded, and a hook chained only off it would then never run.
	local fired = false
	local function finish()
		if fired or gen ~= self._motionGen then
			return
		end
		fired = true
		if onClosed then
			onClosed()
		end
	end
	-- The pickers stand outside the card, so an open one shrinks away alongside the card's
	-- own dismissal instead of snapping off first. Once the card is gone the pickers are
	-- parked (gen-guarded); open() resets too, covering a dismissal callback AnimationHelper
	-- skipped. An immediate close resets at once through that same callback.
	if not immediate and self._activePicker then
		local uiScale = self._pickerScale[self._activePicker]
		if uiScale then
			self:_tween(uiScale, { Scale = 0 }, POP_TIME, Enum.EasingStyle.Cubic, Enum.EasingDirection.In)
		end
	end
	local function resetNested()
		if gen == self._motionGen then
			self:_resetPickers()
		end
	end
	self:_dismiss(self._panel, immediate, resetNested, finish)
	task.delay(MotionPresets.centerClose().time + HANDOFF_SAFETY, finish)
	if self._backdrop then
		self._backdrop.Visible = false
	end
end

function CustomTitleUI:isOpen(): boolean
	return self._panel.Visible == true
end

return CustomTitleUI
