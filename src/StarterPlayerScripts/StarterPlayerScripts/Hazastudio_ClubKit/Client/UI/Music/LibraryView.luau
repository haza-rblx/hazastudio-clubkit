--!strict
-- PATH: StarterPlayerScripts/Client/UI/Music/LibraryView.luau
-- Library tab: playlist column (Liked Tracks, New Drops, playlists, DJ Sets), the selected set's
-- detail, a virtual track list, PrivateWall and Request From ID. Shuffle / Add set queue the
-- tracks currently listed (server caps them per player).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MusicLibraryModel = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.MusicLibraryModel)
local Cover = require(script.Parent.Parent.MusicPlayerCoverHelpers)
local GuiRefs = require(script.Parent.GuiRefs)
local ListPool = require(script.Parent.ListPool)
local MusicMotion = require(script.Parent.MusicMotion)
local Visuals = require(script.Parent.Visuals)

local ROW_STAGGER_SECONDS = 0.03
local ROW_STAGGER_MAX = 10

local SEARCH_DEBOUNCE = 0.15
local ADD_FEEDBACK_SECONDS = 1
local LIKED_TRANSPARENCY = 0
local UNLIKED_TRANSPARENCY = 0.55
local DISABLED_TRANSPARENCY = 0.5
local PLAYLIST_ORDER_BASE = 100
local DJ_SET_ORDER_BASE = 10000

type PlaylistRow = {
	instance: TextButton,
	cover: ImageLabel,
	coverName: TextLabel?,
	name: TextLabel,
	count: TextLabel,
	id: string?,
	key: string?,
}

local function need(parent: Instance, name: string, className: string): any
	return GuiRefs.need(parent, name, className)
end

local function trackCountText(count: number): string
	return string.format("%d %s", count, if count == 1 then "Track" else "Tracks")
end

-- Goal per object, so a selection re-render does not restart a highlight that is mid-fade.
local shownBackground: { [GuiObject]: number } = setmetatable({}, { __mode = "k" }) :: any

local function setBackgroundTransparency(object: GuiObject, value: number)
	local shown = shownBackground[object]
	if shown == value or (shown == nil and object.BackgroundTransparency == value) then
		shownBackground[object] = value
		return
	end
	shownBackground[object] = value
	MusicMotion.tween(object, if shown == nil then 0 else 0.18, { BackgroundTransparency = value })
end

local SET_REQUEST_LOCK_SECONDS = 1.5

local function setButtonEnabled(button: GuiButton, enabled: boolean)
	if button.Interactable == enabled then
		return
	end
	button.Interactable = enabled
	local transparency = if enabled then 0 else DISABLED_TRANSPARENCY
	for _, child in ipairs(button:GetChildren()) do
		if child:IsA("TextLabel") then
			MusicMotion.tween(child, 0.2, { TextTransparency = transparency })
		elseif child:IsA("ImageLabel") then
			MusicMotion.tween(child, 0.2, { ImageTransparency = transparency })
		end
	end
end

local LibraryView = {}
LibraryView.__index = LibraryView

function LibraryView.new(deps: { refs: GuiRefs.Refs, store: any, config: any, fire: (string, ...any) -> () })
	local self = setmetatable({}, LibraryView) :: any
	self._refs = deps.refs.library
	self._templates = deps.refs.playlistTemplates
	self._store = deps.store
	self._config = deps.config
	self._fire = deps.fire
	self._favoritesId = tostring(deps.config.SPECIAL_PLAYLIST_FAVORITES_ID or "__favorites__")
	self._newDropsId = tostring(deps.config.SPECIAL_PLAYLIST_NEW_DROPS_ID or "__new_drops__")
	self._playlists = {} :: { [string]: any }
	self._pools = { nonImage = {}, image = {}, djSet = {} } :: { [string]: { PlaylistRow } }
	self._trackCount = 0
	self._items = {} :: { any }
	self._setRequestLockedUntil = 0
	self._rowEntranceUntil = 0
	self._rowEntranceFirst = 1
	self._lastSelection = nil :: string?
	self._searchToken = 0
	self._connections = {} :: { RBXScriptConnection }
	self._unsubscribers = {} :: { () -> () }
	self._trackPool = ListPool.new({
		scroll = self._refs.trackScroll,
		container = self._refs.trackContainer,
		template = deps.refs.trackRowTemplate,
		buffer = tonumber(deps.config.VIRTUAL_TRACK_ROW_BUFFER),
		maxRows = tonumber(deps.config.VIRTUAL_TRACK_MAX_RENDERED_ROWS),
		keyOf = function(track: any): string
			return string.format(
				"%s|%s|%s|%s|%s",
				tostring(track.id),
				tostring(track.name),
				tostring(track.creator),
				tostring(track.totalDuration),
				tostring(track.coverValue or track.playlistId)
			)
		end,
		createRow = function(instance: GuiObject): any
			return self:_createTrackRow(instance)
		end,
		bindRow = function(row: any, track: any, index: number)
			self:_bindTrackRow(row, track, index)
		end,
	})
	return self
