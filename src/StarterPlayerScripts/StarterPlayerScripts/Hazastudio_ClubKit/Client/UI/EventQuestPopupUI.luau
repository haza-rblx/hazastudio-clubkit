--!strict
-- Client/UI/EventQuestPopupUI.luau
-- Quest popup (CONTEXT.md "Quest popup"): the wide detail of a streak venue quest — quest info and
-- the check-in button on the left, the attendance calendar on the right. Display only; the server
-- owns every value and sends a fresh snapshot after the check-in, which this module animates in:
-- a flame flies from the header into today's tile, the tile flips, the chain stretches to it.
--
-- GUI contract (StarterGui, Config.EventBoard.QUEST_POPUP_GUI):
--   ScreenGui > Wrapper (centred) > Card > Header > Icon / Label / CloseWrapper > CloseButton
--                                        > Main > Left > Category / Title / Date / Spacer /
--                                                 ProgressRow > Label / ValueSlot > Value,
--                                                 Bar > Fill, ButtonSlot > SubmitButton > TextLabel
--                                               > Right > Month / Weekdays / Cal (EventCardKit tiles)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local MotionPresets = require(script.Parent.Parent.Utils.MotionPresets)
local UIMotion = require(script.Parent.Parent.Utils.UIMotion)
local EventCardKit = require(script.Parent.EventCardKit)

local cfg = Config.EventBoard
local path, setText = EventCardKit.path, EventCardKit.setText
local DIM_TRANSPARENCY = 0.35
-- Phones (2026-10-09): the card is authored for desktop (508 px under a 1.1 UIScale) and outgrew a
-- phone screen. A centred full-screen stage above Wrapper carries a fit scale that shrinks it to
-- the screen with this margin; Wrapper's own UIScale stays the open/close motion's.
local FIT_MARGIN = 16
-- Status text widths (design px), measured once per text.
local statusWidths: { [string]: number } = {}

local EventQuestPopupUI = {}
EventQuestPopupUI.__index = EventQuestPopupUI

local function centre(object: GuiObject): Vector2
	return object.AbsolutePosition + object.AbsoluteSize * 0.5
end

function EventQuestPopupUI.tryCreate(playerGui: Instance): any?
	local gui = playerGui:FindFirstChild(cfg.QUEST_POPUP_GUI)
	if not (gui and gui:IsA("ScreenGui")) then
		return nil
	end
	local wrapper = gui:FindFirstChild("Wrapper")
	local card = path(wrapper, "Card")
	local left = path(card, "Main", "Left")
	local right = path(card, "Main", "Right")
	local cal = path(right, "Cal")
	if not (wrapper and wrapper:IsA("GuiObject") and left and right and cal and cal:IsA("GuiObject")) then
		return nil
	end
	local self = setmetatable({}, EventQuestPopupUI) :: any
	self._gui = gui
	self._wrapper = wrapper
	self._card = card
	self._left = left
	self._right = right
	self._cal = cal
	self._header = path(card, "Header")
	self._button = path(left, "ButtonSlot", "SubmitButton")
	self._connections = {} :: { RBXScriptConnection }
	self._quest = nil :: any
	self._questId = nil :: number?
	self._secondsToNextDay = 0
	self._stateAt = 0
	self._busy = false
	self._flying = false
	self._open = false
	self._openToken = 0
	self._onCheckIn = nil :: ((number) -> ())?
	self._onClaim = nil :: ((number) -> ())?
	self._tiles = {} :: { [number]: GuiObject }

	for i, name in ipairs(cfg.WEEKDAYS) do
		local weekdays = right:FindFirstChild("Weekdays")
		local labelNode = weekdays and weekdays:FindFirstChild("D" .. i)
		if labelNode and labelNode:IsA("TextLabel") then
			labelNode.Text = name
		end
	end
	self:_wire()

	local stage = Instance.new("Frame")
	stage.Name = "FitStage"
	stage.BackgroundTransparency = 1
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)
	stage.Size = UDim2.fromScale(1, 1)
	local fitScale = Instance.new("UIScale")
	fitScale.Name = "FitScale"
	fitScale.Parent = stage
	stage.Parent = gui
	wrapper.Parent = stage
	self._fitScale = fitScale
	local wrapperScale = wrapper:FindFirstChildWhichIsA("UIScale")
	self._wrapperRest = if wrapperScale then wrapperScale.Scale else 1
	self:_track((card :: GuiObject):GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_fit()
	end))
	self:_track(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_fit()
	end))

	gui.Enabled = false
	return self
