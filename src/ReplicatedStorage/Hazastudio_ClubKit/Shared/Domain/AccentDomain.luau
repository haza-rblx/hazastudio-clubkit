--!strict
-- Accent theme (CONTEXT.md "Accent theme"): the one colour a player picks in Settings → Appearance.
-- Multicolor (default) keeps every GUI's own colours; Graphite turns them grey; any other accent
-- paints state (on / selected / active) and recolours the kit's GUIs (`recolor`). Pure: hex strings
-- and 0..255 channels, no Roblox types, so the client builds Color3 and lune can spec this file.

local AccentDomain = {}

export type AccentId =
	"multicolor"
	| "graphite"
	| "blue"
	| "slate"
	| "teal"
	| "sage"
	| "green"
	| "yellow"
	| "saddle"
	| "orange"
	| "red"
	| "wine"
	| "pink"
	| "purple"

export type Swatch = {
	-- What the state is painted with (toggle track, selected pill, played row).
	fill: string,
	-- What is drawn on top of `fill` (text, icon, toggle knob).
	onFill: string,
}

-- Picker order, left to right, 7 per line (two full lines). Multicolor first: it is the default and
-- today's look. Colours run by family: cool line on top, warm line below.
AccentDomain.ORDER = {
	"multicolor",
	"graphite",
	"blue",
	"slate",
	"teal",
	"sage",
	"green",
	"yellow",
	"saddle",
	"orange",
	"red",
	"wine",
	"pink",
	"purple",
}

AccentDomain.DEFAULT = "multicolor"
local GRAPHITE = "graphite"

-- "Workshop muted" palette (owner 2026-10-08: street life, automotive, bengkel, 90s). The original
-- seven ids keep their slot so saved picks stay valid; their colour is the workshop shade of that
-- family (blue = denim, purple = plum, pink = dusty rose, red = brake red, orange = rust,
-- yellow = mustard, green = army olive). Graphite keeps the kit's monochrome (white fill, black on
-- it); the light shades (mustard, sage) take black on top as well.
local SWATCHES: { [string]: Swatch } = {
	multicolor = { fill = "FFFFFF", onFill = "000000" },
	graphite = { fill = "FFFFFF", onFill = "000000" },
	blue = { fill = "3E6FA8", onFill = "FFFFFF" }, -- denim
	slate = { fill = "5F7486", onFill = "FFFFFF" },
	teal = { fill = "2F7F86", onFill = "FFFFFF" }, -- petrol
	sage = { fill = "7FA088", onFill = "000000" },
	green = { fill = "7A8B2E", onFill = "FFFFFF" }, -- army olive
	yellow = { fill = "D9A21B", onFill = "000000" }, -- mustard
	saddle = { fill = "9C5B32", onFill = "FFFFFF" },
	orange = { fill = "D2601A", onFill = "FFFFFF" }, -- rust
	red = { fill = "C8102E", onFill = "FFFFFF" }, -- brake red
	wine = { fill = "7A1F3D", onFill = "FFFFFF" },
	pink = { fill = "C85A7A", onFill = "FFFFFF" }, -- dusty rose
	purple = { fill = "7E4A8C", onFill = "FFFFFF" }, -- plum
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
-- Deep colours (dark designed fills like close pills 1C0000): a surface tint never spreads channels
-- more than SURFACE_MIX * 255 = 20.4 apart, so a strongly saturated colour past that is a design.
local DEEP_MIN_CHROMA = 24
local DEEP_MIN_SATURATION = 0.6

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

-- Token ramp (owner 2026-10-08): under a colour accent the kit shows a handful of colours, not one
-- per design. Keeping each design's own saturation/brightness gave 47 different purples across the
-- GUIs. Every token derives from the accent's fill:
-- * primary   — the fill itself (main buttons, highlights, gradient tops)
-- * secondary — fill at 72% brightness (gradient bottoms, pressed shades)
-- * tertiary  — fill at 20% brightness (dark coloured fills: chips, benefit boxes, close pills)
-- * text      — fill at 55% saturation, full brightness (coloured text/icons on dark surfaces)
-- * onPrimary — the swatch's onFill (text drawn on a primary fill)
local SECONDARY_VALUE = 0.72
local TERTIARY_VALUE = 0.20
local TEXT_SATURATION = 0.55
local TOKEN_NAMES = { primary = true, secondary = true, tertiary = true, text = true, onPrimary = true }

-- Channels 0..255 of token `name` under accent `id`, or nil (Multicolor / Graphite / unknown).
function AccentDomain.token(id: any, name: any): (number?, number?, number?)
	local key = AccentDomain.normalize(id)
	if key == nil or AccentDomain.keepsDesign(key) or type(name) ~= "string" or not TOKEN_NAMES[name] then
		return nil, nil, nil
	end
	local swatch = SWATCHES[key]
	if name == "onPrimary" then
		return hexChannels(swatch.onFill)
	elseif name == "primary" then
		return hexChannels(swatch.fill)
	end
	local hue, saturation, value = toHsv(hexChannels(swatch.fill))
	if name == "secondary" then
		return fromHsv(hue, saturation, value * SECONDARY_VALUE)
	elseif name == "tertiary" then
		return fromHsv(hue, saturation, TERTIARY_VALUE)
	end
	return fromHsv(hue, saturation * TEXT_SATURATION, 1)
end

-- A design colour's step on the ramp, by its brightness: light/dark structure (gradient top vs
-- bottom, fill vs pressed) survives as primary vs secondary vs tertiary.
local LEVEL_PRIMARY = 0.75
local LEVEL_SECONDARY = 0.40
function AccentDomain.level(r: number, g: number, b: number): string
	local _, _, value = toHsv(r, g, b)
	if value >= LEVEL_PRIMARY then
		return "primary"
	elseif value >= LEVEL_SECONDARY then
		return "secondary"
	end
	return "tertiary"
