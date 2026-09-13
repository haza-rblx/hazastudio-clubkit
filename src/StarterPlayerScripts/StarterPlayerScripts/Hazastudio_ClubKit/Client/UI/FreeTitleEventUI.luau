--!strict
-- Client/UI/FreeTitleEventUI.luau
-- Drives the buyer-installed `ADDON-FreeTitleEventTrigger` frame: a floating event
-- card that opens the self-service custom title panel.
--
-- It is a door, not a rule: pressing it does exactly what the profile menu's Title
-- row does, so `CustomTitle.MinLevel` and the change quota still apply. Nothing
-- here talks to the server.
--
-- The frame is place data inside the buyer's own `IconGroup`, so `tryCreate`
-- returns nil whenever it (or a piece it cannot animate without) is missing, and
-- the caller simply has no card.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local TitleEventDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.TitleEventDomain)
local DonationAmountFormat = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DonationAmountFormat)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
local PressFeedback = require(script.Parent.Parent.Utils.PressFeedback)
local PhoneLayout = require(script.Parent.Parent.Utils.PhoneLayout)

local FreeTitleEventUI = {}
FreeTitleEventUI.__index = FreeTitleEventUI

local function cfg(): any
	return Config.FreeTitleEvent
end

-- The card's root UIScale when it is simply sitting on screen. Read at each use,
-- not cached, so a rotated or resized viewport lands on the right size next time.
local function restingScale(): number
	if PhoneLayout.isPhoneLayout() then
		return tonumber(Config.MobileScale.FREE_TITLE_EVENT_CARD) or 1
	end
	return 1
end

local function findChild(parent: Instance?, name: string): Instance?
	return if parent then parent:FindFirstChild(name) else nil
end

local function getOrCreateScale(target: GuiObject): UIScale
	local existing = target:FindFirstChildWhichIsA("UIScale")
	if existing then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Parent = target
	return scale
end

-- Position with a vertical offset applied, keeping the scale halves intact.
local function offsetY(pos: UDim2, dy: number): UDim2
	return UDim2.new(pos.X.Scale, pos.X.Offset, pos.Y.Scale, pos.Y.Offset + dy)
end

local function offsetX(pos: UDim2, dx: number): UDim2
	return UDim2.new(pos.X.Scale, pos.X.Offset + dx, pos.Y.Scale, pos.Y.Offset)
end

function FreeTitleEventUI.tryCreate(playerGui: Instance): any?
	local host = playerGui:FindFirstChild(cfg().HOST_GUI_NAME)
	local frame = findChild(host, cfg().FRAME_NAME)
	if not frame or not frame:IsA("Frame") then
		return nil
	end

	local wrapper = findChild(frame, "Wrapper")
	local openButton = findChild(wrapper, "OpenPanelButton")
	if not (openButton and openButton:IsA("GuiButton")) then
		-- Without the button the card is decoration the player cannot use.
		return nil
	end

	local self = setmetatable({}, FreeTitleEventUI) :: any
	self._frame = frame
	self._wrapper = if wrapper and wrapper:IsA("GuiObject") then wrapper else nil
	self._openButton = openButton
	self._closeButton = frame:FindFirstChild("CloseButton", true)
	self._sunburst = findChild(frame, "RotatingBackground")
	self._shine = openButton:FindFirstChildWhichIsA("UIGradient")

	self._restingPos = frame.Position
	self._scale = getOrCreateScale(frame)
	self._openCallback = nil :: (() -> ())?
	-- The template's own wording is the unlocked wording; the locked state borrows
	-- the same label and hands it back afterwards.
	self._openLabel = openButton:FindFirstChildWhichIsA("TextLabel")
	self._openLabelText = if self._openLabel then self._openLabel.Text else nil
	self._unlocked = true
	self._tweens = {} :: { Tween }
	self._rotation = nil :: any
	self._pressHandles = {} :: { any }
	self._running = false
	self._dismissed = false

	self:_wire()
	-- Whatever the template was saved as, the card starts hidden: it earns the
	-- screen with its entrance, and a buyer with the feature off never sees it.
	frame.Visible = false
	return self
end

-- ============================================================
-- Tween bookkeeping — everything started here is stoppable, so hiding the card
-- leaves nothing animating behind it.
-- ============================================================

function FreeTitleEventUI:_track(tween: Tween): Tween
	table.insert(self._tweens, tween)
	return tween
end

