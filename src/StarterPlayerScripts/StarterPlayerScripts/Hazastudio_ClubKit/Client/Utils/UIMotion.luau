--!strict
-- PATH: StarterPlayerScripts/Client/Utils/UIMotion.luau
-- The one motion vocabulary for every kit panel (ADR 0011). Grew out of the v3 music panel's
-- MusicMotion. Kit designs lay most buttons and rows out with UIListLayout/UIGridLayout, where a
-- UIScale changes the reserved size and makes siblings jump — so scale is only ever applied to a
-- centred element (AnchorPoint 0.5) whose parent has no layout; everything else animates
-- layout-neutral properties (transparency, colour, rotation, padding). Never scale a CanvasGroup
-- (ADR 0005). Honours GuiService.ReducedMotionEnabled (tweens snap, flourishes are skipped) and
-- Config.UIMotion.MOTION_SCALE through MotionPresets.

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local MotionPresets = require(script.Parent.MotionPresets)

local SCALE_NAME = "UIMotionScale"
local SLIDE_NAME = "UIMotionSlide"
local ROTATION_ATTRIBUTE = "UIMotionRotation"
local CENTER = Vector2.new(0.5, 0.5)

local UIMotion = {}

-- Latest tween per (instance, channel): a new animation on the same channel replaces the old one.
local running: { [Instance]: { [string]: Tween } } = setmetatable({}, { __mode = "k" }) :: any

function UIMotion.reduced(): boolean
	local ok, value = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	return ok and value == true
end

local function info(time: number, style: Enum.EasingStyle?, direction: Enum.EasingDirection?, reverses: boolean?): TweenInfo
	return TweenInfo.new(
		MotionPresets.scaledTime(time),
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out,
		0,
		reverses == true
	)
end

local function play(instance: Instance, channel: string, tweenInfo: TweenInfo, goals: { [string]: any }): Tween
	local byChannel = running[instance]
	if not byChannel then
		byChannel = {}
		running[instance] = byChannel
	end
	local previous = byChannel[channel]
	if previous then
		previous:Cancel()
	end
	local tween = TweenService:Create(instance, tweenInfo, goals)
	byChannel[channel] = tween
	tween.Completed:Once(function()
		if byChannel[channel] == tween then
			byChannel[channel] = nil
		end
	end)
	tween:Play()
	return tween
end

-- Tween to goals, or set them at once under reduced motion. Channel defaults to the joined
-- property names, so two tweens driving different properties do not cancel each other.
function UIMotion.tween(
	instance: Instance,
	time: number,
	goals: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
)
	local names = {}
	for property in pairs(goals) do
		table.insert(names, property)
	end
	table.sort(names)
	local channel = table.concat(names, ",")
	if time <= 0 or UIMotion.reduced() or not instance.Parent then
		local byChannel = running[instance]
		local previous = byChannel and byChannel[channel]
		if previous then
			previous:Cancel()
			byChannel[channel] = nil
		end
		for property, value in pairs(goals) do
			(instance :: any)[property] = value
		end
		return
	end
	play(instance, channel, info(time, style, direction), goals)
end

-- Cancels every tween this module is running on the instance and leaves the properties where
-- they are. For teardown paths that then set their own resting values.
function UIMotion.cancel(instance: Instance)
	local byChannel = running[instance]
	if not byChannel then
		return
	end
	for channel, tween in pairs(byChannel) do
		tween:Cancel()
		byChannel[channel] = nil
	end
end

local function hasLayout(instance: Instance?): boolean
	return instance ~= nil and instance:FindFirstChildWhichIsA("UIGridStyleLayout") ~= nil
end

-- True when scaling this element cannot move anything else on screen or re-rasterise a group.
function UIMotion.canScale(target: Instance?): boolean
	return target ~= nil
		and target:IsA("GuiObject")
		and not target:IsA("CanvasGroup")
		and target.AnchorPoint == CENTER
		and not hasLayout(target.Parent)
		and target:FindFirstAncestorWhichIsA("CanvasGroup") == nil
end

