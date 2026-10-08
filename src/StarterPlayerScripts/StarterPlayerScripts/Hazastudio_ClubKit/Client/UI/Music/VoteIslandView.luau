--!strict
-- Vote-skip prompt as a notification island (owner, 2026-10-07; spec §4b "V1" of
-- docs/plans/ui-experiments-dance-acm-2026-10-07.md). Replaces the centred VoteModal when
-- Config.NotificationIsland.VOTE_ENABLED is on; same interface as VoteModalView, so PanelShell
-- swaps one for the other.
--
-- Flow: pill ("Rio wants to skip · 0:15") -> card (track, tally, Keep it / Skip) that stays until
-- you vote -> progress pill -> result pill -> collapse. The initiator has already voted skip, so
-- they get the progress pill straight away.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local KitLook = require(script.Parent.Parent.KitLook)
local NotificationIsland = require(script.Parent.Parent.NotificationIsland)
local UIMotion = require(script.Parent.Parent.Parent.Utils.UIMotion)
local Visuals = require(script.Parent.Visuals)

local C = KitLook.COLOR
local MUTED = '<font color="#828282">%s</font>'
local TICK = 0.25
local TALLY_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local RESULT_HOLD = 2.4

type State = { data: any, voted: string?, config: any }

local VoteIslandView = {}
VoteIslandView.__index = VoteIslandView

local function errorColor(): Color3
	return Config.Notify.COLOR_ERROR
end

local function esc(text: any): string
	return (string.gsub(tostring(text or ""), "[&<>\"]", {
		["&"] = "&amp;",
		["<"] = "&lt;",
		[">"] = "&gt;",
		['"'] = "&quot;",
	}))
end

local function remaining(data: any): number
	local endsAt = tonumber(data.endsAt) or Workspace:GetServerTimeNow()
	return math.max(0, endsAt - Workspace:GetServerTimeNow())
end

local function counts(data: any): (number, number, number, number)
	local skip = tonumber(data.skipVotes) or 0
	local keep = tonumber(data.rejectVotes) or 0
	local total = math.max(tonumber(data.totalVotes) or 1, 1)
	local need = tonumber(data.requiredVotes) or (math.floor(total / 2) + 1)
	return skip, keep, total, need
end

local function grow(instance: Instance)
	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = instance
end

local function cover(parent: Instance, state: State, size: number, radius: number, order: number): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = "Cover"
	image.BackgroundColor3 = C.row
	image.BorderSizePixel = 0
	image.ScaleType = Enum.ScaleType.Crop
	image.Size = UDim2.fromOffset(size, size)
	image.LayoutOrder = order
	image.ClipsDescendants = true
	KitLook.corner(image, UDim.new(0, radius))
	image.Parent = parent
	local data = state.data
	if type(data.track) == "table" then
		pcall(Visuals.applyTrackCover, image, data.track, data.playlist, state.config, { compact = true })
	end
	return image
end

-- Two stacked lines beside a leading visual; returns both labels.
local function lines(parent: Instance, order: number): (Frame, TextLabel, TextLabel)
	local column = KitLook.box(parent, "Lines", UDim2.new(0, 0, 1, 0), order)
	grow(column)
	KitLook.list(column, Enum.FillDirection.Vertical, 0, nil, Enum.VerticalAlignment.Center)
	local first = KitLook.text(column, "", 12, Enum.FontWeight.SemiBold, C.sub, 0, { truncate = true, rich = true })
	local second = KitLook.text(column, "", 14, Enum.FontWeight.Bold, C.white, 1, { truncate = true })
	return column, first, second
end

local function pillFrame(content: Frame)
	KitLook.padding(content, 6, 0, 16, 0)
	KitLook.list(content, Enum.FillDirection.Horizontal, 10, nil, Enum.VerticalAlignment.Center)
end

