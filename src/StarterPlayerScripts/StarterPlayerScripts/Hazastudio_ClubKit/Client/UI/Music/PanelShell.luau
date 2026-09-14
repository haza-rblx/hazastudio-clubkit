--!strict
-- PATH: StarterPlayerScripts/Client/UI/Music/PanelShell.luau
-- v3 panel shell: open/close, header tabs, drag. Exposes the binder surface MusicPlayerController
-- already calls so the playback engine stays untouched, and forwards view methods to the views
-- that exist so far. Methods for views not built yet are intentional no-ops.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SliderSelectorUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.SliderSelectorUtil)
local AnimationHelper = require(script.Parent.Parent.Parent.Utils.AnimationHelper)
local DjView = require(script.Parent.DjView)
local GuiRefs = require(script.Parent.GuiRefs)
local LibraryView = require(script.Parent.LibraryView)
local NowPlayingView = require(script.Parent.NowPlayingView)
local VoteModalView = require(script.Parent.VoteModalView)

type Refs = GuiRefs.Refs

local BLUR_OPTIONS = { enableBlur = true, blurName = "MusicPlayerMainBlur", enableZoom = true }
local TAB_KEYS = { "nowplaying", "request", "dj" }
local TAB_LABEL_KEYS = { nowplaying = "nowPlaying", request = "reqSong", dj = "dj" }

-- Callback setters the controller wires in initPanel. Stored by name; views fire them.
local CALLBACK_SETTERS = {
	"setOnCloseRequested",
	"setOnTabSelected",
	"setOnToggleDjMode",
	"setOnVoteSkip",
	"setOnRequestTrack",
	"setOnAddFavoriteTrack",
	"setOnPlaylistSelected",
	"setOnSearchChanged",
	"setOnVolumeChanged",
	"setOnDjSoundboardTriggered",
	"setOnDjPlaybackSpeedChanged",
	"setOnDjEffectEnabledChanged",
	"setOnDjEffectValueChanged",
	"setOnDjResetRequested",
	"setOnManageSubView",
	"setOnManagePlaylist",
	"setOnManageTrack",
	"setOnResolveRequestAsset",
	"setOnFormNotify",
	"setOnTransport",
	"setOnAdminSkip",
}

-- v2-only (aura overlay) or retired with Manage (stage F).
local PENDING_METHODS = {
	"setLoudnessSoundProvider",
	-- Manage (moves to the dashboard, ADR 0010)
	"renderManagePlaylists",
	"renderManageTracks",
	"populateTrackForm",
	"populatePlaylistForm",
	"setManageSubView",
	"setManageAllowed",
}

local PanelShell = {}
PanelShell.__index = PanelShell

for _, setterName in ipairs(CALLBACK_SETTERS) do
	local key = string.sub(setterName, 4) -- "OnCloseRequested"
	PanelShell[setterName] = function(self: any, callback: any)
		self._callbacks[key] = callback
	end
end

for _, methodName in ipairs(PENDING_METHODS) do
	PanelShell[methodName] = function(_self: any, ...: any) end
end

function PanelShell.new(deps: { refs: Refs, store: any, config: any })
	local self = setmetatable({}, PanelShell) :: any
	self._refs = deps.refs
	self._store = deps.store
	self._config = deps.config
	self._anim = AnimationHelper.new()
	self._callbacks = {} :: { [string]: any }
	self._connections = {} :: { RBXScriptConnection }
	self._unsubscribers = {} :: { () -> () }
	self._controlAllowed = nil :: boolean?
	self._djLocked = false
	-- Returns the callback's result: DJ callbacks answer false when the change was refused.
	local fire = function(key: string, ...: any): any
		return self:_fire(key, ...)
	end
	local viewDeps = { refs = deps.refs, store = deps.store, config = deps.config, fire = fire }
	self._nowPlaying = NowPlayingView.new(viewDeps)
	self._vote = VoteModalView.new(viewDeps)
	self._library = LibraryView.new(viewDeps)
	self._dj = DjView.new(viewDeps)
	return self
