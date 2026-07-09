--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ObjectPool = require(script.Parent.Parent.Utils.ObjectPool)
local ScrollIndicatorHelper = require(script.Parent.Parent.Utils.ScrollIndicatorHelper)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
local SliderSelectorUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.SliderSelectorUtil)

local DancePanelUIBinder = {} :: any
DancePanelUIBinder.__index = DancePanelUIBinder

local LIGHT_TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local DARK_TEXT_COLOR = Color3.fromRGB(12, 12, 12)
local KNOB_POP_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local KNOB_HIDE_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local ROW_STATE_TWEEN = TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local ROW_FAST_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local ROW_IMAGE_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
local ROW_GRADIENT_TWEEN = TweenInfo.new(4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
local SPEED_STEP = 0.01
local PANEL_OPEN_SCALE = 1
local SPEED_HANDLE_AUTO_HIDE_DELAY = 2

type AnimationEntry = Animation
type Refs = any

local function clamp(value: number, minValue: number, maxValue: number): number
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function roundToStep(value: number, step: number): number
	return math.floor((value / step) + 0.5) * step
end

local function getRowLabel(row: GuiButton): TextLabel?
	local label = row:FindFirstChild("1-TextLabel", true)
	if label and label:IsA("TextLabel") then
		return label
	end
	return nil
end

local function getFavoriteButton(row: GuiButton): GuiButton?
	local button = row:FindFirstChild("2-ImageButton", true)
	if button and button:IsA("GuiButton") then
		return button
	end
	return nil
end

local function getFavoriteBadge(row: GuiButton): ImageLabel?
	local button = getFavoriteButton(row)
	if not button then
		return nil
	end

	local badge = button:FindFirstChild("Badge")
	if badge and badge:IsA("ImageLabel") then
		return badge
	end

	return nil
end

local function getButtonLabel(button: GuiButton): TextLabel?
	local label = button:FindFirstChild("TextLabel")
	if label and label:IsA("TextLabel") then
		return label
	end
	return nil
end

local function setGradientEnabled(button: GuiButton, gradientNames: { string }, isEnabled: boolean)
	for _, gradientName in ipairs(gradientNames) do
		local gradient = button:FindFirstChild(gradientName)
		if gradient and gradient:IsA("UIGradient") then
			gradient.Enabled = isEnabled
		end
	end
end

-- Device-aware press handler.
--
-- Desktop / hybrid (mouse + keyboard): instant fire on InputBegan, sama persis
-- kayak behavior original — no delay, no drag detection.
--
-- Touch-only (HP / tablet tanpa keyboard): tap detector. Track posisi awal
-- saat InputBegan, monitor drag via UserInputService global, cancel tap kalau
-- finger bergerak > TAP_DRAG_THRESHOLD pixel. Fire callback baru di InputEnded
-- kalau masih dalam threshold. Cegah row dance kepencet pas user mau scroll.
--
-- Return: object dengan method :Disconnect() (compatible dengan existing caller
-- yang panggil rowConnection:Disconnect()).
local IS_TOUCH_ONLY_DEVICE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
-- HP scroll: threshold lebih longgar supaya scroll tidak kepencet sebagai tap dance.
local TAP_DRAG_THRESHOLD_SQ = 42 * 42 -- 42px squared (avoid sqrt per InputChanged)

local function bindPressDown(button: GuiButton, callback: (InputObject) -> ())
	local connections: { RBXScriptConnection } = {}
	local pendingTaps: { [InputObject]: Vector2 } = {}

	table.insert(connections, button.InputBegan:Connect(function(input)
		-- Mouse: always instant (gak ada drag-to-scroll concern di mouse).
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			callback(input)
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		-- Touch on desktop/hybrid (mouse + keyboard available): instant.
		if not IS_TOUCH_ONLY_DEVICE then
			callback(input)
			return
		end
		-- Touch-only device: enter tap detector mode.
		pendingTaps[input] = Vector2.new(input.Position.X, input.Position.Y)
	end))

	if IS_TOUCH_ONLY_DEVICE then
		table.insert(connections, UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			local startPos = pendingTaps[input]
			if not startPos then
				return
			end
			local dx = input.Position.X - startPos.X
			local dy = input.Position.Y - startPos.Y
			if (dx * dx + dy * dy) > TAP_DRAG_THRESHOLD_SQ then
				-- Drag detected — user mau scroll, bukan tap. Cancel.
				pendingTaps[input] = nil
			end
		end))

		table.insert(connections, UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			local startPos = pendingTaps[input]
			if not startPos then
				-- Either tap di-cancel oleh drag, atau input bukan dari button ini.
				return
			end
			pendingTaps[input] = nil
			callback(input)
		end))
	end

	return {
		Disconnect = function()
			for _, c in ipairs(connections) do
				c:Disconnect()
			end
			table.clear(connections)
			table.clear(pendingTaps)
		end,
	}
end

local function getInputPosition(input: InputObject): Vector2
	if input.UserInputType == Enum.UserInputType.Touch then
		return Vector2.new(input.Position.X, input.Position.Y)
	end
	return UserInputService:GetMouseLocation()
end

local function isPointInside(gui: GuiObject?, point: Vector2): boolean
	if not gui or not gui.Visible then
		return false
	end

	local position = gui.AbsolutePosition
	local size = gui.AbsoluteSize
	return point.X >= position.X
		and point.X <= position.X + size.X
		and point.Y >= position.Y
		and point.Y <= position.Y + size.Y
end

local function tweenProperties(instance: Instance, goal: { [string]: any }, tweenInfo: TweenInfo?)
	local tween = TweenService:Create(instance, tweenInfo or ROW_STATE_TWEEN, goal)
	tween:Play()
	return tween
end

local function setPanelAlpha(panelRoot: GuiObject, alpha: number)
	if panelRoot:IsA("CanvasGroup") then
		panelRoot.GroupTransparency = alpha
	end
end

type EmoteSelectedCallback = (AnimationEntry) -> ()
type FavoriteToggledCallback = (string) -> ()
type SpeedChangedCallback = (number) -> ()
type UnsyncRequestedCallback = () -> ()

local function getPanelAnimFrame(refs: Refs): Frame
	-- Mobile: animate MainWrapper so root UIScale (0.75) is not overwritten by AnimationHelper.
	if refs.panelRoot:GetAttribute("DancePanelLayout") == "mobile" then
		local mainWrapper = refs.panelRoot:FindFirstChild("MainWrapper")
		if mainWrapper and mainWrapper:IsA("Frame") then
			return mainWrapper :: Frame
		end
	end
	if refs.panelRoot:IsA("Frame") then
		return refs.panelRoot :: Frame
	end
	return refs.draggableFrame
