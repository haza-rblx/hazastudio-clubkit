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

-- Fixed single-line title for virtualized rows (uniform rowStride; no TextBounds thrash).
local function applyVirtualTrackTitle(label: TextLabel, text: string)
	label.Text = text
	label.TextWrapped = false
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.AutomaticSize = Enum.AutomaticSize.None
	local lineH = math.max(1, label.TextSize)
	label.Size = UDim2.new(label.Size.X.Scale, label.Size.X.Offset, 0, lineH + 4)
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
	boundItemId: string?,
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
type VirtualListRuntime = {
	renderedById: { [string]: PooledRow },
	freeRows: { PooledRow },
	dirty: boolean,
	flushConn: RBXScriptConnection?,
	lastStart: number,
	lastEnd: number,
	lastWindowH: number,
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
local LIST_COVER_THUMB_SIZE = 150
local SEARCH_DEBOUNCE_SEC = 0.18
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

-- List cells: always prefer small Asset rbxthumb (covers legacy 420 + raw rbxassetid).
local function normalizeListCoverUri(coverValue: any): string?
	local text = getImageCoverKey(coverValue)
	if not text then
		return nil
	end

	local assetId = text:match("rbxthumb://type=Asset&id=(%d+)")
		or text:match("rbxassetid://(%d+)")
		or text:match("id=(%d+)")
		or text:match("^(%d+)$")
		or text:match("(%d+)")
	if assetId then
		return ("rbxthumb://type=Asset&id=%s&w=%d&h=%d"):format(
			assetId,
			LIST_COVER_THUMB_SIZE,
			LIST_COVER_THUMB_SIZE
		)
	end

	return getImageCoverUri(coverValue)
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
	self._virtualListRuntimes = {} :: { [string]: VirtualListRuntime }
	self._specialPlaylistBounceActive = false
	self._searchDebounceToken = 0
	self._managePlaylistSearchToken = 0
	self._manageTrackSearchToken = 0
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

local function getVirtualItemId(item: any, index: number): string
	if type(item) == "table" then
		local id = item.id
		if id ~= nil then
			local asString = tostring(id)
			if asString ~= "" then
				return asString
			end
		end
	end
	return "__i" .. tostring(index)
end

local function releaseVirtualRow(runtime: VirtualListRuntime, row: PooledRow)
	disconnectPooledRowConnections(row)
	row.boundItemId = nil
	row.instance.Visible = false
	table.insert(runtime.freeRows, row)
end

local function acquireVirtualRow(
	runtime: VirtualListRuntime,
	pool: { PooledRow },
	template: GuiObject,
	parent: Instance
): PooledRow
	local free = runtime.freeRows
	if #free > 0 then
		local row = table.remove(free) :: PooledRow
		if row.instance.Parent ~= parent then
			row.instance.Parent = parent
		end
		return row
	end
	return ensurePooledRow(pool, #pool + 1, template, parent)
end

local function clearVirtualListRuntime(self: any, key: string)
	local runtime = self._virtualListRuntimes[key] :: VirtualListRuntime?
	if not runtime then
		return
	end
	if runtime.flushConn then
		runtime.flushConn:Disconnect()
		runtime.flushConn = nil
	end
	for _, row in pairs(runtime.renderedById) do
		disconnectPooledRowConnections(row)
		row.boundItemId = nil
		row.instance.Visible = false
	end
	table.clear(runtime.renderedById)
	table.clear(runtime.freeRows)
	self._virtualListRuntimes[key] = nil
end

local function disconnectVirtualList(self: any, key: string)
	clearVirtualListRuntime(self, key)

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
	local keys = {}
	for key in pairs(self._virtualListRuntimes) do
		table.insert(keys, key)
	end
	for key in pairs(self._virtualListConnections) do
		if self._virtualListRuntimes[key] == nil then
			table.insert(keys, key)
		end
	end
	for _, key in ipairs(keys) do
		disconnectVirtualList(self, key)
	end
	table.clear(self._virtualListConnections)
	table.clear(self._virtualListRuntimes)
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

	local freeRows: { PooledRow } = {}
	for _, row in ipairs(options.pool) do
		row.boundItemId = nil
		row.instance.Visible = false
		table.insert(freeRows, row)
	end

	local runtime: VirtualListRuntime = {
		renderedById = {},
		freeRows = freeRows,
		dirty = false,
		flushConn = nil,
		lastStart = 0,
		lastEnd = 0,
		lastWindowH = -1,
	}
	self._virtualListRuntimes[options.key] = runtime

	local function redrawNow()
		if self._virtualListRuntimes[options.key] ~= runtime then
			return
		end

		if totalRows <= 0 then
			setSpacerHeight(topSpacer, 0)
			setSpacerHeight(bottomSpacer, 0)
			for id, row in pairs(runtime.renderedById) do
				releaseVirtualRow(runtime, row)
				runtime.renderedById[id] = nil
			end
			runtime.lastStart = 0
			runtime.lastEnd = 0
			runtime.lastWindowH = scroll.AbsoluteWindowSize.Y
			return
		end

		local viewportRows = math.max(1, math.ceil(scroll.AbsoluteWindowSize.Y / rowStride))
		local renderRows = math.min(totalRows, maxRows, viewportRows + bufferRows * 2)
		local firstVisible = math.floor(math.max(0, scroll.CanvasPosition.Y) / rowStride) + 1
		local startIndex = math.clamp(firstVisible - bufferRows, 1, math.max(1, totalRows - renderRows + 1))
		local endIndex = math.min(totalRows, startIndex + renderRows - 1)
		local windowH = scroll.AbsoluteWindowSize.Y

		if
			startIndex == runtime.lastStart
			and endIndex == runtime.lastEnd
			and windowH == runtime.lastWindowH
			and next(runtime.renderedById) ~= nil
		then
			return
		end

		setSpacerHeight(topSpacer, (startIndex - 1) * rowStride)
		setSpacerHeight(bottomSpacer, (totalRows - endIndex) * rowStride)

		local nextIds: { [string]: boolean } = {}
		local nextEntries: { { id: string, itemIndex: number, item: any } } = {}
		for itemIndex = startIndex, endIndex do
			local item = items[itemIndex]
			local id = getVirtualItemId(item, itemIndex)
			nextIds[id] = true
			table.insert(nextEntries, {
				id = id,
				itemIndex = itemIndex,
				item = item,
			})
		end

		for id, row in pairs(runtime.renderedById) do
			if not nextIds[id] then
				releaseVirtualRow(runtime, row)
				runtime.renderedById[id] = nil
			end
		end

		for _, entry in ipairs(nextEntries) do
			local layoutOrder = VIRTUAL_ROW_LAYOUT_BASE + entry.itemIndex
			local existing = runtime.renderedById[entry.id]
			if existing and existing.boundItemId == entry.id then
				if existing.instance.LayoutOrder ~= layoutOrder then
					existing.instance.LayoutOrder = layoutOrder
				end
				if not existing.instance.Visible then
					existing.instance.Visible = true
				end
			else
				local row = existing or acquireVirtualRow(runtime, options.pool, options.template, parent)
				runtime.renderedById[entry.id] = row
				disconnectPooledRowConnections(row)
				row.boundItemId = entry.id
				row.instance.LayoutOrder = layoutOrder
				options.renderRow(row, entry.item, entry.itemIndex)
				row.instance.Visible = true
			end
		end

		runtime.lastStart = startIndex
		runtime.lastEnd = endIndex
		runtime.lastWindowH = windowH
	end

	local function markDirty()
		runtime.dirty = true
	end

	local function flush()
		if not runtime.dirty then
			return
		end
		if self._virtualListRuntimes[options.key] ~= runtime then
			return
		end
		runtime.dirty = false
		redrawNow()
	end

	redrawNow()
	runtime.flushConn = RunService.Heartbeat:Connect(flush)
	self._virtualListConnections[options.key] = {
		scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(markDirty),
		scroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(markDirty),
	}
	markDirty()
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
	self._specialPlaylistBounceActive = false
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


-- Late method definitions live in a sibling ModuleScript to stay below Roblox Source limits.
local applyPart2 = require(script.Parent.MusicPlayerUIBinderPart2)
applyPart2(MusicPlayerUIBinder, {
	ContentProvider = ContentProvider,
	TweenService = TweenService,
	Players = Players,
	Workspace = Workspace,
	scheduleTrackTitleHeight = scheduleTrackTitleHeight,
	applyVirtualTrackTitle = applyVirtualTrackTitle,
	ScrollIndicatorHelper = ScrollIndicatorHelper,
	SliderSelectorUtil = SliderSelectorUtil,
	Config = Config,
	FADE_INFO_FAST = FADE_INFO_FAST,
	PLAYLIST_RELATED_CAMERA_FOV_DELTA = PLAYLIST_RELATED_CAMERA_FOV_DELTA,
	REQUEST_PLAYLIST_USER_LAYOUT_BASE = REQUEST_PLAYLIST_USER_LAYOUT_BASE,
	VIRTUAL_ROW_LAYOUT_BASE = VIRTUAL_ROW_LAYOUT_BASE,
	QUEUE_SCROLLBAR_IDLE_DELAY = QUEUE_SCROLLBAR_IDLE_DELAY,
	getMonthDropsLabel = getMonthDropsLabel,
	getCoverGradientRotation = getCoverGradientRotation,
	buildCoverGradientColorSequence = buildCoverGradientColorSequence,
	getImageCoverKey = getImageCoverKey,
	getImageCoverUri = getImageCoverUri,
	normalizeListCoverUri = normalizeListCoverUri,
	LIST_COVER_THUMB_SIZE = LIST_COVER_THUMB_SIZE,
	SEARCH_DEBOUNCE_SEC = SEARCH_DEBOUNCE_SEC,
	resolveCoverSourceForTrack = resolveCoverSourceForTrack,
	sampleImageCoverDarkestColor = sampleImageCoverDarkestColor,
	getPlaylistCoverAccentColor = getPlaylistCoverAccentColor,
	PLAYLIST_FORM_COPY = PLAYLIST_FORM_COPY,
	TRACK_FORM_COPY = TRACK_FORM_COPY,
	ensureUIScale = ensureUIScale,
	stashTemplateInstance = stashTemplateInstance,
	_clearListClones = _clearListClones,
	disconnectPooledRowConnections = disconnectPooledRowConnections,
	disconnectConnectionList = disconnectConnectionList,
	ensurePooledRow = ensurePooledRow,
	hideUnusedPooledRows = hideUnusedPooledRows,
	destroyPooledRows = destroyPooledRows,
	startListRenderJob = startListRenderJob,
	cancelAllListRenderJobs = cancelAllListRenderJobs,
	disconnectVirtualList = disconnectVirtualList,
	disconnectAllVirtualLists = disconnectAllVirtualLists,
	renderVirtualList = renderVirtualList,
	animateListRowIn = animateListRowIn,
	hideIfGuiObject = hideIfGuiObject,
	trackConnection = trackConnection,
	trackUnsubscriber = trackUnsubscriber,
	bindClickable = bindClickable,
	bindTrackedClickable = bindTrackedClickable,
	isManageInteractionBlocked = isManageInteractionBlocked,
	findFirstByNames = findFirstByNames,
	forEachDirectChildByName = forEachDirectChildByName,
	findCoverTextLabel = findCoverTextLabel,
	getPlaylistTrackCount = getPlaylistTrackCount,
	formatTrackCount = formatTrackCount,
	setTextLabelByNames = setTextLabelByNames,
	applyNamedFont = applyNamedFont,
	setTextDisplay = setTextDisplay,
	setButtonDisplayText = setButtonDisplayText,
	setSwitchToggleVisual = setSwitchToggleVisual,
	bindSwitchToggleClick = bindSwitchToggleClick,
	formatDjSpeedText = formatDjSpeedText,
	formatDjEffectValueText = formatDjEffectValueText,
	djEffectSliderKey = djEffectSliderKey,
	bindDjSlider = bindDjSlider,
	getActionWrapper = getActionWrapper,
	hasMultipleDirectChildrenNamed = hasMultipleDirectChildrenNamed,
	setActionWrapperButtonsInteractable = setActionWrapperButtonsInteractable,
	getFormTitleDisplay = getFormTitleDisplay,
	getFormHelperDisplay = getFormHelperDisplay,
	getTextInput = getTextInput,
	setTextInput = setTextInput,
	resetRequestTrackFeedback = resetRequestTrackFeedback,
	buildOrderedPlaylistEntries = buildOrderedPlaylistEntries,
	buildOrderedTrackEntries = buildOrderedTrackEntries,
	formatClock = formatClock,
	getSpecialPlaylistIds = getSpecialPlaylistIds,
	applyPlaylistRowState = applyPlaylistRowState,
	capturePlaylistRowState = capturePlaylistRowState,
	restorePlaylistRowState = restorePlaylistRowState,
	setAllChildGradientsEnabled = setAllChildGradientsEnabled,
	findIndicatorFrame = findIndicatorFrame,
	copySelectionTemplateVisual = copySelectionTemplateVisual,
	getPanelBlurSize = getPanelBlurSize,
	getModalBackdropTransparency = getModalBackdropTransparency,
	playModalBlur = playModalBlur,
})

return MusicPlayerUIBinder
