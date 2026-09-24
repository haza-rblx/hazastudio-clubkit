--!strict
-- PATH: StarterPlayerScripts/Client/UI/Music/CoverTile.luau
-- A kit-drawn track cover (ADR 0014): CoverArt's mesh artwork plus the track's cover text, laid
-- out in one of eight layouts ported from the approved cover lab. Everything about the look comes
-- from the web in track.cover (layout per playlist, lines per track, corner mark per venue); the
-- place holds no cover settings. Mounted as one child
-- (HzCoverTile) inside an existing cover element; the element's own image is left empty.
--
-- Geometry is written in the lab's unit, cqw = 1% of the tile's width, as Scale. Text boxes are
-- 1.25 × their type size tall (room for g/p/y descenders), TextScaled so a long name shrinks
-- instead of spilling, with a UITextSizeConstraint that stops short names growing past the lab's
-- size. Pixel-valued things (text caps, stroke widths, radii) follow the tile's AbsoluteSize.
--
-- Full tiles are a CanvasGroup so the rounded corner clips everything inside (a UICorner alone
-- never clips children). Layouts draw into a ClipsDescendants frame inside it, because a
-- CanvasGroup stops clipping once the client runs short of group texture memory (measured in Solo
-- 2026-09-23: with 46 groups on screen a bare CanvasGroup no longer clipped at all, and the
-- Monogram letter spilled out of its tile) — then the corners are square, but nothing escapes.
-- List cards (opts.small) skip the CanvasGroup where per-corner radii exist and round their own
-- corner elements instead (roundEdges), and are built a few per frame. Compact tiles are the
-- artwork only, no text.

local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoverMesh = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.CoverMesh)
local CoverTextPick = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.CoverTextPick)
local CoverArt = require(script.Parent.CoverArt)

local CoverTile = {}

-- Per-corner radii (UICorner.TopLeftRadius…) are a beta in the 2026-09 engine docs: probed once, so a
-- client without them falls back to drawing the ticket's artwork twice (see builders.tiket).
local PER_CORNER = pcall(function()
	local probe = Instance.new("UICorner")
	probe.TopLeftRadius = UDim.new(0, 1)
	probe.BottomLeftRadius = UDim.new(0, 2)
	assert(probe.TopLeftRadius.Offset == 1 and probe.BottomLeftRadius.Offset == 2)
	probe:Destroy()
end)

local TILE_NAME = "HzCoverTile"
local FONT = "rbxassetid://12187365364" -- Inter
local DEFAULT_LAYOUT = "editorial"
local LAYOUTS = { "editorial", "sampul", "samping", "monogram", "piringan", "tiket", "swiss", "cd" }
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

CoverTile.LAYOUTS = LAYOUTS

-- small: a list card (the Library column, track rows, the queue). It is drawn without a CanvasGroup
-- where per-corner radii exist, with fewer hairline details, and built in the background a few
-- tiles per frame, so opening a long list costs no hitch (owner, 2026-09-23: "se efisien mungkin").
export type Opts = { compact: boolean?, index: number?, small: boolean? }

type Scaled = {
	kind: string,
	target: Instance,
	cqw: number,
	min: number?,
	edges: { boolean }?,
	label: TextLabel?,
	max: number?,
}
type Build = {
	root: GuiObject,
	scaled: { Scaled },
	z: number,
	-- The tile's own corner, taken from the element it sits in; insetCorner follows it.
	outer: UDim?,
}
type Mounted = {
	track: any,
	playlist: any?,
	config: any,
	opts: Opts?,
	key: string,
	cleanup: { RBXScriptConnection },
	pending: boolean?,
}

-- Strong on purpose (memory roblox-weak-tables-instances); entries leave on Destroying/unmount.
local mounted: { [GuiObject]: Mounted } = {}
local venueName: string? = nil
local venueLookupStarted = false

-- ---------------------------------------------------------------- small helpers

local function P(cqw: number): number
	return cqw / 100
end

-- The lab's type scale: small text grows 20 %, larger text 8 %, so secondary lines stay readable
-- at 44-150 px while the headline stays the loudest thing.
local function sz(n: number): number
	return n * (if n < 7 then 1.2 else 1.08)
end

-- A headline shrinks for long names (the lab's fit()).
local function fit(text: string, base: number, min: number, perChar: number): number
	local length = utf8.len(text) or #text
	return sz(math.max(min, math.min(base, base * perChar / math.max(perChar, length))))
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function nextZ(b: Build): number
	b.z += 1
	return b.z
end

local function box(b: Build, parent: GuiObject, x: number, y: number, w: number, h: number, colour: Color3?, transparency: number?): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.Position = UDim2.fromScale(x, y)
	frame.Size = UDim2.fromScale(w, h)
	frame.BackgroundColor3 = colour or WHITE
	frame.BackgroundTransparency = if colour then (transparency or 0) else 1
	frame.ZIndex = nextZ(b)
	frame.Parent = parent
	return frame
end

local function corner(b: Build, target: GuiObject, cqw: number)
	local c = Instance.new("UICorner")
	c.Parent = target
	table.insert(b.scaled, { kind = "corner", target = c, cqw = cqw })
end

-- A frame inset `cqw` from the tile's edge keeps a concentric corner: the tile's radius minus the
-- inset. A fixed radius only matched the lab's 9% tile corner, so in a slot with a larger corner
-- (the Library column, 16 px) the ticket's frame line looked cut off (owner, 2026-09-23).
-- `min` (cqw) keeps a floor for elements whose other corners sit inside the card, like the
-- ticket's artwork panel (its lower corners meet the tear line, not the card's edge).
local function insetCorner(b: Build, target: GuiObject, cqw: number, min: number?)
	local c = Instance.new("UICorner")
	c.Parent = target
	table.insert(b.scaled, { kind = "inset", target = c, cqw = cqw, min = min })
