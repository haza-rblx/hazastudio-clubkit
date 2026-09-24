--!strict
-- Shared/Domain/HttpBudgetPolicy.luau
--
-- Pure rules behind Server/Net/BackendClient (production hardening P3, workstream C). No Roblox
-- services, no Config: the caller passes the numbers, so lune specs require this directly
-- (.tmp/http-budget-policy-spec.luau).
--
-- Token bucket: one per game server (Roblox allows 500 HttpService requests/min per server,
-- whatever the player count). Refills at `ratePerMin`, holds at most `burst`. A priority may only
-- take a token while more than `floors[priority] * burst` tokens would remain:
--   critical (licence, notifications, delivery register) may drain it,
--   normal stops at 25 % left, bulk (lookups, telemetry, imports) at 50 % left.
-- A refused take returns how long until it would pass, so callers defer instead of dropping.
--
-- 429 pause: the VPS answers `{ok:false,error:"rate_limited",retry_after:N}` + `Retry-After: N`
-- once its limiter enforces; every priority then waits N seconds (capped).
--
-- Circuit breaker, per endpoint group: opens after `consecutive` straight failures or when at
-- least `minSamples` calls in the last `windowSec` failed `failRatio` or more; stays open for
-- openSteps[1] s, then lets one probe through (half-open). A failed probe re-opens for the next
-- step (30 → 60 → 120 s); a successful one closes it and resets the steps.
-- Failures are transport errors and 5xx. A 4xx is an answer; a 429 is handled by the pause.

export type Priority = "critical" | "normal" | "bulk"

export type BucketConfig = {
	ratePerMin: number,
	burst: number,
	floors: { [string]: number },
}

export type Bucket = {
	cfg: BucketConfig,
	tokens: number,
	updatedAt: number,
	pausedUntil: number,
}

export type BreakerConfig = {
	consecutive: number,
	windowSec: number,
	failRatio: number,
	minSamples: number,
	openSteps: { number },
}

export type Breaker = {
	cfg: BreakerConfig,
	state: "closed" | "open" | "half_open",
	openUntil: number,
	step: number,
	straight: number,
	probing: boolean,
	samples: { { at: number, ok: boolean } },
}

local HttpBudgetPolicy = {}

local function ratePerSec(cfg: BucketConfig): number
	return math.max(0.001, (tonumber(cfg.ratePerMin) or 400) / 60)
end

local function refill(bucket: Bucket, now: number)
	local elapsed = now - bucket.updatedAt
	if elapsed > 0 then
		bucket.tokens = math.min(bucket.cfg.burst, bucket.tokens + elapsed * ratePerSec(bucket.cfg))
		bucket.updatedAt = now
	end
end

function HttpBudgetPolicy.newBucket(cfg: BucketConfig, now: number): Bucket
	return {
		cfg = cfg,
		tokens = cfg.burst,
		updatedAt = now,
		pausedUntil = -math.huge,
	}
end

--- Fraction of the burst currently available (0..1).
function HttpBudgetPolicy.fill(bucket: Bucket, now: number): number
	refill(bucket, now)
	if bucket.cfg.burst <= 0 then
		return 0
	end
	return bucket.tokens / bucket.cfg.burst
end

function HttpBudgetPolicy.isPaused(bucket: Bucket, now: number): boolean
	return now < bucket.pausedUntil
end

--- Takes one token for `priority`. Returns (true, 0) or (false, secondsUntilItWouldPass).
function HttpBudgetPolicy.tryTake(bucket: Bucket, priority: string, now: number): (boolean, number)
	if now < bucket.pausedUntil then
		return false, bucket.pausedUntil - now
	end
	refill(bucket, now)
	local floorFraction = bucket.cfg.floors[priority]
	if type(floorFraction) ~= "number" then
		floorFraction = bucket.cfg.floors.normal or 0
	end
	local floorTokens = floorFraction * bucket.cfg.burst
	local needed = floorTokens + 1
	-- Tolerance for float refill (e.g. 20.000000001 must not count as 21).
	if bucket.tokens + 1e-9 >= needed then
		bucket.tokens -= 1
		return true, 0
	end
	return false, (needed - bucket.tokens) / ratePerSec(bucket.cfg)
end

