--!strict
-- Idle life for workspace boards and posters, all client-side and cheap:
--   * glows — the images GradientLight1 / GradientDarkCenter / GradientLight2 (direct children of the
--     SurfaceGui) drift on long, unrelated periods, so the three colour pools keep re-mixing like a
--     mesh gradient;
--   * podium avatars sway in a wave across the three ranks (a couple's two heads bob in turn);
--   * the colour band in each podium bar's own UIGradient drifts up and down;
--   * the #1 figure gives a small pop now and then.
-- Only what the board already has is moved; nothing is added to it.
-- One Heartbeat drives every board, a few times per frame budget, and only boards near the camera and
-- in front of it; everything else sits at its designed state. Reduced motion keeps every board still.
-- A SurfaceGui opts out with the attribute `AmbientGlow = false`.

local RunService = game:GetService("RunService")

local UIMotion = require(script.Parent.Parent.Utils.UIMotion)

local GLOW_NAMES = { "GradientLight1", "GradientDarkCenter", "GradientLight2" }
local THUMB_NAMES: { [string]: boolean } = {
	PlayerImageThumbnail = true,
	PlayerThumbnailImage = true,
	PlayerThumbnailIcon = true,
	PlayerThumbnail = true,
	PlayerThumbnailPic = true,
	PlayerProfileThumbnail = true,
	PlayerProfilePicture = true,
	ProfilePicture = true,
	CommunityIcon = true,
}
local UPDATE_INTERVAL = 1 / 30
local MAX_DISTANCE = 140
local TAU = math.pi * 2

-- Per-glow motion, in the SurfaceGui's scale units and seconds; periods share no common factor so the
-- three never line up into a visible loop. The side glows reach past the centre so the three colours
-- trade places over time instead of each swaying in its own corner.
local MOTION = {
	{ ampX = 0.38, ampY = 0.16, periodX = 9, periodY = 11, breathe = 0.1, periodBreathe = 8 },
	{ ampX = 0.3, ampY = 0.18, periodX = 13, periodY = 7, breathe = 0.12, periodBreathe = 10 },
	{ ampX = 0.42, ampY = 0.14, periodX = 11, periodY = 15, breathe = 0.08, periodBreathe = 12 },
}
local SWAY_PERIOD = 3.4
local BOB_PERIOD = 2.6
local BAND_PERIOD = 5.2
local BAND_SHIFT = 0.12
local POP_EVERY = 9
local POP_TIME = 0.45

type Glow = { image: ImageLabel, position: UDim2, size: UDim2, motion: typeof(MOTION[1]), phase: number }
type Sway = { object: GuiObject, rotation: number, amount: number, phase: number }
type Bob = { object: GuiObject, position: UDim2, rotation: number, lift: number, tilt: number, period: number, phase: number }
type Band = { gradient: UIGradient, offset: Vector2, phase: number }
type Pop = { label: TextLabel, size: number }

type Board = {
	gui: SurfaceGui,
	phase: number,
	glows: { Glow },
	sways: { Sway },
	bobs: { Bob },
	bands: { Band },
	pops: { Pop },
	resting: boolean,
	connection: RBXScriptConnection,
}

local BoardAmbience = {}

local boards: { [SurfaceGui]: Board } = {}
local connections: { RBXScriptConnection } = {}
local started = false

local function boardPart(gui: SurfaceGui): BasePart?
	local adornee = gui.Adornee
	if adornee and adornee:IsA("BasePart") then
		return adornee
	end
	local parent = gui.Parent
	if parent and parent:IsA("BasePart") then
		return parent
	end
	return nil
end

local function seedOf(text: string): number
	local seed = 0
	for _, byte in ipairs({ string.byte(text, 1, -1) }) do
		seed = (seed * 31 + byte) % 10007
	end
	return seed
end

local function rest(board: Board)
	if board.resting then
		return
	end
	board.resting = true
	for _, glow in ipairs(board.glows) do
		glow.image.Position = glow.position
		glow.image.Size = glow.size
	end
	for _, sway in ipairs(board.sways) do
		sway.object.Rotation = sway.rotation
	end
	for _, bob in ipairs(board.bobs) do
		bob.object.Position = bob.position
		bob.object.Rotation = bob.rotation
	end
	for _, band in ipairs(board.bands) do
		band.gradient.Offset = band.offset
	end
	for _, pop in ipairs(board.pops) do
		pop.label.TextSize = pop.size
	end
end

local function findValueLabel(card: Instance, podium: Instance): TextLabel?
	for _, d in ipairs(card:GetDescendants()) do
		if
			d:IsA("TextLabel")
			and d.Name ~= "ValueIcon"
			and not d:IsDescendantOf(podium)
			and (d.Name:find("Total") or d.Name:find("Value"))
		then
			return d
		end
	end
	return nil
end

local function discoverPodium(board: Board)
	local wrapper = board.gui:FindFirstChild("TopThreeCardWrapper", true)
	if not wrapper then
		return
	end
	type Entry = { card: GuiObject, podium: GuiObject, height: number }
	local ranked: { Entry } = {}
	for _, card in ipairs(wrapper:GetChildren()) do
		if card:IsA("GuiObject") then
			local podium = card:FindFirstChild("Podium", true)
			if podium and podium:IsA("GuiObject") then
				table.insert(ranked, { card = card, podium = podium, height = podium.Size.Y.Scale })
			end
		end
	end
	-- The tallest bar is #1.
	table.sort(ranked, function(a, b)
		return a.height > b.height
	end)
	for rank, entry in ipairs(ranked) do
		local holder = entry.card:FindFirstChild("CoupleAvatars", true)
		if holder then
			local index = 0
			for _, image in ipairs(holder:GetChildren()) do
				if image:IsA("ImageLabel") then
					index += 1
					table.insert(board.bobs, {
						object = image,
						position = image.Position,
						rotation = image.Rotation,
						lift = 3,
						tilt = 3,
						period = BOB_PERIOD,
						phase = rank * 1.1 + index * math.pi,
					})
				end
			end
		else
			for _, d in ipairs(entry.card:GetDescendants()) do
				if d:IsA("ImageLabel") and THUMB_NAMES[d.Name] and not d:IsDescendantOf(entry.podium) then
					table.insert(board.sways, {
						object = d,
						rotation = d.Rotation,
						amount = if rank == 1 then 4 else 3,
						phase = rank * 1.3,
					})
					break
				end
			end
		end
		local gradient = entry.podium:FindFirstChildOfClass("UIGradient")
		if gradient then
			table.insert(board.bands, { gradient = gradient, offset = gradient.Offset, phase = rank * 0.9 })
		end
		if rank == 1 then
			local label = findValueLabel(entry.card, entry.podium)
			if label then
				table.insert(board.pops, { label = label, size = label.TextSize })
			end
		end
	end
end

local function track(gui: SurfaceGui)
	if boards[gui] or gui:GetAttribute("AmbientGlow") == false then
		return
	end
	local seed = seedOf(gui:GetFullName())
	local board: Board = {
		gui = gui,
		phase = seed % 97 / 97,
		glows = {},
		sways = {},
		bobs = {},
		bands = {},
		pops = {},
		resting = true,
		connection = gui.Destroying:Connect(function()
			local entry = boards[gui]
			if entry then
				entry.connection:Disconnect()
				boards[gui] = nil
			end
		end),
	}
	for index, name in ipairs(GLOW_NAMES) do
		local image = gui:FindFirstChild(name)
		if image and image:IsA("ImageLabel") then
			table.insert(board.glows, {
				image = image,
				position = image.Position,
				size = image.Size,
				motion = MOTION[index],
				-- A different start per board, so a wall of boards does not move in lockstep.
				phase = (seed * 0.731 + index * 2.17) % TAU,
			})
		end
	end
	discoverPodium(board)
	if #board.glows + #board.sways + #board.bobs + #board.bands + #board.pops == 0 then
		board.connection:Disconnect()
		return
	end
	boards[gui] = board
end

local function consider(instance: Instance)
	if instance:IsA("SurfaceGui") then
		-- Children may still be streaming in; look once they have had a frame to arrive.
		task.defer(track, instance)
	end
end

local function visible(gui: SurfaceGui, camera: Camera): boolean
	if not gui.Enabled then
		return false
	end
	local part = boardPart(gui)
	if not part then
		return false
	end
	local offset = part.Position - camera.CFrame.Position
	if offset.Magnitude > MAX_DISTANCE + part.Size.Magnitude * 0.5 then
		return false
	end
	-- In front of the camera, with a margin for a board half out of frame.
	return offset.Unit:Dot(camera.CFrame.LookVector) > 0.2
end

local function step(now: number)
	local camera = workspace.CurrentCamera
	local reduced = UIMotion.reduced()
	for _, board in pairs(boards) do
		if reduced or not camera or board.gui:GetAttribute("AmbientGlow") == false or not visible(board.gui, camera) then
			rest(board)
			continue
		end
		board.resting = false

		for _, glow in ipairs(board.glows) do
			local m = glow.motion
			local x = math.sin(now * TAU / m.periodX + glow.phase) * m.ampX
			local y = math.cos(now * TAU / m.periodY + glow.phase * 1.3) * m.ampY
			local grow = 1 + math.sin(now * TAU / m.periodBreathe + glow.phase) * m.breathe
			local p, s = glow.position, glow.size
			glow.image.Position = UDim2.new(p.X.Scale + x, p.X.Offset, p.Y.Scale + y, p.Y.Offset)
			glow.image.Size = UDim2.new(s.X.Scale * grow, s.X.Offset, s.Y.Scale * grow, s.Y.Offset)
		end

		for _, sway in ipairs(board.sways) do
			sway.object.Rotation = sway.rotation + math.sin(now * TAU / SWAY_PERIOD - sway.phase) * sway.amount
		end

		for _, bob in ipairs(board.bobs) do
			local wave = math.sin(now * TAU / bob.period + bob.phase)
			local p = bob.position
			bob.object.Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset - wave * bob.lift)
			bob.object.Rotation = bob.rotation + math.cos(now * TAU / (bob.period * 1.7) + bob.phase) * bob.tilt
		end

		for _, band in ipairs(board.bands) do
			local shift = math.sin(now * TAU / BAND_PERIOD - band.phase) * BAND_SHIFT
			band.gradient.Offset = band.offset + Vector2.new(0, shift)
		end

		local popClock = (now + board.phase * POP_EVERY) % POP_EVERY
		for _, pop in ipairs(board.pops) do
			if popClock < POP_TIME then
				local k = math.sin(math.pi * popClock / POP_TIME)
				pop.label.TextSize = math.floor(pop.size * (1 + 0.14 * k) + 0.5)
			elseif pop.label.TextSize ~= pop.size then
				pop.label.TextSize = pop.size
			end
		end
	end
end

function BoardAmbience.start()
	if started then
		return
	end
	started = true
	for _, instance in ipairs(workspace:GetDescendants()) do
		consider(instance)
	end
	table.insert(connections, workspace.DescendantAdded:Connect(consider))
	local elapsed = 0
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt: number)
			elapsed += dt
			if elapsed < UPDATE_INTERVAL then
				return
			end
			elapsed = 0
			step(os.clock())
		end)
	)
end

function BoardAmbience.stop()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, board in pairs(boards) do
		rest(board)
		board.connection:Disconnect()
	end
	table.clear(boards)
	started = false
end

return BoardAmbience