end

function PanelShell:_connect(connection: RBXScriptConnection)
	table.insert(self._connections, connection)
end

function PanelShell:_fire(key: string, ...: any): any
	local callback = self._callbacks[key]
	if callback then
		return callback(...)
	end
	return nil
end

-- While DJ mode is on, players who cannot control music lose Library and Vote Skip (v2 rule).
function PanelShell:_applyDjGating()
	local state = self._store:get()
	local localPlayer = Players.LocalPlayer
	local isDjOwner = state.isDjMode == true and localPlayer ~= nil and state.djOwnerUserId == localPlayer.UserId
	local locked = state.isDjMode == true and not (isDjOwner or state.isControlAllowed == true)
	if self._djLocked == locked then
		return
	end
	self._djLocked = locked
	self._refs.tabButtons.request.Visible = not locked
	self._nowPlaying:setVoteSkipVisible(not locked)
	if locked and self:_activeTab() == "request" then
		self:switchTab("nowplaying")
	elseif self._refs.mainWrapper.Visible then
		self:_applyTab(self:_activeTab())
	end
end

function PanelShell:_activeTab(): string
	local tab = self._store:get().activeTab
	return if self._refs.tabFrames[tab] then tab else "nowplaying"
end

function PanelShell:_applyTab(tab: string)
	local refs: Refs = self._refs
	for _, key in ipairs(TAB_KEYS) do
		local selected = key == tab
		local frame = (refs.tabFrames :: any)[key]
		if frame.Visible ~= selected then
			frame.Visible = selected
		end
		SliderSelectorUtil.setTabButtonSelected((refs.tabButtons :: any)[key], selected)
	end
	-- DJ sliders need horizontal drags; the panel must not move under them.
	local dragEnabled = tab ~= "dj"
	if refs.dragDetector.Enabled ~= dragEnabled then
		refs.dragDetector.Enabled = dragEnabled
	end
	local selectedButton = (refs.tabButtons :: any)[tab]
	task.defer(function()
		if selectedButton.Parent and refs.backgroundPill.Parent then
			SliderSelectorUtil.animateSlidingPill(refs.backgroundPill, selectedButton, refs.tabButtonOrder)
		end
	end)
end

function PanelShell:bindAll()
	local refs: Refs = self._refs
	local labels = self._config.TAB_LABELS or {}

	-- Raw design templates never show at runtime.
	local templates: { GuiObject } = {
		refs.queueRowTemplate,
		refs.trackRowTemplate,
		refs.soundBoardItemTemplate,
		refs.effectTemplate,
		refs.voteModal,
		refs.backdropBlur,
	}
	for _, template in pairs(refs.playlistTemplates) do
		table.insert(templates, template)
	end
	for _, template in ipairs(templates) do
		template.Visible = false
	end

	for _, key in ipairs(TAB_KEYS) do
		local button = (refs.tabButtons :: any)[key]
		SliderSelectorUtil.applyTabLabel(button, labels[(TAB_LABEL_KEYS :: any)[key]] or key)
		self:_connect(button.Activated:Connect(function()
			if self:_activeTab() == key then
				return
			end
			self:switchTab(key)
			self:_fire("OnTabSelected", key)
		end))
	end

	self:_connect(refs.closeButton.Activated:Connect(function()
		self:_fire("OnCloseRequested")
	end))


	self._nowPlaying:bind()
	self._vote:bind()
	self._library:bind()
	self._dj:bind()

	for _, key in ipairs({ "isDjMode", "djOwnerUserId", "isControlAllowed" }) do
		table.insert(self._unsubscribers, self._store:subscribe(key, function()
			self:_applyDjGating()
		end))
	end
	self:_applyDjGating()

	-- The controller only pushes isControlAllowed on change; apply the current value so a
	-- player who never gains control does not see a DJ tab that silently falls back.
	self:setControlAllowed(self._store:get().isControlAllowed == true)
	self:_applyTab(self:_activeTab())
