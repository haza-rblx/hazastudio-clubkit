--!strict
-- PATH: StarterPlayerScripts/Client/UI/Music/SetBanner.luau
-- The banner face of a set: the solid coloured top of the Set card. SetCardView builds the active
-- card's banner from it, and a waiting set's queue row (NowPlayingView) shows the same face, so the
-- two read as one. Geometry and fonts live here; colours are painted by the caller (paint).
-- Contract: docs/plans/active-set.md.

local AccentService = require(script.Parent.Parent.Parent.Services.AccentService)
local Visuals = require(script.Parent.Visuals)

local FALLBACK_FAMILY = "rbxasset://fonts/families/GothamSSm.json"
local CORNER = UDim.new(0, 12)
local BANNER_FILL_HEIGHT = 12
local BUTTON_SIZE = 34
local BG_AVATAR = Color3.fromRGB(53, 53, 53)
local BG_BUTTON = Color3.fromRGB(0, 0, 0)
local TEXT_WHITE = Color3.new(1, 1, 1)
local TRASH_ICON = "rbxassetid://78255461602603"

local function corner(parent: Instance, radius: UDim?)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or CORNER
	c.Parent = parent
end

local function pad(parent: Instance, left: number, right: number, top: number, bottom: number)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, left)
	p.PaddingRight = UDim.new(0, right)
	p.PaddingTop = UDim.new(0, top)
	p.PaddingBottom = UDim.new(0, bottom)
	p.Parent = parent
end

-- Font family of the queue's own track titles, so the card matches the rows around it.
local function resolveFamily(root: Instance): string
	local ref = root:FindFirstChild("TrackTitle", true)
	if ref and ref:IsA("TextLabel") then
		return ref.FontFace.Family
	end
	return FALLBACK_FAMILY
end

