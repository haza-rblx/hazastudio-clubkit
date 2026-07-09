--!strict
-- Server-side paint for workspace leaderboard SurfaceGuis (replicates to clients).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local WorkspaceLeaderboardRenderer = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Leaderboards.WorkspaceLeaderboardRenderer)

local log = Logger.new("WorkspaceLeaderboardRenderService")

local retryGeneration = 0

local WorkspaceLeaderboardRenderService = {}

function WorkspaceLeaderboardRenderService.apply(payload: any): WorkspaceLeaderboardRenderer.RenderResult
	if Config.Leaderboards.SERVER_PAINT_WORKSPACE == false then
		return { ok = true, missingBoards = {} }
	end

	if type(payload) ~= "table" then
		WorkspaceLeaderboardRenderer.setAllBoardsLoading()
		return { ok = false, missingBoards = {} }
	end

	WorkspaceLeaderboardRenderer.setWarnHandler(function(_key: string, message: string, details: any?)
		log:warn(message, details)
	end)

	local result = WorkspaceLeaderboardRenderer.renderPayload(payload)
	if not result.ok and #result.missingBoards > 0 then
		log:warn("Workspace leaderboard paint incomplete", { missing = result.missingBoards })
		retryGeneration += 1
		local generation = retryGeneration
		task.delay(5, function()
			if generation ~= retryGeneration then
				return
			end
			WorkspaceLeaderboardRenderService.apply(payload)
		end)
	end

	return result
end

return WorkspaceLeaderboardRenderService
