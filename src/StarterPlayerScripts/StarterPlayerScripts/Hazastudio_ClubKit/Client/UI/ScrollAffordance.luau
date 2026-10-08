--!strict
-- "There is more below" cues for a card whose content scrolls but looks finished (the avatar
-- context menu, owner 2026-10-07). Each `reveal()` (content shown):
--   * flashes the short pill scrollbar beside the card (OverlayScrollbar),
--   * fades the card's bottom edge with a small bobbing chevron, gone once the player scrolls,
--   * nudges the content: a slow double bob (down 100px, back, down 60px, back) on the first
--     few reveals of a session, and never again once the player has scrolled themselves.
-- "Scrolled themselves" means real input on the list (wheel, touch, mouse button) — CanvasPosition
-- also moves for other reasons (the card resetting itself, our own nudge) and must not count.

local RunService = game:GetService("RunService")

local OverlayScrollbar = require(script.Parent.OverlayScrollbar)

local ScrollAffordance = {}

export type Handle = {
	reveal: () -> (),
	destroy: () -> (),
}

local NUDGE_STEPS = { { 100, 0.85 }, { 0, 0.85 }, { 60, 0.7 }, { 0, 0.7 } }
local NUDGE_DELAY = 0.4
local MAX_NUDGES = 3
local READY_TIMEOUT = 2
local OPEN_FLASH_SECONDS = 1.2
local HINT_HEIGHT = 64
local HINT_HIDE_AFTER = 40
local CHEVRON_BOB = 2

-- Per-session memory, by key: how often we nudged and whether the player already scrolls.
local sessions: { [string]: { nudges: number, scrolled: boolean } } = {}

local function ease(t: number): number
	return 0.5 - 0.5 * math.cos(math.pi * t)
end

local function canScroll(scroll: ScrollingFrame): boolean
	return scroll.Visible and scroll.AbsoluteCanvasSize.Y > scroll.AbsoluteWindowSize.Y + 1
end

local function buildHint(card: GuiObject): (Frame, Frame)
	local hint = Instance.new("Frame")
	hint.Name = "ScrollHint"
	hint.BorderSizePixel = 0
	hint.AnchorPoint = Vector2.new(0, 1)
	hint.Position = UDim2.fromScale(0, 1)
	hint.Size = UDim2.new(1, 0, 0, HINT_HEIGHT)
	hint.ZIndex = 50
	hint.Visible = false
	-- Painted from the card's own (themed) colour every frame; keep the theme engine off it.
	hint:SetAttribute("AccentNoTint", true)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.6, 0.15),
		NumberSequenceKeypoint.new(1, 0),
	})
	gradient.Parent = hint

	local chevron = Instance.new("Frame")
	chevron.Name = "Chevron"
	chevron.BackgroundTransparency = 1
	chevron.AnchorPoint = Vector2.new(0.5, 1)
	chevron.Position = UDim2.new(0.5, 0, 1, -10)
	chevron.Size = UDim2.fromOffset(16, 8)
	chevron.ZIndex = 51
	for index, rotation in ipairs({ 35, -35 }) do
		local bar = Instance.new("Frame")
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = Color3.new(1, 1, 1)
		bar.BackgroundTransparency = 0.25
		bar.ZIndex = 52
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Size = UDim2.fromOffset(10, 2)
		bar.Rotation = rotation
		bar.Position = UDim2.new(if index == 1 then 0.32 else 0.68, 0, 0.5, 0)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = bar
		bar.Parent = chevron
	end
	chevron.Parent = hint
	hint.Parent = card
	return hint, chevron
end

-- `scroll`: the card's list. `card`: the rounded box it sits in (holds no UIListLayout).
-- `key`: names the per-session nudge memory.
function ScrollAffordance.attach(scroll: ScrollingFrame, card: GuiObject, key: string): Handle
	local session = sessions[key]
	if not session then
		session = { nudges = 0, scrolled = false }
		sessions[key] = session
	end
	local scrollbar = OverlayScrollbar.attach(scroll, card, { side = "right" })
	local hint, chevron = buildHint(card)
	local nudging = false
	local nudgeConnection: RBXScriptConnection? = nil
	local bobTime = 0

	local function stopNudge()
		if nudgeConnection then
			nudgeConnection:Disconnect()
			nudgeConnection = nil
		end
		nudging = false
	end

	local function onInput(input: InputObject)
		local inputType = input.UserInputType
		if
			inputType == Enum.UserInputType.MouseWheel
			or inputType == Enum.UserInputType.Touch
			or inputType == Enum.UserInputType.MouseButton1
		then
			session.scrolled = true
			stopNudge()
			hint.Visible = false
		end
	end

	local function nudge()
		if nudging or session.scrolled or session.nudges >= MAX_NUDGES then
			return
		end
		nudging = true
		local maxPosition = scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y
		local from, step, elapsed = 0, 1, 0
		session.nudges += 1
		nudgeConnection = RunService.RenderStepped:Connect(function(dt)
			if session.scrolled or not scroll.Visible then
				stopNudge()
				return
			end
			local target = math.min(NUDGE_STEPS[step][1], maxPosition)
			elapsed += dt
			local t = math.clamp(elapsed / NUDGE_STEPS[step][2], 0, 1)
			scroll.CanvasPosition = Vector2.new(0, from + (target - from) * ease(t))
			if t >= 1 then
				from, elapsed, step = target, 0, step + 1
				if step > #NUDGE_STEPS then
					stopNudge()
				end
			end
		end)
	end

	local revealToken = 0
	local function reveal()
		revealToken += 1
		local token = revealToken
		task.spawn(function()
			-- The content lays out a moment after it is shown.
			local deadline = os.clock() + READY_TIMEOUT
			while os.clock() < deadline and not canScroll(scroll) do
				task.wait(0.05)
			end
			if token ~= revealToken or not canScroll(scroll) then
				hint.Visible = false
				return
			end
			scrollbar.flash(OPEN_FLASH_SECONDS)
			hint.Visible = not session.scrolled and scroll.CanvasPosition.Y < 8
			task.wait(NUDGE_DELAY)
			if token == revealToken and scroll.CanvasPosition.Y < 2 then
				nudge()
			end
		end)
	end

	local connections = {
		scroll.InputBegan:Connect(onInput),
		scroll.InputChanged:Connect(onInput),
		scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			if not nudging and scroll.CanvasPosition.Y > HINT_HIDE_AFTER then
				hint.Visible = false
			end
		end),
		RunService.RenderStepped:Connect(function(dt)
			if not hint.Visible then
				return
			end
			bobTime += dt
			chevron.Position = UDim2.new(0.5, 0, 1, -10 + math.sin(bobTime * 4) * CHEVRON_BOB)
			-- A transparent scroll over an untinted backdrop names its real surface colour.
			local surface = scroll:GetAttribute("AffordanceColor")
			hint.BackgroundColor3 = if typeof(surface) == "Color3" then surface else scroll.BackgroundColor3
		end),
	}

	return {
		reveal = reveal,
		destroy = function()
			stopNudge()
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
			scrollbar.destroy()
			hint:Destroy()
		end,
	}
end

return ScrollAffordance
