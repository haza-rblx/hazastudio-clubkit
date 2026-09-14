--!strict
-- PATH: ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/MusicLibraryModel.luau
-- Pure v3 Library logic: playlist/track ordering, search, and DJ Sets (one per creator, derived at
-- read time — CONTEXT.md "DJ Set"). No Roblox APIs, so it runs under lune.

local MusicLibraryModel = {}

local DJ_SET_PREFIX = "djset:"
-- Filled in by BRM / asset lookups when the real artist is not known; never a DJ.
local PLACEHOLDER_CREATORS = {
	["unknown"] = true,
	["unknown creator"] = true,
	["unknown artist"] = true,
}

export type PlaylistEntry = { id: string, playlist: any }
export type DjSet = { id: string, name: string, trackIds: { string } }

local function lower(value: any): string
	return string.lower(tostring(value or ""))
end

local function trim(value: any): string
	local text = (string.gsub(tostring(value or ""), "^%s+", ""))
	return (string.gsub(text, "%s+$", ""))
end

local function creatorKey(creator: any): string
	return string.lower(trim(creator))
end

-- Plain-text, case-insensitive: a query like "l%" must not be read as a pattern.
local function matches(needle: string, first: any, second: any?): boolean
	if needle == "" then
		return true
	end
	return string.find(lower(first), needle, 1, true) ~= nil
		or (second ~= nil and string.find(lower(second), needle, 1, true) ~= nil)
end

function MusicLibraryModel.orderPlaylists(playlists: { [any]: any }, query: string?): { PlaylistEntry }
	local needle = lower(query)
	local ordered: { PlaylistEntry } = {}
	for key, playlist in pairs(playlists) do
		if type(playlist) == "table" and matches(needle, playlist.name) then
			table.insert(ordered, { id = tostring(playlist.id or key), playlist = playlist })
		end
	end
	table.sort(ordered, function(a, b)
		local aName, bName = lower(a.playlist.name), lower(b.playlist.name)
		if aName ~= bName then
			return aName < bName
		end
		return a.id < b.id
	end)
	return ordered
end

function MusicLibraryModel.filterTracks(tracks: { [any]: any }, query: string?, newestFirst: boolean?): { any }
	local needle = lower(query)
	local ordered = {}
	for key, track in pairs(tracks) do
		if type(track) == "table" and matches(needle, track.name, track.creator) then
			local entry = track
			if entry.id == nil then
				entry = table.clone(track)
				entry.id = tostring(key)
			end
			table.insert(ordered, entry)
		end
	end
	table.sort(ordered, function(a, b)
		if newestFirst then
			local aCreated, bCreated = tonumber(a.createdAt) or 0, tonumber(b.createdAt) or 0
			if aCreated ~= bCreated then
				return aCreated > bCreated
			end
		end
		local aName, bName = lower(a.name), lower(b.name)
		if aName ~= bName then
			return aName < bName
		end
		local aCreator, bCreator = lower(a.creator), lower(b.creator)
		if aCreator ~= bCreator then
			return aCreator < bCreator
		end
		return tostring(a.id) < tostring(b.id)
	end)
	return ordered
end

function MusicLibraryModel.deriveDjSets(tracks: { [any]: any }): { DjSet }
	local byName = MusicLibraryModel.filterTracks(tracks, nil, false)
	-- The set's display name is the first spelling by track id, so it never depends on pairs() order.
	local byTrackId = table.clone(byName)
	table.sort(byTrackId, function(a, b)
		return tostring(a.id) < tostring(b.id)
	end)

	local setsByKey: { [string]: DjSet } = {}
	local sets: { DjSet } = {}
	for _, track in ipairs(byTrackId) do
		local key = creatorKey(track.creator)
		if key ~= "" and not PLACEHOLDER_CREATORS[key] and setsByKey[key] == nil then
			local set: DjSet = { id = DJ_SET_PREFIX .. key, name = trim(track.creator), trackIds = {} }
			setsByKey[key] = set
			table.insert(sets, set)
		end
	end
	for _, track in ipairs(byName) do
		local set = setsByKey[creatorKey(track.creator)]
		if set then
			table.insert(set.trackIds, tostring(track.id))
		end
	end

	table.sort(sets, function(a, b)
		local aName, bName = string.lower(a.name), string.lower(b.name)
		if aName ~= bName then
			return aName < bName
		end
		return a.id < b.id
	end)
	return sets
end

function MusicLibraryModel.isDjSetId(id: any): boolean
	return type(id) == "string" and string.sub(id, 1, #DJ_SET_PREFIX) == DJ_SET_PREFIX
end

function MusicLibraryModel.tracksForDjSet(tracks: { [any]: any }, setId: string): { [any]: any }
	local subset = {}
	if not MusicLibraryModel.isDjSetId(setId) then
		return subset
	end
	local key = string.sub(setId, #DJ_SET_PREFIX + 1)
	if PLACEHOLDER_CREATORS[key] then
		return subset
	end
	for id, track in pairs(tracks) do
		if type(track) == "table" and creatorKey(track.creator) == key then
			subset[id] = track
		end
	end
	return subset
end

return MusicLibraryModel
