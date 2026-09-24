--!strict
-- GENERATED 2026-09-19 from ReplicatedStorage.WorldEffects (Smite4 + Smite3) in THE BASIC TEST.
-- Do not hand-edit the tables below; regenerate instead (see "Regenerating" at the bottom).
--
-- WHY THIS FILE EXISTS. `WorldEffects` is not in the repo — Rojo maps `src/ReplicatedStorage`
-- and the folder is not under it, so the models live only in the place and the packaged .rbxm.
-- ADR 0013 therefore prunes `Smite3` at runtime and repaints the `Smite4` clone instead. Once
-- `Smite3` stops being replicated this mapping cannot be re-derived from a buyer place, so it is
-- captured here as data before that lands.
--
-- WHAT A ROLE IS. `Smite4` is not a hue rotation of `Smite3` — measured shifts run +135 deg to
-- +300 deg and one source colour lands on three different targets, so it was hand-painted. But
-- grouping nodes by the *pair* (Smite4 colour, Smite3 colour) partitions all 75 coloured nodes
-- into 23 roles with nothing left over. Because those roles are how the pack's author actually
-- grouped the work, a palette per role reproduces BOTH looks exactly rather than approximately.
--
-- KEY FORMAT: "<path>#<ClassName>", path relative to the model root, segments separated by "/".
-- A segment that is not unique among its siblings carries a "~n" ordinal in `GetChildren()`
-- order, which `Clone()` preserves. The ordinal is needed at EVERY segment, not just the leaf:
-- a single `DiamondHammer/Handle` holds five `DiamondCenter` parts, and their `Flare` emitters
-- are three different greens in the nature palette. Keying on the leaf alone silently collapsed
-- them to one and lost two colours.
--
-- Verified at generation: 75 coloured nodes, 0 duplicate keys, 0 nodes missing a `Smite3`
-- partner.

local ThemeData = {}

-- A colour stop: { time, r, g, b } with 0-255 channels. `PointLight` roles carry a single stop.
export type Stop = { number }
export type Palette = { [number]: { Stop } }

ThemeData.ROLE_COUNT = 23