--- The VPS said "retry after `seconds`": every priority waits that long (capped at maxSeconds).
--- A shorter pause never shortens one already running.
function HttpBudgetPolicy.pause(bucket: Bucket, now: number, seconds: number, maxSeconds: number?)
	local capped = math.max(0, math.min(seconds, maxSeconds or seconds))
	local untilAt = now + capped
	if untilAt > bucket.pausedUntil then
		bucket.pausedUntil = untilAt
	end
end

function HttpBudgetPolicy.newBreaker(cfg: BreakerConfig): Breaker
	return {
		cfg = cfg,
		state = "closed",
		openUntil = 0,
		step = 0,
		straight = 0,
		probing = false,
		samples = {},
	}
end

local function openBreaker(breaker: Breaker, now: number)
	local steps = breaker.cfg.openSteps
	breaker.step = math.min(breaker.step + 1, #steps)
	breaker.state = "open"
	breaker.openUntil = now + (steps[breaker.step] or 30)
	breaker.probing = false
	table.clear(breaker.samples)
	breaker.straight = 0
end

function HttpBudgetPolicy.breakerState(breaker: Breaker, now: number): string
	if breaker.state == "open" and now >= breaker.openUntil then
		return "half_open"
	end
	return breaker.state
end

--- True when a call may go out now. In half-open state exactly one probe is let through.
function HttpBudgetPolicy.breakerAllow(breaker: Breaker, now: number): boolean
	if breaker.state == "closed" then
		return true
	end
	if breaker.state == "open" then
		if now < breaker.openUntil then
			return false
		end
		breaker.state = "half_open"
		breaker.probing = false
	end
	-- half_open
	if breaker.probing then
		return false
	end
	breaker.probing = true
	return true
end

function HttpBudgetPolicy.breakerRecord(breaker: Breaker, now: number, success: boolean)
	if breaker.state == "half_open" or (breaker.state == "open" and now >= breaker.openUntil) then
		if success then
			breaker.state = "closed"
			breaker.step = 0
			breaker.straight = 0
			breaker.probing = false
			table.clear(breaker.samples)
		else
			openBreaker(breaker, now)
		end
		return
	end
	if breaker.state == "open" then
		return -- a late answer from before it opened
	end
	local cfg = breaker.cfg
	if success then
		breaker.straight = 0
	else
		breaker.straight += 1
	end
	table.insert(breaker.samples, { at = now, ok = success })
	local cutoff = now - cfg.windowSec
	local kept = {}
	local failures = 0
	for _, sample in ipairs(breaker.samples) do
		if sample.at > cutoff then
			table.insert(kept, sample)
			if not sample.ok then
				failures += 1
			end
		end
	end
	breaker.samples = kept
	if breaker.straight >= cfg.consecutive then
		openBreaker(breaker, now)
		return
	end
	if #kept >= cfg.minSamples and failures / #kept >= cfg.failRatio then
		openBreaker(breaker, now)
	end
end

--- Transport failure (status 0) or 5xx. 4xx and 429 are not breaker failures.
function HttpBudgetPolicy.isFailureStatus(statusCode: number): boolean
	return statusCode == 0 or statusCode >= 500
end

local function positiveSeconds(value: any): number?
	local n = tonumber(value)
	if n and n > 0 and n == n then
		return n
	end
	return nil
end

--- Seconds to wait from a 429: the JSON body's `retry_after`, else the Retry-After header.
function HttpBudgetPolicy.parseRetryAfter(headers: { [string]: any }?, body: string?): number?
	if type(body) == "string" then
		local fromBody = string.match(body, '"retry_after"%s*:%s*(%-?[%d%.]+)')
		local seconds = positiveSeconds(fromBody)
		if seconds then
			return seconds
		end
	end
	if type(headers) == "table" then
		for name, value in pairs(headers) do
			if type(name) == "string" and string.lower(name) == "retry-after" then
				local seconds = positiveSeconds(value)
				if seconds then
					return seconds
				end
			end
		end
	end
	return nil
end

--- RequestAsync `Timeout` must be a whole number of seconds, at least 1.
function HttpBudgetPolicy.timeoutSeconds(value: number?, default: number): number
	local n = tonumber(value) or default
	return math.max(1, math.floor(n))
end

return HttpBudgetPolicy
