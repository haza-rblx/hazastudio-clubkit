--!strict
-- Shared/Utils/Cache.lua
-- TTL-based in-memory cache.
--
-- Two surfaces:
--   1. Module-level singleton (Cache.set/get/invalidate/invalidatePrefix/
--      setNegative/getNegative/destroy): backward-compatible API used across
--      the codebase. Backed by a lazily-created internal instance.
--   2. Cache.new(): factory for callers that want their own bounded store +
--      cancellable cleanup thread (recommended for new code).
--
-- The singleton's cleanup thread is cancellable via Cache.destroy(), which
-- Main.server / Main.client call from script.Destroying so a Rojo/Argon
-- hot-reload (which destroys the old script and fires its Destroying) cancels
-- the old thread instead of orphaning it forever along with its `store`.

type Entry = {
	value: any,
	exp: number,
}

local NEGATIVE_MARKER = {}

-- ============================================================
-- Instance: each instance owns its own store + cancellable thread.
-- ============================================================
local CacheInstance = {}
CacheInstance.__index = CacheInstance

export type CacheInstance = {
	set: (self: CacheInstance, key: string, value: any, ttl: number) -> (),
	get: (self: CacheInstance, key: string) -> any?,
	invalidate: (self: CacheInstance, key: string) -> (),
	invalidatePrefix: (self: CacheInstance, prefix: string) -> (),
	setNegative: (self: CacheInstance, key: string, ttl: number) -> (),
	getNegative: (self: CacheInstance, key: string) -> boolean,
	destroy: (self: CacheInstance) -> (),
}

function CacheInstance.new(): CacheInstance
	local self = setmetatable({
		_store = {} :: { [string]: Entry },
		_cleanupThread = nil :: thread?,
		_destroyed = false,
	}, CacheInstance) :: any
	return self :: CacheInstance
end

function CacheInstance:set(key: string, value: any, ttl: number)
	if self._destroyed then
		return
	end
	self._store[key] = { value = value, exp = os.time() + ttl }
	self:_ensureCleanup()
end

function CacheInstance:get(key: string): any?
	local e = self._store[key]
	if not e then
		return nil
	end
	if os.time() > e.exp then
		self._store[key] = nil
		return nil
	end
	-- Negative markers are only visible via getNegative — never treat as a value hit.
	if e.value == NEGATIVE_MARKER then
		return nil
	end
	return e.value
end

function CacheInstance:invalidate(key: string)
	self._store[key] = nil
end

function CacheInstance:invalidatePrefix(prefix: string)
	for k in pairs(self._store) do
		if k:sub(1, #prefix) == prefix then
			self._store[k] = nil
		end
	end
end

-- Negative cache: short-lived marker used to avoid hammering DataStore (or
-- other failing dependencies) when the underlying system reports budget
-- exhaustion. Callers check getNegative first and skip the expensive call.
function CacheInstance:setNegative(key: string, ttl: number)
	if self._destroyed then
		return
	end
	self._store[key] = { value = NEGATIVE_MARKER, exp = os.time() + ttl }
	self:_ensureCleanup()
end

function CacheInstance:getNegative(key: string): boolean
	local e = self._store[key]
	if not e then
		return false
	end
	if os.time() > e.exp then
		self._store[key] = nil
		return false
	end
	return e.value == NEGATIVE_MARKER
end

function CacheInstance:_ensureCleanup()
	if self._cleanupThread or self._destroyed then
		return
	end
	self._cleanupThread = task.spawn(function()
		-- Auto-cleanup setiap 60 detik. Loop berhenti ketika _destroyed di-flip
		-- oleh destroy() (dipanggil dari script.Destroying saat teardown/reload).
		while not self._destroyed do
			task.wait(60)
			if self._destroyed then
				break
			end
			local now = os.time()
			for k, e in pairs(self._store) do
				if now > e.exp then
					self._store[k] = nil
				end
			end
		end
	end)
end

function CacheInstance:destroy()
	self._destroyed = true
	if self._cleanupThread then
		task.cancel(self._cleanupThread)
		self._cleanupThread = nil
	end
	-- Drop references so GC can reclaim even if a caller still holds the
	-- instance. Subsequent set/get are no-ops / nils.
	self._store = {}
end

-- ============================================================
-- Module-level singleton (backward-compatible API).
-- Delegates to a lazily-created internal instance so the cleanup thread can
-- be cancelled via Cache.destroy() on teardown.
-- ============================================================
local Cache = {}
local _singleton: CacheInstance? = nil

local function singleton(): CacheInstance
	if not _singleton then
		_singleton = CacheInstance.new()
	end
	return _singleton :: CacheInstance
end

function Cache.set(key: string, value: any, ttl: number)
	singleton():set(key, value, ttl)
end

function Cache.get(key: string): any?
	return singleton():get(key)
end

function Cache.invalidate(key: string)
	singleton():invalidate(key)
end

function Cache.invalidatePrefix(prefix: string)
	singleton():invalidatePrefix(prefix)
end

function Cache.setNegative(key: string, ttl: number)
	singleton():setNegative(key, ttl)
end

function Cache.getNegative(key: string): boolean
	return singleton():getNegative(key)
end

-- Hentikan cleanup loop + clear store. Dipanggil dari script.Destroying saat
-- teardown/hot-reload agar thread lama tidak orphan dan store lama tidak leak.
function Cache.destroy()
	if _singleton then
		_singleton:destroy()
		_singleton = nil
	end
end

-- Expose the factory for new callers that want an isolated, owned cache.
Cache.new = CacheInstance.new

return Cache
