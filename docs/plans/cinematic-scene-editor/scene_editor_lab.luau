-- Cinematic Scene Editor + Look panel — UI EXPERIMENT (2026-10-17), not wired into the kit.
-- Run in a live playtest client (eval_client_runtime) with 12-CinematicDockGUI present.
-- Cleanup: _G.CineLabCleanup()

local Players = game:GetService("Players")
local TS = game:GetService("TweenService")
local RS = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local MPS = game:GetService("MarketplaceService")
local RepS = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer
local pg = lp.PlayerGui
if _G.CineLabCleanup then pcall(_G.CineLabCleanup) end
local Modes = require(RepS.Hazastudio_ClubKit.Shared.Utils.CinematicCameraModes)

local dockGui = pg:FindFirstChild("12-CinematicDockGUI")
local dock = dockGui and dockGui:FindFirstChild("CinematicDock")
if not dock then return "no dock" end
local tgtW, movW, spd = dock.SelectTargetWrapper, dock.SelectMovementWrapper, dock.SpeedChanger
local FONT = movW.SelectMovementButton.TextLabel.FontFace
local FONT_S = spd.Wrapper["1"].FontFace
local FONT_SB = Font.new(FONT.Family, Enum.FontWeight.SemiBold)
local refStroke = dock:FindFirstChildOfClass("UIStroke")
local rgb = Color3.fromRGB
local C = {
	bg = rgb(7, 7, 7), surface = rgb(15, 15, 15), surface2 = rgb(30, 30, 30), surface3 = rgb(42, 42, 42),
	text = rgb(255, 255, 255), muted = rgb(140, 140, 140), dim = rgb(85, 85, 85), danger = rgb(255, 95, 95),
}
local F = {
	None = { B = 0, C = 0, S = 0, T = rgb(255, 255, 255), bloom = false, blur = 0, g1 = rgb(80, 80, 80), g2 = rgb(22, 22, 22), clip = rgb(44, 44, 44), accent = rgb(170, 170, 170) },
	Warm = { B = 0.02, C = 0.08, S = 0.12, T = rgb(255, 236, 214), bloom = false, blur = 0, g1 = rgb(255, 184, 110), g2 = rgb(110, 52, 34), clip = rgb(66, 48, 34), accent = rgb(255, 180, 110) },
	Cool = { B = 0, C = 0.1, S = 0.05, T = rgb(212, 228, 255), bloom = false, blur = 0, g1 = rgb(130, 190, 255), g2 = rgb(26, 44, 90), clip = rgb(32, 44, 64), accent = rgb(130, 190, 255) },
	["B&W"] = { B = 0, C = 0.2, S = -1, T = rgb(255, 255, 255), bloom = false, blur = 0, g1 = rgb(235, 235, 235), g2 = rgb(10, 10, 10), clip = rgb(58, 58, 58), accent = rgb(235, 235, 235) },
	Neon = { B = 0.03, C = 0.18, S = 0.45, T = rgb(232, 218, 255), bloom = true, blur = 0, g1 = rgb(255, 70, 200), g2 = rgb(70, 60, 255), clip = rgb(58, 34, 70), accent = rgb(255, 90, 210) },
	VHS = { B = 0.04, C = -0.12, S = -0.25, T = rgb(255, 238, 228), bloom = false, blur = 2, g1 = rgb(210, 175, 165), g2 = rgb(55, 65, 90), clip = rgb(54, 46, 48), accent = rgb(220, 170, 160) },
}
local FILTER_ORDER = { "None", "Warm", "Cool", "B&W", "Neon", "VHS" }
local RULER, ROW, GAP, PPS = 22, 44, 8, 44

local L = { conns = {}, hidden = {}, assetCache = {}, t = 0, playing = false, loop = true }

-- ── helpers ─────────────────────────────────────────────
local nxv = 0
local function nx() nxv += 1; return nxv end
local function new(cls, props, parent)
	local i = Instance.new(cls)
	for k, v in props do i[k] = v end
	if parent then i.Parent = parent end
	return i
end
local function set(i, props) if props then for k, v in props do i[k] = v end end return i end
local function corner(p, r) new("UICorner", { CornerRadius = typeof(r) == "UDim" and r or UDim.new(0, r) }, p) end
local PILL = UDim.new(1, 0)
local function strokeOf(p) if refStroke then refStroke:Clone().Parent = p end end
local function pad(p, a, b, c, d)
	new("UIPadding", { PaddingLeft = UDim.new(0, a), PaddingRight = UDim.new(0, b or a), PaddingTop = UDim.new(0, c or a), PaddingBottom = UDim.new(0, d or c or a) }, p)
end
local function vlist(p, gap) return new("UIListLayout", { Padding = UDim.new(0, gap), SortOrder = Enum.SortOrder.LayoutOrder }, p) end
local function hlist(p, gap, halign)
	return new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, gap), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center, HorizontalAlignment = halign or Enum.HorizontalAlignment.Left }, p)
