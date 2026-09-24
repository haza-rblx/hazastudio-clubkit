--!strict
-- Shared/Domain/OverheadTemplateResolver.luau
--
-- P4b R0b (ADR 0018): which overhead template the place actually has. Today a known GuiType
-- whose BillboardGui is missing from ReplicatedStorage blanks every nametag (server logs
-- "Template BillboardGui not found", attachGui returns nil). This resolves once at boot:
-- wanted → V6 → V5 → V4 → V3 → V2 → V1, first one present; the chosen template name is
-- published as a ReplicatedStorage attribute so every reader agrees. Pure; spec
-- .tmp/overhead-template-resolver-spec.luau.

export type Variants = { [string]: { templateName: string? } }
export type Present = { [string]: boolean }

-- Documented fallback order, wanted variant first.
local FALLBACK_CHAIN = { "V6", "V5", "V4", "V3", "V2", "V1" }

export type Reason = "wanted" | "fallback" | "unknown_type" | "none"

local OverheadTemplateResolver = {}

OverheadTemplateResolver.FALLBACK_CHAIN = FALLBACK_CHAIN

--- Returns the chosen variant key ("V4", …) and why. `present` maps template names to whether
--- the place has them. Never throws; a nil/empty chain answer is (nil, "none").
function OverheadTemplateResolver.resolve(
	wanted: string?,
	variants: Variants?,
	present: Present?
): (string?, Reason)
	local have = if type(present) == "table" then present :: Present else {}
	local chain: { string } = {}
	if type(wanted) == "string" and wanted ~= "" then
		table.insert(chain, wanted)
	end
	for _, key in ipairs(FALLBACK_CHAIN) do
		if key ~= wanted then
			table.insert(chain, key)
		end
	end

	local knownWanted = type(wanted) == "string" and variants ~= nil and (variants :: Variants)[wanted :: string] ~= nil
	local function templateNameOf(key: string): string?
		local entry = variants and (variants :: Variants)[key]
		if type(entry) == "table" and type((entry :: any).templateName) == "string" then
			return (entry :: any).templateName :: string
		end
		return nil
	end

	local bestKey: string? = nil
	local bestName: string? = nil
	for _, key in ipairs(chain) do
		local name = templateNameOf(key)
		if name and have[name] == true then
			if knownWanted and key == wanted then
				return key, "wanted"
			end
			if bestKey == nil then
				bestKey = key
				bestName = name
			end
		end
	end
	if bestKey ~= nil then
		return bestKey, if knownWanted then "fallback" else "unknown_type"
	end
	return nil, "none"
end

--- The value for the ReplicatedStorage attribute: the chosen template's name (what a reader
--- matches a live BillboardGui against), or nil when nothing resolves.
function OverheadTemplateResolver.attributeValue(wanted: string?, variants: Variants?, present: Present?): string?
	local key = OverheadTemplateResolver.resolve(wanted, variants, present)
	local entry = key and variants and (variants :: Variants)[key :: string]
	if type(entry) == "table" and type((entry :: any).templateName) == "string" then
		return (entry :: any).templateName :: string
	end
	return nil
end

return OverheadTemplateResolver
