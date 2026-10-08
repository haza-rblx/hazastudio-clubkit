--!strict
-- Client/UI/StreakUI.lua
-- Display only. Animasi fire streak.
-- Flow: Overlay fade in -> StreakImage scalePop -> counter roll -> glow pulse -> auto-dismiss
-- AnimationHelper still owns arrival and departure (scalePop / scaleOut / startRotation);
-- everything in between goes through UIMotion (ADR 0011), so reduced motion is honoured and
-- the glow never breathes behind a disabled ScreenGui.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config          = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
local UIMotion        = require(script.Parent.Parent.Utils.UIMotion)
local UIShadowHelper  = require(script.Parent.Parent.Utils.UIShadowHelper)
-- Warna api normal vs milestone
local COLOR_DESATURATED = Color3.fromRGB(170, 170, 170)
local COLOR_NORMAL    = Color3.fromRGB(255, 140, 30)
local COLOR_MILESTONE = Color3.fromRGB(255, 60, 60)
local COLOR_RESET     = Color3.new(1, 1, 1)
local COLOR_TWEEN_TIME = 0.35
-- Warna partikel per kondisi
local PARTICLE_COLORS = {
	normal    = { Color3.fromRGB(255, 180, 30), Color3.fromRGB(255, 220, 60), Color3.fromRGB(255, 100, 0) },
	milestone = { Color3.fromRGB(255, 60, 60), Color3.fromRGB(255, 120, 200), Color3.fromRGB(255, 200, 60) },
	reset     = { Color3.fromRGB(160, 160, 160), Color3.fromRGB(200, 200, 200) },
}
local StreakUI = {} :: any
StreakUI.__index = StreakUI
function StreakUI.new(gui: ScreenGui)
	local self     = setmetatable({}, StreakUI) :: any
	local overlay  = gui:WaitForChild("Overlay")      :: Frame
	local imgLabel = overlay:WaitForChild("StreakImage") :: ImageLabel
	local countLbl = imgLabel:WaitForChild("StreakCount") :: TextLabel
	self._gui      = gui
	self._overlay  = overlay
	self._img      = imgLabel
	self._count    = countLbl
	self._anim     = AnimationHelper.new()
	-- Sunburst di belakang StreakImage. Opsional: place lama bisa saja tidak punya.
	self._rotBg    = overlay:FindFirstChild("RotatingBackground") :: ImageLabel?
	self._rotHandle = nil
	self._playId   = 0
	-- Stop functions for every loop started while the overlay is up; dismiss drains them.
	self._glowStops = {} :: { () -> () }
	-- Hide on init
	gui.Enabled            = false
	overlay.Visible        = false
	overlay.BackgroundTransparency = 1
	UIShadowHelper.apply(imgLabel, "STREAK_GLOW")
	return self
end
-- MotionPresets.scaledTime without a second require: MOTION_SCALE stretches every UIMotion
-- tween, so the steps chained off one have to stretch with it or they fire mid-animation.
function StreakUI:_scaledTime(seconds: number): number
	local motion = (Config :: any).UIMotion
	local scale = if type(motion) == "table" then (tonumber(motion.MOTION_SCALE) or 1) else 1
	return seconds * math.clamp(scale, 0.25, 2)
end
-- Counter roll 0 -> target. UIMotion.countTo owns the digits (and snaps them under reduced
-- motion); the follow-up is scheduled for the same stretched duration so the spark burst
-- lands on the last digit rather than before or after it.
function StreakUI:_animateCounter(target: number, onDone: () -> ())
	local duration = Config.Streak.COUNTER_DURATION
	self._count.Text = "0"
	UIMotion.countTo(self._count, 0, target, duration)
	task.delay(if UIMotion.reduced() then 0 else self:_scaledTime(duration), onDone)
