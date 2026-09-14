--!strict
-- PATH: StarterPlayerScripts/Client/UI/Music/DjView.luau
-- DJ tab: DJ mode switch, soundboard, playback speed (slider + presets) and the sound effects
-- listed in Config.Music.DJ. The controller owns the values; setters here only mirror them, and a
-- change the controller refuses (not in DJ mode) snaps back. The panel's drag detector is already
-- off on this tab, so sliders need no drag suppression.

local UserInputService = game:GetService("UserInputService")

local GuiRefs = require(script.Parent.GuiRefs)
local MusicMotion = require(script.Parent.MusicMotion)
local Visuals = require(script.Parent.Visuals)

local SWITCH_TIME = 0.18
local FILL_TIME = 0.2

local SPEED_MIN, SPEED_MAX, SPEED_STEP = 0.25, 2, 0.05
local TOGGLE_DEBOUNCE = 0.18
local MODE_RESYNC_SECONDS = 2
local TRACK_ON = Color3.fromRGB(245, 245, 245)
local TRACK_OFF = Color3.fromRGB(55, 55, 62)
local THUMB_ON = Color3.fromRGB(18, 18, 22)
local THUMB_OFF = Color3.fromRGB(255, 255, 255)
local PRESET_NAMES = { "025", "050", "100", "150", "200" }

type Toggle = { button: TextButton, track: Frame, thumb: Frame, shown: boolean? }
type Slider = {
	host: GuiObject,
	fill: Frame,
	shownPercent: number?,
	label: TextLabel?,
	min: number,
	max: number,
	step: number,
	value: number,
	format: (number) -> string,
	onChange: (number) -> boolean,
	scroll: ScrollingFrame?,
	previousScrolling: boolean?,
}

local need = GuiRefs.need

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function trimNumber(value: number): string
	if math.abs(value - math.floor(value + 0.5)) < 0.001 then
		return tostring(math.floor(value + 0.5))
	end
	local text = (string.gsub(string.format("%.2f", value), "0+$", ""))
	return (string.gsub(text, "%.$", ""))
end

local function formatSpeed(value: number): string
	return trimNumber(math.max(0.05, value)) .. "x"
end

local function formatEffectValue(value: number, suffix: any): string
	local unit = tostring(suffix or "")
	if unit == "db" then
		if math.abs(value) < 0.001 then
			return "0db"
		end
		local rounded = if value >= 0 then math.floor(value + 0.5) else math.ceil(value - 0.5)
		return tostring(rounded) .. "db"
	end
	return trimNumber(value) .. unit
end

local function snap(raw: number, minValue: number, maxValue: number, step: number): number
	local safeStep = if step > 0 then step else 1
	return math.clamp(math.floor(raw / safeStep + 0.5) * safeStep, minValue, maxValue)
end

local DjView = {}
DjView.__index = DjView

function DjView.new(deps: { refs: GuiRefs.Refs, store: any, config: any, fire: (string, ...any) -> any })
	local self = setmetatable({}, DjView) :: any
	self._refs = deps.refs.dj
	self._soundBoardTemplate = deps.refs.soundBoardItemTemplate
	self._effectTemplate = deps.refs.effectTemplate
	self._store = deps.store
	self._fire = deps.fire
	self._djConfig = deps.config.DJ or {}
	self._sliders = {} :: { [string]: Slider }
	self._effectToggles = {} :: { [string]: Toggle }
	self._effectEnabled = {} :: { [string]: boolean }
	self._presets =
		{} :: { { value: number, button: TextButton, stroke: UIStroke?, baseTransparency: number, active: boolean? } }
	self._activeSlider = nil :: Slider?
	self._clones = {} :: { Instance }
	self._connections = {} :: { RBXScriptConnection }
	return self
end

function DjView:_connect(connection: RBXScriptConnection)
	table.insert(self._connections, connection)
end

-- ============================================================
-- Switches and sliders
-- ============================================================

