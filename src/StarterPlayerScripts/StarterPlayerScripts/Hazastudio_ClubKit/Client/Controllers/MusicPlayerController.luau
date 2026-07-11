--!strict
-- PATH: StarterPlayerScripts/Client/Controllers/MusicPlayerController.lua
-- Client orchestrator: Sound engine + wire store -> UI + remotes.
-- Multi-part audio: play part 1..N sequential, seek to elapsed on join.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local NotifService = require(script.Parent.Parent.Services.NotifService)
local MobilePanelManager = require(script.Parent.Parent.Services.MobilePanelManager)
local MusicAssetLoadService = require(script.Parent.Parent.Services.MusicAssetLoadService)
local MusicAssetCache = require(script.Parent.Parent.Services.MusicAssetCache)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MusicDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.MusicDomain)

type NotifType = NotifService.NotifType
type NotificationPayload = {
	message: string?,
	title: string?,
	description: string?,
	domain: string?,
	dedupeKey: string?,
	duration: number?,
	iconImage: string?,
}

local MusicPlayerController = {} :: any
MusicPlayerController.__index = MusicPlayerController

local MUSIC_DATA_CACHE_TTL = 8
local MAX_TRACK_CACHE_PLAYLISTS = 16
local FALLBACK_REMOTE_REQUEST_TIMEOUT = 10
local FALLBACK_FAVORITES_PLAYLIST_ID = "__favorites__"
local FALLBACK_NEW_DROPS_PLAYLIST_ID = "__new_drops__"
local FALLBACK_FAVORITES_ATTRIBUTE_KEY = "MusicFavoriteTrackIds"

local function getSpecialPlaylistIds(config: any): (string, string)
	return tostring(config.SPECIAL_PLAYLIST_FAVORITES_ID or FALLBACK_FAVORITES_PLAYLIST_ID),
		tostring(config.SPECIAL_PLAYLIST_NEW_DROPS_ID or FALLBACK_NEW_DROPS_PLAYLIST_ID)
end

local function getFavoriteAttributeKey(config: any): string
	return tostring(config.FAVORITES_ATTRIBUTE_KEY or FALLBACK_FAVORITES_ATTRIBUTE_KEY)
end

local function readFavoriteTrackIdsFromPlayer(config: any): { [string]: boolean }
	local player = Players.LocalPlayer
	local raw = player and player:GetAttribute(getFavoriteAttributeKey(config))
	if type(raw) ~= "string" or raw == "" then
		return {}
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not ok or type(decoded) ~= "table" then
		return {}
	end

	local favorites = {} :: { [string]: boolean }
	for trackId, isFavorited in pairs(decoded) do
		if type(trackId) == "string" and isFavorited == true then
			favorites[trackId] = true
		end
	end
	return favorites
end

local function trimNotificationText(text: string): string
	return text:match("^%s*(.-)%s*$") or ""
end

local function destroySoundChild(sound: Sound, childName: string)
	local child = sound:FindFirstChild(childName)
	if child then
		child:Destroy()
	end
end

local function findDjConfigItem(config: any, itemId: string?): any?
	if type(config) ~= "table" or type(config.DJ) ~= "table" or type(itemId) ~= "string" or itemId == "" then
		return nil
	end

	local items = config.DJ.SOUND_BOARD_ITEMS
	if type(items) ~= "table" then
		return nil
	end

	for _, item in ipairs(items) do
		if type(item) == "table" and tostring(item.id or "") == itemId then
			return item
		end
	end

	return nil
end

local function getDjEffectsConfig(config: any): { any }
	if type(config) ~= "table" or type(config.DJ) ~= "table" or type(config.DJ.EFFECTS) ~= "table" then
		return {}
	end
	return config.DJ.EFFECTS
end

local function findDjEffectConfig(config: any, effectId: string): any?
	for _, effect in ipairs(getDjEffectsConfig(config)) do
		if type(effect) == "table" and tostring(effect.id or "") == effectId then
			return effect
		end
	end
	return nil
end

local function findDjEffectItem(effect: any, itemId: string): any?
	if type(effect) ~= "table" or type(effect.items) ~= "table" then
		return nil
	end
	for _, item in ipairs(effect.items) do
		if type(item) == "table" and tostring(item.id or item.property or "") == itemId then
			return item
		end
	end
	return nil
end

local function buildDefaultDjEffectState(config: any): ({ [string]: boolean }, { [string]: { [string]: number } })
	local enabledById = {} :: { [string]: boolean }
	local valuesByEffect = {} :: { [string]: { [string]: number } }

	for _, effect in ipairs(getDjEffectsConfig(config)) do
		if type(effect) == "table" then
			local effectId = tostring(effect.id or "")
			if effectId ~= "" then
				enabledById[effectId] = effect.defaultEnabled == true
				valuesByEffect[effectId] = {}
				if type(effect.items) == "table" then
					for _, item in ipairs(effect.items) do
						if type(item) == "table" then
							local itemId = tostring(item.id or item.property or "")
							if itemId ~= "" then
								valuesByEffect[effectId][itemId] = tonumber(item.defaultValue) or 0
							end
						end
					end
				end
			end
		end
	end

	return enabledById, valuesByEffect
end

-- ============================================================
-- FACTORY
-- ============================================================

function MusicPlayerController.create(
	deps: {
		refs: any, -- MusicPlayerGuiRefs.Refs
		store: any,
		binder: any, -- MusicPlayerUIBinder
		remotes: Folder,
		config: any, -- Config.Music
		topbarIcon: any, -- MusicTopbarIcon wrapper (owns lifecycle, fan-out events)
		logger: any, -- ILogger
	}
)
	local self = setmetatable({}, MusicPlayerController) :: any
	self._refs = deps.refs
	self._store = deps.store
	self._binder = deps.binder
	self._remotes = deps.remotes
	self._config = deps.config
	self._topbarIcon = deps.topbarIcon
	self._lastResyncAt = 0
	self._lastSelfHealAt = 0
	self._resyncInFlight = false
	self._lastDjModeRequiredNotifyAt = 0
	self._log = deps.logger
	self._playbackSpeed = math.max(0.05, tonumber(deps.config.PLAYBACK_SPEED) or 1)
	self._pitchSemitones = tonumber(deps.config.PITCH_SEMITONES) or 0
	self._pitchOctave = 2 ^ (self._pitchSemitones / 12)
	self._trackFadeInTime = math.max(0, tonumber(deps.config.TRACK_FADE_IN_TIME) or 0)
	self._trackFadeOutTime = math.max(0, tonumber(deps.config.TRACK_FADE_OUT_TIME) or 0)
	local defaultEffectEnabled, defaultEffectValues = buildDefaultDjEffectState(deps.config)
	self._djEffectEnabledById = defaultEffectEnabled
	self._djEffectValues = defaultEffectValues
	-- Speed system: base × multiplier.
	-- _baseSpeed = "normal" speed for current track (from track.playbackSpeed or Config)
	-- _djSpeedMultiplier = DJ slider value (1.0 = no change, 2.0 = double speed)
	-- _playbackSpeed = actual Sound.PlaybackSpeed = _baseSpeed × _djSpeedMultiplier
	self._baseSpeed = math.max(0.05, tonumber(deps.config.PLAYBACK_SPEED) or 1)
	self._djSpeedMultiplier = 1.0
	self._playbackSpeed = self._baseSpeed * self._djSpeedMultiplier
	self._djSoundboardFallbackSoundId =
		tostring((deps.config.DJ and deps.config.DJ.SOUND_BOARD_FALLBACK_SOUND_ID) or "")

	-- Sound engine state
	self._activeSounds = {} :: { [number]: Sound } -- { [partIndex]: Sound }
	self._fadingOutSounds = {} :: { [Sound]: boolean } -- fade-out tweens (excluded from orphan kill)
	self._currentPartIdx = 1
	self._currentTrackId = nil :: string?
	self._playbackStartKey = nil :: string? -- trackId:startServerTime dedupe for StateSync + TrackChanged
	self._playbackStartClock = 0 :: number -- os.clock when current track playback started (stall guard)
	self._playbackEpoch = 0 -- bumped on stop; invalidates stale Loaded/Ended callbacks
	self._partAdvanceInFlight = false -- part N→N+1 transition
	self._partDurations = {} :: { [number]: number } -- cache durasi per part
	self._assetFailureReportedTrackIds = {} :: { [string]: boolean }
	self._prefetchGeneration = 0
	self._assetCache = MusicAssetCache.create({
		config = deps.config,
		enabled = deps.config.PREFETCH_ENABLED ~= false,
	})

	-- Remote refs (lazy, wait saat init)
	self._trackChangedRE = nil :: RemoteEvent?
	self._queueUpdatedRE = nil :: RemoteEvent?
	self._stateSyncRE = nil :: RemoteEvent?
	self._voteStateRE = nil :: RemoteEvent?
	self._durationReportRE = nil :: RemoteEvent?
	self._playbackFinishedRE = nil :: RemoteEvent?
	self._timingUpdatedRE = nil :: RemoteEvent?
	self._voteSkipRE = nil :: RemoteEvent?
	self._requestTrackRE = nil :: RemoteEvent?
	self._adminSkipRE = nil :: RemoteEvent?
	self._reportFailureRE = nil :: RemoteEvent?
	self._playbackIncidentRE = nil :: RemoteEvent?
	self._musicResponseRE = nil :: RemoteEvent?
	self._getStateRE = nil :: RemoteEvent?
	self._getPlaylistsRE = nil :: RemoteEvent?
	self._getTracksRE = nil :: RemoteEvent?
	self._favoriteTrackRE = nil :: RemoteEvent?
	self._setDjModeRE = nil :: RemoteEvent?
	self._managePlRE = nil :: RemoteEvent?
	self._manageTrRE = nil :: RemoteEvent?
	self._resolveRequestAssetRE = nil :: RemoteEvent?
	self._zoneChangedRE = nil :: RemoteEvent?
	self._connections = {} :: { RBXScriptConnection }
	self._unsubscribers = {} :: { () -> () }
	self._pendingMusicRequests = {} :: { [string]: any }
	self._isPanelOpen = false
	self._panelSessionId = 0
	self._hasReceivedZoneEvent = false -- true after first _zoneChangedRE fire
	self._playlistsLoadedAt = 0
	self._playlistsCache = {} :: any
	self._tracksCacheByPlaylist = {} :: { [string]: { loadedAt: number, data: any } }
	self._durationReportedTrackIds = {} :: { [string]: boolean }
	self._listenersConnected = false
	self._initRetryScheduled = false
	self._engineInitialized = false
	self._panelInitialized = false
	self._settingsVolumeBound = false

	return self
end

function MusicPlayerController:_getEffectivePartDuration(rawDuration: number): number
	return rawDuration / self._playbackSpeed
end

function MusicPlayerController:_getRawTimePositionFromElapsed(elapsed: number): number
	return elapsed * self._playbackSpeed
end

function MusicPlayerController:_resolveServerTiming(data: any): any?
	if type(data) ~= "table" then
		return nil
	end
	if type(data.timing) == "table" then
		return data.timing
	end
	local startServerTime = tonumber(data.startServerTime) or 0
	local expectedEndServerTime = tonumber(data.expectedEndServerTime) or 0
	if startServerTime > 0 and expectedEndServerTime > startServerTime then
		return MusicDomain.buildPlaybackTiming(startServerTime, expectedEndServerTime, 1)
	end
	if startServerTime > 0 then
		return MusicDomain.buildPlaybackTiming(startServerTime, startServerTime, 1)
	end
	return nil
end

function MusicPlayerController:_buildStoreTimingPatch(data: any): { [string]: any }
	local timing = self:_resolveServerTiming(data)
	if type(timing) == "table" then
		return {
			playbackTiming = timing,
			startServerTime = timing.startServerTime,
			expectedEndServerTime = timing.expectedEndServerTime,
		}
	end
	return {
		playbackTiming = self._store.NONE,
		startServerTime = 0,
		expectedEndServerTime = 0,
	}
end

function MusicPlayerController:_reportPlaybackFinished(trackId: string)
	if not self._playbackFinishedRE or trackId == "" then
		return
	end
	self._playbackFinishedRE:FireServer({
		trackId = trackId,
	})
end

function MusicPlayerController:_onTimingUpdated(data: any)
	if type(data) ~= "table" or type(data.timing) ~= "table" then
		return
	end
	local state = self._store:get()
	local currentTrack = state.currentTrack
	if type(currentTrack) ~= "table" then
		return
	end
	if type(data.trackId) == "string" and data.trackId ~= "" and currentTrack.id ~= data.trackId then
		return
	end
	self._store:set(self:_buildStoreTimingPatch(data))
	if self._panelInitialized then
		self._binder:refreshProgressFromStore()
	end
end

-- Sound engine

function MusicPlayerController:_isStalePlayback(track: any, playbackEpoch: number): boolean
	if type(track) ~= "table" or track.id ~= self._currentTrackId then
		return true
	end
	return playbackEpoch ~= self._playbackEpoch
end

function MusicPlayerController:_makePlaybackStartKey(trackId: string, startServerTime: number): string
	return ("%s:%.3f"):format(trackId, startServerTime)
end

function MusicPlayerController:_shouldSkipDuplicatePlaybackStart(trackId: string, startServerTime: number): boolean
	local key = self:_makePlaybackStartKey(trackId, startServerTime)
	if self._playbackStartKey ~= key then
		return false
	end
	-- Only skip when playback is actually healthy. A matched start key with no
	-- active sound means load failed or sounds were destroyed — allow restart.
	if self._currentTrackId ~= trackId then
		return false
	end
	return self:_hasActivePlayback()
end

function MusicPlayerController:_markPlaybackStart(trackId: string, startServerTime: number)
	self._playbackStartKey = self:_makePlaybackStartKey(trackId, startServerTime)
	self._playbackStartClock = os.clock()
end

function MusicPlayerController:_destroySound(sound: Sound?)
	if not sound then
		return
	end
	self._fadingOutSounds[sound] = nil
	if sound.Parent then
		sound:Stop()
		sound:Destroy()
	end
end

