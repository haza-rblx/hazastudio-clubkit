--!strict
-- PATH: StarterPlayerScripts/Client/UI/Music/Visuals.luau
-- Idempotent setters shared by the v3 music views. Every call compares before writing: the
-- server re-sends full state and most syncs change nothing on screen.

local Players = game:GetService("Players")

local Cover = require(script.Parent.Parent.MusicPlayerCoverHelpers)
local CoverTile = require(script.Parent.CoverTile)

local Visuals = {}

-- Weak on purpose (ADR 0011 addendum, 2026-09-17): a pure cache of the cover key last applied per
-- image. A lost entry only costs one redundant re-apply of the same cover, never a wrong picture.
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

-- A cover slot is dressed for the plain gradient cover: an opaque white background (the gradient
-- tints it), and in the Library a 10 px mat, a grey stroke, and the playlist's name + icon drawn
-- over it. When the slot shows a drawn cover or an image instead, that dressing only leaves white
-- corners and a white frame around it (owner, 2026-09-23), so it steps aside — background clear,
-- stroke off, padding 0 — and comes back the moment the slot shows a gradient again. The name and
-- icon overlays also step aside for a drawn list card, which carries its own text. The previous
-- values ride on the objects as attributes, so pooled rows restore exactly what the template had.
local COVER_MODE = "HzCoverMode"

local function clearBackground(object: GuiObject)
	if object:GetAttribute("HzCoverBackground") == nil then
		object:SetAttribute("HzCoverBackground", object.BackgroundTransparency)
	end
	object.BackgroundTransparency = 1
end

local function restoreBackground(object: GuiObject)
	local saved = object:GetAttribute("HzCoverBackground")
	if type(saved) == "number" then
		object.BackgroundTransparency = saved
	end
	object:SetAttribute("HzCoverBackground", nil)
end

local function setOverlaysHidden(host: GuiObject, tile: Instance?, image: Instance, hidden: boolean)
	for _, child in host:GetChildren() do
		if child == tile or child == image or not (child:IsA("TextLabel") or child:IsA("ImageLabel")) then
			continue
		end
		if hidden and child:GetAttribute("HzCoverVisible") == nil then
			child:SetAttribute("HzCoverVisible", child.Visible)
			child.Visible = false
		elseif not hidden and child:GetAttribute("HzCoverVisible") ~= nil then
			child.Visible = child:GetAttribute("HzCoverVisible") == true
			child:SetAttribute("HzCoverVisible", nil)
		end
	end
end

local function enterCoverMode(host: GuiObject, image: ImageLabel, hideOverlays: boolean)
	if not host:GetAttribute(COVER_MODE) then
		host:SetAttribute(COVER_MODE, true)
		clearBackground(host)
		for _, child in host:GetChildren() do
			if child:IsA("UIStroke") then
				child:SetAttribute("HzCoverEnabled", child.Enabled)
				child.Enabled = false
			elseif child:IsA("UIPadding") then
				child:SetAttribute("HzCoverLeft", child.PaddingLeft)
				child:SetAttribute("HzCoverRight", child.PaddingRight)
				child:SetAttribute("HzCoverTop", child.PaddingTop)
				child:SetAttribute("HzCoverBottom", child.PaddingBottom)
				child.PaddingLeft, child.PaddingRight, child.PaddingTop, child.PaddingBottom = UDim.new(), UDim.new(), UDim.new(), UDim.new()
			end
		end
	end
	if image ~= host then
		clearBackground(image)
	end
	setOverlaysHidden(host, host:FindFirstChild("HzCoverTile"), image, hideOverlays)
end

local function exitCoverMode(host: GuiObject, image: ImageLabel)
	if image ~= host then
		restoreBackground(image)
	end
	if not host:GetAttribute(COVER_MODE) then
		return
	end
	host:SetAttribute(COVER_MODE, nil)
	restoreBackground(host)
	for _, child in host:GetChildren() do
		if child:IsA("UIStroke") and child:GetAttribute("HzCoverEnabled") ~= nil then
			child.Enabled = child:GetAttribute("HzCoverEnabled") == true
			child:SetAttribute("HzCoverEnabled", nil)
		elseif child:IsA("UIPadding") and child:GetAttribute("HzCoverLeft") ~= nil then
			child.PaddingLeft = child:GetAttribute("HzCoverLeft") :: UDim
			child.PaddingRight = child:GetAttribute("HzCoverRight") :: UDim
			child.PaddingTop = child:GetAttribute("HzCoverTop") :: UDim
			child.PaddingBottom = child:GetAttribute("HzCoverBottom") :: UDim
			for _, name in { "HzCoverLeft", "HzCoverRight", "HzCoverTop", "HzCoverBottom" } do
				child:SetAttribute(name, nil)
			end
		end
	end
	setOverlaysHidden(host, nil, image, false)
