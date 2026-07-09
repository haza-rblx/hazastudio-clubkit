--!strict
-- PATH: StarterPlayerScripts/Client/UI/MusicPlayerUIBinder.lua
-- Binding semua UI events dan rendering untuk Music Player.
-- Dipanggil oleh Controller setelah refs dan store ready.

local AssetService = game:GetService("AssetService")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Sets TrackTitle height: 1 line if text fits, 2 lines if it wraps
local MAX_TITLE_HEIGHT_RETRIES = 4
local function setTrackTitleHeight(label: TextLabel, attempt: number?)
	local currentAttempt = attempt or 1
	local lineH = label.TextSize
	local maxW = label.AbsoluteSize.X
	if maxW <= 0 then
		-- AbsoluteSize not ready yet; settle it on the next layout pass.
		label.AutomaticSize = Enum.AutomaticSize.None
		label.Size = UDim2.new(label.Size.X.Scale, label.Size.X.Offset, 0, lineH + 4)
		if currentAttempt < MAX_TITLE_HEIGHT_RETRIES then
			task.defer(function()
				if label.Parent then
					setTrackTitleHeight(label, currentAttempt + 1)
				end
			end)
		end
		return
	end
	label.TextWrapped = false
	label.TextTruncate = Enum.TextTruncate.None
	local textBounds = label.TextBounds
	local lines = if textBounds.X <= maxW then 1 else 2
	label.TextWrapped = lines > 1
	label.TextTruncate = if lines == 1 then Enum.TextTruncate.AtEnd else Enum.TextTruncate.None
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.AutomaticSize = Enum.AutomaticSize.None
	label.Size = UDim2.new(label.Size.X.Scale, label.Size.X.Offset, 0, lineH * lines + 4)
end

local function scheduleTrackTitleHeight(label: TextLabel)
	setTrackTitleHeight(label)
	task.defer(function()
		if label.Parent then
			setTrackTitleHeight(label)
		end
	end)
end

local MusicPlayerGuiRefs = require(script.Parent.MusicPlayerGuiRefs)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
local ScrollIndicatorHelper = require(script.Parent.Parent.Utils.ScrollIndicatorHelper)
local SliderSelectorUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.SliderSelectorUtil)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local MusicDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.MusicDomain)

type Refs = MusicPlayerGuiRefs.Refs
type TabFrameState = {
	position: UDim2,
	zIndex: number,
}
type ManageFormCopy = {
	title: string,
	helper: string,
	button: string,
}
type PlaylistRowVisualState = {
	backgroundColor3: Color3,
	backgroundTransparency: number,
	borderSizePixel: number,
	autoButtonColor: boolean?,
}
type PooledRow = {
	instance: GuiObject,
	connections: { RBXScriptConnection },
}
type VirtualListRenderOptions = {
	key: string,
	scroll: ScrollingFrame,
	parent: Instance?,
	pool: { PooledRow },
	template: GuiObject,
	items: { any },
	renderRow: (PooledRow, any, number) -> (),
}
type SuppressedOverheadEntry = {
	gui: BillboardGui,
	wasEnabled: boolean,
}

-- Tween presets
local FADE_INFO_FAST = TweenInfo.new(0.12, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
local _FADE_INFO_MED = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local REQUEST_TRACK_SUCCESS_ASSET = "rbxassetid://135697536961722"
local REQUEST_TRACK_SUCCESS_COLOR = Color3.fromRGB(112, 255, 143)
local REQUEST_TRACK_FEEDBACK_TIME = 2.4
local ADD_TO_QUEUE_BLUR_NAME = "MusicPlayerAddToQueueBlur"
local MAIN_PANEL_BLUR_NAME = "MusicPlayerMainBlur"
local ADD_TO_QUEUE_CAMERA_FOV_DELTA = 2
local ADD_TO_QUEUE_CAMERA_TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
local PLAYLIST_RELATED_BLUR_NAME = "MusicPlayerPlaylistRelatedBlur"
local PLAYLIST_RELATED_CAMERA_FOV_DELTA = ADD_TO_QUEUE_CAMERA_FOV_DELTA
local PLAYLIST_RELATED_CAMERA_TWEEN_INFO = ADD_TO_QUEUE_CAMERA_TWEEN_INFO
local TRACK_RELATED_BLUR_NAME = "MusicPlayerTrackRelatedBlur"
local TRACK_RELATED_CAMERA_FOV_DELTA = ADD_TO_QUEUE_CAMERA_FOV_DELTA
local TRACK_RELATED_CAMERA_TWEEN_INFO = ADD_TO_QUEUE_CAMERA_TWEEN_INFO
local ADD_TO_QUEUE_SUPPRESS_ATTRIBUTE = "MusicPlayerQueueConfirmationOpen"
local SETTINGS_BACKGROUND_BLUR_ATTRIBUTE = "SettingsBackgroundBlurEnabled"
local AVATAR_CONTEXT_GUI_NAME = "AvatarContextMenu"
local OVERHEAD_TEMPLATE_NAME = Config.Template.TEMPLATE_NAME
local VOTE_MODAL_IN_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
local VOTE_MODAL_OUT_INFO = TweenInfo.new(0.08, Enum.EasingStyle.Cubic, Enum.EasingDirection.In)
local VOTE_MODAL_ENTRY_OFFSET = 6
local VOTE_MODAL_BAR_GREEN = Color3.fromRGB(84, 255, 148)
local VOTE_MODAL_BAR_YELLOW = Color3.fromRGB(255, 201, 84)
local VOTE_MODAL_BAR_RED = Color3.fromRGB(255, 84, 84)
local FALLBACK_FAVORITES_PLAYLIST_ID = "__favorites__"
local FALLBACK_NEW_DROPS_PLAYLIST_ID = "__new_drops__"
local REQUEST_PLAYLIST_USER_LAYOUT_BASE = 100
local LIST_RENDER_BATCH_SIZE = 8
local DEFAULT_VIRTUAL_TRACK_ROW_BUFFER = 6
local DEFAULT_VIRTUAL_TRACK_MAX_RENDERED_ROWS = 60
local VIRTUAL_ROW_LAYOUT_BASE = 100
local VIRTUAL_TOP_SPACER_LAYOUT_ORDER = VIRTUAL_ROW_LAYOUT_BASE - 1
local VIRTUAL_BOTTOM_SPACER_LAYOUT_ORDER = 1000000
local DISABLE_UI_SFX_ATTRIBUTE = "DisableUISFX"
local LIST_ROW_ENTER_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
local LIST_ROW_ENTER_SCALE = 0.985
local LIST_ROW_ENTER_TRANSPARENCY_DELTA = 0.18
local LIST_ROW_BASE_SCALE_ATTRIBUTE = "MusicListBaseScale"
local DEFAULT_COVER_GRADIENT_ROTATION = 90
local COVER_GRADIENT_FLAT_BLEND = 0.56
local QUEUE_SCROLLBAR_IDLE_DELAY = 1
local IMAGE_COVER_SAMPLE_MAX_DIMENSION = 64
local IMAGE_COVER_SAMPLE_MIN_ALPHA = 32
local IMAGE_COVER_NEAR_BLACK_LUMINANCE = 0.035
local IMAGE_COVER_NEAR_BLACK_SATURATION = 0.08
local MONTH_NAMES = {
	"January",
	"February",
	"March",
	"April",
	"May",
	"June",
	"July",
	"August",
	"September",
	"October",
	"November",
	"December",
}
local function getMonthDropsLabel(): string
	local month = os.date("*t").month :: number
	return MONTH_NAMES[month] .. " Drops"
end

local function getCoverGradientColors(gradient: any): { Color3 }
	local colors: { Color3 } = {}
	if type(gradient) ~= "table" then
		return colors
	end
	for _, value in ipairs(gradient) do
		if typeof(value) == "Color3" then
			table.insert(colors, value)
		end
	end
	return colors
end

local function getCoverGradientRotation(gradient: any): number
	if type(gradient) ~= "table" then
		return DEFAULT_COVER_GRADIENT_ROTATION
	end
	for index = #gradient, 1, -1 do
		if type(gradient[index]) == "number" then
			return gradient[index]
		end
	end
	return DEFAULT_COVER_GRADIENT_ROTATION
end

local function buildCoverGradientColorSequence(gradient: any): ColorSequence
	local colors = getCoverGradientColors(gradient)
	if #colors == 0 then
		return ColorSequence.new(Color3.fromRGB(80, 80, 80), Color3.fromRGB(20, 20, 20))
	end
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end

	local midColor = colors[1]
	for index = 2, #colors do
		midColor = midColor:Lerp(colors[index], 1 / index)
	end

	local keypoints: { ColorSequenceKeypoint } = {}
	for index, color in ipairs(colors) do
		local flatTint = color:Lerp(midColor, COVER_GRADIENT_FLAT_BLEND)
		table.insert(keypoints, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), flatTint))
	end
	return ColorSequence.new(keypoints)
end

local function sampleColorSequence(sequence: ColorSequence, alpha: number): Color3
	local keypoints = sequence.Keypoints
	if #keypoints == 0 then
		return Color3.fromRGB(255, 255, 255)
	end
	if alpha <= keypoints[1].Time then
		return keypoints[1].Value
	end
	for index = 2, #keypoints do
		local previous = keypoints[index - 1]
		local current = keypoints[index]
		if alpha <= current.Time then
			local span = math.max(current.Time - previous.Time, 0.001)
			return previous.Value:Lerp(current.Value, (alpha - previous.Time) / span)
		end
	end
	return keypoints[#keypoints].Value
end

local function getCoverGradientMidColor(gradient: any): Color3
	return sampleColorSequence(buildCoverGradientColorSequence(gradient), 0.5)
end

local function getStableAccentColor(seed: any): Color3
	local text = tostring(seed or "")
	local hash = 0
	for index = 1, #text do
		hash = (hash * 31 + string.byte(text, index)) % 360
	end
	return Color3.fromHSV(hash / 360, 0.48, 0.88)
end

local function getStableDarkCoverColor(seed: any): Color3
	local text = tostring(seed or "")
	local hash = 0
	for index = 1, #text do
		hash = (hash * 31 + string.byte(text, index)) % 360
	end
	return Color3.fromHSV(hash / 360, 0.62, 0.36)
end

local function getColorLuminance(color: Color3): number
	return color.R * 0.2126 + color.G * 0.7152 + color.B * 0.0722
end

local function getColorSaturation(color: Color3): number
	local maxChannel = math.max(color.R, color.G, color.B)
	local minChannel = math.min(color.R, color.G, color.B)
	if maxChannel <= 0 then
		return 0
	end
	return (maxChannel - minChannel) / maxChannel
end

local function normalizeColorChannel(value: number): number
	if value > 1 then
		return math.clamp(value / 255, 0, 1)
	end
	return math.clamp(value, 0, 1)
end

local function colorFromValue(value: any): Color3?
	if typeof(value) == "Color3" then
		return value
	end

	if type(value) == "string" then
		local hex = value:gsub("#", "")
		if #hex == 6 and hex:match("^[%da-fA-F]+$") then
			local r = tonumber(hex:sub(1, 2), 16)
			local g = tonumber(hex:sub(3, 4), 16)
			local b = tonumber(hex:sub(5, 6), 16)
			if r and g and b then
				return Color3.fromRGB(r, g, b)
			end
		end
		return nil
	end

	if type(value) ~= "table" then
		return nil
	end

	local r = value[1] or value.R or value.r
	local g = value[2] or value.G or value.g
	local b = value[3] or value.B or value.b
	if type(r) == "number" and type(g) == "number" and type(b) == "number" then
		return Color3.new(normalizeColorChannel(r), normalizeColorChannel(g), normalizeColorChannel(b))
	end

	return nil
end

local function collectColors(value: any, colors: { Color3 })
	local directColor = colorFromValue(value)
	if directColor then
		table.insert(colors, directColor)
		return
	end

	if type(value) ~= "table" then
		return
	end

	for _, item in ipairs(value) do
		collectColors(item, colors)
	end
end

local function getPlaylistCoverPaletteColors(playlist: any): { Color3 }
	local colors = {} :: { Color3 }
	collectColors(playlist.coverDarkestColor, colors)
	collectColors(playlist.coverDominantColors, colors)
	collectColors(playlist.coverPalette, colors)
	collectColors(playlist.palette, colors)
	collectColors(playlist.colors, colors)
	collectColors(playlist.coverColors, colors)
	return colors
end

local function getDarkestColor(colors: { Color3 }): Color3?
	local darkest: Color3? = nil
	local darkestLuminance = math.huge

	for _, color in ipairs(colors) do
		local luminance = getColorLuminance(color)
		if luminance < darkestLuminance then
			darkest = color
			darkestLuminance = luminance
		end
	end

	return darkest
end

local function getImageCoverKey(coverValue: any): string?
	local text = tostring(coverValue or "")
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then
		return nil
	end
	return text
end

local function getImageCoverUri(coverValue: any): string?
	local text = getImageCoverKey(coverValue)
	if not text then
		return nil
	end
	if text:match("^rbxassetid://") or text:match("^rbxthumb://") or text:match("^https?://") then
		return text
	end

	local numericId = text:match("%d+")
	if numericId then
		return "rbxassetid://" .. numericId
	end

	return nil
end

local function resolveCoverSourceForTrack(track: any, parentPlaylist: any?): any?
	if type(track) ~= "table" then
		return parentPlaylist
	end
	if type(track.coverType) == "string" and track.coverType ~= "" then
		return {
			coverType = track.coverType,
			coverValue = track.coverValue,
			name = track.name,
			fontFace = if type(parentPlaylist) == "table" then parentPlaylist.fontFace else "Original",
		}
	end
	return parentPlaylist
end

local function sampleImageCoverDarkestColor(coverValue: any): Color3?
	local uri = getImageCoverUri(coverValue)
	if not uri then
		return nil
	end

	local imageOk, editableImage = pcall(function()
		return AssetService:CreateEditableImageAsync(Content.fromUri(uri))
	end)
	if not imageOk or not editableImage then
		return nil
	end

	local image = editableImage :: any
	local size = image.Size
	local width = math.max(1, math.floor(size.X))
	local height = math.max(1, math.floor(size.Y))
	local pixelsOk, pixels = pcall(function()
		return image:ReadPixelsBuffer(Vector2.zero, Vector2.new(width, height))
	end)

	if not pixelsOk or not pixels then
		pcall(function()
			image:Destroy()
		end)
		return nil
	end

	local stride = math.max(1, math.floor(math.max(width, height) / IMAGE_COVER_SAMPLE_MAX_DIMENSION))
	local darkest: Color3? = nil
	local darkestScore = math.huge
	local fallbackDarkest: Color3? = nil
	local fallbackLuminance = math.huge

	for y = 0, height - 1, stride do
		for x = 0, width - 1, stride do
			local pixelIndex = (y * width + x) * 4
			local alpha = buffer.readu8(pixels, pixelIndex + 3)
			if alpha >= IMAGE_COVER_SAMPLE_MIN_ALPHA then
				local color = Color3.fromRGB(
					buffer.readu8(pixels, pixelIndex),
					buffer.readu8(pixels, pixelIndex + 1),
					buffer.readu8(pixels, pixelIndex + 2)
				)
				local luminance = getColorLuminance(color)
				local saturation = getColorSaturation(color)

				if luminance < fallbackLuminance then
					fallbackDarkest = color
					fallbackLuminance = luminance
				end

				local isFlatBlack = luminance <= IMAGE_COVER_NEAR_BLACK_LUMINANCE
					and saturation <= IMAGE_COVER_NEAR_BLACK_SATURATION
				if not isFlatBlack then
					local score = luminance - saturation * 0.12
					if score < darkestScore then
						darkest = color
						darkestScore = score
					end
				end
			end
		end
	end

	pcall(function()
		image:Destroy()
	end)

	return darkest or fallbackDarkest
end

local function getPlaylistCoverAccentColor(
	playlist: any?,
	config: any,
	imageCoverDarkestColors: { [string]: Color3 }?
): Color3?
	if playlist == nil then
		return nil
	end

	if (playlist.coverType or "gradient") == "image" then
		local paletteDarkest = getDarkestColor(getPlaylistCoverPaletteColors(playlist))
		if paletteDarkest then
			return paletteDarkest
		end

		local coverKey = getImageCoverKey(playlist.coverValue)
		local cachedDarkest = if coverKey and imageCoverDarkestColors then imageCoverDarkestColors[coverKey] else nil
		return cachedDarkest or getStableDarkCoverColor(coverKey or playlist.name)
	end

	local gradients = config and config.COVER_GRADIENTS
	local gradientIndex = tonumber(playlist.coverValue) or 1
	if gradients and type(gradients) == "table" and gradientIndex >= 1 and gradientIndex <= #gradients then
		return getCoverGradientMidColor(gradients[gradientIndex])
	end

	return nil
end

local PLAYLIST_FORM_COPY = {
	create = {
		title = "Create a New Playlist",
		helper = "Set the name, cover, and font so your playlist feels polished from the start.",
		button = "Create Playlist",
	},
	update = {
		title = "Edit Playlist Details",
		helper = "Update the name, cover, or font to keep this playlist clear, polished, and easy to spot.",
		button = "Update Playlist",
	},
} :: { create: ManageFormCopy, update: ManageFormCopy }

local TRACK_FORM_COPY = {
	create = {
		title = "Upload a New Track",
		helper = "Add a track to one of your playlists so it is ready to queue whenever the room needs it.",
		button = "Upload Track",
	},
	update = {
		title = "Edit Track Details",
		helper = "Update the track info and audio IDs so playback stays accurate and your library stays tidy.",
		button = "Update Track",
	},
} :: { create: ManageFormCopy, update: ManageFormCopy }

-- ============================================================
-- MODULE
-- ============================================================

local MusicPlayerUIBinder = {} :: any
MusicPlayerUIBinder.__index = MusicPlayerUIBinder

function MusicPlayerUIBinder.new(deps: {
	refs: Refs,
	store: any,
	config: any?,
})
	local self = setmetatable({}, MusicPlayerUIBinder) :: any
	self._refs = deps.refs
	self._store = deps.store
	self._config = deps.config
	self._anim = AnimationHelper.new() -- shared UI motion helper
	self._connections = {} :: { RBXScriptConnection }
	self._unsubscribers = {} :: { () -> () }

	-- Callbacks yang di-set oleh Controller
	self._onTabSelected = nil :: ((string) -> ())?
	self._onToggleDjMode = nil :: (() -> ())?
	self._onCloseRequested = nil :: (() -> ())?
	self._onVoteSkip = nil :: ((string?) -> ())?
	self._onRequestTrack = nil :: ((string) -> ())?
	self._onAddFavoriteTrack = nil :: ((string, boolean) -> ())?
	self._onPlaylistSelected = nil :: ((string) -> ())?
	self._onSearchChanged = nil :: ((string) -> ())?
	self._onVolumeChanged = nil :: ((number) -> ())?
	self._onManageSubView = nil :: ((string, any?) -> ())?
	self._onManagePlaylist = nil :: ((string, { [string]: any }) -> ())?
	self._onManageTrack = nil :: ((string, { [string]: any }) -> ())?
	self._onResolveRequestAsset = nil :: ((string) -> ())?
	self._onFormNotify = nil :: ((string, string, string?) -> ())? -- (level, title, description?)
	self._onDjSoundboardTriggered = nil :: ((string) -> boolean)?
	self._onDjPlaybackSpeedChanged = nil :: ((number) -> boolean)?
	self._onDjEffectEnabledChanged = nil :: ((string, boolean) -> boolean)?
	self._onDjEffectValueChanged = nil :: ((string, string, number) -> boolean)?
	self._onDjBassEnabledChanged = nil :: ((boolean) -> ())?
	self._onDjBassValueChanged = nil :: ((number) -> ())?
	self._onDjResetRequested = nil :: (() -> boolean)?

	-- Progress bar state (Heartbeat)
	self._progressConn = nil :: RBXScriptConnection?
	self._volumeDragConn = nil :: RBXScriptConnection?
	self._totalDuration = 0
	self._tabFrameDefaults = nil :: { [string]: TabFrameState }?
	self._queueRowPool = {} :: { PooledRow }
	self._requestPlaylistRowPool = {} :: { PooledRow }
	self._requestTrackLeftRowPool = {} :: { PooledRow }
	self._requestTrackRightRowPool = {} :: { PooledRow }
	self._managePlaylistRowPool = {} :: { PooledRow }
	self._manageTrackRowPool = {} :: { PooledRow }
	self._manageTrackRightRowPool = {} :: { PooledRow }
	self._listRenderJobs = {} :: { [string]: thread }
	self._listRenderTokens = {} :: { [string]: number }
	self._virtualListConnections = {} :: { [string]: { RBXScriptConnection } }
	self._djSpeedPresetButtons = {} :: { [number]: GuiObject }
	self._djSoundBoardConnections = {} :: { RBXScriptConnection }
	self._djEffectConnections = {} :: { RBXScriptConnection }
	self._djPlaybackSpeedSliderSetter = nil :: ((number) -> ())?
	self._djPlaybackSpeedHeaderValueLabel = nil :: TextLabel?
	self._djEffectSliderSetters = {} :: { [string]: (number) -> () }
	self._djPlaybackSpeedSliderRoot = nil :: GuiObject?
	self._djEffectSliderRoots = {} :: { [string]: GuiObject }
	self._djEffectToggleButtons = {} :: { [string]: GuiObject }
	self._djModeToggle = nil :: GuiObject?
	self._djEffectEnabledById = {} :: { [string]: boolean }
	self._djEffectValues = {} :: { [string]: { [string]: number } }
	-- DJ speed slider is a multiplier (1x = normal), not global Config.Music.PLAYBACK_SPEED.
	self._djPlaybackSpeed = 1
	self._specialPlaylistDefaults = nil :: {
		favorites: PlaylistRowVisualState,
		newDrops: PlaylistRowVisualState,
	}?
	self._pendingRequestTrackId = nil :: string?
	self._pendingFavoriteShouldRemove = false
	self._isAddToQueueModalOpen = false
	self._addToQueueHiddenMainWrapper = false
	self._addToQueueSuppressedOverheads = {} :: { SuppressedOverheadEntry }
	self._addToQueueSuppressedOverheadSet = {} :: { [Instance]: true }
	self._addToQueueSuppressionConnections = {} :: { RBXScriptConnection }
	self._addToQueueAvatarContextGui = nil :: ScreenGui?
	self._addToQueueAvatarContextWasEnabled = nil :: boolean?
	self._addToQueueBlur = nil :: BlurEffect?
	self._addToQueueCameraTween = nil :: Tween?
	self._addToQueueBaseFov = nil :: number?
	self._playlistRelatedHiddenMainWrapper = false
	self._playlistRelatedSuppressedOverheads = {} :: { SuppressedOverheadEntry }
	self._playlistRelatedSuppressedOverheadSet = {} :: { [Instance]: true }
	self._playlistRelatedSuppressionConnections = {} :: { RBXScriptConnection }
	self._playlistRelatedAvatarContextGui = nil :: ScreenGui?
	self._playlistRelatedAvatarContextWasEnabled = nil :: boolean?
	self._playlistRelatedBlur = nil :: BlurEffect?
	self._playlistRelatedCameraTween = nil :: Tween?
	self._playlistRelatedBaseFov = nil :: number?
	self._trackRelatedHiddenMainWrapper = false
	self._trackRelatedSuppressedOverheads = {} :: { SuppressedOverheadEntry }
	self._trackRelatedSuppressedOverheadSet = {} :: { [Instance]: true }
	self._trackRelatedSuppressionConnections = {} :: { RBXScriptConnection }
	self._trackRelatedAvatarContextGui = nil :: ScreenGui?
	self._trackRelatedAvatarContextWasEnabled = nil :: boolean?
	self._trackRelatedBlur = nil :: BlurEffect?
	self._trackRelatedCameraTween = nil :: Tween?
	self._trackRelatedBaseFov = nil :: number?
	self._voteModalTween = nil :: Tween?
	self._voteModalCountdownConn = nil :: RBXScriptConnection?
	self._voteModalBasePosition = nil :: UDim2?
	self._voteModalSessionId = nil :: string?
	self._pendingPlaylistModalAction = nil :: { action: string, data: { [string]: any } }?
	self._activeManageModal = nil :: GuiObject?
	self._manageFormHiddenMainWrapper = false
	self._activePlaylistRelatedModal = nil :: Frame?
	self._isPlaylistRelatedModalOpen = false
	self._pendingTrackModalAction = nil :: { action: string, data: { [string]: any } }?
	-- Explicit create vs edit; save/confirm must not rely on editingTrack/editingPlaylist alone.
	self._trackFormCreateMode = true
	self._playlistFormCreateMode = true
	self._activeTrackRelatedModal = nil :: Frame?
	self._isTrackRelatedModalOpen = false
	self._userThumbnailCache = {} :: { [number]: string }
	self._userThumbnailCacheOrder = {} :: { number }
	self._imageCoverDarkestColors = {} :: { [string]: Color3 }
	self._imageCoverDarkestColorRequests = {} :: { [string]: boolean }
	self._isDestroyed = false
	self._onUpdateManageTab = nil :: ((boolean) -> ())?
	self._onUpdateDjTabAccess = nil :: ((boolean) -> ())?
	self._onUpdateDjTabState = nil :: ((boolean) -> ())?
	self._mainWrapperDragDetectorEnabled = if deps.refs.mainDragDetector
		then deps.refs.mainDragDetector.Enabled
		else nil

	-- v2 fields
	self._tipsLoopConn = nil :: thread?
	self._playlistIconBounceCleanup = nil :: { tweens: { Tween }, connections: { RBXScriptConnection } }?
	self._auraHeartbeatConn = nil :: RBXScriptConnection?
	self._auraSoundCache = {} :: { Sound }
	self._auraSoundScanClock = 0
	self._auraSoundScanInterval = 0.75
	self._loudnessSoundProvider = nil :: (() -> { Sound })?
	self._auraGradientTween = nil :: Tween?
	self._auraGradientConn = nil :: RBXScriptConnection?

	deps.refs.mainWrapper.Active = true

	return self
end

-- Helpers

local function _fadeIn(target: CanvasGroup | Frame, duration: number?)
	local info = TweenInfo.new(duration or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if target:IsA("CanvasGroup") then
		(target :: CanvasGroup).GroupTransparency = 1
		target.Visible = true
		TweenService:Create(target, info, { GroupTransparency = 0 }):Play()
	else
		(target :: Frame).BackgroundTransparency = 1
		target.Visible = true
		TweenService:Create(target, info, { BackgroundTransparency = 0 }):Play()
	end
end

local function _fadeOut(target: CanvasGroup | Frame, duration: number?, callback: (() -> ())?)
	local info = TweenInfo.new(duration or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween: Tween
	if target:IsA("CanvasGroup") then
		tween = TweenService:Create(target, info, { GroupTransparency = 1 })
	else
		tween = TweenService:Create(target, info, { BackgroundTransparency = 1 })
	end
	tween.Completed:Connect(function()
		local targetGui = (target :: any) :: GuiObject
		targetGui.Visible = false
		if callback then
			callback()
		end
	end)
	tween:Play()
end

local function ensureUIScale(guiObject: GuiObject): UIScale
	local existing = guiObject:FindFirstChildWhichIsA("UIScale")
	if existing then
		return existing :: UIScale
	end

	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 1
	uiScale.Parent = guiObject
	return uiScale
end

local function stashTemplateInstance(template: Instance, folderName: string)
	local parent = template.Parent
	if not parent then
		return
	end

	local stash = parent:FindFirstChild(folderName)
	if not stash then
		local created = Instance.new("Folder")
		created.Name = folderName
		created.Parent = parent
		stash = created
	end

	if template.Parent ~= stash then
		template.Parent = stash
	end
end

local function _clearListClones(scrollable: ScrollingFrame, templateName: string)
	for _, child in ipairs(scrollable:GetChildren()) do
		-- Preserve: template, UIListLayout, UIPadding, dan CTA buttons
		local isPreserved = child.Name == templateName
			or child.Name == "UIListLayout"
			or child.Name == "UIPadding"
			or child.Name:sub(1, 2) == "0-" -- Legacy CTA buttons
			or child.Name:sub(1, 2) == "1-" -- Current CTA buttons

		if child:IsA("GuiObject") and not isPreserved then
			child:Destroy()
		end
	end
end

local function disconnectPooledRowConnections(row: PooledRow)
	for _, connection in ipairs(row.connections) do
		connection:Disconnect()
	end
	table.clear(row.connections)
end

local function markDynamicRowForLeanHelpers(row: GuiObject)
	row:SetAttribute(DISABLE_UI_SFX_ATTRIBUTE, true)
	for _, descendant in ipairs(row:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			descendant:SetAttribute(DISABLE_UI_SFX_ATTRIBUTE, true)
		end
	end
end

local function disconnectConnectionList(connections: { RBXScriptConnection })
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function ensurePooledRow(pool: { PooledRow }, index: number, template: GuiObject, parent: Instance): PooledRow
	local row = pool[index]
	if row then
		if row.instance.Parent ~= parent then
			row.instance.Parent = parent
		end
		return row
	end

	local instance = template:Clone()
	instance.Visible = false
	markDynamicRowForLeanHelpers(instance)
	instance.Parent = parent

	local newRow: PooledRow = {
		instance = instance,
		connections = {},
	}
	pool[index] = newRow
	return newRow
end

local function hideUnusedPooledRows(pool: { PooledRow }, firstUnusedIndex: number)
	for index = firstUnusedIndex, #pool do
		local row = pool[index]
		disconnectPooledRowConnections(row)
		row.instance.Visible = false
	end
end

local function destroyPooledRows(pool: { PooledRow })
	for _, row in ipairs(pool) do
		disconnectPooledRowConnections(row)
		row.instance:Destroy()
	end
	table.clear(pool)
end

local function cancelListRenderJob(self: any, key: string): number
	local existing = self._listRenderJobs[key]
	if existing then
		pcall(task.cancel, existing)
		self._listRenderJobs[key] = nil
	end

	local token = (self._listRenderTokens[key] or 0) + 1
	self._listRenderTokens[key] = token
	return token
end

local function isListRenderJobCurrent(self: any, key: string, token: number): boolean
	return self._listRenderTokens[key] == token
end

local function startListRenderJob(self: any, key: string, totalRows: number, renderRow: (number) -> ())
	local token = cancelListRenderJob(self, key)
	if totalRows <= 0 then
		return
	end

	self._listRenderJobs[key] = task.spawn(function()
		for index = 1, totalRows do
			if not isListRenderJobCurrent(self, key, token) then
				return
			end

			renderRow(index)

			if index % LIST_RENDER_BATCH_SIZE == 0 then
				task.wait()
			end
		end

		if isListRenderJobCurrent(self, key, token) then
			self._listRenderJobs[key] = nil
		end
	end)
end

local function cancelAllListRenderJobs(self: any)
	for key, job in pairs(self._listRenderJobs) do
		pcall(task.cancel, job)
		self._listRenderJobs[key] = nil
		self._listRenderTokens[key] = (self._listRenderTokens[key] or 0) + 1
	end
end

local function disconnectVirtualList(self: any, key: string)
	local connections = self._virtualListConnections[key]
	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		self._virtualListConnections[key] = nil
	end

	local refs = self._refs
	local root = refs and refs.root
	if not root then
		return
	end

	local topSpacerName = "CodexVirtualTopSpacer_" .. key
	local bottomSpacerName = "CodexVirtualBottomSpacer_" .. key
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Name == topSpacerName or descendant.Name == bottomSpacerName then
			descendant:Destroy()
		end
	end
end

local function disconnectAllVirtualLists(self: any)
	for _, connections in pairs(self._virtualListConnections) do
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
	end
	table.clear(self._virtualListConnections)
end

local function getVirtualListBuffer(config: any): number
	return math.max(
		0,
		math.floor(tonumber(config and config.VIRTUAL_TRACK_ROW_BUFFER) or DEFAULT_VIRTUAL_TRACK_ROW_BUFFER)
	)
end

local function getVirtualListMaxRows(config: any): number
	return math.max(
		1,
		math.floor(
			tonumber(config and config.VIRTUAL_TRACK_MAX_RENDERED_ROWS) or DEFAULT_VIRTUAL_TRACK_MAX_RENDERED_ROWS
		)
	)
end

local function getLayoutPaddingOffset(scroll: ScrollingFrame): number
	local layout = scroll:FindFirstChildWhichIsA("UIListLayout")
	if layout then
		return math.max(0, layout.Padding.Offset)
	end
	return 0
end

local function getVirtualRowStride(template: GuiObject, scroll: ScrollingFrame): number
	local height = template.AbsoluteSize.Y
	if height <= 0 then
		height = math.max(1, template.Size.Y.Offset)
	end
	return math.max(1, height + getLayoutPaddingOffset(scroll))
end

local function ensureVirtualSpacer(parent: Instance, name: string, layoutOrder: number): Frame
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Frame") then
		existing.LayoutOrder = layoutOrder
		return existing
	end

	local spacer = Instance.new("Frame")
	spacer.Name = name
	spacer.BackgroundTransparency = 1
	spacer.BorderSizePixel = 0
	spacer.Active = false
	spacer.LayoutOrder = layoutOrder
	spacer.Size = UDim2.fromOffset(1, 0)
	spacer.Parent = parent
	return spacer
end

local function setSpacerHeight(spacer: Frame, height: number)
	spacer.Size = UDim2.new(1, 0, 0, math.max(0, math.floor(height + 0.5)))
	spacer.Visible = height > 0
end

local function renderVirtualList(self: any, options: VirtualListRenderOptions)
	disconnectVirtualList(self, options.key)
	cancelListRenderJob(self, options.key)

	local scroll = options.scroll
	local parent = options.parent or scroll
	local items = options.items
	local totalRows = #items
	local bufferRows = getVirtualListBuffer(self._config)
	local maxRows = getVirtualListMaxRows(self._config)
	local rowStride = getVirtualRowStride(options.template, scroll)
	local topSpacer =
		ensureVirtualSpacer(parent, "CodexVirtualTopSpacer_" .. options.key, VIRTUAL_TOP_SPACER_LAYOUT_ORDER)
	local bottomSpacer =
		ensureVirtualSpacer(parent, "CodexVirtualBottomSpacer_" .. options.key, VIRTUAL_BOTTOM_SPACER_LAYOUT_ORDER)

	options.template.Visible = false
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

	local function redraw()
		if totalRows <= 0 then
			setSpacerHeight(topSpacer, 0)
			setSpacerHeight(bottomSpacer, 0)
			hideUnusedPooledRows(options.pool, 1)
			return
		end

		local viewportRows = math.max(1, math.ceil(scroll.AbsoluteWindowSize.Y / rowStride))
		local renderRows = math.min(totalRows, maxRows, viewportRows + bufferRows * 2)
		local firstVisible = math.floor(math.max(0, scroll.CanvasPosition.Y) / rowStride) + 1
		local startIndex = math.clamp(firstVisible - bufferRows, 1, math.max(1, totalRows - renderRows + 1))
		local endIndex = math.min(totalRows, startIndex + renderRows - 1)

		setSpacerHeight(topSpacer, (startIndex - 1) * rowStride)
		setSpacerHeight(bottomSpacer, (totalRows - endIndex) * rowStride)

		local poolIndex = 1
		for itemIndex = startIndex, endIndex do
			local row = ensurePooledRow(options.pool, poolIndex, options.template, parent)
			disconnectPooledRowConnections(row)
			row.instance.LayoutOrder = VIRTUAL_ROW_LAYOUT_BASE + itemIndex
			options.renderRow(row, items[itemIndex], itemIndex)
			poolIndex += 1
		end
		hideUnusedPooledRows(options.pool, poolIndex)
	end

	redraw()
	self._virtualListConnections[options.key] = {
		scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(redraw),
		scroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(redraw),
	}
	task.defer(redraw)
end

local function animateListRowIn(row: GuiObject)
	local uiScale = ensureUIScale(row)
	local storedScale = row:GetAttribute(LIST_ROW_BASE_SCALE_ATTRIBUTE)
	local targetScale = if type(storedScale) == "number" and storedScale > 0
		then storedScale
		elseif uiScale.Scale > 0 then uiScale.Scale
		else 1
	row:SetAttribute(LIST_ROW_BASE_SCALE_ATTRIBUTE, targetScale)
	uiScale.Scale = targetScale * LIST_ROW_ENTER_SCALE
	TweenService:Create(uiScale, LIST_ROW_ENTER_INFO, { Scale = targetScale }):Play()

	if row:IsA("CanvasGroup") then
		local group = row :: CanvasGroup
		local targetTransparency = group.GroupTransparency
		group.GroupTransparency = math.clamp(targetTransparency + LIST_ROW_ENTER_TRANSPARENCY_DELTA, 0, 1)
		TweenService:Create(group, LIST_ROW_ENTER_INFO, { GroupTransparency = targetTransparency }):Play()
		return
	end

	local targetBackgroundTransparency = row.BackgroundTransparency
	if targetBackgroundTransparency < 1 then
		row.BackgroundTransparency = math.clamp(targetBackgroundTransparency + LIST_ROW_ENTER_TRANSPARENCY_DELTA, 0, 1)
		TweenService:Create(row, LIST_ROW_ENTER_INFO, { BackgroundTransparency = targetBackgroundTransparency }):Play()
	end
end

local function hideIfGuiObject(inst: Instance?)
	if inst and inst:IsA("GuiObject") then
		(inst :: GuiObject).Visible = false
	end
end

local function isProjectOverheadGui(inst: Instance): boolean
	local variant = Config.OverheadGuiVariants[Config.Overhead.GUI_TYPE] or Config.OverheadGuiVariants.V1
	local wrapperName = if type(variant.wrapperName) == "string" then variant.wrapperName else "OverheadGUIMainWrapper"
	local hasSpecificWrapper = wrapperName ~= "Frame" and inst:FindFirstChild(wrapperName, true) ~= nil
	return inst:IsA("BillboardGui")
		and (
			inst.Name == OVERHEAD_TEMPLATE_NAME
			or hasSpecificWrapper
			or inst:FindFirstChild("OverheadGUIMainWrapper", true) ~= nil
		)
end

local function trackConnection(self: any, connection: RBXScriptConnection): RBXScriptConnection
	table.insert(self._connections, connection)
	return connection
end

local function trackUnsubscriber(self: any, unsubscribe: () -> ())
	table.insert(self._unsubscribers, unsubscribe)
	return unsubscribe
end

local function bindClickable(target: Instance?, callback: () -> ())
	if not target then
		return
	end

	if target:IsA("GuiButton") then
		local button = target :: GuiButton
		button.Active = true
		local lastFire = 0
		local function guardedCallback()
			local now = os.clock()
			if now - lastFire < 0.25 then
				return
			end
			lastFire = now
			callback()
		end

		button.Activated:Connect(guardedCallback)
		if button:IsA("ImageButton") or button:IsA("TextButton") then
			(button :: any).MouseButton1Click:Connect(guardedCallback)
		end
		return
	end

	for _, descendant in ipairs(target:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			(descendant :: GuiButton).Activated:Connect(callback)
			return
		end
	end

	if target:IsA("GuiObject") then
		local gui = target :: GuiObject
		gui.Active = true
		gui.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				callback()
			end
		end)
	end
end

local function bindTrackedClickable(connections: { RBXScriptConnection }, target: Instance?, callback: () -> ())
	if not target then
		return
	end

	if target:IsA("GuiButton") then
		local button = target :: GuiButton
		button.Active = true
		local lastFire = 0
		local function guardedCallback()
			local now = os.clock()
			if now - lastFire < 0.25 then
				return
			end
			lastFire = now
			callback()
		end

		table.insert(connections, button.Activated:Connect(guardedCallback))
		if button:IsA("ImageButton") or button:IsA("TextButton") then
			table.insert(connections, (button :: any).MouseButton1Click:Connect(guardedCallback))
		end
		return
	end

	for _, descendant in ipairs(target:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			bindTrackedClickable(connections, descendant, callback)
			return
		end
	end

	if target:IsA("GuiObject") then
		local gui = target :: GuiObject
		gui.Active = true
		table.insert(
			connections,
			gui.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					callback()
				end
			end)
		)
	end
end

local function isManageInteractionBlocked(store: any): boolean
	return store:get().isLoading == true
end

local function findFirstByNames(root: Instance?, names: { string }): Instance?
	if not root then
		return nil
	end

	for _, name in ipairs(names) do
		local direct = root:FindFirstChild(name)
		if direct then
			return direct
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		for _, name in ipairs(names) do
			if descendant.Name == name then
				return descendant
			end
		end
	end

	return nil
end

local function forEachDirectChildByName(root: Instance?, name: string, callback: (Instance) -> ())
	if not root then
		return
	end

	for _, child in ipairs(root:GetChildren()) do
		if child.Name == name then
			callback(child)
		end
	end
end

local function findCoverTextLabel(root: Instance?): TextLabel?
	if not root then
		return nil
	end

	local preferredNames = {
		"PlaylistNameDynamic",
		"PlaylistName",
		"TextLabel",
	}

	for _, name in ipairs(preferredNames) do
		local direct = root:FindFirstChild(name, true)
		if direct and direct:IsA("TextLabel") then
			return direct :: TextLabel
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			return descendant :: TextLabel
		end
	end

	return nil
end

local function getPlaylistTrackCount(playlist: any?): number
	if type(playlist) ~= "table" then
		return 0
	end

	if type(playlist.trackIds) == "table" then
		return #playlist.trackIds
	end

	if type(playlist.tracks) == "table" then
		return #playlist.tracks
	end

	return tonumber(playlist.trackCount or playlist.totalTracks or playlist.tracksCount) or 0
end

local function formatTrackCount(count: number): string
	local safeCount = math.max(0, math.floor(count))
	local suffix = if safeCount == 1 then "Track" else "Tracks"
	return string.format("%d %s", safeCount, suffix)
end

local function setTextLabelByNames(root: Instance?, names: { string }, text: string)
	if not root then
		return
	end
	for _, name in ipairs(names) do
		local label = root:FindFirstChild(name, true)
		if label and label:IsA("TextLabel") then
			(label :: TextLabel).Text = text
			return
		end
	end
end

local function trySetFontFace(label: TextLabel, family: string, weight: Enum.FontWeight): boolean
	return pcall(function()
		label.FontFace = Font.new(family, weight, Enum.FontStyle.Normal)
	end)
end

local function applyNamedFont(label: TextLabel, fontName: string?): boolean
	if not fontName or fontName == "" then
		return true
	end

	if fontName == "Original" then
		return trySetFontFace(label, "rbxassetid://12187365977", Enum.FontWeight.SemiBold)
	end

	local family = "rbxasset://fonts/families/" .. fontName .. ".json"
	return trySetFontFace(label, family, Enum.FontWeight.ExtraBold)
		or trySetFontFace(label, family, Enum.FontWeight.Bold)
		or trySetFontFace(label, family, Enum.FontWeight.SemiBold)
		or trySetFontFace(label, family, Enum.FontWeight.Regular)
end

local function isTextDisplay(inst: Instance?): boolean
	return inst ~= nil and (inst:IsA("TextLabel") or inst:IsA("TextButton"))
end

local function isLabelDisplay(inst: Instance?): boolean
	return inst ~= nil and inst:IsA("TextLabel")
end

local function isInsideAny(candidate: Instance, containers: { Instance }): boolean
	for _, container in ipairs(containers) do
		if candidate == container or candidate:IsDescendantOf(container) then
			return true
		end
	end
	return false
end

local function findTextDisplay(root: Instance?, preferredNames: { string }, excludedAncestors: { Instance }?): Instance?
	if not root then
		return nil
	end

	local exclusions = excludedAncestors or {}

	for _, name in ipairs(preferredNames) do
		local candidate = root:FindFirstChild(name, true)
		if candidate and isTextDisplay(candidate) and not isInsideAny(candidate, exclusions) then
			return candidate
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if isTextDisplay(descendant) and not isInsideAny(descendant, exclusions) then
			return descendant
		end
	end

	return nil
end

local function setTextDisplay(inst: Instance?, text: string)
	if not inst then
		return
	end

	if inst:IsA("TextLabel") then
		(inst :: TextLabel).Text = text
	elseif inst:IsA("TextButton") then
		(inst :: TextButton).Text = text
	end
end

local function setButtonDisplayText(button: Instance?, text: string)
	if not button then
		return
	end

	setTextDisplay(button, text)

	local nestedLabel = button:FindFirstChildWhichIsA("TextLabel", true)
	if nestedLabel then
		nestedLabel.Text = text
	end
end

local function findFirstGuiObjectChild(root: Instance?, preferredNames: { string }?): GuiObject?
	if not root then
		return nil
	end

	if preferredNames then
		for _, name in ipairs(preferredNames) do
			local child = root:FindFirstChild(name)
			if child and child:IsA("GuiObject") then
				return child :: GuiObject
			end
		end
	end

	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("GuiObject") then
			return child :: GuiObject
		end
	end

	return nil
end

local function setSwitchToggleVisual(toggle: Instance?, enabled: boolean)
	if not (toggle and toggle:IsA("GuiObject")) then
		return
	end

	local toggleGui = toggle :: GuiObject
	toggleGui:SetAttribute("ToggleEnabled", enabled == true)
	toggleGui.Active = true

	local track = findFirstGuiObjectChild(toggleGui, { "Track", "Background", "Frame" }) or toggleGui
	local thumb = findFirstGuiObjectChild(track, { "Thumb", "Knob", "Handle", "Frame" })
	if thumb == track then
		thumb = nil
	end

	local activeTrackColor = Color3.fromRGB(245, 245, 245)
	local inactiveTrackColor = Color3.fromRGB(55, 55, 62)
	local activeThumbColor = Color3.fromRGB(18, 18, 22)
	local inactiveThumbColor = Color3.fromRGB(255, 255, 255)

	track.BackgroundColor3 = if enabled then activeTrackColor else inactiveTrackColor
	track.BackgroundTransparency = 0

	if thumb then
		thumb.AnchorPoint = Vector2.new(if enabled then 1 else 0, 0.5)
		thumb.BackgroundColor3 = if enabled then activeThumbColor else inactiveThumbColor
		thumb.BackgroundTransparency = 0
		thumb.Position = UDim2.new(if enabled then 1 else 0, 0, 0.5, 0)
	end
end

local function getSwitchToggleParts(toggle: Instance?): (GuiObject?, GuiObject?)
	if not (toggle and toggle:IsA("GuiObject")) then
		return nil, nil
	end

	local track = findFirstGuiObjectChild(toggle, { "Track", "Background", "Frame" })
	if not track then
		return nil, nil
	end

	local thumb = findFirstGuiObjectChild(track, { "Thumb", "Knob", "Handle", "Frame" })
	if thumb == track then
		thumb = nil
	end

	return track, thumb
end

local function isPointInsideGui(gui: GuiObject?, point: Vector2): boolean
	if not gui or not gui.Visible then
		return false
	end

	local position = gui.AbsolutePosition
	local size = gui.AbsoluteSize
	return point.X >= position.X
		and point.X <= position.X + size.X
		and point.Y >= position.Y
		and point.Y <= position.Y + size.Y
end

local function ensureSwitchToggleHitbox(toggle: GuiObject, track: GuiObject?): TextButton
	local parent = toggle
	local existing = parent:FindFirstChild("RuntimeSwitchHitbox")
	if existing and existing:IsA("TextButton") then
		return existing :: TextButton
	end

	local hitbox = Instance.new("TextButton")
	hitbox.Name = "RuntimeSwitchHitbox"
	hitbox.Text = ""
	hitbox.AutoButtonColor = false
	hitbox.BackgroundTransparency = 1
	hitbox.BorderSizePixel = 0
	hitbox.Active = true
	hitbox.Selectable = false
	hitbox.Size = if track then track.Size else UDim2.fromScale(1, 1)
	hitbox.Position = UDim2.fromScale(0, 0)
	hitbox.AnchorPoint = Vector2.new(0, 0)
	hitbox.ZIndex = math.max(toggle.ZIndex, if track then track.ZIndex else toggle.ZIndex) + 20
	hitbox.Parent = parent
	return hitbox
end

local function bindMainDragSuppression(
	connections: { RBXScriptConnection },
	target: Instance?,
	dragDetector: UIDragDetector?
)
	if not (target and target:IsA("GuiObject") and dragDetector) then
		return
	end

	local suppressed = false
	local function suppress()
		suppressed = true
		dragDetector.Enabled = false
	end

	local function restore()
		suppressed = false
		task.defer(function()
			if not suppressed then
				dragDetector.Enabled = true
			end
		end)
	end

	local function bindGui(gui: GuiObject)
		gui.Active = true
		table.insert(connections, gui.MouseEnter:Connect(suppress))
		table.insert(connections, gui.MouseLeave:Connect(restore))
		table.insert(
			connections,
			gui.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					suppress()
				end
			end)
		)
		table.insert(
			connections,
			gui.InputEnded:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					restore()
				end
			end)
		)
	end

	bindGui(target :: GuiObject)
	for _, descendant in ipairs(target:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			bindGui(descendant :: GuiObject)
		end
	end
end

local function bindSwitchToggleClick(
	connections: { RBXScriptConnection },
	target: Instance?,
	dragDetector: UIDragDetector?,
	callback: () -> (),
	shouldRestoreDrag: (() -> boolean)?
)
	if not (target and target:IsA("GuiObject")) then
		return
	end

	local lastFire = 0
	local function suppressDrag()
		if dragDetector then
			dragDetector.Enabled = false
		end
	end

	local function restoreDrag()
		if dragDetector then
			task.defer(function()
				if shouldRestoreDrag == nil or shouldRestoreDrag() then
					dragDetector.Enabled = true
				end
			end)
		end
	end

	local function fire()
		suppressDrag()
		local now = os.clock()
		if now - lastFire < 0.18 then
			return
		end
		lastFire = now
		callback()
	end

	local function tryFire(input: InputObject)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		fire()
	end

	local function bindGui(gui: GuiObject)
		gui.Active = true
		table.insert(connections, gui.MouseEnter:Connect(suppressDrag))
		table.insert(connections, gui.MouseLeave:Connect(restoreDrag))
		table.insert(connections, gui.InputBegan:Connect(tryFire))
		table.insert(
			connections,
			gui.InputEnded:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					restoreDrag()
				end
			end)
		)
	end

	local targetGui = target :: GuiObject
	local track, thumb = getSwitchToggleParts(targetGui)
	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input)
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end

			local point = Vector2.new(input.Position.X, input.Position.Y)
			if
				isPointInsideGui(targetGui, point)
				or isPointInsideGui(track, point)
				or isPointInsideGui(thumb, point)
			then
				fire()
			end
		end)
	)

	if targetGui:IsA("GuiButton") then
		local button = targetGui :: GuiButton
		button.Active = true
		button.AutoButtonColor = false
		button.Selectable = false
		table.insert(connections, button.MouseEnter:Connect(suppressDrag))
		table.insert(connections, button.MouseLeave:Connect(restoreDrag))
		table.insert(connections, button.Activated:Connect(fire))
		return
	else
		local hitbox = ensureSwitchToggleHitbox(targetGui, track)
		bindGui(hitbox)
		table.insert(connections, hitbox.Activated:Connect(fire))
	end
	bindGui(targetGui)
	if track then
		bindGui(track)
	end
	if thumb then
		bindGui(thumb)
	end
