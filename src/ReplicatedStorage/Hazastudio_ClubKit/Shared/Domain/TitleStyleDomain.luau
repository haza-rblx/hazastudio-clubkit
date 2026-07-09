--!strict
-- Pure helpers for generated admin title styles.
local TitleStyleDomain = {}
export type TitleSizeKey = "S" | "M" | "L" | "XL" | "XXL"
export type TitleStyleData = {
	label: string,
	family: string,
	animMode: string,
	animSpeed: number,
	bgColors: {{number}},
	textColors: {{number}},
	bgRotation: number,
	textRotation: number,
	strokeColor: {number},
}
local TITLE_SIZES: {[string]: true} = {
	S = true,
	M = true,
	L = true,
	XL = true,
	XXL = true,
}
local FAMILIES = {
	{
		label = "PANSEXUAL ORIGINAL",
		family = "pansexual_original",
		animMode = "scan",
		bg = {
			{ 0, 255, 33, 140 },
			{ 0.27, 255, 90, 170 },
			{ 0.55, 255, 216, 0 },
			{ 0.83, 144, 232, 255 },
			{ 1, 26, 179, 255 },
		},
		text = {
			{ 0, 255, 210, 232 },
			{ 0.5, 255, 244, 196 },
			{ 1, 186, 232, 255 },
		},
		stroke = { 255, 150, 206 },
	},
	{
		label = "SUNSET VIBES",
		family = "sunset_vibes",
		animMode = "sheen",
		bg = {
			{ 0, 255, 107, 53 },
			{ 0.27, 255, 127, 84 },
			{ 0.55, 255, 142, 114 },
			{ 0.83, 230, 124, 203 },
			{ 1, 168, 85, 247 },
		},
		text = {
			{ 0, 255, 224, 210 },
			{ 0.5, 255, 248, 241 },
			{ 1, 223, 204, 255 },
		},
		stroke = { 255, 154, 126 },
	},
	{
		label = "TROPICAL FRESH",
		family = "tropical_fresh",
		animMode = "drift",
		bg = {
			{ 0, 132, 204, 22 },
			{ 0.27, 95, 217, 165 },
			{ 0.55, 6, 182, 212 },
			{ 0.83, 122, 148, 232 },
			{ 1, 236, 72, 153 },
		},
		text = {
			{ 0, 212, 255, 222 },
			{ 0.5, 244, 255, 250 },
			{ 1, 255, 206, 232 },
		},
		stroke = { 96, 220, 184 },
	},
	{
		label = "OCEAN BREEZE",
		family = "ocean_breeze",
		animMode = "pulse",
		bg = {
			{ 0, 20, 184, 166 },
			{ 0.27, 38, 203, 207 },
			{ 0.55, 56, 189, 248 },
			{ 0.83, 132, 171, 250 },
			{ 1, 192, 132, 252 },
		},
		text = {
			{ 0, 206, 244, 255 },
			{ 0.5, 243, 255, 255 },
			{ 1, 233, 214, 255 },
		},
		stroke = { 141, 204, 255 },
	},
	{
		label = "CANDY POP",
		family = "candy_pop",
		animMode = "bounce",
		bg = {
			{ 0, 244, 114, 182 },
			{ 0.27, 249, 168, 205 },
			{ 0.55, 251, 191, 36 },
			{ 0.83, 149, 164, 226 },
			{ 1, 59, 130, 246 },
		},
		text = {
			{ 0, 255, 220, 244 },
			{ 0.5, 255, 247, 212 },
			{ 1, 214, 226, 255 },
		},
		stroke = { 246, 176, 208 },
	},
	{
		label = "BERRY BLAST",
		family = "berry_blast",
		animMode = "scan",
		bg = {
			{ 0, 220, 38, 38 },
			{ 0.2, 249, 115, 22 },
			{ 0.4, 250, 204, 21 },
			{ 0.6, 163, 230, 53 },
			{ 0.8, 34, 197, 94 },
			{ 1, 14, 165, 233 },
		},
		text = {
			{ 0, 255, 206, 216 },
			{ 0.45, 255, 245, 194 },
			{ 1, 202, 233, 255 },
		},
		stroke = { 224, 132, 172 },
	},
	{
		label = "NEON DREAMS",
		family = "neon_dreams",
		animMode = "prism",
		bg = {
			{ 0, 239, 68, 68 },
			{ 0.2, 245, 158, 11 },
			{ 0.4, 16, 185, 129 },
			{ 0.6, 6, 182, 212 },
			{ 0.8, 139, 92, 246 },
			{ 1, 236, 72, 153 },
		},
		text = {
			{ 0, 255, 215, 226 },
			{ 0.5, 246, 255, 255 },
			{ 1, 235, 201, 255 },
		},
		stroke = { 203, 150, 255 },
	},
	{
		label = "PEACHY KEEN",
		family = "peachy_keen",
		animMode = "sheen",
		bg = {
			{ 0, 251, 146, 60 },
			{ 0.2, 253, 224, 71 },
			{ 0.4, 252, 165, 165 },
			{ 0.6, 249, 168, 212 },
			{ 0.8, 196, 181, 253 },
			{ 1, 167, 243, 208 },
		},
		text = {
			{ 0, 255, 234, 220 },
			{ 0.5, 255, 250, 236 },
			{ 1, 223, 247, 238 },
		},
		stroke = { 255, 198, 172 },
	},
	{
		label = "ELECTRIC AURORA",
		family = "electric_aurora",
		animMode = "drift",
		bg = {
			{ 0, 6, 182, 212 },
			{ 0.2, 14, 165, 233 },
			{ 0.4, 99, 102, 241 },
			{ 0.6, 168, 85, 247 },
			{ 0.8, 236, 72, 153 },
			{ 1, 244, 63, 94 },
		},
		text = {
			{ 0, 200, 236, 255 },
			{ 0.5, 245, 255, 255 },
			{ 1, 255, 208, 236 },
		},
		stroke = { 176, 151, 255 },
	},
	{
		label = "MINT LEMONADE",
		family = "mint_lemonade",
		animMode = "bounce",
		bg = {
			{ 0, 110, 231, 183 },
			{ 0.2, 52, 211, 153 },
			{ 0.4, 253, 230, 138 },
			{ 0.6, 252, 211, 77 },
			{ 0.8, 252, 165, 165 },
			{ 1, 253, 186, 116 },
		},
		text = {
			{ 0, 224, 255, 238 },
			{ 0.5, 255, 251, 210 },
			{ 1, 255, 228, 220 },
		},
		stroke = { 164, 229, 182 },
	},
}
local function clonePoints(points: {{number}}): {{number}}
	local result = {}
	for _, point in ipairs(points) do
		table.insert(result, table.clone(point))
	end
	return result
