--!strict
-- PATH: StarterPlayerScripts/Client/UI/Music/GuiRefs.luau
-- Resolves the 06-MusicPlayerGUIv3 tree once. One name = one element: a missing or renamed
-- instance fails loudly here instead of silently degrading later (no fallbacks, no variants).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local GuiRefs = {}

export type NowPlayingRefs = {
	hero: Frame,
	djStage: Frame,
	trackTitle: TextLabel,
	trackCreator: TextLabel,
	cover: ImageLabel,
	requesterName: TextLabel,
	requesterAvatar: ImageLabel,
	playlistTitle: TextLabel,
	playlistCover: ImageLabel,
	elapsedLabel: TextLabel,
	lengthLabel: TextLabel,
	progressFill: Frame,
	voteSkipButton: TextButton,
	voteSkipLabel: TextLabel,
	clearQueueButton: TextButton,
	transportButtons: { TextButton },
	djName: TextLabel,
	djAvatar: ImageLabel,
	djNowPlaying: TextLabel,
	djPlaylistTitle: TextLabel,
	djControlledLabel: TextLabel,
}

export type VoteRefs = {
	modal: Frame,
	backdrop: Frame,
	title: TextLabel,
	barFill: Frame,
	rejectButton: TextButton,
	rejectLabel: TextLabel,
	skipButton: TextButton,
	skipLabel: TextLabel,
	card: TextButton,
	cardCover: ImageLabel,
	cardPlaylistName: TextLabel,
	cardTitle: TextLabel,
	cardLength: TextLabel,
	cardCreator: TextLabel,
	cardAddWrapper: Frame,
}

export type LibraryRefs = {
	searchBox: TextBox,
	playlistScroll: ScrollingFrame,
	favoritesButton: TextButton,
	newDropsButton: TextButton,
	detail: Frame,
	detailCover: ImageLabel,
	detailOwnerAvatar: ImageLabel,
	detailTitle: TextLabel,
	detailSubtitle: TextLabel,
	detailOwnerName: TextLabel,
	detailLevelLabel: TextLabel,
	shuffleButton: ImageButton,
	addSetButton: ImageButton,
	trackPanel: Frame,
	trackScroll: ScrollingFrame,
	trackContainer: Frame,
	privateWall: Frame,
	requestFromId: Frame,
	requestInput: TextBox,
	requestButton: TextButton,
}

export type DjRefs = {
	modeToggle: TextButton,
	modeToggleTrack: Frame,
	modeToggleThumb: Frame,
	warning: Frame,
	resetButton: TextButton,
	speedValueLabel: TextLabel,
	speedSliderHost: Frame,
	speedSliderFill: Frame,
	speedPresetWrapper: Frame,
}

export type Refs = {
	root: ScreenGui,
	mainWrapper: Frame,
	dragDetector: UIDragDetector,
	closeButton: TextButton,
	-- Header tabs (2-SliderSelector)
	tabButtons: { nowplaying: TextButton, request: TextButton, dj: TextButton },
	tabButtonOrder: { TextButton },
	backgroundPill: Frame,
	-- Tab pages
	tabFrames: { nowplaying: Frame, request: Frame, dj: Frame },
	nowPlaying: NowPlayingRefs,
	vote: VoteRefs,
	library: LibraryRefs,
	dj: DjRefs,
	-- Row templates (hidden at bind, cloned by the views)
	queueRowTemplate: TextButton,
	playlistTemplates: {
		nonImageSelected: TextButton,
		nonImageNormal: TextButton,
		imageSelected: TextButton,
		imageNormal: TextButton,
		djSetNormal: TextButton,
		djSetSelected: TextButton,
	},
	trackRowTemplate: TextButton,
	soundBoardItemTemplate: TextButton,
	effectTemplate: Frame,
	voteModal: Frame,
	voteTrackTemplate: TextButton,
	backdropBlur: Frame,
}

function GuiRefs.need(parent: Instance, name: string, className: string): any
	local child = parent:FindFirstChild(name)
	assert(child ~= nil, string.format("[MusicGuiRefs] missing %s.%s", parent:GetFullName(), name))
	assert(
		child:IsA(className),
		string.format("[MusicGuiRefs] %s is %s, expected %s", child:GetFullName(), child.ClassName, className)
	)
	return child
