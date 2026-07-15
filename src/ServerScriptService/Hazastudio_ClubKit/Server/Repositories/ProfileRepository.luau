--!strict
-- ServerScriptService/Server/Repositories/ProfileRepository.lua

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local BudgetGate = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetGate)
local Cache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cache)
local CrossServerCache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.CrossServerCache)

local PROFILE_INVALIDATE_TOPIC = "ProfileInvalidate"

type Result<T> = Types.Result<T>
type ProfileStoredData = Types.ProfileStoredData
type ILogger = Types.ILogger

local ProfileRepository = {}
ProfileRepository.__index = ProfileRepository

local DEFAULT_DATA: ProfileStoredData = {
	bio = nil,
	displayNameOverride = nil,
	relationshipMode = nil,
	statusText = nil,
	lastBioUpdate = nil,
	lastStatusUpdate = nil,
	_version = 1,
}

function ProfileRepository.new(deps: { logger: ILogger })
	local self = setmetatable({}, ProfileRepository)
	self._logger = deps.logger
	self._store = DataStoreService:GetDataStore(Config.AvatarContext.PROFILE_DATASTORE_KEY)
	self._budgetGate = BudgetGate.create({ logger = deps.logger, name = "ProfileRepository" })

	-- Subscribe untuk cache invalidation lintas server.
	-- Idempotent: tiap require ProfileRepository.new akan re-subscribe,
	-- tapi semua callback meng-clear cache lokal yang sama.
	CrossServerCache.subscribe(PROFILE_INVALIDATE_TOPIC, function(userId)
		Cache.invalidate("profile_" .. tostring(userId))
	end)

	-- Cache is a global module, not a class
	return self
end

function ProfileRepository:_key(userId: number): string
	return "profile_" .. tostring(userId)
end

function ProfileRepository:load(userId: number): Result<ProfileStoredData>
	local key = self:_key(userId)

	if Cache.getNegative(key) then
		return Result.Err("budget_exhausted")
	end

	-- Check cache
	local cached = Cache.get(key)
	if cached then
		return Result.Ok(cached)
	end

	-- Budget-gated load with retry. BudgetGate refuses up front if the
	-- per-server quota is too low; the inner Result.withRetry passes through.
	local result = self._budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
		return Result.withRetry(function()
			return self._store:GetAsync(key)
		end, Config.DataStore.JOIN_READ_RETRY_ATTEMPTS or 1)
	end)

	if not result.ok then
		self._logger:warn("ProfileRepository:load failed", { userId = userId, error = result.error })
		if result.error == "budget_exhausted" then
			Cache.setNegative(key, Config.Budget.NEGATIVE_CACHE_TTL or 10)
		end
		return Result.Err("DataStore read failed")
	end

	local profile: ProfileStoredData = result.value or table.clone(DEFAULT_DATA)

	-- Validate version
	if not profile._version then
		profile._version = 1
	end

	Cache.set(key, profile, Config.DataStore.CACHE_TTL)
	return Result.Ok(profile)
end

function ProfileRepository:update(
	userId: number,
	mutator: (current: ProfileStoredData) -> ProfileStoredData
): Result<ProfileStoredData>
	local key = self:_key(userId)

	local savedData: ProfileStoredData? = nil
	local result = self._budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
		return Result.withRetry(function()
			return self._store:UpdateAsync(key, function(current)
				local data: ProfileStoredData = current or table.clone(DEFAULT_DATA)
				local mutated = mutator(data)
				savedData = mutated
				return mutated
			end)
		end, Config.DataStore.RETRY_ATTEMPTS)
	end)

	if not result.ok then
		self._logger:error("ProfileRepository:update failed", { userId = userId, error = result.error })
		return Result.Err("DataStore write failed")
	end

	-- Set cache baru setelah UpdateAsync berhasil, seperti OverheadRepository
	-- Agar next read tidak hit DataStore lagi
	if savedData then
		Cache.set(key, savedData, Config.DataStore.CACHE_TTL)
	end

	-- Broadcast ke server lain agar cache mereka stale di-evict.
	CrossServerCache.publish(PROFILE_INVALIDATE_TOPIC, userId)

	return Result.Ok(savedData :: ProfileStoredData)
end

function ProfileRepository:invalidateCache(userId: number)
	local key = self:_key(userId)
	Cache.invalidate(key)
end

return ProfileRepository
