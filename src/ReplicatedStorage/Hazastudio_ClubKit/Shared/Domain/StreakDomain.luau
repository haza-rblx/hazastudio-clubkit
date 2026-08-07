--!strict
-- Shared/Domain/StreakDomain.lua
-- Pure functions only. Zero Roblox service calls.
-- All streak logic lives here — not in service or repository.
local StreakDomain = {}
local WIB_OFFSET_SECONDS = 7 * 3600 -- UTC+7
-- ============================================================
-- Convert os.time() -> WIB calendar day (integer)
-- Used to compare whether today is the same as yesterday
-- regardless of join time
-- ============================================================
function StreakDomain.toDayNumber(timestamp: number): number
	return math.floor((timestamp + WIB_OFFSET_SECONDS) / 86400)
end

-- WIB daily donation window: 00:01 to 23:59:59 (auto-resets after WIB midnight).
function StreakDomain.getWibDailyDonationWindow(timestamp: number): (number, number)
	local dayNumber = StreakDomain.toDayNumber(timestamp)
	local dayStart = dayNumber * 86400 - WIB_OFFSET_SECONDS
	return dayStart + 60, dayStart + 86400 - 1
end

function StreakDomain.isWithinWibDailyDonationWindow(timestamp: number): boolean
	local windowStart, windowEnd = StreakDomain.getWibDailyDonationWindow(timestamp)
	return timestamp >= windowStart and timestamp <= windowEnd
end
-- ============================================================
-- Streak evaluation result when player joins
-- ============================================================
export type StreakResult = {
	newStreakDays  : number,
	didIncrement   : boolean, -- true = streak incremented today
	didReset       : boolean, -- true = streak reset because the gap was too long
	alreadyCounted : boolean, -- true = already joined today, no change
}
-- ============================================================
-- evaluateStreak
-- Compute new streak based on lastLoginAt and current time.
--
-- Rules:
-- - dayDiff == 0 : same-day join -> no change
-- - dayDiff == 1 : next-day join -> streak + 1
-- - dayDiff == 2 : grace period (skip 1 day) -> streak + 1
-- - dayDiff >= 3 : gap too old -> reset to 1
-- ============================================================
function StreakDomain.evaluateStreak(
	currentStreak : number,
	lastLoginAt   : number, -- os.time() last login, 0 if never logged in before
	now           : number  -- os.time() now
): StreakResult
	-- New player or never logged in before
	if lastLoginAt == 0 then
		return {
			newStreakDays  = 1,
			didIncrement   = true,
			didReset       = false,
			alreadyCounted = false,
		}
	end
	local dayNow  = StreakDomain.toDayNumber(now)
	local dayLast = StreakDomain.toDayNumber(lastLoginAt)
	local dayDiff = dayNow - dayLast
	if dayDiff == 0 then
		-- Already joined today
		return {
			newStreakDays  = currentStreak,
			didIncrement   = false,
			didReset       = false,
			alreadyCounted = true,
		}
	elseif dayDiff <= 2 then
		-- Join next day or still within grace period
		return {
			newStreakDays  = currentStreak + 1,
			didIncrement   = true,
			didReset       = false,
			alreadyCounted = false,
		}
	else
		-- Gap too old -> reset
		return {
			newStreakDays  = 1,
			didIncrement   = false,
			didReset       = true,
			alreadyCounted = false,
		}
	end
end
return StreakDomain
