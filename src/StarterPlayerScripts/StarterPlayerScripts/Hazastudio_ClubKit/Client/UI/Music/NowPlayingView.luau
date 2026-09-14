--!strict
-- PATH: StarterPlayerScripts/Client/UI/Music/NowPlayingView.luau
-- Now Playing tab: hero (or DJ-on-stage while DJ mode is on), progress, Vote Skip, the queue and
-- the transport row. Transport and Clear Queue show for musicControl only; Remove shows on a
-- player's own requests, or on every row for musicControl.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MusicDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.MusicDomain)
local Cover = require(script.Parent.Parent.MusicPlayerCoverHelpers)
local GuiRefs = require(script.Parent.GuiRefs)
local MusicMotion = require(script.Parent.MusicMotion)
local Visuals = require(script.Parent.Visuals)

local PROGRESS_INTERVAL = 0.2
local ROW_STAGGER_SECONDS = 0.04
local AUTO_PLAYLIST_LABEL = "Auto Playlist"
local SEEK_STEP_SECONDS = 10
local CLEAR_CONFIRM_SECONDS = 3
local CLEAR_CONFIRM_TEXT = "Tap again to clear"

type QueueRow = {
	instance: TextButton,
	title: TextLabel,
	creator: TextLabel,
	length: TextLabel,
	requester: TextLabel,
	avatar: ImageLabel,
	coverHost: Frame,
	coverImage: ImageLabel,
	remove: ImageButton,
	entryId: string?,
	key: string?,
	fade: { GuiObject }?,
	fadeBases: { [GuiObject]: number }?,
}

local function findPlaylist(playlists: any, playlistId: any): any?
	if type(playlists) ~= "table" or type(playlistId) ~= "string" then
		return nil
	end
	local direct = playlists[playlistId]
	if type(direct) == "table" then
		return direct
	end
	for _, playlist in ipairs(playlists) do
		if type(playlist) == "table" and playlist.id == playlistId then
			return playlist
		end
	end
	return nil
end

local NowPlayingView = {}
NowPlayingView.__index = NowPlayingView

function NowPlayingView.new(deps: { refs: GuiRefs.Refs, store: any, config: any, fire: (string, ...any) -> () })
	local self = setmetatable({}, NowPlayingView) :: any
	self._refs = deps.refs.nowPlaying
	self._mainWrapper = deps.refs.mainWrapper
	self._template = deps.refs.queueRowTemplate
	self._store = deps.store
	self._config = deps.config
	self._fire = deps.fire
	self._rows = {} :: { QueueRow }
	self._track = nil :: any
	self._totalDuration = 0
	self._shownSecond = -1
	self._djKey = nil :: string?
	self._progressConn = nil :: RBXScriptConnection?
	self._connections = {} :: { RBXScriptConnection }
	self._unsubscribers = {} :: { () -> () }
	return self
end

function NowPlayingView:bind()
	local refs = self._refs
	Visuals.setText(refs.voteSkipLabel, "Vote Skip")
	table.insert(
		self._connections,
		refs.voteSkipButton.Activated:Connect(function()
			self._fire("OnVoteSkip", "skip")
		end)
	)
	self:_bindPress(refs.voteSkipButton)
	self._heroFade = { refs.trackTitle, refs.trackCreator, refs.cover, refs.requesterName, refs.playlistTitle }
	self._heroBases = MusicMotion.captureBases(self._heroFade)
	self._djFade = { refs.djAvatar, refs.djName }
	self._djBases = MusicMotion.captureBases(self._djFade)
	self:_bindTransport()
	-- Playlist names/covers arrive with the library; re-resolve what is already on screen.
	table.insert(
		self._unsubscribers,
		self._store:subscribe("playlists", function()
			self:updateTrack(self._track)
			self:renderQueue(self._store:get().queue or {}, true)
		end)
	)
	local state = self._store:get()
	self:setDjMode(state.isDjMode == true)
	self:updateTrack(state.currentTrack)
	self:renderQueue(state.queue or {})
end

-- ============================================================
-- Hero
-- ============================================================

