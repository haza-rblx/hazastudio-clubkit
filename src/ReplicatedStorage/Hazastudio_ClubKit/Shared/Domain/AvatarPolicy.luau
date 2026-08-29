--!strict
-- Pure rules for AvatarGuard (ADR 0008 Layer 2c). The guard describes each Accessory as
-- plain numbers (handle size, effect instances, particle emitters); this module decides
-- what to remove, strip or cap. No Roblox globals.

local AvatarPolicy = {}

export type EffectDesc = { class: string, width: number?, range: number?, brightness: number? }
export type ParticleDesc = { rate: number, size: number, lifetime: number }
export type AccessoryDesc = { size: { number }, effects: { EffectDesc }, particles: { ParticleDesc } }

export type Judgement = {
	remove: boolean,
	reason: string?,
	effectCaps: { { index: number, width: number?, range: number?, brightness: number? } },
	stripEffects: { { index: number, kind: string } },
	particleCaps: { { index: number, rate: number, size: number, lifetime: number } },
}

AvatarPolicy.DEFAULTS = {
	MAX_ACCESSORY_STUDS = 10,
	MAX_CHARACTER_HEIGHT = 14,
	MAX_CHARACTER_WIDTH = 10,
	MAX_ACCESSORIES = 30,
	EFFECTS = "cap", -- "cap" | "strip"
	BEAM_MAX_WIDTH = 2,
	LIGHT_MAX_RANGE = 12,
	LIGHT_MAX_BRIGHTNESS = 2,
	PARTICLE_MAX_RATE = 20,
	PARTICLE_MAX_SIZE = 2,
	PARTICLE_MAX_LIFETIME = 3,
	PARTICLE_REMOVE_RATE = 200,
}

local BEAM_LIKE: { [string]: boolean } = { Beam = true, Trail = true }
local LIGHT_LIKE: { [string]: boolean } = { PointLight = true, SpotLight = true, SurfaceLight = true }

local function num(cfg: any, key: string): number
	local v = if type(cfg) == "table" then cfg[key] else nil
	return if type(v) == "number" then v else (AvatarPolicy.DEFAULTS :: any)[key]
end

local function str(cfg: any, key: string): string
	local v = if type(cfg) == "table" then cfg[key] else nil
	return if type(v) == "string" then v else (AvatarPolicy.DEFAULTS :: any)[key]
end

function AvatarPolicy.judgeAccessory(desc: AccessoryDesc, cfg: any): Judgement
	local out: Judgement = { remove = false, reason = nil, effectCaps = {}, stripEffects = {}, particleCaps = {} }

	local cap = num(cfg, "MAX_ACCESSORY_STUDS")
	for _, axis in ipairs(desc.size) do
		if axis > cap then
			out.remove = true
			out.reason = "oversized"
			return out
		end
	end

	local mode = str(cfg, "EFFECTS")
	for index, effect in ipairs(desc.effects) do
		if mode == "strip" then
			table.insert(out.stripEffects, { index = index, kind = "effect" })
		elseif BEAM_LIKE[effect.class] then
			local maxWidth = num(cfg, "BEAM_MAX_WIDTH")
			if (effect.width or 0) > maxWidth then
				table.insert(out.effectCaps, { index = index, width = maxWidth })
			end
		elseif LIGHT_LIKE[effect.class] then
			local maxRange, maxBright = num(cfg, "LIGHT_MAX_RANGE"), num(cfg, "LIGHT_MAX_BRIGHTNESS")
			if (effect.range or 0) > maxRange or (effect.brightness or 0) > maxBright then
				table.insert(out.effectCaps, {
					index = index,
					range = math.min(effect.range or 0, maxRange),
					brightness = math.min(effect.brightness or 0, maxBright),
				})
			end
		end
		-- Fire / Smoke / Sparkles in cap mode: left alone (bounded by the engine already).
	end

	local maxRate, maxSize, maxLife = num(cfg, "PARTICLE_MAX_RATE"), num(cfg, "PARTICLE_MAX_SIZE"), num(cfg, "PARTICLE_MAX_LIFETIME")
	local removeRate = num(cfg, "PARTICLE_REMOVE_RATE")
	for index, p in ipairs(desc.particles) do
		if p.rate > removeRate then
			table.insert(out.stripEffects, { index = index, kind = "particle" })
		elseif p.rate > maxRate or p.size > maxSize or p.lifetime > maxLife then
			table.insert(out.particleCaps, {
				index = index,
				rate = math.min(p.rate, maxRate),
				size = math.min(p.size, maxSize),
				lifetime = math.min(p.lifetime, maxLife),
			})
		end
	end

	return out
end

function AvatarPolicy.volume(size: { number }): number
	return (size[1] or 0) * (size[2] or 0) * (size[3] or 0)
end

function AvatarPolicy.pickLargest<T>(list: { T & { size: { number } } }): T?
	local best: T? = nil
	local bestVolume = -1
	for _, entry in ipairs(list) do
		local v = AvatarPolicy.volume((entry :: any).size)
		if v > bestVolume then
			bestVolume = v
			best = entry
		end
	end
	return best
end

function AvatarPolicy.characterTooBig(extents: { number }, cfg: any): boolean
	local maxH, maxW = num(cfg, "MAX_CHARACTER_HEIGHT"), num(cfg, "MAX_CHARACTER_WIDTH")
	return (extents[2] or 0) > maxH or (extents[1] or 0) > maxW or (extents[3] or 0) > maxW
end

return AvatarPolicy
