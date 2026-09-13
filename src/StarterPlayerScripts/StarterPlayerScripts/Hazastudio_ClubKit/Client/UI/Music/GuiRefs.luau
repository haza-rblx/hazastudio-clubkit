--!strict
-- PATH: StarterPlayerScripts/Client/UI/Music/GuiRefs.luau
-- Resolves the 06-MusicPlayerGUIv3 tree once. One name = one element: a missing or renamed
-- instance fails loudly here instead of silently degrading later (no fallbacks, no variants).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local GuiRefs = {}

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
	-- Row templates (hidden at bind; pooled from Stage D)
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

local function need(parent: Instance, name: string, className: string): any
	local child = parent:FindFirstChild(name)
	assert(child ~= nil, string.format("[MusicGuiRefs] missing %s.%s", parent:GetFullName(), name))
	assert(
		child:IsA(className),
		string.format("[MusicGuiRefs] %s is %s, expected %s", child:GetFullName(), child.ClassName, className)
	)
	return child
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

	local queueScroll =
		need(need(need(nowPlayingTab, "1-NowPlayingWrapper", "Frame"), "2-QueueSectionWrapper", "Frame"), "ScrollableQueue", "ScrollingFrame")

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
	local voteModal = need(modals, "VoteModal", "Frame")

	return {
		root = root,
		mainWrapper = main,
		dragDetector = need(main, "UIDragDetector", "UIDragDetector"),
		closeButton = need(header, "99-CloseModalButton", "TextButton"),
		tabButtons = { nowplaying = optNowPlaying, request = optLibrary, dj = optDj },
		tabButtonOrder = { optNowPlaying, optLibrary, optDj },
		backgroundPill = need(selector, "BackgroundPill", "Frame"),
		tabFrames = { nowplaying = nowPlayingTab, request = libraryTab, dj = djTab },
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
		voteModal = voteModal,
		voteTrackTemplate = need(voteModal, "TrackWrapperTemplate", "TextButton"),
		backdropBlur = need(modals, "BackdropBlur", "Frame"),
	}
end

return GuiRefs
