--!strict
-- Shared/Domain/FlushPolicy.luau
--
-- When a dirty player document gets written (production hardening P3, workstream A1). Pure: the
-- caller passes the clock and Config.PlayerDocWriter numbers; spec .tmp/flush-policy-spec.luau.
--
--   normal (XP ticks): every player owns one fixed phase inside the 90 s interval
--     (userId % intervalSec). A dirty document is written at the first phase slot that is not
--     before it became dirty and not inside the 7 s gap after its last write. Continuously dirty
--     documents are written exactly 90 s apart (owner decision K1: the crash window), and a crowd
--     that joined in the same second is spread over the whole interval.
--   urgent (level-up, title, membership, role, currency, leave): max(now + debounce, last + gap).
--   Roblox allows one write per key per 6 s; the gap is 7 s.
--
-- A 1 Hz scheduler (Server/Persistence/PlayerDocWriter) writes at most tickBudget(dirty) due
-- documents per tick, urgent ones first, then the longest overdue.

export type Config = {
	intervalSec: number,
	minGapSec: number,
	urgentDebounceSec: number,
	tickBase: number,
	tickDivisor: number,
}

export type DueItem = { key: string, dueAt: number, urgent: boolean }

local FlushPolicy = {}

function FlushPolicy.normalDueAt(userId: number, dirtySince: number, lastWriteAt: number, cfg: Config): number
	local interval = math.max(1, cfg.intervalSec)
	local phase = math.floor(userId) % interval
	local lower = math.max(dirtySince, lastWriteAt + cfg.minGapSec)
	-- first t >= lower with t ≡ phase (mod interval)
	local cycleStart = lower - (lower % interval)
	local t = cycleStart + phase
	if t < lower then
		t += interval
	end
	return t
end

function FlushPolicy.urgentDueAt(now: number, lastWriteAt: number, cfg: Config): number
	return math.max(now + cfg.urgentDebounceSec, lastWriteAt + cfg.minGapSec)
end

--- Seconds a direct writer must wait so two writes to one key stay `minGap` apart.
function FlushPolicy.gapWait(lastWriteAt: number, now: number, minGap: number): number
	return math.max(0, lastWriteAt + minGap - now)
end

--- Writes allowed in one scheduler tick with `dirtyCount` dirty documents.
function FlushPolicy.tickBudget(dirtyCount: number, cfg: Config): number
	return math.ceil(math.max(0, dirtyCount) / math.max(1, cfg.tickDivisor)) + cfg.tickBase
end

--- Keys due at `now`, urgent first, then oldest due first, at most `budget`.
function FlushPolicy.selectDue(items: { DueItem }, now: number, budget: number): { string }
	local due: { DueItem } = {}
	for _, item in ipairs(items) do
		if item.dueAt <= now then
			table.insert(due, item)
		end
	end
	table.sort(due, function(a, b)
		if a.urgent ~= b.urgent then
			return a.urgent
		end
		if a.dueAt ~= b.dueAt then
			return a.dueAt < b.dueAt
		end
		return a.key < b.key
	end)
	local out: { string } = {}
	for i = 1, math.min(#due, math.max(0, budget)) do
		out[i] = due[i].key
	end
	return out
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in pairs(a) do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end
	return true
end

--- True when `after` differs from `before` only in `fields` (e.g. {"xp", "_version"}): such a
--- change is neither urgent nor worth telling other servers about.
function FlushPolicy.isOnlyFields(before: any, after: any, fields: { string }): boolean
	if type(before) ~= "table" or type(after) ~= "table" then
		return false
	end
	local ignored: { [string]: boolean } = {}
	for _, name in ipairs(fields) do
		ignored[name] = true
	end
	for key, value in pairs(before) do
		if not ignored[key] and not deepEqual(value, after[key]) then
			return false
		end
	end
	for key in pairs(after) do
		if not ignored[key] and before[key] == nil then
			return false
		end
	end
	return true
end

return FlushPolicy