end

-- Channels 0..255. The colour a GUI element shows under accent `id`, or nil to leave it as designed:
-- * Multicolor: nil (every GUI's own colours).
-- * Colours snap to the accent's token ramp by `level`; `role == "fg"` (text, icon colours) takes the
--   text token instead. Graphite turns them into their luminance grey.
-- * `token` (the `AccentToken` attribute) names the step outright — it also pulls a grey onto the
--   ramp (VVIP silver), while Graphite and Multicolor keep that grey as designed.
-- * Neutral greys get the surface tint (`tintSurface`) only when `surface` is set — backgrounds,
--   never strokes, text or icon colours.
-- * `muted` (strokes): thin lines in full accent glare, so they keep 45% of the token's saturation
--   and 70% of its brightness.
local MUTED_SATURATION = 0.45
local MUTED_VALUE = 0.7
function AccentDomain.recolor(
	r: number,
	g: number,
	b: number,
	id: any,
	surface: boolean?,
	muted: boolean?,
	role: string?,
	token: string?
): (number?, number?, number?)
	local key = AccentDomain.normalize(id)
	if key == nil or key == AccentDomain.DEFAULT then
		return nil, nil, nil
	end
	local high, low = math.max(r, g, b), math.min(r, g, b)
	local grey = high - low <= GREY_SPREAD
	local _, saturation, value = toHsv(r, g, b)
	local isColour = not grey
		and (
			(high - low >= COLOR_MIN_CHROMA and saturation >= COLOR_MIN_SATURATION and value >= COLOR_MIN_VALUE)
			or (high - low >= DEEP_MIN_CHROMA and saturation >= DEEP_MIN_SATURATION)
		)
	local named = token ~= nil and TOKEN_NAMES[token] == true
	if named and key ~= GRAPHITE then
		return AccentDomain.token(key, token)
	end
	if grey then
		if surface and not named then
			return AccentDomain.tintSurface(r, g, b, key)
		end
		return nil, nil, nil
	end
	if not isColour then
		return nil, nil, nil
	end
	if key == GRAPHITE then
		local luminance = 0.299 * r + 0.587 * g + 0.114 * b
		return luminance, luminance, luminance
	end
	local tr, tg, tb = AccentDomain.token(key, if role == "fg" then "text" else AccentDomain.level(r, g, b))
	if muted and tr and tg and tb then
		local hue, tokenSaturation, tokenValue = toHsv(tr, tg, tb)
		return fromHsv(hue, tokenSaturation * MUTED_SATURATION, tokenValue * MUTED_VALUE)
	end
	return tr, tg, tb
end

function AccentDomain.label(id: any): string
	local key = AccentDomain.normalize(id) or AccentDomain.DEFAULT
	return string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2)
end

return AccentDomain
