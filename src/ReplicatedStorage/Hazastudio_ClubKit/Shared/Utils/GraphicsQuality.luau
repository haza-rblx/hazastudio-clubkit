--!strict
-- Resolves graphics preset bundles, per-field overrides, and effective runtime values.

local Types = require(script.Parent.Parent.Domain.Types)

export type GraphicsPreset = Types.GraphicsPreset
export type ShadowQuality = Types.ShadowQuality
export type WorkspaceVfxMode = "Off" | "Reduced" | "Full"
export type PostProcessingMode = "Minimal" | "Standard" | "Full"
-- 0 = Low, 1 = Balanced, 2 = High (Luau does not allow numeric literal unions)
export type GraphicsTier = number

export type GraphicsBundle = {
	textures: number,
	depthOfField: number,
	hideAllParticles: boolean,
	shadowQuality: ShadowQuality,
	globalShadows: boolean,
	-- Point/Spot/SurfaceLight keep their own Shadows value; false forces every one off.
	lightShadows: boolean,
	-- BasePart.CastShadow keeps its own value; false forces every part off.
	partShadows: boolean,
	-- false detaches SurfaceAppearance from non-avatar parts (its maps are
	-- PluginSecurity, so they cannot be blanked at runtime).
	surfaceAppearance: boolean,
	shadowSoftness: number,
	-- NOT here on purpose: mesh detail. `MeshPart.RenderFidelity` cannot be changed at
	-- run-time — the engine warns "Cannot change SolidModel RenderFidelity during Run-Time"
	-- on EVERY write (measured on PARKLAB 2026-09-12: 40 writes, 40 warnings). The property
	-- value does change, so a census of it looks like success while the renderer keeps the
	-- mesh it tessellated at load: nothing visible happens. Mesh detail is therefore place
	-- data, authored in Studio and saved, like Lighting.Technology.
	workspaceVfxMode: WorkspaceVfxMode,
	postProcessing: PostProcessingMode,
	donationVfxScale: number,
	cinematicExtras: boolean,
}

export type EffectiveGraphics = GraphicsBundle & {
	graphicsPreset: GraphicsPreset,
	graphicsTier: GraphicsTier,
}

export type GraphicsOverrideMap = { [string]: boolean }

local GraphicsQuality = {}

GraphicsQuality.STORED_VERSION = 3

GraphicsQuality.OVERRIDE_FIELDS = {
	"textures",
	"depthOfField",
	"hideAllParticles",
	"shadowQuality",
} :: { string }

local BUNDLES: { [GraphicsPreset]: GraphicsBundle } = {
	Low = {
		-- Low cuts shadows and effects, not the map's look: textures and
		-- SurfaceAppearance stay as built.
		textures = 2,
		depthOfField = 0,
		hideAllParticles = true,
		shadowQuality = "Off",
		globalShadows = false,
		lightShadows = false,
		partShadows = false,
		surfaceAppearance = true,
		shadowSoftness = 0,
		workspaceVfxMode = "Off",
		postProcessing = "Minimal",
		donationVfxScale = 0.25,
		cinematicExtras = false,
	},
	Balanced = {
		textures = 2,
		depthOfField = 0,
		hideAllParticles = false,
		shadowQuality = "Balanced",
		globalShadows = true,
		-- Club lights are the costliest shadow casters; Balanced keeps only the sun.
		lightShadows = false,
		partShadows = true,
		surfaceAppearance = true,
		shadowSoftness = 0.15,
		workspaceVfxMode = "Reduced",
		postProcessing = "Standard",
		donationVfxScale = 0.7,
		cinematicExtras = true,
	},
	High = {
		textures = 2,
		depthOfField = 3,
		hideAllParticles = false,
		-- Declares its own shadow tier. It used to say "Balanced", which made the Shadows
		-- toggle round-trip land a High player on Balanced's softness (the toggle can only
		-- ever store "Balanced", so the fidelity must come from the preset, not that word).
		shadowQuality = "High",
		globalShadows = true,
		lightShadows = true,
		partShadows = true,
		surfaceAppearance = true,
		shadowSoftness = 0.55,
		workspaceVfxMode = "Full",
		postProcessing = "Full",
		donationVfxScale = 1,
		cinematicExtras = true,
	},
}