end

local function circle(target: GuiObject)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = target
end

local function stroke(b: Build, target: GuiObject, cqw: number, colour: Color3, transparency: number)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = colour
	s.Transparency = transparency
	s.Parent = target
	table.insert(b.scaled, { kind = "stroke", target = s, cqw = cqw })
end

type TextSpec = {
	text: string,
	size: number, -- cqw
	weight: Enum.FontWeight,
	colour: Color3,
	transparency: number?,
	x: number, -- cqw, left edge
	w: number, -- cqw
	y: number?, -- cqw, top edge
	bottom: number?, -- cqw, bottom edge (instead of y)
	h: number?, -- cqw, box height (default 1.25 × size)
	alignX: Enum.TextXAlignment?,
	alignY: Enum.TextYAlignment?,
	wrap: boolean?,
	lineHeight: number?,
	upper: boolean?,
	rotation: number?,
}

local function text(b: Build, parent: GuiObject, spec: TextSpec): TextLabel
	local h = spec.h or spec.size * 1.25
	local top = spec.y or ((spec.bottom or 100) - h)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Position = UDim2.fromScale(P(spec.x), P(top))
	label.Size = UDim2.fromScale(P(spec.w), P(h))
	label.FontFace = Font.new(FONT, spec.weight, Enum.FontStyle.Normal)
	label.Text = if spec.upper then string.upper(spec.text) else spec.text
	label.TextColor3 = spec.colour
	label.TextTransparency = spec.transparency or 0
	label.TextXAlignment = spec.alignX or Enum.TextXAlignment.Left
	label.TextYAlignment = spec.alignY or Enum.TextYAlignment.Center
	label.TextWrapped = spec.wrap == true
	label.LineHeight = spec.lineHeight or 1
	label.TextScaled = true
	label.RichText = false
	label.ZIndex = nextZ(b)
	if spec.rotation then
		-- Rotated about its centre: x/w/y/h describe the unrotated box.
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(P(spec.x + spec.w / 2), P(top + h / 2))
		label.Rotation = spec.rotation
	end
	local cap = Instance.new("UITextSizeConstraint")
	cap.Parent = label
	table.insert(b.scaled, { kind = "text", target = cap, cqw = spec.size })
	label.Parent = parent
	return label
end

local function gradientFrame(b: Build, parent: GuiObject, rotation: number, transparency: NumberSequence, colour: Color3?): Frame
	local frame = box(b, parent, 0, 0, 1, 1, colour or BLACK, 0)
	local g = Instance.new("UIGradient")
	g.Rotation = rotation
	g.Transparency = transparency
	g.Parent = frame
	return frame
end

-- Darkens the lower part so white text reads: clear down to `from`, then to `alpha` at the bottom.
local function scrim(b: Build, parent: GuiObject, from: number, alpha: number): Frame
	return gradientFrame(b, parent, 90, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(from, 1),
		NumberSequenceKeypoint.new(1, 1 - alpha),
	}))
end

-- The lab's sheen: a soft white light from the top left.
local function sheen(b: Build, parent: GuiObject): Frame
	return gradientFrame(b, parent, 75, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.78),
		NumberSequenceKeypoint.new(0.38, 1),
		NumberSequenceKeypoint.new(1, 1),
	}), WHITE)
end

local function artIn(
	b: Build,
	parent: GuiObject,
	key: string,
	mood: string,
	round: UDim?,
	cqwRadius: number?,
	insetCqw: number?,
	insetKind: string?
)
	local image, corners = CoverArt.mount(parent, key, mood, round)
	image.ZIndex = nextZ(b)
	for _, child in ipairs(image:GetChildren()) do
		if child:IsA("GuiObject") then
			child.ZIndex = image.ZIndex
		end
	end
	if insetCqw then
		for _, c in ipairs(corners) do
			table.insert(b.scaled, { kind = insetKind or "inset", target = c, cqw = insetCqw, min = cqwRadius })
		end
	elseif cqwRadius then
		for _, c in ipairs(corners) do
			table.insert(b.scaled, { kind = "corner", target = c, cqw = cqwRadius })
		end
	end
	return image
end

local function durationText(seconds: number): string?
	if seconds < 1800 then
		return nil
	end
	local h = seconds // 3600
	local m = math.floor((seconds % 3600) / 60 + 0.5)
	if h > 0 then
		return if m > 0 then string.format("%d JAM %d MNT", h, m) else string.format("%d JAM", h)
	end
	return string.format("%d MNT", m)
end

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h, m, sec = s // 3600, (s % 3600) // 60, s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, sec)
	end
	return string.format("%d:%02d", m, sec)
end

