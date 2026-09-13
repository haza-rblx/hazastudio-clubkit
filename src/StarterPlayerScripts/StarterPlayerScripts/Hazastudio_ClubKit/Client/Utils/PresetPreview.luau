--!strict
-- Client/Utils/PresetPreview.luau
-- Paints a TextLabel with an overhead title colour preset, the way the admin
-- panel's preset cards do it. Shared by the player's custom-title panel and the
-- admin panel so a preset never reads differently between the two.
--
-- Every effect owns a RenderStepped loop, so the caller keeps the returned handle
-- and Destroys it when the label is rebuilt or the panel closes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local TitleColorPreset = require(ReplicatedStorage.Hazastudio_ClubKit.OverheadEffects.TitleColorPreset)

local PresetPreview = {}

local CARD_SPEED = Config.Admin.TITLE_PRESET_CARD_SPEED or 0.55
local CARD_SIZE = Config.Admin.TITLE_PRESET_SIZE or 1.5

-- The GUI templates ship a placeholder white gradient on the label; it has to go
-- first or it fights the effect's own gradient.
function PresetPreview.paint(label: TextLabel, presetMode: string): any?
	for _, child in ipairs(label:GetChildren()) do
		if child:IsA("UIGradient") then
			child:Destroy()
		end
	end
	local ok, effect = pcall(function()
		return TitleColorPreset.new(label, presetMode, CARD_SPEED, CARD_SIZE, true)
	end)
	return if ok then effect else nil
end

-- Destroy a list of handles in place. Safe on already-destroyed effects.
function PresetPreview.destroyAll(effects: { any })
	for _, effect in ipairs(effects) do
		pcall(function()
			effect:Destroy()
		end)
	end
	table.clear(effects)
end

return PresetPreview
