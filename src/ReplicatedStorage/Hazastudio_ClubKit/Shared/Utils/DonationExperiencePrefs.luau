--!strict
-- Client runtime attributes for per-player donation experience toggles.

local Players = game:GetService("Players")

local ATTR_HIDE_WORLD_EFFECT = "SettingsHideDonationWorldEffect"
local ATTR_HIDE_AURA = "SettingsHideDonationAura"
local ATTR_HIDE_ANNOUNCE = "SettingsHideDonationAnnounce"
local ATTR_HIDE_DONATOR_HIGHLIGHT = "SettingsHideDonatorHighlight"

local DonationExperiencePrefs = {}

local function isHidden(attrName: string): boolean
	local player = Players.LocalPlayer
	if not player then
		return false
	end
	return player:GetAttribute(attrName) == true
end

function DonationExperiencePrefs.shouldShowWorldEffect(): boolean
	return not isHidden(ATTR_HIDE_WORLD_EFFECT)
end

function DonationExperiencePrefs.shouldShowAura(): boolean
	return not isHidden(ATTR_HIDE_AURA)
end

function DonationExperiencePrefs.shouldShowAnnounce(): boolean
	return not isHidden(ATTR_HIDE_ANNOUNCE)
end

function DonationExperiencePrefs.shouldShowDonatorHighlight(): boolean
	return not isHidden(ATTR_HIDE_DONATOR_HIGHLIGHT)
end

return DonationExperiencePrefs
