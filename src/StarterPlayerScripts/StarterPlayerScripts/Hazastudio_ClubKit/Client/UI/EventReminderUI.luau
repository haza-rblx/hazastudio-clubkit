--!strict
-- Client/UI/EventReminderUI.luau
-- Reminders (CONTEXT.md "Reminder"): bottom-right notices for venue posts, countdowns and a streak
-- quest still waiting for today. Up to REMINDER_MAX_VISIBLE stacked — the front one whole, the
-- others peeking above it, darker; hovering any of them spreads the stack. More wait in a queue
-- behind a "+N" pill. Each card's line timer drains while the stack rests; nothing counts down
-- while it is spread out, hovered, or hidden behind the open menu.
--
-- GUI contract (StarterGui, Config.EventBoard.REMINDER_GUI):
--   ScreenGui > Templates > ReminderCard > Header > Icon / Label / CloseWrapper > CloseButton
--                                        > Body > Timer > Bar, Category, Main > Thumb /
--                                          Info > Title / Date, Text, ButtonSlot > SubmitButton
--             > More (the "+N" pill)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local UIMotion = require(script.Parent.Parent.Utils.UIMotion)
local EventCardKit = require(script.Parent.EventCardKit)

local cfg = Config.EventBoard
local path, setText, setVisible = EventCardKit.path, EventCardKit.setText, EventCardKit.setVisible
local RIGHT, BOTTOM = 16, 96 -- px from the screen corner; clear of the hotbar row
local GAP = 8 -- between spread cards
local SHRINK = 0.05 -- each card further back is this much smaller
local SLIDE = 40 -- px past the edge cards slide in from / out to
local TITLE_LINES, TEXT_LINES = 2, 3
local CORNER = 18 -- the cards' outer corner radius; clipped back cards stop this far above the front's bottom

export type Item = {
	key: string,
	header: string,
	icon: string?, -- image for the header icon slot; nil keeps the design's placeholder
	thumb: string?, -- small image left of the title
	category: string?,
	title: string,
	date: string?,
	text: string?,
	button: string?,
	onAction: (() -> ())?,
}

type Toast = {
	item: Item,
	holder: Frame,
	scale: UIScale,
	card: GuiObject,
	bar: GuiObject?,
	veil: Frame,
	height: number,
	left: number,
	hovered: boolean,
	gone: boolean,
}

local EventReminderUI = {}
EventReminderUI.__index = EventReminderUI

function EventReminderUI.tryCreate(playerGui: Instance): any?
	local gui = playerGui:FindFirstChild(cfg.REMINDER_GUI)
	local template = gui and path(gui, "Templates", "ReminderCard")
	if not (gui and gui:IsA("ScreenGui") and template and template:IsA("GuiObject")) then
		return nil
	end
	local self = setmetatable({}, EventReminderUI) :: any
	self._gui = gui
	self._template = template
	self._more = gui:FindFirstChild("More")
	self._toasts = {} :: { Toast }
	self._queue = {} :: { Item }
	self._shownKeys = {} :: { [string]: boolean }
	self._expanded = false
	self._hoverCount = 0
	self._suppressed = false
	self._connections = {} :: { RBXScriptConnection }
	template.Visible = false
	if self._more and self._more:IsA("GuiObject") then
		self._more.Visible = false
	end
	gui.Enabled = true
	table.insert(self._connections, RunService.Heartbeat:Connect(function(dt)
		self:_step(dt)
	end))
	return self
end

-- Hidden while the menu is open (its panels sit in the same corner); timers stop meanwhile.
function EventReminderUI:setSuppressed(suppressed: boolean)
	if self._suppressed == suppressed then
		return
	end
	self._suppressed = suppressed
	for _, t in ipairs(self._toasts) do
		t.holder.Visible = not suppressed
	end
	if self._more and self._more:IsA("GuiObject") then
		self._more.Visible = not suppressed and #self._queue > 0
	end
	if not suppressed then
		self:_layout()
	end
end

-- Trims `label` to `lines` lines, ending in "…" when it had to cut. TextFits only settles after a
-- render step, so this runs deferred.
local function clampLines(label: TextLabel, lines: number)
	local full = label.Text
	label.TextWrapped = true
	label.AutomaticSize = Enum.AutomaticSize.None
	label.Size = UDim2.new(1, 0, 0, math.ceil(label.TextSize * 1.25) * lines)
	task.spawn(function()
		RunService.Heartbeat:Wait()
		if not label.Parent or label.TextFits then
			-- Shrink to the lines it really uses.
			label.AutomaticSize = Enum.AutomaticSize.Y
			label.Size = UDim2.new(1, 0, 0, 0)
			return
		end
		local words = string.split(full, " ")
		local lo, hi = 1, #words
		while lo < hi do
			local mid = (lo + hi + 1) // 2
			label.Text = table.concat(words, " ", 1, mid) .. "…"
			RunService.Heartbeat:Wait()
			if not label.Parent then
				return
			end
			if label.TextFits then
				lo = mid
			else
				hi = mid - 1
			end
		end
		label.Text = table.concat(words, " ", 1, lo) .. "…"
	end)