end

local function formatDjNumberText(value: number): string
	local rounded = math.max(0, math.floor(value + 0.5))
	return tostring(rounded)
end

local function formatDjScalarText(value: number): string
	if math.abs(value - math.floor(value + 0.5)) < 0.001 then
		return tostring(math.floor(value + 0.5))
	end
	local text = string.format("%.2f", value)
	text = text:gsub("0+$", "")
	text = text:gsub("%.$", "")
	return text
end

local function formatDjSpeedText(value: number): string
	local safeValue = math.max(0.05, value)
	local text = string.format("%.2f", safeValue)
	text = text:gsub("0+$", "")
	text = text:gsub("%.$", "")
	return text .. "x"
end

local function formatDjDbText(value: number): string
	if math.abs(value) < 0.001 then
		return "0db"
	end
	local rounded = if value >= 0 then math.floor(value + 0.5) else math.ceil(value - 0.5)
	return tostring(rounded) .. "db"
end

local function formatDjEffectValueText(value: number, suffix: string?): string
	local cleanSuffix = tostring(suffix or "")
	if cleanSuffix == "db" then
		return formatDjDbText(value)
	end
	if cleanSuffix == "s" or cleanSuffix == "hz" then
		return formatDjScalarText(value) .. cleanSuffix
	end
	if cleanSuffix ~= "" then
		return formatDjScalarText(value) .. cleanSuffix
	end
	return formatDjScalarText(value)
end

local function djEffectSliderKey(effectId: string, itemId: string): string
	return effectId .. "::" .. itemId
end

local function snapDjSliderValue(raw: number, minValue: number, maxValue: number, step: number): number
	if step <= 0 then
		step = 1
	end
	local snapped = math.floor((raw / step) + 0.5) * step
	return math.clamp(snapped, minValue, maxValue)
end

local function getDjSliderHost(root: Instance?): GuiObject?
	if not root then
		return nil
	end

	local host = findFirstByNames(root, { "AdjustSpeedWrapper", "AdjustWrapper" })
	if host and host:IsA("GuiObject") then
		return host :: GuiObject
	end

	return nil
end

local function setDjSliderVisual(
	root: Instance?,
	value: number,
	minValue: number,
	maxValue: number,
	displayText: string?
)
	local host = getDjSliderHost(root)
	if host then
		local fill = host:FindFirstChild("AdjustableFrameWidth")
		if fill and fill:IsA("Frame") then
			local percent = if maxValue > minValue
				then math.clamp((value - minValue) / (maxValue - minValue), 0, 1)
				else 0
			fill.Size = UDim2.new(percent, 0, 1, 0)
			local dragIcon = fill:FindFirstChild("DraggableIcon")
			if dragIcon and dragIcon:IsA("ImageLabel") then
				local icon = dragIcon :: ImageLabel
				icon.AnchorPoint = Vector2.new(0.5, 0.5)
				icon.Position = UDim2.new(1, 0, 0.5, 0)
			end
		end
	end

	if displayText then
		local valueDisplay = findFirstByNames(root, {
			"SliderCurrentValue",
			"CurrentValue",
			"ValueLabel",
			"Value",
			"StatusValue",
		})
		if isTextDisplay(valueDisplay) then
			setTextDisplay(valueDisplay, displayText)
		end
	end
end

local function setDjPresetButtonVisual(button: Instance?, active: boolean)
	if not button or not button:IsA("GuiObject") then
		return
	end

	local gui = button :: GuiObject
	local baseTransparencyValue = gui:GetAttribute("DjBaseBackgroundTransparency")
	local baseTransparency = if type(baseTransparencyValue) == "number"
		then baseTransparencyValue
		else gui.BackgroundTransparency
	if type(baseTransparencyValue) ~= "number" then
		gui:SetAttribute("DjBaseBackgroundTransparency", baseTransparency)
	end
	gui.BackgroundTransparency = if active then math.max(0, baseTransparency - 0.18) else baseTransparency

	local baseColorValue = gui:GetAttribute("DjBaseBackgroundColor3")
	local baseColor = if typeof(baseColorValue) == "Color3" then baseColorValue else gui.BackgroundColor3
	if typeof(baseColorValue) ~= "Color3" then
		gui:SetAttribute("DjBaseBackgroundColor3", baseColor)
	end
	gui.BackgroundColor3 = if active then baseColor:Lerp(Color3.new(1, 1, 1), 0.12) else baseColor

	local baseTextTransparencyValue = gui:GetAttribute("DjBaseTextTransparency")
	if gui:IsA("TextButton") or gui:IsA("TextLabel") then
		local textDisplay = gui :: any
		local baseTextTransparency = if type(baseTextTransparencyValue) == "number"
			then baseTextTransparencyValue
			else textDisplay.TextTransparency
		if type(baseTextTransparencyValue) ~= "number" then
			gui:SetAttribute("DjBaseTextTransparency", baseTextTransparency)
		end
		textDisplay.TextTransparency = if active then 0 else baseTextTransparency
	end

	local stroke = gui:FindFirstChildWhichIsA("UIStroke")
	if stroke then
		(stroke :: UIStroke).Transparency = if active then 0 else 0.35
	end
end

local function bindDjSlider(
	connections: { RBXScriptConnection },
	root: Instance?,
	minValue: number,
	maxValue: number,
	step: number,
	initialValue: number,
	formatValue: (number) -> string,
	onChange: (number) -> boolean,
	onDragActiveChanged: ((boolean) -> ())?
): (number) -> ()
	local host = getDjSliderHost(root)
	local currentValue = snapDjSliderValue(initialValue, minValue, maxValue, step)
	local dragging = false
	local hoverActive = false
	local previousScrollingEnabled: boolean? = nil
	local scrollingFrame = if root then root:FindFirstAncestorWhichIsA("ScrollingFrame") else nil

	local function applyVisual(nextValue: number)
		setDjSliderVisual(root, nextValue, minValue, maxValue, formatValue(nextValue))
	end

	local function applyFromX(x: number)
		if not host then
			return
		end

		local absPos = host.AbsolutePosition.X
		local absSize = host.AbsoluteSize.X
		local percent = math.clamp((x - absPos) / math.max(absSize, 1), 0, 1)
		local raw = minValue + (maxValue - minValue) * percent
		local nextValue = snapDjSliderValue(raw, minValue, maxValue, step)
		if nextValue ~= currentValue then
			local accepted = onChange(nextValue) ~= false
			if accepted then
				currentValue = nextValue
			end
		end
		applyVisual(currentValue)
	end

	local function beginDrag(x: number)
		if not host then
			return
		end
		if not dragging and scrollingFrame then
			previousScrollingEnabled = scrollingFrame.ScrollingEnabled
			scrollingFrame.ScrollingEnabled = false
		end
		dragging = true
		if onDragActiveChanged and not hoverActive then
			onDragActiveChanged(true)
		end
		applyFromX(x)
	end

	local function endDrag()
		if scrollingFrame and previousScrollingEnabled ~= nil then
			scrollingFrame.ScrollingEnabled = previousScrollingEnabled
		end
		previousScrollingEnabled = nil
		dragging = false
		if onDragActiveChanged and not hoverActive then
			onDragActiveChanged(false)
		end
		applyVisual(currentValue)
	end

	if host then
		host.Active = true
		if onDragActiveChanged then
			table.insert(
				connections,
				host.MouseEnter:Connect(function()
					hoverActive = true
					onDragActiveChanged(true)
				end)
			)
			table.insert(
				connections,
				host.MouseLeave:Connect(function()
					hoverActive = false
					if not dragging then
						onDragActiveChanged(false)
					end
				end)
			)
		end
		table.insert(
			connections,
			host.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					beginDrag(input.Position.X)
				end
			end)
		)

		local fill = host:FindFirstChild("AdjustableFrameWidth")
		if fill and fill:IsA("Frame") then
			fill.Active = true
			table.insert(
				connections,
				fill.InputBegan:Connect(function(input)
					if
						input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch
					then
						beginDrag(input.Position.X)
					end
				end)
			)

			local dragIcon = fill:FindFirstChild("DraggableIcon")
			if dragIcon and dragIcon:IsA("ImageLabel") then
				dragIcon.Active = true
				table.insert(
					connections,
					dragIcon.InputBegan:Connect(function(input)
						if
							input.UserInputType == Enum.UserInputType.MouseButton1
							or input.UserInputType == Enum.UserInputType.Touch
						then
							beginDrag(input.Position.X)
						end
					end)
				)
			end
		end
	end

	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(input)
			if not dragging then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				applyFromX(input.Position.X)
			end
		end)
	)

	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				if dragging then
					endDrag()
				end
			end
		end)
	)

	applyVisual(currentValue)

	return function(nextValue: number)
		currentValue = snapDjSliderValue(nextValue, minValue, maxValue, step)
		applyVisual(currentValue)
	end
end

local function getActionWrapper(form: GuiObject): Instance?
	return form:FindFirstChild("ActionableWrapper")
end

local function hasMultipleDirectChildrenNamed(root: Instance?, name: string): boolean
	if not root then
		return false
	end

	local seen = 0
	for _, child in ipairs(root:GetChildren()) do
		if child.Name == name then
			seen += 1
			if seen > 1 then
				return true
			end
		end
	end

	return false
end

local function setActionWrapperButtonsInteractable(form: GuiObject, primaryButtonName: string, isInteractable: boolean)
	local actionWrapper = getActionWrapper(form)
	if not actionWrapper then
		return
	end

	forEachDirectChildByName(actionWrapper, primaryButtonName, function(child)
		if child:IsA("TextButton") then
			(child :: TextButton).Interactable = isInteractable
		end
	end)

	forEachDirectChildByName(actionWrapper, "CancelButton", function(child)
		if child:IsA("TextButton") then
			(child :: TextButton).Interactable = isInteractable
		end
	end)
end

local function getFormTitleDisplay(form: GuiObject, preferredNames: { string }): Instance?
	local exclusions = {} :: { Instance }
	local scrollable = form:FindFirstChild("ScrollablePlayerList")
	local actionWrapper = getActionWrapper(form)

	if scrollable then
		table.insert(exclusions, scrollable)
	end
	if actionWrapper then
		table.insert(exclusions, actionWrapper)
	end

	return findTextDisplay(form, preferredNames, exclusions)
end

local function getFormHelperDisplay(
	actionWrapper: Instance?,
	primaryButton: Instance?,
	cancelButton: Instance?
): Instance?
	if not actionWrapper then
		return nil
	end

	local exclusions = {} :: { Instance }
	if primaryButton then
		table.insert(exclusions, primaryButton)
	end
	if cancelButton then
		table.insert(exclusions, cancelButton)
	end

	for _, name in ipairs({
		"HelperText",
		"Description",
		"SubTitle",
		"Subtitle",
	}) do
		local candidate = actionWrapper:FindFirstChild(name, true)
		if candidate and isLabelDisplay(candidate) and not isInsideAny(candidate, exclusions) then
			return candidate
		end
	end

	for _, descendant in ipairs(actionWrapper:GetDescendants()) do
		if isLabelDisplay(descendant) and not isInsideAny(descendant, exclusions) then
			return descendant
		end
	end

	return nil
end

local function getTextInput(fieldFrame: Frame): string
	local box = fieldFrame:FindFirstChildWhichIsA("TextBox")
	if box then
		return box.Text
	end
	return ""
end

local function setTextInput(fieldFrame: Frame, text: string)
	local box = fieldFrame:FindFirstChildWhichIsA("TextBox")
	if box then
		(box :: TextBox).Text = text
	end
end

local function _playRequestTrackFeedback(button: Instance?, icon: Instance?)
	local host = nil :: Instance?
	local guiButton = nil :: GuiButton?
	local imageIcon = nil :: (ImageLabel | ImageButton)?

	if button and button:IsA("GuiButton") then
		guiButton = button :: GuiButton
		host = guiButton
	end

	if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
		imageIcon = icon :: ImageLabel | ImageButton
		host = host or imageIcon
	end

	if not host then
		return
	end

	local tokenValue = host:GetAttribute("RequestFeedbackToken")
	local token = (if type(tokenValue) == "number" then tokenValue else 0) + 1
	host:SetAttribute("RequestFeedbackToken", token)

	if guiButton then
		guiButton.Interactable = false
	end

	if imageIcon then
		local iconVisual = imageIcon :: any
		local originalImage = imageIcon:GetAttribute("OriginalRequestTrackImage")
		if type(originalImage) ~= "string" then
			originalImage = iconVisual.Image
			imageIcon:SetAttribute("OriginalRequestTrackImage", originalImage)
		end

		local originalColor = imageIcon:GetAttribute("OriginalRequestTrackColor")
		if typeof(originalColor) ~= "Color3" then
			originalColor = iconVisual.ImageColor3
			imageIcon:SetAttribute("OriginalRequestTrackColor", originalColor)
		end

		iconVisual.Image = REQUEST_TRACK_SUCCESS_ASSET
		iconVisual.ImageColor3 = REQUEST_TRACK_SUCCESS_COLOR
	end

	task.delay(REQUEST_TRACK_FEEDBACK_TIME, function()
		if not host.Parent then
			return
		end
		if host:GetAttribute("RequestFeedbackToken") ~= token then
			return
		end

		if guiButton and guiButton.Parent then
			guiButton.Interactable = true
		end

		if imageIcon and imageIcon.Parent then
			local iconVisual = imageIcon :: any
			local restoreImage = imageIcon:GetAttribute("OriginalRequestTrackImage")
			if type(restoreImage) == "string" then
				iconVisual.Image = restoreImage
			end

			local restoreColor = imageIcon:GetAttribute("OriginalRequestTrackColor")
			if typeof(restoreColor) == "Color3" then
				iconVisual.ImageColor3 = restoreColor
			end
		end
	end)
end

local function resetRequestTrackFeedback(button: Instance?, icon: Instance?)
	local host = nil :: Instance?
	local guiButton = nil :: GuiButton?
	local imageIcon = nil :: (ImageLabel | ImageButton)?

	if button and button:IsA("GuiButton") then
		guiButton = button :: GuiButton
		host = guiButton
	end

	if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
		imageIcon = icon :: ImageLabel | ImageButton
		host = host or imageIcon
	end

	if not host then
		return
	end

	local tokenValue = host:GetAttribute("RequestFeedbackToken")
	local token = (if type(tokenValue) == "number" then tokenValue else 0) + 1
	host:SetAttribute("RequestFeedbackToken", token)

	if guiButton then
		guiButton.Interactable = true
	end

	if imageIcon then
		local iconVisual = imageIcon :: any
		local restoreImage = imageIcon:GetAttribute("OriginalRequestTrackImage")
		if type(restoreImage) == "string" then
			iconVisual.Image = restoreImage
		end

		local restoreColor = imageIcon:GetAttribute("OriginalRequestTrackColor")
		if typeof(restoreColor) == "Color3" then
			iconVisual.ImageColor3 = restoreColor
		end
	end
end

local function buildOrderedPlaylistEntries(playlists: any, searchQuery: string?): { { id: string, playlist: any } }
	local normalizedSearch = string.lower(searchQuery or "")
	local ordered = {}

	for id, playlist in pairs(playlists) do
		local playlistName = tostring(playlist.name or "")
		if normalizedSearch == "" or playlistName:lower():find(normalizedSearch, 1, true) then
			table.insert(ordered, {
				id = tostring(id),
				playlist = playlist,
			})
		end
	end

	table.sort(ordered, function(a, b)
		local aName = tostring(a.playlist.name or ""):lower()
		local bName = tostring(b.playlist.name or ""):lower()
		if aName ~= bName then
			return aName < bName
		end
		return a.id < b.id
	end)

	return ordered
end

