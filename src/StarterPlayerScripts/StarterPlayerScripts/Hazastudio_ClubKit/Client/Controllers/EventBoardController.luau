--!strict
-- Client/Controllers/EventBoardController.luau
-- Event board (ADR 0015), client side: feeds the server's snapshots to the Event tab, the quest
-- popup and the reminders, and sends the player's presses back. A place without the EventTab
-- design does nothing here; the popup and the reminders are each optional on top of it.
--
-- Reminders (CONTEXT.md "Reminder"): on join only the show-on-join post and running/upcoming
-- countdowns the player has not seen; afterwards every post that appears on the board while they
-- are online. A post counts as seen once its reminder showed. Hidden while the menu is open.
-- Notify me = Roblox's own RSVP prompt for the countdown's linked Experience Event.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local EventTabUI = require(script.Parent.Parent.UI.EventTabUI)
local EventQuestPopupUI = require(script.Parent.Parent.UI.EventQuestPopupUI)
local EventReminderUI = require(script.Parent.Parent.UI.EventReminderUI)
local EventCardKit = require(script.Parent.Parent.UI.EventCardKit)
local EventBoardRelay = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.EventBoardRelay)

local log = Logger.new("Client.EventBoardController")
local cfg = Config.EventBoard
local OPTIONAL_GUI_WAIT = 20 -- seconds for the popup / reminder ScreenGuis after the menu landed

local connections: { RBXScriptConnection } = {}
local ui: any = nil
local popup: any = nil
local reminders: any = nil
local alive = false

local EventBoardController = {}

-- Top menu's Quests row: scroll the tab to its quests once it is shown.
function EventBoardController.focusQuests()
	if ui then
		ui:focusQuests()
	end
end

function EventBoardController.init(deps: { remotes: Folder })
	if alive then
		return
	end
	alive = true
	-- The menu GUI lands in PlayerGui only once the character spawns, which can be long after
	-- boot (behind the loading screen): wait for it off the boot task, without a deadline.
	task.spawn(EventBoardController._start, deps)
end

-- The menu is on screen when its ScreenGui is enabled and its top wrapper is visible.
local function menuIsOpen(menuGui: Instance): boolean
	if not (menuGui:IsA("ScreenGui") and menuGui.Enabled) then
		return false
	end
	local wrapper = menuGui:FindFirstChild("MenuGUIWrapper")
	return not (wrapper and wrapper:IsA("GuiObject")) or wrapper.Visible
end

local function waitGameplayReady(player: Player)
	local attribute = Config.ClientBoot.GAMEPLAY_READY_ATTRIBUTE
	local deadline = os.clock() + cfg.READY_TIMEOUT
	while player:GetAttribute(attribute) ~= true and os.clock() < deadline do
		task.wait(0.25)
	end
end

