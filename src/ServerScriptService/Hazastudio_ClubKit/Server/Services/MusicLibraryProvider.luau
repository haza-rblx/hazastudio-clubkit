--!strict
-- PATH: ServerScriptService/Server/Services/MusicLibraryProvider.lua
-- Web music library (ADR 0010). The caller boots from the DataStore cache; this module then fetches
-- the library from the VPS and keeps polling it. Whether an answer replaces what is playing is
-- decided only by MusicWebLibraryPolicy, so a VPS outage or a licence 403 never empties the library.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local MusicDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.MusicDomain)
local MusicWebLibraryPolicy = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.MusicWebLibraryPolicy)

local LIBRARY_PATH = "/v3/music/library"
-- One warning per reason per minute: a VPS outage must not turn into a log line every poll.
local FAILURE_LOG_INTERVAL_SECONDS = 60

local MusicLibraryProvider = {}
MusicLibraryProvider.__index = MusicLibraryProvider

local function readSecret(): string
	local ok, secrets = pcall(function()
		return require(ServerScriptService.Hazastudio_ClubKitSecrets.Secrets) :: any
	end)
	if ok and type(secrets) == "table" and type(secrets.DonationApiSecret) == "string" then
		return secrets.DonationApiSecret
	end
	return ""
end

local function countEntries(map: { [any]: any }?): number
	local n = 0
	for _ in pairs(map or {}) do
		n += 1
	end
	return n
end

function MusicLibraryProvider.new(deps: {
	repo: any,
	logger: any,
	-- Receives the ids of tracks the new snapshot no longer has, so the caller can drop them
	-- from the queue (the repository replace cannot see the session).
	onLibraryApplied: (removedTrackIds: { [string]: true }) -> (),
	-- Id of the track on air, if any. The session advances the moment its current track is
	-- missing from the repository, so that one track must survive a snapshot that drops it.
	getPlayingTrackId: (() -> string?)?,
})
	return setmetatable({
		_repo = deps.repo,
		_log = deps.logger,
		_onLibraryApplied = deps.onLibraryApplied,
		_getPlayingTrackId = deps.getPlayingTrackId,
		_revision = nil :: string?,
		_failures = 0,
		_lastWarnAt = {} :: { [string]: number },
		_thread = nil :: thread?,
		_destroyed = false,
	}, MusicLibraryProvider)
end

function MusicLibraryProvider:_endpoint(): (string?, string?)
	local base = Config.Donation and Config.Donation.SHEETS_WEB_APP_URL
	local secret = readSecret()
	if type(base) ~= "string" or base == "" or secret == "" then
		return nil, nil
	end
	return (base:gsub("/+$", "")) .. LIBRARY_PATH, secret
end

-- Returns (statusCode, decodedBody). statusCode 0 = the request never got an HTTP answer.
function MusicLibraryProvider:_fetch(url: string, secret: string): (number, any?)
	if not HttpService.HttpEnabled then
		return 0, nil
	end
	local headers: { [string]: string } = {
		Authorization = "Bearer " .. secret,
		Accept = "application/json",
	}
	if self._revision then
		headers["If-None-Match"] = '"' .. self._revision .. '"'
	end
	local ok, response = pcall(function()
		return HttpService:RequestAsync({ Url = url, Method = "GET", Headers = headers })
	end)
	if not ok or type(response) ~= "table" then
		return 0, nil
	end
	local statusCode = tonumber(response.StatusCode) or 0
	local body = nil
	if type(response.Body) == "string" and response.Body ~= "" then
		local decodeOk, decoded = pcall(function()
			return HttpService:JSONDecode(response.Body)
		end)
		if decodeOk then
			body = decoded
		end
	end
	return statusCode, body
end

function MusicLibraryProvider:_warnThrottled(reason: string, fields: { [string]: any })
	local now = os.clock()
	local last = self._lastWarnAt[reason]
	if last and now - last < FAILURE_LOG_INTERVAL_SECONDS then
		return
	end
	self._lastWarnAt[reason] = now
	self._log:warn("Music web library kept the current library", fields)
end

