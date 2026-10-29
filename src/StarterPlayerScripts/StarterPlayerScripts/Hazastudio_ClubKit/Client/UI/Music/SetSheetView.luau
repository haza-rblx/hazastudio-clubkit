--!strict
-- PATH: StarterPlayerScripts/Client/UI/Music/SetSheetView.luau
-- Full set sheet: the active set's remaining tracks, fetched a page at a time (transport set_page)
-- into a virtual list. Own ScreenGui over the music panel; the panel scales to 0.94 behind a dim.
-- Geometry follows the approved sheet mock: 6 px gutter, 20 px sheet corners, 16 px column corners,
-- 12 px row corners, 52 px rows, 52 px peek. Contract: docs/plans/active-set.md. Opened from the
-- Set card; closes on Back, dim tap, the panel closing, or the set ending.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local AccentService = require(script.Parent.Parent.Parent.Services.AccentService)
local UIMotion = require(script.Parent.Parent.Parent.Utils.UIMotion)
local OverlayScrollbar = require(script.Parent.Parent.OverlayScrollbar)
local SetCardView = require(script.Parent.SetCardView)
local Visuals = require(script.Parent.Visuals)

local musicConfig = (Config :: any).Music or {}
local PAGE_SIZE = math.max(1, math.floor(tonumber(musicConfig.SET_PAGE_SIZE) or 50))

