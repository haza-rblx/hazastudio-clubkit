--!strict
-- Display names + legacy GUI label replacement for external IDR donations (Bagibagi / Saweria).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type ProviderPreset = {
	key: string,
	name: string,
	donorLabel: string,
	illustrationImage: string,
	illustrationHeight: number,
	illustrationGradientEnabled: boolean,
}

local DonationProviderDomain = {}

local function getDonationConfig(): { [string]: any }
	-- Lazy require avoids Config -> ConfigBootstrap -> DonationProviderDomain cycle at load time.
	local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
	return Config.Donation
end

-- Illustration defaults for 3-SaweriaTab HeaderStatic (clubkit ScreenGui).
DonationProviderDomain.PRESETS = {
	bagibagi = {
		key = "bagibagi",
		name = "Bagibagi",
		donorLabel = "nama Bagibagi",
		illustrationImage = "rbxassetid://71634976881165",
		illustrationHeight = 120,
		illustrationGradientEnabled = true,
	},
	saweria = {
		key = "saweria",
		name = "Saweria",
		donorLabel = "nama Saweria",
		illustrationImage = "rbxassetid://113174257336117",
		illustrationHeight = 200,
		illustrationGradientEnabled = false,
	},
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

-- Longer / typo variants first so "BagiBagi" / "Bagi-Bagi" don't leave fragments.
local LEGACY_TEXT_REPLACEMENTS = {
	{ "Bagi-Bagi", false },
	{ "Bagi Bagi", false },
	{ "BagiBagi", false },
	{ "Bagibagi", false },
	{ "bagibagi", true },
	{ "Saweria", false },
	{ "saweria", true },
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

local function findFirstNamed(root: Instance, name: string): Instance?
	if root.Name == name then
		return root
	end
	return root:FindFirstChild(name, true)
end

--- Brand illustration + title on cash tab (`3-SaweriaTab`) from ClubKitConfig.Provider.
function DonationProviderDomain.applyCashTabBrand(saweriaTab: Instance?)
	if not saweriaTab then
		return
	end
	local preset = DonationProviderDomain.resolvePreset(DonationProviderDomain.getKey())

	local headerStatic = findFirstNamed(saweriaTab, "HeaderStatic")
	local titleParent = if headerStatic then findFirstNamed(headerStatic, "Frame") else nil
	local titleLabel = if titleParent
		then (titleParent:FindFirstChild("1-Title") or titleParent:FindFirstChild("Title"))
		else findFirstNamed(saweriaTab, "1-Title")
	if titleLabel and (titleLabel:IsA("TextLabel") or titleLabel:IsA("TextButton")) then
		-- Keep marketing sentence; fix provider name (BagiBagi typo → Bagibagi / Saweria).
		local title = titleLabel :: TextLabel | TextButton
		local current = title.Text
		if string.find(string.lower(current), "support", 1, true) then
			title.Text = ("Support us on %s!"):format(preset.name)
		else
			title.Text = preset.name
		end
	end

	local illustrationSection = if headerStatic
		then findFirstNamed(headerStatic, "IllustrationSection")
		else findFirstNamed(saweriaTab, "IllustrationSection")
	local illustration = if illustrationSection
		then illustrationSection:FindFirstChild("Illustration")
		else findFirstNamed(saweriaTab, "Illustration")
	if illustration and illustration:IsA("ImageLabel") then
		local image = illustration :: ImageLabel
		image.Image = preset.illustrationImage
		local size = image.Size
		image.Size = UDim2.new(size.X.Scale, size.X.Offset, size.Y.Scale, preset.illustrationHeight)
		local gradient = image:FindFirstChild("UIGradient-Gold")
		if gradient and gradient:IsA("UIGradient") then
			gradient.Enabled = preset.illustrationGradientEnabled
		end
	end
end

return DonationProviderDomain
