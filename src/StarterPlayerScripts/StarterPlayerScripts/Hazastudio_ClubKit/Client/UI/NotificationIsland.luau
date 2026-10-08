--!strict
-- Notification island (owner, 2026-10-07; spec §4/§4b of
-- docs/plans/ui-experiments-dance-acm-2026-10-07.md). One morphing shell at the top centre:
-- a dot pops in, widens into a pill (compact layer), grows into a card (card layer), shrinks back
-- to the pill and collapses. Islands play one at a time; a priority island (vote skip) cuts the
-- current one short.
--
-- The shell is a Frame with ClipsDescendants (the radius stays 22 = a full pill at 44 tall, so no
-- corner tween). Each layer is a CanvasGroup used only for its GroupTransparency; its content
-- sits in a plain Frame, because a CanvasGroup with AutomaticSize measures 0.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local KitLook = require(script.Parent.KitLook)

local NotificationIsland = {}

local WIDTH, PILL_HEIGHT, RADIUS = 300, 44, 22
local TOP_OFFSET = 40
local POLL = 0.05

export type Builder = (content: Frame, state: any) -> ((state: any) -> ())?

export type Spec = {
	key: string?,
	priority: boolean?,
	compact: Builder,
	card: Builder?,
	pillHold: number?, -- pill before the card (default 0.9)
	cardHold: number?, -- nil = stays until collapse()
	endHold: number?, -- pill after the card; nil = stays until finish()
	state: any?,
}

export type Handle = {
	update: (self: Handle, state: any) -> (),
	setCompact: (self: Handle, builder: Builder) -> (),
	collapse: (self: Handle) -> (),
	finish: (self: Handle, hold: number?) -> (),
	dismiss: (self: Handle) -> (),
	isActive: (self: Handle) -> boolean,
}

type Layer = { group: CanvasGroup, content: Frame, update: ((any) -> ())? }

type Item = {
	spec: Spec,
	state: any,
	handle: Handle,
	collapseRequested: boolean,
	finishAt: number?,
	dismissed: boolean,
	done: boolean,
	pendingCompact: Builder?,
	compact: Layer?,
	card: Layer?,
}

local queue: { Item } = {}
local current: Item? = nil
local running = false
local shell: Frame? = nil
local pop: UIScale? = nil

local function scaleBoost(): number
	local section = (Config :: any).NotificationIsland
	local value = if type(section) == "table" then tonumber(section.SCALE_BOOST) else nil
	return value or 1.25
end

-- Lives inside the notification centre ScreenGui (its UIScale 0.8 is undone by SCALE_BOOST, so the
-- island renders at its designed size on desktop and follows the phone scale on phones).
local function ensureShell(): Frame?
	if shell and shell.Parent then
		return shell
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local hostGui: Instance? = nil
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") and child:FindFirstChild("GeneralNotificationCenter") then
			hostGui = child
			break
		end
	end
	if not hostGui then
		local made = Instance.new("ScreenGui")
		made.Name = "ClubKitIsland"
		made.ResetOnSpawn = false
		made.DisplayOrder = tonumber(Config.NotificationCenter.V2_DISPLAY_ORDER) or 300
		made.Parent = playerGui
		hostGui = made
	end

	-- The boost undoes the notification centre's own UIScale; the fallback host has none.
	local boost = if (hostGui :: Instance):FindFirstChildWhichIsA("UIScale") then scaleBoost() else 1
	local layer = KitLook.box(nil, "NotificationIsland", UDim2.fromScale(1 / boost, 1 / boost), 0)
	layer.ZIndex = 50
	-- Per-type colours must survive the accent theme: opt out before anything is parented.
	layer:SetAttribute("AccentNoTint", true)
	local boostScale = Instance.new("UIScale")
	boostScale.Scale = boost
	boostScale.Parent = layer

	local made = KitLook.box(layer, "Shell", UDim2.fromOffset(PILL_HEIGHT, PILL_HEIGHT), 0, KitLook.COLOR.panel)
	made.AnchorPoint = Vector2.new(0.5, 0)
	made.Position = UDim2.new(0.5, 0, 0, math.floor(TOP_OFFSET / boost))
	made.ClipsDescendants = true
	made.Visible = false
	made.Active = true
	KitLook.corner(made, UDim.new(0, RADIUS))
	KitLook.shadow(made)
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = made
	layer.Parent = hostGui
	shell = made
	pop = scale
	return made