local function buildOrderedTrackEntries(
	tracks: any,
	searchQuery: string?,
	selectedPlaylistId: string?,
	newDropsPlaylistId: string
): { any }
	local normalizedSearch = string.lower(searchQuery or "")
	local ordered = {}

	for id, track in pairs(tracks) do
		local trackName = tostring(track.name or "")
		local creatorName = tostring(track.creator or "")
		if
			normalizedSearch == ""
			or trackName:lower():find(normalizedSearch, 1, true)
			or creatorName:lower():find(normalizedSearch, 1, true)
		then
			local trackData = table.clone(track)
			trackData.id = trackData.id or tostring(id)
			table.insert(ordered, trackData)
		end
	end

	table.sort(ordered, function(a, b)
		if selectedPlaylistId == newDropsPlaylistId then
			local aCreatedAt = tonumber(a.createdAt) or 0
			local bCreatedAt = tonumber(b.createdAt) or 0
			if aCreatedAt ~= bCreatedAt then
				return aCreatedAt > bCreatedAt
			end
		end

		local aName = tostring(a.name or ""):lower()
		local bName = tostring(b.name or ""):lower()
		if aName ~= bName then
			return aName < bName
		end

		local aCreator = tostring(a.creator or ""):lower()
		local bCreator = tostring(b.creator or ""):lower()
		if aCreator ~= bCreator then
			return aCreator < bCreator
		end

		return tostring(a.id or "") < tostring(b.id or "")
	end)

	return ordered
end

local function formatClock(totalSeconds: number): string
	local safeTotal = math.max(0, math.floor(totalSeconds + 0.5))
	local minutes = math.floor(safeTotal / 60)
	local seconds = safeTotal % 60
	return string.format("%02d:%02d", minutes, seconds)
end

local function getSpecialPlaylistIds(config: any?): (string, string)
	local favoritesId = tostring((config and config.SPECIAL_PLAYLIST_FAVORITES_ID) or FALLBACK_FAVORITES_PLAYLIST_ID)
	local newDropsId = tostring((config and config.SPECIAL_PLAYLIST_NEW_DROPS_ID) or FALLBACK_NEW_DROPS_PLAYLIST_ID)
	return favoritesId, newDropsId
end

local function applyPlaylistRowState(target: GuiObject, source: GuiObject)
	target.BackgroundColor3 = source.BackgroundColor3
	target.BackgroundTransparency = source.BackgroundTransparency
	target.BorderSizePixel = source.BorderSizePixel

	if target:IsA("GuiButton") and source:IsA("GuiButton") then
		target.AutoButtonColor = false
	end
end

local function capturePlaylistRowState(source: GuiObject): PlaylistRowVisualState
	local captured: PlaylistRowVisualState = {
		backgroundColor3 = source.BackgroundColor3,
		backgroundTransparency = source.BackgroundTransparency,
		borderSizePixel = source.BorderSizePixel,
		autoButtonColor = nil,
	}

	if source:IsA("GuiButton") then
		captured.autoButtonColor = source.AutoButtonColor
	end

	return captured
end

local function restorePlaylistRowState(target: GuiObject, state: PlaylistRowVisualState)
	target.BackgroundColor3 = state.backgroundColor3
	target.BackgroundTransparency = state.backgroundTransparency
	target.BorderSizePixel = state.borderSizePixel

	if target:IsA("GuiButton") then
		target.AutoButtonColor = state.autoButtonColor == true
	end
end

local function setNamedStateGradients(root: Instance, selected: boolean)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("UIGradient") then
			local gradient = descendant :: UIGradient
			local lowerName = string.lower(gradient.Name)
			if string.find(lowerName, "enabled") then
				gradient.Enabled = selected
			elseif string.find(lowerName, "disabled") then
				gradient.Enabled = not selected
			end
		end
	end
end

local function setAllChildGradientsEnabled(root: Instance, enabled: boolean)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("UIGradient") then
			(descendant :: UIGradient).Enabled = enabled
		end
	end
end

local function findIndicatorFrame(root: Instance?): Frame?
	if not root then
		return nil
	end

	local indicator = root:FindFirstChild("NormalStateIndicator", true)
		or root:FindFirstChild("SelectedIndicator", true)
		or root:FindFirstChild("NormalorSelectedIndicatorsNormal", true)

	if indicator then
		local frame = indicator:FindFirstChild("Frame")
		if frame and frame:IsA("Frame") then
			return frame :: Frame
		end
	end

	return nil
end

local function copySelectionTemplateVisual(target: Instance?, template: Instance?)
	if not target or not template then
		return
	end

	if target:IsA("GuiObject") and template:IsA("GuiObject") then
		local targetGui = target :: GuiObject
		local templateGui = template :: GuiObject
		targetGui.BackgroundColor3 = templateGui.BackgroundColor3
		targetGui.BackgroundTransparency = templateGui.BackgroundTransparency
		targetGui.BorderColor3 = templateGui.BorderColor3
		targetGui.BorderSizePixel = templateGui.BorderSizePixel
	end

	if target:IsA("ImageLabel") and template:IsA("ImageLabel") then
		local targetImage = target :: ImageLabel
		local templateImage = template :: ImageLabel
		targetImage.ImageColor3 = templateImage.ImageColor3
		targetImage.ImageTransparency = templateImage.ImageTransparency
	elseif target:IsA("ImageButton") and template:IsA("ImageButton") then
		local targetImage = target :: ImageButton
		local templateImage = template :: ImageButton
		targetImage.ImageColor3 = templateImage.ImageColor3
		targetImage.ImageTransparency = templateImage.ImageTransparency
	elseif target:IsA("TextLabel") and template:IsA("TextLabel") then
		local targetText = target :: TextLabel
		local templateText = template :: TextLabel
		targetText.TextColor3 = templateText.TextColor3
		targetText.TextTransparency = templateText.TextTransparency
	elseif target:IsA("TextButton") and template:IsA("TextButton") then
		local targetText = target :: TextButton
		local templateText = template :: TextButton
		targetText.TextColor3 = templateText.TextColor3
		targetText.TextTransparency = templateText.TextTransparency
	end

	local targetStroke = target:FindFirstChildWhichIsA("UIStroke")
	local templateStroke = template:FindFirstChildWhichIsA("UIStroke")
	if targetStroke and templateStroke then
		targetStroke.Color = templateStroke.Color
		targetStroke.Transparency = templateStroke.Transparency
		targetStroke.Thickness = templateStroke.Thickness
	end

	for _, templateChild in ipairs(template:GetChildren()) do
		if templateChild:IsA("UIGradient") then
			continue
		end
		local targetChild = target:FindFirstChild(templateChild.Name)
		if targetChild then
			copySelectionTemplateVisual(targetChild, templateChild)
		end
	end
end

-- ============================================================
-- Tab switching: instant swap
-- Tab content langsung ditukar tanpa tween.
-- ============================================================

local TAB_FRAME_KEY = {
	nowplaying = "nowPlayingFrame",
	request = "selectSongFrame",
	manage = "manageFrame",
	dj = "djTab",
}

local MAIN_PANEL_BLUR_OPTIONS = {
	enableBlur = true,
	blurName = MAIN_PANEL_BLUR_NAME,
	enableZoom = true,
}

local function shouldUseBackgroundBlur(): boolean
	local panelBlur = Config.PanelBlur
	if type(panelBlur) ~= "table" or panelBlur.ENABLED ~= true then
		return false
	end
	local value = Players.LocalPlayer:GetAttribute(SETTINGS_BACKGROUND_BLUR_ATTRIBUTE)
	return value ~= false
end

local function getPanelBlurSize(): number
	local panelBlur = Config.PanelBlur
	if type(panelBlur) == "table" then
		local size = tonumber(panelBlur.SIZE)
		if size then
			return math.clamp(size, 0, 56)
		end
	end
	return 36
end

local function getModalBackdropTransparency(): number
	local panelBlur = Config.PanelBlur
	if type(panelBlur) == "table" then
		local value = tonumber(panelBlur.MODAL_BACKDROP_TRANSPARENCY)
		if value then
			return math.clamp(value, 0, 1)
		end
	end
	return 0.38
end

local function getPanelBlurFadeIn(): number
	local panelBlur = Config.PanelBlur
	if type(panelBlur) == "table" then
		return tonumber(panelBlur.FADE_IN) or 0.32
	end
	return 0.32
end

local function playModalBlur(blur: BlurEffect, targetSize: number)
	if not shouldUseBackgroundBlur() then
		blur.Size = 0
		blur.Enabled = false
		return
	end

	blur.Enabled = true
	TweenService:Create(
		blur,
		TweenInfo.new(getPanelBlurFadeIn(), Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Size = targetSize }
	):Play()
end

local function getTabFrames(refs: Refs): { [string]: CanvasGroup }
	return {
		nowPlayingFrame = refs.nowPlayingFrame,
		selectSongFrame = refs.selectSongFrame,
		manageFrame = refs.manageFrame,
		djTab = refs.djTab,
	}
end

function MusicPlayerUIBinder:_ensureTabFrameDefaults(frames: { [string]: CanvasGroup })
	if self._tabFrameDefaults then
		return
	end

	local defaults = {} :: { [string]: TabFrameState }
	for key, frame in pairs(frames) do
		defaults[key] = {
			position = frame.Position,
			zIndex = frame.ZIndex,
		}
	end

	self._tabFrameDefaults = defaults
end

function MusicPlayerUIBinder:_restoreTabFrame(frameKey: string, frame: CanvasGroup, isVisible: boolean)
	local defaults = self._tabFrameDefaults and self._tabFrameDefaults[frameKey]
	if defaults then
		frame.Position = defaults.position
		frame.ZIndex = defaults.zIndex
	end

	frame.GroupTransparency = if isVisible then 0 else 1
	frame.Visible = isVisible
end

function MusicPlayerUIBinder:_resetTabFrames(frames: { [string]: CanvasGroup }, activeFrameKey: string)
	self:_ensureTabFrameDefaults(frames)

	for key, frame in pairs(frames) do
		self:_restoreTabFrame(key, frame, key == activeFrameKey)
	end
end

function MusicPlayerUIBinder:_updateTabButtonVisuals(activeTab: string)
	local refs = self._refs

	local tabs = {
		nowplaying = refs.tabs.nowPlaying,
		request = refs.tabs.reqSong,
		dj = refs.tabs.dj,
		manage = refs.tabs.manage,
	}

	for tabKey, button in pairs(tabs) do
		SliderSelectorUtil.setTabButtonSelected(button, tabKey == activeTab)
	end

	local tabOrder = refs.tabButtonOrder
	local backgroundPill = refs.backgroundPill
	if backgroundPill and #tabOrder > 0 then
		local selectedButton = tabs[activeTab]
		if selectedButton then
			task.defer(function()
				if selectedButton.Parent and backgroundPill.Parent then
					SliderSelectorUtil.animateSlidingPill(backgroundPill, selectedButton, tabOrder)
				end
			end)
		end
	end
end

function MusicPlayerUIBinder:_shouldMainDragBeEnabled(): boolean
	return self._store:get().activeTab ~= "dj" and self._mainWrapperDragDetectorEnabled ~= false
end

function MusicPlayerUIBinder:_syncMainDragForActiveTab()
	if self._refs.mainDragDetector then
		self._refs.mainDragDetector.Enabled = self:_shouldMainDragBeEnabled()
	end
end

function MusicPlayerUIBinder:_releaseIdleBlockingOverlays()
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	local coupleGui = playerGui:FindFirstChild("01-CoupleSystemGUI")
	if coupleGui then
		local overlay = coupleGui:FindFirstChild("OverlayFrame")
		local main = coupleGui:FindFirstChild("MainWrapper")
		local notif = coupleGui:FindFirstChild("NotificationWrapper")
		local coupleActive = (main and main:IsA("GuiObject") and main.Visible)
			or (notif and notif:IsA("GuiObject") and notif.Visible)
		if overlay and overlay:IsA("GuiObject") and not coupleActive then
			overlay.Visible = false
			overlay.Active = false
			pcall(function()
				overlay.Interactable = false
			end)
		end
	end
end

function MusicPlayerUIBinder:switchTab(newTab: string)
	local frames = getTabFrames(self._refs)
	local newFrameKey = TAB_FRAME_KEY[newTab]
	if not newFrameKey then
		return
	end

	self._store:set({ activeTab = newTab })
	self:_releaseIdleBlockingOverlays()
	self:_syncMainDragForActiveTab()
	self:_resetTabFrames(frames, newFrameKey)
	self:_updateTabButtonVisuals(newTab)

	if newTab ~= "request" then
		cancelListRenderJob(self, "requestPlaylists")
		cancelListRenderJob(self, "requestTracks")
		disconnectVirtualList(self, "requestTracksLeft")
		disconnectVirtualList(self, "requestTracksRight")
		destroyPooledRows(self._requestTrackLeftRowPool)
		destroyPooledRows(self._requestTrackRightRowPool)
	end
	if newTab ~= "manage" then
		cancelListRenderJob(self, "managePlaylists")
		cancelListRenderJob(self, "manageTracks")
		disconnectVirtualList(self, "manageTracksLeft")
		disconnectVirtualList(self, "manageTracksRight")
		destroyPooledRows(self._manageTrackRowPool)
		destroyPooledRows(self._manageTrackRightRowPool)
	end

	if newTab == "nowplaying" then
		local queue = self._store:get().queue or {}
		self:renderQueue(queue)
	end
end

-- ============================================================
-- Open / close panel using near-cut motion.
-- Hindari scalePop legacy supaya main panel tidak terasa lambat/kartun.
-- ============================================================

function MusicPlayerUIBinder:openPanel()
	local activeTab = self._store:get().activeTab
	local activeFrameKey = TAB_FRAME_KEY[activeTab] or TAB_FRAME_KEY.nowplaying
	self:_releaseIdleBlockingOverlays()
	self:_syncMainDragForActiveTab()
	self:_resetTabFrames(getTabFrames(self._refs), activeFrameKey)
	self:_updateTabButtonVisuals(activeTab)
	self._anim:presentCenterPanel(self._refs.mainWrapper, nil, MAIN_PANEL_BLUR_OPTIONS)
end

function MusicPlayerUIBinder:closePanel(onDone: (() -> ())?)
	local activeTab = self._store:get().activeTab
	local activeFrameKey = TAB_FRAME_KEY[activeTab] or TAB_FRAME_KEY.nowplaying
	local wasMainWrapperHiddenByAddToQueue = self._addToQueueHiddenMainWrapper
	local wasMainWrapperHiddenByPlaylistRelated = self._playlistRelatedHiddenMainWrapper
	local wasMainWrapperHiddenByTrackRelated = self._trackRelatedHiddenMainWrapper
	cancelAllListRenderJobs(self)
	self:_resetTabFrames(getTabFrames(self._refs), activeFrameKey)
	self:setManageSubView("idle")
	self:closeVoteModal(true)
	self:closeAddToQueueConfirmation(true, false)
	self:closePlaylistRelatedModal(true, false)
	self:closeTrackRelatedModal(true, false)
	if self._refs.mainDragDetector then
		self._refs.mainDragDetector.Enabled = self._mainWrapperDragDetectorEnabled ~= false
	end
	if
		wasMainWrapperHiddenByAddToQueue
		or wasMainWrapperHiddenByPlaylistRelated
		or wasMainWrapperHiddenByTrackRelated
	then
		self._refs.mainWrapper.Visible = false
		self._anim:dismissBackdropEffects(MAIN_PANEL_BLUR_OPTIONS, function()
			self:releaseLibraryListPools()
			if onDone then
				onDone()
			end
		end)
		return
	end
	self._anim:dismissCenterPanel(self._refs.mainWrapper, function()
		self:releaseLibraryListPools()
		if onDone then
			onDone()
		end
	end, MAIN_PANEL_BLUR_OPTIONS)
end

function MusicPlayerUIBinder:releaseListPools()
	cancelAllListRenderJobs(self)
	disconnectAllVirtualLists(self)
	destroyPooledRows(self._queueRowPool)
	self:releaseLibraryListPools()
end

function MusicPlayerUIBinder:releaseLibraryListPools()
	cancelAllListRenderJobs(self)
	disconnectVirtualList(self, "requestTracksLeft")
	disconnectVirtualList(self, "requestTracksRight")
	disconnectVirtualList(self, "manageTracksLeft")
	disconnectVirtualList(self, "manageTracksRight")
	destroyPooledRows(self._requestPlaylistRowPool)
	destroyPooledRows(self._requestTrackLeftRowPool)
	destroyPooledRows(self._requestTrackRightRowPool)
	destroyPooledRows(self._managePlaylistRowPool)
	destroyPooledRows(self._manageTrackRowPool)
	destroyPooledRows(self._manageTrackRightRowPool)
	table.clear(self._userThumbnailCache)
	table.clear(self._userThumbnailCacheOrder)
end

function MusicPlayerUIBinder:_populateAddToQueueConfirmation(track: any, parentPlaylist: any?)
	local refs = self._refs
	local template = refs.addToQueueTrackTemplate
	local playlist = parentPlaylist or track.playlist
	local coverSource = resolveCoverSourceForTrack(track, playlist)
	local favoriteTrackIds = self._store:get().favoriteTrackIds or {}
	local isFavorited = type(track.id) == "string" and favoriteTrackIds[track.id] == true
	self._pendingFavoriteShouldRemove = isFavorited == true

	setButtonDisplayText(
		refs.addToQueueFavoriteButton,
		if isFavorited then "Remove from my favorites list" else "Add to my favorites list"
	)

	local coverElement = template:FindFirstChild("RelatedPlaylistCover")
	if coverElement then
		if coverSource then
			self:applyCoverStyle(coverElement, coverSource)
		end

		local playlistNameLabel = findCoverTextLabel(coverElement)
		if playlistNameLabel then
			playlistNameLabel.Text = (playlist and playlist.name) or tostring(track.name or "")
		end
	end

	local infoWrap = template:FindFirstChild("TrackInformationWrapper")
	local info = infoWrap and infoWrap:FindFirstChild("TrackInformation")
	local nestedDetails = info and info:FindFirstChild("TrackDetails")
	local details = nestedDetails or info
	if details then
		local titleLabel = details:FindFirstChild("TrackTitle")
		if titleLabel and titleLabel:IsA("TextLabel") then
			(titleLabel :: TextLabel).Text = tostring(track.name or "")
		end

		local creatorLabel = details:FindFirstChild("TrackCreator")
		if creatorLabel and creatorLabel:IsA("TextLabel") then
			(creatorLabel :: TextLabel).Text = tostring(track.creator or "")
		end
	end

	local addWrap = if info then (info:FindFirstChild("AddToQueueWrapper") or info) else nil
	if addWrap then
		local trackLengthLabel = addWrap:FindFirstChild("TrackLength")
		if trackLengthLabel and trackLengthLabel:IsA("TextLabel") then
			(trackLengthLabel :: TextLabel).Text = formatClock(tonumber(track.totalDuration) or 0)
		end

		local addBtn = addWrap:FindFirstChild("AddToQueueButton")
		if addBtn and addBtn:IsA("GuiObject") then
			addBtn.Visible = false
		end
	end
end

function MusicPlayerUIBinder:_getAddToQueueBlur(): BlurEffect
	if self._addToQueueBlur and self._addToQueueBlur.Parent then
		return self._addToQueueBlur
	end

	local existing = Lighting:FindFirstChild(ADD_TO_QUEUE_BLUR_NAME)
	if existing and existing:IsA("BlurEffect") then
		self._addToQueueBlur = existing
		return existing
	end

	local blur = Instance.new("BlurEffect")
	blur.Name = ADD_TO_QUEUE_BLUR_NAME
	blur.Enabled = false
	blur.Size = 0
	blur.Parent = Lighting
	self._addToQueueBlur = blur
	return blur
end

function MusicPlayerUIBinder:_tweenAddToQueueCamera(targetFov: number, immediate: boolean?)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	if self._addToQueueCameraTween then
		self._addToQueueCameraTween:Cancel()
		self._addToQueueCameraTween = nil
	end

	if immediate then
		camera.FieldOfView = targetFov
		return
	end

	local tween = TweenService:Create(camera, ADD_TO_QUEUE_CAMERA_TWEEN_INFO, {
		FieldOfView = targetFov,
	})
	self._addToQueueCameraTween = tween
	tween.Completed:Once(function()
		if self._addToQueueCameraTween == tween then
			self._addToQueueCameraTween = nil
		end
	end)
	tween:Play()
end

function MusicPlayerUIBinder:_hideMainWrapperForAddToQueue()
	if self._addToQueueHiddenMainWrapper then
		return
	end

	local mainWrapper = self._refs.mainWrapper
	self._addToQueueHiddenMainWrapper = mainWrapper.Visible
	if self._addToQueueHiddenMainWrapper then
		mainWrapper.Visible = false
	end
end

function MusicPlayerUIBinder:_restoreMainWrapperAfterAddToQueue()
	if self._addToQueueHiddenMainWrapper then
		self._refs.mainWrapper.Visible = true
	end
	self._addToQueueHiddenMainWrapper = false
end

function MusicPlayerUIBinder:_clearAddToQueueMainWrapperRestore()
	self._addToQueueHiddenMainWrapper = false
end

function MusicPlayerUIBinder:_suppressAddToQueueOverheadGui(gui: BillboardGui)
	if self._addToQueueSuppressedOverheadSet[gui] then
		return
	end

	self._addToQueueSuppressedOverheadSet[gui] = true
	table.insert(self._addToQueueSuppressedOverheads, {
		gui = gui,
		wasEnabled = gui.Enabled,
	})
	gui.Enabled = false
end

function MusicPlayerUIBinder:_suppressAddToQueueAvatarContext()
	if self._addToQueueAvatarContextWasEnabled ~= nil then
		return
	end

	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local gui = playerGui and playerGui:FindFirstChild(AVATAR_CONTEXT_GUI_NAME)
	if gui and gui:IsA("ScreenGui") then
		self._addToQueueAvatarContextGui = gui
		self._addToQueueAvatarContextWasEnabled = gui.Enabled
		gui.Enabled = false
	end
end

-- ============================================================
-- SHARED WORLD CHROME SUPPRESS CORE
-- Eliminates 3 duplicate Workspace:GetDescendants() scans and
-- 3 concurrent DescendantAdded listeners (max 1 active at a time).
-- ============================================================
function MusicPlayerUIBinder:_suppressWorldChromeCore(
	suppressFn: (self: any, gui: BillboardGui) -> (),
	connectionsTable: { RBXScriptConnection }
)
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if isProjectOverheadGui(descendant) then
			suppressFn(self, descendant :: BillboardGui)
		end
	end
	if #connectionsTable == 0 then
		-- Listener is scoped to modal lifecycle (only active while modal is open),
		-- so the attribute guard is redundant — the connection is created/disconnected
		-- contextually. The attribute is still set for external callers to check.
		table.insert(
			connectionsTable,
			Workspace.DescendantAdded:Connect(function(descendant)
				if isProjectOverheadGui(descendant) then
					suppressFn(self, descendant :: BillboardGui)
				end
			end)
		)
	end
end

function MusicPlayerUIBinder:_suppressAddToQueueWorldChrome()
	Players.LocalPlayer:SetAttribute(ADD_TO_QUEUE_SUPPRESS_ATTRIBUTE, true)
	self:_suppressAddToQueueAvatarContext()
	self:_suppressWorldChromeCore(self._suppressAddToQueueOverheadGui, self._addToQueueSuppressionConnections)
end

function MusicPlayerUIBinder:_restoreAddToQueueWorldChrome()
	Players.LocalPlayer:SetAttribute(ADD_TO_QUEUE_SUPPRESS_ATTRIBUTE, false)

	for _, connection in ipairs(self._addToQueueSuppressionConnections) do
		connection:Disconnect()
	end
	self._addToQueueSuppressionConnections = {}

	for _, entry in ipairs(self._addToQueueSuppressedOverheads) do
		if entry.gui.Parent then
			entry.gui.Enabled = entry.wasEnabled
		end
	end
	self._addToQueueSuppressedOverheads = {}
	self._addToQueueSuppressedOverheadSet = {}

	local avatarContextGui = self._addToQueueAvatarContextGui
	if avatarContextGui and avatarContextGui.Parent and self._addToQueueAvatarContextWasEnabled ~= nil then
		avatarContextGui.Enabled = self._addToQueueAvatarContextWasEnabled
	end
	self._addToQueueAvatarContextGui = nil
	self._addToQueueAvatarContextWasEnabled = nil
end

function MusicPlayerUIBinder:_getPlaylistRelatedBlur(): BlurEffect
	if self._playlistRelatedBlur and self._playlistRelatedBlur.Parent then
		return self._playlistRelatedBlur
	end

	local existing = Lighting:FindFirstChild(PLAYLIST_RELATED_BLUR_NAME)
	if existing and existing:IsA("BlurEffect") then
		self._playlistRelatedBlur = existing
		return existing
	end

	local blur = Instance.new("BlurEffect")
	blur.Name = PLAYLIST_RELATED_BLUR_NAME
	blur.Enabled = false
	blur.Size = 0
	blur.Parent = Lighting
	self._playlistRelatedBlur = blur
	return blur
end

function MusicPlayerUIBinder:_tweenPlaylistRelatedCamera(targetFov: number, immediate: boolean?)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	if self._playlistRelatedCameraTween then
		self._playlistRelatedCameraTween:Cancel()
		self._playlistRelatedCameraTween = nil
	end

	if immediate then
		camera.FieldOfView = targetFov
		return
	end

	local tween = TweenService:Create(camera, PLAYLIST_RELATED_CAMERA_TWEEN_INFO, {
		FieldOfView = targetFov,
	})
	self._playlistRelatedCameraTween = tween
	tween.Completed:Once(function()
		if self._playlistRelatedCameraTween == tween then
			self._playlistRelatedCameraTween = nil
		end
	end)
	tween:Play()
end

function MusicPlayerUIBinder:_hideMainWrapperForPlaylistRelated()
	if self._playlistRelatedHiddenMainWrapper then
		return
	end

	local mainWrapper = self._refs.mainWrapper
	self._playlistRelatedHiddenMainWrapper = mainWrapper.Visible
	if self._playlistRelatedHiddenMainWrapper then
		mainWrapper.Visible = false
	end
end

function MusicPlayerUIBinder:_restoreMainWrapperAfterPlaylistRelated()
	if self._playlistRelatedHiddenMainWrapper then
		self._refs.mainWrapper.Visible = true
	end
	if self._manageFormHiddenMainWrapper then
		self._refs.mainWrapper.Visible = true
		self._manageFormHiddenMainWrapper = false
	end
	self._playlistRelatedHiddenMainWrapper = false
end

function MusicPlayerUIBinder:_clearPlaylistRelatedMainWrapperRestore()
	self._playlistRelatedHiddenMainWrapper = false
end

function MusicPlayerUIBinder:_suppressPlaylistRelatedOverheadGui(gui: BillboardGui)
	if self._playlistRelatedSuppressedOverheadSet[gui] then
		return
	end

	self._playlistRelatedSuppressedOverheadSet[gui] = true
	table.insert(self._playlistRelatedSuppressedOverheads, {
		gui = gui,
		wasEnabled = gui.Enabled,
	})
	gui.Enabled = false
end

function MusicPlayerUIBinder:_suppressPlaylistRelatedAvatarContext()
	if self._playlistRelatedAvatarContextWasEnabled ~= nil then
		return
	end

	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local gui = playerGui and playerGui:FindFirstChild(AVATAR_CONTEXT_GUI_NAME)
	if gui and gui:IsA("ScreenGui") then
		self._playlistRelatedAvatarContextGui = gui
		self._playlistRelatedAvatarContextWasEnabled = gui.Enabled
		gui.Enabled = false
	end
end

function MusicPlayerUIBinder:_suppressPlaylistRelatedWorldChrome()
	Players.LocalPlayer:SetAttribute(ADD_TO_QUEUE_SUPPRESS_ATTRIBUTE, true)
	self:_suppressPlaylistRelatedAvatarContext()
	self:_suppressWorldChromeCore(self._suppressPlaylistRelatedOverheadGui, self._playlistRelatedSuppressionConnections)
end

function MusicPlayerUIBinder:_restorePlaylistRelatedWorldChrome()
	Players.LocalPlayer:SetAttribute(ADD_TO_QUEUE_SUPPRESS_ATTRIBUTE, false)

	for _, connection in ipairs(self._playlistRelatedSuppressionConnections) do
		connection:Disconnect()
	end
	self._playlistRelatedSuppressionConnections = {}

	for _, entry in ipairs(self._playlistRelatedSuppressedOverheads) do
		if entry.gui.Parent then
			entry.gui.Enabled = entry.wasEnabled
		end
	end
	self._playlistRelatedSuppressedOverheads = {}
	self._playlistRelatedSuppressedOverheadSet = {}

	local avatarContextGui = self._playlistRelatedAvatarContextGui
	if avatarContextGui and avatarContextGui.Parent and self._playlistRelatedAvatarContextWasEnabled ~= nil then
		avatarContextGui.Enabled = self._playlistRelatedAvatarContextWasEnabled
	end
	self._playlistRelatedAvatarContextGui = nil
	self._playlistRelatedAvatarContextWasEnabled = nil
end

function MusicPlayerUIBinder:_getTrackRelatedBlur(): BlurEffect
	if self._trackRelatedBlur and self._trackRelatedBlur.Parent then
		return self._trackRelatedBlur
	end

	local existing = Lighting:FindFirstChild(TRACK_RELATED_BLUR_NAME)
	if existing and existing:IsA("BlurEffect") then
		self._trackRelatedBlur = existing
		return existing
	end

	local blur = Instance.new("BlurEffect")
	blur.Name = TRACK_RELATED_BLUR_NAME
	blur.Enabled = false
	blur.Size = 0
	blur.Parent = Lighting
	self._trackRelatedBlur = blur
	return blur
end

function MusicPlayerUIBinder:_tweenTrackRelatedCamera(targetFov: number, immediate: boolean?)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	if self._trackRelatedCameraTween then
		self._trackRelatedCameraTween:Cancel()
		self._trackRelatedCameraTween = nil
	end

	if immediate then
		camera.FieldOfView = targetFov
		return
	end

	local tween = TweenService:Create(camera, TRACK_RELATED_CAMERA_TWEEN_INFO, {
		FieldOfView = targetFov,
	})
	self._trackRelatedCameraTween = tween
	tween.Completed:Once(function()
		if self._trackRelatedCameraTween == tween then
			self._trackRelatedCameraTween = nil
		end
	end)
	tween:Play()
end

function MusicPlayerUIBinder:_hideMainWrapperForTrackRelated()
	if self._trackRelatedHiddenMainWrapper then
		return
	end

	local mainWrapper = self._refs.mainWrapper
	self._trackRelatedHiddenMainWrapper = mainWrapper.Visible
	if self._trackRelatedHiddenMainWrapper then
		mainWrapper.Visible = false
	end
end

function MusicPlayerUIBinder:_restoreMainWrapperAfterTrackRelated()
	if self._trackRelatedHiddenMainWrapper then
		self._refs.mainWrapper.Visible = true
	end
	if self._manageFormHiddenMainWrapper then
		self._refs.mainWrapper.Visible = true
		self._manageFormHiddenMainWrapper = false
	end
	self._trackRelatedHiddenMainWrapper = false
end

function MusicPlayerUIBinder:_clearTrackRelatedMainWrapperRestore()
	self._trackRelatedHiddenMainWrapper = false
end

function MusicPlayerUIBinder:_suppressTrackRelatedOverheadGui(gui: BillboardGui)
	if self._trackRelatedSuppressedOverheadSet[gui] then
		return
	end

	self._trackRelatedSuppressedOverheadSet[gui] = true
	table.insert(self._trackRelatedSuppressedOverheads, {
		gui = gui,
		wasEnabled = gui.Enabled,
	})
	gui.Enabled = false
end

function MusicPlayerUIBinder:_suppressTrackRelatedAvatarContext()
	if self._trackRelatedAvatarContextWasEnabled ~= nil then
		return
	end

	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local gui = playerGui and playerGui:FindFirstChild(AVATAR_CONTEXT_GUI_NAME)
	if gui and gui:IsA("ScreenGui") then
		self._trackRelatedAvatarContextGui = gui
		self._trackRelatedAvatarContextWasEnabled = gui.Enabled
		gui.Enabled = false
	end
end

function MusicPlayerUIBinder:_suppressTrackRelatedWorldChrome()
	Players.LocalPlayer:SetAttribute(ADD_TO_QUEUE_SUPPRESS_ATTRIBUTE, true)
	self:_suppressTrackRelatedAvatarContext()
	self:_suppressWorldChromeCore(self._suppressTrackRelatedOverheadGui, self._trackRelatedSuppressionConnections)
end

function MusicPlayerUIBinder:_restoreTrackRelatedWorldChrome()
	Players.LocalPlayer:SetAttribute(ADD_TO_QUEUE_SUPPRESS_ATTRIBUTE, false)

	for _, connection in ipairs(self._trackRelatedSuppressionConnections) do
		connection:Disconnect()
	end
	self._trackRelatedSuppressionConnections = {}

	for _, entry in ipairs(self._trackRelatedSuppressedOverheads) do
		if entry.gui.Parent then
			entry.gui.Enabled = entry.wasEnabled
		end
	end
	self._trackRelatedSuppressedOverheads = {}
	self._trackRelatedSuppressedOverheadSet = {}

	local avatarContextGui = self._trackRelatedAvatarContextGui
	if avatarContextGui and avatarContextGui.Parent and self._trackRelatedAvatarContextWasEnabled ~= nil then
		avatarContextGui.Enabled = self._trackRelatedAvatarContextWasEnabled
	end
	self._trackRelatedAvatarContextGui = nil
	self._trackRelatedAvatarContextWasEnabled = nil
