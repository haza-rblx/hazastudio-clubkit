--!strict
-- Client/UI/EventTabUI.luau
-- Event board (ADR 0015): paints the menu's EventTab (07-MenuGUI) and the post popup.
-- Display only — the server sends a whole snapshot (EventBoardController.buildState) after every
-- change and decides every number; this module only draws it and reports presses.
--
-- GUI contract (names in Config.EventBoard):
--   EventTab (ScrollingFrame) > PostsSection / QuestsSection (Frame)
--     > SectionIdentity > SectionTitle / SectionSubtitle
--     > SectionContentWrapper > BasicAnnouncement / ImageAnnouncement / CountdownTemplate /
--       QuestTemplate / StreakTemplate
--   Every card is an Event card (CONTEXT.md): Header > Icon / Label, and Body > Category / Title /
--   Date, then its own block — Text, Banner, Tiles > Days|Hours|Minutes|Seconds > Num / Unit plus
--   a Live label, ProgressRow > Label / Value and Bar > Fill, Week > WeekLabel / Weekdays / Cal —
--   and ButtonSlot > SubmitButton > TextLabel.
--   PopUpMenuTemplate (07-MenuGUI root) > Wrapper > Content > Category / Title / DatePublished /
--   Body, and Wrapper > SubmitButton.
-- The templates stay in the tree hidden; cards are clones. A place with only one "Section" gets
-- both kinds of card in it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local UIMotion = require(script.Parent.Parent.Utils.UIMotion)
local EventCardKit = require(script.Parent.EventCardKit)

local cfg = Config.EventBoard
local path, setText, setVisible = EventCardKit.path, EventCardKit.setText, EventCardKit.setVisible
local CARD_PREFIX = "EventCard_"
local POPUP_GUI_NAME = "EventBoardPopupGui"
local POPUP_DISPLAY_ORDER = 120
local DIM_TRANSPARENCY = 0.35
local TILE_NAMES = { "Days", "Hours", "Minutes", "Seconds" }

export type PostState = {
	id: number,
	kind: string,
	category: string,
	title: string,
	body: string,
	imageAssetId: string,
	publishedAt: string,
	startsAt: number?,
	endsAt: number?,
	robloxEventId: string,
}

export type QuestState = {
	id: number,
	category: string,
	title: string,
	description: string,
	goalType: string,
	goalValue: number,
	rewardType: string,
	rewardValue: string,
	startDate: string?,
	dueDate: string,
	current: number,
	target: number,
	complete: boolean,
	claimed: boolean,
	checkedInToday: boolean,
	calendar: EventCardKit.Calendar?,
	-- Milestones (2026-10-08): the first one claimable now, or one today's check-in reaches.
	milestones: { any }?,
	claimableMilestoneId: number?,
	claimOnCheckIn: boolean?,
	claimLabel: string?,
}

export type State = {
	serverTime: number,
	secondsToNextDay: number,
	posts: { PostState },
	quests: { QuestState },
	joinPostId: number?,
	unseenPostIds: { number }?,
}

local EventTabUI = {}
EventTabUI.__index = EventTabUI

-- "LV 5/5", "1/3 days", "40/100 Robux", "30/60 min".
local function progressText(goalType: string, current: number, target: number): string
	if goalType == "level" then
		return string.format("LV %d/%d", current, target)
	elseif goalType == "streak" then
		return string.format("%d/%d %s", current, target, if target == 1 then "day" else "days")
	elseif goalType == "robux" then
		return string.format("%d/%d Robux", current, target)
	end
	return string.format("%d/%d min", current, target)
end

