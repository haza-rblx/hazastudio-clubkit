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
local UIMotion = require(script.Parent.Parent.Utils.UIMotion)
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
	self._stateApplied = false
	self._tweens = {} :: { Tween }
	-- Stop functions for the idle pulses, and the connections press/hover feedback owns.
	self._stops = {} :: { () -> () }
	self._connections = {} :: { RBXScriptConnection }
	-- The card's own resting scale lives on self._scale; the breathing needs a UIScale of its
	-- own on the wrapper, and only where scaling the wrapper cannot move anything else.
	self._wrapperScale = if self._wrapper and UIMotion.canScale(self._wrapper)
		then getOrCreateScale(self._wrapper)
		else nil
	self._rotation = nil :: any
	self._running = false
	self._dismissed = false

	self:_wire()
	-- Whatever the template was saved as, the card starts hidden: it earns the
	-- screen with its entrance, and a buyer with the feature off never sees it.
	frame.Visible = false
	return self
end

-- ============================================================
-- Motion bookkeeping — everything started here is stoppable, so hiding the card
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

-- Every loop and channel this card owns, put back at rest.
function FreeTitleEventUI:_stopMotion()
	for _, stop in ipairs(self._stops) do
		stop()
	end
	table.clear(self._stops)
	self:_stopTweens()
	UIMotion.cancel(self._frame)
	UIMotion.cancel(self._scale)
	if self._wrapperScale then
		UIMotion.cancel(self._wrapperScale)
	end
end

-- MotionPresets.scaledTime without a second require: MOTION_SCALE stretches every UIMotion
-- tween, so the steps chained off one have to stretch with it.
function FreeTitleEventUI:_scaledTime(seconds: number): number
	local motion = (Config :: any).UIMotion
	local scale = if type(motion) == "table" then (tonumber(motion.MOTION_SCALE) or 1) else 1
	return seconds * math.clamp(scale, 0.25, 2)
end

-- The card sits in the buyer's own IconGroup. Where that group lays its children out, both
-- Position and a UIScale belong to the layout — travelling or scaling the card would shove
-- the icons beside it — so the entrance and exit degrade to a plain show/hide (ADR 0011).
function FreeTitleEventUI:_isLaidOut(): boolean
	local parent = self._frame.Parent
	return parent ~= nil and parent:FindFirstChildWhichIsA("UIGridStyleLayout") ~= nil
end

function FreeTitleEventUI:_bindButtonMotion(button: GuiObject)
	for _, connection in ipairs(UIMotion.bindPress(button)) do
		table.insert(self._connections, connection)
	end
	for _, connection in ipairs(UIMotion.bindHover(button)) do
		table.insert(self._connections, connection)
	end
end

function FreeTitleEventUI:_wire()
	self:_bindButtonMotion(self._openButton)
	self._openButton.AutoButtonColor = false
	table.insert(
		self._connections,
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
	)

	local close = self._closeButton
	if close and close:IsA("GuiButton") then
		self:_bindButtonMotion(close)
		close.AutoButtonColor = false
		table.insert(
			self._connections,
			close.Activated:Connect(function()
				-- The player's own call: it stays gone for the session rather than
				-- popping back on the next payload.
				self._dismissed = true
				self:hide()
			end)
		)
	end
end

-- ============================================================
-- Idle life
-- ============================================================

