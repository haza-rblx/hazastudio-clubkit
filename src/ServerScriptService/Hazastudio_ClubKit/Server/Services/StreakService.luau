--!strict
-- Server/Services/StreakService.lua
-- Tanggung jawab: evaluasi + update streak saat player join.
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
			log:warn("Gagal update data untuk streak", {
				player = player.Name,
				err    = updateResult.error,
			})
			return ResultUtil.Err(updateResult.error)
		end

		local streakResult = computedResult
		if not streakResult then
			return ResultUtil.Err("Gagal menghitung streak")
		end

		if streakResult.alreadyCounted then
			log:debug("Streak sudah dihitung hari ini", {
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

	return service
end

return createStreakService
