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

function DovetailUI.formatMarkdownPlain(text: string): string
	local lines = {}
	for line in string.gmatch(text, "[^\r\n]+") do
		line = string.gsub(line, "^###%s*", "")
		line = string.gsub(line, "^##%s*", "")
		line = string.gsub(line, "^#%s*", "")
		line = string.gsub(line, "%*%*(.-)%*%*", "%1")
		line = string.gsub(line, "`(.-)`", "%1")
		line = string.gsub(line, "%[(.-)%]%(.-%)", "%1")
		if string.match(line, "%S") then
			if string.match(line, "^%- ") then
				line = "  " .. line
			end
			table.insert(lines, line)
		end
	end
	return table.concat(lines, "\n")
end

function DovetailUI.brandHeader(parent: Instance, kitVersion: string, layoutOrder: number?)
	local header = Instance.new("Frame")
	header.BackgroundColor3 = Theme.colors.graphite
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, Theme.sizes.brandHeight)
	if layoutOrder then
		header.LayoutOrder = layoutOrder
	end
	header.Parent = parent
	applyCorner(header)
	applyStroke(header, Theme.colors.indigoDeep, 0.55)

	local accent = Instance.new("Frame")
	accent.BackgroundColor3 = Theme.colors.softIndigo
	accent.BorderSizePixel = 0
	accent.Size = UDim2.new(0, 4, 1, -16)
	accent.Position = UDim2.new(0, 0, 0, 8)
	accent.Parent = header
	applyCorner(accent, 2)

	local logo = Instance.new("Frame")
	logo.BackgroundColor3 = Theme.colors.indigoDeep
	logo.BorderSizePixel = 0
	logo.Size = UDim2.new(0, 44, 0, 44)
	logo.Position = UDim2.new(0, 16, 0.5, -22)
	logo.Parent = header
	applyCorner(logo, 10)
	applyStroke(logo, Theme.colors.indigoGlow, 0.2)

	local monogram = Instance.new("TextLabel")
	monogram.BackgroundTransparency = 1
	monogram.Size = UDim2.new(1, 0, 1, 0)
	monogram.Font = Theme.fonts.title
	monogram.TextSize = 16
	monogram.TextColor3 = Theme.colors.bone
	monogram.Text = "HK"
	monogram.Parent = logo

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 72, 0, 16)
	title.Size = UDim2.new(1, -150, 0, 22)
	title.Font = Theme.fonts.title
	title.TextSize = Theme.sizes.title
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Theme.colors.bone
	title.Text = "Hazastudio Club Kit"
	title.Parent = header

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.new(0, 72, 0, 40)
	subtitle.Size = UDim2.new(1, -150, 0, 16)
	subtitle.Font = Theme.fonts.body
	subtitle.TextSize = Theme.sizes.subtitle
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextColor3 = Theme.colors.ash
	subtitle.Text = "Engine updater and RBXM packager"
	subtitle.Parent = header

	local versionPill = Instance.new("TextLabel")
	versionPill.BackgroundColor3 = Theme.colors.iron
	versionPill.BorderSizePixel = 0
	versionPill.AnchorPoint = Vector2.new(1, 0.5)
	versionPill.Position = UDim2.new(1, -14, 0.5, 0)
	versionPill.Size = UDim2.new(0, 64, 0, 24)
	versionPill.Font = Theme.fonts.eyebrow
	versionPill.TextSize = 11
	versionPill.TextColor3 = Theme.colors.indigoGlow
	versionPill.Text = "v" .. kitVersion
	versionPill.Parent = header
	applyCorner(versionPill, 12)
	applyStroke(versionPill, Theme.colors.softIndigo, 0.5)

	return header
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