function EventTabUI.tryCreate(playerGui: PlayerGui): any?
	local menuGui = playerGui:FindFirstChild(Config.Settings and Config.Settings.GUI_NAME or "07-MenuGUI")
		or playerGui:FindFirstChild("07-MenuGUI")
	local tab = menuGui and menuGui:FindFirstChild(cfg.TAB_NAME, true)
	if not (tab and tab:IsA("GuiObject")) then
		return nil
	end
	local postsSection = tab:FindFirstChild(cfg.POSTS_SECTION) or tab:FindFirstChild("Section")
	local questsSection = tab:FindFirstChild(cfg.QUESTS_SECTION) or postsSection
	local postsWrapper = path(postsSection, "SectionContentWrapper")
	local questsWrapper = path(questsSection, "SectionContentWrapper")
	if not postsWrapper or not questsWrapper then
		return nil
	end

	local function template(name: string): GuiObject?
		local found = postsWrapper:FindFirstChild(name) or questsWrapper:FindFirstChild(name)
		if found and found:IsA("GuiObject") then
			found.Visible = false
			return found
		end
		return nil
	end

	local self = setmetatable({}, EventTabUI)
	self._tab = tab :: GuiObject
	self._menuGui = menuGui :: ScreenGui
	self._postsSection = postsSection
	self._questsSection = questsSection
	self._postsWrapper = postsWrapper
	self._questsWrapper = questsWrapper
	self._templates = {
		basic = template(cfg.TEMPLATES.BASIC),
		image = template(cfg.TEMPLATES.IMAGE),
		countdown = template(cfg.TEMPLATES.COUNTDOWN),
		quest = template(cfg.TEMPLATES.QUEST),
		streak = template(cfg.TEMPLATES.STREAK),
	}
	self._cards = {} :: { [string]: GuiObject }
	self._connections = {} :: { RBXScriptConnection }
	self._state = nil :: State?
	self._stateReceivedAt = 0
	self._busy = {} :: { [number]: boolean }
	self._notified = {} :: { [number]: boolean }
	self._onClaim = nil :: ((number) -> ())?
	self._onOpenQuest = nil :: ((number) -> ())?
	self._onNotify = nil :: ((number) -> ())?
	self._onPostSeen = nil :: ((number) -> ())?
	self._popup = nil :: GuiObject?
	self._popupGui = nil :: ScreenGui?
	self._popupPostId = nil :: number?

	if postsSection ~= questsSection then
		local identity = path(postsSection, "SectionIdentity")
		setText(identity, "SectionTitle", cfg.SECTION_TITLES.posts)
		setText(identity, "SectionSubtitle", cfg.SECTION_SUBTITLES.posts)
		local questIdentity = path(questsSection, "SectionIdentity")
		setText(questIdentity, "SectionTitle", cfg.SECTION_TITLES.quests)
		setText(questIdentity, "SectionSubtitle", cfg.SECTION_SUBTITLES.quests)
	end

	self:_buildPopup(menuGui :: Instance)
	return self
end

function EventTabUI:onClaim(callback: (number) -> ())
	self._onClaim = callback
end

-- A streak card's "View details": the controller opens the quest popup.
function EventTabUI:onOpenQuest(callback: (number) -> ())
	self._onOpenQuest = callback
end

-- A countdown card's "Notify me" (only shown when the post links a Roblox Event).
function EventTabUI:onNotify(callback: (number) -> ())
	self._onNotify = callback
end

function EventTabUI:onPostSeen(callback: (number) -> ())
	self._onPostSeen = callback
end

function EventTabUI:getTab(): GuiObject
	return self._tab
end

function EventTabUI:getState(): State?
	return self._state
end

-- Server time now, from the last snapshot.
function EventTabUI:now(): number
	local state = self._state
	if not state then
		return os.time()
	end
	return state.serverTime + (os.clock() - self._stateReceivedAt)
end

-- RSVP state for a countdown's linked Roblox Event, as Roblox reported it.
function EventTabUI:setNotified(postId: number, going: boolean)
	self._notified[postId] = going
	local card = self._cards["post_" .. postId]
	local post = self:postById(postId)
	if card and post then
		self:_paintCountdownButton(card, post)
	end
end

-- ── popup ─────────────────────────────────────────────────────────────────────────────────

