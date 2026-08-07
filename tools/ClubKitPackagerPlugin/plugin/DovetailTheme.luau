--!nocheck
--[[
  Club Kit dock tokens — HyperOS AMOLED.

  Pure black page, charcoal surfaces, system blue (#0a84ff).
  Type: Inter Font.fromId(12187365364). Floor weight = Medium.

  PluginGui paint rules (this Studio):
    1. Sidebar TextButtons = DIRECT children of Sidebar, opaque fill.
    2. Never put a Y-scale=1 Edge Frame under the same UIListLayout as nav.
]]

local DovetailTheme = {}

DovetailTheme.INTER_ASSET_ID = 12187365364

local function inter(weight: Enum.FontWeight): Font
	return Font.fromId(DovetailTheme.INTER_ASSET_ID, weight, Enum.FontStyle.Normal)
end

-- HyperOS AMOLED
DovetailTheme.colors = {
	page = Color3.fromHex("#000000"),
	sidebar = Color3.fromHex("#111111"),
	card = Color3.fromHex("#111111"),
	elevated = Color3.fromHex("#1a1a1a"),
	hover = Color3.fromHex("#222222"),
	text = Color3.fromHex("#ffffff"),
	muted = Color3.fromHex("#a0a0a0"),
	faint = Color3.fromHex("#6e6e6e"),
	placeholder = Color3.fromHex("#4a4a4a"),
	sep = Color3.fromRGB(255, 255, 255),

	blue = Color3.fromHex("#0a84ff"),
	blueBright = Color3.fromHex("#64b5ff"),
	blueDeep = Color3.fromHex("#0071e3"),
	-- Alias: gradients that used "violet" stay in the blue family
	violet = Color3.fromHex("#0071e3"),

	red = Color3.fromHex("#ff453a"),
	success = Color3.fromRGB(90, 190, 120),
	warning = Color3.fromRGB(230, 180, 70),
	error = Color3.fromHex("#ff453a"),

	switchOff = Color3.fromHex("#36363b"),
	switchThumbOff = Color3.fromHex("#8e8e93"),
	scrollbar = Color3.fromHex("#2a2a2a"),
	navChild = Color3.fromHex("#111111"),
	-- Soft active: rgba(10,132,255,0.14) blended onto sidebar #111 (opaque for PluginGui)
	navActive = Color3.fromRGB(16, 33, 50),

	-- Legacy aliases
	carbon = Color3.fromHex("#0a0a0a"),
	graphite = Color3.fromHex("#141414"),
	iron = Color3.fromHex("#1e1e1e"),
	slateEdge = Color3.fromHex("#313131"),
	smoke = Color3.fromHex("#454545"),
	ash = Color3.fromHex("#a7a7a7"),
	bone = Color3.fromHex("#ffffff"),
	softIndigo = Color3.fromHex("#0a84ff"),
	indigoDeep = Color3.fromHex("#0071e3"),
	indigoGlow = Color3.fromHex("#64b5ff"),
}

DovetailTheme.fontFaces = {
	regular = inter(Enum.FontWeight.Medium),
	medium = inter(Enum.FontWeight.Medium),
	semiBold = inter(Enum.FontWeight.SemiBold),
	bold = inter(Enum.FontWeight.Bold),
	extraBold = inter(Enum.FontWeight.ExtraBold),
	mono = Font.fromEnum(Enum.Font.RobotoMono),
	monoBold = Font.fromEnum(Enum.Font.RobotoMono),
}

DovetailTheme.fonts = {
	regular = Enum.Font.Gotham,
	medium = Enum.Font.GothamMedium,
	semiBold = Enum.Font.GothamMedium,
	bold = Enum.Font.GothamBold,
	extraBold = Enum.Font.GothamBold,
	mono = Enum.Font.RobotoMono,
	body = Enum.Font.GothamMedium,
	bodyBold = Enum.Font.GothamBold,
	eyebrow = Enum.Font.RobotoMono,
	title = Enum.Font.GothamBold,
}

function DovetailTheme.face(weight: string?): Font
	local key = weight or "medium"
	if key == "regular" then
		key = "medium"
	end
	return DovetailTheme.fontFaces[key] or DovetailTheme.fontFaces.medium
end

DovetailTheme.sizes = {
	body = 16,
	bodySm = 14,
	title = 26,
	subtitle = 15,
	kicker = 12,
	secHead = 12,
	stat = 28,
	hint = 13,

	-- iOS 18–tight: denser inset lists, less air between cards
	contentPadX = 36,
	contentPadY = 28,
	gap = 8,
	sectionGap = 12,
	navGap = 2,
	navGroupGap = 12,
	navH = 38,
	navChildH = 34,
	navChildIndent = 24,
	buttonH = 40,
	buttonSmallH = 34,
	inputH = 40,

	corner = 4,
	cardCorner = 4,
	navCorner = 6,
	-- Buttons / chips / toggles stay fully rounded
	pill = 999,

	switchW = 48,
	switchH = 26,

	sidebarW = 240,
	brandH = 72,
	logo = 40,
}

DovetailTheme.sepTransparency = 0.92
DovetailTheme.edgeTransparency = 0.88

DovetailTheme.assets = {
	studioLogo = "rbxassetid://131546047206193",
}

return DovetailTheme
