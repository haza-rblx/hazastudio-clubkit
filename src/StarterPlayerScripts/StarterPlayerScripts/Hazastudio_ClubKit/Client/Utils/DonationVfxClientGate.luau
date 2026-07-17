--!strict
-- Client gate for donation world VFX (EffectDonate, nuke). Honors Settings graphics attrs.

local Players = game:GetService("Players")

local DonationVfxClientGate = {}

local function localPlayer(): Player?
	return Players.LocalPlayer
end

function DonationVfxClientGate.shouldPlayWorldEffect(): boolean
	local player = localPlayer()
	if not player then
		return false
	end
	-- World FX has its own SettingsHideDonationWorldEffect (DonationExperiencePrefs).
	-- Do not gate on Graphics Low / HideAllParticles — those mute ambient particles;
	-- signature donation world VFX (Nuke/Smite/BlackHole) should still play unless
	-- the player explicitly hides them or donation VFX scale is effectively off.
	local vfxScale = tonumber(player:GetAttribute("SettingsDonationVfxScale")) or 1
	if vfxScale <= 0.05 then
		return false
	end
	return true
end

function DonationVfxClientGate.getVfxScale(): number
	local player = localPlayer()
	if not player then
		return 1
	end
	return math.clamp(tonumber(player:GetAttribute("SettingsDonationVfxScale")) or 1, 0, 1)
end

function DonationVfxClientGate.getGraphicsTier(): number
	local player = localPlayer()
	if not player then
		return 1
	end
	return math.max(0, tonumber(player:GetAttribute("SettingsGraphicsTier")) or 1)
end

return DonationVfxClientGate
