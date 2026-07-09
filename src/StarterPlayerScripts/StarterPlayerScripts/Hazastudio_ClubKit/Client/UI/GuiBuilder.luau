--!strict

local Players = game:GetService("Players")

local GuiBuilder = {}

local COLORS = {
	bg = Color3.fromRGB(9, 14, 24),
	panel = Color3.fromRGB(18, 28, 44),
	panelSoft = Color3.fromRGB(28, 42, 64),
	text = Color3.fromRGB(244, 247, 252),
	textSoft = Color3.fromRGB(172, 184, 204),
	accent = Color3.fromRGB(69, 178, 255),
	accentSoft = Color3.fromRGB(120, 216, 255),
	warn = Color3.fromRGB(255, 102, 102),
	fav = Color3.fromRGB(255, 200, 74),
}

local function getPlayerGui(): PlayerGui
	return Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
end

local function clearChildren(instance: Instance)
	for _, child in ipairs(instance:GetChildren()) do
		if child:IsA("GuiObject") or child:IsA("UIListLayout") or child:IsA("UIPadding") or child:IsA("UICorner") or child:IsA("UIStroke") then
			child:Destroy()
		end
	end
end

local function addCorner(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function addStroke(instance: GuiObject, color: Color3, transparency: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Parent = instance
end

local function addPadding(instance: Instance, size: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, size)
	padding.PaddingBottom = UDim.new(0, size)
	padding.PaddingLeft = UDim.new(0, size)
	padding.PaddingRight = UDim.new(0, size)
	padding.Parent = instance
end

local function makeLabel(parent: Instance, name: string, text: string, height: number, size: number, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.new(1, 0, 0, height)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color or COLORS.text
	label.Font = Enum.Font.Gotham
	label.TextSize = size
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function makeButton(parent: Instance, name: string, text: string, width: number?, color: Color3?): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.new(if width then 0 else 1, width or 0, 0, 38)
	button.BackgroundColor3 = color or COLORS.panelSoft
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Text = text
	button.TextColor3 = COLORS.text
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 14
	button.Parent = parent
	addCorner(button, 12)
	addStroke(button, COLORS.accentSoft, 0.7)
	return button
end

function GuiBuilder.ensure()
	local playerGui = getPlayerGui()

	local emoteGui = playerGui:FindFirstChild("EmoteGui") :: ScreenGui?
	if not emoteGui then
		local created = Instance.new("ScreenGui")
		created.Name = "EmoteGui"
		created.ResetOnSpawn = false
		created.IgnoreGuiInset = true
		created.DisplayOrder = 25
		created.Parent = playerGui
		emoteGui = created
	else
		clearChildren(emoteGui)
	end

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = emoteGui

	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(0, 420, 0, 560)
	mainFrame.Position = UDim2.new(1, -444, 0.5, -280)
	mainFrame.BackgroundColor3 = COLORS.panel
	mainFrame.BorderSizePixel = 0
	mainFrame.Visible = false
	mainFrame.Parent = root
	addCorner(mainFrame, 24)
	addStroke(mainFrame, COLORS.accentSoft, 0.8)
	addPadding(mainFrame, 18)

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = mainFrame

	makeLabel(mainFrame, "Header", "Dance Library", 26, 18, nil)
	makeLabel(mainFrame, "SubHeader", "Open from your own ScreenGui button, then choose dance, speed, and sync controls here.", 34, 12, COLORS.textSoft)

	local searchBox = Instance.new("TextBox")
	searchBox.Name = "SearchBox"
	searchBox.Size = UDim2.new(1, 0, 0, 40)
	searchBox.BackgroundColor3 = COLORS.panelSoft
	searchBox.BorderSizePixel = 0
	searchBox.PlaceholderText = "Search dance or pose..."
	searchBox.PlaceholderColor3 = COLORS.textSoft
	searchBox.ClearTextOnFocus = false
	searchBox.Text = ""
	searchBox.TextColor3 = COLORS.text
	searchBox.Font = Enum.Font.Gotham
	searchBox.TextSize = 14
	searchBox.Parent = mainFrame
	addCorner(searchBox, 14)
	addStroke(searchBox, COLORS.accentSoft, 0.82)
	addPadding(searchBox, 12)

	local control = Instance.new("Frame")
	control.Name = "Control"
	control.Size = UDim2.new(1, 0, 0, 38)
	control.BackgroundTransparency = 1
	control.Parent = mainFrame
	local controlLayout = Instance.new("UIListLayout")
	controlLayout.FillDirection = Enum.FillDirection.Horizontal
	controlLayout.Padding = UDim.new(0, 10)
	controlLayout.SortOrder = Enum.SortOrder.LayoutOrder
	controlLayout.Parent = control
	makeButton(control, "Dance", "Dance", 130, COLORS.accent)
	makeButton(control, "Pose", "Pose", 120, COLORS.panelSoft)
	makeButton(control, "Favorite", "Favorite", 120, COLORS.panelSoft)

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(1, 0, 1, -260)
	container.BackgroundColor3 = COLORS.panelSoft
	container.BorderSizePixel = 0
	container.Parent = mainFrame
	addCorner(container, 18)
	addStroke(container, COLORS.accentSoft, 0.85)

	local containerList = Instance.new("ScrollingFrame")
	containerList.Name = "ContainerList"
	containerList.Size = UDim2.new(1, -16, 1, -16)
	containerList.Position = UDim2.new(0, 8, 0, 8)
	containerList.BackgroundTransparency = 1
	containerList.BorderSizePixel = 0
	containerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	containerList.CanvasSize = UDim2.new()
	containerList.ScrollBarThickness = 5
	containerList.Parent = container
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = containerList

	local template = Instance.new("Frame")
	template.Name = "Template"
	template.Size = UDim2.new(1, -8, 0, 42)
	template.BackgroundColor3 = COLORS.panel
	template.BorderSizePixel = 0
	template.Visible = false
	template.Parent = containerList
	addCorner(template, 12)
	addStroke(template, COLORS.accentSoft, 0.88)

	local templateBtn = makeButton(template, "TemplateBtn", "Dance", nil, COLORS.panel)
	templateBtn.Size = UDim2.new(1, -48, 1, -6)
	templateBtn.Position = UDim2.new(0, 4, 0, 3)
	templateBtn.BackgroundTransparency = 1
	templateBtn.TextXAlignment = Enum.TextXAlignment.Left

	local favoriteBtn = makeButton(template, "FavoriteBtn", "o", 36, COLORS.panelSoft)
	favoriteBtn.Position = UDim2.new(1, -40, 0, 3)
	favoriteBtn.TextColor3 = COLORS.fav
	favoriteBtn.TextSize = 18

	local speedFrame = Instance.new("Frame")
	speedFrame.Name = "SpeedFrame"
	speedFrame.Size = UDim2.new(1, 0, 0, 76)
	speedFrame.BackgroundColor3 = COLORS.panelSoft
	speedFrame.BorderSizePixel = 0
	speedFrame.Parent = mainFrame
	addCorner(speedFrame, 16)
	addStroke(speedFrame, COLORS.accentSoft, 0.85)
	addPadding(speedFrame, 12)

	makeLabel(speedFrame, "TextLabel", "Speed 1.0x", 18, 12, COLORS.textSoft)

	local speedBar = Instance.new("Frame")
	speedBar.Name = "speedBar"
	speedBar.Size = UDim2.new(1, 0, 0, 16)
	speedBar.Position = UDim2.new(0, 0, 0, 36)
	speedBar.BackgroundColor3 = COLORS.bg
	speedBar.BorderSizePixel = 0
	speedBar.Parent = speedFrame
	addCorner(speedBar, 999)

	local speedPosition = Instance.new("Frame")
	speedPosition.Name = "speedPosition"
	speedPosition.Size = UDim2.new(0, 24, 1, 8)
	speedPosition.Position = UDim2.new(0.2, -12, 0, -4)
	speedPosition.BackgroundColor3 = COLORS.accent
	speedPosition.BorderSizePixel = 0
	speedPosition.Parent = speedBar
	addCorner(speedPosition, 999)
	addStroke(speedPosition, COLORS.text, 0.5)

	local dragButton = Instance.new("TextButton")
	dragButton.Name = "Button"
	dragButton.Size = UDim2.fromScale(1, 1)
	dragButton.BackgroundTransparency = 1
	dragButton.Text = ""
	dragButton.Parent = speedPosition

	local unsyncFrame = Instance.new("Frame")
	unsyncFrame.Name = "UnsyncFrame"
	unsyncFrame.Size = UDim2.new(1, 0, 0, 92)
	unsyncFrame.BackgroundColor3 = COLORS.panelSoft
	unsyncFrame.BorderSizePixel = 0
	unsyncFrame.Visible = false
	unsyncFrame.Parent = mainFrame
	addCorner(unsyncFrame, 16)
	addStroke(unsyncFrame, COLORS.accentSoft, 0.85)
	addPadding(unsyncFrame, 12)

	makeLabel(unsyncFrame, "DanceLabel", "Sync ready", 18, 13, nil)
	local leaderLabel = makeLabel(unsyncFrame, "LeaderLabel", "Synced to: -", 18, 12, COLORS.textSoft)
	leaderLabel.Position = UDim2.new(0, 0, 0, 24)
	local animLabel = makeLabel(unsyncFrame, "AnimLabel", "", 18, 12, COLORS.textSoft)
	animLabel.Position = UDim2.new(0, 0, 0, 46)
	local unsyncBtn = makeButton(unsyncFrame, "UnsyncBtn", "Unsync", 100, COLORS.warn)
	unsyncBtn.Position = UDim2.new(1, -100, 0.5, -19)

	return emoteGui
end

return GuiBuilder
