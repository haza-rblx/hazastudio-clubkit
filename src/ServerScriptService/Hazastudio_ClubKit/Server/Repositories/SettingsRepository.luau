--!strict

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local SettingsDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.SettingsDomain)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Cache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cache)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local BudgetGate = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetGate)
local CrossServerCache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.CrossServerCache)

local SETTINGS_INVALIDATE_TOPIC = "SettingsInvalidate"

type Result<T> = Types.Result<T>
type SettingsStoredData = Types.SettingsStoredData

local function createSettingsRepository(datastoreKey: string?): any
	local key = datastoreKey or Config.Settings.DATASTORE_KEY
	local store = DataStoreService:GetDataStore(key)
	local log = Logger.new("SettingsRepository")
	local budgetGate = BudgetGate.create({ logger = log, name = "SettingsRepository" })
	local KEY_PREFIX = "settings:"

	CrossServerCache.subscribe(SETTINGS_INVALIDATE_TOPIC, function(userId)
		Cache.invalidate(KEY_PREFIX .. userId)
	end)

	local repo = {}

	function repo:loadStrict(userId: number): Result<SettingsStoredData>
		local cacheKey = KEY_PREFIX .. userId

		if Cache.getNegative(cacheKey) then
			return Result.Err("budget_exhausted")
		end

		local cached = Cache.get(cacheKey)
		if cached then
			return Result.Ok(cached :: SettingsStoredData)
		end

		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
			return Result.withRetry(function()
				return store:GetAsync(tostring(userId))
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)

		if not result.ok then
			log:error("Load failed", { userId = userId, err = result.error })
			if result.error == "budget_exhausted" then
				Cache.setNegative(cacheKey, Config.Budget.NEGATIVE_CACHE_TTL or 10)
			end
			return Result.Err(result.error)
		end

		local data = SettingsDomain.sanitizeStored(result.value)
		Cache.set(cacheKey, data, Config.DataStore.CACHE_TTL)
		return Result.Ok(data)
	end

	function repo:load(userId: number): Result<SettingsStoredData>
		return self:loadStrict(userId)
	end

	function repo:update(
		userId: number,
		mutator: (current: SettingsStoredData) -> SettingsStoredData
	): Result<SettingsStoredData>
		local updated: SettingsStoredData? = nil
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return Result.withRetry(function()
				return store:UpdateAsync(tostring(userId), function(current)
					local data = SettingsDomain.sanitizeStored(current)
					local nextData = SettingsDomain.sanitizeStored(mutator(data))
					updated = nextData
					return nextData
				end)
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)

		if not result.ok then
			log:error("Update failed", { userId = userId, err = result.error })
			return Result.Err(result.error)
		end

		local nextData = updated or SettingsDomain.defaultStoredData()
		Cache.set(KEY_PREFIX .. userId, nextData, Config.DataStore.CACHE_TTL)
		CrossServerCache.publish(SETTINGS_INVALIDATE_TOPIC, userId)
		return Result.Ok(nextData)
	end

	function repo:save(userId: number, data: SettingsStoredData): Result<nil>
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return Result.withRetry(function(): boolean
				store:UpdateAsync(tostring(userId), function(_current)
					return SettingsDomain.sanitizeStored(data)
				end)
				return true
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)

		if result.ok then
			Cache.set(KEY_PREFIX .. userId, SettingsDomain.sanitizeStored(data), Config.DataStore.CACHE_TTL)
			CrossServerCache.publish(SETTINGS_INVALIDATE_TOPIC, userId)
			return Result.Ok(nil)
		end

		log:error("Save failed", { userId = userId, err = result.error })
		return Result.Err(result.error)
	end

	function repo:invalidateCache(userId: number)
		Cache.invalidate(KEY_PREFIX .. userId)
	end

	return repo
end

return createSettingsRepository()
