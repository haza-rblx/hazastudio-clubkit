--!strict
-- Server-side paint for workspace leaderboard SurfaceGuis (replicates to clients).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local WorkspaceLeaderboardRenderer = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Leaderboards.WorkspaceLeaderboardRenderer)

local log = Logger.new("WorkspaceLeaderboardRenderService")

local retryGeneration = 0

local WorkspaceLeaderboardRenderService = {}

local function renderOnce(payload: any): WorkspaceLeaderboardRenderer.RenderResult
	WorkspaceLeaderboardRenderer.setWarnHandler(function(_key: string, message: string, details: any?)
		log:warn(message, details)
	end)
	return WorkspaceLeaderboardRenderer.renderPayload(payload)
end

local function scheduleMissingRetry(payload: any, generation: number, attempt: number)
	local maxRetries = math.max(0, math.floor(tonumber(Config.Leaderboards.PAINT_MISSING_RETRY_MAX) or 3))
	local retryDelay = math.max(1, tonumber(Config.Leaderboards.PAINT_MISSING_RETRY_DELAY) or 5)
	if attempt > maxRetries then
		log:warn("Workspace leaderboard paint incomplete; retry budget exhausted", {
			attempt = attempt,
			maxRetries = maxRetries,
		})
		return
	end
	task.delay(retryDelay, function()
		if generation ~= retryGeneration then
			return
		end
		local result = renderOnce(payload)
		if result.ok or #result.missingBoards == 0 then
			return
		end
		log:warn("Workspace leaderboard paint incomplete; retrying", {
			missing = result.missingBoards,
			attempt = attempt,
			maxRetries = maxRetries,
		})
		scheduleMissingRetry(payload, generation, attempt + 1)
	end)
end

function WorkspaceLeaderboardRenderService.apply(payload: any): WorkspaceLeaderboardRenderer.RenderResult
	if Config.Leaderboards.SERVER_PAINT_WORKSPACE == false then
		return { ok = true, missingBoards = {} }
	end

	if type(payload) ~= "table" then
		WorkspaceLeaderboardRenderer.setAllBoardsLoading()
		return { ok = false, missingBoards = {} }
	end

	-- New apply cancels any in-flight missing-board retry chain.
	retryGeneration += 1
	local generation = retryGeneration

	local result = renderOnce(payload)
	if not result.ok and #result.missingBoards > 0 then
		log:warn("Workspace leaderboard paint incomplete", { missing = result.missingBoards })
		scheduleMissingRetry(payload, generation, 1)
	end

	return result
end

return WorkspaceLeaderboardRenderService
