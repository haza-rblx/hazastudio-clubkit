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
local UIMotion = require(script.Parent.Parent.Parent.Utils.UIMotion)
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

-- Cover stack behind the detail cover (BackdropFar / BackdropNear). Both land after the front
-- cover, the back one last. They move, never fade: the cards are behind the cover all along.
local BACKDROP_NEAR_TIME = 0.34
local BACKDROP_FAR_TIME = 0.44
-- Only used where a place has one backdrop frame and not the other, so the step between the two
-- cannot be measured. With both present the real offsets win (see _bindBackdrops).
local BACKDROP_FALLBACK_POSITION_STEP = UDim2.fromScale(0, 0.05)
local BACKDROP_FALLBACK_SIZE_STEP = UDim2.fromScale(0.15, 0.15)

type PlaylistRow = {
	instance: TextButton,
	cover: ImageLabel,
	coverName: TextLabel?,
	name: TextLabel,
	count: TextLabel,
	id: string?,
	key: string?,
}

type BackdropLayer = {
	frame: Frame,
	position: UDim2,
	size: UDim2,
	gatheredPosition: UDim2,
	gatheredSize: UDim2,
	time: number,
}

local function need(parent: Instance, name: string, className: string): any
	return GuiRefs.need(parent, name, className)
end

local function trackCountText(count: number): string
	return string.format("%d %s", count, if count == 1 then "Track" else "Tracks")
end

-- Goal per object, so a selection re-render does not restart a highlight that is mid-fade.
-- Weak on purpose (ADR 0011 addendum, 2026-09-17): a pure cache. A lost entry only makes the next
-- change land instantly instead of over 0.18 s (or no-op when already there), never a wrong value.
local shownBackground: { [GuiObject]: number } = setmetatable({}, { __mode = "k" }) :: any

local function setBackgroundTransparency(object: GuiObject, value: number)
	local shown = shownBackground[object]
	if shown == value or (shown == nil and object.BackgroundTransparency == value) then
		shownBackground[object] = value
		return
	end
	shownBackground[object] = value
	UIMotion.tween(object, if shown == nil then 0 else 0.18, { BackgroundTransparency = value })
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
			UIMotion.tween(child, 0.2, { TextTransparency = transparency })
		elseif child:IsA("ImageLabel") then
			UIMotion.tween(child, 0.2, { ImageTransparency = transparency })
		end
	end
end

-- The cover stack is GUI-template decoration: kit code never created BackdropNear/BackdropFar and
-- most buyers' `06-MusicPlayerGUIv3` does not have them (nor the CoverImage inside each one, which
-- is newer still). Every lookup is optional and silent — a place without them keeps exactly the
-- detail panel it has today. Frame and CoverImage are resolved separately, so a place with the
-- frames but no covers still gets the stack settling into place.
local function backdropFrame(wrapper: Instance, name: string): Frame?
	local found = wrapper:FindFirstChild(name)
	return if found and found:IsA("Frame") then found else nil
end

local function backdropCover(frame: Frame?): ImageLabel?
	local found = if frame then frame:FindFirstChild("CoverImage") else nil
	return if found and found:IsA("ImageLabel") then found else nil
end

-- designed + step * factor, on both axes and in both units.
local function gatheredFrom(base: UDim2, step: UDim2, factor: number): UDim2
	return UDim2.new(
		base.X.Scale + step.X.Scale * factor,
		base.X.Offset + step.X.Offset * factor,
		base.Y.Scale + step.Y.Scale * factor,
		base.Y.Offset + step.Y.Offset * factor
	)
end

local function makeBackdropLayer(
	frame: Frame,
	positionStep: UDim2,
	sizeStep: UDim2,
	factor: number,
	seconds: number
): BackdropLayer
	return {
		frame = frame,
		position = frame.Position,
		size = frame.Size,
		gatheredPosition = gatheredFrom(frame.Position, positionStep, factor),
		gatheredSize = gatheredFrom(frame.Size, sizeStep, factor),
		time = seconds,
	}
end

