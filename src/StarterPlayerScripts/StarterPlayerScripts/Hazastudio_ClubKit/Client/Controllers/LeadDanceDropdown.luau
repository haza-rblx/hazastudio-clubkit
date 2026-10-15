--!strict
-- LeadDanceDropdown (ClientController UI)
--
-- The kit's own dropdown for the "Lead Dance" topbar icon. Replaces TopbarPlus's built-in
-- dropdown. The icon stays the trigger: SyncLeadTopbarController calls :open() / :close()
-- from the icon's selected / deselected events.
--
-- Visuals are ported from the approved prototype (lead_dance_dropdown_prototype.luau).
-- Keep the constants in sync with it.
--
-- API:
--   LeadDanceDropdown.new({ getAnchor, onSync, onUnsync, onClosed? })
--   :setEntries(entries), :open(), :close(), :isOpen(), :destroy()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local PhoneLayout = require(script.Parent.Parent.Utils.PhoneLayout)

export type Entry = {
	userId: number,
	displayName: string,
	name: string,
	followers: number,
	following: boolean,
}

type Deps = {
	getAnchor: () -> GuiObject?,
	onSync: (userId: number) -> (),
	onUnsync: () -> (),
	onClosed: (() -> ())?,
}

local FONT = "rbxassetid://12187365364"
local BG, BG_HOVER = Color3.fromRGB(7, 7, 7), Color3.fromRGB(24, 24, 27)
local SUB, PINK, ACCENT = Color3.fromRGB(150, 150, 155), Color3.fromRGB(240, 150, 180), Color3.fromRGB(200, 90, 122)
local W, ROW_H, GAP, MARGIN, END_R, MID_R = 280, 52, 2, 10, 20, 6
local MAX_ROWS = 6
local BOTTOM_GAP = 8 -- space kept above the hotbar wrapper
local ANCHOR_GAP = 4 -- space between the topbar icon and the panel

local function font(weight: Enum.FontWeight): Font
	return Font.new(FONT, weight)
end

local function corner(parent: GuiObject, radius: UDim): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
	return c
end