function FreeTitleEventUI:_stopTweens()
	for _, tween in ipairs(self._tweens) do
		pcall(function()
			tween:Cancel()
		end)
	end
	table.clear(self._tweens)
end

function FreeTitleEventUI:_wire()
	table.insert(self._pressHandles, PressFeedback.bindPressScale(self._openButton))
	self._openButton.AutoButtonColor = false
	self._openButton.Activated:Connect(function()
		-- `Interactable` already stops this, but the callback opens a panel the
		-- server may refuse — better to never ask than to ask and be told no.
		if not self._unlocked then
			return
		end
		self:_punch()
		if self._openCallback then
			self._openCallback()
		end
	end)

	local close = self._closeButton
	if close and close:IsA("GuiButton") then
		table.insert(self._pressHandles, PressFeedback.bindPressScale(close))
		close.AutoButtonColor = false
		close.Activated:Connect(function()
			-- The player's own call: it stays gone for the session rather than
			-- popping back on the next payload.
			self._dismissed = true
			self:hide()
		end)
	end
end

-- ============================================================
-- Idle life
-- ============================================================

-- All three idle motions are ping-pong tweens (`repeatCount = -1, reverses = true`)
-- rather than per-frame work, so an idle card costs nothing measurable.
function FreeTitleEventUI:_startIdle()
	local c = cfg()

	if self._sunburst and self._sunburst:IsA("ImageLabel") then
		self._rotation = AnimationHelper:startRotation(self._sunburst, c.ROTATION_SPEED)
	end

	local bob = TweenService:Create(
		self._frame,
		TweenInfo.new(c.BOB_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = offsetY(self._restingPos, -c.BOB_OFFSET) }
	)
	self:_track(bob)
	bob:Play()

	if self._wrapper then
		local breathe = TweenService:Create(
			getOrCreateScale(self._wrapper),
			TweenInfo.new(c.BREATHE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = c.BREATHE_SCALE }
		)
		self:_track(breathe)
		breathe:Play()
	end

	if self._shine then
		self._shine.Offset = Vector2.new(-1, 0)
		local shine = TweenService:Create(
			self._shine,
			TweenInfo.new(c.SHINE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1, false, c.SHINE_DELAY),
			{ Offset = Vector2.new(1, 0) }
		)
		self:_track(shine)
		shine:Play()
	end

	-- Attention punch on its own loop, guarded by the run token so hiding the card
	-- ends it instead of leaving a thread poking at a dead frame.
	local token = self._runToken
	task.spawn(function()
		while self._running and self._runToken == token do
			task.wait(c.PULSE_INTERVAL)
			if not (self._running and self._runToken == token) then
				return
			end
			self:_punch()
		end
	end)
end

-- A short scale-and-tilt kick. Used both for the periodic pulse and as the
-- feedback when the card is pressed.
function FreeTitleEventUI:_punch()
	-- Only while the card is actually living on screen: the recovery half of this
	-- animation is guarded by the same flag, so punching a stopped card would leave
	-- its scale stuck at the peak.
	if not self._running then
		return
	end
	local c = cfg()
	local target = self._wrapper or self._frame
	local scale = getOrCreateScale(target)
	local base = if target == self._wrapper then c.BREATHE_SCALE else 1

	local up = TweenService:Create(
		scale,
		TweenInfo.new(c.PULSE_TIME / 2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = c.PULSE_SCALE }
	)
	local tiltInfo = TweenInfo.new(c.PULSE_TIME / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 1, true)
	local tilt = TweenService:Create(self._frame, tiltInfo, { Rotation = c.PULSE_TILT })
	self:_track(up)
	self:_track(tilt)
	up:Play()
	tilt:Play()
	up.Completed:Once(function()
		if not self._running then
			return
		end
		local down = TweenService:Create(
			scale,
			TweenInfo.new(c.PULSE_TIME / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ Scale = base }
		)
		self:_track(down)
		down:Play()
	end)
end

-- ============================================================
-- Public
-- ============================================================

function FreeTitleEventUI:bindOpen(callback: () -> ())
	self._openCallback = callback
end

