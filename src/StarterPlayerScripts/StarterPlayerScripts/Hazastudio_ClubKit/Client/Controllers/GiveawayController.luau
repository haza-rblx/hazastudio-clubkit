--!strict
-- Client/Controllers/GiveawayController.luau
-- Giveaway (Auto Gacha) client. Every player gets the hourly card and the winner toast (GiveawayHud);
-- admins open the settings sheet from Admin Spotlight > Giveaway (GiveawaySheet). The server owns the
-- state: snapshots arrive on REMOTE_STATE, spins on REMOTE_SPIN, history on REMOTE_HISTORY and
-- pay-prompt results on REMOTE_NOTICE. Remotes are created by Server/Init/EarlyRemotes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Client = script.Parent.Parent
local GiveawayHud = require(Client.UI.Giveaway.GiveawayHud)
local GiveawaySheet = require(Client.UI.Giveaway.GiveawaySheet)

local LOG = "[Giveaway]"
local G = Config.Giveaway

local GiveawayController = {}
local active: { open: () -> (), destroy: () -> () }? = nil

function GiveawayController.init(deps: { remotes: Folder }): { destroy: () -> (), open: () -> () }
	if active then
		return active
	end
	local remotes = deps.remotes
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	local stateEvent = remotes:WaitForChild(G.REMOTE_STATE) :: RemoteEvent
	local spinEvent = remotes:WaitForChild(G.REMOTE_SPIN) :: RemoteEvent
	local adminEvent = remotes:WaitForChild(G.REMOTE_ADMIN) :: RemoteEvent
	local historyEvent = remotes:WaitForChild(G.REMOTE_HISTORY) :: RemoteEvent
	local noticeEvent = remotes:WaitForChild(G.REMOTE_NOTICE) :: RemoteEvent

	-- Server snapshot, updated in place by the state remote. Defaults mirror Config.Giveaway.
	local state: GiveawayHud.HudState = {
		phase = "counting",
		nextAt = 0,
		count = 0,
		min = G.DEFAULT_MIN_PLAYERS,
		anchor = G.DEFAULT_ANCHOR,
		prize = tostring(G.DEFAULT_PRIZE_ROBUX),
		enabled = G.DEFAULT_ENABLED,
		interval = G.DEFAULT_INTERVAL_MINUTES * 60,
		spinDuration = G.DEFAULT_SPIN_DURATION,
		winFxVariant = G.DEFAULT_WIN_FX_VARIANT,
	}

	local hud = GiveawayHud.new(playerGui, state)
	local sheet = GiveawaySheet.new(playerGui, state, {
		adminEvent = adminEvent,
		isBusy = function(): boolean
			return hud.isSpinning() or state.phase == "spinning"
		end,
	})

	local connections: { RBXScriptConnection } = {}
	table.insert(connections, stateEvent.OnClientEvent:Connect(function(snap: any)
		if type(snap) ~= "table" then
			return
		end
		state.phase = snap.phase
		state.nextAt = snap.nextAt
		state.count = snap.count
		state.min = snap.min
		state.anchor = snap.anchor
		state.prize = snap.prize
		state.enabled = snap.enabled ~= false
		state.interval = snap.interval or state.interval
		state.spinDuration = snap.spinDuration or state.spinDuration
		state.winFxVariant = snap.winFxVariant or state.winFxVariant
		hud.refresh()
		sheet.refresh()
	end))

	table.insert(connections, spinEvent.OnClientEvent:Connect(function(payload: any)
		local ok, err = pcall(hud.beginSpin, payload)
		if not ok then
			warn(LOG .. " beginSpin failed: " .. tostring(err))
		end
	end))

	table.insert(connections, historyEvent.OnClientEvent:Connect(function(list: any)
		sheet.setHistory(list)
	end))

	table.insert(connections, noticeEvent.OnClientEvent:Connect(function(n: any)
		sheet.notice(n)
	end))

	-- Render loop: the countdown and reel are local, driven every frame.
	table.insert(connections, RunService.RenderStepped:Connect(function()
		hud.update(workspace:GetServerTimeNow())
	end))

	local api = {
		open = function()
			sheet.open()
		end,
		destroy = function()
			for _, conn in ipairs(connections) do
				conn:Disconnect()
			end
			table.clear(connections)
			hud.destroy()
			sheet.destroy()
			active = nil
		end,
	}
	active = api
	adminEvent:FireServer("hello")
	return api
end

-- Admin Spotlight entry point (Client/Controllers/AdminHubController "giveaway" action).
function GiveawayController.open()
	if active then
		active.open()
	else
		warn(LOG .. " open requested before init")
	end
end

return GiveawayController
