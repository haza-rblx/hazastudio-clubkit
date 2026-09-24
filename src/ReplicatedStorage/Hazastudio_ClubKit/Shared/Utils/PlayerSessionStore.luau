--!strict
-- Shared/Utils/PlayerSessionStore.luau
--
-- In-memory session documents with dirty fingerprint + debounced durable flush.
-- Used by Overhead/Settings write-behind (Persistence Fabric Phase 2).
--
-- Contract:
--   hydrate(ns, userId, data) — after successful load
--   get / applyMutator — memory-only; applyMutator returns changed=false if fingerprint same
--   scheduleFlush — coalesce durable writes
--   flushNow / flushNamespace / flushAll — autosave / BindToClose
--   invalidate — cross-server "someone else wrote this document": a clean session is dropped
--     (next read reloads); a dirty one is KEPT and marked stale, so its unsaved changes are not
--     lost; its next flush replays them onto the stored document (production hardening P1).
--   release — player left: flush, then drop the slot; a failed flush keeps the dirty entry and
--     retries (Config.Persistence.LEAVE_FLUSH_RETRY_DELAYS); autosave/BindToClose still see it.
--
-- Replay: every applyMutator that changes the document records its mutator until the next
-- successful flush. The flush fn receives `context.replay(base)` which re-applies those mutators
-- to `base` (the document currently stored); repositories use it inside the UpdateAsync transform
-- when the session is stale or the stored `_version` is newer. More than MAX_PENDING_MUTATORS
-- unsaved mutators turn replay off for that session until it flushes (whole-document write, the
-- pre-2026-09-24 behaviour).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Result = require(script.Parent.Result)
local BudgetMeter = require(script.Parent.BudgetMeter)
local Types = require(script.Parent.Parent.Domain.Types)

type Result<T> = Types.Result<T>

export type Mutator = (current: any) -> any

export type FlushContext = {
	-- Another server wrote this document after we loaded it (cross-server invalidate).
	stale: boolean,
	-- Re-applies this session's unsaved mutators, in order, onto `base`. Nil when replay is off.
	replay: ((base: any) -> any)?,
}

-- May return Ok(writtenDocument) when it wrote something other than `data` (a replay);
-- Ok(nil) means `data` itself was written.
export type FlushFn = (userId: number, data: any, context: FlushContext) -> Result<any>

export type ReleaseOptions = {
	-- True when the player is back in this server; a pending release is then abandoned
	-- (the session is live again and the normal flush path owns it).
	isPresent: (() -> boolean)?,
	retryDelays: { number }?,
}

type SessionEntry = {
	data: any,
	fingerprint: string, -- fingerprint of the last durable (flushed/loaded) document
	dirty: boolean,
	flushScheduled: boolean,
	generation: number,
	flushing: boolean,
	pending: { Mutator },
	replayable: boolean,
	stale: boolean,
	staleMarks: number,
	releasing: boolean,
	releaseStartedAt: number,
}

local DEFAULT_MAX_PENDING_MUTATORS = 256
local DEFAULT_MAX_DEPARTED = 400
local DEFAULT_RELEASE_RETRY_DELAYS = { 2, 4, 8, 16, 30 }

local sessions: { [string]: SessionEntry } = {}
local flushFns: { [string]: FlushFn } = {}
local metrics = {
	skipNoOp = 0,
	scheduled = 0,
	flushed = 0,
	flushFailed = 0,
	replayed = 0,
	staleKept = 0,
	releaseRetries = 0,
	releaseGaveUp = 0,
	departedDropped = 0,
}

local function persistenceConfig()
	local p = Config.Persistence
	if type(p) ~= "table" then
		return {
			SESSION_FLUSH_DEBOUNCE = 3,
			SESSION_WRITE_BEHIND_ENABLED = true,
		}
	end
	return p
end

local function sessionKey(namespace: string, userId: number): string
	return namespace .. "::" .. tostring(userId)
end

local function fingerprintOf(data: any): string
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(data)
	end)
	if ok and type(encoded) == "string" then
		return encoded
	end
	return tostring(data)
end

local function newEntry(data: any): SessionEntry
	return {
		data = data,
		fingerprint = fingerprintOf(data),
		dirty = false,
		flushScheduled = false,
		generation = 0,
		flushing = false,
		pending = {},
		replayable = true,
		stale = false,
		staleMarks = 0,
		releasing = false,
		releaseStartedAt = 0,
	}
