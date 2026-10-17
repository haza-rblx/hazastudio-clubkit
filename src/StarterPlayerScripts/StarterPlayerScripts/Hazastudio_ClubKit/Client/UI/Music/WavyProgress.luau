--!strict
-- PATH: StarterPlayerScripts/Client/UI/Music/WavyProgress.luau
-- Material You style wavy progress line over the Now Playing bar (owner, 2026-10-17, lab variant
-- "M3": wave, gap, vertical thumb, gap, flat track). The designed bar stays the source of truth:
-- NowPlayingView keeps tweening InnerBar.Size; this only hides the two frames and draws over them.
--
-- Cost: the wave is a static strip of short segments built once (and again only while the
-- amplitude eases in or out on play/pause), scrolled inside a clipping frame. A frame of motion is
-- a handful of property writes, and nothing runs while the panel is hidden or the wave is flat.
-- Every position is in Scale, not Offset: UDim offsets are whole pixels, so an offset-driven wave
-- crawls in visible 1 px steps.

local RunService = game:GetService("RunService")

local AMPLITUDE = 4 -- px, peak
local WAVELENGTH = 36 -- px
local THICKNESS = 4 -- px
local CYCLES_PER_SECOND = 0.7
local THUMB_WIDTH = 4
local THUMB_EXTRA_HEIGHT = 12
local GAP = 6 -- px between wave / thumb / track
local SEGMENT = 4 -- px per straight piece of the strip
local AMPLITUDE_EASE = 6 -- 1/s, how fast the wave flattens on pause / grows on play
local REBUILD_INTERVAL = 1 / 30

export type Deps = {
	fill: Frame, -- ProgressBar.InnerBar (Size.X.Scale = progress)
	startLabel: GuiObject, -- elapsed time label: the line starts at its left edge
	endLabel: GuiObject, -- length label: the line ends at its right edge
	isPlaying: () -> boolean,
}

local WavyProgress = {}
WavyProgress.__index = WavyProgress

