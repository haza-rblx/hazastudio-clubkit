--!strict
-- Applies "grouped list" corner rounding to the visible GuiObject rows of a container
-- laid out by a UIListLayout (e.g. SectionContentWrapper): first visible row gets
-- rounded top corners, last gets rounded bottom, middle rows are square, and a lone
-- visible row gets all four corners rounded. Standard grouped-table look.
--
-- One UICorner per row, driven by its per-corner radius properties (TopLeftRadius /
-- TopRightRadius / BottomLeftRadius / BottomRightRadius) -- CornerRadius alone can't
-- express this since it rounds all four corners uniformly.

local GroupedRowCornerUtil = {}

local DEFAULT_RADIUS = 18

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
	local zero = UDim.new(0, 0)
	local rows = sortedVisibleRows(container)
	local count = #rows

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
