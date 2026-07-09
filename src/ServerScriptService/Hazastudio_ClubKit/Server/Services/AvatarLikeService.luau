--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)

type Result<T> = Types.Result<T>
type AvatarContextLikeAction = Types.AvatarContextLikeAction
type AvatarLikeTransition = Types.AvatarLikeTransition

type ToggleLikeOutcome = {
	targetUserId: number,
	likesCount: number,
	viewerHasLiked: boolean,
	transition: AvatarLikeTransition,
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
			viewerHasLiked = toggleResult.value.nextState == 1,
			transition = toggleResult.value.transition,
		})
	end

	return service
end

return createAvatarLikeService
