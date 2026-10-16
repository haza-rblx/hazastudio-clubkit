--!strict
-- PATH: StarterPlayerScripts/Client/UI/Music/SetCardView.luau
-- Active set card: the one queue row that stands for a whole set. It sits above the virtual queue
-- rows (LayoutOrder -2, ListPool reads its height as `leading`). Built from code, no template.
-- Geometry and colours follow the approved set card mock (card C): 2 px holder, 12 px corners,
-- solid accent banner 122 px tall, three up-next rows, "View full set" pill, no outline.
-- Shuffle and Remove set show for musicControl holders only. Hidden while no set is active.
-- Contract: docs/plans/active-set.md.

local AccentService = require(script.Parent.Parent.Parent.Services.AccentService)
local UIMotion = require(script.Parent.Parent.Parent.Utils.UIMotion)
local Visuals = require(script.Parent.Visuals)

local FALLBACK_FAMILY = "rbxasset://fonts/families/GothamSSm.json"
local SHUFFLE_ICON = "rbxassetid://123512558618382"
local TRASH_ICON = "rbxassetid://78255461602603"
local CORNER = UDim.new(0, 12)
local UP_NEXT_ROWS = 3
local BANNER_HEIGHT = 122
local BANNER_FILL_HEIGHT = 12
local BUTTON_SIZE = 34
local UP_NEXT_ROW_HEIGHT = 30
local UP_NEXT_NUMBER_WIDTH = 34
local UP_NEXT_DURATION_WIDTH = 50
local BG_CARD = Color3.fromRGB(22, 22, 22)
local BG_PILL = Color3.fromRGB(33, 33, 33)
local BG_AVATAR = Color3.fromRGB(53, 53, 53)
local BG_BUTTON = Color3.fromRGB(0, 0, 0)
local TEXT_WHITE = Color3.new(1, 1, 1)
local TEXT_GRAY = Color3.fromRGB(196, 196, 196)
local TEXT_DIM = Color3.fromRGB(125, 125, 125)

type Row = {
	frame: Frame,
	number: TextLabel,
	title: TextLabel,
	duration: TextLabel,
}

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

local SetCardView = {}
SetCardView.__index = SetCardView