function NowPlayingView:_bindPress(button: GuiObject)
	for _, connection in ipairs(MusicMotion.bindPress(button)) do
		table.insert(self._connections, connection)
	end
end

function NowPlayingView:updateTrack(track: any?)
	local refs = self._refs
	local previousKey = if self._track then tostring(self._track.queueEntryId or self._track.id) else nil
	self._track = if type(track) == "table" then track else nil
	local current = self._track
	local currentKey = if current then tostring(current.queueEntryId or current.id) else nil
	-- A new song glides in; re-syncs of the same song (playlists arriving, state echoes) do not.
	if currentKey ~= nil and currentKey ~= previousKey and self._heroBases then
		task.defer(function()
			MusicMotion.fadeIn(self._heroFade, self._heroBases)
		end)
	end
	if not current then
		Visuals.setText(refs.trackTitle, "No track playing")
		Visuals.setText(refs.trackCreator, "")
		Visuals.setText(refs.requesterName, "")
		Visuals.setText(refs.playlistTitle, "")
		Visuals.setText(refs.djNowPlaying, "")
		Visuals.setText(refs.djPlaylistTitle, "")
		Visuals.setVisible(refs.requesterAvatar, false)
		Visuals.applyCover(refs.cover, nil, self._config)
		Visuals.applyCover(refs.playlistCover, nil, self._config)
		self._totalDuration = 0
		self:_renderProgress(true)
		return
	end

	local state = self._store:get()
	local playlist = current.playlist or findPlaylist(state.playlists, current.playlistId)
	local playlistName = if type(playlist) == "table" then tostring(playlist.name or "") else ""
	Visuals.setText(refs.trackTitle, tostring(current.name or ""))
	Visuals.setText(refs.trackCreator, tostring(current.creator or ""))
	Visuals.setText(refs.playlistTitle, playlistName)
	Visuals.setText(refs.djPlaylistTitle, playlistName)

	if current.isSystemAssigned == true then
		Visuals.setText(refs.requesterName, AUTO_PLAYLIST_LABEL)
		Visuals.setVisible(refs.requesterAvatar, false)
	else
		local requesterName = tostring(current.requesterDisplayName or "")
		local entry = state.currentEntry
		if requesterName == "" and type(entry) == "table" and entry.source == "user" then
			requesterName = tostring(entry.requesterDisplayName or "")
		end
		Visuals.setText(refs.requesterName, requesterName)
		Visuals.setVisible(refs.requesterAvatar, true)
		Visuals.setHeadshot(refs.requesterAvatar, tonumber(current.requesterUserId))
	end

	Visuals.applyCover(refs.cover, Cover.resolveCoverSourceForTrack(current, playlist), self._config)
	Visuals.applyCover(refs.playlistCover, playlist, self._config)
	self._totalDuration = tonumber(current.totalDuration) or 0
	self:_renderProgress(true)
end

