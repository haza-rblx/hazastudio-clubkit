--!strict
-- Client/Controllers/EventBoardController.luau
-- Event board (ADR 0015), client side: feeds the server's snapshots to EventTabUI, sends the
-- player's presses back, opens the join post once, and ticks the check-in countdown while the
-- tab is on screen. A place without the EventTab design does nothing here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local EventTabUI = require(script.Parent.Parent.UI.EventTabUI)

local log = Logger.new("Client.EventBoardController")
local cfg = Config.EventBoard
-- The join post waits for gameplay (the loading screen restores every ScreenGui's Enabled when it
-- leaves, which would switch an early popup back off), then a short beat.
local JOIN_POST_DELAY = 3
local READY_TIMEOUT = 90

local connections: { RBXScriptConnection } = {}
local ui: any = nil
local alive = false

local EventBoardController = {}

-- Top menu's Quests row: scroll the tab to its quests once it is shown.
function EventBoardController.focusQuests()
	if ui then
		ui:focusQuests()
	end
end

function EventBoardController.init(deps: { remotes: Folder })
	if alive then
		return
	end
	alive = true
	-- The menu GUI lands in PlayerGui only once the character spawns, which can be long after
	-- boot (behind the loading screen): wait for it off the boot task, without a deadline.
	task.spawn(EventBoardController._start, deps)
end

function EventBoardController._start(deps: { remotes: Folder })
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	playerGui:WaitForChild("07-MenuGUI")
	if not alive then
		return
	end
	ui = EventTabUI.tryCreate(playerGui)
	if not ui then
		log:info("EventTab not installed; event board off on this client")
		return
	end
	local remote = deps.remotes:WaitForChild(cfg.REMOTE, 30)
	if not (remote and remote:IsA("RemoteEvent")) then
		log:warn("EventBoard remote missing")
		return
	end
	local eventRemote = remote :: RemoteEvent

	ui:onClaim(function(questId: number)
		eventRemote:FireServer({ action = "claim", questId = questId })
	end)
	ui:onCheckIn(function(questId: number)
		eventRemote:FireServer({ action = "checkin", questId = questId })
	end)
	ui:onPostSeen(function(postId: number)
		eventRemote:FireServer({ action = "seen", postId = postId })
	end)

	local joinShown = false
	table.insert(connections, eventRemote.OnClientEvent:Connect(function(raw: any)
		if type(raw) ~= "table" or raw.type ~= "state" then
			return
		end
		ui:setState(raw)
		local joinPostId = raw.joinPostId
		if type(joinPostId) == "number" and not joinShown then
			joinShown = true
			task.spawn(function()
				local attribute = Config.ClientBoot.GAMEPLAY_READY_ATTRIBUTE
				local deadline = os.clock() + READY_TIMEOUT
				while player:GetAttribute(attribute) ~= true and os.clock() < deadline do
					task.wait(0.25)
				end
				task.wait(JOIN_POST_DELAY)
				if alive and ui then
					ui:openPost(joinPostId)
				end
			end)
		end
	end))

	-- Countdown on the streak button, only while someone can see it.
	task.spawn(function()
		while alive and ui do
			task.wait(1)
			if ui and ui:isShown() then
				ui:tick()
			end
		end
	end)

	-- The tab may have been built before the first state arrived; ask once more.
	eventRemote:FireServer({ action = "refresh" })
end

function EventBoardController.destroy()
	alive = false
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	table.clear(connections)
	if ui then
		ui:destroy()
		ui = nil
	end
end

return EventBoardController
