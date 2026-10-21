--!strict
-- Client/UI/Giveaway/GiveawaySheet.luau
-- Giveaway admin sheet (opened from Admin Spotlight > Giveaway). Reference numbers read live from
-- the playtest: header row 40 (close disc, drag handle), title pill 40, card 20 px radius, body
-- rows 38 tall with grouped corners (GroupedRowCornerUtil), scrollbar via OverlayScrollbar.
-- Hero = "Tiles" (MM : SS digit tiles, players line, full-width CTA, text reset). Settings use the
-- "Combo" stepper (one capsule [ value | − | + ], the value is typed or stepped). Clicks sit above
-- the Admin Spotlight (DisplayOrder 10000). Motion: slide Exponential-out 1.0 s open, Cubic-in
-- 0.5 s close, no overshoot.

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent.Parent
local KitLook = require(Client.UI.KitLook)
local OverlayScrollbar = require(Client.UI.OverlayScrollbar)
local GroupedRowCornerUtil = require(Client.Utils.GroupedRowCornerUtil)
local AccentSurfaceTint = require(Client.Services.AccentSurfaceTint)
local GiveawayHud = require(script.Parent.GiveawayHud)

local SHEET_W, SHEET_MAX_H = 310, 600
local HEADER_H, TITLE_H, GAP_H = 40, 40, 6
local CARD_TOP = HEADER_H + GAP_H -- title pill now sits inside the card
local PAD = 12
local ROW_H = 38
local ROW_RADIUS = 12
local CARD_RADIUS = 20
local EDGE_INSET = 14
local HERO_H = 180
local ROW_BG = Color3.fromHex("1e1f18")
local STROKE_C = Color3.fromHex("111111")
local CTA_A = Color3.fromHex("6214ff")
local CTA_B = Color3.fromHex("110042")
local STEP_W, STEP_H = 112, 28
local CHEVRON = '  <font color="#5a5a5a">›</font>'
local DRAG_IMAGE = "rbxassetid://91183535922560"
local GRID_GAP = 8
local TILE_H = 50
local HIST_PREVIEW = 3
local HIST_ROW_H = 56
local PAID_W = 76
local ANCHOR_OPTIONS = { "TopLeft", "TopCenter", "TopRight" }
local ANCHOR_LABEL = { TopLeft = "Top left", TopCenter = "Top centre", TopRight = "Top right" }
local CINEMA_OPTIONS = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }
local SLIDE_OPEN = TweenInfo.new(1.0, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
local SLIDE_CLOSE = TweenInfo.new(0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.In)

type HudState = GiveawayHud.HudState

local function stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function bareButton(parent: Instance, name: string, size: UDim2, order: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundTransparency = 1
	b.Size = size
	b.LayoutOrder = order
	b.Parent = parent
	return b
end

-- A vertical list whose visible children get grouped-row corners (GroupedRowCornerUtil).
local function makeList(parent: Instance, order: number): Frame
	local c = KitLook.box(parent, "List", UDim2.new(1, 0, 0, 0), order, nil)
	c.AutomaticSize = Enum.AutomaticSize.Y
	KitLook.list(c, Enum.FillDirection.Vertical, 2)
	return c
end

local function listRow(list: Frame, index: number, height: number): Frame
	return KitLook.box(list, "Row" .. index, UDim2.new(1, 0, 0, height), index, ROW_BG)
end

local function rowTitle(row: Frame, text: string): TextLabel
	local l = KitLook.text(row, text, 14, Enum.FontWeight.SemiBold, KitLook.COLOR.white, 0, { truncate = true })
	l.Position = UDim2.fromOffset(14, 0)
	l.Size = UDim2.new(0.5, -14, 1, 0)
	return l
end

-- Right-aligned tappable value (chevron text), right edge at EDGE_INSET like every other control.
local function valueButton(row: Frame): (TextButton, TextLabel)
	local btn = bareButton(row, "ValueButton", UDim2.new(0.5, 0, 1, 0), 0)
	btn.AnchorPoint = Vector2.new(1, 0)
	btn.Position = UDim2.fromScale(1, 0)
	local label = KitLook.text(btn, "", 14, Enum.FontWeight.SemiBold, KitLook.COLOR.bodyText, 0)
	label.AutomaticSize = Enum.AutomaticSize.None
	label.Size = UDim2.new(1, -EDGE_INSET, 1, 0)
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.RichText = true
	return btn, label
end

local function anchorRight(f: GuiObject)
	f.AnchorPoint = Vector2.new(1, 0.5)
	f.Position = UDim2.new(1, -EDGE_INSET, 0.5, 0)
end

-- "60 min" → number white, unit muted.
local function unitText(number: string, unit: string?): string
	if not unit then
		return number
	end
	return number .. ' <font color="#828282">' .. unit .. "</font>"
end

local function cinemaText(v: any): string
	if v == 0 then
		return "None"
	end
	local names = {
		"Crown Descent", "Supernova", "Club Takeover", "Ascension Vortex", "Time Freeze",
		"Spotlight Search", "Lightning Strike", "Fireworks Finale", "Red Carpet", "Portal Arrival",
		"Shockwave Slam", "Aurora Crown", "Stage Rise", "Glitch", "Cosmic Zoom",
	}
	return names[tonumber(v) or 0] or ("Variant " .. tostring(v))
end

local function nudge(adminEvent: RemoteEvent, key: string, cur: number, dir: number, step: number, lo: number, hi: number, scale: number)
	local n = math.clamp(cur + dir * step, lo, hi)
	n = math.floor(n * 10 + 0.5) / 10
	adminEvent:FireServer("setConfig", { key = key, value = n * scale })
end

-- Typed value from the Combo field: each key maps to its setConfig payload.
local function comboSet(adminEvent: RemoteEvent, key: string, n: number)
	if key == "Interval" then
		adminEvent:FireServer("setConfig", { key = "IntervalSeconds", value = math.floor(n) * 60 })
	elseif key == "MinPlayers" then
		adminEvent:FireServer("setConfig", { key = "MinPlayers", value = math.floor(n) })
	elseif key == "SpinDuration" then
		adminEvent:FireServer("setConfig", { key = "SpinDuration", value = math.floor(n * 10 + 0.5) / 10 })
	end
end

-- Combo stepper: one capsule [ value field | − │ + ]. The value itself is a TextBox, so admins can
-- type a number as well as step it.
local function comboStepper(adminEvent: RemoteEvent, row: Frame, onMinus: () -> (), onPlus: () -> (), key: string): TextBox
	local COLOR = KitLook.COLOR
	local BTN, GAP = 26, 4
	local PILL_W = BTN * 2
	local box = KitLook.box(row, "Stepper", UDim2.fromOffset(STEP_W + 8, STEP_H), 0, nil)
	anchorRight(box)
	local field = KitLook.box(box, "Field", UDim2.new(1, -(PILL_W + GAP), 1, 0), 0, COLOR.closeDisc)
	KitLook.corner(field, UDim.new(0, 8))
	local pill = KitLook.box(box, "Buttons", UDim2.fromOffset(PILL_W, STEP_H), 0, COLOR.closeDisc)
	pill.AnchorPoint = Vector2.new(1, 0)
	pill.Position = UDim2.fromScale(1, 0)
	KitLook.corner(pill, UDim.new(0, 8))
	-- Glyphs drawn as 2 px bars (font − / + sit off-centre), exactly centred in each half;
	-- white hairline between them.
	local function iconButton(name: string, x: number, vertical: boolean): TextButton
		local b = bareButton(pill, name, UDim2.fromOffset(BTN, STEP_H), 0)
		b.Position = UDim2.fromOffset(x, 0)
		local bars = {}
		local function bar(size: UDim2)
			local f = KitLook.box(b, "Bar", size, 0, COLOR.sub)
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.fromScale(0.5, 0.5)
			KitLook.corner(f, UDim.new(1, 0))
			table.insert(bars, f)
		end
		bar(UDim2.fromOffset(10, 2))
		if vertical then
			bar(UDim2.fromOffset(2, 10))
		end
		b.MouseEnter:Connect(function()
			for _, f in ipairs(bars) do
				f.BackgroundColor3 = COLOR.white
			end
		end)
		b.MouseLeave:Connect(function()
			for _, f in ipairs(bars) do
				f.BackgroundColor3 = COLOR.sub
			end
		end)
		return b
	end
	local minus = iconButton("Minus", 0, false)
	local plus = iconButton("Plus", BTN, true)
	local hair = KitLook.box(pill, "Divider", UDim2.fromOffset(1, 14), 0, COLOR.white, 0.88)
	hair.AnchorPoint = Vector2.new(0.5, 0.5)
	hair.Position = UDim2.fromScale(0.5, 0.5)
	local input = Instance.new("TextBox")
	input.Name = "Value"
	input.BackgroundTransparency = 1
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.RichText = true
	input.TextSize = 13
	input.FontFace = KitLook.font(Enum.FontWeight.SemiBold)
	input.TextColor3 = COLOR.white
	input.TextXAlignment = Enum.TextXAlignment.Center
	input.Size = UDim2.fromScale(1, 1)
	input.Text = ""
	input.Parent = field
	local shown = ""
	input.Focused:Connect(function()
		shown = input.Text
		input.Text = string.match(shown:gsub("<[^>]->", ""), "[%d%.]+") or ""
		field.BackgroundColor3 = COLOR.header
	end)
	input.FocusLost:Connect(function()
		field.BackgroundColor3 = COLOR.closeDisc
		local n = tonumber(string.match(input.Text, "[%d%.]+") or "")
		input.Text = shown
		if n then
			comboSet(adminEvent, key, n)
		end
	end)
	minus.Activated:Connect(onMinus)
	plus.Activated:Connect(onPlus)
	return input
end

local DRAG_SIZE = 36
local function chromeDisc(parent: Instance, name: string, order: number, image: string?, glyph: string?, bg: Color3): TextButton
	local d = Instance.new("TextButton")
	d.Name = name
	d.AutoButtonColor = false
	d.BorderSizePixel = 0
	d.Size = UDim2.fromOffset(DRAG_SIZE, DRAG_SIZE)
	d.LayoutOrder = order
	d.BackgroundColor3 = bg
	d.Text = glyph or ""
	d.TextSize = 18
	d.FontFace = KitLook.font(Enum.FontWeight.Bold)
	d.TextColor3 = KitLook.COLOR.closeGlyph
	KitLook.corner(d, UDim.new(1, 0))
	stroke(d, Color3.fromHex("292929"), 1)
	if image then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Image = image
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = if image == DRAG_IMAGE then UDim2.fromOffset(24, 24) else UDim2.new(1, -8, 1, -8)
		img.Parent = d
	end
	d.Parent = parent
	return d
end

-- Custom Title modal chrome: a 40 px row above the card with centred 36 px discs (drag handle +
-- close), then the card whose top is a full-round header pill and the body below.
local function chrome(parent: Instance, title: string, glyph: string, discOnRight: boolean): (TextLabel, TextButton, Frame)
	-- CT 01-DraggableFrame: SpaceBetween row of three 36 px slots — empty | drag | close
	-- (stacked sheets: back | drag | empty).
	local COLOR = KitLook.COLOR
	local header = KitLook.box(parent, "Header", UDim2.new(1, 0, 0, HEADER_H), 0, nil)
	local row = KitLook.list(header, Enum.FillDirection.Horizontal, 0, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	pcall(function()
		(row :: any).HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween
	end)
	local disc: TextButton
	if discOnRight then
		KitLook.box(header, "Spacer", UDim2.fromOffset(DRAG_SIZE, DRAG_SIZE), 1, nil)
		chromeDisc(header, "Drag", 2, DRAG_IMAGE, nil, COLOR.panel)
		disc = chromeDisc(header, "Close", 3, KitLook.CLOSE_IMAGE, nil, COLOR.closeDisc)
	else
		disc = chromeDisc(header, "Back", 1, nil, glyph, COLOR.closeDisc)
		chromeDisc(header, "Drag", 2, DRAG_IMAGE, nil, COLOR.panel)
		KitLook.box(header, "Spacer", UDim2.fromOffset(DRAG_SIZE, DRAG_SIZE), 3, nil)
	end
	local card = KitLook.box(parent, "Card", UDim2.new(1, 0, 1, -CARD_TOP), 2, COLOR.panel)
	card.Position = UDim2.fromOffset(0, CARD_TOP)
	KitLook.corner(card, UDim.new(0, CARD_RADIUS))
	stroke(card, STROKE_C, 1)
	KitLook.shadow(card)
	local pill = KitLook.box(card, "TitlePill", UDim2.new(1, 0, 0, TITLE_H), 1, COLOR.panel)
	KitLook.splitCorner(pill, CARD_RADIUS, 0) -- follows the card top, square bottom
	stroke(pill, Color3.fromHex("1b1b1b"), 1)
	local textX = 20
	local label = KitLook.text(pill, title, 16, Enum.FontWeight.Bold, COLOR.white, 0, { truncate = true })
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0, textX, 0.5, 0)
	label.Size = UDim2.new(1, -(textX + 20), 0, 22)
	local host = KitLook.box(card, "BodyHost", UDim2.new(1, 0, 1, -TITLE_H), 2, nil)
	host.Position = UDim2.fromOffset(0, TITLE_H)
	host.ClipsDescendants = true
	return label, disc, host
end

-- Scrolling body inside a card; native bar hidden, kit OverlayScrollbar shown instead.
local function scrollBody(card: Frame, name: string): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.Name = name
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.Size = UDim2.fromScale(1, 1)
	s.CanvasSize = UDim2.new()
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.ScrollBarThickness = 0
	s.ScrollBarImageTransparency = 1
	s.Parent = card
	KitLook.padding(s, PAD, PAD, PAD, 14)
	local layout = KitLook.list(s, Enum.FillDirection.Vertical, 10)
	-- AutomaticCanvasSize undercounts nested AutomaticSize lists (last row was cut off):
	-- size the canvas from the layout's content instead.
	s.AutomaticCanvasSize = Enum.AutomaticSize.None
	local function fit()
		s.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + PAD + 14)
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
	fit()
	return s
end

-- Primary CTA: gradient pill (round = orb). Returns the button, its label, fill and gradient.
local function ctaPill(parent: Instance, size: UDim2, text: string, round: boolean, onPress: () -> ()): (TextButton, TextLabel, Frame, UIGradient)
	local COLOR = KitLook.COLOR
	local b = bareButton(parent, "SpinNow", size, 0)
	local fill = KitLook.box(b, "Fill", UDim2.fromScale(1, 1), 0, COLOR.white)
	KitLook.corner(fill, UDim.new(1, 0))
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(CTA_A, CTA_B)
	g.Rotation = if round then 45 else 0
	g.Parent = fill
	local l = KitLook.text(b, text, 14, Enum.FontWeight.Bold, COLOR.white, 0)
	l.AutomaticSize = Enum.AutomaticSize.None
	l.Size = UDim2.fromScale(1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.ZIndex = 2
	b.Activated:Connect(onPress)
	return b, l, fill, g
end

local function paintCta(l: TextLabel, fill: Frame, g: UIGradient, live: boolean, idleText: string)
	local COLOR = KitLook.COLOR
	l.Text = if live then "Drawing…" else idleText
	fill.BackgroundColor3 = if live then COLOR.closeDisc else COLOR.white
	l.TextColor3 = if live then COLOR.sub else COLOR.white
	g.Enabled = not live
end

local function secondary(parent: Instance, size: UDim2, text: string, onPress: () -> ()): TextButton
	local COLOR = KitLook.COLOR
	local b = bareButton(parent, "Reset", size, 0)
	b.BackgroundColor3 = COLOR.closeDisc
	b.BackgroundTransparency = 0
	KitLook.corner(b, UDim.new(1, 0))
	b.Text = text
	b.TextSize = 13
	b.FontFace = KitLook.font(Enum.FontWeight.SemiBold)
	b.TextColor3 = COLOR.bodyText
	b.Activated:Connect(onPress)
	return b
end

local function playersRich(count: number, min: number): string
	return string.format('%d/%d <font color="#828282">players</font>', count, min)
end

local GiveawaySheet = {}

-- state: the controller's table (read here, updated there). deps.isBusy: a spin is running.
function GiveawaySheet.new(playerGui: PlayerGui, state: HudState, deps: { adminEvent: RemoteEvent, isBusy: () -> boolean })
	local adminEvent = deps.adminEvent
	local isBusy = deps.isBusy
	local COLOR = KitLook.COLOR

	-- Sheet shell -------------------------------------------------
	local sheetGui = Instance.new("ScreenGui")
	sheetGui.Name = "GiveawaySheet"
	sheetGui.ResetOnSpawn = false
	sheetGui.IgnoreGuiInset = true
	sheetGui.DisplayOrder = 10000
	sheetGui.Enabled = false
	sheetGui.Parent = playerGui
	pcall(AccentSurfaceTint.attach, sheetGui)

	local sheet = KitLook.box(sheetGui, "Sheet", UDim2.new(0, SHEET_W, 1, -48), 1, nil)
	sheet.AnchorPoint = Vector2.new(0.5, 0.5)
	sheet.Position = UDim2.fromScale(0.5, 0.5)
	local sizeCap = Instance.new("UISizeConstraint")
	sizeCap.MaxSize = Vector2.new(SHEET_W, SHEET_MAX_H)
	sizeCap.Parent = sheet
	local sheetTween: Tween? = nil
	local sheetOpen = false
	local sheetOffset = Vector2.zero -- drag offset from screen centre, kept across open/close

	-- The sheet lives between the topbar (gui inset) and, on phones, the bottom hotbar strip;
	-- sheetBaseY re-centres it in that band. Offsets are clamped so it never leaves the band.
	local sheetBaseY = 0
	local function fitSheet()
		local view = sheetGui.AbsoluteSize
		local top = GuiService:GetGuiInset().Y + 6
		local bottom = if view.Y < 500 then 58 else 12
		sheet.Size = UDim2.new(0, SHEET_W, 1, -(top + bottom))
		sheetBaseY = (top - bottom) / 2
	end
	local function clampVec(o: Vector2): Vector2
		local view = sheetGui.AbsoluteSize
		local size = sheet.AbsoluteSize
		local top = GuiService:GetGuiInset().Y + 6
		local bottom = if view.Y < 500 then 58 else 12
		local mx = math.max(0, (view.X - size.X) / 2)
		local minY = top + size.Y / 2 - view.Y / 2 - sheetBaseY
		local maxY = view.Y - bottom - size.Y / 2 - view.Y / 2 - sheetBaseY
		return Vector2.new(math.clamp(o.X, -mx, mx), math.clamp(o.Y, math.min(minY, maxY), math.max(minY, maxY)))
	end
	local function clampSheetOffset()
		fitSheet()
		sheetOffset = clampVec(sheetOffset)
	end
	sheetGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		clampSheetOffset()
		if sheetOpen then
			sheet.Position = UDim2.new(0.5, sheetOffset.X, 0.5, sheetBaseY + sheetOffset.Y)
		end
	end)
	fitSheet()

	local _titleLabel, closeBtn, card = chrome(sheet, "Giveaway", "×", true)
	local scroll = scrollBody(card, "Body")
	OverlayScrollbar.attach(scroll, sheet, { side = "right", centerOn = scroll })

	local function sectionLabel(order: number, text: string)
		local label = KitLook.text(scroll, text, 12, Enum.FontWeight.Bold, COLOR.sub, order)
		label.Position = UDim2.fromOffset(4, 0)
	end

	-- Hero: live status + CTA (Tiles) ------------------------------
	local heroCap: TextLabel
	local heroMm: TextLabel
	local heroSs: TextLabel
	local heroPlayers: TextLabel
	local heroCtaLabel: TextLabel
	local heroCtaFill: Frame
	local heroCtaGrad: UIGradient
	do
		sectionLabel(1, "DRAW")
		local hero = KitLook.box(scroll, "Hero", UDim2.new(1, 0, 0, HERO_H), 2, COLOR.white)
		KitLook.corner(hero, UDim.new(0, ROW_RADIUS))
		local heroShade = Instance.new("UIGradient")
		heroShade.Color = ColorSequence.new(Color3.fromHex("1d1d1d"), Color3.fromHex("0a0a0a"))
		heroShade.Rotation = 90
		heroShade.Parent = hero

		local f = KitLook.box(hero, "Tiled", UDim2.fromScale(1, 1), 0, nil)
		heroCap = KitLook.text(f, "", 13, Enum.FontWeight.SemiBold, COLOR.sub, 0, { align = Enum.TextXAlignment.Center })
		heroCap.AutomaticSize = Enum.AutomaticSize.None
		heroCap.Size = UDim2.new(1, 0, 0, 16)
		heroCap.Position = UDim2.fromOffset(0, 12)
		local tilesRow = KitLook.box(f, "Tiles", UDim2.fromOffset(150, 46), 0, nil)
		tilesRow.AnchorPoint = Vector2.new(0.5, 0)
		tilesRow.Position = UDim2.new(0.5, 0, 0, 32)
		local function tile(x: number): TextLabel
			local t = KitLook.box(tilesRow, "Tile", UDim2.fromOffset(62, 46), 0, COLOR.white, 0.94)
			t.Position = UDim2.fromOffset(x, 0)
			KitLook.corner(t, UDim.new(0, 10))
			local l = KitLook.text(t, "", 30, Enum.FontWeight.Bold, COLOR.white, 0, { align = Enum.TextXAlignment.Center })
			l.AutomaticSize = Enum.AutomaticSize.None
			l.Size = UDim2.fromScale(1, 1)
			local seam = KitLook.box(t, "Seam", UDim2.new(1, 0, 0, 1), 0, COLOR.black, 0.6)
			seam.Position = UDim2.fromScale(0, 0.5)
			return l
		end
		heroMm = tile(0)
		heroSs = tile(88)
		local colon = KitLook.text(tilesRow, ":", 26, Enum.FontWeight.Bold, COLOR.sub, 0, { align = Enum.TextXAlignment.Center })
		colon.AutomaticSize = Enum.AutomaticSize.None
		colon.Size = UDim2.fromOffset(26, 46)
		colon.Position = UDim2.fromOffset(62, 0)
		heroPlayers = KitLook.text(f, "", 13, Enum.FontWeight.SemiBold, COLOR.white, 0, { rich = true, align = Enum.TextXAlignment.Center })
		heroPlayers.AutomaticSize = Enum.AutomaticSize.None
		heroPlayers.Size = UDim2.new(1, 0, 0, 18)
		heroPlayers.Position = UDim2.fromOffset(0, 84)
		local cta, l, fill, g = ctaPill(f, UDim2.new(1, -28, 0, 34), "Spin now", false, function()
			if not isBusy() then
				adminEvent:FireServer("spin")
			end
		end)
		cta.Position = UDim2.fromOffset(14, 110)
		heroCtaLabel, heroCtaFill, heroCtaGrad = l, fill, g
		local reset = secondary(f, UDim2.new(1, -28, 0, 24), "Reset timer", function()
			adminEvent:FireServer("resetTimer")
		end)
		reset.BackgroundTransparency = 1
		reset.TextColor3 = COLOR.sub
		reset.Position = UDim2.fromOffset(14, 148)
	end

	local function refreshHero()
		local now = workspace:GetServerTimeNow()
		local live = isBusy()
		if live then
			heroCap.Text = "Giveaway is live"
		elseif state.phase == "waiting" then
			heroCap.Text = "Starts when the server is full"
		else
			heroCap.Text = "Next giveaway in"
		end
		local timed = not live and state.phase ~= "waiting"
		local remaining = math.max(0, math.ceil(state.nextAt - now))
		heroMm.Text = if timed then string.format("%02d", math.floor(remaining / 60)) else "–"
		heroSs.Text = if timed then string.format("%02d", remaining % 60) else "–"
		heroPlayers.Text = playersRich(state.count, state.min)
		paintCta(heroCtaLabel, heroCtaFill, heroCtaGrad, live, "Spin now")
	end

	-- Card position: 3 screen illustrations ------------------------
	local posTiles: { [string]: { stroke: UIStroke, caption: TextLabel, card: Frame, screen: Frame, col: GuiObject } } = {}
	local posGrid: Frame
	local function placeMini(anchor: string)
		for a, t in pairs(posTiles) do
			local on = a == anchor
			t.stroke.Transparency = if on then 0.15 else 0.9
			t.stroke.Thickness = if on then 1.5 else 1
			t.caption.TextColor3 = if on then COLOR.white else COLOR.sub
			t.card.BackgroundTransparency = if on then 0 else 0.55
		end
	end

	do
		sectionLabel(7, "CARD POSITION")
		local posList = makeList(scroll, 8)
		-- No row wrapper: a 3-column grid of screen illustrations, each showing the card in its own
		-- spot, caption underneath. Selected = white outline + bright caption; others dimmed.
		posGrid = KitLook.box(posList, "Grid", UDim2.new(1, 0, 0, TILE_H + 24), 1, nil)
		for i, anchor in ipairs(ANCHOR_OPTIONS) do
			local col = bareButton(posGrid, anchor, UDim2.new(1 / 3, -GRID_GAP * 2 / 3, 1, 0), i)
			col.Position = UDim2.new((i - 1) / 3, (i - 1) * GRID_GAP / 3, 0, 0)
			local screen = KitLook.box(col, "Screen", UDim2.new(1, 0, 0, TILE_H), 0, COLOR.white)
			KitLook.corner(screen, UDim.new(0, 10))
			local fillGrad = Instance.new("UIGradient")
			fillGrad.Rotation = 90
			fillGrad.Color = ColorSequence.new(Color3.fromHex("1c1c1c"), Color3.fromHex("0c0c0c"))
			fillGrad.Parent = screen
			local outline = stroke(screen, COLOR.white, 1)
			outline.Transparency = 0.9
			-- dim topbar strip
			for j, spec in ipairs({ { 6, 7 }, { 15, 10 }, { -6 - 10, 10 } }) do
				local chip = KitLook.box(screen, "Topbar" .. j, UDim2.fromOffset(spec[2], 3), 0, COLOR.white, 0.86)
				chip.Position = if spec[1] < 0 then UDim2.new(1, spec[1], 0, 6) else UDim2.fromOffset(spec[1], 6)
				KitLook.corner(chip, UDim.new(1, 0))
			end
			-- the card in this tile's spot
			local miniCard = KitLook.box(screen, "Card", UDim2.fromOffset(24, 15), 0, COLOR.white, 0.55)
			miniCard.AnchorPoint = Vector2.new((i - 1) / 2, 0)
			miniCard.Position = UDim2.new((i - 1) / 2, if i == 1 then 6 elseif i == 3 then -6 else 0, 0, 14)
			KitLook.corner(miniCard, UDim.new(0, 4))
			local head = KitLook.box(miniCard, "Head", UDim2.new(1, 0, 0, 5), 0, COLOR.black, 0.7)
			KitLook.splitCorner(head, 4, 0)
			local caption = KitLook.text(col, ANCHOR_LABEL[anchor] or anchor, 12, Enum.FontWeight.SemiBold, COLOR.sub, 0, { align = Enum.TextXAlignment.Center })
			caption.AutomaticSize = Enum.AutomaticSize.None
			caption.Size = UDim2.new(1, 0, 0, 16)
			caption.Position = UDim2.fromOffset(0, TILE_H + 6)
			posTiles[anchor] = { stroke = outline, caption = caption, card = miniCard, screen = screen, col = col }
			col.MouseEnter:Connect(function()
				if anchor ~= state.anchor then
					outline.Transparency = 0.7
				end
			end)
			col.MouseLeave:Connect(function()
				if anchor ~= state.anchor then
					outline.Transparency = 0.9
				end
			end)
			col.Activated:Connect(function()
				adminEvent:FireServer("setConfig", { key = "Anchor", value = anchor })
			end)
		end

		-- Keep each illustration 4:3 whatever the panel width: height follows the column width.
		local function relayoutPosGrid()
			local any = posTiles[ANCHOR_OPTIONS[1]]
			local w = any and any.col.AbsoluteSize.X or 0
			if w <= 0 then
				return
			end
			local h = math.floor(w * 3 / 4 + 0.5) -- 4:3 reads taller than true 16:9
			for _, t in pairs(posTiles) do
				t.screen.Size = UDim2.new(1, 0, 0, h)
				t.caption.Position = UDim2.fromOffset(0, h + 6)
				t.card.Size = UDim2.fromOffset(math.floor(w * 0.3 + 0.5), math.floor(h * 0.3 + 0.5))
			end
			posGrid.Size = UDim2.new(1, 0, 0, h + 24)
		end
		posGrid:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayoutPosGrid)
		task.defer(relayoutPosGrid)
	end

	-- Settings: grouped rows ---------------------------------------
	local enabledTrack: TextButton
	local enabledKnob: Frame
	local prizeBox: TextBox
	local valueInterval: TextBox
	local valueMinPlayers: TextBox
	local valueSpin: TextBox
	local cinemaLabel: TextLabel
	local openPicker: (string, { { label: string, value: any } }, string, any) -> ()

	do
		sectionLabel(3, "SETTINGS")
		local setList = makeList(scroll, 4)

		do
			local row = listRow(setList, 1, ROW_H)
			rowTitle(row, "Enabled")
			local track = Instance.new("TextButton")
			track.Name = "Toggle"
			track.AutoButtonColor = false
			track.BorderSizePixel = 0
			track.Text = ""
			track.AnchorPoint = Vector2.new(1, 0.5)
			track.Position = UDim2.new(1, -EDGE_INSET, 0.5, 0)
			track.Size = UDim2.fromOffset(44, 24)
			track.BackgroundColor3 = COLOR.closeDisc
			KitLook.corner(track, UDim.new(1, 0))
			track.Parent = row
			local knob = KitLook.box(track, "Knob", UDim2.fromOffset(20, 20), 0, COLOR.white)
			knob.AnchorPoint = Vector2.new(0, 0.5)
			knob.Position = UDim2.new(0, 2, 0.5, 0)
			KitLook.corner(knob, UDim.new(1, 0))
			track.Activated:Connect(function()
				adminEvent:FireServer("setConfig", { key = "Enabled", value = not state.enabled })
			end)
			enabledTrack = track
			enabledKnob = knob
		end

		do
			local row = listRow(setList, 2, ROW_H)
			rowTitle(row, "Prize (R$)")
			local box = Instance.new("TextBox")
			box.Name = "PrizeInput"
			box.BorderSizePixel = 0
			box.ClearTextOnFocus = false
			box.Text = ""
			box.PlaceholderText = "50"
			box.PlaceholderColor3 = COLOR.sub
			box.TextColor3 = COLOR.white
			box.TextSize = 13
			box.FontFace = KitLook.font(Enum.FontWeight.SemiBold)
			box.TextXAlignment = Enum.TextXAlignment.Center
			box.BackgroundColor3 = COLOR.closeDisc
			box.BackgroundTransparency = 0
			box.AnchorPoint = Vector2.new(1, 0.5)
			box.Position = UDim2.new(1, -EDGE_INSET, 0.5, 0)
			box.Size = UDim2.fromOffset(STEP_W + 8, STEP_H)
			KitLook.corner(box, UDim.new(0, 8))
			box.Parent = row
			box.Focused:Connect(function()
				box.BackgroundColor3 = COLOR.white
				box.BackgroundTransparency = 0.92
			end)
			box.FocusLost:Connect(function()
				box.BackgroundColor3 = COLOR.closeDisc
				box.BackgroundTransparency = 0
				local digits = string.gsub(box.Text, "[^%d]", "")
				if digits ~= "" then
					adminEvent:FireServer("setConfig", { key = "PrizeText", value = digits })
				end
				box.Text = tostring(state.prize)
			end)
			prizeBox = box
		end

		do
			local row = listRow(setList, 3, ROW_H)
			rowTitle(row, "Interval")
			valueInterval = comboStepper(adminEvent, row, function()
				nudge(adminEvent, "IntervalSeconds", math.floor(state.interval / 60), -1, 15, 15, 360, 60)
			end, function()
				nudge(adminEvent, "IntervalSeconds", math.floor(state.interval / 60), 1, 15, 15, 360, 60)
			end, "Interval")
		end

		do
			local row = listRow(setList, 4, ROW_H)
			rowTitle(row, "Min players")
			valueMinPlayers = comboStepper(adminEvent, row, function()
				nudge(adminEvent, "MinPlayers", state.min, -1, 5, 5, 500, 1)
			end, function()
				nudge(adminEvent, "MinPlayers", state.min, 1, 5, 5, 500, 1)
			end, "MinPlayers")
		end

		do
			local row = listRow(setList, 5, ROW_H)
			rowTitle(row, "Spin duration")
			valueSpin = comboStepper(adminEvent, row, function()
				nudge(adminEvent, "SpinDuration", state.spinDuration, -1, 0.5, 3, 10, 1)
			end, function()
				nudge(adminEvent, "SpinDuration", state.spinDuration, 1, 0.5, 3, 10, 1)
			end, "SpinDuration")
		end

		do
			local row = listRow(setList, 7, ROW_H)
			rowTitle(row, "Winner cinematic")
			local btn, label = valueButton(row)
			cinemaLabel = label
			btn.Activated:Connect(function()
				local items = {}
				for _, v in ipairs(CINEMA_OPTIONS) do
					table.insert(items, { label = cinemaText(v), value = v })
				end
				openPicker("Winner cinematic", items, "WinFxVariant", state.winFxVariant)
			end)
		end
		GroupedRowCornerUtil.apply(setList, ROW_RADIUS)
	end

	-- Stacked sheet (pickers + history). Same chrome as the main sheet, slides in from the right.
	-- Declared before the settings pickers use it (see openPicker below).
	local clip = KitLook.box(sheet, "Clip", UDim2.fromScale(1, 1), 5, nil)
	clip.ClipsDescendants = true
	local stack = KitLook.box(clip, "Stack", UDim2.fromScale(1, 1), 0, nil)
	stack.Visible = false
	local function setMainVisible(on: boolean)
		for _, name in ipairs({ "Header", "Card" }) do
			local f = sheet:FindFirstChild(name)
			if f and f:IsA("GuiObject") then
				f.Visible = on
			end
		end
	end
	local stackTitle, stackBack, stackCard = chrome(stack, "", "‹", false)
	local stackBody = scrollBody(stackCard, "Body")
	OverlayScrollbar.attach(stackBody, stack, { side = "right", centerOn = stackBody })

	local stackOpen = false
	local stackBuild: (() -> ())? = nil

	local function clearStackBody()
		for _, c in ipairs(stackBody:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
	end

	local function hideStack()
		if not stackOpen then
			return
		end
		stackOpen = false
		setMainVisible(true)
		local tw = TweenService:Create(stack, SLIDE_CLOSE, { Position = UDim2.fromScale(1, 0) })
		tw.Completed:Connect(function()
			if not stackOpen then
				stack.Visible = false
			end
		end)
		tw:Play()
	end

	local function showStack(titleText: string, build: () -> ())
		stackTitle.Text = titleText
		stackBuild = build
		clearStackBody()
		local okBuild, buildErr = pcall(build)
		if not okBuild then
			warn("[Giveaway] stack build failed: " .. tostring(buildErr))
		end
		stackOpen = true
		setMainVisible(false)
		stack.Visible = true
		stack.Position = UDim2.fromScale(1, 0)
		TweenService:Create(stack, SLIDE_OPEN, { Position = UDim2.fromScale(0, 0) }):Play()
	end
	stackBack.Activated:Connect(hideStack)

	openPicker = function(titleText: string, options: { { label: string, value: any } }, key: string, current: any)
		showStack(titleText, function()
			local list = makeList(stackBody, 1)
			for i, opt in ipairs(options) do
				local selected = opt.value == current
				local row = listRow(list, i, ROW_H)
				local label = KitLook.text(row, opt.label, 14, if selected then Enum.FontWeight.Bold else Enum.FontWeight.SemiBold, COLOR.white, 0, { truncate = true })
				label.Position = UDim2.fromOffset(14, 0)
				label.Size = UDim2.new(1, -56, 1, 0)
				if selected then
					local tick = KitLook.text(row, "✓", 14, Enum.FontWeight.Bold, COLOR.white, 0)
					tick.AnchorPoint = Vector2.new(1, 0.5)
					tick.Position = UDim2.new(1, -EDGE_INSET, 0.5, 0)
				end
				local hit = bareButton(row, "Hit", UDim2.fromScale(1, 1), 0)
				hit.Activated:Connect(function()
					adminEvent:FireServer("setConfig", { key = key, value = opt.value })
					hideStack()
				end)
			end
			GroupedRowCornerUtil.apply(list, ROW_RADIUS)
		end)
	end

	-- History: the last 3 winners inline, then a "See all" footer row that opens the stacked list.
	local historyCache: { any } = {}
	local histList: Frame
	local histBtn: Frame
	local histTitle: TextLabel
	local histSub: TextLabel
	local manualPay: { [number]: boolean } = {} -- rows whose transfer prompt failed
	local payChips: { [number]: TextButton } = {}

	-- One entry = headshot 36, name (Bold 14) over one muted meta line, and a compact state chip:
	-- unpaid = "Pay N" (opens Roblox's Robux transfer prompt), paid = "✓ Paid" dimmed, a manual mark
	-- can be undone (a transfer can't). If the prompt can't open the row falls back to "Mark paid".
	local function historyRow(list: Frame, index: number, e: any, height: number?): Frame
		local paid = e.paid == true
		local row = listRow(list, index, height or HIST_ROW_H)
		local face = KitLook.headshot(row, e.userId, 36, 0)
		face.AnchorPoint = Vector2.new(0, 0.5)
		face.Position = UDim2.new(0, 12, 0.5, 0)
		if paid then
			face.ImageTransparency = 0.35
		end
		local textX = 12 + 36 + 10
		local textW = UDim2.new(1, -(textX + PAID_W + EDGE_INSET + 10), 0, 18)
		-- Line 1: display name. Line 2: time · @username — ordered so only the end of a long
		-- username is ever cut (admins still need the @ to find the winner).
		local nameLine = KitLook.text(row, tostring(e.displayName or e.name), 14, Enum.FontWeight.Bold, if paid then COLOR.sub else COLOR.white, 0, { truncate = true })
		nameLine.Position = UDim2.fromOffset(textX, 10)
		nameLine.Size = textW
		local when = os.date("%H:%M", tonumber(e.ts) or 0)
		local meta = string.format("%s · @%s", when, tostring(e.name))
		local metaLine = KitLook.text(row, meta, 13, Enum.FontWeight.SemiBold, COLOR.meta, 0, { truncate = true })
		metaLine.Position = UDim2.fromOffset(textX, 29)
		metaLine.Size = UDim2.new(1, -(textX + PAID_W + EDGE_INSET + 10), 0, 16)

		local owed = math.max(0, (tonumber(e.amount) or 0) - (tonumber(e.paidAmount) or 0))
		local manual = manualPay[e.id] == true
		local idle = if paid then "✓ Paid" elseif manual then "Mark paid" else "Pay " .. owed
		local chip = bareButton(row, "PaidChip", UDim2.fromOffset(PAID_W, 26), 0)
		chip.AnchorPoint = Vector2.new(1, 0.5)
		chip.Position = UDim2.new(1, -EDGE_INSET, 0.5, 0)
		chip.BackgroundColor3 = COLOR.white
		chip.BackgroundTransparency = if paid then 1 else 0
		KitLook.corner(chip, UDim.new(1, 0))
		chip.Text = idle
		chip.TextSize = 12
		chip.FontFace = KitLook.font(if paid then Enum.FontWeight.SemiBold else Enum.FontWeight.Bold)
		chip.TextColor3 = if paid then COLOR.sub else COLOR.black
		chip.TextXAlignment = if paid then Enum.TextXAlignment.Right else Enum.TextXAlignment.Center
		chip.TextTruncate = Enum.TextTruncate.AtEnd
		local undoable = paid and e.via ~= "transfer"
		chip.MouseEnter:Connect(function()
			if undoable then
				chip.Text = "Undo"
			elseif not paid then
				chip.BackgroundTransparency = 0.12
			end
		end)
		chip.MouseLeave:Connect(function()
			if chip.Text == "Undo" then
				chip.Text = idle
			end
			chip.BackgroundTransparency = if paid then 1 else 0
		end)
		payChips[e.id] = chip
		chip.Activated:Connect(function()
			if paid then
				if undoable then
					adminEvent:FireServer("markPaid", { id = e.id, paid = false })
				end
			elseif manual then
				adminEvent:FireServer("markPaid", { id = e.id, paid = true })
			else
				chip.Text = "Opening…"
				adminEvent:FireServer("pay", { id = e.id })
				task.delay(4, function()
					if chip.Parent and chip.Text == "Opening…" then
						chip.Text = idle
					end
				end)
			end
		end)
		return row
	end

	local function buildHistoryList()
		local list = makeList(stackBody, 1)
		if #historyCache == 0 then
			local row = listRow(list, 1, 56)
			local l = KitLook.text(row, "No giveaways yet", 14, Enum.FontWeight.SemiBold, COLOR.sub, 0)
			l.Position = UDim2.fromOffset(14, 18)
		else
			for i, e in ipairs(historyCache) do
				if type(e) == "table" then
					historyRow(list, i, e)
				end
			end
		end
		GroupedRowCornerUtil.apply(list, ROW_RADIUS)
	end

	local function openHistory()
		showStack("History · " .. tostring(#historyCache), buildHistoryList)
	end

	do
		sectionLabel(9, "HISTORY")
		histList = makeList(scroll, 10)
		histBtn = listRow(histList, 99, 44)
		histBtn.Name = "SeeAll"
		histTitle = KitLook.text(histBtn, "See all", 14, Enum.FontWeight.SemiBold, COLOR.white, 0)
		histTitle.AnchorPoint = Vector2.new(0, 0.5)
		histTitle.Position = UDim2.new(0, 14, 0.5, 0)
		histSub = KitLook.text(histBtn, "", 13, Enum.FontWeight.SemiBold, COLOR.meta, 0, { rich = true })
		histSub.AnchorPoint = Vector2.new(1, 0.5)
		histSub.Position = UDim2.new(1, -(EDGE_INSET + 18), 0.5, 0)
		histSub.TextXAlignment = Enum.TextXAlignment.Right
		local histChevron = KitLook.text(histBtn, "›", 18, Enum.FontWeight.Bold, COLOR.sub, 0)
		histChevron.AutomaticSize = Enum.AutomaticSize.None
		histChevron.AnchorPoint = Vector2.new(1, 0.5)
		histChevron.Position = UDim2.new(1, -EDGE_INSET, 0.5, 0)
		histChevron.Size = UDim2.fromOffset(14, 20)
		histChevron.TextXAlignment = Enum.TextXAlignment.Center
		bareButton(histBtn, "Hit", UDim2.fromScale(1, 1), 0).Activated:Connect(openHistory)
	end

	-- Rebuilds the preview rows from the server list (the full list too, when it is on screen).
	local function setHistory(list: any)
		historyCache = if type(list) == "table" then list else {}
		local n = #historyCache
		for _, c in ipairs(histList:GetChildren()) do
			if c:GetAttribute("Preview") then
				c:Destroy()
			end
		end
		local unpaid = 0
		for _, e in ipairs(historyCache) do
			if type(e) == "table" and e.paid ~= true then
				unpaid += 1
			end
		end
		if n == 0 then
			local row = listRow(histList, 1, 52)
			row:SetAttribute("Preview", true)
			local t = KitLook.text(row, "No winners yet", 14, Enum.FontWeight.SemiBold, COLOR.sub, 0)
			t.Position = UDim2.fromOffset(14, 9)
			local d = KitLook.text(row, "Draws will show up here", 13, Enum.FontWeight.SemiBold, COLOR.meta, 0)
			d.Position = UDim2.fromOffset(14, 28)
		else
			for i = 1, math.min(HIST_PREVIEW, n) do
				local e: any = historyCache[i]
				if type(e) == "table" then
					historyRow(histList, i, e):SetAttribute("Preview", true)
				end
			end
		end
		histBtn.Visible = n > HIST_PREVIEW or unpaid > 0 and n > 0
		histTitle.Text = if n > HIST_PREVIEW then string.format("See all %d", n) else "See all"
		histSub.Text = if unpaid > 0 then '<font color="#ffffff">' .. unpaid .. " unpaid</font>" else "All paid"
		GroupedRowCornerUtil.apply(histList, ROW_RADIUS)
		if stackOpen and stackBuild then
			clearStackBody()
			stackBuild()
			stackTitle.Text = "History · " .. tostring(n)
		end
	end

	-- Pay-prompt result for one row: show the text on its chip, then reset the chip.
	local function notice(n: any)
		if type(n) ~= "table" then
			return
		end
		local chip = payChips[n.id]
		if chip and chip.Parent then
			chip.Text = tostring(n.text)
		end
		task.delay(2.5, function()
			if n.fallback then
				manualPay[n.id] = true
			end
			setHistory(historyCache)
		end)
	end

	-- Sheet-wide refresh (state changes and every open). Also drives the settings values.
	local function refresh()
		enabledTrack.BackgroundColor3 = if state.enabled then COLOR.white else COLOR.closeDisc
		enabledKnob.BackgroundColor3 = if state.enabled then COLOR.black else COLOR.white
		enabledKnob.Position = if state.enabled then UDim2.new(0, 22, 0.5, 0) else UDim2.new(0, 2, 0.5, 0)
		placeMini(state.anchor)
		valueInterval.Text = unitText(tostring(math.floor(state.interval / 60)), "min")
		valueMinPlayers.Text = unitText(tostring(state.min))
		valueSpin.Text = unitText(string.format("%.1f", state.spinDuration), "s")
		cinemaLabel.Text = cinemaText(state.winFxVariant) .. CHEVRON
		if not prizeBox:IsFocused() then
			prizeBox.Text = tostring(state.prize)
		end
		pcall(refreshHero)
	end

	-- Hero copy ticks while the sheet is open (the countdown is local).
	task.spawn(function()
		while sheetGui.Parent ~= nil do
			if sheetGui.Enabled then
				pcall(refreshHero)
			end
			task.wait(0.25)
		end
	end)

	local function open()
		sheetOpen = true
		if sheetTween then
			sheetTween:Cancel()
		end
		sheetGui.Enabled = true
		clampSheetOffset()
		sheet.Position = UDim2.new(0.5, sheetOffset.X, 0.5, sheetBaseY + sheetOffset.Y + 40)
		sheetTween = TweenService:Create(sheet, SLIDE_OPEN, { Position = UDim2.new(0.5, sheetOffset.X, 0.5, sheetBaseY + sheetOffset.Y) })
		sheetTween:Play()
		refresh()
		adminEvent:FireServer("getHistory")
	end

	local function closeSheet()
		sheetOpen = false
		hideStack()
		if sheetTween then
			sheetTween:Cancel()
		end
		local tw = TweenService:Create(sheet, SLIDE_CLOSE, { Position = UDim2.new(0.5, sheetOffset.X, 0.5, sheetBaseY + sheetOffset.Y + 40) })
		sheetTween = tw
		tw.Completed:Connect(function(status)
			if not sheetOpen and status == Enum.PlaybackState.Completed then
				sheetGui.Enabled = false
			end
		end)
		tw:Play()
	end
	closeBtn.Activated:Connect(closeSheet)

	-- Drag the sheet by its Drag handles (clamped to the band between the inset and the bottom strip).
	do
		local dragInput: InputObject? = nil
		local dragStart = Vector2.zero
		local startOffset = Vector2.zero
		local clampOffset = clampVec
		local function hook(handle: GuiObject)
			handle.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				if sheetTween then
					sheetTween:Cancel()
				end
				dragInput = input
				dragStart = Vector2.new(input.Position.X, input.Position.Y)
				startOffset = sheetOffset
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End and dragInput == input then
						dragInput = nil
					end
				end)
			end)
		end
		for _, d in ipairs(sheet:GetDescendants()) do
			if d.Name == "Drag" and d:IsA("GuiObject") then
				hook(d)
			end
		end
		UserInputService.InputChanged:Connect(function(input)
			if not dragInput then
				return
			end
			local mouseMove = input.UserInputType == Enum.UserInputType.MouseMovement and dragInput.UserInputType == Enum.UserInputType.MouseButton1
			if not (mouseMove or input == dragInput) then
				return
			end
			local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
			sheetOffset = clampOffset(startOffset + delta)
			sheet.Position = UDim2.new(0.5, sheetOffset.X, 0.5, sheetBaseY + sheetOffset.Y)
		end)
	end

	return {
		open = open,
		refresh = refresh,
		setHistory = setHistory,
		notice = notice,
		destroy = function()
			sheetGui:Destroy()
		end,
	}
end

return GiveawaySheet
