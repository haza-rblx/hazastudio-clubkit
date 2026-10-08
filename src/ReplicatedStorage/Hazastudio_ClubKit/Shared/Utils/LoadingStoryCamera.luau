--!strict
-- Character intro camera for the "cinematic" loading style (CONTEXT.md "Character intro").
--
-- The story, and the rules that keep it one story instead of six unrelated shots:
--   Establish  the venue, framed from the side the avatar will face (buyer marker or auto).
--   Feet       low close-up, camera slides along the avatar.
--   Hands      waist height, the camera tilts up the body.
--   Face       head height, slow push-in.
--   Reveal     hard cut to the front, pull back to full body.
--   Orbit      one continuous move front-left -> front -> right -> behind, landing on the
--              gameplay camera, where control goes back to the player (owner, 2026-10-08).
-- The avatar stands still the whole time (its own idle only, no dance). Every shot climbs the
-- body (feet -> hands -> face -> all of it), shots change on hard cuts (no floaty blends), and
-- all distances scale with the avatar's measured height, so a giant or a tiny avatar frames the
-- same.
-- Public API matches LoadingCinematicCamera so LoadingScreenUI can hold either.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Parent.Constants.Config)
local CinematicConfig = Config.Loading.CINEMATIC
local CameraConfig = Config.Loading.STORY.CAMERA

local LoadingStoryCamera = {} :: any
LoadingStoryCamera.__index = LoadingStoryCamera

local BIND_NAME = "LoadingStoryCamera"
local BIND_PRIORITY = Enum.RenderPriority.Camera.Value + CinematicConfig.BIND_PRIORITY_OFFSET
local DEFAULT_FOV = CinematicConfig.DEFAULT_FIELD_OF_VIEW
local BREATHE_AMP = 0.004
local NORMAL_HEIGHT = 5 -- studs, feet to top of head of a default avatar

-- ── Helpers ──────────────────────────────────────────────────

local function easeInOutSine(t: number): number
	return -(math.cos(math.pi * t) - 1) / 2
end

local function easeInOutQuad(t: number): number
	if t < 0.5 then
		return 2 * t * t
	end
	return 1 - (-2 * t + 2) ^ 2 / 2
end

local function easeOutCubic(t: number): number
	return 1 - (1 - t) ^ 3
end

local function noise(t: number, seed: number): number
	return math.sin(t * 1.7 + seed * 3.14) * 0.4 + math.sin(t * 3.1 + seed * 2.18) * 0.3 + math.sin(t * 5.3 + seed * 1.41) * 0.15
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function getCamera(): Camera?
	local c = Workspace.CurrentCamera
	if c and c:IsA("Camera") then
		return c
	end
	return nil
end

local function flatLook(cf: CFrame): Vector3
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if look.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return look.Unit
end

-- Yaw-only frame at a point: local -Z is "in front of" whoever stands there.
local function stageAt(position: Vector3, look: Vector3): CFrame
	return CFrame.lookAt(position, position + look)
end

local function getBehindRevealCFrame(root: BasePart, height: number, distance: number): CFrame
	local look = root.CFrame.LookVector
	local focus = root.Position + Vector3.new(0, 2.1, 0)
	local pos = root.Position - look * distance + Vector3.new(0, height, 0)
	return CFrame.lookAt(pos, focus)
end

-- ── Shots ────────────────────────────────────────────────────
-- Each shot returns camera position + look target in stage space (X right, Y up from the feet,
-- -Z toward the avatar's front), already multiplied by the avatar scale u, plus a field of view.

type ShotFn = (t: number, u: number) -> (Vector3, Vector3, number)
type Shot = { name: string, duration: number, fn: ShotFn }

-- Stage-space point on a circle around the avatar: theta 0 = straight in front, positive = the
-- viewer's left (the avatar's right), 180 = behind.
local function orbitPoint(theta: number, radius: number, height: number): Vector3
	local a = math.rad(theta)
	return Vector3.new(math.sin(a) * radius, height, -math.cos(a) * radius)
