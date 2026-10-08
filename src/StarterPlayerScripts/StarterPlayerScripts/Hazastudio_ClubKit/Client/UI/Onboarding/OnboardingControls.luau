--!strict
-- Onboarding right-panel pieces: page + header, the theme dot grid and the grouped option rows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AccentDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.AccentDomain)
local AccentService = require(script.Parent.Parent.Parent.Services.AccentService)
local GroupedRowCornerUtil = require(script.Parent.Parent.Parent.Utils.GroupedRowCornerUtil)
local UIMotion = require(script.Parent.Parent.Parent.Utils.UIMotion)
local Kit = require(script.Parent.OnboardingKit)

type Ctx = Kit.Ctx

export type OptionItem = { key: string, title: string, hint: string, icon: string? }

local tween = Kit.tween
local WHITE = Kit.WHITE
local SUB = Kit.SUB

local Controls = {}

function Controls.newPage(): Frame
	local page = Instance.new("Frame")
	page.BackgroundTransparency = 1
	page.Size = UDim2.fromScale(1, 1)
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = page
	return page
end

function Controls.header(page: Instance, kicker: string, title: string, body: string)
	local k = Kit.label(page, kicker, 12, Enum.FontWeight.Bold, Kit.ACCENT_LABEL, 1)
	k:SetAttribute(Kit.TOKEN, "primary")
	Kit.label(page, title, 24, Enum.FontWeight.Bold, WHITE, 2)
	Kit.label(page, body, 14, Enum.FontWeight.SemiBold, Kit.BODY, 3)
	local gap = Instance.new("Frame")
	gap.BackgroundTransparency = 1
	gap.Size = UDim2.new(1, 0, 0, 6)
	gap.LayoutOrder = 4
	gap.Parent = page
end

function Controls.accentFill(): Color3
	if AccentService.isDesign() then
		return Kit.ACCENT_LABEL
	end
	return AccentService.get().fill
end

-- The icon image the owner's live control paints for an option (matched by its button text).
function Controls.iconFrom(container: Instance?, text: string): string?
	if not container then
		return nil
	end
	for _, b in ipairs(container:GetDescendants()) do
		if b:IsA("GuiButton") then
			local t = b:FindFirstChildOfClass("TextLabel")
			if t and t.Text == text then
				for _, d in ipairs(b:GetDescendants()) do
					if d:IsA("ImageLabel") and d.Image ~= "" then
						return d.Image
					end
				end
			end
		end
	end
	return nil
end

-- Grouped option rows: icon, title + hint, radio on the right. Calls onPick(key, initial).
function Controls.optionList(
	ctx: Ctx,
	page: Instance,
	order: number,
	items: { OptionItem },
	selectedKey: string,
	onPick: (key: string, initial: boolean) -> ()
): Frame
	local list = Instance.new("Frame")
	list.Name = "Options"
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(1, 0, 0, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = list
	local radios: { [string]: { row: TextButton, ring: Frame, stroke: UIStroke, dotScale: UIScale } } = {}
	local function paint(key: string, instant: boolean)
		local fill = Controls.accentFill()
		for k, r in pairs(radios) do
			local on = k == key
			local t = if instant then 0 else 0.2
			tween(r.ring, t, { BackgroundColor3 = fill, BackgroundTransparency = if on then 0 else 1 })
			tween(r.stroke, t, { Transparency = if on then 1 else 0 })
			tween(r.dotScale, if instant then 0 else 0.35, { Scale = if on then 1 else 0 }, Enum.EasingStyle.Back)
			tween(r.row, t, { BackgroundColor3 = if on then Kit.ROW_ON else Kit.ROW_BG })
		end
	end
	for i, it in ipairs(items) do
		local row = Instance.new("TextButton")
		row.Name = it.key
		row.Text = ""
		row.AutoButtonColor = false
		row.BackgroundColor3 = Kit.ROW_BG
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 52)
		row.LayoutOrder = i
		local p = Instance.new("UIPadding")
		p.PaddingLeft = UDim.new(0, 12)
		p.PaddingRight = UDim.new(0, 14)
		p.Parent = row
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.fromScale(0, 0.5)
		icon.Size = UDim2.fromOffset(26, 26)
		icon.Image = it.icon or ""
		icon.ImageColor3 = WHITE
		icon.Parent = row
		if not it.icon then
			-- Owner rule: no emoji; a neutral placeholder the owner swaps for a real icon.
			local ph = Instance.new("Frame")
			ph.Name = "IconPlaceholder"
			ph.AnchorPoint = Vector2.new(0.5, 0.5)
			ph.Position = UDim2.fromScale(0.5, 0.5)
			ph.Size = UDim2.fromOffset(18, 18)
			ph.BackgroundColor3 = WHITE
			ph.BackgroundTransparency = 0.8
			Kit.round(ph, UDim.new(0, 5))
			ph.Parent = icon
		end
		local title = Kit.textLabel(row, it.title, 15, Enum.FontWeight.Bold, WHITE)
		title.AnchorPoint = Vector2.new(0, 1)
		title.Position = UDim2.new(0, 38, 0.5, 0)
		title.Size = UDim2.new(1, -70, 0, 17)
		local hint = Kit.textLabel(row, it.hint, 13, Enum.FontWeight.Medium, SUB)
		hint.Position = UDim2.new(0, 38, 0.5, 2)
		hint.Size = UDim2.new(1, -70, 0, 15)
		local ring = Instance.new("Frame")
		ring.Name = "Radio"
		ring.AnchorPoint = Vector2.new(1, 0.5)
		ring.Position = UDim2.fromScale(1, 0.5)
		ring.Size = UDim2.fromOffset(20, 20)
		ring.BackgroundTransparency = 1
		Kit.round(ring, UDim.new(1, 0))
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromHex("5a5a5a")
		stroke.Thickness = 2
		stroke.Parent = ring
		local inner = Instance.new("Frame")
		inner.AnchorPoint = Vector2.new(0.5, 0.5)
		inner.Position = UDim2.fromScale(0.5, 0.5)
		inner.Size = UDim2.fromOffset(8, 8)
		inner.BackgroundColor3 = WHITE
		Kit.round(inner, UDim.new(1, 0))
		local dotScale = Instance.new("UIScale")
		dotScale.Scale = 0
		dotScale.Parent = inner
		inner.Parent = ring
		ring.Parent = row
		row.Parent = list
		radios[it.key] = { row = row, ring = ring, stroke = stroke, dotScale = dotScale }
		for _, c in ipairs(UIMotion.bindPress(row)) do
			table.insert(ctx.conns, c)
		end
		table.insert(
			ctx.conns,
			row.Activated:Connect(function()
				paint(it.key, false)
				onPick(it.key, false)
			end)
		)
	end
	list.Parent = page
	GroupedRowCornerUtil.apply(list)
	paint(selectedKey, true)
	onPick(selectedKey, true)
	return list
