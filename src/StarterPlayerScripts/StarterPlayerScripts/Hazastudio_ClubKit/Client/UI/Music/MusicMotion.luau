--!strict
-- PATH: StarterPlayerScripts/Client/UI/Music/MusicMotion.luau
-- Playful motion for the v3 music panel. The design lays most buttons and rows out with
-- UIListLayout/UIGridLayout, where a UIScale changes the reserved size and makes siblings jump.
-- So scale is only ever applied to a centred element (AnchorPoint 0.5) whose parent has no
-- layout; everything else animates layout-neutral properties (transparency, colour, rotation).
-- Honours GuiService.ReducedMotionEnabled (tweens snap, flourishes are skipped) and
-- Config.UIMotion.MOTION_SCALE through MotionPresets.

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local MotionPresets = require(script.Parent.Parent.Parent.Utils.MotionPresets)

local SCALE_NAME = "MusicMotionScale"
local CENTER = Vector2.new(0.5, 0.5)

local MusicMotion = {}

-- Latest tween per (instance, channel): a new animation on the same channel replaces the old one.
local running: { [Instance]: { [string]: Tween } } = setmetatable({}, { __mode = "k" }) :: any

function MusicMotion.reduced(): boolean
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
function MusicMotion.tween(
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
	if time <= 0 or MusicMotion.reduced() or not instance.Parent then
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

local function hasLayout(instance: Instance?): boolean
	return instance ~= nil and instance:FindFirstChildWhichIsA("UIGridStyleLayout") ~= nil
end

-- True when scaling this element cannot move anything else on screen.
function MusicMotion.canScale(target: Instance?): boolean
	return target ~= nil
		and target:IsA("GuiObject")
		and target.AnchorPoint == CENTER
		and not hasLayout(target.Parent)
end

-- The element a press should squash: the button itself when that is safe, else its centred icon.
function MusicMotion.scaleTargetOf(button: GuiObject): GuiObject?
	if MusicMotion.canScale(button) then
		return button
	end
	if hasLayout(button) then
		return nil
	end
	for _, child in ipairs(button:GetChildren()) do
		if (child:IsA("ImageLabel") or child:IsA("TextLabel")) and MusicMotion.canScale(child) then
			return child
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
function MusicMotion.pop(target: GuiObject?, peak: number?, time: number?)
	if target == nil or MusicMotion.reduced() or not MusicMotion.canScale(target) then
		return
	end
	local scale = scaleOf(target)
	scale.Scale = 1
	play(scale, "Scale", info(time or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, true), {
		Scale = peak or 1.25,
	})
end

-- Grow in from a smaller size with a little overshoot.
function MusicMotion.popIn(target: GuiObject?, from: number?)
	if target == nil or MusicMotion.reduced() or not MusicMotion.canScale(target) then
		return
	end
	local scale = scaleOf(target)
	scale.Scale = from or 0.6
	play(scale, "Scale", info(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
end

-- Rotation never affects layout, so wiggle and spin are safe on any element.
function MusicMotion.wiggle(target: GuiObject?, degrees: number?)
	if target == nil or MusicMotion.reduced() then
		return
	end
	local amount = degrees or 8
	local base = tonumber(target:GetAttribute("MusicMotionRotation"))
	if base == nil then
		base = target.Rotation
		target:SetAttribute("MusicMotionRotation", base)
	end
	local restRotation = base :: number
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

function MusicMotion.spin(target: GuiObject?, turns: number?)
	if target == nil or MusicMotion.reduced() then
		return
	end
	local base = tonumber(target:GetAttribute("MusicMotionRotation"))
	if base == nil then
		base = target.Rotation
		target:SetAttribute("MusicMotionRotation", base)
	end
	local restRotation = base :: number
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

-- Fade text/images in from invisible to their designed transparency. `bases` holds each
-- element's designed value (captured once by the caller, before any fade touched it).
function MusicMotion.fadeIn(elements: { GuiObject }, bases: { [GuiObject]: number }, delay: number?)
	if MusicMotion.reduced() then
		return
	end
	local function run()
		for _, element in ipairs(elements) do
			local base = bases[element]
			if base == nil or not element.Parent then
				continue
			end
			local property = if element:IsA("ImageLabel") or element:IsA("ImageButton")
				then "ImageTransparency"
				else "TextTransparency"
			;(element :: any)[property] = 1
			play(element, property, info(0.28, Enum.EasingStyle.Quad), { [property] = base })
		end
	end
	if delay and delay > 0 then
		for _, element in ipairs(elements) do
			local base = bases[element]
			if base ~= nil then
				local property = if element:IsA("ImageLabel") or element:IsA("ImageButton")
					then "ImageTransparency"
					else "TextTransparency"
				;(element :: any)[property] = 1
			end
		end
		task.delay(MotionPresets.scaledTime(delay), run)
	else
		run()
	end
end

-- Records the designed transparency of text/image elements for fadeIn.
function MusicMotion.captureBases(elements: { GuiObject }, into: { [GuiObject]: number }?): { [GuiObject]: number }
	local bases = into or {}
	for _, element in ipairs(elements) do
		if element:IsA("ImageLabel") or element:IsA("ImageButton") then
			bases[element] = (element :: any).ImageTransparency
		elseif element:IsA("TextLabel") or element:IsA("TextButton") or element:IsA("TextBox") then
			bases[element] = (element :: any).TextTransparency
		end
	end
	return bases
end

-- Slides a page's content in from the side. Equal and opposite UIPadding offsets move the
-- content without changing its width or the page's size, so the laid-out panel stays put
-- (measured: content moved, page and panel heights unchanged). direction: 1 = from the right.
function MusicMotion.slideIn(page: GuiObject, direction: number, distance: number?)
	if MusicMotion.reduced() then
		return
	end
	local existing = page:FindFirstChild("MusicMotionSlide")
	local padding: UIPadding
	if existing and existing:IsA("UIPadding") then
		padding = existing
	else
		padding = Instance.new("UIPadding")
		padding.Name = "MusicMotionSlide"
		padding.Parent = page
	end
	local offset = (distance or 28) * (if direction < 0 then -1 else 1)
	padding.PaddingLeft = UDim.new(0, offset)
	padding.PaddingRight = UDim.new(0, -offset)
	play(padding, "Slide", info(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		PaddingLeft = UDim.new(0, 0),
		PaddingRight = UDim.new(0, 0),
	})
end

-- Squash on press, springy release. Returns the connections so the caller can own them.
function MusicMotion.bindPress(button: GuiObject): { RBXScriptConnection }
	local target = MusicMotion.scaleTargetOf(button)
	if target == nil then
		return {}
	end
	local pressed = false
	local function isPress(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	local function release()
		if not pressed then
			return
		end
		pressed = false
		if MusicMotion.reduced() or not target.Parent then
			return
		end
		play(scaleOf(target), "Scale", info(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	end
	return {
		button.InputBegan:Connect(function(input)
			if not isPress(input) or pressed or MusicMotion.reduced() then
				return
			end
			pressed = true
			play(scaleOf(target), "Scale", info(0.08), { Scale = 0.86 })
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

return MusicMotion
