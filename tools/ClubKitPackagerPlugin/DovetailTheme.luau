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
	success = Color3.fromRGB(90, 190, 120),
	warning = Color3.fromRGB(230, 180, 70),
	error = Color3.fromRGB(230, 90, 90),
}

DovetailTheme.fonts = {
	body = Enum.Font.GothamMedium,
	bodyBold = Enum.Font.GothamBold,
	eyebrow = Enum.Font.Code,
}

DovetailTheme.sizes = {
	eyebrow = 11,
	body = 13,
	title = 15,
	stat = 20,
	padding = 12,
	gap = 8,
	rowHeight = 26,
	buttonHeight = 32,
	corner = 6,
}

return DovetailTheme
