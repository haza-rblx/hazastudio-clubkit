--!strict
-- StarterPlayer/StarterPlayerScripts/Client/Utils/AvatarViewport3D.lua
-- Handle 3D avatar rendering with auto-rotate
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local UIMotion = require(script.Parent.UIMotion)
local UISpring = require(script.Parent.UISpring)
local PointerSpace = require(script.Parent.PointerSpace)
-- Import Logger for proper logging
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local AssetHealthReporter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.AssetHealthReporter)
local log = Logger.new("AvatarViewport3D")
local AvatarViewport3D = {} :: any
AvatarViewport3D.__index = AvatarViewport3D
export type AvatarViewport3D = {
	load: (self: AvatarViewport3D, userId: number) -> boolean,
	startAutoRotate: (self: AvatarViewport3D) -> (),
	stopAutoRotate: (self: AvatarViewport3D) -> (),
	setGazeFollow: (self: AvatarViewport3D, enabled: boolean, hitArea: GuiObject?) -> (),
	cleanup: (self: AvatarViewport3D) -> (),
	setPrewarmPool: (self: AvatarViewport3D, pool: any) -> (),
	_assetReporter: any,
}

-- Model yaw that faces the viewport camera: _positionCamera puts the camera on +Z looking
-- back at the head, and a character's default LookVector is -Z.
local GAZE_FACING_ROTATION = math.pi

