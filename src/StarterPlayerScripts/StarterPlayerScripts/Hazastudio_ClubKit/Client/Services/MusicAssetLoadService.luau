--!strict
-- ContentProvider-driven audio load observation. Skip only on engine-confirmed failure.
-- When MusicAssetCache is provided, uses warmed asset entries for faster ready paths.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

export type WatchOptions = {
	stallLogSeconds: number?,
	cache: any?,
	priority: number?,
	generation: number?,
}

export type WatchCallbacks = {
	onReady: () -> (),
	onDefinitiveFailure: (reason: string, detail: string?) -> (),
	onStallWarning: (() -> ())?,
}

local MusicAssetLoadService = {}

local musicConfig = Config.Music

local function timedOutIsDefinitive(): boolean
	return musicConfig.ASSET_FAILURE_TIMEDOUT_IS_DEFINITIVE == true
end

local function getRetryAttempts(): number
	return math.max(1, math.floor(tonumber(musicConfig.ASSET_FAILURE_RETRY_ATTEMPTS) or 3))
end

local function getRetryBackoff(attempt: number): number
	local tableBackoff = musicConfig.ASSET_FAILURE_RETRY_BACKOFF
	if type(tableBackoff) == "table" and #tableBackoff > 0 then
		local index = math.clamp(attempt, 1, #tableBackoff)
		return math.max(0, tonumber(tableBackoff[index]) or 0)
	end
	return 3 * attempt
end

local function isHardFailureStatus(status: Enum.AssetFetchStatus): boolean
	if status == Enum.AssetFetchStatus.Failure then
		return true
	end
	if status == Enum.AssetFetchStatus.TimedOut and timedOutIsDefinitive() then
		return true
	end
	return false
end

local function isRetryableTimeout(status: Enum.AssetFetchStatus): boolean
	return status == Enum.AssetFetchStatus.TimedOut and not timedOutIsDefinitive()
end

local function isSuccessStatus(status: Enum.AssetFetchStatus): boolean
	return status == Enum.AssetFetchStatus.Success
end

local function soundHasPlayableLength(sound: Sound): boolean
	return sound.IsLoaded and (tonumber(sound.TimeLength) or 0) > 0
end

local function extractAssetIdFromSoundId(soundId: string): any
	local numeric = string.match(soundId, "rbxassetid://(%d+)")
	return tonumber(numeric)
end

-- Returns dispose(). Call dispose on skip/stop/epoch stale.
function MusicAssetLoadService.watchSoundLoad(sound: Sound, options: WatchOptions?, callbacks: WatchCallbacks): () -> ()
	local cache = options and options.cache
	if cache and type(cache.isEnabled) == "function" and cache:isEnabled() then
		local assetId = extractAssetIdFromSoundId(sound.SoundId)
		if assetId then
			local priority = tonumber(options and options.priority) or 0
			local generation = options and options.generation
			if type(cache.scheduleAsset) == "function" then
				cache:scheduleAsset(assetId, priority, generation)
			end
			local cached = if type(cache.getEntry) == "function" then cache:getEntry(assetId) else nil
			if cached and cached.status == "failed" then
				task.defer(function()
					callbacks.onDefinitiveFailure(cached.failedReason or "asset_failed", cached.contentId)
				end)
				return function() end
			end
			if cached and cached.status == "ready" and cached.timeLength and cached.timeLength > 0 then
				task.defer(function()
					if soundHasPlayableLength(sound) then
						callbacks.onReady()
						return
					end
					-- Warm CP cache: playback Sound may still need Loaded; watch below with fast path.
				end)
			end
		end
	end

	local contentId = sound.SoundId
	local disposed = false
	local finished = false
	local conns: { RBXScriptConnection } = {}
	local timeoutAttempts = 0

	local function dispose()
		if disposed then
			return
		end
		disposed = true
		for _, conn in ipairs(conns) do
			conn:Disconnect()
		end
		table.clear(conns)
	end

	local function finishFailure(reason: string, detail: string?)
		if finished or disposed then
			return
		end
		finished = true
		dispose()
		callbacks.onDefinitiveFailure(reason, detail)
	end

	local function finishReady()
		if finished or disposed then
			return
		end
		if not soundHasPlayableLength(sound) then
			return
		end
		finished = true
		dispose()
		callbacks.onReady()
	end

	local function runPreload()
		if disposed or finished then
			return
		end
		pcall(function()
			ContentProvider:PreloadAsync({ sound }, function(_assetId: string, fetchStatus: Enum.AssetFetchStatus)
				if disposed or finished then
					return
				end
				if isHardFailureStatus(fetchStatus) then
					finishFailure("asset_preload_failed", fetchStatus.Name)
				elseif isRetryableTimeout(fetchStatus) then
					scheduleTimeoutRetry("asset_preload_timeout", fetchStatus.Name)
				elseif isSuccessStatus(fetchStatus) and soundHasPlayableLength(sound) then
					finishReady()
				end
			end)
		end)
		if not finished and not disposed and soundHasPlayableLength(sound) then
			finishReady()
		end
	end

	local function scheduleTimeoutRetry(source: string, statusName: string)
		if disposed or finished then
			return
		end
		timeoutAttempts += 1
		if timeoutAttempts >= getRetryAttempts() then
			finishFailure("asset_fetch_status_failure", source .. ":" .. statusName .. ":retries_exhausted")
			return
		end
		local backoff = getRetryBackoff(timeoutAttempts)
		task.delay(backoff, function()
			if disposed or finished then
				return
			end
			runPreload()
		end)
	end

	local function checkStatus(status: Enum.AssetFetchStatus, source: string)
		if isHardFailureStatus(status) then
			finishFailure("asset_fetch_status_failure", source .. ":" .. status.Name)
		elseif isRetryableTimeout(status) then
			scheduleTimeoutRetry(source, status.Name)
		elseif isSuccessStatus(status) and soundHasPlayableLength(sound) then
			finishReady()
		end
	end

	local initialStatus = ContentProvider:GetAssetFetchStatus(contentId)
	checkStatus(initialStatus, "initial")

	if finished or disposed then
		return dispose
	end

	table.insert(
		conns,
		ContentProvider:GetAssetFetchStatusChangedSignal(contentId):Connect(function(newStatus: Enum.AssetFetchStatus)
			checkStatus(newStatus, "status_changed")
		end)
	)

	table.insert(
		conns,
		ContentProvider.AssetFetchFailed:Connect(function(failedContentId: string)
			if failedContentId == contentId then
				finishFailure("asset_fetch_failed", failedContentId)
			end
		end)
	)

	table.insert(conns, sound.Loaded:Connect(function()
		local status = ContentProvider:GetAssetFetchStatus(contentId)
		if isHardFailureStatus(status) then
			finishFailure("asset_fetch_status_failure", "loaded_with_failure_status")
			return
		end
		if isRetryableTimeout(status) then
			scheduleTimeoutRetry("loaded_with_failure_status", status.Name)
			return
		end
		task.defer(function()
			if disposed or finished then
				return
			end
			if soundHasPlayableLength(sound) then
				finishReady()
			end
		end)
	end))

	task.spawn(runPreload)

	if sound.IsLoaded then
		task.defer(function()
			if disposed or finished then
				return
			end
			if soundHasPlayableLength(sound) then
				finishReady()
			end
		end)
	end

	-- Poll cache ready while playback sound loads (prefetch hit).
	if cache and type(cache.getEntry) == "function" then
		local assetId = extractAssetIdFromSoundId(contentId)
		task.spawn(function()
			while not disposed and not finished and assetId do
				local cached = cache:getEntry(assetId)
				if cached and cached.status == "failed" then
					finishFailure(cached.failedReason or "asset_failed", cached.contentId)
					return
				end
				if cached and cached.status == "ready" and soundHasPlayableLength(sound) then
					finishReady()
					return
				end
				task.wait(0.05)
			end
		end)
	end

	local stallSeconds = math.max(30, tonumber(options and options.stallLogSeconds) or 120)
	task.delay(stallSeconds, function()
		if finished or disposed then
			return
		end
		if callbacks.onStallWarning then
			callbacks.onStallWarning()
		end
	end)

	return dispose
end

return MusicAssetLoadService
