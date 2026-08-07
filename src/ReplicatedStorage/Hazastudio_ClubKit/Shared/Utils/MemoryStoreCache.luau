--!strict
-- Shared/Utils/MemoryStoreCache.luau
-- Thin wrapper on MemoryStoreService for cross-server cache layer.
--
-- Primary use case: leaderboard cache shared across all servers. Without
-- this layer, each server hits DataStore GetSortedAsync independently =>
-- N×servers×1 per-TTL = many DS calls. With MemoryStore, only the first
-- server to miss cache hits DS; others read from shared MemoryStore
-- (cheaper per call).
--
-- MemoryStore limits (Roblox docs):
--   - Min TTL 30s, max ~7 days
--   - 4 KB per key value
--   - Per-experience read/write quota (higher than DataStore GetSortedAsync
--     experience limit, but lower than DataStore per-server quota).
--   - MemoryStore may throw throttle/timeout — pcall-wrapped and fall through to
--     return nil/false so callers can always fallback to DataStore.
--
-- Config:
--   Config.Leaderboards.MEMORY_STORE_CACHE_ENABLED — global toggle
--   Config.Leaderboards.MEMORY_STORE_LEADERBOARD_TTL — default TTL (seconds)
--   Config.Leaderboards.MEMORY_STORE_STORE_NAME — store name (default "ClubKitLeaderboardCache")

local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local MemoryStoreCache = {}

-- Per-name store handle cache. GetDataStore returns the same handle per name,
-- but we cache it to avoid re-resolving on every call.
local _stores: { [string]: any } = {}

-- Lazy config read to avoid circular import. Config may not be loaded yet
-- when the module is first required on another server.
local _enabledCache: boolean = false
local function isEnabled(): boolean
	if _enabledCache == true then
		return true
	end
	local lb = Config.Leaderboards
	local enabled = type(lb) == "table" and lb.MEMORY_STORE_CACHE_ENABLED == true
	if enabled then
		_enabledCache = true
	end
	return enabled
end

local function getStore(name: string): any?
	if _stores[name] ~= nil then
		return _stores[name]
	end
	local ok, store = pcall(function()
		-- MemoryStoreService does not have GetDataStore; use GetHashMap for
		-- simple key-value cache operations (GetAsync/SetAsync/RemoveAsync).
		return (MemoryStoreService:GetHashMap(name) :: any)
	end)
	if not ok or store == nil then
		-- MemoryStore may be unavailable in Studio without API Services.
		-- Caller may get nil and must fallback to DS path.
		return nil
	end
	_stores[name] = store
	return store
end

--- Get cached value. Return nil if miss, disabled, or error.
--- Caller MUST always treat nil as "no cache" and fallback to source-of-truth.
function MemoryStoreCache.get(storeName: string, key: string): any?
	if not isEnabled() then
		return nil
	end
	local store = getStore(storeName)
	if store == nil then
		return nil
	end
	local ok, value = pcall(function()
		return (store :: any):GetAsync(key)
	end)
	if not ok then
		return nil
	end
	return value
end

--- Set value with TTL (seconds). Default TTL from Config.Leaderboards.MEMORY_STORE_LEADERBOARD_TTL
--- (60s) — short enough for self-heal if invalidation is missed.
--- Return true on success, false if disabled / error / TTL invalid.
function MemoryStoreCache.set(storeName: string, key: string, value: any, ttl: number?): boolean
	if not isEnabled() then
		return false
	end
	local store = getStore(storeName)
	if store == nil then
		return false
	end
	local resolvedTtl = ttl
	if type(resolvedTtl) ~= "number" or resolvedTtl < 30 then
		local lb = Config.Leaderboards
		resolvedTtl = if type(lb) == "table" and type(lb.MEMORY_STORE_LEADERBOARD_TTL) == "number"
			then lb.MEMORY_STORE_LEADERBOARD_TTL
			else 60
	end
	if resolvedTtl < 30 then
		resolvedTtl = 30 -- MemoryStore minimum TTL
	end
	local ok = pcall(function()
		return (store :: any):SetAsync(key, value, resolvedTtl)
	end)
	return ok
end

--- Invalidate (delete) a key. Called from the write path so the next read
--- falls back to DataStore (and re-populates MemoryStore with fresh data).
function MemoryStoreCache.remove(storeName: string, key: string): boolean
	if not isEnabled() then
		return false
	end
	local store = getStore(storeName)
	if store == nil then
		return false
	end
	local ok = pcall(function()
		return (store :: any):RemoveAsync(key)
	end)
	return ok
end

return MemoryStoreCache
