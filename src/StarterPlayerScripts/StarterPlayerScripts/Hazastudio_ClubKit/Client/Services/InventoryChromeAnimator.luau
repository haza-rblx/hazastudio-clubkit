--!strict
-- Client/Services/InventoryChromeAnimator.luau
-- Single owner for hotbar chrome slide + backpack panel present/dismiss.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local cfg = Config.MobilePanelManager
local hotbarCfg = Config.Hotbar

export type ChromeHideReason = "acm" | "cinematic" | "idle"
export type ChromePhase = "visible" | "hiding" | "hidden" | "showing"

export type Callbacks = {
	onChromeHiddenChanged: ((hidden: boolean) -> ())?,
	isBackpackOpen: (() -> boolean)?,
}

local HOTBAR_GUI_NAMES = hotbarCfg.GUI_NAMES
local HOTBAR_FRAME_NAMES = { hotbarCfg.HOTBAR_WRAPPER_NAME, hotbarCfg.STICKER_WRAPPER_NAME }
local HOTBAR_CHROME_ROOT_NAME = hotbarCfg.HOTBAR_CHROME_ROOT_NAME

local InventoryChromeAnimator = {}

local _initialized = false
local _playerGui: PlayerGui? = nil
local _callbacks: Callbacks = {}
local _anim = AnimationHelper.new()

local _hideCounts: { [ChromeHideReason]: number } = {
	acm = 0,
	cinematic = 0,
	idle = 0,
}
local _phase: ChromePhase = "visible"
local _hotbarRunToken = 0
local _backpackRunToken = 0

local _hotbarGui: ScreenGui? = nil
local _hotbarChromeRoot: Frame? = nil
local _hotbarChromeRootBasePosition: UDim2? = nil
local _hotbarChromeRootScale: UIScale? = nil
local _hotbarChromeRootBaseScale = 1

local _backpackFrame: Frame? = nil
local _backpackBasePosition: UDim2? = nil
local _backpackOpen = false

local _idleHideToken = 0
local _backpackSuppressesIdleHide = false
local _idleConnections: { RBXScriptConnection } = {}
local _hotbarChromeTweens: { Tween } = {}
local _hotbarChromePositionTween: Tween? = nil

local function totalHideCount(): number
	local total = 0
	for _, count in pairs(_hideCounts) do
		total += count
	end
	return total
end

local function wantChromeHidden(): boolean
	return totalHideCount() > 0
end

local function mirrorStore(hidden: boolean): ()
	local onChanged = _callbacks.onChromeHiddenChanged
	if onChanged ~= nil then
		onChanged(hidden)
	end
end

local function offsetPosition(base: UDim2, yOffset: number): UDim2
	return UDim2.new(
		base.X.Scale,
		base.X.Offset,
		base.Y.Scale,
		base.Y.Offset + yOffset
	)
end

local function cancelHotbarChromeTweens(): ()
	for _, activeTween in ipairs(_hotbarChromeTweens) do
		activeTween:Cancel()
	end
	table.clear(_hotbarChromeTweens)
	_hotbarChromePositionTween = nil
end

local function playHotbarChromeTween(instance: Instance, info: TweenInfo, goals: { [string]: any }): Tween
	local created = TweenService:Create(instance, info, goals)
	table.insert(_hotbarChromeTweens, created)
	created:Play()
	return created
end

