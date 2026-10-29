--!strict
-- Interactive controls, one-to-one with the prototype (DJXTabs §0): buttons, fields, segmented
-- switches, the hardware toggle, steppers, dropdown + popup menu, the confirm modal, and the
-- personalised value controls (ruler, LED meter, LED dots).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Vide = require(ReplicatedStorage.HazaDJ.Packages.Vide)
local Base = require(script.Parent.Base)
local Hover = require(script.Parent.Hover)
local Theme = require(script.Parent.Parent.Theme)

local create, source, effect, read, untrack = Vide.create, Vide.source, Vide.effect, Vide.read, Vide.untrack
local C, W, B, SB = Theme.C, Theme.W, Theme.B, Theme.SB
local with, frame, label, corner, pad, hlist, vlist =
	Base.with, Base.frame, Base.label, Base.corner, Base.pad, Base.hlist, Base.vlist

local Controls = {}

export type Props = Base.Props

-- ── buttons ──
local KINDS = {
	primary = { bg = W, over = Color3.fromHex("d6d6d6"), fg = C.ink },
	secondary = { bg = C.card2, over = Color3.fromHex("3f3f3f"), fg = W },
	ghost = { bg = C.flat, over = C.raised, fg = C.soft },
	danger = { bg = C.flat, over = Color3.fromHex("2a1212"), fg = C.redText },
	destructive = { bg = C.red, over = Color3.fromRGB(196, 12, 30), fg = W },
}
Controls.KINDS = KINDS

export type ButtonOpts = {
	text: any,
	kind: string?,
	w: number?,
	h: number?,
	onClick: (() -> ())?,
	-- a source that overrides the colours (e.g. a disabled primary)
	bg: (() -> Color3)?,
	fg: (() -> Color3)?,
	-- a drawn icon instead of text: "plus" | "minus" | "cross" (see Base.glyph)
	glyph: ("plus" | "minus" | "cross")?,
}

function Controls.button(o: ButtonOpts, props: Props?): TextButton
	local k = KINDS[o.kind or "secondary"]
	local hover = source(false)
	return create("TextButton")(with({
		Text = if o.glyph then "" else o.text,
		if o.glyph then Base.glyph(o.glyph, 10, o.fg or k.fg) else nil,
		FontFace = B,
		TextSize = 13,
		TextColor3 = o.fg or k.fg,
		BackgroundColor3 = o.bg or function()
			return if hover() then k.over else k.bg
		end,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(o.w or 0, o.h or 32),
		AutomaticSize = if o.w then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
		Hover.track(hover),
		Activated = o.onClick,
		if o.w then nil else pad(14),
		corner(4),
	}, props))
end

-- ── text field ──
export type InputOpts = {
	placeholder: string?,
	w: number?,
	text: any?, -- initial text or a source to follow
	onText: ((string) -> ())?,
	onCommit: ((string, boolean) -> ())?, -- FocusLost(text, enterPressed)
	editable: any?,
	color: any?,
	ref: ((TextBox) -> ())?,
	box: Props?, -- extra props for the TextBox
}

