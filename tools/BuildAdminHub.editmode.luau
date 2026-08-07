--!nocheck
-- ============================================================
-- BUILD 04-AdminHub — HTML prototype → Studio ScreenGui
-- ============================================================
-- Edit Mode Command Bar / MCP execute_luau.
--
-- USAGE:
-- 1. Paste the ENTIRE file into the Command Bar (Edit) → Enter
--    OR run via Studio MCP execute_luau.
-- 2. Result: StarterGui["04-AdminHub"] (replaces existing if present).
-- 3. All ImageLabel.Image = "" — fill in your own rbxassetid later.
--    Do not put emoji / odd glyphs in icon slots.
--
-- Sumber: tools/prototypes/admin-hub-v1.html (:root tokens + data-name tree)
-- ============================================================

local StarterGui = game:GetService("StarterGui")

local GUI_NAME = "04-AdminHub"
local REPLACE_EXISTING = true
-- Inter (same as Config.TopbarMenu.FONT_ASSET_ID)
local FONT_ASSET = "rbxassetid://12187365364"

local function face(weight: Enum.FontWeight, style: Enum.FontStyle?): Font
	return Font.new(FONT_ASSET, weight, style or Enum.FontStyle.Normal)
end

-- —— Tokens (baked from HTML :root admin-hub-v1.html) ——
local T = {
	text = Color3.fromRGB(255, 255, 255),
	ink = Color3.fromRGB(10, 10, 10),
	muted = Color3.fromRGB(160, 160, 160),
	faint = Color3.fromRGB(92, 92, 92),
	iconFaint = Color3.fromRGB(102, 102, 102),
	panel = Color3.fromRGB(12, 12, 12), -- hub chrome
	surface = Color3.fromRGB(20, 20, 20), -- popup/sheet --surface #141414
	surfaceRaised = Color3.fromRGB(26, 26, 26),
	accent = Color3.fromRGB(10, 132, 255),
	danger = Color3.fromRGB(255, 59, 48),
	cta = Color3.fromRGB(255, 255, 255),
	fill = Color3.fromRGB(255, 255, 255), -- used with transparency
	gBlue = Color3.fromRGB(59, 130, 246),
	gViolet = Color3.fromRGB(124, 58, 237),
	gPink = Color3.fromRGB(219, 39, 119),
	gRose = Color3.fromRGB(225, 29, 72),
	gAmber = Color3.fromRGB(217, 119, 6),
	gCyan = Color3.fromRGB(8, 145, 178),

	s0 = 2,
	s1 = 4,
	micro = 6,
	s2 = 10,
	s3 = 14,
	s4 = 18,
	s5 = 24,
	titleSubGap = 3,
	pad = 24,
	stack = 18,

	rSm = 10,
	rMd = 14,
	rLg = 18,

	fsXs = 11,
	fsSm = 12,
	fsMd = 14,
	fsLg = 16,
	fsXl = 18,
	fsHero = 20,

	ctrl = 40,
	btn = 36,
	ico = 42,
	av = 40,
	gear = 30,
	sideW = 184,
	hubW = 780,
	hubH = 680,
	popupW = 360,
	popupH = 480,
	sheetW = 440,
	sheetH = 560,
	searchW = 148,
	gridCols = 3,
	scrollSize = 5,
	tileH = 108,
	sideBtnH = 40,
}

local FILL_T = 0.96 -- BackgroundTransparency for fill ~ rgba(255,255,255,0.04)
local FILL_STRONG_T = 0.94
local FILL_SIDEBAR_T = 1 -- sidebar chrome fully transparent
local LINE_T = 0.94
local PANEL_T = 0 -- solid panel
local DIM_T = 0.45

local function corner(parent: Instance, radius: number | UDim)
	local c = Instance.new("UICorner")
	if typeof(radius) == "UDim" then
		c.CornerRadius = radius :: UDim
	else
		c.CornerRadius = UDim.new(0, radius :: number)
	end
	c.Parent = parent
	return c
end