local ROW_PITCH = 52
local ROW_HEIGHT = 49
local ROW_POOL = 14
local ROW_NUMBER_LEFT = 8
local ROW_TITLE_GAP = 12
local ROW_TITLE_CLEAR = 98
local ROW_DURATION_WIDTH = 60
local ROW_DURATION_X = -74
local NUMBER_TEXT_SIZE = 14
local LEFT_WIDTH = 280
local GUTTER = 6
local NARROW_WIDTH = 600
local NARROW_LEFT_HEIGHT = 260
local SHEET_OFFSET_Y = 52
local SLIDE_PX = 60
local SHEET_TWEEN = TweenInfo.new(0.32, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local SCALE_OPEN = 0.94
local DIM_TRANSPARENCY = 0.35
local SEARCH_DEBOUNCE = 0.3
local RETRY_SECONDS = 2
local BG_PANEL = Color3.fromRGB(7, 7, 7)
local BG_RIGHT = Color3.fromRGB(18, 18, 18)
local BG_FIELD = Color3.fromRGB(33, 33, 33)
local BG_ROW = Color3.fromRGB(27, 27, 27)
local BG_ROW_FIRST = Color3.fromRGB(38, 38, 38)
local BG_SKELETON_A = Color3.fromRGB(40, 40, 40)
local BG_SKELETON_B = Color3.fromRGB(34, 34, 34)
local BG_AVATAR = Color3.fromRGB(53, 53, 53)
local BG_BUTTON = Color3.fromRGB(0, 0, 0)
local TEXT_WHITE = Color3.new(1, 1, 1)
local TEXT_GRAY = Color3.fromRGB(196, 196, 196)
local TEXT_DIM = Color3.fromRGB(125, 125, 125)
-- Kit icons already in the place: Menu "Back to main menu", Library shuffle, queue trash.
local BACK_ICON = "rbxassetid://113150974507253"
local SHUFFLE_ICON = "rbxassetid://123512558618382"
local TRASH_ICON = "rbxassetid://78255461602603"

type Row = {
	frame: Frame,
	number: TextLabel,
	title: TextLabel,
	artist: TextLabel,
	duration: TextLabel,
	skeletonA: Frame,
	skeletonB: Frame,
	index: number?,
	track: any?,
}

type Fade = {
	object: GuiObject,
	background: number,
	text: number?,
	image: number?,
}

local corner = SetCardView.corner
local pad = SetCardView.pad

local SetSheetView = {}
SetSheetView.__index = SetSheetView

function SetSheetView.new(deps: { refs: any, store: any, fire: (string, ...any) -> any })
	local self = setmetatable({}, SetSheetView) :: any
	self._store = deps.store
	self._fire = deps.fire
	self._root = deps.refs.root :: ScreenGui
	self._main = deps.refs.mainWrapper :: Frame
	self._family = SetCardView.resolveFamily(self._root)
	self._open = false
	self._control = false
	self._rest = UDim2.new()
	self._connections = {} :: { RBXScriptConnection }
	self._unsubscribers = {} :: { () -> () }
	self._tweens = {} :: { Tween }
	self._fade = {} :: { Fade }
	self._cache = {} :: { [number]: any }
	self._loaded = {} :: { [number]: boolean }
	self._pending = {} :: { [number]: boolean }
	self._failed = {} :: { [number]: boolean }
	self._generation = 0
	self._query = ""
	self._total = 0
	self._played = 0
	self._setId = nil :: any
	self._accentFill = TEXT_WHITE
	self._numWidth = 0
	self._numWidthCache = {} :: { [string]: number }
	self._numMeasuring = {} :: { [string]: boolean }
	self._searchToken = 0

	-- Own overlay. Same inset setting as the music GUI, so AbsolutePosition lines up with it.
	local gui = Instance.new("ScreenGui")
	gui.Name = "MusicSetSheet"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = self._root.IgnoreGuiInset
	gui.DisplayOrder = self._root.DisplayOrder + 1
	gui.Enabled = false
	gui.Parent = self._root.Parent
	self._gui = gui

	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.BorderSizePixel = 0
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Position = UDim2.fromOffset(0, -100)
	dim.Size = UDim2.new(1, 0, 1, 200)
	dim.ZIndex = 1
	dim.Parent = gui
	self._dim = dim

	local sheet = Instance.new("Frame")
	sheet.Name = "Sheet"
	sheet.BackgroundColor3 = BG_PANEL
	sheet.BorderSizePixel = 0
	sheet.Active = true
	sheet.ZIndex = 5
	sheet.Visible = false
	sheet.Parent = gui
	corner(sheet, UDim.new(0, 20))
	pad(sheet, GUTTER, GUTTER, GUTTER, GUTTER)
	self._sheet = sheet

	-- Left column: accent, Back, title, started by, counter, songs left, progress, then the controls.
	local summary = Instance.new("Frame")
	summary.Name = "Summary"
	summary.BorderSizePixel = 0
	summary.Size = UDim2.new(0, LEFT_WIDTH, 1, 0)
	summary.Parent = sheet
	corner(summary, UDim.new(0, 16))
	pad(summary, 16, 16, 16, 16)
	self._summary = summary

	local back = self:_makePill(summary, "Back", "Back", BACK_ICON)
	back.Position = UDim2.fromOffset(0, 0)
	self._back = back

	local kicker = SetCardView.makeLabel(summary, "Kicker", self._family, Enum.FontWeight.ExtraBold, 12)
	kicker.Position = UDim2.fromOffset(0, 60)
	kicker.Size = UDim2.new(1, 0, 0, 14)
	kicker.TextTransparency = 0.25
	kicker.Text = "NOW RUNNING A SET"

	local title = SetCardView.makeLabel(summary, "Title", self._family, Enum.FontWeight.ExtraBold, 26)
	title.Position = UDim2.fromOffset(0, 80)
	title.Size = UDim2.new(1, 0, 0, 96)
	title.TextWrapped = true
	title.TextYAlignment = Enum.TextYAlignment.Top
	self._title = title

	local startedRow = SetCardView.makeFrame(summary, "StartedRow", UDim2.new(1, 0, 0, 26))
	startedRow.Position = UDim2.fromOffset(0, 184)
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "StarterAvatar"
	avatar.BackgroundColor3 = BG_AVATAR
	avatar.BorderSizePixel = 0
	avatar.Size = UDim2.fromOffset(26, 26)
	avatar.Parent = startedRow
	corner(avatar, UDim.new(1, 0))
	self._avatar = avatar
	local started = SetCardView.makeLabel(startedRow, "Started", self._family, Enum.FontWeight.SemiBold, 14)
	started.RichText = true
	started.Position = UDim2.fromOffset(34, 0)
	started.Size = UDim2.new(1, -34, 1, 0)
	self._started = started

	local stats = SetCardView.makeFrame(summary, "Stats", UDim2.new(1, 0, 0, 120))
	stats.Position = UDim2.new(0, 0, 1, -120)
	local counter = SetCardView.makeLabel(stats, "Counter", self._family, Enum.FontWeight.ExtraBold, 30)
	counter.Size = UDim2.new(1, 0, 0, 34)
	self._counter = counter
	local songsLeft = SetCardView.makeLabel(stats, "SongsLeft", self._family, Enum.FontWeight.SemiBold, 14)
	songsLeft.Position = UDim2.fromOffset(0, 36)
	songsLeft.Size = UDim2.new(1, 0, 0, 18)
	self._songsLeft = songsLeft

	local progress = Instance.new("Frame")
	progress.Name = "Progress"
	progress.BorderSizePixel = 0
	progress.BackgroundTransparency = 0.8
	progress.Position = UDim2.fromOffset(0, 64)
	progress.Size = UDim2.new(1, 0, 0, 4)
	progress.Parent = stats
	corner(progress, UDim.new(1, 0))
	self._progressTrack = progress
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = progress
	corner(fill, UDim.new(1, 0))
	self._fill = fill

	local actions = SetCardView.makeFrame(stats, "Actions", UDim2.new(1, 0, 0, 36))
	actions.Position = UDim2.new(0, 0, 1, -36)
	local actionsLayout = Instance.new("UIListLayout")
	actionsLayout.FillDirection = Enum.FillDirection.Horizontal
	actionsLayout.Padding = UDim.new(0, 8)
	actionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionsLayout.Parent = actions
	self._actions = actions
	self._reshuffle = self:_makePill(actions, "Reshuffle", "Reshuffle", SHUFFLE_ICON)
	self._removeSet = self:_makePill(actions, "RemoveSet", "Remove set", TRASH_ICON)

	-- Right column: header, search, virtual list. A card of its own, 6 px from the left column.
	local upNext = Instance.new("Frame")
	upNext.Name = "UpNextCard"
	upNext.BackgroundColor3 = BG_RIGHT
	upNext.BorderSizePixel = 0
	upNext.ClipsDescendants = true
	upNext.Position = UDim2.fromOffset(LEFT_WIDTH + GUTTER, 0)
	upNext.Size = UDim2.new(1, -(LEFT_WIDTH + GUTTER), 1, 0)
	upNext.Parent = sheet
	corner(upNext, UDim.new(0, 16))
	pad(upNext, 16, 16, 16, 16)
	self._upNext = upNext

	local header = SetCardView.makeLabel(upNext, "Header", self._family, Enum.FontWeight.ExtraBold, 12)
	header.Size = UDim2.new(1, 0, 0, 20)
	header.TextColor3 = TEXT_DIM
	header.Text = "UP NEXT FROM SET"

	local search = Instance.new("TextBox")
	search.Name = "Search"
	search.BorderSizePixel = 0
	search.BackgroundColor3 = BG_FIELD
	search.ClearTextOnFocus = false
	search.PlaceholderText = "Search in this set"
	search.PlaceholderColor3 = TEXT_DIM
	search.Text = ""
	search.TextColor3 = TEXT_WHITE
	search.TextSize = 14
	search.TextXAlignment = Enum.TextXAlignment.Left
	search.FontFace = Font.new(self._family, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
	search.AnchorPoint = Vector2.new(1, 0)
	search.Position = UDim2.new(1, 0, 0, -6)
	search.Size = UDim2.fromOffset(220, 32)
	search.Parent = upNext
	corner(search, UDim.new(1, 0))
	pad(search, 14, 14, 0, 0)
	self._search = search

	-- The list runs 12 px into the card's right padding: rows still end at the content edge and the
	-- overlay bar lives in that gutter, never over the rows.
	local viewport = Instance.new("ScrollingFrame")
	viewport.Name = "List"
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.ClipsDescendants = true
	viewport.AutomaticCanvasSize = Enum.AutomaticSize.None
	viewport.CanvasSize = UDim2.fromOffset(0, 0)
	viewport.ScrollBarThickness = 0
	viewport.ScrollBarImageTransparency = 1
	viewport.ScrollingDirection = Enum.ScrollingDirection.Y
	viewport.Position = UDim2.fromOffset(0, 34)
	viewport.Size = UDim2.new(1, 12, 1, -34)
	viewport.Parent = upNext
	self._viewport = viewport

	self._rows = {} :: { Row }
	for _ = 1, ROW_POOL do
		table.insert(self._rows, self:_newRow(viewport))
	end

	-- Snapshot every transparency before the overlay scrollbar joins, so open() can restore them.
	self:_snapshotFade()
	self._scrollHandle = OverlayScrollbar.attach(viewport, sheet)

	table.insert(self._connections, back.Activated:Connect(function()
		self:close(false)
	end))
	table.insert(self._connections, dim.Activated:Connect(function()
		self:close(false)
	end))
	table.insert(self._connections, self._reshuffle.Activated:Connect(function()
		self._fire("OnTransport", "set_reshuffle")
	end))
	table.insert(self._connections, self._removeSet.Activated:Connect(function()
		self._fire("OnTransport", "set_stop")
	end))
	table.insert(self._connections, viewport:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:_refreshRows()
	end))
	table.insert(self._connections, viewport:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function()
		self:_refreshRows()
	end))
	table.insert(self._connections, search:GetPropertyChangedSignal("Text"):Connect(function()
		self:_onSearchTyped()
	end))
	-- The panel closing takes the sheet with it.
	table.insert(self._connections, self._main:GetPropertyChangedSignal("Visible"):Connect(function()
		if not self._main.Visible then
			self:close(true)
		end
	end))
	for _, button in ipairs({ back, self._reshuffle, self._removeSet }) do
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

	table.insert(self._unsubscribers, self._store:subscribe("activeSet", function(set: any)
		self:_onSet(set)
	end))
	self:_onSet(self._store:get().activeSet)
	return self