function NowPlayingView:setDjMode(enabled: boolean)
	local refs = self._refs
	local ownerId = self._store:get().djOwnerUserId
	local key = if enabled then "dj:" .. tostring(ownerId) else "off"
	if self._djKey == key then
		return
	end
	self._djKey = key
	Visuals.setVisible(refs.hero, not enabled)
	Visuals.setVisible(refs.djStage, enabled)
	if not enabled then
		if self._heroBases then
			MusicMotion.fadeIn(self._heroFade, self._heroBases)
		end
		return
	end
	if self._djBases then
		MusicMotion.fadeIn(self._djFade, self._djBases)
		MusicMotion.popIn(refs.djAvatar, 0.7)
	end
	local owner = if type(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
	local djName = if owner then owner.DisplayName else "The DJ"
	Visuals.setText(refs.djName, djName)
	Visuals.setText(refs.djControlledLabel, string.format("This set is currently controlled by %s", djName))
	Visuals.setHeadshot(refs.djAvatar, if type(ownerId) == "number" then ownerId else nil, Enum.ThumbnailSize.Size420x420)
end

-- ============================================================
-- Transport row + Clear Queue
-- ============================================================

function NowPlayingView:_bindTransport()
	local refs = self._refs
	local rewind, previous, playPause, nextButton, seek = table.unpack(refs.transportButtons)
	local connect = function(button: GuiButton, handler: () -> ())
		table.insert(self._connections, button.Activated:Connect(handler))
	end

	-- The design ships one icon. A "PauseImage" attribute on the icon (and optionally
	-- "PlayImage") lets the button show pause while playing.
	local icon = GuiRefs.need(playPause, "ImageLabel", "ImageLabel") :: ImageLabel
	self._playPauseIcon = icon
	self._playImage = tostring(icon:GetAttribute("PlayImage") or icon.Image)
	local pauseImage = icon:GetAttribute("PauseImage")
	self._pauseImage = if type(pauseImage) == "string" and pauseImage ~= "" then pauseImage else nil

	local iconOf = function(button: GuiButton): GuiObject?
		return button:FindFirstChildWhichIsA("ImageLabel")
	end
	connect(rewind, function()
		MusicMotion.spin(iconOf(rewind), -1)
		self._fire("OnTransport", "seek", { delta = -SEEK_STEP_SECONDS })
	end)
	connect(seek, function()
		MusicMotion.spin(iconOf(seek), 1)
		self._fire("OnTransport", "seek", { delta = SEEK_STEP_SECONDS })
	end)
	connect(previous, function()
		MusicMotion.wiggle(iconOf(previous), 14)
		self._fire("OnTransport", "previous")
	end)
	connect(nextButton, function()
		MusicMotion.wiggle(iconOf(nextButton), 14)
		self._fire("OnAdminSkip")
	end)
	connect(playPause, function()
		self._fire("OnTransport", if self:_isPaused() then "resume" else "pause")
	end)
	for _, button in ipairs(refs.transportButtons) do
		self:_bindPress(button)
	end
	self:_bindPress(refs.clearQueueButton)

	-- No modal in v3: the first press arms, a second press within 3 s clears.
	local clearLabel = GuiRefs.need(refs.clearQueueButton, "TextLabel", "TextLabel") :: TextLabel
	local clearText = clearLabel.Text
	self._clearToken = 0
	connect(refs.clearQueueButton, function()
		self._clearToken += 1
		if self._clearArmed then
			self._clearArmed = false
			Visuals.setText(clearLabel, clearText)
			self._fire("OnTransport", "clear")
			return
		end
		self._clearArmed = true
		Visuals.setText(clearLabel, CLEAR_CONFIRM_TEXT)
		MusicMotion.wiggle(refs.clearQueueButton, 3)
		local token = self._clearToken
		task.delay(CLEAR_CONFIRM_SECONDS, function()
			if token == self._clearToken and self._clearArmed then
				self._clearArmed = false
				Visuals.setText(clearLabel, clearText)
			end
		end)
	end)

	table.insert(
		self._unsubscribers,
		self._store:subscribe("playbackTiming", function()
			self:_paintPlayPause()
		end)
	)
	self._transportAllowed = nil :: boolean?
	self:setTransportAllowed(false)
	self:_paintPlayPause()
end

function NowPlayingView:_isPaused(): boolean
	local timing = self._store:get().playbackTiming
	return type(timing) == "table" and timing.isPaused == true
end

function NowPlayingView:_paintPlayPause()
	local icon = self._playPauseIcon
	if not icon then
		return
	end
	local image = if self:_isPaused() or not self._pauseImage then self._playImage else self._pauseImage
	if icon.Image ~= image then
		icon.Image = image
		MusicMotion.popIn(icon, 0.55)
	end
end

function NowPlayingView:setTransportAllowed(allowed: boolean)
	if self._transportAllowed == allowed then
		return
	end
	self._transportAllowed = allowed
	for _, button in ipairs(self._refs.transportButtons) do
		Visuals.setVisible(button, allowed)
	end
	Visuals.setVisible(self._refs.clearQueueButton, allowed)
	-- Remove visibility depends on it.
	self:renderQueue(self._store:get().queue or {}, true)
end

function NowPlayingView:setVoteSkipVisible(visible: boolean)
	Visuals.setVisible(self._refs.voteSkipButton, visible)
end

function NowPlayingView:setVoteCounts(skipVotes: number?, totalVotes: number?)
	local text = if skipVotes == nil
		then "Vote Skip"
		else string.format("Vote Skip (%d/%d)", skipVotes, totalVotes or 0)
	Visuals.setText(self._refs.voteSkipLabel, text)
end

-- ============================================================
-- Progress
-- ============================================================

function NowPlayingView:setTotalDuration(duration: number)
	self._totalDuration = tonumber(duration) or 0
end

function NowPlayingView:_progressSeconds(): (number, number)
	local state = self._store:get()
	local now = Workspace:GetServerTimeNow()
	local timing = state.playbackTiming
	if type(timing) == "table" then
		local total = MusicDomain.getTimingTotalSeconds(timing)
		local elapsed = if state.isPlaying then MusicDomain.getTimingElapsedSeconds(timing, now) else 0
		return math.min(elapsed, total), total
	end
	local startAt = tonumber(state.startServerTime) or 0
	local endAt = tonumber(state.expectedEndServerTime) or 0
	local total = if startAt > 0 and endAt > startAt then endAt - startAt else math.max(0, self._totalDuration)
	local elapsed = if state.isPlaying then math.max(0, now - startAt) else 0
	return math.min(elapsed, total), total
end

function NowPlayingView:_renderProgress(force: boolean)
	local refs = self._refs
	local elapsed, total = self:_progressSeconds()
	local progress = if total > 0 then math.clamp(elapsed / total, 0, 1) else 0
	if self._progressShown ~= progress then
		-- Glide forward between 5 Hz samples; jumps (new track, seek back, pause) snap.
		local glide = not force and self._progressShown ~= nil and progress > self._progressShown
		self._progressShown = progress
		MusicMotion.tween(
			refs.progressFill,
			if glide then PROGRESS_INTERVAL else 0,
			{ Size = UDim2.new(progress, 0, 1, 0) },
			Enum.EasingStyle.Linear
		)
	end
	-- Text only when the displayed second changes; the bar is a single property.
	local second = math.floor(elapsed)
	if not force and second == self._shownSecond then
		return
	end
	self._shownSecond = second
	local elapsedText = Visuals.formatClock(second)
	local totalText = Visuals.formatClock(total)
	Visuals.setText(refs.elapsedLabel, elapsedText)
	Visuals.setText(refs.lengthLabel, totalText)
	if self._track then
		Visuals.setText(
			refs.djNowPlaying,
			string.format("%s (%s/%s)", tostring(self._track.name or ""), elapsedText, totalText)
		)
	end
end

function NowPlayingView:refreshProgress()
	self:_renderProgress(true)
end

function NowPlayingView:startProgress()
	self:stopProgress()
	local accum = 0
	self._progressConn = RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < PROGRESS_INTERVAL then
			return
		end
		accum = 0
		-- Closed panel = nothing to draw; openPanel refreshes once on the way in.
		if not self._mainWrapper.Visible or not self._store:get().isPlaying then
			return
		end
		self:_renderProgress(false)
	end)
