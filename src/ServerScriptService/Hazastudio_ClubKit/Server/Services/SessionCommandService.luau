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
	-- True while a /re in-place appearance refresh is in flight.
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
		if syncService and type(syncService.clearPreparedRefresh) == "function" then
			syncService:clearPreparedRefresh(player)
		end
	end

	--- Fetch website avatar description. No kit TTL cache (that caused /re no-ops).
	local function fetchFreshDescription(player: Player): HumanoidDescription?
		pcall(function()
			local clearFn = (player :: any).ClearCachedAvatarAppearance
			if type(clearFn) == "function" then
				clearFn(player)
			end
		end)

		local ok, desc = pcall(function()
			return Players:GetHumanoidDescriptionFromUserIdAsync(player.UserId)
		end)
		if ok and typeof(desc) == "Instance" and desc:IsA("HumanoidDescription") then
			return desc
		end

		-- DevForum workaround when GetHumanoidDescription fails: build a temp model.
		local okModel, model = pcall(function()
			return Players:CreateHumanoidModelFromUserIdAsync(player.UserId)
		end)
		if not okModel or typeof(model) ~= "Instance" then
			return nil
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local applied: HumanoidDescription? = nil
		if humanoid then
			local okApplied, result = pcall(function()
				return humanoid:GetAppliedDescription()
			end)
			if okApplied and typeof(result) == "Instance" and result:IsA("HumanoidDescription") then
				applied = result
			end
		end
		pcall(function()
			model:Destroy()
		end)
		return applied
	end

	--- Clone website HD and mark UseAvatarSettings when the property exists.
	local function prepareRefreshDescription(website: HumanoidDescription): HumanoidDescription
		local okClone, cloned = pcall(function()
			return website:Clone()
		end)
		local out: HumanoidDescription = if okClone and cloned then cloned else website
		pcall(function()
			if (out :: any).UseAvatarSettings ~= nil then
				(out :: any).UseAvatarSettings = true
			end
		end)
		return out
	end

	local function applyAppearanceInPlace(humanoid: Humanoid, desc: HumanoidDescription): (boolean, string?)
		-- Hangout-style ApplyDescription (stay put). Avoid Reset — can break Avatar Settings.
		local ok, err = pcall(function()
			local asyncApply = (humanoid :: any).ApplyDescriptionAsync
			if type(asyncApply) == "function" then
				asyncApply(humanoid, desc)
			else
				humanoid:ApplyDescription(desc)
			end
		end)
		if ok then
			return true, nil
		end
		return false, tostring(err)
	end

	local function emitAvatarRefreshed(player: Player)
		local bus = deps.eventBus
		if bus and type(bus.emit) == "function" then
			bus:emit("Avatar:Refreshed", {
				player = player,
				reason = "session_refresh_inplace",
			})
		end
	end

	local function restoreDanceImmediately(player: Player)
		if syncService and type(syncService.restorePreparedRefresh) == "function" then
			syncService:restorePreparedRefresh(player)
		end
	end

	-- Stream destination before PivotTo so large / StreamingEnabled maps do not
	-- leave the player at SpawnLocation or drop them through unloaded terrain.
	local function restorePositionWithStream(player: Player, character: Model, restoreCFrame: CFrame)
		local lifted = restoreCFrame + Vector3.new(0, Config.Session.RESTORE_Y_OFFSET, 0)
		CharacterReady.pivotTo(player, character, lifted)
	end

	-- Single-flight id so a superseded CharacterAdded aborts the older restore loop
	-- instead of double-pivoting or racing clear of pending.
	local restoreFlightId: { [number]: number } = {}

	local function restoreAfterCharacterAdded(player: Player, payload: RestorePayload)
		local userId = player.UserId
		local flight = (restoreFlightId[userId] or 0) + 1
		restoreFlightId[userId] = flight

		task.spawn(function()
			local function isFlight(): boolean
				return restoreFlightId[userId] == flight and player.Parent ~= nil
			end

			local timeout = math.max(8, tonumber(Config.Overhead.CHARACTER_PART_WAIT_TIMEOUT) or 5)
			local snap = CharacterReady.waitForPositionRestore(player, timeout)
			if not isFlight() then
				return
			end
			if not snap then
				-- Keep pending so a later CharacterAdded can retry. Lock timeout is the safety net.
				log:warn("Restore deferred - character not ready yet", {
					player = player.Name,
				})
				return
			end

			local restoreCFrame = deserializeCFrame(payload.cframe)
			if not restoreCFrame then
				pendingRespawnRestore[userId] = nil
				pendingJoinRestore[userId] = nil
				clearRefreshLock(player)
				return
			end

			local character = snap.character
			local humanoid = snap.humanoid
			local lifted = restoreCFrame + Vector3.new(0, Config.Session.RESTORE_Y_OFFSET, 0)
			local targetPos = lifted.Position

			local function applyPivot(): boolean
				if not isFlight() then
					return false
				end
				if player.Character ~= character or not character.Parent then
					return false
				end
				humanoid:ChangeState(Enum.HumanoidStateType.Physics)
				restorePositionWithStream(player, character, restoreCFrame)
				return true
			end

			if not applyPivot() then
				log:warn("Restore deferred - character replaced before pivot", {
					player = player.Name,
				})
				return
			end

			-- Claim position pending only after a successful pivot.
			pendingRespawnRestore[userId] = nil
			pendingJoinRestore[userId] = nil

			local function reassertIfDrifted()
				if not isFlight() then
					return
				end
				if player.Character ~= character or not character.Parent then
					return
				end
				local hrp = character:FindFirstChild("HumanoidRootPart")
				if hrp and hrp:IsA("BasePart") and (hrp.Position - targetPos).Magnitude > 8 then
					-- SpawnLocation / streaming can overwrite an early PivotTo.
					restorePositionWithStream(player, character, restoreCFrame)
				end
			end

			-- Engine spawn placement often lands after CharacterAdded; re-assert twice.
			task.defer(reassertIfDrifted)
			task.delay(0.2, reassertIfDrifted)

			task.defer(function()
				if humanoid.Parent then
					humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				end
			end)

			local syncPayload = pendingAfkSyncRestore[userId]
			if syncPayload then
				pendingAfkSyncRestore[userId] = nil
				pendingReSyncRestore[userId] = nil
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
					userId = userId,
				})
				return
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

		player.CharacterAdded:Connect(function(_character)
			-- Keep pending until pivot succeeds. Each CharacterAdded starts a new
			-- flight that supersedes the previous loop (no double-pivot race).
			local pending = pendingRespawnRestore[player.UserId] or pendingJoinRestore[player.UserId]
			if not pending then
				return
			end
			restoreAfterCharacterAdded(player, pending)
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
		restoreFlightId[player.UserId] = nil
	end

	function service:handleRefresh(player: Player): Result<nil>
		if not limiter:check(player.UserId) then
			notify.player(player, Config.Session.MSG_RATE_LIMIT, "WARNING")
			return Result.Err(Config.Session.MSG_RATE_LIMIT)
		end

		if pendingReSyncRestore[player.UserId] then
			notify.player(player, Config.Session.MSG_REFRESH_BUSY, "WARNING")
			return Result.Err(Config.Session.MSG_REFRESH_BUSY)
		end

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not character.Parent or not humanoid then
			notify.player(player, Config.Session.MSG_REFRESH_FAILED, "ERROR")
			return Result.Err(Config.Session.MSG_REFRESH_FAILED)
		end

		if syncService and type(syncService.prepareRefreshRestore) == "function" then
			syncService:prepareRefreshRestore(player)
		end

		notify.player(player, Config.Session.MSG_REFRESHING, "INFO")

		-- Busy lock only — no LoadCharacter, no spawn hop, no camera restore.
		pendingReSyncRestore[player.UserId] = true
		local userId = player.UserId
		local lockTimeout = math.max(5, tonumber(Config.Session.REFRESH_LOCK_TIMEOUT) or 12)
		task.delay(lockTimeout, function()
			if pendingReSyncRestore[userId] then
				pendingReSyncRestore[userId] = nil
				local stillHere = Players:GetPlayerByUserId(userId)
				if stillHere and syncService and type(syncService.clearPreparedRefresh) == "function" then
					syncService:clearPreparedRefresh(stillHere)
				end
				log:warn("Refresh lock timed out", { userId = userId })
			end
		end)

		local websiteDesc = fetchFreshDescription(player)
		if not websiteDesc then
			clearRefreshLock(player)
			log:warn("Refresh description fetch failed", { player = player.Name })
			notify.player(player, Config.Session.MSG_REFRESH_FAILED, "ERROR")
			return Result.Err(Config.Session.MSG_REFRESH_FAILED)
		end

		-- Character may have been replaced while yielding on the fetch.
		character = player.Character
		humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not character.Parent or not humanoid or player.UserId ~= userId then
			clearRefreshLock(player)
			notify.player(player, Config.Session.MSG_REFRESH_FAILED, "ERROR")
			return Result.Err(Config.Session.MSG_REFRESH_FAILED)
		end

		local desc = prepareRefreshDescription(websiteDesc)
		local applied, applyErr = applyAppearanceInPlace(humanoid, desc)
		if not applied then
			clearRefreshLock(player)
			log:warn("ApplyDescription refresh failed", {
				player = player.Name,
				error = tostring(applyErr),
			})
			notify.player(player, Config.Session.MSG_REFRESH_FAILED, "ERROR")
			return Result.Err(Config.Session.MSG_REFRESH_FAILED)
		end

		-- Dance first (same frame as apply) so /re while jogging feels continuous.
		-- Overhead waits for Head settle separately — must not delay dance.
		pendingReSyncRestore[userId] = nil
		restoreDanceImmediately(player)

		task.spawn(function()
			if not player.Parent or player.UserId ~= userId then
				return
			end
			local current = player.Character
			if current then
				CharacterReady.waitStableHead(current, 5)
			end
			if player.Parent and player.Character == current then
				emitAvatarRefreshed(player)
			end
		end)

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
