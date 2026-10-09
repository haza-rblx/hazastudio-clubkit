--!strict
-- HotbarUIBinder (UI): renders InventoryStore hotbar slots; a tap on a slot asks to equip it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local MobilePanelManager = require(script.Parent.Parent.Services.MobilePanelManager)
local HotbarGuiRefs = require(script.Parent.HotbarGuiRefs)
local InventoryStore = require(script.Parent.Parent.State.InventoryStore)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local UIMotion = require(script.Parent.Parent.Utils.UIMotion)
local PointerSpace = require(script.Parent.Parent.Utils.PointerSpace)

type HotbarSlotViewModel = InventoryStore.HotbarSlotViewModel
type Refs = HotbarGuiRefs.Refs
type SlotRefs = HotbarGuiRefs.SlotRefs
type ILogger = Types.ILogger

type RenderSlot = {
	refs: SlotRefs,
	originalBackgroundColor: Color3,
	originalBackgroundTransparency: number,
	originalDragDetectorEnabled: boolean?,
	originalLayoutOrder: number,
	originalText: string,
	originalTextVisible: boolean,
	originalTextTransparency: number,
	originalImage: string,
	originalImageVisible: boolean,
	originalStroke: number,
	originalScale: number,
	baseZIndex: number,
	currentScale: number,
	currentStroke: number,
	currentTextTransparency: number,
	viewModel: HotbarSlotViewModel?,
}

type DisabledDragDetector = {
	detector: UIDragDetector,
	enabled: boolean,
}

local HotbarUIBinder = {}
HotbarUIBinder.__index = HotbarUIBinder

local function clamp01(value: number): number
	return math.clamp(value, 0, 1)
end

local function lerp(a: number, b: number, t: number): number
	return a + ((b - a) * t)
end

local function sampleState(raw: number, a: number, b: number, c: number): number
	if raw <= 0.5 then
		return lerp(a, b, raw * 2)
	end

	return lerp(b, c, (raw - 0.5) * 2)
end

local function ensureScale(refs: SlotRefs): UIScale
	if refs.scale then
		return refs.scale
	end

	local scale = Instance.new("UIScale")
	scale.Name = "RuntimeHotbarScale"
	scale.Scale = 1
	scale.Parent = refs.button
	refs.scale = scale
	return scale
end

local function disableNativeDragDetectors(root: Instance): ()
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("UIDragDetector") then
			descendant.Enabled = false
		end
	end
	local direct = root:FindFirstChildWhichIsA("UIDragDetector")
	if direct and direct:IsA("UIDragDetector") then
		direct.Enabled = false
	end
end

local function ensureStroke(refs: SlotRefs): UIStroke
	if refs.stroke then
		return refs.stroke
	end

	local stroke = Instance.new("UIStroke")
	stroke.Name = "RuntimeHotbarStroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = refs.button
	refs.stroke = stroke
	return stroke
end

local function buildRenderSlots(refSlots: { SlotRefs }): { RenderSlot }
	local slots = {} :: { RenderSlot }
	for _, refs in ipairs(refSlots) do
		local scale = ensureScale(refs)
		local stroke = ensureStroke(refs)
		local originalDragDetectorEnabled = if refs.dragDetector then refs.dragDetector.Enabled else nil
		if refs.dragDetector then
			refs.dragDetector.Enabled = false
		end

		table.insert(slots, {
			refs = refs,
			originalBackgroundColor = refs.button.BackgroundColor3,
			originalBackgroundTransparency = refs.button.BackgroundTransparency,
			originalDragDetectorEnabled = originalDragDetectorEnabled,
			originalLayoutOrder = refs.button.LayoutOrder,
			originalText = if refs.textLabel then refs.textLabel.Text else "",
			originalTextVisible = if refs.textLabel then refs.textLabel.Visible else false,
			originalTextTransparency = if refs.textLabel then refs.textLabel.TextTransparency else 0,
			originalImage = if refs.imageLabel then refs.imageLabel.Image else "",
			originalImageVisible = if refs.imageLabel then refs.imageLabel.Visible else false,
			originalStroke = stroke.Thickness,
			originalScale = scale.Scale,
			baseZIndex = refs.button.ZIndex,
			currentScale = scale.Scale,
			currentStroke = stroke.Thickness,
			currentTextTransparency = if refs.textLabel then refs.textLabel.TextTransparency else 1,
			viewModel = nil,
		})
	end

	return slots
