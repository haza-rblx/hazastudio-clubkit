--!strict
-- Durable gift intent storage. Survives server restarts between prompt and ProcessReceipt.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local BudgetGate = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetGate)

export type GiftPendingRepository = {
	store: (self: GiftPendingRepository, fromUserId: number, toUserId: number) -> Result<nil>,
	consume: (self: GiftPendingRepository, fromUserId: number) -> Result<number?>,
}

local GiftPendingRepository = {}

type StoredGiftPending = {
	toUserId: number,
	storedAt: number,
}

local function createRepository(deps: { logger: any? }?): GiftPendingRepository
	local log = if deps and deps.logger then deps.logger else Logger.new("GiftPendingRepository")
	local store = DataStoreService:GetDataStore(Config.Shop.GIFT_PENDING_DATASTORE_KEY)
	local budgetGate = BudgetGate.create({ logger = log, name = "GiftPendingRepository" })

	local function keyFor(fromUserId: number): string
		return "gift:" .. tostring(fromUserId)
	end

	local function isExpired(entry: StoredGiftPending): boolean
		local ttl = Config.Shop.GIFT_PENDING_PERSIST_TIMEOUT or Config.Shop.GIFT_PENDING_TIMEOUT
		return os.time() - entry.storedAt > ttl
	end

	local self = {} :: GiftPendingRepository

	function self:store(fromUserId: number, toUserId: number): Result<nil>
		if fromUserId <= 0 or toUserId <= 0 then
			return Result.Err("invalid_gift_pending")
		end
		local writeResult = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return Result.withRetry(function()
				store:UpdateAsync(keyFor(fromUserId), function()
					return {
						toUserId = toUserId,
						storedAt = os.time(),
					}
				end)
				return nil
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)
		if not writeResult.ok then
			log:warn("Gift pending store failed", {
				fromUserId = fromUserId,
				toUserId = toUserId,
				error = writeResult.error,
			})
			return Result.Err(writeResult.error)
		end
		return Result.Ok(nil)
	end

	function self:consume(fromUserId: number): Result<number?>
		if fromUserId <= 0 then
			return Result.Ok(nil)
		end
		-- Atomic consume via a single UpdateAsync. The callback reads the
		-- current entry, captures toUserId, and returns nil to delete the key —
		-- all within one DataStore operation. This closes the TOCTOU race where
		-- two concurrent consume calls (e.g. ProcessReceipt retries) both
		-- GetAsync'd a valid entry, both saw it as valid, and both returned
		-- toUserId (double gift delivery).
		--
		-- Correctness under UpdateAsync retries: the transform callback may run
		-- more than once on contention. We capture toUserId on EVERY invocation
		-- (set when old is a valid entry, clear when old is nil). The LAST
		-- invocation is the one whose return value commits, so the final value
		-- of consumedToUserId reflects whether THIS call actually performed the
		-- delete. If another server deleted the key between our retries, our
		-- last invocation sees old=nil and we correctly report no-consume.
		local consumedToUserId: number? = nil
		local updateResult = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return Result.withRetry(function()
				store:UpdateAsync(keyFor(fromUserId), function(old)
					if type(old) ~= "table" then
						-- Key absent or already consumed (by another server or
						-- a prior retry of this call). Clear any capture from a
						-- previous invocation so we don't report a consume we
						-- didn't perform.
						consumedToUserId = nil
						return nil
					end
					-- Valid entry in THIS invocation. Capture its toUserId; the
					-- last invocation's capture is the one that matters because
					-- its return value is what commits.
					local entry: StoredGiftPending = {
						toUserId = math.floor(tonumber(old.toUserId) or 0),
						storedAt = math.floor(tonumber(old.storedAt) or 0),
					}
					if entry.toUserId > 0 and entry.storedAt > 0 and not isExpired(entry) then
						consumedToUserId = entry.toUserId
					else
						consumedToUserId = nil
					end
					-- Always delete (consume) the entry on every invocation so
					-- the key is cleared regardless of callback retries.
					return nil
				end)
				return nil
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)
		if not updateResult.ok then
			return Result.Err(updateResult.error)
		end
		return Result.Ok(consumedToUserId)
	end

	return self
end

GiftPendingRepository.create = createRepository

return GiftPendingRepository
