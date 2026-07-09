--!strict
-- Shared/Utils/MemoryStoreCache.luau
-- Thin wrapper di atas MemoryStoreService untuk cross-server cache layer.
--
-- Use case utama: leaderboard cache yang dishare antar semua server. Tanpa
-- layer ini, tiap server akan hit DataStore GetSortedAsync independent =>
-- N×servers×1 per-TTL = banyak DS calls. Dengan MemoryStore, hanya server
-- pertama yang miss cache yang hit DS; sisanya dapat dari shared MemoryStore
-- (yang lebih murah per-call).
--
-- MemoryStore limits (Roblox docs):
--   - Min TTL 30s, max ~7 days
--   - 4 KB per key value
--   - Per-experience read/write quota (lebih besar dari DataStore GetSortedAsync
--     experience limit, tapi lebih kecil dari DataStore per-server quota).
--   - MemoryStore bisa throw throttle/timeout — di-pcall dan fall through ke
--     return nil/false supaya caller selalu bisa fallback ke DataStore.
--
-- Config:
--   Config.Leaderboards.MEMORY_STORE_CACHE_ENABLED — toggle global
--   Config.Leaderboards.MEMORY_STORE_LEADERBOARD_TTL — TTL default (detik)
--   Config.Leaderboards.MEMORY_STORE_STORE_NAME — nama store (default "ClubKitLeaderboardCache")

local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local MemoryStoreCache = {}

-- Per-name store handle cache. GetDataStore returns the same handle per name,
-- tapi kita cache supaya tidak ada re-resolve setiap call.
local _stores: { [string]: any } = {}

-- Lazy config read untuk hindari circular-import. Config mungkin belum loaded
-- saat module pertama di-require di server lain.
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
		-- MemoryStore bisa unavailable di Studio tanpa API Services.
		-- Caller dapat nil dan harus fallback ke DS path.
		return nil
	end
	_stores[name] = store
	return store
end

--- Get cached value. Return nil kalau miss, disabled, atau error.
--- Caller SELALU harus treat nil sebagai "no cache" dan fallback ke source-of-truth.
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

--- Set value with TTL (detik). Default TTL dari Config.Leaderboards.MEMORY_STORE_LEADERBOARD_TTL
--- (60s) — cukup pendek untuk self-heal kalau invalidation terlewat.
--- Return true kalau berhasil, false kalau disabled / error / TTL invalid.
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

--- Invalidate (delete) a key. Dipanggil dari write path supaya next read
--- fallback ke DataStore (dan re-populate MemoryStore dengan fresh data).
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