end

local function restoreMobileBakedPanelScale(panelRoot: GuiObject, syncConfig: any)
	if panelRoot:GetAttribute("DancePanelLayout") ~= "mobile" then
		return
	end
	local bakedScale = panelRoot:FindFirstChild("UIScale")
	if bakedScale and bakedScale:IsA("UIScale") then
		bakedScale.Scale = tonumber(syncConfig.DANCE_PANEL_V2_SCALE_MOBILE) or 0.75
	end
end

function DancePanelUIBinder.new(deps: {
	refs: Refs,
	config: any,
})
	local self = setmetatable({}, DancePanelUIBinder) :: any
	self.refs = deps.refs
	self.config = deps.config.Sync
	self._emoteSelected = nil :: EmoteSelectedCallback?
	self._favoriteToggled = nil :: FavoriteToggledCallback?
	self._speedChanged = nil :: SpeedChangedCallback?
	self._unsyncRequested = nil :: UnsyncRequestedCallback?
	self._danceAnims = {}
	self._poseAnims = {}
	self._favoritedAnims = {}
	self._currentCategory = "Dance"
	self._currentSpeed = self.config.DEFAULT_SPEED
	self._searchQuery = ""
	self._currentAnimName = nil :: string?
	self._activeRows = {}
	self._activeRowsByName = {}
	self._rowPool = nil -- Will be initialized after refs are available
	self._rowPressConnections = {}
	self._favoritePressConnections = {}
	self._descendantsCache = {} -- Cache for row descendants (key = row instance)
	self._rowGradientTweens = {}
	self._dragMoveConn = nil
	self._dragEndConn = nil
	self._sliderMoveConn = nil
	self._sliderEndConn = nil
	self._customSpeedFocusLostConn = nil
	self._resetSpeedConn = nil
	self._isSliderHovered = false
	self._isSliderDragging = false
	self._isOpen = false
	self._isClosing = false
	self._listDirty = true
	self._catalogReady = false
	self._incrementalRebuildGeneration = 0
	self._incrementalRebuildThread = nil :: thread?
	self._anim = AnimationHelper.new()
	self._tweenToken = 0
	self._knobTweenToken = 0
	self._speedHandleVisibilityToken = 0
	ScrollIndicatorHelper.attach(self.refs.mainContent)
	self:_ensureScrollInputCapture()
	self._openPosition = self.refs.panelRoot.Position
	self._openAnchorPoint = self.refs.panelRoot.AnchorPoint
	self._defaultSearchPlaceholder = self.refs.searchBox.PlaceholderText ~= "" and self.refs.searchBox.PlaceholderText
		or "Search dance or pose..."
	self._preparingSearchPlaceholder = "Preparing dances..."

	-- Initialize ObjectPool for row recycling
	self._rowPool = ObjectPool.new(
		function()
			return self.refs.rowRefs.normal:Clone()
		end,
		function(row: GuiButton)
			row.Parent = nil
			row.Visible = false
			row.LayoutOrder = 0
			local label = getRowLabel(row)
			if label then
				label.Text = ""
			end
		end,
		50 -- Max 50 rows in pool
	)

	self:_ensurePanelScale()
	self:_ensureSpeedKnobScale()
	self:_disableRootDragDetector()
	self:_hideReferenceRows()
	self:_bindTabs()
	self:_bindSearch()
	self:_bindSyncOverlay()
	self:_bindPanelDrag()
	self:_setupSpeedSlider()
	self:_bindCustomSpeed()
	self:_applyTabVisuals()
	self:_updateSpeedKnobVisibility()
	restoreMobileBakedPanelScale(self.refs.panelRoot, self.config)
	self:setOpen(false, true)
	restoreMobileBakedPanelScale(self.refs.panelRoot, self.config)
	return self
end

function DancePanelUIBinder:_speedHandleIsKnob(): boolean
	local handle = self.refs.speedHandle
	return handle ~= self.refs.speedFill and handle:IsA("ImageLabel")
end

