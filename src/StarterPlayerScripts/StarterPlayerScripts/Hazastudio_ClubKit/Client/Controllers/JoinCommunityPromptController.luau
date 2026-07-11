--!strict
-- After loading/gameplay entry, optionally prompt the player to join the club group (once per session).

local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local PROMPT_DELAY_SEC = 0.75

local promptedThisSession = false

local function tryPromptAfterGameplay()
	if promptedThisSession then
		return
	end
	if Config.FeatureFlags.PromptJoinCommunityOnLoadEnabled ~= true then
		return
	end
	local groupId = Config.Group.GROUP_ID
	if type(groupId) ~= "number" or groupId <= 0 then
		return
	end

	promptedThisSession = true
	task.delay(PROMPT_DELAY_SEC, function()
		pcall(function()
			GroupService:PromptJoinAsync(groupId)
		end)
	end)
end

return {
	tryPromptAfterGameplay = tryPromptAfterGameplay,
}
