--!strict
-- Shared/Utils/RateLimiter.luau
--
-- Token bucket rate limiter. Smooth rate without boundary burst exploit.
--
-- Why token bucket over fixed window:
-- Fixed window allows 2x burst at window boundaries (e.g., fire max at T=0,
-- window resets at T=1, fire max again → effective 2x rate in ~1s).
-- Token bucket refills gradually, enforcing a smooth average rate.
--
-- API: RateLimiter.new(max, window) → same as before, drop-in replacement.
--   max:    maximum tokens (burst capacity)
--   window: seconds to refill from 0 to max
--   refill rate = max / window tokens per second

type Bucket = {
	tokens    : number,
	lastRefill: number,
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

type RateLimiterImpl = {
	_max           : number,
	_window        : number,
	_refillRate    : number,
	_buckets       : { [number]: Bucket },
	_cleanupThread : thread,
	_running       : boolean,
	check          : (self: RateLimiterImpl, userId: number) -> (boolean, string?),
	cleanup        : (self: RateLimiterImpl) -> (),
	destroy        : (self: RateLimiterImpl) -> (),
}

function RateLimiter.new(max: number, window: number): RateLimiterImpl
	local self = setmetatable({}, RateLimiter) :: any
	self._max = max
	self._window = window
	self._refillRate = max / window
	self._buckets = {}
	self._running = true
	self._cleanupThread = task.spawn(function()
		while self._running do
			task.wait(300)
			if self._running then
				self:cleanup()
			end
		end
	end)
	return self
end

function RateLimiter:check(userId: number): (boolean, string?)
	local now = os.clock()
	local b = self._buckets[userId]

	if not b then
		self._buckets[userId] = { tokens = self._max - 1, lastRefill = now }
		return true, nil
	end

	-- Refill tokens based on elapsed time
	local elapsed = now - b.lastRefill
	if elapsed > 0 then
		local refill = elapsed * self._refillRate
		b.tokens = math.min(self._max, b.tokens + refill)
		b.lastRefill = now
	end

	if b.tokens < 1 then
		local deficit = 1 - b.tokens
		local waitSec = math.ceil(deficit / self._refillRate)
		return false, ("Rate limit. Tunggu %ds"):format(waitSec)
	end

	b.tokens -= 1
	return true, nil
end

function RateLimiter:cleanup()
	local now = os.clock()
	local cutoff = now - self._window * 2
	for id, b in pairs(self._buckets) do
		if b.lastRefill < cutoff then
			self._buckets[id] = nil
		end
	end
end

function RateLimiter:destroy()
	self._running = false
	task.cancel(self._cleanupThread)
	table.clear(self._buckets)
end

return RateLimiter
