--!strict
-- Server/Controllers/EventBoardController.luau
-- Event board (ADR 0015): venue posts + venue quests authored in the customer dashboard.
--   * EventBoardProvider pulls the board; every change is pushed to every player.
--   * Per player: a progress document (VenueQuestProgressRepository) loaded on join, counters
--     (Robux donated, seconds played) accumulated here and flushed periodically and on leave.
--   * One RemoteEvent, both ways. Client → server: { action = "checkin" | "claim", questId }
--     or { action = "seen", postId } (a reminder shown / join post opened) or { action = "refresh" }.
--     Server → client: { type = "state", ... } (see buildState).
--   * Claims (per milestone, 2026-10-08): checked here against the player's real standing,
--     recorded by the VPS (quota, one Robux reward per quest, dashboard), then atomically in the
--     DataStore (refused if another server already paid it), then the in-game reward is granted;
--     a failed grant rolls both back. Robux / manual rewards are only recorded. A check-in press
--     also claims the first claimable milestone. Server → client { type = "needGroup", groupId,
--     questId, milestoneId } asks the client to prompt a group join and claim again.

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local EventBoardDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.EventBoardDomain)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local StreakDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.StreakDomain)
local DailyQuestDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.DailyQuestDomain)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local TextFilterUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.TextFilterUtil)

local EventBoardProvider = require(script.Parent.Parent.Services.EventBoardProvider)
local EventQuestBackend = require(script.Parent.Parent.Services.EventQuestBackend)

type Board = EventBoardDomain.Board
type Quest = EventBoardDomain.Quest
type Milestone = EventBoardDomain.Milestone
type ProgressDoc = EventBoardDomain.ProgressDoc

type Session = {
	player: Player,
	doc: ProgressDoc,
	loaded: boolean,
	loadQueued: boolean,
	dirty: boolean,
	saving: boolean,
	busy: boolean,
	leftAt: number,
}

-- ProfileLoader kind for the progress document (production hardening P1): join loads share the
-- loader's concurrency cap and budget requeue instead of a direct GetAsync per joiner.
local VENUE_QUEST_KIND = "venue_quest"
local DEFAULT_LEAVE_RETRY_DELAYS = { 2, 4, 8, 16, 30 }
local MAX_DEPARTED = 400

