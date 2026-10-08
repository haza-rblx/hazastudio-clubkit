--!strict
-- Onboarding steps: 1 welcome / menu tour, 2 accent theme, 3 relationship status, 4 graphics
-- quality, 5 done. Each step fills the right-panel page and paints its stage preview; picks are
-- applied for real through ctx.apply (the same paths the Settings and Profile tabs use).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AccentDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.AccentDomain)
local AccentService = require(script.Parent.Parent.Parent.Services.AccentService)
local Kit = require(script.Parent.OnboardingKit)
local Controls = require(script.Parent.OnboardingControls)
local Stage = require(script.Parent.OnboardingStage)

type Ctx = Kit.Ctx
type Actor = Stage.Actor

local tween = Kit.tween
local WHITE = Kit.WHITE
local STAGE_W, STAGE_H = Kit.STAGE_W, Kit.STAGE_H

local Steps = {}

-- Section of the Profile tab that holds a named child (CoupleStatus lives in one of them).
local function findProfileSection(profileTab: any, childName: string): any
	if not profileTab then
		return nil
	end
	for _, s in ipairs(profileTab:GetChildren()) do
		local child = s:FindFirstChild(childName)
		if child then
			return child
		end
	end
	return nil
end

-- Step 1: a pointer taps the real Menu pill, the menu drops, the pointer walks its sections.
local function stepWelcome(ctx: Ctx, page: Frame, token: number)
	local live = function()
		return Kit.live(ctx, token)
	end
	local logoWrapper = if ctx.src.loadingScreen then ctx.src.loadingScreen:FindFirstChild("LogoWrapper", true) else nil
	local logoSrc = if logoWrapper then logoWrapper:FindFirstChildWhichIsA("ImageLabel") else nil
	if logoSrc then
		local logo = Kit.cleanClone(logoSrc)
		logo.Name = "Logo"
		logo.Size = UDim2.fromOffset(63, 44)
		logo.Position = UDim2.new()
		logo.AnchorPoint = Vector2.zero
		logo.LayoutOrder = 0
		-- The loading screen has faded its logo out by now; the clone inherits that.
		logo.ImageTransparency = 0
		logo.BackgroundTransparency = 1
		logo.Parent = page
	end
	Controls.header(
		page,
		"WELCOME",
		"Welcome to " .. ctx.placeName,
		"Everything you need lives in one place: the <b>Menu</b> at the top right."
	)
	local topBarMenu = ctx.src.topBarMenu
	if not topBarMenu then
		return
	end
	local menuPillSrc = ctx.src.menuPillSrc
	-- Sections the pointer walks.
	local chapters = { "Section1", "Section2", "Section4", "Section7" }

	-- Pill and menu at their real size, centred.
	local MENU_S = 1
	local PILL_Y = 20
	local pillSize = if menuPillSrc then menuPillSrc.AbsoluteSize else Vector2.new(110, 44)
	local DROP_TOP = PILL_Y + math.floor(pillSize.Y * MENU_S) + 8
	local DROP_W = math.floor(280 * MENU_S)
	local DROP_H = STAGE_H - DROP_TOP
	local DROP_X = math.floor((STAGE_W - DROP_W) / 2)
	local pillCentre = Vector2.new(DROP_X + DROP_W - pillSize.X * MENU_S / 2, PILL_Y + pillSize.Y * MENU_S / 2)
	local pillScale: UIScale? = nil
	if menuPillSrc then
		local pill = Kit.cleanClone(menuPillSrc)
		for _, d in ipairs(pill:GetDescendants()) do
			if d:IsA("TextLabel") and d.Text == "Close Menu" then
				d.Text = "Menu"
			end
		end
		local _, s = Stage.holder(ctx, pill, pillSize.X, pillSize.Y, pillCentre.X, pillCentre.Y, MENU_S, 0)
		pill.AutomaticSize = Enum.AutomaticSize.None
		pillScale = s
	end

	local drop = Instance.new("Frame")
	drop.Name = "Drop"
	drop.BackgroundTransparency = 1
	drop.ClipsDescendants = true
	drop.Position = UDim2.fromOffset(DROP_X, DROP_TOP)
	drop.Size = UDim2.fromOffset(DROP_W, 0)
	drop.Parent = ctx.stage
	local menuRoot = Instance.new("Frame")
	menuRoot.BackgroundTransparency = 1
	menuRoot.Size = UDim2.fromOffset(280, 838)
	local ms = Instance.new("UIScale")
	ms.Scale = MENU_S
	ms.Parent = menuRoot
	local menu = Kit.cleanClone(topBarMenu)
	menu.BackgroundTransparency = 1
	menu.Position = UDim2.fromScale(0, 0)
	menu.AnchorPoint = Vector2.zero
	menu.Size = UDim2.fromOffset(280, 838)
	menu.Visible = true
	menu.Parent = menuRoot
	menuRoot.Parent = drop

	local pointer, pScale = Stage.makePointer(ctx)
	local START = Vector2.new(70, STAGE_H - 40)
	pointer.Position = UDim2.fromOffset(START.X, START.Y)
	local function moveTo(v: Vector2, t: number)
		tween(
			pointer,
			t,
			{ Position = UDim2.fromOffset(v.X, v.Y) },
			Enum.EasingStyle.Quint,
			Enum.EasingDirection.InOut
		)
		task.wait(t)
	end
	local function tap(v: Vector2, target: UIScale?)
		tween(pScale, 0.08, { Scale = 0.75 })
		if target then
			tween(target, 0.08, { Scale = MENU_S * 0.9 })
		end
		task.wait(0.09)
		Stage.ripple(ctx, v.X, v.Y)
		tween(pScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		if target then
			tween(target, 0.35, { Scale = MENU_S }, Enum.EasingStyle.Back)
		end
		task.wait(0.3)
	end
	local function rowsOf(section: Instance): { GuiObject }
		local list: { GuiObject } = {}
		for _, b in ipairs(section:GetChildren()) do
			if b:IsA("TextButton") then
				table.insert(list, b)
			end
		end
		table.sort(list, function(a, b)
			return a.AbsolutePosition.Y < b.AbsolutePosition.Y
		end)
		return list
	end
	local restColor: { [GuiObject]: Color3 } = {}
	for _, b in ipairs(menu:GetDescendants()) do
		if b:IsA("TextButton") then
			restColor[b] = b.BackgroundColor3
		end
	end
	local function light(section: Instance?)
		for b, c in pairs(restColor) do
			local on = section ~= nil and b.Parent == section
			tween(b, 0.25, { BackgroundColor3 = if on then c:Lerp(WHITE, 0.14) else c })
		end
	end

	task.spawn(function()
		while live() do
			drop.Size = UDim2.fromOffset(DROP_W, 0)
			menuRoot.Position = UDim2.fromOffset(0, 0)
			pointer.Position = UDim2.fromOffset(START.X, START.Y)
			pointer.BackgroundTransparency = 0
			light(nil)
			task.wait(0.6)
			if not live() then
				return
			end
			moveTo(pillCentre, 0.9)
			tap(pillCentre, pillScale)
			tween(drop, 0.45, { Size = UDim2.fromOffset(DROP_W, DROP_H) })
			task.wait(0.5)
			for _, sectionName in ipairs(chapters) do
				if not live() then
					return
				end
				local section = menu:FindFirstChild(sectionName)
				local rows = if section then rowsOf(section) else nil
				if section and rows and rows[1] then
					local k = ctx.shellScale.Scale
					local top = (section.AbsolutePosition.Y - menuRoot.AbsolutePosition.Y) / k
					local bottom = top + section.AbsoluteSize.Y / k
					local scroll = math.clamp((top + bottom) / 2 - DROP_H * 0.45, 0, 838 * MENU_S - DROP_H)
					tween(
						menuRoot,
						0.6,
						{ Position = UDim2.fromOffset(0, -scroll) },
						Enum.EasingStyle.Quint,
						Enum.EasingDirection.InOut
					)
					local row = rows[1]
					local rowY = (row.AbsolutePosition.Y - menuRoot.AbsolutePosition.Y + row.AbsoluteSize.Y / 2) / k
					moveTo(Vector2.new(DROP_X + DROP_W * 0.62, DROP_TOP + rowY - scroll), 0.6)
					light(section)
				end
				task.wait(1.5)
			end
			if not live() then
				return
			end
			tap(Vector2.new(pointer.Position.X.Offset, pointer.Position.Y.Offset), nil)
			light(nil)
			tween(drop, 0.35, { Size = UDim2.fromOffset(DROP_W, 0) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			tween(pointer, 0.35, { BackgroundTransparency = 1 })
			task.wait(1.2)
		end
	end)
end

-- Step 2: floating collage of components that wear the accent; a pick spreads as a wave.
local function stepTheme(ctx: Ctx, page: Frame, token: number)
	Controls.header(page, "STEP 1 OF 3", "Pick your colour", "Tints the whole interface. Change it anytime in Settings.")
	local settingsTab = ctx.src.settingsTab
	local topBarMenu = ctx.src.topBarMenu
	local function firstToggleRow(): any
		local visual = Kit.find(settingsTab, "visual_Section")
		if not visual then
			return nil
		end
		for _, d in ipairs(visual:GetDescendants()) do
			if d:IsA("TextButton") and d:FindFirstChild("Toggle") then
				return d
			end
		end
		return nil
	end
	local cards = {
		{
			src = if topBarMenu then topBarMenu:FindFirstChild("MusicPlayerButton", true) else nil,
			size = Vector2.new(280, 54),
			x = 164,
			y = 62,
			rot = -3,
		},
		{ src = firstToggleRow(), size = Vector2.new(264, 36), x = 156, y = 138, rot = 2 },
		{
			src = Kit.find(settingsTab, "graphics_Section", "SectionContentWrapper", "graphicsPreset"),
			size = Vector2.new(264, 118),
			x = 164,
			y = 240,
			rot = -2,
		},
		{
			src = Kit.find(settingsTab, "music_Section", "SectionContentWrapper", "musicVolume"),
			size = Vector2.new(264, 88),
			x = 156,
			y = 356,
			rot = 3,
		},
	}
	-- Real size. Corners: the same radius on all four sides, not the grouped-row rule's small
	-- bottom corners; rows become pills, cards keep 18 everywhere.
	local CARD_S = 1
	local function fullRound(card: any, height: number)
		local radius = if height <= 54 then UDim.new(1, 0) else UDim.new(0, 18)
		local corner = card:FindFirstChildOfClass("UICorner") or Kit.round(card, radius)
		corner.CornerRadius = radius
		for _, side in ipairs({ "TopLeftRadius", "TopRightRadius", "BottomLeftRadius", "BottomRightRadius" }) do
			pcall(function()
				corner[side] = radius
			end)
		end
	end
	local holders: { [number]: { hd: Frame, s: UIScale, base: any } } = {}
	for i, c in ipairs(cards) do
		if c.src then
			local card = Kit.cleanClone(c.src)
			fullRound(card, c.size.Y)
			local hd, s = Stage.holder(ctx, card, c.size.X, c.size.Y, c.x, c.y, CARD_S, c.rot)
			hd.ZIndex = 5
			Stage.popIn(s, CARD_S, 0.08 * i)
			holders[i] = { hd = hd, s = s, base = c }
		end
	end
	Kit.animate(ctx, token, function(t)
		for i, h in pairs(holders) do
			local ph = i * 1.7
			h.hd.Position = UDim2.fromOffset(h.base.x, h.base.y + math.sin(t * 1.3 + ph) * 4)
			h.hd.Rotation = h.base.rot + math.sin(t * 0.9 + ph) * 0.8
		end
	end)

	local function wave(id: string)
		local before = ctx.stageBg.BackgroundColor3
		local cover = Instance.new("Frame")
		cover.Size = UDim2.fromScale(1, 1)
		cover.BackgroundColor3 = before
		cover.BorderSizePixel = 0
		cover.ZIndex = 1
		cover:SetAttribute(Kit.NO_TINT, true)
		cover.Parent = ctx.stage
		ctx.apply.theme(id)
		-- The surface tint repaints the stage once the value settles; wait for it (bounded).
		for _ = 1, 12 do
			task.wait()
			if ctx.stageBg.BackgroundColor3 ~= before then
				break
			end
		end
		local circle = Stage.dot(0, ctx.stageBg.BackgroundColor3, 2)
		circle.Position = UDim2.fromOffset(STAGE_W / 2, STAGE_H / 2)
		circle.Parent = ctx.stage
		tween(circle, 0.6, { Size = UDim2.fromOffset(600, 600) })
		for i, h in pairs(holders) do
			task.delay(0.06 * i, function()
				if h.s.Parent then
					tween(h.s, 0.12, { Scale = CARD_S * 1.06 })
					task.wait(0.12)
					tween(h.s, 0.4, { Scale = CARD_S }, Enum.EasingStyle.Back)
				end
			end)
		end
		task.delay(0.65, function()
			cover:Destroy()
			circle:Destroy()
		end)
	end

	Controls.themeGrid(ctx, page, 10, function(id)
		ctx.picks.theme = AccentDomain.label(id)
		if AccentService.get().id ~= id then
			task.spawn(wave, id)
		else
			ctx.apply.theme(id)
		end
	end)
end

-- Step 3: full-body 3D scene. Single = halo; Taken = partner silhouette facing you;
-- For Fun = three ghost silhouettes fanned behind + rising sparkles.
local function stepRelationship(ctx: Ctx, page: Frame, token: number)
	Controls.header(
		page,
		"STEP 2 OF 3",
		"Relationship status",
		"Shown on your profile. Pick <b>Taken</b> to show your couple's name."
	)
	local ownerCouple = findProfileSection(ctx.src.profileTab, "CoupleStatus")
	local icons: { [string]: string? } = {
		Single = Controls.iconFrom(ownerCouple, "Single"),
		Taken = Controls.iconFrom(ownerCouple, "Taken"),
		["For Fun"] = Controls.iconFrom(ownerCouple, "For Fun"),
	}

	local ghosts: { Actor } = {}
	for _, z in ipairs({ 2, 2, 1 }) do
		local g = Stage.actor(ctx, true, z)
		if g then
			table.insert(ghosts, g)
		end
	end
	local partner = Stage.actor(ctx, true, 3)
	local me = Stage.actor(ctx, false, 4)
	if not me then
		return
	end
	local H = me.H
	local all: { Actor } = { me }
	if partner then
		table.insert(all, partner)
	end
	for _, g in ipairs(ghosts) do
		table.insert(all, g)
	end

	local halo = Stage.dot(230, WHITE, 1)
	halo.BackgroundTransparency = 1
	halo.Position = UDim2.fromOffset(STAGE_W / 2, me.screenY(H * 0.55))
	local haloStroke = Instance.new("UIStroke")
	haloStroke.Color = WHITE
	haloStroke.Thickness = 2
	haloStroke.Transparency = 1
	haloStroke.Parent = halo
	local haloScale = Instance.new("UIScale")
	haloScale.Parent = halo
	halo.Parent = ctx.stage

	local footY = me.screenY(0)

	local mode = "Single"
	Kit.animate(ctx, token, function(t)
		for i, a in ipairs(all) do
			a.apply(math.sin(t * 1.1 + i) * 0.07)
		end
		haloScale.Scale = 1 + math.sin(t * 2) * 0.04
	end)

	task.spawn(function()
		while Kit.live(ctx, token) do
			if mode == "For Fun" then
				local x = STAGE_W / 2 + math.random(-130, 130)
				local y = math.random(80, math.floor(footY))
				local d = Stage.dot(math.random(4, 8), WHITE, 9)
				d.BackgroundTransparency = 0.1
				d.Position = UDim2.fromOffset(x, y)
				d.Parent = ctx.stage
				tween(
					d,
					1.4,
					{ Position = UDim2.fromOffset(x, y - 40), BackgroundTransparency = 1 },
					Enum.EasingStyle.Sine
				)
				task.delay(1.45, function()
					d:Destroy()
				end)
			end
			task.wait(0.18)
		end
	end)

	local function place(a: Actor?, x: number, z: number, yaw: number, transp: number?, t: number)
		if not a then
			return
		end
		tween(a.x, t, { Value = x })
		tween(a.z, t, { Value = z })
		tween(a.yaw, t, { Value = yaw })
		if transp then
			tween(a.vp, t, { ImageTransparency = transp })
		end
	end

	local FACE = 0.5
	local OFF = H * 1.1
	local function setMode(name: string, instant: boolean)
		mode = name
		local t = if instant then 0 else 0.6
		if name == "Taken" then
			place(me, -H * 0.2, 0, FACE, nil, t)
			place(partner, H * 0.2, 0, -FACE, 0.15, t)
			for _, g in ipairs(ghosts) do
				place(g, g.x.Value, g.z.Value, g.yaw.Value, 1, t)
			end
			tween(haloStroke, t, { Transparency = 1 })
		else
			place(partner, OFF, 0, -FACE, 1, t)
			place(me, 0, 0, 0, nil, t)
			if name == "For Fun" then
				tween(haloStroke, t, { Transparency = 1 })
				local spots = {
					{ -H * 0.34, -H * 0.45, 0.45 },
					{ H * 0.34, -H * 0.45, -0.45 },
					{ 0, -H * 0.95, 0 },
				}
				for i, g in ipairs(ghosts) do
					local sp = spots[i]
					if sp then
						g.x.Value, g.z.Value, g.yaw.Value = sp[1] * 0.6, sp[2] - H * 0.3, sp[3]
						task.delay((i - 1) * 0.08, function()
							place(g, sp[1], sp[2], sp[3], 0.45, if instant then 0 else 0.5)
						end)
					end
				end
			else
				for _, g in ipairs(ghosts) do
					place(g, g.x.Value, g.z.Value, g.yaw.Value, 1, t)
				end
				tween(haloStroke, t, { Transparency = 0.7 })
			end
		end
	end

	Controls.optionList(ctx, page, 10, {
		{ key = "Single", title = "Single", hint = "Open to meeting people", icon = icons.Single },
		{ key = "Taken", title = "Taken", hint = "Show your couple's name", icon = icons.Taken },
		{ key = "For Fun", title = "For Fun", hint = "Just here for the vibes", icon = icons["For Fun"] },
	}, ctx.picks.status or ctx.apply.currentStatus, function(key, initial)
		if not initial then
			ctx.picks.status = key
			ctx.apply.status(key)
		end
		setMode(key, initial)
	end)
end

-- Step 4: graphics preset. The turntable, lighting per preset.
local function stepQuality(ctx: Ctx, page: Frame, token: number)
	Controls.header(page, "STEP 3 OF 3", "How it looks", "Pick what your device can handle. Balance suits most phones.")
	local ownerPreset = Kit.find(ctx.src.settingsTab, "graphics_Section", "SectionContentWrapper", "graphicsPreset")
	local a = Stage.turntable(ctx, token)
	Controls.optionList(ctx, page, 10, {
		{ key = "Low", title = "Low", hint = "Smoothest on older phones", icon = Controls.iconFrom(ownerPreset, "Low") },
		{
			key = "Balance",
			title = "Balance",
			hint = "Recommended for most devices",
			icon = Controls.iconFrom(ownerPreset, "Balance"),
		},
		{ key = "High", title = "High", hint = "Best visuals, newer devices", icon = Controls.iconFrom(ownerPreset, "High") },
	}, ctx.picks.quality or ctx.apply.currentQuality, function(name, initial)
		if not initial then
			ctx.picks.quality = name
			ctx.apply.quality(name)
		end
		local look = Stage.LIGHTING[name]
		if a and look then
			tween(a.vp, if initial then 0 else 0.5, { Ambient = look.Ambient, LightColor = look.LightColor })
		end
	end)
end

-- Step 5: avatar + recap chips (ReminderCard header pills) popping in around it.
local function stepDone(ctx: Ctx, page: Frame, token: number)
	Controls.header(page, "ALL SET", "You're ready", "Open the <b>Menu</b> anytime to change these in Settings.")
	Stage.turntable(ctx, token)
	local picks = ctx.picks
	-- Ticked by default: finishing once means not seeing it again, unless the player unticks.
	picks.dontShow = true
	Controls.checkRow(ctx, page, 10, "Don't show this again", true, function(checked)
		picks.dontShow = checked
	end)
	local ownerCouple = findProfileSection(ctx.src.profileTab, "CoupleStatus")
	local ownerPreset = Kit.find(ctx.src.settingsTab, "graphics_Section", "SectionContentWrapper", "graphicsPreset")
	local statusText = picks.status or ctx.apply.currentStatus
	local qualityText = picks.quality or ctx.apply.currentQuality
	local chips = {
		{
			text = "Theme  " .. (picks.theme or AccentDomain.label(AccentService.get().id)),
			x = 104,
			y = 70,
			rot = -4,
			swatch = true,
		},
		{
			text = statusText,
			x = 236,
			y = 150,
			rot = 3,
			icon = if ownerCouple then Controls.iconFrom(ownerCouple, statusText) else nil,
		},
		{
			text = "Quality  " .. qualityText,
			x = 110,
			y = 356,
			rot = 2,
			icon = if ownerPreset then Controls.iconFrom(ownerPreset, qualityText) else nil,
		},
	}
	local floating: { [number]: { hd: Frame, base: any } } = {}
	for i, c in ipairs(chips) do
		local p = Stage.statusPill(ctx, c.x, c.y, 6)
		if p then
			-- The theme chip shows the picked colour as a dot where the other chips show an icon.
			p.set(c.text, if c.swatch then "" else c.icon, true)
			local chipIcon = p.hd:FindFirstChild("Icon", true)
			if c.swatch and chipIcon then
				local dotFrame = Stage.dot(18, if AccentService.isDesign() then Kit.ACCENT_LABEL else AccentService.get().fill, 2)
				dotFrame.Position = UDim2.fromScale(0.5, 0.5)
				dotFrame.Parent = chipIcon
			end
			p.hd.Rotation = c.rot
			Stage.popIn(p.scale, 1, 0.25 + 0.12 * i)
			floating[i] = { hd = p.hd, base = c }
		end
	end
	Kit.animate(ctx, token, function(t)
		for i, c in pairs(floating) do
			c.hd.Position = UDim2.fromOffset(c.base.x, c.base.y + math.sin(t * 1.4 + i * 2) * 4)
		end
	end)
end

Steps.list = { stepWelcome, stepTheme, stepRelationship, stepQuality, stepDone } :: { (Ctx, Frame, number) -> () }

return Steps
