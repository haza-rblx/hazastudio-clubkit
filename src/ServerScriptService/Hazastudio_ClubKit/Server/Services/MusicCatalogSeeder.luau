--!strict
-- PATH: ServerScriptService/.../Server/Services/MusicCatalogSeeder.luau
-- Additive merge of buyer MusicCatalog ModuleScript → MusicRepository (DataStore).
-- Does not overwrite existing tracks (Manage edits stick). Skips tombstoned fingerprints.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local MusicDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.MusicDomain)

type TrackInfo = MusicDomain.TrackInfo
type PlaylistInfo = MusicDomain.PlaylistInfo

export type SeedSummary = {
	added: number,
	skipped: number,
	errors: number,
	playlistsCreated: number,
	skippedReason: string?,
}

local MusicCatalogSeeder = {}

local function trim(value: string): string
	return (string.gsub(value, "^%s*(.-)%s*$", "%1"))
end

local function normalizeAssetId(raw: any): string?
	if type(raw) == "number" then
		if raw ~= raw or raw <= 0 or raw ~= math.floor(raw) then
			return nil
		end
		return tostring(math.floor(raw))
	end
	if type(raw) ~= "string" then
		return nil
	end
	local s = trim(raw)
	if s == "" then
		return nil
	end
	local digits = string.match(s, "(%d+)$")
	if not digits or digits == "" or digits == "0" then
		return nil
	end
	return digits
end

local function collectParts(source: { [string]: any }, maxParts: number): ({ string }, boolean)
	local parts: { string } = {}
	local truncated = false

	local function push(raw: any)
		if #parts >= maxParts then
			truncated = true
			return
		end
		local id = normalizeAssetId(raw)
		if id then
			table.insert(parts, id)
		end
	end

	local list = source.parts or source.assetIds or source.audioIds or source.audios
	if type(list) == "table" then
		for _, item in ipairs(list) do
			push(item)
		end
	end

	if #parts == 0 then
		for i = 1, maxParts do
			local keyA = "part" .. tostring(i)
			local keyB = "assetId" .. tostring(i)
			local keyC = "audioId" .. tostring(i)
			if source[keyA] ~= nil then
				push(source[keyA])
			elseif source[keyB] ~= nil then
				push(source[keyB])
			elseif source[keyC] ~= nil then
				push(source[keyC])
			end
		end
	end

	return parts, truncated
end

local function parsePlaybackSpeed(raw: any): number?
	if type(raw) == "number" and raw > 0 then
		return raw
	end
	if type(raw) == "string" then
		local cleaned = string.gsub(trim(raw), "[xX]%s*$", "")
		local n = tonumber(cleaned)
		if n and n > 0 then
			return n
		end
	end
	return nil
end

local function fingerprint(name: string, creator: string, parts: { string }): string
	return string.lower(name) .. "|" .. string.lower(creator) .. "|" .. table.concat(parts, ",")
end

local function loadCatalogModule(): ({ [string]: any }?, string?)
	local folder = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKitConfig")
	if not folder then
		return nil, "missing_config_folder"
	end
	local mod = folder:FindFirstChild("MusicCatalog")
	if not mod or not mod:IsA("ModuleScript") then
		return nil, "missing_module"
	end
	local ok, result = pcall(require, mod)
	if not ok then
		return nil, "require_failed:" .. tostring(result)
	end
	if type(result) ~= "table" then
		return nil, "invalid_module_return"
	end
	return result :: { [string]: any }, nil
end

local function indexPlaylistsByName(playlists: { [string]: PlaylistInfo }): { [string]: string }
	local byName: { [string]: string } = {}
	for id, playlist in pairs(playlists) do
		if type(playlist.name) == "string" and playlist.name ~= "" then
			byName[string.lower(playlist.name)] = id
		end
	end
	return byName
end

local function buildFingerprintSet(
	tracks: { [string]: TrackInfo },
	tombstones: { [string]: TrackInfo }
): { [string]: true }
	local seen: { [string]: true } = {}
	local function ingest(track: TrackInfo)
		if type(track.name) ~= "string" or type(track.creator) ~= "string" then
			return
		end
		local parts = track.parts
		if type(parts) ~= "table" or #parts < 1 then
			return
		end
		local normalized: { string } = {}
		for _, part in ipairs(parts) do
			local id = normalizeAssetId(part)
			if id then
				table.insert(normalized, id)
			end
		end
		if #normalized < 1 then
			return
		end
		seen[fingerprint(track.name, track.creator, normalized)] = true
	end
	for _, track in pairs(tracks) do
		ingest(track)
	end
	for _, track in pairs(tombstones) do
		ingest(track)
	end
	return seen