end

-- Shrinks (never grows) the stage until the card, at Wrapper's resting scale, fits the screen.
-- AbsoluteSize already carries both live scales, so dividing by them gives the design size even
-- while the open pop is running.
function EventQuestPopupUI:_fit()
	local card = self._card :: GuiObject
	local fit = self._fitScale :: UIScale
	local wrapperScale = self._wrapper:FindFirstChildWhichIsA("UIScale")
	local live = fit.Scale * (if wrapperScale then wrapperScale.Scale else 1)
	local size = card.AbsoluteSize
	local room = (self._gui :: ScreenGui).AbsoluteSize
	if live <= 0 or size.X <= 0 or size.Y <= 0 or room.X <= 0 or room.Y <= 0 then
		return
	end
	local full = size / live * self._wrapperRest
	local wanted = math.clamp(
		math.min((room.X - 2 * FIT_MARGIN) / full.X, (room.Y - 2 * FIT_MARGIN) / full.Y),
		0.3,
		1
	)
	if math.abs(wanted - fit.Scale) > 0.002 then
		fit.Scale = wanted
	end
end

function EventQuestPopupUI:_track(conn: RBXScriptConnection)
	table.insert(self._connections, conn)
end

function EventQuestPopupUI:_wire()
	local button = self._button
	if button and button:IsA("GuiButton") then
		for _, c in ipairs(UIMotion.bindPress(button)) do
			self:_track(c)
		end
		for _, c in ipairs(UIMotion.bindHover(button)) do
			self:_track(c)
		end
		self:_track(button.Activated:Connect(function()
			local quest = self._quest
			if not quest or self._busy or self._flying then
				return
			end
			-- A claimable milestone: one press checks in (if not yet today) and claims it.
			if quest.claimableMilestoneId and quest.checkedInToday then
				self._busy = true
				self:_paintButton()
				if self._onClaim then
					self._onClaim(quest.id)
				end
			elseif not quest.checkedInToday and (not quest.complete or quest.claimableMilestoneId) then
				self._busy = true
				self:_paintButton()
				if self._onCheckIn then
					self._onCheckIn(quest.id)
				end
			end
		end))
	end
	local close = path(self._header, "CloseWrapper", "CloseButton")
	if close and close:IsA("GuiButton") then
		for _, c in ipairs(UIMotion.bindPress(close)) do
			self:_track(c)
		end
		self:_track(close.Activated:Connect(function()
			self:close()
		end))
	end
end

function EventQuestPopupUI:onCheckIn(callback: (number) -> ())
	self._onCheckIn = callback
end

function EventQuestPopupUI:onClaim(callback: (number) -> ())
	self._onClaim = callback
end

function EventQuestPopupUI:isOpen(): boolean
	return self._open
end

function EventQuestPopupUI:questId(): number?
	return self._questId
end

-- ── paint ─────────────────────────────────────────────────────────────────────────────────

function EventQuestPopupUI:_paintButton()
	local quest = self._quest
	local button = self._button
	if not quest or not button then
		return
	end
	local text: string
	local active = false
	local left = self._secondsToNextDay - (os.clock() - self._stateAt)
	if self._busy then
		text = cfg.BUTTON_BUSY
	elseif quest.claimableMilestoneId or (quest.claimOnCheckIn and not quest.checkedInToday) then
		text, active = quest.claimLabel or cfg.BUTTON_CLAIM, true
	elseif quest.claimed or quest.complete then
		-- Every milestone claimed, or the rest can no longer be (slots full, Robux already held).
		text = cfg.BUTTON_CLAIMED
	elseif quest.checkedInToday then
		text = string.format(cfg.BUTTON_CHECKED_IN, EventCardKit.clock(left))
	else
		text, active = string.format(cfg.BUTTON_CHECK_IN, EventCardKit.clock(left)), true
	end
	setText(button, "TextLabel", text)
	local label = button:FindFirstChild("TextLabel")
	if label and label:IsA("TextLabel") then
		local goal = if active then 0 else DIM_TRANSPARENCY
		if label.TextTransparency ~= goal then
			UIMotion.tween(label, 0.2, { TextTransparency = goal })
		end
	end
	if button:IsA("GuiButton") then
		button.AutoButtonColor = false
	end
