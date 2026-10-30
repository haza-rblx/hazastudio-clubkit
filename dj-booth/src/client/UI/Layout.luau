--!strict
-- The page language shared by Library, Access and Settings (owner, 2026-10-22): side nav captions
-- and rows, a 56 px page head, a scrolling body, square cards of setting rows, inspector fields.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vide = require(ReplicatedStorage.CosmicDJ.Packages.Vide)
local Base = require(script.Parent.Base)
local Hover = require(script.Parent.Hover)
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

-- side nav caption (28 px for the first, 44 after, so each group reads as its own block)
function Layout.sideCaption(order: number, text: string): Frame
	return frame({
		Size = UDim2.new(1, 0, 0, if order == 1 then 28 else 44),
		LayoutOrder = order,
		caption(text, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -6) }),
	})
end

-- a 36 px side nav row with an optional value on the right. Rows hang off a guide line under their
-- caption (owner, 2026-10-30): each on a curved branch into a 4 px pill, the group's last row ends
-- the line, and the selected row's branch is in the accent.
function Layout.sideRow(
	order: number,
	on: any,
	title: string,
	right: any?,
	rightColor: any?,
	onClick: () -> ()
): TextButton
	local hover = source(false)
	local isOn = function()
		return Vide.read(on) == true
	end
	local last = source(false) -- no visible row follows in this group, so the guide ends here
	local row = create("TextButton")({
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 0, 36),
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Hover.track(hover),
		Activated = onClick,
		-- the pill after the branch
		frame({
			Position = UDim2.fromOffset(32, 2),
			Size = UDim2.new(1, -40, 1, -4),
			BackgroundColor3 = function()
				return if isOn() then C.select else C.hover
			end,
			BackgroundTransparency = function()
				return if isOn() or hover() then 0 else 1
			end,
			Base.corner(4),
		}),
		-- the guide runs on past this row unless it's the group's last
		frame({
			Position = UDim2.fromOffset(20, 0),
			Size = UDim2.new(0, 1, 1, 0),
			BackgroundTransparency = 0,
			BackgroundColor3 = C.card2,
			Visible = function()
				return not last()
			end,
		}),
		-- the branch: the bottom-left corner of a stroked, rounded frame, clipped to a quarter curve
		frame({
			Position = UDim2.fromOffset(20, 0),
			Size = UDim2.fromOffset(12, 19),
			ClipsDescendants = true,
			frame({
				-- the stroke sits outside the frame, so it lands on the guide and the row's middle
				Position = UDim2.fromOffset(1, -40),
				Size = UDim2.fromOffset(60, 58),
				Base.corner(2),
				create("UIStroke")({
					Thickness = 1,
					Color = function()
						return if isOn() then Theme.accent() else C.card2
					end,
				}),
			}),
		}),
		label(title, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 42, 0.5, 0),
			TextSize = 14,
			TextColor3 = function()
				return if isOn() then W else C.soft
			end,
		}),
		if right
			then label(right, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -20, 0.5, 0),
				FontFace = R,
				TextSize = 13,
				TextColor3 = rightColor or C.dim,
				Visible = function()
					return (Vide.read(right) or "") ~= ""
				end,
			})
			else nil,
	}) :: TextButton
	row:SetAttribute("SideRow", true)
	-- once the nav is built, see whether a visible row follows before the next caption
	task.defer(function()
		local parent = row.Parent
		if not parent then
			return
		end
		local function check()
			local after = {}
			for _, c in parent:GetChildren() do
				if c:IsA("GuiObject") and c.LayoutOrder > order then
					table.insert(after, c)
				end
			end
			table.sort(after, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			for _, c in after do
				if not c:GetAttribute("SideRow") then
					break
				elseif c.Visible then
					last(false)
					return
				end
			end
			last(true)
		end
		check()
		for _, c in parent:GetChildren() do
			if c:GetAttribute("SideRow") and c ~= row then
				c:GetPropertyChangedSignal("Visible"):Connect(check)
			end
		end
	end)
	return row
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
			Base.corner(4),
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
