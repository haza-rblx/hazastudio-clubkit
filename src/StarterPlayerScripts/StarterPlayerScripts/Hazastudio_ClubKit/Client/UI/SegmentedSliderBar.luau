--!strict
-- Settings slider look (owner 2026-10-07): a dark box of thin vertical segments that light up to
-- the value — accent fill, white on Multicolor / Graphite. The slider logic is unchanged: it still
-- sizes the (now invisible) AdjustableFrameWidth fill, and the segments follow that fill's width.
--
-- Segments are laid out in whole screen pixels (5px wide, 3px apart, 6px inset), rebuilt when the
-- box changes size. Scale-based widths (1/N of the box) rounded differently per segment and read
-- as uneven bars. The box should be a plain Frame: inside a CanvasGroup the bars are drawn into a
-- texture placed at a fractional position and still look uneven (GUI fix ships with the RBXM).
--
-- Under a UIScale (07-MenuGUI 0.95) the box sits on fractional screen pixels, and dividing pixel
-- offsets by the scale does not help: UDim offsets are integers, so 5 / 0.95 was stored as 5 and
-- drew 4.75px (measured 2026-10-07). Every position/size is therefore a Scale of the box, aimed at
-- the box's rounded screen edges, and re-aimed when the box moves.

local AccentService = require(script.Parent.Parent.Services.AccentService)

local SegmentedSliderBar = {}

local SEGMENT_WIDTH = 5
local SEGMENT_GAP = 3
local INSET = 6
local SEGMENT_CORNER = 2
local DIM_TRANSPARENCY = 0.88
local BOX_COLOR = Color3.fromRGB(28, 28, 30)

