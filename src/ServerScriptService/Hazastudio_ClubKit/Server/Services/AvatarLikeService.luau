--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local AvatarLikePolicy = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.AvatarLikePolicy)
local StreakDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.StreakDomain)

type Result<T> = Types.Result<T>
type AvatarContextLikeAction = Types.AvatarContextLikeAction
type AvatarLikeTransition = Types.AvatarLikeTransition

type ToggleLikeOutcome = {
	targetUserId: number,
	likesCount: number,
	viewerHasLiked: boolean,
	transition: AvatarLikeTransition,
	alreadyLikedToday: boolean,
}

local function createAvatarLikeService(deps: {
	logger: Types.ILogger,
	avatarLikeRepository: any,
})
	local log = deps.logger
	local repository = deps.avatarLikeRepository

	local service = {}

	function service:toggle(giverPlayer: Player, targetPlayer: Player, action: AvatarContextLikeAction): Result<ToggleLikeOutcome>
		if giverPlayer.UserId == targetPlayer.UserId then
			return Result.Err("Cannot like yourself")
		end

		local toggleResult = repository:toggle(targetPlayer.UserId, giverPlayer.UserId, action)
		if not toggleResult.ok then
			log:warn("AvatarLikeService toggle failed", {
				giverUserId = giverPlayer.UserId,
				targetUserId = targetPlayer.UserId,
				action = action,
				error = toggleResult.error,
			})
			return Result.Err("Failed to update like")
		end
		if type(repository.saveTargetMetadata) == "function" then
			task.spawn(function()
				repository:saveTargetMetadata(targetPlayer)
			end)
		end

		return Result.Ok({
			targetUserId = targetPlayer.UserId,
			likesCount = toggleResult.value.totalLikes,
			-- Not `nextState == 1`: in daily mode the stored value is a WIB day stamp, and "liked"
			-- means "liked today".
			viewerHasLiked = AvatarLikePolicy.viewerHasLiked(
				toggleResult.value.nextState,
				StreakDomain.toDayNumber(os.time()),
				Config.AvatarContext.DAILY_LIKE_RESET == true
			),
			transition = toggleResult.value.transition,
			alreadyLikedToday = toggleResult.value.alreadyLikedToday == true,
		})
	end

	return service
end

return createAvatarLikeService