end

function NowPlayingView:stopProgress()
	if self._progressConn then
		self._progressConn:Disconnect()
		self._progressConn = nil
	end
end

-- ============================================================
-- Queue
-- ============================================================

function NowPlayingView:_row(index: number): QueueRow
	local existing = self._rows[index]
	if existing then
		return existing
	end
	local instance = self._template:Clone() :: TextButton
	local info = GuiRefs.need(instance, "TrackInformationSection", "Frame")
	local trackInfo = GuiRefs.need(info, "TrackInfo", "Frame")
	local coverHost = GuiRefs.need(GuiRefs.need(instance, "Wrapper", "Frame"), "RelatedPlaylistCover", "Frame")
	local remove = GuiRefs.need(info, "RemovefromQueueButton", "ImageButton")
	local row: QueueRow = {
		instance = instance,
		title = GuiRefs.need(trackInfo, "TrackTitle", "TextLabel"),
		creator = GuiRefs.need(trackInfo, "TrackCreator", "TextLabel"),
		length = GuiRefs.need(trackInfo, "TrackLength", "TextLabel"),
		requester = GuiRefs.need(GuiRefs.need(info, "RequesterWrapper", "Frame"), "RequesterDisplayName", "TextLabel"),
		avatar = GuiRefs.need(info, "RequesterProfilePicture", "ImageLabel"),
		coverHost = coverHost,
		coverImage = GuiRefs.need(coverHost, "ImageLabel", "ImageLabel"),
		remove = remove,
		entryId = nil,
		key = nil,
	}
	table.insert(
		self._connections,
		remove.Activated:Connect(function()
			if row.entryId then
				MusicMotion.wiggle(remove:FindFirstChildWhichIsA("ImageLabel"), 16)
				self._fire("OnTransport", "remove", { entryId = row.entryId })
			end
		end)
	)
	self:_bindPress(remove)
	row.fade = { row.title, row.creator, row.length, row.requester, row.coverImage }
	row.fadeBases = MusicMotion.captureBases(row.fade)
	instance.Parent = self._template.Parent
	self._rows[index] = row
	return row