function Controls.input(o: InputOpts, props: Props?): Frame
	local focused = source(false)
	local tb = create("TextBox")(with({
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = untrack(function()
			return read(o.text) or ""
		end),
		PlaceholderText = o.placeholder or "",
		PlaceholderColor3 = C.faint,
		TextColor3 = o.color or W,
		FontFace = SB,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextEditable = o.editable == nil and true or o.editable,
		Focused = function()
			focused(true)
		end,
		FocusLost = function()
			focused(false)
		end,
	}, o.box)) :: TextBox
	if o.onCommit then
		local commit = o.onCommit
		tb.FocusLost:Connect(function(enter)
			commit(tb.Text, enter)
		end)
	end
	if o.onText then
		local onText = o.onText
		tb:GetPropertyChangedSignal("Text"):Connect(function()
			onText(tb.Text)
		end)
	end
	if type(o.text) == "function" then
		local follow = o.text
		effect(function()
			local v = follow()
			if not untrack(focused) then
				tb.Text = v or ""
			end
		end)
	end
	if o.ref then
		o.ref(tb)
	end
	return create("Frame")(with({
		Size = if o.w then UDim2.fromOffset(o.w, 32) else UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = C.field,
		BorderSizePixel = 0,
		corner(4),
		create("UIStroke")({
			Color = W,
			Thickness = 1,
			Transparency = function()
				return if focused() then 0.6 else 1
			end,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		tb,
	}, props))
end

-- ── chevron (the dropdown arrow) ──
-- two 2 px arms meeting at the apex (each runs 1 px past it so the joint is filled), rounded ends
function Controls.chevron(color: Color3?): Frame
	local L, apexX, apexY = 8, 6, 6
	local off = (L / 2 - 1) * math.sqrt(0.5)
	local function arm(side: number)
		return Base.new("Frame", {
			Size = UDim2.fromOffset(L, 2),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(apexX + side * off, apexY - off),
			Rotation = -45 * side,
			BackgroundColor3 = color or C.dim,
			corner(1),
		})
	end
	return frame({
		Size = UDim2.fromOffset(12, 8),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		arm(-1),
		arm(1),
	})
end

-- ── segmented switch ──
-- index: a source (read and written) or a number; onChange(i, label)
function Controls.segmented(
	options: { string },
	index: any,
	onChange: (number, string) -> (),
	w: number?,
	props: Props?
): Frame
	local n = #options
	local each = if w then math.floor((w - 4 - 2 * (n - 1)) / n) else nil
	local cur = if type(index) == "function" then index else source(index)
	local kids = {}
	for i, o in options do
		local hover = source(false)
		local size = if each then UDim2.new(0, each, 1, 0) else UDim2.new(0, 0, 1, 0)
		if i == n and each and w then
			size = UDim2.new(0, w - 4 - 2 * (n - 1) - each * (n - 1), 1, 0) -- absorb the rounding
		end
		kids[i] = create("TextButton")({
			Text = o,
			FontFace = B,
			TextSize = 12,
			AutoButtonColor = false,
			BackgroundColor3 = C.card2,
			BorderSizePixel = 0,
			Size = size,
			AutomaticSize = if each then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
			LayoutOrder = i,
			BackgroundTransparency = function()
				return if cur() == i then 0 else 1
			end,
			TextColor3 = function()
				return if cur() == i then W elseif hover() then C.soft else C.dim
			end,
			Hover.track(hover),
			Activated = function()
				if untrack(cur) == i then
					return
				end
				cur(i)
				onChange(i, o)
			end,
			corner(3),
			if each then nil else pad(12),
		})
	end
	return create("Frame")(with({
		Size = UDim2.fromOffset(w or 0, 32),
		AutomaticSize = if w then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
		BackgroundColor3 = C.field,
		BorderSizePixel = 0,
		corner(4),
		pad(2, 2, 2, 2),
		hlist(2),
		kids,
	}, props))
end

-- ── toggle: a hardware slide switch with a fader cap and an LED (owner, 2026-10-23) ──
function Controls.toggle(on: any, onChange: (boolean) -> (), props: Props?): TextButton
	local state = if type(on) == "function" then on else source(on)
	local hover = source(false)
	local cap, led, glow
	local grooves = {}
	local first = true
	local function paint(tween: boolean)
		local v = untrack(state)
		local function go(o: Instance, p: { [string]: any })
			if tween then
				TweenService:Create(o, Theme.SLIDE, p):Play()
			else
				for k, x in p do
					(o :: any)[k] = x
				end
			end
		end
		go(cap, { Position = UDim2.fromOffset(if v then 23 else 3, 3), BackgroundColor3 = if v then W else C.card2 })
		go(
			led,
			{ Position = UDim2.fromOffset(if v then 13 else 36, 12), BackgroundColor3 = if v then C.red else C.faint }
		)
		go(glow, { Transparency = if v then 0.7 else 1 })
		for _, g in grooves do
			go(g, { BackgroundColor3 = if v then C.soft else C.faint })
		end
	end
	glow = create("UIStroke")({ Color = C.red, Thickness = 2, Transparency = 1 })
	led = Base.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(3, 10), corner(1), glow })
	for i, x in { -3, 2 } do
		grooves[i] = Base.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0.5, x, 0.5, 0),
			Size = UDim2.fromOffset(1, 8),
			ZIndex = 3,
		})
	end
	cap = Base.new(
		"Frame",
		{ Size = UDim2.fromOffset(22, 18), Position = UDim2.fromOffset(3, 3), ZIndex = 2, corner(3), grooves }
	)
	local t = create("TextButton")(with({
		Text = "",
		Size = UDim2.fromOffset(48, 24),
		BackgroundColor3 = C.tile,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Hover.track(hover),
		Activated = function()
			local v = not untrack(state)
			state(v)
			onChange(v)
		end,
		corner(4),
		create("UIStroke")({
			Color = function()
				return if hover() then C.dim else C.card2
			end,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		led,
		cap,
	}, props))
	effect(function()
		state()
		paint(not first)
		first = false
	end)
	return t
end

-- ── stepper: − value +, the middle types too ("12", "12 s", "1:30", "off") ──
function Controls.stepper(
	value: any,
	min: number,
	max: number,
	step: number,
	fmt: (number) -> string,
	onChange: (number) -> (),
	props: Props?
): Frame
	local v = if type(value) == "function" then value else source(value)
	local focused = source(false)
	local box
	local function side(kind: "plus" | "minus", x: number, d: number)
		local hover = source(false)
		return create("TextButton")({
			Text = "",
			Base.glyph(kind, 10, function()
				return if hover() then W else C.dim
			end),
			BackgroundColor3 = C.card2,
			BackgroundTransparency = function()
				return if hover() then 0 else 1
			end,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.fromOffset(x, 2),
			Hover.track(hover),
			Activated = function()
				local cur = untrack(v)
				local nv = math.clamp(cur + d * step, min, max)
				if nv ~= cur then
					v(nv)
					onChange(nv)
				end
			end,
			corner(3),
		})
	end
	box = create("TextBox")({
		Text = fmt(untrack(v)),
		FontFace = SB,
		TextSize = 13,
		TextColor3 = W,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Size = UDim2.new(1, -64, 1, 0),
		Position = UDim2.fromOffset(32, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		Focused = function()
			focused(true)
		end,
	}) :: TextBox
	box.Focused:Connect(function()
		box.SelectionStart = 1
		box.CursorPosition = #box.Text + 1
	end)
	box.FocusLost:Connect(function()
		focused(false)
		local t = string.lower(box.Text)
		local n
		local m, sec = string.match(t, "(%d+):(%d+)")
		if m then
			n = tonumber(m) :: number * 60 + tonumber(sec) :: number
		elseif string.find(t, "off") then
			n = min
		else
			n = tonumber(string.match(t, "[%d%.]+") or "")
		end
		local cur = untrack(v)
		if n then
			n = math.clamp(min + math.floor((n - min) / step + 0.5) * step, min, max)
			if n ~= cur then
				v(n)
				onChange(n)
			end
		end
		box.Text = fmt(untrack(v))
	end)
	effect(function()
		local x = v()
		if not untrack(focused) then
			box.Text = fmt(x)
		end
	end)
	return create("Frame")(with({
		Size = UDim2.fromOffset(120, 32),
		BackgroundColor3 = C.field,
		BorderSizePixel = 0,
		corner(4),
		box,
		create("UIStroke")({
			Color = W,
			Thickness = 1,
			Transparency = function()
				return if focused() then 0.6 else 1
			end,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		side("minus", 2, -1),
		side("plus", 90, 1),
	}, props))
end

-- ── popup menu + dropdown ──
-- the menu draws on a host frame (the page area) so it can overflow its own column
local menuHost: { frame: GuiObject?, height: number, scale: () -> number } = {
	frame = nil,
	height = Theme.PAGE_H,
	scale = function()
		return 1
	end,
}
local openMenu: Instance? = nil
local menuScope: (() -> ())? = nil

function Controls.setMenuHost(host: GuiObject, height: number, scale: () -> number)
	menuHost.frame = host
	menuHost.height = height
	menuHost.scale = scale
end

function Controls.closeMenu()
	if openMenu then
		openMenu:Destroy()
		openMenu = nil
	end
	if menuScope then
		local d = menuScope
		menuScope = nil
		d()
	end
end

-- menus are built from click handlers, so each gets its own Vide root (disposed on close)
function Controls.openMenu(anchor: GuiObject, options: { string }, current: number?, pick: (number, string) -> ())
	Controls.closeMenu()
	menuScope = Vide.root(function()
		Controls.buildMenu(anchor, options, current, pick)
	end)
end

function Controls.buildMenu(anchor: GuiObject, options: { string }, current: number?, pick: (number, string) -> ())
	local host = menuHost.frame
	if not host then
		return
	end
	local s = menuHost.scale()
	local p = (anchor.AbsolutePosition - host.AbsolutePosition) / s
	local aw, ah = anchor.AbsoluteSize.X / s, anchor.AbsoluteSize.Y / s
	local rows = math.min(#options, 8)
	local h = rows * 30 + 8
	local y = p.Y + ah + 4
	if y + h > menuHost.height - 8 then
		y = p.Y - h - 4
	end
	local items = {}
	for i, o in options do
		local hover = source(false)
		items[i] = create("TextButton")({
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = C.card2,
			BackgroundTransparency = function()
				return if hover() then 0 else 1
			end,
			BorderSizePixel = 0,
			LayoutOrder = i,
			ZIndex = 42,
			Hover.track(hover),
			Activated = function()
				Controls.closeMenu()
				pick(i, o)
			end,
			corner(4),
			label(o, {
				AutomaticSize = Enum.AutomaticSize.None,
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.new(1, -34, 1, 0),
				TextSize = 13,
				TextColor3 = if i == current then W else C.soft,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 43,
			}),
			if i == current
				then Base.new("Frame", {
					Size = UDim2.fromOffset(6, 6),
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -12, 0.5, 0),
					BackgroundColor3 = W,
					ZIndex = 43,
					corner(3),
				})
				else nil,
		})
	end
	local box = create("ScrollingFrame")({
		Position = UDim2.fromOffset(p.X, y),
		Size = UDim2.fromOffset(math.max(aw, 150), h),
		BackgroundColor3 = C.menu,
		BorderSizePixel = 0,
		ScrollBarThickness = if #options > 8 then 4 else 0,
		ScrollBarImageColor3 = C.faint,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 41,
		corner(6),
		create("UIStroke")({ Color = C.menuEdge, Thickness = 1 }),
		pad(4, 4, 4, 4),
		vlist(0),
		items,
	}) :: ScrollingFrame
	local m = create("TextButton")({
		Name = "HazaDJ_Menu",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 40,
		Activated = Controls.closeMenu,
		box,
		Parent = host,
	})
	if current and current > 8 then
		box.CanvasPosition = Vector2.new(0, (current - 4) * 30)
	end
	openMenu = m
end

-- a dropdown: index is a number or a source
function Controls.dropdown(
	options: any,
	index: any,
	onChange: (number, string) -> (),
	w: number?,
	props: Props?
): TextButton
	local cur = if type(index) == "function" then index else source(index)
	local hover = source(false)
	local btn: TextButton
	btn = create("TextButton")(with({
		Text = "",
		Size = if w then UDim2.fromOffset(w, 32) else UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = function()
			return if hover() then C.raised else C.field
		end,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Hover.track(hover),
		Activated = function()
			local opts = read(options)
			Controls.openMenu(btn, opts, untrack(cur), function(i, o)
				cur(i)
				onChange(i, o)
			end)
		end,
		corner(4),
		label(function()
			local opts = read(options)
			return opts[cur()] or "Choose…"
		end, {
			AutomaticSize = Enum.AutomaticSize.None,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -34, 1, 0),
			TextSize = 13,
			TextColor3 = function()
				return if read(options)[cur()] then W else C.faint
			end,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Controls.chevron(),
	}, props)) :: TextButton
	return btn
end

-- ── confirm modal (owner, 2026-10-22: no "click again to …"): one header, one body, Cancel + the
-- action. The scrim covers the screen; the card follows the panel's scale. Esc or the scrim cancels.
local modalHost: { gui: LayerCollector?, scale: () -> number } = {
	gui = nil,
	scale = function()
		return 1
	end,
}
function Controls.setModalHost(gui: LayerCollector, scale: () -> number)
	modalHost.gui = gui
	modalHost.scale = scale
end

export type ConfirmOpts = { title: string, body: string, action: string, onConfirm: () -> () }

function Controls.confirm(o: ConfirmOpts)
	local dispose
	dispose = Vide.root(function()
		Controls.buildConfirm(o, function()
			if dispose then
				dispose()
			end
		end)
	end)
end

function Controls.buildConfirm(o: ConfirmOpts, done: () -> ())
	local gui = modalHost.gui
	if not gui then
		return
	end
	local old = gui:FindFirstChild("HazaDJ_Modal")
	if old then
		old:Destroy()
	end
	local s = modalHost.scale()
	local scrim: TextButton
	local esc: RBXScriptConnection?
	local function close()
		if esc then
			esc:Disconnect()
		end
		scrim:Destroy()
		task.defer(done)
	end
	local scale = create("UIScale")({ Scale = s * 0.96 })
	local card = Base.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.raised,
		Active = true, -- clicks on the card don't reach the scrim
		ZIndex = 101,
		corner(8),
		create("UIStroke")({ Color = C.line, Thickness = 1 }),
		scale,
		pad(20, 20, 20, 20),
		vlist(8),
		label(o.title, { FontFace = B, TextSize = 16, LayoutOrder = 1, ZIndex = 101 }),
		label(o.body, {
			FontFace = Theme.R,
			TextSize = 13,
			TextColor3 = C.soft,
			TextWrapped = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			LayoutOrder = 2,
			ZIndex = 101,
		}),
		frame({
			Size = UDim2.new(1, 0, 0, 44),
			LayoutOrder = 3,
			ZIndex = 101,
			frame({
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.fromScale(1, 1),
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 32),
				ZIndex = 101,
				hlist(8, Enum.HorizontalAlignment.Right),
				Controls.button(
					{ text = "Cancel", kind = "secondary", h = 32, onClick = close },
					{ LayoutOrder = 1, ZIndex = 101 }
				),
				Controls.button({
					text = o.action,
					kind = "destructive",
					h = 32,
					onClick = function()
						close()
						o.onConfirm()
					end,
				}, { LayoutOrder = 2, ZIndex = 101 }),
			}),
		}),
	})
	scrim = create("TextButton")({
		Name = "HazaDJ_Modal",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 100,
		Activated = close,
		card,
		Parent = gui,
	}) :: TextButton
	TweenService:Create(scrim, Theme.FAST, { BackgroundTransparency = 0.45 }):Play()
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = s })
		:Play()
	esc = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape then
			close()
		end
	end)
