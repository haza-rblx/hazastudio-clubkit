--!strict
-- StarterPlayer/StarterPlayerScripts/Client/Utils/AvatarViewport3D.lua
-- Handle 3D avatar rendering with auto-rotate
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
-- Import Logger untuk proper logging
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local AssetHealthReporter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.AssetHealthReporter)
local log = Logger.new("AvatarViewport3D")
local AvatarViewport3D = {} :: any
AvatarViewport3D.__index = AvatarViewport3D
export type AvatarViewport3D = {
	load: (self: AvatarViewport3D, userId: number) -> boolean,
	startAutoRotate: (self: AvatarViewport3D) -> (),
	stopAutoRotate: (self: AvatarViewport3D) -> (),
	cleanup: (self: AvatarViewport3D) -> (),
	setPrewarmPool: (self: AvatarViewport3D, pool: any) -> (),
	_assetReporter: any,
}
function AvatarViewport3D.new(viewportFrame: ViewportFrame): AvatarViewport3D
	local self = setmetatable({}, AvatarViewport3D) :: any

	self._viewport = viewportFrame
	self._worldModel = nil :: WorldModel?
	self._character = nil :: Model?
	self._camera = nil :: Camera?
	self._autoRotateConnection = nil :: RBXScriptConnection?
	self._assetReporter = AssetHealthReporter.new(log)
	self._prewarmPool = nil :: any?
	-- Generation counter: incremented on every cleanup() call.
	-- Used as a cancellation token to detect stale load() calls after a yield.
	self._loadGeneration = 0
	self._currentRotation = 0
	return self
end
local function collectBodyParts(character: Model): {BasePart}
	local bodyParts = {}
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") and not descendant:FindFirstAncestorWhichIsA("Accessory") then
			table.insert(bodyParts, descendant)
		end
	end
	return bodyParts
end
local function getBodyBounds(character: Model): (Vector3, Vector3)
	local bodyParts = collectBodyParts(character)
	if #bodyParts == 0 then
		local boxCFrame, boxSize = character:GetBoundingBox()
		return boxCFrame.Position, boxSize
	end
	local minPoint = Vector3.new(math.huge, math.huge, math.huge)
	local maxPoint = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, part in ipairs(bodyParts) do
		local pos = part.Position
		local half = part.Size * 0.5
		minPoint = Vector3.new(
			math.min(minPoint.X, pos.X - half.X),
			math.min(minPoint.Y, pos.Y - half.Y),
			math.min(minPoint.Z, pos.Z - half.Z)
		)
		maxPoint = Vector3.new(
			math.max(maxPoint.X, pos.X + half.X),
			math.max(maxPoint.Y, pos.Y + half.Y),
			math.max(maxPoint.Z, pos.Z + half.Z)
		)
	end
	return (minPoint + maxPoint) * 0.5, maxPoint - minPoint
end

