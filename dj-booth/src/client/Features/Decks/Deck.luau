--!strict
-- One deck: the compact 60 px track header and the 231 px body (SYNC + tempo on the outer edge,
-- the platter, the EQ column, FILTER + VOL on the inner edge). Deck B is mirrored.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Vide = require(ReplicatedStorage.HazaDJ.Packages.Vide)
local Shared = ReplicatedStorage.HazaDJ.Shared
local Format = require(Shared.Format)
local Mix = require(Shared.Mix)
local Actions = require(script.Parent.Parent.Parent.Actions)
local Store = require(script.Parent.Parent.Parent.Store)
local Theme = require(script.Parent.Parent.Parent.Theme)
local Base = require(script.Parent.Parent.Parent.UI.Base)
local Hover = require(script.Parent.Parent.Parent.UI.Hover)
local Hardware = require(script.Parent.Parent.Parent.UI.Hardware)
local Model = require(script.Parent.Model)

local create = Vide.create
local C, W, B, SB, R = Theme.C, Theme.W, Theme.B, Theme.SB, Theme.R
local frame, label, corner = Base.frame, Base.label, Base.corner

local Deck = {}

Deck.HEAD_H = 60
local HEAD_W = 624
-- a pin's head is a slightly flat pill (owner, 2026-10-26): a digit centres more cleanly in it
local PIN_W, PIN_HEAD, PIN_STEM = 16, 12, 5
Deck.BODY_H = 231

