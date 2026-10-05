--!strict
-- Client/Utils/SmoothScrollHelper.luau
-- Wheel smoothing for a ScrollingFrame: intercepts MouseWheel over the frame
-- and glides CanvasPosition to the next notch instead of Roblox's hard jump.
-- Touch drag and the scrollbar thumb keep their native behaviour (we only
-- intercept the wheel), so nothing else about the frame changes.
--
-- Usage:
--   local SmoothScrollHelper = require(path.to.SmoothScrollHelper)
--   local handle = SmoothScrollHelper.attach(myScrollingFrame)
--   -- options are all optional:
--   local handle = SmoothScrollHelper.attach(frame, { glideTime = 0.18 })
--   -- later, to clean up:
--   handle.destroy()
local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local SmoothScrollHelper = {}

type Handle = {
	destroy: () -> (),
}

export type Options = {
	glideTime: number?,
	easing: Enum.EasingStyle?,
	direction: Enum.EasingDirection?,
}

local CFG = (Config :: any).SmoothScroll or {}
local DEFAULT_GLIDE_TIME = tonumber(CFG.GLIDE_TIME) or 0.22
local DEFAULT_EASING = Enum.EasingStyle.Quad
local DEFAULT_DIRECTION = Enum.EasingDirection.Out

-- Is the cursor inside the frame right now? A wheel event anywhere else must
-- fall through to default scrolling — we only smooth OUR frame.
local function isMouseOver(frame: ScrollingFrame): boolean
	local mouse = UserInputService:GetMouseLocation()
	-- GetMouseLocation is viewport coords; AbsolutePosition already includes GuiInset.
	local pos = frame.AbsolutePosition
	local size = frame.AbsoluteSize
	local inset = game:GetService("GuiService"):GetGuiInset()
	local y = mouse.Y - inset.Y
	return mouse.X >= pos.X and mouse.X <= pos.X + size.X and y >= pos.Y and y <= pos.Y + size.Y
end

function SmoothScrollHelper.attach(frame: ScrollingFrame, options: Options?): Handle
	local glideTime = DEFAULT_GLIDE_TIME
	local easing = DEFAULT_EASING
	local direction = DEFAULT_DIRECTION
	if options then
		if options.glideTime ~= nil then
			glideTime = options.glideTime
		end
		if options.easing ~= nil then
			easing = options.easing
		end
		if options.direction ~= nil then
			direction = options.direction
		end
	end

	-- Unique per attach; GetDebugId is Plugin-security so a GUID is used instead.
	local actionName = "SmoothScroll_" .. HttpService:GenerateGUID(false)
	local currentTween: Tween? = nil
	local destroyed = false

	local function cancelTween()
		if currentTween then
			currentTween:Cancel()
			currentTween = nil
		end
	end

	local function handleWheel(_actionName: string, inputState: Enum.UserInputState, input: InputObject)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if not frame.Visible or not frame.Parent or not isMouseOver(frame) then
			return Enum.ContextActionResult.Pass
		end

		local wheel = input.Position.Z
		if wheel == 0 then
			return Enum.ContextActionResult.Pass
		end

		-- Where the glide starts: wherever the previous glide currently is.
		cancelTween()
		local currentY = frame.CanvasPosition.Y

		-- Native feel: each notch is ScrollWheelDuration11 ticks of ElasticBehavior.
		-- ScrollingFrames without ElasticBehavior use ~100px/notch (engine default);
		-- with ElasticBehavior the wheel jumps by the elastic distance — honour
		-- whichever the frame itself uses, falling back to 100.
		local maxY = math.max(0, frame.AbsoluteCanvasSize.Y - frame.AbsoluteWindowSize.Y)
		if maxY <= 0 then
			return Enum.ContextActionResult.Pass
		end

		local step = if frame.ElasticBehavior == Enum.ElasticBehavior.Always
			then math.min(frame.AbsoluteWindowSize.Y, maxY)
			else 100
		local targetY = math.clamp(currentY - wheel * step, 0, maxY)

		local tween = TweenService:Create(
			frame,
			TweenInfo.new(glideTime, easing, direction),
			{ CanvasPosition = Vector2.new(frame.CanvasPosition.X, targetY) }
		)
		currentTween = tween
		tween:Play()

		return Enum.ContextActionResult.Sink
	end

	ContextActionService:BindActionAtPriority(
		actionName,
		handleWheel,
		false,
		Enum.ContextActionPriority.High.Value + 1,
		Enum.UserInputType.MouseWheel
	)

	return {
		destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			cancelTween()
			ContextActionService:UnbindAction(actionName)
		end,
	}
end

return SmoothScrollHelper