end
local function frame(p, props) return set(new("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = nx() }, p), props) end
local function txt(p, s, size, color, font, props)
	return set(new("TextLabel", { BackgroundTransparency = 1, Text = s, TextSize = size, TextColor3 = color or C.text, FontFace = font or FONT, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, size + 4), LayoutOrder = nx() }, p), props)
end
local function btn(p, props) return set(new("TextButton", { AutoButtonColor = false, Text = "", BorderSizePixel = 0, FontFace = FONT, TextColor3 = C.text, LayoutOrder = nx() }, p), props) end
local function section(p, s) return txt(p, string.upper(s), 10, C.muted, FONT_S, { Size = UDim2.new(1, 0, 0, 16) }) end
local function on(sig, fn) table.insert(L.conns, sig:Connect(fn)) end
local function tw(i, t, props, style, dir)
	local x = TS:Create(i, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
	x:Play()
	return x
end
local function copy(t)
	if type(t) ~= "table" then return t end
	local r = {}
	for k, v in t do r[k] = copy(v) end
	return r
end
local function clear(p)
	for _, c in p:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
end
local function fmt(s) return string.format("%d:%04.1f", s // 60, s % 60) end
local function sum(list) local a = 0 for _, c in list do a += c.dur end return a end
local function sceneTotal(s) return math.max(sum(s.camera), sum(s.target), sum(s.look)) end
local function clipAt(list, t)
	local acc = 0
	for i, c in list do
		if t < acc + c.dur then return i, c end
		acc += c.dur
	end
	return #list, list[#list]
end
local function LK(filter, lb, dur) return { filter = filter, lb = lb, pos = "Full", op = 1, dur = dur } end

-- ── dock buttons ────────────────────────────────────────
local saved = { dock = dock.Size, tgt = { tgtW.Size, tgtW.LayoutOrder }, mov = { movW.Size, movW.LayoutOrder }, spd = { spd.Size, spd.LayoutOrder } }
dock.Size = UDim2.new(0, 860, saved.dock.Y.Scale, saved.dock.Y.Offset)
tgtW.Size = UDim2.new(0.22, 0, 1, 0); tgtW.LayoutOrder = 1
movW.Size = UDim2.new(0.22, 0, 1, 0); movW.LayoutOrder = 2
spd.Size = UDim2.new(0.3, 0, 1, 0); spd.LayoutOrder = 5
local function dockBtn(name, text, order)
	local w = movW:Clone()
	w.Name = "CineLab_" .. name; w.Size = UDim2.new(0.13, 0, 1, 0); w.LayoutOrder = order
	local b = w.SelectMovementButton
	b.Name = name .. "Button"; b.TextLabel.Text = text
	w.Parent = dock
	return w, b
end
local lookW, lookBtn = dockBtn("Look", "Look", 3)
local sceneW, sceneBtn = dockBtn("Scene", "Scene", 4)

-- ── effects layer ───────────────────────────────────────
local fx = new("ScreenGui", { Name = "CineLabFX", IgnoreGuiInset = true, DisplayOrder = -5, ResetOnSpawn = false }, pg)
local ui = new("ScreenGui", { Name = "CineLabUI", DisplayOrder = dockGui.DisplayOrder + 1, ResetOnSpawn = false }, pg)
local cc = new("ColorCorrectionEffect", { Name = "CineLabCC" }, Lighting)
local bloom = new("BloomEffect", { Name = "CineLabBloom", Enabled = false, Intensity = 1.2, Size = 30, Threshold = 0.9 }, Lighting)
local blur = new("BlurEffect", { Name = "CineLabBlur", Size = 0 }, Lighting)
local overlay = new("ImageLabel", { Name = "Overlay", BackgroundTransparency = 1, Visible = false }, fx)
local bars = {}
for _, k in { "Top", "Bottom", "Left", "Right" } do
	local f = new("Frame", { BackgroundColor3 = rgb(0, 0, 0), BorderSizePixel = 0 }, fx)
	if k == "Top" then f.Size = UDim2.new(1, 0, 0, 0)
	elseif k == "Bottom" then f.AnchorPoint = Vector2.new(0, 1); f.Position = UDim2.new(0, 0, 1, 0); f.Size = UDim2.new(1, 0, 0, 0)
	elseif k == "Left" then f.Size = UDim2.new(0, 0, 1, 0)
	else f.AnchorPoint = Vector2.new(1, 0); f.Position = UDim2.new(1, 0, 0, 0); f.Size = UDim2.new(0, 0, 1, 0) end
	bars[k] = f
end
L.lb = "Off"
local function setBars(mode)
	L.lb = mode
	local vp = workspace.CurrentCamera.ViewportSize
	local hb, sb = 0, 0
	if mode == "2.39:1" then hb = math.max(0, (vp.Y - vp.X / 2.39) / 2)
	elseif mode == "16:9" then hb = math.max(0, (vp.Y - vp.X * 9 / 16) / 2)
	elseif mode == "9:16" then sb = math.max(0, (vp.X - vp.Y * 9 / 16) / 2) end
	tw(bars.Top, 0.6, { Size = UDim2.new(1, 0, 0, hb) }); tw(bars.Bottom, 0.6, { Size = UDim2.new(1, 0, 0, hb) })
	tw(bars.Left, 0.6, { Size = UDim2.new(0, sb, 1, 0) }); tw(bars.Right, 0.6, { Size = UDim2.new(0, sb, 1, 0) })
end
on(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), function() setBars(L.lb) end)
local function applyLook(look)
	local p = F[look.filter] or F.None
	tw(cc, 0.5, { Brightness = p.B, Contrast = p.C, Saturation = p.S, TintColor = p.T }, Enum.EasingStyle.Quad)
	tw(blur, 0.5, { Size = p.blur }, Enum.EasingStyle.Quad)
	bloom.Enabled = p.bloom
	if look.lb ~= L.lb then setBars(look.lb) end
	if not look.overlaySrc then overlay.Visible = false; return end
	overlay.Image = look.overlaySrc
	overlay.ImageTransparency = 1 - (look.op or 1)
	if look.pos == "Corner" then
		set(overlay, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 70), Size = UDim2.fromOffset(150, 150), ScaleType = Enum.ScaleType.Fit })
	elseif look.pos == "Lower third" then
		set(overlay, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -90), Size = UDim2.fromOffset(440, 120), ScaleType = Enum.ScaleType.Fit })
	else
		set(overlay, { AnchorPoint = Vector2.zero, Position = UDim2.new(), Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Stretch })
	end
	overlay.Visible = true
