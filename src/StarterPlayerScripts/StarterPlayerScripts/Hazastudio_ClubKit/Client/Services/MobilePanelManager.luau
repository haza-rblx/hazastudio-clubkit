--!strict
-- Client/Services/MobilePanelManager.luau
-- Exclusive-panel focus system for mobile devices.
-- Inventory chrome animation is delegated to InventoryChromeAnimator.

local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local InventoryChromeAnimator = require(script.Parent.InventoryChromeAnimator)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

local log = Logger.new("MobilePanelManager")
local cfg = Config.MobilePanelManager

local NEVER_HIDE: { [string]: boolean } = {
	["MobilePanelOverlay"] = true,
	["00-LoadingScreen"] = true,
	["99-NotificationCenter"] = true,
}

type GuiState = { enabled: boolean, displayOrder: number, ignoreGuiInset: boolean }
export type ChromeHideReason = InventoryChromeAnimator.ChromeHideReason
type InventoryChromeCallbacks = {
	onHiddenChanged: ((hidden: boolean) -> ())?,
	isBackpackOpen: (() -> boolean)?,
}

local _initialized = false
local _playerGui: PlayerGui? = nil
local _registry: { [string]: string } = {}
local _closeCallbacks: { [string]: () -> () } = {}
local _savedAll: { [string]: GuiState } = {}
local _activePanelId: string? = nil
local _overlayGui: ScreenGui? = nil
local _overlayFrame: Frame? = nil
local _overlayButton: TextButton? = nil
local _overlayTween: Tween? = nil
local _connections: { RBXScriptConnection } = {}

local function isMobile(): boolean
	if not UserInputService.TouchEnabled then
		return false
	end
	if UserInputService.KeyboardEnabled then
		return false
	end
	if RunService:IsStudio() then
		return true
	end
	local vp = workspace.CurrentCamera.ViewportSize
	return math.min(vp.X, vp.Y) < cfg.TABLET_MIN_SHORT_SIDE
end

local function showOverlay(): ()
	local frame = _overlayFrame
	local gui = _overlayGui
	if frame == nil or gui == nil then
		return
	end
	gui.Enabled = true
	if _overlayTween ~= nil then
		_overlayTween:Cancel()
	end
	_overlayTween = TweenService:Create(
		frame,
		TweenInfo.new(cfg.OVERLAY_TWEEN_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = cfg.OVERLAY_TRANSPARENCY }
	)
	_overlayTween:Play()
end

