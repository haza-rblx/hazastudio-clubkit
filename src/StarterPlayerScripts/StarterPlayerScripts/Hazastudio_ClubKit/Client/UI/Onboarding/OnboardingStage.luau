--!strict
-- Onboarding left stage: centred holders (scale and rotation grow from the middle), the pointer,
-- the full-stage 3D avatar actors and the recap pill.

local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local Kit = require(script.Parent.OnboardingKit)

type Ctx = Kit.Ctx

local tween = Kit.tween
local WHITE = Kit.WHITE
local STAGE_H = Kit.STAGE_H

local Stage = {}

-- A centred holder at stage point (x, y): scale/rotation grow from the middle (owner rule).
function Stage.holder(
	ctx: Ctx,
	content: any,
	w: number,
	h: number,
	x: number,
	y: number,
	scale: number?,
	rot: number?
): (Frame, UIScale)
	local hd = Instance.new("Frame")
	hd.BackgroundTransparency = 1
	hd.AnchorPoint = Vector2.new(0.5, 0.5)
	hd.Size = UDim2.fromOffset(w, h)
	hd.Position = UDim2.fromOffset(x, y)
	hd.Rotation = rot or 0
	local s = Instance.new("UIScale")
	s.Scale = scale or 1
	s.Parent = hd
	content.AnchorPoint = Vector2.zero
	content.Position = UDim2.fromScale(0, 0)
	content.Size = UDim2.fromOffset(w, h)
	content.Visible = true
	content.Parent = hd
	hd.Parent = ctx.stage
	return hd, s
end

function Stage.popIn(s: UIScale, to: number, delay: number?)
	s.Scale = to * 0.6
	task.delay(delay or 0, function()
		if s.Parent then
			tween(s, 0.5, { Scale = to }, Enum.EasingStyle.Back)
		end
	end)
end

function Stage.dot(size: number, color: Color3, z: number?): Frame
	local d = Instance.new("Frame")
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Size = UDim2.fromOffset(size, size)
	d.BackgroundColor3 = color
	d.BorderSizePixel = 0
	d.ZIndex = z or 1
	d:SetAttribute(Kit.NO_TINT, true)
	Kit.round(d, UDim.new(1, 0))
	return d
end

-- Pointer: plain dot + ring (no emoji/icon art; the owner swaps in a real asset).
function Stage.makePointer(ctx: Ctx): (Frame, UIScale)
	local p = Stage.dot(18, WHITE, 40)
	p.Name = "Pointer"
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 2
	stroke.Transparency = 0.4
	stroke.Parent = p
	local s = Instance.new("UIScale")
	s.Parent = p
	p.Parent = ctx.stage
	return p, s
end

function Stage.ripple(ctx: Ctx, x: number, y: number)
	local r = Stage.dot(18, WHITE, 39)
	r.BackgroundTransparency = 1
	r.Position = UDim2.fromOffset(x, y)
	local stroke = Instance.new("UIStroke")
	stroke.Color = WHITE
	stroke.Thickness = 2
	stroke.Parent = r
	r.Parent = ctx.stage
	tween(r, 0.5, { Size = UDim2.fromOffset(56, 56) })
	tween(stroke, 0.5, { Transparency = 1 })
	task.delay(0.55, function()
		r:Destroy()
	end)
end

-- 3D actor: the profile's avatar model in its own full-stage ViewportFrame. Every actor gets the
-- same camera framing (from its height), so x/z/yaw place them in one shared "world".
local FOV = 30

export type Actor = {
	vp: ViewportFrame,
	model: Model,
	H: number,
	visH: number,
	lookY: number,
	x: NumberValue,
	z: NumberValue,
	yaw: NumberValue,
	apply: (extraYaw: number?) -> (),
	screenY: (worldY: number) -> number,
}

local function sourceModel(ctx: Ctx): (Model?, ViewportFrame?)
	local summary = ctx.src.summarySrc
	local vp = if summary then summary:FindFirstChild("3DTargetPlayerAvatar", true) else nil
	local m = if vp then vp:FindFirstChildWhichIsA("Model", true) else nil
	if m then
		return m, vp
	end
	local ch = Players.LocalPlayer.Character
	if ch then
		ch.Archivable = true
		return ch, nil
	end
	return nil, nil
end

