--!strict
-- Pure helpers for `roleColor.stops` — the optional multi-color gradient a buyer can put on a
-- role (`roleColor = { stops = { "daad18", "ffed2a", ... } }`). No Roblox globals: the client
-- turns `toKeypoints` output into a ColorSequence; RolesDomain uses `normalizeStops` at boot.

local RoleColorDomain = {}

RoleColorDomain.MAX_STOPS = 5

export type Keypoint = { time: number, r: number, g: number, b: number }

-- "#RRGGBB" / "RRGGBB" / "#RGB" / "RGB" (any case) → "#RRGGBB" uppercase, or nil when malformed.
function RoleColorDomain.normalizeHex(raw: any): string?
	if type(raw) ~= "string" then
		return nil
	end
	local hex = string.gsub(string.gsub(raw, "^%s+", ""), "%s+$", "")
	hex = string.gsub(hex, "^#", "")
	if string.match(hex, "^%x%x%x$") then
		local r, g, b = string.sub(hex, 1, 1), string.sub(hex, 2, 2), string.sub(hex, 3, 3)
		hex = r .. r .. g .. g .. b .. b
	elseif not string.match(hex, "^%x%x%x%x%x%x$") then
		return nil
	end
	return "#" .. string.upper(hex)
end

-- Drops malformed entries, caps at MAX_STOPS. Returns nil unless at least two valid stops
-- remain — a one-color "gradient" is just a solid, and the caller falls back to primary/secondary.
function RoleColorDomain.normalizeStops(raw: any, maxStops: number?): { string }?
	if type(raw) ~= "table" then
		return nil
	end
	local cap = maxStops or RoleColorDomain.MAX_STOPS
	local out: { string } = {}
	for _, entry in ipairs(raw) do
		local hex = RoleColorDomain.normalizeHex(entry)
		if hex then
			table.insert(out, hex)
			if #out >= cap then
				break
			end
		end
	end
	if #out < 2 then
		return nil
	end
	return out
end

-- Evenly spaced keypoints with decoded 0..255 rgb. Assumes normalized stops (>= 2 entries).
function RoleColorDomain.toKeypoints(stops: { string }): { Keypoint }
	local count = #stops
	local out: { Keypoint } = {}
	for index, hex in ipairs(stops) do
		local r = tonumber(string.sub(hex, 2, 3), 16) or 255
		local g = tonumber(string.sub(hex, 4, 5), 16) or 255
		local b = tonumber(string.sub(hex, 6, 7), 16) or 255
		local time = if count <= 1 then 0 else (index - 1) / (count - 1)
		table.insert(out, { time = time, r = r, g = g, b = b })
	end
	return out
end

-- Chat / tag colors only take a pair: first stop as primary, last stop as secondary.
function RoleColorDomain.deriveChatPair(stops: { string }): (string, string)
	return stops[1], stops[#stops]
end

return RoleColorDomain
