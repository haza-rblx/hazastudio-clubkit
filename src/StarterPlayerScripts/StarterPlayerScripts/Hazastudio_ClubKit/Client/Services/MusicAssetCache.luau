--!strict
-- Asset-level audio preload cache for music playback (Horizon A/B prefetch).

local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

export type CacheEntry = {
	status: "loading" | "ready" | "failed",
	timeLength: number?,
	failedReason: string?,
	contentId: string,
}

export type CacheStats = {
	generation: number,
	ready: number,
	loading: number,
	failed: number,
	scheduled: number,
	activeLoads: number,
}

export type HolderStats = {
	total: number,
	loaded: number,
	playing: number,
}

local function timedOutIsDefinitive(config: any): boolean
	return type(config) == "table" and config.ASSET_FAILURE_TIMEDOUT_IS_DEFINITIVE == true
end

local function getRetryAttempts(config: any): number
	if type(config) ~= "table" then
		return 3
	end
	return math.max(1, math.floor(tonumber(config.ASSET_FAILURE_RETRY_ATTEMPTS) or 3))
end

local function getRetryBackoff(config: any, attempt: number): number
	if type(config) ~= "table" then
		return 3 * attempt
	end
	local tableBackoff = config.ASSET_FAILURE_RETRY_BACKOFF
	if type(tableBackoff) == "table" and #tableBackoff > 0 then
		local index = math.clamp(attempt, 1, #tableBackoff)
		return math.max(0, tonumber(tableBackoff[index]) or 0)
	end
	return 3 * attempt
end

local function isHardFailureStatus(status: Enum.AssetFetchStatus, config: any): boolean
	if status == Enum.AssetFetchStatus.Failure then
		return true
	end
	if status == Enum.AssetFetchStatus.TimedOut and timedOutIsDefinitive(config) then
		return true
	end
	return false
end

local function isRetryableTimeout(status: Enum.AssetFetchStatus, config: any): boolean
	return status == Enum.AssetFetchStatus.TimedOut and not timedOutIsDefinitive(config)
end

local function isSuccessStatus(status: Enum.AssetFetchStatus): boolean
	return status == Enum.AssetFetchStatus.Success
end

local function toContentId(assetId: any): string?
	local numericId = tonumber(assetId)
	if not numericId or numericId <= 0 then
		return nil
	end
	return "rbxassetid://" .. tostring(math.floor(numericId))
end

local function soundHasPlayableLength(sound: Sound): boolean
	return sound.IsLoaded and (tonumber(sound.TimeLength) or 0) > 0
end

local DEFAULT_MAX_CACHE_ENTRIES = 48

local function getMaxCacheEntries(config: any): number
	if type(config) ~= "table" then
		return DEFAULT_MAX_CACHE_ENTRIES
	end
	return math.max(8, math.floor(tonumber(config.PREFETCH_MAX_CACHE_ENTRIES) or DEFAULT_MAX_CACHE_ENTRIES))
end

local MusicAssetCache = {}
MusicAssetCache.__index = MusicAssetCache

function MusicAssetCache.create(deps: { config: any, enabled: boolean? })
	local self = setmetatable({}, MusicAssetCache)
	self._config = deps.config
	self._enabled = deps.enabled ~= false
	self._generation = 0
	self._entries = {} :: {
		[string]: {
			status: "loading" | "ready" | "failed",
			timeLength: number?,
			failedReason: string?,
			holder: Sound?,
			holderPlayingConn: RBXScriptConnection?,
			loadGeneration: number,
			lastTouched: number,
		},
	}
	self._pendingJobs = {} :: { { contentId: string, priority: number, generation: number } }
	self._activeLoads = 0
	self._destroyed = false
	self._holderFolder = Instance.new("Folder")
	self._holderFolder.Name = "MusicAssetCacheHolders"
	self._holderFolder.Parent = SoundService
	self._cachedSounds = {} :: { Sound }
	self._pumpScheduled = false
	-- Keep cached sound list in sync with holder folder
	self._holderFolder.ChildAdded:Connect(function(child)
		if child:IsA("Sound") then
			table.insert(self._cachedSounds, child)
		end
	end)
	self._holderFolder.ChildRemoved:Connect(function(child)
		local idx = table.find(self._cachedSounds, child)
		if idx then
			table.remove(self._cachedSounds, idx)
		end
	end)
	return self
end

function MusicAssetCache:isEnabled(): boolean
	return self._enabled and not self._destroyed
end

function MusicAssetCache:getGeneration(): number
	return self._generation
end

function MusicAssetCache:bumpGeneration(): number
	if self._destroyed then
		return self._generation
	end
	self._generation += 1
	table.clear(self._pendingJobs)
	-- Drop prefetch holders from prior track generations (holders are not used for playback).
	for contentId, entry in pairs(self._entries) do
		if entry.loadGeneration < self._generation then
			self:_disposeHolder(entry)
			self._entries[contentId] = nil
		end
	end
	self:_evictUntilUnderCap()
	return self._generation
end

function MusicAssetCache:getProfileMaxConcurrent(): number
	local config = self._config
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	local isSmallViewport = viewport.X <= 900 or viewport.Y <= 600
	local isTouchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local profile = if isTouchOnly or isSmallViewport then "conservative" else "balanced"

	local key = "PREFETCH_PROFILE_" .. string.upper(profile)
	return math.max(1, tonumber(config[key]) or tonumber(config.PREFETCH_PROFILE_BALANCED) or 8)
end

function MusicAssetCache:_waitForNetworkQueue()
	local config = self._config
	local highWatermark = tonumber(config.PREFETCH_QUEUE_HIGH_WATERMARK) or 24
	local pause = tonumber(config.PREFETCH_QUEUE_PAUSE) or 0.12
	while not self._destroyed and ContentProvider.RequestQueueSize > highWatermark do
		task.wait(pause)
	end
end

function MusicAssetCache:getEntry(assetId: any): CacheEntry?
	local contentId = toContentId(assetId)
	if not contentId then
		return {
			status = "failed",
			timeLength = nil,
			failedReason = "asset_invalid_id",
			contentId = "",
		}
	end
	local entry = self._entries[contentId]
	if not entry then
		return nil
	end
	self:_touchEntry(entry)
	return {
		status = entry.status,
		timeLength = entry.timeLength,
		failedReason = entry.failedReason,
		contentId = contentId,
	}
end

function MusicAssetCache:getStats(): CacheStats
	local ready, loading, failed = 0, 0, 0
	for _, entry in pairs(self._entries) do
		if entry.status == "ready" then
			ready += 1
		elseif entry.status == "loading" then
			loading += 1
		elseif entry.status == "failed" then
			failed += 1
		end
	end
	return {
		generation = self._generation,
		ready = ready,
		loading = loading,
		failed = failed,
		scheduled = #self._pendingJobs,
		activeLoads = self._activeLoads,
	}
end

function MusicAssetCache:_touchEntry(entry: { lastTouched: number })
	entry.lastTouched = os.clock()
end

function MusicAssetCache:_evictUntilUnderCap()
	local maxEntries = getMaxCacheEntries(self._config)
	while not self._destroyed do
		local count = 0
		for _ in pairs(self._entries) do
			count += 1
		end
		if count <= maxEntries then
			return
		end

		local evictId: string? = nil
		local evictTouch = math.huge
		local evictIsReady = true

		for contentId, entry in pairs(self._entries) do
			if entry.status == "loading" then
				continue
			end
			local touch = entry.lastTouched or 0
			local isReady = entry.status == "ready"
			local take = evictId == nil
				or (not isReady and evictIsReady)
				or (isReady == evictIsReady and touch < evictTouch)
			if take then
				evictId = contentId
				evictTouch = touch
				evictIsReady = isReady
			end
		end

		if not evictId then
			return
		end

		local doomed = self._entries[evictId]
		if doomed then
			self:_disposeHolder(doomed)
		end
		self._entries[evictId] = nil
	end
end

function MusicAssetCache:_getOrCreateEntry(contentId: string, generation: number)
	local entry = self._entries[contentId]
	if entry then
		self:_touchEntry(entry)
		if entry.status == "failed" then
			return entry
		end
		if entry.status == "ready" then
			return entry
		end
		entry.loadGeneration = math.max(entry.loadGeneration, generation)
		return entry
	end

	self:_evictUntilUnderCap()

	entry = {
		status = "loading",
		timeLength = nil,
		failedReason = nil,
		holder = nil,
		holderPlayingConn = nil,
		loadGeneration = generation,
		lastTouched = os.clock(),
	}
	self._entries[contentId] = entry
	return entry
end

function MusicAssetCache:_disposeHolder(entry: { holder: Sound?, holderPlayingConn: RBXScriptConnection? })
	local conn = entry.holderPlayingConn
	entry.holderPlayingConn = nil
	if conn then
		conn:Disconnect()
	end
	local holder = entry.holder
	entry.holder = nil
	if holder and holder.Parent then
		if holder.IsPlaying then
			holder:Stop()
		end
		holder:Destroy()
	end
end

function MusicAssetCache:_markFailed(entry: any, reason: string, detail: string?)
	entry.status = "failed"
	entry.failedReason = reason
	entry.timeLength = nil
	self:_disposeHolder(entry)
	self:_touchEntry(entry)
	self:_evictUntilUnderCap()
end

function MusicAssetCache:_markReady(entry: any, sound: Sound)
	local duration = tonumber(sound.TimeLength) or 0
	if duration <= 0 then
		self:_markFailed(entry, "asset_zero_duration", nil)
		return
	end
	entry.status = "ready"
	entry.timeLength = duration
	entry.failedReason = nil
	self:_touchEntry(entry)
	self:_evictUntilUnderCap()
end

function MusicAssetCache:_ensureHolder(entry: any, contentId: string): Sound
	local holder = entry.holder
	if holder and holder.Parent then
		return holder
	end
	holder = Instance.new("Sound")
	holder.Name = "MusicPrefetchHolder"
	holder.SoundId = contentId
	holder.Volume = 0
	holder.PlaybackSpeed = 1
	holder.RollOffMaxDistance = 0
	holder.PlayOnRemove = false
	holder.Parent = self._holderFolder
	entry.holder = holder
	entry.holderPlayingConn = holder:GetPropertyChangedSignal("IsPlaying"):Connect(function()
		if not holder.Parent or not holder.IsPlaying then
			return
		end
		warn("[MusicAssetCache] Prefetch holder started playing (stopped immediately)", {
			soundId = holder.SoundId,
		})
		holder:Stop()
	end)
	return holder
end

function MusicAssetCache:_loadContentId(contentId: string, generation: number)
	if self._destroyed or not self._enabled then
		return
	end
	if generation ~= self._generation then
		return
	end

	local entry = self:_getOrCreateEntry(contentId, generation)
	if entry.status == "ready" or entry.status == "failed" then
		return
	end

	self:_waitForNetworkQueue()
	if self._destroyed or generation ~= self._generation then
		return
	end

	local config = self._config
	local timeoutAttempts = 0
	local loadedConn: RBXScriptConnection? = nil
	local statusConn: RBXScriptConnection? = nil
	local failedConn: RBXScriptConnection? = nil

	local function cleanupConns()
		if loadedConn then
			loadedConn:Disconnect()
			loadedConn = nil
		end
		if statusConn then
			statusConn:Disconnect()
			statusConn = nil
		end
		if failedConn then
			failedConn:Disconnect()
			failedConn = nil
		end
	end

	local function resetHolderForRetry()
		cleanupConns()
		self:_disposeHolder(entry)
		entry.status = "loading"
		entry.failedReason = nil
		entry.timeLength = nil
	end

	local holder: Sound

	-- Forward declarations — wireLoadListeners closes over these; must exist before it is created.
	local scheduleTimeoutRetry: (source: string, statusName: string) -> ()
	local checkStatus: (status: Enum.AssetFetchStatus, source: string) -> ()
	local runPreload: () -> ()
	local wireLoadListeners: () -> ()

	local function ensureActiveHolder(): Sound
		holder = self:_ensureHolder(entry, contentId)
		return holder
	end

	scheduleTimeoutRetry = function(source: string, statusName: string)
		if generation ~= self._generation or entry.status ~= "loading" then
			return
		end
		timeoutAttempts += 1
		if timeoutAttempts >= getRetryAttempts(config) then
			self:_markFailed(entry, "asset_fetch_status_failure", source .. ":" .. statusName .. ":retries_exhausted")
			cleanupConns()
			return
		end
		local backoff = getRetryBackoff(config, timeoutAttempts)
		task.delay(backoff, function()
			if self._destroyed or generation ~= self._generation or entry.status ~= "loading" then
				return
			end
			resetHolderForRetry()
			holder = ensureActiveHolder()
			wireLoadListeners()
			runPreload()
		end)
	end

	checkStatus = function(status: Enum.AssetFetchStatus, source: string)
		if generation ~= self._generation or entry.status ~= "loading" then
			return
		end
		if isHardFailureStatus(status, config) then
			self:_markFailed(entry, "asset_fetch_status_failure", source .. ":" .. status.Name)
			cleanupConns()
		elseif isRetryableTimeout(status, config) then
			scheduleTimeoutRetry(source, status.Name)
		elseif isSuccessStatus(status) and soundHasPlayableLength(holder) then
			self:_markReady(entry, holder)
			cleanupConns()
		end
	end

	runPreload = function()
		if generation ~= self._generation or entry.status ~= "loading" then
			return
		end
		pcall(function()
			ContentProvider:PreloadAsync({ holder }, function(_assetId: string, fetchStatus: Enum.AssetFetchStatus)
				if generation ~= self._generation or entry.status ~= "loading" then
					return
				end
				if isHardFailureStatus(fetchStatus, config) then
					self:_markFailed(entry, "asset_preload_failed", fetchStatus.Name)
					cleanupConns()
				elseif isRetryableTimeout(fetchStatus, config) then
					scheduleTimeoutRetry("asset_preload_timeout", fetchStatus.Name)
				elseif isSuccessStatus(fetchStatus) and soundHasPlayableLength(holder) then
					self:_markReady(entry, holder)
					cleanupConns()
				end
			end)
		end)
		if entry.status == "loading" and soundHasPlayableLength(holder) then
			self:_markReady(entry, holder)
			cleanupConns()
		end
	end

	wireLoadListeners = function()
		loadedConn = holder.Loaded:Connect(function()
			if generation ~= self._generation or entry.status ~= "loading" then
				cleanupConns()
				return
			end
			local status = ContentProvider:GetAssetFetchStatus(contentId)
			if isHardFailureStatus(status, config) then
				self:_markFailed(entry, "asset_fetch_status_failure", "loaded_with_failure_status")
				cleanupConns()
				return
			end
			if isRetryableTimeout(status, config) then
				scheduleTimeoutRetry("loaded_with_failure_status", status.Name)
				return
			end
			if soundHasPlayableLength(holder) then
				self:_markReady(entry, holder)
				cleanupConns()
			end
		end)

		statusConn = ContentProvider:GetAssetFetchStatusChangedSignal(contentId):Connect(function(newStatus: Enum.AssetFetchStatus)
			checkStatus(newStatus, "status_changed")
			if entry.status ~= "loading" then
				cleanupConns()
			end
		end)

		failedConn = ContentProvider.AssetFetchFailed:Connect(function(failedContentId: string)
			if failedContentId == contentId then
				self:_markFailed(entry, "asset_fetch_failed", failedContentId)
				cleanupConns()
			end
		end)
	end

	holder = ensureActiveHolder()

	checkStatus(ContentProvider:GetAssetFetchStatus(contentId), "initial")
	if entry.status ~= "loading" then
		return
	end

	wireLoadListeners()
	runPreload()
end

function MusicAssetCache:_pumpQueue()
	if self._pumpScheduled or self._destroyed or not self._enabled then
		return
	end
	self._pumpScheduled = true
	task.spawn(function()
		self._pumpScheduled = false
		if self._destroyed then
			return
		end

		table.sort(self._pendingJobs, function(a, b)
			if a.priority ~= b.priority then
				return a.priority < b.priority
			end
			return false
		end)

		local maxConcurrent = self:getProfileMaxConcurrent()
		while not self._destroyed and #self._pendingJobs > 0 and self._activeLoads < maxConcurrent do
			local jobIndex: number? = nil
			for i, job in ipairs(self._pendingJobs) do
				if job.generation == self._generation then
					jobIndex = i
					break
				end
			end
			if not jobIndex then
				table.clear(self._pendingJobs)
				break
			end

			local job = table.remove(self._pendingJobs, jobIndex)
			if not job then
				break
			end

			local entry = self._entries[job.contentId]
			if entry and (entry.status == "ready" or entry.status == "failed") then
				continue
			end

			self._activeLoads += 1
			task.spawn(function()
				self:_loadContentId(job.contentId, job.generation)
				self._activeLoads = math.max(0, self._activeLoads - 1)
				self:_pumpQueue()
			end)
		end
	end)
end

function MusicAssetCache:scheduleAsset(assetId: any, priority: number, generation: number?)
	if not self:isEnabled() then
		return
	end
	local contentId = toContentId(assetId)
	if not contentId then
		return
	end
	local gen = generation or self._generation
	local entry = self._entries[contentId]
	if entry and (entry.status == "ready" or entry.status == "failed") then
		return
	end

	for _, job in ipairs(self._pendingJobs) do
		if job.contentId == contentId and job.generation == gen then
			if priority < job.priority then
				job.priority = priority
			end
			self:_pumpQueue()
			return
		end
	end

	table.insert(self._pendingJobs, {
		contentId = contentId,
		priority = priority,
		generation = gen,
	})
	self:_getOrCreateEntry(contentId, gen)
	self:_pumpQueue()
end

function MusicAssetCache:scheduleAssets(assetIds: { any }, priority: number, generation: number?)
	for _, assetId in ipairs(assetIds) do
		self:scheduleAsset(assetId, priority, generation)
	end
end

function MusicAssetCache:getHolderStats(): HolderStats
		local total, loaded, playing = 0, 0, 0
		-- Use cached sound list instead of GetChildren scan
		for _, child in ipairs(self._cachedSounds) do
			if child.Parent then
				total += 1
				if child.IsLoaded then
					loaded += 1
				end
				if child.IsPlaying then
					playing += 1
				end
			end
		end
		return {
			total = total,
			loaded = loaded,
			playing = playing,
		}
	end

function MusicAssetCache:createPlaybackSound(assetId: any, instanceName: string): Sound?
	local contentId = toContentId(assetId)
	if not contentId then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = instanceName
	sound.SoundId = contentId
	sound.Volume = 0
	sound.PlaybackSpeed = 1
	sound.RollOffMaxDistance = 0
	return sound
end

function MusicAssetCache:destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	table.clear(self._pendingJobs)
	for _, entry in pairs(self._entries) do
		self:_disposeHolder(entry)
	end
	table.clear(self._entries)
	if self._holderFolder.Parent then
		self._holderFolder:Destroy()
	end
end

return MusicAssetCache
