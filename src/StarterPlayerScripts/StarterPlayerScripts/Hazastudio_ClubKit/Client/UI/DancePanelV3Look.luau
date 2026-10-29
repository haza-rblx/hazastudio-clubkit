--!strict
-- Dance panel v3 polish (owner, 2026-10-07; spec §1 of
-- docs/plans/ui-experiments-dance-acm-2026-10-07.md). Code-built so buyers get it through the
-- engine sync, no GUI re-export:
--   * a Preferences-style "Speed" row with the value in a chip above the segmented speed bar,
--   * a taller bar (44) and a shorter dance list so the panel keeps its height,
--   * a search box with a magnifier and a clear button, left aligned,
--   * concentric corners (bar 11 -> wrapper 17, search 11).
-- Only the horizontal v3 layout (segmented bar + custom speed field) is touched; v1/v2 and the
-- vertical phone slider keep their GUI.

local KitLook = require(script.Parent.KitLook)
local PhoneLayout = require(script.Parent.Parent.Utils.PhoneLayout)

local DancePanelV3Look = {}

local BAR_HEIGHT = 44
local LABEL_HEIGHT = 22
local LABEL_GAP = 8
local LIST_TOP_GAP = 2 -- search -> list, as designed
local LIST_BOTTOM_GAP = 4 -- list -> label, as designed (was list -> bar)
local WRAPPER_RADIUS = 17 -- 11 (bar curve) + 6 (wrapper padding)
local SEARCH_RADIUS = 11
local SEARCH_ICON = "rbxassetid://72914550286274"
local ICON_SIZE, ICON_INSET, CLEAR_SIZE, CLEAR_INSET, TEXT_GAP = 18, 12, 14, 10, 8
local MUTED = Color3.fromHex("737373")
local CLEAR_COLOR = Color3.fromHex("9a9a9a")
local CHIP_BG = Color3.fromHex("030303")
local CHIP_STROKE = Color3.fromHex("292929")
local PLACEHOLDER = "Search dance or pose"
-- Phones: the speed bar stands right of the dance list.
local PHONE_BAR_WIDTH = 30
local PHONE_BAR_GAP = 6

export type Look = {
	setSpeedText: (text: string) -> (),
	connections: { RBXScriptConnection },
}

function DancePanelV3Look.isApplicable(refs: any): boolean
	local wrapper = refs.speedWrapper
	return not refs.speedSliderVertical
		and wrapper ~= nil
		and wrapper.ClassName == "Frame"
		and refs.customSpeedField ~= nil
		and refs.mainContentWrapper ~= nil
		and refs.mainContent ~= nil
		and refs.searchBox ~= nil
end

