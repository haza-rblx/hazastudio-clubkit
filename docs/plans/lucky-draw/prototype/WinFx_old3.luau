--!strict
-- LuckyDrawWinFx (ModuleScript, client-local). 3 winner spotlight variants.
-- WinFx.play(variant, character) / WinFx.stopAll(). Light shafts are Beam instances.
-- Everything lives in workspace.LuckyDrawFx, except the WINNER tag (parented to the
-- character's Head, tracked and destroyed on cleanup).
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WinFx = {}

local FOLDER_NAME = "LuckyDrawFx"
local CC_NAME = "LuckyDrawWinFxCC"
local HARD_CLEANUP = 6.5
local WHITE = Color3.new(1, 1, 1)
local PURPLE = Color3.fromRGB(139, 92, 255) -- #8B5CFF
local SPARK = Color3.fromRGB(178, 139, 255) -- #B28BFF
local WARM = Color3.fromRGB(255, 248, 235)
local GOLD = Color3.fromRGB(255, 211, 107) -- #FFD36B
local SKY = Color3.fromRGB(122, 215, 255) -- #7AD7FF
local SPARK_TEX = "rbxasset://textures/particles/sparkles_main.dds"
-- Rotating a Cylinder 90 degrees about Z turns its axis (X) to world up (Y).
local REL_90 = math.rad(90)

local session: any = nil

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

local function quintOut(x: number): number
	return 1 - (1 - x) ^ 5
end

-- Transparency sequence from source value a to far value b, both pushed toward 1 by fade.
local function fadedSeq(a: number, b: number, fade: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, a + (1 - a) * fade),
		NumberSequenceKeypoint.new(1, b + (1 - b) * fade),
	})
end

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

-- ============================================================
-- V1 "Stage Spot": follow-spot from 28 studs above. Two tapered Beams (core + halo)
-- from the lamp to the floor, a SpotLight, and two floor discs for falloff.
-- ============================================================
local function buildStage(ctx: any): any
	local folder = ctx.folder
	local lamp = mkPart(folder, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), WHITE, 1, false)
	local spot = mkSpot(lamp, Enum.NormalId.Bottom, 35, 40)
	local floorPart = mkPart(folder, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), WHITE, 1, false)
	local lampA = mkAtt(lamp)
	local floorA = mkAtt(floorPart)
	local tint = ColorSequence.new(WARM)
	local halo = mkBeam(folder, lampA, floorA, 1.5, 11, tint, fadedSeq(0.8, 0.97, 0))
	local core = mkBeam(folder, lampA, floorA, 0.6, 6, tint, fadedSeq(0.55, 0.9, 0))
	local disc1 = mkPart(folder, Enum.PartType.Cylinder, Vector3.new(0.2, 8, 8), WHITE, 0.75, true)
	local disc2 = mkPart(folder, Enum.PartType.Cylinder, Vector3.new(0.15, 12, 12), WHITE, 0.9, true)

	return {
		duration = 6.0,
		dim = { b = -0.25, s = -0.4, inT = 0.5, outT = 4.6, outDur = 0.8 },
		extras = {},
		update = function(t: number, hrp: any)
			local p: Vector3 = hrp.Position
			local floorY = p.Y - 3
			local fade = ramp(t, 4.6, 0.8)
			lamp.CFrame = CFrame.new(p.X, p.Y + 28, p.Z)
			floorPart.CFrame = CFrame.new(p.X, floorY, p.Z)
			spot.Brightness = 8 * ramp(t, 0, 0.4) * (1 - fade)
			core.Transparency = fadedSeq(0.55, 0.9, fade)
			halo.Transparency = fadedSeq(0.8, 0.97, fade)
			disc1.CFrame = CFrame.new(p.X, floorY + 0.12, p.Z) * CFrame.Angles(0, 0, REL_90)
			disc1.Transparency = 0.75 + 0.25 * fade
			disc2.CFrame = CFrame.new(p.X, floorY + 0.1, p.Z) * CFrame.Angles(0, 0, REL_90)
			disc2.Transparency = 0.9 + 0.1 * fade
		end,
	}
end

-- ============================================================
-- V2 "Ascension Pillar": tapered Beam column rising from the feet, highlight,
-- two purple shockwave discs at the feet, sparkles.
-- ============================================================
local function updShock(part: any, t0: number, t: number, p: Vector3, floorY: number)
	if t < t0 then
		part.Transparency = 1
		return
	end
	local k = ramp(t, t0, 0.9)
	local d = 2 + 14 * quintOut(k)
	part.Size = Vector3.new(0.15, d, d)
	part.CFrame = CFrame.new(p.X, floorY + 0.15, p.Z) * CFrame.Angles(0, 0, REL_90)
	part.Transparency = 0.3 + 0.7 * k
