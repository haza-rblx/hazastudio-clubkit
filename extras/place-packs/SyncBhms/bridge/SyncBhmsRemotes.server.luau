--!strict
--[[
  Place-only: provision Remotes2 + StoredAnimations expected by SyncBhms.
  Put as Script under ServerScriptService (run before SyncBhms SyncServer.Main1).

  Does NOT touch Club Kit SyncRemotes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SyncBhmsGate = require(ReplicatedStorage:WaitForChild("SyncBhmsGate"))
if not SyncBhmsGate.isEnabled() then
	return
end

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensureRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function ensureRemoteFunction(parent: Instance, name: string): RemoteFunction
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local remotes = ensureFolder(ReplicatedStorage, "Remotes2")
-- Main1 uses OnServerInvoke for animationStart
ensureRemoteFunction(remotes, "animationStart")
ensureRemoteEvent(remotes, "startSync")
ensureRemoteEvent(remotes, "changeSpeed")
ensureRemoteEvent(remotes, "updateFavoritedAnimationsEvent")
ensureRemoteEvent(remotes, "syncWarning")
ensureRemoteEvent(remotes, "ToggleAutoDance")
-- Created by Main1 if missing; ensure early for BeatDanceClient waiters
ensureRemoteEvent(remotes, "BeatDanceMode")

ensureFolder(ReplicatedStorage, "StoredAnimations")
