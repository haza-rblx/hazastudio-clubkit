--!strict
-- PATH: ReplicatedStorage/Shared/Domain/MusicDomain.lua
-- Type definitions untuk Music Player system.

local MusicDomain = {}

-- ============================================================
-- TYPES
-- ============================================================

export type TrackInfo = {
	id            : string,         -- UUID (HttpService:GenerateGUID)
	name          : string,         -- nama lagu
	creator       : string,         -- nama creator/artist
	playlistId    : string,         -- parent playlist ID
	parts         : { string },     -- up to 9 Roblox audio asset IDs (minimal 1, max = Config.Music.MAX_TRACK_PARTS)
	totalDuration : number,         -- detik; 0 saat upload pertama, diisi setelah first play
	playbackSpeed : number?,        -- per-track baseline speed; nil = pakai global Config.Music.PLAYBACK_SPEED
	coverType     : string?,        -- opsional override cover parent playlist: "gradient" | "image"
	coverValue    : any?,           -- gradient index atau image URI / asset id
	createdAt     : number,         -- os.time() saat track dibuat
	updatedAt     : number,         -- os.time() update terakhir
	syncUpdatedAt : string?,
	syncDeletedAt : string?,
	syncRevision  : number?,
	syncSource    : string?,
}

export type PlaylistInfo = {
	id         : string,         -- UUID
	name       : string,
	visibility : string?,        -- "public" | "private" (default "public")
	coverType  : string?,        -- "gradient" | "image" (opsional, default "gradient")
	coverValue : any?,           -- gradient index (number) atau image asset ID (string)
	fontFace   : string?,        -- nama font dari SelectFontFace (opsional)
	trackIds   : { string },     -- urutan track dalam playlist
	syncUpdatedAt : string?,
	syncDeletedAt : string?,
	syncRevision  : number?,
	syncSource    : string?,
}

export type QueueEntry = {
	entryId: string,
	trackId: string,
	source: "user" | "system",
	requesterUserId: number?,
	requesterDisplayName: string,
}

export type PlaybackTiming = {
	startServerTime: number,
	expectedEndServerTime: number,
	effectivePlaybackSpeed: number,
}

export type PlaybackState = {
	currentTrackId: string?,
	currentEntry: QueueEntry?,
	startServerTime: number,
	expectedEndServerTime: number,
	effectivePlaybackSpeed: number,
	isPlaying: boolean,
	isDjMode: boolean,
	djOwnerUserId: number?,
	queue: { QueueEntry },
	voteSkipVoters: { [number]: true },
}

-- Payload yang di-fire oleh RemoteEvent ke client
export type TrackChangedPayload = {
	track: TrackInfo,
	currentEntry: QueueEntry?,
	timing: PlaybackTiming,
	startServerTime: number?, -- legacy alias for timing.startServerTime
	skipReason: string?,
}

export type TimingUpdatedPayload = {
	trackId: string,
	timing: PlaybackTiming,
}

export type QueueUpdatedPayload = {
	queue: { TrackInfo },
	prefetchBuffer: { TrackInfo }?,
}

export type StateSyncPayload = {
	track: TrackInfo?,
	currentEntry: QueueEntry?,
	timing: PlaybackTiming?,
	startServerTime: number?, -- legacy
	expectedEndServerTime: number?, -- legacy
	queue: { TrackInfo },
	prefetchBuffer: { TrackInfo }?,
	isDjMode: boolean,
	djOwnerUserId: number?,
	isManageAllowed: boolean,
	djEffects: any?,
}

-- Action payload untuk RF Manage
export type ManagePlaylistPayload = {
	action : string,  -- "create" | "update" | "delete"
	data   : { [string]: any },
}

export type ManageTrackPayload = {
	action : string,  -- "upload" | "update" | "delete"
	data   : { [string]: any },
}

-- ============================================================
-- HELPERS
-- ============================================================

function MusicDomain.buildQueueEntry(data: { [string]: any }): QueueEntry
	local source = if data.source == "system" then "system" else "user"
	return {
		entryId = tostring(data.entryId or ""),
		trackId = tostring(data.trackId or ""),
		source = source,
		requesterUserId = if type(data.requesterUserId) == "number" then data.requesterUserId else nil,
		requesterDisplayName = tostring(data.requesterDisplayName or ""),
	}
end

function MusicDomain.newUserQueueEntry(trackId: string, entryId: string, player: { UserId: number, DisplayName: string }): QueueEntry
	return {
		entryId = entryId,
		trackId = trackId,
		source = "user",
		requesterUserId = player.UserId,
		requesterDisplayName = player.DisplayName,
	}
end

function MusicDomain.newSystemQueueEntry(trackId: string, entryId: string, displayName: string): QueueEntry
	return {
		entryId = entryId,
		trackId = trackId,
		source = "system",
		requesterUserId = nil,
		requesterDisplayName = displayName,
	}
end

function MusicDomain.applyEntryToTrack(track: any, entry: QueueEntry?): any
	if type(track) ~= "table" or entry == nil then
		return track
	end
	local enriched = table.clone(track) :: any
	enriched.requesterUserId = entry.requesterUserId
	enriched.requesterDisplayName = entry.requesterDisplayName
	enriched.isSystemAssigned = entry.source == "system"
	enriched.queueEntryId = entry.entryId
	return enriched
end

function MusicDomain.computeEffectivePlaybackSpeed(
	track: TrackInfo?,
	globalPlaybackSpeed: number,
	djMultiplier: number
): number
	local base = globalPlaybackSpeed
	if track and type(track.playbackSpeed) == "number" and track.playbackSpeed > 0 then
		base = track.playbackSpeed
	end
	return math.max(0.05, base * math.clamp(djMultiplier, 0.25, 2))
