--!strict
-- PATH: StarterPlayerScripts/Client/UI/Music/VoteModalView.luau
-- Vote-skip modal. Lives outside the panel (the controller closes the panel when a vote starts);
-- the countdown bar refreshes at 4 Hz.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local GuiRefs = require(script.Parent.GuiRefs)
local Visuals = require(script.Parent.Visuals)

local IN_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
local OUT_INFO = TweenInfo.new(0.08, Enum.EasingStyle.Cubic, Enum.EasingDirection.In)
local FADE_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
local ENTRY_OFFSET = 6
local COUNTDOWN_INTERVAL = 0.25
local BAR_GREEN = Color3.fromRGB(84, 255, 148)
local BAR_YELLOW = Color3.fromRGB(255, 201, 84)
local BAR_RED = Color3.fromRGB(255, 84, 84)

local function backdropTransparency(): number
	local panelBlur = Config.PanelBlur
	local value = if type(panelBlur) == "table" then tonumber(panelBlur.MODAL_BACKDROP_TRANSPARENCY) else nil
	return if value then math.clamp(value, 0, 1) else 0.38
end

local VoteModalView = {}
VoteModalView.__index = VoteModalView

function VoteModalView.new(deps: { refs: GuiRefs.Refs, config: any, fire: (string, ...any) -> () })
	local self = setmetatable({}, VoteModalView) :: any
	self._refs = deps.refs.vote
	self._config = deps.config
	self._fire = deps.fire
	self._basePosition = self._refs.modal.Position
	self._sessionId = nil :: string?
	self._countdownConn = nil :: RBXScriptConnection?
	self._tween = nil :: Tween?
	self._backdropTween = nil :: Tween?
	self._connections = {} :: { RBXScriptConnection }
	return self
end

function VoteModalView:bind()
	local refs = self._refs
	refs.cardAddWrapper.Visible = false
	table.insert(
		self._connections,
		refs.rejectButton.Activated:Connect(function()
			self._fire("OnVoteSkip", "reject")
		end)
	)
	table.insert(
		self._connections,
		refs.skipButton.Activated:Connect(function()
			self._fire("OnVoteSkip", "skip")
		end)
	)
end

function VoteModalView:_cancelTweens()
	if self._tween then
		self._tween:Cancel()
		self._tween = nil
	end
	if self._backdropTween then
		self._backdropTween:Cancel()
		self._backdropTween = nil
	end
end

function VoteModalView:_stopCountdown()
	if self._countdownConn then
		self._countdownConn:Disconnect()
		self._countdownConn = nil
	end
end

function VoteModalView:_renderTime(endsAt: number, duration: number)
	local remaining = math.max(0, endsAt - Workspace:GetServerTimeNow())
	local progress = math.clamp(remaining / duration, 0, 1)
	local fill = self._refs.barFill
	fill.Size = UDim2.new(progress, 0, 1, 0)
	fill.BackgroundColor3 = if progress >= 0.5
		then BAR_YELLOW:Lerp(BAR_GREEN, (progress - 0.5) / 0.5)
		else BAR_RED:Lerp(BAR_YELLOW, progress / 0.5)
end

function VoteModalView:_populate(data: any)
	local refs = self._refs
	local skipVotes = tonumber(data.skipVotes) or 0
	local rejectVotes = tonumber(data.rejectVotes) or 0
	local totalVotes = tonumber(data.totalVotes) or 0
	Visuals.setText(
		refs.title,
		string.format("%s thinks we should skip this one:", tostring(data.initiatorDisplayName or "Someone"))
	)
	Visuals.setText(refs.rejectLabel, string.format("Nah, let it play (%d/%d)", rejectVotes, totalVotes))
	Visuals.setText(refs.skipLabel, string.format("Yeah, skip it (%d/%d)", skipVotes, totalVotes))

	local track = data.track
	if type(track) ~= "table" then
		Visuals.setVisible(refs.card, false)
		return
	end
	local playlist = data.playlist
	local hasPlaylist = type(playlist) == "table"
	Visuals.setVisible(refs.card, true)
	Visuals.setText(refs.cardTitle, tostring(track.name or ""))
	Visuals.setText(refs.cardCreator, tostring(track.creator or ""))
	Visuals.setText(refs.cardLength, Visuals.formatClock(tonumber(track.totalDuration) or 0))
	Visuals.setText(refs.cardPlaylistName, if hasPlaylist then tostring(playlist.name or "") else "")
	Visuals.setVisible(refs.cardPlaylistName, not (hasPlaylist and playlist.coverType == "image"))
	Visuals.applyCover(refs.cardCover, playlist, self._config)
end

function VoteModalView:open(data: any)
	local refs = self._refs
	local sessionId = tostring(data.sessionId or "")
	local isNewSession = self._sessionId ~= sessionId
	self._sessionId = sessionId

	local startedAt = tonumber(data.startedAt) or Workspace:GetServerTimeNow()
	local endsAt = tonumber(data.endsAt) or (startedAt + (tonumber(self._config.VOTE_SKIP_DURATION) or 15))
	local duration = math.max(0.001, endsAt - startedAt)
	self:_populate(data)
	self:_stopCountdown()
	self:_renderTime(endsAt, duration)
	local accum = 0
	self._countdownConn = RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < COUNTDOWN_INTERVAL then
			return
		end
		accum = 0
		self:_renderTime(endsAt, duration)
	end)

	self:_cancelTweens()
	local backdrop = refs.backdrop
	backdrop.ZIndex = math.max(refs.modal.ZIndex - 1, 0)
	backdrop.BackgroundTransparency = backdropTransparency()
	backdrop.Active = true
	backdrop.Visible = true

	local base = self._basePosition
	if isNewSession or not refs.modal.Visible then
		refs.modal.Position = UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, base.Y.Offset - ENTRY_OFFSET)
		refs.modal.Visible = true
		local tween = TweenService:Create(refs.modal, IN_INFO, { Position = base })
		self._tween = tween
		tween:Play()
	elseif refs.modal.Position ~= base then
		refs.modal.Position = base
	end
end

function VoteModalView:close(immediate: boolean?)
	local refs = self._refs
	local base = self._basePosition
	self._sessionId = nil
	self:_stopCountdown()
	self:_cancelTweens()
	refs.backdrop.Active = false

	if immediate or not refs.modal.Visible then
		refs.modal.Visible = false
		refs.modal.Position = base
		refs.backdrop.Visible = false
		return
	end

	local tween = TweenService:Create(refs.modal, OUT_INFO, {
		Position = UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, base.Y.Offset - ENTRY_OFFSET),
	})
	local backdropTween = TweenService:Create(refs.backdrop, FADE_INFO, { BackgroundTransparency = 1 })
	self._tween = tween
	self._backdropTween = backdropTween
	tween.Completed:Once(function()
		if self._tween ~= tween then
			return
		end
		self._tween = nil
		self._backdropTween = nil
		refs.modal.Visible = false
		refs.modal.Position = base
		refs.backdrop.Visible = false
	end)
	backdropTween:Play()
	tween:Play()
end

function VoteModalView:destroy()
	self:_stopCountdown()
	self:_cancelTweens()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
end

return VoteModalView