-- Rough width of Inter Bold caps/numbers in cqw, for chips that size to their text.
local function capsWidth(label: string, size: number): number
	return (utf8.len(label) or #label) * size * 0.66
end

-- A left-aligned chip is as wide as the text it holds plus `pad` (cqw) on each side, capped at
-- `max` (cqw). capsWidth only guesses — it ran about a third wide on "THE BASIC TEST 1.3", and the
-- empty end of the translucent chip showed the artwork's sheen through it (owner, 2026-09-23) — so
-- the rescale pass sizes it from the label's measured TextBounds instead.
local function fitChip(b: Build, chip: GuiObject, label: TextLabel, pad: number, max: number)
	table.insert(b.scaled, { kind = "chipFit", target = chip, cqw = pad, label = label, max = max })
end

-- A dark pill with the set's length (only for sets of 30 minutes or more).
local function pill(b: Build, parent: GuiObject, label: string, x: number?, y: number?, right: number?, bottom: number?)
	local size = 5.5
	local w = capsWidth(label, size) + 6.8
	local h = size * 1.25 + 2.4
	local left = x or (100 - (right or 0) - w)
	local top = y or (100 - (bottom or 0) - h)
	local chip = box(b, parent, P(left), P(top), P(w), P(h), BLACK, 0.55)
	circle(chip)
	text(b, parent, { text = label, size = size, weight = Enum.FontWeight.Bold, colour = WHITE, x = left + 3.4, w = w - 6.8, y = top + 1.2, alignX = Enum.TextXAlignment.Center })
end

local function markLabel(b: Build, venue: string?, colour: Color3, transparency: number?)
	if venue then
		text(b, b.root, { text = venue, size = 5.3, weight = Enum.FontWeight.ExtraBold, colour = colour, transparency = transparency, x = 40, w = 50, y = 8.5, alignX = Enum.TextXAlignment.Right })
	end
end

-- The colour behind the tile, for the ticket's punched notches (Roblox cannot cut real holes).
local function backdropColour(host: GuiObject): Color3
	local node: Instance? = host.Parent
	while node and node:IsA("GuiObject") do
		if node.BackgroundTransparency < 0.5 then
			return node.BackgroundColor3
		end
		node = node.Parent
	end
	return Color3.fromRGB(17, 17, 20)
end

-- ---------------------------------------------------------------- layouts

type Ctx = {
	b: Build,
	key: string,
	mood: string,
	mesh: CoverMesh.Mesh,
	head: string,
	sub: string?,
	kicker: string?,
	venue: string?,
	dur: string?,
	seconds: number,
	index: number,
	host: GuiObject,
	track: any,
	playlist: any?,
	small: boolean,
}

local builders: { [string]: (Ctx) -> () } = {}

builders.editorial = function(c: Ctx)
	local b = c.b
	local t = CoverMesh.tint(c.mesh, c.mood, "auto", "top")
	b.root.BackgroundColor3 = rgb(t.bg)
	b.root.BackgroundTransparency = 0
	local bandH = if c.sub then 50 else 44
	local bottom = bandH - 5
	if c.sub then
		local subLabel = text(b, b.root, { text = c.sub, size = sz(8), weight = Enum.FontWeight.SemiBold, colour = rgb(t.sub), transparency = t.subTransparency, x = 11, w = 78, bottom = bottom })
		bottom = bottom - subLabel.Size.Y.Scale * 100 - 1
	end
	text(b, b.root, { text = c.head, size = fit(c.head, 12, 7.5, 11), weight = Enum.FontWeight.ExtraBold, colour = rgb(t.ink), x = 11, w = 78, bottom = bottom })
	local media = box(b, b.root, 0, P(bandH), 1, 1 - P(bandH))
	artIn(b, media, c.key, c.mood)
	sheen(b, media)
	if c.dur then
		pill(b, b.root, c.dur, nil, nil, 10, 9)
	end
	markLabel(b, c.venue, rgb(t.ink))
end

builders.sampul = function(c: Ctx)
	local b = c.b
	artIn(b, b.root, c.key, c.mood)
	sheen(b, b.root)
	scrim(b, b.root, 0.3, 0.72)
	local bottom = 90
	if c.sub then
		local subLabel = text(b, b.root, { text = c.sub, size = sz(7.4), weight = Enum.FontWeight.SemiBold, colour = WHITE, transparency = 0.15, x = 11, w = 78, bottom = bottom })
		bottom = bottom - subLabel.Size.Y.Scale * 100 - 1
	end
	text(b, b.root, { text = c.head, size = fit(c.head, 12.5, 7.5, 10), weight = Enum.FontWeight.ExtraBold, colour = WHITE, x = 11, w = 78, bottom = bottom })
	markLabel(b, c.venue, WHITE)
	if c.dur then
		pill(b, b.root, c.dur, 10, 8)
	end
end

builders.samping = function(c: Ctx)
	local b = c.b
	local t = CoverMesh.tint(c.mesh, c.mood, "auto", "all")
	b.root.BackgroundColor3 = rgb(t.bg)
	b.root.BackgroundTransparency = 0
	local media = box(b, b.root, 0.34, 0, 0.66, 1)
	artIn(b, media, c.key, c.mood)
	sheen(b, media)
	if c.dur then
		pill(b, b.root, c.dur, nil, nil, 9, 9)
	end
	-- The headline stands up the colour column, reading bottom to top.
	local size = fit(c.head, 11, 7, 9)
	local h = size * 1.25
	local length = 58
	text(b, b.root, { text = c.head, size = size, weight = Enum.FontWeight.ExtraBold, colour = rgb(t.ink), x = 17 - length / 2, w = length, y = 90 - length / 2 - h / 2, h = h, rotation = -90 })
	if c.sub then
		text(b, b.root, { text = c.sub, size = sz(4.2), weight = Enum.FontWeight.Bold, colour = rgb(t.sub), transparency = t.subTransparency, x = 4, w = 26, y = 9, h = 20, alignX = Enum.TextXAlignment.Center, alignY = Enum.TextYAlignment.Top, wrap = true, lineHeight = 1.15, upper = true })
	end
end

builders.monogram = function(c: Ctx)
	local b = c.b
	artIn(b, b.root, c.key, c.mood)
	sheen(b, b.root)
	local first = string.match(c.head, "^%s*(" .. utf8.charpattern .. ")") or "?"
	local letter = text(b, b.root, { text = string.upper(first), size = 68, weight = Enum.FontWeight.Heavy, colour = WHITE, transparency = 0.1, x = 0, w = 90, y = 120 - 81.6, h = 81.6, alignX = Enum.TextXAlignment.Right, alignY = Enum.TextYAlignment.Bottom })
	letter.Name = "Monogram"
	gradientFrame(b, b.root, 90, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.62),
		NumberSequenceKeypoint.new(0.45, 1),
		NumberSequenceKeypoint.new(1, 1),
	}))
	local headLabel = text(b, b.root, { text = c.head, size = fit(c.head, 8, 5.6, 12), weight = Enum.FontWeight.ExtraBold, colour = WHITE, x = 11, w = 49, y = 9 })
	if c.sub then
		text(b, b.root, { text = c.sub, size = sz(6), weight = Enum.FontWeight.SemiBold, colour = WHITE, transparency = 0.18, x = 11, w = 49, y = 9 + headLabel.Size.Y.Scale * 100 + 0.4 })
	end
	if c.dur then
		pill(b, b.root, c.dur, 10, nil, nil, 9)
	end
