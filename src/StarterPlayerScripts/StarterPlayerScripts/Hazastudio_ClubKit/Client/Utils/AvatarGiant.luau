--!strict
-- Gives the donation giant the donor's 3D clothing without touching the effect's own rig.
--
-- THE PROBLEM. `Humanoid` scale values do not scale layered clothing (3D clothes / 3D
-- accessories); `Model:ScaleTo` does. Bisected 2026-09-18 on one avatar, front-on, identical
-- framing: dressed at x4, half gone at x7 (shorts survive, jacket sinks into the body), naked
-- at x10 and above. Rigid accessories (Hat, Face, Neck, Waist, Back) scale normally, which is
-- exactly the "hat and lollipop but no clothes" buyers photographed. The bundled effect rigs
-- are sized with Humanoid scale values, so their giant could never wear layered clothing.
--
-- THE APPROACH: TWO RIGS, ONE VISIBLE.
--   * the effect's own rig stays exactly as it was and keeps driving everything — the
--     animation and its markers, the hammer weld, the portal alignment, the emergence — and
--     is simply made invisible by the effect's existing transparency pass.
--   * a shell built from the donor's avatar, sized with `ScaleTo`, carries the wardrobe and
--     is the thing players actually see.
--   * every PreSimulation the shell copies the rig's pose: root CFrame, then each paired
--     joint's and bone's `Transform`.
--
-- Replacing the rig with the avatar (the obvious approach, and what this module did first)
-- looks equivalent and is not: it orphans the animation track, throws the hammer out of
-- proportion because avatar limb lengths differ from the authored rig, and loses the portal
-- alignment. Mirroring keeps all of that untouched by construction.
--
-- Technique learned by studying a free community asset ("HAMMER FIX R15 3D CLOTH", Cheese
-- Studio) that solves the same problem; this is an independent implementation.
--
-- Two engine details this depends on:
--   * AvatarJointUpgrade replaces `Motor6D` with `AnimationConstraint` on current rigs. Both
--     expose `.Transform` with the same animation-offset semantics, so both are paired.
--     Handling only Motor6D breaks on any rig Roblox has since upgraded.
--   * `ApplyDescription` and `ScaleTo` settle asynchronously, so pairing is retried for a few
--     frames and repaired if the pairs later go stale.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientHttpApi = require(script.Parent.ClientHttpApi)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local AvatarGiant = {}

-- R15 is forced. `CreateHumanoidModelFromUserIdAsync` mirrors whatever the donor wears, so an
-- R6 donor would come back with different part names and nothing would pair.
local RIG_TYPE = Enum.HumanoidRigType.R15
local PAIR_ATTEMPTS = 12
local REPAIR_INTERVAL = 0.25

export type ShellHandle = {
	shell: Model,
	destroy: (self: ShellHandle) -> (),
}

local function isJoint(object: Instance): boolean
	return object:IsA("AnimationConstraint") or object:IsA("Motor6D")
end

-- A joint's identity across two rigs is the pair of parts it binds, not its name: rigs reuse
-- names like "Root". AnimationConstraint exposes Part0/Part1 as read-only aliases, so the
-- same key works for both classes.
local function jointKey(joint: Instance): string?
	local part0 = (joint :: any).Part0
	local part1 = (joint :: any).Part1
	if part0 and part1 then
		return part0.Name .. "|" .. part1.Name
	end
	return nil
end

local function collectJoints(rig: Instance): { [string]: Instance }
	local found: { [string]: Instance } = {}
	for _, object in ipairs(rig:GetDescendants()) do
		if isJoint(object) then
			local key = jointKey(object)
			if key and not found[key] then
				found[key] = object
			end
		end
	end
	return found
end

local function collectBones(rig: Instance): { [string]: Instance }
	local found: { [string]: Instance } = {}
	for _, object in ipairs(rig:GetDescendants()) do
		if object:IsA("Bone") and not found[object.Name] then
			found[object.Name] = object
		end
	end
	return found
end

local function buildPairs(sourceRig: Instance, shellRig: Instance): ({ { Instance } }, { { Instance } })
	local sourceJoints = collectJoints(sourceRig)
	local sourceBones = collectBones(sourceRig)

	local jointPairs: { { Instance } } = {}
	for _, object in ipairs(shellRig:GetDescendants()) do
		if isJoint(object) then
			local key = jointKey(object)
			local partner = key and sourceJoints[key]
			if partner then
				table.insert(jointPairs, { partner, object })
			end
		end
	end

	local bonePairs: { { Instance } } = {}
	for _, object in ipairs(shellRig:GetDescendants()) do
		if object:IsA("Bone") then
			local partner = sourceBones[object.Name]
			if partner then
				table.insert(bonePairs, { partner, object })
			end
		end
	end

	return jointPairs, bonePairs
end

--- The donor's description, cloned. ClientHttpApi's cache hands back the SAME instance, and
--- callers mutate scale fields on it — one donor donating twice inside the 600 s TTL used to
--- compound to x2809 (measured 47.7 -> 2,528 -> 133,989). Always clone before touching it.
function AvatarGiant.fetchDescription(userId: number): HumanoidDescription?
	if type(userId) ~= "number" or userId <= 0 then
		return nil
	end
	local source = ClientHttpApi.getHumanoidDescriptionFromUserIdAsync(userId)
	if source == nil then
		return nil
	end
	local ok, clone = pcall(function()
		return (source :: any):Clone()
	end)
	return if ok then clone else nil
