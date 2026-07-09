--!strict
-- Registry of cinematic camera modes for the cinematic dock.
--
-- Each mode is a pure-ish definition that the camera system dispatches to.
-- Character modes operate on a (root, head) pair; part modes operate on a
-- single BasePart (CCTV).
--
-- A mode's `update` is called every RenderStepped with the persistent state
-- table. Modes may use any fields on the state table for their own bookkeeping
-- (e.g. accumulated angles), as long as they don't collide with the reserved
-- fields `t` and `speed`.
--
-- Registering modes here is a data-only operation; the camera system reads
-- this module to know what's available.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local CinematicCameraModes = {}
local cctvCfg = Config.CinematicDock

export type ModeState = {
	t: number,
	speed: number,
	[string]: any,
}

export type CharacterMode = {
	label: string,
	transitionTime: number?,
	lerpSpeed: number?,
	init: ((state: ModeState, root: BasePart, head: BasePart) -> ())?,
	update: (state: ModeState, dt: number, root: BasePart, head: BasePart) -> (CFrame, number),
}

export type PartMode = {
	label: string,
	transitionTime: number?,
	lerpSpeed: number?,
	init: ((state: ModeState, part: BasePart) -> ())?,
	update: (state: ModeState, dt: number, part: BasePart) -> (CFrame, number),
}

-- ── Easing helpers ──────────────────────────────────────────
local function easeInOutSine(x: number): number
	return -(math.cos(math.pi * x) - 1) / 2
end

-- ── Character-relative framing (face the subject, not the backpack) ──
local function flatOnXZ(v: Vector3): Vector3
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude < 1e-4 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function characterAxes(root: BasePart): (Vector3, Vector3)
	local look = flatOnXZ(root.CFrame.LookVector)
	local right = flatOnXZ(root.CFrame.RightVector)
	if right:Dot(look) > 0.99 then
		right = Vector3.new(1, 0, 0)
	end
	return look, right
end

-- angle 0 = in front of subject; π = behind
local function characterOrbitPosition(root: BasePart, angle: number, radius: number, height: number): Vector3
	local look, right = characterAxes(root)
	local offset = look * (radius * math.cos(angle)) + right * (radius * math.sin(angle))
	return root.Position + offset + Vector3.new(0, height, 0)
end

local function inFrontOfSubject(root: BasePart, head: BasePart, distance: number, heightBias: number): Vector3
	local look = flatOnXZ(root.CFrame.LookVector)
	return head.Position + look * distance + Vector3.new(0, heightBias, 0)
end

local function threeQuarterFront(root: BasePart, head: BasePart, distance: number, sideBias: number): Vector3
	local look, right = characterAxes(root)
	return head.Position + look * (distance * 0.82) + right * (distance * 0.38 * sideBias) + Vector3.new(0, 1.2, 0)
end

local function behindSubject(root: BasePart, head: BasePart, distance: number, heightBias: number): Vector3
	local look = flatOnXZ(root.CFrame.LookVector)
	return head.Position - look * distance + Vector3.new(0, heightBias, 0)
end

local function characterLocalOffset(root: BasePart, localX: number, localZ: number, height: number): Vector3
	local look, right = characterAxes(root)
	return root.Position + look * localX + right * localZ + Vector3.new(0, height, 0)
end

-- ============================================================
-- CHARACTER MODES
-- ============================================================

local Character: { [string]: CharacterMode } = {}

-- 1. Pendulum Orbit (existing) ── classic swinging arc orbit
Character.PendulumOrbit = {
	label = "Pendulum Orbit",
	transitionTime = 0.45,
	lerpSpeed = 8,
	update = function(s, dt, root, _head)
		s.t += dt * s.speed
		local r = 8 + math.sin(s.t * 0.6) * 6
		local h = 3 + math.sin(s.t * 0.4) * 3
		local pos = characterOrbitPosition(root, s.t * 0.5, r, h)
		local cf = CFrame.lookAt(pos, root.Position + Vector3.new(0, 2, 0))
		return cf * CFrame.Angles(0, 0, math.sin(s.t * 0.6) * 0.18), 70
	end,
}

-- 2. Donation Orbit (existing) ── slower, wider, more cinematic
Character.DonationOrbit = {
	label = "Donation Orbit",
	transitionTime = 1.1,
	lerpSpeed = 4.5,
	update = function(s, dt, root, head)
		s.t += dt * 0.28 * s.speed
		local radius = 18 + math.sin(s.t * 0.45) * 2.5
		local heightOffset = math.sin(s.t * 0.35) * 0.75
		local planar = characterOrbitPosition(root, s.t * 0.42, radius, 0)
		local pos = Vector3.new(planar.X, head.Position.Y + heightOffset, planar.Z)
		local cf = CFrame.lookAt(pos, head.Position)
		return cf * CFrame.Angles(0, 0, math.sin(s.t * 0.5) * 0.055), 54
	end,
}

-- 3. Slow Orbit ── steady, contemplative full orbit
Character.SlowOrbit = {
	label = "Slow Orbit",
	transitionTime = 0.8,
	lerpSpeed = 5,
	update = function(s, dt, root, _head)
		s.t += dt * s.speed
		local pos = characterOrbitPosition(root, s.t * 0.25, 10, 4)
		return CFrame.lookAt(pos, root.Position + Vector3.new(0, 2, 0)), 60
	end,
}

