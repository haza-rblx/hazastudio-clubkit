--!strict
-- LuckyDrawWinFx (ModuleScript, client-local). Five cinematic winner effects:
-- 1 Crown Descent, 2 Supernova, 3 Club Takeover, 4 Ascension Vortex, 5 Time Freeze.
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
local HEAD_UP = 3.2 -- approx. top of head above root
local TAU = math.pi * 2
-- Rotating a Cylinder 90 degrees about Z turns its axis (X) to world up (Y).
local REL_90 = math.rad(90)

local WHITE = Color3.new(1, 1, 1)
local PURPLE = Color3.fromRGB(139, 92, 255)
local PURPLE_DEEP = Color3.fromRGB(98, 20, 255) -- #6214FF
local SPARK = Color3.fromRGB(178, 139, 255)
local GOLD = Color3.fromRGB(255, 211, 107)
local SKY = Color3.fromRGB(122, 215, 255)
local MAGENTA = Color3.fromRGB(255, 64, 200)
local DARK = Color3.fromRGB(22, 22, 28)
local SPARK_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"

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

local function expoOut(x: number): number
	if x >= 1 then
		return 1
	end
	return 1 - 2 ^ (-10 * x)
end

local function easeInOut(x: number): number
	return x * x * (3 - 2 * x)
end

-- 0 before t0, quick rise to 1 over the first 15% of dur, then decay back to 0.
local function pulse(t: number, t0: number, dur: number): number
	local k = ramp(t, t0, dur)
	if k <= 0 or k >= 1 then
		return 0
	end
	if k < 0.15 then
		return k / 0.15
	end
	return 1 - (k - 0.15) / 0.85
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