function DancePanelUIBinder:_ensureSpeedKnobScale(): UIScale?
	if not self:_speedHandleIsKnob() then
		return nil
	end

	local existing = self.refs.speedHandle:FindFirstChild("DancePanelKnobScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end

	local scale = Instance.new("UIScale")
	scale.Name = "DancePanelKnobScale"
	scale.Scale = 0.82
	scale.Parent = self.refs.speedHandle
	return scale
end

function DancePanelUIBinder:_ensureSpeedInputShield(): Frame
	local speedWrapper = self.refs.speedWrapper
	local existing = speedWrapper:FindFirstChild("SpeedInputShield")
	if existing then
		if existing:IsA("Frame") then
			existing.Active = true
			existing.BackgroundTransparency = 1
			existing.BorderSizePixel = 0
			existing.Selectable = false
			existing.Size = UDim2.fromScale(1, 1)
			existing.Position = UDim2.fromScale(0, 0)
			existing.ZIndex = math.max(speedWrapper.ZIndex, self.refs.speedFill.ZIndex, self.refs.speedHandle.ZIndex)
				+ 10
			return existing
		end

		existing:Destroy()
	end

	-- Transparent blocker so slider clicks do not fall through to the dance list behind it.
	local shield = Instance.new("Frame")
	shield.Name = "SpeedInputShield"
	shield.Active = true
	shield.BackgroundTransparency = 1
	shield.BorderSizePixel = 0
	shield.Selectable = false
	shield.Size = UDim2.fromScale(1, 1)
	shield.Position = UDim2.fromScale(0, 0)
	shield.ZIndex = math.max(speedWrapper.ZIndex, self.refs.speedFill.ZIndex, self.refs.speedHandle.ZIndex) + 10
	shield.Parent = speedWrapper
	return shield
end

function DancePanelUIBinder:_ensurePanelScale(): UIScale
	local existing = self.refs.panelRoot:FindFirstChild("DancePanelRootScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end

	-- Mobile: keep baked UIScale (0.75) untouched; open anim uses a separate child only.
	local isMobileLayout = self.refs.panelRoot:GetAttribute("DancePanelLayout") == "mobile"
	if not isMobileLayout then
		local bakedScale = self.refs.panelRoot:FindFirstChildWhichIsA("UIScale")
		if bakedScale and bakedScale.Name ~= "DancePanelRootScale" then
			return bakedScale
		end
	end

	local scale = Instance.new("UIScale")
	scale.Name = "DancePanelRootScale"
	scale.Scale = PANEL_OPEN_SCALE
	scale.Parent = self.refs.panelRoot
	return scale
end

function DancePanelUIBinder:_applySpeedFillRatio(ratio: number)
	local snapped = clamp(ratio, 0, 1)
	if self.refs.speedSliderVertical then
		self.refs.speedFill.Size = UDim2.new(1, 0, snapped, 0)
	else
		self.refs.speedFill.Size = UDim2.new(snapped, 0, 1, 0)
	end
end

function DancePanelUIBinder:_disableRootDragDetector()
	local detector = self.refs.panelDragDetector
	if not detector then
		return
	end

	pcall(function()
		(detector :: any).Enabled = false
	end)
end

local function setGuiInputCapture(gui: GuiObject)
	gui.Active = true
	if gui:IsA("CanvasGroup") then
		gui.Interactable = true
	end
end

-- HP: pastikan scroll list menangkap touch (tidak nembus ke kamera).
function DancePanelUIBinder:_ensureScrollInputCapture()
	local panelRoot = self.refs.panelRoot
	local wrapper = self.refs.mainContentWrapper
	local scroll = self.refs.mainContent

	setGuiInputCapture(panelRoot)
	setGuiInputCapture(wrapper)
	setGuiInputCapture(scroll)
	scroll.ScrollingEnabled = true
	scroll.Active = true
	pcall(function()
		scroll.ElasticBehavior = Enum.ElasticBehavior.Always
	end)
	-- Kurangi overscroll / momentum agar scroll list tidak “loncat” di HP.
	pcall(function()
		(scroll :: any).ScrollBarThickness = math.max(scroll.ScrollBarThickness, 6)
	end)

	-- Saat jari di area list, matikan sementara touch-look kamera default.
	local touchCameraController: any = nil
	local function resolveTouchCameraController(): any
		if touchCameraController ~= nil then
			return touchCameraController
		end
		local player = Players.LocalPlayer
		local playerScripts = player and player:FindFirstChild("PlayerScripts")
		local playerModuleScript = playerScripts and playerScripts:FindFirstChild("PlayerModule")
		if not playerModuleScript then
			return nil
		end
		local ok, playerModule = pcall(require, playerModuleScript)
		if not ok or type(playerModule) ~= "table" or type(playerModule.GetCameras) ~= "function" then
			return nil
		end
		local cameras = playerModule:GetCameras()
		if type(cameras) ~= "table" then
			return nil
		end
		touchCameraController = cameras.activeTouchController or cameras.touchCamera
		return touchCameraController
	end

	local scrollTouches: { [InputObject]: boolean } = {}
	local function setScrollTouchCameraSuppressed(suppressed: boolean)
		local controller = resolveTouchCameraController()
		if not controller then
			return
		end
		pcall(function()
			if type(controller.Enable) == "function" then
				controller:Enable(not suppressed)
			elseif type(controller.SetEnabled) == "function" then
				controller:SetEnabled(not suppressed)
			end
		end)
	end

	local function isScrollCapturePoint(point: Vector2): boolean
		return isPointInside(scroll, point) or isPointInside(wrapper, point)
	end

	local function recomputeScrollTouchCamera()
		for touch in pairs(scrollTouches) do
			if touch.UserInputState ~= Enum.UserInputState.End then
				setScrollTouchCameraSuppressed(true)
				return
			end
		end
		setScrollTouchCameraSuppressed(false)
	end

	scroll.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch or not self._isOpen then
			return
		end
		scrollTouches[input] = true
		recomputeScrollTouchCamera()
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if not scrollTouches[input] then
			return
		end
		scrollTouches[input] = nil
		recomputeScrollTouchCamera()
	end)

	UserInputService.TouchStarted:Connect(function(_touch, gameProcessedEvent)
		if gameProcessedEvent or not self._isOpen then
			return
		end
		local touch = _touch :: InputObject
		local point = Vector2.new(touch.Position.X, touch.Position.Y)
		if isScrollCapturePoint(point) then
			scrollTouches[touch] = true
			recomputeScrollTouchCamera()
		end
	end)
end

function DancePanelUIBinder:_hideReferenceRows()
	for _, refRow in pairs(self.refs.rowRefs) do
		refRow.Visible = false
	end
end

function DancePanelUIBinder:_bindTabs()
	self.refs.danceTabButton.AutoButtonColor = false
	self.refs.poseTabButton.AutoButtonColor = false
	if self.refs.favoritesTabButton then
		self.refs.favoritesTabButton.AutoButtonColor = false
	end
	bindPressDown(self.refs.danceTabButton, function()
		self:setCategory("Dance")
	end)
	bindPressDown(self.refs.poseTabButton, function()
		self:setCategory("Pose")
	end)
	if self.refs.favoritesTabButton then
		bindPressDown(self.refs.favoritesTabButton, function()
			self:setCategory("Favorites")
		end)
	end
end

function DancePanelUIBinder:_bindSearch()
	self.refs.searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		self._searchQuery = string.lower(self.refs.searchBox.Text)
		self:rebuildList(true)
	end)
end

function DancePanelUIBinder:_bindSyncOverlay()
	self.refs.syncOverlay.Activated:Connect(function()
		if self._unsyncRequested then
			self._unsyncRequested()
		end
	end)
end

function DancePanelUIBinder:_bindPanelDrag()
	local dragTarget = self.refs.draggableFrame:FindFirstChild("DraggableIcon") or self.refs.draggableFrame
	local panelRoot = self.refs.panelRoot

	local function disconnectDrag()
		if self._dragMoveConn then
			self._dragMoveConn:Disconnect()
			self._dragMoveConn = nil
		end
		if self._dragEndConn then
			self._dragEndConn:Disconnect()
			self._dragEndConn = nil
		end
	end

	dragTarget.InputBegan:Connect(function(input)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		disconnectDrag()
		local startInputPosition = input.Position
		local startPanelPosition = panelRoot.Position

		self._dragMoveConn = UserInputService.InputChanged:Connect(function(changedInput: InputObject)
			if
				changedInput.UserInputType ~= Enum.UserInputType.MouseMovement
				and changedInput.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end

			local delta = changedInput.Position - startInputPosition
			panelRoot.Position = UDim2.new(
				startPanelPosition.X.Scale,
				startPanelPosition.X.Offset + delta.X,
				startPanelPosition.Y.Scale,
				startPanelPosition.Y.Offset + delta.Y
			)
		end)

		self._dragEndConn = UserInputService.InputEnded:Connect(function(endedInput)
			if endedInput.UserInputType ~= input.UserInputType then
				return
			end
			self._openPosition = panelRoot.Position
			disconnectDrag()
		end)
	end)
end

