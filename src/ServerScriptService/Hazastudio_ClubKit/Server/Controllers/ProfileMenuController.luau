--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local NetworkManager = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkManager)

type ILogger = Types.ILogger
type INotify = {
	player: (Player, string, string?) -> (),
	all: (string, string?) -> (),
}

local PUBLIC_OVERHEAD_FIELDS = {
	displayNameOverride = true,
	specialTitle = true,
	relationshipMode = true,
	showCoupleName = true,
	statusText = true,
}

local function createProfileMenuController(deps: {
	logger: ILogger,
	remotes: Folder,
	profileMenuService: any,
	notify: INotify?,
	overheadController: any?,
	avatarContextController: any?,
})
	local log = deps.logger
	local remotes = deps.remotes
	local profileMenuService = deps.profileMenuService
	local notify = deps.notify
	local overheadController = deps.overheadController
	local avatarContextController = deps.avatarContextController

	local requestRemote = remotes:WaitForChild(Config.ProfileMenu.REMOTE_REQUEST) :: RemoteEvent
	local syncRemote = remotes:WaitForChild(Config.ProfileMenu.REMOTE_SYNC) :: RemoteEvent
	local updateRemote = remotes:WaitForChild(Config.ProfileMenu.REMOTE_UPDATE) :: RemoteEvent

	-- NetworkManager batches per-Heartbeat. Profile sync fires on join + on
	-- per-field update; rapid edits in the menu coalesce onto one wire flush.
	local syncNetwork = NetworkManager.create({
		reliable = syncRemote,
		logger = log,
		isServer = true,
	})

	local controller = {}

	local function fireSync(player: Player)
		local loaded = profileMenuService:load(player)
		if not loaded.ok then
			log:warn("profile menu load failed", {
				player = player.Name,
				error = loaded.error,
			})
			return
		end

		syncNetwork:fireClient(player, loaded.value)
	end

	-- Public: force a fresh profile-menu payload to a player. Used by other
	-- server controllers (e.g. AdminController) that mutate overhead-backed
	-- profile fields (like specialTitle) so an already-open profile panel
	-- updates live without requiring the player to rejoin.
	function controller:syncPlayer(player: Player)
		fireSync(player)
	end

	local function pushLiveUpdate(player: Player, field: string)
		if
			PUBLIC_OVERHEAD_FIELDS[field]
			and overheadController
			and type(overheadController.refreshPlayer) == "function"
		then
			overheadController:refreshPlayer(player)
		end

		if avatarContextController and type(avatarContextController.pushContextUpdate) == "function" then
			avatarContextController:pushContextUpdate(player.UserId)
		end
	end

	function controller:init()
		requestRemote.OnServerEvent:Connect(function(player: Player)
			fireSync(player)
		end)

		updateRemote.OnServerEvent:Connect(function(player: Player, payload: any)
			if type(payload) ~= "table" then
				return
			end

			local field = payload.field
			if type(field) ~= "string" or field == "" then
				return
			end

			local result = profileMenuService:updateField(player, field, payload.value)
			if not result.ok then
				if notify then
					notify.player(player, result.error, "WARNING")
				end
				fireSync(player)
				return
			end

			syncNetwork:fireClient(player, result.value)
			pushLiveUpdate(player, field)
		end)

		Players.PlayerAdded:Connect(function(player)
			task.spawn(function()
				fireSync(player)
			end)
		end)

		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(function()
				fireSync(player)
			end)
		end

		log:info("ProfileMenuController initialized")
	end

	return controller
end

return createProfileMenuController
