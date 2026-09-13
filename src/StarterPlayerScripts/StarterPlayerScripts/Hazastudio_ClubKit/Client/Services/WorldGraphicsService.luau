--!strict
-- Sole owner of shadow casting and SurfaceAppearance across the whole Workspace for
-- the graphics preset (CONTEXT.md "Shadows Off"). Not gated by ScalableGeometry tags:
-- an untagged map must still reach zero shadows.
--
-- While anything is forced off, instances that appear later (StreamingEnabled, avatars,
-- GLights fixtures that build their lights on the client) are caught by DescendantAdded.
-- Nothing is watched while the preset keeps the map as built.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

export type WorldGraphicsState = {
	lightShadows: boolean,
	partShadows: boolean,
	surfaceAppearance: boolean,
}

-- Mesh detail is NOT here: `MeshPart.RenderFidelity` cannot be changed at run-time. Every
-- write warns "Cannot change SolidModel RenderFidelity during Run-Time" (PARKLAB 2026-09-12:
-- 40 writes, 40 warnings) and the renderer keeps the mesh it tessellated at load, so the
-- property value changing is not a visual change. It is authored in Studio and saved.
local ORIGINAL_CAST_SHADOW_ATTRIBUTE = "RuntimeSettingsOriginalCastShadow"
local ORIGINAL_LIGHT_SHADOWS_ATTRIBUTE = "RuntimeSettingsOriginalLightShadows"
local SWEEP_BATCH = 1000
local DETACHED_PRUNE_EVERY = 500

local WorldGraphicsService = {}

local current: WorldGraphicsState = { lightShadows = true, partShadows = true, surfaceAppearance = true }
local generation = 0
local shadowsEverForced = false
local addedConn: RBXScriptConnection? = nil
-- SurfaceAppearance -> the part it was taken from. Strong refs: a detached instance has
-- no other owner, so a weak table would lose it before it can be put back.
local detached: { [SurfaceAppearance]: Instance } = {}
local detachedSincePrune = 0

local function isAvatarDescendant(instance: Instance): boolean
	local model = instance:FindFirstAncestorWhichIsA("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") or Players:GetPlayerFromCharacter(model) then
			return true
		end
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	return false
end

local function applyPart(part: BasePart)
	local original = part:GetAttribute(ORIGINAL_CAST_SHADOW_ATTRIBUTE)
	if current.partShadows then
		if type(original) == "boolean" and part.CastShadow ~= original then
			part.CastShadow = original
		end
		return
	end
	if original == nil then
		part:SetAttribute(ORIGINAL_CAST_SHADOW_ATTRIBUTE, part.CastShadow)
	end
	if part.CastShadow then
		part.CastShadow = false
	end
end

local function applyLight(light: Light)
	local original = light:GetAttribute(ORIGINAL_LIGHT_SHADOWS_ATTRIBUTE)
	if current.lightShadows then
		if type(original) == "boolean" and light.Shadows ~= original then
			light.Shadows = original
		end
		return
	end
	if original == nil then
		light:SetAttribute(ORIGINAL_LIGHT_SHADOWS_ATTRIBUTE, light.Shadows)
	end
	if light.Shadows then
		light.Shadows = false
	end
end

local function pruneDetached()
	detachedSincePrune = 0
	for surface, owner in pairs(detached) do
		if not owner:IsDescendantOf(game) then
			detached[surface] = nil
		end
	end
end

local function detachSurface(surface: SurfaceAppearance)
	local owner = surface.Parent
	if not owner or isAvatarDescendant(surface) then
		return
	end
	detached[surface] = owner
	surface.Parent = nil
	detachedSincePrune += 1
	if detachedSincePrune >= DETACHED_PRUNE_EVERY then
		pruneDetached()
	end
end

local function reattachSurfaces()
	for surface, owner in pairs(detached) do
		if owner:IsDescendantOf(game) then
			surface.Parent = owner
		end
	end
	table.clear(detached)
	detachedSincePrune = 0
end

local function applyToInstance(instance: Instance)
	if instance:IsA("BasePart") then
		-- Terrain shadows follow GlobalShadows and light Shadows, both already handled.
		if not instance:IsA("Terrain") then
			applyPart(instance :: BasePart)
		end
	elseif instance:IsA("Light") then
		applyLight(instance :: Light)
	elseif instance:IsA("SurfaceAppearance") then
		if not current.surfaceAppearance and instance.Parent then
			detachSurface(instance :: SurfaceAppearance)
		end
	end
end

local function onDescendantAdded(instance: Instance)
	if instance:IsA("BasePart") or instance:IsA("Light") or instance:IsA("SurfaceAppearance") then
		-- Deferred so the creator finishes configuring it (and avatars get their Humanoid).
		task.defer(applyToInstance, instance)
	end
end

local function sweep(sweepGeneration: number)
	local processed = 0
	for _, instance in ipairs(Workspace:GetDescendants()) do
		if sweepGeneration ~= generation then
			return
		end
		applyToInstance(instance)
		processed += 1
		if processed % SWEEP_BATCH == 0 then
			task.wait()
		end
	end
end

function WorldGraphicsService.apply(state: WorldGraphicsState)
	if
		state.lightShadows == current.lightShadows
		and state.partShadows == current.partShadows
		and state.surfaceAppearance == current.surfaceAppearance
	then
		return
	end

	local shadowsChanged = state.lightShadows ~= current.lightShadows or state.partShadows ~= current.partShadows
	local surfacesForced = not state.surfaceAppearance and current.surfaceAppearance
	current = {
		lightShadows = state.lightShadows,
		partShadows = state.partShadows,
		surfaceAppearance = state.surfaceAppearance,
	}
	generation += 1

	local anythingForced = not (current.lightShadows and current.partShadows and current.surfaceAppearance)
	if anythingForced and not addedConn then
		addedConn = Workspace.DescendantAdded:Connect(onDescendantAdded)
	elseif not anythingForced and addedConn then
		addedConn:Disconnect()
		addedConn = nil
	end

	if current.surfaceAppearance then
		reattachSurfaces()
	end
	if not (current.lightShadows and current.partShadows) then
		shadowsEverForced = true
	end

	-- Restoring shadows only needs a pass if something was ever forced off; reattaching
	-- SurfaceAppearance never needs one (the detached map holds them all).
	if (shadowsChanged and shadowsEverForced) or surfacesForced then
		task.spawn(sweep, generation)
	end
end

function WorldGraphicsService.stop()
	WorldGraphicsService.apply({ lightShadows = true, partShadows = true, surfaceAppearance = true })
end

return WorldGraphicsService
