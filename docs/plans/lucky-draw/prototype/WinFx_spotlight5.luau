--!strict
-- LuckyDrawWinFx (ModuleScript, client-local). Five stage-lighting winner effects:
-- 1 Follow Spot, 2 Sweep & Lock, 3 Halo Truss, 4 Backlight Fan, 5 Runway.
-- WinFx.play(variant, character) / WinFx.stopAll().
-- Parts, beams and emitters live in workspace.LuckyDrawFx (cleared on stop). Lighting
-- effects are our own instances, tracked and destroyed on stop. The camera and the
-- letterbox are restored on stop. Everything is anchored to the root position captured
-- at play time. Each effect is driven by one RenderStepped connection.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WinFx = {}

local FOLDER_NAME = "LuckyDrawFx"
local CC_NAME = "LuckyDrawWinFxCC"
local BLOOM_NAME = "LuckyDrawWinFxBloom"
local LB_NAME = "LuckyDrawLetterbox"
local DURATION = 6.5
local HAND_BACK = 0.6
local LB_TIME = 0.5
local LB_FRAC = 0.1
local HARD_CLEANUP = DURATION + 1.5
local FLOOR_DROP = 3 -- floor Y = root.Y - 3
local TARGET_UP = 1.5 -- aim point above root
local TAU = math.pi * 2
-- Rotating a Cylinder 90 degrees about Z turns its axis (X) to world up (Y).
local REL_90 = math.rad(90)
local POOL_T = 0.7 -- transparency of a floor pool at full level

local WHITE = Color3.new(1, 1, 1)
local WARM = Color3.fromRGB(255, 244, 224) -- #FFF4E0, default lamp colour
local PURPLE_DEEP = Color3.fromRGB(98, 20, 255) -- #6214FF
local PURPLE_SOFT = Color3.fromRGB(169, 139, 255) -- #A98BFF
local DARK = Color3.fromRGB(22, 22, 28)

local session: any = nil -- { conn, extras } while an effect runs
local cine: any = nil -- { camType, camCF, camFov, gui, top, bottom } while the camera is taken over

-- ============================================================
-- Math helpers
-- ============================================================
local function clamp01(x: number): number
	if x < 0 then
		return 0
	elseif x > 1 then
		return 1
	end
	return x
end

local function ramp(t: number, t0: number, dur: number): number
	return clamp01((t - t0) / dur)
end

local function lerp(a: number, b: number, x: number): number
	return a + (b - a) * x
end

local function rnd(a: number, b: number): number
	return a + (b - a) * math.random()
end

local function quintOut(x: number): number
	return 1 - (1 - x) ^ 5
end

local function easeInOut(x: number): number
	return x * x * (3 - 2 * x)
end

-- 1 until the last second, then 0 at the end. Used to fade parts out before stop.
local function fadeOutT(t: number): number
	return 1 - ramp(t, DURATION - 1.0, 1.0)
end

-- Random small rotational offset (radians) applied on top of the camera shot.
local function shakeCF(amp: number): CFrame
	return CFrame.Angles(rnd(-amp, amp), rnd(-amp, amp), rnd(-amp, amp))
end

-- Camera at `dist` studs in front of the root (rotated by `ang` about Y), `dy` above the root.
local function camAt(ctx: any, ang: number, dist: number, dy: number, target: Vector3): CFrame
	local dir: Vector3 = CFrame.Angles(0, ang, 0):VectorToWorldSpace(ctx.front)
	return CFrame.lookAt(ctx.origin + dir * dist + Vector3.new(0, dy, 0), target)
end

-- ============================================================
-- Instance helpers
-- ============================================================
local function getFolder(): any
	local f: any = Workspace:FindFirstChild(FOLDER_NAME)
	if not f then
		f = Instance.new("Folder")
		f.Name = FOLDER_NAME
		f.Parent = Workspace
	end
	return f
end

local function mkPart(parent: Instance, shape: Enum.PartType, size: Vector3, color: Color3, transp: number, neon: boolean): any
	local p: any = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Transparency = transp
	if neon then
		p.Material = Enum.Material.Neon
	end
	p.Parent = parent
	return p
end

local function mkAtt(part: any): any
	local a: any = Instance.new("Attachment")
	a.Parent = part
	return a
end

