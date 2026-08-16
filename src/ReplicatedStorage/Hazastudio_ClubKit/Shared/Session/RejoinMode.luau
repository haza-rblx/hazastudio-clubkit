--!strict
-- Detects "this join is an AFK auto-rejoin" from teleport data, once.
-- Consumed by LoadingBootstrap (skip loading), JoinCommunityPromptController
-- (skip prompt), and Main.client (instant dance/music restore) so a rejoin
-- lands seamlessly instead of replaying the first-join interruptions.

local Players = game:GetService("Players")

local RejoinMode = {}

local cached: boolean? = nil

function RejoinMode.isAfkRejoin(): boolean
	if cached ~= nil then
		return cached
	end
	local result = false
	local player = Players.LocalPlayer
	if player then
		local ok, joinData = pcall(function()
			return player:GetJoinData()
		end)
		if ok and type(joinData) == "table" then
			local teleportData = (joinData :: any).TeleportData
			if type(teleportData) == "table" then
				local restore = (teleportData :: any).sessionRestore
				if type(restore) == "table" and (restore :: any).afkRejoin == true then
					result = true
				end
			end
		end
	end
	cached = result
	return result
end

return RejoinMode
