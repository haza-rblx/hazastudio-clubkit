--!strict
-- PATH: StarterPlayerScripts/Client/UI/Music/Visuals.luau
-- Idempotent setters shared by the v3 music views. Every call compares before writing: the
-- server re-sends full state and most syncs change nothing on screen.

local Players = game:GetService("Players")

local Cover = require(script.Parent.Parent.MusicPlayerCoverHelpers)

local Visuals = {}

local coverKeys: { [Instance]: string } = setmetatable({}, { __mode = "k" }) :: any
local headshotCache: { [string]: string } = {}

function Visuals.setText(label: TextLabel, text: string)
	if label.Text ~= text then
		label.Text = text
	end
end

function Visuals.setVisible(object: GuiObject, visible: boolean)
	if object.Visible ~= visible then
		object.Visible = visible
	end
end

function Visuals.formatClock(seconds: number): string
	local total = math.max(0, math.floor(seconds + 0.5))
	return string.format("%02d:%02d", total // 60, total % 60)
end

-- Cover = playlist/track art: an image asset, or a Config.Music.COVER_GRADIENTS index.
-- gradientHost: the element that owns the gradient when it is not the ImageLabel itself (the
-- image is then hidden in gradient mode so the host shows through).
function Visuals.applyCover(
	image: ImageLabel,
	source: any?,
	config: any,
	opts: { gradientHost: GuiObject?, listThumb: boolean? }?
)
	local host: GuiObject = if opts and opts.gradientHost then opts.gradientHost else image
	local listThumb = opts ~= nil and opts.listThumb == true
	local coverType = if type(source) == "table" then tostring(source.coverType or "gradient") else "none"
	local coverValue = if type(source) == "table" then source.coverValue else nil
	local key = coverType .. "|" .. tostring(coverValue) .. "|" .. tostring(listThumb)
	if coverKeys[image] == key then
		return
	end
	coverKeys[image] = key

	local gradient = host:FindFirstChildOfClass("UIGradient")
	if coverType == "image" then
		local uri = if listThumb then Cover.normalizeListCoverUri(coverValue) else Cover.getImageCoverUri(coverValue)
		image.Image = uri or ""
		if gradient then
			gradient.Enabled = false
		end
		if host ~= image then
			image.Visible = true
		end
		return
	end

	image.Image = ""
	if host ~= image then
		image.Visible = false
	end
	local gradients = config and config.COVER_GRADIENTS
	if type(gradients) ~= "table" or #gradients == 0 then
		return
	end
	local index = tonumber(coverValue) or 1
	if index < 1 or index > #gradients then
		index = 1
	end
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Parent = host
	end
	local spec = gradients[index]
	local target = gradient :: UIGradient
	target.Color = Cover.buildCoverGradientColorSequence(spec)
	target.Rotation = Cover.getCoverGradientRotation(spec)
	target.Enabled = true
end

function Visuals.setHeadshot(image: ImageLabel, userId: number?, size: Enum.ThumbnailSize?)
	local thumbSize = size or Enum.ThumbnailSize.Size100x100
	if type(userId) ~= "number" or userId <= 0 then
		image:SetAttribute("HeadshotKey", nil)
		if image.Image ~= "" then
			image.Image = ""
		end
		return
	end
	local key = tostring(userId) .. ":" .. thumbSize.Name
	if image:GetAttribute("HeadshotKey") == key then
		return
	end
	image:SetAttribute("HeadshotKey", key)
	local cached = headshotCache[key]
	image.Image = cached or ""
	if cached then
		return
	end
	task.spawn(function()
		local ok, uri = pcall(Players.GetUserThumbnailAsync, Players, userId, Enum.ThumbnailType.HeadShot, thumbSize)
		if not ok or type(uri) ~= "string" or uri == "" then
			return
		end
		headshotCache[key] = uri
		if image.Parent and image:GetAttribute("HeadshotKey") == key then
			image.Image = uri
		end
	end)
end

return Visuals
