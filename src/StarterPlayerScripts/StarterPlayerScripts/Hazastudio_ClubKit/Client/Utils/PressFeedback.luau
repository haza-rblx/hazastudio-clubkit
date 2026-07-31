--!strict
-- Calm press micro-interaction. Uses a dedicated UIScale child so it never fights
-- AnimationHelper / panel open UIScale on ancestors or the same GuiObject.
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local MotionPresets = require(script.Parent.MotionPresets)

export type PressHandle = {
	Destroy: (self: PressHandle) -> (),
}

local PRESS_SCALE_NAME = "PressScale"

local PressFeedback = {}

local function getOrCreatePressScale(target: GuiObject): UIScale
	local existing = target:FindFirstChild(PRESS_SCALE_NAME)
	if existing and existing:IsA("UIScale") then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = PRESS_SCALE_NAME
	scale.Scale = 1
	scale.Parent = target
	return scale
end

local function isPressInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

function PressFeedback.bindPressScale(target: GuiObject): PressHandle
	local scale = getOrCreatePressScale(target)
	local activeTween: Tween? = nil
	local pressed = false
	local connections: { RBXScriptConnection } = {}
	local destroyed = false

	local function cancelTween()
		if activeTween then
			activeTween:Cancel()
			activeTween = nil
		end
	end

	local function tweenTo(goalScale: number, info: TweenInfo)
		if destroyed or not scale.Parent then
			return
		end
		cancelTween()
		local tween = TweenService:Create(scale, info, { Scale = goalScale })
		activeTween = tween
		tween.Completed:Once(function()
			if activeTween == tween then
				activeTween = nil
			end
		end)
		tween:Play()
	end

	local function setPressed(isDown: boolean)
		if destroyed then
			return
		end
		if isDown then
			if pressed then
				return
			end
			pressed = true
			local down = MotionPresets.pressDown()
			tweenTo(down.scale, MotionPresets.pressDownInfo())
		else
			if not pressed then
				return
			end
			pressed = false
			local up = MotionPresets.pressUp()
			tweenTo(up.scale, MotionPresets.pressUpInfo())
		end
	end

	table.insert(
		connections,
		target.InputBegan:Connect(function(input: InputObject)
			if not isPressInput(input) then
				return
			end
			setPressed(true)
		end)
	)

	table.insert(
		connections,
		target.InputEnded:Connect(function(input: InputObject)
			if not isPressInput(input) then
				return
			end
			setPressed(false)
		end)
	)

	-- Finger/mouse released outside the button still needs to restore scale.
	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if not isPressInput(input) then
				return
			end
			setPressed(false)
		end)
	)

	table.insert(
		connections,
		target.Destroying:Connect(function()
			destroyed = true
			cancelTween()
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
			table.clear(connections)
		end)
	)

	local handle: PressHandle = {
		Destroy = function(_self: PressHandle)
			if destroyed then
				return
			end
			destroyed = true
			cancelTween()
			pressed = false
			if scale.Parent then
				scale.Scale = 1
			end
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
			table.clear(connections)
		end,
	}
	return handle
end

return PressFeedback