-- Painting compares against the goal, not the live value: a tween in flight must not restart.
function DjView:_paintToggle(toggle: Toggle, enabled: boolean)
	if toggle.shown == enabled then
		return
	end
	-- The first paint is the design default, not a change the player made.
	local animate = toggle.shown ~= nil
	toggle.shown = enabled
	local trackGoal = { BackgroundColor3 = if enabled then TRACK_ON else TRACK_OFF }
	local thumbGoal = {
		AnchorPoint = Vector2.new(if enabled then 1 else 0, 0.5),
		Position = UDim2.new(if enabled then 1 else 0, 0, 0.5, 0),
		BackgroundColor3 = if enabled then THUMB_ON else THUMB_OFF,
	}
	if not animate then
		for property, value in pairs(trackGoal) do
			(toggle.track :: any)[property] = value
		end
		for property, value in pairs(thumbGoal) do
			(toggle.thumb :: any)[property] = value
		end
		return
	end
	MusicMotion.tween(toggle.track, SWITCH_TIME, trackGoal)
	MusicMotion.tween(toggle.thumb, SWITCH_TIME, thumbGoal, Enum.EasingStyle.Back)
end

function DjView:_paintSlider(slider: Slider, animate: boolean?)
	local percent = if slider.max > slider.min
		then math.clamp((slider.value - slider.min) / (slider.max - slider.min), 0, 1)
		else 0
	if slider.shownPercent ~= percent then
		slider.shownPercent = percent
		local goal = UDim2.new(percent, 0, 1, 0)
		if animate then
			MusicMotion.tween(slider.fill, FILL_TIME, { Size = goal }, Enum.EasingStyle.Quart)
		else
			MusicMotion.tween(slider.fill, 0, { Size = goal })
		end
	end
	if slider.label then
		Visuals.setText(slider.label, slider.format(slider.value))
	end
end

function DjView:_applyFromX(slider: Slider, x: number)
	local width = math.max(slider.host.AbsoluteSize.X, 1)
	local percent = math.clamp((x - slider.host.AbsolutePosition.X) / width, 0, 1)
	local nextValue = snap(slider.min + (slider.max - slider.min) * percent, slider.min, slider.max, slider.step)
	if nextValue ~= slider.value and slider.onChange(nextValue) then
		slider.value = nextValue
	end
	self:_paintSlider(slider)
end

function DjView:_endDrag()
	local slider = self._activeSlider
	if not slider then
		return
	end
	self._activeSlider = nil
	if slider.scroll and slider.previousScrolling ~= nil then
		slider.scroll.ScrollingEnabled = slider.previousScrolling
	end
	slider.previousScrolling = nil
end

function DjView:_bindSlider(
	host: GuiObject,
	fill: Frame,
	label: TextLabel?,
	range: { min: number, max: number, step: number, initial: number },
	format: (number) -> string,
	onChange: (number) -> boolean
): Slider
	local slider: Slider = {
		host = host,
		fill = fill,
		label = label,
		min = range.min,
		max = range.max,
		step = range.step,
		value = snap(range.initial, range.min, range.max, range.step),
		format = format,
		onChange = onChange,
		scroll = nil,
		previousScrolling = nil,
	}
	local function begin(input: InputObject)
		if not isPress(input) then
			return
		end
		self:_endDrag()
		-- Resolved on press: clones are parented after their sliders are bound.
		slider.scroll = host:FindFirstAncestorWhichIsA("ScrollingFrame")
		if slider.scroll then
			slider.previousScrolling = slider.scroll.ScrollingEnabled
			slider.scroll.ScrollingEnabled = false
		end
		self._activeSlider = slider
		self:_applyFromX(slider, input.Position.X)
	end
	host.Active = true
	fill.Active = true
	self:_connect(host.InputBegan:Connect(begin))
	self:_connect(fill.InputBegan:Connect(begin))
	self:_paintSlider(slider)
	return slider
end

-- ============================================================
-- Bind
-- ============================================================

