--!strict
-- PATH: ServerScriptService/Server/Repositories/MusicRepository.lua
-- DataStore CRUD untuk music library (playlists + tracks).
-- Data disimpan sebagai satu JSON blob per key (shared library, bukan per-player).
-- Pattern: mirip FavoritesRepository tapi dengan global key, bukan per-player key.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local BudgetGate = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetGate)
local MusicDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.MusicDomain)

type Result<T> = Types.Result<T>
type ILogger = Types.ILogger
type TrackInfo = MusicDomain.TrackInfo
type PlaylistInfo = MusicDomain.PlaylistInfo

local MusicRepository = {} :: any
MusicRepository.__index = MusicRepository

local function cloneStringArray(values: { string }): { string }
	local cloned = {} :: { string }
	for index, value in ipairs(values) do
		cloned[index] = value
	end
	return cloned
end

local function clonePlaylist(data: PlaylistInfo): PlaylistInfo
	return {
		id = data.id,
		name = data.name,
		coverType = data.coverType,
		coverValue = data.coverValue,
		fontFace = data.fontFace,
		trackIds = cloneStringArray(data.trackIds),
		syncUpdatedAt = (data :: any).syncUpdatedAt,
		syncDeletedAt = (data :: any).syncDeletedAt,
		syncRevision = (data :: any).syncRevision,
		syncSource = (data :: any).syncSource,
	}
end

local function cloneTrack(data: TrackInfo): TrackInfo
	return {
		id = data.id,
		name = data.name,
		creator = data.creator,
		playlistId = data.playlistId,
		parts = cloneStringArray(data.parts),
		totalDuration = data.totalDuration,
		playbackSpeed = (data :: any).playbackSpeed,
		createdAt = data.createdAt,
		updatedAt = data.updatedAt,
		syncUpdatedAt = (data :: any).syncUpdatedAt,
		syncDeletedAt = (data :: any).syncDeletedAt,
		syncRevision = (data :: any).syncRevision,
		syncSource = (data :: any).syncSource,
	}
end

local function stampSyncFields(data: any, source: string?)
	local now = os.time()
	data.syncUpdatedAt = os.date("!%Y-%m-%dT%H:%M:%SZ", now)
	data.syncRevision = now * 1000
	data.syncSource = source or "club-kit"
end

local function stampDeletedSyncFields(data: any)
	stampSyncFields(data, "club-kit")
	data.syncDeletedAt = data.syncUpdatedAt
end

local function clearDeletedSyncField(data: any)
	data.syncDeletedAt = nil
end

-- Merge two serialized { [id]: entry } maps by syncRevision.
-- Used inside UpdateAsync so concurrent edits from other servers (which share
-- the global PLAYLIST_KEY / TRACK_KEY) are merged instead of clobbered.
-- Last-writer-wins per id by syncRevision; tombstones (entries with
-- syncDeletedAt) win against live entries when their revision is >=.
local function mergeEntriesByRevision(current: { [string]: any }?, incoming: { [string]: any }): { [string]: any }
	if current == nil then
		return incoming
	end
	local merged = {} :: { [string]: any }
	for id, entry in pairs(current :: { [string]: any }) do
		merged[id] = entry
	end
	for id, incomingEntry in pairs(incoming) do
		local existing = merged[id]
		if existing == nil then
			merged[id] = incomingEntry
		else
			local existingRev = tonumber((existing :: any).syncRevision) or 0
			local incomingRev = tonumber((incomingEntry :: any).syncRevision) or 0
			if incomingRev >= existingRev then
				merged[id] = incomingEntry
			end
		end
	end
	return merged
end

function MusicRepository.new(deps: { config: any, logger: ILogger })
	local self = setmetatable({
		_config = deps.config,
		_logger = deps.logger,
		_store = DataStoreService:GetDataStore(deps.config.DATASTORE_NAME),
		_budgetGate = BudgetGate.create({ logger = deps.logger, name = "MusicRepository" }),
		_playlists = {} :: { [string]: PlaylistInfo },
		_tracks = {} :: { [string]: TrackInfo },
		_playlistTombstones = {} :: { [string]: PlaylistInfo },
		_trackTombstones = {} :: { [string]: TrackInfo },
		_loaded = false,
	}, MusicRepository) :: any

	return self
end

function MusicRepository:_clonePlaylists(source: { [string]: PlaylistInfo }): { [string]: PlaylistInfo }
	local cloned = {} :: { [string]: PlaylistInfo }
	for id, playlist in pairs(source) do
		cloned[id] = clonePlaylist(playlist)
	end
	return cloned
