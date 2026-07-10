--!nocheck
-- Dovetail UI component factory for Club Kit plugin.

local Theme = require(script.Parent.DovetailTheme)

local DovetailUI = {}

local function applyCorner(inst: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or Theme.sizes.corner)
	corner.Parent = inst
end

local function applyStroke(inst: GuiObject, color: Color3?, transparency: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.colors.slateEdge
	stroke.Transparency = transparency or 0.35
	stroke.Thickness = 1
	stroke.Parent = inst
end

function DovetailUI.card(parent: Instance, layoutOrder: number?): Frame
	local card = Instance.new("Frame")
	card.BackgroundColor3 = Theme.colors.iron
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	if layoutOrder then
		card.LayoutOrder = layoutOrder
	end
	card.Parent = parent
	applyCorner(card)
	applyStroke(card)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, Theme.sizes.padding)
	padding.PaddingBottom = UDim.new(0, Theme.sizes.padding)
	padding.PaddingLeft = UDim.new(0, Theme.sizes.padding)
	padding.PaddingRight = UDim.new(0, Theme.sizes.padding)
	padding.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, Theme.sizes.gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card

	return card
end

function DovetailUI.eyebrow(parent: Instance, text: string, layoutOrder: number?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 14)
	label.Font = Theme.fonts.eyebrow
	label.TextSize = Theme.sizes.eyebrow
	label.TextColor3 = Theme.colors.softIndigo
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = string.upper(text)
	if layoutOrder then
		label.LayoutOrder = layoutOrder
	end
	label.Parent = parent
	return label
end

function DovetailUI.statBlock(parent: Instance, label: string, layoutOrder: number?): (Frame, TextLabel)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 44)
	row.LayoutOrder = layoutOrder or 0
	row.Parent = parent

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(0.5, -4, 1, 0)
	nameLabel.Font = Theme.fonts.body
	nameLabel.TextSize = Theme.sizes.body
	nameLabel.TextColor3 = Theme.colors.ash
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = label
	nameLabel.Parent = row

	local valueLabel = Instance.new("TextLabel")
	valueLabel.BackgroundTransparency = 1
	valueLabel.Position = UDim2.new(0.5, 4, 0, 0)
	valueLabel.Size = UDim2.new(0.5, -4, 1, 0)
	valueLabel.Font = Theme.fonts.bodyBold
	valueLabel.TextSize = Theme.sizes.stat
	valueLabel.TextColor3 = Theme.colors.bone
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Text = "—"
	valueLabel.Parent = row

	return row, valueLabel
end

local function makeButton(parent: Instance, text: string, variant: string, layoutOrder: number?): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 0, Theme.sizes.buttonHeight)
	button.Font = Theme.fonts.bodyBold
	button.TextSize = Theme.sizes.body
	button.Text = text
	button.AutoButtonColor = true
	button.LayoutOrder = layoutOrder or 0
	button.Parent = parent
	applyCorner(button)

	if variant == "primary" then
		button.BackgroundColor3 = Theme.colors.softIndigo
		button.TextColor3 = Theme.colors.carbon
	else
		button.BackgroundColor3 = Theme.colors.graphite
		button.TextColor3 = Theme.colors.bone
		applyStroke(button)
	end

	return button
end

function DovetailUI.primaryButton(parent: Instance, text: string, layoutOrder: number?): TextButton
	return makeButton(parent, text, "primary", layoutOrder)
end

function DovetailUI.ghostButton(parent: Instance, text: string, layoutOrder: number?): TextButton
	return makeButton(parent, text, "ghost", layoutOrder)
end

function DovetailUI.checkboxRow(parent: Instance, label: string, default: boolean, layoutOrder: number?): BoolValue
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, Theme.sizes.rowHeight)
	row.LayoutOrder = layoutOrder or 0
	row.Parent = parent

	local check = Instance.new("TextButton")
	check.Size = UDim2.new(0, 22, 0, 22)
	check.Position = UDim2.new(0, 0, 0, 2)
	check.BackgroundColor3 = Theme.colors.graphite
	check.Text = default and "✓" or ""
	check.TextColor3 = Theme.colors.bone
	check.Font = Theme.fonts.bodyBold
	check.TextSize = 14
	check.Parent = row
	applyCorner(check, 4)
	applyStroke(check)

	local flag = Instance.new("BoolValue")
	flag.Name = "Flag"
	flag.Value = default
	flag.Parent = check

	check.MouseButton1Click:Connect(function()
		flag.Value = not flag.Value
		check.Text = flag.Value and "✓" or ""
	end)

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Position = UDim2.new(0, 30, 0, 0)
	text.Size = UDim2.new(1, -30, 1, 0)
	text.Font = Theme.fonts.body
	text.TextSize = Theme.sizes.body
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextColor3 = Theme.colors.ash
	text.Text = label
	text.Parent = row

	return flag
end

function DovetailUI.statusLine(parent: Instance, layoutOrder: number?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = Theme.fonts.body
	label.TextSize = 12
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextColor3 = Theme.colors.ash
	label.Text = ""
	if layoutOrder then
		label.LayoutOrder = layoutOrder
	end
	label.Parent = parent
	return label
end

function DovetailUI.bodyText(parent: Instance, text: string, layoutOrder: number?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = Theme.fonts.body
	label.TextSize = Theme.sizes.body
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextColor3 = Theme.colors.ash
	label.Text = text
	if layoutOrder then
		label.LayoutOrder = layoutOrder
	end
	label.Parent = parent
	return label
end

function DovetailUI.scrollRoot(parent: Instance): (ScrollingFrame, Frame)
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundColor3 = Theme.colors.carbon
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.new(1, 0, 1, 0)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Theme.colors.smoke
	scroll.Parent = parent

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, Theme.sizes.padding)
	padding.PaddingBottom = UDim.new(0, Theme.sizes.padding)
	padding.PaddingLeft = UDim.new(0, Theme.sizes.padding)
	padding.PaddingRight = UDim.new(0, Theme.sizes.padding)
	padding.Parent = scroll

	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, 0, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Parent = scroll

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, Theme.sizes.gap + 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content

	return scroll, content
end

return DovetailUI
