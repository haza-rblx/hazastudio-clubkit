--!strict
-- Client-side holder of the newest event board snapshot (ADR 0015/0019).
--
-- The cinematic loading screen listens to Remotes.EventBoard from ReplicatedFirst, long before
-- the menu's EventBoardController exists. A RemoteEvent hands its queued events to the FIRST
-- connection only, so the loading screen would swallow the join-time push the controller relies
-- on. The relay keeps that snapshot; EventBoardController replays it when it starts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Parent.Constants.Config)

local EventBoardRelay = {}

local REMOTE_WAIT = 120

local latest: { [string]: any }? = nil
local listeners: { (state: { [string]: any }) -> () } = {}
local started = false

local function isState(raw: any): boolean
	return type(raw) == "table" and raw.type == "state" and type(raw.posts) == "table"
end

--- Start listening (idempotent, non-blocking).
function EventBoardRelay.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("Remotes", REMOTE_WAIT)
		local remote = folder and folder:WaitForChild(Config.EventBoard.REMOTE, REMOTE_WAIT)
		if not (remote and remote:IsA("RemoteEvent")) then
			return
		end
		remote.OnClientEvent:Connect(function(raw: any)
			if not isState(raw) then
				return
			end
			latest = raw
			for _, listener in ipairs(listeners) do
				task.spawn(listener, raw)
			end
		end)
	end)
end

function EventBoardRelay.latest(): { [string]: any }?
	return latest
end

--- Called with every snapshot from now on (and the current one, if any). Returns a disconnect.
function EventBoardRelay.subscribe(listener: (state: { [string]: any }) -> ()): () -> ()
	table.insert(listeners, listener)
	if latest then
		task.spawn(listener, latest)
	end
	return function()
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end
end

return EventBoardRelay