local function mkBeam(parent: Instance, a0: any, a1: any, w0: number, w1: number, col: ColorSequence, tr: NumberSequence): any
	local b: any = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.FaceCamera = true
	b.LightEmission = 1
	b.LightInfluence = 0
	b.Segments = 1
	b.Width0 = w0
	b.Width1 = w1
	b.Color = col
	b.Transparency = tr
	b.Parent = parent
	return b
end

local function mkSpot(parent: Instance, face: Enum.NormalId, angle: number, range: number): any
	local l: any = Instance.new("SpotLight")
	l.Face = face
	l.Angle = angle
	l.Range = range
	l.Brightness = 0
	l.Color = WHITE
	l.Shadows = false
	l.Parent = parent
	return l
end

-- Lighting effects we create; destroyed on stop via the session's extras list.
local function ownLight(ctx: any, className: string, name: string): any
	local inst: any = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	table.insert(ctx.s.extras, inst)
	return inst
end

-- ============================================================
-- Shared cinematic layer
-- ============================================================
local function beginCinematic()
	local camera: any = Workspace.CurrentCamera
	local c: any = {}
	if camera then
		c.camType = camera.CameraType
		c.camCF = camera.CFrame
		c.camFov = camera.FieldOfView
		camera.CameraType = Enum.CameraType.Scriptable
	end
	local player = Players.LocalPlayer
	local pg: any = player and player:FindFirstChildOfClass("PlayerGui")
	if pg then
		local gui: any = Instance.new("ScreenGui")
		gui.Name = LB_NAME
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 50
		gui.ResetOnSpawn = false
		local top: any = Instance.new("Frame")
		top.Name = "Top"
		top.BackgroundColor3 = Color3.new(0, 0, 0)
		top.BorderSizePixel = 0
		top.Position = UDim2.fromScale(0, 0)
		top.Size = UDim2.new(1, 0, 0, 0)
		top.Parent = gui
		local bottom: any = Instance.new("Frame")
		bottom.Name = "Bottom"
		bottom.BackgroundColor3 = Color3.new(0, 0, 0)
		bottom.BorderSizePixel = 0
		bottom.AnchorPoint = Vector2.new(0, 1)
		bottom.Position = UDim2.fromScale(0, 1)
		bottom.Size = UDim2.new(1, 0, 0, 0)
		bottom.Parent = gui
		gui.Parent = pg
		c.gui = gui
		c.top = top
		c.bottom = bottom
	end
	cine = c
end

-- Restores FOV and CameraType (Custom if it was Scriptable) and destroys the letterbox.
-- The camera CFrame is reset to the saved one before the type switch.
local function endCinematic()
	local c = cine
	cine = nil
	if not c then
		return
	end
	local camera: any = Workspace.CurrentCamera
	if camera and c.camType then
		if c.camCF then
			camera.CFrame = c.camCF
		end
		if c.camFov then
			camera.FieldOfView = c.camFov
		end
		local restored = c.camType
		if restored == Enum.CameraType.Scriptable then
			restored = Enum.CameraType.Custom
		end
		camera.CameraType = restored
	end
	if c.gui then
		c.gui:Destroy()
	end
end

-- ============================================================
-- Stage-light rig helpers (used by the five lighting builders)
-- ============================================================

-- Dims the world over the first 0.4 s, recovers over the last 0.8 s.
local function dimWorld(cc: any, t: number, level: number)
	local d = ramp(t, 0, 0.4) * (1 - ramp(t, DURATION - 0.8, 0.8))
	cc.Brightness = level * d
	cc.Contrast = 0.15 * d
end

-- One lamp: dark matte housing with a real SpotLight, a narrow core beam and a soft wide beam
-- from the housing to its aim point, and a thin neon pool disc on the floor.
-- Drive it with aimLamp (position) and setLamp (levels) each frame.
local function mkLamp(ctx: any, pos: Vector3, color: Color3, peak: number, angle: number, poolD: number): any
	local folder = ctx.folder
	local housing = mkPart(folder, Enum.PartType.Block, Vector3.new(1, 1, 1), DARK, 0, false)
	housing.CFrame = CFrame.new(pos)
	local spot = mkSpot(housing, Enum.NormalId.Front, angle, 60)
	spot.Color = color
	spot.Shadows = true
	local aim = mkPart(folder, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), WHITE, 1, false)
	local a0 = mkAtt(housing)
	local a1 = mkAtt(aim)
	local core = mkBeam(folder, a0, a1, 0.4, poolD, ColorSequence.new(color), NumberSequence.new(1))
	local soft = mkBeam(folder, a0, a1, 1, poolD, ColorSequence.new(color), NumberSequence.new(1))
	local pool = mkPart(folder, Enum.PartType.Cylinder, Vector3.new(0.1, poolD, poolD), color, 1, true)
	return {
		pos = pos,
		peak = peak,
		housing = housing,
		spot = spot,
		aim = aim,
		core = core,
		soft = soft,
		pool = pool,
	}
