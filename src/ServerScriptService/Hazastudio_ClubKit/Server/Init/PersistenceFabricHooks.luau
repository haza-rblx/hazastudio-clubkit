--!strict
-- Server/Init/PersistenceFabricHooks.luau
--
-- Single Main.server entry point for Persistence Fabric runtime hooks.
-- Keeps DataStoreScheduler / CrossServerCache / PlayerSessionStore requires
-- OUT of Main's top-level local register set (Luau limit 200 per function).
--
-- Main should `require` ONLY this module (one local), then call the API below.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerSessionStore = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.PlayerSessionStore)
local DataStoreScheduler = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DataStoreScheduler)
local CrossServerCache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.CrossServerCache)

local PersistenceFabricHooks = {}

--- Flush dirty Overhead/Settings session docs, then drop session slots.
function PersistenceFabricHooks.onPlayerRemoving(player: Player)
	local userId = player.UserId
	PlayerSessionStore.flushNow("overhead", userId)
	PlayerSessionStore.flushNow("settings", userId)
	PlayerSessionStore.clear("overhead", userId)
	PlayerSessionStore.clear("settings", userId)
end

--- Flush all dirty session documents (autosave / BindToClose).
--- Returns count of entries that failed to flush.
function PersistenceFabricHooks.flushAll(): number
	return PlayerSessionStore.flushAll()
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
