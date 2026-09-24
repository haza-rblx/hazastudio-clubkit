--!strict
-- CoverMesh: the artwork of a kit-drawn track cover (ADR 0014). Seeded by the track's name +
-- creator, so every server and every player draws the same cover for the same track.
--
-- v2 (owner, 2026-09-24): one leaderboard board's colour family per track (no gold), dark, in one
-- of three Apple-style fields (mesh / light from above / folds) with very soft edges ("blur 120")
-- and no grain. Mixed in OKLab. The dashboard preview (clubkit-infra lib/cover-tile.ts) runs
-- the same code, generated from scratchpad mesh-core-v2.js; change both together.
--
-- A straight port of the JS reference, bit for bit:
-- JS integer maths is reproduced with bit32, strings are hashed as UTF-16 code units like
-- String.charCodeAt, and the random draws happen in exactly the lab's order. Pure: no Roblox API,
-- colours are {r, g, b} in 0..255, so it runs under lune.

local CoverMesh = {}

export type Lab = { number } -- {L, a, b}
export type Rgb = { number } -- {r, g, b}, 0..255
export type Mesh = {
	nodes: { { Lab } }, -- nodes[row][col], 1-based, 4×4, sampled from the artwork
	art: any, -- Art (declared below)
	base: number,
}
export type Mood = "vivid" | "dusk" | "pastel" | "neon" | "mono"

local TWO32 = 4294967296
local GRID = 4

-- ---------------------------------------------------------------- JS integer maths

-- Math.imul for unsigned 32-bit operands, returned unsigned.
local function imul(a: number, b: number): number
	local ah, al = bit32.rshift(a, 16), bit32.band(a, 0xFFFF)
	local bh, bl = bit32.rshift(b, 16), bit32.band(b, 0xFFFF)
	return (al * bl + bit32.lshift((ah * bl + al * bh) % 65536, 16)) % TWO32
end
CoverMesh.imul = imul

-- String.charCodeAt units: code points above U+FFFF become a surrogate pair.
local function utf16Units(text: string): { number }
	local units = {}
	local ok = pcall(function()
		for _, cp in utf8.codes(text) do
			if cp >= 0x10000 then
				local v = cp - 0x10000
				table.insert(units, 0xD800 + bit32.rshift(v, 10))
				table.insert(units, 0xDC00 + bit32.band(v, 0x3FF))
			else
				table.insert(units, cp)
			end
		end
	end)
	if not ok then
		-- Not valid UTF-8: fall back to bytes, still deterministic.
		units = {}
		for i = 1, #text do
			units[i] = string.byte(text, i)
		end
	end
	return units
end

-- The lab's hashCode: Java-style 31-multiplier hash on int32, then Math.abs.
function CoverMesh.hash(text: string): number
	local h = 0
	for _, unit in ipairs(utf16Units(text)) do
		h = (bit32.lshift(h, 5) - h + unit) % TWO32
	end
	if h >= 2147483648 then
		h -= TWO32
	end
	return math.abs(h)
end

-- mulberry32, as a closure returning [0, 1).
function CoverMesh.random(seed: number): () -> number
	local state = seed % TWO32
	return function(): number
		state = (state + 0x6D2B79F5) % TWO32
		local t = state
		t = imul(bit32.bxor(t, bit32.rshift(t, 15)), bit32.bor(t, 1))
		t = bit32.bxor(t, (t + imul(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(t, 61))) % TWO32)
		return bit32.bxor(t, bit32.rshift(t, 14)) / TWO32
	end
end

-- ---------------------------------------------------------------- colour

local function clamp(v: number, lo: number, hi: number): number
	return math.min(hi, math.max(lo, v))
end

local function gam(c: number): number
	if c <= 0.0031308 then
		return 12.92 * c
	end
	return 1.055 * c ^ (1 / 2.4) - 0.055
end

function CoverMesh.oklch(L: number, C: number, hDeg: number): Lab
	local h = hDeg * math.pi / 180
	return { L, C * math.cos(h), C * math.sin(h) }
end

