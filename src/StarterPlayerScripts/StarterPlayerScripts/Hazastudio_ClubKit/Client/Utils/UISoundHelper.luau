--!strict

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local AssetHealthReporter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.AssetHealthReporter)

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
	_attachedButtons: { [GuiButton]: boolean },
	_buttonConnections: { [GuiButton]: { RBXScriptConnection } },
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
	self._attachedButtons = (
		setmetatable({} :: { [GuiButton]: boolean }, { __mode = "k" }) :: any
	) :: { [GuiButton]: boolean }
	self._buttonConnections = (
		setmetatable({} :: { [GuiButton]: { RBXScriptConnection } }, { __mode = "k" }) :: any
	) :: { [GuiButton]: { RBXScriptConnection } }
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
	local connections = self._buttonConnections[button]
	if not connections then
		self._attachedButtons[button] = nil
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	self._buttonConnections[button] = nil
	self._attachedButtons[button] = nil
end

function UISoundHelper:_bindButton(button: GuiButton): ()
	if button:GetAttribute(DISABLE_ATTRIBUTE) == true then
		return
	end
	if self._attachedButtons[button] then
		return
	end

	self._attachedButtons[button] = true
	local buttonConnections = {} :: { RBXScriptConnection }
	self._buttonConnections[button] = buttonConnections

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

	for button in pairs(self._buttonConnections) do
		self:_disconnectButton(button)
	end

	if self._hoverTemplate then
		self._hoverTemplate:Destroy()
	end
	if self._clickTemplate then
		self._clickTemplate:Destroy()
	end
end

return UISoundHelper
