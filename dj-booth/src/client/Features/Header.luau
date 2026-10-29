--!strict
-- The 40 px header: page tabs on the left, the "xfade" mark in the middle, the Deck · Window ·
-- Full switch with its tiny screens, and close on the right.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Vide = require(ReplicatedStorage.HazaDJ.Packages.Vide)
local Base = require(script.Parent.Parent.UI.Base)
local Hover = require(script.Parent.Parent.UI.Hover)
local Theme = require(script.Parent.Parent.Theme)

local create, source, effect, untrack = Vide.create, Vide.source, Vide.effect, Vide.untrack
local C, W, B = Theme.C, Theme.W, Theme.B
local frame, label, corner, pad, hlist = Base.frame, Base.label, Base.corner, Base.pad, Base.hlist

local Header = {}

export type Props = {
	tab: () -> string,
	setTab: (string) -> (),
	badge: () -> number, -- the Library tab's "needs attention" count
	view: () -> string,
	setView: (string) -> (),
	onClose: () -> (),
}

local TABS = { { "Decks", "Decks" }, { "Tracks", "Library" }, { "Access", "Access" }, { "Settings", "Settings" } }

local function tabButton(p: Props, key: string, text: string, order: number)
	local hover = source(false)
	local on = function()
		return p.tab() == key
	end
	local bar = Base.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = if untrack(on) then UDim2.new(1, -20, 0, 2) else UDim2.new(0, 0, 0, 2),
		BackgroundColor3 = C.red,
	})
	local first = true
	effect(function()
		local isOn = on()
		if first then
			first = false
			return
		end
		TweenService
			:Create(bar, Theme.SLIDE, { Size = UDim2.new(if isOn then 1 else 0, if isOn then -20 else 0, 0, 2) })
			:Play()
	end)
	return frame({
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order,
		frame({
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			pad(10),
			hlist(6),
			label(text, {
				FontFace = B,
				TextSize = 13,
				LayoutOrder = 1,
				TextColor3 = function()
					return if on() then W elseif hover() then C.soft else C.dim
				end,
			}),
			-- a true 16 px circle, the count centred in it
			create("TextLabel")({
				Visible = function()
					return key == "Tracks" and p.badge() > 0
				end,
				Text = function()
					return tostring(p.badge())
				end,
				FontFace = B,
				TextSize = 12,
				TextColor3 = W,
				BackgroundColor3 = C.red,
				BorderSizePixel = 0,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(16, 16),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				LayoutOrder = 2,
				create("UIPadding")({ PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }),
				corner(8),
			}),
		}),
		bar,
		create("TextButton")({
			Text = "",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Hover.track(hover),
			Activated = function()
				p.setTab(key)
			end,
		}),
	})
end

-- the view switch (owner, 2026-10-23): each mode is a tiny screen showing where the panel sits;
-- a white pill slides under the active one
local MODES = {
	{ "deck", "Deck", Vector2.new(2, 8), Vector2.new(14, 2) },
	{ "window", "Window", Vector2.new(5, 3), Vector2.new(8, 6) },
	{ "full", "Full", Vector2.new(2, 2), Vector2.new(14, 8) },
}
local BW = 84

