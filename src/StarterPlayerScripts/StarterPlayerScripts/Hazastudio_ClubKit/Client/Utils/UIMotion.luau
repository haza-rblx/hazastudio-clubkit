--!strict
-- PATH: StarterPlayerScripts/Client/Utils/UIMotion.luau
-- The one motion vocabulary for every kit panel (ADR 0011). Grew out of the v3 music panel's
-- MusicMotion. Kit designs lay most buttons and rows out with UIListLayout/UIGridLayout, where a
-- UIScale changes the reserved size and makes siblings jump — so scale is only ever applied to a
-- centred element (AnchorPoint 0.5) whose parent has no layout; everything else animates
-- layout-neutral properties (transparency, colour, rotation, padding) — a press or hover on a
-- button with no legal scale target scales its icon instead (1.08 hover, 0.92 press — pinned by a
-- UIMotionIconSlot wherever the icon's own footprint is load-bearing), a button that paints only
-- words lifts that one label by the same amounts (frozen for the gesture where it measures itself),
-- and only a button with neither icon nor label falls back to a padding squash or a brightness dip,
-- never to silence. Only one UIScale per instance is honoured by Roblox, so scale reuses the element's
-- existing UIScale (MobileScaleService's, the cinematic dock's, AnimationHelper's) and tweens
-- relative to that owner's rest value rather than adding a second, silently dead one.
-- Never scale a CanvasGroup (ADR 0005). Honours GuiService.ReducedMotionEnabled
-- (tweens snap, flourishes are skipped) and
-- Config.UIMotion.MOTION_SCALE through MotionPresets.

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local MotionPresets = require(script.Parent.MotionPresets)
local InstanceState = require(game:GetService("ReplicatedStorage").Hazastudio_ClubKit.Shared.Utils.InstanceState)

local SCALE_NAME = "UIMotionScale"
-- Stamped on every UIScale this module creates. The name is UIMotion's own — nothing in a buyer's
-- place writes it, unlike `Name == "UIMotionScale"`, which a buyer is free to reuse — so it is safe
-- as a second proof of ownership beside identity (see `isOwned`).
local OWNED_ATTRIBUTE = "UIMotionOwned"
local SLIDE_NAME = "UIMotionSlide"
local ROTATION_ATTRIBUTE = "UIMotionRotation"
-- Runtime-only evidence, the same kind `UIMotionBound` leaves for the coverage audit: a slide that
-- `slidePaddingOf` refused writes the axis it wanted to travel ("X" / "Y") on the page, and a slide
-- that runs clears it. No log — a refusal repeats on every tab switch, and console noise in a kit
-- shipped to buyers is worse than silence — but a refusal that leaves nothing behind is how the
-- music player's tab slide stayed broken in plain sight (ADR 0011 addendum, 2026-09-16).
local SLIDE_REFUSED_ATTRIBUTE = "UIMotionSlideRefused"
local CENTER = Vector2.new(0.5, 0.5)
-- Fallback press/hover (ADR 0011 decision 2, "everything else gets transparency, colour, rotation
-- or padding"): channels and amounts for a button that has no legal scale target.
local SQUASH_CHANNEL = "Squash"
local TINT_CHANNEL = "Tint"
local SQUASH_RATIO = 0.06
local SQUASH_MIN, SQUASH_MAX = 2, 6
local PRESS_DARKEN = 0.15
local HOVER_LIGHTEN = 0.08
local PRESS_TEXT_FADE = 0.25
local HOVER_TEXT_FADE = -0.1
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
-- Icon tier (between the button scale and the padding/brightness fallback): a button that cannot
-- be scaled itself but paints an image lifts and squashes that image instead of washing white. The
-- text tier below it borrows the same two amounts — a lift is a lift, whether the button's one
-- visible thing is a badge or a word.
local ICON_SLOT_NAME = "UIMotionIconSlot"
local ICON_HOVER = 1.08
local ICON_PRESS = 0.92
local CLIP_EPSILON = 0.5
-- A clipper only counts as tight around an icon below this multiple of the icon's own box.
local TIGHT_CLIP = 1.5
-- Feel tuning, 2026-09-16 (owner: "animasinya dibuat untuk dinikmati"). Durations are pre-scale
-- seconds — every one of them goes through `info`, so `Config.UIMotion.MOTION_SCALE` still stretches
-- or tightens the whole set. Coherence rules this set keeps: every release is longer than its press
-- but shorter than a panel open (MotionPresets.panelOpen, 0.52 s); every hover-out is shorter than
-- its hover-in; and the row cascade finishes inside a second on the longest list the cap allows.
-- PRESS_DOWN_TIME IS DELIBERATELY FAST AND MUST STAY THAT WAY: the gap between a finger landing and
-- the button reacting reads as input lag, not as elegance. Everything after the contact luxuriates.
local PRESS_DOWN_TIME = 0.08
local PRESS_RELEASE_TIME = 0.28
local HOVER_IN_TIME = 0.22
local HOVER_OUT_TIME = 0.18
local FADE_TIME = 0.36
local SLIDE_TIME = 0.38
-- Row cascade. STAGGER_STEP * (STAGGER_MAX_ROWS - 1) + FADE_TIME is the worst case a caller that
-- passes no step can produce: 0.055 * 11 + 0.36 = 0.965 s, and rows past the cap arrive at once, so
-- a 20-row list still settles inside a second.
local STAGGER_STEP = 0.055
local STAGGER_MAX_ROWS = 12

local UIMotion = {}

-- Every piece of per-instance state this module keeps, in one STRONG record per instance — never a
-- weak-keyed table. Roblox drops a weak-keyed entry the moment no *Lua* value references the
-- Instance, even while that Instance is alive and parented in the tree. Measured live 2026-09-17:
-- a UIScale parented under a holder, `weak[s] = true`, ~40 frames of allocation churn, 1 s wait —
-- entriesBefore = 1, entriesAfterChurn = 0, instanceStillInTree = true. Kit binds keep no Lua
-- reference to the UIScales they create, so every entry keyed by one sat on a GC timer: a lost
-- `running` entry orphaned the in-flight hover-in tween so a hover-out could no longer cancel it
-- (0.22 s hover-in outlives 0.18 s hover-out and lands last, at 1.08 — the music library's covers
-- "randomly" staying enlarged); a lost rest capture made the leave re-capture 1.08 as rest; a lost
-- ownership flag sent an owned scale down the borrowed path; a lost tint capture left a brightness
-- stuck; a lost freeze left a label `AutomaticSize = None` forever (ADR 0011 addendum, 2026-09-17).
-- Weak tables keyed by Instances are not a lifetime mechanism in Roblox. Entries are reclaimed
-- explicitly instead, through the kit-wide `InstanceState` store: the first state recorded for an
-- instance connects `Destroying` once, and that clears the whole record. Only `Destroying` reclaims
-- — `AncestryChanged` to a nil parent is not destruction; pooled music rows are detached and
-- re-shown, and their state must survive that. A hidden-but-alive pooled row therefore keeps a few
-- small entries (an empty channel map, an ownership flag, one connection) for as long as it lives —
-- intended.
type MotionState = {
	-- Latest tween per channel: a new animation on the same channel replaces the old one.
	running: { [string]: Tween },
	-- A UIScale this module created (`scaleOf`); rests at 1 by construction.
	owned: boolean?,
	-- Rest value of a borrowed UIScale while a gesture holds it off rest (`restScaleOf`).
	scaleRest: number?,
	-- Designed colour/transparency while a fallback tint holds it off (`tintHold`).
	tintRest: any,
	-- What a frozen AutomaticSize label gets back on thaw (`freezeText`).
	frozen: { size: UDim2, automatic: Enum.AutomaticSize }?,
}

-- `state.of(instance)` makes the record on first use. Release and teardown readers use
-- `state.get(instance)` instead: they may run from a Destroying handler and must not make a record
-- that no Destroying will ever reclaim.
local state = InstanceState.new(function(): MotionState
	return { running = {} }
end)

-- The rest each scale tween was aimed from, so a gesture that lands mid-tween on a borrowed scale
-- with no capture can inherit it instead of reading an in-flight `Scale`. Strong, keyed by the
-- Tween: `play`'s own Completed handler drops the entry when the tween ends or is cancelled, so a
-- superseded tween's entry never lingers past its cancellation.
local scaleTweenRest: { [Tween]: number } = {}

function UIMotion.reduced(): boolean
	local ok, value = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	return ok and value == true
end

local function info(time: number, style: Enum.EasingStyle?, direction: Enum.EasingDirection?, reverses: boolean?): TweenInfo
	return TweenInfo.new(
		MotionPresets.scaledTime(time),
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out,
		0,
		reverses == true
	)
end

local function play(instance: Instance, channel: string, tweenInfo: TweenInfo, goals: { [string]: any }): Tween
	local byChannel = state.of(instance).running
	local previous = byChannel[channel]
	if previous then
		previous:Cancel()
	end
	local tween = TweenService:Create(instance, tweenInfo, goals)
	byChannel[channel] = tween
	-- Runs on Completed and on Cancelled alike: both end this tween's life, so both drop the rest it
	-- was aimed from. The channel is only cleared if this tween is still the one on it.
	tween.Completed:Once(function()
		scaleTweenRest[tween] = nil
		if byChannel[channel] == tween then
			byChannel[channel] = nil
		end
	end)
	tween:Play()
	return tween
end

-- Tween to goals, or set them at once under reduced motion. Channel defaults to the joined
-- property names, so two tweens driving different properties do not cancel each other.
function UIMotion.tween(
	instance: Instance,
	time: number,
	goals: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
)
	local names = {}
	for property in pairs(goals) do
		table.insert(names, property)
	end
	table.sort(names)
	local channel = table.concat(names, ",")
	if time <= 0 or UIMotion.reduced() or not instance.Parent then
		local record = state.get(instance)
		local previous = if record then record.running[channel] else nil
		if record and previous then
			previous:Cancel()
			record.running[channel] = nil
		end
		for property, value in pairs(goals) do
			(instance :: any)[property] = value
		end
		return
	end
	play(instance, channel, info(time, style, direction), goals)
end

-- Cancels every tween this module is running on the instance and leaves the properties where
-- they are. For teardown paths that then set their own resting values.
function UIMotion.cancel(instance: Instance)
	local record = state.get(instance)
	if not record then
		return
	end
	for channel, tween in pairs(record.running) do
		tween:Cancel()
		record.running[channel] = nil
	end
end

local function hasLayout(instance: Instance?): boolean
	return instance ~= nil and instance:FindFirstChildWhichIsA("UIGridStyleLayout") ~= nil
end

-- True when scaling this element cannot move anything else on screen or re-rasterise a group.
function UIMotion.canScale(target: Instance?): boolean
	return target ~= nil
		and target:IsA("GuiObject")
		and not target:IsA("CanvasGroup")
		and target.AnchorPoint == CENTER
		and not hasLayout(target.Parent)
		and target:FindFirstAncestorWhichIsA("CanvasGroup") == nil
end

-- Most kit buttons are laid-out TextButtons holding one label anchored at (0, 0). Moving that
-- label's anchor to the centre, with its position compensated, does not move a pixel and makes
-- it a safe scale target (its parent, the button, has no layout). Done once per instance.
local function recentre(child: GuiObject): GuiObject?
	if child.AnchorPoint == CENTER then
		return child
	end
	if child.AutomaticSize ~= Enum.AutomaticSize.None or child:GetAttribute("UIMotionRecentred") then
		return nil
	end
	local anchor, size, position = child.AnchorPoint, child.Size, child.Position
	local dx, dy = 0.5 - anchor.X, 0.5 - anchor.Y
	child.Position = UDim2.new(
		position.X.Scale + dx * size.X.Scale,
		position.X.Offset + dx * size.X.Offset,
		position.Y.Scale + dy * size.Y.Scale,
		position.Y.Offset + dy * size.Y.Offset
	)
	child.AnchorPoint = CENTER
	child:SetAttribute("UIMotionRecentred", true)
	return child
end

-- `target` made a safe scale target where only its anchor stood in the way (see recentre), else nil.
function UIMotion.centred(target: GuiObject?): GuiObject?
	if target == nil or hasLayout(target.Parent) or target:FindFirstAncestorWhichIsA("CanvasGroup") then
		return nil
	end
	local centred = recentre(target)
	return if centred and UIMotion.canScale(centred) then centred else nil
end

-- The element a press should squash: the button itself when that is safe, else its label/icon.
function UIMotion.scaleTargetOf(button: GuiObject): GuiObject?
	if UIMotion.canScale(button) then
		return button
	end
	if hasLayout(button) or button:FindFirstAncestorWhichIsA("CanvasGroup") then
		return nil
	end
	-- A visible icon first, then visible text: a hidden label must never take the squash. Looks
	-- one level into plain wrapper Frames (no layout of their own), where many designs keep the
	-- label; never into buttons or groups.
	local function pick(parent: Instance): GuiObject?
		for _, className in ipairs({ "ImageLabel", "TextLabel" }) do
			for _, child in ipairs(parent:GetChildren()) do
				if child:IsA(className) and (child :: GuiObject).Visible then
					local target = recentre(child :: GuiObject)
					if target and UIMotion.canScale(target) then
						return target
					end
				end
			end
		end
		return nil
	end
	local direct = pick(button)
	if direct then
		return direct
	end
	for _, child in ipairs(button:GetChildren()) do
		if child.ClassName == "Frame" and (child :: Frame).Visible and not hasLayout(child) then
			local nested = pick(child)
			if nested then
				return nested
			end
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------------------------
-- Icon tier. `scaleTargetOf` refuses a button that carries its own layout, or sits under a
-- CanvasGroup, or whose label cannot be recentred — but most of those buttons still paint an
-- icon, and the owner wants hover and press to read on that icon (1.08 lift, 0.92 squash) rather
-- than on the faint white wash the fallback gives. Two hazards: the icon's own footprint, which
-- `UIMotionIconSlot` pins down, and a CanvasGroup above it, which ADR 0005 refuses outright —
-- scaling a descendant never changes the group's AbsoluteSize, but it re-rasterizes the group on
-- every hover, so an icon under one is left to the padding/brightness fallback.
-- ---------------------------------------------------------------------------------------------

-- Most kit icons are a *chip*: a styled badge (UICorner + UIGradient + a UIAspectRatioConstraint)
-- whose own `Image` is empty, because the art lives in an ImageLabel nested inside it. Every top
-- bar row is built that way, and so are the music playlist covers and the cinematic dock rows — 63
-- of the kit's remaining fallback buttons in all. The chip is what should grow (corner, gradient
-- and art together, so a row whose chip happens to carry a leftover placeholder image behaves
-- exactly like one whose chip is empty), so an image-less chip counts as an icon when it holds
-- image-bearing art **and no words of its own**.
--
-- That no-text clause is the guard against the one real false positive: a button whose direct
-- "image" child is actually its full-bleed background, with the row's whole content inside it.
-- Growing that grows the row's text too, which is not an icon lift. Words are the thing that
-- separates a badge from a surface — a badge never labels itself, a row's chrome always does — and
-- it is a guard on shape rather than on size, which is why the 99x99 playlist cover passes it: the
-- cover fills its card's face but its title and artist sit outside it, so it holds art and no text
-- and zooms on hover, exactly as intended. A chip rejected for holding text is not lost either: the
-- wrapper scan in `iconTargetOf` then reaches the art inside it and lifts that instead.
local function holdsArtOnly(chip: GuiObject): boolean
	local art = false
	for _, descendant in ipairs(chip:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			local text = descendant :: TextLabel
			if text.Visible and text.Text ~= "" then
				return false
			end
		elseif descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
			local image = descendant :: ImageLabel
			if image.Visible and image.Image ~= "" then
				art = true
			end
		end
	end
	return art
end

-- A decorative image: one that paints art itself, or a chip holding art (above). An ImageButton
-- counts only while it is inactive: an active nested GuiButton swallows the input that drives this
-- bind and gets its own bind anyway.
local function isIcon(child: Instance): boolean
	if not (child:IsA("ImageLabel") or child:IsA("ImageButton")) then
		return false
	end
	if child:IsA("GuiButton") and (child :: GuiButton).Active then
		return false
	end
	local element = child :: ImageLabel
	if not element.Visible then
		return false
	end
	return element.Image ~= "" or holdsArtOnly(element)
end

-- An icon already living in a slot a previous bind made: its footprint is pinned, so it is safe
-- to scale whatever the button and its layout do.
local function inSlot(icon: GuiObject): boolean
	local parent = icon.Parent
	return parent ~= nil and parent:GetAttribute(ICON_SLOT_NAME) == true
end

local function iconIn(parent: Instance): GuiObject?
	for _, child in ipairs(parent:GetChildren()) do
		if child.ClassName == "Frame" and child:GetAttribute(ICON_SLOT_NAME) == true then
			for _, slotted in ipairs(child:GetChildren()) do
				if isIcon(slotted) then
					return slotted :: GuiObject
				end
			end
		elseif isIcon(child) then
			return child :: GuiObject
		end
	end
	return nil
end

-- The lift grows the icon 8% about its centre — 4% of its own size per side, which on a 16 px list
-- icon is 0.64 px. A clipping ancestor only matters when it hugs the icon. A scroll window or a
-- panel body is many times the icon's size, and whenever that row is actually on screen its icon
-- sits well inside the rect; measuring it at bind time would be measuring a *scroll offset*, and a
-- bind is permanent — rows cloned while they happened to be outside the window would lose the tier
-- for good while the rows beside them kept it, which is a worse panel than no tier at all. So a
-- clipper refuses only when it is tight around the icon (under 1.5x its box on either axis) AND
-- the grown icon would break out of it. A zero AbsoluteSize still refuses: nothing to measure.
local function iconFits(icon: GuiObject): boolean
	local size = icon.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return false
	end
	local margin = size * ((ICON_HOVER - 1) * 0.5)
	local low, high = icon.AbsolutePosition - margin, icon.AbsolutePosition + size + margin
	local ancestor: Instance? = icon.Parent
	while ancestor ~= nil and ancestor:IsA("GuiObject") do
		local frame = ancestor :: GuiObject
		if frame.ClipsDescendants then
			local clip = frame.AbsoluteSize
			local tight = clip.X < size.X * TIGHT_CLIP or clip.Y < size.Y * TIGHT_CLIP
			local clipLow = frame.AbsolutePosition
			local clipHigh = clipLow + clip
			if
				tight
				and (
					low.X < clipLow.X - CLIP_EPSILON
					or low.Y < clipLow.Y - CLIP_EPSILON
					or high.X > clipHigh.X + CLIP_EPSILON
					or high.Y > clipHigh.Y + CLIP_EPSILON
				)
			then
				return false
			end
		end
		ancestor = frame.Parent
	end
	return true
end

-- Where the slot will land in its parent's layout. A layout sorting by Name would put a Frame
-- called UIMotionIconSlot somewhere else entirely, so those are refused outright. A LayoutOrder
-- sort is fine — except that equal LayoutOrders are broken by child order, and the slot is parented
-- last, which would send the icon to the end of its row. When the icon shares its LayoutOrder with
-- a sibling, the row's current order is first written out as explicit unique LayoutOrders (same
-- order, nothing moves) so the slot can copy one that means exactly the icon's place.
local function orderableFor(parent: GuiObject, icon: GuiObject): boolean
	local layout = parent:FindFirstChildWhichIsA("UIGridStyleLayout")
	if layout == nil then
		return true
	end
	if layout.SortOrder == Enum.SortOrder.Name then
		return false
	end
	local siblings: { GuiObject } = {}
	local tied = false
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("GuiObject") then
			table.insert(siblings, child :: GuiObject)
			if child ~= icon and (child :: GuiObject).LayoutOrder == icon.LayoutOrder then
				tied = true
			end
		end
	end
	if not tied then
		return true
	end
	local position: { [Instance]: number } = {}
	for index, child in ipairs(siblings) do
		position[child] = index
	end
	table.sort(siblings, function(a: GuiObject, b: GuiObject): boolean
		if a.LayoutOrder ~= b.LayoutOrder then
			return a.LayoutOrder < b.LayoutOrder
		end
		return position[a] < position[b]
	end)
	for index, child in ipairs(siblings) do
		child.LayoutOrder = index
	end
	return true
end

-- Every UIScale between the element and the screen. AbsoluteSize is already measured through all of
-- them, but an offset written back into `Size` gets measured through the ancestors' again — so the
-- pin has to divide them back out, or a mobile-scaled panel (MobileScaleService puts a UIScale on
-- panel roots) would shrink the element the first time it was pinned.
local function scaleChainAbove(icon: GuiObject): number
	local factor = 1
	local node: Instance? = icon.Parent
	while node ~= nil and node:IsA("GuiBase2d") do
		local scale = node:FindFirstChildWhichIsA("UIScale")
		if scale then
			factor *= scale.Scale
		end
		node = node.Parent
	end
	return factor
end

-- The footprint an element is currently showing, in the offsets a pin will be sized in. Read from
-- AbsoluteSize, and so only ever safe at a moment the element is known to have laid out: the text
-- tier's `freezeText` is its one caller, and that runs at gesture time, on a label the player has
-- just hovered or pressed. (The icon tier used to call this at bind time and pin the result — see
-- `slotIcon` — which froze a pre-layout measurement forever.) The ancestors' UIScales and the
-- element's own are divided back out, since AbsoluteSize is measured through all of them.
local function restFootprint(icon: GuiObject): Vector2
	local own = icon:FindFirstChildWhichIsA("UIScale")
	local factor = scaleChainAbove(icon) * (if own then own.Scale else 1)
	if factor <= 0 then
		return Vector2.zero
	end
	return icon.AbsoluteSize / factor
end

-- Wraps the icon in a Frame that stands in its place exactly (its own `Size`, position, anchor,
-- layout order, ZIndex, aspect), then centres the icon inside it at full size. The layout above
-- now measures the slot instead of the icon; the icon scales within it and is free to overflow.
-- Created at most once per icon — `iconIn` finds the slot on every later bind. Measured on
-- TopBarMenu.ShopButton, where a bare UIScale grew the row 38 -> 41 px and pushed the sibling
-- Frame +3 px.
--
-- The slot copies the icon's `Size` property rather than a measurement of its AbsoluteSize. A
-- measurement has to be taken at some moment, and the moment a bind happens is not one the icon
-- gets to choose: pooled rows (the music library's playlist cards, the Admin v3 player list) are
-- built and bound before or during their first layout pass, so a measured pin froze a pre-layout
-- size forever — playlist covers and the player picture came out as 8 and 16 px dots. And even a
-- well-timed measurement is wrong for a scale-sized icon (`PlaylistCover` is {0.5, 0}, {1, 0}),
-- because a fixed offset stops tracking the row the moment the panel is resized or mobile-scaled.
-- Copying `Size` needs no timing at all: the slot sits under the same parent and the same layout
-- the icon did, and the icon inside it becomes `fromScale(1, 1)`, so scale icons and offset icons
-- alike reproduce their footprint and go on tracking it.
local function slotIcon(icon: GuiObject): boolean
	local parent = icon.Parent
	if parent == nil or not parent:IsA("GuiObject") then
		return false
	end
	-- The one footprint a pin cannot stand in for: an icon that is still sizing itself from its own
	-- content, and would go on doing it inside the slot. Its `Size` is not what it is showing, so
	-- there is nothing worth copying. A constrained icon is fine — the constraint moves up with the
	-- slot and goes on shaping the same footprint.
	if icon.AutomaticSize ~= Enum.AutomaticSize.None then
		return false
	end
	if not orderableFor(parent :: GuiObject, icon) then
		return false
	end
	local slot = Instance.new("Frame")
	slot.Name = ICON_SLOT_NAME
	slot.BackgroundTransparency = 1
	slot.BorderSizePixel = 0
	slot.Size = icon.Size
	slot.Position = icon.Position
	slot.AnchorPoint = icon.AnchorPoint
	slot.LayoutOrder = icon.LayoutOrder
	slot.ZIndex = icon.ZIndex
	slot.SizeConstraint = icon.SizeConstraint
	slot:SetAttribute(ICON_SLOT_NAME, true)
	slot.Parent = parent
	-- The aspect constraint shaped the footprint, and the slot now carries the `Size` it shaped, so it
	-- moves up and goes on shaping the footprint while the icon is left free to scale inside it.
	-- UICorner, UIGradient and nested decorations stay on the icon and ride along with it.
	for _, child in ipairs(icon:GetChildren()) do
		if child:IsA("UIAspectRatioConstraint") then
			child.Parent = slot
		end
	end
	icon.Size = UDim2.fromScale(1, 1)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.AnchorPoint = CENTER
	-- The slot now carries the constraint; the icon just fills it.
	icon.SizeConstraint = Enum.SizeConstraint.RelativeXY
	icon.Parent = slot
	return true
end

-- The image a press/hover should ride when the button itself cannot be scaled: a visible icon with
-- a real Image, direct child first, then one level into a plain wrapper Frame. Returns it ready to
-- scale — either in place (nothing above it can reflow) or moved into a slot that holds its
-- footprint — or nil, which sends the button on to the padding/brightness fallback.
function UIMotion.iconTargetOf(button: GuiObject): GuiObject?
	local icon = iconIn(button)
	if icon == nil then
		-- Any visible container that is not itself a button: a plain Frame usually, but a
		-- ScrollingFrame or an image-bearing chrome panel holds a row's art just as often, and
		-- refusing those bought nothing. (A CanvasGroup wrapper is scanned too, but the art found
		-- inside it is refused below — ADR 0005.)
		for _, child in ipairs(button:GetChildren()) do
			if child:IsA("GuiObject") and not child:IsA("GuiButton") and (child :: GuiObject).Visible then
				icon = iconIn(child)
				if icon then
					break
				end
			end
		end
	end
	if icon == nil then
		return nil
	end
	-- ADR 0005: any change under a CanvasGroup re-rasterizes the whole group, an icon lift no less
	-- than the label lift `textTargetOf` refuses for the same reason. Checked on the icon (which
	-- covers the button's ancestors and a group wrapper between them) and before the slot, so no
	-- slot is ever built for an icon this will never scale; the button falls to the
	-- padding/brightness fallback, which is legal under a group. It costs coverage — the cinematic
	-- dock's favourite `Badge`, the dance and command-library rows — and that is the right trade.
	if icon:FindFirstAncestorWhichIsA("CanvasGroup") ~= nil then
		return nil
	end
	if inSlot(icon) then
		return icon
	end
	if not iconFits(icon) then
		return nil
	end
	local parent = icon.Parent :: GuiObject
	-- Scale in place only when nothing can reflow: no layout reading the icon's size, and no
	-- AutomaticSize between the icon and the button that would pass the growth upwards. Spilling
	-- over the button's own fixed bounds is fine — the layout above reads the button, which does
	-- not change size.
	if
		not hasLayout(parent)
		and parent.AutomaticSize == Enum.AutomaticSize.None
		and button.AutomaticSize == Enum.AutomaticSize.None
	then
		-- Free: growth then reads from the icon's centre instead of its top-left corner.
		recentre(icon)
		return icon
	end
	if slotIcon(icon) then
		return icon
	end
	return nil
end

-- ---------------------------------------------------------------------------------------------
-- Text tier, between the icon tier and the padding/brightness fallback. A pill that paints nothing
-- but one word — the Admin v3 custom-title `SaveButton` and `RemoveButton` are the reported case —
-- has no icon to lift, and the fallback has nothing to show it either: its padding squash is a
-- measured no-op under the button's own centring layout (see `squashPaddingOf`), and its hover is
-- the 8%-toward-white wash the owner threw out of the icon tier. The word itself is the only thing
-- on that button, so the word is what moves.
-- ---------------------------------------------------------------------------------------------

-- The label a press/hover should ride when neither the button nor an icon can take it. The shape
-- this is written for is exactly the one `scaleTargetOf` refuses at its `hasLayout(button)` guard:
-- the button lays its own content out. That layout is also what makes the lift safe here — it
-- re-centres the label at every size, so growing it moves nothing but itself — but only while the
-- button's footprint is fixed and nothing above it rasterizes, hence the refusals below. Returns
-- nil for anything else, which sends the button on to the padding/brightness fallback.
function UIMotion.textTargetOf(button: GuiObject): TextLabel?
	-- An AutomaticSize button measures its own content, so a lifted label would grow the button and
	-- shove every sibling in its row — the jump `canScale` exists to prevent.
	if button.AutomaticSize ~= Enum.AutomaticSize.None then
		return nil
	end
	-- ADR 0005: a CanvasGroup resizes with its content, and a bigger label inside one re-rasterizes
	-- the whole group.
	if button:FindFirstAncestorWhichIsA("CanvasGroup") ~= nil then
		return nil
	end
	-- A button that paints art of its own is the icon tier's business, and it already had its turn.
	if (button:IsA("ImageButton") or button:IsA("ImageLabel")) and (button :: any).Image ~= "" then
		return nil
	end
	-- Centred on both axes, or the lift reads as a drift: an aligned label grows away from its
	-- alignment edge, which under a layout that also reserves its size is a shove, not a press.
	local layout = button:FindFirstChildWhichIsA("UIGridStyleLayout")
	if
		layout == nil
		or layout.HorizontalAlignment ~= Enum.HorizontalAlignment.Center
		or layout.VerticalAlignment ~= Enum.VerticalAlignment.Center
	then
		return nil
	end
	-- Exactly one visible GuiObject, and it is a label. Two means the layout is arranging a row, and
	-- lifting one half of a row is a wobble rather than a press. Looks one level into a plain
	-- wrapper Frame with no layout of its own, the same reach `scaleTargetOf`'s `pick` has.
	local function sole(parent: Instance): GuiObject?
		local found: GuiObject? = nil
		for _, child in ipairs(parent:GetChildren()) do
			if child:IsA("GuiObject") and (child :: GuiObject).Visible then
				if found ~= nil then
					return nil
				end
				found = child :: GuiObject
			end
		end
		return found
	end
	local only = sole(button)
	if only ~= nil and only.ClassName == "Frame" and not hasLayout(only) then
		only = sole(only)
	end
	if only == nil or not only:IsA("TextLabel") then
		return nil
	end
	local label = only :: TextLabel
	-- The lift has to stay inside the pill. A label that already fills the button's padded inner
	-- rect would push its words over the corner and the stroke at 1.08, which reads as a bug and not
	-- as a press — so it keeps the fallback instead. Same spirit as `iconFits`, measured against the
	-- one rect that matters here: the box this layout is centring the label in. A zero AbsoluteSize
	-- refuses too, the GUI has not laid out yet.
	local size = label.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return nil
	end
	local inner = button.AbsoluteSize
	local padding = button:FindFirstChildWhichIsA("UIPadding")
	if padding then
		local left, right = padding.PaddingLeft, padding.PaddingRight
		local top, bottom = padding.PaddingTop, padding.PaddingBottom
		inner -= Vector2.new(
			left.Offset + right.Offset + (left.Scale + right.Scale) * inner.X,
			top.Offset + bottom.Offset + (top.Scale + bottom.Scale) * inner.Y
		)
	end
	if size.X * ICON_HOVER > inner.X + CLIP_EPSILON or size.Y * ICON_HOVER > inner.Y + CLIP_EPSILON then
		return nil
	end
	return label
end

-- Roblox honours one UIScale per instance, so a second one is a silent no-op: UIMotion borrows
-- whatever UIScale the element already has (MobileScaleService puts one on panel roots and on the
-- dance trigger and re-applies it on every viewport change; the cinematic dock magnifier and
-- AnimationHelper own theirs) and only an element with none gets a UIMotionScale of its own.
-- The UIScales this module created — by identity (`owned` on the record) and by the
-- `UIMotionOwned` attribute stamped at creation; never by `Name == SCALE_NAME`, which a buyer's
-- place is free to use for a UIScale of its own. Nobody else writes these, so they rest at 1. The
-- attribute is belt and braces: it is UIMotion's own name, so it cannot collide with anything in a
-- buyer's place, and a clone of an owned scale (a row template cloned mid-gesture) inherits it and
-- so rests at 1 too, which is the right answer for a clone.
local function isOwned(scale: UIScale): boolean
	local record = state.get(scale)
	return (record ~= nil and record.owned == true) or scale:GetAttribute(OWNED_ATTRIBUTE) == true
end

local function scaleOf(target: GuiObject): UIScale
	local existing = target:FindFirstChildWhichIsA("UIScale")
	if existing then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = SCALE_NAME
	scale:SetAttribute(OWNED_ATTRIBUTE, true)
	state.of(scale).owned = true
	scale.Parent = target
	return scale
end

-- Rest value of a borrowed UIScale, i.e. what its owner left it at. Captured (`record.scaleRest`)
-- the first time UIMotion pushes it off rest and dropped again once it has settled back (the same
-- capture-on-hold, clear-on-release rule as the tint capture below), so the owner's value is only
-- ever read between interactions and a re-apply mid-press cannot leave a stale rest behind.
-- A UIScale UIMotion made itself rests at 1 by construction and is never read: the music library's
-- playlist covers stayed enlarged after hover because a capture went missing mid-hover and the
-- leave re-captured the lifted 1.08 as "rest" (ADR 0011 addendum, 2026-09-17 — the capture went
-- missing because it lived in a weak-keyed table, see `state`). For an owned scale no interleaving
-- can do that any more, whatever cleared the capture.
--
-- The rest a borrowed scale is known to have without reading it: its capture, else the rest of the
-- UIMotion tween now driving it (nil for a caller's own `UIMotion.tween` on Scale, which has none).
local function knownRestOf(scale: UIScale): number?
	if isOwned(scale) then
		return 1
	end
	local record = state.get(scale)
	if record == nil then
		return nil
	end
	if record.scaleRest ~= nil then
		return record.scaleRest
	end
	local inFlight = record.running["Scale"]
	return if inFlight then scaleTweenRest[inFlight] else nil
end

local function restScaleOf(scale: UIScale): number
	local known = knownRestOf(scale)
	if known ~= nil then
		return known
	end
	local record = state.of(scale)
	if record.running["Scale"] then
		-- A caller's own Scale tween is mid-flight (a dock or notification entrance): `Scale` is not
		-- the owner's value, so it is used for this one gesture and never stored. The gesture's own
		-- tween records it in `scaleTweenRest`, so its release lands where it started, and the next
		-- gesture that begins at rest captures the real value.
		return scale.Scale
	end
	local rest = scale.Scale
	record.scaleRest = rest
	return rest
end

-- A label that measures itself cannot be scaled and handed back clean: a UIScale *on* an
-- AutomaticSize element corrupts the measurement it feeds itself. Measured on the Admin v3
-- SaveButton's label — rest width 112, 1.08 read back 120.96, 1.20 read back 138.89, and destroying
-- the UIScale left it at 116.67 rather than 112, with its height stuck at 15.83 instead of coming
-- back to 18. A UIScale *above* the label is clean by contrast (scaling the button took the same
-- label 116.67 -> 125 and back to exactly 112), so the answer is to stop the label measuring for as
-- long as a gesture holds it: pin the footprint it is already showing, then hand `Size` and
-- `AutomaticSize` back untouched. Held per instance (`record.frozen`), never per bind — a press
-- landing mid-hover finds it already frozen and the release thaws it once, when the scale has
-- settled back on rest.
--
-- Only a label: an icon that sizes itself is refused a slot for the same reason (`slotIcon`) and
-- the ones scaled in place are the kit's fixed-size art, so there is nothing here to freeze.
local function freezeText(target: GuiObject)
	local record = state.get(target)
	if
		not target:IsA("TextLabel")
		or target.AutomaticSize == Enum.AutomaticSize.None
		or (record ~= nil and record.frozen ~= nil)
	then
		return
	end
	local footprint = restFootprint(target)
	if footprint.X < 1 or footprint.Y < 1 then
		return
	end
	state.of(target).frozen = { size = target.Size, automatic = target.AutomaticSize }
	target.Size = UDim2.fromOffset(math.round(footprint.X), math.round(footprint.Y))
	target.AutomaticSize = Enum.AutomaticSize.None
end

-- Never leave a label frozen: these panels rewrite their labels' text per tab, and a stuck offset
-- size would clip the longer wording. Safe to call on anything — nothing frozen, nothing to do.
local function thawText(target: GuiObject)
	local record = state.get(target)
	if record == nil then
		return
	end
	local held = record.frozen
	if held == nil then
		return
	end
	record.frozen = nil
	target.Size = held.size
	target.AutomaticSize = held.automatic
end

-- Tween a UIScale to `factor` x its rest (press 0.86, hover 1.05, pop peak, 1 = back to rest).
-- `settles` marks a tween that ends on rest and so frees the capture; a tween cancelled by the
-- next interaction does not, because that interaction is still holding the same rest.
local function scaleTo(scale: UIScale, factor: number, tweenInfo: TweenInfo, settles: boolean)
	local rest = restScaleOf(scale)
	local tween = play(scale, "Scale", tweenInfo, { Scale = rest * factor })
	scaleTweenRest[tween] = rest
	if settles then
		tween.Completed:Once(function(playbackState)
			if playbackState ~= Enum.PlaybackState.Completed then
				return
			end
			-- Only the scale's current tween may release the capture (and the frozen label). A
			-- "Completed" that has since been superseded — its handler can run after the next
			-- gesture's tween started, e.g. under deferred signals — must not clear a rest that
			-- gesture is still relying on. `play` connected its own Completed first, so by now it has
			-- already set the channel to nil if this tween was still current; a different non-nil
			-- tween therefore means superseded. `== tween` is accepted too, should that order ever
			-- not hold. The record is read, not made: the scale may be mid-destruction here.
			local record = state.get(scale)
			local current = if record then record.running["Scale"] else nil
			if current ~= nil and current ~= tween then
				return
			end
			if record then
				record.scaleRest = nil
			end
			-- Back on rest is also the only moment a frozen label may measure itself again: a
			-- release cancelled by the next gesture leaves it pinned, which is what that gesture
			-- wants anyway.
			local owner = scale.Parent
			if owner and owner:IsA("GuiObject") then
				thawText(owner :: GuiObject)
			end
		end)
	end
end

-- Puts a UIScale back at rest at once, without creating one. Every release with no tween to land
-- on rest ends here — teardown, reduced motion, and a target detached mid-gesture — because a
-- pooled row can be re-shown before any tween could finish. A scale UIMotion made goes back to 1
-- unconditionally (a missing capture is exactly how one got stuck at 1.08). A borrowed one with no
-- known rest is already at rest (and belongs to someone else) — leave it alone. A frozen label is
-- thawed either way: these are the paths where no tween will ever land to do it.
local function settleScale(target: GuiObject)
	local scale = target:FindFirstChildWhichIsA("UIScale")
	if scale == nil then
		thawText(target)
		return
	end
	local rest = knownRestOf(scale)
	if rest == nil then
		thawText(target)
		return
	end
	local record = state.get(scale)
	if record then
		record.scaleRest = nil
	end
	UIMotion.cancel(scale)
	scale.Scale = rest
	thawText(target)
end

-- Quick bounce: rest -> rest x peak -> rest.
function UIMotion.pop(target: GuiObject?, peak: number?, time: number?)
	if target == nil or UIMotion.reduced() or not UIMotion.canScale(target) then
		return
	end
	local scale = scaleOf(target)
	scale.Scale = restScaleOf(scale)
	-- Reverses, so it ends on rest.
	scaleTo(scale, peak or 1.25, info(time or 0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, true), true)
end

-- Grow in from a smaller size with a little overshoot.
function UIMotion.popIn(target: GuiObject?, from: number?)
	if target == nil or UIMotion.reduced() or not UIMotion.canScale(target) then
		return
	end
	local scale = scaleOf(target)
	scale.Scale = restScaleOf(scale) * (from or 0.6)
	scaleTo(scale, 1, info(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), true)
end

local function restRotationOf(target: GuiObject): number
	local base = tonumber(target:GetAttribute(ROTATION_ATTRIBUTE))
	if base == nil then
		base = target.Rotation
		target:SetAttribute(ROTATION_ATTRIBUTE, base)
	end
	return base :: number
end

-- Rotation never affects layout, so wiggle and spin are safe on any element.
function UIMotion.wiggle(target: GuiObject?, degrees: number?)
	if target == nil or UIMotion.reduced() then
		return
	end
	local amount = degrees or 8
	local restRotation = restRotationOf(target)
	task.spawn(function()
		for _, offset in ipairs({ amount, -amount, amount * 0.5, -amount * 0.5, 0 }) do
			if not target.Parent then
				return
			end
			local tween = play(target, "Rotation", info(0.05, Enum.EasingStyle.Sine), { Rotation = restRotation + offset })
			tween.Completed:Wait()
			if tween.PlaybackState ~= Enum.PlaybackState.Completed then
				return
			end
		end
	end)
end

function UIMotion.spin(target: GuiObject?, turns: number?)
	if target == nil or UIMotion.reduced() then
		return
	end
	local restRotation = restRotationOf(target)
	target.Rotation = restRotation
	local tween = play(
		target,
		"Rotation",
		info(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Rotation = restRotation + 360 * (turns or 1) }
	)
	tween.Completed:Once(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed and target.Parent then
			target.Rotation = restRotation
		end
	end)
end

local function fadeProperty(element: GuiObject): string?
	if element:IsA("ImageLabel") or element:IsA("ImageButton") then
		return "ImageTransparency"
	elseif element:IsA("TextLabel") or element:IsA("TextButton") or element:IsA("TextBox") then
		return "TextTransparency"
	end
	return nil
end

-- Fade text/images in from invisible to their designed transparency. `bases` holds each
-- element's designed value (captured once by the caller, before any fade touched it).
function UIMotion.fadeIn(elements: { GuiObject }, bases: { [GuiObject]: number }, delay: number?)
	if UIMotion.reduced() then
		return
	end
	local function run()
		for _, element in ipairs(elements) do
			local base = bases[element]
			local property = fadeProperty(element)
			if base == nil or property == nil then
				continue
			end
			if not element.Parent then
				-- Detached before the fade could start — a pooled row released mid-cascade, after
				-- the delayed branch below had already hidden it. No tween will land on it, so the
				-- design is written back at once; skipping it left the row blank when re-shown.
				(element :: any)[property] = base
				continue
			end
			(element :: any)[property] = 1
			play(element, property, info(FADE_TIME, Enum.EasingStyle.Sine), { [property] = base })
		end
	end
	if delay and delay > 0 then
		for _, element in ipairs(elements) do
			local property = fadeProperty(element)
			if bases[element] ~= nil and property then
				(element :: any)[property] = 1
			end
		end
		task.delay(MotionPresets.scaledTime(delay), run)
	else
		run()
	end
end

-- Records the designed transparency of text/image elements for fadeIn.
function UIMotion.captureBases(elements: { GuiObject }, into: { [GuiObject]: number }?): { [GuiObject]: number }
	local bases = into or {}
	for _, element in ipairs(elements) do
		local property = fadeProperty(element)
		if property then
			bases[element] = (element :: any)[property]
		end
	end
	return bases
end

-- Rows of a list cascade in: each row's text/images fade a step later than the one before.
-- `step` is the delay between rows; rows past `maxRows` appear at once (long lists must not
-- take seconds to settle).
function UIMotion.stagger(rows: { GuiObject }, bases: { [GuiObject]: number }, step: number?, maxRows: number?)
	if UIMotion.reduced() then
		return
	end
	local stepTime = step or STAGGER_STEP
	local cap = maxRows or STAGGER_MAX_ROWS
	for index, row in ipairs(rows) do
		local elements: { GuiObject } = {}
		for _, descendant in ipairs(row:GetDescendants()) do
			if descendant:IsA("GuiObject") and bases[descendant] ~= nil then
				table.insert(elements, descendant)
			end
		end
		if bases[row] ~= nil then
			table.insert(elements, row)
		end
		UIMotion.fadeIn(elements, bases, if index <= cap then stepTime * (index - 1) else 0)
	end
end

-- Does the page measure itself along the axis a caller is about to move its padding on? `travel`
-- is that axis: X for `slideIn`'s left/right pair, Y for `slideInVertical`'s top/bottom pair, and
-- XY for the squash, which insets all four sides at once and so has both axes in play.
local function growsAlong(page: GuiObject, travel: Enum.AutomaticSize): boolean
	local grows = page.AutomaticSize
	if grows == Enum.AutomaticSize.None then
		return false
	end
	if grows == Enum.AutomaticSize.XY or travel == Enum.AutomaticSize.XY then
		return true
	end
	return grows == travel
end

-- Roblox honours one UIPadding per instance, so a page that already has one (buyer designs
-- often do) is slid through that padding, offset from its designed values; only a page with
-- none gets a UIMotionSlide padding. Designed values are recorded once as attributes.
--
-- The refusal is per axis, not blanket. A page that measures itself along the axis the padding is
-- travelling on would resize as the content moves and take the laid-out panel with it — that is the
-- case worth refusing. Auto-sizing on the *other* axis is not: the kit's tab pages are
-- `AutomaticSize.Y` and slide horizontally, and a blanket refusal silently swallowed every one of
-- their slides (ADR 0011 addendum, 2026-09-16 — the music player's tab switch had no animation at
-- all, and `slideIn` returned without a sound).
--
-- The hazard a reader will reach for here is text re-wrap — narrow the content box and a
-- `TextWrapped` label gains a line, which on an `AutomaticSize.Y` page changes its height mid-slide.
-- It cannot happen to the slide as written, and the reason is structural rather than lucky: the two
-- offsets are **equal and opposite**, so `PaddingLeft + PaddingRight` is invariant and the content
-- box's *width* never changes — only its origin moves. Nothing can re-wrap, so a horizontal slide
-- cannot resize an `AutomaticSize.Y` page, and a vertical one cannot resize an `AutomaticSize.X`
-- page. (Measured on `06-MusicPlayerGUI` with `PaddingLeft +28 / PaddingRight -28` applied by hand:
-- `LibraryTab` and `NowPlayingTab` held 950 x 554.80 at rest, shifted and back — dY 0.00.)
--
-- The caveat that does survive, because it is the thing a later edit might actually do: make the
-- shift **asymmetric** — one side moved further than the other, or one side left alone — and the
-- content box's width really does change, which re-wraps text and puts the height wobble back on an
-- `AutomaticSize.Y` page. If a slide ever needs to move the two sides by different amounts, this
-- per-axis refusal stops being sufficient and has to go back to refusing the growing axis outright.
local function slidePaddingOf(page: GuiObject, travel: Enum.AutomaticSize): UIPadding?
	if growsAlong(page, travel) then
		return nil
	end
	local existing = page:FindFirstChildWhichIsA("UIPadding")
	if existing then
		return existing
	end
	local padding = Instance.new("UIPadding")
	padding.Name = SLIDE_NAME
	padding.Parent = page
	return padding
end

local function designedPadding(padding: UIPadding, side: string): UDim
	local attribute = "UIMotionBase" .. side
	local base = padding:GetAttribute(attribute)
	if typeof(base) ~= "UDim" then
		base = (padding :: any)["Padding" .. side]
		padding:SetAttribute(attribute, base)
	end
	return base :: UDim
end

local function shifted(base: UDim, by: number): UDim
	return UDim.new(base.Scale, base.Offset + by)
end

-- Slides a page's content in from the side. Equal and opposite padding offsets move the
-- content without changing its width or the page's size, so the laid-out panel stays put
-- (measured: content moved, page and panel heights unchanged). direction: 1 = from the right.
-- The equal-and-opposite pair is not a style choice: `slidePaddingOf`'s per-axis refusal is only
-- safe because it holds the content width invariant. Keep the two offsets mirrored.
function UIMotion.slideIn(page: GuiObject, direction: number, distance: number?)
	if UIMotion.reduced() then
		return
	end
	local padding = slidePaddingOf(page, Enum.AutomaticSize.X)
	if not padding then
		page:SetAttribute(SLIDE_REFUSED_ATTRIBUTE, "X")
		return
	end
	page:SetAttribute(SLIDE_REFUSED_ATTRIBUTE, nil)
	local left, right = designedPadding(padding, "Left"), designedPadding(padding, "Right")
	local offset = (distance or 28) * (if direction < 0 then -1 else 1)
	padding.PaddingLeft = shifted(left, offset)
	padding.PaddingRight = shifted(right, -offset)
	play(padding, "Slide", info(SLIDE_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		PaddingLeft = left,
		PaddingRight = right,
	})
end

-- Same trick vertically: content drops in from above (direction -1) or rises from below (1).
function UIMotion.slideInVertical(page: GuiObject, direction: number, distance: number?)
	if UIMotion.reduced() then
		return
	end
	local padding = slidePaddingOf(page, Enum.AutomaticSize.Y)
	if not padding then
		page:SetAttribute(SLIDE_REFUSED_ATTRIBUTE, "Y")
		return
	end
	page:SetAttribute(SLIDE_REFUSED_ATTRIBUTE, nil)
	local top, bottom = designedPadding(padding, "Top"), designedPadding(padding, "Bottom")
	local offset = (distance or 20) * (if direction < 0 then -1 else 1)
	padding.PaddingTop = shifted(top, offset)
	padding.PaddingBottom = shifted(bottom, -offset)
	play(padding, "SlideV", info(SLIDE_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		PaddingTop = top,
		PaddingBottom = bottom,
	})
end

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- ---------------------------------------------------------------------------------------------
-- Fallback micro-interactions. A coverage scan found 120 of 483 kit GuiButtons where
-- `scaleTargetOf` returns nil — the button lays its own children out, has no children at all, or
-- sits under a CanvasGroup — so press and hover were silent and the button felt dead. ADR 0011
-- decision 2 already promises those "transparency, colour, rotation or padding": press squashes
-- the button's own UIPadding (internal, so its AbsoluteSize and its parent's layout never move,
-- and it is legal under a CanvasGroup), and where padding would show nothing, brightness moves.
-- ---------------------------------------------------------------------------------------------

local function cancelChannel(instance: Instance, channel: string)
	local record = state.get(instance)
	if not record then
		return
	end
	local previous = record.running[channel]
	if previous then
		previous:Cancel()
		record.running[channel] = nil
	end
end

-- A bind connects a global signal (UserInputService.InputEnded, so a press that ends off the
-- button still releases it), and list rows are cloned and destroyed on every rebuild while
-- callers hold the returned connections until the panel dies — so a bind has to let go of
-- itself. The rule: per-instance state and binds live exactly as long as the instance; only
-- `Destroying` ends them (every connection disconnected, the press state dropped). Leaving the
-- tree is not the end — the dance panel and the command library pool their rows with
-- `Parent = nil`, re-acquire the same instance and bind it exactly once, so a bind torn down on
-- detach left every recycled row dead for the session while `UIMotionBound` still read bound. A
-- detach therefore only settles the target to rest at once (no tween: the row may be re-shown
-- before one could land, and it must come back at its designed scale, padding and colour) and
-- keeps its connections for the next showing; the bind callbacks already sit out a detached
-- target. A row built detached and parented in afterwards is not settled either — nothing has
-- happened to it yet. The same array is returned, for callers that track it; disconnecting an
-- already-disconnected connection is a no-op.
local function selfRelease(
	button: GuiObject,
	connections: { RBXScriptConnection },
	drop: () -> ()
): { RBXScriptConnection }
	local attached = button:IsDescendantOf(game)
	local function release()
		drop()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
	end
	table.insert(connections, button.Destroying:Once(release))
	table.insert(
		connections,
		button.AncestryChanged:Connect(function()
			if button:IsDescendantOf(game) then
				attached = true
			elseif attached then
				attached = false
				drop()
			end
		end)
	)
	return connections
end

-- A few px, proportional to the button: never so small it reads as nothing, never so large it
-- swallows a dense row. Measured at press time — AbsoluteSize is only real once the GUI laid out.
local function squashAmount(button: GuiObject): number
	local shorter = math.min(button.AbsoluteSize.X, button.AbsoluteSize.Y)
	if shorter <= 0 then
		return 0
	end
	return math.clamp(shorter * SQUASH_RATIO, SQUASH_MIN, SQUASH_MAX)
end

-- The one shape where insetting the padding is a guaranteed no-op, not merely a small move: the
-- button lays its own content out and centres it on *both* axes, so the layout re-centres that
-- content inside the smaller inner rect and a child that does not fill the rect lands on exactly
-- the same pixel. Measured on the Admin v3 custom-title `SaveButton` (176 x 38.72, a centring
-- `UIListLayout`, one auto-sized label): the whole press moved nothing, on every button of that
-- shape. A child sized in scale on an axis is the exception that keeps the squash — it is measured
-- from the inner rect, so it really does shrink with the padding.
local function centredContentIgnoresPadding(button: GuiObject): boolean
	local layout = button:FindFirstChildWhichIsA("UIGridStyleLayout")
	if
		layout == nil
		or layout.HorizontalAlignment ~= Enum.HorizontalAlignment.Center
		or layout.VerticalAlignment ~= Enum.VerticalAlignment.Center
	then
		return false
	end
	for _, child in ipairs(button:GetChildren()) do
		if child:IsA("GuiObject") and (child :: GuiObject).Visible then
			local size = (child :: GuiObject).Size
			if size.X.Scale ~= 0 or size.Y.Scale ~= 0 then
				return false
			end
		end
	end
	return true
end

-- The button's own UIPadding, through the one-per-instance mechanism `slideIn` uses (designed
-- values recorded once as attributes, offsets taken from those, never a second UIPadding). nil
-- when a squash would show or prove nothing: a button with no children has nothing to pull in;
-- an AutomaticSize button measures its own padding, so insetting it would resize the button and
-- shove its siblings — the very jump `canScale` exists to prevent — and `slidePaddingOf` refuses
-- those for it; a centring layout moves its content by zero (above); and a slide in flight owns
-- these same four properties. Refused before `slidePaddingOf` runs, so a button that can never use
-- a squash is not given a `UIMotionSlide` padding to hold it.
--
-- The axis passed is `XY`, and it must stay `XY`: a squash insets left, right, top *and* bottom in
-- the same tween, so unlike a slide it has both axes in play and **any** AutomaticSize resizes the
-- button. The slides' per-axis refusal (above) does not apply here and loosening this to match them
-- would bring back the sibling jump.
local function squashPaddingOf(button: GuiObject): UIPadding?
	if button:FindFirstChildWhichIsA("GuiObject") == nil then
		return nil
	end
	if centredContentIgnoresPadding(button) then
		return nil
	end
	local padding = slidePaddingOf(button, Enum.AutomaticSize.XY)
	if padding == nil then
		return nil
	end
	local record = state.get(padding)
	if record and (record.running["Slide"] ~= nil or record.running["SlideV"] ~= nil) then
		return nil
	end
	return padding
end

-- `by` px inside the designed padding on all four sides (0 = back to the design). A nil tweenInfo
-- sets it at once, for reduced motion and for teardown.
local function squashTo(padding: UIPadding, by: number, tweenInfo: TweenInfo?)
	local goals = {
		PaddingLeft = shifted(designedPadding(padding, "Left"), by),
		PaddingRight = shifted(designedPadding(padding, "Right"), by),
		PaddingTop = shifted(designedPadding(padding, "Top"), by),
		PaddingBottom = shifted(designedPadding(padding, "Bottom"), by),
	}
	if tweenInfo == nil then
		cancelChannel(padding, SQUASH_CHANNEL)
		for property, value in pairs(goals) do
			(padding :: any)[property] = value
		end
		return
	end
	play(padding, SQUASH_CHANNEL, tweenInfo, goals)
end

-- The property a brightness change would actually be visible on, in the order a button paints:
-- its fill, then its image, then its text.
local function tintable(element: GuiObject): string?
	if element.BackgroundTransparency < 1 then
		return "BackgroundColor3"
	end
	if (element:IsA("ImageButton") or element:IsA("ImageLabel")) and (element :: any).Image ~= "" then
		return "ImageColor3"
	end
	if (element:IsA("TextButton") or element:IsA("TextLabel")) and (element :: any).Text ~= "" then
		return "TextTransparency"
	end
	return nil
end

-- The button itself when it paints something, else its first visible label/icon: a fully
-- transparent container button keeps its visuals in its children.
local function tintTargetOf(button: GuiObject): (GuiObject?, string?)
	local property = tintable(button)
	if property then
		return button, property
	end
	for _, child in ipairs(button:GetChildren()) do
		if child:IsA("GuiObject") and (child :: GuiObject).Visible then
			property = tintable(child :: GuiObject)
			if property then
				return child :: GuiObject, property
			end
		end
	end
	return nil, nil
end

-- Designed value of every element a fallback is currently holding off it (`record.tintRest`).
-- Captured on the first tint instead of read back at release time, so a press landing mid-hover
-- (or mid-release) still restores the design; cleared on release, so a panel that recolours the
-- button between interactions is never reverted to a stale colour.
local function tintGoal(property: string, rest: any, darken: boolean): any
	if property == "TextTransparency" then
		return math.clamp((rest :: number) + (if darken then PRESS_TEXT_FADE else HOVER_TEXT_FADE), 0, 1)
	end
	return (rest :: Color3):Lerp(if darken then BLACK else WHITE, if darken then PRESS_DARKEN else HOVER_LIGHTEN)
end

local function tintHold(element: GuiObject, property: string, darken: boolean, time: number)
	local record = state.of(element)
	local rest = record.tintRest
	if rest == nil then
		rest = (element :: any)[property]
		record.tintRest = rest
	end
	play(element, TINT_CHANNEL, info(time, Enum.EasingStyle.Quad), { [property] = tintGoal(property, rest, darken) })
end

-- Drops a held tint's rest capture without writing anything back. A row whose state repaint
-- (played / favorited template swap) changed the element's colour while a hover/press tint was
-- still holding must not have the OLD colour restored on release — that left the row half in each
-- state (reverted background, repainted text). The caller repaints after calling this, so the new
-- value becomes the design the next gesture captures.
function UIMotion.forgetTint(element: GuiObject)
	local record = state.get(element)
	if record == nil or record.tintRest == nil then
		return
	end
	record.tintRest = nil
	cancelChannel(element, TINT_CHANNEL)
end

-- Always puts back exactly what was captured, and instantly when there is no time to tween
-- (reduced motion, teardown, detached element): a press must never leave a colour changed.
local function tintRelease(element: GuiObject, property: string, time: number?)
	local record = state.get(element)
	if record == nil or record.tintRest == nil then
		return
	end
	local rest = record.tintRest
	record.tintRest = nil
	if time == nil or UIMotion.reduced() or not element.Parent then
		cancelChannel(element, TINT_CHANNEL)
		-- Written even while detached. Skipping it was the tint twin of the scale bug: the capture
		-- is dropped either way, so a pooled row came back still holding the press darken or the
		-- hover lighten, and the next gesture on it captured that tinted value as the design.
		local held = element :: any
		held[property] = rest
		return
	end
	play(element, TINT_CHANNEL, info(time, Enum.EasingStyle.Quad), { [property] = rest })
end

-- Runtime-only marker for the motion coverage audit (a scan lists GuiButtons without it). A
-- button bound for both press and hover keeps the strongest result: true (button scale) >
-- "icon" (icon scale) > "text" (label scale) > "fallback" (padding/brightness) > "no-target".
local function boundRank(value: any): number
	if value == true then
		return 5
	elseif value == "icon" then
		return 4
	elseif value == "text" then
		return 3
	elseif value == "fallback" then
		return 2
	elseif value == "no-target" then
		return 1
	end
	return 0
end

-- Public so the attribute has one writer: PressFeedback's own scale press (a `true`-rank bind) goes
-- through this and keeps the precedence instead of stamping the attribute itself.
function UIMotion.markBound(button: GuiObject, value: string | boolean)
	if boundRank(button:GetAttribute("UIMotionBound")) >= boundRank(value) then
		return
	end
	button:SetAttribute("UIMotionBound", value)
end

-- Press with no scale target: squash the button's padding, or dip what it paints when padding
-- would show nothing (a childless or AutomaticSize button).
local function bindPressFallback(button: GuiObject): { RBXScriptConnection }
	UIMotion.markBound(button, "fallback")
	local pressed = false
	local padding: UIPadding? = nil
	local element: GuiObject? = nil
	local property: string? = nil

	local function release(instant: boolean)
		if not pressed then
			return
		end
		pressed = false
		local heldPadding, heldElement, heldProperty = padding, element, property
		padding, element, property = nil, nil, nil
		if heldPadding and heldPadding.Parent then
			-- Back Out on a 2-6 px inset overshoots a few tenths of a pixel past the design and
			-- settles; nothing can spill, because the padding is internal to the button.
			local back = if instant or UIMotion.reduced()
				then nil
				else info(PRESS_RELEASE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			squashTo(heldPadding, 0, back)
		end
		if heldElement and heldProperty then
			-- A colour has nothing to spring back from, so it fades a touch under the scale release.
			tintRelease(heldElement, heldProperty, if instant then nil else 0.24)
		end
	end

	local connections = {
		button.InputBegan:Connect(function(input)
			if not isPress(input) or pressed or UIMotion.reduced() then
				return
			end
			pressed = true
			local amount = squashAmount(button)
			padding = if amount > 0 then squashPaddingOf(button) else nil
			local squashed = padding
			if squashed then
				squashTo(squashed, amount, info(PRESS_DOWN_TIME))
				return
			end
			element, property = tintTargetOf(button)
			local dimmed, dimmedProperty = element, property
			if dimmed and dimmedProperty then
				tintHold(dimmed, dimmedProperty, true, PRESS_DOWN_TIME)
			else
				-- Nothing to inset and nothing painted: an invisible hit area, genuinely silent.
				button:SetAttribute("UIMotionBound", "no-target")
			end
		end),
		button.InputEnded:Connect(function(input)
			if isPress(input) then
				release(false)
			end
		end),
		button.MouseLeave:Connect(function()
			release(false)
		end),
		UserInputService.InputEnded:Connect(function(input)
			if isPress(input) then
				release(false)
			end
		end),
	}
	return selfRelease(button, connections, function()
		release(true)
	end)
end

-- Hover with no scale target: brightness only. No padding — hover is a resting state, and
-- holding a button's content inset for as long as the cursor sits there reads as broken.
local function bindHoverFallback(button: GuiObject): { RBXScriptConnection }
	local element, property = tintTargetOf(button)
	if element == nil or property == nil then
		UIMotion.markBound(button, "no-target")
		return {}
	end
	UIMotion.markBound(button, "fallback")
	local lifted, liftedProperty = element, property
	local connections = {
		button.MouseEnter:Connect(function()
			if UIMotion.reduced() or not lifted.Parent then
				return
			end
			tintHold(lifted, liftedProperty, false, HOVER_IN_TIME)
		end),
		button.MouseLeave:Connect(function()
			tintRelease(lifted, liftedProperty, HOVER_OUT_TIME)
		end),
	}
	return selfRelease(button, connections, function()
		tintRelease(lifted, liftedProperty, nil)
	end)
end

-- Scale press, shared by the button tier (the button itself, or its recentred label), the icon tier
-- (the button's image, in place or in its slot) and the text tier (the button's one label): same
-- borrowed UIScale, same captured rest, same reduced-motion silence, same self-release back to rest
-- the moment the button leaves the tree.
local function bindScalePress(
	button: GuiObject,
	target: GuiObject,
	marker: string | boolean,
	pressScale: number
): { RBXScriptConnection }
	UIMotion.markBound(button, marker)
	local pressed = false
	local function release()
		if not pressed then
			return
		end
		pressed = false
		if UIMotion.reduced() or not target.Parent then
			-- No tween will land, so this path has to land the release itself: put the borrowed
			-- scale back on rest at once (and thaw a frozen label), exactly as the teardown does.
			-- Thawing alone left the target squashed for good — a pooled row (the music library's
			-- playlist cards, the Admin v3 player list) is re-shown as the same instance with the
			-- same UIScale, and `selfRelease`'s settle only runs when the button leaves the tree,
			-- which a pooled row never does. Reduced motion means no tween, not no final state.
			settleScale(target)
			return
		end
		-- The delight lives here. Back Out past 1 is bounded by the press depth (0.86 button /
		-- 0.92 icon and text), so the peak is ~1.010 / ~1.006 — under a tenth of a pixel on a
		-- 16 px list icon, and the icon slot already holds the footprint for anything bigger.
		scaleTo(scaleOf(target), 1, info(PRESS_RELEASE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), true)
	end
	local connections = {
		button.InputBegan:Connect(function(input)
			if not isPress(input) or pressed or UIMotion.reduced() then
				return
			end
			pressed = true
			freezeText(target)
			-- Never softened: see PRESS_DOWN_TIME.
			scaleTo(scaleOf(target), pressScale, info(PRESS_DOWN_TIME), false)
		end),
		button.InputEnded:Connect(function(input)
			if isPress(input) then
				release()
			end
		end),
		button.MouseLeave:Connect(release),
		UserInputService.InputEnded:Connect(function(input)
			if isPress(input) then
				release()
			end
		end),
	}
	return selfRelease(button, connections, function()
		-- Pooled rows come back re-shown: leave the scale at rest, without creating a UIScale.
		pressed = false
		settleScale(target)
	end)
end

local function bindScaleHover(
	button: GuiObject,
	target: GuiObject,
	marker: string | boolean,
	hoverScale: number
): { RBXScriptConnection }
	UIMotion.markBound(button, marker)
	local connections = {
		button.MouseEnter:Connect(function()
			if UIMotion.reduced() or not target.Parent then
				return
			end
			freezeText(target)
			-- Sine Out: a lift the cursor arrives into rather than one that snaps up to meet it.
			-- No overshoot on hover — the cursor can rest here, and a bounce under a resting
			-- pointer reads as a glitch.
			scaleTo(scaleOf(target), hoverScale, info(HOVER_IN_TIME, Enum.EasingStyle.Sine), false)
		end),
		button.MouseLeave:Connect(function()
			if UIMotion.reduced() or not target.Parent then
				-- Same hole as the press release, at the hover value instead of the press one: no
				-- tween to carry the lift home, so settle it here.
				settleScale(target)
				return
			end
			scaleTo(scaleOf(target), 1, info(HOVER_OUT_TIME, Enum.EasingStyle.Sine), true)
		end),
	}
	return selfRelease(button, connections, function()
		settleScale(target)
	end)
end

-- Squash on press, springy release. Four tiers, strongest first: the button (or its label) when
-- scaling it is layout-safe; else the button's icon, scaled in place or inside its slot; else the
-- one label a wordy button paints; else the button's own padding or brightness — never nothing.
-- Returns the connections so the caller can own them; the bind also drops them itself once the
-- button leaves the tree.
function UIMotion.bindPress(button: GuiObject, depth: number?): { RBXScriptConnection }
	local target = UIMotion.scaleTargetOf(button)
	if target then
		return bindScalePress(button, target, true, depth or 0.86)
	end
	-- An icon squash is written against the icon, not the button, so a caller's button-sized depth
	-- does not carry over. The same holds for a label.
	local icon = UIMotion.iconTargetOf(button)
	if icon then
		return bindScalePress(button, icon, "icon", ICON_PRESS)
	end
	local label = UIMotion.textTargetOf(button)
	if label then
		return bindScalePress(button, label, "text", ICON_PRESS)
	end
	return bindPressFallback(button)
end

-- Gentle lift while the mouse rests on a button: the button, else its icon, else its one label,
-- else a brightness lift when nothing can be scaled. Pointer devices only — a finger never hovers,
-- and on touch MouseEnter fires on tap and would fight the press squash.
function UIMotion.bindHover(button: GuiObject, lift: number?): { RBXScriptConnection }
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return {}
	end
	local target = UIMotion.scaleTargetOf(button)
	if target then
		return bindScaleHover(button, target, true, lift or 1.05)
	end
	local icon = UIMotion.iconTargetOf(button)
	if icon then
		return bindScaleHover(button, icon, "icon", ICON_HOVER)
	end
	local label = UIMotion.textTargetOf(button)
	if label then
		return bindScaleHover(button, label, "text", ICON_HOVER)
	end
	return bindHoverFallback(button)
end

-- Breathing loop on one numeric property (a glow's transparency, a badge's rotation) until the
-- returned stop function is called. Under reduced motion the property is left at rest.
function UIMotion.pulse(target: Instance, property: string, to: number, period: number?): () -> ()
	local rest = (target :: any)[property]
	if UIMotion.reduced() then
		return function() end
	end
	local tween = play(
		target,
		property,
		TweenInfo.new(MotionPresets.scaledTime(period or 1.2), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ [property] = to }
	)
	return function()
		tween:Cancel()
		local record = state.get(target)
		if record and record.running[property] == tween then
			record.running[property] = nil
		end
		if target.Parent then
			(target :: any)[property] = rest
		end
	end
end

-- Rolls a number label from one value to another. `format` receives the rounded value.
function UIMotion.countTo(
	label: TextLabel,
	from: number,
	to: number,
	time: number?,
	format: ((number) -> string)?
): ()
	local render = format or function(value: number): string
		return tostring(math.floor(value + 0.5))
	end
	if UIMotion.reduced() or from == to then
		label.Text = render(to)
		return
	end
	local value = Instance.new("NumberValue")
	value.Value = from
	local conn = value:GetPropertyChangedSignal("Value"):Connect(function()
		if label.Parent then
			label.Text = render(value.Value)
		end
	end)
	local tween = play(value, "Value", info(time or 0.6, Enum.EasingStyle.Quart), { Value = to })
	tween.Completed:Once(function()
		conn:Disconnect()
		if label.Parent then
			label.Text = render(to)
		end
		value:Destroy()
	end)
end

return UIMotion