--- The neck joint of either rig generation, plus the pose field gaze is allowed to own.
--- Legacy rigs weld the head with a Motor6D (`Head.Neck` on R15, `Torso.Neck` on R6);
--- constraint rigs use an AnimationConstraint whose offset lives on the rig Attachment.
--- Both have a `Transform`, and on both the Animator rewrites it every frame — measured
--- 2026-09-20 at Input/Camera/Character+1/500/Last/Last+100, every one overwritten. So gaze
--- writes the field the Animator never touches: `C0` for a Motor6D, `Attachment0.CFrame` for
--- an AnimationConstraint. Both compose on top of the idle animation instead of fighting it.
type GazeJoint = {
	motor: Motor6D?,
	attachment: Attachment?,
	base: CFrame,
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
	-- Gaze follow is opt-in per instance (setGazeFollow). ACM, donation panel and profile
	-- tab all opt in (2026-09-21); a viewport that does not keeps the plain spin.
	self._gazeRequested = false
	self._gazeHitArea = nil :: GuiObject?
	self._gazeConnection = nil :: RBXScriptConnection?
	self._gazeJoint = nil :: GazeJoint?
	self._gazeWaist = nil :: GazeJoint?
	self._gazeYaw = 0
	self._gazePitch = 0
	return self
end

local function toGazeJoint(joint: Instance?): GazeJoint?
	if joint and joint:IsA("Motor6D") then
		return { motor = joint, attachment = nil, base = joint.C0 }
	end
	if joint and joint:IsA("AnimationConstraint") then
		local rigAttachment = joint.Attachment0
		if rigAttachment then
			return { motor = nil, attachment = rigAttachment, base = rigAttachment.CFrame }
		end
	end
	return nil
end

local function resolveGazeJoint(character: Model): GazeJoint?
	local head = character:FindFirstChild("Head")
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	return toGazeJoint((head and head:FindFirstChild("Neck")) or (torso and torso:FindFirstChild("Neck")))
end

--- R15 only (`UpperTorso.Waist`); R6 has no waist and the neck keeps the whole turn.
local function resolveGazeWaist(character: Model): GazeJoint?
	local upperTorso = character:FindFirstChild("UpperTorso")
	return toGazeJoint(upperTorso and upperTorso:FindFirstChild("Waist"))
end

--- Rotate around the joint's own pivot but in the PARENT part's axes, so one pair of
--- angles reads the same on every rig — R6's Neck C0 carries a -90°/180° rotation of its
--- own, and rotating in joint space there would yaw the head sideways.
local function writeGazeJoint(joint: GazeJoint, pitch: number, yaw: number)
	local base = joint.base
	local pose = CFrame.new(base.Position) * CFrame.Angles(pitch, yaw, 0) * base.Rotation
	if joint.motor then
		joint.motor.C0 = pose
	elseif joint.attachment then
		joint.attachment.CFrame = pose
	end
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

--- Inject a pre-warm pool. load() only uses models from the pool —
--- NO CreateHumanoidModelFromUserId fallback. Caller (UI) is responsible
--- for thumbnail fallback + triggering pool prewarm.
function AvatarViewport3D:setPrewarmPool(pool: any)
	self._prewarmPool = pool
end

-- Destroy every WorldModel child of the viewport. self._worldModel may be only the
-- most recent; orphans from a second AvatarViewport3D bound to the same ViewportFrame
-- or a superseded in-flight load would otherwise linger and double-render.
function AvatarViewport3D:_destroyAllWorldModels()
	for _, child in ipairs(self._viewport:GetChildren()) do
		if child:IsA("WorldModel") then
			child:Destroy()
		end
	end
end

function AvatarViewport3D:load(userId: number): boolean
	self:cleanup()
	-- Snapshot the generation token BEFORE any yield so we can detect
	-- if cleanup() is called again while the pool take suspends.
	local generation = self._loadGeneration

	-- Defensive: remove any leftover WorldModel before creating the new one.
	self:_destroyAllWorldModels()

	-- Create WorldModel upfront and store it so cleanup() can destroy it
	-- even if the load is still in flight.
	local worldModel = Instance.new("WorldModel")
	self._worldModel = worldModel
	self._viewport.CurrentCamera = nil

	-- Pool-only path. On pool miss, return false so caller can fallback
	-- to thumbnail + subscribe to subscribeModelReady for seamless upgrade.
	-- Remove CreateHumanoidModelFromUserId from click path so
	-- no YIELD 2-8s on the main thread (root cause from old placeholder
	-- + close button disabled in AvatarContextController.openPanel).
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
		-- Stale load - caller already close, discard to avoid leak.
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
	-- Gaze follow replaces the spin when this viewport opted in and the player has a cursor.
	if self:_gazeSupported() then
		self:_startGazeFollow()
	else
		self:startAutoRotate()
	end
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
--- Gaze needs a pointer to follow: no mouse (touch / gamepad) keeps the spin, and
--- ReducedMotionEnabled turns the whole thing off (ADR 0011).
function AvatarViewport3D:_gazeSupported(): boolean
	if not self._gazeRequested then return false end
	if Config.AvatarContext.GAZE_FOLLOW_ENABLED == false then return false end
	if not UserInputService.MouseEnabled or UserInputService.TouchEnabled then return false end
	return not UIMotion.reduced()
end

local function wrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

--- Whether the viewport is actually drawn: every GuiObject up to its LayerCollector visible
--- and that collector enabled. The profile tab keeps its avatar loaded while the menu is
--- closed, so the gaze loop checks this every frame and idles instead of animating unseen.
local function isOnScreen(gui: GuiObject): boolean
	local node: Instance? = gui
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end
		elseif node:IsA("LayerCollector") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

function AvatarViewport3D:_startGazeFollow()
	if not self._character then return end
	self:stopAutoRotate()

	-- Gaze owns the model and its spin: the loop below spins the body only while the cursor
	-- is away, and turns it back to face the camera when the cursor comes in, so the head
	-- never hits its clamp and "breaks" gaze with its back to the viewer.
	self._currentRotation = GAZE_FACING_ROTATION
	self:_applyRotation()

	local joint = resolveGazeJoint(self._character)
	if not joint then
		-- Custom rig with no Neck joint: a frozen avatar would look broken, so spin instead.
		log:debug("Gaze follow: no neck joint on this rig, falling back to auto-rotate")
		self:startAutoRotate()
		return
	end
	self._gazeJoint = joint
	self._gazeWaist = if Config.AvatarContext.GAZE_WAIST_ENABLED == false then nil else resolveGazeWaist(self._character)
	self._gazeYaw = 0
	self._gazePitch = 0
	self:_writeGaze(0, 0)

	if self._gazeConnection then return end

	local cfg = Config.AvatarContext
	local yawLimit = math.rad(cfg.GAZE_YAW_LIMIT or 40)
	local pitchLimit = math.rad(cfg.GAZE_PITCH_LIMIT or 25)
	local skipRate = math.max(1, cfg.GAZE_SKIP_RATE or 1)
	local spinSpeed = math.rad(cfg.AUTO_ROTATE_SPEED or 30)
	local resumeDelay = cfg.GAZE_RESUME_SPIN_DELAY or 1.5
	local spinRamp = cfg.GAZE_SPIN_RAMP or 3
	local swayAngle = math.rad(cfg.GAZE_SWAY_ANGLE or 0)
	local swayPeriod = math.max(0.5, cfg.GAZE_SWAY_PERIOD or 6)
	local frameCounter = 0
	local accumulated = 0
	-- Opened with the cursor elsewhere: hold facing for one resume delay, then spin.
	local lastInsideAt = os.clock()
	local spinVelocity = 0
	local swayClock = 0
	-- Critically-damped springs (UISpring, same formula as Freecam) instead of exponential
	-- easing: exponential easing jumps to full speed the instant its target moves, which read
	-- as jerky every time the cursor moved or the spin handed over to the turn-back. A spring
	-- carries its velocity across every retarget, so spin -> turn back -> sway is one curve.
	local headYawSpring = UISpring.newNumber(cfg.GAZE_HEAD_SPRING_FREQ or 1.6, 0)
	local headPitchSpring = UISpring.newNumber(cfg.GAZE_HEAD_SPRING_FREQ or 1.6, 0)
	-- Body angle is unwrapped (it spins); its goal is always picked on the near side of it.
	local bodySpring = UISpring.newNumber(cfg.GAZE_BODY_SPRING_FREQ or 0.9, self._currentRotation)
	local spinGoal = self._currentRotation

	self._gazeConnection = RunService.RenderStepped:Connect(function(deltaTime)
		accumulated += deltaTime
		frameCounter += 1
		if frameCounter % skipRate ~= 0 then
			return
		end
		local step = accumulated
		accumulated = 0

		if not self._gazeJoint or not isOnScreen(self._viewport) then
			return
		end
		-- Back on screen after a long hide: one huge step would fling the springs.
		step = math.min(step, 0.1)

		-- Look direction relative to the CAMERA, not the body: 0/0 = straight at the viewer.
		local inside = false
		local lookYaw, lookPitch = 0, 0
		local hitArea = self._gazeHitArea
		local viewport = self._viewport
		if hitArea and isOnScreen(hitArea) and viewport.AbsoluteSize.X > 0 then
			local pointer = PointerSpace.mouse()
			local areaPosition = hitArea.AbsolutePosition
			local areaSize = hitArea.AbsoluteSize
			inside = pointer.X >= areaPosition.X
				and pointer.X <= areaPosition.X + areaSize.X
				and pointer.Y >= areaPosition.Y
				and pointer.Y <= areaPosition.Y + areaSize.Y
			if inside then
				-- Measured from the VIEWPORT's centre (where the avatar is), scaled by the
				-- panel's half-extent so a cursor at the panel edge is a full turn.
				local centre = viewport.AbsolutePosition + viewport.AbsoluteSize * 0.5
				local dx = math.clamp((pointer.X - centre.X) / math.max(1, areaSize.X * 0.5), -1, 1)
				local dy = math.clamp((pointer.Y - centre.Y) / math.max(1, areaSize.Y * 0.5), -1, 1)
				-- The body faces the camera (yaw π), so the avatar's own left is screen-right:
				-- a cursor right of the avatar is POSITIVE yaw (owner-tested 2026-09-21; the
				-- first cut had it negative and looked away from the cursor). Cursor above it
				-- lifts the chin (positive pitch).
				lookYaw = dx * yawLimit
				lookPitch = -dy * pitchLimit
			end
		end

		local now = os.clock()
		if inside then
			lastInsideAt = now
		end

		-- Variation 1 + sway (owner 2026-09-21): cursor away for resumeDelay -> spin; cursor
		-- in (or just left) -> turn back to the camera the short way and sway a few degrees.
		local targetYaw, targetPitch = 0, 0
		local bodyGoal
		if now - lastInsideAt < resumeDelay then
			spinVelocity = 0
			swayClock += step
			local facing = GAZE_FACING_ROTATION + swayAngle * math.sin(swayClock * 2 * math.pi / swayPeriod)
			bodyGoal = bodySpring.p + wrapAngle(facing - bodySpring.p)
			spinGoal = bodySpring.p
		else
			-- The spin drives the spring's GOAL forward, ramping up, so the body inherits a
			-- smooth start and the turn-back later inherits the spin's momentum.
			swayClock = 0
			spinVelocity += (spinSpeed - spinVelocity) * (1 - math.exp(-spinRamp * step))
			spinGoal += spinVelocity * step
			bodyGoal = spinGoal
		end
		UISpring.step(bodySpring, step, bodyGoal)
		-- Keep the unwrapped angle small without a visible jump (whole turns only).
		if math.abs(bodySpring.p) > 4 * math.pi then
			local turns = 2 * math.pi * math.floor(bodySpring.p / (2 * math.pi))
			bodySpring.p -= turns
			spinGoal -= turns
		end
		self._currentRotation = bodySpring.p
		self:_applyRotation()

		-- The head subtracts the body's own turn so the look stays on the cursor while the
		-- body sways. Back still to the viewer (mid turn / spinning): head straight ahead.
		local bodyOffset = wrapAngle(self._currentRotation - GAZE_FACING_ROTATION)
		if math.abs(bodyOffset) < math.pi / 2 then
			targetYaw = math.clamp(lookYaw - bodyOffset, -yawLimit, yawLimit)
			targetPitch = lookPitch
		end
		self._gazeYaw = UISpring.step(headYawSpring, step, targetYaw)
		self._gazePitch = UISpring.step(headPitchSpring, step, targetPitch)
		self:_writeGaze(self._gazePitch, self._gazeYaw)
	end)
end

--- Split one look direction between waist and neck. The neck is parented under the
--- upper torso, so the two turns stack: the head still ends up at the full angle, the
--- body just carries part of it. No waist (R6, custom rig) = the neck takes it all.
function AvatarViewport3D:_writeGaze(pitch: number, yaw: number)
	local neck = self._gazeJoint
	if not neck then
		return
	end
	local waist = self._gazeWaist
	if waist then
		local yawShare = math.clamp(Config.AvatarContext.GAZE_WAIST_YAW_SHARE or 0.35, 0, 1)
		local pitchShare = math.clamp(Config.AvatarContext.GAZE_WAIST_PITCH_SHARE or 0.2, 0, 1)
		writeGazeJoint(waist, pitch * pitchShare, yaw * yawShare)
		writeGazeJoint(neck, pitch * (1 - pitchShare), yaw * (1 - yawShare))
	else
		writeGazeJoint(neck, pitch, yaw)
	end
end

function AvatarViewport3D:_stopGazeFollow(restorePose: boolean?)
	if self._gazeConnection then
		self._gazeConnection:Disconnect()
		self._gazeConnection = nil
	end
	if restorePose then
		self:_writeGaze(0, 0)
	end
	self._gazeJoint = nil
	self._gazeWaist = nil
	self._gazeYaw = 0
	self._gazePitch = 0
end

--- Opt a single viewport into cursor gaze follow. Safe to call before load(): the next
--- load() picks it up. Turning it off restores the neck and resumes the spin.
function AvatarViewport3D:setGazeFollow(enabled: boolean, hitArea: GuiObject?)
	self._gazeRequested = enabled == true
	self._gazeHitArea = hitArea
	if not self._character then
		return
	end
	if self:_gazeSupported() then
		self:_startGazeFollow()
	else
		self:_stopGazeFollow(true)
		self:startAutoRotate()
	end
end

function AvatarViewport3D:startAutoRotate()
	-- Gaze owns the model while it runs and does its own spin when the cursor is away.
	if self._gazeConnection then return end
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
	-- Stop auto-rotate. Gaze too — the model is destroyed below, so its neck needs no restore,
	-- but the connection must go or it writes into a destroyed joint every frame.
	self:_stopGazeFollow(false)
	self:stopAutoRotate()
	-- Clear viewport: destroy every WorldModel child (orphans from a second binder
	-- or a superseded load would otherwise linger and double-render).
	if self._worldModel then
		self._worldModel:Destroy()
		self._worldModel = nil
	end
	self:_destroyAllWorldModels()
	self._character = nil
	self._camera = nil
	self._viewport.CurrentCamera = nil
	-- Reset state
	self._currentRotation = 0
end
return AvatarViewport3D
