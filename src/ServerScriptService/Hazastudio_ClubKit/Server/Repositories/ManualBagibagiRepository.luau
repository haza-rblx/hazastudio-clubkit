--!strict
-- Persistent owner manual Bagi-Bagi / IDR adjustments.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local BudgetGate = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetGate)

export type ManualBagibagiRepository = {
	loadAll: (self: ManualBagibagiRepository) -> Result<{ [number]: number }>,
	adjust: (self: ManualBagibagiRepository, userId: number, deltaIdr: number) -> Result<number>,
	remove: (self: ManualBagibagiRepository, userId: number, amountIdr: number?) -> Result<number>,
}

local ManualBagibagiRepository = {}

local DOCUMENT_KEY = "manual_v1"

local function sanitizeMap(raw: any): { [number]: number }
	local map: { [number]: number } = {}
	if type(raw) ~= "table" then
		return map
	end
	for rawUserId, rawAmount in pairs(raw) do
		local userId = tonumber(rawUserId)
		local amount = math.floor(tonumber(rawAmount) or 0)
		if userId and userId > 0 and amount > 0 then
			map[userId] = amount
		end
	end
	return map
end

local function createRepository(deps: { logger: any? }?): ManualBagibagiRepository
	local log = if deps and deps.logger then deps.logger else Logger.new("ManualBagibagiRepository")
	local store = DataStoreService:GetDataStore(Config.Donation.MANUAL_BAGIBAGI_DATASTORE_KEY)
	local budgetGate = BudgetGate.create({ logger = log, name = "ManualBagibagiRepository" })

	local self = {} :: ManualBagibagiRepository

	local function mutate(mutator: (current: { [string]: number }) -> { [string]: number }): Result<{ [number]: number }>
		local saved: { [number]: number }? = nil
		local writeResult = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return Result.withRetry(function()
				store:UpdateAsync(DOCUMENT_KEY, function(current: any)
					local map = if type(current) == "table" then current else {}
					local nextMap = mutator(map)
					saved = sanitizeMap(nextMap)
					return nextMap
				end)
				return nil
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)
		if not writeResult.ok then
			log:warn("Manual Bagibagi write failed", { error = writeResult.error })
			return Result.Err(writeResult.error)
		end
		return Result.Ok(saved or {})
	end

	function self:loadAll(): Result<{ [number]: number }>
		local readResult = budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
			return Result.withRetry(function()
				return store:GetAsync(DOCUMENT_KEY)
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)
		if not readResult.ok then
			return Result.Err(readResult.error)
		end
		return Result.Ok(sanitizeMap(readResult.value))
	end

	function self:adjust(userId: number, deltaIdr: number): Result<number>
		local delta = math.floor(deltaIdr)
		if userId <= 0 or delta == 0 then
			return Result.Err("invalid_adjustment")
		end
		local nextValue = 0
		local result = mutate(function(current)
			local key = tostring(userId)
			nextValue = math.max(0, math.floor(tonumber(current[key]) or 0) + delta)
			if nextValue <= 0 then
				current[key] = nil
			else
				current[key] = nextValue
			end
			return current
		end)
		if not result.ok then
			return Result.Err(result.error)
		end
		return Result.Ok(nextValue)
	end

	function self:remove(userId: number, amountIdr: number?): Result<number>
		if userId <= 0 then
			return Result.Err("invalid_user")
		end
		local nextValue = 0
		local result = mutate(function(current)
			local key = tostring(userId)
			local currentValue = math.max(0, math.floor(tonumber(current[key]) or 0))
			if currentValue <= 0 then
				return current
			end
			local removeAmount = if amountIdr == nil then currentValue else math.max(0, math.floor(amountIdr))
			nextValue = math.max(0, currentValue - removeAmount)
			if nextValue <= 0 then
				current[key] = nil
			else
				current[key] = nextValue
			end
			return current
		end)
		if not result.ok then
			return Result.Err(result.error)
		end
		return Result.Ok(nextValue)
	end

	return self
end

ManualBagibagiRepository.create = createRepository

return ManualBagibagiRepository
