--!strict
-- Whole-GUI theme (CONTEXT.md "Accent theme"): every colour under an attached root follows the
-- accent through AccentDomain.recolor — saturated colours take the accent's hue (Graphite: their
-- grey), neutral grey backgrounds/strokes get the surface tint, Multicolor shows the design as is.
-- Covers BackgroundColor3, UIStroke.Color, TextColor3, ImageColor3 and UIGradient.Color.
--
-- Each (instance, property) remembers the value its GUI/code gave it (`design`) and the value
-- written over it (`written`). Code that repaints later (row state, hover release, segment reset)
-- is caught by the property signal and recoloured, so no paint site needs to know about this.
--
-- Only values that have *settled* (unchanged for a whole frame) are judged: a hover/press tween
-- passes through intermediate colours every frame, and treating those as design values fought the
-- tween and recorded wrong ones. A settled value that is the design under an older accent
-- (UIMotion restoring a rest captured before the switch) is recoloured to the current one.
--
-- Nothing is watched until a player first leaves Multicolor, so the default costs nothing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AccentDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.AccentDomain)
local AccentService = require(script.Parent.AccentService)

local AccentSurfaceTint = {}

-- Set on a ScreenGui or any GuiObject to keep it and everything under it as designed (the accent
-- picker dots, colour previews; buyers can opt a whole GUI out the same way).
AccentSurfaceTint.NO_TINT_ATTRIBUTE = "AccentNoTint"

-- The design value under a recolour, kept on the instance itself: Clone copies attributes, so a
-- row cloned from an already-recoloured template still knows its design.
local DESIGN_ATTRIBUTE_PREFIX = "AccentDesign"

-- Engine GUIs that manage their own look.
local SKIPPED_SCREEN_GUIS = {
	TopbarStandard = true,
	TopbarStandardClipped = true,
	TopbarCentered = true,
	TopbarCenteredClipped = true,
	BubbleChat = true,
	Chat = true,
}

local SAME_EPSILON = 0.5 / 255

type Value = Color3 | ColorSequence

type Entry = {
	inst: Instance,
	prop: string,
	surface: boolean,
	muted: boolean,
	design: Value?,
	written: Value?,
}

-- Strong tables + Destroying cleanup (weak keys on live Instances get collected at random).
local entries: { [Instance]: { Entry } } = {}
local roots: { [Instance]: boolean } = {}
local scannedRoots: { [Instance]: boolean } = {}
-- Entries whose value changed, with the frame it last changed on; judged once it settles.
local pending: { [Entry]: number } = {}
local frame = 0
local started = false

