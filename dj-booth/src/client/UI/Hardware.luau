--!strict
-- The semi-realistic deck hardware (owner, 2026-10-22: keep it semi-realistic): matte knobs with
-- LED rings, faders with matte caps, round keys. Every control takes a value source (0..1) and an
-- onChange; dragging writes through onChange and the source follows the server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Vide = require(ReplicatedStorage.HazaDJ.Packages.Vide)
local Base = require(script.Parent.Base)
local Theme = require(script.Parent.Parent.Theme)

local create = Vide.create
local C, W, B = Theme.C, Theme.W, Theme.B
local frame, label, corner = Base.frame, Base.label, Base.corner

local Hardware = {}

local DARK = ColorSequence.new(Color3.fromRGB(64, 64, 64), Color3.fromRGB(32, 32, 32))
local LIGHT = ColorSequence.new(Color3.fromRGB(238, 238, 238), Color3.fromRGB(170, 170, 170))

-- a drag on `hit` that maps pointer travel to a value: axis "x" | "y" (y up = more) | "knob"
-- (vertical travel, 160 px for the full sweep). Double-click resets to `default`. `pad` insets the
-- travel by that many px at each end (a fader cap's half-width).
function Hardware.drag(
	hit: GuiObject,
	axis: string,
	get: () -> number,
	set: (number) -> (),
	default: number?,
	track: GuiObject?,
	pad: number?
)
	local edge = pad or 0
	local lastClick = 0
	hit.InputBegan:Connect(function(io)
		if not Base.isPress(io) then
			return
		end
		local now = os.clock()
		if default and now - lastClick < 0.3 then
			lastClick = 0
			set(default)
			return
		end
		lastClick = now
		local area = track or hit
		local startX, startY, startV = io.Position.X, io.Position.Y, get()
		-- faders move by the pointer's travel from the press (grab anywhere, no jump on press), so
		-- the top-bar inset never enters the maths
		local function at(pos: Vector3)
			if axis == "x" then
				set(math.clamp(startV + (pos.X - startX) / math.max(area.AbsoluteSize.X - 2 * edge, 1), 0, 1))
			elseif axis == "y" then
				set(math.clamp(startV + (pos.Y - startY) / math.max(area.AbsoluteSize.Y - 2 * edge, 1), 0, 1))
			else
				set(math.clamp(startV + (startY - pos.Y) / 160, 0, 1))
			end
		end
		-- a mouse drag on a fader hides the cursor, so it never shows drifting off the cap past the
		-- ends (owner, 2026-10-23). Not locked: a locked mouse turns the camera.
		local hidden = axis ~= "knob" and io.UserInputType == Enum.UserInputType.MouseButton1
		local iconWas = UserInputService.MouseIconEnabled
		if hidden then
			UserInputService.MouseIconEnabled = false
		end
		local moveC, endC
		moveC = UserInputService.InputChanged:Connect(function(m)
			if Base.isMove(m) then
				at(m.Position)
			end
		end)
		endC = UserInputService.InputEnded:Connect(function(e)
			if Base.isPress(e) then
				moveC:Disconnect()
				endC:Disconnect()
				if hidden then
					UserInputService.MouseIconEnabled = iconWas
				end
			end
		end)
	end)
	hit.InputChanged:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseWheel then
			set(math.clamp(get() + io.Position.Z * 0.02, 0, 1))
		end
	end)
end

-- a matte face (knob body, fader cap): dark or light gradient, a near-black rim
function Hardware.matte(
	cx: number,
	cy: number,
	w: number,
	h: number,
	r: number,
	light: boolean?,
	props: Base.Props?
): Frame
	return Base.new(
		"Frame",
		Base.with({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx, cy),
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = W,
			ZIndex = 53,
			corner(r),
			create("UIGradient")({ Rotation = 90, Color = if light then LIGHT else DARK }),
			create("UIStroke")({ Color = C.tile, Thickness = 1 }),
		}, props)
	)
end

-- knob with an LED ring (15 dots over 270°); bipolar rings light from 12 o'clock. The pointer is a
-- white dot near the rim (owner, 2026-10-22).
function Hardware.ledKnob(
	cx: number,
	cy: number,
	size: number,
	value: () -> number,
	bipolar: boolean,
	onChange: ((number) -> ())?,
	default: number?
): Frame
	local rd = size / 2 - 6
	local dot = Base.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(5, 5),
		BackgroundColor3 = W,
		ZIndex = 54,
		Position = function()
			local a = math.rad(-135 + 270 * value())
			return UDim2.new(0.5, math.sin(a) * rd, 0.5, -math.cos(a) * rd)
		end,
		corner(3),
	})
	local leds = {}
	local N = 15
	for i = 0, N - 1 do
		local t = i / (N - 1)
		local b = math.rad(-135 + 270 * t)
		local rr = size / 2 + 7
		leds[i + 1] = Base.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.sin(b) * rr, 0.5, -math.cos(b) * rr),
			Size = UDim2.fromOffset(3, 3),
			ZIndex = 53,
			BackgroundColor3 = function()
				local v = value()
				local lit = if bipolar
					then (v >= 0.5 and t >= 0.5 - 1e-6 and t <= v + 1e-6) or (v < 0.5 and t <= 0.5 + 1e-6 and t >= v - 1e-6)
					else t <= v + 1e-6
				return if lit then W else C.ledOff
			end,
			corner(2),
		})
	end
	local k = Hardware.matte(cx, cy, size, size, size // 2, false, { dot, leds })
	if onChange then
		local hit = create("TextButton")({
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1.6, 1.6),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = 56,
			Parent = k,
		})
		Hardware.drag(hit, "knob", function()
			return Vide.untrack(value)
		end, onChange, default)
	end
	return k
