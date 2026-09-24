--!strict
-- Server/Init/PersistenceFabricHooks.luau
--
-- Single Main.server entry point for Persistence Fabric runtime hooks.
-- Keeps DataStoreScheduler / CrossServerCache / PlayerSessionStore requires
-- OUT of Main's top-level local register set (Luau limit 200 per function).
--
-- Main should `require` ONLY this module (one local), then call the API below.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerSessionStore = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.PlayerSessionStore)
local DataStoreScheduler = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DataStoreScheduler)
local CrossServerCache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.CrossServerCache)
local PlayerDocWriter = require(script.Parent.Parent.Persistence.PlayerDocWriter)

local PersistenceFabricHooks = {}

--- Flush dirty Overhead/Settings session docs, then drop session slots. A failed flush no
--- longer drops the unsaved document (it did until 2026-09-24): the slot is kept and retried
--- (Config.Persistence.LEAVE_FLUSH_RETRY_DELAYS), and autosave / BindToClose flushAll see it too.
function PersistenceFabricHooks.onPlayerRemoving(player: Player)
	local userId = player.UserId
	local options = {
		isPresent = function(): boolean
			return Players:GetPlayerByUserId(userId) ~= nil
		end,
	}
	PlayerSessionStore.release("overhead", userId, options)
	PlayerSessionStore.release("settings", userId, options)
end

--- Flush all dirty session documents (autosave / early restart / BindToClose).
--- Returns count of entries that failed to flush. Under the v2 write policy (production hardening
--- P3) the 60 s autosave (`reason == "autosave"`) writes nothing — PlayerDocWriter's 1 Hz
--- scheduler owns periodic writes (90 s XP slot) — and the other callers get the paced
--- shutdown flush (Overhead first, ≤ 12 writes/s).
function PersistenceFabricHooks.flushAll(reason: string?): number
	if reason == "autosave" and PlayerDocWriter.isV2() then
		return 0
	end
	return PlayerDocWriter.flushForShutdown()
end

--- Starts PlayerDocWriter's 1 Hz scheduler (no-op under the legacy write policy).
function PersistenceFabricHooks.startWriter()
	PlayerDocWriter.start()
end

--- DEBUG snapshot for BackgroundJobScheduler (PersistenceFabric metrics).
function PersistenceFabricHooks.debugSnapshot(log: any)
	log:debug("PersistenceFabric snapshot", {
		scheduler = DataStoreScheduler.getMetrics(),
		invalidateBus = CrossServerCache.getMetrics(),
		session = PlayerSessionStore.getMetrics(),
		openSessions = PlayerSessionStore.openSessionCount(),
	})
end

--- Register the periodic metrics job when METRICS_LOG_INTERVAL > 0.
function PersistenceFabricHooks.registerMetricsJob(scheduler: any, log: any, intervalSec: number)
	if type(intervalSec) ~= "number" or intervalSec <= 0 then
		return
	end
	if not scheduler or type(scheduler.register) ~= "function" then
		return
	end
	scheduler:register({
		name = "persistence_fabric_snapshot",
		callback = function()
			PersistenceFabricHooks.debugSnapshot(log)
		end,
		intervalMin = intervalSec,
		intervalMax = intervalSec,
	})
end

return PersistenceFabricHooks