end

function EventReminderUI:_build(item: Item): GuiObject
	local card = self._template:Clone()
	card.Name = "Card"
	card.Visible = true
	card.Position = UDim2.new()
	EventCardKit.paintHeader(card, item.header, item.icon)
	local body = card:FindFirstChild("Body")
	setText(body, "Category", if item.category and item.category ~= "" then EventCardKit.spaced(item.category) else "")
	setVisible(body, "Category", item.category ~= nil and item.category ~= "")
	local main = body and body:FindFirstChild("Main")
	local info = main and main:FindFirstChild("Info")
	setText(info, "Title", item.title)
	setText(info, "Date", item.date or "")
	setVisible(info, "Date", item.date ~= nil and item.date ~= "")
	local thumb = main and main:FindFirstChild("Thumb")
	if thumb and thumb:IsA("ImageLabel") then
		thumb.Visible = item.thumb ~= nil and item.thumb ~= ""
		thumb.Image = item.thumb or ""
	end
	setText(body, "Text", item.text or "")
	setVisible(body, "Text", item.text ~= nil and item.text ~= "")
	local slot = body and body:FindFirstChild("ButtonSlot")
	if slot and slot:IsA("GuiObject") then
		slot.Visible = item.button ~= nil
	end
	setText(EventCardKit.button(card), "TextLabel", item.button or "")
	local title = info and info:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		clampLines(title, TITLE_LINES)
	end
	local text = body and body:FindFirstChild("Text")
	if text and text:IsA("TextLabel") and item.text and item.text ~= "" then
		clampLines(text, TEXT_LINES)
	end
	return card
end

-- Queues `item` unless it is showing or already waiting (keys are once per session).
function EventReminderUI:push(item: Item)
	if self._shownKeys[item.key] then
		return
	end
	self._shownKeys[item.key] = true
	if #self._toasts >= cfg.REMINDER_MAX_VISIBLE then
		table.insert(self._queue, item)
		self:_layout()
		return
	end
	self:_show(item)
end