function EventTabUI:_buildPopup(menuGui: Instance)
	local source = menuGui:FindFirstChild(cfg.POPUP_NAME)
	if not (source and source:IsA("GuiObject")) then
		return
	end
	source.Visible = false
	-- Its own ScreenGui: the menu's is disabled while the menu is closed.
	local playerGui = menuGui.Parent
	local existing = playerGui and playerGui:FindFirstChild(POPUP_GUI_NAME)
	if existing then
		existing:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = POPUP_GUI_NAME
	gui.ResetOnSpawn = false
	gui.DisplayOrder = POPUP_DISPLAY_ORDER
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	local popup = source:Clone()
	popup.Name = "Popup"
	popup.Visible = true
	popup.Parent = gui
	gui.Parent = playerGui
	self._popupGui = gui
	self._popup = popup

	local button = path(popup, "Wrapper", "SubmitButton")
	if button and button:IsA("GuiButton") then
		setText(button, "TextLabel", cfg.BUTTON_CLOSE_POPUP)
		for _, c in ipairs(UIMotion.bindPress(button)) do
			table.insert(self._connections, c)
		end
		for _, c in ipairs(UIMotion.bindHover(button)) do
			table.insert(self._connections, c)
		end
		table.insert(self._connections, (button :: GuiButton).Activated:Connect(function()
			self:closePopup()
		end))
	end
end

function EventTabUI:postById(postId: number): PostState?
	local state = self._state
	if not state then
		return nil
	end
	for _, post in ipairs(state.posts) do
		if post.id == postId then
			return post
		end
	end
	return nil
end

function EventTabUI:openPost(postId: number)
	local post = self:postById(postId)
	if not post or not self._popup or not self._popupGui then
		return
	end
	local content = path(self._popup, "Wrapper", "Content")
	setText(content, "Category", if post.category ~= "" then EventCardKit.spaced(post.category) else "")
	setVisible(content, "Category", post.category ~= "")
	setText(content, "Title", post.title)
	setText(content, "DatePublished", self:_postDate(post))
	setText(content, "Body", post.body)
	setVisible(content, "Body", post.body ~= "")
	self._popupPostId = post.id
	self._popupGui.Enabled = true
	UIMotion.popIn(self._popup :: GuiObject, 0.94)
	if self._onPostSeen then
		self._onPostSeen(post.id)
	end
end

function EventTabUI:closePopup()
	if self._popupGui then
		self._popupGui.Enabled = false
	end
	self._popupPostId = nil
end

-- ── cards ─────────────────────────────────────────────────────────────────────────────────

function EventTabUI:_bindButton(card: GuiObject, onPress: () -> ())
	local button = EventCardKit.button(card)
	if not button then
		return
	end
	for _, c in ipairs(UIMotion.bindPress(button)) do
		table.insert(self._connections, c)
	end
	for _, c in ipairs(UIMotion.bindHover(button)) do
		table.insert(self._connections, c)
	end
	table.insert(self._connections, button.Activated:Connect(onPress))
end

function EventTabUI:_card(key: string, templateName: string, parent: Instance, build: (GuiObject) -> ()): GuiObject?
	local existing = self._cards[key]
	if existing and existing.Parent == parent and existing:GetAttribute("EventTemplate") == templateName then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local source = self._templates[templateName]
	if not source then
		return nil
	end
	local card = source:Clone()
	card.Name = CARD_PREFIX .. key
	card:SetAttribute("EventTemplate", templateName)
	card.Visible = true
	card.Parent = parent
	build(card)
	self._cards[key] = card
	return card
end

function EventTabUI:_postDate(post: PostState): string
	if post.kind == "countdown" and post.startsAt then
		return EventCardKit.momentText(post.startsAt)
	end
	return EventCardKit.publishedText(post.publishedAt)
end