function DjView:bind()
	local refs = self._refs
	local djConfig = self._djConfig
	refs.warning.Visible = false

	-- One pair of global listeners drives whichever slider is being dragged.
	self:_connect(UserInputService.InputChanged:Connect(function(input)
		local slider = self._activeSlider
		if
			slider
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			self:_applyFromX(slider, input.Position.X)
		end
	end))
	self:_connect(UserInputService.InputEnded:Connect(function(input)
		if self._activeSlider and isPress(input) then
			self:_endDrag()
		end
	end))

	local modeToggle: Toggle = { button = refs.modeToggle, track = refs.modeToggleTrack, thumb = refs.modeToggleThumb }
	self._modeToggle = modeToggle
	self:_paintToggle(modeToggle, self._store:get().isDjMode == true)
	local lastModeClick = 0
	self:_connect(refs.modeToggle.Activated:Connect(function()
		local now = os.clock()
		if now - lastModeClick < TOGGLE_DEBOUNCE then
			return
		end
		lastModeClick = now
		self:_paintToggle(modeToggle, not (self._store:get().isDjMode == true))
		self._fire("OnToggleDjMode")
		-- The controller pushes the new state only on success; a refused switch flips back here.
		task.delay(MODE_RESYNC_SECONDS, function()
			if not self._destroyed then
				self:_paintToggle(modeToggle, self._store:get().isDjMode == true)
			end
		end)
	end))

	for index, item in ipairs(djConfig.SOUND_BOARD_ITEMS or {}) do
		local itemId = tostring(item.id or index)
		local clone = self._soundBoardTemplate:Clone() :: TextButton
		clone.Name = itemId
		clone.LayoutOrder = index
		Visuals.setText(need(clone, "TextLabel", "TextLabel"), tostring(item.label or itemId))
		local label = need(clone, "TextLabel", "TextLabel")
		self:_connect(clone.Activated:Connect(function()
			MusicMotion.wiggle(clone, 4)
			MusicMotion.pop(MusicMotion.scaleTargetOf(label), 1.15)
			self._fire("OnDjSoundboardTriggered", itemId)
		end))
		clone.Visible = true
		clone.Parent = self._soundBoardTemplate.Parent
		table.insert(self._clones, clone)
	end

	self:_connect(refs.resetButton.Activated:Connect(function()
		MusicMotion.spin(refs.resetButton:FindFirstChildWhichIsA("ImageLabel"), -1)
		self._fire("OnDjResetRequested")
	end))
	for _, button in ipairs({ refs.resetButton, refs.modeToggle }) do
		for _, connection in ipairs(MusicMotion.bindPress(button)) do
			self:_connect(connection)
		end
	end

	self._sliders.speed = self:_bindSlider(
		refs.speedSliderHost,
		refs.speedSliderFill,
		refs.speedValueLabel,
		{ min = SPEED_MIN, max = SPEED_MAX, step = SPEED_STEP, initial = 1 },
		formatSpeed,
		function(value: number): boolean
			return self._fire("OnDjPlaybackSpeedChanged", value) ~= false
		end
	)
	for index, preset in ipairs(djConfig.PLAYBACK_SPEED_PRESETS or {}) do
		local buttonName = PRESET_NAMES[index]
		if not buttonName then
			break
		end
		local button = need(refs.speedPresetWrapper, buttonName, "TextButton") :: TextButton
		local value = tonumber(preset.value) or 1
		Visuals.setText(need(button, "TextLabel", "TextLabel"), tostring(preset.label or formatSpeed(value)))
		table.insert(self._presets, {
			value = value,
			button = button,
			stroke = button:FindFirstChildOfClass("UIStroke"),
			baseTransparency = button.BackgroundTransparency,
		})
		self:_connect(button.Activated:Connect(function()
			self._fire("OnDjPlaybackSpeedChanged", value)
		end))
		for _, connection in ipairs(MusicMotion.bindPress(button)) do
			self:_connect(connection)
		end
	end

	for index, effect in ipairs(djConfig.EFFECTS or {}) do
		self:_buildEffect(effect, index)
	end

	self:setPlaybackSpeed(1)
end