end

local function foldMutators(mutators: { Mutator }, base: any): any
	local doc = base
	for _, mutator in ipairs(mutators) do
		doc = mutator(doc)
	end
	return doc
end

local function splitKey(key: string): (string?, number?)
	local ns, idStr = string.match(key, "^(.-)::(%d+)$")
	return ns, tonumber(idStr)
end

local PlayerSessionStore = {}

function PlayerSessionStore.isEnabled(): boolean
	local cfg = persistenceConfig()
	return cfg.SESSION_WRITE_BEHIND_ENABLED ~= false
		and cfg.USE_LEGACY_IMMEDIATE_OVERHEAD_WRITES ~= true
end

function PlayerSessionStore.registerFlush(namespace: string, flushFn: FlushFn)
	flushFns[namespace] = flushFn
end

function PlayerSessionStore.getMetrics()
	local departed = 0
	for _, entry in pairs(sessions) do
		if entry.releasing then
			departed += 1
		end
	end
	return {
		skipNoOp = metrics.skipNoOp,
		scheduled = metrics.scheduled,
		flushed = metrics.flushed,
		flushFailed = metrics.flushFailed,
		replayed = metrics.replayed,
		staleKept = metrics.staleKept,
		releaseRetries = metrics.releaseRetries,
		releaseGaveUp = metrics.releaseGaveUp,
		departedDropped = metrics.departedDropped,
		departed = departed,
		openSessions = 0, -- filled below
	}
end

function PlayerSessionStore.hydrate(namespace: string, userId: number, data: any)
	local key = sessionKey(namespace, userId)
	local existing = sessions[key]
	if existing and existing.dirty then
		-- Never overwrite unsaved changes with a (possibly older) loaded copy.
		return
	end
	sessions[key] = newEntry(data)
end

function PlayerSessionStore.get(namespace: string, userId: number): any?
	local entry = sessions[sessionKey(namespace, userId)]
	if not entry then
		return nil
	end
	return entry.data
end

--- Unconditional drop (explicit cache reset). Prefer `invalidate` for cross-server messages
--- and `release` for leaves: both keep unsaved changes.
function PlayerSessionStore.clear(namespace: string, userId: number)
	sessions[sessionKey(namespace, userId)] = nil
end

--- Local cache reset that never discards unsaved changes: drops the slot only when clean.
--- Returns true when dropped (or absent).
function PlayerSessionStore.dropIfClean(namespace: string, userId: number): boolean
	local key = sessionKey(namespace, userId)
	local entry = sessions[key]
	if not entry then
		return true
	end
	if entry.dirty or entry.flushing then
		return false
	end
	sessions[key] = nil
	return true
end

--- Another server wrote this document. Returns "absent" | "cleared" | "kept_dirty".
function PlayerSessionStore.invalidate(namespace: string, userId: number): string
	local key = sessionKey(namespace, userId)
	local entry = sessions[key]
	if not entry then
		return "absent"
	end
	if entry.dirty or entry.flushing then
		entry.stale = true
		entry.staleMarks += 1
		metrics.staleKept += 1
		BudgetMeter.recordEvent("session_stale_kept")
		return "kept_dirty"
	end
	sessions[key] = nil
	return "cleared"
end

function PlayerSessionStore.isStale(namespace: string, userId: number): boolean
	local entry = sessions[sessionKey(namespace, userId)]
	return entry ~= nil and entry.stale == true
end

--- Apply mutator in memory. Returns (okData, changed).
--- If not hydrated, returns nil, false — caller should load first.
function PlayerSessionStore.applyMutator(
	namespace: string,
	userId: number,
	mutator: Mutator
): (any?, boolean)
	local key = sessionKey(namespace, userId)
	local entry = sessions[key]
	if not entry then
		return nil, false
	end
	-- Fingerprint of what memory holds now, taken BEFORE the mutator runs (a mutator may edit
	-- `current` in place). Clean entries hold exactly the durable document.
	local currentFp = if entry.dirty then fingerprintOf(entry.data) else entry.fingerprint
	local nextData = mutator(entry.data)
	local nextFp = fingerprintOf(nextData)
	if nextFp == currentFp then
		metrics.skipNoOp += 1
		return entry.data, false
	end
	entry.data = nextData
	entry.dirty = true
	entry.generation += 1
	if entry.replayable then
		local cap = persistenceConfig().MAX_PENDING_MUTATORS or DEFAULT_MAX_PENDING_MUTATORS
		if #entry.pending >= cap then
			-- Too many unsaved steps (flushes keep failing): fall back to whole-document writes.
			entry.replayable = false
			table.clear(entry.pending)
		else
			table.insert(entry.pending, mutator)
		end
	end
	-- fingerprint stays as last *flushed* fingerprint until flush succeeds
	return nextData, true
