--!strict
-- Shared/Domain/StreakDomain.lua
-- Pure functions only. Zero Roblox service calls.
-- Semua logika streak di sini - tidak ada di service atau repository.
local StreakDomain = {}
local WIB_OFFSET_SECONDS = 7 * 3600 -- UTC+7
-- ============================================================
-- Konversi os.time() -> hari kalender WIB (angka bulat)
-- Dipakai untuk bandingkan "apakah hari ini sama dengan kemarin"
-- tanpa peduli jam berapa join
-- ============================================================
function StreakDomain.toDayNumber(timestamp: number): number
	return math.floor((timestamp + WIB_OFFSET_SECONDS) / 86400)
end

-- Window donasi harian WIB: 00:01 s/d 23:59:59 (reset otomatis setelah tengah malam WIB).
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
-- Hasil evaluasi streak saat player join
-- ============================================================
export type StreakResult = {
	newStreakDays  : number,
	didIncrement   : boolean, -- true = streak naik hari ini
	didReset       : boolean, -- true = streak di-reset karena skip terlalu lama
	alreadyCounted : boolean, -- true = sudah join hari ini, tidak ada perubahan
}
-- ============================================================
-- evaluateStreak
-- Hitung streak baru berdasarkan lastLoginAt dan waktu sekarang.
--
-- Aturan:
-- - dayDiff == 0 : join hari yang sama -> tidak ada perubahan
-- - dayDiff == 1 : join hari berikutnya -> streak + 1
-- - dayDiff == 2 : grace period (skip 1 hari) -> streak + 1
-- - dayDiff >= 3 : skip terlalu lama -> reset ke 1
-- ============================================================
function StreakDomain.evaluateStreak(
	currentStreak : number,
	lastLoginAt   : number, -- os.time() last login, 0 jika belum pernah
	now           : number  -- os.time() sekarang
): StreakResult
	-- Player baru atau belum pernah login
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
		-- Sudah join hari ini
		return {
			newStreakDays  = currentStreak,
			didIncrement   = false,
			didReset       = false,
			alreadyCounted = true,
		}
	elseif dayDiff <= 2 then
		-- Join hari berikutnya atau masih dalam grace period
		return {
			newStreakDays  = currentStreak + 1,
			didIncrement   = true,
			didReset       = false,
			alreadyCounted = false,
		}
	else
		-- Skip terlalu lama -> reset
		return {
			newStreakDays  = 1,
			didIncrement   = false,
			didReset       = true,
			alreadyCounted = false,
		}
	end
end
return StreakDomain
