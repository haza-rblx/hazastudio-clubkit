--!strict
-- CoverTextPick: the two lines a kit-drawn cover prints (ADR 0014). brm-api resolves them per
-- track (library/cover-text.ts + cover-style.ts) and ships them in the pull as track.cover; this
-- applies only the rules that need the game (the experience's name in the corner, per-layout
-- limits), and falls back to the track's name/creator when the web sent nothing. Pure.

local CoverTextPick = {}

export type Lines = { headline: string, subline: string?, kicker: string? }

-- The ticket's stub fits ten characters a line (the owner's rule, 2026-09-22).
CoverTextPick.TICKET_MAX = 10
CoverTextPick.HEADLINE_MAX = 26
CoverTextPick.SUBLINE_MAX = 30

local function trim(text: string): string
	return (string.gsub(text, "^%s+", ""):gsub("%s+$", ""))
end

local function same(a: string?, b: string?): boolean
	return a ~= nil and b ~= nil and a ~= "" and b ~= "" and string.lower(trim(a)) == string.lower(trim(b))
end

-- Length and slicing in characters, not bytes; invalid UTF-8 falls back to bytes.
local function charLen(text: string): number
	return utf8.len(text) or #text
end

local function charSlice(text: string, count: number): string
	if utf8.len(text) == nil then
		return string.sub(text, 1, count)
	end
	local stop = utf8.offset(text, count + 1)
	return if stop then string.sub(text, 1, stop - 1) else text
end

local DANGLING = { feat = true, ["feat."] = true, ft = true, ["ft."] = true, ["&"] = true, x = true, ["and"] = true, dan = true, ["-"] = true, ["–"] = true, ["—"] = true, ["·"] = true }
local TRAILING = { " ", "\t", ",", ";", ":", "-", "–", "—" }

-- Cut on a word boundary, never mid-word, never leaving a dangling "feat." / "&" / "x".
-- Same rule as brm-api's clip().
function CoverTextPick.clip(text: string, max: number): string
	if text == "" or charLen(text) <= max then
		return text
	end
	local cut = charSlice(text, max + 1)
	local at: number? = nil
	for i = #cut, 1, -1 do
		if string.sub(cut, i, i) == " " then
			at = i
			break
		end
	end
	-- Short limits take any word boundary; long ones only a late one.
	local minAt = if max <= 12 then 1 else max * 0.55
	if at and charLen(string.sub(cut, 1, at - 1)) >= minAt then
		cut = string.sub(cut, 1, at - 1)
	else
		cut = charSlice(text, max)
	end
	local lastSpace = string.match(cut, "^.*()%s")
	if lastSpace then
		local word = string.sub(cut, lastSpace + 1)
		if DANGLING[string.lower(word)] then
			cut = string.gsub(string.sub(cut, 1, lastSpace), "%s+$", "")
		end
	end
	local trimmed = true
	while trimmed and cut ~= "" do
		trimmed = false
		for _, tail in ipairs(TRAILING) do
			if #cut >= #tail and string.sub(cut, -#tail) == tail then
				cut = string.sub(cut, 1, #cut - #tail)
				trimmed = true
			end
		end
	end
	return cut .. "…"
end

type CoverLike = { headline: string, subline: string?, venueAlt: { string }, kicker: string?, mark: string }
type TrackLike = { name: string, creator: string?, cover: CoverLike? }

-- The name printed in the tile's corner. The web sets it per venue: "" = the experience's name
-- (known only in game, passed in as experienceName), "-" = none, anything else as written.
function CoverTextPick.markText(cover: CoverLike?, experienceName: string?): string?
	local mark = if cover then cover.mark else ""
	if mark == "-" then
		return nil
	end
	if mark ~= "" then
		return mark
	end
	return if experienceName and experienceName ~= "" then experienceName else nil
end

-- venue: the name printed in the corner (markText), or nil. limit: a layout's own cap (the
-- ticket's 10). Everything else was decided on the web.
function CoverTextPick.pick(track: TrackLike, venue: string?, limit: number?): Lines
	local lines: Lines
	local cover = track.cover
	if cover then
		local subline = cover.subline
		-- The venue's name already sits in the corner: say something else, or nothing.
		if subline and venue and same(subline, venue) then
			subline = nil
			for _, alt in ipairs(cover.venueAlt) do
				if not same(alt, venue) then
					subline = alt
					break
				end
			end
		end
		lines = { headline = cover.headline, subline = subline, kicker = cover.kicker }
	else
		-- An older pull, or a track the web has not described yet.
		local creator = track.creator and trim(track.creator) or ""
		local subline: string? = if creator ~= "" and not same(creator, track.name) and not same(creator, venue)
			then CoverTextPick.clip(creator, CoverTextPick.SUBLINE_MAX)
			else nil
		lines = { headline = CoverTextPick.clip(trim(track.name), CoverTextPick.HEADLINE_MAX), subline = subline, kicker = nil }
	end
	if limit then
		lines.headline = CoverTextPick.clip(lines.headline, limit)
		if lines.subline then
			lines.subline = CoverTextPick.clip(lines.subline, limit)
		end
	end
	return lines
end

return CoverTextPick
