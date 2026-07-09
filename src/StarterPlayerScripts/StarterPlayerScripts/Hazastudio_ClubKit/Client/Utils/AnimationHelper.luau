--!strict
-- PATH: StarterPlayerScripts/Client/Utils/AnimationHelper.lua (ModuleScript)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
-- ============================================================
-- Types
-- ============================================================
export type ProgressRingHandle = {
	stop: () -> (),
}
export type RotationHandle = {
	stop: () -> (),
}
export type AnimationHelper = {
	scalePop: (self: AnimationHelper, modal: Frame, onDone: (() -> ())?) -> (),
	scaleCenterPop: (self: AnimationHelper, modal: Frame, onDone: (() -> ())?) -> (),
	scaleOut: (self: AnimationHelper, modal: Frame, onDone: (() -> ())?) -> (),
	presentPanel: (self: AnimationHelper, modal: Frame, onDone: (() -> ())?) -> (),
	dismissPanel: (self: AnimationHelper, modal: Frame, onDone: (() -> ())?) -> (),
	cancelPanel: (self: AnimationHelper, modal: Frame) -> (),
	presentCenterPanel: (self: AnimationHelper, modal: Frame, onDone: (() -> ())?) -> (),
	dismissCenterPanel: (self: AnimationHelper, modal: Frame, onDone: (() -> ())?) -> (),
	presentBackdropEffects: (self: AnimationHelper, options: {
		enableBlur: boolean?,
		blurName: string?,
		enableZoom: boolean?,
	}?) -> (),
	dismissBackdropEffects: (self: AnimationHelper, options: {
		enableBlur: boolean?,
		blurName: string?,
		enableZoom: boolean?,
	}?, onDone: (() -> ())?) -> (),
	presentDialog: (self: AnimationHelper, modal: Frame, onDone: (() -> ())?) -> (),
	dismissDialog: (self: AnimationHelper, modal: Frame, onDone: (() -> ())?) -> (),
	slideOut: (self: AnimationHelper, modal: Frame, onDone: (() -> ())?) -> (),
	scatterFragments: (self: AnimationHelper, modal: Frame, overlay: Frame, onDone: (() -> ())?) -> (),
	swingIn: (self: AnimationHelper, modal: Frame, overlay: Frame, onDone: (() -> ())?) -> (),
	progressRing: (self: AnimationHelper, ring: Frame, durationSec: number, onDone: (() -> ())?) -> ProgressRingHandle,
	startRotation: (self: AnimationHelper, image: ImageLabel, speed: number?) -> RotationHandle,
	stopRotation: (self: AnimationHelper, handle: RotationHandle) -> (),
}
-- ============================================================
-- Constants
-- ============================================================
local SCALE_POP_TIME = 0.4
local SCALE_OUT_TIME = 0.2
local PRESENT_PANEL_SNAP_TIME = 0.18
local PRESENT_PANEL_SETTLE_TIME = 0.16
local DISMISS_PANEL_TIME = 0.16
local PRESENT_PANEL_Y_OFFSET = 34
local PRESENT_PANEL_SETTLE_Y_OFFSET = -2
local DISMISS_PANEL_Y_OFFSET = 22
local CENTER_PANEL_OPEN_START_SCALE = 0.96
local CENTER_PANEL_CLOSE_SCALE = 0.96
local CENTER_PANEL_OPEN_TIME = 0.28
local CENTER_PANEL_CLOSE_TIME = 0.18
local PANEL_CAMERA_FOV_DELTA = 2

local function getPanelBlurConfig(): { SIZE: number, FADE_IN: number, FADE_OUT: number }
	local panelBlur = Config.PanelBlur
	if type(panelBlur) ~= "table" then
		return { SIZE = 36, FADE_IN = 0.32, FADE_OUT = 0.22 }
	end
	return {
		SIZE = math.clamp(tonumber(panelBlur.SIZE) or 36, 0, 56),
		FADE_IN = tonumber(panelBlur.FADE_IN) or 0.32,
		FADE_OUT = tonumber(panelBlur.FADE_OUT) or 0.22,
	}
