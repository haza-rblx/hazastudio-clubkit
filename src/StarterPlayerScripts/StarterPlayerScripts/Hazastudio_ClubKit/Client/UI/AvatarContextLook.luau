--!strict
-- Avatar context menu polish (owner, 2026-10-07; spec §2 of
-- docs/plans/ui-experiments-dance-acm-2026-10-07.md). Applied in code so buyers get it through
-- the engine sync:
--   * MainWrapper becomes a Frame (the outer CanvasGroup only clipped the shadow),
--   * no outlines; panel surfaces stay black while buttons and tiles take the accent,
--   * soft shadow, 5px gaps (whole pixels at the desktop UIScale 0.8),
--   * a stats strip (Robux / Rupiah / Level / Streak) under Connections / Total likes,
--   * the full-width actions grouped (18 outer / 4 inner corners) with a Propose Couple row.
-- Every lookup is guarded: a buyer GUI missing a piece just keeps that piece as designed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local KitLook = require(script.Parent.KitLook)

local AvatarContextLook = {}

local GAP = 5 -- x 0.8 desktop UIScale = exactly 4 screen px
local TILE_HEIGHT = 68
local OUTER_RADIUS, INNER_RADIUS = 18, 4
local NO_TINT = "AccentNoTint"
local STAT_VALUE = { size = 24, weight = Enum.FontWeight.ExtraBold }
local STAT_CAPTION = { size = 14, weight = Enum.FontWeight.SemiBold, color = Color3.fromHex("9a9a9a") }
local SURFACE_FALLBACK = Color3.fromHex("111111")
local TILE_FALLBACK = Color3.fromHex("1b1b1b")

local ORDER = {
	PlayerInformation = 1,
	SocialProofSection = 2,
	StatsStrip = 3,
	BioSection = 4,
	RelationshipStatus = 5,
	Separator = 8,
	ButtonsGroup = 10,
	ActionGroup = 11,
}

local WRAPPER_PROPS = {
	"Name",
	"Size",
	"Position",
	"AnchorPoint",
	"BackgroundColor3",
	"BackgroundTransparency",
	"BorderSizePixel",
	"LayoutOrder",
	"Visible",
	"ZIndex",
	"Active",
	"Rotation",
	"SizeConstraint",
	"Selectable",
}

-- The colour a GUI designed, under any accent tint already written over it.
local function designColor(target: GuiObject, fallback: Color3): Color3
	local design = target:GetAttribute("AccentDesignBackgroundColor3")
	if typeof(design) == "Color3" then
		return design
	end
	return if target.BackgroundTransparency < 1 then target.BackgroundColor3 else fallback
end

--- CanvasGroup MainWrapper -> Frame, before AvatarContextUI captures any reference.
function AvatarContextLook.prepareWrapper(wrapper: GuiObject): GuiObject
	local result = wrapper
	if wrapper:IsA("CanvasGroup") then
		local frame = Instance.new("Frame")
		for _, property in ipairs(WRAPPER_PROPS) do
			pcall(function()
				(frame :: any)[property] = (wrapper :: any)[property]
			end)
		end
		for key, value in pairs(wrapper:GetAttributes()) do
			frame:SetAttribute(key, value)
		end
		for _, child in ipairs(wrapper:GetChildren()) do
			child.Parent = frame
		end
		frame.Parent = wrapper.Parent
		wrapper:Destroy()
		result = frame
	end
	-- XY made the width balloon once children with scale widths changed; the width is fixed.
	result.AutomaticSize = Enum.AutomaticSize.Y
	return result
end

local function disableStroke(target: Instance?)
	if not target then
		return
	end
	for _, child in ipairs(target:GetChildren()) do
		if child:IsA("UIStroke") then
			child.Enabled = false
		end
	end
end

-- AccentNoTint covers a whole subtree, so the surface goes transparent and an empty, untinted
-- backdrop child paints the designed colour underneath everything else.
local function untintSurface(surface: GuiObject?)
	if not surface or surface:FindFirstChild("NoTintBackdrop") then
		return
	end
	local color = designColor(surface, SURFACE_FALLBACK)
	local backdrop = Instance.new("Frame")
	backdrop.Name = "NoTintBackdrop"
	backdrop:SetAttribute(NO_TINT, true)
	backdrop.BackgroundColor3 = color
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = 0
	backdrop.Active = false
	local corner = surface:FindFirstChildWhichIsA("UICorner")
	if corner then
		corner:Clone().Parent = backdrop
	end
	backdrop.Parent = surface
	surface.BackgroundTransparency = 1
end