end

-- Pill: black at 60% transparency, fully round, 36 px tall, 16 px either side of its content.
-- With an icon, the icon (18 px) sits left of the label and the pill's own Text stays empty.
function SetSheetView:_makePill(parent: Instance, name: string, text: string, icon: string?): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = if icon then "" else text
	button.TextSize = 15
	button.FontFace = Font.new(self._family, Enum.FontWeight.Bold, Enum.FontStyle.Normal)
	button.TextColor3 = TEXT_WHITE
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = BG_BUTTON
	button.BackgroundTransparency = 0.6
	button.Size = UDim2.fromOffset(0, 36)
	button.AutomaticSize = Enum.AutomaticSize.X
	button.Parent = parent
	corner(button, UDim.new(1, 0))
	pad(button, if icon then 12 else 16, 16, 0, 0)
	if icon then
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 8)
		layout.Parent = button
		local image = Instance.new("ImageLabel")
		image.Name = "Icon"
		image.BackgroundTransparency = 1
		image.Image = icon
		image.ImageColor3 = TEXT_WHITE
		image.ScaleType = Enum.ScaleType.Fit
		image.Size = UDim2.fromOffset(18, 18)
		image.LayoutOrder = 1
		image.Parent = button
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextSize = 15
		label.FontFace = button.FontFace
		label.TextColor3 = TEXT_WHITE
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromOffset(0, 36)
		label.LayoutOrder = 2
		label.Parent = button
	end
	return button
