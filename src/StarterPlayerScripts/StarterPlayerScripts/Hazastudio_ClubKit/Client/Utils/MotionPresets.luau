--!strict
-- Shared calm UI motion tokens. Playful FX (donation/sticker/scalePop) stay outside this module.
-- Feel (owner, 2026-09-16): smooth and enjoyable rather than brisk — openings luxuriate, closes stay
-- clearly shorter than their opening, curves are Quint/Sine Out rather than Quart. The one exception
-- is `pressDown`: the gap between a finger landing and the button reacting reads as input lag, not
-- as elegance, so it stays at 0.08 while everything after the contact is softened. Every duration
-- here still flows through `scaledTime`, so `Config.UIMotion.MOTION_SCALE` keeps working.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

export type TweenPreset = {
	time: number,
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection,
}

export type CenterOpenPreset = {
	startScale: number,
	time: number,
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection,
}

export type CenterClosePreset = {
	endScale: number,
	time: number,
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection,
}

export type PanelOpenPreset = {
	yOffset: number,
	settleYOffset: number,
	snapTime: number,
	settleTime: number,
	snapStyle: Enum.EasingStyle,
	settleStyle: Enum.EasingStyle,
}

export type PanelClosePreset = {
	yOffset: number,
	time: number,
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection,
}

export type DialogOpenPreset = {
	yOffset: number,
	settleYOffset: number,
	snapTime: number,
	settleTime: number,
}

export type DialogClosePreset = {
	yOffset: number,
	time: number,
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection,
}

export type PressPreset = {
	scale: number,
	time: number,
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection,
}

local MotionPresets = {}

local function readMotionScale(): number
	local uiMotion = (Config :: any).UIMotion
	if type(uiMotion) ~= "table" then
		return 1
	end
	local scale = tonumber(uiMotion.MOTION_SCALE)
	if scale == nil then
		return 1
	end
	return math.clamp(scale, 0.25, 2)
end

function MotionPresets.getMotionScale(): number
	return readMotionScale()
end

function MotionPresets.scaledTime(seconds: number): number
	return math.max(0.01, seconds * readMotionScale())
end

function MotionPresets.makeInfo(time: number, style: Enum.EasingStyle, direction: Enum.EasingDirection): TweenInfo
	return TweenInfo.new(MotionPresets.scaledTime(time), style, direction)
end

local function readCenterOpenTime(): number
	local uiMotion = (Config :: any).UIMotion
	if type(uiMotion) == "table" then
		local t = tonumber(uiMotion.CENTER_OPEN_TIME)
		if t ~= nil then
			return t
		end
	end
	return 0.40
end

local function readCenterCloseTime(): number
	local uiMotion = (Config :: any).UIMotion
	if type(uiMotion) == "table" then
		local t = tonumber(uiMotion.CENTER_CLOSE_TIME)
		if t ~= nil then
			return t
		end
	end
	return 0.24
end

-- Quint Out over a long open: most of the 0.96 -> 1 travel lands early, then a long soft tail, which
-- reads as luxurious rather than sluggish. No overshoot here — a centre panel is the kit's largest
-- surface and the one most often clipped by its own rounded frame.
function MotionPresets.centerOpen(): CenterOpenPreset
	return {
		startScale = 0.96,
		time = readCenterOpenTime(),
		style = Enum.EasingStyle.Quint,
		direction = Enum.EasingDirection.Out,
	}
end

function MotionPresets.centerClose(): CenterClosePreset
	return {
		endScale = 0.96,
		time = readCenterCloseTime(),
		style = Enum.EasingStyle.Sine,
		direction = Enum.EasingDirection.In,
	}
end

function MotionPresets.centerOpenInfo(): TweenInfo
	local p = MotionPresets.centerOpen()
	return MotionPresets.makeInfo(p.time, p.style, p.direction)
end

function MotionPresets.centerCloseInfo(): TweenInfo
	local p = MotionPresets.centerClose()
	return MotionPresets.makeInfo(p.time, p.style, p.direction)
end

