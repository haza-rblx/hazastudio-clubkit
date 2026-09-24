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
	peek: (self: GiftPendingRepository, fromUserId: number) -> Result<number?>,
	consume: (self: GiftPendingRepository, fromUserId: number) -> Result<number?>,
}

local GiftPendingRepository = {}

type StoredGiftPending = {
	toUserId: number,
	storedAt: number,
}

-- Tombstone written by consume(): { state = "consumed", toUserId = 0, consumedToUserId,
-- storedAt, consumedAt }. Additive shape on the same key; toUserId = 0 makes older kits (which
-- only check toUserId > 0) read it as "no pending gift" too. The next store() overwrites it.
local CONSUMED_STATE = "consumed"

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

	local function parseEntry(old: any): StoredGiftPending?
		if type(old) ~= "table" then
			return nil
		end
		-- A consumed intent stays behind as a tombstone (see consume); it is never a live gift.
		if old.state == CONSUMED_STATE then
			return nil
		end
		local entry: StoredGiftPending = {
			toUserId = math.floor(tonumber(old.toUserId) or 0),
			storedAt = math.floor(tonumber(old.storedAt) or 0),
		}
		if entry.toUserId > 0 and entry.storedAt > 0 and not isExpired(entry) then
			return entry
		end
		return nil
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

	-- Read-only: do not delete. ProcessReceipt peeks, grants, then consume().
	function self:peek(fromUserId: number): Result<number?>
		if fromUserId <= 0 then
			return Result.Ok(nil)
		end
		local readResult = budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
			return Result.withRetry(function()
				return store:GetAsync(keyFor(fromUserId))
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)
		if not readResult.ok then
			return Result.Err(readResult.error)
		end
		local entry = parseEntry(readResult.value)
		if entry then
			return Result.Ok(entry.toUserId)
		end
		return Result.Ok(nil)
	end

	function self:consume(fromUserId: number): Result<number?>
		if fromUserId <= 0 then
			return Result.Ok(nil)
		end
		-- Atomic consume via a single UpdateAsync: the transform reads the
		-- current entry, captures toUserId and replaces the entry with a
		-- tombstone that parseEntry treats as absent — all in one DataStore
		-- operation. This closes the TOCTOU race where two concurrent consume
		-- calls (e.g. ProcessReceipt retries) both saw a valid entry and both
		-- returned toUserId (double gift delivery): the second one now reads
		-- the tombstone and reports no-consume.
		--
		-- Returning nil from an UpdateAsync transform CANCELS the write (it
		-- does not delete the key). Until 2026-09-24 this function returned nil
		-- here, so the entry was never removed and a re-delivered receipt could
		-- re-grant within the persist timeout. RemoveAsync is not an option:
		-- it cannot read-and-clear atomically.
		--
		-- Correctness under UpdateAsync retries: the transform may run more
		-- than once on contention. consumedToUserId is set on EVERY invocation,
		-- and only the LAST invocation's return value commits, so it reflects
		-- whether THIS call wrote the tombstone. No live entry → return nil
		-- (cancel; nothing to write).
		local consumedToUserId: number? = nil
		local updateResult = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return Result.withRetry(function()
				store:UpdateAsync(keyFor(fromUserId), function(old)
					local entry = parseEntry(old)
					if not entry then
						consumedToUserId = nil
						return nil
					end
					consumedToUserId = entry.toUserId
					return {
						state = CONSUMED_STATE,
						toUserId = 0,
						consumedToUserId = entry.toUserId,
						storedAt = entry.storedAt,
						consumedAt = os.time(),
					}
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