end

-- vertical fader: groove, ticks on both sides (long white centre), light cap with an index line.
-- value 0 = top, 1 = bottom (the deck faders' screen direction)
function Hardware.vfader(
	x: number,
	y: number,
	h: number,
	value: () -> number,
	capW: number,
	ticks: number,
	onChange: ((number) -> ())?,
	default: number?
): Frame
	local marks = {}
	for i = 0, ticks do
		local mid = i == ticks // 2
		for _, side in { 0, 1 } do
			table.insert(
				marks,
				Base.new("Frame", {
					AnchorPoint = Vector2.new(side, 0.5),
					Position = UDim2.new(side, 0, i / ticks, 11 - (i / ticks) * 22),
					Size = UDim2.fromOffset(if mid then 10 else 6, 1),
					BackgroundColor3 = if mid then W else C.faint,
					ZIndex = 52,
				})
			)
		end
	end
	local cap = Hardware.matte(capW / 2, 0, capW, 22, 3, true, {
		Position = function()
			return UDim2.new(0.5, 0, value(), 11 - value() * 22)
		end,
		Base.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(capW - 8, 2),
			BackgroundColor3 = C.ink,
			ZIndex = 54,
		}),
	})
	local f = frame({
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(capW, h),
		ZIndex = 52,
		Base.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.new(0, 4, 1, 0),
			BackgroundColor3 = C.groove,
			ZIndex = 52,
		}),
		marks,
		cap,
	})
	if onChange then
		local hit = create("TextButton")({
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 8, 1, 22),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = 56,
			Parent = f,
		})
		Hardware.drag(hit, "y", function()
			return Vide.untrack(value)
		end, onChange, default, f, 11)
	end
	return f
end

-- the strip's dark fader cap: dark gradient, rim, white index across
function Hardware.cap(w: number, h: number, props: Base.Props?): Frame
	local horizontal = w >= h
	return Base.new(
		"Frame",
		Base.with({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = W,
			ZIndex = 4,
			corner(3),
			create("UIGradient")({
				Rotation = 90,
				Color = ColorSequence.new(Color3.fromRGB(70, 70, 70), Color3.fromRGB(44, 44, 44)),
			}),
			create("UIStroke")({ Color = C.tile, Thickness = 1 }),
			Base.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = if horizontal then UDim2.fromOffset(2, h - 4) else UDim2.fromOffset(w - 4, 2),
				BackgroundColor3 = W,
				ZIndex = 5,
			}),
		}, props)
	)
end

-- horizontal fader (strip FX, curve): a 4 px groove and a 14 x 22 cap at value
function Hardware.hfader(
	x: number,
	y: number,
	w: number,
	value: () -> number,
	onChange: ((number) -> ())?,
	default: number?
): Frame
	local f = frame({
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, 24),
		Base.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, 0, 0, 4),
			BackgroundColor3 = C.groove,
		}),
		Hardware.cap(14, 22, {
			Position = function()
				return UDim2.new(value(), 7 - value() * 14, 0.5, 0)
			end,
		}),
	})
	if onChange then
		local hit = create("TextButton")({
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 14, 1, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			ZIndex = 6,
			Parent = f,
		})
		Hardware.drag(hit, "x", function()
			return Vide.untrack(value)
		end, onChange, default, f, 7)
	end
	return f
end

-- a round key (CUE, PLAY, hot cues): dark matte face with a coloured rim
function Hardware.roundKey(
	cx: number,
	cy: number,
	size: number,
	rim: any,
	rimW: any,
	text: any,
	textSize: number,
	textColor: any?,
	props: Base.Props?
): TextButton
	return create("TextButton")(Base.with({
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = W,
		BorderSizePixel = 0,
		corner(size // 2),
		create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new(Color3.fromRGB(62, 62, 62), Color3.fromRGB(32, 32, 32)),
		}),
		-- Border: a TextButton's default (Contextual) strokes its own empty Text, so no rim draws
		create("UIStroke")({ Color = rim, Thickness = rimW, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		label(text, {
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			FontFace = B,
			TextSize = textSize,
			TextColor3 = textColor or W,
		}),
	}, props))
end

return Hardware