local function hotbarHideTweenInfo(): TweenInfo
	return TweenInfo.new(cfg.HOTBAR_HIDE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
end

local function hotbarShowTweenInfo(): TweenInfo
	return TweenInfo.new(cfg.HOTBAR_SHOW_DURATION, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
end

local function findHotbarGui(): ScreenGui?
	local pg = _playerGui
	if pg == nil then
		return nil
	end
	for _, name in ipairs(HOTBAR_GUI_NAMES) do
		local found = pg:FindFirstChild(name)
		if found ~= nil and found:IsA("ScreenGui") then
			return found :: ScreenGui
		end
	end
	return nil
end

local function findScreenHotbarListLayout(hotbarGui: Instance): UIListLayout?
	for _, child in ipairs(hotbarGui:GetChildren()) do
		if child:IsA("UIListLayout") then
			return child :: UIListLayout
		end
	end
	return nil
end

local function setHotbarChromeChildrenVisible(visible: boolean): ()
	local host = _hotbarChromeRoot or _hotbarGui
	if host == nil then
		return
	end
	for _, frameName in ipairs(HOTBAR_FRAME_NAMES) do
		local frame = host:FindFirstChild(frameName, true)
		if frame ~= nil and frame:IsA("GuiObject") then
			(frame :: GuiObject).Visible = visible
		end
	end
end

--- Wrap HotbarWrapper + StickerButtonWrapper (and screen UIListLayout) under one root we tween.
local function ensureHotbarChromeRoot(): boolean
	if _hotbarChromeRoot ~= nil and _hotbarChromeRoot.Parent ~= nil then
		return true
	end

	local hotbarGui = _hotbarGui or findHotbarGui()
	if hotbarGui == nil then
		return false
	end
	_hotbarGui = hotbarGui

	local wrapper = hotbarGui:FindFirstChild(hotbarCfg.HOTBAR_WRAPPER_NAME, true)
	local sticker = hotbarGui:FindFirstChild(hotbarCfg.STICKER_WRAPPER_NAME, true)
	if wrapper == nil or sticker == nil or not wrapper:IsA("GuiObject") or not sticker:IsA("GuiObject") then
		return false
	end
	local wrapperGui = wrapper :: GuiObject
	local stickerGui = sticker :: GuiObject

	local root = hotbarGui:FindFirstChild(HOTBAR_CHROME_ROOT_NAME)
	if root == nil or not root:IsA("Frame") then
		local layout = findScreenHotbarListLayout(hotbarGui)
		local chromeRoot = Instance.new("Frame")
		chromeRoot.Name = HOTBAR_CHROME_ROOT_NAME
		chromeRoot.BackgroundTransparency = 1
		chromeRoot.BorderSizePixel = 0
		chromeRoot.AutomaticSize = Enum.AutomaticSize.XY
		chromeRoot.AnchorPoint = wrapperGui.AnchorPoint
		chromeRoot.Position = wrapperGui.Position
		chromeRoot.Parent = hotbarGui

		if layout ~= nil then
			layout.Parent = chromeRoot
		end
		wrapperGui.Parent = chromeRoot
		stickerGui.Parent = chromeRoot
		root = chromeRoot
	elseif wrapperGui.Parent ~= root then
		local layout = findScreenHotbarListLayout(hotbarGui)
		if layout ~= nil and layout.Parent ~= root then
			layout.Parent = root
		end
		if wrapperGui.Parent ~= root then
			wrapperGui.Parent = root
		end
		if stickerGui.Parent ~= root then
			stickerGui.Parent = root
		end
	end

	_hotbarChromeRoot = root :: Frame
	if _hotbarChromeRootBasePosition == nil then
		_hotbarChromeRootBasePosition = _hotbarChromeRoot.Position
	end

	local scale = _hotbarChromeRoot:FindFirstChildWhichIsA("UIScale")
	if scale == nil then
		scale = Instance.new("UIScale")
		scale.Scale = 1
		scale.Parent = _hotbarChromeRoot
	end
	_hotbarChromeRootScale = scale :: UIScale
	_hotbarChromeRootBaseScale = (_hotbarChromeRootScale :: UIScale).Scale

	return true
end

local function resolveBackpackFrame(): boolean
	local pg = _playerGui
	if pg == nil then
		return false
	end

	local root = pg:FindFirstChild(Config.Backpack.GUI_NAME)
	if root == nil then
		root = pg:FindFirstChild(Config.Backpack.GUI_NAME, true)
	end
	if root == nil or not root:IsA("ScreenGui") then
		return false
	end

	local wrapper = root:FindFirstChild(Config.Backpack.WRAPPER_NAME, true)
	if wrapper == nil or not wrapper:IsA("Frame") then
		return false
	end

	_backpackFrame = wrapper :: Frame
	if _backpackBasePosition == nil then
		_backpackBasePosition = wrapper.Position
	end
	return true
end

local function prepareBackpackForChromeSlide(): ()
	if not resolveBackpackFrame() or _backpackFrame == nil then
		return
	end
	_backpackRunToken += 1
	local frame = _backpackFrame
	_anim:cancelPanel(frame)
	local basePos = _backpackBasePosition or frame.Position
	_backpackBasePosition = basePos
	frame.Position = basePos
end

local function isBackpackOpenFromStore(): boolean
	local fn = _callbacks.isBackpackOpen
	if fn ~= nil then
		return fn()
	end
	return _backpackOpen
end

local function finishHotbarPhase(target: ChromePhase): ()
	_phase = target
	mirrorStore(wantChromeHidden())
end

local function tweenBackpackChrome(
	frame: Frame,
	basePos: UDim2,
	info: TweenInfo,
	yOffset: number
): ()
	frame.Visible = true
	playHotbarChromeTween(frame, info, {
		Position = offsetPosition(basePos, yOffset),
	})
end

local function hideHotbarChrome(): ()
	if not ensureHotbarChromeRoot() or _hotbarChromeRoot == nil or _hotbarChromeRootBasePosition == nil then
		_phase = "hidden"
		mirrorStore(true)
		return
	end

	_hotbarRunToken += 1
	local token = _hotbarRunToken
	_phase = "hiding"
	cancelHotbarChromeTweens()

	local root = _hotbarChromeRoot :: Frame
	local trueBase = _hotbarChromeRootBasePosition :: UDim2
	local scale = _hotbarChromeRootScale
	local baseScale = _hotbarChromeRootBaseScale
	local hideInfo = hotbarHideTweenInfo()
	local hideScale = cfg.HOTBAR_SHOW_START_SCALE or 0.96
	local slideOffset = cfg.HOTBAR_SLIDE_OFFSET
	local includeBackpack = isBackpackOpenFromStore()
	if includeBackpack then
		prepareBackpackForChromeSlide()
	end

	root.Visible = true
	setHotbarChromeChildrenVisible(true)
	_hotbarChromePositionTween = playHotbarChromeTween(root, hideInfo, {
		Position = offsetPosition(trueBase, slideOffset),
	})
	if scale ~= nil then
		playHotbarChromeTween(scale, hideInfo, {
			Scale = baseScale * hideScale,
		})
	end

	if includeBackpack and _backpackFrame ~= nil and _backpackBasePosition ~= nil then
		local frame = _backpackFrame
		local basePos = _backpackBasePosition :: UDim2
		tweenBackpackChrome(frame, basePos, hideInfo, slideOffset)
		task.delay(cfg.HOTBAR_HIDE_DURATION, function()
			if token ~= _hotbarRunToken then
				return
			end
			if frame.Parent ~= nil and wantChromeHidden() then
				frame.Visible = false
			end
		end)
	end

	local positionTween = _hotbarChromePositionTween
	if positionTween ~= nil then
		positionTween.Completed:Connect(function()
			if token ~= _hotbarRunToken or not wantChromeHidden() then
				return
			end
			root.Visible = false
			finishHotbarPhase("hidden")
		end)
	else
		task.delay(cfg.HOTBAR_HIDE_DURATION, function()
			if token ~= _hotbarRunToken or not wantChromeHidden() then
				return
			end
			root.Visible = false
			finishHotbarPhase("hidden")
		end)
	end
end

local function showHotbarChrome(): ()
	if not ensureHotbarChromeRoot() or _hotbarChromeRoot == nil or _hotbarChromeRootBasePosition == nil then
		_phase = "visible"
		mirrorStore(false)
		return
	end

	_hotbarRunToken += 1
	local token = _hotbarRunToken
	_phase = "showing"
	mirrorStore(false)
	cancelHotbarChromeTweens()

	local includeBackpack = isBackpackOpenFromStore()
	if includeBackpack then
		prepareBackpackForChromeSlide()
	end

	if token ~= _hotbarRunToken or wantChromeHidden() then
		if wantChromeHidden() then
			finishHotbarPhase("hidden")
		end
		return
	end

	local root = _hotbarChromeRoot :: Frame
	local trueBase = _hotbarChromeRootBasePosition :: UDim2
	local scale = _hotbarChromeRootScale
	local baseScale = _hotbarChromeRootBaseScale
	local showInfo = hotbarShowTweenInfo()
	local showStartScale = cfg.HOTBAR_SHOW_START_SCALE or 0.96
	local slideOffset = cfg.HOTBAR_SLIDE_OFFSET

	root.Position = offsetPosition(trueBase, slideOffset)
	root.Visible = true
	setHotbarChromeChildrenVisible(true)
	if scale ~= nil then
		scale.Scale = baseScale * showStartScale
		playHotbarChromeTween(scale, showInfo, { Scale = baseScale })
	end
	_hotbarChromePositionTween = playHotbarChromeTween(root, showInfo, { Position = trueBase })

	if includeBackpack and _backpackFrame ~= nil and _backpackBasePosition ~= nil then
		local frame = _backpackFrame
		local basePos = _backpackBasePosition :: UDim2
		frame.Position = offsetPosition(basePos, slideOffset)
		frame.Visible = true
		playHotbarChromeTween(frame, showInfo, { Position = basePos })
	end

	local positionTween = _hotbarChromePositionTween
	if positionTween ~= nil then
		positionTween.Completed:Connect(function()
			if token ~= _hotbarRunToken then
				return
			end
			if wantChromeHidden() then
				finishHotbarPhase("hidden")
				return
			end
			finishHotbarPhase("visible")
		end)
	else
		task.delay(cfg.HOTBAR_SHOW_DURATION, function()
			if token ~= _hotbarRunToken then
				return
			end
			if wantChromeHidden() then
				finishHotbarPhase("hidden")
				return
			end
			finishHotbarPhase("visible")
		end)
	end
end

local function forceShowHotbarChrome(): ()
	_phase = "hidden"
	showHotbarChrome()
end

local function reconcileHotbarChrome(): ()
	local hidden = wantChromeHidden()
	if hidden then
		if _phase == "hidden" or _phase == "hiding" then
			return
		end
		hideHotbarChrome()
		return
	end

	if _phase == "visible" or _phase == "showing" then
		return
	end
	showHotbarChrome()
end

function InventoryChromeAnimator._presentBackpackPanel(): ()
	if wantChromeHidden() then
		return
	end
	if not resolveBackpackFrame() or _backpackFrame == nil then
		return
	end
	_backpackRunToken += 1
	local frame = _backpackFrame
	frame.Visible = true
	_anim:presentPanel(frame, nil)
end

function InventoryChromeAnimator._dismissBackpackPanel(): ()
	if not resolveBackpackFrame() or _backpackFrame == nil then
		return
	end
	_backpackRunToken += 1
	local token = _backpackRunToken
	local frame = _backpackFrame
	_anim:dismissPanel(frame, function()
		if token ~= _backpackRunToken then
			return
		end
	end)
end

local function applyBackpackPanelVisual(open: boolean): ()
	_backpackOpen = open
	if wantChromeHidden() then
		if not open and _backpackFrame ~= nil and _backpackFrame.Parent ~= nil then
			_backpackFrame.Visible = false
		end
		return
	end
	if open then
		InventoryChromeAnimator._presentBackpackPanel()
	else
		InventoryChromeAnimator._dismissBackpackPanel()
	end
end

local function scheduleIdleHide(): ()
	if cfg.HOTBAR_IDLE_HIDE_ENABLED ~= true then
		return
	end
	if _backpackSuppressesIdleHide then
		return
	end
	_idleHideToken += 1
	local token = _idleHideToken
	local timeout = cfg.HOTBAR_IDLE_TIMEOUT or 3
	task.delay(timeout, function()
		if _idleHideToken ~= token then
			return
		end
		if not wantChromeHidden() and not _backpackSuppressesIdleHide then
			InventoryChromeAnimator.notifyHide("idle")
		end
	end)
end

function InventoryChromeAnimator.init(playerGui: PlayerGui): ()
	if _initialized then
		return
	end
	_initialized = true
	_playerGui = playerGui
end

function InventoryChromeAnimator.setCallbacks(callbacks: Callbacks): ()
	_callbacks = callbacks
end

function InventoryChromeAnimator.getPhase(): ChromePhase
	return _phase
end

function InventoryChromeAnimator.isChromeHidden(): boolean
	return wantChromeHidden()
end

function InventoryChromeAnimator.isAnimating(): boolean
	return _phase == "hiding" or _phase == "showing"
end

function InventoryChromeAnimator.notifyHide(reason: ChromeHideReason): ()
	local count = _hideCounts[reason] or 0
	if count > 0 and (reason == "idle" or reason == "acm") then
		return
	end
	_hideCounts[reason] = count + 1
	reconcileHotbarChrome()
end

function InventoryChromeAnimator.notifyShow(reason: ChromeHideReason): ()
	local count = _hideCounts[reason] or 0
	if count <= 0 then
		return
	end
	_hideCounts[reason] = count - 1
	reconcileHotbarChrome()
end

function InventoryChromeAnimator.onCinematicSessionEnd(): ()
	_hideCounts.cinematic = 0
	if (_hideCounts.idle or 0) > 0 then
		_hideCounts.idle = 0
		_idleHideToken += 1
	end
	mirrorStore(wantChromeHidden())
	if wantChromeHidden() then
		reconcileHotbarChrome()
		return
	end
	forceShowHotbarChrome()
	scheduleIdleHide()
end

function InventoryChromeAnimator.setBackpackOpen(open: boolean): ()
	if open then
		_backpackSuppressesIdleHide = true
		_idleHideToken += 1
		if (_hideCounts.idle or 0) > 0 then
			InventoryChromeAnimator.notifyShow("idle")
		end
	else
		_backpackSuppressesIdleHide = false
		if not wantChromeHidden() then
			scheduleIdleHide()
		end
	end

	applyBackpackPanelVisual(open)
end

function InventoryChromeAnimator.setupAcmWatcher(): ()
	local pg = _playerGui
	if pg == nil then
		return
	end
	task.spawn(function()
		local acmGui = pg:WaitForChild("AvatarContextMenu", 30)
		if acmGui == nil then
			return
		end
		local mainWrapper = acmGui:FindFirstChild("MainWrapper")
		if mainWrapper == nil or not mainWrapper:IsA("GuiObject") then
			return
		end
		local mw = mainWrapper :: GuiObject
		table.insert(
			_idleConnections,
			mw:GetPropertyChangedSignal("Visible"):Connect(function()
				if mw.Visible then
					if (_hideCounts.acm or 0) <= 0 then
						InventoryChromeAnimator.notifyHide("acm")
					end
				else
					InventoryChromeAnimator.notifyShow("acm")
				end
			end)
		)
	end)
end

function InventoryChromeAnimator.setupDesktopIdle(): ()
	if cfg.HOTBAR_IDLE_HIDE_ENABLED ~= true then
		return
	end

	local function onActivity()
		if _backpackSuppressesIdleHide then
			return
		end
		InventoryChromeAnimator.notifyShow("idle")
		scheduleIdleHide()
	end

	table.insert(_idleConnections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1
			or t == Enum.UserInputType.MouseButton2
			or t == Enum.UserInputType.MouseButton3
			or t == Enum.UserInputType.Keyboard
		then
			onActivity()
		end
	end))

	table.insert(_idleConnections, UserInputService.InputChanged:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			onActivity()
		end
	end))

	scheduleIdleHide()
end

function InventoryChromeAnimator.destroy(): ()
	_hotbarRunToken += 1
	_backpackRunToken += 1
	cancelHotbarChromeTweens()
	for _, conn in ipairs(_idleConnections) do
		conn:Disconnect()
	end
	table.clear(_idleConnections)
	_hideCounts.acm = 0
	_hideCounts.cinematic = 0
	_hideCounts.idle = 0
	_phase = "visible"
	_backpackOpen = false
	_backpackSuppressesIdleHide = false
	_idleHideToken += 1
	_callbacks = {}
	_playerGui = nil
	_hotbarGui = nil
	_hotbarChromeRoot = nil
	_hotbarChromeRootBasePosition = nil
	_hotbarChromeRootScale = nil
	_hotbarChromeRootBaseScale = 1
	_initialized = false
	_backpackFrame = nil
	_backpackBasePosition = nil
end

return InventoryChromeAnimator
