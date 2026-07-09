--!strict
-- Server/Repositories/OverheadRepository.lua
-- Diubah dari singleton menjadi factory function untuk konsistensi
-- dengan pola DI di seluruh project (CORE.md). Singleton lama dibiarkan
-- sebagai default export via createOverheadRepository() agar Main.server.lua
-- cukup panggil require sekali tanpa perubahan besar.
-- HANYA boleh diakses dari Service layer.
-- Zero business logic di sini.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Gunakan ReplicatedStorage local variable, bukan game.ReplicatedStorage
local Config         = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types          = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local ResultUtil     = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Cache          = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cache)
local Logger         = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local BudgetGate     = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetGate)
local CrossServerCache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.CrossServerCache)

local OVERHEAD_INVALIDATE_TOPIC = "OverheadInvalidate"
type Result<T> = Types.Result<T>
type OverheadStoredData = Types.OverheadStoredData
type IOverheadRepository = Types.IOverheadRepository
-- Factory function - memungkinkan injeksi DataStore key untuk testability
local function createOverheadRepository(datastoreKey: string?): IOverheadRepository
	local key   = datastoreKey or Config.DataStore.OVERHEAD_KEY
	local log   = Logger.new("OverheadRepository")
	local Store = DataStoreService:GetDataStore(key)
	local KEY_PREFIX = "overhead:"
	local budgetGate = BudgetGate.create({ logger = log, name = "OverheadRepository" })
	local repo = {} :: IOverheadRepository

	-- Subscribe untuk cache invalidation lintas server.
	-- Saat server lain nulis perubahan ke userId X, kita evict cache lokal
	-- supaya read berikutnya hit DataStore (bukan serve data lama 60s).
	-- Idempotent kalau dipanggil lebih dari sekali (cuma 1 subscription yang aktif).
	CrossServerCache.subscribe(OVERHEAD_INVALIDATE_TOPIC, function(userId)
		Cache.invalidate(KEY_PREFIX .. userId)
		log:debug("Cross-server cache invalidated", { userId = userId })
	end)

	-- Helper internal: panggil ini setiap kali write sukses ke DataStore
	-- agar server lain tahu cache mereka stale.
	local function publishInvalidation(userId: number)
		CrossServerCache.publish(OVERHEAD_INVALIDATE_TOPIC, userId)
	end
	-- ============================================================
	-- LOAD
	-- ============================================================
	function repo:loadStrict(userId: number): Result<OverheadStoredData>
		local cacheKey = KEY_PREFIX .. userId
		if Cache.getNegative(cacheKey) then
			return ResultUtil.Err("budget_exhausted")
		end
		local cached   = Cache.get(cacheKey)
		if cached then
			return ResultUtil.Ok(cached :: OverheadStoredData)
		end
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
			return ResultUtil.withRetry(function()
				return Store:GetAsync(tostring(userId))
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)
		if not result.ok then
			log:error("Load gagal", { userId = userId, err = result.error })
			if result.error == "budget_exhausted" then
				Cache.setNegative(cacheKey, Config.Budget.NEGATIVE_CACHE_TTL or 10)
			end
			return ResultUtil.Err(result.error)
		end
		local raw  = result.value
		local data = raw and OverheadDomain.sanitize(raw) or OverheadDomain.defaultStoredData()
		Cache.set(cacheKey, data, Config.DataStore.CACHE_TTL)
		log:debug("Load OK", { userId = userId })
		return ResultUtil.Ok(data)
	end
	-- load() tidak lagi silent fallback ke default data.
	-- Caller yang decide policy fallback - repository hanya report error.
	-- Kalau loadStrict gagal, return Err agar caller tahu data asli tidak bisa dibaca.
	function repo:load(userId: number): Result<OverheadStoredData>
		return self:loadStrict(userId)
	end
	-- ============================================================
	-- UPDATE (atomic merge on latest server state)
	-- ============================================================
	function repo:update(
		userId: number,
		mutator: (current: OverheadStoredData) -> OverheadStoredData
	): Result<OverheadStoredData>
		local updatedData: OverheadStoredData? = nil
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return ResultUtil.withRetry(function()
				return Store:UpdateAsync(tostring(userId), function(oldData: any): any
					local current = oldData and OverheadDomain.sanitize(oldData) or OverheadDomain.defaultStoredData()
					local nextData = mutator(current)
					updatedData = OverheadDomain.sanitize(nextData)
					return updatedData
				end)
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)
		if not result.ok then
			log:error("Update gagal", { userId = userId, err = result.error })
			return ResultUtil.Err(result.error)
		end
		local finalData = updatedData
		if not finalData then
			log:error("Update gagal: updatedData nil", { userId = userId })
			return ResultUtil.Err("Update failed: no data produced")
		end
		Cache.set(KEY_PREFIX .. userId, finalData, Config.DataStore.CACHE_TTL)
		publishInvalidation(userId)
		log:debug("Update OK", { userId = userId })
		return ResultUtil.Ok(finalData)
	end
	-- ============================================================
	-- SAVE
	-- ============================================================
	function repo:save(userId: number, data: OverheadStoredData): Result<nil>
		local versionConflict = false
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return ResultUtil.withRetry(function(): boolean
				versionConflict = false
				Store:UpdateAsync(tostring(userId), function(oldData: any): any
					local base = oldData or {}
					if base._version and data._version and base._version > data._version then
						log:warn("UpdateAsync conflict: server version newer, aborting write", {
							userId = userId,
							serverV = base._version,
							localV = data._version,
						})
						versionConflict = true
						return nil -- abort UpdateAsync
					end
					return data
				end)
				return true
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)
		if versionConflict then
			Cache.invalidate(KEY_PREFIX .. userId)
			return ResultUtil.Err("version_conflict")
		end
		if result.ok then
			Cache.set(KEY_PREFIX .. userId, data, Config.DataStore.CACHE_TTL)
			publishInvalidation(userId)
			log:debug("Save OK", { userId = userId })
			return ResultUtil.Ok(nil)
		else
			log:error("Save gagal", { userId = userId, err = result.error })
			return ResultUtil.Err(result.error)
		end
	end

	-- ============================================================
	-- INVALIDATE CACHE
	-- ============================================================
	function repo:invalidateCache(userId: number)
		Cache.invalidate(KEY_PREFIX .. userId)
	end
	return repo
end
-- Default instance - Main.server.lua tetap cukup panggil require()
-- dan langsung dapat repo yang sudah dikonfigurasi dengan key production.
return createOverheadRepository()