local function fadeHeaderGradient(parent: Instance)
	local g = Instance.new("UIGradient")
	g.Name = "UIGradient"
	g.Rotation = 90
	g.Color = ColorSequence.new(T.panel, T.panel)
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = parent
	return g
end

local function stroke(parent: Instance, color: Color3, transparency: number, thickness: number?)
	-- Kept for optional use; chrome frames are stroke-less after MainWrapper polish.
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Transparency = transparency
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function padding(parent: Instance, t: number, r: number, b: number, l: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, t)
	p.PaddingRight = UDim.new(0, r)
	p.PaddingBottom = UDim.new(0, b)
	p.PaddingLeft = UDim.new(0, l)
	p.Parent = parent
	return p
end

local function list(parent: Instance, dir: Enum.FillDirection, pad: number, horizontalAlign: Enum.HorizontalAlignment?)
	local l = Instance.new("UIListLayout")
	l.FillDirection = dir
	l.Padding = UDim.new(0, pad)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.HorizontalAlignment = horizontalAlign or Enum.HorizontalAlignment.Left
	l.VerticalAlignment = Enum.VerticalAlignment.Top
	l.Parent = parent
	return l
end

local function grid(parent: Instance, cellX: number, cellY: number, pad: number, maxCells: number)
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.fromOffset(cellX, cellY)
	g.CellPadding = UDim2.fromOffset(pad, pad)
	g.FillDirectionMaxCells = maxCells
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.HorizontalAlignment = Enum.HorizontalAlignment.Left
	g.Parent = parent
	return g
end

-- Empty image slot — user fills rbxassetid later. Never put emoji here.
local function emptyImage(parent: Instance, name: string, size: UDim2, props: { [string]: any }?)
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.Image = "" -- PLACEHOLDER — set rbxassetid://… manually
	img.ScaleType = Enum.ScaleType.Fit
	img.Size = size
	img.BorderSizePixel = 0
	img:SetAttribute("ImageAssetPending", true)
	if props then
		for k, v in pairs(props) do
			(img :: any)[k] = v
		end
	end
	img.Parent = parent
	return img
end

local function label(parent: Instance, name: string, text: string, sizePx: number, weight: Enum.FontWeight, color: Color3, props: { [string]: any }?)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.Text = text
	t.TextColor3 = color
	t.TextSize = sizePx
	t.FontFace = face(weight)
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.Size = UDim2.fromScale(1, 0)
	t.AutomaticSize = Enum.AutomaticSize.Y
	if props then
		for k, v in pairs(props) do
			(t :: any)[k] = v
		end
	end
	t.Parent = parent
	return t
end

local function frame(parent: Instance, name: string, props: { [string]: any }?)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = T.surface
	f.BackgroundTransparency = 1
	if props then
		for k, v in pairs(props) do
			(f :: any)[k] = v
		end
	end
	f.Parent = parent
	return f
end

local function textButton(parent: Instance, name: string, props: { [string]: any }?)
	local b = Instance.new("TextButton")
	b.Name = name
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Text = ""
	b.TextSize = T.fsMd
	b.FontFace = face(Enum.FontWeight.SemiBold)
	b.TextColor3 = T.text
	b.BackgroundColor3 = T.fill
	b.BackgroundTransparency = FILL_T
	if props then
		for k, v in pairs(props) do
			(b :: any)[k] = v
		end
	end
	b.Parent = parent
	return b
end

-- —— Actions (static gallery tiles for shell preview) ——
local ACTIONS = {
	{ id = "bring", group = "utilities", title = "Bring here", desc = "Pull them to you", g = T.gBlue },
	{ id = "to", group = "utilities", title = "Go to", desc = "Teleport to them", g = T.gViolet },
	{ id = "announce", group = "utilities", title = "Announce", desc = "Server broadcast", g = T.gAmber },
	{ id = "ungravity", group = "utilities", title = "Ungravity", desc = "Float everyone", g = T.gCyan, gear = true },
	{ id = "gravity", group = "utilities", title = "Gravity", desc = "Restore everyone", g = T.gBlue, gear = true },
	{ id = "role", group = "access", title = "Set role", desc = "Leadership · Mod · Content", g = T.gAmber },
	{ id = "gift", group = "access", title = "Gift membership", desc = "VIP · VVIP · Supreme", g = T.gPink },
	{ id = "title", group = "identity", title = "Custom title", desc = "Special overhead title", g = T.gViolet },
	{ id = "donate", group = "donations", title = "Donations", desc = "Fake donations, credit, or edit score", g = T.gRose },
	{ id = "refresh", group = "donations", title = "Reload boards", desc = "Refresh cash & Robux boards", g = T.gCyan },
}

