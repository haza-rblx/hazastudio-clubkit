--!strict
-- PATH: ServerScriptService/Server/Services/MusicService.lua
-- Manager: owns shared library, rate limiters, rank cache.
-- Central server mode: single global session for all players, no zones.

local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local MusicDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.MusicDomain)
local PermissionDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.PermissionDomain)
local MusicPlayOncePolicy = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.MusicPlayOncePolicy)
local MusicLibraryModel = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.MusicLibraryModel)
local MusicAssetProbe = require(script.Parent.MusicAssetProbe)

local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local HttpApiCounter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApiCounter)
local HttpApi = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApi)
local createMusicSession = require(script.Parent.MusicSession)
local MusicLibraryProvider = require(script.Parent.MusicLibraryProvider)

type TrackInfo = MusicDomain.TrackInfo
type PlaylistInfo = MusicDomain.PlaylistInfo

local function createMusicService(deps: {
	repo: any,
	favoritesRepository: any?,
	overheadRepository: any?,
	eventBus: any?,
	logger: any,
	config: any,
	groupId: number,
	-- When false, favorites GetAsync is owned by SharedProfileLoader (Main).
	loadFavoritesOnJoin: boolean?,
})
	local repo = deps.repo
	local favoritesRepo = deps.favoritesRepository
	local overheadRepository = deps.overheadRepository
	local eventBus = deps.eventBus
	local log = deps.logger
	local loadFavoritesOnJoin = deps.loadFavoritesOnJoin ~= false
	local config = deps.config
	local groupId = deps.groupId

	local service = {}

	local SPECIAL_PLAYLIST_FAVORITES_ID = tostring(config.SPECIAL_PLAYLIST_FAVORITES_ID or "__favorites__")
	local SPECIAL_PLAYLIST_NEW_DROPS_ID = tostring(config.SPECIAL_PLAYLIST_NEW_DROPS_ID or "__new_drops__")
	local NEW_DROPS_WINDOW_SECONDS = tonumber(config.NEW_DROPS_WINDOW_SECONDS) or (7 * 24 * 60 * 60)
	local isStudioMode = RunService:IsStudio()
	local durationUpdateInFlight = {} :: { [string]: boolean }

	-- Teardown handles. MusicService is NOT registered via trackLifecycle (it
	-- needs a manual init() call), so script.Destroying in Main.server calls
	-- service:destroy() to cancel the poll loop, disconnect PlayerRemoving,
	-- unsubscribe EventBus, and destroy sessions. Without this, a Rojo
	-- hot-reload orphaned the poll `while true` thread + stale EventBus
	-- subscriber + stacked PlayerRemoving handlers.
	local _playerRemovingConn: RBXScriptConnection? = nil
	local _eventBusUnsub: (() -> ())? = nil
	local _webProvider: any = nil
	local _destroyed = false

	-- Rank cache: fetch once per player on join
	local rankCache = {} :: { [number]: number }

	-- Role cache: updated live from Overhead:Payload eventBus.
	-- Ini jauh more reliable from DataStore call for check gifted role.
	local roleCache = {} :: { [number]: string }

	-- Rate limiters: per-player, shared across the whole server
	local voteSkipLimiter = RateLimiter.new(config.VOTE_SKIP_RATE_MAX, config.VOTE_SKIP_RATE_WINDOW)
	local requestTrackLimiter = RateLimiter.new(config.REQUEST_TRACK_RATE_MAX, config.REQUEST_TRACK_RATE_WINDOW)
	-- Accepted play-once requests per player (os.time), pruned to the window on every accept.
	-- Kept across rejoin so leaving and coming back does not reset the limit.
	local playOnceRequestTimes = {} :: { [number]: { number } }

	local function normalizeAssetId(raw: any): string?
		local text = tostring(raw or ""):gsub("^%s+", ""):gsub("%s+$", "")
		text = text:gsub("^rbxassetid://", "")
		local numericId = text:match("(%d+)")
		if not numericId or numericId == "" then
			return nil
		end
		return numericId
	end

	local function isPlaylistPrivate(playlist: PlaylistInfo?): boolean
		return type(playlist) == "table" and (playlist :: any).visibility == "private"
	end

	-- Callbacks forwarded from the session to the controller
	-- skipReason: optional string for client notification (vote_skip, admin_skip, etc.)
	local _onTrackChanged: ((any, { Player }, string?) -> ())? = nil
	local _onTimingUpdated: ((any, { Player }) -> ())? = nil
	local _onQueueUpdated: (({ any }, { Player }) -> ())? = nil
	local _onStateSync: ((Player, any) -> ())? = nil
	local _onVoteState: ((Player?, any, { Player }) -> ())? = nil
	-- Single global session for all players (lazy-created on first use).
	local session: any? = nil

	-- ============================================================
	-- RANK / PERMISSION
	-- ============================================================

	local function fetchAndCacheRank(player: Player)
		-- HTTP API telemetry counter (quota-efficiency-pass-2026-06, Phase 0).
		-- Only fire when wrapper disabled (when enabled, wrapper's internal counter handles it).
		if (not (Config.HttpApi and Config.HttpApi.ENABLED)) and Config.HttpApi and Config.HttpApi.COUNTERS_ENABLED then
			HttpApiCounter.record("music_getgroups_total")
		end
		local groups = HttpApi.getGroupsAsync(player.UserId)
		local rank = 0
		if type(groups) == "table" then
			for _, g in ipairs(groups) do
				if g.Id == groupId then
					rank = g.Rank
					break
				end
			end
		else
			log:warn("GroupService:GetGroupsAsync failed", { player = player.Name })
		end
		rankCache[player.UserId] = rank
		log:debug("Rank cached", { player = player.Name, rank = rank })
	end

	-- One music privilege for a player: admin users, then the group role, then the stored /setrole role.
	function service:_hasMusicPrivilege(
		player: Player,
		check: (roleKey: string?, userId: number?) -> boolean,
		privilege: string
	): boolean
		if PermissionDomain.isAdminUser(player.UserId) then
			return true
		end
		local cachedRole = roleCache[player.UserId]
		if type(cachedRole) == "string" and check(cachedRole, player.UserId) then
			return true
		end
		if overheadRepository and type(overheadRepository.load) == "function" then
			local storedResult = overheadRepository:load(player.UserId)
			if storedResult.ok and type(storedResult.value.giftedRole) == "string" then
				if check(storedResult.value.giftedRole, player.UserId) then
					return true
				end
			elseif not storedResult.ok then
				log:warn("Internal role lookup failed for music permission", {
					player = player.Name,
					privilege = privilege,
					error = storedResult.error,
				})
			end
		end
		return false
	end

	-- Live control: DJ mode, effects, speed, skip, private playlists (ADR 0010). The library itself is
	-- edited only in the customer area, so there is no in-game manage privilege any more (3.0).
	function service:isControlAllowed(player: Player): boolean
		return service:_hasMusicPrivilege(player, PermissionDomain.canControlMusic, "musicControl")
	end

	-- Whether this player sees Request From ID. Every per-player state payload must carry it: the
	-- client stores the field as sent, so a payload without it hides the box.
	function service:isPlayOnceOffered(player: Player): boolean
		return MusicPlayOncePolicy.isOffered(config.PLAY_ONCE_REQUEST, service:isControlAllowed(player))
	end

	-- ============================================================
	-- SESSION (single global session)
	-- ============================================================

	local function getMembers(): { Player }
		return Players:GetPlayers()
	end

	local function buildSession(): any
		local sess = createMusicSession({
			repo = repo,
			logger = log,
			config = config,
			getMembers = getMembers,
			isControlAllowed = function(player: Player): boolean
				return service:isControlAllowed(player)
			end,
		})
		sess:setOnTrackChanged(function(payload: any, members: { Player }?, skipReason: string?)
			if _onTrackChanged then
				_onTrackChanged(payload, members or getMembers(), skipReason)
			end
		end)
		sess:setOnTimingUpdated(function(payload: any, members: { Player }?)
			if _onTimingUpdated then
				_onTimingUpdated(payload, members or getMembers())
			end
		end)
		sess:setOnQueueUpdated(function(payload: { queue: { any }, prefetchBuffer: { any } })
			if _onQueueUpdated then _onQueueUpdated(payload, getMembers()) end
		end)
		sess:setOnStateSync(function(player: Player, payload: any)
			if _onStateSync then _onStateSync(player, payload) end
		end)
		sess:setOnVoteState(function(targetPlayer: Player?, payload: any)
			if _onVoteState then _onVoteState(targetPlayer, payload, getMembers()) end
		end)
		return sess
	end

	local function getOrCreateSession(): any
		if session then
			return session
		end
		session = buildSession()
		return session
	end

	local function startGlobalSession()
		local sess = getOrCreateSession()
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(function()
				local waited = 0
				while rankCache[player.UserId] == nil and waited < 5 do
					task.wait(0.2)
					waited += 0.2
				end
				if player.Parent then
					sess:onPlayerEntered(player)
				end
			end)
		end
		log:info("MusicService: global session active")
	end

	-- ============================================================
	-- LIBRARY HELPERS
	-- ============================================================

	local function getFavoriteTrackIds(player: Player?): { [string]: boolean }
		if not favoritesRepo or not player then return {} end
		return favoritesRepo:loadDecoded(player)
	end

	local function isTrackInNewDrops(track: TrackInfo, now: number): boolean
		if type(track.createdAt) ~= "number" or track.createdAt <= 0 then return false end
		return (now - track.createdAt) <= NEW_DROPS_WINDOW_SECONDS
	end

	-- ============================================================
	-- PUBLIC API
	-- ============================================================

	function service:init()
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(fetchAndCacheRank, player)
		end

		-- Subscribe to Overhead:Payload so roleCache stays up-to-date
		-- without a DataStore call every time isControlAllowed runs.
		if eventBus and type(eventBus.on) == "function" then
			_eventBusUnsub = eventBus:on("Overhead:Payload", function(payload: any)
				if type(payload) == "table" and type(payload.userId) == "number" and type(payload.role) == "string" then
					roleCache[payload.userId] = payload.role
				end
			end)
		end

		startGlobalSession()

		-- 3.0 (ADR 0010): the web is the only library, for every venue. Start from the DataStore
		-- cache so music plays even with the VPS down, then let the web replace it. No catalog
		-- seed and no DataStore poll: the web is the only writer.
		local cacheResult = repo:loadAll()
		if not cacheResult.ok then
			log:warn("Music web library: cache unreadable, waiting for the web", { error = cacheResult.error })
		end
		_webProvider = MusicLibraryProvider.new({
			repo = repo,
			logger = log,
			onLibraryApplied = function(removedTrackIds: { [string]: true })
				service:_onWebLibraryApplied(removedTrackIds)
			end,
			getPlayingTrackId = function(): string?
				if not session then
					return nil
				end
				-- currentEntry, not track: track resolves through the repository and is nil
				-- exactly when the id is the one that needs protecting.
				local current = session:getState()
				local entry = type(current) == "table" and current.currentEntry or nil
				return if type(entry) == "table" and type(entry.trackId) == "string" then entry.trackId else nil
			end,
		})
		_webProvider:start()
		log:info("MusicService initialized (web library)")

		_playerRemovingConn = Players.PlayerRemoving:Connect(function(player: Player)
			local userId = player.UserId
			if favoritesRepo and type(favoritesRepo.onPlayerRemoving) == "function" then
				favoritesRepo:onPlayerRemoving(player)
			end
			if session then
				session:onPlayerLeft(player)
			end
			rankCache[userId] = nil
			roleCache[userId] = nil
		end)
	end

	function service:destroy()
		_destroyed = true
		if _webProvider then
			_webProvider:destroy()
			_webProvider = nil
		end
		if _playerRemovingConn then
			_playerRemovingConn:Disconnect()
			_playerRemovingConn = nil
		end
		if _eventBusUnsub then
			pcall(_eventBusUnsub)
			_eventBusUnsub = nil
		end
		-- Destroy the music session (holds autoBuffer, queue, callbacks).
		if session and type((session :: any).destroy) == "function" then
			pcall(function()
				(session :: any):destroy()
			end)
		end
		session = nil
		table.clear(rankCache)
		table.clear(roleCache)
	end

	function service:getState(_player: Player?): any
		return getOrCreateSession():getState()
	end

	function service:getPlaybackIncidentSnapshot(_player: Player?): any?
		local sess = getOrCreateSession()
		if type(sess.getIncidentSnapshot) ~= "function" then
			return nil
		end
		return sess:getIncidentSnapshot()
	end

	function service:getPlaylists(player: Player?): { [string]: PlaylistInfo }
		local result = repo:getPlaylists()
		if not result.ok then
			return {}
		end
		if player and service:isControlAllowed(player) then
			return result.value
		end

		-- A private playlist keeps its card for everyone (the v3 Library shows the PrivateWall);
		-- only musicControl holders receive its track ids.
		local visible: { [string]: PlaylistInfo } = {}
		for id, playlist in pairs(result.value) do
			if isPlaylistPrivate(playlist) then
				local card = table.clone(playlist)
				card.trackIds = {}
				visible[id] = card
			else
				visible[id] = playlist
			end
		end
		return visible
	end

	function service:reloadLibraryFromStore(_reason: string?): (boolean, string)
		-- The DataStore is only a cache of the web library; reloading it would undo a newer snapshot.
		return true, "web_library"
	end

	-- Web snapshot applied: tracks the owner removed leave the queue and the auto buffer (the song
	-- on air was carried by the provider and is not in this set), then every member resyncs.
	function service:_onWebLibraryApplied(removedTrackIds: { [string]: true })
		if not session then
			return
		end
		if next(removedTrackIds) ~= nil then
			session:pruneDeletedTracks(removedTrackIds)
		end
		session:prunePrivateSystemTracks()
		session:onLibraryReloaded()
	end

	function service:getTracksForPlaylist(player: Player?, playlistId: string?): { [string]: TrackInfo }
		local result = repo:getTracks()
		if not result.ok then return {} end
		local canSeePrivate = player ~= nil and service:isControlAllowed(player)
		local playlistsById: { [string]: PlaylistInfo } = {}
		if not canSeePrivate then
			local playlistsResult = repo:getPlaylists()
			if playlistsResult.ok then
				playlistsById = playlistsResult.value
			end
		end
		-- Tracks of a private playlist never reach players without musicControl, whichever list
		-- asks: all tracks (DJ Sets are derived from it), favourites and new drops included.
		local function isVisible(track: TrackInfo): boolean
			return canSeePrivate or not isPlaylistPrivate(playlistsById[track.playlistId])
		end
		if playlistId == SPECIAL_PLAYLIST_FAVORITES_ID then
			local favorites = getFavoriteTrackIds(player)
			local filtered: { [string]: TrackInfo } = {}
			for id, track in pairs(result.value) do
				if favorites[id] == true and isVisible(track) then filtered[id] = track end
			end
			return filtered
		end
		if playlistId == SPECIAL_PLAYLIST_NEW_DROPS_ID then
			local now = os.time()
			local filtered: { [string]: TrackInfo } = {}
			for id, track in pairs(result.value) do
				if isTrackInNewDrops(track, now) and isVisible(track) then filtered[id] = track end
			end
			return filtered
		end
		if playlistId and playlistId ~= "" then
			local playlist = repo:getPlaylist(playlistId)
			if isPlaylistPrivate(playlist) and not canSeePrivate then
				return {}
			end
			local filtered: { [string]: TrackInfo } = {}
			for id, track in pairs(result.value) do
				if track.playlistId == playlistId then filtered[id] = track end
			end
			return filtered
		end
		local filtered: { [string]: TrackInfo } = {}
		for id, track in pairs(result.value) do
			if isVisible(track) then filtered[id] = track end
		end
		return filtered
	end

	local function playOnceLimits(): MusicPlayOncePolicy.Limits
		return {
			maxPending = math.max(1, math.floor(tonumber(config.PLAY_ONCE_MAX_PENDING) or 1)),
			maxPerWindow = math.max(1, math.floor(tonumber(config.PLAY_ONCE_MAX_PER_WINDOW) or 3)),
			windowSeconds = math.max(1, tonumber(config.PLAY_ONCE_WINDOW_SECONDS) or 600),
		}
	end

	local function evaluatePlayOnce(player: Player, now: number): MusicPlayOncePolicy.Decision
		return MusicPlayOncePolicy.evaluate({
			mode = config.PLAY_ONCE_REQUEST,
			isControl = service:isControlAllowed(player),
			pendingCount = getOrCreateSession():countPendingPlayOnce(player.UserId),
			recentRequestTimes = playOnceRequestTimes[player.UserId] or {},
			now = now,
			limits = playOnceLimits(),
		})
	end

	-- Request From ID (3.0, ADR 0010): the asset joins the queue for one play and is never saved.
	-- Evaluated again after GetProductInfoAsync yields, so parallel requests cannot all pass the limits.
	function service:requestPlayOnce(player: Player, rawAssetId: any): (boolean, string, any?)
		local assetId = normalizeAssetId(rawAssetId)
		if not assetId then
			return false, "invalid_asset_id", nil
		end
		local before = evaluatePlayOnce(player, os.time())
		if not before.allowed then
			return false, before.reason, { retryAfter = before.retryAfter }
		end

		local productOk, productInfo = pcall(function()
			return MarketplaceService:GetProductInfoAsync(tonumber(assetId) :: number, Enum.InfoType.Asset)
		end)
		local now = os.time()
		local track, buildReason = MusicPlayOncePolicy.buildTrack({
			assetId = assetId,
			productInfo = if productOk then productInfo else nil,
			guid = HttpService:GenerateGUID(false),
			now = now,
		})
		if not track then
			return false, buildReason, nil
		end

		if MusicAssetProbe.probeTrackAsync(track) == "Failure" then
			return false, "asset_unavailable", nil
		end

		local after = evaluatePlayOnce(player, now)
		if not after.allowed then
			return false, after.reason, { retryAfter = after.retryAfter }
		end
		local ok, err, resultData = getOrCreateSession():requestPlayOnce(player, track)
		if not ok then
			return false, err, nil
		end

		local windowSeconds = playOnceLimits().windowSeconds
		local kept: { number } = {}
		for _, requestedAt in ipairs(playOnceRequestTimes[player.UserId] or {}) do
			if now - requestedAt < windowSeconds then
				table.insert(kept, requestedAt)
			end
		end
		table.insert(kept, now)
		playOnceRequestTimes[player.UserId] = kept
		return true, "", resultData
	end

	function service:addFavoriteTrack(player: Player, trackId: string): (boolean, string, boolean)
		if not favoritesRepo then return false, "favorites_unavailable", false end
		if not repo:getTrack(trackId) then return false, "track_not_found", false end
		local favoriteResult = favoritesRepo:addTrack(player, trackId)
		if not favoriteResult.ok then return false, favoriteResult.error, false end
		return true, "", favoriteResult.value == true
	end

	function service:removeFavoriteTrack(player: Player, trackId: string): (boolean, string, boolean)
		if not favoritesRepo then return false, "favorites_unavailable", false end
		if not repo:getTrack(trackId) then return false, "track_not_found", false end
		local favoriteResult = favoritesRepo:removeTrack(player, trackId)
		if not favoriteResult.ok then return false, favoriteResult.error, false end
		return true, "", favoriteResult.value == true
	end

	function service:requestTrack(player: Player, trackId: string): (boolean, string, any?)
		if not isStudioMode then
			local allowed, _ = requestTrackLimiter:check(player.UserId)
			if not allowed then return false, "rate_limited", nil end
		end
		return getOrCreateSession():requestTrack(player, trackId, service:isControlAllowed(player))
	end

	function service:voteSkip(player: Player, voteType: string?): (boolean, string)
		local allowed, _ = voteSkipLimiter:check(player.UserId)
		if not allowed then return false, "rate_limited" end
		return getOrCreateSession():voteSkip(player, voteType)
	end

	function service:adminSkip(player: Player): (boolean, string)
		if not service:isControlAllowed(player) then return false, "no_permission" end
		log:info("AdminSkip by " .. player.Name)
		return getOrCreateSession():adminSkip()
	end

	-- Telegram / external admin skip: global session only, no in-game player permission.
	function service:adminSkipGlobal(): (boolean, string)
		local sess = getOrCreateSession()
		log:info("AdminSkip via global command")
		return sess:adminSkip()
	end

	-- Active set (docs/plans/active-set.md): the source is resolved here, in the order the Library
	-- list shows it (name, creator, id; New Drops newest first), then handed to the session.
	function service:startActiveSet(player: Player, source: any, shuffle: boolean): (boolean, string, any?)
		local kind = if type(source) == "table" then source.kind else nil
		local title = ""
		local sourceId: string? = nil
		local tracks: { [string]: TrackInfo } = {}
		if kind == "favorites" then
			title = "Liked Tracks"
			tracks = service:getTracksForPlaylist(player, SPECIAL_PLAYLIST_FAVORITES_ID)
		elseif kind == "new_drops" then
			title = "New Drops"
			tracks = service:getTracksForPlaylist(player, SPECIAL_PLAYLIST_NEW_DROPS_ID)
		elseif kind == "playlist" then
			local id = if type(source.id) == "string" then source.id else ""
			local playlist = if id ~= "" then repo:getPlaylist(id) else nil
			if not playlist then
				return false, "playlist_not_found", nil
			end
			title = tostring(playlist.name or "Playlist")
			sourceId = id
			tracks = service:getTracksForPlaylist(player, id)
		else
			return false, "invalid_source", nil
		end
		local ordered = MusicLibraryModel.filterTracks(tracks, nil, kind == "new_drops")
		return getOrCreateSession():startActiveSet(player, {
			title = title,
			sourceKind = kind,
			sourceId = sourceId,
			items = ordered,
			shuffle = shuffle,
		})
	end

	-- v3 transport. Pause / resume / seek / previous / clear and bulk requests (Add set / Shuffle,
	-- owner 2026-10-09) need live control; removing your own queue entry does not.
	function service:transport(player: Player, action: string, payload: any): (boolean, string, any?)
		local sess = getOrCreateSession()
		local canControl = service:isControlAllowed(player)
		if action == "remove" then
			local ok, err = sess:removeQueueEntry(player, tostring(payload.entryId or ""), canControl)
			return ok, err, nil
		elseif action == "request_many" then
			if not canControl then
				return false, "sets_control_only", nil
			end
			if not isStudioMode then
				local allowed, _ = requestTrackLimiter:check(player.UserId)
				if not allowed then
					return false, "rate_limited", nil
				end
			end
			return sess:requestMany(player, payload.trackIds or {}, payload.shuffle == true, canControl)
		elseif action == "set_page" then
			-- Everyone may read the remaining order of the active set.
			return sess:pageActiveSet(payload.offset, payload.limit, payload.query)
		elseif action == "set_start" or action == "set_stop" or action == "set_reshuffle" then
			if not canControl then
				return false, "sets_control_only", nil
			end
			if action == "set_start" then
				if not isStudioMode then
					local allowed, _ = requestTrackLimiter:check(player.UserId)
					if not allowed then
						return false, "rate_limited", nil
					end
				end
				return service:startActiveSet(player, payload.source, payload.shuffle == true)
			elseif action == "set_stop" then
				return sess:stopActiveSet()
			end
			return sess:reshuffleActiveSet()
		end

		if not canControl then
			return false, "no_permission", nil
		end
		local ok, err
		if action == "pause" then
			ok, err = sess:pause()
		elseif action == "resume" then
			ok, err = sess:resume()
		elseif action == "seek" then
			ok, err = sess:seek(tonumber(payload.delta) or 0)
		elseif action == "previous" then
			ok, err = sess:previous()
		elseif action == "clear" then
			ok, err = sess:clearQueue()
		else
			return false, "invalid_action", nil
		end
		if ok then
			log:info("Transport " .. action .. " by " .. player.Name)
		end
		return ok, err, nil
	end

	-- reportTrackFailure: client reports local load failure. Logged only — never
	-- advances the global queue (one bad client must not skip for everyone).
	function service:reportTrackFailure(player: Player, trackId: string, reason: string?): (boolean, string)
		local allowed, _ = voteSkipLimiter:check(player.UserId)
		if not allowed then return false, "rate_limited" end
		return getOrCreateSession():reportTrackFailure(player, trackId, reason)
	end

	function service:setDjMode(player: Player, enabled: boolean): (boolean, string, boolean)
		if not service:isControlAllowed(player) then
			local currentDjMode = session ~= nil and (session:getState().isDjMode == true) or false
			return false, "no_permission", currentDjMode
		end
		return getOrCreateSession():setDjMode(enabled, player)
	end

	-- DJ effect sync: server-authoritative. DJ changes effect → server stores +
	-- broadcasts to all members via stateSync. Listeners apply to local Sound.
	function service:setDjEffect(player: Player, effectId: string, action: string, itemId: string?, value: any): (boolean, string)
		if not service:isControlAllowed(player) then return false, "no_permission" end
		return getOrCreateSession():setDjEffect(effectId, action, itemId, value)
	end

	function service:setDjPlaybackSpeed(player: Player, speed: number): (boolean, string)
		if not service:isControlAllowed(player) then return false, "no_permission" end
		return getOrCreateSession():setDjPlaybackSpeed(speed)
	end

	function service:reportDuration(trackId: string, duration: number)
		if type(duration) ~= "number" or duration <= 0 then
			return
		end
		if durationUpdateInFlight[trackId] then
			return
		end
		if MusicPlayOncePolicy.isPlayOnceId(trackId) then
			-- Play-once tracks live only in the session; there is no library row to update.
			if session then
				session:onDurationUpdated(trackId, duration)
			end
			return
		end
		local track = repo:getTrack(trackId)
		if not track then
			return
		end

		if session then
			session:onDurationUpdated(trackId, duration)
		end

		local libraryDuration = tonumber(track.totalDuration) or 0
		if libraryDuration > 0 and math.abs(libraryDuration - duration) < 0.5 then
			return
		end
		-- Library metadata only grows; session timing is updated above regardless.
		if libraryDuration > 0 and duration < libraryDuration - 1 then
			log:debug("Rejecting client duration shrink for library", {
				trackId = trackId,
				reported = duration,
				library = libraryDuration,
			})
			return
		end
		durationUpdateInFlight[trackId] = true
		local result = repo:updateTrackDuration(trackId, duration)
		durationUpdateInFlight[trackId] = nil
		if not result.ok then
			log:warn("Failed to update track duration", { trackId = trackId, error = result.error })
			return
		end
		log:debug("Track duration updated", { trackId = trackId, duration = duration })
	end

	function service:reportPlaybackFinished(player: Player, trackId: string): (boolean, string)
		return getOrCreateSession():reportPlaybackFinished(player, trackId)
	end

	function service:syncPlayerSessionState(player: Player)
		if not player.Parent then
			return
		end
		local sess = getOrCreateSession()
		if type(sess.onPlayerEntered) == "function" then
			sess:onPlayerEntered(player)
		end
	end

	function service:onPlayerAdded(player: Player)
		if loadFavoritesOnJoin and favoritesRepo and type(favoritesRepo.onPlayerAdded) == "function" then
			favoritesRepo:onPlayerAdded(player)
		end
		task.spawn(fetchAndCacheRank, player)
		-- Auto-enter the global session once rank is cached.
		task.spawn(function()
			local waited = 0
			while rankCache[player.UserId] == nil and waited < 5 do
				task.wait(0.2)
				waited += 0.2
			end
			if player.Parent then
				getOrCreateSession():onPlayerEntered(player)
			end
		end)
	end

	-- Callback registration (forwarded to controller)
	-- skipReason: optional string for client notification (vote_skip, admin_skip, etc.)
	function service:setOnTrackChanged(fn: (any, { Player }, string?) -> ())
		_onTrackChanged = fn
	end

	function service:setOnTimingUpdated(fn: (any, { Player }) -> ())
		_onTimingUpdated = fn
	end

	function service:setOnQueueUpdated(fn: ({ any }, { Player }) -> ())
		_onQueueUpdated = fn
	end

	function service:setOnStateSync(fn: (Player, any) -> ())
		_onStateSync = fn
	end

	function service:setOnVoteState(fn: (Player?, any, { Player }) -> ())
		_onVoteState = fn
	end



	if RunService:IsStudio() then
		_G.musicService = service
	end
	return service
end

return createMusicService