function EventTabUI:_paintPost(post: PostState, order: number)
	local templateName = "basic"
	if post.kind == "countdown" and self._templates.countdown then
		templateName = "countdown"
	elseif post.imageAssetId ~= "" and self._templates.image then
		templateName = "image"
	end
	local card = self:_card("post_" .. post.id, templateName, self._postsWrapper, function(card)
		local postId = post.id
		self:_bindButton(card, function()
			local current = self:postById(postId)
			if not current then
				return
			end
			if current.kind == "countdown" and self:_countdownPhase(current) == "upcoming" then
				if current.robloxEventId ~= "" and self._onNotify then
					self._onNotify(postId)
				end
				return
			end
			self:openPost(postId)
		end)
	end)
	if not card then
		return
	end
	card.LayoutOrder = order
	EventCardKit.paintHeader(card, if post.kind == "countdown" then cfg.HEADER_LABELS.countdown else cfg.HEADER_LABELS.announcement)
	local body = card:FindFirstChild("Body")
	setText(body, "Category", if post.category ~= "" then EventCardKit.spaced(post.category) else "")
	setVisible(body, "Category", post.category ~= "")
	setText(body, "Title", post.title)
	setText(body, "Date", self:_postDate(post))
	setText(body, "Text", post.body)
	setVisible(body, "Text", post.body ~= "" and post.kind ~= "countdown")
	local banner = body and body:FindFirstChild("Banner")
	if banner and banner:IsA("ImageLabel") then
		banner.Image = if post.imageAssetId ~= "" then "rbxassetid://" .. post.imageAssetId else ""
		banner.ScaleType = Enum.ScaleType.Crop
		banner.Visible = post.imageAssetId ~= ""
	end
	if post.kind == "countdown" then
		self:_paintCountdown(card, post)
	else
		setText(EventCardKit.button(card), "TextLabel", cfg.BUTTON_OPEN_POST)
	end
end

function EventTabUI:_countdownPhase(post: PostState): string
	local now = self:now()
	if post.startsAt and now < post.startsAt then
		return "upcoming"
	elseif post.endsAt and now >= post.endsAt then
		return "ended"
	end
	return "live"
end

function EventTabUI:_paintCountdownButton(card: GuiObject, post: PostState)
	local phase = self:_countdownPhase(post)
	local slot = path(card, "Body", "ButtonSlot")
	local button = EventCardKit.button(card)
	if phase == "upcoming" then
		local linked = post.robloxEventId ~= ""
		if slot and slot:IsA("GuiObject") then
			slot.Visible = linked
		end
		if linked and button then
			local going = self._notified[post.id] == true
			setText(button, "TextLabel", if going then cfg.BUTTON_NOTIFIED else cfg.BUTTON_NOTIFY)
			-- Going reads as done: the design's quiet look (Outline stroke on, fill off).
			local outline = button:FindFirstChild("Outline")
			if outline and outline:IsA("UIStroke") then
				outline.Enabled = going
			end
			button.BackgroundTransparency = if going then 1 else 0
			for _, g in ipairs(button:GetChildren()) do
				if g:IsA("UIGradient") then
					g.Enabled = not going
				end
			end
		end
	else
		if slot and slot:IsA("GuiObject") then
			slot.Visible = true
		end
		if button then
			setText(button, "TextLabel", cfg.BUTTON_DETAIL)
			button.BackgroundTransparency = 0
			local outline = button:FindFirstChild("Outline")
			if outline and outline:IsA("UIStroke") then
				outline.Enabled = false
			end
			for _, g in ipairs(button:GetChildren()) do
				if g:IsA("UIGradient") then
					g.Enabled = true
				end
			end
		end
	end
end

-- Tiles count down to the start; after it, one LIVE line until the end.
function EventTabUI:_paintCountdown(card: GuiObject, post: PostState)
	local body = card:FindFirstChild("Body")
	local tiles = body and body:FindFirstChild("Tiles")
	local phase = self:_countdownPhase(post)
	if tiles and tiles:IsA("GuiObject") then
		tiles.Visible = phase == "upcoming"
		if phase == "upcoming" and post.startsAt then
			local parts = EventCardKit.countdownParts(post.startsAt - self:now())
			for i, name in ipairs(TILE_NAMES) do
				local tile = tiles:FindFirstChild(name)
				local num = tile and tile:FindFirstChild("Num")
				if num and num:IsA("TextLabel") then
					local text = string.format("%02d", parts[i])
					if num.Text ~= text then
						local first = num.Text == "" or num:GetAttribute("EventPainted") ~= true
						num.Text = text
						num:SetAttribute("EventPainted", true)
						if not first then
							UIMotion.pop(num, 1.12, 0.14)
						end
					end
				end
				setText(tile, "Unit", cfg.COUNTDOWN_UNITS[i])
			end
		end
	end
	local live = body and body:FindFirstChild("Live")
	if live and live:IsA("TextLabel") then
		live.Visible = phase == "live"
		if post.endsAt then
			live.Text = string.format(cfg.COUNTDOWN_LIVE_TEXT, EventCardKit.clockText(post.endsAt))
		end
	end
	self:_paintCountdownButton(card, post)
