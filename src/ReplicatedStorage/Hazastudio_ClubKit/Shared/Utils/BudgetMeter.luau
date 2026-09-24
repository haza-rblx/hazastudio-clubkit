--!strict
-- Shared/Utils/BudgetMeter.luau
--
-- Counts the per-server Roblox budgets the kit spends (production hardening P1, workstream F /
-- ADR 0007 phase B, minimal): DataStore requests by type, HttpService requests by endpoint
-- class, MessagingService publishes, and budget events (budget_low refusals, loads given up).
-- Server-side only in practice; it is pure (no Roblox services) so lune specs require it.
--
-- Hooks: BudgetGate (DataStore), DataStoreScheduler (lowest budget seen), Server/Net/HttpRequest
-- (HTTP), CrossServerCache + DonationService (Messaging), ProfileLoader / PersistenceFabricHooks
-- (events). Main.server logs `formatSummary(rollWindow())` every Config.BudgetMeter.LOG_INTERVAL_SEC.
-- P3: Server/Net/BudgetTelemetry folds the rolled windows into an Aggregate (below) and posts it
-- to {ApiUrl}/v3/telemetry (kind "budget", every 15 min, bulk priority) through BackendClient.
--
-- Counters come in two scopes: `window` (since the last rollWindow) and `total` (since boot).

type Counts = { [string]: number }

export type Scope = {
	dataStore: Counts, -- dispatched requests by DataStoreRequestType name
	dataStoreRefused: Counts, -- admission refusals by reason (budget_low, inflight_saturated)
	minBudget: Counts, -- lowest GetRequestBudgetForRequestType seen, by type (window only)
	http: Counts, -- requests by endpoint class
	httpFailed: Counts, -- pcall errors + non-2xx by endpoint class
	http429: number,
	messaging: Counts, -- publishes by topic
	messagingFailed: number,
	events: Counts, -- budget_low, load_gave_up, leave_flush_retry, ...
}

export type Snapshot = {
	windowSec: number,
	window: Scope,
	total: Scope,
}

local BudgetMeter = {}

local function newScope(): Scope
	return {
		dataStore = {},
		dataStoreRefused = {},
		minBudget = {},
		http = {},
		httpFailed = {},
		http429 = 0,
		messaging = {},
		messagingFailed = 0,
		events = {},
	}
end

local window: Scope = newScope()
local total: Scope = newScope()
local windowStartedAt = os.clock()

local function bump(counts: Counts, key: string, amount: number?)
	counts[key] = (counts[key] or 0) + (amount or 1)
end

local function cleanKey(value: any, fallback: string): string
	if type(value) == "string" and value ~= "" then
		return value
	end
	return fallback
end

local function copyCounts(counts: Counts): Counts
	return table.clone(counts)
end

local function copyScope(scope: Scope): Scope
	return {
		dataStore = copyCounts(scope.dataStore),
		dataStoreRefused = copyCounts(scope.dataStoreRefused),
		minBudget = copyCounts(scope.minBudget),
		http = copyCounts(scope.http),
		httpFailed = copyCounts(scope.httpFailed),
		http429 = scope.http429,
		messaging = copyCounts(scope.messaging),
		messagingFailed = scope.messagingFailed,
		events = copyCounts(scope.events),
	}
end

--- A DataStore request that passed admission and was dispatched.
function BudgetMeter.recordDataStore(requestType: string)
	local key = cleanKey(requestType, "Unknown")
	bump(window.dataStore, key)
	bump(total.dataStore, key)
end

--- A request the admission gate refused. `budget_low` also counts as a budget event.
function BudgetMeter.recordDataStoreRefused(requestType: string, reason: string)
	local key = cleanKey(reason, "refused") .. ":" .. cleanKey(requestType, "Unknown")
	bump(window.dataStoreRefused, key)
	bump(total.dataStoreRefused, key)
	if reason == "budget_low" or reason == "budget_exhausted" then
		BudgetMeter.recordEvent("budget_low")
	end
end

--- Lowest remaining budget seen this window, per request type.
function BudgetMeter.observeBudget(requestType: string, budget: number)
	if type(budget) ~= "number" then
		return
	end
	local key = cleanKey(requestType, "Unknown")
	local current = window.minBudget[key]
	if current == nil or budget < current then
		window.minBudget[key] = budget
	end
end

--- One HttpService request. `ok` = the call returned a 2xx response.
function BudgetMeter.recordHttp(endpointClass: string, ok: boolean, statusCode: number?)
	local key = cleanKey(endpointClass, "other")
	bump(window.http, key)
	bump(total.http, key)
	if not ok then
		bump(window.httpFailed, key)
		bump(total.httpFailed, key)
	end
	if statusCode == 429 then
		window.http429 += 1
		total.http429 += 1
	end
end

--- One MessagingService:PublishAsync attempt.
function BudgetMeter.recordMessagingPublish(topic: string, ok: boolean)
	local key = cleanKey(topic, "unknown")
	bump(window.messaging, key)
	bump(total.messaging, key)
	if not ok then
		window.messagingFailed += 1
		total.messagingFailed += 1
	end
end

