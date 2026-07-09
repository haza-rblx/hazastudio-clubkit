--!strict
-- Display names + legacy GUI label replacement for external IDR donations (Bagibagi).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type ProviderPreset = {
	key: string,
	name: string,
	donorLabel: string,
}

local DonationProviderDomain = {}

local function getDonationConfig(): { [string]: any }
	-- Lazy require avoids Config -> ConfigBootstrap -> DonationProviderDomain cycle at load time.
	local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
	return Config.Donation
end

DonationProviderDomain.PRESETS = {
	bagibagi = { key = "bagibagi", name = "Bagi-Bagi", donorLabel = "nama Bagi-Bagi" },
	saweria = { key = "saweria", name = "Saweria", donorLabel = "nama Saweria" },
} :: { [string]: ProviderPreset }

local function normalizeProviderKey(providerKey: string?): string
	local key = string.lower(tostring(providerKey or ""))
	if DonationProviderDomain.PRESETS[key] then
		return key
	end
	return "bagibagi"
end

function DonationProviderDomain.resolvePreset(providerKey: string?): ProviderPreset
	return DonationProviderDomain.PRESETS[normalizeProviderKey(providerKey)]
end

function DonationProviderDomain.inferProviderKey(donation: { Provider: string?, ProviderName: string? }?): string
	if type(donation) ~= "table" then
		return "bagibagi"
	end
	if type(donation.Provider) == "string" and donation.Provider ~= "" then
		return normalizeProviderKey(donation.Provider)
	end
	if type(donation.ProviderName) == "string" and donation.ProviderName ~= "" then
		local lower = string.lower(donation.ProviderName)
		if string.find(lower, "saweria", 1, true) then
			return "saweria"
		end
	end
	return "bagibagi"
end

function DonationProviderDomain.applyToConfig(configDonation: { [string]: any }, providerKey: string)
	local preset = DonationProviderDomain.resolvePreset(providerKey)
	configDonation.PROVIDER_KEY = preset.key
	configDonation.PROVIDER_NAME = preset.name
	configDonation.PROVIDER_DONOR_LABEL = preset.donorLabel
end

local LEGACY_TEXT_REPLACEMENTS = {
	{ "Saweria", false },
	{ "saweria", true },
	{ "Bagibagi", false },
	{ "bagibagi", true },
	{ "Bagi Bagi", false },
	{ "Bagi-Bagi", false },
}

function DonationProviderDomain.getName(): string
	local donation = getDonationConfig()
	return tostring(donation.PROVIDER_NAME or "Bagibagi")
end

function DonationProviderDomain.getKey(): string
	local donation = getDonationConfig()
	return tostring(donation.PROVIDER_KEY or "bagibagi")
end

function DonationProviderDomain.getDonorLabel(): string
	local donation = getDonationConfig()
	return tostring(donation.PROVIDER_DONOR_LABEL or "nama Bagibagi")
end

function DonationProviderDomain.replaceLegacyText(text: string): string
	local providerName = DonationProviderDomain.getName()
	local providerLower = string.lower(providerName)
	local out = text
	for _, entry in ipairs(LEGACY_TEXT_REPLACEMENTS) do
		local from = entry[1]
		local useLower = entry[2] == true
		if string.find(out, from, 1, true) then
			out = string.gsub(out, from, if useLower then providerLower else providerName)
		end
	end
	return out
end

function DonationProviderDomain.applyDisplayText(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			local textObject = descendant :: TextLabel | TextButton | TextBox
			textObject.Text = DonationProviderDomain.replaceLegacyText(textObject.Text)
			if descendant:IsA("TextBox") then
				local textBox = descendant :: TextBox
				textBox.PlaceholderText = DonationProviderDomain.replaceLegacyText(textBox.PlaceholderText)
			end
		end
	end
end

return DonationProviderDomain