end

-- Theme grid straight on the panel (no wrapper card): "Accent" + live name, 7 dots per line at
-- 36px; the selected dot shrinks inside a white ring.
local DOT = 36
local PER_LINE = 7

-- "Don't show again" row: one grouped-row pill, a rounded checkbox that fills with the accent and
-- a drawn tick (no emoji, no glyph). Calls onToggle(checked) on every click.
function Controls.checkRow(ctx: Ctx, page: Instance, order: number, text: string, checked: boolean, onToggle: (checked: boolean) -> ()): TextButton
	local row = Instance.new("TextButton")
	row.Name = "CheckRow"
	row.Text = ""
	row.AutoButtonColor = false
	row.BackgroundColor3 = Kit.ROW_BG
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, 52)
	row.LayoutOrder = order
	Kit.round(row, UDim.new(0, 18))
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = row

	local box = Instance.new("Frame")
	box.Name = "Box"
	box.AnchorPoint = Vector2.new(0, 0.5)
	box.Position = UDim2.fromScale(0, 0.5)
	box.Size = UDim2.fromOffset(24, 24)
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	Kit.round(box, UDim.new(0, 8))
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromHex("5a5a5a")
	stroke.Thickness = 2
	stroke.Parent = box
	-- The tick: a short and a long bar turned 45 degrees either way.
	local tick = Instance.new("Frame")
	tick.Name = "Tick"
	tick.AnchorPoint = Vector2.new(0.5, 0.5)
	tick.Position = UDim2.fromScale(0.5, 0.5)
	tick.Size = UDim2.fromOffset(24, 24)
	tick.BackgroundTransparency = 1
	local short = Instance.new("Frame")
	short.AnchorPoint = Vector2.new(0.5, 0.5)
	short.Position = UDim2.fromOffset(8, 13)
	short.Size = UDim2.fromOffset(3, 7)
	short.Rotation = -45
	short.BackgroundColor3 = WHITE
	short.BorderSizePixel = 0
	Kit.round(short, UDim.new(1, 0))
	short.Parent = tick
	local long = Instance.new("Frame")
	long.AnchorPoint = Vector2.new(0.5, 0.5)
	long.Position = UDim2.fromOffset(13, 11)
	long.Size = UDim2.fromOffset(3, 13)
	long.Rotation = 45
	long.BackgroundColor3 = WHITE
	long.BorderSizePixel = 0
	Kit.round(long, UDim.new(1, 0))
	long.Parent = tick
	local tickScale = Instance.new("UIScale")
	tickScale.Parent = tick
	tick.Parent = box
	box.Parent = row

	local label = Kit.textLabel(row, text, 15, Enum.FontWeight.Bold, WHITE)
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0, 36, 0.5, 0)
	label.Size = UDim2.new(1, -36, 0, 18)
	row.Parent = page

	local function paint(on: boolean, instant: boolean?)
		local t = if instant then 0 else 0.2
		tween(box, t, { BackgroundTransparency = if on then 0 else 1, BackgroundColor3 = Controls.accentFill() })
		tween(stroke, t, { Transparency = if on then 1 else 0 })
		tween(tickScale, if instant then 0 else 0.3, { Scale = if on then 1 else 0 }, Enum.EasingStyle.Back)
	end
	paint(checked, true)
	for _, c in ipairs(UIMotion.bindPress(row)) do
		table.insert(ctx.conns, c)
	end
	local on = checked
	table.insert(
		ctx.conns,
		row.Activated:Connect(function()
			on = not on
			paint(on)
			onToggle(on)
		end)
	)
	return row
