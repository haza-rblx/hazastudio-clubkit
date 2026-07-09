--!strict
-- Client/Controllers/StreakController.lua
-- Wiring: listen StreakNotif -> pasang ke StreakUI.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config         = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger         = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local StreakUIModule  = require(script.Parent.Parent.UI.StreakUI)
local log = Logger.new("Client.StreakController")

local _connections: { RBXScriptConnection } = {}

local function track(conn: RBXScriptConnection): RBXScriptConnection
	table.insert(_connections, conn)
	return conn
end

local function destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)
end

local function init(deps: { remotes: Folder })
	local remotes = deps.remotes
	local player  = Players.LocalPlayer
	local gui = player.PlayerGui:WaitForChild("05-StreakGUI", 30) :: ScreenGui?
	if not gui then
		log:warn("05-StreakGUI tidak ditemukan, StreakController tidak dijalankan")
		return
	end
	local ui  = StreakUIModule.new(gui :: ScreenGui)
	local notifRemote = remotes:WaitForChild(Config.Streak.REMOTE_NOTIF, 30) :: RemoteEvent?
	if not notifRemote then
		log:warn("Remote StreakNotif tidak ditemukan, StreakController tidak dijalankan")
		return
	end
	track(notifRemote.OnClientEvent:Connect(function(raw: any)
		if type(raw) ~= "table"            then return end
		if type(raw.streakDays) ~= "number" then return end
		ui:play({
			streakDays   = raw.streakDays,
			didReset     = raw.didReset    == true,
			didIncrement = raw.didIncrement == true,
			isMilestone  = raw.isMilestone == true,
		})
	end))
end
return { init = init, destroy = destroy }