-- ── header: 40 px cover, title over artist · BPM · key, remaining over position / length ──
function Deck.header(m: Model.Deck, props: Base.Props?): Frame
	local ejectHover = Vide.source(false)
	local title = function()
		local t = m.track()
		return if t then t.title else "No track loaded"
	end
	return Base.new(
		"Frame",
		Base.with({
			Size = UDim2.fromOffset(HEAD_W, Deck.HEAD_H),
			BackgroundColor3 = C.tile,
			Base.new("Frame", {
				Position = UDim2.fromOffset(16, 10),
				Size = UDim2.fromOffset(40, 40),
				BackgroundColor3 = m.color,
				corner(4),
				label(function()
					return if m.track() then Format.initials(title()) else ""
				end, {
					AutomaticSize = Enum.AutomaticSize.None,
					Size = UDim2.fromScale(1, 1),
					TextXAlignment = Enum.TextXAlignment.Center,
					FontFace = B,
					TextSize = 14,
				}),
			}),
			label(title, {
				Position = UDim2.fromOffset(68, 8),
				FontFace = SB,
				TextSize = 14,
				TextColor3 = function()
					return if m.track() then W else C.dim
				end,
			}),
			label(function()
				local t = m.track()
				if not t then
					return ""
				end
				local bpm = Format.effectiveBpm(t.bpm, t.speed)
				return t.artist
					.. "  ·  "
					.. (if bpm then bpm .. " BPM" else "— BPM")
					.. "  ·  "
					.. (t.key or "—")
			end, { Position = UDim2.fromOffset(68, 27), FontFace = R, TextSize = 12, TextColor3 = C.dim }),
			label(function()
				return Model.headerLeft(m)
			end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -42, 0, 6), FontFace = B, TextSize = 18 }),
			label(function()
				return Model.headerAt(m)
			end, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -42, 0, 29),
				FontFace = SB,
				TextSize = 12,
				TextColor3 = C.dim,
			}),
			-- eject: empties the deck, at the end of the title row (only with a track loaded)
			create("TextButton")({
				Text = "",
				AutoButtonColor = false,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -16, 0, 7),
				Size = UDim2.fromOffset(20, 20),
				BackgroundColor3 = C.field,
				BorderSizePixel = 0,
				ZIndex = 3,
				Visible = function()
					return m.track() ~= nil
				end,
				Hover.track(ejectHover),
				Activated = function()
					m.run("Eject")
				end,
				corner(10),
				Base.glyph("cross", 8, function()
					return if ejectHover() then W else C.dim
				end),
			}),
			-- progress, red while the deck is heard
			Base.new("Frame", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 3),
				BackgroundColor3 = Color3.fromHex("2a2a2a"),
				Base.new("Frame", {
					Size = function()
						return UDim2.fromScale(Model.progress(m), 1)
					end,
					BackgroundColor3 = function()
						return if m.live() then C.red else W
					end,
				}),
			}),
			-- markers on the progress line (owner, 2026-10-26, picked live): each set hot cue is a pin, its
			-- number in a round head on a 1 px stem down to the line (red for the one last hit); the CUE
			-- point is a red triangle pointing down onto the line. The text above sits 3-4 px up for them.
			frame({
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 0, 1, -3),
				Size = UDim2.new(1, 0, 0, PIN_HEAD + PIN_STEM),
				ZIndex = 2,
				Base.rebuild(function(): string
					local t, d = m.track(), m.deck()
					if not (t and t.len) then
						return ""
					end
					local key = t.len .. ":" .. d.cue .. ":" .. tostring(d.lastCue)
					for k = 1, 8 do
						key ..= ":" .. tostring((t.cues or {})[tostring(k)])
					end
					return key
				end, function(key: string)
					if key == "" then
						return nil
					end
					local t, d = m.track(), m.deck()
					local len = (t :: any).len :: number
					local cues = {}
					for k, at in (t :: any).cues or {} do
						table.insert(cues, { n = tonumber(k) :: number, at = at :: number })
					end
					table.sort(cues, function(a, b)
						return a.at < b.at
					end)
					local out = {}
					-- later pins stack over earlier ones; the dark rim keeps touching heads apart
					local half = math.ceil(PIN_W / 2)
					for i, c in cues do
						local hit = d.lastCue == c.n
						local color = if hit then C.red else W
						local x = math.floor(math.clamp(c.at / len, 0, 1) * HEAD_W)
						table.insert(
							out,
							Base.new("Frame", {
								AnchorPoint = Vector2.new(0.5, 1),
								Position = UDim2.new(0, x, 1, 0),
								Size = UDim2.fromOffset(1, PIN_STEM + 1),
								BackgroundColor3 = color,
								ZIndex = 3 + i * 2,
							})
						)
						-- the head stays whole at the ends; the stem keeps the true spot
						table.insert(
							out,
							label(tostring(c.n), {
								AutomaticSize = Enum.AutomaticSize.None,
								AnchorPoint = Vector2.new(0.5, 0),
								Position = UDim2.fromOffset(math.clamp(x, half, HEAD_W - half), 0),
								Size = UDim2.fromOffset(PIN_W, PIN_HEAD),
								BackgroundTransparency = 0,
								BackgroundColor3 = color,
								FontFace = B,
								TextSize = 12,
								TextColor3 = if hit then W else C.tile,
								TextXAlignment = Enum.TextXAlignment.Center,
								ZIndex = 4 + i * 2,
								Base.round(1),
								Base.stroke(C.tile, 1.5, { ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
							})
						)
					end
					-- CUE: the lower half of a turned square, over the pins
					table.insert(
						out,
						frame({
							AnchorPoint = Vector2.new(0.5, 1),
							Position = UDim2.new(math.clamp(d.cue / len, 0, 1), 0, 1, 0),
							Size = UDim2.fromOffset(11, 6),
							ClipsDescendants = true,
							ZIndex = 30,
							Base.new("Frame", {
								AnchorPoint = Vector2.new(0.5, 0.5),
								Position = UDim2.fromScale(0.5, 0),
								Size = UDim2.fromOffset(8, 8),
								Rotation = 45,
								BackgroundColor3 = C.red,
								ZIndex = 30,
							}),
						})
					)
					return out
				end),
			}),
			-- the progress line seeks: click along the header's bottom edge
			create("TextButton")({
				Text = "",
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 8),
				Position = UDim2.new(0, 0, 1, -8),
				ZIndex = 3,
				Vide.action(function(bar: Instance)
					local b = bar :: GuiObject
					b.InputBegan:Connect(function(io)
						local t = m.track()
						if not (Base.isPress(io) and t and t.len) then
							return
						end
						local a =
							math.clamp((io.Position.X - b.AbsolutePosition.X) / math.max(b.AbsoluteSize.X, 1), 0, 1)
						Actions.send({ Kind = "Seek", Deck = m.n, Seconds = a * (t.len :: number) })
					end)
				end),
			}),
		}, props)
	)
end