end

function SetSheetView:_newRow(parent: ScrollingFrame): Row
	local family = self._family
	local frame = Instance.new("Frame")
	frame.Name = "SetRow"
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = BG_ROW
	frame.Size = UDim2.new(1, -12, 0, ROW_HEIGHT)
	frame.Visible = false
	frame.Parent = parent
	corner(frame, UDim.new(0, 12))

	local number = SetCardView.makeLabel(frame, "Number", family, Enum.FontWeight.Bold, NUMBER_TEXT_SIZE)
	number.TextXAlignment = Enum.TextXAlignment.Center
	number.TextColor3 = TEXT_DIM

	local title = SetCardView.makeLabel(frame, "Title", family, Enum.FontWeight.Bold, 15)
	local artist = SetCardView.makeLabel(frame, "Artist", family, Enum.FontWeight.SemiBold, 13)
	artist.TextColor3 = TEXT_GRAY

	local duration = SetCardView.makeLabel(frame, "Duration", family, Enum.FontWeight.SemiBold, 13)
	duration.TextColor3 = TEXT_DIM
	duration.TextXAlignment = Enum.TextXAlignment.Right
	duration.Position = UDim2.new(1, ROW_DURATION_X, 0, 0)
	duration.Size = UDim2.new(0, ROW_DURATION_WIDTH, 1, 0)

	local function skeleton(name: string, scaleWidth: number, height: number, color: Color3): Frame
		local bar = Instance.new("Frame")
		bar.Name = name
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = color
		bar.Size = UDim2.new(scaleWidth, 0, 0, height)
		bar.Visible = false
		bar.Parent = frame
		corner(bar, UDim.new(1, 0))
		return bar
	end
	local skeletonA = skeleton("SkeletonTitle", 0.45, 12, BG_SKELETON_A)
	local skeletonB = skeleton("SkeletonArtist", 0.28, 10, BG_SKELETON_B)

	local row: Row = {
		frame = frame,
		number = number,
		title = title,
		artist = artist,
		duration = duration,
		skeletonA = skeletonA,
		skeletonB = skeletonB,
		index = nil,
		track = nil,
	}
	self:_layoutRow(row)
	return row