local GROUPS = {
	{ id = "utilities", label = "Utilities" },
	{ id = "access", label = "Access" },
	{ id = "identity", label = "Identity" },
	{ id = "donations", label = "Donations" },
}

local SIDE_BTNS = {
	{ name = "SideBtn_Gallery", label = "Gallery", filter = "all", current = true },
	{ name = "SideBtn_Utilities", label = "Utilities", filter = "utilities" },
	{ name = "SideBtn_Access", label = "Access", filter = "access" },
	{ name = "SideBtn_Identity", label = "Identity", filter = "identity" },
	{ name = "SideBtn_Donations", label = "Donations", filter = "donations" },
}

-- —— Build ——
if REPLACE_EXISTING then
	local old = StarterGui:FindFirstChild(GUI_NAME)
	if old then
		old:Destroy()
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 40
gui.Enabled = false -- AdminHubController enables on open
gui:SetAttribute("KitPrototype", "admin-hub-v1")
gui.Parent = StarterGui

-- MainWrapper
local main = frame(gui, "MainWrapper", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(T.hubW, T.hubH),
	BackgroundColor3 = T.panel,
	BackgroundTransparency = PANEL_T,
	ClipsDescendants = true,
	Visible = false, -- AdminHubUI:show() reveals
})
corner(main, T.rLg)

local scale = Instance.new("UIScale")
scale.Name = "UIScale"
scale.Scale = 1
scale.Parent = main

-- Sidebar
local side = frame(main, "01-SidebarWrapper", {
	Size = UDim2.new(0, T.sideW, 1, 0),
	BackgroundColor3 = T.fill,
	BackgroundTransparency = FILL_SIDEBAR_T,
	ClipsDescendants = true,
})
padding(side, T.pad, T.s2, T.pad, T.s2)
list(side, Enum.FillDirection.Vertical, T.s0)