end

function MusicDomain.buildPlaybackTiming(
	startServerTime: number,
	expectedEndServerTime: number,
	effectivePlaybackSpeed: number
): PlaybackTiming
	return {
		startServerTime = startServerTime,
		expectedEndServerTime = expectedEndServerTime,
		effectivePlaybackSpeed = effectivePlaybackSpeed,
	}
end

function MusicDomain.getTimingTotalSeconds(timing: PlaybackTiming?): number
	if type(timing) ~= "table" then
		return 0
	end
	return math.max(0, timing.expectedEndServerTime - timing.startServerTime)
end

function MusicDomain.getTimingElapsedSeconds(timing: PlaybackTiming?, now: number?): number
	if type(timing) ~= "table" then
		return 0
	end
	local clockNow = if type(now) == "number" then now else 0
	return math.max(0, clockNow - timing.startServerTime)
end

function MusicDomain.getTimingProgress(timing: PlaybackTiming?, now: number?): number
	local total = MusicDomain.getTimingTotalSeconds(timing)
	if total <= 0 then
		return 0
	end
	local elapsed = MusicDomain.getTimingElapsedSeconds(timing, now)
	return math.clamp(elapsed / total, 0, 1)
end

-- Validasi TrackInfo sebelum disimpan ke DataStore
function MusicDomain.validateTrack(data: { [string]: any }): (boolean, string)
	if type(data.name) ~= "string" or data.name == "" then
		return false, "Track name kosong atau bukan string"
	end
	if type(data.creator) ~= "string" or data.creator == "" then
		return false, "Track creator kosong atau bukan string"
	end
	if type(data.playlistId) ~= "string" or data.playlistId == "" then
		return false, "playlistId kosong atau bukan string"
	end
	if type(data.parts) ~= "table" or #data.parts < 1 then
		return false, "parts harus array minimal 1 elemen"
	end
	if #data.parts > 9 then
		-- NOTE: must stay in sync with Config.Music.MAX_TRACK_PARTS.
		-- Validator pake literal di sini biar MusicDomain bebas dari
		-- dependency ke Config (avoid circular require).
		return false, "parts tidak boleh lebih dari 9 elemen"
	end
	for i, part in ipairs(data.parts) do
		if type(part) ~= "string" or part == "" then
			return false, ("parts[%d] bukan string valid"):format(i)
		end
	end
	if data.coverType ~= nil then
		if data.coverType ~= "gradient" and data.coverType ~= "image" then
			return false, "coverType harus gradient atau image"
		end
	end
	return true, ""
end

-- Validasi PlaylistInfo sebelum disimpan ke DataStore
function MusicDomain.validatePlaylist(data: { [string]: any }): (boolean, string)
	if type(data.name) ~= "string" or data.name == "" then
		return false, "Playlist name kosong atau bukan string"
	end
	return true, ""
end

-- Build TrackInfo dari raw data (dengan default values)
function MusicDomain.buildTrack(data: { [string]: any }): TrackInfo
	return {
		id            = tostring(data.id or ""),
		name          = tostring(data.name or ""),
		creator       = tostring(data.creator or ""),
		playlistId    = tostring(data.playlistId or ""),
		parts         = data.parts or {},
		totalDuration = tonumber(data.totalDuration) or 0,
		playbackSpeed = if tonumber(data.playbackSpeed) ~= nil and (tonumber(data.playbackSpeed) :: number) > 0
			then tonumber(data.playbackSpeed)
			else nil,
		coverType     = type(data.coverType) == "string" and data.coverType or nil,
		coverValue    = if data.coverValue ~= nil then data.coverValue else nil,
		createdAt     = tonumber(data.createdAt) or 0,
		updatedAt     = tonumber(data.updatedAt) or 0,
		syncUpdatedAt = type(data.syncUpdatedAt) == "string" and data.syncUpdatedAt or nil,
		syncDeletedAt = type(data.syncDeletedAt) == "string" and data.syncDeletedAt or nil,
		syncRevision  = tonumber(data.syncRevision),
		syncSource    = type(data.syncSource) == "string" and data.syncSource or nil,
	}
end

-- Build PlaylistInfo dari raw data (dengan default values)
function MusicDomain.buildPlaylist(data: { [string]: any }): PlaylistInfo
	local legacyCover = data.cover
	local coverType = type(data.coverType) == "string" and data.coverType or nil
	local coverValue = data.coverValue

	if not coverType and type(legacyCover) == "table" then
		coverType = type(legacyCover.type) == "string" and legacyCover.type or nil
		if coverValue == nil then
			coverValue = legacyCover.value
		end
	end

	local visibility = type(data.visibility) == "string" and data.visibility or nil
	if visibility ~= "public" and visibility ~= "private" then
		visibility = "public"
	end

	return {
		id         = tostring(data.id or ""),
		name       = tostring(data.name or ""),
		visibility = visibility,
		coverType  = coverType or "gradient",
		coverValue = coverValue or 1,  -- default gradient index 1
		fontFace   = type(data.fontFace) == "string" and data.fontFace or "Original",
		trackIds   = type(data.trackIds) == "table" and data.trackIds or {},
		syncUpdatedAt = type(data.syncUpdatedAt) == "string" and data.syncUpdatedAt or nil,
		syncDeletedAt = type(data.syncDeletedAt) == "string" and data.syncDeletedAt or nil,
		syncRevision  = tonumber(data.syncRevision),
		syncSource    = type(data.syncSource) == "string" and data.syncSource or nil,
	}
end

return MusicDomain
