--!strict
-- OverheadLayerPolicy — pure reader for the tri-state overhead layer / badge config.
--
-- Why this exists: ClubKitConfig.Overhead.DefaultLayers / DefaultBadges started life as one
-- boolean per key, meaning a *default* — the Settings menu could always switch a layer back
-- on. Buyers also need the other thing: a layer that is simply not part of their venue, off
-- for everyone, with its Settings row gone rather than sitting there doing nothing. Rather
-- than a second table to keep in agreement with the first, one value carries three states:
--   true    -> starts visible
--   false   -> starts hidden, the player may switch it back on   (the original meaning, kept)
--   "off"   -> off for everyone, always; the Settings row is hidden too   (also "disabled")
-- Case and surrounding spaces are forgiven, as Graphics.DefaultPreset already does. Junk
-- keeps the kit's own default and is reported through invalidValueKeys, so a typo can flip a
-- real layer but can never invent one, blank a table, or quietly lock a layer.
--
-- A hard-off is enforced rather than merely seeded, so it reaches players whose stored record
-- predates the config change (OverheadDomain.buildPayload runs `enforce` on both public maps).
-- Stored values are never rewritten, so switching the layer back on restores each player
-- exactly as they had it.
--
-- Pure: no Roblox globals, and no require of Config — so it is unit-testable headless
-- (.tmp/overhead-layer-lock-spec.luau) and safe on both server and client. ConfigBootstrap
-- derives Config.Overhead.DISABLED_LAYERS / DISABLED_BADGES with disabledSet, passing the
-- engine's own DEFAULT_*_VISIBLE table as the known-key set so there is no second key list
-- to drift. Every render and Settings site then asks isDisabled.

local OverheadLayerPolicy = {}

export type Classification = "enabled" | "default-off" | "disabled" | "invalid"
--- Any table whose KEYS are the layer/badge names (values ignored), e.g. DEFAULT_LAYER_VISIBLE.
export type KeyTable = { [string]: any }
export type DisabledSet = { [string]: true }

local DISABLED_WORDS: { [string]: true } = {
	off = true,
	disabled = true,
}

--- What the buyer wrote for one layer/badge key. "invalid" covers nil, so callers that care
--- about "absent" vs "junk" must check for nil themselves (invalidValueKeys does).
function OverheadLayerPolicy.classify(value: any): Classification
	-- Booleans by identity: a string "false" is junk, not a boolean, the same rule
	-- CustomTitle.QuotaEnabled follows.
	if value == true then
		return "enabled"
	end
	if value == false then
		return "default-off"
	end
	if type(value) == "string" then
		local trimmed = string.match(value :: string, "^%s*(.-)%s*$") or ""
		if DISABLED_WORDS[string.lower(trimmed)] then
			return "disabled"
		end
	end
	return "invalid"
end

--- The boolean that seeds a player's first stored record. A hard-off key seeds hidden too, so
--- stored data agrees with what renders; junk keeps the kit's own value in both directions.
function OverheadLayerPolicy.defaultVisible(value: any, fallback: boolean): boolean
	local classification = OverheadLayerPolicy.classify(value)
	if classification == "enabled" then
		return true
	end
	if classification == "default-off" or classification == "disabled" then
		return false
	end
	return fallback
end

--- The keys the buyer switched off for everyone. Known keys only.
function OverheadLayerPolicy.disabledSet(buyerMap: any, knownKeys: KeyTable): DisabledSet
	local result: DisabledSet = {}
	if type(buyerMap) ~= "table" then
		return result
	end
	for key in pairs(knownKeys) do
		if OverheadLayerPolicy.classify((buyerMap :: KeyTable)[key]) == "disabled" then
			result[key] = true
		end
	end
	return result
end

--- Nil-safe: an engine Config without the projected set must read as "nothing disabled",
--- so an older Config.luau cannot make every layer vanish.
function OverheadLayerPolicy.isDisabled(disabled: DisabledSet?, key: string): boolean
	if type(disabled) ~= "table" then
		return false
	end
	return (disabled :: DisabledSet)[key] == true
end

--- Force every hard-off key false in a visibility map, without mutating the caller's table.
--- Keys absent from the map stay absent — enforcement hides layers, it does not invent them.
function OverheadLayerPolicy.enforce(
	map: { [string]: boolean }?,
	disabled: DisabledSet?
): { [string]: boolean }
	if type(map) ~= "table" then
		return {}
	end
	local result = table.clone(map :: { [string]: boolean })
	if type(disabled) ~= "table" then
		return result
	end
	for key in pairs(disabled :: DisabledSet) do
		if result[key] ~= nil then
			result[key] = false
		end
	end
	return result
end

--- Known keys carrying a value that is neither boolean nor an off-word, sorted so the
--- warning ConfigBootstrap prints is deterministic. Absent keys are not reported.
function OverheadLayerPolicy.invalidValueKeys(buyerMap: any, knownKeys: KeyTable): { string }
	local keys: { string } = {}
	if type(buyerMap) ~= "table" then
		return keys
	end
	for key in pairs(knownKeys) do
		local value = (buyerMap :: KeyTable)[key]
		if value ~= nil and OverheadLayerPolicy.classify(value) == "invalid" then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	return keys
end

return OverheadLayerPolicy
