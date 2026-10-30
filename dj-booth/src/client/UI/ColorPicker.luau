--!strict
-- The HSV colour picker (owner, 2026-10-23: "rgb picker yang kotak"): a saturation / value square
-- over the hue, a hue bar, a preview chip, a hex field and Default. Shared by the playlist cover
-- (CoverPop) and the game accent (Settings).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Vide = require(ReplicatedStorage.CosmicDJ.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)
local Base = require(script.Parent.Base)
local Controls = require(script.Parent.Controls)

local create, source, untrack = Vide.create, Vide.source, Vide.untrack
local W = Theme.W
local frame, corner = Base.frame, Base.corner

local ColorPicker = {}

local SQ_H, HUE_H = 128, 12

export type Opts = {
	w: number?, -- 256 by default
	-- the colour to show; a source is followed when it changes from outside (e.g. a preset)
	value: Color3 | () -> Color3,
	onPick: (Color3) -> (), -- every drag step and hex commit
	placeholder: string?,
	onDefault: (() -> Color3)?, -- resets, returns the colour to show
	zIndex: number?,
}

ColorPicker.SQ_H, ColorPicker.HUE_H = SQ_H, HUE_H

function ColorPicker.height(): number
	return SQ_H + 8 + HUE_H + 8 + 32
end

function ColorPicker.new(o: Opts, props: Base.Props?): Frame
	local PW = o.w or 256
	local z = o.zIndex or 1
	local read = function(): Color3
		local v = o.value
		return if typeof(v) == "Color3" then v else (v :: () -> Color3)()
	end
	local h0, s0, v0 = untrack(read):ToHSV()
	local hh, ss, vv = source(h0), source(s0), source(v0)
	local color = function()
		return Color3.fromHSV(hh(), ss(), vv())
	end
	local function show(c: Color3)
		local h, s, v = c:ToHSV()
		-- a grey has no hue: keep the bar where it was
		if s > 0 then
			hh(h)
		end
		ss(s)
		vv(v)
	end
	-- follow the value when it changes from outside (not our own pick echoing back)
	if typeof(o.value) ~= "Color3" then
		Vide.effect(function()
			local c = read()
			if c:ToHex() ~= untrack(color):ToHex() then
				show(c)
			end
		end)
	end
	local hexBox: TextBox
	local hexFocus = false
	Vide.effect(function()
		local c = color()
		if hexBox and not hexFocus then
			hexBox.Text = "#" .. c:ToHex()
		end
	end)
	local function drag(target: GuiObject, onPos: (number, number) -> ())
		target.InputBegan:Connect(function(i)
			if not Base.isPress(i) then
				return
			end
			local function at(pos: Vector3)
				-- input Y excludes the top-bar inset; this ScreenGui ignores it
				local inset = game:GetService("GuiService"):GetGuiInset()
				local rel = (Vector2.new(pos.X, pos.Y + inset.Y) - target.AbsolutePosition) / target.AbsoluteSize
				onPos(math.clamp(rel.X, 0, 1), math.clamp(rel.Y, 0, 1))
				o.onPick(untrack(color))
			end
			at(i.Position)
			local mv, up
			mv = UserInputService.InputChanged:Connect(function(m)
				if Base.isMove(m) then
					at(m.Position)
				end
			end)
			up = UserInputService.InputEnded:Connect(function(e)
				if Base.isPress(e) then
					mv:Disconnect()
					up:Disconnect()
				end
			end)
		end)
	end
	local keys = {}
	for i = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i / 6) % 1, 1, 1)))
	end
	local sq = create("TextButton")({
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(PW, SQ_H),
		BorderSizePixel = 0,
		BackgroundColor3 = function()
			return Color3.fromHSV(hh(), 1, 1)
		end,
		ZIndex = z,
		corner(4),
		Base.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = W,
			ZIndex = z,
			corner(4),
			create("UIGradient")({ Transparency = NumberSequence.new(0, 1) }),
		}),
		Base.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(),
			ZIndex = z,
			corner(4),
			create("UIGradient")({ Rotation = 90, Transparency = NumberSequence.new(1, 0) }),
		}),
		Base.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(12, 12),
			BackgroundTransparency = 1,
			ZIndex = z,
			Position = function()
				return UDim2.fromScale(ss(), 1 - vv())
			end,
			corner(6),
			create("UIStroke")({ Color = W, Thickness = 2 }),
		}),
	}) :: TextButton
	local hue = create("TextButton")({
		Text = "",
		AutoButtonColor = false,
		Position = UDim2.fromOffset(0, SQ_H + 8),
		Size = UDim2.fromOffset(PW, HUE_H),
		BackgroundColor3 = W,
		BorderSizePixel = 0,
		ZIndex = z,
		corner(6),
		create("UIGradient")({ Color = ColorSequence.new(keys) }),
		Base.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return UDim2.fromScale(hh(), 0.5)
			end,
			Size = UDim2.fromOffset(6, HUE_H + 6),
			BackgroundColor3 = W,
			ZIndex = z,
			corner(3),
			create("UIStroke")({ Color = Color3.new(), Thickness = 1, Transparency = 0.5 }),
		}),
	}) :: TextButton
	drag(sq, function(x, y)
		ss(x)
		vv(1 - y)
	end)
	drag(hue, function(x)
		hh(math.min(x, 0.999))
	end)

	local hexField = Controls.input({
		placeholder = o.placeholder,
		w = PW - 40,
		text = "#" .. untrack(color):ToHex(),
		ref = function(tb)
			hexBox = tb
			tb.Focused:Connect(function()
				hexFocus = true
			end)
		end,
		onCommit = function(text)
			hexFocus = false
			local hex = string.match(string.lower(text), "^%s*#?(%x%x%x%x%x%x)%s*$")
			if hex then
				show(Color3.fromHex(hex))
				o.onPick(untrack(color))
			else
				hexBox.Text = "#" .. untrack(color):ToHex()
			end
		end,
	}, { Position = UDim2.fromOffset(40, SQ_H + 8 + HUE_H + 8), ZIndex = z })
	if o.onDefault then
		local onDefault = o.onDefault
		Controls.button({
			text = "Default",
			kind = "ghost",
			h = 24,
			onClick = function()
				show(onDefault())
			end,
		}, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0.5, 0),
			TextSize = 11,
			ZIndex = z,
			Parent = hexField,
		})
	end

	return frame(Base.with({
		Size = UDim2.fromOffset(PW, ColorPicker.height()),
		ZIndex = z,
		sq,
		hue,
		Base.new("Frame", {
			Position = UDim2.fromOffset(0, SQ_H + 8 + HUE_H + 8),
			Size = UDim2.fromOffset(32, 32),
			BackgroundColor3 = color,
			ZIndex = z,
			corner(4),
		}),
		hexField,
	}, props))
end

return ColorPicker
