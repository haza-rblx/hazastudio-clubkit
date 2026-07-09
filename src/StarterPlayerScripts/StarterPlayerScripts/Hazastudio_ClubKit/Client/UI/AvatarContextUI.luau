--!strict
-- StarterPlayer/StarterPlayerScripts/Client/UI/AvatarContextUI.lua

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local AvatarViewport3D = require(script.Parent.Parent.Utils.AvatarViewport3D)
local AvatarPrewarmShared = require(script.Parent.Parent.Utils.AvatarPrewarmShared)

type AvatarContextPayload = Types.AvatarContextPayload
type ILogger = Types.ILogger

local DEFAULT_BIO_TEXTS = {
	"Too lazy to write",
	"No bio yet",
	"Nothing to say",
	"Empty for now",
	"Bio coming soon",
	"Just vibing here",
	"Mystery player here",
	"No words needed",
	"Silence is golden",
	"Still a mystery",
}

local LOADING_TEXTS = {
	"Loading...",
	"Hang tight...",
	"Almost ready...",
	"Just a sec...",
	"Getting things ready...",
}

local LIKE_BUTTON_TEXT_IDLE = "Like Player"
local LIKE_BUTTON_TEXT_ACTIVE = "Unlike Player"
local LIKE_BUTTON_ACTIVE_COLOR = Color3.fromRGB(255, 82, 112)
local LIKE_BUTTON_ACTIVE_TRANSPARENCY = 0.05
local PANEL_OPEN_START_SCALE = 0.96
local PANEL_OPEN_Y_OFFSET = 34
local PANEL_CLOSE_SCALE = 0.96
local PANEL_CLOSE_Y_OFFSET = 22
local PANEL_OPEN_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local PANEL_CLOSE_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.In)

local function formatCompactCount(value: number?): string
	local count = math.max(0, math.floor(value or 0))
	if count < 100 then
		return string.format("%02d", count)
	end
	if count < 1000 then
		return tostring(count)
	end
	if count < 100000 then
		return string.format("%dK", math.floor(count / 1000))
	end
	return "99+"
end

local function getOrCreateUIScale(target: Instance?): UIScale?
	if not target then
		return nil
	end
	local existing = target:FindFirstChildWhichIsA("UIScale") :: UIScale?
	if existing then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = target
	return scale
end

local function offsetPosition(position: UDim2, yOffset: number): UDim2
	return UDim2.new(position.X.Scale, position.X.Offset, position.Y.Scale, position.Y.Offset + yOffset)
end

local function waitForFirstChildByName(parent: Instance, names: { string }, timeout: number): Instance?
	for _, name in ipairs(names) do
		local existing = parent:FindFirstChild(name)
		if existing then
			return existing
		end
	end

	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		for _, name in ipairs(names) do
			local found = parent:FindFirstChild(name)
			if found then
				return found
			end
		end
		task.wait(0.05)
	end

	return nil
end

local function findFirstDescendantByName(parent: Instance, names: { string }): Instance?
	for _, name in ipairs(names) do
		local found = parent:FindFirstChild(name, true)
		if found then
			return found
		end
	end
	return nil
end

local function ensureFrame(parent: Instance, names: { string }, fallbackName: string): Frame
	local found = findFirstDescendantByName(parent, names)
	if found and found:IsA("Frame") then
		return found
	end

	local frame = Instance.new("Frame")
	frame.Name = fallbackName
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = parent
	return frame
end

local function ensureImageLabel(parent: Instance, names: { string }, fallbackName: string): ImageLabel
	local found = findFirstDescendantByName(parent, names)
	if found and found:IsA("ImageLabel") then
		return found
	end

	local image = Instance.new("ImageLabel")
	image.Name = fallbackName
	image.BackgroundTransparency = 1
	image.ImageTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Visible = false
	image.Parent = parent
	return image
end

local function ensureTextLabel(parent: Instance, names: { string }, fallbackName: string): TextLabel
	local found = findFirstDescendantByName(parent, names)
	if found and found:IsA("TextLabel") then
		return found
	end

	local label = Instance.new("TextLabel")
	label.Name = fallbackName
	label.BackgroundTransparency = 1
	label.Text = ""
	label.TextTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = parent
	return label
end

local function ensureViewportFrame(parent: Instance, names: { string }, fallbackName: string): ViewportFrame
	local found = findFirstDescendantByName(parent, names)
	if found and found:IsA("ViewportFrame") then
		return found
	end

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = fallbackName
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Parent = parent
	return viewport
end

local function createDisabledAvatarContextUI(): any
	local ui = {}

	function ui:setCloseCallback(_callback: () -> ()) end
	function ui:setSyncDanceCallback(_callback: (number) -> ()) end
	function ui:setInvestigateAvatarCallback(_callback: (number) -> ()) end
	function ui:setSendFriendRequestCallback(_callback: (number) -> ()) end
	function ui:setSendGiftCallback(_callback: (number) -> ()) end
	function ui:setCarryCallback(_callback: (number) -> ()) end
	function ui:setBeforeOpenCallback(_callback: () -> number) end
	function ui:setAfterOpenCallback(_callback: (() -> ())?) end
	function ui:setSyncState(_isSyncing: boolean, _targetUserId: number?) end
	function ui:setViewerIsLeader(_isLeader: boolean) end
	function ui:setLikeCallback(_callback: (number) -> ()) end
	function ui:open() end
	function ui:close() end
	function ui:setLoading(_loading: boolean) end
	function ui:setError(_message: string) end
	function ui:setData(_payload: AvatarContextPayload) end
	function ui:showAvatar(_userId: number) end
	function ui:updateLikeState(_likesCount: number, _viewerHasLiked: boolean, _animate: boolean?) end
	function ui:updateBioStatus(_bio: string?, _statusText: string?) end
	function ui:setLikePending(_pending: boolean) end
	function ui:isPointerInside(_point: Vector2): boolean
		return false
	end

	return ui