-- The idle motions are ping-pong loops rather than per-frame work, so an idle card costs
-- nothing measurable — and each one hands back a stop function that hide() drains.
function FreeTitleEventUI:_startIdle()
	local c = cfg()

	if self._sunburst and self._sunburst:IsA("ImageLabel") then
		self._rotation = AnimationHelper:startRotation(self._sunburst, c.ROTATION_SPEED)
	end

	-- The float: Position only where the layout is not the one deciding it.
	if not self:_isLaidOut() then
		table.insert(
			self._stops,
			UIMotion.pulse(self._frame, "Position", offsetY(self._restingPos, -c.BOB_OFFSET), c.BOB_TIME)
		)
	end

	-- The breathing scale — the card's one persistent pulse. self._wrapperScale is nil
	-- wherever scaling the wrapper could move a sibling or re-raster a CanvasGroup.
	if self._wrapperScale then
		table.insert(self._stops, UIMotion.pulse(self._wrapperScale, "Scale", c.BREATHE_SCALE, c.BREATHE_TIME))
	end

	-- The one raw tween left in this file: the gold sweep has to repeat WITHOUT reversing and
	-- with a pause between sweeps, and UIMotion.pulse is a ping-pong by definition — a sheen
	-- running backwards reads as a glitch. Reduced motion is honoured by skipping it outright.
	if self._shine and not UIMotion.reduced() then
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
	-- Only while the card is actually living on screen.
	if not self._running then
		return
	end
	local c = cfg()
	-- pop bounces on a UIScale of its own, so it no longer has to hand the breathing loop
	-- its resting scale back afterwards — the two multiply instead of fighting.
	local target: GuiObject = if self._wrapper and UIMotion.canScale(self._wrapper)
		then self._wrapper
		else self._frame
	UIMotion.pop(target, c.PULSE_SCALE, c.PULSE_TIME / 2)
	UIMotion.wiggle(self._frame, c.PULSE_TILT)
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
	-- Overhead and level payloads echo the whole state on every refresh. Only a real change
	-- may repaint or animate, or the card would shake itself apart on a still screen.
	local changed = (not self._stateApplied) or self._unlocked ~= unlocked
	self._stateApplied = true
	self._unlocked = unlocked

	if changed and (self._openButton:IsA("TextButton") or self._openButton:IsA("ImageButton")) then
		self._openButton.Interactable = unlocked
	end
	if changed and not unlocked and self._running then
		-- "Not yet" said in motion: rotation only, so nothing about the layout moves.
		UIMotion.wiggle(self._frame, c.PULSE_TILT * 2)
	end
	if not self._openLabel then
		return
	end
	if unlocked then
		self:_setOpenLabel(self._openLabelText or self._openLabel.Text)
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
		self:_setOpenLabel(self._openLabelText or self._openLabel.Text)
		return
	end
	local amount = math.max(1, math.floor(tonumber(pending.requirement) or 1))
	if pending.axis == "robux" then
		self:_setOpenLabel(string.format(c.MSG_LOCKED_ROBUX, amount))
	elseif pending.axis == "cash" then
		self:_setOpenLabel(string.format(c.MSG_LOCKED_CASH, DonationAmountFormat.formatCash(amount)))
	else
		self:_setOpenLabel(string.format(c.MSG_LOCKED_LEVEL, amount))
	end
end

-- Same wording arriving again is not a repaint.
function FreeTitleEventUI:_setOpenLabel(text: string)
	local label = self._openLabel
	if label and label.Text ~= text then
		label.Text = text
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
		self._frame.Rotation = 0
		-- The resting scale is the card's size, not part of the entrance: popIn grows a
		-- UIScale of its own on top of it, so a phone-scaled card still lands at its own size.
		self._scale.Scale = restingScale()
		local canTravel = not self:_isLaidOut()
		self._frame.Position = if canTravel
			then offsetX(self._restingPos, c.ENTER_OFFSET)
			else self._restingPos
		self._frame.Visible = true

		if canTravel then
			UIMotion.tween(
				self._frame,
				c.ENTER_TIME,
				{ Position = self._restingPos },
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out
			)
		end
		UIMotion.popIn(self._frame, 0.75)

		task.delay(self:_scaledTime(c.ENTER_TIME), function()
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
	self:_stopMotion()
	if self._rotation then
		AnimationHelper:stopRotation(self._rotation)
		self._rotation = nil
	end

	local function settle()
		self._frame.Visible = false
		self._frame.Position = self._restingPos
		self._frame.Rotation = 0
		self._scale.Scale = restingScale()
		if self._wrapperScale then
			self._wrapperScale.Scale = 1
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
	-- Travelling off the right edge and shrinking both need a card the layout is not placing.
	if self:_isLaidOut() then
		settle()
		return
	end
	UIMotion.tween(
		self._frame,
		c.EXIT_TIME,
		{ Position = offsetX(self._restingPos, c.ENTER_OFFSET) },
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	UIMotion.tween(
		self._scale,
		c.EXIT_TIME,
		{ Scale = 0.75 * restingScale() },
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	-- An entrance that started while this exit was still running owns the card now.
	local token = self._runToken
	task.delay(self:_scaledTime(c.EXIT_TIME), function()
		if self._runToken == token then
			settle()
		end
	end)
end

function FreeTitleEventUI:isVisible(): boolean
	return self._frame.Visible == true
end

function FreeTitleEventUI:destroy()
	-- hide(true) has already drained every loop; this is the press/hover feedback and the
	-- two Activated handlers, which the old press handles never actually released.
	self:hide(true)
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
end

return FreeTitleEventUI