function DancePanelUIBinder:_updateSpeedLabels()
	if self.refs.currentSpeedLabel then
		self.refs.currentSpeedLabel.Text = string.format("%.2fx", self._currentSpeed)
	end
	if self.refs.maxSpeedLabel then
		self.refs.maxSpeedLabel.Text = string.format("%.2fx", self.config.MAX_SPEED)
	end
end

function DancePanelUIBinder:_updateSpeedLabelContrast()
	local fill = self.refs.speedFill

	local function applyContrast(label: TextLabel?)
		if not label then
			return
		end

		local isOnLightFill: boolean
		if self.refs.speedSliderVertical then
			local fillTop = fill.AbsolutePosition.Y
			local fillBottom = fillTop + fill.AbsoluteSize.Y
			local labelCenterY = label.AbsolutePosition.Y + (label.AbsoluteSize.Y * 0.5)
			isOnLightFill = labelCenterY >= fillTop and labelCenterY <= fillBottom
		else
			local fillRight = fill.AbsolutePosition.X + fill.AbsoluteSize.X
			local labelCenterX = label.AbsolutePosition.X + (label.AbsoluteSize.X * 0.5)
			isOnLightFill = labelCenterX <= fillRight
		end
		label.TextColor3 = if isOnLightFill then DARK_TEXT_COLOR else LIGHT_TEXT_COLOR
	end

	applyContrast(self.refs.currentSpeedLabel)
	applyContrast(self.refs.maxSpeedLabel)
end

function DancePanelUIBinder:_updateSpeedKnobVisibility()
	if not self:_speedHandleIsKnob() then
		return
	end

	local shouldShow = self._isSliderHovered or self._isSliderDragging
	local speedHandle = self.refs.speedHandle
	local knobScale = self:_ensureSpeedKnobScale()
	if not knobScale then
		return
	end

	self._knobTweenToken += 1
	local token = self._knobTweenToken

	if shouldShow then
		speedHandle.Visible = true
		local tween = TweenService:Create(knobScale, KNOB_POP_TWEEN, {
			Scale = 1,
		})
		tween:Play()
		return
	end

	local tween = TweenService:Create(knobScale, KNOB_HIDE_TWEEN, {
		Scale = 0.82,
	})
	tween.Completed:Once(function()
		if token ~= self._knobTweenToken then
			return
		end
		speedHandle.Visible = false
	end)
	tween:Play()
end

function DancePanelUIBinder:_scheduleSpeedHandleAutoHide()
	self._speedHandleVisibilityToken += 1
	local visibilityToken = self._speedHandleVisibilityToken

	task.delay(SPEED_HANDLE_AUTO_HIDE_DELAY, function()
		if visibilityToken ~= self._speedHandleVisibilityToken then
			return
		end
		if self._isSliderDragging then
			return
		end
		self._isSliderHovered = false
		self:_updateSpeedKnobVisibility()
	end)
end

function DancePanelUIBinder:_setupSpeedSlider()
	local speedFill = self.refs.speedFill
	local speedWrapper = self.refs.speedWrapper
	speedWrapper.Active = true
	speedFill.Active = true

	local speedInputShield = self:_ensureSpeedInputShield()
	local dragTargets = {
		speedInputShield,
	}

	local function disconnectSlider()
		if self._sliderMoveConn then
			self._sliderMoveConn:Disconnect()
			self._sliderMoveConn = nil
		end
		if self._sliderEndConn then
			self._sliderEndConn:Disconnect()
			self._sliderEndConn = nil
		end
		self._isSliderDragging = false
		self:_updateSpeedKnobVisibility()
	end

	local function applyFromInput(position: Vector2, suppressCallback: boolean?)
		local ratio: number
		if self.refs.speedSliderVertical then
			local wrapperAbsPos = speedWrapper.AbsolutePosition.Y
			local wrapperAbsSize = math.max(speedWrapper.AbsoluteSize.Y, 1)
			ratio = clamp((wrapperAbsPos + wrapperAbsSize - position.Y) / wrapperAbsSize, 0, 1)
		else
			local wrapperAbsPos = speedWrapper.AbsolutePosition.X
			local wrapperAbsSize = math.max(speedWrapper.AbsoluteSize.X, 1)
			ratio = clamp((position.X - wrapperAbsPos) / wrapperAbsSize, 0, 1)
		end

		local rawSpeed = self.config.MIN_SPEED + ratio * (self.config.MAX_SPEED - self.config.MIN_SPEED)
		local speed = clamp(roundToStep(rawSpeed, SPEED_STEP), self.config.MIN_SPEED, self.config.MAX_SPEED)
		self._currentSpeed = speed
		local snappedRatio = (speed - self.config.MIN_SPEED)
			/ math.max(self.config.MAX_SPEED - self.config.MIN_SPEED, 0.001)
		self:_applySpeedFillRatio(snappedRatio)
		self:_updateSpeedLabels()
		self:_updateSpeedLabelContrast()

		if not suppressCallback and self._speedChanged then
			self._speedChanged(speed)
		end
	end

	local function beginSliderDrag(input)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		disconnectSlider()
		self._isSliderDragging = true
		self:_updateSpeedKnobVisibility()
		applyFromInput(input.Position)

		self._sliderMoveConn = UserInputService.InputChanged:Connect(function(changedInput)
			if
				changedInput.UserInputType ~= Enum.UserInputType.MouseMovement
				and changedInput.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end
			applyFromInput(changedInput.Position)
		end)

		self._sliderEndConn = UserInputService.InputEnded:Connect(function(endedInput)
			if endedInput.UserInputType ~= input.UserInputType then
				return
			end
			disconnectSlider()
		end)
	end

	for _, target in ipairs(dragTargets) do
		if target and target:IsA("GuiObject") then
			target.InputBegan:Connect(beginSliderDrag)
			target.MouseEnter:Connect(function()
				self._isSliderHovered = true
				self._speedHandleVisibilityToken += 1
				self:_updateSpeedKnobVisibility()
			end)
			target.MouseLeave:Connect(function()
				if self._isSliderDragging then
					return
				end
				self:_scheduleSpeedHandleAutoHide()
			end)
		end
	end

	self:setCurrentSpeed(self.config.DEFAULT_SPEED, true)
end

function DancePanelUIBinder:_bindCustomSpeed()
	local customSpeedField = self.refs.customSpeedField
	if customSpeedField then
		self._customSpeedFocusLostConn = customSpeedField.FocusLost:Connect(function()
			local speedText = customSpeedField.Text:gsub("x", "")
			local speed = tonumber(speedText)
			if not speed then
				customSpeedField.Text = string.format("%.2fx", self._currentSpeed)
				return
			end

			self:setCurrentSpeed(speed)
		end)
	end

	local resetSpeedButton = self.refs.resetSpeedButton
	if resetSpeedButton then
		self._resetSpeedConn = resetSpeedButton.Activated:Connect(function()
			self:setCurrentSpeed(self.config.DEFAULT_SPEED)
		end)
	end
