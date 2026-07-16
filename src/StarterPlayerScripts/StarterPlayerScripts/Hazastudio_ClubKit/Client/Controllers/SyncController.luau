--!strict
-- SyncController (client) — Refactored 2026-05-23.
--
-- Server is now the only thing that loads & plays animation tracks. Clients
-- receive replicated AnimationTrack changes via Roblox's built-in animation
-- replication. This controller's job is purely:
--   - Forward UI intents to the server (play/stop, sync/unsync, speed, favorites)
--   - Update local UI state from server notifications
--   - Provide local-only fallback during the loading screen

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local NotifService = require(script.Parent.Parent.Services.NotifService)
local LoadingScreenUI = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.UI.LoadingScreenUI)

local SyncController = {} :: any
SyncController.__index = SyncController

function SyncController.create(deps: {
	store: any,
	config: any,
	logger: any,
	danceWarmupService: any?,
	animationLoader: any?,
})
	local self = setmetatable({}, SyncController) :: any
	self.store = deps.store
	self.config = deps.config.Sync
	self.favoritesConfig = deps.config.Favorites
	self.logger = deps.logger
	self.danceWarmupService = deps.danceWarmupService
	self.animationLoader = deps.animationLoader
	self.connections = {} :: { RBXScriptConnection }
	self._loadingLocalTracks = {} :: { AnimationTrack }
	self._loadingCleanupGeneration = 0
	self._hasLoadingLocalDance = false
	self._predictiveLocalTracks = {} :: { AnimationTrack }
	self._predictiveGeneration = 0
	self._knownDanceAnimationIds = {} :: { [string]: boolean }
	self._knownDanceAnimationNames = {} :: { [string]: boolean }

	if self.animationLoader then
		local function indexAnimations(list: { Animation })
			for _, animation in ipairs(list) do
				self._knownDanceAnimationNames[animation.Name] = true
				if animation.AnimationId ~= "" then
					self._knownDanceAnimationIds[animation.AnimationId] = true
				end
			end
		end

		indexAnimations(self.animationLoader.getAnimationsByCategory("Dance"))
		indexAnimations(self.animationLoader.getAnimationsByCategory("Pose"))
	end

	local syncRemotes = ReplicatedStorage:WaitForChild(self.config.REMOTE_FOLDER, 15)
	if not syncRemotes then
		self.logger:error("SyncRemotes folder not found, sync features disabled")
		return self
	end

	self.animationStartRE = syncRemotes:WaitForChild(self.config.REMOTE_ANIMATION_START, 15) :: RemoteEvent
	self.startSyncRE = syncRemotes:WaitForChild(self.config.REMOTE_START_SYNC, 15) :: RemoteEvent
	self.changeSpeedRE = syncRemotes:WaitForChild(self.config.REMOTE_CHANGE_SPEED, 15) :: RemoteEvent
	self.updateFavoritesRE = syncRemotes:WaitForChild(self.config.REMOTE_UPDATE_FAVORITES, 15) :: RemoteEvent
	self.syncFavoritesRE = syncRemotes:WaitForChild(self.config.REMOTE_SYNC_FAVORITES, 15) :: RemoteEvent
	self.notificationRemote = syncRemotes:WaitForChild(self.config.REMOTE_NOTIFICATION, 15) :: RemoteEvent

	if
		not self.animationStartRE
		or not self.startSyncRE
		or not self.changeSpeedRE
		or not self.updateFavoritesRE
		or not self.notificationRemote
	then
		self.logger:error("SyncRemotes incomplete, sync features disabled", {
			hasAnimStart = self.animationStartRE ~= nil,
			hasStartSync = self.startSyncRE ~= nil,
			hasChangeSpeed = self.changeSpeedRE ~= nil,
			hasUpdateFav = self.updateFavoritesRE ~= nil,
			hasNotif = self.notificationRemote ~= nil,
		})
		return self
	end

	table.insert(
		self.connections,
		self.notificationRemote.OnClientEvent:Connect(function(payload: any)
			self:_handleNotification(payload)
		end)
	)

	if self.syncFavoritesRE then
		table.insert(
			self.connections,
			self.syncFavoritesRE.OnClientEvent:Connect(function(jsonData: any)
				self:_applyFavoritesJson(jsonData)
			end)
		)
	end

	return self