end

-- Number column: as wide as the widest number in the set, number centred in it, 8 px from the left.
-- Title and artist start 12 px after the column.
function SetSheetView:_layoutRow(row: Row)
	local width = self._numWidth
	local textX = ROW_NUMBER_LEFT + width + ROW_TITLE_GAP
	local textWidth = -(textX + ROW_TITLE_CLEAR)
	row.number.Position = UDim2.fromOffset(ROW_NUMBER_LEFT, 0)
	row.number.Size = UDim2.new(0, width, 1, 0)
	row.title.Position = UDim2.fromOffset(textX, 6)
	row.title.Size = UDim2.new(1, textWidth, 0, 18)
	row.artist.Position = UDim2.fromOffset(textX, 25)
	row.artist.Size = UDim2.new(1, textWidth, 0, 16)
	row.skeletonA.Position = UDim2.fromOffset(textX, 9)
	row.skeletonB.Position = UDim2.fromOffset(textX, 27)
end

function SetSheetView:_bindRow(row: Row, index: number)
	local track = self._cache[index]
	row.index = index
	row.track = track
	row.frame.Position = UDim2.fromOffset(0, (index - 1) * ROW_PITCH)
	row.frame.BackgroundColor3 = if index == 1 then BG_ROW_FIRST else BG_ROW
	row.number.TextColor3 = if index == 1 then self._accentFill else TEXT_DIM
	local base = if self._query == "" then self._played else 0
	Visuals.setText(row.number, tostring(base + index))
	local loaded = type(track) == "table"
	row.title.Visible = loaded
	row.artist.Visible = loaded
	row.duration.Visible = loaded
	row.skeletonA.Visible = not loaded
	row.skeletonB.Visible = not loaded
	if loaded then
		Visuals.setText(row.title, tostring(track.name or ""))
		Visuals.setText(row.artist, tostring(track.creator or ""))
		Visuals.setText(row.duration, Visuals.formatClock(tonumber(track.totalDuration) or 0))
	end
end

-- ============================================================
-- Data
-- ============================================================

function SetSheetView:_onSet(set: any?)
	if type(set) ~= "table" then
		self._setId = nil
		self:close(true)
		return
	end
	local played = tonumber(set.played) or 0
	local idChanged = set.id ~= self._setId
	local playedChanged = played ~= self._played
	self._setId = set.id
	self._played = played
	self:_paintHeader(set)
	if self._open and (idChanged or playedChanged) then
		-- A new set or reshuffle reorders everything (back to the top); a track ending only shifts
		-- the remaining order, so the reader keeps their place.
		self:_reset(not idChanged)
	end
end

function SetSheetView:_remainingEstimate(): number
	local set = self._store:get().activeSet
	if type(set) ~= "table" then
		return 0
	end
	return math.max(0, (tonumber(set.total) or 0) - (tonumber(set.played) or 0))
end

-- Drops everything fetched so far and refetches what is on screen. The estimate is the set's own
-- remaining count; a search has no known count, so one placeholder row asks for page 0.
function SetSheetView:_reset(keepScroll: boolean)
	self._generation += 1
	self._cache = {}
	self._loaded = {}
	self._pending = {}
	self._failed = {}
	if self._query == "" then
		self._total = self:_remainingEstimate()
	else
		self._total = math.min(ROW_POOL, PAGE_SIZE)
	end
	if not keepScroll then
		self._viewport.CanvasPosition = Vector2.zero
	end
	self:_applyTotal()
	self:_refreshRows()