end

function Controls.themeGrid(ctx: Ctx, page: Instance, order: number, onPick: (id: string) -> ()): Frame
	local card = Instance.new("Frame")
	card.Name = "ThemeGrid"
	card.BackgroundTransparency = 1
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 12)
	layout.Parent = card

	local top = Instance.new("Frame")
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, 0, 0, 18)
	top.LayoutOrder = 1
	top.Parent = card
	local cap = Kit.textLabel(top, "Accent", 13, Enum.FontWeight.Medium, SUB)
	cap.Size = UDim2.fromScale(0.5, 1)
	local name = Kit.textLabel(top, "", 15, Enum.FontWeight.Bold, WHITE)
	name.AnchorPoint = Vector2.new(1, 0)
	name.Position = UDim2.fromScale(1, 0)
	name.Size = UDim2.fromScale(0.5, 1)
	name.TextXAlignment = Enum.TextXAlignment.Right

	local grid = Instance.new("Frame")
	grid.Name = "Swatches"
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, 0, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = 2
	grid:SetAttribute(Kit.NO_TINT, true)
	local gl = Instance.new("UIListLayout")
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Padding = UDim.new(0, 12)
	gl.Parent = grid
	grid.Parent = card

	-- The Settings Appearance dots, when that tab is built: same Multicolor wheel and Graphite grey.
	local ownerDots = Kit.find(ctx.src.settingsTab, "appearance_Section")
	ownerDots = if ownerDots then ownerDots:FindFirstChild("AccentSwatches", true) else nil
	local lines: { [number]: Frame } = {}
	local slots: { [string]: { slot: TextButton, ring: UIStroke, scale: UIScale } } = {}
	for index, id in ipairs(AccentDomain.ORDER) do
		local li = math.ceil(index / PER_LINE)
		if not lines[li] then
			local line = Instance.new("Frame")
			line.BackgroundTransparency = 1
			line.Size = UDim2.new(1, 0, 0, DOT)
			line.LayoutOrder = li
			local ll = Instance.new("UIListLayout")
			ll.FillDirection = Enum.FillDirection.Horizontal
			ll.HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween
			ll.VerticalAlignment = Enum.VerticalAlignment.Center
			ll.SortOrder = Enum.SortOrder.LayoutOrder
			ll.Parent = line
			line.Parent = grid
			lines[li] = line
		end
		local slot = Instance.new("TextButton")
		slot.Name = id
		slot.Text = ""
		slot.AutoButtonColor = false
		slot.BackgroundTransparency = 1
		slot.Size = UDim2.fromOffset(DOT, DOT)
		slot.LayoutOrder = index
		Kit.round(slot, UDim.new(1, 0))
		local ring = Instance.new("UIStroke")
		ring.Color = WHITE
		ring.Thickness = 2
		ring.Transparency = 1
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.Parent = slot
		local fill = Instance.new("Frame")
		fill.AnchorPoint = Vector2.new(0.5, 0.5)
		fill.Position = UDim2.fromScale(0.5, 0.5)
		fill.Size = UDim2.fromScale(1, 1)
		fill.BorderSizePixel = 0
		local src = if ownerDots then ownerDots:FindFirstChild(id, true) else nil
		fill.BackgroundColor3 = if src and src:IsA("GuiObject")
			then src.BackgroundColor3
			else Color3.fromHex(AccentDomain.swatch(id).fill)
		local grad = if src then src:FindFirstChildOfClass("UIGradient") else nil
		if grad then
			grad:Clone().Parent = fill
		end
		Kit.round(fill, UDim.new(1, 0))
		local ds = Instance.new("UIScale")
		ds.Parent = fill
		fill.Parent = slot
		slot.Parent = lines[li]
		slots[id] = { slot = slot, ring = ring, scale = ds }
	end
	local function paint(id: string, instant: boolean)
		name.Text = AccentDomain.label(id)
		for k, sl in pairs(slots) do
			local on = k == id
			local t = if instant then 0 else 0.25
			tween(sl.ring, t, { Transparency = if on then 0 else 1 })
			tween(sl.scale, t, { Scale = if on then 0.74 else 1 }, Enum.EasingStyle.Back)
		end
	end
	for id, sl in pairs(slots) do
		table.insert(
			ctx.conns,
			sl.slot.Activated:Connect(function()
				paint(id, false)
				onPick(id)
			end)
		)
	end
	card.Parent = page
	paint(AccentService.get().id, true)
	return card
end

return Controls