--- Which role paints each coloured node of the `Smite4` model.
local ROLE_BY_NODE: { [string]: number } = {
	["DiamondHammer/Effects/Beams/FlameEffect1#Beam"] = 1,
	["DiamondHammer/Effects/Beams/FlameEffect10#Beam"] = 1,
	["DiamondHammer/Effects/Beams/FlameEffect11#Beam"] = 1,
	["DiamondHammer/Effects/Beams/FlameEffect12#Beam"] = 1,
	["DiamondHammer/Effects/Beams/FlameEffect2#Beam"] = 1,
	["DiamondHammer/Effects/Beams/FlameEffect3#Beam"] = 1,
	["DiamondHammer/Effects/Beams/FlameEffect4#Beam"] = 1,
	["DiamondHammer/Effects/Beams/FlameEffect5#Beam"] = 1,
	["DiamondHammer/Effects/Beams/FlameEffect6#Beam"] = 1,
	["DiamondHammer/Effects/Beams/FlameEffect7#Beam"] = 1,
	["DiamondHammer/Effects/Beams/FlameEffect8#Beam"] = 1,
	["DiamondHammer/Effects/Beams/FlameEffect9#Beam"] = 1,
	["DiamondHammer/Effects/Trails/HandleTrail#Trail"] = 2,
	["DiamondHammer/Effects/Trails/InnerTrail#Trail"] = 3,
	["DiamondHammer/Effects/Trails/OuterTrail1#Trail"] = 3,
	["DiamondHammer/Effects/Trails/OuterTrail2#Trail"] = 3,
	["DiamondHammer/Effects/Trails/OuterTrail3#Trail"] = 3,
	["DiamondHammer/Effects/Trails/OuterTrail4#Trail"] = 3,
	["DiamondHammer/Effects/Trails/OuterTrail5#Trail"] = 3,
	["DiamondHammer/Effects/Trails/OuterTrail6#Trail"] = 3,
	["DiamondHammer/Handle/BaseFrontOffset/Shockwave#ParticleEmitter"] = 4,
	["DiamondHammer/Handle/BigDiamondCenter~1/Flare#ParticleEmitter"] = 5,
	["DiamondHammer/Handle/BigDiamondCenter~2/Flare#ParticleEmitter"] = 5,
	["DiamondHammer/Handle/DiamondCenter~1/Flare#ParticleEmitter"] = 5,
	["DiamondHammer/Handle/DiamondCenter~2/Flare#ParticleEmitter"] = 5,
	["DiamondHammer/Handle/DiamondCenter~3/Flare#ParticleEmitter"] = 5,
	["DiamondHammer/Handle/DiamondCenter~4/Flare#ParticleEmitter"] = 6,
	["DiamondHammer/Handle/DiamondCenter~5/Flare#ParticleEmitter"] = 7,
	["DiamondHammer/Handle/Fire~1#ParticleEmitter"] = 5,
	["DiamondHammer/Handle/Fire~2#ParticleEmitter"] = 5,
	["DiamondHammer/Handle/HammerBase/Flames#ParticleEmitter"] = 5,
	["DiamondHammer/Handle/HammerBaseOutline/Appearance#ParticleEmitter"] = 5,
	["DiamondHammer/Handle/HammerBaseOutline/Sparkles#ParticleEmitter"] = 5,
	["DiamondHammer/Handle/HammerHandleBase/Appearance#ParticleEmitter"] = 8,
	["DiamondHammer/Handle/MainDiamondCenter/ChargeGlow#ParticleEmitter"] = 9,
	["DiamondHammer/Handle/MainDiamondCenter/ChargeRays#ParticleEmitter"] = 5,
	["DiamondHammer/Handle/MainDiamondCenter/Flare#ParticleEmitter"] = 5,
	["DiamondHammer/Handle/MainDiamondCenter/Shockwave#ParticleEmitter"] = 5,
	["Head/LeftEyeAttachment/Flare#ParticleEmitter"] = 10,
	["Head/LeftEyeAttachment/FlareFlash#ParticleEmitter"] = 11,
	["Head/RightEyeAttachment/Flare#ParticleEmitter"] = 12,
	["Head/RightEyeAttachment/FlareFlash#ParticleEmitter"] = 13,
	["Objects/Ambiance/InnerStreaks#ParticleEmitter"] = 5,
	["Objects/Ambiance/OuterStreaks#ParticleEmitter"] = 5,
	["Objects/FloorAmbiance/Ashes#ParticleEmitter"] = 5,
	["Objects/FloorAmbiance/BigFlames#ParticleEmitter"] = 5,
	["Objects/FloorAmbiance/FlameSparks#ParticleEmitter"] = 5,
	["Objects/FloorAmbiance/Flames~1#ParticleEmitter"] = 5,
	["Objects/FloorAmbiance/Flames~2#ParticleEmitter"] = 5,
	["Objects/FloorAmbiance/Smoke#ParticleEmitter"] = 5,
	["Objects/FloorAmbiance/Sparks#ParticleEmitter"] = 5,
	["Objects/ImpactVisuals/EmitPoint/Impact_FractalBurst#ParticleEmitter"] = 14,
	["Objects/ImpactVisuals/EmitPoint/Impact_RaysBurst#ParticleEmitter"] = 14,
	["Objects/ImpactVisuals/EmitPoint/Impact_Shockwave#ParticleEmitter"] = 1,
	["Objects/ImpactVisuals/EmitPoint/Impact_Spark1#ParticleEmitter"] = 15,
	["Objects/ImpactVisuals/EmitPoint/Impact_Spark2#ParticleEmitter"] = 16,
	["Objects/ImpactVisuals/EmitPoint/Impact_Spark3#ParticleEmitter"] = 16,
	["Objects/ImpactVisuals/EmitPoint/Impact_SparkleExplosion#ParticleEmitter"] = 16,
	["Objects/ImpactVisuals/EmitPoint/SparkleExplosion#ParticleEmitter"] = 16,
	["Objects/ImpactVisuals/EmitPoint/Sparks#ParticleEmitter"] = 17,
	["Objects/Meteor/EmitPoint/Explosion_Dust#ParticleEmitter"] = 18,
	["Objects/Meteor/EmitPoint/Explosion_Flames#ParticleEmitter"] = 8,
	["Objects/Meteor/EmitPoint/Explosion_Shockwave#ParticleEmitter"] = 19,
	["Objects/Meteor/EmitPoint/Meteor_Glow#ParticleEmitter"] = 4,
	["Objects/Meteor/EmitPoint/Meteor_Outline#ParticleEmitter"] = 5,
	["Objects/Meteor/EmitPoint/Meteor_Tail#ParticleEmitter"] = 5,
	["Objects/Meteor/EmitPoint/Meteor_WhiteTail#ParticleEmitter"] = 5,
	["Objects/Meteor/Glow#PointLight"] = 20,
	["Objects/Meteor/Meteor_Debris#ParticleEmitter"] = 4,
	["Objects/Meteor/Trail#Trail"] = 21,
	["Objects/Portal/Appearance#ParticleEmitter"] = 12,
	["Objects/Portal/InnerLightBeam#Beam"] = 22,
	["Objects/Portal/OuterLightBeam#Beam"] = 22,
	["Objects/Portal/Sparks#ParticleEmitter"] = 23,
	["Particles/Appearance#ParticleEmitter"] = 3,
}