end

function SetSheetView:_applyTotal()
	self._viewport.CanvasSize = UDim2.fromOffset(0, self._total * ROW_PITCH)
	local width = self:_numberWidth()
	if width ~= self._numWidth then
		self._numWidth = width
		for _, row in ipairs(self._rows) do
			self:_layoutRow(row)
		end
	end
end

-- Width of the number column, measured in the list's own font for the widest number the set can
-- show. Until the measurement lands, a rough width stands in and the rows relayout after it.
function SetSheetView:_numberWidth(): number
	local set = self._store:get().activeSet
	local setTotal = if type(set) == "table" then math.floor(tonumber(set.total) or 0) else 0
	local text = tostring(math.max(10, setTotal, self._total))
	local measured = self._numWidthCache[text]
	if measured then
		return measured
	end
	if not self._numMeasuring[text] then
		self._numMeasuring[text] = true
		task.spawn(function()
			self:_measureNumber(text)
		end)
	end
	return #text * 8 + 2
end

function SetSheetView:_measureNumber(text: string)
	local params = Instance.new("GetTextBoundsParams")
	params.Text = text
	params.Font = Font.new(self._family, Enum.FontWeight.Bold, Enum.FontStyle.Normal)
	params.Size = NUMBER_TEXT_SIZE
	params.Width = 1000
	local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
	self._numMeasuring[text] = nil
	if ok and typeof(bounds) == "Vector2" then
		self._numWidthCache[text] = math.ceil(bounds.X) + 2
		if self._gui.Parent then
			self:_applyTotal()
		end
	end
end

function SetSheetView:_refreshRows()
	if not self._open then
		return
	end
	local total = self._total
	local first = math.max(1, math.floor(math.max(0, self._viewport.CanvasPosition.Y) / ROW_PITCH) + 1)
	for slot, row in ipairs(self._rows) do
		local index = first + slot - 1
		if index <= total then
			if row.index ~= index or row.track ~= self._cache[index] then
				self:_bindRow(row, index)
			end
			row.frame.Visible = true
		else
			row.frame.Visible = false
			row.index = nil
			row.track = nil
		end
	end
	local last = math.min(total, first + ROW_POOL - 1)
	-- Pages for what is on screen, plus one pool of rows either side so a scroll lands on data.
	self:_requestPages(math.max(1, first - ROW_POOL), math.min(total, last + ROW_POOL))
end

function SetSheetView:_requestPages(first: number, last: number)
	if last < first then
		return
	end
	for page = math.floor((first - 1) / PAGE_SIZE), math.floor((last - 1) / PAGE_SIZE) do
		if not self._loaded[page] and not self._pending[page] then
			self:_requestPage(page)
		end
	end
end

-- set_page is rate limited on the server (SET_PAGE_RATE). A refused page is retried later.
function SetSheetView:_requestPage(page: number)
	local generation = self._generation
	local pending = self._pending
	local query = self._query
	local offset = page * PAGE_SIZE
	pending[page] = true
	task.spawn(function()
		local result = self._fire("OnTransportRequest", "set_page", {
			offset = offset,
			limit = PAGE_SIZE,
			query = if query ~= "" then query else nil,
		})
		pending[page] = nil
		if generation ~= self._generation then
			return
		end
		local data = if type(result) == "table" and type(result.data) == "table" then result.data else result
		if type(result) ~= "table" or result.ok ~= true or type(data) ~= "table" then
			self._failed[page] = true
			task.delay(RETRY_SECONDS, function()
				if generation == self._generation and self._open then
					self._failed[page] = nil
					self:_refreshRows()
				end
			end)
			return
		end
		if type(data.total) == "number" then
			self._total = math.max(0, math.floor(data.total))
		end
		local tracks = if type(data.tracks) == "table" then data.tracks else {}
		for position, track in ipairs(tracks) do
			self._cache[offset + position] = track
		end
		self._loaded[page] = true
		self:_applyTotal()
		self:_refreshRows()
	end)
end

function SetSheetView:_onSearchTyped()
	self._searchToken += 1
	local token = self._searchToken
	task.delay(SEARCH_DEBOUNCE, function()
		if token ~= self._searchToken or not self._open then
			return
		end
		local query = self._search.Text
		if query == self._query then
			return
		end
		self._query = query
		self:_reset(false)
	end)