end
local function resolveAsset(id, cb)
	if L.assetCache[id] then cb(L.assetCache[id][1], L.assetCache[id][2]); return end
	task.spawn(function()
		local ok, info = pcall(MPS.GetProductInfo, MPS, tonumber(id))
		local src, note
		if not ok or not info then src, note = "rbxassetid://" .. id, "Couldn't verify asset"
		elseif info.AssetTypeId == 1 then src, note = "rbxassetid://" .. id, info.Name .. " · Image"
		elseif info.AssetTypeId == 13 then src, note = "rbxthumb://type=Asset&id=" .. id .. "&w=420&h=420", info.Name .. " · Decal (thumbnail)"
		else src, note = nil, "Not an image asset" end
		L.assetCache[id] = { src, note }
		cb(src, note)
	end)
end

-- ── controls ────────────────────────────────────────────
local function segmented(p, options, value, onPick)
	local track = frame(p, { BackgroundTransparency = 0, BackgroundColor3 = C.surface2, Size = UDim2.new(1, 0, 0, 30) })
	corner(track, PILL); pad(track, 3); hlist(track, 2)
	local n, btns = #options, {}
	local function paint(v)
		for o, b in btns do
			local s = o == v
			b.BackgroundTransparency = s and 0 or 1
			b.TextColor3 = s and rgb(0, 0, 0) or C.muted
		end
	end
	for i, o in options do
		local b = btn(track, { Text = o, TextSize = 12, FontFace = FONT_S, BackgroundColor3 = C.text, Size = UDim2.new(1 / n, -(2 * (n - 1)) / n, 1, 0), LayoutOrder = i })
		corner(b, PILL)
		btns[o] = b
		on(b.MouseButton1Click, function() paint(o); onPick(o) end)
	end
	paint(value)
	return track
end
local function stepper(p, label, value, onChange)
	local row = frame(p, { Size = UDim2.new(1, 0, 0, 30) })
	txt(row, label, 13, C.text, FONT, { Size = UDim2.new(0.5, 0, 1, 0) })
	local g = frame(row, { BackgroundTransparency = 0, BackgroundColor3 = C.surface2, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(124, 30) })
	corner(g, PILL)
	local minus = btn(g, { Text = "−", TextSize = 16, BackgroundTransparency = 1, Size = UDim2.fromOffset(34, 30) })
	local val = txt(g, "", 13, C.text, FONT_S, { Size = UDim2.new(1, -68, 1, 0), Position = UDim2.fromOffset(34, 0), TextXAlignment = Enum.TextXAlignment.Center })
	local plus = btn(g, { Text = "+", TextSize = 16, BackgroundTransparency = 1, Size = UDim2.fromOffset(34, 30), Position = UDim2.new(1, -34, 0, 0) })
	local v = value
	local function show() val.Text = string.format("%.1f s", v) end
	show()
	on(minus.MouseButton1Click, function() v = math.max(1, v - 0.5); show(); onChange(v) end)
	on(plus.MouseButton1Click, function() v = math.min(30, v + 0.5); show(); onChange(v) end)
end
local function swatches(p, value, onPick)
	local grid = frame(p, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -6, 0, 46), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local strokes = {}
	local function paint(v) for k, s in strokes do s.Enabled = k == v end end
	for i, name in FILTER_ORDER do
		local t = btn(grid, { BackgroundColor3 = C.text, LayoutOrder = i })
		corner(t, 10)
		new("UIGradient", { Color = ColorSequence.new(F[name].g1, F[name].g2), Rotation = 35 }, t)
		txt(t, name, 12, C.text, FONT_SB, { Position = UDim2.new(0, 8, 1, -20), Size = UDim2.new(1, -16, 0, 16), TextStrokeTransparency = 0.7 })
		strokes[name] = new("UIStroke", { Color = C.text, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, t)
		on(t.MouseButton1Click, function() paint(name); onPick(name) end)
	end
	paint(value)
end
local function buildLook(p, look, onChange)
	section(p, "Filter")
	swatches(p, look.filter, function(v) look.filter = v; onChange() end)
	section(p, "Letterbox")
	segmented(p, { "Off", "2.39:1", "16:9", "9:16" }, look.lb, function(v) look.lb = v; onChange() end)
	section(p, "Overlay")
	local row = frame(p, { Size = UDim2.new(1, 0, 0, 40) })
	local box = new("TextBox", { Size = UDim2.new(1, -50, 1, 0), BackgroundColor3 = C.surface2, PlaceholderText = "Image or decal ID", PlaceholderColor3 = C.dim, Text = look.overlayId or "", TextColor3 = C.text, TextSize = 13, FontFace = FONT_S, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false }, row)
	corner(box, PILL); pad(box, 14, 14, 0, 0)
	local prev = new("ImageLabel", { Size = UDim2.fromOffset(40, 40), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), BackgroundColor3 = C.surface2, ScaleType = Enum.ScaleType.Fit, Image = look.overlayId and ("rbxthumb://type=Asset&id=" .. look.overlayId .. "&w=150&h=150") or "" }, row)
	corner(prev, 10)
	local note = txt(p, look.overlayNote or "Paste an ID, then tap outside", 11, C.dim, FONT_S, { TextTruncate = Enum.TextTruncate.AtEnd })
	on(box.FocusLost, function()
		local id = string.match(box.Text, "%d+")
		if not id then
			look.overlayId, look.overlaySrc, look.overlayNote = nil, nil, nil
			prev.Image = ""; note.Text = "Paste an ID, then tap outside"; box.Text = ""
			onChange(); return
		end
		box.Text = id; look.overlayId = id
		prev.Image = "rbxthumb://type=Asset&id=" .. id .. "&w=150&h=150"
		note.Text = "Checking…"
		resolveAsset(id, function(src, n)
			if look.overlayId ~= id then return end
			look.overlaySrc, look.overlayNote = src, n
			if note.Parent then note.Text = n end
			onChange()
		end)
	end)
	segmented(p, { "Full", "Corner", "Lower third" }, look.pos, function(v) look.pos = v; onChange() end)
	segmented(p, { "25%", "50%", "75%", "100%" }, tostring(math.floor((look.op or 1) * 100 + 0.5)) .. "%", function(v)
		look.op = tonumber(string.match(v, "%d+")) / 100; onChange()
	end)
