--!strict
-- PATH: StarterPlayerScripts/Client/UI/MusicPlayerGuiRefs.lua
-- Resolve semua path GUI 06-MusicPlayerGUI ke typed table.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local SliderSelectorUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.SliderSelectorUtil)

local MusicPlayerGuiRefs = {}

local TAB_KEYS = { "nowPlaying", "reqSong", "dj", "manage" }

export type Refs = {
	-- Root
	root: ScreenGui,
	mainWrapper: Frame,
	mainDragDetector: UIDragDetector?,
	closeButton: TextButton,
	-- Tabs (Header) — 2-SliderSelector + BackgroundPill
	selectorOuter: GuiObject,
	backgroundPill: GuiObject?,
	tabButtonOrder: { TextButton },
	tabs: {
		nowPlaying: TextButton,
		reqSong: TextButton,
		dj: TextButton,
		manage: TextButton,
	},
	-- Now Playing frame
	nowPlayingFrame: CanvasGroup,
	nowPlayingWrapper: Frame,
	trackTitle: TextLabel,
	trackCreator: TextLabel,
	playlistTitle: TextLabel,
	playlistColorOrImage: ImageLabel,
	requesterDisplayName: TextLabel,
	requesterProfilePicture: ImageLabel,
	addToFavoritesButton: TextButton?,
	trackProgressWrapper: Frame,
	controlledByDjInfo: TextButton,
	tipsDynamic: TextButton,
	voteSkipButton: TextButton,
	voteSkipButtonText: TextLabel,
	queueHeaderLabel: TextLabel,
	scrollableQueue: ScrollingFrame,
	queueTemplate: TextButton,
	dependsOnPlaylist: UIGradient?,
	-- SelectSong frame
	selectSongFrame: CanvasGroup,
	searchBox: TextBox,
	scrollablePlaylist: ScrollingFrame,
	favoritesPlaylistButton: TextButton,
	newDropsPlaylistButton: TextButton,
	playlistTemplateNormal: TextButton,
	playlistTemplateSelected: TextButton,
	scrollableTrackLeft: ScrollingFrame,
	trackTemplateLeft: TextButton,
	scrollableTrackRight: ScrollingFrame,
	trackTemplateRight: TextButton,
	djTab: CanvasGroup,
	-- Request by asset ID (optional — newer GUI)
	requestFromIdWrapper: Frame?,
	requestFromIdInput: TextBox?,
	requestFromIdButton: TextButton?,
	-- Utilities modal
	utilitiesModal: Folder,
	utilitiesBackdropBlur: Frame,
	addToQueueConfirmation: Frame,
	addToQueueTrackTemplate: TextButton,
	addToQueueConfirmButton: TextButton,
	addToQueueFavoriteButton: TextButton,
	addToQueueCancelButton: TextButton,
	voteModal: Frame,
	voteCountdownLabel: TextLabel,
	voteLoadingBar: Frame,
	voteLoadingInnerBar: Frame,
	voteDynamicTitle: TextLabel,
	voteTrackTemplate: TextButton,
	voteRejectButton: TextButton,
	voteRejectText: TextLabel,
	voteSkipButtonModal: TextButton,
	voteSkipText: TextLabel,
	-- Playlist-related modal
	playlistRelatedModalFolder: Folder,
	playlistRelatedBackdropBlur: Frame,
	addToPlaylistConfirmation: Frame,
	addToPlaylistTemplate: TextButton,
	addToPlaylistCreateButton: TextButton,
	addToPlaylistCancelButton: TextButton,
	deletePlaylistConfirmation: Frame,
	deletePlaylistTemplate: TextButton,
	deletePlaylistConfirmButton: TextButton,
	deletePlaylistCancelButton: TextButton,
	editPlaylistConfirmation: Frame,
	editPlaylistBeforeTemplate: TextButton,
	editPlaylistAfterTemplate: TextButton,
	editPlaylistSaveButton: TextButton,
	editPlaylistCancelButton: TextButton,
	-- Track-related modal
	trackRelatedModalFolder: Folder,
	trackRelatedBackdropBlur: Frame,
	addToTrackConfirmation: Frame,
	addToTrackPreviewCard: TextButton,
	addToTrackSaveButton: TextButton,
	addToTrackCancelButton: TextButton,
	deleteTrackConfirmation: Frame,
	deleteTrackPreviewCard: TextButton,
	deleteTrackConfirmButton: TextButton,
	deleteTrackCancelButton: TextButton,
	editTrackConfirmation: Frame,
	editTrackBeforeTemplate: TextButton,
	editTrackAfterTemplate: TextButton,
	editTrackSaveButton: TextButton,
	editTrackCancelButton: TextButton,
	-- Manage frame
	manageFrame: CanvasGroup,
	createPlaylistButton: TextButton,
	scrollableManagePlaylist: ScrollingFrame,
	managePlaylistTemplate: TextButton,
	uploadTrackButton: TextButton,
	scrollableManageTrack: ScrollingFrame,
	manageTrackTemplate: TextButton,
	manageTrackTemplateRight: TextButton?,
	manageTrackScrollLeft: Frame?,
	manageTrackScrollRight: Frame?,
	-- Form: Track modal (4-AddorEditTrackModal), Visible = false by default
	formTrack: CanvasGroup,
	formTrackTitle: TextLabel,
	formTrackNameField: Frame,
	formTrackPlaylistField: Frame,
	formTrackIdParts: { Frame },
	formTrackCreatorField: Frame,
	-- Per-track normal playback speed input (NormalPlaybackSpeed frame).
	-- Optional: nil kalau frame belum ada di GUI (backward compat).
	formTrackPlaybackSpeedField: Frame?,
	-- Form: Playlist modal (AddorEditPlaylistModal), Visible = false by default
	formPlaylist: CanvasGroup,
	formPlaylistTitle: TextLabel,
	formPlaylistNameField: Frame,
	formPlaylistCoverField: Frame,
	formPlaylistFontField: Frame,
	formPlaylistVisibilityField: Frame?,
}