-- 4. Fast Orbit ── tight, energetic spin
Character.FastOrbit = {
	label = "Fast Orbit",
	transitionTime = 0.3,
	lerpSpeed = 11,
	update = function(s, dt, root, _head)
		s.t += dt * s.speed
		local pos = characterOrbitPosition(root, s.t * 1.6, 6, 3)
		return CFrame.lookAt(pos, root.Position + Vector3.new(0, 2, 0)), 75
	end,
}

-- 5. High Orbit ── lifted angle looking down
Character.HighOrbit = {
	label = "High Orbit",
	transitionTime = 0.7,
	lerpSpeed = 6,
	update = function(s, dt, root, _head)
		s.t += dt * s.speed
		local pos = characterOrbitPosition(root, s.t * 0.35, 13, 16)
		return CFrame.lookAt(pos, root.Position + Vector3.new(0, 1, 0)), 65
	end,
}

-- 6. Low Orbit ── dramatic ground-level sweep
Character.LowOrbit = {
	label = "Low Orbit",
	transitionTime = 0.55,
	lerpSpeed = 7,
	update = function(s, dt, root, _head)
		s.t += dt * s.speed
		local h = 0.6 + math.sin(s.t * 0.3) * 0.25
		local pos = characterOrbitPosition(root, s.t * 0.45, 9, h)
		return CFrame.lookAt(pos, root.Position + Vector3.new(0, 2.5, 0)), 78
	end,
}

-- 7. Dolly In ── smoothly approach the subject from a fixed direction
Character.DollyIn = {
	label = "Dolly In",
	transitionTime = 0.7,
	lerpSpeed = 5,
	init = function(s, root, _head)
		s.dollyDir = flatOnXZ(root.CFrame.LookVector)
		s.dollyMaxDist = 22
		s.dollyMinDist = 4
	end,
	update = function(s, dt, root, head)
		s.t += dt * s.speed
		local progress = math.clamp(s.t / 14, 0, 1)
		local distance = s.dollyMaxDist + (s.dollyMinDist - s.dollyMaxDist) * easeInOutSine(progress)
		local pos = head.Position + s.dollyDir * distance + Vector3.new(0, 1.5, 0)
		return CFrame.lookAt(pos, head.Position), 55
	end,
}

-- 8. Dolly Out ── slow pull-back from a tight start
Character.DollyOut = {
	label = "Dolly Out",
	transitionTime = 0.7,
	lerpSpeed = 5,
	init = function(s, root, _head)
		s.dollyDir = flatOnXZ(root.CFrame.LookVector)
	end,
	update = function(s, dt, root, head)
		s.t += dt * s.speed
		local progress = math.clamp(s.t / 14, 0, 1)
		local distance = 4 + (24 - 4) * easeInOutSine(progress)
		local pos = head.Position + s.dollyDir * distance + Vector3.new(0, 1.5, 0)
		return CFrame.lookAt(pos, head.Position), 60
	end,
}

-- 9. Truck Left ── lateral pan along a static axis
Character.TruckLeft = {
	label = "Truck Left",
	transitionTime = 0.6,
	lerpSpeed = 6,
	init = function(s, root, _head)
		local _, right = characterAxes(root)
		s.truckRight = right
		s.truckFront = flatOnXZ(root.CFrame.LookVector)
	end,
	update = function(s, dt, root, head)
		s.t += dt * s.speed
		local lateral = math.sin(s.t * 0.35) * 8
		local pos = head.Position + s.truckRight * lateral + s.truckFront * 10 + Vector3.new(0, 1.5, 0)
		return CFrame.lookAt(pos, head.Position), 60
	end,
}

-- 10. Truck Right ── mirrored lateral pan
Character.TruckRight = {
	label = "Truck Right",
	transitionTime = 0.6,
	lerpSpeed = 6,
	init = function(s, root, _head)
		local _, right = characterAxes(root)
		s.truckRight = right
		s.truckFront = flatOnXZ(root.CFrame.LookVector)
	end,
	update = function(s, dt, root, head)
		s.t += dt * s.speed
		local lateral = -math.sin(s.t * 0.35) * 8
		local pos = head.Position + s.truckRight * lateral + s.truckFront * 10 + Vector3.new(0, 1.5, 0)
		return CFrame.lookAt(pos, head.Position), 60
	end,
}

-- 11. Crane Up ── rising vertical sweep
Character.CraneUp = {
	label = "Crane Up",
	transitionTime = 0.7,
	lerpSpeed = 5,
	init = function(s, root, _head)
		s.craneFront = flatOnXZ(root.CFrame.LookVector)
	end,
	update = function(s, dt, root, _head)
		s.t += dt * s.speed
		local progress = math.clamp(s.t / 12, 0, 1)
		local h = 1.5 + (14 - 1.5) * easeInOutSine(progress)
		local pos = root.Position + s.craneFront * 14 + Vector3.new(0, h, 0)
		return CFrame.lookAt(pos, root.Position + Vector3.new(0, 2, 0)), 62
	end,
}

-- 12. Crane Down ── descending vertical sweep
Character.CraneDown = {
	label = "Crane Down",
	transitionTime = 0.7,
	lerpSpeed = 5,
	init = function(s, root, _head)
		s.craneFront = flatOnXZ(root.CFrame.LookVector)
	end,
	update = function(s, dt, root, _head)
		s.t += dt * s.speed
		local progress = math.clamp(s.t / 12, 0, 1)
		local h = 14 + (1.5 - 14) * easeInOutSine(progress)
		local pos = root.Position + s.craneFront * 14 + Vector3.new(0, h, 0)
		return CFrame.lookAt(pos, root.Position + Vector3.new(0, 2, 0)), 62
	end,
}