end

function SyncController:_applyFavoritesJson(jsonData: any)
	if type(jsonData) ~= "string" or jsonData == "" then
		return
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(jsonData)
	end)
	if ok and type(decoded) == "table" then
		self.store:set({ favoritedAnims = decoded })
	end
end

function SyncController:_fireAnimationAction(animation: Animation, shouldPlay: boolean)
	if not self.animationStartRE then
		return
	end
	-- intent kept as "play" for server-side compat; restart path was removed.
	self.animationStartRE:FireServer(animation, shouldPlay, self.store:get().currentSpeed, "play")
end

function SyncController:_stopPredictiveLocal()
	self._predictiveGeneration += 1
	for _, track in ipairs(self._predictiveLocalTracks) do
		pcall(function()
			track:Stop(0)
			track:Destroy()
		end)
	end
	table.clear(self._predictiveLocalTracks)
end

--- Preload (if needed) + Play locally for instant self feedback. Server still
--- owns replication for others; stop predictive when anim_result arrives.
function SyncController:_startPredictiveLocal(animation: Animation)
	self:_stopPredictiveLocal()
	local generation = self._predictiveGeneration
	local animationName = animation.Name

	task.spawn(function()
		local warmed = false
		if self.danceWarmupService and type(self.danceWarmupService.warmAnimation) == "function" then
			warmed = self.danceWarmupService:warmAnimation(animation) == true
		else
			local ok = pcall(function()
				ContentProvider:PreloadAsync({ animation })
			end)
			warmed = ok
		end

		if generation ~= self._predictiveGeneration then
			return
		end
		if self.store:get().visualAnim ~= animationName then
			return
		end

		local animator = self:_getLocalAnimator()
		if not animator then
			return
		end

		local ok, trackOrErr = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if not ok or not trackOrErr then
			self.logger:warn("Predictive local LoadAnimation failed", {
				animation = animationName,
				warmed = warmed,
				error = tostring(trackOrErr),
			})
			return
		end
		if generation ~= self._predictiveGeneration then
			pcall(function()
				trackOrErr:Destroy()
			end)
			return
		end

		local track = trackOrErr :: AnimationTrack
		track.Looped = true
		track.Priority = self.config.ANIM_PRIORITY
		track:Play(self.config.FADE_IN or 0.14)
		local speed = tonumber(self.store:get().currentSpeed) or 1
		pcall(function()
			track:AdjustSpeed(speed)
		end)
		table.insert(self._predictiveLocalTracks, track)
	end)
end

function SyncController:_queuePendingAnimation(animation: Animation)
	-- Kept for compatibility; play path no longer gates on warmup.
	self.store:set({
		isDancePreparing = true,
		isPanelOpen = true,
		visualAnim = animation.Name,
		pendingAnimationName = animation.Name,
		pendingAnimationObject = animation,
	})
end