end

function MusicRepository:_cloneTracks(source: { [string]: TrackInfo }): { [string]: TrackInfo }
	local cloned = {} :: { [string]: TrackInfo }
	for id, track in pairs(source) do
		cloned[id] = cloneTrack(track)
	end
	return cloned
end

function MusicRepository:_serializePlaylists(source: { [string]: PlaylistInfo }, tombstones: { [string]: PlaylistInfo }?): { [string]: any }
	local serialized = {} :: { [string]: any }
	for id, playlist in pairs(source) do
		serialized[id] = {
			name = playlist.name,
			coverType = playlist.coverType,
			coverValue = playlist.coverValue,
			fontFace = playlist.fontFace,
			trackIds = cloneStringArray(playlist.trackIds),
			syncUpdatedAt = (playlist :: any).syncUpdatedAt,
			syncDeletedAt = (playlist :: any).syncDeletedAt,
			syncRevision = (playlist :: any).syncRevision,
			syncSource = (playlist :: any).syncSource,
		}
	end
	for id, playlist in pairs(tombstones or {}) do
		if serialized[id] == nil then
			serialized[id] = {
				name = playlist.name,
				coverType = playlist.coverType,
				coverValue = playlist.coverValue,
				fontFace = playlist.fontFace,
				trackIds = cloneStringArray(playlist.trackIds),
				syncUpdatedAt = (playlist :: any).syncUpdatedAt,
				syncDeletedAt = (playlist :: any).syncDeletedAt,
				syncRevision = (playlist :: any).syncRevision,
				syncSource = (playlist :: any).syncSource,
			}
		end
	end
	return serialized
end

function MusicRepository:_serializeTracks(source: { [string]: TrackInfo }, tombstones: { [string]: TrackInfo }?): { [string]: any }
	local serialized = {} :: { [string]: any }
	for id, track in pairs(source) do
		serialized[id] = {
			name = track.name,
			creator = track.creator,
			playlistId = track.playlistId,
			parts = cloneStringArray(track.parts),
			totalDuration = track.totalDuration,
			playbackSpeed = (track :: any).playbackSpeed,
			createdAt = track.createdAt,
			updatedAt = track.updatedAt,
			syncUpdatedAt = (track :: any).syncUpdatedAt,
			syncDeletedAt = (track :: any).syncDeletedAt,
			syncRevision = (track :: any).syncRevision,
			syncSource = (track :: any).syncSource,
		}
	end
	for id, track in pairs(tombstones or {}) do
		if serialized[id] == nil then
			serialized[id] = {
				name = track.name,
				creator = track.creator,
				playlistId = track.playlistId,
				parts = cloneStringArray(track.parts),
				totalDuration = track.totalDuration,
				playbackSpeed = (track :: any).playbackSpeed,
				createdAt = track.createdAt,
				updatedAt = track.updatedAt,
				syncUpdatedAt = (track :: any).syncUpdatedAt,
				syncDeletedAt = (track :: any).syncDeletedAt,
				syncRevision = (track :: any).syncRevision,
				syncSource = (track :: any).syncSource,
			}
		end
	end
	return serialized
end

function MusicRepository:_getAsync(key: string): (boolean, any)
	local result = self._budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
		return Result.withRetry(function()
			return self._store:GetAsync(key)
		end, Config.DataStore.RETRY_ATTEMPTS)
	end)
	if not result.ok then
		self._logger:warn("DataStore GetAsync failed", { key = key, error = result.error })
		return false, nil
	end
	if type(result.value) ~= "string" then
		return true, nil
	end

	local decodeOk, decoded = pcall(function()
		return HttpService:JSONDecode(result.value)
	end)
	if not decodeOk or type(decoded) ~= "table" then
		self._logger:warn("JSONDecode failed", { key = key, error = tostring(decoded) })
		return false, nil
	end

	return true, decoded
end