end
local function scaleIn(scale, gui)
	gui.Visible = true; scale.Scale = 0
	tw(scale, 1.2, { Scale = 1 }, Enum.EasingStyle.Exponential)
end
local function scaleOut(scale, gui, still)
	local t = tw(scale, 0.75, { Scale = 0 }, Enum.EasingStyle.Cubic, Enum.EasingDirection.In)
	t.Completed:Once(function() if not still() then gui.Visible = false end end)
end

-- ── quick Look panel ────────────────────────────────────
L.quick = LK("None", "Off", 0)
local qp = frame(ui, { BackgroundTransparency = 0, BackgroundColor3 = C.bg, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -112), Size = UDim2.fromOffset(300, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false })
corner(qp, 22); strokeOf(qp); pad(qp, 16); vlist(qp, 12)
local qpScale = new("UIScale", {}, qp)
local qHead = frame(qp, { Size = UDim2.new(1, 0, 0, 24) })
txt(qHead, "Look", 17, C.text, FONT_SB, { Size = UDim2.new(1, 0, 1, 0) })
local qReset = btn(qHead, { Text = "Reset", TextSize = 12, FontFace = FONT_S, TextColor3 = C.muted, BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(50, 24), TextXAlignment = Enum.TextXAlignment.Right })
local qBody = frame(qp, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
vlist(qBody, 10)
local function renderQuick()
	clear(qBody)
	buildLook(qBody, L.quick, function() applyLook(L.quick) end)
end
on(qReset.MouseButton1Click, function() L.quick = LK("None", "Off", 0); applyLook(L.quick); renderQuick() end)
renderQuick()

-- ── scene editor ────────────────────────────────────────
local BUILTIN = {
	{ name = "DJ Drop", scene = { camera = { { mode = "EpicReveal", dur = 3, blend = false }, { mode = "ZoomBurst", dur = 2, blend = true }, { mode = "MusicVideoSpin", dur = 5, blend = true }, { mode = "CloseUp", dur = 3, blend = false } }, target = { { who = "Self", dur = 13 } }, look = { LK("None", "2.39:1", 3), LK("Neon", "2.39:1", 10) } } },
	{ name = "Slow Reveal", scene = { camera = { { mode = "DollyOut", dur = 5, blend = false }, { mode = "SlowOrbit", dur = 8, blend = true }, { mode = "CraneUp", dur = 5, blend = true } }, target = { { who = "Self", dur = 18 } }, look = { LK("B&W", "2.39:1", 6), LK("Warm", "2.39:1", 12) } } },
	{ name = "Crowd Sweep", scene = { camera = { { mode = "DroneFlyby", dur = 6, blend = false }, { mode = "HighOrbit", dur = 6, blend = true }, { mode = "BirdsEye", dur = 4, blend = true } }, target = { { who = "Self", dur = 16 } }, look = { LK("Cool", "16:9", 16) } } },
}
_G.CineLabPresets = _G.CineLabPresets or BUILTIN
L.presets = _G.CineLabPresets
L.scene = copy(L.presets[1].scene); L.scene.name = L.presets[1].name; L.active = L.presets[1].name

local EW = math.min(workspace.CurrentCamera.ViewportSize.X - 32, 1120)
local EH = 340
local ed = frame(ui, { BackgroundTransparency = 0, BackgroundColor3 = C.bg, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -112), Size = UDim2.fromOffset(EW, EH), Visible = false, ClipsDescendants = true })
corner(ed, 22); strokeOf(ed); pad(ed, 12)
local edScale = new("UIScale", {}, ed)