function DovetailUI.sectionHeader(parent: Instance, title: string, description: string?, layoutOrder: number?)
	local block = Instance.new("Frame")
	block.BackgroundTransparency = 1
	block.Size = UDim2.new(1, 0, 0, 0)
	block.AutomaticSize = Enum.AutomaticSize.Y
	block.LayoutOrder = layoutOrder or 0
	block.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = block

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, 0, 0, 18)
	titleLabel.Font = Theme.fonts.bodyBold
	titleLabel.TextSize = Theme.sizes.body + 1
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = Theme.colors.bone
	titleLabel.Text = title
	titleLabel.LayoutOrder = 0
	titleLabel.Parent = block

	if description then
		local descLabel = Instance.new("TextLabel")
		descLabel.BackgroundTransparency = 1
		descLabel.Size = UDim2.new(1, 0, 0, 0)
		descLabel.AutomaticSize = Enum.AutomaticSize.Y
		descLabel.Font = Theme.fonts.body
		descLabel.TextSize = 12
		descLabel.TextWrapped = true
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextColor3 = Theme.colors.ash
		descLabel.Text = description
		descLabel.LayoutOrder = 1
		descLabel.Parent = block
	end

	return block
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

function DovetailUI.versionPillRow(parent: Instance, layoutOrder: number?): (TextLabel, TextLabel)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 58)
	row.LayoutOrder = layoutOrder or 0
	row.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, Theme.sizes.gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local function makePill(labelText: string, order: number): TextLabel
		local pill = Instance.new("Frame")
		pill.BackgroundColor3 = Theme.colors.graphite
		pill.BorderSizePixel = 0
		pill.Size = UDim2.new(0.5, -5, 1, 0)
		pill.LayoutOrder = order
		pill.Parent = row
		applyCorner(pill)
		applyStroke(pill)

		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 10)
		padding.PaddingBottom = UDim.new(0, 10)
		padding.PaddingLeft = UDim.new(0, 12)
		padding.PaddingRight = UDim.new(0, 12)
		padding.Parent = pill

		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.Size = UDim2.new(1, 0, 0, 14)
		nameLabel.Font = Theme.fonts.eyebrow
		nameLabel.TextSize = 10
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextColor3 = Theme.colors.softIndigo
		nameLabel.Text = string.upper(labelText)
		nameLabel.Parent = pill

		local valueLabel = Instance.new("TextLabel")
		valueLabel.BackgroundTransparency = 1
		valueLabel.Position = UDim2.new(0, 0, 0, 18)
		valueLabel.Size = UDim2.new(1, 0, 0, 22)
		valueLabel.Font = Theme.fonts.bodyBold
		valueLabel.TextSize = Theme.sizes.stat
		valueLabel.TextXAlignment = Enum.TextXAlignment.Left
		valueLabel.TextColor3 = Theme.colors.bone
		valueLabel.Text = "-"
		valueLabel.Parent = pill

		return valueLabel
	end

	return makePill("Installed", 0), makePill("Latest", 1)
end

function DovetailUI.changelogBox(parent: Instance, layoutOrder: number?): TextLabel
	local box = Instance.new("Frame")
	box.BackgroundColor3 = Theme.colors.graphite
	box.BorderSizePixel = 0
	box.Size = UDim2.new(1, 0, 0, Theme.sizes.changelogHeight)
	box.LayoutOrder = layoutOrder or 0
	box.Parent = parent
	applyCorner(box)
	applyStroke(box)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = box

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.new(1, 0, 1, 0)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Theme.colors.smoke
	scroll.Parent = box

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -4, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = Theme.fonts.body
	label.TextSize = 12
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextColor3 = Theme.colors.ash
	label.Text = "Check for updates to load release notes."
	label.Parent = scroll

	return label
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

-- Full-width iOS-style pill CTA (Update Now).
function DovetailUI.pillPrimaryButton(parent: Instance, text: string, layoutOrder: number?): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 0, Theme.sizes.pillButtonHeight)
	button.Font = Theme.fonts.bodyBold
	button.TextSize = Theme.sizes.body + 1
	button.Text = text
	button.AutoButtonColor = true
	button.BackgroundColor3 = Theme.colors.softIndigo
	button.TextColor3 = Theme.colors.bone
	button.LayoutOrder = layoutOrder or 0
	button.Parent = parent
	applyCorner(button, Theme.sizes.pillCorner)
	return button
end