-- Paint locked vs open from the server's own verdict. The card never decides who
-- qualifies — it only shows what the payload already says, and the server checks
-- again on every accepted title anyway.
function FreeTitleEventUI:applyState(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local c = cfg()
	-- Already able to edit by any route (level reached, or an admin-granted title):
	-- the card is just a shortcut then, so it must not read as locked.
	local unlocked = payload.canEditSpecialTitle == true or payload.titleEventMet == true
	self._unlocked = unlocked

	if self._openButton:IsA("TextButton") or self._openButton:IsA("ImageButton") then
		self._openButton.Interactable = unlocked
	end
	if not self._openLabel then
		return
	end
	if unlocked then
		self._openLabel.Text = self._openLabelText or self._openLabel.Text
		return
	end

	-- One line, one next step: the first requirement they have not reached. The
	-- server decides the order and what counts; this only words it.
	local pending = TitleEventDomain.nextUnmet({
		met = payload.titleEventMet == true,
		requirements = if type(payload.titleEventRequirements) == "table"
			then payload.titleEventRequirements
			else {},
	} :: any)
	if not pending then
		self._openLabel.Text = self._openLabelText or self._openLabel.Text
		return
	end
	local amount = math.max(1, math.floor(tonumber(pending.requirement) or 1))
	if pending.axis == "robux" then
		self._openLabel.Text = string.format(c.MSG_LOCKED_ROBUX, amount)
	elseif pending.axis == "cash" then
		self._openLabel.Text = string.format(c.MSG_LOCKED_CASH, DonationAmountFormat.formatCash(amount))
	else
		self._openLabel.Text = string.format(c.MSG_LOCKED_LEVEL, amount)
	end
end

-- Fly in from off the right edge, then settle into the idle loop. Waits for the
-- kit's own gameplay-ready attribute first: a card that plays its entrance behind
-- the loading screen has spent it for nothing.
function FreeTitleEventUI:playEntrance()
	if self._running or self._dismissed then
		return
	end
	local c = cfg()
	self._runToken = (self._runToken or 0) + 1
	local token = self._runToken

	task.spawn(function()
		local player = Players.LocalPlayer
		local attribute = Config.ClientBoot.GAMEPLAY_READY_ATTRIBUTE
		local deadline = os.clock() + c.READY_TIMEOUT
		while player:GetAttribute(attribute) ~= true and os.clock() < deadline do
			task.wait(0.25)
		end
		task.wait(c.ENTER_DELAY)
		if self._runToken ~= token or self._dismissed then
			return
		end

		self._running = true
		local rest = restingScale()
		self._frame.Rotation = 0
		self._scale.Scale = 0.75 * rest
		self._frame.Position = offsetX(self._restingPos, c.ENTER_OFFSET)
		self._frame.Visible = true

		local slide = TweenService:Create(
			self._frame,
			TweenInfo.new(c.ENTER_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = self._restingPos }
		)
		local pop = TweenService:Create(
			self._scale,
			TweenInfo.new(c.ENTER_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = rest }
		)
		self:_track(slide)
		self:_track(pop)
		slide:Play()
		pop:Play()
		slide.Completed:Once(function()
			if self._runToken ~= token or not self._running then
				return
			end
			-- Idle motion starts only once the entrance has landed, so the two never
			-- fight over Position.
			self:_startIdle()
		end)
	end)
end

function FreeTitleEventUI:hide(immediate: boolean?)
	self._runToken = (self._runToken or 0) + 1
	self._running = false
	self:_stopTweens()
	if self._rotation then
		AnimationHelper:stopRotation(self._rotation)
		self._rotation = nil
	end

	local function settle()
		self._frame.Visible = false
		self._frame.Position = self._restingPos
		self._frame.Rotation = 0
		self._scale.Scale = restingScale()
		if self._wrapper then
			getOrCreateScale(self._wrapper).Scale = 1
		end
		-- Hand the buyer's own gradient back where it started.
		if self._shine then
			self._shine.Offset = Vector2.new(0, 0)
		end
	end

	if immediate or not self._frame.Visible then
		settle()
		return
	end

	local c = cfg()
	local out = TweenService:Create(
		self._frame,
		TweenInfo.new(c.EXIT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = offsetX(self._restingPos, c.ENTER_OFFSET) }
	)
	local shrink = TweenService:Create(
		self._scale,
		TweenInfo.new(c.EXIT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = 0.75 * restingScale() }
	)
	out:Play()
	shrink:Play()
	out.Completed:Once(settle)
end

function FreeTitleEventUI:isVisible(): boolean
	return self._frame.Visible == true
end

function FreeTitleEventUI:destroy()
	self:hide(true)
	for _, handle in ipairs(self._pressHandles) do
		if type(handle) == "table" and type(handle.destroy) == "function" then
			pcall(handle.destroy)
		end
	end
	table.clear(self._pressHandles)
end

return FreeTitleEventUI