end

builders.piringan = function(c: Ctx)
	local b = c.b
	b.root.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
	b.root.BackgroundTransparency = 0
	-- The record, peeking out from behind the sleeve: rim, grooves, artwork label, hole.
	local disc = box(b, b.root, 0.23, 0.13, 0.74, 0.74, Color3.fromRGB(32, 32, 38))
	circle(disc)
	local vinyl = box(b, disc, P(1.2 / 0.74), P(1.2 / 0.74), 1 - P(2.4 / 0.74), 1 - P(2.4 / 0.74), Color3.fromRGB(20, 20, 24))
	circle(vinyl)
	for _, inset in ipairs({ 5.25, 9.75, 14.25 }) do
		local f = inset / 74
		local groove = box(b, disc, f, f, 1 - 2 * f, 1 - 2 * f)
		circle(groove)
		stroke(b, groove, 0.5, Color3.fromRGB(38, 38, 46), 0)
	end
	local labelFrame = box(b, disc, 0.3, 0.3, 0.4, 0.4)
	artIn(b, labelFrame, c.key, c.mood, UDim.new(0.5, 0))
	local hole = box(b, disc, 0.475, 0.475, 0.05, 0.05, Color3.fromRGB(14, 14, 18))
	circle(hole)

	local sleeve = box(b, b.root, 0, 0, 0.58, 1)
	artIn(b, sleeve, c.key, c.mood)
	sheen(b, sleeve)
	scrim(b, sleeve, 0.4, 0.66)
	local bottom = 91
	if c.sub then
		local subLabel = text(b, b.root, { text = c.sub, size = sz(5.4), weight = Enum.FontWeight.SemiBold, colour = WHITE, transparency = 0.2, x = 8, w = 46, bottom = bottom })
		bottom = bottom - subLabel.Size.Y.Scale * 100 - 0.4
	end
	text(b, b.root, { text = c.head, size = fit(c.head, 8, 5.5, 9), weight = Enum.FontWeight.ExtraBold, colour = WHITE, x = 8, w = 46, bottom = bottom })
	if c.dur then
		pill(b, b.root, c.dur, nil, nil, 6, 8)
	end
end