-- Skip share from the left (error colour), keep share from the right (white), a mark at the
-- threshold. Returns a painter that tweens to new counts.
local function tallyBar(parent: Instance, height: number, order: number): (data: any) -> ()
	local bar = KitLook.box(parent, "Tally", UDim2.new(1, 0, 0, height), order, C.white, 0.9)
	KitLook.corner(bar, UDim.new(1, 0))
	local skipFill = KitLook.box(bar, "Skip", UDim2.fromScale(0, 1), 0, errorColor())
	KitLook.corner(skipFill, UDim.new(1, 0))
	local keepFill = KitLook.box(bar, "Keep", UDim2.fromScale(0, 1), 0, C.white)
	keepFill.AnchorPoint = Vector2.new(1, 0)
	keepFill.Position = UDim2.fromScale(1, 0)
	KitLook.corner(keepFill, UDim.new(1, 0))
	local mark = KitLook.box(bar, "Mark", UDim2.new(0, 2, 1, 4), 0, C.white)
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, 0.5)
	mark.ZIndex = 3
	local first = true
	return function(data: any)
		local skip, keep, total, need = counts(data)
		local goals = {
			{ skipFill, { Size = UDim2.fromScale(math.clamp(skip / total, 0, 1), 1) } },
			{ keepFill, { Size = UDim2.fromScale(math.clamp(keep / total, 0, 1), 1) } },
			{ mark, { Position = UDim2.fromScale(math.clamp(need / total, 0, 1), 0.5) } },
		}
		for _, goal in ipairs(goals) do
			local target = goal[1] :: Frame
			if first then
				for property, value in pairs(goal[2]) do
					(target :: any)[property] = value
				end
			else
				TweenService:Create(target, TALLY_INFO, goal[2]):Play()
			end
		end
		first = false
	end
end

local function invitePill(content: Frame, state: State)
	pillFrame(content)
	KitLook.headshot(content, tonumber(state.data.initiatorUserId), 32, 0)
	local _, first, second = lines(content, 1)
	local function paint(now: State)
		local data = now.data
		first.Text = esc(data.initiatorDisplayName or "Someone") .. " wants to skip · " .. KitLook.clock(remaining(data))
		second.Text = if type(data.track) == "table" then tostring(data.track.name or "") else ""
	end
	paint(state)
	return paint
end

local function progressPill(content: Frame, state: State)
	pillFrame(content)
	cover(content, state, 32, 8, 0)
	local column = KitLook.box(content, "Progress", UDim2.new(0, 0, 1, 0), 1)
	grow(column)
	KitLook.list(column, Enum.FillDirection.Vertical, 5, nil, Enum.VerticalAlignment.Center)
	local top = KitLook.box(column, "Top", UDim2.new(1, 0, 0, 16), 0)
	KitLook.list(top, Enum.FillDirection.Horizontal, 8, nil, Enum.VerticalAlignment.Center)
	local label = KitLook.text(top, "", 12, Enum.FontWeight.SemiBold, errorColor(), 0, { truncate = true })
	label.Size = UDim2.new(0, 0, 1, 0)
	grow(label)
	local timer = KitLook.text(top, "", 13, Enum.FontWeight.Bold, C.white, 1)
	local paintBar = tallyBar(column, 4, 1)
	local function paint(now: State)
		local data = now.data
		local skip, _, _, need = counts(data)
		if now.voted == "reject" then
			label.Text = string.format("You voted keep · %d of %d to skip", skip, need)
			label.TextColor3 = C.white
		else
			label.Text = string.format("You voted skip · %d of %d", skip, need)
			label.TextColor3 = errorColor()
		end
		timer.Text = KitLook.clock(remaining(data))
		paintBar(data)
	end
	paint(state)
	return paint
end

local function resultPill(headline: string, color: Color3): NotificationIsland.Builder
	return function(content: Frame, state: State)
		pillFrame(content)
		cover(content, state, 32, 8, 0)
		local _, first, second = lines(content, 1)
		-- Result first, track second: the result is what this pill is for.
		first.Text = if type(state.data.track) == "table" then esc(state.data.track.name) else ""
		first.LayoutOrder = 1
		second.LayoutOrder = 0
		second.Text = headline
		second.TextColor3 = color
		return nil
	end
end

