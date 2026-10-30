--!strict
-- The playlist cover editor under the header cover: cover text, cover image, and the colour as an
-- HSV picker (UI/ColorPicker).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vide = require(ReplicatedStorage.CosmicDJ.Packages.Vide)
local Actions = require(script.Parent.Parent.Parent.Actions)
local Theme = require(script.Parent.Parent.Parent.Theme)
local Base = require(script.Parent.Parent.Parent.UI.Base)
local Controls = require(script.Parent.Parent.Parent.UI.Controls)
local ColorPicker = require(script.Parent.Parent.Parent.UI.ColorPicker)
local Covers = require(script.Parent.Parent.Parent.UI.Covers)
local State = require(script.Parent.State)

local create = Vide.create
local C = Theme.C
local caption, corner = Base.caption, Base.corner

local CoverPop = {}

local PW = 256

function CoverPop.new(S: State.S, pid: string, props: Base.Props?): Frame
	local p0 = S.playlist(pid)
	local start = Covers.playlistColor(p0)
	local picker = ColorPicker.new({
		w = PW,
		value = start,
		placeholder = "#" .. Theme.accent():ToHex(),
		onPick = function(c: Color3)
			Actions.settle(pid .. "color", { Kind = "PlaylistEdit", Id = pid, Field = "Color", Text = c:ToHex() }, 0.12)
		end,
		onDefault = function(): Color3
			Actions.send({ Kind = "PlaylistEdit", Id = pid, Field = "Color", Text = "" })
			return Theme.accent()
		end,
		zIndex = 31,
	}, { LayoutOrder = 6 })

	local function popField(order: number, title: string, value: string, placeholder: string, onCommit: (string) -> ())
		return {
			caption(title, { LayoutOrder = order * 2 - 1, ZIndex = 31 }),
			Controls.input(
				{ placeholder = placeholder, text = value, onCommit = onCommit },
				{ LayoutOrder = order * 2, ZIndex = 31 }
			),
		}
	end

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
			picker,
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
