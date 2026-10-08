--!strict
-- Shared/Domain/EventBoardDomain.luau
-- Event board (ADR 0015): venue posts and venue quests authored in the customer dashboard.
-- Pure functions only — no Roblox services, no Config — so the rules run under lune.
--
-- Days are WIB calendar day numbers (StreakDomain.toDayNumber). A quest runs from its start day
-- to its due day inclusive. Progress per goal:
--   level    — the player's current level (nothing stored);
--   streak   — manual check-ins, the Daily Quest grace/reset rule (DailyQuestDomain);
--   robux    — Robux donated while the quest is running;
--   playtime — seconds online while the quest is running (the goal is in minutes).
-- A reward is claimed once per player per quest; `claimedAt` is the guard.
local DailyQuestDomain = require(script.Parent.DailyQuestDomain)

local EventBoardDomain = {}

EventBoardDomain.GOAL_TYPES = { level = true, streak = true, robux = true, playtime = true }
EventBoardDomain.REWARD_TYPES = { membership = true, title = true, xp = true }
-- Post kinds (2026-10-07). A countdown runs from `startsAt` to `endsAt` (unix seconds); the API
-- fills a missing end with start + 2 h, the kit does the same for an end it cannot use.
EventBoardDomain.POST_KINDS = { announcement = true, countdown = true }
EventBoardDomain.COUNTDOWN_DEFAULT_SECONDS = 2 * 3600

local LIMITS = {
	category = 32,
	postTitle = 80,
	body = 1000,
	questTitle = 60,
	description = 160,
	rewardTitle = 40,
	posts = 30,
	quests = 30,
}
local GOAL_MAX = { level = 10000, streak = DailyQuestDomain.MAX_TARGET_DAYS, robux = 10000000, playtime = 100000 }
local XP_MAX = 1000000
local MEMBERSHIP = { Tier1 = true, Tier2 = true, Tier3 = true }

export type Post = {
	id: number,
	category: string,
	title: string,
	body: string,
	imageAssetId: string,
	showOnJoin: boolean,
	publishedAt: string,
	-- "announcement" | "countdown". Posts from before kinds existed read as announcements.
	kind: string,
	startsAt: number?, -- countdown only
	endsAt: number?, -- countdown only, always after startsAt
	robloxEventId: string, -- Creator Hub Experience Event id, digits; "" = none
}

export type Quest = {
	id: number,
	category: string,
	title: string,
	description: string,
	goalType: string,
	goalValue: number,
	rewardType: string,
	rewardValue: string,
	startDate: string,
	dueDate: string,
	startDay: number,
	dueDay: number,
}

export type Board = { revision: string, posts: { Post }, quests: { Quest } }

export type QuestProgress = {
	progress: number,
	lastDay: number,
	completed: boolean,
	claimedAt: number?,
	-- The quest's due day, stamped when the entry is created (production hardening P3), so the
	-- entry can be pruned 30 days later even after the quest left the board. Additive field.
	dueDay: number?,
	-- Streak quests: the WIB days the player checked in, ascending, unique, at most
	-- DailyQuestDomain.MAX_TARGET_DAYS (oldest dropped). A reset keeps earlier days. Absent on
	-- entries from before 2026-10-07 — checkInDays reconstructs those. Additive field.
	days: { number }?,
}

export type ProgressDoc = {
	quests: { [string]: QuestProgress },
	seenPosts: { [string]: boolean },
}