local function setRadius(target: Instance, radius: number)
	local corner = target:FindFirstChildWhichIsA("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, radius)
	else
		KitLook.corner(target, UDim.new(0, radius))
	end
end

local function buildSpeedRow(wrapper: GuiObject, bar: GuiObject): TextLabel
	local row = KitLook.box(nil, "SpeedLabel", UDim2.new(bar.Size.X.Scale, bar.Size.X.Offset, 0, LABEL_HEIGHT), 0)
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.new(0.5, 0, 1, -(BAR_HEIGHT + LABEL_GAP))
	local layout = KitLook.list(row, Enum.FillDirection.Horizontal, 0, nil, Enum.VerticalAlignment.Center)
	layout.HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween
	KitLook.text(row, "Speed", 14, Enum.FontWeight.SemiBold, KitLook.COLOR.white, 0)

	local chip = KitLook.box(row, "ValueChip", UDim2.new(0, 0, 0, LABEL_HEIGHT), 1, CHIP_BG)
	chip.AutomaticSize = Enum.AutomaticSize.X
	KitLook.corner(chip, UDim.new(1, 0))
	local stroke = Instance.new("UIStroke")
	stroke.Color = CHIP_STROKE
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = chip
	KitLook.padding(chip, 9, 0)
	local value = KitLook.text(chip, "1.00x", 13, Enum.FontWeight.Bold, KitLook.COLOR.white, 0)
	value.Name = "SliderCurrentValue"
	value.Size = UDim2.new(0, 0, 1, 0)
	value.AutomaticSize = Enum.AutomaticSize.X
	row.Parent = wrapper
	return value
end

local function polishSearch(box: TextBox, connections: { RBXScriptConnection })
	setRadius(box, SEARCH_RADIUS)
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.ClearTextOnFocus = false
	box.PlaceholderText = PLACEHOLDER
	local padding = box:FindFirstChildWhichIsA("UIPadding") or Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, ICON_INSET + ICON_SIZE + TEXT_GAP)
	padding.PaddingRight = UDim.new(0, CLEAR_INSET + CLEAR_SIZE + TEXT_GAP)
	padding.Parent = box

	-- UIPadding moves children too: negative offsets park the glyphs in the padded margins.
	local icon = box:FindFirstChildWhichIsA("ImageLabel")
	if not icon then
		local made = Instance.new("ImageLabel")
		made.Name = "Icon"
		made.BackgroundTransparency = 1
		made.Image = SEARCH_ICON
		made.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
		made.AnchorPoint = Vector2.new(0, 0.5)
		made.Position = UDim2.new(0, -(ICON_SIZE + TEXT_GAP), 0.5, 0)
		made.Parent = box
		icon = made
	end

	local clear = Instance.new("ImageButton")
	clear.Name = "ClearButton"
	clear.BackgroundTransparency = 1
	clear.Image = KitLook.CLOSE_IMAGE
	clear.ImageColor3 = CLEAR_COLOR
	clear.Size = UDim2.fromOffset(CLEAR_SIZE, CLEAR_SIZE)
	clear.AnchorPoint = Vector2.new(1, 0.5)
	clear.Position = UDim2.new(1, CLEAR_SIZE + TEXT_GAP, 0.5, 0)
	clear.ZIndex = box.ZIndex + 2
	clear.Visible = false
	clear.Parent = box

	local iconImage = icon :: ImageLabel
	local function paint()
		local hasText = box.Text ~= ""
		iconImage.ImageColor3 = if hasText or box:IsFocused() then KitLook.COLOR.white else MUTED
		clear.Visible = hasText
	end
	table.insert(connections, box:GetPropertyChangedSignal("Text"):Connect(paint))
	table.insert(connections, box.Focused:Connect(paint))
	table.insert(connections, box.FocusLost:Connect(paint))
	table.insert(connections, clear.Activated:Connect(function()
		box.Text = ""
	end))
	paint()
end

function DancePanelV3Look.apply(refs: any): Look?
	if not DancePanelV3Look.isApplicable(refs) then
		return nil
	end
	local connections: { RBXScriptConnection } = {}
	local wrapper: GuiObject = refs.mainContentWrapper
	local list: GuiObject = refs.mainContent
	local search: TextBox = refs.searchBox
	local bar: GuiObject = refs.speedWrapper

	setRadius(wrapper, WRAPPER_RADIUS)
	bar.Size = UDim2.new(bar.Size.X.Scale, bar.Size.X.Offset, 0, BAR_HEIGHT)

	-- The list keeps its top edge and gives up the label row + the taller bar.
	local searchHeight = search.Size.Y.Offset
	list.AnchorPoint = Vector2.new(0, 0)
	list.Position = UDim2.new(list.Position.X.Scale, list.Position.X.Offset, 0, searchHeight + LIST_TOP_GAP)
	list.Size = UDim2.new(
		list.Size.X.Scale,
		list.Size.X.Offset,
		1,
		-(searchHeight + LIST_TOP_GAP + LIST_BOTTOM_GAP + LABEL_HEIGHT + LABEL_GAP + BAR_HEIGHT)
	)

	local value = buildSpeedRow(wrapper, bar)
	polishSearch(search, connections)

	return {
		setSpeedText = function(text: string)
			value.Text = text
		end,
		connections = connections,
	}
