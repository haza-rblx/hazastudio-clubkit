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
local C = {
	bg = Color3.fromHex("19111d"),
	card = Color3.fromHex("1f1723"),
	card2 = Color3.fromHex("2b232f"),
	dim = Color3.fromHex("7f7f7f"),
	live = Color3.fromRGB(228, 16, 36),
	accent = Color3.fromRGB(234, 75, 7),
	ok = Color3.fromRGB(46, 200, 110),
	sfx = Color3.fromRGB(255, 150, 60),
	world = Color3.fromRGB(110, 140, 255),
	deckA = Color3.fromRGB(80, 170, 255),
	deckB = Color3.fromRGB(255, 120, 70),
	lane = Color3.fromHex("120c15"),
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
			bl.Padding = UDim.new(0, 2)
			bl.VerticalAlignment = Enum.VerticalAlignment.Center
			band.Knob.Size = UDim2.fromOffset(43, 43)
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
		fc.Size = UDim2.new(1, 0, 0, ROW)
		fc.LayoutOrder = 1
		local fl = fc:FindFirstChildOfClass("UIListLayout")
		fl.Padding = UDim.new(0, 2)
		fl.VerticalAlignment = Enum.VerticalAlignment.Center
		for _, c in w:GetChildren() do
			if c:IsA("TextLabel") then
				c.Parent = fc -- the template's "100%" readout becomes the band's value line
			end
		end
		for _, c in fc:GetChildren() do
			if c:IsA("TextLabel") then
				c.LayoutOrder = c.Text == "FILTER" and 0 or 3
			end
		end
		local fknob = fc:FindFirstChild("Knob", true)
		local holder = fknob.Parent == fc and fknob or fknob.Parent
		holder.LayoutOrder = 1
		holder.Size = UDim2.fromOffset(43, 43)
		if holder ~= fknob then
			fknob.Size = UDim2.fromScale(1, 1)
		end
		local vol = w.TrackA_VolumeChanger
		vol.LayoutOrder = 2
		vol.Size = UDim2.new(1, 0, 1, -(PAD * 2 + ROW + ROW * 0.25))

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
		cp2.Frame.Size = UDim2.new(1, 0, 1, -(PAD * 2 + 40 + 20 + 30 + 8 * 3))
	end
end

-- ════════════════════════════════════════════════════════════
-- 6. Centre column: two scrolling waveform lanes, playhead, beat grid,
--    per-deck VU, BPM tags, 4-beat phase meter
-- ════════════════════════════════════════════════════════════
do
	local wave = deckWrapper.Waveform
	for _, c in wave:GetChildren() do
		if c:IsA("GuiObject") then
			c.Visible = false
		end
	end
	local center = noTint(new("Frame", { Name = "DJX_Center", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromHex("0c080e"), BorderSizePixel = 0 }, wave))
	local TOP, BOTTOM = 26, 22
	local top = new("Frame", { Size = UDim2.new(1, 0, 0, TOP), BackgroundTransparency = 1 }, center)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, top)
	local function tag(deck, bpm, anchorX)
		local f = new("Frame", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(anchorX, 0), Position = UDim2.fromScale(anchorX, 0), BackgroundTransparency = 1 }, top)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = anchorX == 1 and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left }, f)
		local chip = noTint(new("TextLabel", { Text = deck, FontFace = B, TextSize = 11, TextColor3 = Color3.fromHex("0c080e"), BackgroundColor3 = deck == "A" and C.deckA or C.deckB, Size = UDim2.fromOffset(16, 16), LayoutOrder = anchorX == 1 and 2 or 1 }, f))
		new("UICorner", { CornerRadius = UDim.new(0, 4) }, chip)
		new("TextLabel", { Text = bpm, FontFace = B, TextSize = 12, TextColor3 = W, BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new(), LayoutOrder = anchorX == 1 and 1 or 2 }, f)
	end
	tag("A", "124.0", 0)
	tag("B", "122.0", 1)
	local body = new("Frame", { Size = UDim2.new(1, -16, 1, -(TOP + BOTTOM)), Position = UDim2.fromOffset(8, TOP), BackgroundTransparency = 1 }, center)
	local VUW, LGAP = 5, 6
	local function vuMeter(x, anchor)
		local f = new("Frame", { Size = UDim2.new(0, VUW, 1, 0), AnchorPoint = Vector2.new(anchor, 0), Position = UDim2.fromScale(x, 0), BackgroundColor3 = C.lane, BorderSizePixel = 0 }, body)
		new("UICorner", { CornerRadius = UDim.new(0, 2) }, f)
		local lvl = noTint(new("Frame", { Size = UDim2.fromScale(1, 0), AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), BackgroundColor3 = W, BorderSizePixel = 0 }, f))
		new("UICorner", { CornerRadius = UDim.new(0, 2) }, lvl)
		new("UIGradient", { Rotation = -90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 220, 120)), ColorSequenceKeypoint.new(0.7, Color3.fromRGB(255, 210, 60)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 70, 70)) }) }, lvl)
		return lvl
	end
	local vuA, vuB = vuMeter(0, 0), vuMeter(1, 1)
	local function lane(xScale, xOff)
		local l = noTint(new("Frame", { Size = UDim2.new(0.5, -(VUW + 4 + LGAP / 2), 1, 0), Position = UDim2.new(xScale, xOff, 0, 0), BackgroundColor3 = C.lane, BorderSizePixel = 0, ClipsDescendants = true }, body))
		new("UICorner", { CornerRadius = UDim.new(0, 4) }, l)
		return l
	end
	local laneA, laneB = lane(0, VUW + 4), lane(0.5, LGAP / 2)
	local N = 64
	local function rng(seed)
		local s = seed
		return function()
			s = (s * 1103515245 + 12345) % 2147483648
			return s / 2147483648
		end
	end
	local function build(l, color, seed)
		local r = rng(seed)
		local amps, prev = {}, 0.5
		for i = 1, N do
			local a = math.clamp(prev * 0.55 + r() * 0.7, 0.08, 1)
			if i % 16 == 1 then
				a = 1
			end
			amps[i] = a
			prev = a
		end
		local strips = {}
		for copy = 0, 1 do
			local strip = new("Frame", { Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0, copy), BackgroundTransparency = 1 }, l)
			for i = 1, N do
				local a = amps[i]
				noTint(new("Frame", { Size = UDim2.new(a * 0.9, 0, 1 / N, -1), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, (i - 1) / N), BackgroundColor3 = color:Lerp(W, a > 0.85 and 0.55 or 0), BackgroundTransparency = 0.15 + (1 - a) * 0.35, BorderSizePixel = 0 }, strip))
				if i % 16 == 1 then
					new("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromScale(0, (i - 1) / N), BackgroundColor3 = W, BackgroundTransparency = 0.6, BorderSizePixel = 0 }, strip)
				end
			end
			strips[copy + 1] = strip
		end
		new("Frame", { Size = UDim2.fromScale(1, 0.35), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 3 }, l)
		return strips
	end
	local stripsA, stripsB = build(laneA, C.deckA, 7), build(laneB, C.deckB, 42)
	local ph = noTint(new("Frame", { Size = UDim2.new(1, 0, 0, 2), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.35), BackgroundColor3 = W, BorderSizePixel = 0, ZIndex = 5 }, body))
	for _, side in { 0, 1 } do
		noTint(new("Frame", { Size = UDim2.fromOffset(6, 6), AnchorPoint = Vector2.new(side, 0.5), Position = UDim2.fromScale(side, 0.5), Rotation = 45, BackgroundColor3 = W, BorderSizePixel = 0, ZIndex = 5 }, ph))
	end
	local bot = new("Frame", { Size = UDim2.new(1, -16, 0, BOTTOM - 8), Position = UDim2.new(0, 8, 1, -(BOTTOM - 4)), BackgroundTransparency = 1 }, center)
	local function phaseRow(y, color)
		local cells = {}
		for i = 1, 4 do
			local c = noTint(new("Frame", { Size = UDim2.new(0.25, -3, 0.5, -1), Position = UDim2.new((i - 1) * 0.25, 0, y, 0), BackgroundColor3 = color, BackgroundTransparency = 0.8, BorderSizePixel = 0 }, bot))
			new("UICorner", { CornerRadius = UDim.new(0, 2) }, c)
			cells[i] = c
		end
		return cells
	end
	local phA, phB = phaseRow(0, C.deckA), phaseRow(0.5, C.deckB)
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
	local posA, posB, lvA, lvB = 0, 0.37, 0, 0
	RunService.RenderStepped:Connect(function(dt)
		if os.clock() - lastScan > 3 then
			lastScan = os.clock()
			music = loudest()
		end
		local lv = math.clamp((music and music.PlaybackLoudness or 0) / 500, 0, 1)
		posA = (posA + dt * (124 / 60) / 16) % 1
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
		local beatA = math.floor(posA * 16) % 4 + 1
		for i, c in phA do
			c.BackgroundTransparency = i == beatA and 0 or 0.8
		end
		for i, c in phB do
			c.BackgroundTransparency = i == 1 and 0.3 or 0.85
		end
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
-- 8. Knobs: bipolar filter (OFF in the middle, LPF left, HPF right), LED-ring look
-- ════════════════════════════════════════════════════════════
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
		local bipolar = k:FindFirstAncestor("FilterChanger") ~= nil
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
		-- LED dots on rotated arms: sub-pixel placement keeps every gap identical (pixel-snapped
		-- offsets made the spacing uneven); everything in Scale so the panel UIScale can't skew it
		local leds = new("Frame", { Name = "DJX_Leds", Size = UDim2.fromScale(1, 1), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, ZIndex = k.ZIndex + 1 }, k)
		local DOT = 0.09
		local ticks = {}
		for i = 0, 10 do
			local arm = new("Frame", { Size = UDim2.fromScale(DOT, 1), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Rotation = -135 + i * 27, BackgroundTransparency = 1, ZIndex = k.ZIndex + 1 }, leds)
			local dot = noTint(new("Frame", { Size = UDim2.fromScale(1, 1), SizeConstraint = Enum.SizeConstraint.RelativeXX, BackgroundColor3 = W, BorderSizePixel = 0, ZIndex = k.ZIndex + 1 }, arm))
			new("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
			ticks[i] = dot
		end
		local function refresh()
			leds.Rotation = -k.Rotation
			local v = math.clamp((k.Rotation + 135) / 270, 0, 1)
			for i = 0, 10 do
				local f = i / 10
				local lit
				if bipolar then
					lit = (v < 0.5 and f >= v - 0.001 and f <= 0.5) or (v > 0.5 and f <= v + 0.001 and f >= 0.5) or (math.abs(v - 0.5) < 0.01 and i == 5)
				else
					lit = f <= v + 0.001
				end
				ticks[i].BackgroundTransparency = lit and 0 or 0.8
			end
		end
		k:GetPropertyChangedSignal("Rotation"):Connect(refresh)
		refresh()
	end
end

-- ════════════════════════════════════════════════════════════
-- 9. Jog wheels: drag around the platter ring to scratch (visual)
-- ════════════════════════════════════════════════════════════
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
				rotating.Rotation = (rotating.Rotation + ((a - lastA + 540) % 360 - 180)) % 360
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

task.defer(fit)
