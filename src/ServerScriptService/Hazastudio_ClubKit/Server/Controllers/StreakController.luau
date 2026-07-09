--!strict
-- Server/Controllers/StreakController.lua
-- Fire StreakNotif ke client setelah processLogin berhasil.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local NetworkManager = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkManager)
local log = Logger.new("StreakController")

local function createStreakController(deps: {
	streakService: any,
	overheadController: any,
	remotes: Folder,
})
	local streakService = deps.streakService
	local overheadController = deps.overheadController
	local remotes = deps.remotes
	local processedUserIds: { [number]: boolean } = {}

	local function getOrCreateRemote(name: string): RemoteEvent
		local existing = remotes:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotes
		return remote
	end

	local notifRemote = getOrCreateRemote(Config.Streak.REMOTE_NOTIF)
	local notifNetwork = NetworkManager.create({
		reliable = notifRemote,
		logger = log,
		isServer = true,
	})

	local function isMilestone(days: number): boolean
		for _, milestone in ipairs(Config.Streak.MILESTONE_DAYS) do
			if days == milestone then
				return true
			end
		end
		return false
	end

	local controller = {}

	function controller:processLoginForPlayer(player: Player)
		if not player.Parent then
			return
		end
		local userId = player.UserId
		if processedUserIds[userId] then
			return
		end
		processedUserIds[userId] = true

		task.spawn(function()
			if not player.Character then
				player.CharacterAdded:Wait()
			end
			task.wait(Config.Streak.CLIENT_READY_DELAY)
			if not player.Parent then
				processedUserIds[userId] = nil
				return
			end

			local result = streakService:processLogin(player)
			if not result.ok then
				processedUserIds[userId] = nil
				return
			end

			local streakResult = result.value
			if streakResult.alreadyCounted then
				return
			end

			local payload = {
				streakDays = streakResult.newStreakDays,
				didReset = streakResult.didReset,
				didIncrement = streakResult.didIncrement,
				isMilestone = isMilestone(streakResult.newStreakDays),
			}
			overheadController:refreshPlayer(player)
			notifNetwork:fireClient(player, payload)
			log:info("StreakNotif fired", {
				player = player.Name,
				streak = streakResult.newStreakDays,
				milestone = payload.isMilestone,
			})
		end)
	end

	function controller:onPlayerRemoving(player: Player)
		processedUserIds[player.UserId] = nil
	end

	log:info("StreakController initialized", {})
	return controller
end

return createStreakController