-- The hero fade must land on black. A watched UIGradient keeps being recoloured, so the old one
-- is replaced by a fresh copy under an AccentNoTint parent.
local function untintGradientOverlay(root: Instance)
	local overlay = root:FindFirstChild("GradientOverlay", true)
	if not overlay then
		return
	end
	overlay:SetAttribute(NO_TINT, true)
	local gradient = overlay:FindFirstChildWhichIsA("UIGradient")
	if not gradient then
		return
	end
	local design = gradient:GetAttribute("AccentDesignColor")
	local fresh = gradient:Clone()
	if typeof(design) == "ColorSequence" then
		fresh.Color = design
	end
	fresh.Parent = overlay
	gradient:Destroy()
end

local function addShadow(target: GuiObject?)
	if target and not target:FindFirstChild("SoftShadow") then
		KitLook.shadow(target)
	end
end

local function styleStatLabels(container: Instance)
	local labels: { TextLabel } = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(labels, child)
		end
	end
	table.sort(labels, function(a, b)
		return a.TextSize > b.TextSize
	end)
	if labels[1] then
		labels[1].FontFace = KitLook.font(STAT_VALUE.weight)
		labels[1].TextSize = STAT_VALUE.size
		labels[1].TextColor3 = KitLook.COLOR.white
	end
	if labels[2] then
		labels[2].FontFace = KitLook.font(STAT_CAPTION.weight)
		labels[2].TextSize = STAT_CAPTION.size
		labels[2].TextColor3 = STAT_CAPTION.color
	end
	local layout = container:FindFirstChildWhichIsA("UIListLayout")
	if layout then
		layout.Padding = UDim.new(0, 3)
	end
end

local function flexRow(container: GuiObject?)
	if not container then
		return
	end
	local layout = container:FindFirstChildWhichIsA("UIListLayout")
	if layout then
		layout.Padding = UDim.new(0, GAP)
		layout.HorizontalFlex = Enum.UIFlexAlignment.Fill
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	end
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") then
			child.Size = UDim2.new(0, 0, 1, 0)
		end
	end
end