local function sideLabel(name: string, text: string, order: number)
	local l = label(side, name, string.upper(text), T.fsXs, Enum.FontWeight.Bold, T.faint, {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 22),
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	return l
end

sideLabel("SideLabelBrowse", "Browse", 1)

local function makeSideBtn(def: any, order: number)
	local btn = textButton(side, def.name, {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, T.sideBtnH),
		BackgroundTransparency = if def.current then 0 else 1,
		BackgroundColor3 = if def.current then T.accent else T.fill,
	})
	corner(btn, UDim.new(1, 0)) -- fully rounded pill
	btn:SetAttribute("Filter", def.filter)
	local row = frame(btn, "Content", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	padding(row, 0, T.s3, 0, T.s3)
	list(row, Enum.FillDirection.Horizontal, T.s2, Enum.HorizontalAlignment.Left)
	local lay = row:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	lay.VerticalAlignment = Enum.VerticalAlignment.Center

	emptyImage(row, "Icon", UDim2.fromOffset(16, 16), {
		LayoutOrder = 1,
		ImageTransparency = 1, -- empty until asset id set
	})
	label(row, "Label", def.label, T.fsLg, Enum.FontWeight.SemiBold, T.text, {
		LayoutOrder = 2,
		Size = UDim2.new(1, -24, 1, 0),
		AutomaticSize = Enum.AutomaticSize.None,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	return btn
end

makeSideBtn(SIDE_BTNS[1], 2)
sideLabel("SideLabelCategories", "Categories", 3)
for i = 2, #SIDE_BTNS do
	makeSideBtn(SIDE_BTNS[i], 3 + i)
end

-- Main content
local content = frame(main, "02-MainContentWrapper", {
	Position = UDim2.fromOffset(T.sideW, 0),
	Size = UDim2.new(1, -T.sideW, 1, 0),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
})

-- Header (fade gradient over solid fill — matches live MainWrapper polish)
local header = frame(content, "01-HeaderWrapper", {
	Size = UDim2.new(1, 0, 0, 50),
	BackgroundColor3 = T.fill,
	BackgroundTransparency = 0,
	ZIndex = 99,
})
corner(header, T.rLg)
fadeHeaderGradient(header)
padding(header, T.pad, T.pad, 0, T.pad)
list(header, Enum.FillDirection.Horizontal, T.s2)
do
	local lay = header:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
end

label(header, "1-HeaderTitle", "Admin Panel", T.fsHero, Enum.FontWeight.Bold, T.text, {
	LayoutOrder = 1,
	Size = UDim2.new(1, -(T.searchW + T.btn + T.s2 * 2), 1, 0),
	AutomaticSize = Enum.AutomaticSize.None,
	TextTruncate = Enum.TextTruncate.AtEnd,
})

local searchBox = frame(header, "02-SearchBox", {
	LayoutOrder = 2,
	Size = UDim2.fromOffset(T.searchW, T.ctrl),
	BackgroundColor3 = T.fill,
	BackgroundTransparency = FILL_STRONG_T,
})
corner(searchBox, 999)
padding(searchBox, 0, T.s3, 0, T.s3)
list(searchBox, Enum.FillDirection.Horizontal, T.s2)
do
	local lay = searchBox:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
end
emptyImage(searchBox, "Icon", UDim2.fromOffset(16, 16), { LayoutOrder = 1, ImageTransparency = 1 })
local searchInput = Instance.new("TextBox")
searchInput.Name = "Input"
searchInput.BackgroundTransparency = 1
searchInput.BorderSizePixel = 0
searchInput.ClearTextOnFocus = false
searchInput.PlaceholderText = "Search"
searchInput.PlaceholderColor3 = T.faint
searchInput.Text = ""
searchInput.TextColor3 = T.text
searchInput.TextSize = T.fsMd
searchInput.FontFace = face(Enum.FontWeight.Medium)
searchInput.TextXAlignment = Enum.TextXAlignment.Left
searchInput.Size = UDim2.new(1, -24, 1, 0)
searchInput.LayoutOrder = 2
searchInput.Parent = searchBox

local closeBtn = textButton(header, "3-CloseModalButton", {
	LayoutOrder = 3,
	Size = UDim2.fromOffset(T.btn, T.btn),
	BackgroundColor3 = T.danger,
	BackgroundTransparency = 0,
})
corner(closeBtn, 999)
emptyImage(closeBtn, "Icon", UDim2.fromOffset(16, 16), {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	ImageTransparency = 1,
})

-- Gallery scroll (top pad clears fade header)
local gallery = Instance.new("ScrollingFrame")
gallery.Name = "02-GalleryScroll"
gallery.BackgroundTransparency = 1
gallery.BorderSizePixel = 0
gallery.Position = UDim2.fromOffset(0, 0)
gallery.Size = UDim2.fromScale(1, 1)
gallery.ScrollBarThickness = T.scrollSize
gallery.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
gallery.ScrollBarImageTransparency = 0.82
gallery.CanvasSize = UDim2.new(0, 0, 0, 0)
gallery.AutomaticCanvasSize = Enum.AutomaticSize.Y
gallery.ScrollingDirection = Enum.ScrollingDirection.Y
gallery.Parent = content
padding(gallery, 56, T.pad, T.pad, T.pad)
list(gallery, Enum.FillDirection.Vertical, T.s5)

local function makeTile(parent: Instance, action: any, order: number)
	local tile = textButton(parent, "ActionTile_" .. action.id, {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, T.tileH),
		BackgroundColor3 = T.fill,
		BackgroundTransparency = FILL_T,
		ClipsDescendants = true,
	})
	corner(tile, T.rMd)
	tile:SetAttribute("ActionId", action.id)
	tile:SetAttribute("GroupId", action.group)

	local body = frame(tile, "Body", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	padding(body, T.s3, if action.gear then T.s3 + T.gear else T.s3, T.s3, T.s3)
	list(body, Enum.FillDirection.Vertical, T.s2)

	local ico = frame(body, "IconCircle", {
		LayoutOrder = 1,
		Size = UDim2.fromOffset(T.ico, T.ico),
		BackgroundColor3 = action.g,
		BackgroundTransparency = 0,
	})
	corner(ico, 999)
	emptyImage(ico, "Icon", UDim2.fromOffset(16, 16), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ImageTransparency = 1,
	})

	local info = frame(body, "TileInfo", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	})
	list(info, Enum.FillDirection.Vertical, T.titleSubGap)
	label(info, "1-Title", action.title, T.fsMd, Enum.FontWeight.Bold, T.text, {
		LayoutOrder = 1,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	label(info, "2-SubTitle", action.desc, T.fsSm, Enum.FontWeight.Medium, T.muted, {
		LayoutOrder = 2,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	if action.gear then
		local gear = textButton(tile, "GearButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -T.s2, 0, T.s2),
			Size = UDim2.fromOffset(T.gear + 8, T.gear),
			BackgroundColor3 = T.fill,
			BackgroundTransparency = 0.92,
			ZIndex = 2,
			Text = "3",
			TextSize = T.fsXs,
			TextColor3 = T.muted,
			FontFace = face(Enum.FontWeight.Bold),
		})
		corner(gear, 999)
		emptyImage(gear, "Icon", UDim2.fromOffset(12, 12), {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, 0),
			ImageTransparency = 1,
		})
	end
	return tile
end

-- Section builder: use flexible width tiles via UIListLayout rows of 3 using UIGridLayout with computed cell
local galleryInnerW = T.hubW - T.sideW - T.pad * 2
local cellGap = T.s2
local cellW = math.floor((galleryInnerW - cellGap * (T.gridCols - 1)) / T.gridCols)
local cellH = T.tileH

for gi, group in ipairs(GROUPS) do
	local section = frame(gallery, "Section_" .. group.id, {
		LayoutOrder = gi,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	})
	list(section, Enum.FillDirection.Vertical, T.s2)
	label(section, "1-SectionLabel", string.upper(group.label), T.fsXs, Enum.FontWeight.Bold, T.faint, {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 16),
		AutomaticSize = Enum.AutomaticSize.None,
	})
	local tileGrid = frame(section, "2-TileGrid", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	})
	grid(tileGrid, cellW, cellH, cellGap, T.gridCols)

	local order = 0
	for _, action in ipairs(ACTIONS) do
		if action.group == group.id then
			order += 1
			makeTile(tileGrid, action, order)
		end
	end
end

-- DimOverlay
local dim = frame(content, "DimOverlay", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = DIM_T,
	Visible = false,
	ZIndex = 4,
})