end

local function createAvatarContextUIUnsafe(deps: { logger: ILogger })
	local log = deps.logger
	-- Wait for GUI
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("AvatarContextMenu", 10)
	if not gui then
		warn("[AvatarContextUI] 'AvatarContextMenu' not found in PlayerGui — panel disabled")
		return createDisabledAvatarContextUI()
	end
	local mainWrapper = gui:WaitForChild("MainWrapper") :: CanvasGroup

	-- Draggable frame (for close button)
	local draggableFrame = mainWrapper:WaitForChild("01-DraggableFrame") :: Frame
	local draggableIcon = draggableFrame:WaitForChild("DraggableIcon") :: Frame

	-- Main content
	local contentWrapper = mainWrapper:WaitForChild("02-MainContentWrapper") :: CanvasGroup
	local loadingScreen = contentWrapper:WaitForChild("LoadingScreen") :: Frame
	local loadingText = loadingScreen:WaitForChild("LoadingText") :: TextLabel
	local mainContent = contentWrapper:WaitForChild("MainContent") :: ScrollingFrame

	-- Player Information Section
	local playerInformation = mainContent:WaitForChild("PlayerInformation") :: Frame
	local illustrationSection =
		ensureFrame(playerInformation, { "IllustrationSection", "Illustrator" }, "IllustrationSection")
	local avatar3D = ensureViewportFrame(illustrationSection, { "3DTargetPlayerAvatar" }, "3DTargetPlayerAvatar")
	local communityCover = ensureImageLabel(illustrationSection, { "CommunityCoverorImage" }, "CommunityCoverorImage")
	local statusPopUp = ensureFrame(illustrationSection, { "StatusPopUp" }, "StatusPopUp")
	local statusPopUpLabel = ensureTextLabel(statusPopUp, { "TextLabel" }, "TextLabel")

	local mainPlayerInfo = playerInformation:WaitForChild("MainPlayerInfo") :: Frame
	local displayNameLabel = mainPlayerInfo:WaitForChild("1-TargetPlayerDisplayName") :: TextLabel
	local usernameLabel = mainPlayerInfo:WaitForChild("2-TargetPlayerUsername") :: TextLabel
	local badgeGroup = mainPlayerInfo:WaitForChild("3-BadgeGroup") :: Frame

	-- Badge references
	local ownerBadge = badgeGroup:WaitForChild("01-OwnerCoOwnerBadge") :: Frame
	local devBadge = badgeGroup:WaitForChild("02-DeveloperBadge") :: Frame
	local adminBadge = badgeGroup:WaitForChild("03-AdminBadge") :: Frame
	local memberBadge = badgeGroup:WaitForChild("04-MemberBadge") :: Frame
	local vipBadge = badgeGroup:WaitForChild("05-VIPMemberBadge") :: Frame
	local vvipBadge = badgeGroup:WaitForChild("06-VVIPMemberBagde") :: Frame
	local eliteBadge = badgeGroup:WaitForChild("07-ELITEMemberBadge") :: Frame
	local streakBadge = badgeGroup:WaitForChild("08-StreakBadge") :: Frame
	local streakBadgeInner = streakBadge:FindFirstChild("Badge")
	local streakCountLabel = streakBadgeInner and streakBadgeInner:FindFirstChild("TextLabel") :: TextLabel?
	local likeBadge = badgeGroup:WaitForChild("09-LikeCounterBadge") :: Frame
	local likeCountLabel = likeBadge:FindFirstChild("LikeCounts", true) :: TextLabel?
	local communityBadge = badgeGroup:WaitForChild("10-CommunityBadge") :: Frame
	local communityBadgeInner = communityBadge:FindFirstChild("Badge")
	local communityLogo = communityBadgeInner and communityBadgeInner:FindFirstChild("CommunityLogo") :: ImageLabel?

	-- Social Proof Section
	local socialProofSection = mainContent:WaitForChild("SocialProofSection") :: Frame
	local connectionCard = socialProofSection:WaitForChild("Connection") :: Frame
	local connectionCountLabel = connectionCard:WaitForChild("ConnectionCounts") :: TextLabel
	local followersCard = socialProofSection:WaitForChild("Followers") :: Frame
	local followersCountLabel = followersCard:WaitForChild("FollowersCounter") :: TextLabel

	-- Bio Section
	local bioSection = mainContent:WaitForChild("BioSection") :: Frame
	local bioContent = bioSection:WaitForChild("BioContent") :: TextLabel

	-- Relationship Status
	local relationshipStatus = mainContent:WaitForChild("RelationshipStatus") :: Frame
	local relationshipContent = relationshipStatus:WaitForChild("RelationshipStatusContent") :: TextLabel

	-- Buttons
	local buttonsGroup = mainContent:WaitForChild("ButtonsGroup") :: Frame
	local buttonsGroupDefaultVisible = buttonsGroup.Visible
	local likeButton = buttonsGroup:WaitForChild("LikeButton") :: TextButton
	local likeButtonBadgeVisual = likeButton:FindFirstChild("Badge", true)
	local likeButtonLabel = likeButton:FindFirstChildWhichIsA("TextLabel", true) :: TextLabel?
	local carryButton = buttonsGroup:WaitForChild("CarryButton") :: TextButton
	local syncDanceButton = buttonsGroup:WaitForChild("SyncDanceButton") :: TextButton
	local syncDanceButtonLabel = syncDanceButton:FindFirstChildWhichIsA("TextLabel", true) :: TextLabel?

	local investigateAvatarButton =
		waitForFirstChildByName(mainContent, { "InvestigateAvatar", "Investigate Avatar" }, 10) :: TextButton
	if not investigateAvatarButton then
		warn("[AvatarContextUI] InvestigateAvatar button not found; panel disabled")
		return createDisabledAvatarContextUI()
	end
	local sendFriendRequestButton = mainContent:WaitForChild("SendFriendRequest") :: TextButton
	local sendGiftButton = mainContent:WaitForChild("SendGiftButton") :: TextButton
	local actionSeparators = {} :: { { gui: GuiObject, visible: boolean } }
	for _, descendant in ipairs(mainContent:GetDescendants()) do
		if descendant:IsA("GuiObject") and string.find(string.lower(descendant.Name), "separator", 1, true) then
			table.insert(actionSeparators, {
				gui = descendant :: GuiObject,
				visible = (descendant :: GuiObject).Visible,
			})
		end
	end

	-- Hide by default
	mainWrapper.Visible = false
	loadingScreen.Visible = false

	local currentTargetUserId: number? = nil
	local renderedAvatarUserId: number? = nil
	local onCloseCallback: (() -> ())? = nil
	local loadingTextThread: thread? = nil
	local currentViewport = nil :: any
	local avatarPool = AvatarPrewarmShared.getPool()
	local thumbnailFallback: ImageLabel? = nil
	local closeButtonConnection: RBXScriptConnection? = nil
	local loadingScreenTween: Tween? = nil
	local investigateAvatarButtonConnection: RBXScriptConnection? = nil
	local sendFriendRequestButtonConnection: RBXScriptConnection? = nil
	local giftButtonConnection: RBXScriptConnection? = nil
	local likeButtonConnection: RBXScriptConnection? = nil
	local syncDanceButtonConnection: RBXScriptConnection? = nil
	local carryButtonConnection: RBXScriptConnection? = nil
	local investigateAvatarCallback: ((number) -> ())? = nil
	local sendFriendRequestCallback: ((number) -> ())? = nil
	local sendGiftCallback: ((number) -> ())? = nil
	local carryCallback: ((number) -> ())? = nil
	local beforeOpenCallback: (() -> number)? = nil
	local afterOpenCallback: (() -> ())? = nil
	local likeButtonCallback: ((number) -> ())? = nil
	local syncDanceCallback: ((number) -> ())? = nil
	local visibilityToken = 0
	local _syncDanceEnabled = false
	local viewerIsSyncing = false
	local viewerSyncTargetUserId: number? = nil
	local viewerIsLeader = false
	local likeButtonPending = false
	local statusBasePosition = statusPopUp.Position
	local statusBaseRotation = statusPopUp.Rotation
	local statusTweenToken = 0
	local likeButtonBadgeScale = getOrCreateUIScale(likeButtonBadgeVisual or likeButton)
	local mainWrapperScale = getOrCreateUIScale(mainWrapper) :: UIScale
	local likeButtonBaseTransparency = likeButton.BackgroundTransparency
	local likeButtonBaseTextTransparency = likeButton.TextTransparency
	local likeButtonLabelBaseTransparency = likeButtonLabel and likeButtonLabel.TextTransparency or 0
	local likeButtonBadgeBaseColor = Color3.fromRGB(255, 255, 255)
	local likeButtonBadgeBaseTransparency = 0
	local setLikeButtonText: (text: string) -> ()
	local setSyncDanceButtonText: (text: string) -> ()
	local setLikeBadgeVisual: (color: Color3, transparency: number) -> ()
	local applyLikePendingState: () -> ()
	local panelAnimationToken = 0
	local panelTween: Tween? = nil
	local panelScaleTween: Tween? = nil
	local panelRestingPosition = mainWrapper.Position
	likeButton.Text = ""
	likeButton.TextTransparency = 1

	if likeButtonBadgeVisual then
		if likeButtonBadgeVisual:IsA("ImageLabel") or likeButtonBadgeVisual:IsA("ImageButton") then
			likeButtonBadgeBaseColor = likeButtonBadgeVisual.ImageColor3
			likeButtonBadgeBaseTransparency = likeButtonBadgeVisual.ImageTransparency
		elseif likeButtonBadgeVisual:IsA("GuiObject") then
			likeButtonBadgeBaseColor = likeButtonBadgeVisual.BackgroundColor3
			likeButtonBadgeBaseTransparency = likeButtonBadgeVisual.BackgroundTransparency
		end
	end

	local ui = {}

	local function cancelPanelTweens()
		if panelTween then
			panelTween:Cancel()
			panelTween = nil
		end
		if panelScaleTween then
			panelScaleTween:Cancel()
			panelScaleTween = nil
		end
	end

	local function presentPanelFromBottom()
		panelAnimationToken += 1
		local token = panelAnimationToken
		cancelPanelTweens()

		mainWrapper.GroupTransparency = 0
		mainWrapperScale.Scale = PANEL_OPEN_START_SCALE
		mainWrapper.Position = offsetPosition(panelRestingPosition, PANEL_OPEN_Y_OFFSET)
		mainWrapper.Visible = true

		local positionTween = TweenService:Create(mainWrapper, PANEL_OPEN_TWEEN, {
			Position = panelRestingPosition,
		})
		local scaleTween = TweenService:Create(mainWrapperScale, PANEL_OPEN_TWEEN, {
			Scale = 1,
		})
		panelTween = positionTween
		panelScaleTween = scaleTween

		positionTween.Completed:Once(function(playbackState)
			if token ~= panelAnimationToken or playbackState ~= Enum.PlaybackState.Completed then
				return
			end
			panelTween = nil
			mainWrapper.Position = panelRestingPosition
		end)
		scaleTween.Completed:Once(function(playbackState)
			if token ~= panelAnimationToken or playbackState ~= Enum.PlaybackState.Completed then
				return
			end
			panelScaleTween = nil
			mainWrapperScale.Scale = 1
		end)

		positionTween:Play()
		scaleTween:Play()
	end

	local function dismissPanelToBottom(onDone: (() -> ())?)
		panelAnimationToken += 1
		local token = panelAnimationToken
		cancelPanelTweens()

		local targetPosition = offsetPosition(panelRestingPosition, PANEL_CLOSE_Y_OFFSET)
		mainWrapper.Visible = true

		local positionTween = TweenService:Create(mainWrapper, PANEL_CLOSE_TWEEN, {
			Position = targetPosition,
		})
		local scaleTween = TweenService:Create(mainWrapperScale, PANEL_CLOSE_TWEEN, {
			Scale = PANEL_CLOSE_SCALE,
		})
		panelTween = positionTween
		panelScaleTween = scaleTween

		positionTween.Completed:Once(function(playbackState)
			if token ~= panelAnimationToken then
				return
			end
			panelTween = nil
			panelScaleTween = nil
			mainWrapper.Visible = false
			mainWrapper.Position = panelRestingPosition
			mainWrapperScale.Scale = 1
			if playbackState == Enum.PlaybackState.Completed and onDone then
				onDone()
			end
		end)

		positionTween:Play()
		scaleTween:Play()
	end

	local function resetVisualState()
		displayNameLabel.Text = "Loading..."
		usernameLabel.Text = "@loading"
		bioContent.Text = ""
		relationshipContent.Text = "Status : ..."
		connectionCountLabel.Text = "..."
		followersCountLabel.Text = "..."
		statusPopUp.Visible = false
		statusPopUpLabel.Text = ""
		communityCover.Visible = false
		communityCover.Image = ""
		avatar3D.Visible = false

		ownerBadge.Visible = false
		devBadge.Visible = false
		adminBadge.Visible = false
		memberBadge.Visible = false
		vipBadge.Visible = false
		vvipBadge.Visible = false
		eliteBadge.Visible = false
		streakBadge.Visible = false
		likeBadge.Visible = false
		communityBadge.Visible = false

		if streakCountLabel then
			streakCountLabel.Text = "0"
		end

		if likeCountLabel then
			likeCountLabel.Text = "0"
		end

		setLikeButtonText(LIKE_BUTTON_TEXT_IDLE)
		setLikeBadgeVisual(likeButtonBadgeBaseColor, likeButtonBadgeBaseTransparency)
		if likeButtonBadgeScale then
			likeButtonBadgeScale.Scale = 1
		end
		likeButtonPending = false
		applyLikePendingState()

		if communityLogo then
			communityLogo.Image = ""
		end
	end

	local function stopStatusAnimation(resetVisual: boolean)
		statusTweenToken += 1
		if resetVisual then
			statusPopUp.Position = statusBasePosition
			statusPopUp.Rotation = statusBaseRotation
			statusPopUpLabel.TextTransparency = 0
		end
	end

	local function startStatusFloatLoop()
		local token = statusTweenToken
		task.spawn(function()
			while statusPopUp.Visible and token == statusTweenToken do
				local riseTween = TweenService:Create(
					statusPopUp,
					TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{
						Position = UDim2.new(
							statusBasePosition.X.Scale,
							statusBasePosition.X.Offset,
							statusBasePosition.Y.Scale,
							statusBasePosition.Y.Offset - 3
						),
						Rotation = statusBaseRotation - 0.75,
					}
				)
				riseTween:Play()
				riseTween.Completed:Wait()
				if not statusPopUp.Visible or token ~= statusTweenToken then
					break
				end

				local fallTween = TweenService:Create(
					statusPopUp,
					TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{
						Position = statusBasePosition,
						Rotation = statusBaseRotation + 0.4,
					}
				)
				fallTween:Play()
				fallTween.Completed:Wait()
			end

			if token == statusTweenToken and statusPopUp.Parent then
				statusPopUp.Position = statusBasePosition
				statusPopUp.Rotation = statusBaseRotation
			end
		end)
	end

	setLikeButtonText = function(text: string)
		likeButton.Text = ""
		likeButton.TextTransparency = 1
		if likeButtonLabel then
			likeButtonLabel.Text = text
		end
	end

	setSyncDanceButtonText = function(text: string)
		if syncDanceButtonLabel then
			syncDanceButton.Text = ""
			syncDanceButtonLabel.Text = text
		else
			syncDanceButton.Text = text
		end
	end

	local function resolveSyncDanceLabel(): string
		if viewerIsSyncing then
			return "Unsync Dance"
		elseif viewerIsLeader then
			return "Transfer Lead"
		end
		return "Sync Dance"
	end

	local function tweenLikeButtonText(text: string)
		if likeButtonLabel then
			local fadeOut = TweenService:Create(
				likeButtonLabel,
				TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ TextTransparency = 1 }
			)
			fadeOut.Completed:Once(function()
				likeButtonLabel.Text = text
				TweenService:Create(
					likeButtonLabel,
					TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ TextTransparency = likeButtonLabelBaseTransparency }
				):Play()
			end)
			fadeOut:Play()
		end

		likeButton.Text = ""
		likeButton.TextTransparency = 1
	end

	setLikeBadgeVisual = function(color: Color3, transparency: number)
		if not likeButtonBadgeVisual then
			return
		end

		if likeButtonBadgeVisual:IsA("ImageLabel") or likeButtonBadgeVisual:IsA("ImageButton") then
			local badgeVisual = likeButtonBadgeVisual :: any
			badgeVisual.ImageColor3 = color
			badgeVisual.ImageTransparency = transparency
			return
		end

		if likeButtonBadgeVisual:IsA("GuiObject") then
			likeButtonBadgeVisual.BackgroundColor3 = color
			likeButtonBadgeVisual.BackgroundTransparency = transparency
		end
	end

	local function tweenLikeBadgeVisual(color: Color3, transparency: number)
		if not likeButtonBadgeVisual then
			return
		end

		if likeButtonBadgeVisual:IsA("ImageLabel") or likeButtonBadgeVisual:IsA("ImageButton") then
			TweenService
				:Create(likeButtonBadgeVisual, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					ImageColor3 = color,
					ImageTransparency = transparency,
				})
				:Play()
			return
		end

		if likeButtonBadgeVisual:IsA("GuiObject") then
			TweenService
				:Create(likeButtonBadgeVisual, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					BackgroundColor3 = color,
					BackgroundTransparency = transparency,
				})
				:Play()
		end
	end

	applyLikePendingState = function()
		local canInteract = not likeButtonPending
		likeButton.Active = canInteract
		likeButton.AutoButtonColor = canInteract
		likeButton.Selectable = canInteract
		likeButton.BackgroundTransparency = canInteract and likeButtonBaseTransparency
			or math.min(0.35, likeButtonBaseTransparency + 0.2)
	end

	local function isGuiPointInside(guiObject: GuiObject, point: Vector2): boolean
		if not guiObject.Visible then
			return false
		end
		local absolutePosition = guiObject.AbsolutePosition
		local absoluteSize = guiObject.AbsoluteSize
		return point.X >= absolutePosition.X
			and point.X <= absolutePosition.X + absoluteSize.X
			and point.Y >= absolutePosition.Y
			and point.Y <= absolutePosition.Y + absoluteSize.Y
	end

	function ui:isPointerInside(point: Vector2): boolean
		if not mainWrapper.Visible then
			return false
		end
		if isGuiPointInside(mainWrapper, point) then
			return true
		end
		if loadingScreen.Visible and isGuiPointInside(loadingScreen, point) then
			return true
		end
		return false
	end

	function ui:setCloseCallback(callback: () -> ())
		onCloseCallback = callback

		if closeButtonConnection then
			closeButtonConnection:Disconnect()
			closeButtonConnection = nil
		end

		-- Wire draggable icon as close button (click to close)
		closeButtonConnection = draggableIcon.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				if onCloseCallback then
					onCloseCallback()
				end
			end
		end)
	end

	function ui:open()
		visibilityToken += 1
		local openToken = visibilityToken
		local delaySeconds = 0
		if beforeOpenCallback then
			delaySeconds = math.max(beforeOpenCallback(), 0)
		end
		if delaySeconds <= 0 then
			presentPanelFromBottom()
			if afterOpenCallback then
				afterOpenCallback()
			end
			return
		end
		task.delay(delaySeconds, function()
			if openToken ~= visibilityToken then
				return
			end
			presentPanelFromBottom()
			if afterOpenCallback then
				afterOpenCallback()
			end
		end)
	end

	function ui:close()
		visibilityToken += 1
		local closeToken = visibilityToken
		if loadingTextThread then
			task.cancel(loadingTextThread)
			loadingTextThread = nil
		end
		if loadingScreenTween then
			loadingScreenTween:Cancel()
			loadingScreenTween = nil
		end

		-- Jangan disconnect button connections di sini — event order di Roblox:
		-- InputBegan (mouse down) → handler close panel → Activated (mouse up).
		-- Kalau connections di-disconnect, Activated ga pernah fire dan
		-- callback (investigateAvatar, sendFriendRequest, dll) ga jalan.
		-- Connections akan di-replace otomatis pas setData berikutnya.

		stopStatusAnimation(true)
		statusPopUp.Visible = false
		resetVisualState()

		loadingScreen.Visible = false
		loadingScreen.Position = UDim2.fromScale(0, 0)
		mainContent.Visible = false

		dismissPanelToBottom(function()
			if closeToken ~= visibilityToken then
				return
			end
			currentTargetUserId = nil
		end)
	end

	function ui:setLoading(loading: boolean)
		if loadingScreenTween then
			loadingScreenTween:Cancel()
			loadingScreenTween = nil
		end

		if loading then
			resetVisualState()

			-- Reset loading screen position
			loadingScreen.Position = UDim2.fromScale(0, 0)

			-- Show loading screen, hide main content
			loadingScreen.Visible = true
			mainContent.Visible = false

			-- Stop previous loading text animation if any
			if loadingTextThread then
				task.cancel(loadingTextThread)
			end

			-- Start loading text rotation
			loadingTextThread = task.spawn(function()
				local index = 1
				while loadingScreen.Visible do
					loadingText.Text = LOADING_TEXTS[index]
					index = index % #LOADING_TEXTS + 1
					task.wait(1)
				end
			end)
		else
			-- Stop loading text animation
			if loadingTextThread then
				task.cancel(loadingTextThread)
				loadingTextThread = nil
			end

			-- Show main content immediately
			mainContent.Visible = true

			-- Slide loading screen up and hide with spring-like animation
			local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			local tween = TweenService:Create(loadingScreen, tweenInfo, {
				Position = UDim2.fromScale(0, -1),
			})
			loadingScreenTween = tween

			tween:Play()
			tween.Completed:Once(function(playbackState)
				if playbackState == Enum.PlaybackState.Completed and loadingScreen.Parent then
					loadingScreen.Visible = false
				end
				loadingScreenTween = nil
			end)
		end
	end

	function ui:setData(payload: AvatarContextPayload)
		-- setData sekarang HANYA update text/data state. Tidak pernah panggil
		-- currentViewport:load() (yang yield) atau trigger 3D model loading.
		-- 3D avatar adalah concern terpisah via showAvatar() yang dipanggil
		-- dari controller.openPanel. Ini mengeliminasi coupling yang sebelumnya
		-- memblokir FireServer selama 14 detik.
		currentTargetUserId = payload.userId

		-- Set display name and username
		displayNameLabel.Text = payload.displayName
		usernameLabel.Text = "@" .. payload.username

		-- Set badges
		ui:_setBadges(payload.visibleBadges)

		-- Set streak
		ui:_setStreak(payload.streakDays)

		-- Set likes
		ui:_setLikeCount(payload.likesCount)
		ui:_applyLikeButtonState(payload.viewerHasLiked, false)

		-- Set community
		ui:_setCommunity(payload.communityId, payload.communityName, payload.communityLogo)

		-- Set bio
		ui:_setBio(payload.bio)

		-- Set status popup
		ui:_setStatusPopup(payload.statusText)

		-- Set relationship
		ui:_setRelationship(payload.relationshipText)

		-- Set social proof
		ui:_setSocialProof(payload.likesCount, payload.connectionsCount)

		-- Set action buttons
		ui:_setActionButtons(payload)
	end

	local function _showThumbnail(userId: number)
		local thumbnailUrl = string.format("rbxthumb://type=AvatarBust&id=%d&w=420&h=420", userId)
		if thumbnailUrl == "" then
			avatar3D.Visible = false
			renderedAvatarUserId = nil
			return
		end
		if not thumbnailFallback then
			local created = Instance.new("ImageLabel")
			thumbnailFallback = created
		end
		local fallback = thumbnailFallback :: ImageLabel
		fallback.Name = "ThumbnailFallback"
		fallback.Size = UDim2.fromScale(1, 1)
		fallback.Position = UDim2.fromScale(0.5, 0.5)
		fallback.AnchorPoint = Vector2.new(0.5, 0.5)
		fallback.BackgroundTransparency = 1
		fallback.Image = thumbnailUrl
		fallback.ScaleType = Enum.ScaleType.Fit
		fallback.Visible = true
		fallback.Parent = avatar3D
		renderedAvatarUserId = userId
	end

	-- Active subscription ke pool's subscribeModelReady untuk upgrade
	-- thumbnail → 3D seamless. Disimpan agar bisa di-unsubscribe saat
	-- showAvatar dipanggil untuk user berbeda.
	local modelReadyUnsub: (() -> ())? = nil

	function ui:showAvatar(userId: number)
		-- Hentikan subscription lama agar callback tidak fire untuk userId
		-- yang sudah bukan target lagi (mis. user klik avatar lain).
		if modelReadyUnsub then
			modelReadyUnsub()
			modelReadyUnsub = nil
		end

		-- Reset avatar visibility
		avatar3D.Visible = true
		if thumbnailFallback then
			thumbnailFallback.Visible = false
		end

		if not currentViewport then
			currentViewport = AvatarViewport3D.new(avatar3D)
			currentViewport:setPrewarmPool(avatarPool)
		else
			currentViewport:cleanup()
		end

		local success = currentViewport:load(userId)
		if success then
			renderedAvatarUserId = userId
			log:info("3D avatar loaded successfully", { userId = userId })
			return
		end

		-- Pool miss: fallback ke thumbnail (instant, no YIELD) + subscribe
		-- ke subscribeModelReady untuk upgrade seamless saat pool ready.
		log:debug("Pool miss — using thumbnail, subscribing to model ready", { userId = userId })
		_showThumbnail(userId)

		if avatarPool and type(avatarPool.subscribeModelReady) == "function" then
			modelReadyUnsub = avatarPool:subscribeModelReady(userId, function()
				-- Guard: userId masih jadi target? (mungkin user sudah close
				-- panel atau pindah ke user lain).
				if currentTargetUserId ~= userId or not avatar3D.Visible then
					return
				end
				-- Pool sudah ready. Re-attempt load(). Kalau masih miss
				-- (mis. pool evicted lagi), keep thumbnail.
				if not currentViewport then
					currentViewport = AvatarViewport3D.new(avatar3D)
					currentViewport:setPrewarmPool(avatarPool)
				else
					currentViewport:cleanup()
				end
				local reloaded = currentViewport:load(userId)
				if reloaded then
					renderedAvatarUserId = userId
					if thumbnailFallback then
						thumbnailFallback.Visible = false
					end
					log:info("3D avatar upgraded from thumbnail to 3D", { userId = userId })
				end
			end)
		end

		-- Trigger pool prewarm on-demand kalau belum ada di pool / loading.
		-- Ini membuat subsequent clicks instant (pool akan sudah ready).
		if avatarPool and type(avatarPool.prewarmOnDemand) == "function" then
			avatarPool:prewarmOnDemand(userId)
		end
	end

	function ui:_setBadges(visibleBadges: { string })
		-- Hide role/membership badges only (not streak/community - they have separate logic)
		ownerBadge.Visible = false
		devBadge.Visible = false
		adminBadge.Visible = false
		memberBadge.Visible = false
		vipBadge.Visible = false
		vvipBadge.Visible = false
		eliteBadge.Visible = false
		likeBadge.Visible = false

		-- Show visible badges
		for _, badgeName in visibleBadges do
			if badgeName == "01-OwnerCoOwnerBadge" then
				ownerBadge.Visible = true
			elseif badgeName == "02-DeveloperBadge" then
				devBadge.Visible = true
			elseif badgeName == "03-AdminBadge" then
				adminBadge.Visible = true
			elseif badgeName == "04-MemberBadge" then
				memberBadge.Visible = true
			elseif badgeName == "05-VIPMemberBadge" then
				vipBadge.Visible = true
			elseif badgeName == "06-VVIPMemberBagde" then
				vvipBadge.Visible = true
			elseif badgeName == "07-ELITEMemberBadge" then
				eliteBadge.Visible = true
			elseif badgeName == "09-LikeCounterBadge" then
				likeBadge.Visible = true
			end
		end
	end

	function ui:_setStreak(streakDays: number)
		if streakDays > 0 then
			streakBadge.Visible = true
			if streakCountLabel then
				streakCountLabel.Text = tostring(streakDays)
			end
		else
			streakBadge.Visible = false
		end
	end

	function ui:_setLikeCount(likesCount: number)
		if likesCount > 0 then
			likeBadge.Visible = true
			if likeCountLabel then
				likeCountLabel.Text = formatCompactCount(likesCount)
			end
		else
			likeBadge.Visible = false
			if likeCountLabel then
				likeCountLabel.Text = "0"
			end
		end
	end

	function ui:_applyLikeButtonState(isLiked: boolean, animate: boolean?)
		local targetText = if isLiked then LIKE_BUTTON_TEXT_ACTIVE else LIKE_BUTTON_TEXT_IDLE
		local targetColor = if isLiked then LIKE_BUTTON_ACTIVE_COLOR else likeButtonBadgeBaseColor
		local targetTransparency = if isLiked then LIKE_BUTTON_ACTIVE_TRANSPARENCY else likeButtonBadgeBaseTransparency

		if animate then
			tweenLikeButtonText(targetText)
			tweenLikeBadgeVisual(targetColor, targetTransparency)
			if likeButtonBadgeScale then
				likeButtonBadgeScale.Scale = 1
				local popOut = TweenService:Create(
					likeButtonBadgeScale,
					TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Scale = 1.12 }
				)
				popOut.Completed:Once(function()
					TweenService:Create(
						likeButtonBadgeScale :: UIScale,
						TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Scale = 1 }
					):Play()
				end)
				popOut:Play()
			end
			return
		end

		setLikeButtonText(targetText)
		setLikeBadgeVisual(targetColor, targetTransparency)
		if likeButtonLabel then
			likeButtonLabel.TextTransparency = likeButtonLabelBaseTransparency
		end
		likeButton.Text = ""
		likeButton.TextTransparency = 1
		if likeButtonBadgeScale then
			likeButtonBadgeScale.Scale = 1
		end
	end

	function ui:_setCommunity(communityId: number?, communityName: string?, communityLogoUrl: string?)
		if communityId and communityLogoUrl then
			communityBadge.Visible = true
			if communityLogo then
				communityLogo.Image = communityLogoUrl
			end

			-- Set community cover as subtle background
			communityCover.Visible = true
			communityCover.Image = communityLogoUrl
			communityCover.ImageTransparency = 0.9 -- Very subtle
			communityCover.ImageColor3 = Color3.fromRGB(255, 255, 255)
		else
			communityBadge.Visible = false
			communityCover.Visible = false
		end
	end

	function ui:_setBio(bio: string?)
		bioSection.Visible = true

		if bio and #bio > 0 then
			-- User has bio - show it normally
			bioContent.Text = '"' .. bio .. '"'
			bioContent.TextColor3 = Color3.fromRGB(255, 255, 255) -- Normal white
			bioContent.FontFace = Font.new("rbxassetid://12187365977", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
		else
			-- No bio - show random placeholder
			local randomIndex = math.random(1, #DEFAULT_BIO_TEXTS)
			local placeholderText = DEFAULT_BIO_TEXTS[randomIndex]
			bioContent.Text = '"' .. placeholderText .. '"'
			bioContent.TextColor3 = Color3.fromRGB(180, 180, 180) -- Dimmed gray
			bioContent.FontFace = Font.new("rbxassetid://12187365977", Enum.FontWeight.SemiBold, Enum.FontStyle.Italic)
		end
	end

	function ui:_setStatusPopup(statusText: string?)
		stopStatusAnimation(true)

		if statusText and #statusText > 0 then
			statusPopUp.Visible = true
			statusPopUpLabel.Text = statusText

			statusPopUpLabel.TextTransparency = 1
			statusPopUp.Position = UDim2.new(
				statusBasePosition.X.Scale,
				statusBasePosition.X.Offset,
				statusBasePosition.Y.Scale,
				statusBasePosition.Y.Offset - 10
			)
			statusPopUp.Rotation = statusBaseRotation - 3

			local localToken = statusTweenToken
			local tweenInfo = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			local tween1 = TweenService:Create(statusPopUp, tweenInfo, {
				Position = statusBasePosition,
				Rotation = statusBaseRotation,
			})
			local tween2 = TweenService:Create(statusPopUpLabel, tweenInfo, {
				TextTransparency = 0,
			})

			tween1.Completed:Once(function()
				if localToken == statusTweenToken and statusPopUp.Visible then
					startStatusFloatLoop()
				end
			end)

			tween1:Play()
			tween2:Play()
		else
			statusPopUp.Visible = false
			statusPopUpLabel.Text = ""
			statusPopUpLabel.TextTransparency = 0
		end
	end

	function ui:_setRelationship(relationshipText: string?)
		relationshipStatus.Visible = true
		relationshipContent.Text = if relationshipText and relationshipText ~= ""
			then relationshipText
			else "Status : Single"
	end

	function ui:_setSocialProof(totalLikes: number, connectionsCount: number?)
		socialProofSection.Visible = true

		-- Set connections
		if connectionsCount then
			connectionCard.Visible = true
			connectionCountLabel.Text = tostring(connectionsCount)
		else
			connectionCard.Visible = true
			connectionCountLabel.Text = "N/A"
		end

		-- Set total likes
		if totalLikes >= 0 then
			followersCard.Visible = true
			followersCountLabel.Text = formatCompactCount(totalLikes)
		else
			followersCard.Visible = true
			followersCountLabel.Text = "N/A"
		end
	end

	function ui:_setActionButtons(payload: AvatarContextPayload)
		if investigateAvatarButtonConnection then
			investigateAvatarButtonConnection:Disconnect()
			investigateAvatarButtonConnection = nil
		end
		if sendFriendRequestButtonConnection then
			sendFriendRequestButtonConnection:Disconnect()
			sendFriendRequestButtonConnection = nil
		end
		if giftButtonConnection then
			giftButtonConnection:Disconnect()
			giftButtonConnection = nil
		end
		if likeButtonConnection then
			likeButtonConnection:Disconnect()
			likeButtonConnection = nil
		end
		if syncDanceButtonConnection then
			syncDanceButtonConnection:Disconnect()
			syncDanceButtonConnection = nil
		end
		if carryButtonConnection then
			carryButtonConnection:Disconnect()
			carryButtonConnection = nil
		end

		buttonsGroup.Visible = buttonsGroupDefaultVisible
		for _, separator in ipairs(actionSeparators) do
			separator.gui.Visible = separator.visible
		end

		-- Like button
		likeButton.Visible = payload.canLike
		applyLikePendingState()

		-- Carry button
		carryButton.Visible = payload.canCarry

		-- Sync dance button
		_syncDanceEnabled = payload.canSyncDance
		setSyncDanceButtonText(resolveSyncDanceLabel())
		syncDanceButton.Visible = true
		syncDanceButton.AutoButtonColor = payload.canSyncDance
		syncDanceButton.Active = payload.canSyncDance
		syncDanceButton.Selectable = payload.canSyncDance
		syncDanceButton.TextTransparency = payload.canSyncDance and 0 or 0.45
		syncDanceButton.BackgroundTransparency = payload.canSyncDance and 0 or 0.35

		-- Send gift button
		investigateAvatarButton.Visible = payload.canInvestigateAvatar
		sendFriendRequestButton.Visible = payload.canSendFriendRequest
		sendGiftButton.Visible = payload.canSendGift

		if payload.canInvestigateAvatar and investigateAvatarCallback then
				investigateAvatarButtonConnection = investigateAvatarButton.Activated:Connect(function()
					log:debug("InvestigateAvatar activated", { targetUserId = currentTargetUserId })
					if currentTargetUserId then
						investigateAvatarCallback(currentTargetUserId)
					end
				end)
			end

		if payload.canSendFriendRequest and sendFriendRequestCallback then
			sendFriendRequestButtonConnection = sendFriendRequestButton.Activated:Connect(function()
				if currentTargetUserId then
					sendFriendRequestCallback(currentTargetUserId)
				end
			end)
		end

		if payload.canSendGift and sendGiftCallback then
			giftButtonConnection = sendGiftButton.Activated:Connect(function()
				if currentTargetUserId then
					sendGiftCallback(currentTargetUserId)
				end
			end)
		end

		if payload.canLike and likeButtonCallback then
			likeButtonConnection = likeButton.Activated:Connect(function()
				if currentTargetUserId then
					likeButtonCallback(currentTargetUserId)
				end
			end)
		end

		if payload.canCarry and carryCallback then
			carryButtonConnection = carryButton.Activated:Connect(function()
				if currentTargetUserId then
					carryCallback(currentTargetUserId)
				end
			end)
		end

		if payload.canSyncDance and syncDanceCallback then
			syncDanceButtonConnection = syncDanceButton.Activated:Connect(function()
				if currentTargetUserId then
					syncDanceCallback(currentTargetUserId)
				end
			end)
		end
	end

	function ui:setSyncDanceCallback(callback: (number) -> ())
		syncDanceCallback = callback
	end

	function ui:setInvestigateAvatarCallback(callback: (number) -> ())
		investigateAvatarCallback = callback
	end

	function ui:setSendFriendRequestCallback(callback: (number) -> ())
		sendFriendRequestCallback = callback
	end

	function ui:setSendGiftCallback(callback: (number) -> ())
		sendGiftCallback = callback
	end

	function ui:setCarryCallback(callback: (number) -> ())
		carryCallback = callback
	end

	function ui:setBeforeOpenCallback(callback: () -> number)
		beforeOpenCallback = callback
	end

	function ui:setAfterOpenCallback(callback: (() -> ())?)
		afterOpenCallback = callback
	end

	function ui:setSyncState(isSyncing: boolean, targetUserId: number?)
		viewerIsSyncing = isSyncing
		viewerSyncTargetUserId = targetUserId
		if currentTargetUserId then
			setSyncDanceButtonText(resolveSyncDanceLabel())
		end
	end

	function ui:setViewerIsLeader(isLeader: boolean)
		viewerIsLeader = isLeader == true
		if currentTargetUserId then
			setSyncDanceButtonText(resolveSyncDanceLabel())
		end
	end

	function ui:setLikeCallback(callback: (number) -> ())
		likeButtonCallback = callback
	end

	function ui:setLikePending(pending: boolean)
		likeButtonPending = pending
		applyLikePendingState()
	end

	function ui:updateLikeState(likesCount: number, viewerHasLiked: boolean, animate: boolean?)
		ui:_setLikeCount(likesCount)
		ui:_applyLikeButtonState(viewerHasLiked, animate)
	end

	function ui:updateBioStatus(bio: string?, statusText: string?)
		ui:_setBio(bio)
		ui:_setStatusPopup(statusText)
	end

	return ui
end

local function createAvatarContextUI(deps: { logger: ILogger })
	local ok, uiOrError = xpcall(function()
		return createAvatarContextUIUnsafe(deps)
	end, function(err)
		return debug.traceback(tostring(err), 2)
	end)

	if ok then
		return uiOrError
	end

	deps.logger:warn("AvatarContextMenu structure tidak lengkap; panel disabled", {
		error = tostring(uiOrError),
	})
	return createDisabledAvatarContextUI()
end

return createAvatarContextUI
