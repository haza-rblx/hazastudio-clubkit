--!strict
-- Shared tokens + small builders for code-built UI that has to read as the owner's design system
-- (Preferences rows, check-in popup cards, Event tab category cards). Used by the 2026-10-07
-- redesigns (dance panel v3 polish, ACM polish, profile edit modal, notification island) so every
-- one of them picks the same font, colours, radii and shadow. Spec:
-- docs/plans/ui-experiments-dance-acm-2026-10-07.md.

local KitLook = {}

KitLook.FONT = "rbxassetid://12187365364" -- Inter

KitLook.COLOR = {
	white = Color3.new(1, 1, 1),
	black = Color3.new(0, 0, 0),
	panel = Color3.fromHex("070707"),
	-- check-in popup card
	header = Color3.fromHex("202020"),
	body = Color3.fromHex("040404"),
	closeDisc = Color3.fromHex("2c2c2c"),
	closeGlyph = Color3.fromHex("c8c8c8"),
	-- Preferences rows
	row = Color3.fromHex("121212"),
	-- text
	sub = Color3.fromHex("828282"),
	bodyText = Color3.fromHex("bebebe"),
	meta = Color3.fromHex("7c7c7c"),
	danger = Color3.fromHex("ff5a6a"),
}

KitLook.CLOSE_IMAGE = "rbxassetid://135390345456797"

function KitLook.font(weight: Enum.FontWeight): Font
	return Font.new(KitLook.FONT, weight)
end

function KitLook.corner(parent: Instance, radius: UDim): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
	return corner
end

-- Different top and bottom radii, the way the check-in popup splits its card: header 18 top /
-- 6 bottom, body 6 top / 18 bottom. Per-corner radii are newer than UICorner itself, so older
-- clients keep the uniform `top` radius.
function KitLook.splitCorner(parent: Instance, top: number, bottom: number): UICorner
	local corner = KitLook.corner(parent, UDim.new(0, top))
	pcall(function()
		local anyCorner = corner :: any
		anyCorner.TopLeftRadius = UDim.new(0, top)
		anyCorner.TopRightRadius = UDim.new(0, top)
		anyCorner.BottomLeftRadius = UDim.new(0, bottom)
		anyCorner.BottomRightRadius = UDim.new(0, bottom)
	end)
	return corner
end

function KitLook.padding(parent: Instance, left: number, top: number?, right: number?, bottom: number?): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, left)
	padding.PaddingTop = UDim.new(0, top or left)
	padding.PaddingRight = UDim.new(0, right or left)
	padding.PaddingBottom = UDim.new(0, bottom or top or left)
	padding.Parent = parent
	return padding
end