function CoverMesh.toRgb(lab: Lab): Rgb
	local L, a, b = lab[1], lab[2], lab[3]
	local l = (L + 0.3963377774 * a + 0.2158037573 * b) ^ 3
	local m = (L - 0.1055613458 * a - 0.0638541728 * b) ^ 3
	local s = (L - 0.0894841775 * a - 1.2914855480 * b) ^ 3
	return {
		clamp(gam(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s), 0, 1) * 255,
		clamp(gam(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s), 0, 1) * 255,
		clamp(gam(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s), 0, 1) * 255,
	}
end

-- JS Math.round: halves go up.
local function jsRound(v: number): number
	return math.floor(v + 0.5)
end

function CoverMesh.toRgbRounded(lab: Lab): Rgb
	local rgb = CoverMesh.toRgb(lab)
	return { jsRound(rgb[1]), jsRound(rgb[2]), jsRound(rgb[3]) }
end

-- ---------------------------------------------------------------- palette (v2, 2026-09-24)

-- Every cover takes one leaderboard board's colours (owner: covers, boards and UI in one
-- spectrum): the board hue for the dark base and the lit accent, plus its three glow hues. Blue →
-- violet → magenta → pink → red → orange; no gold or yellow (owner, 2026-09-24: they read olive /
-- mustard when dark), no green, teal or neon, and dark by design. Rows: board hue, its glow
-- triad, then optionally the hue of its dark tones (default hue + 10).
local FAMILIES = {
	{ 16, 350, 10, 24, 6 }, -- orange: glows stop at 24 and dark tones lean red (they read brown / mustard)
	{ 356, 322, 356, 22 },
	{ 328, 292, 328, 358 },
	{ 288, 256, 288, 325 },
	{ 262, 228, 262, 300 },
	{ 214, 200, 222, 256 },
}

local function lin(c: number): number
	if c <= 0.04045 then
		return c / 12.92
	end
	return ((c + 0.055) / 1.055) ^ 2.4
end

-- HSV (the boards are specified in HSV) to OKLab.
local function hsvLab(h: number, s: number, v: number): Lab
	local hh = ((h % 360) + 360) % 360 / 60
	local c = v * s
	local x = c * (1 - math.abs(hh % 2 - 1))
	local m = v - c
	local sector = math.floor(hh) % 6
	local r0, g0, b0
	if sector == 0 then
		r0, g0, b0 = c, x, 0
	elseif sector == 1 then
		r0, g0, b0 = x, c, 0
	elseif sector == 2 then
		r0, g0, b0 = 0, c, x
	elseif sector == 3 then
		r0, g0, b0 = 0, x, c
	elseif sector == 4 then
		r0, g0, b0 = x, 0, c
	else
		r0, g0, b0 = c, 0, x
	end
	local r, g, b = lin(r0 + m), lin(g0 + m), lin(b0 + m)
	local l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ^ (1 / 3)
	local mm = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ^ (1 / 3)
	local ss = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ^ (1 / 3)
	return {
		0.2104542553 * l + 0.7936177850 * mm - 0.0040720468 * ss,
		1.9779984951 * l - 2.4285922050 * mm + 0.4505937099 * ss,
		0.0259040371 * l + 0.7827717662 * mm - 0.8086757660 * ss,
	}
end

export type Palette = { bg: Lab, deep: Lab, mid: Lab, g1: Lab, g2: Lab, g3: Lab, accent: Lab, hi: Lab }

local function paletteOf(f: { number }): Palette
	local h = f[1]
	local d = f[5] or h + 10
	return {
		bg = hsvLab(d, 0.75, 0.1),
		deep = hsvLab(d, 0.74, 0.26),
		mid = hsvLab(d, 0.72, 0.44),
		g1 = hsvLab(f[2], 0.7, 0.72),
		g2 = hsvLab(f[3], 0.7, 0.8),
		g3 = hsvLab(f[4], 0.7, 0.66),
		accent = hsvLab(h, 0.62, 0.86),
		hi = hsvLab(h, 0.3, 0.95),
	}
end

-- Every v2 cover is dark; the mood stays in the API for the tile code (tint picks dark paper).
local AUTO_MOODS: { Mood } = { "dusk" }

function CoverMesh.isDarkMood(mood: string): boolean
	return mood == "dusk" or mood == "neon"
end

-- The seed text of a track. The lab keyed covers by title + " — " + DJ.
function CoverMesh.keyFor(name: string, creator: string?): string
	return string.format("%s — %s", name, creator or "")