end

function DancePanelUIBinder:_applyTabVisuals()
	local backgroundPill = self.refs.backgroundPill
	local tabButtonOrder = self.refs.tabButtonOrder
	if backgroundPill and tabButtonOrder and #tabButtonOrder > 0 then
		local selectedButton: GuiButton? = nil
		if self._currentCategory == "Dance" then
			selectedButton = self.refs.danceTabButton
		elseif self._currentCategory == "Pose" then
			selectedButton = self.refs.poseTabButton
		elseif self._currentCategory == "Favorites" then
			selectedButton = self.refs.favoritesTabButton
		end

		for _, button in ipairs(tabButtonOrder) do
			SliderSelectorUtil.setTabButtonSelected(button, button == selectedButton)
		end

		if selectedButton then
			task.defer(function()
				if selectedButton.Parent and backgroundPill.Parent then
					SliderSelectorUtil.animateSlidingPill(backgroundPill, selectedButton, tabButtonOrder)
				end
			end)
		end
		return
	end

	local danceStroke = self.refs.danceTabButton:FindFirstChildWhichIsA("UIStroke")
	local poseStroke = self.refs.poseTabButton:FindFirstChildWhichIsA("UIStroke")
	local favoritesStroke = if self.refs.favoritesTabButton
		then self.refs.favoritesTabButton:FindFirstChildWhichIsA("UIStroke")
		else nil
	local danceLabel = getButtonLabel(self.refs.danceTabButton)
	local poseLabel = getButtonLabel(self.refs.poseTabButton)
	local favoritesLabel = if self.refs.favoritesTabButton then getButtonLabel(self.refs.favoritesTabButton) else nil
	local isDance = self._currentCategory == "Dance"
	local isPose = self._currentCategory == "Pose"
	local isFavorites = self._currentCategory == "Favorites"

	setGradientEnabled(self.refs.danceTabButton, { "UIGradient-Gold", "UIGradientGold" }, isDance)
	setGradientEnabled(self.refs.danceTabButton, { "UIGradient-Normal", "UIGradientNormal" }, not isDance)
	setGradientEnabled(self.refs.poseTabButton, { "UIGradient-Silver", "UIGradientSilver" }, isPose)
	setGradientEnabled(self.refs.poseTabButton, { "UIGradient-Normal", "UIGradientNormal" }, not isPose)
	if self.refs.favoritesTabButton then
		setGradientEnabled(self.refs.favoritesTabButton, { "UIGradient-Gold", "UIGradientGold" }, isFavorites)
		setGradientEnabled(self.refs.favoritesTabButton, { "UIGradient-Silver", "UIGradientSilver" }, isFavorites)
		setGradientEnabled(self.refs.favoritesTabButton, { "UIGradient-Normal", "UIGradientNormal" }, not isFavorites)
	end

	if danceStroke then
		danceStroke.Transparency = isDance and 0 or 1
	end
	if poseStroke then
		poseStroke.Transparency = isPose and 0 or 1
	end
	if favoritesStroke then
		favoritesStroke.Transparency = isFavorites and 0 or 1
	end
	if danceLabel then
		danceLabel.TextTransparency = 0
	end
	if poseLabel then
		poseLabel.TextTransparency = 0
	end
	if favoritesLabel then
		favoritesLabel.TextTransparency = 0
	end
end

function DancePanelUIBinder:_getStateReference(animationName: string): GuiButton
	local isFavorited = self._favoritedAnims[animationName] == true
	local isCurrent = self._currentAnimName == animationName

	if isFavorited and isCurrent then
		return self.refs.rowRefs.favoritedPlayed
	end
	if isFavorited then
		return self.refs.rowRefs.favorited
	end
	if isCurrent then
		return self.refs.rowRefs.played
	end
	return self.refs.rowRefs.normal
end

function DancePanelUIBinder:_buildFilteredSource(): { AnimationEntry }
	if self._currentCategory == "Favorites" then
		local filtered = {}
		local addedByName = {}

		for _, source in ipairs({ self._danceAnims, self._poseAnims }) do
			for _, animation in ipairs(source) do
				if not addedByName[animation.Name] and self._favoritedAnims[animation.Name] == true then
					if self._searchQuery == "" or string.find(string.lower(animation.Name), self._searchQuery, 1, true) then
						table.insert(filtered, animation)
						addedByName[animation.Name] = true
					end
				end
			end
		end

		table.sort(filtered, function(a, b)
			return a.Name < b.Name
		end)

		return filtered
	end

	local source = if self._currentCategory == "Pose" then self._poseAnims else self._danceAnims
	local alternateSource = if self._currentCategory == "Pose" then self._danceAnims else self._poseAnims
	local filtered = {}
	local addedByName = {}

	for _, animation in ipairs(source) do
		if self._searchQuery == "" or string.find(string.lower(animation.Name), self._searchQuery, 1, true) then
			table.insert(filtered, animation)
			addedByName[animation.Name] = true
		end
	end

	for _, animation in ipairs(alternateSource) do
		if not addedByName[animation.Name] and self._favoritedAnims[animation.Name] == true then
			if self._searchQuery == "" or string.find(string.lower(animation.Name), self._searchQuery, 1, true) then
				table.insert(filtered, animation)
				addedByName[animation.Name] = true
			end
		end
	end

	-- Sort alphabetical aja. Item favorit TIDAK lagi naik ke atas —
	-- biarin stay di posisi natural-nya. Khusus favorit udah ada tab
	-- sendiri (Favorites) yang nge-handle list dedicated.
	table.sort(filtered, function(a: AnimationEntry, b: AnimationEntry)
		return a.Name < b.Name
	end)

	return filtered
end

function DancePanelUIBinder:_disconnectRowConnections(row: GuiButton)
	local rowConnection = self._rowPressConnections[row]
	if rowConnection then
		rowConnection:Disconnect()
		self._rowPressConnections[row] = nil
	end

	local favoriteConnection = self._favoritePressConnections[row]
	if favoriteConnection then
		favoriteConnection:Disconnect()
		self._favoritePressConnections[row] = nil
	end
end

function DancePanelUIBinder:_stopRowGradient(row: GuiButton)
	local tweens = self._rowGradientTweens[row]
	if not tweens then
		return
	end

	for _, tween in ipairs(tweens) do
		tween:Cancel()
		tween:Destroy()
	end
	self._rowGradientTweens[row] = nil
