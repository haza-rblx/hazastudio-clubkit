--!strict
-- Accent theme (CONTEXT.md "Accent theme"): the one colour a player picks in Settings → Appearance.
-- Multicolor (default) keeps every GUI's own colours; Graphite turns them grey; any other accent
-- paints state (on / selected / active) and recolours the kit's GUIs (`recolor`). Pure: hex strings
-- and 0..255 channels, no Roblox types, so the client builds Color3 and lune can spec this file.

local AccentDomain = {}

export type AccentId = "multicolor" | "graphite" | "blue" | "purple" | "pink" | "red" | "orange" | "yellow" | "green"

export type Swatch = {
	-- What the state is painted with (toggle track, selected pill, played row).
	fill: string,
	-- What is drawn on top of `fill` (text, icon, toggle knob).
	onFill: string,
}

-- Picker order, left to right. Multicolor first: it is the default and today's look.
AccentDomain.ORDER = { "multicolor", "graphite", "blue", "purple", "pink", "red", "orange", "yellow", "green" }

AccentDomain.DEFAULT = "multicolor"
local GRAPHITE = "graphite"

-- Apple dark-mode system colours. Graphite keeps the kit's monochrome (white fill, black on it);
-- yellow is the one colour light enough to need black on top as well.
local SWATCHES: { [string]: Swatch } = {
	multicolor = { fill = "FFFFFF", onFill = "000000" },
	graphite = { fill = "FFFFFF", onFill = "000000" },
	blue = { fill = "0A84FF", onFill = "FFFFFF" },
	purple = { fill = "BF5AF2", onFill = "FFFFFF" },
	pink = { fill = "FF375F", onFill = "FFFFFF" },
	red = { fill = "FF453A", onFill = "FFFFFF" },
	orange = { fill = "FF9F0A", onFill = "FFFFFF" },
	yellow = { fill = "FFD60A", onFill = "000000" },
	green = { fill = "30D158", onFill = "FFFFFF" },
}

-- A known accent id (case and spaces forgiven), else nil. "" is how Settings stores "not picked".
function AccentDomain.normalize(raw: any): string?
	if type(raw) ~= "string" then
		return nil
	end
	local id = string.lower((string.gsub(raw, "^%s*(.-)%s*$", "%1")))
	if SWATCHES[id] then
		return id
	end
	return nil
end

-- The accent a player sees: their own pick, else the venue default (ClubKitConfig), else Multicolor.
function AccentDomain.resolve(playerChoice: any, venueDefault: any): string
	return AccentDomain.normalize(playerChoice) or AccentDomain.normalize(venueDefault) or AccentDomain.DEFAULT
end

-- Multicolor and Graphite paint state with the design's own colours (white toggle, white pill).
function AccentDomain.keepsDesign(id: any): boolean
	local key = AccentDomain.normalize(id) or AccentDomain.DEFAULT
	return key == AccentDomain.DEFAULT or key == GRAPHITE
end

function AccentDomain.swatch(id: any): Swatch
	return SWATCHES[AccentDomain.normalize(id) or AccentDomain.DEFAULT]
end

-- Surface tint: the kit's neutral grey surfaces (cards, rows, off tracks, strokes) pick up a hint
-- of the accent, macOS-style. Owner rule: near-black (brightest channel below 10) stays neutral;
-- light greys and whites (above 200) stay too, so knobs and selected fills keep their colour.
AccentDomain.SURFACE_MIX = 0.08
local GREY_SPREAD = 3
local SURFACE_MIN = 10
local SURFACE_MAX = 200

local function hexChannels(hex: string): (number, number, number)
	return tonumber(string.sub(hex, 1, 2), 16) :: number,
		tonumber(string.sub(hex, 3, 4), 16) :: number,
		tonumber(string.sub(hex, 5, 6), 16) :: number
end