end

function LibraryView:_connect(connection: RBXScriptConnection)
	table.insert(self._connections, connection)
end

-- ============================================================
-- Bind
-- ============================================================

function LibraryView:bind()
	local refs = self._refs
	local store = self._store

	local newDropsInfo = need(refs.newDropsButton, "PlaylistInformation", "Frame")
	Visuals.setText(need(newDropsInfo, "PlaylistName", "TextLabel"), Cover.getMonthDropsLabel())
	self._specialNormalTransparency = refs.favoritesButton.BackgroundTransparency
	-- Both ship with LayoutOrder 0; ties have no defined order in a UIListLayout.
	refs.favoritesButton.LayoutOrder = 1
	refs.newDropsButton.LayoutOrder = 2
	self:_connect(refs.favoritesButton.Activated:Connect(function()
		self:_select(self._favoritesId)
	end))
	self:_connect(refs.newDropsButton.Activated:Connect(function()
		self:_select(self._newDropsId)
	end))

	local function requestSet(shuffle: boolean)
		if os.clock() < self._setRequestLockedUntil or #self._items == 0 then
			return
		end
		local trackIds = {}
		for _, track in ipairs(self._items) do
			table.insert(trackIds, tostring(track.id))
		end
		self._fire("OnTransport", "request_many", { trackIds = trackIds, shuffle = shuffle })
		-- Brief lock against double taps; both buttons share it.
		self._setRequestLockedUntil = os.clock() + SET_REQUEST_LOCK_SECONDS
		self:_applySetButtons()
		task.delay(SET_REQUEST_LOCK_SECONDS, function()
			self:_applySetButtons()
		end)
	end
	local shuffleIcon = refs.shuffleButton:FindFirstChildWhichIsA("ImageLabel")
	local addSetIcon = refs.addSetButton:FindFirstChildWhichIsA("ImageLabel")
	self:_connect(refs.shuffleButton.Activated:Connect(function()
		if refs.shuffleButton.Interactable then
			MusicMotion.spin(shuffleIcon)
		end
		requestSet(true)
	end))
	self:_connect(refs.addSetButton.Activated:Connect(function()
		if refs.addSetButton.Interactable then
			MusicMotion.wiggle(addSetIcon, 12)
		end
		requestSet(false)
	end))
	for _, button in ipairs({ refs.favoritesButton, refs.newDropsButton, refs.requestButton }) do
		for _, connection in ipairs(MusicMotion.bindPress(button)) do
			self:_connect(connection)
		end
	end
	self:_applySetButtons()
	Visuals.setVisible(refs.detailOwnerAvatar, false)

	self:_connect(refs.searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		self._searchToken += 1
		local token = self._searchToken
		task.delay(SEARCH_DEBOUNCE, function()
			if token ~= self._searchToken then
				return
			end
			local query = refs.searchBox.Text
			if store:get().searchQuery == query then
				return
			end
			store:set({ searchQuery = query })
			self._fire("OnSearchChanged", query)
		end)
	end))

	local function submitRequestFromId()
		local raw = refs.requestInput.Text
		if string.match(raw, "^%s*$") then
			self._fire("OnFormNotify", "warning", "Asset ID required", "Enter a Roblox audio asset ID first.")
			return
		end
		self._fire("OnResolveRequestAsset", raw)
	end
	self:_connect(refs.requestButton.Activated:Connect(submitRequestFromId))
	self:_connect(refs.requestInput.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			submitRequestFromId()
		end
	end))

	table.insert(self._unsubscribers, store:subscribe("favoriteTrackIds", function()
		self._trackPool:forEachRendered(function(row)
			self:_applyLiked(row, true)
		end)
	end))
	table.insert(self._unsubscribers, store:subscribe("djSets", function()
		self:renderPlaylists(self._playlists, store:get().searchQuery)
	end))
	table.insert(self._unsubscribers, store:subscribe("isControlAllowed", function()
		self:_renderDetail()
	end))
	-- Request by asset ID creates a library track, so it follows the manage privilege (off in web mode).
	table.insert(self._unsubscribers, store:subscribe("isManageAllowed", function(allowed)
		Visuals.setVisible(refs.requestFromId, allowed == true)
	end))
	Visuals.setVisible(refs.requestFromId, store:get().isManageAllowed == true)

	self:_renderDetail()