function KitLook.list(
	parent: Instance,
	direction: Enum.FillDirection,
	gap: number,
	horizontal: Enum.HorizontalAlignment?,
	vertical: Enum.VerticalAlignment?
): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.Padding = UDim.new(0, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	if horizontal then
		layout.HorizontalAlignment = horizontal
	end
	if vertical then
		layout.VerticalAlignment = vertical
	end
	layout.Parent = parent
	return layout
end

-- A Frame; transparent unless a background colour is given.
function KitLook.box(parent: Instance?, name: string, size: UDim2, order: number?, background: Color3?, transparency: number?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.LayoutOrder = order or 0
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = background or KitLook.COLOR.black
	frame.BackgroundTransparency = transparency or (if background then 0 else 1)
	frame.Parent = parent
	return frame
end

export type TextOptions = { wrap: boolean?, truncate: boolean?, rich: boolean?, align: Enum.TextXAlignment? }

function KitLook.text(
	parent: Instance?,
	content: string,
	size: number,
	weight: Enum.FontWeight,
	color: Color3,
	order: number?,
	options: TextOptions?
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Text = content
	label.TextSize = size
	label.FontFace = KitLook.font(weight)
	label.TextColor3 = color
	label.TextXAlignment = if options and options.align then options.align else Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.RichText = options ~= nil and options.rich == true
	label.LayoutOrder = order or 0
	if options and options.truncate then
		label.Size = UDim2.new(1, 0, 0, size + 3)
		label.TextTruncate = Enum.TextTruncate.AtEnd
	elseif options and options.wrap then
		label.TextWrapped = true
		label.Size = UDim2.new(1, 0, 0, 0)
		label.AutomaticSize = Enum.AutomaticSize.Y
	else
		label.Size = UDim2.new()
		label.AutomaticSize = Enum.AutomaticSize.XY
	end
	label.Parent = parent
	return label
end

-- Pushes the items after it to the end of a horizontal UIListLayout.
function KitLook.spacer(parent: Instance, order: number): Frame
	local spacer = KitLook.box(parent, "Fill", UDim2.new(0, 0, 0, 1), order)
	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = spacer
	return spacer
end

-- The kit's soft card shadow (dance panel SoftShadow). UIShadow is a newer engine class: the
-- pcall keeps older clients from erroring, they just render without a shadow.
function KitLook.shadow(parent: Instance)
	pcall(function()
		local shadow = Instance.new("UIShadow" :: any) :: any
		shadow.Name = "SoftShadow"
		shadow.Color = Color3.new(0, 0, 0)
		shadow.Transparency = 0.82
		shadow.Offset = UDim2.fromOffset(0, 8)
		shadow.BlurRadius = UDim.new(0, 28)
		shadow.ZIndex = -1
		shadow.Parent = parent
	end)
end

-- Round player headshot.
function KitLook.headshot(parent: Instance, userId: number?, size: number, order: number?): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = "Headshot"
	image.BackgroundColor3 = Color3.fromHex("1a1a1a")
	image.BorderSizePixel = 0
	image.ScaleType = Enum.ScaleType.Crop
	image.Size = UDim2.fromOffset(size, size)
	image.LayoutOrder = order or 0
	if type(userId) == "number" and userId > 0 then
		image.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
	end
	KitLook.corner(image, UDim.new(1, 0))
	image.Parent = parent
	return image
end

-- Pill-shaped choice button in the Preferences MultiOption look: solid white + black text when
-- primary, white @0.95 + white text otherwise.
function KitLook.choiceButton(parent: Instance, label: string, order: number, primary: boolean): TextButton
	local button = Instance.new("TextButton")
	button.Name = label
	button.LayoutOrder = order
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Size = UDim2.new(0, 0, 1, 0)
	button.BackgroundColor3 = KitLook.COLOR.white
	button.BackgroundTransparency = if primary then 0 else 0.95
	button.Text = label
	button.TextSize = 14
	button.FontFace = KitLook.font(Enum.FontWeight.Bold)
	button.TextColor3 = if primary then KitLook.COLOR.black else KitLook.COLOR.white
	KitLook.corner(button, UDim.new(1, 0))
	button.Parent = parent
	return button
end

-- "Rio, Kai and Mia" style lists for rich text: names bold, glue muted.
function KitLook.richNames(names: { string }, maxNamed: number): string
	local muted = '<font color="#828282">%s</font>'
	local count = #names
	if count == 0 then
		return ""
	end
	if count == 1 then
		return "<b>" .. names[1] .. "</b>"
	end
	if count == 2 then
		return "<b>" .. names[1] .. "</b> " .. string.format(muted, "and") .. " <b>" .. names[2] .. "</b>"
	end
	if count == 3 and maxNamed >= 3 then
		return "<b>" .. names[1] .. ", " .. names[2] .. "</b> " .. string.format(muted, "and") .. " <b>" .. names[3] .. "</b>"
	end
	return "<b>" .. names[1] .. ", " .. names[2] .. "</b> " .. string.format(muted, string.format("and %d others", count - 2))
end

function KitLook.clock(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", math.floor(whole / 60), whole % 60)
end

return KitLook