-- Client detects unloadable audio locally. Server does not global-skip; optional telemetry only.
function MusicPlayerController:_reportTrackAssetFailure(trackId: string, reason: string, context: { [string]: any }?)
	if self._currentTrackId ~= trackId then
		return
	end
	if self._assetFailureReportedTrackIds[trackId] then
		self._log:debug("Track asset failure already reported", { trackId = trackId, reason = reason })
		return
	end
	-- Race condition guard: jika sound sudah berhasil playing, jangan report failure.
	-- Ini mencegah deferred report dari transient failure yang sudah recover.
	if self:_hasActivePlayback() then
		self._log:debug("Track asset failure suppressed (sound already playing)", {
			trackId = trackId,
			reason = reason,
		})
		return
	end

	local minStallSeconds = math.max(
		0,
		tonumber(self._config.ASSET_FAILURE_SKIP_MIN_STALL_SECONDS) or 60
	)
	local elapsedSinceStart = if self._playbackStartClock > 0
		then os.clock() - self._playbackStartClock
		else 0
	if elapsedSinceStart < minStallSeconds then
		local waitSeconds = minStallSeconds - elapsedSinceStart
		self._log:warn("Music asset failure deferred (stall guard)", {
			trackId = trackId,
			reason = reason,
			waitSeconds = math.floor(waitSeconds * 10) / 10,
		})
		task.delay(waitSeconds, function()
			if self._currentTrackId ~= trackId then
				return
			end
			if self._assetFailureReportedTrackIds[trackId] then
				return
			end
			-- Re-check active playback: jika sound sudah recover dan playing,
			-- jangan kirim failure report (transient failure recovered).
			if self:_hasActivePlayback() then
				self._log:debug("Deferred track failure cancelled (sound recovered)", {
					trackId = trackId,
					reason = reason,
				})
				return
			end
			self:_reportTrackAssetFailure(trackId, reason, context)
		end)
		return
	end

	self._assetFailureReportedTrackIds[trackId] = true
	self._log:warn("Track asset failed locally", {
		trackId = trackId,
		reason = reason,
		context = context,
	})
	if self._config.ASSET_FAILURE_REPORT_TO_SERVER ~= true or not self._reportFailureRE then
		return
	end
	self._reportFailureRE:FireServer({
		requestId = HttpService:GenerateGUID(false),
		trackId = trackId,
		reason = reason,
	})
end

function MusicPlayerController:_isPrefetchEnabled(): boolean
	return self._config.PREFETCH_ENABLED ~= false
		and self._assetCache ~= nil
		and self._assetCache:isEnabled()
end

function MusicPlayerController:_bumpPrefetchGeneration(): number
	if self._assetCache then
		self._prefetchGeneration = self._assetCache:bumpGeneration()
	end
	return self._prefetchGeneration
end

function MusicPlayerController:_applyCachedPartDuration(partIndex: number, assetId: any): boolean
	if not self:_isPrefetchEnabled() then
		return false
	end
	local entry = self._assetCache:getEntry(assetId)
	if entry and entry.status == "ready" and entry.timeLength and entry.timeLength > 0 then
		self._partDurations[partIndex] = self:_getEffectivePartDuration(entry.timeLength)
		return true
	end
	return false
end

function MusicPlayerController:_schedulePrefetchPartsForTrack(track: any, trackSlot: number, gen: number)
	if type(track) ~= "table" or type(track.parts) ~= "table" then
		return
	end
	for partIndex, partAssetId in ipairs(track.parts) do
		-- Current track (slot 0): all parts highest priority. Queue lookahead: lower.
		local priority = if trackSlot == 0 then 1 elseif trackSlot == 1 and partIndex == 1 then 2 else 3
		self._assetCache:scheduleAsset(partAssetId, priority, gen)
	end
end