local function hideOverlay(): ()
	local frame = _overlayFrame
	local gui = _overlayGui
	if frame == nil or gui == nil then
		return
	end
	if _overlayTween ~= nil then
		_overlayTween:Cancel()
	end
	local tween = TweenService:Create(
		frame,
		TweenInfo.new(cfg.OVERLAY_TWEEN_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)
	tween.Completed:Once(function()
		if gui ~= nil then
			gui.Enabled = false
		end
	end)
	_overlayTween = tween
	tween:Play()
end

local function setRobloxTopbarEnabled(enabled: boolean)
	pcall(function()
		StarterGui:SetCore("TopbarEnabled", enabled)
	end)
end

local MobilePanelManager = {}

function MobilePanelManager.register(id: string, guiName: string, onClose: (() -> ())?): ()
	_registry[id] = guiName
	if onClose ~= nil then
		_closeCallbacks[id] = onClose
	end
end

function MobilePanelManager.open(id: string): ()
	if not isMobile() then
		return
	end
	local activeGuiName = _registry[id]
	if activeGuiName == nil then
		log:warn("open() called for unregistered panel", { id = id })
		return
	end
	local pg = _playerGui
	if pg == nil then
		return
	end
	if _activePanelId == nil then
		table.clear(_savedAll)
		for _, child in ipairs(pg:GetChildren()) do
			if child:IsA("ScreenGui") then
				_savedAll[child.Name] = {
					enabled = child.Enabled,
					displayOrder = child.DisplayOrder,
					ignoreGuiInset = child.IgnoreGuiInset,
				}
			end
		end
		setRobloxTopbarEnabled(false)
	end
	_activePanelId = id
	for _, child in ipairs(pg:GetChildren()) do
		if not child:IsA("ScreenGui") then
			continue
		end
		if NEVER_HIDE[child.Name] then
			continue
		end
		local gui = child :: ScreenGui
		if child.Name == activeGuiName then
			gui.Enabled = true
			gui.DisplayOrder = cfg.OVERLAY_DISPLAY_ORDER + 1
			gui.IgnoreGuiInset = true
		else
			gui.Enabled = false
		end
	end
	showOverlay()
	log:info("Panel opened", { id = id })
end

function MobilePanelManager.close(id: string): ()
	if not isMobile() then
		return
	end
	if _activePanelId ~= id then
		return
	end
	_activePanelId = nil
	local pg = _playerGui
	if pg ~= nil then
		for _, child in ipairs(pg:GetChildren()) do
			if not child:IsA("ScreenGui") then
				continue
			end
			if NEVER_HIDE[child.Name] then
				continue
			end
			local saved = _savedAll[child.Name]
			if saved ~= nil then
				local gui = child :: ScreenGui
				gui.Enabled = saved.enabled
				gui.DisplayOrder = saved.displayOrder
				gui.IgnoreGuiInset = saved.ignoreGuiInset
			end
		end
	end
	table.clear(_savedAll)
	setRobloxTopbarEnabled(true)
	hideOverlay()
	log:info("Panel closed", { id = id })
end

function MobilePanelManager.setInventoryChromeCallbacks(callbacks: InventoryChromeCallbacks): ()
	InventoryChromeAnimator.setCallbacks({
		onChromeHiddenChanged = callbacks.onHiddenChanged,
		isBackpackOpen = callbacks.isBackpackOpen,
	})
end

function MobilePanelManager.isInventoryChromeHidden(): boolean
	return InventoryChromeAnimator.isChromeHidden()
end

function MobilePanelManager.isInventoryChromeAnimating(): boolean
	return InventoryChromeAnimator.isAnimating()
end

function MobilePanelManager.getInventoryChromePhase(): InventoryChromeAnimator.ChromePhase
	return InventoryChromeAnimator.getPhase()
end

function MobilePanelManager.setBackpackOpen(open: boolean): ()
	InventoryChromeAnimator.setBackpackOpen(open)
end

function MobilePanelManager.animateBackpackPanel(open: boolean): ()
	MobilePanelManager.setBackpackOpen(open)
end

function MobilePanelManager.notifyInventoryChromeHide(reason: ChromeHideReason): ()
	InventoryChromeAnimator.notifyHide(reason)
end

function MobilePanelManager.notifyInventoryChromeShow(reason: ChromeHideReason): ()
	InventoryChromeAnimator.notifyShow(reason)
end

function MobilePanelManager.notifyCinematicSessionEnd(): ()
	InventoryChromeAnimator.onCinematicSessionEnd()
end

function MobilePanelManager.notifyAcmOpen(): number
	-- ACM watcher only fires when count is zero; keep duration contract for callers.
	InventoryChromeAnimator.notifyHide("acm")
	return cfg.HOTBAR_HIDE_DURATION
end

function MobilePanelManager.notifyAcmClose(): ()
	InventoryChromeAnimator.notifyShow("acm")
end

function MobilePanelManager.notifyIdleHide(): ()
	InventoryChromeAnimator.notifyHide("idle")
end

function MobilePanelManager.notifyIdleShow(): ()
	InventoryChromeAnimator.notifyShow("idle")
end

function MobilePanelManager.notifyBackpackOpen(): ()
	MobilePanelManager.setBackpackOpen(true)
end

function MobilePanelManager.notifyBackpackClose(): ()
	MobilePanelManager.setBackpackOpen(false)
end

function MobilePanelManager.init(playerGui: PlayerGui): ()
	if _initialized then
		return
	end
	_initialized = true
	_playerGui = playerGui

	InventoryChromeAnimator.init(playerGui)
	InventoryChromeAnimator.setupAcmWatcher()

	if not isMobile() then
		if cfg.HOTBAR_IDLE_HIDE_ENABLED == true then
			InventoryChromeAnimator.setupDesktopIdle()
		end
		log:info("MobilePanelManager initialized for ACM hotbar focus")
		return
	end

	local overlayGui = Instance.new("ScreenGui")
	overlayGui.Name = "MobilePanelOverlay"
	overlayGui.DisplayOrder = cfg.OVERLAY_DISPLAY_ORDER
	overlayGui.ResetOnSpawn = false
	overlayGui.IgnoreGuiInset = true
	overlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local overlayFrame = Instance.new("Frame")
	overlayFrame.Size = UDim2.fromScale(1, 1)
	overlayFrame.BackgroundColor3 = Color3.new(0, 0, 0)
	overlayFrame.BackgroundTransparency = 1
	overlayFrame.BorderSizePixel = 0
	overlayFrame.ZIndex = 1
	overlayFrame.Parent = overlayGui

	local overlayButton = Instance.new("TextButton")
	overlayButton.Size = UDim2.fromScale(1, 1)
	overlayButton.BackgroundTransparency = 1
	overlayButton.Text = ""
	overlayButton.ZIndex = 2
	overlayButton.Parent = overlayGui

	table.insert(
		_connections,
		overlayButton.Activated:Connect(function()
			local activeId = _activePanelId
			if activeId == nil then
				return
			end
			MobilePanelManager.close(activeId)
			local cb = _closeCallbacks[activeId]
			if cb ~= nil then
				cb()
			end
		end)
	)

	overlayGui.Enabled = false
	overlayGui.Parent = playerGui
	_overlayGui = overlayGui
	_overlayFrame = overlayFrame
	_overlayButton = overlayButton

	log:info("MobilePanelManager initialized")
end

function MobilePanelManager.destroy(): ()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)
	if _overlayTween ~= nil then
		_overlayTween:Cancel()
		_overlayTween = nil
	end
	if _overlayGui ~= nil then
		_overlayGui:Destroy()
		_overlayGui = nil
		_overlayFrame = nil
		_overlayButton = nil
	end
	table.clear(_registry)
	table.clear(_closeCallbacks)
	table.clear(_savedAll)
	InventoryChromeAnimator.destroy()
	_activePanelId = nil
	_playerGui = nil
	_initialized = false
end

return MobilePanelManager
