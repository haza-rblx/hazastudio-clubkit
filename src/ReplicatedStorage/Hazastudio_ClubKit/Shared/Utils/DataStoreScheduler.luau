--!strict
-- Shared/Utils/DataStoreScheduler.luau
--
-- Process-wide DataStore admission control.
--
-- Problem: per-repo BudgetGate instances each snapshot GetRequestBudget and may
-- all fire while budget looks OK, so Roblox still queues ("request was added to
-- queue"). This singleton reserves credits before dispatch and serializes
-- concurrent updates to the same store key.
--
-- Contract:
--   executeAsync(requestType, fn, opts?) waits until
--     budget - reserved >= minBudget + HEADROOM and inflight < MAX,
--   then reserves cost, optionally waits for key mutex, runs fn, releases.
--   Returns Result (pass-through if fn already returned Result).

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Result = require(script.Parent.Result)
local Types = require(script.Parent.Parent.Domain.Types)

type Result<T> = Types.Result<T>
type ILogger = Types.ILogger

export type ExecuteOptions = {
	minBudget: number?,
	deferSeconds: number?,
	pollInterval: number?,
	logger: ILogger?,
	name: string?,
	-- Logical key mutex, e.g. "Overhead_v1::8842050215"
	keyMutex: string?,
}

export type SchedulerMetrics = {
	deferred: number,
	rejectedBudget: number,
	dispatched: number,
	keySerialized: number,
	reservedByType: { [string]: number },
	inflightByType: { [string]: number },
}

local DEFAULT_MIN_BUDGET: { [Enum.DataStoreRequestType]: number } = {
	[Enum.DataStoreRequestType.GetAsync] = 1,
	[Enum.DataStoreRequestType.SetIncrementAsync] = 2,
	[Enum.DataStoreRequestType.UpdateAsync] = 2,
	[Enum.DataStoreRequestType.GetSortedAsync] = 1,
	[Enum.DataStoreRequestType.SetIncrementSortedAsync] = 2,
}

local reservedByType: { [Enum.DataStoreRequestType]: number } = {}
local inflightByType: { [Enum.DataStoreRequestType]: number } = {}

local metrics = {
	deferred = 0,
	rejectedBudget = 0,
	dispatched = 0,
	keySerialized = 0,
}

-- keyMutex -> waiters (boolean lock held by owner fiber)
local keyHeld: { [string]: boolean } = {}
local keyWaitQueues: { [string]: { thread } } = {}

local function persistenceConfig()
	local p = Config.Persistence
	if type(p) ~= "table" then
		return {
			HEADROOM = 2,
			MAX_INFLIGHT_PER_TYPE = 4,
			KEY_MUTEX_ENABLED = true,
			DEFER_SECONDS = Config.Budget.DEFER_SECONDS or 8,
			POLL_INTERVAL = Config.Budget.POLL_INTERVAL or 0.5,
		}
	end
	return p
end

local function getBudgetSafe(requestType: Enum.DataStoreRequestType): number
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(requestType)
	end)
	if not ok then
		return 0
	end
	return tonumber(budget) or 0
end

local function typeKey(requestType: Enum.DataStoreRequestType): string
	return tostring(requestType)
end

local function isResultShape(value: any): boolean
	return type(value) == "table" and value.ok ~= nil and (value.ok == true or value.ok == false)
end

local function minBudgetFor(requestType: Enum.DataStoreRequestType, override: number?): number
	if override ~= nil then
		return override
	end
	return DEFAULT_MIN_BUDGET[requestType] or 1
end

local function acquireKeyMutex(key: string): () -> ()
	local cfg = persistenceConfig()
	if not cfg.KEY_MUTEX_ENABLED then
		return function() end
	end

	if keyHeld[key] then
		metrics.keySerialized += 1
		local queue = keyWaitQueues[key]
		if not queue then
			queue = {}
			keyWaitQueues[key] = queue
		end
		table.insert(queue, coroutine.running())
		coroutine.yield()
	end

	keyHeld[key] = true

	return function()
		keyHeld[key] = nil
		local queue = keyWaitQueues[key]
		if queue and #queue > 0 then
			local nextThread = table.remove(queue, 1)
			if #queue == 0 then
				keyWaitQueues[key] = nil
			end
			if nextThread then
				task.spawn(nextThread)
			end
		else
			keyWaitQueues[key] = nil
		end
	end
end

local DataStoreScheduler = {}