function SetCardView.new(deps: {
	scroll: ScrollingFrame,
	refs: any,
	store: any,
	fire: (string, ...any) -> any,
	onViewAll: () -> (),
})
	local self = setmetatable({}, SetCardView) :: any
	self._store = deps.store
	self._fire = deps.fire
	self._onViewAll = deps.onViewAll
	self._signature = nil :: string?
	self._control = false
	self._connections = {} :: { RBXScriptConnection }
	self._rows = {} :: { Row }
	local family = resolveFamily(deps.scroll)

	-- Holder: the queue child (2 px around the card, so the card is never clipped by the list).
	local holder = makeFrame(deps.scroll, "ActiveSetCard", UDim2.new(1, 0, 0, 0))
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.LayoutOrder = -2
	holder.Visible = false
	pad(holder, 2, 2, 2, 2)
	self.frame = holder

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.BackgroundColor3 = BG_CARD
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Parent = holder
	corner(card)
	local cardLayout = Instance.new("UIListLayout")
	cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
	cardLayout.Parent = card

	-- Banner: solid accent with rounded top corners (the square filler keeps the bottom square
	-- under the banner's bottom 12 px, which is how the mock rounds only the top).
	local banner = makeFrame(card, "Banner", UDim2.new(1, 0, 0, BANNER_HEIGHT))
	banner.LayoutOrder = 1
	self._banner = banner
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
	self._bannerParts = { bannerTop, bannerFill }

	local content = makeFrame(banner, "Content", UDim2.fromScale(1, 1))
	content.ZIndex = 2
	pad(content, 14, 12, 12, 14)

	local kicker = makeLabel(content, "Kicker", family, Enum.FontWeight.ExtraBold, 12)
	kicker.Size = UDim2.new(1, -86, 0, 14)
	kicker.TextTransparency = 0.25
	kicker.Text = "NOW RUNNING A SET"
	self._kicker = kicker

	local title = makeLabel(content, "Title", family, Enum.FontWeight.ExtraBold, 20)
	title.Position = UDim2.fromOffset(0, 18)
	title.Size = UDim2.new(1, -86, 0, 44)
	title.TextWrapped = true
	title.LineHeight = 1
	title.TextYAlignment = Enum.TextYAlignment.Top
	self._title = title

	-- Controls sit top-right, 8 px apart, 34 px round (shuffle, then remove).
	local shuffleImage = SHUFFLE_ICON
	local shuffleIcon = if deps.refs and deps.refs.library then deps.refs.library.shuffleButton:FindFirstChildWhichIsA("ImageLabel") else nil
	if shuffleIcon then
		shuffleImage = shuffleIcon.Image
	end
	self._shuffle = makeIconButton(content, "ShuffleSet", shuffleImage, 0.55, UDim2.new(1, -42, 0, 0))
	self._trash = makeIconButton(content, "RemoveSet", TRASH_ICON, 0.6, UDim2.new(1, 0, 0, 0))
	table.insert(self._connections, self._shuffle.Activated:Connect(function()
		UIMotion.spin(self._shuffle:FindFirstChildWhichIsA("ImageLabel"))
		self._fire("OnTransport", "set_reshuffle")
	end))
	table.insert(self._connections, self._trash.Activated:Connect(function()
		UIMotion.wiggle(self._trash:FindFirstChildWhichIsA("ImageLabel"), 14)
		self._fire("OnTransport", "set_stop")
	end))

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
	self._avatar = avatar
	local started = makeLabel(startedRow, "Started", family, Enum.FontWeight.SemiBold, 14)
	started.RichText = true
	started.Position = UDim2.fromOffset(32, 0)
	started.Size = UDim2.new(1, -120, 1, 0)
	self._started = started
	local counter = makeLabel(startedRow, "Counter", family, Enum.FontWeight.Bold, 15)
	counter.Position = UDim2.new(1, -100, 0, 0)
	counter.Size = UDim2.fromOffset(100, 24)
	counter.TextXAlignment = Enum.TextXAlignment.Right
	self._counter = counter

	-- Progress: 3 px along the bottom edge of the banner.
	local track = Instance.new("Frame")
	track.Name = "Progress"
	track.BorderSizePixel = 0
	track.Position = UDim2.new(0, 0, 1, -3)
	track.Size = UDim2.new(1, 0, 0, 3)
	track.BackgroundTransparency = 0.85
	track.ZIndex = 3
	track.Parent = banner
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 3
	fill.Parent = track
	self._fill = fill
	self._progressTrack = track

	-- Peek: "UP NEXT FROM SET", three rows, then the "View full set" pill.
	local peek = makeFrame(card, "Peek", UDim2.new(1, 0, 0, 0))
	peek.AutomaticSize = Enum.AutomaticSize.Y
	peek.LayoutOrder = 2
	pad(peek, 14, 14, 10, 12)
	local peekLayout = Instance.new("UIListLayout")
	peekLayout.Padding = UDim.new(0, 2)
	peekLayout.SortOrder = Enum.SortOrder.LayoutOrder
	peekLayout.Parent = peek

	local upHeader = makeLabel(peek, "UpNextHeader", family, Enum.FontWeight.ExtraBold, 12)
	upHeader.Size = UDim2.new(1, 0, 0, 20)
	upHeader.LayoutOrder = 0
	upHeader.TextColor3 = TEXT_DIM
	upHeader.Text = "UP NEXT FROM SET"

	for index = 1, UP_NEXT_ROWS do
		local rowFrame = makeFrame(peek, "UpNext" .. index, UDim2.new(1, 0, 0, UP_NEXT_ROW_HEIGHT))
		rowFrame.LayoutOrder = index
		local number = makeLabel(rowFrame, "Number", family, Enum.FontWeight.Bold, 14)
		number.Size = UDim2.new(0, UP_NEXT_NUMBER_WIDTH, 1, 0)
		number.TextColor3 = TEXT_DIM
		local rowTitle = makeLabel(rowFrame, "Title", family, if index == 1 then Enum.FontWeight.Bold else Enum.FontWeight.SemiBold, 15)
		rowTitle.Position = UDim2.fromOffset(36, 0)
		rowTitle.Size = UDim2.new(1, -92, 1, 0)
		rowTitle.TextColor3 = if index == 1 then TEXT_WHITE else TEXT_GRAY
		local duration = makeLabel(rowFrame, "Duration", family, Enum.FontWeight.SemiBold, 13)
		duration.Position = UDim2.new(1, -UP_NEXT_DURATION_WIDTH, 0, 0)
		duration.Size = UDim2.new(0, UP_NEXT_DURATION_WIDTH, 1, 0)
		duration.TextColor3 = TEXT_DIM
		duration.TextXAlignment = Enum.TextXAlignment.Right
		table.insert(self._rows, { frame = rowFrame, number = number, title = rowTitle, duration = duration })
	end

	local spacer = makeFrame(peek, "Spacer", UDim2.new(1, 0, 0, 6))
	spacer.LayoutOrder = 98

	local viewAll = Instance.new("TextButton")
	viewAll.Name = "ViewFullSet"
	viewAll.Text = "View full set"
	viewAll.TextSize = 15
	viewAll.FontFace = Font.new(family, Enum.FontWeight.Bold, Enum.FontStyle.Normal)
	viewAll.TextColor3 = TEXT_GRAY
	viewAll.AutoButtonColor = false
	viewAll.BorderSizePixel = 0
	viewAll.BackgroundColor3 = BG_PILL
	viewAll.Size = UDim2.new(1, 0, 0, 34)
	viewAll.LayoutOrder = 99
	viewAll.Parent = peek
	corner(viewAll, UDim.new(1, 0))
	self._viewAll = viewAll
	table.insert(self._connections, viewAll.Activated:Connect(function()
		self._onViewAll()
	end))

	for _, button in ipairs({ self._shuffle, self._trash, viewAll }) do
		for _, connection in ipairs(UIMotion.bindPress(button)) do
			table.insert(self._connections, connection)
		end
		for _, connection in ipairs(UIMotion.bindHover(button)) do
			table.insert(self._connections, connection)
		end
	end

	self._accentUnsubscribe = AccentService.subscribe(function()
		self:_paintAccent()
	end)
	self:_paintAccent()
	self:setControl(false)
	return self
end

-- Accent banner (the playlist's accent, or the player's accent). Text and icons take the accent's
-- on-colour, as the rest of the kit does on accent fills.
function SetCardView:_paintAccent()
	local accent = AccentService.get()
	for _, part in ipairs(self._bannerParts) do
		part.BackgroundColor3 = accent.fill
	end
	for _, child in ipairs({ self._kicker, self._title, self._started, self._counter }) do
		child.TextColor3 = accent.onFill
	end
	self._fill.BackgroundColor3 = accent.onFill
	self._progressTrack.BackgroundColor3 = accent.onFill
	for _, button in ipairs({ self._shuffle, self._trash }) do
		local stroke = button:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			stroke.Color = accent.onFill
		end
		local icon = button:FindFirstChildWhichIsA("ImageLabel")
		if icon then
			icon.ImageColor3 = accent.onFill
		end
	end
end

-- Shuffle and Remove set: musicControl holders only (set_reshuffle / set_stop are gated the same).
function SetCardView:setControl(allowed: boolean)
	self._control = allowed
	self._shuffle.Visible = allowed
	self._trash.Visible = allowed
end

-- Idempotent: the store echoes the full state on every sync, so an unchanged set repaints nothing.
function SetCardView:update(set: any?)
	if type(set) ~= "table" then
		if self._signature ~= nil then
			self._signature = nil
			self.frame.Visible = false
		end
		return
	end
	local upNext = if type(set.upNext) == "table" then set.upNext else {}
	local upIds = {}
	for _, track in ipairs(upNext) do
		table.insert(upIds, tostring(track.id))
	end
	local signature = table.concat({
		tostring(set.id),
		tostring(set.title),
		tostring(set.played),
		tostring(set.total),
		tostring(set.starterUserId),
		tostring(set.starterName),
		table.concat(upIds, ","),
	}, "|")
	if signature == self._signature then
		return
	end
	self._signature = signature

	local played = math.floor(tonumber(set.played) or 0)
	local total = math.floor(tonumber(set.total) or 0)
	self.frame.Visible = true
	Visuals.setText(self._title, tostring(set.title or ""))
	self._started.Text = startedText(tostring(set.starterName or ""))
	Visuals.setHeadshot(self._avatar, tonumber(set.starterUserId))
	Visuals.setText(self._counter, string.format("%d / %d", played, total))
	local progress = if total > 0 then math.clamp(played / total, 0, 1) else 0
	self._fill.Size = UDim2.fromScale(progress, 1)

	for index, row in ipairs(self._rows) do
		local track = upNext[index]
		row.frame.Visible = type(track) == "table"
		if type(track) == "table" then
			Visuals.setText(row.number, tostring(played + index))
			Visuals.setText(row.title, tostring(track.name or ""))
			Visuals.setText(row.duration, Visuals.formatClock(tonumber(track.totalDuration) or 0))
		end
	end
end

function SetCardView:destroy()
	if self._accentUnsubscribe then
		self._accentUnsubscribe()
	end
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self.frame:Destroy()
end

-- Shared with SetSheetView so both build from the same pieces and font.
SetCardView.resolveFamily = resolveFamily
SetCardView.makeLabel = makeLabel
SetCardView.makeFrame = makeFrame
SetCardView.corner = corner
SetCardView.pad = pad
SetCardView.startedText = startedText

return SetCardView
