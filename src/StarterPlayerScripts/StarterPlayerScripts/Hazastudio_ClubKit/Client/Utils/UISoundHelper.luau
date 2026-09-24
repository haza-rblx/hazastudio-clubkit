--!strict

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local AssetHealthReporter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.AssetHealthReporter)
local InstanceState = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.InstanceState)

local localPlayer = Players.LocalPlayer
local log = Logger.new("UISoundHelper")

type SoundConfig = {
	ENABLED: boolean,
	HOVER_SOUND_ID: string,
	CLICK_SOUND_ID: string,
	HOVER_VOLUME: number,
	CLICK_VOLUME: number,
	HOVER_PLAYBACK_SPEED: number,
	CLICK_PLAYBACK_SPEED: number,
	ROLLOFF_MAX_DISTANCE: number,
}

type Dependencies = {
	config: SoundConfig,
}

export type UISoundHelper = {
	_config: SoundConfig,
	-- The bind-once guard and the bind's connections, one STRONG record per button reclaimed on its
	-- `Destroying` (InstanceState; ADR 0011 addendum, 2026-09-17). Weak keys dropped the guard while
	-- the button lived, so a pooled row re-parented into PlayerGui was bound twice: two click sounds.
	_buttonConnections: InstanceState.Store<{ RBXScriptConnection }>,
	_connections: { RBXScriptConnection },
	_hoverTemplate: Sound,
	_clickTemplate: Sound,
	_assetReporter: any,
	_canPlay: (self: UISoundHelper, button: GuiButton) -> boolean,
	_playTemplate: (self: UISoundHelper, template: Sound) -> (),
	_validateTemplate: (self: UISoundHelper, template: Sound, sourcePath: string) -> (),
	_disconnectButton: (self: UISoundHelper, button: GuiButton) -> (),
	_bindButton: (self: UISoundHelper, button: GuiButton) -> (),
	init: (self: UISoundHelper) -> (),
	destroy: (self: UISoundHelper) -> (),
}

local DISABLE_ATTRIBUTE = "DisableUISFX"
local HOVER_SOUNDS_ENABLED = false -- Temporary kill switch while hover SFX direction is being reviewed.

local UISoundHelper = {}
UISoundHelper.__index = UISoundHelper

local function createTemplate(
	name: string,
	soundId: string,
	volume: number,
	playbackSpeed: number,
	maxDistance: number
): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Volume = volume
	sound.PlaybackSpeed = playbackSpeed
	sound.RollOffMaxDistance = maxDistance
	sound.Parent = SoundService

	return sound
end

function UISoundHelper.new(deps: Dependencies): UISoundHelper
	local self: UISoundHelper = setmetatable({} :: any, UISoundHelper)

	self._config = deps.config
	self._buttonConnections = InstanceState.new(function(): { RBXScriptConnection }
		return {}
	end)
	self._connections = {}
	self._assetReporter = AssetHealthReporter.new(log)
	self._hoverTemplate = createTemplate(
		"UIHoverTemplate",
		deps.config.HOVER_SOUND_ID,
		deps.config.HOVER_VOLUME,
		deps.config.HOVER_PLAYBACK_SPEED,
		deps.config.ROLLOFF_MAX_DISTANCE
	)
	self._clickTemplate = createTemplate(
		"UIClickTemplate",
		deps.config.CLICK_SOUND_ID,
		deps.config.CLICK_VOLUME,
		deps.config.CLICK_PLAYBACK_SPEED,
		deps.config.ROLLOFF_MAX_DISTANCE
	)

	return self
end

function UISoundHelper:_canPlay(button: GuiButton): boolean
	if button:GetAttribute(DISABLE_ATTRIBUTE) == true then
		return false
	end

	return button.Visible
end

function UISoundHelper:_playTemplate(template: Sound): ()
	if template.SoundId == "" or template.SoundId == "rbxassetid://0" then
		return
	end

	local sound = template:Clone()
	sound.Parent = SoundService
	sound:Play()
	-- Play() (not PlayLocalSound) so Ended fires; Debris is a safety net.
	sound.Ended:Once(function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	local lifetime = sound.TimeLength
	Debris:AddItem(sound, if lifetime > 0 then lifetime + 1 else 8)
end

function UISoundHelper:_validateTemplate(template: Sound, sourcePath: string): ()
	if template.SoundId == "" or template.SoundId == "rbxassetid://0" then
		return
	end

	local ok, err = pcall(function()
		ContentProvider:PreloadAsync({ template })
	end)
	if not ok then
		self._assetReporter:recordSourceFailure("Sound", sourcePath, template.SoundId, "UISoundHelper.init", err, {
			templateName = template.Name,
		})
	end
end

function UISoundHelper:_disconnectButton(button: GuiButton): ()
	local connections = self._buttonConnections.get(button)
	if not connections then
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	self._buttonConnections.drop(button)
end

function UISoundHelper:_bindButton(button: GuiButton): ()
	if button:GetAttribute(DISABLE_ATTRIBUTE) == true then
		return
	end
	if self._buttonConnections.get(button) then
		return
	end

	local buttonConnections = self._buttonConnections.of(button)

	if HOVER_SOUNDS_ENABLED then
		table.insert(
			buttonConnections,
			button.MouseEnter:Connect(function()
				if not self:_canPlay(button) then
					return
				end

				self:_playTemplate(self._hoverTemplate)
			end)
		)

		table.insert(
			buttonConnections,
			button.SelectionGained:Connect(function()
				if not self:_canPlay(button) then
					return
				end

				self:_playTemplate(self._hoverTemplate)
			end)
		)
	end

	table.insert(
		buttonConnections,
		button.Activated:Connect(function()
			if not self:_canPlay(button) then
				return
			end

			self:_playTemplate(self._clickTemplate)
		end)
	)

	table.insert(
		buttonConnections,
		button.Destroying:Connect(function()
			self:_disconnectButton(button)
		end)
	)
end

function UISoundHelper:init(): ()
	if not self._config.ENABLED then
		return
	end

	task.spawn(function()
		if HOVER_SOUNDS_ENABLED then
			self:_validateTemplate(self._hoverTemplate, "Config.UISFX.HOVER_SOUND_ID")
		end
		self:_validateTemplate(self._clickTemplate, "Config.UISFX.CLICK_SOUND_ID")
	end)

	local playerGui = localPlayer:WaitForChild("PlayerGui")

	for _, desc in ipairs(playerGui:GetDescendants()) do
		if desc:IsA("GuiButton") then
			self:_bindButton(desc)
		end
	end

	table.insert(
		self._connections,
		playerGui.DescendantAdded:Connect(function(desc)
			if not desc:IsA("GuiButton") then return end -- EARLY RETURN
			self:_bindButton(desc)
		end)
	)
end

function UISoundHelper:destroy(): ()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}

	-- The store is not walkable; every button this helper bound was found in PlayerGui, so the tree
	-- is walked instead. A bound button that is detached but alive keeps its connections until it is
	-- destroyed, which its own Destroying listener (above) handles.
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		for _, desc in ipairs(playerGui:GetDescendants()) do
			if desc:IsA("GuiButton") then
				self:_disconnectButton(desc)
			end
		end
	end

	if self._hoverTemplate then
		self._hoverTemplate:Destroy()
	end
	if self._clickTemplate then
		self._clickTemplate:Destroy()
	end
end

return UISoundHelper