builders.tiket = function(c: Ctx)
	-- A printed concert ticket: artwork panel, torn line with punched notches, then the main
	-- part (Admit one + set chip, headline, DJ) and a stub with a barcode and serial.
	local b = c.b
	local t = CoverMesh.tint(c.mesh, c.mood, "auto", "all")
	local ink = rgb(t.ink)
	local ruleColour = if t.dark then WHITE else BLACK
	local ruleTransparency = if t.dark then 0.74 else 0.82
	b.root.BackgroundColor3 = rgb(t.bg)
	b.root.BackgroundTransparency = 0
	local seed = CoverMesh.hash(c.key)
	local M, ART_H, STUB_W = 6, 38, 19
	local TEAR = M + ART_H + 5.5

	local frameLine = box(b, b.root, P(2.4), P(2.4), P(95.2), P(95.2))
	insetCorner(b, frameLine, 2.4)
	stroke(b, frameLine, 0.45, ruleColour, if t.dark then 0.88 else 0.92)

	local media = box(b, b.root, P(M), P(M), P(100 - 2 * M), P(ART_H))
	-- Its top corners follow the card's own (the slot's radius minus the margin, never below the
	-- lab's 4 cqw), its bottom corners stay the lab's 4 cqw where the panel meets the tear line
	-- (owner, 2026-09-23). A UICorner is one radius for all four corners, so the same artwork is
	-- drawn twice: once rounded like the card, and once more with the small radius, sized to the
	-- whole panel but clipped to its lower half. Both come from the same cached image.
	-- Where the client has per-corner radii (UICorner.TopLeftRadius…, still a beta in the 2026-09
	-- engine docs) one copy is enough; the second copy is the fallback for clients without them.
	if PER_CORNER then
		artIn(b, media, c.key, c.mood, UDim.new(0, 0), 4, M, "insetTop")
	else
		artIn(b, media, c.key, c.mood, UDim.new(0, 0), 4, M)
		local lower = box(b, media, 0, 0.5, 1, 0.5)
		lower.ClipsDescendants = true
		local lowerArt = artIn(b, lower, c.key, c.mood, UDim.new(0, 0), 4)
		lowerArt.Size = UDim2.fromScale(1, 2)
		lowerArt.Position = UDim2.fromScale(0, -1)
	end
	local mediaSheen = sheen(b, media)
	insetCorner(b, mediaSheen, M, 4)
	if c.venue then
		local size = 5.3
		local w = math.min(capsWidth(c.venue, size) + 4.4, 60)
		local chip = box(b, b.root, P(M + 3.6), P(M + 3.2), P(w), P(size * 1.25 + 1.8), BLACK, 0.68)
		circle(chip)
		local venueLabel = text(b, b.root, { text = c.venue, size = size, weight = Enum.FontWeight.Bold, colour = WHITE, x = M + 3.6 + 2.2, w = w - 4.4, y = M + 3.2 + 0.9, upper = true })
		fitChip(b, chip, venueLabel, 2.2, w)
	end
	if c.dur then
		pill(b, b.root, c.dur, nil, nil, M + 3.6, 100 - M - ART_H + 3.6)
	end

	local cut = backdropColour(c.host)
	for _, x in ipairs({ -5, 95 }) do
		local notch = box(b, b.root, P(x), P(TEAR - 5), P(10), P(10), cut)
		circle(notch)
	end
	-- Dotted tear line; dots are Frames, a few more than a dash so it reads as perforation. At list
	-- size the dots are under a pixel apart, so one faint hairline draws the same thing.
	if c.small then
		box(b, b.root, P(8), P(TEAR - 0.3), P(84), P(0.6), ruleColour, 1 - (1 - ruleTransparency) * 0.6)
	else
		local DOTS = 24
		for i = 0, DOTS - 1 do
			box(b, b.root, P(8 + i * (84 - 0.8) / (DOTS - 1)), P(TEAR - 0.4), P(0.8), P(0.8), ruleColour, ruleTransparency)
		end
	end

	local mainX, mainW = 9, 100 - (STUB_W + 7) - 9
	local rowY = TEAR + 5
	local admit = "ADMIT ONE"
	text(b, b.root, { text = admit, size = 5.3, weight = Enum.FontWeight.Bold, colour = rgb(t.sub), transparency = t.subTransparency, x = mainX, w = capsWidth(admit, 5.3), y = rowY })
	if c.kicker then
		local size = sz(3.8)
		local chipX = mainX + capsWidth(admit, 5.3) + 2
		local w = math.min(capsWidth(c.kicker, size) + 4, mainX + mainW - chipX)
		local chip = box(b, b.root, P(chipX), P(rowY + 0.4), P(w), P(size * 1.25 + 1.6), if t.dark then WHITE else BLACK, if t.dark then 0.86 else 0.92)
		circle(chip)
		local kickerLabel = text(b, b.root, { text = c.kicker, size = size, weight = Enum.FontWeight.Bold, colour = ink, x = chipX + 2, w = w - 4, y = rowY + 1.2, upper = true })
		fitChip(b, chip, kickerLabel, 2, w)
	end
	local headY = rowY + 5.3 * 1.25 + 1.4
	local headLabel = text(b, b.root, { text = CoverTextPick.clip(c.head, CoverTextPick.TICKET_MAX), size = sz(12.5), weight = Enum.FontWeight.ExtraBold, colour = ink, x = mainX, w = mainW, y = headY })
	if c.sub then
		text(b, b.root, { text = CoverTextPick.clip(c.sub, CoverTextPick.TICKET_MAX), size = sz(7), weight = Enum.FontWeight.SemiBold, colour = rgb(t.sub), transparency = t.subTransparency, x = mainX, w = mainW, y = headY + headLabel.Size.Y.Scale * 100 + 1.4 })
	end

	-- Stub: dotted divider, a barcode of stacked bars (no rotation needed), the serial under it.
	local stubX, stubTop, stubBottom = 100 - M - 1 - (STUB_W - 2), rowY, 100 - 8.5
	if c.small then
		box(b, b.root, P(stubX), P(stubTop), P(0.6), P(stubBottom - stubTop), ruleColour, 1 - (1 - ruleTransparency) * 0.6)
	else
		for i = 0, 11 do
			box(b, b.root, P(stubX), P(stubTop + i * (stubBottom - stubTop - 0.6) / 11), P(0.6), P(0.6), ruleColour, ruleTransparency)
		end
	end
	local contentX = stubX + 0.6 + 3.6
	local contentW = 100 - M - 1 - contentX
	local serialH = sz(3.2) * 1.25
	local barsBottom = stubBottom - serialH - 1.6
	local heights: { number } = {}
	local widths: { number } = {}
	local total = 0
	local h = seed
	for i = 1, 12 do
		h = (CoverMesh.imul(h, 1103515245) + 12345) % 4294967296
		heights[i] = 0.4 + (h % 3) * 0.35
		widths[i] = (60 + (bit32.rshift(h, 5) % 5) * 10) / 100
		total += heights[i]
	end
	local gap = (barsBottom - stubTop - total) / 11
	local y = stubTop
	for i = 1, 12 do
		box(b, b.root, P(contentX), P(y), P(contentW * widths[i]), P(heights[i]), ink, 0)
		y += heights[i] + gap
	end
	if not c.small then
		text(b, b.root, { text = string.format("%05d", seed % 100000), size = sz(3.2), weight = Enum.FontWeight.Bold, colour = rgb(t.sub), transparency = t.subTransparency, x = contentX, w = contentW, y = stubBottom - serialH })
	end
end

