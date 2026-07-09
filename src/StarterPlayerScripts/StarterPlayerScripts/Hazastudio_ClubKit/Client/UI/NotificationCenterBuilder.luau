--!strict
-- Builder for 99-NotificationCenter > GeneralNotificationCenter GUI.
-- Call :build() to ensure the full toast structure exists in PlayerGui.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local NotificationCenterBuilder = {}

local COLORS = {
	bg = Color3.fromRGB(9, 14, 24),
	panel = Color3.fromRGB(18, 28, 44),
	panelSoft = Color3.fromRGB(28, 42, 64),
	text = Color3.fromRGB(244, 247, 252),
	textSoft = Color3.fromRGB(172, 184, 204),
	stroke = Color3.fromRGB(69, 178, 255),
}

-- ============================================================
-- Helpers
-- ============================================================

local function addCorner(parent: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function addStroke(parent: GuiObject, color: Color3, transparency: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Thickness = 1.2
	stroke.Parent = parent
end

local function _addPadding(parent: Instance, top: number, bottom: number?, left: number?, right: number?)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, top)
	padding.PaddingBottom = UDim.new(0, bottom or top)
	padding.PaddingLeft = UDim.new(0, left or top)
	padding.PaddingRight = UDim.new(0, right or top)
	padding.Parent = parent
end

-- ============================================================
-- Leaf constructors (true leaves: zero children after creation)
-- ============================================================

local function makeLeafIcon(parent: Instance, name: string, image: string): ImageLabel
	local icon = Instance.new("ImageLabel")
	icon.Name = name
	icon.Size = UDim2.new(0, 32, 0, 32)
	icon.BackgroundTransparency = 1
	icon.Image = image
	icon.ImageColor3 = Config.Notify.COLOR_INFO
	icon.ImageTransparency = 0
	icon.Parent = parent
	return icon
end

local function makeLeafTitle(parent: Instance, name: string, text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.new(1, 0, 0, 18)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = COLORS.text
	label.FontFace = Font.new("rbxassetid://12187365977", Enum.FontWeight.SemiBold)
	label.TextSize = 15
	label.TextWrapped = false
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Parent = parent
	return label
end

local function makeLeafDescription(parent: Instance, name: string, text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.new(1, 0, 0, 16)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = COLORS.textSoft
	label.FontFace = Font.new("rbxassetid://12187365977", Enum.FontWeight.Medium)
	label.TextSize = 14
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Parent = parent
	return label
end

-- ============================================================
-- Composite constructors
-- ============================================================

local function makeWrapper(parent: Instance): Frame
	local wrapper = Instance.new("Frame")
	wrapper.Name = "NotificationWrapper"
	wrapper.Size = UDim2.new(1, 0, 1, 0)
	wrapper.BackgroundTransparency = 1
	wrapper.BorderSizePixel = 0
	wrapper.Parent = parent

	-- Leaf: icon on the left, vertically centered
	local icon = makeLeafIcon(wrapper, "NotificationIcon", "rbxassetid://0")
	icon.Position = UDim2.new(0, 0, 0.5, -16)
	icon.AnchorPoint = Vector2.new(0, 0.5)

	-- Leaf: title stacked above description on the right
	local title = makeLeafTitle(wrapper, "NotificationTitle", "Notification")
	title.Position = UDim2.new(0, 44, 0, 4)
	title.Size = UDim2.new(1, -44, 0, 18)

	local desc = makeLeafDescription(wrapper, "NotificationDescription", "")
	desc.Position = UDim2.new(0, 44, 0, 24)
	desc.Size = UDim2.new(1, -44, 0, 16)

	return wrapper
end

local function makePanel(parent: Instance): Frame
	local panel = Instance.new("Frame")
	panel.Name = "GeneralNotificationCenter"
	panel.Size = UDim2.new(0, 400, 0, 76)
	panel.Position = UDim2.new(0.5, 0, 0, 72)
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.BackgroundColor3 = COLORS.panel
	panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = parent

	-- Decorative leaf: padding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = panel

	addCorner(panel, 20)
	addStroke(panel, COLORS.stroke, 0.75)

	-- Content wrapper
	makeWrapper(panel)

	return panel
end

-- ============================================================
-- Public API
-- ============================================================

function NotificationCenterBuilder.build(): ScreenGui
	local player = Players.LocalPlayer
	if not player then
		error("NotificationCenterBuilder.build() called before LocalPlayer exists")
	end

	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	local existing = playerGui:FindFirstChild("99-NotificationCenter")
	if existing and existing:IsA("ScreenGui") then
		return existing
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "99-NotificationCenter"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 99
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	makePanel(screenGui)

	return screenGui
end

function NotificationCenterBuilder.ensure(): ScreenGui
	local player = Players.LocalPlayer
	if not player then
		error("NotificationCenterBuilder.ensure() called before LocalPlayer exists")
	end

	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	local screenGui = playerGui:FindFirstChild("99-NotificationCenter") :: ScreenGui?

	if screenGui and screenGui:IsA("ScreenGui") then
		return screenGui
	end

	return NotificationCenterBuilder.build()
end

return NotificationCenterBuilder
