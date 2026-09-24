--!strict
-- Client/UI/DailyQuestUI.luau
-- Drives the buyer-installed `1000-02-DQ-ADDON` ScreenGui: quest copy, progress bar, one day
-- circle per target day, and the daily check-in button. Display only — the server owns every
-- number here and sends a whole snapshot (DailyQuestService.Snapshot) after each change.
--
-- The grid is laid out by a UIGridLayout, so no circle is ever moved or scaled: the check-in
-- flight is a separate ImageLabel on this ScreenGui that travels from the streak overlay's
-- flame to today's circle, and the circle only changes template when it lands (ADR 0011).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local MotionPresets = require(script.Parent.Parent.Utils.MotionPresets)
local UIMotion = require(script.Parent.Parent.Utils.UIMotion)

local SPARK_COLORS = { Color3.fromRGB(255, 180, 30), Color3.fromRGB(255, 220, 60), Color3.fromRGB(255, 100, 0) }
local OPEN_OFFSET = 28 -- px the card rises from when it opens
local DISABLED_TEXT_TRANSPARENCY = 0.35

local DailyQuestUI = {}
DailyQuestUI.__index = DailyQuestUI

local function findPath(root: Instance?, ...: string): Instance?
	local node = root
	for _, name in ipairs({ ... }) do
		if not node then
			return nil
		end
		node = node:FindFirstChild(name)
	end
	return node
end

local function formatClock(seconds: number, withSeconds: boolean): string
	local s = math.max(0, math.floor(seconds))
	local h, m = s // 3600, (s % 3600) // 60
	if withSeconds then
		return string.format("%02d:%02d:%02d", h, m, s % 60)
	end
	return string.format("%02d:%02d", h, m)
end

-- Centre of a GuiObject in AbsolutePosition space. Every kit ScreenGui reports from the same
-- inset origin whatever its IgnoreGuiInset (measured: viewport Y = AbsolutePosition.Y + inset for
-- both kinds), so a point read under 05-StreakGUI is a valid offset inside this ScreenGui.
local function screenCenter(object: GuiObject): Vector2
	return object.AbsolutePosition + object.AbsoluteSize * 0.5
end

