--!nocheck
-- DJ panel UI exploration (owner, 2026-10-08) — PLACE-ONLY MOCKUP, not kit code.
-- Lives as StarterGui.DJGUI.DJXExperiment in the Experiment Area place and restyles the
-- owner's DJGUI template at runtime (the template itself stays untouched). Everything here is
-- visual + local interaction; nothing talks to the server or the music system yet.
-- Notes and decisions: docs/plans/dj-panel-2026-10-08.md

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local gui = script.Parent
local root = gui:WaitForChild("9-AdvancedDJ")
-- AdvancedDJController wires the EQ knobs / faders by path on its first frame; let it finish
-- before anything here moves those objects.
task.wait(0.25)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local B = Font.new("rbxassetid://12187365364", Enum.FontWeight.Bold)
local SB = Font.new("rbxassetid://12187365364", Enum.FontWeight.SemiBold)
local W = Color3.new(1, 1, 1)
-- djay-style neutral greys (2026-10-10; was a purple-tinted set)
local C = {
	gutter = Color3.fromHex("0a0a0a"),
	bg = Color3.fromHex("1c1c1c"),
	card = Color3.fromHex("222222"),
	card2 = Color3.fromHex("2a2a2a"),
	inset = Color3.fromHex("141414"),
	dim = Color3.fromHex("7f7f7f"),
	live = Color3.fromRGB(228, 16, 36),
	accent = Color3.fromRGB(234, 75, 7),
	ok = Color3.fromRGB(46, 200, 110),
	sfx = Color3.fromRGB(255, 150, 60),
	world = Color3.fromRGB(110, 140, 255),
	deckA = Color3.fromRGB(80, 170, 255),
	deckB = Color3.fromRGB(255, 120, 70),
	lane = Color3.fromHex("141414"),
	wave = Color3.fromHex("101010"),
}

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in props do
		i[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end
local function noTint(i)
	i:SetAttribute("AccentNoTint", true)
	return i
end
local function isPress(i)
	return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end
local function isMove(i)
	return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch
end
local function txt(parent, props)
	local l = new("TextLabel", { BackgroundTransparency = 1, FontFace = SB, TextColor3 = W, TextSize = 14, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new() }, parent)
	for k, v in props do
		l[k] = v
	end
	return l
end

local deckRoot = root.DJ_Deck
local deckWrapper = deckRoot.DeckWrapper
local overlay = new("Frame", { Name = "DJX_Overlay", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 20 }, gui)
local function rel(g)
	return g.AbsolutePosition - overlay.AbsolutePosition
end

-- ════════════════════════════════════════════════════════════
-- 1. Fit to screen
-- ════════════════════════════════════════════════════════════
local scale = root:FindFirstChildOfClass("UIScale") or new("UIScale", {}, root)
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
local function fit()
	local vp = camera.ViewportSize
	local h = root.AbsoluteSize.Y / math.max(scale.Scale, 0.01)
	scale.Scale = math.min(1, (vp.X - 48) / 1250, (vp.Y - 72) / math.max(h, 1))
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	task.defer(fit)
end)

-- ════════════════════════════════════════════════════════════
-- 2. Header: DJ BOOTH · ON AIR · listeners | crowd hype | DROP · TAKE OVER · — ×
-- ════════════════════════════════════════════════════════════
do
	local minOrder = 0
	for _, c in root:GetChildren() do
		if c:IsA("GuiObject") then
			minOrder = math.min(minOrder, c.LayoutOrder)
		end
	end
	local header = new("Frame", { Name = "DJX_Header", Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = C.bg, BorderSizePixel = 0, LayoutOrder = minOrder - 1 }, root)
	new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, header)
	new("Frame", { Size = UDim2.new(1, 32, 0, 1), Position = UDim2.new(0, -16, 1, -1), BackgroundColor3 = W, BackgroundTransparency = 0.92, BorderSizePixel = 0 }, header)
	local function row(parent, align, pad)
		return new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = align or Enum.HorizontalAlignment.Left, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, pad or 10), SortOrder = Enum.SortOrder.LayoutOrder }, parent)
	end
	local left = new("Frame", { Size = UDim2.fromScale(0.36, 1), BackgroundTransparency = 1 }, header)
	row(left)
	txt(left, { Text = "DJ BOOTH", FontFace = B, TextSize = 16, LayoutOrder = 1 })
	local onair = noTint(new("Frame", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 0, 22), BackgroundColor3 = C.live, LayoutOrder = 2 }, left))
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, onair)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, onair)
	row(onair, nil, 6)
	local dot = new("Frame", { Size = UDim2.fromOffset(6, 6), BackgroundColor3 = W, LayoutOrder = 1 }, onair)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
	txt(onair, { Text = "ON AIR", FontFace = B, TextSize = 12, LayoutOrder = 2 })
	local glow = new("UIStroke", { Color = C.live, Thickness = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, onair)
	txt(left, { Text = "24 listening", TextColor3 = C.dim, TextSize = 13, LayoutOrder = 3 })

	local hype = new("Frame", { Size = UDim2.new(0.2, 0, 0, 30), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1 }, header)
	txt(hype, { Text = "CROWD HYPE", FontFace = B, TextSize = 11, TextColor3 = C.dim })
	local pct = txt(hype, { Text = "60%", FontFace = B, TextSize = 11, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0) })
	local bar = new("Frame", { Size = UDim2.new(1, 0, 0, 6), AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), BackgroundColor3 = C.card2 }, hype)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, bar)
	local fill = noTint(new("Frame", { Size = UDim2.fromScale(0.6, 1), BackgroundColor3 = W }, bar))
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
	new("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 90, 255)), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 60, 140)), ColorSequenceKeypoint.new(1, C.accent) }) }, fill)

	local right = new("Frame", { Size = UDim2.fromScale(0.36, 1), AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), BackgroundTransparency = 1 }, header)
	row(right, Enum.HorizontalAlignment.Right, 8)
	local function hbtn(text, w, bg, order, size)
		local b = new("TextButton", { Text = text, FontFace = B, TextSize = size or 13, TextColor3 = W, Size = UDim2.fromOffset(w, 32), BackgroundColor3 = bg, AutoButtonColor = true, LayoutOrder = order }, right)
		new("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
		return b
	end
	local drop = hbtn("DROP", 88, C.accent, 1)
	hbtn("TAKE OVER", 100, C.card2, 2)
	new("Frame", { Size = UDim2.fromOffset(1, 20), BackgroundColor3 = W, BackgroundTransparency = 0.85, BorderSizePixel = 0, LayoutOrder = 3 }, right)
	hbtn("—", 32, C.card, 4)
	hbtn("×", 32, C.card, 5, 18)

	local busy = false
	drop.MouseButton1Click:Connect(function()
		if busy then
			return
		end
		busy = true
		local o = new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "3", FontFace = B, TextSize = 160, TextColor3 = W, ZIndex = 50 }, gui)
		new("UIStroke", { Color = C.accent, Thickness = 4 }, o)
		for _, n in { "3", "2", "1" } do
			o.Text = n
			local s = new("UIScale", { Scale = 1.4 }, o)
			TweenService:Create(s, TweenInfo.new(0.8, Enum.EasingStyle.Quint), { Scale = 1 }):Play()
			task.wait(0.9)
			s:Destroy()
		end
		o.Text = "DROP!"
		o.TextColor3 = C.accent
		local flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = W, BackgroundTransparency = 0.2, ZIndex = 49 }, gui)
		TweenService:Create(flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(o, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
		task.wait(1.3)
		o:Destroy()
		flash:Destroy()
		busy = false
	end)

	local t0 = os.clock()
	RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local p = (math.sin(t * math.pi * 1.4) + 1) / 2
		glow.Thickness = p * 3
		glow.Transparency = 0.25 + p * 0.7
		dot.BackgroundTransparency = (t % 1) < 0.5 and 0 or 0.7
		local h = 0.62 + math.sin(t * 0.7) * 0.12 + math.sin(t * 2.3) * 0.04
		fill.Size = UDim2.fromScale(h, 1)
		pct.Text = math.floor(h * 100) .. "%"
	end)
end

