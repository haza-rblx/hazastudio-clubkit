--!strict
-- Client/UI/AdminSpotlightUI.luau
-- Code-built Admin Spotlight panel (docs/plans/admin-spotlight/SPEC.md). Replaces the 04-AdminHub
-- template binder. The public API matches AdminHubUI so AdminHubController keeps its logic;
-- usesActionTemplate() is always false, so the controller takes its code-built path.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local NotifService = require(script.Parent.Parent.Services.NotifService)
local OverlayScrollbar = require(script.Parent.OverlayScrollbar)

export type PlayerEntry = {
	userId: number,
	username: string,
	displayName: string,
	role: string?,
}

export type SheetFootButton = {
	text: string,
	primary: boolean?,
	onClick: () -> (),
}

type ActionMeta = {
	title: string,
	subtitle: string,
	alias: string,
	glyph: string,
	needsPlayer: boolean,
	sheet: boolean,
	speed: boolean,
}

type FlatEntry = {
	id: string,
	row: GuiButton,
	pill: boolean,
}

type Modal = {
	frame: Frame,
	scale: UIScale,
	nav: Frame,
	left: TextButton,
	right: TextButton,
	title: TextLabel,
	sub: TextLabel,
	body: Frame,
	tw: Tween?,
}

local CFG = Config :: any
local FONT_ASSET = "rbxassetid://" .. tostring(CFG.TopbarMenu.FONT_ASSET_ID or 12187365364)
local MONO = Font.fromEnum(Enum.Font.RobotoMono)
local ICON_SEARCH = "rbxassetid://72914550286274"
local ICON_CLOSE = "rbxassetid://70796895792875"
local ICON_CHEVRON = "rbxassetid://75726391560105"
local DISC_FALLBACK = Color3.fromRGB(200, 16, 46)
local DIM_T = 0.45
local RECENT_MAX = 4
local TOAST_HOLD = 2.6
local PANEL_SLIDE = 120
local MAIN_MAX = Vector2.new(500, 640)
local MODAL_MAX = 400
local SEGMENT_MAX = 4

local C = {
	item = Color3.fromRGB(7, 7, 7),
	hover = Color3.fromRGB(26, 26, 26),
	modal = Color3.fromRGB(11, 11, 11),
	row = Color3.fromRGB(22, 22, 22),
	ctrl = Color3.fromRGB(42, 42, 42),
	muted = Color3.fromRGB(142, 142, 142),
	sub = Color3.fromRGB(177, 177, 177),
	white = Color3.new(1, 1, 1),
	black = Color3.new(0, 0, 0),
}

local function aliasOf(section: any, key: string, fallback: string): string
	local value = if type(section) == "table" then section[key] else nil
	return "/" .. tostring(value or fallback)
end

-- Row metadata for the action ids AdminHubController allows. Titles, gates and needsPlayer
-- for the gate itself stay in the controller; this is only how a row looks.
local ACTION_META: { [string]: ActionMeta } = {
	bring = {
		title = "Bring here",
		subtitle = "Teleport the player to you",
		alias = aliasOf(CFG.Session, "CMD_ALIAS_BRING", "bring"),
		glyph = "rbxassetid://102707776395252",
		needsPlayer = true,
		sheet = false,
		speed = false,
	},
	to = {
		title = "Go to",
		subtitle = "Teleport yourself to the player",
		alias = aliasOf(CFG.Session, "CMD_ALIAS_TO", "to"),
		glyph = "rbxassetid://75467598830089",
		needsPlayer = true,
		sheet = false,
		speed = false,
	},
	role = {
		title = "Set role",
		subtitle = "Assign a staff or content role",
		alias = aliasOf(CFG.SetRole, "CMD_ALIAS_SET", "setrole"),
		glyph = "rbxassetid://117147623788832",
		needsPlayer = true,
		sheet = true,
		speed = false,
	},
	gift = {
		title = "Gift membership",
		subtitle = "Grant a membership tier",
		alias = aliasOf(CFG.Gift, "CMD_ALIAS_GIFT", "gift"),
		glyph = "rbxassetid://134476914059182",
		needsPlayer = true,
		sheet = true,
		speed = false,
	},
	title = {
		title = "Custom title",
		subtitle = "Edit a player's title",
		alias = "/title",
		glyph = "rbxassetid://83337728090708",
		needsPlayer = true,
		sheet = false,
		speed = false,
	},
	stats = {
		title = "Edit stats",
		subtitle = "Level, XP, streak and daily quest",
		alias = "/stats",
		glyph = "Lv",
		needsPlayer = true,
		sheet = true,
		speed = false,
	},
	announce = {
		title = "Announce",
		subtitle = "Message everyone in the server",
		alias = aliasOf(CFG.Announcement, "CMD_ALIAS_ANNOUNCE", "announce"),
		glyph = "rbxassetid://124143778277635",
		needsPlayer = false,
		sheet = true,
		speed = false,
	},
	ungravity = {
		title = "Ungravity",
		subtitle = "Float everyone up",
		alias = aliasOf(CFG.Gravity, "CMD_ALIAS_UNGRAVITY", "ungravity"),
		glyph = "rbxassetid://96883678546137",
		needsPlayer = false,
		sheet = false,
		speed = true,
	},
	gravity = {
		title = "Gravity",
		subtitle = "Bring everyone back down",
		alias = aliasOf(CFG.Gravity, "CMD_ALIAS", "gravity"),
		glyph = "rbxassetid://89744205085140",
		needsPlayer = false,
		sheet = false,
		speed = true,
	},
	donate = {
		title = "Donations",
		subtitle = "Fake, credit or edit donations",
		alias = "/donate",
		glyph = "rbxassetid://95726098804496",
		needsPlayer = false,
		sheet = true,
		speed = false,
	},
	refresh = {
		title = "Reload boards",
		subtitle = "Refresh every leaderboard",
		alias = aliasOf(CFG.Leaderboards, "CMD_REFRESH", "refresh"),
		glyph = "rbxassetid://135445189444807",
		needsPlayer = false,
		sheet = false,
		speed = false,
	},
}

-- Main-list order. Player actions first, then server actions ("Affects everyone").
local ACTION_ORDER = {
	"bring", "to", "role", "gift", "title", "stats",
	"announce", "ungravity", "gravity", "donate", "refresh",
}

local function face(weight: Enum.FontWeight): Font
	return Font.new(FONT_ASSET, weight, Enum.FontStyle.Normal)
end

local function trimmed(value: string): string
	return string.match(value, "^%s*(.-)%s*$") or ""
end

-- "/bring sari" -> "bring", "sari" (both lower case).
local function parseCommand(query: string): (string, string)
	local body = string.sub(query, 2)
	local cmd, rest = string.match(body, "^%s*(%S*)%s*(.-)%s*$")
	return string.lower(cmd or ""), string.lower(trimmed(rest or ""))
end

