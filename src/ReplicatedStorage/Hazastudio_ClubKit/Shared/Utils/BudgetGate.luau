--!strict
-- Shared/Utils/BudgetGate.lua
--
-- Wrap every DataStoreService request behind a per-request-type budget check.
--
-- Why this exists:
-- Roblox publishes a per-server quota for each DataStoreRequestType. Calls
-- issued past the quota are queued or dropped, surfacing in production as
-- "DataStore request was added to queue. If request queue fills, further
-- requests will be dropped." Repository layers MUST funnel every call through
-- a BudgetGate so the gate can defer or refuse before Roblox queues it.
--
-- Contract (see Guidelines_v3/refs/REF_PERSISTENCE.md):
--   - executeAsync polls budget; if below minBudget it waits up to deferSeconds
--   - on recovery it executes the wrapped function
--   - on timeout it returns Result.Err("budget_exhausted")
--   - if the wrapped function returns a Result, it is passed through
--   - otherwise the raw return value is wrapped in Result.Ok
--
-- Composes with RetryUtils.retryAsync and Result.withRetry. Typical pattern:
--   budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
--       return Result.withRetry(function()
--           return store:UpdateAsync(key, mergeFn)
--       end, RETRY_ATTEMPTS)
--   end)

local DataStoreService = game:GetService("DataStoreService")

local Result = require(script.Parent.Result)
local Types = require(script.Parent.Parent.Domain.Types)

type Result<T> = Types.Result<T>
type ILogger = Types.ILogger

export type BudgetGateOptions = {
	minBudget: number?,
	deferSeconds: number?,
	pollInterval: number?,
	logger: ILogger?,
	name: string?,
}

export type BudgetGate = {
	executeAsync: <T>(self: BudgetGate, requestType: Enum.DataStoreRequestType, fn: () -> T) -> Result<T>,
	canProceed: (self: BudgetGate, requestType: Enum.DataStoreRequestType) -> (boolean, number),
	getBudget: (self: BudgetGate, requestType: Enum.DataStoreRequestType) -> number,
	destroy: (self: BudgetGate) -> (),
}

-- Per-RequestType minimum budget. Reads stay at 1; writes need 2 because
-- UpdateAsync internally consumes Get + Set credits.
local DEFAULT_MIN_BUDGET: { [Enum.DataStoreRequestType]: number } = {
	[Enum.DataStoreRequestType.GetAsync] = 1,
	[Enum.DataStoreRequestType.SetIncrementAsync] = 2,
	[Enum.DataStoreRequestType.UpdateAsync] = 2,
	[Enum.DataStoreRequestType.GetSortedAsync] = 1,
	[Enum.DataStoreRequestType.SetIncrementSortedAsync] = 2,
}

local DEFAULT_DEFER_SECONDS = 5
local DEFAULT_POLL_INTERVAL = 0.5

local BudgetGate = {}
BudgetGate.__index = BudgetGate

local function getBudgetSafe(requestType: Enum.DataStoreRequestType): number
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(requestType)
	end)
	if not ok then
		return 0
	end
	return tonumber(budget) or 0
end

local function isResultShape(value: any): boolean
	return type(value) == "table" and value.ok ~= nil and (value.ok == true or value.ok == false)
end

--- Construct a BudgetGate. Options are all optional; defaults are tuned for
--- the 100 CCU target (perf-scaling R3.8: ~110 writes/min, ~80 reads/min,
--- 5s defer window — see Config.Budget).
function BudgetGate.create(options: BudgetGateOptions?): BudgetGate
	local opts = options or {}
	local self = setmetatable({
		_minBudgetOverride = opts.minBudget,
		_deferSeconds = opts.deferSeconds or DEFAULT_DEFER_SECONDS,
		_pollInterval = opts.pollInterval or DEFAULT_POLL_INTERVAL,
		_logger = opts.logger,
		_name = opts.name or "BudgetGate",
	}, BudgetGate)
	return (self :: any) :: BudgetGate
end

function BudgetGate:_minBudget(requestType: Enum.DataStoreRequestType): number
	if self._minBudgetOverride ~= nil then
		return self._minBudgetOverride
	end
	return DEFAULT_MIN_BUDGET[requestType] or 1
end

--- Read the current budget. Useful for diagnostics; prefer executeAsync for
--- actual gating logic.
function BudgetGate:getBudget(requestType: Enum.DataStoreRequestType): number
	return getBudgetSafe(requestType)
end

--- Snapshot check: is there enough budget right now? Returns the boolean and
--- the current budget so callers can log without a second pcall.
function BudgetGate:canProceed(requestType: Enum.DataStoreRequestType): (boolean, number)
	local budget = getBudgetSafe(requestType)
	return budget >= self:_minBudget(requestType), budget
end

--- Wait for budget, then execute the wrapped function.
--- Returns Result<T>. If the wrapped function itself returns a Result, that
--- Result is returned as-is (no double-wrap).
function BudgetGate:executeAsync<T>(
	requestType: Enum.DataStoreRequestType,
	fn: () -> T
): Result<T>
	local minBudget = self:_minBudget(requestType)
	local startedAt = os.clock()
	local deferred = false

	while true do
		local budget = getBudgetSafe(requestType)
		if budget >= minBudget then
			if deferred and self._logger then
				self._logger:info("Budget recovered after defer", {
					gate = self._name,
					requestType = tostring(requestType),
					budget = budget,
					deferredMs = math.floor((os.clock() - startedAt) * 1000),
				})
			end
			break
		end

		local elapsed = os.clock() - startedAt
		if elapsed >= self._deferSeconds then
			if self._logger then
				self._logger:warn("Budget exhausted, refusing call", {
					gate = self._name,
					requestType = tostring(requestType),
					budget = budget,
					minBudget = minBudget,
					deferredMs = math.floor(elapsed * 1000),
				})
			end
			return Result.Err("budget_exhausted")
		end

		deferred = true
		if self._logger then
			self._logger:debug("Budget low, deferring", {
				gate = self._name,
				requestType = tostring(requestType),
				budget = budget,
				minBudget = minBudget,
			})
		end
		task.wait(self._pollInterval)
	end

	local opStartedAt = os.clock()
	local ok, valueOrError = pcall(fn)
	local latencyMs = (os.clock() - opStartedAt) * 1000

	if not ok then
		if self._logger then
			self._logger:warn("Wrapped operation errored inside budget gate", {
				gate = self._name,
				requestType = tostring(requestType),
				error = tostring(valueOrError),
				latencyMs = math.floor(latencyMs),
			})
		end
		return Result.Err(tostring(valueOrError))
	end

	-- Pass-through: the wrapped function already returned a Result. Avoid
	-- double-wrapping so callers do not have to unwrap result.value.value.
	if isResultShape(valueOrError) then
		return valueOrError :: any
	end

	return Result.Ok(valueOrError :: T)
end

function BudgetGate:destroy()
	-- BudgetGate holds no connections; symmetric API for Lifecycle integration.
end

return BudgetGate
