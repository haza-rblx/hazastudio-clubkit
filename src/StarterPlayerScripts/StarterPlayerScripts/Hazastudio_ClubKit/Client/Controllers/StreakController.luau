--!strict
-- Client/Controllers/StreakController.lua
-- Wiring: listen StreakNotif -> pasang ke StreakUI.
-- Daily Quest addon (1000-02-DQ-ADDON): the panel's check-in button, its topbar icon, the
-- auto-open after join, and the flame handoff from StreakUI to today's circle.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config         = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger         = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local StreakUIModule  = require(script.Parent.Parent.UI.StreakUI)
local DailyQuestUI   = require(script.Parent.Parent.UI.DailyQuestUI)
local log = Logger.new("Client.StreakController")

local _connections: { RBXScriptConnection } = {}
local _questUI: any = nil
local _questIcon: any = nil

local function track(conn: RBXScriptConnection): RBXScriptConnection
	table.insert(_connections, conn)
	return conn
end

local function destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)
	if _questUI then
		_questUI:destroy()
		_questUI = nil
	end
	if _questIcon and type(_questIcon.destroy) == "function" then
		_questIcon:destroy()
	end
	_questIcon = nil
end

-- Returns the panel when the addon is on, installed and its remote exists; nil otherwise, and the
-- streak overlay then behaves exactly as it did before the addon.
local function initDailyQuest(player: Player, remotes: Folder, createTopbarIcon: (() -> any)?): any?
	if Config.FeatureFlags.DailyQuestEnabled ~= true then
		return nil
	end
	local playerGui = player:WaitForChild("PlayerGui")
	if not playerGui:WaitForChild(Config.DailyQuest.GUI_NAME, 15) then
		return nil
	end
	local ui = DailyQuestUI.tryCreate(playerGui)
	if not ui then
		log:warn("1000-02-DQ-ADDON is missing required children, Daily Quest not started")
		return nil
	end
	local remote = remotes:WaitForChild(Config.DailyQuest.REMOTE, 30) :: RemoteEvent?
	if not remote then
		log:warn("Remote DailyQuest not found, Daily Quest not started")
		return nil
	end
	_questUI = ui

	local function sync()
		remote:FireServer({ action = "sync" })
	end
	ui:onCheckIn(function()
		remote:FireServer({ action = "checkin" })
	end)
	ui:onDayTurned(sync)

	if createTopbarIcon then
		local ok, icon = pcall(createTopbarIcon)
		if ok and icon then
			_questIcon = icon
			icon.selected:Connect(function()
				ui:open()
			end)
			icon.deselected:Connect(function()
				ui:close()
			end)
			ui:onClosed(function()
				if icon.isSelected then
					icon:deselect()
				end
			end)
		elseif not ok then
			log:warn("Daily Quest topbar icon failed", { err = icon })
		end
	end

	local function open()
		if _questIcon and not _questIcon.isSelected then
			_questIcon:select() -- selected handler opens the panel
		else
			ui:open()
		end
	end

	-- Auto-open once per session, after the loading screen, if today's check-in is still open.
	local autoOpenDecided = false
	local function considerAutoOpen(state: any)
		if autoOpenDecided then
			return
		end
		autoOpenDecided = true
		if state.enabled ~= true or state.checkedInToday == true then
			return
		end
		task.spawn(function()
			local attribute = Config.ClientBoot.GAMEPLAY_READY_ATTRIBUTE
			local deadline = os.clock() + Config.DailyQuest.READY_TIMEOUT
			while player:GetAttribute(attribute) ~= true and os.clock() < deadline do
				task.wait(0.25)
			end
			task.wait(Config.DailyQuest.AUTO_OPEN_DELAY)
			if _questUI == ui and not ui:isOpen() then
				open()
			end
		end)
	end

	track(remote.OnClientEvent:Connect(function(raw: any)
		if type(raw) ~= "table" or raw.kind ~= "state" or type(raw.state) ~= "table" then
			return
		end
		ui:setState(raw.state)
		considerAutoOpen(raw.state)
	end))
	sync()
	return ui
end

local function init(deps: { remotes: Folder, createTopbarIcon: (() -> any)? })
	local remotes = deps.remotes
	local player  = Players.LocalPlayer
	local gui = player.PlayerGui:WaitForChild("05-StreakGUI", 30) :: ScreenGui?
	if not gui then
		log:warn("05-StreakGUI not found, StreakController not started")
		return
	end
	local ui  = StreakUIModule.new(gui :: ScreenGui)
	local notifRemote = remotes:WaitForChild(Config.Streak.REMOTE_NOTIF, 30) :: RemoteEvent?
	if not notifRemote then
		log:warn("Remote StreakNotif not found, StreakController not started")
		return
	end
	-- Connected before the Daily Quest setup yields, so a join-time notif is never missed.
	track(notifRemote.OnClientEvent:Connect(function(raw: any)
		if type(raw) ~= "table" then return end
		if type(raw.streakDays) ~= "number" then return end
		local quest = if type(raw.quest) == "table" then raw.quest else nil
		local questUI = _questUI
		local handoff: ((ImageLabel) -> ())? = nil
		if quest and questUI and type(quest.state) == "table" then
			-- Today's circle stays unfilled until the flame lands on it.
			questUI:setState(quest.state, quest.counted == true)
			if quest.counted == true then
				handoff = function(image: ImageLabel)
					questUI:flyFrom(image)
				end
			end
		end
		ui:play({
			streakDays   = raw.streakDays,
			didReset     = raw.didReset    == true,
			didIncrement = raw.didIncrement == true,
			isMilestone  = raw.isMilestone == true,
		}, handoff)
	end))
	task.spawn(function()
		local ok, err = pcall(initDailyQuest, player, remotes, deps.createTopbarIcon)
		if not ok then
			log:warn("Daily Quest init failed", { err = err })
		end
	end)
end
return { init = init, destroy = destroy }