end

function MusicPlayerUIBinder:_hideTrackRelatedModalFrames()
	local refs = self._refs
	refs.addToTrackConfirmation.Visible = false
	refs.deleteTrackConfirmation.Visible = false
	refs.editTrackConfirmation.Visible = false
end

function MusicPlayerUIBinder:_openTrackRelatedModal(modal: Frame)
	local refs = self._refs
	local blur = self:_getTrackRelatedBlur()
	local camera = Workspace.CurrentCamera
	self:_hideTrackRelatedModalFrames()
	self._activeTrackRelatedModal = modal

	refs.trackRelatedBackdropBlur.Active = true
	refs.trackRelatedBackdropBlur.ZIndex = modal.ZIndex - 1
	refs.trackRelatedBackdropBlur.BackgroundTransparency = 1
	refs.trackRelatedBackdropBlur.Visible = true
	TweenService:Create(refs.trackRelatedBackdropBlur, FADE_INFO_FAST, {
		BackgroundTransparency = getModalBackdropTransparency(),
	}):Play()
	playModalBlur(blur, getPanelBlurSize())
	if camera then
		self._trackRelatedBaseFov = camera.FieldOfView
		self:_tweenTrackRelatedCamera(math.max(1, camera.FieldOfView - TRACK_RELATED_CAMERA_FOV_DELTA))
	end
	self:_suppressTrackRelatedWorldChrome()
	self:_hideMainWrapperForTrackRelated()
	self._isTrackRelatedModalOpen = true

	self._anim:presentDialog(modal)
end

function MusicPlayerUIBinder:closeTrackRelatedModal(immediate: boolean?, restoreMainWrapper: boolean?)
	local refs = self._refs
	local activeModal = self._activeTrackRelatedModal
	local blur = self:_getTrackRelatedBlur()
	local restoreFov = self._trackRelatedBaseFov
	local shouldRestoreMainWrapper = restoreMainWrapper ~= false

	self._pendingTrackModalAction = nil
	self._activeTrackRelatedModal = nil
	self._isTrackRelatedModalOpen = false
	self._trackRelatedBaseFov = nil

	if immediate then
		blur.Size = 0
		blur.Enabled = false
		if restoreFov then
			self:_tweenTrackRelatedCamera(restoreFov, true)
		end
		refs.trackRelatedBackdropBlur.Visible = false
		refs.trackRelatedBackdropBlur.Active = false
		refs.trackRelatedBackdropBlur.BackgroundTransparency = getModalBackdropTransparency()
		self:_restoreTrackRelatedWorldChrome()
		if shouldRestoreMainWrapper then
			self:_restoreMainWrapperAfterTrackRelated()
		else
			self:_clearTrackRelatedMainWrapperRestore()
		end
		if activeModal then
			local modalScale = activeModal:FindFirstChildWhichIsA("UIScale")
			if modalScale then
				modalScale.Scale = 1
			end
		end
		self:_hideTrackRelatedModalFrames()
		return
	end

	TweenService:Create(blur, FADE_INFO_FAST, {
		Size = 0,
	}):Play()
	if restoreFov then
		self:_tweenTrackRelatedCamera(restoreFov)
	end
	refs.trackRelatedBackdropBlur.Active = false
	TweenService:Create(refs.trackRelatedBackdropBlur, FADE_INFO_FAST, {
		BackgroundTransparency = 1,
	}):Play()
	task.delay(FADE_INFO_FAST.Time, function()
		if not self._isTrackRelatedModalOpen then
			blur.Enabled = false
			refs.trackRelatedBackdropBlur.Visible = false
			refs.trackRelatedBackdropBlur.Active = false
			refs.trackRelatedBackdropBlur.BackgroundTransparency = getModalBackdropTransparency()
			self:_restoreTrackRelatedWorldChrome()
		end
	end)

	if activeModal then
		self._anim:dismissDialog(activeModal, function()
			if self._isTrackRelatedModalOpen then
				return
			end
			self:_hideTrackRelatedModalFrames()
			if shouldRestoreMainWrapper then
				self:_restoreMainWrapperAfterTrackRelated()
			else
				self:_clearTrackRelatedMainWrapperRestore()
			end
		end)
	else
		self:_hideTrackRelatedModalFrames()
		if shouldRestoreMainWrapper then
			self:_restoreMainWrapperAfterTrackRelated()
		else
			self:_clearTrackRelatedMainWrapperRestore()
		end
	end
end

function MusicPlayerUIBinder:_openCreateTrackConfirmation(formData: { [string]: any })
	local refs = self._refs
	local preview = self:_buildUpdatedTrackPreview(nil, formData)
	self._pendingTrackModalAction = {
		action = "upload",
		data = formData,
	}
	self:_closeManageFormForConfirmation()
	self:_populateTrackPreviewCard(refs.addToTrackPreviewCard, preview, preview.playlist)
	self:_openTrackRelatedModal(refs.addToTrackConfirmation)
end

function MusicPlayerUIBinder:_openDeleteTrackConfirmation(track: any, data: { [string]: any })
	local refs = self._refs
	self._pendingTrackModalAction = {
		action = "delete",
		data = data,
	}
	self:_populateTrackPreviewCard(refs.deleteTrackPreviewCard, track, track and track.playlist)
	self:_openTrackRelatedModal(refs.deleteTrackConfirmation)
end

function MusicPlayerUIBinder:_openUpdateTrackConfirmation(beforeTrack: any, formData: { [string]: any })
	local refs = self._refs
	local afterTrack = self:_buildUpdatedTrackPreview(beforeTrack, formData)
	self._pendingTrackModalAction = {
		action = "update",
		data = formData,
	}
	self:_closeManageFormForConfirmation()
	self:_populateTrackPreviewCard(refs.editTrackBeforeTemplate, beforeTrack, beforeTrack and beforeTrack.playlist)
	self:_populateTrackPreviewCard(refs.editTrackAfterTemplate, afterTrack, afterTrack.playlist)
	self:_openTrackRelatedModal(refs.editTrackConfirmation)
end

function MusicPlayerUIBinder:_clearManageEditingState()
	self._trackFormCreateMode = true
	self._playlistFormCreateMode = true
	self._store:set({
		editingTrack = nil,
		editingPlaylist = nil,
	})
end

function MusicPlayerUIBinder:_enterManageIdle(preserveEditing: boolean?)
	if preserveEditing == true then
		self:setManageSubView("idle", { preserveEditing = true })
		return
	end
	self._trackFormCreateMode = true
	self._playlistFormCreateMode = true
	if self._onManageSubView then
		self._onManageSubView("idle", nil)
	else
		self:_clearManageEditingState()
		self:setManageSubView("idle")
	end
end

function MusicPlayerUIBinder:_cancelTrackRelatedConfirmation()
	local pending = self._pendingTrackModalAction
	self:closeTrackRelatedModal()
	if not pending or (pending.action ~= "upload" and pending.action ~= "update") then
		return
	end

	local restoreTrack = if pending.action == "update" then self._store:get().editingTrack else nil
	self._trackFormCreateMode = restoreTrack == nil
	if self._onManageSubView then
		self._onManageSubView("edit_track", restoreTrack)
	else
		self._store:set({ editingTrack = restoreTrack })
		self:populateTrackForm(restoreTrack)
		self:setManageSubView("edit_track")
	end
end

function MusicPlayerUIBinder:_cancelPlaylistRelatedConfirmation()
	local pending = self._pendingPlaylistModalAction
	self:closePlaylistRelatedModal()
	if not pending or (pending.action ~= "create" and pending.action ~= "update") then
		return
	end

	local restorePlaylist = if pending.action == "update" then self._store:get().editingPlaylist else nil
	self._playlistFormCreateMode = restorePlaylist == nil
	if self._onManageSubView then
		self._onManageSubView("edit_playlist", restorePlaylist)
	else
		self._store:set({ editingPlaylist = restorePlaylist })
		self:populatePlaylistForm(restorePlaylist)
		self:setManageSubView("edit_playlist")
	end
end

function MusicPlayerUIBinder:_confirmTrackRelatedModal()
	local pending = self._pendingTrackModalAction
	if not pending then
		self:closeTrackRelatedModal()
		return
	end

	local action = pending.action
	local data = pending.data
	self:closeTrackRelatedModal()
	if action == "upload" then
		self:_enterManageIdle(false)
	elseif action == "update" then
		self:setManageSubView("idle", { preserveEditing = true })
	else
		self:_enterManageIdle(false)
	end
	if self._onManageTrack then
		self._onManageTrack(action, data)
	end
end

function MusicPlayerUIBinder:openAddToQueueConfirmation(track: any, parentPlaylist: any?)
	local refs = self._refs
	local blur = self:_getAddToQueueBlur()
	local camera = Workspace.CurrentCamera
	self._pendingRequestTrackId = track.id
	self:_populateAddToQueueConfirmation(track, parentPlaylist)
	refs.addToQueueTrackTemplate.Visible = true
	refs.utilitiesBackdropBlur.Active = true
	refs.utilitiesBackdropBlur.ZIndex = refs.addToQueueConfirmation.ZIndex - 1
	refs.utilitiesBackdropBlur.BackgroundTransparency = 1
	refs.utilitiesBackdropBlur.Visible = true
	TweenService:Create(refs.utilitiesBackdropBlur, FADE_INFO_FAST, {
		BackgroundTransparency = getModalBackdropTransparency(),
	}):Play()
	playModalBlur(blur, getPanelBlurSize())
	if camera then
		self._addToQueueBaseFov = camera.FieldOfView
		self:_tweenAddToQueueCamera(math.max(1, camera.FieldOfView - ADD_TO_QUEUE_CAMERA_FOV_DELTA))
	end
	self:_suppressAddToQueueWorldChrome()
	self:_hideMainWrapperForAddToQueue()
	self._isAddToQueueModalOpen = true
	self._anim:presentDialog(refs.addToQueueConfirmation)
end

function MusicPlayerUIBinder:closeAddToQueueConfirmation(immediate: boolean?, restoreMainWrapper: boolean?)
	local refs = self._refs
	local blur = self:_getAddToQueueBlur()
	local restoreFov = self._addToQueueBaseFov
	local shouldRestoreMainWrapper = restoreMainWrapper ~= false
	self._pendingRequestTrackId = nil
	self._pendingFavoriteShouldRemove = false
	self._isAddToQueueModalOpen = false
	self._addToQueueBaseFov = nil

	if immediate then
		blur.Size = 0
		blur.Enabled = false
		if restoreFov then
			self:_tweenAddToQueueCamera(restoreFov, true)
		end
		refs.utilitiesBackdropBlur.Visible = false
		refs.utilitiesBackdropBlur.Active = false
		refs.utilitiesBackdropBlur.BackgroundTransparency = 1
		refs.addToQueueTrackTemplate.Visible = false
		refs.addToQueueConfirmation.Visible = false
		local modalScale = refs.addToQueueConfirmation:FindFirstChildWhichIsA("UIScale")
		if modalScale then
			modalScale.Scale = 1
		end
		self:_restoreAddToQueueWorldChrome()
		if shouldRestoreMainWrapper then
			self:_restoreMainWrapperAfterAddToQueue()
		else
			self:_clearAddToQueueMainWrapperRestore()
		end
		return
	end

	TweenService:Create(blur, FADE_INFO_FAST, {
		Size = 0,
	}):Play()
	if restoreFov then
		self:_tweenAddToQueueCamera(restoreFov)
	end
	refs.utilitiesBackdropBlur.Active = false
	TweenService:Create(refs.utilitiesBackdropBlur, FADE_INFO_FAST, {
		BackgroundTransparency = 1,
	}):Play()
	task.delay(FADE_INFO_FAST.Time, function()
		if not self._isAddToQueueModalOpen then
			blur.Enabled = false
			refs.utilitiesBackdropBlur.Visible = false
			refs.utilitiesBackdropBlur.Active = false
			self:_restoreAddToQueueWorldChrome()
		end
	end)
	self._anim:dismissDialog(refs.addToQueueConfirmation, function()
		refs.addToQueueTrackTemplate.Visible = false
		if shouldRestoreMainWrapper then
			self:_restoreMainWrapperAfterAddToQueue()
		else
			self:_clearAddToQueueMainWrapperRestore()
		end
	end)
end

function MusicPlayerUIBinder:_getVoteModalBasePosition(): UDim2
	if self._voteModalBasePosition then
		return self._voteModalBasePosition
	end
	self._voteModalBasePosition = self._refs.voteModal.Position
	return self._voteModalBasePosition
end

function MusicPlayerUIBinder:_stopVoteModalCountdown()
	if self._voteModalCountdownConn then
		self._voteModalCountdownConn:Disconnect()
		self._voteModalCountdownConn = nil
	end
end

function MusicPlayerUIBinder:_updateVoteModalTimeVisuals(remaining: number, duration: number)
	local refs = self._refs
	local safeDuration = math.max(duration, 0.001)
	local progress = math.clamp(remaining / safeDuration, 0, 1)
	local secondsLeft = math.max(0, math.ceil(remaining))

	refs.voteCountdownLabel.Text = string.format("%ds", secondsLeft)
	refs.voteLoadingInnerBar.Size = UDim2.new(progress, 0, 1, 0)

	local barColor = VOTE_MODAL_BAR_RED
	if progress >= 0.5 then
		barColor = VOTE_MODAL_BAR_YELLOW:Lerp(VOTE_MODAL_BAR_GREEN, (progress - 0.5) / 0.5)
	else
		barColor = VOTE_MODAL_BAR_RED:Lerp(VOTE_MODAL_BAR_YELLOW, progress / 0.5)
	end
	refs.voteLoadingInnerBar.BackgroundColor3 = barColor
end

function MusicPlayerUIBinder:_populateVoteModal(data: any)
	local refs = self._refs
	local template = refs.voteTrackTemplate
	local track = data.track
	local playlist = data.playlist

	refs.voteDynamicTitle.Text =
		string.format("%s thinks we should skip this one:", tostring(data.initiatorDisplayName or "Someone"))
	refs.voteRejectText.Text =
		string.format("Nah, let it play (%d/%d)", tonumber(data.rejectVotes) or 0, tonumber(data.totalVotes) or 0)
	refs.voteSkipText.Text =
		string.format("Yeah, skip it (%d/%d)", tonumber(data.skipVotes) or 0, tonumber(data.totalVotes) or 0)
	refs.voteSkipButtonText.Text =
		string.format("Vote Skip (%d/%d)", tonumber(data.skipVotes) or 0, tonumber(data.totalVotes) or 0)

	if not track then
		template.Visible = false
		return
	end

	template.Visible = true

	local coverElement = template:FindFirstChild("RelatedPlaylistCover")
	if coverElement then
		if playlist then
			self:applyCoverStyle(coverElement, playlist)
		end

		local playlistNameLabel = findCoverTextLabel(coverElement)
		if playlistNameLabel then
			playlistNameLabel.Text = (playlist and playlist.name) or ""
		end
	end

	local infoWrap = template:FindFirstChild("TrackInformationWrapper")
	local info = infoWrap and infoWrap:FindFirstChild("TrackInformation")
	local details = info and info:FindFirstChild("TrackDetails")
	if details then
		local titleLabel = details:FindFirstChild("TrackTitle")
		if titleLabel and titleLabel:IsA("TextLabel") then
			titleLabel.Text = track.name or ""
		end

		local creatorLabel = details:FindFirstChild("TrackCreator") or details:FindFirstChild("TrackLength")
		if creatorLabel and creatorLabel:IsA("TextLabel") then
			creatorLabel.Text = track.creator or ""
		end
	end

	local addWrap = info and info:FindFirstChild("AddToQueueWrapper")
	if addWrap then
		local trackLengthLabel = addWrap:FindFirstChild("TrackLength")
		if trackLengthLabel and trackLengthLabel:IsA("TextLabel") then
			local totalSeconds = math.max(0, math.floor(tonumber(track.totalDuration) or 0))
			local minutes = math.floor(totalSeconds / 60)
			local seconds = totalSeconds % 60
			trackLengthLabel.Text = string.format("%02d:%02d", minutes, seconds)
			trackLengthLabel.Visible = true
		end

		local addBtn = addWrap:FindFirstChild("AddToQueueButton")
		if addBtn and addBtn:IsA("GuiObject") then
			addBtn.Visible = false
		end
	end
end

function MusicPlayerUIBinder:openOrUpdateVoteModal(data: any)
	local refs = self._refs
	local modal = refs.voteModal
	local blur = refs.utilitiesBackdropBlur
	local uiScale = ensureUIScale(modal)
	local basePosition = self:_getVoteModalBasePosition()
	local isNewSession = self._voteModalSessionId ~= tostring(data.sessionId or "")
	local startedAt = tonumber(data.startedAt) or Workspace:GetServerTimeNow()
	local endsAt = tonumber(data.endsAt) or (startedAt + ((self._config and self._config.VOTE_SKIP_DURATION) or 15))
	local duration = math.max(0.001, endsAt - startedAt)

	self._voteModalSessionId = tostring(data.sessionId or "")
	self:_populateVoteModal(data)
	self:_stopVoteModalCountdown()
	self:_updateVoteModalTimeVisuals(math.max(0, endsAt - Workspace:GetServerTimeNow()), duration)

	blur.Visible = true
	blur.Active = true
	blur.ZIndex = math.max(modal.ZIndex - 1, 0)
	blur.BackgroundTransparency = getModalBackdropTransparency()

	-- v2.2: throttle vote countdown from 60Hz to ~4Hz.
	-- Countdown displays seconds; 60Hz wastes 56 updates per second drawing
	-- the same number. 0.25s interval keeps animation feeling responsive
	-- (no visible stutter at second boundary) while cutting cost ~15x.
	local voteCountdownAccum = 0
	local VOTE_COUNTDOWN_REFRESH_INTERVAL = 0.25
	self._voteModalCountdownConn = RunService.Heartbeat:Connect(function(dt)
		voteCountdownAccum += dt
		if voteCountdownAccum < VOTE_COUNTDOWN_REFRESH_INTERVAL then
			return
		end
		voteCountdownAccum = 0
		local remaining = math.max(0, endsAt - Workspace:GetServerTimeNow())
		self:_updateVoteModalTimeVisuals(remaining, duration)
	end)

	if self._voteModalTween then
		self._voteModalTween:Cancel()
		self._voteModalTween = nil
	end

	if isNewSession or not modal.Visible then
		modal.Visible = true
		modal.Position = UDim2.new(
			basePosition.X.Scale,
			basePosition.X.Offset,
			basePosition.Y.Scale,
			basePosition.Y.Offset - VOTE_MODAL_ENTRY_OFFSET
		)
		uiScale.Scale = 1

		local tween = TweenService:Create(modal, VOTE_MODAL_IN_INFO, {
			Position = basePosition,
		})
		self._voteModalTween = tween
		tween.Completed:Once(function()
			if self._voteModalTween == tween then
				self._voteModalTween = nil
			end
		end)
		tween:Play()
	else
		modal.Visible = true
		modal.Position = basePosition
		uiScale.Scale = 1
	end
end

function MusicPlayerUIBinder:closeVoteModal(immediate: boolean?)
	local refs = self._refs
	local modal = refs.voteModal
	local blur = refs.utilitiesBackdropBlur
	local uiScale = ensureUIScale(modal)
	local basePosition = self:_getVoteModalBasePosition()

	self._voteModalSessionId = nil
	self:_stopVoteModalCountdown()
	refs.voteSkipButtonText.Text = "Vote Skip"

	if self._voteModalTween then
		self._voteModalTween:Cancel()
		self._voteModalTween = nil
	end

	if immediate then
		refs.voteTrackTemplate.Visible = false
		modal.Visible = false
		modal.Position = basePosition
		uiScale.Scale = 1
		blur.Active = false
		blur.Visible = false
		blur.BackgroundTransparency = 1
		return
	end

	if not modal.Visible then
		refs.voteTrackTemplate.Visible = false
		modal.Position = basePosition
		uiScale.Scale = 1
		blur.Active = false
		blur.Visible = false
		blur.BackgroundTransparency = 1
		return
	end

	local tween = TweenService:Create(modal, VOTE_MODAL_OUT_INFO, {
		Position = UDim2.new(
			basePosition.X.Scale,
			basePosition.X.Offset,
			basePosition.Y.Scale,
			basePosition.Y.Offset - VOTE_MODAL_ENTRY_OFFSET
		),
	})
	self._voteModalTween = tween
	refs.voteTrackTemplate.Visible = false
	blur.Active = false
	TweenService:Create(blur, FADE_INFO_FAST, {
		BackgroundTransparency = 1,
	}):Play()
	tween.Completed:Once(function()
		if self._voteModalTween == tween then
			self._voteModalTween = nil
		end
		modal.Visible = false
		modal.Position = basePosition
		uiScale.Scale = 1
		blur.Visible = false
		blur.BackgroundTransparency = 1
	end)
	tween:Play()
end

-- ============================================================
-- Now playing track info
-- ============================================================

function MusicPlayerUIBinder:updateTrackDisplay(track: any?)
	local refs = self._refs
	if track then
		refs.trackTitle.Text = track.name or ""
		refs.trackCreator.Text = track.creator or ""
		local playlistsById = self._store:get().playlists or {}
		local parentPlaylist = track.playlist or playlistsById[track.playlistId]
		local coverSource = resolveCoverSourceForTrack(track, parentPlaylist)
		refs.playlistTitle.Text = if parentPlaylist then tostring(parentPlaylist.name or "") else ""
		if track.isSystemAssigned == true then
			refs.requesterDisplayName.Text = "Auto Playlist"
		else
			local requesterName = tostring(track.requesterDisplayName or "")
			if requesterName == "" then
				local currentEntry = self._store:get().currentEntry
				if type(currentEntry) == "table" and currentEntry.source == "user" then
					requesterName = tostring(currentEntry.requesterDisplayName or "")
				end
			end
			refs.requesterDisplayName.Text = requesterName
		end
		self._totalDuration = track.totalDuration or 0

		-- Apply playlist cover style to Now Playing background
		if coverSource then
			-- Update background gradient directly via resolved ref
			local bgGradient = refs.dependsOnPlaylist
			if bgGradient and bgGradient:IsA("UIGradient") then
				local config = self._config
				local coverType = coverSource.coverType or "gradient"
				if coverType ~= "image" then
					local gradients = config and config.COVER_GRADIENTS
					local gIdx = tonumber(coverSource.coverValue) or 1
					if gradients and gIdx >= 1 and gIdx <= #gradients then
						local g = gradients[gIdx]
						bgGradient.Color = buildCoverGradientColorSequence(g)
						bgGradient.Rotation = getCoverGradientRotation(g)
						bgGradient.Enabled = true
					end
				else
					bgGradient.Enabled = false
				end
			end
			self:applyCoverStyle(refs.playlistColorOrImage, coverSource)
			if refs.playlistColorOrImage then
				refs.playlistColorOrImage.Visible = (coverSource.coverType or "gradient") ~= "gradient"
			end
		elseif refs.playlistColorOrImage then
			refs.playlistColorOrImage.Image = ""
			refs.playlistColorOrImage.Visible = false
			local coverText = findCoverTextLabel(refs.playlistColorOrImage)
			if coverText then
				coverText.Text = ""
			end
		end
		if refs.requesterProfilePicture then
			if track.isSystemAssigned == true then
				refs.requesterProfilePicture.Visible = false
			else
				refs.requesterProfilePicture.Visible = true
				self:_setRequesterThumbnail(refs.requesterProfilePicture, tonumber(track.requesterUserId))
			end
		end

		self:_updateNowPlayingStatusCallouts(track)
		self:_updateNowPlayingFavoriteState(track)
		self:_updateAuraOverlay(coverSource)

		local state = self._store:get()
		local elapsed, total = self:_getProgressSeconds(state)
		self:_updateNowPlayingTimeLabels(elapsed, total)
	else
		refs.trackTitle.Text = "No track playing"
		refs.trackCreator.Text = ""
		refs.playlistTitle.Text = ""
		refs.requesterDisplayName.Text = ""
		self._totalDuration = 0
		if refs.playlistColorOrImage and refs.playlistColorOrImage:IsA("ImageLabel") then
			refs.playlistColorOrImage.Image = ""
			refs.playlistColorOrImage.Visible = false
			local coverText = findCoverTextLabel(refs.playlistColorOrImage)
			if coverText then
				coverText.Text = ""
			end
		end
		if refs.requesterProfilePicture and refs.requesterProfilePicture:IsA("ImageLabel") then
			refs.requesterProfilePicture.Image = ""
		end
		self:_updateNowPlayingStatusCallouts(nil)
		self:_updateAuraOverlay(nil)
		-- Reset progress bar
		self:_updateProgressBar(0)
		self:_updateNowPlayingTimeLabels(0, 0)
		self:_updateNowPlayingFavoriteState(nil)
	end
end

function MusicPlayerUIBinder:setLoudnessSoundProvider(provider: () -> { Sound })
	self._loudnessSoundProvider = provider
end