local function compact(value: number): string
	local units = { { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
	for _, unit in ipairs(units) do
		if value >= unit[1] then
			local scaled = value / unit[1]
			if scaled >= 100 then
				return string.format("%d%s", math.floor(scaled), unit[2])
			end
			local text = string.format("%.1f", math.floor(scaled * 10) / 10):gsub("%.0$", "")
			return text .. unit[2]
		end
	end
	return tostring(math.floor(value))
end

local STAT_COLUMNS = {
	{ stat = "ROBUX_STAT_NAME", fallback = "Robux", caption = "Robux", compact = true },
	{ stat = "CASH_STAT_NAME", fallback = "Cash", caption = "Rupiah", compact = true },
	{ stat = "LEVEL_STAT_NAME", fallback = "Level", caption = "Level" },
	{ stat = "STREAK_STAT_NAME", fallback = "Streak", caption = "Streak" },
}

local function buildStatsStrip(mainContent: Instance, fill: Color3): ({ TextLabel }, Frame)
	local strip = KitLook.box(nil, "StatsStrip", UDim2.new(1, 0, 0, TILE_HEIGHT), ORDER.StatsStrip, fill)
	KitLook.corner(strip, UDim.new(0, 20))
	KitLook.padding(strip, 6, 0)
	local layout = KitLook.list(strip, Enum.FillDirection.Horizontal, 0, nil, Enum.VerticalAlignment.Center)
	layout.HorizontalFlex = Enum.UIFlexAlignment.Fill
	local values: { TextLabel } = {}
	for index, column in ipairs(STAT_COLUMNS) do
		local cell = KitLook.box(strip, column.caption, UDim2.new(0, 0, 0, 0), index)
		cell.AutomaticSize = Enum.AutomaticSize.Y
		KitLook.list(cell, Enum.FillDirection.Vertical, 3, Enum.HorizontalAlignment.Center)
		values[index] = KitLook.text(cell, "-", STAT_VALUE.size, STAT_VALUE.weight, KitLook.COLOR.white, 1, {
			align = Enum.TextXAlignment.Center,
		})
		KitLook.text(cell, column.caption, STAT_CAPTION.size, STAT_CAPTION.weight, STAT_CAPTION.color, 2, {
			align = Enum.TextXAlignment.Center,
		})
	end
	strip.Parent = mainContent
	return values, strip
end

-- GroupedRowCornerUtil radii over the visible rows, top to bottom.
local function regroup(group: Frame)
	local rows: { GuiObject } = {}
	for _, child in ipairs(group:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible then
			table.insert(rows, child)
		end
	end
	table.sort(rows, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	local outer, inner = UDim.new(0, OUTER_RADIUS), UDim.new(0, INNER_RADIUS)
	for index, row in ipairs(rows) do
		local corner = row:FindFirstChildWhichIsA("UICorner") or KitLook.corner(row, outer)
		local first, last = index == 1, index == #rows
		corner.TopLeftRadius = if first then outer else inner
		corner.TopRightRadius = if first then outer else inner
		corner.BottomLeftRadius = if last then outer else inner
		corner.BottomRightRadius = if last then outer else inner
	end
	group.Visible = #rows > 0
end

export type Parts = {
	contentWrapper: GuiObject,
	mainContent: ScrollingFrame,
	draggableIcon: GuiObject?,
	loadingScreen: GuiObject?,
	socialProofSection: GuiObject?,
	connectionCard: GuiObject?,
	followersCard: GuiObject?,
	buttonsGroup: GuiObject?,
	syncDanceButton: GuiObject?,
	sendGiftButton: GuiObject?,
	sendFriendRequestButton: GuiObject?,
	investigateAvatarButton: GuiObject?,
}

export type Look = {
	proposeButton: TextButton?,
	setStats: (userId: number?) -> (),
}

function AvatarContextLook.decorate(parts: Parts): Look
	local content, scroll = parts.contentWrapper, parts.mainContent
	local buttonFill = if parts.syncDanceButton then designColor(parts.syncDanceButton, TILE_FALLBACK) else TILE_FALLBACK
	local surfaceColor = designColor(content, SURFACE_FALLBACK)

	-- Outlines off; black surfaces; the hero fade lands on black; soft shadows.
	disableStroke(content)
	disableStroke(parts.draggableIcon)
	disableStroke(parts.connectionCard)
	disableStroke(parts.followersCard)
	disableStroke(scroll:FindFirstChild("RelationshipStatus"))
	untintSurface(content)
	untintSurface(parts.draggableIcon)
	untintSurface(parts.loadingScreen)
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("GuiObject") and string.find(string.lower(child.Name), "separator", 1, true) then
			untintSurface(child)
		end
	end
	scroll.BackgroundTransparency = 1
	scroll:SetAttribute("AffordanceColor", surfaceColor)
	untintGradientOverlay(scroll)
	addShadow(content)
	addShadow(parts.draggableIcon)

	-- Order + 5px rhythm.
	local scrollLayout = scroll:FindFirstChildWhichIsA("UIListLayout")
	if scrollLayout then
		scrollLayout.Padding = UDim.new(0, GAP)
	end
	for name, order in pairs(ORDER) do
		local child = scroll:FindFirstChild(name)
		if child and child:IsA("GuiObject") then
			child.LayoutOrder = order
		end
	end

	-- Connections / Total likes: same family as the stats strip.
	local social = parts.socialProofSection
	if social then
		social.Size = UDim2.new(social.Size.X.Scale, social.Size.X.Offset, 0, TILE_HEIGHT)
		flexRow(social)
		for _, tile in ipairs({ parts.connectionCard, parts.followersCard }) do
			if tile then
				tile.BackgroundColor3 = buttonFill
				tile.BackgroundTransparency = 0
				styleStatLabels(tile)
			end
		end
	end
	local statValues = buildStatsStrip(scroll, buttonFill)
	flexRow(parts.buttonsGroup)

	-- Full-width actions as one grouped list, Propose Couple between gift and friend request.
	local group = KitLook.box(nil, "ActionGroup", UDim2.new(1, 0, 0, 0), ORDER.ActionGroup)
	group.AutomaticSize = Enum.AutomaticSize.Y
	KitLook.list(group, Enum.FillDirection.Vertical, GAP)
	group.Parent = scroll
	local proposeButton: TextButton? = nil
	local template = parts.sendFriendRequestButton
	if template and template:IsA("TextButton") then
		local made = template:Clone()
		made.Name = "ProposeCoupleButton"
		made.Visible = false
		local label = made:FindFirstChildWhichIsA("TextLabel", true)
		if label then
			label.Text = "Propose Couple"
		end
		proposeButton = made
	end
	local rows = { parts.sendGiftButton, proposeButton, parts.sendFriendRequestButton, parts.investigateAvatarButton }
	for index, row in ipairs(rows) do
		if row then
			row.LayoutOrder = index
			row.Parent = group
			row:GetPropertyChangedSignal("Visible"):Connect(function()
				regroup(group)
			end)
		end
	end
	regroup(group)

	local function setStats(userId: number?)
		local player = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
		local leaderstats = player and player:FindFirstChild("leaderstats")
		local playerList = Config.PlayerList or {}
		for index, column in ipairs(STAT_COLUMNS) do
			local statName = tostring(playerList[column.stat] or column.fallback)
			local stat = leaderstats and leaderstats:FindFirstChild(statName)
			local raw = if stat and (stat:IsA("IntValue") or stat:IsA("NumberValue")) then stat.Value else nil
			statValues[index].Text = if raw == nil
				then "-"
				elseif column.compact then compact(raw)
				else tostring(math.floor(raw))
		end
	end

	return {
		proposeButton = proposeButton,
		setStats = setStats,
	}
end

return AvatarContextLook