function BudgetMeter.recordEvent(name: string, amount: number?)
	local key = cleanKey(name, "event")
	bump(window.events, key, amount)
	bump(total.events, key, amount)
end

--- Copy of the current window and the since-boot totals. Does not reset anything.
function BudgetMeter.snapshot(): Snapshot
	return {
		windowSec = math.max(0, os.clock() - windowStartedAt),
		window = copyScope(window),
		total = copyScope(total),
	}
end

--- Snapshot, then start a new window (the since-boot totals keep counting).
function BudgetMeter.rollWindow(): Snapshot
	local snap = BudgetMeter.snapshot()
	window = newScope()
	windowStartedAt = os.clock()
	return snap
end

--- Test helper: forget everything.
function BudgetMeter.reset()
	window = newScope()
	total = newScope()
	windowStartedAt = os.clock()
end

local function sumCounts(counts: Counts): number
	local n = 0
	for _, value in pairs(counts) do
		n += value
	end
	return n
end

-- ── Telemetry aggregate (production hardening P3, workstream F / ADR 0007 phase B) ──────────
-- The rolled 60 s windows are folded into one aggregate that Server/Net/BudgetTelemetry posts to
-- {ApiUrl}/v3/telemetry (kind "budget") every Config.Telemetry.BUDGET_INTERVAL_SEC. Counts,
-- lowest budgets and per-window peaks only — never a player id.

export type Aggregate = {
	windows: number,
	seconds: number,
	scope: Scope,
	peak: { ds: number, http: number, msg: number, players: number },
}

function BudgetMeter.newAggregate(): Aggregate
	return { windows = 0, seconds = 0, scope = newScope(), peak = { ds = 0, http = 0, msg = 0, players = 0 } }
end

local function addCounts(into: Counts, from: Counts)
	for key, value in pairs(from) do
		into[key] = (into[key] or 0) + value
	end
end

--- Folds one rolled window (`BudgetMeter.rollWindow()`) into `agg`; `players` = players online now.
function BudgetMeter.absorb(agg: Aggregate, snap: Snapshot, players: number?)
	local w = snap.window
	local s = agg.scope
	agg.windows += 1
	agg.seconds += snap.windowSec
	addCounts(s.dataStore, w.dataStore)
	addCounts(s.dataStoreRefused, w.dataStoreRefused)
	addCounts(s.http, w.http)
	addCounts(s.httpFailed, w.httpFailed)
	addCounts(s.messaging, w.messaging)
	addCounts(s.events, w.events)
	s.http429 += w.http429
	s.messagingFailed += w.messagingFailed
	for key, value in pairs(w.minBudget) do
		local current = s.minBudget[key]
		if current == nil or value < current then
			s.minBudget[key] = value
		end
	end
	agg.peak.ds = math.max(agg.peak.ds, sumCounts(w.dataStore))
	agg.peak.http = math.max(agg.peak.http, sumCounts(w.http))
	agg.peak.msg = math.max(agg.peak.msg, sumCounts(w.messaging))
	agg.peak.players = math.max(agg.peak.players, math.floor(tonumber(players) or 0))
end

--- JSON-ready payload of an aggregate (the `payload` of POST /v3/telemetry, kind "budget").
function BudgetMeter.aggregatePayload(agg: Aggregate): { [string]: any }
	local s = agg.scope
	return {
		windows = agg.windows,
		seconds = math.floor(agg.seconds + 0.5),
		ds = copyCounts(s.dataStore),
		ds_refused = copyCounts(s.dataStoreRefused),
		min_budget = copyCounts(s.minBudget),
		http = copyCounts(s.http),
		http_failed = copyCounts(s.httpFailed),
		http_429 = s.http429,
		messaging = copyCounts(s.messaging),
		messaging_failed = s.messagingFailed,
		events = copyCounts(s.events),
		peak = table.clone(agg.peak),
	}
end

local function formatCounts(counts: Counts): string
	local keys = {}
	for key in pairs(counts) do
		table.insert(keys, key)
	end
	table.sort(keys)
	local parts = table.create(#keys)
	for i, key in ipairs(keys) do
		parts[i] = key .. "=" .. tostring(counts[key])
	end
	return if #parts > 0 then table.concat(parts, " ") else "-"
end

--- One line for the server log, e.g.
--- "budget 60s | ds 17 [GetAsync=12 UpdateAsync=5] refused [-] min [GetAsync=240] | http 14 [...] fail 1 429 0 | msg 3 [...] fail 0 | events [-]"
function BudgetMeter.formatSummary(snap: Snapshot): string
	local w = snap.window
	return string.format(
		"budget %ds | ds %d [%s] refused [%s] min [%s] | http %d [%s] fail %d 429 %d | msg %d [%s] fail %d | events [%s]",
		math.floor(snap.windowSec + 0.5),
		sumCounts(w.dataStore),
		formatCounts(w.dataStore),
		formatCounts(w.dataStoreRefused),
		formatCounts(w.minBudget),
		sumCounts(w.http),
		formatCounts(w.http),
		sumCounts(w.httpFailed),
		w.http429,
		sumCounts(w.messaging),
		formatCounts(w.messaging),
		w.messagingFailed,
		formatCounts(w.events)
	)
end

return BudgetMeter