local TIER_BY_PRESET: { [GraphicsPreset]: GraphicsTier } = {
	Low = 0,
	Balanced = 1,
	High = 2,
}

local function cloneOverrideMap(raw: any): GraphicsOverrideMap
	local result: GraphicsOverrideMap = {}
	if type(raw) ~= "table" then
		return result
	end
	for _, fieldName in ipairs(GraphicsQuality.OVERRIDE_FIELDS) do
		if raw[fieldName] == true then
			result[fieldName] = true
		end
	end
	return result
end

function GraphicsQuality.isOverrideField(field: string): boolean
	for _, name in ipairs(GraphicsQuality.OVERRIDE_FIELDS) do
		if name == field then
			return true
		end
	end
	return false
end

function GraphicsQuality.getBundle(preset: GraphicsPreset): GraphicsBundle
	return table.clone(BUNDLES[preset] or BUNDLES.Balanced)
end

-- A preset name as a buyer might write it in ClubKitConfig, or nil when it is not one.
-- Case and surrounding spaces are forgiven; legacy "Ultra" reads as High.
function GraphicsQuality.resolvePreset(raw: any): GraphicsPreset?
	if type(raw) ~= "string" then
		return nil
	end
	local name = string.lower((string.gsub(raw, "^%s*(.-)%s*$", "%1")))
	if name == "low" then
		return "Low"
	elseif name == "balanced" then
		return "Balanced"
	elseif name == "high" or name == "ultra" then
		return "High"
	end
	return nil
end

function GraphicsQuality.getTier(preset: GraphicsPreset): GraphicsTier
	return TIER_BY_PRESET[preset] or 1
end

--- The preset to actually RENDER on this device. High forces every MeshPart to Precise,
--- which a phone cannot carry, so a phone player who chose High renders at `ceiling`
--- instead. Their stored choice is never rewritten — back on desktop they get High again.
--- A junk ceiling is ignored rather than guessed at, so a typo can never silently
--- downgrade everybody.
function GraphicsQuality.clampPresetForDevice(
	preset: GraphicsPreset,
	isPhone: boolean,
	ceiling: any
): GraphicsPreset
	if not isPhone then
		return preset
	end
	local resolved = GraphicsQuality.resolvePreset(ceiling)
	if not resolved then
		return preset
	end
	if GraphicsQuality.getTier(preset) > GraphicsQuality.getTier(resolved) then
		return resolved
	end
	return preset
end

--- Whether to suggest the player raise their OWN Roblox graphics slider. The kit only ever
--- reads UserGameSettings.SavedQualityLevel — writing it would change a persistent
--- account-wide setting that follows them into other experiences.
--- `savedLevel` is the enum's numeric value: 0 = Automatic (the engine is already choosing
--- per device, so never nag), 1..10 = an explicit level the player picked. Only High asks;
--- Low and Balanced are deliberate downgrades and must stay quiet.
function GraphicsQuality.shouldSuggestQualityBump(
	preset: GraphicsPreset,
	savedLevel: number?,
	belowLevel: number?
): boolean
	if preset ~= "High" then
		return false
	end
	if type(savedLevel) ~= "number" or savedLevel < 1 then
		return false
	end
	local threshold = if type(belowLevel) == "number" and belowLevel > 0 then belowLevel else 8
	return savedLevel < threshold
end

function GraphicsQuality.clearOverrides(): GraphicsOverrideMap
	return {}
end

function GraphicsQuality.markOverride(overrides: GraphicsOverrideMap, field: string): GraphicsOverrideMap
	if not GraphicsQuality.isOverrideField(field) then
		return overrides
	end
	local nextMap = table.clone(overrides)
	nextMap[field] = true
	return nextMap
