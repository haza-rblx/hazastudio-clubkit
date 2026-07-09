--!strict
-- PATH: ServerScriptService/Server/Controllers/MusicController.lua
-- Wire remotes ke MusicService. Semua handler: validation + rate limit + idempotency.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger      = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local NetworkManager = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkManager)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local Validator   = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Validator)
-- Helper: buat atau ambil remote
local function getOrCreate(parent: Instance, name: string, className: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then return existing end
	if existing then
		existing:Destroy()
	end
	local inst = Instance.new(className)
	inst.Name   = name
	inst.Parent = parent
	return inst
end
-- Idempotency cache helper
local MAX_REQ_CACHE = 5000
local function makeIdempotencyCache(): { [string]: boolean }
	return {}
end
local function checkIdempotency(cache: { [string]: boolean }, requestId: string): boolean
	if cache[requestId] then return false end
	cache[requestId] = true
	-- Hard reset jika terlalu besar
	local count = 0
	for _ in pairs(cache) do
		count += 1
	end
	if count > MAX_REQ_CACHE then
		table.clear(cache)
	end
	return true
end
-- Basic payload validator
local function validatePayload(raw: any): (boolean, string)
	local sizeOk = Validator.checkSize(raw)
	if not sizeOk then
		return false, "payload_too_large"
	end
	if type(raw) ~= "table" then
		return false, "not_table"
	end
	-- requestId wajib untuk command yang modifikasi data
	if type(raw.requestId) ~= "string" or raw.requestId == "" then
		return false, "missing_requestId"
	end
	return true, ""
end
-- String field validator
local function requireString(raw: any, field: string): (boolean, string)
	if type((raw :: any)[field]) ~= "string" or ((raw :: any)[field] :: string) == "" then
		return false, "missing_" .. field
	end
	return true, ""
end

local function fireMusicResponse(
	responseNetwork: any,
	player: Player,
	responseType: string,
	requestId: any,
	ok: boolean,
	data: any?,
	err: string?
)
	if type(requestId) ~= "string" or requestId == "" then
		return
	end

	responseNetwork:fireClient(player, {
		type = "music_response",
		responseType = responseType,
		requestId = requestId,
		ok = ok,
		data = data,
		error = if ok then nil else (err or "request_failed"),
	})
end

local function getMusicFailureNotification(action: string, reason: string, config: any?): (string, string)
	local queueLimit = math.max(1, tonumber(config and config.REQUEST_TRACK_MAX_PER_USER_QUEUE) or 3)
	if reason == "not_in_zone" then
		local message = if config and type(config.MSG_NOT_IN_ZONE) == "string"
			then config.MSG_NOT_IN_ZONE
			else "You're not in a music zone yet. Step into one to start listening."
		return message, "WARNING"
	end

	if action == "request" then
		if reason == "rate_limited" then
			return "You're queueing songs a little too fast. Give it a second.", "WARNING"
		elseif reason == "track_not_found" then
			return "That track couldn't be found.", "ERROR"
		elseif reason == "already_playing" then
			return "That track is already playing.", "WARNING"
		elseif reason == "already_in_queue" then
			return "That track is already waiting in the queue.", "WARNING"
		elseif reason == "queue_limit_reached" then
			return string.format("You already have %d songs lined up. Let the queue breathe first.", queueLimit), "WARNING"
		end
		return "Couldn't queue that track.", "ERROR"
	elseif action == "vote" then
		if reason == "rate_limited" then
			return "You're voting too fast. Try again in a moment.", "WARNING"
		elseif reason == "not_playing" then
			return "Nothing is playing right now.", "WARNING"
		elseif reason == "no_active_vote" then
			return "There isn't an active skip vote right now.", "WARNING"
		elseif reason == "vote_expired" then
			return "That skip vote already ended.", "WARNING"
		elseif reason == "not_eligible" then
			return "You can't vote in this round.", "WARNING"
		elseif reason == "already_voted" then
			return "You already cast your vote.", "WARNING"
		end
		return "Couldn't process your skip vote.", "ERROR"
	elseif action == "admin" then
		if reason == "rate_limited" then
			return "You're doing that too fast. Try again in a moment.", "WARNING"
		elseif reason == "no_permission" then
			return "You don't have permission for that action.", "ERROR"
		elseif reason == "nothing_to_skip" then
			return "There's nothing to skip right now.", "WARNING"
		end
		return "That music action didn't go through.", "ERROR"
	end

	return "That music action didn't go through.", "ERROR"
end

local function notifyMusicFailure(notify: any?, player: Player, action: string, reason: string, config: any?)
	if not notify or type(notify.player) ~= "function" then
		return
	end

	local message, notifType = getMusicFailureNotification(action, reason, config)
	notify.player(player, "[Music] " .. message, notifType)
end

local function notifyMusicRequestSuccess(notify: any?, player: Player, resultData: any)
	if not notify or type(notify.player) ~= "function" then
		return
	end

	local track = type(resultData) == "table" and resultData.track or nil
	local trackName = if type(track) == "table" and type(track.name) == "string" and track.name ~= ""
		then track.name
		else "Your track"
	local outcome = type(resultData) == "table" and resultData.outcome or "queued"
	local queuePosition = type(resultData) == "table" and tonumber(resultData.queuePosition) or nil

	if outcome == "playing_now" then
		notify.player(player, {
			message = "[Music] Now playing.",
			notifType = "SUCCESS",
			domain = "music",
			title = "Now playing",
			description = string.format('"%s" started playing right away.', trackName),
		})
		return
	end

	local description = string.format('"%s" is now in the queue.', trackName)
	if queuePosition and queuePosition > 0 then
		description = string.format('"%s" slid into spot #%d.', trackName, queuePosition)
	end

	notify.player(player, {
		message = "[Music] Added to queue.",
		notifType = "SUCCESS",
		domain = "music",
		title = "Added to queue",
		description = description,
	})
end
-- ============================================================
-- FACTORY
-- ============================================================
local function createMusicController(deps: {
	service : any,
	remotes : Folder,
	logger  : any,
	config  : any,
	notify  : any?,
})
	local service = deps.service
	local remotes = deps.remotes
	local log     = deps.logger or Logger.new("MusicController")
	local config  = deps.config
	local notify  = deps.notify
	local controller = {}
	function controller:init()
		-- Buat semua Remote
		local trackChangedRE   = getOrCreate(remotes, config.REMOTE_TRACK_CHANGED,   "RemoteEvent")  :: RemoteEvent
		local queueUpdatedRE   = getOrCreate(remotes, config.REMOTE_QUEUE_UPDATED,   "RemoteEvent")  :: RemoteEvent
		local stateSyncRE      = getOrCreate(remotes, config.REMOTE_STATE_SYNC,      "RemoteEvent")  :: RemoteEvent
		local timingUpdatedRE  = getOrCreate(remotes, config.REMOTE_TIMING_UPDATED,  "RemoteEvent")  :: RemoteEvent
		local voteStateRE      = getOrCreate(remotes, config.REMOTE_VOTE_STATE,      "RemoteEvent")  :: RemoteEvent
		local durationReportRE = getOrCreate(remotes, config.REMOTE_DURATION_REPORT, "RemoteEvent")  :: RemoteEvent
		local playbackFinishedRE = getOrCreate(remotes, config.REMOTE_PLAYBACK_FINISHED, "RemoteEvent") :: RemoteEvent
		local voteSkipRE       = getOrCreate(remotes, config.REMOTE_VOTE_SKIP,       "RemoteEvent")  :: RemoteEvent
		local requestTrackRE   = getOrCreate(remotes, config.REMOTE_REQUEST_TRACK,   "RemoteEvent")  :: RemoteEvent
		local adminSkipRE      = getOrCreate(remotes, config.REMOTE_ADMIN_SKIP,      "RemoteEvent")  :: RemoteEvent
		local reportFailureRE  = getOrCreate(remotes, config.REMOTE_REPORT_FAILURE,  "RemoteEvent")  :: RemoteEvent

		local responseRemoteEvent = getOrCreate(remotes, config.REMOTE_RESPONSE,    "RemoteEvent") :: RemoteEvent
		local getStateRE      = getOrCreate(remotes, config.REMOTE_GET_STATE,       "RemoteEvent") :: RemoteEvent
		local getPlaylistsRE  = getOrCreate(remotes, config.REMOTE_GET_PLAYLISTS,   "RemoteEvent") :: RemoteEvent
		local getTracksRE     = getOrCreate(remotes, config.REMOTE_GET_TRACKS,      "RemoteEvent") :: RemoteEvent
		local favoriteTrackRE = getOrCreate(remotes, config.REMOTE_FAVORITE_TRACK,  "RemoteEvent") :: RemoteEvent
		local setDjModeRE     = getOrCreate(remotes, config.REMOTE_SET_DJ_MODE,     "RemoteEvent") :: RemoteEvent
		local djEffectRE      = getOrCreate(remotes, config.REMOTE_DJ_EFFECT,       "RemoteEvent") :: RemoteEvent
		local managePlRE      = getOrCreate(remotes, config.REMOTE_MANAGE_PLAYLIST, "RemoteEvent") :: RemoteEvent
		local manageTrRE      = getOrCreate(remotes, config.REMOTE_MANAGE_TRACK,    "RemoteEvent") :: RemoteEvent
		local resolveRequestAssetRE = getOrCreate(
			remotes,
			config.REMOTE_RESOLVE_REQUEST_ASSET,
			"RemoteEvent"
		) :: RemoteEvent

		-- NetworkManagers batch per-Heartbeat. Music broadcasts fan out to many
		-- listeners (track change, queue update, vote state, response).
		local trackChangedNetwork = NetworkManager.create({
			reliable = trackChangedRE,
			logger = log,
			isServer = true,
		})
		local queueUpdatedNetwork = NetworkManager.create({
			reliable = queueUpdatedRE,
			logger = log,
			isServer = true,
		})
		local stateSyncNetwork = NetworkManager.create({
			reliable = stateSyncRE,
			logger = log,
			isServer = true,
		})
		local timingUpdatedNetwork = NetworkManager.create({
			reliable = timingUpdatedRE,
			logger = log,
			isServer = true,
		})
		local voteStateNetwork = NetworkManager.create({
			reliable = voteStateRE,
			logger = log,
			isServer = true,
		})
		local responseRE = NetworkManager.create({
			reliable = responseRemoteEvent,
			logger = log,
			isServer = true,
		})

		local voteSkipCache    = makeIdempotencyCache()
		local requestTrackCache = makeIdempotencyCache()
		local adminSkipCache   = makeIdempotencyCache()
		local reportFailureCache = makeIdempotencyCache()
		local favoriteTrackCache = makeIdempotencyCache()
		local djModeCache      = makeIdempotencyCache()
		local djEffectCache    = makeIdempotencyCache()
		local manageCache      = makeIdempotencyCache()

		local voteSkipLimiter = RateLimiter.new(config.VOTE_SKIP_RATE_MAX, config.VOTE_SKIP_RATE_WINDOW)
		local requestTrackLimiter = RateLimiter.new(config.REQUEST_TRACK_RATE_MAX, config.REQUEST_TRACK_RATE_WINDOW)
		local readLimiter = RateLimiter.new(config.READ_RATE_MAX, config.READ_RATE_WINDOW)
		local durationReportLimiter =
			RateLimiter.new(config.DURATION_REPORT_RATE_MAX, config.DURATION_REPORT_RATE_WINDOW)
		local playbackFinishedLimiter = RateLimiter.new(
			config.PLAYBACK_FINISHED_RATE_MAX,
			config.PLAYBACK_FINISHED_RATE_WINDOW
		)
		local favoriteTrackLimiter = RateLimiter.new(config.FAVORITE_RATE_MAX, config.FAVORITE_RATE_WINDOW)
		local manageLimiter = RateLimiter.new(config.MANAGE_RATE_MAX, config.MANAGE_RATE_WINDOW)
		local djModeLimiter = RateLimiter.new(config.DJ_MODE_RATE_MAX, config.DJ_MODE_RATE_WINDOW)
		local djEffectLimiter = RateLimiter.new(config.DJ_EFFECT_RATE_MAX, config.DJ_EFFECT_RATE_WINDOW)
		local resolveRequestAssetLimiter = RateLimiter.new(
			config.RESOLVE_REQUEST_ASSET_RATE_MAX,
			config.RESOLVE_REQUEST_ASSET_RATE_WINDOW
		)
		local resolveRequestAssetCache = makeIdempotencyCache()
		-- Wire callbacks ke Service
		-- skipReason: optional string for client notification (vote_skip, admin_skip, etc.)
		service:setOnTrackChanged(function(payload: any, members: { Player }, skipReason: string?)
			if type(payload) ~= "table" then
				return
			end
			if skipReason ~= nil and payload.skipReason == nil then
				payload.skipReason = skipReason
			end
			trackChangedNetwork:fireList(members, payload)
		end)
		service:setOnTimingUpdated(function(payload: any, members: { Player })
			if type(payload) ~= "table" then
				return
			end
			timingUpdatedNetwork:fireList(members, payload)
		end)
		service:setOnQueueUpdated(function(updatePayload: any, members: { Player })
			local payload = if type(updatePayload) == "table" and updatePayload.queue ~= nil
				then updatePayload
				else { queue = updatePayload, prefetchBuffer = {} }
			queueUpdatedNetwork:fireList(members, payload)
		end)
		service:setOnStateSync(function(player: Player, payload: any)
			stateSyncNetwork:fireClient(player, payload)
		end)
		service:setOnVoteState(function(targetPlayer: Player?, payload: any, members: { Player })
			if targetPlayer then
				voteStateNetwork:fireClient(targetPlayer, payload)
			else
				voteStateNetwork:fireList(members, payload)
			end
		end)

		if type(service.ensureRequestHistoryPlaylist) == "function" then
			task.spawn(function()
				service:ensureRequestHistoryPlaylist()
			end)
		end

		-- VoteSkip
		voteSkipRE.OnServerEvent:Connect(function(player: Player, raw: any)
			local valid, reason = validatePayload(raw)
			if not valid then
				log:warn("VoteSkip: invalid payload", { player = player.Name, reason = reason })
				notifyMusicFailure(notify, player, "vote", "invalid_request", config)
				return
			end
			if not voteSkipLimiter:check(player.UserId) then
				notifyMusicFailure(notify, player, "vote", "rate_limited", config)
				return
			end
			if not checkIdempotency(voteSkipCache, (raw :: any).requestId) then return end
			task.spawn(function()
				-- Admin+ bypass: langsung adminSkip tanpa masuk vote flow
				if service:isManageAllowed(player) then
					local ok, err = service:adminSkip(player)
					if not ok then
						log:debug("AdminSkip (via vote button) rejected", { player = player.Name, reason = err })
						notifyMusicFailure(notify, player, "vote", err, config)
					end
					return
				end
				local voteType = type((raw :: any).voteType) == "string" and (raw :: any).voteType or "skip"
				local ok, err = service:voteSkip(player, voteType)
				if not ok then
					log:debug("VoteSkip rejected", { player = player.Name, reason = err, voteType = voteType })
					notifyMusicFailure(notify, player, "vote", err, config)
				end
			end)
		end)
		-- RequestTrack
		requestTrackRE.OnServerEvent:Connect(function(player: Player, raw: any)
			local valid, reason = validatePayload(raw)
			if not valid then
				log:warn("RequestTrack: invalid payload", { player = player.Name, reason = reason })
				notifyMusicFailure(notify, player, "request", "invalid_request", config)
				return
			end
			local okStr, errStr = requireString(raw, "trackId")
			if not okStr then
				log:warn("RequestTrack: " .. errStr, { player = player.Name })
				notifyMusicFailure(notify, player, "request", errStr, config)
				return
			end
			if not requestTrackLimiter:check(player.UserId) then
				notifyMusicFailure(notify, player, "request", "rate_limited", config)
				return
			end
			if not checkIdempotency(requestTrackCache, (raw :: any).requestId) then return end
			task.spawn(function()
				local ok, err, resultData = service:requestTrack(player, (raw :: any).trackId)
				if not ok then
					log:debug("RequestTrack rejected", { player = player.Name, reason = err })
					notifyMusicFailure(notify, player, "request", err, config)
					return
				end

				notifyMusicRequestSuccess(notify, player, resultData)
			end)
		end)
		-- AdminSkip
		adminSkipRE.OnServerEvent:Connect(function(player: Player, raw: any)
			local valid, reason = validatePayload(raw)
			if not valid then
				log:warn("AdminSkip: invalid payload", { player = player.Name, reason = reason })
				notifyMusicFailure(notify, player, "admin", "invalid_request", config)
				return
			end
			if not manageLimiter:check(player.UserId) then
				notifyMusicFailure(notify, player, "admin", "rate_limited", config)
				return
			end
			if not checkIdempotency(adminSkipCache, (raw :: any).requestId) then return end
			task.spawn(function()
				local ok, err = service:adminSkip(player)
				if not ok then
					log:debug("AdminSkip rejected", { player = player.Name, reason = err })
					notifyMusicFailure(notify, player, "admin", err, config)
				end
			end)
		end)
		-- ReportFailure: client-side asset failure telemetry (no global skip).
		reportFailureRE.OnServerEvent:Connect(function(player: Player, raw: any)
			local valid, reason = validatePayload(raw)
			if not valid then
				log:debug("ReportFailure: invalid payload", { player = player.Name, reason = reason })
				return
			end
			local trackId = type((raw :: any).trackId) == "string" and (raw :: any).trackId or nil
			if not trackId then
				return
			end
			if not checkIdempotency(reportFailureCache, (raw :: any).requestId) then return end
			local failureReason = type((raw :: any).reason) == "string" and (raw :: any).reason or "asset_failed"
			task.spawn(function()
				local ok, err = service:reportTrackFailure(player, trackId, failureReason)
				if not ok then
					log:debug("ReportFailure rejected", { player = player.Name, reason = err })
				end
			end)
		end)
		-- DurationReport (C -> S, read-only, no idempotency needed)
		durationReportRE.OnServerEvent:Connect(function(player: Player, raw: any)
			if not Validator.checkSize(raw) then return end
			if not durationReportLimiter:check(player.UserId) then return end
			if type(raw) ~= "table" then return end
			local trackId  = type(raw.trackId) == "string" and raw.trackId or nil
			local duration = type(raw.totalDuration) == "number" and raw.totalDuration or nil
			if not trackId or not duration then return end
			task.spawn(function()
				service:reportDuration(trackId, duration)
			end)
		end)
		playbackFinishedRE.OnServerEvent:Connect(function(player: Player, raw: any)
			if not Validator.checkSize(raw) then return end
			if not playbackFinishedLimiter:check(player.UserId) then return end
			if type(raw) ~= "table" then return end
			local trackId = type(raw.trackId) == "string" and raw.trackId or nil
			if not trackId then return end
			task.spawn(function()
				service:reportPlaybackFinished(player, trackId)
			end)
		end)
		-- GetState (RE, read-only)
		getStateRE.OnServerEvent:Connect(function(player: Player, raw: any)
			local valid, reason = validatePayload(raw)
			if not valid then
				log:warn("GetState: invalid payload", { player = player.Name, reason = reason })
				return
			end
			if not readLimiter:check(player.UserId) then
				fireMusicResponse(responseRE, player, "get_state", (raw :: any).requestId, false, nil, "rate_limited")
				return
			end

			task.spawn(function()
				if type(service.syncPlayerSessionState) == "function" then
					service:syncPlayerSessionState(player)
				end
				local currentState = service:getState(player)
				currentState.isManageAllowed = service:isManageAllowed(player)
				fireMusicResponse(responseRE, player, "get_state", (raw :: any).requestId, true, currentState, nil)
			end)
		end)
		-- GetPlaylists (RE, read-only)
		getPlaylistsRE.OnServerEvent:Connect(function(player: Player, raw: any)
			local valid, reason = validatePayload(raw)
			if not valid then
				log:warn("GetPlaylists: invalid payload", { player = player.Name, reason = reason })
				return
			end
			if not readLimiter:check(player.UserId) then
				fireMusicResponse(responseRE, player, "get_playlists", (raw :: any).requestId, false, nil, "rate_limited")
				return
			end

			task.spawn(function()
				fireMusicResponse(responseRE, player, "get_playlists", (raw :: any).requestId, true, service:getPlaylists(player), nil)
			end)
		end)
		resolveRequestAssetRE.OnServerEvent:Connect(function(player: Player, raw: any)
			local valid, reason = validatePayload(raw)
			if not valid then
				log:warn("ResolveRequestAsset: invalid payload", { player = player.Name, reason = reason })
				fireMusicResponse(
					responseRE,
					player,
					"resolve_request_asset",
					type(raw) == "table" and raw.requestId or nil,
					false,
					nil,
					"invalid_request"
				)
				return
			end
			if not resolveRequestAssetLimiter:check(player.UserId) then
				fireMusicResponse(
					responseRE,
					player,
					"resolve_request_asset",
					(raw :: any).requestId,
					false,
					nil,
					"rate_limited"
				)
				return
			end
			if not checkIdempotency(resolveRequestAssetCache, (raw :: any).requestId) then
				fireMusicResponse(
					responseRE,
					player,
					"resolve_request_asset",
					(raw :: any).requestId,
					false,
					nil,
					"duplicate_request"
				)
				return
			end

			task.spawn(function()
				local assetId = type((raw :: any).assetId) == "string" and (raw :: any).assetId
					or type((raw :: any).assetId) == "number" and tostring((raw :: any).assetId)
					or ""
				local ok, err, track = service:resolveOrCreateTrackForAsset(player, assetId)
				fireMusicResponse(
					responseRE,
					player,
					"resolve_request_asset",
					(raw :: any).requestId,
					ok,
					track,
					if ok then nil else err
				)
			end)
		end)
		-- GetTracks (RE, read-only)
		getTracksRE.OnServerEvent:Connect(function(player: Player, raw: any)
			local valid, reason = validatePayload(raw)
			if not valid then
				log:warn("GetTracks: invalid payload", { player = player.Name, reason = reason })
				return
			end
			if not readLimiter:check(player.UserId) then
				fireMusicResponse(responseRE, player, "get_tracks", (raw :: any).requestId, false, nil, "rate_limited")
				return
			end

			task.spawn(function()
				local playlistId = type(raw) == "table" and type(raw.playlistId) == "string"
					and raw.playlistId or nil
				local tracks = service:getTracksForPlaylist(player, playlistId)
				fireMusicResponse(responseRE, player, "get_tracks", (raw :: any).requestId, true, tracks, nil)
			end)
		end)
		favoriteTrackRE.OnServerEvent:Connect(function(player: Player, raw: any)
			local valid, reason = validatePayload(raw)
			if not valid then
				log:warn("FavoriteTrack: invalid payload", { player = player.Name, reason = reason })
				fireMusicResponse(responseRE, player, "favorite_track", type(raw) == "table" and raw.requestId or nil, false, nil, "invalid_request")
				return
			end
			local okStr, errStr = requireString(raw, "trackId")
			if not okStr then
				log:warn("FavoriteTrack: " .. errStr, { player = player.Name })
				fireMusicResponse(responseRE, player, "favorite_track", (raw :: any).requestId, false, nil, errStr)
				return
			end
			if not favoriteTrackLimiter:check(player.UserId) then
				fireMusicResponse(responseRE, player, "favorite_track", (raw :: any).requestId, false, nil, "rate_limited")
				return
			end
			if not checkIdempotency(favoriteTrackCache, (raw :: any).requestId) then
				fireMusicResponse(responseRE, player, "favorite_track", (raw :: any).requestId, false, nil, "duplicate_request")
				return
			end

			task.spawn(function()
				local action = type((raw :: any).action) == "string" and string.lower((raw :: any).action) or "add"
				local ok, err, changed
				if action == "remove" then
					ok, err, changed = service:removeFavoriteTrack(player, (raw :: any).trackId)
				else
					action = "add"
					ok, err, changed = service:addFavoriteTrack(player, (raw :: any).trackId)
				end

				fireMusicResponse(responseRE, player, "favorite_track", (raw :: any).requestId, ok, {
					action = action,
					changed = changed == true,
					added = action == "add" and changed == true,
					removed = action == "remove" and changed == true,
					alreadyFavorited = action == "add" and ok and not (changed == true) or false,
					notFavorited = action == "remove" and ok and not (changed == true) or false,
				}, if ok then nil else err)
			end)
		end)
		setDjModeRE.OnServerEvent:Connect(function(player: Player, raw: any)
			local valid, reason = validatePayload(raw)
			if not valid then
				log:warn("SetDjMode: invalid payload", { player = player.Name, reason = reason })
				fireMusicResponse(responseRE, player, "set_dj_mode", type(raw) == "table" and raw.requestId or nil, false, nil, "invalid_request")
				return
			end
			if not djModeLimiter:check(player.UserId) then
				fireMusicResponse(responseRE, player, "set_dj_mode", (raw :: any).requestId, false, nil, "rate_limited")
				return
			end
			if not checkIdempotency(djModeCache, (raw :: any).requestId) then
				fireMusicResponse(responseRE, player, "set_dj_mode", (raw :: any).requestId, false, nil, "duplicate_request")
				return
			end

			task.spawn(function()
				local enabled = (raw :: any).enabled == true
				local ok, err, isDjMode = service:setDjMode(player, enabled)
				fireMusicResponse(responseRE, player, "set_dj_mode", (raw :: any).requestId, ok, {
					isDjMode = isDjMode == true,
				}, if ok then nil else err)
			end)
		end)
		-- DjEffect: DJ changed an effect toggle or slider value.
		-- Server stores state and broadcasts to all members via stateSync.
		djEffectRE.OnServerEvent:Connect(function(player: Player, raw: any)
			local valid, reason = validatePayload(raw)
			if not valid then
				log:debug("DjEffect: invalid payload", { player = player.Name, reason = reason })
				return
			end
			if not djEffectLimiter:check(player.UserId) then
				return
			end
			if not checkIdempotency(djEffectCache, (raw :: any).requestId) then return end
			local effectAction = type((raw :: any).effectAction) == "string" and (raw :: any).effectAction or ""
			local effectId = type((raw :: any).effectId) == "string" and (raw :: any).effectId or ""
			local itemId = type((raw :: any).itemId) == "string" and (raw :: any).itemId or nil
			local value = (raw :: any).value
			if effectAction == "set_speed" then
				local speed = tonumber(value) or 1
				task.spawn(function()
					service:setDjPlaybackSpeed(player, speed)
				end)
			else
				task.spawn(function()
					local ok, err = service:setDjEffect(player, effectId, effectAction, itemId, value)
					if not ok then
						log:debug("DjEffect rejected", { player = player.Name, reason = err })
					end
				end)
			end
		end)
		-- ManagePlaylist (RE, write, admin only)
		managePlRE.OnServerEvent:Connect(function(player: Player, raw: any)
			local valid, reason = validatePayload(raw)
			if not valid then
				log:warn("ManagePlaylist: invalid payload", { player = player.Name, reason = reason })
				fireMusicResponse(responseRE, player, "manage_playlist", type(raw) == "table" and raw.requestId or nil, false, nil, "invalid_request")
				return
			end
			if not manageLimiter:check(player.UserId) then
				fireMusicResponse(responseRE, player, "manage_playlist", (raw :: any).requestId, false, nil, "rate_limited")
				return
			end
			if not checkIdempotency(manageCache, (raw :: any).requestId) then
				fireMusicResponse(responseRE, player, "manage_playlist", (raw :: any).requestId, false, nil, "duplicate_request")
				return
			end

			task.spawn(function()
				local action = type(raw.action) == "string" and raw.action or ""
				local data   = type(raw.data) == "table" and raw.data or {}
				local ok, _err, result = service:managePlaylist(player, action, data)
				-- Jangan expose detail error internal ke client
				fireMusicResponse(responseRE, player, "manage_playlist", (raw :: any).requestId, ok, if ok then result else nil, if ok then nil else "request_failed")
			end)
		end)
		-- ManageTrack (RE, write, admin only)
		manageTrRE.OnServerEvent:Connect(function(player: Player, raw: any)
			local valid, reason = validatePayload(raw)
			if not valid then
				log:warn("ManageTrack: invalid payload", { player = player.Name, reason = reason })
				fireMusicResponse(responseRE, player, "manage_track", type(raw) == "table" and raw.requestId or nil, false, nil, "invalid_request")
				return
			end
			if not manageLimiter:check(player.UserId) then
				fireMusicResponse(responseRE, player, "manage_track", (raw :: any).requestId, false, nil, "rate_limited")
				return
			end
			if not checkIdempotency(manageCache, (raw :: any).requestId) then
				fireMusicResponse(responseRE, player, "manage_track", (raw :: any).requestId, false, nil, "duplicate_request")
				return
			end

			task.spawn(function()
				local action = type(raw.action) == "string" and raw.action or ""
				local data   = type(raw.data) == "table" and raw.data or {}
				local ok, _err, result = service:manageTrack(player, action, data)
				fireMusicResponse(responseRE, player, "manage_track", (raw :: any).requestId, ok, if ok then result else nil, if ok then nil else "request_failed")
			end)
		end)

		log:info("MusicController initialized")
	end
	return controller
end
return createMusicController
