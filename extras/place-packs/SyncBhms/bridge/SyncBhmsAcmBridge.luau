--!strict
--[[
  Place-pack bridge: Club Kit Avatar Context Menu → BHMS Remotes2.startSync.

  Install as ModuleScript:
    ReplicatedStorage.SyncBhmsAcmBridge

  Club Kit loads this when Features.LegacySyncBhms = true.
  Does not use Club Kit SyncRemotes / dance panel.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bridge = {}

local remotesFolder: Folder? = nil
local startSyncRemote: RemoteEvent? = nil

local function ensureRemotes(): (Folder?, RemoteEvent?)
	if remotesFolder and startSyncRemote and startSyncRemote.Parent then
		return remotesFolder, startSyncRemote
	end
	local folder = ReplicatedStorage:WaitForChild("Remotes2", 30)
	if not folder or not folder:IsA("Folder") then
		warn("[SyncBhmsAcmBridge] Remotes2 missing — SyncBhms server remotes not installed")
		return nil, nil
	end
	local remote = folder:WaitForChild("startSync", 15)
	if not remote or not remote:IsA("RemoteEvent") then
		warn("[SyncBhmsAcmBridge] Remotes2.startSync missing")
		return folder, nil
	end
	remotesFolder = folder
	startSyncRemote = remote
	return folder, remote
end

--[[
  Fire BHMS sync (or unsync if already syncing that player).
  BHMS SyncManager accepts condition true/"sync" or false/"unsync".
]]
function Bridge.requestSyncByUserId(targetUserId: number): boolean
	if typeof(targetUserId) ~= "number" or targetUserId ~= targetUserId then
		return false
	end
	local localPlayer = Players.LocalPlayer
	if not localPlayer or targetUserId == localPlayer.UserId then
		return false
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target then
		return false
	end

	local _, startSync = ensureRemotes()
	if not startSync then
		return false
	end

	local character = localPlayer.Character
	local syncingName = if character then character:GetAttribute("Syncing") else nil
	local alreadyOnTarget = type(syncingName) == "string" and syncingName == target.Name

	if alreadyOnTarget then
		startSync:FireServer(target, false)
	else
		startSync:FireServer(target, true)
	end
	return true
end

return Bridge
