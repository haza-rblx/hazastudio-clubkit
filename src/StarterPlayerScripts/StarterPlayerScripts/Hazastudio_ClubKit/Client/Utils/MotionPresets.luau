--!strict
-- Shared calm UI motion tokens. Playful FX (donation/sticker/scalePop) stay outside this module.
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
	return 0.28
end

local function readCenterCloseTime(): number
	local uiMotion = (Config :: any).UIMotion
	if type(uiMotion) == "table" then
		local t = tonumber(uiMotion.CENTER_CLOSE_TIME)
		if t ~= nil then
			return t
		end
	end
	return 0.18
end

function MotionPresets.centerOpen(): CenterOpenPreset
	return {
		startScale = 0.96,
		time = readCenterOpenTime(),
		style = Enum.EasingStyle.Sine,
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

function MotionPresets.panelOpen(): PanelOpenPreset
	return {
		yOffset = 34,
		settleYOffset = -2,
		snapTime = 0.18,
		settleTime = 0.16,
		snapStyle = Enum.EasingStyle.Quart,
		settleStyle = Enum.EasingStyle.Sine,
	}
end

function MotionPresets.panelClose(): PanelClosePreset
	return {
		yOffset = 22,
		time = 0.16,
		style = Enum.EasingStyle.Cubic,
		direction = Enum.EasingDirection.In,
	}
end

function MotionPresets.dialogOpen(): DialogOpenPreset
	return {
		yOffset = 12,
		settleYOffset = -1,
		snapTime = 0.13,
		settleTime = 0.12,
	}
end

function MotionPresets.dialogClose(): DialogClosePreset
	return {
		yOffset = 8,
		time = 0.12,
		style = Enum.EasingStyle.Cubic,
		direction = Enum.EasingDirection.In,
	}
end

function MotionPresets.sidebarInInfo(): TweenInfo
	return MotionPresets.makeInfo(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
end

function MotionPresets.sidebarOutInfo(): TweenInfo
	return MotionPresets.makeInfo(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
end

-- Critically-damped spring freq (Hz-ish via Freecam formula). Lower = softer slide.
-- TopMenu / sidebar chrome prefer this over Quart tweens for interruptible open/close.
function MotionPresets.sidebarSpringFrequency(): number
	local uiMotion = (Config :: any).UIMotion
	local base = 6.2
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
	return MotionPresets.makeInfo(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
end

function MotionPresets.toastOutInfo(): TweenInfo
	return MotionPresets.makeInfo(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
end

function MotionPresets.pressDown(): PressPreset
	return {
		scale = 0.97,
		time = 0.08,
		style = Enum.EasingStyle.Quad,
		direction = Enum.EasingDirection.Out,
	}
end

function MotionPresets.pressUp(): PressPreset
	return {
		scale = 1,
		time = 0.12,
		style = Enum.EasingStyle.Quad,
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