end

-- ============================================================
-- Paint
-- ============================================================

function SetSheetView:_paintAccent()
	local accent = AccentService.get()
	self._accentFill = accent.fill
	self._summary.BackgroundColor3 = accent.fill
	for _, text in ipairs({ self._title, self._started, self._counter, self._songsLeft, self._back, self._reshuffle, self._removeSet }) do
		text.TextColor3 = accent.onFill
	end
	for _, pill in ipairs({ self._back, self._reshuffle, self._removeSet }) do
		local icon = pill:FindFirstChild("Icon")
		local label = pill:FindFirstChild("Label")
		if icon and icon:IsA("ImageLabel") then
			icon.ImageColor3 = accent.onFill
		end
		if label and label:IsA("TextLabel") then
			label.TextColor3 = accent.onFill
		end
	end
	self._fill.BackgroundColor3 = accent.onFill
	self._progressTrack.BackgroundColor3 = accent.onFill
	for _, row in ipairs(self._rows) do
		if row.index == 1 then
			row.number.TextColor3 = accent.fill
		end
	end
end

function SetSheetView:_paintHeader(set: any)
	local played = math.floor(tonumber(set.played) or 0)
	local total = math.floor(tonumber(set.total) or 0)
	Visuals.setText(self._title, tostring(set.title or ""))
	self._started.Text = SetCardView.startedText(tostring(set.starterName or ""))
	Visuals.setHeadshot(self._avatar, tonumber(set.starterUserId))
	Visuals.setText(self._counter, string.format("%d / %d", played, total))
	local left = math.max(0, total - played)
	Visuals.setText(self._songsLeft, string.format("%d %s left", left, if left == 1 then "song" else "songs"))
	local progress = if total > 0 then math.clamp(played / total, 0, 1) else 0
	self._fill.Size = UDim2.fromScale(progress, 1)
end

function SetSheetView:setControl(allowed: boolean)
	self._control = allowed
	self._actions.Visible = allowed
end