-- 13. Close Up ── locked tight on head with subtle drift
Character.CloseUp = {
	label = "Close Up",
	transitionTime = 0.5,
	lerpSpeed = 7,
	update = function(s, dt, root, head)
		s.t += dt * s.speed
		local drift = Vector3.new(math.sin(s.t * 0.6) * 0.12, math.cos(s.t * 0.5) * 0.08, 0)
		local pos = inFrontOfSubject(root, head, 3, 0.2) + drift
		return CFrame.lookAt(pos, head.Position), 48
	end,
}

-- 14. Wide Shot ── pulled-back establishing frame
Character.WideShot = {
	label = "Wide Shot",
	transitionTime = 0.8,
	lerpSpeed = 4,
	init = function(s, _root, _head)
		s.wideSide = 1
	end,
	update = function(s, dt, root, head)
		s.t += dt * s.speed
		local breathe = Vector3.new(0, math.sin(s.t * 0.25) * 0.4, 0)
		local pos = threeQuarterFront(root, head, 28, s.wideSide or 1) + Vector3.new(0, 6.5, 0) + breathe
		return CFrame.lookAt(pos, root.Position + Vector3.new(0, 1, 0)), 80
	end,
}

-- 15. Over The Shoulder ── classic OTS framing
Character.OverShoulder = {
	label = "Over The Shoulder",
	transitionTime = 0.55,
	lerpSpeed = 6,
	init = function(s, root, _head)
		s.otsBack = -root.CFrame.LookVector
		s.otsRight = root.CFrame.RightVector
	end,
	update = function(s, dt, _root, head)
		s.t += dt * s.speed
		local sway = math.sin(s.t * 0.5) * 0.1
		local pos = head.Position + s.otsBack * 3.5 + s.otsRight * 1.6 + Vector3.new(0, 0.6 + sway, 0)
		local lookTarget = head.Position + (-s.otsBack) * 6
		return CFrame.lookAt(pos, lookTarget), 58
	end,
}

-- 16. Point Of View ── first-person from the head with walk bob
Character.PointOfView = {
	label = "Point Of View",
	transitionTime = 0.4,
	lerpSpeed = 9,
	update = function(s, dt, _root, head)
		s.t += dt * s.speed
		local bob = Vector3.new(0, math.sin(s.t * 4) * 0.05, 0)
		local pos = head.Position + Vector3.new(0, 0.15, 0) + bob
		local lookTarget = pos + head.CFrame.LookVector * 10
		return CFrame.lookAt(pos, lookTarget), 75
	end,
}

-- 17. Worm's Eye ── extreme low angle looking up
Character.WormsEye = {
	label = "Worm's Eye",
	transitionTime = 0.6,
	lerpSpeed = 6,
	update = function(s, dt, root, head)
		s.t += dt * s.speed
		local sway = math.sin(s.t * 0.4) * 0.5
		local pos = inFrontOfSubject(root, head, 5, -1.5) + Vector3.new(sway, 0, 0)
		return CFrame.lookAt(pos, head.Position + Vector3.new(0, 0.5, 0)), 72
	end,
}

-- 18. Bird's Eye ── top-down with gentle drift
Character.BirdsEye = {
	label = "Bird's Eye",
	transitionTime = 0.7,
	lerpSpeed = 5,
	update = function(s, dt, root, _head)
		s.t += dt * s.speed
		local drift = Vector3.new(math.sin(s.t * 0.3) * 1.5, 0, math.cos(s.t * 0.3) * 1.5)
		local pos = root.Position + Vector3.new(0, 22, 0) + drift
		return CFrame.lookAt(pos, root.Position), 60
	end,
}

-- 19. Dutch Angle ── orbit with sustained roll for unease
Character.DutchAngle = {
	label = "Dutch Angle",
	transitionTime = 0.6,
	lerpSpeed = 6,
	update = function(s, dt, root, _head)
		s.t += dt * s.speed
		local pos = characterOrbitPosition(root, s.t * 0.4, 8, 4)
		local cf = CFrame.lookAt(pos, root.Position + Vector3.new(0, 2, 0))
		return cf * CFrame.Angles(0, 0, math.rad(18) + math.sin(s.t * 0.5) * 0.05), 65
	end,
}

-- 20. Handheld ── shaky, organic camera operator feel
Character.Handheld = {
	label = "Handheld",
	transitionTime = 0.4,
	lerpSpeed = 9,
	init = function(s, root, _head)
		s.handheldSide = 1
	end,
	update = function(s, dt, root, head)
		s.t += dt * s.speed
		local jitterX = math.sin(s.t * 7.3) * 0.18 + math.sin(s.t * 13.1) * 0.07
		local jitterY = math.cos(s.t * 6.7) * 0.14 + math.cos(s.t * 11.3) * 0.06
		local jitterZ = math.sin(s.t * 5.1) * 0.05
		local pos = threeQuarterFront(root, head, 5.5, s.handheldSide or 1) + Vector3.new(jitterX, jitterY, jitterZ)
		local cf = CFrame.lookAt(pos, head.Position)
		return cf * CFrame.Angles(0, 0, math.sin(s.t * 4.2) * 0.04), 62
	end,
}