function Stage.actor(ctx: Ctx, silhouette: boolean, z: number): Actor?
	local srcM, srcVp = sourceModel(ctx)
	if not srcM then
		return nil
	end
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Actor"
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.ZIndex = z
	vp:SetAttribute(Kit.NO_TINT, true)
	if srcVp then
		vp.Ambient = srcVp.Ambient
		vp.LightColor = srcVp.LightColor
		vp.LightDirection = srcVp.LightDirection
	end
	if silhouette then
		vp.ImageColor3 = Color3.new(0, 0, 0)
		vp.ImageTransparency = 1
	end
	local wm = Instance.new("WorldModel")
	wm.Parent = vp
	local m = Kit.cleanClone(srcM) :: Model
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
		end
	end
	m.Parent = wm
	m:PivotTo(CFrame.new())
	local c, size = m:GetBoundingBox()
	local H = size.Y
	local visH = H / 0.7
	local D = (visH / 2) / math.tan(math.rad(FOV / 2))
	local lookY = H * 0.44
	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.CFrame = CFrame.lookAt(Vector3.new(0, lookY, D), Vector3.new(0, lookY, 0))
	cam.Parent = vp
	vp.CurrentCamera = cam
	vp.Parent = ctx.stage
	local ax, az, ayaw = Instance.new("NumberValue"), Instance.new("NumberValue"), Instance.new("NumberValue")
	local offset = CFrame.new(-c.Position.X, -(c.Position.Y - size.Y / 2), -c.Position.Z)
	-- Yaw: pi faces the camera; positive turns the avatar toward stage-right.
	local function apply(extraYaw: number?)
		m:PivotTo(
			CFrame.new(ax.Value, 0, az.Value)
				* CFrame.Angles(0, math.pi + ayaw.Value + (extraYaw or 0), 0)
				* offset
		)
	end
	-- Stage-space y of a world height on the actor (for UI drawn at the feet / chest).
	local function screenY(worldY: number): number
		return STAGE_H / 2 - ((worldY - lookY) / (visH / 2)) * (STAGE_H / 2)
	end
	local a: Actor = {
		vp = vp,
		model = m,
		H = H,
		visH = visH,
		lookY = lookY,
		x = ax,
		z = az,
		yaw = ayaw,
		apply = apply,
		screenY = screenY,
	}
	apply()
	return a
end

-- Full-body avatar turning slowly; lighting follows the quality pick.
Stage.LIGHTING = {
	Low = { Ambient = Color3.fromRGB(175, 175, 175), LightColor = Color3.fromRGB(70, 70, 70) },
	Balance = { Ambient = Color3.fromRGB(120, 120, 128), LightColor = Color3.fromRGB(190, 190, 190) },
	High = { Ambient = Color3.fromRGB(60, 60, 75), LightColor = Color3.fromRGB(255, 250, 240) },
} :: { [string]: { Ambient: Color3, LightColor: Color3 } }

function Stage.turntable(ctx: Ctx, token: number): Actor?
	local a = Stage.actor(ctx, false, 3)
	if not a then
		return nil
	end
	Kit.animate(ctx, token, function(t)
		a.yaw.Value = t * 0.7
		a.apply()
	end)
	local preset = Stage.LIGHTING[ctx.picks.quality or ""]
	if preset then
		a.vp.Ambient = preset.Ambient
		a.vp.LightColor = preset.LightColor
	end
	return a
end

export type Pill = {
	hd: Frame,
	scale: UIScale,
	set: (text: string, image: string?, instant: boolean?) -> (),
}

-- Recap pill: the owner's ReminderCard header with an optional icon. nil when the place has no
-- ReminderCard (19-EventReminders), so callers skip the chip.
function Stage.statusPill(ctx: Ctx, x: number, y: number, z: number?): Pill?
	local reminderCard = ctx.src.reminderCard
	local headerSrc = if reminderCard then reminderCard:FindFirstChild("Header") else nil
	if not headerSrc then
		return nil
	end
	local tag = Kit.cleanClone(headerSrc)
	for _, n in ipairs({ "CloseWrapper", "Fill" }) do
		local c = tag:FindFirstChild(n)
		if c then
			c:Destroy()
		end
	end
	local tagIcon = tag:FindFirstChild("Icon")
	if tagIcon then
		local ph = tagIcon:FindFirstChild("Placeholder")
		if ph then
			ph:Destroy()
		end
		tagIcon.ImageColor3 = WHITE
	end
	-- Full round (owner 2026-10-08): the header's 18/4 corners become a pill.
	local tagCorner = tag:FindFirstChildOfClass("UICorner")
	if tagCorner then
		tagCorner.CornerRadius = UDim.new(1, 0)
		for _, side in ipairs({ "TopLeftRadius", "TopRightRadius", "BottomLeftRadius", "BottomRightRadius" }) do
			pcall(function()
				(tagCorner :: any)[side] = UDim.new(1, 0)
			end)
		end
	end
	local tagLabel = tag:FindFirstChild("Label")
	local hd, s = Stage.holder(ctx, tag, 160, 40, x, y, 1, 0)
	tag.AutomaticSize = Enum.AutomaticSize.None
	hd.ZIndex = z or 8
	local function set(text: string, image: string?, instant: boolean?)
		if tagLabel then
			tagLabel.Text = text
		end
		if tagIcon then
			tagIcon.Image = image or ""
		end
		-- TextBounds is 0 until rendered; measure up front so the pill stays centred.
		local w = TextService:GetTextSize(text, 16, Enum.Font.GothamBold, Vector2.new(1000, 40)).X
			+ (if image then 74 else 44)
		hd.Size = UDim2.fromOffset(w, 40)
		tag.Size = UDim2.fromOffset(w, 40)
		if not instant then
			s.Scale = 0.85
			tween(s, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
	local pill: Pill = { hd = hd, scale = s, set = set }
	return pill
end

return Stage