end

-- Where Roblox's own camera will sit the moment control returns, in stage space (absolute studs:
-- the default camera does not scale with the avatar). Filled by _step from the same formula
-- BaseCamera:GetSubjectPosition uses, so the orbit lands on it exactly and the hand-over has no
-- jump. Until the first frame sets it, a sane pose behind the avatar.
local landing = { pos = Vector3.new(0, 6, 12.3), target = Vector3.new(0, 4, 0) }

-- Front-left -> front -> right -> behind in one eased move that settles on `landing`.
local function orbitFn(t: number, u: number): (Vector3, Vector3, number)
	local e = easeInOutSine(t)
	local settle = e * e
	local pos = orbitPoint(
		lerp(40, -180, e),
		lerp(9 * u, landing.pos.Z, settle),
		lerp(3.1 * u, landing.pos.Y, settle)
	)
	local target = Vector3.new(0, lerp(2.5 * u, landing.target.Y, settle), 0)
	return pos, target, lerp(52, DEFAULT_FOV, e ^ 1.5)
end

local AVATAR_SHOTS: { Shot } = {
	{
		name = "Feet",
		duration = CameraConfig.FEET,
		fn = function(t, u)
			local e = easeInOutSine(t)
			local pos = Vector3.new(lerp(-1.7, 0.5, e), 0.55, lerp(-3.3, -3.0, e)) * u
			local target = Vector3.new(lerp(-0.25, 0.1, e), 0.35, 0) * u
			return pos, target, 38
		end,
	},
	{
		name = "Hands",
		duration = CameraConfig.HANDS,
		fn = function(t, u)
			local e = easeInOutSine(t)
			local pos = Vector3.new(lerp(-1.2, 0.35, e), lerp(2.2, 2.6, e), -3.4) * u
			local target = Vector3.new(0, lerp(2.1, 3.1, e), 0) * u
			return pos, target, 40
		end,
	},
	{
		name = "Face",
		duration = CameraConfig.FACE,
		fn = function(t, u)
			local e = easeInOutSine(t)
			local pos = Vector3.new(lerp(0.5, 0.3, e), 4.35, lerp(-3.4, -2.45, e)) * u
			local target = Vector3.new(0, 4.3, 0) * u
			return pos, target, 36
		end,
	},
	{
		name = "Reveal",
		duration = CameraConfig.REVEAL,
		fn = function(t, u)
			local e = easeOutCubic(t)
			local pos = Vector3.new(0, lerp(3.4, 3.1, e), lerp(-4.6, -10, e)) * u
			local target = Vector3.new(0, 2.5, 0) * u
			return pos, target, lerp(48, 52, e)
		end,
	},
	{
		name = "Orbit",
		duration = CameraConfig.ORBIT,
		fn = orbitFn,
	},
}

-- After the orbit: hold its end frame (the gameplay camera) until the loading screen lets go.
local HOLD_SHOT: Shot = {
	name = "Hold",
	duration = math.huge,
	fn = function(_t, u)
		return orbitFn(1, u)
	end,
}

-- ── Constructor ──────────────────────────────────────────────

