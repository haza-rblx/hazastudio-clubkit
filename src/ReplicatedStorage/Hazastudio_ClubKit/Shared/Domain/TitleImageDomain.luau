--!strict
-- Shared/Domain/TitleImageDomain.luau
-- Asset ids for the overhead image title (the `02-AddOnCustomImageBadge` row in
-- OverheadGUIMainTemplateV5), plus the place-global registry of images that have
-- been assigned before, so an admin can re-pick one without retyping the id.
--
-- Pure: no Roblox services, no Config require — callers pass their own limits in.
--
-- Accepted shapes deliberately match the kit's existing `normalizeImage`
-- (StickerService / StickerController): bare digits, or `rbxassetid://<digits>`.
-- Library URLs are NOT accepted here either; one path quietly taking more than
-- the other is how "but it worked in the sticker panel" bugs start.

local TitleImageDomain = {}

local PREFIX = "rbxassetid://"
-- Audit 2026-08-29 H5 asks for a digit cap on image input. 19 digits is the
-- widest a real asset id can be (int64), so this rejects pasted junk without
-- ever rejecting a genuine id.
local MAX_ID_DIGITS = 19
-- Used when the caller passes no registry limit.
local FALLBACK_REGISTRY_MAX = 60

TitleImageDomain.PREFIX = PREFIX
TitleImageDomain.MAX_ID_DIGITS = MAX_ID_DIGITS

local function digitsOf(value: any): string?
	if type(value) ~= "string" then
		return nil
	end
	local trimmed = value:match("^%s*(.-)%s*$") or ""
	local digits = trimmed:match("^(%d+)$") or trimmed:match("^rbxassetid://(%d+)$")
	if not digits then
		return nil
	end
	if #digits > MAX_ID_DIGITS then
		return nil
	end
	-- "0", "000" and friends are placeholders, not assets.
	if digits:match("^0+$") then
		return nil
	end
	return digits
end

-- Canonical `rbxassetid://<digits>`, or "" when the value cannot be one.
function TitleImageDomain.normalizeAssetId(value: any): string
	local digits = digitsOf(value)
	return if digits then PREFIX .. digits else ""
end

local function resolveMax(max: any): number
	local raw = tonumber(max)
	if raw == nil then
		return FALLBACK_REGISTRY_MAX
	end
	return math.max(1, math.floor(raw))
end

-- Clean a registry list read back from DataStore: drop anything that is not a
-- usable id, collapse duplicates to their first (newest) position, cap the
-- length. Order is preserved, so index 1 stays the most recent.
function TitleImageDomain.sanitizeList(raw: any, max: any): { string }
	local limit = resolveMax(max)
	local cleaned: { string } = {}
	if type(raw) ~= "table" then
		return cleaned
	end
	local seen: { [string]: true } = {}
	for _, entry in ipairs(raw) do
		local id = TitleImageDomain.normalizeAssetId(entry)
		if id ~= "" and not seen[id] then
			seen[id] = true
			table.insert(cleaned, id)
			if #cleaned >= limit then
				break
			end
		end
	end
	return cleaned
end

-- The registry to store after an image is assigned: newest first, no duplicates,
-- capped. An id that cannot be normalized leaves the list untouched rather than
-- writing an entry nobody can render.
function TitleImageDomain.remember(list: any, assetId: any, max: any): { string }
	local limit = resolveMax(max)
	local id = TitleImageDomain.normalizeAssetId(assetId)
	local cleaned = TitleImageDomain.sanitizeList(list, limit)
	if id == "" then
		return cleaned
	end

	local next_: { string } = { id }
	for _, existing in ipairs(cleaned) do
		if existing ~= id and #next_ < limit then
			table.insert(next_, existing)
		end
	end
	return next_
end

return TitleImageDomain