-- Helpers

local function expect(parent: Instance, name: string, timeout: number?): Instance
	local child = parent:WaitForChild(name, timeout or 15)
	assert(child, ("MusicPlayerGuiRefs: Missing '%s' under %s"):format(name, parent:GetFullName()))
	return child
end

local function asTextButton(inst: Instance): TextButton
	assert(inst:IsA("TextButton"), ("Expected TextButton, got %s at %s"):format(inst.ClassName, inst:GetFullName()))
	return inst :: TextButton
end

local function asTextLabel(inst: Instance): TextLabel
	assert(inst:IsA("TextLabel"), ("Expected TextLabel, got %s at %s"):format(inst.ClassName, inst:GetFullName()))
	return inst :: TextLabel
end

local function asFrame(inst: Instance): Frame
	assert(inst:IsA("Frame"), ("Expected Frame, got %s at %s"):format(inst.ClassName, inst:GetFullName()))
	return inst :: Frame
end

local function asCanvasGroup(inst: Instance): CanvasGroup
	assert(inst:IsA("CanvasGroup"), ("Expected CanvasGroup, got %s at %s"):format(inst.ClassName, inst:GetFullName()))
	return inst :: CanvasGroup
end

local function asScrollingFrame(inst: Instance): ScrollingFrame
	assert(
		inst:IsA("ScrollingFrame"),
		("Expected ScrollingFrame, got %s at %s"):format(inst.ClassName, inst:GetFullName())
	)
	return inst :: ScrollingFrame
end

local function asTextBox(inst: Instance): TextBox
	assert(inst:IsA("TextBox"), ("Expected TextBox, got %s at %s"):format(inst.ClassName, inst:GetFullName()))
	return inst :: TextBox
end

local function asImageLabel(inst: Instance): ImageLabel
	assert(inst:IsA("ImageLabel"), ("Expected ImageLabel, got %s at %s"):format(inst.ClassName, inst:GetFullName()))
	return inst :: ImageLabel
end

local function findFirstDescendantByNames(root: Instance?, names: { string }): Instance?
	if not root then
		return nil
	end

	for _, name in ipairs(names) do
		local candidate = root:FindFirstChild(name, true)
		if candidate then
			return candidate
		end
	end

	return nil
end

local function expectFirstDescendantByNames(root: Instance?, names: { string }): Instance
	local candidate = findFirstDescendantByNames(root, names)
	assert(
		candidate,
		("MusicPlayerGuiRefs: Missing one of [%s] under %s"):format(table.concat(names, ", "), root and root:GetFullName() or "nil")
	)
	return candidate
end

local function asFolder(inst: Instance): Folder
	assert(inst:IsA("Folder"), ("Expected Folder, got %s at %s"):format(inst.ClassName, inst:GetFullName()))
	return inst :: Folder
end

type ResolvedTabs = {
	nowPlaying: TextButton,
	reqSong: TextButton,
	dj: TextButton,
	manage: TextButton,
}

local SLIDER_SELECTOR_NAMES = { "2-SliderSelector", "SliderSelector" }

local function describeChildNames(parent: Instance): string
	local names = {}
	for _, child in ipairs(parent:GetChildren()) do
		table.insert(names, child.Name)
	end
	return table.concat(names, ", ")
end

local function findSliderSelectorOuter(headerWrapper: Instance): GuiObject?
	for _, name in ipairs(SLIDER_SELECTOR_NAMES) do
		local direct = headerWrapper:FindFirstChild(name)
		if direct and direct:IsA("GuiObject") then
			return direct :: GuiObject
		end
	end
	return nil
end

local function waitForSliderSelectorOuter(headerWrapper: Instance, timeout: number): GuiObject?
	local existing = findSliderSelectorOuter(headerWrapper)
	if existing then
		return existing
	end

	for _, name in ipairs(SLIDER_SELECTOR_NAMES) do
		local waited = headerWrapper:WaitForChild(name, timeout)
		if waited and waited:IsA("GuiObject") then
			return waited :: GuiObject
		end
	end

	return findSliderSelectorOuter(headerWrapper)
end