end
-- Glow pulse: the shadow breathes for as long as the overlay is up (the old fixed
-- GLOW_PULSE_COUNT burst is gone), and the flame breathes with it when that is safe.
function StreakUI:_startGlow()
	self:_stopGlow()
	local img     = self._img
	local glowCfg = Config.UIShadow.STREAK_GLOW
	local period  = 0.2 -- one symmetric half-cycle replaces the old 0.22 out / 0.18 in pair
	local shadow  = UIShadowHelper.get(img)
	if shadow then
		if not UIMotion.reduced() then
			UIShadowHelper.setTransparency(img, glowCfg.PulseMin)
		end
		table.insert(self._glowStops, UIMotion.pulse(shadow, "Transparency", glowCfg.PulseMax, period))
	end
	-- Size only moves on a centred, layout-free image outside any CanvasGroup: breathing a
	-- laid-out child would shove its siblings (ADR 0011) and resizing a rasterized group
	-- would re-create its texture (ADR 0005). canScale is that exact question.
	if UIMotion.canScale(img) and not UIMotion.reduced() then
		local sizeIn  = Config.Streak.GLOW_PULSE_SIZE_IN
		local sizeOut = Config.Streak.GLOW_PULSE_SIZE_OUT
		img.Size = UDim2.new(0, sizeIn, 0, sizeIn)
		table.insert(self._glowStops, UIMotion.pulse(img, "Size", UDim2.new(0, sizeOut, 0, sizeOut), period))
	end
end
function StreakUI:_stopGlow()
	for _, stop in ipairs(self._glowStops) do
		stop()
	end
	table.clear(self._glowStops)
end
-- Shake for milestone. Rotation instead of the old Position nudges: it reads the same, never
-- touches layout, and stops itself when the image leaves.
function StreakUI:_shake()
	UIMotion.wiggle(self._img, 10)