end
local PRESENT_DIALOG_SNAP_TIME = 0.13
local PRESENT_DIALOG_SETTLE_TIME = 0.12
local DISMISS_DIALOG_TIME = 0.12
local PRESENT_DIALOG_Y_OFFSET = 12
local PRESENT_DIALOG_SETTLE_Y_OFFSET = -1
local DISMISS_DIALOG_Y_OFFSET = 8
local SWING_TIME = 0.55
local SCATTER_TIME = 0.38
local SCATTER_SPREAD = 0.35
local SCATTER_DELAY = 0.04
local OVERLAY_FADE_TIME = 0.25
local SCATTER_DIRS: { { number } } = {
	{ -1, -1 },
	{ 1, -1 },
	{ -1, 1 },
	{ 1, 1 },
}
-- ============================================================
-- Private helpers
-- ============================================================
local function makeInfo(t: number, style: Enum.EasingStyle, dir: Enum.EasingDirection): TweenInfo
	return TweenInfo.new(t, style, dir)
end
local function getOrCreateUIScale(frame: Frame): UIScale
	local existing = frame:FindFirstChildWhichIsA("UIScale") :: UIScale?
	if existing then
		return existing
	end
	local s = Instance.new("UIScale")
	s.Scale = 1
	s.Parent = frame
	return s
end
local function weakInstanceKeyTable<T>(): T
	return setmetatable({}, { __mode = "k" }) :: any
end
local activeTweens: { [Instance]: { Tween } } = weakInstanceKeyTable()
local activeTokens: { [Instance]: number } = weakInstanceKeyTable()
local activeRestingPositions: { [Instance]: UDim2 } = weakInstanceKeyTable()
local function cancelActiveTweens(target: Instance): ()
	local tweens = activeTweens[target]
	if not tweens then
		return
	end
	activeTweens[target] = nil
	for _, tween in ipairs(tweens) do
		tween:Cancel()
	end
end
local function beginAnimation(target: Instance): number
	local token = (activeTokens[target] or 0) + 1
	activeTokens[target] = token
	cancelActiveTweens(target)
	return token
end
local function isCurrentAnimation(target: Instance, token: number): boolean
	return activeTokens[target] == token
end
local function registerTweens(target: Instance, tweens: { Tween }, restingPos: UDim2): ()
	activeTweens[target] = tweens
	activeRestingPositions[target] = restingPos
end
local function completeTweens(target: Instance): ()
	activeTweens[target] = nil
	activeRestingPositions[target] = nil
end
local function resolveRestingPosition(frame: Frame): UDim2
	local cached = activeRestingPositions[frame]
	if activeTweens[frame] and cached then
		return cached
	end
	return frame.Position
end
local function offsetPosition(pos: UDim2, yOffset: number): UDim2
	return UDim2.new(pos.X.Scale, pos.X.Offset, pos.Y.Scale, pos.Y.Offset + yOffset)
end
local function _fadeOverlayIn(overlay: Frame): ()
	overlay.Visible = true
	TweenService:Create(
		overlay,
		makeInfo(OVERLAY_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0 }
	):Play()
