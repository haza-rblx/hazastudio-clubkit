--!strict
-- Client/Utils/ScrollIndicatorHelper.luau
-- Attaches auto-fadeout behaviour to a ScrollingFrame's scroll bar.
-- After FADEOUT_DELAY seconds of inactivity the bar fades out;
-- any scroll event fades it back in instantly.
--
-- Usage:
--   local ScrollIndicatorHelper = require(path.to.ScrollIndicatorHelper)
--   local handle = ScrollIndicatorHelper.attach(myScrollingFrame)
--   local handle = ScrollIndicatorHelper.attach(myScrollingFrame, { fadeoutDelay = 1 })
--   -- later, to clean up:
--   handle.destroy()
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local ScrollIndicatorHelper = {}

type Handle = {
	destroy: () -> (),
}

export type Options = {
	fadeoutDelay: number?,
	fadeoutDuration: number?,
	fadeinDuration: number?,
	hiddenTransparency: number?,
	visibleTransparency: number?,
}

local FADEOUT_DELAY = Config.ScrollIndicator.FADEOUT_DELAY
local FADEOUT_DUR = Config.ScrollIndicator.FADEOUT_DURATION
local FADEIN_DUR = Config.ScrollIndicator.FADEIN_DURATION
local HIDDEN_ALPHA = Config.ScrollIndicator.HIDDEN_TRANSPARENCY
local VISIBLE_ALPHA = Config.ScrollIndicator.VISIBLE_TRANSPARENCY

function ScrollIndicatorHelper.attach(frame: ScrollingFrame, options: Options?): Handle
	local connections: { RBXScriptConnection } = {}
	local currentTween: Tween? = nil
	local timerToken = 0
	local fadeoutDelay = FADEOUT_DELAY
	local fadeoutDuration = FADEOUT_DUR
	local fadeinDuration = FADEIN_DUR
	local hiddenAlpha = HIDDEN_ALPHA
	local visibleAlpha = VISIBLE_ALPHA

	if options then
		if options.fadeoutDelay ~= nil then
			fadeoutDelay = options.fadeoutDelay
		end
		if options.fadeoutDuration ~= nil then
			fadeoutDuration = options.fadeoutDuration
		end
		if options.fadeinDuration ~= nil then
			fadeinDuration = options.fadeinDuration
		end
		if options.hiddenTransparency ~= nil then
			hiddenAlpha = options.hiddenTransparency
		end
		if options.visibleTransparency ~= nil then
			visibleAlpha = options.visibleTransparency
		end
	end

	local fadeoutInfo = TweenInfo.new(fadeoutDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeinInfo = TweenInfo.new(fadeinDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local function cancelTween()
		if currentTween then
			currentTween:Cancel()
			currentTween = nil
		end
	end

	local function fadeOut()
		cancelTween()
		local t = TweenService:Create(frame, fadeoutInfo, { ScrollBarImageTransparency = hiddenAlpha })
		currentTween = t
		t:Play()
	end

	local function fadeIn()
		cancelTween()
		local t = TweenService:Create(frame, fadeinInfo, { ScrollBarImageTransparency = visibleAlpha })
		currentTween = t
		t:Play()
	end

	local function onActivity()
		timerToken += 1
		local token = timerToken
		fadeIn()
		task.delay(fadeoutDelay, function()
			if timerToken == token then
				fadeOut()
			end
		end)
	end

	table.insert(connections, frame:GetPropertyChangedSignal("CanvasPosition"):Connect(onActivity))

	-- Start hidden; show only when user first scrolls
	frame.ScrollBarImageTransparency = hiddenAlpha

	return {
		destroy = function()
			cancelTween()
			for _, c in ipairs(connections) do
				c:Disconnect()
			end
			table.clear(connections)
		end,
	}
end

return ScrollIndicatorHelper
