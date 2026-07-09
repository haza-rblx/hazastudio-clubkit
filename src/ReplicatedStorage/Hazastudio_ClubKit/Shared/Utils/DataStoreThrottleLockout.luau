--!strict
-- Shared/Utils/DataStoreThrottleLockout.luau
-- Singleton cooldown gate untuk seluruh server. Saat DataStoreService emit
-- StandardReadExperienceThrottled atau OrderedListExperienceThrottled, semua
-- DS-bound operations (getRobuxLeaderboard, recordRobuxDonation, dll) akan
-- short-circuit selama cooldown dan return Err("ds_throttled"). Caller fall
-- back ke TTL cache; BudgetGate naturally re-budgeted setelah cooldown
-- sehingga throttle biasanya sudah clear.
--
-- Penting:
--   - In-memory only. Tiap server restart = lockout reset (acceptable; cooldown 60s).
--   - Event handler dipasang di module load. Kalau DataStoreService di Studio
--     belum punya event (API Services off), Connect di-pcall dan diwarn sekali.
--   - markThrottled() juga dipanggil dari pcall catch di repository jika error
--     string mengandung "throttled" / "queue" / "Throttled" - belt-and-suspenders
--     karena beberapa throttle event tidak fire (mis. Roblox internal limit).
--   - Lockout MONOTONICALLY EXTENDS: kalau sudah locked dan dipanggil lagi,
--     cooldown yang lebih panjang yang berlaku (max(current, new)).

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Lazy Config lookup supaya tidak circular-import. Config mungkin belum loaded
-- saat module pertama di-require.
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

--- True selama cooldown window aktif. Repo functions check ini di top dan
--- return Err("ds_throttled") tanpa menyentuh DataStore.
function DataStoreThrottleLockout.isLocked(): boolean
	return _now() < _lockoutUntil
end

--- Extend (atau set) cooldown window. Hanya extend, tidak pernah shorten -
--- supaya late-arriving events tidak accidentally unlock saat throttle storm.
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

--- Sisa detik lockout aktif (untuk logging).
function DataStoreThrottleLockout.getRemainingSec(): number
	return math.max(0, _lockoutUntil - _now())
end

--- Reset lockout (untuk test/admin command).
function DataStoreThrottleLockout.clear()
	_lockoutUntil = 0
end

--- Hook ke DataStoreService events. Panggil sekali saat module load. Aman
--- di-pcall: kalau event tidak ada (Studio tanpa API Services), di-skip.
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
			warn(string.format("[DataStoreThrottleLockout] connect gagal event=%s err=%s", eventName, tostring(err)))
		end
	end

	tryConnect("StandardReadExperienceThrottled")
	tryConnect("OrderedListExperienceThrottled")
end

-- Auto-init saat module di-require. Module-level code di Luau jalan sekali
-- per server, jadi aman.
DataStoreThrottleLockout.init()

return DataStoreThrottleLockout
