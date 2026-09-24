--!strict
-- Shared/Domain/GreetingPacer.luau
--
-- Join greeting pacing (production hardening P4, H11). Pure: the caller passes the clock and
-- Config.PerfDeferred numbers; spec .tmp/greeting-pacer-spec.luau.
--
-- Staff greetings (Leadership / Content) that arrive inside one window wait in a FIFO and go out
-- one per window, so a join storm broadcasts at most one paced greeting per `windowSec`. The
-- client already shows one card at a time (JoinGreetingController queue), so pacing on the server
-- changes neither the wire shape nor what a viewer sees — only when. VIP / donor kinds
-- (`isIndividual`) bypass the pacer. A greeting older than `maxAgeSec` is dropped rather than
-- announced late; over `maxQueue` the oldest waiting one is dropped. windowSec <= 0 = legacy
-- (every greeting immediate).

export type Config = {
	windowSec: number,
	maxQueue: number,
	maxAgeSec: number,
}

type Waiting = { item: any, at: number }

export type State = {
	lastSentAt: number,
	queue: { Waiting },
	droppedCount: number,
}

local GreetingPacer = {}

function GreetingPacer.new(): State
	return { lastSentAt = -math.huge, queue = {}, droppedCount = 0 }
end

function GreetingPacer.isIndividual(categoryKind: string, individualKinds: { [string]: boolean }?): boolean
	return type(individualKinds) == "table" and individualKinds[categoryKind] == true
end

local function pruneStale(state: State, now: number, cfg: Config)
	local queue = state.queue
	while #queue > 0 and now - queue[1].at > cfg.maxAgeSec do
		table.remove(queue, 1)
		state.droppedCount += 1
	end
end

--- Returns `item` when it may be broadcast now, else nil (it waits; call `take` at the wake time).
function GreetingPacer.submit(state: State, item: any, now: number, cfg: Config): any?
	if cfg.windowSec <= 0 then
		state.lastSentAt = now
		return item
	end
	pruneStale(state, now, cfg)
	if #state.queue == 0 and now - state.lastSentAt >= cfg.windowSec then
		state.lastSentAt = now
		return item
	end
	table.insert(state.queue, { item = item, at = now })
	while #state.queue > math.max(1, cfg.maxQueue) do
		table.remove(state.queue, 1)
		state.droppedCount += 1
	end
	return nil
end

--- The waiting greeting due at `now` (or nil), and when to call again (nil = queue empty).
function GreetingPacer.take(state: State, now: number, cfg: Config): (any?, number?)
	pruneStale(state, now, cfg)
	local queue = state.queue
	if #queue == 0 then
		return nil, nil
	end
	local dueAt = state.lastSentAt + math.max(0, cfg.windowSec)
	if now < dueAt then
		return nil, dueAt
	end
	local head = table.remove(queue, 1) :: Waiting
	state.lastSentAt = now
	if #queue == 0 then
		return head.item, nil
	end
	return head.item, now + math.max(0, cfg.windowSec)
end

function GreetingPacer.queued(state: State): number
	return #state.queue
end

function GreetingPacer.dropped(state: State): number
	return state.droppedCount
end

return GreetingPacer
