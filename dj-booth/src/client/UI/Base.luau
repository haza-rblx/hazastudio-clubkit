--!strict
-- Building blocks every surface uses, on top of Vide's `create`. Each helper takes the prototype's
-- exact defaults and an optional props table that overrides them (Vide applies nested tables
-- after the top level). A function-valued prop is reactive (Vide creates the effect).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vide = require(ReplicatedStorage.HazaDJ.Packages.Vide)
local Theme = require(script.Parent.Parent.Theme)

local create = Vide.create
local C, W = Theme.C, Theme.W

local Base = {}

export type Props = { [any]: any }

local function with(defaults: Props, props: Props?): Props
	if props then
		table.insert(defaults, props)
	end
	return defaults
end
Base.with = with

function Base.new(class: string, props: Props?): any
	return create(class)(with({ BorderSizePixel = 0 }, props))
end

-- a drawn + / − / × (no font glyphs: they sit off-centre or render as tofu), centred in its parent.
-- `size` is the bar length; bars are 2 px so an even-sized button keeps them on whole pixels.
function Base.glyph(kind: "plus" | "minus" | "cross", size: number, color: any): Frame
	local function bar(rot: number)
		return create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size, 2),
			Rotation = rot,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
		})
	end
	local bars = if kind == "plus"
		then { bar(0), bar(90) }
		elseif kind == "minus" then { bar(0) }
		else { bar(45), bar(-45) }
	return create("Frame")({
		Name = "Glyph",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		bars,
	})
end

function Base.frame(props: Props?): Frame
	return create("Frame")(with({ BackgroundTransparency = 1, BorderSizePixel = 0 }, props))
end

function Base.corner(r: number?): UICorner
	return create("UICorner")({ CornerRadius = UDim.new(0, r or 4) })
end

function Base.round(scale: number, offset: number?): UICorner
	return create("UICorner")({ CornerRadius = UDim.new(scale, offset or 0) })
end

-- pad(l, r, t, b): r defaults to l, b defaults to t (the prototype's helper)
function Base.pad(l: number?, r: number?, t: number?, b: number?): UIPadding
	return create("UIPadding")({
		PaddingLeft = UDim.new(0, l or 0),
		PaddingRight = UDim.new(0, r or l or 0),
		PaddingTop = UDim.new(0, t or 0),
		PaddingBottom = UDim.new(0, b or t or 0),
	})
end

function Base.hlist(gap: number?, align: Enum.HorizontalAlignment?, props: Props?): UIListLayout
	return create("UIListLayout")(with({
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, gap or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, props))
end

function Base.vlist(gap: number?, props: Props?): UIListLayout
	return create("UIListLayout")(with({
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, props))
end

function Base.stroke(color: any, thickness: number?, props: Props?): UIStroke
	return create("UIStroke")(with({ Color = color, Thickness = thickness or 1 }, props))
end

function Base.gradient(props: Props): UIGradient
	return create("UIGradient")(props)
end

function Base.label(text: any, props: Props?): TextLabel
	return create("TextLabel")(with({
		Text = text,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		FontFace = Theme.SB,
		TextSize = 14,
		TextColor3 = W,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, props))
end

-- a label in a fixed box, truncated
function Base.fixed(text: any, x: number, y: number, w: number, h: number, props: Props?): TextLabel
	return Base.label(
		text,
		with({
			AutomaticSize = Enum.AutomaticSize.None,
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, h),
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, props)
	)
end

-- small caps caption: Bold 11, dim
function Base.caption(text: any, props: Props?): TextLabel
	local t = if type(text) == "function"
		then function()
			return string.upper(text())
		end
		else string.upper(text)
	return Base.label(t, with({ FontFace = Theme.B, TextSize = 11, TextColor3 = C.dim }, props))
end

-- a 1 px divider; bottom = sits on the parent's bottom edge
function Base.rule(bottom: boolean?, inset: number?, props: Props?): Frame
	local i = inset or 0
	return create("Frame")(with({
		Size = UDim2.new(1, -i * 2, 0, 1),
		Position = if bottom then UDim2.new(0, i, 1, -1) else UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = C.line,
		BorderSizePixel = 0,
	}, props))
end

-- section tile on the 2 px grid
function Base.tile(x: number, y: number, w: number, h: number, props: Props?): Frame
	return create("Frame")(with({
		Name = "Tile",
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = C.tile,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, props))
end

function Base.scroll(props: Props?): ScrollingFrame
	return create("ScrollingFrame")(with({
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.faint,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, props))
end

-- a press: mouse button 1 or touch
function Base.isPress(i: InputObject): boolean
	return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end

function Base.isMove(i: InputObject): boolean
	return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch
end

-- a subtree rebuilt whenever `deps` changes. `deps` is tracked; `build` runs untracked in its own
-- scope, and the instances it made are destroyed on the next rebuild.
function Base.rebuild<T>(deps: () -> T, build: (T) -> any): () -> any
	-- derive memoises: a dependency that returns an equal string / number / nil doesn't rebuild
	local key = Vide.derive(deps)
	return function()
		local value = key()
		return Vide.untrack(function()
			local made = build(value)
			Vide.cleanup(function()
				if typeof(made) == "Instance" then
					made:Destroy()
				elseif type(made) == "table" then
					for _, m in made do
						if typeof(m) == "Instance" then
							m:Destroy()
						end
					end
				end
			end)
			return made
		end)
	end
end

-- an Instance's property follows an action-style setter (for TweenService-driven motion)
function Base.ref(store: { any }, key: any)
	return Vide.action(function(inst)
		store[key] = inst
	end)
end

return Base