local function sameColor(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < SAME_EPSILON
		and math.abs(a.G - b.G) < SAME_EPSILON
		and math.abs(a.B - b.B) < SAME_EPSILON
end

local function same(a: Value, b: Value): boolean
	if typeof(a) == "Color3" and typeof(b) == "Color3" then
		return sameColor(a, b)
	end
	if typeof(a) == "ColorSequence" and typeof(b) == "ColorSequence" then
		local ka, kb = a.Keypoints, b.Keypoints
		if #ka ~= #kb then
			return false
		end
		for i, point in ipairs(ka) do
			if math.abs(point.Time - kb[i].Time) > 1e-4 or not sameColor(point.Value, kb[i].Value) then
				return false
			end
		end
		return true
	end
	return false
end

-- The colour under accent `id`, or nil when it stays as designed.
local function recolorColor(color: Color3, id: string, surface: boolean, muted: boolean): Color3?
	local r, g, b = AccentDomain.recolor(color.R * 255, color.G * 255, color.B * 255, id, surface, muted)
	if r == nil or g == nil or b == nil then
		return nil
	end
	return Color3.new(r / 255, g / 255, b / 255)
end

-- The value under accent `id`, plus whether any part of it is recoloured at all.
local function recolorValue(value: Value, id: string, surface: boolean, muted: boolean): (Value, boolean)
	if typeof(value) == "Color3" then
		local color = recolorColor(value, id, surface, muted)
		return color or value, color ~= nil
	end
	local sequence = value :: ColorSequence
	local points = {}
	local changed = false
	for _, point in ipairs(sequence.Keypoints) do
		local color = recolorColor(point.Value, id, surface, false)
		changed = changed or color ~= nil
		table.insert(points, ColorSequenceKeypoint.new(point.Time, color or point.Value))
	end
	return if changed then ColorSequence.new(points) else sequence, changed
end

local function isRecolorable(value: Value, surface: boolean): boolean
	-- Asked against a coloured accent so the answer does not depend on the one in use.
	local _, changed = recolorValue(value, "blue", surface, false)
	return changed
end

local function current(entry: Entry): Value
	return (entry.inst :: any)[entry.prop]
end

local function themed(entry: Entry, design: Value): Value
	return (recolorValue(design, AccentService.get().id, entry.surface, entry.muted))
end

-- True when `value` is `design` under some accent (a stale rest, or a clone made before a switch).
local function isSomeThemeOf(entry: Entry, value: Value, design: Value): boolean
	for _, id in ipairs(AccentDomain.ORDER) do
		if same(value, (recolorValue(design, id, entry.surface, entry.muted))) then
			return true
		end
	end
	return false
end

local function write(entry: Entry, value: Value)
	entry.written = value
	if not same(current(entry), value) then
		(entry.inst :: any)[entry.prop] = value
	end
end

local function settle(entry: Entry)
	local value = current(entry)
	if entry.written and same(value, entry.written) then
		return
	end
	local design = entry.design
	if design and isSomeThemeOf(entry, value, design) then
		write(entry, themed(entry, design))
		return
	end
	entry.written = nil
	if isRecolorable(value, entry.surface) then
		entry.design = value
		local attribute = DESIGN_ATTRIBUTE_PREFIX .. entry.prop
		local stored = entry.inst:GetAttribute(attribute)
		if stored == nil or not same(stored :: any, value) then
			entry.inst:SetAttribute(attribute, value)
		end
		write(entry, themed(entry, value))
	end
end

RunService.Heartbeat:Connect(function()
	frame += 1
	if next(pending) == nil then
		return
	end
	for entry, changedOn in pairs(pending) do
		if changedOn < frame - 1 then
			pending[entry] = nil
			if entry.inst.Parent then
				settle(entry)
			end
		end
	end
end)

-- Strokes: no grey tint and muted colours — hundreds of thin lines in accent glare were too loud.
-- Gradients take the grey tint like backgrounds: a grey fade over a tinted card (the avatar context
-- menu's overlay) must land on the card's colour, not on the bare grey.
local function propsFor(inst: Instance): { { prop: string, surface: boolean, muted: boolean? } }?
	if inst:IsA("UIGradient") then
		return { { prop = "Color", surface = true } }
	elseif inst:IsA("UIStroke") then
		return { { prop = "Color", surface = false, muted = true } }
	elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		return { { prop = "BackgroundColor3", surface = true }, { prop = "ImageColor3", surface = false } }
	elseif inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		return { { prop = "BackgroundColor3", surface = true }, { prop = "TextColor3", surface = false } }
	elseif inst:IsA("GuiObject") then
		return { { prop = "BackgroundColor3", surface = true } }
	end
	return nil
end

local function isExcluded(inst: Instance, root: Instance): boolean
	local node: Instance? = inst
	while node do
		if node:GetAttribute(AccentSurfaceTint.NO_TINT_ATTRIBUTE) then
			return true
		end
		if node == root then
			return false
		end
		node = node.Parent
	end
	return false
end

local function watch(inst: Instance, root: Instance)
	if entries[inst] then
		return
	end
	local props = propsFor(inst)
	if props == nil or isExcluded(inst, root) then
		return
	end
	local list: { Entry } = {}
	entries[inst] = list
	for _, spec in ipairs(props) do
		local entry: Entry = { inst = inst, prop = spec.prop, surface = spec.surface, muted = spec.muted == true }
		table.insert(list, entry)
		local carried = inst:GetAttribute(DESIGN_ATTRIBUTE_PREFIX .. spec.prop)
		if typeof(carried) == "Color3" or typeof(carried) == "ColorSequence" then
			entry.design = carried
		end
		inst:GetPropertyChangedSignal(spec.prop):Connect(function()
			pending[entry] = frame
		end)
		-- First sight is judged at once so a freshly shown row never flashes its design colour.
		settle(entry)
	end
	inst.Destroying:Connect(function()
		for _, entry in ipairs(list) do
			pending[entry] = nil
		end
		entries[inst] = nil
	end)
end

local function scan(root: Instance)
	if scannedRoots[root] then
		return
	end
	scannedRoots[root] = true
	watch(root, root)
	for _, descendant in ipairs(root:GetDescendants()) do
		watch(descendant, root)
	end
	root.DescendantAdded:Connect(function(descendant)
		watch(descendant, root)
	end)
end

local function start()
	if started then
		return
	end
	started = true
	for root in pairs(roots) do
		scan(root)
	end
end

-- Theme every colour under `root`, now and as rows are added. Safe to call twice.
function AccentSurfaceTint.attach(root: Instance)
	if roots[root] then
		return
	end
	roots[root] = true
	root.Destroying:Connect(function()
		roots[root] = nil
		scannedRoots[root] = nil
	end)
	if started then
		scan(root)
	end
end

-- Every kit ScreenGui in PlayerGui, including ones added later (lazy-loaded panels).
local playerGuiAttached = false
function AccentSurfaceTint.attachPlayerGui(playerGui: Instance)
	if playerGuiAttached then
		return
	end
	playerGuiAttached = true
	local function consider(child: Instance)
		if child:IsA("ScreenGui") and not SKIPPED_SCREEN_GUIS[child.Name] then
			AccentSurfaceTint.attach(child)
		end
	end
	for _, child in ipairs(playerGui:GetChildren()) do
		consider(child)
	end
	playerGui.ChildAdded:Connect(consider)
end

local function onAccentChanged()
	if not started then
		if AccentService.get().id == AccentDomain.DEFAULT then
			return
		end
		start()
		return
	end
	for _, list in pairs(entries) do
		for _, entry in ipairs(list) do
			local design = entry.design
			if design then
				local value = current(entry)
				local written = entry.written
				if (written and same(value, written)) or isSomeThemeOf(entry, value, design) then
					write(entry, themed(entry, design))
				end
			end
		end
	end
end

AccentService.subscribe(onAccentChanged)
-- The venue default may already be a colour before any settings arrive.
task.defer(onAccentChanged)

return AccentSurfaceTint
