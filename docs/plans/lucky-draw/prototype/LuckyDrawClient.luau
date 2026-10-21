--!strict
-- StarterPlayer.StarterPlayerScripts.LuckyDrawClient (LocalScript)
-- Drives the owner's LuckyDrawGui (the PlayerGui copy). The StarterGui design is never edited.
-- Panel reel + toast reel share one RenderStepped connection.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local STRIP_LEN = 32
local WIN_INDEX = 28
local OFF_START = 2
local HOLD_SECONDS = 4
local PENDING_TIMEOUT = 3
local STUDIO_MIN_POOL = 12
local TOAST_TOP_PX = 12
local FACE_SCALE = 1.3

local localPlayer = Players.LocalPlayer
local playerGui: any = localPlayer:WaitForChild("PlayerGui")
local gui: any = playerGui:WaitForChild("LuckyDrawGui")
local remotes: any = ReplicatedStorage:WaitForChild("LuckyDrawRemotes")
local requestEvent: any = remotes:WaitForChild("Request")
local broadcastEvent: any = remotes:WaitForChild("Broadcast")

local root: any = gui:WaitForChild("Root")
local rootScale: any = root:WaitForChild("UIScale")
local chrome: any = root:WaitForChild("Chrome")
local dragHandle: any = chrome:WaitForChild("DragHandle")
local panelClose: any = chrome:WaitForChild("CloseWrapper"):WaitForChild("CloseButton")
local content: any = root:WaitForChild("Card"):WaitForChild("Content")
local reelWindow: any = content:WaitForChild("ReelWindow")
local oddsLabel: any = reelWindow:WaitForChild("OddsChip"):WaitForChild("Label")
local spinButton: any = content:WaitForChild("SpinButton")
local spinLabel: any = spinButton:WaitForChild("Label")

local toast: any = gui:WaitForChild("Toast")
local toastTitle: any = toast:WaitForChild("Title")
local toastClose: any = toast:WaitForChild("CloseWrapper"):WaitForChild("CloseButton")
local miniStage: any = toast:WaitForChild("MiniReel"):WaitForChild("Stage")
local progressSpot: any = miniStage:FindFirstChild("Spotlight")
local progressBeam: any = progressSpot and progressSpot:FindFirstChild("Beam")
local progressGradient: any = progressBeam and progressBeam:FindFirstChild("ProgressGradient")

-- Toast spawns top-centre (drops from above), panel spawns centre (rises from below); no scaling.
toast.AnchorPoint = Vector2.new(0.5, 0)
local TOAST_HOME: UDim2 = UDim2.new(0.5, 0, 0, TOAST_TOP_PX)
local TOAST_AWAY: UDim2 = UDim2.new(0.5, 0, 0, -320)
root.AnchorPoint = Vector2.new(0.5, 0.5)
local PANEL_HOME: UDim2 = UDim2.fromScale(0.5, 0.5)
local PANEL_AWAY: UDim2 = UDim2.fromScale(0.5, 1.6)
local SPIN_BASE_BT: number = spinButton.BackgroundTransparency

-- ============================================================
-- Helpers
-- ============================================================
local function clamp(x: number, lo: number, hi: number): number
	if x < lo then
		return lo
	end
	if x > hi then
		return hi
	end
	return x
end

local function escapeRich(s: string): string
	local out = string.gsub(s, "&", "&amp;")
	out = string.gsub(out, "<", "&lt;")
	out = string.gsub(out, ">", "&gt;")
	return out
end

local function thumbOf(userId: number): string
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
end

local function spinningTitle(name: string): string
	return '<font color="#ffffff">' .. escapeRich(name) .. '</font><font color="#bebebe"> is spinning!</font>'
end

local function wonTitle(name: string): string
	return '<font color="#ffffff">' .. escapeRich(name) .. '</font><font color="#bebebe"> won!</font>'
end

local function setTileContent(tile: any, entry: any)
	tile.Face.Image = thumbOf(entry.userId)
	tile.DisplayName.Text = entry.displayName
	tile.Handle.Text = "@" .. entry.username
end