function MusicPlayerUIBinder:_updateAuraOverlay(playlist: any?)
	local refs = self._refs
	local nowPlayingWrapper = refs.nowPlayingWrapper
	if not nowPlayingWrapper then
		return
	end
	local aura = nowPlayingWrapper:FindFirstChild("AuraOverlay") :: ImageLabel?
	if not aura or not aura:IsA("ImageLabel") then
		return
	end

	-- ── Gradient color (fade transition) ────────────────────────
	local uiGradient = aura:FindFirstChildOfClass("UIGradient")
	if not uiGradient then
		uiGradient = Instance.new("UIGradient")
		uiGradient.Parent = aura
	end

	local targetColor: ColorSequence
	local config = self._config
	if playlist == nil then
		targetColor = ColorSequence.new(Color3.fromRGB(30, 30, 30), Color3.fromRGB(0, 0, 0))
	elseif (playlist.coverType or "gradient") == "image" then
		local accent = getPlaylistCoverAccentColor(playlist, config, self._imageCoverDarkestColors)
			or getStableAccentColor(playlist.coverValue or playlist.name)
		targetColor = ColorSequence.new(accent:Lerp(Color3.new(1, 1, 1), 0.18), accent:Lerp(Color3.new(0, 0, 0), 0.38))
	else
		-- Gradient cover: use exact same source as applyCoverStyle
		local gradients = config and config.COVER_GRADIENTS
		local gradientIndex = tonumber(playlist.coverValue) or 1
		if gradients and type(gradients) == "table" and gradientIndex >= 1 and gradientIndex <= #gradients then
			local g = gradients[gradientIndex]
			targetColor = buildCoverGradientColorSequence(g)
		else
			targetColor = ColorSequence.new(Color3.fromRGB(80, 80, 80), Color3.fromRGB(20, 20, 20))
		end
	end

	-- Tween gradient via intermediate binding (ColorSequence can't be tweened directly;
	-- use a 0→1 NumberValue driven by TweenService, sampling lerp each Heartbeat frame).
	if self._auraGradientTween then
		self._auraGradientTween:Cancel()
		self._auraGradientTween = nil
	end
	if self._auraGradientConn then
		self._auraGradientConn:Disconnect()
		self._auraGradientConn = nil
	end

	local FADE_DURATION = 0.5
	local fromKeys = uiGradient.Color.Keypoints
	local fromColor0 = fromKeys[1].Value
	local fromColor1 = fromKeys[#fromKeys].Value
	local toColor0 = targetColor.Keypoints[1].Value
	local toColor1 = targetColor.Keypoints[#targetColor.Keypoints].Value

	local proxy = Instance.new("NumberValue")
	proxy.Value = 0
	local tweenInfo = TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(proxy, tweenInfo, { Value = 1 })
	local gradientConn = proxy.Changed:Connect(function(t)
		local c0 = fromColor0:Lerp(toColor0, t)
		local c1 = fromColor1:Lerp(toColor1, t)
		uiGradient.Color = ColorSequence.new(c0, c1)
	end)
	self._auraGradientConn = gradientConn
	tween.Completed:Connect(function()
		-- Protect against race when a newer tween already replaced this connection.
		if gradientConn.Connected then
			gradientConn:Disconnect()
		end
		if self._auraGradientConn == gradientConn then
			self._auraGradientConn = nil
		end
		-- Ensure exact landing color even if last Changed step is skipped.
		uiGradient.Color = targetColor
		proxy:Destroy()
	end)
	self._auraGradientTween = tween
	tween:Play()

	-- ── Loudness-driven breath (Heartbeat) ───────────────────────
	if self._auraHeartbeatConn then
		self._auraHeartbeatConn:Disconnect()
		self._auraHeartbeatConn = nil
	end

	if playlist == nil then
		for index = 1, #self._auraSoundCache do
			self._auraSoundCache[index] = nil
		end
		self._auraSoundScanClock = 0
		-- Restore scale to 1 and reset position
		local auraScale = ensureUIScale(aura)
		TweenService
			:Create(auraScale, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		-- Position will auto-correct on next heartbeat; if heartbeat is stopped, reset manually
		return
	end

	local auraScale = ensureUIScale(aura)
	local auraImg = aura :: ImageLabel

	-- Only scale is animated — transparency stays at original GUI value (0)
	auraImg.ImageTransparency = 0

	-- ── Tuning ────────────────────────────────────────────────
	local BASE_SCALE = 1.0
	local MAX_SCALE_ADD = 0.32 -- max expansion
	-- Attack: cepat tangkap beat
	local ATTACK = 0.70 -- lerp factor naik (frame-rate independent base)
	-- Decay: "ballistic" — energy halved every DECAY_HALF seconds
	local DECAY_HALF = 0.38
	-- Rolling max untuk auto-normalize (adaptif ke volume musik)
	local ROLLING_DECAY = 0.9992
	local ROLLING_MIN = 180

	local currentScale = auraScale.Scale
	local rollingMax = ROLLING_MIN
	-- "energy" terpisah dari visual — visual smoothed terhadap energy
	local energy = 0.0

	local function refreshSoundCache(scanClock: number)
		local soundCache = self._auraSoundCache
		for index = 1, #soundCache do
			soundCache[index] = nil
		end

		local provider = self._loudnessSoundProvider
		if type(provider) == "function" then
			for _, sound in ipairs(provider()) do
				if typeof(sound) == "Instance" and sound:IsA("Sound") and sound.Parent ~= nil then
					soundCache[#soundCache + 1] = sound :: Sound
				end
			end
		else
			for _, descendant in ipairs(SoundService:GetDescendants()) do
				if descendant:IsA("Sound") then
					soundCache[#soundCache + 1] = descendant :: Sound
				end
			end
		end

		self._auraSoundScanClock = scanClock
	end

	refreshSoundCache(os.clock())

	local function getLoudness(): number
		local scanClock = os.clock()
		if scanClock - self._auraSoundScanClock >= self._auraSoundScanInterval then
			refreshSoundCache(scanClock)
		end

		local best = 0
		local soundCache = self._auraSoundCache
		local writeIndex = 1
		for readIndex = 1, #soundCache do
			local sound = soundCache[readIndex]
			if sound.Parent ~= nil then
				if writeIndex ~= readIndex then
					soundCache[writeIndex] = sound
				end
				writeIndex += 1

				if sound.IsPlaying then
					local l = sound.PlaybackLoudness
					if l > best then
						best = l
					end
				end
			end
		end

		for index = writeIndex, #soundCache do
			soundCache[index] = nil
		end

		return best
	end

	-- v2.2: throttle aura overlay from 60Hz to ~20Hz.
	-- PlaybackLoudness sampling at 60Hz is overkill for visual envelope;
	-- human eye perception of beat sync caps around 15-20Hz. Attack/decay
	-- math remains frame-rate independent because we feed accumulated dt.
	local auraAccum = 0
	local AURA_REFRESH_INTERVAL = 0.05
	self._auraHeartbeatConn = RunService.Heartbeat:Connect(function(dt)
		auraAccum += dt
		if auraAccum < AURA_REFRESH_INTERVAL then
			return
		end
		dt = auraAccum
		auraAccum = 0
		local loudness = getLoudness()

		-- Adaptive normalization
		if loudness > rollingMax then
			rollingMax = loudness
		else
			rollingMax = math.max(rollingMax * ROLLING_DECAY, ROLLING_MIN)
		end

		local raw = math.clamp(loudness / rollingMax, 0, 1)
		-- Soft-knee curve: sqrt untuk bawah lembut, kuadrat untuk puncak tajam
		-- Hasilnya: quiet terasa smooth, beat keras tetap punch
		local t = raw < 0.5 and (raw * raw * 2) -- lower half: kuadratik (lembut)
			or (1 - 2 * (1 - raw) ^ 2) -- upper half: ease-out (punch tapi smooth)

		-- Energy envelope: attack cepat, decay ballistic (half-life based)
		if t > energy then
			-- Naik: frame-rate independent attack lerp
			local f = 1 - (1 - ATTACK) ^ (dt * 60)
			energy = energy + (t - energy) * f
		else
			-- Turun: exponential half-life decay — halved setiap DECAY_HALF detik
			energy = energy * (0.5 ^ (dt / DECAY_HALF))
		end

		local targetScale = BASE_SCALE + energy * MAX_SCALE_ADD

		-- Tambahan smoothing ringan pada visual supaya tidak ada jitter
		local VISUAL_SMOOTH = 0.25
		local vs = 1 - (1 - VISUAL_SMOOTH) ^ (dt * 60)

		currentScale = currentScale + (targetScale - currentScale) * vs

		auraScale.Scale = currentScale
		-- ImageTransparency fixed at 0 — only scale is animated
	end)
end

local TIPS_MESSAGES = {
	"Looking for volume option? check on settings.",
	"Use the search bar to find tracks quickly.",
	"You can add tracks to your favorites anytime.",
	"Vote Skip lets the crowd decide the next song.",
	"Create playlists to organise your music.",
}

function MusicPlayerUIBinder:_startTipsLoop()
	if self._tipsLoopConn then
		return
	end
	local refs = self._refs
	local tips = refs.tipsDynamic
	if not tips then
		return
	end
	-- Always visible; rotate message every 5 seconds
	tips.Visible = true
	local tipIndex = 1
	local function setTipText()
		local textLabel = tips:FindFirstChildWhichIsA("TextLabel", true) or (tips:IsA("TextLabel") and tips)
		if textLabel and textLabel:IsA("TextLabel") then
			(textLabel :: TextLabel).Text = TIPS_MESSAGES[tipIndex]
		end
	end
	setTipText()
	self._tipsLoopConn = task.spawn(function()
		while true do
			if not self._refs.tipsDynamic then
				break
			end
			task.wait(5)
			if not self._refs.tipsDynamic then
				break
			end
			local djInfo = self._refs.controlledByDjInfo
			if djInfo and djInfo.Visible then
				continue
			end
			tipIndex = (tipIndex % #TIPS_MESSAGES) + 1
			setTipText()
		end
	end)
end

function MusicPlayerUIBinder:_stopTipsLoop()
	if self._tipsLoopConn then
		local ok = pcall(function()
			coroutine.close(self._tipsLoopConn :: thread)
		end)
		if not ok then
		end
		self._tipsLoopConn = nil
	end
	local refs = self._refs
	if refs.tipsDynamic then
		refs.tipsDynamic.Visible = false
	end
end

function MusicPlayerUIBinder:_updateNowPlayingStatusCallouts(track: any?)
	local refs = self._refs
	local storeState = self._store:get()
	local isDjMode = storeState.isDjMode == true
	local isDjControlled = isDjMode and type(track) == "table" and track.isSystemAssigned ~= true

	if refs.controlledByDjInfo then
		refs.controlledByDjInfo.Visible = isDjControlled
		local textLabel = refs.controlledByDjInfo:FindFirstChildWhichIsA("TextLabel", true)
		if textLabel then
			local djName = track and track.controllerDisplayName or storeState.djPlayerDisplayName or "DJ"
			(textLabel :: TextLabel).Text = string.format("This set is currently controlled by %s", djName)
		end
	end

	if refs.tipsDynamic then
		local textLabel = refs.tipsDynamic:FindFirstChildWhichIsA("TextLabel", true)
		if textLabel then
			(textLabel :: TextLabel).Text = "Looking for volume option? check on settings."
		end
		if isDjControlled then
			self:_stopTipsLoop()
			refs.tipsDynamic.Visible = false
		else
			self:_startTipsLoop()
		end
	end
end

function MusicPlayerUIBinder:_updateNowPlayingFavoriteState(track: any?)
	local refs = self._refs
	local favoriteTrackIds = self._store:get().favoriteTrackIds or {}
	local trackId: string? = nil
	if type(track) == "table" and type(track.id) == "string" then
		trackId = track.id
	end

	local isFavorited = false
	if trackId ~= nil then
		isFavorited = favoriteTrackIds[trackId] == true
	end
	if refs.addToFavoritesButton then
		refs.addToFavoritesButton.BackgroundTransparency = if isFavorited then 0 else 1
	end

	local hasTrack = trackId ~= nil
	if refs.addToFavoritesButton then
		refs.addToFavoritesButton.Active = hasTrack
		refs.addToFavoritesButton.Interactable = hasTrack
	end
end

function MusicPlayerUIBinder:_getProgressSeconds(state: any?): (number, number)
	local storeState = state or self._store:get()
	local timing = storeState.playbackTiming
	local now = Workspace:GetServerTimeNow()
	if type(timing) == "table" then
		local total = MusicDomain.getTimingTotalSeconds(timing)
		local elapsed = if storeState.isPlaying
			then MusicDomain.getTimingElapsedSeconds(timing, now)
			else 0
		return math.min(elapsed, total), total
	end

	local total = 0
	local startServerTime = tonumber(storeState.startServerTime) or 0
	local expectedEndServerTime = tonumber(storeState.expectedEndServerTime) or 0
	if startServerTime > 0 and expectedEndServerTime > startServerTime then
		total = expectedEndServerTime - startServerTime
	else
		total = math.max(0, tonumber(self._totalDuration) or 0)
	end
	local elapsed = if storeState.isPlaying
		then math.max(0, now - (tonumber(storeState.startServerTime) or 0))
		else 0
	return math.min(elapsed, total), total
end

function MusicPlayerUIBinder:refreshProgressFromStore()
	local state = self._store:get()
	if not state.isPlaying then
		return
	end
	local elapsed, total = self:_getProgressSeconds(state)
	local progress = if total > 0 then math.clamp(elapsed / total, 0, 1) else 0
	self:_updateProgressBar(progress)
	self:_updateNowPlayingTimeLabels(elapsed, total)
end

function MusicPlayerUIBinder:_updateNowPlayingTimeLabels(elapsedSeconds: number, totalSeconds: number)
	local progressWrapper = self._refs.trackProgressWrapper
	local numberFrame = progressWrapper:FindFirstChild("Number")
	if not numberFrame or not numberFrame:IsA("Frame") then
		return
	end

	local currentLabel = numberFrame:FindFirstChild("DetikSaatIni")
	if currentLabel and currentLabel:IsA("TextLabel") then
		(currentLabel :: TextLabel).Text = formatClock(elapsedSeconds)
	end

	local totalLabel = numberFrame:FindFirstChild("SongLength")
	if totalLabel and totalLabel:IsA("TextLabel") then
		(totalLabel :: TextLabel).Text = formatClock(totalSeconds)
	end
end

-- ============================================================
-- PROGRESS BAR (Heartbeat)
-- ============================================================

function MusicPlayerUIBinder:startProgressTracking()
	if self._progressConn then
		self._progressConn:Disconnect()
		self._progressConn = nil
	end

	local progressWrapper = self._refs.trackProgressWrapper
	local progressBar = progressWrapper:FindFirstChild("ProgressBar")
	local fillFrame = if progressBar and progressBar:IsA("Frame") then progressBar:FindFirstChild("InnerBar") else nil

	-- v2.2: throttle progress refresh from 60Hz to ~5Hz.
	-- A song is 3-5 minutes long; 60Hz updates move the fill ~0.0033% per
	-- frame which is well below human perception. 5Hz (0.2s) is still smooth
	-- enough to look continuous while cutting cost 12x. Time labels show
	-- second precision only, so 5Hz is more than enough.
	local progressAccum = 0
	local PROGRESS_REFRESH_INTERVAL = 0.2
	self._progressConn = RunService.Heartbeat:Connect(function(dt)
		progressAccum += dt
		if progressAccum < PROGRESS_REFRESH_INTERVAL then
			return
		end
		progressAccum = 0
		local state = self._store:get()
		if not state.isPlaying then
			return
		end
		local elapsed, total = self:_getProgressSeconds(state)
		if total <= 0 then
			return
		end
		local progress = math.clamp(elapsed / total, 0, 1)
		self:_updateProgressBar(progress, fillFrame)
		self:_updateNowPlayingTimeLabels(elapsed, total)
	end)
end

function MusicPlayerUIBinder:stopProgressTracking()
	if self._progressConn then
		self._progressConn:Disconnect()
		self._progressConn = nil
	end
end

function MusicPlayerUIBinder:_updateProgressBar(progress: number, fillFrame: Frame?)
	local fill = fillFrame
	if not fill then
		local progressBar = self._refs.trackProgressWrapper:FindFirstChild("ProgressBar")
		if progressBar and progressBar:IsA("Frame") then
			local innerBar = progressBar:FindFirstChild("InnerBar")
			if innerBar and innerBar:IsA("Frame") then
				fill = innerBar
			end
		end
	end
	if fill then
		fill.Size = UDim2.new(progress, 0, 1, 0)
	end
end

-- ============================================================
-- VOLUME SLIDER (client-side only)
-- ============================================================

function MusicPlayerUIBinder:bindVolumeSlider()
	-- Volume control was removed from Now Playing in v2.
	-- Keep this method around so older init paths do not fail.
end

function MusicPlayerUIBinder:_updateDjSpeedPresetVisuals()
	for presetValue, button in pairs(self._djSpeedPresetButtons) do
		setDjPresetButtonVisual(button, math.abs((self._djPlaybackSpeed or 0) - presetValue) < 0.001)
	end
end

function MusicPlayerUIBinder:setDjPlaybackSpeed(speed: number)
	local safeSpeed = math.clamp(tonumber(speed) or self._djPlaybackSpeed or 1, 0.25, 2)
	self._djPlaybackSpeed = safeSpeed
	local displayText = formatDjSpeedText(safeSpeed)
	if self._djPlaybackSpeedSliderSetter then
		self._djPlaybackSpeedSliderSetter(safeSpeed)
	elseif self._djPlaybackSpeedSliderRoot then
		setDjSliderVisual(self._djPlaybackSpeedSliderRoot, safeSpeed, 0.25, 2.0, displayText)
	end
	if self._djPlaybackSpeedHeaderValueLabel then
		setTextDisplay(self._djPlaybackSpeedHeaderValueLabel, displayText)
	end
	self:_updateDjSpeedPresetVisuals()
end

function MusicPlayerUIBinder:setDjEffectEnabled(effectId: string, enabled: boolean)
	local key = tostring(effectId or "")
	self._djEffectEnabledById[key] = enabled == true
	local toggle = self._djEffectToggleButtons[key]
	if toggle then
		setSwitchToggleVisual(toggle, self._djEffectEnabledById[key])
		task.defer(setSwitchToggleVisual, toggle, self._djEffectEnabledById[key])
	end
end

function MusicPlayerUIBinder:setDjEffectValue(effectId: string, itemId: string, value: number)
	local effectKey = tostring(effectId or "")
	local itemKey = tostring(itemId or "")
	local effectValues = self._djEffectValues[effectKey]
	if not effectValues then
		effectValues = {}
		self._djEffectValues[effectKey] = effectValues
	end
	effectValues[itemKey] = tonumber(value) or 0

	local sliderKey = djEffectSliderKey(effectKey, itemKey)
	local setter = self._djEffectSliderSetters[sliderKey]
	if setter then
		setter(effectValues[itemKey])
	end
end

function MusicPlayerUIBinder:setDjBassEnabled(enabled: boolean)
	self:setDjEffectEnabled("equalizer", enabled)
end

function MusicPlayerUIBinder:setDjBassValue(value: number)
	self:setDjEffectValue("equalizer", "low", tonumber(value) or 0)
end

function MusicPlayerUIBinder:bindDjTab()
	local refs = self._refs
	local config = self._config or {}
	local djConfig = config.DJ or {}
	local soundBoardItems = djConfig.SOUND_BOARD_ITEMS or {}
	local speedPresets = djConfig.PLAYBACK_SPEED_PRESETS or {}
	local effects = djConfig.EFFECTS or {}
	local djTab = refs.djTab
	if not djTab then
		return
	end

	disconnectConnectionList(self._djSoundBoardConnections)
	disconnectConnectionList(self._djEffectConnections)
	self._djSpeedPresetButtons = {}
	self._djPlaybackSpeedSliderSetter = nil
	self._djPlaybackSpeedSliderRoot = nil
	self._djPlaybackSpeedHeaderValueLabel = nil
	self._djEffectSliderSetters = {}
	self._djEffectSliderRoots = {}
	self._djEffectToggleButtons = {}
	self._djModeToggle = nil
	self:_syncMainDragForActiveTab()

	local sliderDragDepth = 0
	local function setSliderDragActive(active: boolean)
		if active then
			sliderDragDepth += 1
		else
			sliderDragDepth = math.max(0, sliderDragDepth - 1)
		end
		if refs.mainDragDetector and self:_shouldMainDragBeEnabled() then
			refs.mainDragDetector.Enabled = sliderDragDepth <= 0
		elseif refs.mainDragDetector then
			refs.mainDragDetector.Enabled = false
		end
	end

	local playlistSection = findFirstByNames(djTab, { "1-PlaylistSection" })
	local djModeWrapper = findFirstByNames(playlistSection, { "DJModeWrapper" })
	local djModeContentWrapper = findFirstByNames(djModeWrapper, { "Wrapper" })
	local djModeToggle = findFirstByNames(djModeContentWrapper, { "ToggleEnableDJMode" })
		or findFirstByNames(djModeWrapper, { "ToggleEnableDJMode" })
	if djModeToggle and djModeToggle:IsA("GuiObject") then
		self._djModeToggle = djModeToggle :: GuiObject
		setSwitchToggleVisual(djModeToggle, self._store:get().isDjMode == true)
		task.defer(setSwitchToggleVisual, djModeToggle, self._store:get().isDjMode == true)
		bindSwitchToggleClick(self._djEffectConnections, djModeToggle, refs.mainDragDetector, function()
			setSwitchToggleVisual(djModeToggle, not (self._store:get().isDjMode == true))
			if self._onToggleDjMode then
				self._onToggleDjMode()
			end
		end, function()
			return self:_shouldMainDragBeEnabled()
		end)
	end

	local soundBoardWrapper = findFirstByNames(playlistSection, { "SoundBoardWrapper" })
	local soundBoardScroll = findFirstByNames(soundBoardWrapper, { "ScrollingFrame" })
	local soundBoardTemplate = findFirstByNames(soundBoardScroll, { "SoundBoardItemTemplate" })
	if soundBoardScroll and soundBoardTemplate and soundBoardTemplate:IsA("TextButton") then
		local template = soundBoardTemplate :: TextButton
		template.Visible = false
		_clearListClones(soundBoardScroll :: ScrollingFrame, "SoundBoardItemTemplate")

		for index, item in ipairs(soundBoardItems) do
			local clone = template:Clone()
			clone.Name = tostring(item.id or index)
			clone.LayoutOrder = index
			clone.Visible = true
			clone.Parent = soundBoardScroll
			setButtonDisplayText(clone, tostring(item.label or item.id or clone.Name))

			bindTrackedClickable(self._djSoundBoardConnections, clone, function()
				if self._onDjSoundboardTriggered then
					self._onDjSoundboardTriggered(tostring(item.id or clone.Name))
				end
			end)
		end
	end

	local soundEffectWrapper = findFirstByNames(djTab, { "SoundEffectWrapper" })
	local soundEffectScroll = findFirstByNames(soundEffectWrapper, { "ScrollableFrame" })
	local resetButton = findFirstByNames(soundEffectScroll, { "SoundEffectResetButton" })
	if resetButton then
		bindTrackedClickable(self._djEffectConnections, resetButton, function()
			if self._onDjResetRequested then
				self._onDjResetRequested()
			end
		end)
	end

	local playbackSpeedSection = findFirstByNames(soundEffectScroll, { "PlaybackSpeed" })
	local playbackSpeedWrapper = findFirstByNames(playbackSpeedSection, { "Wrapper" })
	local speedTop = findFirstByNames(playbackSpeedWrapper, { "Top" })
	local speedHeader = findFirstByNames(speedTop, { "Header" })
	if speedHeader then
		for _, child in ipairs(speedHeader:GetChildren()) do
			if child:IsA("TextLabel") and child.Text ~= "Playback Speed" then
				self._djPlaybackSpeedHeaderValueLabel = child :: TextLabel
				break
			end
		end
	end
	local speedTemplateWrapper = findFirstByNames(playbackSpeedWrapper, { "SpeedTemplateWrapper" })
	local speedSliderRoot = findFirstByNames(playbackSpeedWrapper, { "SliderWrapper" })
	if speedSliderRoot and speedSliderRoot:IsA("GuiObject") then
		self._djPlaybackSpeedSliderRoot = speedSliderRoot :: GuiObject
		self._djPlaybackSpeedSliderSetter = bindDjSlider(
			self._djEffectConnections,
			speedSliderRoot,
			0.25,
			2.0,
			0.05,
			self._djPlaybackSpeed,
			formatDjSpeedText,
			function(nextSpeed): boolean
				if self._onDjPlaybackSpeedChanged then
					return self._onDjPlaybackSpeedChanged(nextSpeed) == true
				end
				return true
			end,
			setSliderDragActive
		)
	end

	if speedTemplateWrapper then
		local presetNames = { "025", "050", "100", "150", "200" }
		for index, preset in ipairs(speedPresets) do
			local childName = presetNames[index] or tostring(index)
			local presetButton = findFirstByNames(speedTemplateWrapper, { childName })
			if presetButton then
				local speedValue = tonumber(preset.value) or self._djPlaybackSpeed
				self._djSpeedPresetButtons[speedValue] = presetButton :: GuiObject
				setButtonDisplayText(presetButton, tostring(preset.label or formatDjSpeedText(speedValue)))
				bindTrackedClickable(self._djEffectConnections, presetButton, function()
					if self._onDjPlaybackSpeedChanged then
						self._onDjPlaybackSpeedChanged(speedValue)
					end
				end)
			end
		end
	end

	local templateEffect = findFirstByNames(soundEffectScroll, { "TemplateEffect" })
	if soundEffectScroll and templateEffect and templateEffect:IsA("GuiObject") then
		local template = templateEffect :: GuiObject
		template.Visible = false
		for _, child in ipairs(soundEffectScroll:GetChildren()) do
			if child:IsA("GuiObject") and child:GetAttribute("DjEffectClone") == true then
				child:Destroy()
			end
		end

		for index, effect in ipairs(effects) do
			local effectId = tostring(effect.id or index)
			local effectClone = template:Clone()
			effectClone.Name = effectId
			effectClone.LayoutOrder = 100 + index
			effectClone:SetAttribute("DjEffectClone", true)
			effectClone.Visible = true
			effectClone.Parent = soundEffectScroll

			local sectionHeader = findFirstByNames(effectClone, { "SectionHeader" })
			local sectionName = findFirstByNames(sectionHeader, { "SectionName" })
			local toggle = findFirstByNames(sectionHeader, { "Toggle" })
			local effectEnabled = if self._djEffectEnabledById[effectId] ~= nil
				then self._djEffectEnabledById[effectId]
				else effect.defaultEnabled == true
			self._djEffectEnabledById[effectId] = effectEnabled

			if sectionName then
				setButtonDisplayText(sectionName, tostring(effect.sectionName or effect.label or effect.id or "Effect"))
			end

			if toggle then
				self._djEffectToggleButtons[effectId] = toggle :: GuiObject
				setSwitchToggleVisual(toggle, effectEnabled)
				task.defer(setSwitchToggleVisual, toggle, effectEnabled)
				bindSwitchToggleClick(self._djEffectConnections, toggle, refs.mainDragDetector, function()
					local nextEnabled = not (self._djEffectEnabledById[effectId] == true)
					local accepted = true
					if self._onDjEffectEnabledChanged then
						accepted = self._onDjEffectEnabledChanged(effectId, nextEnabled) == true
					end
					setSwitchToggleVisual(
						toggle,
						if accepted then nextEnabled else (self._djEffectEnabledById[effectId] == true)
					)
				end, function()
					return self:_shouldMainDragBeEnabled()
				end)
			end

			local wrapper = findFirstByNames(effectClone, { "Wrapper" })
			local effectItemTemplate = findFirstByNames(wrapper, { "EffectItemTemplate" })
			if effectItemTemplate and effectItemTemplate:IsA("GuiObject") then
				local itemTemplate = effectItemTemplate :: GuiObject
				itemTemplate.Visible = false
				local effectValues = self._djEffectValues[effectId]
				if not effectValues then
					effectValues = {}
					self._djEffectValues[effectId] = effectValues
				end
				local items = if type(effect.items) == "table" then effect.items else {}
				local itemCount = 0
				for itemIndex, item in ipairs(items) do
					local itemId = tostring(item.id or item.property or itemIndex)
					local itemClone = itemTemplate:Clone()
					itemClone.Name = itemId
					itemClone.LayoutOrder = itemIndex
					itemClone.Visible = true
					itemClone.Parent = wrapper
					itemCount += 1

					local itemLabel = findFirstByNames(itemClone, { "Item", "Label", "Name" })
					if itemLabel then
						setButtonDisplayText(itemLabel, tostring(item.label or item.id or item.property or "Value"))
					end

					local initialValue = if effectValues[itemId] ~= nil
						then effectValues[itemId]
						else tonumber(item.defaultValue) or 0
					effectValues[itemId] = initialValue

					local sliderRoot = findFirstByNames(itemClone, { "Slider" })
					if sliderRoot and sliderRoot:IsA("GuiObject") then
						local sliderKey = djEffectSliderKey(effectId, itemId)
						self._djEffectSliderRoots[sliderKey] = sliderRoot :: GuiObject
						self._djEffectSliderSetters[sliderKey] = bindDjSlider(
							self._djEffectConnections,
							itemClone,
							tonumber(item.min) or 0,
							tonumber(item.max) or 1,
							tonumber(item.step) or 0.05,
							initialValue,
							function(nextValue)
								return formatDjEffectValueText(nextValue, item.suffix)
							end,
							function(nextValue): boolean
								if self._onDjEffectValueChanged then
									return self._onDjEffectValueChanged(effectId, itemId, nextValue) == true
								end
								return true
							end,
							setSliderDragActive
						)
					end
				end

				if itemCount == 0 then
					itemTemplate.Visible = true
				end
			end
		end
	end

	self:setDjPlaybackSpeed(self._djPlaybackSpeed)
	for _, effect in ipairs(effects) do
		local effectId = tostring(effect.id or "")
		if effectId ~= "" then
			self:setDjEffectEnabled(effectId, self._djEffectEnabledById[effectId] == true)
			if type(effect.items) == "table" then
				for _, item in ipairs(effect.items) do
					local itemId = tostring(item.id or item.property or "")
					local value = self._djEffectValues[effectId] and self._djEffectValues[effectId][itemId]
					if itemId ~= "" and type(value) == "number" then
						self:setDjEffectValue(effectId, itemId, value)
					end
				end
			end
		end
	end
end

local function rememberRequesterThumbnail(self: any, requesterUserId: number, thumbnail: string)
	if self._userThumbnailCache[requesterUserId] == nil then
		table.insert(self._userThumbnailCacheOrder, requesterUserId)
	end
	self._userThumbnailCache[requesterUserId] = thumbnail

	local maxEntries = math.max(1, math.floor(tonumber(self._config and self._config.THUMBNAIL_CACHE_MAX) or 100))
	while #self._userThumbnailCacheOrder > maxEntries do
		local evictedUserId = table.remove(self._userThumbnailCacheOrder, 1)
		if evictedUserId then
			self._userThumbnailCache[evictedUserId] = nil
		end
	end
end

function MusicPlayerUIBinder:_setRequesterThumbnail(imageLabel: ImageLabel, requesterUserId: number?)
	imageLabel:SetAttribute("RequesterUserId", requesterUserId)
	imageLabel.Image = ""

	if type(requesterUserId) ~= "number" or requesterUserId <= 0 then
		return
	end

	local cached = self._userThumbnailCache[requesterUserId]
	if type(cached) == "string" and cached ~= "" then
		imageLabel.Image = cached
		return
	end

	task.spawn(function()
		local ok, thumbnail = pcall(
			Players.GetUserThumbnailAsync,
			Players,
			requesterUserId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size100x100
		)

		if not ok or type(thumbnail) ~= "string" or thumbnail == "" then
			return
		end

		rememberRequesterThumbnail(self, requesterUserId, thumbnail)
		if imageLabel.Parent and imageLabel:GetAttribute("RequesterUserId") == requesterUserId then
			imageLabel.Image = thumbnail
		end
	end)
end

function MusicPlayerUIBinder:_updateQueueHeaderVisibility()
	local refs = self._refs
	local header = refs.queueHeaderLabel
	local scroll = refs.scrollableQueue
	if not header or not scroll then
		return
	end

	local headerTop = header.AbsolutePosition.Y
	local headerBottom = headerTop + header.AbsoluteSize.Y
	local shouldShow = true

	for _, child in ipairs(scroll:GetChildren()) do
		if
			child:IsA("GuiObject")
			and child.Visible
			and child ~= refs.queueTemplate
			and child.Name ~= "QueueListTemplate"
			and child.Name ~= "UIListLayout"
			and child.Name ~= "UIPadding"
		then
			local top = child.AbsolutePosition.Y
			local bottom = top + child.AbsoluteSize.Y
			if bottom > headerTop and top < headerBottom then
				shouldShow = false
				break
			end
		end
	end

	if header.Visible ~= shouldShow then
		header.Visible = shouldShow
	end
end

-- ============================================================
-- QUEUE RENDER
-- ============================================================

function MusicPlayerUIBinder:_requestImageCoverDarkestColor(playlist: any)
	if type(playlist) ~= "table" or (playlist.coverType or "gradient") ~= "image" then
		return
	end

	local coverKey = getImageCoverKey(playlist.coverValue)
	if not coverKey then
		return
	end
	if self._imageCoverDarkestColors[coverKey] or self._imageCoverDarkestColorRequests[coverKey] then
		return
	end

	self._imageCoverDarkestColorRequests[coverKey] = true
	task.spawn(function()
		local sampleOk, darkestColor = pcall(function()
			return sampleImageCoverDarkestColor(playlist.coverValue)
		end)
		self._imageCoverDarkestColorRequests[coverKey] = nil
		if self._isDestroyed or not sampleOk or not darkestColor then
			return
		end

		self._imageCoverDarkestColors[coverKey] = darkestColor

		local state = self._store:get()
		self:renderQueue(state.queue or {})

		local currentTrack = state.currentTrack
		if type(currentTrack) ~= "table" then
			return
		end

		local playlistsById = state.playlists or {}
		local parentPlaylist = currentTrack.playlist or playlistsById[currentTrack.playlistId]
		if type(parentPlaylist) == "table" and getImageCoverKey(parentPlaylist.coverValue) == coverKey then
			self:_updateAuraOverlay(parentPlaylist)
		end
	end)
end

function MusicPlayerUIBinder:_getQueueNumberColor(parentPlaylist: any?): Color3?
	if type(parentPlaylist) ~= "table" then
		return nil
	end

	if (parentPlaylist.coverType or "gradient") == "image" then
		self:_requestImageCoverDarkestColor(parentPlaylist)
	end

	return getPlaylistCoverAccentColor(parentPlaylist, self._config, self._imageCoverDarkestColors)
end

function MusicPlayerUIBinder:renderQueue(queue: { any })
	local refs = self._refs
	local scroll = refs.scrollableQueue
	local template = refs.queueTemplate
	local playlistsById = self._store:get().playlists or {}

	template.Visible = false

	for i, track in ipairs(queue) do
		local row = ensurePooledRow(self._queueRowPool, i, template, scroll)
		disconnectPooledRowConnections(row)
		local clone = row.instance

		-- QueueListTemplate structure (from live dump):
		-- RelatedPlaylistCover -> QueueNumberWrapper -> QueueNumber [TextLabel]
		-- RelatedPlaylistCover -> RelatedCoverTitle [TextLabel]
		-- TrackInformationSection -> TrackInfo -> TrackTitle [TextLabel]
		-- TrackInformationSection -> TrackInfo -> TrackCreator [TextLabel]
		local parentPlaylist = track.playlist or playlistsById[track.playlistId]
		local cover = clone:FindFirstChild("RelatedPlaylistCover")
		if cover then
			-- QueueNumber lives inside QueueNumberWrapper
			local queueWrapper = cover:FindFirstChild("QueueNumberWrapper")
			local queueNum = if queueWrapper then queueWrapper:FindFirstChild("QueueNumber") else nil
			if queueNum and queueNum:IsA("TextLabel") then
				(queueNum :: TextLabel).Text = string.format("%02d", i)
			end
			-- Color QueueNumber text from the playlist cover accent.
			if queueNum and queueNum:IsA("TextLabel") then
				local numberLabel = queueNum :: TextLabel
				if typeof(numberLabel:GetAttribute("QueueNumberBaseTextColor3")) ~= "Color3" then
					numberLabel:SetAttribute("QueueNumberBaseTextColor3", numberLabel.TextColor3)
				end
				local queueNumberColor = self:_getQueueNumberColor(parentPlaylist)
				numberLabel.TextColor3 = queueNumberColor
					or (numberLabel:GetAttribute("QueueNumberBaseTextColor3") :: Color3)
					or Color3.new(1, 1, 1)
			end

			local coverTitle = cover:FindFirstChild("RelatedCoverTitle")
			if coverTitle and coverTitle:IsA("TextLabel") then
				(coverTitle :: TextLabel).Text = if parentPlaylist then tostring(parentPlaylist.name or "") else ""
			end

			-- Apply cover style if track has playlist info
			if parentPlaylist then
				local coverSource = resolveCoverSourceForTrack(track, parentPlaylist)
				self:applyCoverStyle(cover, coverSource)
			end
		end

		local infoSection = clone:FindFirstChild("TrackInformationSection")
		if infoSection then
			local trackInfo = infoSection:FindFirstChild("TrackInfo")
			if trackInfo then
				local titleLabel = trackInfo:FindFirstChild("TrackTitle")
				if titleLabel and titleLabel:IsA("TextLabel") then
					local label = titleLabel :: TextLabel
					label.Text = track.name or ""
					scheduleTrackTitleHeight(label)
				end
				-- Actual field name is TrackCreator (not CreatorName)
				local creatorLabel = trackInfo:FindFirstChild("TrackCreator") or trackInfo:FindFirstChild("CreatorName")
				if creatorLabel and creatorLabel:IsA("TextLabel") then
					(creatorLabel :: TextLabel).Text = track.creator or ""
				end

				local trackLengthLabel = trackInfo:FindFirstChild("Track Length")
					or trackInfo:FindFirstChild("TrackLength")
				if trackLengthLabel and trackLengthLabel:IsA("TextLabel") then
					(trackLengthLabel :: TextLabel).Text = formatClock(tonumber(track.totalDuration) or 0)
				end
			end

			local requesterWrapper = infoSection:FindFirstChild("RequesterWrapper")
			if requesterWrapper then
				local requesterLabel = requesterWrapper:FindFirstChild("RequesterDisplayName")
				if requesterLabel and requesterLabel:IsA("TextLabel") then
					local requesterName = if track.isSystemAssigned == true
						then "Auto Playlist"
						else tostring(track.requesterDisplayName or "Unknown")
					local requesterTextLabel = requesterLabel :: TextLabel
					requesterTextLabel.Text = string.format("Requester : %s", requesterName)
				end
			end

			local requesterProfile = infoSection:FindFirstChild("RequesterProfilePicture")
			if requesterProfile and requesterProfile:IsA("ImageLabel") then
				if track.isSystemAssigned == true then
					requesterProfile.Visible = false
				else
					requesterProfile.Visible = true
					self:_setRequesterThumbnail(requesterProfile :: ImageLabel, tonumber(track.requesterUserId))
				end
			end
		end

		clone.Name = tostring(track.id or i)
		clone.LayoutOrder = i
		clone.Visible = true
	end

	hideUnusedPooledRows(self._queueRowPool, #queue + 1)
	self:_updateQueueHeaderVisibility()
end

-- ============================================================
-- PLAYLIST ICON BOUNCE (idle loop, memory-safe)
-- ============================================================

function MusicPlayerUIBinder:_refreshPlaylistIconBounce(...)
	-- Cancel any existing bounces first
	local existing = self._playlistIconBounceCleanup
	if existing then
		for _, entry in ipairs(existing) do
			entry.kill()
			for _, t in ipairs(entry.tweens) do
				t:Cancel()
			end
			for _, c in ipairs(entry.conns) do
				c:Disconnect()
			end
		end
	end
	self._playlistIconBounceCleanup = {}

	local buttons = { ... }
	for delayIdx, btn in ipairs(buttons) do
		if not (btn and btn:IsA("GuiObject")) then
			continue
		end
		local cover = btn:FindFirstChild("PlaylistCover", true)
		local icon = if cover then cover:FindFirstChild("PlaylistIcon") else nil
		if not (icon and icon:IsA("GuiObject")) then
			continue
		end

		local iconObj = icon :: GuiObject
		local uiScale = ensureUIScale(iconObj)

		local PAUSE_BETWEEN = 4.0 -- idle pause between each attention cycle
		local DELAY_OFFSET = (delayIdx - 1) * 1.2 -- stagger between icons

		local alive = true
		local conns: { RBXScriptConnection } = {}
		local tweens: { Tween } = {}

		-- Attention-seeker sequence run as a task (coroutine-based)
		local function runCycle()
			if not alive then
				return
			end

			-- 1. Rise + tilt right
			uiScale.Scale = 1
			iconObj.Rotation = 0
			local tRise = TweenService:Create(
				uiScale,
				TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ Scale = 1.18 }
			)
			local tTilt = TweenService:Create(
				iconObj,
				TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ Rotation = 10 }
			)
			table.insert(tweens, tRise)
			table.insert(tweens, tTilt)
			tRise:Play()
			tTilt:Play()
			task.wait(0.20)

			-- 2. Shake: quick left-right-left-right rotation
			local shakeAngles = { -12, 10, -8, 6, -4, 0 }
			for _, angle in ipairs(shakeAngles) do
				if not alive then
					break
				end
				local tShake =
					TweenService:Create(iconObj, TweenInfo.new(0.07, Enum.EasingStyle.Linear), { Rotation = angle })
				table.insert(tweens, tShake)
				tShake:Play()
				task.wait(0.075)
			end

			-- 3. Settle: scale back to 1, rotation to 0
			if not alive then
				return
			end
			local tDown = TweenService:Create(
				uiScale,
				TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Scale = 1.0 }
			)
			local tStraighten = TweenService:Create(
				iconObj,
				TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Rotation = 0 }
			)
			table.insert(tweens, tDown)
			table.insert(tweens, tStraighten)
			tDown:Play()
			tStraighten:Play()
			task.wait(0.25)
		end

		-- Loop thread
		local thread = task.spawn(function()
			task.wait(DELAY_OFFSET)
			while alive do
				runCycle()
				task.wait(PAUSE_BETWEEN)
			end
		end)

		table.insert(self._playlistIconBounceCleanup, {
			tweens = tweens,
			conns = conns,
			kill = function()
				alive = false
				task.cancel(thread)
				iconObj.Rotation = 0
				uiScale.Scale = 1
			end,
		})
	end
end

-- ============================================================
-- PLAYLIST LIST RENDER (Request Tab)
-- ============================================================

function MusicPlayerUIBinder:renderPlaylists(playlists: { any }, searchQuery: string)
	local refs = self._refs
	local scroll = refs.scrollablePlaylist
	local normalTemplate = refs.playlistTemplateNormal
	local selectedTemplate = refs.playlistTemplateSelected
	local state = self._store:get()
	local selectedPlaylistId = state.selectedPlaylistId
	local favoritesPlaylistId, newDropsPlaylistId = getSpecialPlaylistIds(self._config)

	if not self._specialPlaylistDefaults then
		self._specialPlaylistDefaults = {
			favorites = capturePlaylistRowState(refs.favoritesPlaylistButton),
			newDrops = capturePlaylistRowState(refs.newDropsPlaylistButton),
		}
	end
	local specialDefaults = self._specialPlaylistDefaults

	normalTemplate.Visible = false
	selectedTemplate.Visible = false
	normalTemplate.LayoutOrder = 10000
	selectedTemplate.LayoutOrder = 10001

	refs.favoritesPlaylistButton.Visible = true
	refs.newDropsPlaylistButton.Visible = true
	refs.favoritesPlaylistButton.LayoutOrder = 1
	refs.newDropsPlaylistButton.LayoutOrder = 2

	if selectedPlaylistId == favoritesPlaylistId then
		applyPlaylistRowState(refs.favoritesPlaylistButton, selectedTemplate)
	else
		restorePlaylistRowState(refs.favoritesPlaylistButton, specialDefaults.favorites)
	end

	if selectedPlaylistId == newDropsPlaylistId then
		applyPlaylistRowState(refs.newDropsPlaylistButton, selectedTemplate)
	else
		restorePlaylistRowState(refs.newDropsPlaylistButton, specialDefaults.newDrops)
	end

	-- Dynamic NewDrops month label
	do
		local ndCover = refs.newDropsPlaylistButton:FindFirstChild("PlaylistCover", true)
		local ndNameLabel = if ndCover then ndCover:FindFirstChild("PlaylistName") else nil
		if ndNameLabel and ndNameLabel:IsA("TextLabel") then
			(ndNameLabel :: TextLabel).Text = getMonthDropsLabel()
		end
	end

	-- Idle bounce animation on special playlist icons (smart cleanup to prevent leaks)
	self:_refreshPlaylistIconBounce(refs.favoritesPlaylistButton, refs.newDropsPlaylistButton)

	local orderedPlaylists = buildOrderedPlaylistEntries(playlists, searchQuery)
	hideUnusedPooledRows(self._requestPlaylistRowPool, 1)

	startListRenderJob(self, "requestPlaylists", #orderedPlaylists, function(index: number)
		local entry = orderedPlaylists[index]
		local id = entry.id
		local playlist = entry.playlist
		local row = ensurePooledRow(self._requestPlaylistRowPool, index, normalTemplate, scroll)
		disconnectPooledRowConnections(row)
		local clone = row.instance

		local info = clone:FindFirstChild("PlaylistInformation")
		if info then
			local nameLabel = info:FindFirstChild("PlaylistName")
			if nameLabel and nameLabel:IsA("TextLabel") then
				(nameLabel :: TextLabel).Text = playlist.name or ""
			end

			local totalTrackLabel = info:FindFirstChild("TotalTrack")
			if totalTrackLabel and totalTrackLabel:IsA("TextLabel") then
				local trackCount = type(playlist.trackIds) == "table" and #playlist.trackIds or 0
				local suffix = if trackCount == 1 then "Track" else "Tracks"
				(totalTrackLabel :: TextLabel).Text = string.format("%d %s", trackCount, suffix)
			end
		end

		local coverElement = clone:FindFirstChild("PlaylistCover") or clone:FindFirstChild("ImageLabel")
		if coverElement then
			self:applyCoverStyle(coverElement, playlist)
		end

		if clone:IsA("GuiObject") then
			applyPlaylistRowState(clone, if selectedPlaylistId == id then selectedTemplate else normalTemplate)
		end

		clone.Name = id
		clone.LayoutOrder = REQUEST_PLAYLIST_USER_LAYOUT_BASE + index
		clone.Visible = true
		animateListRowIn(clone)

		if clone:IsA("TextButton") then
			bindTrackedClickable(row.connections, clone, function()
				if self._onPlaylistSelected then
					self._onPlaylistSelected(id)
				end
			end)
		end
	end)
end

-- ============================================================
-- Track list render (Request tab, 2 kolom)
-- ============================================================

function MusicPlayerUIBinder:renderTracks(tracks: { any }, searchQuery: string)
	local refs = self._refs
	local state = self._store:get()
	local playlistsById = state.playlists or {}
	local _, newDropsPlaylistId = getSpecialPlaylistIds(self._config)
	refs.trackTemplateLeft.Visible = false
	refs.trackTemplateRight.Visible = false

	local filtered = buildOrderedTrackEntries(tracks, searchQuery, state.selectedPlaylistId, newDropsPlaylistId)
	local leftTracks = {} :: { any }
	local rightTracks = {} :: { any }
	for index, track in ipairs(filtered) do
		if index % 2 == 1 then
			table.insert(leftTracks, track)
		else
			table.insert(rightTracks, track)
		end
	end

	local function renderRequestTrackRow(row: PooledRow, track: any, index: number)
		local parentPlaylist = playlistsById[track.playlistId] or track.playlist
		local coverSource = resolveCoverSourceForTrack(track, parentPlaylist)

		local clone = row.instance
		local feedbackLocked = false
		local function requestTrack()
			if feedbackLocked then
				return
			end
			if self._isAddToQueueModalOpen then
				return
			end
			if track.id then
				self:openAddToQueueConfirmation(track, parentPlaylist)
			end
		end

		if clone:IsA("TextButton") then
			(clone :: TextButton).AutoButtonColor = false
			(clone :: TextButton).Active = true
			(clone :: TextButton).Interactable = true
		end

		-- TrackWrapperTemplate structure (dari GUI dump):
		-- TrackInformationWrapper -> TrackInformation -> TrackDetails -> TrackTitle [TextLabel]
		-- TrackInformation -> AddToQueueWrapper -> AddToQueueButton [TextButton]
		local infoWrap = clone:FindFirstChild("TrackInformationWrapper")
		if infoWrap then
			local info = infoWrap:FindFirstChild("TrackInformation")
			if info then
				local details = info:FindFirstChild("TrackDetails")
				if details then
					local titleLabel = details:FindFirstChild("TrackTitle")
					if titleLabel and titleLabel:IsA("TextLabel") then
						local label = titleLabel :: TextLabel
						label.Text = track.name or ""
						scheduleTrackTitleHeight(label)
					end

					local creatorLabel = details:FindFirstChild("TrackCreator")
					if creatorLabel and creatorLabel:IsA("TextLabel") then
						(creatorLabel :: TextLabel).Text = track.creator or ""
					end
				end
				local addWrap = info:FindFirstChild("AddToQueueWrapper")
				if addWrap then
					local trackLengthLabel = addWrap:FindFirstChild("TrackLength")
					if trackLengthLabel and trackLengthLabel:IsA("TextLabel") then
						local totalSeconds = math.max(0, math.floor(tonumber(track.totalDuration) or 0))
						local minutes = math.floor(totalSeconds / 60)
						local seconds = totalSeconds % 60
						(trackLengthLabel :: TextLabel).Text = string.format("%02d:%02d", minutes, seconds)
					end

					local addBtn = addWrap:FindFirstChild("AddToQueueButton")
					local addIcon = if addBtn then addBtn:FindFirstChild("AddToQueueIconBefore") else nil
					resetRequestTrackFeedback(addBtn, addIcon)

					if addBtn and addBtn:IsA("GuiButton") then
						local addQueueButton = addBtn :: GuiButton
						addQueueButton.Active = true
						addQueueButton.Interactable = true
					end

					if addIcon and addIcon:IsA("GuiButton") then
						local addQueueIcon = addIcon :: GuiButton
						addQueueIcon.Active = true
						addQueueIcon.Interactable = true
					end

					if addWrap:IsA("GuiObject") then
						local addWrapGui = addWrap :: GuiObject
						addWrapGui.Active = true
						table.insert(
							row.connections,
							addWrapGui.InputBegan:Connect(function(input)
								if
									input.UserInputType == Enum.UserInputType.MouseButton1
									or input.UserInputType == Enum.UserInputType.Touch
								then
									requestTrack()
								end
							end)
						)
					end

					if addBtn then
						bindTrackedClickable(row.connections, addBtn, requestTrack)
						if addIcon then
							bindTrackedClickable(row.connections, addIcon, requestTrack)
						end
					end
				end
			end
		end

		-- Apply cover style to track's playlist cover if available
		if coverSource then
			local coverElement = clone:FindFirstChild("PlaylistCover")
				or clone:FindFirstChild("TrackCover")
				or clone:FindFirstChild("RelatedPlaylistCover")
			if coverElement then
				self:applyCoverStyle(coverElement, coverSource)
			end
		end

		if clone:IsA("GuiButton") then
			bindTrackedClickable(row.connections, clone, requestTrack)
		end

		clone.Name = track.id or tostring(index)
		clone.LayoutOrder = VIRTUAL_ROW_LAYOUT_BASE + index
		clone.Visible = true
	end

	renderVirtualList(self, {
		key = "requestTracksLeft",
		scroll = refs.scrollableTrackLeft,
		pool = self._requestTrackLeftRowPool,
		template = refs.trackTemplateLeft,
		items = leftTracks,
		renderRow = renderRequestTrackRow,
	})
	renderVirtualList(self, {
		key = "requestTracksRight",
		scroll = refs.scrollableTrackRight,
		pool = self._requestTrackRightRowPool,
		template = refs.trackTemplateRight,
		items = rightTracks,
		renderRow = renderRequestTrackRow,
	})
end

function MusicPlayerUIBinder:setManageSubView(subView: string, options: { preserveEditing: boolean? }?)
	local refs = self._refs
	local blur = refs.utilitiesBackdropBlur
	local playlistModal = refs.formPlaylist
	local trackModal = refs.formTrack
	local preserveEditing = options ~= nil and options.preserveEditing == true

	local function resetModal(modal: GuiObject?)
		if not modal then
			return
		end

		modal.Visible = false
		local modalScale = modal:FindFirstChildWhichIsA("UIScale")
		if modalScale then
			modalScale.Scale = 1
		end
	end

	local function openModal(modal: GuiObject?)
		if not modal then
			return
		end

		modal.Visible = true
		local modalScale = modal:FindFirstChildWhichIsA("UIScale")
		if modalScale then
			modalScale.Scale = 1
		end
		if self._anim then
			self._anim:presentDialog(modal)
		end
	end

	local function hideMainWrapperForManageForm()
		if refs.mainWrapper and refs.mainWrapper.Visible then
			self._manageFormHiddenMainWrapper = true
			refs.mainWrapper.Visible = false
		end
	end

	local function restoreMainWrapperAfterManageForm()
		if self._manageFormHiddenMainWrapper and refs.mainWrapper then
			refs.mainWrapper.Visible = true
		end
		self._manageFormHiddenMainWrapper = false
	end

	local normalizedSubView = if subView == "create_playlist_focus"
		then "edit_playlist"
		elseif subView == "create_track_focus" then "edit_track"
		else subView

	if normalizedSubView == "edit_playlist" then
		-- Close all other modal layers before opening
		self:closeVoteModal(true)
		self:closeAddToQueueConfirmation(true)
		self:closePlaylistRelatedModal(true)
		self:closeTrackRelatedModal(true)
		resetModal(trackModal)
		blur.Visible = true
		blur.Active = true
		blur.ZIndex = math.max(playlistModal.ZIndex - 1, 0)
		blur.BackgroundTransparency = getModalBackdropTransparency()
		hideMainWrapperForManageForm()
		openModal(playlistModal)
		self._activeManageModal = playlistModal
	elseif normalizedSubView == "edit_track" then
		-- Close all other modal layers before opening
		self:closeVoteModal(true)
		self:closeAddToQueueConfirmation(true)
		self:closePlaylistRelatedModal(true)
		self:closeTrackRelatedModal(true)
		resetModal(playlistModal)
		blur.Visible = true
		blur.Active = true
		blur.ZIndex = math.max(trackModal.ZIndex - 1, 0)
		blur.BackgroundTransparency = getModalBackdropTransparency()
		hideMainWrapperForManageForm()
		openModal(trackModal)
		self._activeManageModal = trackModal
	else
		resetModal(playlistModal)
		resetModal(trackModal)
		restoreMainWrapperAfterManageForm()
		blur.Active = false
		blur.Visible = false
		blur.BackgroundTransparency = 1
		self._activeManageModal = nil
	end

	local storePatch: { [string]: any } = { manageSubView = subView }
	if normalizedSubView ~= "edit_track" and normalizedSubView ~= "edit_playlist" then
		if not preserveEditing then
			storePatch.editingTrack = nil
			storePatch.editingPlaylist = nil
			self._trackFormCreateMode = true
			self._playlistFormCreateMode = true
		end
	end
	self._store:set(storePatch)
end

function MusicPlayerUIBinder:_closeManageFormForConfirmation()
	local refs = self._refs
	if self._activeManageModal then
		self._activeManageModal.Visible = false
		self._activeManageModal = nil
	end
	if refs.formPlaylist then
		refs.formPlaylist.Visible = false
	end
	if refs.formTrack then
		refs.formTrack.Visible = false
	end
	if refs.utilitiesBackdropBlur then
		refs.utilitiesBackdropBlur.Active = false
		refs.utilitiesBackdropBlur.Visible = false
		refs.utilitiesBackdropBlur.BackgroundTransparency = 1
	end
end

-- Manage form copy

function MusicPlayerUIBinder:_syncManageFormCopy(kind: "playlist" | "track", isEditing: boolean)
	local form: GuiObject
	local titleNames: { string }
	local primaryButtonNames: { string }
	local copy: ManageFormCopy

	if kind == "playlist" then
		form = self._refs.formPlaylist
		titleNames = {
			"CreateorCustomPlaylistTitle",
			"CreateorEditPlaylistTitle",
			"PlaylistFormTitle",
			"PlaylistTitle",
		}
		primaryButtonNames = { "CreateorSavePlaylistButton" }
		copy = if isEditing then PLAYLIST_FORM_COPY.update else PLAYLIST_FORM_COPY.create
	else
		form = self._refs.formTrack
		titleNames = {
			"AddorEditTrackTitle",
			"UploadorCustomTrackTitle",
			"CreateorCustomTrackTitle",
			"UploadorEditTrackTitle",
			"TrackFormTitle",
			"TrackTitle",
		}
		primaryButtonNames = { "UploadorSaveTrackButton" }
		copy = if isEditing then TRACK_FORM_COPY.update else TRACK_FORM_COPY.create
	end

	local actionWrapper = getActionWrapper(form)
	local primaryButton = findFirstByNames(actionWrapper, primaryButtonNames)
	local cancelButton = if actionWrapper then actionWrapper:FindFirstChild("CancelButton", true) else nil
	local titleDisplay = getFormTitleDisplay(form, titleNames)
	local helperDisplay = nil :: Instance?
	if actionWrapper and primaryButton and not hasMultipleDirectChildrenNamed(actionWrapper, primaryButton.Name) then
		helperDisplay = getFormHelperDisplay(actionWrapper, primaryButton, cancelButton)
	end

	setTextDisplay(titleDisplay, copy.title)
	setTextDisplay(helperDisplay, copy.helper)
	if actionWrapper then
		for _, name in ipairs(primaryButtonNames) do
			forEachDirectChildByName(actionWrapper, name, function(child)
				setButtonDisplayText(child, copy.button)
			end)
		end
	else
		setButtonDisplayText(primaryButton, copy.button)
	end
end

-- Form validation

function MusicPlayerUIBinder:validatePlaylistForm(data: { [string]: any }): (boolean, string)
	if not data.name or data.name == "" then
		return false, "Playlist name is required"
	end
	if #data.name > 50 then
		return false, "Playlist name too long (max 50 characters)"
	end
	-- Validate cover selection
	if not data.coverType or (data.coverType ~= "gradient" and data.coverType ~= "image") then
		return false, "Please select a cover style"
	end
	if data.coverType == "gradient" and (not data.coverValue or data.coverValue < 1) then
		return false, "Please select a color gradient"
	end
	if data.coverType == "image" and (not data.coverValue or data.coverValue == "") then
		return false, "Please enter an image asset ID"
	end
	-- Font is optional, will use default if not set
	return true, ""
end

function MusicPlayerUIBinder:validateTrackForm(data: { [string]: any }): (boolean, string)
	if not data.name or data.name == "" then
		return false, "Track name is required"
	end
	if not data.creator or data.creator == "" then
		return false, "Creator name is required"
	end
	if not data.playlistId or data.playlistId == "" then
		return false, "Please select a playlist"
	end
	if not data.parts or #data.parts == 0 then
		return false, "At least one audio ID is required"
	end
	-- Validate audio IDs are numbers
	for i, part in ipairs(data.parts) do
		if tonumber(part) == nil then
			return false, "Audio ID " .. tostring(i) .. " must be a number"
		end
	end
	return true, ""
end

-- Form helpers

local function getPlaylistFormScrollable(formPlaylist: Instance?): Instance?
	return formPlaylist and formPlaylist:FindFirstChild("ScrollablePlayerList")
end

local function getCustomizeCoverParts(formPlaylist: Instance?): (
	Instance?,
	Instance?,
	Instance?,
	Instance?,
	Instance?,
	Instance?,
	Instance?,
	Instance?
)
	local scrollable = getPlaylistFormScrollable(formPlaylist)
	local customizeCover = scrollable and scrollable:FindFirstChild("2-CustomizeCover")
	local selectorStyle = customizeCover and customizeCover:FindFirstChild("SelectorStyle")
	local colorTabBtn = selectorStyle and selectorStyle:FindFirstChild("ColorTabButton")
	local imageTabBtn = selectorStyle and selectorStyle:FindFirstChild("ImageTabButton")
	local canvasGroup = customizeCover and customizeCover:FindFirstChild("CanvasGroup")
	local colorTemplateList = canvasGroup and canvasGroup:FindFirstChild("ColorTemplateList")
	local inputImageID = canvasGroup and canvasGroup:FindFirstChild("InputImageID")
	local selectFontFace = scrollable and scrollable:FindFirstChild("3-SelectFontFace")
	return customizeCover,
		colorTabBtn,
		imageTabBtn,
		canvasGroup,
		colorTemplateList,
		inputImageID,
		selectFontFace,
		selectorStyle
end

local function getPlaylistVisibilityParts(formPlaylist: Instance?): (Instance?, TextButton?, TextButton?)
	local scrollable = getPlaylistFormScrollable(formPlaylist)
	local visibilityField = scrollable and scrollable:FindFirstChild("4-PlaylistVisibility")
	local list = visibilityField and visibilityField:FindFirstChild("SelectFontFaceList")
	local scroll = list and list:FindFirstChild("ScrollableFontFace")
	local privateBtn = scroll and scroll:FindFirstChild("Normal")
	local publicBtn = scroll and scroll:FindFirstChild("Selected")
	return visibilityField,
		if privateBtn and privateBtn:IsA("TextButton") then privateBtn :: TextButton else nil,
		if publicBtn and publicBtn:IsA("TextButton") then publicBtn :: TextButton else nil
end

function MusicPlayerUIBinder:populateTrackForm(track: any?)
	local refs = self._refs
	local store = self._store
	local currentState = store:get()
	local isCreateMode = track == nil
	self._trackFormCreateMode = isCreateMode
	self:_syncManageFormCopy("track", not isCreateMode)
	if track then
		setTextInput(refs.formTrackNameField, track.name or "")
		setTextInput(refs.formTrackCreatorField, track.creator or "")
		for i, partFrame in ipairs(refs.formTrackIdParts) do
			setTextInput(partFrame, (track.parts and track.parts[i]) or "")
		end
		-- Per-track playback speed: kalau track punya nilai sendiri,
		-- tampilkan di TextBox; kalau nil, biarin kosong (= pakai global).
		if refs.formTrackPlaybackSpeedField then
			local speed = (track :: any).playbackSpeed
			if typeof(speed) == "number" and speed > 0 then
				setTextInput(refs.formTrackPlaybackSpeedField, tostring(speed))
			else
				setTextInput(refs.formTrackPlaybackSpeedField, "")
			end
		end
		store:set({
			selectedTrackPlaylistId = track.playlistId or nil,
		})
	else
		local preservedPlaylistId = currentState.selectedTrackPlaylistId
		if preservedPlaylistId and not (currentState.playlists or {})[preservedPlaylistId] then
			preservedPlaylistId = nil
		end
		-- Clear for create mode
		setTextInput(refs.formTrackNameField, "")
		setTextInput(refs.formTrackCreatorField, "")
		for _, partFrame in ipairs(refs.formTrackIdParts) do
			setTextInput(partFrame, "")
		end
		if refs.formTrackPlaybackSpeedField then
			setTextInput(refs.formTrackPlaybackSpeedField, "")
		end
		store:set({
			editingTrack = nil,
			selectedTrackPlaylistId = preservedPlaylistId,
		})
	end

	self:renderTrackPlaylistOptions(store:get().playlists or {})
end

function MusicPlayerUIBinder:populatePlaylistForm(playlist: any?)
	local refs = self._refs
	local store = self._store
	local isCreateMode = playlist == nil
	self._playlistFormCreateMode = isCreateMode
	self:_syncManageFormCopy("playlist", not isCreateMode)

	if playlist then
		setTextInput(refs.formPlaylistNameField, playlist.name or "")

		-- Set preview name for gradient cards
		store:set({ playlistNamePreview = playlist.name or "" })

		-- Populate cover selection
		if playlist.coverType == "image" then
			store:set({
				selectedCoverType = "image",
				selectedCoverValue = playlist.coverValue or "",
			})
			self:_setCoverTab("image")
			local _, _, _, _, _, inputImageID = getCustomizeCoverParts(refs.formPlaylist)
			if inputImageID and inputImageID:IsA("TextBox") then
				(inputImageID :: TextBox).Text = playlist.coverValue or ""
			end
		else
			-- Gradient mode
			local gradientIndex = playlist.coverValue or 1
			store:set({
				selectedCoverType = "gradient",
				selectedCoverValue = gradientIndex,
			})
			self:_setCoverTab("color")
			self:_selectGradient(gradientIndex)
		end

		-- Populate font selection
		if playlist.fontFace then
			local config = self._config
			if config and config.FONT_PRESETS then
				-- Find font index
				local fontIndex = 1
				for i, fontName in ipairs(config.FONT_PRESETS) do
					if fontName == playlist.fontFace then
						fontIndex = i
						break
					end
				end
				self:_selectFont(fontIndex, playlist.fontFace)
			end
		end

		local visibility = type(playlist.visibility) == "string" and playlist.visibility or "public"
		store:set({ selectedPlaylistVisibility = visibility })
		self:_selectPlaylistVisibility(visibility)
	else
		-- Clear for create mode
		setTextInput(refs.formPlaylistNameField, "")

		-- Reset preview name
		store:set({ playlistNamePreview = "" })

		-- Reset to defaults
		store:set({
			editingPlaylist = nil,
			selectedCoverType = "gradient",
			selectedCoverValue = 1,
			selectedFontFace = "Original",
			selectedPlaylistVisibility = "public",
		})

		self:_setCoverTab("color")
		local _, _, _, _, _, inputImageID = getCustomizeCoverParts(refs.formPlaylist)
		if inputImageID and inputImageID:IsA("TextBox") then
			(inputImageID :: TextBox).Text = ""
		end

		-- Select first gradient and font
		self:_selectGradient(1)
		self:_selectFont(1, "Original")
		self:_selectPlaylistVisibility("public")
	end
end

function MusicPlayerUIBinder:readTrackForm(): { [string]: any }
	local refs = self._refs
	local state = self._store:get()
	local parts: { string } = {}
	for _, partFrame in ipairs(refs.formTrackIdParts) do
		local v = getTextInput(partFrame)
		if v ~= "" then
			table.insert(parts, v)
		end
	end
	-- Per-track playback speed (optional). Tolerant ke input user:
	--   "2.3", "2.3x", " 0.85 " semua valid. Empty/invalid = nil
	--   (server fallback ke Config.Music.PLAYBACK_SPEED).
	local playbackSpeed: number? = nil
	if refs.formTrackPlaybackSpeedField then
		local raw = getTextInput(refs.formTrackPlaybackSpeedField)
		if raw ~= "" then
			local cleaned = (raw:gsub("[xX%s]", ""))
			local n = tonumber(cleaned)
			if n and n > 0 then
				playbackSpeed = n
			end
		end
	end
	return {
		name = getTextInput(refs.formTrackNameField),
		playlistId = state.selectedTrackPlaylistId or getTextInput(refs.formTrackPlaylistField),
		creator = getTextInput(refs.formTrackCreatorField),
		parts = parts,
		playbackSpeed = playbackSpeed,
	}
end

function MusicPlayerUIBinder:readPlaylistForm(): { [string]: any }
	local refs = self._refs
	local store = self._store
	local state = store:get()

	return {
		name = getTextInput(refs.formPlaylistNameField),
		coverType = state.selectedCoverType or "gradient", -- "gradient" or "image"
		coverValue = state.selectedCoverValue or 1, -- gradient index or image assetId
		fontFace = if state.selectedCoverType == "image" then "Original" else (state.selectedFontFace or "Original"),
		visibility = state.selectedPlaylistVisibility or "public",
	}
end

function MusicPlayerUIBinder:_selectPlaylistVisibility(visibility: string)
	local refs = self._refs
	local store = self._store
	local _, privateBtn, publicBtn = getPlaylistVisibilityParts(refs.formPlaylist)
	if not privateBtn or not publicBtn then
		return
	end

	local selectedVisibility = if visibility == "private" then "private" else "public"
	copySelectionTemplateVisual(privateBtn, if selectedVisibility == "private" then publicBtn else privateBtn)
	copySelectionTemplateVisual(publicBtn, if selectedVisibility == "public" then publicBtn else privateBtn)
	store:set({ selectedPlaylistVisibility = selectedVisibility })
end

function MusicPlayerUIBinder:bindPlaylistVisibility()
	local refs = self._refs
	local _, privateBtn, publicBtn = getPlaylistVisibilityParts(refs.formPlaylist)
	if not privateBtn or not publicBtn then
		return
	end

	trackConnection(
		self,
		privateBtn.Activated:Connect(function()
			self:_selectPlaylistVisibility("private")
		end)
	)
	trackConnection(
		self,
		publicBtn.Activated:Connect(function()
			self:_selectPlaylistVisibility("public")
		end)
	)

	self:_selectPlaylistVisibility(self._store:get().selectedPlaylistVisibility or "public")
end

function MusicPlayerUIBinder:bindRequestFromId()
	local refs = self._refs
	if not refs.requestFromIdButton then
		return
	end

	local function submitRequestFromId()
		if not refs.requestFromIdInput or not self._onResolveRequestAsset then
			return
		end
		local raw = refs.requestFromIdInput.Text
		if type(raw) ~= "string" or raw:match("^%s*$") then
			if self._onFormNotify then
				self._onFormNotify("warning", "Asset ID required", "Enter a Roblox audio asset ID first.")
			end
			return
		end
		self._onResolveRequestAsset(raw)
	end

	trackConnection(self, refs.requestFromIdButton.Activated:Connect(submitRequestFromId))
	if refs.requestFromIdInput then
		trackConnection(
			self,
			refs.requestFromIdInput.FocusLost:Connect(function(enterPressed: boolean)
				if enterPressed then
					submitRequestFromId()
				end
			end)
		)
	end
end

-- ============================================================
-- COVER & FONT CUSTOMIZATION
-- ============================================================

local function setCoverTabButtonVisual(button: Instance?, selected: boolean)
	if not button or not button:IsA("GuiObject") then
		return
	end
	local gui = button :: GuiObject
	gui.BackgroundColor3 = if selected then Color3.fromRGB(8, 8, 8) else Color3.fromRGB(48, 48, 48)
	gui.BackgroundTransparency = 0
	setAllChildGradientsEnabled(gui, false)

	if button:IsA("TextButton") then
		local textButton = button :: TextButton
		textButton.TextTransparency = if selected then 0 else 0.05
	else
		local textLabel = button:FindFirstChildWhichIsA("TextLabel", true)
		if textLabel then
			textLabel.TextTransparency = if selected then 0 else 0.05
		end
	end
end

function MusicPlayerUIBinder:_setCoverTab(tabType: string)
	local _, colorTabBtn, imageTabBtn, _, colorTemplateList, inputImageID, selectFontFace =
		getCustomizeCoverParts(self._refs.formPlaylist)
	if not colorTemplateList or not inputImageID then
		return
	end

	local isImage = tabType == "image"
	if colorTemplateList:IsA("GuiObject") then
		(colorTemplateList :: GuiObject).Visible = not isImage
	end
	if inputImageID:IsA("GuiObject") then
		(inputImageID :: GuiObject).Visible = isImage
	end
	if selectFontFace and selectFontFace:IsA("GuiObject") then
		(selectFontFace :: GuiObject).Visible = not isImage
	end

	setCoverTabButtonVisual(colorTabBtn, not isImage)
	setCoverTabButtonVisual(imageTabBtn, isImage)
	self._store:set({ selectedCoverType = if isImage then "image" else "gradient" })
end

function MusicPlayerUIBinder:applyCoverStyle(coverElement: Instance, playlist: any)
	-- Apply cover style (gradient or image) to a playlist cover element
	-- coverElement can be an ImageLabel (playlist cover) or a Frame container
	-- that owns a background gradient (now playing wrapper).

	local imageLabel = if coverElement:IsA("ImageLabel") then coverElement else nil

	local config = self._config
	if not config then
		return
	end

	-- Default to gradient if no coverType specified
	local coverType = playlist.coverType or "gradient"
	local textLabel = if imageLabel then findCoverTextLabel(imageLabel) else nil
	local backgroundGradient = coverElement:FindFirstChild("BackgroundNowPlaying(DependsonPlaylist)", true)
	local targetGradient = if imageLabel
		then (imageLabel :: ImageLabel):FindFirstChildOfClass("UIGradient")
		else if backgroundGradient and backgroundGradient:IsA("UIGradient") then backgroundGradient else nil
	local strokeTransparencyAttribute = "MusicCoverBaseStrokeTransparency"
	local backgroundTransparencyAttribute = "MusicCoverBaseBackgroundTransparency"

	local function applyCoverText()
		if not textLabel then
			return
		end
		textLabel.Visible = coverType ~= "image"
		textLabel.Text = playlist.name or ""

		local success = applyNamedFont(textLabel, tostring(playlist.fontFace or "Original"))
		if not success then
			textLabel.FontFace = Font.fromEnum(Enum.Font.SourceSans)
		end
	end

	-- Disable ALL UIGradient descendants when in image mode (CoverImageType rule)
	local function setAllGradientsEnabled(enabled: boolean)
		for _, descendant in ipairs(coverElement:GetDescendants()) do
			if descendant:IsA("UIGradient") then
				descendant.Enabled = enabled
			end
		end
		if targetGradient and targetGradient:IsA("UIGradient") then
			targetGradient.Enabled = enabled
		end
	end

	local function setImageCoverChromeVisible(root: Instance, visible: boolean)
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("UIStroke") then
				local stroke = descendant :: UIStroke
				local baseTransparency = stroke:GetAttribute(strokeTransparencyAttribute)
				if type(baseTransparency) ~= "number" then
					baseTransparency = stroke.Transparency
					stroke:SetAttribute(strokeTransparencyAttribute, baseTransparency)
				end
				stroke.Transparency = if visible then baseTransparency else 1
			end
		end
	end

	local function setImageCoverBackgroundVisible(label: ImageLabel, visible: boolean)
		local baseTransparency = label:GetAttribute(backgroundTransparencyAttribute)
		if type(baseTransparency) ~= "number" then
			baseTransparency = label.BackgroundTransparency
			label:SetAttribute(backgroundTransparencyAttribute, baseTransparency)
		end
		label.BackgroundTransparency = if visible then baseTransparency else 1
	end

	if coverType == "image" then
		setAllGradientsEnabled(false)
		if imageLabel then
			local typedImageLabel = imageLabel :: ImageLabel
			setImageCoverChromeVisible(typedImageLabel, false)
			setImageCoverBackgroundVisible(typedImageLabel, false)
			typedImageLabel.Image = getImageCoverUri(playlist.coverValue) or ""
			applyCoverText()
		elseif targetGradient and targetGradient:IsA("UIGradient") then
			targetGradient.Color = ColorSequence.new(Color3.fromRGB(22, 22, 22), Color3.fromRGB(0, 0, 0))
			targetGradient.Rotation = 90
		end
	else
		-- Gradient mode: enable UIGradient, set colors
		local gradientIndex = playlist.coverValue or 1
		local gradients = config.COVER_GRADIENTS

		if gradients and gradientIndex >= 1 and gradientIndex <= #gradients then
			local gradient = gradients[gradientIndex]

			local uiGradient = targetGradient
			if imageLabel and not uiGradient then
				local created = Instance.new("UIGradient")
				created.Parent = imageLabel
				uiGradient = created
			end

			if uiGradient and uiGradient:IsA("UIGradient") then
				uiGradient.Enabled = true
				uiGradient.Color = buildCoverGradientColorSequence(gradient)
				uiGradient.Rotation = getCoverGradientRotation(gradient)
			end

			if imageLabel then
				-- Reset image to empty (show gradient only)
				local typedImageLabel = imageLabel :: ImageLabel
				setImageCoverChromeVisible(typedImageLabel, true)
				setImageCoverBackgroundVisible(typedImageLabel, true)
				typedImageLabel.Image = ""
			end
			applyCoverText()
		end
	end
end

function MusicPlayerUIBinder:_populatePlaylistPreviewCard(template: Instance, playlist: any)
	local name = if type(playlist) == "table" then tostring(playlist.name or "") else ""
	local trackCount = getPlaylistTrackCount(playlist)

	local info = template:FindFirstChild("PlaylistInformation")
	if info then
		local nameLabel = info:FindFirstChild("PlaylistName")
		if nameLabel and nameLabel:IsA("TextLabel") then
			(nameLabel :: TextLabel).Text = name
		end

		local totalTrackLabel = info:FindFirstChild("TotalTrack")
		if totalTrackLabel and totalTrackLabel:IsA("TextLabel") then
			(totalTrackLabel :: TextLabel).Text = formatTrackCount(trackCount)
		end
	end

	local coverElement = template:FindFirstChild("PlaylistCover")
	if coverElement and type(playlist) == "table" then
		self:applyCoverStyle(coverElement, playlist)
		local coverName = coverElement:FindFirstChild("PlaylistName")
		if coverName and coverName:IsA("TextLabel") then
			(coverName :: TextLabel).Text = name
		end
	end
end

function MusicPlayerUIBinder:_buildUpdatedPlaylistPreview(
	beforePlaylist: any?,
	formData: { [string]: any }
): { [string]: any }
	local preview: { [string]: any } = {}
	if type(beforePlaylist) == "table" then
		for key, value in pairs(beforePlaylist) do
			preview[key] = value
		end
	end
	preview.name = formData.name
	preview.coverType = formData.coverType
	preview.coverValue = formData.coverValue
	preview.fontFace = formData.fontFace
	preview.visibility = formData.visibility or preview.visibility or "public"
	preview.trackIds = if type(preview.trackIds) == "table" then preview.trackIds else {}
	return preview
end

function MusicPlayerUIBinder:_buildUpdatedTrackPreview(
	beforeTrack: any?,
	formData: { [string]: any }
): { [string]: any }
	local preview: { [string]: any } = {}
	if type(beforeTrack) == "table" then
		for key, value in pairs(beforeTrack) do
			preview[key] = value
		end
	end

	preview.name = formData.name
	preview.creator = formData.creator
	preview.parts = formData.parts
	preview.playlistId = formData.playlistId
	if formData.id ~= nil then
		preview.id = formData.id
	end

	local playlistsById = self._store:get().playlists or {}
	local playlistId = tostring(formData.playlistId or "")
	if playlistId ~= "" then
		preview.playlist = playlistsById[playlistId] or preview.playlist
	end

	preview.totalDuration = tonumber(formData.totalDuration) or tonumber(preview.totalDuration) or 0
	return preview
end

function MusicPlayerUIBinder:_populateTrackPreviewCard(template: Instance, track: any, playlist: any?)
	local previewTrack = if type(track) == "table" then track else {}
	local resolvedPlaylist = playlist or previewTrack.playlist

	template.Visible = true

	local coverElement = template:FindFirstChild("RelatedPlaylistCover")
	if coverElement then
		if resolvedPlaylist then
			self:applyCoverStyle(coverElement, resolvedPlaylist)
		end

		local playlistNameLabel = findCoverTextLabel(coverElement)
		if playlistNameLabel then
			playlistNameLabel.Text = (resolvedPlaylist and resolvedPlaylist.name) or ""
		end
	end

	local infoWrap = template:FindFirstChild("TrackInformationWrapper")
	local info = infoWrap and infoWrap:FindFirstChild("TrackInformation")
	local nestedDetails = info and info:FindFirstChild("TrackDetails")
	local details = nestedDetails or info
	if details then
		local titleLabel = details:FindFirstChild("TrackTitle")
		if titleLabel and titleLabel:IsA("TextLabel") then
			(titleLabel :: TextLabel).Text = tostring(previewTrack.name or "")
		end

		local creatorLabel = details:FindFirstChild("TrackCreator") or details:FindFirstChild("TrackLength")
		if creatorLabel and creatorLabel:IsA("TextLabel") then
			(creatorLabel :: TextLabel).Text = tostring(previewTrack.creator or "")
		end
	end

	local addWrap = if info then (info:FindFirstChild("AddToQueueWrapper") or info) else nil
	if addWrap then
		local trackLengthLabel = addWrap:FindFirstChild("TrackLength")
		if trackLengthLabel and trackLengthLabel:IsA("TextLabel") then
			(trackLengthLabel :: TextLabel).Text = formatClock(tonumber(previewTrack.totalDuration) or 0)
		end

		local addBtn = addWrap:FindFirstChild("AddToQueueButton")
		if addBtn and addBtn:IsA("GuiObject") then
			addBtn.Visible = false
		end
	end
end

function MusicPlayerUIBinder:_hidePlaylistRelatedModalFrames()
	local refs = self._refs
	refs.addToPlaylistConfirmation.Visible = false
	refs.deletePlaylistConfirmation.Visible = false
	refs.editPlaylistConfirmation.Visible = false
end

function MusicPlayerUIBinder:_openPlaylistRelatedModal(modal: Frame)
	local refs = self._refs
	local blur = self:_getPlaylistRelatedBlur()
	local camera = Workspace.CurrentCamera
	self:_hidePlaylistRelatedModalFrames()
	self._activePlaylistRelatedModal = modal

	refs.playlistRelatedBackdropBlur.Active = true
	refs.playlistRelatedBackdropBlur.ZIndex = modal.ZIndex - 1
	refs.playlistRelatedBackdropBlur.BackgroundTransparency = 1
	refs.playlistRelatedBackdropBlur.Visible = true
	TweenService:Create(refs.playlistRelatedBackdropBlur, FADE_INFO_FAST, {
		BackgroundTransparency = getModalBackdropTransparency(),
	}):Play()
	playModalBlur(blur, getPanelBlurSize())
	if camera then
		self._playlistRelatedBaseFov = camera.FieldOfView
		self:_tweenPlaylistRelatedCamera(math.max(1, camera.FieldOfView - PLAYLIST_RELATED_CAMERA_FOV_DELTA))
	end
	self:_suppressPlaylistRelatedWorldChrome()
	self:_hideMainWrapperForPlaylistRelated()
	self._isPlaylistRelatedModalOpen = true

	self._anim:presentDialog(modal)
end

function MusicPlayerUIBinder:closePlaylistRelatedModal(immediate: boolean?, restoreMainWrapper: boolean?)
	local refs = self._refs
	local activeModal = self._activePlaylistRelatedModal
	local blur = self:_getPlaylistRelatedBlur()
	local restoreFov = self._playlistRelatedBaseFov
	local shouldRestoreMainWrapper = restoreMainWrapper ~= false

	self._pendingPlaylistModalAction = nil
	self._activePlaylistRelatedModal = nil
	self._isPlaylistRelatedModalOpen = false
	self._playlistRelatedBaseFov = nil

	if immediate then
		blur.Size = 0
		blur.Enabled = false
		if restoreFov then
			self:_tweenPlaylistRelatedCamera(restoreFov, true)
		end
		refs.playlistRelatedBackdropBlur.Visible = false
		refs.playlistRelatedBackdropBlur.Active = false
		refs.playlistRelatedBackdropBlur.BackgroundTransparency = getModalBackdropTransparency()
		self:_restorePlaylistRelatedWorldChrome()
		if shouldRestoreMainWrapper then
			self:_restoreMainWrapperAfterPlaylistRelated()
		else
			self:_clearPlaylistRelatedMainWrapperRestore()
		end
		if activeModal then
			local modalScale = activeModal:FindFirstChildWhichIsA("UIScale")
			if modalScale then
				modalScale.Scale = 1
			end
		end
		self:_hidePlaylistRelatedModalFrames()
		return
	end

	TweenService:Create(blur, FADE_INFO_FAST, {
		Size = 0,
	}):Play()
	if restoreFov then
		self:_tweenPlaylistRelatedCamera(restoreFov)
	end
	refs.playlistRelatedBackdropBlur.Active = false
	TweenService:Create(refs.playlistRelatedBackdropBlur, FADE_INFO_FAST, {
		BackgroundTransparency = 1,
	}):Play()
	task.delay(FADE_INFO_FAST.Time, function()
		if not self._isPlaylistRelatedModalOpen then
			blur.Enabled = false
			refs.playlistRelatedBackdropBlur.Visible = false
			refs.playlistRelatedBackdropBlur.Active = false
			refs.playlistRelatedBackdropBlur.BackgroundTransparency = getModalBackdropTransparency()
			self:_restorePlaylistRelatedWorldChrome()
		end
	end)

	if activeModal then
		self._anim:dismissDialog(activeModal, function()
			if self._isPlaylistRelatedModalOpen then
				return
			end
			self:_hidePlaylistRelatedModalFrames()
			if shouldRestoreMainWrapper then
				self:_restoreMainWrapperAfterPlaylistRelated()
			else
				self:_clearPlaylistRelatedMainWrapperRestore()
			end
		end)
	else
		self:_hidePlaylistRelatedModalFrames()
		if shouldRestoreMainWrapper then
			self:_restoreMainWrapperAfterPlaylistRelated()
		else
			self:_clearPlaylistRelatedMainWrapperRestore()
		end
	end
end

function MusicPlayerUIBinder:_openCreatePlaylistConfirmation(formData: { [string]: any })
	local refs = self._refs
	local preview = self:_buildUpdatedPlaylistPreview(nil, formData)
	self._pendingPlaylistModalAction = {
		action = "create",
		data = formData,
	}
	self:_closeManageFormForConfirmation()
	self:_populatePlaylistPreviewCard(refs.addToPlaylistTemplate, preview)
	self:_openPlaylistRelatedModal(refs.addToPlaylistConfirmation)
end

function MusicPlayerUIBinder:_openDeletePlaylistConfirmation(playlist: any, data: { [string]: any })
	local refs = self._refs
	self._pendingPlaylistModalAction = {
		action = "delete",
		data = data,
	}
	self:_populatePlaylistPreviewCard(refs.deletePlaylistTemplate, playlist)
	self:_openPlaylistRelatedModal(refs.deletePlaylistConfirmation)
end

function MusicPlayerUIBinder:_openUpdatePlaylistConfirmation(beforePlaylist: any, formData: { [string]: any })
	local refs = self._refs
	local afterPlaylist = self:_buildUpdatedPlaylistPreview(beforePlaylist, formData)
	self._pendingPlaylistModalAction = {
		action = "update",
		data = formData,
	}
	self:_closeManageFormForConfirmation()
	self:_populatePlaylistPreviewCard(refs.editPlaylistBeforeTemplate, beforePlaylist)
	self:_populatePlaylistPreviewCard(refs.editPlaylistAfterTemplate, afterPlaylist)
	self:_openPlaylistRelatedModal(refs.editPlaylistConfirmation)
end

function MusicPlayerUIBinder:_confirmPlaylistRelatedModal()
	local pending = self._pendingPlaylistModalAction
	if not pending then
		self:closePlaylistRelatedModal()
		return
	end

	local action = pending.action
	local data = pending.data
	self:closePlaylistRelatedModal()
	if action == "create" then
		self:_enterManageIdle(false)
	elseif action == "update" then
		self:setManageSubView("idle", { preserveEditing = true })
	else
		self:_enterManageIdle(false)
	end
	if self._onManagePlaylist then
		self._onManagePlaylist(action, data)
	end
end

function MusicPlayerUIBinder:bindCoverTabs()
	local refs = self._refs
	local store = self._store

	local _, colorTabBtn, imageTabBtn, _, colorTemplateList, inputImageID = getCustomizeCoverParts(refs.formPlaylist)

	if not colorTabBtn or not imageTabBtn or not colorTemplateList or not inputImageID then
		return
	end

	-- Bind tab buttons
	if colorTabBtn:IsA("TextButton") then
		trackConnection(
			self,
			(colorTabBtn :: TextButton).Activated:Connect(function()
				self:_setCoverTab("color")
			end)
		)
	end

	if imageTabBtn:IsA("TextButton") then
		trackConnection(
			self,
			(imageTabBtn :: TextButton).Activated:Connect(function()
				self:_setCoverTab("image")
			end)
		)
	end

	-- Bind image input TextBox
	if inputImageID:IsA("TextBox") then
		trackConnection(
			self,
			(inputImageID :: TextBox):GetPropertyChangedSignal("Text"):Connect(function()
				if not (inputImageID :: TextBox).Visible then
					return
				end
				local assetId = (inputImageID :: TextBox).Text
				store:set({
					selectedCoverType = "image",
					selectedCoverValue = assetId,
				})
			end)
		)
	end

	-- Default to color tab
	self:_setCoverTab("color")
end

function MusicPlayerUIBinder:bindColorSelection()
	local refs = self._refs
	local store = self._store
	local config = self._config

	if not config or not config.COVER_GRADIENTS then
		return
	end

	local customizeCover = select(1, getCustomizeCoverParts(refs.formPlaylist))
	if not customizeCover then
		return
	end

	local colorTemplateList = select(5, getCustomizeCoverParts(refs.formPlaylist))
	if not colorTemplateList then
		return
	end

	-- Find template cards (NormalState and SelectedState)
	local normalTemplate = colorTemplateList:FindFirstChild("NormalState")
	local selectedTemplate = colorTemplateList:FindFirstChild("SelectedState")

	if not normalTemplate or not selectedTemplate then
		return
	end

	-- Hide templates
	normalTemplate.Visible = false
	selectedTemplate.Visible = false

	-- Clear existing clones
	for _, child in ipairs(colorTemplateList:GetChildren()) do
		if child:IsA("TextButton") and child.Name:match("^GradientCard_") then
			child:Destroy()
		end
	end

	-- Create gradient cards from config
	local gradients = config.COVER_GRADIENTS
	for i, gradient in ipairs(gradients) do
		local card = normalTemplate:Clone()
		card.Name = "GradientCard_" .. tostring(i)
		card.Visible = true
		card.LayoutOrder = i

		-- Apply gradient to card's ImageLabel
		local imageLabel = card:FindFirstChild("ImageLabel")
		if imageLabel then
			local uiGradient = imageLabel:FindFirstChildOfClass("UIGradient")
			if not uiGradient then
				uiGradient = Instance.new("UIGradient")
				uiGradient.Parent = imageLabel
			end

			-- Set gradient colors and rotation
			uiGradient.Color = buildCoverGradientColorSequence(gradient)
			uiGradient.Rotation = getCoverGradientRotation(gradient)

			-- Find and setup the playlist name label
			local playlistNameLabel = imageLabel:FindFirstChild("PlaylistNameDynamic")
			if playlistNameLabel and playlistNameLabel:IsA("TextLabel") then
				-- Will be updated when playlist name changes
				(playlistNameLabel :: TextLabel).Text = ""

				-- Apply default font
				local defaultFont = store:get().selectedFontFace or "Original"
				local success = applyNamedFont(playlistNameLabel :: TextLabel, defaultFont)
				if not success then
					(playlistNameLabel :: TextLabel).FontFace = Font.fromEnum(Enum.Font.SourceSans)
				end
			end

			-- Find indicator frame
			local indicator = imageLabel:FindFirstChild("NormalorSelectedIndicatorsNormal")
			if indicator then
				local frame = indicator:FindFirstChild("Frame")
				if frame then
					frame.Visible = false -- Hidden by default
				end
			end
		end

		-- Bind click event
		if card:IsA("TextButton") then
			trackConnection(
				self,
				(card :: TextButton).Activated:Connect(function()
					self:_selectGradient(i)
				end)
			)
		end

		card.Parent = colorTemplateList
	end

	-- Select first gradient by default
	self:_selectGradient(1)

	-- Subscribe to playlist name changes to update preview
	trackUnsubscriber(
		self,
		store:subscribe("playlistNamePreview", function(name)
			self:_updateGradientPreviews(name)
		end)
	)
end

function MusicPlayerUIBinder:_selectGradient(index: number)
	local refs = self._refs
	local store = self._store
	self:_setCoverTab("color")

	local customizeCover = select(1, getCustomizeCoverParts(refs.formPlaylist))
	if not customizeCover then
		return
	end

	local colorTemplateList = select(5, getCustomizeCoverParts(refs.formPlaylist))
	if not colorTemplateList then
		return
	end
	local normalTemplate = colorTemplateList:FindFirstChild("NormalState")
	local selectedTemplate = colorTemplateList:FindFirstChild("SelectedState")

	-- Hide all indicators first
	for _, child in ipairs(colorTemplateList:GetChildren()) do
		if child:IsA("TextButton") and child.Name:match("^GradientCard_") then
			local isSelected = child.Name == "GradientCard_" .. tostring(index)
			copySelectionTemplateVisual(child, if isSelected then selectedTemplate else normalTemplate)

			local imageLabel = child:FindFirstChild("ImageLabel")
			if imageLabel then
				local indicator = imageLabel:FindFirstChild("NormalorSelectedIndicatorsNormal")
				if indicator then
					local frame = indicator:FindFirstChild("Frame")
					if frame then
						frame.Visible = false
					end
				end
			end
		end
	end

	-- Show indicator for selected card
	local selectedCard = colorTemplateList:FindFirstChild("GradientCard_" .. tostring(index))
	if selectedCard then
		local imageLabel = selectedCard:FindFirstChild("ImageLabel")
		if imageLabel then
			local indicator = imageLabel:FindFirstChild("NormalorSelectedIndicatorsNormal")
			if indicator then
				local frame = indicator:FindFirstChild("Frame")
				if frame then
					frame.Visible = true
				end
			end
		end
	end

	-- Update store
	store:set({
		selectedCoverType = "gradient",
		selectedCoverValue = index,
	})
end

function MusicPlayerUIBinder:_updateGradientPreviews(playlistName: string)
	-- Update playlist name text in all gradient preview cards
	local refs = self._refs
	local store = self._store
	local state = store:get()

	local customizeCover = select(1, getCustomizeCoverParts(refs.formPlaylist))
	if not customizeCover then
		return
	end

	local colorTemplateList = select(5, getCustomizeCoverParts(refs.formPlaylist))
	if not colorTemplateList then
		return
	end

	-- Update all gradient cards
	for _, child in ipairs(colorTemplateList:GetChildren()) do
		if child:IsA("TextButton") and child.Name:match("^GradientCard_") then
			local imageLabel = child:FindFirstChild("ImageLabel")
			if imageLabel then
				-- Find TextLabel (not PlaylistNameDynamic)
				local textLabel = imageLabel:FindFirstChild("PlaylistNameDynamic")
					or imageLabel:FindFirstChild("TextLabel")
				if textLabel and textLabel:IsA("TextLabel") then
					(textLabel :: TextLabel).Text = playlistName or ""

					-- Apply current selected font
					local fontFace = state.selectedFontFace or "Original"
					local success = applyNamedFont(textLabel :: TextLabel, fontFace)
					if not success then
						-- Fallback to default
						(textLabel :: TextLabel).FontFace = Font.fromEnum(Enum.Font.SourceSans)
					end
				end
			end
		end
	end
end

function MusicPlayerUIBinder:renderTrackPlaylistOptions(playlists: { [string]: any })
	local refs = self._refs
	local store = self._store

	local selectorField = refs.formTrackPlaylistField
	if not selectorField then
		return
	end

	local selectWrapper = selectorField:FindFirstChild("SelectWrapper")
	if not selectWrapper then
		return
	end

	local scrollablePlaylist = selectWrapper:FindFirstChild("ScrollablePlaylist")
	if not scrollablePlaylist or not scrollablePlaylist:IsA("ScrollingFrame") then
		return
	end

	local normalTemplate = scrollablePlaylist:FindFirstChild("Normal")
		or scrollablePlaylist:FindFirstChild("NormalState")
	local selectedTemplate = scrollablePlaylist:FindFirstChild("Selected")
		or scrollablePlaylist:FindFirstChild("SelectedState")

	if not normalTemplate or not selectedTemplate then
		return
	end

	if normalTemplate:IsA("GuiObject") then
		normalTemplate.Visible = false
	end
	if selectedTemplate:IsA("GuiObject") then
		selectedTemplate.Visible = false
	end

	for _, child in ipairs(scrollablePlaylist:GetChildren()) do
		if child:IsA("TextButton") and child.Name:match("^PlaylistOption_") then
			child:Destroy()
		end
	end

	local orderedPlaylists = {}
	for id, playlist in pairs(playlists) do
		table.insert(orderedPlaylists, {
			id = id,
			playlist = playlist,
		})
	end

	table.sort(orderedPlaylists, function(a, b)
		local aName = tostring(a.playlist.name or ""):lower()
		local bName = tostring(b.playlist.name or ""):lower()
		return aName < bName
	end)

	for index, entry in ipairs(orderedPlaylists) do
		local card = (normalTemplate :: Instance):Clone()
		if not card:IsA("TextButton") then
			card:Destroy()
			continue
		end

		card.Name = "PlaylistOption_" .. tostring(entry.id)
		card.Visible = true
		card.LayoutOrder = index

		local imageLabel = card:FindFirstChild("ImageLabel")
			or card:FindFirstChild("PlaylistCover")
			or card:FindFirstChild("Cover")
		if imageLabel then
			self:applyCoverStyle(imageLabel, entry.playlist)
			local indicatorFrame = findIndicatorFrame(imageLabel)
			if indicatorFrame then
				indicatorFrame.Visible = false
			end
		end

		bindClickable(card, function()
			self:_selectTrackPlaylist(tostring(entry.id))
		end)

		card.Parent = scrollablePlaylist
	end

	local selectedPlaylistId = store:get().selectedTrackPlaylistId
	if selectedPlaylistId and playlists[selectedPlaylistId] then
		self:_selectTrackPlaylist(selectedPlaylistId)
	else
		store:set({ selectedTrackPlaylistId = nil })
	end
end

function MusicPlayerUIBinder:_selectTrackPlaylist(playlistId: string)
	local refs = self._refs
	local store = self._store

	local selectorField = refs.formTrackPlaylistField
	if not selectorField then
		return
	end

	local selectWrapper = selectorField:FindFirstChild("SelectWrapper")
	if not selectWrapper then
		return
	end

	local scrollablePlaylist = selectWrapper:FindFirstChild("ScrollablePlaylist")
	if not scrollablePlaylist or not scrollablePlaylist:IsA("ScrollingFrame") then
		return
	end

	for _, child in ipairs(scrollablePlaylist:GetChildren()) do
		if child:IsA("TextButton") and child.Name:match("^PlaylistOption_") then
			local imageLabel = child:FindFirstChild("ImageLabel")
				or child:FindFirstChild("PlaylistCover")
				or child:FindFirstChild("Cover")
			local indicatorFrame = findIndicatorFrame(imageLabel)
			if indicatorFrame then
				indicatorFrame.Visible = false
			end
		end
	end

	local selectedCard = scrollablePlaylist:FindFirstChild("PlaylistOption_" .. playlistId)
	if selectedCard and selectedCard:IsA("TextButton") then
		local imageLabel = selectedCard:FindFirstChild("ImageLabel")
			or selectedCard:FindFirstChild("PlaylistCover")
			or selectedCard:FindFirstChild("Cover")
		local indicatorFrame = findIndicatorFrame(imageLabel)
		if indicatorFrame then
			indicatorFrame.Visible = true
		end
	end

	store:set({ selectedTrackPlaylistId = playlistId })
end

function MusicPlayerUIBinder:bindFontSelection()
	local refs = self._refs
	local config = self._config

	if not config or not config.FONT_PRESETS then
		return
	end

	local selectFontFace = select(7, getCustomizeCoverParts(refs.formPlaylist))
	if not selectFontFace then
		return
	end

	local selectFontFaceList = selectFontFace:FindFirstChild("SelectFontFaceList")
	if not selectFontFaceList then
		return
	end

	local scrollableFontFace = selectFontFaceList:FindFirstChild("ScrollableFontFace")
	if not scrollableFontFace then
		return
	end

	-- Find template cards
	local normalTemplate = scrollableFontFace:FindFirstChild("Normal")
	local selectedTemplate = scrollableFontFace:FindFirstChild("Selected")

	if not normalTemplate or not selectedTemplate then
		return
	end

	-- Hide templates
	normalTemplate.Visible = false
	selectedTemplate.Visible = false

	-- Clear existing clones
	for _, child in ipairs(scrollableFontFace:GetChildren()) do
		if child:IsA("TextButton") and child.Name:match("^FontCard_") then
			child:Destroy()
		end
	end

	-- Create font cards from config
	local fonts = config.FONT_PRESETS
	for i, fontName in ipairs(fonts) do
		local card = normalTemplate:Clone()
		card.Name = "FontCard_" .. tostring(i)
		card.Visible = true
		card.LayoutOrder = i

		-- Set font name in card
		local imageLabel = card:FindFirstChild("ImageLabel")
		if imageLabel then
			local fontLabel = imageLabel:FindFirstChild("FontFace") or imageLabel:FindFirstChild("FontFaceName")
			if fontLabel and fontLabel:IsA("TextLabel") then
				(fontLabel :: TextLabel).Text = fontName
				local success = applyNamedFont(fontLabel :: TextLabel, fontName)
				if not success then
					-- Fallback to default if font not found
					(fontLabel :: TextLabel).FontFace = Font.fromEnum(Enum.Font.SourceSans)
				end
			end

			-- Find indicator frame
			local indicator = imageLabel:FindFirstChild("NormalStateIndicator")
				or imageLabel:FindFirstChild("SelectedIndicator")
			if indicator then
				local frame = indicator:FindFirstChild("Frame")
				if frame then
					frame.Visible = false -- Hidden by default
				end
			end
		end

		-- Bind click event
		if card:IsA("TextButton") then
			trackConnection(
				self,
				(card :: TextButton).Activated:Connect(function()
					self:_selectFont(i, fontName)
				end)
			)
		end

		card.Parent = scrollableFontFace
	end

	-- Select first font by default
	self:_selectFont(1, fonts[1])
end

function MusicPlayerUIBinder:_selectFont(index: number, fontName: string)
	local refs = self._refs
	local store = self._store

	local selectFontFace = select(7, getCustomizeCoverParts(refs.formPlaylist))
	if not selectFontFace then
		return
	end

	local selectFontFaceList = selectFontFace:FindFirstChild("SelectFontFaceList")
	if not selectFontFaceList then
		return
	end

	local scrollableFontFace = selectFontFaceList:FindFirstChild("ScrollableFontFace")
	if not scrollableFontFace then
		return
	end
	local normalTemplate = scrollableFontFace:FindFirstChild("Normal")
	local selectedTemplate = scrollableFontFace:FindFirstChild("Selected")

	-- Hide all indicators first
	for _, child in ipairs(scrollableFontFace:GetChildren()) do
		if child:IsA("TextButton") and child.Name:match("^FontCard_") then
			local isSelected = child.Name == "FontCard_" .. tostring(index)
			copySelectionTemplateVisual(child, if isSelected then selectedTemplate else normalTemplate)

			local imageLabel = child:FindFirstChild("ImageLabel")
			if imageLabel then
				local indicator = imageLabel:FindFirstChild("NormalStateIndicator")
					or imageLabel:FindFirstChild("SelectedIndicator")
				if indicator then
					local frame = indicator:FindFirstChild("Frame")
					if frame then
						frame.Visible = false
					end
				end
			end
		end
	end

	-- Show indicator for selected card
	local selectedCard = scrollableFontFace:FindFirstChild("FontCard_" .. tostring(index))
	if selectedCard then
		local imageLabel = selectedCard:FindFirstChild("ImageLabel")
		if imageLabel then
			local indicator = imageLabel:FindFirstChild("NormalStateIndicator")
				or imageLabel:FindFirstChild("SelectedIndicator")
			if indicator then
				local frame = indicator:FindFirstChild("Frame")
				if frame then
					frame.Visible = true
				end
			end
		end
	end

	-- Update store
	store:set({ selectedFontFace = fontName })

	-- Update gradient preview cards with new font
	local state = store:get()
	self:_updateGradientPreviews(state.playlistNamePreview or "")
end

-- ============================================================
-- MANAGE LIST RENDER
-- ============================================================

function MusicPlayerUIBinder:renderManagePlaylists(playlists: { any }, searchQuery: string?)
	local refs = self._refs
	local store = self._store
	local scroll = refs.scrollableManagePlaylist
	local template = refs.managePlaylistTemplate

	self:renderTrackPlaylistOptions(playlists)

	template.Visible = false

	local orderedPlaylists = buildOrderedPlaylistEntries(playlists, searchQuery)
	hideUnusedPooledRows(self._managePlaylistRowPool, 1)

	startListRenderJob(self, "managePlaylists", #orderedPlaylists, function(index: number)
		local entry = orderedPlaylists[index]
		local id = entry.id
		local playlist = entry.playlist
		local row = ensurePooledRow(self._managePlaylistRowPool, index, template, scroll)
		disconnectPooledRowConnections(row)
		local clone = row.instance

		-- PlaylistTemplate (manage): PlaylistInfo -> PlaylistDetail -> PlaylistName [TextLabel]
		local info = clone:FindFirstChild("PlaylistInfo")
		if info then
			local detail = info:FindFirstChild("PlaylistDetail")
			if detail then
				local nameLabel = detail:FindFirstChild("PlaylistName")
				if nameLabel and nameLabel:IsA("TextLabel") then
					local displayName = playlist.name or ""
					if playlist.visibility == "private" then
						displayName = displayName .. " (Private)"
					end
					(nameLabel :: TextLabel).Text = displayName
				end
				setTextLabelByNames(
					detail,
					{ "TotalTracks", "TotalTrack" },
					formatTrackCount(getPlaylistTrackCount(playlist))
				)
			end
			-- EditButton & DeleteButton di dalam PlaylistInfo -> InputArea
			local inputArea = info:FindFirstChild("InputArea")
			if inputArea then
				local editBtn = findFirstByNames(inputArea, {
					"EditButton",
					"EditPlaylistButton",
					"EditTrackButton",
				})
				bindTrackedClickable(row.connections, editBtn, function()
					if isManageInteractionBlocked(store) then
						return
					end
					if self._onManageSubView then
						self._onManageSubView("edit_playlist", playlist)
					end
				end)

				-- Delete button binding
				local deleteBtn = findFirstByNames(inputArea, {
					"DeleteButton",
					"DeletePlaylistButton",
					"DeleteTrackButton",
				})
				bindTrackedClickable(row.connections, deleteBtn, function()
					if isManageInteractionBlocked(store) then
						return
					end
					self:_openDeletePlaylistConfirmation(playlist, { id = id })
				end)
			end
		end

		-- Apply cover style to playlist cover element
		-- Try multiple possible locations for cover element
		local playlistInfo = clone:FindFirstChild("PlaylistInfo")
		local coverElement = clone:FindFirstChild("PlaylistCover")
			or clone:FindFirstChild("ImageLabel")
			or clone:FindFirstChild("Cover")
			or (playlistInfo and playlistInfo:FindFirstChild("ImageLabel"))

		if coverElement then
			self:applyCoverStyle(coverElement, playlist)
		end

		clone.Name = id
		clone.LayoutOrder = index
		clone.Visible = true
		animateListRowIn(clone)
	end)
end

function MusicPlayerUIBinder:_populateManageTrackRow(
	row: any,
	track: any,
	trackData: any,
	index: number,
	id: string,
	store: any
)
	local clone = row.instance
	local parentPlaylist = trackData.playlist

	local trackInfo = clone:FindFirstChild("TrackInfo")
	if trackInfo then
		local detailed = trackInfo:FindFirstChild("TrackDetailed")
		if detailed then
			local trackFrame = detailed:FindFirstChild("Track")
			if trackFrame then
				local titleLabel = trackFrame:FindFirstChild("TrackTitle")
				if titleLabel and titleLabel:IsA("TextLabel") then
					local label = titleLabel :: TextLabel
					label.Text = track.name or ""
					scheduleTrackTitleHeight(label)
				end
				setTextLabelByNames(
					trackFrame,
					{ "TrackLength", "TrackDuration", "Duration" },
					formatClock(
						tonumber(track.totalDuration or track.duration or track.durationSeconds or track.length or 0)
							or 0
					)
				)
				local creatorLabel = trackFrame:FindFirstChild("TrackCreator")
				if creatorLabel and creatorLabel:IsA("TextLabel") then
					(creatorLabel :: TextLabel).Text = track.creator or ""
				end
			end
			local inputArea = detailed:FindFirstChild("InputArea")
			if inputArea then
				local editBtn = findFirstByNames(inputArea, { "EditButton", "EditTrackButton" })
				bindTrackedClickable(row.connections, editBtn, function()
					if isManageInteractionBlocked(store) then
						return
					end
					if self._onManageSubView then
						self._onManageSubView("edit_track", trackData)
					end
				end)
				local deleteBtn = findFirstByNames(inputArea, { "DeleteButton", "DeleteTrackButton" })
				bindTrackedClickable(row.connections, deleteBtn, function()
					if isManageInteractionBlocked(store) then
						return
					end
					if not self._onManageTrack then
						return
					end
					self:_openDeleteTrackConfirmation(trackData, { id = id })
				end)
			end
		end
	end

	if parentPlaylist then
		local coverElement = clone:FindFirstChild("RelatedPlaylistCover")
			or clone:FindFirstChild("PlaylistCover")
			or clone:FindFirstChild("TrackCover")
		if coverElement then
			self:applyCoverStyle(coverElement, parentPlaylist)
		end
	end

	clone.Name = id
	clone.LayoutOrder = VIRTUAL_ROW_LAYOUT_BASE + index
	clone.Visible = true
end

function MusicPlayerUIBinder:renderManageTracks(tracks: { any }, searchQuery: string?)
	local refs = self._refs
	local store = self._store
	local playlistsById = store:get().playlists or {}
	local scroll = refs.scrollableManageTrack
	local templateLeft = refs.manageTrackTemplate
	local templateRight = refs.manageTrackTemplateRight
	local containerLeft = refs.manageTrackScrollLeft or scroll
	local containerRight = refs.manageTrackScrollRight

	templateLeft.Visible = false
	if templateRight then
		templateRight.Visible = false
	end

	local orderedTracks = buildOrderedTrackEntries(tracks, searchQuery, nil, "")

	if not containerRight then
		renderVirtualList(self, {
			key = "manageTracksLeft",
			scroll = scroll,
			parent = containerLeft :: Instance,
			pool = self._manageTrackRowPool,
			template = templateLeft,
			items = orderedTracks,
			renderRow = function(row: PooledRow, track: any, index: number)
				local id = tostring(track.id or "")
				local parentPlaylist = playlistsById[track.playlistId] or track.playlist
				local trackData = table.clone(track)
				trackData.id = trackData.id or id
				trackData.playlist = parentPlaylist
				self:_populateManageTrackRow(row, track, trackData, index, id, store)
			end,
		})
		disconnectVirtualList(self, "manageTracksRight")
		hideUnusedPooledRows(self._manageTrackRightRowPool, 1)
		return
	end

	local leftTracks = {} :: { any }
	local rightTracks = {} :: { any }
	for index, track in ipairs(orderedTracks) do
		if index % 2 == 1 then
			table.insert(leftTracks, track)
		else
			table.insert(rightTracks, track)
		end
	end

	local function renderManageTrackRow(row: PooledRow, track: any, index: number)
		local id = tostring(track.id or "")
		local parentPlaylist = playlistsById[track.playlistId] or track.playlist
		local trackData = table.clone(track)
		trackData.id = trackData.id or id
		trackData.playlist = parentPlaylist

		self:_populateManageTrackRow(row, track, trackData, index, id, store)
	end

	renderVirtualList(self, {
		key = "manageTracksLeft",
		scroll = scroll,
		parent = containerLeft :: Instance,
		pool = self._manageTrackRowPool,
		template = templateLeft,
		items = leftTracks,
		renderRow = renderManageTrackRow,
	})
	renderVirtualList(self, {
		key = "manageTracksRight",
		scroll = scroll,
		parent = containerRight :: Instance,
		pool = self._manageTrackRightRowPool,
		template = templateRight :: TextButton,
		items = rightTracks,
		renderRow = renderManageTrackRow,
	})
end

-- ============================================================
-- BIND ALL UI EVENTS (dipanggil oleh Controller saat init)
-- ============================================================

function MusicPlayerUIBinder:bindAll()
	local refs = self._refs
	local store = self._store

	-- Jangan pernah tampilkan template mentah di runtime.
	hideIfGuiObject(refs.playlistTemplateNormal)
	hideIfGuiObject(refs.playlistTemplateSelected)
	hideIfGuiObject(refs.queueTemplate)
	hideIfGuiObject(refs.trackTemplateLeft)
	hideIfGuiObject(refs.trackTemplateRight)
	hideIfGuiObject(refs.djTab)
	hideIfGuiObject(refs.managePlaylistTemplate)
	hideIfGuiObject(refs.manageTrackTemplate)
	hideIfGuiObject(refs.addToQueueConfirmation)
	hideIfGuiObject(refs.utilitiesBackdropBlur)
	hideIfGuiObject(refs.voteModal)
	hideIfGuiObject(refs.voteTrackTemplate)
	hideIfGuiObject(refs.playlistRelatedBackdropBlur)
	hideIfGuiObject(refs.addToPlaylistConfirmation)
	hideIfGuiObject(refs.deletePlaylistConfirmation)
	hideIfGuiObject(refs.editPlaylistConfirmation)
	hideIfGuiObject(refs.trackRelatedBackdropBlur)
	hideIfGuiObject(refs.addToTrackConfirmation)
	hideIfGuiObject(refs.deleteTrackConfirmation)
	hideIfGuiObject(refs.editTrackConfirmation)
	hideIfGuiObject(refs.formPlaylist)
	hideIfGuiObject(refs.formTrack)
	if refs.controlledByDjInfo then
		refs.controlledByDjInfo.Visible = false
	end
	if refs.tipsDynamic then
		refs.tipsDynamic.Visible = true
	end
	refs.voteSkipButtonText.Text = "Vote Skip"

	stashTemplateInstance(refs.playlistTemplateNormal, "RuntimeTemplates")
	stashTemplateInstance(refs.playlistTemplateSelected, "RuntimeTemplates")
	stashTemplateInstance(refs.queueTemplate, "RuntimeTemplates")
	stashTemplateInstance(refs.trackTemplateLeft, "RuntimeTemplates")
	stashTemplateInstance(refs.trackTemplateRight, "RuntimeTemplates")
	stashTemplateInstance(refs.managePlaylistTemplate, "RuntimeTemplates")
	stashTemplateInstance(refs.manageTrackTemplate, "RuntimeTemplates")

	-- Close button
	trackConnection(
		self,
		refs.closeButton.Activated:Connect(function()
			if self._onCloseRequested then
				self._onCloseRequested()
			end
		end)
	)

	trackConnection(
		self,
		refs.addToQueueConfirmButton.Activated:Connect(function()
			if self._pendingRequestTrackId and self._onRequestTrack then
				self._onRequestTrack(self._pendingRequestTrackId)
			end
			self:closeAddToQueueConfirmation()
		end)
	)

	trackConnection(
		self,
		refs.addToQueueFavoriteButton.Activated:Connect(function()
			if self._pendingRequestTrackId and self._onAddFavoriteTrack then
				self._onAddFavoriteTrack(self._pendingRequestTrackId, self._pendingFavoriteShouldRemove == true)
			end
			self:closeAddToQueueConfirmation()
		end)
	)

	trackConnection(
		self,
		refs.addToQueueCancelButton.Activated:Connect(function()
			self:closeAddToQueueConfirmation()
		end)
	)

	if refs.addToFavoritesButton then
		local favBtn = refs.addToFavoritesButton
		local favScale = ensureUIScale(favBtn)
		trackConnection(
			self,
			favBtn.Activated:Connect(function()
				local state = store:get()
				local currentTrack = state.currentTrack
				if type(currentTrack) ~= "table" or type(currentTrack.id) ~= "string" then
					return
				end
				-- ScalePop: quick up then smooth spring back
				local popUp = TweenService:Create(
					favScale,
					TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Scale = 1.25 }
				)
				local popDown = TweenService:Create(
					favScale,
					TweenInfo.new(0.30, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
					{ Scale = 1.0 }
				)
				popUp.Completed:Connect(function(s)
					if s == Enum.TweenStatus.Completed then
						popDown:Play()
					end
				end)
				popUp:Play()
				if self._onAddFavoriteTrack then
					local favoriteTrackIds = state.favoriteTrackIds or {}
					self._onAddFavoriteTrack(currentTrack.id, favoriteTrackIds[currentTrack.id] == true)
				end
			end)
		)
	end

	trackConnection(
		self,
		refs.voteRejectButton.Activated:Connect(function()
			if self._onVoteSkip then
				self._onVoteSkip("reject")
			end
		end)
	)

	trackConnection(
		self,
		refs.voteSkipButtonModal.Activated:Connect(function()
			if self._onVoteSkip then
				self._onVoteSkip("skip")
			end
		end)
	)

	trackConnection(
		self,
		refs.utilitiesBackdropBlur.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				self:closeAddToQueueConfirmation()
			end
		end)
	)

	trackConnection(
		self,
		refs.playlistRelatedBackdropBlur.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				self:_cancelPlaylistRelatedConfirmation()
			end
		end)
	)

	trackConnection(
		self,
		refs.addToPlaylistCreateButton.Activated:Connect(function()
			self:_confirmPlaylistRelatedModal()
		end)
	)

	trackConnection(
		self,
		refs.addToPlaylistCancelButton.Activated:Connect(function()
			self:_cancelPlaylistRelatedConfirmation()
		end)
	)

	trackConnection(
		self,
		refs.deletePlaylistConfirmButton.Activated:Connect(function()
			self:_confirmPlaylistRelatedModal()
		end)
	)

	trackConnection(
		self,
		refs.deletePlaylistCancelButton.Activated:Connect(function()
			self:closePlaylistRelatedModal()
		end)
	)

	trackConnection(
		self,
		refs.editPlaylistSaveButton.Activated:Connect(function()
			self:_confirmPlaylistRelatedModal()
		end)
	)

	trackConnection(
		self,
		refs.editPlaylistCancelButton.Activated:Connect(function()
			self:_cancelPlaylistRelatedConfirmation()
		end)
	)

	trackConnection(
		self,
		refs.trackRelatedBackdropBlur.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				self:_cancelTrackRelatedConfirmation()
			end
		end)
	)

	trackConnection(
		self,
		refs.addToTrackSaveButton.Activated:Connect(function()
			self:_confirmTrackRelatedModal()
		end)
	)

	trackConnection(
		self,
		refs.addToTrackCancelButton.Activated:Connect(function()
			self:_cancelTrackRelatedConfirmation()
		end)
	)

	trackConnection(
		self,
		refs.deleteTrackConfirmButton.Activated:Connect(function()
			self:_confirmTrackRelatedModal()
		end)
	)

	trackConnection(
		self,
		refs.deleteTrackCancelButton.Activated:Connect(function()
			self:closeTrackRelatedModal()
		end)
	)

	trackConnection(
		self,
		refs.editTrackSaveButton.Activated:Connect(function()
			self:_confirmTrackRelatedModal()
		end)
	)

	trackConnection(
		self,
		refs.editTrackCancelButton.Activated:Connect(function()
			self:_cancelTrackRelatedConfirmation()
		end)
	)

	-- Tab buttons
	trackConnection(
		self,
		refs.tabs.nowPlaying.Activated:Connect(function()
			self:switchTab("nowplaying")
			if self._onTabSelected then
				self._onTabSelected("nowplaying")
			end
		end)
	)
	trackConnection(
		self,
		refs.tabs.reqSong.Activated:Connect(function()
			self:switchTab("request")
			if self._onTabSelected then
				self._onTabSelected("request")
			end
		end)
	)
	trackConnection(
		self,
		refs.tabs.manage.Activated:Connect(function()
			if not store:get().isManageAllowed then
				return
			end
			self:switchTab("manage")
			if self._onTabSelected then
				self._onTabSelected("manage")
			end
		end)
	)
	trackConnection(
		self,
		refs.tabs.dj.Activated:Connect(function()
			if not store:get().isManageAllowed then
				return
			end
			self:switchTab("dj")
			if self._onTabSelected then
				self._onTabSelected("dj")
			end
		end)
	)

	-- Vote skip
	trackConnection(
		self,
		refs.voteSkipButton.Activated:Connect(function()
			if self._onVoteSkip then
				self._onVoteSkip("skip")
			end
		end)
	)

	trackConnection(
		self,
		refs.scrollableQueue:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			self:_updateQueueHeaderVisibility()
		end)
	)
	trackUnsubscriber(
		self,
		ScrollIndicatorHelper.attach(refs.scrollableQueue, {
			fadeoutDelay = QUEUE_SCROLLBAR_IDLE_DELAY,
		}).destroy
	)

	-- Scrollbar idle-color: dim bar when not scrolling
	do
		local PLAYLIST_IDLE = Color3.fromHex("181818")
		local PLAYLIST_ACTIVE = Color3.fromHex("555555")
		local TRACK_IDLE = Color3.fromHex("111111")
		local TRACK_ACTIVE = Color3.fromHex("444444")
		local IDLE_DELAY = 1 -- seconds of no scroll before dimming

		local function bindScrollIdle(scroll: ScrollingFrame, idleColor: Color3, activeColor: Color3)
			scroll.ScrollBarImageColor3 = idleColor
			local debounce: thread? = nil
			trackConnection(
				self,
				scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
					scroll.ScrollBarImageColor3 = activeColor
					if debounce then
						task.cancel(debounce)
					end
					debounce = task.delay(IDLE_DELAY, function()
						debounce = nil
						scroll.ScrollBarImageColor3 = idleColor
					end)
				end)
			)
		end

		bindScrollIdle(refs.scrollablePlaylist, PLAYLIST_IDLE, PLAYLIST_ACTIVE)
		bindScrollIdle(refs.scrollableTrackLeft, TRACK_IDLE, TRACK_ACTIVE)
		bindScrollIdle(refs.scrollableTrackRight, TRACK_IDLE, TRACK_ACTIVE)
	end

	-- Search box
	trackConnection(
		self,
		refs.searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			local q = refs.searchBox.Text
			store:set({ searchQuery = q })
			if self._onSearchChanged then
				self._onSearchChanged(q)
			end
		end)
	)

	do
		local managePlaylistSearch = refs.scrollableManagePlaylist:FindFirstChild("SearchPlaylist", true)
		if managePlaylistSearch and managePlaylistSearch:IsA("TextBox") then
			trackConnection(
				self,
				(managePlaylistSearch :: TextBox):GetPropertyChangedSignal("Text"):Connect(function()
					local q = (managePlaylistSearch :: TextBox).Text
					store:set({ managePlaylistSearchQuery = q })
					self:renderManagePlaylists(store:get().playlists or {}, q)
				end)
			)
		end

		local manageTrackSearch = refs.scrollableManageTrack:FindFirstChild("SearTrack", true)
			or refs.scrollableManageTrack:FindFirstChild("SearchTrack", true)
			or refs.scrollableManageTrack:FindFirstChild("SearchTracks", true)
		if manageTrackSearch and manageTrackSearch:IsA("TextBox") then
			trackConnection(
				self,
				(manageTrackSearch :: TextBox):GetPropertyChangedSignal("Text"):Connect(function()
					local q = (manageTrackSearch :: TextBox).Text
					store:set({ manageTrackSearchQuery = q })
					self:renderManageTracks(store:get().manageTracks or store:get().tracks or {}, q)
				end)
			)
		end
	end

	trackConnection(
		self,
		refs.favoritesPlaylistButton.Activated:Connect(function()
			local favoritesPlaylistId = select(1, getSpecialPlaylistIds(self._config))
			if self._onPlaylistSelected then
				self._onPlaylistSelected(favoritesPlaylistId)
			end
		end)
	)

	trackConnection(
		self,
		refs.newDropsPlaylistButton.Activated:Connect(function()
			local _, newDropsPlaylistId = getSpecialPlaylistIds(self._config)
			if self._onPlaylistSelected then
				self._onPlaylistSelected(newDropsPlaylistId)
			end
		end)
	)

	-- Manage frame buttons
	trackConnection(
		self,
		refs.createPlaylistButton.Activated:Connect(function()
			local state = store:get()
			if state.isLoading then
				return
			end
			local isCreatePlaylistOpen = state.manageSubView == "edit_playlist"
				and self._playlistFormCreateMode
				and state.editingPlaylist == nil

			if isCreatePlaylistOpen then
				self:_enterManageIdle(false)
				return
			end

			if self._onManageSubView then
				self._onManageSubView("edit_playlist", nil)
			else
				self:populatePlaylistForm(nil)
				self:setManageSubView("edit_playlist")
			end
		end)
	)

	trackConnection(
		self,
		refs.uploadTrackButton.Activated:Connect(function()
			local state = store:get()
			if state.isLoading then
				return
			end
			local isCreateTrackOpen = state.manageSubView == "edit_track"
				and self._trackFormCreateMode
				and state.editingTrack == nil

			if isCreateTrackOpen then
				self:_enterManageIdle(false)
				return
			end

			if self._onManageSubView then
				self._onManageSubView("edit_track", nil)
			else
				self:populateTrackForm(nil)
				self:setManageSubView("edit_track")
			end
		end)
	)

	-- Bind cover and font customization
	self:bindCoverTabs()
	self:bindColorSelection()
	self:bindFontSelection()
	self:bindPlaylistVisibility()
	self:bindRequestFromId()

	-- Bind playlist name input for preview
	local playlistNameField = refs.formPlaylistNameField
	local playlistNameBox = playlistNameField:FindFirstChildWhichIsA("TextBox")
	if playlistNameBox then
		trackConnection(
			self,
			(playlistNameBox :: TextBox):GetPropertyChangedSignal("Text"):Connect(function()
				local name = (playlistNameBox :: TextBox).Text
				store:set({ playlistNamePreview = name })
			end)
		)
	end

	-- Save playlist button
	local savePlaylistBtn = refs.formPlaylist:FindFirstChild("ActionableWrapper")
	if savePlaylistBtn then
		local btn = savePlaylistBtn:FindFirstChild("CreateorSavePlaylistButton")
		if btn and btn:IsA("TextButton") then
			trackConnection(
				self,
				(btn :: TextButton).Activated:Connect(function()
					if store:get().isLoading then
						return
					end
					if self._onManagePlaylist then
						local formData = self:readPlaylistForm()
						local valid, err = self:validatePlaylistForm(formData)
						if not valid then
							warn("[MusicPlayer] Validation failed: " .. err)
							return
						end
						local state = store:get()
						local editingPlaylist = if self._playlistFormCreateMode then nil else state.editingPlaylist
						local action = editingPlaylist and "update" or "create"
						if action == "update" then
							formData.id = editingPlaylist.id
							self:_openUpdatePlaylistConfirmation(editingPlaylist, formData)
						else
							self:_openCreatePlaylistConfirmation(formData)
						end
					end
				end)
			)
		end
	end

	-- Save track button
	local saveTrackBtn = refs.formTrack:FindFirstChild("ActionableWrapper")
	if saveTrackBtn then
		local btn = saveTrackBtn:FindFirstChild("UploadorSaveTrackButton")
		if btn and btn:IsA("TextButton") then
			trackConnection(
				self,
				(btn :: TextButton).Activated:Connect(function()
					if store:get().isLoading then
						return
					end
					if not self._onManageTrack then
						return
					end

					local formData = self:readTrackForm()
					local valid, err = self:validateTrackForm(formData)
					if not valid then
						warn("[MusicPlayer] Validation failed: " .. err)
						if self._onFormNotify then
							self._onFormNotify("warning", "Validation failed", err)
						end
						return
					end

					local state = store:get()
					local editingTrack = if self._trackFormCreateMode then nil else state.editingTrack
					local action = editingTrack and "update" or "upload"

					-- Async audio asset validation before proceeding
					store:set({ isLoading = true })
					task.spawn(function()
						local allReady = true
						local failedPartIndex: number? = nil
						local failedStatus: string? = nil

						for i, partId in ipairs(formData.parts) do
							local contentId = "rbxassetid://" .. tostring(partId)
							local sound = Instance.new("Sound")
							sound.SoundId = contentId
							pcall(function()
								ContentProvider:PreloadAsync({ sound })
							end)
							local status = ContentProvider:GetAssetFetchStatus(contentId)
							sound:Destroy()
							if status ~= Enum.AssetFetchStatus.Success then
								allReady = false
								failedPartIndex = i
								failedStatus = tostring(status and status.Name or "Unknown")
								break
							end
						end

						store:set({ isLoading = false })

						if not allReady then
							local title = if failedStatus == "TimedOut"
								then "Audio check timed out"
								else "Audio not ready"
							local desc = if failedStatus == "TimedOut"
								then "Roblox took too long to respond. This may be a temporary CDN issue. Please try again."
								else ("Roblox can't serve audio part %d yet. It may still be under review or the ID is invalid. Please try again in a few minutes."):format(failedPartIndex or 1)
							if self._onFormNotify then
								self._onFormNotify("warning", title, desc)
							end
							return
						end

						-- All parts valid, proceed
						if action == "update" then
							formData.id = editingTrack.id
							self:_openUpdateTrackConfirmation(editingTrack, formData)
						else
							self:_openCreateTrackConfirmation(formData)
						end
					end)
				end)
			)
		end
	end

	-- Cancel playlist form (CloseModalButton in header, or CancelButton in ActionableWrapper)
	do
		local btn = refs.formPlaylist:FindFirstChild("CloseModalButton", true)
			or (
				refs.formPlaylist:FindFirstChild("ActionableWrapper")
				and refs.formPlaylist:FindFirstChild("ActionableWrapper"):FindFirstChild("CancelButton")
			)
		if btn and btn:IsA("TextButton") or (btn and btn:IsA("ImageButton")) then
			trackConnection(
				self,
				(btn :: GuiButton).Activated:Connect(function()
					if store:get().isLoading then
						return
					end
					self:_enterManageIdle(false)
				end)
			)
		end
	end

	-- Cancel track form (CloseModalButton in header, or CancelButton in ActionableWrapper)
	do
		local btn = refs.formTrack:FindFirstChild("CloseModalButton", true)
			or (
				refs.formTrack:FindFirstChild("ActionableWrapper")
				and refs.formTrack:FindFirstChild("ActionableWrapper"):FindFirstChild("CancelButton")
			)
		if btn and (btn:IsA("TextButton") or btn:IsA("ImageButton")) then
			trackConnection(
				self,
				(btn :: GuiButton).Activated:Connect(function()
					if store:get().isLoading then
						return
					end
					self:_enterManageIdle(false)
				end)
			)
		end
	end

	-- Loading state subscription
	trackUnsubscriber(
		self,
		store:subscribe("isLoading", function(isLoading)
			-- Disable buttons saat loading
			refs.createPlaylistButton.Interactable = not isLoading
			refs.uploadTrackButton.Interactable = not isLoading
			setActionWrapperButtonsInteractable(refs.formPlaylist, "CreateorSavePlaylistButton", not isLoading)
			setActionWrapperButtonsInteractable(refs.formTrack, "UploadorSaveTrackButton", not isLoading)
		end)
	)
	trackUnsubscriber(
		self,
		store:subscribe("currentTrack", function(track)
			self:updateTrackDisplay(if type(track) == "table" then track else nil)
			self:_updateNowPlayingFavoriteState(track)
		end)
	)
	trackUnsubscriber(
		self,
		store:subscribe("favoriteTrackIds", function()
			self:_updateNowPlayingFavoriteState(store:get().currentTrack)
		end)
	)

	-- DJ mode gating: saat DJ mode ON, privileged users (Admin/DJ/Owner) tetap bisa akses.
	-- Regular player di-block.
	local function updateDjModeGating()
		local storeState = store:get()
		local localUserId = Players.LocalPlayer and Players.LocalPlayer.UserId
		local isDjOwner = storeState.isDjMode == true
			and type(localUserId) == "number"
			and storeState.djOwnerUserId == localUserId
		local canControl = isDjOwner or storeState.isManageAllowed == true
		local shouldHide = storeState.isDjMode == true and not canControl
		refs.voteSkipButton.Visible = not shouldHide
		refs.tabs.reqSong.Visible = not shouldHide
		SliderSelectorUtil.setTabButtonDimmed(refs.tabs.reqSong, shouldHide)
		if shouldHide and storeState.activeTab == "request" then
			self:switchTab("nowplaying")
		else
			self:_updateTabButtonVisuals(store:get().activeTab or "nowplaying")
		end
	end
	trackUnsubscriber(
		self,
		store:subscribe("isDjMode", function()
			updateDjModeGating()
		end)
	)
	trackUnsubscriber(
		self,
		store:subscribe("djOwnerUserId", function()
			updateDjModeGating()
		end)
	)
	trackUnsubscriber(
		self,
		store:subscribe("isManageAllowed", function()
			updateDjModeGating()
		end)
	)

	-- DraggableIcon: no custom logic, UIDragDetector already handles MainWrapper

	-- ManageAllowed: disable tab secara visual (data di-push dari controller via store subscribe)
	-- Manage tab: saat DJ mode ON, privileged users (DJ owner / Admin / Owner) tetap bisa akses.
	local function updateManageTab(allowed: boolean)
		local storeState = store:get()
		local localUserId = Players.LocalPlayer and Players.LocalPlayer.UserId
		local isDjOwner = storeState.isDjMode == true
			and type(localUserId) == "number"
			and storeState.djOwnerUserId == localUserId
		local canControl = isDjOwner or allowed
		local visible = if storeState.isDjMode then canControl else allowed
		refs.tabs.manage.Visible = visible
		SliderSelectorUtil.setTabButtonDimmed(refs.tabs.manage, not visible)
		if not visible and store:get().activeTab == "manage" then
			self:switchTab("nowplaying")
		else
			self:_updateTabButtonVisuals(store:get().activeTab or "nowplaying")
		end
	end
	local function updateDjTabAccess(allowed: boolean)
		local storeState = store:get()
		local localUserId = Players.LocalPlayer and Players.LocalPlayer.UserId
		local isDjOwner = storeState.isDjMode == true
			and type(localUserId) == "number"
			and storeState.djOwnerUserId == localUserId
		local canControl = isDjOwner or allowed
		local visible = if storeState.isDjMode then canControl else allowed
		refs.tabs.dj.Visible = visible
		SliderSelectorUtil.setTabButtonDimmed(refs.tabs.dj, not visible)
		if not visible and store:get().activeTab == "dj" then
			self:switchTab("nowplaying")
		else
			self:_updateTabButtonVisuals(store:get().activeTab or "nowplaying")
		end
	end
	local function updateDjTabState(enabled: boolean)
		setButtonDisplayText(refs.tabs.dj, "DJ")
		setSwitchToggleVisual(self._djModeToggle, enabled == true)
		task.defer(setSwitchToggleVisual, self._djModeToggle, enabled == true)
	end
	self._onUpdateManageTab = updateManageTab
	self._onUpdateDjTabAccess = updateDjTabAccess
	self._onUpdateDjTabState = updateDjTabState
	updateManageTab(false) -- default disabled sampai controller push data
	updateDjTabAccess(false)
	updateDjTabState(self._store:get().isDjMode == true)
	updateDjModeGating()
	self:bindDjTab()
	self:_updateQueueHeaderVisibility()
	self:_updateTabButtonVisuals(self._store:get().activeTab or "nowplaying")

	-- Initial state: ensure manage sections visible
	self:setManageSubView("idle")
