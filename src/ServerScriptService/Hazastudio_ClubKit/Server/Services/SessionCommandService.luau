--!strict

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local AfkGuardDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.AfkGuardDomain)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local CharacterReady = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.CharacterReady)

type Result<T> = Types.Result<T>

type RestorePayload = {
	cframe: {number},
}

type AfkSyncRestoreOptions = {
	fireSyncNotification: ((player: Player, payload: { [string]: any }) -> ())?,
	notifyPlayer: ((player: Player, message: string, kind: string?) -> ())?,
}

local function createSessionCommandService(deps: {
	notify: any,
	syncService: any?,
	eventBus: any?,
	syncNotify: ((player: Player, payload: { [string]: any }) -> ())?,
})
	local notify = deps.notify
	local syncService = deps.syncService
	local syncNotify = deps.syncNotify
	local log = Logger.new("SessionCommandService")
	local limiter = RateLimiter.new(Config.Session.RATE_MAX, Config.Session.RATE_WINDOW)
	local pendingRespawnRestore: { [number]: RestorePayload } = {}
	local pendingJoinRestore: { [number]: RestorePayload } = {}
	local pendingAfkSyncRestore: { [number]: AfkGuardDomain.SyncRestorePayload } = {}
	-- True while a /re LoadCharacter → restore cycle is in flight.
	local pendingReSyncRestore: { [number]: boolean } = {}

	local service = {}

	local function serializeCFrame(cframe: CFrame): { number }
		return { cframe:GetComponents() }
	end

	local function deserializeCFrame(values: { number }): CFrame?
		if #values ~= 12 then
			return nil
		end

		for _, value in ipairs(values) do
			if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
				return nil
			end
		end

		local MAX_POSITION = 100000
		if
			math.abs(values[1]) > MAX_POSITION
			or math.abs(values[2]) > MAX_POSITION
			or math.abs(values[3]) > MAX_POSITION
		then
			return nil
		end

		return CFrame.new(
			values[1],
			values[2],
			values[3],
			values[4],
			values[5],
			values[6],
			values[7],
			values[8],
			values[9],
			values[10],
			values[11],
			values[12]
		)
	end

	local function getCharacterRestoreCFrame(player: Player): CFrame?
		local character = player.Character
		if not character then
			return nil
		end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			return hrp.CFrame
		end

		local ok, pivot = pcall(function()
			return character:GetPivot()
		end)
		if ok then
			return pivot
		end

		return nil
	end

	local function getCharacterModel(player: Player): Model?
		local character = player.Character
		if character and character.Parent then
			return character
		end
		return nil
	end

	local function getTeleportCFrameNear(anchor: CFrame): CFrame
		local forwardOffset = tonumber(Config.Session.TELEPORT_FORWARD_OFFSET) or 4
		local yOffset = tonumber(Config.Session.TELEPORT_Y_OFFSET) or 3
		return anchor * CFrame.new(0, yOffset, -forwardOffset)
	end

	local function movePlayerCharacter(player: Player, targetCFrame: CFrame): boolean
		local character = getCharacterModel(player)
		if not character then
			return false
		end
		return CharacterReady.pivotTo(player, character, targetCFrame)
	end

	local function clearRefreshLock(player: Player)
		local userId = player.UserId
		pendingReSyncRestore[userId] = nil
		pendingRespawnRestore[userId] = nil
		if syncService and type(syncService.clearPreparedRefresh) == "function" then
			syncService:clearPreparedRefresh(player)
		end
	end

	-- Stream destination before PivotTo so large / StreamingEnabled maps do not
	-- leave the player at SpawnLocation or drop them through unloaded terrain.
	local function restorePositionWithStream(player: Player, character: Model, restoreCFrame: CFrame)
		local lifted = restoreCFrame + Vector3.new(0, Config.Session.RESTORE_Y_OFFSET, 0)
		CharacterReady.pivotTo(player, character, lifted)
	end

	local function restoreAfterCharacterAdded(player: Player, character: Model, payload: RestorePayload)
		task.spawn(function()
			local snap = CharacterReady.wait(character, "parts")
			if not snap then
				clearRefreshLock(player)
				log:warn("Restore skipped - character not ready", {
					player = player.Name,
				})
				return
			end
			local humanoid = snap.humanoid

			local restoreCFrame = deserializeCFrame(payload.cframe)
			if not restoreCFrame then
				clearRefreshLock(player)
				return
			end

			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			restorePositionWithStream(player, character, restoreCFrame)
			task.defer(function()
				if humanoid.Parent then
					humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				end
			end)

			local syncPayload = pendingAfkSyncRestore[player.UserId]
			if syncPayload then
				pendingAfkSyncRestore[player.UserId] = nil
				pendingReSyncRestore[player.UserId] = nil
				if syncService and type(syncService.restoreAfterAfkRejoin) == "function" then
					task.defer(function()
						local options: AfkSyncRestoreOptions = {
							fireSyncNotification = syncNotify,
							notifyPlayer = function(target: Player, message: string, kind: string?)
								notify.player(target, message, kind)
							end,
						}
						syncService:restoreAfterAfkRejoin(player, syncPayload, options)
					end)
				end
				log:info("afk_restore_position_ok", {
					player = player.Name,
					userId = player.UserId,
				})
				return
			end

			-- /re: restore dance only. OverheadController onCharacterAdded already
			-- attaches + recovery broadcast (avoids double attach).
			if pendingReSyncRestore[player.UserId] then
				pendingReSyncRestore[player.UserId] = nil
				if syncService and type(syncService.restorePreparedRefresh) == "function" then
					task.defer(function()
						syncService:restorePreparedRefresh(player)
					end)
				end
			end
		end)
	end

	local function wirePlayer(player: Player)
		local joinData = player:GetJoinData()
		local teleportData = joinData and joinData.TeleportData
		if type(teleportData) == "table" then
			local restoreData = (teleportData :: any).sessionRestore
			if type(restoreData) == "table" then
				local placeId = tonumber(restoreData.placeId)
				local jobId = tostring(restoreData.jobId or "")
				local values = restoreData.cframe
				local afkRejoin = restoreData.afkRejoin == true
				if placeId == game.PlaceId and type(values) == "table" and (jobId == game.JobId or afkRejoin) then
					pendingJoinRestore[player.UserId] = {
						cframe = values,
					}
				end
				if afkRejoin and type(restoreData.syncRestore) == "table" then
					local validated = AfkGuardDomain.validateSyncRestorePayload(restoreData.syncRestore)
					if validated.ok then
						pendingAfkSyncRestore[player.UserId] = validated.value
					else
						log:warn("Invalid AFK sync restore payload", {
							player = player.Name,
							userId = player.UserId,
							error = validated.error,
						})
					end
				end
				if afkRejoin and jobId ~= "" and jobId ~= game.JobId then
					task.defer(function()
						if player.Parent then
							notify.player(player, Config.AfkGuard.MSG_FALLBACK_SERVER, "WARNING")
						end
					end)
				end
			end
		end

		player.CharacterAdded:Connect(function(character)
			local pending = pendingRespawnRestore[player.UserId]
			if pending then
				pendingRespawnRestore[player.UserId] = nil
				restoreAfterCharacterAdded(player, character, pending)
				return
			end

			local joinPending = pendingJoinRestore[player.UserId]
			if not joinPending then
				return
			end

			pendingJoinRestore[player.UserId] = nil
			restoreAfterCharacterAdded(player, character, joinPending)
		end)
	end

	function service:init()
		for _, player in ipairs(Players:GetPlayers()) do
			wirePlayer(player)
		end
		Players.PlayerAdded:Connect(wirePlayer)
	end

	function service:onPlayerRemoving(player: Player)
		pendingRespawnRestore[player.UserId] = nil
		pendingJoinRestore[player.UserId] = nil
		pendingAfkSyncRestore[player.UserId] = nil
		pendingReSyncRestore[player.UserId] = nil
	end

	function service:handleRefresh(player: Player): Result<nil>
		if not limiter:check(player.UserId) then
			notify.player(player, Config.Session.MSG_RATE_LIMIT, "WARNING")
			return Result.Err(Config.Session.MSG_RATE_LIMIT)
		end

		if pendingReSyncRestore[player.UserId] or pendingRespawnRestore[player.UserId] then
			notify.player(player, Config.Session.MSG_REFRESH_BUSY, "WARNING")
			return Result.Err(Config.Session.MSG_REFRESH_BUSY)
		end

		local restoreCFrame = getCharacterRestoreCFrame(player)
		if not restoreCFrame then
			notify.player(player, Config.Session.MSG_RESTORE_FAILED, "ERROR")
			return Result.Err(Config.Session.MSG_RESTORE_FAILED)
		end

		if syncService and type(syncService.prepareRefreshRestore) == "function" then
			syncService:prepareRefreshRestore(player)
		end

		notify.player(player, Config.Session.MSG_REFRESHING, "INFO")

		-- Warm streamed destination before LoadCharacter so restore is less likely
		-- to land in unloaded terrain / stick near SpawnLocation on large maps.
		CharacterReady.streamAround(player, restoreCFrame.Position)

		pendingRespawnRestore[player.UserId] = {
			cframe = serializeCFrame(restoreCFrame),
		}
		pendingReSyncRestore[player.UserId] = true

		local userId = player.UserId
		local lockTimeout = math.max(5, tonumber(Config.Session.REFRESH_LOCK_TIMEOUT) or 12)
		task.delay(lockTimeout, function()
			if pendingReSyncRestore[userId] or pendingRespawnRestore[userId] then
				pendingReSyncRestore[userId] = nil
				pendingRespawnRestore[userId] = nil
				local stillHere = Players:GetPlayerByUserId(userId)
				if stillHere and syncService and type(syncService.clearPreparedRefresh) == "function" then
					syncService:clearPreparedRefresh(stillHere)
				end
				log:warn("Refresh lock timed out", { userId = userId })
			end
		end)

		local loaded, loadErr = pcall(function()
			player:LoadCharacter()
		end)
		if not loaded then
			clearRefreshLock(player)
			log:error("LoadCharacter refresh failed", {
				player = player.Name,
				error = tostring(loadErr),
			})
			notify.player(player, Config.Session.MSG_RESTORE_FAILED, "ERROR")
			return Result.Err(Config.Session.MSG_RESTORE_FAILED)
		end

		return Result.Ok(nil)
	end

	function service:handleRejoin(player: Player): Result<nil>
		if not limiter:check(player.UserId) then
			notify.player(player, Config.Session.MSG_RATE_LIMIT, "WARNING")
			return Result.Err(Config.Session.MSG_RATE_LIMIT)
		end

		local restoreCFrame = getCharacterRestoreCFrame(player)
		if not restoreCFrame then
			notify.player(player, Config.Session.MSG_RESTORE_FAILED, "ERROR")
			return Result.Err(Config.Session.MSG_RESTORE_FAILED)
		end

		local teleportData = {
			sessionRestore = {
				placeId = game.PlaceId,
				jobId = game.JobId,
				cframe = serializeCFrame(restoreCFrame),
			},
		}

		notify.player(player, Config.Session.MSG_REJOINING, "INFO")

		local success, err = pcall(function()
			TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player, nil, teleportData)
		end)

		if not success then
			log:error("Rejoin teleport failed", {
				player = player.Name,
				error = tostring(err),
			})
			notify.player(player, Config.Session.MSG_REJOIN_FAILED, "ERROR")
			return Result.Err(Config.Session.MSG_REJOIN_FAILED)
		end

		return Result.Ok(nil)
	end

	function service:handleAfkRejoin(player: Player, reportedIdleSec: number?): Result<nil>
		local afkConfig = Config.AfkGuard
		if afkConfig.ENABLED ~= true then
			return Result.Err("disabled")
		end

		local restoreCFrame = getCharacterRestoreCFrame(player)
		if not restoreCFrame then
			notify.player(player, afkConfig.MSG_REJOIN_FAILED, "ERROR")
			return Result.Err(Config.Session.MSG_RESTORE_FAILED)
		end

		local syncRestore: any = nil
		if syncService and type(syncService.captureSyncSnapshotForTeleport) == "function" then
			local rawSnapshot = syncService:captureSyncSnapshotForTeleport(player)
			if rawSnapshot then
				local validatedSnapshot = AfkGuardDomain.validateSyncRestorePayload(rawSnapshot)
				if validatedSnapshot.ok then
					syncRestore = validatedSnapshot.value
				end
			end
		end

		local teleportData = {
			sessionRestore = {
				placeId = game.PlaceId,
				jobId = game.JobId,
				cframe = serializeCFrame(restoreCFrame),
				afkRejoin = true,
				preferSameServer = afkConfig.TELEPORT_PREFER_SAME_SERVER == true,
				syncRestore = syncRestore,
			},
		}

		notify.player(player, afkConfig.MSG_REJOINING, "INFO")
		log:info("afk_teleport_started", {
			player = player.Name,
			userId = player.UserId,
			jobId = game.JobId,
			reportedIdleSec = reportedIdleSec,
		})

		local function trySameServer(): (boolean, string?)
			local ok, err = pcall(function()
				TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player, nil, teleportData)
			end)
			if ok then
				return true, nil
			end
			return false, tostring(err)
		end

		local success, err = trySameServer()
		local maxRetry = tonumber(afkConfig.MAX_RETRY) or 1
		local retryDelay = tonumber(afkConfig.RETRY_DELAY_SEC) or 30
		local canRetry = reportedIdleSec == nil or AfkGuardDomain.isBelowTeleportAbortIdle(reportedIdleSec)

		if not success and maxRetry > 0 and canRetry then
			task.wait(retryDelay)
			if player.Parent then
				success, err = trySameServer()
			end
		end

		if success then
			return Result.Ok(nil)
		end

		if afkConfig.TELEPORT_FALLBACK_NEW_SERVER == true and canRetry and player.Parent then
			local fallbackOk, fallbackErr = pcall(function()
				TeleportService:Teleport(game.PlaceId, player, teleportData)
			end)
			if fallbackOk then
				log:warn("afk_teleport_fallback_new_server", {
					player = player.Name,
					userId = player.UserId,
					error = err,
				})
				return Result.Ok(nil)
			end
			err = tostring(fallbackErr)
		end

		log:error("afk_teleport_failed", {
			player = player.Name,
			userId = player.UserId,
			error = err,
		})
		notify.player(player, afkConfig.MSG_REJOIN_FAILED, "ERROR")
		return Result.Err(afkConfig.MSG_REJOIN_FAILED)
	end

	function service:handleBring(player: Player, target: Player): Result<nil>
		if target == player then
			notify.player(player, Config.Session.MSG_TELEPORT_SELF, "WARNING")
			return Result.Err(Config.Session.MSG_TELEPORT_SELF)
		end
		if not limiter:check(player.UserId) then
			notify.player(player, Config.Session.MSG_RATE_LIMIT, "WARNING")
			return Result.Err(Config.Session.MSG_RATE_LIMIT)
		end

		local anchor = getCharacterRestoreCFrame(player)
		if not anchor then
			notify.player(player, Config.Session.MSG_RESTORE_FAILED, "ERROR")
			return Result.Err(Config.Session.MSG_RESTORE_FAILED)
		end

		if not movePlayerCharacter(target, getTeleportCFrameNear(anchor)) then
			notify.player(player, Config.Session.MSG_TELEPORT_TARGET_NOT_READY, "WARNING")
			return Result.Err(Config.Session.MSG_TELEPORT_TARGET_NOT_READY)
		end

		notify.player(player, Config.Session.MSG_TELEPORT_SUCCESS_BRING:format(target.DisplayName), "SUCCESS")
		return Result.Ok(nil)
	end

	function service:handleTo(player: Player, target: Player): Result<nil>
		if target == player then
			notify.player(player, Config.Session.MSG_TELEPORT_SELF, "WARNING")
			return Result.Err(Config.Session.MSG_TELEPORT_SELF)
		end
		if not limiter:check(player.UserId) then
			notify.player(player, Config.Session.MSG_RATE_LIMIT, "WARNING")
			return Result.Err(Config.Session.MSG_RATE_LIMIT)
		end

		local anchor = getCharacterRestoreCFrame(target)
		if not anchor then
			notify.player(player, Config.Session.MSG_TELEPORT_TARGET_NOT_READY, "WARNING")
			return Result.Err(Config.Session.MSG_TELEPORT_TARGET_NOT_READY)
		end

		if not movePlayerCharacter(player, getTeleportCFrameNear(anchor)) then
			notify.player(player, Config.Session.MSG_RESTORE_FAILED, "ERROR")
			return Result.Err(Config.Session.MSG_RESTORE_FAILED)
		end

		notify.player(player, Config.Session.MSG_TELEPORT_SUCCESS_TO:format(target.DisplayName), "SUCCESS")
		return Result.Ok(nil)
	end

	return service
end

return createSessionCommandService
