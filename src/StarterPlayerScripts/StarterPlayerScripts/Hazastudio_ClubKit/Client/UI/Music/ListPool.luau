--!strict
-- PATH: StarterPlayerScripts/Client/UI/Music/ListPool.luau
-- Virtual list over a UIListLayout: only rows inside the scroll window (plus a buffer) exist as
-- instances; two spacer frames stand in for the rest. Rows are pooled. When the window moves, a
-- row that already holds an item's key is moved (LayoutOrder) instead of rebound. Redraws run in
-- the same frame as a scroll and are coalesced to one per frame for size changes.

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
	-- A frame above the first row (the Set card). Its height plus the layout gap is kept out of the
	-- index math, so rows start after it. Hidden means it takes no room.
	leading: GuiObject?,
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
	self._instances = {} :: { GuiObject }
	self._scheduled = false
	self._redrawing = false
	self._leading = opts.leading
	self._connections = {
		opts.scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			self:_redraw()
		end),
		opts.scroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function()
			self:_schedule()
		end),
	} :: { RBXScriptConnection }
	local leading = opts.leading
	if leading then
		for _, property in ipairs({ "AbsoluteSize", "Visible" }) do
			table.insert(
				self._connections,
				leading:GetPropertyChangedSignal(property :: any):Connect(function()
					self:_schedule()
				end)
			)
		end
	end
	return self
end

-- Absolute pixels above the first row: the leading frame and the layout gap under it.
function ListPool:_leadingHeight(): number
	local leading = self._leading
	if not leading or not leading.Visible then
		return 0
	end
	return leading.AbsoluteSize.Y + self._padding
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
	-- Parented (hidden) before createRow: UIMotion picks a row's scale target from its live
	-- ancestry, so a row bound while detached would look layout-safe when it is not.
	instance.Visible = false
	instance.Parent = self._opts.container
	table.insert(self._instances, instance)
	local row = self._opts.createRow(instance)
	row.instance = instance
	row.itemKey = nil
	return row
end

-- Measured in absolute pixels: CanvasPosition and the window size are absolute, while spacers and
-- the layout are offset units. The whole list can draw scaled (template Size.Y.Offset 80 drew 76 px),
-- so the index math scales the stride by a ratio read off a spacer. Spacers, not rows: a row under
-- a hover UIScale would make the ratio, and with it the window, jump while the cursor rests on it.
function ListPool:_absoluteStride(offsetStride: number): number
	for _, spacer in ipairs({ self._top, self._bottom }) do
		local offset = spacer.Size.Y.Offset
		local height = spacer.AbsoluteSize.Y
		if spacer.Visible and offset > 0 and height > 0 then
			self._ratio = height / offset
			break
		end
	end
	return math.max(1, offsetStride * (self._ratio or 1))
end

function ListPool:_redraw()
	-- A redraw can re-enter through a CanvasPosition change it causes; run that one afterwards.
	if self._redrawing then
		self:_schedule()
		return
	end
	self._redrawing = true
	local ok, err = pcall(self._redrawNow, self)
	self._redrawing = false
	if not ok then
		error(err, 0)
	end
end

function ListPool:_redrawNow()
	local opts: Options = self._opts
	local items = self._items
	local total = #items
	local offsetStride = math.max(1, opts.template.Size.Y.Offset + self._padding)
	local stride = self:_absoluteStride(offsetStride)
	local viewportRows = math.max(1, math.ceil(opts.scroll.AbsoluteWindowSize.Y / stride))
	local renderRows = math.min(total, self._maxRows, viewportRows + self._buffer * 2)
	local scrolled = math.max(0, opts.scroll.CanvasPosition.Y - self:_leadingHeight())
	local firstVisible = math.floor(scrolled / stride) + 1
	local startIndex = math.clamp(firstVisible - self._buffer, 1, math.max(1, total - renderRows + 1))
	local endIndex = if total == 0 then 0 else math.min(total, startIndex + renderRows - 1)

	-- Pass 1: a row already at its index with the right key stays put.
	local keys = {} :: { [number]: string }
	local assigned = {} :: { [number]: any }
	local claimed = {} :: { [any]: boolean }
	for index = startIndex, endIndex do
		local key = opts.keyOf(items[index])
		keys[index] = key
		local row = self._rendered[index]
		if row and row.itemKey == key then
			assigned[index] = row
			claimed[row] = true
		end
	end

	-- Every other rendered row is a spare, indexed by the key it holds.
	local spare = {} :: { any }
	local byKey = {} :: { [string]: { any } }
	for _, row in pairs(self._rendered) do
		if not claimed[row] then
			table.insert(spare, row)
			if row.itemKey ~= nil then
				local list = byKey[row.itemKey]
				if not list then
					list = {}
					byKey[row.itemKey] = list
				end
				table.insert(list, row)
			end
		end
	end

	-- Pass 2: a spare that holds the needed key moves to the new index; it is not rebound.
	for index = startIndex, endIndex do
		if not assigned[index] then
			local list = byKey[keys[index]]
			local row = if list then table.remove(list) else nil
			if row then
				assigned[index] = row
				claimed[row] = true
			end
		end
	end

	-- Pass 3: the rest take a free row, then a spare, then a new row. Only changed keys rebind.
	local function takeRow(): any
		local row = table.remove(self._free)
		if row then
			return row
		end
		while #spare > 0 do
			local candidate = table.remove(spare)
			if not claimed[candidate] then
				return candidate
			end
		end
		return self:_newRow()
	end

	local nextRendered = {} :: { [number]: any }
	for index = startIndex, endIndex do
		local row = assigned[index]
		if not row then
			row = takeRow()
		end
		claimed[row] = true
		nextRendered[index] = row
		local key = keys[index]
		if row.itemKey ~= key then
			row.itemKey = key
			opts.bindRow(row, items[index], index)
		end
		if row.instance.LayoutOrder ~= index then
			row.instance.LayoutOrder = index
		end
		if not row.instance.Visible then
			row.instance.Visible = true
		end
	end

	-- Unclaimed rows leave the window: hidden and returned to the free list.
	for _, row in ipairs(spare) do
		if not claimed[row] then
			row.itemKey = nil
			row.instance.Visible = false
			table.insert(self._free, row)
		end
	end
	self._rendered = nextRendered

	-- Hidden children are skipped by the layout, so a spacer only costs padding when it shows.
	local above = startIndex - 1
	local below = if total == 0 then 0 else total - endIndex
	setSpacer(self._top, if above > 0 then above * offsetStride - self._padding else 0)
	setSpacer(self._bottom, if below > 0 then below * offsetStride - self._padding else 0)
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
	for _, instance in ipairs(self._instances) do
		instance:Destroy()
	end
	self._top:Destroy()
	self._bottom:Destroy()
	table.clear(self._instances)
	table.clear(self._rendered)
	table.clear(self._free)
end

return ListPool
