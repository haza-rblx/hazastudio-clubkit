--!strict
-- Cover / title helpers for MusicPlayerUIBinder (register pressure offload).

local AssetService = game:GetService("AssetService")

local M = {}

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

M.setTrackTitleHeight = setTrackTitleHeight
M.scheduleTrackTitleHeight = scheduleTrackTitleHeight
M.applyVirtualTrackTitle = applyVirtualTrackTitle
M.getMonthDropsLabel = getMonthDropsLabel
M.getCoverGradientColors = getCoverGradientColors
M.getCoverGradientRotation = getCoverGradientRotation
M.buildCoverGradientColorSequence = buildCoverGradientColorSequence
M.sampleColorSequence = sampleColorSequence
M.getCoverGradientMidColor = getCoverGradientMidColor
M.getStableAccentColor = getStableAccentColor
M.getStableDarkCoverColor = getStableDarkCoverColor
M.getColorLuminance = getColorLuminance
M.getColorSaturation = getColorSaturation
M.colorFromValue = colorFromValue
M.getPlaylistCoverPaletteColors = getPlaylistCoverPaletteColors
M.getDarkestColor = getDarkestColor
M.getImageCoverKey = getImageCoverKey
M.getImageCoverUri = getImageCoverUri
M.normalizeListCoverUri = normalizeListCoverUri
M.resolveCoverSourceForTrack = resolveCoverSourceForTrack
M.sampleImageCoverDarkestColor = sampleImageCoverDarkestColor
M.getPlaylistCoverAccentColor = getPlaylistCoverAccentColor
M.LIST_COVER_THUMB_SIZE = LIST_COVER_THUMB_SIZE

return M