-- 21. Drift ── gentle floating with drifting orbit angle
Character.Drift = {
	label = "Drift",
	transitionTime = 0.9,
	lerpSpeed = 4,
	update = function(s, dt, root, _head)
		s.t += dt * s.speed
		local angle = math.sin(s.t * 0.18) * 1.2
		local r = 9 + math.sin(s.t * 0.22) * 2
		local h = 4 + math.cos(s.t * 0.16) * 1.5
		local pos = characterOrbitPosition(root, angle, r, h)
		return CFrame.lookAt(pos, root.Position + Vector3.new(0, 2, 0)), 58
	end,
}

-- 22. Zoom Burst ── rapid in/out FOV pulse around fixed framing
Character.ZoomBurst = {
	label = "Zoom Burst",
	transitionTime = 0.4,
	lerpSpeed = 9,
	update = function(s, dt, root, head)
		s.t += dt * s.speed
		local pos = inFrontOfSubject(root, head, 8, 1)
		local fov = 55 + math.sin(s.t * 1.6) * 18
		return CFrame.lookAt(pos, head.Position), fov
	end,
}

-- 23. Vertigo ── dolly zoom (Hitchcock effect)
Character.Vertigo = {
	label = "Vertigo",
	transitionTime = 0.7,
	lerpSpeed = 5,
	update = function(s, dt, root, head)
		s.t += dt * s.speed
		local cycle = math.sin(s.t * 0.4)
		local distance = 10 + cycle * 6
		local fov = 65 - cycle * 25
		local pos = inFrontOfSubject(root, head, distance, 1)
		return CFrame.lookAt(pos, head.Position), fov
	end,
}

-- 24. Heartbeat ── rhythmic distance pulse
Character.Heartbeat = {
	label = "Heartbeat",
	transitionTime = 0.5,
	lerpSpeed = 7,
	update = function(s, dt, root, head)
		s.t += dt * s.speed
		local pulse = math.abs(math.sin(s.t * 1.3)) * 1.4
		local pos = inFrontOfSubject(root, head, 6 + pulse, 0.8)
		return CFrame.lookAt(pos, head.Position), 58 + pulse * 2
	end,
}

-- 25. Spiral In ── descending corkscrew approach
Character.SpiralIn = {
	label = "Spiral In",
	transitionTime = 0.7,
	lerpSpeed = 5,
	update = function(s, dt, root, _head)
		s.t += dt * s.speed
		local progress = math.clamp(s.t / 16, 0, 1)
		local r = 16 + (5 - 16) * easeInOutSine(progress)
		local h = 12 + (3 - 12) * easeInOutSine(progress)
		local pos = characterOrbitPosition(root, s.t * 0.7, r, h)
		return CFrame.lookAt(pos, root.Position + Vector3.new(0, 2, 0)), 60
	end,
}

-- 26. Spiral Out ── ascending corkscrew retreat
Character.SpiralOut = {
	label = "Spiral Out",
	transitionTime = 0.7,
	lerpSpeed = 5,
	update = function(s, dt, root, _head)
		s.t += dt * s.speed
		local progress = math.clamp(s.t / 16, 0, 1)
		local r = 5 + (18 - 5) * easeInOutSine(progress)
		local h = 3 + (14 - 3) * easeInOutSine(progress)
		local pos = characterOrbitPosition(root, s.t * 0.7, r, h)
		return CFrame.lookAt(pos, root.Position + Vector3.new(0, 2, 0)), 60
	end,
}

-- 27. Figure Eight ── lemniscate path around subject
Character.FigureEight = {
	label = "Figure Eight",
	transitionTime = 0.6,
	lerpSpeed = 6,
	update = function(s, dt, root, _head)
		s.t += dt * s.speed
		local a = s.t * 0.4
		local denom = 1 + math.sin(a) * math.sin(a)
		local x = (10 * math.cos(a)) / denom
		local z = (10 * math.sin(a) * math.cos(a)) / denom
		local pos = characterLocalOffset(root, x, z, 4)
		return CFrame.lookAt(pos, root.Position + Vector3.new(0, 2, 0)), 62
	end,
}

-- 28. Helix ── stacked orbits at varying heights
Character.Helix = {
	label = "Helix",
	transitionTime = 0.6,
	lerpSpeed = 6,
	update = function(s, dt, root, _head)
		s.t += dt * s.speed
		local h = 2 + (math.sin(s.t * 0.4) * 0.5 + 0.5) * 12
		local pos = characterOrbitPosition(root, s.t * 0.55, 9, h)
		return CFrame.lookAt(pos, root.Position + Vector3.new(0, 2, 0)), 62
	end,
}

-- 29. Chase Cam ── tight third-person follow
Character.ChaseCam = {
	label = "Chase Cam",
	transitionTime = 0.4,
	lerpSpeed = 9,
	update = function(s, dt, root, head)
		s.t += dt * s.speed
		local sway = math.sin(s.t * 0.6) * 0.4
		local pos = behindSubject(root, head, 5, 1.2) + Vector3.new(sway, 0, 0)
		local look = flatOnXZ(root.CFrame.LookVector)
		local lookTarget = head.Position + look * 8 + Vector3.new(0, -0.3, 0)
		return CFrame.lookAt(pos, lookTarget), 70
	end,
}

-- 30. Drone Flyby ── high-speed pass with curved path
Character.DroneFlyby = {
	label = "Drone Flyby",
	transitionTime = 0.5,
	lerpSpeed = 7,
	update = function(s, dt, root, _head)
		s.t += dt * s.speed
		local r = 14 + math.sin(s.t * 0.5) * 4
		local h = 7 + math.cos(s.t * 0.7) * 3
		local pos = characterOrbitPosition(root, s.t * 0.9, r, h)
		local cf = CFrame.lookAt(pos, root.Position + Vector3.new(0, 1.5, 0))
		return cf * CFrame.Angles(0, 0, math.sin(s.t * 0.8) * 0.12), 68
	end,
}