function VoteIslandView.new(deps: { refs: any, config: any, fire: (string, ...any) -> () })
	local self = setmetatable({}, VoteIslandView) :: any
	self._refs = deps.refs.vote
	self._config = deps.config
	self._fire = deps.fire
	self._sessionId = nil :: string?
	self._handle = nil :: NotificationIsland.Handle?
	self._state = nil :: State?
	self._ticker = nil :: thread?
	self._connections = {} :: { RBXScriptConnection }
	return self
end

function VoteIslandView:bind()
	-- The GUI's own modal stays hidden for good.
	local refs = self._refs
	if refs then
		if refs.modal then
			refs.modal.Visible = false
		end
		if refs.backdrop then
			refs.backdrop.Visible = false
			refs.backdrop.Active = false
		end
	end
end

function VoteIslandView:_card(): NotificationIsland.Builder
	return function(content: Frame, state: State)
		local data = state.data
		KitLook.padding(content, 14)
		KitLook.list(content, Enum.FillDirection.Vertical, 10)

		local top = KitLook.box(content, "Top", UDim2.new(1, 0, 0, 24), 0)
		KitLook.list(top, Enum.FillDirection.Horizontal, 8, nil, Enum.VerticalAlignment.Center)
		KitLook.headshot(top, tonumber(data.initiatorUserId), 24, 0)
		local who = KitLook.text(
			top,
			"<b>" .. esc(data.initiatorDisplayName or "Someone") .. "</b>" .. string.format(MUTED, " wants to skip this song"),
			14,
			Enum.FontWeight.SemiBold,
			C.white,
			1,
			{ rich = true, truncate = true }
		)
		who.Size = UDim2.new(0, 0, 1, 0)
		grow(who)
		local countdown = KitLook.text(top, "", 13, Enum.FontWeight.Bold, C.white, 2)

		local trackRow = KitLook.box(content, "Track", UDim2.new(1, 0, 0, 56), 1, C.white, 0.95)
		KitLook.corner(trackRow, UDim.new(0, 10))
		KitLook.padding(trackRow, 8)
		KitLook.list(trackRow, Enum.FillDirection.Horizontal, 10, nil, Enum.VerticalAlignment.Center)
		cover(trackRow, state, 40, 8, 0)
		local trackLines = KitLook.box(trackRow, "Lines", UDim2.new(0, 0, 1, 0), 1)
		grow(trackLines)
		KitLook.list(trackLines, Enum.FillDirection.Vertical, 1, nil, Enum.VerticalAlignment.Center)
		local track = if type(data.track) == "table" then data.track else {}
		KitLook.text(trackLines, tostring(track.name or ""), 14, Enum.FontWeight.Bold, C.white, 0, { truncate = true })
		KitLook.text(trackLines, tostring(track.creator or ""), 12, Enum.FontWeight.SemiBold, C.sub, 1, { truncate = true })

		local tally = KitLook.box(content, "Tally", UDim2.new(1, 0, 0, 0), 2)
		tally.AutomaticSize = Enum.AutomaticSize.Y
		KitLook.list(tally, Enum.FillDirection.Vertical, 6)
		local labels = KitLook.box(tally, "Labels", UDim2.new(1, 0, 0, 16), 0)
		local skipText = KitLook.text(labels, "", 13, Enum.FontWeight.SemiBold, C.white, 0, { rich = true })
		local needText = KitLook.text(labels, "", 12, Enum.FontWeight.SemiBold, C.sub, 0)
		needText.AnchorPoint = Vector2.new(0.5, 0)
		needText.Position = UDim2.fromScale(0.5, 0)
		local keepText = KitLook.text(labels, "", 13, Enum.FontWeight.SemiBold, C.white, 0, { rich = true })
		keepText.AnchorPoint = Vector2.new(1, 0)
		keepText.Position = UDim2.fromScale(1, 0)
		for _, label in ipairs({ skipText, needText, keepText }) do
			label.Size = UDim2.new(0, 0, 1, 0)
			label.AutomaticSize = Enum.AutomaticSize.X
		end
		local paintBar = tallyBar(tally, 6, 1)

		local buttons = KitLook.box(content, "Buttons", UDim2.new(1, 0, 0, 36), 3)
		KitLook.list(buttons, Enum.FillDirection.Horizontal, 8)
		local keep = KitLook.choiceButton(buttons, "Keep it", 0, false)
		local skip = KitLook.choiceButton(buttons, "Skip", 1, true)
		for _, button in ipairs({ keep, skip }) do
			grow(button)
			for _, connection in ipairs(UIMotion.bindPress(button)) do
				table.insert(self._connections, connection)
			end
		end
		table.insert(self._connections, keep.Activated:Connect(function()
			self._fire("OnVoteSkip", "reject")
		end))
		table.insert(self._connections, skip.Activated:Connect(function()
			self._fire("OnVoteSkip", "skip")
		end))

		local hex = errorColor():ToHex()
		local function paint(now: State)
			local nextData = now.data
			local skipVotes, keepVotes, total, need = counts(nextData)
			countdown.Text = KitLook.clock(remaining(nextData))
			skipText.Text = string.format('<font color="#%s">Skip</font> <b>%d</b>', hex, skipVotes)
			needText.Text = string.format("need %d of %d", need, total)
			keepText.Text = string.format("<b>%d</b> Keep", keepVotes)
			paintBar(nextData)
		end
		paint(state)
		return paint
	end
