--!strict
-- Shows chat bubbles on multiple players for /crowd.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Chat = game:GetService("Chat")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local function createCrowdController(deps: {
	remotes: Folder?,
})
	local remotes = deps.remotes or ReplicatedStorage:WaitForChild("Remotes", 30) :: Folder
	local crowdConfig = Config.Crowd
	local sayRemote = remotes:WaitForChild(crowdConfig.REMOTE_SAY, 30) :: RemoteEvent?

	local function bubbleOnPlayer(userId: number, text: string)
		local player = Players:GetPlayerByUserId(userId)
		if player == nil then
			return
		end
		local character = player.Character
		if character == nil then
			return
		end
		local head = character:FindFirstChild("Head")
		if head == nil or not head:IsA("BasePart") then
			return
		end
		pcall(function()
			Chat:Chat(head, text)
		end)
	end

	local controller = {}

	function controller:init()
		if Config.FeatureFlags.CrowdEnabled ~= true then
			return
		end
		if sayRemote == nil or not sayRemote:IsA("RemoteEvent") then
			return
		end
		sayRemote.OnClientEvent:Connect(function(payload: any)
			if type(payload) ~= "table" then
				return
			end
			local text = tostring(payload.text or "")
			if text == "" then
				return
			end
			local speakers = payload.speakerUserIds
			if type(speakers) ~= "table" then
				return
			end
			for _, userId in ipairs(speakers) do
				local id = tonumber(userId)
				if id then
					bubbleOnPlayer(id, text)
				end
			end
		end)
	end

	function controller:destroy() end

	return controller
end

return createCrowdController