end

local function buildPillar(ctx: any): any
	local folder = ctx.folder
	local base = mkPart(folder, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), WHITE, 1, false)
	local top = mkPart(folder, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), WHITE, 1, false)
	local baseA = mkAtt(base)
	local topA = mkAtt(top)
	local colour = ColorSequence.new(WHITE, PURPLE)
	local halo = mkBeam(folder, baseA, topA, 7, 3, colour, fadedSeq(0.8, 1, 0))
	local core = mkBeam(folder, baseA, topA, 2.5, 1, colour, fadedSeq(0.35, 1, 0))

	local glow: any = Instance.new("PointLight")
	glow.Color = PURPLE
	glow.Brightness = 2
	glow.Range = 14
	glow.Parent = base

	local emitter: any = Instance.new("ParticleEmitter")
	emitter.Texture = SPARK_TEX
	emitter.Rate = 40
	emitter.Lifetime = NumberRange.new(1.2, 1.2)
	emitter.Speed = NumberRange.new(6, 10)
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.5, 0.15)
	emitter.Color = ColorSequence.new(WHITE, SPARK)
	emitter.Parent = base

	local shock1 = mkPart(folder, Enum.PartType.Cylinder, Vector3.new(0.15, 2, 2), PURPLE, 1, true)
	local shock2 = mkPart(folder, Enum.PartType.Cylinder, Vector3.new(0.15, 2, 2), PURPLE, 1, true)

	local hl: any = Instance.new("Highlight")
	hl.FillColor = WHITE
	hl.FillTransparency = 0.75
	hl.OutlineColor = PURPLE
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Adornee = ctx.character
	hl.Parent = folder

	return {
		duration = 6.0,
		dim = nil,
		extras = {},
		update = function(t: number, hrp: any)
			local p: Vector3 = hrp.Position
			local floorY = p.Y - 3
			local fade = ramp(t, 5.2, 0.8)
			base.CFrame = CFrame.new(p.X, floorY, p.Z)
			local rise = math.max(0.1, 60 * quintOut(ramp(t, 0, 0.6)))
			top.CFrame = CFrame.new(p.X, floorY + rise, p.Z)
			core.Transparency = fadedSeq(0.35, 1, fade)
			halo.Transparency = fadedSeq(0.8, 1, fade)
			glow.Brightness = 2 * (1 - fade)
			emitter.Enabled = t < 5.0
			updShock(shock1, 0, t, p, floorY)
			updShock(shock2, 0.35, t, p, floorY)
			hl.FillTransparency = 0.75 + 0.25 * fade
			hl.OutlineTransparency = fade
		end,
	}
end

