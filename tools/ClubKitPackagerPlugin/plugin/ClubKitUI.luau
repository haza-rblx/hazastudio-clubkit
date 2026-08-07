--!nocheck
--[[
  Club Kit panel UI primitives — "Aurora Dusk" visual system for Studio PluginGui.
  Body type: Inter (Theme.fontFaces). Opaque fills on interactive chrome.
  No arbitrary fields on Instances — APIs live in weak maps.
]]

local Theme = require(script.Parent.DovetailTheme)
local Motion = require(script.Parent.PanelMotion)

local ClubKitUI = {}

local switchApi: { [Frame]: { set: (boolean) -> (), get: () -> boolean } } = setmetatable({}, { __mode = "k" })
local pillApi: { [TextButton]: { setSelected: (boolean) -> () } } = setmetatable({}, { __mode = "k" })

-- Thin-space letter tracking for small-caps kickers/eyebrows — a cheap but
-- distinctive premium touch (Stripe/Linear-style section labels).
local THIN_SPACE = "\u{2009}"
function ClubKitUI.tracked(text: string): string
	local out = table.create(#text * 2)
	for i = 1, #text do
		table.insert(out, text:sub(i, i))
		if i < #text then
			table.insert(out, THIN_SPACE)
		end
	end
	return table.concat(out)
end

function ClubKitUI.corner(inst: GuiObject, radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or Theme.sizes.corner)
	c.Parent = inst
	return c
end

function ClubKitUI.stroke(_inst: GuiObject, _color: Color3?, _transparency: number?, _thickness: number?): nil
	-- Strokes removed from the visual system — keep no-op for older callers.
	return nil
end

function ClubKitUI.gradient(inst: GuiObject, colorA: Color3, colorB: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(colorA, colorB)
	g.Rotation = rotation or 90
	g.Parent = inst
	return g
end

function ClubKitUI.pad(inst: GuiObject, top: number, right: number?, bottom: number?, left: number?): UIPadding
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, top)
	p.PaddingRight = UDim.new(0, right or top)
	p.PaddingBottom = UDim.new(0, bottom or top)
	p.PaddingLeft = UDim.new(0, left or right or top)
	p.Parent = inst
	return p
end

function ClubKitUI.vlist(parent: Instance, gap: number?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, gap or Theme.sizes.gap)
	l.Parent = parent
	return l
end

function ClubKitUI.hlist(parent: Instance, gap: number?, vAlign: Enum.VerticalAlignment?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, gap or 10)
	l.VerticalAlignment = vAlign or Enum.VerticalAlignment.Center
	l.Parent = parent
	return l
end

function ClubKitUI.sep(parent: Instance, order: number?): Frame
	-- Prefer section spacing over hairlines — emit an invisible spacer instead.
	local line = Instance.new("Frame")
	line.Name = "Sep"
	line.BackgroundTransparency = 1
	line.BorderSizePixel = 0
	line.Size = UDim2.new(1, 0, 0, 0)
	if order then
		line.LayoutOrder = order
	end
	line.Parent = parent
	return line
end

function ClubKitUI.label(props: {
	parent: Instance,
	text: string,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	textSize: number?,
	weight: ("regular" | "medium" | "semiBold" | "bold" | "extraBold" | "mono")?,
	color: Color3?,
	xAlign: Enum.TextXAlignment?,
	yAlign: Enum.TextYAlignment?,
	rich: boolean?,
	wrap: boolean?,
	autoHeight: boolean?,
	order: number?,
}): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Text = props.text
	l.TextColor3 = props.color or Theme.colors.text
	l.TextSize = props.textSize or Theme.sizes.body
	l.FontFace = Theme.face(props.weight)
	l.TextXAlignment = props.xAlign or Enum.TextXAlignment.Left
	l.TextYAlignment = props.yAlign or Enum.TextYAlignment.Center
	l.TextWrapped = props.wrap == true
	l.RichText = props.rich == true
	l.TextTruncate = if props.wrap then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd
	l.Size = props.size or UDim2.new(1, 0, 0, 18)
	if props.autoHeight then
		l.AutomaticSize = Enum.AutomaticSize.Y
	end
	if props.position then
		l.Position = props.position
	end
	if props.anchor then
		l.AnchorPoint = props.anchor
	end
	if props.order then
		l.LayoutOrder = props.order
	end
	l.Parent = props.parent
	return l
end

--[[ Small tracked-caps section header with a leading accent pip. ]]
function ClubKitUI.secHead(parent: Instance, text: string, order: number?): Frame
	local host = Instance.new("Frame")
	host.Name = "SecHead"
	host.BackgroundTransparency = 1
	host.Size = UDim2.new(1, 0, 0, 26)
	if order then
		host.LayoutOrder = order
	end
	host.Parent = parent
	ClubKitUI.hlist(host, 7)

	local pip = Instance.new("Frame")
	pip.Name = "Pip"
	pip.BackgroundColor3 = Theme.colors.blue
	pip.BackgroundTransparency = 0.15
	pip.BorderSizePixel = 0
	pip.Size = UDim2.new(0, 3, 0, 11)
	pip.Parent = host
	ClubKitUI.corner(pip, 2)

	ClubKitUI.label({
		parent = host,
		text = ClubKitUI.tracked(string.upper(text)),
		textSize = Theme.sizes.secHead,
		weight = "bold",
		color = Theme.colors.faint,
		order = 2,
		size = UDim2.new(1, -10, 1, 0),
		yAlign = Enum.TextYAlignment.Center,
	})
	return host
end

--[[ Page header: optional tracked kicker + title + optional subtitle. ]]
function ClubKitUI.pageHeader(props: {
	parent: Instance,
	kicker: string?,
	title: string,
	subtitle: string?,
	order: number?,
}): (Frame, TextLabel, TextLabel?)
	local host = Instance.new("Frame")
	host.Name = "PageHeader"
	host.BackgroundTransparency = 1
	host.Size = UDim2.new(1, 0, 0, 0)
	host.AutomaticSize = Enum.AutomaticSize.Y
	host.LayoutOrder = props.order or 1
	host.Parent = props.parent
	ClubKitUI.vlist(host, 4)

	if props.kicker then
		ClubKitUI.label({
			parent = host,
			text = ClubKitUI.tracked(string.upper(props.kicker)),
			textSize = Theme.sizes.kicker,
			weight = "bold",
			color = Theme.colors.blueBright,
			order = 1,
			size = UDim2.new(1, 0, 0, 16),
		})
	end

	local title = ClubKitUI.label({
		parent = host,
		text = props.title,
		weight = "extraBold",
		textSize = Theme.sizes.title,
		order = 2,
		size = UDim2.new(1, 0, 0, 30),
	})

	local subtitle = nil
	if props.subtitle then
		subtitle = ClubKitUI.label({
			parent = host,
			text = props.subtitle,
			weight = "medium",
			textSize = Theme.sizes.subtitle,
			color = Theme.colors.muted,
			wrap = true,
			autoHeight = true,
			order = 3,
			size = UDim2.new(1, 0, 0, 0),
		})
	end

	local spacer = Instance.new("Frame")
	spacer.Name = "HeaderSpacer"
	spacer.BackgroundTransparency = 1
	spacer.Size = UDim2.new(1, 0, 0, 0)
	spacer.LayoutOrder = 9
	spacer.Parent = host

	return host, title, subtitle
end

--[[ Elevated card container. Returns (card, body) — append children to body. ]]
function ClubKitUI.card(props: {
	parent: Instance,
	order: number?,
	padding: number?,
	gap: number?,
}): (Frame, Frame)
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.BackgroundColor3 = Theme.colors.card
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.LayoutOrder = props.order
	card.Parent = props.parent
	ClubKitUI.corner(card, Theme.sizes.cardCorner)

	local padAmt = props.padding or 14
	ClubKitUI.pad(card, padAmt, padAmt, padAmt, padAmt)

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Parent = card
	ClubKitUI.vlist(body, props.gap or 10)

	return card, body
end

--[[ Plain semibold header for use INSIDE a card (no tracking/pip — the card
     border already provides the grouping cue). ]]
function ClubKitUI.cardTitle(parent: Instance, title: string, desc: string?, order: number?): Frame
	local host = Instance.new("Frame")
	host.Name = "CardTitle"
	host.BackgroundTransparency = 1
	host.Size = UDim2.new(1, 0, 0, 0)
	host.AutomaticSize = Enum.AutomaticSize.Y
	if order then
		host.LayoutOrder = order
	end
	host.Parent = parent
	ClubKitUI.vlist(host, 3)
	ClubKitUI.label({
		parent = host,
		text = title,
		weight = "bold",
		textSize = 15,
		order = 1,
		size = UDim2.new(1, 0, 0, 20),
	})
	if desc then
		ClubKitUI.label({
			parent = host,
			text = desc,
			weight = "medium",
			textSize = Theme.sizes.bodySm,
			color = Theme.colors.faint,
			wrap = true,
			autoHeight = true,
			order = 2,
			size = UDim2.new(1, 0, 0, 0),
		})
	end
	return host
end

function ClubKitUI.button(props: {
	parent: Instance?,
	text: string,
	variant: ("primary" | "ghost" | "danger")?,
	small: boolean?,
	order: number?,
	onClick: (() -> ())?,
}): TextButton
	local variant = props.variant or "primary"
	local primary = variant == "primary"
	local danger = variant == "danger"
	local small = props.small == true
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.Text = props.text
	b.FontFace = Theme.fontFaces.bold
	b.TextSize = small and Theme.sizes.bodySm or Theme.sizes.body
	b.TextColor3 = Theme.colors.text
	b.BackgroundColor3 = if primary then Theme.colors.blue elseif danger then Theme.colors.error else Theme.colors.hover
	b.BackgroundTransparency = 0
	-- Fixed height; width from text. Do NOT use UIPadding / UIGradient —
	-- both blank TextButton paint in this Studio PluginGui.
	local padX = small and 28 or 36
	b.Size = UDim2.new(0, math.max(#props.text * 9 + padX, small and 72 or 88), 0, small and Theme.sizes.buttonSmallH or Theme.sizes.buttonH)
	b.AutomaticSize = Enum.AutomaticSize.None
	ClubKitUI.corner(b, Theme.sizes.pill)
	if danger then
		b.TextColor3 = Theme.colors.text
		b.BackgroundColor3 = Theme.colors.error
	end
	if props.order then
		b.LayoutOrder = props.order
	end
	if props.parent then
		b.Parent = props.parent
	end
	b.MouseButton1Click:Connect(function()
		if props.onClick then
			props.onClick()
		end
	end)
	b.MouseEnter:Connect(function()
		if primary then
			b.BackgroundColor3 = Theme.colors.blueBright
		elseif danger then
			b.BackgroundColor3 = Theme.colors.error:Lerp(Color3.new(1, 1, 1), 0.12)
		else
			b.BackgroundColor3 = Theme.colors.elevated
		end
	end)
	b.MouseLeave:Connect(function()
		if primary then
			b.BackgroundColor3 = Theme.colors.blue
		elseif danger then
			b.BackgroundColor3 = Theme.colors.error
		else
			b.BackgroundColor3 = Theme.colors.hover
		end
	end)
	Motion.bindPress(b)
	return b
end

function ClubKitUI.input(props: {
	parent: Instance,
	value: string?,
	placeholder: string?,
	order: number?,
	size: UDim2?,
	onChanged: ((string) -> ())?,
}): TextBox
	local box = Instance.new("TextBox")
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Text = props.value or ""
	box.PlaceholderText = props.placeholder or ""
	box.PlaceholderColor3 = Theme.colors.placeholder
	box.TextColor3 = Theme.colors.text
	box.BackgroundColor3 = Theme.colors.elevated
	box.FontFace = Theme.fontFaces.medium
	box.TextSize = Theme.sizes.body
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextTruncate = Enum.TextTruncate.AtEnd
	box.Size = props.size or UDim2.new(1, 0, 0, Theme.sizes.inputH)
	ClubKitUI.pad(box, 0, 14, 0, 14)
	ClubKitUI.corner(box)
	if props.order then
		box.LayoutOrder = props.order
	end
	box.Parent = props.parent
	box.Focused:Connect(function()
		box.BackgroundColor3 = Theme.colors.hover
	end)
	box.FocusLost:Connect(function()
		box.BackgroundColor3 = Theme.colors.elevated
	end)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if props.onChanged then
			props.onChanged(box.Text)
		end
	end)
	return box
end

function ClubKitUI.field(props: {
	parent: Instance,
	label: string,
	value: string?,
	placeholder: string?,
	hint: string?,
	order: number?,
	onChanged: ((string) -> ())?,
}): Frame
	local f = Instance.new("Frame")
	f.Name = "Field"
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.new(1, 0, 0, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	if props.order then
		f.LayoutOrder = props.order
	end
	f.Parent = props.parent
	ClubKitUI.vlist(f, 6)

	ClubKitUI.label({
		parent = f,
		text = ClubKitUI.tracked(string.upper(props.label)),
		textSize = 11,
		weight = "bold",
		color = Theme.colors.faint,
		order = 1,
		size = UDim2.new(1, 0, 0, 14),
	})
	ClubKitUI.input({
		parent = f,
		value = props.value,
		placeholder = props.placeholder,
		order = 2,
		onChanged = props.onChanged,
	})
	if props.hint then
		ClubKitUI.label({
			parent = f,
			text = props.hint,
			textSize = Theme.sizes.hint,
			weight = "medium",
			color = Theme.colors.faint,
			wrap = true,
			autoHeight = true,
			order = 3,
			size = UDim2.new(1, 0, 0, 0),
		})
	end

	local spacer = Instance.new("Frame")
	spacer.Name = "FieldSpacer"
	spacer.BackgroundTransparency = 1
	spacer.Size = UDim2.new(1, 0, 0, 8)
	spacer.LayoutOrder = 99
	spacer.Parent = f
	return f
end

--[[ Switch: pill track, thumb grows + brightens when on. ]]
function ClubKitUI.switch(props: {
	parent: Instance?,
	on: boolean?,
	onChanged: ((boolean) -> ())?,
}): Frame
	local on = props.on == true
	local W, H = Theme.sizes.switchW, Theme.sizes.switchH

	local track = Instance.new("Frame")
	track.Name = "Switch"
	track.BorderSizePixel = 0
	track.Size = UDim2.new(0, W, 0, H)
	ClubKitUI.corner(track, Theme.sizes.pill)

	local thumb = Instance.new("Frame")
	thumb.Name = "Thumb"
	thumb.BorderSizePixel = 0
	thumb.AnchorPoint = Vector2.new(0, 0.5)
	ClubKitUI.corner(thumb, Theme.sizes.pill)
	thumb.Parent = track

	local function apply(state: boolean, animate: boolean?)
		on = state
		local d = on and 17 or 12
		local pos = UDim2.new(0, on and (W - d - 3) or 5, 0.5, 0)
		local trackColor = on and Theme.colors.blue or Theme.colors.switchOff
		local thumbColor = on and Theme.colors.text or Theme.colors.switchThumbOff
		if animate then
			Motion.tween(track, { BackgroundColor3 = trackColor }, TweenInfo.new(0.16))
			Motion.tween(thumb, { BackgroundColor3 = thumbColor, Size = UDim2.new(0, d, 0, d), Position = pos }, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
		else
			track.BackgroundColor3 = trackColor
			thumb.BackgroundColor3 = thumbColor
			thumb.Size = UDim2.new(0, d, 0, d)
			thumb.Position = pos
		end
	end
	apply(on, false)

	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.Size = UDim2.new(1, 0, 1, 0)
	hit.ZIndex = 2
	hit.Parent = track
	hit.MouseButton1Click:Connect(function()
		apply(not on, true)
		if props.onChanged then
			props.onChanged(on)
		end
	end)

	if props.parent then
		track.Parent = props.parent
	end
	switchApi[track] = {
		set = function(state: boolean)
			apply(state, true)
		end,
		get = function()
			return on
		end,
	}
	return track
end

function ClubKitUI.setSwitch(track: Frame, state: boolean)
	local api = switchApi[track]
	if api then
		api.set(state)
	end
end

--[[ Settings-style row: label + optional desc on the left, optional control on the right.
     Hovers with a soft fill when `hoverable` is set (rows with only static info skip it). ]]
function ClubKitUI.row(props: {
	parent: Instance,
	label: string,
	desc: string?,
	labelColor: Color3?,
	order: number?,
	right: GuiObject?,
	rightWidth: number?,
	noBorder: boolean?,
	hoverable: boolean?,
}): Frame
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundColor3 = Theme.colors.card
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	if props.order then
		row.LayoutOrder = props.order
	end
	row.Parent = props.parent

	ClubKitUI.pad(row, 11, 2, 11, 2)
	-- Dividers removed — rows space via padding only.

	local rightW = props.rightWidth or (props.right and 120 or 0)
	local textCol = Instance.new("Frame")
	textCol.Name = "TextCol"
	textCol.BackgroundTransparency = 1
	textCol.Size = UDim2.new(1, -rightW, 0, 0)
	textCol.AutomaticSize = Enum.AutomaticSize.Y
	textCol.Parent = row
	ClubKitUI.vlist(textCol, 3)

	ClubKitUI.label({
		parent = textCol,
		text = props.label,
		textSize = Theme.sizes.body,
		weight = "semiBold",
		color = props.labelColor,
		order = 1,
		size = UDim2.new(1, 0, 0, 22),
	})
	if props.desc then
		ClubKitUI.label({
			parent = textCol,
			text = props.desc,
			textSize = Theme.sizes.bodySm,
			weight = "medium",
			color = Theme.colors.faint,
			wrap = true,
			autoHeight = true,
			order = 2,
			size = UDim2.new(1, 0, 0, 0),
		})
	end

	if props.right then
		props.right.AnchorPoint = Vector2.new(1, 0.5)
		props.right.Position = UDim2.new(1, -4, 0.5, 0)
		props.right.Parent = row
	end

	if props.hoverable then
		ClubKitUI.corner(row, Theme.sizes.corner)
		row.MouseEnter:Connect(function()
			Motion.tween(row, { BackgroundTransparency = 0.55 }, TweenInfo.new(0.14))
		end)
		row.MouseLeave:Connect(function()
			Motion.tween(row, { BackgroundTransparency = 1 }, TweenInfo.new(0.14))
		end)
	end
	return row
end

function ClubKitUI.pill(props: {
	parent: Instance,
	text: string,
	selected: boolean?,
	order: number?,
	onClick: (() -> ())?,
}): TextButton
	local p = Instance.new("TextButton")
	p.AutoButtonColor = false
	p.BorderSizePixel = 0
	p.Text = props.text
	p.FontFace = Theme.fontFaces.semiBold
	p.TextSize = Theme.sizes.bodySm
	p.AutomaticSize = Enum.AutomaticSize.X
	p.Size = UDim2.new(0, 0, 0, 34)
	ClubKitUI.pad(p, 0, 16, 0, 16)
	ClubKitUI.corner(p, Theme.sizes.pill)
	if props.order then
		p.LayoutOrder = props.order
	end

	local function applySelected(sel: boolean)
		-- Solid fills only — no outline stroke
		p.BackgroundColor3 = sel and Theme.colors.blue or Theme.colors.elevated
		p.BackgroundTransparency = sel and 0.72 or 0
		p.TextColor3 = sel and Theme.colors.text or Theme.colors.muted
		p.FontFace = sel and Theme.fontFaces.bold or Theme.fontFaces.semiBold
	end
	applySelected(props.selected == true)

	p.Parent = props.parent
	p.MouseButton1Click:Connect(function()
		if props.onClick then
			props.onClick()
		end
	end)
	Motion.bindPress(p)
	pillApi[p] = { setSelected = applySelected }
	return p
end

function ClubKitUI.setPillSelected(p: TextButton, sel: boolean)
	local api = pillApi[p]
	if api then
		api.setSelected(sel)
	end
end

--[[ Pill group: renders options, tracks selection, returns setter. ]]
function ClubKitUI.pillGroup(props: {
	parent: Instance,
	options: { { string } }, -- { {value, label}, ... }
	selected: string?,
	onSelect: ((string) -> ())?,
}): (Frame, (string) -> ())
	local host = Instance.new("Frame")
	host.BackgroundTransparency = 1
	host.AutomaticSize = Enum.AutomaticSize.XY
	host.Size = UDim2.new(0, 0, 0, 30)
	ClubKitUI.hlist(host, 8)
	host.Parent = props.parent

	local pills: { [string]: TextButton } = {}
	local function select(value: string)
		for v, btn in pills do
			ClubKitUI.setPillSelected(btn, v == value)
		end
	end
	for i, opt in props.options do
		local value, text = opt[1], opt[2]
		pills[value] = ClubKitUI.pill({
			parent = host,
			text = text,
			selected = props.selected == value,
			order = i,
			onClick = function()
				select(value)
				if props.onSelect then
					props.onSelect(value)
				end
			end,
		})
	end
	return host, select
end

function ClubKitUI.tag(parent: Instance?, text: string, order: number?, tone: ("neutral" | "accent" | "success" | "warning" | "error")?): TextLabel
	local t = Instance.new("TextLabel")
	local toneColors = {
		neutral = { bg = Theme.colors.elevated, fg = Theme.colors.muted },
		accent = { bg = Theme.colors.blue, fg = Theme.colors.blueBright },
		success = { bg = Theme.colors.success, fg = Theme.colors.success },
		warning = { bg = Theme.colors.warning, fg = Theme.colors.warning },
		error = { bg = Theme.colors.error, fg = Theme.colors.error },
	}
	local pal = toneColors[tone or "neutral"]
	t.BackgroundColor3 = pal.bg
	t.BackgroundTransparency = (tone and tone ~= "neutral") and 0.85 or 0
	t.BorderSizePixel = 0
	t.Text = text
	t.FontFace = Theme.fontFaces.bold
	t.TextSize = 11
	t.TextColor3 = pal.fg
	t.AutomaticSize = Enum.AutomaticSize.XY
	t.Size = UDim2.new(0, 0, 0, 0)
	ClubKitUI.pad(t, 4, 9, 4, 9)
	ClubKitUI.corner(t, Theme.sizes.pill)
	if order then
		t.LayoutOrder = order
	end
	if parent then
		t.Parent = parent
	end
	return t
end

function ClubKitUI.statusDot(parent: Instance?, kind: "ok" | "warn" | "fail" | "pending"): Frame
	local d = Instance.new("Frame")
	d.BorderSizePixel = 0
	d.Size = UDim2.new(0, 9, 0, 9)
	d.BackgroundColor3 = if kind == "ok"
		then Theme.colors.success
		elseif kind == "warn" then Theme.colors.warning
		elseif kind == "fail" then Theme.colors.error
		else Color3.fromHex("#333333")
	ClubKitUI.corner(d, Theme.sizes.pill)
	if parent then
		d.Parent = parent
	end
	return d
end

--[[ Elevated stat card. Returns the value label so callers can update it live. ]]
function ClubKitUI.statCard(props: {
	parent: Instance,
	order: number?,
	label: string,
	color: Color3,
	value: string?,
}): TextLabel
	local card = Instance.new("Frame")
	card.Name = "StatCard"
	card.BackgroundColor3 = Theme.colors.card
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1 / 3, -8, 1, 0)
	card.LayoutOrder = props.order
	card.Parent = props.parent
	ClubKitUI.corner(card, Theme.sizes.cardCorner)
	ClubKitUI.pad(card, 12, 14, 12, 14)

	local value = ClubKitUI.label({
		parent = card,
		text = props.value or "–",
		weight = "extraBold",
		textSize = Theme.sizes.stat,
		color = props.color,
		size = UDim2.new(1, 0, 0, 32),
	})
	ClubKitUI.label({
		parent = card,
		text = ClubKitUI.tracked(string.upper(props.label)),
		weight = "bold",
		textSize = 10.5,
		color = Theme.colors.faint,
		position = UDim2.new(0, 0, 0, 38),
		size = UDim2.new(1, 0, 0, 14),
	})
	return value
end

function ClubKitUI.toast(host: Instance): (string) -> ()
	local toast = Instance.new("TextLabel")
	toast.Name = "Toast"
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.new(0.5, 0, 1, -24)
	toast.BackgroundColor3 = Theme.colors.elevated
	toast.BorderSizePixel = 0
	toast.FontFace = Theme.fontFaces.semiBold
	toast.TextSize = Theme.sizes.body
	toast.TextColor3 = Theme.colors.text
	toast.RichText = true
	toast.Text = ""
	toast.Visible = false
	toast.ZIndex = 50
	toast.AutomaticSize = Enum.AutomaticSize.XY
	ClubKitUI.pad(toast, 12, 24, 12, 24)
	ClubKitUI.corner(toast, Theme.sizes.pill)
	toast.Parent = host

	local token = 0
	return function(msg: string)
		token += 1
		local my = token
		toast.Text = msg
		toast.Visible = true
		Motion.popIn(toast, 0)
		task.delay(3.2, function()
			if my == token and toast.Parent then
				Motion.tween(toast, { TextTransparency = 1, BackgroundTransparency = 1 }, TweenInfo.new(0.25))
				task.delay(0.25, function()
					if my == token then
						toast.Visible = false
						toast.TextTransparency = 0
						toast.BackgroundTransparency = 0
					end
				end)
			end
		end)
	end
end

return ClubKitUI
