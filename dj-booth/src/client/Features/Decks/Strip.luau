--!strict
-- The hardware strip "C" (owner, 2026-10-22), 1250 x 130. Per deck: CUE over PLAY on the outer
-- edge, eight round hot cues, a rule, and the deck's FX unit (ECHO · REVERB · FLANGER faders).
-- Centre: A · crossfader · B on top; MASTER (its groove is the stereo meter) and CURVE below.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Vide = require(ReplicatedStorage.HazaDJ.Packages.Vide)
local Store = require(script.Parent.Parent.Parent.Store)
local Actions = require(script.Parent.Parent.Parent.Actions)
local Theme = require(script.Parent.Parent.Parent.Theme)
local Base = require(script.Parent.Parent.Parent.UI.Base)
local Hardware = require(script.Parent.Parent.Parent.UI.Hardware)
local Model = require(script.Parent.Model)

local create = Vide.create
local C, W, B = Theme.C, Theme.W, Theme.B
local frame, label, corner = Base.frame, Base.label, Base.corner

local Strip = {}

local H = 130
-- the strip grew 16 px for the compact header: top tier +4, rules +11, bottom tier +18
local TOP, RULE, BOT = 4, 11, 18

local function cap11(text: any, x: number, y: number, color: any?, props: Base.Props?): TextLabel
	return label(
		text,
		Base.with(
			{ FontFace = B, TextSize = 11, TextColor3 = color or C.dim, Position = UDim2.fromOffset(x, y) },
			props
		)
	)
end

local function cell(x: number, w: number, children: { any }): Frame
	return Base.new(
		"Frame",
		{ Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(w, H), BackgroundColor3 = C.tile, children }
	)
end

local function pct(v: number): string
	return if v > 0.004 then math.floor(v * 100 + 0.5) .. "%" else "Off"
end

local function side(m: Model.Deck, x: number, mirror: boolean): Frame
	local kids = {}
	local ox = if mirror then 436 - 40 else 40
	local d = m.deck
	-- CUE: press and hold previews on the cue point; tap sets it (CDJ rules, on the server)
	local cue = Hardware.roundKey(ox, 30 + TOP, 40, C.soft, 2, "CUE", 11)
	cue.InputBegan:Connect(function(io)
		if Base.isPress(io) then
			m.run("CueDown")
		end
	end)
	cue.InputEnded:Connect(function(io)
		if Base.isPress(io) then
			m.run("CueUp")
		end
	end)
	table.insert(kids, cue)
	table.insert(
		kids,
		Hardware.roundKey(
			ox,
			80 + BOT,
			44,
			-- playing: a lit red rim, like a hit hot cue or a synced SYNC key
			function()
				return if d().playing then C.red else C.tile
			end,
			function()
				return if d().playing then 2 else 1
			end,
			function()
				return if d().playing then "" else "▶"
			end,
			16,
			function()
				return if d().playing then C.red else W
			end,
			{
				Activated = function()
					m.run(if Vide.untrack(d).playing then "Pause" else "Play")
				end,
				-- while playing the key shows a square (stop glyph) instead of the triangle
				Base.new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(12, 12),
					BackgroundColor3 = W,
					ZIndex = 2,
					Visible = function()
						return d().playing
					end,
					corner(2),
				}),
			}
		)
	)
	-- eight hot cues; deck B counts from its outer edge too
	local x0 = if mirror then 16 else 84
	local span = 436 - 84 - 16
	local step = span / 8
	for i = 1, 8 do
		local n = if mirror then 9 - i else i
		local isSet = function()
			local t = m.track()
			return t ~= nil and t.cues ~= nil and t.cues[tostring(n)] ~= nil
		end
		local isHit = function()
			return d().lastCue == n and isSet()
		end
		local key = Hardware.roundKey(
			math.floor(x0 + step * (i - 0.5)),
			30 + TOP,
			34,
			function()
				return if isHit() then C.red elseif isSet() then C.soft else C.tile
			end,
			function()
				return if isHit() then 2 else 1
			end,
			tostring(n),
			12,
			function()
				return if isSet() or isHit() then W else C.dim
			end,
			{
				Activated = function()
					Actions.send({ Kind = "HotCue", Deck = m.n, N = n, Clear = false })
				end,
				MouseButton2Click = function()
					Actions.send({ Kind = "HotCue", Deck = m.n, N = n, Clear = true })
				end,
			}
		)
		table.insert(kids, key)
	end
	table.insert(
		kids,
		Base.new(
			"Frame",
			{ Position = UDim2.fromOffset(x0, 56 + RULE), Size = UDim2.fromOffset(span, 1), BackgroundColor3 = C.line }
		)
	)
	-- the deck's FX unit: three short faders, caption and amount above each
	local fstep = span / 3
	for j, f in { { "ECHO", "Echo" }, { "REVERB", "Reverb" }, { "FLANGER", "Flanger" } } do
		local fx0 = math.floor(x0 + fstep * (j - 1) + 10)
		local fw = math.floor(fstep - 20)
		local v = m.value(f[2], function()
			return d().fx[j]
		end)
		table.insert(
			kids,
			cap11(f[1], fx0, 62 + BOT, function()
				return if v() > 0.004 then C.soft else C.dim
			end)
		)
		table.insert(
			kids,
			label(function()
				return pct(v())
			end, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromOffset(fx0 + fw, 62 + BOT),
				FontFace = B,
				TextSize = 11,
				TextColor3 = function()
					return if v() > 0.004 then W else C.faint
				end,
			})
		)
		table.insert(
			kids,
			Hardware.hfader(fx0, 74 + BOT, fw, v, function(x)
				m.set(f[2], x)
			end, 0)
		)
	end
	return cell(x, 436, kids)
