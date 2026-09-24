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
EventBoardDomain.STRIP_DAYS = 6

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
	return {
		id = id,
		category = text(raw.category, LIMITS.category) or "",
		title = title,
		body = text(raw.body, LIMITS.body) or "",
		imageAssetId = asset,
		showOnJoin = raw.showOnJoin == true,
		publishedAt = if type(raw.publishedAt) == "string" then raw.publishedAt else "",
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
				out.quests[key] = table.clone(entry)
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
	entry.progress = result.state.progress
	entry.lastDay = result.state.lastDay
	entry.completed = result.state.completed
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

-- The streak card's six squares: today and the next five days (owner, 2026-09-24). Today is
-- "done" once checked in, otherwise "today"; the rest are "upcoming"; days past the due date are
-- "closed".
function EventBoardDomain.dayStrip(quest: Quest, doc: ProgressDoc, today: number): { string }
	local entry = doc.quests[tostring(quest.id)]
	local out = {}
	for offset = 0, EventBoardDomain.STRIP_DAYS - 1 do
		local day = today + offset
		if day > quest.dueDay then
			out[offset + 1] = "closed"
		elseif offset == 0 then
			out[offset + 1] = if entry and entry.lastDay == today then "done" else "today"
		else
			out[offset + 1] = "upcoming"
		end
	end
	return out
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
			out.quests[key] = table.clone(entry)
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