function MusicRepository:_setAsync(key: string, data: any): Result<nil>
	local saveResult = self._budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
		return Result.withRetry(function()
			self._store:UpdateAsync(key, function(currentRaw)
				-- Merge against the current stored value instead of discarding it.
				-- The PLAYLIST_KEY / TRACK_KEY are global and shared across every
				-- server; a blind overwrite would clobber concurrent edits from
				-- other servers (lost-update). We merge per-id by syncRevision
				-- (last-writer-wins), preserving entries this server doesn't know
				-- about and letting tombstones win on revision ties.
				local currentDecoded: { [string]: any }? = nil
				if type(currentRaw) == "string" then
					local ok, decoded = pcall(function()
						return HttpService:JSONDecode(currentRaw)
					end)
					if ok and type(decoded) == "table" then
						currentDecoded = decoded
					end
				end

				local merged = mergeEntriesByRevision(currentDecoded, data)
				local encodeOk, encoded = pcall(function()
					return HttpService:JSONEncode(merged)
				end)
				if not encodeOk then
					-- On encode failure, return the current value unchanged to
					-- avoid destroying stored data.
					return currentRaw
				end
				return encoded
			end)
			return nil
		end, Config.DataStore.RETRY_ATTEMPTS)
	end)
	if not saveResult.ok then
		self._logger:error("DataStore UpdateAsync failed", { key = key, error = saveResult.error })
		return Result.Err("DataStore save failed: " .. saveResult.error)
	end

	return Result.Ok(nil)
end

function MusicRepository:loadAll(): Result<nil>
	local prevPlaylistCount = self:_countTable(self._playlists)
	local prevTrackCount = self:_countTable(self._tracks)

	local loadedPlaylists = {} :: { [string]: PlaylistInfo }
	local loadedTracks = {} :: { [string]: TrackInfo }
	local loadedPlaylistTombstones = {} :: { [string]: PlaylistInfo }
	local loadedTrackTombstones = {} :: { [string]: TrackInfo }

	local okP, rawPlaylists = self:_getAsync(self._config.PLAYLIST_KEY)
	local okT, rawTracks = self:_getAsync(self._config.TRACK_KEY)

	-- Incomplete / failed reads must NOT wipe the in-memory library.
	-- Previously a failed GetAsync still replaced _tracks with {} and returned Ok,
	-- which caused MusicSession:onLibraryReloaded to prune the entire user queue.
	local playlistsReadable = okP and (rawPlaylists == nil or type(rawPlaylists) == "table")
	local tracksReadable = okT and (rawTracks == nil or type(rawTracks) == "table")
	if not playlistsReadable or not tracksReadable then
		self._logger:warn("Music library reload incomplete — keeping prior snapshot", {
			playlistsOk = okP,
			tracksOk = okT,
			playlistsReadable = playlistsReadable,
			tracksReadable = tracksReadable,
			prevPlaylists = prevPlaylistCount,
			prevTracks = prevTrackCount,
		})
		return Result.Err("library_reload_incomplete")
	end

	-- After first successful load, a sudden nil blob (missing key) while we still
	-- have live entries is treated as incomplete — do not clobber memory.
	if self._loaded then
		if rawPlaylists == nil and prevPlaylistCount > 0 then
			self._logger:warn("Music playlists blob missing while local library non-empty — keeping prior snapshot", {
				prevPlaylists = prevPlaylistCount,
			})
			return Result.Err("playlists_blob_missing")
		end
		if rawTracks == nil and prevTrackCount > 0 then
			self._logger:warn("Music tracks blob missing while local library non-empty — keeping prior snapshot", {
				prevTracks = prevTrackCount,
			})
			return Result.Err("tracks_blob_missing")
		end
	end

	if type(rawPlaylists) == "table" then
		for id, data in pairs(rawPlaylists) do
			if type(data) == "table" then
				data.id = id
				local playlist = MusicDomain.buildPlaylist(data)
				if (playlist :: any).syncDeletedAt then
					loadedPlaylistTombstones[id] = playlist
				else
					loadedPlaylists[id] = playlist
				end
			end
		end
	end

	if type(rawTracks) == "table" then
		for id, data in pairs(rawTracks) do
			if type(data) == "table" then
				data.id = id
				local track = MusicDomain.buildTrack(data)
				if (track :: any).syncDeletedAt then
					loadedTrackTombstones[id] = track
				else
					loadedTracks[id] = track
				end
			end
		end
	end

	self._playlists = loadedPlaylists
	self._tracks = loadedTracks
	self._playlistTombstones = loadedPlaylistTombstones
	self._trackTombstones = loadedTrackTombstones
	self._loaded = true

	self._logger:info("MusicRepository loaded", {
		playlists = self:_countTable(self._playlists),
		tracks = self:_countTable(self._tracks),
		playlistTombstones = self:_countTable(self._playlistTombstones),
		trackTombstones = self:_countTable(self._trackTombstones),
		prevPlaylists = prevPlaylistCount,
		prevTracks = prevTrackCount,
	})

	return Result.Ok(nil)
end

function MusicRepository:_countTable(t: { [any]: any }): number
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

