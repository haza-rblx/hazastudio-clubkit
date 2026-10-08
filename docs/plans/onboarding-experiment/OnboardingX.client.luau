-- Onboarding experiment v5 (2026-10-08) — runs in a solo playtest via eval_client_runtime
-- (wrapped as _G.__OnbXBoot), not part of the kit. Key O restarts; _G.__OnbX.goTo(n) jumps;
-- _G.__OnbXSteps[n] = function(page, token, ctx) hot-swaps one step (ctx = _G.__OnbXCtx).
-- Shell = the owner's 17-OnboardingGUI split sketch (640x420). Stage previews:
--   1 Welcome  — a pointer taps the real Menu pill, the menu drops, the pointer walks its sections
--   2 Theme    — floating collage of accent-wearing components; a pick spreads as a circular wave
--   3 Status   — full-body 3D scene: Single halo / Taken partner silhouette + thread / For Fun ghosts
--   4 Quality  — full-body avatar turntable, lighting per preset
--   5 Done     — avatar + recap chips (ReminderCard header pills)
-- 3D actors: one full-stage ViewportFrame each with its own framing camera, so nothing is cropped
-- (the profile's square avatar viewport cut off legs and accessories).
-- Right panel: Back on top, full-width primary at the bottom; controls redesigned (owner).
-- Choices are a live preview only (theme via AccentService.set); nothing is saved.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local lp = Players.LocalPlayer
local pg = lp:WaitForChild("PlayerGui")
local client = lp.PlayerScripts.Hazastudio_ClubKit.Client
local UIMotion = require(client.Utils.UIMotion)
local AccentService = require(client.Services.AccentService)
local Icon = require(ReplicatedStorage.Hazastudio_ClubKit.Icon)
local GroupedRowCornerUtil = require(client.Utils.GroupedRowCornerUtil)
local AccentDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.AccentDomain)

local G = _G
if G.__OnbX then
	G.__OnbX.destroy()
end

local INTER = "rbxassetid://12187365364"
local SHELL_W, SHELL_H = 640, 420
local STAGE_W, STAGE_H = SHELL_W / 2, SHELL_H
local TOP_H = 48
local MUTED = Color3.fromHex("7c7c7c")
local BODY = Color3.fromHex("bebebe")
local ACCENT_LABEL = Color3.fromHex("ea4b07")
local NO_TINT = "AccentNoTint"
local ROW_BG = Color3.fromHex("1e1e1e")
local ROW_ON = Color3.fromHex("262626")
local SUB = Color3.fromHex("b1b1b1")
local WHITE = Color3.new(1, 1, 1)

local conns = {}
local alive = true
local runToken = 0
local picks = {}

local function tween(inst, t, props, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function live(token)
	return alive and runToken == token
end

local function animate(token, fn)
	local t0 = os.clock()
	local c
	c = RunService.RenderStepped:Connect(function()
		if not live(token) then
			c:Disconnect()
			return
		end
		fn(os.clock() - t0)
	end)
	table.insert(conns, c)
end

local function round(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r
	c.Parent = inst
	return c
end

local function label(parent, text, size, weight, color, order)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.RichText = true
	l.FontFace = Font.new(INTER, weight, Enum.FontStyle.Normal)
	l.TextSize = size
	l.TextColor3 = color
	l.Text = text
	l.LayoutOrder = order
	l.Parent = parent
	return l
end

local function textLabel(parent, text, size, weight, color)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = Font.new(INTER, weight, Enum.FontStyle.Normal)
	l.TextSize = size
	l.TextColor3 = color
	l.Text = text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = parent
	return l
end

-- ── owner components ───────────────────────────────────────────────────────────────────────
local menuGui = pg:WaitForChild("07-MenuGUI")
local menuInner = menuGui.MenuGUIWrapper.MenuGUIWrapper
local settingsTab = menuInner.SettingsTab
local profileTab = menuInner.ProfileTab
local topBarMenu = pg["15-TopMenuGUI"].TopBarMenu
local questPopup = pg["18-EventQuestPopup"]
local reminderCard = pg["19-EventReminders"].Templates.ReminderCard
local sketch = pg["17-OnboardingGUI"].Frame
local summarySrc = profileTab.PlayerInfoSummary

local menuPillSrc = nil
for _, icon in pairs(Icon.getIcons()) do
	local ok, lbl = pcall(function()
		return icon:getInstance("IconLabel")
	end)
	if ok and lbl and (lbl.Text == "Menu" or lbl.Text == "Close Menu") then
		menuPillSrc = icon.widget
	end
end

local function findProfileSection(childName)
	for _, s in ipairs(profileTab:GetChildren()) do
		if s:FindFirstChild(childName) then
			return s
		end
	end
	return nil
end

local function cleanClone(src)
	local c = src:Clone()
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("UIDragDetector") then
			d:Destroy()
		end
	end
	for _, d in ipairs({ c, table.unpack(c:GetDescendants()) }) do
		if d:GetAttribute("UIMotionBound") ~= nil then
			d:SetAttribute("UIMotionBound", nil)
		end
	end
	return c
end

local placeName = game.Name
pcall(function()
	placeName = MarketplaceService:GetProductInfo(game.PlaceId).Name
end)

-- ── shell ──────────────────────────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "OnboardingExperiment"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 250
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local dim = Instance.new("Frame")
dim.Name = "Dim"
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 1
dim.Active = true
dim.Parent = gui

local shell = Instance.new("CanvasGroup")
shell.Name = "Shell"
shell.AnchorPoint = Vector2.new(0.5, 0.5)
shell.Position = UDim2.fromScale(0.5, 0.5)
shell.Size = UDim2.fromOffset(SHELL_W, SHELL_H)
shell.BackgroundColor3 = sketch.BackgroundColor3
shell.BorderSizePixel = 0
shell.GroupTransparency = 1
shell.Parent = gui
cleanClone(sketch:FindFirstChildOfClass("UICorner")).Parent = shell
local shellScale = Instance.new("UIScale")
shellScale.Scale = 0.94
shellScale.Parent = shell

local leftSrc, rightSrc
for _, f in ipairs(sketch:FindFirstChildOfClass("Frame"):GetChildren()) do
	if f:IsA("Frame") then
		if f.AnchorPoint.X == 0 then
			leftSrc = f
		else
			rightSrc = f
		end
	end
end

local stage = cleanClone(leftSrc)
stage.Name = "Stage"
for _, c in ipairs(stage:GetChildren()) do
	c:Destroy()
end
stage.ClipsDescendants = true
stage.Parent = shell

local panel = cleanClone(rightSrc)
panel.Name = "Panel"
for _, c in ipairs(panel:GetChildren()) do
	if not c:IsA("UIPadding") then
		c:Destroy()
	end
end
panel.BackgroundTransparency = 1
panel.ClipsDescendants = true
local pad = panel:FindFirstChildOfClass("UIPadding")
pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 18), UDim.new(0, 18)
pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 18), UDim.new(0, 18)
panel.Parent = shell