-- 31. Earthquake ── violent multi-axis shake
Character.Earthquake = {
	label = "Earthquake",
	transitionTime = 0.4,
	lerpSpeed = 9,
	init = function(s, root, _head)
		s.quakeSide = -1
	end,
	update = function(s, dt, root, head)
		s.t += dt * s.speed
		local shakeX = math.sin(s.t * 23) * 0.6 + math.sin(s.t * 41) * 0.3
		local shakeY = math.cos(s.t * 27) * 0.5 + math.cos(s.t * 37) * 0.25
		local shakeZ = math.sin(s.t * 19) * 0.4
		local pos = threeQuarterFront(root, head, 7, s.quakeSide or -1) + Vector3.new(shakeX, shakeY, shakeZ)
		local cf = CFrame.lookAt(pos, head.Position)
		return cf * CFrame.Angles(shakeY * 0.05, shakeX * 0.05, math.sin(s.t * 31) * 0.08), 64
	end,
}

-- 32. Noir Shadow ── moody side angle, slow drift
Character.NoirShadow = {
	label = "Noir Shadow",
	transitionTime = 1.0,
	lerpSpeed = 4,
	init = function(s, root, _head)
		local _, right = characterAxes(root)
		s.noirRight = right
		s.noirFront = flatOnXZ(root.CFrame.LookVector)
	end,
	update = function(s, dt, _root, head)
		s.t += dt * s.speed
		local sway = math.sin(s.t * 0.2) * 0.6
		local pos = head.Position + s.noirRight * (5 + sway) + s.noirFront * 3 + Vector3.new(0, 0.3, 0)
		local cf = CFrame.lookAt(pos, head.Position)
		return cf * CFrame.Angles(0, 0, math.rad(8)), 50
	end,
}

-- 33. Romantic Glide ── slow elegant arc with soft FOV
Character.RomanticGlide = {
	label = "Romantic Glide",
	transitionTime = 1.2,
	lerpSpeed = 3.5,
	update = function(s, dt, root, head)
		s.t += dt * 0.4 * s.speed
		local r = 7 + math.sin(s.t * 0.2) * 1.5
		local h = 2.5 + math.sin(s.t * 0.25) * 0.6
		local pos = characterOrbitPosition(root, s.t * 0.3, r, h)
		local lookTarget = head.Position + Vector3.new(0, -0.2, 0)
		local cf = CFrame.lookAt(pos, lookTarget)
		return cf * CFrame.Angles(0, 0, math.sin(s.t * 0.3) * 0.04), 50
	end,
}

-- 34. Epic Reveal ── dramatic pull-back from extreme close-up
Character.EpicReveal = {
	label = "Epic Reveal",
	transitionTime = 0.9,
	lerpSpeed = 4,
	init = function(s, root, _head)
		s.revealFront = flatOnXZ(root.CFrame.LookVector)
	end,
	update = function(s, dt, root, head)
		s.t += dt * s.speed
		local progress = math.clamp(s.t / 18, 0, 1)
		local distance = 2 + (28 - 2) * easeInOutSine(progress)
		local height = 0.8 + (10 - 0.8) * easeInOutSine(progress)
		local pos = head.Position + s.revealFront * distance + Vector3.new(0, height, 0)
		local fov = 45 + (75 - 45) * progress
		return CFrame.lookAt(pos, root.Position + Vector3.new(0, 1.5, 0)), fov
	end,
}

-- 35. Music Video Spin ── flashy fast-spin with FOV pulse
Character.MusicVideoSpin = {
	label = "Music Video Spin",
	transitionTime = 0.4,
	lerpSpeed = 9,
	update = function(s, dt, root, _head)
		s.t += dt * s.speed
		local r = 6 + math.sin(s.t * 1.2) * 1.5
		local h = 3 + math.cos(s.t * 1.0) * 1
		local pos = characterOrbitPosition(root, s.t * 2.4, r, h)
		local cf = CFrame.lookAt(pos, root.Position + Vector3.new(0, 2, 0))
		local fov = 65 + math.sin(s.t * 2) * 8
		return cf * CFrame.Angles(0, 0, math.sin(s.t * 1.5) * 0.15), fov
	end,
}

-- ============================================================
-- PART MODES (CCTV / static rigs)
-- ============================================================

local Part: { [string]: PartMode } = {}

-- CCTV parts are usually static anchors, but their replicated CFrame can still
-- wobble slightly client-side. Smooth tiny changes to avoid visible camera jitter,
-- while still snapping quickly when the rig actually moves/rotates.
local function sampleStablePartCFrame(state: ModeState, part: BasePart): CFrame
	local live = part.CFrame
	local cached = state._stablePartCFrame
	if typeof(cached) ~= "CFrame" then
		state._stablePartCFrame = live
		return live
	end

	local positionDelta = (live.Position - cached.Position).Magnitude
	local lookDelta = 1 - math.clamp(live.LookVector:Dot(cached.LookVector), -1, 1)
	local upDelta = 1 - math.clamp(live.UpVector:Dot(cached.UpVector), -1, 1)

	-- Big motion = follow immediately; micro drift = smooth.
	if positionDelta > 2.5 or lookDelta > 0.08 or upDelta > 0.08 then
		state._stablePartCFrame = live
		return live
	end

	local smoothed = cached:Lerp(live, 0.14)
	state._stablePartCFrame = smoothed
	return smoothed