local function findPlayerByPrefix(players: { PlayerEntry }, prefix: string): PlayerEntry?
	for _, entry in ipairs(players) do
		if string.sub(string.lower(entry.username), 1, #prefix) == prefix then
			return entry
		end
		if string.sub(string.lower(entry.displayName), 1, #prefix) == prefix then
			return entry
		end
	end
	return nil
end

local function thumbOf(userId: number): string
	return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150"
end

local function corner(parent: Instance, radius: UDim): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
	return c
end

local function frame(parent: Instance?, name: string, size: UDim2, bg: Color3?, bgT: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.Size = size
	f.BackgroundColor3 = bg or C.white
	f.BackgroundTransparency = bgT or 1
	f.Parent = parent
	return f
end

local function label(parent: Instance, name: string, value: string, size: number, weight: Enum.FontWeight, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Text = value
	l.TextSize = size
	l.TextColor3 = color
	l.FontFace = face(weight)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Size = UDim2.new(1, 0, 1, 0)
	l.Parent = parent
	return l
end

local function wrapText(parent: Instance, name: string, value: string, size: number, weight: Enum.FontWeight, color: Color3): TextLabel
	local t = label(parent, name, value, size, weight, color)
	t.TextWrapped = true
	t.TextTruncate = Enum.TextTruncate.None
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.Size = UDim2.new(1, 0, 0, 0)
	return t
end

local function clickable(parent: Instance, name: string, bg: Color3, bgT: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.Text = ""
	b.BackgroundColor3 = bg
	b.BackgroundTransparency = bgT
	b.Parent = parent
	return b
end

local function hoverRow(row: GuiButton, color: Color3)
	row.MouseEnter:Connect(function()
		row.BackgroundColor3 = color
		row.BackgroundTransparency = 0
	end)
	row.MouseLeave:Connect(function()
		row.BackgroundTransparency = 1
	end)
end

local function clearKids(parent: Instance, keep: { [string]: boolean }?)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("UIListLayout") or child:IsA("UIPadding") or child:IsA("UIGridLayout") or child:IsA("UISizeConstraint") then
			continue
		end
		if keep and keep[child.Name] then
			continue
		end
		child:Destroy()
	end
end

local function tween(inst: Instance, time: number, style: Enum.EasingStyle, dir: Enum.EasingDirection, props: { [string]: any }): Tween
	local t = TweenService:Create(inst, TweenInfo.new(time, style, dir), props)
	t:Play()
	return t
end

-- Icon disc: colour and AccentDiscGradient come from the top-menu BroadcastButton disc.
local function accentDisc(): (Color3, UIGradient?)
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local top = if playerGui then playerGui:FindFirstChild("15-TopMenuGUI") else nil
	local broadcast = if top then top:FindFirstChild("BroadcastButton", true) else nil
	local slot = if broadcast then broadcast:FindFirstChild("UIMotionIconSlot") else nil
	local disc = if slot then slot:FindFirstChildWhichIsA("ImageLabel") else nil
	if disc then
		return disc.BackgroundColor3, disc:FindFirstChildOfClass("UIGradient")
	end
	return DISC_FALLBACK, nil
end

local function makeDisc(parent: Instance, glyph: string, color: Color3, gradient: UIGradient?, size: number, pos: UDim2): Frame
	local d = frame(parent, "IconDisc", UDim2.fromOffset(size, size), color, 0)
	d.Position = pos
	corner(d, UDim.new(1, 0))
	if gradient then
		gradient:Clone().Parent = d
	end
	-- Asset ids are the Admin Hub tile icons; anything else is a short text glyph.
	if string.sub(glyph, 1, 13) == "rbxassetid://" then
		local img = Instance.new("ImageLabel")
		img.Name = "Icon"
		img.BackgroundTransparency = 1
		img.Image = glyph
		img.ImageColor3 = C.white
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		local iconSize = math.floor(size * 24 / 38)
		img.Size = UDim2.fromOffset(iconSize, iconSize)
		img.Parent = d
	else
		local g = label(d, "Glyph", glyph, 12, Enum.FontWeight.Bold, C.white)
		g.TextXAlignment = Enum.TextXAlignment.Center
	end
	return d
end

local function chevron(parent: Instance, pos: UDim2, color: Color3): ImageLabel
	local c = Instance.new("ImageLabel")
	c.Name = "Chevron"
	c.BackgroundTransparency = 1
	c.Image = ICON_CHEVRON
	c.ImageColor3 = color
	c.Size = UDim2.fromOffset(12, 12)
	c.Position = pos
	c.Parent = parent
	return c
end

-- Segmented groups (top menu / Preferences): each row has its own fill, rows sit 2px apart, the
-- group's outer corners are round and the joins between rows are tight. UICorner has one radius,
-- so a row's fill is two clipped halves (top radius, bottom radius) overlapping by 1px.
local segFills: { [GuiObject]: { Frame } } = setmetatable({}, { __mode = "k" }) :: any

local function paintSegment(row: GuiObject, color: Color3)
	local parts = segFills[row]
	if parts then
		for _, part in ipairs(parts) do
			part.BackgroundColor3 = color
		end
	end
end

local function segmentRow(row: GuiObject, topRadius: number, bottomRadius: number, color: Color3)
	local old = row:FindFirstChild("SegFill")
	if old then
		old:Destroy()
	end
	row.BackgroundTransparency = 1
	local holder = Instance.new("Frame")
	holder.Name = "SegFill"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = 0
	local parts = {}
	for _, top in ipairs({ true, false }) do
		local clip = Instance.new("Frame")
		clip.BackgroundTransparency = 1
		clip.ClipsDescendants = true
		clip.ZIndex = 0
		clip.Position = if top then UDim2.new() else UDim2.new(0, 0, 0.5, -1)
		clip.Size = if top then UDim2.fromScale(1, 0.5) else UDim2.new(1, 0, 0.5, 1)
		clip.Parent = holder
		local fill = Instance.new("Frame")
		fill.BorderSizePixel = 0
		fill.BackgroundColor3 = color
		fill.ZIndex = 0
		fill.Size = UDim2.fromScale(1, 2)
		fill.Position = if top then UDim2.new() else UDim2.fromScale(0, -1)
		corner(fill, UDim.new(0, if top then topRadius else bottomRadius))
		fill.Parent = clip
		table.insert(parts, fill)
	end
	holder.Parent = row
	segFills[row] = parts
end

local function resegment(g: Frame)
	local rows: { GuiObject } = {}
	for _, child in ipairs(g:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible then
			table.insert(rows, child)
		end
	end
	table.sort(rows, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	local outer = g:GetAttribute("SegOuter") :: number
	local inner = g:GetAttribute("SegInner") :: number
	local color = g:GetAttribute("SegColor") :: Color3
	for index, row in ipairs(rows) do
		local radiusOuter = if outer < 0 then math.floor(row.AbsoluteSize.Y / 2) else outer
		segmentRow(row, if index == 1 then radiusOuter else inner, if index == #rows then radiusOuter else inner, color)
	end
end

-- outer < 0 = a full pill (half the row height).
local function segmentedGroup(parent: Instance, name: string, outer: number, inner: number, color: Color3): Frame
	local g = frame(parent, name, UDim2.new(1, 0, 0, 0), C.white, 1)
	g.AutomaticSize = Enum.AutomaticSize.Y
	g:SetAttribute("SegOuter", outer)
	g:SetAttribute("SegInner", inner)
	g:SetAttribute("SegColor", color)
	local lay = Instance.new("UIListLayout")
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Padding = UDim.new(0, 2)
	lay.Parent = g
	local pending = false
	local function schedule()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			if g.Parent then
				resegment(g)
			end
		end)
	end
	g.ChildAdded:Connect(schedule)
	g.ChildRemoved:Connect(schedule)
	lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(schedule)
	return g
end

-- Modal group (Preferences semantics): outer 18, inner 4.
local function group(parent: Instance, name: string): Frame
	return segmentedGroup(parent, name, 18, 4, C.row)
end

-- Padded, auto-height wrapper for headers and footnotes (sits outside any group).
local function inset(parent: Instance, name: string): Frame
	local f = frame(parent, name, UDim2.new(1, 0, 0, 0), C.white, 1)
	f.AutomaticSize = Enum.AutomaticSize.Y
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = f
	local lay = Instance.new("UIListLayout")
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Padding = UDim.new(0, 2)
	lay.Parent = f
	return f
end

local function textRow(parent: Instance, name: string, placeholder: string, multi: boolean): TextBox
	local box = Instance.new("TextBox")
	box.Name = name
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = C.muted
	box.Text = ""
	box.TextColor3 = C.white
	box.TextSize = 15
	box.FontFace = face(Enum.FontWeight.Medium)
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = if multi then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center
	box.MultiLine = multi
	box.TextWrapped = multi
	box.Size = UDim2.new(1, 0, 0, if multi then 96 else 48)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.PaddingTop = UDim.new(0, if multi then 10 else 0)
	pad.PaddingBottom = UDim.new(0, if multi then 10 else 0)
	pad.Parent = box
	box.Parent = parent
	return box
end

local function buildModal(gui: ScreenGui, name: string, hasSub: boolean): Modal
	local modal = frame(gui, name, UDim2.new(1, -32, 0, 0), C.modal, 0)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.AutomaticSize = Enum.AutomaticSize.Y
	modal.Visible = false
	corner(modal, UDim.new(0, 28))
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(MODAL_MAX, 4000)
	limit.Parent = modal
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 16)
	pad.PaddingBottom = UDim.new(0, 16)
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = modal
	local lay = Instance.new("UIListLayout")
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Padding = UDim.new(0, 16)
	lay.Parent = modal
	local scale = Instance.new("UIScale")
	scale.Parent = modal

	local nav = frame(modal, "Nav", UDim2.new(1, 0, 0, if hasSub then 64 else 56), C.white, 1)
	nav.LayoutOrder = 0
	local left = clickable(nav, "Left", C.white, 1)
	left.Size = UDim2.new(0, 96, 1, 0)
	left.Text = "Cancel"
	left.FontFace = face(Enum.FontWeight.SemiBold)
	left.TextSize = 15
	left.TextColor3 = C.muted
	left.TextXAlignment = Enum.TextXAlignment.Left
	local right = clickable(nav, "Right", C.white, 1)
	right.AnchorPoint = Vector2.new(1, 0)
	right.Position = UDim2.new(1, 0, 0, 0)
	right.Size = UDim2.new(0, 96, 1, 0)
	right.Text = "Done"
	right.FontFace = face(Enum.FontWeight.Bold)
	right.TextSize = 15
	right.TextColor3 = C.white
	right.TextXAlignment = Enum.TextXAlignment.Right
	right.Visible = false
	local title = label(nav, "Title", "", 16, Enum.FontWeight.Bold, C.white)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Position = UDim2.new(0, 96, 0, if hasSub then 10 else 18)
	title.Size = UDim2.new(1, -192, 0, 20)
	local sub = label(nav, "Sub", "", 12, Enum.FontWeight.Medium, C.muted)
	sub.TextXAlignment = Enum.TextXAlignment.Center
	sub.Position = UDim2.new(0, 96, 0, 32)
	sub.Size = UDim2.new(1, -192, 0, 16)
	sub.Visible = hasSub

	local body = frame(modal, "Body", UDim2.new(1, 0, 0, 0), C.white, 1)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.LayoutOrder = 1
	local bodyLay = Instance.new("UIListLayout")
	bodyLay.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLay.Padding = UDim.new(0, 12)
	bodyLay.Parent = body

	return {
		frame = modal,
		scale = scale,
		nav = nav,
		left = left,
		right = right,
		title = title,
		sub = sub,
		body = body,
		tw = nil,
	}
end

local function presentModal(m: Modal)
	if m.tw then
		m.tw:Cancel()
	end
	m.frame.Visible = true
	m.scale.Scale = 0.92
	m.tw = tween(m.scale, 0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, { Scale = 1 })
end

local function dismissModal(m: Modal)
	if m.tw then
		m.tw:Cancel()
	end
	local t = tween(m.scale, 0.2, Enum.EasingStyle.Cubic, Enum.EasingDirection.In, { Scale = 0.9 })
	m.tw = t
	t.Completed:Connect(function()
		if m.tw == t then
			m.frame.Visible = false
			m.scale.Scale = 1
			m.tw = nil
		end
	end)
end

local function snapHide(m: Modal)
	if m.tw then
		m.tw:Cancel()
		m.tw = nil
	end
	m.frame.Visible = false
	m.scale.Scale = 1
end

local AdminSpotlightUI = {}
AdminSpotlightUI.__index = AdminSpotlightUI

function AdminSpotlightUI.new()
	local self = setmetatable({}, AdminSpotlightUI)
	self._conns = {} :: { RBXScriptConnection }
	self._footConns = {} :: { RBXScriptConnection }
	self._players = {} :: { PlayerEntry }
	self._allowed = {} :: { [string]: boolean }
	self._recent = {} :: { string }
	self._flat = {} :: { FlatEntry }
	self._speedLabels = {} :: { [string]: GuiButton }
	self._cursor = 0
	self._query = ""
	self._pickerQuery = ""
	self._overlay = nil :: string?
	self._preselect = nil :: string?
	self._floatSpeed = 3
	self._restoreSpeed = 3
	self._greetingRole = "Player"
	self._toastToken = 0
	self._dimToken = 0
	self._panelTween = nil :: Tween?
	self._dimTween = nil :: Tween?
	self._onPlayerPicked = nil :: ((PlayerEntry) -> ())?
	self._onAction = nil :: ((string) -> ())?
	self._onGear = nil :: ((string) -> ())?
	self._onClose = nil :: (() -> ())?

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "04-AdminSpotlight"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 20
	gui.Enabled = false
	-- Designed colours only: the accent shows on the icon discs, not the black surfaces.
	gui:SetAttribute("AccentNoTint", true)
	gui.Parent = playerGui
	self._gui = gui

	-- Main panel: transparent wrapper, every item floats.
	local main = frame(gui, "MainWrapper", UDim2.new(1, -32, 1, -32), C.white, 1)
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.Position = UDim2.fromScale(0.5, 0.5)
	main.Visible = false
	local mainLimit = Instance.new("UISizeConstraint")
	mainLimit.MaxSize = MAIN_MAX
	mainLimit.Parent = main
	local mainScale = Instance.new("UIScale")
	mainScale.Parent = main
	self._main = main
	self._mainScale = mainScale

	-- Header: search pill plus close button.
	local header = frame(main, "Header", UDim2.new(1, 0, 0, 54), C.white, 1)
	local searchPill = frame(header, "SearchPill", UDim2.new(1, -46, 1, 0), C.item, 0)
	corner(searchPill, UDim.new(1, 0))
	local searchIcon = Instance.new("ImageLabel")
	searchIcon.Name = "SearchIcon"
	searchIcon.BackgroundTransparency = 1
	searchIcon.Image = ICON_SEARCH
	searchIcon.ImageColor3 = C.muted
	searchIcon.Size = UDim2.fromOffset(20, 20)
	searchIcon.Position = UDim2.fromOffset(18, 17)
	searchIcon.Parent = searchPill
	local search = Instance.new("TextBox")
	search.Name = "Query"
	search.BackgroundTransparency = 1
	search.BorderSizePixel = 0
	search.ClearTextOnFocus = false
	search.PlaceholderText = "Search players, actions or /commands"
	search.PlaceholderColor3 = C.muted
	search.Text = ""
	search.TextColor3 = C.white
	search.TextSize = 16
	search.FontFace = face(Enum.FontWeight.Medium)
	search.TextXAlignment = Enum.TextXAlignment.Left
	search.Position = UDim2.fromOffset(52, 0)
	search.Size = UDim2.new(1, -52 - 38, 1, 0)
	search.Parent = searchPill
	local keyHint = frame(searchPill, "KeyHint", UDim2.fromOffset(22, 22), C.hover, 0)
	keyHint.AnchorPoint = Vector2.new(1, 0.5)
	keyHint.Position = UDim2.new(1, -16, 0.5, 0)
	corner(keyHint, UDim.new(0, 6))
	local hintText = label(keyHint, "Text", "/", 12, Enum.FontWeight.Regular, C.muted)
	hintText.FontFace = MONO
	hintText.TextXAlignment = Enum.TextXAlignment.Center
	self._search = search

	local closeBtn = clickable(header, "Close", C.item, 0)
	closeBtn.Size = UDim2.fromOffset(36, 36)
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, 0, 0.5, 0)
	corner(closeBtn, UDim.new(1, 0))
	local closeIcon = Instance.new("ImageLabel")
	closeIcon.Name = "CloseIcon"
	closeIcon.BackgroundTransparency = 1
	closeIcon.Image = ICON_CLOSE
	closeIcon.ImageColor3 = C.white
	closeIcon.Size = UDim2.fromOffset(14, 14)
	closeIcon.Position = UDim2.new(0.5, -7, 0.5, -7)
	closeIcon.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(function()
		if self._onClose then
			self._onClose()
		else
			self:hide()
		end
	end)

	-- Action list.
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, 64)
	list.Size = UDim2.new(1, 0, 1, -64)
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 0
	list.ClipsDescendants = true
	list.Parent = main
	local listLay = Instance.new("UIListLayout")
	listLay.SortOrder = Enum.SortOrder.LayoutOrder
	listLay.Padding = UDim.new(0, 14)
	listLay.Parent = list
	self._list = list
	self._scrollbar = OverlayScrollbar.attach(list, list)

	-- In-panel toast (white pill, bottom of the panel).
	local toast = Instance.new("TextLabel")
	toast.Name = "Toast"
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.new(0.5, 0, 1, -8)
	toast.Size = UDim2.fromOffset(0, 40)
	toast.AutomaticSize = Enum.AutomaticSize.X
	toast.BackgroundColor3 = C.white
	toast.BackgroundTransparency = 0
	toast.BorderSizePixel = 0
	toast.Text = ""
	toast.TextColor3 = C.black
	toast.TextSize = 14
	toast.FontFace = face(Enum.FontWeight.SemiBold)
	toast.Visible = false
	toast.ZIndex = 5
	corner(toast, UDim.new(1, 0))
	local toastPad = Instance.new("UIPadding")
	toastPad.PaddingLeft = UDim.new(0, 18)
	toastPad.PaddingRight = UDim.new(0, 18)
	toastPad.Parent = toast
	toast.Parent = main
	self._toast = toast

	-- Dim sits above the main panel and below both modals.
	local dim = clickable(gui, "Dim", C.black, 1)
	dim.Size = UDim2.fromScale(1, 1)
	dim.Visible = false
	dim.ZIndex = 2
	dim.MouseButton1Click:Connect(function()
		self:closeOverlay()
	end)
	self._dim = dim

	-- Player picker and action sheet.
	self._picker = buildModal(gui, "PlayerPicker", true)
	self._sheet = buildModal(gui, "ActionSheet", false)
	self._picker.frame.ZIndex = 3
	self._sheet.frame.ZIndex = 3
	self._picker.title.Text = "Choose Player"
	self._picker.right.Visible = false
	self._picker.left.MouseButton1Click:Connect(function()
		self:closePlayerPopup()
	end)

	local pickerSearchGroup = group(self._picker.body, "SearchGroup")
	pickerSearchGroup.LayoutOrder = 0
	local pickerSearch = textRow(pickerSearchGroup, "Filter", "Search players", false)
	self._pickerSearch = pickerSearch
	pickerSearch:GetPropertyChangedSignal("Text"):Connect(function()
		self._pickerQuery = pickerSearch.Text
		self:_renderPicker()
	end)

	search:GetPropertyChangedSignal("Text"):Connect(function()
		self._query = search.Text
		self:_renderMain()
	end)
	search.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			self:_runCursor()
		end
	end)

	table.insert(self._conns, UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Escape then
			if self._overlay ~= nil then
				self:closeOverlay()
			elseif self:isVisible() and self._onClose then
				self._onClose()
			end
			return
		end
		if not self:isVisible() or self._overlay ~= nil then
			return
		end
		if key == Enum.KeyCode.Slash and not gameProcessed then
			self._search:CaptureFocus()
		elseif key == Enum.KeyCode.Up then
			self:_moveCursor(-1)
		elseif key == Enum.KeyCode.Down then
			self:_moveCursor(1)
		end
	end))

	return self
end

-- ============================================================
-- Shared small builders (need the class helpers above)
-- ============================================================

local function openSection(list: Instance, title: string, tag: string?, order: number): Frame
	local box = frame(list, "Section", UDim2.new(1, 0, 0, 0), C.white, 1)
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.LayoutOrder = order
	local lay = Instance.new("UIListLayout")
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Padding = UDim.new(0, 8)
	lay.Parent = box
	local head = frame(box, "Head", UDim2.new(1, 0, 0, 24), C.white, 1)
	head.LayoutOrder = 1
	local left = frame(head, "Label", UDim2.fromOffset(0, 24), C.item, 0)
	left.AutomaticSize = Enum.AutomaticSize.X
	corner(left, UDim.new(1, 0))
	local leftPad = Instance.new("UIPadding")
	leftPad.PaddingLeft = UDim.new(0, 10)
	leftPad.PaddingRight = UDim.new(0, 10)
	leftPad.Parent = left
	local leftText = label(left, "Text", title, 12, Enum.FontWeight.Bold, C.sub)
	leftText.AutomaticSize = Enum.AutomaticSize.X
	leftText.Size = UDim2.fromOffset(0, 24)
	if tag then
		local right = frame(head, "Tag", UDim2.fromOffset(0, 24), C.item, 0)
		right.AutomaticSize = Enum.AutomaticSize.X
		right.AnchorPoint = Vector2.new(1, 0)
		right.Position = UDim2.new(1, 0, 0, 0)
		corner(right, UDim.new(1, 0))
		local rightPad = Instance.new("UIPadding")
		rightPad.PaddingLeft = UDim.new(0, 10)
		rightPad.PaddingRight = UDim.new(0, 10)
		rightPad.Parent = right
		local rightText = label(right, "Text", tag, 12, Enum.FontWeight.Bold, C.sub)
		rightText.AutomaticSize = Enum.AutomaticSize.X
		rightText.Size = UDim2.fromOffset(0, 24)
	end
	return box
end

-- ============================================================
-- Main panel
-- ============================================================

function AdminSpotlightUI:_setCursor(index: number)
	self._cursor = index
	self:_paintCursor()
end

function AdminSpotlightUI:_paintCursor()
	for index, entry in ipairs(self._flat) do
		local lit = index == self._cursor
		if entry.pill then
			entry.row.BackgroundColor3 = if lit then C.hover else C.item
		else
			paintSegment(entry.row, if lit then C.hover else C.item)
		end
	end
end

function AdminSpotlightUI:_moveCursor(delta: number)
	local n = #self._flat
	if n == 0 then
		return
	end
	local c = self._cursor + delta
	if self._cursor == 0 then
		c = if delta > 0 then 1 else n
	end
	if c < 1 then
		c = n
	elseif c > n then
		c = 1
	end
	self:_setCursor(c)
end

function AdminSpotlightUI:_runCursor()
	if self._cursor == 0 then
		return
	end
	local entry = self._flat[self._cursor]
	if entry then
		self:_run(entry.id)
	end
end

function AdminSpotlightUI:_pushRecent(id: string)
	local out = { id }
	for _, existing in ipairs(self._recent) do
		if existing ~= id and #out < RECENT_MAX then
			table.insert(out, existing)
		end
	end
	self._recent = out
end

function AdminSpotlightUI:_resetSearch()
	self._query = ""
	self._search.Text = ""
	self:_renderMain()
end

function AdminSpotlightUI:_run(id: string)
	local meta = ACTION_META[id]
	if meta == nil or self._onAction == nil then
		return
	end
	local rest = ""
	local query = string.lower(trimmed(self._query))
	if string.sub(query, 1, 1) == "/" then
		local _cmd, parsedRest = parseCommand(query)
		rest = parsedRest
	end
	self:_pushRecent(id)
	self._preselect = if meta.needsPlayer and rest ~= "" then rest else nil
	local ok, err = pcall(self._onAction, id)
	self._preselect = nil
	if not ok then
		warn("[AdminSpotlightUI] action failed: " .. tostring(err))
	end
	self:_resetSearch()
end

function AdminSpotlightUI:_recentCell(parent: Instance, id: string, order: number)
	local meta = ACTION_META[id]
	local cell = clickable(parent, "Recent_" .. id, C.item, 0)
	cell.LayoutOrder = order
	corner(cell, UDim.new(1, 0))
	local discColor, discGradient = accentDisc()
	makeDisc(cell, meta.glyph, discColor, discGradient, 38, UDim2.fromOffset(8, 8))
	local title = label(cell, "Title", meta.title, 14, Enum.FontWeight.Bold, C.white)
	title.Position = UDim2.fromOffset(54, 0)
	title.Size = UDim2.new(1, -62, 1, 0)
	table.insert(self._flat, { id = id, row = cell, pill = true })
	local index = #self._flat
	cell.MouseEnter:Connect(function()
		self:_setCursor(index)
	end)
	cell.MouseButton1Click:Connect(function()
		self:_run(id)
	end)
end

function AdminSpotlightUI:_actionRow(parent: Instance, id: string, order: number)
	local meta = ACTION_META[id]
	local row = clickable(parent, "Row_" .. id, C.item, 1)
	row.Size = UDim2.new(1, 0, 0, 54)
	row.LayoutOrder = order
	local discColor, discGradient = accentDisc()
	makeDisc(row, meta.glyph, discColor, discGradient, 38, UDim2.fromOffset(8, 8))

	local title = label(row, "Title", meta.title, 15, Enum.FontWeight.Bold, C.white)
	title.Position = UDim2.fromOffset(54, 8)
	title.Size = UDim2.new(1, -54 - 130, 0, 20)
	local sub = label(row, "Subtitle", meta.subtitle, 14, Enum.FontWeight.Medium, C.sub)
	sub.Position = UDim2.fromOffset(54, 28)
	sub.Size = UDim2.new(1, -54 - 130, 0, 18)

	local trailing = 14
	if meta.speed then
		local pill = clickable(row, "SpeedPill", C.ctrl, 0)
		pill.AnchorPoint = Vector2.new(1, 0)
		pill.Position = UDim2.new(1, -14, 0.5, -11)
		pill.Size = UDim2.fromOffset(30, 22)
		corner(pill, UDim.new(1, 0))
		local value = if id == "gravity" then self._restoreSpeed else self._floatSpeed
		local pillText = label(pill, "Value", tostring(value), 12, Enum.FontWeight.Bold, C.white)
		pillText.TextXAlignment = Enum.TextXAlignment.Center
		self._speedLabels[id] = pill
		pill.MouseButton1Click:Connect(function()
			if self._onGear then
				self._onGear(id)
			end
		end)
		trailing = 54
	elseif meta.sheet then
		chevron(row, UDim2.new(1, -26, 0.5, -6), C.muted)
		trailing = 34
	end

	local alias = label(row, "Alias", meta.alias, 12, Enum.FontWeight.Regular, C.muted)
	alias.FontFace = MONO
	alias.TextXAlignment = Enum.TextXAlignment.Right
	alias.AnchorPoint = Vector2.new(1, 0.5)
	alias.AutomaticSize = Enum.AutomaticSize.X
	alias.Size = UDim2.fromOffset(0, 16)
	alias.Position = UDim2.new(1, -trailing, 0.5, 0)

	table.insert(self._flat, { id = id, row = row, pill = false })
	local index = #self._flat
	row.MouseEnter:Connect(function()
		self:_setCursor(index)
	end)
	row.MouseButton1Click:Connect(function()
		self:_run(id)
	end)
end

function AdminSpotlightUI:_renderMain()
	local list = self._list
	clearKids(list)
	self._flat = {}

	local query = string.lower(trimmed(self._query))
	local cmdMode = string.sub(query, 1, 1) == "/"
	local cmdName = ""
	if cmdMode then
		cmdName = parseCommand(query)
	end

	local function matches(id: string, meta: ActionMeta): boolean
		if self._allowed[id] ~= true then
			return false
		end
		if query == "" then
			return true
		end
		if cmdMode then
			local name = string.lower(string.sub(meta.alias, 2))
			return string.sub(name, 1, #cmdName) == cmdName
		end
		return string.find(string.lower(meta.title), query, 1, true) ~= nil
			or string.find(string.lower(meta.subtitle), query, 1, true) ~= nil
			or string.find(string.lower(meta.alias), query, 1, true) ~= nil
	end

	local recent: { string } = {}
	if query == "" then
		for _, id in ipairs(self._recent) do
			if self._allowed[id] == true and ACTION_META[id] ~= nil then
				table.insert(recent, id)
			end
		end
	end
	local players: { string } = {}
	local servers: { string } = {}
	for _, id in ipairs(ACTION_ORDER) do
		local meta = ACTION_META[id]
		if matches(id, meta) then
			if meta.needsPlayer then
				table.insert(players, id)
			else
				table.insert(servers, id)
			end
		end
	end

	if #recent == 0 and #players == 0 and #servers == 0 then
		local empty = frame(list, "Empty", UDim2.new(1, 0, 0, 0), C.white, 1)
		empty.AutomaticSize = Enum.AutomaticSize.Y
		empty.LayoutOrder = 1
		local emptyLay = Instance.new("UIListLayout")
		emptyLay.SortOrder = Enum.SortOrder.LayoutOrder
		emptyLay.Padding = UDim.new(0, 4)
		emptyLay.Parent = empty
		local heading = wrapText(empty, "Title", "No results", 15, Enum.FontWeight.Bold, C.white)
		heading.TextXAlignment = Enum.TextXAlignment.Center
		local hintLine = wrapText(empty, "Hint", "Try a player name or a command like /bring", 12, Enum.FontWeight.Medium, C.muted)
		hintLine.TextXAlignment = Enum.TextXAlignment.Center
		self._cursor = 0
		return
	end

	local order = 0
	if #recent > 0 then
		order += 1
		local box = openSection(list, "Recent", nil, order)
		local grid = frame(box, "Grid", UDim2.new(1, 0, 0, 0), C.white, 1)
		grid.AutomaticSize = Enum.AutomaticSize.Y
		grid.LayoutOrder = 2
		local gridLay = Instance.new("UIGridLayout")
		gridLay.CellSize = UDim2.new(0.5, -1, 0, 54)
		gridLay.CellPadding = UDim2.fromOffset(2, 2)
		gridLay.FillDirectionMaxCells = 2
		gridLay.SortOrder = Enum.SortOrder.LayoutOrder
		gridLay.Parent = grid
		for index, id in ipairs(recent) do
			self:_recentCell(grid, id, index)
		end
	end
	if #players > 0 then
		order += 1
		local box = openSection(list, "Player actions", nil, order)
		local rows = segmentedGroup(box, "Rows", -1, 6, C.item)
		rows.LayoutOrder = 2
		for index, id in ipairs(players) do
			self:_actionRow(rows, id, index)
		end
	end
	if #servers > 0 then
		order += 1
		local box = openSection(list, "Server", "Affects everyone", order)
		local rows = segmentedGroup(box, "Rows", -1, 6, C.item)
		rows.LayoutOrder = 2
		for index, id in ipairs(servers) do
			self:_actionRow(rows, id, index)
		end
	end

	self._cursor = if query ~= "" and #self._flat > 0 then 1 else 0
	self:_paintCursor()
end

-- ============================================================
-- Overlays: player picker and action sheet share one dim
-- ============================================================

function AdminSpotlightUI:_showDim()
	self._dimToken += 1
	self._dim.Visible = true
	if self._dimTween then
		self._dimTween:Cancel()
	end
	self._dimTween = tween(self._dim, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { BackgroundTransparency = DIM_T })
	tween(self._mainScale, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, { Scale = 0.96 })
end

function AdminSpotlightUI:_hideDim()
	self._dimToken += 1
	local token = self._dimToken
	if self._dimTween then
		self._dimTween:Cancel()
	end
	self._dimTween = tween(self._dim, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { BackgroundTransparency = 1 })
	tween(self._mainScale, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, { Scale = 1 })
	task.delay(0.22, function()
		if token == self._dimToken and self._overlay == nil then
			self._dim.Visible = false
		end
	end)
end

function AdminSpotlightUI:_forceClose()
	self._onPlayerPicked = nil
	self._overlay = nil
	self:_disconnectFoot()
	snapHide(self._picker)
	snapHide(self._sheet)
	self._dimToken += 1
	if self._dimTween then
		self._dimTween:Cancel()
	end
	self._dim.Visible = false
	self._dim.BackgroundTransparency = 1
	self._mainScale.Scale = 1
end

function AdminSpotlightUI:_renderPicker()
	local body = self._picker.body
	clearKids(body, { SearchGroup = true })
	local query = string.lower(trimmed(self._pickerQuery))

	local head = inset(body, "Header")
	head.LayoutOrder = 1
	local headText = label(head, "FieldLabel", tostring(#self._players) .. " IN SERVER", 12, Enum.FontWeight.Bold, C.muted)
	headText.TextTruncate = Enum.TextTruncate.None
	headText.Size = UDim2.new(1, 0, 0, 16)

	local rows = group(body, "Players")
	rows.LayoutOrder = 2
	local shown = 0
	for _, entry in ipairs(self._players) do
		local name = string.lower(entry.username)
		local display = string.lower(entry.displayName)
		if query == "" or string.find(name, query, 1, true) or string.find(display, query, 1, true) then
			shown += 1
			self:_playerRow(rows, entry, shown)
		end
	end
	if shown == 0 then
		local none = inset(body, "None")
		none.LayoutOrder = 3
		wrapText(none, "Text", "No players match", 12, Enum.FontWeight.Medium, C.muted)
	end
end

function AdminSpotlightUI:_playerRow(parent: Instance, entry: PlayerEntry, order: number)
	local row = clickable(parent, "Player_" .. tostring(entry.userId), C.row, 1)
	row.Size = UDim2.new(1, 0, 0, 56)
	row.LayoutOrder = order

	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.BackgroundColor3 = C.ctrl
	avatar.BackgroundTransparency = 0
	avatar.BorderSizePixel = 0
	avatar.Image = thumbOf(entry.userId)
	avatar.Size = UDim2.fromOffset(36, 36)
	avatar.Position = UDim2.fromOffset(10, 10)
	avatar.Parent = row
	corner(avatar, UDim.new(1, 0))

	local isSelf = entry.userId == Players.LocalPlayer.UserId
	local shownName = if entry.displayName ~= "" then entry.displayName else entry.username
	local name = label(row, "Name", shownName .. (if isSelf then " (You)" else ""), 15, Enum.FontWeight.Bold, C.white)
	name.Position = UDim2.fromOffset(56, 9)
	name.Size = UDim2.new(1, -56 - 36, 0, 20)
	local handle = label(row, "Handle", "@" .. entry.username, 12, Enum.FontWeight.Medium, C.muted)
	handle.Position = UDim2.fromOffset(56, 29)
	handle.Size = UDim2.new(1, -56 - 36, 0, 16)
	chevron(row, UDim2.new(1, -22, 0.5, -6), C.muted)

	hoverRow(row, C.ctrl)
	row.MouseButton1Click:Connect(function()
		self:_pickPlayer(entry)
	end)
end

function AdminSpotlightUI:_pickPlayer(entry: PlayerEntry)
	local cb = self._onPlayerPicked
	self._onPlayerPicked = nil
	snapHide(self._picker)
	if cb == nil then
		self._overlay = nil
		self:_hideDim()
		return
	end
	-- Dim stays up while the callback runs; it either opens a sheet or clears the dim below.
	self._overlay = "pending"
	cb(entry)
	if self._overlay == "pending" then
		self._overlay = nil
		self:_hideDim()
	end
end

function AdminSpotlightUI:_disconnectFoot()
	for _, conn in ipairs(self._footConns) do
		conn:Disconnect()
	end
	table.clear(self._footConns)
end

function AdminSpotlightUI:_applyFoot(leftText: string, leftFn: () -> (), right: SheetFootButton?)
	self:_disconnectFoot()
	local sheet = self._sheet
	sheet.left.Text = leftText
	table.insert(self._footConns, sheet.left.MouseButton1Click:Connect(function()
		leftFn()
	end))
	if right then
		local commit = right.onClick
		sheet.right.Text = right.text
		sheet.right.Visible = true
		table.insert(self._footConns, sheet.right.MouseButton1Click:Connect(function()
			commit()
		end))
	else
		sheet.right.Visible = false
	end
end

-- ============================================================
-- Public API (mirrors AdminHubUI)
-- ============================================================

function AdminSpotlightUI:bindClose(callback: () -> ())
	self._onClose = callback
end

function AdminSpotlightUI:bindAction(callback: (string) -> ())
	self._onAction = callback
end

function AdminSpotlightUI:bindGear(callback: (string) -> ())
	self._onGear = callback
end

-- The Spotlight has no filter tabs; the callback is stored for API parity only.
function AdminSpotlightUI:bindFilter(_callback: (string) -> ())
end

function AdminSpotlightUI:setAllowedActions(allowed: { [string]: boolean })
	self._allowed = allowed
	if self:isVisible() then
		self:_renderMain()
	end
end

function AdminSpotlightUI:setFloatSpeed(speed: number)
	self._floatSpeed = speed
	local pill = self._speedLabels.ungravity
	if pill then
		(pill:FindFirstChild("Value") :: TextLabel).Text = tostring(speed)
	end
end

function AdminSpotlightUI:getFloatSpeed(): number
	return self._floatSpeed
end

function AdminSpotlightUI:setRestoreSpeed(speed: number)
	self._restoreSpeed = speed
	local pill = self._speedLabels.gravity
	if pill then
		(pill:FindFirstChild("Value") :: TextLabel).Text = tostring(speed)
	end
end

function AdminSpotlightUI:getRestoreSpeed(): number
	return self._restoreSpeed
end

-- Stored only: the Spotlight header has no greeting line.
function AdminSpotlightUI:setGreetingRole(role: string?)
	self._greetingRole = if type(role) == "string" and role ~= "" then role else "Player"
end

function AdminSpotlightUI:show()
	if self._panelTween then
		self._panelTween:Cancel()
		self._panelTween = nil
	end
	self._gui.Enabled = true
	self._main.Visible = true
	self._main.Position = UDim2.new(0.5, 0, 0.5, PANEL_SLIDE)
	self:_resetSearch()
	self._panelTween = tween(self._main, 1.0, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out, {
		Position = UDim2.fromScale(0.5, 0.5),
	})
end

function AdminSpotlightUI:hide()
	self:_forceClose()
	if not self._main.Visible then
		self._gui.Enabled = false
		return
	end
	if self._panelTween then
		self._panelTween:Cancel()
	end
	local t = tween(self._main, 0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.In, {
		Position = UDim2.new(0.5, 0, 0.5, PANEL_SLIDE),
	})
	self._panelTween = t
	t.Completed:Connect(function()
		if self._panelTween == t then
			self._gui.Enabled = false
			self._main.Visible = false
			self._panelTween = nil
		end
	end)
end

function AdminSpotlightUI:isVisible(): boolean
	return self._gui.Enabled and self._main.Visible
end

function AdminSpotlightUI:getScreenGui(): ScreenGui
	return self._gui
end

function AdminSpotlightUI:getMainWrapper(): Frame
	return self._main
end

-- White pill at the bottom of the panel. Falls back to NotifService when the panel is closed.
function AdminSpotlightUI:toast(message: string, notifType: NotifService.NotifType?)
	if type(message) ~= "string" or message == "" then
		return
	end
	if not self:isVisible() then
		NotifService.show({
			message = message,
			notifType = notifType or "INFO",
			domain = "admin",
			title = "Admin Panel",
		})
		return
	end
	self._toastToken = self._toastToken + 1
	local token = self._toastToken
	local toast = self._toast
	toast.Text = message
	toast.Visible = true
	toast.BackgroundTransparency = 0
	toast.TextTransparency = 0
	toast.Position = UDim2.new(0.5, 0, 1, 12)
	tween(toast, 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Position = UDim2.new(0.5, 0, 1, -8) })
	task.delay(TOAST_HOLD, function()
		if token ~= self._toastToken then
			return
		end
		tween(toast, 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
			BackgroundTransparency = 1,
			TextTransparency = 1,
		})
		task.delay(0.26, function()
			if token == self._toastToken then
				toast.Visible = false
			end
		end)
	end)
end

function AdminSpotlightUI:setPlayers(players: { PlayerEntry })
	self._players = players
	if self._overlay == "player" then
		self:_renderPicker()
	end
end

function AdminSpotlightUI:openPlayerPopup(title: string, onPick: (PlayerEntry) -> ())
	-- "/bring sari" pre-selects the matching player, so the picker is skipped.
	local wanted = self._preselect
	self._preselect = nil
	if wanted ~= nil then
		local entry = findPlayerByPrefix(self._players, wanted)
		if entry then
			onPick(entry)
			return
		end
	end

	self._onPlayerPicked = onPick
	local action = string.gsub(title, " who%?$", "")
	local dash = string.find(action, " \226\128\148", 1, true)
	if dash then
		action = string.sub(action, 1, dash - 1)
	end
	self._picker.sub.Text = "for " .. action
	self._pickerQuery = ""
	self._pickerSearch.Text = ""
	if self._sheet.frame.Visible then
		snapHide(self._sheet)
	end
	self:_disconnectFoot()
	self._overlay = "player"
	self:_renderPicker()
	self:_showDim()
	presentModal(self._picker)
end

function AdminSpotlightUI:closePlayerPopup(keepDim: boolean?)
	self._onPlayerPicked = nil
	if not self._picker.frame.Visible then
		if not keepDim and self._overlay == "player" then
			self._overlay = nil
			self:_hideDim()
		end
		return
	end
	if keepDim then
		snapHide(self._picker)
		self._overlay = "pending"
		return
	end
	self._overlay = nil
	dismissModal(self._picker)
	self:_hideDim()
end

function AdminSpotlightUI:openSheet(
	_actionId: string,
	title: string,
	buildBody: (GuiObject) -> (),
	footButtons: { SheetFootButton }?,
	_chromeActionId: string?
)
	snapHide(self._picker)
	self._onPlayerPicked = nil
	self._sheet.title.Text = title
	self:_applyFoot("Cancel", function()
		self:closeSheet()
	end, nil)
	clearKids(self._sheet.body)
	buildBody(self._sheet.body)
	if footButtons then
		self:setSheetFoot(footButtons)
	end
	self._overlay = "sheet"
	self:_showDim()
	presentModal(self._sheet)
end

function AdminSpotlightUI:closeSheet(keepDim: boolean?)
	self:_disconnectFoot()
	if not self._sheet.frame.Visible then
		if not keepDim and self._overlay == "sheet" then
			self._overlay = nil
			self:_hideDim()
		end
		return
	end
	if keepDim then
		snapHide(self._sheet)
		self._overlay = "pending"
		return
	end
	self._overlay = nil
	dismissModal(self._sheet)
	self:_hideDim()
end

function AdminSpotlightUI:closeOverlay(force: boolean?)
	if force then
		self:_forceClose()
		return
	end
	if self._overlay == "player" then
		self:closePlayerPopup()
	elseif self._overlay == "sheet" then
		self:closeSheet()
	end
end

-- Nav bar: the secondary button is the left action ("Cancel" when it reads Cancel), the
-- primary button is the right action text.
function AdminSpotlightUI:setSheetFoot(buttons: { SheetFootButton })
	local secondary: SheetFootButton? = nil
	local primary: SheetFootButton? = nil
	for index, def in ipairs(buttons) do
		if def.primary == true or (def.primary == nil and index == #buttons) then
			primary = def
		elseif secondary == nil then
			secondary = def
		end
	end
	local leftDef = secondary
	local leftText = if leftDef then leftDef.text else "Cancel"
	self:_applyFoot(leftText, function()
		if leftDef then
			leftDef.onClick()
		else
			self:closeSheet()
		end
	end, primary)
end

function AdminSpotlightUI:showSelectedPlayer(parent: Instance, entry: PlayerEntry?, onChange: (() -> ())?)
	if not entry then
		return
	end
	local g = group(parent, "SelectedPlayerInfo")
	g.LayoutOrder = -10
	local row = clickable(g, "Target", C.row, 1)
	row.Size = UDim2.new(1, 0, 0, 56)
	row.LayoutOrder = 1

	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.BackgroundColor3 = C.ctrl
	avatar.BackgroundTransparency = 0
	avatar.BorderSizePixel = 0
	avatar.Image = thumbOf(entry.userId)
	avatar.Size = UDim2.fromOffset(40, 40)
	avatar.Position = UDim2.fromOffset(8, 8)
	avatar.Parent = row
	corner(avatar, UDim.new(1, 0))

	local shownName = if entry.displayName ~= "" then entry.displayName else entry.username
	local name = label(row, "Name", shownName, 15, Enum.FontWeight.Bold, C.white)
	name.Position = UDim2.fromOffset(60, 10)
	name.Size = UDim2.new(1, -60 - 110, 0, 20)
	local handle = label(row, "Handle", "@" .. entry.username, 12, Enum.FontWeight.Medium, C.muted)
	handle.Position = UDim2.fromOffset(60, 30)
	handle.Size = UDim2.new(1, -60 - 110, 0, 16)

	if onChange then
		local change = label(row, "Change", "Change", 15, Enum.FontWeight.SemiBold, C.muted)
		change.TextXAlignment = Enum.TextXAlignment.Right
		change.AnchorPoint = Vector2.new(1, 0.5)
		change.Position = UDim2.new(1, -30, 0.5, 0)
		change.Size = UDim2.fromOffset(72, 20)
		chevron(row, UDim2.new(1, -22, 0.5, -6), C.muted)
		hoverRow(row, C.ctrl)
		row.MouseButton1Click:Connect(function()
			if onChange then
				onChange()
			end
		end)
	end
end

function AdminSpotlightUI:addCallout(parent: Instance, text: string, variant: string?, title: string?)
	local _ = variant
	local box = inset(parent, "Callout")
	if title and title ~= "" then
		local heading = wrapText(box, "Title", title, 12, Enum.FontWeight.Bold, C.white)
		heading.LayoutOrder = 1
	end
	local body = wrapText(box, "Text", text, 12, Enum.FontWeight.Medium, C.muted)
	body.LayoutOrder = 2
end

function AdminSpotlightUI:addHint(parent: Instance, text: string)
	local box = inset(parent, "Hint")
	wrapText(box, "Hint", text, 12, Enum.FontWeight.Medium, C.muted)
end

function AdminSpotlightUI:addFieldLabel(parent: Instance, text: string)
	local box = inset(parent, "FieldLabelBox")
	local t = label(box, "FieldLabel", string.upper(text), 12, Enum.FontWeight.Bold, C.muted)
	t.TextTruncate = Enum.TextTruncate.None
	t.Size = UDim2.new(1, 0, 0, 16)
end

function AdminSpotlightUI:addPreview(parent: Instance, text: string): TextLabel
	local g = group(parent, "Preview")
	local row = frame(g, "Row", UDim2.new(1, 0, 0, 64), C.white, 1)
	local t = label(row, "Preview", text, 22, Enum.FontWeight.Bold, C.white)
	t.TextXAlignment = Enum.TextXAlignment.Center
	return t
end

function AdminSpotlightUI:addTextBox(parent: Instance, name: string, placeholder: string, multiLine: boolean?): TextBox
	local g = group(parent, "Input_" .. name)
	return textRow(g, name, placeholder, multiLine == true)
end

-- Check list: a row per option, a ring on the right, filled white on the picked row.
function AdminSpotlightUI:addPickGrid(
	parent: Instance,
	options: { { key: string, label: string, desc: string?, color: Color3? } },
	initialKey: string,
	onChanged: (string) -> (),
	columns: number?
): () -> string
	local _ = columns
	local picked = initialKey
	local g = group(parent, "PickGrid")
	local rings: { [string]: { ring: Frame, core: Frame } } = {}

	local function sync()
		for key, pair in pairs(rings) do
			local on = key == picked
			pair.ring.BackgroundColor3 = if on then C.white else C.ctrl
			pair.core.Visible = on
		end
	end

	for index, opt in ipairs(options) do
		local hasDesc = opt.desc ~= nil and opt.desc ~= ""
		local row = clickable(g, "Pick_" .. opt.key, C.row, 1)
		row.Size = UDim2.new(1, 0, 0, if hasDesc then 56 else 48)
		row.LayoutOrder = index
		local title = label(row, "T", opt.label, 15, Enum.FontWeight.Medium, C.white)
		title.Position = UDim2.fromOffset(16, if hasDesc then 9 else 0)
		title.Size = UDim2.new(1, -70, 0, if hasDesc then 20 else 48)
		if hasDesc then
			local desc = label(row, "D", opt.desc :: string, 12, Enum.FontWeight.Medium, C.muted)
			desc.Position = UDim2.fromOffset(16, 29)
			desc.Size = UDim2.new(1, -70, 0, 16)
		end
		local ring = frame(row, "Ring", UDim2.fromOffset(22, 22), C.ctrl, 0)
		ring.AnchorPoint = Vector2.new(1, 0.5)
		ring.Position = UDim2.new(1, -16, 0.5, 0)
		corner(ring, UDim.new(1, 0))
		local core = frame(ring, "Core", UDim2.fromOffset(8, 8), C.black, 0)
		core.AnchorPoint = Vector2.new(0.5, 0.5)
		core.Position = UDim2.fromScale(0.5, 0.5)
		corner(core, UDim.new(1, 0))
		rings[opt.key] = { ring = ring, core = core }
		hoverRow(row, C.ctrl)
		row.MouseButton1Click:Connect(function()
			picked = opt.key
			sync()
			onChanged(picked)
		end)
	end
	sync()
	return function()
		return picked
	end
end

-- Segmented control for up to SEGMENT_MAX values; larger sets wrap into pill chips.
function AdminSpotlightUI:addChipRow(parent: Instance, values: { string }, initial: string, onChanged: (string) -> ()): () -> string
	local picked = initial
	local count = #values

	if count <= SEGMENT_MAX then
		local wrap = frame(parent, "ChipRow", UDim2.new(1, 0, 0, 32), C.white, 1)
		local track = frame(wrap, "Track", UDim2.new(1, 0, 1, 0), C.ctrl, 0)
		corner(track, UDim.new(0, 9))
		local thumb = frame(track, "Thumb", UDim2.new(1 / count, -4, 1, -4), C.white, 0)
		corner(thumb, UDim.new(0, 7))
		local labels: { [string]: TextButton } = {}
		local function indexOf(value: string): number
			for i, v in ipairs(values) do
				if v == value then
					return i
				end
			end
			return 1
		end
		local function sync(animate: boolean)
			local idx = indexOf(picked)
			local pos = UDim2.new((idx - 1) / count, 2, 0, 2)
			if animate then
				tween(thumb, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Position = pos })
			else
				thumb.Position = pos
			end
			for value, btn in pairs(labels) do
				btn.TextColor3 = if value == picked then C.black else C.muted
			end
		end
		for i, value in ipairs(values) do
			local seg = clickable(track, "Chip_" .. value, C.white, 1)
			seg.Position = UDim2.new((i - 1) / count, 0, 0, 0)
			seg.Size = UDim2.new(1 / count, 0, 1, 0)
			seg.Text = value
			seg.TextSize = 13
			seg.FontFace = face(Enum.FontWeight.SemiBold)
			seg.TextColor3 = C.muted
			seg.ZIndex = 2
			labels[value] = seg
			seg.MouseButton1Click:Connect(function()
				picked = value
				sync(true)
				onChanged(picked)
			end)
		end
		thumb.ZIndex = 1
		sync(false)
	else
		local wrap = frame(parent, "ChipRow", UDim2.new(1, 0, 0, 0), C.white, 1)
		wrap.AutomaticSize = Enum.AutomaticSize.Y
		local lay = Instance.new("UIListLayout")
		lay.FillDirection = Enum.FillDirection.Horizontal
		lay.Wraps = true
		lay.Padding = UDim.new(0, 8)
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Parent = wrap
		local chips: { [string]: TextButton } = {}
		local function sync()
			for value, btn in pairs(chips) do
				local on = value == picked
				btn.BackgroundColor3 = if on then C.white else C.ctrl
				btn.TextColor3 = if on then C.black else C.muted
			end
		end
		for i, value in ipairs(values) do
			local chip = clickable(wrap, "Chip_" .. value, C.ctrl, 0)
			chip.Size = UDim2.fromOffset(0, 32)
			chip.AutomaticSize = Enum.AutomaticSize.X
			chip.LayoutOrder = i
			chip.Text = value
			chip.TextSize = 13
			chip.FontFace = face(Enum.FontWeight.SemiBold)
			corner(chip, UDim.new(1, 0))
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 14)
			pad.PaddingRight = UDim.new(0, 14)
			pad.Parent = chip
			chips[value] = chip
			chip.MouseButton1Click:Connect(function()
				picked = value
				sync()
				onChanged(picked)
			end)
		end
		sync()
	end

	return function()
		return picked
	end
end

-- Target-free stepper row: value to the left, an iOS "-|+" pill on the right.
function AdminSpotlightUI:addStepper(parent: Instance, labelText: string, value: number, minV: number, maxV: number, fmt: ((number) -> string)?): () -> number
	local current = math.clamp(math.floor(value), minV, maxV)
	local g = group(parent, "Stepper_" .. labelText)
	local row = frame(g, "Row", UDim2.new(1, 0, 0, 48), C.white, 1)

	local name = label(row, "Label", labelText, 15, Enum.FontWeight.Medium, C.white)
	name.Position = UDim2.fromOffset(16, 0)
	name.Size = UDim2.new(1, -16 - 240, 1, 0)

	local shown = label(row, "Value", "", 15, Enum.FontWeight.SemiBold, C.muted)
	shown.TextXAlignment = Enum.TextXAlignment.Right
	shown.AnchorPoint = Vector2.new(1, 0.5)
	shown.Position = UDim2.new(1, -(16 + 94 + 12), 0.5, 0)
	shown.Size = UDim2.fromOffset(120, 20)

	local pill = frame(row, "Pill", UDim2.fromOffset(94, 32), C.ctrl, 0)
	pill.AnchorPoint = Vector2.new(1, 0.5)
	pill.Position = UDim2.new(1, -16, 0.5, 0)
	corner(pill, UDim.new(1, 0))
	local minus = clickable(pill, "Minus", C.ctrl, 1)
	minus.Size = UDim2.new(0.5, 0, 1, 0)
	minus.Text = "−"
	minus.FontFace = face(Enum.FontWeight.SemiBold)
	minus.TextSize = 18
	minus.TextColor3 = C.white
	local plus = clickable(pill, "Plus", C.ctrl, 1)
	plus.Position = UDim2.new(0.5, 0, 0, 0)
	plus.Size = UDim2.new(0.5, 0, 1, 0)
	plus.Text = "+"
	plus.FontFace = face(Enum.FontWeight.SemiBold)
	plus.TextSize = 18
	plus.TextColor3 = C.white
	local divider = frame(pill, "Divider", UDim2.fromOffset(1, 18), C.muted, 0.6)
	divider.Position = UDim2.new(0.5, 0, 0.5, -9)

	local function sync()
		shown.Text = if fmt then fmt(current) else tostring(current)
	end
	sync()
	minus.MouseButton1Click:Connect(function()
		if current > minV then
			current = current - 1
			sync()
		end
	end)
	plus.MouseButton1Click:Connect(function()
		if current < maxV then
			current = current + 1
			sync()
		end
	end)
	return function()
		return current
	end
end

-- Value field: label on the left, a TextBox on the right.
function AdminSpotlightUI:addValueField(parent: Instance, labelText: string, text: string): TextBox
	local g = group(parent, "Field_" .. labelText)
	local row = frame(g, "Row", UDim2.new(1, 0, 0, 48), C.white, 1)
	local name = label(row, "Label", labelText, 15, Enum.FontWeight.Medium, C.white)
	name.Position = UDim2.fromOffset(16, 0)
	name.Size = UDim2.new(1, -16 - 170, 1, 0)
	local box = Instance.new("TextBox")
	box.Name = "Value"
	box.BackgroundColor3 = C.ctrl
	box.BackgroundTransparency = 0
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Text = text
	box.TextColor3 = C.white
	box.TextSize = 15
	box.FontFace = face(Enum.FontWeight.Medium)
	box.TextXAlignment = Enum.TextXAlignment.Right
	box.AnchorPoint = Vector2.new(1, 0.5)
	box.Position = UDim2.new(1, -16, 0.5, 0)
	box.Size = UDim2.fromOffset(150, 32)
	corner(box, UDim.new(0, 9))
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = box
	box.Parent = row
	return box
end

-- iOS-style switch: white track with a black knob when on.
function AdminSpotlightUI:addToggle(parent: Instance, labelText: string, on: boolean): () -> boolean
	local state = on
	local g = group(parent, "Toggle_" .. labelText)
	local row = clickable(g, "Row", C.row, 1)
	row.Size = UDim2.new(1, 0, 0, 48)
	local name = label(row, "Label", labelText, 15, Enum.FontWeight.Medium, C.white)
	name.Position = UDim2.fromOffset(16, 0)
	name.Size = UDim2.new(1, -16 - 70, 1, 0)

	local track = frame(row, "Track", UDim2.fromOffset(48, 28), C.ctrl, 0)
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.new(1, -16, 0.5, 0)
	corner(track, UDim.new(1, 0))
	local knob = frame(track, "Knob", UDim2.fromOffset(24, 24), C.white, 0)
	corner(knob, UDim.new(1, 0))

	local function paint(animate: boolean)
		track.BackgroundColor3 = if state then C.white else C.ctrl
		knob.BackgroundColor3 = if state then C.black else C.white
		local pos = if state then UDim2.new(1, -26, 0, 2) else UDim2.fromOffset(2, 2)
		if animate then
			tween(knob, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Position = pos })
		else
			knob.Position = pos
		end
	end
	paint(false)
	row.MouseButton1Click:Connect(function()
		state = not state
		paint(true)
	end)
	return function()
		return state
	end
end

function AdminSpotlightUI:usesActionTemplate(_root: GuiObject): boolean
	return false
end

-- Template-only helpers. The Spotlight never reaches these: usesActionTemplate() is always false,
-- so the controller only calls them inside branches it skips. They are safe no-ops.
function AdminSpotlightUI:findChipRowContaining(_parent: Instance, _chipValue: string): Frame?
	return nil
end

function AdminSpotlightUI:applyPickCardLabels(_host: Instance, _options: { { key: string, label: string, desc: string? } })
end

function AdminSpotlightUI:bindPickCards(
	_host: Instance,
	initialKey: string,
	_onChanged: (string) -> (),
	_allowed: { [string]: boolean }?
): () -> string
	return function()
		return initialKey
	end
end

function AdminSpotlightUI:bindChipRowTemplate(
	_chipRow: Frame,
	initial: string,
	_onChanged: (string) -> (),
	_allowed: { [string]: boolean }?
): () -> string
	return function()
		return initial
	end
end

function AdminSpotlightUI:fillChipRow(_row: Frame, _chips: { string }, _current: string, _onChanged: (string) -> ())
end

function AdminSpotlightUI:destroy()
	for _, conn in ipairs(self._conns) do
		conn:Disconnect()
	end
	table.clear(self._conns)
	self:_disconnectFoot()
	if self._scrollbar then
		self._scrollbar.destroy()
	end
	self._gui:Destroy()
end

return AdminSpotlightUI