end

local need = GuiRefs.need

local function resolveNowPlaying(page: Frame): NowPlayingRefs
	local hero = need(page, "NowPlayingWrapper", "Frame")
	local heroOuter = need(hero, "Outer", "Frame")
	local tracker = need(heroOuter, "NowPlayingTracker", "Frame")
	local progress = need(tracker, "TrackProgressWrapper", "Frame")
	local numbers = need(progress, "Number", "Frame")
	local controls = need(tracker, "DJControl", "Frame")
	local voteSkipButton = need(controls, "VoteSkipButton", "TextButton")
	local trackInfo = need(heroOuter, "TrackInfo", "Frame")
	local track = need(trackInfo, "Track", "Frame")
	local identity = need(trackInfo, "TrackIdentity", "Frame")
	local requester = need(identity, "RequesterInfoWrapper", "Frame")
	local playlist = need(identity, "RelatedPlaylistWrapper", "Frame")

	local djStage = need(page, "DJPlayingWrapper", "Frame")
	local djOuter = need(djStage, "Outer", "Frame")
	local djInfo = need(djOuter, "TrackInfo", "Frame")
	local djWrapper = need(djInfo, "Wrapper", "Frame")
	local djIdentity = need(djInfo, "TrackIdentity", "Frame")
	local djControlled = need(need(djOuter, "Wrapper", "Frame"), "ControlledbyDJInfo", "TextButton")

	return {
		hero = hero,
		djStage = djStage,
		trackTitle = need(track, "1-TrackTitle", "TextLabel"),
		trackCreator = need(track, "2-TrackCreator", "TextLabel"),
		cover = need(track, "ImageLabel", "ImageLabel"),
		requesterName = need(requester, "2-RequesterDisplayName", "TextLabel"),
		requesterAvatar = need(requester, "3-RequesterProfilePicture", "ImageLabel"),
		playlistTitle = need(playlist, "2-PlaylistTitle", "TextLabel"),
		playlistCover = need(playlist, "3-PlaylistColororImage", "ImageLabel"),
		elapsedLabel = need(numbers, "DetikSaatIni", "TextLabel"),
		lengthLabel = need(numbers, "SongLength", "TextLabel"),
		progressFill = need(need(progress, "ProgressBar", "Frame"), "InnerBar", "Frame"),
		voteSkipButton = voteSkipButton,
		voteSkipLabel = need(voteSkipButton, "TextLabel", "TextLabel"),
		clearQueueButton = need(controls, "ClearQueueButton", "TextButton"),
		transportButtons = {
			need(controls, "RewindButton", "TextButton"),
			need(controls, "PreviousButton", "TextButton"),
			need(controls, "PlayorPauseButton", "TextButton"),
			need(controls, "NextButton", "TextButton"),
			need(controls, "SeekButton", "TextButton"),
		},
		djName = need(djWrapper, "DJName", "TextLabel"),
		djAvatar = need(djWrapper, "DJProfileThumbnail", "ImageLabel"),
		djNowPlaying = need(need(djIdentity, "RequesterInfoWrapper", "Frame"), "2-RequesterDisplayName", "TextLabel"),
		djPlaylistTitle = need(need(djIdentity, "RelatedPlaylistWrapper", "Frame"), "2-PlaylistTitle", "TextLabel"),
		djControlledLabel = need(djControlled, "TextLabel", "TextLabel"),
	}
end

local function resolveVote(modals: Folder): VoteRefs
	local modal = need(modals, "VoteModal", "Frame")
	local card = need(modal, "TrackWrapperTemplate", "TextButton")
	local cardCover = need(card, "RelatedPlaylistCover", "ImageLabel")
	local information = need(need(card, "TrackInformationWrapper", "Frame"), "TrackInformation", "Frame")
	local details = need(information, "TrackDetails", "Frame")
	local inputs = need(modal, "InputWrapper", "Frame")
	local rejectButton = need(inputs, "RejectSkipButton", "TextButton")
	local skipButton = need(inputs, "SkipButtonVote", "TextButton")

	return {
		modal = modal,
		backdrop = need(modals, "BackdropBlur", "Frame"),
		title = need(modal, "DynamicVoteTitle", "TextLabel"),
		barFill = need(need(modal, "LoadingBar", "Frame"), "InnerBar", "Frame"),
		rejectButton = rejectButton,
		rejectLabel = need(rejectButton, "DynamicRejectText", "TextLabel"),
		skipButton = skipButton,
		skipLabel = need(skipButton, "DynamicSkipText", "TextLabel"),
		card = card,
		cardCover = cardCover,
		cardPlaylistName = need(cardCover, "PlaylistName", "TextLabel"),
		cardTitle = need(details, "TrackTitle", "TextLabel"),
		cardLength = need(details, "TrackLength", "TextLabel"),
		cardCreator = need(details, "TrackCreator", "TextLabel"),
		cardAddWrapper = need(information, "AddToQueueWrapper", "Frame"),
	}