end

local function getCCTVStandOff(part: BasePart, extraBack: number?): number
	-- Keep camera outside the CCTV rig volume so transition never clips through.
	local halfDepth = math.max(part.Size.Z * 0.5, 0.15)
	local margin = 0.35 + (extraBack or 0)
	return halfDepth + margin
end

-- 36. CCTV View (existing) ── locked surveillance with subtle sway
Part.CCTVView = {
	label = "CCTV View",
	transitionTime = 0.9,
	lerpSpeed = 5,
	init = function(state, part)
		state._stablePartCFrame = part.CFrame
	end,
	update = function(s, dt, part)
		s.t += dt * s.speed
		local base = sampleStablePartCFrame(s, part)
		local back = getCCTVStandOff(part, 0)
		local yOffset = 0.15 + math.sin(s.t * 0.45) * 0.04
		local localOffset = Vector3.new(0, yOffset, -back)
		local position = (base * CFrame.new(localOffset)).Position
		local lookTarget = position + base.LookVector * 40 + base.UpVector * math.sin(s.t * 0.3) * 0.4
		local cf = CFrame.lookAt(position, lookTarget, base.UpVector)
		return cf * CFrame.Angles(0, 0, math.sin(s.t * 0.5) * 0.015), 58
	end,
}

-- 37. CCTV Pan ── horizontal sweep mimicking PTZ camera
Part.CCTVPan = {
	label = "CCTV Pan",
	transitionTime = 1.0,
	lerpSpeed = 4,
	init = function(state, part)
		state._stablePartCFrame = part.CFrame
	end,
	update = function(s, dt, part)
		s.t += dt * s.speed
		local base = sampleStablePartCFrame(s, part)
		local panAngle = math.sin(s.t * 0.25) * math.rad(30)
		local position = (base * CFrame.new(0, 0.15, -getCCTVStandOff(part, 0.05))).Position
		local rotated = base * CFrame.Angles(0, panAngle, 0)
		local lookTarget = position + rotated.LookVector * 40
		return CFrame.lookAt(position, lookTarget, base.UpVector), 60
	end,
}

-- 38. CCTV Zoom ── slow zoom-in over time, then reset
Part.CCTVZoom = {
	label = "CCTV Zoom",
	transitionTime = 1.0,
	lerpSpeed = 4,
	init = function(state, part)
		state._stablePartCFrame = part.CFrame
	end,
	update = function(s, dt, part)
		s.t += dt * s.speed
		local base = sampleStablePartCFrame(s, part)
		local cycle = (math.sin(s.t * 0.18) + 1) * 0.5
		local fov = 65 - cycle * 35
		local position = (base * CFrame.new(0, 0.15, -getCCTVStandOff(part, 0.05))).Position
		local lookTarget = position + base.LookVector * 40
		return CFrame.lookAt(position, lookTarget, base.UpVector), fov
	end,
}

-- 39. CCTV Static ── completely locked, no motion (max realism)
Part.CCTVStatic = {
	label = "CCTV Static",
	transitionTime = 0.7,
	lerpSpeed = 12,
	init = function(state, part)
		state._stablePartCFrame = part.CFrame
	end,
	update = function(s, _dt, part)
		local base = sampleStablePartCFrame(s, part)
		local position = (base * CFrame.new(0, 0.15, -getCCTVStandOff(part, 0.02))).Position
		local lookTarget = position + base.LookVector * 40
		return CFrame.lookAt(position, lookTarget, base.UpVector), 56
	end,
}

-- 40. CCTV Glitch ── interference jitter pattern
Part.CCTVGlitch = {
	label = "CCTV Glitch",
	transitionTime = 0.6,
	lerpSpeed = 8,
	init = function(state, part)
		state._stablePartCFrame = part.CFrame
	end,
	update = function(s, dt, part)
		s.t += dt * s.speed
		local base = sampleStablePartCFrame(s, part)
		local burst = math.floor(s.t * 0.7) % 3 == 0
		local glitchX = if burst then (math.sin(s.t * 53) * 0.18) else 0
		local glitchY = if burst then (math.cos(s.t * 47) * 0.12) else 0
		local position = (base * CFrame.new(glitchX, 0.15 + glitchY, -getCCTVStandOff(part, 0.08))).Position
		local lookTarget = position + base.LookVector * 40
		local cf = CFrame.lookAt(position, lookTarget, base.UpVector)
		local roll = if burst then math.sin(s.t * 41) * 0.04 else 0
		return cf * CFrame.Angles(0, 0, roll), 58
	end,
}

-- 41. CCTV Tilt ── vertical nod like a PTZ tilt motor
Part.CCTVTilt = {
	label = "CCTV Tilt",
	transitionTime = 1.0,
	lerpSpeed = 4,
	init = function(state, part)
		state._stablePartCFrame = part.CFrame
	end,
	update = function(s, dt, part)
		s.t += dt * s.speed
		local base = sampleStablePartCFrame(s, part)
		local tiltAngle = math.sin(s.t * 0.22) * math.rad(20)
		local position = (base * CFrame.new(0, 0.15, -getCCTVStandOff(part, 0.04))).Position
		local rotated = base * CFrame.Angles(tiltAngle, 0, 0)
		local lookTarget = position + rotated.LookVector * 42
		return CFrame.lookAt(position, lookTarget, base.UpVector), 60
	end,
}

