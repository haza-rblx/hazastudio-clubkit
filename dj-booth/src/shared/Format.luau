--!strict
-- Text formatting shared by the UI and the server (announcements). Matches the prototype exactly.
local Format = {}

function Format.mmss(s: number?): string
	if not s then
		return "—"
	end
	local n = math.floor(s + 0.5)
	return string.format("%d:%02d", n // 60, n % 60)
end

-- "01:13.2" as on the jog's inner display
function Format.clock(s: number): string
	s = math.max(0, s)
	local m = math.floor(s / 60)
	return string.format("%02d:%04.1f", m, s - m * 60)
end

function Format.initials(s: string): string
	local a, b = string.match(s, "^(%w)%w*%s+(%w)")
	return string.upper(if a and b then a .. b else string.sub(s, 1, 2))
end

-- a stable grey per name (avatars without a user id): 0x3a .. 0x9a
function Format.shade(s: string): Color3
	local h = 0
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 97
	end
	local v = (58 + h) / 255
	return Color3.new(v, v, v)
end

function Format.speed(v: number): string
	return string.format("%.2fx", v)
end

function Format.effectiveBpm(bpm: number?, speed: number?): number?
	return if bpm then math.floor(bpm * (speed or 1) + 0.5) else nil
end

function Format.pct(v: number): string
	return v .. "%"
end

function Format.plural(n: number): string
	return n .. (if n == 1 then " Track" else " Tracks")
end

function Format.seconds(v: number): string
	return v .. " s"
end

function Format.offSeconds(v: number): string
	return if v == 0 then "Off" else v .. " s"
end

-- "Today", "2 days ago", "Last week", "Never" for a unix time
function Format.ago(t: number?, now: number): string
	if not t then
		return "Never"
	end
	local d = math.floor((now - t) / 86400)
	if d <= 0 then
		return "Today"
	elseif d == 1 then
		return "Yesterday"
	elseif d < 7 then
		return d .. " days ago"
	elseif d < 14 then
		return "Last week"
	elseif d < 31 then
		return math.floor(d / 7) .. " weeks ago"
	end
	return math.floor(d / 30) .. " months ago"
end

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
function Format.dayMonth(t: number): string
	local d = os.date("!*t", t) :: any
	return d.day .. " " .. MONTHS[d.month]
end

return Format
