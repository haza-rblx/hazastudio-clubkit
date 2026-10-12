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
	[Config.NotificationCenter.GUI_NAME] = true,
	[Config.NotificationCenter.GUI_NAME_V2] = true,
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
-- Watchdog state for the active panel (see watchActivePanel).
local _activeOpenedAt = 0
local _activeSeenVisible = false
local _activeHiddenSince: number? = nil
local _lastWatchAt = 0

-- Seconds a panel may take to show itself after open(), how long it must stay hidden before the
-- focus is released, and how often the watchdog looks.
local WATCH_SHOW_GRACE = 3
local WATCH_HIDDEN_HOLD = 0.6
local WATCH_INTERVAL = 0.15

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
	-- Cancel before enabling: a dismissal still in flight fires its Completed(Cancelled) the
	-- moment it is cancelled, and that handler switches the GUI off. Cancelling first keeps the
	-- re-show authoritative — open(B) over open(A) does exactly that, and the overlay used to
	-- end up invisible behind the new panel (2026-10-12).
	if _overlayTween ~= nil then
		_overlayTween:Cancel()
		_overlayTween = nil
	end
	gui.Enabled = true
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
		_overlayTween = nil
	end
	local tween = TweenService:Create(
		frame,
		TweenInfo.new(cfg.OVERLAY_TWEEN_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)
	tween.Completed:Once(function(state)
		-- A cancelled dismissal must not switch the GUI off: the tween it abandoned was
		-- replaced by a re-show (open over open), and that one owns the overlay now.
		if state == Enum.PlaybackState.Completed and gui ~= nil then
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
	-- Nested open: a menu row (or any second entry point) opens another panel while this one still
	-- holds focus. Focus is exclusive, so the old panel closes for real first — restoring every GUI
	-- and telling the old panel's controller to drop its icon — before the new snapshot is taken.
	-- Without this the new panel overwrote _activePanelId, close() on the old id early-returned,
	-- and the stale selection kept the other GUIs hidden until the watchdog noticed (2026-10-12).
	local previousId = _activePanelId
	if previousId ~= nil and previousId ~= id then
		MobilePanelManager.close(previousId)
		local previousClose = _closeCallbacks[previousId]
		if previousClose ~= nil then
			-- Deferred: the callback deselects an icon, whose deselected handler calls close()
			-- again. By then _activePanelId is the new panel, so that call is a no-op.
			task.spawn(previousClose)
		end
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
	_activeOpenedAt = os.clock()
	_activeSeenVisible = false
	_activeHiddenSince = nil
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

-- Panels close through many paths (their own X, a menu row, a remote, a timeout) and not all of
-- them reach close(): the focus used to follow the hidden TopbarPlus trigger icon, so a panel shut
-- by its own X left every other GUI disabled for good (owner 2026-10-09: couple, gift, settings).
-- The watchdog releases the focus once the active panel's ScreenGui shows nothing for a moment,
-- whatever path closed it. A panel that never shows within WATCH_SHOW_GRACE is released too.
-- "Visible" alone is not enough: some panels leave a transparent shell frame Visible (e.g.
-- 09-DonationSystemGUI.InputCustomMessageModal) while nothing of it is drawn. A panel counts as
-- showing only when something in it is actually painted on screen.
local OPAQUE = 0.98

local function paints(obj: GuiObject): boolean
	if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
		local image = obj :: any
		if image.Image ~= "" and image.ImageTransparency < OPAQUE then
			return true
		end
	elseif obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
		local text = obj :: any
		if text.Text ~= "" and text.TextTransparency < OPAQUE then
			return true
		end
	end
	return obj.BackgroundTransparency < OPAQUE
end

local function showing(obj: Instance, viewport: Vector2, depth: number): boolean
	if not obj:IsA("GuiObject") then
		return false
	end
	local gui = obj :: GuiObject
	if not gui.Visible then
		return false
	end
	if gui:IsA("CanvasGroup") and (gui :: CanvasGroup).GroupTransparency >= OPAQUE then
		return false
	end
	local pos, size = gui.AbsolutePosition, gui.AbsoluteSize
	if size.X < 2 or size.Y < 2 then
		return false
	end
	-- Off screen (parked panels) does not count. AbsolutePosition ignores the topbar inset, so
	-- allow a generous band above the top edge.
	if pos.X > viewport.X or pos.Y > viewport.Y or pos.X + size.X < 0 or pos.Y + size.Y < -80 then
		return false
	end
	if paints(gui) then
		return true
	end
	if depth <= 0 then
		return false
	end
	for _, child in ipairs(gui:GetChildren()) do
		if showing(child, viewport, depth - 1) then
			return true
		end
	end
	return false
end

local function hasVisibleContent(gui: ScreenGui): boolean
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(4096, 4096)
	for _, child in ipairs(gui:GetChildren()) do
		if showing(child, viewport, 8) then
			return true
		end
	end
	return false
end

local function watchActivePanel(): ()
	local id = _activePanelId
	local pg = _playerGui
	if id == nil or pg == nil then
		return
	end
	local now = os.clock()
	if now - _lastWatchAt < WATCH_INTERVAL then
		return
	end
	_lastWatchAt = now
	local guiName = _registry[id]
	local gui = if guiName then pg:FindFirstChild(guiName) else nil
	local showing = gui ~= nil and gui:IsA("ScreenGui") and gui.Enabled and hasVisibleContent(gui)
	if showing then
		_activeSeenVisible = true
		_activeHiddenSince = nil
		return
	end
	if not _activeSeenVisible and now - _activeOpenedAt < WATCH_SHOW_GRACE then
		return
	end
	if _activeHiddenSince == nil then
		_activeHiddenSince = now
		return
	end
	if now - _activeHiddenSince < WATCH_HIDDEN_HOLD then
		return
	end
	log:info("Panel focus released by watchdog", { id = id, seenVisible = _activeSeenVisible })
	MobilePanelManager.close(id)
	-- Bring the trigger icon (and anything that follows it) back in step with the closed panel.
	local cb = _closeCallbacks[id]
	if cb ~= nil then
		task.spawn(cb)
	end
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
	-- Returns the entrance delay the ACM should wait out (0 on desktop, where the ACM no longer
	-- sits over the hotbar and there is no hide to release). The matching release is
	-- notifyAcmClose(), called by AvatarContextController:closePanel.
	if not isMobile() then
		return 0
	end
	InventoryChromeAnimator.notifyHide("acm")
	return cfg.HOTBAR_HIDE_DURATION
end

function MobilePanelManager.notifyAcmClose(): ()
	InventoryChromeAnimator.notifyShow("acm")
end

-- Dance panel v3 on a phone reaches down over the hotbar; it hides while the panel is open.
function MobilePanelManager.notifyDancePanel(open: boolean): ()
	if not isMobile() then
		return
	end
	if open then
		InventoryChromeAnimator.notifyHide("dance")
	else
		InventoryChromeAnimator.notifyShow("dance")
	end
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

	-- The ACM only covers the hotbar on phones; on desktop it no longer sits at the bottom, so the
	-- hotbar stays put (and can never be left hidden by a missed ACM close).
	if not isMobile() then
		if cfg.HOTBAR_IDLE_HIDE_ENABLED == true then
			InventoryChromeAnimator.setupDesktopIdle()
		end
		log:info("MobilePanelManager initialized (desktop: idle hide only)")
		return
	end

	InventoryChromeAnimator.setupAcmWatcher()

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

	table.insert(_connections, RunService.Heartbeat:Connect(watchActivePanel))

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