end

local function setButtonText(button: GuiButton, text: string): ()
	if button:IsA("TextButton") then
		(button :: TextButton).Text = ""
	end

	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			descendant.Text = text
		end
	end
end

local function renderEmptySlot(slot: RenderSlot, viewModel: HotbarSlotViewModel?): ()
	local refs = slot.refs
	slot.viewModel = viewModel
	refs.button.Visible = true
	refs.button.LayoutOrder = slot.originalLayoutOrder
	refs.button.BackgroundColor3 = slot.originalBackgroundColor
	refs.button.BackgroundTransparency = slot.originalBackgroundTransparency
	refs.button.ZIndex = slot.baseZIndex
	ensureScale(refs).Scale = slot.originalScale
	ensureStroke(refs).Thickness = slot.originalStroke
	setButtonText(refs.button, "")

	if refs.textLabel then
		refs.textLabel.Visible = false
		refs.textLabel.TextTransparency = slot.originalTextTransparency
	end

	if refs.imageLabel then
		refs.imageLabel.Image = Config.Hotbar.EMPTY_IMAGE
		refs.imageLabel.Visible = false
	end
end

local HOTBAR_TOOL_KEY_ATTRIBUTE = "InventoryToolKey"

-- `animate` lets an equip change glide; a repaint that changes nothing (equip echo, chrome show)
-- must not read as a change.
local function renderToolSlot(slot: RenderSlot, viewModel: HotbarSlotViewModel, animate: boolean?): ()
	local refs = slot.refs
	local previous = slot.viewModel
	slot.viewModel = viewModel
	refs.button:SetAttribute(HOTBAR_TOOL_KEY_ATTRIBUTE, viewModel.toolKey)
	refs.button.Visible = true
	refs.button.LayoutOrder = slot.originalLayoutOrder
	local background = if viewModel.isEquipped
		then Config.Hotbar.EQUIPPED_BACKGROUND_COLOR
		else slot.originalBackgroundColor
	local sameTool = previous ~= nil and previous.toolKey == viewModel.toolKey
	if animate ~= true or not sameTool then
		refs.button.BackgroundColor3 = background
	elseif previous ~= nil and previous.isEquipped ~= viewModel.isEquipped then
		-- Selected-slot highlight glides; a repaint that changes nothing leaves it alone.
		UIMotion.tween(refs.button, 0.16, { BackgroundColor3 = background })
	end
	refs.button.BackgroundTransparency = slot.originalBackgroundTransparency
	setButtonText(refs.button, viewModel.displayName)

	if refs.textLabel then
		refs.textLabel.Visible = false
		refs.textLabel.TextTransparency = Config.Hotbar.STATE_A.LABEL_TRANSPARENCY
	end

	if refs.imageLabel then
		refs.imageLabel.Image = viewModel.iconAsset
		refs.imageLabel.Visible = viewModel.iconAsset ~= ""
	end
end

function HotbarUIBinder.new(deps: {
	refs: Refs,
	store: any,
	logger: ILogger,
}): any
	local self = setmetatable({}, HotbarUIBinder)

	self._refs = deps.refs
	self._store = deps.store
	self._log = deps.logger
	self._slots = buildRenderSlots(deps.refs.slots)
	self._connections = {} :: { RBXScriptConnection }
	self._unsubscribers = {} :: { () -> () }
	self._equipRequested = nil :: ((string) -> ())?
	self._mouseReady = false
	self._pendingEquipKey = nil :: string?
	self._backpackButton = deps.refs.backpackButton
	if self._backpackButton then
		disableNativeDragDetectors(self._backpackButton)
		self._backpackButton.Active = true
		self._backpackButton.Selectable = true
	end
	disableNativeDragDetectors(self._refs.hotbarWrapper)

	self._refs.root.Enabled = not (Workspace.CurrentCamera and Workspace.CurrentCamera:GetAttribute("FreecamActive") == true)
	self._refs.root.DisplayOrder = Config.Hotbar.DISPLAY_ORDER

	self:_connectInput()
	self:_subscribeStore()
	self:_render(deps.store:get().hotbarSlots, deps.store:get().hasTools)

	return self