local header = frame(ed, { Size = UDim2.new(1, 0, 0, 36) })
local hl = frame(header, { Size = UDim2.new(0.4, 0, 1, 0) })
hlist(hl, 10)
local nameBox = new("TextBox", { BackgroundTransparency = 1, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, TextSize = 17, FontFace = FONT_SB, TextColor3 = C.text, ClearTextOnFocus = false, LayoutOrder = 1, Text = "" }, hl)
local durLbl = txt(hl, "", 12, C.muted, FONT_S, { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })
local hc = frame(header, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(240, 36) })
hlist(hc, 8, Enum.HorizontalAlignment.Center)
local restartB = btn(hc, { Text = "⏮", TextSize = 13, BackgroundColor3 = C.surface2, Size = UDim2.fromOffset(32, 32), LayoutOrder = 1 }); corner(restartB, PILL)
local playB = btn(hc, { Text = "▶", TextSize = 14, TextColor3 = rgb(0, 0, 0), BackgroundColor3 = C.text, Size = UDim2.fromOffset(36, 36), LayoutOrder = 2 }); corner(playB, PILL)
local timeLbl = txt(hc, "", 13, C.text, FONT_S, { Size = UDim2.fromOffset(120, 36), LayoutOrder = 3 })
local hr = frame(header, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.35, 0, 1, 0) })
hlist(hr, 8, Enum.HorizontalAlignment.Right)
local loopB = btn(hr, { Text = "Loop", TextSize = 12, FontFace = FONT_S, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1 }); corner(loopB, PILL); pad(loopB, 14, 14, 0, 0)
local saveB = btn(hr, { Text = "Save preset", TextSize = 12, FontFace = FONT_SB, TextColor3 = rgb(0, 0, 0), BackgroundColor3 = C.text, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 }); corner(saveB, PILL); pad(saveB, 16, 16, 0, 0)
local closeB = btn(hr, { BackgroundColor3 = C.surface2, Size = UDim2.fromOffset(30, 30), LayoutOrder = 3 }); corner(closeB, PILL)
for _, r in { 45, -45 } do frame(closeB, { BackgroundTransparency = 0, BackgroundColor3 = C.text, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(12, 1.5), Rotation = r }) end

local body = frame(ed, { Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -46) })
local presetCol = frame(body, { BackgroundTransparency = 0, BackgroundColor3 = C.surface, Size = UDim2.new(0, 180, 1, 0) })
corner(presetCol, 14); pad(presetCol, 10)
section(presetCol, "Presets").Size = UDim2.new(1, 0, 0, 20)
local newB = btn(presetCol, { Text = "+ New", TextSize = 12, FontFace = FONT_S, TextColor3 = C.muted, BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(50, 20), TextXAlignment = Enum.TextXAlignment.Right })
local presetList = new("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 1, -28), ScrollBarThickness = 2, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, presetCol)
vlist(presetList, 4)

local tlCol = frame(body, { BackgroundTransparency = 0, BackgroundColor3 = C.surface, Position = UDim2.fromOffset(190, 0), Size = UDim2.new(1, -190 - 290, 1, 0), ClipsDescendants = true })
corner(tlCol, 14); pad(tlCol, 10)
local TRACKS = { { key = "camera", name = "Camera", accent = C.text }, { key = "target", name = "Target", accent = rgb(120, 160, 255) }, { key = "look", name = "Look", accent = rgb(255, 150, 200) } }
for i, tr in TRACKS do
	local y = RULER + 4 + (i - 1) * (ROW + GAP)
	local lab = frame(tlCol, { Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(70, ROW) })
	local dot = frame(lab, { BackgroundTransparency = 0, BackgroundColor3 = tr.accent, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0), Size = UDim2.fromOffset(6, 6) })
	corner(dot, PILL)
	txt(lab, tr.name, 12, C.text, FONT, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -14, 1, 0) })