local function findTabButtonFallback(searchRoot: Instance, legacyName: string?): TextButton?
	if type(legacyName) ~= "string" or legacyName == "" then
		return nil
	end

	local found = searchRoot:FindFirstChild(legacyName, true)
	if found and found:IsA("TextButton") then
		return found :: TextButton
	end

	return nil
end

local function resolveHeaderTabs(
	headerWrapper: Frame,
	mainWrapper: Frame
): (GuiObject, GuiObject?, ResolvedTabs, { TextButton })
	local legacyNames = Config.Music.TAB_LEGACY_BUTTON_NAMES
	local tabLabels = Config.Music.TAB_LABELS

	local sliderOuter = waitForSliderSelectorOuter(headerWrapper, 10)
	if sliderOuter then
		local container = SliderSelectorUtil.getOptionsContainer(sliderOuter)
		local backgroundPill = SliderSelectorUtil.getBackgroundPill(sliderOuter)
		local allButtons = SliderSelectorUtil.collectTabButtons(container)

		local tabButtonOrder: { TextButton } = {}
		local resolved: { [string]: TextButton } = {}

		for index, key in ipairs(TAB_KEYS) do
			local legacyName = legacyNames[key]
			local spec = {
				legacyNames = if legacyName then { legacyName } else nil,
				optionIndex = index,
				defaultLabel = tabLabels[key],
			}
			local button = SliderSelectorUtil.resolveTabButton(container, spec, allButtons)
				or findTabButtonFallback(mainWrapper, legacyName)
			assert(
				button,
				("MusicPlayerGuiRefs: missing tab '%s' (need Option%d or %s). Children of %s: [%s]"):format(
					key,
					index,
					tostring(legacyName),
					container:GetFullName(),
					describeChildNames(container)
				)
			)
			resolved[key] = button
			table.insert(tabButtonOrder, button)
			local label = tabLabels[key]
			if type(label) == "string" and label ~= "" then
				SliderSelectorUtil.applyTabLabel(button, label)
			end
		end

		local tabs: ResolvedTabs = {
			nowPlaying = resolved.nowPlaying,
			reqSong = resolved.reqSong,
			dj = resolved.dj,
			manage = resolved.manage,
		}
		return sliderOuter, backgroundPill, tabs, tabButtonOrder
	end

	-- Legacy header (Selector + named tab buttons)
	local selectorRaw = headerWrapper:FindFirstChild("Selector", true)
	assert(
		selectorRaw and selectorRaw:IsA("Frame"),
		("MusicPlayerGuiRefs: missing header tabs under %s (expected 2-SliderSelector or Selector). Children: [%s]"):format(
			headerWrapper:GetFullName(),
			describeChildNames(headerWrapper)
		)
	)
	local selector = asFrame(selectorRaw)
	local tabs: ResolvedTabs = {
		nowPlaying = asTextButton(expect(selector, legacyNames.nowPlaying)),
		reqSong = asTextButton(expect(selector, legacyNames.reqSong)),
		dj = asTextButton(expect(selector, legacyNames.dj)),
		manage = asTextButton(expect(selector, legacyNames.manage)),
	}
	return selector, nil, tabs, { tabs.nowPlaying, tabs.reqSong, tabs.dj, tabs.manage }
end

-- Resolve

