--!strict
-- Client/Utils/ObjectPool.lua
-- Generic object pool for UI elements to prevent GC pressure

local ObjectPool = {}
ObjectPool.__index = ObjectPool

export type ObjectPool<T> = {
	_available: { T },
	_inUse: { [T]: boolean },
	_factory: () -> T,
	_reset: (T) -> (),
	_maxSize: number,
	acquire: (self: ObjectPool<T>) -> T,
	release: (self: ObjectPool<T>, object: T) -> (),
	releaseAll: (self: ObjectPool<T>) -> (),
	destroy: (self: ObjectPool<T>) -> (),
}

function ObjectPool.new<T>(
	factory: () -> T,
	reset: (T) -> (),
	maxSize: number
): ObjectPool<T>
	local self = setmetatable({}, ObjectPool)
	self._available = {}
	self._inUse = {}
	self._factory = factory
	self._reset = reset
	self._maxSize = maxSize
	return self :: any
end

function ObjectPool:acquire()
	local object
	if #self._available > 0 then
		object = table.remove(self._available)
	else
		object = self._factory()
	end
	self._inUse[object] = true
	return object
end

function ObjectPool:release(object)
	if not self._inUse[object] then
		return
	end
	
	self._inUse[object] = nil
	self._reset(object)
	
	if #self._available < self._maxSize then
		table.insert(self._available, object)
	else
		-- Pool is full, destroy the object
		if typeof(object) == "Instance" then
			pcall(function()
				(object :: any):Destroy()
			end)
		end
	end
end

function ObjectPool:releaseAll()
	for object in pairs(self._inUse) do
		self:release(object)
	end
end

function ObjectPool:destroy()
	-- Destroy all objects in pool
	for _, object in ipairs(self._available) do
		if typeof(object) == "Instance" then
			pcall(function()
				(object :: any):Destroy()
			end)
		end
	end
	
	for object in pairs(self._inUse) do
		if typeof(object) == "Instance" then
			pcall(function()
				(object :: any):Destroy()
			end)
		end
	end
	
	table.clear(self._available)
	table.clear(self._inUse)
end

return ObjectPool
