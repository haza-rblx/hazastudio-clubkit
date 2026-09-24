--!strict
-- Client/UI/EventTabUI.luau
-- Event board (ADR 0015): paints the menu's EventTab (07-MenuGUI) and the post popup.
-- Display only — the server sends a whole snapshot (EventBoardController.buildState) after every
-- change and decides every number; this module only draws it and reports presses.
--
-- GUI contract (names in Config.EventBoard):
--   EventTab (ScrollingFrame) > PostsSection / QuestsSection (Frame)
--     > SectionIdentity > SectionTitle / SectionSubtitle
--     > SectionContentWrapper > BasicAnnouncement / ImageAnnouncement / QuestTemplate / StreakTemplate
--   Each card: Content > Category / Title / DatePublished | DueDate / Body / Banner / ProgressBar >
--   Fill / ProgressLabel / StreakDays > Day1..Day6 > Icon, and a SubmitButton > TextLabel.
--   PopUpMenuTemplate (07-MenuGUI root) > Wrapper > Content > Category / Title / DatePublished /
--   Body, and Wrapper > SubmitButton.
-- The templates stay in the tree hidden; cards are clones. A place with only one "Section" (the
-- design as delivered) gets both kinds of card in it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local DailyQuestDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.DailyQuestDomain)
local UIMotion = require(script.Parent.Parent.Utils.UIMotion)

local cfg = Config.EventBoard
local CARD_PREFIX = "EventCard_"
local POPUP_GUI_NAME = "EventBoardPopupGui"
local POPUP_DISPLAY_ORDER = 120
local MONTHS = {
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
}
local DIM_TRANSPARENCY = 0.35

export type PostState = {
	id: number,
	category: string,
	title: string,
	body: string,
	imageAssetId: string,
	publishedAt: string,
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
	dueDate: string,
	current: number,
	target: number,
	complete: boolean,
	claimed: boolean,
	checkedInToday: boolean,
	strip: { string }?,
}

export type State = {
	serverTime: number,
	secondsToNextDay: number,
	posts: { PostState },
	quests: { QuestState },
	joinPostId: number?,
}

local EventTabUI = {}
EventTabUI.__index = EventTabUI

local function path(root: Instance?, ...: string): Instance?
	local node = root
	for _, name in ipairs({ ... }) do
		if not node then
			return nil
		end
		node = node:FindFirstChild(name)
	end
	return node
end

local function setText(root: Instance?, name: string, text: string)
	local label = root and root:FindFirstChild(name)
	if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
		(label :: TextLabel).Text = text
	end
end

local function setVisible(root: Instance?, name: string, visible: boolean)
	local node = root and root:FindFirstChild(name)
	if node and node:IsA("GuiObject") then
		node.Visible = visible
	end
end

-- "A N N O U N C E M E N T S", the design's letter-spaced category line.
local function spaced(text: string): string
	local upper = string.upper(text)
	local letters = {}
	for _, code in utf8.codes(upper) do
		table.insert(letters, utf8.char(code))
	end
	return table.concat(letters, " ")
end

local function dateText(dateString: string): string
	local day = DailyQuestDomain.parseWibDate(dateString)
	if not day then
		return dateString
	end
	local y, m, d = DailyQuestDomain.toCivil(day)
	return string.format(cfg.DATE_FORMAT, MONTHS[m], d, y)
end