end

-- Points the lamp at a target (uses the front axis as up when the beam is near vertical).
local function aimLamp(ctx: any, lamp: any, target: Vector3)
	local d: Vector3 = target - lamp.pos
	local up = Vector3.yAxis
	if math.abs(d.Unit.Y) > 0.9 then
		up = ctx.front
	end
	lamp.housing.CFrame = CFrame.lookAt(lamp.pos, target, up)
	lamp.aim.CFrame = CFrame.new(target)
end

-- Puts the lamp's floor pool under floorPos.
local function placePool(lamp: any, floorPos: Vector3)
	lamp.pool.CFrame = CFrame.new(floorPos.X, floorPos.Y + 0.12, floorPos.Z) * CFrame.Angles(0, 0, REL_90)
end

local function setLampColor(lamp: any, color: Color3)
	lamp.spot.Color = color
	lamp.core.Color = ColorSequence.new(color)
	lamp.soft.Color = ColorSequence.new(color)
	lamp.pool.Color = color
end

-- lv (0..1) drives spot brightness and beams. poolLv and beamLv default to lv.
local function setLamp(lamp: any, lv: number, poolLv: number?, beamLv: number?)
	local level = clamp01(lv)
	local bl = clamp01(beamLv or level)
	local pl = clamp01(poolLv or level)
	lamp.spot.Brightness = lamp.peak * level
	lamp.core.Transparency = NumberSequence.new(lerp(1, 0.55, bl), lerp(1, 0.9, bl))
	lamp.soft.Transparency = NumberSequence.new(lerp(1, 0.75, bl), lerp(1, 0.95, bl))
	lamp.pool.Transparency = lerp(1, POOL_T, pl)
end

-- ============================================================
-- 1 "Follow Spot": darkened stage, one hard white key from above-front snaps on and holds,
-- two purple rim spots fade in from behind. Slow push-in on the winner.
-- ============================================================
local function buildFollow(ctx: any): any
	local o: Vector3 = ctx.origin
	local floorY = o.Y - FLOOR_DROP
	local floorPt = Vector3.new(o.X, floorY, o.Z)
	local center = o + Vector3.new(0, TARGET_UP, 0)

	local cc: any = ownLight(ctx, "ColorCorrectionEffect", CC_NAME)

	-- Hard white key from directly above-front; its pool is the one under the winner.
	local key = mkLamp(ctx, o + ctx.front * 6 + Vector3.new(0, 22, 0), WARM, 7, 30, 7)
	placePool(key, floorPt)
	aimLamp(ctx, key, floorPt)

	-- Purple rim spots from back-left and back-right, aimed at the floor behind the winner.
	local rimL = mkLamp(ctx, o - ctx.front * 8 - ctx.right * 8 + Vector3.new(0, 20, 0), PURPLE_SOFT, 4, 35, 6)
	local rimR = mkLamp(ctx, o - ctx.front * 8 + ctx.right * 8 + Vector3.new(0, 20, 0), PURPLE_SOFT, 4, 35, 6)
	local rimTL = floorPt - ctx.front * 2 - ctx.right * 3
	local rimTR = floorPt - ctx.front * 2 + ctx.right * 3
	placePool(rimL, rimTL)
	aimLamp(ctx, rimL, rimTL)
	placePool(rimR, rimTR)
	aimLamp(ctx, rimR, rimTR)

	return {
		shot = function(t: number)
			local e = easeInOut(ramp(t, 0, DURATION))
			local cf = camAt(ctx, 0, lerp(16, 7, e), 2.0, center)
			return cf, lerp(60, 50, e)
		end,
		update = function(t: number)
			dimWorld(cc, t, -0.35)
			local g = fadeOutT(t)
			-- Key snaps on at 0.6 s with a short flicker of random dips, then holds.
			local flick = 1
			if t >= 0.6 and t < 0.85 then
				flick = rnd(0.2, 1)
			end
			setLamp(key, ramp(t, 0.6, 0.05) * flick * g)
			local rim = ramp(t, 2.5, 1.0) * g
			setLamp(rimL, rim)
			setLamp(rimR, rim)
		end,
	}
