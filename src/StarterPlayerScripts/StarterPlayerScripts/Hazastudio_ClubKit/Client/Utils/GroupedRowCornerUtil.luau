--!strict
-- Applies "grouped list" corner rounding to the visible GuiObject rows of a container
-- laid out by a UIListLayout (e.g. SectionContentWrapper): first visible row gets
-- rounded top corners and small bottom ones, last the reverse, middle rows get the small
-- radius all round, and a lone visible row gets all four corners rounded. Rows sit ROW_GAP
-- apart and the container's own fill moves onto rows that had none, so the gaps read as
-- separate pills (same discipline as the top menu, owner 2026-10-07).
--
-- One UICorner per row, driven by its per-corner radius properties (TopLeftRadius /
-- TopRightRadius / BottomLeftRadius / BottomRightRadius) -- CornerRadius alone can't
-- express this since it rounds all four corners uniformly.

local GroupedRowCornerUtil = {}

local DEFAULT_RADIUS = 18
local INNER_RADIUS = 4
local ROW_GAP = 2
local FILL_ATTRIBUTE = "GroupedRowFill"

local function getOrCreateCorner(row: GuiObject): UICorner
	local corner = row:FindFirstChildOfClass("UICorner")
	if not corner then
		corner = Instance.new("UICorner")
		corner.Name = "UICorner"
		corner.Parent = row
	end
	return corner :: UICorner
end

local function sortedVisibleRows(container: Instance): { GuiObject }
	local layout = container:FindFirstChildOfClass("UIListLayout")
	local sortOrder = if layout then layout.SortOrder else Enum.SortOrder.LayoutOrder

	local rows: { GuiObject } = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible then
			table.insert(rows, child)
		end
	end

	table.sort(rows, function(a, b)
		if sortOrder == Enum.SortOrder.Name then
			return a.Name < b.Name
		end
		if a.LayoutOrder ~= b.LayoutOrder then
			return a.LayoutOrder < b.LayoutOrder
		end
		return a.Name < b.Name
	end)

	return rows
end

-- container: the SectionContentWrapper-style Frame whose visible GuiObject children
-- are the rows to round. radius: pixel radius for the rounded edges (default 18).
function GroupedRowCornerUtil.apply(container: Instance, radius: number?)
	local r = UDim.new(0, radius or DEFAULT_RADIUS)
	local zero = UDim.new(0, INNER_RADIUS)
	local rows = sortedVisibleRows(container)
	local count = #rows

	local layout = container:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.Padding = UDim.new(0, ROW_GAP)
	end
	if container:IsA("GuiObject") then
		-- Remember the card's fill once (its design value if the accent theme already tinted it),
		-- so rows that become visible later still get it after the card went transparent.
		if container.BackgroundTransparency < 1 then
			local design = container:GetAttribute("AccentDesignBackgroundColor3")
			container:SetAttribute(FILL_ATTRIBUTE, if typeof(design) == "Color3" then design else container.BackgroundColor3)
			container.BackgroundTransparency = 1
		end
		local fill = container:GetAttribute(FILL_ATTRIBUTE)
		if typeof(fill) == "Color3" then
			for _, row in ipairs(rows) do
				if row.BackgroundTransparency >= 1 then
					row.BackgroundColor3 = fill
					row.BackgroundTransparency = 0
				end
			end
		end
	end

	for index, row in ipairs(rows) do
		local corner = getOrCreateCorner(row)
		if count == 1 then
			corner.TopLeftRadius = r
			corner.TopRightRadius = r
			corner.BottomLeftRadius = r
			corner.BottomRightRadius = r
		elseif index == 1 then
			corner.TopLeftRadius = r
			corner.TopRightRadius = r
			corner.BottomLeftRadius = zero
			corner.BottomRightRadius = zero
		elseif index == count then
			corner.TopLeftRadius = zero
			corner.TopRightRadius = zero
			corner.BottomLeftRadius = r
			corner.BottomRightRadius = r
		else
			corner.TopLeftRadius = zero
			corner.TopRightRadius = zero
			corner.BottomLeftRadius = zero
			corner.BottomRightRadius = zero
		end
	end
end

return GroupedRowCornerUtil
