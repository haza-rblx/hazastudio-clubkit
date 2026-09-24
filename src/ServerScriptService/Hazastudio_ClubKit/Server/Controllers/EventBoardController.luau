--!strict
-- Server/Controllers/EventBoardController.luau
-- Event board (ADR 0015): venue posts + venue quests authored in the customer dashboard.
--   * EventBoardProvider pulls the board; every change is pushed to every player.
--   * Per player: a progress document (VenueQuestProgressRepository) loaded on join, counters
--     (Robux donated, seconds played) accumulated here and flushed periodically and on leave.
--   * One RemoteEvent, both ways. Client → server: { action = "checkin" | "claim", questId }
--     or { action = "seen", postId }. Server → client: { type = "state", ... } (see buildState).
--   * Claims: checked here against the player's real standing, recorded atomically in the
--     DataStore first (refused if another server already paid it), then the reward is granted;
--     a failed grant rolls the claim back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local EventBoardDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.EventBoardDomain)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local StreakDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.StreakDomain)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local TextFilterUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.TextFilterUtil)

local EventBoardProvider = require(script.Parent.Parent.Services.EventBoardProvider)

type Board = EventBoardDomain.Board
type Quest = EventBoardDomain.Quest
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
})
	local log = deps.logger or Logger.new("EventBoardController")
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
		local posts = {}
		for _, post in ipairs(current.posts) do
			table.insert(posts, {
				id = post.id,
				category = post.category,
				title = post.title,
				body = post.body,
				imageAssetId = post.imageAssetId,
				publishedAt = post.publishedAt,
			})
		end
		local quests = {}
		for _, quest in ipairs(EventBoardDomain.visibleQuests(current, day)) do
			local standing = EventBoardDomain.standing(quest, session.doc, level, day)
			table.insert(quests, {
				id = quest.id,
				category = quest.category,
				title = quest.title,
				description = quest.description,
				goalType = quest.goalType,
				goalValue = quest.goalValue,
				rewardType = quest.rewardType,
				rewardValue = quest.rewardValue,
				dueDate = quest.dueDate,
				current = standing.current,
				target = standing.target,
				complete = standing.complete,
				claimed = standing.claimed,
				checkedInToday = standing.checkedInToday,
				strip = if quest.goalType == "streak" then EventBoardDomain.dayStrip(quest, session.doc, day) else nil,
			})
		end
		-- Sent until the player has seen it (the client reports "seen" when it opens); the client
		-- opens it at most once per session, so a push that lands before it listens loses nothing.
		local joinPost = nil
		local post = EventBoardDomain.joinPost(current)
		if post and not session.doc.seenPosts[tostring(post.id)] then
			joinPost = post.id
		end
		return {
			type = "state",
			serverTime = now,
			secondsToNextDay = EventBoardDomain.secondsUntilNextDay(now),
			posts = posts,
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

	-- Returns true when nothing is left to write (saved now, or already clean). False while a
	-- save is in flight or when the save failed (the session stays dirty for a retry).
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
			return progressRepo:save(session.player.UserId, session.doc)
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
	local function grantReward(player: Player, quest: Quest): (boolean, string)
		local userId = player.UserId
		if quest.rewardType == "membership" then
			local tier = OverheadDomain.normalizeMembershipTier(quest.rewardValue)
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
		elseif quest.rewardType == "title" then
			local filtered = TextFilterUtil.filterForBroadcast(userId, quest.rewardValue)
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
			if skipped then
				return true, cfg.MSG_REWARD_SKIPPED_TITLE
			end
			overheadController:invalidateBuildCache(userId)
			overheadController:refreshPlayer(player, "recovery")
			return true, cfg.MSG_CLAIMED:format('"' .. text .. '" title')
		else
			local amount = tonumber(quest.rewardValue) or 0
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
	local function onClaim(session: Session, quest: Quest)
		local player = session.player
		local userId = player.UserId
		local day = today()
		local verdict = EventBoardDomain.canClaim(quest, session.doc, levelOf(userId), day)
		if verdict ~= "ok" then
			push(session)
			return
		end
		local key = tostring(quest.id)
		local claimed, merged = progressRepo:claim(userId, session.doc, key, os.time())
		if not claimed.ok then
			notify.player(player, cfg.MSG_SAVE_FAILED, "ERROR")
			return
		end
		if merged then
			session.doc = EventBoardDomain.mergeProgress(session.doc, merged)
		end
		if not claimed.value then
			-- Already paid out by another server.
			push(session)
			return
		end
		local ok, message = grantReward(player, quest)
		if not ok then
			progressRepo:unclaim(userId, key)
			local entry = session.doc.quests[key]
			if entry then
				entry.claimedAt = nil
			end
			notify.player(player, message, "ERROR")
			push(session)
			return
		end
		notify.player(player, message, "SUCCESS")
		push(session)
		local announce = cfg.MSG_COMPLETED_ALL:format(player.DisplayName, quest.title)
		task.delay(cfg.ANNOUNCE_DELAY, function()
			notify.all({
				message = announce,
				title = "Quest",
				description = announce,
				domain = "venue_quest",
				dedupeKey = "venue-quest-" .. userId .. "-" .. key,
			}, "SUCCESS")
		end)
	end

	local function onCheckIn(session: Session, quest: Quest)
		local counted = EventBoardDomain.checkIn(session.doc, quest, today())
		if counted then
			session.dirty = true
			-- A check-in is a once-a-day action the player waits for: save it now.
			flush(session)
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
				onClaim(session, quest :: Quest)
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

	function controller:onStart()
		provider = EventBoardProvider.new({
			logger = Logger.new("EventBoardProvider"),
			onBoard = function()
				pushAll()
			end,
		})
		provider:start()
		-- Sessions created before a ProfileLoader was attached (none, when Main wired it).
		for _, session in pairs(sessions) do
			startLoad(session)
		end
		task.spawn(function()
			local sinceFlush = 0
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
					pushAll()
				end
				sinceFlush += cfg.PLAYTIME_TICK_SECONDS
				if sinceFlush >= cfg.PROGRESS_SAVE_SECONDS then
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

	for _, player in ipairs(Players:GetPlayers()) do
		controller:onPlayerAdded(player)
	end

	return controller
end

return createEventBoardController
