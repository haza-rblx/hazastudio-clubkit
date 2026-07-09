--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local SettingsDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.SettingsDomain)

type Result<T> = Types.Result<T>
type SettingsStoredData = Types.SettingsStoredData
type SettingsSessionData = Types.SettingsSessionData
type SettingsPayload = Types.SettingsPayload
type ISettingsRepository = any
type ILogger = Types.ILogger

local FLUSH_IDLE_SEC = 3

local function createSettingsService(deps: {
	logger: ILogger,
	repo: ISettingsRepository,
})
	local repo = deps.repo
	local sessionByUserId = {} :: { [number]: SettingsSessionData }
	local storedByUserId = {} :: { [number]: SettingsStoredData }
	local dirtyByUserId = {} :: { [number]: boolean }
	local flushTokenByUserId = {} :: { [number]: number }
	-- Snapshot settings that failed to flush on leave/shutdown for retry.
	local pendingFlushByUserId = {} :: { [number]: SettingsStoredData }
	-- Tracks players whose stored settings loaded successfully. Any write
	-- (updateStored/reset) is refused while false/nil so a failed load can
	-- never seed a default snapshot that overwrites the player's real data.
	local loadedByUserId = {} :: { [number]: boolean }
	local service = {}

	local function cancelScheduledFlush(userId: number)
		flushTokenByUserId[userId] = (flushTokenByUserId[userId] or 0) + 1
	end

	local function scheduleFlush(player: Player)
		local userId = player.UserId
		flushTokenByUserId[userId] = (flushTokenByUserId[userId] or 0) + 1
		local token = flushTokenByUserId[userId]
		task.delay(FLUSH_IDLE_SEC, function()
			if flushTokenByUserId[userId] ~= token then
				return
			end
			if not player.Parent then
				return
			end
			service:flushStored(player)
		end)
	end

	function service:load(player: Player): Result<SettingsPayload>
		local loaded = repo:load(player.UserId)
		if not loaded.ok then
			loadedByUserId[player.UserId] = nil
			return loaded
		end

		loadedByUserId[player.UserId] = true
		storedByUserId[player.UserId] = loaded.value
		dirtyByUserId[player.UserId] = false
		local session = sessionByUserId[player.UserId] or SettingsDomain.defaultSessionData()
		sessionByUserId[player.UserId] = session
		return { ok = true, value = SettingsDomain.merge(loaded.value, session) }
	end

	function service:get(player: Player): SettingsPayload
		local stored = storedByUserId[player.UserId] or SettingsDomain.defaultStoredData()
		local session = sessionByUserId[player.UserId] or SettingsDomain.defaultSessionData()
		return SettingsDomain.merge(stored, session)
	end

	function service:updateStored(
		player: Player,
		updater: (current: SettingsStoredData) -> SettingsStoredData
	): Result<SettingsPayload>
		-- Refuse writes until the player's stored settings have loaded. Without
		-- this gate, a failed load seeds a default snapshot and the next flush
		-- would overwrite the player's real stored settings with defaults.
		if not loadedByUserId[player.UserId] then
			return { ok = false, error = "settings_not_loaded" }
		end
		local current = storedByUserId[player.UserId] or SettingsDomain.defaultStoredData()
		local nextStored = SettingsDomain.sanitizeStored(updater(current))
		storedByUserId[player.UserId] = nextStored
		dirtyByUserId[player.UserId] = true
		scheduleFlush(player)
		local session = sessionByUserId[player.UserId] or SettingsDomain.defaultSessionData()
		sessionByUserId[player.UserId] = session
		return { ok = true, value = SettingsDomain.merge(nextStored, session) }
	end

	function service:flushStored(player: Player): Result<SettingsStoredData>
		local userId = player.UserId
		if not dirtyByUserId[userId] then
			return { ok = true, value = storedByUserId[userId] or SettingsDomain.defaultStoredData() }
		end

		local stored = storedByUserId[userId] or SettingsDomain.defaultStoredData()
		local saved = repo:save(userId, stored)
		if not saved.ok then
			pendingFlushByUserId[userId] = stored
			return { ok = false, error = saved.error }
		end

		dirtyByUserId[userId] = false
		pendingFlushByUserId[userId] = nil
		return { ok = true, value = stored }
	end

	function service:isDirty(player: Player): boolean
		return dirtyByUserId[player.UserId] == true
	end

	function service:isLoaded(player: Player): boolean
		return loadedByUserId[player.UserId] == true
	end

	function service:setSession(player: Player, session: SettingsSessionData)
		sessionByUserId[player.UserId] = SettingsDomain.sanitizeSession(session)
	end

	function service:updateSession(
		player: Player,
		mutator: (current: SettingsSessionData) -> SettingsSessionData
	): SettingsPayload
		local current = sessionByUserId[player.UserId] or SettingsDomain.defaultSessionData()
		local nextSession = SettingsDomain.sanitizeSession(mutator(current))
		sessionByUserId[player.UserId] = nextSession
		local stored = storedByUserId[player.UserId] or SettingsDomain.defaultStoredData()
		return SettingsDomain.merge(stored, nextSession)
	end

	function service:reset(player: Player): Result<SettingsPayload>
		-- Refuse reset until the player's stored settings have loaded; otherwise
		-- reset-on-a-failed-load would clobber the real stored data with defaults.
		if not loadedByUserId[player.UserId] then
			return { ok = false, error = "settings_not_loaded" }
		end
		cancelScheduledFlush(player.UserId)
		local saved = repo:save(player.UserId, SettingsDomain.defaultStoredData())
		if not saved.ok then
			return saved
		end
		storedByUserId[player.UserId] = SettingsDomain.defaultStoredData()
		dirtyByUserId[player.UserId] = false
		pendingFlushByUserId[player.UserId] = nil
		local session = SettingsDomain.defaultSessionData()
		sessionByUserId[player.UserId] = session
		return { ok = true, value = SettingsDomain.merge(storedByUserId[player.UserId], session) }
	end

	function service:onPlayerRemoving(player: Player)
		local userId = player.UserId
		if dirtyByUserId[userId] then
			local result = service:flushStored(player)
			if not result.ok then
				pendingFlushByUserId[userId] = storedByUserId[userId] or SettingsDomain.defaultStoredData()
			end
		end
		cancelScheduledFlush(userId)
		storedByUserId[userId] = nil
		sessionByUserId[userId] = nil
		dirtyByUserId[userId] = nil
		loadedByUserId[userId] = nil
		repo:invalidateCache(userId)
	end

	-- Flush dirty online players + pending snapshots from failed leave flushes.
	-- Returns count of entries still unsaved after the attempt.
	function service:flushShutdown(): number
		local remaining = 0

		for _, player in ipairs(Players:GetPlayers()) do
			if dirtyByUserId[player.UserId] then
				local result = service:flushStored(player)
				if not result.ok then
					remaining += 1
				end
			end
		end

		for userId, stored in pairs(pendingFlushByUserId) do
			local saved = repo:save(userId, stored)
			if saved.ok then
				pendingFlushByUserId[userId] = nil
			else
				remaining += 1
			end
		end

		return remaining
	end

	return service
end

return createSettingsService
