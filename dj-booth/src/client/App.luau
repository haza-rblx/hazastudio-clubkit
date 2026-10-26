--!strict
-- The panel shell: one ScreenGui, the 1250-wide root on 2 px gutters (header, then the Decks rows or
-- a management page), view modes (Deck docked at the bottom · Window centred · Full), the fit to
-- the screen, and how it opens (hotkey, the DJ deck's prompt, the DJ button).
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Icon = require(ReplicatedStorage.HazaDJ.Packages.TopbarPlus)
local Vide = require(ReplicatedStorage.HazaDJ.Packages.Vide)
local LicensePolicy = require(ReplicatedStorage.HazaDJ.Shared.LicensePolicy)
local Actions = require(script.Parent.Actions)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Base = require(script.Parent.UI.Base)
local Controls = require(script.Parent.UI.Controls)
local Access = require(script.Parent.Features.Access)
local Decks = require(script.Parent.Features.Decks)
local Header = require(script.Parent.Features.Header)
local Library = require(script.Parent.Features.Library)
local Lock = require(script.Parent.Features.Lock)
local Settings = require(script.Parent.Features.Settings)
local Debug = require(script.Parent.Debug)

local create, source, effect, untrack = Vide.create, Vide.source, Vide.effect, Vide.untrack
local C = Theme.C

local App = {}

local HOTKEYS = { Enum.KeyCode.J, Enum.KeyCode.K, Enum.KeyCode.B }
local SIZES = { 0.85, 1, 1.15 }
local PANEL_CORNER = 4

function App.new(): ScreenGui
	Store.bind()
	local camera = workspace.CurrentCamera
	local viewport = source(camera.ViewportSize)
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		viewport(camera.ViewportSize)
	end)

	local tab, open = Store.tab, Store.open
	-- the owner of a locked DJ deck sees the lock screen (ADR 0022); it always takes the Window size
	local locked = function()
		return Store.me().role == "Owner" and not LicensePolicy.unlocked(Store.license())
	end
	local chosenView = Store.view
	local view = function(): string
		return if locked() then "window" else chosenView()
	end
	-- the Studio demo fixture opens straight away, like the prototype
	local fixtureOpened = false
	effect(function()
		if not fixtureOpened and Store.ready() and Store.me().canOpen and workspace:GetAttribute("HazaDJ_Fixture") then
			fixtureOpened = true
			open(true)
		end
	end)
	local canOpen = function()
		return Store.me().canOpen
	end
	-- the owner of a locked DJ deck gets the lock screen once on joining (a beat later, so a licence
	-- that arrives just after the role doesn't open it for nothing)
	local lockOpened = false
	effect(function()
		if not lockOpened and Store.ready() and locked() then
			lockOpened = true
			task.delay(1.5, function()
				if untrack(locked) then
					open(true)
				end
			end)
		end
	end)

	-- the saved view mode comes from prefs once
	local viewLoaded = false
	effect(function()
		local prefs = Store.me().prefs
		if not viewLoaded and Store.ready() then
			viewLoaded = true
			chosenView(prefs.view)
		end
	end)
	local function setView(m: string)
		if untrack(chosenView) == m then
			return
		end
		chosenView(m)
		if m == "deck" and untrack(tab) ~= "Decks" then
			tab("Decks")
		end
		Actions.send({ Kind = "PrefsSet", View = m })
	end
	local function setTab(t: string)
		Controls.closeMenu()
		tab(t)
	end

	-- the panel's unscaled height when open: header + the Decks rows (or a page)
	local fullH = function()
		return if tab() ~= "Decks" or view() ~= "deck"
			then Theme.HEADER_H + 2 + Theme.PAGE_H
			else Theme.HEADER_H + 2 + Theme.DECK_H
	end
	local scale = function()
		local vp = viewport()
		local h = fullH()
		local m = view()
		local size = SIZES[Store.me().prefs.panelSize] or 1
		if m == "full" then
			return math.min(vp.X / Theme.PANEL_W, vp.Y / h)
		elseif m == "deck" then
			-- Deck view is always the Small size (owner, 2026-10-23)
			return math.min(SIZES[1], (vp.X - 48) / Theme.PANEL_W, (vp.Y * 0.62) / h)
		end
		return math.min(size, (vp.X - 48) / Theme.PANEL_W, (vp.Y - 72) / h)
	end
	local scaleNow = function()
		return untrack(scale)
	end

	local gui: ScreenGui
	local root: Frame
	-- the panel's scale is driven by the motion below (a tween while changing mode), not bound
	local uiScale = create("UIScale")({ Scale = scaleNow() })

	-- ── the content ──
	local onDecks = function()
		return tab() == "Decks"
	end
	local deckRows = Decks.new({
		visible = function()
			return onDecks()
		end,
		compact = function()
			return view() == "deck"
		end,
	})
	local libraryPage, attention = Library.new({
		Visible = function()
			return tab() == "Tracks"
		end,
	})
	local pages = Base.frame({
		Name = "Pages",
		Size = UDim2.new(1, 0, 0, Theme.PAGE_H),
		LayoutOrder = 0,
		Visible = function()
			return not onDecks()
		end,
		libraryPage,
		Access.new({
			Visible = function()
				return tab() == "Access"
			end,
		}),
		Settings.new({
			Visible = function()
				return tab() == "Settings"
			end,
		}),
	})

	-- popup menus draw on a layer over the content area, inside the header so the list layout
	-- doesn't place it (the header's 16 px padding is undone)
	local menuLayer = Base.frame({
		Name = "Menus",
		Position = UDim2.new(0, -16, 0, Theme.HEADER_H + 2),
		Size = UDim2.fromOffset(Theme.PANEL_W, Theme.PAGE_H),
		ZIndex = 40,
	})
	local header = Header.new({
		tab = tab,
		setTab = setTab,
		badge = attention,
		view = view,
		setView = setView,
		onClose = function()
			open(false)
		end,
	})
	header.ZIndex = 2
	menuLayer.Parent = header
	Controls.setMenuHost(menuLayer, Theme.PAGE_H, scaleNow)
	-- after an unlock, the rows under the header rise into place one after another as the lock's
	-- curtain parts (owner, 2026-10-26). Each row's content is pushed down through its UIPadding and
	-- eased back, under a veil in the panel colour that fades as it lands.
	local RISE_Y = 28
	local RISE = TweenInfo.new(0.8, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	local function riseIn()
		if untrack(Store.me).prefs.reduceMotion == true then
			return
		end
		local rows: { GuiObject } = {}
		for _, r in deckRows do
			if r:IsA("GuiObject") and r.Visible then
				if r.Name == "Deck" then
					for _, c in r:GetChildren() do
						if c:IsA("GuiObject") and c.Visible then
							table.insert(rows, c)
						end
					end
				else
					table.insert(rows, r)
				end
			end
		end
		if pages.Visible then
			table.insert(rows, pages)
		end
		table.sort(rows, function(x, y)
			return x.AbsolutePosition.Y < y.AbsolutePosition.Y
		end)
		local s = scaleNow()
		local origin = menuLayer.AbsolutePosition
		for i, row in rows do
			local pad = row:FindFirstChildOfClass("UIPadding")
			local made = pad == nil
			if not pad then
				pad = Instance.new("UIPadding")
				pad.Parent = row
			end
			local top = (pad :: UIPadding).PaddingTop
			pad.PaddingTop = UDim.new(top.Scale, top.Offset + RISE_Y)
			local veil = create("Frame")({
				Position = UDim2.fromOffset(
					(row.AbsolutePosition.X - origin.X) / s,
					(row.AbsolutePosition.Y - origin.Y) / s
				),
				Size = UDim2.fromOffset(row.AbsoluteSize.X / s, row.AbsoluteSize.Y / s),
				BackgroundColor3 = C.root,
				BorderSizePixel = 0,
				ZIndex = 41,
				Parent = menuLayer,
			})
			task.delay((i - 1) * 0.07, function()
				TweenService:Create(pad :: UIPadding, RISE, { PaddingTop = top }):Play()
				TweenService:Create(veil, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					BackgroundTransparency = 1,
				}):Play()
			end)
			task.delay((i - 1) * 0.07 + RISE.Time, function()
				veil:Destroy()
				if made then
					(pad :: UIPadding):Destroy()
				end
			end)
		end
	end
	-- the lock screen covers the whole panel, from the same layer as the menus (above them).
	-- Below ~0.75 scale (phones) it drops the pass and shows the form at a readable size.
	local lockScreen = Lock.new({
		onReveal = riseIn,
		compact = function()
			return scale() < 0.75
		end,
		boost = function()
			return math.clamp(0.95 / scale(), 1, 2.4)
		end,
		onClose = function()
			open(false)
		end,
	})
	lockScreen.Parent = header

	-- the rows under the header sit on their own backing, so the header alone can show the room
	-- through it (owner, 2026-10-26); the 2 px gutters stay solid
	local body = create("Frame")({
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.root,
		BorderSizePixel = 0,
		LayoutOrder = 1,
		create("UIPadding")({ PaddingTop = UDim.new(0, 2) }),
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 2),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		pages,
		deckRows,
	})

	root = create("Frame")({
		Name = "Panel",
		-- hidden until opened: a visible root whose first sink gets cancelled by a relayout stays on
		-- screen with open() false, and the deck clocks (gated on open) then only move on re-anchors
		Visible = false,
		Size = UDim2.new(0, Theme.PANEL_W, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		-- 4 px corners and a soft drop shadow (owner, 2026-10-26, picked live)
		create("UICorner")({ CornerRadius = UDim.new(0, PANEL_CORNER) }),
		create("UIShadow")({
			Color = Color3.new(0, 0, 0),
			Transparency = 0.45,
			BlurRadius = UDim.new(0, 40),
			Offset = UDim2.fromOffset(0, 12),
			-- the header is see-through: the shadow mustn't darken what shows behind it
			ShowBehindParent = false,
		}),
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		create("UIStroke")({ Color = C.tile, Thickness = 1 }),
		uiScale,
		header,
		body,
	}) :: Frame

	-- a frame's rounded corners don't clip its children, so whatever tile sits in a corner of the
	-- panel gets that corner rounded too. Re-run when the layout changes (mode, page); the corners it
	-- rounded last time go back first.
	local cornered: { [UICorner]: { UDim } } = {}
	local CORNERS = { "TopLeftRadius", "TopRightRadius", "BottomLeftRadius", "BottomRightRadius" }
	local function shown(g: GuiObject): boolean
		local at: Instance? = g
		while at and at ~= root do
			if at:IsA("GuiObject") and not at.Visible then
				return false
			end
			at = at.Parent
		end
		return true
	end
	local function roundCorners()
		for c, was in cornered do
			for i, k in CORNERS do
				(c :: any)[k] = was[i]
			end
		end
		table.clear(cornered)
		local p0, s0 = root.AbsolutePosition, root.AbsoluteSize
		for _, d in root:GetDescendants() do
			if not d:IsA("GuiObject") or d.BackgroundTransparency >= 1 or d:IsDescendantOf(lockScreen) then
				continue
			end
			local p, s = d.AbsolutePosition, d.AbsoluteSize
			local l, r = math.abs(p.X - p0.X) < 2, math.abs(p.X + s.X - p0.X - s0.X) < 2
			local t, b = math.abs(p.Y - p0.Y) < 2, math.abs(p.Y + s.Y - p0.Y - s0.Y) < 2
			if not ((l or r) and (t or b)) or not shown(d) then
				continue
			end
			local c = d:FindFirstChildOfClass("UICorner")
			if not c then
				c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(0, 0)
				c.Parent = d
			end
			local corner = c :: UICorner
			cornered[corner] = {
				corner.TopLeftRadius,
				corner.TopRightRadius,
				corner.BottomLeftRadius,
				corner.BottomRightRadius,
			}
			local r4 = UDim.new(0, PANEL_CORNER)
			if t and l then
				corner.TopLeftRadius = r4
			end
			if t and r then
				corner.TopRightRadius = r4
			end
			if b and l then
				corner.BottomLeftRadius = r4
			end
			if b and r then
				corner.BottomRightRadius = r4
			end
		end
	end
	effect(function()
		view()
		tab()
		open()
		-- after the layout has settled
		task.defer(function()
			task.wait()
			roundCorners()
		end)
	end)

	-- ── motion (owner, 2026-10-23, picked live in the playtest: "rise morph") ──
	-- open: rise from below the screen, Expo Out 1.0 s; close: sink, Cubic In 0.5 s.
	-- changing mode: morph position + scale from where it was, Expo Out 0.7 s.
	-- Deck sits flush on the bottom edge, the others centre.
	local RISE = TweenInfo.new(1.0, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	local SINK = TweenInfo.new(0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.In)
	local MORPH = TweenInfo.new(0.7, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	local function anchorOf(m: string): Vector2
		return if m == "deck" then Vector2.new(0.5, 1) else Vector2.new(0.5, 0.5)
	end
	local function restOf(m: string): UDim2
		return if m == "deck" then UDim2.fromScale(0.5, 1) else UDim2.fromScale(0.5, 0.5)
	end
	local still = function()
		return untrack(Store.me).prefs.reduceMotion == true
	end
	local posTween: Tween?, scaleTween: Tween?
	local function stop()
		if posTween then
			posTween:Cancel()
			posTween = nil
		end
		if scaleTween then
			scaleTween:Cancel()
			scaleTween = nil
		end
	end
	-- how far below its rest the panel must go for its top edge to clear the screen (worked out from
	-- the mode's rest, not read back from the layout, which lags a frame behind)
	local function below(): number
		local area = root.Parent :: any
		if not area then
			return 0
		end
		local gy = area.AbsoluteSize.Y
		local h = fullH() * scale()
		local top = if view() == "deck" then gy - h else (gy - h) / 2
		return gy - top + 4
	end

	local lastView: string?, lastScale: number? = nil, nil
	effect(function()
		local m, s = view(), scale()
		untrack(function()
			-- the server's prefs echo re-runs this with nothing changed: leave a running morph alone
			if m == lastView and s == lastScale then
				return
			end
			local from = lastView
			lastView, lastScale = m, s
			local area = root.Parent :: any
			if from == nil or from == m or not root.Visible or not area or still() then
				stop()
				root.AnchorPoint = anchorOf(m)
				root.Position = restOf(m)
				uiScale.Scale = s
				return
			end
			-- morph: start where the old mode drew the panel, end at the new mode's rest
			local g: Vector2 = area.AbsoluteSize
			local fromScale = uiScale.Scale
			local fromCenter = root.AbsolutePosition - area.AbsolutePosition + root.AbsoluteSize / 2
			local a = anchorOf(m)
			local startH = fullH() * fromScale
			local startAnchor = Vector2.new(fromCenter.X, fromCenter.Y + (a.Y - 0.5) * startH)
			local endAnchor = Vector2.new(g.X / 2, if m == "deck" then g.Y else g.Y / 2)
			local d = startAnchor - endAnchor
			stop()
			root.AnchorPoint = a
			root.Position = restOf(m) + UDim2.fromOffset(d.X, d.Y)
			uiScale.Scale = fromScale
			posTween = TweenService:Create(root, MORPH, { Position = restOf(m) })
			scaleTween = TweenService:Create(uiScale, MORPH, { Scale = s });
			(posTween :: Tween):Play();
			(scaleTween :: Tween):Play()
		end)
	end)

	-- the topbar button (TopbarPlus): shown to anyone with access, selected while the panel is open
	local icon = Icon.new():setName("HazaDJ"):setImage(Theme.MUSIC_ICON):setLabel("DJ"):setCaption("DJ deck")
	icon.toggled:Connect(function(selected: boolean)
		if selected ~= untrack(open) then
			open(selected)
		end
	end)
	effect(function()
		icon:setEnabled(canOpen())
	end)
	effect(function()
		local isOpen = open()
		if isOpen and not icon.isSelected then
			icon:select()
		elseif not isOpen and icon.isSelected then
			icon:deselect()
		end
	end)
	Vide.cleanup(function()
		icon:destroy()
	end)

	gui = create("ScreenGui")({
		Name = "HazaDJ",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
		Enabled = function()
			return Store.ready()
		end,
		root,
	}) :: ScreenGui
	local lastWant: boolean? = nil
	effect(function()
		local want = open() and canOpen()
		-- Store.me() re-fires on every prefs echo: only a real open/close change animates
		if want == lastWant then
			return
		end
		lastWant = want
		untrack(function()
			local rest = restOf(view())
			if want then
				if root.Visible and not posTween then
					return
				end
				stop()
				-- from hidden it rises from below the screen; mid-sink it turns around where it is
				if not root.Visible then
					uiScale.Scale = scale()
					root.AnchorPoint = anchorOf(view())
					root.Position = if still() then rest else rest + UDim2.fromOffset(0, below())
					root.Visible = true
				end
				if still() then
					root.Position = rest
					return
				end
				posTween = TweenService:Create(root, RISE, { Position = rest });
				(posTween :: Tween):Play()
			elseif root.Visible then
				stop()
				if still() then
					root.Visible = false
					return
				end
				local t = TweenService:Create(root, SINK, { Position = rest + UDim2.fromOffset(0, below()) })
				posTween = t
				t.Completed:Connect(function(state)
					if state == Enum.PlaybackState.Completed and not untrack(open) then
						root.Visible = false
						root.Position = rest
						posTween = nil
					end
				end)
				t:Play()
			end
		end)
	end)
	Controls.setModalHost(gui, scaleNow)
	Debug.on("tab", function(t: string)
		setTab(t)
		return "ok"
	end)
	Debug.on("view", function(m: string)
		setView(m)
		return "ok"
	end)
	Debug.on("send", function(cmd: any)
		local r = Actions.run(cmd)
		return if r.Ok then "ok" else tostring(r.Message)
	end)
	Debug.on("live", function(deck: number, param: any, v: number)
		Actions.live(deck, param, v)
		return "ok"
	end)
	Debug.on("open", function(on: boolean)
		open(on)
		return "ok"
	end)
	Debug.mount(gui)

	-- losing access closes the panel
	effect(function()
		if not canOpen() and untrack(open) then
			open(false)
		end
	end)

	-- hotkey (prefs: J / K / B / none); not while typing
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		local key = HOTKEYS[untrack(Store.me).prefs.hotkey]
		if key and input.KeyCode == key and untrack(canOpen) then
			open(not untrack(open))
		end
	end)
	-- the DJ deck's "Open the decks" prompt
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who == Players.LocalPlayer and prompt.Name == "HazaDJ_Open" and untrack(canOpen) then
			open(true)
		end
	end)
	return gui
end

return App
