--!strict
-- Server/Persistence/PlayerDocWriter.luau
--
-- One write path per player document (production hardening P3, plan §2 A1). Wraps
-- Shared/Utils/PlayerSessionStore; the timing rules are Shared/Domain/FlushPolicy.
--   * start(): a 1 Hz scheduler that writes the session documents (Overhead) that are due —
--     XP-only changes on the player's slot in every 90 s (owner decision K1), other changes after
--     a 3 s debounce, never two writes of one key within 7 s, at most ceil(dirty/60)+2 per tick.
--   * guard(docKey, fn): the same 7 s per-key gap for repositories that write directly
--     (Settings, VenueQuestProgress).
--   * flushForShutdown(): BindToClose / early-restart flush — every dirty document, Overhead first,
--     at most SHUTDOWN_WRITES_PER_SEC started per second within SHUTDOWN_BUDGET_SEC.
-- Config.PlayerDocWriter.WRITE_POLICY = "legacy" turns all of it off (P1 behaviour: 3 s debounce
-- timers, sequential flushAll); every function here is then a pass-through / no-op.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local PlayerSessionStore = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.PlayerSessionStore)
local BudgetMeter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetMeter)
local FlushPolicy = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.FlushPolicy)

local PlayerDocWriter = {}

-- Namespaces written first at shutdown (plan: Overhead → VenueQuestProgress → Settings → rest;
-- venue progress has its own flushAll in the same BindToClose phase).
local SHUTDOWN_ORDER = { "overhead", "settings" }

local running = false
local ticker: thread? = nil
local lastDirectWrite: { [string]: number } = {}
local lastDirectWriteCount = 0

local function cfg(): any
	local w = Config.PlayerDocWriter
	return if type(w) == "table" then w else {}
end

function PlayerDocWriter.isV2(): boolean
	return cfg().WRITE_POLICY == "v2"
end

--- Starts the 1 Hz scheduler (v2 only). Safe to call twice.
function PlayerDocWriter.start()
	if running or not PlayerDocWriter.isV2() then
		return
	end
	running = true
	local tickSec = math.max(0.25, tonumber(cfg().TICK_SEC) or 1)
	ticker = task.spawn(function()
		while running do
			task.wait(tickSec)
			if not running then
				break
			end
			local ok, err = pcall(PlayerSessionStore.flushDue, os.clock())
			if not ok then
				warn("[PlayerDocWriter] tick failed: " .. tostring(err))
			end
		end
	end)
end

function PlayerDocWriter.stop()
	running = false
	local thread = ticker
	ticker = nil
	if thread and coroutine.status(thread) == "suspended" then
		pcall(task.cancel, thread)
	end
end

--- Runs `write` (one direct DataStore write of `docKey`, e.g. "settings::123") no sooner than
--- MIN_GAP_SEC after the previous write of that key through this guard. Returns what `write`
--- returns. Legacy policy: runs it at once.
function PlayerDocWriter.guard<T>(docKey: string, write: () -> T): T
	if not PlayerDocWriter.isV2() then
		return write()
	end
	local minGap = tonumber(cfg().MIN_GAP_SEC) or 7
	local wait = FlushPolicy.gapWait(lastDirectWrite[docKey] or -math.huge, os.clock(), minGap)
	if wait > 0 then
		BudgetMeter.recordEvent("samekey_gap_wait")
		task.wait(wait)
	end
	-- Recorded before the write: two callers racing for one key still end up MIN_GAP apart.
	if lastDirectWrite[docKey] == nil then
		lastDirectWriteCount += 1
	end
	lastDirectWrite[docKey] = os.clock()
	if lastDirectWriteCount > 1000 then
		local cutoff = os.clock() - 60
		for key, at in pairs(lastDirectWrite) do
			if at < cutoff then
				lastDirectWrite[key] = nil
				lastDirectWriteCount -= 1
			end
		end
	end
	return write()
end

--- Shutdown / early-restart flush of the session documents. Returns how many stay unsaved.
function PlayerDocWriter.flushForShutdown(budgetSec: number?): number
	if not PlayerDocWriter.isV2() then
		return PlayerSessionStore.flushAll()
	end
	local perSec = tonumber(cfg().SHUTDOWN_WRITES_PER_SEC) or 12
	local budget = budgetSec or tonumber(cfg().SHUTDOWN_BUDGET_SEC) or 22
	return PlayerSessionStore.flushAllPaced(SHUTDOWN_ORDER, perSec, budget)
end

return PlayerDocWriter
