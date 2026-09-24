--!strict
-- Server/Controllers/StreakController.lua
-- Fire StreakNotif to client after processLogin succeeds.
-- Daily Quest addon: in manual mode the join does not advance the streak; the DailyQuest
-- remote's check-in does, and the same StreakNotif carries the quest result for the flight.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local NetworkManager = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkManager)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local log = Logger.new("StreakController")

local function createStreakController(deps: {
	streakService: any,
	overheadController: any,
	remotes: Folder,
	dailyQuestService: any?,
	notify: any?,
})
	local streakService = deps.streakService
	local overheadController = deps.overheadController
	local remotes = deps.remotes
	local dailyQuestService = deps.dailyQuestService
	local notify = deps.notify
	local processedUserIds: { [number]: boolean } = {}

	local function getOrCreateRemote(name: string): RemoteEvent
		local existing = remotes:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotes
		return remote
	end

	local notifRemote = getOrCreateRemote(Config.Streak.REMOTE_NOTIF)
	local notifNetwork = NetworkManager.create({
		reliable = notifRemote,
		logger = log,
		isServer = true,
	})

	local function isMilestone(days: number): boolean
		for _, milestone in ipairs(Config.Streak.MILESTONE_DAYS) do
			if days == milestone then
				return true
			end
		end
		return false
	end

	local function isManualMode(): boolean
		return dailyQuestService ~= nil and dailyQuestService:isManualMode()
	end

	-- ── Daily Quest remote ──────────────────────────────────────────────
	-- Client -> server: { action = "sync" | "checkin" }. Server -> client: { kind = "state", state }.
	local questRemote: RemoteEvent? = nil
	local questLimiter = RateLimiter.new(Config.DailyQuest.RATE_MAX, Config.DailyQuest.RATE_WINDOW)
	local checkInFlight: { [number]: boolean } = {}

	local function pushQuestState(player: Player, snapshot: any)
		if questRemote and player.Parent then
			questRemote:FireClient(player, { kind = "state", state = snapshot })
		end
	end

	local function sendQuestState(player: Player)
		if not dailyQuestService then
			return
		end
		local snapshot = dailyQuestService:getSnapshot(player)
		if snapshot.ok then
			pushQuestState(player, snapshot.value)
		end
	end

	local function handleCheckIn(player: Player)
		local userId = player.UserId
		if checkInFlight[userId] then
			return
		end
		checkInFlight[userId] = true
		local ok, err = pcall(function()
			local result = dailyQuestService:checkIn(player)
			if not result.ok then
				if result.error ~= "already_checked_in" and notify then
					notify.player(player, Config.DailyQuest.MSG_SAVE_FAILED, "ERROR")
				end
				sendQuestState(player)
				return
			end
			local outcome = result.value
			local streak = outcome.streak
			overheadController:refreshPlayer(player, if outcome.rewardGranted then "recovery" else nil)
			-- The new quest state rides on the streak notif instead of a separate push, so the
			-- panel can hold today's circle unfilled until the overlay's flame lands on it.
			notifNetwork:fireClient(player, {
				streakDays = streak.newStreakDays,
				didReset = streak.didReset,
				didIncrement = streak.didIncrement,
				isMilestone = isMilestone(streak.newStreakDays),
				quest = {
					counted = outcome.questCounted,
					completed = outcome.questCompleted,
					state = outcome.snapshot,
				},
			})
			if outcome.questCompleted and notify then
				local label = outcome.snapshot.rewardLabel
				if outcome.rewardGranted then
					-- Held until the player's own overlay and flame flight have played out.
					local message = Config.DailyQuest.MSG_COMPLETED_ALL:format(player.DisplayName, label)
					task.delay(Config.DailyQuest.ANNOUNCE_DELAY, function()
						notify.all({
							message = message,
							title = "Daily Streak",
							description = message,
							domain = "daily_quest",
							dedupeKey = "daily-quest-" .. tostring(player.UserId),
						}, "SUCCESS")
					end)
				else
					notify.player(player, Config.DailyQuest.MSG_COMPLETED_ALREADY:format(label), "SUCCESS")
				end
			end
			log:info("Daily check-in", {
				player = player.Name,
				streak = streak.newStreakDays,
				quest = outcome.snapshot.progress,
				completed = outcome.questCompleted,
			})
		end)
		checkInFlight[userId] = nil
		if not ok then
			log:warn("Daily check-in errored", { player = player.Name, err = err })
		end
	end

	if dailyQuestService and Config.FeatureFlags.DailyQuestEnabled == true then
		local remote = getOrCreateRemote(Config.DailyQuest.REMOTE)
		questRemote = remote
		remote.OnServerEvent:Connect(function(player: Player, raw: any)
			if type(raw) ~= "table" or not questLimiter:check(player.UserId) then
				return
			end
			if raw.action == "sync" then
				task.spawn(sendQuestState, player)
			elseif raw.action == "checkin" and isManualMode() then
				task.spawn(handleCheckIn, player)
			end
		end)
		Players.PlayerRemoving:Connect(function(player: Player)
			checkInFlight[player.UserId] = nil
		end)
	end

	local controller = {}

	function controller:processLoginForPlayer(player: Player)
		if not player.Parent then
			return
		end
		local userId = player.UserId
		if processedUserIds[userId] then
			return
		end
		processedUserIds[userId] = true

		task.spawn(function()
			if not player.Character then
				player.CharacterAdded:Wait()
			end
			task.wait(Config.Streak.CLIENT_READY_DELAY)
			if not player.Parent then
				processedUserIds[userId] = nil
				return
			end

			-- Manual mode: the panel's button owns the streak. Push the state so the panel can
			-- decide whether to open itself; the client also asks on its own in case this lands
			-- before its listener is connected.
			if isManualMode() then
				sendQuestState(player)
				return
			end

			local result = streakService:processLogin(player)
			if not result.ok then
				processedUserIds[userId] = nil
				return
			end

			local streakResult = result.value
			if streakResult.alreadyCounted then
				return
			end

			local payload = {
				streakDays = streakResult.newStreakDays,
				didReset = streakResult.didReset,
				didIncrement = streakResult.didIncrement,
				isMilestone = isMilestone(streakResult.newStreakDays),
			}
			overheadController:refreshPlayer(player)
			notifNetwork:fireClient(player, payload)
			log:info("StreakNotif fired", {
				player = player.Name,
				streak = streakResult.newStreakDays,
				milestone = payload.isMilestone,
			})
		end)
	end

	function controller:onPlayerRemoving(player: Player)
		processedUserIds[player.UserId] = nil
	end

	log:info("StreakController initialized", {})
	return controller
end

return createStreakController