-- "Two random covers" made repeatable: the scan starts at a slot derived from the set's own id, so
-- different sets show different pairs while one set shows the same pair every time. `math.random`
-- would re-roll on every repaint of the same set, which reads as a bug rather than as variety.
local function backdropStart(setId: string, count: number): number
	local hash = 0
	for index = 1, #setId do
		hash = (hash * 31 + string.byte(setId, index)) % 1048576
	end
	return hash % count + 1
end

-- Up to two distinct image covers taken from the set's own tracks, scanned circularly from that
-- slot. Distinctness is by cover asset, not by track: two tracks sharing art count once.
local function pickBackdropCovers(setId: string, trackIds: { any }?, allTracks: { [any]: any }?): { any }
	local picks = {}
	local count = if type(trackIds) == "table" then #trackIds else 0
	if count == 0 or type(allTracks) ~= "table" then
		return picks
	end
	local start = backdropStart(setId, count)
	local seen = {}
	for step = 0, count - 1 do
		local track = allTracks[(trackIds :: { any })[(start - 1 + step) % count + 1]]
		if type(track) == "table" and track.coverType == "image" then
			local key = Cover.getImageCoverKey(track.coverValue)
			if key and not seen[key] then
				seen[key] = true
				table.insert(picks, { coverType = "image", coverValue = track.coverValue })
				if #picks == 2 then
					break
				end
			end
		end
	end
	return picks
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
	self._backdropLayers = {} :: { BackdropLayer }
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

-- Press squash + hover lift, the pairing every other kit panel uses (ADR 0011). Pooled rows call
-- this from createRow, which ListPool runs once per instance, so a rebind cannot stack connections.
function LibraryView:_bindMotion(button: GuiObject)
	for _, connection in ipairs(UIMotion.bindPress(button)) do
		self:_connect(connection)
	end
	for _, connection in ipairs(UIMotion.bindHover(button)) do
		self:_connect(connection)
	end
end

-- ============================================================
-- Bind
-- ============================================================

