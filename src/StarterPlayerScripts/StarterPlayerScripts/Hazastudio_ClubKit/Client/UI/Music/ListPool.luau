--!strict
-- PATH: StarterPlayerScripts/Client/UI/Music/ListPool.luau
-- Virtual list over a UIListLayout: only rows inside the scroll window (plus a buffer) exist as
-- instances; two spacer frames stand in for the rest. Rows are pooled and rebound only when the
-- item in their slot changes. Redraws are coalesced to one per frame.

local ListPool = {}
ListPool.__index = ListPool

local TOP_ORDER = -1
local BOTTOM_ORDER = 2 ^ 30

export type Options = {
	scroll: ScrollingFrame,
	container: GuiObject,
	template: GuiObject,
	createRow: (GuiObject) -> any,
	bindRow: (any, any, number) -> (),
	keyOf: (any) -> string,
	buffer: number?,
	maxRows: number?,
}

local function makeSpacer(parent: Instance, name: string, order: number): Frame
	local spacer = Instance.new("Frame")
	spacer.Name = name
	spacer.BackgroundTransparency = 1
	spacer.BorderSizePixel = 0
	spacer.Size = UDim2.new(1, 0, 0, 0)
	spacer.LayoutOrder = order
	spacer.Visible = false
	spacer.Parent = parent
	return spacer
end

local function setSpacer(spacer: Frame, height: number)
	local rounded = math.max(0, math.floor(height + 0.5))
	if spacer.Size.Y.Offset ~= rounded then
		spacer.Size = UDim2.new(1, 0, 0, rounded)
	end
	local visible = rounded > 0
	if spacer.Visible ~= visible then
		spacer.Visible = visible
	end
end

function ListPool.new(opts: Options)
	local self = setmetatable({}, ListPool) :: any
	self._opts = opts
	self._buffer = math.max(0, opts.buffer or 6)
	self._maxRows = math.max(1, opts.maxRows or 60)
	local layout = opts.container:FindFirstChildWhichIsA("UIListLayout")
	self._padding = if layout then math.max(0, layout.Padding.Offset) else 0
	self._top = makeSpacer(opts.container, "ListPoolTop", TOP_ORDER)
	self._bottom = makeSpacer(opts.container, "ListPoolBottom", BOTTOM_ORDER)
	self._items = {} :: { any }
	self._rendered = {} :: { [number]: any }
	self._free = {} :: { any }
	self._all = {} :: { any }
	self._scheduled = false
	self._connections = {
		opts.scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			self:_schedule()
		end),
		opts.scroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function()
			self:_schedule()
		end),
	} :: { RBXScriptConnection }
	return self
end

function ListPool:_schedule()
	if self._scheduled then
		return
	end
	self._scheduled = true
	task.defer(function()
		self._scheduled = false
		if self._destroyed then
			return
		end
		self:_redraw()
	end)
end

function ListPool:_newRow(): any
	local instance = self._opts.template:Clone()
	local row = self._opts.createRow(instance)
	row.instance = instance
	row.itemKey = nil
	instance.Visible = false
	instance.Parent = self._opts.container
	table.insert(self._all, row)
	return row
end

function ListPool:_redraw()
	local opts: Options = self._opts
	local total = #self._items
	local stride = math.max(1, opts.template.Size.Y.Offset + self._padding)
	local viewportRows = math.max(1, math.ceil(opts.scroll.AbsoluteWindowSize.Y / stride))
	local renderRows = math.min(total, self._maxRows, viewportRows + self._buffer * 2)
	local firstVisible = math.floor(math.max(0, opts.scroll.CanvasPosition.Y) / stride) + 1
	local startIndex = math.clamp(firstVisible - self._buffer, 1, math.max(1, total - renderRows + 1))
	local endIndex = if total == 0 then 0 else math.min(total, startIndex + renderRows - 1)

	for index, row in pairs(self._rendered) do
		if index < startIndex or index > endIndex then
			row.itemKey = nil
			row.instance.Visible = false
			table.insert(self._free, row)
			self._rendered[index] = nil
		end
	end

	for index = startIndex, endIndex do
		local item = self._items[index]
		local key = opts.keyOf(item)
		local row = self._rendered[index]
		if not row then
			row = table.remove(self._free) or self:_newRow()
			self._rendered[index] = row
		end
		if row.itemKey ~= key then
			row.itemKey = key
			opts.bindRow(row, item, index)
		end
		if row.instance.LayoutOrder ~= index then
			row.instance.LayoutOrder = index
		end
		if not row.instance.Visible then
			row.instance.Visible = true
		end
	end

	-- Hidden children are skipped by the layout, so a spacer only costs padding when it shows.
	local above = startIndex - 1
	local below = if total == 0 then 0 else total - endIndex
	setSpacer(self._top, if above > 0 then above * stride - self._padding else 0)
	setSpacer(self._bottom, if below > 0 then below * stride - self._padding else 0)
end

function ListPool:setItems(items: { any }, resetScroll: boolean?)
	self._items = items
	if resetScroll and self._opts.scroll.CanvasPosition.Y ~= 0 then
		self._opts.scroll.CanvasPosition = Vector2.zero
	end
	self:_redraw()
end

function ListPool:forEachRendered(callback: (any) -> ())
	for _, row in pairs(self._rendered) do
		callback(row)
	end
end

function ListPool:destroy()
	self._destroyed = true
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	for _, row in ipairs(self._all) do
		row.instance:Destroy()
	end
	self._top:Destroy()
	self._bottom:Destroy()
	table.clear(self._all)
	table.clear(self._rendered)
	table.clear(self._free)
end

return ListPool
