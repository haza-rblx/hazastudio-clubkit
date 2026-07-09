--!strict
-- Shared/Utils/Cleaner.lua
--
-- Track teardown items and release them in one call.
--
-- Replaces the ad-hoc `_connections` tables scattered across Services and
-- Controllers. Single API handles RBXScriptConnection, Instance, function
-- callbacks (typical EventBus / Store unsubscribers), and any object that
-- exposes a Disconnect or destroy method.
--
-- Pattern:
--   local cleaner = Cleaner.new()
--   cleaner:add(remote.OnServerEvent:Connect(handler))
--   cleaner:add(eventBus:on("Player:Joined", onJoin))
--   cleaner:add(function() pool:destroy() end)
--   cleaner:add(billboardGui)
--
--   -- on destroy
--   cleaner:clean()

local Cleaner = {}
Cleaner.__index = Cleaner

export type CleanItem =
	RBXScriptConnection
	| Instance
	| (() -> ())
	| { Disconnect: (any) -> () }
	| { destroy: (any) -> () }
	| { Destroy: (any) -> () }

export type Cleaner = {
	add: <T>(self: Cleaner, item: T) -> T,
	addMany: (self: Cleaner, items: { CleanItem }) -> (),
	remove: (self: Cleaner, item: CleanItem) -> boolean,
	clean: (self: Cleaner) -> (),
	size: (self: Cleaner) -> number,
	isClean: (self: Cleaner) -> boolean,
}

local function release(item: any)
	if typeof(item) == "RBXScriptConnection" then
		item:Disconnect()
		return
	end
	if typeof(item) == "Instance" then
		item:Destroy()
		return
	end
	if type(item) == "function" then
		-- Unsubscribe callback. Errors are swallowed so one bad subscriber
		-- does not block the rest of the cleanup.
		pcall(item)
		return
	end
	if type(item) == "table" then
		if type(item.Disconnect) == "function" then
			pcall(item.Disconnect, item)
			return
		end
		if type(item.destroy) == "function" then
			pcall(item.destroy, item)
			return
		end
		if type(item.Destroy) == "function" then
			pcall(item.Destroy, item)
			return
		end
	end
	-- Unknown item type: drop the reference. Silent on purpose; callers
	-- should not pass arbitrary values.
end

--- Construct a new Cleaner.
function Cleaner.new(): Cleaner
	local self = setmetatable({
		_items = {} :: { CleanItem },
	}, Cleaner)
	return (self :: any) :: Cleaner
end

--- Track an item. Returns the item unchanged so callers can chain:
---   local conn = cleaner:add(remote.OnServerEvent:Connect(handler))
function Cleaner:add<T>(item: T): T
	table.insert(self._items, item :: any)
	return item
end

--- Track multiple items in one call.
function Cleaner:addMany(items: { CleanItem })
	for _, item in items do
		table.insert(self._items, item)
	end
end

--- Remove a specific item without releasing it. Returns true if found.
--- Useful when an item is destroyed early and should not be touched twice.
function Cleaner:remove(item: CleanItem): boolean
	for index, candidate in self._items do
		if candidate == item then
			table.remove(self._items, index)
			return true
		end
	end
	return false
end

--- Release every tracked item. Idempotent; safe to call multiple times.
function Cleaner:clean()
	-- Snapshot first: a release callback may itself add to the cleaner during
	-- teardown (rare but possible). Items added during clean() are released on
	-- the next call.
	local snapshot = self._items
	self._items = {}
	for _, item in snapshot do
		release(item)
	end
end

function Cleaner:size(): number
	return #self._items
end

function Cleaner:isClean(): boolean
	return #self._items == 0
end

return Cleaner