-- `vertical` (dance panel on phones, 2026-10-09): the segments are horizontal bars stacked bottom to
-- top and light up with the fill's height.
function SegmentedSliderBar.attach(box: GuiObject, fill: GuiObject, vertical: boolean?)
	if box:FindFirstChild("Segments") then
		return
	end
	-- Darker box than the old pill track so lit segments carry the contrast (tinted like any surface).
	box.BackgroundColor3 = BOX_COLOR
	box.BackgroundTransparency = 0
	fill.BackgroundTransparency = 1
	local knob = fill:FindFirstChild("DraggableIcon")
	if knob and knob:IsA("ImageLabel") then
		knob.ImageTransparency = 1
	end

	local holder = Instance.new("Frame")
	holder.Name = "Segments"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = fill.ZIndex + 1
	-- Painted from the accent here; the whole-GUI theme must not recolour them.
	holder:SetAttribute("AccentNoTint", true)
	holder.Parent = box

	local segments: { Frame } = {}

	local function paint()
		local count = #segments
		local value = if vertical then fill.Size.Y.Scale else fill.Size.X.Scale
		local lit = math.round(math.clamp(value, 0, 1) * count)
		local on = if AccentService.isDesign() then Color3.new(1, 1, 1) else AccentService.get().fill
		for index, segment in ipairs(segments) do
			segment.BackgroundColor3 = on
			segment.BackgroundTransparency = if index <= lit then 0 else DIM_TRANSPARENCY
		end
	end

	local function setCount(count: number)
		if count == #segments then
			return
		end
		for _, segment in ipairs(segments) do
			segment:Destroy()
		end
		table.clear(segments)
		for _ = 1, count do
			local segment = Instance.new("Frame")
			segment.Name = "Segment"
			segment.BorderSizePixel = 0
			segment.ZIndex = holder.ZIndex
			local corner = Instance.new("UICorner")
			-- Scale of the segment's narrow side, so the radius stays 2 screen px under any UIScale.
			corner.CornerRadius = UDim.new(SEGMENT_CORNER / SEGMENT_WIDTH, 0)
			corner.Parent = segment
			segment.Parent = holder
			table.insert(segments, segment)
		end
		paint()
	end

	local lastKey = ""
	local function layout()
		local position, size = box.AbsolutePosition, box.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local key = string.format("%.3f,%.3f,%.3f,%.3f", position.X, position.Y, size.X, size.Y)
		if key == lastKey then
			return
		end
		lastKey = key
		-- The box's edges as drawn, in whole screen pixels.
		local left = math.floor(position.X + 0.5)
		local top = math.floor(position.Y + 0.5)
		local width = math.floor(position.X + size.X + 0.5) - left
		local height = math.floor(position.Y + size.Y + 0.5) - top
		if width <= INSET * 2 or height <= INSET * 2 then
			setCount(0)
			return
		end
		if vertical then
			-- Same rules with the axes swapped; segment 1 sits at the bottom.
			local inner = height - INSET * 2
			local count = math.floor((inner + SEGMENT_GAP) / (SEGMENT_WIDTH + SEGMENT_GAP))
			local used = count * SEGMENT_WIDTH + (count - 1) * SEGMENT_GAP
			local startY = INSET + math.floor((inner - used) / 2)
			local marginSide = startY
			local segmentWidth = width - marginSide * 2
			if segmentWidth < 8 then
				segmentWidth = width - INSET * 2
				marginSide = INSET
			end
			local boxCorner = box:FindFirstChildWhichIsA("UICorner")
			if boxCorner then
				boxCorner.CornerRadius = UDim.new((marginSide + SEGMENT_CORNER) / math.min(size.X, size.Y), 0)
			end
			setCount(count)
			local segmentX = (left + marginSide - position.X) / size.X
			for index, segment in ipairs(segments) do
				local y = top + height - startY - index * SEGMENT_WIDTH - (index - 1) * SEGMENT_GAP
				segment.Position = UDim2.fromScale(segmentX, (y - position.Y) / size.Y)
				segment.Size = UDim2.fromScale(segmentWidth / size.X, SEGMENT_WIDTH / size.Y)
			end
			return
		end
		local inner = width - INSET * 2
		local count = math.floor((inner + SEGMENT_GAP) / (SEGMENT_WIDTH + SEGMENT_GAP))
		local used = count * SEGMENT_WIDTH + (count - 1) * SEGMENT_GAP
		local startX = INSET + math.floor((inner - used) / 2)
		-- The leftover pixels widen the left/right margins; match top/bottom to them so the box
		-- has the same inner margin on all four sides (owner 2026-10-07). Top and bottom both take
		-- the left margin: using left + right made the bottom 1px wider whenever the leftover was
		-- odd (44px dance bar: 9 top / 10 bottom, owner "yang bawah terlalu lebar").
		local marginLeft = startX
		local segmentHeight = height - marginLeft * 2
		local marginTop = marginLeft
		if segmentHeight < 8 then
			segmentHeight = height - INSET * 2
			marginTop = INSET
		end
		-- Concentric corners: box radius = inner margin + the segments' own radius.
		local boxCorner = box:FindFirstChildWhichIsA("UICorner")
		if boxCorner then
			boxCorner.CornerRadius = UDim.new((marginTop + SEGMENT_CORNER) / math.min(size.X, size.Y), 0)
		end
		setCount(count)
		local segmentY = (top + marginTop - position.Y) / size.Y
		for index, segment in ipairs(segments) do
			local x = left + startX + (index - 1) * (SEGMENT_WIDTH + SEGMENT_GAP)
			segment.Position = UDim2.fromScale((x - position.X) / size.X, segmentY)
			segment.Size = UDim2.fromScale(SEGMENT_WIDTH / size.X, segmentHeight / size.Y)
		end
	end

	local sizeConnection = box:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	local positionConnection = box:GetPropertyChangedSignal("AbsolutePosition"):Connect(layout)
	local fillConnection = fill:GetPropertyChangedSignal("Size"):Connect(paint)
	local unsubscribe = AccentService.subscribe(function()
		paint()
	end)
	box.Destroying:Connect(function()
		sizeConnection:Disconnect()
		positionConnection:Disconnect()
		fillConnection:Disconnect()
		unsubscribe()
	end)
	layout()
	task.defer(layout)
end

return SegmentedSliderBar
