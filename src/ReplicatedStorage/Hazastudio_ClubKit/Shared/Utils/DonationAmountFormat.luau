--!strict
-- Compact donation totals (e.g. 12.5K, 1.2M) + cash currency formatting for UI panels.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DonationAmountFormat = {}

local function getCashCurrencyDomain()
	-- Lazy require mirrors DonationProviderDomain's Config-cycle guard; cheap to call
	-- since ModuleScript requires are cached after first load.
	return require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.CashCurrencyDomain)
end

function DonationAmountFormat.formatCompact(value: number): string
	local amount = math.max(0, math.floor(tonumber(value) or 0))
	if amount >= 1_000_000 then
		local millions = amount / 1_000_000
		if math.abs(millions - math.floor(millions + 0.0001)) < 0.05 then
			return string.format("%dM", math.floor(millions + 0.5))
		end
		local rounded = math.floor(millions * 10 + 0.5) / 10
		if rounded == math.floor(rounded) then
			return string.format("%dM", rounded)
		end
		return string.format("%.1fM", rounded)
	end
	if amount >= 1_000 then
		local thousands = amount / 1_000
		if math.abs(thousands - math.floor(thousands + 0.0001)) < 0.05 then
			return string.format("%dK", math.floor(thousands + 0.5))
		end
		local rounded = math.floor(thousands * 10 + 0.5) / 10
		if rounded == math.floor(rounded) then
			return string.format("%dK", rounded)
		end
		return string.format("%.1fK", rounded)
	end
	return tostring(amount)
end

function DonationAmountFormat.formatRank(rank: number?): string
	if type(rank) ~= "number" or rank < 1 then
		return "#-"
	end
	return "#" .. tostring(math.floor(rank))
end

--- Grouped integer string (e.g. "10.000" / "10,000") using the given separator.
--- Defaults to "." (IDR-style) when groupSep is omitted, matching prior callers.
function DonationAmountFormat.formatGrouped(value: number, groupSep: string?): string
	local sep = if type(groupSep) == "string" and groupSep ~= "" then groupSep else "."
	local raw = tostring(math.floor(math.max(tonumber(value) or 0, 0)))
	local result = ""
	local len = #raw
	for index = 1, len do
		if index > 1 and (len - index + 1) % 3 == 0 then
			result ..= sep
		end
		result ..= raw:sub(index, index)
	end
	return result
end

--- Notification-style cash text, e.g. "Rp 10.000" / "₱10,000" (active Donation.Currency).
function DonationAmountFormat.formatCash(amount: number): string
	local preset = getCashCurrencyDomain().getActive()
	return preset.symbol .. DonationAmountFormat.formatGrouped(amount, preset.groupSep)
end

--- Board/leaderboard-style cash text, e.g. "RP 10.000" / "₱10,000".
function DonationAmountFormat.formatCashBoard(amount: number): string
	local preset = getCashCurrencyDomain().getActive()
	return preset.boardPrefix .. DonationAmountFormat.formatGrouped(amount, preset.groupSep)
end

--- Compact cash text, e.g. "Rp 12.5K" / "₱12.5K".
function DonationAmountFormat.formatCashCompact(amount: number): string
	local preset = getCashCurrencyDomain().getActive()
	return preset.symbol .. DonationAmountFormat.formatCompact(amount)
end

return DonationAmountFormat
