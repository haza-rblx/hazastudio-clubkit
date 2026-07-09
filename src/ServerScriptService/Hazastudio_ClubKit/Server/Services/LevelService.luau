--!strict
-- Server/Services/LevelService.lua
-- Business logic XP dan level. Zero DataStore langsung, zero UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config         = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local Types          = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local LevelDomain    = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.LevelDomain)
local ResultUtil     = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger         = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

type Result<T> = Types.Result<T>
type IOverheadRepository = Types.IOverheadRepository

local function createLevelService(deps: {
	repo : IOverheadRepository,
})
	local repo = deps.repo
	local log  = Logger.new("LevelService")

	local pendingXp: {[number]: number} = {}

	local service = {}

	local function flush(userId: number): Result<LevelDomain.LevelUpResult?>
		local pending = pendingXp[userId]
		if not pending or pending <= 0 then
			return ResultUtil.Ok(nil)
		end
		pendingXp[userId] = nil

		local latestLevelResult: LevelDomain.LevelUpResult? = nil
		local updateResult = repo:update(userId, function(current)
			local computed = LevelDomain.addXp(current.level, current.xp or 0, pending)
			latestLevelResult = computed
			if computed.newLevel == current.level and computed.newXp == (current.xp or 0) then
				return current
			end
			return OverheadDomain.mergeStored(current, {
				level = computed.newLevel,
				xp    = computed.newXp,
			})
		end)

		if not updateResult.ok then
			pendingXp[userId] = pending
			log:error("Gagal save XP", { userId = userId, err = updateResult.error })
			return ResultUtil.Err(updateResult.error)
		end

		local levelResult = latestLevelResult
		if not levelResult then
			return ResultUtil.Ok(nil)
		end

		if levelResult.didLevelUp then
			log:info("Level up", {
				userId = userId,
				level  = levelResult.newLevel,
				gained = levelResult.levelsGained,
			})
		else
			log:debug("XP saved", { userId = userId, xp = levelResult.newXp })
		end

		return ResultUtil.Ok(levelResult)
	end

	function service:addXp(userId: number, amount: number): Result<LevelDomain.LevelUpResult?>
		pendingXp[userId] = (pendingXp[userId] or 0) + amount
		if pendingXp[userId] >= Config.Level.SAVE_BATCH_SIZE then
			return flush(userId)
		end
		return ResultUtil.Ok(nil)
	end

	function service:flushPlayer(userId: number): Result<LevelDomain.LevelUpResult?>
		return flush(userId)
	end

	function service:setLevel(userId: number, level: number): Result<nil>
		local newLevel = math.clamp(level, 1, Config.Level.MAX_LEVEL > 0 and Config.Level.MAX_LEVEL or math.huge)
		local updateResult = repo:update(userId, function(current)
			return OverheadDomain.mergeStored(current, {
				level = newLevel,
				xp    = 0,
			})
		end)
		if not updateResult.ok then
			return ResultUtil.Err(updateResult.error)
		end

		pendingXp[userId] = nil

		log:info("Level set by admin", { userId = userId, level = newLevel })
		return ResultUtil.Ok(nil)
	end

	return service
end

return createLevelService
