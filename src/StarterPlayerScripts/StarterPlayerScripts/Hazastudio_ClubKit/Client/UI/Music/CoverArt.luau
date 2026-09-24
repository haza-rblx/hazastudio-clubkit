--!strict
-- PATH: StarterPlayerScripts/Client/UI/Music/CoverArt.luau
-- The artwork of a kit-drawn track cover (ADR 0014): the CoverMesh gradient, drawn into an
-- EditableImage when the experience may use one, otherwise approximated by three UIGradient
-- layers. Nothing is uploaded anywhere.
--
-- EditableImage in a published experience needs the owner to be 13+ and ID-verified with
-- "Enable Mesh / Image APIs" on, so the gradient layers are not a degraded path to hide: they
-- are what most venues show. Every mount paints them first; the image replaces them when ready.
--
-- Images are built off a queue, a few rows per frame, and shared: one EditableImage per
-- key|mood serves every ImageLabel showing it (Content.fromObject). Tables that hold Instances
-- are strong and cleaned on Destroying (weak Instance keys vanish at random, see memory
-- roblox-weak-tables-instances).

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CoverMesh = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.CoverMesh)

local CoverArt = {}

-- v2 artwork is very soft (no detail finer than ~a third of the tile), so 48 px upscaled by the
-- engine looks the same as 128 and costs 7× less to draw (measured in Studio 2026-09-24: 1.6 s
-- per cover at 128 px, which would stall the queue).
local SIZE = 48
local CACHE_LIMIT = 64 -- 9 KB each: well under 1 MB of client memory, plus images still on screen
local FRAME_BUDGET_SECONDS = 0.002
local ART_NAME = "HzCoverArt"

type Entry = {
	id: string,
	mesh: CoverMesh.Mesh,
	editable: any?, -- EditableImage once built
	failed: boolean,
	users: { [ImageLabel]: true },
	lastUsed: number,
	queued: boolean,
}

local capability: boolean? = nil
local entries: { [string]: Entry } = {}
local entryCount = 0
local queue: { Entry } = {}
local worker: thread? = nil
local imageEntry: { [ImageLabel]: Entry } = {}
local imageCleanup: { [ImageLabel]: RBXScriptConnection } = {}

-- Studio testers can force the fallback: set attribute ForceGradient = true on this module.
local function forceGradient(): boolean
	return script:GetAttribute("ForceGradient") == true
end

function CoverArt.canUseEditableImage(): boolean
	if capability == nil then
		local ok, probe = pcall(function()
			return AssetService:CreateEditableImage({ Size = Vector2.new(1, 1) })
		end)
		capability = ok and probe ~= nil
		if ok and probe then
			pcall(function()
				(probe :: any):Destroy()
			end)
		end
	end
	return capability == true and not forceGradient()
end

local function color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- Keypoints at 0, 1/3, 2/3, 1: the lab's addColorStop(i / 3).
local function spread(colors: { { number } }): ColorSequence
	local points = {}
	for i, rgb in ipairs(colors) do
		table.insert(points, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), color(rgb)))
	end
	return ColorSequence.new(points)
end

local function addCorner(target: GuiObject, corner: UDim?, corners: { UICorner })
	if corner then
		local c = Instance.new("UICorner")
		c.CornerRadius = corner
		c.Parent = target
		table.insert(corners, c)
	end
end

local function paintGradientLayers(image: ImageLabel, mesh: CoverMesh.Mesh, corner: UDim?, corners: { UICorner })
	local layers = CoverMesh.gradientLayers(mesh)
	image.BackgroundColor3 = Color3.new(1, 1, 1)
	image.BackgroundTransparency = 0
	local rows = Instance.new("UIGradient")
	rows.Name = "Rows"
	rows.Rotation = 90
	rows.Color = spread(layers.rows)
	rows.Parent = image

	local cols = Instance.new("Frame")
	cols.Name = "HzCols"
	cols.BorderSizePixel = 0
	cols.Size = UDim2.fromScale(1, 1)
	cols.BackgroundColor3 = Color3.new(1, 1, 1)
	cols.BackgroundTransparency = 0.45 -- the lab's 0.55 alpha
	local colsGradient = Instance.new("UIGradient")
	colsGradient.Color = spread(layers.cols)
	colsGradient.Parent = cols
	addCorner(cols, corner, corners)
	cols.Parent = image

	local diagonal = Instance.new("Frame")
	diagonal.Name = "HzDiagonal"
	diagonal.BorderSizePixel = 0
	diagonal.Size = UDim2.fromScale(1, 1)
	diagonal.BackgroundColor3 = Color3.new(1, 1, 1)
	local diagonalGradient = Instance.new("UIGradient")
	diagonalGradient.Rotation = 45
	diagonalGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color(layers.topLeft)),
		ColorSequenceKeypoint.new(0.499, color(layers.topLeft)),
		ColorSequenceKeypoint.new(0.501, color(layers.bottomRight)),
		ColorSequenceKeypoint.new(1, color(layers.bottomRight)),
	})
	diagonalGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(1, 0.5),
	})
	diagonalGradient.Parent = diagonal
	addCorner(diagonal, corner, corners)
	diagonal.Parent = image
end

