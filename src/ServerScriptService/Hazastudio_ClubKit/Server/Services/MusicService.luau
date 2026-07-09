--!strict
-- PATH: ServerScriptService/Server/Services/MusicService.lua
-- Manager: owns shared library, rate limiters, rank cache.
-- Central server mode: single global session for all players, no zones.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local GroupService = game:GetService("GroupService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local MusicDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.MusicDomain)
local PermissionDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.PermissionDomain)

local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local HttpApiCounter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApiCounter)
local HttpApi = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApi)
local createMusicSession = require(script.Parent.MusicSession)
local MusicAssetValidator = require(script.Parent.MusicAssetValidator)

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
})
	local repo = deps.repo
	local favoritesRepo = deps.favoritesRepository
	local overheadRepository = deps.overheadRepository
	local eventBus = deps.eventBus
	local log = deps.logger
	local config = deps.config
	local groupId = deps.groupId

	local service = {}

	local SPECIAL_PLAYLIST_FAVORITES_ID = tostring(config.SPECIAL_PLAYLIST_FAVORITES_ID or "__favorites__")
	local SPECIAL_PLAYLIST_NEW_DROPS_ID = tostring(config.SPECIAL_PLAYLIST_NEW_DROPS_ID or "__new_drops__")
	local SPECIAL_PLAYLIST_REQUEST_HISTORY_ID =
		tostring(config.SPECIAL_PLAYLIST_REQUEST_HISTORY_ID or "__request_history__")
	local SPECIAL_PLAYLIST_REQUEST_HISTORY_NAME =
		tostring(config.SPECIAL_PLAYLIST_REQUEST_HISTORY_NAME or "Requested")
	local NEW_DROPS_WINDOW_SECONDS = tonumber(config.NEW_DROPS_WINDOW_SECONDS) or (7 * 24 * 60 * 60)
	local isStudioMode = RunService:IsStudio()
	local isLibraryReloadInFlight = false
	local durationUpdateInFlight = {} :: { [string]: boolean }

	-- Teardown handles. MusicService is NOT registered via trackLifecycle (it
	-- needs a manual init() call), so script.Destroying in Main.server calls
	-- service:destroy() to cancel the poll loop, disconnect PlayerRemoving,
	-- unsubscribe EventBus, and destroy sessions. Without this, a Rojo
	-- hot-reload orphaned the poll `while true` thread + stale EventBus
	-- subscriber + stacked PlayerRemoving handlers.
	local _pollThread: thread? = nil
	local _playerRemovingConn: RBXScriptConnection? = nil
	local _eventBusUnsub: (() -> ())? = nil
	local _destroyed = false

	-- Rank cache: fetch once per player on join
	local rankCache = {} :: { [number]: number }

	-- Role cache: di-update live dari Overhead:Payload eventBus.
	-- Ini jauh lebih reliable dari DataStore call untuk cek gifted role.
	local roleCache = {} :: { [number]: string }

	-- Rate limiters: per-player, shared across all zones to prevent zone-hop bypass
	local voteSkipLimiter = RateLimiter.new(config.VOTE_SKIP_RATE_MAX, config.VOTE_SKIP_RATE_WINDOW)
	local requestTrackLimiter = RateLimiter.new(config.REQUEST_TRACK_RATE_MAX, config.REQUEST_TRACK_RATE_WINDOW)
	local manageLimiter = RateLimiter.new(config.MANAGE_RATE_MAX, config.MANAGE_RATE_WINDOW)

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

	function service:ensureRequestHistoryPlaylist(): PlaylistInfo
		local existing = repo:getPlaylist(SPECIAL_PLAYLIST_REQUEST_HISTORY_ID)
		if existing then
			return existing
		end

		local playlist: PlaylistInfo = MusicDomain.buildPlaylist({
			id = SPECIAL_PLAYLIST_REQUEST_HISTORY_ID,
			name = SPECIAL_PLAYLIST_REQUEST_HISTORY_NAME,
			visibility = "public",
			coverType = "gradient",
			coverValue = 1,
			trackIds = {},
		})
		local saveResult = repo:savePlaylist(playlist)
		if not saveResult.ok then
			log:warn("Gagal bootstrap request history playlist", { error = saveResult.error })
		else
			log:info("Request history playlist bootstrapped", { id = SPECIAL_PLAYLIST_REQUEST_HISTORY_ID })
		end
		return playlist
	end

	-- Callbacks forwarded from sessions to controller
	-- skipReason: optional string for client notification (vote_skip, admin_skip, etc.)
	local _onTrackChanged: ((any, { Player }, string?) -> ())? = nil
	local _onTimingUpdated: ((any, { Player }) -> ())? = nil
	local _onQueueUpdated: (({ any }, { Player }) -> ())? = nil
	local _onStateSync: ((Player, any) -> ())? = nil
	local _onVoteState: ((Player?, any, { Player }) -> ())? = nil
	-- Mode resolution: "global" (single session) atau "zone" (per-tagged-zone).
	-- Default "global" untuk backward-compat.
	local MUSIC_MODE = if type(config.MODE) == "string" and config.MODE == "zone" then "zone" else "global"
	local GLOBAL_ZONE_ID = "__global__"
	local sessions = {} :: { [string]: any }
	service.sessions = sessions

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
			log:warn("GroupService:GetGroupsAsync gagal", { player = player.Name })
		end
		rankCache[player.UserId] = rank
		log:debug("Rank cached", { player = player.Name, rank = rank })
	end

	function service:isManageAllowed(player: Player): boolean
		if PermissionDomain.isAdminUser(player.UserId) then
			return true
		end
		local cachedRole = roleCache[player.UserId]
		if type(cachedRole) == "string" and PermissionDomain.canManageMusic(cachedRole, player.UserId) then
			return true
		end
		if overheadRepository and type(overheadRepository.load) == "function" then
			local storedResult = overheadRepository:load(player.UserId)
			if storedResult.ok and type(storedResult.value.giftedRole) == "string" then
				if PermissionDomain.canManageMusic(storedResult.value.giftedRole, player.UserId) then
					return true
				end
			elseif not storedResult.ok then
				log:warn("Internal role lookup failed for music permission", {
					player = player.Name,
					error = storedResult.error,
				})
			end
		end
		return false
	end

	-- ============================================================
	-- ZONE MEMBERSHIP
	-- ============================================================

	-- Tracks which zone each player is currently in (zone mode only).
	local playerZone: { [number]: string } = {}

	local function getZoneMembers(zoneId: string): { Player }
		if MUSIC_MODE == "global" then
			return Players:GetPlayers()
		end
		local members: { Player } = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if playerZone[player.UserId] == zoneId then
				table.insert(members, player)
			end
		end
		return members
	end

	local function buildSession(zoneId: string, getMembers: () -> { Player }): any
		local sess = createMusicSession({
			zoneId = zoneId,
			repo = repo,
			logger = log,
			config = config,
			getMembers = getMembers,
			isManageAllowed = function(player: Player): boolean
				return service:isManageAllowed(player)
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

	local function ensureSession(zoneId: string): any
		local existing = sessions[zoneId]
		if existing then return existing end
		local sess = buildSession(zoneId, function()
			return getZoneMembers(zoneId)
		end)
		sessions[zoneId] = sess
		return sess
	end

	local function resolveSessionForPlayer(player: Player): any?
		if MUSIC_MODE == "global" then
			return ensureSession(GLOBAL_ZONE_ID)
		end
		local zoneId = playerZone[player.UserId]
		if not zoneId then
			return nil
		end
		return ensureSession(zoneId)
	end

	local function startGlobalSession()
		local sess = ensureSession(GLOBAL_ZONE_ID)
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
		log:info("MusicService: central server mode active", { zoneId = GLOBAL_ZONE_ID })
	end

	local function startZoneSessions()
		-- Zone mode pre-creates a session for each tagged BasePart.
		-- Players don't auto-enter; a future ZoneTracker controller is responsible
		-- for calling service:enterZone(player, zoneId) on volume detection.
		local zoneTag = if type(config.ZONE_TAG) == "string" then config.ZONE_TAG else "MusicZone"
		local zoneIdAttr = if type(config.ZONE_ID_ATTRIBUTE) == "string" then config.ZONE_ID_ATTRIBUTE else "ZoneId"
		local zonesFound = 0
		for _, part in ipairs(CollectionService:GetTagged(zoneTag)) do
			if part:IsA("BasePart") then
				local zoneIdAttrVal = part:GetAttribute(zoneIdAttr)
				local zoneId = if type(zoneIdAttrVal) == "string" and zoneIdAttrVal ~= ""
					then zoneIdAttrVal
					else part:GetFullName()
				ensureSession(zoneId)
				zonesFound += 1
			end
		end
		log:info("MusicService: zone mode active", { zoneTag = zoneTag, zonesFound = zonesFound })
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

		-- Subscribe ke Overhead:Payload agar roleCache selalu up-to-date
		-- tanpa perlu DataStore call setiap kali isManageAllowed dipanggil.
		if eventBus and type(eventBus.on) == "function" then
			_eventBusUnsub = eventBus:on("Overhead:Payload", function(payload: any)
				if type(payload) == "table" and type(payload.userId) == "number" and type(payload.role) == "string" then
					roleCache[payload.userId] = payload.role
				end
			end)
		end

		if MUSIC_MODE == "zone" then
			startZoneSessions()
		else
			startGlobalSession()
		end

		local result = repo:loadAll()
		if not result.ok then
			log:error("Gagal load music library", { error = result.error })
		else
			log:info("MusicService initialized")
			service:ensureRequestHistoryPlaylist()
			local pollInterval = tonumber(config.SYNC_POLL_INTERVAL) or 0
			if pollInterval > 0 then
				_pollThread = task.spawn(function()
					-- Loop berhenti ketika _destroyed di-flip oleh destroy().
					while not _destroyed do
						task.wait(pollInterval)
						if _destroyed then
							break
						end
						service:reloadLibraryFromStore("poll")
					end
				end)
			end
		end

		_playerRemovingConn = Players.PlayerRemoving:Connect(function(player: Player)
			local userId = player.UserId
			if favoritesRepo and type(favoritesRepo.onPlayerRemoving) == "function" then
				favoritesRepo:onPlayerRemoving(player)
			end
			for _, sess in pairs(sessions) do
				sess:onPlayerLeft(player)
			end
			rankCache[userId] = nil
			roleCache[userId] = nil
			-- Clear the zone membership entry so it doesn't leak across the
			-- server lifetime (zone mode only).
			playerZone[userId] = nil
		end)
	end

	function service:destroy()
		_destroyed = true
		if _pollThread then
			task.cancel(_pollThread)
			_pollThread = nil
		end
		if _playerRemovingConn then
			_playerRemovingConn:Disconnect()
			_playerRemovingConn = nil
		end
		if _eventBusUnsub then
			pcall(_eventBusUnsub)
			_eventBusUnsub = nil
		end
		-- Destroy all music sessions (each holds autoBuffer, queue, callbacks).
		for _, sess in pairs(sessions) do
			if type((sess :: any).destroy) == "function" then
				pcall(function()
					(sess :: any):destroy()
				end)
			end
		end
		table.clear(sessions)
		table.clear(playerZone)
		table.clear(rankCache)
		table.clear(roleCache)
	end

	function service:getMusicZoneDebug(): { [string]: any }
		local sess = sessions[GLOBAL_ZONE_ID]
		return {
			mode = "central_server",
			globalSessionActive = sess ~= nil,
			playerCount = #Players:GetPlayers(),
		}
	end

	function service:getState(player: Player?): any
		local sess = if player then resolveSessionForPlayer(player) else nil
		if not sess then
			return {
				track = nil,
				startServerTime = 0,
				isPlaying = false,
				isDjMode = false,
				queue = {},
				zoneId = nil,
				zoneDisplayName = nil,
			}
		end
		local state = sess:getState()
		state.zoneId = nil
		state.zoneDisplayName = nil
		return state
	end

	function service:getPlaybackIncidentSnapshot(player: Player?): any?
		local sess = if player then resolveSessionForPlayer(player) else ensureSession(GLOBAL_ZONE_ID)
		if not sess or type(sess.getIncidentSnapshot) ~= "function" then
			return nil
		end
		return sess:getIncidentSnapshot()
	end

	function service:getPlaylists(player: Player?): { [string]: PlaylistInfo }
		local result = repo:getPlaylists()
		if not result.ok then
			return {}
		end
		if player and service:isManageAllowed(player) then
			return result.value
		end

		local filtered: { [string]: PlaylistInfo } = {}
		for id, playlist in pairs(result.value) do
			if not isPlaylistPrivate(playlist) then
				filtered[id] = playlist
			end
		end
		return filtered
	end

	function service:reloadLibraryFromStore(reason: string?): (boolean, string)
		if isLibraryReloadInFlight then return false, "reload_in_flight" end
		isLibraryReloadInFlight = true
		local result = repo:loadAll()
		isLibraryReloadInFlight = false
		if not result.ok then
			log:warn("Music library reload failed", { reason = reason, error = result.error })
			return false, result.error
		end
		for _, sess in pairs(sessions) do
			sess:onLibraryReloaded()
		end
		return true, ""
	end

	function service:getTracksForPlaylist(player: Player?, playlistId: string?): { [string]: TrackInfo }
		local result = repo:getTracks()
		if not result.ok then return {} end
		if playlistId == SPECIAL_PLAYLIST_FAVORITES_ID then
			local favorites = getFavoriteTrackIds(player)
			local filtered: { [string]: TrackInfo } = {}
			for id, track in pairs(result.value) do
				if favorites[id] == true then filtered[id] = track end
			end
			return filtered
		end
		if playlistId == SPECIAL_PLAYLIST_NEW_DROPS_ID then
			local now = os.time()
			local filtered: { [string]: TrackInfo } = {}
			for id, track in pairs(result.value) do
				if isTrackInNewDrops(track, now) then filtered[id] = track end
			end
			return filtered
		end
		if playlistId and playlistId ~= "" then
			local playlist = repo:getPlaylist(playlistId)
			if isPlaylistPrivate(playlist) and not (player and service:isManageAllowed(player)) then
				return {}
			end
		end
		if not playlistId or playlistId == "" then return result.value end
		local filtered: { [string]: TrackInfo } = {}
		for id, track in pairs(result.value) do
			if track.playlistId == playlistId then filtered[id] = track end
		end
		return filtered
	end

	function service:resolveOrCreateTrackForAsset(_player: Player, rawAssetId: any): (boolean, string, TrackInfo?)
		local assetId = normalizeAssetId(rawAssetId)
		if not assetId then
			return false, "invalid_asset_id", nil
		end

		local usePreload = config.ASSET_VALIDATE_USE_PRELOAD == true
		local assetValid = if usePreload
			then MusicAssetValidator.isPartAssetLoadable(assetId)
			else MusicAssetValidator.isPartAssetIdValid(assetId)
		if not assetValid then
			return false, "asset_not_loadable", nil
		end

		local requestHistoryPlaylist = service:ensureRequestHistoryPlaylist()

		local tracksResult = repo:getTracks()
		if not tracksResult.ok then
			return false, "library_unavailable", nil
		end

		for trackId, track in pairs(tracksResult.value) do
			local firstPart = type(track.parts) == "table" and track.parts[1] or nil
			if tostring(firstPart or "") == assetId then
				local playlist = repo:getPlaylist(requestHistoryPlaylist.id)
				if playlist then
					local alreadyListed = false
					for _, listedTrackId in ipairs(playlist.trackIds) do
						if listedTrackId == trackId then
							alreadyListed = true
							break
						end
					end
					if not alreadyListed then
						local updatedTrackIds = table.clone(playlist.trackIds)
						table.insert(updatedTrackIds, trackId)
						local updatedPlaylist: PlaylistInfo = {
							id = playlist.id,
							name = playlist.name,
							visibility = (playlist :: any).visibility,
							coverType = playlist.coverType,
							coverValue = playlist.coverValue,
							fontFace = playlist.fontFace,
							trackIds = updatedTrackIds,
							syncUpdatedAt = playlist.syncUpdatedAt,
							syncDeletedAt = playlist.syncDeletedAt,
							syncRevision = playlist.syncRevision,
							syncSource = playlist.syncSource,
						}
						local savePlaylistResult = repo:savePlaylist(updatedPlaylist)
						if not savePlaylistResult.ok then
							log:warn("Gagal append track ke request history playlist", {
								trackId = trackId,
								error = savePlaylistResult.error,
							})
						end
					end
				end
				return true, "", track
			end
		end

		local trackName = "Audio " .. assetId
		local trackCreator = "Unknown"
		local productOk, productInfo = pcall(function()
			return MarketplaceService:GetProductInfoAsync(tonumber(assetId), Enum.InfoType.Asset)
		end)
		if productOk and type(productInfo) == "table" then
			-- Verify the asset is actually Audio. Without this a client can
			-- submit an arbitrary (non-audio) image/mesh asset ID; its thumbnail
			-- would be stored on the request-history playlist and rendered to
			-- all clients. The canonical Roblox audio AssetTypeId is 70
			-- (Enum.AssetType.Audio.Value).
			local AUDIO_ASSET_TYPE_ID = 70
			if productInfo.AssetTypeId ~= AUDIO_ASSET_TYPE_ID then
				return false, "asset_not_audio", nil
			end
			if type(productInfo.Name) == "string" and productInfo.Name ~= "" then
				trackName = productInfo.Name
			end
			if type(productInfo.Creator) == "table" and type(productInfo.Creator.Name) == "string" then
				if productInfo.Creator.Name ~= "" then
					trackCreator = productInfo.Creator.Name
				end
			end
		end

		local coverValue = ("rbxthumb://type=Asset&id=%s&w=420&h=420"):format(assetId)
		local now = os.time()
		local trackId = HttpService:GenerateGUID(false)
		local track: TrackInfo = MusicDomain.buildTrack({
			id = trackId,
			name = trackName,
			creator = trackCreator,
			playlistId = requestHistoryPlaylist.id,
			parts = { assetId },
			totalDuration = 0,
			coverType = "image",
			coverValue = coverValue,
			createdAt = now,
			updatedAt = now,
		})

		local saveTrackResult = repo:saveTrack(track)
		if not saveTrackResult.ok then
			return false, "save_failed", nil
		end

		local playlist = repo:getPlaylist(requestHistoryPlaylist.id) or requestHistoryPlaylist
		local updatedTrackIds = table.clone(playlist.trackIds)
		table.insert(updatedTrackIds, trackId)
		local updatedPlaylist: PlaylistInfo = {
			id = playlist.id,
			name = playlist.name,
			visibility = (playlist :: any).visibility,
			coverType = playlist.coverType,
			coverValue = playlist.coverValue,
			fontFace = playlist.fontFace,
			trackIds = updatedTrackIds,
			syncUpdatedAt = playlist.syncUpdatedAt,
			syncDeletedAt = playlist.syncDeletedAt,
			syncRevision = playlist.syncRevision,
			syncSource = playlist.syncSource,
		}
		local savePlaylistResult = repo:savePlaylist(updatedPlaylist)
		if not savePlaylistResult.ok then
			local rollbackResult = repo:deleteTrack(trackId)
			if not rollbackResult.ok then
				log:error("Rollback gagal setelah save request history playlist gagal", {
					trackId = trackId,
					error = rollbackResult.error,
				})
			end
			return false, "save_failed", nil
		end

		log:info("Request asset resolved to track", {
			by = _player.Name,
			assetId = assetId,
			trackId = trackId,
			name = trackName,
		})
		return true, "", track
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
		local sess = resolveSessionForPlayer(player)
		if not sess then return false, "not_in_zone", nil end
		return sess:requestTrack(player, trackId)
	end

	function service:voteSkip(player: Player, voteType: string?): (boolean, string)
		local allowed, _ = voteSkipLimiter:check(player.UserId)
		if not allowed then return false, "rate_limited" end
		local sess = resolveSessionForPlayer(player)
		if not sess then return false, "not_in_zone" end
		return sess:voteSkip(player, voteType)
	end

	function service:adminSkip(player: Player): (boolean, string)
		if not service:isManageAllowed(player) then return false, "no_permission" end
		local sess = resolveSessionForPlayer(player)
		if not sess then return false, "not_in_zone" end
		log:info("AdminSkip by " .. player.Name)
		return sess:adminSkip()
	end

	-- Telegram / external admin skip: global session only, no in-game player permission.
	function service:adminSkipGlobal(): (boolean, string)
		local sess = ensureSession(GLOBAL_ZONE_ID)
		log:info("AdminSkip via global command")
		return sess:adminSkip()
	end

	-- reportTrackFailure: client reports local load failure. Logged only — never
	-- advances the global queue (one bad client must not skip for everyone).
	function service:reportTrackFailure(player: Player, trackId: string, reason: string?): (boolean, string)
		local allowed, _ = voteSkipLimiter:check(player.UserId)
		if not allowed then return false, "rate_limited" end
		local sess = resolveSessionForPlayer(player)
		if not sess then return false, "not_in_zone" end
		return sess:reportTrackFailure(player, trackId, reason)
	end

	function service:setDjMode(player: Player, enabled: boolean): (boolean, string, boolean)
		if not service:isManageAllowed(player) then
			local sess = resolveSessionForPlayer(player)
			local currentDjMode = sess and (sess:getState().isDjMode == true) or false
			return false, "no_permission", currentDjMode
		end
		local sess = resolveSessionForPlayer(player)
		if not sess then return false, "not_in_zone", false end
		return sess:setDjMode(enabled, player)
	end

	-- DJ effect sync: server-authoritative. DJ changes effect → server stores +
	-- broadcasts to all members via stateSync. Listeners apply to local Sound.
	function service:setDjEffect(player: Player, effectId: string, action: string, itemId: string?, value: any): (boolean, string)
		if not service:isManageAllowed(player) then return false, "no_permission" end
		local sess = resolveSessionForPlayer(player)
		if not sess then return false, "not_in_zone" end
		return sess:setDjEffect(effectId, action, itemId, value)
	end

	function service:setDjPlaybackSpeed(player: Player, speed: number): (boolean, string)
		if not service:isManageAllowed(player) then return false, "no_permission" end
		local sess = resolveSessionForPlayer(player)
		if not sess then return false, "not_in_zone" end
		return sess:setDjPlaybackSpeed(speed)
	end

	function service:reportDuration(trackId: string, duration: number)
		if type(duration) ~= "number" or duration <= 0 then
			return
		end
		if durationUpdateInFlight[trackId] then
			return
		end
		local track = repo:getTrack(trackId)
		if not track then
			return
		end

		for _, sess in pairs(sessions) do
			sess:onDurationUpdated(trackId, duration)
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
			log:warn("Gagal update track duration", { trackId = trackId, error = result.error })
			return
		end
		log:debug("Track duration updated", { trackId = trackId, duration = duration })
	end

	function service:reportPlaybackFinished(player: Player, trackId: string): (boolean, string)
		local sess = resolveSessionForPlayer(player)
		if not sess then
			return false, "not_in_zone"
		end
		return sess:reportPlaybackFinished(player, trackId)
	end

	function service:managePlaylist(player: Player, action: string, data: { [string]: any }): (boolean, string, any)
		if not service:isManageAllowed(player) then return false, "no_permission", nil end
		local allowed, _ = manageLimiter:check(player.UserId)
		if not allowed then return false, "rate_limited", nil end

		if action == "create" then
			local ok, err = MusicDomain.validatePlaylist(data)
			if not ok then return false, err, nil end
			local id = HttpService:GenerateGUID(false)
			local playlist: PlaylistInfo = MusicDomain.buildPlaylist({
				id = id,
				name = data.name,
				visibility = type(data.visibility) == "string" and data.visibility or "public",
				coverType = data.coverType,
				coverValue = data.coverValue,
				fontFace = data.fontFace,
				trackIds = {},
			})
			local result = repo:savePlaylist(playlist)
			if not result.ok then return false, "save_failed", nil end
			log:info("Playlist created", { by = player.Name, id = id, name = data.name })
			return true, "", playlist

		elseif action == "update" then
			local id = tostring(data.id or "")
			local existing = repo:getPlaylist(id)
			if not existing then return false, "playlist_not_found", nil end
			local updated: PlaylistInfo = {
				id = id,
				name = type(data.name) == "string" and data.name or existing.name,
				visibility = type(data.visibility) == "string" and data.visibility
					or (existing :: any).visibility
					or "public",
				coverType = type(data.coverType) == "string" and data.coverType or existing.coverType,
				coverValue = data.coverValue ~= nil and data.coverValue or existing.coverValue,
				fontFace = type(data.fontFace) == "string" and data.fontFace or existing.fontFace,
				trackIds = existing.trackIds,
			}
			local result = repo:savePlaylist(updated)
			if not result.ok then return false, "save_failed", nil end
			log:info("Playlist updated", { by = player.Name, id = id })
			return true, "", updated

		elseif action == "delete" then
			local id = tostring(data.id or "")
			local existing = repo:getPlaylist(id)
			if not existing then return false, "playlist_not_found", nil end
			local deletedLookup: { [string]: true } = {}
			for _, trackId in ipairs(existing.trackIds) do
				deletedLookup[trackId] = true
				local deleteTrackResult = repo:deleteTrack(trackId)
				if not deleteTrackResult.ok then
					log:warn("Gagal delete track saat hapus playlist", {
						playlistId = id,
						trackId = trackId,
						error = deleteTrackResult.error,
					})
					return false, "delete_failed", nil
				end
			end
			local result = repo:deletePlaylist(id)
			if not result.ok then return false, "delete_failed", nil end
			for _, sess in pairs(sessions) do
				sess:pruneDeletedTracks(deletedLookup)
			end
			log:info("Playlist deleted", {
				by = player.Name,
				id = id,
				deletedTrackCount = #existing.trackIds,
			})
			return true, "", nil
		end

		return false, "unknown_action", nil
	end

	function service:manageTrack(player: Player, action: string, data: { [string]: any }): (boolean, string, any)
		if not service:isManageAllowed(player) then return false, "no_permission", nil end
		local allowed, _ = manageLimiter:check(player.UserId)
		if not allowed then return false, "rate_limited", nil end

		if action == "upload" then
			local ok, err = MusicDomain.validateTrack(data)
			if not ok then return false, err, nil end
			local playlist = repo:getPlaylist(tostring(data.playlistId or ""))
			if not playlist then return false, "playlist_not_found", nil end
			local id = HttpService:GenerateGUID(false)
			local now = os.time()
			local parts: { string } = {}
			for i, p in ipairs(data.parts) do
				if i > config.MAX_TRACK_PARTS then break end
				table.insert(parts, tostring(p))
			end
			local track: TrackInfo = MusicDomain.buildTrack({
				id = id,
				name = data.name,
				creator = data.creator,
				playlistId = data.playlistId,
				parts = parts,
				totalDuration = 0,
				playbackSpeed = data.playbackSpeed,
				createdAt = now,
				updatedAt = now,
			})
			local saveResult = repo:saveTrack(track)
			if not saveResult.ok then return false, "save_failed", nil end
			local updatedPlaylist: PlaylistInfo = {
				id = playlist.id,
				name = playlist.name,
				visibility = (playlist :: any).visibility,
				coverType = playlist.coverType,
				coverValue = playlist.coverValue,
				fontFace = playlist.fontFace,
				trackIds = {},
			}
			for _, trackId in ipairs(playlist.trackIds) do
				table.insert(updatedPlaylist.trackIds, trackId)
			end
			table.insert(updatedPlaylist.trackIds, id)
			local playlistSaveResult = repo:savePlaylist(updatedPlaylist)
			if not playlistSaveResult.ok then
				local rollbackResult = repo:deleteTrack(id)
				if not rollbackResult.ok then
					log:error("Rollback gagal setelah save playlist music gagal", {
						trackId = id,
						playlistId = playlist.id,
						error = rollbackResult.error,
					})
				end
				return false, "save_failed", nil
			end
			log:info("Track uploaded", { by = player.Name, id = id, name = data.name })
			return true, "", track

		elseif action == "update" then
			local id = tostring(data.id or "")
			local existing = repo:getTrack(id)
			if not existing then return false, "track_not_found", nil end
			local nextPlaylistId = existing.playlistId
			if type(data.playlistId) == "string" and data.playlistId ~= "" then
				nextPlaylistId = data.playlistId
			end
			if nextPlaylistId ~= existing.playlistId and not repo:getPlaylist(nextPlaylistId) then
				return false, "playlist_not_found", nil
			end
			local parts = existing.parts
			local partsWereReplaced = false
			if type(data.parts) == "table" and #data.parts >= 1 then
				partsWereReplaced = true
				parts = {}
				for i, p in ipairs(data.parts) do
					if i > config.MAX_TRACK_PARTS then break end
					table.insert(parts, tostring(p))
				end
			end
			local nextPlaybackSpeed = (existing :: any).playbackSpeed
			if (data :: any).playbackSpeed ~= nil then
				local parsedPlaybackSpeed = tonumber((data :: any).playbackSpeed)
				if parsedPlaybackSpeed and parsedPlaybackSpeed > 0 then
					nextPlaybackSpeed = parsedPlaybackSpeed
				else
					nextPlaybackSpeed = nil
				end
			end
			local updated: TrackInfo = {
				id = id,
				name = type(data.name) == "string" and data.name or existing.name,
				creator = type(data.creator) == "string" and data.creator or existing.creator,
				playlistId = nextPlaylistId,
				parts = parts,
				totalDuration = if partsWereReplaced then 0 else existing.totalDuration,
				playbackSpeed = nextPlaybackSpeed,
				createdAt = existing.createdAt,
				updatedAt = os.time(),
			}
			local result = repo:saveTrack(updated)
			if not result.ok then return false, "save_failed", nil end
			if nextPlaylistId ~= existing.playlistId then
				local oldPlaylist = repo:getPlaylist(existing.playlistId)
				if oldPlaylist then
					local nextOldTrackIds = {}
					for _, trackId in ipairs(oldPlaylist.trackIds) do
						if trackId ~= id then table.insert(nextOldTrackIds, trackId) end
					end
					oldPlaylist.trackIds = nextOldTrackIds
					local oldSave = repo:savePlaylist(oldPlaylist)
					if not oldSave.ok then return false, "save_failed", nil end
				end
				local newPlaylist = repo:getPlaylist(nextPlaylistId)
				if newPlaylist then
					local alreadyListed = false
					for _, trackId in ipairs(newPlaylist.trackIds) do
						if trackId == id then
							alreadyListed = true
							break
						end
					end
					if not alreadyListed then
						table.insert(newPlaylist.trackIds, id)
						local newSave = repo:savePlaylist(newPlaylist)
						if not newSave.ok then return false, "save_failed", nil end
					end
				end
			end
			log:info("Track updated", { by = player.Name, id = id })
			return true, "", updated

		elseif action == "delete" then
			local id = tostring(data.id or "")
			local result = repo:deleteTrack(id)
			if not result.ok then return false, "delete_failed", nil end
			local deletedLookup: { [string]: true } = { [id] = true }
			for _, sess in pairs(sessions) do
				sess:pruneDeletedTracks(deletedLookup)
			end
			log:info("Track deleted", { by = player.Name, id = id })
			return true, "", nil
		end

		return false, "unknown_action", nil
	end

	function service:syncPlayerSessionState(player: Player)
		if not player.Parent then
			return
		end
		local sess = resolveSessionForPlayer(player)
		if sess and type(sess.onPlayerEntered) == "function" then
			sess:onPlayerEntered(player)
		end
	end

	function service:onPlayerAdded(player: Player)
		if favoritesRepo and type(favoritesRepo.onPlayerAdded) == "function" then
			favoritesRepo:onPlayerAdded(player)
		end
		task.spawn(fetchAndCacheRank, player)
		-- Global mode: auto-enter the single session once rank is cached.
		-- Zone mode: caller (ZoneTracker) is responsible for service:enterZone(...).
		if MUSIC_MODE == "global" then
			task.spawn(function()
				local waited = 0
				while rankCache[player.UserId] == nil and waited < 5 do
					task.wait(0.2)
					waited += 0.2
				end
				if player.Parent then
					ensureSession(GLOBAL_ZONE_ID):onPlayerEntered(player)
				end
			end)
		end
	end

	--- Zone mode entry point. Call from ZoneTracker when a player enters a
	--- tagged BasePart. No-op in global mode.
	function service:enterZone(player: Player, zoneId: string)
		if MUSIC_MODE ~= "zone" then return end
		if type(zoneId) ~= "string" or zoneId == "" then return end
		local previous = playerZone[player.UserId]
		if previous == zoneId then return end
		if previous then
			local prevSess = sessions[previous]
			if prevSess and type(prevSess.onPlayerLeft) == "function" then
				prevSess:onPlayerLeft(player)
			end
		end
		playerZone[player.UserId] = zoneId
		local sess = ensureSession(zoneId)
		if sess and type(sess.onPlayerEntered) == "function" then
			sess:onPlayerEntered(player)
		end
	end

	--- Zone mode exit point. No-op in global mode.
	function service:leaveZone(player: Player)
		if MUSIC_MODE ~= "zone" then return end
		local previous = playerZone[player.UserId]
		if not previous then return end
		playerZone[player.UserId] = nil
		local sess = sessions[previous]
		if sess and type(sess.onPlayerLeft) == "function" then
			sess:onPlayerLeft(player)
		end
	end

	--- Read the active mode (used by client for UI gating, e.g. hiding zone
	--- prompts when mode is global).
	function service:getMode(): string
		return MUSIC_MODE
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



	local debugFunction = ServerScriptService:FindFirstChild("MusicZoneDebug")
	if debugFunction and not debugFunction:IsA("BindableFunction") then
		debugFunction:Destroy()
		debugFunction = nil
	end
	if not debugFunction then
		debugFunction = Instance.new("BindableFunction")
		debugFunction.Name = "MusicZoneDebug"
		debugFunction.Parent = ServerScriptService
	end
	(debugFunction :: BindableFunction).OnInvoke = function()
		return service:getMusicZoneDebug()
	end

	if RunService:IsStudio() then
		_G.musicService = service
	end
	return service
end

return createMusicService