end
local tlH = RULER + 4 + 3 * (ROW + GAP)
local scroll = new("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(76, 0), Size = UDim2.new(1, -76, 0, tlH + 6), ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 3, ScrollBarImageColor3 = C.dim, CanvasSize = UDim2.new() }, tlCol)
txt(tlCol, "Tap a shot to edit  ·  + adds a shot  ·  tap the ruler to scrub", 11, C.dim, FONT_S, { Position = UDim2.new(0, 0, 1, -16), Size = UDim2.new(1, 0, 0, 16) })

local insCol = frame(body, { BackgroundTransparency = 0, BackgroundColor3 = C.surface, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 280, 1, 0), ClipsDescendants = true })
corner(insCol, 14)
local ins = new("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ScrollBarThickness = 2, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, insCol)
pad(ins, 12); vlist(ins, 10)

local renderTimeline, renderInspector, renderPresets, updateHeader, renderAll

local function clipTitle(key, c)
	if key == "camera" then local m = Modes.Character[c.mode]; return m and m.label or c.mode end
	if key == "target" then
		if c.who == "Self" then return "You" end
		local p = Players:FindFirstChild(c.who)
		return p and p.DisplayName or c.who
	end
	local s = c.filter
	if c.lb ~= "Off" then s ..= " · " .. c.lb end
	if c.overlayId then s ..= " · Overlay" end
	return s
end
local function movePlayhead()
	if L.playhead then L.playhead.Position = UDim2.fromOffset(L.t * PPS, 0) end
	timeLbl.Text = fmt(L.t) .. "  /  " .. fmt(sceneTotal(L.scene))
end
local function seekX(x)
	local total = sceneTotal(L.scene)
	L.t = math.clamp((x - scroll.AbsolutePosition.X + scroll.CanvasPosition.X) / PPS, 0, total)
	movePlayhead()
	if not L.playing then local _, lc = clipAt(L.scene.look, L.t); if lc then applyLook(lc) end end
end
local function addClip(key)
	local list = L.scene[key]
	local last = list[#list]
	local c
	if key == "camera" then c = { mode = last and last.mode or "SlowOrbit", dur = 3, blend = true }
	elseif key == "target" then c = { who = "Self", dur = 4 }
	else c = last and copy(last) or LK("None", "Off", 4); c.dur = 4 end
	table.insert(list, c)
	L.sel = { key = key, i = #list }
	renderAll()
end

renderTimeline = function()
	clear(scroll)
	local total = sceneTotal(L.scene)
	local w = total * PPS + 80
	scroll.CanvasSize = UDim2.fromOffset(w, 0)
	local ruler = btn(scroll, { BackgroundTransparency = 1, Size = UDim2.fromOffset(w, RULER) })
	on(ruler.InputBegan, function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then seekX(inp.Position.X) end
	end)
	for s = 0, math.ceil(total) do
		local major = s % 2 == 0
		frame(ruler, { BackgroundTransparency = 0, BackgroundColor3 = major and C.muted or C.dim, Position = UDim2.fromOffset(s * PPS, major and 13 or 16), Size = UDim2.fromOffset(1, major and 7 or 4) })
		if major then txt(ruler, fmt(s):gsub("%.0$", ""), 10, C.dim, FONT_S, { Position = UDim2.fromOffset(s * PPS + 4, 0), Size = UDim2.fromOffset(40, 12) }) end
	end
	for i, tr in TRACKS do
		local y = RULER + 4 + (i - 1) * (ROW + GAP)
		local lane = frame(scroll, { BackgroundTransparency = 0, BackgroundColor3 = C.bg, Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(w, ROW) })
		corner(lane, 10)
		local acc = 0
		for j, c in L.scene[tr.key] do
			local sel = L.sel and L.sel.key == tr.key and L.sel.i == j
			local fc = tr.key == "look" and (F[c.filter] or F.None) or nil
			local clip = btn(scroll, { BackgroundColor3 = fc and fc.clip or (tr.key == "target" and rgb(30, 38, 54) or rgb(40, 40, 40)), Position = UDim2.fromOffset(acc * PPS + 2, y + 4), Size = UDim2.fromOffset(c.dur * PPS - 4, ROW - 8), ZIndex = 2, ClipsDescendants = true })
			corner(clip, 8)
			local bar = frame(clip, { BackgroundTransparency = 0, BackgroundColor3 = fc and fc.accent or tr.accent, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0), Size = UDim2.fromOffset(3, 18), ZIndex = 2 })
			corner(bar, PILL)
			txt(clip, clipTitle(tr.key, c), 12, C.text, FONT, { Position = UDim2.fromOffset(15, 4), Size = UDim2.new(1, -19, 0, 15), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 2 })
			local sub = string.format("%.1fs", c.dur)
			if tr.key == "camera" then sub ..= c.blend and "  ·  Blend" or "  ·  Cut" end
			txt(clip, sub, 10, C.muted, FONT_S, { Position = UDim2.fromOffset(15, 20), Size = UDim2.new(1, -19, 0, 12), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 2 })
			if sel then new("UIStroke", { Color = C.text, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, clip) end
			on(clip.MouseButton1Click, function()
				L.sel = { key = tr.key, i = j }
				renderTimeline(); renderInspector()
				if tr.key == "look" and not L.playing then applyLook(c) end
			end)
			acc += c.dur
		end
		local add = btn(scroll, { Text = "+", TextSize = 18, TextColor3 = C.muted, BackgroundColor3 = C.surface2, Position = UDim2.fromOffset(acc * PPS + 4, y + 4), Size = UDim2.fromOffset(36, ROW - 8), ZIndex = 2 })
		corner(add, 8)
		on(add.MouseButton1Click, function() addClip(tr.key) end)
	end
	L.playhead = frame(scroll, { BackgroundTransparency = 0, BackgroundColor3 = C.text, Size = UDim2.fromOffset(2, tlH), ZIndex = 5 })
	local knob = frame(L.playhead, { BackgroundTransparency = 0, BackgroundColor3 = C.text, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.fromOffset(10, 10), ZIndex = 5 })
	corner(knob, PILL)
	movePlayhead()
end

local function pickList(p, items, current, height, onPick, searchable)
	local search
	if searchable then
		search = new("TextBox", { Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = C.surface2, PlaceholderText = "Search movement", PlaceholderColor3 = C.dim, Text = "", TextColor3 = C.text, TextSize = 13, FontFace = FONT_S, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, LayoutOrder = nx() }, p)
		corner(search, PILL); pad(search, 14, 14, 0, 0)
	end
	local lf = new("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, height), ScrollBarThickness = 2, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, LayoutOrder = nx() }, p)
	vlist(lf, 2)
	local rows = {}
	local function paint(v)
		for id, r in rows do
			local s = id == v
			r.BackgroundTransparency = s and 0 or 1
			r.TextColor3 = s and rgb(0, 0, 0) or C.text
		end
	end
	for _, it in items do
		local r = btn(lf, { Text = it.label, TextSize = 13, FontFace = FONT, BackgroundColor3 = C.text, Size = UDim2.new(1, -4, 0, 30), TextXAlignment = Enum.TextXAlignment.Left })
		corner(r, 8); pad(r, 10, 10, 0, 0)
		rows[it.id] = r
		on(r.MouseButton1Click, function() paint(it.id); onPick(it.id) end)
	end
	paint(current)
	if search then
		on(search:GetPropertyChangedSignal("Text"), function()
			local q = string.lower(search.Text)
			for _, it in items do rows[it.id].Visible = q == "" or string.find(string.lower(it.label), q, 1, true) ~= nil end
		end)
	end
end

renderInspector = function()
	clear(ins)
	local sel = L.sel
	if not sel or not L.scene[sel.key][sel.i] then
		txt(ins, "No shot selected", 14, C.text, FONT_SB)
		txt(ins, "Tap a shot on the timeline to edit its movement, target or look.", 12, C.muted, FONT_S, { TextWrapped = true, Size = UDim2.new(1, 0, 0, 34) })
		return
	end
	local list = L.scene[sel.key]
	local c = list[sel.i]
	local trName = sel.key == "camera" and "Camera" or sel.key == "target" and "Target" or "Look"
	txt(ins, trName .. " shot", 15, C.text, FONT_SB)
	txt(ins, "Shot " .. sel.i .. " of " .. #list, 11, C.muted, FONT_S)
	local function changed() renderTimeline(); updateHeader() end
	if sel.key == "camera" then
		section(ins, "Movement")
		local items = {}
		for id, m in Modes.Character do
			if not string.find(id, "^Donation") then table.insert(items, { id = id, label = m.label }) end
		end
		table.sort(items, function(a, b) return a.label < b.label end)
		pickList(ins, items, c.mode, 150, function(id) c.mode = id; changed() end, true)
		section(ins, "Transition")
		segmented(ins, { "Cut", "Blend" }, c.blend and "Blend" or "Cut", function(v) c.blend = v == "Blend"; changed() end)
	elseif sel.key == "target" then
		section(ins, "Follow")
		local items = { { id = "Self", label = "You" } }
		for _, p in Players:GetPlayers() do
			if p ~= lp then table.insert(items, { id = p.Name, label = p.DisplayName .. "  @" .. p.Name }) end
		end
		pickList(ins, items, c.who, math.min(#items, 5) * 32, function(id) c.who = id; changed() end, false)
	else
		buildLook(ins, c, function() if not L.playing then applyLook(c) end changed() end)
	end
	section(ins, "Timing")
	stepper(ins, "Duration", c.dur, function(v) c.dur = v; changed() end)
	local actions = frame(ins, { Size = UDim2.new(1, 0, 0, 30) })
	hlist(actions, 8)
	local dup = btn(actions, { Text = "Duplicate", TextSize = 12, FontFace = FONT_S, BackgroundColor3 = C.surface2, Size = UDim2.new(0.5, -4, 1, 0) }); corner(dup, PILL)
	local del = btn(actions, { Text = "Delete", TextSize = 12, FontFace = FONT_S, TextColor3 = #list > 1 and C.danger or C.dim, BackgroundColor3 = C.surface2, Size = UDim2.new(0.5, -4, 1, 0) }); corner(del, PILL)
	on(dup.MouseButton1Click, function() table.insert(list, sel.i + 1, copy(c)); L.sel = { key = sel.key, i = sel.i + 1 }; renderAll() end)
	on(del.MouseButton1Click, function()
		if #list <= 1 then return end
		table.remove(list, sel.i); L.sel = nil; renderAll()
	end)
end

renderPresets = function()
	clear(presetList)
	for _, p in L.presets do
		local active = p.name == L.active
		local r = btn(presetList, { BackgroundColor3 = C.surface3, BackgroundTransparency = active and 0 or 1, Size = UDim2.new(1, -4, 0, 44) })
		corner(r, 10)
		txt(r, p.name, 13, C.text, active and FONT_SB or FONT, { Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd })
		txt(r, string.format("%.1fs  ·  %d shots", sceneTotal(p.scene), #p.scene.camera), 11, C.muted, FONT_S, { Position = UDim2.fromOffset(10, 24), Size = UDim2.new(1, -20, 0, 13) })
		on(r.MouseButton1Click, function()
			if L.playing then return end
			L.scene = copy(p.scene); L.scene.name = p.name; L.active = p.name; L.sel = nil; L.t = 0
			renderAll()
			local _, lc = clipAt(L.scene.look, 0); if lc then applyLook(lc) end
		end)
	end
end

updateHeader = function()
	if not nameBox:IsFocused() then nameBox.Text = L.scene.name or "Untitled scene" end
	durLbl.Text = string.format("%.1fs  ·  %d shots", sceneTotal(L.scene), #L.scene.camera)
	playB.Text = L.playing and "❚❚" or "▶"
	loopB.BackgroundColor3 = L.loop and C.text or C.surface2
	loopB.TextColor3 = L.loop and rgb(0, 0, 0) or C.muted
	movePlayhead()
end
renderAll = function() renderPresets(); renderTimeline(); renderInspector(); updateHeader() end

local function toast(msg)
	local t = btn(ui, { Text = msg, TextSize = 13, FontFace = FONT_SB, TextColor3 = rgb(0, 0, 0), BackgroundColor3 = C.text, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 56), Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, TextTransparency = 1 })
	corner(t, PILL); pad(t, 18, 18, 0, 0)
	tw(t, 0.3, { BackgroundTransparency = 0, TextTransparency = 0, Position = UDim2.new(0.5, 0, 0, 64) })
	task.delay(1.8, function()
		if not t.Parent then return end
		tw(t, 0.4, { BackgroundTransparency = 1, TextTransparency = 1 }).Completed:Once(function() t:Destroy() end)
	end)
end

-- ── playback ────────────────────────────────────────────
local function hideOthers(v)
	if v then
		for _, g in pg:GetChildren() do
			if g:IsA("ScreenGui") and g ~= ui and g ~= fx and g.Enabled then g.Enabled = false; table.insert(L.hidden, g) end
		end
	else
		for _, g in L.hidden do if g.Parent then g.Enabled = true end end
		table.clear(L.hidden)
	end
end
local function step(dt)
	local total = sceneTotal(L.scene)
	L.t += dt
	if L.t >= total then
		if L.loop then L.t = 0; L.camIdx = nil; L.lookIdx = nil
		else L.t = total; L.stop(); return end
	end
	local _, tc = clipAt(L.scene.target, L.t)
	local char = lp.Character
	if tc and tc.who ~= "Self" then
		local p = Players:FindFirstChild(tc.who)
		if p and p.Character then char = p.Character end
	end
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local head = char and char:FindFirstChild("Head")
	if not (root and head) then return end
	local ci, cclip = clipAt(L.scene.camera, L.t)
	if ci ~= L.camIdx then
		L.camIdx = ci
		L.mode = Modes.Character[cclip.mode] or Modes.Character.SlowOrbit
		L.camState = { t = 0, speed = 1 }
		if L.mode.init then pcall(L.mode.init, L.camState, root, head) end
		L.first = true; L.blend = cclip.blend
	end
	local ok, cf, fov = pcall(L.mode.update, L.camState, dt, root, head)
	local cam = workspace.CurrentCamera
	if ok and typeof(cf) == "CFrame" then
		fov = fov or 70
		if L.first and not L.blend then
			cam.CFrame = cf; cam.FieldOfView = fov
		else
			local a = 1 - math.exp(-(L.mode.lerpSpeed or 6) * dt)
			cam.CFrame = cam.CFrame:Lerp(cf, a)
			cam.FieldOfView += (fov - cam.FieldOfView) * a
		end
	end
	L.first = false
	local li, lc = clipAt(L.scene.look, L.t)
	if li ~= L.lookIdx then L.lookIdx = li; applyLook(lc) end
	movePlayhead()
end
local function play()
	if L.playing then return end
	if L.t >= sceneTotal(L.scene) - 0.05 then L.t = 0 end
	L.playing = true; L.camIdx = nil; L.lookIdx = nil
	local cam = workspace.CurrentCamera
	L.savedFov = cam.FieldOfView
	cam.CameraType = Enum.CameraType.Scriptable
	hideOthers(true)
	if qp.Visible then qp.Visible = false end
	body.Visible = false
	tw(ed, 0.6, { Size = UDim2.fromOffset(EW, 60), Position = UDim2.new(0.5, 0, 1, -24) })
	RS:BindToRenderStep("CineLabPlay", Enum.RenderPriority.Camera.Value + 1, step)
	updateHeader()
end
L.stop = function()
	if not L.playing then return end
	L.playing = false
	RS:UnbindFromRenderStep("CineLabPlay")
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
	if hum then cam.CameraSubject = hum end
	cam.FieldOfView = L.savedFov or 70
	hideOthers(false)
	applyLook(L.quick)
	tw(ed, 0.6, { Size = UDim2.fromOffset(EW, EH), Position = UDim2.new(0.5, 0, 1, -112) }).Completed:Once(function()
		if not L.playing then body.Visible = true end
	end)
	updateHeader()
end

-- ── wiring ──────────────────────────────────────────────
on(playB.MouseButton1Click, function() if L.playing then L.stop() else play() end end)
on(restartB.MouseButton1Click, function() L.t = 0; L.camIdx = nil; L.lookIdx = nil; movePlayhead() end)
on(loopB.MouseButton1Click, function() L.loop = not L.loop; updateHeader() end)
on(nameBox.FocusLost, function()
	local n = string.gsub(nameBox.Text, "^%s+", "")
	L.scene.name = n ~= "" and n or "Untitled scene"
	updateHeader()
end)
on(saveB.MouseButton1Click, function()
	local name = L.scene.name or "Untitled scene"
	local data = copy(L.scene); data.name = nil
	local found = false
	for _, p in L.presets do if p.name == name then p.scene = data; found = true end end
	if not found then table.insert(L.presets, { name = name, scene = data }) end
	L.active = name
	renderPresets()
	toast((found and "Updated  “" or "Saved  “") .. name .. "”")
end)
on(newB.MouseButton1Click, function()
	if L.playing then return end
	L.scene = { name = "Untitled scene", camera = { { mode = "SlowOrbit", dur = 4, blend = false } }, target = { { who = "Self", dur = 4 } }, look = { LK("None", "Off", 4) } }
	L.active = nil; L.sel = { key = "camera", i = 1 }; L.t = 0
	renderAll(); nameBox:CaptureFocus()
end)
local function setEditor(v)
	L.edOpen = v
	if v then
		if qp.Visible then L.qOpen = false; scaleOut(qpScale, qp, function() return L.qOpen end) end
		scaleIn(edScale, ed)
	else
		L.stop()
		scaleOut(edScale, ed, function() return L.edOpen end)
	end
end
local function setQuick(v)
	L.qOpen = v
	if v then
		if L.edOpen then setEditor(false) end
		scaleIn(qpScale, qp)
	else
		scaleOut(qpScale, qp, function() return L.qOpen end)
	end
end
on(closeB.MouseButton1Click, function() setEditor(false) end)
on(sceneBtn.MouseButton1Click, function() setEditor(not L.edOpen) end)
on(lookBtn.MouseButton1Click, function() setQuick(not L.qOpen) end)

_G.CineLabCleanup = function()
	L.stop()
	for _, c in L.conns do c:Disconnect() end
	for _, i in { lookW, sceneW, ui, fx, cc, bloom, blur } do i:Destroy() end
	dock.Size = saved.dock
	tgtW.Size, tgtW.LayoutOrder = saved.tgt[1], saved.tgt[2]
	movW.Size, movW.LayoutOrder = saved.mov[1], saved.mov[2]
	spd.Size, spd.LayoutOrder = saved.spd[1], saved.spd[2]
	_G.CineLabCleanup = nil
end
_G.CineLab = { setEditor = setEditor, setQuick = setQuick, play = play, stop = L.stop, L = L }

renderAll()
setEditor(true)
return "ok"