local function confettiColours(): ColorSequence
	local keys: { ColorSequenceKeypoint } = {}
	for i = 0, 4 do
		table.insert(keys, ColorSequenceKeypoint.new(i / 4, Color3.fromHSV(i / 4, 1, 1)))
	end
	return ColorSequence.new(keys)
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
-- 1 "Crown Descent": gold ring drops from 40 studs, shrinks to a crown over the head.
-- ============================================================
local function buildCrown(ctx: any): any
	local folder = ctx.folder
	local o: Vector3 = ctx.origin
	local floorY = o.Y - FLOOR_DROP
	local hoverY = o.Y + HEAD_UP + 1.5
	local DESCENT = 3.2

	local cc: any = ownLight(ctx, "ColorCorrectionEffect", CC_NAME)
	local bloom: any = ownLight(ctx, "BloomEffect", BLOOM_NAME)
	bloom.Size = 24
	bloom.Threshold = 0.8

	local lamp = mkPart(folder, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), WHITE, 1, false)
	lamp.CFrame = CFrame.new(o.X, o.Y + 30, o.Z)
	local spot = mkSpot(lamp, Enum.NormalId.Bottom, 28, 70)
	spot.Color = GOLD

	local ring = mkPart(folder, Enum.PartType.Cylinder, Vector3.new(0.25, 14, 14), GOLD, 0.1, true)
	local ringLight: any = Instance.new("PointLight")
	ringLight.Color = GOLD
	ringLight.Range = 12
	ringLight.Brightness = 0
	ringLight.Parent = ring

	-- Sparkle rain: four emitters, each moved to a random spot in a 12-stud disc per frame.
	local rainAnchors: { any } = {}
	local rains: { any } = {}
	for i = 1, 4 do
		local anchor = mkPart(folder, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), WHITE, 1, false)
		local em: any = Instance.new("ParticleEmitter")
		em.Texture = SPARK_TEX
		em.Rate = 0
		em.Lifetime = NumberRange.new(1.6, 2.2)
		em.Speed = NumberRange.new(0, 1)
		em.SpreadAngle = Vector2.new(10, 10)
		em.EmissionDirection = Enum.NormalId.Bottom
		em.Acceleration = Vector3.new(0, -12, 0)
		em.Size = NumberSequence.new(0.5, 0.2)
		em.Color = ColorSequence.new(GOLD, WHITE)
		em.LightEmission = 1
		em.Transparency = NumberSequence.new(0.1, 1)
		em.Parent = anchor
		rainAnchors[i] = anchor
		rains[i] = em
	end

	local shock = mkPart(folder, Enum.PartType.Cylinder, Vector3.new(0.15, 2, 2), GOLD, 1, true)

	return {
		shot = function(t: number)
			local e = easeInOut(ramp(t, 0, 5.0))
			local cf = camAt(ctx, 0, lerp(18, 6, e), lerp(10, 2.2, e), o + Vector3.new(0, lerp(TARGET_UP, HEAD_UP, e), 0))
			return cf, lerp(70, 55, e)
		end,
		update = function(t: number)
			local e = quintOut(ramp(t, 0, DESCENT))
			local y = lerp(o.Y + 40, hoverY, e) + math.sin(t * 2) * 0.12 * ramp(t, DESCENT, 0.5)
			local d = lerp(14, 3, e)
			ring.Size = Vector3.new(0.25, d, d)
			ring.CFrame = CFrame.new(o.X, y, o.Z) * CFrame.Angles(0, t * 0.9, 0) * CFrame.Angles(math.rad(8), 0, 0) * CFrame.Angles(0, 0, REL_90)
			ringLight.Brightness = 3 * ramp(t, DESCENT - 0.7, 0.7)

			local dimLvl = ramp(t, 0, 0.5) * (1 - ramp(t, DURATION - 0.8, 0.8))
			cc.Brightness = -0.15 * dimLvl
			cc.Saturation = -0.3 * dimLvl
			spot.Brightness = 7 * dimLvl

			if t < DESCENT then
				for i = 1, 4 do
					local a = rnd(0, TAU)
					local r = 12 * math.sqrt(math.random())
					rainAnchors[i].CFrame = CFrame.new(o.X + math.cos(a) * r, o.Y + 22, o.Z + math.sin(a) * r)
					rains[i]:Emit(3)
				end
			end

			bloom.Intensity = 2.5 * pulse(t, DESCENT, 1.2)

			if t < DESCENT then
				shock.Transparency = 1
			else
				local k = ramp(t, DESCENT, 1.4)
				local d2 = lerp(2, 40, quintOut(k))
				shock.Size = Vector3.new(0.15, d2, d2)
				shock.CFrame = CFrame.new(o.X, floorY + 0.15, o.Z) * CFrame.Angles(0, 0, REL_90)
				shock.Transparency = 0.2 + 0.8 * k
			end
		end,
	}
end