-- ISO timestamp from the API → "September 24, 2026 | 18:30 WIB".
local function publishedText(iso: string): string
	local y, mo, d, h, mi = string.match(iso, "^(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
	if not y then
		return ""
	end
	-- Plain arithmetic on the UTC parts: os.time/os.date read tables in the client's own
	-- timezone, which is not the venue's.
	local utcMinutes = (tonumber(h) :: number) * 60 + (tonumber(mi) :: number) + 7 * 60
	local dayShift = utcMinutes // (24 * 60)
	local minutes = utcMinutes % (24 * 60)
	local dayNumber = (DailyQuestDomain.parseWibDate(string.format("%s-%s-%s", y, mo, d)) or 0) + dayShift
	local cy, cm, cd = DailyQuestDomain.toCivil(dayNumber)
	return string.format("%s %d, %d | %02d:%02d WIB", MONTHS[cm], cd, cy, minutes // 60, minutes % 60)
end

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
end

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
		quest = template(cfg.TEMPLATES.QUEST),
		streak = template(cfg.TEMPLATES.STREAK),
	}
	self._cards = {} :: { [string]: GuiObject }
	self._connections = {} :: { RBXScriptConnection }
	self._state = nil :: State?
	self._stateReceivedAt = 0
	self._busy = {} :: { [number]: boolean }
	self._onClaim = nil :: ((number) -> ())?
	self._onCheckIn = nil :: ((number) -> ())?
	self._onPostSeen = nil :: ((number) -> ())?
	self._popup = nil :: GuiObject?
	self._popupGui = nil :: ScreenGui?
	self._popupPostId = nil :: number?
	self._stripStyles = nil :: any

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

function EventTabUI:onCheckIn(callback: (number) -> ())
	self._onCheckIn = callback
end

function EventTabUI:onPostSeen(callback: (number) -> ())
	self._onPostSeen = callback
end

function EventTabUI:getTab(): GuiObject
	return self._tab
end

-- ── popup ─────────────────────────────────────────────────────────────────────────────────

function EventTabUI:_buildPopup(menuGui: Instance)
	local source = menuGui:FindFirstChild(cfg.POPUP_NAME)
	if not (source and source:IsA("GuiObject")) then
		return
	end
	source.Visible = false
	-- Its own ScreenGui: the menu's is disabled while the menu is closed, and the join popup
	-- shows without it.
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

function EventTabUI:openPost(postId: number)
	local state = self._state
	if not state or not self._popup or not self._popupGui then
		return
	end
	local post: PostState? = nil
	for _, candidate in ipairs(state.posts) do
		if candidate.id == postId then
			post = candidate
		end
	end
	if not post then
		return
	end
	local content = path(self._popup, "Wrapper", "Content")
	setText(content, "Category", if post.category ~= "" then spaced(post.category) else "")
	setVisible(content, "Category", post.category ~= "")
	setText(content, "Title", post.title)
	setText(content, "DatePublished", publishedText(post.publishedAt))
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
	local button = card:FindFirstChild("SubmitButton", true)
	if not (button and button:IsA("GuiButton")) then
		return
	end
	for _, c in ipairs(UIMotion.bindPress(button)) do
		table.insert(self._connections, c)
	end
	for _, c in ipairs(UIMotion.bindHover(button)) do
		table.insert(self._connections, c)
	end
	table.insert(self._connections, (button :: GuiButton).Activated:Connect(onPress))
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

function EventTabUI:_paintPost(post: PostState, order: number)
	local templateName = if post.imageAssetId ~= "" and self._templates.image then "image" else "basic"
	local card = self:_card("post_" .. post.id, templateName, self._postsWrapper, function(card)
		local postId = post.id
		self:_bindButton(card, function()
			self:openPost(postId)
		end)
	end)
	if not card then
		return
	end
	card.LayoutOrder = order
	local content = card:FindFirstChild("Content")
	setText(content, "Category", if post.category ~= "" then spaced(post.category) else "")
	setVisible(content, "Category", post.category ~= "")
	setText(content, "Title", post.title)
	setText(content, "DatePublished", publishedText(post.publishedAt))
	setText(content, "Body", post.body)
	local banner = content and content:FindFirstChild("Banner")
	if banner and banner:IsA("ImageLabel") then
		banner.Image = if post.imageAssetId ~= "" then "rbxassetid://" .. post.imageAssetId else ""
		banner.ScaleType = Enum.ScaleType.Crop
	end
	setText(card:FindFirstChild("SubmitButton", true), "TextLabel", cfg.BUTTON_OPEN_POST)
end

function EventTabUI:_questButtonText(quest: QuestState): (string, boolean)
	if quest.claimed then
		return cfg.BUTTON_CLAIMED, false
	end
	if self._busy[quest.id] then
		return cfg.BUTTON_BUSY, false
	end
	if quest.complete then
		return cfg.BUTTON_CLAIM, true
	end
	if quest.goalType == "streak" then
		local state = self._state :: State
		local elapsed = os.clock() - self._stateReceivedAt
		local left = clock(state.secondsToNextDay - elapsed)
		if quest.checkedInToday then
			return string.format(cfg.BUTTON_CHECKED_IN, left), false
		end
		return string.format(cfg.BUTTON_CHECK_IN, left), true
	end
	return cfg.BUTTON_INCOMPLETE, false
end

function EventTabUI:_paintQuestButton(card: GuiObject, quest: QuestState)
	local button = card:FindFirstChild("SubmitButton", true)
	if not (button and button:IsA("GuiButton")) then
		return
	end
	local text, active = self:_questButtonText(quest)
	setText(button, "TextLabel", text)
	local label = button:FindFirstChild("TextLabel")
	if label and label:IsA("TextLabel") then
		label.TextTransparency = if active then 0 else DIM_TRANSPARENCY
	end
	(button :: GuiButton).AutoButtonColor = false
	button:SetAttribute("EventActionable", active)
end

function EventTabUI:_paintQuest(quest: QuestState, order: number)
	local templateName = if quest.goalType == "streak" and self._templates.streak then "streak" else "quest"
	local card = self:_card("quest_" .. quest.id, templateName, self._questsWrapper, function(card)
		local questId = quest.id
		self:_bindButton(card, function()
			local button = card:FindFirstChild("SubmitButton", true)
			if not button or button:GetAttribute("EventActionable") ~= true then
				return
			end
			local current = self:_questById(questId)
			if not current then
				return
			end
			self._busy[questId] = true
			self:_paintQuestButton(card, current)
			if current.complete and not current.claimed then
				if self._onClaim then
					self._onClaim(questId)
				end
			elseif current.goalType == "streak" and self._onCheckIn then
				self._onCheckIn(questId)
			end
		end)
	end)
	if not card then
		return
	end
	card.LayoutOrder = (self._postsWrapper == self._questsWrapper and 1000 or 0) + order
	local content = card:FindFirstChild("Content")
	setText(content, "Category", spaced(if quest.category ~= "" then quest.category else "Quest"))
	-- The design's headline is the goal sentence; the dashboard fills it in automatically.
	setText(content, "Title", if quest.description ~= "" then quest.description else quest.title)
	setText(content, "DueDate", string.format(cfg.DUE_DATE_TEXT, dateText(quest.dueDate)))
	setText(content, "ProgressLabel", string.format(cfg.PROGRESS_TEXT, progressText(quest.goalType, quest.current, quest.target)))
	local fill = path(content, "ProgressBar", "Fill")
	if fill and fill:IsA("GuiObject") then
		local ratio = if quest.target > 0 then math.clamp(quest.current / quest.target, 0, 1) else 0
		fill.Size = UDim2.new(ratio, 0, fill.Size.Y.Scale, fill.Size.Y.Offset)
		fill.Visible = ratio > 0
	end
	local strip = quest.strip
	local days = content and content:FindFirstChild("StreakDays")
	if strip and days then
		self:_paintStrip(days, strip)
	end
	self:_paintQuestButton(card, quest)
end

-- Day1 in the design is the "done" look (dark square with the streak flame), Day2 the plain one.
function EventTabUI:_paintStrip(days: Instance, strip: { string })
	if not self._stripStyles then
		local done = days:FindFirstChild("Day1")
		local plain = days:FindFirstChild("Day2")
		if not (done and plain and done:IsA("GuiObject") and plain:IsA("GuiObject")) then
			return
		end
		local doneIcon = done:FindFirstChildWhichIsA("ImageLabel")
		self._stripStyles = {
			done = { color = done.BackgroundColor3, transparency = done.BackgroundTransparency, icon = if doneIcon then doneIcon.Image else "" },
			plain = { color = plain.BackgroundColor3, transparency = plain.BackgroundTransparency },
		}
	end
	local styles = self._stripStyles
	for index, status in ipairs(strip) do
		local day = days:FindFirstChild("Day" .. index)
		if day and day:IsA("GuiObject") then
			local icon = day:FindFirstChildWhichIsA("ImageLabel")
			if status == "done" then
				day.BackgroundColor3 = styles.done.color
				day.BackgroundTransparency = styles.done.transparency
				if icon then
					icon.Image = styles.done.icon
					icon.ImageTransparency = 0
				end
			else
				day.BackgroundColor3 = styles.plain.color
				day.BackgroundTransparency = if status == "closed"
					then math.min(1, styles.plain.transparency + 0.06)
					else styles.plain.transparency
				if icon then
					-- Today, still open: a faint flame says "this one is yours to fill".
					icon.Image = if status == "today" then styles.done.icon else ""
					icon.ImageTransparency = if status == "today" then 0.7 else 1
				end
			end
		end
	end
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
		created.FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.Medium)
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
	if self._popupPostId then
		local stillThere = false
		for _, post in ipairs(state.posts) do
			if post.id == self._popupPostId then
				stillThere = true
			end
		end
		if not stillThere then
			self:closePopup()
		end
	end
end

-- Countdown on streak buttons; called about once a second while the tab is on screen.
function EventTabUI:tick()
	local state = self._state
	if not state then
		return
	end
	for _, quest in ipairs(state.quests) do
		if quest.goalType == "streak" and not quest.complete then
			local card = self._cards["quest_" .. quest.id]
			if card then
				self:_paintQuestButton(card, quest)
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