end
local function fadeOverlayOut(overlay: Frame, onDone: (() -> ())?): ()
	local t = TweenService:Create(
		overlay,
		makeInfo(OVERLAY_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	)
	if onDone then
		t.Completed:Once(function()
			onDone()
		end)
	end
	t:Play()
end
local function buildFragments(modal: Frame): { Frame }
	local abs = modal.AbsoluteSize
	local hw = abs.X / 2
	local hh = abs.Y / 2
	local quads: { { number } } = {
		{ 0, 0, 0, 0 },
		{ hw, 0, 1, 0 },
		{ 0, hh, 0, 1 },
		{ hw, hh, 1, 1 },
	}
	local frags: { Frame } = {}
	for i, q in ipairs(quads) do
		local frag = Instance.new("Frame")
		frag.Name = "Frag_" .. i
		frag.Size = UDim2.new(0, hw, 0, hh)
		frag.Position = UDim2.new(0, q[1], 0, q[2])
		frag.AnchorPoint = Vector2.new(q[3], q[4])
		frag.BackgroundColor3 = modal.BackgroundColor3
		frag.BorderSizePixel = 0
		frag.ClipsDescendants = true
		frag.ZIndex = modal.ZIndex + 10
		frag.Parent = modal.Parent
		for _, child in ipairs(modal:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Clone().Parent = frag
			end
		end
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 0)
		corner.Parent = frag
		table.insert(frags, frag)
	end
	return frags
end
-- ============================================================
-- AnimationHelper
-- ============================================================
local AnimationHelper = {}
AnimationHelper.__index = AnimationHelper
function AnimationHelper.new(): AnimationHelper
	return setmetatable({}, AnimationHelper) :: any
end
-- ============================================================
-- Scale Pop In - untuk open panel/modal
-- Tidak ubah Position/AnchorPoint sama sekali
-- ============================================================
function AnimationHelper:scalePop(modal: Frame, onDone: (() -> ())?): ()
	local uiScale = getOrCreateUIScale(modal)
	uiScale.Scale = 0
	modal.Visible = true
	local t = TweenService:Create(
		uiScale,
		makeInfo(SCALE_POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	t.Completed:Once(function()
		if onDone then
			onDone()
		end
	end)
	t:Play()
end
-- ============================================================
-- Scale Center Pop - untuk panel content swap (tanpa overshoot, dari tengah)
-- Berbeda dari scalePop: easing Quint.Out + AnchorPoint 0.5,0.5 sementara
-- sehingga frame mengembang dari pusat, bukan dari pojok kiri atas
-- ============================================================
local SCALE_CENTER_POP_TIME = 0.4
function AnimationHelper:scaleCenterPop(modal: Frame, onDone: (() -> ())?): ()
	local uiScale = getOrCreateUIScale(modal)
	uiScale.Scale = 0
	modal.Visible = true
	-- Kompensasi AnchorPoint -> skala dari tengah selama animasi
	local origAnchor = modal.AnchorPoint
	local pos = modal.Position
	local sz = modal.Size
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.new(
		pos.X.Scale + sz.X.Scale * 0.5,
		pos.X.Offset + sz.X.Offset * 0.5,
		pos.Y.Scale + sz.Y.Scale * 0.5,
		pos.Y.Offset + sz.Y.Offset * 0.5
	)
	local t = TweenService:Create(
		uiScale,
		makeInfo(SCALE_CENTER_POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	t.Completed:Once(function()
		-- Kembalikan AnchorPoint; UIListLayout akan reset Position
		modal.AnchorPoint = origAnchor
		if onDone then
			onDone()
		end
	end)
	t:Play()
end
-- ============================================================
-- Scale Out - untuk close panel/modal
-- ============================================================
function AnimationHelper:scaleOut(modal: Frame, onDone: (() -> ())?): ()
	local uiScale = getOrCreateUIScale(modal)
	local t = TweenService:Create(
		uiScale,
		makeInfo(SCALE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = 0 }
	)
	t.Completed:Once(function()
		modal.Visible = false
		uiScale.Scale = 1
		if onDone then
			onDone()
		end
	end)
	t:Play()
end
-- ============================================================
-- Present/Dismiss Panel - travel sedang tanpa UIScale.
-- Ada settle kecil di akhir supaya terasa gamey, tapi typography tetap stabil.
-- ============================================================
function AnimationHelper:presentPanel(modal: Frame, onDone: (() -> ())?): ()
	local restingPos = resolveRestingPosition(modal)
	local token = beginAnimation(modal)
	local settlePos = offsetPosition(restingPos, PRESENT_PANEL_SETTLE_Y_OFFSET)
	modal.Position = offsetPosition(restingPos, PRESENT_PANEL_Y_OFFSET)
	modal.Visible = true
	local snapTween = TweenService:Create(
		modal,
		makeInfo(PRESENT_PANEL_SNAP_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Position = settlePos }
	)
	local settleTween = TweenService:Create(
		modal,
		makeInfo(PRESENT_PANEL_SETTLE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Position = restingPos }
	)
	registerTweens(modal, { snapTween, settleTween }, restingPos)
	snapTween.Completed:Once(function(playbackState)
		if not isCurrentAnimation(modal, token) then
			return
		end
		if playbackState ~= Enum.PlaybackState.Completed then
			return
		end
		settleTween:Play()
	end)
	settleTween.Completed:Once(function(playbackState)
		if not isCurrentAnimation(modal, token) then
			return
		end
		completeTweens(modal)
		modal.Position = restingPos
		if playbackState == Enum.PlaybackState.Completed and onDone then
			onDone()
		end
	end)
	snapTween:Play()
end
function AnimationHelper:dismissPanel(modal: Frame, onDone: (() -> ())?): ()
	local restingPos = resolveRestingPosition(modal)
	local token = beginAnimation(modal)
	local targetPos = offsetPosition(restingPos, DISMISS_PANEL_Y_OFFSET)
	modal.Visible = true
	local positionTween = TweenService:Create(
		modal,
		makeInfo(DISMISS_PANEL_TIME, Enum.EasingStyle.Cubic, Enum.EasingDirection.In),
		{ Position = targetPos }
	)
	registerTweens(modal, { positionTween }, restingPos)
	positionTween.Completed:Once(function(playbackState)
		if not isCurrentAnimation(modal, token) then
			return
		end
		completeTweens(modal)
		modal.Visible = false
		modal.Position = restingPos
		if playbackState == Enum.PlaybackState.Completed and onDone then
			onDone()
		end
	end)
	positionTween:Play()
end

function AnimationHelper:cancelPanel(modal: Frame): ()
	beginAnimation(modal)
	completeTweens(modal)
end

function AnimationHelper:_getOrCreatePanelBlur(blurName: string): BlurEffect
	local Lighting = game:GetService("Lighting")
	local existing = Lighting:FindFirstChild(blurName)
	if existing and existing:IsA("BlurEffect") then
		return existing
	end
	
	local blur = Instance.new("BlurEffect")
	blur.Name = blurName
	blur.Enabled = false
	blur.Size = 0
	blur.Parent = Lighting
	return blur
end

function AnimationHelper:_shouldUseBackgroundBlur(): boolean
	local panelBlur = Config.PanelBlur
	if type(panelBlur) ~= "table" or panelBlur.ENABLED ~= true then
		return false
	end

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local settingsData = ReplicatedStorage:FindFirstChild("ClientSettings")
	if settingsData then
		local value = settingsData:FindFirstChild("BackgroundBlur")
		if value and value:IsA("BoolValue") then
			return value.Value
		end
	end
	return true
end

function AnimationHelper:_animatePanelBlur(blur: BlurEffect, targetSize: number)
	if not self:_shouldUseBackgroundBlur() then
		blur.Size = 0
		blur.Enabled = false
		return
	end

	local blurConfig = getPanelBlurConfig()
	local tweenTime = if targetSize > 0 then blurConfig.FADE_IN else blurConfig.FADE_OUT
	blur.Enabled = true
	local tween = TweenService:Create(blur, TweenInfo.new(tweenTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Size = targetSize,
	})
	tween:Play()
end

function AnimationHelper:_getPanelEffectTweenInfo(): TweenInfo
	local blurConfig = getPanelBlurConfig()
	return TweenInfo.new(blurConfig.FADE_IN, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
end

function AnimationHelper:_tweenCameraZoom(deltaFov: number)
	local camera = workspace.CurrentCamera
	if not camera then return end
	
	local targetFov = math.clamp(camera.FieldOfView + deltaFov, 1, 120)
	local tween = TweenService:Create(camera, self:_getPanelEffectTweenInfo(), {
		FieldOfView = targetFov,
	})
	tween:Play()
end

function AnimationHelper:presentBackdropEffects(options: {
	enableBlur: boolean?,
	blurName: string?,
	enableZoom: boolean?,
}?): ()
	local opts = options or {}
	if opts.enableZoom then
		self:_tweenCameraZoom(-PANEL_CAMERA_FOV_DELTA)
	end
	if opts.enableBlur and opts.blurName then
		local blur = self:_getOrCreatePanelBlur(opts.blurName)
		self:_animatePanelBlur(blur, getPanelBlurConfig().SIZE)
	end
end

function AnimationHelper:dismissBackdropEffects(options: {
	enableBlur: boolean?,
	blurName: string?,
	enableZoom: boolean?,
}?, onDone: (() -> ())?): ()
	local opts = options or {}
	local blurConfig = getPanelBlurConfig()
	local pending = 0
	local completed = false

	local function finish()
		if completed then
			return
		end
		completed = true
		if onDone then
			onDone()
		end
	end

	local function trackAsync()
		pending += 1
		return function()
			pending -= 1
			if pending <= 0 then
				finish()
			end
		end
	end

	if opts.enableBlur and opts.blurName then
		local Lighting = game:GetService("Lighting")
		local blur = Lighting:FindFirstChild(opts.blurName)
		if blur and blur:IsA("BlurEffect") then
			local done = trackAsync()
			self:_animatePanelBlur(blur, 0)
			task.delay(blurConfig.FADE_OUT + 0.05, function()
				blur.Enabled = false
				done()
			end)
		end
	end

	if opts.enableZoom then
		self:_tweenCameraZoom(PANEL_CAMERA_FOV_DELTA)
	end

	if pending == 0 then
		finish()
	end
end

function AnimationHelper:presentCenterPanel(modal: Frame, onDone: (() -> ())?, options: {
	enableBlur: boolean?,
	blurName: string?,
	enableZoom: boolean?
}?): ()
	local opts = options or {}
	local uiScale = getOrCreateUIScale(modal)
	local token = beginAnimation(modal)

	self:presentBackdropEffects(opts)
	
	uiScale.Scale = CENTER_PANEL_OPEN_START_SCALE
	modal.Visible = true
	local scaleTween = TweenService:Create(
		uiScale,
		makeInfo(CENTER_PANEL_OPEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	registerTweens(modal, { scaleTween }, modal.Position)
	scaleTween.Completed:Once(function(playbackState)
		if not isCurrentAnimation(modal, token) then
			return
		end
		completeTweens(modal)
		uiScale.Scale = 1
		if playbackState == Enum.PlaybackState.Completed and onDone then
			onDone()
		end
	end)
	scaleTween:Play()
end

function AnimationHelper:dismissCenterPanel(modal: Frame, onDone: (() -> ())?, options: {
	enableBlur: boolean?,
	blurName: string?,
	enableZoom: boolean?
}?): ()
	local opts = options or {}
	local uiScale = getOrCreateUIScale(modal)
	local token = beginAnimation(modal)

	self:dismissBackdropEffects(opts)
	
	modal.Visible = true
	local scaleTween = TweenService:Create(
		uiScale,
		makeInfo(CENTER_PANEL_CLOSE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
		{ Scale = CENTER_PANEL_CLOSE_SCALE }
	)
	registerTweens(modal, { scaleTween }, modal.Position)
	scaleTween.Completed:Once(function(playbackState)
		if not isCurrentAnimation(modal, token) then
			return
		end
		completeTweens(modal)
		modal.Visible = false
		uiScale.Scale = 1
		if playbackState == Enum.PlaybackState.Completed and onDone then
			onDone()
		end
	end)
	scaleTween:Play()
end
-- ============================================================
-- Present/Dismiss Dialog - snap-settle kecil untuk modal lokal.
-- ============================================================
function AnimationHelper:presentDialog(modal: Frame, onDone: (() -> ())?): ()
	local restingPos = resolveRestingPosition(modal)
	local token = beginAnimation(modal)
	local settlePos = offsetPosition(restingPos, PRESENT_DIALOG_SETTLE_Y_OFFSET)
	modal.Position = offsetPosition(restingPos, PRESENT_DIALOG_Y_OFFSET)
	modal.Visible = true
	local snapTween = TweenService:Create(
		modal,
		makeInfo(PRESENT_DIALOG_SNAP_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Position = settlePos }
	)
	local settleTween = TweenService:Create(
		modal,
		makeInfo(PRESENT_DIALOG_SETTLE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Position = restingPos }
	)
	registerTweens(modal, { snapTween, settleTween }, restingPos)
	snapTween.Completed:Once(function(playbackState)
		if not isCurrentAnimation(modal, token) then
			return
		end
		if playbackState ~= Enum.PlaybackState.Completed then
			return
		end
		settleTween:Play()
	end)
	settleTween.Completed:Once(function(playbackState)
		if not isCurrentAnimation(modal, token) then
			return
		end
		completeTweens(modal)
		modal.Position = restingPos
		if playbackState == Enum.PlaybackState.Completed and onDone then
			onDone()
		end
	end)
	snapTween:Play()
end
function AnimationHelper:dismissDialog(modal: Frame, onDone: (() -> ())?): ()
	local restingPos = resolveRestingPosition(modal)
	local token = beginAnimation(modal)
	local targetPos = offsetPosition(restingPos, DISMISS_DIALOG_Y_OFFSET)
	modal.Visible = true
	local positionTween = TweenService:Create(
		modal,
		makeInfo(DISMISS_DIALOG_TIME, Enum.EasingStyle.Cubic, Enum.EasingDirection.In),
		{ Position = targetPos }
	)
	registerTweens(modal, { positionTween }, restingPos)
	positionTween.Completed:Once(function(playbackState)
		if not isCurrentAnimation(modal, token) then
			return
		end
		completeTweens(modal)
		modal.Visible = false
		modal.Position = restingPos
		if playbackState == Enum.PlaybackState.Completed and onDone then
			onDone()
		end
	end)
	positionTween:Play()
end
-- ============================================================
-- Slide Out - panel jatuh ke bawah + scale mengecil
-- Lebih natural untuk dismiss panel besar (shop, gift)
-- ============================================================
local SLIDE_OUT_TIME = 0.3
local SLIDE_OUT_OFFSET = 50 -- px ke bawah
function AnimationHelper:slideOut(modal: Frame, onDone: (() -> ())?): ()
	local uiScale = getOrCreateUIScale(modal)
	local origPos = modal.Position
	local targetPos = UDim2.new(origPos.X.Scale, origPos.X.Offset, origPos.Y.Scale, origPos.Y.Offset + SLIDE_OUT_OFFSET)
	uiScale.Scale = 1
	modal.Visible = true
	-- Slide ke bawah
	TweenService
		:Create(
			modal,
			makeInfo(SLIDE_OUT_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
			{ Position = targetPos }
		)
		:Play()
	-- Scale sedikit mengecil + selesaikan
	local tScale = TweenService:Create(
		uiScale,
		makeInfo(SLIDE_OUT_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
		{ Scale = 0.85 }
	)
	tScale.Completed:Once(function()
		modal.Visible = false
		modal.Position = origPos -- kembalikan posisi
		uiScale.Scale = 1
		if onDone then
			onDone()
		end
	end)
	tScale:Play()
end
-- ============================================================
-- Scatter Fragments - untuk Rejected frame dismiss
-- ============================================================
function AnimationHelper:scatterFragments(modal: Frame, overlay: Frame, onDone: (() -> ())?): ()
	task.defer(function()
		local frags = buildFragments(modal)
		modal.Visible = false
		local completed = 0
		local total = #frags
		for i, frag in ipairs(frags) do
			local dx = SCATTER_DIRS[i][1]
			local dy = SCATTER_DIRS[i][2]
			local targetPos = UDim2.new(
				frag.Position.X.Scale + dx * SCATTER_SPREAD,
				frag.Position.X.Offset,
				frag.Position.Y.Scale + dy * SCATTER_SPREAD,
				frag.Position.Y.Offset
			)
			local t = TweenService:Create(
				frag,
				makeInfo(SCATTER_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = targetPos, BackgroundTransparency = 1 }
			)
			t.Completed:Once(function()
				frag:Destroy()
				completed += 1
				if completed >= total then
					fadeOverlayOut(overlay, function()
						overlay.Visible = false
						modal.Visible = true
						if onDone then
							onDone()
						end
					end)
				end
			end)
			task.delay((i - 1) * SCATTER_DELAY, function()
				t:Play()
			end)
		end
	end)
end
-- ============================================================
-- Swing In - untuk Confirmation notif masuk
-- ============================================================
function AnimationHelper:swingIn(modal: Frame, overlay: Frame, onDone: (() -> ())?): ()
	local uiScale = getOrCreateUIScale(modal)
	local finalRotation = modal.Rotation
	modal.Visible = true
	uiScale.Scale = 0.7
	modal.Rotation = -12
	-- Tidak fade overlay - biarkan transparent
	-- overlay dipakai swingIn tapi tidak diubah transparencynya
	TweenService:Create(uiScale, makeInfo(SWING_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	local tRot = TweenService:Create(
		modal,
		makeInfo(SWING_TIME * 0.85, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Rotation = finalRotation }
	)
	tRot.Completed:Once(function()
		if onDone then
			onDone()
		end
	end)
	tRot:Play()
end
-- ============================================================
-- Rotation - infinite spin untuk RotatingBackground
-- speed: detik per 1 putaran penuh (default 5)
-- ============================================================
local ROTATION_DEFAULT_SPEED = 5
function AnimationHelper:startRotation(image: ImageLabel, speed: number?): RotationHandle
	local duration = speed or ROTATION_DEFAULT_SPEED
	image.Rotation = 0
	local tween = TweenService:Create(
		image,
		TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1, false, 0),
		{ Rotation = 360 }
	)
	tween:Play()
	local handle: RotationHandle = {
		stop = function()
			tween:Cancel()
			image.Rotation = 0
		end,
	}
	return handle
end
function AnimationHelper:stopRotation(handle: RotationHandle): ()
	handle.stop()
end
-- ============================================================
-- Progress Ring - countdown timeout di Waiting frame
-- Struktur ring yang diharapkan:
--   ring (Frame)
-- |-- ArcFrame (Frame, ClipsDescendants = true)
-- | `-- ArcIndicator (Frame, UICorner radius 0.5, UIStroke)
-- `-- TimerLabel (TextLabel)
-- ============================================================
function AnimationHelper:progressRing(ring: Frame, durationSec: number, onDone: (() -> ())?): ProgressRingHandle
	local arcFrame = ring:FindFirstChild("ArcFrame") :: Frame?
	local arcIndicator = arcFrame and arcFrame:FindFirstChild("ArcIndicator") :: Frame?
	local timerLabel = ring:FindFirstChild("TimerLabel") :: TextLabel?
	local stopped = false
	local tArc: Tween? = nil
	local handle: ProgressRingHandle = {
		stop = function()
			stopped = true
			if tArc then
				tArc:Cancel()
			end
			if timerLabel then
				timerLabel.Text = ""
			end
		end,
	}
	if not arcIndicator then
		task.delay(durationSec, function()
			if not stopped and onDone then
				onDone()
			end
		end)
		return handle
	end
	arcIndicator.Rotation = 0
	if timerLabel then
		timerLabel.Text = tostring(math.floor(durationSec))
	end
	local arcTween = TweenService:Create(
		arcIndicator,
		makeInfo(durationSec, Enum.EasingStyle.Linear, Enum.EasingDirection.In),
		{ Rotation = 360 }
	)
	tArc = arcTween
	task.spawn(function()
		local remaining = math.floor(durationSec)
		while remaining > 0 and not stopped do
			task.wait(1)
			if stopped then
				break
			end
			remaining -= 1
			if timerLabel then
				timerLabel.Text = tostring(remaining)
			end
		end
	end)
	arcTween.Completed:Once(function()
		if stopped then
			return
		end
		if onDone then
			onDone()
		end
	end)
	arcTween:Play()
	handle = {
		stop = function()
			stopped = true
			if tArc then
				tArc:Cancel()
			end
			if timerLabel then
				timerLabel.Text = ""
			end
		end,
	}
	return handle
end
return AnimationHelper