end

function HotbarUIBinder:_trackConnection(connection: RBXScriptConnection): ()
	table.insert(self._connections, connection)
end

function HotbarUIBinder:_trackConnections(connections: { RBXScriptConnection }): ()
	for _, connection in ipairs(connections) do
		table.insert(self._connections, connection)
	end
end

function HotbarUIBinder:_trackUnsubscriber(unsubscribe: () -> ()): ()
	table.insert(self._unsubscribers, unsubscribe)
end

function HotbarUIBinder:_ensureStepConnection(): ()
	if Config.Hotbar.DOCK_ZOOM_ENABLED ~= true then
		return
	end
	if self._stepConn then
		return
	end
	self._stepConn = RunService.RenderStepped:Connect(function(dt: number)
		self:_step(dt)
	end)
end

function HotbarUIBinder:_disconnectStep(): ()
	if self._stepConn then
		self._stepConn:Disconnect()
		self._stepConn = nil
	end
end

-- Slot buttons live in the wrapper's UIListLayout and their own UIScale belongs to the dock
-- zoom loop, so every pop/squash goes on the slot's icon instead. UIMotion re-anchors a lone
-- icon once (pixel-neutral) and returns nil for anything it cannot scale safely.
function HotbarUIBinder:_iconTargetOf(refs: SlotRefs): GuiObject?
	local icon = refs.imageLabel
	local host: GuiObject = refs.button
	if icon and icon.Parent and icon.Parent:IsA("GuiObject") then
		host = icon.Parent :: GuiObject
	end
	local target = UIMotion.scaleTargetOf(host)
	if icon ~= nil and target ~= icon and UIMotion.canScale(icon) then
		return icon
	end
	if target == refs.button then
		return nil
	end
	return target
end

function HotbarUIBinder:_animateSlotChange(
	slot: RenderSlot,
	previous: HotbarSlotViewModel?,
	viewModel: HotbarSlotViewModel
): ()
	local icon = self:_iconTargetOf(slot.refs)
	if icon == nil then
		return
	end

	if previous == nil or previous.toolKey ~= viewModel.toolKey then
		UIMotion.popIn(icon, 0.72)
	elseif viewModel.isEquipped and not previous.isEquipped then
		UIMotion.pop(icon, 1.18)
	end
end

function HotbarUIBinder:_subscribeStore(): ()
	self:_trackUnsubscriber(self._store:subscribe("hotbarSlots", function(slots: { HotbarSlotViewModel })
		self:_render(slots, self._store:get().hasTools)
	end))

	self:_trackUnsubscriber(self._store:subscribe("hasTools", function(hasTools: boolean)
		-- Gate the RenderStepped loop on whether tools exist to render
		if hasTools then
			self:_ensureStepConnection()
		else
			self:_disconnectStep()
		end
		self:_render(self._store:get().hotbarSlots, hasTools)
	end))

	self:_trackUnsubscriber(self._store:subscribe("inventoryChromeHidden", function()
		self:_render(self._store:get().hotbarSlots, self._store:get().hasTools)
	end))
end