function MusicPlayerGuiRefs.resolve(playerGui: PlayerGui): Refs
	local root = expect(playerGui, "06-MusicPlayerGUI") :: ScreenGui
	local mainWrapper = asFrame(expect(root, "MainWrapper"))
	local mainDragDetector = mainWrapper:FindFirstChildWhichIsA("UIDragDetector")

	-- UIScale untuk pop animation, buat runtime jika belum ada di GUI
	local uiScale: UIScale
	do
		local existing = mainWrapper:FindFirstChildWhichIsA("UIScale")
		if existing then
			uiScale = existing :: UIScale
		else
			uiScale = Instance.new("UIScale")
			uiScale.Name = "RuntimeUIScale"
			uiScale.Scale = 1
			uiScale.Parent = mainWrapper
		end
	end

	-- Header (2-SliderSelector + pill, legacy Selector fallback)
	local headerWrapperRaw = mainWrapper:FindFirstChild("01-HeaderWrapper")
		or mainWrapper:WaitForChild("01-HeaderWrapper", 10)
		or mainWrapper:FindFirstChild("1-HeaderWrapper")
	assert(
		headerWrapperRaw and headerWrapperRaw:IsA("Frame"),
		("MusicPlayerGuiRefs: missing 01-HeaderWrapper under %s"):format(mainWrapper:GetFullName())
	)
	local headerWrapper = asFrame(headerWrapperRaw)
	local selectorOuter, backgroundPill, tabs, tabButtonOrder = resolveHeaderTabs(headerWrapper, mainWrapper)
	local closeButton = asTextButton(
		headerWrapper:FindFirstChild("99-CloseModalButton")
		or expect(mainWrapper, "99-CloseModalButton")
	)

	-- Now Playing frame
	local nowPlayingFrame = asCanvasGroup(expect(mainWrapper, "3-NowPlayingFrame"))
	local nowPlayingWrapper = asFrame(expect(nowPlayingFrame, "1-NowPlayingWrapper"))
	local nowPlayingContent: Instance = nowPlayingWrapper
	local outer = nowPlayingWrapper:FindFirstChild("Outer")
	if outer then
		nowPlayingContent = asFrame(outer)
	else
		nowPlayingContent = nowPlayingWrapper
	end

	-- TrackInfo -> TrackIdentity + Track
	local trackInfoRoot = asFrame(expect(nowPlayingContent, "TrackInfo"))
	local trackIdentity = asFrame(expect(trackInfoRoot, "TrackIdentity"))
	local relatedPlaylistWrapper = asFrame(expect(trackIdentity, "RelatedPlaylistWrapper"))
	local requesterInfoWrapper = asFrame(expect(trackIdentity, "RequesterInfoWrapper"))
	local trackFrame = asFrame(expect(trackInfoRoot, "Track"))
	local playlistTitle = asTextLabel(expect(relatedPlaylistWrapper, "2-PlaylistTitle"))
	local playlistColorOrImage = asImageLabel(expect(relatedPlaylistWrapper, "3-PlaylistColororImage"))
	local requesterDisplayName = asTextLabel(expect(requesterInfoWrapper, "2-RequesterDisplayName"))
	local requesterProfilePicture = asImageLabel(expect(requesterInfoWrapper, "3-RequesterProfilePicture"))
	local trackTitle = asTextLabel(expect(trackFrame, "1-TrackTitle"))
	local trackCreator = asTextLabel(expect(trackFrame, "2-TrackCreator"))
	local dependsOnPlaylist: UIGradient? = nil
	do
		local gradient = nowPlayingContent:FindFirstChild("BackgroundNowPlaying(DependsonPlaylist)")
		if gradient and gradient:IsA("UIGradient") then
			dependsOnPlaylist = gradient :: UIGradient
		end
	end

	-- Tracker
	local tracker = asFrame(expect(nowPlayingContent, "NowPlayingTracker"))
	local trackProgressWrapper = asFrame(expect(tracker, "TrackProgressWrapper"))
	local addToFavoritesButton: TextButton? = nil
	do
		local favoriteCandidate = findFirstDescendantByNames(nowPlayingContent, {
			"AddToFavoritesButton",
			"AddtoMyFavoritesListButton",
		})
		if favoriteCandidate and favoriteCandidate:IsA("TextButton") then
			addToFavoritesButton = favoriteCandidate :: TextButton
		end
	end
	local voteSkipButton = asTextButton(expectFirstDescendantByNames(tracker, { "VoteSkipButton" }))
	local voteSkipButtonText = asTextLabel(expect(voteSkipButton, "TextLabel"))
	local controlledByDjInfo = asTextButton(expect(trackFrame, "ControlledbyDJInfo"))
	local tipsDynamic = asTextButton(expect(trackFrame, "TipsDynamic"))

	-- Queue
	local queueSection = asFrame(expect(nowPlayingFrame, "2-QueueSectionWrapper"))
	local queueHeaderLabel = asTextLabel(expect(queueSection, "1-TextLabel"))
	local scrollableQueue = asScrollingFrame(expect(queueSection, "ScrollableQueue"))
	local queueTemplate = asTextButton(expect(scrollableQueue, "QueueListTemplate"))

	-- SelectSong frame
	local selectSongFrame = asCanvasGroup(expect(mainWrapper, "4-SelectSongFrame"))

	-- Left panel: playlists
	local selectPlaylistPanel = asFrame(expect(selectSongFrame, "1-SelectPlaylist"))
	local searchBox = asTextBox(expect(selectPlaylistPanel, "01-SearchSong"))
	local scrollablePlaylistWrap = asCanvasGroup(expect(selectPlaylistPanel, "ScrollablePlaylistWrapper"))
	local scrollablePlaylist = asScrollingFrame(expect(scrollablePlaylistWrap, "ScrollablePlaylist"))
	local favoritesPlaylistButton = asTextButton(expect(scrollablePlaylist, "FavoritesPlaylistTabButton"))
	local newDropsPlaylistButton = asTextButton(expect(scrollablePlaylist, "NewDropsTabButton"))
	local playlistTemplateNormal = asTextButton(expect(scrollablePlaylist, "PlaylistTemplateNormal"))
	local playlistTemplateSelected = asTextButton(expect(scrollablePlaylist, "PlaylistTemplateSelected"))

	-- Right panel: tracks (2 columns)
	local selectSongPanel = asFrame(expect(selectSongFrame, "2-SelectSong"))
	local trackListLeft = asFrame(expect(selectSongPanel, "TrackListLeft"))
	local scrollableTrackLeft = asScrollingFrame(expect(trackListLeft, "ScrollableTrackList"))
	local trackTemplateLeft = asTextButton(
		expectFirstDescendantByNames(scrollableTrackLeft, {
			"TrackWrapperTemplate",
			"TrackWrapperTemplateImageType",
		})
	)
	local trackListRight = asFrame(expect(selectSongPanel, "TrackListRight"))
	local scrollableTrackRight = asScrollingFrame(expect(trackListRight, "ScrollablePlayerList"))
	local trackTemplateRight = asTextButton(
		expectFirstDescendantByNames(scrollableTrackRight, {
			"TrackWrapperTemplate",
			"TrackWrapperTemplateImageType",
		})
	)

	local requestFromIdWrapperRaw = selectSongPanel:FindFirstChild("Request From ID")
	local requestFromIdWrapper: Frame? = if requestFromIdWrapperRaw and requestFromIdWrapperRaw:IsA("Frame")
		then requestFromIdWrapperRaw :: Frame
		else nil
	local requestFromIdInput: TextBox? = nil
	local requestFromIdButton: TextButton? = nil
	if requestFromIdWrapper then
		for _, child in ipairs(requestFromIdWrapper:GetChildren()) do
			if not requestFromIdInput and child:IsA("TextBox") then
				requestFromIdInput = child :: TextBox
			elseif not requestFromIdButton and child:IsA("TextButton") then
				requestFromIdButton = child :: TextButton
			end
		end
	end

	local djTab = asCanvasGroup(expect(mainWrapper, "6-DJTab"))

	-- Utilities modal
	local utilitiesModal = expect(root, "UtilitesModal")
	local utilitiesBackdropBlur = asFrame(expect(utilitiesModal, "BackdropBlur"))
	local addToQueueConfirmation = asFrame(expect(utilitiesModal, "AddtoQueueConfirmation"))
	local addToQueueTrackTemplate = asTextButton(expect(addToQueueConfirmation, "TrackWrapperTemplate"))
	local addToQueueConfirmButton = asTextButton(expect(addToQueueConfirmation, "AddtoQueueButton"))
	local addToQueueFavoriteButton = asTextButton(expect(addToQueueConfirmation, "AddtoMyFavoritesListButton"))
	local addToQueueCancelButton = asTextButton(expect(addToQueueConfirmation, "CancelButton"))
	local voteModal = asFrame(expect(utilitiesModal, "VoteModal"))
	local voteCountdownWrapper = asFrame(expect(voteModal, "CountdownWrapper"))
	local voteCountdownLabel = asTextLabel(expect(voteCountdownWrapper, "CountDown"))
	local voteLoadingBar = asFrame(expect(voteModal, "LoadingBar"))
	local voteLoadingInnerBar = asFrame(expect(voteLoadingBar, "InnerBar"))
	local voteDynamicTitle = asTextLabel(expect(voteModal, "DynamicVoteTitle"))
	local voteTrackTemplate = asTextButton(expect(voteModal, "TrackWrapperTemplate"))
	local voteInputWrapper = asFrame(expect(voteModal, "InputWrapper"))
	local voteRejectButton = asTextButton(expect(voteInputWrapper, "RejectSkipButton"))
	local voteRejectText = asTextLabel(expect(voteRejectButton, "DynamicRejectText"))
	local voteSkipButtonModal = asTextButton(expect(voteInputWrapper, "SkipButtonVote"))
	local voteSkipText = asTextLabel(expect(voteSkipButtonModal, "DynamicSkipText"))

	local formTrack = asCanvasGroup(expect(utilitiesModal, "4-AddorEditTrackModal"))
	local formTrackHeader = asFrame(expect(formTrack, "Frame"))
	local formTrackTitle = asTextLabel(expect(formTrackHeader, "AddorEditTrackTitle"))
	local formTrackActionWrapper = asFrame(expect(formTrack, "ActionableWrapper"))
	local formTrackUploadButton = asTextButton(expect(formTrackActionWrapper, "UploadorSaveTrackButton"))
	local formTrackScrollable = asScrollingFrame(expect(formTrack, "ScrollablePlayerList"))
	local formTrackNameField = asFrame(expect(formTrackScrollable, "1-TrackName"))
	local formTrackPlaylistFieldRaw = formTrackScrollable:FindFirstChild("2-SelectPlaylist")
		or formTrackScrollable:FindFirstChild("3-SelectPlaylist")
		or formTrackScrollable:FindFirstChild("SelectPlaylist")
	assert(formTrackPlaylistFieldRaw, "MusicPlayerGuiRefs: Missing SelectPlaylist field under " .. formTrackScrollable:GetFullName())
	local formTrackPlaylistField = asFrame(formTrackPlaylistFieldRaw)
	-- Collect all TrackIDPart fields (2-TrackIDPart1 .. 2-TrackIDPart9).
	-- Loop sampe 10 buat tolerant kalau nanti ada slot ke-10 ditambah,
	-- tapi server cap di Config.Music.MAX_TRACK_PARTS (default 9).
	local formTrackIdParts: { Frame } = {}
	for i = 1, 10 do
		local part = formTrackScrollable:FindFirstChild("2-TrackIDPart" .. i)
		if part and part:IsA("Frame") then
			table.insert(formTrackIdParts, part :: Frame)
		end
	end
	local formTrackCreatorFieldRaw = formTrackScrollable:FindFirstChild("2-SelectCreator")
		or formTrackScrollable:FindFirstChild("3-SelectCreator")
		or formTrackScrollable:FindFirstChild("4-SelectCreator")
		or formTrackScrollable:FindFirstChild("SelectCreator")
	assert(formTrackCreatorFieldRaw, "MusicPlayerGuiRefs: Missing SelectCreator field under " .. formTrackScrollable:GetFullName())
	local formTrackCreatorField = asFrame(formTrackCreatorFieldRaw)
	-- Per-track playback speed field. Optional (older kits may not have it).
	-- Tolerant ke variasi naming: NormalPlaybackSpeed (preferred),
	-- NormalPlayBackSpeed (legacy capitalization), atau PlaybackSpeed.
	local formTrackPlaybackSpeedFieldRaw = formTrackScrollable:FindFirstChild("NormalPlaybackSpeed")
		or formTrackScrollable:FindFirstChild("NormalPlayBackSpeed")
		or formTrackScrollable:FindFirstChild("PlaybackSpeed")
	local formTrackPlaybackSpeedField: Frame? = if formTrackPlaybackSpeedFieldRaw and formTrackPlaybackSpeedFieldRaw:IsA("Frame")
		then formTrackPlaybackSpeedFieldRaw :: Frame
		else nil

	local formPlaylist = asCanvasGroup(expect(utilitiesModal, "AddorEditPlaylistModal"))
	local formPlaylistHeaderRaw = formPlaylist:FindFirstChild("Header") or formPlaylist:FindFirstChild("Frame")
	assert(formPlaylistHeaderRaw, "MusicPlayerGuiRefs: Missing Header/Frame under " .. formPlaylist:GetFullName())
	local formPlaylistHeader = asFrame(formPlaylistHeaderRaw)
	local formPlaylistTitleRaw = formPlaylistHeader:FindFirstChild("CreateorCustomPlaylistTitle")
		or formPlaylistHeader:FindFirstChild("AddorEditTrackTitle")
		or formPlaylistHeader:FindFirstChild("AddorEditPlaylistTitle")
		or formPlaylistHeader:FindFirstChild("TextLabel")
	assert(formPlaylistTitleRaw, "MusicPlayerGuiRefs: Missing playlist title TextLabel under " .. formPlaylistHeader:GetFullName())
	local formPlaylistTitle = asTextLabel(formPlaylistTitleRaw)
	local formPlaylistActionWrapper = asFrame(expect(formPlaylist, "ActionableWrapper"))
	local formPlaylistScrollable = asScrollingFrame(expect(formPlaylist, "ScrollablePlayerList"))
	local formPlaylistNameField = asFrame(expect(formPlaylistScrollable, "1-PlaylistName"))
	local formPlaylistCoverField = asFrame(expect(formPlaylistScrollable, "2-CustomizeCover"))
	local formPlaylistFontField = asFrame(expect(formPlaylistScrollable, "3-SelectFontFace"))
	local formPlaylistVisibilityRaw = formPlaylistScrollable:FindFirstChild("4-PlaylistVisibility")
	local formPlaylistVisibilityField: Frame? = if formPlaylistVisibilityRaw and formPlaylistVisibilityRaw:IsA("Frame")
		then formPlaylistVisibilityRaw :: Frame
		else nil

	-- Playlist-related modal
	local playlistRelatedModalFolder = asFolder(expect(root, "PlaylistRelatedModal"))
	local playlistRelatedBackdropBlur = asFrame(expect(playlistRelatedModalFolder, "BackdropBlur"))
	local addToPlaylistConfirmation = asFrame(expect(playlistRelatedModalFolder, "AddtoPlaylistConfirmation"))
	local addToPlaylistTemplate = asTextButton(expect(addToPlaylistConfirmation, "PlaylistTemplate"))
	local addToPlaylistCreateButton = asTextButton(expect(addToPlaylistConfirmation, "CreatePlaylistButton"))
	local addToPlaylistCancelButton = asTextButton(expect(addToPlaylistConfirmation, "CancelButton"))
	local deletePlaylistConfirmation = asFrame(expect(playlistRelatedModalFolder, "DeleteTrackConfirmation"))
	local deletePlaylistTemplate = asTextButton(expect(deletePlaylistConfirmation, "PlaylistTemplate"))
	local deletePlaylistConfirmButton = asTextButton(expect(deletePlaylistConfirmation, "DeletePlaylistButton"))
	local deletePlaylistCancelButton = asTextButton(expect(deletePlaylistConfirmation, "CancelButton"))
	local editPlaylistConfirmation = asFrame(expect(playlistRelatedModalFolder, "EditTrackConfirmation"))
	local editPlaylistBeforeTemplate = asTextButton(expect(editPlaylistConfirmation, "PlaylistTemplateBefore"))
	local editPlaylistAfterTemplate = asTextButton(expect(editPlaylistConfirmation, "PlaylistTemplateAfter"))
	local editPlaylistSaveButton = asTextButton(expect(editPlaylistConfirmation, "SavePlaylistUpdate"))
	local editPlaylistCancelButton = asTextButton(expect(editPlaylistConfirmation, "CancelButton"))

	-- Track-related modal
	local trackRelatedModalFolder = asFolder(expect(root, "TrackRelatedModal"))
	local trackRelatedBackdropBlur = asFrame(expect(trackRelatedModalFolder, "BackdropBlur"))
	local addToTrackConfirmation = asFrame(expect(trackRelatedModalFolder, "AddtoTrackConfirmation"))
	local addToTrackPreviewCard = asTextButton(expect(addToTrackConfirmation, "TrackWrapper"))
	local addToTrackSaveButton = asTextButton(expect(addToTrackConfirmation, "SaveTrackButton"))
	local addToTrackCancelButton = asTextButton(expect(addToTrackConfirmation, "CancelButton"))
	local deleteTrackConfirmation = asFrame(expect(trackRelatedModalFolder, "DeleteTrackConfirmation"))
	local deleteTrackPreviewCard = asTextButton(expect(deleteTrackConfirmation, "TrackWrapper"))
	local deleteTrackConfirmButton = asTextButton(expect(deleteTrackConfirmation, "DeleteTrack"))
	local deleteTrackCancelButton = asTextButton(expect(deleteTrackConfirmation, "CancelButton"))
	local editTrackConfirmation = asFrame(expect(trackRelatedModalFolder, "EditTrackConfirmation"))
	local editTrackBeforeTemplate = asTextButton(expect(editTrackConfirmation, "TrackBefore"))
	local editTrackAfterTemplate = asTextButton(expect(editTrackConfirmation, "TrackAfter"))
	local editTrackSaveButton = asTextButton(expect(editTrackConfirmation, "SaveUpdateButton"))
	local editTrackCancelButton = asTextButton(expect(editTrackConfirmation, "CancelButton"))

	-- Manage frame
	local manageFrame = asCanvasGroup(expect(mainWrapper, "5-ManageFrame"))

	-- Playlist section
	local playlistSection = asFrame(expect(manageFrame, "1-PlaylistSection"))
	local managePlaylistWrap = asCanvasGroup(expect(playlistSection, "ScrollablePlaylistWrapper"))
	local manageScrollPl = asScrollingFrame(expect(managePlaylistWrap, "ScrollablePlaylist"))
	local createPlaylistButton = asTextButton(expect(manageScrollPl, "1-CreateNewPlaylistButton"))
	local managePlaylistTemplate = asTextButton(expect(manageScrollPl, "PlaylistTemplate"))

	-- Track section
	local trackSection = asFrame(expect(manageFrame, "2-TrackSection"))
	local manageScrollTr = asScrollingFrame(expect(trackSection, "ScrollableTrackList"))
	-- In the new GUI, upload button and template live inside a "Left" sub-frame
	local manageScrollTrLeftRaw = manageScrollTr:FindFirstChild("Left")
	local manageScrollTrLeft: Frame? = if manageScrollTrLeftRaw and manageScrollTrLeftRaw:IsA("Frame")
		then manageScrollTrLeftRaw :: Frame
		else nil
	local manageScrollTrContainer = manageScrollTrLeft or manageScrollTr :: Instance
	local uploadTrackButton = asTextButton(expect(manageScrollTrContainer, "1-UploadNewTrackButton"))
	local manageTrackTemplate = asTextButton(expect(manageScrollTrContainer, "TrackTemplate"))
	-- Right column (optional — only in the new GUI)
	local manageScrollTrRightRaw = manageScrollTr:FindFirstChild("Right")
	local manageScrollTrRight: Frame? = if manageScrollTrRightRaw and manageScrollTrRightRaw:IsA("Frame")
		then manageScrollTrRightRaw :: Frame
		else nil
	local manageTrackTemplateRight: TextButton? = nil
	if manageScrollTrRight then
		local tmpl = manageScrollTrRight:FindFirstChild("TrackTemplate")
		if tmpl and tmpl:IsA("TextButton") then
			manageTrackTemplateRight = tmpl :: TextButton
		end
	end

	return {
		root = root,
		mainWrapper = mainWrapper,
		mainDragDetector = mainDragDetector,
		closeButton = closeButton,
		selectorOuter = selectorOuter,
		backgroundPill = backgroundPill,
		tabButtonOrder = tabButtonOrder,
		tabs = tabs,

		nowPlayingFrame = nowPlayingFrame,
		nowPlayingWrapper = nowPlayingWrapper,
		trackTitle = trackTitle,
		trackCreator = trackCreator,
		playlistTitle = playlistTitle,
		playlistColorOrImage = playlistColorOrImage,
		requesterDisplayName = requesterDisplayName,
		requesterProfilePicture = requesterProfilePicture,
		addToFavoritesButton = addToFavoritesButton,
		trackProgressWrapper = trackProgressWrapper,
		controlledByDjInfo = controlledByDjInfo,
		tipsDynamic = tipsDynamic,
		voteSkipButton = voteSkipButton,
		voteSkipButtonText = voteSkipButtonText,
		queueHeaderLabel = queueHeaderLabel,
		scrollableQueue = scrollableQueue,
		queueTemplate = queueTemplate,
		dependsOnPlaylist = dependsOnPlaylist,

		selectSongFrame = selectSongFrame,
		searchBox = searchBox,
		scrollablePlaylist = scrollablePlaylist,
		favoritesPlaylistButton = favoritesPlaylistButton,
		newDropsPlaylistButton = newDropsPlaylistButton,
		playlistTemplateNormal = playlistTemplateNormal,
		playlistTemplateSelected = playlistTemplateSelected,
		scrollableTrackLeft = scrollableTrackLeft,
		trackTemplateLeft = trackTemplateLeft,
		scrollableTrackRight = scrollableTrackRight,
		trackTemplateRight = trackTemplateRight,
		requestFromIdWrapper = requestFromIdWrapper,
		requestFromIdInput = requestFromIdInput,
		requestFromIdButton = requestFromIdButton,
		djTab = djTab,
		utilitiesModal = utilitiesModal,
		utilitiesBackdropBlur = utilitiesBackdropBlur,
		addToQueueConfirmation = addToQueueConfirmation,
		addToQueueTrackTemplate = addToQueueTrackTemplate,
		addToQueueConfirmButton = addToQueueConfirmButton,
		addToQueueFavoriteButton = addToQueueFavoriteButton,
		addToQueueCancelButton = addToQueueCancelButton,
		voteModal = voteModal,
		voteCountdownLabel = voteCountdownLabel,
		voteLoadingBar = voteLoadingBar,
		voteLoadingInnerBar = voteLoadingInnerBar,
		voteDynamicTitle = voteDynamicTitle,
		voteTrackTemplate = voteTrackTemplate,
		voteRejectButton = voteRejectButton,
		voteRejectText = voteRejectText,
		voteSkipButtonModal = voteSkipButtonModal,
		voteSkipText = voteSkipText,
		playlistRelatedModalFolder = playlistRelatedModalFolder,
		playlistRelatedBackdropBlur = playlistRelatedBackdropBlur,
		addToPlaylistConfirmation = addToPlaylistConfirmation,
		addToPlaylistTemplate = addToPlaylistTemplate,
		addToPlaylistCreateButton = addToPlaylistCreateButton,
		addToPlaylistCancelButton = addToPlaylistCancelButton,
		deletePlaylistConfirmation = deletePlaylistConfirmation,
		deletePlaylistTemplate = deletePlaylistTemplate,
		deletePlaylistConfirmButton = deletePlaylistConfirmButton,
		deletePlaylistCancelButton = deletePlaylistCancelButton,
		editPlaylistConfirmation = editPlaylistConfirmation,
		editPlaylistBeforeTemplate = editPlaylistBeforeTemplate,
		editPlaylistAfterTemplate = editPlaylistAfterTemplate,
		editPlaylistSaveButton = editPlaylistSaveButton,
		editPlaylistCancelButton = editPlaylistCancelButton,
		trackRelatedModalFolder = trackRelatedModalFolder,
		trackRelatedBackdropBlur = trackRelatedBackdropBlur,
		addToTrackConfirmation = addToTrackConfirmation,
		addToTrackPreviewCard = addToTrackPreviewCard,
		addToTrackSaveButton = addToTrackSaveButton,
		addToTrackCancelButton = addToTrackCancelButton,
		deleteTrackConfirmation = deleteTrackConfirmation,
		deleteTrackPreviewCard = deleteTrackPreviewCard,
		deleteTrackConfirmButton = deleteTrackConfirmButton,
		deleteTrackCancelButton = deleteTrackCancelButton,
		editTrackConfirmation = editTrackConfirmation,
		editTrackBeforeTemplate = editTrackBeforeTemplate,
		editTrackAfterTemplate = editTrackAfterTemplate,
		editTrackSaveButton = editTrackSaveButton,
		editTrackCancelButton = editTrackCancelButton,

		manageFrame = manageFrame,
		createPlaylistButton = createPlaylistButton,
		scrollableManagePlaylist = manageScrollPl,
		managePlaylistTemplate = managePlaylistTemplate,
		uploadTrackButton = uploadTrackButton,
		scrollableManageTrack = manageScrollTr,
		manageTrackTemplate = manageTrackTemplate,
		manageTrackTemplateRight = manageTrackTemplateRight,
		manageTrackScrollLeft = manageScrollTrLeft,
		manageTrackScrollRight = manageScrollTrRight,

		formTrack = formTrack,
		formTrackTitle = formTrackTitle,
		formTrackNameField = formTrackNameField,
		formTrackPlaylistField = formTrackPlaylistField,
		formTrackIdParts = formTrackIdParts,
		formTrackCreatorField = formTrackCreatorField,
		formTrackPlaybackSpeedField = formTrackPlaybackSpeedField,

		formPlaylist = formPlaylist,
		formPlaylistTitle = formPlaylistTitle,
		formPlaylistNameField = formPlaylistNameField,
		formPlaylistCoverField = formPlaylistCoverField,
		formPlaylistFontField = formPlaylistFontField,
		formPlaylistVisibilityField = formPlaylistVisibilityField,
	}
end

return MusicPlayerGuiRefs