-- ============================================================
-- V3 "Searchlight Sweep": 3 searchlights wander, converge and lock on the winner.
-- Each beam is a tapered Beam from its lamp to an aim point.
-- ============================================================
local function buildSearch(ctx: any): any
	local folder = ctx.folder
	local lamps: { any } = {}
	local aims: { any } = {}
	local beams: { any } = {}
	local spots: { any } = {}
	local beamColour = ColorSequence.new(WHITE)
	for i = 1, 3 do
		local lamp = mkPart(folder, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), WHITE, 1, false)
		local aim = mkPart(folder, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), WHITE, 1, false)
		lamps[i] = lamp
		aims[i] = aim
		spots[i] = mkSpot(lamp, Enum.NormalId.Front, 20, 60)
		beams[i] = mkBeam(folder, mkAtt(lamp), mkAtt(aim), 0.5, 5, beamColour, fadedSeq(0.6, 0.95, 0))
	end

	-- WINNER tag: parented to the character's Head (falls back to HRP), tracked for cleanup.
	local adornee: any = ctx.character:FindFirstChild("Head") or ctx.hrp
	local bb: any = Instance.new("BillboardGui")
	bb.Name = "WinFxWinnerTag"
	bb.Size = UDim2.fromOffset(160, 44)
	bb.AlwaysOnTop = true
	bb.StudsOffsetWorldSpace = Vector3.new(0, 11, 0) -- clears the game's overhead nameplate stack
	bb.Adornee = adornee
	bb.Parent = adornee
	local pill: any = Instance.new("Frame")
	pill.Size = UDim2.fromScale(1, 1)
	pill.BackgroundColor3 = PURPLE
	pill.BackgroundTransparency = 0.6
	pill.BorderSizePixel = 0
	pill.Parent = bb
	local corner: any = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = pill
	local pillScale: any = Instance.new("UIScale")
	pillScale.Scale = 0
	pillScale.Parent = pill
	local txt: any = Instance.new("TextLabel")
	txt.Size = UDim2.fromScale(1, 1)
	txt.BackgroundTransparency = 1
	txt.Text = "WINNER"
	txt.TextColor3 = WHITE
	txt.TextScaled = true
	local okFont, fontVal = pcall(Font.fromName, "Inter", Enum.FontWeight.Bold)
	if okFont then
		txt.FontFace = fontVal
	else
		txt.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	end
	txt.Parent = pill

	local confAnchor = mkPart(folder, Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), WHITE, 1, false)
	local conf: any = Instance.new("ParticleEmitter")
	conf.Texture = SPARK_TEX
	conf.Enabled = false
	conf.Lifetime = NumberRange.new(1.2, 1.8)
	conf.Speed = NumberRange.new(8, 14)
	conf.SpreadAngle = Vector2.new(60, 60)
	conf.Rotation = NumberRange.new(0, 360)
	conf.RotSpeed = NumberRange.new(-200, 200)
	conf.Size = NumberSequence.new(0.6, 0.3)
	conf.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.33, PURPLE),
		ColorSequenceKeypoint.new(0.66, GOLD),
		ColorSequenceKeypoint.new(1, SKY),
	})
	conf.Parent = confAnchor

	local fired = false

	return {
		duration = 6.0,
		dim = { b = -0.15, s = -0.15, inT = 0.5, outT = 4.8, outDur = 0.8 },
		extras = { bb },
		update = function(t: number, hrp: any)
			local p: Vector3 = hrp.Position
			local centre = p + Vector3.new(0, 1.5, 0)
			local c = quintOut(ramp(t, 1.8, 0.6))
			local fade = ramp(t, 4.8, 0.7)
			for i = 1, 3 do
				local ang = (i - 1) * (2 * math.pi / 3)
				local lampPos = p + Vector3.new(math.cos(ang) * 25, 18, math.sin(ang) * 25)
				local wander = p + Vector3.new(
					math.sin(t * 1.3 + i * 2.1) * 20,
					2 + math.sin(t * 0.9 + i) * 2.5,
					math.cos(t * 1.1 + i * 2.1) * 20
				)
				local aim: Vector3 = wander:Lerp(centre, c)
				lamps[i].CFrame = CFrame.lookAt(lampPos, aim)
				aims[i].CFrame = CFrame.new(aim)
				spots[i].Brightness = 6 * ramp(t, 0, 0.3) * (1 - fade)
				beams[i].Transparency = fadedSeq(0.6, 0.95, fade)
			end
			confAnchor.CFrame = CFrame.new(p + Vector3.new(0, 6, 0))
			if t >= 2.4 and not fired then
				fired = true
				conf:Emit(80)
			end
			pillScale.Scale = quintOut(ramp(t, 2.4, 0.35))
			bb.StudsOffsetWorldSpace = Vector3.new(0, 11 + ramp(t, 2.4, 2.6), 0)
			pill.BackgroundTransparency = 0.6 + 0.4 * fade
			txt.TextTransparency = fade
		end,
	}
end

local BUILDERS: { [number]: (any) -> any } = {
	[1] = buildStage,
	[2] = buildPillar,
	[3] = buildSearch,
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
		if s.cc then
			s.cc:Destroy()
			s.cc = nil
		end
		for _, inst in ipairs(s.extras or {}) do
			inst:Destroy()
		end
	end
	local leftoverCC = Lighting:FindFirstChild(CC_NAME)
	if leftoverCC then
		leftoverCC:Destroy()
	end
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if folder then
		folder:ClearAllChildren()
	end
end

function WinFx.play(variant: number, character: Model)
	WinFx.stopAll()
	local hrp: any = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local ctx = { character = character, hrp = hrp, folder = getFolder() }
	local build = BUILDERS[variant] or buildStage
	local fx = build(ctx)

	local s: any = { conn = nil, cc = nil, extras = fx.extras }
	session = s
	if fx.dim then
		local cc: any = Instance.new("ColorCorrectionEffect")
		cc.Name = CC_NAME
		cc.Brightness = 0
		cc.Saturation = 0
		cc.TintColor = WHITE
		cc.Parent = Lighting
		s.cc = cc
	end

	local t0 = os.clock()
	s.conn = RunService.Heartbeat:Connect(function()
		if session ~= s then
			return
		end
		local t = os.clock() - t0
		if t >= fx.duration or hrp.Parent == nil then
			WinFx.stopAll()
			return
		end
		if fx.dim and s.cc then
			local d = fx.dim
			local lvl = ramp(t, 0, d.inT) * (1 - ramp(t, d.outT, d.outDur))
			s.cc.Brightness = d.b * lvl
			s.cc.Saturation = d.s * lvl
		end
		fx.update(t, hrp)
	end)

	task.delay(HARD_CLEANUP, function()
		if session == s then
			WinFx.stopAll()
		end
	end)
end

return WinFx
