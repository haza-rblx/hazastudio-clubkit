--!strict
-- SyncLeadTopbarController (ClientController)
--
-- Topbar "Lead Dance": request remote sync to eligible leads.
-- Eligibility: Lead Dance overhead title and/or de facto lead (Character.IsLeader).
-- Data: OverheadController role cache + live Character attributes (FollowerCount).
-- Dedupe: one dropdown row per userId when both title and followers apply.
-- The dropdown is the kit's LeadDanceDropdown (not TopbarPlus sub-icons); the icon stays the trigger.
-- Following state: SyncStore leaderName (the leader's Player.Name the local player is synced to).
-- Wired from Main.client SyncDanceBootstrap → SyncController.requestSyncByUserId / onUnsync.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local NotifService = require(script.Parent.Parent.Services.NotifService)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local OverheadController = require(script.Parent.OverheadController)
local LeadDanceDropdown = require(script.Parent.LeadDanceDropdown)

local LEAD_DANCE_ROLE_KEY = "LeadDance"

type LeaderEntry = {
	userId: number,
	displayName: string,
	name: string,
	hasTitle: boolean,
	hasFollowers: boolean,
	followerCount: number,
}

local function bindIconEvent(icon: any, eventName: string, handler: () -> ()): RBXScriptConnection?
	if icon and icon[eventName] and type(icon[eventName].Connect) == "function" then
		return icon[eventName]:Connect(handler)
	end
	if icon and type(icon.bindEvent) == "function" then
		icon:bindEvent(eventName, handler)
		return nil
	end
	return nil
end

local function hasLeadDanceTitle(userId: number): boolean
	local role = OverheadController.getPlayerRole(userId)
	if type(role) ~= "string" then
		return false
	end
	return OverheadDomain.normalizeRoleKey(role) == LEAD_DANCE_ROLE_KEY
end

local function readFollowerCount(character: Model?): number
	if not character then
		return 0
	end
	local raw = character:GetAttribute("FollowerCount")
	if type(raw) == "number" then
		return math.max(0, math.floor(raw))
	end
	return 0
end

local function hasDeFactoLead(character: Model?): boolean
	return character ~= nil and character:GetAttribute("IsLeader") == true
end

local function createSyncLeadTopbarController(deps: {
	icon: any,
	iconFactory: () -> any,
	onRequestSyncToLeader: ((userId: number) -> ())?,
	onRequestUnsync: (() -> ())?,
	syncStore: any?,
})
	local log = Logger.new("Client.SyncLeadTopbarController")
	local mainIcon = deps.icon
	local onRequestSyncToLeader = deps.onRequestSyncToLeader
	local onRequestUnsync = deps.onRequestUnsync
	local syncStore = deps.syncStore

	assert(
		type(onRequestSyncToLeader) == "function",
		"SyncLeadTopbarController: onRequestSyncToLeader is required (Main.client must pass it at create time)"
	)

	local leaderState: { [number]: LeaderEntry } = {}
	local characterConns: { [number]: { RBXScriptConnection } } = {}
	local playerCharacterConns: { [number]: RBXScriptConnection } = {}

	local mainSelectedConn: RBXScriptConnection? = nil
	local mainDeselectedConn: RBXScriptConnection? = nil
	local roleChangedUnsubscribe: (() -> ())? = nil
	local overheadCacheUnsubscribe: (() -> ())? = nil
	local storeUnsubscribe: (() -> ())? = nil

	local rebuildPending = false
	-- True while the controller itself deselects the icon (after the dropdown closes), so the
	-- icon's deselected handler does not re-enter the dropdown.
	local syncingIcon = false
	local dropdown: any = nil

	local requestSyncToLeader: (number) -> ()
	local requestUnsync: () -> ()
	local scheduleRebuild: () -> ()
	local rebuildMenu: () -> ()

	local function disconnectCharacterSubs(userId: number)
		local conns = characterConns[userId]
		if conns then
			for _, conn in ipairs(conns) do
				conn:Disconnect()
			end
			characterConns[userId] = nil
		end
	end

	-- Merge title + follower signals into one entry per remote player (never duplicate rows).
	local function computeLeaderEntry(player: Player): LeaderEntry?
		if player == Players.LocalPlayer then
			return nil
		end

		local userId = player.UserId
		local character = player.Character
		local hasTitle = hasLeadDanceTitle(userId)
		local hasFollowers = hasDeFactoLead(character)

		if not hasTitle and not hasFollowers then
			return nil
		end

		return {
			userId = userId,
			displayName = player.DisplayName,
			name = player.Name,
			hasTitle = hasTitle,
			hasFollowers = hasFollowers,
			followerCount = if hasFollowers then readFollowerCount(character) else 0,
		}
	end

	local function applyEntryForPlayer(player: Player)
		local entry = computeLeaderEntry(player)
		if entry then
			leaderState[player.UserId] = entry
		else
			leaderState[player.UserId] = nil
		end
	end

	local function updateMainIconLabel(count: number)
		if not mainIcon then
			return
		end
		mainIcon:setLabel(string.format("Lead Dance (%d)", count))
		if type(mainIcon.setEnabled) == "function" then
			mainIcon:setEnabled(true)
		end
	end

	-- Local player's current sync target (leader Player.Name), or nil when not synced.
	local function currentLeaderName(): string?
		if not syncStore then
			return nil
		end
		local name = syncStore:get().leaderName
		if type(name) == "string" then
			return name
		end
		return nil
	end

	rebuildMenu = function()
		local leaderName = currentLeaderName()
		local entries = {}
		for _, info in pairs(leaderState) do
			table.insert(entries, {
				userId = info.userId,
				displayName = info.displayName,
				name = info.name,
				followers = info.followerCount,
				following = leaderName ~= nil and info.name == leaderName,
			})
		end

		if dropdown then
			dropdown:setEntries(entries)
		end
		updateMainIconLabel(#entries)
	end

	scheduleRebuild = function()
		if rebuildPending then
			return
		end
		rebuildPending = true
		task.defer(function()
			rebuildPending = false
			rebuildMenu()
		end)
	end

	requestSyncToLeader = function(userId: number)
		-- onRequestSyncToLeader is required (assert in constructor). The type
		-- check below is belt-and-suspenders in case the upvalue ever gets
		-- shadowed or replaced; if it isn't callable, drop the click quietly
		-- (mirrors ruang penat) instead of queueing/notifying.
		if type(onRequestSyncToLeader) == "function" then
			local target = Players:GetPlayerByUserId(userId)
			local label = if target then target.DisplayName else "lead"
			NotifService.show({
				message = "Requesting sync to " .. label .. "…",
				notifType = "INFO",
				domain = "sync",
				title = "Lead Dance",
				dedupeKey = "sync-lead-request-" .. tostring(userId),
				duration = 2,
			})
			-- pcall so a bug in the caller's handler doesn't kill the
			-- controller and leave the topbar in a stuck state.
			local ok, err = pcall(onRequestSyncToLeader, userId)
			if not ok then
				log:warn("onRequestSyncToLeader handler threw", { userId = userId, err = tostring(err) })
			end
		end
	end

	requestUnsync = function()
		if type(onRequestUnsync) ~= "function" then
			return
		end
		local ok, err = pcall(onRequestUnsync)
		if not ok then
			log:warn("onRequestUnsync handler threw", { err = tostring(err) })
			return
		end
		NotifService.show({
			message = "Unsynced",
			notifType = "INFO",
			domain = "sync",
			title = "Lead Dance",
			duration = 2,
		})
	end

	-- Icon deselect is driven by the dropdown closing; the flag stops the deselected handler
	-- from closing the dropdown again.
	local function setIconDeselected()
		if mainIcon and type(mainIcon.deselect) == "function" then
			syncingIcon = true
			pcall(function()
				mainIcon:deselect()
			end)
			syncingIcon = false
		end
	end

	dropdown = LeadDanceDropdown.new({
		getAnchor = function(): GuiObject?
			-- TopbarPlus exposes the icon's Widget frame as icon.widget (see Icon.Utility / Overflow).
			local widget = if mainIcon then mainIcon.widget else nil
			if typeof(widget) == "Instance" and widget:IsA("GuiObject") then
				return widget
			end
			return nil
		end,
		onSync = function(userId: number)
			requestSyncToLeader(userId)
		end,
		onUnsync = function()
			requestUnsync()
		end,
		onClosed = function()
			setIconDeselected()
		end,
	})

	local function bindCharacter(player: Player, character: Model)
		disconnectCharacterSubs(player.UserId)

		local conns: { RBXScriptConnection } = {}
		table.insert(
			conns,
			character:GetAttributeChangedSignal("IsLeader"):Connect(function()
				applyEntryForPlayer(player)
				scheduleRebuild()
			end)
		)
		table.insert(
			conns,
			character:GetAttributeChangedSignal("FollowerCount"):Connect(function()
				applyEntryForPlayer(player)
				scheduleRebuild()
			end)
		)
		characterConns[player.UserId] = conns
		applyEntryForPlayer(player)
		scheduleRebuild()
	end

	local function bindPlayerCharacter(player: Player)
		local existing = playerCharacterConns[player.UserId]
		if existing then
			existing:Disconnect()
		end

		if player.Character then
			bindCharacter(player, player.Character)
		end

		playerCharacterConns[player.UserId] = player.CharacterAdded:Connect(function(character)
			bindCharacter(player, character)
		end)
	end

	local function unbindPlayer(player: Player)
		disconnectCharacterSubs(player.UserId)
		local charConn = playerCharacterConns[player.UserId]
		if charConn then
			charConn:Disconnect()
			playerCharacterConns[player.UserId] = nil
		end
		leaderState[player.UserId] = nil
	end

	local function refreshAllLeaderEntries()
		for _, player in ipairs(Players:GetPlayers()) do
			applyEntryForPlayer(player)
		end
		scheduleRebuild()
	end

	local function onPlayerAdded(player: Player)
		bindPlayerCharacter(player)
	end

	local function onPlayerRemoving(player: Player)
		unbindPlayer(player)
		scheduleRebuild()
	end

	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	if type(OverheadController.subscribeRoleChanged) == "function" then
		roleChangedUnsubscribe = OverheadController.subscribeRoleChanged(function(userId: number, _role: string?)
			local player = Players:GetPlayerByUserId(userId)
			if player then
				applyEntryForPlayer(player)
				scheduleRebuild()
			end
		end)
	end

	if type(OverheadController.subscribeOverheadCacheUpdated) == "function" then
		overheadCacheUnsubscribe = OverheadController.subscribeOverheadCacheUpdated(function(userId: number?)
			if userId then
				local player = Players:GetPlayerByUserId(userId)
				if player then
					applyEntryForPlayer(player)
					scheduleRebuild()
					return
				end
			end
			refreshAllLeaderEntries()
		end)
	end

	-- Following changes (sync started / ended) rebuild the rows so the Unsync row updates.
	if syncStore and type(syncStore.subscribe) == "function" then
		storeUnsubscribe = syncStore:subscribe("leaderName", function()
			scheduleRebuild()
		end)
	end

	-- Icon selected opens the dropdown with fresh rows; icon deselected closes it.
	mainSelectedConn = bindIconEvent(mainIcon, "selected", function()
		refreshAllLeaderEntries()
		rebuildMenu()
		if dropdown then
			dropdown:open()
		end
	end)
	mainDeselectedConn = bindIconEvent(mainIcon, "deselected", function()
		if syncingIcon then
			return
		end
		if dropdown then
			dropdown:close()
		end
	end)

	task.defer(refreshAllLeaderEntries)

	return {
		destroy = function()
			if mainSelectedConn then
				mainSelectedConn:Disconnect()
				mainSelectedConn = nil
			end
			if mainDeselectedConn then
				mainDeselectedConn:Disconnect()
				mainDeselectedConn = nil
			end
			if storeUnsubscribe then
				storeUnsubscribe()
				storeUnsubscribe = nil
			end
			if roleChangedUnsubscribe then
				roleChangedUnsubscribe()
				roleChangedUnsubscribe = nil
			end
			if overheadCacheUnsubscribe then
				overheadCacheUnsubscribe()
				overheadCacheUnsubscribe = nil
			end
			for userId in pairs(playerCharacterConns) do
				local conn = playerCharacterConns[userId]
				if conn then
					conn:Disconnect()
				end
				playerCharacterConns[userId] = nil
			end
			for userId in pairs(characterConns) do
				disconnectCharacterSubs(userId)
			end
			if dropdown then
				dropdown:destroy()
				dropdown = nil
			end
			table.clear(leaderState)
		end,
	}
end

return createSyncLeadTopbarController
