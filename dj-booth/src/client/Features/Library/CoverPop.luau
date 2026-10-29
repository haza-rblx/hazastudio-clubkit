--!strict
-- The playlist cover editor under the header cover: cover text, cover image, and the colour as an
-- HSV picker (owner, 2026-10-23: "rgb picker yang kotak") — a saturation / value square over the
-- hue, a hue bar, a preview chip, a hex field and Default.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Vide = require(ReplicatedStorage.HazaDJ.Packages.Vide)
local Actions = require(script.Parent.Parent.Parent.Actions)
local Theme = require(script.Parent.Parent.Parent.Theme)
local Base = require(script.Parent.Parent.Parent.UI.Base)
local Controls = require(script.Parent.Parent.Parent.UI.Controls)
local Covers = require(script.Parent.Parent.Parent.UI.Covers)
local State = require(script.Parent.State)

local create, source, untrack = Vide.create, Vide.source, Vide.untrack
local C, W = Theme.C, Theme.W
local frame, caption, corner = Base.frame, Base.caption, Base.corner

local CoverPop = {}

local PW, SQ_H, HUE_H = 256, 128, 12

function CoverPop.new(S: State.S, pid: string, props: Base.Props?): Frame
	local p0 = S.playlist(pid)
	local start = Covers.playlistColor(p0)
	local h0, s0, v0 = start:ToHSV()
	local hh, ss, vv = source(h0), source(s0), source(v0)
	local color = function()
		return Color3.fromHSV(hh(), ss(), vv())
	end
	local hexBox: TextBox
	local hexFocus = false
	Vide.effect(function()
		local c = color()
		if hexBox and not hexFocus then
			hexBox.Text = "#" .. c:ToHex()
		end
	end)
	local function save()
		Actions.settle(
			pid .. "color",
			{ Kind = "PlaylistEdit", Id = pid, Field = "Color", Text = untrack(color):ToHex() },
			0.12
		)
	end
	local function drag(target: GuiObject, onPos: (number, number) -> ())
		target.InputBegan:Connect(function(i)
			if not Base.isPress(i) then
				return
			end
			local function at(pos: Vector3)
				-- input Y excludes the top-bar inset; this ScreenGui ignores it
				local inset = game:GetService("GuiService"):GetGuiInset()
				local rel = (Vector2.new(pos.X, pos.Y + inset.Y) - target.AbsolutePosition) / target.AbsoluteSize
				onPos(math.clamp(rel.X, 0, 1), math.clamp(rel.Y, 0, 1))
				save()
			end
			at(i.Position)
			local mv, up
			mv = UserInputService.InputChanged:Connect(function(m)
				if Base.isMove(m) then
					at(m.Position)
				end
			end)
			up = UserInputService.InputEnded:Connect(function(e)
				if Base.isPress(e) then
					mv:Disconnect()
					up:Disconnect()
				end
			end)
		end)
	end
	local keys = {}
	for i = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i / 6) % 1, 1, 1)))
	end
	local sq = create("TextButton")({
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(PW, SQ_H),
		BorderSizePixel = 0,
		BackgroundColor3 = function()
			return Color3.fromHSV(hh(), 1, 1)
		end,
		ZIndex = 31,
		corner(4),
		Base.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = W,
			ZIndex = 31,
			corner(4),
			create("UIGradient")({ Transparency = NumberSequence.new(0, 1) }),
		}),
		Base.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(),
			ZIndex = 31,
			corner(4),
			create("UIGradient")({ Rotation = 90, Transparency = NumberSequence.new(1, 0) }),
		}),
		Base.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(12, 12),
			BackgroundTransparency = 1,
			ZIndex = 31,
			Position = function()
				return UDim2.fromScale(ss(), 1 - vv())
			end,
			corner(6),
			create("UIStroke")({ Color = W, Thickness = 2 }),
		}),
	}) :: TextButton
	local hue = create("TextButton")({
		Text = "",
		AutoButtonColor = false,
		Position = UDim2.fromOffset(0, SQ_H + 8),
		Size = UDim2.fromOffset(PW, HUE_H),
		BackgroundColor3 = W,
		BorderSizePixel = 0,
		ZIndex = 31,
		corner(6),
		create("UIGradient")({ Color = ColorSequence.new(keys) }),
		Base.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return UDim2.fromScale(hh(), 0.5)
			end,
			Size = UDim2.fromOffset(6, HUE_H + 6),
			BackgroundColor3 = W,
			ZIndex = 31,
			corner(3),
			create("UIStroke")({ Color = Color3.new(), Thickness = 1, Transparency = 0.5 }),
		}),
	}) :: TextButton
	drag(sq, function(x, y)
		ss(x)
		vv(1 - y)
	end)
	drag(hue, function(x)
		hh(math.min(x, 0.999))
	end)

	local function popField(order: number, title: string, value: string, placeholder: string, onCommit: (string) -> ())
		return {
			caption(title, { LayoutOrder = order * 2 - 1, ZIndex = 31 }),
			Controls.input(
				{ placeholder = placeholder, text = value, onCommit = onCommit },
				{ LayoutOrder = order * 2, ZIndex = 31 }
			),
		}
	end

	local hexField = Controls.input({
		placeholder = "#e41024",
		w = PW - 40,
		text = "#" .. start:ToHex(),
		ref = function(tb)
			hexBox = tb
			tb.Focused:Connect(function()
				hexFocus = true
			end)
		end,
		onCommit = function(text)
			hexFocus = false
			local ok, c = pcall(Color3.fromHex, (string.gsub(text, "#", "")))
			if ok and c then
				local h, s, v = c:ToHSV()
				hh(h)
				ss(s)
				vv(v)
				save()
			else
				hexBox.Text = "#" .. untrack(color):ToHex()
			end
		end,
	}, { Position = UDim2.fromOffset(40, SQ_H + 8 + HUE_H + 8), ZIndex = 31 })
	Controls.button({
		text = "Default",
		kind = "ghost",
		h = 24,
		onClick = function()
			local h, s, v = Theme.RED_COVER:ToHSV()
			hh(h)
			ss(s)
			vv(v)
			Actions.send({ Kind = "PlaylistEdit", Id = pid, Field = "Color", Text = "" })
		end,
	}, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		TextSize = 11,
		ZIndex = 31,
		Parent = hexField,
	})

	local pop = Base.new(
		"Frame",
		Base.with({
			Size = UDim2.fromOffset(280, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = C.raised,
			ZIndex = 30,
			corner(6),
			create("UIStroke")({ Color = C.line, Thickness = 1 }),
			Base.pad(12, 12, 12, 12),
			Base.vlist(6),
			popField(1, "Cover text", (p0 and p0.coverText) or "", "Same as the name", function(text)
				Actions.send({ Kind = "PlaylistEdit", Id = pid, Field = "CoverText", Text = text })
			end),
			popField(
				2,
				"Cover image",
				if p0 and p0.image then string.format("%d", p0.image) else "",
				"Image asset ID (optional)",
				function(text)
					local n = tonumber(string.match(text, "(%d+)") or "")
					Actions.send({ Kind = "PlaylistEdit", Id = pid, Field = "Image", Number = n })
				end
			),
			caption("Cover colour", { LayoutOrder = 5, ZIndex = 31 }),
			frame({
				Size = UDim2.fromOffset(PW, SQ_H + 8 + HUE_H + 8 + 32),
				LayoutOrder = 6,
				ZIndex = 31,
				sq,
				hue,
				Base.new("Frame", {
					Position = UDim2.fromOffset(0, SQ_H + 8 + HUE_H + 8),
					Size = UDim2.fromOffset(32, 32),
					BackgroundColor3 = color,
					ZIndex = 31,
					corner(4),
				}),
				hexField,
			}),
		}, props)
	)
	-- everything in the popover draws above the table
	task.defer(function()
		for _, d in pop:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 31
			end
		end
	end)
	return pop
end

return CoverPop