end

-- Callback setters

function MusicPlayerUIBinder:setOnCloseRequested(fn: () -> ())
	self._onCloseRequested = fn
end

function MusicPlayerUIBinder:setOnTabSelected(fn: (string) -> ())
	self._onTabSelected = fn
end

function MusicPlayerUIBinder:setOnToggleDjMode(fn: () -> ())
	self._onToggleDjMode = fn
end

function MusicPlayerUIBinder:setOnVoteSkip(fn: (string?) -> ())
	self._onVoteSkip = fn
end

function MusicPlayerUIBinder:setOnRequestTrack(fn: (string) -> ())
	self._onRequestTrack = fn
end

function MusicPlayerUIBinder:setOnAddFavoriteTrack(fn: (string, boolean) -> ())
	self._onAddFavoriteTrack = fn
end

function MusicPlayerUIBinder:setOnPlaylistSelected(fn: (string) -> ())
	self._onPlaylistSelected = fn
end

function MusicPlayerUIBinder:setOnSearchChanged(fn: (string) -> ())
	self._onSearchChanged = fn
end

function MusicPlayerUIBinder:setOnVolumeChanged(fn: (number) -> ())
	self._onVolumeChanged = fn
end

function MusicPlayerUIBinder:setOnManageSubView(fn: (string, any?) -> ())
	self._onManageSubView = fn
