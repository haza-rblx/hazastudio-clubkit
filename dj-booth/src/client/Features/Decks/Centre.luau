--!strict
-- The centre column (the original design, stretched to the top): a rolling loudness history per
-- deck in two lanes, a red playhead at 35 %, and two LED meters a side reading each deck's
-- PlaybackLoudness. Updated per frame imperatively (hundreds of segments), only while shown.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Vide = require(ReplicatedStorage.HazaDJ.Packages.Vide)
local Theme = require(script.Parent.Parent.Parent.Theme)
local Base = require(script.Parent.Parent.Parent.UI.Base)
local Model = require(script.Parent.Model)

local C = Theme.C

local Centre = {}

local W, H = 374, 231
local VUW = 5
local SEGS, PITCH = 151, 2 -- 138 for the lane plus the 13 that fill the 26 px head band
local DIM = Color3.fromHex("313131")
local LANE = Color3.fromHex("151515")
local N, HIST_P = 128, 45 -- history rows; the newest sits on row 45 (the playhead, 35 % down)
local LOW, MIDC, HIGH = Color3.fromRGB(228, 16, 36), Color3.fromRGB(105, 105, 105), Color3.fromRGB(104, 104, 104)

local function segColor(i: number): Color3
	local t = i / 138
	return if t < 0.6
		then Color3.fromRGB(200, 200, 200)
		elseif t < 0.85 then Color3.fromRGB(255, 255, 255)
		else Color3.fromRGB(228, 16, 36)
end

local function meter(x: number, anchor: number): (Frame, { Frame })
	local segs = {}
	local f = Base.new("Frame", {
		Size = UDim2.new(0, VUW, 1, 0),
		AnchorPoint = Vector2.new(anchor, 0),
		Position = UDim2.new(anchor, x, 0, 0),
		BackgroundColor3 = LANE,
	})
	for i = 1, SEGS do
		segs[i] = Base.new("Frame", {
			Size = UDim2.new(1, 0, 0, 1),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -(i - 1) * PITCH),
			BackgroundColor3 = DIM,
			ZIndex = 2,
			Parent = f,
		})
	end
	return f, segs
end

local function lane(x: number, xOff: number, wOff: number): (Frame, { Frame })
	local rows = {}
	local strip = Base.frame({ Size = UDim2.fromScale(1, 1) })
	for i = 1, N do
		rows[i] = Base.new("Frame", {
			Size = UDim2.new(0, 0, 1 / N, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, (i - 1) / N),
			BackgroundColor3 = HIGH,
			BackgroundTransparency = 0.1,
			Parent = strip,
		})
	end
	return Base.new("Frame", {
		Size = UDim2.new(0.5, wOff, 1, 0),
		Position = UDim2.new(x, xOff, 0, 0),
		BackgroundColor3 = LANE,
		ClipsDescendants = true,
		strip,
	}),
		rows
end

function Centre.new(props: Base.Props?): Frame
	local mA1, segA1 = meter(0, 0)
	local mA2, segA2 = meter(6, 0)
	local mB1, segB1 = meter(0, 1)
	local mB2, segB2 = meter(-6, 1)
	local laneA, rowsA = lane(0, 12, -13)
	local laneB, rowsB = lane(0.5, 0, -12)
	local body = Base.frame({
		Size = UDim2.fromScale(1, 1),
		mA1,
		mA2,
		mB1,
		mB2,
		laneA,
		laneB,
		Base.new("Frame", {
			Size = UDim2.new(1, 0, 0, 2),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.35),
			BackgroundColor3 = C.red,
			ZIndex = 5,
		}),
	})
	local root = Base.new(
		"Frame",
		Base.with({
			Name = "Centre",
			Size = UDim2.fromOffset(W, H),
			ClipsDescendants = true,
			BackgroundColor3 = Color3.fromHex("090909"),
			body,
		}, props)
	)

	-- meters: lit count per side, painted only when it changes
	local lit = { -1, -1 }
	local function paint(side: number, n: number)
		if lit[side] == n then
			return
		end
		lit[side] = n
		local cols = if side == 1 then { segA1, segA2 } else { segB1, segB2 }
		for _, segs in cols do
			for i, s in segs do
				-- the 13 top segments follow the 138th, as in the prototype
				local on = if i > 138 then n >= 138 else i <= n
				s.BackgroundColor3 = if on then segColor(math.min(i, 138)) else DIM
			end
		end
	end
	local hist = { {}, {} } :: { { number } }
	local function push(rows: { Frame }, h: { number }, level: number)
		for k = HIST_P, 2, -1 do
			h[k] = h[k - 1] or 0
		end
		h[1] = level
		for k = 1, HIST_P do
			local v = h[k] or 0
			local bar = rows[HIST_P - k + 1]
			bar.Size = UDim2.new(v * 0.96, 0, 1 / N, 0)
			bar.BackgroundColor3 = if v < 0.5 then HIGH:Lerp(MIDC, v * 2) else MIDC:Lerp(LOW, (v - 0.5) * 2)
		end
	end
	local lv = { 0, 0 }
	local acc = 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		if not root.Parent or not root:IsDescendantOf(game) then
			return
		end
		local a, b = Model.level(1), Model.level(2)
		acc += dt
		if acc >= 1 / 30 then
			acc %= 1 / 30
			push(rowsA, hist[1], a)
			push(rowsB, hist[2], b)
		end
		lv[1] = math.max(a * (0.85 + math.random() * 0.3), lv[1] - dt * 1.6)
		lv[2] = math.max(b * (0.85 + math.random() * 0.3), lv[2] - dt * 1.6)
		paint(1, math.floor(math.clamp(lv[1], 0, 1) * 138 + 0.5))
		paint(2, math.floor(math.clamp(lv[2], 0, 1) * 138 + 0.5))
	end)
	Vide.cleanup(function()
		conn:Disconnect()
	end)
	paint(1, 0)
	paint(2, 0)
	return root
end

-- the master level: the louder deck through the master fader (0..1)
function Centre.masterLevel(): number
	return math.max(Model.level(1), Model.level(2))
end

return Centre
