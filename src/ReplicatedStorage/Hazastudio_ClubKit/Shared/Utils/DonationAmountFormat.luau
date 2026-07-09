--!strict
-- Compact donation totals (e.g. 12.5K, 1.2M) for UI panels.

local DonationAmountFormat = {}

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

return DonationAmountFormat