end

function MusicPlayerUIBinder:setOnManagePlaylist(fn: (string, { [string]: any }) -> ())
	self._onManagePlaylist = fn
end

function MusicPlayerUIBinder:setOnResolveRequestAsset(fn: (string) -> ())
	self._onResolveRequestAsset = fn
end

function MusicPlayerUIBinder:setOnManageTrack(fn: (string, { [string]: any }) -> ())
	self._onManageTrack = fn
end

function MusicPlayerUIBinder:setOnFormNotify(fn: (string, string, string?) -> ())
	self._onFormNotify = fn
end

function MusicPlayerUIBinder:setOnDjSoundboardTriggered(fn: (string) -> boolean)
	self._onDjSoundboardTriggered = fn
end

function MusicPlayerUIBinder:setOnDjPlaybackSpeedChanged(fn: (number) -> boolean)
	self._onDjPlaybackSpeedChanged = fn
end

function MusicPlayerUIBinder:setOnDjEffectEnabledChanged(fn: (string, boolean) -> boolean)
	self._onDjEffectEnabledChanged = fn
end

function MusicPlayerUIBinder:setOnDjEffectValueChanged(fn: (string, string, number) -> boolean)
	self._onDjEffectValueChanged = fn
end

function MusicPlayerUIBinder:setOnDjBassEnabledChanged(fn: (boolean) -> ())
	self._onDjBassEnabledChanged = fn
	self._onDjEffectEnabledChanged = function(effectId, enabled)
		if effectId == "equalizer" then
			return fn(enabled) == true
		end
		return true
	end