function LoadingStoryCamera.new()
	local self = setmetatable({}, LoadingStoryCamera) :: any
	self._active = false
	self._bound = false
	self._player = Players.LocalPlayer
	self._elapsed = 0
	self._phase = "establish" -- "establish" | "avatar"
	self._shotIndex = 0
	self._shotElapsed = 0
	self._stage = nil :: CFrame?
	-- Avatar size, measured once per character: the head moves with any animation, and
	-- re-measuring it every frame made every distance breathe with it (camera shake).
	self._body = nil :: { root: BasePart, feetDrop: number, u: number }?
	self._establish = nil :: { from: CFrame, to: CFrame, fov: number }?
	self._revealMode = nil :: string?
	self._revealElapsed = 0
	self._revealDuration = 0
	self._revealStartCF = nil :: CFrame?
	self._revealMidCF = nil :: CFrame?
	self._revealEndCF = nil :: CFrame?
	self._revealStartFov = DEFAULT_FOV
	self._revealEndFov = DEFAULT_FOV
	self._rayParams = RaycastParams.new()
	self._rayParams.FilterType = Enum.RaycastFilterType.Exclude
	-- Roblox's stock camera: 12.5 studs behind, looking down 10.7 degrees. start() overwrites
	-- these with what the player's camera actually has.
	self._landZoom = CameraConfig.ORBIT_FALLBACK_ZOOM
	self._landPitch = math.rad(CameraConfig.ORBIT_FALLBACK_PITCH_DEG)
	return self
end

-- ── Avatar measurement ───────────────────────────────────────

-- Root, the stage-space feet height below it, and the avatar scale (1 = default 5-stud avatar).
function LoadingStoryCamera:_measure(): (BasePart?, number, number)
	local character = self._player.Character
	if not character then
		return nil, 0, 1
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil, 0, 1
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local legs = 2
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
		legs = humanoid.HipHeight
	end
	local feetDrop = root.Size.Y / 2 + legs
	local height = NORMAL_HEIGHT
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		height = (head.Position.Y + head.Size.Y / 2) - (root.Position.Y - feetDrop)
	end
	return root, feetDrop, math.clamp(height / NORMAL_HEIGHT, 0.4, 40)
end

function LoadingStoryCamera:_avatarReady(): boolean
	local root = self:_measure()
	if not root then
		return false
	end
	local ok, loaded = pcall(function()
		return self._player:HasAppearanceLoaded()
	end)
	return not ok or loaded == true or self._elapsed >= CameraConfig.ESTABLISH_MAX
end

-- Pull the camera in front of any solid, visible wall between it and what it looks at.
-- Invisible or non-colliding parts (zones, triggers, glass barriers) do not count.
function LoadingStoryCamera:_clearLine(target: Vector3, desired: Vector3): Vector3
	local character = self._player.Character
	local ignore: { Instance } = if character then { character } else {}
	local offset = desired - target
	for _ = 1, 6 do
		self._rayParams.FilterDescendantsInstances = ignore
		local hit = Workspace:Raycast(target, offset, self._rayParams)
		if not hit then
			return desired
		end
		local part = hit.Instance
		if part:IsA("BasePart") and (part.Transparency >= 0.9 or not part.CanCollide) then
			table.insert(ignore, part)
		else
			local distance = math.max((hit.Position - target).Magnitude - 0.6, 1.5)
			return target + offset.Unit * distance
		end
	end
	return desired
end