function LibraryView:bind()
	local refs = self._refs
	local store = self._store

	self:_bindBackdrops()

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
			UIMotion.spin(shuffleIcon)
		end
		requestSet(true)
	end))
	self:_connect(refs.addSetButton.Activated:Connect(function()
		if refs.addSetButton.Interactable then
			UIMotion.wiggle(addSetIcon, 12)
		end
		requestSet(false)
	end))
	for _, button in ipairs({ refs.favoritesButton, refs.newDropsButton, refs.requestButton }) do
		self:_bindMotion(button)
	end
	for _, button in ipairs({ refs.shuffleButton, refs.addSetButton }) do
		self:_bindMotion(button)
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
	-- Request by asset ID plays the song once and never touches the library (3.0); the server
	-- decides per player from ClubKitConfig.Music.PlayOnceRequest.
	table.insert(self._unsubscribers, store:subscribe("isPlayOnceAllowed", function(allowed)
		Visuals.setVisible(refs.requestFromId, allowed == true)
	end))
	Visuals.setVisible(refs.requestFromId, store:get().isPlayOnceAllowed == true)

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
			UIMotion.wiggle(cover, 5)
			self:_select(row.id)
		end
	end))
	instance.Parent = self._refs.playlistScroll
	-- After parenting: the squash target is chosen from the live ancestry (list layout, groups).
	self:_bindMotion(instance)
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
			-- The column shows each playlist's real cover, text and layout included, like the web.
			Visuals.applyCover(row.cover, playlist, self._config, { listThumb = true, fullTile = true })
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
		local key = string.format("%s|%s|%d|%s", set.id, set.name, #set.trackIds, tostring(set.trackIds[1]))
		row.id = set.id
		if row.key ~= key then
			row.key = key
			Visuals.setText(row.name, set.name)
			Visuals.setText(row.count, trackCountText(#set.trackIds))
			-- The set's card shows its first song's own cover, like the set's detail page does.
			-- Going through the song's playlist instead drew every set whose first song sat in the
			-- same template playlist with that playlist's one cover (THE BASIC, 2026-09-23).
			Visuals.applyTrackCover(
				row.cover,
				firstTrack,
				if firstTrack then self._playlists[firstTrack.playlistId] else nil,
				self._config,
				{ listThumb = true }
			)
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

-- ============================================================
-- Selected set: the cover stack behind the detail cover
-- ============================================================

-- Resolved once, at bind, before anything has moved. Everything the stack animates back to is read
-- here and frozen: _renderDetail runs on most store changes, so a value read at animation time
-- could be a mid-tween position and would become the new, wrong, "design".
function LibraryView:_bindBackdrops()
	local wrapper = self._refs.detailCover.Parent
	if not wrapper then
		return
	end
	local nearFrame = backdropFrame(wrapper, "BackdropNear")
	local farFrame = backdropFrame(wrapper, "BackdropFar")
	if not nearFrame and not farFrame then
		return
	end
	self._backdropNearCover = backdropCover(nearFrame)
	self._backdropFarCover = backdropCover(farFrame)

	-- ADR 0005: under a CanvasGroup the panel is one rasterized texture. Leave Position/Size alone
	-- there and let the fade above carry the change on its own.
	local ancestor: Instance? = wrapper
	while ancestor and not ancestor:IsA("ScreenGui") do
		if ancestor:IsA("CanvasGroup") then
			return
		end
		ancestor = ancestor.Parent
	end

	-- The gathered start is extrapolated from the frames' own designed offsets: the step from Far
	-- to Near, applied once more, lands on the front cover's plane. So the stack collapses into the
	-- cover and fans back out without this code ever measuring the cover — whose Size is in offsets
	-- while the frames' is in scale, and which no buyer template is obliged to lay out the same way.
	local positionStep = if nearFrame and farFrame
		then nearFrame.Position - farFrame.Position
		else BACKDROP_FALLBACK_POSITION_STEP
	local sizeStep = if nearFrame and farFrame
		then nearFrame.Size - farFrame.Size
		else BACKDROP_FALLBACK_SIZE_STEP

	local layers = self._backdropLayers
	if nearFrame then
		table.insert(layers, makeBackdropLayer(nearFrame, positionStep, sizeStep, 1, BACKDROP_NEAR_TIME))
	end
	if farFrame then
		table.insert(layers, makeBackdropLayer(farFrame, positionStep, sizeStep, 2, BACKDROP_FAR_TIME))
	end
end

-- Both layers leave the gathered state on the same frame and settle over different durations, so
-- the back one lands last without a task.delay a second playlist switch could land inside.
function LibraryView:_playBackdropStack()
	local reduced = UIMotion.reduced()
	for _, layer in ipairs(self._backdropLayers) do
		if not reduced then
			UIMotion.tween(layer.frame, 0, { Position = layer.gatheredPosition, Size = layer.gatheredSize })
		end
		UIMotion.tween(
			layer.frame,
			if reduced then 0 else layer.time,
			{ Position = layer.position, Size = layer.size },
			Enum.EasingStyle.Quint,
			Enum.EasingDirection.Out
		)
	end
end

-- Two covers off the opened set's own tracks, picked once and then frozen: the pick is re-run only
-- when the selection, the playlists table or the allTracks table is a different table than last
-- time (the controller replaces both wholesale), so an ordinary repaint cannot swap the art.
-- Whatever the pick cannot fill falls back to the set's own cover — a stack of one art is still a
-- stack. Liked Tracks / New Drops / All Tracks have no track id list of their own and so always
-- take that fallback, which for them is the same empty source the front cover gets.
function LibraryView:_applyBackdropCovers(selected: string?, coverSource: any?, trackIds: { any }?)
	local near, far = self._backdropNearCover, self._backdropFarCover
	if not near and not far then
		return
	end
	local allTracks = self._store:get().allTracks
	if
		self._backdropSelection ~= selected
		or self._backdropPlaylistsRef ~= self._playlists
		or self._backdropTracksRef ~= allTracks
	then
		self._backdropSelection = selected
		self._backdropPlaylistsRef = self._playlists
		self._backdropTracksRef = allTracks
		local picks = pickBackdropCovers(tostring(selected), trackIds, allTracks)
		self._backdropNearSource = picks[1] or coverSource
		self._backdropFarSource = picks[2] or coverSource
	end
	-- listThumb: both the playlist column and the track rows already hold these assets as 150 px
	-- thumbs, so the common cases cost no extra texture at all.
	if near then
		Visuals.applyCover(near, self._backdropNearSource, self._config, { listThumb = true })
	end
	if far then
		Visuals.applyCover(far, self._backdropFarSource, self._config, { listThumb = true })
	end
end

-- ============================================================
-- Dealt stack (All Tracks / New Drops)
-- ============================================================

-- A real deck: one card per slot (the detail cover, then BackdropNear, BackdropFar) plus a spare
-- parked invisibly in the last slot. Every DECK_INTERVAL the front card leaves (up and to the left,
-- fading), every other card slides one slot forward and the spare fades in at the back. The cards
-- are clones of the detail cover, so they look like it; the template's own cover and backdrops are
-- hidden while the deck runs. Each card keeps its tile for as long as it holds a track, and the one
-- that left is re-dealt only after every move has finished, while it is invisible — so no cover is
-- ever built mid-animation or shown before it is drawn (owner, 2026-09-23: "patah-patah", "card
-- kosong").
-- A card behind the front is dimmed the way the template dims its backdrops (their CoverImage
-- transparency over a dark frame): a black shade inside the card, eased along as it changes slot.
-- Opening one of these sets plays the same entrance as any other set: the front card pops and the
-- cards behind fan out from under it, each dealt one frame apart so opening never builds every
-- cover in one frame (owner: "ga rapi", "ga se smooth kek buka playlist lain").
local DECK_INTERVAL = 3.2
local DECK_MOVE_TIME = 0.55
local DECK_EXIT_TIME = 0.45
local DECK_EXIT_OFFSET = UDim2.fromOffset(-40, -20)
local DECK_EXIT_ROTATION = -12
local DECK_DEFAULT_DIM = { 0, 0.4, 0.7 }
local DECK_ENTRANCE_TIMES = { 0, BACKDROP_NEAR_TIME, BACKDROP_FAR_TIME }
local CENTRE = Vector2.new(0.5, 0.5)

type DeckSlot = { position: UDim2, size: UDim2, z: number, dim: number }

local function shownOnScreen(gui: GuiObject): boolean
	local node: Instance? = gui
	while node and not node:IsA("ScreenGui") do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return node ~= nil and (node :: ScreenGui).Enabled
end

function LibraryView:_nextDealt(): any?
	local order = self._deckOrder
	if not order or #order == 0 then
		return nil
	end
	self._deckCursor = self._deckCursor % #order + 1
	return order[self._deckCursor]
end

function LibraryView:_dealCard(card: ImageLabel, track: any?)
	if type(track) == "table" then
		Visuals.applyTrackCover(card, track, self._playlists[track.playlistId], self._config)
	end
end

local function shadeOf(card: ImageLabel): Frame
	return card:FindFirstChild("DeckShade") :: Frame
end

-- `shown` false parks the card invisible (image and shade both transparent).
function LibraryView:_placeCard(card: ImageLabel, slot: DeckSlot, shown: boolean)
	UIMotion.cancel(card)
	local shade = shadeOf(card)
	UIMotion.cancel(shade)
	card.AnchorPoint = CENTRE
	card.Position = slot.position
	card.Size = slot.size
	card.Rotation = 0
	card.ZIndex = slot.z
	card.ImageTransparency = if shown then 0 else 1
	shade.BackgroundTransparency = if shown then 1 - slot.dim else 1
end

function LibraryView:_moveCard(card: ImageLabel, slot: DeckSlot, seconds: number)
	card.ZIndex = slot.z
	UIMotion.tween(card, seconds, {
		Position = slot.position,
		Size = slot.size,
		Rotation = 0,
		ImageTransparency = 0,
	}, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	UIMotion.tween(shadeOf(card), seconds, { BackgroundTransparency = 1 - slot.dim }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
end

-- Front first. Geometry is read once per deal from the template's designed values (the backdrop
-- layers keep theirs from bind time), so a mid-tween position is never mistaken for a slot. Every
-- slot is expressed around a centre anchor, so a card moving between slots never jumps and the
-- front card can pop from its middle.
function LibraryView:_deckSlots(): { DeckSlot }
	local cover = self._refs.detailCover
	local raw = {
		{ position = cover.Position, size = cover.Size, anchor = cover.AnchorPoint, z = cover.ZIndex, dim = DECK_DEFAULT_DIM[1] },
	}
	for index, name in ipairs({ "BackdropNear", "BackdropFar" }) do
		for _, layer in ipairs(self._backdropLayers) do
			if layer.frame.Name == name then
				local inner = backdropCover(layer.frame)
				table.insert(raw, {
					position = layer.position,
					size = layer.size,
					anchor = layer.frame.AnchorPoint,
					z = layer.frame.ZIndex,
					dim = if inner then inner.ImageTransparency else DECK_DEFAULT_DIM[index + 1],
				})
			end
		end
	end
	-- Each slot as the square the template actually draws: its UIAspectRatioConstraint shrinks the
	-- designed box to min(w, h) around the element's own anchor point (a backdrop anchored at its
	-- top stays at its top). Expressed as fractions of the wrapper, centre-anchored.
	local wrapper = cover.Parent :: GuiObject
	-- Offsets are in design units; AbsoluteSize already carries every UIScale above (the panel's
	-- phone/desktop scale), so bring the wrapper back to design units before mixing the two.
	local uiScale = 1
	local node: Instance? = wrapper
	while node do
		local scale = node:FindFirstChildOfClass("UIScale")
		if scale then
			uiScale *= scale.Scale
		end
		if node:IsA("ScreenGui") then
			break
		end
		node = node.Parent
	end
	local wrapperSize = wrapper.AbsoluteSize / math.max(uiScale, 0.01)
	local slots: { DeckSlot } = {}
	for _, slot in ipairs(raw) do
		local w = wrapperSize.X * slot.size.X.Scale + slot.size.X.Offset
		local h = wrapperSize.Y * slot.size.Y.Scale + slot.size.Y.Offset
		local side = math.min(w, h)
		local anchorX = wrapperSize.X * slot.position.X.Scale + slot.position.X.Offset
		local anchorY = wrapperSize.Y * slot.position.Y.Scale + slot.position.Y.Offset
		local centreX = anchorX + (0.5 - slot.anchor.X) * side
		local centreY = anchorY + (0.5 - slot.anchor.Y) * side
		table.insert(slots, {
			position = UDim2.fromScale(centreX / wrapperSize.X, centreY / wrapperSize.Y),
			size = UDim2.fromScale(side / wrapperSize.X, side / wrapperSize.Y),
			z = slot.z,
			dim = slot.dim,
		})
	end
	return slots
end

function LibraryView:_hideTemplateCovers(hidden: boolean)
	local wrapper = self._refs.detailCover.Parent
	if not wrapper then
		return
	end
	self._refs.detailCover.Visible = not hidden
	for _, name in ipairs({ "BackdropNear", "BackdropFar" }) do
		local frame = wrapper:FindFirstChild(name)
		if frame and frame:IsA("GuiObject") then
			frame.Visible = not hidden
		end
	end
end

function LibraryView:_clearDeck()
	for _, card in ipairs(self._deckCards or {}) do
		card:Destroy()
	end
	self._deckCards = {}
end

function LibraryView:_makeCardTemplate(): ImageLabel
	local template = self._refs.detailCover:Clone()
	for _, child in ipairs(template:GetChildren()) do
		if child.Name == "HzCoverTile" or child:IsA("UIScale") then
			child:Destroy()
		end
	end
	template.Name = "DealtCard"
	template.Visible = true
	template.Image = ""
	local shade = Instance.new("Frame")
	shade.Name = "DeckShade"
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 1
	shade.BorderSizePixel = 0
	shade.Size = UDim2.fromScale(1, 1)
	shade.ZIndex = 10000
	local corner = template:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Clone().Parent = shade
	end
	shade.Parent = template
	return template
end

function LibraryView:_startDeck(selected: string?)
	-- A repaint of the same list keeps the running deck; a new set or a new search re-deals.
	if self._deckItems == self._items and self._deckSelection == selected then
		return
	end
	local wrapper = self._refs.detailCover.Parent
	if not wrapper then
		return
	end
	-- Opening this set from another one animates; the panel's very first paint does not.
	local animate = (self._detailSelection ~= nil or self._detailBases ~= nil) and not UIMotion.reduced()
	self._deckItems = self._items
	self._deckSelection = selected
	self._deckGeneration = (self._deckGeneration or 0) + 1
	local generation = self._deckGeneration

	local order = table.clone(self._items)
	for index = #order, 2, -1 do
		local swap = math.random(index)
		order[index], order[swap] = order[swap], order[index]
	end
	self._deckOrder = order
	self._deckCursor = 0

	self:_clearDeck()
	local slots = self:_deckSlots()
	self._deckSlotList = slots
	local template = self:_makeCardTemplate()
	local cards: { ImageLabel } = {}
	for index = 1, #slots + 1 do
		local card = template:Clone()
		local slot = slots[math.min(index, #slots)]
		if index > #slots then
			self:_placeCard(card, slot, false)
			card.ZIndex = slot.z - 1
		elseif index > 1 then
			-- Invisible until its cover is dealt; when animating, gathered under the front card.
			self:_placeCard(card, if animate then slots[1] else slot, false)
			card.ZIndex = slot.z
		else
			self:_placeCard(card, slot, true)
		end
		card.Parent = wrapper
		table.insert(cards, card)
	end
	template:Destroy()
	self._deckCards = cards
	self:_hideTemplateCovers(true)

	-- Front now; each card behind one frame later, fanning out from under the front as it is dealt.
	self:_dealCard(cards[1], self:_nextDealt())
	if animate then
		UIMotion.popIn(cards[1], 0.94)
	end
	task.spawn(function()
		for index = 2, #cards do
			task.wait()
			if self._deckGeneration ~= generation then
				return
			end
			local card = cards[index]
			self:_dealCard(card, self:_nextDealt())
			if index <= #slots then
				if animate then
					card.ImageTransparency = 0
					shadeOf(card).BackgroundTransparency = 1 - slots[1].dim
					self:_moveCard(card, slots[index], DECK_ENTRANCE_TIMES[index] or BACKDROP_FAR_TIME)
				else
					self:_placeCard(card, slots[index], true)
				end
			end
		end
	end)
	if #order < 2 then
		return
	end

	task.spawn(function()
		while self._deckGeneration == generation do
			task.wait(DECK_INTERVAL)
			if self._deckGeneration ~= generation then
				return
			end
			if shownOnScreen(wrapper :: GuiObject) then
				self:_advanceDeck(generation)
			end
		end
	end)
end

function LibraryView:_advanceDeck(generation: number)
	local cards: { ImageLabel } = self._deckCards
	local slots: { DeckSlot } = self._deckSlotList
	if not cards or #cards < 2 then
		return
	end
	local reduced = UIMotion.reduced()
	local leaving = cards[1]
	local front = slots[1]
	leaving.ZIndex = front.z + 2
	if reduced then
		self:_placeCard(leaving, front, false)
	else
		UIMotion.tween(leaving, DECK_EXIT_TIME, {
			Position = front.position + DECK_EXIT_OFFSET,
			Rotation = DECK_EXIT_ROTATION,
			ImageTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		UIMotion.tween(shadeOf(leaving), DECK_EXIT_TIME, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	for index = 2, #cards do
		local card = cards[index]
		local slot = slots[index - 1]
		if reduced then
			self:_placeCard(card, slot, true)
		else
			self:_moveCard(card, slot, DECK_MOVE_TIME)
		end
	end
	table.remove(cards, 1)
	table.insert(cards, leaving)

	-- Once everything has landed, the card that left becomes the spare: parked in the last slot,
	-- invisible, and dealt the next track — the only cover built in a cycle, and never on screen.
	task.delay(if reduced then 0 else math.max(DECK_MOVE_TIME, DECK_EXIT_TIME) + 0.05, function()
		if self._deckGeneration ~= generation then
			return
		end
		local spareSlot = slots[#slots]
		self:_placeCard(leaving, spareSlot, false)
		leaving.ZIndex = spareSlot.z - 1
		self:_dealCard(leaving, self:_nextDealt())
	end)
end

function LibraryView:_stopDeck()
	if not self._deckItems then
		return
	end
	self._deckItems = nil
	self._deckSelection = nil
	self._deckGeneration = (self._deckGeneration or 0) + 1
	self:_clearDeck()
	self:_hideTemplateCovers(false)
	-- The next ordinary set repaints the backdrops.
	self._backdropSelection = nil
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
	local coverTrack: any = nil
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
			coverTrack = firstTrack
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
	-- All Tracks, New Drops and Liked Tracks have no cover of their own: their stack deals the
	-- listed tracks' covers instead (owner, 2026-09-23).
	local dealt = not djSet and type(playlist) ~= "table" and #self._items > 0
	if dealt then
		self:_startDeck(selected)
	else
		self:_stopDeck()
		if coverTrack then
			Visuals.applyTrackCover(refs.detailCover, coverTrack, self._playlists[coverTrack.playlistId], self._config)
		else
			Visuals.applyCover(refs.detailCover, coverSource, self._config)
		end
		self:_applyBackdropCovers(
			selected,
			coverSource,
			if djSet then djSet.trackIds elseif type(playlist) == "table" then playlist.trackIds else nil
		)
	end

	-- Picking another set: the words fade in, the cover pops forward, and the stack fans out from
	-- behind it. The covers never fade (owner, 2026-09-23: the stack fading in first read as a
	-- glitch) — a card that is already there moving into place is what a stack does.
	if self._detailSelection ~= selected then
		local first = self._detailSelection == nil and self._detailBases == nil
		self._detailSelection = selected
		if not self._detailBases then
			self._detailFade = { refs.detailTitle, refs.detailSubtitle, refs.detailOwnerName }
			self._detailBases = UIMotion.captureBases(self._detailFade)
		end
		if not first then
			UIMotion.fadeIn(self._detailFade, self._detailBases)
			UIMotion.popIn(UIMotion.centred(refs.detailCover), 0.94)
			self:_playBackdropStack()
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
		UIMotion.spin(row.addIcon)
		UIMotion.tween(row.addIcon, 0.2, { ImageTransparency = DISABLED_TRANSPARENCY })
		task.delay(ADD_FEEDBACK_SECONDS, function()
			if row.addToken ~= token then
				return
			end
			addButton.Interactable = true
			UIMotion.tween(row.addIcon, 0.2, { ImageTransparency = 0 })
			UIMotion.pop(row.addIcon, 1.2)
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
		self:_bindMotion(button)
	end
	-- The row itself is a button (tapping it acts on the track), so it takes the motion too.
	self:_bindMotion(instance)
	row.fade = { row.title, row.creator, row.length, row.coverImage }
	row.fadeBases = UIMotion.captureBases(row.fade)
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
		UIMotion.tween(row.likeIcon, 0.2, { ImageTransparency = transparency })
		if liked then
			UIMotion.pop(row.likeIcon, 1.45, 0.14)
		else
			UIMotion.wiggle(row.likeIcon, 10)
		end
	else
		UIMotion.tween(row.likeIcon, 0, { ImageTransparency = transparency })
	end
end

function LibraryView:_bindTrackRow(row: any, track: any, index: number)
	row.trackId = tostring(track.id)
	row.likedShown = nil
	row.addToken += 1
	row.addButton.Interactable = true
	UIMotion.tween(row.addIcon, 0, { ImageTransparency = 0 })
	local restRotation = tonumber(row.addIcon:GetAttribute("UIMotionRotation"))
	if restRotation then
		UIMotion.tween(row.addIcon, 0, { Rotation = restRotation })
	end
	if self._rowEntranceActive then
		UIMotion.fadeIn(row.fade, row.fadeBases, ROW_STAGGER_SECONDS * math.min(self._rowEntranceCount, ROW_STAGGER_MAX))
		self._rowEntranceCount += 1
	end
	Visuals.setText(row.title, tostring(track.name or ""))
	Visuals.setText(row.creator, tostring(track.creator or ""))
	Visuals.setText(row.length, Visuals.formatClock(tonumber(track.totalDuration) or 0))
	local playlist = self._playlists[track.playlistId] or track.playlist
	Visuals.applyTrackCover(
		row.coverImage,
		track,
		playlist,
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
function LibraryView:destroy()
	self:_stopDeck()
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
