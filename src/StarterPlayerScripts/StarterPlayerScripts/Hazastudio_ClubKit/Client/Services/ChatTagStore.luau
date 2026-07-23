--!strict
-- Client ChatTagStore — thin global roster for chat tags (not proximity-gated).
-- Server publishes via ChatTagSync; ChatTagsController reads this first.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)

type ChatTagEntry = Types.ChatTagEntry

local ChatTagStore = {}

local byUserId: { [number]: ChatTagEntry } = {}
local listeners: { (userId: number?) -> () } = {}
local wired = false
local playerRemovingConn: RBXScriptConnection? = nil

local function notify(userId: number?)
	for _, fn in ipairs(listeners) do
		task.spawn(fn, userId)
	end
end

local function isEntry(value: any): boolean
	return type(value) == "table"
		and type(value.userId) == "number"
		and type(value.displayName) == "string"
		and type(value.primaryTag) == "string"
		and type(value.role) == "string"
		and type(value.effectiveMembership) == "string"
		and type(value.rev) == "number"
end

local function upsert(entry: ChatTagEntry, force: boolean?)
	local existing = byUserId[entry.userId]
	-- Drop stale only when not a catch-up batch. After leave/rejoin, server rev
	-- restarts at 1; a lost remove would otherwise block forever.
	if not force and existing and existing.rev > entry.rev then
		return
	end
	byUserId[entry.userId] = entry
	notify(entry.userId)
end

local function remove(userId: number)
	if byUserId[userId] == nil then
		return
	end
	byUserId[userId] = nil
	notify(userId)
end

local function applyMessage(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if type(payload.remove) == "number" then
		remove(payload.remove)
		return
	end
	if type(payload.batch) == "table" then
		-- Full roster snapshot from server is authoritative for listed users.
		for _, item in ipairs(payload.batch) do
			if isEntry(item) then
				upsert(item :: ChatTagEntry, true)
			end
		end
		notify(nil)
		return
	end
	if isEntry(payload) then
		upsert(payload :: ChatTagEntry)
		return
	end
	if isEntry(payload.entry) then
		upsert(payload.entry :: ChatTagEntry)
	end
end

function ChatTagStore.get(userId: number): ChatTagEntry?
	return byUserId[userId]
end

function ChatTagStore.subscribe(fn: (userId: number?) -> ()): () -> ()
	table.insert(listeners, fn)
	return function()
		for i, existing in ipairs(listeners) do
			if existing == fn then
				table.remove(listeners, i)
				return
			end
		end
	end
end

local function requestCatchup(remotes: Instance)
	-- Reuse OverheadRosterRequest (server also sends ChatTag batch there).
	-- Covers the race where join batch fired before this client wired OnClientEvent.
	local remoteName = "OverheadRosterRequest"
	local remote = remotes:FindFirstChild(remoteName)
	if not remote or not remote:IsA("RemoteEvent") then
		remote = remotes:WaitForChild(remoteName, 10) :: any
	end
	if remote and remote:IsA("RemoteEvent") then
		pcall(function()
			(remote :: RemoteEvent):FireServer()
		end)
	end
end

function ChatTagStore.init()
	if wired then
		return
	end
	wired = true

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
	end
	if not remotes then
		return
	end

	local remoteName = tostring(Config.Overhead.REMOTE_CHAT_TAG_SYNC or "ChatTagSync")
	local remote = remotes:FindFirstChild(remoteName) :: RemoteEvent?
	if not remote then
		remote = remotes:WaitForChild(remoteName, Config.Overhead.REMOTE_READY_TIMEOUT or 45) :: any
	end
	if not remote or not remote:IsA("RemoteEvent") then
		return
	end

	remote.OnClientEvent:Connect(function(payload: any)
		applyMessage(payload)
	end)

	-- Optimistic local clear if server remove is delayed/lost.
	if not playerRemovingConn then
		playerRemovingConn = Players.PlayerRemoving:Connect(function(player)
			remove(player.UserId)
		end)
	end

	task.defer(function()
		requestCatchup(remotes)
	end)
end

function ChatTagStore.clear()
	table.clear(byUserId)
	notify(nil)
end

return ChatTagStore