end

local function resolveLibrary(wrapper: Frame): LibraryRefs
	local selectPlaylist = need(wrapper, "1-SelectPlaylist", "Frame")
	local playlistScroll =
		need(need(selectPlaylist, "ScrollablePlaylistWrapper", "Frame"), "ScrollablePlaylist", "ScrollingFrame")
	local selectSong = need(wrapper, "2-SelectSong", "Frame")
	local detail = need(selectSong, "TrackListLeft", "Frame")
	local art = need(detail, "Wrapper", "Frame")
	local info = need(detail, "PlaylistInfo", "Frame")
	local buttons = need(detail, "ButtonWrapper", "Frame")
	local trackPanel = need(selectSong, "TrackListRight", "Frame")
	local trackScroll = need(trackPanel, "ScrollingFrame", "ScrollingFrame")
	local requestFromId = need(selectSong, "Request From ID", "Frame")

	return {
		searchBox = need(selectPlaylist, "SearchBar", "TextBox"),
		playlistScroll = playlistScroll,
		favoritesButton = need(playlistScroll, "FavoritesPlaylistTabButton", "TextButton"),
		newDropsButton = need(playlistScroll, "NewDropsTabButton", "TextButton"),
		detail = detail,
		detailCover = need(art, "CoverImage", "ImageLabel"),
		detailOwnerAvatar = need(art, "OwnerAvatar", "ImageLabel"),
		detailTitle = need(info, "DJorPlaylistName", "TextLabel"),
		detailSubtitle = need(info, "PlaylistSubtitle", "TextLabel"),
		detailOwnerName = need(info, "DJDisplayName", "TextLabel"),
		detailLevelLabel = need(need(info, "PlaylistLevel", "Frame"), "TextLabel", "TextLabel"),
		shuffleButton = need(buttons, "ShuffleButton", "ImageButton"),
		addSetButton = need(buttons, "AddSetstoQueue", "ImageButton"),
		trackPanel = trackPanel,
		trackScroll = trackScroll,
		trackContainer = need(trackScroll, "TracklistWrapper", "Frame"),
		privateWall = need(selectSong, "PrivateWall", "Frame"),
		requestFromId = requestFromId,
		requestInput = need(requestFromId, "TextBox", "TextBox"),
		requestButton = need(requestFromId, "TextButton", "TextButton"),
	}
end

local function resolveDj(djTab: Frame): DjRefs
	local modeWrapper = need(need(djTab, "1-PlaylistSection", "Frame"), "DJModeWrapper", "Frame")
	local modeToggle = need(need(modeWrapper, "Wrapper", "Frame"), "ToggleEnableDJMode", "TextButton")
	local modeTrack = need(modeToggle, "Frame", "Frame")
	local effects = need(need(djTab, "SoundEffectWrapper", "Frame"), "ScrollableFrame", "ScrollingFrame")
	local speed = need(need(effects, "PlaybackSpeed", "Frame"), "Wrapper", "Frame")
	local speedTop = need(speed, "Top", "Frame")
	local sliderHost = need(need(speedTop, "SliderWrapper", "Frame"), "AdjustSpeedWrapper", "Frame")

	return {
		modeToggle = modeToggle,
		modeToggleTrack = modeTrack,
		modeToggleThumb = need(modeTrack, "Frame", "Frame"),
		warning = need(modeWrapper, "Warning(Ignore)", "Frame"),
		resetButton = need(need(effects, "Header", "Frame"), "SoundEffectResetButton", "TextButton"),
		speedValueLabel = need(need(speedTop, "Header", "Frame"), "Value", "TextLabel"),
		speedSliderHost = sliderHost,
		speedSliderFill = need(sliderHost, "AdjustableFrameWidth", "Frame"),
		speedPresetWrapper = need(speed, "SpeedTemplateWrapper", "Frame"),
	}