-- Names stay hidden before and during the spin (photo only); they fade in once it lands.
local NAME_FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function setNamesShown(tile: any, shown: boolean, animated: boolean)
	local t = if shown then 0 else 1
	for _, label in ipairs({ tile.DisplayName, tile.Handle }) do
		if animated then
			TweenService:Create(label, NAME_FADE, { TextTransparency = t }):Play()
		else
			label.TextTransparency = t
		end
	end
end

local function captureStyle(tile: any): any
	return {
		faceSize = tile.Face.Size,
		faceT = tile.Face.ImageTransparency,
		dnTS = tile.DisplayName.TextSize,
		dnColor = tile.DisplayName.TextColor3,
		hdTS = tile.Handle.TextSize,
		hdColor = tile.Handle.TextColor3,
	}
end

-- Reel bookkeeping for one Rows frame (panel or toast). The two style ends are read
-- from the owner's RowTemplate (side) and Row1 (centre) at runtime, never hard-coded.
local function makeReel(rows: any): any
	local template: any = rows:WaitForChild("RowTemplate")
	local centre: any = rows:WaitForChild("Row1")
	local row2: any = rows:WaitForChild("Row2")
	local layout: any = rows:FindFirstChildOfClass("UIListLayout")
	local pad = 0
	if layout then
		pad = layout.Padding.Offset
	end
	-- Photos are scaled up uniformly (side and centre keep their ratio) since names are mostly hidden.
	for _, tile in ipairs({ template, centre, row2 }) do
		local s = tile.Face.Size
		tile.Face.Size = UDim2.new(s.X.Scale, math.round(s.X.Offset * FACE_SCALE), s.Y.Scale, math.round(s.Y.Offset * FACE_SCALE))
	end
	local centreStroke: any = centre.Face:FindFirstChildOfClass("UIStroke")
	return {
		rows = rows,
		layout = layout,
		template = template,
		centre = centre,
		row2 = row2,
		sideStyle = captureStyle(template),
		centreStyle = captureStyle(centre),
		sideW = template.Size.X.Offset,
		centreW = centre.Size.X.Offset,
		pitch = template.Size.X.Offset + pad,
		stroke = centreStroke,
		centreStrokeT = if centreStroke then centreStroke.Transparency else 0,
		stripH = 80,
		-- Rows UIPadding.PaddingLeft shifts absolutely positioned children right by this many logical units.
		padL = (function(): number
			local p = rows:FindFirstChildOfClass("UIPadding")
			return if p then p.PaddingLeft.Offset else 0
		end)(),
		state = nil,
	}
end

local mainReel: any = makeReel(reelWindow:WaitForChild("Rows"))

-- Winner spotlight FX (client-local ModuleScript). Optional: the panel works without it.
local WinFx: any = nil
do
	local m = ReplicatedStorage:FindFirstChild("LuckyDrawWinFx")
	if m then
		local okFx, mod = pcall(require, m)
		if okFx then
			WinFx = mod
		else
			warn("[LuckyDraw] WinFx load failed: " .. tostring(mod))
		end
	end
end
local toastReel: any = makeReel(miniStage:WaitForChild("Rows"))