--- Pool models are stored anchored; without this, parts stay frozen in place,
--- rotation only moves HRP, and the camera can frame a single part (e.g. nose).
local function prepareCharacterForViewport(character: Model): Humanoid
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		error("Character missing HumanoidRootPart")
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		error("Character missing Humanoid")
	end
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
		elseif (part:IsA("LocalScript") or part:IsA("Script")) and part.Name == "Animate" then
			-- Disable Roblox-injected Animate script — it errors inside ViewportFrame/WorldModel
			-- context (can't find server services it expects). Manual Animator in playIdleAnimation
			-- handles animation instead.
			part.Enabled = false
		end
	end
	character.PrimaryPart = hrp
	character:MoveTo(Vector3.new(0, 0, 0))
	return humanoid
end

local function playIdleAnimation(
	self: AvatarViewport3D,
	character: Model,
	humanoid: Humanoid,
	userId: number,
	generation: number
)
	task.defer(function()
		task.wait(0.1)
		if self._loadGeneration ~= generation or not humanoid.Parent then
			return
		end
		local rigType = humanoid.RigType
		local idleAnimationId = if rigType == Enum.HumanoidRigType.R15
			then Config.Icons.Avatar.IdleR15
			else Config.Icons.Avatar.IdleR6
		local idleSourcePath = if rigType == Enum.HumanoidRigType.R15
			then "Config.Icons.Avatar.IdleR15"
			else "Config.Icons.Avatar.IdleR6"
		local idleAnim = Instance.new("Animation")
		idleAnim.AnimationId = idleAnimationId
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		if self._loadGeneration ~= generation or not humanoid.Parent then
			idleAnim:Destroy()
			return
		end
		local animSuccess, idleTrack = pcall(function()
			return animator:LoadAnimation(idleAnim)
		end)
		if not animSuccess then
			idleAnim:Destroy()
		end
		if animSuccess and idleTrack then
			idleTrack.Looped = true
			idleTrack.Priority = Enum.AnimationPriority.Idle
			idleTrack:Play(0.1, 1, 1)
			character:SetAttribute("_idleTrack", true)
		else
			self._assetReporter:recordSourceFailure(
				"Animation",
				idleSourcePath,
				idleAnimationId,
				"AvatarViewport3D.load",
				idleTrack,
				{
					userId = userId,
					rigType = tostring(rigType),
				}
			)
		end
	end)
end

--- Inject a pre-warm pool. load() hanya memakai model dari pool —
--- TIDAK ada fallback CreateHumanoidModelFromUserId. Caller (UI) yang
--- bertanggung jawab untuk thumbnail fallback + trigger pool prewarm.
function AvatarViewport3D:setPrewarmPool(pool: any)
	self._prewarmPool = pool
end

function AvatarViewport3D:load(userId: number): boolean
	self:cleanup()
	-- Snapshot the generation token BEFORE any yield so we can detect
	-- if cleanup() is called again while the pool take suspends.
	local generation = self._loadGeneration

	-- Create WorldModel upfront and store it so cleanup() can destroy it
	-- even if the load is still in flight.
	local worldModel = Instance.new("WorldModel")
	self._worldModel = worldModel
	self._viewport.CurrentCamera = nil

	-- Pool-only path. Kalau pool miss, return false agar caller fallback
	-- ke thumbnail + subscribe ke subscribeModelReady untuk upgrade seamless.
	-- Menghilangkan CreateHumanoidModelFromUserId di click path supaya
	-- tidak ada YIELD 2-8s di main thread (root cause dari placeholder lama
	-- + button close disabled di AvatarContextController.openPanel).
	if not self._prewarmPool or type(self._prewarmPool.take) ~= "function" then
		log:warn("load() called without prewarm pool; caller must ensure pool is set", { userId = userId })
		return false
	end
	local poolModel = self._prewarmPool:take(userId)
	if not poolModel then
		log:debug("Pool miss — caller should fallback to thumbnail", { userId = userId })
		return false
	end
	log:debug("Pool hit — using pre-warmed model", { userId = userId })

	if self._loadGeneration ~= generation then
		-- Stale load - caller sudah close, discard untuk hindari leak.
		poolModel:Destroy()
		log:warn("load() cancelled (superseded by newer request)", { userId = userId })
		return false
	end

	local prepOk, humanoidOrErr = pcall(prepareCharacterForViewport, poolModel)
	if not prepOk then
		poolModel:Destroy()
		log:warn("Failed to prepare character for viewport", {
			userId = userId,
			fromPool = true,
			error = tostring(humanoidOrErr),
		})
		return false
	end
	playIdleAnimation(self, poolModel, humanoidOrErr :: Humanoid, userId, generation)

	self._character = poolModel
	poolModel.Parent = worldModel
	worldModel.Parent = self._viewport
	-- Setup camera
	local camera = Instance.new("Camera")
	camera.Parent = worldModel
	self._camera = camera
	self._viewport.CurrentCamera = camera
	-- Position camera
	self:_positionCamera()
	-- Start auto-rotate immediately
	self:startAutoRotate()
	return true
end
function AvatarViewport3D:_positionCamera()
	if not self._character or not self._camera then return end
	local hrp = self._character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = self._character:FindFirstChild("Head") :: BasePart?
	if not hrp or not head then return end
	local bodyCenter, bodySize = getBodyBounds(self._character)
	local torsoDepthBias = math.max(0.2, bodySize.Z * 0.08)
	local focusPoint = Vector3.new(
		head.Position.X,
		head.Position.Y - math.max(0.4, bodySize.Y * 0.12),
		head.Position.Z - torsoDepthBias
	)
	local cameraDistance = math.max(
		Config.AvatarContext.CAMERA_DISTANCE,
		(bodySize.Y * 0.52) + (bodySize.X * 0.45)
	) * 0.92
	local cameraHeight = math.max(
		Config.AvatarContext.CAMERA_HEIGHT,
		(head.Position.Y - bodyCenter.Y) * 0.08
	)
	self._camera.CFrame = CFrame.new(
		Vector3.new(focusPoint.X, focusPoint.Y + cameraHeight, focusPoint.Z + cameraDistance),
		focusPoint
	)

	self._camera.FieldOfView = Config.AvatarContext.CAMERA_FOV
end
function AvatarViewport3D:_applyRotation()
	if not self._character then return end
	if not self._character.PrimaryPart then return end

	-- Rotate the entire model via PrimaryPart
	local hrp = self._character.PrimaryPart
	local currentCFrame = hrp.CFrame
	local position = currentCFrame.Position

	-- Apply Y-axis rotation
	hrp.CFrame = CFrame.new(position) * CFrame.Angles(0, self._currentRotation, 0)
end
function AvatarViewport3D:startAutoRotate()
	if self._autoRotateConnection then return end

	local rotateSpeed = math.rad(Config.AvatarContext.AUTO_ROTATE_SPEED)
	-- Frame-skip throttle: only process every N-th RenderStepped frame.
	-- Reduces Lua CPU callback cost ~3x and CFrame-triggered engine work.
	-- Rotation speed is compensated (multiplied by skip rate) so the
	-- perceived rotation speed stays the same.
	local skipRate = math.max(1, Config.AvatarContext.AUTO_ROTATE_SKIP_RATE or 3)
	local frameCounter = 0

	self._autoRotateConnection = RunService.RenderStepped:Connect(function(deltaTime)
		frameCounter += 1
		if frameCounter % skipRate ~= 0 then
			return
		end
		self._currentRotation += rotateSpeed * deltaTime * skipRate
		self:_applyRotation()
	end)
end
function AvatarViewport3D:stopAutoRotate()
	if self._autoRotateConnection then
		self._autoRotateConnection:Disconnect()
		self._autoRotateConnection = nil
	end
end
function AvatarViewport3D:cleanup()
	-- Increment generation so any in-flight load() knows it has been cancelled.
	self._loadGeneration += 1
	-- Stop auto-rotate
	self:stopAutoRotate()
	-- Clear viewport
	if self._worldModel then
		self._worldModel:Destroy()
		self._worldModel = nil
	end
	self._character = nil
	self._camera = nil
	self._viewport.CurrentCamera = nil
	-- Reset state
	self._currentRotation = 0
end
return AvatarViewport3D
