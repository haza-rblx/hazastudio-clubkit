--!strict
-- Server/HideDefaultOverhead.server.lua
-- Hide Roblox default overhead name tag for all players.
-- Harus run di server so berlaku for all client.

local Players = game:GetService("Players")

-- Per-player CharacterAdded connection tracking.
-- Prevent leak: when player leaves, connections explicitly disconnected.
local characterAddedConns: { [number]: RBXScriptConnection } = {}

local function hideDefaultOverhead(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

local function onPlayerAdded(player: Player)
	-- Handle characters already present (join mid-session in Studio)
	if player.Character then
		task.spawn(hideDefaultOverhead, player)
	end

	-- Track connection so it can be cleaned up when player leaves
	local old = characterAddedConns[player.UserId]
	if old then
		old:Disconnect()
	end
	characterAddedConns[player.UserId] = player.CharacterAdded:Connect(function()
		task.spawn(hideDefaultOverhead, player)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player: Player)
	local conn = characterAddedConns[player.UserId]
	if conn then
		conn:Disconnect()
		characterAddedConns[player.UserId] = nil
	end
end)

-- Handle players already present when server starts
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