end

-- Phones (owner-approved mock 2026-10-09): the same v3 panel, wider and shorter, with the segmented
-- speed bar standing on the right of the dance list and no Speed row (the custom speed field in the
-- bottom row reads the value). Marks the slider vertical for the binder. nil on desktop/tablet.
function DancePanelV3Look.applyPhone(refs: any, syncCfg: any): Look?
	if not (DancePanelV3Look.isApplicable(refs) and PhoneLayout.isPhoneLayout()) then
		return nil
	end
	local connections: { RBXScriptConnection } = {}
	local root: GuiObject = refs.panelRoot
	local wrapper: GuiObject = refs.mainContentWrapper
	local list: GuiObject = refs.mainContent
	local search: TextBox = refs.searchBox
	local bar: GuiObject = refs.speedWrapper
	local fill: GuiObject = refs.speedFill

	root.Size = UDim2.new(0, syncCfg.DANCE_PANEL_V3_WIDTH_MOBILE, root.Size.Y.Scale, root.Size.Y.Offset)
	wrapper.Size = UDim2.new(wrapper.Size.X.Scale, wrapper.Size.X.Offset, 0, syncCfg.DANCE_PANEL_V3_CONTENT_HEIGHT_MOBILE)
	setRadius(wrapper, WRAPPER_RADIUS)
	search.Size = UDim2.new(1, 0, 0, search.Size.Y.Offset)

	local top = search.Size.Y.Offset + LIST_TOP_GAP
	list.AnchorPoint = Vector2.new(0, 0)
	list.Position = UDim2.new(0, 0, 0, top)
	list.Size = UDim2.new(1, -(PHONE_BAR_WIDTH + PHONE_BAR_GAP), 1, -(top + LIST_BOTTOM_GAP))
	bar.AnchorPoint = Vector2.new(1, 0)
	bar.Position = UDim2.new(1, 0, 0, top)
	bar.Size = UDim2.new(0, PHONE_BAR_WIDTH, 1, -(top + LIST_BOTTOM_GAP))
	-- The fill grows up from the bar's bottom; the knob rides its top edge.
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	local knob = fill:FindFirstChild("DraggableIcon")
	if knob and knob:IsA("GuiObject") then
		knob.AnchorPoint = Vector2.new(0.5, 0.5)
		knob.Position = UDim2.fromScale(0.5, 0)
	end
	local row = wrapper:FindFirstChild("SpeedLabel")
	if row and row:IsA("GuiObject") then
		row.Visible = false
	end
	refs.speedSliderVertical = true
	refs.v3PhoneLayout = true

	polishSearch(search, connections)
	return {
		setSpeedText = function(_text: string) end,
		connections = connections,
	}
end

-- Phones: the panel's top edge sits `DANCE_PANEL_V3_TOP_MOBILE` screen px down, right of the dance
-- button. The panel is centre-anchored on Y (its open/close zoom comes from the centre), so the
-- centre is placed from its design height at the phone scale. Returns the open position.
function DancePanelV3Look.phonePosition(root: GuiObject, syncCfg: any): UDim2?
	local scale = root:FindFirstChildWhichIsA("UIScale")
	local current = if scale then scale.Scale else 1
	local height = root.AbsoluteSize.Y
	if height <= 0 or current <= 0 then
		return nil
	end
	local design = height / current
	local screenGui = root:FindFirstAncestorWhichIsA("ScreenGui")
	local inset = 0
	if screenGui and not screenGui.IgnoreGuiInset then
		inset = game:GetService("GuiService"):GetGuiInset().Y
	end
	local centre = syncCfg.DANCE_PANEL_V3_TOP_MOBILE - inset + design * syncCfg.DANCE_PANEL_V3_SCALE_MOBILE / 2
	root.AnchorPoint = Vector2.new(0, 0.5)
	return UDim2.new(0, syncCfg.DANCE_PANEL_V3_X_MOBILE, 0, math.floor(centre + 0.5))
end

return DancePanelV3Look
