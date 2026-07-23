--!strict

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local SettingsDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.SettingsDomain)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Cache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cache)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local BudgetGate = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetGate)
local CrossServerCache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.CrossServerCache)
local PlayerSessionStore = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.PlayerSessionStore)

local SETTINGS_INVALIDATE_TOPIC = "SettingsInvalidate"
local SESSION_NS = "settings"

type Result<T> = Types.Result<T>
type SettingsStoredData = Types.SettingsStoredData

local function fingerprint(data: any): string
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(data)
	end)
	if ok and type(encoded) == "string" then
		return encoded
	end
	return tostring(data)
end

local function createSettingsRepository(datastoreKey: string?): any
	local key = datastoreKey or Config.Settings.DATASTORE_KEY
	local store = DataStoreService:GetDataStore(key)
	local log = Logger.new("SettingsRepository")
	local budgetGate = BudgetGate.create({ logger = log, name = "SettingsRepository" })
	local KEY_PREFIX = "settings:"

	local function mutexFor(userId: number): string
		return key .. "::" .. tostring(userId)
	end

	CrossServerCache.subscribe(SETTINGS_INVALIDATE_TOPIC, function(userId)
		Cache.invalidate(KEY_PREFIX .. userId)
		PlayerSessionStore.clear(SESSION_NS, userId)
	end)

	local function durableWrite(userId: number, data: SettingsStoredData): Result<nil>
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return Result.withRetry(function(): boolean
				store:UpdateAsync(tostring(userId), function(_current)
					return SettingsDomain.sanitizeStored(data)
				end)
				return true
			end, Config.DataStore.RETRY_ATTEMPTS)
		end, mutexFor(userId))

		if result.ok then
			Cache.set(KEY_PREFIX .. userId, SettingsDomain.sanitizeStored(data), Config.DataStore.CACHE_TTL)
			PlayerSessionStore.markClean(SESSION_NS, userId, SettingsDomain.sanitizeStored(data))
			CrossServerCache.publish(SETTINGS_INVALIDATE_TOPIC, userId)
			return Result.Ok(nil)
		end

		return Result.Err(result.error or "save_failed")
	end

	PlayerSessionStore.registerFlush(SESSION_NS, function(userId: number, data: any)
		return durableWrite(userId, data :: SettingsStoredData)
	end)

	local repo = {}

	function repo:loadStrict(userId: number): Result<SettingsStoredData>
		local sessionData = PlayerSessionStore.get(SESSION_NS, userId)
		if sessionData ~= nil then
			return Result.Ok(sessionData :: SettingsStoredData)
		end

		local cacheKey = KEY_PREFIX .. userId

		if Cache.getNegative(cacheKey) then
			return Result.Err("budget_low")
		end

		local cached = Cache.get(cacheKey)
		if cached then
			local data = cached :: SettingsStoredData
			PlayerSessionStore.hydrate(SESSION_NS, userId, data)
			return Result.Ok(data)
		end

		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
			return Result.withRetry(function()
				return store:GetAsync(tostring(userId))
			end, Config.DataStore.JOIN_READ_RETRY_ATTEMPTS or 1)
		end, mutexFor(userId))

		if not result.ok then
			log:error("Load failed", { userId = userId, err = result.error })
			if result.error == "budget_low" or result.error == "budget_exhausted" then
				Cache.setNegative(cacheKey, Config.Budget.NEGATIVE_CACHE_TTL or 10)
			end
			return Result.Err(result.error)
		end

		local data = SettingsDomain.sanitizeStored(result.value)
		Cache.set(cacheKey, data, Config.DataStore.CACHE_TTL)
		PlayerSessionStore.hydrate(SESSION_NS, userId, data)
		return Result.Ok(data)
	end

	function repo:load(userId: number): Result<SettingsStoredData>
		return self:loadStrict(userId)
	end

	function repo:update(
		userId: number,
		mutator: (current: SettingsStoredData) -> SettingsStoredData
	): Result<SettingsStoredData>
		-- SettingsService already write-behinds; repo still skips no-op durable writes.
		local loaded = self:loadStrict(userId)
		if not loaded.ok then
			return loaded
		end
		local current = loaded.value
		local nextData = SettingsDomain.sanitizeStored(mutator(current))
		if fingerprint(nextData) == fingerprint(current) then
			return Result.Ok(current)
		end

		local writeResult = durableWrite(userId, nextData)
		if not writeResult.ok then
			log:error("Update failed", { userId = userId, err = writeResult.error })
			return Result.Err(writeResult.error)
		end
		return Result.Ok(nextData)
	end

	function repo:save(userId: number, data: SettingsStoredData): Result<nil>
		local sanitized = SettingsDomain.sanitizeStored(data)
		local cached = Cache.get(KEY_PREFIX .. userId) or PlayerSessionStore.get(SESSION_NS, userId)
		if cached and fingerprint(sanitized) == fingerprint(cached) then
			PlayerSessionStore.markClean(SESSION_NS, userId, sanitized)
			return Result.Ok(nil)
		end
		local result = durableWrite(userId, sanitized)
		if not result.ok then
			log:error("Save failed", { userId = userId, err = result.error })
		end
		return result
	end

	function repo:invalidateCache(userId: number)
		Cache.invalidate(KEY_PREFIX .. userId)
		PlayerSessionStore.clear(SESSION_NS, userId)
	end

	return repo
end

return createSettingsRepository()
