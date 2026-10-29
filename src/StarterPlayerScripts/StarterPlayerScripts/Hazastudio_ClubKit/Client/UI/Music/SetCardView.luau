--!strict
-- PATH: StarterPlayerScripts/Client/UI/Music/SetCardView.luau
-- Active set card: the one queue row that stands for a whole set. It sits above the virtual queue
-- rows (LayoutOrder -2, ListPool reads its height as `leading`). Built from code, no template.
-- Geometry and colours follow the approved set card mock (card C): 2 px holder, 12 px corners,
-- solid banner 122 px tall (built by SetBanner, shared with a waiting set's queue row), three
-- up-next rows, "View full set" pill, no outline.
-- Shuffle and Remove set show for musicControl holders only. Hidden while no set is active.
-- Contract: docs/plans/active-set.md.

local AccentService = require(script.Parent.Parent.Parent.Services.AccentService)
local UIMotion = require(script.Parent.Parent.Parent.Utils.UIMotion)
local Visuals = require(script.Parent.Visuals)
local SetBanner = require(script.Parent.SetBanner)

local SHUFFLE_ICON = "rbxassetid://123512558618382"
local CORNER = UDim.new(0, 12)
local UP_NEXT_ROWS = 3
local BANNER_HEIGHT = 122
local BUTTON_SIZE = 34
local UP_NEXT_ROW_HEIGHT = 30
local UP_NEXT_NUMBER_WIDTH = 34
local UP_NEXT_DURATION_WIDTH = 50
local BG_CARD = Color3.fromRGB(22, 22, 22)
local BG_PILL = Color3.fromRGB(33, 33, 33)
local TEXT_WHITE = Color3.new(1, 1, 1)
local TEXT_GRAY = Color3.fromRGB(196, 196, 196)
local TEXT_DIM = Color3.fromRGB(125, 125, 125)

type Row = {
	frame: Frame,
	number: TextLabel,
	title: TextLabel,
	duration: TextLabel,
}

local corner = SetBanner.corner
local pad = SetBanner.pad
local makeLabel = SetBanner.makeLabel
local makeFrame = SetBanner.makeFrame
local makeIconButton = SetBanner.makeIconButton
local resolveFamily = SetBanner.resolveFamily

local SetCardView = {}
SetCardView.__index = SetCardView

function SetCardView.new(deps: {
	scroll: ScrollingFrame,
	refs: any,
	store: any,
	config: any?,
	fire: (string, ...any) -> any,
	onViewAll: () -> (),
})
	local self = setmetatable({}, SetCardView) :: any
	self._store = deps.store
	self._config = deps.config
	self._fire = deps.fire
	self._onViewAll = deps.onViewAll
	self._signature = nil :: string?
	self._coverFill = nil :: Color3?
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

	-- Banner: the shared set banner, full card width, kicker "NOW RUNNING A SET", two-line title.
	local banner = SetBanner.new(card, {
		height = BANNER_HEIGHT,
		kicker = "NOW RUNNING A SET",
		family = family,
		trashIcon = SetBanner.TRASH_ICON,
	})
	banner.frame.LayoutOrder = 1
	self._banner = banner
	local content = banner.content

	-- Shuffle sits left of Remove, 8 px apart (Remove is the banner's own control).
	local shuffleImage = SHUFFLE_ICON
	local shuffleIcon = if deps.refs and deps.refs.library then deps.refs.library.shuffleButton:FindFirstChildWhichIsA("ImageLabel") else nil
	if shuffleIcon then
		shuffleImage = shuffleIcon.Image
	end
	self._shuffle = makeIconButton(content, "ShuffleSet", shuffleImage, 0.55, UDim2.new(1, -42, 0, 0))
	local trash = banner.trash :: TextButton
	table.insert(self._connections, self._shuffle.Activated:Connect(function()
		UIMotion.spin(self._shuffle:FindFirstChildWhichIsA("ImageLabel"))
		self._fire("OnTransport", "set_reshuffle")
	end))
	table.insert(self._connections, trash.Activated:Connect(function()
		UIMotion.wiggle(trash:FindFirstChildWhichIsA("ImageLabel"), 14)
		self._fire("OnTransport", "set_stop")
	end))

	-- Progress: 3 px along the bottom edge of the banner.
	local track = Instance.new("Frame")
	track.Name = "Progress"
	track.BorderSizePixel = 0
	track.Position = UDim2.new(0, 0, 1, -3)
	track.Size = UDim2.new(1, 0, 0, 3)
	track.BackgroundTransparency = 0.85
	track.ZIndex = 3
	track.Parent = banner.frame
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

	for _, button in ipairs({ self._shuffle, trash, viewAll }) do
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

-- Accent banner: the set playlist's cover colour, or the player's accent when there is no playlist
-- or no colour (SetBanner.colorsFor). Text and icons take the fill's on-colour, as the rest of the
-- kit does on accent fills.
function SetCardView:_paintAccent()
	local fill = self._coverFill
	local onFill: Color3
	if fill then
		onFill = Visuals.onFillFor(fill)
	else
		local accent = AccentService.get()
		fill = accent.fill
		onFill = accent.onFill
	end
	self._banner:paint(fill, onFill)
	self._fill.BackgroundColor3 = onFill
	self._progressTrack.BackgroundColor3 = onFill
	SetBanner.paintButton(self._shuffle, onFill)
end

-- Shuffle and Remove set: musicControl holders only (set_reshuffle / set_stop are gated the same).
function SetCardView:setControl(allowed: boolean)
	self._control = allowed
	self._shuffle.Visible = allowed
	self._banner.trash.Visible = allowed
end

-- The playlist a set was started from (nil for Liked Tracks / New Drops, which have no playlist).
function SetCardView:_playlistFor(set: any): any?
	local playlists = self._store:get().playlists
	if type(playlists) ~= "table" or type(set.sourceId) ~= "string" then
		return nil
	end
	return playlists[set.sourceId]
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
	-- The banner colour follows the set's playlist, so a playlist recolour repaints even when the
	-- set itself is unchanged.
	local coverFill = Visuals.coverAccent(self:_playlistFor(set), self._config)
	if coverFill ~= self._coverFill then
		self._coverFill = coverFill
		self:_paintAccent()
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
	self._banner:setData({
		title = tostring(set.title or ""),
		starterName = tostring(set.starterName or ""),
		starterUserId = tonumber(set.starterUserId),
		counter = string.format("%d / %d", played, total),
	})
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
SetCardView.startedText = SetBanner.startedText

return SetCardView