-- 42. CCTV PanTilt ── combined horizontal + vertical scan
Part.CCTVPanTilt = {
	label = "CCTV Pan + Tilt",
	transitionTime = 1.1,
	lerpSpeed = 4,
	init = function(state, part)
		state._stablePartCFrame = part.CFrame
	end,
	update = function(s, dt, part)
		s.t += dt * s.speed
		local base = sampleStablePartCFrame(s, part)
		local pan = math.sin(s.t * 0.24) * math.rad(26)
		local tilt = math.cos(s.t * 0.19) * math.rad(14)
		local position = (base * CFrame.new(0, 0.15, -getCCTVStandOff(part, 0.06))).Position
		local rotated = base * CFrame.Angles(tilt, pan, 0)
		local lookTarget = position + rotated.LookVector * 44
		return CFrame.lookAt(position, lookTarget, base.UpVector), 61
	end,
}

-- 43. CCTV SweepWide ── wider patrol arc with slower cadence
Part.CCTVSweepWide = {
	label = "CCTV Sweep Wide",
	transitionTime = 1.2,
	lerpSpeed = 3.8,
	init = function(state, part)
		state._stablePartCFrame = part.CFrame
	end,
	update = function(s, dt, part)
		s.t += dt * s.speed
		local base = sampleStablePartCFrame(s, part)
		local panAngle = math.sin(s.t * 0.16) * math.rad(48)
		local position = (base * CFrame.new(0, 0.15, -getCCTVStandOff(part, 0.1))).Position
		local rotated = base * CFrame.Angles(0, panAngle, 0)
		local lookTarget = position + rotated.LookVector * 50
		return CFrame.lookAt(position, lookTarget, base.UpVector), 66
	end,
}

-- 44. CCTV MicroShake ── subtle noisy vibration like old motor rig
Part.CCTVMicroShake = {
	label = "CCTV Micro Shake",
	transitionTime = 0.8,
	lerpSpeed = 6,
	init = function(state, part)
		state._stablePartCFrame = part.CFrame
	end,
	update = function(s, dt, part)
		s.t += dt * s.speed
		local base = sampleStablePartCFrame(s, part)
		local jitterX = math.sin(s.t * 8.1) * 0.03 + math.sin(s.t * 15.7) * 0.02
		local jitterY = math.cos(s.t * 7.6) * 0.025 + math.cos(s.t * 13.9) * 0.018
		local roll = math.sin(s.t * 6.4) * 0.008
		local position = (base * CFrame.new(jitterX, 0.15 + jitterY, -getCCTVStandOff(part, 0.05))).Position
		local lookTarget = position + base.LookVector * 40
		local cf = CFrame.lookAt(position, lookTarget, base.UpVector)
		return cf * CFrame.Angles(0, 0, roll), 58
	end,
}

-- 45. CCTV PushIn ── periodic push-in and pull-back lens feel
Part.CCTVPushIn = {
	label = "CCTV Push In",
	transitionTime = 1.0,
	lerpSpeed = 4.5,
	init = function(state, part)
		state._stablePartCFrame = part.CFrame
	end,
	update = function(s, dt, part)
		s.t += dt * s.speed
		local base = sampleStablePartCFrame(s, part)
		local cycle = (math.sin(s.t * 0.2) + 1) * 0.5
		local baseStandOff = getCCTVStandOff(part, 0.08)
		local localZ = -(baseStandOff + 0.18) + cycle * 0.38
		local position = (base * CFrame.new(0, 0.15, localZ)).Position
		local lookTarget = position + base.LookVector * 42
		local fov = 64 - cycle * 14
		return CFrame.lookAt(position, lookTarget, base.UpVector), fov
	end,
}

-- 46. CCTV FocusPulse ── locked view with breathing focus/FOV pulse
Part.CCTVFocusPulse = {
	label = "CCTV Focus Pulse",
	transitionTime = 0.9,
	lerpSpeed = 5,
	init = function(state, part)
		state._stablePartCFrame = part.CFrame
	end,
	update = function(s, dt, part)
		s.t += dt * s.speed
		local base = sampleStablePartCFrame(s, part)
		local position = (base * CFrame.new(0, 0.15, -getCCTVStandOff(part, 0.03))).Position
		local lookTarget = position + base.LookVector * 40
		local pulse = math.sin(s.t * 0.9) * 0.5 + math.sin(s.t * 0.35) * 0.5
		local fov = 58 + pulse * 6
		return CFrame.lookAt(position, lookTarget, base.UpVector), fov
	end,
}

-- ============================================================
-- 360 venue rig (center mount, ultra-wide FOV, horizontal sweep)
-- ============================================================

local FOV_360_WIDE = 102
local FOV_360_ULTRA = 110

local function textContains360(text: string): boolean
	return string.find(string.lower(text), "360", 1, true) ~= nil
end

local function get360MountPosition(base: CFrame, part: BasePart): Vector3
	local lift = math.max(part.Size.Y * 0.45, 0.35) + 0.55
	return (base * CFrame.new(0, lift, 0)).Position
end

local function cctv360Look(base: CFrame, mountPos: Vector3, yaw: number, pitch: number, lookDist: number): CFrame
	local aim = base * CFrame.Angles(pitch, yaw, 0)
	local lookTarget = mountPos + aim.LookVector * lookDist
	return CFrame.lookAt(mountPos, lookTarget, Vector3.yAxis)
end