local function newFrame(name: string, parent: Instance, zIndex: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundTransparency = 1
	frame.ZIndex = zIndex
	frame.Parent = parent
	return frame
end

local function newPill(name: string, parent: Instance, zIndex: number): Frame
	local frame = newFrame(name, parent, zIndex)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundTransparency = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	return frame
end

function WavyProgress.new(deps: Deps)
	local self = setmetatable({}, WavyProgress) :: any
	local bar = deps.fill.Parent :: Frame
	self._fill = deps.fill
	self._bar = bar
	self._startLabel = deps.startLabel
	self._endLabel = deps.endLabel
	self._isPlaying = deps.isPlaying
	self._screenGui = bar:FindFirstAncestorOfClass("ScreenGui")
	self._barTransparency = bar.BackgroundTransparency
	self._fillTransparency = deps.fill.BackgroundTransparency
	self._amp = 0
	self._builtAmp = -1
	self._builtKey = ""
	self._phase = 0
	self._rebuildAccum = 0
	self._stripLength = 0
	self._stripHeight = 0
	self._segments = {} :: { Frame }

	local z = deps.fill.ZIndex + 1
	local layer = newFrame("WavyProgress", bar, z)
	layer.Size = UDim2.fromScale(1, 1)
	-- 100 offset px measured in absolute px = the UIScale chain above the bar.
	local probe = newFrame("Probe", layer, z)
	probe.Size = UDim2.fromOffset(100, 0)
	local clip = newFrame("Clip", layer, z)
	clip.AnchorPoint = Vector2.new(0, 0.5)
	clip.ClipsDescendants = true
	local strip = newFrame("Strip", clip, z)
	self._layer, self._probe, self._clip, self._strip = layer, probe, clip, strip
	self._cap = newPill("StartCap", layer, z)
	self._track = newPill("Track", layer, z)
	self._track.AnchorPoint = Vector2.new(0, 0.5)
	self._thumb = newPill("Thumb", layer, z + 1)

	bar.BackgroundTransparency = 1
	deps.fill.BackgroundTransparency = 1

	self._conn = RunService.RenderStepped:Connect(function(dt: number)
		self:_step(dt)
	end)
	return self
end

function WavyProgress:_isShown(): boolean
	local gui = self._screenGui
	if gui and not gui.Enabled then
		return false
	end
	local node: Instance? = self._bar
	while node and node ~= gui do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return self._bar.AbsoluteSize.X > 0
end

-- The strip is longer than the line by one wavelength so it can scroll a full cycle.
function WavyProgress:_build(length: number, amp: number)
	local height = (AMPLITUDE + THICKNESS) * 2 + 4
	self._stripLength, self._stripHeight = length, height
	local color = self._fill.BackgroundColor3
	local mid = height / 2
	local k = 2 * math.pi / WAVELENGTH
	local count = math.ceil(length / SEGMENT)
	local segments = self._segments
	local px, py = 0, mid
	for i = 1, count do
		local x = i * SEGMENT
		local y = mid + amp * math.sin(k * x)
		local segment = segments[i]
		if not segment then
			segment = newFrame("Segment", self._strip, self._layer.ZIndex)
			segment.AnchorPoint = Vector2.new(0.5, 0.5)
			segment.BackgroundTransparency = 0
			segments[i] = segment
		end
		local dx, dy = x - px, y - py
		segment.Visible = true
		segment.BackgroundColor3 = color
		segment.Position = UDim2.fromScale((px + x) / 2 / length, (py + y) / 2 / height)
		-- +0.6 px overlaps neighbours so the joints never show a hairline gap.
		segment.Size = UDim2.fromScale((math.sqrt(dx * dx + dy * dy) + 0.6) / length, THICKNESS / height)
		segment.Rotation = math.deg(math.atan2(dy, dx))
		px, py = x, y
	end
	for i = count + 1, #segments do
		segments[i].Visible = false
	end
	self._builtAmp = amp
end

function WavyProgress:_step(dt: number)
	if not self:_isShown() then
		return
	end
	local scale = self._probe.AbsoluteSize.X / 100
	if scale <= 0 then
		return
	end
	local bar = self._bar
	local width = bar.AbsoluteSize.X / scale
	local height = bar.AbsoluteSize.Y / scale
	local function at(x: number, y: number): UDim2
		return UDim2.fromScale(x / width, y / height)
	end

	local target = if self._isPlaying() then AMPLITUDE else 0
	local amp = self._amp + (target - self._amp) * math.min(1, dt * AMPLITUDE_EASE)
	if math.abs(amp - target) < 0.05 then
		amp = target
	end
	self._amp = amp
	-- Paused and already flat: nothing moves until the bar does (seek, new track, resize).
	local progress = math.clamp(self._fill.Size.X.Scale, 0, 1)
	local sizeKey = bar.AbsoluteSize
	if amp == 0 and self._builtAmp == 0 and progress == self._lastProgress and sizeKey == self._lastSize then
		return
	end
	self._lastProgress = progress
	self._lastSize = sizeKey

	local barX = bar.AbsolutePosition.X
	local half = THICKNESS / 2
	local a = (self._startLabel.AbsolutePosition.X - barX) / scale + half
	local b = (self._endLabel.AbsolutePosition.X + self._endLabel.AbsoluteSize.X - barX) / scale - half
	local mid = height / 2

	self._rebuildAccum += dt
	local key = tostring(math.floor(b - a))
	if key ~= self._builtKey or (amp ~= self._builtAmp and self._rebuildAccum >= REBUILD_INTERVAL) then
		self._rebuildAccum = 0
		self._builtKey = key
		self:_build((b - a) + WAVELENGTH + SEGMENT, amp)
	end
	if amp > 0 then
		self._phase = (self._phase + dt * CYCLES_PER_SECOND) % 1
	end

	local fillX = a + progress * (b - a)
	local cut = THUMB_WIDTH / 2 + GAP
	local clipWidth = math.max(0.5, fillX - cut - a)

	-- The strip travels toward the thumb; the start cap rides the wave's first point.
	self._clip.Position = at(a, mid)
	self._clip.Size = UDim2.fromScale(clipWidth / width, self._stripHeight / height)
	self._strip.Size = UDim2.fromScale(self._stripLength / clipWidth, 1)
	self._strip.Position = UDim2.fromScale((self._phase - 1) * WAVELENGTH / clipWidth, 0)

	local fillColor = self._fill.BackgroundColor3
	local cap = self._cap
	cap.BackgroundColor3 = fillColor
	cap.Size = UDim2.fromScale(THICKNESS / width, THICKNESS / height)
	cap.Position = at(a, mid - amp * math.sin(2 * math.pi * self._phase))

	local thumb = self._thumb
	thumb.BackgroundColor3 = fillColor
	thumb.Size = UDim2.fromScale(THUMB_WIDTH / width, (THICKNESS + THUMB_EXTRA_HEIGHT) / height)
	thumb.Position = at(fillX, mid)

	local trackStart = math.min(b, fillX + cut)
	local track = self._track
	track.Visible = trackStart < b - 1
	track.BackgroundColor3 = bar.BackgroundColor3
	track.BackgroundTransparency = self._barTransparency
	track.Position = at(trackStart - half, mid)
	track.Size = UDim2.fromScale((b - trackStart + THICKNESS) / width, math.max(2, THICKNESS - 1) / height)
end

function WavyProgress:destroy()
	self._conn:Disconnect()
	self._layer:Destroy()
	self._bar.BackgroundTransparency = self._barTransparency
	self._fill.BackgroundTransparency = self._fillTransparency
end

return WavyProgress