function MusicPlayerController:_schedulePrefetch(currentTrack: any?, userQueue: { any }?, prefetchBuffer: { any }?)
	if not self:_isPrefetchEnabled() then
		return
	end
	local gen = self._prefetchGeneration
	local tracksAhead = math.max(1, math.floor(tonumber(self._config.PREFETCH_TRACKS_AHEAD) or 3))
	local refillMax = math.max(0, math.floor(tonumber(self._config.AUTO_BUFFER_REFILL_MAX_USER_QUEUE) or 1))

	if type(currentTrack) == "table" then
		self:_schedulePrefetchPartsForTrack(currentTrack, 0, gen)
	end

	local userCount = if type(userQueue) == "table" then #userQueue else 0
	local slotsUsed = 0
	if type(userQueue) == "table" then
		for queueIndex = 1, math.min(tracksAhead, #userQueue) do
			slotsUsed += 1
			self:_schedulePrefetchPartsForTrack(userQueue[queueIndex], queueIndex, gen)
		end
	end

	if userCount <= refillMax and slotsUsed < tracksAhead and type(prefetchBuffer) == "table" then
		for bufferIndex = 1, math.min(tracksAhead - slotsUsed, #prefetchBuffer) do
			self:_schedulePrefetchPartsForTrack(prefetchBuffer[bufferIndex], slotsUsed + bufferIndex, gen)
		end
	end
end

function MusicPlayerController:_schedulePrefetchFromStore(currentTrack: any?)
	local state = self._store:get()
	self:_schedulePrefetch(currentTrack, state.queue, state.prefetchBuffer)
end

function MusicPlayerController:_stopAllSounds(fadeDuration: number?)
	self._playbackEpoch += 1
	self:_bumpPrefetchGeneration()
	local shouldFade = type(fadeDuration) == "number" and fadeDuration > 0
	local soundsToStop = self._activeSounds
	self._activeSounds = {}
	self._currentPartIdx = 1

	for _, sound in pairs(soundsToStop) do
		if shouldFade and sound.Parent then
			local resolvedFadeDuration = fadeDuration :: number
			self._fadingOutSounds[sound] = true
			local tween = TweenService:Create(
				sound,
				TweenInfo.new(resolvedFadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Volume = 0 }
			)
			tween.Completed:Once(function()
				self._fadingOutSounds[sound] = nil
				if sound.Parent then
					self:_destroySound(sound)
				end
			end)
			-- Safety net: clean up if tween.Completed never fires (sound destroyed externally)
			task.delay(resolvedFadeDuration + 1, function()
				if self._fadingOutSounds[sound] then
					self._fadingOutSounds[sound] = nil
					if sound.Parent then
						self:_destroySound(sound)
					end
				end
			end)
			tween:Play()
		else
			self:_destroySound(sound)
		end
	end
end

-- startServerTime + accumDur (opsional): jika diteruskan dari _seekToElapsed,
-- onLoaded() akan menghitung ulang posisi seek dari GetServerTimeNow() agar
-- delay loading asset tidak menyebabkan desync antar player.
function MusicPlayerController:_playFromPart(
	track: any,
	partIndex: number,
	seekTo: number,
	fadeInDuration: number?,
	startServerTime: number?,
	accumDur: number?
)
	if not track or not track.parts or partIndex > #track.parts then
		-- Semua part selesai -> advance request ke server (server yang putuskan)
		return
	end
	if self._currentTrackId ~= track.id then
		return
	end

	local playbackEpoch = self._playbackEpoch
	local assetId = track.parts[partIndex]
	if self:_isPrefetchEnabled() then
		for upcomingIndex = partIndex + 1, #track.parts do
			self._assetCache:scheduleAsset(track.parts[upcomingIndex], 0, self._prefetchGeneration)
		end
		local cached = self._assetCache:getEntry(assetId)
		if cached and cached.status == "failed" then
			self:_reportTrackAssetFailure(track.id, cached.failedReason or "asset_failed", {
				partIndex = partIndex,
				assetId = assetId,
			})
			return
		end
	end
	local volume = self._store:get().volume
	self._log:debug("Music part playback start", {
		assetId = tostring(assetId),
		partIndex = partIndex,
		seekTo = seekTo,
		trackId = tostring(track.id),
	})

	local soundName = ("MusicPart_%s_p%d_e%d"):format(tostring(track.id), partIndex, playbackEpoch)
	local sound: Sound
	if self:_isPrefetchEnabled() then
		local cachedSound = self._assetCache:createPlaybackSound(assetId, soundName)
		if cachedSound then
			sound = cachedSound
		else
			sound = Instance.new("Sound")
			sound.SoundId = "rbxassetid://" .. tostring(assetId)
			sound.Name = soundName
		end
	else
		sound = Instance.new("Sound")
		sound.SoundId = "rbxassetid://" .. tostring(assetId)
		sound.Name = soundName
	end
	sound.Volume = if (fadeInDuration or 0) > 0 then 0 else volume
	sound.RollOffMaxDistance = 0 -- non-spatial (music)
	sound.Parent = SoundService
	self:_applyDjSoundSettings(sound)
	if self:_applyCachedPartDuration(partIndex, assetId) then
		self:_tryReportDuration(track)
	end

	self._activeSounds[partIndex] = sound
	self._partAdvanceInFlight = false

	local loaded = false
	local disposeLoadWatch: (() -> ())? = nil

	local function stopLoadWatch()
		if disposeLoadWatch then
			disposeLoadWatch()
			disposeLoadWatch = nil
		end
	end

	local function onLoaded()
		if loaded then
			return
		end
		loaded = true
		stopLoadWatch()

		if self:_isStalePlayback(track, playbackEpoch) then
			self:_destroySound(sound)
			if self._activeSounds[partIndex] == sound then
				self._activeSounds[partIndex] = nil
			end
			return
		end

		local partDuration = self:_getEffectivePartDuration(sound.TimeLength)
		if partDuration <= 0 then
			-- TimeLength can be 0 for a frame right after Loaded; recheck once.
			task.defer(function()
				if self:_isStalePlayback(track, playbackEpoch) then
					return
				end
				if self._activeSounds[partIndex] ~= sound or not sound.Parent then
					return
				end
				local retryDuration = self:_getEffectivePartDuration(sound.TimeLength)
				if retryDuration > 0 then
					loaded = false
					onLoaded()
					return
				end
				self:_destroySound(sound)
				if self._activeSounds[partIndex] == sound then
					self._activeSounds[partIndex] = nil
				end
				self:_reportTrackAssetFailure(track.id, "asset_zero_duration", {
					partIndex = partIndex,
					assetId = assetId,
				})
			end)
			return
		end
		self._partDurations[partIndex] = partDuration

		-- Hitung posisi seek: jika startServerTime tersedia, gunakan server clock
		-- saat ini agar load-delay asset tidak menyebabkan desync.
		local effectiveSeekTo: number
		if startServerTime and startServerTime > 0 then
			local freshElapsed = workspace:GetServerTimeNow() - startServerTime
			effectiveSeekTo = math.max(0, freshElapsed - (accumDur or 0))
		else
			effectiveSeekTo = seekTo
		end

		local partEffectiveDur = self._partDurations[partIndex]

		-- Jika posisi seek melampaui durasi part ini, lewati ke part berikutnya.
		-- Ini terjadi saat durasi tidak diketahui di _seekToElapsed (pertama kali
		-- join) dan track sudah berada di part 2+.
		if
			startServerTime
			and startServerTime > 0
			and partEffectiveDur
			and partEffectiveDur > 0
			and effectiveSeekTo >= partEffectiveDur
		then
			self:_destroySound(sound)
			self._activeSounds[partIndex] = nil
			if self:_isStalePlayback(track, playbackEpoch) then
				return
			end
			self._partAdvanceInFlight = true
			local nextAccumDur = (accumDur or 0) + partEffectiveDur
			self:_playFromPart(track, partIndex + 1, 0, fadeInDuration, startServerTime, nextAccumDur)
			return
		end

		if self:_isStalePlayback(track, playbackEpoch) then
			self:_destroySound(sound)
			if self._activeSounds[partIndex] == sound then
				self._activeSounds[partIndex] = nil
			end
			return
		end

		local rawSeekTo = self:_getRawTimePositionFromElapsed(effectiveSeekTo)
		if rawSeekTo > 0 and rawSeekTo < sound.TimeLength then
			sound.TimePosition = rawSeekTo
		end
		sound:Play()
		if (fadeInDuration or 0) > 0 then
			local resolvedFadeInDuration = fadeInDuration or 0
			TweenService
				:Create(sound, TweenInfo.new(resolvedFadeInDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Volume = math.clamp(tonumber(self._store:get().volume) or volume, 0, 1),
				})
				:Play()
		end

		-- Setelah ALL parts loaded pertama kali -> hitung total durasi -> report ke server
		self:_tryReportDuration(track)
	end

	local function onEnded()
		if self:_isStalePlayback(track, playbackEpoch) then
			return
		end
		local nextIdx = partIndex + 1
		if nextIdx > #track.parts then
			self:_reportPlaybackFinished(track.id)
			return
		end
		if self._activeSounds[partIndex] == sound then
			self._activeSounds[partIndex] = nil
		end
		self:_destroySound(sound)
		self._partAdvanceInFlight = true
		task.spawn(function()
			if self:_isStalePlayback(track, playbackEpoch) then
				self._partAdvanceInFlight = false
				return
			end
			self:_playFromPart(track, nextIdx, 0, self._trackFadeInTime)
			self._partAdvanceInFlight = false
		end)
	end

	sound.Ended:Connect(onEnded)

	local watchOptions: MusicAssetLoadService.WatchOptions = {
		stallLogSeconds = tonumber(self._config.ASSET_LOAD_STALL_LOG_SECONDS) or 120,
	}
	if self:_isPrefetchEnabled() then
		watchOptions.cache = self._assetCache
		watchOptions.priority = 0
		watchOptions.generation = self._prefetchGeneration
	end
	disposeLoadWatch = MusicAssetLoadService.watchSoundLoad(
		sound,
		watchOptions,
		{
			onReady = onLoaded,
			onDefinitiveFailure = function(reason: string, detail: string?)
				if loaded or self:_isStalePlayback(track, playbackEpoch) then
					return
				end
				loaded = true
				stopLoadWatch()
				self:_destroySound(sound)
				if self._activeSounds[partIndex] == sound then
					self._activeSounds[partIndex] = nil
				end
				self:_reportTrackAssetFailure(track.id, reason, {
					partIndex = partIndex,
					assetId = assetId,
					detail = detail,
				})
			end,
			onStallWarning = function()
				if loaded or self:_isStalePlayback(track, playbackEpoch) then
					return
				end
				self._log:warn("Music asset still loading (stall log only, will not auto-skip)", {
					trackId = track.id,
					partIndex = partIndex,
					assetId = tostring(assetId),
					soundId = sound.SoundId,
				})
			end,
		}
	)
end

function MusicPlayerController:_probePartDuration(track: any, partIndex: number, assetId: any)
	if self._currentTrackId ~= track.id then
		return
	end
	if self._partDurations[partIndex] and self._partDurations[partIndex] > 0 then
		return
	end
	if self:_isPrefetchEnabled() then
		self._assetCache:scheduleAsset(assetId, 0, self._prefetchGeneration)
		if self:_applyCachedPartDuration(partIndex, assetId) then
			self:_tryReportDuration(track)
			return
		end
		local cached = self._assetCache:getEntry(assetId)
		if cached and cached.status == "failed" then
			return
		end
	end

	local probe = Instance.new("Sound")
	probe.SoundId = "rbxassetid://" .. tostring(assetId)
	probe.Volume = 0
	probe.PlaybackSpeed = 1
	probe.RollOffMaxDistance = 0
	probe.Parent = SoundService

	local finalized = false
	local conn: RBXScriptConnection?

	local function finalize()
		if finalized then
			return
		end
		finalized = true
		if conn then
			conn:Disconnect()
			conn = nil
		end

		local duration = tonumber(probe.TimeLength) or 0
		if self._currentTrackId == track.id and duration > 0 then
			self._partDurations[partIndex] = self:_getEffectivePartDuration(duration)
			self:_tryReportDuration(track)
		end

		probe:Destroy()
	end

	if probe.IsLoaded then
		finalize()
	else
		conn = probe.Loaded:Connect(finalize)
	end
end

function MusicPlayerController:_primeTrackPartDurations(track: any)
	if type(track) ~= "table" or type(track.parts) ~= "table" then
		return
	end

	for partIndex, assetId in ipairs(track.parts) do
		if not self._partDurations[partIndex] or self._partDurations[partIndex] <= 0 then
			task.spawn(function()
				self:_probePartDuration(track, partIndex, assetId)
			end)
		end
	end
end

function MusicPlayerController:_tryReportDuration(track: any)
	local serverDuration = tonumber(track.totalDuration) or 0
	if serverDuration > 0 then
		self._binder:setTotalDuration(serverDuration)
	end

	-- Hitung total jika semua parts sudah punya durasi
	local parts = track.parts
	local total = 0
	if type(parts) ~= "table" or #parts == 0 then
		return
	end

	for i = 1, #parts do
		local dur = self._partDurations[i]
		if not dur or dur <= 0 then
			return
		end
		total += dur
	end

	if total <= 0 then
		return
	end

	self._binder:setTotalDuration(total)
	local currentTrack = self._store:get().currentTrack
	if currentTrack and currentTrack.id == track.id then
		local updatedTrack = table.clone(currentTrack)
		updatedTrack.totalDuration = total
		self._store:set({
			currentTrack = updatedTrack,
		})
	end

	local durationNeedsReport = serverDuration <= 0 or math.abs(serverDuration - total) > 0.75
	local minReportDuration = math.max(15, #parts * 3)
	if total < minReportDuration then
		self._log:debug("Duration report deferred (total too short for part count)", {
			trackId = track.id,
			total = total,
			parts = #parts,
		})
		return
	end
	if durationNeedsReport and self._durationReportRE and not self._durationReportedTrackIds[track.id] then
		self._durationReportedTrackIds[track.id] = true
		self._durationReportRE:FireServer({
			trackId = track.id,
			totalDuration = total,
		})
		self._log:debug("Duration reported to server", { trackId = track.id, total = total })
	end
end

-- Skip reason notification messages
local SKIP_REASON_MESSAGES: { [string]: { title: string, message: string } } = {
	vote_skip = { title = "Track Skipped", message = "Track skipped by vote" },
	admin_skip = { title = "Track Skipped", message = "Track skipped by admin" },
	asset_failure = { title = "Track Skipped", message = "Track skipped (audio failed to load)" },
	track_deleted = { title = "Track Removed", message = "Track was removed from library" },
	track_unavailable = { title = "Track Unavailable", message = "Track data is no longer available" },
}

-- Track changed handler

function MusicPlayerController:_onTrackChanged(data: any)
	if type(data) ~= "table" or not data.track then
		-- Track nil = playback berhenti
		self:_stopAllSounds(self._trackFadeOutTime)
		self._currentTrackId = nil
		self._playbackStartKey = nil
		table.clear(self._assetFailureReportedTrackIds)
		self._store:set({
			currentTrack = self._store.NONE,
			startServerTime = 0,
			expectedEndServerTime = 0,
			playbackTiming = self._store.NONE,
			currentEntry = self._store.NONE,
			isPlaying = false,
		})
		self._binder:updateTrackDisplay(nil)
		self._binder:stopProgressTracking()
		return
	end

	local track = data.track
	local timing = self:_resolveServerTiming(data)
	local startServerTime = if timing then timing.startServerTime else (data.startServerTime or 0)
	local skipReason = data.skipReason
	local timingPatch = self:_buildStoreTimingPatch(data)
	local currentEntry = if type(data.currentEntry) == "table" then data.currentEntry else nil

	-- Show notification if track was skipped (not natural transition)
	if type(skipReason) == "string" and skipReason ~= "" then
		local reasonInfo = SKIP_REASON_MESSAGES[skipReason]
		if reasonInfo then
			self:_showNotification({
				title = reasonInfo.title,
				message = reasonInfo.message,
				domain = "music",
				dedupeKey = "music_skip_" .. skipReason,
				duration = 4,
			}, if skipReason == "asset_failure" then "warning" else "info")
		else
			-- Unknown reason, still show it for transparency
			self:_showNotification({
				title = "Track Skipped",
				message = "Track skipped: " .. skipReason,
				domain = "music",
				dedupeKey = "music_skip_unknown",
				duration = 4,
			}, "info")
		end
	end
	local currentState = self._store:get()
	local currentTrack = currentState.currentTrack
	local samePlayback = type(currentTrack) == "table"
		and currentTrack.id == track.id
		and math.abs((currentState.startServerTime or 0) - startServerTime) < 0.001
		and currentState.isPlaying == true
		and self:_hasActivePlayback()

	if samePlayback then
		self._store:set({
			currentTrack = track,
			currentEntry = currentEntry or self._store.NONE,
			isPlaying = true,
			playbackTiming = timingPatch.playbackTiming,
			startServerTime = timingPatch.startServerTime,
			expectedEndServerTime = timingPatch.expectedEndServerTime,
		})
		self._binder:updateTrackDisplay(track)
		self._binder:startProgressTracking()
		self:_primeTrackPartDurations(track)
		self:_schedulePrefetchFromStore(track)
		self:_markPlaybackStart(track.id, startServerTime)
		return
	end

	if self:_shouldSkipDuplicatePlaybackStart(track.id, startServerTime) then
		self._log:debug("Skipping duplicate TrackChanged playback start", {
			trackId = track.id,
			startServerTime = startServerTime,
		})
		self._store:set({
			currentTrack = track,
			currentEntry = currentEntry or self._store.NONE,
			isPlaying = true,
			playbackTiming = timingPatch.playbackTiming,
			startServerTime = timingPatch.startServerTime,
			expectedEndServerTime = timingPatch.expectedEndServerTime,
		})
		self._binder:updateTrackDisplay(track)
		self._binder:startProgressTracking()
		return
	end

	self:_stopAllSounds(self._trackFadeOutTime)
	self:killOrphanMusicSounds()
	self._assetFailureReportedTrackIds[track.id] = nil
	self._currentTrackId = track.id
	self._partDurations = {}
	self._durationReportedTrackIds[track.id] = false
	self:_markPlaybackStart(track.id, startServerTime)

	self._store:set({
		currentTrack = track,
		currentEntry = currentEntry or self._store.NONE,
		isPlaying = true,
		playbackTiming = timingPatch.playbackTiming,
		startServerTime = timingPatch.startServerTime,
		expectedEndServerTime = timingPatch.expectedEndServerTime,
	})

	self._binder:updateTrackDisplay(track)
	self._binder:startProgressTracking()
	self:_primeTrackPartDurations(track)

	-- Apply per-track playback speed sebagai baseline.
	-- Kalau track punya speed sendiri, pakai itu. Kalau tidak, reset ke global config.
	local trackSpeed = tonumber((track :: any).playbackSpeed)
	if trackSpeed and trackSpeed > 0 then
		self:_setBaseSpeed(trackSpeed)
	else
		self:_setBaseSpeed(math.max(0.05, tonumber(self._config.PLAYBACK_SPEED) or 1))
	end

	-- Teruskan startServerTime; _seekToElapsed menghitung elapsed secara fresh.
	self:_seekToElapsed(track, startServerTime)
	self:_schedulePrefetchFromStore(track)
end

function MusicPlayerController:_showNotInZoneNotification()
	local message = tostring(
		self._config.MSG_NOT_IN_ZONE or "You're not in a music zone yet. Step into one to start listening."
	)
	self:_showNotification({
		message = message,
		title = "Music",
		description = message,
		domain = "music",
		dedupeKey = "music_not_in_zone",
	}, "warning")
end

function MusicPlayerController:_onZoneChanged(zoneId: string?, displayName: string?)
	local previousZoneId = self._store:get().activeZoneId
	if previousZoneId == zoneId then
		self._store:set({
			activeZoneDisplayName = if displayName == nil then self._store.NONE else displayName,
		})
		return
	end

	self._log:info("Music zone changed", {
		previousZoneId = tostring(previousZoneId),
		zoneId = tostring(zoneId),
		displayName = tostring(displayName),
	})
	local NONE = self._store.NONE
	self._store:set({
		activeZoneId = if zoneId == nil then NONE else zoneId,
		activeZoneDisplayName = if displayName == nil then NONE else displayName,
		currentTrack = NONE,
		currentEntry = NONE,
		startServerTime = 0,
		expectedEndServerTime = 0,
		playbackTiming = NONE,
		isPlaying = false,
		queue = {},
	})
	self:_stopAllSounds(self._trackFadeOutTime)
	self._currentTrackId = nil
	self._playbackStartKey = nil
	self._partDurations = {}
	self:_invalidateLibraryCache()

	self._binder:updateTrackDisplay(nil)
	self._binder:stopProgressTracking()
	self._binder:renderQueue({})

	if zoneId == nil then
		-- Force-close panel synchronously, regardless of _isPanelOpen state.
		-- Hide icon IMMEDIATELY (not via async subscriber) to guarantee removal.
		-- IMPORTANT: Do NOT call binder:closePanel() here because
		-- dismissCenterPanel sets mainWrapper.Visible=true for its animation,
		-- causing a visible flicker. Instead, force-hide and cleanup directly.
		MobilePanelManager.close("music")
		self._isPanelOpen = false
		self._panelSessionId += 1
		self._store:set({ isOpen = false })
		if self._refs and self._refs.mainWrapper then
			self._refs.mainWrapper.Visible = false
		end
		-- Release binder resources without triggering dismiss animation.
		if self._binder and type(self._binder.releaseListPools) == "function" then
			self._binder:releaseListPools()
		end
		if self._topbarIcon then
			if type(self._topbarIcon.hide) == "function" then
				self._topbarIcon:hide()
			end
		end
		return
	end

	-- Entering a zone: ensure icon is visible (respects DJ mode permission).
	self:_setMusicIconVisible(self:_computeIconVisible())

	if self._isPanelOpen and self._store:get().activeTab == "request" then
		local panelSessionId = self._panelSessionId
		local selectedPlaylistId = self._store:get().selectedPlaylistId
		task.spawn(function()
			self:_loadPlaylists(panelSessionId)
		end)
		task.spawn(function()
			self:_loadTracks(selectedPlaylistId, true, panelSessionId)
		end)
	end
end

function MusicPlayerController:_computeIconVisible()
	local _state = self._store:get()
	-- Topbar icon stays visible regardless of DJ mode. Listeners still need
	-- access (vote skip, view queue, request track when DJ allows). DJ-mode
	-- gating happens at the action level (e.g., request track button hides),
	-- not at the topbar icon level.
	return true
end

function MusicPlayerController:_setMusicIconVisible(visible: boolean)
	local icon = self._topbarIcon
	if not icon then
		return
	end

	if visible then
		if type(icon.show) == "function" then
			icon:show()
		end
	else
		if type(icon.hide) == "function" then
			icon:hide()
		end
	end
end

-- startServerTime: server clock value when this track began (from state).
-- elapsed is recomputed fresh here so that any time already spent in the
-- caller before this function is called is also accounted for.
function MusicPlayerController:_seekToElapsed(track: any, startServerTime: number)
	local parts = track.parts
	if not parts or #parts == 0 then
		return
	end

	local elapsed = workspace:GetServerTimeNow() - startServerTime

	-- Jika durasi sudah diketahui dari sebelumnya, cari part yang tepat.
	-- Kalau belum -> play dari part 1 (fresh seek dilakukan saat sound loaded).
	local accumDur = 0
	local startPart = 1
	local seekOffset = 0

	for i = 1, #parts do
		local dur = self._partDurations[i] or 0
		if dur > 0 and (accumDur + dur) <= elapsed then
			accumDur += dur
			startPart = i + 1
		elseif dur > 0 then
			seekOffset = elapsed - accumDur
			startPart = i
			break
		else
			-- Durasi tidak diketahui; startServerTime + accumDur diteruskan ke
			-- _playFromPart agar onLoaded() bisa hitung posisi yang tepat saat itu.
			startPart = i
			seekOffset = 0
			break
		end
	end

	if startPart > #parts then
		-- Sudah lewat semua parts
		self._log:debug("Elapsed past all parts, waiting for server advance", { trackId = track.id })
		return
	end

	-- Teruskan startServerTime + accumDur agar _playFromPart bisa resync
	-- tepat saat sound selesai loading, bukan saat kita memulai load.
	self:_playFromPart(track, startPart, seekOffset, self._trackFadeInTime, startServerTime, accumDur)
end

-- Volume sync ke semua sounds

function MusicPlayerController:_applyVolume(volume: number)
	local safeVolume = math.clamp(tonumber(volume) or 0, 0, 1)
	for _, sound in pairs(self._activeSounds) do
		if sound and sound.Parent then
			sound.Volume = safeVolume
		end
	end
end

function MusicPlayerController:_bindSettingsVolumeControls()
	if self._settingsVolumeBound then
		return
	end
	self._settingsVolumeBound = true

	local store = self._store
	self:_trackUnsubscriber(store:subscribe("volume", function(vol)
		self:_applyVolume(vol)
	end))

	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return
	end

	local function applySettingsMusicVolume()
		local attrValue = localPlayer:GetAttribute("SettingsMusicVolume")
		if type(attrValue) ~= "number" then
			return
		end
		local safeVolume = math.clamp(attrValue, 0, 1)
		local previousVolume = store:get().volume
		store:set({
			volume = safeVolume,
		})
		if previousVolume == safeVolume then
			self:_applyVolume(safeVolume)
		end
	end

	self:_trackConnection(
		localPlayer:GetAttributeChangedSignal("SettingsMusicVolume"):Connect(applySettingsMusicVolume)
	)
	applySettingsMusicVolume()
end

function MusicPlayerController:_applyDjSoundSettings(sound: Sound)
	sound.PlaybackSpeed = self._playbackSpeed
	destroySoundChild(sound, "MusicPlayerTempPitchShift")
	for _, child in ipairs(sound:GetChildren()) do
		if child:IsA("SoundEffect") and child.Name:match("^MusicPlayerDjEffect_") then
			child:Destroy()
		end
	end

	if self._pitchSemitones ~= 0 then
		local pitchEffect = Instance.new("PitchShiftSoundEffect")
		pitchEffect.Name = "MusicPlayerTempPitchShift"
		pitchEffect.Octave = self._pitchOctave
		pitchEffect.Parent = sound
	end

	for _, effectConfig in ipairs(getDjEffectsConfig(self._config)) do
		local effectId = tostring(effectConfig.id or "")
		local className = tostring(effectConfig.className or "")
		if effectId ~= "" and className ~= "" and self._djEffectEnabledById[effectId] == true then
			local ok, soundEffect = pcall(function()
				return Instance.new(className)
			end)
			if ok and soundEffect and soundEffect:IsA("SoundEffect") then
				soundEffect.Name = "MusicPlayerDjEffect_" .. effectId
				if type(effectConfig.priority) == "number" then
					(soundEffect :: SoundEffect).Priority = effectConfig.priority
				end
				local effectValues = self._djEffectValues[effectId] or {}
				if type(effectConfig.items) == "table" then
					for _, item in ipairs(effectConfig.items) do
						if type(item) == "table" then
							local propertyName = tostring(item.property or "")
							local itemId = tostring(item.id or propertyName)
							local value = effectValues[itemId]
							if propertyName ~= "" and type(value) == "number" then
								pcall(function()
									(soundEffect :: any)[propertyName] = value
								end)
							end
						end
					end
				end
				(soundEffect :: SoundEffect).Parent = sound
			end
		end
	end
end

function MusicPlayerController:_refreshActiveDjSoundSettings()
	for _, sound in pairs(self._activeSounds) do
		self:_applyDjSoundSettings(sound)
	end
end

function MusicPlayerController:_setPlaybackSpeed(speed: number)
	local safeSpeed = math.max(0.05, tonumber(speed) or self._playbackSpeed)
	self._playbackSpeed = safeSpeed
	self:_refreshActiveDjSoundSettings()
	if self._binder and self._binder.setDjPlaybackSpeed then
		-- UI shows the multiplier, not the absolute speed.
		self._binder:setDjPlaybackSpeed(self._djSpeedMultiplier)
	end
end

--- Set the base speed (called on track change). Does NOT change DJ multiplier.
function MusicPlayerController:_setBaseSpeed(base: number)
	self._baseSpeed = math.max(0.05, tonumber(base) or self._baseSpeed)
	self._playbackSpeed = self._baseSpeed * self._djSpeedMultiplier
	self:_refreshActiveDjSoundSettings()
end

--- Set the DJ multiplier (called from DJ slider). Recomputes actual speed.
function MusicPlayerController:_setDjSpeedMultiplier(multiplier: number)
	self._djSpeedMultiplier = math.clamp(tonumber(multiplier) or 1, 0.25, 2)
	self._playbackSpeed = self._baseSpeed * self._djSpeedMultiplier
	self:_refreshActiveDjSoundSettings()
	if self._binder and self._binder.setDjPlaybackSpeed then
		self._binder:setDjPlaybackSpeed(self._djSpeedMultiplier)
	end
end

function MusicPlayerController:_setDjEffectEnabled(effectId: string, enabled: boolean)
	local key = tostring(effectId or "")
	if key == "" or not findDjEffectConfig(self._config, key) then
		return
	end
	self._djEffectEnabledById[key] = enabled == true
	self:_refreshActiveDjSoundSettings()
	if self._binder and self._binder.setDjEffectEnabled then
		self._binder:setDjEffectEnabled(key, self._djEffectEnabledById[key])
	end
end

function MusicPlayerController:_setDjEffectValue(effectId: string, itemId: string, value: number)
	local effectKey = tostring(effectId or "")
	local itemKey = tostring(itemId or "")
	local effectConfig = findDjEffectConfig(self._config, effectKey)
	local itemConfig = findDjEffectItem(effectConfig, itemKey)
	if not itemConfig then
		return
	end

	local minValue = tonumber(itemConfig.min) or -math.huge
	local maxValue = tonumber(itemConfig.max) or math.huge
	local nextValue = math.clamp(tonumber(value) or tonumber(itemConfig.defaultValue) or 0, minValue, maxValue)
	local values = self._djEffectValues[effectKey]
	if not values then
		values = {}
		self._djEffectValues[effectKey] = values
	end
	values[itemKey] = nextValue
	self:_refreshActiveDjSoundSettings()
	if self._binder and self._binder.setDjEffectValue then
		self._binder:setDjEffectValue(effectKey, itemKey, nextValue)
	end
end

function MusicPlayerController:_resetDjEffects()
	local defaultEffectEnabled, defaultEffectValues = buildDefaultDjEffectState(self._config)
	self._djEffectEnabledById = defaultEffectEnabled
	self._djEffectValues = defaultEffectValues
	-- Reset multiplier to 1.0 (base speed unchanged).
	self:_setDjSpeedMultiplier(1.0)
	self:_refreshActiveDjSoundSettings()
	if self._binder then
		for effectId, enabled in pairs(self._djEffectEnabledById) do
			if self._binder.setDjEffectEnabled then
				self._binder:setDjEffectEnabled(effectId, enabled)
			end
		end
		for effectId, values in pairs(self._djEffectValues) do
			for itemId, value in pairs(values) do
				if self._binder.setDjEffectValue then
					self._binder:setDjEffectValue(effectId, itemId, value)
				end
			end
		end
	end
end

function MusicPlayerController:_playDjSoundboardItem(itemId: string)
	local item = findDjConfigItem(self._config, itemId)
	if type(item) ~= "table" then
		return
	end

	local soundId = tostring(item.soundId or self._djSoundboardFallbackSoundId or "")
	if soundId == "" or soundId == "rbxassetid://0" then
		self:_showNotification({
			title = "Sound effect unavailable",
			message = tostring(item.label or itemId) .. " is not configured yet.",
			description = "Add a real audio asset ID to Config.Music.DJ.SOUND_BOARD_ITEMS.",
		}, "warning")
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "MusicPlayerDjSoundboard_" .. tostring(item.id or itemId)
	sound.SoundId = soundId
	sound.Volume = math.max(0, tonumber(item.volume) or 0.9)
	sound.PlaybackSpeed = math.max(0.05, tonumber(item.playbackSpeed) or 1)
	sound.RollOffMaxDistance = 0
	sound.Parent = SoundService
	sound.Ended:Once(function()
		sound:Destroy()
	end)

	SoundService:PlayLocalSound(sound)
end

function MusicPlayerController:_resolveMusicResponse(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.type ~= "music_response" then
		return
	end

	local requestId = payload.requestId
	if type(requestId) ~= "string" then
		return
	end

	local pending = self._pendingMusicRequests[requestId]
	if not pending then
		return
	end
	if pending.responseType ~= payload.responseType then
		return
	end

	pending.response = payload
	pending.event:Fire()
end

function MusicPlayerController:_requestMusicAsync(
	responseType: string,
	remote: RemoteEvent?,
	payload: { [string]: any }?
): any
	if not remote then
		return {
			ok = false,
			error = "remote_unavailable",
			responseType = responseType,
		}
	end

	local requestId = HttpService:GenerateGUID(false)
	local requestPayload = if type(payload) == "table" then table.clone(payload) else {}
	requestPayload.requestId = requestId

	local pending = {
		responseType = responseType,
		event = Instance.new("BindableEvent"),
		response = nil,
	}
	self._pendingMusicRequests[requestId] = pending

	local timeoutSeconds = tonumber(self._config.REMOTE_REQUEST_TIMEOUT) or FALLBACK_REMOTE_REQUEST_TIMEOUT
	task.delay(timeoutSeconds, function()
		local activePending = self._pendingMusicRequests[requestId]
		if activePending ~= pending or pending.response ~= nil then
			return
		end

		pending.response = {
			ok = false,
			error = "timeout",
			requestId = requestId,
			responseType = responseType,
		}
		pending.event:Fire()
	end)

	local fireOk, fireError = pcall(function()
		remote:FireServer(requestPayload)
	end)
	if not fireOk then
		pending.response = {
			ok = false,
			error = tostring(fireError),
			requestId = requestId,
			responseType = responseType,
		}
		pending.event:Fire()
	end

	if pending.response == nil then
		pending.event.Event:Wait()
	end

	if self._pendingMusicRequests[requestId] == pending then
		self._pendingMusicRequests[requestId] = nil
	end

	local response = pending.response
	pending.event:Destroy()

	if type(response) == "table" then
		return response
	end

	return {
		ok = false,
		error = "request_cancelled",
		responseType = responseType,
	}
end

function MusicPlayerController:_applyDjEffectsFromServer(djEffects: any, isDjMode: boolean)
	if not isDjMode or type(djEffects) ~= "table" then
		self:_resetDjEffects()
		return
	end
	if type(djEffects.playbackSpeed) == "number" and djEffects.playbackSpeed > 0 then
		self:_setDjSpeedMultiplier(djEffects.playbackSpeed)
	end
	if type(djEffects.enabled) == "table" then
		for effectId, enabled in pairs(djEffects.enabled) do
			self:_setDjEffectEnabled(effectId, enabled)
		end
	end
	if type(djEffects.values) == "table" then
		for effectId, values in pairs(djEffects.values) do
			if type(values) == "table" then
				for itemId, value in pairs(values) do
					self:_setDjEffectValue(effectId, itemId, value)
				end
			end
		end
	end
end

function MusicPlayerController:_notifyDjModeRequired()
	local message = tostring(
		self._config.MSG_DJ_MODE_REQUIRED or "Enable DJ mode first to adjust sound effects and playback."
	)
	self:_showNotification({
		title = "DJ mode",
		message = message,
		description = message,
		domain = "music",
		dedupeKey = "music_dj_mode_required",
	}, "WARNING")
end

function MusicPlayerController:_requireDjModeForAdjust(): boolean
	if not self._isPanelOpen then
		return false
	end
	if self._store:get().isDjMode == true then
		return true
	end
	local now = os.clock()
	if now - (self._lastDjModeRequiredNotifyAt or 0) >= 1 then
		self._lastDjModeRequiredNotifyAt = now
		self:_notifyDjModeRequired()
	end
	self:_resetDjEffects()
	return false
end

function MusicPlayerController:_applyServerState(data: any, options: { forcePlayback: boolean? }?)
	if type(data) ~= "table" then
		return
	end

	local incomingTrack = data.track
	local timingPatch = self:_buildStoreTimingPatch(data)
	local incomingStartServerTime = timingPatch.startServerTime
	local serverIsPlaying = data.isPlaying == true
	local incomingEntry = if type(data.currentEntry) == "table" then data.currentEntry else nil
	local forcePlayback = options and options.forcePlayback == true
	local previousState = self._store:get()
	local previousQueue = previousState.queue or {}
	local previousBuffer = previousState.prefetchBuffer or {}
	local currentState = previousState
	local currentTrack = currentState.currentTrack
	local samePlayback = not forcePlayback
		and type(incomingTrack) == "table"
		and type(currentTrack) == "table"
		and currentTrack.id == incomingTrack.id
		and math.abs((currentState.startServerTime or 0) - incomingStartServerTime) < 0.001
		and serverIsPlaying
		and currentState.isPlaying == true
		and self:_hasActivePlayback()

	local newQueue = data.queue or {}
	local newBuffer = data.prefetchBuffer or {}
	if #newQueue > #previousQueue
		or (#newQueue > 0 and #previousQueue == 0)
		or (#newBuffer < #previousBuffer and #previousBuffer > 0)
	then
		self:_bumpPrefetchGeneration()
	end

	self._store:set({
		isDjMode = data.isDjMode == true,
		djOwnerUserId = type(data.djOwnerUserId) == "number" and data.djOwnerUserId or nil,
		isManageAllowed = data.isManageAllowed == true,
		queue = newQueue,
		prefetchBuffer = newBuffer,
	})
	self:_setMusicIconVisible(self:_computeIconVisible())
	self._binder:setDjModeEnabled(self._store:get().isDjMode == true)
	self._binder:renderQueue(self._store:get().queue)
	self:_schedulePrefetch(
		if type(incomingTrack) == "table" then incomingTrack else self._store:get().currentTrack,
		newQueue,
		newBuffer
	)

	self:_applyDjEffectsFromServer(data.djEffects, data.isDjMode == true)

	if type(incomingTrack) ~= "table" then
		if serverIsPlaying then
			self._log:warn("StateSync missing track while server reports playing", {
				startServerTime = incomingStartServerTime,
			})
		end
		if currentState.isPlaying or type(currentTrack) == "table" or serverIsPlaying then
			self:_stopAllSounds(self._trackFadeOutTime)
			self._currentTrackId = nil
		end
		self._store:set({
			currentTrack = self._store.NONE,
			currentEntry = self._store.NONE,
			startServerTime = if serverIsPlaying then incomingStartServerTime else 0,
			expectedEndServerTime = if serverIsPlaying then timingPatch.expectedEndServerTime else 0,
			playbackTiming = if serverIsPlaying then timingPatch.playbackTiming else self._store.NONE,
			isPlaying = serverIsPlaying,
		})
		self._binder:updateTrackDisplay(nil)
		self._binder:stopProgressTracking()
		return
	end

	if samePlayback then
		self._store:set({
			currentTrack = incomingTrack,
			currentEntry = incomingEntry or self._store.NONE,
			startServerTime = incomingStartServerTime,
			expectedEndServerTime = timingPatch.expectedEndServerTime,
			playbackTiming = timingPatch.playbackTiming,
			isPlaying = serverIsPlaying,
		})
		self._binder:updateTrackDisplay(incomingTrack)
		if serverIsPlaying then
			self:_markPlaybackStart(incomingTrack.id, incomingStartServerTime)
		end
		return
	end

	if not forcePlayback
		and serverIsPlaying
		and self:_shouldSkipDuplicatePlaybackStart(incomingTrack.id, incomingStartServerTime)
	then
		self._log:debug("Skipping duplicate StateSync playback start", {
			trackId = incomingTrack.id,
			startServerTime = incomingStartServerTime,
		})
		self._store:set({
			currentTrack = incomingTrack,
			currentEntry = incomingEntry or self._store.NONE,
			startServerTime = incomingStartServerTime,
			expectedEndServerTime = timingPatch.expectedEndServerTime,
			playbackTiming = timingPatch.playbackTiming,
			isPlaying = serverIsPlaying,
		})
		self._binder:updateTrackDisplay(incomingTrack)
		return
	end

	self:_onTrackChanged({
		track = incomingTrack,
		currentEntry = incomingEntry,
		timing = timingPatch.playbackTiming,
		startServerTime = incomingStartServerTime,
		expectedEndServerTime = timingPatch.expectedEndServerTime,
	})
end

function MusicPlayerController:_refreshStateFromServer(forcePlayback: boolean?): "ok" | "failed" | "idle"
	if not self._getStateRE then
		return "failed"
	end

	local result = self:_requestMusicAsync("get_state", self._getStateRE, {})
	if type(result) ~= "table" or result.ok ~= true or type(result.data) ~= "table" then
		local err = if type(result) == "table" then result.error else tostring(result)
		self._log:warn("MusicGetState failed", { error = tostring(err) })
		return "failed"
	end

	self:_applyServerState(result.data, { forcePlayback = forcePlayback == true })
	local state = self._store:get()
	if state.isPlaying == true and type(state.currentTrack) == "table" then
		return "ok"
	end
	return "idle"
end

function MusicPlayerController:_hasActivePlayback(): boolean
	for _, sound in pairs(self._activeSounds) do
		if sound and sound.Parent then
			-- Loading counts as active; IsPlaying-only caused false self-heal + double audio.
			if sound.IsPlaying or not sound.IsLoaded then
				return true
			end
		end
	end
	return false
end

function MusicPlayerController:_forceStartPlaybackFromStore(): boolean
	local state = self._store:get()
	local track = state.currentTrack
	if type(track) ~= "table" or state.isPlaying ~= true then
		return false
	end

	local startServerTime = state.startServerTime or 0
	self:_stopAllSounds(0)
	self:killOrphanMusicSounds()
	self._assetFailureReportedTrackIds[track.id] = nil
	self._currentTrackId = track.id
	self._partDurations = {}
	self._durationReportedTrackIds[track.id] = false
	self._playbackStartKey = nil

	self._store:set({
		currentTrack = track,
		startServerTime = startServerTime,
		isPlaying = true,
	})
	self._binder:updateTrackDisplay(track)
	self._binder:startProgressTracking()
	self:_primeTrackPartDurations(track)

	local trackSpeed = tonumber((track :: any).playbackSpeed)
	if trackSpeed and trackSpeed > 0 then
		self:_setBaseSpeed(trackSpeed)
	else
		self:_setBaseSpeed(math.max(0.05, tonumber(self._config.PLAYBACK_SPEED) or 1))
	end

	self:_seekToElapsed(track, startServerTime)
	self:_markPlaybackStart(track.id, startServerTime)
	self:_schedulePrefetchFromStore(track)
	return true
end

-- Hard refresh: pull server state, kill orphans, restart local sounds (bypass samePlayback).
function MusicPlayerController:resyncPlayback(options: { silent: boolean? }?)
	if self._resyncInFlight then
		return
	end

	local silent = type(options) == "table" and options.silent == true
	local cooldown = if silent
		then math.max(30, tonumber((self._config.INCIDENT or {}).SELF_HEAL_COOLDOWN_SECONDS) or 90)
		else 4
	local lastAt = if silent then (self._lastSelfHealAt or 0) else (self._lastResyncAt or 0)
	local now = os.clock()
	if now - lastAt < cooldown then
		if not silent then
			self:_showNotification({
			message = "Wait a moment before loading again.",
			title = "Music",
			domain = "music",
				dedupeKey = "music_resync_cooldown",
			}, "warning")
		end
		return
	end

	self._resyncInFlight = true
	if silent then
		self._lastSelfHealAt = now
	else
		self._lastResyncAt = now
	end

	local orphansRemoved = self:killOrphanMusicSounds()
	local syncResult = self:_refreshStateFromServer(true)
	if syncResult == "failed" then
		self._resyncInFlight = false
		if silent then
			self._log:warn("Music self-heal sync failed")
			return
		end
		self:_showNotification({
			message = "Couldn't sync with the server. Try again in a moment.",
			title = "Music",
			domain = "music",
			dedupeKey = "music_resync_failed",
		}, "warning")
		return
	end

	local started = self:_forceStartPlaybackFromStore()
	if not started then
		self._resyncInFlight = false
		if silent then
			self._log:debug("Music self-heal: nothing playing on server")
			return
		end
		self:_showNotification({
			message = "Nothing is playing on the server right now.",
			title = "Music",
			domain = "music",
			dedupeKey = "music_resync_idle",
		}, "warning")
		return
	end

	self._log:warn(if silent then "Music self-heal resync" else "Music manual resync", {
		trackId = tostring(self._currentTrackId),
		orphansRemoved = orphansRemoved,
	})

	task.delay(0.6, function()
		self._resyncInFlight = false
		if silent then
			return
		end
		if self:_hasActivePlayback() then
			self:_showNotification({
				message = "Track loaded.",
				title = "Music",
				domain = "music",
				dedupeKey = "music_resync_ok",
				duration = 3,
			}, "success")
			return
		end
		self:_showNotification({
			message = tostring(
				self._config.MSG_RELOAD_WAIT
					or "Still loading audio. Check music volume in Settings."
			),
			title = "Music",
			domain = "music",
			dedupeKey = "music_resync_wait",
		}, "warning")
	end)
end

-- Retries initial sync: server may push StateSync before remotes/listeners are ready.
function MusicPlayerController:_bootstrapInitialPlayback()
	local maxAttempts = math.max(3, math.floor(tonumber(self._config.BOOTSTRAP_MAX_ATTEMPTS) or 10))
	local retryBase = math.max(1, tonumber(self._config.BOOTSTRAP_RETRY_BASE_SECONDS) or 4)
	for attempt = 1, maxAttempts do
		local syncResult = self:_refreshStateFromServer(true)
		if syncResult == "ok" then
			self:_forceStartPlaybackFromStore()
		end
		if self:_hasActivePlayback() then
			return
		end

		if attempt < maxAttempts then
			task.wait(retryBase + ((attempt - 1) * retryBase * 0.5))
		end
	end

	self._log:warn("Music bootstrap finished without active playback", {
		isPlaying = self._store:get().isPlaying == true,
		hasTrack = type(self._store:get().currentTrack) == "table",
	})
end

function MusicPlayerController:_toggleDjMode()
	if not self._setDjModeRE then
		return
	end

	local desiredState = not (self._store:get().isDjMode == true)
	task.spawn(function()
		local result = self:_requestMusicAsync("set_dj_mode", self._setDjModeRE, {
			enabled = desiredState,
		})

		if type(result) ~= "table" or result.ok ~= true then
			local err = if type(result) == "table" then result.error else tostring(result)
			self._log:warn("SetDjMode failed", { error = tostring(err), desiredState = desiredState })
			self:_showNotification({
				message = "Failed to update DJ mode",
				title = "Couldn't change DJ mode",
				description = "The server didn't accept that switch just now.",
			}, "error")
			return
		end

		local data = type(result.data) == "table" and result.data or {}
		local isDjMode = data.isDjMode == true
		self._store:set({
			isDjMode = isDjMode,
		})
		self._binder:setDjModeEnabled(isDjMode)
		if not isDjMode then
			self:_resetDjEffects()
		end
		self:_showNotification({
			message = if isDjMode then "DJ mode enabled" else "DJ mode disabled",
			title = if isDjMode then "DJ mode on" else "DJ mode off",
			description = if isDjMode
				then "You're in control now. Regular song requests are paused."
				else "Song requests are open again.",
		}, "success")
	end)
end

function MusicPlayerController:_trackConnection(connection: RBXScriptConnection): RBXScriptConnection
	table.insert(self._connections, connection)
	return connection
end

function MusicPlayerController:_trackUnsubscriber(unsubscribe: () -> ())
	table.insert(self._unsubscribers, unsubscribe)
	return unsubscribe
end

function MusicPlayerController:_isCacheFresh(timestamp: number): boolean
	return timestamp > 0 and (os.clock() - timestamp) < MUSIC_DATA_CACHE_TTL
end

function MusicPlayerController:_cacheKeyForPlaylist(playlistId: string?): string
	if playlistId and playlistId ~= "" then
		return playlistId
	end
	return "__all__"
end

function MusicPlayerController:_invalidateLibraryCache()
	self._playlistsLoadedAt = 0
	self._playlistsCache = {}
	self._tracksCacheByPlaylist = {}
end

function MusicPlayerController:_invalidateTrackCacheForPlaylist(playlistId: string?)
	local cacheKey = self:_cacheKeyForPlaylist(playlistId)
	self._tracksCacheByPlaylist[cacheKey] = nil
end

function MusicPlayerController:_pruneTrackCache()
	local entries = {} :: { { key: string, loadedAt: number } }

	for cacheKey, cacheEntry in pairs(self._tracksCacheByPlaylist) do
		if type(cacheEntry) ~= "table" or not self:_isCacheFresh(cacheEntry.loadedAt) then
			self._tracksCacheByPlaylist[cacheKey] = nil
		else
			table.insert(entries, {
				key = cacheKey,
				loadedAt = cacheEntry.loadedAt,
			})
		end
	end

	if #entries <= MAX_TRACK_CACHE_PLAYLISTS then
		return
	end

	table.sort(entries, function(a, b)
		return a.loadedAt > b.loadedAt
	end)

	for index = MAX_TRACK_CACHE_PLAYLISTS + 1, #entries do
		self._tracksCacheByPlaylist[entries[index].key] = nil
	end
end

function MusicPlayerController:_fetchPlaylists(forceRefresh: boolean?): any
	if not self._getPlaylistsRE then
		return nil
	end
	if not forceRefresh and self:_isCacheFresh(self._playlistsLoadedAt) then
		return self._playlistsCache
	end

	local result = self:_requestMusicAsync("get_playlists", self._getPlaylistsRE, {})
	if type(result) == "table" and result.ok == true and type(result.data) == "table" then
		self._playlistsLoadedAt = os.clock()
		self._playlistsCache = result.data
		return result.data
	end

	local err = if type(result) == "table" then result.error else tostring(result)
	self._log:warn("GetPlaylists failed", { error = tostring(err) })
	return nil
end

function MusicPlayerController:_fetchTracks(playlistId: string?, forceRefresh: boolean?): any
	if not self._getTracksRE then
		return nil
	end

	self:_pruneTrackCache()

	local cacheKey = self:_cacheKeyForPlaylist(playlistId)
	local cachedEntry = self._tracksCacheByPlaylist[cacheKey]
	if not forceRefresh and cachedEntry and self:_isCacheFresh(cachedEntry.loadedAt) then
		return cachedEntry.data
	end

	local result = self:_requestMusicAsync("get_tracks", self._getTracksRE, { playlistId = playlistId })
	if type(result) == "table" and result.ok == true and type(result.data) == "table" then
		self._tracksCacheByPlaylist[cacheKey] = {
			loadedAt = os.clock(),
			data = result.data,
		}
		self:_pruneTrackCache()
		return result.data
	end

	local err = if type(result) == "table" then result.error else tostring(result)
	self._log:warn("GetTracks failed", { error = tostring(err) })
	return nil
end

function MusicPlayerController:_renderRequestSnapshot()
	local store = self._store
	local state = store:get()
	local playlistId = state.selectedPlaylistId
	local playlists = state.playlists or {}
	local tracks = state.tracks or {}

	if self:_isCacheFresh(self._playlistsLoadedAt) then
		playlists = self._playlistsCache
	end

	local cachedTracks = self._tracksCacheByPlaylist[self:_cacheKeyForPlaylist(playlistId)]
	if cachedTracks and self:_isCacheFresh(cachedTracks.loadedAt) then
		tracks = cachedTracks.data
	end

	store:set({
		playlists = playlists,
		tracks = tracks,
	})
	self._binder:renderPlaylists(playlists, state.searchQuery)
	self._binder:renderTracks(tracks, state.searchQuery)
end

function MusicPlayerController:_renderManageSnapshot()
	local store = self._store
	local state = store:get()
	local playlists = state.playlists or {}
	local tracks = {}
	local hasTracksSnapshot = false

	if self:_isCacheFresh(self._playlistsLoadedAt) then
		playlists = self._playlistsCache
	end

	local cachedTracks = self._tracksCacheByPlaylist[self:_cacheKeyForPlaylist(nil)]
	if cachedTracks and self:_isCacheFresh(cachedTracks.loadedAt) then
		tracks = cachedTracks.data
		hasTracksSnapshot = true
	end

	store:set({
		playlists = playlists,
		manageTracks = if hasTracksSnapshot then tracks else state.manageTracks,
	})
	self._binder:renderManagePlaylists(playlists, state.managePlaylistSearchQuery)
	if hasTracksSnapshot then
		self._binder:renderManageTracks(tracks, state.manageTrackSearchQuery)
	end
end

function MusicPlayerController:_isPanelSessionActive(expectedSessionId: number?): boolean
	if not self._isPanelOpen then
		return false
	end
	if expectedSessionId ~= nil and expectedSessionId ~= self._panelSessionId then
		return false
	end
	return true
end

function MusicPlayerController:_findTrackById(trackId: string?): any?
	if type(trackId) ~= "string" or trackId == "" then
		return nil
	end

	local state = self._store:get()
	local currentTrack = state.currentTrack
	if type(currentTrack) == "table" and currentTrack.id == trackId then
		return currentTrack
	end

	for _, queuedTrack in ipairs(state.queue or {}) do
		if type(queuedTrack) == "table" and queuedTrack.id == trackId then
			return queuedTrack
		end
	end

	for key, track in pairs(state.tracks or {}) do
		if (key == trackId or (type(track) == "table" and track.id == trackId)) and type(track) == "table" then
			return track
		end
	end

	for _, cacheEntry in pairs(self._tracksCacheByPlaylist) do
		local cachedTracks = cacheEntry.data or {}
		for key, track in pairs(cachedTracks) do
			if (key == trackId or (type(track) == "table" and track.id == trackId)) and type(track) == "table" then
				return track
			end
		end
	end

	return nil
end

function MusicPlayerController:_resolveTrackName(trackId: string?, fallbackName: string?): string
	local track = self:_findTrackById(trackId)
	if type(track) == "table" then
		local trackName = trimNotificationText(tostring(track.name or ""))
		if trackName ~= "" then
			return trackName
		end
	end

	local fallback = trimNotificationText(tostring(fallbackName or ""))
	if fallback ~= "" then
		return fallback
	end

	return "Track itu"
end

function MusicPlayerController:_resolvePlaylistName(playlistId: string?, fallbackName: string?): string
	local normalizedPlaylistId = if type(playlistId) == "string" and playlistId ~= "" then playlistId else nil
	if normalizedPlaylistId then
		local statePlaylist = (self._store:get().playlists or {})[normalizedPlaylistId]
		if type(statePlaylist) == "table" then
			local playlistName = trimNotificationText(tostring(statePlaylist.name or ""))
			if playlistName ~= "" then
				return playlistName
			end
		end

		local cachedPlaylist = self._playlistsCache[normalizedPlaylistId]
		if type(cachedPlaylist) == "table" then
			local playlistName = trimNotificationText(tostring(cachedPlaylist.name or ""))
			if playlistName ~= "" then
				return playlistName
			end
		end
	end

	local fallback = trimNotificationText(tostring(fallbackName or ""))
	if fallback ~= "" then
		return fallback
	end

	return "playlist itu"
end

-- Init

function MusicPlayerController:_waitMusicRemote(remoteName: string): RemoteEvent?
	local inst = self._remotes:WaitForChild(remoteName, 60)
	if inst and inst:IsA("RemoteEvent") then
		return inst :: RemoteEvent
	end
	self._log:warn("Music remote unavailable", {
		name = remoteName,
		foundClass = if inst then inst.ClassName else "nil",
	})
	return nil
end

function MusicPlayerController:_connectRemoteEvent(remote: RemoteEvent?, handler: (any) -> ())
	if not remote then
		return
	end
	self:_trackConnection(remote.OnClientEvent:Connect(handler))
end

function MusicPlayerController:_scheduleInitRetry()
	if self._initRetryScheduled or self._listenersConnected then
		return
	end
	self._initRetryScheduled = true
	task.delay(2, function()
		self._initRetryScheduled = false
		self:initEngine()
	end)
end

function MusicPlayerController:_collectAuraLoudnessSounds(): { Sound }
	local sounds = {} :: { Sound }
	for _, sound in pairs(self._activeSounds) do
		if sound and sound.Parent and sound:IsA("Sound") then
			table.insert(sounds, sound)
		end
	end
	return sounds
end

function MusicPlayerController:init()
	self:initEngine()
	self:initPanel()
end

function MusicPlayerController:initEngine()
	if self._engineInitialized then
		return
	end

	local config = self._config
	local remotes = self._remotes
	local store = self._store
	local binder = self._binder
	local log = self._log

	-- Do not hide here: MusicTopbarIcon starts hidden, and a hide-before-remotes
	-- race used to mark the icon "shown" without a restore parent (invisible forever).

	-- Resolve remotes
	self._trackChangedRE = self:_waitMusicRemote(config.REMOTE_TRACK_CHANGED)
	self._queueUpdatedRE = self:_waitMusicRemote(config.REMOTE_QUEUE_UPDATED)
	self._stateSyncRE = self:_waitMusicRemote(config.REMOTE_STATE_SYNC)
	self._voteStateRE = self:_waitMusicRemote(config.REMOTE_VOTE_STATE)
	self._durationReportRE = self:_waitMusicRemote(config.REMOTE_DURATION_REPORT)
	self._playbackFinishedRE = self:_waitMusicRemote(config.REMOTE_PLAYBACK_FINISHED)
	self._timingUpdatedRE = self:_waitMusicRemote(config.REMOTE_TIMING_UPDATED)
	self._voteSkipRE = self:_waitMusicRemote(config.REMOTE_VOTE_SKIP)
	self._requestTrackRE = self:_waitMusicRemote(config.REMOTE_REQUEST_TRACK)
	self._adminSkipRE = self:_waitMusicRemote(config.REMOTE_ADMIN_SKIP)
	local reportFailure = remotes:FindFirstChild(config.REMOTE_REPORT_FAILURE)
	self._reportFailureRE = if reportFailure and reportFailure:IsA("RemoteEvent")
		then reportFailure :: RemoteEvent
		else nil
	local playbackIncident = remotes:FindFirstChild(tostring(config.REMOTE_PLAYBACK_INCIDENT or "MusicPlaybackIncident"))
	self._playbackIncidentRE = if playbackIncident and playbackIncident:IsA("RemoteEvent")
		then playbackIncident :: RemoteEvent
		else nil
	self._musicResponseRE = self:_waitMusicRemote(config.REMOTE_RESPONSE)
	self._getStateRE = self:_waitMusicRemote(config.REMOTE_GET_STATE)
	self._getPlaylistsRE = self:_waitMusicRemote(config.REMOTE_GET_PLAYLISTS)
	self._getTracksRE = self:_waitMusicRemote(config.REMOTE_GET_TRACKS)
	self._favoriteTrackRE = self:_waitMusicRemote(config.REMOTE_FAVORITE_TRACK)
	self._setDjModeRE = self:_waitMusicRemote(config.REMOTE_SET_DJ_MODE)
	self._managePlRE = self:_waitMusicRemote(config.REMOTE_MANAGE_PLAYLIST)
	self._manageTrRE = self:_waitMusicRemote(config.REMOTE_MANAGE_TRACK)
	self._resolveRequestAssetRE = self:_waitMusicRemote(config.REMOTE_RESOLVE_REQUEST_ASSET)
	-- Central server mode: no zone changed remote

	if
		not self._trackChangedRE
		or not self._queueUpdatedRE
		or not self._stateSyncRE
		or not self._musicResponseRE
		or not self._getStateRE
	then
		log:warn("MusicPlayerController init deferred — core remotes not ready yet")
		self:_scheduleInitRetry()
		return
	end

	self._listenersConnected = true
	self:_bindSettingsVolumeControls()

	store:set({
		favoriteTrackIds = readFavoriteTrackIdsFromPlayer(config),
	})
	self:_trackConnection(
		Players.LocalPlayer:GetAttributeChangedSignal(getFavoriteAttributeKey(config)):Connect(function()
			store:set({
				favoriteTrackIds = readFavoriteTrackIdsFromPlayer(config),
			})
		end)
	)

	-- RemoteEvent listeners

	self:_connectRemoteEvent(self._musicResponseRE, function(data)
		self:_resolveMusicResponse(data)
	end)

	self:_connectRemoteEvent(self._trackChangedRE, function(data)
		self:_onTrackChanged(data)
	end)

	self:_connectRemoteEvent(self._timingUpdatedRE, function(data)
		self:_onTimingUpdated(data)
	end)

	-- Central server mode: zone changed remote removed, no zone events

	self:_connectRemoteEvent(self._queueUpdatedRE, function(data)
		if type(data) == "table" then
			self:_bumpPrefetchGeneration()
			store:set({
				queue = data.queue or {},
				prefetchBuffer = data.prefetchBuffer or {},
			})
			if self._panelInitialized then
				binder:renderQueue(store:get().queue)
			end
			local currentTrack = store:get().currentTrack
			local state = store:get()
			self:_schedulePrefetch(
				if type(currentTrack) == "table" then currentTrack else nil,
				state.queue,
				state.prefetchBuffer
			)
		end
	end)

	self:_connectRemoteEvent(self._stateSyncRE, function(data)
		self:_applyServerState(data)
	end)

	self:_connectRemoteEvent(self._voteStateRE, function(data)
		if type(data) ~= "table" then
			return
		end

		local action = type(data.action) == "string" and data.action or ""
		if action == "started" then
			if self._isPanelOpen then
				self:_closePanel()
			end
			self:initPanel()
			self._binder:openOrUpdateVoteModal(data)
		elseif action == "updated" then
			self:initPanel()
			self._binder:openOrUpdateVoteModal(data)
		elseif action == "ended" then
			if self._panelInitialized then
				self._binder:closeVoteModal()
			end
		end
	end)

	task.spawn(function()
		self:_bootstrapInitialPlayback()
	end)

	self:_startIncidentWatchdog()
	self._binder:setLoudnessSoundProvider(function()
		return self:_collectAuraLoudnessSounds()
	end)

	self._engineInitialized = true
	log:info("MusicPlayerController engine initialized")
end

function MusicPlayerController:initPanel()
	if self._panelInitialized then
		return
	end
	if not self._engineInitialized then
		self:initEngine()
	end

	local config = self._config
	local store = self._store
	local binder = self._binder
	local log = self._log

	-- Bind UI callbacks

	binder:setOnCloseRequested(function()
		self:_closePanel()
	end)

	binder:setOnTabSelected(function(tab)
		self:_onTabSelected(tab)
	end)

	binder:setOnToggleDjMode(function()
		self:_toggleDjMode()
	end)

	binder:setOnVoteSkip(function(voteType)
		if self._voteSkipRE then
			self._voteSkipRE:FireServer({
				requestId = HttpService:GenerateGUID(false),
				voteType = voteType or "skip",
			})
		end
	end)

	binder:setOnRequestTrack(function(trackId)
		if self._requestTrackRE then
			self._requestTrackRE:FireServer({ trackId = trackId, requestId = HttpService:GenerateGUID(false) })
		end
	end)

	binder:setOnAddFavoriteTrack(function(trackId, shouldRemove)
		if not self._favoriteTrackRE then
			return
		end

		task.spawn(function()
			local action = if shouldRemove then "remove" else "add"
			local result = self:_requestMusicAsync("favorite_track", self._favoriteTrackRE, {
				trackId = trackId,
				action = action,
			})

			if type(result) ~= "table" or result.ok ~= true then
				local err = if type(result) == "table" then result.error else tostring(result)
				local trackName = self:_resolveTrackName(trackId)
				self._log:warn("FavoriteTrack failed", { error = tostring(err), trackId = trackId })
				self:_showNotification({
					message = if shouldRemove
						then "Failed to remove track from favorites"
						else "Failed to add track to favorites",
					title = "Favorites not updated",
					description = string.format('We could not update "%s" in your favorites.', trackName),
				}, "error")
				return
			end

			local data = type(result.data) == "table" and result.data or {}
			local favoriteTrackIds = table.clone(self._store:get().favoriteTrackIds or {})
			if data.removed == true then
				favoriteTrackIds[trackId] = nil
			elseif data.added == true then
				favoriteTrackIds[trackId] = true
			end
			self._store:set({
				favoriteTrackIds = favoriteTrackIds,
			})

			local favoritesPlaylistId = select(1, getSpecialPlaylistIds(self._config))
			self:_invalidateTrackCacheForPlaylist(favoritesPlaylistId)

			if self._store:get().selectedPlaylistId == favoritesPlaylistId then
				self:_loadTracks(favoritesPlaylistId, true)
			end

			local trackName = self:_resolveTrackName(trackId)
			local payload: NotificationPayload = {
				message = "Favorites updated",
				title = "Favorites updated",
				description = string.format('"%s" was just updated.', trackName),
			}
			local notifKind = "success"
			if data.removed == true then
				payload = {
					message = "Track removed from favorites",
					title = "Removed from favorites",
					description = string.format('"%s" left your favorites.', trackName),
				}
			elseif data.notFavorited == true then
				payload = {
					message = "Track is not in your favorites",
					title = "Nothing to remove",
					description = string.format('"%s" was not in your favorites yet.', trackName),
				}
				notifKind = "warning"
			elseif data.added == true then
				payload = {
					message = "Track added to favorites",
					title = "Saved to favorites",
					description = string.format('"%s" is tucked into your favorites now.', trackName),
				}
			elseif data.alreadyFavorited == true then
				payload = {
					message = "Track is already in your favorites",
					title = "Already in favorites",
					description = string.format('"%s" is already sitting in your favorites.', trackName),
				}
				notifKind = "warning"
			end
			self:_showNotification(payload, notifKind)
		end)
	end)

	binder:setOnPlaylistSelected(function(playlistId)
		store:set({ selectedPlaylistId = playlistId })
		binder:renderPlaylists(store:get().playlists, store:get().searchQuery)
		self:_loadTracks(playlistId)
	end)

	binder:setOnSearchChanged(function(query)
		-- Re-render sesuai search
		local state = store:get()
		if state.activeTab == "request" then
			binder:renderTracks(state.tracks, query)
			binder:renderPlaylists(state.playlists, query)
		elseif state.activeTab == "manage" then
			binder:renderManagePlaylists(state.playlists or {}, state.managePlaylistSearchQuery)
			binder:renderManageTracks(state.manageTracks or state.tracks or {}, state.manageTrackSearchQuery)
		end
	end)

	binder:setOnVolumeChanged(function(volume)
		store:set({
			volume = math.clamp(tonumber(volume) or store:get().volume, 0, 1),
		})
	end)

	binder:setOnDjSoundboardTriggered(function(itemId)
		if not self:_requireDjModeForAdjust() then
			return false
		end
		self:_playDjSoundboardItem(itemId)
		return true
	end)

	binder:setOnDjPlaybackSpeedChanged(function(speed)
		if not self:_requireDjModeForAdjust() then
			return false
		end
		self:_setDjSpeedMultiplier(speed)
		-- Sync to server so all listeners hear the same speed.
		local djEffectRemote = self._remotes:FindFirstChild(self._config.REMOTE_DJ_EFFECT)
		if djEffectRemote and djEffectRemote:IsA("RemoteEvent") then
			djEffectRemote:FireServer({
				requestId = HttpService:GenerateGUID(false),
				effectAction = "set_speed",
				effectId = "",
				value = speed,
			})
		end
		return true
	end)

	binder:setOnDjEffectEnabledChanged(function(effectId, enabled)
		if not self:_requireDjModeForAdjust() then
			return false
		end
		self:_setDjEffectEnabled(effectId, enabled)
		-- Sync to server so all listeners hear the same effect toggle.
		local djEffectRemote = self._remotes:FindFirstChild(self._config.REMOTE_DJ_EFFECT)
		if djEffectRemote and djEffectRemote:IsA("RemoteEvent") then
			djEffectRemote:FireServer({
				requestId = HttpService:GenerateGUID(false),
				effectAction = "toggle",
				effectId = effectId,
				value = enabled,
			})
		end
		return true
	end)

	binder:setOnDjEffectValueChanged(function(effectId, itemId, value)
		if not self:_requireDjModeForAdjust() then
			return false
		end
		self:_setDjEffectValue(effectId, itemId, value)
		-- Sync to server so all listeners hear the same effect values.
		local djEffectRemote = self._remotes:FindFirstChild(self._config.REMOTE_DJ_EFFECT)
		if djEffectRemote and djEffectRemote:IsA("RemoteEvent") then
			djEffectRemote:FireServer({
				requestId = HttpService:GenerateGUID(false),
				effectAction = "set_value",
				effectId = effectId,
				itemId = itemId,
				value = value,
			})
		end
		return true
	end)

	binder:setOnDjResetRequested(function()
		if not self:_requireDjModeForAdjust() then
			return false
		end
		self:_resetDjEffects()
		return true
	end)

	binder:setOnManageSubView(function(subView, data)
		store:set({
			manageSubView = subView,
			editingTrack = if subView == "edit_track" and data ~= nil then data else nil,
			editingPlaylist = if subView == "edit_playlist" and data ~= nil then data else nil,
		})
		if subView == "edit_track" then
			binder:populateTrackForm(data)
		elseif subView == "edit_playlist" then
			binder:populatePlaylistForm(data)
		end
		binder:setManageSubView(subView)
	end)

	binder:setOnManagePlaylist(function(action, data)
		self:_handleManagePlaylist(action, data)
	end)

	binder:setOnManageTrack(function(action, data)
		self:_handleManageTrack(action, data)
	end)

	binder:setOnResolveRequestAsset(function(assetIdRaw)
		self:_resolveRequestAsset(assetIdRaw)
	end)

	binder:setOnFormNotify(function(level, title, description)
		self:_showNotification({
			message = title,
			title = title,
			description = description,
			domain = "music",
			dedupeKey = "music_form_notify",
		}, level)
	end)

	-- Volume store subscription lives in initEngine via _bindSettingsVolumeControls.

	-- isManageAllowed -> push ke binder via setManageAllowed
	self:_trackUnsubscriber(store:subscribe("isManageAllowed", function(allowed)
		binder:setManageAllowed(allowed == true)
	end))
	self:_trackUnsubscriber(store:subscribe("isDjMode", function(isDjMode)
		binder:setDjModeEnabled(isDjMode == true)
		if isDjMode ~= true then
			self:_resetDjEffects()
		end
		self:_setMusicIconVisible(self:_computeIconVisible())
	end))
	self:_trackUnsubscriber(store:subscribe("activeZoneId", function(zoneId)
		self:_setMusicIconVisible(self:_computeIconVisible())
	end))
	self:_trackUnsubscriber(store:subscribe("isManageAllowed", function()
		self:_setMusicIconVisible(self:_computeIconVisible())
	end))

	-- Topbar icon — wrapper provides multi-listener API; unsubscribers are tracked
	-- so they fire on controller destroy. Connections inside the icon itself are
	-- automatically disconnected when the icon hides (recreate cycle).
	if self._topbarIcon then
		self:_trackUnsubscriber(self._topbarIcon:onSelected(function()
			-- Central server mode: no zone guard, always open panel.
			-- Open panel IMMEDIATELY with cached state. Refresh from server
			-- in background — do NOT close panel on refresh failure.
			-- Previous behavior: close panel on timeout → caused "panel suka
			-- nutup sendiri" bug when server was slow to respond.
			self:_openPanel()
			task.spawn(function()
				self:_refreshStateFromServer()
			end)
		end))
		self:_trackUnsubscriber(self._topbarIcon:onDeselected(function()
			self:_closePanel()
		end))
	end

	-- Show topbar before bindAll so the icon appears even if a later bind fails.
	-- show() is idempotent and re-asserts TopbarPlus parenting.
	self:_setMusicIconVisible(self:_computeIconVisible())
	-- LoadingScreen / TopbarPlus layout can race the first show; re-assert shortly after.
	task.defer(function()
		if self._destroyed then
			return
		end
		self:_setMusicIconVisible(self:_computeIconVisible())
	end)
	task.delay(0.5, function()
		if self._destroyed then
			return
		end
		self:_setMusicIconVisible(self:_computeIconVisible())
	end)

	-- Bind UI
	binder:bindAll()
	binder:setDjPlaybackSpeed(self._djSpeedMultiplier)
	for effectId, enabled in pairs(self._djEffectEnabledById) do
		if binder.setDjEffectEnabled then
			binder:setDjEffectEnabled(effectId, enabled)
		end
	end
	for effectId, values in pairs(self._djEffectValues) do
		for itemId, value in pairs(values) do
			if binder.setDjEffectValue then
				binder:setDjEffectValue(effectId, itemId, value)
			end
		end
	end

	-- Playback sync is server-push only (trackChanged / stateSync). Client asset
	-- failures are handled locally; server never global-skips on one client report.

	log:info("MusicPlayerController panel initialized")
	self._panelInitialized = true
end

-- Panel open/close

function MusicPlayerController:_openPanel()
	if not self._panelInitialized then
		self:initPanel()
	end
	local binder = self._binder
	local store = self._store
	-- Central server mode: no zone check needed

	self._isPanelOpen = true
	self._panelSessionId += 1
	store:set({ isOpen = true })
	local panelSessionId = self._panelSessionId
	binder:openPanel()

	local hydratedTrack = store:get().currentTrack
	binder:updateTrackDisplay(if type(hydratedTrack) == "table" then hydratedTrack else nil)

	local activeTab = store:get().activeTab

	-- Restore tab terakhir, lalu refresh data yang sesuai dengan tab tersebut.
	binder:switchTab(activeTab)

	if activeTab == "manage" then
		self:_renderManageSnapshot()
		store:set({
			manageSubView = "idle",
			editingTrack = nil,
			editingPlaylist = nil,
		})
		task.spawn(function()
			if not self:_isPanelSessionActive(panelSessionId) then
				return
			end
			binder:setManageSubView("idle")
			self:_loadManageData(false, panelSessionId)
		end)
	elseif activeTab == "request" then
		self:_renderRequestSnapshot()
		local selectedPlaylistId = store:get().selectedPlaylistId
		task.spawn(function()
			self:_loadPlaylists(panelSessionId)
		end)
		task.spawn(function()
			self:_loadTracks(selectedPlaylistId, false, panelSessionId)
		end)
	end
end

function MusicPlayerController:_closePanel()
	local wasOpen = self._isPanelOpen
	self._isPanelOpen = false
	self._panelSessionId += 1
	self._store:set({ isOpen = false })
	if wasOpen then
		self._binder:closePanel()
	end
	if self._topbarIcon and type(self._topbarIcon.deselect) == "function" then
		self._topbarIcon:deselect()
	end
end

-- Tab selected

function MusicPlayerController:_onTabSelected(tab: string)
	local panelSessionId = self._panelSessionId
	if tab ~= "manage" then
		self._binder:setManageSubView("idle")
	end
	if tab == "request" then
		self:_renderRequestSnapshot()
		local selectedPlaylistId = self._store:get().selectedPlaylistId
		task.spawn(function()
			self:_loadPlaylists(panelSessionId)
		end)
		task.spawn(function()
			self:_loadTracks(selectedPlaylistId, false, panelSessionId)
		end)
	elseif tab == "manage" then
		self:_renderManageSnapshot()
		task.spawn(function()
			if not self:_isPanelSessionActive(panelSessionId) then
				return
			end
			-- Ensure manage sections visible (idle state)
			self._binder:setManageSubView("idle")
			self:_loadManageData(false, panelSessionId)
		end)
	end
end

-- Data loading

function MusicPlayerController:_loadPlaylists(expectedSessionId: number?)
	if not self:_isPanelSessionActive(expectedSessionId) then
		return
	end
	local result = self:_fetchPlaylists(false)
	if result and self:_isPanelSessionActive(expectedSessionId) then
		local store = self._store
		store:set({ playlists = result })
		self._binder:renderPlaylists(result, store:get().searchQuery)
		if store:get().activeTab == "request" then
			self._binder:renderTracks(store:get().tracks, store:get().searchQuery)
		end
	end
end

function MusicPlayerController:_loadTracks(playlistId: string?, forceRefresh: boolean?, expectedSessionId: number?)
	if not self:_isPanelSessionActive(expectedSessionId) then
		return
	end
	local result = self:_fetchTracks(playlistId, forceRefresh)
	if result and self:_isPanelSessionActive(expectedSessionId) then
		local store = self._store
		store:set({ tracks = result })
		self._binder:renderTracks(result, store:get().searchQuery)
	end
end

function MusicPlayerController:_loadManageData(forceRefresh: boolean?, expectedSessionId: number?)
	if not self:_isPanelSessionActive(expectedSessionId) then
		return
	end
	local playlists = self:_fetchPlaylists(forceRefresh)
	local tracks = self:_fetchTracks(nil, forceRefresh)

	if not self:_isPanelSessionActive(expectedSessionId) then
		return
	end

	if playlists then
		self._store:set({ playlists = playlists })
		self._binder:renderManagePlaylists(playlists, self._store:get().managePlaylistSearchQuery)
	end
	if tracks then
		self._store:set({ manageTracks = tracks })
		self._binder:renderManageTracks(tracks, self._store:get().manageTrackSearchQuery)
	end
end

function MusicPlayerController:_findManageTrackById(trackId: string): any?
	local tracks = self._store:get().manageTracks
	if type(tracks) ~= "table" or trackId == "" then
		return nil
	end
	return tracks[trackId]
end

function MusicPlayerController:_findManagePlaylistById(playlistId: string): any?
	local playlists = self._store:get().playlists
	if type(playlists) ~= "table" or playlistId == "" then
		return nil
	end
	return playlists[playlistId]
end

function MusicPlayerController:_reopenManageTrackCreate(): ()
	self._store:set({
		manageSubView = "edit_track",
		editingTrack = nil,
	})
	self._binder:populateTrackForm(nil)
	self._binder:setManageSubView("edit_track")
end

function MusicPlayerController:_reopenManageTrackEdit(trackId: string?): ()
	if not trackId then
		return
	end
	local track = self:_findManageTrackById(tostring(trackId))
	if not track then
		return
	end
	self._store:set({
		manageSubView = "edit_track",
		editingTrack = track,
	})
	self._binder:populateTrackForm(track)
	self._binder:setManageSubView("edit_track")
end

function MusicPlayerController:_reopenManagePlaylistCreate(): ()
	self._store:set({
		manageSubView = "edit_playlist",
		editingPlaylist = nil,
	})
	self._binder:populatePlaylistForm(nil)
	self._binder:setManageSubView("edit_playlist")
end

function MusicPlayerController:_reopenManagePlaylistEdit(playlistId: string?): ()
	if not playlistId then
		return
	end
	local playlist = self:_findManagePlaylistById(tostring(playlistId))
	if not playlist then
		return
	end
	self._store:set({
		manageSubView = "edit_playlist",
		editingPlaylist = playlist,
	})
	self._binder:populatePlaylistForm(playlist)
	self._binder:setManageSubView("edit_playlist")
end

-- Manage playlist handler

function MusicPlayerController:_resolveRequestAsset(assetIdRaw: string)
	if not self._resolveRequestAssetRE then
		self:_showNotification({
			message = "Request by ID is unavailable right now.",
			title = "Music unavailable",
			description = "Try again in a moment.",
			domain = "music",
		}, "error")
		return
	end

	task.spawn(function()
		local store = self._store
		if store:get().isLoading then
			return
		end
		store:set({ isLoading = true })

		local result = self:_requestMusicAsync("resolve_request_asset", self._resolveRequestAssetRE, {
			assetId = assetIdRaw,
		})

		store:set({ isLoading = false })

		if type(result) ~= "table" or result.ok ~= true or type(result.data) ~= "table" then
			local err = if type(result) == "table" then tostring(result.error or "request_failed") else "request_failed"
			local message = if err == "rate_limited"
				then "You're resolving IDs too fast. Give it a moment."
				elseif err == "invalid_asset_id" or err == "asset_not_loadable"
				then "That doesn't look like a valid audio asset ID."
				else "Couldn't resolve that asset ID."
			self._log:warn("ResolveRequestAsset failed", { error = err, assetId = assetIdRaw })
			self:_showNotification({
				message = message,
				title = "Request failed",
				description = message,
				domain = "music",
			}, "error")
			return
		end

		local track = result.data
		self:_invalidateLibraryCache()
		local requestHistoryId = tostring(self._config.SPECIAL_PLAYLIST_REQUEST_HISTORY_ID or "__request_history__")
		self:_invalidateTrackCacheForPlaylist(requestHistoryId)

		task.spawn(function()
			self:_loadPlaylists(self._panelSessionId)
		end)
		if store:get().selectedPlaylistId == requestHistoryId then
			task.spawn(function()
				self:_loadTracks(requestHistoryId, true, self._panelSessionId)
			end)
		end

		local playlists = store:get().playlists or {}
		local parentPlaylist = playlists[track.playlistId]
		if not parentPlaylist and track.playlistId == requestHistoryId then
			parentPlaylist = {
				id = requestHistoryId,
				name = tostring(self._config.SPECIAL_PLAYLIST_REQUEST_HISTORY_NAME or "Requested"),
				coverType = "gradient",
				coverValue = 1,
			}
		end
		self._binder:openAddToQueueConfirmation(track, parentPlaylist)
	end)
end

function MusicPlayerController:_handleManagePlaylist(action: string, data: { [string]: any })
	if not self._managePlRE then
		return
	end

	local store = self._store
	store:set({ isLoading = true })

	task.spawn(function()
		local completed, unexpectedErr = xpcall(function()
			local result = self:_requestMusicAsync("manage_playlist", self._managePlRE, {
				action = action,
				data = data,
			})

			if type(result) == "table" and result.ok then
				self._log:info("Playlist " .. action .. " success")
				self:_invalidateLibraryCache()
				local resultData = type(result.data) == "table" and result.data or nil
				local playlistId = if resultData then resultData.id else data.id
				local playlistName =
					self:_resolvePlaylistName(playlistId, if resultData then resultData.name else data.name)
				if action == "delete" and store:get().selectedPlaylistId == data.id then
					store:set({
						selectedPlaylistId = nil,
						tracks = {},
					})
					self._binder:renderTracks({}, store:get().searchQuery)
				end

				if action == "delete" then
					self:_showNotification({
						message = "Playlist deleted successfully",
						title = "Playlist removed",
						description = string.format('"%s" is out of your library.', playlistName),
					}, "success")
				elseif action == "update" then
					self:_showNotification({
						message = "Playlist saved successfully",
						title = "Playlist updated",
						description = string.format('"%s" is live with its latest changes.', playlistName),
					}, "success")
				else
					self:_showNotification({
						message = "Playlist saved successfully",
						title = "Playlist created",
						description = string.format('"%s" is ready for your next picks.', playlistName),
					}, "success")
				end
				store:set({
					editingPlaylist = nil,
					manageSubView = "idle",
				})
				self._binder:setManageSubView("idle")
				-- Refresh playlist list
				self:_loadPlaylists()
				self:_loadManageData(true)
			else
				local err = if type(result) == "table" then result.error else tostring(result)
				local playlistName = self:_resolvePlaylistName(data.id, data.name)
				self._log:warn("Playlist " .. action .. " failed", { error = err })
				self:_showNotification({
					message = "Failed to save playlist: " .. err,
					title = "Playlist save failed",
					description = string.format('"%s" could not be saved just yet.', playlistName),
				}, "error")
				if action == "update" then
					self:_reopenManagePlaylistEdit(data.id)
				elseif action == "create" then
					self:_reopenManagePlaylistCreate()
				end
			end
		end, debug.traceback)

		store:set({ isLoading = false })
		if not completed then
			local playlistName = self:_resolvePlaylistName(data.id, data.name)
			self._log:error("Playlist " .. action .. " handler crashed", { error = tostring(unexpectedErr) })
			self:_showNotification({
				message = "Failed to save playlist due to an unexpected client error",
				title = "Playlist save failed",
				description = string.format('"%s" ran into an unexpected client-side error.', playlistName),
			}, "error")
			if action == "update" then
				self:_reopenManagePlaylistEdit(data.id)
			elseif action == "create" then
				self:_reopenManagePlaylistCreate()
			end
		end
	end)
end

-- Manage track handler

function MusicPlayerController:_handleManageTrack(action: string, data: { [string]: any })
	if not self._manageTrRE then
		return
	end

	local store = self._store
	store:set({ isLoading = true })

	task.spawn(function()
		local completed, unexpectedErr = xpcall(function()
			local result = self:_requestMusicAsync("manage_track", self._manageTrRE, {
				action = action,
				data = data,
			})

			if type(result) == "table" and result.ok then
				self._log:info("Track " .. action .. " success")
				self:_invalidateLibraryCache()
				local resultData = type(result.data) == "table" and result.data or nil
				local trackName = self:_resolveTrackName(
					if resultData then resultData.id else data.id,
					if resultData then resultData.name else data.name
				)
				if action == "delete" then
					self:_showNotification({
						message = "Track deleted successfully",
						title = "Track removed",
						description = string.format('"%s" is out of the library.', trackName),
					}, "success")
				elseif action == "update" then
					self:_showNotification({
						message = "Track saved successfully",
						title = "Track updated",
						description = string.format('"%s" is live with its latest changes.', trackName),
					}, "success")
				else
					self:_showNotification({
						message = "Track saved successfully",
						title = "Track saved",
						description = string.format('"%s" is ready to be queued.', trackName),
					}, "success")
				end
				store:set({
					editingTrack = nil,
					manageSubView = "idle",
					selectedTrackPlaylistId = data.playlistId or store:get().selectedTrackPlaylistId,
				})
				self._binder:setManageSubView("idle")
				-- Refresh track list
				self:_loadManageData(true)
				local selectedPlaylistId = store:get().selectedPlaylistId
				if selectedPlaylistId then
					self:_loadTracks(selectedPlaylistId, true)
				end
			else
				local err = if type(result) == "table" then result.error else tostring(result)
				local trackName = self:_resolveTrackName(data.id, data.name)
				self._log:warn("Track " .. action .. " failed", { error = err })
				self:_showNotification({
					message = (if action == "delete" then "Failed to delete track: " else "Failed to save track: ")
						.. err,
					title = if action == "delete" then "Track delete failed" else "Track save failed",
					description = string.format('"%s" could not be processed just yet.', trackName),
				}, "error")
				if action == "update" then
					self:_reopenManageTrackEdit(data.id)
				elseif action == "upload" then
					self:_reopenManageTrackCreate()
				end
			end
		end, debug.traceback)

		store:set({ isLoading = false })
		if not completed then
			local trackName = self:_resolveTrackName(data.id, data.name)
			self._log:error("Track " .. action .. " handler crashed", { error = tostring(unexpectedErr) })
			self:_showNotification({
				message = if action == "delete"
					then "Failed to delete track due to an unexpected client error"
					else "Failed to save track due to an unexpected client error",
				title = if action == "delete" then "Track delete failed" else "Track save failed",
				description = string.format('"%s" ran into an unexpected client-side error.', trackName),
			}, "error")
			if action == "update" then
				self:_reopenManageTrackEdit(data.id)
			elseif action == "upload" then
				self:_reopenManageTrackCreate()
			end
		end
	end)
end

-- Notification helper

function MusicPlayerController:_showNotification(messageOrPayload: string | NotificationPayload, _type: string?)
	local payload = if type(messageOrPayload) == "table"
		then messageOrPayload
		else { message = messageOrPayload } :: NotificationPayload
	local normalizedType = string.upper(tostring(_type or "INFO"))
	local notifType: NotifType = "INFO"
	if normalizedType == "ERROR" then
		notifType = "ERROR"
	elseif normalizedType == "SUCCESS" then
		notifType = "SUCCESS"
	elseif normalizedType == "WARNING" then
		notifType = "WARNING"
	elseif normalizedType == "SYSTEM" then
		notifType = "SYSTEM"
	end

	local fallbackMessage = payload.message
	if type(fallbackMessage) ~= "string" or fallbackMessage == "" then
		if type(payload.description) == "string" and payload.description ~= "" then
			fallbackMessage = payload.description
		elseif type(payload.title) == "string" and payload.title ~= "" then
			fallbackMessage = payload.title
		else
			fallbackMessage = "Music update"
		end
	end

	NotifService.show({
		message = fallbackMessage,
		notifType = notifType,
		title = payload.title,
		description = payload.description,
		domain = payload.domain or "music",
		dedupeKey = payload.dedupeKey,
		duration = payload.duration,
		iconImage = payload.iconImage,
	})
end

function MusicPlayerController:destroy()
	self._destroyed = true
	if self._incidentThread then
		task.cancel(self._incidentThread)
		self._incidentThread = nil
	end
	self:_stopAllSounds()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}

	for _, unsubscribe in ipairs(self._unsubscribers) do
		unsubscribe()
	end
	self._unsubscribers = {}

	for requestId, pending in pairs(self._pendingMusicRequests) do
		self._pendingMusicRequests[requestId] = nil
		pending.response = {
			ok = false,
			error = "controller_destroyed",
			requestId = requestId,
			responseType = pending.responseType,
		}
		pending.event:Fire()
	end

	if self._binder and type(self._binder.destroy) == "function" then
		self._binder:destroy()
	end
	if self._assetCache and type(self._assetCache.destroy) == "function" then
		self._assetCache:destroy()
		self._assetCache = nil
	end
end

local ORPHAN_SOUND_NAME_BLOCKLIST = {
	UIHoverTemplate = true,
	UIClickTemplate = true,
}

local PREFETCH_HOLDER_FOLDER_NAME = "MusicAssetCacheHolders"
local PREFETCH_HOLDER_SOUND_NAME = "MusicPrefetchHolder"

local function isPrefetchHolderSound(sound: Sound): boolean
	if sound.Name == PREFETCH_HOLDER_SOUND_NAME then
		return true
	end
	local parent = sound.Parent
	return parent ~= nil and parent.Name == PREFETCH_HOLDER_FOLDER_NAME
end

-- Silent load-only instances (prefetch holders, duration probes) must not be orphan-killed.
local function isSilentNonPlayingMusicSound(sound: Sound): boolean
	if sound.IsPlaying then
		return false
	end
	return sound.Volume <= 0
end

function MusicPlayerController:_describeSound(sound: Sound): string
	local parentName = if sound.Parent then sound.Parent:GetFullName() else "nil"
	return string.format(
		"%s | playing=%s loaded=%s vol=%.2f pos=%.2fs id=%s parent=%s",
		sound.Name,
		tostring(sound.IsPlaying),
		tostring(sound.IsLoaded),
		sound.Volume,
		sound.TimePosition,
		sound.SoundId,
		parentName
	)
end

function MusicPlayerController:_collectTrackedSoundSet(): { [Sound]: boolean }
	local tracked = {} :: { [Sound]: boolean }
	for _, sound in pairs(self._activeSounds) do
		if sound and sound.Parent then
			tracked[sound] = true
		end
	end
	for sound in pairs(self._fadingOutSounds) do
		if sound.Parent then
			tracked[sound] = true
		end
	end
	return tracked
end

function MusicPlayerController:killOrphanMusicSounds(): number
	local tracked = self:_collectTrackedSoundSet()
	local removed = 0
	for _, sound in ipairs(SoundService:GetDescendants()) do
		if not sound:IsA("Sound") then
			continue
		end
		if ORPHAN_SOUND_NAME_BLOCKLIST[sound.Name] then
			continue
		end
		if sound.Name:match("^MusicPlayerDjSoundboard_") then
			continue
		end
		if tracked[sound] then
			continue
		end
		if isPrefetchHolderSound(sound) then
			continue
		end
		if isSilentNonPlayingMusicSound(sound) then
			continue
		end
		if sound.IsPlaying or sound.IsLoaded then
			self:_destroySound(sound)
			removed += 1
		end
	end
	return removed
end

function MusicPlayerController:_getPlatformLabel(): string
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Mobile"
	end
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Gamepad"
	end
	return "Desktop"
end

function MusicPlayerController:_reportPlaybackIncident(code: string, detail: string?)
	local incidentConfig = self._config.INCIDENT
	if type(incidentConfig) ~= "table" or incidentConfig.ENABLED ~= true then
		return
	end
	if not self._playbackIncidentRE then
		return
	end

	local state = self._store:get()
	local track = state.currentTrack
	local trackId = if type(track) == "table" and type(track.id) == "string" then track.id else nil

	local payload = {
		requestId = HttpService:GenerateGUID(false),
		code = code,
		platform = self:_getPlatformLabel(),
		trackId = trackId,
		storePlaying = state.isPlaying == true,
		hasActiveSound = self:_hasActivePlayback(),
		volume = tonumber(state.volume),
		elapsedSinceJoin = math.max(0, os.clock() - (self._incidentJoinAt or os.clock())),
		detail = detail,
	}

	local fireOk, fireErr = pcall(function()
		self._playbackIncidentRE:FireServer(payload)
	end)
	if not fireOk then
		self._log:debug("PlaybackIncident fire failed", { error = tostring(fireErr), code = code })
	end
end

function MusicPlayerController:_startIncidentWatchdog()
	local incidentConfig = self._config.INCIDENT
	if type(incidentConfig) ~= "table" or incidentConfig.ENABLED ~= true then
		return
	end

	self._incidentJoinAt = os.clock()
	local interval = math.max(4, tonumber(incidentConfig.CLIENT_WATCHDOG_INTERVAL) or 8)
	local noAudioGrace = math.max(10, tonumber(incidentConfig.CLIENT_NO_AUDIO_GRACE) or 35)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		noAudioGrace = math.max(
			noAudioGrace,
			tonumber(incidentConfig.INCIDENT_MOBILE_NO_AUDIO_GRACE) or 55
		)
	end
	local joinGrace = math.max(20, tonumber(incidentConfig.INCIDENT_JOIN_GRACE_SECONDS) or 45)
	local selfHealEnabled = incidentConfig.INCIDENT_SELF_HEAL_ENABLED ~= false
	local selfHealCooldown = math.max(30, tonumber(incidentConfig.SELF_HEAL_COOLDOWN_SECONDS) or 90)
	local reportedCodes = {} :: { [string]: boolean }
	local noAudioSince: number? = nil
	local desyncSince: number? = nil

	local function trySelfHeal(code: string): boolean
		if not selfHealEnabled or self._resyncInFlight then
			return false
		end
		local now = os.clock()
		if now - (self._lastSelfHealAt or 0) < selfHealCooldown then
			return false
		end
		self._log:warn("Music incident self-heal", { code = code })
		task.spawn(function()
			self:resyncPlayback({ silent = true })
		end)
		return true
	end

	self._incidentThread = task.spawn(function()
		while not self._destroyed do
			task.wait(interval)

			if self._destroyed then
				break
			end
			if os.clock() - (self._incidentJoinAt or os.clock()) < joinGrace then
				continue
			end

			local state = self._store:get()
			local hasTrack = type(state.currentTrack) == "table"
			local isPlaying = state.isPlaying == true
			local hasSound = self:_hasActivePlayback()
			local volume = tonumber(state.volume) or 0

			if isPlaying and not hasTrack then
				if not desyncSince then
					desyncSince = os.clock()
				elseif (os.clock() - desyncSince) >= noAudioGrace then
					if trySelfHeal("MUSIC_DESYNC") then
						desyncSince = os.clock()
						reportedCodes.MUSIC_DESYNC = nil
					elseif not reportedCodes.MUSIC_DESYNC then
						reportedCodes.MUSIC_DESYNC = true
						self:_reportPlaybackIncident("MUSIC_DESYNC", "isPlaying=true but store.currentTrack=nil")
					end
				end
			else
				desyncSince = nil
				reportedCodes.MUSIC_DESYNC = nil
			end

			if isPlaying and hasTrack and not hasSound then
				if not noAudioSince then
					noAudioSince = os.clock()
				elseif (os.clock() - noAudioSince) >= noAudioGrace then
					if trySelfHeal("MUSIC_NO_AUDIO") then
						noAudioSince = os.clock()
						reportedCodes.MUSIC_NO_AUDIO = nil
					elseif not reportedCodes.MUSIC_NO_AUDIO then
						reportedCodes.MUSIC_NO_AUDIO = true
						self:_reportPlaybackIncident("MUSIC_NO_AUDIO", "track in store but no active Sound")
					end
				end
			else
				noAudioSince = nil
				reportedCodes.MUSIC_NO_AUDIO = nil
			end

			if isPlaying and hasTrack and volume <= 0.01 and not reportedCodes.MUSIC_MUTED then
				reportedCodes.MUSIC_MUTED = true
				self:_reportPlaybackIncident("MUSIC_MUTED", "Settings/store volume at 0")
			elseif volume > 0.01 then
				reportedCodes.MUSIC_MUTED = nil
			end
		end
	end)
end

return MusicPlayerController