-- ════════════════════════════════════════════════════════════
-- 3. Effect pads: category strip on the left, cooldown inside the label
-- ════════════════════════════════════════════════════════════
do
	local WORLD = { ["Camera Shake"] = true, ["Camera Rotate"] = true, ["Darken Camera"] = true, ["Ungravity All Players"] = true }
	for _, rowFrame in { root.DJ_SoundAndGlobalEffects.Top, root.DJ_SoundAndGlobalEffects.Bottom } do
		for _, b in rowFrame:GetChildren() do
			if b:IsA("TextButton") then
				local world = WORLD[b.Text] == true
				local strip = noTint(new("Frame", { Name = "CategoryStrip", Size = UDim2.new(0, 3, 1, -14), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), BackgroundColor3 = world and C.world or C.sfx, BorderSizePixel = 0, ZIndex = 3 }, b))
				new("UICorner", { CornerRadius = UDim.new(1, 0) }, strip)
				local cd = new("Frame", { Name = "Cooldown", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 2 }, b)
				local base = b.Text
				local secs = world and 8 or 3
				local bz = false
				b.MouseButton1Click:Connect(function()
					if bz then
						return
					end
					bz = true
					cd.Size = UDim2.fromScale(1, 1)
					TweenService:Create(cd, TweenInfo.new(secs, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()
					for s = secs, 1, -1 do
						b.Text = base .. "  ·  " .. s .. "s"
						task.wait(1)
					end
					b.Text = base
					bz = false
				end)
			end
		end
	end
end

-- ════════════════════════════════════════════════════════════
-- 4. Library: Library / Requests / Queue tabs (mock rows)
-- ════════════════════════════════════════════════════════════
do
	local song = root.DJ_Library["2-SelectSong"]
	local trackList = song.TrackList
	local scroll = trackList.ScrollableTrackList
	local template = scroll.TrackWrapperTemplate
	local function makeList(name)
		local sf = scroll:Clone()
		sf.Name = name
		for _, c in sf:GetChildren() do
			if c:IsA("GuiButton") or c:IsA("Frame") then
				c:Destroy()
			end
		end
		sf.Visible = false
		sf.Parent = trackList
		return sf
	end
	local function fill(sf, rows)
		for i, r in rows do
			local row = template:Clone()
			row.Name = "Row" .. i
			row.LayoutOrder = i
			row.Visible = true
			local info = row.TrackInformationWrapper.TrackInformation
			local leftD, rightD
			for _, d in info:GetChildren() do
				if d.Name == "TrackDetails" then
					if d:FindFirstChild("TrackTitle") then
						leftD = d
					else
						rightD = d
					end
				end
			end
			if r.image then
				row.RelatedPlaylistCover.Image = r.image
			end
			row.RelatedPlaylistCover.PlaylistName.Text = r.coverText or ""
			leftD.TrackTitle.Text = r.title
			leftD.TrackCreator.Text = r.sub
			rightD.TrackBPM.Visible = false
			rightD.TrackLength.Visible = false
			local bar = new("Frame", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 0, 30), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), BackgroundTransparency = 1, ZIndex = 4 }, row)
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, bar)
			new("TextLabel", { Text = r.meta, FontFace = B, TextSize = 13, TextColor3 = C.dim, BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), LayoutOrder = 0 }, bar)
			for j, bdef in r.buttons do
				local btn = noTint(new("TextButton", { Text = bdef[1], FontFace = B, TextSize = 13, TextColor3 = W, Size = UDim2.fromOffset(bdef[3], 30), BackgroundColor3 = bdef[2], LayoutOrder = j, ZIndex = 5 }, bar))
				new("UICorner", { CornerRadius = UDim.new(0, 8) }, btn)
				btn.MouseButton1Click:Connect(function()
					row:Destroy()
				end)
			end
			row.Parent = sf
		end
	end
	local function head(id)
		return ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(id)
	end
	local requests = makeList("DJX_Requests")
	fill(requests, {
		{ image = head(player.UserId), title = "Dua Lipa — Houdini (Extended Mix)", sub = "Requested by Rio  ·  2 votes", meta = "3:42", buttons = { { "Play next", C.ok, 92 }, { "Skip", C.card2, 64 } } },
		{ image = head(1), title = "Fred again.. — Delilah (pull me out of this)", sub = "Requested by Nadia  ·  5 votes", meta = "4:10", buttons = { { "Play next", C.ok, 92 }, { "Skip", C.card2, 64 } } },
		{ image = head(156), title = "Amapiano Sunset Set Vol. 3", sub = "Requested by Kevin  ·  1 vote", meta = "12:30", buttons = { { "Play next", C.ok, 92 }, { "Skip", C.card2, 64 } } },
	})
	local queue = makeList("DJX_Queue")
	fill(queue, {
		{ coverText = "UP NEXT", title = "Peggy Gou — (It Goes Like) Nanana", sub = "Loads on Deck B", meta = "124 BPM", buttons = { { "Load B", C.card2, 72 } } },
		{ coverText = "#2", title = "Calvin Harris — Desire", sub = "Queued by Nadia", meta = "122 BPM", buttons = { { "Load B", C.card2, 72 } } },
		{ coverText = "#3", title = "Rufus Du Sol — Innerbloom", sub = "Session set", meta = "121 BPM", buttons = { { "Load B", C.card2, 72 } } },
	})
	for _, sf in { scroll, requests, queue } do
		local pad = sf:FindFirstChildOfClass("UIPadding")
		if pad then
			pad.PaddingTop = UDim.new(0, 56)
			pad.PaddingBottom = UDim.new(0, 76)
		end
		sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
		sf.CanvasSize = UDim2.new()
	end

	local tabs = new("Frame", { Name = "DJX_Tabs", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 0, 40), BackgroundColor3 = C.card, ZIndex = 5 }, overlay)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, tabs)
	new("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }, tabs)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, tabs)
	local tabScale = new("UIScale", {}, tabs)
	local views = { Library = scroll, Requests = requests, Queue = queue }
	local tabBtns = {}
	local function select(name)
		for n, v in views do
			v.Visible = n == name
		end
		for n, b in tabBtns do
			b.BackgroundTransparency = n == name and 0 or 1
			b.TextColor3 = n == name and W or C.dim
		end
	end
	for i, def in { { "Library", "Library" }, { "Requests", "Requests  3" }, { "Queue", "Queue  3" } } do
		local b = new("TextButton", { Text = def[2], FontFace = B, TextSize = 13, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = C.card2, LayoutOrder = i, ZIndex = 6 }, tabs)
		new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, b)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, b)
		tabBtns[def[1]] = b
		b.MouseButton1Click:Connect(function()
			select(def[1])
		end)
	end
	select("Library")
	RunService.RenderStepped:Connect(function()
		local sc = scale.Scale
		local p = rel(song)
		tabs.Position = UDim2.fromOffset(p.X + 16 * sc, p.Y + 6 * sc)
		tabScale.Scale = sc
		overlay.Visible = root.Visible and gui.Enabled
	end)
end

-- ════════════════════════════════════════════════════════════
-- 5. Deck geometry: taller deck row; centre 30%, decks 35%; per deck
--    SYNC/speed 20% | platter + EQ row 63% | filter + volume 17%
-- ════════════════════════════════════════════════════════════
local PAD, ROW, GAP = 14, 84, 8
-- FILTER column and knob at x1.3 of the old 84 / 43 px, so the knob reads as the deck's main control
-- (owner, 2026-10-10: "gedein secara proporsional"). The two labels keep their old 14 / 17 px.
local FILTER_H, FILTER_KNOB, FILTER_LABEL, FILTER_VALUE = 104, 56, 14, 17
-- both faders (speed on the left, volume on the right) run the same length, bottom on the EQ row's
-- bottom edge (y 287 of the 301 px deck), so they line up top to bottom
local SLIDER_H = 162
do
	deckRoot.CurrentTrack.Size = UDim2.new(1, 0, 0, 88)
	deckRoot.EffectWrapperTop.Size = UDim2.new(1, 0, 0, 57)
	deckRoot.EffectWrapperBottom.Size = UDim2.new(1, 0, 0, 57)
	deckWrapper.Size = UDim2.new(1, 0, 0, 301)
	deckRoot.Size = UDim2.new(1, 0, 0, 88 + 57 + 57 + 301)
	deckWrapper.Waveform.Size = UDim2.fromScale(0.3, 1)

	local function pad(o, t, b, l, r)
		local p = o:FindFirstChildOfClass("UIPadding") or new("UIPadding", {}, o)
		p.PaddingTop = UDim.new(0, t)
		p.PaddingBottom = UDim.new(0, b)
		if l then
			p.PaddingLeft = UDim.new(0, l)
		end
		if r then
			p.PaddingRight = UDim.new(0, r)
		end
	end
	for _, deckName in { "Deck_A", "Deck_B" } do
		local deck = deckWrapper[deckName]
		deck.Size = UDim2.fromScale(0.35, 1)
		local mon = deck["Monitor" .. deckName]
		local cp1, cp2 = deck.ControlPad1, deck.ControlPad2
		local eq = cp1.EQWrapper
		cp2.Size = UDim2.fromScale(0.2, 1)
		cp1.Size = UDim2.fromScale(0.17, 1)
		mon.Size = UDim2.fromScale(0.63, 1)

		-- EQ: HIGH / MID / LOW in one row under the platter
		eq.Parent = mon
		eq.AnchorPoint = Vector2.new(0.5, 1)
		eq.Position = UDim2.new(0.5, 0, 1, -PAD)
		eq.Size = UDim2.new(1, -16, 0, ROW)
		local ep = eq:FindFirstChildOfClass("UIPadding")
		if ep then
			ep.PaddingTop = UDim.new()
			ep.PaddingBottom = UDim.new()
		end
		local el = eq:FindFirstChildOfClass("UIListLayout")
		el.FillDirection = Enum.FillDirection.Horizontal
		el.SortOrder = Enum.SortOrder.LayoutOrder
		el.HorizontalFlex = Enum.UIFlexAlignment.SpaceEvenly
		el.VerticalFlex = Enum.UIFlexAlignment.None
		el.HorizontalAlignment = Enum.HorizontalAlignment.Center
		el.VerticalAlignment = Enum.VerticalAlignment.Center
		el.Padding = UDim.new()
		for name, order in { High = 1, Mid = 2, Low = 3 } do
			local band = eq:FindFirstChild(name)
			band.LayoutOrder = order
			band.Size = UDim2.new(0.3, 0, 1, 0)
			local bl = band:FindFirstChildOfClass("UIListLayout")
			bl.Padding = UDim.new(0, 0)
			bl.VerticalAlignment = Enum.VerticalAlignment.Top
			band.Knob.Size = UDim2.fromOffset(43, 43)
			-- label under the knob, value under the label: the same stack as the FILTER column
			for _, c in band:GetChildren() do
				if c:IsA("TextLabel") then
					c.LayoutOrder = c.Name:find("Value") and 3 or 2
				end
			end
		end

		-- platter: top-anchored, as big as the space above the EQ row
		local jog = mon.Wrapper
		jog.AnchorPoint = Vector2.new(0.5, 0)
		jog.Position = UDim2.new(0.5, 0, 0, PAD)
		jog.Size = UDim2.new(1, -16, 1, -(PAD + ROW + GAP + PAD))

		-- filter column: FILTER label / knob / value, the volume fader fills the rest
		local w = cp1.Wrapper
		w.Size = UDim2.fromScale(1, 1)
		pad(w, PAD, PAD, 8, 8)
		local wl = w:FindFirstChildOfClass("UIListLayout")
		wl.Padding = UDim.new()
		wl.VerticalFlex = Enum.UIFlexAlignment.SpaceBetween
		wl.VerticalAlignment = Enum.VerticalAlignment.Top
		local fc = w.FilterChanger
		fc.Size = UDim2.new(1, 0, 0, FILTER_H)
		fc.LayoutOrder = 1
		local fl = fc:FindFirstChildOfClass("UIListLayout")
		fl.Padding = UDim.new(0, 2)
		fl.VerticalAlignment = Enum.VerticalAlignment.Top -- knob top lines up with the SYNC button's top
		for _, c in w:GetChildren() do
			if c:IsA("TextLabel") then
				c.Parent = fc -- the template's "100%" readout becomes the band's value line
			end
		end
		for _, c in fc:GetChildren() do
			if c:IsA("TextLabel") then
				c.LayoutOrder = c.Text == "FILTER" and 2 or 3 -- under the knob, above the value
				c.TextSize = c.Text == "FILTER" and FILTER_LABEL or FILTER_VALUE
			end
		end
		local fknob = fc:FindFirstChild("Knob", true)
		local holder = fknob.Parent == fc and fknob or fknob.Parent
		holder.LayoutOrder = 1
		holder.Size = UDim2.fromOffset(FILTER_KNOB, FILTER_KNOB)
		if holder ~= fknob then
			fknob.Size = UDim2.fromScale(1, 1)
		end
		local vol = w.TrackA_VolumeChanger
		vol.LayoutOrder = 2
		vol.Size = UDim2.new(1, 0, 0, SLIDER_H)

		-- sync / speed column: from the label line down to the EQ row bottom
		pad(cp2, PAD, PAD, 8, 8)
		local cl = cp2:FindFirstChildOfClass("UIListLayout")
		cl.VerticalAlignment = Enum.VerticalAlignment.Top
		cl.Padding = UDim.new(0, 8)
		local order = { ["SyncSpeedDeckA&B"] = 1, PlaybackSpeedValue = 2, Wrapper = 3, Frame = 4 }
		for _, c in cp2:GetChildren() do
			if c:IsA("GuiObject") and order[c.Name] then
				c.LayoutOrder = order[c.Name]
			end
		end
		cp2.Frame.Size = UDim2.new(1, 0, 0, SLIDER_H)
	end
end