local wipe = Instance.new("Frame")
wipe.Name = "Wipe"
wipe.Size = UDim2.fromScale(1, 1)
wipe.BackgroundColor3 = stage.BackgroundColor3
for k, v in pairs(leftSrc:GetAttributes()) do
	wipe:SetAttribute(k, v)
end
wipe.BackgroundTransparency = 1
wipe.ZIndex = 50
wipe.BorderSizePixel = 0
wipe.Parent = stage

-- Top row: Back on the left (owner: "backnya pindah atas"), the close X on the right.
local close = cleanClone(questPopup:FindFirstChild("CloseButton", true))
-- Back at the owner component's own 40px height; the X scaled up with it (16 → 20), centred on it.
close.AnchorPoint = Vector2.new(1, 0.5)
close.Size = UDim2.fromOffset(20, 20)
close.Position = UDim2.new(1, -20, 0, 18 + 20)
close.ZIndex = 20
close.Parent = shell

local back = cleanClone(settingsTab.BacktoMainMenuButton)
back.Size = UDim2.fromOffset(100, 40)
back.Position = UDim2.fromOffset(0, 0)
back:FindFirstChildOfClass("TextLabel").Text = "Back"
back.Parent = panel

-- Primary: the quest popup SubmitButton, full width like the ReminderCard ButtonSlot.
local primary = cleanClone(questPopup:FindFirstChild("SubmitButton", true))
primary.AnchorPoint = Vector2.new(0, 1)
primary.Position = UDim2.fromScale(0, 1)
primary.Size = UDim2.new(1, 0, 0, 40)
primary.Parent = panel
local primaryLabel = primary:FindFirstChildOfClass("TextLabel")
primaryLabel.TextXAlignment = Enum.TextXAlignment.Center

local pageHost = Instance.new("Frame")
pageHost.Name = "Page"
pageHost.BackgroundTransparency = 1
pageHost.Size = UDim2.new(1, 0, 1, -52)
pageHost.Parent = panel

-- ── stage helpers ────────────────────────────────────────────────────────────────────────
local function clearStage()
	for _, c in ipairs(stage:GetChildren()) do
		if c ~= wipe then
			c:Destroy()
		end
	end
end

-- A centred holder at stage point (x, y): scale/rotation grow from the middle (owner rule).
local function holder(content, w, h, x, y, scale, rot, class)
	local hd = Instance.new(class or "Frame")
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
	hd.Parent = stage
	return hd, s
end

local function popIn(hd, s, to, delay)
	s.Scale = to * 0.6
	task.delay(delay or 0, function()
		tween(s, 0.5, { Scale = to }, Enum.EasingStyle.Back)
	end)
end

local function dot(size, color, z)
	local d = Instance.new("Frame")
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Size = UDim2.fromOffset(size, size)
	d.BackgroundColor3 = color
	d.BorderSizePixel = 0
	d.ZIndex = z or 1
	d:SetAttribute(NO_TINT, true)
	round(d, UDim.new(1, 0))
	return d
end

-- Pointer: plain dot + ring (no emoji/icon art — owner swaps in a real asset if this survives).
local function makePointer()
	local p = dot(18, WHITE, 40)
	p.Name = "Pointer"
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 2
	stroke.Transparency = 0.4
	stroke.Parent = p
	local s = Instance.new("UIScale")
	s.Parent = p
	p.Parent = stage
	return p, s
end

local function ripple(x, y)
	local r = dot(18, WHITE, 39)
	r.BackgroundTransparency = 1
	r.Position = UDim2.fromOffset(x, y)
	local stroke = Instance.new("UIStroke")
	stroke.Color = WHITE
	stroke.Thickness = 2
	stroke.Parent = r
	r.Parent = stage
	tween(r, 0.5, { Size = UDim2.fromOffset(56, 56) })
	tween(stroke, 0.5, { Transparency = 1 })
	task.delay(0.55, function()
		r:Destroy()
	end)
end

-- 3D actor: the profile's avatar model in its own full-stage ViewportFrame. Every actor gets the
-- same camera framing (from its height), so x/z/yaw place them in one shared "world".
local FOV = 30
local function sourceModel()
	local vp = summarySrc:FindFirstChild("3DTargetPlayerAvatar", true)
	local m = vp and vp:FindFirstChildWhichIsA("Model", true)
	if m then
		return m, vp
	end
	local ch = lp.Character
	if ch then
		ch.Archivable = true
		return ch, nil
	end
	return nil, nil
end

