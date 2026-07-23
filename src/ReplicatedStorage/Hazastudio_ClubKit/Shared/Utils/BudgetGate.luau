--!strict
-- Shared/Utils/BudgetGate.lua
--
-- Repository-facing admission wrapper. By default delegates to the process-wide
-- DataStoreScheduler (Persistence Fabric) so concurrent BudgetGate.create()
-- callers cannot race on GetRequestBudget snapshots.
--
-- Kill switch: Config.Persistence.USE_LEGACY_PER_REPO_BUDGET_GATE = true
-- restores the pre-fabric per-instance snapshot loop.
--
-- Contract:
--   - executeAsync polls/reserves budget; refuses with budget_low
--     (legacy alias budget_exhausted may still appear from older call sites)
--   - optional 3rd arg keyMutex serializes same-key writes via the scheduler
--   - if the wrapped function returns a Result, it is passed through

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Result = require(script.Parent.Result)
local Types = require(script.Parent.Parent.Domain.Types)
local DataStoreScheduler = require(script.Parent.DataStoreScheduler)

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
	executeAsync: <T>(
		self: BudgetGate,
		requestType: Enum.DataStoreRequestType,
		fn: () -> T,
		keyMutex: string?
	) -> Result<T>,
	canProceed: (self: BudgetGate, requestType: Enum.DataStoreRequestType) -> (boolean, number),
	getBudget: (self: BudgetGate, requestType: Enum.DataStoreRequestType) -> number,
	destroy: (self: BudgetGate) -> (),
}

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

local function useLegacyGate(): boolean
	local p = Config.Persistence
	return type(p) == "table" and p.USE_LEGACY_PER_REPO_BUDGET_GATE == true
end

function BudgetGate.create(options: BudgetGateOptions?): BudgetGate
	local opts = options or {}
	local deferDefault = (Config.Budget and Config.Budget.DEFER_SECONDS) or DEFAULT_DEFER_SECONDS
	local pollDefault = (Config.Budget and Config.Budget.POLL_INTERVAL) or DEFAULT_POLL_INTERVAL
	local self = setmetatable({
		_minBudgetOverride = opts.minBudget,
		_deferSeconds = opts.deferSeconds or deferDefault,
		_pollInterval = opts.pollInterval or pollDefault,
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

function BudgetGate:getBudget(requestType: Enum.DataStoreRequestType): number
	return getBudgetSafe(requestType)
end

function BudgetGate:canProceed(requestType: Enum.DataStoreRequestType): (boolean, number)
	if not useLegacyGate() then
		return DataStoreScheduler.canProceed(requestType, self:_minBudget(requestType))
	end
	local budget = getBudgetSafe(requestType)
	return budget >= self:_minBudget(requestType), budget
end

function BudgetGate:executeAsync<T>(
	requestType: Enum.DataStoreRequestType,
	fn: () -> T,
	keyMutex: string?
): Result<T>
	if not useLegacyGate() then
		return DataStoreScheduler.executeAsync(requestType, fn, {
			minBudget = self:_minBudget(requestType),
			deferSeconds = self._deferSeconds,
			pollInterval = self._pollInterval,
			logger = self._logger,
			name = self._name,
			keyMutex = keyMutex,
		})
	end

	-- Legacy per-instance snapshot loop (kill-switch path).
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
			return Result.Err("budget_low")
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

	if isResultShape(valueOrError) then
		return valueOrError :: any
	end

	return Result.Ok(valueOrError :: T)
end

function BudgetGate:destroy()
end

return BudgetGate