-- Channels 0..255. Returns the tinted channels, or nil when the colour should be left alone
-- (Graphite / unknown accent, not a neutral grey, or outside the 10..200 band).
function AccentDomain.tintSurface(r: number, g: number, b: number, id: any): (number?, number?, number?)
	local key = AccentDomain.normalize(id)
	if key == nil or AccentDomain.keepsDesign(key) then
		return nil, nil, nil
	end
	local high, low = math.max(r, g, b), math.min(r, g, b)
	if high - low > GREY_SPREAD or high < SURFACE_MIN or high > SURFACE_MAX then
		return nil, nil, nil
	end
	local ar, ag, ab = hexChannels(SWATCHES[key].fill)
	local mix = AccentDomain.SURFACE_MIX
	return r + (ar - r) * mix, g + (ag - g) * mix, b + (ab - b) * mix
end

-- Whole-GUI recolour: colours with at least this saturation and brightness count as "colour".
local COLOR_MIN_SATURATION = 0.25
local COLOR_MIN_VALUE = 0.12
-- Channel spread (0..255) a colour needs too: a surface-tinted dark grey reads "saturated" in HSV
-- (41,25,28 is s = .39) but is a tint, not a design colour, and must never be recorded as one.
local COLOR_MIN_CHROMA = 40

local function toHsv(r: number, g: number, b: number): (number, number, number)
	local high, low = math.max(r, g, b), math.min(r, g, b)
	local delta = high - low
	local hue = 0
	if delta > 0 then
		if high == r then
			hue = ((g - b) / delta) % 6
		elseif high == g then
			hue = (b - r) / delta + 2
		else
			hue = (r - g) / delta + 4
		end
		hue /= 6
	end
	return hue, if high > 0 then delta / high else 0, high / 255
end

local function fromHsv(hue: number, saturation: number, value: number): (number, number, number)
	local sector = math.floor(hue * 6) % 6
	local f = hue * 6 - math.floor(hue * 6)
	local v = value * 255
	local p = v * (1 - saturation)
	local q = v * (1 - saturation * f)
	local t = v * (1 - saturation * (1 - f))
	if sector == 0 then
		return v, t, p
	elseif sector == 1 then
		return q, v, p
	elseif sector == 2 then
		return p, v, t
	elseif sector == 3 then
		return p, q, v
	elseif sector == 4 then
		return t, p, v
	end
	return v, p, q
end

-- Channels 0..255. The colour a GUI element shows under accent `id`, or nil to leave it as designed:
-- * Multicolor: nil (every GUI's own colours).
-- * Saturated colours take the accent's hue with their own saturation and brightness, so a design's
--   light/dark structure (gradients, pressed shades) survives; Graphite turns them into their
--   luminance grey.
-- * Neutral greys get the surface tint (`tintSurface`) only when `surface` is set — backgrounds,
--   never strokes, text or icon colours.
-- * `muted` (strokes): thin lines in full accent glare, so they keep 45% of the colour's saturation
--   and 70% of its brightness.
local MUTED_SATURATION = 0.45
local MUTED_VALUE = 0.7
function AccentDomain.recolor(
	r: number,
	g: number,
	b: number,
	id: any,
	surface: boolean?,
	muted: boolean?
): (number?, number?, number?)
	local key = AccentDomain.normalize(id)
	if key == nil or key == AccentDomain.DEFAULT then
		return nil, nil, nil
	end
	local high, low = math.max(r, g, b), math.min(r, g, b)
	if high - low <= GREY_SPREAD then
		if surface then
			return AccentDomain.tintSurface(r, g, b, key)
		end
		return nil, nil, nil
	end
	local _, saturation, value = toHsv(r, g, b)
	if high - low < COLOR_MIN_CHROMA or saturation < COLOR_MIN_SATURATION or value < COLOR_MIN_VALUE then
		return nil, nil, nil
	end
	if key == GRAPHITE then
		local luminance = 0.299 * r + 0.587 * g + 0.114 * b
		return luminance, luminance, luminance
	end
	local hue = toHsv(hexChannels(SWATCHES[key].fill))
	if muted then
		return fromHsv(hue, saturation * MUTED_SATURATION, value * MUTED_VALUE)
	end
	return fromHsv(hue, saturation, value)
end

function AccentDomain.label(id: any): string
	local key = AccentDomain.normalize(id) or AccentDomain.DEFAULT
	return string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2)
end

return AccentDomain