local function makeLabel(parent: Instance, name: string, family: string, weight: Enum.FontWeight, size: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.FontFace = Font.new(family, weight, Enum.FontStyle.Normal)
	l.TextSize = size
	l.TextColor3 = TEXT_WHITE
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = ""
	l.Parent = parent
	return l
end

local function makeFrame(parent: Instance, name: string, size: UDim2): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = size
	f.Parent = parent
	return f
end

-- Rich text for the starter line: the name is bold, and escaped so it cannot break the markup.
local function startedText(name: string): string
	local safe = string.gsub(string.gsub(string.gsub(name, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
	return "Started by <b>" .. safe .. "</b>"
end

local function makeIconButton(parent: Instance, name: string, image: string, iconScale: number, position: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = ""
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = BG_BUTTON
	button.BackgroundTransparency = 0.7
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = position
	button.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
	button.Visible = false
	button.Parent = parent
	corner(button, UDim.new(1, 0))
	local stroke = Instance.new("UIStroke")
	stroke.Color = TEXT_WHITE
	stroke.Transparency = 0.75
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(iconScale, iconScale)
	icon.Image = image
	icon.ImageColor3 = TEXT_WHITE
	icon.Parent = button
	return button
end

-- Paints a round control's stroke and icon (the remove and shuffle buttons take the on-fill colour).
local function paintButton(button: GuiObject, onFill: Color3)
	local stroke = button:FindFirstChildWhichIsA("UIStroke")
	if stroke then
		stroke.Color = onFill
	end
	local icon = button:FindFirstChildWhichIsA("ImageLabel")
	if icon then
		icon.ImageColor3 = onFill
	end
end

local SetBanner = {}
SetBanner.__index = SetBanner

-- The fill and on-fill a set's banner wears: its playlist's cover colour, or the player's accent
-- when there is no playlist (Liked Tracks, New Drops) or no colour.
function SetBanner.colorsFor(playlist: any?, config: any): (Color3, Color3)
	local cover = Visuals.coverAccent(playlist, config)
	if cover then
		return cover, Visuals.onFillFor(cover)
	end
	local accent = AccentService.get()
	return accent.fill, accent.onFill
end

-- parent: the frame the banner sits in. height nil fills the parent (a queue row).
-- opts.oneLineTitle: the title is one line that truncates (a waiting set); otherwise it wraps to two.
function SetBanner.new(
	parent: GuiObject,
	opts: { height: number?, kicker: string, family: string, trashIcon: string?, oneLineTitle: boolean? }
)
	local self = setmetatable({}, SetBanner) :: any
	local family = opts.family
	local banner = makeFrame(
		parent,
		"Banner",
		if opts.height then UDim2.new(1, 0, 0, opts.height) else UDim2.fromScale(1, 1)
	)
	self.frame = banner

	-- Solid fill with rounded top corners (the square filler keeps the bottom square under the
	-- banner's bottom 12 px, which is how the mock rounds only the top).
	local bannerTop = Instance.new("Frame")
	bannerTop.Name = "Top"
	bannerTop.BorderSizePixel = 0
	bannerTop.Size = UDim2.fromScale(1, 1)
	bannerTop.Parent = banner
	corner(bannerTop)
	local bannerFill = Instance.new("Frame")
	bannerFill.Name = "BottomFill"
	bannerFill.BorderSizePixel = 0
	bannerFill.Size = UDim2.new(1, 0, 0, BANNER_FILL_HEIGHT)
	bannerFill.Position = UDim2.new(0, 0, 1, -BANNER_FILL_HEIGHT)
	bannerFill.Parent = banner
	-- A waiting set's row banner stands alone, so all four corners round.
	bannerFill.Visible = opts.height ~= nil
	self._parts = { bannerTop, bannerFill }

	local content = makeFrame(banner, "Content", UDim2.fromScale(1, 1))
	content.ZIndex = 2
	pad(content, 14, 12, 12, 14)
	self.content = content

	local kicker = makeLabel(content, "Kicker", family, Enum.FontWeight.ExtraBold, 12)
	kicker.Size = UDim2.new(1, -86, 0, 14)
	kicker.TextTransparency = 0.25
	kicker.Text = opts.kicker
	self.kicker = kicker

	local title = makeLabel(content, "Title", family, Enum.FontWeight.ExtraBold, 20)
	title.Position = UDim2.fromOffset(0, 18)
	title.LineHeight = 1
	title.TextYAlignment = Enum.TextYAlignment.Top
	if opts.oneLineTitle then
		title.Size = UDim2.new(1, -86, 0, 24)
		title.TextWrapped = false
	else
		title.Size = UDim2.new(1, -86, 0, 44)
		title.TextWrapped = true
	end
	self.title = title

	-- Remove sits top-right; the caller places any other control (shuffle) beside it.
	if opts.trashIcon then
		self.trash = makeIconButton(content, "RemoveSet", opts.trashIcon, 0.6, UDim2.new(1, 0, 0, 0))
	end

	-- Starter row at the bottom of the banner: 24 px headshot, "Started by <name>", counter.
	local startedRow = makeFrame(content, "StartedRow", UDim2.new(1, 0, 0, 24))
	startedRow.Position = UDim2.new(0, 0, 1, -24)
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "StarterAvatar"
	avatar.BackgroundColor3 = BG_AVATAR
	avatar.BorderSizePixel = 0
	avatar.Size = UDim2.fromOffset(24, 24)
	avatar.Parent = startedRow
	corner(avatar, UDim.new(1, 0))
	self.avatar = avatar
	local started = makeLabel(startedRow, "Started", family, Enum.FontWeight.SemiBold, 14)
	started.RichText = true
	started.Position = UDim2.fromOffset(32, 0)
	started.Size = UDim2.new(1, -120, 1, 0)
	self.started = started
	local counter = makeLabel(startedRow, "Counter", family, Enum.FontWeight.Bold, 15)
	counter.Position = UDim2.new(1, -100, 0, 0)
	counter.Size = UDim2.fromOffset(100, 24)
	counter.TextXAlignment = Enum.TextXAlignment.Right
	self.counter = counter

	self._starterName = nil :: string?
	self._fill = nil :: Color3?
	self._onFill = nil :: Color3?
	return self
end

-- Idempotent: the store echoes full state, so unchanged text and headshots are not written again.
function SetBanner:setData(data: { title: string, starterName: string, starterUserId: number?, counter: string })
	Visuals.setText(self.title, data.title)
	if self._starterName ~= data.starterName then
		self._starterName = data.starterName
		self.started.Text = startedText(data.starterName)
	end
	Visuals.setHeadshot(self.avatar, data.starterUserId)
	Visuals.setText(self.counter, data.counter)
end

-- Paints the banner's fill and text. Idempotent for an unchanged pair.
function SetBanner:paint(fill: Color3, onFill: Color3)
	if self._fill == fill and self._onFill == onFill then
		return
	end
	self._fill = fill
	self._onFill = onFill
	for _, part in ipairs(self._parts) do
		part.BackgroundColor3 = fill
	end
	for _, child in ipairs({ self.kicker, self.title, self.started, self.counter }) do
		child.TextColor3 = onFill
	end
	if self.trash then
		paintButton(self.trash, onFill)
	end
end

function SetBanner:destroy()
	self.frame:Destroy()
end

SetBanner.TRASH_ICON = TRASH_ICON
SetBanner.paintButton = paintButton
SetBanner.makeIconButton = makeIconButton
SetBanner.resolveFamily = resolveFamily
SetBanner.makeLabel = makeLabel
SetBanner.makeFrame = makeFrame
SetBanner.corner = corner
SetBanner.pad = pad
SetBanner.startedText = startedText

return SetBanner