end

function LibraryView:_select(playlistId: string)
	if self._store:get().selectedPlaylistId == playlistId then
		return
	end
	self._fire("OnPlaylistSelected", playlistId)
end

-- ============================================================
-- Playlist column
-- ============================================================

function LibraryView:_playlistRow(kind: string, index: number): PlaylistRow
	local pool = self._pools[kind]
	local existing = pool[index]
	if existing then
		return existing
	end
	local template = if kind == "image"
		then self._templates.imageNormal
		elseif kind == "djSet" then self._templates.djSetNormal
		else self._templates.nonImageNormal
	local instance = template:Clone() :: TextButton
	local cover = need(instance, "PlaylistCover", "ImageLabel")
	local info = need(instance, "PlaylistInformation", "Frame")
	local row: PlaylistRow = {
		instance = instance,
		cover = cover,
		coverName = if kind == "nonImage" then need(cover, "PlaylistName", "TextLabel") else nil,
		name = need(info, "PlaylistName", "TextLabel"),
		count = need(info, "TotalTrack", "TextLabel"),
		id = nil,
		key = nil,
	}
	self:_connect(instance.Activated:Connect(function()
		if row.id then
			MusicMotion.wiggle(cover, 5)
			self:_select(row.id)
		end
	end))
	instance.Parent = self._refs.playlistScroll
	pool[index] = row
	return row
end

function LibraryView:_applyRowSelection(row: PlaylistRow, kind: string, selected: boolean)
	local templates = self._templates
	local selectedTemplate = if kind == "image"
		then templates.imageSelected
		elseif kind == "djSet" then templates.djSetSelected
		else templates.nonImageSelected
	local normalTemplate = if kind == "image"
		then templates.imageNormal
		elseif kind == "djSet" then templates.djSetNormal
		else templates.nonImageNormal
	setBackgroundTransparency(
		row.instance,
		if selected then selectedTemplate.BackgroundTransparency else normalTemplate.BackgroundTransparency
	)
end