local function clearGradientLayers(image: ImageLabel)
	local rows = image:FindFirstChild("Rows")
	if rows then
		rows:Destroy()
	end
	for _, name in ipairs({ "HzCols", "HzDiagonal" }) do
		local layer = image:FindFirstChild(name)
		if layer then
			layer:Destroy()
		end
	end
	image.BackgroundTransparency = 1
end

local function showImage(image: ImageLabel, entry: Entry)
	if imageEntry[image] ~= entry or not entry.editable then
		return
	end
	image.ImageContent = Content.fromObject(entry.editable)
	clearGradientLayers(image)
end

local function evict()
	if entryCount <= CACHE_LIMIT then
		return
	end
	local idle: { Entry } = {}
	for _, entry in pairs(entries) do
		if next(entry.users) == nil and not entry.queued then
			table.insert(idle, entry)
		end
	end
	table.sort(idle, function(a, b)
		return a.lastUsed < b.lastUsed
	end)
	for _, entry in ipairs(idle) do
		if entryCount <= CACHE_LIMIT then
			break
		end
		entries[entry.id] = nil
		entryCount -= 1
		if entry.editable then
			pcall(function()
				entry.editable:Destroy()
			end)
		end
	end
end

-- Builds queued images, FRAME_BUDGET_SECONDS of pixel work per frame.
local function runQueue()
	while #queue > 0 do
		local entry = table.remove(queue, 1) :: Entry
		entry.queued = false
		if next(entry.users) == nil or entry.editable or entry.failed then
			continue
		end
		local ok, editable = pcall(function()
			return AssetService:CreateEditableImage({ Size = Vector2.new(SIZE, SIZE) })
		end)
		if not ok or not editable then
			-- Out of image budget on this device: this cover keeps its gradient layers.
			entry.failed = true
			continue
		end
		local pixels = buffer.create(SIZE * SIZE * 4)
		local started = os.clock()
		for y = 0, SIZE - 1 do
			for x = 0, SIZE - 1 do
				local r, g, b = CoverMesh.pixel(entry.mesh, x, y, SIZE)
				local k = (y * SIZE + x) * 4
				buffer.writeu8(pixels, k, r)
				buffer.writeu8(pixels, k + 1, g)
				buffer.writeu8(pixels, k + 2, b)
				buffer.writeu8(pixels, k + 3, 255)
			end
			if os.clock() - started > FRAME_BUDGET_SECONDS then
				RunService.Heartbeat:Wait()
				started = os.clock()
			end
		end
		local written = pcall(function()
			(editable :: any):WritePixelsBuffer(Vector2.zero, Vector2.new(SIZE, SIZE), pixels)
		end)
		if not written then
			entry.failed = true
			pcall(function()
				(editable :: any):Destroy()
			end)
			continue
		end
		entry.editable = editable
		for image in pairs(entry.users) do
			showImage(image, entry)
		end
		evict()
		-- One finished image per frame at most (engine: one EditableImage update per frame).
		RunService.Heartbeat:Wait()
	end
	worker = nil
end

local function release(image: ImageLabel)
	local entry = imageEntry[image]
	if entry then
		entry.users[image] = nil
		imageEntry[image] = nil
	end
	local connection = imageCleanup[image]
	if connection then
		connection:Disconnect()
		imageCleanup[image] = nil
	end
end

-- Creates the artwork as a full-size ImageLabel under parent and returns it with the UICorners
-- it made (so the caller can rescale radii). corner: nil = square (the parent clips it).
function CoverArt.mount(parent: GuiObject, key: string, mood: string, corner: UDim?): (ImageLabel, { UICorner })
	local id = key .. "|" .. mood
	local entry = entries[id]
	if not entry then
		entry = {
			id = id,
			mesh = CoverMesh.build(key, mood :: any),
			editable = nil,
			failed = false,
			users = {},
			lastUsed = os.clock(),
			queued = false,
		}
		entries[id] = entry
		entryCount += 1
	end
	local current = entry :: Entry
	current.lastUsed = os.clock()

	local corners: { UICorner } = {}
	local image = Instance.new("ImageLabel")
	image.Name = ART_NAME
	image.BorderSizePixel = 0
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	-- The artwork is square; a wide or tall slot (ticket panel, list card) crops it rather than
	-- squashing it (owner, 2026-09-24: "gepeng").
	image.ScaleType = Enum.ScaleType.Crop
	addCorner(image, corner, corners)

	current.users[image] = true
	imageEntry[image] = current
	imageCleanup[image] = image.Destroying:Connect(function()
		release(image)
	end)

	if current.editable and CoverArt.canUseEditableImage() then
		image.ImageContent = Content.fromObject(current.editable)
	else
		paintGradientLayers(image, current.mesh, corner, corners)
		if not current.failed and not current.queued and CoverArt.canUseEditableImage() then
			current.queued = true
			table.insert(queue, current)
			if not worker then
				worker = task.spawn(runQueue)
			end
		end
	end
	image.Parent = parent
	return image, corners
end

function CoverArt.meshFor(key: string, mood: string): CoverMesh.Mesh
	local entry = entries[key .. "|" .. mood]
	if entry then
		return entry.mesh
	end
	return CoverMesh.build(key, mood :: any)
end

return CoverArt
