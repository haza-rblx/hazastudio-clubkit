--!strict
-- PATH: ServerScriptService/Server/Services/MusicSession.lua
-- Per-zone playback session. Owns queue, state, and vote logic for one zone.
-- Shared resources (repo, rate limiters, rank) are injected by MusicService manager.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MusicDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.MusicDomain)
local MusicAssetValidator = require(script.Parent.MusicAssetValidator)

type TrackInfo = MusicDomain.TrackInfo
type QueueEntry = MusicDomain.QueueEntry
type PlaybackTiming = MusicDomain.PlaybackTiming

local function createMusicSession(deps: {
	zoneId: string,
	repo: any,
	logger: any,
	config: any,
	getMembers: () -> { Player },
	isManageAllowed: (player: Player) -> boolean,
})
	local zoneId = deps.zoneId
	local repo = deps.repo
	local log = deps.logger
	local config = deps.config
	local getMembers = deps.getMembers
	local isManageAllowed = deps.isManageAllowed

	local session = {}

	local SYSTEM_ASSIGNER_LABEL = tostring(config.SYSTEM_ASSIGNER_LABEL or "Assigned by System")
	local IDLE_SYSTEM_FALLBACK_ENABLED = config.IDLE_SYSTEM_FALLBACK_ENABLED ~= false
	local unknownDurationFallbackSeconds = math.max(
		60,
		tonumber(config.AUTO_ADVANCE_UNKNOWN_DURATION_SECONDS) or 180
	)
	local loadGraceSeconds = math.max(0, tonumber(config.ASSET_LOAD_GRACE_SECONDS) or 90)
	local requestTrackMaxPerUserQueue = math.max(1, tonumber(config.REQUEST_TRACK_MAX_PER_USER_QUEUE) or 3)
	local finishAdvanceToleranceSeconds = math.max(
		2,
		tonumber(config.PLAYBACK_FINISH_ADVANCE_TOLERANCE_SECONDS) or 15
	)
	local finishQuorumRatio = math.clamp(tonumber(config.PLAYBACK_FINISH_QUORUM_RATIO) or 0.5, 0.25, 1)
	local globalPlaybackSpeed = math.max(0.05, tonumber(config.PLAYBACK_SPEED) or 1)
	local randomGenerator = Random.new()

	local state = {
		currentTrackId = nil :: string?,
		currentEntry = nil :: QueueEntry?,
		startServerTime = 0,
		expectedEndServerTime = 0,
		effectivePlaybackSpeed = globalPlaybackSpeed,
		isPlaying = false,
		isDjMode = false,
		djOwnerUserId = nil :: number?,
		queue = {} :: { QueueEntry },
		voteSkipVoters = {} :: { [number]: true },
	}

	local djEffectState: { enabled: { [string]: boolean }, values: { [string]: { [string]: number } }, playbackSpeed: number } = {
		enabled = {},
		values = {},
		playbackSpeed = 1.0,
	}

	local _onTrackChanged: ((any, { Player }?, string?) -> ())? = nil
	local _onTimingUpdated: ((any, { Player }?) -> ())? = nil
	local _onQueueUpdated: (({ queue: { any }, prefetchBuffer: { any } }) -> ())? = nil
	local _onStateSync: ((Player, any) -> ())? = nil
	local _onVoteState: ((Player?, any) -> ())? = nil

	local pendingSkipReason: string? = nil
	local advanceScheduleToken = 0
	local voteSession = nil :: any
	local voteSessionCounter = 0
	local lastSystemTrackId = nil :: string?
	local autoBuffer: { QueueEntry } = {}
	local playbackFinishVotes = {} :: { [number]: true }

	local function newEntryId(): string
		return HttpService:GenerateGUID(false)
	end

	local function isDjOwner(player: Player?): boolean
		return state.isDjMode == true
			and player ~= nil
			and state.djOwnerUserId ~= nil
			and state.djOwnerUserId == player.UserId
	end

	local function canControlDuringDjMode(player: Player?): boolean
		if player == nil then
			return false
		end
		return isDjOwner(player) or isManageAllowed(player)
	end

	local function getTrackById(trackId: string?): TrackInfo?
		if not trackId or trackId == "" then
			return nil
		end
		return repo:getTrack(trackId)
	end

	local function getEffectivePlaybackSpeed(track: TrackInfo?): number
		return MusicDomain.computeEffectivePlaybackSpeed(track, globalPlaybackSpeed, djEffectState.playbackSpeed)
	end

	local function buildTiming(): PlaybackTiming
		return MusicDomain.buildPlaybackTiming(
			state.startServerTime,
			state.expectedEndServerTime,
			state.effectivePlaybackSpeed
		)
	end

	local function clearPlaybackFinishVotes()
		table.clear(playbackFinishVotes)
	end

	local function resetTiming()
		state.startServerTime = 0
		state.expectedEndServerTime = 0
		state.effectivePlaybackSpeed = globalPlaybackSpeed
	end

	local function isSystemEntry(entry: QueueEntry?): boolean
		return entry ~= nil and entry.source == "system"
	end

	local function countQueuedTracksForUser(userId: number): number
		local total = 0
		for _, entry in ipairs(state.queue) do
			if entry.source == "user" and entry.requesterUserId == userId then
				total += 1
			end
		end
		return total
	end

	local function enrichTrack(track: TrackInfo?, entry: QueueEntry?): any?
		if not track then
			return nil
		end
		local enriched = table.clone(track :: any) :: any
		local playlist = repo:getPlaylist(track.playlistId)
		if playlist then
			enriched.playlist = playlist
		end
		local activeEntry = entry or state.currentEntry
		if activeEntry and activeEntry.trackId == track.id then
			return MusicDomain.applyEntryToTrack(enriched, activeEntry)
		end
		return enriched
	end

	local function buildQueueTracks(entries: { QueueEntry }): { any }
		local queueTracks: { any } = {}
		for _, entry in ipairs(entries) do
			local track = getTrackById(entry.trackId)
			if track then
				table.insert(queueTracks, enrichTrack(track, entry))
			end
		end
		return queueTracks
	end

	local function isTrackPlayable(track: TrackInfo): boolean
		return type(track.parts) == "table" and #track.parts >= 1
	end

	local function collectExcludedTrackIds(previousTrackId: string?): { [string]: true }
		local excludedLookup = {} :: { [string]: true }
		if previousTrackId and previousTrackId ~= "" then
			excludedLookup[previousTrackId] = true
		end
		for _, entry in ipairs(state.queue) do
			excludedLookup[entry.trackId] = true
		end
		for _, entry in ipairs(autoBuffer) do
			excludedLookup[entry.trackId] = true
		end
		return excludedLookup
	end

	local function chooseSystemTrack(previousTrackId: string?): string?
		if not IDLE_SYSTEM_FALLBACK_ENABLED or state.isDjMode then
			return nil
		end
		local result = repo:getTracks()
		if not result.ok then
			log:warn("Gagal ambil track untuk idle fallback", { error = result.error, zoneId = zoneId })
			return nil
		end
		local preferredCandidates: { string } = {}
		local relaxedCandidates: { string } = {}
		local emergencyCandidates: { string } = {}
		local excludedLookup = collectExcludedTrackIds(previousTrackId)
		for trackId, track in pairs(result.value) do
			if isTrackPlayable(track) then
				if not excludedLookup[trackId] and trackId ~= lastSystemTrackId then
					table.insert(preferredCandidates, trackId)
				elseif not excludedLookup[trackId] then
					table.insert(relaxedCandidates, trackId)
				elseif trackId ~= previousTrackId then
					table.insert(emergencyCandidates, trackId)
				end
			end
		end
		local candidates = if #preferredCandidates > 0
			then preferredCandidates
			elseif #relaxedCandidates > 0 then relaxedCandidates
			else emergencyCandidates
		if #candidates == 0 then
			return nil
		end
		return candidates[randomGenerator:NextInteger(1, #candidates)]
	end

	local function enqueueSystemTrack(previousTrackId: string?): boolean
		local trackId = chooseSystemTrack(previousTrackId)
		if not trackId then
			return false
		end
		table.insert(autoBuffer, MusicDomain.newSystemQueueEntry(trackId, newEntryId(), SYSTEM_ASSIGNER_LABEL))
		lastSystemTrackId = trackId
		log:debug("System assigned idle track", { trackId = trackId, zoneId = zoneId })
		return true
	end

	local function getAutoQueueDepth(): number
		return math.max(1, math.floor(tonumber(config.AUTO_QUEUE_DEPTH) or 3))
	end

	local function getAutoBufferRefillMaxUserQueue(): number
		return math.max(0, math.floor(tonumber(config.AUTO_BUFFER_REFILL_MAX_USER_QUEUE) or 1))
	end

	local function shouldMaintainAutoBuffer(): boolean
		if state.isDjMode or not IDLE_SYSTEM_FALLBACK_ENABLED then
			return false
		end
		return #state.queue <= getAutoBufferRefillMaxUserQueue()
	end

	local function clearAutoBuffer()
		table.clear(autoBuffer)
	end

	local function sanitizeQueue()
		local nextUserQueue: { QueueEntry } = {}
		for _, entry in ipairs(state.queue) do
			if entry.source == "system" then
				table.insert(autoBuffer, entry)
			else
				table.insert(nextUserQueue, entry)
			end
		end
		state.queue = nextUserQueue
	end

	local function buildQueueUpdatePayload(): { queue: { any }, prefetchBuffer: { any } }
		return {
			queue = buildQueueTracks(state.queue),
			prefetchBuffer = buildQueueTracks(autoBuffer),
		}
	end

	local function ensureAutoBufferDepth(minDepth: number?)
		if not shouldMaintainAutoBuffer() then
			return
		end
		local targetDepth = math.max(1, math.floor(tonumber(minDepth) or getAutoQueueDepth()))
		local safety = 0
		while #autoBuffer < targetDepth and safety < targetDepth + 4 do
			safety += 1
			local pickAfter = state.currentTrackId or lastSystemTrackId
			if not enqueueSystemTrack(pickAfter) then
				break
			end
		end
	end

	sanitizeQueue()

	local function cancelAutoAdvance()
		advanceScheduleToken += 1
	end

	local function scheduleAdvanceToExpectedEnd(trackId: string)
		cancelAutoAdvance()
		local token = advanceScheduleToken
		local now = workspace:GetServerTimeNow()
		local remaining = state.expectedEndServerTime - now
		if remaining <= 0 then
			task.defer(function()
				if token ~= advanceScheduleToken then
					return
				end
				if state.currentTrackId == trackId and state.isPlaying then
					session:advanceQueue()
				end
			end)
			return
		end
		task.delay(remaining, function()
			if token ~= advanceScheduleToken then
				return
			end
			if state.currentTrackId == trackId and state.isPlaying then
				log:debug("Auto-advance at expected end", { trackId = trackId, zoneId = zoneId })
				session:advanceQueue()
			end
		end)
	end

	local function setExpectedEndFromWallDuration(track: TrackInfo?, wallDuration: number, applyLoadGrace: boolean?)
		local now = workspace:GetServerTimeNow()
		if state.startServerTime <= 0 then
			state.startServerTime = now
		end
		state.effectivePlaybackSpeed = getEffectivePlaybackSpeed(track)
		local grace = if applyLoadGrace == true then loadGraceSeconds else 0
		local safeWall = math.max(1, wallDuration)
		state.expectedEndServerTime = state.startServerTime + grace + safeWall
		scheduleAdvanceToExpectedEnd(state.currentTrackId or "")
	end

	local function broadcastTimingUpdated(members: { Player }?)
		if not _onTimingUpdated then
			return
		end
		local trackId = state.currentTrackId
		if not trackId or trackId == "" then
			return
		end
		_onTimingUpdated({
			trackId = trackId,
			timing = buildTiming(),
		}, members)
	end

	local function applyTimingUpdate(newExpectedEndServerTime: number, trackId: string?)
		local activeTrackId = trackId or state.currentTrackId
		if not activeTrackId or activeTrackId == "" then
			return false
		end
		local minEnd = state.startServerTime + 1
		state.expectedEndServerTime = math.max(minEnd, newExpectedEndServerTime)
		scheduleAdvanceToExpectedEnd(activeTrackId)
		broadcastTimingUpdated(nil)
		return true
	end

	local function rescheduleTimingForSpeedChange()
		if not state.isPlaying or state.startServerTime <= 0 then
			return
		end
		local now = workspace:GetServerTimeNow()
		local oldSpeed = state.effectivePlaybackSpeed
		local track = getTrackById(state.currentTrackId)
		local newSpeed = getEffectivePlaybackSpeed(track)
		if math.abs(oldSpeed - newSpeed) < 0.001 then
			state.effectivePlaybackSpeed = newSpeed
			return
		end
		local remainingWall = math.max(0, state.expectedEndServerTime - now)
		local adjustedRemaining = remainingWall * (oldSpeed / newSpeed)
		state.effectivePlaybackSpeed = newSpeed
		state.expectedEndServerTime = now + adjustedRemaining
		scheduleAdvanceToExpectedEnd(state.currentTrackId or "")
		broadcastTimingUpdated(nil)
	end

	local function resolveZombieCurrentTrack(source: string): boolean
		local trackId = state.currentTrackId
		if not trackId or trackId == "" then
			return true
		end
		if getTrackById(trackId) then
			return true
		end
		log:warn("Unresolvable current track, advancing", {
			trackId = trackId,
			source = source,
			zoneId = zoneId,
		})
		state.currentTrackId = nil
		state.currentEntry = nil
		state.isPlaying = false
		resetTiming()
		clearPlaybackFinishVotes()
		cancelAutoAdvance()
		task.defer(function()
			session:advanceQueue("track_unavailable")
		end)
		return false
	end

	local function buildTrackChangedPayload(skipReason: string?): any
		local trackId = state.currentTrackId
		if not trackId then
			return nil
		end
		local track = getTrackById(trackId)
		if not track then
			return nil
		end
		local timing = buildTiming()
		return {
			track = enrichTrack(track, state.currentEntry),
			currentEntry = state.currentEntry,
			timing = timing,
			startServerTime = timing.startServerTime,
			skipReason = skipReason,
		}
	end

	local function fireTrackChanged(members: { Player }?, skipReason: string?)
		if not _onTrackChanged then
			return
		end
		if not resolveZombieCurrentTrack("fireTrackChanged") then
			return
		end
		local payload = buildTrackChangedPayload(skipReason)
		if not payload then
			return
		end
		_onTrackChanged(payload, members, skipReason)
	end

	local function broadcastTrackChanged()
		local reason = pendingSkipReason
		pendingSkipReason = nil
		fireTrackChanged(nil, reason)
	end

	local function syncTrackToPlayer(player: Player)
		fireTrackChanged({ player })
	end

	local function broadcastQueueUpdated()
		if not _onQueueUpdated then
			return
		end
		_onQueueUpdated(buildQueueUpdatePayload())
	end

	local function syncStateToPlayer(player: Player)
		if not _onStateSync then
			return
		end
		resolveZombieCurrentTrack("syncStateToPlayer")
		local payload = session:getState()
		payload.isManageAllowed = isManageAllowed(player)
		_onStateSync(player, payload)
	end

	function session:syncStateToPlayer(player: Player)
		syncStateToPlayer(player)
	end

	local function syncStateToAllMembers()
		if not _onStateSync then
			return
		end
		for _, player in ipairs(getMembers()) do
			syncStateToPlayer(player)
		end
	end

	local function stopPlayback()
		state.currentTrackId = nil
		state.currentEntry = nil
		state.isPlaying = false
		state.voteSkipVoters = {}
		resetTiming()
		clearPlaybackFinishVotes()
		cancelAutoAdvance()
		log:info("Queue habis - playback berhenti", { zoneId = zoneId })
		broadcastQueueUpdated()
		syncStateToAllMembers()
	end

	local function countMapEntries(map: { [number]: true }): number
		local count = 0
		for _ in pairs(map) do
			count += 1
		end
		return count
	end

	local function getRequiredVoteCount(totalPlayers: number): number
		return math.max(1, math.floor(totalPlayers / 2) + 1)
	end

	local function emitVoteState(payload: any, targetPlayer: Player?)
		if not _onVoteState then
			return
		end
		_onVoteState(targetPlayer, payload)
	end

	local function buildVotePayload(action: string, result: string?): any
		if not voteSession then
			return { action = action, result = result }
		end
		local track = getTrackById(voteSession.trackId)
		local playlist = track and repo:getPlaylist(track.playlistId) or nil
		local skipVotes = countMapEntries(voteSession.skipVotes)
		local rejectVotes = countMapEntries(voteSession.rejectVotes)
		return {
			action = action,
			result = result,
			sessionId = voteSession.sessionId,
			track = track,
			playlist = playlist,
			initiatorDisplayName = voteSession.initiatorDisplayName,
			skipVotes = skipVotes,
			rejectVotes = rejectVotes,
			totalVotes = voteSession.totalVotes,
			requiredVotes = getRequiredVoteCount(voteSession.totalVotes),
			startedAt = voteSession.startedAt,
			endsAt = voteSession.endsAt,
		}
	end

	local function clearVoteSession(result: string?)
		if not voteSession then
			state.voteSkipVoters = {}
			return
		end
		local payload = buildVotePayload("ended", result)
		voteSession = nil
		state.voteSkipVoters = {}
		emitVoteState(payload, nil)
	end

	local function updateVoteSessionTotals()
		if not voteSession then
			return
		end
		voteSession.totalVotes = countMapEntries(voteSession.eligibleUserIds)
	end

	local function maybeResolveVoteSession()
		if not voteSession then
			return
		end
		local skipVotes = countMapEntries(voteSession.skipVotes)
		local totalVotes = voteSession.totalVotes
		local requiredVotes = getRequiredVoteCount(totalVotes)
		if skipVotes >= requiredVotes then
			clearVoteSession("passed")
			log:info("Vote skip passed", {
				skipVotes = skipVotes,
				totalVotes = totalVotes,
				requiredVotes = requiredVotes,
				zoneId = zoneId,
			})
			session:advanceQueue("vote_skip")
		end
	end

	local function broadcastActiveVoteState(action: string)
		if not voteSession then
			return
		end
		emitVoteState(buildVotePayload(action, nil), nil)
	end

	local function beginVoteSession(player: Player)
		if voteSession then
			return
		end
		local startedAt = workspace:GetServerTimeNow()
		local endsAt = startedAt + (config.VOTE_SKIP_DURATION or 15)
		local eligibleUserIds = {} :: { [number]: true }
		for _, member in ipairs(getMembers()) do
			eligibleUserIds[member.UserId] = true
		end
		voteSessionCounter += 1
		voteSession = {
			sessionId = ("vote_%d_%d"):format(voteSessionCounter, math.floor(startedAt * 1000)),
			trackId = state.currentTrackId,
			initiatorDisplayName = player.DisplayName,
			startedAt = startedAt,
			endsAt = endsAt,
			eligibleUserIds = eligibleUserIds,
			totalVotes = countMapEntries(eligibleUserIds),
			skipVotes = { [player.UserId] = true } :: { [number]: true },
			rejectVotes = {} :: { [number]: true },
		}
		state.voteSkipVoters = voteSession.skipVotes
		broadcastActiveVoteState("started")
		maybeResolveVoteSession()
		task.delay(config.VOTE_SKIP_DURATION or 15, function()
			if not voteSession then
				return
			end
			if workspace:GetServerTimeNow() < voteSession.endsAt then
				return
			end
			clearVoteSession("failed")
			log:debug("Vote skip expired", { zoneId = zoneId })
		end)
	end

	local function estimateWallDuration(track: TrackInfo): number
		local libraryDuration = tonumber(track.totalDuration) or 0
		if libraryDuration <= 0 then
			return unknownDurationFallbackSeconds + loadGraceSeconds
		end
		local measureSpeed = MusicDomain.computeEffectivePlaybackSpeed(track, globalPlaybackSpeed, 1)
		local currentSpeed = getEffectivePlaybackSpeed(track)
		if math.abs(currentSpeed - measureSpeed) < 0.001 then
			return libraryDuration
		end
		return libraryDuration * (measureSpeed / currentSpeed)
	end

	local function startTrackPlayback(nextEntry: QueueEntry, nextTrack: TrackInfo)
		state.currentTrackId = nextEntry.trackId
		state.currentEntry = nextEntry
		state.startServerTime = workspace:GetServerTimeNow()
		state.isPlaying = true
		state.voteSkipVoters = {}
		clearPlaybackFinishVotes()

		setExpectedEndFromWallDuration(nextTrack, estimateWallDuration(nextTrack), false)
	end

	function session:advanceQueue(skipReason: string?)
		pendingSkipReason = skipReason
		if voteSession then
			clearVoteSession("cancelled")
		end
		local previousTrackId = state.currentTrackId
		state.currentTrackId = nil
		state.currentEntry = nil
		cancelAutoAdvance()
		clearPlaybackFinishVotes()

		local validateOnServer = config.ASSET_VALIDATE_ON_SERVER ~= false
		local usePreloadValidate = config.ASSET_VALIDATE_USE_PRELOAD == true
		local maxSkips = math.max(10, #state.queue + #autoBuffer + 5)
		local skipped = 0

		while skipped < maxSkips do
			if shouldMaintainAutoBuffer() then
				ensureAutoBufferDepth(getAutoQueueDepth())
			end

			local nextEntry: QueueEntry? = nil
			if #state.queue > 0 then
				nextEntry = table.remove(state.queue, 1)
			elseif not state.isDjMode and #autoBuffer > 0 then
				nextEntry = table.remove(autoBuffer, 1)
			elseif not state.isDjMode then
				ensureAutoBufferDepth(getAutoQueueDepth())
				if #autoBuffer > 0 then
					nextEntry = table.remove(autoBuffer, 1)
				elseif shouldMaintainAutoBuffer() and enqueueSystemTrack(previousTrackId) then
					nextEntry = table.remove(autoBuffer, 1)
				end
			end

			if not nextEntry then
				state.isPlaying = false
				resetTiming()
				state.voteSkipVoters = {}
				log:info("Queue habis — playback berhenti", { zoneId = zoneId })
				broadcastQueueUpdated()
				syncStateToAllMembers()
				return
			end

			local nextTrack = getTrackById(nextEntry.trackId)
			if validateOnServer and not MusicAssetValidator.isTrackPlayable(nextTrack, usePreloadValidate) then
				skipped += 1
				log:warn("Skipping track with invalid audio asset metadata", {
					trackId = nextEntry.trackId,
					zoneId = zoneId,
					usePreload = usePreloadValidate,
				})
				continue
			end

			startTrackPlayback(nextEntry, nextTrack :: TrackInfo)
			log:info("Track changed", {
				trackId = nextEntry.trackId,
				entryId = nextEntry.entryId,
				queueSize = #state.queue,
				autoBufferSize = #autoBuffer,
				zoneId = zoneId,
			})
			if shouldMaintainAutoBuffer() then
				ensureAutoBufferDepth(getAutoQueueDepth())
			end
			broadcastTrackChanged()
			broadcastQueueUpdated()
			return
		end

		log:warn("advanceQueue stopped after max asset skips", { zoneId = zoneId, skipped = skipped })
		state.isPlaying = false
		resetTiming()
		cancelAutoAdvance()
		broadcastQueueUpdated()
		syncStateToAllMembers()
	end

	function session:getState(): any
		resolveZombieCurrentTrack("getState")
		local timing = buildTiming()
		return {
			track = enrichTrack(getTrackById(state.currentTrackId), state.currentEntry),
			currentEntry = state.currentEntry,
			timing = timing,
			startServerTime = timing.startServerTime,
			expectedEndServerTime = timing.expectedEndServerTime,
			isPlaying = state.isPlaying,
			isDjMode = state.isDjMode,
			djOwnerUserId = state.djOwnerUserId,
			queue = buildQueueTracks(state.queue),
			prefetchBuffer = buildQueueTracks(autoBuffer),
			djEffects = djEffectState,
		}
	end

	function session:getIncidentSnapshot(): any
		local trackId = state.currentTrackId
		local track = getTrackById(trackId)
		local timing = buildTiming()
		local elapsed = 0
		if state.isPlaying and timing.startServerTime > 0 then
			elapsed = math.max(0, workspace:GetServerTimeNow() - timing.startServerTime)
		end
		return {
			currentTrackId = trackId,
			isPlaying = state.isPlaying,
			startServerTime = timing.startServerTime,
			expectedEndServerTime = timing.expectedEndServerTime,
			trackResolvable = track ~= nil,
			totalDuration = MusicDomain.getTimingTotalSeconds(timing),
			elapsed = elapsed,
		}
	end

	function session:onPlayerEntered(player: Player)
		resolveZombieCurrentTrack("onPlayerEntered")
		if not state.isPlaying and #state.queue == 0 then
			if shouldMaintainAutoBuffer() then
				ensureAutoBufferDepth(getAutoQueueDepth())
			end
			if #state.queue > 0 or #autoBuffer > 0 then
				session:advanceQueue()
				return
			end
		end
		syncStateToPlayer(player)
		if state.isPlaying and state.currentTrackId then
			syncTrackToPlayer(player)
		end
	end

	function session:onPlayerLeft(player: Player)
		local userId = player.UserId
		if state.isDjMode and state.djOwnerUserId == userId then
			session:setDjMode(false, nil)
			for _, member in ipairs(getMembers()) do
				session:syncStateToPlayer(member)
			end
		end
		state.voteSkipVoters[userId] = nil
		playbackFinishVotes[userId] = nil
		if voteSession then
			voteSession.eligibleUserIds[userId] = nil
			voteSession.skipVotes[userId] = nil
			voteSession.rejectVotes[userId] = nil
			updateVoteSessionTotals()
			if voteSession.totalVotes <= 0 then
				clearVoteSession("failed")
			else
				broadcastActiveVoteState("updated")
				maybeResolveVoteSession()
			end
		end
		if #getMembers() == 0 and isSystemEntry(state.currentEntry) and #state.queue == 0 and #autoBuffer == 0 then
			stopPlayback()
		end
	end

	function session:pruneDeletedTracks(deletedLookup: { [string]: true })
		local queueChanged = false
		local newQueue: { QueueEntry } = {}
		for _, entry in ipairs(state.queue) do
			if deletedLookup[entry.trackId] then
				queueChanged = true
			else
				table.insert(newQueue, entry)
			end
		end
		state.queue = newQueue
		local bufferChanged = false
		local newBuffer: { QueueEntry } = {}
		for _, entry in ipairs(autoBuffer) do
			if deletedLookup[entry.trackId] then
				bufferChanged = true
			else
				table.insert(newBuffer, entry)
			end
		end
		autoBuffer = newBuffer
		local currentTrackDeleted = state.currentTrackId ~= nil
			and deletedLookup[state.currentTrackId :: string] == true
		if currentTrackDeleted then
			session:advanceQueue("track_deleted")
		elseif queueChanged or bufferChanged then
			broadcastQueueUpdated()
			syncStateToAllMembers()
		end
	end

	function session:onLibraryReloaded()
		local queueChanged = false
		local nextQueue: { QueueEntry } = {}
		for _, entry in ipairs(state.queue) do
			if repo:getTrack(entry.trackId) then
				table.insert(nextQueue, entry)
			else
				queueChanged = true
			end
		end
		state.queue = nextQueue
		local bufferChanged = false
		local nextBuffer: { QueueEntry } = {}
		for _, entry in ipairs(autoBuffer) do
			if repo:getTrack(entry.trackId) then
				table.insert(nextBuffer, entry)
			else
				bufferChanged = true
			end
		end
		autoBuffer = nextBuffer
		if not resolveZombieCurrentTrack("onLibraryReloaded") then
			return
		end
		if state.currentTrackId then
			broadcastTrackChanged()
		end
		if queueChanged or bufferChanged then
			broadcastQueueUpdated()
		end
		syncStateToAllMembers()
	end

	function session:onDurationUpdated(trackId: string, wallDuration: number): boolean
		if state.currentTrackId ~= trackId or not state.isPlaying then
			return false
		end
		if type(wallDuration) ~= "number" or wallDuration <= 0 then
			return false
		end

		local now = workspace:GetServerTimeNow()
		local elapsed = math.max(0, now - state.startServerTime)
		local minRemaining = math.max(
			15,
			tonumber(config.CLIENT_DURATION_MIN_REMAINING_SECONDS) or 45
		)
		local newExpectedEnd = state.startServerTime + wallDuration

		if newExpectedEnd <= now + minRemaining then
			if newExpectedEnd <= now + 5 then
				task.defer(function()
					if state.currentTrackId == trackId and state.isPlaying then
						session:advanceQueue()
					end
				end)
			end
			return false
		end

		if math.abs(newExpectedEnd - state.expectedEndServerTime) < 0.5 then
			return true
		end

		log:debug("Session timing updated from client duration", {
			trackId = trackId,
			reportedWallDuration = wallDuration,
			previousExpectedEnd = state.expectedEndServerTime,
			nextExpectedEnd = newExpectedEnd,
			zoneId = zoneId,
		})
		return applyTimingUpdate(newExpectedEnd, trackId)
	end

	function session:reportPlaybackFinished(player: Player, trackId: string): (boolean, string)
		if type(trackId) ~= "string" or trackId == "" then
			return false, "invalid_track"
		end
		if state.currentTrackId ~= trackId or not state.isPlaying then
			return true, ""
		end

		playbackFinishVotes[player.UserId] = true
		local members = getMembers()
		local memberCount = #members
		if memberCount <= 0 then
			return true, ""
		end

		local finishCount = 0
		for _, member in ipairs(members) do
			if playbackFinishVotes[member.UserId] then
				finishCount += 1
			end
		end

		local requiredVotes = math.max(1, math.ceil(memberCount * finishQuorumRatio))
		if finishCount < requiredVotes then
			return true, "awaiting_quorum"
		end

		local now = workspace:GetServerTimeNow()
		local elapsed = math.max(0, now - state.startServerTime)
		local totalWall = math.max(1, state.expectedEndServerTime - state.startServerTime)
		local nearExpectedEnd = now >= state.expectedEndServerTime - finishAdvanceToleranceSeconds
		local pastSeventyPercent = elapsed >= totalWall * 0.7

		if nearExpectedEnd or pastSeventyPercent then
			log:debug("Playback finish quorum advancing queue", {
				trackId = trackId,
				finishCount = finishCount,
				memberCount = memberCount,
				zoneId = zoneId,
			})
			session:advanceQueue()
			return true, "advanced"
		end

		applyTimingUpdate(now + 2, trackId)
		return true, "rescheduled"
	end

	function session:startIdleIfNeeded()
		if not state.isPlaying and #state.queue == 0 then
			if shouldMaintainAutoBuffer() then
				ensureAutoBufferDepth(getAutoQueueDepth())
			end
			if #state.queue > 0 or #autoBuffer > 0 then
				session:advanceQueue()
			end
		end
	end

	function session:requestTrack(player: Player, trackId: string): (boolean, string, any?)
		if state.isDjMode and not canControlDuringDjMode(player) then
			return false, "dj_only", nil
		end
		local track = repo:getTrack(trackId)
		if not track then
			return false, "track_not_found", nil
		end
		if state.currentTrackId == trackId then
			return false, "already_playing", nil
		end
		for _, entry in ipairs(state.queue) do
			if entry.trackId == trackId then
				return false, "already_in_queue", nil
			end
		end
		if state.isPlaying and countQueuedTracksForUser(player.UserId) >= requestTrackMaxPerUserQueue then
			return false, "queue_limit_reached", nil
		end

		clearAutoBuffer()
		sanitizeQueue()
		local entry = MusicDomain.newUserQueueEntry(trackId, newEntryId(), player)

		if not state.isPlaying then
			state.queue = { entry }
			session:advanceQueue()
			return true, "", {
				track = track,
				outcome = "playing_now",
				queuePosition = 0,
			}
		end

		table.insert(state.queue, entry)
		broadcastQueueUpdated()
		log:debug("Track requested", { player = player.Name, trackId = trackId, zoneId = zoneId })
		return true, "", {
			track = track,
			outcome = "queued",
			queuePosition = #state.queue,
			userQueueCount = countQueuedTracksForUser(player.UserId),
		}
	end

	function session:voteSkip(player: Player, voteType: string?): (boolean, string)
		if not state.isPlaying then
			return false, "not_playing"
		end

		if state.isDjMode then
			if not canControlDuringDjMode(player) then
				return false, "dj_only"
			end
			session:advanceQueue("vote_skip")
			return true, ""
		end

		local normalizedVoteType = voteType == "reject" and "reject" or "skip"
		local userId = player.UserId
		if not voteSession then
			if normalizedVoteType ~= "skip" then
				return false, "no_active_vote"
			end
			beginVoteSession(player)
			return true, ""
		end
		if voteSession.trackId ~= state.currentTrackId then
			clearVoteSession("cancelled")
			if normalizedVoteType ~= "skip" then
				return false, "vote_expired"
			end
			beginVoteSession(player)
			return true, ""
		end
		if not voteSession.eligibleUserIds[userId] then
			return false, "not_eligible"
		end
		if voteSession.skipVotes[userId] or voteSession.rejectVotes[userId] then
			return false, "already_voted"
		end
		if normalizedVoteType == "reject" then
			voteSession.rejectVotes[userId] = true
		else
			voteSession.skipVotes[userId] = true
		end
		state.voteSkipVoters = voteSession.skipVotes
		log:debug("VoteSkip updated", {
			player = player.Name,
			voteType = normalizedVoteType,
			skipVotes = countMapEntries(voteSession.skipVotes),
			rejectVotes = countMapEntries(voteSession.rejectVotes),
			requiredVotes = getRequiredVoteCount(voteSession.totalVotes),
			totalVotes = voteSession.totalVotes,
			zoneId = zoneId,
		})
		broadcastActiveVoteState("updated")
		maybeResolveVoteSession()
		return true, ""
	end

	function session:adminSkip(): (boolean, string)
		if not state.isPlaying and #state.queue == 0 and #autoBuffer == 0 then
			return false, "nothing_to_skip"
		end
		session:advanceQueue("admin_skip")
		return true, ""
	end

	function session:reportTrackFailure(_player: Player, trackId: string, reason: string?): (boolean, string)
		if type(trackId) ~= "string" or trackId == "" then
			return false, "invalid_track"
		end
		if state.currentTrackId ~= trackId then
			return true, ""
		end
		local failureReason = if type(reason) == "string" then reason else "asset_failed"
		log:debug("Client track failure recorded (no global skip)", {
			trackId = trackId,
			reason = failureReason,
			zoneId = zoneId,
		})
		return true, "recorded"
	end

	function session:setDjMode(enabled: boolean, player: Player?): (boolean, string, boolean)
		local nextValue = enabled == true
		if state.isDjMode == nextValue then
			return true, "", state.isDjMode
		end
		state.isDjMode = nextValue
		state.djOwnerUserId = if nextValue and player then player.UserId else nil
		log:info("DJ mode updated", { enabled = nextValue, djOwnerUserId = state.djOwnerUserId, zoneId = zoneId })
		if nextValue then
			clearAutoBuffer()
			if isSystemEntry(state.currentEntry) then
				if #state.queue > 0 then
					session:advanceQueue()
				else
					stopPlayback()
				end
			else
				syncStateToAllMembers()
			end
		else
			if not state.isPlaying and #state.queue == 0 then
				if shouldMaintainAutoBuffer() then
					ensureAutoBufferDepth(getAutoQueueDepth())
				end
				if #state.queue > 0 or #autoBuffer > 0 then
					session:advanceQueue()
				else
					syncStateToAllMembers()
				end
			else
				syncStateToAllMembers()
			end
		end
		return true, "", state.isDjMode
	end

	function session:setDjEffect(effectId: string, action: string, itemId: string?, value: any): (boolean, string)
		if not state.isDjMode then
			return false, "dj_mode_disabled"
		end
		if type(effectId) ~= "string" or effectId == "" then
			return false, "invalid_effect"
		end
		if action == "toggle" then
			djEffectState.enabled[effectId] = value == true
		elseif action == "set_value" and type(itemId) == "string" and itemId ~= "" then
			if not djEffectState.values[effectId] then
				djEffectState.values[effectId] = {}
			end
			djEffectState.values[effectId][itemId] = tonumber(value) or 0
		else
			return false, "invalid_action"
		end
		syncStateToAllMembers()
		return true, ""
	end

	function session:setDjPlaybackSpeed(speed: number): (boolean, string)
		if not state.isDjMode then
			return false, "dj_mode_disabled"
		end
		local safeMultiplier = math.clamp(tonumber(speed) or 1, 0.25, 2)
		djEffectState.playbackSpeed = safeMultiplier
		rescheduleTimingForSpeedChange()
		syncStateToAllMembers()
		return true, ""
	end

	function session:getDjEffectState(): any
		return djEffectState
	end

	function session:setOnTrackChanged(fn: (any, { Player }?, string?) -> ())
		_onTrackChanged = fn
	end

	function session:setOnTimingUpdated(fn: (any, { Player }?) -> ())
		_onTimingUpdated = fn
	end

	function session:setOnQueueUpdated(fn: ({ queue: { any }, prefetchBuffer: { any } }) -> ())
		_onQueueUpdated = fn
	end

	function session:setOnStateSync(fn: (Player, any) -> ())
		_onStateSync = fn
	end

	function session:setOnVoteState(fn: (Player?, any) -> ())
		_onVoteState = fn
	end

	function session:destroy()
		cancelAutoAdvance()
		if voteSession then
			clearVoteSession("cancelled")
		end
		_onTrackChanged = nil
		_onTimingUpdated = nil
		_onQueueUpdated = nil
		_onStateSync = nil
		_onVoteState = nil
		log:debug("MusicSession destroyed", { zoneId = zoneId })
	end

	return session
end

return createMusicSession