builders.swiss = function(c: Ctx)
	local b = c.b
	local t = CoverMesh.tint(c.mesh, c.mood, "white", "all")
	local ink = rgb(t.ink)
	b.root.BackgroundColor3 = rgb(t.bg)
	b.root.BackgroundTransparency = 0
	box(b, b.root, 0, 0.5, 1, P(0.35), BLACK, 0.86)
	box(b, b.root, 0.5, 0, P(0.35), 1, BLACK, 0.86)
	text(b, b.root, { text = string.format("%02d", (c.index - 1) % 99 + 1), size = 26, weight = Enum.FontWeight.Heavy, colour = ink, x = 8, w = 40, y = 5, h = 31.2 })
	local media = box(b, b.root, 0.5, 0.5, 0.5, 0.5)
	artIn(b, media, c.key, c.mood)
	sheen(b, media)
	text(b, b.root, { text = c.head, size = fit(c.head, 7.6, 5, 7), weight = Enum.FontWeight.ExtraBold, colour = ink, x = 8, w = 38, y = 57, h = 36, alignY = Enum.TextYAlignment.Top, wrap = true, lineHeight = 1.14 })
	local y = 7
	local function row(label: string, value: string)
		text(b, b.root, { text = label, size = sz(3.8), weight = Enum.FontWeight.Bold, colour = rgb(t.sub), x = 56, w = 38, y = y, upper = true })
		y += sz(3.8) * 1.25
		text(b, b.root, { text = value, size = sz(5.4), weight = Enum.FontWeight.SemiBold, colour = ink, x = 56, w = 38, y = y })
		y += sz(5.4) * 1.25 + 2.6
	end
	if c.sub then
		row("DJ", c.sub)
	end
	-- A playlist card has no length; an empty "0:00" row would read as a broken track.
	if c.seconds > 0 then
		row("Durasi", clock(c.seconds))
	end
end

builders.cd = function(c: Ctx)
	-- A compact disc from above: artwork printed on the disc, silver rim, clear hub, rainbow sheen.
	local b = c.b
	local t = CoverMesh.tint(c.mesh, c.mood, "auto", "all")
	b.root.BackgroundColor3 = rgb(t.bg)
	b.root.BackgroundTransparency = 0
	local disc = box(b, b.root, 0.07, 0.07, 0.86, 0.86)
	circle(disc)
	stroke(b, disc, 1, Color3.fromRGB(216, 217, 222), 0)
	artIn(b, disc, c.key, c.mood, UDim.new(0.5, 0))
	local rainbow = box(b, disc, 0, 0, 1, 1, WHITE, 0)
	circle(rainbow)
	local g = Instance.new("UIGradient")
	g.Rotation = 35
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 120, 120)),
		ColorSequenceKeypoint.new(0.46, Color3.fromRGB(255, 230, 120)),
		ColorSequenceKeypoint.new(0.52, Color3.fromRGB(120, 255, 170)),
		ColorSequenceKeypoint.new(0.58, Color3.fromRGB(120, 190, 255)),
		ColorSequenceKeypoint.new(0.64, Color3.fromRGB(200, 120, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 120, 255)),
	})
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 1),
		NumberSequenceKeypoint.new(0.4, 0.78),
		NumberSequenceKeypoint.new(0.46, 0.78),
		NumberSequenceKeypoint.new(0.52, 0.8),
		NumberSequenceKeypoint.new(0.58, 0.78),
		NumberSequenceKeypoint.new(0.64, 0.8),
		NumberSequenceKeypoint.new(0.72, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = rainbow
	circle(scrim(b, disc, 0.4, 0.66))
	local hub = box(b, disc, 0.36, 0.36, 0.28, 0.28, Color3.fromRGB(235, 237, 242), 0.45)
	circle(hub)
	stroke(b, hub, 0.5, WHITE, 0.5)
	local hole = box(b, disc, 0.455, 0.455, 0.09, 0.09, rgb(t.bg), 0)
	circle(hole)
	stroke(b, hole, 0.5, BLACK, 0.85)

	local bottom = 7 + 86 * 0.87
	if c.sub then
		local subLabel = text(b, b.root, { text = c.sub, size = sz(5.2), weight = Enum.FontWeight.SemiBold, colour = WHITE, transparency = 0.15, x = 22.5, w = 55, bottom = bottom, alignX = Enum.TextXAlignment.Center })
		bottom = bottom - subLabel.Size.Y.Scale * 100 - 0.3
	end
	text(b, b.root, { text = c.head, size = fit(c.head, 8, 5.6, 12), weight = Enum.FontWeight.ExtraBold, colour = WHITE, x = 22.5, w = 55, bottom = bottom, alignX = Enum.TextXAlignment.Center })
	if c.venue then
		text(b, b.root, { text = c.venue, size = sz(4), weight = Enum.FontWeight.Bold, colour = WHITE, transparency = 0.15, x = 7, w = 86, y = 7 + 86 * 0.14, alignX = Enum.TextXAlignment.Center, upper = true })
	end
	if c.dur then
		pill(b, b.root, c.dur, nil, 5, 5)
	end
end

-- ---------------------------------------------------------------- experience name

-- The corner mark "" means the experience's own name, which only the game knows.
local function experienceName(): string?
	if not venueLookupStarted then
		venueLookupStarted = true
		task.spawn(function()
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, game.PlaceId)
			if ok and type(info) == "table" and type(info.Name) == "string" and info.Name ~= "" then
				venueName = string.sub(info.Name, 1, 40)
				CoverTile.refreshAll()
			end
		end)
	end
	return venueName
end

function CoverTile.layoutFor(track: any): string
	local cover = track.cover
	local layout = if type(cover) == "table" then cover.layout else nil
	return if type(layout) == "string" and table.find(LAYOUTS, layout) then layout else DEFAULT_LAYOUT
end

-- ---------------------------------------------------------------- mount

local function findTile(host: GuiObject): GuiObject?
	local existing = host:FindFirstChild(TILE_NAME)
	return if existing and existing:IsA("GuiObject") then existing else nil
end

function CoverTile.unmount(host: GuiObject)
	local record = mounted[host]
	if record then
		for _, connection in ipairs(record.cleanup) do
			connection:Disconnect()
		end
		mounted[host] = nil
	end
	local tile = findTile(host)
	if tile then
		tile:Destroy()
	end