-- ============================================================
-- 2 "Supernova": tight close-up while the orb implodes, then detonation and a 120 degree orbit.
-- ============================================================
local function buildSupernova(ctx: any): any
	local folder = ctx.folder
	local o: Vector3 = ctx.origin
	local center = o + Vector3.new(0, TARGET_UP, 0)
	local floorY = o.Y - FLOOR_DROP
	local DET = 1.6

	local cc: any = ownLight(ctx, "ColorCorrectionEffect", CC_NAME)
	local bloom: any = ownLight(ctx, "BloomEffect", BLOOM_NAME)
	bloom.Size = 30
	bloom.Threshold = 0.7

	local orb = mkPart(folder, Enum.PartType.Ball, Vector3.new(10, 10, 10), WHITE, 0.55, true)
	local orbLight: any = Instance.new("PointLight")
	orbLight.Range = 24
	orbLight.Brightness = 0
	orbLight.Parent = orb

	local burstAnchor = mkPart(folder, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), WHITE, 1, false)
	burstAnchor.CFrame = CFrame.new(center)
	local burst: any = Instance.new("ParticleEmitter")
	burst.Texture = SPARK_TEX
	burst.Rate = 0
	burst.Lifetime = NumberRange.new(1.0, 1.6)
	burst.Speed = NumberRange.new(50, 80)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Drag = 6
	burst.Size = NumberSequence.new(1.2, 0.1)
	burst.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.5, SKY),
		ColorSequenceKeypoint.new(1, MAGENTA),
	})
	burst.LightEmission = 1
	burst.Transparency = NumberSequence.new(0, 1)
	burst.Parent = burstAnchor

	local colBase = mkPart(folder, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), WHITE, 1, false)
	colBase.CFrame = CFrame.new(o.X, floorY, o.Z)
	local colTop = mkPart(folder, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), WHITE, 1, false)
	colTop.CFrame = CFrame.new(o.X, floorY + 70, o.Z)
	local column = mkBeam(folder, mkAtt(colBase), mkAtt(colTop), 1.2, 0.6, ColorSequence.new(WHITE, SKY), NumberSequence.new(1))

	local rings: { any } = {}
	local ringCols: { Color3 } = { SKY, MAGENTA, SKY }
	for i = 1, 3 do
		rings[i] = mkPart(folder, Enum.PartType.Cylinder, Vector3.new(0.15, 2, 2), ringCols[i], 1, true)
	end

	local fired = false

	return {
		shake = function(t: number): number
			if t < DET then
				return 0.01 + 0.05 * ramp(t, 0, DET)
			end
			return 0.06 * (1 - ramp(t, DET, 1.0))
		end,
		shot = function(t: number)
			local k = expoOut(ramp(t, DET, 0.5))
			local ang = math.rad(120) * easeInOut(ramp(t, DET, DURATION - DET))
			local cf = camAt(ctx, ang, lerp(5, 16, k), lerp(2.0, 5.0, k), center)
			return cf, 70
		end,
		update = function(t: number)
			if t < DET then
				local k = ramp(t, 0, DET)
				local d = lerp(10, 0.5, k * k * k)
				orb.Size = Vector3.new(d, d, d)
				orb.CFrame = CFrame.new(center)
				orb.Color = WHITE:Lerp(SKY, ramp(t, 0, 0.8)):Lerp(MAGENTA, ramp(t, 0.8, 0.8))
				orbLight.Brightness = 4 * k
				orbLight.Color = orb.Color
			else
				orb.Transparency = 1
				orbLight.Brightness = 0
			end

			local flash = 0
			if t >= DET then
				flash = 0.6 * (1 - ramp(t, DET, 0.4))
			end
			cc.Brightness = flash
			bloom.Intensity = 1.5 * pulse(t, DET, 1.2)

			if t >= DET and not fired then
				fired = true
				burst:Emit(200)
			end

			for i = 1, 3 do
				local t0 = DET + (i - 1) * 0.15
				local ring = rings[i]
				if t < t0 then
					ring.Transparency = 1
				else
					local k = ramp(t, t0, 1.6)
					local d = lerp(2, 60, quintOut(k))
					ring.Size = Vector3.new(0.15, d, d)
					ring.CFrame = CFrame.new(o.X, floorY + 0.12 + i * 0.04, o.Z) * CFrame.Angles(0, 0, REL_90)
					ring.Transparency = 0.1 + 0.9 * k
				end
			end

			local colT = 1
			if t >= DET then
				colT = lerp(0.1, 1, ramp(t, DET, 3.0))
			end
			column.Transparency = NumberSequence.new(colT)
		end,
	}
end

