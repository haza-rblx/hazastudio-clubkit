--!strict
-- SyncLeadTopbarController (ClientController)
--
-- Topbar "Lead Dance": request remote sync to eligible leads.
-- Eligibility: Lead Dance overhead title and/or de facto lead (Character.IsLeader).
-- Data: OverheadController role cache + live Character attributes (FollowerCount).
-- Dedupe: one dropdown row per userId when both title and followers apply.
-- Wired from Main.client SyncDanceBootstrap → SyncController.requestSyncByUserId.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local NotifService = require(script.Parent.Parent.Services.NotifService)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local OverheadController = require(script.Parent.OverheadController)

local LEAD_DANCE_ROLE_KEY = "LeadDance"

type LeaderEntry = {
	userId: number,
	displayName: string,
	name: string,
	hasTitle: boolean,
	hasFollowers: boolean,
	followerCount: number,
}

local function bindIconSelected(icon: any, handler: () -> ()): RBXScriptConnection?
	if icon and icon.selected and type(icon.selected.Connect) == "function" then
		return icon.selected:Connect(handler)
	end
	if icon and type(icon.bindEvent) == "function" then
		icon:bindEvent("selected", handler)
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

local function formatLeaderLabel(info: LeaderEntry): string
	local base = info.displayName .. " (@" .. info.name .. ")"
	if info.followerCount > 0 then
		return base .. " · " .. tostring(info.followerCount)
	end
	return base
end

local function buildMenuSignature(entries: { LeaderEntry }): string
	local parts = table.create(#entries)
	for _, info in ipairs(entries) do
		table.insert(parts, string.format("%d:%d:%s", info.userId, info.followerCount, info.displayName))
	end
	table.sort(parts)
	return table.concat(parts, "|")
end

local function createSyncLeadTopbarController(deps: {
	icon: any,
	iconFactory: () -> any,
	onRequestSyncToLeader: ((userId: number) -> ())?,
})
	local log = Logger.new("Client.SyncLeadTopbarController")
	local mainIcon = deps.icon
	local iconFactory = deps.iconFactory
	local onRequestSyncToLeader = deps.onRequestSyncToLeader

	assert(
		type(onRequestSyncToLeader) == "function",
		"SyncLeadTopbarController: onRequestSyncToLeader is required (Main.client must pass it at create time)"
	)

	local leaderIcons: { [number]: any } = {}
	local leaderSubConnections: { [number]: { RBXScriptConnection } } = {}
	local leaderState: { [number]: LeaderEntry } = {}
	local characterConns: { [number]: { RBXScriptConnection } } = {}
	local playerCharacterConns: { [number]: RBXScriptConnection } = {}

	local mainSelectedConn: RBXScriptConnection? = nil
	local roleChangedUnsubscribe: (() -> ())? = nil
	local overheadCacheUnsubscribe: (() -> ())? = nil

	local rebuildPending = false
	local lastMenuSignature = ""

	local requestSyncToLeader: (number) -> ()
	local scheduleRebuild: () -> ()
	local rebuildMenu: () -> ()

	local function disconnectLeaderSubs()
		for userId, conns in pairs(leaderSubConnections) do
			for _, conn in ipairs(conns) do
				conn:Disconnect()
			end
			leaderSubConnections[userId] = nil
		end
	end

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

	rebuildMenu = function()
		disconnectLeaderSubs()

		local entries = {} :: { LeaderEntry }
		for _, info in pairs(leaderState) do
			table.insert(entries, info)
		end
		table.sort(entries, function(a, b)
			local nameCmp = a.displayName:lower() < b.displayName:lower()
			if a.displayName:lower() ~= b.displayName:lower() then
				return nameCmp
			end
			return a.followerCount > b.followerCount
		end)

		local signature = buildMenuSignature(entries)
		if signature == lastMenuSignature then
			updateMainIconLabel(#entries)
			return
		end
		lastMenuSignature = signature

		for userId, icon in pairs(leaderIcons) do
			pcall(function()
				icon:destroy()
			end)
			leaderIcons[userId] = nil
		end

		local items = {}
		for _, info in ipairs(entries) do
			local sub = iconFactory()
			sub:setLabel(formatLeaderLabel(info))
			if type(sub.modifyTheme) == "function" then
				sub:modifyTheme({
					{ "IconImage", "Visible", false },
					{ "PaddingLeft", "Size", UDim2.fromScale(0, 1) },
				})
			end
			if type(sub.oneClick) == "function" then
				sub:oneClick(true)
			end
			leaderIcons[info.userId] = sub

			local conns: { RBXScriptConnection } = {}
			local capturedUserId = info.userId
			local conn = bindIconSelected(sub, function()
				requestSyncToLeader(capturedUserId)
			end)
			if conn then
				table.insert(conns, conn)
			end
			leaderSubConnections[info.userId] = conns

			table.insert(items, sub)
		end

		if mainIcon then
			updateMainIconLabel(#entries)
			if type(mainIcon.setDropdown) == "function" then
				mainIcon:setDropdown(items)
			elseif type(mainIcon.setMenu) == "function" then
				mainIcon:setMenu(items)
			end
		end
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
		if mainIcon and type(mainIcon.deselect) == "function" then
			pcall(function()
				mainIcon:deselect()
			end)
		end
	end

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
		lastMenuSignature = ""
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

	mainSelectedConn = bindIconSelected(mainIcon, function()
		refreshAllLeaderEntries()
	end)

	task.defer(refreshAllLeaderEntries)

	return {
		destroy = function()
			disconnectLeaderSubs()
			if mainSelectedConn then
				mainSelectedConn:Disconnect()
				mainSelectedConn = nil
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
			for userId, icon in pairs(leaderIcons) do
				pcall(function()
					icon:destroy()
				end)
				leaderIcons[userId] = nil
			end
			table.clear(leaderState)
			lastMenuSignature = ""
		end,
	}
end

return createSyncLeadTopbarController