function HotbarUIBinder:_connectInput(): ()
	-- Press/hover feedback; these listeners only read input, they never consume it, so the
	-- tap-equip below is untouched.
	for _, slot in ipairs(self._slots) do
		local button = slot.refs.button
		-- A slot must never gain a second UIScale: its own belongs to the dock zoom loop.
		-- canScale is true only where UIMotion would squash the button itself, so bind the
		-- squash only when it lands on the icon.
		if not UIMotion.canScale(button) then
			self:_trackConnections(UIMotion.bindPress(button))
			self:_trackConnections(UIMotion.bindHover(button))
		end
		self:_trackConnection(button.InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end

			local viewModel = slot.viewModel
			if viewModel ~= nil and not viewModel.isEmpty and viewModel.toolKey ~= nil then
				return
			end
			-- Nothing equippable here: refuse visibly instead of swallowing the tap.
			UIMotion.wiggle(button, 6)
		end))
	end

	if self._backpackButton then
		self:_trackConnections(UIMotion.bindPress(self._backpackButton))
		self:_trackConnections(UIMotion.bindHover(self._backpackButton))
	end

	-- The dock zoom loop reads the cursor, but only once it has moved at least once.
	self:_trackConnection(UserInputService.InputChanged:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			self._mouseReady = true
		end
	end))

	-- Tap-equip: press and release on the same slot.
	for _, slot in ipairs(self._slots) do
		local button = slot.refs.button
		self:_trackConnection(button.InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end

			local viewModel = slot.viewModel
			if not viewModel or viewModel.isEmpty or not viewModel.toolKey then
				return
			end

			self._pendingEquipKey = viewModel.toolKey
		end))

		self:_trackConnection(button.InputEnded:Connect(function(input: InputObject)
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end

			local viewModel = slot.viewModel
			if not viewModel or not viewModel.toolKey then
				return
			end

			if self._pendingEquipKey == viewModel.toolKey and self._equipRequested then
				self._equipRequested(viewModel.toolKey)
			end
			self._pendingEquipKey = nil
		end))
	end

	-- Only connect the render step loop if tools are already present at mount time
	if self._store:get().hasTools then
		self:_ensureStepConnection()
	end
end

function HotbarUIBinder:_findHotbarChromeRoot(): GuiObject?
	local chromeRoot = self._refs.root:FindFirstChild(Config.Hotbar.HOTBAR_CHROME_ROOT_NAME)
	if chromeRoot and chromeRoot:IsA("GuiObject") then
		return chromeRoot :: GuiObject
	end
	return nil
end

function HotbarUIBinder:_applyChromeFullyHidden(): ()
	local chromeRoot = self:_findHotbarChromeRoot()
	if chromeRoot then
		chromeRoot.Visible = false
	end
	self._refs.hotbarWrapper.Visible = false
	if self._backpackButton then
		self._backpackButton.Visible = false
	end
	for _, slot in ipairs(self._slots) do
		slot.refs.button.Visible = false
	end
end

function HotbarUIBinder:_render(slots: { HotbarSlotViewModel }, hasTools: boolean): ()
	self._refs.root.Enabled = not (Workspace.CurrentCamera and Workspace.CurrentCamera:GetAttribute("FreecamActive") == true)
	self._refs.root.DisplayOrder = Config.Hotbar.DISPLAY_ORDER

	local chromePhase = MobilePanelManager.getInventoryChromePhase()
	local storeChromeHidden = self._store:get().inventoryChromeHidden == true
	-- Fully hidden only when animator phase and store agree (avoids race on idle show).
	if chromePhase == "hidden" and storeChromeHidden then
		self:_applyChromeFullyHidden()
		return
	end

	if not hasTools then
		self._refs.hotbarWrapper.Visible = false
		if self._backpackButton then
			self._backpackButton.Visible = false
		end
		for _, slot in ipairs(self._slots) do
			slot.refs.button.Visible = false
		end
		return
	end

	local chromeRoot = self:_findHotbarChromeRoot()
	if chromeRoot then
		chromeRoot.Visible = true
	end
	self._refs.hotbarWrapper.Visible = true
	if self._backpackButton then
		self._backpackButton.Visible = true
	end

	-- Normal render: show only slots that have a tool view model.
	local visualIndex = 1
	for index, renderSlot in ipairs(self._slots) do
		local viewModel = slots[index]
		if not viewModel then
			renderSlot.refs.button.Visible = false
			continue
		end

		local previousModel = renderSlot.viewModel
		renderToolSlot(renderSlot, viewModel, true)
		self:_animateSlotChange(renderSlot, previousModel, viewModel)
		renderSlot.refs.button.LayoutOrder = visualIndex * 10
		visualIndex += 1
	end