function MusicRepository:getPlaylists(): Result<{ [string]: PlaylistInfo }>
	return Result.Ok(self:_clonePlaylists(self._playlists))
end

function MusicRepository:getTracks(): Result<{ [string]: TrackInfo }>
	return Result.Ok(self:_cloneTracks(self._tracks))
end

function MusicRepository:getTrack(trackId: string): TrackInfo?
	local track = self._tracks[trackId]
	return if track then cloneTrack(track) else nil
end

function MusicRepository:getPlaylist(playlistId: string): PlaylistInfo?
	local playlist = self._playlists[playlistId]
	return if playlist then clonePlaylist(playlist) else nil
end

function MusicRepository:savePlaylist(data: PlaylistInfo): Result<nil>
	-- Persist first to prevent memory divergence from DataStore on write failure.
	-- Pattern: REF_PERSISTENCE.md cache invalidation on success only.
	local nextPlaylists = self:_clonePlaylists(self._playlists)
	local nextTombstones = self:_clonePlaylists(self._playlistTombstones)
	local nextData = clonePlaylist(data)
	stampSyncFields(nextData :: any, "club-kit")
	clearDeletedSyncField(nextData :: any)
	nextPlaylists[data.id] = nextData
	nextTombstones[data.id] = nil

	local persistResult = self:_setAsync(
		self._config.PLAYLIST_KEY,
		self:_serializePlaylists(nextPlaylists, nextTombstones)
	)
	if not persistResult.ok then
		return persistResult
	end

	self._playlists = nextPlaylists
	self._playlistTombstones = nextTombstones
	return Result.Ok(nil)
end

function MusicRepository:deletePlaylist(playlistId: string): Result<nil>
	if not self._playlists[playlistId] then
		return Result.Err("Playlist tidak ditemukan: " .. playlistId)
	end

	local nextPlaylists = self:_clonePlaylists(self._playlists)
	local nextTombstones = self:_clonePlaylists(self._playlistTombstones)
	local tombstone = clonePlaylist(self._playlists[playlistId])
	stampDeletedSyncFields(tombstone :: any)
	nextPlaylists[playlistId] = nil
	nextTombstones[playlistId] = tombstone

	local persistResult = self:_setAsync(
		self._config.PLAYLIST_KEY,
		self:_serializePlaylists(nextPlaylists, nextTombstones)
	)
	if not persistResult.ok then
		return persistResult
	end

	self._playlists = nextPlaylists
	self._playlistTombstones = nextTombstones
	return Result.Ok(nil)
end

function MusicRepository:saveTrack(data: TrackInfo): Result<nil>
	local nextTracks = self:_cloneTracks(self._tracks)
	local nextTombstones = self:_cloneTracks(self._trackTombstones)
	local nextData = cloneTrack(data)
	stampSyncFields(nextData :: any, "club-kit")
	clearDeletedSyncField(nextData :: any)
	nextTracks[data.id] = nextData
	nextTombstones[data.id] = nil

	local persistResult = self:_setAsync(
		self._config.TRACK_KEY,
		self:_serializeTracks(nextTracks, nextTombstones)
	)
	if not persistResult.ok then
		return persistResult
	end

	self._tracks = nextTracks
	self._trackTombstones = nextTombstones
	return Result.Ok(nil)
end

function MusicRepository:deleteTrack(trackId: string): Result<nil>
	local currentTrack = self._tracks[trackId]
	if not currentTrack then
		return Result.Err("Track tidak ditemukan: " .. trackId)
	end

	-- Two-phase write: persist playlist first, then track tombstone.
	-- Rollback playlist if track write fails to maintain consistency.
	local nextTracks = self:_cloneTracks(self._tracks)
	local nextTrackTombstones = self:_cloneTracks(self._trackTombstones)
	local trackTombstone = cloneTrack(currentTrack)
	stampDeletedSyncFields(trackTombstone :: any)
	nextTracks[trackId] = nil
	nextTrackTombstones[trackId] = trackTombstone

	local nextPlaylists = self:_clonePlaylists(self._playlists)
	local parentPlaylist = nextPlaylists[currentTrack.playlistId]
	if parentPlaylist then
		local nextTrackIds = {} :: { string }
		for _, id in ipairs(parentPlaylist.trackIds) do
			if id ~= trackId then
				table.insert(nextTrackIds, id)
			end
		end
		parentPlaylist.trackIds = nextTrackIds
		stampSyncFields(parentPlaylist :: any, "club-kit")
	end

	local playlistPersistResult = self:_setAsync(
		self._config.PLAYLIST_KEY,
		self:_serializePlaylists(nextPlaylists, self._playlistTombstones)
	)
	if not playlistPersistResult.ok then
		return playlistPersistResult
	end

	local trackPersistResult = self:_setAsync(
		self._config.TRACK_KEY,
		self:_serializeTracks(nextTracks, nextTrackTombstones)
	)
	if not trackPersistResult.ok then
		local rollbackResult = self:_setAsync(
			self._config.PLAYLIST_KEY,
			self:_serializePlaylists(self._playlists, self._playlistTombstones)
		)
		if not rollbackResult.ok then
			self._logger:error("Rollback playlist gagal setelah deleteTrack gagal", {
				trackId = trackId,
				error = (rollbackResult :: { ok: false, error: string }).error,
			})
		end
		return trackPersistResult
	end

	self._playlists = nextPlaylists
	self._tracks = nextTracks
	self._trackTombstones = nextTrackTombstones
	return Result.Ok(nil)