end

-- ============================================================
-- 2 "Sweep & Lock": four floor-level searchlights sweep figure-8 patterns over the area,
-- then ease onto the winner in stagger and lock. Their pools merge under the winner.
-- ============================================================
local function buildSweep(ctx: any): any
	local o: Vector3 = ctx.origin
	local floorY = o.Y - FLOOR_DROP
	local floorPt = Vector3.new(o.X, floorY, o.Z)
	local center = o + Vector3.new(0, TARGET_UP, 0)
	local LOCK0 = 2.6
	local STAGGER = 0.15

	local cc: any = ownLight(ctx, "ColorCorrectionEffect", CC_NAME)

	-- Four searchlights on a wide arc 28 studs out, angles measured from the winner's front.
	local ARC = { -150, -60, 60, 150 }
	local lamps: { any } = {}
	for i = 1, 4 do
		local dir: Vector3 = CFrame.Angles(0, math.rad(ARC[i]), 0):VectorToWorldSpace(ctx.front)
		local p = o + dir * 28
		local lamp = mkLamp(ctx, Vector3.new(p.X, floorY + 1.5, p.Z), WARM, 6, 30, 8)
		placePool(lamp, floorPt)
		lamps[i] = lamp
	end

	-- Sweep target: a figure-8 over the area in the air, with a unique phase per lamp.
	local function sweepPt(i: number, t: number): Vector3
		local ph = t * 1.2 + i * 0.9
		return o
			+ ctx.right * (12 * math.sin(ph))
			+ ctx.front * (6 * math.sin(2 * ph))
			+ Vector3.new(0, 7 + 3 * math.sin(ph * 0.7 + i), 0)
	end

	return {
		shot = function(t: number)
			local e = easeInOut(ramp(t, 0, DURATION))
			return camAt(ctx, math.rad(90) * e, 14, 5, center), 62
		end,
		update = function(t: number)
			dimWorld(cc, t, -0.25)
			local g = fadeOutT(t)
			for i = 1, 4 do
				local lock = quintOut(ramp(t, LOCK0 + (i - 1) * STAGGER, 0.9))
				aimLamp(ctx, lamps[i], sweepPt(i, t):Lerp(center, lock))
				setLamp(lamps[i], ramp(t, 0.1 * i, 0.3) * g, lock * g)
			end
		end,
	}
end

-- ============================================================
-- 3 "Halo Truss": twelve fixtures on a 10-stud ring 20 studs up. They chase on around the ring
-- aimed straight down, then tilt inward together into a crown on the winner. Colour goes purple, then white.
-- ============================================================
local function buildHalo(ctx: any): any
	local o: Vector3 = ctx.origin
	local floorY = o.Y - FLOOR_DROP
	local center = o + Vector3.new(0, TARGET_UP, 0)
	local N = 12
	local RING_R = 10
	local HALO_Y = 20
	local CHASE0 = 0.3
	local CHASE1 = 2.4
	local TILT0 = 2.6
	local TILT1 = 3.6

	local cc: any = ownLight(ctx, "ColorCorrectionEffect", CC_NAME)

	local lamps: { any } = {}
	local floorPts: { Vector3 } = {}
	local onTs: { number } = {}
	for i = 1, N do
		local a = (i - 1) * TAU / N
		local pos = o + ctx.front * (math.cos(a) * RING_R) + ctx.right * (math.sin(a) * RING_R) + Vector3.new(0, HALO_Y, 0)
		local below = Vector3.new(pos.X, floorY, pos.Z)
		local lamp = mkLamp(ctx, pos, WARM, 5, 25, 6)
		placePool(lamp, below)
		aimLamp(ctx, lamp, below)
		lamps[i] = lamp
		floorPts[i] = below
		onTs[i] = CHASE0 + (i - 1) * (CHASE1 - CHASE0) / (N - 1)
	end

	return {
		shot = function(t: number)
			-- Low at the winner's feet looking up through the beams, rising to eye level 8 studs out.
			local e = easeInOut(ramp(t, 0, DURATION))
			local pos = o + ctx.front * lerp(3, 8, e) + Vector3.new(0, lerp(-2.5, 2.0, e), 0)
			local tgt = o + Vector3.new(0, lerp(12, TARGET_UP, e), 0)
			return CFrame.lookAt(pos, tgt), lerp(70, 65, e)
		end,
		update = function(t: number)
			dimWorld(cc, t, -0.25)
			local g = fadeOutT(t)
			local tilt = easeInOut(ramp(t, TILT0, TILT1 - TILT0))
			local pa = ramp(t, TILT1, 0.4) * (1 - ramp(t, TILT1 + 0.6, 2.0))
			local col = WARM:Lerp(PURPLE_DEEP, pa)
			for i = 1, N do
				local lamp = lamps[i]
				local on = ramp(t, onTs[i], 0.15)
				aimLamp(ctx, lamp, floorPts[i]:Lerp(center, tilt))
				setLamp(lamp, on * g, on * (1 - tilt) * g)
				setLampColor(lamp, col)
			end
		end,
	}