end


function HotbarUIBinder:_step(dt: number): ()
	if Config.Hotbar.DOCK_ZOOM_ENABLED ~= true then
		return
	end
	if not self._refs.hotbarWrapper.Visible then
		return
	end

	if not self._mouseReady then
		return
	end

	local mousePosition = PointerSpace.mouse()
	local dtAlpha = clamp01(dt * Config.Hotbar.SMOOTHING)

	for _, slot in ipairs(self._slots) do
		local refs = slot.refs
		if not slot.viewModel then
			continue
		end
		local absolutePosition = refs.button.AbsolutePosition
		local absoluteSize = refs.button.AbsoluteSize
		-- Distance from cursor to the nearest point on the button's bounding box.
		-- 0 when the cursor is inside the button, grows outward.
		local dx = math.max(0, absolutePosition.X - mousePosition.X, mousePosition.X - (absolutePosition.X + absoluteSize.X))
		local dy = math.max(0, absolutePosition.Y - mousePosition.Y, mousePosition.Y - (absolutePosition.Y + absoluteSize.Y))
		local distance = math.sqrt(dx * dx + dy * dy)
		local proximity = clamp01(1 - (distance / math.max(Config.Hotbar.MAGNIFIER_RADIUS, 1)))
		local rawInfluence = proximity ^ Config.Hotbar.MAGNIFIER_FALLOFF
		local targetScale = sampleState(
			rawInfluence,
			Config.Hotbar.STATE_A.SCALE,
			Config.Hotbar.STATE_B.SCALE,
			Config.Hotbar.STATE_C.SCALE
		)
		local targetStroke = sampleState(
			rawInfluence,
			Config.Hotbar.STATE_A.STROKE,
			Config.Hotbar.STATE_B.STROKE,
			Config.Hotbar.STATE_C.STROKE
		)
		local targetTextTransparency = sampleState(
			rawInfluence,
			Config.Hotbar.STATE_A.LABEL_TRANSPARENCY,
			Config.Hotbar.STATE_B.LABEL_TRANSPARENCY,
			Config.Hotbar.STATE_C.LABEL_TRANSPARENCY
		)

		slot.currentScale = lerp(slot.currentScale, targetScale, dtAlpha)
		slot.currentStroke = lerp(slot.currentStroke, targetStroke, dtAlpha)
		slot.currentTextTransparency = lerp(slot.currentTextTransparency, targetTextTransparency, dtAlpha)

		ensureScale(refs).Scale = slot.currentScale
		ensureStroke(refs).Thickness = slot.currentStroke
		refs.button.ZIndex = slot.baseZIndex + math.round(rawInfluence * Config.Hotbar.ZINDEX_BUMP)

		if refs.textLabel and slot.viewModel then
			refs.textLabel.Visible = false
			refs.textLabel.TextTransparency = slot.currentTextTransparency
		end
	end
end

function HotbarUIBinder:bindEquipRequested(callback: (string) -> ()): ()
	self._equipRequested = callback
end

function HotbarUIBinder:renderHotbarSlots(slots: { HotbarSlotViewModel }, hasTools: boolean): ()
	self:_render(slots, hasTools)
end

function HotbarUIBinder:destroy(): ()
	self:_disconnectStep()

	for _, slot in ipairs(self._slots) do
		if slot.refs.dragDetector and slot.originalDragDetectorEnabled ~= nil then
			slot.refs.dragDetector.Enabled = slot.originalDragDetectorEnabled
		end
	end

	for _, unsubscribe in ipairs(self._unsubscribers) do
		unsubscribe()
	end
	table.clear(self._unsubscribers)

	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
end

return HotbarUIBinder
