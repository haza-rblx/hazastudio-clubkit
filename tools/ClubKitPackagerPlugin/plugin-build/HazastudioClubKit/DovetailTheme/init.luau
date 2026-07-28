--!nocheck
-- Dovetail / HyperOS AMOLED tokens for Club Kit plugin UI (panel v2).

local DovetailTheme = {}

DovetailTheme.colors = {
	page = Color3.fromHex("#000000"),
	card = Color3.fromHex("#111111"),
	elevated = Color3.fromHex("#1a1a1a"),
	text = Color3.fromHex("#ffffff"),
	muted = Color3.fromHex("#a0a0a0"),
	faint = Color3.fromHex("#6e6e6e"),
	sep = Color3.fromHex("#ffffff"),
	blue = Color3.fromHex("#0a84ff"),
	blueBright = Color3.fromHex("#64b5ff"),
	blueDeep = Color3.fromHex("#0071e3"),
	blueSoft = Color3.fromHex("#0a84ff"),
	red = Color3.fromHex("#ff453a"),
	redSoft = Color3.fromHex("#ff453a"),
	-- Legacy aliases (older DovetailUI helpers)
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
	success = Color3.fromRGB(90, 190, 120),
	warning = Color3.fromRGB(230, 180, 70),
	error = Color3.fromRGB(230, 90, 90),
}

DovetailTheme.fonts = {
	body = Enum.Font.GothamMedium,
	bodyBold = Enum.Font.GothamBold,
	eyebrow = Enum.Font.Code,
	title = Enum.Font.GothamBold,
}

DovetailTheme.sizes = {
	eyebrow = 11,
	body = 13,
	title = 20,
	subtitle = 12,
	stat = 18,
	padding = 14,
	gap = 10,
	rowHeight = 28,
	buttonHeight = 44,
	pillButtonHeight = 44,
	corner = 16,
	pillCorner = 22,
	brandHeight = 72,
	changelogHeight = 130,
}

return DovetailTheme
