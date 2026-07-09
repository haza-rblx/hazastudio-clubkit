--!strict
-- StarterPlayer/StarterPlayerScripts/Client/Controllers/AvatarContextController.lua

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")

local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local LoadingScreenUI = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.UI.LoadingScreenUI)

type AvatarContextRequest = Types.AvatarContextRequest
type AvatarContextResponse = Types.AvatarContextResponse
type AvatarContextPayload = Types.AvatarContextPayload
type AvatarContextProfileUpdatedPayload = Types.AvatarContextProfileUpdatedPayload
type AvatarContextUpdatedPayload = Types.AvatarContextUpdatedPayload
type AvatarContextLikeRequest = Types.AvatarContextLikeRequest
type AvatarContextLikeResult = Types.AvatarContextLikeResult
type ILogger = Types.ILogger

local MUSIC_QUEUE_CONFIRMATION_ATTRIBUTE = "MusicPlayerQueueConfirmationOpen"

local function createAvatarContextController(deps: {
	logger: ILogger,
	ui: any,
	getCachedOverheadPayload: ((userId: number) -> any)?,
})
	local log = deps.logger
	local ui = deps.ui
	local getCachedOverheadPayload = deps.getCachedOverheadPayload
	local HOVER_SAMPLE_INTERVAL = 1 / 30

	local isOpen = false
	local isLoading = false
	local panelReady = false
	local currentTargetUserId: number? = nil
	local pendingRequestId: string? = nil
	local likePendingRequestId: string? = nil
	local currentPayload: AvatarContextPayload? = nil
	local instantPaintApplied = false

	-- Client-side cooldown per target untuk mencegah spam FireServer
	-- yang cuma akan kena rate limit di server. Cooldown harus lebih pendek
	-- dari window server (REQUEST_RATE_WINDOW=10s, max=5) -- 1.2s aman
	-- untuk pola normal interaksi player.
	local REQUEST_COOLDOWN = 1.2
	local lastRequestAt: { [number]: number } = {}

	-- Client-side friend check cache (reduces async calls)
	local friendCheckCache: { [number]: { result: boolean, expiry: number } } = {}
	local FRIEND_CHECK_CACHE_TTL = 60

	local controller = {} :: any
	controller._connections = {} :: { RBXScriptConnection }

	local function trackConnection(conn: RBXScriptConnection): RBXScriptConnection
		table.insert(controller._connections, conn)
		return conn
	end

	-- Helper to check if local player is friends with target (client-side)
	local function checkIsFriend(targetUserId: number): boolean
		local localPlayer = Players.LocalPlayer
		if not localPlayer or targetUserId == localPlayer.UserId then
			return false
		end

		local cached = friendCheckCache[targetUserId]
		if cached and os.clock() < cached.expiry then
			return cached.result
		end

		local ok, isFriend = pcall(function()
			return localPlayer:IsFriendsWith(targetUserId)
		end)

		local result = ok and isFriend == true
		friendCheckCache[targetUserId] = {
			result = result,
			expiry = os.clock() + FRIEND_CHECK_CACHE_TTL,
		}
		return result
	end

	-- Build instant payload from overhead cache for fast paint
	local function buildInstantPayload(targetUserId: number): AvatarContextPayload?
		if not getCachedOverheadPayload then
			return nil
		end

		local overhead = getCachedOverheadPayload(targetUserId)
		if not overhead or type(overhead) ~= "table" then
			return nil
		end

		local targetPlayer = Players:GetPlayerByUserId(targetUserId)
		local localPlayer = Players.LocalPlayer

		local isFriend = checkIsFriend(targetUserId)
		local canSendFriendRequest = not isFriend and targetUserId ~= localPlayer.UserId

		local payload: AvatarContextPayload = {
			userId = targetUserId,
			displayName = overhead.displayName or (targetPlayer and targetPlayer.DisplayName) or "Player",
			username = targetPlayer and targetPlayer.Name or "Unknown",
			role = overhead.role or "Guest",
			effectiveMembership = overhead.effectiveMembership or "Guest",
			visibleBadges = overhead.visibleBadges or {},
			streakDays = overhead.streakDays or 0,
			couplePartner = overhead.couplePartner,
			communityId = overhead.communityId,
			communityName = overhead.communityName,
			communityLogo = overhead.communityLogo,
			relationshipText = nil,
			bio = nil,
			statusText = nil,
			followersCount = nil,
			connectionsCount = nil,
			likesCount = overhead.likesCount or 0,
			viewerHasLiked = false,
			canSendGift = true,
			canSendFriendRequest = true,
			canInvestigateAvatar = true,
			canLike = true,
			canCarry = true,
			canSyncDance = true,
		}

		return payload
	end

	function controller:init()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local remoteRequest = remotes:WaitForChild(Config.AvatarContext.REMOTE_REQUEST) :: RemoteEvent
		local remoteResponse = remotes:WaitForChild(Config.AvatarContext.REMOTE_RESPONSE) :: RemoteEvent
		local profileUpdatedRemote = remotes:WaitForChild(Config.AvatarContext.REMOTE_PROFILE_UPDATED) :: RemoteEvent
		local updatedRemote = remotes:WaitForChild(Config.AvatarContext.REMOTE_UPDATED) :: RemoteEvent
		local closeRemote = remotes:WaitForChild(Config.AvatarContext.REMOTE_CLOSE) :: RemoteEvent
		local likeRequestRemote = remotes:WaitForChild(Config.AvatarContext.REMOTE_LIKE_REQUEST) :: RemoteEvent
		local likeResultRemote = remotes:WaitForChild(Config.AvatarContext.REMOTE_LIKE_RESULT) :: RemoteEvent

		controller._remoteRequest = remoteRequest
		controller._remoteResponse = remoteResponse
		controller._closeRemote = closeRemote
		controller._likeRequestRemote = likeRequestRemote

		-- Listen for responses
		trackConnection(remoteResponse.OnClientEvent:Connect(function(response: AvatarContextResponse)
			controller:_handleResponse(response)
		end))

		trackConnection(profileUpdatedRemote.OnClientEvent:Connect(function(payload: AvatarContextProfileUpdatedPayload)
			controller:_handleProfileUpdated(payload)
		end))

		trackConnection(updatedRemote.OnClientEvent:Connect(function(payload: AvatarContextUpdatedPayload)
			controller:_handleContextUpdated(payload)
		end))

		trackConnection(likeResultRemote.OnClientEvent:Connect(function(payload: AvatarContextLikeResult)
			controller:_handleLikeResult(payload)
		end))

		if type(ui.setLikeCallback) == "function" then
			ui:setLikeCallback(function(targetUserId: number)
				controller:requestLikeToggle(targetUserId)
			end)
		end

		-- Detect avatar clicks
		controller:_setupClickDetection()

		-- Auto-close when target leaves
		controller:_setupTargetLeaveDetection()

		log:info("AvatarContextController initialized")
	end

	function controller:_setupTargetLeaveDetection()
		trackConnection(Players.PlayerRemoving:Connect(function(player: Player)
			if currentTargetUserId == player.UserId then
				log:debug("Target left, closing panel", { userId = player.UserId })
				controller:closePanel()
			end
		end))
	end

	function controller:destroy()
		for _, conn in ipairs(controller._connections) do
			conn:Disconnect()
		end
		table.clear(controller._connections)
	end

	function controller:_setupClickDetection()
		local localPlayer = Players.LocalPlayer

		log:info("Click detection setup complete")

		-- Track current highlighted character
		local currentHighlight: Highlight? = nil
		local lastHoveredCharacter: Model? = nil
		local lastHoverSampleAt = 0
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Include

		local trackedCharacters = {} :: { [number]: Model }
		local characterFilterList = {} :: { Instance }
		local nonLocalCharacterFilterList = {} :: { Instance }

		local function rebuildRaycastFilterList()
			local nextFilterList = {} :: { Instance }
			local nextNonLocalFilterList = {} :: { Instance }
			for userId, character in pairs(trackedCharacters) do
				table.insert(nextFilterList, character)
				if userId ~= localPlayer.UserId then
					table.insert(nextNonLocalFilterList, character)
				end
			end
			characterFilterList = nextFilterList
			nonLocalCharacterFilterList = nextNonLocalFilterList
			raycastParams.FilterDescendantsInstances = characterFilterList
		end

		local function setTrackedCharacter(player: Player, character: Model?)
			if character and character.Parent then
				trackedCharacters[player.UserId] = character
			else
				trackedCharacters[player.UserId] = nil
			end
			rebuildRaycastFilterList()
		end

		local clearHighlight: () -> ()

		local function trackPlayer(player: Player)
			if player.Character then
				setTrackedCharacter(player, player.Character)
			end

			player.CharacterAdded:Connect(function(character)
				setTrackedCharacter(player, character)
				if player == localPlayer then
					clearHighlight()
				end
			end)

			player.CharacterRemoving:Connect(function(character)
				if trackedCharacters[player.UserId] == character then
					setTrackedCharacter(player, nil)
				end
				if player == localPlayer then
					clearHighlight()
				end
			end)
		end

		clearHighlight = function()
			if currentHighlight then
				currentHighlight:Destroy()
				currentHighlight = nil
			end
			lastHoveredCharacter = nil
		end

		local function isLoadingOverlayBlocking(): boolean
			local loadingUi = LoadingScreenUI.get()
			return loadingUi ~= nil and loadingUi:isBlockingGameplay()
		end

		local function isQueueConfirmationBlocking(): boolean
			return localPlayer:GetAttribute(MUSIC_QUEUE_CONFIRMATION_ATTRIBUTE) == true
		end

		local function clearQueueBlockedInteraction()
			clearHighlight()
			if isOpen then
				controller:closePanel()
			end
		end

		localPlayer:GetAttributeChangedSignal(MUSIC_QUEUE_CONFIRMATION_ATTRIBUTE):Connect(function()
			if isQueueConfirmationBlocking() then
				clearQueueBlockedInteraction()
			end
		end)
		if isQueueConfirmationBlocking() then
			clearQueueBlockedInteraction()
		end

		for _, player in ipairs(Players:GetPlayers()) do
			trackPlayer(player)
		end

		Players.PlayerAdded:Connect(function(player)
			trackPlayer(player)
		end)

		Players.PlayerRemoving:Connect(function(player)
			local removedCharacter = trackedCharacters[player.UserId]
			trackedCharacters[player.UserId] = nil
			rebuildRaycastFilterList()
			if currentTargetUserId == player.UserId or lastHoveredCharacter == removedCharacter then
				clearHighlight()
			end
		end)

		local function getInputScreenPosition(input: InputObject?): Vector2
			if input and input.UserInputType == Enum.UserInputType.Touch then
				return Vector2.new(input.Position.X, input.Position.Y)
			end
			return UserInputService:GetMouseLocation()
		end

		local function isGuiInteractionBlocker(object: GuiObject): boolean
			if object:IsA("GuiButton") or object:IsA("TextBox") then
				return true
			end
			if object:IsA("ScrollingFrame") then
				return object.Active or object.ScrollingEnabled
			end
			if object.BackgroundTransparency < 1 then
				return true
			end
			if not (object.Active or object.Selectable) then
				return false
			end

			local lowerName = string.lower(object.Name)
			if
				string.find(lowerName, "backdrop", 1, true)
				or string.find(lowerName, "shield", 1, true)
				or string.find(lowerName, "blocker", 1, true)
				or string.find(lowerName, "modal", 1, true)
				or string.find(lowerName, "popup", 1, true)
				or string.find(lowerName, "panel", 1, true)
				or string.find(lowerName, "menu", 1, true)
			then
				return true
			end

			return false
		end

		local function isDescendantOfAvatarContextMenu(instance: Instance?, playerGui: PlayerGui): boolean
			local ancestor = instance
			while ancestor and ancestor ~= playerGui do
				if ancestor.Name == "AvatarContextMenu" then
					return true
				end
				ancestor = ancestor.Parent
			end
			return false
		end

		local function getPointerGuiHit(screenPosition: Vector2): (boolean, boolean)
			local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
			if not playerGui then
				return false, false
			end

			local guiObjects = playerGui:GetGuiObjectsAtPosition(screenPosition.X, screenPosition.Y)
			-- Pass 1: any hit inside ACM counts as ACM click (buttons, scroll content, etc.)
			for _, object in ipairs(guiObjects) do
				if object.Visible and isDescendantOfAvatarContextMenu(object, playerGui) then
					return true, true
				end
			end

			-- Pass 2: other GUI blockers (topbar, donation panel, etc.)
			for _, object in ipairs(guiObjects) do
				if not object.Visible then
					continue
				end
				local ancestor = object
				while ancestor and ancestor ~= playerGui do
					if ancestor:IsA("GuiObject") and isGuiInteractionBlocker(ancestor) then
						return true, false
					end
					ancestor = ancestor.Parent
				end
			end

			return false, false
		end

		local function raycastFromPointer(screenPosition: Vector2): BasePart?
			local camera = workspace.CurrentCamera
			if not camera then
				return nil
			end
			local unitRay = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)

			if #nonLocalCharacterFilterList > 0 then
				raycastParams.FilterDescendantsInstances = nonLocalCharacterFilterList
				local nonLocalResult = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, raycastParams)
				if nonLocalResult then
					return nonLocalResult.Instance
				end
			end

			if #characterFilterList == 0 then
				return nil
			end

			raycastParams.FilterDescendantsInstances = characterFilterList
			local raycastResult = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, raycastParams)

			if raycastResult then
				return raycastResult.Instance
			end

			return nil
		end

		local function getCharacterFromPart(part: BasePart?): (Model?, Player?)
			if not part then
				return nil, nil
			end

			local character = part:FindFirstAncestorOfClass("Model")
			if not character and part:IsA("Model") then
				character = part
			end

			if not character or not character:FindFirstChildOfClass("Humanoid") then
				return nil, nil
			end

			local player = Players:GetPlayerFromCharacter(character)
			if not player then
				return nil, nil
			end

			return character, player
		end

		-- Mouse move tracking (no visual highlight; click detection only).
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseMovement then
				return
			end
			if isLoadingOverlayBlocking() or isQueueConfirmationBlocking() then
				clearHighlight()
				return
			end
			local now = os.clock()
			if now - lastHoverSampleAt < HOVER_SAMPLE_INTERVAL then
				return
			end
			lastHoverSampleAt = now

			local hitPart = raycastFromPointer(getInputScreenPosition(input))
			local character, player = getCharacterFromPart(hitPart)

			if not character or not player then
				lastHoveredCharacter = nil
				return
			end

			lastHoveredCharacter = character
		end)

		local pendingPanelPointerInput: InputObject? = nil

		local function isPointerInsideAcmPanel(screenPosition: Vector2): boolean
			if type(ui.isPointerInside) == "function" and ui:isPointerInside(screenPosition) then
				return true
			end
			local _, pointerOverAvatarContext = getPointerGuiHit(screenPosition)
			return pointerOverAvatarContext
		end

		local function handlePanelPointerRelease(input: InputObject)
			if not isOpen then
				return
			end
			if not panelReady or isLoading then
				return
			end

			local screenPosition = getInputScreenPosition(input)
			if isPointerInsideAcmPanel(screenPosition) then
				return
			end

			local pointerOverGui, _pointerOverAcm = getPointerGuiHit(screenPosition)
			if pointerOverGui and not _pointerOverAcm then
				controller:closePanel()
				return
			end

			local hitPart = raycastFromPointer(screenPosition)
			local character, targetPlayer = getCharacterFromPart(hitPart)
			if character and targetPlayer then
				log:info("Opening panel for player", { player = targetPlayer.Name, userId = targetPlayer.UserId })
				controller:openPanel(targetPlayer.UserId)
				return
			end

			log:debug("ACM outside click close", { targetUserId = currentTargetUserId })
			controller:closePanel()
		end

		-- Mouse click (open panel when closed)
		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end
			if isLoadingOverlayBlocking() then
				clearHighlight()
				return
			end
			if isQueueConfirmationBlocking() then
				clearQueueBlockedInteraction()
				return
			end

			if isOpen then
				-- Roblox GUI buttons (Investigate Avatar, Like, etc.) set gameProcessed.
				-- Do not run outside-click logic on mousedown or Activated never fires.
				if gameProcessed then
					return
				end

				local screenPosition = getInputScreenPosition(input)
				if isPointerInsideAcmPanel(screenPosition) then
					return
				end

				pendingPanelPointerInput = input
				return
			end

			if gameProcessed then
				return
			end

			local screenPosition = getInputScreenPosition(input)
			local pointerOverGui, _ = getPointerGuiHit(screenPosition)
			if pointerOverGui then
				return
			end

			local hitPart = raycastFromPointer(screenPosition)
			log:debug("Mouse clicked", { hitPart = hitPart and hitPart.Name or "nil" })

			local character, targetPlayer = getCharacterFromPart(hitPart)
			if not character or not targetPlayer then
				log:debug("No character found from raycast")
				return
			end

			log:info("Opening panel for player", { player = targetPlayer.Name, userId = targetPlayer.UserId })
			controller:openPanel(targetPlayer.UserId)
		end)

		UserInputService.InputEnded:Connect(function(input)
			if pendingPanelPointerInput ~= input then
				return
			end
			pendingPanelPointerInput = nil
			handlePanelPointerRelease(input)
		end)
	end

	function controller:openPanel(targetUserId: number)
		log:info("openPanel called", { targetUserId = targetUserId })
		if Players.LocalPlayer:GetAttribute(MUSIC_QUEUE_CONFIRMATION_ATTRIBUTE) == true then
			return
		end

		if isOpen and currentTargetUserId == targetUserId then
			log:debug("Same target, toggling close")
			controller:closePanel()
			return
		end

		local now = os.clock()
		local lastAt = lastRequestAt[targetUserId]
		if lastAt and (now - lastAt) < REQUEST_COOLDOWN then
			log:debug("openPanel cooldown active", {
				targetUserId = targetUserId,
				remaining = REQUEST_COOLDOWN - (now - lastAt),
			})
			return
		end
		lastRequestAt[targetUserId] = now

		if isOpen and currentTargetUserId ~= targetUserId then
			log:debug("Different target, closing old")
			controller:_notifyContextClosed()
			ui:close()
		end

		isOpen = true
		isLoading = true
		currentTargetUserId = targetUserId
		currentPayload = nil
		likePendingRequestId = nil
		instantPaintApplied = false

		log:debug("Opening UI (no loading state; data flows async)")

		panelReady = false
		ui:setAfterOpenCallback(function()
			panelReady = true
		end)
		ui:open()

		-- ORKESTRASI PARALEL (tidak ada yang block yang lain):
		-- 1. Fire server request (1ms — no YIELD).
		-- 2. Instant paint dari cache overhead (text only, 1ms).
		-- 3. Show 3D avatar (pool hit = instant, miss = thumbnail instant + pool prewarm on-demand).
		-- Sebelumnya, setData() synchronous panggil currentViewport:load() yang yield
		-- CreateHumanoidModelFromUserId 2-8s, block FireServer, dan setLoading(true)
		-- hide mainContent (close button disabled). Sekarang semua paralel + non-blocking.
		local requestId = HttpService:GenerateGUID(false)
		pendingRequestId = requestId

		local request: AvatarContextRequest = {
			targetUserId = targetUserId,
			requestId = requestId,
		}

		log:info("Firing request to server", { requestId = requestId, targetUserId = targetUserId })
		controller._remoteRequest:FireServer(request)

		local instantPayload = buildInstantPayload(targetUserId)
		if instantPayload then
			log:debug("Instant paint from overhead cache", { targetUserId = targetUserId })
			currentPayload = instantPayload
			instantPaintApplied = true
			ui:setData(instantPayload)
		end
		-- 3D avatar: pool-or-thumbnail. Tidak yield di main thread.
		-- Panel tetap fully interactive (close button aktif) selama pool warm.
		ui:showAvatar(targetUserId)

		task.delay(Config.AvatarContext.REQUEST_TIMEOUT, function()
			if pendingRequestId == requestId then
				log:warn("Request timeout", { targetUserId = targetUserId })
				pendingRequestId = nil
				isLoading = false
				if instantPaintApplied and currentPayload then
					log:debug("Timeout but keeping instant paint data")
				elseif type(ui.setError) == "function" then
					ui:setError("Connection timed out. Click to retry.")
				else
					controller:closePanel()
				end
			end
		end)
	end

	function controller:closePanel()
		controller:_notifyContextClosed()
		isOpen = false
		panelReady = false
		isLoading = false
		currentTargetUserId = nil
		pendingRequestId = nil
		likePendingRequestId = nil
		currentPayload = nil
		instantPaintApplied = false
		ui:close()
	end

	function controller:_notifyContextClosed()
		if controller._closeRemote and (isOpen or currentTargetUserId ~= nil) then
			controller._closeRemote:FireServer()
		end
	end

	function controller:_handleResponse(response: AvatarContextResponse)
		log:info("Response received", {
			requestId = response.requestId,
			ok = response.ok,
			hadInstantPaint = instantPaintApplied,
		})

		if response.requestId ~= pendingRequestId then
			log:debug("Stale response ignored", { requestId = response.requestId })
			return
		end

		pendingRequestId = nil
		isLoading = false

		if not response.ok then
			log:warn("Request failed", { error = response.error })
			if instantPaintApplied and currentPayload then
				ui:setLoading(false)
				log:debug("Server failed but keeping instant paint")
				return
			end
			currentPayload = nil
			controller:closePanel()
			return
		end

		log:info("Reconciling with server data", {
			userId = response.payload.userId,
			wasInstantPaint = instantPaintApplied,
		})

		-- Guard: jangan downgrade visibleBadges dari instant paint ke empty.
		-- Race condition di server bisa menyebabkan cache hit dengan badge kosong
		-- padahal overhead cache client sudah punya data benar.
		local serverPayload = response.payload
		if instantPaintApplied and currentPayload then
			local serverBadges = serverPayload.visibleBadges
			local instantBadges = currentPayload.visibleBadges
			if
				type(instantBadges) == "table"
				and #instantBadges > 0
				and (type(serverBadges) ~= "table" or #serverBadges == 0)
			then
				log:warn("Server response has empty visibleBadges but instant paint has badges; preserving", {
					instantBadgeCount = #instantBadges,
					userId = serverPayload.userId,
				})
				serverPayload = table.clone(serverPayload)
				serverPayload.visibleBadges = instantBadges
			end
		end

		currentPayload = serverPayload
		instantPaintApplied = false
		ui:setData(serverPayload)
		ui:setLoading(false)
	end

	function controller:_handleProfileUpdated(payload: AvatarContextProfileUpdatedPayload)
		if not isOpen then
			return
		end
		if payload.targetUserId ~= currentTargetUserId then
			return
		end
		ui:updateBioStatus(payload.bio, payload.statusText)
	end

	function controller:_handleContextUpdated(payload: AvatarContextUpdatedPayload)
		if not isOpen or not currentTargetUserId then
			return
		end
		if payload.targetUserId ~= currentTargetUserId then
			return
		end
		currentPayload = payload.payload
		ui:setData(payload.payload)
	end

	function controller:_applyLikeResult(result: AvatarContextLikeResult)
		if not currentPayload then
			return
		end
		if currentPayload.userId ~= result.targetUserId then
			return
		end
		if result.likesCount == nil or result.viewerHasLiked == nil then
			return
		end

		local nextPayload = table.clone(currentPayload :: any) :: AvatarContextPayload
		nextPayload.likesCount = result.likesCount
		nextPayload.viewerHasLiked = result.viewerHasLiked
		currentPayload = nextPayload

		if type(ui.updateLikeState) == "function" then
			ui:updateLikeState(
				result.likesCount,
				result.viewerHasLiked,
				result.transition == "first_like" or result.transition == "reliked" or result.transition == "unliked"
			)
		else
			ui:setData(nextPayload)
		end
	end

	function controller:_handleLikeResult(result: AvatarContextLikeResult)
		if result.requestId ~= likePendingRequestId then
			return
		end
		likePendingRequestId = nil
		if type(ui.setLikePending) == "function" then
			ui:setLikePending(false)
		end
		if not result.ok then
			log:warn("Like request failed", {
				targetUserId = result.targetUserId,
				error = result.error,
			})
			return
		end
		controller:_applyLikeResult(result)
	end

	function controller:requestLikeToggle(targetUserId: number)
		if not isOpen or isLoading or likePendingRequestId ~= nil then
			return
		end
		if not currentPayload then
			return
		end
		if currentPayload.userId ~= targetUserId or not currentPayload.canLike then
			return
		end

		local requestId = HttpService:GenerateGUID(false)
		local request: AvatarContextLikeRequest = {
			requestId = requestId,
			targetUserId = targetUserId,
			action = if currentPayload.viewerHasLiked then "unlike" else "like",
		}

		likePendingRequestId = requestId
		if type(ui.setLikePending) == "function" then
			ui:setLikePending(true)
		end
		controller._likeRequestRemote:FireServer(request)
	end

	function controller:inspectAvatar(targetUserId: number)
		log:debug("InspectAvatar invoked", { targetUserId = targetUserId })

		pcall(function()
			if type(GuiService.SetInspectMenuEnabled) == "function" then
				GuiService:SetInspectMenuEnabled(true)
			end
		end)

		-- pcall succeeding does not mean CoreGui inspect actually opened.
		-- Wait for MenuOpened so we don't close ACM when inspect silently fails.
		local menuOpened = false
		local hasMenuOpenedSignal = GuiService.MenuOpened ~= nil
		local menuConn: RBXScriptConnection? = nil
		if hasMenuOpenedSignal then
			menuConn = GuiService.MenuOpened:Connect(function()
				menuOpened = true
			end)
		end

		local inspectErr: string? = nil
		local inspectInvoked = false
		local invokeOk, invokeResult = pcall(function()
			GuiService:InspectPlayerFromUserId(targetUserId)
			inspectInvoked = true
		end)
		if not invokeOk then
			inspectErr = tostring(invokeResult)
			local targetPlayer = Players:GetPlayerByUserId(targetUserId)
			local character = targetPlayer and targetPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and type(GuiService.InspectPlayerFromHumanoidDescription) == "function" then
				local descOk, descErr = pcall(function()
					GuiService:InspectPlayerFromHumanoidDescription(humanoid:GetAppliedDescription())
					inspectInvoked = true
				end)
				if descOk then
					invokeOk = true
				else
					inspectErr = tostring(descErr)
				end
			end
		end

		local deadline = os.clock() + 0.6
		while not menuOpened and os.clock() < deadline do
			task.wait()
		end
		if menuConn then
			menuConn:Disconnect()
			menuConn = nil
		end

		if invokeOk and inspectInvoked and menuOpened then
			if isOpen then
				controller:closePanel()
			end
			log:debug("InspectAvatar opened", { targetUserId = targetUserId, menuOpened = menuOpened })
		elseif invokeOk and inspectInvoked and not hasMenuOpenedSignal then
			-- Legacy clients without MenuOpened: keep previous behavior.
			if isOpen then
				controller:closePanel()
			end
			log:debug("InspectAvatar opened without MenuOpened signal", { targetUserId = targetUserId })
		else
			log:warn("Inspect avatar failed — ACM kept open", {
				targetUserId = targetUserId,
				menuOpened = menuOpened,
				inspectInvoked = inspectInvoked,
				error = inspectErr,
			})
		end
	end

	function controller:promptFriendRequest(targetUserId: number)
		if targetUserId == Players.LocalPlayer.UserId then
			return
		end

		local targetPlayer = Players:GetPlayerByUserId(targetUserId)
		if not targetPlayer then
			log:warn("Friend request target not found", { targetUserId = targetUserId })
			return
		end

		local ok, err = pcall(function()
			StarterGui:SetCore("PromptSendFriendRequest", targetPlayer)
		end)
		if not ok then
			log:warn("Friend request prompt failed", {
				targetUserId = targetUserId,
				error = tostring(err),
			})
		end
	end

	return controller
end

return createAvatarContextController
