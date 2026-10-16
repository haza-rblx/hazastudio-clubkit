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
local GuiRefs = require(script.Parent.GuiRefs)
local UIMotion = require(script.Parent.Parent.Parent.Utils.UIMotion)
local SmoothScrollHelper = require(script.Parent.Parent.Parent.Utils.SmoothScrollHelper)
local Visuals = require(script.Parent.Visuals)
local ListPool = require(script.Parent.ListPool)
local SetCardView = require(script.Parent.SetCardView)
local SetBanner = require(script.Parent.SetBanner)

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
	info: Frame,
	wrapper: Frame,
	coverHost: Frame,
	coverImage: ImageLabel,
	-- The set banner a waiting set card wears (built lazily, hidden for track rows).
	banner: any?,
	remove: ImageButton,
	entryId: string?,
	fade: { GuiObject }?,
	fadeBases: { [GuiObject]: number }?,
	avatarPosition: UDim2?,
	avatarEndPosition: UDim2?,
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

-- Identity of a queue entry: the same entry keeps its row when the queue shifts.
local function queueKey(track: any): string
	return string.format("%s|%s", tostring(track.queueEntryId or track.id), tostring(track.requesterUserId))
end

local NowPlayingView = {}
NowPlayingView.__index = NowPlayingView

function NowPlayingView.new(deps: { refs: GuiRefs.Refs, store: any, config: any, fire: (string, ...any) -> (), setSheet: any? })
	local self = setmetatable({}, NowPlayingView) :: any
	self._refs = deps.refs.nowPlaying
	self._mainWrapper = deps.refs.mainWrapper
	self._template = deps.refs.queueRowTemplate
	self._store = deps.store
	self._config = deps.config
	self._fire = deps.fire
	self._queueKeys = {} :: { [string]: boolean }
	self._prevKeys = {} :: { [string]: boolean }
	self._bindEpoch = 0
	self._renderForce = false
	self._entering = 0
	self._playlists = nil :: any
	self._track = nil :: any
	self._totalDuration = 0
	self._shownSecond = -1
	self._djKey = nil :: string?
	self._progressConn = nil :: RBXScriptConnection?
	self._connections = {} :: { RBXScriptConnection }
	self._unsubscribers = {} :: { () -> () }
	self._scrollHandles = {} :: { { destroy: () -> () } }
	-- The queue rows are children of the queue ScrollingFrame (the template's parent).
	local queueScroll = self._template.Parent :: ScrollingFrame
	-- The Set card sits above the rows; ListPool keeps it out of the index math (`leading`).
	self._setCard = SetCardView.new({
		scroll = queueScroll,
		refs = deps.refs,
		store = deps.store,
		config = deps.config,
		fire = self._fire,
		onViewAll = function()
			if deps.setSheet then
				deps.setSheet:open()
			end
		end,
	})
	self._pool = ListPool.new({
		scroll = queueScroll,
		container = queueScroll,
		template = self._template,
		leading = self._setCard.frame,
		keyOf = function(track: any): string
			return string.format("%d#%s", self._bindEpoch, queueKey(track))
		end,
		createRow = function(instance: GuiObject): any
			return self:_createQueueRow(instance)
		end,
		bindRow = function(row: any, track: any)
			self:_bindQueueRow(row, track)
		end,
	})
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
	self:_bindMotion(refs.voteSkipButton)
	self._heroFade = { refs.trackTitle, refs.trackCreator, refs.cover, refs.requesterName, refs.playlistTitle }
	self._heroBases = UIMotion.captureBases(self._heroFade)
	self._djFade = { refs.djAvatar, refs.djName }
	self._djBases = UIMotion.captureBases(self._djFade)
	self:_bindTransport()
	table.insert(self._scrollHandles, SmoothScrollHelper.attach(self._template.Parent :: ScrollingFrame))
	-- Playlist names/covers arrive with the library; re-resolve what is already on screen.
	table.insert(
		self._unsubscribers,
		self._store:subscribe("playlists", function()
			self:updateTrack(self._track)
			self:renderQueue(self._store:get().queue or {}, true)
		end)
	)
	table.insert(
		self._unsubscribers,
		self._store:subscribe("activeSet", function(set: any)
			self._setCard:update(set)
		end)
	)
	local state = self._store:get()
	self:setDjMode(state.isDjMode == true)
	self:updateTrack(state.currentTrack)
	self._setCard:update(state.activeSet)
	self:renderQueue(state.queue or {})
end

-- ============================================================
-- Hero
-- ============================================================

-- Press squash + hover lift, the pairing every other kit panel uses (ADR 0011). Queue rows call
-- this from _row, which builds each pooled slot once, so a rebind cannot stack connections.
function NowPlayingView:_bindMotion(button: GuiObject)
	for _, connection in ipairs(UIMotion.bindPress(button)) do
		table.insert(self._connections, connection)
	end
	for _, connection in ipairs(UIMotion.bindHover(button)) do
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
			UIMotion.fadeIn(self._heroFade, self._heroBases)
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

	Visuals.applyTrackCover(refs.cover, current, playlist, self._config)
	Visuals.applyCover(refs.playlistCover, playlist, self._config)
	self._totalDuration = tonumber(current.totalDuration) or 0
	self:_renderProgress(true)
end

function NowPlayingView:setDjMode(enabled: boolean)
	local refs = self._refs
	local state = self._store:get()
	local ownerId = state.djOwnerUserId
	-- The stage is the audience view. The DJ and anyone with control (admins) keep the normal hero
	-- with the transport row, or they could not skip/seek during their own set.
	local localPlayer = Players.LocalPlayer
	local canControl = state.isControlAllowed == true
		or (type(ownerId) == "number" and localPlayer ~= nil and ownerId == localPlayer.UserId)
	enabled = enabled and not canControl
	local key = if enabled then "dj:" .. tostring(ownerId) else "off"
	if self._djKey == key then
		return
	end
	self._djKey = key
	Visuals.setVisible(refs.hero, not enabled)
	Visuals.setVisible(refs.djStage, enabled)
	if not enabled then
		if self._heroBases then
			UIMotion.fadeIn(self._heroFade, self._heroBases)
		end
		return
	end
	if self._djBases then
		UIMotion.fadeIn(self._djFade, self._djBases)
		UIMotion.popIn(refs.djAvatar, 0.7)
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

	-- Resolved before the binds below: the icon tier may move an icon into its UIMotionIconSlot,
	-- where a direct lookup at press time no longer finds it.
	local iconOf = function(button: GuiButton): GuiObject?
		return button:FindFirstChildWhichIsA("ImageLabel")
	end
	local rewindIcon, seekIcon = iconOf(rewind), iconOf(seek)
	local previousIcon, nextIcon = iconOf(previous), iconOf(nextButton)
	connect(rewind, function()
		UIMotion.spin(rewindIcon, -1)
		self._fire("OnTransport", "seek", { delta = -SEEK_STEP_SECONDS })
	end)
	connect(seek, function()
		UIMotion.spin(seekIcon, 1)
		self._fire("OnTransport", "seek", { delta = SEEK_STEP_SECONDS })
	end)
	connect(previous, function()
		UIMotion.wiggle(previousIcon, 14)
		self._fire("OnTransport", "previous")
	end)
	connect(nextButton, function()
		UIMotion.wiggle(nextIcon, 14)
		self._fire("OnAdminSkip")
	end)
	connect(playPause, function()
		self._fire("OnTransport", if self:_isPaused() then "resume" else "pause")
	end)
	for _, button in ipairs(refs.transportButtons) do
		self:_bindMotion(button)
	end
	self:_bindMotion(refs.clearQueueButton)

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
		UIMotion.wiggle(refs.clearQueueButton, 3)
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
		UIMotion.popIn(icon, 0.55)
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
	self._setCard:setControl(allowed)
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
		UIMotion.tween(
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

-- Called by ListPool once per pooled instance (already parented, hidden).
function NowPlayingView:_createQueueRow(instance: GuiObject): QueueRow
	local button = instance :: TextButton
	local info = GuiRefs.need(instance, "TrackInformationSection", "Frame")
	local trackInfo = GuiRefs.need(info, "TrackInfo", "Frame")
	local coverHost = GuiRefs.need(GuiRefs.need(instance, "Wrapper", "Frame"), "RelatedPlaylistCover", "Frame")
	local remove = GuiRefs.need(info, "RemovefromQueueButton", "ImageButton")
	local row: QueueRow = {
		instance = button,
		title = GuiRefs.need(trackInfo, "TrackTitle", "TextLabel"),
		creator = GuiRefs.need(trackInfo, "TrackCreator", "TextLabel"),
		length = GuiRefs.need(trackInfo, "TrackLength", "TextLabel"),
		requester = GuiRefs.need(GuiRefs.need(info, "RequesterWrapper", "Frame"), "RequesterDisplayName", "TextLabel"),
		avatar = GuiRefs.need(info, "RequesterProfilePicture", "ImageLabel"),
		info = info,
		wrapper = GuiRefs.need(instance, "Wrapper", "Frame") :: Frame,
		coverHost = coverHost,
		coverImage = GuiRefs.need(coverHost, "ImageLabel", "ImageLabel"),
		remove = remove,
		entryId = nil,
	}
	-- "Queued by : <name>" on one line: the design wraps it, so a long name fell onto a second line
	-- below the 23 px chip and the chip read "Queued by :". The chip fills its row and ends in "...".
	row.requester.AutomaticSize = Enum.AutomaticSize.None
	row.requester.Size = UDim2.fromScale(1, 1)
	row.requester.TextWrapped = false
	row.requester.TextTruncate = Enum.TextTruncate.AtEnd
	-- The avatar sits left of the remove button; it moves into that slot when the button is hidden.
	row.avatarPosition = row.avatar.Position
	row.avatarEndPosition = UDim2.new(remove.Position.X.Scale, remove.Position.X.Offset, row.avatar.Position.Y.Scale, row.avatar.Position.Y.Offset)
	-- Resolved before the bind below: the icon tier may move the icon into its UIMotionIconSlot.
	local removeIcon = remove:FindFirstChildWhichIsA("ImageLabel")
	table.insert(
		self._connections,
		remove.Activated:Connect(function()
			if row.entryId then
				UIMotion.wiggle(removeIcon, 16)
				self._fire("OnTransport", "remove", { entryId = row.entryId })
			end
		end)
	)
	row.fade = { row.title, row.creator, row.length, row.requester, row.coverImage }
	row.fadeBases = UIMotion.captureBases(row.fade)
	-- After parenting (ListPool parents before createRow): the squash target is chosen from the live ancestry.
	local ok, err = pcall(function()
		self:_bindMotion(remove)
		self:_bindMotion(button)
	end)
	if not ok then
		warn(string.format("[NowPlayingView] queue row: motion bind failed, row shown without motion: %s", tostring(err)))
	end
	return row
end

-- The banner a waiting set card wears: the same face as the active Set card (SetBanner), built once
-- per row. Its remove control is wired here; it shows only when the row's remove rule allows it.
function NowPlayingView:_setBanner(row: QueueRow): any
	local existing = row.banner
	if existing then
		return existing
	end
	local banner = SetBanner.new(row.instance, {
		kicker = "UP NEXT SET",
		family = row.title.FontFace.Family,
		trashIcon = SetBanner.TRASH_ICON,
		oneLineTitle = true,
	})
	row.banner = banner
	local trash = banner.trash :: TextButton
	local trashIcon = trash:FindFirstChildWhichIsA("ImageLabel")
	table.insert(
		self._connections,
		trash.Activated:Connect(function()
			if row.entryId then
				UIMotion.wiggle(trashIcon, 16)
				self._fire("OnTransport", "remove", { entryId = row.entryId })
			end
		end)
	)
	return banner
end

function NowPlayingView:_bindSetBanner(row: QueueRow, track: any, playlist: any?)
	local banner = self:_setBanner(row)
	local count = math.floor(tonumber(track.total) or 0)
	local fill, onFill = SetBanner.colorsFor(playlist, self._config)
	banner:setData({
		title = tostring(track.name or ""),
		starterName = tostring(track.requesterDisplayName or ""),
		starterUserId = tonumber(track.requesterUserId),
		counter = string.format("%d %s", count, if count == 1 then "Track" else "Tracks"),
	})
	banner:paint(fill, onFill)
	Visuals.setVisible(banner.frame, true)
end

function NowPlayingView:_bindRow(row: QueueRow, track: any, playlist: any?)
	local isSet = track.setCard == true
	-- A waiting set card is drawn as its banner alone: the track layout (cover, text, length) hides.
	Visuals.setVisible(row.wrapper, not isSet)
	Visuals.setVisible(row.info, not isSet)
	if isSet then
		self:_bindSetBanner(row, track, playlist)
	elseif row.banner then
		Visuals.setVisible(row.banner.frame, false)
	end
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
	if not isSet then
		Visuals.applyTrackCover(
			row.coverImage,
			track,
			playlist,
			self._config,
			{ gradientHost = row.coverHost, listThumb = true }
		)
	end
	row.entryId = if type(track.queueEntryId) == "string" then track.queueEntryId else nil
	local localPlayer = Players.LocalPlayer
	local ownRequest = track.isSystemAssigned ~= true
		and localPlayer ~= nil
		and tonumber(track.requesterUserId) == localPlayer.UserId
	local canRemove = row.entryId ~= nil and (self._transportAllowed == true or ownRequest)
	Visuals.setVisible(row.remove, canRemove)
	if row.banner then
		Visuals.setVisible(row.banner.trash, canRemove)
	end
	local avatarPosition = if canRemove then row.avatarPosition else row.avatarEndPosition
	if avatarPosition and row.avatar.Position ~= avatarPosition then
		row.avatar.Position = avatarPosition
	end
	row.instance.Name = tostring(track.queueEntryId or track.id or "QueueRow")
end

-- ListPool binds a row only when the entry in its slot changes; a row that already holds the entry
-- moves with it. A key not in the previous render fades in; forced re-resolves rebind without motion.
function NowPlayingView:_bindQueueRow(row: QueueRow, track: any)
	if not self._renderForce and not self._prevKeys[queueKey(track)] and row.fade and row.fadeBases then
		UIMotion.fadeIn(row.fade, row.fadeBases, ROW_STAGGER_SECONDS * math.min(self._entering, 8))
		self._entering += 1
	end
	self:_bindRow(row, track, findPlaylist(self._playlists, track.playlistId))
end

function NowPlayingView:renderQueue(queue: { any }, force: boolean?)
	-- A forced render changes every key, so the pool rebinds each row it shows.
	if force then
		self._bindEpoch += 1
	end
	local items = {}
	local keys = {} :: { [string]: boolean }
	for _, track in ipairs(queue) do
		-- Tracks from the active set are drawn by the Set card, not as rows.
		if type(track) ~= "table" or track.fromSet == true then
			continue
		end
		table.insert(items, track)
		keys[queueKey(track)] = true
	end
	self._prevKeys = self._queueKeys
	self._queueKeys = keys
	self._renderForce = force == true
	self._entering = 0
	self._playlists = self._store:get().playlists
	self._pool:setItems(items)
end

function NowPlayingView:destroy()
	self:stopProgress()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	for _, unsubscribe in ipairs(self._unsubscribers) do
		unsubscribe()
	end
	for _, handle in ipairs(self._scrollHandles) do
		handle.destroy()
	end
	self._pool:destroy()
	self._setCard:destroy()
	table.clear(self._connections)
	table.clear(self._unsubscribers)
	table.clear(self._scrollHandles)
end

return NowPlayingView
