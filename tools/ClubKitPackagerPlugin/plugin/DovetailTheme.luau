--!nocheck
-- Dovetail dark theme tokens for Club Kit plugin UI.

local DovetailTheme = {}

DovetailTheme.colors = {
	carbon = Color3.fromHex("#0a0a0a"),
	graphite = Color3.fromHex("#141414"),
	iron = Color3.fromHex("#1e1e1e"),
	slateEdge = Color3.fromHex("#313131"),
	smoke = Color3.fromHex("#454545"),
	ash = Color3.fromHex("#a7a7a7"),
	bone = Color3.fromHex("#ffffff"),
	softIndigo = Color3.fromHex("#6798ff"),
	indigoDeep = Color3.fromHex("#3d5f99"),
	indigoGlow = Color3.fromHex("#8eb4ff"),
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
	title = 18,
	subtitle = 12,
	stat = 18,
	padding = 14,
	gap = 10,
	rowHeight = 28,
	buttonHeight = 34,
	pillButtonHeight = 44,
	corner = 8,
	pillCorner = 22,
	brandHeight = 72,
	changelogHeight = 130,
}

return DovetailTheme