end

function PanelShell:switchTab(tab: string)
	if not self._refs.tabFrames[tab] then
		return
	end
	if (tab == "dj" and self._controlAllowed ~= true) or (tab == "request" and self._djLocked) then
		tab = "nowplaying"
	end
	if self._store:get().activeTab ~= tab then
		self._store:set({ activeTab = tab })
	end
	self:_applyTab(tab)
end

function PanelShell:setControlAllowed(allowed: boolean)
	if self._controlAllowed == allowed then
		return
	end
	self._controlAllowed = allowed
	self._nowPlaying:setTransportAllowed(allowed)
	local djButton = self._refs.tabButtons.dj
	djButton.Visible = allowed
	if not allowed and self:_activeTab() == "dj" then
		self:switchTab("nowplaying")
	elseif self._refs.mainWrapper.Visible then
		self:_applyTab(self:_activeTab())
	end
end

function PanelShell:openPanel()
	self:switchTab(self:_activeTab())
	self._nowPlaying:refreshProgress()
	self._anim:presentCenterPanel(self._refs.mainWrapper, nil, BLUR_OPTIONS)
end

function PanelShell:closePanel(onDone: (() -> ())?)
	self._anim:dismissCenterPanel(self._refs.mainWrapper, onDone, BLUR_OPTIONS)
end

-- ============================================================
-- Now Playing + vote (forwarded)
-- ============================================================

function PanelShell:updateTrackDisplay(track: any?)
	self._nowPlaying:updateTrack(track)
end

function PanelShell:setTotalDuration(duration: number)
	self._nowPlaying:setTotalDuration(duration)
end

function PanelShell:startProgressTracking()
	self._nowPlaying:startProgress()
end

function PanelShell:stopProgressTracking()
	self._nowPlaying:stopProgress()
end

function PanelShell:refreshProgressFromStore()
	self._nowPlaying:refreshProgress()
end

function PanelShell:renderQueue(queue: { any })
	self._nowPlaying:renderQueue(queue)
end

function PanelShell:setDjModeEnabled(enabled: boolean)
	self._nowPlaying:setDjMode(enabled)
	self._dj:setDjMode(enabled)
	self:_applyDjGating()
end

-- ============================================================
-- DJ (forwarded)
-- ============================================================

function PanelShell:setDjPlaybackSpeed(speed: number)
	self._dj:setPlaybackSpeed(speed)
end

function PanelShell:setDjEffectEnabled(effectId: string, enabled: boolean)
	self._dj:setEffectEnabled(effectId, enabled)
end

function PanelShell:setDjEffectValue(effectId: string, itemId: string, value: number)
	self._dj:setEffectValue(effectId, itemId, value)
end

function PanelShell:openOrUpdateVoteModal(data: any)
	self._vote:open(data)
	self._nowPlaying:setVoteCounts(tonumber(data.skipVotes) or 0, tonumber(data.totalVotes) or 0)
end

function PanelShell:closeVoteModal(immediate: boolean?)
	self._vote:close(immediate)
	self._nowPlaying:setVoteCounts(nil, nil)
end

-- ============================================================
-- Library (forwarded)
-- ============================================================

function PanelShell:renderPlaylists(playlists: { [string]: any }?, query: string?)
	self._library:renderPlaylists(playlists, query)
end

function PanelShell:renderTracks(tracks: { [any]: any }?, query: string?)
	self._library:renderTracks(tracks, query)
end

function PanelShell:openAddToQueueConfirmation(track: any, _parentPlaylist: any?)
	self._library:requestResolvedTrack(track)
end

function PanelShell:destroy()
	self._nowPlaying:destroy()
	self._vote:destroy()
	self._library:destroy()
	self._dj:destroy()
	for _, unsubscribe in ipairs(self._unsubscribers) do
		unsubscribe()
	end
	table.clear(self._unsubscribers)
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	table.clear(self._callbacks)
end

return PanelShell