--- `blossom` is `Smite4` exactly as it ships today. It is the default, so an untouched buyer
--- sees no change at all. Roles 16 and 18 are deliberately green: the pack's author missed
--- those nodes when recolouring, and reproducing the miss is what makes this byte-identical.
local PALETTES: { [string]: Palette } = {
	blossom = {
		[1] = { { 0, 255, 85, 255 }, { 1, 255, 85, 255 } },
		[2] = { { 0, 255, 170, 255 }, { 1, 255, 170, 255 } },
		[3] = { { 0, 255, 170, 255 }, { 1, 255, 170, 255 } },
		[4] = { { 0, 255, 0, 255 }, { 1, 255, 0, 255 } },
		[5] = { { 0, 255, 85, 255 }, { 1, 255, 85, 255 } },
		[6] = { { 0, 255, 85, 255 }, { 1, 255, 85, 255 } },
		[7] = { { 0, 255, 85, 255 }, { 1, 255, 85, 255 } },
		[8] = { { 0, 255, 170, 255 }, { 1, 255, 170, 255 } },
		[9] = { { 0, 255, 0, 127 }, { 1, 255, 0, 127 } },
		[10] = { { 0, 255, 0, 255 }, { 1, 255, 0, 255 } },
		[11] = { { 0, 255, 255, 255 }, { 1, 255, 255, 255 } },
		[12] = { { 0, 255, 0, 255 }, { 1, 255, 0, 255 } },
		[13] = { { 0, 255, 255, 255 }, { 1, 255, 255, 255 } },
		[14] = { { 0, 255, 170, 255 }, { 1, 255, 170, 255 } },
		[15] = { { 0, 0, 255, 255 }, { 1, 0, 0, 255 } },
		[16] = { { 0, 85, 255, 127 }, { 1, 85, 255, 127 } },
		[17] = { { 0, 255, 0, 255 }, { 1, 255, 0, 255 } },
		[18] = { { 0, 255, 255, 255 }, { 0.5156, 255, 182, 255 }, { 1, 255, 85, 255 } },
		[19] = { { 0, 255, 170, 255 }, { 1, 255, 170, 255 } },
		[20] = { { 0, 255, 85, 255 } },
		[21] = { { 0, 255, 170, 255 }, { 1, 255, 170, 255 } },
		[22] = { { 0, 255, 170, 255 }, { 1, 255, 170, 255 } },
		[23] = { { 0, 255, 85, 255 }, { 1, 255, 85, 255 } },
	},

	--- `nature` is `Smite3`'s greens, the look GreenHammer used to draw. Reproduced on the
	--- `Smite4` base, so it comes with `Crown` instead of `CORONA` — accepted in ADR 0013,
	--- because no shipped `WorldEffectTiers` ever reached `Smite3`.
	nature = {
		[1] = { { 0, 85, 255, 127 }, { 1, 85, 255, 127 } },
		[2] = { { 0, 255, 255, 255 }, { 0.2907, 210, 255, 221 }, { 0.3772, 173, 255, 193 }, { 0.5225, 205, 255, 218 }, { 1, 85, 255, 127 } },
		[3] = { { 0, 85, 255, 0 }, { 1, 85, 255, 0 } },
		[4] = { { 0, 85, 170, 0 }, { 1, 85, 170, 0 } },
		[5] = { { 0, 85, 170, 0 }, { 1, 85, 170, 0 } },
		[6] = { { 0, 0, 85, 0 }, { 1, 0, 85, 0 } },
		[7] = { { 0, 85, 170, 127 }, { 1, 85, 170, 127 } },
		[8] = { { 0, 85, 170, 0 }, { 1, 85, 170, 0 } },
		[9] = { { 0, 85, 170, 0 }, { 1, 85, 170, 0 } },
		[10] = { { 0, 0, 255, 127 }, { 1, 0, 255, 127 } },
		[11] = { { 0, 0, 255, 127 }, { 1, 0, 255, 127 } },
		[12] = { { 0, 0, 170, 0 }, { 1, 0, 170, 0 } },
		[13] = { { 0, 0, 170, 0 }, { 1, 0, 170, 0 } },
		[14] = { { 0, 85, 255, 127 }, { 1, 85, 255, 127 } },
		[15] = { { 0, 0, 255, 255 }, { 1, 0, 0, 255 } },
		[16] = { { 0, 85, 255, 127 }, { 1, 85, 255, 127 } },
		[17] = { { 0, 85, 255, 127 }, { 1, 85, 255, 127 } },
		[18] = { { 0, 255, 255, 255 }, { 1, 129, 129, 129 } },
		[19] = { { 0, 255, 255, 255 }, { 1, 255, 255, 255 } },
		[20] = { { 0, 85, 255, 127 } },
		[21] = { { 0, 0, 255, 0 }, { 1, 0, 255, 0 } },
		[22] = { { 0, 0, 170, 127 }, { 1, 0, 170, 127 } },
		[23] = { { 0, 0, 170, 0 }, { 1, 0, 170, 0 } },
	},
}

ThemeData.ROLE_BY_NODE = ROLE_BY_NODE
ThemeData.PALETTES = PALETTES

ThemeData.DEFAULT_PALETTE = "blossom"

--[[
  Regenerating (needs a place where BOTH `WorldEffects.Smite3` and `.Smite4` still exist —
  after ADR 0013's runtime prune lands, that is the dev place only):

  Walk both models with the key builder described above (per-segment "~n" ordinals in
  GetChildren order), read `Color` from every ParticleEmitter / Beam / Trail / PointLight,
  and group nodes by the pair of colour sequences. Assert three things before writing:
  no duplicate keys, no node without a `Smite3` partner, and the node count still 75.
  The generator script is not checked in because it is a one-shot; the assertions above are
  what make a regeneration trustworthy, not the script.
]]

return ThemeData
