--!strict
-- Lightweight 1s-window counters for OverheadUpdate / MusicStateSync / apply rates.
-- No-op when Config.NetworkPerf.ENABLE_COUNTERS is false (hot path stays free).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local NetworkPerfCounters = {}

local windowStart = os.clock()
local windowCounts: { [string]: number } = {}
local lastLoggedAt = 0
local LOG_INTERVAL_SEC = 5

local function countersEnabled(): boolean
	local np = Config.NetworkPerf
	return type(np) == "table" and np.ENABLE_COUNTERS == true
end

local function rollWindowIfNeeded()
	local now = os.clock()
	if now - windowStart < 1 then
		return
	end
	windowStart = now
	table.clear(windowCounts)
end

function NetworkPerfCounters.record(bucket: string, n: number?): ()
	if not countersEnabled() then
		return
	end
	rollWindowIfNeeded()
	windowCounts[bucket] = (windowCounts[bucket] or 0) + (n or 1)
end

function NetworkPerfCounters.snapshot(): { [string]: number }
	if not countersEnabled() then
		return {}
	end
	rollWindowIfNeeded()
	return table.clone(windowCounts) :: { [string]: number }
end

function NetworkPerfCounters.reset(): ()
	windowStart = os.clock()
	table.clear(windowCounts)
end

--- Optional sparse info log (call from a Heartbeat/periodic tick if desired).
function NetworkPerfCounters.maybeLog(logger: any): ()
	if not countersEnabled() or type(logger) ~= "table" or type(logger.info) ~= "function" then
		return
	end
	local now = os.clock()
	if now - lastLoggedAt < LOG_INTERVAL_SEC then
		return
	end
	lastLoggedAt = now
	local snap = NetworkPerfCounters.snapshot()
	if next(snap) == nil then
		return
	end
	logger:info("NetworkPerf 1s window", snap)
end

return NetworkPerfCounters