end

function MusicPlayerUIBinder:setOnDjBassValueChanged(fn: (number) -> ())
	self._onDjBassValueChanged = fn
	self._onDjEffectValueChanged = function(effectId, itemId, value)
		if effectId == "equalizer" and itemId == "low" then
			fn(value)
			return true
		end
		return true
	end
end

function MusicPlayerUIBinder:setOnDjResetRequested(fn: () -> boolean)
	self._onDjResetRequested = fn
end

function MusicPlayerUIBinder:setManageAllowed(allowed: boolean)
	if self._onUpdateManageTab then
		self._onUpdateManageTab(allowed)
	end
	if self._onUpdateDjTabAccess then
		self._onUpdateDjTabAccess(allowed)
	end
end

function MusicPlayerUIBinder:setDjModeEnabled(enabled: boolean)
	if self._onUpdateDjTabState then
		self._onUpdateDjTabState(enabled)
	end
	-- Re-evaluate manage/DJ tab access when DJ mode toggles.
	-- setManageAllowed provides the base permission; the internal
	-- updateManageTab/updateDjTabAccess now overlay DJ-owner check.
	local storeState = self._store:get()
	self:setManageAllowed(storeState.isManageAllowed == true)
end

function MusicPlayerUIBinder:setTotalDuration(duration: number)
	self._totalDuration = duration
end

function MusicPlayerUIBinder:destroy()
	self._isDestroyed = true
	cancelAllListRenderJobs(self)
	disconnectAllVirtualLists(self)
	self:_stopTipsLoop()
	if self._auraHeartbeatConn then
		self._auraHeartbeatConn:Disconnect()
		self._auraHeartbeatConn = nil
	end
	if self._auraGradientTween then
		self._auraGradientTween:Cancel()
		self._auraGradientTween = nil
	end
	if self._auraGradientConn then
		self._auraGradientConn:Disconnect()
		self._auraGradientConn = nil
	end
	for index = 1, #self._auraSoundCache do
		self._auraSoundCache[index] = nil
	end
	self._auraSoundScanClock = 0
	if self._playlistIconBounceCleanup then
		for _, entry in ipairs(self._playlistIconBounceCleanup) do
			entry.kill()
			for _, t in ipairs(entry.tweens) do
				t:Cancel()
			end
			for _, c in ipairs(entry.conns) do
				c:Disconnect()
			end
		end
		self._playlistIconBounceCleanup = nil
	end
	self:closeAddToQueueConfirmation(true)
	self:closeVoteModal(true)
	self:closePlaylistRelatedModal(true)
	self:closeTrackRelatedModal(true)
	self:stopProgressTracking()
	if self._refs.mainDragDetector and self._mainWrapperDragDetectorEnabled ~= nil then
		self._refs.mainDragDetector.Enabled = self._mainWrapperDragDetectorEnabled
	end
	if self._volumeDragConn then
		self._volumeDragConn:Disconnect()
		self._volumeDragConn = nil
	end
	disconnectConnectionList(self._djSoundBoardConnections)
	disconnectConnectionList(self._djEffectConnections)
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	self._connections = {}
	for _, unsubscribe in ipairs(self._unsubscribers) do
		unsubscribe()
	end
	self._unsubscribers = {}
	destroyPooledRows(self._queueRowPool)
	destroyPooledRows(self._requestPlaylistRowPool)
	destroyPooledRows(self._requestTrackLeftRowPool)
	destroyPooledRows(self._requestTrackRightRowPool)
	destroyPooledRows(self._managePlaylistRowPool)
	destroyPooledRows(self._manageTrackRowPool)
	destroyPooledRows(self._manageTrackRightRowPool)
end

return MusicPlayerUIBinder