-- ============================================================
-- 3 "Club Takeover": 8 moving heads sweep, then converge and lock on the winner.
-- ============================================================
local function buildClub(ctx: any): any
	local folder = ctx.folder
	local o: Vector3 = ctx.origin
	local floorY = o.Y - FLOOR_DROP
	local center = o + Vector3.new(0, TARGET_UP, 0)
	local N = 8
	local RING = 20
	local SWEEP_R = 12
	local LOCK = 2.5

	local aims: { any } = {}
	local beams: { any } = {}
	for i = 1, N do
		local a = (i - 1) * TAU / N
		local head = mkPart(folder, Enum.PartType.Block, Vector3.new(1.2, 1, 1.2), DARK, 0, false)
		head.CFrame = CFrame.new(o.X + math.cos(a) * RING, floorY + 0.5, o.Z + math.sin(a) * RING)
		local aim = mkPart(folder, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), WHITE, 1, false)
		aims[i] = aim
		beams[i] = mkBeam(folder, mkAtt(head), mkAtt(aim), 0.6, 3, ColorSequence.new(WHITE),
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.9) }))
	end

	-- Confetti: two upward bursts, one on each side of the winner.
	local confetti: { any } = {}
	for i = 1, 2 do
		local side = -1
		if i == 1 then
			side = 1
		end
		local anchor = mkPart(folder, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), WHITE, 1, false)
		anchor.CFrame = CFrame.new(o + ctx.right * (6 * side) + Vector3.new(0, 1, 0))
		local e: any = Instance.new("ParticleEmitter")
		e.Texture = SPARK_TEX
		e.Rate = 0
		e.Lifetime = NumberRange.new(2.2, 3.0)
		e.Speed = NumberRange.new(18, 30)
		e.SpreadAngle = Vector2.new(25, 25)
		e.EmissionDirection = Enum.NormalId.Top
		e.Acceleration = Vector3.new(0, -25, 0)
		e.Drag = 1
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-300, 300)
		e.Size = NumberSequence.new(0.8, 0.4)
		e.Color = confettiColours()
		e.LightEmission = 0.5
		e.Parent = anchor
		table.insert(confetti, e)
	end

	local disc = mkPart(folder, Enum.PartType.Cylinder, Vector3.new(0.15, 6, 6), PURPLE, 1, true)

	local fired = false

	return {
		shot = function(t: number)
			local fov = 70 + 3 * math.sin(t * 1.2)
			return camAt(ctx, TAU * (t / DURATION), 12, 4, center), fov
		end,
		update = function(t: number)
			local conv = easeInOut(ramp(t, LOCK, 0.7))
			local lockT = ramp(t, LOCK, 0.5)
			local whiteT = ramp(t, LOCK + 0.5, 2.0)
			for i = 1, N do
				local a0 = (i - 1) * TAU / N
				local sa = a0 + t * 1.6 + math.sin(t * 2.3 + i) * 0.8
				local sy = 4 + 5 * (0.5 + 0.5 * math.sin(t * 2.7 + i * 1.3))
				local sweep = o + Vector3.new(math.cos(sa) * SWEEP_R, sy, math.sin(sa) * SWEEP_R)
				aims[i].CFrame = CFrame.new(sweep:Lerp(center, conv))
				local hue = Color3.fromHSV((t * 0.35 + i / N) % 1, 1, 1)
				beams[i].Color = ColorSequence.new(hue:Lerp(PURPLE_DEEP, lockT):Lerp(WHITE, whiteT))
			end

			if t >= LOCK and not fired then
				fired = true
				for _, e in ipairs(confetti) do
					e:Emit(60)
				end
			end

			local r = 6 + 2 * ramp(t, LOCK, 0.3) * math.abs(math.sin((t - LOCK) * 7))
			disc.Size = Vector3.new(0.15, r, r)
			disc.CFrame = CFrame.new(o.X, floorY + 0.12, o.Z) * CFrame.Angles(0, 0, REL_90)
			disc.Transparency = 1 - 0.6 * ramp(t, LOCK, 0.3)
		end,
	}
end

