--!strict
-- The page language shared by Library, Access and Settings (owner, 2026-10-22): side nav captions
-- and rows, a 56 px page head, a scrolling body, square cards of setting rows, inspector fields.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vide = require(ReplicatedStorage.HazaDJ.Packages.Vide)
local Base = require(script.Parent.Base)
local Theme = require(script.Parent.Parent.Theme)

local create, source = Vide.create, Vide.source
local C, W, B, R = Theme.C, Theme.W, Theme.B, Theme.R
local with, frame, label, caption, fixed = Base.with, Base.frame, Base.label, Base.caption, Base.fixed

local Layout = {}

local PAGE_PAD, PAGE_HEAD = Theme.PAGE_PAD, Theme.PAGE_HEAD

-- a caption + control block for inspector / editor columns; returns (body, wrapper)
function Layout.field(order: number, title: any, h: number?, body: { any }?, props: Base.Props?): Frame
	return frame(with({
		Size = UDim2.new(1, 0, 0, 20 + (h or 32)),
		LayoutOrder = order,
		caption(title),
		frame({ Name = "Body", Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, h or 32), body }),
	}, props))
end

-- a settings row: title + one-line description on the left, the control on the right (52 px)
function Layout.settingRow(order: number, title: string, desc: string, control: Instance?, last: boolean?): Frame
	if control then
		local c = control :: GuiObject
		c.AnchorPoint = Vector2.new(1, 0.5)
		c.Position = UDim2.new(1, 0, 0.5, 0)
	end
	return frame({
		Size = UDim2.new(1, 0, 0, 52),
		LayoutOrder = order,
		label(title, { Position = UDim2.fromOffset(0, 9), TextSize = 14 }),
		fixed(
			desc,
			0,
			27,
			0,
			16,
			{ Size = UDim2.new(1, -270, 0, 16), FontFace = R, TextSize = 12, TextColor3 = C.dim }
		),
		if last then nil else Base.rule(true),
		control,
	})
end

-- side nav caption (24 px for the first, 32 after)
function Layout.sideCaption(order: number, text: string): Frame
	return frame({
		Size = UDim2.new(1, 0, 0, if order == 1 then 24 else 32),
		LayoutOrder = order,
		caption(text, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -6) }),
	})
end

-- a 36 px side nav row with an optional value on the right; on = select fill
function Layout.sideRow(
	order: number,
	on: any,
	title: string,
	right: any?,
	rightColor: any?,
	onClick: () -> ()
): TextButton
	local hover = source(false)
	return create("TextButton")({
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 0, 36),
		BorderSizePixel = 0,
		LayoutOrder = order,
		BackgroundColor3 = function()
			return if Vide.read(on) then C.select else C.hover
		end,
		BackgroundTransparency = function()
			return if Vide.read(on) or hover() then 0 else 1
		end,
		MouseEnter = function()
			hover(true)
		end,
		MouseLeave = function()
			hover(false)
		end,
		Activated = onClick,
		label(title, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 16, 0.5, 0),
			TextSize = 14,
			TextColor3 = function()
				return if Vide.read(on) then W else C.soft
			end,
		}),
		if right
			then label(right, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -16, 0.5, 0),
				FontFace = R,
				TextSize = 13,
				TextColor3 = rightColor or C.dim,
				Visible = function()
					return (Vide.read(right) or "") ~= ""
				end,
			})
			else nil,
	})
end

-- page head: the title at 16 px gutters; an action (see headAction) sits on the right
function Layout.pageHead(title: any, action: Instance?): Frame
	if action then
		local a = action :: GuiObject
		a.AnchorPoint = Vector2.new(1, 0.5)
		a.Position = UDim2.new(1, 0, 0, PAGE_HEAD / 2)
	end
	return frame({
		Size = UDim2.new(1, 0, 0, PAGE_HEAD),
		Base.pad(PAGE_PAD, PAGE_PAD, 0, 0),
		label(title, { FontFace = B, TextSize = 16, Position = UDim2.fromOffset(0, 18) }),
		action,
	})
end

-- the scrolling body under a page head
function Layout.pageBody(children: { any }, props: Base.Props?): ScrollingFrame
	return Base.scroll(with({
		Position = UDim2.fromOffset(0, PAGE_HEAD),
		Size = UDim2.new(1, 0, 1, -PAGE_HEAD),
		ScrollingDirection = Enum.ScrollingDirection.XY,
		Base.pad(PAGE_PAD, PAGE_PAD, 0, 24),
		Base.vlist(0),
		children,
	}, props))
end

-- a group: caption, then a square card of rows. `rows` are built by the caller with settingRow;
-- the caller passes last = true for the final row (the card's edge ends it).
function Layout.group(nx: () -> number, title: string, rows: { any }, first: boolean?): { Instance }
	local order = nx()
	nx()
	return {
		frame({
			Size = UDim2.new(1, 0, 0, if first then 28 else 40),
			LayoutOrder = order,
			caption(title, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -8) }),
		}),
		Base.new("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = C.flat,
			LayoutOrder = order + 1,
			Base.pad(16, 16, 0, 0),
			Base.vlist(0),
			rows,
		}),
	}
end

function Layout.counter(): () -> number
	local o = 0
	return function()
		o += 1
		return o
	end
end

-- an input set into a settings row's control slot
function Layout.rowInput(placeholder: string, w: number, value: string, onText: (string) -> ()): Frame
	local Controls = require(script.Parent.Controls) :: any
	return Controls.input({ placeholder = placeholder, w = w, text = value, onText = onText })
end

return Layout