function DataStoreScheduler.getMetrics(): SchedulerMetrics
	local reservedSnapshot: { [string]: number } = {}
	local inflightSnapshot: { [string]: number } = {}
	for requestType, amount in pairs(reservedByType) do
		reservedSnapshot[typeKey(requestType)] = amount
	end
	for requestType, amount in pairs(inflightByType) do
		inflightSnapshot[typeKey(requestType)] = amount
	end
	return {
		deferred = metrics.deferred,
		rejectedBudget = metrics.rejectedBudget,
		dispatched = metrics.dispatched,
		keySerialized = metrics.keySerialized,
		reservedByType = reservedSnapshot,
		inflightByType = inflightSnapshot,
	}
end

function DataStoreScheduler.resetMetrics()
	metrics.deferred = 0
	metrics.rejectedBudget = 0
	metrics.dispatched = 0
	metrics.keySerialized = 0
end

--- Snapshot: can a new request of this cost likely proceed without waiting?
function DataStoreScheduler.canProceed(requestType: Enum.DataStoreRequestType, minBudget: number?): (boolean, number)
	local cfg = persistenceConfig()
	local cost = minBudgetFor(requestType, minBudget)
	local budget = getBudgetSafe(requestType)
	local reserved = reservedByType[requestType] or 0
	local inflight = inflightByType[requestType] or 0
	local maxInflight = cfg.MAX_INFLIGHT_PER_TYPE or 4
	local headroom = cfg.HEADROOM or 2
	local available = budget - reserved
	local ok = available >= (cost + headroom) and inflight < maxInflight
	return ok, budget
end

function DataStoreScheduler.executeAsync<T>(
	requestType: Enum.DataStoreRequestType,
	fn: () -> T,
	opts: ExecuteOptions?
): Result<T>
	local options = opts or {}
	local cfg = persistenceConfig()
	local cost = minBudgetFor(requestType, options.minBudget)
	local deferSeconds = options.deferSeconds or cfg.DEFER_SECONDS or Config.Budget.DEFER_SECONDS or 8
	local pollInterval = options.pollInterval or cfg.POLL_INTERVAL or Config.Budget.POLL_INTERVAL or 0.5
	local maxInflight = cfg.MAX_INFLIGHT_PER_TYPE or 4
	local headroom = cfg.HEADROOM or 2
	local log = options.logger
	local gateName = options.name or "DataStoreScheduler"

	local startedAt = os.clock()
	local deferred = false

	while true do
		local budget = getBudgetSafe(requestType)
		local reserved = reservedByType[requestType] or 0
		local inflight = inflightByType[requestType] or 0
		local available = budget - reserved

		if available >= (cost + headroom) and inflight < maxInflight then
			-- Reserve before yielding so concurrent waiters observe the debit.
			reservedByType[requestType] = reserved + cost
			inflightByType[requestType] = inflight + 1
			if deferred and log then
				log:info("Budget recovered after defer", {
					gate = gateName,
					requestType = tostring(requestType),
					budget = budget,
					reserved = reservedByType[requestType],
					deferredMs = math.floor((os.clock() - startedAt) * 1000),
				})
			end
			break
		end

		local elapsed = os.clock() - startedAt
		if elapsed >= deferSeconds then
			metrics.rejectedBudget += 1
			if log then
				log:warn("Budget exhausted, refusing call", {
					gate = gateName,
					requestType = tostring(requestType),
					budget = budget,
					reserved = reserved,
					inflight = inflight,
					minBudget = cost,
					headroom = headroom,
					deferredMs = math.floor(elapsed * 1000),
				})
			end
			return Result.Err("budget_exhausted")
		end

		if not deferred then
			metrics.deferred += 1
		end
		deferred = true
		if log then
			log:debug("Budget low, deferring", {
				gate = gateName,
				requestType = tostring(requestType),
				budget = budget,
				reserved = reserved,
				inflight = inflight,
				minBudget = cost,
				headroom = headroom,
			})
		end
		task.wait(pollInterval)
	end

	local releaseKey = function() end
	if type(options.keyMutex) == "string" and options.keyMutex ~= "" then
		releaseKey = acquireKeyMutex(options.keyMutex)
	end

	local opStartedAt = os.clock()
	local ok, valueOrError = pcall(fn)
	local latencyMs = (os.clock() - opStartedAt) * 1000

	releaseKey()

	local reservedNow = reservedByType[requestType] or 0
	reservedByType[requestType] = math.max(0, reservedNow - cost)
	local inflightNow = inflightByType[requestType] or 0
	inflightByType[requestType] = math.max(0, inflightNow - 1)

	if not ok then
		if log then
			log:warn("Wrapped operation errored inside DataStoreScheduler", {
				gate = gateName,
				requestType = tostring(requestType),
				error = tostring(valueOrError),
				latencyMs = math.floor(latencyMs),
			})
		end
		return Result.Err(tostring(valueOrError))
	end

	metrics.dispatched += 1

	if isResultShape(valueOrError) then
		return valueOrError :: any
	end

	return Result.Ok(valueOrError :: T)
end

return DataStoreScheduler
