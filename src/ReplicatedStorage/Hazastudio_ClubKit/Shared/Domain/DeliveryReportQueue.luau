--!strict
-- Shared/Domain/DeliveryReportQueue.luau
--
-- ReliabilityV2 delivery reports, batched (production hardening P3, workstream C3). Until P3 every
-- client ack and every on-screen display was its own POST (≈ 400 POSTs per donation at 200
-- players). DonationService now queues them here and flushes each kind every `flushSec` or at
-- `flushMax` entries (the VPS accepts up to 200 per POST).
--   * Deduped by (kind, donationId, userId), also against entries flushed in the last recentTtlSec.
--   * A display must name a donation this server fired (markKnown) — a client cannot invent rows.
--   * Each player may report at most playerMaxEvents per playerWindowSec (both kinds together).
--   * At most maxQueue entries wait per kind; beyond that new ones are dropped (queue_full).
-- Pure: the caller passes the clock. Spec: .tmp/delivery-report-queue-spec.luau.

export type Config = {
	flushSec: number,
	flushMax: number,
	playerMaxEvents: number,
	playerWindowSec: number,
	maxQueue: number,
	recentTtlSec: number,
	knownTtlSec: number,
}

export type Queue = {
	cfg: Config,
	queues: { [string]: { any } },
	recent: { [string]: number }, -- key -> expiresAt
	recentCount: number,
	known: { [number]: number }, -- donationId -> expiresAt
	playerEvents: { [number]: { number } }, -- userId -> timestamps in the window
}

local DeliveryReportQueue = {}

function DeliveryReportQueue.new(cfg: Config): Queue
	return {
		cfg = cfg,
		queues = { ack = {}, display = {} },
		recent = {},
		recentCount = 0,
		known = {},
		playerEvents = {},
	}
end

--- The server fired this donation to clients: displays for it are accepted for knownTtlSec.
function DeliveryReportQueue.markKnown(q: Queue, donationId: number, now: number)
	q.known[donationId] = now + q.cfg.knownTtlSec
end

function DeliveryReportQueue.isKnown(q: Queue, donationId: number, now: number): boolean
	local expiresAt = q.known[donationId]
	return expiresAt ~= nil and expiresAt >= now
end

local function takePlayerSlot(q: Queue, userId: number, now: number): boolean
	local cutoff = now - q.cfg.playerWindowSec
	local events = q.playerEvents[userId] or {}
	local kept = {}
	for _, at in ipairs(events) do
		if at > cutoff then
			table.insert(kept, at)
		end
	end
	if #kept >= q.cfg.playerMaxEvents then
		q.playerEvents[userId] = kept
		return false
	end
	table.insert(kept, now)
	q.playerEvents[userId] = kept
	return true
end

--- Queues one report. Returns (true) or (false, "duplicate" | "unknown_donation" | "rate_limited" | "queue_full").
function DeliveryReportQueue.push(
	q: Queue,
	kind: string,
	donationId: number,
	userId: number,
	entry: any,
	now: number
): (boolean, string?)
	local list = q.queues[kind]
	if not list then
		list = {}
		q.queues[kind] = list
	end
	local key = kind .. ":" .. tostring(donationId) .. ":" .. tostring(userId)
	local seenUntil = q.recent[key]
	if seenUntil and seenUntil >= now then
		return false, "duplicate"
	end
	if kind == "display" and not DeliveryReportQueue.isKnown(q, donationId, now) then
		return false, "unknown_donation"
	end
	if #list >= q.cfg.maxQueue then
		return false, "queue_full"
	end
	if not takePlayerSlot(q, userId, now) then
		return false, "rate_limited"
	end
	if seenUntil == nil then
		q.recentCount += 1
	end
	q.recent[key] = now + q.cfg.recentTtlSec
	table.insert(list, entry)
	return true, nil
end

function DeliveryReportQueue.size(q: Queue, kind: string): number
	local list = q.queues[kind]
	return if list then #list else 0
end

--- Time to send: any kind has flushMax entries, or entries wait and flushSec has passed.
function DeliveryReportQueue.shouldFlush(q: Queue, now: number, lastFlushAt: number): boolean
	local any = false
	for _, list in pairs(q.queues) do
		if #list >= q.cfg.flushMax then
			return true
		end
		if #list > 0 then
			any = true
		end
	end
	return any and now - lastFlushAt >= q.cfg.flushSec
end

--- Removes and returns up to `max` queued entries of `kind`, oldest first.
function DeliveryReportQueue.take(q: Queue, kind: string, max: number): { any }
	local list = q.queues[kind]
	if not list or #list == 0 then
		return {}
	end
	local n = math.min(#list, math.max(0, max))
	local out = table.move(list, 1, n, 1, {})
	local rest = table.move(list, n + 1, #list, 1, {})
	q.queues[kind] = rest
	return out
end

function DeliveryReportQueue.recentCount(q: Queue): number
	return q.recentCount
end

--- Forgets expired dedupe keys, known donations and idle players (bounded memory).
function DeliveryReportQueue.prune(q: Queue, now: number)
	for key, expiresAt in pairs(q.recent) do
		if expiresAt < now then
			q.recent[key] = nil
			q.recentCount -= 1
		end
	end
	for donationId, expiresAt in pairs(q.known) do
		if expiresAt < now then
			q.known[donationId] = nil
		end
	end
	local cutoff = now - q.cfg.playerWindowSec
	for userId, events in pairs(q.playerEvents) do
		local last = events[#events]
		if last == nil or last <= cutoff then
			q.playerEvents[userId] = nil
		end
	end
end

return DeliveryReportQueue
