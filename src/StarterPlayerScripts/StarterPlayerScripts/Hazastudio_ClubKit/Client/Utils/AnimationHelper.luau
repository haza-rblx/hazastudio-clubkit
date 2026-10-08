--!strict
-- PATH: StarterPlayerScripts/Client/Utils/AnimationHelper.lua (ModuleScript)
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local MotionPresets = require(script.Parent.MotionPresets)
local GroupMotion = require(script.Parent.GroupMotion)
local InstanceState = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.InstanceState)
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
-- Constants (legacy playful / FX — not MotionPresets calm language)
-- ============================================================
local SCALE_POP_TIME = 0.4
local SCALE_OUT_TIME = 0.2
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
	return MotionPresets.makeInfo(t, style, dir)
end
-- ADR 0011: when the player asked Roblox for less motion, every path below snaps to the state
-- its tween would have ended in and skips blur/zoom. Same pcall pattern as UIMotion.reduced.
local function reduced(): boolean
	local ok, value = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	return ok and value == true
end
-- Reduced-motion completion for untracked paths: deferred so callers keep the "onDone runs
-- after this call returns" ordering a tween gives them.
local function deferDone(onDone: (() -> ())?): ()
	if onDone then
		task.defer(onDone)
	end
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
-- Per-target motion bookkeeping: one STRONG record per Instance, reclaimed on its `Destroying`
-- (InstanceState; ADR 0011 addendum, 2026-09-17). These used to be weak-keyed tables, and Roblox
-- drops such an entry while the panel is still alive — which orphaned an in-flight present/dismiss
-- so the next one could neither cancel it nor read the resting position it was aimed from.
type MotionRecord = {
	-- Tweens of the animation in flight, so the next animation on the target cancels them.
	tweens: { Tween }?,
	-- Bumped by every animation; a Completed handler for an older token does nothing.
	token: number,
	-- Where the in-flight travel is heading, so a new one starting mid-flight aims from rest.
	restingPosition: UDim2?,
	-- GroupTransparency at rest, captured before the first group fade (size-stable path, ADR 0005).
	restingGroupAlpha: number?,
}
local motion = InstanceState.new(function(): MotionRecord
	return { token = 0 }
end)
local function cancelActiveTweens(target: Instance): ()
	local record = motion.get(target)
	local tweens = if record then record.tweens else nil
	if not record or not tweens then
		return
	end
	record.tweens = nil
	for _, tween in ipairs(tweens) do
		tween:Cancel()
	end
end
local function beginAnimation(target: Instance): number
	local record = motion.of(target)
	record.token += 1
	cancelActiveTweens(target)
	return record.token
end
local function isCurrentAnimation(target: Instance, token: number): boolean
	local record = motion.get(target)
	return record ~= nil and record.token == token
end
local function registerTweens(target: Instance, tweens: { Tween }, restingPos: UDim2): ()
	local record = motion.of(target)
	record.tweens = tweens
	record.restingPosition = restingPos
end
local function completeTweens(target: Instance): ()
	local record = motion.get(target)
	if record then
		record.tweens = nil
		record.restingPosition = nil
	end
end
local function resolveRestingPosition(frame: Frame): UDim2
	local record = motion.get(frame)
	local cached = if record then record.restingPosition else nil
	if record and record.tweens and cached then
		return cached
	end
	return frame.Position
end
-- Reduced-motion completion for token-tracked paths: clears the registry like a finished tween
-- and only fires onDone if no newer animation on the target began before the deferred tick.
local function snapComplete(target: Instance, token: number, onDone: (() -> ())?): ()
	completeTweens(target)
	if onDone then
		task.defer(function()
			if isCurrentAnimation(target, token) then
				onDone()
			end
		end)
	end