end

function NowPlayingView:_bindRow(row: QueueRow, track: any, playlist: any?)
	Visuals.setText(row.title, tostring(track.name or ""))
	Visuals.setText(row.creator, tostring(track.creator or ""))
	Visuals.setText(row.length, Visuals.formatClock(tonumber(track.totalDuration) or 0))
	if track.isSystemAssigned == true then
		Visuals.setText(row.requester, "Queued by : " .. AUTO_PLAYLIST_LABEL)
		Visuals.setVisible(row.avatar, false)
	else
		Visuals.setText(row.requester, "Queued by : " .. tostring(track.requesterDisplayName or "Unknown"))
		Visuals.setVisible(row.avatar, true)
		Visuals.setHeadshot(row.avatar, tonumber(track.requesterUserId))
	end
	Visuals.applyCover(
		row.coverImage,
		Cover.resolveCoverSourceForTrack(track, playlist),
		self._config,
		{ gradientHost = row.coverHost, listThumb = true }
	)
	row.entryId = if type(track.queueEntryId) == "string" then track.queueEntryId else nil
	local localPlayer = Players.LocalPlayer
	local ownRequest = track.isSystemAssigned ~= true
		and localPlayer ~= nil
		and tonumber(track.requesterUserId) == localPlayer.UserId
	Visuals.setVisible(row.remove, row.entryId ~= nil and (self._transportAllowed == true or ownRequest))
	row.instance.Name = tostring(track.queueEntryId or track.id or "QueueRow")
end

-- Rows are pooled by position and rebound only when the entry in that slot changes.
function NowPlayingView:renderQueue(queue: { any }, force: boolean?)
	local playlists = self._store:get().playlists
	local count = 0
	local entering = 0
	for _, track in ipairs(queue) do
		if type(track) ~= "table" then
			continue
		end
		count += 1
		local row = self:_row(count)
		local key = string.format("%s|%s", tostring(track.queueEntryId or track.id), tostring(track.requesterUserId))
		if force or row.key ~= key then
			-- A slot that now holds a different entry fades in; forced re-resolves do not.
			if not force and row.fade and row.fadeBases then
				MusicMotion.fadeIn(row.fade, row.fadeBases, ROW_STAGGER_SECONDS * math.min(entering, 8))
				entering += 1
			end
			row.key = key
			self:_bindRow(row, track, findPlaylist(playlists, track.playlistId))
		end
		if row.instance.LayoutOrder ~= count then
			row.instance.LayoutOrder = count
		end
		Visuals.setVisible(row.instance, true)
	end
	for index = count + 1, #self._rows do
		local row = self._rows[index]
		row.key = nil
		Visuals.setVisible(row.instance, false)
	end
end

function NowPlayingView:destroy()
	self:stopProgress()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	for _, unsubscribe in ipairs(self._unsubscribers) do
		unsubscribe()
	end
	for _, row in ipairs(self._rows) do
		row.instance:Destroy()
	end
	table.clear(self._connections)
	table.clear(self._unsubscribers)
	table.clear(self._rows)
end

return NowPlayingView