end

local function tween(target: Instance, duration: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local info = TweenInfo.new(duration, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out)
	local playing = TweenService:Create(target, info, props)
	playing:Play()
	return playing
end

local function makeLayer(parent: Frame, name: string, builder: Builder, state: any, fixedHeight: number?): Layer
	local group = Instance.new("CanvasGroup")
	group.Name = name
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.GroupTransparency = 1
	group.Size = UDim2.fromOffset(WIDTH, fixedHeight or 400)
	group.Parent = parent
	local content = KitLook.box(group, "Content", UDim2.new(1, 0, if fixedHeight then 1 else 0, 0), 0)
	if not fixedHeight then
		content.AutomaticSize = Enum.AutomaticSize.Y
	end
	local ok, update = pcall(builder, content, state)
	return { group = group, content = content, update = if ok then update else nil }
end

-- Content height in design pixels (AbsoluteSize carries every UIScale above it).
local function designHeight(frame: GuiObject): number
	local factor = 1
	local node: Instance? = frame
	while node do
		local scale = node:FindFirstChildWhichIsA("UIScale")
		if scale then
			factor *= scale.Scale
		end
		node = node.Parent
	end
	return math.round(frame.AbsoluteSize.Y / math.max(factor, 0.01))
end

local function swapIn(from: Layer?, to: Layer?)
	if from then
		tween(from.group, 0.15, { GroupTransparency = 1 })
	end
	task.wait(0.12)
	if to then
		tween(to.group, 0.25, { GroupTransparency = 0 })
	end
end

local function waitUntil(item: Item, predicate: () -> boolean)
	while not item.dismissed and not predicate() do
		task.wait(POLL)
	end
end

local function runItem(item: Item)
	local frame = ensureShell()
	local scale = pop
	if not frame or not scale then
		item.done = true
		return
	end
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("CanvasGroup") then
			child:Destroy()
		end
	end
	local spec = item.spec
	item.compact = makeLayer(frame, "Compact", spec.compact, item.state, PILL_HEIGHT)
	local cardHeight = PILL_HEIGHT
	if spec.card then
		-- Measured off-screen in the (visible) island layer: the shell is still hidden here, and
		-- AutomaticSize is not computed under an invisible ancestor (it read 44, playtest 2026-10-07).
		local card = makeLayer(frame.Parent :: Frame, "Card", spec.card, item.state, nil)
		item.card = card
		card.group.Position = UDim2.fromOffset(-4000, 0)
		task.wait()
		task.wait()
		cardHeight = math.max(PILL_HEIGHT, designHeight(card.content))
		card.content.AutomaticSize = Enum.AutomaticSize.None
		card.content.Size = UDim2.fromScale(1, 1)
		card.group.Size = UDim2.fromOffset(WIDTH, cardHeight)
		card.group.Position = UDim2.new()
		card.group.Parent = frame
	end

	-- 1. dot -> 2. pill
	frame.Size = UDim2.fromOffset(PILL_HEIGHT, PILL_HEIGHT)
	frame.Visible = true
	scale.Scale = 0.4
	tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	task.wait(0.25)
	tween(frame, 0.4, { Size = UDim2.fromOffset(WIDTH, PILL_HEIGHT) }, Enum.EasingStyle.Back)
	tween((item.compact :: Layer).group, 0.25, { GroupTransparency = 0 })

	-- 3. card
	if item.card and not item.collapseRequested then
		local started = os.clock()
		waitUntil(item, function()
			return os.clock() - started >= (spec.pillHold or 0.9) or item.collapseRequested
		end)
		if not item.dismissed and not item.collapseRequested then
			tween(frame, 0.5, { Size = UDim2.fromOffset(WIDTH, cardHeight) }, Enum.EasingStyle.Back)
			swapIn(item.compact, item.card)
			local shownAt = os.clock()
			waitUntil(item, function()
				return item.collapseRequested
					or (spec.cardHold ~= nil and os.clock() - shownAt >= spec.cardHold)
					or item.finishAt ~= nil
			end)
			-- 4. back to the pill (with a new compact layer if one was handed over meanwhile)
			if not item.dismissed then
				if item.pendingCompact then
					local fresh = makeLayer(frame, "Compact", item.pendingCompact, item.state, PILL_HEIGHT)
					item.pendingCompact = nil
					local old = item.compact
					item.compact = fresh
					if old then
						old.group:Destroy()
					end
				end
				tween(frame, 0.45, { Size = UDim2.fromOffset(WIDTH, PILL_HEIGHT) })
				swapIn(item.card, item.compact)
			end
		end
	end

	-- Pill phase: compact swaps keep coming in (vote progress -> result) until it ends.
	local pillSince = os.clock()
	while not item.dismissed do
		if item.pendingCompact then
			local fresh = makeLayer(frame, "Compact", item.pendingCompact, item.state, PILL_HEIGHT)
			item.pendingCompact = nil
			local old = item.compact
			item.compact = fresh
			swapIn(old, fresh)
			if old then
				old.group:Destroy()
			end
		end
		if item.finishAt and os.clock() >= item.finishAt then
			break
		end
		if not item.finishAt and spec.endHold ~= nil and os.clock() - pillSince >= spec.endHold then
			break
		end
		task.wait(POLL)
	end

	-- 5. collapse
	if item.compact then
		tween(item.compact.group, 0.15, { GroupTransparency = 1 })
	end
	if item.card then
		tween(item.card.group, 0.15, { GroupTransparency = 1 })
	end
	tween(frame, 0.35, { Size = UDim2.fromOffset(PILL_HEIGHT, PILL_HEIGHT) })
	task.wait(0.3)
	tween(scale, 0.2, { Scale = 0 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	task.wait(0.25)
	frame.Visible = false
	item.done = true
end

local function pump()
	if running then
		return
	end
	running = true
	task.spawn(function()
		while #queue > 0 do
			local item = table.remove(queue, 1) :: Item
			current = item
			local ok, err = pcall(runItem, item)
			if not ok then
				warn("[NotificationIsland] " .. tostring(err))
				if shell then
					shell.Visible = false
				end
			end
			item.done = true
			current = nil
			task.wait(0.15)
		end
		running = false
	end)
end

function NotificationIsland.show(spec: Spec): Handle
	local item: Item
	local handle = {} :: any
	function handle:update(state: any)
		item.state = state
		for _, layer in ipairs({ item.compact, item.card }) do
			if layer and layer.update then
				pcall(layer.update, state)
			end
		end
	end
	function handle:setCompact(builder: Builder)
		item.pendingCompact = builder
	end
	function handle:collapse()
		item.collapseRequested = true
	end
	function handle:finish(hold: number?)
		item.collapseRequested = true
		item.finishAt = os.clock() + (hold or 0)
	end
	function handle:dismiss()
		item.dismissed = true
		local index = table.find(queue, item)
		if index then
			table.remove(queue, index)
		end
	end
	function handle:isActive(): boolean
		return not item.done and not item.dismissed
	end
	item = {
		spec = spec,
		state = spec.state,
		handle = handle :: Handle,
		collapseRequested = false,
		finishAt = nil,
		dismissed = false,
		done = false,
		pendingCompact = nil,
		compact = nil,
		card = nil,
	}
	if spec.priority then
		-- Cut the current island short and jump the line.
		if current and not current.spec.priority then
			current.handle:finish(0)
		end
		table.insert(queue, 1, item)
	else
		table.insert(queue, item)
	end
	pump()
	return item.handle
end

-- Islands waiting or playing (callers use it to shorten or drop low-value islands).
function NotificationIsland.pending(): number
	return #queue + (if current then 1 else 0)
end

NotificationIsland.WIDTH = WIDTH
NotificationIsland.PILL_HEIGHT = PILL_HEIGHT

return NotificationIsland
