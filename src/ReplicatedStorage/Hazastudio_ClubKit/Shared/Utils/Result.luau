--!strict
-- Shared/Utils/Result.lua

local Types = require(script.Parent.Parent.Domain.Types)

type Result<T> = Types.Result<T>

local Result = {}

function Result.Ok<T>(value: T): Result<T>
	return { ok = true, value = value }
end

function Result.Err<T>(err: string): Result<T>
	return { ok = false, error = err }
end

function Result.withRetry<T>(fn: () -> T, maxAttempts: number): Result<T>
	local lastErr = ""
	for attempt = 1, maxAttempts do
		local ok, value = pcall(fn)
		if ok then
			return Result.Ok(value :: T)
		end
		lastErr = tostring(value)
		if attempt < maxAttempts then
			local baseDelay = 2 ^ attempt         -- 2s, 4s, 8s
			local jitter    = math.random() * 0.5 * baseDelay  -- 0-50% jitter
			task.wait(baseDelay + jitter)
		end
	end
	return Result.Err(("Gagal setelah %d percobaan: %s"):format(maxAttempts, lastErr))
end

return Result
