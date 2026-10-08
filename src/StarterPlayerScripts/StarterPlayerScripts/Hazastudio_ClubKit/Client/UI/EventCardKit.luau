--!strict
-- Client/UI/EventCardKit.luau
-- Shared drawing for the event cards (CONTEXT.md "Event card"): the Event tab, the quest popup and
-- the reminders all paint the same Header + Body shape, the same dates, the same countdown and the
-- same attendance calendar. Display only; every value comes from the server's snapshot.
--
-- Attendance calendar contract: a `Cal` frame holding hidden tile templates — TileDone (with a
-- flame ImageLabel), TileToday (with a UIStroke ring), TileMissed, TileUpcoming (each with a
-- `Number` TextLabel), Chain, MarkerStart, MarkerFinish. Tiles are cloned into a `Painted` frame
-- and placed by code; their look is the design's.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local DailyQuestDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.DailyQuestDomain)
local UIMotion = require(script.Parent.Parent.Utils.UIMotion)

local cfg = Config.EventBoard

local EventCardKit = {}

EventCardKit.MONTHS = {
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
}

export type CalendarCell = { day: number, dom: number, month: number, year: number, state: string }
-- A long quest window comes as a 6-week span around today; clipped edges carry no START/FINISH.
export type Calendar = {
	leadBlanks: number,
	cells: { CalendarCell },
	todayIndex: number?,
	clippedStart: boolean?,
	clippedEnd: boolean?,
}

-- ── tree helpers ───────────────────────────────────────────────────────────────────────────

function EventCardKit.path(root: Instance?, ...: string): Instance?
	local node = root
	for _, name in ipairs({ ... }) do
		if not node then
			return nil
		end
		node = node:FindFirstChild(name)
	end
	return node
end

function EventCardKit.setText(root: Instance?, name: string, text: string)
	local label = root and root:FindFirstChild(name)
	if label and (label:IsA("TextLabel") or label:IsA("TextButton")) and (label :: TextLabel).Text ~= text then
		(label :: TextLabel).Text = text
	end
end

function EventCardKit.setVisible(root: Instance?, name: string, visible: boolean)
	local node = root and root:FindFirstChild(name)
	if node and node:IsA("GuiObject") then
		node.Visible = visible
	end
end

-- The card's button: Body > ButtonSlot > SubmitButton (centred in its slot so a press squashes it
-- from the middle), or anywhere below the card for older designs.
function EventCardKit.button(card: Instance): GuiButton?
	local button = EventCardKit.path(card, "Body", "ButtonSlot", "SubmitButton") or card:FindFirstChild("SubmitButton", true)
	if button and button:IsA("GuiButton") then
		return button
	end
	return nil
end

-- ── text ───────────────────────────────────────────────────────────────────────────────────

-- "A N N O U N C E M E N T S", the design's letter-spaced category line.
function EventCardKit.spaced(text: string): string
	local letters = {}
	for _, code in utf8.codes(string.upper(text)) do
		table.insert(letters, utf8.char(code))
	end
	return table.concat(letters, " ")
end

-- "YYYY-MM-DD" (WIB) → "October 20, 2026".
function EventCardKit.dateText(dateString: string): string
	local day = DailyQuestDomain.parseWibDate(dateString)
	if not day then
		return dateString
	end
	local y, m, d = DailyQuestDomain.toCivil(day)
	return string.format(cfg.DATE_FORMAT, EventCardKit.MONTHS[m], d, y)
end