end
-- Spark particles flying out from StreakImage
function StreakUI:_spawnParticles(colorSet: { Color3 })
	-- A 45-spark burst is the first thing a player who asked for less motion wants gone.
	if UIMotion.reduced() then
		return
	end
	local cfg     = Config.Streak
	local COUNT   = cfg.PARTICLE_COUNT
	local overlay = self._overlay
	-- The sparks are our own absolutely-positioned children of the backdrop, not template
	-- rows. If a buyer's Overlay lays its children out, a flying Frame would shove the card
	-- around instead of flying, so that place gets no burst.
	if overlay:FindFirstChildWhichIsA("UIGridStyleLayout") then
		return
	end
	for i = 1, COUNT do
		task.spawn(function()
			local angle    = (i / COUNT) * math.pi * 2 + math.random() * 0.6
			local distVar  = cfg.PARTICLE_DIST_MAX - cfg.PARTICLE_DIST_MIN
			local dist     = cfg.PARTICLE_DIST_MIN + math.random() * distVar
			local size     = math.random(cfg.PARTICLE_SIZE_MIN, cfg.PARTICLE_SIZE_MAX)
			local color    = colorSet[math.random(1, #colorSet)]
			local delay    = math.random() * cfg.PARTICLE_DELAY_MAX
			task.wait(delay)
			local spark            = Instance.new("Frame")
			spark.Size             = UDim2.new(0, size, 0, size)
			spark.Position         = UDim2.new(0.5, 0, 0.5, 0)
			spark.AnchorPoint      = Vector2.new(0.5, 0.5)
			spark.BackgroundColor3 = color
			spark.BorderSizePixel  = 0
			spark.ZIndex           = 10
			spark.Parent           = overlay
			local corner        = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent       = spark
			local targetX  = 0.5 + math.cos(angle) * dist
			local targetY  = 0.5 + math.sin(angle) * dist
			local duration = cfg.PARTICLE_DUR_MIN + math.random() * cfg.PARTICLE_DUR_VAR
			UIMotion.tween(spark, duration, {
				Position               = UDim2.new(targetX, 0, targetY, 0),
				BackgroundTransparency = 1,
				Size                   = UDim2.new(0, size * 0.2, 0, size * 0.2),
			}, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			task.delay(self:_scaledTime(duration), function()
				spark:Destroy()
			end)
		end)
	end
end
-- API utama
function StreakUI:play(payload: {
	streakDays   : number,
	didReset     : boolean,
	didIncrement : boolean,
	isMilestone  : boolean,
})
	local days      = payload.streakDays
	local isMile    = payload.isMilestone
	local didReset  = payload.didReset
	local colorKey  = didReset and "reset" or (isMile and "milestone" or "normal")
	-- Warna gambar sesuai kondisi
	local imageColor = didReset and COLOR_RESET
		or (isMile and COLOR_MILESTONE)
		or COLOR_NORMAL
	self._playId          += 1
	-- A second notif landing mid-show: kill the old loops before repainting the glow, or
	-- their stop functions would restore the previous colour on top of the new one. The
	-- token then keeps the older sequence's steps from touching this one.
	self:_stopGlow()
	local playToken = self._playId
	self._img.ImageColor3  = COLOR_DESATURATED
	self._count.Text       = "0"
	self._gui.Enabled      = true
	self._overlay.Visible  = true
	-- Sunburst mulai muter selama overlay tampil
	if self._rotBg then
		if self._rotHandle then
			self._anim:stopRotation(self._rotHandle)
		end
		self._rotHandle = self._anim:startRotation(self._rotBg, Config.Streak.ROTATION_SPEED)
	end
	UIShadowHelper.apply(self._img, "STREAK_GLOW", {
		Color = Config.UIShadow.STREAK_COLORS[colorKey],
		Transparency = Config.UIShadow.STREAK_GLOW.Transparency,
	})
	UIMotion.tween(
		self._img,
		COLOR_TWEEN_TIME,
		{ ImageColor3 = imageColor },
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	-- 1. Fade in overlay
	self._overlay.BackgroundTransparency = 1
	UIMotion.tween(
		self._overlay,
		0.3,
		{ BackgroundTransparency = Config.Streak.OVERLAY_TRANSPARENCY },
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	-- 2. StreakImage scalePop
	self._anim:scalePop(self._img :: Frame, function()
		if self._playId ~= playToken then return end
		-- 3. The reveal kick, then the glow breathes for as long as the overlay is up.
		-- scalePop has already made AnimationHelper's own UIScale, so the UIMotionScale
		-- this pop adds is the second child and never gets picked up as the panel scale.
		UIMotion.pop(self._img, 1.12)
		if payload.didIncrement then
			UIMotion.wiggle(self._img, 6)
		end
		self:_startGlow()
		-- 4. Counter roll
		self:_animateCounter(days, function()
			if self._playId ~= playToken then return end
			-- Particles explode after counter finishes
			self:_spawnParticles(PARTICLE_COLORS[colorKey])
			-- 5. Milestone shake
			if isMile then self:_shake() end
			-- 6. Auto-dismiss after SHOW_DURATION
			task.delay(Config.Streak.SHOW_DURATION, function()
				if self._playId ~= playToken then return end
				self:dismiss()
			end)
		end)
	end)
end
function StreakUI:dismiss()
	local playId = self._playId
	-- Nothing may keep breathing behind a disabled ScreenGui.
	self:_stopGlow()
	UIShadowHelper.setTransparency(self._img, Config.UIShadow.STREAK_GLOW.Transparency)
	self._anim:scaleOut(self._img :: Frame, nil)
	UIMotion.tween(
		self._overlay,
		0.3,
		{ BackgroundTransparency = 1 },
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	task.delay(self:_scaledTime(0.3), function()
		-- Notif baru keburu main duluan: jangan disembunyiin
		if self._playId ~= playId then return end
		if self._rotHandle then
			self._anim:stopRotation(self._rotHandle)
			self._rotHandle = nil
		end
		self._gui.Enabled = false
		self._overlay.Visible = false
		-- Reset every UIScale for berikutnya: AnimationHelper's and the one UIMotion.pop adds.
		for _, child in ipairs(self._img:GetChildren()) do
			if child:IsA("UIScale") then
				(child :: UIScale).Scale = 1
			end
		end
	end)
end
return StreakUI
