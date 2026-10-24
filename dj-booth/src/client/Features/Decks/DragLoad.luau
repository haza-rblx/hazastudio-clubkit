--!strict
-- Drag a library row onto a deck (owner, 2026-10-23: explored in the playtest). A press that travels
-- 6 px (a touch: a 0.3 s hold, so a swipe still scrolls) lifts a ghost card that follows the pointer;
-- the deck body under it gets a red inner outline, and the release point decides the drop.
-- Input positions exclude the top-bar inset while the panel's ScreenGui ignores it, so every pointer
-- position gets the inset added back.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Vide = require(ReplicatedStorage.HazaDJ.Packages.Vide)
local Theme = require(script.Parent.Parent.Parent.Theme)
local Base = require(script.Parent.Parent.Parent.UI.Base)
local Covers = require(script.Parent.Parent.Parent.UI.Covers)

local create = Vide.create
local C, W, B = Theme.C, Theme.W, Theme.B

local DragLoad = {}

local LIFT = 6
-- touch waits for a hold before lifting, so a swipe still scrolls the list
local HOLD = 0.3
-- the frames a drop lands on, per deck (its header and its body)
local targets: { [number]: { GuiObject } } = { {}, {} }
local outlines: { [number]: { UIStroke } } = { {}, {} }
local lastDrag = 0
local dragging = false

-- f takes a drop; outlined (the deck body, not its header strip) also lights up while hovered
function DragLoad.target(n: number, f: GuiObject, outlined: boolean)
	table.insert(targets[n], f)
	local s: UIStroke? = nil
	if outlined then
		s = create("UIStroke")({
			Name = "DropOutline",
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			BorderStrokePosition = Enum.BorderStrokePosition.Inner,
			Color = C.red,
			Thickness = 2,
			Enabled = false,
			Parent = f,
		})
		table.insert(outlines[n], s :: UIStroke)
	end
	-- a remounted panel registers fresh frames; the old ones leave the lists
	f.Destroying:Once(function()
		table.remove(targets[n], table.find(targets[n], f) or 0)
		if s then
			table.remove(outlines[n], table.find(outlines[n], s) or 0)
		end
	end)
end

-- true while a ghost is up or just after, so the row's own click (select) can ignore the release
-- whichever of the two release events lands first
function DragLoad.recent(): boolean
	return dragging or os.clock() - lastDrag < 0.25
end

-- a pointer position in the panel ScreenGui's space (IgnoreGuiInset)
local function guiPoint(v: Vector3): Vector2
	return Vector2.new(v.X, v.Y) + GuiService:GetGuiInset()
end

-- on screen: the frame and every GuiObject above it visible, its ScreenGui enabled
local function shown(f: GuiObject): boolean
	local p: Instance? = f
	while p and p:IsA("GuiObject") do
		if not p.Visible then
			return false
		end
		p = p.Parent
	end
	return p ~= nil and p:IsA("LayerCollector") and p.Enabled
end

local function deckAt(p: Vector2): number?
	for n, list in targets do
		for _, f in list do
			local a, s = f.AbsolutePosition, f.AbsoluteSize
			if p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y and shown(f) then
				return n
			end
		end
	end
	return nil
end

local function light(n: number?)
	for k, list in outlines do
		for _, s in list do
			s.Enabled = k == n
		end
	end
end

-- row: the library row; title + color for the ghost; onDrop(n) loads deck n
function DragLoad.bind(row: GuiObject, title: string, color: Color3, onDrop: (number) -> ())
	row.InputBegan:Connect(function(io: InputObject)
		local touch = io.UserInputType == Enum.UserInputType.Touch
		if io.UserInputType ~= Enum.UserInputType.MouseButton1 and not touch then
			return
		end
		local start = guiPoint(io.Position)
		local at = start
		local ghost: Frame? = nil
		-- the ghost is built from an input handler, so it gets its own Vide root (disposed on release)
		local dispose: (() -> ())? = nil
		local over: number? = nil
		local done = false
		local scroller = row:FindFirstAncestorOfClass("ScrollingFrame")
		local scrolled = scroller and scroller.ScrollingEnabled
		local conns: { RBXScriptConnection } = {}

		local function finish(drop: boolean)
			if done then
				return
			end
			done = true
			for _, c in conns do
				c:Disconnect()
			end
			if not ghost then
				return
			end
			lastDrag = os.clock()
			dragging = false
			ghost:Destroy()
			if dispose then
				dispose()
			end
			light(nil)
			if scroller and scrolled ~= nil then
				scroller.ScrollingEnabled = scrolled
			end
			local n = if drop then deckAt(at) else nil
			if n then
				onDrop(n)
			end
		end

		local function follow()
			local g = ghost :: Frame
			g.Position = UDim2.fromOffset(at.X + 14, at.Y)
			local n = deckAt(at)
			if n ~= over then
				over = n
				light(n)
			end
		end

		local function lift()
			if ghost or done then
				return
			end
			dragging = true
			if touch and scroller then
				scroller.ScrollingEnabled = false
			end
			local gui = row:FindFirstAncestorOfClass("ScreenGui")
			dispose = Vide.root(function()
				ghost = Base.new("Frame", {
					Name = "DragGhost",
					AnchorPoint = Vector2.new(0, 0.5),
					Size = UDim2.fromOffset(220, 44),
					BackgroundColor3 = C.card2,
					ZIndex = 200,
					Parent = gui,
					Base.corner(4),
					create("UIStroke")({
						Color = C.line,
						Thickness = 1,
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					}),
					Covers.track(title, color, 28, { Position = UDim2.fromOffset(8, 8), ZIndex = 201 }),
					Base.label(title, {
						AutomaticSize = Enum.AutomaticSize.None,
						Position = UDim2.fromOffset(44, 0),
						Size = UDim2.new(1, -52, 1, 0),
						FontFace = B,
						TextSize = 13,
						TextColor3 = W,
						TextTruncate = Enum.TextTruncate.AtEnd,
						ZIndex = 201,
					}),
				})
			end)
			follow()
		end

		if touch then
			task.delay(HOLD, function()
				if not done and (at - start).Magnitude < LIFT then
					lift()
				end
			end)
		end
		table.insert(
			conns,
			UserInputService.InputChanged:Connect(function(m: InputObject)
				-- the same finger, or the mouse
				if touch then
					if m ~= io then
						return
					end
				elseif m.UserInputType ~= Enum.UserInputType.MouseMovement then
					return
				elseif not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
					-- released somewhere the game never heard about (outside the window)
					finish(false)
					return
				end
				at = guiPoint(m.Position)
				if ghost then
					follow()
				elseif (at - start).Magnitude >= LIFT then
					if touch then
						-- moved before the hold: a scroll, not a drag
						finish(false)
					else
						lift()
					end
				end
			end)
		)
		table.insert(
			conns,
			UserInputService.InputEnded:Connect(function(e: InputObject)
				if (touch and e ~= io) or (not touch and e.UserInputType ~= Enum.UserInputType.MouseButton1) then
					return
				end
				at = guiPoint(e.Position)
				finish(true)
			end)
		)
		table.insert(
			conns,
			UserInputService.WindowFocusReleased:Connect(function()
				finish(false)
			end)
		)
	end)
end

return DragLoad
