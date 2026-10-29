--!strict
-- LuckyDraw: a plain, static ScreenGui with the round-2 IDLE look.
-- Built only from real instances: no runtime layout code, no Heartbeat, no tweens,
-- no BindableEvent. Edit the result in Studio; nothing here needs to run again.
--
--   local BuildStaticGui = require(path.to.BuildStaticGui)
--   BuildStaticGui.build(game.StarterGui)            -- to make the template
--   BuildStaticGui.build(player.PlayerGui)           -- to preview on the Client
--
-- Sample content: the local player (8842050215) and two friends (9522682462, 7201051025),
-- shown with rbxthumb headshot URLs. Change the text and ids freely in Studio.
--
-- Names a script can bind to later:
--   Root > Chrome > DragHandle, CloseWrapper > CloseButton
--   Root > Card > Header > Icon, Title
--   Root > Card > Content > Hero > AvatarStack > Avatar1..3, Heading, Meta
--   Root > Card > Content > ResultLabel, ReelWindow
--   Root > Card > Content > ReelWindow > Rows > RowTemplate, Row1, Row2
--   Root > Card > Content > ReelWindow > Band, MaskTop, MaskBottom, OddsChip > Label
--   Root > Card > Content > SpinButton > Label
--   Toast > Title, CloseWrapper > CloseButton, MiniReel > RowTemplate, Progress > Fill

local FONT_ID = "rbxassetid://12187365364"
local CLOSE_IMG = "rbxassetid://135390345456797"
local DRAG_IMG = "rbxassetid://91183535922560"

local BG = Color3.fromRGB(7, 7, 7)
local RIM = Color3.fromRGB(41, 41, 41)
local MUTED = Color3.fromRGB(143, 143, 143)
local WHITE = Color3.new(1, 1, 1)
local PURPLE_A = Color3.fromRGB(98, 20, 255)
local PURPLE_B = Color3.fromRGB(17, 0, 66)

local LOCAL_ID = 8842050215
local FRIEND_A = 7201051025
local FRIEND_B = 9522682462

local function font(weight: Enum.FontWeight): Font
	return Font.new(FONT_ID, weight)
end

local function headshot(userId: number): string
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
end

-- Create an instance with properties, then parent it last.
local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst: any = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(parent: Instance, radius: UDim?)
	make("UICorner", { CornerRadius = radius or UDim.new(1, 0) }, parent)
end

local function stroke(parent: Instance, thickness: number, color: Color3, inner: boolean?)
	make("UIStroke", {
		Thickness = thickness,
		Color = color,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		BorderStrokePosition = if inner then Enum.BorderStrokePosition.Inner else Enum.BorderStrokePosition.Outer,
	}, parent)
end

local function padding(parent: Instance, all: number)
	local u = UDim.new(0, all)
	make("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u }, parent)
end

local function closeButton(parent: Instance)
	local wrap = make("Frame", {
		Name = "CloseWrapper",
		BackgroundColor3 = Color3.fromRGB(52, 1, 1),
		BorderSizePixel = 0,
	}, parent)
	corner(wrap)
	stroke(wrap, 1, RIM)
	make("ImageButton", {
		Name = "CloseButton",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = CLOSE_IMG,
		ScaleType = Enum.ScaleType.Fit,
		AutoButtonColor = false,
	}, wrap)
	return wrap
end

-- One reel row: 40px headshot at (14, 8), name at x66 y9, handle at x66 y29.
local function sampleRow(parent: Instance, name: string, y: number, userId: number, display: string, handle: string)
	local r = make("Frame", {
		Name = name,
		Position = UDim2.new(0, 0, 0, y),
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 1,
	}, parent)
	local face = make("ImageLabel", {
		Name = "Face",
		Position = UDim2.new(0, 14, 0, 8),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Color3.fromRGB(26, 26, 26),
		BorderSizePixel = 0,
		Image = headshot(userId),
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = 1,
	}, r)
	corner(face)
	make("TextLabel", {
		Name = "DisplayName",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 66, 0, 9),
		Size = UDim2.new(1, -80, 0, 20),
		FontFace = font(Enum.FontWeight.Bold),
		Text = display,
		TextSize = 17,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 1,
	}, r)
	make("TextLabel", {
		Name = "Handle",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 66, 0, 29),
		Size = UDim2.new(1, -80, 0, 16),
		FontFace = font(Enum.FontWeight.Medium),
		Text = "@" .. handle,
		TextSize = 14,
		TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 1,
	}, r)
	return r
end