function SyncController:_handleNotification(payload: any)
	if type(payload) ~= "table" then
		return
	end

	local notifType = payload.type
	if notifType == "sync_success" or notifType == "transfer_success" then
		self:_stopPredictiveLocal()
		local currentAnim = if type(payload.currentAnim) == "string" then payload.currentAnim else ""
		self.store:set({
			isSyncing = true,
			leaderName = payload.leaderName,
			leaderDisplay = payload.leaderDisplay or payload.leaderName,
			currentAnim = currentAnim,
			visualAnim = currentAnim,
			syncTargetUserId = payload.targetUserId,
		})
		local leaderLabel = payload.leaderDisplay or payload.leaderName or "target"
		local waitingForDance = currentAnim == ""
		local message = if notifType == "transfer_success"
			then "Lead transferred to " .. tostring(leaderLabel) .. "."
			elseif waitingForDance
			then "Synced to " .. tostring(leaderLabel) .. ". You'll match their dance when they start."
			else "Synced with " .. tostring(leaderLabel) .. "."
		local dedupePrefix = if notifType == "transfer_success" then "transfer-" else "sync-started-"
		NotifService.show({
			message = message,
			notifType = "SUCCESS",
			domain = "sync",
			title = "Dance sync",
			dedupeKey = dedupePrefix .. tostring(payload.targetUserId or leaderLabel),
		})
	elseif notifType == "unsync_success" then
		self.store:set({
			isSyncing = false,
			leaderName = nil,
			leaderDisplay = nil,
			visualAnim = self.store:get().currentAnim,
			syncTargetUserId = nil,
		})
		NotifService.show({
			message = "Dance sync stopped.",
			notifType = "INFO",
			domain = "sync",
			title = "Dance sync",
			dedupeKey = "sync-stopped",
		})
	elseif notifType == "leader_left" then
		local currentState = self.store:get()
		if not currentState.isSyncing and not currentState.leaderName then
			return
		end
		local leaderLabel = currentState.leaderDisplay
			or currentState.leaderName
			or (if type(payload.leaderName) == "string" then payload.leaderName else "your leader")
		self.store:set({
			isSyncing = false,
			leaderName = nil,
			leaderDisplay = nil,
			visualAnim = self.store:get().currentAnim,
			syncTargetUserId = nil,
			pendingAnimationName = nil,
			pendingAnimationObject = nil,
			isDancePreparing = false,
		})
		NotifService.show({
			message = tostring(leaderLabel) .. " left. Dance sync stopped.",
			notifType = "INFO",
			domain = "sync",
			title = "Dance sync",
			dedupeKey = "sync-leader-left-" .. tostring(payload.leaderName or leaderLabel),
		})
	elseif notifType == "leader_not_dancing" then
		self.logger:warn("Target is not dancing")
		NotifService.show({
			message = "Target is not dancing.",
			notifType = "WARNING",
			domain = "sync",
			title = "Sync blocked",
		})
	elseif notifType == "self_target" then
		self.logger:warn("Cannot sync to self")
		NotifService.show({
			message = "You cannot sync to yourself.",
			notifType = "WARNING",
			domain = "sync",
			title = "Sync blocked",
		})
	elseif notifType == "circular_blocked" or notifType == "leader_blocked" then
		self.logger:warn("Sync chain blocked", { reason = notifType })
		NotifService.show({
			message = "Sync blocked to avoid a loop.",
			notifType = "WARNING",
			domain = "sync",
			title = "Sync blocked",
		})
	elseif notifType == "rate_limited" then
		self.logger:warn("Sync request rate limited")
		NotifService.show({
			message = "Too fast. Wait a moment.",
			notifType = "WARNING",
			domain = "sync",
			title = "Sync rate limit",
		})
	elseif notifType == "anim_result" then
		local result = payload.result
		local animName = payload.animationName
		if result == "playing" then
			local state = self.store:get()
			-- Ignore stale ack if user already selected a different dance.
			if type(animName) == "string"
				and type(state.visualAnim) == "string"
				and state.visualAnim ~= ""
				and state.visualAnim ~= animName
			then
				return
			end
			-- Server track is authoritative for replication; drop predictive local
			-- to avoid double-weight on self.
			self:_stopPredictiveLocal()
			self.store:set({
				currentAnim = animName,
				visualAnim = animName,
				isPanelOpen = true,
				isDancePreparing = false,
				pendingAnimationName = nil,
				pendingAnimationObject = nil,
			})
		elseif result == "stopped" then
			self:_stopPredictiveLocal()
			self.store:set({
				currentAnim = "",
				visualAnim = "",
				isDancePreparing = false,
				pendingAnimationName = "",
				pendingAnimationObject = nil,
			})
		else
			-- error / rate_limited — revert preparing state
			self:_stopPredictiveLocal()
			self.store:set({
				isDancePreparing = false,
				visualAnim = self.store:get().currentAnim,
			})
		end
	end
end

function SyncController:getCurrentAnimName()
	return self.store:get().currentAnim
end

function SyncController:getVisualAnimName()
	return self.store:get().visualAnim
end

function SyncController:togglePanel()
	self.store:set({ isPanelOpen = not self.store:get().isPanelOpen })