-- Travel (yOffset / settleYOffset) is deliberately unchanged: this pass retunes how long a panel
-- takes and along which curve, never what moves (ADR 0005 / the slide mechanism depend on that).
-- 0.32 + 0.20 = 0.52 s of arrival, Quint Out into a Sine Out landing that is meant to be noticed.
function MotionPresets.panelOpen(): PanelOpenPreset
	return {
		yOffset = 34,
		settleYOffset = -2,
		snapTime = 0.32,
		settleTime = 0.20,
		snapStyle = Enum.EasingStyle.Quint,
		settleStyle = Enum.EasingStyle.Sine,
	}
end

-- Softer than Cubic In, and still less than half the open: leaving must never feel like a wait.
function MotionPresets.panelClose(): PanelClosePreset
	return {
		yOffset = 22,
		time = 0.22,
		style = Enum.EasingStyle.Quad,
		direction = Enum.EasingDirection.In,
	}
end

-- Same treatment as a panel, a touch quicker: 0.24 + 0.15 = 0.39 s against the panel's 0.52.
function MotionPresets.dialogOpen(): DialogOpenPreset
	return {
		yOffset = 12,
		settleYOffset = -1,
		snapTime = 0.24,
		settleTime = 0.15,
	}
end

function MotionPresets.dialogClose(): DialogClosePreset
	return {
		yOffset = 8,
		time = 0.17,
		style = Enum.EasingStyle.Quad,
		direction = Enum.EasingDirection.In,
	}
end

function MotionPresets.sidebarInInfo(): TweenInfo
	return MotionPresets.makeInfo(0.38, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
end

function MotionPresets.sidebarOutInfo(): TweenInfo
	return MotionPresets.makeInfo(0.26, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
end

-- Critically-damped spring freq (Hz-ish via Freecam formula). Lower = softer slide.
-- TopMenu / sidebar chrome prefer this over Quart tweens for interruptible open/close.
function MotionPresets.sidebarSpringFrequency(): number
	local uiMotion = (Config :: any).UIMotion
	local base = 5.0
	if type(uiMotion) == "table" then
		local f = tonumber(uiMotion.SIDEBAR_SPRING_FREQ)
		if f ~= nil then
			base = f
		end
	end
	-- MOTION_SCALE > 1 slows motion by lowering frequency.
	return math.clamp(base / readMotionScale(), 2.5, 14)
end

function MotionPresets.sidebarFadeSpringFrequency(): number
	-- Fade settles a touch faster than the slide so the panel doesn't linger ghosted.
	return math.clamp(MotionPresets.sidebarSpringFrequency() * 1.15, 2.5, 16)
end

function MotionPresets.toastInInfo(): TweenInfo
	return MotionPresets.makeInfo(0.30, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
end

function MotionPresets.toastOutInfo(): TweenInfo
	return MotionPresets.makeInfo(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
end

-- DELIBERATELY FAST, do not soften (owner told, 2026-09-16): a delay between the finger landing and
-- the button reacting reads as input lag. Everything after the contact luxuriates instead.
function MotionPresets.pressDown(): PressPreset
	return {
		scale = 0.97,
		time = 0.08,
		style = Enum.EasingStyle.Quad,
		direction = Enum.EasingDirection.Out,
	}
end

-- Where the delight goes. Back Out on a 3% squash overshoots to ~1.002, far too small to spill out
-- of any clipping parent, so this is safe on every button PressFeedback is bound to.
function MotionPresets.pressUp(): PressPreset
	return {
		scale = 1,
		time = 0.26,
		style = Enum.EasingStyle.Back,
		direction = Enum.EasingDirection.Out,
	}
end

function MotionPresets.pressDownInfo(): TweenInfo
	local p = MotionPresets.pressDown()
	return MotionPresets.makeInfo(p.time, p.style, p.direction)
end

function MotionPresets.pressUpInfo(): TweenInfo
	local p = MotionPresets.pressUp()
	return MotionPresets.makeInfo(p.time, p.style, p.direction)
end

return MotionPresets