-- ============================================================
-- Fade (close fades the sheet's contents out together; open restores them)
-- ============================================================

function SetSheetView:_snapshotFade()
	table.clear(self._fade)
	local entries: { Fade } = {}
	table.insert(entries, { object = self._sheet, background = self._sheet.BackgroundTransparency })
	for _, d in ipairs(self._sheet:GetDescendants()) do
		if d:IsA("GuiObject") then
			local entry: Fade = { object = d, background = d.BackgroundTransparency }
			if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
				entry.text = d.TextTransparency
			end
			if d:IsA("ImageLabel") or d:IsA("ImageButton") then
				entry.image = d.ImageTransparency
			end
			table.insert(entries, entry)
		end
	end
	self._fade = entries
end

function SetSheetView:_restoreFade()
	for _, entry in ipairs(self._fade) do
		local object = entry.object
		object.BackgroundTransparency = entry.background
		if entry.text ~= nil then
			(object :: any).TextTransparency = entry.text
		end
		if entry.image ~= nil then
			(object :: any).ImageTransparency = entry.image
		end
	end
end

-- ============================================================
-- Open / close
-- ============================================================

-- Sizes the sheet to the panel and lays out the two columns. Narrow panels stack the controls over
-- the list instead of a 280 px column (not in the mock; phone widths only).
function SetSheetView:_layout()
	local main = self._main
	local size = main.AbsoluteSize
	self._sheet.Size = UDim2.fromOffset(size.X, size.Y - SHEET_OFFSET_Y)
	if size.X < NARROW_WIDTH then
		self._summary.Position = UDim2.fromOffset(0, 0)
		self._summary.Size = UDim2.new(1, 0, 0, NARROW_LEFT_HEIGHT)
		self._upNext.Position = UDim2.fromOffset(0, NARROW_LEFT_HEIGHT + GUTTER)
		self._upNext.Size = UDim2.new(1, 0, 1, -(NARROW_LEFT_HEIGHT + GUTTER))
	else
		self._summary.Position = UDim2.fromOffset(0, 0)
		self._summary.Size = UDim2.new(0, LEFT_WIDTH, 1, 0)
		self._upNext.Position = UDim2.fromOffset(LEFT_WIDTH + GUTTER, 0)
		self._upNext.Size = UDim2.new(1, -(LEFT_WIDTH + GUTTER), 1, 0)
	end
end

function SetSheetView:_scale(): UIScale
	local scale = self._main:FindFirstChild("SetSheetScale")
	if scale and scale:IsA("UIScale") then
		return scale :: UIScale
	end
	local created = Instance.new("UIScale")
	created.Name = "SetSheetScale"
	created.Parent = self._main
	return created
end

function SetSheetView:_play(object: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local tween = TweenService:Create(object, info, goal)
	table.insert(self._tweens, tween)
	tween:Play()
	return tween
end

function SetSheetView:_cancelMotion()
	for _, tween in ipairs(self._tweens) do
		tween:Cancel()
	end
	table.clear(self._tweens)
end

function SetSheetView:open()
	local set = self._store:get().activeSet
	if self._open or type(set) ~= "table" or not self._main.Visible then
		return
	end
	self._open = true
	self:_cancelMotion()
	self:_restoreFade()
	-- Measured at full scale, before the panel scales back, so the sheet covers the panel at rest.
	local scale = self:_scale()
	scale.Scale = 1
	local origin = self._main.AbsolutePosition
	self:_layout()
	self._gui.Enabled = true
	-- Shown at its slide-in start pose (the first frame of the animation), then one frame later the
	-- drift between the two ScreenGuis' insets is measured and the rest position corrected for it.
	local guess = UDim2.fromOffset(origin.X, origin.Y + SHEET_OFFSET_Y)
	self._rest = guess
	self._sheet.Position = guess + UDim2.fromOffset(0, SLIDE_PX)
	self._sheet.Visible = true
	self:_paintHeader(set)
	self:setControl(self._store:get().isControlAllowed == true)
	self:_reset(false)
	self._scrollHandle.flash(1.5)
	task.wait()
	if not self._open then
		return
	end
	local shown = self._sheet.Position
	local absolute = self._sheet.AbsolutePosition
	local drift = Vector2.new(absolute.X - shown.X.Offset, absolute.Y - shown.Y.Offset)
	self._rest = UDim2.fromOffset(origin.X - drift.X, origin.Y + SHEET_OFFSET_Y - drift.Y)
	self._sheet.Position = self._rest + UDim2.fromOffset(0, SLIDE_PX)
	self:_play(self._sheet, SHEET_TWEEN, { Position = self._rest })
	self:_play(self._dim, SHEET_TWEEN, { BackgroundTransparency = DIM_TRANSPARENCY })
	self:_play(scale, SHEET_TWEEN, { Scale = SCALE_OPEN })
end

function SetSheetView:close(immediate: boolean)
	if not self._open then
		return
	end
	self._open = false
	self._generation += 1
	self:_cancelMotion()
	local scale = self:_scale()
	if immediate then
		scale.Scale = 1
		self._dim.BackgroundTransparency = 1
		self._sheet.Visible = false
		self._gui.Enabled = false
		return
	end
	local slide = self:_play(self._sheet, SHEET_TWEEN, { Position = self._rest + UDim2.fromOffset(0, SLIDE_PX) })
	self:_play(self._dim, SHEET_TWEEN, { BackgroundTransparency = 1 })
	self:_play(scale, SHEET_TWEEN, { Scale = 1 })
	for _, entry in ipairs(self._fade) do
		local goal: { [string]: any } = { BackgroundTransparency = 1 }
		if entry.text ~= nil then
			goal.TextTransparency = 1
		end
		if entry.image ~= nil then
			goal.ImageTransparency = 1
		end
		self:_play(entry.object, SHEET_TWEEN, goal)
	end
	slide.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and not self._open then
			self._sheet.Visible = false
			self._gui.Enabled = false
		end
	end)
end

function SetSheetView:destroy()
	self:close(true)
	self:_cancelMotion()
	if self._accentUnsubscribe then
		self._accentUnsubscribe()
	end
	for _, unsubscribe in ipairs(self._unsubscribers) do
		unsubscribe()
	end
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._unsubscribers)
	table.clear(self._connections)
	self._scrollHandle.destroy()
	local scale = self._main:FindFirstChild("SetSheetScale")
	if scale then
		scale:Destroy()
	end
	self._gui:Destroy()
end

return SetSheetView