local function makeCenterPopup(parent: Instance, name: string, maxW: number, maxH: number, z: number)
	local p = frame(parent, name, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(maxW, maxH),
		BackgroundColor3 = T.surface,
		BackgroundTransparency = 0,
		Visible = false,
		ZIndex = z,
		ClipsDescendants = true,
	})
	corner(p, T.rLg)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "UIStroke"
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.92
	stroke.Thickness = 1
	stroke.Parent = p
	local sc = Instance.new("UIScale")
	sc.Name = "UIScale"
	sc.Scale = 1
	sc.Parent = p
	return p
end

-- 03-PlayerPopup
local playerPopup = makeCenterPopup(content, "03-PlayerPopup", T.popupW, T.popupH, 6)
local popupHead = frame(playerPopup, "01-Header", {
	Size = UDim2.new(1, 0, 0, T.btn + T.s3 + T.s2),
	BackgroundTransparency = 1,
	ZIndex = 7,
})
padding(popupHead, T.s3, T.pad, T.s2, T.pad)
list(popupHead, Enum.FillDirection.Horizontal, T.s2)
do
	local lay = popupHead:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
end
label(popupHead, "1-Title", "Find player", T.fsLg, Enum.FontWeight.ExtraBold, T.text, {
	LayoutOrder = 1,
	Size = UDim2.new(1, -T.btn - T.s2, 1, 0),
	AutomaticSize = Enum.AutomaticSize.None,
})
local popupClose = textButton(popupHead, "CloseModalButton", {
	LayoutOrder = 2,
	Size = UDim2.fromOffset(T.btn, T.btn),
	BackgroundColor3 = T.fill,
	BackgroundTransparency = FILL_STRONG_T,
	ZIndex = 8,
})
corner(popupClose, 999)
emptyImage(popupClose, "Icon", UDim2.fromOffset(16, 16), {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	ImageTransparency = 1,
})

