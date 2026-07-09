--!strict

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local SHADOW_NAME = "__NativeUIShadow"

type ShadowTweenOverrides = {[string]: any}
type ShadowTarget = GuiObject

local UIShadowHelper = {}

local function getShadowConfig(): any
	return Config.UIShadow :: any
end

local function getPreset(presetName: string): {[string]: any}?
	return getShadowConfig()[presetName]
end

local function getExistingShadow(target: ShadowTarget): Instance?
	local shadow = target:FindFirstChild(SHADOW_NAME)
	if shadow and shadow.ClassName == "UIShadow" then
		return shadow
	end
	return nil
end

local function mergeProps(baseProps: {[string]: any}, overrides: ShadowTweenOverrides?): {[string]: any}
	local merged = {}
	for key, value in pairs(baseProps) do
		merged[key] = value
	end
	if overrides then
		for key, value in pairs(overrides) do
			merged[key] = value
		end
	end
	return merged
end

local function assignProperties(shadow: Instance, props: {[string]: any})
	for key, value in pairs(props) do
		if key ~= "VisibleAlpha" and key ~= "PulseMin" and key ~= "PulseMax" then
			if key == "Offset" and typeof(value) == "Vector2" then
				value = UDim2.fromOffset(value.X, value.Y)
			end
			(shadow :: any)[key] = value
		end
	end
end

function UIShadowHelper.isSupported(): boolean
	if not getShadowConfig().ENABLED then
		return false
	end

	local ok, shadow = pcall(function()
		return Instance.new("UIShadow")
	end)

	if ok and shadow then
		shadow:Destroy()
		return true
	end

	return false
end

function UIShadowHelper.get(target: ShadowTarget): Instance?
	return getExistingShadow(target)
end

function UIShadowHelper.remove(target: ShadowTarget)
	local shadow = target:FindFirstChild(SHADOW_NAME)
	if shadow then
		shadow:Destroy()
	end
end

function UIShadowHelper.apply(target: ShadowTarget, presetName: string, overrides: ShadowTweenOverrides?): Instance?
	if not UIShadowHelper.isSupported() then
		return nil
	end

	local preset = getPreset(presetName)
	if not preset then
		return nil
	end

	local shadow = getExistingShadow(target)
	if not shadow then
		local ok, instanceOrErr = pcall(function()
			local newShadow = Instance.new("UIShadow")
			newShadow.Name = SHADOW_NAME
			newShadow.Parent = target
			return newShadow
		end)
		if not ok then
			return nil
		end
		shadow = (instanceOrErr :: any) :: Instance
	end

	local resolvedShadow = shadow :: Instance
	assignProperties(resolvedShadow, mergeProps(preset, overrides))
	return resolvedShadow
end

function UIShadowHelper.setColor(target: ShadowTarget, color: Color3)
	local shadow = getExistingShadow(target)
	if shadow then
		(shadow :: any).Color = color
	end
end

function UIShadowHelper.setTransparency(target: ShadowTarget, transparency: number)
	local shadow = getExistingShadow(target)
	if shadow then
		(shadow :: any).Transparency = transparency
	end
end

function UIShadowHelper.tweenTransparency(target: ShadowTarget, transparency: number, duration: number): Tween?
	local shadow = getExistingShadow(target)
	if not shadow then
		return nil
	end

	local tween = TweenService:Create(
		shadow,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = transparency }
	)
	tween:Play()
	return tween
end

function UIShadowHelper.tweenPreset(
	target: ShadowTarget,
	presetName: string,
	duration: number,
	overrides: ShadowTweenOverrides?
): Tween?
	local shadow = UIShadowHelper.apply(target, presetName)
	local preset = getPreset(presetName)
	if not shadow or not preset then
		return nil
	end

	local tweenProps = mergeProps(preset, overrides)
	tweenProps.VisibleAlpha = nil
	tweenProps.PulseMin = nil
	tweenProps.PulseMax = nil

	local tween = TweenService:Create(
		shadow,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		tweenProps
	)
	tween:Play()
	return tween
end

function UIShadowHelper.hoverBind(target: ShadowTarget, normalPreset: string, hoverPreset: string): () -> ()
	if not UIShadowHelper.isSupported() then
		return function() end
	end

	UIShadowHelper.apply(target, normalPreset)

	local enterConn = target.MouseEnter:Connect(function()
		UIShadowHelper.tweenPreset(target, hoverPreset, getShadowConfig().HOVER_IN_TIME or 0.14)
	end)

	local leaveConn = target.MouseLeave:Connect(function()
		UIShadowHelper.tweenPreset(target, normalPreset, getShadowConfig().HOVER_OUT_TIME or 0.16)
	end)

	return function()
		enterConn:Disconnect()
		leaveConn:Disconnect()
	end
end

return UIShadowHelper