local function actor(silhouette, z)
	local srcM, srcVp = sourceModel()
	if not srcM then
		return nil
	end
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Actor"
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.ZIndex = z
	vp:SetAttribute(NO_TINT, true)
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
	local m = cleanClone(srcM)
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
	vp.Parent = stage
	local a = {
		vp = vp,
		model = m,
		H = H,
		visH = visH,
		lookY = lookY,
		x = Instance.new("NumberValue"),
		z = Instance.new("NumberValue"),
		yaw = Instance.new("NumberValue"),
	}
	local offset = CFrame.new(-c.Position.X, -(c.Position.Y - size.Y / 2), -c.Position.Z)
	-- Yaw: pi faces the camera; positive turns the avatar toward stage-right.
	function a.apply(extraYaw)
		m:PivotTo(CFrame.new(a.x.Value, 0, a.z.Value) * CFrame.Angles(0, math.pi + a.yaw.Value + (extraYaw or 0), 0) * offset)
	end
	-- Stage-space y of a world height on the actor (for UI drawn at the feet / chest).
	function a.screenY(worldY)
		return STAGE_H / 2 - ((worldY - lookY) / (visH / 2)) * (STAGE_H / 2)
	end
	a.apply()
	return a
end

-- ── pages ─────────────────────────────────────────────────────────────────────────────────
local function newPage()
	local page = Instance.new("Frame")
	page.BackgroundTransparency = 1
	page.Size = UDim2.fromScale(1, 1)
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = page
	return page
end

local function header(page, kicker, title, body)
	local k = label(page, kicker, 12, Enum.FontWeight.Bold, ACCENT_LABEL, 1)
	k:SetAttribute("AccentToken", "primary")
	label(page, title, 24, Enum.FontWeight.Bold, WHITE, 2)
	label(page, body, 14, Enum.FontWeight.SemiBold, BODY, 3)
	local gap = Instance.new("Frame")
	gap.BackgroundTransparency = 1
	gap.Size = UDim2.new(1, 0, 0, 6)
	gap.LayoutOrder = 4
	gap.Parent = page
end

-- ── onboarding controls (redesigned, owner 2026-10-08) ─────────────────────────────────────
local function accentFill()
	if AccentService.isDesign() then
		return ACCENT_LABEL
	end
	return AccentService.get().fill
end

local function iconFrom(container, text)
	for _, b in ipairs(container:GetDescendants()) do
		if b:IsA("GuiButton") then
			local t = b:FindFirstChildOfClass("TextLabel")
			if t and t.Text == text then
				for _, d in ipairs(b:GetDescendants()) do
					if d:IsA("ImageLabel") and d.Image ~= "" then
						return d.Image
					end
				end
			end
		end
	end
	return nil
end

-- Which option the owner's live control shows as on (solid fill; MenuSegmentedOn can be stale).
local function currentOf(container, fallback)
	for _, b in ipairs(container:GetDescendants()) do
		local t = b:IsA("GuiButton") and b:FindFirstChildOfClass("TextLabel")
		if t and b.BackgroundTransparency < 0.5 then
			return t.Text
		end
	end
	return fallback
end

-- Grouped option rows: icon, title + hint, radio on the right. Calls onPick(key, initial).
local function optionList(page, order, items, selectedKey, onPick)
	local list = Instance.new("Frame")
	list.Name = "Options"
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(1, 0, 0, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = list
	local radios = {}
	local function paint(key, instant)
		local fill = accentFill()
		for k, r in pairs(radios) do
			local on = k == key
			local t = if instant then 0 else 0.2
			tween(r.ring, t, { BackgroundColor3 = fill, BackgroundTransparency = if on then 0 else 1 })
			tween(r.stroke, t, { Transparency = if on then 1 else 0 })
			tween(r.dotScale, if instant then 0 else 0.35, { Scale = if on then 1 else 0 }, Enum.EasingStyle.Back)
			tween(r.row, t, { BackgroundColor3 = if on then ROW_ON else ROW_BG })
		end
	end
	for i, it in ipairs(items) do
		local row = Instance.new("TextButton")
		row.Name = it.key
		row.Text = ""
		row.AutoButtonColor = false
		row.BackgroundColor3 = ROW_BG
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 52)
		row.LayoutOrder = i
		local p = Instance.new("UIPadding")
		p.PaddingLeft = UDim.new(0, 12)
		p.PaddingRight = UDim.new(0, 14)
		p.Parent = row
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.fromScale(0, 0.5)
		icon.Size = UDim2.fromOffset(26, 26)
		icon.Image = it.icon or ""
		icon.ImageColor3 = WHITE
		icon.Parent = row
		if not it.icon then
			-- Owner rule: no emoji — a neutral placeholder the owner swaps for a real icon.
			local ph = Instance.new("Frame")
			ph.Name = "IconPlaceholder"
			ph.AnchorPoint = Vector2.new(0.5, 0.5)
			ph.Position = UDim2.fromScale(0.5, 0.5)
			ph.Size = UDim2.fromOffset(18, 18)
			ph.BackgroundColor3 = WHITE
			ph.BackgroundTransparency = 0.8
			round(ph, UDim.new(0, 5))
			ph.Parent = icon
		end
		local title = textLabel(row, it.title, 15, Enum.FontWeight.Bold, WHITE)
		title.AnchorPoint = Vector2.new(0, 1)
		title.Position = UDim2.new(0, 38, 0.5, 0)
		title.Size = UDim2.new(1, -70, 0, 17)
		local hint = textLabel(row, it.hint, 13, Enum.FontWeight.Medium, SUB)
		hint.Position = UDim2.new(0, 38, 0.5, 2)
		hint.Size = UDim2.new(1, -70, 0, 15)
		local ring = Instance.new("Frame")
		ring.Name = "Radio"
		ring.AnchorPoint = Vector2.new(1, 0.5)
		ring.Position = UDim2.fromScale(1, 0.5)
		ring.Size = UDim2.fromOffset(20, 20)
		ring.BackgroundTransparency = 1
		round(ring, UDim.new(1, 0))
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromHex("5a5a5a")
		stroke.Thickness = 2
		stroke.Parent = ring
		local inner = Instance.new("Frame")
		inner.AnchorPoint = Vector2.new(0.5, 0.5)
		inner.Position = UDim2.fromScale(0.5, 0.5)
		inner.Size = UDim2.fromOffset(8, 8)
		inner.BackgroundColor3 = WHITE
		round(inner, UDim.new(1, 0))
		local dotScale = Instance.new("UIScale")
		dotScale.Scale = 0
		dotScale.Parent = inner
		inner.Parent = ring
		ring.Parent = row
		row.Parent = list
		radios[it.key] = { row = row, ring = ring, stroke = stroke, dotScale = dotScale }
		UIMotion.bindPress(row)
		table.insert(conns, row.Activated:Connect(function()
			paint(it.key, false)
			onPick(it.key, false)
		end))
	end
	list.Parent = page
	GroupedRowCornerUtil.apply(list)
	paint(selectedKey, true)
	onPick(selectedKey, true)
	return list