-- One-time import of the in-game library (ADR 0010 import addendum). Returns true when the web now
-- holds it: imported by this call, or already imported by another server of the same game.
function MusicLibraryProvider:_importLibrary(url: string, secret: string): boolean
	-- Never send an unread cache: an empty import would mark the game imported with nothing in it,
	-- and the next snapshot would then erase the venue's library.
	if not self._repo:isLoaded() then
		local loadResult = self._repo:loadAll()
		if not loadResult.ok then
			self:_warnThrottled("import_cache_unreadable", { reason = "import_cache_unreadable", error = loadResult.error })
			return false
		end
	end

	local payload = self._repo:exportForWebImport()
	local encodeOk, encoded = pcall(function()
		return HttpService:JSONEncode(payload)
	end)
	if not encodeOk then
		self._log:error("Music web library import encode failed", { error = tostring(encoded) })
		return false
	end

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url .. "/import",
			Method = "POST",
			Headers = {
				Authorization = "Bearer " .. secret,
				Accept = "application/json",
				["Content-Type"] = "application/json",
			},
			Body = encoded,
		})
	end)
	if not ok or type(response) ~= "table" then
		self:_warnThrottled("import_unavailable", { reason = "import_unavailable", status = 0 })
		return false
	end

	local statusCode = tonumber(response.StatusCode) or 0
	local errorCode = nil
	if type(response.Body) == "string" and response.Body ~= "" then
		local decodeOk, decoded = pcall(function()
			return HttpService:JSONDecode(response.Body)
		end)
		if decodeOk and type(decoded) == "table" and type(decoded.error) == "string" then
			errorCode = decoded.error
		end
	end

	if statusCode == 200 then
		self._log:info("Music web library imported", {
			playlists = #payload.playlists,
			tracks = #payload.tracks,
		})
		return true
	end
	-- 409 is also "universe_unbound": only the import-specific answer counts as done.
	if statusCode == 409 and errorCode == "already_imported" then
		return true
	end
	self:_warnThrottled("import_rejected", {
		reason = "import_rejected",
		status = statusCode,
		error = errorCode,
	})
	return false
end

function MusicLibraryProvider:refresh(afterImport: boolean?): string
	local url, secret = self:_endpoint()
	if not url or not secret then
		self:_warnThrottled("not_configured", { reason = "not_configured" })
		self._failures += 1
		return "not_configured"
	end

	local tracksResult = self._repo:getTracks()
	local cachedTrackCount = if tracksResult.ok then countEntries(tracksResult.value) else 0
	local statusCode, body = self:_fetch(url, secret)
	local decision = MusicWebLibraryPolicy.interpret(
		{ statusCode = statusCode, body = body },
		{ currentRevision = self._revision, cachedTrackCount = cachedTrackCount },
		MusicDomain
	)

	if decision.action == "apply" then
		local removedTrackIds = {} :: { [string]: true }
		local newTracks = decision.tracks or {}
		-- Carry the song on air until it ends: dropping it here would cut it mid-play. The carried
		-- copy belongs to no playlist, so the library no longer lists it.
		local playingTrackId = if self._getPlayingTrackId then self._getPlayingTrackId() else nil
		local carriedTrackIds: { [string]: boolean }? = nil
		if playingTrackId and newTracks[playingTrackId] == nil and tracksResult.ok then
			local playing = tracksResult.value[playingTrackId]
			if playing then
				playing.playlistId = ""
				newTracks[playingTrackId] = playing
				-- Memory only: the cache mirrors the web library, and the web no longer has it.
				carriedTrackIds = { [playingTrackId] = true }
			end
		end
		if tracksResult.ok then
			for trackId in pairs(tracksResult.value) do
				if newTracks[trackId] == nil then
					removedTrackIds[trackId] = true
				end
			end
		end
		self._repo:applyWebSnapshot(decision.playlists, decision.tracks)
		self._revision = decision.revision
		self._failures = 0
		self._log:info("Music web library applied", {
			revision = decision.revision,
			playlists = countEntries(decision.playlists),
			tracks = countEntries(decision.tracks),
			dropped = decision.dropped,
		})
		self._onLibraryApplied(removedTrackIds)
		task.spawn(function()
			self._repo:writeWebCache(carriedTrackIds)
		end)
	elseif decision.action == "unchanged" then
		self._failures = 0
	elseif decision.action == "import" then
		-- Imported on the previous pass but the web still asks: stop here rather than loop.
		if afterImport then
			self._failures += 1
			self:_warnThrottled("import_not_acknowledged", { reason = "import_not_acknowledged", status = statusCode })
			return "keep"
		end
		if self:_importLibrary(url, secret) then
			self._revision = nil
			self._failures = 0
			return self:refresh(true)
		end
		self._failures += 1
	else
		-- An empty web library next to a playing cache is a waiting state (not yet imported),
		-- not a fault: keep the normal poll pace instead of backing off.
		if decision.reason ~= "web_empty_cache_present" then
			self._failures += 1
		end
		self:_warnThrottled(decision.reason, {
			reason = decision.reason,
			status = statusCode,
			failures = self._failures,
			cachedTracks = cachedTrackCount,
		})
	end
	return decision.action
end

function MusicLibraryProvider:start()
	if self._thread then
		return
	end
	self._thread = task.spawn(function()
		while not self._destroyed do
			local ok, err = pcall(function()
				self:refresh()
			end)
			if not ok then
				self._failures += 1
				self._log:error("Music web library refresh threw", { error = tostring(err) })
			end
			if self._destroyed then
				break
			end
			task.wait(MusicWebLibraryPolicy.nextPollSeconds(self._failures))
		end
	end)
end

function MusicLibraryProvider:destroy()
	self._destroyed = true
	if self._thread then
		pcall(task.cancel, self._thread)
		self._thread = nil
	end
end

return MusicLibraryProvider