function EventBoardController._start(deps: { remotes: Folder })
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	local menuGui = playerGui:WaitForChild("07-MenuGUI")
	if not alive then
		return
	end
	ui = EventTabUI.tryCreate(playerGui)
	if not ui then
		log:info("EventTab not installed; event board off on this client")
		return
	end
	local remote = deps.remotes:WaitForChild(cfg.REMOTE, 30)
	if not (remote and remote:IsA("RemoteEvent")) then
		log:warn("EventBoard remote missing")
		return
	end
	local eventRemote = remote :: RemoteEvent
	local function send(payload: { [string]: any })
		eventRemote:FireServer(payload)
	end

	if playerGui:WaitForChild(cfg.QUEST_POPUP_GUI, OPTIONAL_GUI_WAIT) then
		popup = EventQuestPopupUI.tryCreate(playerGui)
	end
	if playerGui:WaitForChild(cfg.REMINDER_GUI, OPTIONAL_GUI_WAIT) then
		reminders = EventReminderUI.tryCreate(playerGui)
	end
	if not alive then
		return
	end

	-- ── presses ──────────────────────────────────────────────────────────────────────────
	ui:onClaim(function(questId: number)
		send({ action = "claim", questId = questId })
	end)
	ui:onPostSeen(function(postId: number)
		send({ action = "seen", postId = postId })
	end)

	local function questById(questId: number): any?
		local state = ui:getState()
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

	local function openQuest(questId: number)
		local quest = questById(questId)
		local state = ui:getState()
		if not popup or not quest or not state then
			return
		end
		popup:setQuest(quest, state.secondsToNextDay)
		popup:open()
	end
	ui:onOpenQuest(openQuest)
	if popup then
		popup:onCheckIn(function(questId: number)
			send({ action = "checkin", questId = questId })
		end)
		popup:onClaim(function(questId: number)
			send({ action = "claim", questId = questId })
		end)
	end

	-- Roblox Experience Event RSVP. Fails once the event started (Roblox errors), hence pcall.
	local rsvpAsked: { [string]: boolean } = {}
	local function refreshRsvp(post: any)
		local eventId = post.robloxEventId
		if eventId == "" or rsvpAsked[eventId] then
			return
		end
		rsvpAsked[eventId] = true
		task.spawn(function()
			local ok, status = pcall(function()
				return SocialService:GetEventRsvpStatusAsync(eventId)
			end)
			if ok and ui then
				ui:setNotified(post.id, status == Enum.RsvpStatus.Going)
			end
		end)
	end
	local function notify(postId: number)
		local post = ui:postById(postId)
		if not post or post.robloxEventId == "" then
			return
		end
		task.spawn(function()
			local ok, status = pcall(function()
				return SocialService:PromptRsvpToEventAsync(post.robloxEventId)
			end)
			if ok and ui then
				ui:setNotified(postId, status == Enum.RsvpStatus.Going)
			elseif not ok then
				log:warn("RSVP prompt failed", { eventId = post.robloxEventId, err = status })
			end
		end)
	end
	ui:onNotify(notify)

	-- ── reminders ────────────────────────────────────────────────────────────────────────
	local knownPosts: { [number]: boolean } = {}
	local baselineTaken = false
	local function remind(post: any)
		if not reminders then
			return
		end
		local isCountdown = post.kind == "countdown"
		local now = ui:now()
		local upcoming = isCountdown and post.startsAt ~= nil and now < post.startsAt
		local text = post.body
		local date = EventCardKit.publishedText(post.publishedAt)
		local button = cfg.BUTTON_OPEN_POST
		local action = function()
			ui:openPost(post.id)
		end
		if isCountdown and post.startsAt then
			date = EventCardKit.momentText(post.startsAt)
			if upcoming then
				text = string.format(cfg.REMINDER_COUNTDOWN_TEXT, EventCardKit.shortDuration(post.startsAt - now))
				if post.robloxEventId ~= "" then
					button = cfg.BUTTON_NOTIFY
					action = function()
						notify(post.id)
					end
				else
					button = cfg.BUTTON_DETAIL
				end
			else
				text = string.format(cfg.COUNTDOWN_LIVE_TEXT, EventCardKit.clockText(post.endsAt or post.startsAt))
				button = cfg.BUTTON_DETAIL
			end
		end
		reminders:push({
			key = "post_" .. post.id,
			header = if isCountdown then cfg.HEADER_LABELS.countdown else cfg.HEADER_LABELS.announcement,
			thumb = if post.imageAssetId ~= "" then "rbxassetid://" .. post.imageAssetId else nil,
			category = post.category,
			title = post.title,
			date = date,
			text = text,
			button = button,
			onAction = action,
		})
		send({ action = "seen", postId = post.id })
	end

	local function considerReminders(state: any)
		local unseen: { [number]: boolean } = {}
		for _, id in ipairs(state.unseenPostIds or {}) do
			unseen[id] = true
		end
		local fresh = {}
		for _, post in ipairs(state.posts) do
			if not knownPosts[post.id] then
				knownPosts[post.id] = true
				if unseen[post.id] then
					-- First snapshot: only the join post and timely countdowns, never the backlog.
					local timely = post.id == state.joinPostId or post.kind == "countdown"
					if baselineTaken or timely then
						table.insert(fresh, post)
					end
				end
			end
		end
		baselineTaken = true
		if #fresh == 0 then
			return
		end
		task.spawn(function()
			waitGameplayReady(player)
			for _, post in ipairs(fresh) do
				if alive and ui:postById(post.id) then
					remind(post)
				end
			end
		end)
	end

	-- Reminders hide while the menu is open and come back when it closes; the tab's cards were
	-- painted while the menu was hidden, so their wrapped text is re-measured as it opens. The
	-- menu ScreenGui can stay enabled while closed — its top wrapper's Visible is what opens it.
	if menuGui:IsA("ScreenGui") then
		local wrapper = menuGui:FindFirstChild("MenuGUIWrapper")
		local wasOpen = false
		local function sync()
			local open = menuIsOpen(menuGui)
			if reminders then
				reminders:setSuppressed(open)
			end
			if open and not wasOpen and ui then
				EventCardKit.remeasure(ui:getTab())
			end
			wasOpen = open
		end
		table.insert(connections, menuGui:GetPropertyChangedSignal("Enabled"):Connect(sync))
		if wrapper and wrapper:IsA("GuiObject") then
			table.insert(connections, wrapper:GetPropertyChangedSignal("Visible"):Connect(sync))
		end
		sync()
	end

	-- ── quest popup: once per session on its own when a streak quest still waits for today ──
	local autoOpenDecided = false
	local function considerAutoOpen(state: any)
		if autoOpenDecided or not popup then
			return
		end
		autoOpenDecided = true
		local waiting = nil
		for _, quest in ipairs(state.quests) do
			if quest.goalType == "streak" and not quest.checkedInToday and not quest.complete then
				waiting = quest.id
				break
			end
		end
		if not waiting then
			return
		end
		task.spawn(function()
			waitGameplayReady(player)
			task.wait(cfg.POPUP_AUTO_OPEN_DELAY)
			if alive and popup and not popup:isOpen() and not menuIsOpen(menuGui) then
				openQuest(waiting)
			end
		end)
	end

	-- ── snapshots ────────────────────────────────────────────────────────────────────────
	local function onState(raw: any)
		if type(raw) ~= "table" or raw.type ~= "state" or type(raw.posts) ~= "table" or type(raw.quests) ~= "table" then
			return
		end
		ui:setState(raw)
		for _, post in ipairs(raw.posts) do
			if post.kind == "countdown" then
				refreshRsvp(post)
			end
		end
		if popup and popup:isOpen() then
			local id = popup:questId()
			local quest = if id then questById(id) else nil
			if quest then
				popup:setQuest(quest, raw.secondsToNextDay)
			else
				popup:close()
			end
		end
		considerReminders(raw)
		considerAutoOpen(raw)
	end
	table.insert(connections, eventRemote.OnClientEvent:Connect(onState))
	-- The cinematic loading screen may have taken the join-time push first (EventBoardRelay).
	local relayed = EventBoardRelay.latest()
	if relayed and not ui:getState() then
		onState(relayed)
	end

	-- Countdowns and the check-in clock, once a second while someone can see them; a fresh
	-- snapshot when the WIB day turns.
	task.spawn(function()
		local askedForDay = false
		while alive and ui do
			task.wait(1)
			if ui and ui:isShown() then
				ui:tick()
			end
			if popup and popup:isOpen() then
				popup:tick()
			end
			local state = ui and ui:getState()
			if state then
				local left = state.secondsToNextDay - (ui:now() - state.serverTime)
				if left <= 0 and not askedForDay then
					askedForDay = true
					send({ action = "refresh" })
				elseif left > 0 then
					askedForDay = false
				end
			end
		end
	end)

	-- The tab may have been built before the first state arrived; ask once more.
	send({ action = "refresh" })
end

function EventBoardController.destroy()
	alive = false
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	table.clear(connections)
	if ui then
		ui:destroy()
		ui = nil
	end
	if popup then
		popup:destroy()
		popup = nil
	end
	if reminders then
		reminders:destroy()
		reminders = nil
	end
end

return EventBoardController
