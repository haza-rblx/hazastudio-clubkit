--!strict
-- Cash display presets (symbol/prefix/grouping/labels) for venue-level Donation.Currency.
-- Currency is a per-venue display setting (ClubKitConfig.Donation.Currency), not a
-- per-donation field — amounts stay untagged integers; this only controls formatting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type CashCurrencyPreset = {
	code: string,
	symbol: string,
	boardPrefix: string,
	chipSuffix: string,
	roleLabel: string,
	shortRoleLabel: string,
	groupSep: string,
	adminHint: string,
}

local CashCurrencyDomain = {}

local function getDonationConfig(): { [string]: any }
	-- Lazy require avoids Config -> ConfigBootstrap -> CashCurrencyDomain cycle at load time.
	local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
	return Config.Donation
end

CashCurrencyDomain.PRESETS = {
	IDR = {
		code = "IDR",
		symbol = "Rp ",
		boardPrefix = "RP ",
		chipSuffix = "RUPIAH",
		roleLabel = "Top Rupiah Spender",
		shortRoleLabel = "Top Rupiah",
		groupSep = ".",
		adminHint = "IDR",
	},
	PHP = {
		code = "PHP",
		symbol = "₱",
		boardPrefix = "₱",
		chipSuffix = "PESO",
		roleLabel = "Top Peso Spender",
		shortRoleLabel = "Top Peso",
		groupSep = ",",
		adminHint = "PHP",
	},
} :: { [string]: CashCurrencyPreset }

--- Normalizes a buyer-provided currency code to a known preset key ("IDR" | "PHP").
--- Unknown / missing codes fall back to "IDR" (existing behavior for buyers who
--- have not set Donation.Currency yet).
function CashCurrencyDomain.normalize(code: string?): string
	local key = string.upper(tostring(code or ""))
	if CashCurrencyDomain.PRESETS[key] then
		return key
	end
	return "IDR"
end

function CashCurrencyDomain.getPreset(code: string?): CashCurrencyPreset
	return CashCurrencyDomain.PRESETS[CashCurrencyDomain.normalize(code)]
end

--- Active preset for this venue, read from Config.Donation.CASH_CURRENCY.
function CashCurrencyDomain.getActive(): CashCurrencyPreset
	local donation = getDonationConfig()
	return CashCurrencyDomain.getPreset(donation and donation.CASH_CURRENCY)
end

return CashCurrencyDomain