end

function VoteIslandView:_stopTicker()
	if self._ticker then
		pcall(task.cancel, self._ticker)
		self._ticker = nil
	end
end

function VoteIslandView:_startTicker()
	self:_stopTicker()
	self._ticker = task.spawn(function()
		while true do
			task.wait(TICK)
			local handle = self._handle
			if not handle or not handle:isActive() or not self._state then
				break
			end
			handle:update(self._state)
		end
		self._ticker = nil
	end)
end

function VoteIslandView:open(data: any)
	if type(data) ~= "table" then
		return
	end
	local sessionId = tostring(data.sessionId or "")
	local handle = self._handle
	if sessionId == self._sessionId and handle and handle:isActive() and self._state then
		self._state.data = data
		handle:update(self._state)
		return
	end

	self._sessionId = sessionId
	local localPlayer = Players.LocalPlayer
	local isInitiator = localPlayer ~= nil and tonumber(data.initiatorUserId) == localPlayer.UserId
	local state: State = { data = data, voted = if isInitiator then "skip" else nil, config = self._config }
	self._state = state
	self:_clearConnections()
	if isInitiator then
		self._handle = NotificationIsland.show({
			key = "vote",
			priority = true,
			compact = progressPill,
			state = state,
		})
	else
		self._handle = NotificationIsland.show({
			key = "vote",
			priority = true,
			compact = invitePill,
			card = self:_card(),
			state = state,
		})
	end
	self:_startTicker()
end

-- PanelShell routes every OnVoteSkip through here, so a vote from the panel's own button lands
-- the same way as one from the card.
function VoteIslandView:noteLocalVote(voteType: string?)
	local state = self._state
	local handle = self._handle
	if not state or state.voted or not handle or not handle:isActive() then
		return
	end
	state.voted = if voteType == "reject" then "reject" else "skip"
	handle:setCompact(progressPill)
	handle:collapse()
end

function VoteIslandView:close(immediate: boolean?, data: any?)
	self:_stopTicker()
	local handle = self._handle
	local state = self._state
	self._sessionId = nil
	if not handle or not handle:isActive() or not state then
		self._handle = nil
		self._state = nil
		return
	end
	if immediate then
		handle:dismiss()
	else
		if type(data) == "table" then
			state.data = data
		end
		local result = if type(data) == "table" then data.result else nil
		local skip, _, total = counts(state.data)
		local headline, color
		if result == "passed" then
			headline, color = string.format("Skipped · %d of %d voted", skip, total), errorColor()
		elseif result == "failed" then
			headline, color = "Keeps playing · vote ended", C.white
		else
			headline, color = "Vote closed", C.white
		end
		handle:setCompact(resultPill(headline, color))
		handle:finish(RESULT_HOLD)
	end
	self._handle = nil
	self._state = nil
end

function VoteIslandView:_clearConnections()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
end

function VoteIslandView:destroy()
	self:_stopTicker()
	if self._handle then
		self._handle:dismiss()
		self._handle = nil
	end
	self:_clearConnections()
end

return VoteIslandView