end

function PlayerSessionStore.markClean(namespace: string, userId: number, data: any?)
	local key = sessionKey(namespace, userId)
	local entry = sessions[key]
	if not entry then
		if data ~= nil then
			PlayerSessionStore.hydrate(namespace, userId, data)
		end
		return
	end
	if data ~= nil then
		entry.data = data
	end
	entry.fingerprint = fingerprintOf(entry.data)
	entry.dirty = false
	entry.stale = false
	table.clear(entry.pending)
	entry.replayable = true
end

function PlayerSessionStore.isDirty(namespace: string, userId: number): boolean
	local entry = sessions[sessionKey(namespace, userId)]
	return entry ~= nil and entry.dirty == true
end

local function flushOne(namespace: string, userId: number): Result<nil>
	local key = sessionKey(namespace, userId)
	local entry = sessions[key]
	if not entry or not entry.dirty then
		return Result.Ok(nil)
	end
	if entry.flushing then
		return Result.Err("flush_in_flight")
	end
	local flushFn = flushFns[namespace]
	if not flushFn then
		return Result.Err("no_flush_fn")
	end
	entry.flushing = true
	local flushGeneration = entry.generation
	local staleMarksAtStart = entry.staleMarks
	local pendingCount = #entry.pending
	local snapshot = entry.data
	local replay: ((base: any) -> any)? = nil
	if entry.replayable then
		local steps = table.move(entry.pending, 1, pendingCount, 1, {})
		replay = function(base: any): any
			return foldMutators(steps, base)
		end
	end
	local context: FlushContext = { stale = entry.stale, replay = replay }
	local called, resultOrError = pcall(flushFn, userId, snapshot, context)
	entry.flushing = false
	local result: Result<any> = if called then resultOrError else Result.Err(tostring(resultOrError))
	if not result.ok then
		metrics.flushFailed += 1
		return result
	end

	local written = if result.value ~= nil then result.value else snapshot
	if result.value ~= nil then
		metrics.replayed += 1
	end
	-- The first `pendingCount` mutators are durable now; later ones arrived during the yield.
	local remaining: { Mutator } = {}
	for index = pendingCount + 1, #entry.pending do
		table.insert(remaining, entry.pending[index])
	end
	entry.pending = remaining
	entry.fingerprint = fingerprintOf(written)
	-- A stale mark that landed during the write still needs a replayed write.
	entry.stale = entry.staleMarks ~= staleMarksAtStart
	if entry.generation == flushGeneration then
		entry.data = written
		entry.dirty = false
		entry.replayable = true
	elseif result.value ~= nil and entry.replayable then
		-- Rebase the newer in-memory steps on what was actually written.
		entry.data = foldMutators(remaining, written)
	end
	metrics.flushed += 1
	-- Newer mutations during yield keep dirty=true for a follow-up flush.
	if entry.releasing and not entry.dirty and sessions[key] == entry then
		sessions[key] = nil
	end
	return Result.Ok(nil)
end

function PlayerSessionStore.flushNow(namespace: string, userId: number): Result<nil>
	return flushOne(namespace, userId)
end

function PlayerSessionStore.scheduleFlush(namespace: string, userId: number)
	local key = sessionKey(namespace, userId)
	local entry = sessions[key]
	if not entry or not entry.dirty then
		return
	end
	if entry.flushScheduled then
		return
	end
	entry.flushScheduled = true
	metrics.scheduled += 1
	local debounce = persistenceConfig().SESSION_FLUSH_DEBOUNCE or 3
	task.delay(debounce, function()
		local current = sessions[key]
		if current then
			current.flushScheduled = false
		end
		local flushResult = flushOne(namespace, userId)
		if not flushResult.ok and flushResult.error == "flush_in_flight" then
			PlayerSessionStore.scheduleFlush(namespace, userId)
		end
	end)
end