end

function MusicCatalogSeeder.merge(deps: {
	repo: any,
	config: any?,
	logger: any?,
	featureFlags: any?,
}): SeedSummary
	local summary: SeedSummary = {
		added = 0,
		skipped = 0,
		errors = 0,
		playlistsCreated = 0,
		skippedReason = nil,
	}

	local log = deps.logger
	local musicConfig = deps.config or Config.Music
	local featureFlags = deps.featureFlags or Config.FeatureFlags
	local repo = deps.repo

	local function info(msg: string, ctx: { [string]: any }?)
		if log and type(log.info) == "function" then
			log:info(msg, ctx)
		end
	end
	local function warn(msg: string, ctx: { [string]: any }?)
		if log and type(log.warn) == "function" then
			log:warn(msg, ctx)
		end
	end

	if featureFlags and featureFlags.MusicCatalogSeedEnabled == false then
		summary.skippedReason = "feature_disabled"
		info("MusicCatalogSeed skipped (ClubKitConfig.Features.MusicCatalogSeed=false)")
		return summary
	end

	local catalog, loadErr = loadCatalogModule()
	if not catalog then
		summary.skippedReason = loadErr or "missing_module"
		if loadErr == "missing_module" or loadErr == "missing_config_folder" then
			info("MusicCatalogSeed skipped (no MusicCatalog module)")
		else
			warn("MusicCatalogSeed skipped", { reason = loadErr })
		end
		return summary
	end

	if catalog.enabled == false then
		summary.skippedReason = "catalog_disabled"
		info("MusicCatalogSeed skipped (MusicCatalog.enabled=false)")
		return summary
	end

	local tracksSource = catalog.tracks
	if type(tracksSource) ~= "table" then
		summary.skippedReason = "no_tracks"
		info("MusicCatalogSeed skipped (tracks not an array)")
		return summary
	end

	local playlistsResult = repo:getPlaylists()
	local tracksResult = repo:getTracks()
	if not playlistsResult.ok or not tracksResult.ok then
		summary.skippedReason = "library_unavailable"
		warn("MusicCatalogSeed aborted: library unavailable")
		return summary
	end

	local existingPlaylists: { [string]: PlaylistInfo } = playlistsResult.value
	local existingTracks: { [string]: TrackInfo } = tracksResult.value
	local tombstones: { [string]: TrackInfo } = {}
	if type(repo.getTrackTombstones) == "function" then
		tombstones = repo:getTrackTombstones()
	end

	local byName = indexPlaylistsByName(existingPlaylists)
	local seen = buildFingerprintSet(existingTracks, tombstones)

	local maxParts = tonumber(musicConfig.MAX_TRACK_PARTS) or 9
	local defaultPlaylistName = tostring(musicConfig.CATALOG_DEFAULT_PLAYLIST_NAME or "Legacy")
	local syncSource = tostring(musicConfig.CATALOG_SYNC_SOURCE or "music-catalog-seeder")

	local newPlaylists: { PlaylistInfo } = {}
	local newTracks: { TrackInfo } = {}
	local appendToExisting: { [string]: { string } } = {}
	-- Playlists created in this pass (id → mutable trackIds list used before bulkSeed)
	local pendingPlaylists: { [string]: PlaylistInfo } = {}

	local function ensurePlaylist(name: string): string?
		local key = string.lower(name)
		local existingId = byName[key]
		if existingId then
			return existingId
		end
		for id, pending in pairs(pendingPlaylists) do
			if string.lower(pending.name) == key then
				return id
			end
		end
		local id = HttpService:GenerateGUID(false)
		local playlist = MusicDomain.buildPlaylist({
			id = id,
			name = name,
			visibility = "public",
			trackIds = {},
		})
		pendingPlaylists[id] = playlist
		table.insert(newPlaylists, playlist)
		byName[key] = id
		summary.playlistsCreated += 1
		return id
	end

	-- Ensure optional catalog.playlists exist first
	local catalogPlaylists = catalog.playlists
	if type(catalogPlaylists) == "table" then
		for _, entry in ipairs(catalogPlaylists) do
			if type(entry) == "table" and type(entry.name) == "string" and trim(entry.name) ~= "" then
				ensurePlaylist(trim(entry.name))
			end
		end
	end

	for index, raw in ipairs(tracksSource) do
		if type(raw) ~= "table" then
			summary.errors += 1
			warn("MusicCatalogSeed track skipped (not a table)", { index = index })
			continue
		end

		local name = if type(raw.name) == "string" then trim(raw.name) else ""
		local creatorRaw = raw.creator or raw.artist or raw.author or "Unknown"
		local creator = trim(tostring(creatorRaw))
		if name == "" or creator == "" then
			summary.errors += 1
			warn("MusicCatalogSeed track skipped (name/creator)", { index = index })
			continue
		end

		local parts, truncated = collectParts(raw, maxParts)
		if truncated then
			warn("MusicCatalogSeed truncated parts", { index = index, name = name, max = maxParts })
		end
		if #parts < 1 then
			summary.errors += 1
			warn("MusicCatalogSeed track skipped (no valid parts)", { index = index, name = name })
			continue
		end

		local fp = fingerprint(name, creator, parts)
		if seen[fp] then
			summary.skipped += 1
			continue
		end

		local playlistId: string? = nil
		if type(raw.playlistId) == "string" and trim(raw.playlistId) ~= "" then
			local wantId = trim(raw.playlistId)
			if existingPlaylists[wantId] or pendingPlaylists[wantId] then
				playlistId = wantId
			else
				summary.errors += 1
				warn("MusicCatalogSeed track skipped (playlistId not found)", {
					index = index,
					name = name,
					playlistId = wantId,
				})
				continue
			end
		elseif type(raw.playlistName) == "string" and trim(raw.playlistName) ~= "" then
			playlistId = ensurePlaylist(trim(raw.playlistName))
			if not playlistId then
				summary.errors += 1
				continue
			end
		else
			playlistId = ensurePlaylist(defaultPlaylistName)
			if not playlistId then
				summary.errors += 1
				warn("MusicCatalogSeed failed to ensure default playlist", { name = defaultPlaylistName })
				continue
			end
		end

		local trackId = HttpService:GenerateGUID(false)
		local now = os.time()
		local speed = parsePlaybackSpeed(raw.playbackSpeed)
			or parsePlaybackSpeed(raw.normalPlaybackSpeed)
			or parsePlaybackSpeed(raw.speed)

		local track = MusicDomain.buildTrack({
			id = trackId,
			name = name,
			creator = creator,
			playlistId = playlistId,
			parts = parts,
			totalDuration = 0,
			playbackSpeed = speed,
			createdAt = now,
			updatedAt = now,
			syncSource = syncSource,
		})

		local okValidate, validateErr = MusicDomain.validateTrack(track)
		if not okValidate then
			summary.errors += 1
			warn("MusicCatalogSeed track invalid", { index = index, name = name, error = validateErr })
			continue
		end

		table.insert(newTracks, track)
		seen[fp] = true

		local pending = pendingPlaylists[playlistId]
		if pending then
			table.insert(pending.trackIds, trackId)
		else
			local bucket = appendToExisting[playlistId]
			if not bucket then
				bucket = {}
				appendToExisting[playlistId] = bucket
			end
			table.insert(bucket, trackId)
		end

		summary.added += 1
	end

	if #newPlaylists == 0 and #newTracks == 0 and next(appendToExisting) == nil then
		info("MusicCatalogSeed complete (nothing new)", {
			skipped = summary.skipped,
			errors = summary.errors,
		})
		return summary
	end

	local seedResult = repo:bulkSeed({
		newPlaylists = newPlaylists,
		newTracks = newTracks,
		appendToExistingPlaylists = appendToExisting,
		syncSource = syncSource,
	})
	if not seedResult.ok then
		summary.errors += 1
		summary.added = 0
		summary.playlistsCreated = 0
		warn("MusicCatalogSeed bulkSeed failed", { error = seedResult.error })
		return summary
	end

	info("MusicCatalogSeed complete", {
		added = summary.added,
		skipped = summary.skipped,
		errors = summary.errors,
		playlistsCreated = summary.playlistsCreated,
	})
	return summary
end

return MusicCatalogSeeder