end
-- ============================================================
-- Size-stable variants (ADR 0005)
-- A CanvasGroup is rasterized to a texture sized by its AbsoluteSize; scaling it (or any
-- ancestor) re-creates that texture every frame and renders BLANK once the client's
-- texture budget is exceeded. When GroupMotion says "stable", scale pops become:
--   * CanvasGroup target  -> GroupTransparency fade (no size change)
--   * Frame wrapping one  -> dialog snap/settle travel (position only)
-- UIScale instances already on the target are left untouched (mobile scaling lives there).
-- ============================================================
local function resolveRestingGroupAlpha(group: CanvasGroup): number
	local record = motion.of(group)
	local cached = record.restingGroupAlpha
	if record.tweens and cached ~= nil then
		return cached
	end
	local current = group.GroupTransparency
	-- Fully faded-out counts as "opaque at rest": that is how our own dismiss leaves it.
	if current >= 0.999 then
		current = 0
	end
	record.restingGroupAlpha = current
	return current
end
local function presentGroupFade(group: CanvasGroup, info: TweenInfo, onDone: (() -> ())?): ()
	local resting = resolveRestingGroupAlpha(group)
	local token = beginAnimation(group)
	if reduced() then
		group.GroupTransparency = resting
		group.Visible = true
		snapComplete(group, token, onDone)
		return
	end
	group.GroupTransparency = 1
	group.Visible = true
	local fade = TweenService:Create(group, info, { GroupTransparency = resting })
	registerTweens(group, { fade }, group.Position)
	fade.Completed:Once(function(playbackState)
		if not isCurrentAnimation(group, token) then
			return
		end
		completeTweens(group)
		group.GroupTransparency = resting
		if playbackState == Enum.PlaybackState.Completed and onDone then
			onDone()
		end
	end)
	fade:Play()
end
local function dismissGroupFade(group: CanvasGroup, info: TweenInfo, onDone: (() -> ())?): ()
	local resting = resolveRestingGroupAlpha(group)
	local token = beginAnimation(group)
	if reduced() then
		group.Visible = false
		group.GroupTransparency = resting
		snapComplete(group, token, onDone)
		return
	end
	group.Visible = true
	local fade = TweenService:Create(group, info, { GroupTransparency = 1 })
	registerTweens(group, { fade }, group.Position)
	fade.Completed:Once(function(playbackState)
		if not isCurrentAnimation(group, token) then
			return
		end
		completeTweens(group)
		group.Visible = false
		-- Restore so any later plain `Visible = true` by a binder shows the group opaque.
		group.GroupTransparency = resting
		if playbackState == Enum.PlaybackState.Completed and onDone then
			onDone()
		end
	end)
	fade:Play()
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
-- Scale Pop In — for opening panel/modal
-- Does not change Position/AnchorPoint at all
-- ============================================================
function AnimationHelper:scalePop(modal: Frame, onDone: (() -> ())?): ()
	if GroupMotion.isStable(modal) then
		if modal:IsA("CanvasGroup") then
			presentGroupFade(modal, makeInfo(SCALE_POP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), onDone)
		else
			self:presentDialog(modal, onDone)
		end
		return
	end
	local uiScale = getOrCreateUIScale(modal)
	if reduced() then
		uiScale.Scale = 1
		modal.Visible = true
		deferDone(onDone)
		return
	end
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
-- Scale Center Pop — for panel content swap (no overshoot, from center)
-- Unlike scalePop: Quint.Out easing + AnchorPoint 0.5,0.5 while
-- so the frame expands from center, not top-left corner
-- ============================================================
local SCALE_CENTER_POP_TIME = 0.4
function AnimationHelper:scaleCenterPop(modal: Frame, onDone: (() -> ())?): ()
	if GroupMotion.isStable(modal) then
		-- No anchor compensation needed: nothing scales, so nothing drifts off-center.
		self:scalePop(modal, onDone)
		return
	end
	local uiScale = getOrCreateUIScale(modal)
	if reduced() then
		-- Nothing scales, so AnchorPoint/Position never need compensating.
		uiScale.Scale = 1
		modal.Visible = true
		deferDone(onDone)
		return
	end
	uiScale.Scale = 0
	modal.Visible = true
	-- Compensate AnchorPoint -> scale from center during animation
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
		-- Restore AnchorPoint; UIListLayout will reset Position
		modal.AnchorPoint = origAnchor
		if onDone then
			onDone()
		end
	end)
	t:Play()