end

-- ============================================================
-- 4 "Backlight Fan": five fixtures behind the winner fan rays toward the camera, silhouetting
-- the winner. Beams alternate white and purple on a 1.2 s rhythm. A soft front key lights the face.
-- ============================================================
local function buildBacklight(ctx: any): any
	local o: Vector3 = ctx.origin
	local floorY = o.Y - FLOOR_DROP
	local floorPt = Vector3.new(o.X, floorY, o.Z)
	local center = o + Vector3.new(0, TARGET_UP, 0)
	local XS = { -7, -3.5, 0, 3.5, 7 }
	local PERIOD = 1.2

	local cc: any = ownLight(ctx, "ColorCorrectionEffect", CC_NAME)

	local lamps: { any } = {}
	for i = 1, 5 do
		local pos = o - ctx.front * 8 + ctx.right * XS[i] + Vector3.new(0, -1.5, 0)
		local lamp = mkLamp(ctx, pos, WARM, 6, 30, 7)
		placePool(lamp, floorPt)
		lamps[i] = lamp
	end

	-- Soft front key from above-front, beams hidden so only the face is lit.
	local key = mkLamp(ctx, o + ctx.front * 8 + Vector3.new(0, 22, 0), WARM, 5, 40, 6)
	placePool(key, floorPt)
	local keyTarget = o + Vector3.new(0, 2.5, 0)
	aimLamp(ctx, key, keyTarget)

	return {
		shot = function(t: number)
			local e = easeInOut(ramp(t, 0, DURATION))
			return camAt(ctx, 0, lerp(12, 11, e), -1, o + Vector3.new(0, 2.5, 0)), 55
		end,
		update = function(t: number)
			dimWorld(cc, t, -0.3)
			local g = fadeOutT(t)
			local fan = 0.3 + 0.9 * (0.5 + 0.5 * math.sin(t * TAU / PERIOD))
			local on = ramp(t, 0, 0.3) * g
			for i = 1, 5 do
				local target = o + ctx.front * 10 + ctx.right * (XS[i] * fan) + Vector3.new(0, 3, 0)
				aimLamp(ctx, lamps[i], target)
				local mix = 0.5 + 0.5 * math.sin(t * TAU / PERIOD + (i % 2) * math.pi)
				setLamp(lamps[i], on, 0)
				setLampColor(lamps[i], WARM:Lerp(PURPLE_DEEP, mix))
			end
			setLamp(key, ramp(t, 3.0, 1.0) * g, 0, 0)
		end,
	}
end

-- ============================================================
-- 5 "Runway": six pairs of spots switch on far to near, leaving a lit path to the winner.
-- A big top spot snaps on over the winner at the end. The camera dollies down the runway.
-- ============================================================
local function buildRunway(ctx: any): any
	local o: Vector3 = ctx.origin
	local floorY = o.Y - FLOOR_DROP
	local center = o + Vector3.new(0, TARGET_UP, 0)
	local floorPt = Vector3.new(o.X, floorY, o.Z)
	local N = 6

	local cc: any = ownLight(ctx, "ColorCorrectionEffect", CC_NAME)

	local rows: { { any } } = {}
	for k = 1, N do
		local d = lerp(30, 6, (k - 1) / (N - 1))
		local pair: { any } = {}
		for side = -1, 1, 2 do
			local pos = o + ctx.front * d + ctx.right * (side * 4) + Vector3.new(0, 16, 0)
			local target = Vector3.new(o.X, floorY, o.Z) + ctx.front * d + ctx.right * (side * 1.5)
			local lamp = mkLamp(ctx, pos, WARM, 5, 30, 6)
			placePool(lamp, target)
			aimLamp(ctx, lamp, target)
			table.insert(pair, lamp)
		end
		rows[k] = pair
	end

	local top = mkLamp(ctx, o + Vector3.new(0, 26, 0), WARM, 8, 35, 8)
	placePool(top, floorPt)
	aimLamp(ctx, top, center)

	return {
		shot = function(t: number)
			local e = easeInOut(ramp(t, 0, DURATION))
			local pos = o + ctx.front * lerp(30, 6, e) + Vector3.new(0, 3, 0)
			return CFrame.lookAt(pos, center), 60
		end,
		update = function(t: number)
			dimWorld(cc, t, -0.25)
			local g = fadeOutT(t)
			for k = 1, N do
				local on = ramp(t, 0.4 + (k - 1) * 0.35, 0.25) * g
				for _, lamp in ipairs(rows[k]) do
					setLamp(lamp, on)
				end
			end
			setLamp(top, ramp(t, 5.2, 0.1) * g)
		end,
	}