end

function GuiRefs.resolve(playerGui: PlayerGui): Refs
	local root = need(playerGui, Config.Music.GUI_NAME, "ScreenGui")
	local main = need(root, "MainWrapper", "Frame")

	local header = need(main, "01-HeaderWrapper", "Frame")
	local selector = need(header, "2-SliderSelector", "Frame")
	local options = need(selector, "2-SliderSelector", "Frame")
	local optNowPlaying = need(options, "Option1", "TextButton")
	local optLibrary = need(options, "Option2", "TextButton")
	local optDj = need(options, "Option3", "TextButton")

	local nowPlayingTab = need(main, "NowPlayingTab", "Frame")
	local libraryTab = need(main, "LibraryTab", "Frame")
	local djTab = need(main, "DJTab", "Frame")

	local nowPlayingPage = need(nowPlayingTab, "1-NowPlayingWrapper", "Frame")
	local queueScroll = need(need(nowPlayingPage, "2-QueueSectionWrapper", "Frame"), "ScrollableQueue", "ScrollingFrame")

	local libraryWrapper = need(libraryTab, "Wrapper", "Frame")
	local playlistScroll = need(
		need(need(libraryWrapper, "1-SelectPlaylist", "Frame"), "ScrollablePlaylistWrapper", "Frame"),
		"ScrollablePlaylist",
		"ScrollingFrame"
	)
	local trackListWrapper = need(
		need(need(need(libraryWrapper, "2-SelectSong", "Frame"), "TrackListRight", "Frame"), "ScrollingFrame", "ScrollingFrame"),
		"TracklistWrapper",
		"Frame"
	)

	local djPlaylistSection = need(djTab, "1-PlaylistSection", "Frame")
	local soundBoardScroll = need(need(djPlaylistSection, "SoundBoardWrapper", "Frame"), "ScrollingFrame", "ScrollingFrame")
	local effectScroll = need(need(djTab, "SoundEffectWrapper", "Frame"), "ScrollableFrame", "ScrollingFrame")

	local modals = need(root, "UtilitesModal", "Folder")
	local vote = resolveVote(modals)

	return {
		root = root,
		mainWrapper = main,
		dragDetector = need(main, "UIDragDetector", "UIDragDetector"),
		closeButton = need(header, "99-CloseModalButton", "TextButton"),
		tabButtons = { nowplaying = optNowPlaying, request = optLibrary, dj = optDj },
		tabButtonOrder = { optNowPlaying, optLibrary, optDj },
		backgroundPill = need(selector, "BackgroundPill", "Frame"),
		tabFrames = { nowplaying = nowPlayingTab, request = libraryTab, dj = djTab },
		nowPlaying = resolveNowPlaying(nowPlayingPage),
		vote = vote,
		library = resolveLibrary(libraryWrapper),
		dj = resolveDj(djTab),
		queueRowTemplate = need(queueScroll, "QueueListTemplate", "TextButton"),
		playlistTemplates = {
			nonImageSelected = need(playlistScroll, "PlaylistNonImageTemplateSelected", "TextButton"),
			nonImageNormal = need(playlistScroll, "PlaylistNonIMageTemplateNormal", "TextButton"),
			imageSelected = need(playlistScroll, "PlaylistImageTemplateSelected", "TextButton"),
			imageNormal = need(playlistScroll, "PlaylistImageTemplateNormal", "TextButton"),
			djSetNormal = need(playlistScroll, "DJSetsTemplateNormal", "TextButton"),
			djSetSelected = need(playlistScroll, "DJSetsTemplateSelected", "TextButton"),
		},
		trackRowTemplate = need(trackListWrapper, "QueueListTemplate", "TextButton"),
		soundBoardItemTemplate = need(soundBoardScroll, "SoundBoardItemTemplate", "TextButton"),
		effectTemplate = need(effectScroll, "TemplateEffect", "Frame"),
		voteModal = vote.modal,
		voteTrackTemplate = vote.card,
		backdropBlur = vote.backdrop,
	}
end

return GuiRefs
