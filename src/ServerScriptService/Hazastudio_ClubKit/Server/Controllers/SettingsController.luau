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
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)

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
	profileLoader: any?,
})
	local log = deps.logger
	local remotes = deps.remotes
	local settingsService = deps.settingsService
	local notify = deps.notify
	local overheadRepository = deps.overheadRepository
	local overheadController = deps.overheadController
	local profileLoader = deps.profileLoader

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

	-- Coalesce Settings → Overhead public visibility writes (anti UpdateAsync spam).
	local PUBLIC_SYNC_IDLE_SEC = 3
	local pendingPublicSyncByUserId: {
		[number]: {
			layers: { [string]: boolean },
			badges: { [string]: boolean },
		},
	} =
		{}
	local publicSyncTokenByUserId: { [number]: number } = {}

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

	local function boolMapsEqual(a: { [string]: boolean }?, b: { [string]: boolean }?): boolean
		if a == b then
			return true
		end
		if type(a) ~= "table" or type(b) ~= "table" then
			return false
		end
		for key, value in pairs(a) do
			if b[key] ~= value then
				return false
			end
		end
		for key, value in pairs(b) do
			if a[key] ~= value then
				return false
			end
		end
		return true
	end

	-- Diff-before-write + at most one short retry. Returns true when stored
	-- public maps match the requested maps (including no-op / already synced).
	local function writePublicOverheadVisibility(
		player: Player,
		publicLayerVisible: { [string]: boolean },
		publicBadgeVisible: { [string]: boolean }
	): boolean
		if not overheadRepository then
			return true
		end

		local retryDelays = { 0, 1 }
		for _, delaySec in ipairs(retryDelays) do
			if delaySec > 0 then
				task.wait(delaySec)
			end
			if not player.Parent then
				return false
			end

			local didChange = false
			local overheadSaved = overheadRepository:update(player.UserId, function(current)
				local nextData = OverheadDomain.mergeStored(current, {
					publicOverheadLayerVisible = publicLayerVisible,
					publicOverheadBadgeVisible = publicBadgeVisible,
				})
				if
					boolMapsEqual(current.publicOverheadLayerVisible, nextData.publicOverheadLayerVisible)
					and boolMapsEqual(current.publicOverheadBadgeVisible, nextData.publicOverheadBadgeVisible)
				then
					return current
				end
				didChange = true
				return nextData
			end)
			if overheadSaved.ok then
				if
					didChange
					and overheadController
					and type(overheadController.refreshPlayer) == "function"
				then
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

	local function cancelPublicOverheadSync(userId: number)
		publicSyncTokenByUserId[userId] = (publicSyncTokenByUserId[userId] or 0) + 1
		pendingPublicSyncByUserId[userId] = nil
	end

	local function flushPublicOverheadSync(player: Player): boolean
		local userId = player.UserId
		local pending = pendingPublicSyncByUserId[userId]
		if not pending then
			return true
		end
		cancelPublicOverheadSync(userId)
		return writePublicOverheadVisibility(player, pending.layers, pending.badges)
	end

	local function schedulePublicOverheadSync(
		player: Player,
		publicLayerVisible: { [string]: boolean },
		publicBadgeVisible: { [string]: boolean }
	)
		local userId = player.UserId
		pendingPublicSyncByUserId[userId] = {
			layers = publicLayerVisible,
			badges = publicBadgeVisible,
		}
		publicSyncTokenByUserId[userId] = (publicSyncTokenByUserId[userId] or 0) + 1
		local token = publicSyncTokenByUserId[userId]
		task.delay(PUBLIC_SYNC_IDLE_SEC, function()
			if publicSyncTokenByUserId[userId] ~= token then
				return
			end
			local pending = pendingPublicSyncByUserId[userId]
			pendingPublicSyncByUserId[userId] = nil
			if not pending then
				return
			end
			if not player.Parent then
				return
			end
			local synced = writePublicOverheadVisibility(player, pending.layers, pending.badges)
			if not synced and notify and player.Parent then
				notify.player(
					player,
					"[Settings] Saved locally, but public overhead visibility may not have synced yet. Try again.",
					"WARNING"
				)
			end
		end)
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
			schedulePublicOverheadSync(
				player,
				updated.value.overheadLayerVisible,
				updated.value.overheadBadgeVisible
			)
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
			local maxBytes = (Config.Settings and Config.Settings.MAX_PAYLOAD_BYTES) or (8 * 1024)
			local sizeOk, encodedBytes = Validator.checkSizeLimit(payload, maxBytes)
			if not sizeOk then
				log:warn("Settings update rejected: payload too large", {
					player = player.Name,
					bytes = encodedBytes,
					maxBytes = maxBytes,
				})
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
			-- Reset should apply public defaults promptly (not wait for idle debounce).
			cancelPublicOverheadSync(player.UserId)
			if overheadRepository then
				local defaultSettings = SettingsDomain.defaultStoredData()
				task.spawn(function()
					local synced = writePublicOverheadVisibility(
						player,
						defaultSettings.overheadLayerVisible,
						defaultSettings.overheadBadgeVisible
					)
					if not synced and notify and player.Parent then
						notify.player(
							player,
							"[Settings] Reset saved, but public overhead visibility may not have synced yet.",
							"WARNING"
						)
					end
				end)
			end
			if notify then
				notify.player(player, "[Settings] All settings were reset.", "SUCCESS")
			end
		end))

		track(Players.PlayerRemoving:Connect(function(player)
			-- Flush coalesced privacy sync before settings leave-flush so public
			-- maps are not lost when the player leaves mid-debounce.
			local pending = pendingPublicSyncByUserId[player.UserId]
			if pending then
				flushPublicOverheadSync(player)
			end
			settingsService:onPlayerRemoving(player)
			cancelPublicOverheadSync(player.UserId)
		end))

		-- Fold join-time settings GetAsync into SharedProfileLoader instead of
		-- free-firing parallel reads on PlayerAdded against overhead/profile.
		if profileLoader and type(profileLoader.register) == "function" and type(profileLoader.enqueueKind) == "function" then
			profileLoader:register("settings", function(player: Player)
				fireSyncWithRetry(player)
				return Result.Ok(true)
			end)
			track(Players.PlayerAdded:Connect(function(player)
				profileLoader:enqueueKindDeferred(player, "settings")
			end))
			for _, player in ipairs(Players:GetPlayers()) do
				profileLoader:enqueueKindDeferred(player, "settings")
			end
		else
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
		end

		log:info("SettingsController initialized")
	end

	function controller:destroy()
		for userId in pairs(pendingPublicSyncByUserId) do
			cancelPublicOverheadSync(userId)
		end
		for _, conn in ipairs(_connections) do
			conn:Disconnect()
		end
		table.clear(_connections)
	end

	return controller
end

return createSettingsController