local function label(parent: GuiObject, text: string, size: number, weight: Enum.FontWeight, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.FontFace = font(weight)
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.ZIndex = 2
	l.Parent = parent
	return l
end

local function findRefGradient(pg: PlayerGui): Instance?
	local tm = pg:FindFirstChild("15-TopMenuGUI")
	if tm then
		return tm:FindFirstChild("AccentDiscGradient", true)
	end
	return nil
end

local function setRowColor(row: TextButton, col: Color3)
	row.BackgroundColor3 = col
	local fill = row:FindFirstChild("SquareFill")
	if fill and fill:IsA("Frame") then
		fill.BackgroundColor3 = col
	end
end

-- UICorner is uniform, so a square end is faked with a same-colour fill over that half of the row.
local function shapeRow(row: TextButton, rowCorner: UICorner, isFirst: boolean, isLast: boolean)
	if isFirst or isLast then
		rowCorner.CornerRadius = UDim.new(0, END_R)
		if not (isFirst and isLast) then
			local f = Instance.new("Frame")
			f.Name = "SquareFill"
			f.BorderSizePixel = 0
			f.BackgroundColor3 = row.BackgroundColor3
			f.Size = UDim2.new(1, 0, 0.5, 0)
			f.Position = if isFirst then UDim2.fromScale(0, 0.5) else UDim2.fromScale(0, 0)
			f.ZIndex = 0
			f.Parent = row
			local fc = Instance.new("UICorner")
			fc.CornerRadius = UDim.new(0, MID_R)
			fc.Parent = f
		end
	else
		rowCorner.CornerRadius = UDim.new(0, MID_R)
	end
end

local function containsPoint(obj: GuiObject, p: Vector2): boolean
	local pos, size = obj.AbsolutePosition, obj.AbsoluteSize
	return p.X >= pos.X and p.X <= pos.X + size.X and p.Y >= pos.Y and p.Y <= pos.Y + size.Y
end

local LeadDanceDropdown = {}

function LeadDanceDropdown.new(deps: Deps)
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

	local gui = Instance.new("ScreenGui")
	gui.Name = "LeadDanceDropdown"
	gui.IgnoreGuiInset = false
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 11
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = pg

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundTransparency = 1
	panel.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Parent = panel

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 0
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, GAP)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scroll

	local entries: { Entry } = {}
	-- nil, not "": an empty list's signature is "" and must still build the empty-state row once.
	local signature: string? = nil
	local isOpen = false
	local destroyed = false
	local rowConns: { RBXScriptConnection } = {}
	local connections: { RBXScriptConnection } = {}
	local api = {} :: any

	local close: () -> () = function() end

	local function bottomLimit(): number
		local hb = pg:FindFirstChild("10-HotbarGUI")
		local wrap = if hb then hb:FindFirstChild("HotbarWrapper", true) else nil
		if wrap and wrap:IsA("GuiObject") and wrap.AbsoluteSize.Y > 0 then
			return wrap.AbsolutePosition.Y - BOTTOM_GAP
		end
		return gui.AbsoluteSize.Y - MARGIN
	end

	local function layout()
		if destroyed then
			return
		end
		local vp = gui.AbsoluteSize
		local phone = PhoneLayout.isPhoneLayout()
		local s = math.min(if phone then 0.8 else 0.92, (vp.X - MARGIN * 2) / W)
		scale.Scale = s
		local x, y = MARGIN, MARGIN
		local anchor = deps.getAnchor()
		if anchor then
			x = anchor.AbsolutePosition.X
			y = anchor.AbsolutePosition.Y + anchor.AbsoluteSize.Y + ANCHOR_GAP
		end
		x = math.clamp(x, MARGIN, math.max(MARGIN, vp.X - W * s - MARGIN))
		local availPx = (bottomLimit() - y) / s
		local rowCount = math.max(1, #entries) -- the empty state is one row
		local fit = math.clamp(math.floor((availPx + GAP) / (ROW_H + GAP)), 1, MAX_ROWS)
		local rowsShown = math.min(rowCount, fit)
		local listH = rowsShown * ROW_H + math.max(0, rowsShown - 1) * GAP
		if rowCount > rowsShown and availPx - listH > ROW_H * 0.5 then
			listH += GAP + ROW_H * 0.5
		end
		panel.Position = UDim2.fromOffset(x, y)
		panel.Size = UDim2.fromOffset(W, listH)
	end

	local function buildRow(e: Entry, layoutOrder: number, isFirst: boolean, isLast: boolean)
		local row = Instance.new("TextButton")
		row.Name = "Row_" .. tostring(e.userId)
		row.AutoButtonColor = false
		row.Text = ""
		row.BackgroundColor3 = BG
		row.BackgroundTransparency = 0
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, ROW_H)
		row.LayoutOrder = layoutOrder
		row.Parent = scroll
		local rowCorner = corner(row, UDim.new(0, MID_R))
		shapeRow(row, rowCorner, isFirst, isLast)

		local avatarBg = Instance.new("Frame")
		avatarBg.Size = UDim2.fromOffset(36, 36)
		avatarBg.Position = UDim2.new(0, 10, 0.5, -18)
		avatarBg.BackgroundColor3 = ACCENT
		avatarBg.ZIndex = 2
		avatarBg.Parent = row
		corner(avatarBg, UDim.new(1, 0))
		local grad = findRefGradient(pg)
		if grad then
			grad:Clone().Parent = avatarBg
		end
		local av = Instance.new("ImageLabel")
		av.BackgroundTransparency = 1
		av.Size = UDim2.fromScale(1, 1)
		av.ZIndex = 2
		av.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(e.userId) .. "&w=48&h=48"
		av.Parent = avatarBg
		corner(av, UDim.new(1, 0))

		local actionW = if e.following then 70 else 64
		local textW = -(56 + actionW + 16)
		local nm = label(row, e.displayName, 15, Enum.FontWeight.Bold, Color3.new(1, 1, 1))
		nm.Position = UDim2.fromOffset(56, 8)
		nm.Size = UDim2.new(1, textW, 0, 18)
		local sub = label(
			row,
			(if e.following then "You · " else "") .. tostring(e.followers) .. " synced",
			14,
			Enum.FontWeight.Medium,
			if e.following then PINK else SUB
		)
		sub.Name = "Sub"
		sub.Position = UDim2.fromOffset(56, 27)
		sub.Size = UDim2.new(1, textW, 0, 17)

		local b = Instance.new("TextButton")
		b.Name = "Action"
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -10, 0.5, 0)
		b.Size = UDim2.fromOffset(actionW, 30)
		b.Text = if e.following then "Unsync" else "Sync"
		b.TextSize = 13
		b.FontFace = font(Enum.FontWeight.Bold)
		b.ZIndex = 2
		if e.following then
			b.BackgroundColor3 = Color3.new(1, 1, 1)
			b.TextColor3 = BG
		else
			b.BackgroundColor3 = ACCENT
			b.TextColor3 = Color3.new(1, 1, 1)
			local btnGrad = findRefGradient(pg)
			if btnGrad then
				btnGrad:Clone().Parent = b
			end
		end
		b.Parent = row
		corner(b, UDim.new(1, 0))

		-- Both the row and its button can receive the same tap; the first one to run closes the
		-- dropdown, so the second sees it closed and does nothing (no double sync/unsync).
		local function dismiss(): boolean
			if not isOpen then
				return false
			end
			close()
			return true
		end

		table.insert(rowConns, row.MouseEnter:Connect(function()
			setRowColor(row, BG_HOVER)
		end))
		table.insert(rowConns, row.MouseLeave:Connect(function()
			setRowColor(row, BG)
		end))
		table.insert(rowConns, row.Activated:Connect(function()
			if e.following then
				return
			end
			if dismiss() then
				deps.onSync(e.userId)
			end
		end))
		table.insert(rowConns, b.Activated:Connect(function()
			if e.following then
				if dismiss() then
					deps.onUnsync()
				end
			elseif dismiss() then
				deps.onSync(e.userId)
			end
		end))
	end

	local function buildEmptyRow()
		local row = Instance.new("Frame")
		row.Name = "Empty"
		row.BackgroundColor3 = BG
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, ROW_H)
		row.LayoutOrder = 1
		row.Parent = scroll
		corner(row, UDim.new(0, ROW_H / 2))
		local text = label(row, "No lead dancers right now", 14, Enum.FontWeight.Medium, SUB)
		text.Size = UDim2.fromScale(1, 1)
		text.TextXAlignment = Enum.TextXAlignment.Center
	end

	local function rebuildRows()
		for _, conn in ipairs(rowConns) do
			conn:Disconnect()
		end
		table.clear(rowConns)
		for _, child in ipairs(scroll:GetChildren()) do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		if #entries == 0 then
			buildEmptyRow()
			return
		end
		for i, e in ipairs(entries) do
			buildRow(e, i, i == 1, i == #entries)
		end
	end

	close = function()
		if not isOpen then
			return
		end
		isOpen = false
		gui.Enabled = false
		if deps.onClosed then
			deps.onClosed()
		end
	end

	api.setEntries = function(input: { Entry })
		local sorted = table.clone(input)
		table.sort(sorted, function(a, b)
			if a.following ~= b.following then
				return a.following
			end
			local an, bn = a.displayName:lower(), b.displayName:lower()
			if an ~= bn then
				return an < bn
			end
			return a.userId < b.userId
		end)
		entries = sorted

		local parts = table.create(#sorted)
		for _, e in ipairs(sorted) do
			table.insert(parts, string.format("%s:%s:%s:%s", tostring(e.userId), tostring(e.followers), tostring(e.following), e.displayName))
		end
		local nextSignature = table.concat(parts, "|")
		if nextSignature ~= signature then
			signature = nextSignature
			rebuildRows()
		end
		layout()
	end

	api.open = function()
		if destroyed or isOpen then
			return
		end
		isOpen = true
		gui.Enabled = true
		layout()
	end

	api.close = close

	api.isOpen = function(): boolean
		return isOpen
	end

	api.destroy = function()
		if destroyed then
			return
		end
		destroyed = true
		isOpen = false
		for _, conn in ipairs(connections) do
			conn:Disconnect()
		end
		table.clear(connections)
		for _, conn in ipairs(rowConns) do
			conn:Disconnect()
		end
		table.clear(rowConns)
		gui:Destroy()
	end

	-- Close on a tap/click outside the panel and the anchor. The anchor (the icon) is excluded so
	-- its own selected/deselected handling toggles the dropdown without a double close.
	table.insert(connections, UserInputService.InputBegan:Connect(function(input: InputObject)
		if not isOpen then
			return
		end
		local t = input.UserInputType
		if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then
			return
		end
		-- InputObject.Position (mouse/touch) is already measured below the topbar inset, the same
		-- space as AbsolutePosition here; verified in playtest (Position.Y = GetMouseLocation().Y - 58).
		local p = Vector2.new(input.Position.X, input.Position.Y)
		if containsPoint(panel, p) then
			return
		end
		local anchor = deps.getAnchor()
		if anchor and containsPoint(anchor, p) then
			return
		end
		close()
	end))

	table.insert(connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))

	return api :: any
end

return LeadDanceDropdown