end

-- Hands `host` to CoverTile (ADR 0014): the element's own image and gradient step aside.
local function mountTile(image: ImageLabel, host: GuiObject, track: any, playlist: any?, config: any, opts: any)
	if coverKeys[image] ~= "tile" then
		coverKeys[image] = "tile"
		image.Image = ""
		local gradient = host:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Enabled = false
		end
		if host ~= image then
			image.Visible = false
		end
	end
	CoverTile.mount(host, track, playlist, config, opts)
	enterCoverMode(host, image, opts ~= nil and opts.listCard == true)
end

-- Cover = playlist/track art: an image asset, or a Config.Music.COVER_GRADIENTS index. A playlist
-- set to a template on the web carries `cover` and is drawn like its songs, name as headline.
-- gradientHost: the element that owns the gradient when it is not the ImageLabel itself (the
-- image is then hidden in gradient mode so the host shows through).
function Visuals.applyCover(
	image: ImageLabel,
	source: any?,
	config: any,
	opts: { gradientHost: GuiObject?, listThumb: boolean?, fullTile: boolean? }?
)
	local host: GuiObject = if opts and opts.gradientHost then opts.gradientHost else image
	local listThumb = opts ~= nil and opts.listThumb == true
	if type(source) == "table" and type(source.cover) == "table" then
		local card = { id = source.id, name = tostring(source.name or ""), creator = "", cover = source.cover }
		-- fullTile: a list card that should read as the real cover (text and layout), not only
		-- its artwork — the playlist column (owner, 2026-09-23).
		local compact = listThumb and not (opts ~= nil and opts.fullTile == true)
		mountTile(image, host, card, nil, config, { compact = compact, listCard = listThumb and not compact, small = listThumb and not compact })
		return
	end
	local coverType = if type(source) == "table" then tostring(source.coverType or "gradient") else "none"
	local coverValue = if type(source) == "table" then source.coverValue else nil
	local key = coverType .. "|" .. tostring(coverValue) .. "|" .. tostring(listThumb)
	if coverKeys[image] == key then
		return
	end
	coverKeys[image] = key
	CoverTile.unmount(host)

	local gradient = host:FindFirstChildOfClass("UIGradient")
	if coverType == "image" then
		local uri = if listThumb then Cover.normalizeListCoverUri(coverValue) else Cover.getImageCoverUri(coverValue)
		image.Image = uri or ""
		enterCoverMode(host, image, false)
		if gradient then
			gradient.Enabled = false
		end
		if host ~= image then
			image.Visible = true
		end
		return
	end

	image.Image = ""
	exitCoverMode(host, image)
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

-- A track's cover: its own image when the customer gave it one (coverType "image"); the cover the
-- kit draws when its playlist uses a template (track.cover, ADR 0014); otherwise the playlist's
-- gradient or image. compact = artwork only, for list rows.
function Visuals.applyTrackCover(
	image: ImageLabel,
	track: any?,
	playlist: any?,
	config: any,
	opts: { gradientHost: GuiObject?, listThumb: boolean?, compact: boolean?, index: number? }?
)
	if type(track) ~= "table" or track.coverType == "image" or type(track.cover) ~= "table" then
		local source = if type(track) == "table" then Cover.resolveCoverSourceForTrack(track, playlist) else nil
		Visuals.applyCover(image, source, config, opts and { gradientHost = opts.gradientHost, listThumb = opts.listThumb })
		return
	end
	local host: GuiObject = if opts and opts.gradientHost then opts.gradientHost else image
	local compact = opts ~= nil and opts.compact == true
	mountTile(image, host, track, playlist, config, {
		compact = compact,
		index = opts and opts.index,
		listCard = opts ~= nil and opts.listThumb == true and not compact,
		small = opts ~= nil and opts.listThumb == true and not compact,
	})
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