-- Strip of STRIP_LEN tiles drawn from the pool, winner at WIN_INDEX, no two adjacent equal.
local function buildStrip(pool: { any }, winnerIndex: number, seed: number): { any }
	local rng = Random.new(seed)
	local winner = pool[winnerIndex]
	local seq: { any } = {}
	for i = 1, STRIP_LEN do
		if i == WIN_INDEX then
			seq[i] = winner
		else
			local candidates: { any } = {}
			for _, e in ipairs(pool) do
				local bad = i > 1 and seq[i - 1] ~= nil and seq[i - 1].userId == e.userId
				if (i == WIN_INDEX - 1 or i == WIN_INDEX + 1) and e.userId == winner.userId then
					bad = true
				end
				if not bad then
					table.insert(candidates, e)
				end
			end
			if #candidates == 0 then
				candidates = pool
			end
			seq[i] = candidates[rng:NextInteger(1, #candidates)]
		end
	end
	return seq
end

-- Scale of the UIScale wrapping this reel (screen px per logical unit).
local function reelScale(reel: any): number
	local frame = reel.rows.Parent
	if frame.Size.Y.Offset > 0 and frame.AbsoluteSize.Y > 0 then
		return frame.AbsoluteSize.Y / frame.Size.Y.Offset
	end
	return 1
end

local function endReel(reel: any)
	if reel.state then
		for _, t in ipairs(reel.state.tiles) do
			t.frame:Destroy()
		end
		reel.state = nil
	end
	-- Sweep any leftover strip clones (never leave a ghost tile under Rows).
	for _, c in ipairs(reel.rows:GetChildren()) do
		if string.sub(c.Name, 1, 5) == "Strip" then
			c:Destroy()
		end
	end
	reel.template.Visible = true
	reel.centre.Visible = true
	reel.row2.Visible = true
	if reel.layout and reel.layout.Parent == nil then
		reel.layout.Parent = reel.rows
	end
end

local function beginReel(reel: any, seq: { any }, data: any, hooks: any)
	endReel(reel)
	-- Measure the logical tile height while the static tiles are still shown (strip tiles get a fixed Y size).
	-- Use the centre tile so the enlarged winner photo plus its names fit.
	local measured = reel.centre.AbsoluteSize.Y / reelScale(reel)
	if measured > 0 then
		reel.stripH = measured
	end
	reel.template.Visible = false
	reel.centre.Visible = false
	reel.row2.Visible = false
	if reel.layout and reel.layout.Parent then
		reel.layout.Parent = nil
	end
	local tiles: { any } = {}
	for i, entry in ipairs(seq) do
		local frame: any = reel.template:Clone()
		frame.Name = "Strip" .. tostring(i)
		frame.AutomaticSize = Enum.AutomaticSize.None
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Size = UDim2.new(0, reel.sideW, 0, reel.stripH)
		frame.Position = UDim2.new(0, 0, 0.5, 0)
		frame.Visible = false
		frame.Parent = reel.rows
		setTileContent(frame, entry)
		setNamesShown(frame, false, false)
		local stroke: any = nil
		if reel.stroke then
			stroke = reel.stroke:Clone()
			stroke.Transparency = 1
			stroke.Parent = frame.Face
		end
		tiles[i] = { frame = frame, face = frame.Face, dn = frame.DisplayName, hd = frame.Handle, stroke = stroke, list = frame:FindFirstChildOfClass("UIListLayout") }
	end
	reel.state = {
		tiles = tiles,
		seq = seq,
		startAt = data.startAt,
		duration = data.duration,
		landed = false,
		landAt = 0,
		doneFired = false,
		hooks = hooks,
		winnerName = seq[WIN_INDEX].displayName,
	}
end

local function applyTile(reel: any, tile: any, e: number)
	local side = reel.sideStyle
	local centre = reel.centreStyle
	tile.face.Size = side.faceSize:Lerp(centre.faceSize, e)
	tile.face.ImageTransparency = side.faceT + (centre.faceT - side.faceT) * e
	tile.dn.TextSize = math.round(side.dnTS + (centre.dnTS - side.dnTS) * e)
	tile.dn.TextColor3 = side.dnColor:Lerp(centre.dnColor, e)
	tile.hd.TextSize = math.round(side.hdTS + (centre.hdTS - side.hdTS) * e)
	tile.hd.TextColor3 = side.hdColor:Lerp(centre.hdColor, e)
	if tile.stroke then
		tile.stroke.Transparency = 1 - e * (1 - reel.centreStrokeT)
	end
end

local function stepReel(reel: any, serverNow: number, now: number)
	local s = reel.state
	if not s then
		return
	end
	local k = clamp((serverNow - s.startAt) / s.duration, 0, 1)
	local eased = 1 - (1 - k) ^ 5 -- Quint Out
	local offset = OFF_START + (WIN_INDEX - OFF_START) * eased
	-- All geometry in logical units (the reel sits inside a UIScale): screen px / scale.
	local width = reel.rows.AbsoluteSize.X / reelScale(reel)
	-- Tile x is offset by PaddingLeft, so the wrapper centre in tile space is width/2 - padL.
	local cx = width / 2 - reel.padL
	local reach = width / 2 + reel.centreW
	local scale = reelScale(reel)
	-- After landing the winner glides from photo-centred to photo+names-centred while its names fade in.
	local rise = if s.landed then clamp((now - s.landAt) / NAME_FADE.Time, 0, 1) else 0
	rise = 1 - (1 - rise) ^ 2
	for i, tile in ipairs(s.tiles) do
		local x = cx + (i - offset) * reel.pitch
		local d = math.abs(x - cx)
		if d > reach then
			tile.frame.Visible = false
		else
			local e = clamp(1 - d / reel.pitch, 0, 1)
			applyTile(reel, tile, e)
			-- Tiles are top-aligned and names are hidden, so centre the photo itself on the reel line.
			local y = reel.stripH / 2 - tile.face.Size.Y.Offset / 2
			if i == WIN_INDEX and rise > 0 and tile.list then
				local contentH = tile.list.AbsoluteContentSize.Y / scale
				y += (reel.stripH / 2 - contentH / 2 - y) * rise
			end
			tile.frame.Position = UDim2.new(0, x, 0.5, y)
			tile.frame.Size = UDim2.new(0, reel.sideW + (reel.centreW - reel.sideW) * e, 0, reel.stripH)
			tile.frame.Visible = true
			tile.frame.ZIndex = 1 + math.floor(e * 8)
		end
	end
	if k >= 1 and not s.landed then
		s.landed = true
		s.landAt = now
		setNamesShown(s.tiles[WIN_INDEX].frame, true, true)
		if s.hooks.onLand then
			s.hooks.onLand(s)
		end
	end
	if s.landed and not s.doneFired and s.hooks.hold and now >= s.landAt + s.hooks.hold then
		s.doneFired = true
		if s.hooks.onDone then
			s.hooks.onDone(s)
		end
	end
end

-- ============================================================
-- Idle panel (static 3 tiles + odds)
-- ============================================================
local function idleList(): { any }
	local list: { any } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		table.insert(list, { userId = p.UserId, displayName = p.DisplayName, username = p.Name })
	end
	while #list < 3 do
		table.insert(list, { userId = localPlayer.UserId, displayName = localPlayer.DisplayName, username = localPlayer.Name })
	end
	return list
end

local function poolCount(): number
	local n = #Players:GetPlayers()
	if RunService:IsStudio() and n < STUDIO_MIN_POOL then
		n = STUDIO_MIN_POOL
	end
	return n
end

local function refreshIdle()
	oddsLabel.Text = "1 in " .. tostring(poolCount())
	if mainReel.state ~= nil then
		return
	end
	local list = idleList()
	setTileContent(mainReel.template, list[1])
	setTileContent(mainReel.centre, list[2])
	setTileContent(mainReel.row2, list[3])
	for _, t in ipairs({ mainReel.template, mainReel.centre, mainReel.row2 }) do
		setNamesShown(t, false, false)
	end
end

-- ============================================================
-- Idle flow (panel open, no spin): equal photos drifting left, no names
-- ============================================================
local IDLE_SPEED = 24 -- logical px per second

local idle: any = { running = false, tiles = {}, scroll = 0, nextIdx = 0 }

local function idleNextEntry(): any
	local list = idleList()
	idle.nextIdx += 1
	return list[(idle.nextIdx - 1) % #list + 1]
end

local function stopIdle()
	if not idle.running then
		return
	end
	idle.running = false
	for _, t in ipairs(idle.tiles) do
		t.frame:Destroy()
	end
	idle.tiles = {}
	mainReel.template.Visible = true
	mainReel.centre.Visible = true
	mainReel.row2.Visible = true
	if mainReel.layout and mainReel.layout.Parent == nil then
		mainReel.layout.Parent = mainReel.rows
	end
end

local function startIdle()
	if idle.running or mainReel.state ~= nil then
		return
	end
	idle.running = true
	idle.scroll = 0
	idle.nextIdx = 0
	mainReel.template.Visible = false
	mainReel.centre.Visible = false
	mainReel.row2.Visible = false
	if mainReel.layout and mainReel.layout.Parent then
		mainReel.layout.Parent = nil
	end
	local width = mainReel.rows.AbsoluteSize.X / reelScale(mainReel)
	local count = math.max(math.ceil(width / mainReel.pitch) + 2, 6)
	for i = 1, count do
		local frame: any = mainReel.template:Clone()
		frame.Name = "Idle" .. tostring(i)
		frame.AutomaticSize = Enum.AutomaticSize.None
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Size = UDim2.new(0, mainReel.sideW, 1, 0)
		frame.Position = UDim2.new(0, -1000, 0.5, 0)
		frame.DisplayName.Visible = false
		frame.Handle.Visible = false
		local list: any = frame:FindFirstChildOfClass("UIListLayout")
		if list then
			list.VerticalAlignment = Enum.VerticalAlignment.Center
		end
		frame.Visible = false
		frame.Parent = mainReel.rows
		setTileContent(frame, idleNextEntry())
		idle.tiles[i] = { frame = frame, last = math.huge }
	end
end

local function stepIdle(dt: number)
	if not idle.running then
		return
	end
	idle.scroll += IDLE_SPEED * dt
	local pitch = mainReel.pitch
	local total = #idle.tiles * pitch
	for i, t in ipairs(idle.tiles) do
		local wrapped = ((i - 1) * pitch - idle.scroll) % total
		if wrapped > t.last then
			-- Re-entered on the right: give it the next player.
			setTileContent(t.frame, idleNextEntry())
		end
		t.last = wrapped
		t.frame.Position = UDim2.new(0, wrapped - pitch / 2 - mainReel.padL, 0.5, 0)
		t.frame.Visible = true
	end
end

-- ============================================================
-- Spin button
-- ============================================================
local spinBusy = false
local hasSpun = false

local function setSpinIdle(again: boolean)
	spinBusy = false
	spinLabel.Text = if again then "Spin again" else "Spin"
	spinButton.BackgroundTransparency = SPIN_BASE_BT
end

local function setSpinBusy()
	spinBusy = true
	spinLabel.Text = "Spinning…"
	spinButton.BackgroundTransparency = 0.4
end

-- ============================================================
-- Main reel hooks
-- ============================================================
local function playWinFx(s: any)
	if not WinFx then
		return
	end
	local entry = s.seq[WIN_INDEX]
	local plr = Players:GetPlayerByUserId(entry.userId)
	local char: any = plr and plr.Character
	if not char and RunService:IsStudio() then
		char = localPlayer.Character
	end
	if char then
		local variant = remotes:GetAttribute("WinFxVariant") or 1
		WinFx.play(variant, char)
	end
end

local function mainOnLand(s: any)
	print("[LuckyDraw] spin -> " .. s.winnerName)
	hasSpun = true
	setSpinIdle(true)
	playWinFx(s)
end

local function restoreMain(s: any)
	local seq = s.seq
	endReel(mainReel)
	setTileContent(mainReel.template, seq[WIN_INDEX - 1])
	setTileContent(mainReel.centre, seq[WIN_INDEX])
	setTileContent(mainReel.row2, seq[WIN_INDEX + 1])
	setNamesShown(mainReel.template, false, false)
	setNamesShown(mainReel.centre, true, false)
	setNamesShown(mainReel.row2, false, false)
end

-- ============================================================
-- Toast
-- ============================================================
local toastTween: any = nil

local function setProgress(p: number)
	if not progressGradient then
		return
	end
	local P = clamp(p, 0, 0.999)
	progressGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(P, 0),
		NumberSequenceKeypoint.new(P + 0.001, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local function toastRelease()
	endReel(toastReel)
	toast.Visible = false
end

local function toastHide(animated: boolean)
	if toastTween then
		toastTween:Cancel()
		toastTween = nil
	end
	if not animated then
		toastRelease()
		return
	end
	local tw = TweenService:Create(
		toast,
		TweenInfo.new(0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.In),
		{ Position = TOAST_AWAY }
	)
	toastTween = tw
	tw.Completed:Connect(function(st)
		if st == Enum.PlaybackState.Completed then
			toastRelease()
		end
	end)
	tw:Play()
end

local function toastShowFor(hostName: string)
	if toastTween then
		toastTween:Cancel()
		toastTween = nil
	end
	setProgress(0)
	toast.Visible = true
	toast.Position = TOAST_AWAY
	toastTitle.Text = spinningTitle(hostName)
	local tw = TweenService:Create(
		toast,
		TweenInfo.new(0.8, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
		{ Position = TOAST_HOME }
	)
	toastTween = tw
	tw:Play()
end

local function toastOnLand(s: any)
	toastTitle.Text = wonTitle(s.winnerName)
end

local function toastOnDone(_s: any)
	toastHide(true)
end

-- ============================================================
-- Panel open / close / drag
-- ============================================================
local panelOpen = false
local panelTween: any = nil

local function openPanel()
	if panelOpen then
		return
	end
	panelOpen = true
	refreshIdle()
	if mainReel.state == nil then
		startIdle()
	end
	root.Visible = true
	rootScale.Scale = 0.88
	root.Position = PANEL_AWAY
	if panelTween then
		panelTween:Cancel()
	end
	panelTween = TweenService:Create(root, TweenInfo.new(1.0, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), { Position = PANEL_HOME })
	panelTween:Play()
end

local function closePanel()
	if not panelOpen then
		return
	end
	panelOpen = false
	if panelTween then
		panelTween:Cancel()
	end
	local tw = TweenService:Create(root, TweenInfo.new(0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), { Position = PANEL_AWAY })
	panelTween = tw
	tw.Completed:Connect(function(st)
		if st == Enum.PlaybackState.Completed and not panelOpen then
			stopIdle()
			root.Visible = false
		end
	end)
	tw:Play()
end

local dragging = false
local dragStart: any = nil
local startPos: any = nil

dragHandle.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = root.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

UserInputService.InputChanged:Connect(function(input: InputObject)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local d = input.Position - dragStart
		root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, _gp: boolean)
	if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
		closePanel()
	end
end)

panelClose.Activated:Connect(closePanel)
toastClose.Activated:Connect(function()
	toastHide(false)
end)

-- ============================================================
-- Spin requests and broadcasts
-- ============================================================
spinButton.Activated:Connect(function()
	if spinBusy then
		return
	end
	setSpinBusy()
	requestEvent:FireServer({ type = "spin" })
	task.delay(PENDING_TIMEOUT, function()
		-- No broadcast arrived (rejected server-side): restore the button.
		if spinBusy and mainReel.state == nil then
			setSpinIdle(hasSpun)
		end
	end)
end)

broadcastEvent.OnClientEvent:Connect(function(data: any)
	if type(data) ~= "table" or data.type ~= "spin" then
		return
	end
	local seq = buildStrip(data.pool, data.winnerIndex, data.seed)
	setSpinBusy()
	stopIdle()
	beginReel(mainReel, seq, data, { hold = HOLD_SECONDS, onLand = mainOnLand, onDone = restoreMain })
	toastShowFor(data.host.displayName)
	beginReel(toastReel, seq, data, { hold = HOLD_SECONDS, onLand = toastOnLand, onDone = toastOnDone })
end)

-- ============================================================
-- Startup
-- ============================================================
root.Visible = false
toast.Visible = false
setProgress(0)
refreshIdle()

local openEvent = Instance.new("BindableEvent")
openEvent.Name = "Open"
openEvent.Parent = gui
openEvent.Event:Connect(openPanel)

local testWinFx = Instance.new("BindableEvent")
testWinFx.Name = "TestWinFx"
testWinFx.Parent = gui
testWinFx.Event:Connect(function(variant: any)
	if WinFx and localPlayer.Character then
		WinFx.play(tonumber(variant) or 1, localPlayer.Character)
	end
end)

Players.PlayerAdded:Connect(function()
	task.defer(refreshIdle)
end)
Players.PlayerRemoving:Connect(function()
	task.defer(refreshIdle)
end)

-- One RenderStepped connection drives both reels and the toast progress beam.
RunService.RenderStepped:Connect(function(dt: number)
	local now = os.clock()
	stepIdle(dt)
	local serverNow = workspace:GetServerTimeNow()
	stepReel(mainReel, serverNow, now)
	stepReel(toastReel, serverNow, now)
	local ts = toastReel.state
	if ts then
		setProgress(clamp((serverNow - ts.startAt) / ts.duration, 0, 1))
	end
end)
