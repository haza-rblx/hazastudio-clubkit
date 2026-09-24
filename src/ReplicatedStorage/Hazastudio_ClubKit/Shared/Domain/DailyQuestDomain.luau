--!strict
-- Shared/Domain/DailyQuestDomain.luau
-- Daily Quest addon (1000-02-DQ-ADDON): quest window, progress counter, completion.
-- Pure functions only. Zero Roblox service calls, zero Config — callers pass the quest in.
--
-- Days are WIB calendar day numbers, the same "today" StreakDomain.toDayNumber gives, so a
-- quest day and a streak day always turn over together. Progress follows the streak rule:
-- the next day or one skipped day adds one, two or more skipped days start over at 1.
local DailyQuestDomain = {}

-- A quest longer than this is a typo, and every day is one circle in the panel grid.
DailyQuestDomain.MAX_TARGET_DAYS = 100
-- Gap (in days) at or above which progress starts over. Mirrors StreakDomain's reset rule.
local RESET_GAP = 3

export type Quest = {
	id: string,
	targetDays: number,
	startDay: number,
	dueDay: number,
}

export type State = {
	id: string,
	progress: number,
	lastDay: number,
	completed: boolean,
}

export type CheckInResult = {
	state: State?,
	counted: boolean,
	didReset: boolean,
	completedNow: boolean,
}

export type View = {
	status: "none" | "upcoming" | "active" | "ended" | "completed",
	progress: number,
	target: number,
	checkedInToday: boolean,
}

-- Days since 1970-01-01 for a proleptic Gregorian date (Hinnant's days_from_civil).
local function daysFromCivil(y: number, m: number, d: number): number
	y = if m <= 2 then y - 1 else y
	local era = (if y >= 0 then y else y - 399) // 400
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = (153 * mp + 2) // 5 + d - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	return era * 146097 + doe - 719468
end

function DailyQuestDomain.toCivil(day: number): (number, number, number)
	local z = day + 719468
	local era = (if z >= 0 then z else z - 146096) // 146097
	local doe = z - era * 146097
	local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
	local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
	local mp = (5 * doy + 2) // 153
	local d = doy - (153 * mp + 2) // 5 + 1
	local m = if mp < 10 then mp + 3 else mp - 9
	local y = yoe + era * 400
	return (if m <= 2 then y + 1 else y), m, d
end

-- "YYYY-MM-DD" -> WIB day number, or nil for anything that is not a real date.
function DailyQuestDomain.parseWibDate(raw: any): number?
	if type(raw) ~= "string" then
		return nil
	end
	local ys, ms, ds = string.match(raw, "^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s*$")
	if not ys then
		return nil
	end
	local y, m, d = tonumber(ys) :: number, tonumber(ms) :: number, tonumber(ds) :: number
	if m < 1 or m > 12 or d < 1 or d > 31 then
		return nil
	end
	local day = daysFromCivil(y, m, d)
	-- Round-trip rejects 2026-02-29, 2026-04-31 and friends.
	local ry, rm, rd = DailyQuestDomain.toCivil(day)
	if ry ~= y or rm ~= m or rd ~= d then
		return nil
	end
	return day
end

-- Buyer-shaped quest ({ Id, TargetDays, StartDate, DueDate }) -> Quest, or nil when it cannot run.
function DailyQuestDomain.normalizeQuest(raw: any): Quest?
	if type(raw) ~= "table" then
		return nil
	end
	local id = raw.Id
	if type(id) ~= "string" or id == "" then
		return nil
	end
	local target = tonumber(raw.TargetDays)
	if not target or target < 1 then
		return nil
	end
	local startDay = DailyQuestDomain.parseWibDate(raw.StartDate)
	local dueDay = DailyQuestDomain.parseWibDate(raw.DueDate)
	if not startDay or not dueDay or dueDay < startDay then
		return nil
	end
	return {
		id = id,
		targetDays = math.min(math.floor(target), DailyQuestDomain.MAX_TARGET_DAYS),
		startDay = startDay,
		dueDay = dueDay,
	}
end

-- Stored `dailyQuest` field -> State, or nil when there is nothing usable.
function DailyQuestDomain.sanitizeState(raw: any): State?
	if type(raw) ~= "table" or type(raw.id) ~= "string" or raw.id == "" then
		return nil
	end
	local progress = tonumber(raw.progress)
	local lastDay = tonumber(raw.lastDay)
	return {
		id = raw.id,
		progress = if progress and progress > 0 then math.floor(progress) else 0,
		lastDay = if lastDay and lastDay > 0 then math.floor(lastDay) else 0,
		completed = raw.completed == true,
	}
end

local function stateFor(state: State?, quest: Quest): State
	if state and state.id == quest.id then
		return table.clone(state)
	end
	return { id = quest.id, progress = 0, lastDay = 0, completed = false }
end

local function inWindow(quest: Quest, today: number): boolean
	return today >= quest.startDay and today <= quest.dueDay
end

-- One check-in on `today`. Never mutates `state`. `counted` is true only when progress moved.
function DailyQuestDomain.evaluateCheckIn(state: State?, quest: Quest?, today: number): CheckInResult
	local unchanged: CheckInResult = { state = state, counted = false, didReset = false, completedNow = false }
	if not quest or not inWindow(quest, today) then
		return unchanged
	end
	local current = stateFor(state, quest)
	if current.completed or current.lastDay == today then
		unchanged.state = current
		return unchanged
	end

	local didReset = false
	if current.lastDay == 0 or today - current.lastDay >= RESET_GAP then
		didReset = current.progress > 0
		current.progress = 1
	else
		current.progress += 1
	end
	current.lastDay = today

	local completedNow = false
	if current.progress >= quest.targetDays then
		current.progress = quest.targetDays
		current.completed = true
		completedNow = true
	end
	return { state = current, counted = true, didReset = didReset, completedNow = completedNow }
end

-- What the panel paints. A lapsed run shows 0 — the value the next check-in starts from — so
-- the circles never promise progress that the next press would wipe.
function DailyQuestDomain.view(state: State?, quest: Quest?, today: number): View
	if not quest then
		return { status = "none", progress = 0, target = 0, checkedInToday = false }
	end
	local current = stateFor(state, quest)
	local target = quest.targetDays
	if current.completed then
		return { status = "completed", progress = target, target = target, checkedInToday = current.lastDay == today }
	end
	local checkedInToday = current.lastDay == today
	local progress = current.progress
	if current.lastDay > 0 and today - current.lastDay >= RESET_GAP then
		progress = 0
	end
	local status: "upcoming" | "active" | "ended" = if today < quest.startDay
		then "upcoming"
		elseif today > quest.dueDay then "ended"
		else "active"
	return { status = status, progress = progress, target = target, checkedInToday = checkedInToday }
end

return DailyQuestDomain