end

-- ── personalised value controls: drag across, wheel = one step, double-click = default ──
local function snap(v: number, min: number, max: number, step: number): number
	return math.clamp(min + math.floor((v - min) / step + 0.5) * step, min, max)
end

export type ValueOpts = {
	min: number,
	max: number,
	step: number,
	value: number,
	default: number,
	origin: number?,
	detent: number?,
	fmt: (number) -> string,
	onChange: (number) -> (),
	-- ruler
	ticks: number?,
	major: number?,
	mid: number?,
	label: ((number) -> string)?,
	parse: ((string) -> number?)?,
}

local function valueModel(o: ValueOpts)
	local value = source(o.value)
	local function set(v: number, dragging: boolean?)
		v = snap(v, o.min, o.max, o.step)
		if dragging and o.detent and o.origin and math.abs(v - o.origin) <= o.detent then
			v = o.origin
		end
		if v ~= untrack(value) then
			value(v)
			o.onChange(v)
		end
	end
	return value, set
end

local function bindDrag(hit: GuiObject, area: GuiObject, o: ValueOpts, get: () -> number, set: (number, boolean?) -> ())
	local lastClick = 0
	local function fromX(x: number)
		local a = math.clamp((x - area.AbsolutePosition.X) / math.max(area.AbsoluteSize.X, 1), 0, 1)
		set(o.min + a * (o.max - o.min), true)
	end
	hit.InputBegan:Connect(function(io)
		if not Base.isPress(io) then
			return
		end
		local now = os.clock()
		if now - lastClick < 0.3 then
			lastClick = 0
			set(o.default)
			return
		end
		lastClick = now
		fromX(io.Position.X)
		local release = Hover.hold()
		local moveC, endC
		moveC = UserInputService.InputChanged:Connect(function(m)
			if Base.isMove(m) then
				fromX(m.Position.X)
			end
		end)
		endC = UserInputService.InputEnded:Connect(function(e)
			if Base.isPress(e) then
				moveC:Disconnect()
				endC:Disconnect()
				release()
			end
		end)
	end)
	hit.InputChanged:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseWheel then
			set(get() + (if io.Position.Z > 0 then o.step else -o.step))
		end
	end)