end

local function centre(): Frame
	local s = Store.session
	local xf = function()
		return Store.localOr("1Xfader", s().xfader)
	end
	local master = function()
		return Store.localOr("1Master", s().master)
	end
	local curve = function()
		return Store.localOr("1Curve", s().curve)
	end
	-- crossfader: deep groove, a tall centre detent, A and B at the ends, a big light handle
	local ticks = {}
	for i = 0, 10 do
		local centreTick = i == 5
		for _, yy in { 0, 1 } do
			table.insert(
				ticks,
				Base.new("Frame", {
					AnchorPoint = Vector2.new(0.5, yy),
					Position = UDim2.fromScale(i / 10, yy),
					Size = UDim2.fromOffset(if centreTick then 2 else 1, if centreTick then 10 else 5),
					BackgroundColor3 = if centreTick then W else C.faint,
				})
			)
		end
	end
	local handle = Base.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.new(xf(), 13 - xf() * 26, 0.5, 0)
		end,
		Size = UDim2.fromOffset(26, 44),
		BackgroundColor3 = W,
		ZIndex = 5,
		corner(3),
		create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new(Color3.fromRGB(238, 238, 238), Color3.fromRGB(170, 170, 170)),
		}),
		create("UIStroke")({ Color = C.tile, Thickness = 1 }),
		Base.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.22, 0.5),
			Size = UDim2.fromOffset(1, 34),
			BackgroundColor3 = Color3.new(),
			BackgroundTransparency = 0.6,
			ZIndex = 6,
		}),
		Base.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.78, 0.5),
			Size = UDim2.fromOffset(1, 34),
			BackgroundColor3 = Color3.new(),
			BackgroundTransparency = 0.6,
			ZIndex = 6,
		}),
		Base.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(2, 38),
			BackgroundColor3 = C.ink,
			ZIndex = 6,
		}),
	})
	local xfFrame = frame({
		Position = UDim2.fromOffset(36, 6 + TOP),
		Size = UDim2.fromOffset(302, 46),
		Base.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, 0, 0, 6),
			BackgroundColor3 = C.groove,
		}),
		ticks,
		handle,
	})
	local xfHit = create("TextButton")({
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 26, 1, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		ZIndex = 7,
		Parent = xfFrame,
	})
	Hardware.drag(xfHit, "x", function()
		return Vide.untrack(xf)
	end, function(v)
		Actions.live(1, "Xfader", v)
	end, 0.5, xfFrame, 13)

	-- MASTER: a fader whose groove is the stereo meter (L over R), level at the right
	local segs = {}
	for ch = 0, 1 do
		for i = 1, 24 do
			segs[ch * 24 + i] = Base.new("Frame", {
				Position = UDim2.new((i - 1) / 24, 0, 0, 5 + ch * 7),
				Size = UDim2.new(1 / 24, -2, 0, 5),
				BackgroundColor3 = Color3.fromHex("2a2a2a"),
			})
		end
	end
	local mf = frame({
		Position = UDim2.fromOffset(16, 75 + BOT),
		Size = UDim2.fromOffset(246, 22),
		segs,
		Hardware.cap(16, 26, {
			Position = function()
				return UDim2.new(master(), 8 - master() * 16, 0.5, 0)
			end,
		}),
	})
	local mHit = create("TextButton")({
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 16, 1, 6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 6,
		Parent = mf,
	})
	Hardware.drag(mHit, "x", function()
		return Vide.untrack(master)
	end, function(v)
		Actions.live(1, "Master", v)
	end, 0.8, mf, 8)
	-- the meter: both channels read the louder deck through the master fader
	local litNow = -1
	local lv = 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		local level = math.max(Model.level(1), Model.level(2)) * Vide.untrack(master) / 0.8
		lv = math.max(level, lv - dt * 1.4)
		local n = math.floor(math.clamp(lv, 0, 1) * 24 + 0.5)
		if n == litNow then
			return
		end
		litNow = n
		for ch = 0, 1 do
			for i = 1, 24 do
				segs[ch * 24 + i].BackgroundColor3 = if i <= n
					then (if i > 20 then C.red else C.soft)
					else Color3.fromHex("2a2a2a")
			end
		end
	end)
	Vide.cleanup(function()
		conn:Disconnect()
	end)

	return cell(438, 374, {
		cap11("A", 16, 22 + TOP, W),
		cap11("B", 350, 22 + TOP, W),
		xfFrame,
		Base.new(
			"Frame",
			{ Position = UDim2.fromOffset(16, 56 + RULE), Size = UDim2.fromOffset(342, 1), BackgroundColor3 = C.line }
		),
		cap11("MASTER", 16, 62 + BOT, W),
		label(function()
			return math.floor(master() * 100 + 0.5) .. "%"
		end, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromOffset(262, 62 + BOT),
			FontFace = B,
			TextSize = 11,
			TextColor3 = W,
		}),
		mf,
		cap11("CURVE", 286, 62 + BOT),
		Hardware.hfader(286, 74 + BOT, 72, curve, function(v)
			Actions.live(1, "Curve", v)
		end, 0),
	})
end

function Strip.new(a: Model.Deck, b: Model.Deck, props: Base.Props?): Frame
	return frame(Base.with({
		Name = "Strip",
		Size = UDim2.fromOffset(1250, H),
		side(a, 0, false),
		centre(),
		side(b, 814, true),
	}, props))
end

return Strip
