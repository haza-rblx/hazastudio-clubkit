--!strict
-- NetworkFlushScheduler — Single shared per-frame flush driver (Guidelines v3 N1, R9).
--
-- Every NetworkManager instance registers its per-instance flush() here instead of each
-- opening its own RunService.Heartbeat connection. The scheduler maintains EXACTLY one
-- Heartbeat connection regardless of how many instances are registered (1, 2, or 13+),
-- and disconnects it once the registry empties.
--
-- Per-instance FIFO ordering and empty-queue skipping are the responsibility of each
-- registered flush() callback (see NetworkManager); this scheduler only fans out the
-- per-frame tick to every registered instance.
--
-- This is a process-wide singleton: the module table holds shared state, so all callers
-- of require() observe the same registry and the same single connection.

local RunService = game:GetService("RunService")

-- ── Types ─────────────────────────────────────────────────────

export type FlushCallback = () -> ()

-- ── Shared singleton state ────────────────────────────────────

local registry: { [string]: FlushCallback } = {}
local registeredCount = 0
local heartbeatConnection: RBXScriptConnection? = nil

-- Reused buffer so the per-frame fan-out allocates nothing and is safe against a flush
-- callback registering/unregistering instances mid-iteration.
local flushBuffer: { FlushCallback } = {}

local NetworkFlushScheduler = {}

-- ── Internal ──────────────────────────────────────────────────

local function onHeartbeat()
	-- Snapshot current callbacks before invoking any, so a flush() that triggers an
	-- (un)register (e.g. an instance torn down during flush) cannot corrupt iteration.
	local count = 0
	for _, flush in registry do
		count += 1
		flushBuffer[count] = flush
	end

	for index = 1, count do
		local flush = flushBuffer[index]
		flushBuffer[index] = nil
		flush()
	end
end

local function ensureConnected()
	if heartbeatConnection == nil then
		heartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)
	end
end

local function disconnect()
	if heartbeatConnection ~= nil then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
end

-- ── Public API ────────────────────────────────────────────────

--- Register an instance's flush callback with the shared scheduler.
--- The shared Heartbeat connection is opened on the first registration and reused for all
--- subsequent registrations. Re-registering an existing instanceId replaces its callback
--- without opening a second connection.
function NetworkFlushScheduler.register(instanceId: string, flush: FlushCallback)
	if registry[instanceId] == nil then
		registeredCount += 1
	end
	registry[instanceId] = flush
	ensureConnected()
end

--- Remove an instance from the shared scheduler. When the last instance is unregistered
--- the shared Heartbeat connection is disconnected so that zero flush connections remain;
--- otherwise the connection stays active for the remaining instances.
function NetworkFlushScheduler.unregister(instanceId: string)
	if registry[instanceId] == nil then
		return
	end
	registry[instanceId] = nil
	registeredCount -= 1
	if registeredCount <= 0 then
		registeredCount = 0
		disconnect()
	end
end

-- ── Introspection (test/diagnostic helpers) ───────────────────

--- Number of instances currently registered.
function NetworkFlushScheduler.getRegisteredCount(): number
	return registeredCount
end

--- True while the shared Heartbeat connection is active.
function NetworkFlushScheduler.isConnected(): boolean
	return heartbeatConnection ~= nil
end

return NetworkFlushScheduler