end

-- ── milestones (2026-10-08) ─────────────────────────────────────────────────────────────────
-- A list under the due date, one row per milestone: marker dot, "7 days · 50 Robux", status on
-- the right (slots left / Claimed / Slots full / 1 Robux reward per player). Drawn from the
-- design's own ProgressRow (font, colours), or from a `Milestones > MilestoneTemplate` row when
-- the GUI ships one. A quest with one milestone shows no list.

local function milestoneStatusText(row: any): string
	if row.status == "claimed" then
		return cfg.MILESTONE_CLAIMED_TEXT
	elseif row.status == "full" then
		return cfg.MILESTONE_FULL_TEXT
	elseif row.status == "robux_taken" then
		return cfg.MILESTONE_ROBUX_TAKEN_TEXT
	elseif row.quota and row.remaining then
		return string.format(cfg.MILESTONE_SLOTS_TEXT, row.remaining, row.quota)
	end
	return ""
end

function EventQuestPopupUI:_milestoneList(): Frame?
	local left = self._left
	local existing = left:FindFirstChild("Milestones")
	if existing and existing:IsA("Frame") then
		return existing
	end
	local progressRow = left:FindFirstChild("ProgressRow")
	local label = path(progressRow, "Label")
	local value = path(progressRow, "ValueSlot", "Value")
	local fill = path(left, "Bar", "Fill")
	local track = left:FindFirstChild("Bar")
	if not (label and label:IsA("TextLabel") and value and value:IsA("TextLabel") and fill and fill:IsA("Frame") and track and track:IsA("Frame")) then
		return nil
	end
	local list = Instance.new("Frame")
	list.Name = "Milestones"
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(1, 0, 0, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.LayoutOrder = 45
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.Parent = list

	local template = Instance.new("Frame")
	template.Name = "MilestoneTemplate"
	template.BackgroundTransparency = 1
	template.Size = UDim2.new(1, 0, 0, progressRow and (progressRow :: Frame).Size.Y.Offset or 16)
	template.Visible = false
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.Position = UDim2.fromScale(0, 0.5)
	dot.Size = UDim2.fromOffset(6, 6)
	dot.BorderSizePixel = 0
	dot.BackgroundColor3 = track.BackgroundColor3
	dot.BackgroundTransparency = track.BackgroundTransparency
	dot:SetAttribute("OnColor", fill.BackgroundColor3)
	dot:SetAttribute("OffColor", track.BackgroundColor3)
	dot:SetAttribute("OffTransparency", track.BackgroundTransparency)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot
	dot.Parent = template
	local name = label:Clone()
	name.Name = "Label"
	name.AnchorPoint = Vector2.new(0, 0.5)
	name.Position = UDim2.new(0, 12, 0.5, 0)
	name.Parent = template
	-- The label is truncated before the status, never drawn under it (sized per row on paint).
	name.AutomaticSize = Enum.AutomaticSize.Y
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Size = UDim2.new(1, -12, 0, 0)
	local status = value:Clone()
	status.Name = "Status"
	status.AutomaticSize = Enum.AutomaticSize.X
	status.Size = UDim2.fromScale(0, 1)
	status.AnchorPoint = Vector2.new(1, 0.5)
	status.Position = UDim2.fromScale(1, 0.5)
	status.TextXAlignment = Enum.TextXAlignment.Right
	status.Parent = template
	template.Parent = list
	list.Parent = left
	return list
end

function EventQuestPopupUI:_paintMilestones()
	local quest = self._quest
	local milestones = quest and quest.milestones or {}
	local list = self:_milestoneList()
	if not list then
		return
	end
	for _, child in ipairs(list:GetChildren()) do
		if child.Name == "MilestoneRow" then
			child:Destroy()
		end
	end
	list.Visible = #milestones > 1
	if #milestones <= 1 then
		return
	end
	local template = list:FindFirstChild("MilestoneTemplate")
	if not (template and template:IsA("GuiObject")) then
		return
	end
	local accent = Color3.new(1, 1, 1)
	local category = self._left:FindFirstChild("Category")
	if category and category:IsA("TextLabel") then
		accent = category.TextColor3
	end
	local unit = cfg.MILESTONE_UNIT[quest.goalType] or "%d"
	for index, row in ipairs(milestones) do
		local copy = template:Clone()
		copy.Name = "MilestoneRow"
		copy.LayoutOrder = index
		copy.Visible = true
		local rowUnit = if row.value == 1 and cfg.MILESTONE_UNIT_ONE then cfg.MILESTONE_UNIT_ONE[quest.goalType] or unit else unit
		setText(copy, "Label", string.format(rowUnit, row.value) .. " · " .. row.rewardLabel)
		local statusText = milestoneStatusText(row)
		setText(copy, "Status", statusText)
		local reached = quest.current >= row.value or row.status == "claimed"
		local dot = copy:FindFirstChild("Dot")
		if dot and dot:IsA("Frame") then
			dot.BackgroundColor3 = if reached then dot:GetAttribute("OnColor") :: Color3 else dot:GetAttribute("OffColor") :: Color3
			dot.BackgroundTransparency = if reached then 0 else dot:GetAttribute("OffTransparency") :: number
		end
		local status = copy:FindFirstChild("Status")
		if status and status:IsA("TextLabel") then
			if row.status == "claimable" then
				status.TextColor3 = accent
			end
			if row.status == "full" or row.status == "robux_taken" or row.status == "claimed" then
				status.TextTransparency = DIM_TRANSPARENCY
			end
		end
		copy.Parent = list
		local name = copy:FindFirstChild("Label")
		if statusText ~= "" and name and name:IsA("TextLabel") and status and status:IsA("TextLabel") then
			local function fit(width: number)
				name.Size = UDim2.new(1, -(12 + math.ceil(width) + 6), 0, 0)
			end
			local known = statusWidths[statusText]
			if known then
				fit(known)
			else
				local fontFace, textSize = status.FontFace, status.TextSize
				task.spawn(function()
					local params = Instance.new("GetTextBoundsParams")
					params.Text = statusText
					params.Font = fontFace
					params.Size = textSize
					params.Width = 1000
					local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
					local width = if ok then bounds.X else #statusText * textSize * 0.6
					statusWidths[statusText] = width
					if name.Parent then
						fit(width)
					end
				end)
			end
		end
	end
end

-- Calendar badges: the day each open milestone lands if the streak holds from today.
function EventQuestPopupUI:_badges(): { [number]: string }?
	local quest = self._quest
	local calendar = quest and quest.calendar
	if not (calendar and calendar.todayIndex and quest.milestones and #quest.milestones > 1) then
		return nil
	end
	local badges: { [number]: string } = {}
	for _, row in ipairs(quest.milestones) do
		if row.status ~= "claimed" and row.value > quest.current then
			local offset = row.value - quest.current - (if quest.checkedInToday then 0 else 1)
			local index = calendar.todayIndex + offset
			if index >= 1 and index <= #calendar.cells then
				badges[index] = if row.rewardType == "robux"
					then "R$" .. row.rewardValue
					elseif row.rewardType == "xp" then row.rewardValue .. " XP"
					else "REWARD"
			end
		end
	end
	return badges
end

-- Both columns end on one bottom line: the left column's Spacer takes up the difference.
function EventQuestPopupUI:_balance()
	local spacer = self._left:FindFirstChild("Spacer")
	local leftLayout = self._left:FindFirstChildWhichIsA("UIListLayout")
	local rightLayout = self._right:FindFirstChildWhichIsA("UIListLayout")
	if not (spacer and spacer:IsA("GuiObject") and leftLayout and rightLayout) then
		return
	end
	spacer.Size = UDim2.new(1, 0, 0, 0)
	task.spawn(function()
		-- Two frames: the layouts settle one frame after a repaint (or after the GUI turns on).
		RunService.Heartbeat:Wait()
		RunService.Heartbeat:Wait()
		if not spacer.Parent or not self._gui.Enabled then
			return
		end
		-- AbsoluteContentSize is in screen pixels; undo any UIScale above.
		local scale = self._wrapper.AbsoluteSize.X / math.max(1, (self._wrapper :: GuiObject).Size.X.Offset)
		if (self._wrapper :: GuiObject).Size.X.Offset <= 0 then
			scale = 1
			local s = self._wrapper:FindFirstChildWhichIsA("UIScale")
			if s then
				scale = s.Scale
			end
		end
		local lh = leftLayout.AbsoluteContentSize.Y / scale
		local rh = rightLayout.AbsoluteContentSize.Y / scale
		spacer.Size = UDim2.new(1, 0, 0, math.max(0, math.floor(rh - lh)))
	end)
end

function EventQuestPopupUI:_paint(holdToday: boolean?)
	local quest = self._quest
	if not quest then
		return
	end
	local left = self._left
	EventCardKit.paintHeader(self._card, cfg.HEADER_LABELS.streak)
	setText(left, "Category", EventCardKit.spaced(if quest.category ~= "" then quest.category else "Quest"))
	setText(left, "Title", if quest.description ~= "" then quest.description else quest.title)
	local title = left:FindFirstChild("Title")
	if title and title:IsA("TextLabel") and self._gui.Enabled then
		EventCardKit.fitHeight(title)
	end
	setText(left, "Date", string.format(cfg.DUE_DATE_TEXT, EventCardKit.dateText(quest.dueDate)))
	self:_paintMilestones()
	local row = left:FindFirstChild("ProgressRow")
	setText(row, "Label", string.format(cfg.PROGRESS_TEXT, ""))
	local shown = quest.current
	if holdToday then
		shown = math.max(0, shown - 1)
	end
	local valueText = string.format("%d/%d", shown, quest.target)
	local slot = row and row:FindFirstChild("ValueSlot")
	setText(slot, "Value", valueText)
	if slot and slot:IsA("GuiObject") then
		local value = slot:FindFirstChild("Value")
		if value and value:IsA("TextLabel") then
			slot.Size = UDim2.new(0, math.ceil(value.TextBounds.X) + 4, 1, 0)
		end
	end
	local fill = path(left, "Bar", "Fill")
	if fill and fill:IsA("GuiObject") then
		local ratio = if quest.target > 0 then math.clamp(shown / quest.target, 0, 1) else 0
		UIMotion.tween(fill, 0.6, { Size = UDim2.new(ratio, 0, 1, 0) }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	end
	local calendar = quest.calendar
	if calendar then
		setText(self._right, "Month", EventCardKit.monthText(calendar))
		self._tiles = EventCardKit.paintCalendar(self._cal, calendar, { holdToday = holdToday, badges = self:_badges() })
	end
	self:_paintButton()
	self:_balance()
end

-- `quest` is the streak QuestState from the server snapshot.
function EventQuestPopupUI:setQuest(quest: any, secondsToNextDay: number)
	local previous = self._quest
	local landing = previous ~= nil
		and self._open
		and previous.id == quest.id
		and previous.checkedInToday ~= true
		and quest.checkedInToday == true
	self._quest = quest
	self._questId = quest.id
	self._secondsToNextDay = secondsToNextDay
	self._stateAt = os.clock()
	self._busy = false
	if landing and quest.calendar and quest.calendar.todayIndex then
		self:_paint(true)
		self:_fly(quest.calendar.todayIndex)
	elseif not self._flying then
		self:_paint(false)
	end
end

-- ── check-in flight ─────────────────────────────────────────────────────────────────────────

function EventQuestPopupUI:_fly(todayIndex: number)
	local source = path(self._header, "Icon")
	local target = self._tiles[todayIndex]
	if UIMotion.reduced() or not (source and source:IsA("ImageLabel")) or not target then
		self:_land(todayIndex)
		return
	end
	self._flying = true
	local from = centre(source)
	local fromSize = source.AbsoluteSize
	local flame = Instance.new("ImageLabel")
	flame.Name = "EventCheckInFlight"
	flame.BackgroundTransparency = 1
	flame.AnchorPoint = Vector2.new(0.5, 0.5)
	flame.Image = source.Image
	flame.ImageColor3 = source.ImageColor3
	flame.ScaleType = Enum.ScaleType.Fit
	flame.Size = UDim2.fromOffset(fromSize.X, fromSize.Y)
	flame.Position = UDim2.fromOffset(from.X, from.Y)
	flame.ZIndex = 50
	flame.Parent = self._gui
	-- One alpha drives the bowed path; the end is re-read each frame (the card may still settle).
	local alpha = Instance.new("NumberValue")
	local conn = alpha:GetPropertyChangedSignal("Value"):Connect(function()
		local t = alpha.Value
		local tile = self._tiles[todayIndex]
		local to = if tile and tile.Parent then centre(tile) else from
		local toSize = if tile then tile.AbsoluteSize else fromSize
		local control = (from + to) * 0.5 - Vector2.new(0, cfg.FLIGHT_ARC)
		local u = 1 - t
		local p = from * (u * u) + control * (2 * u * t) + to * (t * t)
		local size = fromSize:Lerp(toSize * 0.9, t) * (1 + 0.35 * math.sin(t * math.pi))
		flame.Position = UDim2.fromOffset(p.X, p.Y)
		flame.Size = UDim2.fromOffset(size.X, size.Y)
		flame.Rotation = math.sin(t * math.pi) * 22
	end)
	-- Parented: UIMotion.tween snaps an instance that is not in the tree.
	alpha.Parent = flame
	UIMotion.tween(alpha, cfg.FLIGHT_TIME, { Value = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	task.delay(MotionPresets.scaledTime(cfg.FLIGHT_TIME), function()
		conn:Disconnect()
		flame:Destroy()
		self._flying = false
		self:_land(todayIndex)
	end)
end

function EventQuestPopupUI:_land(todayIndex: number)
	self:_paint(false)
	local tile = self._tiles[todayIndex]
	if not tile then
		return
	end
	-- The chain that now ends on today stretches out to it.
	local layer = self._cal:FindFirstChild("Painted")
	if layer and not UIMotion.reduced() then
		for _, piece in ipairs(layer:GetChildren()) do
			if piece:IsA("GuiObject") and piece:GetAttribute("LastIndex") == todayIndex and piece:GetAttribute("FirstIndex") ~= todayIndex then
				local full = piece.Size
				local step = tile.AbsoluteSize.X / math.max(0.01, tile.AbsoluteSize.X / full.Y.Offset) + cfg.CALENDAR_GAP
				piece.Size = UDim2.fromOffset(full.X.Offset - step, full.Y.Offset)
				UIMotion.tween(piece, 0.35, { Size = full }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			end
		end
	end
	UIMotion.pop(tile, 1.18, 0.2)
	local flame = tile:FindFirstChild("Flame")
	if flame and flame:IsA("GuiObject") then
		UIMotion.popIn(flame, 0.2)
	end
	local accent = Color3.new(1, 0.6, 0.2)
	local category = self._left:FindFirstChild("Category")
	if category and category:IsA("TextLabel") then
		accent = category.TextColor3
	end
	EventCardKit.sparks(self._gui, centre(tile), cfg.LAND_SPARKS, tile.AbsoluteSize.X, accent)
	local value = path(self._left, "ProgressRow", "ValueSlot", "Value")
	if value and value:IsA("GuiObject") then
		UIMotion.pop(value, 1.3, 0.2)
	end
end

-- ── open / close ────────────────────────────────────────────────────────────────────────────

function EventQuestPopupUI:open()
	if not self._quest then
		return
	end
	self._openToken += 1
	self._open = true
	self._gui.Enabled = true
	self:_paint(false)
	UIMotion.popIn(self._wrapper :: GuiObject, 0.92)
end

function EventQuestPopupUI:close()
	if not self._open then
		return
	end
	self._open = false
	self._openToken += 1
	local token = self._openToken
	local scale = self._wrapper:FindFirstChildWhichIsA("UIScale")
	if scale and not UIMotion.reduced() then
		local rest = scale.Scale
		UIMotion.tween(scale, 0.18, { Scale = rest * 0.94 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(MotionPresets.scaledTime(0.18), function()
			if self._openToken == token then
				self._gui.Enabled = false
				scale.Scale = rest
			end
		end)
	else
		self._gui.Enabled = false
	end
end

-- Button countdown, about once a second while open.
function EventQuestPopupUI:tick()
	if self._open then
		self:_paintButton()
	end
end

function EventQuestPopupUI:destroy()
	self._open = false
	for _, c in ipairs(self._connections) do
		c:Disconnect()
	end
	table.clear(self._connections)
end

return EventQuestPopupUI