end

function DancePanelUIBinder:_startRowGradient(row: GuiButton)
	self:_stopRowGradient(row)

	local tweens = {}
	local descendants = self._descendantsCache[row] or row:GetDescendants()
	for _, descendant in ipairs(descendants) do
		if descendant:IsA("UIGradient") and descendant.Enabled then
			local gradient = descendant :: UIGradient
			local tween = TweenService:Create(gradient, ROW_GRADIENT_TWEEN, {
				Rotation = gradient.Rotation + 360,
			})
			tween:Play()
			table.insert(tweens, tween)
		end
	end

	if #tweens > 0 then
		self._rowGradientTweens[row] = tweens
	end
end

function DancePanelUIBinder:_syncRowGradient(row: GuiButton, isSelected: boolean)
	if isSelected then
		self:_startRowGradient(row)
	else
		self:_stopRowGradient(row)
	end
end

function DancePanelUIBinder:_isRowInputAllowed(row: GuiButton, input: InputObject): boolean
	if not self._isOpen then
		return false
	end

	-- InputBegan on `row` already guarantees the input started on the row itself.
	-- Only verify the point is within the visible scroll area.
	local point = getInputPosition(input)
	if not isPointInside(self.refs.mainContent, point) then
		return false
	end
	if isPointInside(self.refs.searchBox, point) then
		return false
	end
	-- Only block the slider knob area (handle ± 10px padding), not the full speed track
	local handle = self.refs.speedHandle
	if handle and handle.Visible then
		local pos = handle.AbsolutePosition
		local size = handle.AbsoluteSize
		local PAD = 10
		if
			point.X >= pos.X - PAD
			and point.X <= pos.X + size.X + PAD
			and point.Y >= pos.Y - PAD
			and point.Y <= pos.Y + size.Y + PAD
		then
			return false
		end
	end

	return true
end

function DancePanelUIBinder:_clearActiveRows()
	-- Release rows back to pool instead of destroying
	for _, row in ipairs(self._activeRows) do
		self:_disconnectRowConnections(row)
		self:_stopRowGradient(row)

		-- Clear descendants cache when releasing
		self._descendantsCache[row] = nil

		if self._rowPool then
			self._rowPool:release(row)
		else
			row:Destroy()
		end
	end
	self._activeRows = {}
	self._activeRowsByName = {}
end

function DancePanelUIBinder:_createRow(animation: AnimationEntry, layoutOrder: number): GuiButton
	-- Acquire row from pool instead of cloning
	local row = self._rowPool:acquire()
	self:_disconnectRowConnections(row)
	row.Name = animation.Name
	row.Visible = true
	row.Active = true
	row.LayoutOrder = layoutOrder
	row.AutoButtonColor = false

	-- Cache descendants for performance (avoid repeated GetDescendants calls)
	-- Store in separate table since we can't add custom properties to Roblox instances
	if not self._descendantsCache[row] then
		self._descendantsCache[row] = row:GetDescendants()
	end

	local label = getRowLabel(row)
	if label then
		label.Text = animation.Name
	end

	self._rowPressConnections[row] = bindPressDown(row, function(input)
		if not self:_isRowInputAllowed(row, input) then
			return
		end
		if self._emoteSelected then
			self._emoteSelected(animation)
		end
	end)

	local favoriteButton = getFavoriteButton(row)
	if favoriteButton then
		favoriteButton.AutoButtonColor = false
		self._favoritePressConnections[row] = bindPressDown(favoriteButton, function(input)
			if not self:_isRowInputAllowed(row, input) then
				return
			end
			if self._favoriteToggled then
				self._favoriteToggled(animation.Name)
			end
		end)
	end

	local badge = getFavoriteBadge(row)
	if badge then
		badge.ImageTransparency = self._favoritedAnims[animation.Name] and 0 or 0.8
	end

	return row
end