end

-- Theme grid straight on the panel (no wrapper card): "Accent" + live name, 7 dots per line at
-- 36px; the selected dot shrinks inside a white ring.
local DOT = 36
local function themeGrid(page, order, onPick)
	local card = Instance.new("Frame")
	card.Name = "ThemeGrid"
	card.BackgroundTransparency = 1
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 12)
	layout.Parent = card

	local top = Instance.new("Frame")
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, 0, 0, 18)
	top.LayoutOrder = 1
	top.Parent = card
	local cap = textLabel(top, "Accent", 13, Enum.FontWeight.Medium, SUB)
	cap.Size = UDim2.fromScale(0.5, 1)
	local name = textLabel(top, "", 15, Enum.FontWeight.Bold, WHITE)
	name.AnchorPoint = Vector2.new(1, 0)
	name.Position = UDim2.fromScale(1, 0)
	name.Size = UDim2.fromScale(0.5, 1)
	name.TextXAlignment = Enum.TextXAlignment.Right

	local grid = Instance.new("Frame")
	grid.Name = "Swatches"
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, 0, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = 2
	grid:SetAttribute(NO_TINT, true)
	local gl = Instance.new("UIListLayout")
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Padding = UDim.new(0, 12)
	gl.Parent = grid
	grid.Parent = card

	local ownerDots = settingsTab.appearance_Section:FindFirstChild("AccentSwatches", true)
	local PER_LINE = 7
	local lines = {}
	local slots = {}
	for index, id in ipairs(AccentDomain.ORDER) do
		local li = math.ceil(index / PER_LINE)
		if not lines[li] then
			local line = Instance.new("Frame")
			line.BackgroundTransparency = 1
			line.Size = UDim2.new(1, 0, 0, DOT)
			line.LayoutOrder = li
			local ll = Instance.new("UIListLayout")
			ll.FillDirection = Enum.FillDirection.Horizontal
			ll.HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween
			ll.VerticalAlignment = Enum.VerticalAlignment.Center
			ll.SortOrder = Enum.SortOrder.LayoutOrder
			ll.Parent = line
			line.Parent = grid
			lines[li] = line
		end
		local slot = Instance.new("TextButton")
		slot.Name = id
		slot.Text = ""
		slot.AutoButtonColor = false
		slot.BackgroundTransparency = 1
		slot.Size = UDim2.fromOffset(DOT, DOT)
		slot.LayoutOrder = index
		round(slot, UDim.new(1, 0))
		local ring = Instance.new("UIStroke")
		ring.Color = WHITE
		ring.Thickness = 2
		ring.Transparency = 1
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.Parent = slot
		local fill = Instance.new("Frame")
		fill.AnchorPoint = Vector2.new(0.5, 0.5)
		fill.Position = UDim2.fromScale(0.5, 0.5)
		fill.Size = UDim2.fromScale(1, 1)
		fill.BorderSizePixel = 0
		local src = ownerDots and ownerDots:FindFirstChild(id, true)
		fill.BackgroundColor3 = if src then src.BackgroundColor3 else Color3.fromHex(AccentDomain.swatch(id).fill)
		local grad = src and src:FindFirstChildOfClass("UIGradient")
		if grad then
			grad:Clone().Parent = fill
		end
		round(fill, UDim.new(1, 0))
		local ds = Instance.new("UIScale")
		ds.Parent = fill
		fill.Parent = slot
		slot.Parent = lines[li]
		slots[id] = { slot = slot, ring = ring, scale = ds }
	end
	local function paint(id, instant)
		name.Text = AccentDomain.label(id)
		for k, sl in pairs(slots) do
			local on = k == id
			local t = if instant then 0 else 0.25
			tween(sl.ring, t, { Transparency = if on then 0 else 1 })
			tween(sl.scale, t, { Scale = if on then 0.74 else 1 }, Enum.EasingStyle.Back)
		end
	end
	for id, sl in pairs(slots) do
		table.insert(conns, sl.slot.Activated:Connect(function()
			paint(id, false)
			onPick(id, false)
		end))
	end
	card.Parent = page
	paint(AccentService.get().id, true)
	return card
end

