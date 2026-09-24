--!strict
-- Server/Services/DailyQuestService.luau
-- Daily Quest addon (1000-02-DQ-ADDON): manual check-in, quest progress, membership reward.
-- Zero UI. The streak, the quest counter and the reward move in ONE repo:update, so a
-- check-in can never keep its progress while losing the membership it earned.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local StreakDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.StreakDomain)
local DailyQuestDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.DailyQuestDomain)
local ResultUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

type Result<T> = Types.Result<T>
type IOverheadRepository = Types.IOverheadRepository
type MembershipTier = Types.MembershipTier

export type Snapshot = {
	enabled: boolean,
	status: string, -- DailyQuestDomain.View status
	progress: number,
	target: number,
	checkedInToday: boolean, -- the STREAK check-in, which is what the button spends
	streakDays: number,
	dueDate: { number }?, -- { year, month, day } WIB
	title: string,
	rewardLabel: string,
	secondsToReset: number,
}

export type CheckInOutcome = {
	streak: typeof(StreakDomain.evaluateStreak(0, 0, 0)),
	questCounted: boolean,
	questDidReset: boolean,
	questCompleted: boolean,
	rewardGranted: boolean,
	rewardAlreadyOwned: boolean,
	snapshot: Snapshot,
}

local SECONDS_PER_DAY = 86400
local WIB_OFFSET_SECONDS = 7 * 3600

local function createDailyQuestService(deps: {
	repo: IOverheadRepository,
})
	local repo = deps.repo
	local log = Logger.new("DailyQuestService")
	local cfg = Config.DailyQuest

	local service = {}

	-- Manual check-in replaces the join-time streak only when the buyer switched the addon on
	-- AND installed the panel. The server can see StarterGui, so a place without the GUI keeps
	-- the old behaviour instead of leaving nobody able to check in.
	function service:isManualMode(): boolean
		return Config.FeatureFlags.DailyQuestEnabled == true and StarterGui:FindFirstChild(cfg.GUI_NAME) ~= nil
	end

	function service:getQuest(): DailyQuestDomain.Quest?
		return DailyQuestDomain.normalizeQuest({
			Id = cfg.QUEST_ID,
			TargetDays = cfg.TARGET_DAYS,
			StartDate = cfg.START_DATE,
			DueDate = cfg.DUE_DATE,
		})
	end

	local function rewardTier(): MembershipTier?
		local tier = OverheadDomain.normalizeMembershipTier(cfg.REWARD_TIER)
		if tier and OverheadDomain.isPaidMembershipTier(tier) then
			return tier
		end
		return nil
	end

	function service:getRewardLabel(): string
		local tier = rewardTier()
		return if tier then OverheadDomain.getMembershipChatLabel(tier) else tostring(cfg.REWARD_TIER)
	end

	local function buildSnapshot(stored: Types.OverheadStoredData, now: number): Snapshot
		local quest = service:getQuest()
		local today = StreakDomain.toDayNumber(now)
		local view = DailyQuestDomain.view(DailyQuestDomain.sanitizeState(stored.dailyQuest), quest, today)
		local rewardLabel = service:getRewardLabel()
		local dueDate: { number }? = nil
		if quest then
			local y, m, d = DailyQuestDomain.toCivil(quest.dueDay)
			dueDate = { y, m, d }
		end
		local title = string.gsub(tostring(cfg.TITLE_TEXT), "{days}", tostring(view.target))
		title = string.gsub(title, "{tier}", (string.gsub(rewardLabel, "%%", "%%%%")))
		return {
			enabled = service:isManualMode(),
			status = view.status,
			progress = view.progress,
			target = view.target,
			checkedInToday = stored.lastLoginAt > 0 and StreakDomain.toDayNumber(stored.lastLoginAt) == today,
			streakDays = stored.streakDays,
			dueDate = dueDate,
			title = title,
			rewardLabel = rewardLabel,
			secondsToReset = SECONDS_PER_DAY - ((now + WIB_OFFSET_SECONDS) % SECONDS_PER_DAY),
		}
	end

	function service:getSnapshot(player: Player): Result<Snapshot>
		local loaded = repo:load(player.UserId)
		if not loaded.ok then
			return ResultUtil.Err(loaded.error)
		end
		return ResultUtil.Ok(buildSnapshot(loaded.value, os.time()))
	end

	-- Err("already_checked_in") when today's streak day is spent; any other Err is a save failure.
	function service:checkIn(player: Player): Result<CheckInOutcome>
		local userId = player.UserId
		local now = os.time()
		local today = StreakDomain.toDayNumber(now)
		local quest = self:getQuest()
		local tier = rewardTier()

		-- UpdateAsync may run the mutator more than once; every capture is rewritten per run,
		-- so the outcome always describes the attempt that was actually committed.
		local outcome: CheckInOutcome? = nil
		local alreadyCounted = false
		local updated = repo:update(userId, function(current)
			outcome = nil
			alreadyCounted = false
			local streak = StreakDomain.evaluateStreak(current.streakDays, current.lastLoginAt, now)
			if streak.alreadyCounted then
				alreadyCounted = true
				return current
			end
			local questResult = DailyQuestDomain.evaluateCheckIn(
				DailyQuestDomain.sanitizeState(current.dailyQuest),
				quest,
				today
			)
			local nextData = OverheadDomain.mergeStored(current, {
				streakDays = streak.newStreakDays,
				lastLoginAt = now,
				dailyQuest = if questResult.state then questResult.state else OverheadDomain.NIL,
			})
			local granted, alreadyOwned = false, false
			if questResult.completedNow and tier then
				if OverheadDomain.hasStoredMembershipAtLeast(nextData, tier) then
					alreadyOwned = true
				else
					nextData = OverheadDomain.addGiftedMembership(nextData, tier, 0, "daily_quest")
					granted = true
				end
			end
			outcome = {
				streak = streak,
				questCounted = questResult.counted,
				questDidReset = questResult.didReset,
				questCompleted = questResult.completedNow,
				rewardGranted = granted,
				rewardAlreadyOwned = alreadyOwned,
				snapshot = (nil :: any),
			}
			return nextData
		end)

		if not updated.ok then
			log:warn("Daily check-in save failed", { userId = userId, err = updated.error })
			return ResultUtil.Err(updated.error)
		end
		if alreadyCounted then
			return ResultUtil.Err("already_checked_in")
		end
		local final = outcome
		if not final then
			return ResultUtil.Err("no_outcome")
		end
		final.snapshot = buildSnapshot(updated.value, now)
		if final.questCompleted then
			log:info("Daily quest completed", {
				player = player.Name,
				quest = quest and quest.id,
				tier = tier,
				granted = final.rewardGranted,
			})
		end
		if final.questCompleted and not tier then
			log:warn("Daily quest completed but DailyQuest.RewardTier is not a paid tier", {
				tier = cfg.REWARD_TIER,
			})
		end
		return ResultUtil.Ok(final)
	end

	return service
end

return createDailyQuestService