function DancePanelUIBinder:_syncRowVisualState(row: GuiButton, animationName: string, animate: boolean?)
	local sourceRef = self:_getStateReference(animationName)

	local sourceBackgroundTransparency = sourceRef.BackgroundTransparency
	local sourceSelectable = row.Selectable
	if animate then
		tweenProperties(row, {
			BackgroundColor3 = sourceRef.BackgroundColor3,
			BackgroundTransparency = sourceBackgroundTransparency,
		})
	else
		row.BackgroundColor3 = sourceRef.BackgroundColor3
		row.BackgroundTransparency = sourceBackgroundTransparency
	end
	row.AutoButtonColor = false
	row.Selectable = sourceSelectable

	-- Use cached descendants instead of calling GetDescendants() every time
	local descendants = self._descendantsCache[row] or row:GetDescendants()
	for _, descendant in ipairs(descendants) do
		if descendant:IsA("UIGradient") or descendant:IsA("UICorner") or descendant:IsA("UIStroke") then
			local templateDescendant = sourceRef:FindFirstChild(descendant.Name, true)
			if templateDescendant and templateDescendant.ClassName == descendant.ClassName then
				if descendant:IsA("UIGradient") and templateDescendant:IsA("UIGradient") then
					descendant.Enabled = templateDescendant.Enabled
					descendant.Color = templateDescendant.Color
					descendant.Transparency = templateDescendant.Transparency
					descendant.Offset = templateDescendant.Offset
					descendant.Rotation = templateDescendant.Rotation
				elseif descendant:IsA("UICorner") and templateDescendant:IsA("UICorner") then
					descendant.CornerRadius = templateDescendant.CornerRadius
				elseif descendant:IsA("UIStroke") and templateDescendant:IsA("UIStroke") then
					descendant.ApplyStrokeMode = templateDescendant.ApplyStrokeMode
					descendant.Enabled = templateDescendant.Enabled
					descendant.LineJoinMode = templateDescendant.LineJoinMode
					if animate then
						tweenProperties(descendant, {
							Color = templateDescendant.Color,
							Thickness = templateDescendant.Thickness,
							Transparency = templateDescendant.Transparency,
						})
					else
						descendant.Color = templateDescendant.Color
						descendant.Thickness = templateDescendant.Thickness
						descendant.Transparency = templateDescendant.Transparency
					end
				end
			end
		elseif
			descendant:IsA("TextLabel")
			or descendant:IsA("TextButton")
			or descendant:IsA("ImageLabel")
			or descendant:IsA("ImageButton")
			or descendant:IsA("Frame")
		then
			local templateDescendant = sourceRef:FindFirstChild(descendant.Name, true)
			if templateDescendant and templateDescendant.ClassName == descendant.ClassName then
				if descendant:IsA("TextLabel") and templateDescendant:IsA("TextLabel") then
					if animate then
						tweenProperties(descendant, {
							BackgroundColor3 = templateDescendant.BackgroundColor3,
							BackgroundTransparency = templateDescendant.BackgroundTransparency,
							TextColor3 = templateDescendant.TextColor3,
							TextTransparency = templateDescendant.TextTransparency,
						})
					else
						descendant.BackgroundColor3 = templateDescendant.BackgroundColor3
						descendant.BackgroundTransparency = templateDescendant.BackgroundTransparency
						descendant.TextColor3 = templateDescendant.TextColor3
						descendant.TextTransparency = templateDescendant.TextTransparency
					end
				elseif descendant:IsA("TextButton") and templateDescendant:IsA("TextButton") then
					if animate then
						tweenProperties(descendant, {
							BackgroundColor3 = templateDescendant.BackgroundColor3,
							BackgroundTransparency = templateDescendant.BackgroundTransparency,
							TextColor3 = templateDescendant.TextColor3,
							TextTransparency = templateDescendant.TextTransparency,
						})
					else
						descendant.BackgroundColor3 = templateDescendant.BackgroundColor3
						descendant.BackgroundTransparency = templateDescendant.BackgroundTransparency
						descendant.TextColor3 = templateDescendant.TextColor3
						descendant.TextTransparency = templateDescendant.TextTransparency
					end
				elseif descendant:IsA("ImageLabel") and templateDescendant:IsA("ImageLabel") then
					descendant.Image = templateDescendant.Image
					if animate then
						tweenProperties(descendant, {
							BackgroundColor3 = templateDescendant.BackgroundColor3,
							BackgroundTransparency = templateDescendant.BackgroundTransparency,
							ImageColor3 = templateDescendant.ImageColor3,
							ImageTransparency = templateDescendant.ImageTransparency,
						}, ROW_IMAGE_TWEEN)
					else
						descendant.BackgroundColor3 = templateDescendant.BackgroundColor3
						descendant.BackgroundTransparency = templateDescendant.BackgroundTransparency
						descendant.ImageColor3 = templateDescendant.ImageColor3
						descendant.ImageTransparency = templateDescendant.ImageTransparency
					end
				elseif descendant:IsA("ImageButton") and templateDescendant:IsA("ImageButton") then
					descendant.BackgroundColor3 = templateDescendant.BackgroundColor3
					descendant.BackgroundTransparency = templateDescendant.BackgroundTransparency
					descendant.Image = templateDescendant.Image
					descendant.ImageColor3 = templateDescendant.ImageColor3
					descendant.ImageTransparency = templateDescendant.ImageTransparency
				elseif descendant:IsA("Frame") and templateDescendant:IsA("Frame") then
					descendant.BackgroundColor3 = templateDescendant.BackgroundColor3
					descendant.BackgroundTransparency = templateDescendant.BackgroundTransparency
				end
			end
		end
	end

	local label = getRowLabel(row)
	if label then
		label.Text = animationName
	end

	local badge = getFavoriteBadge(row)
	if badge then
		local targetTransparency = self._favoritedAnims[animationName] and 0 or 0.8
		if animate then
			tweenProperties(badge, {
				ImageTransparency = targetTransparency,
			}, ROW_FAST_TWEEN)
		else
			badge.ImageTransparency = targetTransparency
		end
	end

	local favoriteButton = getFavoriteButton(row)
	if favoriteButton then
		favoriteButton.AutoButtonColor = false
	end

	self:_syncRowGradient(row, self._currentAnimName == animationName)
end

function DancePanelUIBinder:_resetScrollPosition()
	self.refs.mainContent.CanvasPosition = Vector2.new(0, 0)
end

function DancePanelUIBinder:refreshRowStates()
	for animationName, row in pairs(self._activeRowsByName) do
		if row.Parent then
			self:_syncRowVisualState(row, animationName, true)
		end
	end
end

function DancePanelUIBinder:_setListLoadingPlaceholder(isLoading: boolean)
	if self.refs.searchBox then
		self.refs.searchBox.PlaceholderText = if isLoading
			then "Loading emotes..."
			else if self.refs.searchBox.Text == "" then self._defaultSearchPlaceholder else self.refs.searchBox.PlaceholderText
	end
end

function DancePanelUIBinder:_cancelIncrementalRebuild()
	self._incrementalRebuildGeneration += 1
	local threadHandle = self._incrementalRebuildThread
	self._incrementalRebuildThread = nil
	if threadHandle and threadHandle ~= coroutine.running() then
		pcall(task.cancel, threadHandle)
	end
end

function DancePanelUIBinder:_ensureListBuilt()
	if not self._listDirty then
		return
	end
	self:rebuildListIncremental(true)
end

