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
	shadowSoftness: number,
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
		-- Keep textures enabled so low preset remains visually usable.
		textures = 2,
		depthOfField = 0,
		hideAllParticles = true,
		shadowQuality = "Off",
		globalShadows = false,
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
		shadowQuality = "Balanced",
		globalShadows = true,
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

function GraphicsQuality.getTier(preset: GraphicsPreset): GraphicsTier
	return TIER_BY_PRESET[preset] or 1
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
	local shadowSoftness = bundle.shadowSoftness
	if overrides.shadowQuality == true then
		if shadowQuality == "Off" then
			globalShadows = false
			shadowSoftness = 0
		else
			globalShadows = true
			if shadowQuality == "High" then
				shadowSoftness = 0.55
			else
				shadowSoftness = 0.15
			end
		end
	elseif preset == "Low" then
		globalShadows = false
		shadowSoftness = 0
	end

	return {
		graphicsPreset = preset,
		graphicsTier = GraphicsQuality.getTier(preset),
		textures = textures,
		depthOfField = depthOfField,
		hideAllParticles = hideAllParticles,
		shadowQuality = shadowQuality,
		globalShadows = globalShadows,
		shadowSoftness = shadowSoftness,
		workspaceVfxMode = bundle.workspaceVfxMode,
		postProcessing = bundle.postProcessing,
		donationVfxScale = bundle.donationVfxScale,
		cinematicExtras = bundle.cinematicExtras,
	}
end

return GraphicsQuality