local function text(value: any, max: number): string?
	if type(value) ~= "string" then
		return nil
	end
	-- Never trust a length the server may have missed: clip, do not reject.
	if utf8.len(value) == nil then
		return nil
	end
	if (utf8.len(value) :: number) > max then
		local cut = utf8.offset(value, max + 1)
		value = string.sub(value, 1, (cut or #value + 1) - 1)
	end
	return value
end

local function positiveInt(value: any, max: number): number?
	if type(value) ~= "number" or value ~= value or value < 1 or value > max or value % 1 ~= 0 then
		return nil
	end
	return value
end

local function readPost(raw: any): Post?
	if type(raw) ~= "table" then
		return nil
	end
	local id = positiveInt(raw.id, 2 ^ 52)
	local title = text(raw.title, LIMITS.postTitle)
	if not id or not title or title == "" then
		return nil
	end
	local asset = if type(raw.imageAssetId) == "string" and string.match(raw.imageAssetId, "^%d+$") and #raw.imageAssetId <= 19
		then raw.imageAssetId
		else ""
	-- A countdown without a usable start cannot count down: it falls back to an announcement
	-- rather than vanishing from the board.
	local kind = "announcement"
	local startsAt: number? = nil
	local endsAt: number? = nil
	if raw.kind == "countdown" and positiveInt(raw.startsAt, 2 ^ 40) then
		kind = "countdown"
		startsAt = raw.startsAt
		endsAt = if positiveInt(raw.endsAt, 2 ^ 40) and raw.endsAt > raw.startsAt
			then raw.endsAt
			else raw.startsAt + EventBoardDomain.COUNTDOWN_DEFAULT_SECONDS
	end
	local eventId = if type(raw.robloxEventId) == "string" and string.match(raw.robloxEventId, "^%d+$") and #raw.robloxEventId <= 32
		then raw.robloxEventId
		else ""
	return {
		id = id,
		category = text(raw.category, LIMITS.category) or "",
		title = title,
		body = text(raw.body, LIMITS.body) or "",
		imageAssetId = asset,
		showOnJoin = raw.showOnJoin == true,
		publishedAt = if type(raw.publishedAt) == "string" then raw.publishedAt else "",
		kind = kind,
		startsAt = startsAt,
		endsAt = endsAt,
		robloxEventId = eventId,
	}
end

local function readQuest(raw: any): Quest?
	if type(raw) ~= "table" or type(raw.goal) ~= "table" or type(raw.reward) ~= "table" then
		return nil
	end
	local id = positiveInt(raw.id, 2 ^ 52)
	local title = text(raw.title, LIMITS.questTitle)
	local goalType = raw.goal.type
	local rewardType = raw.reward.type
	if not id or not title or title == "" then
		return nil
	end
	if type(goalType) ~= "string" or not EventBoardDomain.GOAL_TYPES[goalType] then
		return nil
	end
	local goalValue = positiveInt(raw.goal.value, GOAL_MAX[goalType])
	if not goalValue then
		return nil
	end
	if type(rewardType) ~= "string" or not EventBoardDomain.REWARD_TYPES[rewardType] then
		return nil
	end
	local rewardValue = raw.reward.value
	if rewardType == "membership" then
		if type(rewardValue) ~= "string" or not MEMBERSHIP[rewardValue] then
			return nil
		end
	elseif rewardType == "title" then
		rewardValue = text(rewardValue, LIMITS.rewardTitle)
		if not rewardValue or rewardValue == "" then
			return nil
		end
	else
		local xp = tonumber(rewardValue)
		if not xp or not positiveInt(xp, XP_MAX) then
			return nil
		end
		rewardValue = tostring(xp)
	end
	local startDay = if type(raw.startDate) == "string" then DailyQuestDomain.parseWibDate(raw.startDate) else nil
	local dueDay = if type(raw.dueDate) == "string" then DailyQuestDomain.parseWibDate(raw.dueDate) else nil
	if not startDay or not dueDay or dueDay < startDay then
		return nil
	end
	return {
		id = id,
		category = text(raw.category, LIMITS.category) or "",
		title = title,
		description = text(raw.description, LIMITS.description) or "",
		goalType = goalType,
		goalValue = goalValue,
		rewardType = rewardType,
		rewardValue = rewardValue :: string,
		startDate = raw.startDate,
		dueDate = raw.dueDate,
		startDay = startDay,
		dueDay = dueDay,
	}
end

-- The pulled document, or nil when its shape is wrong. Broken entries are dropped one by one so a
-- single bad row never blanks the board.
function EventBoardDomain.readBoard(raw: any): Board?
	if type(raw) ~= "table" or type(raw.revision) ~= "string" or raw.revision == "" then
		return nil
	end
	if type(raw.posts) ~= "table" or type(raw.quests) ~= "table" then
		return nil
	end
	local posts: { Post } = {}
	for _, entry in ipairs(raw.posts) do
		local post = readPost(entry)
		if post and #posts < LIMITS.posts then
			table.insert(posts, post)
		end
	end
	local quests: { Quest } = {}
	for _, entry in ipairs(raw.quests) do
		local quest = readQuest(entry)
		if quest and #quests < LIMITS.quests then
			table.insert(quests, quest)
		end
	end
	return { revision = raw.revision, posts = posts, quests = quests }
end

function EventBoardDomain.emptyBoard(): Board
	return { revision = "", posts = {}, quests = {} }
end

-- A sanitized board back in the raw shape the VPS sends (readBoard(serializeBoard(b)) == b), for
-- the DataStore copy (production hardening P3, B): only checked fields are stored, and kits that
-- still store/read the raw body read this unchanged.
function EventBoardDomain.serializeBoard(board: Board): { [string]: any }
	local posts = table.create(#board.posts)
	for i, post in ipairs(board.posts) do
		posts[i] = {
			id = post.id,
			category = post.category,
			title = post.title,
			body = post.body,
			imageAssetId = post.imageAssetId,
			showOnJoin = post.showOnJoin,
			publishedAt = post.publishedAt,
			kind = post.kind,
			startsAt = post.startsAt,
			endsAt = post.endsAt,
			robloxEventId = post.robloxEventId,
		}
	end
	local quests = table.create(#board.quests)
	for i, quest in ipairs(board.quests) do
		quests[i] = {
			id = quest.id,
			category = quest.category,
			title = quest.title,
			description = quest.description,
			goal = { type = quest.goalType, value = quest.goalValue },
			reward = { type = quest.rewardType, value = quest.rewardValue },
			startDate = quest.startDate,
			dueDate = quest.dueDate,
		}
	end
	return { revision = board.revision, posts = posts, quests = quests }
end

-- The one post that opens on join, if any.
function EventBoardDomain.joinPost(board: Board): Post?
	for _, post in ipairs(board.posts) do
		if post.showOnJoin then
			return post
		end
	end
	return nil
end

-- Where a post stands at `nowUnix`: announcements have no phase; a countdown is upcoming before
-- its start, live from start until its end, ended from its end on.
function EventBoardDomain.postPhase(post: Post, nowUnix: number): "none" | "upcoming" | "live" | "ended"
	if post.kind ~= "countdown" or not post.startsAt or not post.endsAt then
		return "none"
	end
	if nowUnix < post.startsAt then
		return "upcoming"
	elseif nowUnix < post.endsAt then
		return "live"
	end
	return "ended"
end

-- Posts a player sees: every post except countdowns that have ended. Board order is kept.
function EventBoardDomain.visiblePosts(board: Board, nowUnix: number): { Post }
	local out = {}
	for _, post in ipairs(board.posts) do
		if EventBoardDomain.postPhase(post, nowUnix) ~= "ended" then
			table.insert(out, post)
		end
	end
	return out
end

-- The next unix second at which a post's phase changes (a countdown starting or ending), or nil
-- when no post on the board will change again after `nowUnix`.
function EventBoardDomain.nextPostBoundary(board: Board, nowUnix: number): number?
	local nextAt: number? = nil
	for _, post in ipairs(board.posts) do
		if post.kind == "countdown" then
			for _, at in ipairs({ post.startsAt, post.endsAt }) do
				if at and at > nowUnix and (nextAt == nil or at < nextAt) then
					nextAt = at
				end
			end
		end
	end
	return nextAt
end

function EventBoardDomain.phase(quest: Quest, today: number): "upcoming" | "active" | "ended"
	if today < quest.startDay then
		return "upcoming"
	elseif today > quest.dueDay then
		return "ended"
	end
	return "active"
end

-- Quests a player sees: running ones. Upcoming quests wait, ended ones are gone (ADR 0015).
function EventBoardDomain.visibleQuests(board: Board, today: number): { Quest }
	local out = {}
	for _, quest in ipairs(board.quests) do
		if EventBoardDomain.phase(quest, today) == "active" then
			table.insert(out, quest)
		end
	end
	return out
end

-- ── progress document ────────────────────────────────────────────────────────────────────

function EventBoardDomain.emptyProgress(): ProgressDoc
	return { quests = {}, seenPosts = {} }
end

-- Sorted, unique, bounded copy of a day list (whole positive day numbers only).
local function boundDays(...: { number }?): { number }
	local seen: { [number]: boolean } = {}
	local out: { number } = {}
	for index = 1, select("#", ...) do
		local source = select(index, ...)
		if type(source) == "table" then
			for _, day in ipairs(source) do
				if type(day) == "number" and day >= 1 and day < 2 ^ 31 and day % 1 == 0 and not seen[day] then
					seen[day] = true
					table.insert(out, day)
				end
			end
		end
	end
	table.sort(out)
	local extra = #out - DailyQuestDomain.MAX_TARGET_DAYS
	if extra > 0 then
		table.move(out, extra + 1, #out, 1)
		for index = #out, #out - extra + 1, -1 do
			out[index] = nil
		end
	end
	return out
end

local function copyEntry(entry: QuestProgress): QuestProgress
	local copy = table.clone(entry)
	if entry.days then
		copy.days = table.clone(entry.days)
	end
	return copy
end

local function readQuestProgress(raw: any): QuestProgress?
	if type(raw) ~= "table" then
		return nil
	end
	local progress = if type(raw.progress) == "number" and raw.progress >= 0 and raw.progress < 2 ^ 40
		then math.floor(raw.progress)
		else 0
	local lastDay = if type(raw.lastDay) == "number" and raw.lastDay >= 0 then math.floor(raw.lastDay) else 0
	local claimedAt = if type(raw.claimedAt) == "number" and raw.claimedAt > 0 then raw.claimedAt else nil
	local dueDay = if type(raw.dueDay) == "number" and raw.dueDay > 0 then math.floor(raw.dueDay) else nil
	return {
		progress = progress,
		lastDay = lastDay,
		completed = raw.completed == true,
		claimedAt = claimedAt,
		dueDay = dueDay,
		days = if type(raw.days) == "table" then boundDays(raw.days) else nil,
	}
end

function EventBoardDomain.sanitizeProgress(raw: any): ProgressDoc
	local doc = EventBoardDomain.emptyProgress()
	if type(raw) ~= "table" then
		return doc
	end
	if type(raw.quests) == "table" then
		for key, value in pairs(raw.quests) do
			if type(key) == "string" and string.match(key, "^%d+$") then
				local entry = readQuestProgress(value)
				if entry then
					doc.quests[key] = entry
				end
			end
		end
	end
	if type(raw.seenPosts) == "table" then
		for key, value in pairs(raw.seenPosts) do
			if type(key) == "string" and string.match(key, "^%d+$") and value == true then
				doc.seenPosts[key] = true
			end
		end
	end
	return doc
end

-- Two copies of one player's document (this server's session and what the DataStore holds):
-- the higher counters win and a claim is never lost, so a second server can never re-open one.
function EventBoardDomain.mergeProgress(a: ProgressDoc, b: ProgressDoc): ProgressDoc
	local out = EventBoardDomain.emptyProgress()
	for _, doc in ipairs({ a, b }) do
		for key, entry in pairs(doc.quests) do
			local current = out.quests[key]
			if not current then
				out.quests[key] = copyEntry(entry)
			else
				if entry.progress > current.progress or (entry.progress == current.progress and entry.lastDay > current.lastDay) then
					current.progress = entry.progress
					current.lastDay = entry.lastDay
				end
				current.completed = current.completed or entry.completed
				if entry.claimedAt and (not current.claimedAt or entry.claimedAt < current.claimedAt) then
					current.claimedAt = entry.claimedAt
				end
				if current.dueDay == nil then
					current.dueDay = entry.dueDay
				end
				if current.days or entry.days then
					current.days = boundDays(current.days, entry.days)
				end
			end
		end
		for key in pairs(doc.seenPosts) do
			out.seenPosts[key] = true
		end
	end
	return out
end

local function entryFor(doc: ProgressDoc, quest: Quest): QuestProgress
	local key = tostring(quest.id)
	local entry = doc.quests[key]
	if not entry then
		entry = { progress = 0, lastDay = 0, completed = false, claimedAt = nil, dueDay = quest.dueDay }
		doc.quests[key] = entry
	elseif entry.dueDay == nil then
		entry.dueDay = quest.dueDay
	end
	return entry
end

local function dqQuest(quest: Quest): DailyQuestDomain.Quest
	return { id = tostring(quest.id), targetDays = quest.goalValue, startDay = quest.startDay, dueDay = quest.dueDay }
end

local function dqState(quest: Quest, entry: QuestProgress?): DailyQuestDomain.State?
	if not entry then
		return nil
	end
	return { id = tostring(quest.id), progress = entry.progress, lastDay = entry.lastDay, completed = entry.completed }
end

-- Where a player stands on a quest: `current` against `target`, in the goal's own unit (level,
-- days, Robux, minutes). `level` is the player's current level (only read by level quests).
function EventBoardDomain.standing(quest: Quest, doc: ProgressDoc, level: number, today: number): {
	current: number,
	target: number,
	complete: boolean,
	claimed: boolean,
	checkedInToday: boolean,
}
	local entry = doc.quests[tostring(quest.id)]
	local claimed = entry ~= nil and entry.claimedAt ~= nil
	local target = quest.goalValue
	if quest.goalType == "streak" then
		local view = DailyQuestDomain.view(dqState(quest, entry), dqQuest(quest), today)
		return {
			current = view.progress,
			target = target,
			complete = view.status == "completed",
			claimed = claimed,
			checkedInToday = view.checkedInToday,
		}
	end
	local current = 0
	if quest.goalType == "level" then
		current = math.max(0, math.floor(level))
	elseif quest.goalType == "robux" then
		current = if entry then entry.progress else 0
	elseif quest.goalType == "playtime" then
		current = if entry then entry.progress // 60 else 0
	end
	return {
		current = math.min(current, target),
		target = target,
		complete = current >= target,
		claimed = claimed,
		checkedInToday = false,
	}
end

-- A streak quest's daily press. Mutates `doc`. Returns whether the day counted and whether it
-- completed the quest now.
function EventBoardDomain.checkIn(doc: ProgressDoc, quest: Quest, today: number): (boolean, boolean)
	if quest.goalType ~= "streak" then
		return false, false
	end
	local key = tostring(quest.id)
	local result = DailyQuestDomain.evaluateCheckIn(dqState(quest, doc.quests[key]), dqQuest(quest), today)
	if not result.counted or not result.state then
		return false, false
	end
	local entry = entryFor(doc, quest)
	-- An entry from before check-in days were stored keeps its history: seed it first.
	local days = EventBoardDomain.checkInDays(quest, entry)
	entry.progress = result.state.progress
	entry.lastDay = result.state.lastDay
	entry.completed = result.state.completed
	table.insert(days, today)
	entry.days = boundDays(days)
	return true, result.completedNow
end

-- Robux donated or seconds played while the quest runs. Mutates `doc`. Returns whether it counted.
function EventBoardDomain.addAmount(doc: ProgressDoc, quest: Quest, goalType: string, amount: number, today: number): boolean
	if quest.goalType ~= goalType or amount <= 0 or EventBoardDomain.phase(quest, today) ~= "active" then
		return false
	end
	local entry = entryFor(doc, quest)
	if entry.claimedAt then
		return false
	end
	-- Counting stops at the goal: nothing past it changes what the card shows.
	local cap = if goalType == "playtime" then quest.goalValue * 60 else quest.goalValue
	if entry.progress >= cap then
		return false
	end
	entry.progress = math.min(cap, entry.progress + math.floor(amount))
	return true
end

-- "ok" or why not: "not_active" | "incomplete" | "claimed".
function EventBoardDomain.canClaim(quest: Quest, doc: ProgressDoc, level: number, today: number): string
	if EventBoardDomain.phase(quest, today) ~= "active" then
		return "not_active"
	end
	local standing = EventBoardDomain.standing(quest, doc, level, today)
	if standing.claimed then
		return "claimed"
	end
	if not standing.complete then
		return "incomplete"
	end
	return "ok"
end

function EventBoardDomain.markClaimed(doc: ProgressDoc, quest: Quest, now: number)
	entryFor(doc, quest).claimedAt = now
end

-- The WIB days a player checked in on a streak quest: the stored list, or for an entry from
-- before that list existed, the run it implies — `progress` consecutive days ending on `lastDay`,
-- never before the quest's start day. Always a fresh list the caller may change.
function EventBoardDomain.checkInDays(quest: Quest, entry: QuestProgress?): { number }
	if not entry then
		return {}
	end
	if entry.days then
		return table.clone(entry.days)
	end
	local out: { number } = {}
	if entry.progress <= 0 or entry.lastDay <= 0 then
		return out
	end
	for day = math.max(quest.startDay, entry.lastDay - entry.progress + 1), entry.lastDay do
		table.insert(out, day)
	end
	return out
end

export type CalendarCell = {
	day: number,
	dom: number,
	month: number,
	year: number,
	state: "done" | "today" | "missed" | "upcoming",
}

export type Calendar = {
	leadBlanks: number,
	cells: { CalendarCell },
	todayIndex: number?,
	-- True when the cells do not begin at the start day / end at the due day (a long window
	-- clipped to CALENDAR_MAX_DAYS): that edge gets no START / FINISH marker.
	clippedStart: boolean,
	clippedEnd: boolean,
}

-- The calendar draws at most six Su–Sa weeks; a longer window shows the six around today.
EventBoardDomain.CALENDAR_MAX_DAYS = 42
-- Within a clipped window, today's week is this row (0-based) when the window allows: two weeks
-- of history above it, three ahead.
local CALENDAR_TODAY_ROW = 2

-- Day 0 (1970-01-01) was a Thursday: weekday with Sunday = 0.
local function weekday(day: number): number
	return (day + 4) % 7
end

-- The attendance calendar of a streak quest: one cell per day from the start day to the due day,
-- laid out Sunday-first (`leadBlanks` empty slots before the first cell).
-- done = checked in; today = today, not yet checked in; missed = an earlier day without a
-- check-in; upcoming = a later day. `todayIndex` is nil when today is not among the cells.
-- A window longer than CALENDAR_MAX_DAYS draws six whole weeks containing today, kept inside the
-- window: before the start the first six weeks, once the window has passed the last six.
function EventBoardDomain.calendar(quest: Quest, doc: ProgressDoc, today: number): Calendar
	local done: { [number]: boolean } = {}
	for _, day in ipairs(EventBoardDomain.checkInDays(quest, doc.quests[tostring(quest.id)])) do
		done[day] = true
	end
	local firstDay, lastDay = quest.startDay, quest.dueDay
	if lastDay - firstDay + 1 > EventBoardDomain.CALENDAR_MAX_DAYS then
		local firstRow = firstDay - weekday(firstDay)
		local lastRow = lastDay - weekday(lastDay)
		local anchor = math.clamp(today, firstDay, lastDay)
		local spanStart = anchor - weekday(anchor) - CALENDAR_TODAY_ROW * 7
		-- A window over 42 days covers at least seven rows, so this range is never empty.
		spanStart = math.clamp(spanStart, firstRow, lastRow - (EventBoardDomain.CALENDAR_MAX_DAYS - 7))
		firstDay = math.max(firstDay, spanStart)
		lastDay = math.min(lastDay, spanStart + EventBoardDomain.CALENDAR_MAX_DAYS - 1)
	end
	local cells: { CalendarCell } = table.create(lastDay - firstDay + 1)
	local todayIndex: number? = nil
	for day = firstDay, lastDay do
		local year, month, dom = DailyQuestDomain.toCivil(day)
		local state: "done" | "today" | "missed" | "upcoming" = if done[day]
			then "done"
			elseif day == today then "today"
			elseif day < today then "missed"
			else "upcoming"
		table.insert(cells, { day = day, dom = dom, month = month, year = year, state = state })
		if day == today then
			todayIndex = #cells
		end
	end
	return {
		leadBlanks = weekday(firstDay),
		cells = cells,
		todayIndex = todayIndex,
		clippedStart = firstDay > quest.startDay,
		clippedEnd = lastDay < quest.dueDay,
	}
end

-- Seconds until the next WIB midnight, for the check-in countdown.
function EventBoardDomain.secondsUntilNextDay(unixSeconds: number): number
	local wib = unixSeconds + 7 * 3600
	return 86400 - (wib % 86400)
end

-- Keeps a venue progress document bounded (production hardening P3, A8). Returns a pruned copy:
--   * a quest entry goes 30 (keepDays) days after its due day — the entry's stamped dueDay, or
--     the board's for older entries of quests still on it;
--   * an entry with no known due day goes only when its claim is older than keepDays (a server
--     with a stale board must never drop progress another server is counting);
--   * seenPosts keeps the posts on the board plus the newest ids, maxSeenPosts in total.
-- Claims are safe: a quest past its due day can no longer be claimed (canClaim → not_active).
function EventBoardDomain.pruneProgress(
	doc: ProgressDoc,
	board: Board,
	today: number,
	nowUnix: number,
	cfg: { keepDays: number, maxSeenPosts: number }
): ProgressDoc
	local boardDue: { [string]: number } = {}
	for _, quest in ipairs(board.quests) do
		boardDue[tostring(quest.id)] = quest.dueDay
	end
	local out = EventBoardDomain.emptyProgress()
	for key, entry in pairs(doc.quests) do
		local dueDay = entry.dueDay or boardDue[key]
		local keep = true
		if dueDay then
			keep = today <= dueDay + cfg.keepDays
		elseif entry.claimedAt then
			keep = nowUnix - entry.claimedAt <= cfg.keepDays * 86400
		end
		if keep then
			out.quests[key] = copyEntry(entry)
		end
	end
	local onBoard: { [string]: boolean } = {}
	for _, post in ipairs(board.posts) do
		onBoard[tostring(post.id)] = true
	end
	local others: { number } = {}
	local count = 0
	for key in pairs(doc.seenPosts) do
		if onBoard[key] then
			out.seenPosts[key] = true
			count += 1
		else
			table.insert(others, tonumber(key) or 0)
		end
	end
	table.sort(others, function(a, b)
		return a > b
	end)
	for _, id in ipairs(others) do
		if count >= cfg.maxSeenPosts then
			break
		end
		out.seenPosts[tostring(id)] = true
		count += 1
	end
	return out
end

return EventBoardDomain