Part.CCTV360Overview = {
	label = "360 Overview",
	transitionTime = 1.0,
	lerpSpeed = 4.5,
	init = function(state, part)
		state._stablePartCFrame = part.CFrame
	end,
	update = function(s, dt, part)
		s.t += dt * s.speed
		local base = sampleStablePartCFrame(s, part)
		local mountPos = get360MountPosition(base, part)
		local yaw = math.sin(s.t * 0.1) * math.rad(14)
		local pitch = math.sin(s.t * 0.17) * math.rad(4)
		return cctv360Look(base, mountPos, yaw, pitch, 90), 104
	end,
}

Part.CCTV360Spin = {
	label = "360 Spin",
	transitionTime = 1.1,
	lerpSpeed = 4,
	init = function(state, part)
		state._stablePartCFrame = part.CFrame
	end,
	update = function(s, dt, part)
		s.t += dt * s.speed
		local base = sampleStablePartCFrame(s, part)
		local mountPos = get360MountPosition(base, part)
		local yaw = s.t * 0.11
		return cctv360Look(base, mountPos, yaw, 0, 95), FOV_360_WIDE
	end,
}

Part.CCTV360HalfSweep = {
	label = "360 Half Sweep",
	transitionTime = 1.1,
	lerpSpeed = 3.8,
	init = function(state, part)
		state._stablePartCFrame = part.CFrame
	end,
	update = function(s, dt, part)
		s.t += dt * s.speed
		local base = sampleStablePartCFrame(s, part)
		local mountPos = get360MountPosition(base, part)
		local yaw = math.sin(s.t * 0.14) * math.rad(125)
		return cctv360Look(base, mountPos, yaw, 0, 100), 106
	end,
}

Part.CCTV360Patrol = {
	label = "360 Patrol",
	transitionTime = 1.0,
	lerpSpeed = 4,
	init = function(state, part)
		state._stablePartCFrame = part.CFrame
	end,
	update = function(s, dt, part)
		s.t += dt * s.speed
		local base = sampleStablePartCFrame(s, part)
		local mountPos = get360MountPosition(base, part)
		local yaw = math.sin(s.t * 0.11) * math.rad(88)
		local pitch = math.cos(s.t * 0.08) * math.rad(6)
		return cctv360Look(base, mountPos, yaw, pitch, 92), 103
	end,
}

Part.CCTV360Pulse = {
	label = "360 Atmosphere Pulse",
	transitionTime = 0.95,
	lerpSpeed = 4.5,
	init = function(state, part)
		state._stablePartCFrame = part.CFrame
	end,
	update = function(s, dt, part)
		s.t += dt * s.speed
		local base = sampleStablePartCFrame(s, part)
		local mountPos = get360MountPosition(base, part)
		local yaw = math.sin(s.t * 0.06) * math.rad(22)
		local pulse = math.sin(s.t * 0.45) * 0.5 + math.sin(s.t * 0.2) * 0.5
		local fov = 98 + pulse * 12
		return cctv360Look(base, mountPos, yaw, 0, 88), fov
	end,
}

Part.CCTV360StaticWide = {
	label = "360 Static Wide",
	transitionTime = 0.85,
	lerpSpeed = 8,
	init = function(state, part)
		state._stablePartCFrame = part.CFrame
	end,
	update = function(s, _dt, part)
		local base = sampleStablePartCFrame(s, part)
		local mountPos = get360MountPosition(base, part)
		return cctv360Look(base, mountPos, 0, 0, 85), FOV_360_ULTRA
	end,
}

-- ============================================================
-- Public API
-- ============================================================

CinematicCameraModes.Character = Character
CinematicCameraModes.Part = Part
CinematicCameraModes.DefaultCharacterMode = "PendulumOrbit"
CinematicCameraModes.DefaultPartMode = "CCTVView"
CinematicCameraModes.DefaultPart360Mode = "CCTV360Overview"

function CinematicCameraModes.is360CctvPart(part: BasePart): boolean
	local profileAttr = cctvCfg.CCTV_PROFILE_ATTRIBUTE
	if type(profileAttr) == "string" and profileAttr ~= "" then
		local profile = part:GetAttribute(profileAttr)
		if type(profile) == "string" and string.lower(profile) == "360" then
			return true
		end
	end
	local id = part:GetAttribute(cctvCfg.CCTV_ID_ATTRIBUTE)
	if type(id) == "string" and textContains360(id) then
		return true
	end
	local displayName = part:GetAttribute(cctvCfg.CCTV_NAME_ATTRIBUTE)
	if type(displayName) == "string" and textContains360(displayName) then
		return true
	end
	return textContains360(part.Name)
end

function CinematicCameraModes.is360CctvTarget(target: any): boolean
	if type(target) ~= "table" or target.type ~= "cctv" then
		return false
	end
	if type(target.id) == "string" and textContains360(target.id) then
		return true
	end
	if type(target.name) == "string" and textContains360(target.name) then
		return true
	end
	if type(target.path) == "table" then
		for _, segment in ipairs(target.path) do
			if type(segment) == "string" and textContains360(segment) then
				return true
			end
		end
	end
	return false
end

function CinematicCameraModes.getCharacterMode(name: string?): CharacterMode
	local mode = if name then Character[name] else nil
	return mode or Character[CinematicCameraModes.DefaultCharacterMode]
end

function CinematicCameraModes.getPartMode(name: string?, part: BasePart?): PartMode
	local mode = if name then Part[name] else nil
	if mode then
		return mode
	end
	if part and CinematicCameraModes.is360CctvPart(part) then
		return Part[CinematicCameraModes.DefaultPart360Mode]
	end
	return Part[CinematicCameraModes.DefaultPartMode]
end

return CinematicCameraModes
