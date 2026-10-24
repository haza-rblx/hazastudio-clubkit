--!strict
-- Retry policy for a deck's asset load (ADR 0021): how many tries per cycle, how long each waits,
-- and which cache key each try uses.
local LoadPolicy = {}

LoadPolicy.MAX_ATTEMPTS = 6
LoadPolicy.CYCLE_DELAY = 8 -- seconds to wait after a failed cycle before starting over
LoadPolicy.WATCHDOG_INTERVAL = 2 -- seconds between watchdog checks
LoadPolicy.PRELOAD_CAP_DESKTOP = 300
LoadPolicy.PRELOAD_CAP_MOBILE = 15
LoadPolicy.PRELOAD_CONCURRENCY = 8

-- seconds to wait for a load to finish
function LoadPolicy.timeout(isTouch: boolean): number
	return if isTouch then 30 else 25
end

-- seconds to back off after attempt `attempt` fails: 1.5 s per attempt, capped at 8 s
function LoadPolicy.backoff(attempt: number): number
	return math.min(1.5 * attempt, 8)
end

-- odd attempts use the asset URL, even attempts the web URL (a different cache key)
function LoadPolicy.contentId(assetId: number, attempt: number): string
	if attempt % 2 == 1 then
		return "rbxassetid://" .. string.format("%d", assetId)
	end
	return "https://www.roblox.com/asset/?id=" .. string.format("%d", assetId)
end

return LoadPolicy