end

-- ---------------------------------------------------------------- group-less rounding

-- Where a list card has no CanvasGroup, nothing clips its artwork to the rounded card: every drawn
-- element that reaches one of the card's corners gets that corner rounded itself (per-corner
-- radii), and elements that already carry a UICorner (circles, inset frames) are left as they are.
local EDGE = 0.002

local function rectIn(object: GuiObject, content: GuiObject): { number }?
	local x, y = object.Position.X.Scale, object.Position.Y.Scale
	local w, h = object.Size.X.Scale, object.Size.Y.Scale
	local node = object.Parent
	while node and node ~= content do
		if not node:IsA("GuiObject") then
			return nil
		end
		local parent = node :: GuiObject
		if parent.AnchorPoint ~= Vector2.zero or parent.Rotation ~= 0 then
			return nil
		end
		x = parent.Position.X.Scale + x * parent.Size.X.Scale
		y = parent.Position.Y.Scale + y * parent.Size.Y.Scale
		w *= parent.Size.X.Scale
		h *= parent.Size.Y.Scale
		node = parent.Parent
	end
	if node ~= content then
		return nil
	end
	return { x, y, x + w, y + h }
end

local function roundEdges(b: Build, content: GuiObject)
	for _, object in ipairs(content:GetDescendants()) do
		if not (object:IsA("Frame") or object:IsA("ImageLabel")) then
			continue
		end
		local gui = object :: GuiObject
		if gui:FindFirstChildOfClass("UICorner") or gui.AnchorPoint ~= Vector2.zero or gui.Rotation ~= 0 then
			continue
		end
		if gui:IsA("Frame") and gui.BackgroundTransparency >= 1 then
			continue
		end
		local rect = rectIn(gui, content)
		if not rect then
			continue
		end
		local left, top = rect[1] <= EDGE, rect[2] <= EDGE
		local right, bottom = rect[3] >= 1 - EDGE, rect[4] >= 1 - EDGE
		local edges = { left and top, right and top, right and bottom, left and bottom }
		if edges[1] or edges[2] or edges[3] or edges[4] then
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new()
			c.Parent = gui
			table.insert(b.scaled, { kind = "edge", target = c, cqw = 0, edges = edges })
		end
	end
end

-- ---------------------------------------------------------------- building

type Job = {
	host: GuiObject,
	stamp: string,
	key: string,
	mood: string,
	layout: string,
	venue: string?,
	lines: any,
	seconds: number,
	index: number,
	compact: boolean,
}

local function build(job: Job)
	local host = job.host
	local record = mounted[host]
	if not record then
		return
	end
	local opts = record.opts
	local compact, small = job.compact, opts ~= nil and opts.small == true
	local key, mood = job.key, job.mood

	local hostCorner = host:FindFirstChildOfClass("UICorner")
	local rootCorner = if hostCorner then hostCorner.CornerRadius else UDim.new(0.09, 0)
	-- A CanvasGroup costs a texture of its own; list cards use per-corner radii instead where the
	-- client has them (roundEdges), and keep the group where it does not.
	local grouped = not compact and not (small and PER_CORNER)
	local root: GuiObject
	if grouped then
		local group = Instance.new("CanvasGroup")
		group.BackgroundTransparency = 1
		local c = Instance.new("UICorner")
		c.CornerRadius = rootCorner
		c.Parent = group
		root = group
	else
		local frame = Instance.new("Frame")
		frame.BackgroundTransparency = 1
		root = frame
	end
	root.Name = TILE_NAME
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = host.ZIndex
	local content: GuiObject = root
	if not compact then
		local clip = Instance.new("Frame")
		clip.Name = "Content"
		clip.BackgroundTransparency = 1
		clip.BorderSizePixel = 0
		clip.Size = UDim2.fromScale(1, 1)
		clip.ClipsDescendants = true
		clip.ZIndex = host.ZIndex
		local c = Instance.new("UICorner")
		c.CornerRadius = rootCorner
		c.Parent = clip
		clip.Parent = root
		content = clip
	end
	local b: Build = { root = content, scaled = {}, z = host.ZIndex, outer = rootCorner }

	if compact then
		artIn(b, root, key, mood, rootCorner)
	else
		local ctx: Ctx = {
			b = b,
			key = key,
			mood = mood,
			mesh = CoverArt.meshFor(key, mood),
			head = job.lines.headline,
			sub = job.lines.subline,
			kicker = job.lines.kicker,
			venue = job.venue,
			dur = durationText(job.seconds),
			seconds = job.seconds,
			index = job.index,
			host = host,
			track = record.track,
			playlist = record.playlist,
			small = small,
		}
		local ok, err = pcall(builders[job.layout], ctx)
		if not ok then
			warn(string.format("[CoverTile] layout %s failed, drawing artwork only: %s", job.layout, tostring(err)))
			for _, child in content:GetChildren() do
				if not child:IsA("UICorner") then
					child:Destroy()
				end
			end
			b.scaled = {}
			content.BackgroundTransparency = 1
			artIn(b, content, key, mood)
		end
		if not grouped then
			roundEdges(b, content)
		end
	end

	local cleanup = record.cleanup
	local function rescale()
		local width = root.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local outer = b.outer or UDim.new(0.09, 0)
		local outerPx = outer.Scale * width + outer.Offset
		for _, item in ipairs(b.scaled) do
			local px = width * item.cqw / 100
			if item.kind == "text" then
				(item.target :: UITextSizeConstraint).MaxTextSize = math.max(1, math.floor(px + 0.5))
			elseif item.kind == "stroke" then
				(item.target :: UIStroke).Thickness = math.max(1, px)
			elseif item.kind == "corner" then
				(item.target :: UICorner).CornerRadius = UDim.new(0, px)
			elseif item.kind == "inset" then
				local inner = item.target :: UICorner
				local floor = if item.min then width * item.min / 100 else 0
				inner.CornerRadius = UDim.new(0, math.max(floor, outerPx - px))
			elseif item.kind == "insetTop" then
				-- Top corners follow the card, bottom corners keep the floor (per-corner radii).
				local floor = if item.min then width * item.min / 100 else 0
				local inner = item.target :: UICorner
				local top = UDim.new(0, math.max(floor, outerPx - px))
				inner.TopLeftRadius = top
				inner.TopRightRadius = top
				inner.BottomLeftRadius = UDim.new(0, floor)
				inner.BottomRightRadius = UDim.new(0, floor)
			elseif item.kind == "chipFit" then
				local label = item.label :: TextLabel
				local textWidth = label.TextBounds.X
				if textWidth > 0 then
					local chip = item.target :: GuiObject
					local fitted = math.min(textWidth + 2 * px, width * (item.max or 100) / 100)
					chip.Size = UDim2.new(fitted / width, 0, chip.Size.Y.Scale, chip.Size.Y.Offset)
				end
			elseif item.kind == "edge" then
				local edges = item.edges :: { boolean }
				local inner = item.target :: UICorner
				local round, square = UDim.new(0, outerPx), UDim.new()
				inner.TopLeftRadius = if edges[1] then round else square
				inner.TopRightRadius = if edges[2] then round else square
				inner.BottomRightRadius = if edges[3] then round else square
				inner.BottomLeftRadius = if edges[4] then round else square
			end
		end
	end
	table.insert(cleanup, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale))
	-- A label's measured width settles a frame after its text size does.
	for _, item in ipairs(b.scaled) do
		if item.kind == "chipFit" and item.label then
			table.insert(cleanup, item.label:GetPropertyChangedSignal("TextBounds"):Connect(rescale))
		end
	end
	-- Fades of the cover element carry the tile along.
	if root:IsA("CanvasGroup") and host:IsA("ImageLabel") then
		local group = root :: CanvasGroup
		local image = host :: ImageLabel
		group.GroupTransparency = image.ImageTransparency
		table.insert(cleanup, image:GetPropertyChangedSignal("ImageTransparency"):Connect(function()
			group.GroupTransparency = image.ImageTransparency
		end))
	end
	record.pending = nil
	root.Parent = host
	rescale()