end

function CoverMesh.moodFor(key: string): Mood
	return AUTO_MOODS[CoverMesh.hash(key .. "|mood") % #AUTO_MOODS + 1]
end

-- ---------------------------------------------------------------- artwork

-- Three styles the owner kept from the Apple set, each a soft-edged field, so the "blur" is the
-- edge width and no blur pass is needed: 0 mesh (3×3, B-spline), 1 light from above (Now
-- Playing), 2 folded sheets (Ventura). Layered waves were dropped (owner, 2026-09-24).
CoverMesh.STYLES = { "mesh", "light", "folds" }
local W = 0.56 -- edge softness: the owner's "blur 120"

local function smooth(a: number, b: number, x: number): number
	local t = clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local function mix(p: Lab, q: Lab, t: number): Lab
	return { p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t, p[3] + (q[3] - p[3]) * t }
end

local function dim(p: Lab, k: number): Lab
	return { p[1] * k, p[2] * k, p[3] * k }
end

-- Uniform cubic B-spline: smoother than Catmull-Rom (no overshoot), which is the blur the owner
-- asked for on the mesh style.
local function bs(p0: number, p1: number, p2: number, p3: number, t: number): number
	local t2 = t * t
	local t3 = t2 * t
	local u = 1 - t
	return (u * u * u * p0 + (3 * t3 - 6 * t2 + 4) * p1 + (-3 * t3 + 3 * t2 + 3 * t + 1) * p2 + t3 * p3) / 6
end

export type Art = {
	style: number, -- 0-based index into CoverMesh.STYLES
	p: Palette,
	grid: { { Lab } }?,
	ox: number?,
	oy: number?,
	blobs: { { cx: number, cy: number, rx: number, ry: number, c: Lab, a: number } }?,
	folds: { { c: Lab, cos: number, sin: number, off: number } }?,
}

-- Random draws happen in exactly the lab's order.
local function buildArt(seed: number): Art
	local r = CoverMesh.random(seed)
	local p = paletteOf(FAMILIES[math.floor(r() * #FAMILIES) + 1])
	local style = math.floor(r() * #CoverMesh.STYLES)
	local art: Art = { style = style, p = p }
	if style == 0 then
		local pool = { p.deep, p.mid, p.g1, p.g2, p.g3, p.bg }
		local grid = {}
		for row = 1, 3 do
			grid[row] = {}
			for col = 1, 3 do
				grid[row][col] = pool[math.floor(r() * #pool) + 1]
			end
		end
		grid[1][math.floor(r() * 3) + 1] = p.accent
		grid[3][math.floor(r() * 3) + 1] = p.bg
		art.grid = grid
		art.ox = (r() - 0.5) * 0.5
		art.oy = (r() - 0.5) * 0.5
	elseif style == 1 then
		local cx1 = 0.3 + r() * 0.4
		local cx2 = 0.3 + r() * 0.4
		local left = r() < 0.5
		local first = r() < 0.5
		art.blobs = {
			{ cx = cx1, cy = -0.05, rx = 0.7, ry = 0.4, c = p.accent, a = 0.9 },
			{ cx = cx2, cy = -0.1, rx = 0.35, ry = 0.18, c = p.hi, a = 0.75 },
			{ cx = if left then 0.1 else 0.9, cy = 0.95, rx = 0.45, ry = 0.3, c = if first then p.g1 else p.g3, a = 0.8 },
		}
	else
		local rot = r() * 3
		local cols = { p.g1, p.accent, p.g2, p.mid, p.g3 }
		local folds = {}
		for i = 1, 5 do
			local angle = rot + (i - 1) * 0.35
			folds[i] = { c = cols[i], cos = math.cos(angle), sin = math.sin(angle), off = 0.25 - (i - 1) * 0.12 }
		end
		art.folds = folds
	end
	return art
end

local function sampleArt(art: Art, u: number, v: number): Lab
	local p = art.p
	if art.style == 0 then
		local grid = art.grid :: { { Lab } }
		local k = math.sin(math.pi * u) * math.sin(math.pi * v)
		local wu = clamp(u + (art.ox :: number) * k, 0, 1)
		local wv = clamp(v + (art.oy :: number) * k, 0, 1)
		local gx, gy = wu * 2, wv * 2
		local i = math.min(1, math.floor(gx))
		local j = math.min(1, math.floor(gy))
		local tx, ty = gx - i, gy - j
		local out = { 0, 0, 0 }
		for c = 1, 3 do
			local rows = table.create(4)
			for n = -1, 2 do
				local row = grid[clamp(j + n, 0, 2) + 1]
				rows[n + 2] = bs(
					row[clamp(i - 1, 0, 2) + 1][c],
					row[clamp(i, 0, 2) + 1][c],
					row[clamp(i + 1, 0, 2) + 1][c],
					row[clamp(i + 2, 0, 2) + 1][c],
					tx
				)
			end
			out[c] = bs(rows[1], rows[2], rows[3], rows[4], ty)
		end
		return out
	elseif art.style == 1 then
		local col = mix(p.mid, p.bg, smooth(0, 1, v))
		for _, e in ipairs(art.blobs :: any) do
			local dx = (u - e.cx) / e.rx
			local dy = (v - e.cy) / e.ry
			local sd = (math.sqrt(dx * dx + dy * dy) - 1) * math.min(e.rx, e.ry)
			col = mix(col, e.c, e.a * (1 - smooth(-W, W, sd)))
		end
		return col
	end
	local col = p.deep
	for _, f in ipairs(art.folds :: any) do
		local x0, y0 = u - 0.5, v - 0.5
		local lx = x0 * f.cos + y0 * f.sin - f.off
		local ly = -x0 * f.sin + y0 * f.cos
		local dx, dy = lx / 0.75, ly / 0.22
		local sd = (math.sqrt(dx * dx + dy * dy) - 1) * 0.22
		col = mix(col, dim(col, 0.5), 0.45 * (1 - smooth(0, 2.2 * W, sd)))
		local body = mix(f.c, p.mid, clamp((lx + 0.6) / 1.2, 0, 1))
		col = mix(col, body, 1 - smooth(-W * 0.6, W * 0.6, sd))
	end
	return col
end

-- The artwork plus a 4×4 grid sampled from it: the UIGradient path, the tints and the glow colour
-- all read that grid. The mood is accepted for the callers' cache keys and ignored.
function CoverMesh.build(key: string, _mood: Mood?): Mesh
	local art = buildArt(CoverMesh.hash(key))
	local nodes: { { Lab } } = {}
	for row = 1, GRID do
		nodes[row] = {}
		for col = 1, GRID do
			nodes[row][col] = sampleArt(art, (col - 1) / (GRID - 1), (row - 1) / (GRID - 1))
		end
	end
	return { nodes = nodes, art = art, base = 0 }
end

-- ---------------------------------------------------------------- sampling

function CoverMesh.sample(mesh: Mesh, u: number, v: number): Lab
	return sampleArt(mesh.art, u, v)
end

-- The lab's ±0.8 ordered noise, which hides banding in 8-bit gradients.
function CoverMesh.dither(x: number, y: number): number
	local h = (x * 374761393 + y * 668265263) % TWO32
	h = imul(bit32.bxor(h, bit32.rshift(h, 13)), 1274126177)
	return (bit32.band(bit32.bxor(h, bit32.rshift(h, 16)), 255) / 255 - 0.5) * 1.6
end

-- Uint8ClampedArray conversion: clamp, then round half to even.
local function toByte(v: number): number
	if v <= 0 then
		return 0
	end
	if v >= 255 then
		return 255
	end
	local f = math.floor(v)
	local rest = v - f
	if rest > 0.5 or (rest == 0.5 and f % 2 == 1) then
		return f + 1
	end
	return f
end

-- One pixel of the EditableImage path, as the lab writes it into its canvas.
function CoverMesh.pixel(mesh: Mesh, x: number, y: number, size: number): (number, number, number)
	local rgb = CoverMesh.toRgb(CoverMesh.sample(mesh, (x + 0.5) / size, (y + 0.5) / size))
	local d = CoverMesh.dither(x, y)
	return toByte(rgb[1] + d), toByte(rgb[2] + d), toByte(rgb[3] + d)
end

-- The whole image as RGBA bytes, ready for EditableImage:WritePixelsBuffer.
function CoverMesh.pixels(mesh: Mesh, size: number): buffer
	local out = buffer.create(size * size * 4)
	for y = 0, size - 1 do
		for x = 0, size - 1 do
			local r, g, b = CoverMesh.pixel(mesh, x, y, size)
			local k = (y * size + x) * 4
			buffer.writeu8(out, k, r)
			buffer.writeu8(out, k + 1, g)
			buffer.writeu8(out, k + 2, b)
			buffer.writeu8(out, k + 3, 255)
		end
	end
	return out
end

-- ---------------------------------------------------------------- derived colours

local function average(list: { Lab }): Lab
	local sum = { 0, 0, 0 }
	for _, c in ipairs(list) do
		sum[1] += c[1]
		sum[2] += c[2]
		sum[3] += c[3]
	end
	return { sum[1] / #list, sum[2] / #list, sum[3] / #list }
end

-- The UIGradient path: three full-size layers built from the same mesh. rows (top to bottom,
-- opaque), cols (left to right, 0.55 opacity), and the corner diagonal (0.5 at the ends, 0 in
-- the middle), each as rounded {r, g, b}.
function CoverMesh.gradientLayers(mesh: Mesh): { rows: { Rgb }, cols: { Rgb }, topLeft: Rgb, bottomRight: Rgb }
	local rows = {}
	for r = 1, GRID do
		rows[r] = CoverMesh.toRgbRounded(average(mesh.nodes[r]))
	end
	local cols = {}
	for c = 1, GRID do
		local column = {}
		for r = 1, GRID do
			column[r] = mesh.nodes[r][c]
		end
		cols[c] = CoverMesh.toRgbRounded(average(column))
	end
	return {
		rows = rows,
		cols = cols,
		topLeft = CoverMesh.toRgbRounded(mesh.nodes[1][1]),
		bottomRight = CoverMesh.toRgbRounded(mesh.nodes[GRID][GRID]),
	}
end

export type Tint = { bg: Rgb, ink: Rgb, sub: Rgb, subTransparency: number, dark: boolean }

-- Colour for bands, columns and paper, taken from the artwork. tone: "auto" | "white" | "black";
-- where: "top" (the artwork's top row) or "all".
function CoverMesh.tint(mesh: Mesh, mood: string, tone: string, where: string): Tint
	local src: Lab
	if where == "top" then
		src = average(mesh.nodes[1])
	else
		local all = {}
		for r = 1, GRID do
			for c = 1, GRID do
				table.insert(all, mesh.nodes[r][c])
			end
		end
		src = average(all)
	end
	local C = math.sqrt(src[2] * src[2] + src[3] * src[3])
	local h = math.atan2(src[3], src[2]) * 180 / math.pi
	local dark = { 255, 255, 255 }
	local light = { 29, 29, 31 }
	if tone == "white" then
		return { bg = { 255, 255, 255 }, ink = light, sub = { 134, 134, 139 }, subTransparency = 0, dark = false }
	end
	if tone == "black" or (tone == "auto" and CoverMesh.isDarkMood(mood)) then
		local lab = CoverMesh.oklch(if tone == "black" then 0.17 else 0.28, math.min(C * 0.8, if tone == "black" then 0.03 else 0.08), h)
		return { bg = CoverMesh.toRgbRounded(lab), ink = dark, sub = dark, subTransparency = 0.38, dark = true }
	end
	local lab = CoverMesh.oklch(0.88, math.min(C * 0.55, 0.06), h)
	return { bg = CoverMesh.toRgbRounded(lab), ink = light, sub = light, subTransparency = 0.48, dark = false }
end

-- A bright accent in the hue of the artwork's lightest node (disc labels, ticket stubs).
function CoverMesh.glow(mesh: Mesh): Rgb
	local brightest = mesh.nodes[1][1]
	for r = 1, GRID do
		for c = 1, GRID do
			local node = mesh.nodes[r][c]
			-- The lab keeps the earlier node on a tie (reduce with >=).
			if node[1] > brightest[1] then
				brightest = node
			end
		end
	end
	local h = math.atan2(brightest[3], brightest[2]) * 180 / math.pi
	return CoverMesh.toRgbRounded(CoverMesh.oklch(0.84, 0.17, h))
end

return CoverMesh
