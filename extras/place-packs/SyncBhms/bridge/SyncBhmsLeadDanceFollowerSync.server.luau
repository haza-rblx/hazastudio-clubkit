--!strict
--[[
  Place-pack bridge: mirrors BHMS's own follower graph (Character.Syncing,
  see SyncServer/Modules/SyncManager.luau) onto the same Character attributes
  Club Kit's SyncLeadTopbarController already reads (IsLeader, FollowerCount)
  — making SyncBhmsLeadDanceBridge's "Lead Dance" dropdown dynamic instead of
  role-title-only. No changes to SyncLeadTopbarController or the client
  bridge; this only feeds the attributes they already listen to.

  Install as Script:
    ServerScriptService.SyncBhmsLeadDanceFollowerSync

  BHMS keeps a flat sync graph (SyncManager.syncPlayerAnimation redirects a
  leader's own followers straight to the new leader when that leader in turn
  syncs to someone else) — so a simple "count direct Syncing == Name matches"
  pass, redone whenever any Syncing attribute changes, is exact.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SyncBhmsGate = require(ReplicatedStorage:WaitForChild("SyncBhmsGate"))
if not SyncBhmsGate.isEnabled() then
	return
end

local syncingConns: { [number]: RBXScriptConnection } = {}
local recomputePending = false

local function recomputeLeaderAttributes()
	local followerCounts: { [string]: number } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local syncingName = character and character:GetAttribute("Syncing")
		if type(syncingName) == "string" and syncingName ~= "" then
			followerCounts[syncingName] = (followerCounts[syncingName] or 0) + 1
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if not character then
			continue
		end
		local count = followerCounts[player.Name] or 0
		if character:GetAttribute("FollowerCount") ~= count then
			character:SetAttribute("FollowerCount", count)
		end
		local isLeader = count > 0
		if character:GetAttribute("IsLeader") ~= isLeader then
			character:SetAttribute("IsLeader", isLeader)
		end
	end
end

local function scheduleRecompute()
	if recomputePending then
		return
	end
	recomputePending = true
	task.defer(function()
		recomputePending = false
		recomputeLeaderAttributes()
	end)
end

local function bindCharacter(player: Player, character: Model)
	local existing = syncingConns[player.UserId]
	if existing then
		existing:Disconnect()
	end
	syncingConns[player.UserId] = character:GetAttributeChangedSignal("Syncing"):Connect(scheduleRecompute)
	scheduleRecompute()
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		bindCharacter(player, character)
	end)
	if player.Character then
		bindCharacter(player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	local conn = syncingConns[player.UserId]
	if conn then
		conn:Disconnect()
		syncingConns[player.UserId] = nil
	end
	scheduleRecompute()
end)

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
