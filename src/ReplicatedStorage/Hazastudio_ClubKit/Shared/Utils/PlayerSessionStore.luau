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
--   flushNow / flushNamespace / flushAll — leave / BindToClose

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Result = require(script.Parent.Result)
local Types = require(script.Parent.Parent.Domain.Types)

type Result<T> = Types.Result<T>

export type FlushFn = (userId: number, data: any) -> Result<nil>

type SessionEntry = {
	data: any,
	fingerprint: string,
	dirty: boolean,
	flushScheduled: boolean,
	generation: number,
	flushing: boolean,
}

local sessions: { [string]: SessionEntry } = {}
local flushFns: { [string]: FlushFn } = {}
local metrics = {
	skipNoOp = 0,
	scheduled = 0,
	flushed = 0,
	flushFailed = 0,
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
	return {
		skipNoOp = metrics.skipNoOp,
		scheduled = metrics.scheduled,
		flushed = metrics.flushed,
		flushFailed = metrics.flushFailed,
		openSessions = 0, -- filled below
	}
end

function PlayerSessionStore.hydrate(namespace: string, userId: number, data: any)
	local key = sessionKey(namespace, userId)
	sessions[key] = {
		data = data,
		fingerprint = fingerprintOf(data),
		dirty = false,
		flushScheduled = false,
		generation = 0,
		flushing = false,
	}
end

function PlayerSessionStore.get(namespace: string, userId: number): any?
	local entry = sessions[sessionKey(namespace, userId)]
	if not entry then
		return nil
	end
	return entry.data
end

function PlayerSessionStore.clear(namespace: string, userId: number)
	sessions[sessionKey(namespace, userId)] = nil
end

--- Apply mutator in memory. Returns (okData, changed).
--- If not hydrated, returns nil, false — caller should load first.
function PlayerSessionStore.applyMutator(
	namespace: string,
	userId: number,
	mutator: (current: any) -> any
): (any?, boolean)
	local key = sessionKey(namespace, userId)
	local entry = sessions[key]
	if not entry then
		return nil, false
	end
	local nextData = mutator(entry.data)
	local nextFp = fingerprintOf(nextData)
	if nextFp == entry.fingerprint and not entry.dirty then
		metrics.skipNoOp += 1
		return entry.data, false
	end
	if nextFp == entry.fingerprint then
		-- Same as last durable fingerprint but marked dirty somehow — treat as no-op
		metrics.skipNoOp += 1
		entry.dirty = false
		return entry.data, false
	end
	entry.data = nextData
	entry.dirty = true
	entry.generation += 1
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
	local snapshot = entry.data
	local result = flushFn(userId, snapshot)
	entry.flushing = false
	if result.ok then
		if entry.generation == flushGeneration then
			entry.fingerprint = fingerprintOf(entry.data)
			entry.dirty = false
			metrics.flushed += 1
		end
		-- Newer mutations during yield keep dirty=true for a follow-up flush.
		return Result.Ok(nil)
	end
	metrics.flushFailed += 1
	return result
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

function PlayerSessionStore.flushNamespace(namespace: string): number
	local failed = 0
	local prefix = namespace .. "::"
	for key, entry in pairs(sessions) do
		if entry.dirty and string.sub(key, 1, #prefix) == prefix then
			local userId = tonumber(string.sub(key, #prefix + 1))
			if userId then
				local result = flushOne(namespace, userId)
				if not result.ok then
					failed += 1
				end
			end
		end
	end
	return failed
end

function PlayerSessionStore.flushAll(): number
	local failed = 0
	for key, entry in pairs(sessions) do
		if entry.dirty then
			local ns, idStr = string.match(key, "^(.-)::(%d+)$")
			local userId = tonumber(idStr)
			if ns and userId then
				local result = flushOne(ns, userId)
				if not result.ok then
					failed += 1
				end
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