local function build(parent: Instance): ScreenGui
	local gui = make("ScreenGui", {
		Name = "LuckyDrawGui",
		ResetOnSpawn = false,
		DisplayOrder = 46,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	-- Root: content-sized column, 0.88 scale baked in as a UIScale instance.
	local root = make("Frame", {
		Name = "Root",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 24, 0.5, 0),
		Size = UDim2.new(0, 320, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, gui)
	make("UIScale", { Scale = 0.88 }, root)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, root)

	-- Chrome row above the card: drag disc centred, close disc at the right edge.
	local chrome = make("Frame", {
		Name = "Chrome",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = 1,
	}, root)
	local dragHandle = make("Frame", {
		Name = "DragHandle",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = BG,
		BorderSizePixel = 0,
		Active = true,
	}, chrome)
	corner(dragHandle)
	stroke(dragHandle, 1, RIM)
	make("ImageLabel", {
		Name = "DragIcon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(24, 24),
		BackgroundTransparency = 1,
		Image = DRAG_IMG,
	}, dragHandle)
	local close = closeButton(chrome)
	close.Position = UDim2.new(1, -38, 0, 2)
	close.Size = UDim2.fromOffset(36, 36)

	-- Card: content-sized, inner stroke, CT-style header on top.
	local card = make("Frame", {
		Name = "Card",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = BG,
		BorderSizePixel = 0,
		LayoutOrder = 2,
	}, root)
	corner(card, UDim.new(0, 32))
	stroke(card, 1, Color3.fromRGB(26, 26, 26), true)
	pcall(function()
		make("UIShadow", { Transparency = 0.6, BlurRadius = UDim.new(0, 20) }, card)
	end)

	local header = make("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 55),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		BackgroundColor3 = BG,
		BorderSizePixel = 0,
	}, card)
	corner(header, UDim.new(1, 0))
	stroke(header, 1, Color3.fromRGB(27, 27, 27), true)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 20),
		PaddingRight = UDim.new(0, 20),
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
	}, header)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 12),
	}, header)
	make("TextLabel", {
		Name = "Icon",
		Size = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 1,
		Text = "🎲",
		TextScaled = true,
		FontFace = font(Enum.FontWeight.Bold),
		TextColor3 = WHITE,
		LayoutOrder = 0,
	}, header)
	make("TextLabel", {
		Name = "Title",
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		Text = "Spin",
		TextSize = 18,
		FontFace = font(Enum.FontWeight.Bold),
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
	}, header)

	-- Content starts 50px down (measured from the CT card), 8px padding, 8px gaps.
	local content = make("Frame", {
		Name = "Content",
		Position = UDim2.new(0, 0, 0, 50),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, card)
	padding(content, 8)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, content)

	local hero = make("Frame", {
		Name = "Hero",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = 1,
	}, content)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, hero)

	local avatarStack = make("Frame", {
		Name = "AvatarStack",
		Size = UDim2.fromOffset(104, 44),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, hero)
	local avatarIds = { LOCAL_ID, FRIEND_B, FRIEND_A }
	for i, id in ipairs(avatarIds) do
		local av = make("ImageLabel", {
			Name = "Avatar" .. i,
			Position = UDim2.fromOffset((i - 1) * 30, 0),
			Size = UDim2.fromOffset(44, 44),
			BackgroundColor3 = Color3.fromRGB(26, 26, 26),
			BorderSizePixel = 0,
			Image = headshot(id),
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = i,
		}, avatarStack)
		corner(av)
		stroke(av, 3, BG)
	end
	make("TextLabel", {
		Name = "Heading",
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		Text = "Spin a Player",
		TextSize = 27,
		FontFace = font(Enum.FontWeight.Bold),
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
	}, hero)
	make("TextLabel", {
		Name = "Meta",
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = "12 players in the pool · 1 in 12",
		TextSize = 17,
		FontFace = font(Enum.FontWeight.Medium),
		TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 3,
	}, hero)

	make("TextLabel", {
		Name = "ResultLabel",
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Text = "Result :",
		TextSize = 18,
		FontFace = font(Enum.FontWeight.SemiBold),
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
	}, content)

	-- Reel window: 3 rows of 56 = 168. Band sits on Row1 (index 2, the centre row).
	local reel = make("Frame", {
		Name = "ReelWindow",
		Size = UDim2.new(1, 0, 0, 168),
		BackgroundColor3 = Color3.fromRGB(4, 4, 4),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = 3,
	}, content)
	corner(reel, UDim.new(0, 16))
	stroke(reel, 1, Color3.fromRGB(27, 27, 27), true)

	local rows = make("Frame", {
		Name = "Rows",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 1,
	}, reel)
	sampleRow(rows, "RowTemplate", 0, FRIEND_A, "Khaverish", "Khaverish")
	sampleRow(rows, "Row1", 56, LOCAL_ID, "haza", "hazatargz")
	sampleRow(rows, "Row2", 112, FRIEND_B, "jaehyunlummy", "jaehyunlummy")

	local band = make("Frame", {
		Name = "Band",
		Position = UDim2.new(0, 6, 0, 56),
		Size = UDim2.new(1, -12, 0, 56),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.94,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, reel)
	corner(band)
	stroke(band, 1, RIM, true)

	local maskTop = make("Frame", {
		Name = "MaskTop",
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Color3.fromRGB(4, 4, 4),
		BorderSizePixel = 0,
		ZIndex = 5,
	}, reel)
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0, 1) }, maskTop)
	local maskBottom = make("Frame", {
		Name = "MaskBottom",
		Position = UDim2.new(0, 0, 1, -40),
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Color3.fromRGB(4, 4, 4),
		BorderSizePixel = 0,
		ZIndex = 5,
	}, reel)
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0) }, maskBottom)

	local odds = make("Frame", {
		Name = "OddsChip",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = Color3.fromRGB(18, 18, 18),
		BorderSizePixel = 0,
		ZIndex = 12,
	}, reel)
	corner(odds)
	stroke(odds, 1, RIM)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
	}, odds)
	make("TextLabel", {
		Name = "Label",
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		Text = "1 in 12",
		TextSize = 13,
		FontFace = font(Enum.FontWeight.Bold),
		TextColor3 = WHITE,
		ZIndex = 12,
	}, odds)

	-- CTA: 46px, purple gradient, Bold 18.
	local spin = make("TextButton", {
		Name = "SpinButton",
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = 4,
	}, content)
	corner(spin)
	make("UIGradient", { Color = ColorSequence.new(PURPLE_A, PURPLE_B), Rotation = 90 }, spin)
	make("TextLabel", {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "Spin",
		TextSize = 18,
		FontFace = font(Enum.FontWeight.Bold),
		TextColor3 = WHITE,
		ZIndex = 2,
	}, spin)

	-- Toast: top-right, hidden until a spin. Same 0.88 scale as the panel.
	local toast = make("Frame", {
		Name = "Toast",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 24),
		Size = UDim2.fromOffset(300, 136),
		BackgroundColor3 = BG,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 20,
	}, gui)
	make("UIScale", { Scale = 0.88 }, toast)
	corner(toast, UDim.new(0, 24))
	stroke(toast, 1, Color3.fromRGB(26, 26, 26), true)
	make("TextLabel", {
		Name = "Title",
		Position = UDim2.new(0, 12, 0, 12),
		Size = UDim2.new(1, -60, 0, 28),
		BackgroundTransparency = 1,
		RichText = true,
		Text = '<font color="#ffffff">haza</font><font color="#bebebe"> is spinning!</font>',
		TextSize = 17,
		FontFace = font(Enum.FontWeight.Bold),
		TextColor3 = Color3.fromRGB(190, 190, 190),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, toast)
	local toastClose = closeButton(toast)
	toastClose.Position = UDim2.new(1, -40, 0, 12)
	toastClose.Size = UDim2.fromOffset(28, 28)

	local mini = make("Frame", {
		Name = "MiniReel",
		Position = UDim2.new(0, 12, 0, 48),
		Size = UDim2.new(1, -24, 0, 64),
		BackgroundColor3 = Color3.fromRGB(4, 4, 4),
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, toast)
	corner(mini, UDim.new(0, 16))
	stroke(mini, 1, Color3.fromRGB(27, 27, 27), true)
	sampleRow(mini, "RowTemplate", 4, LOCAL_ID, "haza", "hazatargz")

	local progress = make("Frame", {
		Name = "Progress",
		Position = UDim2.new(0, 12, 0, 120),
		Size = UDim2.new(1, -24, 0, 4),
		BackgroundColor3 = Color3.fromRGB(27, 27, 27),
		BorderSizePixel = 0,
	}, toast)
	corner(progress)
	local fill = make("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0.4, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, progress)
	corner(fill)
	make("UIGradient", { Color = ColorSequence.new(PURPLE_A, PURPLE_B), Rotation = 0 }, fill)

	gui.Parent = parent
	return gui
end

return {
	build = build,
}