end

Controls.RULER_H = 44

-- ruler: ticks hang from the top edge, labels along the bottom, the stretch from the origin to the
-- value fills as a band with a 2 px line at its far edge (marker "E", owner 2026-10-22)
function Controls.ruler(w: number, o: ValueOpts, props: Props?): Frame
	local value, set = valueModel(o)
	local origin = o.origin or o.min
	local ticks = o.ticks :: number
	local rulerArea = frame({ Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0) })
	for i = 0, ticks do
		local v = o.min + (o.max - o.min) * i / ticks
		local isOrigin = math.abs(v - origin) < 1e-6
		local major, mid = i % (o.major :: number) == 0, o.mid and i % o.mid == 0
		Base.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(i / ticks, 0),
			Size = UDim2.fromOffset(
				if isOrigin then 2 else 1,
				if isOrigin then 18 elseif major then 13 elseif mid then 8 else 5
			),
			BackgroundColor3 = function()
				local x = value()
				local lit = v >= math.min(origin, x) - 1e-6 and v <= math.max(origin, x) + 1e-6
				return if lit then W else C.faint
			end,
			Parent = rulerArea,
		})
		if major then
			local edge = if i == 0 then 0 elseif i == ticks then 1 else 0.5
			label((o.label :: (number) -> string)(v), {
				AnchorPoint = Vector2.new(edge, 1),
				Position = UDim2.new(i / ticks, 0, 1, -5),
				FontFace = SB,
				TextSize = 10,
				TextColor3 = if isOrigin then C.soft else C.dim,
				Parent = rulerArea,
			})
		end
	end
	local span = o.max - o.min
	Base.new("Frame", {
		BackgroundColor3 = W,
		BackgroundTransparency = 0.86,
		ZIndex = 1,
		Position = function()
			return UDim2.fromScale((math.min(origin, value()) - o.min) / span, 0)
		end,
		Size = function()
			local x = value()
			local a, b = (math.min(origin, x) - o.min) / span, (math.max(origin, x) - o.min) / span
			return UDim2.new(b - a, 0, 1, -19)
		end,
		Parent = rulerArea,
	})
	frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0, 2, 1, -19),
		ZIndex = 2,
		Position = function()
			return UDim2.fromScale((value() - o.min) / span, 0)
		end,
		Base.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = W, ZIndex = 2 }),
		Parent = rulerArea,
	})
	local body = Base.new("Frame", {
		Size = UDim2.new(1, -70, 1, 0),
		BackgroundColor3 = C.field,
		ClipsDescendants = true,
		corner(4),
		rulerArea,
	})
	local hit = create("TextButton")({
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = body,
	})
	bindDrag(hit, rulerArea, o, function()
		return untrack(value)
	end, set)
	local box = Controls.input({
		placeholder = "",
		w = 62,
		text = function()
			return o.fmt(value())
		end,
		onCommit = function(text)
			local n = o.parse and o.parse(text)
			set(n or untrack(value))
		end,
		box = { TextXAlignment = Enum.TextXAlignment.Center, FontFace = B, TextSize = 14 },
	}, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 62, 1, 0) })
	return frame(with({ Size = UDim2.fromOffset(w, Controls.RULER_H), body, box }, props))
