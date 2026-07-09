--!strict
-- Client/UI/StreakUI.lua
-- Display only. Animasi fire streak.
-- Flow: Overlay fade in -> StreakImage scalePop -> counter animate -> glow pulse -> auto-dismiss
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config          = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
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
	-- Sembunyikan saat init
	gui.Enabled            = false
	overlay.BackgroundTransparency = 1
	UIShadowHelper.apply(imgLabel, "STREAK_GLOW")
	return self
end
-- Animate counter dari 0 ke target
function StreakUI:_animateCounter(target: number, onDone: () -> ())
	local label    = self._count
	local duration = Config.Streak.COUNTER_DURATION
	local steps    = math.min(target, 30) -- max 30 langkah
	local interval = duration / steps
	local current  = 0
	local step     = math.max(1, math.floor(target / steps))
	label.Text = "0"
	task.spawn(function()
		while current < target do
			task.wait(interval)
			current = math.min(current + step, target)
			label.Text = tostring(current)
		end
		label.Text = tostring(target)
		onDone()
	end)
end
-- Glow pulse: scale out -> in, N kali
function StreakUI:_glowPulse(onDone: () -> ())
	local img    = self._img
	local count  = Config.Streak.GLOW_PULSE_COUNT
	local sizeOut = Config.Streak.GLOW_PULSE_SIZE_OUT
	local sizeIn  = Config.Streak.GLOW_PULSE_SIZE_IN
	local glowCfg = Config.UIShadow.STREAK_GLOW
	local done   = 0
	local tOut   = 0.22
	local tIn    = 0.18
	local function pulse()
		if done >= count then
			onDone()
			return
		end
		done += 1
		UIShadowHelper.tweenTransparency(img, glowCfg.PulseMax, tOut)
		TweenService:Create(img,
			TweenInfo.new(tOut, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ Size = UDim2.new(0, sizeOut, 0, sizeOut) }
		):Play()
		task.delay(tOut, function()
			UIShadowHelper.tweenTransparency(img, glowCfg.PulseMin, tIn)
			TweenService:Create(img,
				TweenInfo.new(tIn, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
				{ Size = UDim2.new(0, sizeIn, 0, sizeIn) }
			):Play()
			task.delay(tIn, pulse)
		end)
	end
	pulse()
end
-- Shake untuk milestone
function StreakUI:_shake()
	local img    = self._img
	local origin = img.Position
	local shakes = { 8, -8, 6, -6, 4, -4, 2, -2, 0 }
	task.spawn(function()
		for _, offset in ipairs(shakes) do
			img.Position = UDim2.new(
				origin.X.Scale, origin.X.Offset + offset,
				origin.Y.Scale, origin.Y.Offset
			)
			task.wait(0.04)
		end
		img.Position = origin
	end)
end
-- Partikel spark yang terbang keluar dari StreakImage
function StreakUI:_spawnParticles(colorSet: { Color3 })
	local cfg     = Config.Streak
	local COUNT   = cfg.PARTICLE_COUNT
	local overlay = self._overlay
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
			TweenService:Create(spark,
				TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{
					Position               = UDim2.new(targetX, 0, targetY, 0),
					BackgroundTransparency = 1,
					Size                   = UDim2.new(0, size * 0.2, 0, size * 0.2),
				}
			):Play()
			task.delay(duration, function()
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
	self._img.ImageColor3  = COLOR_DESATURATED
	self._count.Text       = "0"
	self._gui.Enabled      = true
	UIShadowHelper.apply(self._img, "STREAK_GLOW", {
		Color = Config.UIShadow.STREAK_COLORS[colorKey],
		Transparency = Config.UIShadow.STREAK_GLOW.Transparency,
	})
	TweenService:Create(self._img,
		TweenInfo.new(COLOR_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ ImageColor3 = imageColor }
	):Play()
	-- 1. Fade in overlay
	TweenService:Create(self._overlay,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	):Play()
	-- 2. StreakImage scalePop
	self._anim:scalePop(self._img :: Frame, function()
		-- 3. Counter animate
		self:_animateCounter(days, function()
			-- Partikel meledak setelah counter selesai
			self:_spawnParticles(PARTICLE_COLORS[colorKey])
			-- 4. Milestone shake
			if isMile then self:_shake() end
			-- 5. Glow pulse
			self:_glowPulse(function()
				-- 6. Auto-dismiss setelah SHOW_DURATION
				task.delay(Config.Streak.SHOW_DURATION, function()
					self:dismiss()
				end)
			end)
		end)
	end)
end
function StreakUI:dismiss()
	UIShadowHelper.setTransparency(self._img, Config.UIShadow.STREAK_GLOW.Transparency)
	self._anim:scaleOut(self._img :: Frame, nil)
	TweenService:Create(self._overlay,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	):Play()
	task.delay(0.3, function()
		self._gui.Enabled = false
		-- Reset UIScale untuk berikutnya
		local s = self._img:FindFirstChildWhichIsA("UIScale") :: UIScale?
		if s then s.Scale = 1 end
	end)
end
return StreakUI