end
-- ============================================================
-- Scale Out — for closing panel/modal
-- ============================================================
function AnimationHelper:scaleOut(modal: Frame, onDone: (() -> ())?): ()
	if GroupMotion.isStable(modal) then
		if modal:IsA("CanvasGroup") then
			dismissGroupFade(modal, makeInfo(SCALE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), onDone)
		else
			self:dismissDialog(modal, onDone)
		end
		return
	end
	local uiScale = getOrCreateUIScale(modal)
	if reduced() then
		modal.Visible = false
		uiScale.Scale = 1
		deferDone(onDone)
		return
	end
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
-- Present/Dismiss Panel - moderate travel without UIScale.
-- Small settle at the end for a gamey feel, but typography stays stable.
-- ============================================================
function AnimationHelper:presentPanel(modal: Frame, onDone: (() -> ())?): ()
	local preset = MotionPresets.panelOpen()
	local restingPos = resolveRestingPosition(modal)
	local token = beginAnimation(modal)
	if reduced() then
		modal.Position = restingPos
		modal.Visible = true
		snapComplete(modal, token, onDone)
		return
	end
	local settlePos = offsetPosition(restingPos, preset.settleYOffset)
	modal.Position = offsetPosition(restingPos, preset.yOffset)
	modal.Visible = true
	local snapTween = TweenService:Create(
		modal,
		MotionPresets.transitionInfo(preset.snapTime, preset.snapStyle, Enum.EasingDirection.Out),
		{ Position = settlePos }
	)
	local settleTween = TweenService:Create(
		modal,
		MotionPresets.transitionInfo(preset.settleTime, preset.settleStyle, Enum.EasingDirection.Out),
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
	local preset = MotionPresets.panelClose()
	local restingPos = resolveRestingPosition(modal)
	local token = beginAnimation(modal)
	if reduced() then
		modal.Visible = false
		modal.Position = restingPos
		snapComplete(modal, token, onDone)
		return
	end
	local targetPos = offsetPosition(restingPos, preset.yOffset)
	modal.Visible = true
	local positionTween = TweenService:Create(
		modal,
		MotionPresets.transitionInfo(preset.time, preset.style, preset.direction),
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
	if reduced() or not self:_shouldUseBackgroundBlur() then
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

local function isPanelZoomEnabled(): boolean
	local panelZoom = Config.PanelZoom
	return type(panelZoom) == "table" and panelZoom.ENABLED == true
end

-- ADR 0011: what each present actually applied to the camera, newest last. Dismiss used to
-- mirror +PANEL_CAMERA_FOV_DELTA, which is the wrong amount whenever the clamp bit, the zoom
-- config was switched, or reduced motion turned on while the panel was open — and the camera
-- then kept an offset it could never lose. Undo exactly what went in instead.
local appliedCameraFovDeltas: { number } = {}

function AnimationHelper:_applyCameraFov(deltaFov: number, snap: boolean): number
	local camera = workspace.CurrentCamera
	if not camera or deltaFov == 0 then return 0 end

	local targetFov = math.clamp(camera.FieldOfView + deltaFov, 1, 120)
	local applied = targetFov - camera.FieldOfView
	if applied == 0 then return 0 end
	if snap then
		camera.FieldOfView = targetFov
		return applied
	end
	local tween = TweenService:Create(camera, self:_getPanelEffectTweenInfo(), {
		FieldOfView = targetFov,
	})
	tween:Play()
	return applied
end

function AnimationHelper:_tweenCameraZoom(deltaFov: number)
	if reduced() or not isPanelZoomEnabled() then
		-- Still record the (zero) delta so the matching dismiss pops this panel's own entry.
		table.insert(appliedCameraFovDeltas, 0)
		return
	end
	table.insert(appliedCameraFovDeltas, self:_applyCameraFov(deltaFov, false))
end

function AnimationHelper:_restoreCameraZoom()
	local applied = table.remove(appliedCameraFovDeltas)
	if applied == nil or applied == 0 then return end
	-- Always undone, even when reduced motion or the zoom config turned off while the panel was
	-- open: in that case the camera snaps back rather than tweening, but it does go back.
	self:_applyCameraFov(-applied, reduced() or not isPanelZoomEnabled())
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
			if reduced() then
				-- Blur was never faded in; nothing to wait for.
				blur.Enabled = false
				task.defer(done)
			else
				task.delay(blurConfig.FADE_OUT + 0.05, function()
					blur.Enabled = false
					done()
				end)
			end
		end
	end

	if opts.enableZoom then
		self:_restoreCameraZoom()
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
	local openPreset = MotionPresets.centerOpen()
	self:presentBackdropEffects(opts)
	if GroupMotion.isStable(modal) then
		if modal:IsA("CanvasGroup") then
			presentGroupFade(modal, MotionPresets.centerOpenInfo(), onDone)
		else
			self:presentDialog(modal, onDone)
		end
		return
	end
	local uiScale = getOrCreateUIScale(modal)
	local token = beginAnimation(modal)
	if reduced() then
		uiScale.Scale = 1
		modal.Visible = true
		snapComplete(modal, token, onDone)
		return
	end

	uiScale.Scale = openPreset.startScale
	modal.Visible = true
	local scaleTween = TweenService:Create(
		uiScale,
		MotionPresets.centerOpenTransitionInfo(),
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
	local closePreset = MotionPresets.centerClose()
	self:dismissBackdropEffects(opts)
	if GroupMotion.isStable(modal) then
		if modal:IsA("CanvasGroup") then
			dismissGroupFade(modal, MotionPresets.centerCloseInfo(), onDone)
		else
			self:dismissDialog(modal, onDone)
		end
		return
	end
	local uiScale = getOrCreateUIScale(modal)
	local token = beginAnimation(modal)
	if reduced() then
		modal.Visible = false
		uiScale.Scale = 1
		snapComplete(modal, token, onDone)
		return
	end

	modal.Visible = true
	local scaleTween = TweenService:Create(
		uiScale,
		MotionPresets.centerCloseTransitionInfo(),
		{ Scale = closePreset.endScale }
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
-- Present/Dismiss Dialog — small snap-settle for local modals.
-- ============================================================
function AnimationHelper:presentDialog(modal: Frame, onDone: (() -> ())?): ()
	local preset = MotionPresets.dialogOpen()
	local restingPos = resolveRestingPosition(modal)
	local token = beginAnimation(modal)
	if reduced() then
		modal.Position = restingPos
		modal.Visible = true
		snapComplete(modal, token, onDone)
		return
	end
	local settlePos = offsetPosition(restingPos, preset.settleYOffset)
	modal.Position = offsetPosition(restingPos, preset.yOffset)
	modal.Visible = true
	-- DialogOpenPreset carries no style fields (its shape is consumed elsewhere), so the curve is
	-- written here. Quint Out to match MotionPresets.panelOpen's snap after the 2026-09-16 feel
	-- pass — a dialog and a panel must not arrive along different curves.
	local snapTween = TweenService:Create(
		modal,
		MotionPresets.transitionInfo(preset.snapTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = settlePos }
	)
	local settleTween = TweenService:Create(
		modal,
		MotionPresets.transitionInfo(preset.settleTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
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
	local preset = MotionPresets.dialogClose()
	local restingPos = resolveRestingPosition(modal)
	local token = beginAnimation(modal)
	if reduced() then
		modal.Visible = false
		modal.Position = restingPos
		snapComplete(modal, token, onDone)
		return
	end
	local targetPos = offsetPosition(restingPos, preset.yOffset)
	modal.Visible = true
	local positionTween = TweenService:Create(
		modal,
		MotionPresets.transitionInfo(preset.time, preset.style, preset.direction),
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
-- Slide Out - panel drops down + scale shrinks
-- More natural for dismissing large panels (shop, gift)
-- ============================================================
local SLIDE_OUT_TIME = 0.3
local SLIDE_OUT_OFFSET = 50 -- px downward
function AnimationHelper:slideOut(modal: Frame, onDone: (() -> ())?): ()
	-- Size-stable (ADR 0005): keep the downward slide, drop the shrink on CanvasGroup trees.
	local uiScale: UIScale? = if GroupMotion.isStable(modal) then nil else getOrCreateUIScale(modal)
	local origPos = modal.Position
	local targetPos = UDim2.new(origPos.X.Scale, origPos.X.Offset, origPos.Y.Scale, origPos.Y.Offset + SLIDE_OUT_OFFSET)
	if uiScale then
		uiScale.Scale = 1
	end
	if reduced() then
		modal.Visible = false
		modal.Position = origPos
		deferDone(onDone)
		return
	end
	modal.Visible = true
	local slideInfo = makeInfo(SLIDE_OUT_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	-- Slide downward
	local tSlide = TweenService:Create(modal, slideInfo, { Position = targetPos })
	tSlide.Completed:Once(function()
		modal.Visible = false
		modal.Position = origPos -- restore position
		if uiScale then
			uiScale.Scale = 1
		end
		if onDone then
			onDone()
		end
	end)
	-- Slight scale-down + settle (scale mode only)
	if uiScale then
		TweenService:Create(uiScale, slideInfo, { Scale = 0.85 }):Play()
	end
	tSlide:Play()
end
-- ============================================================
-- Scatter Fragments - for Rejected frame dismiss
-- ============================================================
function AnimationHelper:scatterFragments(modal: Frame, overlay: Frame, onDone: (() -> ())?): ()
	if reduced() then
		-- Where the scatter ends: no fragments, overlay faded out and hidden, modal shown again.
		overlay.BackgroundTransparency = 1
		overlay.Visible = false
		modal.Visible = true
		deferDone(onDone)
		return
	end
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
-- Swing In - for Confirmation notification entrance
-- ============================================================
function AnimationHelper:swingIn(modal: Frame, overlay: Frame, onDone: (() -> ())?): ()
	-- Size-stable (ADR 0005): rotation does not resize a CanvasGroup texture, scale does.
	local uiScale: UIScale? = if GroupMotion.isStable(modal) then nil else getOrCreateUIScale(modal)
	local finalRotation = modal.Rotation
	if reduced() then
		if uiScale then
			uiScale.Scale = 1
		end
		modal.Visible = true
		deferDone(onDone)
		return
	end
	modal.Visible = true
	modal.Rotation = -12
	-- Do not fade overlay — leave transparent
	-- overlay used by swingIn but transparency not changed
	if uiScale then
		uiScale.Scale = 0.7
		TweenService:Create(uiScale, makeInfo(SWING_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end
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
-- Rotation - infinite spin for RotatingBackground
-- speed: seconds per 1 full rotation (default 5)
-- ============================================================
local ROTATION_DEFAULT_SPEED = 5
function AnimationHelper:startRotation(image: ImageLabel, speed: number?): RotationHandle
	local duration = speed or ROTATION_DEFAULT_SPEED
	image.Rotation = 0
	if reduced() then
		local still: RotationHandle = {
			stop = function()
				image.Rotation = 0
			end,
		}
		return still
	end
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
-- Progress Ring - countdown timeout on Waiting frame
-- Expected ring structure:
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
	if reduced() then
		-- The ring is a timeout, so the countdown keeps its full duration; only the arc sweep is skipped.
		task.delay(durationSec, function()
			if not stopped and onDone then
				onDone()
			end
		end)
		return handle
	end
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