end

-- loudness: a rising LED staircase; the top three are the red peak
function Controls.meter(w: number, o: ValueOpts, props: Props?): Frame
	local N = 20
	local value, set = valueModel(o)
	local areaW = w - 56
	local PITCH = math.floor(areaW / N)
	local area = frame({ Size = UDim2.fromOffset(PITCH * N, 32) })
	for i = 1, N do
		Base.new("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, (i - 1) * PITCH, 1, -4),
			Size = UDim2.fromOffset(PITCH - 2, 6 + math.floor((i - 1) * 18 / (N - 1) + 0.5)),
			BackgroundColor3 = function()
				local lit = math.floor((value() - o.min) / (o.max - o.min) * N + 0.5)
				return if i > lit then C.card2 elseif i > N - 3 then C.red else W
			end,
			Parent = area,
		})
	end
	local hit = create("TextButton")({
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = area,
	})
	bindDrag(hit, area, o, function()
		return untrack(value)
	end, set)
	return frame(with({
		Size = UDim2.fromOffset(w, 32),
		area,
		label(function()
			return o.fmt(value())
		end, {
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.fromOffset(48, 32),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			FontFace = B,
			TextSize = 13,
		}),
	}, props))
end

-- intensity: LED dots growing left to right, lit up to the value
function Controls.dots(w: number, o: ValueOpts, props: Props?): Frame
	local N = 11
	local value, set = valueModel(o)
	local area = frame({ Size = UDim2.new(1, -56, 1, 0) })
	for i = 1, N do
		local d = math.floor(4 + (i - 1) / (N - 1) * 10 + 0.5)
		Base.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new((i - 0.5) / N, 0, 0.5, 0),
			Size = UDim2.fromOffset(d, d),
			BackgroundColor3 = function()
				local v = value()
				local lit = math.floor((v - o.min) / (o.max - o.min) * (N - 1) + 0.5) + 1
				return if v > o.min and i <= lit then W else C.card2
			end,
			corner(d),
			Parent = area,
		})
	end
	local hit = create("TextButton")({
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = area,
	})
	bindDrag(hit, area, o, function()
		return untrack(value)
	end, set)
	return frame(with({
		Size = UDim2.fromOffset(w, 32),
		area,
		label(function()
			return o.fmt(value())
		end, {
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.fromOffset(48, 32),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			FontFace = B,
			TextSize = 13,
		}),
	}, props))
end

return Controls
