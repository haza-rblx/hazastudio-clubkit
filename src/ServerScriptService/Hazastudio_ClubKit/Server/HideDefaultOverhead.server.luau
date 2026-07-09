--!strict
-- Server/HideDefaultOverhead.server.lua
-- Sembunyikan overhead name tag bawaan Roblox untuk semua player.
-- Harus jalan di server agar berlaku untuk semua client.

local Players = game:GetService("Players")

-- Per-player CharacterAdded connection tracking.
-- Cegah leak: saat player leave, koneksi di-disconnect eksplisit.
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
	-- Handle character yang sudah ada (join mid-session di Studio)
	if player.Character then
		task.spawn(hideDefaultOverhead, player)
	end

	-- Track connection agar bisa di-cleanup saat player leave
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

-- Handle player yang sudah ada saat server start
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