local popupSearch = frame(playerPopup, "02-SearchBox", {
	Size = UDim2.new(1, -(T.pad * 2), 0, T.ctrl),
	Position = UDim2.fromOffset(T.pad, T.btn + T.s3 + T.s2),
	BackgroundColor3 = T.fill,
	BackgroundTransparency = FILL_STRONG_T,
	ZIndex = 6,
})
corner(popupSearch, T.rMd)
padding(popupSearch, 0, T.s3, 0, T.s3)
list(popupSearch, Enum.FillDirection.Horizontal, T.s2)
do
	local lay = popupSearch:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
end
emptyImage(popupSearch, "Icon", UDim2.fromOffset(16, 16), { LayoutOrder = 1, ImageTransparency = 1 })
local popupSearchInput = Instance.new("TextBox")
popupSearchInput.Name = "Input"
popupSearchInput.BackgroundTransparency = 1
popupSearchInput.BorderSizePixel = 0
popupSearchInput.PlaceholderText = "Name or username…"
popupSearchInput.PlaceholderColor3 = T.faint
popupSearchInput.Text = ""
popupSearchInput.TextColor3 = T.text
popupSearchInput.TextSize = T.fsMd
popupSearchInput.FontFace = face(Enum.FontWeight.Medium)
popupSearchInput.TextXAlignment = Enum.TextXAlignment.Left
popupSearchInput.Size = UDim2.new(1, -24, 1, 0)
popupSearchInput.LayoutOrder = 2
popupSearchInput.Parent = popupSearch

local playerList = Instance.new("ScrollingFrame")
playerList.Name = "ScrollablePlayerList"
playerList.BackgroundTransparency = 1
playerList.BorderSizePixel = 0
playerList.Position = UDim2.fromOffset(0, T.btn + T.s3 + T.s2 + T.ctrl + T.s2)
playerList.Size = UDim2.new(1, 0, 1, -(T.btn + T.s3 + T.s2 + T.ctrl + T.s2))
playerList.ScrollBarThickness = T.scrollSize
playerList.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
playerList.ScrollBarImageTransparency = 0.82
playerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
playerList.CanvasSize = UDim2.new(0, 0, 0, 0)
playerList.ZIndex = 6
playerList.Parent = playerPopup
padding(playerList, 0, T.s2, T.s3, T.s2)
list(playerList, Enum.FillDirection.Vertical, T.s1)

-- PlayerSelectorCard template (hidden)
local card = textButton(playerList, "PlayerSelectorCard", {
	Size = UDim2.new(1, 0, 0, T.av + T.s2 * 2),
	BackgroundTransparency = 1,
	Visible = false, -- template
	ZIndex = 6,
})
corner(card, T.rMd)
padding(card, T.s2, T.s3, T.s2, T.s3)
list(card, Enum.FillDirection.Horizontal, T.s3)
do
	local lay = card:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
