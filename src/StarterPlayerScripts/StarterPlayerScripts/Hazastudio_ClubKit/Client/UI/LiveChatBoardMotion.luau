--!strict
-- Client/UI/LiveChatBoardMotion.luau
-- Chat-bubble look for the workspace live chat board (LiveChatDonations / LiveChatGUI), owner
-- design 2026-10-10. Runs after DonationNotificationController has written the board's texts:
--   * colour by source — cash accent orange, Robux green — on bubble, tail, amount chip, avatar ring
--   * amount label "Rp 50.000" / "50 Robux", counted up from 0
--   * the bubble hugs its message (largest text size that fits, then trimmed to what rendered)
--   * the message types itself in; the avatar ring flashes, then breathes while the card stays up
-- Only boards built for it take part: the bubble design has a `BubbleTail` under DonationMessage.
-- A venue still on the old board layout is left exactly as before.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local CashCurrencyDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.CashCurrencyDomain)
local DonationAmountFormat = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DonationAmountFormat)

local LiveChatBoardMotion = {}

local CASH_COLOR = Color3.fromHex("ea4b07")
local ROBUX_COLOR = Color3.fromHex("00a35c")
-- Bubble limits in the board's design units (the 519x232 canvas the GUI is laid out in).
-- A board can override them with attributes on DonationMessage.
local DEFAULT_MAX_WIDTH = 349
local DEFAULT_MAX_TEXT_HEIGHT = 78
local PAD_X = 18
local PAD_Y = 10
local TEXT_SIZE_MAX = 26
local TEXT_SIZE_MIN = 14
local COUNT_SECONDS = 1.1
local TYPE_DELAY = 0.25

type BoardState = {
	token: number,
	trimBound: boolean,
	breathe: Tween?,
}

local states: { [Instance]: BoardState } = {}

local function formatAmount(source: string?, amount: number): string
	local grouped = DonationAmountFormat.formatGrouped(math.floor(amount))
	if source == "robux" then
		return grouped .. " Robux"
	end
	return CashCurrencyDomain.getActive().symbol .. grouped
end

local function bubbleLimits(message: TextLabel): (number, number)
	local maxWidth = tonumber(message:GetAttribute("BubbleMaxWidth")) or DEFAULT_MAX_WIDTH
	local maxHeight = tonumber(message:GetAttribute("BubbleMaxTextHeight")) or DEFAULT_MAX_TEXT_HEIGHT
	return maxWidth, maxHeight
end

-- TextBounds is in screen pixels (the board's PixelsPerStud and UIScale); the size is set in design
-- units, so convert with the bubble's own pixels-per-unit before trimming.
local function trimBubble(message: TextLabel)
	if message.TextScaled or message.Size.X.Offset <= 0 then
		return
	end
	local ratio = message.AbsoluteSize.X / message.Size.X.Offset
	if ratio <= 0 then
		return
	end
	local maxWidth = bubbleLimits(message)
	local wantHeight = math.max(math.ceil(message.TextBounds.Y / ratio), message.TextSize) + PAD_Y * 2
	local wantWidth = math.min(math.ceil(message.TextBounds.X / ratio), maxWidth) + PAD_X * 2 + 2
	if math.abs(message.Size.Y.Offset - wantHeight) > 1 or math.abs(message.Size.X.Offset - wantWidth) > 1 then
		message.Size = UDim2.fromOffset(wantWidth, wantHeight)
	end
end

-- Largest size from TEXT_SIZE_MAX down that fits the bubble; the bubble then starts at full width
-- and trimBubble narrows it to the text once it has rendered.
local function fitBubble(message: TextLabel)
	local maxWidth, maxHeight = bubbleLimits(message)
	message.TextScaled = false
	local params = Instance.new("GetTextBoundsParams")
	params.Text = message.Text
	params.Font = message.FontFace
	params.Width = maxWidth
	local size = TEXT_SIZE_MAX
	while size > TEXT_SIZE_MIN do
		params.Size = size
		local ok, bounds = pcall(function()
			return TextService:GetTextBoundsAsync(params)
		end)
		if ok and bounds.Y <= maxHeight then
			break
		end
		size -= 2
	end
	message.TextSize = size
	message.Size = UDim2.fromOffset(maxWidth + PAD_X * 2 + 2, maxHeight + PAD_Y * 2)
end

function LiveChatBoardMotion.isBubbleBoard(message: TextLabel?): boolean
	return message ~= nil and message:FindFirstChild("BubbleTail") ~= nil
end

function LiveChatBoardMotion.present(refs: any, source: string?, amount: number)
	local message: TextLabel? = refs.liveDonationMessage
	if not message or not LiveChatBoardMotion.isBubbleBoard(message) then
		return
	end
	local chip: TextLabel? = refs.liveTotalDonations
	local wrapper: Frame? = refs.liveMessageWrapper
	local tail = message:FindFirstChild("BubbleTail") :: GuiObject
	local ring = if refs.liveAvatar then refs.liveAvatar:FindFirstChildOfClass("UIStroke") else nil

	local state = states[message]
	if not state then
		state = { token = 0, trimBound = false, breathe = nil }
		states[message] = state
		message.Destroying:Connect(function()
			local s = states[message]
			if s and s.breathe then
				s.breathe:Cancel()
			end
			states[message] = nil
		end)
	end
	local current = state :: BoardState
	if not current.trimBound then
		current.trimBound = true
		message:GetPropertyChangedSignal("TextBounds"):Connect(function()
			task.defer(trimBubble, message)
		end)
		-- The wrapper's layout slot follows the bubble, so the stack stays centred on the board.
		if wrapper then
			message:GetPropertyChangedSignal("Size"):Connect(function()
				wrapper.Size = UDim2.new(1, 0, 0, message.Size.Y.Offset)
			end)
		end
	end

	current.token += 1
	local token = current.token
	local color = if source == "robux" then ROBUX_COLOR else CASH_COLOR
	message.BackgroundColor3 = color
	tail.BackgroundColor3 = color
	if chip then
		chip.BackgroundColor3 = color
	end
	if ring then
		ring.Color = color
	end

	local finalAmount = formatAmount(source, amount)
	local total = utf8.len(message.Text) or #message.Text
	message.MaxVisibleGraphemes = 0
	task.spawn(function()
		fitBubble(message)
		if current.token ~= token then
			return
		end
		local typeSeconds = math.clamp(total * 0.03, 0.6, 1.6)
		local startedAt = os.clock()
		local connection: RBXScriptConnection
		connection = RunService.Heartbeat:Connect(function()
			if current.token ~= token or not message.Parent then
				connection:Disconnect()
				return
			end
			local elapsed = os.clock() - startedAt
			message.MaxVisibleGraphemes = math.floor(total * math.clamp((elapsed - TYPE_DELAY) / typeSeconds, 0, 1) + 0.5)
			if chip then
				local k = math.clamp(elapsed / COUNT_SECONDS, 0, 1)
				k = 1 - (1 - k) ^ 3
				chip.Text = formatAmount(source, amount * k)
			end
			if elapsed >= math.max(typeSeconds + TYPE_DELAY, COUNT_SECONDS) then
				message.MaxVisibleGraphemes = -1
				if chip then
					chip.Text = finalAmount
				end
				connection:Disconnect()
			end
		end)
	end)

	if ring then
		ring.Thickness = 9
		TweenService:Create(ring, TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Thickness = 4,
		}):Play()
		if not current.breathe then
			local breathe = TweenService:Create(
				ring,
				TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Transparency = 0.45 }
			)
			current.breathe = breathe
			breathe:Play()
		end
	end
end

return LiveChatBoardMotion
