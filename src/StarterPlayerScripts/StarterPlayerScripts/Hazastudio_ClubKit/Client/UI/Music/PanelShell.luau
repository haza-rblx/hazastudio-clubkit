--!strict
-- PATH: StarterPlayerScripts/Client/UI/Music/PanelShell.luau
-- v3 panel shell: open/close, header tabs, drag. Exposes the binder surface MusicPlayerController
-- already calls so the playback engine stays untouched. Views (Now Playing / Library / DJ) plug
-- in during Stage D; until then their render methods are intentional no-ops.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SliderSelectorUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.SliderSelectorUtil)
local AnimationHelper = require(script.Parent.Parent.Parent.Utils.AnimationHelper)
local GuiRefs = require(script.Parent.GuiRefs)

type Refs = GuiRefs.Refs

local BLUR_OPTIONS = { enableBlur = true, blurName = "MusicPlayerMainBlur", enableZoom = true }
local TAB_KEYS = { "nowplaying", "request", "dj" }
local TAB_LABEL_KEYS = { nowplaying = "nowPlaying", request = "reqSong", dj = "dj" }

-- Callback setters the controller wires in initPanel. Stored by name; views read them later.
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
}

-- Render/state methods owned by views (Stage D/E) or retired with Manage (Stage F).
local PENDING_METHODS = {
	"updateTrackDisplay",
	"startProgressTracking",
	"stopProgressTracking",
	"refreshProgressFromStore",
	"setTotalDuration",
	"renderQueue",
	"renderPlaylists",
	"renderTracks",
	"openOrUpdateVoteModal",
	"closeVoteModal",
	"openAddToQueueConfirmation",
	"setLoudnessSoundProvider",
	"setDjModeEnabled",
	"setDjPlaybackSpeed",
	"setDjEffectEnabled",
	"setDjEffectValue",
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
	self._controlAllowed = nil :: boolean?
	return self
end

function PanelShell:_connect(connection: RBXScriptConnection)
	table.insert(self._connections, connection)
end

function PanelShell:_fire(key: string, ...: any)
	local callback = self._callbacks[key]
	if callback then
		callback(...)
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
		refs.voteTrackTemplate,
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

	-- The controller only pushes isControlAllowed on change; apply the current value so a
	-- player who never gains control does not see a DJ tab that silently falls back.
	self:setControlAllowed(self._store:get().isControlAllowed == true)
	self:_applyTab(self:_activeTab())
end

function PanelShell:switchTab(tab: string)
	if not self._refs.tabFrames[tab] then
		return
	end
	if tab == "dj" and self._controlAllowed ~= true then
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
	self._anim:presentCenterPanel(self._refs.mainWrapper, nil, BLUR_OPTIONS)
end

function PanelShell:closePanel(onDone: (() -> ())?)
	self._anim:dismissCenterPanel(self._refs.mainWrapper, onDone, BLUR_OPTIONS)
end

function PanelShell:destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	table.clear(self._callbacks)
end

return PanelShell