-- ════════════════════════════════════════════════════════════
-- 6. Centre column, djay look (2026-10-10; the owner keeps it vertical): two scrolling lanes
--    with spectral colour (kick = red, hats = blue, mids = magenta), grey beat lines, pale bar
--    lines with bar numbers, a red playhead, per-deck VU, BPM tags
-- ════════════════════════════════════════════════════════════
do
	local wave = deckWrapper.Waveform
	for _, c in wave:GetChildren() do
		if c:IsA("GuiObject") then
			c.Visible = false
		end
	end
	local center = noTint(new("Frame", { Name = "DJX_Center", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.wave, BorderSizePixel = 0 }, wave))
	local TOP, BOTTOM = 26, 0 -- lanes run to the waveform's bottom edge (the phase meter strip is gone)
	local top = new("Frame", { Size = UDim2.new(1, 0, 0, TOP), BackgroundTransparency = 1 }, center)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, top)
	local function tag(deck, bpm, anchorX)
		local f = new("Frame", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(anchorX, 0), Position = UDim2.fromScale(anchorX, 0), BackgroundTransparency = 1 }, top)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = anchorX == 1 and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left }, f)
		-- neutral grey chip, 15 px (12 x1.25, owner: "gedein dikit secara proporsional"). The letter sits
		-- in its own label. Measured at 10x (scaled text, no pixel snapping) it is centred with no nudge,
		-- but at 1x the glyph snaps and lands about 1 px right, so the real label is nudged 1 px left.
		local chip = noTint(new("Frame", { Size = UDim2.fromOffset(15, 15), BackgroundColor3 = Color3.fromHex("3a3a3a"), BorderSizePixel = 0, LayoutOrder = anchorX == 1 and 2 or 1 }, f))
		new("UICorner", { CornerRadius = UDim.new(0, 4) }, chip)
		new("TextLabel", { Text = deck, FontFace = B, TextSize = 10, TextColor3 = W, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(-1, 0), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center }, chip)
		-- the BPM label fills the 26 px bar, so its text centres on the same line as the chip
		new("TextLabel", { Text = bpm, FontFace = B, TextSize = 12, TextColor3 = W, BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), TextYAlignment = Enum.TextYAlignment.Center, LayoutOrder = anchorX == 1 and 1 or 2 }, f)
	end
	tag("A", "124.0", 0)
	tag("B", "122.0", 1)
	local body = new("Frame", { Size = UDim2.new(1, -16, 1, -(TOP + BOTTOM)), Position = UDim2.fromOffset(8, TOP), BackgroundTransparency = 1 }, center)
	local VUW, LGAP = 5, 6
	local GW = VUW * 2 + 2 -- two meter columns a side, 2 px apart
	-- LED-style meter (owner, 2026-10-10: "model gini juga" = djay's segmented bar): 1 px bars with
	-- 1 px gaps, pixel-sized (not a share of the lane), so the count is tied to the 275 px lane height;
	-- lit from the bottom; green up to 60%, yellow to 85%, red above.
	-- The level carrier stays invisible and the section below still drives its height.
	local SEG_H, PITCH, SEGS = 1, 2, 138 -- 1 px bars, 1 px gaps: 138 x 2 px = the 275 px lane
	local DIM = Color3.fromHex("262626")
	local function vuMeter(xScale, xOff, anchor, level)
		local f = new("Frame", { Size = UDim2.new(0, VUW, 1, 0), AnchorPoint = Vector2.new(anchor, 0), Position = UDim2.new(xScale, xOff, 0, 0), BackgroundColor3 = C.lane, BorderSizePixel = 0 }, body)
		-- the outer column of a side owns the level carrier; the inner column reads the same one
		local lvl = level or noTint(new("Frame", { Size = UDim2.fromScale(1, 0), AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), BackgroundTransparency = 1, BorderSizePixel = 0 }, f))
		local box = noTint(new("Frame", { Name = "DJX_Segs", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = f.ZIndex + 1 }, f))
		local segs = {}
		for i = 1, SEGS do
			segs[i] = noTint(new("Frame", { Size = UDim2.new(1, 0, 0, SEG_H), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -(i - 1) * PITCH), BackgroundColor3 = DIM, BorderSizePixel = 0, ZIndex = f.ZIndex + 1 }, box))
		end
		local lit, conn = -1, nil
		conn = RunService.RenderStepped:Connect(function()
			if not box.Parent then
				conn:Disconnect()
				return
			end
			local n = math.floor(math.clamp(lvl.Size.Y.Scale, 0, 1) * SEGS + 0.5)
			if n == lit then
				return
			end
			lit = n
			for i, s in segs do
				local t = i / SEGS
				local col = t < 0.6 and Color3.fromRGB(70, 220, 120) or t < 0.85 and Color3.fromRGB(255, 210, 60) or Color3.fromRGB(255, 70, 70)
				s.BackgroundColor3 = i <= n and col or DIM
			end
		end)
		return lvl
	end
	local vuA = vuMeter(0, 0, 0)
	vuMeter(0, 7, 0, vuA)
	local vuB = vuMeter(1, 0, 1)
	vuMeter(1, -7, 1, vuB)
	local function lane(xScale, xOff)
		return noTint(new("Frame", { Size = UDim2.new(0.5, -(GW + 4 + LGAP / 2), 1, 0), Position = UDim2.new(xScale, xOff, 0, 0), BackgroundColor3 = C.lane, BorderSizePixel = 0, ClipsDescendants = true }, body))
	end
	local laneA, laneB = lane(0, GW + 4), lane(0.5, LGAP / 2)

	-- one strip = 16 beats = 4 bars; two copies scroll end to end
	local N, PER_BEAT, BEATS = 128, 8, 16
	local LOW, MIDC, HIGH = Color3.fromRGB(232, 36, 64), Color3.fromRGB(176, 52, 196), Color3.fromRGB(70, 92, 255)
	local BARLINE = Color3.fromRGB(214, 206, 140)
	local function rng(seed)
		local s = seed
		return function()
			s = (s * 1103515245 + 12345) % 2147483648
			return s / 2147483648
		end
	end
	local function build(l, seed, introRows)
		local strips, labels = {}, {}
		for copy = 0, 1 do
			local r = rng(seed + copy)
			local strip = new("Frame", { Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0, copy), BackgroundTransparency = 1 }, l)
			for i = 1, N do
				-- spiky, noisy rows like djay: kick body decays over ~2 rows, off-beat hats push
				-- the colour to blue, everything else drifts red -> magenta -> blue
				local b = (i - 1) % PER_BEAT
				local kick = math.exp(-b / 1.6)
				local hat = (b == 4 or b == 6) and 0.45 or 0
				local a = math.clamp(0.38 + kick * 0.6 + hat * 0.35 + (r() - 0.5) * 0.45, 0.12, 1)
				local bright = math.clamp(hat * 0.9 + (1 - kick) * 0.35 + (r() - 0.5) * 0.5, 0, 1)
				local col = bright < 0.5 and LOW:Lerp(MIDC, bright * 2) or MIDC:Lerp(HIGH, (bright - 0.5) * 2)
				if copy == 0 and i <= introRows then
					a, col = 0.015, HIGH -- silence before the first downbeat: a thin blue line
				end
				noTint(new("Frame", { Size = UDim2.new(a * 0.96, 0, 1 / N, 0), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, (i - 1) / N), BackgroundColor3 = col:Lerp(W, a > 0.92 and 0.35 or 0), BackgroundTransparency = 0.08 + (1 - a) * 0.2, BorderSizePixel = 0 }, strip))
			end
			local stripLabels = {}
			for beat = 0, BEATS - 1 do
				local isBar = beat % 4 == 0
				noTint(new("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromScale(0, beat / BEATS), BackgroundColor3 = isBar and BARLINE or W, BackgroundTransparency = isBar and 0.1 or 0.82, BorderSizePixel = 0, ZIndex = 2 }, strip))
				if isBar then
					table.insert(stripLabels, noTint(new("TextLabel", { Text = "", FontFace = SB, TextSize = 11, TextColor3 = BARLINE, BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new(), Position = UDim2.new(0, 3, beat / BEATS, 1), ZIndex = 3 }, strip)))
				end
			end
			strips[copy + 1] = strip
			labels[copy + 1] = stripLabels
		end
		return strips, labels
	end
	local function number(labels, firstBar)
		for copy, list in labels do
			for k, lbl in list do
				local n = firstBar + (copy - 1) * 4 + (k - 1)
				lbl.Text = n >= 1 and tostring(n) or ""
			end
		end
	end
	local stripsA, labelsA = build(laneA, 7, 0)
	local stripsB, labelsB = build(laneB, 42, N / 4) -- one bar of silence, then bar 1
	local barA = 97
	number(labelsA, barA)
	number(labelsB, 0)
	noTint(new("Frame", { Size = UDim2.new(1, 0, 0, 2), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.35), BackgroundColor3 = Color3.fromRGB(255, 40, 40), BorderSizePixel = 0, ZIndex = 5 }, body))

	local function loudest()
		local best, bl = nil, -1
		for _, s in SoundService:GetDescendants() do
			if s:IsA("Sound") and s.IsPlaying and s.TimeLength > 30 and s.PlaybackLoudness > bl then
				best, bl = s, s.PlaybackLoudness
			end
		end
		return best
	end
	local music, lastScan = loudest(), os.clock()
	local posA, posB, lvA, lvB = 0, -0.1, 0, 0 -- B is cued: bar 1 sits on the playhead (35%)
	RunService.RenderStepped:Connect(function(dt)
		if os.clock() - lastScan > 3 then
			lastScan = os.clock()
			music = loudest()
		end
		local lv = math.clamp((music and music.PlaybackLoudness or 0) / 500, 0, 1)
		local nextA = posA + dt * (124 / 60) / BEATS
		if nextA >= 1 then
			barA += 4
			number(labelsA, barA)
		end
		posA = nextA % 1
		for i, s in stripsA do
			s.Position = UDim2.fromScale(0, (i - 1) - posA)
		end
		for i, s in stripsB do
			s.Position = UDim2.fromScale(0, (i - 1) - posB)
		end
		lvA = math.max(lv * (0.85 + math.random() * 0.3), lvA - dt * 1.6)
		lvB = math.max(0.05, lvB - dt * 1.6)
		vuA.Size = UDim2.fromScale(1, math.clamp(lvA, 0, 1))
		vuB.Size = UDim2.fromScale(1, math.clamp(lvB, 0, 1))
	end)
end

-- ════════════════════════════════════════════════════════════
-- 7. Fader caps: matte, white indicator line, faint grip grooves
-- ════════════════════════════════════════════════════════════
do
	local MATTE = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(58, 58, 64)), ColorSequenceKeypoint.new(1, Color3.fromRGB(42, 42, 47)) })
	for _, h in root:GetDescendants() do
		if h:IsA("GuiObject") and h.BackgroundColor3:ToHex() == "ababab" and h.BackgroundTransparency < 0.5 then
			for _, c in h:GetChildren() do
				if c:IsA("UIStroke") or c:IsA("UIGradient") or c:IsA("UICorner") then
					c:Destroy()
				end
			end
			if h:IsA("ImageButton") or h:IsA("ImageLabel") then
				h.ImageTransparency = 1
			end
			noTint(h)
			local horizontal = h.AbsoluteSize.X >= h.AbsoluteSize.Y
			local o = h.Size
			h.Size = horizontal and UDim2.new(o.X.Scale, o.X.Offset + 4, o.Y.Scale, o.Y.Offset + 8) or UDim2.new(o.X.Scale, o.X.Offset + 6, o.Y.Scale, o.Y.Offset + 4)
			h.BackgroundColor3 = W
			h.BackgroundTransparency = 0
			h.BorderSizePixel = 0
			new("UICorner", { CornerRadius = UDim.new(0, 3) }, h)
			new("UIGradient", { Rotation = 90, Color = MATTE }, h)
			new("UIStroke", { Color = Color3.fromRGB(10, 10, 12), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, h)
			local cap = new("Frame", { Name = "DJX_Cap", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = h.ZIndex + 1 }, h)
			local function line(pos, thick, color, trans, inset)
				local f = horizontal
					and new("Frame", { Size = UDim2.new(1, -inset, 0, thick), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, pos), BackgroundColor3 = color, BackgroundTransparency = trans, BorderSizePixel = 0, ZIndex = h.ZIndex + 1 }, cap)
					or new("Frame", { Size = UDim2.new(0, thick, 1, -inset), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(pos, 0.5), BackgroundColor3 = color, BackgroundTransparency = trans, BorderSizePixel = 0, ZIndex = h.ZIndex + 1 }, cap)
				return noTint(f)
			end
			for _, p in { 0.22, 0.78 } do
				line(p, 1, Color3.new(0, 0, 0), 0.7, 6)
			end
			local ind = line(0.5, 2, W, 0.05, 4)
			new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Transparency = 0.7 }, ind)
		end
	end