end

function SyncController:openPanel()
	self.store:set({ isPanelOpen = true })
end

function SyncController:closePanel()
	self.store:set({ isPanelOpen = false })
end

function SyncController:_getLocalAnimator(): Animator?
	local localPlayer = Players.LocalPlayer
	local character = localPlayer and localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid:FindFirstChildOfClass("Animator") or nil
end

function SyncController:_isKnownDanceTrack(track: AnimationTrack): boolean
	local animation = track.Animation
	if animation then
		if animation.AnimationId ~= "" and self._knownDanceAnimationIds[animation.AnimationId] then
			return true
		end
		if self._knownDanceAnimationNames[animation.Name] then
			return true
		end
	end

	return self._knownDanceAnimationNames[track.Name] == true
end

function SyncController:_clearTrackedLoadingDances()
	for _, track in ipairs(self._loadingLocalTracks) do
		pcall(function()
			track:Stop(0)
			track:Destroy()
		end)
	end
	table.clear(self._loadingLocalTracks)
end

function SyncController:stopLoadingLocalDances()
	if not self._hasLoadingLocalDance and #self._loadingLocalTracks == 0 then
		return
	end

	self._loadingCleanupGeneration += 1
	self:_clearTrackedLoadingDances()
	self._hasLoadingLocalDance = false

	local animator = self:_getLocalAnimator()
	if animator then
		local ok, tracks = pcall(function()
			return animator:GetPlayingAnimationTracks()
		end)
		if ok and tracks then
			for _, track in ipairs(tracks) do
				if self:_isKnownDanceTrack(track) then
					pcall(function()
						track:Stop(0)
					end)
				end
			end
		end
	end

	self.store:set({
		currentAnim = "",
		visualAnim = "",
		isDancePreparing = false,
		pendingAnimationName = nil,
		pendingAnimationObject = nil,
	})
end

function SyncController:_watchLoadingLocalDanceCleanup()
	self._loadingCleanupGeneration += 1
	local generation = self._loadingCleanupGeneration

	task.spawn(function()
		while generation == self._loadingCleanupGeneration do
			local loadingUI = LoadingScreenUI.get()
			if not loadingUI or loadingUI:isBootFinished() or not loadingUI:isBlockingGameplay() then
				self:stopLoadingLocalDances()
				return
			end
			task.wait(0.1)
		end
	end)
end

function SyncController:_playLocalOnly(animation: Animation)
	self:_clearTrackedLoadingDances()

	local animator = self:_getLocalAnimator()
	if not animator then
		return
	end
	local track = animator:LoadAnimation(animation)
	track.Looped = true
	track.Priority = self.config.ANIM_PRIORITY
	track:Play(self.config.FADE_IN or 0.14)
	table.insert(self._loadingLocalTracks, track)
	self._hasLoadingLocalDance = true
	self:_watchLoadingLocalDanceCleanup()
	self.store:set({
		currentAnim = animation.Name,
		visualAnim = animation.Name,
		isDancePreparing = false,
	})
end

function SyncController:onEmoteSelected(animation: Animation)
	if self.store:get().isInputLocked then
		return
	end

	-- During loading screen: play locally only, don't replicate to other clients
	local loadingUI = LoadingScreenUI.get()
	if loadingUI and loadingUI:isBlockingGameplay() then
		if loadingUI:isBootFinished() then
			self:stopLoadingLocalDances()
		else
			self:_playLocalOnly(animation)
		end
		return
	end
	self:stopLoadingLocalDances()

	local state = self.store:get()
	local animationName = animation.Name

	-- Toggle off when same animation is the active one (and not currently
	-- mid-prepare or syncing to someone else).
	local isSameActive = state.currentAnim == animationName
		and not state.isDancePreparing
		and not state.isSyncing
	if isSameActive then
		self:_stopPredictiveLocal()
		self.store:set({
			currentAnim = "",
			visualAnim = "",
			isDancePreparing = false,
			pendingAnimationName = nil,
			pendingAnimationObject = nil,
		})
		self:_fireAnimationAction(animation, false)
		return
	end

	-- Optimistic UI + FireServer immediately (do not gate on catalog warmup).
	self.store:set({
		visualAnim = animationName,
		isDancePreparing = true,
		isPanelOpen = true,
		pendingAnimationName = animationName,
		pendingAnimationObject = animation,
	})
	self:_fireAnimationAction(animation, true)
	self:_startPredictiveLocal(animation)