local function dropOldestDeparted()
	local cap = persistenceConfig().MAX_DEPARTED_SESSIONS or DEFAULT_MAX_DEPARTED
	local departed: { { key: string, at: number } } = {}
	for key, entry in pairs(sessions) do
		if entry.releasing then
			table.insert(departed, { key = key, at = entry.releaseStartedAt })
		end
	end
	if #departed <= cap then
		return
	end
	table.sort(departed, function(a, b)
		return a.at < b.at
	end)
	for index = 1, #departed - cap do
		sessions[departed[index].key] = nil
		metrics.departedDropped += 1
		BudgetMeter.recordEvent("leave_session_dropped")
		warn(string.format("[PlayerSessionStore] departed cap reached, unsaved session dropped: %s", departed[index].key))
	end
end

--- Player left: flush (if dirty), then drop the slot. On failure the dirty entry stays (so
--- autosave / BindToClose flushAll retry it too) and the flush is retried at `retryDelays`;
--- any later successful flush drops it. Returns the first attempt's result.
function PlayerSessionStore.release(namespace: string, userId: number, options: ReleaseOptions?): Result<nil>
	local key = sessionKey(namespace, userId)
	local entry = sessions[key]
	if not entry then
		return Result.Ok(nil)
	end
	if not entry.dirty and not entry.flushing then
		sessions[key] = nil
		return Result.Ok(nil)
	end
	entry.releasing = true
	entry.releaseStartedAt = os.clock()
	local first = flushOne(namespace, userId)
	if sessions[key] ~= entry or not entry.releasing then
		return first -- released by the flush, or the player came back
	end
	if not entry.dirty and not entry.flushing then
		sessions[key] = nil
		return first
	end
	dropOldestDeparted()

	local opts = options or {}
	local delays = opts.retryDelays or persistenceConfig().LEAVE_FLUSH_RETRY_DELAYS or DEFAULT_RELEASE_RETRY_DELAYS
	local isPresent = opts.isPresent
	local attempt = 0
	local function retry()
		attempt += 1
		local current = sessions[key]
		if current ~= entry or not entry.releasing then
			return
		end
		if isPresent and isPresent() then
			-- Rejoined this server: the live session owns the entry again.
			entry.releasing = false
			return
		end
		metrics.releaseRetries += 1
		BudgetMeter.recordEvent("leave_flush_retry")
		local retried = flushOne(namespace, userId)
		if sessions[key] ~= entry then
			return
		end
		if not entry.dirty and not entry.flushing then
			sessions[key] = nil
			return
		end
		if attempt < #delays then
			task.delay(delays[attempt + 1], retry)
			return
		end
		if retried.ok then
			return -- still dirty only because of newer steps; autosave/BindToClose take it
		end
		metrics.releaseGaveUp += 1
		BudgetMeter.recordEvent("leave_flush_gave_up")
		warn(string.format(
			"[PlayerSessionStore] leave flush still failing after %d retries (kept for autosave/BindToClose): %s err=%s",
			attempt,
			key,
			tostring(retried.error)
		))
	end
	if #delays > 0 then
		task.delay(delays[1], retry)
	end
	return first
end

local function dirtyKeys(prefix: string?): { string }
	local keys = {}
	for key, entry in pairs(sessions) do
		if entry.dirty and (prefix == nil or string.sub(key, 1, #prefix) == prefix) then
			table.insert(keys, key)
		end
	end
	return keys
end

-- Iterates a snapshot of keys: flushOne yields, and other threads may add sessions meanwhile.
function PlayerSessionStore.flushNamespace(namespace: string): number
	local failed = 0
	for _, key in ipairs(dirtyKeys(namespace .. "::")) do
		local ns, userId = splitKey(key)
		if ns and userId then
			local result = flushOne(ns, userId)
			if not result.ok then
				failed += 1
			end
		end
	end
	return failed
end

function PlayerSessionStore.flushAll(): number
	local failed = 0
	for _, key in ipairs(dirtyKeys(nil)) do
		local ns, userId = splitKey(key)
		if ns and userId then
			local result = flushOne(ns, userId)
			if not result.ok then
				failed += 1
			end
		end
	end
	return failed
end

function PlayerSessionStore.openSessionCount(): number
	local n = 0
	for _ in pairs(sessions) do
		n += 1
	end
	return n
end

return PlayerSessionStore