end

-- List cards are built in the background, a few per frame within a time budget, newest request
-- first per host; a card whose host changed track or left the screen before its turn is skipped.
local FRAME_BUDGET = 0.004
local queue: { Job } = {}
local draining = false

local function drain()
	draining = true
	task.spawn(function()
		while #queue > 0 do
			local started = os.clock()
			while #queue > 0 and os.clock() - started < FRAME_BUDGET do
				local job = table.remove(queue, 1) :: Job
				local record = mounted[job.host]
				if record and record.pending and record.key == job.stamp and job.host.Parent then
					build(job)
				end
			end
			if #queue > 0 then
				RunService.Heartbeat:Wait()
			end
		end
		draining = false
	end)
end

-- Draws (or keeps) the cover of `track` inside `host`. Idempotent: a repaint with the same track,
-- text, layout and venue changes nothing.
function CoverTile.mount(host: GuiObject, track: any, playlist: any?, config: any, opts: Opts?)
	local compact = opts ~= nil and opts.compact == true
	local name = tostring(track.name or "")
	local creator = if type(track.creator) == "string" then track.creator else nil
	local key = CoverMesh.keyFor(name, creator)
	local mood = CoverMesh.moodFor(key)
	local layout = CoverTile.layoutFor(track)
	local venue = if compact then nil else CoverTextPick.markText(track.cover, experienceName())
	local lines = CoverTextPick.pick(track, venue, nil)
	local seconds = tonumber(track.totalDuration) or 0
	local index = (opts and opts.index) or (CoverMesh.hash(key) % 99 + 1)
	local stamp = table.concat({
		key,
		mood,
		if compact then "compact" else layout,
		lines.headline,
		lines.subline or "",
		lines.kicker or "",
		venue or "",
		tostring(math.floor(seconds)),
		tostring(index),
	}, "\0")

	local record = mounted[host]
	if record and record.key == stamp and (record.pending or findTile(host)) then
		record.track, record.playlist, record.config, record.opts = track, playlist, config, opts
		return
	end
	CoverTile.unmount(host)

	local cleanup: { RBXScriptConnection } = {}
	table.insert(cleanup, host.Destroying:Connect(function()
		CoverTile.unmount(host)
	end))
	mounted[host] = { track = track, playlist = playlist, config = config, opts = opts, key = stamp, cleanup = cleanup, pending = true }
	local job: Job = {
		host = host,
		stamp = stamp,
		key = key,
		mood = mood,
		layout = layout,
		venue = venue,
		lines = lines,
		seconds = seconds,
		index = index,
		compact = compact,
	}
	if opts ~= nil and opts.small == true and not compact then
		table.insert(queue, job)
		if not draining then
			drain()
		end
	else
		build(job)
	end
end

-- Re-draws every mounted tile (the experience's name arrived).
function CoverTile.refreshAll()
	local hosts: { GuiObject } = {}
	for host in pairs(mounted) do
		table.insert(hosts, host)
	end
	for _, host in ipairs(hosts) do
		local record = mounted[host]
		if record and host.Parent then
			record.key = "" -- force a rebuild
			CoverTile.mount(host, record.track, record.playlist, record.config, record.opts)
		end
	end
end

return CoverTile