end

--- Strips layered clothing from a description, in place. The source rig is invisible, so it
--- gains nothing from garments it cannot render — and feeding them to a Humanoid-scaled rig
--- is what produced the broken deformation in the first place.
function AvatarGiant.stripLayered(description: HumanoidDescription)
	local ok, accessories = pcall(function()
		return description:GetAccessories(true)
	end)
	if not ok or type(accessories) ~= "table" then
		return
	end
	local rigid = {}
	for _, info in ipairs(accessories) do
		if (info :: any).IsLayered ~= true then
			table.insert(rigid, info)
		end
	end
	pcall(function()
		description:SetAccessories(rigid, true)
	end)
end

--- Builds the visible shell and keeps it mirroring `sourceRig` until destroyed.
--- Returns nil on any failure so the effect simply runs as it always did.
function AvatarGiant.attachShell(sourceRig: Model, description: HumanoidDescription, scale: number): ShellHandle?
	local sourceRoot = sourceRig:FindFirstChild("HumanoidRootPart")
	if not (sourceRoot and sourceRoot:IsA("BasePart")) then
		return nil
	end

	local okDesc, shellDescription = pcall(function()
		return description:Clone()
	end)
	if not okDesc or shellDescription == nil then
		return nil
	end
	-- Size comes from ScaleTo alone, so it is applied once and cannot compound.
	shellDescription.DepthScale = 1
	shellDescription.HeadScale = 1
	shellDescription.HeightScale = 1
	shellDescription.WidthScale = 1

	local okShell, shell = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(shellDescription, RIG_TYPE)
	end)
	pcall(function()
		shellDescription:Destroy()
	end)
	if not okShell or typeof(shell) ~= "Instance" or not shell:IsA("Model") then
		return nil
	end

	shell.Name = sourceRig.Name .. "_ClothingShell"
	shell.Parent = sourceRig.Parent or workspace
	if not pcall(function()
		shell:ScaleTo(scale)
	end) then
		shell:Destroy()
		return nil
	end

	local shellHumanoid = shell:FindFirstChildOfClass("Humanoid")
	if shellHumanoid then
		shellHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		shellHumanoid.AutoRotate = false
		-- The shell is a rendered surface, nothing else. Its own Animator and the stock
		-- Animate script would both fight the pose being copied onto it.
		local shellAnimator = shellHumanoid:FindFirstChildOfClass("Animator")
		if shellAnimator then
			shellAnimator:Destroy()
		end
	end
	local animate = shell:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end

	local shellRoot = shell:FindFirstChild("HumanoidRootPart")
	if not (shellRoot and shellRoot:IsA("BasePart")) then
		shell:Destroy()
		return nil
	end

	for _, object in ipairs(shell:GetDescendants()) do
		if object:IsA("BasePart") then
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = false
			object.Massless = true
			object.Anchored = false
		end
	end
	;(shellRoot :: BasePart).Anchored = true
	;(shellRoot :: BasePart).CFrame = (sourceRoot :: BasePart).CFrame

	-- ApplyDescription and ScaleTo settle over a few frames; pairing too early finds nothing.
	local jointPairs, bonePairs = {}, {}
	for _ = 1, PAIR_ATTEMPTS do
		jointPairs, bonePairs = buildPairs(sourceRig, shell)
		if #jointPairs >= 10 or #bonePairs >= 10 then
			break
		end
		RunService.Heartbeat:Wait()
		if not (sourceRig.Parent and shell.Parent) then
			break
		end
	end

	local lastRepair = 0
	local connection: RBXScriptConnection
	connection = RunService.PreSimulation:Connect(function()
		if not (sourceRig.Parent and shell.Parent) then
			connection:Disconnect()
			return
		end

		local firstJointDead = jointPairs[1] and not (jointPairs[1][1].Parent and jointPairs[1][2].Parent)
		local firstBoneDead = bonePairs[1] and not (bonePairs[1][1].Parent and bonePairs[1][2].Parent)
		local now = os.clock()
		if
			((#jointPairs == 0 and #bonePairs == 0) or firstJointDead or firstBoneDead)
			and now - lastRepair > REPAIR_INTERVAL
		then
			lastRepair = now
			jointPairs, bonePairs = buildPairs(sourceRig, shell)
		end

		;(shellRoot :: BasePart).CFrame = (sourceRoot :: BasePart).CFrame
		for _, pair in ipairs(jointPairs) do
			if pair[1].Parent and pair[2].Parent then
				(pair[2] :: any).Transform = (pair[1] :: any).Transform
			end
		end
		for _, pair in ipairs(bonePairs) do
			if pair[1].Parent and pair[2].Parent then
				(pair[2] :: any).Transform = (pair[1] :: any).Transform
			end
		end
	end)

	local handle = {} :: any
	handle.shell = shell
	function handle:destroy()
		if connection then
			connection:Disconnect()
		end
		if shell and shell.Parent then
			shell:Destroy()
		end
	end
	return handle
end

function AvatarGiant.isEnabled(): boolean
	local flags = Config.FeatureFlags :: any
	return flags == nil or flags.DonationGiantRealAvatar ~= false
end

return AvatarGiant