end

function EventTabUI:_questButtonText(quest: QuestState): (string, boolean)
	if self._busy[quest.id] then
		return cfg.BUTTON_BUSY, false
	end
	-- A milestone to claim (a streak card opens the popup, where the claim happens).
	if quest.claimableMilestoneId or (quest.claimOnCheckIn and not quest.checkedInToday) then
		return quest.claimLabel or cfg.BUTTON_CLAIM, true
	end
	if quest.claimed then
		return cfg.BUTTON_CLAIMED, false
	end
	if quest.goalType == "streak" then
		return cfg.BUTTON_DETAIL, true
	end
	if quest.complete then
		-- Reached, but what is left can no longer be claimed (slots full, Robux already held).
		return cfg.BUTTON_CLAIMED, false
	end
	return cfg.BUTTON_INCOMPLETE, false
end

function EventTabUI:_paintQuestButton(card: GuiObject, quest: QuestState)
	local button = EventCardKit.button(card)
	if not button then
		return
	end
	local text, active = self:_questButtonText(quest)
	setText(button, "TextLabel", text)
	local label = button:FindFirstChild("TextLabel")
	if label and label:IsA("TextLabel") then
		label.TextTransparency = if active then 0 else DIM_TRANSPARENCY
	end
	button.AutoButtonColor = false
	button:SetAttribute("EventActionable", active)
end

function EventTabUI:_paintQuest(quest: QuestState, order: number)
	local templateName = if quest.goalType == "streak" and self._templates.streak then "streak" else "quest"
	local card = self:_card("quest_" .. quest.id, templateName, self._questsWrapper, function(card)
		local questId = quest.id
		self:_bindButton(card, function()
			local button = EventCardKit.button(card)
			if not button or button:GetAttribute("EventActionable") ~= true then
				return
			end
			local current = self:_questById(questId)
			if not current then
				return
			end
			if current.goalType ~= "streak" and current.claimableMilestoneId then
				self._busy[questId] = true
				self:_paintQuestButton(card, current)
				if self._onClaim then
					self._onClaim(questId)
				end
			elseif current.goalType == "streak" and self._onOpenQuest then
				self._onOpenQuest(questId)
			end
		end)
	end)
	if not card then
		return
	end
	card.LayoutOrder = (self._postsWrapper == self._questsWrapper and 1000 or 0) + order
	EventCardKit.paintHeader(card, if quest.goalType == "streak" then cfg.HEADER_LABELS.streak else cfg.HEADER_LABELS.quest)
	local body = card:FindFirstChild("Body")
	setText(body, "Category", EventCardKit.spaced(if quest.category ~= "" then quest.category else "Quest"))
	-- The design's headline is the goal sentence; the dashboard fills it in automatically.
	setText(body, "Title", if quest.description ~= "" then quest.description else quest.title)
	setText(body, "Date", string.format(cfg.DUE_DATE_TEXT, EventCardKit.dateText(quest.dueDate)))
	local row = body and body:FindFirstChild("ProgressRow")
	setText(row, "Label", string.format(cfg.PROGRESS_TEXT, ""))
	setText(row, "Value", progressText(quest.goalType, quest.current, quest.target))
	local fill = path(body, "Bar", "Fill")
	if fill and fill:IsA("GuiObject") then
		local ratio = if quest.target > 0 then math.clamp(quest.current / quest.target, 0, 1) else 0
		UIMotion.tween(fill, 0.45, { Size = UDim2.new(ratio, 0, 1, 0) }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		fill.Visible = ratio > 0
	end
	local week = body and body:FindFirstChild("Week")
	local calendar = quest.calendar
	if week and calendar then
		setText(week, "WeekLabel", EventCardKit.weekText(calendar))
		local cal = week:FindFirstChild("Cal")
		if cal and cal:IsA("GuiObject") then
			EventCardKit.paintCalendar(cal, calendar, { weekOnly = true })
		end
	end
	self:_paintQuestButton(card, quest)
end

function EventTabUI:_questById(questId: number): QuestState?
	local state = self._state
	if not state then
		return nil
	end
	for _, quest in ipairs(state.quests) do
		if quest.id == questId then
			return quest
		end
	end
	return nil
end

function EventTabUI:_emptyLabel(wrapper: Instance, key: string, text: string, show: boolean)
	local name = "EventEmpty_" .. key
	local label = wrapper:FindFirstChild(name)
	if not show then
		if label then
			label:Destroy()
		end
		return
	end
	if not label then
		local created = Instance.new("TextLabel")
		created.Name = name
		created.BackgroundTransparency = 1
		created.Size = UDim2.new(1, 0, 0, 36)
		created.TextColor3 = Color3.new(1, 1, 1)
		created.TextTransparency = 0.45
		created.TextSize = 15
		created.FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.SemiBold)
		created.TextXAlignment = Enum.TextXAlignment.Left
		created.LayoutOrder = if key == "quests" and self._postsWrapper == self._questsWrapper then 999 else -1
		created.Parent = wrapper
		label = created
	end
	(label :: TextLabel).Text = text