end

-- ════════════════════════════════════════════════════════════
-- 8. Knobs: bipolar filter (OFF in the middle, LPF left, HPF right); disc and pointer only
-- ════════════════════════════════════════════════════════════
-- A knob's Rotation only reaches its disc and pointer when the knob sits in a plain wrapper.
-- Directly under a UIListLayout the rotation is ignored (AbsoluteRotation stays 0), which is why
-- those knobs spun only their ring. The FILTER knob's KnobWrapper is the working case, so every
-- knob that sits under a layout gets the same wrapper. The owner's controller keeps its reference
-- to the Knob (it wires after the first frame, before the wait above), so moving it here is safe.
local function wrapKnob(knob: GuiObject, size: number)
	local holder = new("Frame", { Name = "KnobWrapper", Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, LayoutOrder = knob.LayoutOrder }, knob.Parent)
	knob.Parent = holder
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.Size = UDim2.fromScale(1, 1)
end
for _, deckName in { "Deck_A", "Deck_B" } do
	local mon = deckWrapper[deckName]["Monitor" .. deckName]
	for _, bandName in { "High", "Mid", "Low" } do
		wrapKnob(mon.EQWrapper[bandName].Knob, 56) -- same 56 px as the FILTER knob, so the row balances
	end
end
-- Deck A's FILTER already has its KnobWrapper from section 5; Deck B's sits straight under the layout
local fcB = deckWrapper.Deck_B.ControlPad1.Wrapper.FilterChanger
local fknobB = fcB:FindFirstChild("Knob", true)
if fknobB and fknobB.Parent == fcB then
	wrapKnob(fknobB, 56)
end

local function filterKnobs()
	for _, deckName in { "Deck_A", "Deck_B" } do
		local fc = deckWrapper[deckName].ControlPad1.Wrapper.FilterChanger
		local knob = fc:FindFirstChild("Knob", true)
		local label
		for _, d in fc:GetDescendants() do
			if d:IsA("TextLabel") and d.Text ~= "FILTER" then
				label = d
			end
		end
		local v, raw, dragging, lastY, lastClick = 0.5, 0.5, false, 0, 0
		local function apply()
			knob.Rotation = (v - 0.5) * 270
			if label then
				local amt = math.floor(math.abs(v - 0.5) / 0.5 * 100 + 0.5)
				label.Text = amt == 0 and "OFF" or ((v < 0.5 and "LPF " or "HPF ") .. amt .. "%")
				label.TextColor3 = amt == 0 and W or (v < 0.5 and Color3.fromRGB(110, 170, 255) or Color3.fromRGB(255, 150, 80))
				noTint(label)
			end
		end
		knob.InputBegan:Connect(function(i)
			if isPress(i) then
				if os.clock() - lastClick < 0.3 then
					v, raw = 0.5, 0.5
					apply()
				end
				lastClick = os.clock()
				dragging = true
				lastY = i.Position.Y
			end
		end)
		UserInputService.InputChanged:Connect(function(i)
			if dragging and isMove(i) then
				raw = math.clamp(raw + (lastY - i.Position.Y) * 0.005, 0, 1)
				lastY = i.Position.Y
				v = math.abs(raw - 0.5) < 0.04 and 0.5 or raw
				apply()
			end
		end)
		UserInputService.InputEnded:Connect(function(i)
			if isPress(i) then
				dragging = false
			end
		end)
		apply()
	end
end
filterKnobs()