end

-- Apply speed locally for instant slider responsiveness; server still gets
-- the throttled fire to propagate to followers (and to update its leader
-- speed map for sync joiners).
local function applyLocalAnimationSpeed(speed: number)
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return
	end
	local character = localPlayer.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	-- Only adjust dance tracks (Action4 priority), not system animations (idle/walk/run)
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if track.Looped and track.IsPlaying and track.Priority == Enum.AnimationPriority.Action4 then
			pcall(function()
				track:AdjustSpeed(speed)
			end)
		end
	end
end

function SyncController:onSpeedChanged(speed: number)
	self.store:set({ currentSpeed = speed })
	applyLocalAnimationSpeed(speed)

	-- Throttle network fire (max 1× per 100ms) and guarantee final value.
	self._lastSpeedSent = self._lastSpeedSent or 0
	self._pendingSpeedValue = speed
	local now = os.clock()
	if now - self._lastSpeedSent >= 0.1 then
		self._lastSpeedSent = now
		self.changeSpeedRE:FireServer(speed)
	elseif not self._pendingSpeedDispatch then
		self._pendingSpeedDispatch = true
		task.delay(0.1, function()
			self._pendingSpeedDispatch = false
			self._lastSpeedSent = os.clock()
			if self._pendingSpeedValue then
				self.changeSpeedRE:FireServer(self._pendingSpeedValue)
			end
		end)
	end
end

function SyncController:onFavoriteToggled(animationName: string)
	local favorites = table.clone(self.store:get().favoritedAnims)
	local isFavorited = not favorites[animationName]
	favorites[animationName] = isFavorited
	self.store:set({ favoritedAnims = favorites })

	NotifService.show({
		message = if isFavorited
			then string.format("%s added to favorites.", animationName)
			else string.format("%s removed from favorites.", animationName),
		notifType = if isFavorited then "SUCCESS" else "INFO",
		domain = "sync",
		title = "Dance favorites",
		dedupeKey = "dance-favorite-" .. animationName .. "-" .. (if isFavorited then "add" else "remove"),
	})

	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(favorites)
	end)
	if ok then
		self.updateFavoritesRE:FireServer({
			requestId = HttpService:GenerateGUID(false),
			data = encoded,
		})
	end
end

function SyncController:onUnsync()
	self:_stopPredictiveLocal()
	self.startSyncRE:FireServer(nil, false)
	self.store:set({
		isSyncing = false,
		leaderName = nil,
		leaderDisplay = nil,
		currentAnim = nil,
		visualAnim = nil,
		pendingAnimationName = nil,
		pendingAnimationObject = nil,
		syncTargetUserId = nil,
	})
end

function SyncController:requestSyncByUserId(targetUserId: number): boolean
	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer or targetPlayer == Players.LocalPlayer then
		return false
	end
	self.store:set({ syncTargetUserId = targetUserId })
	self.startSyncRE:FireServer(targetPlayer, true)
	return true
end

-- Lead dancer transfer kepemimpinan ke target. Server bakal pindahin
-- seluruh subtree caller (caller + transitive followers) ke target's
-- ultimate leader. Kalau caller bukan leader (gak punya followers), server
-- otomatis fallback ke normal sync.
function SyncController:requestTransferLeadByUserId(targetUserId: number): boolean
	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer or targetPlayer == Players.LocalPlayer then
		return false
	end
	self.store:set({ syncTargetUserId = targetUserId })
	self.startSyncRE:FireServer(targetPlayer, true, true)
	return true
end

function SyncController:destroy()
	self:_stopPredictiveLocal()
	self:stopLoadingLocalDances()
	for _, connection in ipairs(self.connections or {}) do
		connection:Disconnect()
	end
	self.connections = {}
	self._waitingForWarmup = false
end

return SyncController