end

function EventTabUI:setState(state: State)
	self._state = state
	self._stateReceivedAt = os.clock()
	table.clear(self._busy)
	local keep: { [string]: boolean } = {}
	for index, post in ipairs(state.posts) do
		keep["post_" .. post.id] = true
		self:_paintPost(post, index)
	end
	for index, quest in ipairs(state.quests) do
		keep["quest_" .. quest.id] = true
		self:_paintQuest(quest, index)
	end
	for key, card in pairs(self._cards) do
		if not keep[key] then
			card:Destroy()
			self._cards[key] = nil
		end
	end
	self:_emptyLabel(self._postsWrapper, "posts", cfg.EMPTY_POSTS, #state.posts == 0)
	self:_emptyLabel(self._questsWrapper, "quests", cfg.EMPTY_QUESTS, #state.quests == 0)
	if self._popupPostId and not self:postById(self._popupPostId) then
		self:closePopup()
	end
end

-- Countdown tiles; called about once a second while the tab is on screen.
function EventTabUI:tick()
	local state = self._state
	if not state then
		return
	end
	for _, post in ipairs(state.posts) do
		if post.kind == "countdown" then
			local card = self._cards["post_" .. post.id]
			if card then
				self:_paintCountdown(card, post)
			end
		end
	end
end

function EventTabUI:isShown(): boolean
	local node: Instance? = self._tab
	while node and not node:IsA("ScreenGui") do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return node ~= nil and (node :: ScreenGui).Enabled
end

-- Brings the quests section into view (the top menu's Quests row).
function EventTabUI:focusQuests()
	local tab = self._tab
	local section = self._questsSection
	if not (tab:IsA("ScrollingFrame") and section and section:IsA("GuiObject")) then
		return
	end
	task.defer(function()
		local scroller = tab :: ScrollingFrame
		local offset = (section :: GuiObject).AbsolutePosition.Y - scroller.AbsolutePosition.Y + scroller.CanvasPosition.Y
		scroller.CanvasPosition = Vector2.new(0, math.max(0, offset))
	end)
end

function EventTabUI:destroy()
	for _, c in ipairs(self._connections) do
		c:Disconnect()
	end
	table.clear(self._connections)
	for _, card in pairs(self._cards) do
		card:Destroy()
	end
	table.clear(self._cards)
	if self._popupGui then
		self._popupGui:Destroy()
	end
end

return EventTabUI