for _, k in root:GetDescendants() do
	if k:IsA("ImageButton") and k.Name == "Knob" then
		k.BackgroundTransparency = 1
		k.ImageTransparency = 1
		local st = k:FindFirstChildOfClass("UIStroke")
		if st then
			st.Transparency = 1
		end
		local disc = noTint(new("Frame", { Name = "DJX_Disc", Size = UDim2.fromScale(0.66, 0.66), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(28, 28, 32), BorderSizePixel = 0, ZIndex = k.ZIndex + 1 }, k))
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, disc)
		new("UIStroke", { Color = Color3.fromRGB(10, 10, 12), Thickness = 1 }, disc)
		local pointer = noTint(new("Frame", { Name = "DJX_Pointer", Size = UDim2.new(0, 2, 0.42, 0), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = W, BorderSizePixel = 0, ZIndex = k.ZIndex + 2 }, disc))
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, pointer)
		-- thin continuous 1 px ring around the knob. It sits beside the knob in its wrapper, not inside
		-- it, so it never turns with the knob
		local ring = noTint(new("Frame", { Name = "DJX_Ring", Size = UDim2.fromScale(0.92, 0.92), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = k.ZIndex + 1 }, k.Parent))
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
		new("UIStroke", { Color = Color3.fromRGB(58, 58, 64), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ring)
	end
end

-- ════════════════════════════════════════════════════════════
-- 9. Jog wheels: drag around the platter ring to scratch (visual)
-- ════════════════════════════════════════════════════════════
local jogScratch = { Deck_A = 0, Deck_B = 0 } -- degrees scratched since section 13 last read it
for _, deckName in { "Deck_A", "Deck_B" } do
	local hit = deckWrapper[deckName]["Monitor" .. deckName].Wrapper
	local rotating = hit:FindFirstChild("RotatingThings")
	if rotating then
		local scratching, lastA = false, 0
		local function angleAt(pos)
			local c = hit.AbsolutePosition + hit.AbsoluteSize / 2
			return math.deg(math.atan2(pos.Y - c.Y, pos.X - c.X))
		end
		hit.InputBegan:Connect(function(i)
			if isPress(i) then
				local c = hit.AbsolutePosition + hit.AbsoluteSize / 2
				if (Vector2.new(i.Position.X, i.Position.Y) - c).Magnitude > hit.AbsoluteSize.X * 0.28 then
					scratching = true
					lastA = angleAt(i.Position)
				end
			end
		end)
		UserInputService.InputChanged:Connect(function(i)
			if scratching and isMove(i) then
				local a = angleAt(i.Position)
				local step = (a - lastA + 540) % 360 - 180
				rotating.Rotation = (rotating.Rotation + step) % 360
				jogScratch[deckName] += step
				lastA = a
			end
		end)
		UserInputService.InputEnded:Connect(function(i)
			if isPress(i) then
				scratching = false
			end
		end)
	end
end

-- ════════════════════════════════════════════════════════════
-- 10. djay-style surface: neutral grey tiles on a black gutter, small corners, no borders,
--     no accent tint. ONE line weight (G = 2 px) everywhere, and every tile sized in whole
--     pixels: Scale widths (0.35 x 1250 = 437.5) put edges on half pixels and the same gutter
--     rendered 1, 2 or 3 px wide (owner, 2026-10-10: "ada yang tebel ada yang tipis ada yang double").
--     Column grid: 436 | 374 | 436; mixer row 217 217 | 374 | 217 217; pads 4 x 311;
--     library 311 | 937. The panel height must stay even, or centring puts it on a half pixel.
-- ════════════════════════════════════════════════════════════
do
	local G, SIDE, MID, ROWH = 2, 436, 374, 56
	noTint(root) -- needs AccentNoTint on StarterGui.DJGUI too: the tint judges an instance once, at first sight
	local function corner(o, r)
		local c = o:FindFirstChildOfClass("UICorner")
		if r == 0 then
			if c then
				c:Destroy()
			end
			return
		end
		c = c or new("UICorner", {}, o)
		c.CornerRadius = UDim.new(0, r)
	end
	local function unstroke(o)
		for _, c in o:GetChildren() do
			if c:IsA("UIStroke") then
				c:Destroy()
			end
		end
	end
	local function tile(o, color)
		o.BackgroundColor3 = color or C.bg
		o.BackgroundTransparency = 0
		o.BorderSizePixel = 0
		unstroke(o)
	end
	local function clear(o)
		o.BackgroundTransparency = 1
		unstroke(o)
	end
	local function gap(o)
		local l = o:FindFirstChildOfClass("UIListLayout")
		l.Padding = UDim.new(0, G)
		return l
	end
	local function byOrder(f)
		local t = {}
		for _, c in f:GetChildren() do
			if c:IsA("GuiObject") and c.Visible then
				table.insert(t, c)
			end
		end
		table.sort(t, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		return t
	end

	-- window
	root.BackgroundColor3 = C.gutter
	root.BackgroundTransparency = 0
	corner(root, 6)
	local rs = root:FindFirstChildOfClass("UIStroke")
	if rs then
		rs.Color = Color3.new(0, 0, 0)
	end
	gap(root)

	-- header
	local header = root.DJX_Header
	tile(header)
	for _, c in header:GetChildren() do
		if c:IsA("Frame") and c.AbsoluteSize.Y <= 1 then
			c:Destroy() -- hairline: the gutter separates now
		end
	end
	for _, d in header:GetDescendants() do
		if d:IsA("TextButton") then
			corner(d, 4)
			d.BackgroundColor3 = d.Text == "DROP" and C.accent or C.card2
			noTint(d)
		elseif d:IsA("Frame") and d.BackgroundColor3:ToHex() == "e41024" then
			corner(d, 3) -- ON AIR
		end
	end

	-- deck block: track strip / decks + waveform / transport / mixer row
	local deck = root.DJ_Deck
	clear(deck)
	gap(deck)
	local top, bottom = deck.EffectWrapperTop, deck.EffectWrapperBottom
	top.Size = UDim2.new(1, 0, 0, ROWH)
	bottom.Size = UDim2.new(1, 0, 0, ROWH)
	deck.Size = UDim2.new(1, 0, 0, 88 + ROWH * 2 + 301 + G * 3)
	local ct = deck.CurrentTrack
	clear(ct)
	gap(ct)
	ct.Separator.Visible = false
	for _, t in { ct.Track_A, ct.Track_B } do
		tile(t)
		t.Size = UDim2.new(0, (1250 - G) / 2, 1, 0)
	end
	clear(deckWrapper)
	gap(deckWrapper)
	for _, n in { "Deck_A", "Deck_B" } do
		tile(deckWrapper[n])
		deckWrapper[n].Size = UDim2.new(0, SIDE, 1, 0)
	end
	tile(deckWrapper.Waveform)
	deckWrapper.Waveform.Size = UDim2.new(0, MID, 1, 0)
	for _, row in { top, bottom } do
		clear(row)
		gap(row)
	end
	for _, f in { top.Left, top.Right, top.CrosfaderAtoB } do
		tile(f)
		f.Size = UDim2.new(0, f == top.CrosfaderAtoB and MID or SIDE, 1, 0)
	end
	bottom:FindFirstChildOfClass("UIListLayout").HorizontalFlex = Enum.UIFlexAlignment.None
	for i, f in byOrder(bottom) do
		tile(f)
		f.Size = UDim2.new(0, i == 3 and MID or (SIDE - G) / 2, 1, 0)
	end
	for _, d in deck:GetDescendants() do
		if d:IsA("TextButton") and d.BackgroundTransparency < 0.5 and not d:IsDescendantOf(top) then
			d.BackgroundColor3 = C.card2
			unstroke(d)
			corner(d, 4)
		end
	end
	-- speed readout: just the number, no box behind it (the section above gave it card2)
		for _, deckName in { "Deck_A", "Deck_B" } do
			deck.DeckWrapper[deckName].ControlPad2.PlaybackSpeedValue.BackgroundTransparency = 1
		end
		-- transport: the owner's own play / hot-cue look (2026-10-10, picked over every restyle):
	-- 1b1b1b fill, 060606 1.5 px rim, hot cues one capsule whose dividers are the 1 px black
	-- strokes on buttons 2 and 4. Only the corners changed (8 -> 4, "agak kotakin") and the
	-- sizes snap to whole pixels (cues 5 x 60).
	local CUE_FILL, CUE_RIM = Color3.fromHex("1b1b1b"), Color3.fromHex("060606")
	local function rim(o, color, th)
		unstroke(o)
		new("UIStroke", { Color = color, Thickness = th, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
	end
	for _, side in { top.Left, top.Right } do
		local w = side.Wrapper
		local p = w:FindFirstChildOfClass("UIPadding")
		p.PaddingTop = UDim.new(0, 8)
		p.PaddingBottom = UDim.new(0, 8)
		for _, c in w:GetChildren() do
			local ar = c:IsA("TextButton") and c:FindFirstChildOfClass("UIAspectRatioConstraint")
			if ar then
				ar.AspectRatio = 78 / 40
				c.BackgroundColor3 = CUE_FILL
				rim(c, CUE_RIM, 1.5)
				corner(c, 4)
			elseif c:IsA("CanvasGroup") and c.Name == "HotCue" then
				rim(c, CUE_RIM, 1.5)
				corner(c, 4)
				c.Size = UDim2.fromOffset(300, 40)
				for _, b in c:GetChildren() do
					if b:IsA("TextButton") then
						b.Size = UDim2.new(0, 60, 1, 0)
						b.BackgroundColor3 = CUE_FILL
						corner(b, 0)
						if b.Name == "2" or b.Name == "4" then
							rim(b, Color3.new(0, 0, 0), 1)
						end
					end
				end
			end
		end
	end
	top.CrosfaderAtoB.Wrapper.Size = UDim2.fromOffset(358, 40) -- runs from the outer edge of the left VU meter to the outer edge of the right one (LCD box less its 8 px body inset)

		-- crossfader ticks: 12 evenly spaced (the template has 8)
		do
			local cfTicks = top.CrosfaderAtoB.Wrapper.Frame
			local proto, have = nil, 0
			for _, c in cfTicks:GetChildren() do
				if c:IsA("Frame") and c.Size.X.Offset == 3 then
					proto = proto or c
					have += 1
				end
			end
			for _ = have + 1, 12 do
				proto:Clone().Parent = cfTicks
			end
		end

		-- SYNC gets the play button's look: 1b1b1b fill, 060606 1.5 px rim. The owner's controller
		-- captured the old fill as its "off" colour, so a switch back to that fill is undone here
		for _, deckName in { "Deck_A", "Deck_B" } do
			local sync = deck.DeckWrapper[deckName].ControlPad2["SyncSpeedDeckA&B"]
			sync.BackgroundColor3 = CUE_FILL
			rim(sync, CUE_RIM, 1.5)
			sync:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
				if sync.BackgroundColor3 == C.card2 then
					sync.BackgroundColor3 = CUE_FILL
				end
			end)
		end

	-- effect pads: flat cells, 4 x 311 with the same gutter both ways
	local pads = root.DJ_SoundAndGlobalEffects
	clear(pads)
	gap(pads)
	pads.Size = UDim2.new(1, 0, 0, 40 * 2 + G)
	for _, row in { pads.Top, pads.Bottom } do
		gap(row).HorizontalFlex = Enum.UIFlexAlignment.None
		row.Size = UDim2.new(1, 0, 0, 40)
		for _, b in row:GetChildren() do
			if b:IsA("TextButton") then
				tile(b, C.card)
				corner(b, 0)
				b.AutoButtonColor = true
				b.Size = UDim2.new(0, (1250 - G * 3) / 4, 1, 0)
			end
		end
	end

	-- library: source column under the first pad gutter, track list to the right edge
	local lib = root.DJ_Library
	clear(lib)
	lib.Size = UDim2.new(1, 0, 0, 261) -- keeps the panel height even (908)
	local sp, ss = lib["1-SelectPlaylist"], lib["2-SelectSong"]
	tile(sp)
	tile(ss)
	sp.Size = UDim2.new(0, 311, 1, 0)
	ss.Size = UDim2.new(0, 1250 - 311 - G, 1, 0)
	ss.Position = UDim2.new(1, 0, 0, 0) -- right-anchored in the template; no list layout here
	clear(ss.TrackList)
	local search = sp["01-SearchSong"]
	tile(search, C.inset)
	corner(search, 4)
end

-- 11. Font: every text in the panel is Inter (owner, 2026-10-10). The template mixes SourceSansPro
--     and two other families; keep each label's weight, swap only the family. Runs last so the
--     labels built above are covered too.
do
	local INTER = "rbxassetid://12187365364"
	for _, d in gui:GetDescendants() do
		if (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) and not string.find(d.FontFace.Family, "12187365364", 1, true) then
			local ff = d.FontFace
			d.FontFace = Font.new(INTER, ff.Weight, ff.Style)
		end
	end
end

-- ════════════════════════════════════════════════════════════
-- 12. Library from the real music store (read-only): playlists and tracks come from the kit's
--     MusicPlayerStore. They appear once the real music panel's Request tab has loaded them; until
--     then the mock rows stay. Requests and Queue are still mock.
-- ════════════════════════════════════════════════════════════
do
	local okStore, store = pcall(function()
		local K = player:WaitForChild("PlayerScripts", 5):WaitForChild("Hazastudio_ClubKit", 5)
		return require(K:WaitForChild("Client", 5):WaitForChild("State", 5):WaitForChild("MusicPlayerStore", 5))
	end)
	if okStore and store then
		local rowsScroll = root.DJ_Library["2-SelectSong"].TrackList.ScrollableTrackList
		local rowProto = rowsScroll.TrackWrapperTemplate
		local list = root.DJ_Library["1-SelectPlaylist"].ScrollablePlaylistWrapper.ScrollablePlaylist
		local protoNormal = list.PlaylistTemplateNormal:Clone()
		local protoSelected = list.PlaylistTemplateSelected:Clone()
		local protoAll = list.AllTracks:Clone()
		local selectedId = nil -- nil = All Tracks
		local mocksGone = false

		local function fmt(sec)
			sec = math.floor(sec or 0)
			return string.format("%d:%02d", sec // 60, sec % 60)
		end
		local function hasData()
			return next(store:get().allTracks or {}) ~= nil or next(store:get().playlists or {}) ~= nil
		end
		local function sortedPlaylists()
			local out = {}
			for _, p in (store:get().playlists or {}) do
				table.insert(out, p)
			end
			table.sort(out, function(a, b)
				return a.name < b.name
			end)
			return out
		end
		local function visibleTracks()
			local all = store:get().allTracks or {}
			local out = {}
			if selectedId == nil then
				for _, t in all do
					table.insert(out, t)
				end
			else
				local pl = (store:get().playlists or {})[selectedId]
				for _, id in ((pl and pl.trackIds) or {}) do
					if all[id] then
						table.insert(out, all[id])
					end
				end
			end
			table.sort(out, function(a, b)
				return a.name < b.name
			end)
			return out
		end

		local renderTracks -- declared first: the playlist click handler calls it
		local function renderPlaylists()
			for _, c in list:GetChildren() do
				if c.Name == "RealPlaylistRow" then
					c:Destroy()
				end
			end
			local order = 0
			local function addRow(proto, id, name, count)
				order += 1
				local row = proto:Clone()
				row.Name = "RealPlaylistRow"
				row.LayoutOrder = order
				row.PlaylistInformation.PlaylistName.Text = name
				row.PlaylistInformation.TotalTrack.Text = count .. " Tracks"
				row.PlaylistCover.PlaylistName.Text = name
				row.MouseButton1Click:Connect(function()
					selectedId = id
					renderPlaylists()
					renderTracks()
				end)
				row.Parent = list
			end
			local allCount = 0
			for _ in (store:get().allTracks or {}) do
				allCount += 1
			end
			addRow(selectedId == nil and protoSelected or protoAll, nil, "All Tracks", allCount)
			for _, p in sortedPlaylists() do
				addRow(selectedId == p.id and protoSelected or protoNormal, p.id, p.name, #p.trackIds)
			end
		end

		function renderTracks()
			for _, c in rowsScroll:GetChildren() do
				if c.Name == "RealTrackRow" then
					c:Destroy()
				end
			end
			for i, t in visibleTracks() do
				local row = rowProto:Clone()
				row.Name = "RealTrackRow"
				row.LayoutOrder = i
				row.Visible = true
				local info = row.TrackInformationWrapper.TrackInformation
				local leftD, rightD
				for _, d in info:GetChildren() do
					if d.Name == "TrackDetails" then
						if d:FindFirstChild("TrackTitle") then
							leftD = d
						else
							rightD = d
						end
					end
				end
				row.RelatedPlaylistCover.PlaylistName.Text = ""
				leftD.TrackTitle.Text = t.name
				leftD.TrackCreator.Text = t.creator
				rightD.TrackBPM.Visible = false
				rightD.TrackLength.Visible = true
				rightD.TrackLength.Text = fmt(t.totalDuration)
				row.Parent = rowsScroll
			end
		end

		local function refresh()
			if not hasData() then
				return
			end
			if not mocksGone then
				mocksGone = true
				for _, c in list:GetChildren() do
					if c:IsA("TextButton") then
						c:Destroy()
					end
				end
				rowProto.Visible = false
			end
			renderPlaylists()
			renderTracks()
		end

		store:subscribe("playlists", refresh)
		store:subscribe("allTracks", refresh)
		refresh()
	end
end

-- ════════════════════════════════════════════════════════════
-- 13. Drag a library row onto Deck A / B (owner, 2026-10-11): hold a row, drag it over a deck
--     (the deck tile or its track tile); the deck gets a green outline while hovered, and on
--     release the track is loaded and plays there for real (2026-10-11): one local Sound per
--     deck, gain = channel fader x crossfader curve, speed = track tempo x deck speed readout.
--     Client-only (the DJ's own monitor); nothing is sent to the server. The deck's play button
--     pauses / resumes it; elapsed / remaining and the progress bar follow the Sound.
-- ════════════════════════════════════════════════════════════
do
	local UIS = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local GuiService = game:GetService("GuiService")
	local TweenService = game:GetService("TweenService")
	local gui = root:FindFirstAncestorOfClass("ScreenGui")
	local okStore, store = pcall(function()
		local K = player:WaitForChild("PlayerScripts", 5):WaitForChild("Hazastudio_ClubKit", 5)
		return require(K:WaitForChild("Client", 5):WaitForChild("State", 5):WaitForChild("MusicPlayerStore", 5))
	end)
	if okStore and store and gui then
		local rowsScroll = root.DJ_Library["2-SelectSong"].TrackList.ScrollableTrackList
		local GREEN = Color3.fromHex("2ee66b")
		local LETTERS = { "A", "B" }

		local function zoneOf(letter)
			return { deckRoot.DeckWrapper["Deck_" .. letter], deckRoot.CurrentTrack["Track_" .. letter] }
		end
		local function setOutline(letter, on)
			for _, f in zoneOf(letter) do
				local s = f:FindFirstChild("DropOutline")
				if not s and on then
					s = Instance.new("UIStroke")
					s.Name = "DropOutline"
					s.Color = GREEN
					s.Thickness = 3
					s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					s.Parent = f
				end
				if s then
					s.Enabled = on
				end
			end
		end
		local function inside(o, p)
			local a, s = o.AbsolutePosition, o.AbsoluteSize
			return p.X >= a.X and p.X < a.X + s.X and p.Y >= a.Y and p.Y < a.Y + s.Y
		end
		local function deckAt(p)
			for _, letter in LETTERS do
				for _, f in zoneOf(letter) do
					if inside(f, p) then
						return letter
					end
				end
			end
			return nil
		end
		local function guiPos(input)
			local v = Vector2.new(input.Position.X, input.Position.Y)
			return if gui.IgnoreGuiInset then v + GuiService:GetGuiInset() else v
		end
		local function trackOf(row)
			local all = store:get().allTracks or {}
			local id = row:GetAttribute("TrackId")
			if id and all[id] then
				return all[id]
			end
			local title = row:FindFirstChild("TrackTitle", true)
			if title then
				for _, t in all do
					if t.name == title.Text then
						return t
					end
				end
			end
			return nil
		end

		-- deck clocks. The template's label names are crossed and differ between Track_A and
		-- Track_B, so labels are found by position: wrapper.TrackDetails (order 1 / 2) = title /
		-- creator, wrapper.TrackInformationWrapper.TrackDetails (order 1 / 2) = remaining / elapsed.
		local function labelsOf(letter)
			local w = deckRoot.CurrentTrack["Track_" .. letter]:FindFirstChildWhichIsA("TextButton")
			local out = {}
			for key, holder in { name = w.TrackDetails, time = w.TrackInformationWrapper.TrackDetails } do
				local a, b
				for _, l in holder:GetChildren() do
					if l:IsA("TextLabel") then
						if l.LayoutOrder == 1 then a = l else b = l end
					end
				end
				out[key] = { a, b }
			end
			return out
		end
		local function mmss(sec, neg)
			sec = math.max(sec, 0)
			return string.format("%s%02d:%02d.%02d", neg and "-" or "", sec // 60, sec % 60, math.floor((sec % 1) * 100))
		end
		local decks = {}
		local function paint(letter)
			local d = decks[letter]
			local tr = deckRoot.CurrentTrack["Track_" .. letter]
			local L = d.labels
			L.name[1].Text = d.t.name
			L.name[2].Text = d.t.creator
			L.time[1].Text = mmss(d.dur - d.pos, true)
			L.time[2].Text = mmss(d.pos)
			local bar = d.bar
			bar.Size = UDim2.new(d.pos / d.dur, 0, bar.Size.Y.Scale, bar.Size.Y.Offset)
			-- jog wheel read-out: remaining % / playback rate / elapsed / remaining
			local M = d.mon
			M.pct.Text = string.format("-%.1f%%", (1 - d.pos / d.dur) * 100)
			-- the track's own tempo counts as 1.00X (as in the music panel); only the deck's speed shows
			M.rate.Text = string.format("%.2fX", d.speed or 1)
			M.elapsed.Text = string.format("%02d:%04.1f", d.pos // 60, d.pos % 60)
			local left = math.max(d.dur - d.pos, 0)
			M.left.Text = string.format("-%02d:%04.1f", left // 60, left % 60)
		end
		-- Real audio, local to this client (the DJ's own monitor; nothing is sent to the server).
		-- One Sound per deck plays the track's parts in order at track.playbackSpeed x the deck's
		-- speed readout. Gain per frame = channel fader x crossfader curve (equal power: A = cos,
		-- B = sin of v * pi/2, v = 0 left / 1 right), read from the panel's own controls.
		local ORANGE = Color3.fromRGB(230, 140, 40) -- AdvancedDJController's "playing" colour
		local function deckControls(letter)
			local dw = deckRoot.DeckWrapper["Deck_" .. letter]
			local top = deckRoot.EffectWrapperTop
			local btn = top.Left.Wrapper:FindFirstChild("PlayandPauseDeck" .. letter)
				or top.Right.Wrapper:FindFirstChild("PlayandPauseDeck" .. letter)
			return {
				fader = dw.ControlPad1.Wrapper.TrackA_VolumeChanger.DragThisToAdjustVolume,
				speed = dw.ControlPad2.PlaybackSpeedValue,
				btn = btn,
				btnBase = btn and btn.BackgroundColor3,
				hot = btn and btn.Parent:FindFirstChild("HotCue"),
			}
		end
		local cfHandle = deckRoot.EffectWrapperTop.CrosfaderAtoB.Wrapper.DraggableHandle
		local function crossValue()
			local span = (cfHandle.Parent.AbsoluteSize.X - cfHandle.AbsoluteSize.X) / math.max(cfHandle.Parent.AbsoluteSize.X, 1)
			return math.clamp(cfHandle.Position.X.Scale / math.max(span, 0.0001), 0, 1)
		end
		-- EQ: the knobs are the owner's (AdvancedDJController turns them and writes Knob.Rotation =
		-- -135 + v * 270, v 0..1, 0.5 = flat). Here v becomes dB the way a mixer's EQ is read:
		-- centre = 0 dB, up to +6 dB at full, down to a kill (-inf) at the bottom, with the usual
		-- -12 dB at a quarter turn. The read-out under each knob is rewritten in dB, and each deck's
		-- Sound carries one EqualizerSoundEffect (low / mid / high gain).
		local EQ_BANDS = { "High", "Mid", "Low" }
		local function eqDb(v)
			if v <= 0.005 then
				return -80
			elseif v <= 0.5 then
				return 20 * math.log10((v / 0.5) ^ 2)
			end
			return 6 * (v - 0.5) / 0.5
		end
		local function eqText(db)
			if db <= -60 then
				return "-∞ dB"
			elseif math.abs(db) < 0.05 then
				return "0 dB"
			elseif math.abs(db) < 10 then
				return string.format("%+.1f dB", db)
			end
			return string.format("%+.0f dB", db)
		end
		local eqUi = {}
		for _, letter in LETTERS do
			local wrap = deckRoot.DeckWrapper["Deck_" .. letter]["MonitorDeck_" .. letter].EQWrapper
			eqUi[letter] = {}
			for _, band in EQ_BANDS do
				eqUi[letter][band] = { knob = wrap[band]:FindFirstChild("Knob", true), label = wrap[band][band .. "Value"], db = 0 }
			end
		end
		-- FILTER knob (section 8 turns it: Rotation = (v - 0.5) * 270, 0.5 = off, below = LPF, above =
		-- HPF). Roblox has no filter effect, so it is built from a second EqualizerSoundEffect in
		-- series with the EQ: LPF cuts High (and Mid from 60 % up), HPF cuts Low (same). The cut grows
		-- as amount^1.5 to -80 dB. Coarse on purpose: the three bands have the engine's fixed edges.
		local filterKnobs = {}
		for _, letter in LETTERS do
			filterKnobs[letter] = deckRoot.DeckWrapper["Deck_" .. letter].ControlPad1.Wrapper.FilterChanger:FindFirstChild("Knob", true)
		end
		local function filterGains(v)
			local amount = math.abs(v - 0.5) / 0.5
			local cut = -80 * amount ^ 1.5
			local midCut = -80 * math.max(0, (amount - 0.6) / 0.4) ^ 1.5
			if v < 0.5 then
				return 0, midCut, cut -- low, mid, high: LPF
			end
			return cut, midCut, 0 -- HPF
		end
		local function partDur(d, i)
			return d.t.partDurations and tonumber(d.t.partDurations[i]) or 0
		end
		local function startPart(d, letter, i)
			if d.sound then
				d.sound:Destroy()
			end
			local id = d.t.parts[i]
			if type(id) == "table" then
				id = id.assetId or id.id
			end
			local snd = Instance.new("Sound")
			snd.Name = "DJXDeck" .. letter
			snd.SoundId = "rbxassetid://" .. tostring(id)
			snd.Looped = false
			snd.Volume = 0
			local fx = Instance.new("EqualizerSoundEffect")
			fx.Name = "DJXEq"
			fx.Parent = snd
			local ff = Instance.new("EqualizerSoundEffect")
			ff.Name = "DJXFilter"
			ff.Parent = snd
			snd.Parent = gui
			snd.Ended:Connect(function()
				if decks[letter] ~= d or d.sound ~= snd then
					return
				end
				if d.t.parts[i + 1] then
					d.offset += snd.TimeLength
					d.partIndex = i + 1
					startPart(d, letter, i + 1)
				else
					d.playing = false
					d.finished = true
				end
			end)
			d.sound = snd
			d.soundPlaying = false
			d.partStart[i] = d.offset
			d.started = false
		end
		-- Hot cues 1-5 (the pads in each deck's transport row): tap an empty pad to store the current
		-- position, tap a lit pad to jump there, right-click a lit pad to clear it. Cues are kept per
		-- track for this session, so reloading a track brings its pads back.
		local CUE_COLORS = {
			Color3.fromHex("e5484d"),
			Color3.fromHex("f5a524"),
			Color3.fromHex("a3d32e"),
			Color3.fromHex("3b9eff"),
			Color3.fromHex("a855f7"),
		}
		local cuesByTrack = {}
		local padBase = {} -- [pad] = { bg, text }
		local function refreshPads(letter)
			local d = decks[letter]
			local hot = d.ctl.hot
			for i = 1, 5 do
				local pad = hot and hot:FindFirstChild(tostring(i))
				if pad then
					padBase[pad] = padBase[pad] or { pad.BackgroundColor3, pad.TextColor3 }
					if d.cues[i] then
						pad.BackgroundColor3 = CUE_COLORS[i]:Lerp(padBase[pad][1], 0.55)
						pad.TextColor3 = Color3.new(1, 1, 1)
					else
						pad.BackgroundColor3, pad.TextColor3 = padBase[pad][1], padBase[pad][2]
					end
				end
			end
		end
		local function jumpToCue(letter, d, cue)
			if cue.part == d.partIndex and d.sound then
				d.sound.TimePosition = cue.t
			else
				d.partIndex = cue.part
				d.offset = d.partStart[cue.part]
				if not d.offset then
					d.offset = 0
					for k = 1, cue.part - 1 do
						d.offset += partDur(d, k)
					end
				end
				d.pendingSeek = cue.t
				startPart(d, letter, cue.part)
			end
			if d.finished then
				-- the track had ended: a cue starts it again from there
				d.finished = false
				d.playing = true
				if d.ctl.btn then
					d.ctl.btn.BackgroundColor3 = ORANGE
				end
				if d.sound and not d.pendingSeek then
					d.sound:Play()
					d.started = true
					d.soundPlaying = true
				end
			end
		end
		local function wirePads(letter)
			local hot = decks[letter].ctl.hot
			for i = 1, 5 do
				local pad = hot and hot:FindFirstChild(tostring(i))
				if pad then
					pad.MouseButton1Click:Connect(function()
						local d = decks[letter]
						if not d or not d.sound or not d.sound.IsLoaded then
							return
						end
						local cue = d.cues[i]
						if cue then
							jumpToCue(letter, d, cue)
						else
							d.cues[i] = { part = d.partIndex, t = d.sound.TimePosition }
							refreshPads(letter)
						end
					end)
					pad.MouseButton2Click:Connect(function()
						local d = decks[letter]
						if d and d.cues[i] then
							d.cues[i] = nil
							refreshPads(letter)
						end
					end)
				end
			end
		end
		-- Waveform strip in the track tile (replaces the 2 px progress line), djay-style: a full-width
		-- symmetric waveform, loud blocks (red core, blue tips) split by thin quiet stretches (cyan /
		-- green), a red playhead, a coloured arrow per hot cue. The shape is DECORATIVE: Roblox cannot
		-- read audio samples, so it is drawn from a Random seeded with the track id (same track, same
		-- picture): quiet intro, loud blocks, short breaks, quiet tail. Each bar carries a vertical
		-- UIGradient picked by its loudness.
		local WAVE_N = 250
		local function gradient(c0, c1, c2)
			return ColorSequence.new({
				ColorSequenceKeypoint.new(0, c0),
				ColorSequenceKeypoint.new(0.2, c1),
				ColorSequenceKeypoint.new(0.5, c2),
				ColorSequenceKeypoint.new(0.8, c1),
				ColorSequenceKeypoint.new(1, c0),
			})
		end
		local WAVE_LOUD = gradient(Color3.fromRGB(60, 100, 255), Color3.fromRGB(255, 50, 110), Color3.fromRGB(255, 130, 150))
		local WAVE_MID = gradient(Color3.fromRGB(70, 120, 255), Color3.fromRGB(175, 70, 230), Color3.fromRGB(205, 150, 250))
		local WAVE_QUIET = gradient(Color3.fromRGB(40, 190, 255), Color3.fromRGB(110, 240, 210), Color3.fromRGB(190, 255, 225))
		local waveUi = {}
		local function buildWave(letter, d)
			local tile = deckRoot.CurrentTrack["Track_" .. letter]
			local w = waveUi[letter]
			if not w then
				w = { bars = {}, cues = {}, cueAt = {} }
				local holder = Instance.new("Frame")
				holder.Name = "DJXWave"
				holder.BackgroundTransparency = 1
				holder.Position = UDim2.new(0, 104, 1, -28)
				holder.Size = UDim2.new(1, -118, 0, 24)
				holder.ZIndex = 5
				local base = Instance.new("Frame")
				base.Name = "Baseline"
				base.AnchorPoint = Vector2.new(0, 0.5)
				base.Position = UDim2.new(0, 0, 0.5, 0)
				base.Size = UDim2.new(1, 0, 0, 1)
				base.BackgroundColor3 = Color3.fromRGB(110, 110, 120)
				base.BackgroundTransparency = 0.5
				base.BorderSizePixel = 0
				base.ZIndex = 4
				base.Parent = holder
				-- room for the taller strip: the title block and the times lift 6 px
				for _, blk in { tile:FindFirstChildWhichIsA("TextButton").TrackDetails, tile:FindFirstChildWhichIsA("TextButton").TrackInformationWrapper.TrackDetails } do
					local pad = blk:FindFirstChild("DJXLift") or Instance.new("UIPadding")
					pad.Name = "DJXLift"
					pad.PaddingBottom = UDim.new(0, 12)
					pad.Parent = blk
				end
				for i = 1, WAVE_N do
					local bar = Instance.new("Frame")
					bar.Name = "Bar"
					bar.AnchorPoint = Vector2.new(0, 0.5)
					bar.Position = UDim2.new((i - 1) / WAVE_N, 0, 0.5, 0)
					bar.BorderSizePixel = 0
					bar.BackgroundColor3 = Color3.new(1, 1, 1)
					bar.ZIndex = 5
					local g = Instance.new("UIGradient")
					g.Rotation = 90
					g.Parent = bar
					bar.Parent = holder
					w.bars[i] = bar
				end
				local head = Instance.new("Frame")
				head.Name = "Playhead"
				head.AnchorPoint = Vector2.new(0.5, 0.5)
				head.Size = UDim2.new(0, 2, 1, 6)
				head.BackgroundColor3 = Color3.fromRGB(230, 30, 40)
				head.BorderSizePixel = 0
				head.ZIndex = 7
				head.Parent = holder
				w.head = head
				for i = 1, 5 do
					local m = Instance.new("TextLabel")
					m.Name = "Cue" .. i
					m.AnchorPoint = Vector2.new(0.5, 1)
					m.Size = UDim2.fromOffset(12, 10)
					m.BackgroundTransparency = 1
					m.Text = "▼"
					m.TextSize = 10
					m.TextColor3 = CUE_COLORS[i]
					m.FontFace = Font.new("rbxassetid://12187365364")
					m.Visible = false
					m.ZIndex = 8
					m.Parent = holder
					w.cues[i] = m
				end
				holder.Parent = tile
				w.holder = holder
				waveUi[letter] = w
			end
			-- the old progress line gives way to the strip
			for _, n in { "ProgressWrapper", "TrackProgressWrapper" } do
				local o = tile:FindFirstChild(n)
				if o then
					o.Visible = false
				end
			end
			local seed = 0
			for ch in tostring(d.t.id):gmatch(".") do
				seed = (seed * 31 + ch:byte()) % 2147483647
			end
			local rng = Random.new(seed)
			local amp, at = {}, 1
			local function fill(n, lo, hi) -- n bars with energy between lo and hi
				for k = 1, n do
					if at > WAVE_N then
						return
					end
					local swing = 0.5 + 0.5 * math.sin(at * 0.9 + k * 0.35)
					amp[at] = math.clamp((lo + (hi - lo) * swing) * (0.88 + rng:NextNumber() * 0.12), 0.05, 1)
					at += 1
				end
			end
			fill(math.floor(WAVE_N * 0.08), 0.1, 0.2) -- intro
			while at <= WAVE_N - 10 do
				fill(math.floor(30 + rng:NextNumber() * 60), 0.7, 1) -- loud block
				fill(math.floor(8 + rng:NextNumber() * 22), 0.08, 0.2) -- break
			end
			fill(WAVE_N, 0.05, 0.12) -- tail
			for b = 1, WAVE_N do
				local a = amp[b]
				local bar = w.bars[b]
				bar.Size = UDim2.new(1 / WAVE_N, -1, 0.06 + 0.94 * a, 0)
				bar.UIGradient.Color = if a > 0.6 then WAVE_LOUD elseif a > 0.3 then WAVE_MID else WAVE_QUIET
				bar.BackgroundTransparency = 0
			end
			w.owner, w.idx = d, nil
			for i = 1, 5 do
				w.cueAt[i] = nil
				w.cues[i].Visible = false
			end
		end
		local function updateWave(letter, d)
			local w = waveUi[letter]
			if not w or w.owner ~= d then
				return
			end
			local frac = math.clamp(d.pos / d.dur, 0, 1)
			w.head.Position = UDim2.new(frac, 0, 0.5, 0)
			local idx = math.floor(frac * WAVE_N)
			if idx ~= w.idx then
				local from, to = 1, WAVE_N
				if w.idx then
					from, to = math.min(idx, w.idx) + 1, math.max(idx, w.idx)
				end
				for i = from, to do
					w.bars[i].BackgroundTransparency = if i <= idx then 0.45 else 0
				end
				w.idx = idx
			end
			for i = 1, 5 do
				local c = d.cues[i]
				local at = c and ((d.partStart[c.part] or 0) + c.t) / math.max(d.clipTotal or 1, 1)
				if at ~= w.cueAt[i] then
					w.cueAt[i] = at
					local m = w.cues[i]
					m.Visible = at ~= nil
					if at then
						m.Position = UDim2.new(math.clamp(at, 0, 1), 0, 0, 1)
					end
				end
			end
		end
		local function loadDeck(letter, t)
			local old = decks[letter]
			if old and old.sound then
				old.sound:Destroy()
			end
			local total = 0
			local d = { t = t, offset = 0, partIndex = 1, pos = 0, playing = true, finished = false, partStart = {} }
			d.cues = cuesByTrack[t.id] or {}
			cuesByTrack[t.id] = d.cues
			for i = 1, #t.parts do
				total += partDur(d, i)
			end
			d.total = if total > 0 then total else (t.totalDuration or 1) * (t.playbackSpeed or 1)
			d.dur = math.max(t.totalDuration or 1, 1)
			d.labels = labelsOf(letter)
			d.rotating = deckRoot.DeckWrapper["Deck_" .. letter]["MonitorDeck_" .. letter].Wrapper:FindFirstChild("RotatingThings")
			d.angle = if d.rotating then d.rotating.Rotation else 0
			do
				local inner = deckRoot.DeckWrapper["Deck_" .. letter]["MonitorDeck_" .. letter].Wrapper.InnerWrapper
				d.mon = {
					pct = inner.Top.TrackRemainingProgress,
					rate = inner.Top.TrackPlaybackSpeed,
					elapsed = inner.Bottom.HowLongTrackOngoing,
					left = inner.Bottom.RemainingDurations,
				}
			end
			-- Track_A calls the wrapper ProgressWrapper, Track_B TrackProgressWrapper
			d.bar = deckRoot.CurrentTrack["Track_" .. letter]:FindFirstChild("AdjustableWidthProgresss", true)
			d.ctl = if old then old.ctl else deckControls(letter)
			decks[letter] = d
			startPart(d, letter, 1)
			paint(letter)
			refreshPads(letter)
			buildWave(letter, d)
			if not old then
				wirePads(letter)
				local btn = d.ctl.btn
				if btn then
					btn.MouseButton1Click:Connect(function()
						local cur = decks[letter]
						cur.playing = not cur.playing
						-- the panel controller flips its own copy of the colour on the same click and starts
						-- from "stopped"; paint ours last so button and sound agree
						task.defer(function()
							btn.BackgroundColor3 = if cur.playing then ORANGE else cur.ctl.btnBase
						end)
					end)
				end
			end
			if d.ctl.btn then
				d.ctl.btn.BackgroundColor3 = ORANGE
			end
		end
		-- Crossfader feel. A real fader has mass and dead travel; a mouse drag has neither, so:
		--  * the raw handle value is only a target, the gain chases it (time constant 50 ms)
		--  * the last 3 % at each end is a full cut, and 50 % has a 3 % magnet
		--  * three curves, cycled by the pill on the crossfader: smooth (equal power), cut (both
		--    decks full across the middle, hard fade at the edges), linear
		-- The handle itself is left alone: AdvancedDJController writes its position.
		local CURVES = { "SMOOTH", "CUT", "LINEAR" }
		local curve = 1
		local cross = nil -- smoothed crossfader value, 0 = A, 1 = B
		local function shape(v)
			if v <= 0.03 then
				return 0
			elseif v >= 0.97 then
				return 1
			end
			v = (v - 0.03) / 0.94
			return if math.abs(v - 0.5) < 0.03 then 0.5 else v
		end
		local function curveGains(v)
			if curve == 1 then
				return math.cos(v * math.pi / 2), math.sin(v * math.pi / 2)
			elseif curve == 2 then
				return math.min(1, (1 - v) / 0.1), math.min(1, v / 0.1)
			end
			return 1 - v, v
		end
		local cfFrame = deckRoot.EffectWrapperTop.CrosfaderAtoB
		do
			local old = cfFrame:FindFirstChild("DJXCurve")
			if old then
				old:Destroy()
			end
			local pill = Instance.new("TextButton")
			pill.Name = "DJXCurve"
			pill.AnchorPoint = Vector2.new(0.5, 0)
			pill.Position = UDim2.new(0.5, 0, 0, 1)
			pill.Size = UDim2.fromOffset(88, 12)
			pill.BackgroundColor3 = Color3.fromHex("1b1b1b")
			pill.AutoButtonColor = false
			pill.FontFace = Font.new("rbxassetid://12187365364")
			pill.TextSize = 9
			pill.TextColor3 = Color3.fromHex("8a8a8a")
			pill.Text = "CURVE · " .. CURVES[curve]
			pill.ZIndex = 0 -- under the handle, which is in the Wrapper sibling
			local pc = Instance.new("UICorner")
			pc.CornerRadius = UDim.new(0, 3)
			pc.Parent = pill
			pill.MouseButton1Click:Connect(function()
				curve = curve % #CURVES + 1
				pill.Text = "CURVE · " .. CURVES[curve]
			end)
			pill.Parent = cfFrame
		end
		-- grab feedback: the handle grows a little while held, the nearest tick lights up
		local held = false
		local grabScale = cfHandle:FindFirstChild("DJXGrab") or Instance.new("UIScale")
		grabScale.Name = "DJXGrab"
		grabScale.Parent = cfHandle
		local function grow(to)
			TweenService:Create(grabScale, TweenInfo.new(0.08, Enum.EasingStyle.Quad), { Scale = to }):Play()
		end
		cfHandle.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				held = true
				grow(1.12)
			end
		end)
		UIS.InputEnded:Connect(function(input)
			if held and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
				held = false
				grow(1)
			end
		end)
		local ticks, tickBase, litTick = {}, nil, nil
		for _, c in cfHandle.Parent:FindFirstChild("Frame"):GetChildren() do
			if c:IsA("Frame") then
				table.insert(ticks, c)
				tickBase = tickBase or c.BackgroundColor3
			end
		end
		RunService.Heartbeat:Connect(function(dt)
			local target = shape(crossValue())
			if cross == nil or math.abs(target - cross) < 0.0005 then
				cross = target
			else
				cross += (target - cross) * (1 - math.exp(-dt / 0.05))
			end
			local ga, gb = curveGains(cross)
			local gains = { A = ga, B = gb }
			local hx = cfHandle.AbsolutePosition.X + cfHandle.AbsoluteSize.X / 2
			local nearest, best = nil, math.huge
			for _, tk in ticks do
				local dist = math.abs(tk.AbsolutePosition.X + tk.AbsoluteSize.X / 2 - hx)
				if dist < best then
					nearest, best = tk, dist
				end
			end
			if nearest ~= litTick then
				if litTick then
					litTick.BackgroundColor3 = tickBase
				end
				litTick = nearest
				if litTick then
					litTick.BackgroundColor3 = GREEN
				end
			end
			for _, letter in LETTERS do
				for _, band in EQ_BANDS do
					local u = eqUi[letter][band]
					u.db = eqDb(math.clamp((u.knob.Rotation + 135) / 270, 0, 1))
					local txt = eqText(u.db)
					if u.label.Text ~= txt then
						u.label.Text = txt
					end
				end
			end
			for letter, d in decks do
				-- platter: 180 deg/s at 1.00x, so it turns faster / slower with the deck speed and stops
				-- when paused. Written as an absolute angle every frame, so the panel controller's own
				-- fixed-speed spin (it adds to Rotation while ITS play flag is on) cannot change the pace.
				if d.rotating then
					d.angle = (d.angle + (if d.playing then dt * 180 * (d.speed or 1) else 0) + jogScratch["Deck_" .. letter]) % 360
					jogScratch["Deck_" .. letter] = 0
					d.rotating.Rotation = d.angle
				end
				local snd = d.sound
				local fx = snd and snd:FindFirstChild("DJXEq")
				if fx then
					-- live effect: mutate in place, and only when the value moved
					for _, band in EQ_BANDS do
						local prop, db = band .. "Gain", eqUi[letter][band].db
						if fx[prop] ~= db then
							fx[prop] = db
						end
					end
				end
				local ff = snd and snd:FindFirstChild("DJXFilter")
				if ff then
					local lo, mid, hi = filterGains(math.clamp(filterKnobs[letter].Rotation / 270 + 0.5, 0, 1))
					if ff.LowGain ~= lo then
						ff.LowGain = lo
					end
					if ff.MidGain ~= mid then
						ff.MidGain = mid
					end
					if ff.HighGain ~= hi then
						ff.HighGain = hi
					end
				end
				if snd and snd.IsLoaded then
					local speed = tonumber(d.ctl.speed.Text:match("[%d%.]+")) or 1
					local rate = (d.t.playbackSpeed or 1) * speed
					d.speed = speed
					if snd.PlaybackSpeed ~= rate then
						snd.PlaybackSpeed = rate
					end
					local fader = math.clamp(1 - d.ctl.fader.Position.Y.Scale, 0, 1)
					snd.Volume = fader * gains[letter]
					if d.playing and not d.soundPlaying then
						if d.started then
							snd:Resume()
						else
							snd:Play()
							d.started = true
						end
						d.soundPlaying = true
					elseif not d.playing and d.soundPlaying then
						snd:Pause()
						d.soundPlaying = false
					end
					if d.pendingSeek then
						snd.TimePosition = d.pendingSeek
						d.pendingSeek = nil
					end
					-- the stored partDurations can disagree with the real asset, so the length comes from
					-- the loaded Sound (later parts, not loaded yet, fall back to the stored value)
					local total = d.offset + snd.TimeLength
					for i = d.partIndex + 1, #d.t.parts do
						total += partDur(d, i)
					end
					d.clipTotal = total
					d.dur = math.max(total / rate, 1)
					d.pos = math.min((d.offset + snd.TimePosition) / rate, d.dur)
				end
				paint(letter)
				updateWave(letter, d)
			end
		end)

		-- test / scripting hook: DJXLoadDeck:Fire("A" | "B", trackId) loads a library track on a deck
		-- without dragging (the playtest input simulator cannot move the cursor)
		local stale = gui:FindFirstChild("DJXLoadDeck")
		if stale then
			stale:Destroy()
		end
		local loadEvt = Instance.new("BindableEvent")
		loadEvt.Name = "DJXLoadDeck"
		loadEvt.Event:Connect(function(letter, trackId)
			local t = (store:get().allTracks or {})[trackId]
			if t and (letter == "A" or letter == "B") then
				loadDeck(letter, t)
			end
		end)
		loadEvt.Parent = gui

		-- drag
		local pending, ghost, ghostHint, hover = nil, nil, nil, nil
		local function endDrag()
			if hover then
				setOutline(hover, false)
			end
			if ghost then
				ghost:Destroy()
			end
			pending, ghost, ghostHint, hover = nil, nil, nil, nil
		end
		-- the mini card that follows the cursor: cover, title, creator, length, and a hint line that
		-- names the deck under the cursor (updated by the drag loop through g.Hint)
		local function makeGhost(t, row)
			local function label(parent, props)
				local l = Instance.new("TextLabel")
				l.BackgroundTransparency = 1
				l.FontFace = Font.new("rbxassetid://12187365364")
				l.TextXAlignment = Enum.TextXAlignment.Left
				l.TextTruncate = Enum.TextTruncate.AtEnd
				l.ZIndex = 101
				for k, v in props do
					l[k] = v
				end
				l.Parent = parent
				return l
			end
			local g = Instance.new("Frame")
			g.Name = "DJXDragGhost"
			g.Size = UDim2.fromOffset(300, 64)
			g.BackgroundColor3 = Color3.fromHex("202020")
			g.ZIndex = 100
			g.Active = false
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 6)
			c.Parent = g
			local s = Instance.new("UIStroke")
			s.Name = "Rim"
			s.Color = Color3.fromHex("3a3a3a")
			s.Thickness = 1
			s.Parent = g
			local cover = row:FindFirstChild("RelatedPlaylistCover")
			if cover then
				cover = cover:Clone()
				cover.AnchorPoint = Vector2.new(0, 0.5)
				cover.Position = UDim2.new(0, 8, 0.5, 0)
				cover.Size = UDim2.fromOffset(48, 48)
				cover.ZIndex = 101
				for _, d in cover:GetDescendants() do
					if d:IsA("GuiObject") then
						d.ZIndex = 102
					end
				end
				local asp = cover:FindFirstChildOfClass("UIAspectRatioConstraint")
				if asp then
					asp:Destroy()
				end
				cover.Parent = g
			end
			label(g, {
				Position = UDim2.fromOffset(64, 10),
				Size = UDim2.new(1, -130, 0, 18),
				Text = t.name,
				TextColor3 = Color3.fromHex("ffffff"),
				TextSize = 14,
			})
			label(g, {
				Position = UDim2.fromOffset(64, 29),
				Size = UDim2.new(1, -130, 0, 14),
				Text = t.creator,
				TextColor3 = Color3.fromHex("9a9a9a"),
				TextSize = 12,
			})
			local hint = label(g, {
				Name = "Hint",
				Position = UDim2.fromOffset(64, 44),
				Size = UDim2.new(1, -72, 0, 14),
				Text = "Drop on a deck",
				TextColor3 = Color3.fromHex("6a6a6a"),
				TextSize = 11,
			})
			label(g, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 10),
				Size = UDim2.fromOffset(52, 18),
				Text = mmss(t.totalDuration or 0):sub(1, 5),
				TextColor3 = Color3.fromHex("9a9a9a"),
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Right,
			})
			g.Parent = gui
			return g, hint
		end
		local function hook(row)
			if row.Name ~= "RealTrackRow" then
				return
			end
			row.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					local t = trackOf(row)
					if t then
						pending = { t = t, row = row, start = guiPos(input), input = input }
					end
				end
			end)
		end
		-- polled every frame while a row is held (does not depend on InputChanged delivery)
		RunService.RenderStepped:Connect(function()
			if not pending then
				return
			end
			local m = UIS:GetMouseLocation()
			local p = if gui.IgnoreGuiInset then m else m - GuiService:GetGuiInset()
			if not ghost and (p - pending.start).Magnitude > 8 then
				ghost, ghostHint = makeGhost(pending.t, pending.row)
			end
			if ghost then
				ghost.Position = UDim2.fromOffset(p.X + 14, p.Y + 14)
				local over = deckAt(p)
				if over ~= hover then
					if hover then
						setOutline(hover, false)
					end
					hover = over
					if hover then
						setOutline(hover, true)
					end
					ghostHint.Text = if hover then "Release to play on Deck " .. hover else "Drop on a deck"
					ghostHint.TextColor3 = if hover then GREEN else Color3.fromHex("6a6a6a")
					ghost.Rim.Color = if hover then GREEN else Color3.fromHex("3a3a3a")
				end
			end
		end)
		UIS.InputEnded:Connect(function(input)
			if
				pending
				and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch)
			then
				-- decide on the release point, not on hover state: a fast drag may skip move events
				local p = guiPos(input)
				local target = if (p - pending.start).Magnitude > 8 then deckAt(p) else nil
				if target then
					loadDeck(target, pending.t)
				end
				endDrag()
			end
		end)

		for _, c in rowsScroll:GetChildren() do
			hook(c)
		end
		rowsScroll.ChildAdded:Connect(hook)
	end
end

task.defer(fit)