end

local BUILDERS: { [number]: (any) -> any } = {
	[1] = buildFollow,
	[2] = buildSweep,
	[3] = buildHalo,
	[4] = buildBacklight,
	[5] = buildRunway,
}

-- ============================================================
-- Public API
-- ============================================================
function WinFx.stopAll()
	local s = session
	session = nil
	if s then
		if s.conn then
			s.conn:Disconnect()
			s.conn = nil
		end
		for _, inst in ipairs(s.extras) do
			inst:Destroy()
		end
		s.extras = {}
	end
	endCinematic()
	local leftoverCC = Lighting:FindFirstChild(CC_NAME)
	if leftoverCC then
		leftoverCC:Destroy()
	end
	local leftoverBloom = Lighting:FindFirstChild(BLOOM_NAME)
	if leftoverBloom then
		leftoverBloom:Destroy()
	end
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if folder then
		folder:ClearAllChildren()
	end
end

function WinFx.play(variant: number, character: Model)
	WinFx.stopAll()
	local root: any = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local look: Vector3 = root.CFrame.LookVector
	local front = Vector3.new(look.X, 0, look.Z)
	if front.Magnitude < 0.01 then
		front = Vector3.new(0, 0, -1)
	else
		front = front.Unit
	end

	local s: any = { conn = nil, extras = {} }
	session = s
	beginCinematic()

	local ctx: any = {
		s = s,
		character = character,
		origin = root.Position,
		front = front,
		right = front:Cross(Vector3.yAxis),
		folder = getFolder(),
	}
	local build = BUILDERS[variant] or BUILDERS[1]
	local okBuild, fx = pcall(build, ctx)
	if not okBuild or type(fx) ~= "table" then
		warn("[WinFx] build failed: " .. tostring(fx))
		WinFx.stopAll()
		return
	end

	local t0 = os.clock()
	s.conn = RunService.RenderStepped:Connect(function()
		if session ~= s then
			return
		end
		local t = os.clock() - t0
		if t >= DURATION or character.Parent == nil then
			WinFx.stopAll()
			return
		end

		fx.update(t)

		local c = cine
		if c then
			if c.top and c.bottom then
				local h = LB_FRAC * ramp(t, 0, LB_TIME) * (1 - ramp(t, DURATION - LB_TIME, LB_TIME))
				c.top.Size = UDim2.new(1, 0, h, 0)
				c.bottom.Size = UDim2.new(1, 0, h, 0)
			end
			local camera: any = Workspace.CurrentCamera
			if camera and c.camCF then
				local cf, fov = fx.shot(t)
				local amp: number = 0
				if fx.shake then
					amp = fx.shake(t)
				end
				if amp > 0 then
					cf = cf * shakeCF(amp)
				end
				local outFov: number = fov or c.camFov
				-- Hand-back: ease the shot onto the saved camera over the last 0.6 s.
				local hb = ramp(t, DURATION - HAND_BACK, HAND_BACK)
				if hb > 0 then
					local a = easeInOut(hb)
					cf = cf:Lerp(c.camCF, a)
					outFov = lerp(outFov, c.camFov, a)
				end
				camera.CFrame = cf
				camera.FieldOfView = outFov
			end
		end
	end)

	task.delay(HARD_CLEANUP, function()
		if session == s then
			WinFx.stopAll()
		end
	end)
end

return WinFx