end
local function makeRng(seed: number): () -> number
	local state = math.floor(seed) % 2147483647
	if state <= 0 then
		state = 13579
	end
	return function(): number
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end
local function clamp(value: number, minValue: number, maxValue: number): number
	return math.max(minValue, math.min(maxValue, value))
end
local COLOR_JITTER_RANGE = 10

local function jitterColor(color: {number}, rng: () -> number): {number}
	return {
		clamp(math.floor(color[1] + (rng() - 0.5) * COLOR_JITTER_RANGE + 0.5), 0, 255),
		clamp(math.floor(color[2] + (rng() - 0.5) * COLOR_JITTER_RANGE + 0.5), 0, 255),
		clamp(math.floor(color[3] + (rng() - 0.5) * COLOR_JITTER_RANGE + 0.5), 0, 255),
	}
end
local function jitterPoints(points: {{number}}, rng: () -> number): {{number}}
	local result = {}
	for _, point in ipairs(points) do
		local rgb = jitterColor({ point[2], point[3], point[4] }, rng)
		table.insert(result, { point[1], rgb[1], rgb[2], rgb[3] })
	end
	return result
end
function TitleStyleDomain.isValidTitleSize(value: string): boolean
	return TITLE_SIZES[value] == true
end
function TitleStyleDomain.sanitizeStyle(raw: any): TitleStyleData?
	if type(raw) ~= "table" then
		return nil
	end
	local label = type(raw.label) == "string" and raw.label or nil
	local family = type(raw.family) == "string" and raw.family or nil
	local animMode = type(raw.animMode) == "string" and raw.animMode or nil
	local animSpeed = type(raw.animSpeed) == "number" and raw.animSpeed or nil
	local bgColors = type(raw.bgColors) == "table" and raw.bgColors or nil
	local textColors = type(raw.textColors) == "table" and raw.textColors or nil
	local bgRotation = type(raw.bgRotation) == "number" and raw.bgRotation or nil
	local textRotation = type(raw.textRotation) == "number" and raw.textRotation or nil
	local strokeColor = type(raw.strokeColor) == "table" and raw.strokeColor or nil
	if not label or not family or not animMode or not animSpeed or not bgColors or not textColors or not bgRotation or not textRotation or not strokeColor then
		return nil
	end
	-- Hard limit color points - cegah memory exhaustion dari payload besar
	local MAX_COLOR_POINTS = 10
	local function sanitizePoints(points: any): {{number}}?
		local sanitized = {}
		local count = 0
		for _, point in ipairs(points) do
			count += 1
			if count > MAX_COLOR_POINTS then
				return nil  -- Tolak jika terlalu banyak points
			end
			if type(point) ~= "table" or type(point[1]) ~= "number" or type(point[2]) ~= "number" or type(point[3]) ~= "number" or type(point[4]) ~= "number" then
				return nil
			end
			table.insert(sanitized, {
				clamp(point[1], 0, 1),
				clamp(math.floor(point[2] + 0.5), 0, 255),
				clamp(math.floor(point[3] + 0.5), 0, 255),
				clamp(math.floor(point[4] + 0.5), 0, 255),
			})
		end
		return #sanitized >= 2 and sanitized or nil
	end
	local sanitizedBg = sanitizePoints(bgColors)
	local sanitizedText = sanitizePoints(textColors)
	if not sanitizedBg or not sanitizedText then
		return nil
	end
	if type(strokeColor[1]) ~= "number" or type(strokeColor[2]) ~= "number" or type(strokeColor[3]) ~= "number" then
		return nil
	end
	return {
		label = string.sub(label, 1, 32),
		family = string.sub(family, 1, 32),
		animMode = string.sub(animMode, 1, 24),
		animSpeed = clamp(animSpeed, 0.4, 3),
		bgColors = sanitizedBg,
		textColors = sanitizedText,
		bgRotation = clamp(bgRotation, -180, 180),
		textRotation = clamp(textRotation, -180, 180),
		strokeColor = {
			clamp(math.floor(strokeColor[1] + 0.5), 0, 255),
			clamp(math.floor(strokeColor[2] + 0.5), 0, 255),
			clamp(math.floor(strokeColor[3] + 0.5), 0, 255),
		},
	}
end
function TitleStyleDomain.generateBatch(seed: number, count: number?): {TitleStyleData}
	local total = count or 10
	local rng = makeRng(seed)
	local families = table.clone(FAMILIES)
	for index = #families, 2, -1 do
		local swapIndex = math.floor(rng() * index) + 1
		families[index], families[swapIndex] = families[swapIndex], families[index]
	end
	local batch = {}
	for index = 1, total do
		local family = families[((index - 1) % #families) + 1]
		local bgRotation = math.floor(rng() * 6) * 15
		local textRotation = math.floor(rng() * 6) * 10
		table.insert(batch, {
			label = family.label,
			family = family.family,
			animMode = family.animMode,
			animSpeed = 0.8 + rng() * 1.1,
			bgColors = jitterPoints(clonePoints(family.bg), rng),
			textColors = jitterPoints(clonePoints(family.text), rng),
			bgRotation = bgRotation,
			textRotation = textRotation,
			strokeColor = jitterColor(table.clone(family.stroke), rng),
		})
	end
	return batch
end
return TitleStyleDomain