-- ============================================================
-- 4 "Ascension Vortex": helix of neon parts climbing around the winner, purple pillar, smoke.
-- ============================================================
local function buildVortex(ctx: any): any
	local folder = ctx.folder
	local o: Vector3 = ctx.origin
	local floorY = o.Y - FLOOR_DROP
	local center = o + Vector3.new(0, TARGET_UP, 0)
	local N = 36
	local HELIX_H = 40
	local CLIMB = 6 -- studs per second

	local helix: { any } = {}
	local helixH0: { number } = {}
	local helixStrand: { number } = {}
	for i = 1, N do
		helix[i] = mkPart(folder, Enum.PartType.Block, Vector3.new(0.6, 0.6, 0.6), PURPLE:Lerp(WHITE, (i - 1) / (N - 1)), 0.1, true)
		helixStrand[i] = (i - 1) % 2 -- two interleaved strands
		helixH0[i] = math.floor((i - 1) / 2) * (HELIX_H / 18)
	end

	local pBase = mkPart(folder, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), WHITE, 1, false)
	pBase.CFrame = CFrame.new(o.X, floorY, o.Z)
	local pTop = mkPart(folder, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), WHITE, 1, false)
	local pillar = mkBeam(folder, mkAtt(pBase), mkAtt(pTop), 3.5, 3.5, ColorSequence.new(PURPLE), NumberSequence.new(1))

	local lights: { any } = {}
	for i = 1, 8 do
		local a = (i - 1) * TAU / 8
		local anchor = mkPart(folder, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), PURPLE, 1, false)
		anchor.CFrame = CFrame.new(o.X + math.cos(a) * 6, floorY + 1, o.Z + math.sin(a) * 6)
		local l: any = Instance.new("PointLight")
		l.Color = PURPLE
		l.Range = 10
		l.Brightness = 0
		l.Parent = anchor
		lights[i] = l
	end

	local smokeAnchor = mkPart(folder, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), WHITE, 1, false)
	smokeAnchor.CFrame = CFrame.new(o.X, floorY + 0.2, o.Z)
	local smoke: any = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE_TEX
	smoke.Rate = 22
	smoke.Lifetime = NumberRange.new(2.5, 3.5)
	smoke.Speed = NumberRange.new(3, 6)
	smoke.SpreadAngle = Vector2.new(25, 25)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Size = NumberSequence.new(2, 8)
	smoke.Transparency = NumberSequence.new(0.6, 1)
	smoke.Color = ColorSequence.new(PURPLE, SPARK)
	smoke.Parent = smokeAnchor

	return {
		shot = function(t: number)
			-- Crane: starts at the feet, 3 studs out, and spirals up to ~20 studs above, nearly top-down.
			local e = easeInOut(ramp(t, 0, DURATION))
			local cf = camAt(ctx, TAU * 1.5 * e, lerp(3, 1, e), lerp(-2, 20, e), center)
			return cf, lerp(70, 62, e)
		end,
		update = function(t: number)
			local g = fadeOutT(t)
			for i = 1, N do
				local h = (helixH0[i] + t * CLIMB) % HELIX_H
				local r = lerp(4, 2.5, h / HELIX_H)
				local a = helixStrand[i] * math.pi + h * 0.25
				helix[i].CFrame = CFrame.new(o.X + math.cos(a) * r, floorY + h, o.Z + math.sin(a) * r)
				local topF = clamp01((h - 26) / 14)
				local botF = clamp01(1 - h / 4)
				local base = 0.1 + 0.9 * math.max(topF, botF)
				helix[i].Transparency = 1 - (1 - base) * g
			end

			local rise = quintOut(ramp(t, 0, 2.0))
			pTop.CFrame = CFrame.new(o.X, floorY + 60 * rise + 0.1, o.Z)
			pillar.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, lerp(1, 0.6, g)),
				NumberSequenceKeypoint.new(0.5, lerp(1, 0.1, g)),
				NumberSequenceKeypoint.new(1, lerp(1, 0.6, g)),
			})

			smoke.Enabled = t < DURATION - 1.2

			for i = 1, 8 do
				lights[i].Brightness = (0.8 + 0.8 * math.sin(t * 5 + i * math.pi / 4)) * g
			end
		end,
	}
end