function DjView:_buildEffect(effect: any, index: number)
	local effectId = tostring(effect.id or index)
	local clone = self._effectTemplate:Clone()
	clone.Name = effectId
	clone.LayoutOrder = 100 + index

	local header = need(clone, "SectionHeader", "Frame")
	Visuals.setText(need(need(header, "SectionName", "Frame"), "TextLabel", "TextLabel"), tostring(effect.sectionName or effectId))
	local toggleButton = need(header, "Toggle", "TextButton") :: TextButton
	local track = need(toggleButton, "Frame", "Frame")
	local toggle: Toggle = { button = toggleButton, track = track, thumb = need(track, "Frame", "Frame") }
	self._effectToggles[effectId] = toggle
	self._effectEnabled[effectId] = effect.defaultEnabled == true
	self:_paintToggle(toggle, self._effectEnabled[effectId])
	local lastClick = 0
	self:_connect(toggleButton.Activated:Connect(function()
		local now = os.clock()
		if now - lastClick < TOGGLE_DEBOUNCE then
			return
		end
		lastClick = now
		local nextEnabled = not self._effectEnabled[effectId]
		if self._fire("OnDjEffectEnabledChanged", effectId, nextEnabled) ~= false then
			self._effectEnabled[effectId] = nextEnabled
		end
		self:_paintToggle(toggle, self._effectEnabled[effectId])
	end))

	local wrapper = need(clone, "Wrapper", "Frame")
	local itemTemplate = need(wrapper, "EffectItemTemplate", "Frame")
	itemTemplate.Visible = false
	for itemIndex, item in ipairs(effect.items or {}) do
		local itemId = tostring(item.id or item.property or itemIndex)
		local itemClone = itemTemplate:Clone()
		itemClone.Name = itemId
		itemClone.LayoutOrder = itemIndex
		local row = need(itemClone, "Item", "Frame")
		Visuals.setText(need(row, "ItemName", "TextLabel"), tostring(item.label or itemId))
		local host = need(need(itemClone, "Slider", "Frame"), "AdjustSpeedWrapper", "Frame")
		local suffix = item.suffix
		self._sliders[effectId .. "::" .. itemId] = self:_bindSlider(
			host,
			need(host, "AdjustableFrameWidth", "Frame"),
			need(row, "Value", "TextLabel"),
			{
				min = tonumber(item.min) or 0,
				max = tonumber(item.max) or 1,
				step = tonumber(item.step) or 0.05,
				initial = tonumber(item.defaultValue) or 0,
			},
			function(value: number): string
				return formatEffectValue(value, suffix)
			end,
			function(value: number): boolean
				return self._fire("OnDjEffectValueChanged", effectId, itemId, value) ~= false
			end
		)
		itemClone.Visible = true
		itemClone.Parent = wrapper
	end

	clone.Visible = true
	clone.Parent = self._effectTemplate.Parent
	table.insert(self._clones, clone)
end

-- ============================================================
-- Setters (driven by the controller)
-- ============================================================

function DjView:setDjMode(enabled: boolean)
	if self._modeToggle then
		self:_paintToggle(self._modeToggle, enabled == true)
	end
end

function DjView:setPlaybackSpeed(speed: number)
	local value = math.clamp(tonumber(speed) or 1, SPEED_MIN, SPEED_MAX)
	local slider = self._sliders.speed
	if slider and self._activeSlider ~= slider then
		slider.value = snap(value, SPEED_MIN, SPEED_MAX, SPEED_STEP)
		self:_paintSlider(slider, true)
	end
	for _, preset in ipairs(self._presets) do
		local active = math.abs(value - preset.value) < 0.001
		if preset.active == active then
			continue
		end
		local becameActive = active and preset.active ~= nil
		preset.active = active
		local transparency = if active then math.max(0, preset.baseTransparency - 0.18) else preset.baseTransparency
		MusicMotion.tween(preset.button, SWITCH_TIME, { BackgroundTransparency = transparency })
		if preset.stroke then
			MusicMotion.tween(preset.stroke, SWITCH_TIME, { Transparency = if active then 0 else 0.35 })
		end
		if becameActive then
			MusicMotion.pop(MusicMotion.scaleTargetOf(preset.button), 1.2)
		end
	end
end

function DjView:setEffectEnabled(effectId: string, enabled: boolean)
	local key = tostring(effectId)
	self._effectEnabled[key] = enabled == true
	local toggle = self._effectToggles[key]
	if toggle then
		self:_paintToggle(toggle, enabled == true)
	end
end

function DjView:setEffectValue(effectId: string, itemId: string, value: number)
	local slider = self._sliders[tostring(effectId) .. "::" .. tostring(itemId)]
	if slider and self._activeSlider ~= slider then
		slider.value = snap(tonumber(value) or 0, slider.min, slider.max, slider.step)
		self:_paintSlider(slider, true)
	end
end

function DjView:destroy()
	self._destroyed = true
	self:_endDrag()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	for _, clone in ipairs(self._clones) do
		clone:Destroy()
	end
	table.clear(self._connections)
	table.clear(self._clones)
end

return DjView