end
emptyImage(card, "PlayerProfilePicture", UDim2.fromOffset(T.av, T.av), {
	LayoutOrder = 1,
	BackgroundColor3 = T.surfaceRaised,
	BackgroundTransparency = 0,
	ImageTransparency = 1,
})
corner(card:FindFirstChild("PlayerProfilePicture") :: ImageLabel, 999)
local pInfo = frame(card, "PlayerInformation", {
	LayoutOrder = 2,
	Size = UDim2.new(1, -(T.av + 80), 1, 0),
	BackgroundTransparency = 1,
})
list(pInfo, Enum.FillDirection.Vertical, T.s0)
label(pInfo, "1-Title", "DisplayName", T.fsMd, Enum.FontWeight.Bold, T.text, { LayoutOrder = 1 })
label(pInfo, "2-SubTitle", "@username", T.fsSm, Enum.FontWeight.Medium, T.muted, { LayoutOrder = 2 })
label(card, "RoleBadge", "Player", T.fsXs, Enum.FontWeight.SemiBold, T.faint, {
	LayoutOrder = 3,
	Size = UDim2.fromOffset(64, 24),
	AutomaticSize = Enum.AutomaticSize.None,
	TextXAlignment = Enum.TextXAlignment.Center,
	BackgroundColor3 = T.fill,
	BackgroundTransparency = FILL_STRONG_T,
})
corner(card:FindFirstChild("RoleBadge") :: TextLabel, 999)

-- 04-ActionPopup
local sheet = makeCenterPopup(content, "04-ActionPopup", T.sheetW, T.sheetH, 5)
local sheetHead = frame(sheet, "SheetHead", {
	Size = UDim2.new(1, 0, 0, T.btn + T.s3 + T.s2),
	BackgroundTransparency = 1,
	ZIndex = 6,
})
padding(sheetHead, T.s3, T.pad, T.s2, T.pad)
list(sheetHead, Enum.FillDirection.Horizontal, T.s2)
do
	local lay = sheetHead:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
end
local sheetIco = frame(sheetHead, "IconCircle", {
	LayoutOrder = 1,
	Size = UDim2.fromOffset(T.ico, T.ico),
	BackgroundColor3 = T.gRose,
	BackgroundTransparency = 0,
})
corner(sheetIco, 999)
emptyImage(sheetIco, "Icon", UDim2.fromOffset(16, 16), {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	ImageTransparency = 1,
})
label(sheetHead, "1-Title", "Action", T.fsLg, Enum.FontWeight.ExtraBold, T.text, {
	LayoutOrder = 2,
	Size = UDim2.new(1, -(T.ico + T.btn + T.s2 * 2), 1, 0),
	AutomaticSize = Enum.AutomaticSize.None,
})
local sheetClose = textButton(sheetHead, "CloseModalButton", {
	LayoutOrder = 3,
	Size = UDim2.fromOffset(T.btn, T.btn),
	BackgroundColor3 = T.fill,
	BackgroundTransparency = FILL_STRONG_T,
})
corner(sheetClose, 999)
emptyImage(sheetClose, "Icon", UDim2.fromOffset(16, 16), {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	ImageTransparency = 1,
})

local sheetFoot = frame(sheet, "SheetFoot", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.new(1, 0, 0, T.ctrl + T.s3 + T.pad),
	BackgroundColor3 = T.surface,
	BackgroundTransparency = 0,
	ZIndex = 6,
})
do
	local hair = Instance.new("Frame")
	hair.Name = "TopHairline"
	hair.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	hair.BackgroundTransparency = 0.94
	hair.BorderSizePixel = 0
	hair.Size = UDim2.new(1, 0, 0, 1)
	hair.Position = UDim2.fromOffset(0, 0)
	hair.ZIndex = 7
	hair.Parent = sheetFoot
end
padding(sheetFoot, T.s3, T.pad, T.pad, T.pad)
list(sheetFoot, Enum.FillDirection.Horizontal, T.s2)
local ghostCta = textButton(sheetFoot, "GhostButton", {
	LayoutOrder = 1,
	Size = UDim2.new(0.35, -T.s1, 1, 0),
	BackgroundColor3 = T.fill,
	BackgroundTransparency = FILL_STRONG_T,
	Text = "Secondary",
	TextColor3 = T.text,
	FontFace = face(Enum.FontWeight.SemiBold),
	Visible = false,
})
corner(ghostCta, 999)
local primaryCta = textButton(sheetFoot, "PrimaryButton", {
	LayoutOrder = 2,
	Size = UDim2.new(0.65, -T.s1, 1, 0),
	BackgroundColor3 = T.cta,
	BackgroundTransparency = 0,
	Text = "Primary",
	TextColor3 = T.ink,
	FontFace = face(Enum.FontWeight.Bold),
	Visible = false,
})
corner(primaryCta, 999)