function EventReminderUI:_show(item: Item)
	local base = cfg.REMINDER_SCALE
	local width = self._template.Size.X.Offset
	local holder = Instance.new("Frame")
	holder.Name = "Reminder"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Size = UDim2.fromOffset(width, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.Position = UDim2.new(1, -RIGHT - width * base / 2 + width + SLIDE, 1, -BOTTOM)
	holder.Visible = not self._suppressed
	local scale = Instance.new("UIScale")
	scale.Scale = base
	scale.Parent = holder
	local card = self:_build(item)
	card.Parent = holder
	-- Darkens cards further back in the stack.
	local veil = Instance.new("Frame")
	veil.Name = "Veil"
	veil.BackgroundColor3 = Color3.new()
	veil.BackgroundTransparency = 1
	veil.Size = UDim2.fromScale(1, 1)
	veil.ZIndex = 50
	veil.Active = false
	local veilCorner = Instance.new("UICorner")
	veilCorner.CornerRadius = UDim.new(0, 18)
	veilCorner.Parent = veil
	veil.Parent = holder
	holder.Parent = self._gui

	local toast: Toast = {
		item = item,
		holder = holder,
		scale = scale,
		card = card,
		bar = path(card, "Body", "Timer", "Bar") :: GuiObject?,
		veil = veil,
		height = 0,
		left = cfg.REMINDER_SECONDS,
		hovered = false,
		gone = false,
	}
	table.insert(self._toasts, 1, toast)

	for _, part in ipairs({ card:FindFirstChild("Header"), card:FindFirstChild("Body") }) do
		if part and part:IsA("GuiObject") then
			table.insert(self._connections, part.MouseEnter:Connect(function()
				self:_hover(toast, true)
			end))
			table.insert(self._connections, part.MouseLeave:Connect(function()
				self:_hover(toast, false)
			end))
		end
	end
	local close = path(card, "Header", "CloseWrapper", "CloseButton")
	if close and close:IsA("GuiButton") then
		for _, c in ipairs(UIMotion.bindPress(close)) do
			table.insert(self._connections, c)
		end
		table.insert(self._connections, close.Activated:Connect(function()
			self:_remove(toast)
		end))
	end
	local button = EventCardKit.button(card)
	if button then
		for _, c in ipairs(UIMotion.bindPress(button)) do
			table.insert(self._connections, c)
		end
		table.insert(self._connections, button.Activated:Connect(function()
			if item.onAction then
				item.onAction()
			end
			self:_remove(toast)
		end))
	end
	-- The stack is laid out from each card's unscaled height, which settles only after the
	-- title/text clamps run: re-lay out whenever it really changes (not on every scale tween).
	local function measure()
		if toast.gone then
			return
		end
		local height = card.AbsoluteSize.Y / math.max(0.01, scale.Scale)
		if math.abs(height - toast.height) > 1 then
			toast.height = height
			self:_layout()
		end
	end
	table.insert(self._connections, card:GetPropertyChangedSignal("AbsoluteSize"):Connect(measure))
	task.defer(function()
		RunService.Heartbeat:Wait()
		measure()
	end)
end

function EventReminderUI:_hover(toast: Toast, on: boolean)
	if toast.hovered == on or toast.gone then
		return
	end
	toast.hovered = on
	self._hoverCount += if on then 1 else -1
	if on then
		if not self._expanded then
			self._expanded = true
			self:_layout()
		end
	else
		task.delay(0.15, function()
			if self._hoverCount <= 0 and self._expanded then
				self._hoverCount = 0
				self._expanded = false
				self:_layout()
			end
		end)
	end
end

function EventReminderUI:_layout()
	local base = cfg.REMINDER_SCALE
	local width = self._template.Size.X.Offset * base
	local x = UDim.new(1, -RIGHT - width / 2)
	local front = self._toasts[1]
	local frontH = if front then front.height * base else 0
	local acc, top = 0, 0
	for i, t in ipairs(self._toasts) do
		local h = t.height * base
		local y, s
		-- Collapsed, a card behind the front one is cut to a window that ends just above the front
		-- card's bottom corners and starts PEEK px above its top, so a taller card never shows below.
		local clip = not self._expanded and i > 1
		if self._expanded then
			y, s = -acc, 1
			acc += h + GAP
			top = y - h
		elseif i == 1 then
			y, s = 0, 1
			top = math.min(top, -h)
		else
			s = 1 - (i - 1) * SHRINK
			y = -CORNER
			top = math.min(top, -frontH - cfg.REMINDER_PEEK * (i - 1))
		end
		t.holder.ClipsDescendants = clip
		if clip then
			local window = (frontH + cfg.REMINDER_PEEK * (i - 1) - CORNER) / (base * s)
			t.holder.AutomaticSize = Enum.AutomaticSize.None
			t.holder.Size = UDim2.fromOffset(self._template.Size.X.Offset, math.max(0, window))
		else
			t.holder.AutomaticSize = Enum.AutomaticSize.Y
			t.holder.Size = UDim2.fromOffset(self._template.Size.X.Offset, 0)
		end
		t.holder.ZIndex = 100 - i
		t.veil.BackgroundTransparency = if self._expanded or i == 1 then 1 else 1 - math.min(0.5, 0.22 * (i - 1))
		UIMotion.tween(t.holder, 0.4, { Position = UDim2.new(x, UDim.new(1, -BOTTOM + y)) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		UIMotion.tween(t.scale, 0.4, { Scale = s * base }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end
	local more = self._more
	if more and more:IsA("TextLabel") then
		more.Visible = not self._suppressed and #self._queue > 0
		more.Text = string.format(cfg.REMINDER_MORE_TEXT, #self._queue)
		more.AnchorPoint = Vector2.new(1, 1)
		UIMotion.tween(more, 0.4, { Position = UDim2.new(1, -RIGHT, 1, -BOTTOM + top - 6) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end
end

function EventReminderUI:_remove(toast: Toast)
	if toast.gone then
		return
	end
	toast.gone = true
	local index = table.find(self._toasts, toast)
	if index then
		table.remove(self._toasts, index)
	end
	if toast.hovered then
		self._hoverCount = math.max(0, self._hoverCount - 1)
	end
	if self._hoverCount == 0 then
		self._expanded = false
	end
	local holder = toast.holder
	UIMotion.tween(holder, 0.35, { Position = holder.Position + UDim2.fromOffset(holder.AbsoluteSize.X + SLIDE, 0) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	task.delay(0.4, function()
		holder:Destroy()
	end)
	self:_layout()
	if #self._queue > 0 then
		local nextItem = table.remove(self._queue, 1) :: Item
		task.delay(0.3, function()
			self:_show(nextItem)
		end)
	end
end

function EventReminderUI:_step(dt: number)
	if self._suppressed or self._expanded then
		return
	end
	local front = self._toasts[1]
	if not front or front.height == 0 then
		return
	end
	front.left -= dt
	local bar = front.bar
	if bar then
		bar.Size = UDim2.new(math.max(0, front.left / cfg.REMINDER_SECONDS), 0, 1, 0)
	end
	if front.left <= 0 then
		self:_remove(front)
	end
end

function EventReminderUI:destroy()
	for _, c in ipairs(self._connections) do
		c:Disconnect()
	end
	table.clear(self._connections)
	for _, t in ipairs(self._toasts) do
		t.holder:Destroy()
	end
	table.clear(self._toasts)
	table.clear(self._queue)
end

return EventReminderUI
