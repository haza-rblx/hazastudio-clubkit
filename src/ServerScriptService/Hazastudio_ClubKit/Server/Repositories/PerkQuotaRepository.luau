--!strict
-- Durable weekly perk-quota counters (external-admin bridge perks, e.g. smite).
-- One DataStore entry per {perk, userId, ISO-week}: the week key rotates the
-- key itself, so a new ISO week (Mon 00:00 UTC) starts from zero with no
-- cleanup job. See ExternalAdminPerksDomain.quotaKey/isoWeekKey.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local BudgetGate = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetGate)
local ExternalAdminPerksDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.ExternalAdminPerksDomain)

export type PerkQuotaRepository = {
	--- Atomically consume one unit of the weekly quota. Returns remaining uses
	--- after the write, or Err("perk_quota_exhausted") when none are left.
	consume: (self: PerkQuotaRepository, perk: string, userId: number, quota: number) -> Result<number>,
	--- Read-only remaining count (never writes).
	peek: (self: PerkQuotaRepository, perk: string, userId: number, quota: number) -> Result<number>,
}

local PerkQuotaRepository = {}

local function createRepository(deps: { logger: any? }?): PerkQuotaRepository
	local log = if deps and deps.logger then deps.logger else Logger.new("PerkQuotaRepository")
	local store = DataStoreService:GetDataStore(Config.DataStore.PERK_QUOTA_KEY)
	local budgetGate = BudgetGate.create({ logger = log, name = "PerkQuotaRepository" })

	local function parseUsed(raw: any): number
		if type(raw) ~= "table" then
			return 0
		end
		local used = math.floor(tonumber(raw.used) or 0)
		return math.max(0, used)
	end

	local self = {} :: PerkQuotaRepository

	function self:peek(perk: string, userId: number, quota: number): Result<number>
		if type(perk) ~= "string" or perk == "" or userId <= 0 or quota <= 0 then
			return Result.Err("invalid_perk_quota")
		end
		local key = ExternalAdminPerksDomain.quotaKey(perk, userId, ExternalAdminPerksDomain.isoWeekKey(os.time()))
		local readResult = budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
			return Result.withRetry(function()
				return store:GetAsync(key)
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)
		if not readResult.ok then
			return Result.Err(readResult.error)
		end
		return Result.Ok(math.max(0, quota - parseUsed(readResult.value)))
	end

	function self:consume(perk: string, userId: number, quota: number): Result<number>
		if type(perk) ~= "string" or perk == "" or userId <= 0 or quota <= 0 then
			return Result.Err("invalid_perk_quota")
		end
		local key = ExternalAdminPerksDomain.quotaKey(perk, userId, ExternalAdminPerksDomain.isoWeekKey(os.time()))
		-- Atomically read-and-increment (or reject) in one UpdateAsync transform.
		-- Returning nil from the transform cancels the write, so an exhausted
		-- quota never creates/updates the key.
		local remaining: number? = nil
		local writeResult = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return Result.withRetry(function()
				store:UpdateAsync(key, function(old: any): any
					local used = parseUsed(old)
					if used >= quota then
						remaining = nil
						return nil -- cancel: quota exhausted, nothing written
					end
					used += 1
					remaining = quota - used
					return { used = used }
				end)
				return nil
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)
		if not writeResult.ok then
			return Result.Err(writeResult.error)
		end
		if remaining == nil then
			return Result.Err("perk_quota_exhausted")
		end
		return Result.Ok(remaining :: number)
	end

	return self
end

PerkQuotaRepository.create = createRepository

return PerkQuotaRepository