local sheetBody = Instance.new("ScrollingFrame")
sheetBody.Name = "SheetBody"
sheetBody.BackgroundTransparency = 1
sheetBody.BorderSizePixel = 0
sheetBody.Position = UDim2.fromOffset(0, T.btn + T.s3 + T.s2)
sheetBody.Size = UDim2.new(1, 0, 1, -(T.btn + T.s3 + T.s2 + T.ctrl + T.s3 + T.pad))
sheetBody.ScrollBarThickness = T.scrollSize
sheetBody.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
sheetBody.ScrollBarImageTransparency = 0.82
sheetBody.AutomaticCanvasSize = Enum.AutomaticSize.Y
sheetBody.CanvasSize = UDim2.new(0, 0, 0, 0)
sheetBody.ZIndex = 5
sheetBody.Parent = sheet
padding(sheetBody, T.s1, T.pad, T.s4, T.pad)
list(sheetBody, Enum.FillDirection.Vertical, T.stack)

-- SelectedPlayerInfo template inside SheetBody (for action forms)
local target = textButton(sheetBody, "SelectedPlayerInfo", {
	Size = UDim2.new(1, 0, 0, T.av + T.s2 * 2),
	BackgroundColor3 = T.fill,
	BackgroundTransparency = FILL_STRONG_T,
	Visible = false,
	ZIndex = 5,
})
corner(target, T.rMd)
padding(target, T.s2, T.s3, T.s2, T.s3)
list(target, Enum.FillDirection.Horizontal, T.s3)
do
	local lay = target:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
end
emptyImage(target, "PlayerProfilePicture", UDim2.fromOffset(T.av, T.av), {
	LayoutOrder = 1,
	BackgroundColor3 = T.surfaceRaised,
	BackgroundTransparency = 0,
	ImageTransparency = 1,
})
corner(target:FindFirstChild("PlayerProfilePicture") :: ImageLabel, 999)
local tInfo = frame(target, "TargetInfoWrapper", {
	LayoutOrder = 2,
	Size = UDim2.new(1, -(T.av + 72), 1, 0),
	BackgroundTransparency = 1,
})
list(tInfo, Enum.FillDirection.Vertical, T.s0)
label(tInfo, "1-Title", "DisplayName", T.fsMd, Enum.FontWeight.Bold, T.text, { LayoutOrder = 1 })
label(tInfo, "2-SubTitle", "@username", T.fsSm, Enum.FontWeight.Medium, T.muted, { LayoutOrder = 2 })
label(target, "ChangeButton", "Change", T.fsSm, Enum.FontWeight.SemiBold, T.muted, {
	LayoutOrder = 3,
	Size = UDim2.fromOffset(52, 20),
	AutomaticSize = Enum.AutomaticSize.None,
	TextXAlignment = Enum.TextXAlignment.Right,
})

-- Toast
local toast = frame(content, "Toast", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -T.pad),
	Size = UDim2.fromOffset(240, 34),
	BackgroundColor3 = T.panel,
	BackgroundTransparency = 0,
	Visible = false,
	ZIndex = 8,
})
corner(toast, T.rMd)
label(toast, "Label", "Done", T.fsSm, Enum.FontWeight.SemiBold, T.text, {
	Size = UDim2.fromScale(1, 1),
	AutomaticSize = Enum.AutomaticSize.None,
	TextXAlignment = Enum.TextXAlignment.Center,
})

-- Count empty images for report
local pending = 0
for _, d in ipairs(gui:GetDescendants()) do
	if d:IsA("ImageLabel") and d:GetAttribute("ImageAssetPending") == true then
		pending += 1
	end
end

print(string.format(
	"[BuildAdminHub] Created StarterGui.%s | tiles=%d | empty ImageLabels=%d (fill rbxassetid later)",
	GUI_NAME,
	#ACTIONS,
	pending
))

return {
	gui = gui:GetFullName(),
	emptyImages = pending,
	actions = #ACTIONS,
}
