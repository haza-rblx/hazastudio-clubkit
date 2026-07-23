--!strict
-- ServerScriptService/Server/Init/EarlyRemotes.luau
--
-- Create remotes before heavy service wiring so clients can bind during slow boot.

local function ensureRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing:IsA("RemoteEvent") then
			return existing
		end
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing:IsA("Folder") then
			return existing
		end
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function provisionRemotesFolder(remotes: Folder, config: any)
	ensureRemoteEvent(remotes, "AboutRosterSync")
	ensureRemoteEvent(remotes, "ChatTagSync")
	ensureRemoteEvent(remotes, "OverheadRosterRequest")
	ensureRemoteEvent(remotes, "OverheadRequestRefresh")
	ensureRemoteEvent(remotes, "OverheadUpdate")

	ensureRemoteEvent(remotes, config.Streak.REMOTE_NOTIF)

	for _, name in ipairs({
		"CoupleSendRequest",
		"CoupleRespond",
		"CoupleBreakup",
		"CoupleOpenPanel",
		"CoupleNotifyRequest",
		"CoupleNotifyResult",
		"CoupleAnnounce",
		"CouplePanelData",
	}) do
		ensureRemoteEvent(remotes, name)
	end

	ensureRemoteEvent(remotes, config.Admin.REMOTE_SET_TITLE)
	ensureRemoteEvent(remotes, config.Admin.REMOTE_SEND_GIFTCARD)
	ensureRemoteEvent(remotes, config.Admin.REMOTE_GIFTCARD_RESULT)
	ensureRemoteEvent(remotes, config.Admin.REMOTE_RESET_TITLE)

	ensureRemoteEvent(remotes, config.CinematicDock.REMOTE_REQUEST)
	ensureRemoteEvent(remotes, config.CinematicDock.REMOTE_BROADCAST)
	ensureRemoteEvent(remotes, config.CinematicDock.REMOTE_TARGETS)

	ensureRemoteEvent(remotes, config.CommandLibrary.REMOTE_EXECUTE)
	ensureRemoteEvent(remotes, config.CommandLibrary.REMOTE_EXECUTE_RESULT)
end

local function provisionSyncRemotes(replicatedStorage: ReplicatedStorage, config: any)
	if not config.FeatureFlags.SyncDanceEnabled then
		return
	end

	local syncConfig = config.Sync
	local syncFolder = ensureFolder(replicatedStorage, syncConfig.REMOTE_FOLDER)
	ensureRemoteEvent(syncFolder, syncConfig.REMOTE_ANIMATION_START)
	ensureRemoteEvent(syncFolder, syncConfig.REMOTE_START_SYNC)
	ensureRemoteEvent(syncFolder, syncConfig.REMOTE_CHANGE_SPEED)
	ensureRemoteEvent(syncFolder, syncConfig.REMOTE_UPDATE_FAVORITES)
	ensureRemoteEvent(syncFolder, syncConfig.REMOTE_SYNC_FAVORITES)
	ensureRemoteEvent(syncFolder, syncConfig.REMOTE_NOTIFICATION)
end

local function provisionCarryRemotes(replicatedStorage: ReplicatedStorage, config: any)
	local carryConfig = config.Carry
	local carryFolder = ensureFolder(replicatedStorage, carryConfig.REMOTE_FOLDER)
	ensureRemoteEvent(carryFolder, carryConfig.COMMAND_REMOTE)
	ensureRemoteEvent(carryFolder, carryConfig.NOTIFY_REMOTE)
	ensureRemoteEvent(carryFolder, carryConfig.DEBUG_REMOTE)
end

local function provisionGravityRemotes(replicatedStorage: ReplicatedStorage, config: any)
	if config.FeatureFlags.GravityEnabled ~= true then
		return
	end

	local gravityConfig = config.Gravity
	local gravityFolder = ensureFolder(replicatedStorage, gravityConfig.REMOTE_FOLDER)
	ensureRemoteEvent(gravityFolder, gravityConfig.COMMAND_REMOTE)
end

return function(replicatedStorage: ReplicatedStorage, remotes: Folder, config: any)
	provisionRemotesFolder(remotes, config)
	provisionSyncRemotes(replicatedStorage, config)
	provisionCarryRemotes(replicatedStorage, config)
	provisionGravityRemotes(replicatedStorage, config)
end