-- Status pill: the owner's ReminderCard header with an icon, centred on the stage.
local function statusPill(x, y, z)
	local tag = cleanClone(reminderCard.Header)
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
	local hd, s = holder(tag, 160, 40, x, y, 1, 0)
	tag.AutomaticSize = Enum.AutomaticSize.None
	hd.ZIndex = z or 8
	local pill = { hd = hd, scale = s }
	function pill.set(text, image, instant)
		tag.Label.Text = text
		if tagIcon then
			tagIcon.Image = image or ""
		end
		-- TextBounds is 0 until rendered; measure up front so the pill stays centred.
		local w = TextService:GetTextSize(text, 16, Enum.Font.GothamBold, Vector2.new(1000, 40)).X + (if image then 74 else 44)
		hd.Size = UDim2.fromOffset(w, 40)
		tag.Size = UDim2.fromOffset(w, 40)
		if not instant then
			s.Scale = 0.85
			tween(s, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
	return pill
end

-- ── steps ─────────────────────────────────────────────────────────────────────────────────
-- Step 1: a pointer taps the real Menu pill, the menu drops, the pointer walks its sections.
local function stepWelcome(page, token)
	local logoSrc = pg["00-LoadingScreen"]:FindFirstChild("LogoWrapper", true)
	logoSrc = logoSrc and logoSrc:FindFirstChildWhichIsA("ImageLabel")
	if logoSrc then
		local logo = cleanClone(logoSrc)
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
	header(page, "WELCOME", "Welcome to " .. placeName, "Everything you need lives in one place: the <b>Menu</b> at the top right.")
	-- Sections the pointer walks (the text list on the right was removed, owner 2026-10-08).
	local chapters = { "Section1", "Section2", "Section4", "Section7" }

	-- Pill and menu at their real size (owner: "scale 1 aja"), centred.
	local MENU_S = 1
	local PILL_Y = 20
	local pillSize = if menuPillSrc then menuPillSrc.AbsoluteSize else Vector2.new(110, 44)
	local DROP_TOP = PILL_Y + math.floor(pillSize.Y * MENU_S) + 8
	local DROP_W = math.floor(280 * MENU_S)
	local DROP_H = STAGE_H - DROP_TOP
	local DROP_X = math.floor((STAGE_W - DROP_W) / 2)
	local pillCentre = Vector2.new(DROP_X + DROP_W - pillSize.X * MENU_S / 2, PILL_Y + pillSize.Y * MENU_S / 2)
	local pillScale
	if menuPillSrc then
		local pill = cleanClone(menuPillSrc)
		for _, d in ipairs(pill:GetDescendants()) do
			if d:IsA("TextLabel") and d.Text == "Close Menu" then
				d.Text = "Menu"
			end
		end
		local _, s = holder(pill, pillSize.X, pillSize.Y, pillCentre.X, pillCentre.Y, MENU_S, 0)
		pill.AutomaticSize = Enum.AutomaticSize.None
		pillScale = s
	end

	local drop = Instance.new("Frame")
	drop.Name = "Drop"
	drop.BackgroundTransparency = 1
	drop.ClipsDescendants = true
	drop.Position = UDim2.fromOffset(DROP_X, DROP_TOP)
	drop.Size = UDim2.fromOffset(DROP_W, 0)
	drop.Parent = stage
	local menuRoot = Instance.new("Frame")
	menuRoot.BackgroundTransparency = 1
	menuRoot.Size = UDim2.fromOffset(280, 838)
	local ms = Instance.new("UIScale")
	ms.Scale = MENU_S
	ms.Parent = menuRoot
	local menu = cleanClone(topBarMenu)
	menu.BackgroundTransparency = 1
	menu.Position = UDim2.fromScale(0, 0)
	menu.AnchorPoint = Vector2.zero
	menu.Size = UDim2.fromOffset(280, 838)
	menu.Visible = true
	menu.Parent = menuRoot
	menuRoot.Parent = drop

	local pointer, pScale = makePointer()
	local START = Vector2.new(70, STAGE_H - 40)
	pointer.Position = UDim2.fromOffset(START.X, START.Y)
	local function moveTo(v, t)
		tween(pointer, t, { Position = UDim2.fromOffset(v.X, v.Y) }, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
		task.wait(t)
	end
	local function tap(v, target)
		tween(pScale, 0.08, { Scale = 0.75 })
		if target then
			tween(target, 0.08, { Scale = MENU_S * 0.9 })
		end
		task.wait(0.09)
		ripple(v.X, v.Y)
		tween(pScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		if target then
			tween(target, 0.35, { Scale = MENU_S }, Enum.EasingStyle.Back)
		end
		task.wait(0.3)
	end
	local function rowsOf(section)
		local list = {}
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
	local restColor = {}
	for _, b in ipairs(menu:GetDescendants()) do
		if b:IsA("TextButton") then
			restColor[b] = b.BackgroundColor3
		end
	end
	local function light(section)
		for b, c in pairs(restColor) do
			local on = section and b.Parent == section
			tween(b, 0.25, { BackgroundColor3 = if on then c:Lerp(WHITE, 0.14) else c })
		end
	end

	task.spawn(function()
		while live(token) do
			drop.Size = UDim2.fromOffset(DROP_W, 0)
			menuRoot.Position = UDim2.fromOffset(0, 0)
			pointer.Position = UDim2.fromOffset(START.X, START.Y)
			pointer.BackgroundTransparency = 0
			light(nil)
			task.wait(0.6)
			if not live(token) then
				return
			end
			moveTo(pillCentre, 0.9)
			tap(pillCentre, pillScale)
			tween(drop, 0.45, { Size = UDim2.fromOffset(DROP_W, DROP_H) })
			task.wait(0.5)
			for _, sectionName in ipairs(chapters) do
				if not live(token) then
					return
				end
				local section = menu:FindFirstChild(sectionName)
				local rows = section and rowsOf(section)
				if rows and rows[1] then
					local k = shellScale.Scale
					local top = (section.AbsolutePosition.Y - menuRoot.AbsolutePosition.Y) / k
					local bottom = top + section.AbsoluteSize.Y / k
					local scroll = math.clamp((top + bottom) / 2 - DROP_H * 0.45, 0, 838 * MENU_S - DROP_H)
					tween(menuRoot, 0.6, { Position = UDim2.fromOffset(0, -scroll) }, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
					local row = rows[1]
					local rowY = (row.AbsolutePosition.Y - menuRoot.AbsolutePosition.Y + row.AbsoluteSize.Y / 2) / k
					moveTo(Vector2.new(DROP_X + DROP_W * 0.62, DROP_TOP + rowY - scroll), 0.6)
					light(section)
				end
				task.wait(1.5)
			end
			if not live(token) then
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
local function stepTheme(page, token)
	header(page, "STEP 1 OF 3", "Pick your colour", "Tints the whole interface. Change it anytime in Settings.")
	local function firstToggleRow()
		for _, d in ipairs(settingsTab.visual_Section:GetDescendants()) do
			if d:IsA("TextButton") and d:FindFirstChild("Toggle") then
				return d
			end
		end
		return nil
	end
	local cards = {
		{ src = topBarMenu:FindFirstChild("MusicPlayerButton", true), size = Vector2.new(280, 54), x = 164, y = 62, rot = -3 },
		{ src = firstToggleRow(), size = Vector2.new(264, 36), x = 156, y = 138, rot = 2 },
		{ src = settingsTab.graphics_Section.SectionContentWrapper.graphicsPreset, size = Vector2.new(264, 118), x = 164, y = 240, rot = -2 },
		{ src = settingsTab.music_Section.SectionContentWrapper:FindFirstChild("musicVolume"), size = Vector2.new(264, 88), x = 156, y = 356, rot = 3 },
	}
	-- Real size (owner: "scale 1 aja"). Corners: the same radius on all four sides, not the
	-- grouped-row rule's small bottom corners — rows become pills, cards keep 18 everywhere.
	local CARD_S = 1
	local function fullRound(card, height)
		local radius = if height <= 54 then UDim.new(1, 0) else UDim.new(0, 18)
		local corner = card:FindFirstChildOfClass("UICorner") or round(card, radius)
		corner.CornerRadius = radius
		for _, side in ipairs({ "TopLeftRadius", "TopRightRadius", "BottomLeftRadius", "BottomRightRadius" }) do
			pcall(function()
				corner[side] = radius
			end)
		end
	end
	local holders = {}
	for i, c in ipairs(cards) do
		if c.src then
			local card = cleanClone(c.src)
			fullRound(card, c.size.Y)
			local hd, s = holder(card, c.size.X, c.size.Y, c.x, c.y, CARD_S, c.rot)
			hd.ZIndex = 5
			popIn(hd, s, CARD_S, 0.08 * i)
			holders[i] = { hd = hd, s = s, base = c }
		end
	end
	animate(token, function(t)
		for i, h in pairs(holders) do
			local ph = i * 1.7
			h.hd.Position = UDim2.fromOffset(h.base.x, h.base.y + math.sin(t * 1.3 + ph) * 4)
			h.hd.Rotation = h.base.rot + math.sin(t * 0.9 + ph) * 0.8
		end
	end)

	local function wave(id)
		local before = stage.BackgroundColor3
		local cover = Instance.new("Frame")
		cover.Size = UDim2.fromScale(1, 1)
		cover.BackgroundColor3 = before
		cover.BorderSizePixel = 0
		cover.ZIndex = 1
		cover:SetAttribute(NO_TINT, true)
		cover.Parent = stage
		AccentService.set(id)
		-- The surface tint repaints the stage once the value settles; wait for it (bounded).
		for _ = 1, 12 do
			task.wait()
			if stage.BackgroundColor3 ~= before then
				break
			end
		end
		local circle = dot(0, stage.BackgroundColor3, 2)
		circle.Position = UDim2.fromOffset(STAGE_W / 2, STAGE_H / 2)
		circle.Parent = stage
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

	themeGrid(page, 10, function(id)
		picks.theme = AccentDomain.label(id)
		if AccentService.get().id ~= id then
			task.spawn(wave, id)
		end
	end)
end

-- Step 3: full-body 3D scene. Single = halo; Taken = partner silhouette + thread at the feet;
-- For Fun = three ghost silhouettes fanned behind + rising sparkles.
local function stepRelationship(page, token)
	header(page, "STEP 2 OF 3", "Relationship status", "Shown on your profile. Pick <b>Taken</b> to show your couple's name.")
	local ownerCouple = findProfileSection("CoupleStatus").CoupleStatus
	local icons = {
		Single = iconFrom(ownerCouple, "Single"),
		Taken = iconFrom(ownerCouple, "Taken"),
		["For Fun"] = iconFrom(ownerCouple, "For Fun"),
	}

	local ghosts = { actor(true, 2), actor(true, 2), actor(true, 1) }
	local partner = actor(true, 3)
	local me = actor(false, 4)
	if not me then
		return
	end
	local H = me.H
	local all = { me, partner, ghosts[1], ghosts[2], ghosts[3] }

	local halo = dot(230, WHITE, 1)
	halo.BackgroundTransparency = 1
	halo.Position = UDim2.fromOffset(STAGE_W / 2, me.screenY(H * 0.55))
	local haloStroke = Instance.new("UIStroke")
	haloStroke.Color = WHITE
	haloStroke.Thickness = 2
	haloStroke.Transparency = 1
	haloStroke.Parent = halo
	local haloScale = Instance.new("UIScale")
	haloScale.Parent = halo
	halo.Parent = stage

	-- Thread at the feet: two halves drawn toward a white node (accent would vanish on the stage).
	local footY = me.screenY(0)
	local link = Instance.new("Frame")
	link.AnchorPoint = Vector2.new(0.5, 0.5)
	link.Position = UDim2.fromOffset(STAGE_W / 2, footY)
	link.Size = UDim2.fromOffset(200, 14)
	link.BackgroundTransparency = 1
	link.ZIndex = 6
	link:SetAttribute(NO_TINT, true)
	link.Parent = stage
	local function thread(anchorX)
		local l = Instance.new("Frame")
		l.AnchorPoint = Vector2.new(anchorX, 0.5)
		l.Position = UDim2.fromScale(0.5, 0.5)
		l.Size = UDim2.fromOffset(0, 2)
		l.BackgroundColor3 = WHITE
		l.BackgroundTransparency = 0.25
		l.BorderSizePixel = 0
		l.Parent = link
		return l
	end
	local threadL, threadR = thread(1), thread(0)
	local node = dot(12, WHITE, 7)
	node.Position = UDim2.fromScale(0.5, 0.5)
	local rim = Instance.new("UIStroke")
	rim.Color = Color3.fromHex("070707")
	rim.Thickness = 3
	rim.Parent = node
	local nodeScale = Instance.new("UIScale")
	nodeScale.Scale = 0
	nodeScale.Parent = node
	node.Parent = link


	local mode = "Single"
	animate(token, function(t)
		for i, a in ipairs(all) do
			if a then
				a.apply(math.sin(t * 1.1 + i) * 0.07)
			end
		end
		haloScale.Scale = 1 + math.sin(t * 2) * 0.04
	end)

	task.spawn(function()
		while live(token) do
			if mode == "For Fun" then
				local x = STAGE_W / 2 + math.random(-130, 130)
				local y = math.random(80, math.floor(footY))
				local d = dot(math.random(4, 8), WHITE, 9)
				d.BackgroundTransparency = 0.1
				d.Position = UDim2.fromOffset(x, y)
				d.Parent = stage
				tween(d, 1.4, { Position = UDim2.fromOffset(x, y - 40), BackgroundTransparency = 1 }, Enum.EasingStyle.Sine)
				task.delay(1.45, function()
					d:Destroy()
				end)
			end
			task.wait(0.18)
		end
	end)

	local function place(a, x, z, yaw, transp, t)
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
	local function setMode(name, instant)
		mode = name
		local t = if instant then 0 else 0.6
		if name == "Taken" then
			place(me, -H * 0.2, 0, FACE, nil, t)
			place(partner, H * 0.2, 0, -FACE, 0.15, t)
			for _, g in ipairs(ghosts) do
				place(g, g.x.Value, g.z.Value, g.yaw.Value, 1, t)
			end
			tween(haloStroke, t, { Transparency = 1 })
			tween(threadL, t, { Size = UDim2.fromOffset(60, 2) })
			tween(threadR, t, { Size = UDim2.fromOffset(60, 2) })
			task.delay(t * 0.6, function()
				tween(nodeScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
			end)
		else
			tween(threadL, t * 0.6, { Size = UDim2.fromOffset(0, 2) })
			tween(threadR, t * 0.6, { Size = UDim2.fromOffset(0, 2) })
			tween(nodeScale, t * 0.5, { Scale = 0 })
			place(partner, OFF, 0, -FACE, 1, t)
			place(me, 0, 0, 0, nil, t)
			if name == "For Fun" then
				tween(haloStroke, t, { Transparency = 1 })
				local spots = { { -H * 0.34, -H * 0.45, 0.45 }, { H * 0.34, -H * 0.45, -0.45 }, { 0, -H * 0.95, 0 } }
				for i, g in ipairs(ghosts) do
					if g then
						local sp = spots[i]
						g.x.Value, g.z.Value, g.yaw.Value = sp[1] * 0.6, sp[2] - H * 0.3, sp[3]
						task.delay((i - 1) * 0.08, function()
							place(g, sp[1], sp[2], sp[3], 0.45, if instant then 0 else 0.5)
						end)
					end
				end
			else
				for _, g in ipairs(ghosts) do
					place(g, g and g.x.Value or 0, g and g.z.Value or 0, g and g.yaw.Value or 0, 1, t)
				end
				tween(haloStroke, t, { Transparency = 0.7 })
			end
		end
	end

	optionList(page, 10, {
		{ key = "Single", title = "Single", hint = "Open to meeting people", icon = icons.Single },
		{ key = "Taken", title = "Taken", hint = "Show your couple's name", icon = icons.Taken },
		{ key = "For Fun", title = "For Fun", hint = "Just here for the vibes", icon = icons["For Fun"] },
	}, picks.status or currentOf(ownerCouple, "Single"), function(key, initial)
		if not initial then
			picks.status = key
		end
		setMode(key, initial)
	end)
end

-- Full-body avatar turning slowly; lighting follows the quality pick.
local LIGHTING = {
	Low = { Ambient = Color3.fromRGB(175, 175, 175), LightColor = Color3.fromRGB(70, 70, 70) },
	Balance = { Ambient = Color3.fromRGB(120, 120, 128), LightColor = Color3.fromRGB(190, 190, 190) },
	High = { Ambient = Color3.fromRGB(60, 60, 75), LightColor = Color3.fromRGB(255, 250, 240) },
}
local function turntable(token)
	local a = actor(false, 3)
	if not a then
		return nil
	end
	animate(token, function(t)
		a.yaw.Value = t * 0.7
		a.apply()
	end)
	local preset = LIGHTING[picks.quality or ""]
	if preset then
		a.vp.Ambient = preset.Ambient
		a.vp.LightColor = preset.LightColor
	end
	return a
end

-- Step 4: graphics preset — the turntable, lighting per preset.
local function stepQuality(page, token)
	header(page, "STEP 3 OF 3", "How it looks", "Pick what your device can handle. Balance suits most phones.")
	local ownerPreset = settingsTab.graphics_Section.SectionContentWrapper.graphicsPreset
	local a = turntable(token)
	optionList(page, 10, {
		{ key = "Low", title = "Low", hint = "Smoothest on older phones", icon = iconFrom(ownerPreset, "Low") },
		{ key = "Balance", title = "Balance", hint = "Recommended for most devices", icon = iconFrom(ownerPreset, "Balance") },
		{ key = "High", title = "High", hint = "Best visuals, newer devices", icon = iconFrom(ownerPreset, "High") },
	}, picks.quality or currentOf(ownerPreset, "Balance"), function(name, initial)
		if not initial then
			picks.quality = name
		end
		local look = LIGHTING[name]
		if a and look then
			tween(a.vp, if initial then 0 else 0.5, { Ambient = look.Ambient, LightColor = look.LightColor })
		end
	end)
end

-- Step 5: avatar + recap chips (ReminderCard header pills) popping in around it.
local function stepDone(page, token)
	header(page, "ALL SET", "You're ready", "Open the <b>Menu</b> anytime to change these in Settings.")
	turntable(token)
	local chips = {
		{ text = "Theme  " .. (picks.theme or AccentDomain.label(AccentService.get().id)), x = 104, y = 70, rot = -4 },
		{ text = picks.status or "Single", x = 236, y = 150, rot = 3 },
		{ text = "Quality  " .. (picks.quality or "Balance"), x = 110, y = 356, rot = 2 },
	}
	local floating = {}
	for i, c in ipairs(chips) do
		local p = statusPill(c.x, c.y, 6)
		p.set(c.text, nil, true)
		p.hd.Rotation = c.rot
		popIn(p.hd, p.scale, 1, 0.25 + 0.12 * i)
		floating[i] = { hd = p.hd, base = c }
	end
	animate(token, function(t)
		for i, c in pairs(floating) do
			c.hd.Position = UDim2.fromOffset(c.base.x, c.base.y + math.sin(t * 1.4 + i * 2) * 4)
		end
	end)
end

local steps = { stepWelcome, stepTheme, stepRelationship, stepQuality, stepDone }
local current = 0
local currentPage = nil
local busy = false

local function closeAll()
	alive = false
	tween(shellScale, 0.3, { Scale = 0.94 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	tween(shell, 0.3, { GroupTransparency = 1 })
	tween(dim, 0.3, { BackgroundTransparency = 1 })
	task.delay(0.35, function()
		gui:Destroy()
	end)
end

local function goTo(index)
	if busy or index < 1 then
		return
	end
	if index > #steps then
		closeAll()
		return
	end
	busy = true
	runToken += 1
	local token = runToken
	local dir = if index >= current then 1 else -1
	current = index
	if currentPage then
		local old = currentPage
		tween(old, 0.2, { Position = UDim2.fromOffset(-24 * dir, old.Position.Y.Offset) })
		for _, d in ipairs(old:GetDescendants()) do
			if d:IsA("TextLabel") then
				tween(d, 0.15, { TextTransparency = 1 })
			end
		end
		tween(wipe, 0.18, { BackgroundTransparency = 0 })
		task.wait(0.2)
		old:Destroy()
	end
	clearStage()
	-- Step 1 has no Back, so its page starts at the top; later pages sit under the Back row.
	local topY = if index > 1 then TOP_H else 0
	back.Visible = index > 1
	pageHost.Position = UDim2.fromOffset(0, topY)
	pageHost.Size = UDim2.new(1, 0, 1, -52 - topY)
	local page = newPage()
	page.Position = UDim2.fromOffset(28 * dir, 0)
	page.Parent = pageHost
	currentPage = page
	local fn = (G.__OnbXSteps and G.__OnbXSteps[index]) or steps[index]
	local ok, err = pcall(fn, page, token, G.__OnbXCtx)
	if not ok then
		warn("[OnbX] step", index, err)
	end
	tween(page, 0.35, { Position = UDim2.fromOffset(0, 0) })
	tween(wipe, 0.3, { BackgroundTransparency = 1 })
	primaryLabel.Text = if index == 1 then "Get started" elseif index == #steps then "Let's go" else "Next"
	task.wait(0.3)
	busy = false
end

UIMotion.bindPress(primary)
UIMotion.bindPress(back)
table.insert(conns, primary.Activated:Connect(function()
	goTo(current + 1)
end))
table.insert(conns, back.Activated:Connect(function()
	goTo(current - 1)
end))
table.insert(conns, close.Activated:Connect(closeAll))

local function destroy()
	alive = false
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	if gui.Parent then
		gui:Destroy()
	end
	G.__OnbX = nil
end

table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.O then
		task.spawn(G.__OnbXBoot)
	end
end))

G.__OnbX = { destroy = destroy, goTo = goTo, gui = gui }
G.__OnbXCtx = {
	tween = tween, live = live, animate = animate, label = label, header = header, holder = holder,
	popIn = popIn, dot = dot, makePointer = makePointer, ripple = ripple, actor = actor, turntable = turntable,
	optionList = optionList, themeGrid = themeGrid, statusPill = statusPill, iconFrom = iconFrom,
	currentOf = currentOf, textLabel = textLabel, round = round, cleanClone = cleanClone,
	findProfileSection = findProfileSection, accentFill = accentFill, picks = picks, conns = conns,
	stage = stage, STAGE_W = STAGE_W, STAGE_H = STAGE_H, settingsTab = settingsTab, profileTab = profileTab,
	topBarMenu = topBarMenu, summarySrc = summarySrc, reminderCard = reminderCard, menuPillSrc = menuPillSrc,
	shellScale = shellScale, placeName = placeName, LIGHTING = LIGHTING, AccentService = AccentService,
	AccentDomain = AccentDomain, UIMotion = UIMotion, lp = lp, pg = pg, steps = steps,
}

gui.Parent = pg
tween(dim, 0.35, { BackgroundTransparency = 0.45 })
tween(shell, 0.35, { GroupTransparency = 0 })
tween(shellScale, 0.45, { Scale = 1 })
task.spawn(goTo, 1)