local function viewSwitch(p: Props)
	local index = function(m: string): number
		for i, x in MODES do
			if x[1] == m then
				return i
			end
		end
		return 2
	end
	local pill = Base.new("Frame", {
		Position = UDim2.fromOffset(2 + (index(untrack(p.view)) - 1) * BW, 2),
		Size = UDim2.fromOffset(BW, 24),
		BackgroundColor3 = W,
		corner(3),
	})
	local inners = {}
	local buttons = {}
	for i, m in MODES do
		local hover = source(false)
		local col = function()
			return if p.view() == m[1] then C.ink elseif hover() then W else C.dim
		end
		local inner = Base.new("Frame", {
			Position = UDim2.fromOffset(m[3].X, m[3].Y),
			Size = UDim2.fromOffset(m[4].X, m[4].Y),
			BackgroundColor3 = col,
			corner(1),
		})
		inners[m[1]] = inner
		buttons[i] = create("TextButton")({
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(2 + (i - 1) * BW, 2),
			Size = UDim2.fromOffset(BW, 24),
			ZIndex = 2,
			Hover.track(hover),
			Activated = function()
				p.setView(m[1])
			end,
			frame({
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromScale(0, 1),
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0),
				hlist(6),
				frame({
					Size = UDim2.fromOffset(18, 12),
					LayoutOrder = 1,
					corner(2),
					create("UIStroke")({ Color = col, Thickness = 1 }),
					inner,
				}),
				label(m[2], { FontFace = B, TextSize = 12, LayoutOrder = 2, TextColor3 = col }),
			}),
		})
	end
	local first = true
	effect(function()
		local m = p.view()
		if first then
			first = false
			return
		end
		local i = index(m)
		TweenService:Create(pill, Theme.SLIDE, { Position = UDim2.fromOffset(2 + (i - 1) * BW, 2) }):Play()
		-- the panel shape grows into place on the new mode
		local spec = MODES[i]
		local inner = inners[m]
		inner.Size = UDim2.fromOffset(2, 2)
		inner.Position = UDim2.fromOffset(spec[3].X + spec[4].X / 2 - 1, spec[3].Y + spec[4].Y / 2 - 1)
		TweenService:Create(
			inner,
			Theme.SLIDE,
			{ Size = UDim2.fromOffset(spec[4].X, spec[4].Y), Position = UDim2.fromOffset(spec[3].X, spec[3].Y) }
		):Play()
	end)
	return Base.new("Frame", {
		Name = "ViewMode",
		Size = UDim2.fromOffset(2 + BW * #MODES + 2, 28),
		BackgroundColor3 = C.field,
		LayoutOrder = 3,
		corner(4),
		pill,
		buttons,
	})
end

-- close: drawn glyph in a 28 px capsule
local function capsule(order: number, isClose: boolean, onClick: () -> ())
	local hover = source(false)
	local glyph = function(w: number, rot: number?)
		return Base.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(w, 2),
			Rotation = rot or 0,
			BackgroundColor3 = function()
				return if hover() then W else C.soft
			end,
			corner(1),
		})
	end
	return create("TextButton")({
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(28, 28),
		LayoutOrder = order,
		BackgroundColor3 = function()
			return if hover() then (if isClose then C.red else C.raised) else C.field
		end,
		Hover.track(hover),
		Activated = onClick,
		corner(4),
		if isClose then { glyph(12, 45), glyph(12, -45) } else glyph(10),
	})
end

function Header.new(p: Props): Frame
	local tabs = {}
	for i, t in TABS do
		tabs[i] = tabButton(p, t[1], t[2], i)
	end
	return Base.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, Theme.HEADER_H),
		BackgroundColor3 = C.tile,
		-- 80 %: the room shows through the header only; the panel behind it is see-through and the
		-- rows below sit on their own backing (App, owner 2026-10-26)
		BackgroundTransparency = 0.2,
		LayoutOrder = -1,
		create("UIPadding")({ PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }),
		frame({
			-- the first tab's 10 px inner padding is pulled back so "Decks" sits 16 px in, like the
			-- close button on the right
			Position = UDim2.fromOffset(-10, 0),
			Size = UDim2.new(0, 520, 1, 0),
			hlist(10),
			frame({
				Name = "Tabs",
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 1, 0),
				LayoutOrder = 10,
				hlist(0),
				tabs,
			}),
		}),
		-- the wordmark (owner, 2026-10-26, picked live): "xfade" with a red outlined DUAL DECK tag, over
		-- a small "by kosmik" at 50 %; nudged 1 px up so it reads centred (no descenders)
		frame({
			Name = "Title",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, -1),
			AutomaticSize = Enum.AutomaticSize.XY,
			ZIndex = 5,
			Base.vlist(0, { HorizontalAlignment = Enum.HorizontalAlignment.Center }),
			frame({
				AutomaticSize = Enum.AutomaticSize.XY,
				LayoutOrder = 1,
				ZIndex = 5,
				hlist(5),
				label("xfade", {
					FontFace = Font.new(Theme.BRAND.Family, Enum.FontWeight.ExtraBold),
					TextSize = 19,
					LayoutOrder = 1,
					ZIndex = 5,
				}),
				frame({
					Size = UDim2.fromOffset(0, 16),
					AutomaticSize = Enum.AutomaticSize.X,
					LayoutOrder = 2,
					ZIndex = 5,
					Base.corner(2),
					Base.stroke(C.redText, 1),
					Base.pad(5, 5, 0, 0),
					label("DUAL DECK", {
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.fromScale(0, 1),
						FontFace = Theme.BRAND,
						TextSize = 12,
						TextColor3 = C.redText,
						ZIndex = 5,
					}),
				}),
			}),
			label("by kosmik", {
				FontFace = Theme.SB,
				TextSize = 12,
				TextTransparency = 0.5,
				LayoutOrder = 2,
				ZIndex = 5,
			}),
		}),
		frame({
			Size = UDim2.fromScale(0.36, 1),
			AnchorPoint = Vector2.new(1, 0),
			-- the close capsule sits as far from the right edge as from the top: (40 - 28) / 2 = 6 px,
			-- so it is pushed 10 px past the header's 16 px padding
			Position = UDim2.new(1, 10, 0, 0),
			hlist(8, Enum.HorizontalAlignment.Right),
			viewSwitch(p),
			capsule(5, true, p.onClose),
		}),
	})
end

return Header
