--!strict
-- Decides what the game does with one answer from GET /game/<key>/v3/music/library (ADR 0010).
-- Pure: the caller does the HTTP call, the JSON decoding and the DataStore work. MusicDomain is
-- passed in so a web track is judged by the kit's own validation, not by a copy of it.
--
-- The rule that matters most: nothing but a well-formed 200 ever replaces the library. A licence
-- 403, an unconfigured route, a VPS that is down or a malformed body all keep what is playing.

local MusicWebLibraryPolicy = {}

local BASE_POLL_SECONDS = 60
local MAX_POLL_SECONDS = 600

export type Response = {
	statusCode: number,
	body: any?,
}

export type Context = {
	currentRevision: string?,
	cachedTrackCount: number,
}

-- action: "apply" | "unchanged" | "keep" | "import"
-- dropped: tracks in the payload the kit would reject (invalid, duplicate, deleted, orphaned).
export type Decision = {
	action: string,
	reason: string,
	revision: string?,
	playlists: { [string]: any }?,
	tracks: { [string]: any }?,
	dropped: number?,
}

local function keep(reason: string): Decision
	return { action = "keep", reason = reason }
end

local function isDeleted(entry: any): boolean
	return type(entry.syncDeletedAt) == "string"
end

local function failureReason(statusCode: number, body: any?): string
	if statusCode == 403 then
		if type(body) == "table" and type(body.error) == "string" and body.error ~= "" then
			return body.error
		end
		return "forbidden"
	elseif statusCode == 409 then
		return "universe_unbound"
	elseif statusCode == 503 then
		return "unconfigured"
	elseif statusCode == 0 or statusCode >= 500 then
		return "unavailable"
	end
	return "unexpected_status"
end

function MusicWebLibraryPolicy.interpret(response: Response, context: Context, domain: any): Decision
	local statusCode = response.statusCode
	if statusCode == 304 then
		return { action = "unchanged", reason = "not_modified" }
	end
	if statusCode ~= 200 then
		return keep(failureReason(statusCode, response.body))
	end

	local body = response.body
	if
		type(body) ~= "table"
		or body.ok ~= true
		or type(body.revision) ~= "string"
		or body.revision == ""
		or type(body.playlists) ~= "table"
		or type(body.tracks) ~= "table"
	then
		return keep("invalid_payload")
	end
	-- The venue's in-game library has not reached the web yet: however complete the web side
	-- looks, it may be stale (ADR 0010 import addendum). Import first, apply nothing.
	if body.import_required == true then
		return { action = "import", reason = "import_required" }
	end
	if context.currentRevision ~= nil and body.revision == context.currentRevision then
		return { action = "unchanged", reason = "same_revision" }
	end

	local playlists: { [string]: any } = {}
	local listedTrackIds: { [string]: { any } } = {}
	for _, raw in ipairs(body.playlists) do
		if
			type(raw) == "table"
			and type(raw.id) == "string"
			and raw.id ~= ""
			and not isDeleted(raw)
			and playlists[raw.id] == nil
			and domain.validatePlaylist(raw)
		then
			local built = domain.buildPlaylist(raw)
			listedTrackIds[raw.id] = if type(raw.trackIds) == "table" then raw.trackIds else {}
			built.trackIds = {}
			playlists[raw.id] = built
		end
	end

	local tracks: { [string]: any } = {}
	local membersByPlaylist: { [string]: { string } } = {}
	local dropped = 0
	local trackCount = 0
	for _, raw in ipairs(body.tracks) do
		local valid = type(raw) == "table"
			and type(raw.id) == "string"
			and raw.id ~= ""
			and not isDeleted(raw)
			and tracks[raw.id] == nil
			and type(raw.playlistId) == "string"
			and playlists[raw.playlistId] ~= nil
		if valid then
			valid = (domain.validateTrack(raw))
		end
		if valid then
			tracks[raw.id] = domain.buildTrack(raw)
			trackCount += 1
			local members = membersByPlaylist[raw.playlistId]
			if not members then
				members = {}
				membersByPlaylist[raw.playlistId] = members
			end
			table.insert(members, raw.id)
		else
			dropped += 1
		end
	end

	-- trackIds describe the tracks actually present: the web's order for the ones it listed,
	-- then any member it did not list, by id, so a stale list can neither hide nor invent a track.
	for playlistId, playlist in pairs(playlists) do
		local ordered: { string } = {}
		local placed: { [string]: boolean } = {}
		for _, trackId in ipairs(listedTrackIds[playlistId]) do
			if type(trackId) == "string" and not placed[trackId] then
				local listed = tracks[trackId]
				if listed and listed.playlistId == playlistId then
					placed[trackId] = true
					table.insert(ordered, trackId)
				end
			end
		end
		local unlisted: { string } = {}
		for _, trackId in ipairs(membersByPlaylist[playlistId] or {}) do
			if not placed[trackId] then
				table.insert(unlisted, trackId)
			end
		end
		table.sort(unlisted)
		for _, trackId in ipairs(unlisted) do
			table.insert(ordered, trackId)
		end
		playlist.trackIds = ordered
	end

	-- A venue still playing from its cache must not go silent because the web side is empty
	-- (a library that was never imported, or one where every track was rejected above).
	if trackCount == 0 and (tonumber(context.cachedTrackCount) or 0) > 0 then
		return keep("web_empty_cache_present")
	end

	return {
		action = "apply",
		reason = "accepted",
		revision = body.revision,
		playlists = playlists,
		tracks = tracks,
		dropped = dropped,
	}
end

-- 60 s while healthy; doubles per consecutive failure, capped at 10 minutes.
function MusicWebLibraryPolicy.nextPollSeconds(consecutiveFailures: number): number
	local failures = math.max(0, math.floor(tonumber(consecutiveFailures) or 0))
	return math.min(MAX_POLL_SECONDS, BASE_POLL_SECONDS * 2 ^ math.min(failures, 10))
end

return MusicWebLibraryPolicy