function LibraryView:renderPlaylists(playlists: { [string]: any }?, query: string?)
	local refs = self._refs
	local state = self._store:get()
	local selected = state.selectedPlaylistId
	self._playlists = playlists or {}

	local selectedTransparency = self._templates.nonImageSelected.BackgroundTransparency
	local normalTransparency = self._specialNormalTransparency or refs.favoritesButton.BackgroundTransparency
	setBackgroundTransparency(
		refs.favoritesButton,
		if selected == self._favoritesId then selectedTransparency else normalTransparency
	)
	setBackgroundTransparency(
		refs.newDropsButton,
		if selected == self._newDropsId then selectedTransparency else normalTransparency
	)

	local used = { nonImage = 0, image = 0, djSet = 0 }
	for order, entry in ipairs(MusicLibraryModel.orderPlaylists(self._playlists, query)) do
		local playlist = entry.playlist
		local kind = if playlist.coverType == "image" then "image" else "nonImage"
		used[kind] += 1
		local row = self:_playlistRow(kind, used[kind])
		local isPrivate = playlist.visibility == "private"
		local trackCount = if type(playlist.trackIds) == "table" then #playlist.trackIds else 0
		local key = string.format(
			"%s|%s|%d|%s|%s|%s",
			entry.id,
			tostring(playlist.name),
			trackCount,
			tostring(playlist.coverType),
			tostring(playlist.coverValue),
			tostring(playlist.visibility)
		)
		row.id = entry.id
		if row.key ~= key then
			row.key = key
			local name = tostring(playlist.name or "")
			Visuals.setText(row.name, name)
			Visuals.setText(row.count, if isPrivate then "Private" else trackCountText(trackCount))
			if row.coverName then
				Visuals.setText(row.coverName, name)
			end
			Visuals.applyCover(row.cover, playlist, self._config, { listThumb = true })
			row.instance.Name = entry.id
		end
		self:_applyRowSelection(row, kind, selected == entry.id)
		if row.instance.LayoutOrder ~= PLAYLIST_ORDER_BASE + order then
			row.instance.LayoutOrder = PLAYLIST_ORDER_BASE + order
		end
		Visuals.setVisible(row.instance, true)
	end

	local needle = string.lower(query or "")
	local allTracks = state.allTracks or {}
	for _, set in ipairs(state.djSets or {}) do
		if needle ~= "" and not string.find(string.lower(set.name), needle, 1, true) then
			continue
		end
		used.djSet += 1
		local row = self:_playlistRow("djSet", used.djSet)
		local firstTrack = allTracks[set.trackIds[1]]
		local coverSource = if firstTrack
			then Cover.resolveCoverSourceForTrack(firstTrack, self._playlists[firstTrack.playlistId])
			else nil
		local key = string.format("%s|%s|%d|%s", set.id, set.name, #set.trackIds, tostring(set.trackIds[1]))
		row.id = set.id
		if row.key ~= key then
			row.key = key
			Visuals.setText(row.name, set.name)
			Visuals.setText(row.count, trackCountText(#set.trackIds))
			Visuals.applyCover(row.cover, coverSource, self._config, { listThumb = true })
			row.instance.Name = set.id
		end
		self:_applyRowSelection(row, "djSet", selected == set.id)
		if row.instance.LayoutOrder ~= DJ_SET_ORDER_BASE + used.djSet then
			row.instance.LayoutOrder = DJ_SET_ORDER_BASE + used.djSet
		end
		Visuals.setVisible(row.instance, true)
	end

	for kind, pool in pairs(self._pools) do
		for index = (used :: any)[kind] + 1, #pool do
			local row = pool[index]
			row.id = nil
			Visuals.setVisible(row.instance, false)
		end
	end

	self:_renderDetail()
end

-- ============================================================
-- Selected set: detail + PrivateWall
-- ============================================================

function LibraryView:_isWalled(selected: string?): boolean
	local playlist = if selected then self._playlists[selected] else nil
	return type(playlist) == "table"
		and playlist.visibility == "private"
		and self._store:get().isControlAllowed ~= true
end

function LibraryView:_findDjSet(selected: string?): any?
	if not MusicLibraryModel.isDjSetId(selected) then
		return nil
	end
	for _, set in ipairs(self._store:get().djSets or {}) do
		if set.id == selected then
			return set
		end
	end
	return nil
end

function LibraryView:_renderDetail()
	local refs = self._refs
	local selected = self._store:get().selectedPlaylistId
	local walled = self:_isWalled(selected)
	Visuals.setVisible(refs.privateWall, walled)
	Visuals.setVisible(refs.detail, not walled)
	Visuals.setVisible(refs.trackPanel, not walled)
	if walled then
		return
	end

	local countText = trackCountText(self._trackCount)
	local title, subtitle, level, owner, coverSource = "All Tracks", countText, "Library", nil, nil
	local playlist = if selected then self._playlists[selected] else nil
	local djSet = self:_findDjSet(selected)
	if selected == self._favoritesId then
		title, subtitle, level = "Liked Tracks", "Your no skip tracks live here.", "Only You"
	elseif selected == self._newDropsId then
		title, subtitle, level = Cover.getMonthDropsLabel(), "Fresh tracks you gotta hear rn.", "New Drops"
	elseif djSet then
		title, level, owner = djSet.name, "DJ Set", "DJ Set"
		local firstTrack = (self._store:get().allTracks or {})[djSet.trackIds[1]]
		if firstTrack then
			coverSource = Cover.resolveCoverSourceForTrack(firstTrack, self._playlists[firstTrack.playlistId])
		end
	elseif type(playlist) == "table" then
		title = tostring(playlist.name or "")
		level = if playlist.visibility == "private" then "Private Playlist" else "Public Playlist"
		coverSource = playlist
	end

	Visuals.setText(refs.detailTitle, title)
	Visuals.setText(refs.detailSubtitle, subtitle)
	Visuals.setText(refs.detailLevelLabel, level)
	Visuals.setVisible(refs.detailOwnerName, owner ~= nil)
	if owner then
		Visuals.setText(refs.detailOwnerName, owner)
	end
	Visuals.applyCover(refs.detailCover, coverSource, self._config)

	-- Picking another set fades its header in; repaints of the same set stay still.
	if self._detailSelection ~= selected then
		local first = self._detailSelection == nil and self._detailBases == nil
		self._detailSelection = selected
		if not self._detailBases then
			self._detailFade = { refs.detailCover, refs.detailTitle, refs.detailSubtitle, refs.detailOwnerName }
			self._detailBases = MusicMotion.captureBases(self._detailFade)
		end
		if not first then
			MusicMotion.fadeIn(self._detailFade, self._detailBases)
		end
	end
end

-- ============================================================
-- Track list
-- ============================================================

function LibraryView:_createTrackRow(instance: GuiObject): any
	local info = need(instance, "TrackInformationSection", "Frame")
	local trackInfo = need(info, "TrackInfo", "Frame")
	local coverHost = need(need(instance, "RelatedPlaylistCover", "Frame"), "RelatedPlaylistCover", "Frame")
	local addButton = need(info, "AddtoQueueButton", "ImageButton")
	local likeButton = need(info, "LikeTrackButton", "ImageButton")
	local row = {
		title = need(trackInfo, "TrackTitle", "TextLabel"),
		creator = need(trackInfo, "TrackCreator", "TextLabel"),
		length = need(trackInfo, "TrackLength", "TextLabel"),
		coverHost = coverHost,
		coverImage = need(coverHost, "ImageLabel", "ImageLabel"),
		addButton = addButton,
		addIcon = need(addButton, "ImageLabel", "ImageLabel"),
		likeButton = likeButton,
		likeIcon = need(likeButton, "ImageLabel", "ImageLabel"),
		trackId = nil :: string?,
		addToken = 0,
	}
	self:_connect(addButton.Activated:Connect(function()
		local trackId = row.trackId
		if not trackId or not addButton.Interactable then
			return
		end
		self._fire("OnRequestTrack", trackId)
		row.addToken += 1
		local token = row.addToken
		addButton.Interactable = false
		MusicMotion.spin(row.addIcon)
		MusicMotion.tween(row.addIcon, 0.2, { ImageTransparency = DISABLED_TRANSPARENCY })
		task.delay(ADD_FEEDBACK_SECONDS, function()
			if row.addToken ~= token then
				return
			end
			addButton.Interactable = true
			MusicMotion.tween(row.addIcon, 0.2, { ImageTransparency = 0 })
			MusicMotion.pop(row.addIcon, 1.2)
		end)
	end))
	self:_connect(likeButton.Activated:Connect(function()
		local trackId = row.trackId
		if not trackId then
			return
		end
		local favorites = self._store:get().favoriteTrackIds or {}
		self._fire("OnAddFavoriteTrack", trackId, favorites[trackId] == true)
	end))
	for _, button in ipairs({ addButton, likeButton }) do
		for _, connection in ipairs(MusicMotion.bindPress(button)) do
			self:_connect(connection)
		end
	end
	row.fade = { row.title, row.creator, row.length, row.coverImage }
	row.fadeBases = MusicMotion.captureBases(row.fade)
	return row
end

-- animate: the like state changed while the row stayed on screen (not a rebind to another track).
function LibraryView:_applyLiked(row: any, animate: boolean?)
	local favorites = self._store:get().favoriteTrackIds or {}
	local liked = row.trackId ~= nil and favorites[row.trackId] == true
	local transparency = if liked then LIKED_TRANSPARENCY else UNLIKED_TRANSPARENCY
	if row.likedShown == liked then
		return
	end
	local changed = row.likedShown ~= nil
	row.likedShown = liked
	if animate and changed then
		MusicMotion.tween(row.likeIcon, 0.2, { ImageTransparency = transparency })
		if liked then
			MusicMotion.pop(row.likeIcon, 1.45, 0.14)
		else
			MusicMotion.wiggle(row.likeIcon, 10)
		end
	else
		MusicMotion.tween(row.likeIcon, 0, { ImageTransparency = transparency })
	end
end

function LibraryView:_bindTrackRow(row: any, track: any, index: number)
	row.trackId = tostring(track.id)
	row.likedShown = nil
	row.addToken += 1
	row.addButton.Interactable = true
	MusicMotion.tween(row.addIcon, 0, { ImageTransparency = 0 })
	local restRotation = tonumber(row.addIcon:GetAttribute("MusicMotionRotation"))
	if restRotation then
		MusicMotion.tween(row.addIcon, 0, { Rotation = restRotation })
	end
	if self._rowEntranceActive then
		MusicMotion.fadeIn(row.fade, row.fadeBases, ROW_STAGGER_SECONDS * math.min(self._rowEntranceCount, ROW_STAGGER_MAX))
		self._rowEntranceCount += 1
	end
	Visuals.setText(row.title, tostring(track.name or ""))
	Visuals.setText(row.creator, tostring(track.creator or ""))
	Visuals.setText(row.length, Visuals.formatClock(tonumber(track.totalDuration) or 0))
	local playlist = self._playlists[track.playlistId] or track.playlist
	Visuals.applyCover(
		row.coverImage,
		Cover.resolveCoverSourceForTrack(track, playlist),
		self._config,
		{ gradientHost = row.coverHost, listThumb = true }
	)
	self:_applyLiked(row)
	row.instance.Name = row.trackId
end

function LibraryView:_applySetButtons()
	local enabled = #self._items > 0 and os.clock() >= self._setRequestLockedUntil
	setButtonEnabled(self._refs.shuffleButton, enabled)
	setButtonEnabled(self._refs.addSetButton, enabled)
end

function LibraryView:renderTracks(tracks: { [any]: any }?, query: string?)
	local selected = self._store:get().selectedPlaylistId
	local resetScroll = self._lastSelection ~= selected
	self._lastSelection = selected
	if self:_isWalled(selected) then
		self._items = {}
		self._trackCount = 0
		self._trackPool:setItems({}, true)
	else
		local items = MusicLibraryModel.filterTracks(tracks or {}, query, selected == self._newDropsId)
		self._items = items
		self._trackCount = #items
		-- Rows rebound by this redraw (a new set or search) cascade in. Rows reached later by
		-- scrolling are bound outside it and just appear; a same-list refresh rebinds nothing.
		self._rowEntranceActive = true
		self._rowEntranceCount = 0
		self._trackPool:setItems(items, resetScroll)
		self._rowEntranceActive = false
	end
	self:_applySetButtons()
	self:_renderDetail()
end

-- v3 has no confirmation modal: a resolved asset goes straight to the queue.
function LibraryView:requestResolvedTrack(track: any)
	if type(track) == "table" and track.id then
		self._fire("OnRequestTrack", track.id)
	end
end

function LibraryView:destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	for _, unsubscribe in ipairs(self._unsubscribers) do
		unsubscribe()
	end
	for _, pool in pairs(self._pools) do
		for _, row in ipairs(pool) do
			row.instance:Destroy()
		end
	end
	self._trackPool:destroy()
	table.clear(self._connections)
	table.clear(self._unsubscribers)
end

return LibraryView
