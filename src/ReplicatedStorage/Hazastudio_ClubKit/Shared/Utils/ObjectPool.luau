--!strict
-- ReplicatedStorage/Shared/Utils/ObjectPool.lua
-- Generic object pool for recycling instances

-- Import Logger untuk proper logging
local Logger = require(script.Parent.Logger)
local log = Logger.new("ObjectPool")

local ObjectPool = {}
ObjectPool.__index = ObjectPool

export type ObjectPool<T> = {
	acquire: (self: ObjectPool<T>) -> T?,
	release: (self: ObjectPool<T>, object: T) -> (),
	clear: (self: ObjectPool<T>) -> (),
	getSize: (self: ObjectPool<T>) -> number,
}

function ObjectPool.new<T>(createFn: () -> T, resetFn: ((T) -> ())?, maxSize: number?): ObjectPool<T>
	local self = setmetatable({
		_createFn = createFn,
		_resetFn = resetFn,
		_maxSize = maxSize or 10,
		_available = {} :: {T},
		_inUse = {} :: {[T]: boolean},
	}, ObjectPool) :: any

	return self :: ObjectPool<T>
end

function ObjectPool:acquire()
	-- Try to get from available pool
	if #self._available > 0 then
		local object = table.remove(self._available)
		self._inUse[object] = true
		return object
	end
	
	-- Create new if under max size
	local totalSize = #self._available + self:_countInUse()
	if totalSize < self._maxSize then
		local object = self._createFn()
		self._inUse[object] = true
		return object
	end
	
	-- Pool exhausted
	return nil
end

function ObjectPool:release(object)
	if not self._inUse[object] then
		-- Gunakan Logger bukan bare warn()
		log:warn("Trying to release object that's not in use")
		return
	end
	
	self._inUse[object] = nil
	
	-- Reset object if reset function provided
	if self._resetFn then
		self._resetFn(object)
	end
	
	table.insert(self._available, object)
end

function ObjectPool:clear()
	self._available = {}
	self._inUse = {}
end

function ObjectPool:getSize(): number
	return #self._available + self:_countInUse()
end

function ObjectPool:_countInUse(): number
	local count = 0
	for _ in self._inUse do
		count += 1
	end
	return count
end

return ObjectPool