end

function GraphicsQuality.sanitizeOverrides(raw: any): GraphicsOverrideMap
	return cloneOverrideMap(raw)
end

function GraphicsQuality.cascadePresetToStored(stored: {
	graphicsPreset: GraphicsPreset,
	textures: number,
	depthOfField: number,
	hideAllParticles: boolean,
	shadowQuality: ShadowQuality,
	graphicsOverrides: GraphicsOverrideMap?,
}): ({ graphicsOverrides: GraphicsOverrideMap } & typeof(stored))
	local bundle = GraphicsQuality.getBundle(stored.graphicsPreset)
	local next = table.clone(stored) :: any
	next.textures = bundle.textures
	next.depthOfField = bundle.depthOfField
	next.hideAllParticles = bundle.hideAllParticles
	next.shadowQuality = bundle.shadowQuality
	next.graphicsOverrides = GraphicsQuality.clearOverrides()
	return next
end

function GraphicsQuality.getEffective(stored: {
	graphicsPreset: GraphicsPreset,
	textures: number,
	depthOfField: number,
	hideAllParticles: boolean,
	shadowQuality: ShadowQuality,
	graphicsOverrides: GraphicsOverrideMap?,
}): EffectiveGraphics
	local preset = stored.graphicsPreset
	local bundle = GraphicsQuality.getBundle(preset)
	local overrides = stored.graphicsOverrides or {}

	local function pick<T>(field: string, bundled: T, raw: T): T
		if overrides[field] == true then
			return raw
		end
		return bundled
	end

	local textures = pick("textures", bundle.textures, stored.textures)
	local depthOfField = pick("depthOfField", bundle.depthOfField, stored.depthOfField)
	local hideAllParticles = pick("hideAllParticles", bundle.hideAllParticles, stored.hideAllParticles)
	local shadowQuality = pick("shadowQuality", bundle.shadowQuality, stored.shadowQuality)

	local globalShadows = bundle.globalShadows
	local lightShadows = bundle.lightShadows
	local partShadows = bundle.partShadows
	local shadowSoftness = bundle.shadowSoftness
	if overrides.shadowQuality == true then
		if shadowQuality == "Off" then
			globalShadows = false
			shadowSoftness = 0
		else
			-- Shadows toggled back on: restore the PRESET's own fidelity. The Settings row
			-- is a toggle with valueMap { on = "Balanced", off = "Off" }, so switching
			-- shadows on always stores "Balanced" whatever preset you are on — keying the
			-- fidelity off that stored word silently downgraded a High player to Balanced's
			-- softness, with no way back short of re-picking the preset.
			globalShadows = true
			partShadows = true
			lightShadows = bundle.lightShadows
			shadowSoftness = bundle.shadowSoftness
		end
	elseif preset == "Low" then
		globalShadows = false
		shadowSoftness = 0
	end
	-- Shadows Off means zero shadows on screen (CONTEXT.md), not just the sun.
	if shadowQuality == "Off" then
		globalShadows = false
		lightShadows = false
		partShadows = false
		shadowSoftness = 0
	end

	local surfaceAppearance = if overrides.textures == true then textures > 0 else bundle.surfaceAppearance

	return {
		graphicsPreset = preset,
		graphicsTier = GraphicsQuality.getTier(preset),
		textures = textures,
		depthOfField = depthOfField,
		hideAllParticles = hideAllParticles,
		shadowQuality = shadowQuality,
		globalShadows = globalShadows,
		lightShadows = lightShadows,
		partShadows = partShadows,
		surfaceAppearance = surfaceAppearance,
		shadowSoftness = shadowSoftness,
		workspaceVfxMode = bundle.workspaceVfxMode,
		postProcessing = bundle.postProcessing,
		donationVfxScale = bundle.donationVfxScale,
		cinematicExtras = bundle.cinematicExtras,
	}
end

return GraphicsQuality