-- Most kit buttons are laid-out TextButtons holding one label anchored at (0, 0). Moving that
-- label's anchor to the centre, with its position compensated, does not move a pixel and makes
-- it a safe scale target (its parent, the button, has no layout). Done once per instance.
local function recentre(child: GuiObject): GuiObject?
	if child.AnchorPoint == CENTER then
		return child
	end
	if child.AutomaticSize ~= Enum.AutomaticSize.None or child:GetAttribute("UIMotionRecentred") then
		return nil
	end
	local anchor, size, position = child.AnchorPoint, child.Size, child.Position
	local dx, dy = 0.5 - anchor.X, 0.5 - anchor.Y
	child.Position = UDim2.new(
		position.X.Scale + dx * size.X.Scale,
		position.X.Offset + dx * size.X.Offset,
		position.Y.Scale + dy * size.Y.Scale,
		position.Y.Offset + dy * size.Y.Offset
	)
	child.AnchorPoint = CENTER
	child:SetAttribute("UIMotionRecentred", true)
	return child
end

-- The element a press should squash: the button itself when that is safe, else its label/icon.
function UIMotion.scaleTargetOf(button: GuiObject): GuiObject?
	if UIMotion.canScale(button) then
		return button
	end
	if hasLayout(button) or button:FindFirstAncestorWhichIsA("CanvasGroup") then
		return nil
	end
	-- A visible icon first, then visible text: a hidden label must never take the squash. Looks
	-- one level into plain wrapper Frames (no layout of their own), where many designs keep the
	-- label; never into buttons or groups.
	local function pick(parent: Instance): GuiObject?
		for _, className in ipairs({ "ImageLabel", "TextLabel" }) do
			for _, child in ipairs(parent:GetChildren()) do
				if child:IsA(className) and (child :: GuiObject).Visible then
					local target = recentre(child :: GuiObject)
					if target and UIMotion.canScale(target) then
						return target
					end
				end
			end
		end
		return nil
	end
	local direct = pick(button)
	if direct then
		return direct
	end
	for _, child in ipairs(button:GetChildren()) do
		if child.ClassName == "Frame" and (child :: Frame).Visible and not hasLayout(child) then
			local nested = pick(child)
			if nested then
				return nested
			end
		end
	end
	return nil
end

local function scaleOf(target: GuiObject): UIScale
	local existing = target:FindFirstChild(SCALE_NAME)
	if existing and existing:IsA("UIScale") then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = SCALE_NAME
	scale.Parent = target
	return scale
end

-- Quick bounce: 1 -> peak -> 1.
function UIMotion.pop(target: GuiObject?, peak: number?, time: number?)
	if target == nil or UIMotion.reduced() or not UIMotion.canScale(target) then
		return
	end
	local scale = scaleOf(target)
	scale.Scale = 1
	play(scale, "Scale", info(time or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, true), {
		Scale = peak or 1.25,
	})
end