-- Unix seconds → WIB parts. Plain arithmetic: os.date reads the client's own timezone.
local function wibParts(unix: number): (number, number, number, number, number)
	local wib = math.floor(unix) + 7 * 3600
	local y, m, d = DailyQuestDomain.toCivil(wib // 86400)
	local minutes = (wib % 86400) // 60
	return y, m, d, minutes // 60, minutes % 60
end

-- Unix seconds → "October 31, 2026 · 21:00 WIB".
function EventCardKit.momentText(unix: number): string
	local y, m, d, h, mi = wibParts(unix)
	return string.format("%s %d, %d · %02d:%02d WIB", EventCardKit.MONTHS[m], d, y, h, mi)
end

-- Unix seconds → "21:00".
function EventCardKit.clockText(unix: number): string
	local _, _, _, h, mi = wibParts(unix)
	return string.format("%02d:%02d", h, mi)
end

-- ISO timestamp from the API → "October 7, 2026 · 18:30 WIB".
function EventCardKit.publishedText(iso: string): string
	local y, mo, d, h, mi, s = string.match(iso, "^(%d+)-(%d+)-(%d+)T(%d+):(%d+):?(%d*)")
	if not y then
		return ""
	end
	local day = DailyQuestDomain.parseWibDate(string.format("%s-%s-%s", y, mo, d))
	if not day then
		return ""
	end
	local unix = day * 86400 + (tonumber(h) :: number) * 3600 + (tonumber(mi) :: number) * 60 + (tonumber(s) or 0)
	return EventCardKit.momentText(unix)
end

function EventCardKit.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
end

-- Seconds → { days, hours, minutes, seconds }.
function EventCardKit.countdownParts(seconds: number): { number }
	local s = math.max(0, math.floor(seconds))
	return { s // 86400, (s % 86400) // 3600, (s % 3600) // 60, s % 60 }
end

-- Seconds → "2d 4h", "4h 12m", "12m 5s" for one-line places (reminders).
function EventCardKit.shortDuration(seconds: number): string
	local p = EventCardKit.countdownParts(seconds)
	if p[1] > 0 then
		return string.format("%dd %dh", p[1], p[2])
	elseif p[2] > 0 then
		return string.format("%dh %dm", p[2], p[3])
	end
	return string.format("%dm %ds", p[3], p[4])
end

-- Text set while its ScreenGui was disabled keeps the size it was measured at (a wrapped title
-- stays one line tall) until something changes: re-arm every auto-sized label under `root` once
-- the GUI is on screen.
function EventCardKit.remeasure(root: Instance)
	for _, node in ipairs(root:GetDescendants()) do
		if node:IsA("TextLabel") and node.AutomaticSize ~= Enum.AutomaticSize.None then
			local mode = node.AutomaticSize
			node.AutomaticSize = Enum.AutomaticSize.None
			node.AutomaticSize = mode
		end
	end
end

-- Sizes a wrapped label to its text by hand. AutomaticSize.Y measures it one line tall when it
-- sits in an auto-sized column of a horizontal layout under a UIScale (the quest popup) — measured
-- 2026-10-07: 22 px with AutomaticSize, 66 px (three lines) once given room. TextBounds is in
-- unscaled pixels, so it can be written straight back to Size.
function EventCardKit.fitHeight(label: TextLabel)
	label.AutomaticSize = Enum.AutomaticSize.None
	label.Size = UDim2.new(label.Size.X.Scale, label.Size.X.Offset, 0, 1000)
	task.spawn(function()
		RunService.Heartbeat:Wait()
		if label.Parent then
			label.Size = UDim2.new(label.Size.X.Scale, label.Size.X.Offset, 0, math.ceil(label.TextBounds.Y))
		end
	end)
end

-- ── header ─────────────────────────────────────────────────────────────────────────────────

-- The header row (and its close button) carries a hint of the card's accent, read off the card's
-- Category line so it follows the theme engine's recolour of that line — and still shows on
-- Multicolor, where the engine tints nothing. Owner, 2026-10-07.
local HEADER_BASE = Color3.fromRGB(32, 32, 32)
local CLOSE_BASE = Color3.fromRGB(44, 44, 44)
local HEADER_MIX, CLOSE_MIX = 0.12, 0.16

function EventCardKit.tintHeader(card: Instance)
	local header = card:FindFirstChild("Header")
	local category = card:FindFirstChild("Category", true)
	if not (header and header:IsA("GuiObject") and category and category:IsA("TextLabel")) then
		return
	end
	local function apply()
		local accent = category.TextColor3
		header.BackgroundColor3 = HEADER_BASE:Lerp(accent, HEADER_MIX)
		local close = header:FindFirstChild("CloseWrapper")
		if close and close:IsA("GuiObject") then
			close.BackgroundColor3 = CLOSE_BASE:Lerp(accent, CLOSE_MIX)
		end
	end
	apply()
	-- The engine recolours the Category a frame after a clone and on every theme switch (and puts
	-- its own surface tint on the header then): follow it, once per card. Dies with the card.
	if header:GetAttribute("EventTintBound") ~= true then
		header:SetAttribute("EventTintBound", true)
		category:GetPropertyChangedSignal("TextColor3"):Connect(function()
			task.delay(0.1, function()
				if header.Parent then
					apply()
				end
			end)
		end)
	end
end

-- Header > Label, and Header > Icon when an image is given (the design keeps a placeholder).
function EventCardKit.paintHeader(card: Instance, label: string, image: string?)
	local header = card:FindFirstChild("Header")
	EventCardKit.tintHeader(card)
	EventCardKit.setText(header, "Label", label)
	local icon = header and header:FindFirstChild("Icon")
	if image and icon and icon:IsA("ImageLabel") then
		icon.Image = image
		local box = icon:FindFirstChild("Placeholder")
		if box and box:IsA("GuiObject") then
			box.Visible = image == ""
		end
	end
end

-- ── sparks ─────────────────────────────────────────────────────────────────────────────────

-- A burst of dots at `at` (AbsolutePosition space) on `layer`, a full-screen-origin GuiObject or
-- ScreenGui. Colours from the card's accent.
function EventCardKit.sparks(layer: Instance, at: Vector2, count: number, spread: number, color: Color3)
	if UIMotion.reduced() then
		return
	end
	local warm = color:Lerp(Color3.fromRGB(255, 225, 90), 0.6)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.random() * 0.5
		local size = math.random(3, 6)
		local spark = Instance.new("Frame")
		spark.Name = "EventSpark"
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		spark.Size = UDim2.fromOffset(size, size)
		spark.Position = UDim2.fromOffset(at.X, at.Y)
		spark.BackgroundColor3 = if i % 3 == 0 then warm else color
		spark.BorderSizePixel = 0
		spark.ZIndex = 60
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = spark
		spark.Parent = layer
		local distance = spread * (0.6 + math.random() * 0.4)
		local duration = 0.45 + math.random() * 0.25
		UIMotion.tween(spark, duration, {
			Position = spark.Position + UDim2.fromOffset(math.cos(angle) * distance, math.sin(angle) * distance),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(duration + 0.1, function()
			spark:Destroy()
		end)
	end
end

-- ── attendance calendar ────────────────────────────────────────────────────────────────────

local TILE_FOR_STATE = {
	done = "TileDone",
	today = "TileToday",
	missed = "TileMissed",
	upcoming = "TileUpcoming",
}

local function templates(cal: Instance): { [string]: GuiObject }
	local out = {}
	for _, name in ipairs({ "TileDone", "TileToday", "TileMissed", "TileUpcoming", "Chain", "MarkerStart", "MarkerFinish" }) do
		local t = cal:FindFirstChild(name)
		if t and t:IsA("GuiObject") then
			t.Visible = false
			out[name] = t
		end
	end
	return out
end

-- Swaying flame: each done tile breathes on its own beat so a row never moves in step.
local function sway(image: GuiObject)
	if UIMotion.reduced() then
		return
	end
	image.Rotation = -4
	TweenService:Create(
		image,
		TweenInfo.new(0.9 + math.random() * 0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Rotation = 4 }
	):Play()
end

export type PaintOptions = {
	weekOnly: boolean?, -- only the row holding today (or the window's first row before it starts)
	holdToday: boolean?, -- draw today as still open (a check-in flight is on its way)
}

-- Paints `calendar` into `cal`. Returns the tile per cell index and the row range drawn.
function EventCardKit.paintCalendar(cal: GuiObject, calendar: Calendar, options: PaintOptions?): { [number]: GuiObject }
	local opts = options or {}
	local t = templates(cal)
	local sample = t.TileUpcoming or t.TileDone
	if not sample then
		return {}
	end
	local painted = cal:FindFirstChild("Painted")
	if painted then
		painted:Destroy()
	end
	local layer = Instance.new("Frame")
	layer.Name = "Painted"
	layer.BackgroundTransparency = 1
	layer.Size = UDim2.fromScale(1, 1)
	layer.Parent = cal

	local cell = sample.Size.X.Offset
	local gap = cfg.CALENDAR_GAP
	local step = cell + gap
	local gridWidth = cell * 7 + gap * 6
	local designWidth = (cal :: GuiObject).Size.X.Offset
	local xo = math.max(0, math.floor(((if designWidth > 0 then designWidth else gridWidth) - gridWidth) / 2))

	local cells = calendar.cells
	local lead = calendar.leadBlanks
	local total = lead + #cells
	local firstRow, lastRow = 0, (total - 1) // 7
	if opts.weekOnly then
		local anchor = calendar.todayIndex or (if #cells > 0 and cells[1].state == "upcoming" then 1 else #cells)
		local row = (lead + anchor - 1) // 7
		firstRow, lastRow = row, row
	end
	local rows = lastRow - firstRow + 1
	-- Rings and markers sit just outside a tile; the frame keeps a few px for them.
	local pad = if opts.weekOnly then 3 else 0
	cal.Size = UDim2.new(cal.Size.X.Scale, cal.Size.X.Offset, 0, rows * step - gap + pad * 2)

	local function stateOf(index: number): string
		local c = cells[index]
		if opts.holdToday and calendar.todayIndex == index and c.state == "done" then
			return "today"
		end
		return c.state
	end
	local function place(index: number): (number, number)
		local i = lead + index - 1
		return i % 7, i // 7 - firstRow
	end

	-- Chains under consecutive done days, one capsule per run per row; a run that wraps keeps a
	-- flat end at the row edge so it reads as continuing.
	local chain = t.Chain
	if chain then
		local index = 1
		while index <= #cells do
			if stateOf(index) == "done" then
				local startIndex = index
				local _, row = place(index)
				while index + 1 <= #cells and stateOf(index + 1) == "done" and select(2, place(index + 1)) == row do
					index += 1
				end
				local c0 = place(startIndex)
				local c1 = place(index)
				if row >= 0 and row < rows then
					local piece = chain:Clone()
					piece.Name = "ChainPiece"
					piece.Visible = true
					piece.Position = UDim2.fromOffset(xo + c0 * step, pad + row * step)
					piece.Size = UDim2.fromOffset((c1 - c0) * step + cell, cell)
					piece.ZIndex = sample.ZIndex
					piece:SetAttribute("FirstIndex", startIndex)
					piece:SetAttribute("LastIndex", index)
					local function flat(right: boolean)
						local patch = Instance.new("Frame")
						patch.Name = if right then "FlatRight" else "FlatLeft"
						patch.BorderSizePixel = 0
						patch.BackgroundColor3 = piece.BackgroundColor3
						patch.BackgroundTransparency = piece.BackgroundTransparency
						patch.AnchorPoint = Vector2.new(if right then 1 else 0, 0)
						patch.Position = UDim2.fromScale(if right then 1 else 0, 0)
						patch.Size = UDim2.new(0, math.ceil(cell / 3), 1, 0)
						patch.ZIndex = piece.ZIndex
						patch.Parent = piece
					end
					if c0 == 0 and startIndex > 1 and stateOf(startIndex - 1) == "done" then
						flat(false)
					end
					if c1 == 6 and index < #cells and stateOf(index + 1) == "done" then
						flat(true)
					end
					piece.Parent = layer
				end
			end
			index += 1
		end
	end

	local tiles: { [number]: GuiObject } = {}
	for index, c in ipairs(cells) do
		local col, row = place(index)
		if row >= 0 and row < rows then
			local state = stateOf(index)
			local source = t[TILE_FOR_STATE[state]] or sample
			local tile = source:Clone()
			tile.Name = "Day" .. index
			tile.Visible = true
			tile.AnchorPoint = Vector2.new(0.5, 0.5)
			tile.Position = UDim2.fromOffset(xo + col * step + cell / 2, pad + row * step + cell / 2)
			tile.ZIndex = sample.ZIndex + 1
			EventCardKit.setText(tile, "Number", tostring(c.dom))
			local flame = tile:FindFirstChild("Flame")
			if flame and flame:IsA("GuiObject") then
				sway(flame)
			end
			local ring = tile:FindFirstChildWhichIsA("UIStroke")
			if ring and state == "today" and not UIMotion.reduced() then
				UIMotion.pulse(ring, "Transparency", 0.75, 1.1)
			end
			local function marker(name: string)
				local m = t[name]
				if m then
					local copy = m:Clone()
					copy.Name = name
					copy.Visible = true
					copy.Parent = tile
				end
			end
			if index == 1 and not calendar.clippedStart then
				marker("MarkerStart")
			end
			if index == #cells and not calendar.clippedEnd then
				marker("MarkerFinish")
			end
			tile.Parent = layer
			tiles[index] = tile
		end
	end
	return tiles
end

-- "This week · 4–10 October": the row the week view shows, clipped to the quest window.
function EventCardKit.weekText(calendar: Calendar): string
	local cells = calendar.cells
	if #cells == 0 then
		return ""
	end
	local anchor = calendar.todayIndex or (if cells[1].state == "upcoming" then 1 else #cells)
	local i = calendar.leadBlanks + anchor - 1
	local rowStart = i - i % 7
	local first = math.max(1, rowStart - calendar.leadBlanks + 1)
	local last = math.min(#cells, rowStart + 7 - calendar.leadBlanks)
	return string.format(cfg.WEEK_TEXT, cells[first].dom, cells[last].dom, EventCardKit.MONTHS[cells[last].month])
end

-- "October 2026" for the month the window (or today) sits in.
function EventCardKit.monthText(calendar: Calendar): string
	local cells = calendar.cells
	if #cells == 0 then
		return ""
	end
	local c = cells[calendar.todayIndex or 1]
	return string.format("%s %d", EventCardKit.MONTHS[c.month], c.year)
end

return EventCardKit