function DancePanelUIBinder:rebuildListIncremental(resetScroll: boolean?)
	self:_cancelIncrementalRebuild()
	self:_clearActiveRows()
	self._listDirty = false

	local filtered = self:_buildFilteredSource()
	if self.refs.paginationWrapper then
		self.refs.paginationWrapper.Visible = false
	end
	if #filtered == 0 then
		if resetScroll then
			self:_resetScrollPosition()
		end
		return
	end

	self._incrementalRebuildGeneration += 1
	local generation = self._incrementalRebuildGeneration
	self:_setListLoadingPlaceholder(true)

	self._incrementalRebuildThread = task.spawn(function()
		local chunkSize = 12
		local index = 1
		while index <= #filtered do
			if generation ~= self._incrementalRebuildGeneration or not self.refs.mainContent.Parent then
				return
			end
			local chunkEnd = math.min(index + chunkSize - 1, #filtered)
			for rowIndex = index, chunkEnd do
				local animation = filtered[rowIndex]
				local row = self:_createRow(animation, rowIndex)
				self:_syncRowVisualState(row, animation.Name, false)
				row.Parent = self.refs.mainContent
				table.insert(self._activeRows, row)
				self._activeRowsByName[animation.Name] = row
			end
			index = chunkEnd + 1
			task.wait()
		end

		if generation ~= self._incrementalRebuildGeneration then
			return
		end
		self._incrementalRebuildThread = nil
		self:_setListLoadingPlaceholder(false)
		if resetScroll then
			self:_resetScrollPosition()
		end
	end)
end

function DancePanelUIBinder:rebuildList(resetScroll: boolean?)
	if self._isOpen then
		self:rebuildListIncremental(resetScroll)
		return
	end
	self._listDirty = true
end

function DancePanelUIBinder:setCategory(category: string)
	if category ~= "Dance" and category ~= "Pose" and category ~= "Favorites" then
		return
	end

	self._currentCategory = category
	self:_applyTabVisuals()
	self._listDirty = true
	if self._isOpen then
		self:rebuildListIncremental(true)
	end
end

function DancePanelUIBinder:setEmotes(danceAnims: { AnimationEntry }, poseAnims: { AnimationEntry })
	self._danceAnims = danceAnims
	self._poseAnims = poseAnims
	self._catalogReady = true
	self._listDirty = true
end

function DancePanelUIBinder:setFavorites(favorites: { [string]: boolean }, suppressRebuild: boolean?)
	self._favoritedAnims = favorites
	if suppressRebuild == true then
		self._listDirty = true
		if self._isOpen and #self._activeRows > 0 then
			self:refreshRowStates()
		end
		return
	end
	self._listDirty = true
	if self._isOpen then
		self:rebuildListIncremental(false)
	end
end

function DancePanelUIBinder:setPreparingState(isPreparing: boolean)
	self.refs.searchBox.PlaceholderText = if isPreparing
		then self._preparingSearchPlaceholder
		else self._defaultSearchPlaceholder
end

function DancePanelUIBinder:setCurrentAnimName(animName: string?)
	-- Important: Treat empty string as nil (cleared state)
	if animName == "" then
		animName = nil
	end
	self._currentAnimName = animName
	self:refreshRowStates()
end

function DancePanelUIBinder:setCurrentSpeed(speed: number, suppressCallback: boolean?)
	self._currentSpeed = clamp(roundToStep(speed, SPEED_STEP), self.config.MIN_SPEED, self.config.MAX_SPEED)
	local ratio = (self._currentSpeed - self.config.MIN_SPEED)
		/ math.max(self.config.MAX_SPEED - self.config.MIN_SPEED, 0.001)
	self:_applySpeedFillRatio(ratio)
	self:_updateSpeedLabels()
	self:_updateSpeedLabelContrast()
	if self.refs.customSpeedField then
		self.refs.customSpeedField.Text = string.format("%.2fx", self._currentSpeed)
	end

	if not suppressCallback and self._speedChanged then
		self._speedChanged(self._currentSpeed)
	end
end

function DancePanelUIBinder:setSyncOverlay(isVisible: boolean, leaderDisplay: string?, animName: string?)
	self.refs.syncOverlay.Visible = isVisible

	if self.refs.syncLeaderLabel then
		self.refs.syncLeaderLabel.Text = isVisible
				and string.format("Synced to %s", leaderDisplay or "PlayerDisplayName")
			or self.refs.syncLeaderLabel.Text
	end
	if self.refs.syncTapLabel then
		self.refs.syncTapLabel.Text = "Tap to unsync"
	end
	if self.refs.syncAutoRouteLabel then
		self.refs.syncAutoRouteLabel.Text = "Auto re-route lead : ON"
	end

	self:setCurrentAnimName(animName)
end

function DancePanelUIBinder:updateSyncAnimName(animName: string?)
	self:setCurrentAnimName(animName)
end

function DancePanelUIBinder:setOpen(isOpen: boolean, immediate: boolean?)
	self._isOpen = isOpen
	local panelRoot = self.refs.panelRoot
	local animFrame = getPanelAnimFrame(self.refs)
	local panelScale = self:_ensurePanelScale()
	panelScale.Scale = PANEL_OPEN_SCALE
	restoreMobileBakedPanelScale(panelRoot, self.config)

	if immediate then
		panelRoot.Visible = isOpen
		panelRoot.Position = self._openPosition
		panelRoot.AnchorPoint = self._openAnchorPoint
		setPanelAlpha(panelRoot, if isOpen then 0 else 1)
		animFrame.Visible = isOpen
		if isOpen then
			self:_resetScrollPosition()
		end
		restoreMobileBakedPanelScale(panelRoot, self.config)
		return
	end

	if isOpen then
		self:_ensureListBuilt()
		panelRoot.Visible = true
		panelRoot.Position = self._openPosition
		panelRoot.AnchorPoint = self._openAnchorPoint
		setPanelAlpha(panelRoot, 0)
		animFrame.Visible = true
		self._anim:presentCenterPanel(animFrame, function()
			restoreMobileBakedPanelScale(panelRoot, self.config)
			if self._isOpen then
				self:_resetScrollPosition()
				self:_applyTabVisuals()
			end
		end)
		return
	end

	if self._isClosing then
		return
	end
	self._isClosing = true
	animFrame.Visible = true
	self._anim:dismissCenterPanel(animFrame, function()
		self._isClosing = false
		restoreMobileBakedPanelScale(panelRoot, self.config)
		if not self._isOpen then
			panelRoot.Visible = false
			setPanelAlpha(panelRoot, 1)
		end
	end)
end

function DancePanelUIBinder:bindEmoteSelected(callback: (AnimationEntry) -> ())
	self._emoteSelected = callback
end

function DancePanelUIBinder:bindFavoriteToggle(callback: (string) -> ())
	self._favoriteToggled = callback
end

function DancePanelUIBinder:bindSpeedChanged(callback: (number) -> ())
	self._speedChanged = callback
end

function DancePanelUIBinder:bindUnsyncRequested(callback: () -> ())
	self._unsyncRequested = callback
end

function DancePanelUIBinder:destroy()
	self:_cancelIncrementalRebuild()
	-- Cleanup connections
	if self._dragMoveConn then
		self._dragMoveConn:Disconnect()
		self._dragMoveConn = nil
	end
	if self._dragEndConn then
		self._dragEndConn:Disconnect()
		self._dragEndConn = nil
	end
	if self._sliderMoveConn then
		self._sliderMoveConn:Disconnect()
		self._sliderMoveConn = nil
	end
	if self._sliderEndConn then
		self._sliderEndConn:Disconnect()
		self._sliderEndConn = nil
	end
	if self._customSpeedFocusLostConn then
		self._customSpeedFocusLostConn:Disconnect()
		self._customSpeedFocusLostConn = nil
	end
	if self._resetSpeedConn then
		self._resetSpeedConn:Disconnect()
		self._resetSpeedConn = nil
	end

	-- Clear active rows
	self:_clearActiveRows()

	-- Cleanup object pool
	if self._rowPool then
		self._rowPool:destroy()
		self._rowPool = nil
	end

	table.clear(self._rowPressConnections)
	table.clear(self._favoritePressConnections)
	table.clear(self._rowGradientTweens)

	-- Clear descendants cache
	table.clear(self._descendantsCache)
end

return DancePanelUIBinder
