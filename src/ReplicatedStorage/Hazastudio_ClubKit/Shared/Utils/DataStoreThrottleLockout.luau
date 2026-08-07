--!strict
-- Shared/Utils/DataStoreThrottleLockout.luau
-- Singleton cooldown gate for the whole server. When DataStoreService emits
-- StandardReadExperienceThrottled or OrderedListExperienceThrottled, all
-- DS-bound operations (getRobuxLeaderboard, recordRobuxDonation, etc) will
-- short-circuit during cooldown and return Err("ds_throttled"). Callers fall
-- back to TTL cache; BudgetGate naturally re-budgets after cooldown
-- so throttle is usually already clear.
--
-- Notes:
--   - In-memory only. Each server restart = lockout reset (acceptable; cooldown 60s).
--   - Event handler attached at module load. If DataStoreService in Studio
--     does not have the event yet (API Services off), Connect is pcall-wrapped and warned once.
--   - markThrottled() also called from pcall catch in repository if error
--     string contains "throttled" / "queue" / "Throttled" - belt-and-suspenders
--     because some throttle events do not fire (e.g. Roblox internal limit).
--   - Lockout MONOTONICALLY EXTENDS: if already locked and called again,
--     the longer cooldown wins (max(current, new)).

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Lazy Config lookup to avoid circular import. Config may not be loaded
-- when module is first required.
local Config = nil :: any
local function getDefaultCooldown(): number
	if Config == nil then
		local ok, mod = pcall(function()
			return require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
		end)
		if ok and type(mod) == "table" and type(mod.Donation) == "table" then
			Config = mod
		end
	end
	if Config and Config.Donation and type(Config.Donation.DATASTORE_THROTTLE_COOLDOWN) == "number" then
		return Config.Donation.DATASTORE_THROTTLE_COOLDOWN
	end
	return 60
end

local DataStoreThrottleLockout = {}

local _lockoutUntil = 0
local _initialized = false

local function _now(): number
	return os.clock()
end

--- True while cooldown window is active. Repo functions check this at top and
--- return Err("ds_throttled") without touching DataStore.
function DataStoreThrottleLockout.isLocked(): boolean
	return _now() < _lockoutUntil
end

--- Extend (or set) cooldown window. Only extend, never shorten —
--- so late-arriving events do not accidentally unlock during throttle storm.
--- @param cooldownSec optional, default = Config.Donation.DATASTORE_THROTTLE_COOLDOWN
function DataStoreThrottleLockout.markThrottled(cooldownSec: number?)
	local cd: number
	if type(cooldownSec) == "number" and cooldownSec > 0 then
		cd = cooldownSec
	else
		cd = getDefaultCooldown()
	end
	local newUntil = _now() + cd
	if newUntil > _lockoutUntil then
		_lockoutUntil = newUntil
	end
end

--- Remaining lockout seconds (for logging).
function DataStoreThrottleLockout.getRemainingSec(): number
	return math.max(0, _lockoutUntil - _now())
end

--- Reset lockout (for test/admin command).
function DataStoreThrottleLockout.clear()
	_lockoutUntil = 0
end

--- Hook DataStoreService events. Call once at module load. Safe to
--- pcall: if event missing (Studio without API Services), skip.
function DataStoreThrottleLockout.init()
	if _initialized then
		return
	end
	_initialized = true

	local function tryConnect(eventName: string)
		local ok, eventOrErr = pcall(function()
			return (DataStoreService :: any)[eventName]
		end)
		if not ok or type(eventOrErr) ~= "userdata" then
			return
		end
		local connOk, err = pcall(function()
			local signal = eventOrErr :: any
			(signal.Connect :: any)(signal, function()
				DataStoreThrottleLockout.markThrottled(nil)
			end)
		end)
		if not connOk then
			warn(string.format("[DataStoreThrottleLockout] connect failed event=%s err=%s", eventName, tostring(err)))
		end
	end

	tryConnect("StandardReadExperienceThrottled")
	tryConnect("OrderedListExperienceThrottled")
end

-- Auto-init when module is required. Module-level code runs once
-- per server, so this is safe.
DataStoreThrottleLockout.init()

return DataStoreThrottleLockout