-- ── the platter (the original template's, rebuilt; owner: "ambil sama plek aja") ──
local JOG_NATIVE, JOG = 181, 168

local function jog(m: Model.Deck, cx: number, cy: number): Frame
	local rotation = function()
		Model.clock()
		-- 180°/s at 1.00x, like a platter at 33 rpm drawn as a half turn a second
		return 180 + (m.position() * 180) % 360
	end
	local remainingPct = function()
		local len = m.length()
		if not len or len <= 0 then
			return "—"
		end
		return string.format("-%.1f%%", math.max(0, (len - m.position()) / len * 100))
	end
	local inner = Base.new("Frame", {
		Name = "InnerWrapper",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.7),
		BackgroundColor3 = C.tile,
		ZIndex = 54,
		create("UIAspectRatioConstraint")({ AspectRatio = 1 }),
		Base.round(1),
		create("UIStroke")({
			Color = Color3.fromHex("2a2a2a"),
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Base.vlist(
			5,
			{ HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Top }
		),
		frame({
			Name = "Top",
			Size = UDim2.new(1, 0, 0.5, 0),
			ZIndex = 54,
			Base.vlist(2, {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
			}),
			label(remainingPct, {
				FontFace = SB,
				TextSize = 16,
				TextColor3 = C.soft,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 54,
				LayoutOrder = 1,
			}),
			label(function()
				return Mix.speedLabel(Store.localOr(m.n .. "Pitch", m.deck().pitch))
			end, {
				FontFace = B,
				TextSize = 28,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 54,
				LayoutOrder = 2,
			}),
		}),
		Base.new("Frame", {
			Name = "Separator",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.new(0.8, 0, 0, 2),
			BackgroundColor3 = Color3.fromHex("3a3a3a"),
			LayoutOrder = 2,
			ZIndex = 54,
		}),
		frame({
			Name = "Bottom",
			Size = UDim2.new(1, 0, 0.5, 0),
			LayoutOrder = 3,
			ZIndex = 54,
			Base.vlist(2, {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Top,
			}),
			label(function()
				return Format.clock(m.position() / m.rate())
			end, {
				FontFace = SB,
				TextSize = 16,
				TextColor3 = C.dim,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 54,
				LayoutOrder = 1,
			}),
			label(function()
				local r = Model.remaining(m)
				return if r then "-" .. Format.clock(r) else "-00:00.0"
			end, {
				FontFace = SB,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 54,
				LayoutOrder = 2,
			}),
		}),
	})
	local wrapper = Base.new("Frame", {
		Name = "Wrapper",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(JOG_NATIVE, JOG_NATIVE),
		BackgroundColor3 = Color3.fromHex("141414"),
		ZIndex = 54,
		create("UIScale")({ Scale = JOG / JOG_NATIVE }),
		create("UIAspectRatioConstraint")({ AspectRatio = 1 }),
		Base.round(1),
		create("UIStroke")({
			Color = Color3.fromHex("262626"),
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Base.new("Frame", {
			Name = "RotatingThings",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.new(0, 10, 1, 0),
			BackgroundColor3 = W,
			ZIndex = 54,
			Rotation = rotation,
			-- only the red end shows; the far end is transparent so it blends into the platter
			create("UIGradient")({
				Rotation = 90,
				Color = ColorSequence.new(C.red),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(0.501, 1),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		}),
		inner,
	})
	-- scratch: drag around the ring; each turn is 1.8 s of audio
	local hit = create("TextButton")({
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 60,
		Parent = wrapper,
	})
	hit.InputBegan:Connect(function(io)
		if not Base.isPress(io) or not m.track() then
			return
		end
		-- input positions exclude the top-bar inset; this ScreenGui ignores it, so add it back
		local function angle(p: Vector3): number
			local c = wrapper.AbsolutePosition + wrapper.AbsoluteSize / 2
			local y = p.Y + GuiService:GetGuiInset().Y
			return math.deg(math.atan2(y - c.Y, p.X - c.X))
		end
		local last = angle(io.Position)
		local acc, sentAt = 0, os.clock()
		local release = Hover.hold()
		local moveC, endC
		moveC = UserInputService.InputChanged:Connect(function(mv)
			if not Base.isMove(mv) then
				return
			end
			local a = angle(mv.Position)
			local d = a - last
			if d > 180 then
				d -= 360
			elseif d < -180 then
				d += 360
			end
			last = a
			acc += d / 360 * 1.8
			if os.clock() - sentAt > 0.05 and math.abs(acc) > 0.01 then
				m.nudge(acc)
				acc, sentAt = 0, os.clock()
			end
		end)
		endC = UserInputService.InputEnded:Connect(function(e)
			if Base.isPress(e) then
				moveC:Disconnect()
				endC:Disconnect()
				release()
				if math.abs(acc) > 0.01 then
					m.nudge(acc)
				end
			end
		end)
	end)
	return wrapper
end

local function small(text: any, x: number, y: number, color: any?, anchorX: number?): TextLabel
	return label(text, {
		AnchorPoint = Vector2.new(anchorX or 0, 0),
		Position = UDim2.fromOffset(x, y),
		FontFace = B,
		TextSize = 11,
		TextColor3 = color or C.dim,
		ZIndex = 53,
	})
end

-- ── body ──
function Deck.body(m: Model.Deck, mirror: boolean, props: Base.Props?): Frame
	local BH = Deck.BODY_H
	local W0 = 436
	local function X(x: number): number
		return if mirror then W0 - x else x
	end
	local CAP = BH - 22 -- one bottom caption line for every column
	local d = m.deck
	local range = function()
		return Mix.PITCH_RANGES[Store.settings().pitch] or 0.16
	end
	-- tempo fader: 0 top = fastest; the centre is 1.00x
	local pitch = m.value("Pitch", function()
		return d().pitch
	end)
	local tempoV = function()
		return math.clamp(0.5 - pitch() / (2 * range()), 0, 1)
	end
	-- both SYNC keys light while the decks are linked (this one follows, or the other one does)
	local synced = function()
		return d().synced or Store.session().decks[3 - m.n].synced
	end
	local syncBtn = create("TextButton")({
		Text = "SYNC",
		FontFace = B,
		TextSize = 13,
		TextColor3 = function()
			return if synced() then W else C.soft
		end,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(X(40), 10),
		Size = UDim2.fromOffset(64, 28),
		BackgroundColor3 = C.key,
		BorderSizePixel = 0,
		ZIndex = 53,
		Activated = function()
			m.run("Sync")
		end,
		corner(4),
		-- synced: a red rim, like a lit hot cue or the playing PLAY key
		create("UIStroke")({
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = function()
				return if synced() then C.red else C.root
			end,
			Thickness = function()
				return if synced() then 2 else 1
			end,
		}),
	})
	-- EQ: HIGH over MID over LOW, each with its dB line (dim at 0 dB)
	local EQ_X, EQ_S = 327, 26
	local eqParts = {}
	for i, e in { { "HIGH", "EqHigh" }, { "MID", "EqMid" }, { "LOW", "EqLow" } } do
		local top, bottom = 30, CAP - 30
		local ey = math.floor(top + (i - 1) * (bottom - top) / 2)
		local v = m.value(e[2], function()
			return d().eq[i]
		end)
		table.insert(
			eqParts,
			Hardware.ledKnob(X(EQ_X), ey, EQ_S, v, true, function(x)
				m.set(e[2], x)
			end, 0.5)
		)
		table.insert(eqParts, small(e[1], X(EQ_X), ey + 18, C.dim, 0.5))
		table.insert(
			eqParts,
			small(
				function()
					return (Mix.eqLabel(v()))
				end,
				X(EQ_X),
				ey + 30,
				function()
					local _, on = Mix.eqLabel(v())
					return if on then W else C.faint
				end,
				0.5
			)
		)
	end
	local filter = m.value("Filter", function()
		return d().filter
	end)
	local vol = m.value("Vol", function()
		return d().vol
	end)
	return Base.new(
		"Frame",
		Base.with({
			Size = UDim2.fromOffset(W0, BH),
			BackgroundColor3 = C.tile,
			ClipsDescendants = true,
			syncBtn,
			small(function()
				return Mix.pitchLabel(pitch())
			end, X(40), 44, W, 0.5),
			Hardware.vfader(X(40) - 18, 62, CAP - 8 - 62, tempoV, 36, 8, function(v)
				m.set("Pitch", (0.5 - v) * 2 * range())
			end, 0.5),
			small(function()
				return "TEMPO " .. (Mix.PITCH_LABELS[Store.settings().pitch] or "±16%")
			end, X(40), CAP, C.faint, 0.5),
			eqParts,
			jog(m, X(186), math.floor(BH / 2)),
			Hardware.ledKnob(X(400), 32, 30, filter, true, function(x)
				m.set("Filter", x)
			end, 0.5),
			small("FILTER", X(400), 54, C.dim, 0.5),
			small(
				function()
					return Mix.filterLabel(filter())
				end,
				X(400),
				68,
				function()
					return if math.abs(filter() - 0.5) > 0.005 then W else C.faint
				end,
				0.5
			),
			Hardware.vfader(
				X(400) - 16,
				90,
				CAP - 8 - 90,
				function()
					return 1 - vol()
				end,
				32,
				6,
				function(v)
					m.set("Vol", 1 - v)
				end,
				0.2
			),
			small("VOL", X(400), CAP, C.dim, 0.5),
		}, props)
	)
end

return Deck