-- ============================================================
-- 5 "Time Freeze": grey world, dolly-zoom, gold highlight, dust and a drawn constellation.
-- ============================================================
local function buildFreeze(ctx: any): any
	local folder = ctx.folder
	local o: Vector3 = ctx.origin
	local center = o + Vector3.new(0, TARGET_UP, 0)

	local cc: any = ownLight(ctx, "ColorCorrectionEffect", CC_NAME)

	local hl: any = Instance.new("Highlight")
	hl.FillColor = GOLD
	hl.FillTransparency = 0.6
	hl.OutlineColor = WHITE
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee = ctx.character
	hl.Parent = folder

	-- Dust: 9 emitters on a 3x3 grid across a 25-stud box, hanging in the air.
	for i = 1, 9 do
		local gx = ((i - 1) % 3 - 1) * 9
		local gz = (math.floor((i - 1) / 3) - 1) * 9
		local gy = 2 + (i % 3) * 5
		local anchor = mkPart(folder, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), WHITE, 1, false)
		anchor.CFrame = CFrame.new(o + ctx.right * gx + ctx.front * gz + Vector3.new(0, gy, 0))
		local dust: any = Instance.new("ParticleEmitter")
		dust.Texture = SPARK_TEX
		dust.Rate = 5
		dust.Lifetime = NumberRange.new(6, 8)
		dust.Speed = NumberRange.new(0.2, 0.6)
		dust.SpreadAngle = Vector2.new(180, 180)
		dust.Drag = 1
		dust.Size = NumberSequence.new(0.15, 0.25)
		dust.Color = ColorSequence.new(WHITE)
		dust.LightEmission = 1
		dust.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(0.2, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		dust.Parent = anchor
	end

	-- Constellation: 5 neon points on a 6-stud ring in the plane facing the camera.
	local starC = o + Vector3.new(0, 3.5, 0)
	local pts: { any } = {}
	local ptPos: { Vector3 } = {}
	for i = 1, 5 do
		local a = math.pi / 2 + (i - 1) * TAU / 5
		local pos: Vector3 = starC + ctx.right * (math.cos(a) * 6) + Vector3.new(0, math.sin(a) * 6, 0)
		local p = mkPart(folder, Enum.PartType.Ball, Vector3.new(0.7, 0.7, 0.7), WHITE, 0, true)
		p.CFrame = CFrame.new(pos)
		pts[i] = mkAtt(p)
		ptPos[i] = pos
	end

	-- Pentagram order; each segment is drawn by a moving tip that a Beam follows.
	local ORDER = { 1, 3, 5, 2, 4, 1 }
	local segs: { any } = {}
	for k = 1, 5 do
		local a = ORDER[k]
		local b = ORDER[k + 1]
		local tip = mkPart(folder, Enum.PartType.Block, Vector3.new(0.1, 0.1, 0.1), WHITE, 1, false)
		local beam = mkBeam(folder, pts[a], mkAtt(tip), 0.15, 0.15, ColorSequence.new(WHITE), NumberSequence.new(1))
		segs[k] = { beam = beam, tip = tip, from = ptPos[a], to = ptPos[b], t0 = 0.8 + (k - 1) * 0.7 }
	end

	local d0 = 6 * math.tan(math.rad(35)) -- constant apparent size: dist * tan(fov/2)

	return {
		shot = function(t: number)
			-- Dolly-zoom: 6 -> 20 studs while FOV follows so the winner keeps the same size.
			-- Then a slow sideways drift.
			local e = easeInOut(ramp(t, 0, 4.5))
			local dist = lerp(6, 20, e)
			local fov = math.deg(2 * math.atan(d0 / dist))
			local drift = ctx.right * (3 * easeInOut(ramp(t, 3.5, 3.0)))
			local pos = o + ctx.front * dist + drift + Vector3.new(0, 2, 0)
			return CFrame.lookAt(pos, center), fov
		end,
		update = function(t: number)
			-- Grey world, fades in over 0.6 s and floods back over the last 0.8 s before hand-back.
			local lvl = ramp(t, 0, 0.6) * (1 - ramp(t, DURATION - 1.4, 0.8))
			cc.Saturation = -1 * lvl
			for k = 1, 5 do
				local sg = segs[k]
				local kk = ramp(t, sg.t0, 0.5)
				sg.tip.CFrame = CFrame.new(sg.from:Lerp(sg.to, easeInOut(kk)))
				sg.beam.Transparency = NumberSequence.new(kk > 0 and 0.3 or 1)
			end
		end,
	}
end

local BUILDERS: { [number]: (any) -> any } = {
	[1] = buildCrown,
	[2] = buildSupernova,
	[3] = buildClub,
	[4] = buildVortex,
	[5] = buildFreeze,
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