function DailyQuestUI.tryCreate(playerGui: Instance): any?
	local gui = playerGui:FindFirstChild(Config.DailyQuest.GUI_NAME)
	if not gui or not gui:IsA("ScreenGui") then
		return nil
	end
	local wrapper = gui:FindFirstChild("Wrapper")
	local main = findPath(wrapper, "MainWrapper", "Main")
	local grid = findPath(main, "Grid")
	local action = findPath(main, "ActionButton")
	local complete = findPath(grid, "MarkComplete")
	local progress = findPath(grid, "MarkProgress")
	local incomplete = findPath(grid, "MarkIncomplete")
	if
		not (wrapper and wrapper:IsA("GuiObject"))
		or not (grid and grid:IsA("GuiObject"))
		or not (action and action:IsA("GuiButton"))
		or not (complete and complete:IsA("GuiObject"))
		or not (progress and progress:IsA("GuiObject"))
		or not (incomplete and incomplete:IsA("GuiObject"))
	then
		return nil
	end

	local self = setmetatable({}, DailyQuestUI) :: any
	self._gui = gui
	self._wrapper = wrapper
	self._grid = grid
	self._action = action
	self._actionLabel = action:FindFirstChildWhichIsA("TextLabel")
	self._category = findPath(main, "Category")
	self._dueDate = findPath(main, "DueDate")
	self._title = findPath(main, "QuestTitle")
	self._progressTitle = findPath(main, "ProgressTitle")
	self._barFill = findPath(main, "Progressbar", "Frame")
	self._close = findPath(wrapper, "01-DraggableFrame", "CloseWrapper", "CloseButton")
	self._dragHandle = findPath(wrapper, "01-DraggableFrame", "DraggableIcon")

	-- Templates leave the tree; the grid is rebuilt from them. Every other GuiObject in the grid
	-- is template filler from the design file.
	self._templates = {
		complete = (complete :: GuiObject):Clone(),
		progress = (progress :: GuiObject):Clone(),
		incomplete = (incomplete :: GuiObject):Clone(),
	}
	for _, child in ipairs(grid:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	self._cells = {} :: { GuiObject }
	self._cellKinds = {} :: { string }

	self._restPosition = (wrapper :: GuiObject).Position
	self._open = false
	self._openToken = 0
	self._busy = false
	self._state = nil :: any
	self._stateAt = 0
	self._holdIndex = nil :: number?
	self._checkInCallback = nil :: (() -> ())?
	self._closedCallback = nil :: (() -> ())?
	self._dayTurnedCallback = nil :: (() -> ())?
	self._connections = {} :: { RBXScriptConnection }
	self._ticker = nil :: thread?

	if self._category and self._category:IsA("TextLabel") then
		self._category.Text = Config.DailyQuest.CATEGORY_TEXT
	end
	self:_wire()
	gui.Enabled = true
	;(wrapper :: GuiObject).Visible = false
	return self
end

function DailyQuestUI:_track(conn: RBXScriptConnection)
	table.insert(self._connections, conn)
end

function DailyQuestUI:_wire()
	local action = self._action :: GuiButton
	for _, conn in ipairs(UIMotion.bindPress(action)) do
		self:_track(conn)
	end
	for _, conn in ipairs(UIMotion.bindHover(action)) do
		self:_track(conn)
	end
	self:_track(action.Activated:Connect(function()
		local state = self._state
		if self._busy or not state or state.checkedInToday or self._holdIndex then
			return
		end
		if self._checkInCallback then
			self:setBusy(true)
			self._checkInCallback()
		end
	end))

	local close = self._close
	if close and close:IsA("GuiButton") then
		for _, conn in ipairs(UIMotion.bindPress(close)) do
			self:_track(conn)
		end
		self:_track(close.Activated:Connect(function()
			self:close()
		end))
	end

	-- Drag by the handle when the design shows one (the template ships it hidden).
	local handle = self._dragHandle
	if handle and handle:IsA("GuiObject") then
		local dragging: InputObject? = nil
		local startPointer = Vector2.zero
		local startPosition = self._restPosition
		self:_track(handle.InputBegan:Connect(function(input: InputObject)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				dragging = input
				startPointer = Vector2.new(input.Position.X, input.Position.Y)
				startPosition = self._wrapper.Position
			end
		end))
		self:_track(UserInputService.InputChanged:Connect(function(input: InputObject)
			if not dragging then
				return
			end
			local t = input.UserInputType
			if t ~= Enum.UserInputType.MouseMovement and input ~= dragging then
				return
			end
			local delta = Vector2.new(input.Position.X, input.Position.Y) - startPointer
			local nextPosition = startPosition + UDim2.fromOffset(delta.X, delta.Y)
			self._wrapper.Position = nextPosition
			self._restPosition = nextPosition
		end))
		self:_track(UserInputService.InputEnded:Connect(function(input: InputObject)
			if input == dragging or input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = nil
			end
		end))
	end
end

function DailyQuestUI:onCheckIn(callback: () -> ())
	self._checkInCallback = callback
end

function DailyQuestUI:onClosed(callback: () -> ())
	self._closedCallback = callback
end

function DailyQuestUI:isOpen(): boolean
	return self._open
end

function DailyQuestUI:setBusy(busy: boolean)
	self._busy = busy
	self:_paintButton()
end

-- ============================================================
-- Paint
-- ============================================================

-- `holdToday`: the check-in that produced this state is still flying — paint today's circle as
-- it was until `landFlight` fills it.
function DailyQuestUI:setState(state: any, holdToday: boolean?)
	if type(state) ~= "table" then
		return
	end
	self._state = state
	self._stateAt = os.clock()
	self._busy = false
	self._holdIndex = if holdToday and (tonumber(state.progress) or 0) > 0 then state.progress else nil
	self:_paint()
end

function DailyQuestUI:_setText(label: Instance?, text: string)
	if label and label:IsA("TextLabel") and label.Text ~= text then
		label.Text = text
	end
end

function DailyQuestUI:_shownProgress(): number
	local state = self._state
	local progress = tonumber(state and state.progress) or 0
	if self._holdIndex then
		progress = math.max(0, progress - 1)
	end
	return progress
end

function DailyQuestUI:_paint()
	local state = self._state
	if not state then
		return
	end
	local cfg = Config.DailyQuest
	local target = tonumber(state.target) or 0
	local progress = self:_shownProgress()

	self:_setText(self._title, tostring(state.title or ""))
	if state.status == "upcoming" then
		self:_setText(self._dueDate, cfg.STATUS_UPCOMING)
	elseif state.status == "ended" then
		self:_setText(self._dueDate, cfg.STATUS_ENDED)
	elseif state.status == "none" then
		self:_setText(self._dueDate, cfg.STATUS_NONE)
	elseif type(state.dueDate) == "table" then
		local y, m, d = state.dueDate[1], state.dueDate[2], state.dueDate[3]
		local month = cfg.MONTH_NAMES[m] or tostring(m)
		self:_setText(self._dueDate, cfg.DUE_DATE_TEXT:format(string.format("%s %d %d", month, d, y)))
	end
	self:_setText(self._progressTitle, cfg.PROGRESS_TEXT:format(progress, target))

	local fill = self._barFill
	if fill and fill:IsA("GuiObject") then
		local ratio = if target > 0 then math.clamp(progress / target, 0, 1) else 0
		local goal = UDim2.new(ratio, 0, fill.Size.Y.Scale, fill.Size.Y.Offset)
		if fill.Size ~= goal then
			UIMotion.tween(fill, 0.45, { Size = goal }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		end
	end

	self:_paintCells(target, progress)
	self:_paintButton()
end

function DailyQuestUI:_paintCells(target: number, progress: number)
	local state = self._state
	local todayIndex = if state.status == "active" and not state.checkedInToday then progress + 1 else nil
	if self._holdIndex then
		todayIndex = self._holdIndex
	end
	for i = 1, target do
		local kind = if i <= progress then "complete" elseif i == todayIndex then "progress" else "incomplete"
		if self._cellKinds[i] ~= kind then
			local old = self._cells[i]
			local cell = (self._templates[kind] :: GuiObject):Clone()
			cell.Name = "Day" .. tostring(i)
			cell.LayoutOrder = i
			local label = cell:FindFirstChildWhichIsA("TextLabel")
			if label then
				label.Text = string.format("%02d", i)
			end
			cell.Parent = self._grid
			if old then
				old:Destroy()
			end
			self._cells[i] = cell
			self._cellKinds[i] = kind
		end
	end
	for i = #self._cells, target + 1, -1 do
		self._cells[i]:Destroy()
		self._cells[i] = nil
		self._cellKinds[i] = nil
	end
end

function DailyQuestUI:_secondsToReset(): number
	local state = self._state
	local seconds = tonumber(state and state.secondsToReset) or 0
	return seconds - (os.clock() - self._stateAt)
end

function DailyQuestUI:_paintButton()
	local state = self._state
	local cfg = Config.DailyQuest
	local text: string
	local enabled = false
	if not state then
		text = cfg.BUTTON_BUSY
	elseif self._busy then
		text = cfg.BUTTON_BUSY
	elseif state.checkedInToday then
		text = if state.status == "completed"
			then cfg.BUTTON_COMPLETED
			else cfg.BUTTON_WAIT:format(formatClock(self:_secondsToReset(), true))
	else
		text = cfg.BUTTON_CHECK_IN:format(formatClock(self:_secondsToReset(), false))
		enabled = self._holdIndex == nil
	end
	self:_setText(self._actionLabel, text)
	local action = self._action :: GuiButton
	action.AutoButtonColor = enabled
	local label = self._actionLabel
	if label then
		local goal = if enabled then 0 else DISABLED_TEXT_TRANSPARENCY
		if label.TextTransparency ~= goal then
			UIMotion.tween(label, 0.2, { TextTransparency = goal })
		end
	end
end

-- One repaint a second while open: the countdown, and a sync request when the WIB day turns.
function DailyQuestUI:_startTicker()
	if self._ticker then
		return
	end
	self._ticker = task.spawn(function()
		local asked = false
		while self._open do
			self:_paintButton()
			if self._state and self:_secondsToReset() <= 0 and not asked then
				asked = true
				if self._dayTurnedCallback then
					self._dayTurnedCallback()
				end
			elseif self._state and self:_secondsToReset() > 0 then
				asked = false
			end
			task.wait(1)
		end
		self._ticker = nil
	end)
end

function DailyQuestUI:onDayTurned(callback: () -> ())
	self._dayTurnedCallback = callback
end

-- ============================================================
-- Open / close
-- ============================================================

function DailyQuestUI:open()
	if self._open then
		return
	end
	self._open = true
	self._openToken += 1
	local wrapper = self._wrapper :: GuiObject
	self._gui.Enabled = true
	wrapper.Visible = true
	wrapper.Position = self._restPosition + UDim2.fromOffset(0, OPEN_OFFSET)
	UIMotion.tween(wrapper, 0.4, { Position = self._restPosition }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	self:_paint()
	self:_startTicker()
end

function DailyQuestUI:close()
	if not self._open then
		return
	end
	self._open = false
	self._openToken += 1
	local token = self._openToken
	local wrapper = self._wrapper :: GuiObject
	UIMotion.tween(
		wrapper,
		0.22,
		{ Position = self._restPosition + UDim2.fromOffset(0, OPEN_OFFSET) },
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	task.delay(if UIMotion.reduced() then 0 else MotionPresets.scaledTime(0.22), function()
		if self._openToken ~= token then
			return
		end
		wrapper.Visible = false
		wrapper.Position = self._restPosition
	end)
	if self._closedCallback then
		self._closedCallback()
	end
end

-- ============================================================
-- Check-in flight
-- ============================================================

function DailyQuestUI:_sparks(at: Vector2, count: number, spread: number)
	if UIMotion.reduced() then
		return
	end
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.random() * 0.5
		local size = math.random(3, 6)
		local spark = Instance.new("Frame")
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		spark.Size = UDim2.fromOffset(size, size)
		spark.Position = UDim2.fromOffset(at.X, at.Y)
		spark.BackgroundColor3 = SPARK_COLORS[math.random(1, #SPARK_COLORS)]
		spark.BorderSizePixel = 0
		spark.ZIndex = 50
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = spark
		spark.Parent = self._gui
		local distance = spread * (0.6 + math.random() * 0.4)
		local duration = 0.45 + math.random() * 0.25
		UIMotion.tween(spark, duration, {
			Position = spark.Position + UDim2.fromOffset(math.cos(angle) * distance, math.sin(angle) * distance),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(MotionPresets.scaledTime(duration), function()
			spark:Destroy()
		end)
	end
end

-- Fly a copy of `source` (the streak overlay's flame) into today's circle, then fill it.
-- Safe to call with no hold pending: it just repaints.
function DailyQuestUI:flyFrom(source: ImageLabel)
	local index = self._holdIndex
	if not index then
		self:_paint()
		return
	end
	if not self._open then
		self:open()
	end
	local cfg = Config.DailyQuest
	local cell = self._cells[index]
	if UIMotion.reduced() or not cell or not source.Parent then
		self:_land(index)
		return
	end

	local from = screenCenter(source)
	local fromSize = source.AbsoluteSize
	local flame = Instance.new("ImageLabel")
	flame.Name = "DailyQuestFlight"
	flame.BackgroundTransparency = 1
	flame.AnchorPoint = Vector2.new(0.5, 0.5)
	flame.Image = source.Image
	flame.ImageColor3 = source.ImageColor3
	flame.ScaleType = Enum.ScaleType.Fit
	flame.Size = UDim2.fromOffset(fromSize.X, fromSize.Y)
	flame.Position = UDim2.fromOffset(from.X, from.Y)
	flame.ZIndex = 40
	flame.Parent = self._gui

	-- Driven by one alpha so the path can bow (quadratic Bezier) while the size shrinks.
	-- The end point is re-read every frame: the card may still be sliding open.
	local alpha = Instance.new("NumberValue")
	local conn = alpha:GetPropertyChangedSignal("Value"):Connect(function()
		if not flame.Parent then
			return
		end
		local t = alpha.Value
		local target = self._cells[index]
		local to = if target and target.Parent then screenCenter(target) else from
		local toSize = if target then target.AbsoluteSize else Vector2.new(38, 38)
		local control = (from + to) * 0.5 - Vector2.new(0, cfg.FLIGHT_ARC)
		local u = 1 - t
		local p = from * (u * u) + control * (2 * u * t) + to * (t * t)
		local size = fromSize:Lerp(toSize, t)
		flame.Position = UDim2.fromOffset(p.X, p.Y)
		flame.Size = UDim2.fromOffset(size.X, size.Y)
		flame.Rotation = math.sin(t * math.pi) * 18
	end)
	-- Parented: UIMotion.tween snaps an instance that is not in the tree.
	alpha.Parent = flame
	UIMotion.tween(alpha, cfg.FLIGHT_TIME, { Value = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	task.delay(MotionPresets.scaledTime(cfg.FLIGHT_TIME), function()
		conn:Disconnect()
		flame:Destroy()
		self:_land(index)
	end)
end

function DailyQuestUI:_land(index: number)
	if self._holdIndex ~= index then
		return
	end
	self._holdIndex = nil
	self:_paint()
	local cell = self._cells[index]
	if not cell then
		return
	end
	local image = cell:FindFirstChildWhichIsA("ImageLabel")
	UIMotion.wiggle(image or cell, 14)
	self:_sparks(screenCenter(cell), Config.DailyQuest.LAND_SPARKS, cell.AbsoluteSize.X * 1.2)
	if self._state and self._state.status == "completed" then
		local header = findPath(self._wrapper, "Header", "ImageLabel")
		if header and header:IsA("GuiObject") then
			UIMotion.spin(header)
		end
		local card = findPath(self._wrapper, "MainWrapper")
		if card and card:IsA("GuiObject") then
			self:_sparks(screenCenter(card), Config.DailyQuest.LAND_SPARKS * 3, card.AbsoluteSize.X * 0.7)
		end
	end
end

function DailyQuestUI:destroy()
	self._open = false
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	table.clear(self._connections)
end

return DailyQuestUI
