--!strict
-- Resolves aura (per-player) and world (global VFX) donation tiers from Config.Donation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local DonationProviderDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.DonationProviderDomain)

export type AuraTier = {
	level: number,
	min: number,
	idrMin: number,
	idrMax: number,
	effect: string,
	sound: string?,
	duration: number?,
	cameraDuration: number?,
}

local DonationEffectTierResolver = {}

local function getDonationConfig(): { [string]: any }
	return Config.Donation :: any
end

local function getAuraTiers(): { any }
	local donationCfg = getDonationConfig()
	local tiers = donationCfg.AURA_TIERS
	if type(tiers) ~= "table" or #tiers == 0 then
		tiers = donationCfg.ROBUX_EFFECT_TIERS
	end
	return if type(tiers) == "table" then tiers else {}
end

local function getWorldTiers(): { any }
	local donationCfg = getDonationConfig()
	local tiers = donationCfg.WORLD_EFFECT_TIERS
	if type(tiers) ~= "table" or #tiers == 0 then
		tiers = donationCfg.SAWERIA_NUKE_TIERS
	end
	return if type(tiers) == "table" then tiers else {}
end

local function buildAuraTier(rawTier: any): AuraTier?
	if type(rawTier) ~= "table" then
		return nil
	end
	local effectName = rawTier.effect
	local minAmount = tonumber(rawTier.min)
	if not minAmount or type(effectName) ~= "string" or effectName == "" then
		return nil
	end
	return {
		level = tonumber(rawTier.level) or 0,
		min = minAmount,
		idrMin = tonumber(rawTier.idrMin) or 0,
		idrMax = tonumber(rawTier.idrMax) or math.huge,
		effect = effectName,
		sound = if type(rawTier.sound) == "string" then rawTier.sound else nil,
		duration = if type(rawTier.duration) == "number" then rawTier.duration else nil,
		cameraDuration = if type(rawTier.cameraDuration) == "number" then rawTier.cameraDuration else nil,
	}
end

function DonationEffectTierResolver.resolveAuraByRobux(amount: number): AuraTier?
	local selected: AuraTier? = nil
	for _, rawTier in ipairs(getAuraTiers()) do
		local tier = buildAuraTier(rawTier)
		if tier and amount >= tier.min and (not selected or tier.min >= selected.min) then
			selected = tier
		end
	end
	return selected
end

function DonationEffectTierResolver.resolveAuraByIdr(amount: number): AuraTier?
	for _, rawTier in ipairs(getAuraTiers()) do
		local tier = buildAuraTier(rawTier)
		if tier and amount >= tier.idrMin and amount <= tier.idrMax then
			return tier
		end
	end
	return nil
end

function DonationEffectTierResolver.resolveWorldByIdr(amount: number): string?
	local selected: string? = nil
	local selectedMin = -math.huge
	for _, entry in ipairs(getWorldTiers()) do
		local min = tonumber(entry.min)
		local effect = entry.effect
		if type(min) == "number" and type(effect) == "string" and effect ~= "" and amount >= min and min > selectedMin then
			selected = effect
			selectedMin = min
		end
	end
	return selected
end

function DonationEffectTierResolver.resolveNotifDuration(source: string, amount: number): number
	local fallback = tonumber(getDonationConfig().NOTIF_SHOW_DURATION) or 20
	local normalizedSource = if source == "" then DonationProviderDomain.getKey() else source

	if normalizedSource == "robux" then
		local tier = DonationEffectTierResolver.resolveAuraByRobux(amount)
		return if tier and tier.duration then tier.duration else fallback
	end

	local tier = DonationEffectTierResolver.resolveAuraByIdr(amount)
	return if tier and tier.duration then tier.duration else fallback
end

return DonationEffectTierResolver