-- Grow in from a smaller size with a little overshoot.
function UIMotion.popIn(target: GuiObject?, from: number?)
	if target == nil or UIMotion.reduced() or not UIMotion.canScale(target) then
		return
	end
	local scale = scaleOf(target)
	scale.Scale = from or 0.6
	play(scale, "Scale", info(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
end

local function restRotationOf(target: GuiObject): number
	local base = tonumber(target:GetAttribute(ROTATION_ATTRIBUTE))
	if base == nil then
		base = target.Rotation
		target:SetAttribute(ROTATION_ATTRIBUTE, base)
	end
	return base :: number
end

-- Rotation never affects layout, so wiggle and spin are safe on any element.
function UIMotion.wiggle(target: GuiObject?, degrees: number?)
	if target == nil or UIMotion.reduced() then
		return
	end
	local amount = degrees or 8
	local restRotation = restRotationOf(target)
	task.spawn(function()
		for _, offset in ipairs({ amount, -amount, amount * 0.5, -amount * 0.5, 0 }) do
			if not target.Parent then
				return
			end
			local tween = play(target, "Rotation", info(0.05, Enum.EasingStyle.Sine), { Rotation = restRotation + offset })
			tween.Completed:Wait()
			if tween.PlaybackState ~= Enum.PlaybackState.Completed then
				return
			end
		end
	end)
end

function UIMotion.spin(target: GuiObject?, turns: number?)
	if target == nil or UIMotion.reduced() then
		return
	end
	local restRotation = restRotationOf(target)
	target.Rotation = restRotation
	local tween = play(
		target,
		"Rotation",
		info(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Rotation = restRotation + 360 * (turns or 1) }
	)
	tween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed and target.Parent then
			target.Rotation = restRotation
		end
	end)
end

local function fadeProperty(element: GuiObject): string?
	if element:IsA("ImageLabel") or element:IsA("ImageButton") then
		return "ImageTransparency"
	elseif element:IsA("TextLabel") or element:IsA("TextButton") or element:IsA("TextBox") then
		return "TextTransparency"
	end
	return nil
end

-- Fade text/images in from invisible to their designed transparency. `bases` holds each
-- element's designed value (captured once by the caller, before any fade touched it).
function UIMotion.fadeIn(elements: { GuiObject }, bases: { [GuiObject]: number }, delay: number?)
	if UIMotion.reduced() then
		return
	end
	local function run()
		for _, element in ipairs(elements) do
			local base = bases[element]
			local property = fadeProperty(element)
			if base == nil or property == nil or not element.Parent then
				continue
			end
			(element :: any)[property] = 1
			play(element, property, info(0.28, Enum.EasingStyle.Quad), { [property] = base })
		end
	end
	if delay and delay > 0 then
		for _, element in ipairs(elements) do
			local property = fadeProperty(element)
			if bases[element] ~= nil and property then
				(element :: any)[property] = 1
			end
		end
		task.delay(MotionPresets.scaledTime(delay), run)
	else
		run()
	end
end

-- Records the designed transparency of text/image elements for fadeIn.
function UIMotion.captureBases(elements: { GuiObject }, into: { [GuiObject]: number }?): { [GuiObject]: number }
	local bases = into or {}
	for _, element in ipairs(elements) do
		local property = fadeProperty(element)
		if property then
			bases[element] = (element :: any)[property]
		end
	end
	return bases
end

-- Rows of a list cascade in: each row's text/images fade a step later than the one before.
-- `step` is the delay between rows; rows past `maxRows` appear at once (long lists must not
-- take seconds to settle).
function UIMotion.stagger(rows: { GuiObject }, bases: { [GuiObject]: number }, step: number?, maxRows: number?)
	if UIMotion.reduced() then
		return
	end
	local stepTime = step or 0.03
	local cap = maxRows or 12
	for index, row in ipairs(rows) do
		local elements: { GuiObject } = {}
		for _, descendant in ipairs(row:GetDescendants()) do
			if descendant:IsA("GuiObject") and bases[descendant] ~= nil then
				table.insert(elements, descendant)
			end
		end
		if bases[row] ~= nil then
			table.insert(elements, row)
		end
		UIMotion.fadeIn(elements, bases, if index <= cap then stepTime * (index - 1) else 0)
	end
end

-- Roblox honours one UIPadding per instance, so a page that already has one (buyer designs
-- often do) is slid through that padding, offset from its designed values; only a page with
-- none gets a UIMotionSlide padding. Designed values are recorded once as attributes.
local function slidePaddingOf(page: GuiObject): UIPadding?
	-- An AutomaticSize page grows with its padding, so the slide would resize it. Skip.
	if page.AutomaticSize ~= Enum.AutomaticSize.None then
		return nil
	end
	local existing = page:FindFirstChildWhichIsA("UIPadding")
	if existing then
		return existing
	end
	local padding = Instance.new("UIPadding")
	padding.Name = SLIDE_NAME
	padding.Parent = page
	return padding
end

local function designedPadding(padding: UIPadding, side: string): UDim
	local attribute = "UIMotionBase" .. side
	local base = padding:GetAttribute(attribute)
	if typeof(base) ~= "UDim" then
		base = (padding :: any)["Padding" .. side]
		padding:SetAttribute(attribute, base)
	end
	return base :: UDim
end

local function shifted(base: UDim, by: number): UDim
	return UDim.new(base.Scale, base.Offset + by)
end

-- Slides a page's content in from the side. Equal and opposite padding offsets move the
-- content without changing its width or the page's size, so the laid-out panel stays put
-- (measured: content moved, page and panel heights unchanged). direction: 1 = from the right.
function UIMotion.slideIn(page: GuiObject, direction: number, distance: number?)
	if UIMotion.reduced() then
		return
	end
	local padding = slidePaddingOf(page)
	if not padding then
		return
	end
	local left, right = designedPadding(padding, "Left"), designedPadding(padding, "Right")
	local offset = (distance or 28) * (if direction < 0 then -1 else 1)
	padding.PaddingLeft = shifted(left, offset)
	padding.PaddingRight = shifted(right, -offset)
	play(padding, "Slide", info(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		PaddingLeft = left,
		PaddingRight = right,
	})
end

-- Same trick vertically: content drops in from above (direction -1) or rises from below (1).
function UIMotion.slideInVertical(page: GuiObject, direction: number, distance: number?)
	if UIMotion.reduced() then
		return
	end
	local padding = slidePaddingOf(page)
	if not padding then
		return
	end
	local top, bottom = designedPadding(padding, "Top"), designedPadding(padding, "Bottom")
	local offset = (distance or 20) * (if direction < 0 then -1 else 1)
	padding.PaddingTop = shifted(top, offset)
	padding.PaddingBottom = shifted(bottom, -offset)
	play(padding, "SlideV", info(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		PaddingTop = top,
		PaddingBottom = bottom,
	})
end

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- Squash on press, springy release. Returns the connections so the caller can own them.
function UIMotion.bindPress(button: GuiObject, depth: number?): { RBXScriptConnection }
	local target = UIMotion.scaleTargetOf(button)
	if target == nil then
		return {}
	end
	local pressed = false
	local pressScale = depth or 0.86
	local function release()
		if not pressed then
			return
		end
		pressed = false
		if UIMotion.reduced() or not target.Parent then
			return
		end
		play(scaleOf(target), "Scale", info(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	end
	return {
		button.InputBegan:Connect(function(input)
			if not isPress(input) or pressed or UIMotion.reduced() then
				return
			end
			pressed = true
			play(scaleOf(target), "Scale", info(0.08), { Scale = pressScale })
		end),
		button.InputEnded:Connect(function(input)
			if isPress(input) then
				release()
			end
		end),
		button.MouseLeave:Connect(release),
		UserInputService.InputEnded:Connect(function(input)
			if isPress(input) then
				release()
			end
		end),
	}
end

-- Gentle lift while the mouse rests on a button. Pointer devices only — a finger never hovers,
-- and on touch MouseEnter fires on tap and would fight the press squash.
function UIMotion.bindHover(button: GuiObject, lift: number?): { RBXScriptConnection }
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return {}
	end
	local target = UIMotion.scaleTargetOf(button)
	if target == nil then
		return {}
	end
	local hoverScale = lift or 1.05
	return {
		button.MouseEnter:Connect(function()
			if UIMotion.reduced() or not target.Parent then
				return
			end
			play(scaleOf(target), "Scale", info(0.14, Enum.EasingStyle.Quad), { Scale = hoverScale })
		end),
		button.MouseLeave:Connect(function()
			if UIMotion.reduced() or not target.Parent then
				return
			end
			play(scaleOf(target), "Scale", info(0.18, Enum.EasingStyle.Quad), { Scale = 1 })
		end),
	}
end

-- Breathing loop on one numeric property (a glow's transparency, a badge's rotation) until the
-- returned stop function is called. Under reduced motion the property is left at rest.
function UIMotion.pulse(target: Instance, property: string, to: number, period: number?): () -> ()
	local rest = (target :: any)[property]
	if UIMotion.reduced() then
		return function() end
	end
	local tween = play(
		target,
		property,
		TweenInfo.new(MotionPresets.scaledTime(period or 1.2), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ [property] = to }
	)
	return function()
		tween:Cancel()
		local byChannel = running[target]
		if byChannel and byChannel[property] == tween then
			byChannel[property] = nil
		end
		if target.Parent then
			(target :: any)[property] = rest
		end
	end
end

-- Rolls a number label from one value to another. `format` receives the rounded value.
function UIMotion.countTo(
	label: TextLabel,
	from: number,
	to: number,
	time: number?,
	format: ((number) -> string)?
): ()
	local render = format or function(value: number): string
		return tostring(math.floor(value + 0.5))
	end
	if UIMotion.reduced() or from == to then
		label.Text = render(to)
		return
	end
	local value = Instance.new("NumberValue")
	value.Value = from
	local conn = value:GetPropertyChangedSignal("Value"):Connect(function()
		if label.Parent then
			label.Text = render(value.Value)
		end
	end)
	local tween = play(value, "Value", info(time or 0.6, Enum.EasingStyle.Quart), { Value = to })
	tween.Completed:Once(function()
		conn:Disconnect()
		if label.Parent then
			label.Text = render(to)
		end
		value:Destroy()
	end)
end

return UIMotion