-- ── Landing pose (what Roblox's default camera will do when control returns) ──

-- The default camera follows HumanoidRootPart + a fixed offset (PlayerModule BaseCamera
-- :GetSubjectPosition: R15 with automatic scaling = 1.5 + (rootHeight/2 - 1)), sits `zoom` studs
-- behind it and looks down by `pitch`. None of that scales with the avatar, so neither does this.
function LoadingStoryCamera:_updateLanding(root: BasePart, feetDrop: number)
	local humanoid = root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
	local offsetY = 1.5
	local cameraOffset = Vector3.zero
	if humanoid then
		cameraOffset = humanoid.CameraOffset
		if humanoid.RigType == Enum.HumanoidRigType.R15 then
			offsetY = if humanoid.AutomaticScalingEnabled then 1.5 + (root.Size.Y / 2 - 1) else 2
		end
	end
	local focusY = feetDrop + offsetY + cameraOffset.Y
	local zoom = self._landZoom
	local pitch = self._landPitch -- radians, negative = looking down
	landing.target = Vector3.new(cameraOffset.X, focusY, cameraOffset.Z)
	landing.pos = Vector3.new(cameraOffset.X, focusY - math.sin(pitch) * zoom, cameraOffset.Z + math.cos(pitch) * zoom)
end

-- ── Establishing shot ────────────────────────────────────────

local function findMarker(): BasePart?
	local folder = Workspace:FindFirstChild(CameraConfig.MARKER_FOLDER)
	if not folder then
		return nil
	end
	local parts = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end
	table.sort(parts, function(a, b)
		return a.Name < b.Name
	end)
	return parts[1]
end

function LoadingStoryCamera:_buildEstablish(camera: Camera)
	local marker = findMarker()
	if marker then
		local fov = tonumber(marker:GetAttribute("FieldOfView")) or 50
		local from = marker.CFrame
		self._establish = { from = from, to = from + from.LookVector * 6, fov = fov }
		return
	end

	-- Auto: from in front of where the avatar stands (or will spawn), high and wide, easing in.
	local anchor: Vector3
	local look: Vector3
	local root = self:_measure()
	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if root then
		anchor, look = root.Position, flatLook(root.CFrame)
	elseif spawn then
		anchor, look = spawn.Position + Vector3.new(0, 3, 0), flatLook(spawn.CFrame)
	else
		anchor, look = camera.CFrame.Position + camera.CFrame.LookVector * 20, flatLook(camera.CFrame)
	end
	local stage = stageAt(anchor, look)
	local focus = anchor + Vector3.new(0, 3, 0)
	local fromPos = self:_clearLine(focus, stage:PointToWorldSpace(Vector3.new(-6, 16, -34)))
	local toPos = self:_clearLine(focus, stage:PointToWorldSpace(Vector3.new(4, 9, -24)))
	self._establish = {
		from = CFrame.lookAt(fromPos, focus),
		to = CFrame.lookAt(toPos, focus),
		fov = 55,
	}
end

-- ── Reveal (tap) moves, same choreography as the classic camera ──

function LoadingStoryCamera:_stepReveal(dt: number, camera: Camera): boolean
	if not self._revealMode then
		return false
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil

	local duration = math.max(self._revealDuration, 0.05)
	self._revealElapsed = math.min(self._revealElapsed + dt, duration)
	local alpha = math.clamp(self._revealElapsed / duration, 0, 1)
	local eased = if self._revealMode == "click_lift" then easeInOutQuad(alpha) else easeOutCubic(alpha)

	local root = self:_measure()
	if root and self._revealMode == "gameplay_drop" then
		self._revealEndCF = getBehindRevealCFrame(root, 4.2, 11)
	end

	local startCF = self._revealStartCF or camera.CFrame
	local midCF = self._revealMidCF
	local endCF = self._revealEndCF or startCF
	if self._revealMode == "click_lift" and midCF then
		if alpha < 0.62 then
			camera.CFrame = startCF:Lerp(midCF, easeInOutQuad(alpha / 0.62))
		else
			camera.CFrame = midCF:Lerp(endCF, easeOutCubic((alpha - 0.62) / 0.38))
		end
	else
		camera.CFrame = startCF:Lerp(endCF, eased)
	end
	camera.FieldOfView = self._revealStartFov + (self._revealEndFov - self._revealStartFov) * eased
	if alpha >= 1 and self._revealMode == "click_lift" then
		self._revealMode = nil
	end
	return true
end

-- ── Render step ──────────────────────────────────────────────

function LoadingStoryCamera:_step(dt: number)
	if not self._active then
		return
	end
	local camera = getCamera()
	if not camera then
		return
	end
	if self:_stepReveal(dt, camera) then
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil
	self._elapsed += dt
	self._shotElapsed += dt

	local breathe = CFrame.Angles(
		noise(self._elapsed, 1) * BREATHE_AMP,
		noise(self._elapsed, 2) * BREATHE_AMP,
		noise(self._elapsed, 3) * BREATHE_AMP * 0.5
	)

	if self._phase == "establish" then
		if not self._establish then
			self:_buildEstablish(camera)
		end
		local shot = self._establish :: { from: CFrame, to: CFrame, fov: number }
		local p = easeInOutSine(math.clamp(self._elapsed / CameraConfig.ESTABLISH_MAX, 0, 1))
		camera.CFrame = shot.from:Lerp(shot.to, p) * breathe
		camera.FieldOfView = shot.fov
		if self._elapsed >= CameraConfig.ESTABLISH_MIN and self:_avatarReady() then
			self._phase = "avatar"
			self._shotIndex = 1
			self._shotElapsed = 0
			self._stage = nil
		end
		return
	end

	local body = self._body
	local character = self._player.Character
	local currentRoot = character and character:FindFirstChild("HumanoidRootPart")
	if not body or body.root ~= currentRoot or body.root.Parent == nil then
		local root, feetDrop, u = self:_measure()
		if not root then
			return -- respawning; hold the last frame
		end
		body = { root = root, feetDrop = feetDrop, u = u }
		self._body = body
	end
	local root, feetDrop, u = body.root, body.feetDrop, body.u

	local shot = AVATAR_SHOTS[self._shotIndex] or HOLD_SHOT
	if shot ~= HOLD_SHOT and self._shotElapsed >= shot.duration then
		local wasOrbit = shot.name == "Orbit"
		self._shotIndex += 1
		self._shotElapsed = 0
		if not wasOrbit then
			self._stage = nil -- hard cut (the hold continues the orbit's end frame)
		end
		shot = AVATAR_SHOTS[self._shotIndex] or HOLD_SHOT
	end

	local feet = root.Position - Vector3.new(0, feetDrop, 0)
	local actual = stageAt(feet, flatLook(root.CFrame))
	if self._stage then
		self._stage = (self._stage :: CFrame):Lerp(actual, math.clamp(dt * CameraConfig.FOLLOW_LERP, 0, 1))
	else
		self._stage = actual
	end
	local stage = self._stage :: CFrame

	self:_updateLanding(root, feetDrop)
	local t = if shot == HOLD_SHOT then 1 else math.clamp(self._shotElapsed / shot.duration, 0, 1)
	local localPos, localTarget, fov = shot.fn(t, u)
	local target = stage:PointToWorldSpace(localTarget)
	local pos = self:_clearLine(target, stage:PointToWorldSpace(localPos))
	-- The idle sway fades out over the orbit's settle, so the last frame is exactly the pose the
	-- default camera takes over with (any leftover tilt would show as a nudge at the hand-over).
	local sway = 1
	if shot == HOLD_SHOT then
		sway = 0
	elseif shot.name == "Orbit" then
		local e = easeInOutSine(t)
		sway = 1 - e * e
	end
	camera.CFrame = CFrame.lookAt(pos, target) * CFrame.identity:Lerp(breathe, sway)
	camera.FieldOfView = fov
end

-- ── Public API ───────────────────────────────────────────────

function LoadingStoryCamera:shotName(): string
	if self._phase == "establish" then
		return "Establish"
	end
	local shot = AVATAR_SHOTS[self._shotIndex] or HOLD_SHOT
	return shot.name
end

--- True once the orbit is within HANDOFF of its end: the loading screen opens the letterbox and
--- fades out over exactly that time, so control returns as the camera lands behind the avatar.
function LoadingStoryCamera:isStoryDone(): boolean
	if self._phase ~= "avatar" then
		return false
	end
	local shot = AVATAR_SHOTS[self._shotIndex]
	if shot == nil then
		return true
	end
	return shot.name == "Orbit" and self._shotElapsed >= shot.duration - CameraConfig.HANDOFF
end

function LoadingStoryCamera:playClickLift(duration: number)
	if not self._active then
		return
	end
	local cam = getCamera()
	if not cam then
		return
	end
	local root = self:_measure()
	local startCF = cam.CFrame
	local endCF = startCF + Vector3.new(0, 18, 0)
	local midCF = startCF + startCF.LookVector * 8
	if root then
		local focus = root.Position + Vector3.new(0, 2.1, 0)
		local toFocus = focus - startCF.Position
		local distance = toFocus.Magnitude
		local forwardDistance = math.max(math.min(distance * 0.58, 14), 5)
		local forward = if distance > 0.001 then toFocus.Unit else startCF.LookVector
		local midPos = startCF.Position + forward * forwardDistance + Vector3.new(0, 0.6, 0)
		midCF = CFrame.lookAt(midPos, focus)
		endCF = CFrame.lookAt(midPos + Vector3.new(0, 16, 0), focus + Vector3.new(0, 1.2, 0))
	end
	self._revealMode = "click_lift"
	self._revealElapsed = 0
	self._revealDuration = math.max(duration, 0.05)
	self._revealStartCF = startCF
	self._revealMidCF = midCF
	self._revealEndCF = endCF
	self._revealStartFov = cam.FieldOfView
	self._revealEndFov = 62
end

function LoadingStoryCamera:playGameplayDrop(duration: number)
	if not self._active then
		return
	end
	local cam = getCamera()
	if not cam then
		return
	end
	local root = self:_measure()
	local startCF = cam.CFrame
	local endCF = startCF + Vector3.new(0, -14, 0)
	if root then
		startCF = getBehindRevealCFrame(root, 22, 18)
		endCF = getBehindRevealCFrame(root, 4.2, 11)
		cam.CFrame = startCF
	end
	self._revealMode = "gameplay_drop"
	self._revealElapsed = 0
	self._revealDuration = math.max(duration, 0.05)
	self._revealStartCF = startCF
	self._revealMidCF = nil
	self._revealEndCF = endCF
	self._revealStartFov = cam.FieldOfView
	self._revealEndFov = DEFAULT_FOV
end

function LoadingStoryCamera:start()
	if self._active then
		return
	end
	self._active = true
	self._elapsed = 0
	self._phase = "establish"
	self._shotIndex = 0
	self._shotElapsed = 0
	self._stage = nil
	self._body = nil
	self._establish = nil
	self._revealMode = nil
	local cam = getCamera()
	if cam then
		-- Read the default camera's zoom and pitch BEFORE taking over: that is what the player
		-- gets back, and the orbit lands on it (_updateLanding).
		if cam.CameraType == Enum.CameraType.Custom then
			local offset = cam.CFrame.Position - cam.Focus.Position
			local zoom = offset.Magnitude
			local pitch = math.asin(math.clamp(cam.CFrame.LookVector.Y, -1, 1))
			if zoom >= 4 and zoom <= 40 then
				self._landZoom = zoom
			end
			if pitch >= math.rad(-70) and pitch <= math.rad(20) then
				self._landPitch = pitch
			end
		end
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CameraSubject = nil
	end
	if not self._bound then
		self._bound = true
		RunService:BindToRenderStep(BIND_NAME, BIND_PRIORITY, function(dt)
			self:_step(dt)
		end)
	end
end

function LoadingStoryCamera:stop()
	if not self._active and not self._bound then
		return
	end
	self._active = false
	if self._bound then
		RunService:UnbindFromRenderStep(BIND_NAME)
		self._bound = false
	end
	local cam = getCamera()
	if cam then
		pcall(function()
			-- Hand over on the player's saved FOV (published by SettingsController), not the default.
			local savedFov = self._player:GetAttribute("HazaSettingsFov")
			cam.FieldOfView = if type(savedFov) == "number" then savedFov else DEFAULT_FOV
			cam.CameraType = Enum.CameraType.Custom
			local character = self._player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				cam.CameraSubject = humanoid
			end
		end)
	end
	self._establish = nil
	self._stage = nil
	self._revealMode = nil
end

function LoadingStoryCamera:destroy()
	self:stop()
end

return LoadingStoryCamera