-- Text-only secondary action (Remind Me Later / Check for Updates).
function DovetailUI.textLinkButton(parent: Instance, text: string, layoutOrder: number?): TextButton
	local button = Instance.new("TextButton")
	button.BackgroundTransparency = 1
	button.Size = UDim2.new(1, 0, 0, 28)
	button.Font = Theme.fonts.body
	button.TextSize = Theme.sizes.body
	button.Text = text
	button.TextColor3 = Theme.colors.softIndigo
	button.AutoButtonColor = false
	button.LayoutOrder = layoutOrder or 0
	button.Parent = parent
	return button
end

function DovetailUI.checkboxRow(parent: Instance, label: string, default: boolean, layoutOrder: number?): BoolValue
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, Theme.sizes.rowHeight)
	row.LayoutOrder = layoutOrder or 0
	row.Parent = parent

	local check = Instance.new("TextButton")
	check.Size = UDim2.new(0, 20, 0, 20)
	check.Position = UDim2.new(0, 0, 0, 4)
	check.BackgroundColor3 = Theme.colors.graphite
	check.Text = ""
	check.AutoButtonColor = false
	check.Parent = row
	applyCorner(check, 4)
	applyStroke(check)

	local mark = Instance.new("Frame")
	mark.BackgroundColor3 = Theme.colors.softIndigo
	mark.BorderSizePixel = 0
	mark.Size = UDim2.new(0, 10, 0, 10)
	mark.Position = UDim2.new(0.5, -5, 0.5, -5)
	mark.Visible = default
	mark.Parent = check
	applyCorner(mark, 2)

	local flag = Instance.new("BoolValue")
	flag.Name = "Flag"
	flag.Value = default
	flag.Parent = check

	check.MouseButton1Click:Connect(function()
		flag.Value = not flag.Value
		mark.Visible = flag.Value
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
	local row = Instance.new("Frame")
	row.BackgroundColor3 = Theme.colors.graphite
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.LayoutOrder = layoutOrder or 0
	row.Parent = parent
	applyCorner(row, 6)
	applyStroke(row, Theme.colors.slateEdge, 0.6)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = row

	local dot = Instance.new("Frame")
	dot.Name = "StatusDot"
	dot.BackgroundColor3 = Theme.colors.ash
	dot.BorderSizePixel = 0
	dot.Size = UDim2.new(0, 6, 0, 6)
	dot.Position = UDim2.new(0, 10, 0, 11)
	dot.Parent = row
	applyCorner(dot, 3)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 22, 0, 0)
	label.Size = UDim2.new(1, -22, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = Theme.fonts.body
	label.TextSize = 12
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextColor3 = Theme.colors.ash
	label.Text = "Ready."
	label.Parent = row

	return label
end

function DovetailUI.setStatusTone(statusLabel: TextLabel, tone: string?)
	local row = statusLabel.Parent
	if not row then
		return
	end
	local dot = row:FindFirstChild("StatusDot")
	if not dot or not dot:IsA("Frame") then
		return
	end
	if tone == "error" then
		statusLabel.TextColor3 = Theme.colors.error
		dot.BackgroundColor3 = Theme.colors.error
	elseif tone == "success" then
		statusLabel.TextColor3 = Theme.colors.success
		dot.BackgroundColor3 = Theme.colors.success
	elseif tone == "warning" then
		statusLabel.TextColor3 = Theme.colors.warning
		dot.BackgroundColor3 = Theme.colors.warning
	else
		statusLabel.TextColor3 = Theme.colors.ash
		dot.BackgroundColor3 = Theme.colors.ash
	end
end

function DovetailUI.bodyText(parent: Instance, text: string, layoutOrder: number?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = Theme.fonts.body
	label.TextSize = 12
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextColor3 = Theme.colors.smoke
	label.Text = text
	if layoutOrder then
		label.LayoutOrder = layoutOrder
	end
	label.Parent = parent
	return label
end

function DovetailUI.divider(parent: Instance, layoutOrder: number?)
	local line = Instance.new("Frame")
	line.BackgroundColor3 = Theme.colors.slateEdge
	line.BorderSizePixel = 0
	line.Size = UDim2.new(1, 0, 0, 1)
	line.LayoutOrder = layoutOrder or 0
	line.Parent = parent
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
	layout.Padding = UDim.new(0, Theme.sizes.gap + 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content

	return scroll, content
end

return DovetailUI
