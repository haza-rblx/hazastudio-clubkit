--!strict
-- Design tokens: black, white and one red (owner, 2026-10-22), Inter, two motion curves.
local Theme = {}

local FAMILY = "rbxassetid://12187365364" -- Inter

Theme.FAMILY = FAMILY
Theme.B = Font.new(FAMILY, Enum.FontWeight.Bold)
Theme.SB = Font.new(FAMILY, Enum.FontWeight.SemiBold)
-- secondary text is Medium: Regular at 11-12 px renders broken (owner, 2026-10-22)
Theme.R = Font.new(FAMILY, Enum.FontWeight.Medium)
Theme.BRAND = Font.new("rbxasset://fonts/families/BuilderExtended.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)

Theme.W = Color3.new(1, 1, 1)
Theme.BLACK = Color3.new(0, 0, 0)

Theme.C = {
	root = Color3.fromHex("060606"), -- the panel behind the tiles (the 2 px gutters)
	tile = Color3.fromHex("0b0b0b"), -- section tiles, header, deck surfaces
	flat = Color3.fromHex("1f1f1f"), -- ghost and danger buttons
	raised = Color3.fromHex("292929"),
	select = Color3.fromHex("161616"), -- selected row
	hover = Color3.fromHex("111111"), -- hovered row
	card2 = Color3.fromHex("353535"),
	field = Color3.fromHex("171717"),
	line = Color3.fromHex("141414"), -- dividers
	soft = Color3.fromHex("bdbdbd"),
	dim = Color3.fromHex("7f7f7f"),
	faint = Color3.fromHex("4a4a4a"),
	ink = Color3.fromHex("0a0a0a"), -- text on white
	red = Color3.fromRGB(228, 16, 36), -- live, alerts, the active tab
	redText = Color3.fromRGB(255, 84, 96), -- red as text on black
	ok = Color3.fromHex("2fd27a"), -- the Available dot
	groove = Color3.fromHex("222222"), -- fader grooves on the near-black surface
	key = Color3.fromHex("262626"), -- SYNC and transport keys
	ledOff = Color3.fromHex("2f2f2f"),
	lane = Color3.fromHex("141414"),
	wave = Color3.fromHex("101010"),
	menu = Color3.fromHex("2e2e2e"),
	menuEdge = Color3.fromHex("3e3e3e"),
	coverEmpty = Color3.fromHex("2a2a2a"),
	libCover = Color3.fromHex("1a1a1a"),
	countText = Color3.fromHex("6f6f6f"),
}

Theme.RED_COVER = Color3.fromRGB(228, 16, 36)

Theme.FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
Theme.SLIDE = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- the panel grid: 1250 wide, tiles 311 / 624 / 937 with 2 px gutters
Theme.PANEL_W = 1250
Theme.HEADER_H = 40
Theme.PAGE_H = 760 -- deck 425 + pads 70 + library 261 + two 2 px gaps
Theme.DECK_H = 425
Theme.PADS_H = 70
Theme.LIB_H = 261
Theme.PAGE_PAD = 16
Theme.PAGE_HEAD = 56

Theme.MUSIC_ICON = "rbxassetid://79906818545872"

return Theme
