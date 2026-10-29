--!strict
-- Server/Services/StreakService.lua
-- Responsibilities: evaluasi + update streak when player join.
-- Zero DataStore langsung, zero UI.

local Types         = require(game.ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local OverheadDomain = require(game.ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local StreakDomain  = require(game.ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.StreakDomain)
local ResultUtil    = require(game.ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger        = require(game.ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

type Result<T> = Types.Result<T>
type IOverheadRepository = Types.IOverheadRepository

local function createStreakService(deps: {
	repo : IOverheadRepository,
})
	local repo = deps.repo
	local log  = Logger.new("StreakService")

	local service = {}

	function service:processLogin(player: Player): Result<typeof(StreakDomain.evaluateStreak(0, 0, 0))>
		local userId = player.UserId
		local now    = os.time()

		-- Peek already-loaded overhead (SharedProfileLoader / Cache) before any
		-- UpdateAsync. Returning unchanged from UpdateAsync still burns write budget.
		local peek = repo:load(userId)
		if peek.ok then
			local peeked = StreakDomain.evaluateStreak(peek.value.streakDays, peek.value.lastLoginAt, now)
			if peeked.alreadyCounted then
				log:debug("Streak already counted today (skip UpdateAsync)", {
					player = player.Name,
					streak = peeked.newStreakDays,
				})
				return ResultUtil.Ok(peeked)
			end
		end

		local computedResult: typeof(StreakDomain.evaluateStreak(0, 0, 0))? = nil
		local updateResult = repo:update(userId, function(current)
			local streakResult = StreakDomain.evaluateStreak(current.streakDays, current.lastLoginAt, now)
			computedResult = streakResult
			if streakResult.alreadyCounted then
				return current
			end
			return OverheadDomain.mergeStored(current, {
				streakDays  = streakResult.newStreakDays,
				lastLoginAt = now,
			})
		end)

		if not updateResult.ok then
			log:warn("Failed to update data for streak", {
				player = player.Name,
				err    = updateResult.error,
			})
			return ResultUtil.Err(updateResult.error)
		end

		local streakResult = computedResult
		if not streakResult then
			return ResultUtil.Err("Failed to compute streak")
		end

		if streakResult.alreadyCounted then
			log:debug("Streak already counted today", {
				player = player.Name,
				streak = streakResult.newStreakDays,
			})
			return ResultUtil.Ok(streakResult)
		end

		if streakResult.didReset then
			log:info("Streak reset", {
				player    = player.Name,
				newStreak = streakResult.newStreakDays,
			})
		elseif streakResult.didIncrement then
			log:info("Streak naik", {
				player    = player.Name,
				newStreak = streakResult.newStreakDays,
			})
		end

		return ResultUtil.Ok(streakResult)
	end

	function service:setStreak(userId: number, newDays: number): Types.Result<boolean>
		if type(userId) ~= "number" or type(newDays) ~= "number" then
			return ResultUtil.Err("invalid args")
		end
		newDays = math.floor(math.max(0, newDays))
		local updateResult = repo:update(userId, function(current)
			return OverheadDomain.mergeStored(current, {
				streakDays  = newDays,
				lastLoginAt = os.time(),
			})
		end)
		if not updateResult.ok then
			log:warn("setStreak failed", { userId = userId, err = updateResult.error })
			return ResultUtil.Err(updateResult.error)
		end
		log:info("setStreak ok", { userId = userId, newDays = newDays })
		return ResultUtil.Ok(true)
	end

	return service
end

return createStreakService