end

-- ============================================================
-- bulkSeed: insert banyak playlist + track sekaligus dalam 2 DataStore
-- writes (1 per key) sebagai gantinya N writes per item. Pattern dipakai
-- oleh MusicSeeder untuk seed library awal tanpa nge-trigger rate limit.
-- Idempotent saat dipanggil dengan input kosong (return Ok langsung).
-- ============================================================
function MusicRepository:bulkSeed(deps: {
	newPlaylists: { PlaylistInfo },
	newTracks: { TrackInfo },
	appendToExistingPlaylists: { [string]: { string } },
}): Result<nil>
	local hasNewPlaylists = #deps.newPlaylists > 0
	local hasNewTracks = #deps.newTracks > 0
	local hasAppends = next(deps.appendToExistingPlaylists) ~= nil
	if not hasNewPlaylists and not hasNewTracks and not hasAppends then
		return Result.Ok(nil)
	end

	local nextPlaylists = self:_clonePlaylists(self._playlists)
	local nextTracks = self:_cloneTracks(self._tracks)

	-- Add new playlists
	for _, np in ipairs(deps.newPlaylists) do
		local cloned = clonePlaylist(np)
		stampSyncFields(cloned :: any, "music-seeder")
		clearDeletedSyncField(cloned :: any)
		nextPlaylists[cloned.id] = cloned
	end

	-- Append trackIds ke existing playlists (yang udah ada di repo, bukan yang
	-- baru ditambah di newPlaylists — itu sudah masukin trackIds lewat field).
	for playlistId, trackIds in pairs(deps.appendToExistingPlaylists) do
		local target = nextPlaylists[playlistId]
		if target then
			local mergedTrackIds = cloneStringArray(target.trackIds)
			for _, trackId in ipairs(trackIds) do
				table.insert(mergedTrackIds, trackId)
			end
			target.trackIds = mergedTrackIds
			stampSyncFields(target :: any, "music-seeder")
		end
	end

	-- Add new tracks
	for _, nt in ipairs(deps.newTracks) do
		local cloned = cloneTrack(nt)
		stampSyncFields(cloned :: any, "music-seeder")
		clearDeletedSyncField(cloned :: any)
		nextTracks[cloned.id] = cloned
	end

	-- 1 write per key, total 2 writes
	local playlistPersistResult = self:_setAsync(
		self._config.PLAYLIST_KEY,
		self:_serializePlaylists(nextPlaylists, self._playlistTombstones)
	)
	if not playlistPersistResult.ok then
		return playlistPersistResult
	end

	local trackPersistResult = self:_setAsync(
		self._config.TRACK_KEY,
		self:_serializeTracks(nextTracks, self._trackTombstones)
	)
	if not trackPersistResult.ok then
		-- Rollback playlists biar tetap konsisten
		local rollbackResult = self:_setAsync(
			self._config.PLAYLIST_KEY,
			self:_serializePlaylists(self._playlists, self._playlistTombstones)
		)
		if not rollbackResult.ok then
			self._logger:error("bulkSeed rollback failed", {
				error = (rollbackResult :: { ok: false, error: string }).error,
			})
		end
		return trackPersistResult
	end

	self._playlists = nextPlaylists
	self._tracks = nextTracks
	return Result.Ok(nil)
end

function MusicRepository:updateTrackDuration(trackId: string, duration: number): Result<nil>
	local track = self._tracks[trackId]
	if not track then
		return Result.Err("Track tidak ditemukan: " .. trackId)
	end

	local updatedTrack = cloneTrack(track)
	updatedTrack.totalDuration = duration
	return self:saveTrack(updatedTrack)
end

return MusicRepository
