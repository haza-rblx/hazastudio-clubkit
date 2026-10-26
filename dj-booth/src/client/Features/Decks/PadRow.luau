--!strict
-- The deck pads (70 px): the Pads tab's pads as one line each, 4 x 2. A press asks the server; the
-- deck-wide cooldown comes back as a ready time, drawn as a draining fill and a countdown chip.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vide = require(ReplicatedStorage.HazaDJ.Packages.Vide)
local Actions = require(script.Parent.Parent.Parent.Actions)
local Store = require(script.Parent.Parent.Parent.Store)
local Theme = require(script.Parent.Parent.Parent.Theme)
local Base = require(script.Parent.Parent.Parent.UI.Base)
local Hover = require(script.Parent.Parent.Parent.UI.Hover)
local Model = require(script.Parent.Model)

local create, source, indexes = Vide.create, Vide.source, Vide.indexes
local C, W, B = Theme.C, Theme.W, Theme.B
local label, corner = Base.label, Base.corner

local PadRow = {}

local PW, GAP = 311, 2

function PadRow.new(height: number, props: Base.Props?): Frame
	local PH = math.floor((height - GAP) / 2)
	local pads = function()
		local list = Store.library().pads
		local out = {}
		for i = 1, math.min(8, #list) do
			out[i] = list[i]
		end
		return out
	end
	local faces = indexes(pads, function(pad, i)
		local col, row = (i - 1) % 4, (i - 1) // 4
		local hover = source(false)
		local left = function()
			Model.clock()
			return math.max(0, (Store.session().padReady[i] or 0) - Store.now())
		end
		local busy = function()
			return left() > 0
		end
		return create("TextButton")({
			Text = "",
			AutoButtonColor = false,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Size = UDim2.fromOffset(PW, PH),
			Position = UDim2.fromOffset(col * (PW + GAP), row * (PH + GAP)),
			BackgroundColor3 = function()
				return if not pad().kind then C.field elseif hover() and not busy() then C.select else C.raised
			end,
			Hover.track(hover),
			Activated = function()
				if pad().kind and not Vide.untrack(busy) then
					Actions.send({ Kind = "PadPress", Index = i })
				end
			end,
			-- empty
			label("Empty pad", {
				Visible = function()
					return not pad().kind
				end,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 16, 0.5, 0),
				TextSize = 13,
				TextColor3 = C.faint,
			}),
			-- cooldown: a dark fill that drains left to right, under the text
			Base.new("Frame", {
				Visible = function()
					return pad().kind ~= nil
				end,
				Size = function()
					local p = pad()
					local total = math.max(1, p.cooldown or 1)
					return UDim2.fromScale(math.clamp(left() / total, 0, 1), 1)
				end,
				BackgroundColor3 = Color3.new(),
				BackgroundTransparency = 0.5,
				ZIndex = 1,
			}),
			Base.fixed(
				function()
					local p = pad()
					return if p.label ~= "" then p.label else "Untitled"
				end,
				16,
				0,
				PW - 100,
				PH,
				{
					Visible = function()
						return pad().kind ~= nil
					end,
					FontFace = B,
					TextSize = 14,
					ZIndex = 2,
				}
			),
			create("TextLabel")({
				Visible = function()
					return pad().kind ~= nil
				end,
				Text = function()
					local l = left()
					return if l > 0 then math.ceil(l) .. "s" else (pad().cooldown or 0) .. "s"
				end,
				FontFace = B,
				TextSize = 11,
				TextColor3 = function()
					return if busy() then W else C.dim
				end,
				BackgroundColor3 = C.field,
				BorderSizePixel = 0,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 20),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				ZIndex = 2,
				corner(3),
				Base.pad(8),
			}),
		})
	end)
	return Base.frame(Base.with({
		Name = "Pads",
		Size = UDim2.new(1, 0, 0, height),
		faces,
	}, props))
end

return PadRow
