--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local SettingsDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.SettingsDomain)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local NetworkManager = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkManager)
local Validator = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Validator)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local TTLSet = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.TTLSet)

type ILogger = Types.ILogger
type INotify = {
	player: (Player, string, string?) -> (),
	all: (string, string?) -> (),
}

local function createSettingsController(deps: {
	logger: ILogger,
	remotes: Folder,
	settingsService: any,
	notify: INotify?,
	overheadRepository: any?,
	overheadController: any?,
})
	local log = deps.logger
	local remotes = deps.remotes
	local settingsService = deps.settingsService
	local notify = deps.notify
	local overheadRepository = deps.overheadRepository
	local overheadController = deps.overheadController

	local syncRemote = remotes:WaitForChild(Config.Settings.REMOTE_SYNC) :: RemoteEvent
	local requestRemote = remotes:WaitForChild(Config.Settings.REMOTE_REQUEST) :: RemoteEvent
	local updateRemote = remotes:WaitForChild(Config.Settings.REMOTE_UPDATE) :: RemoteEvent
	local resetRemote = remotes:WaitForChild(Config.Settings.REMOTE_RESET) :: RemoteEvent

	-- NetworkManager batches per-Heartbeat. Settings sync fires on join, on
	-- update, and on reset; batching coalesces multi-field updates from rapid
	-- toggle clicks onto one wire flush per player.
	local syncNetwork = NetworkManager.create({
		reliable = syncRemote,
		logger = log,
		isServer = true,
	})

	local limiter = RateLimiter.new(Config.Settings.UPDATE_RATE_MAX, Config.Settings.UPDATE_RATE_WINDOW)
	local processedRequests = TTLSet.create({
		ttl = Config.Security.REQUEST_DEDUPE_WINDOW,
		maxSize = 200,
	})

	local _connections: { RBXScriptConnection } = {}

	local function track(conn: RBXScriptConnection): RBXScriptConnection
		table.insert(_connections, conn)
		return conn
	end

	local controller = {}

	local function fireSync(player: Player)
		local loaded = settingsService:load(player)
		if not loaded.ok then
			log:warn("load failed", { player = player.Name, error = loaded.error })
			syncNetwork:fireClient(player, SettingsDomain.merge(nil, nil))
			return
		end
		syncNetwork:fireClient(player, loaded.value)
	end

	-- Join-time fire with backoff retries. A single repo:load already retries
	-- internally (Result.withRetry + BudgetGate), but budget exhaustion can
	-- persist across that short window. Retrying at the controller level gives
	-- the budget a chance to recover before we give up and hand the client
	-- defaults (which, combined with the service write-gate, prevents the
	-- player from clobbering their real stored settings).
	local function fireSyncWithRetry(player: Player)
		local delays = { 0, 1, 3, 8 }
		for _, delay in ipairs(delays) do
			if delay > 0 then
				task.wait(delay)
			end
			if not player.Parent then
				return
			end
			local loaded = settingsService:load(player)
			if loaded.ok then
				syncNetwork:fireClient(player, loaded.value)
				return
			end
			log:warn("load retry failed", { player = player.Name, error = loaded.error, attempt = delay })
		end
		log:warn("load failed after retries", { player = player.Name })
		syncNetwork:fireClient(player, SettingsDomain.merge(nil, nil))
	end

	local function syncPublicOverheadVisibility(
		player: Player,
		publicLayerVisible: { [string]: boolean },
		publicBadgeVisible: { [string]: boolean }
	): boolean
		if not overheadRepository then
			return true
		end

		local retryDelays = { 0, 1, 3 }
		for _, delaySec in ipairs(retryDelays) do
			if delaySec > 0 then
				task.wait(delaySec)
			end
			if not player.Parent then
				return false
			end

			local overheadSaved = overheadRepository:update(player.UserId, function(current)
				return OverheadDomain.mergeStored(current, {
					publicOverheadLayerVisible = publicLayerVisible,
					publicOverheadBadgeVisible = publicBadgeVisible,
				})
			end)
			if overheadSaved.ok then
				if overheadController and type(overheadController.refreshPlayer) == "function" then
					overheadController:refreshPlayer(player)
				end
				return true
			end

			log:warn("public overhead visibility update failed", {
				player = player.Name,
				error = overheadSaved.error,
				delaySec = delaySec,
			})
		end

		return false
	end

	local function upsertStored(player: Player, incoming: any)
		if type(incoming) ~= "table" then
			return
		end

		local updated = settingsService:updateStored(player, function(current)
			local merged = table.clone(current)
			local mergedAny = merged :: any
			for key, value in pairs(incoming) do
				mergedAny[key] = value
			end
			return SettingsDomain.sanitizeStored(merged)
		end)

		if not updated.ok then
			log:warn("update failed", { player = player.Name, error = updated.error })
			if notify then
				notify.player(player, "[Settings] Could not save your changes. Try again.", "WARNING")
			end
			return
		end

		if
			type(incoming.overheadLayerVisible) == "table"
			or type(incoming.overheadBadgeVisible) == "table"
		then
			local publicLayerVisible = updated.value.overheadLayerVisible
			local publicBadgeVisible = updated.value.overheadBadgeVisible
			task.spawn(function()
				local synced = syncPublicOverheadVisibility(player, publicLayerVisible, publicBadgeVisible)
				if not synced and notify and player.Parent then
					notify.player(
						player,
						"[Settings] Saved locally, but public overhead visibility may not have synced yet. Try again.",
						"WARNING"
					)
				end
			end)
		end

		syncNetwork:fireClient(player, updated.value)
	end

	function controller:init()
		track(requestRemote.OnServerEvent:Connect(function(player: Player)
			fireSync(player)
		end))

		track(updateRemote.OnServerEvent:Connect(function(player: Player, payload: any)
			if type(payload) ~= "table" then
				return
			end
			if not Validator.checkSize(payload) then
				log:warn("Settings update rejected: payload too large", { player = player.Name })
				return
			end
			if not limiter:check(player.UserId) then
				log:warn("Settings update rate limited", { player = player.Name })
				return
			end
			if type(payload.requestId) == "string" and #payload.requestId > 0 then
				if processedRequests:contains(payload.requestId) then
					return
				end
				processedRequests:add(payload.requestId)
			end
			upsertStored(player, payload)
		end))

		track(resetRemote.OnServerEvent:Connect(function(player: Player)
			local reset = settingsService:reset(player)
			if not reset.ok then
				log:warn("reset failed", { player = player.Name, error = reset.error })
				if notify then
					notify.player(player, "[Settings] Could not reset your settings yet.", "WARNING")
				end
				return
			end

			syncNetwork:fireClient(player, reset.value)
			if overheadRepository then
				local defaultSettings = SettingsDomain.defaultStoredData()
				local overheadSaved = overheadRepository:update(player.UserId, function(current)
					return OverheadDomain.mergeStored(current, {
						publicOverheadLayerVisible = defaultSettings.overheadLayerVisible,
						publicOverheadBadgeVisible = defaultSettings.overheadBadgeVisible,
					})
				end)
				if overheadSaved.ok and overheadController and type(overheadController.refreshPlayer) == "function" then
					overheadController:refreshPlayer(player)
				end
			end
			if notify then
				notify.player(player, "[Settings] All settings were reset.", "SUCCESS")
			end
		end))

		track(Players.PlayerAdded:Connect(function(player)
			task.spawn(function()
				fireSyncWithRetry(player)
			end)
		end))

		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(function()
				fireSyncWithRetry(player)
			end)
		end

		track(Players.PlayerRemoving:Connect(function(player)
			settingsService:onPlayerRemoving(player)
		end))

		log:info("SettingsController initialized")
	end

	function controller:destroy()
		for _, conn in ipairs(_connections) do
			conn:Disconnect()
		end
		table.clear(_connections)
	end

	return controller
end

return createSettingsController