local function createEventBoardController(deps: {
	remotes: Folder,
	notify: any,
	repo: any, -- OverheadRepository
	overheadController: any,
	progressRepo: any, -- VenueQuestProgressRepository
	levelService: any?,
	logger: any?,
	-- Optional: stored-settings write for title grants (own client shows the layer).
	settingsService: any?,
	settingsSync: { syncPlayer: ((Player) -> ())? }?,
})
	local log = deps.logger or Logger.new("EventBoardController")
	local settingsService = deps.settingsService
	local settingsSync = deps.settingsSync

	-- Only an online target has loaded settings to write into.
	local function grantStoredLayers(userId: number, keys: { string })
		local onlineTarget = game:GetService("Players"):GetPlayerByUserId(userId)
		if not settingsService or not onlineTarget then
			return
		end
		if settingsService:grantOverheadLayers(onlineTarget, keys) and settingsSync and settingsSync.syncPlayer then
			settingsSync.syncPlayer(onlineTarget)
		end
	end
	local cfg = Config.EventBoard
	local notify = deps.notify
	local repo = deps.repo
	local overheadController = deps.overheadController
	local progressRepo = deps.progressRepo
	local levelService = deps.levelService

	local remote = deps.remotes:FindFirstChild(cfg.REMOTE)
	if not (remote and remote:IsA("RemoteEvent")) then
		remote = Instance.new("RemoteEvent")
		remote.Name = cfg.REMOTE
		remote.Parent = deps.remotes
	end
	local eventRemote = remote :: RemoteEvent

	local limiter = RateLimiter.new(cfg.RATE_MAX, cfg.RATE_WINDOW)
	local sessions: { [number]: Session } = {}
	-- Players who left with progress not yet written. Kept (and retried) until a save succeeds,
	-- flushed by the periodic loop and by flushAll (BindToClose), handed back on a rejoin.
	local departed: { [number]: Session } = {}
	local connections: { RBXScriptConnection } = {}
	local destroyed = false
	local lastDay = StreakDomain.toDayNumber(os.time())
	local profileLoader: any = nil

	local provider: any
	local backend: any = nil

	local function remainingOf(milestoneId: number): number?
		return if backend then backend:remaining(milestoneId) else nil
	end

	local function rewardLabel(rewardType: string, rewardValue: string): string
		if rewardType == "robux" then
			return cfg.ROBUX_REWARD_TEXT:format(rewardValue)
		elseif rewardType == "xp" then
			return cfg.XP_REWARD_TEXT:format(rewardValue)
		elseif rewardType == "membership" then
			local tier = OverheadDomain.normalizeMembershipTier(rewardValue)
			return if tier then OverheadDomain.getMembershipChatLabel(tier) else rewardValue
		end
		return rewardValue -- title / manual: the text itself
	end

	local function today(): number
		return StreakDomain.toDayNumber(os.time())
	end

	local function levelOf(userId: number): number
		local loaded = repo:load(userId)
		if loaded.ok and type(loaded.value) == "table" and type(loaded.value.level) == "number" then
			return loaded.value.level
		end
		return 0
	end

	local function board(): Board
		return if provider then provider:getBoard() else EventBoardDomain.emptyBoard()
	end

	local function findQuest(questId: any): Quest?
		if type(questId) ~= "number" then
			return nil
		end
		for _, quest in ipairs(board().quests) do
			if quest.id == questId then
				return quest
			end
		end
		return nil
	end

	local function buildState(session: Session): { [string]: any }
		local now = os.time()
		local day = StreakDomain.toDayNumber(now)
		local level = levelOf(session.player.UserId)
		local current = board()
		-- Ended countdowns are gone; a push lands at every countdown start/end (scheduleBoundaryPush).
		local visible = EventBoardDomain.visiblePosts(current, now)
		local posts = {}
		-- Posts this player has not been reminded of yet (once per player per post, seenPosts).
		local unseenPostIds = {}
		for _, post in ipairs(visible) do
			table.insert(posts, {
				id = post.id,
				category = post.category,
				title = post.title,
				body = post.body,
				imageAssetId = post.imageAssetId,
				publishedAt = post.publishedAt,
				kind = post.kind,
				startsAt = post.startsAt,
				endsAt = post.endsAt,
				robloxEventId = post.robloxEventId,
			})
			if not session.doc.seenPosts[tostring(post.id)] then
				table.insert(unseenPostIds, post.id)
			end
		end
		local quests = {}
		for _, quest in ipairs(EventBoardDomain.visibleQuests(current, day)) do
			local standing = EventBoardDomain.standing(quest, session.doc, level, day)
			-- One row per milestone; `status` drives the row and the button:
			-- claimed | claimable | locked (not reached) | full | robux_taken.
			local milestones = {}
			local claimable: { [string]: any }? = nil
			for _, milestone in ipairs(quest.milestones) do
				local remaining = remainingOf(milestone.id)
				local verdict = EventBoardDomain.canClaimMilestone(quest, milestone, session.doc, level, day, remaining)
				local status = if verdict == "ok"
					then "claimable"
					elseif verdict == "claimed" then "claimed"
					elseif verdict == "quota_full" then "full"
					elseif verdict == "robux_taken" then "robux_taken"
					else "locked"
				-- Not reached yet but already out of slots: show it full, it can never be claimed.
				if status == "locked" and milestone.quota and remaining ~= nil and remaining <= 0 then
					status = "full"
				end
				local quota = if backend then backend:quotaOf(milestone.id) else nil
				local row = {
					id = milestone.id,
					value = milestone.value,
					rewardType = milestone.rewardType,
					rewardValue = milestone.rewardValue,
					rewardLabel = rewardLabel(milestone.rewardType, milestone.rewardValue),
					quota = milestone.quota,
					remaining = if milestone.quota then (if quota then math.max(0, quota.quota - quota.claimed) else milestone.quota) else nil,
					status = status,
				}
				table.insert(milestones, row)
				if status == "claimable" and not claimable then
					claimable = row
				end
			end
			-- Today's check-in would reach a milestone that is still open: the check-in button
			-- already reads "Claim <reward>" (the press checks in and claims).
			local onCheckIn: { [string]: any }? = nil
			if not claimable and quest.goalType == "streak" and not standing.checkedInToday and not standing.complete then
				for index, row in ipairs(milestones) do
					local milestone = quest.milestones[index]
					if row.status == "locked"
						and milestone.value <= standing.current + 1
						and not (milestone.rewardType == "robux" and EventBoardDomain.robuxClaimed(quest, session.doc))
						and (row.remaining == nil or row.remaining > 0)
					then
						onCheckIn = row
						break
					end
				end
			end
			local labelled = claimable or onCheckIn
			table.insert(quests, {
				milestones = milestones,
				claimableMilestoneId = if claimable then claimable.id else nil,
				claimOnCheckIn = onCheckIn ~= nil,
				claimLabel = if labelled then cfg.BUTTON_CLAIM_MILESTONE:format(labelled.rewardLabel) else nil,
				id = quest.id,
				category = quest.category,
				title = quest.title,
				description = quest.description,
				goalType = quest.goalType,
				goalValue = quest.goalValue,
				rewardType = quest.rewardType,
				rewardValue = quest.rewardValue,
				startDate = quest.startDate,
				dueDate = quest.dueDate,
				current = standing.current,
				target = standing.target,
				complete = standing.complete,
				claimed = standing.claimed,
				checkedInToday = standing.checkedInToday,
				calendar = if quest.goalType == "streak" then EventBoardDomain.calendar(quest, session.doc, day) else nil,
			})
		end
		-- Sent until the player has seen it (the client reports "seen" when it opens); the client
		-- opens it at most once per session, so a push that lands before it listens loses nothing.
		local joinPost = nil
		local post = EventBoardDomain.joinPost({ revision = current.revision, posts = visible, quests = current.quests })
		if post and not session.doc.seenPosts[tostring(post.id)] then
			joinPost = post.id
		end
		return {
			type = "state",
			serverTime = now,
			secondsToNextDay = EventBoardDomain.secondsUntilNextDay(now),
			posts = posts,
			unseenPostIds = unseenPostIds,
			quests = quests,
			joinPostId = joinPost,
		}
	end

	local function push(session: Session)
		if not session.loaded or not session.player.Parent then
			return
		end
		local ok, err = pcall(function()
			eventRemote:FireClient(session.player, buildState(session))
		end)
		if not ok then
			log:warn("Event board push failed", { userId = session.player.UserId, error = tostring(err) })
		end
	end

	local function pushAll()
		for _, session in pairs(sessions) do
			push(session)
		end
	end

	-- A countdown starting (tiles → LIVE) or ending (card gone) changes every player's state:
	-- one push at the next such moment, re-armed after each one and on every board change.
	local boundaryToken = 0
	local function scheduleBoundaryPush()
		boundaryToken += 1
		local token = boundaryToken
		local now = os.time()
		local nextAt = EventBoardDomain.nextPostBoundary(board(), now)
		if not nextAt then
			return
		end
		-- +1 s: os.time() is whole seconds, so land safely past the boundary second.
		task.delay(nextAt - now + 1, function()
			if destroyed or token ~= boundaryToken then
				return
			end
			pushAll()
			scheduleBoundaryPush()
		end)
	end

	-- Returns true when nothing is left to write (saved now, or already clean). False while a
	-- save is in flight or when the save failed (the session stays dirty for a retry).
	-- Production hardening P3 (A8): documents are pruned inside the save transform (quests 30 days
	-- past their due day, seenPosts capped). Only once a real board is known (revision set).
	local function pruneFn(): ((EventBoardDomain.ProgressDoc) -> EventBoardDomain.ProgressDoc)?
		local writer = Config.PlayerDocWriter
		if type(writer) ~= "table" or writer.VENUE_PRUNE_ENABLED ~= true then
			return nil
		end
		local current = board()
		if current.revision == "" then
			return nil
		end
		local day = today()
		local nowUnix = os.time()
		local pruneCfg = {
			keepDays = tonumber(writer.VENUE_PRUNE_KEEP_DAYS) or 30,
			maxSeenPosts = tonumber(writer.VENUE_PRUNE_MAX_SEEN_POSTS) or 50,
		}
		return function(doc: EventBoardDomain.ProgressDoc): EventBoardDomain.ProgressDoc
			return EventBoardDomain.pruneProgress(doc, current, day, nowUnix, pruneCfg)
		end
	end

	local function flush(session: Session): boolean
		if not session.loaded then
			return true
		end
		if session.saving then
			return false
		end
		if not session.dirty then
			return true
		end
		session.dirty = false
		session.saving = true
		local ok, saved = pcall(function()
			return progressRepo:save(session.player.UserId, session.doc, pruneFn())
		end)
		session.saving = false
		if ok and saved.ok then
			-- Keep what another server may have added meanwhile.
			session.doc = EventBoardDomain.mergeProgress(session.doc, saved.value)
			return not session.dirty
		end
		session.dirty = true
		return false
	end

	-- Retries `flush` until it reports done or `deadline` (os.clock) passes; waits out an
	-- in-flight save instead of counting it as a failure.
	local function flushUntil(session: Session, deadline: number): boolean
		while true do
			if flush(session) then
				return true
			end
			if os.clock() >= deadline then
				return false
			end
			task.wait(if session.saving then 0.2 else 1)
		end
	end

	local function forgetDeparted(userId: number, session: Session)
		if departed[userId] == session then
			departed[userId] = nil
		end
	end

	local function capDeparted()
		local list = {}
		for userId, session in pairs(departed) do
			table.insert(list, { userId = userId, at = session.leftAt })
		end
		if #list <= MAX_DEPARTED then
			return
		end
		table.sort(list, function(a, b)
			return a.at < b.at
		end)
		for index = 1, #list - MAX_DEPARTED do
			departed[list[index].userId] = nil
			log:warn("Venue quest progress dropped: too many unsaved departed players", { userId = list[index].userId })
		end
	end

	-- ── rewards ──────────────────────────────────────────────────────────────────────────
	-- Returns ok, a message for the player.
	local function grantReward(player: Player, rewardType: string, rewardValue: string): (boolean, string)
		local userId = player.UserId
		if rewardType == "membership" then
			local tier = OverheadDomain.normalizeMembershipTier(rewardValue)
			if not tier then
				return false, cfg.MSG_SAVE_FAILED
			end
			local label = OverheadDomain.getMembershipChatLabel(tier)
			local skipped = false
			local updated = repo:update(userId, function(current)
				if OverheadDomain.hasStoredMembershipAtLeast(current, tier) then
					skipped = true
					return current
				end
				skipped = false
				return OverheadDomain.addGiftedMembership(current, tier, 0, "venue_quest")
			end)
			if not updated.ok then
				return false, cfg.MSG_SAVE_FAILED
			end
			overheadController:refreshPlayer(player, "recovery")
			if skipped then
				return true, cfg.MSG_REWARD_SKIPPED_MEMBERSHIP:format(label)
			end
			return true, cfg.MSG_CLAIMED:format(label)
		elseif rewardType == "title" then
			local filtered = TextFilterUtil.filterForBroadcast(userId, rewardValue)
			local text = if filtered then ((filtered :: string):gsub("^%s+", ""):gsub("%s+$", "")) else ""
			if text == "" then
				return false, cfg.MSG_SAVE_FAILED
			end
			local skipped = false
			local updated = repo:update(userId, function(current)
				-- Only a player without a title gets one (owner, 2026-09-24).
				if (type(current.specialTitle) == "string" and current.specialTitle ~= "")
					or (type(current.specialTitleImage) == "string" and current.specialTitleImage ~= "")
				then
					skipped = true
					return current
				end
				skipped = false
				local visible = if type(current.publicOverheadLayerVisible) == "table"
					then table.clone(current.publicOverheadLayerVisible)
					else {}
				if not OverheadDomain.isLayerDisabled("SpecialTitle") then
					visible.SpecialTitle = true
				end
				return OverheadDomain.mergeStored(current, {
					specialTitle = text,
					specialTitleFromAdmin = true,
					specialTitlePreset = OverheadDomain.NIL,
					specialTitlePosition = Config.Admin.DEFAULT_SPECIAL_TITLE_POSITION or "Top",
					specialSubRole = OverheadDomain.NIL,
					publicOverheadLayerVisible = visible,
				})
			end)
			if not updated.ok then
				return false, cfg.MSG_SAVE_FAILED
			end
			if not skipped then
				grantStoredLayers(userId, { "SpecialTitle" })
			end
			if skipped then
				return true, cfg.MSG_REWARD_SKIPPED_TITLE
			end
			overheadController:invalidateBuildCache(userId)
			overheadController:refreshPlayer(player, "recovery")
			return true, cfg.MSG_CLAIMED:format('"' .. text .. '" title')
		else
			local amount = tonumber(rewardValue) or 0
			if not levelService or amount <= 0 then
				return false, cfg.MSG_SAVE_FAILED
			end
			local added = levelService:addXp(userId, amount)
			if not added.ok then
				return false, cfg.MSG_SAVE_FAILED
			end
			if type(levelService.flushPlayer) == "function" then
				levelService:flushPlayer(userId)
			end
			overheadController:refreshPlayer(player)
			return true, cfg.MSG_CLAIMED:format(tostring(amount) .. " XP")
		end
	end

	-- ── actions ──────────────────────────────────────────────────────────────────────────
	-- Robux rewards need the venue group (Config.Group.GROUP_ID; none configured = no check).
	-- Player:IsInGroup caches for the session, so a "no" is re-checked fresh — the player may have
	-- just joined through the prompt.
	local function groupId(): number
		local group = Config.Group
		local id = if type(group) == "table" then tonumber(group.GROUP_ID) else nil
		return if id and id > 0 then id else 0
	end

	local function inVenueGroup(player: Player): boolean
		local id = groupId()
		if id == 0 then
			return true
		end
		local okCached, cached = pcall(function()
			return player:IsInGroup(id)
		end)
		if okCached and cached then
			return true
		end
		local okFresh, groups = pcall(function()
			return GroupService:GetGroupsAsync(player.UserId)
		end)
		if okFresh and type(groups) == "table" then
			for _, entry in ipairs(groups) do
				if type(entry) == "table" and entry.Id == id then
					return true
				end
			end
		end
		return false
	end

	local REFUSAL_MESSAGES = {
		quota_full = "MSG_QUOTA_FULL",
		robux_taken = "MSG_ROBUX_TAKEN",
	}

	-- Claims one milestone. Returns true when it was claimed now.
	local function claimMilestone(session: Session, quest: Quest, milestone: Milestone): boolean
		local player = session.player
		local userId = player.UserId
		local day = today()
		local verdict = EventBoardDomain.canClaimMilestone(
			quest,
			milestone,
			session.doc,
			levelOf(userId),
			day,
			remainingOf(milestone.id)
		)
		if verdict ~= "ok" then
			return false
		end
		if milestone.rewardType == "robux" and not inVenueGroup(player) then
			pcall(function()
				eventRemote:FireClient(player, {
					type = "needGroup",
					groupId = groupId(),
					questId = quest.id,
					milestoneId = milestone.id,
				})
			end)
			notify.player(player, cfg.MSG_JOIN_GROUP, "INFO")
			return false
		end
		-- 1. The VPS: quota, one Robux reward per quest, the dashboard record. Idempotent per
		-- (milestone, player), so a retry after a later failure finds the slot already held.
		if not backend then
			notify.player(player, cfg.MSG_SAVE_FAILED, "ERROR")
			return false
		end
		local recorded = backend:claim(quest.id, milestone.id, player)
		if not recorded.ok then
			local messageKey = REFUSAL_MESSAGES[recorded.reason or ""]
			notify.player(player, if messageKey then cfg[messageKey] else cfg.MSG_SAVE_FAILED, "ERROR")
			return false
		end
		-- 2. The player's own document (another server may have paid it already).
		local claimed, merged = progressRepo:claim(userId, session.doc, quest, milestone, os.time())
		if not claimed.ok then
			notify.player(player, cfg.MSG_SAVE_FAILED, "ERROR")
			return false
		end
		if merged then
			session.doc = EventBoardDomain.mergeProgress(session.doc, merged)
		end
		if not claimed.value then
			return false
		end
		-- 3. The reward: granted in game, or only recorded (Robux / manual — the venue pays).
		local message: string
		if EventBoardDomain.IN_GAME_REWARDS[milestone.rewardType] then
			local ok, grantMessage = grantReward(player, milestone.rewardType, milestone.rewardValue)
			if not ok then
				progressRepo:unclaim(userId, quest, milestone)
				EventBoardDomain.unmarkMilestoneClaimed(session.doc, quest, milestone.id)
				local entry = session.doc.quests[tostring(quest.id)]
				local final = quest.milestones[#quest.milestones]
				if entry and final and final.id == milestone.id then
					entry.claimedAt = nil
				end
				backend:release(quest.id, milestone.id, userId)
				notify.player(player, grantMessage, "ERROR")
				return false
			end
			message = grantMessage
		else
			message = cfg.MSG_RECORDED:format(rewardLabel(milestone.rewardType, milestone.rewardValue), recorded.slot or 0)
		end
		notify.player(player, message, "SUCCESS")
		local final = quest.milestones[#quest.milestones]
		if final and final.id == milestone.id then
			local announce = cfg.MSG_COMPLETED_ALL:format(player.DisplayName, quest.title)
			task.delay(cfg.ANNOUNCE_DELAY, function()
				notify.all({
					message = announce,
					title = "Quest",
					description = announce,
					domain = "venue_quest",
					dedupeKey = "venue-quest-" .. userId .. "-" .. quest.id,
				}, "SUCCESS")
			end)
		end
		return true
	end

	-- The requested milestone, or the first one the player can claim now.
	local function onClaim(session: Session, quest: Quest, milestoneId: any)
		local milestone: Milestone? = nil
		if type(milestoneId) == "number" then
			milestone = EventBoardDomain.findMilestone(quest, milestoneId)
		else
			local level = levelOf(session.player.UserId)
			milestone = EventBoardDomain.claimableMilestones(quest, session.doc, level, today(), remainingOf)[1]
		end
		if milestone then
			claimMilestone(session, quest, milestone)
		end
		push(session)
	end

	-- One press: today's check-in (if not done yet), then the first claimable milestone.
	local function onCheckIn(session: Session, quest: Quest)
		local day = today()
		local counted = EventBoardDomain.checkIn(session.doc, quest, day)
		if counted then
			session.dirty = true
			-- A check-in is a once-a-day action the player waits for: save it now.
			flush(session)
			if backend then
				local year, month, dom = DailyQuestDomain.toCivil(day)
				local player = session.player
				backend:logCheckIn({
					questId = quest.id,
					userId = player.UserId,
					username = player.Name,
					displayName = player.DisplayName,
					day = string.format("%04d-%02d-%02d", year, month, dom),
					streak = EventBoardDomain.standing(quest, session.doc, 0, day).current,
				})
			end
		end
		local milestone = EventBoardDomain.claimableMilestones(quest, session.doc, 0, day, remainingOf)[1]
		if milestone then
			claimMilestone(session, quest, milestone)
		end
		push(session)
	end

	local function onSeen(session: Session, postId: any)
		if type(postId) ~= "number" then
			return
		end
		local key = tostring(math.floor(postId))
		if not session.doc.seenPosts[key] then
			session.doc.seenPosts[key] = true
			session.dirty = true
		end
	end

	table.insert(connections, eventRemote.OnServerEvent:Connect(function(player: Player, raw: any)
		if type(raw) ~= "table" or type(raw.action) ~= "string" then
			return
		end
		if not limiter:check(player.UserId) then
			return
		end
		local session = sessions[player.UserId]
		if not session or not session.loaded then
			return
		end
		if raw.action == "seen" then
			onSeen(session, raw.postId)
			return
		end
		if raw.action == "refresh" then
			push(session)
			return
		end
		local quest = findQuest(raw.questId)
		if not quest or session.busy then
			return
		end
		session.busy = true
		local ok, err = pcall(function()
			if raw.action == "claim" then
				onClaim(session, quest :: Quest, raw.milestoneId)
			elseif raw.action == "checkin" then
				onCheckIn(session, quest :: Quest)
			end
		end)
		session.busy = false
		if not ok then
			log:error("Event board action failed", { userId = player.UserId, action = raw.action, error = tostring(err) })
		end
	end))

	-- ── counters ─────────────────────────────────────────────────────────────────────────
	local controller = {}

	-- ShopController calls this for every completed (not replayed) Robux donation.
	function controller:onRobuxDonated(userId: number, amount: number)
		local session = sessions[userId]
		if not session or not session.loaded then
			return
		end
		local day = today()
		local changed = false
		for _, quest in ipairs(board().quests) do
			if EventBoardDomain.addAmount(session.doc, quest, "robux", amount, day) then
				changed = true
			end
		end
		if changed then
			session.dirty = true
			flush(session)
			push(session)
		end
	end

	local function tickPlaytime()
		local day = today()
		for _, session in pairs(sessions) do
			if session.loaded then
				local before = {}
				for _, quest in ipairs(board().quests) do
					if quest.goalType == "playtime" then
						local entry = session.doc.quests[tostring(quest.id)]
						before[quest.id] = if entry then entry.progress // 60 else 0
					end
				end
				local minuteMoved = false
				for _, quest in ipairs(board().quests) do
					if EventBoardDomain.addAmount(session.doc, quest, "playtime", cfg.PLAYTIME_TICK_SECONDS, day) then
						session.dirty = true
						local entry = session.doc.quests[tostring(quest.id)]
						if entry and entry.progress // 60 ~= before[quest.id] then
							minuteMoved = true
						end
					end
				end
				if minuteMoved then
					push(session)
				end
			end
		end
	end

	-- ── players ──────────────────────────────────────────────────────────────────────────
	local function applyLoaded(session: Session, loaded: any)
		if session.loaded or sessions[session.player.UserId] ~= session then
			return
		end
		if type(loaded) == "table" and loaded.ok then
			session.doc = loaded.value
		else
			-- Start empty; the first save merges with whatever the store really holds.
			log:warn("Venue quest progress load failed", {
				userId = session.player.UserId,
				err = if type(loaded) == "table" then loaded.error else tostring(loaded),
			})
		end
		session.loaded = true
		push(session)
	end

	-- Through the shared ProfileLoader once attached (Main wires it right after creating the
	-- loader); a direct load only if no loader was ever attached (see onStart).
	local function startLoad(session: Session)
		if session.loaded or session.loadQueued then
			return
		end
		session.loadQueued = true
		if profileLoader then
			profileLoader:enqueueKindDeferred(session.player, VENUE_QUEST_KIND)
			return
		end
		task.spawn(function()
			applyLoaded(session, progressRepo:load(session.player.UserId))
		end)
	end

	function controller:onPlayerAdded(player: Player)
		local userId = player.UserId
		if sessions[userId] then
			return
		end
		-- Back before the previous visit's progress was written: that copy is the newest one.
		local previous = departed[userId]
		if previous then
			departed[userId] = nil
			previous.player = player
			previous.busy = false
			sessions[userId] = previous
			push(previous)
			return
		end
		local session: Session = {
			player = player,
			doc = EventBoardDomain.emptyProgress(),
			loaded = false,
			loadQueued = false,
			dirty = false,
			saving = false,
			busy = false,
			leftAt = 0,
		}
		sessions[userId] = session
		if profileLoader then
			startLoad(session)
		end
	end

	function controller:attachProfileLoader(loader: any)
		if profileLoader or type(loader) ~= "table" then
			return
		end
		profileLoader = loader
		loader:register(VENUE_QUEST_KIND, function(player: Player)
			return progressRepo:load(player.UserId)
		end)
		loader:onLoaded(function(event)
			if event.kind ~= VENUE_QUEST_KIND then
				return
			end
			local session = sessions[event.player.UserId]
			if session and session.player == event.player then
				applyLoaded(session, event.result)
			end
		end)
		for _, session in pairs(sessions) do
			startLoad(session)
		end
	end

	-- Leave: keep the session until its progress is written (retries at LEAVE_FLUSH_RETRY_DELAYS);
	-- until 2026-09-24 a failed leave save was dropped with the session.
	function controller:onPlayerRemoving(player: Player)
		local userId = player.UserId
		local session = sessions[userId]
		if not session then
			return
		end
		sessions[userId] = nil
		if not session.loaded then
			return
		end
		session.leftAt = os.clock()
		departed[userId] = session
		capDeparted()
		task.spawn(function()
			local persistence = Config.Persistence
			local delays = if type(persistence) == "table" and type(persistence.LEAVE_FLUSH_RETRY_DELAYS) == "table"
				then persistence.LEAVE_FLUSH_RETRY_DELAYS
				else DEFAULT_LEAVE_RETRY_DELAYS
			for attempt = 0, #delays do
				if attempt > 0 then
					task.wait(delays[attempt])
				end
				if departed[userId] ~= session then
					return -- rejoined, or written by the periodic / shutdown flush
				end
				if flush(session) then
					forgetDeparted(userId, session)
					return
				end
			end
			log:warn("Venue quest progress still unsaved after leave retries; kept for the next flush", {
				userId = userId,
			})
		end)
	end

	--- BindToClose flush phase (Main launches it next to the other repo flushes): writes every
	--- dirty session and every departed one in parallel, waits out in-flight saves, retries
	--- failures until `budgetSec` runs out. Returns how many are still unsaved.
	function controller:flushAll(budgetSec: number?): number
		local deadline = os.clock() + (budgetSec or 20)
		local work: { { userId: number, session: Session } } = {}
		for userId, session in pairs(sessions) do
			if session.loaded and (session.dirty or session.saving) then
				table.insert(work, { userId = userId, session = session })
			end
		end
		for userId, session in pairs(departed) do
			table.insert(work, { userId = userId, session = session })
		end
		local remaining = #work
		local unsaved = 0
		for _, item in ipairs(work) do
			task.spawn(function()
				local ok, done = pcall(flushUntil, item.session, deadline)
				if ok and done then
					forgetDeparted(item.userId, item.session)
				else
					unsaved += 1
				end
				remaining -= 1
			end)
		end
		while remaining > 0 and os.clock() < deadline + 1 do
			task.wait(0.1)
		end
		if unsaved > 0 or remaining > 0 then
			log:warn("Venue quest progress flush incomplete", { unsaved = unsaved, pending = remaining })
		end
		return unsaved + remaining
	end

	-- Slots are polled only while a running quest has a milestone with a quota.
	local function updateQuotaWanted()
		if not backend then
			return
		end
		local wanted = false
		for _, quest in ipairs(EventBoardDomain.visibleQuests(board(), today())) do
			for _, milestone in ipairs(quest.milestones) do
				if milestone.quota then
					wanted = true
				end
			end
		end
		local was = backend._wantQuota
		backend:setQuotaWanted(wanted)
		if wanted and not was then
			task.spawn(function()
				backend:refreshQuota()
			end)
		end
	end

	function controller:onStart()
		backend = EventQuestBackend.new({
			logger = Logger.new("EventQuestBackend"),
			onQuota = pushAll,
		})
		backend:start()
		provider = EventBoardProvider.new({
			logger = Logger.new("EventBoardProvider"),
			onBoard = function()
				updateQuotaWanted()
				pushAll()
				scheduleBoundaryPush()
			end,
		})
		provider:start()
		-- Sessions created before a ProfileLoader was attached (none, when Main wired it).
		for _, session in pairs(sessions) do
			startLoad(session)
		end
		task.spawn(function()
			local sinceFlush = 0
			local tickIndex = 0
			while not destroyed do
				task.wait(cfg.PLAYTIME_TICK_SECONDS)
				if destroyed then
					break
				end
				local ok, err = pcall(tickPlaytime)
				if not ok then
					log:error("Playtime tick failed", { error = tostring(err) })
				end
				-- A new WIB day opens quests, closes others and resets "checked in today".
				local day = today()
				if day ~= lastDay then
					lastDay = day
					updateQuotaWanted()
					pushAll()
				end
				sinceFlush += cfg.PLAYTIME_TICK_SECONDS
				local writer = Config.PlayerDocWriter
				if type(writer) == "table" and writer.VENUE_FLUSH_STAGGER == true then
					-- Production hardening P3 (A8): each player is still written every
					-- PROGRESS_SAVE_SECONDS, but in groups (userId % groups) — one group per tick, spread
					-- over the tick — instead of every player in one burst.
					local groups = math.max(1, math.floor(cfg.PROGRESS_SAVE_SECONDS / cfg.PLAYTIME_TICK_SECONDS))
					local group = tickIndex % groups
					tickIndex += 1
					local due: { number } = {}
					for userId, session in pairs(sessions) do
						if userId % groups == group and session.dirty then
							table.insert(due, userId)
						end
					end
					local spacing = if #due > 0 then (cfg.PLAYTIME_TICK_SECONDS * 0.8) / #due else 0
					for index, userId in ipairs(due) do
						task.delay((index - 1) * spacing, function()
							local session = sessions[userId]
							if session and not destroyed then
								flush(session)
							end
						end)
					end
					if group == 0 then
						for userId, session in pairs(departed) do
							task.spawn(function()
								if flush(session) then
									forgetDeparted(userId, session)
								end
							end)
						end
					end
				elseif sinceFlush >= cfg.PROGRESS_SAVE_SECONDS then
					sinceFlush = 0
					for _, session in pairs(sessions) do
						task.spawn(flush, session)
					end
					for userId, session in pairs(departed) do
						task.spawn(function()
							if flush(session) then
								forgetDeparted(userId, session)
							end
						end)
					end
				end
			end
		end)
	end

	function controller:onDestroy()
		destroyed = true
		if provider then
			provider:destroy()
		end
		if backend then
			backend:destroy()
		end
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
		-- Last chance only: BindToClose already ran flushAll inside its flush phase, so these are
		-- normally clean no-ops (this runs after the 25 s shutdown wait).
		for _, session in pairs(sessions) do
			flush(session)
		end
		for _, session in pairs(departed) do
			flush(session)
		end
		limiter:destroy()
	end

	function controller:getBoard(): Board
		return board()
	end

	-- ── admin stats (AdminController "Edit stats") ───────────────────────────────────────
	-- The live streak quest a player checks in to: the first running streak quest on the board.
	local function activeStreakQuest(): Quest?
		for _, quest in ipairs(EventBoardDomain.visibleQuests(board(), today())) do
			if quest.goalType == "streak" then
				return quest
			end
		end
		return nil
	end

	-- Read-only snapshot for the admin sheet. nil when the player is not loaded or no streak quest runs.
	function controller:getStreakQuestStanding(userId: number): { label: string, progress: number, goal: number, completed: boolean }?
		local session = sessions[userId]
		local quest = activeStreakQuest()
		if not session or not session.loaded or not quest then
			return nil
		end
		local standing = EventBoardDomain.standing(quest, session.doc, 0, today())
		return {
			label = quest.title,
			progress = standing.current,
			goal = standing.target,
			completed = standing.complete,
		}
	end

	-- Admin write of the streak quest progress. Keeps the run going: after a non-zero progress
	-- write on a day not yet checked in, lastDay is set to yesterday so today's check-in counts.
	function controller:setStreakQuestStanding(userId: number, progress: number?, completed: boolean?): (boolean, string)
		local session = sessions[userId]
		if not session or not session.loaded then
			return false, "Player quest data is not ready"
		end
		if session.saving or session.busy then
			return false, "Try again in a moment"
		end
		local quest = activeStreakQuest()
		if not quest then
			return false, "No active streak quest"
		end
		local day = today()
		local goal = quest.goalValue
		local key = tostring(quest.id)
		local entry = session.doc.quests[key]
		if not entry then
			entry = { progress = 0, lastDay = 0, completed = false, claimedAt = nil, dueDay = quest.dueDay }
			session.doc.quests[key] = entry
		elseif entry.dueDay == nil then
			entry.dueDay = quest.dueDay
		end

		local newProgress = entry.progress
		if progress ~= nil then
			newProgress = math.clamp(math.floor(progress), 0, goal)
		end
		local newCompleted = entry.completed
		if completed ~= nil then
			newCompleted = completed
		elseif progress ~= nil then
			newCompleted = newProgress >= goal
		end
		if newCompleted then
			newProgress = goal
		end

		local newLastDay = entry.lastDay
		if newProgress == 0 then
			newLastDay = 0
		elseif entry.lastDay ~= day then
			newLastDay = day - 1
		end

		entry.progress = newProgress
		entry.completed = newCompleted
		entry.lastDay = newLastDay
		session.dirty = true
		flush(session)
		push(session)
		log:info("Streak quest set by admin", { userId = userId, progress = newProgress, completed = newCompleted })
		return true, "Quest updated"
	end

	for _, player in ipairs(Players:GetPlayers()) do
		controller:onPlayerAdded(player)
	end

	return controller
end

return createEventBoardController
