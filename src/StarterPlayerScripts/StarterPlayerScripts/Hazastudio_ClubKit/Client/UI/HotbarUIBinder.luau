--!strict
-- HotbarUIBinder (UI): renders InventoryStore hotbar slots; drag/tap-equip via InventoryDragController.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local MobilePanelManager = require(script.Parent.Parent.Services.MobilePanelManager)
local HotbarGuiRefs = require(script.Parent.HotbarGuiRefs)
local InventoryStore = require(script.Parent.Parent.State.InventoryStore)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)

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

type DragLift = {
	button: GuiButton,
	parent: Instance,
	placeholder: Frame,
	originalAnchorPoint: Vector2,
	originalAutomaticSize: Enum.AutomaticSize,
	originalLayoutOrder: number,
	originalPosition: UDim2,
	originalSize: UDim2,
	originalZIndex: number,
}

type DragState = {
	slotIndex: number,
	toolKey: string,
	currentIndex: number,
	startPosition: Vector2,
	isDragging: boolean,
	lift: DragLift?,
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

local function getGuiMousePosition(root: ScreenGui): Vector2
	local mouse = UserInputService:GetMouseLocation()
	if root.IgnoreGuiInset then
		return mouse
	end

	local inset = GuiService:GetGuiInset()
	return mouse - inset
end

local function getInputPosition(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y)
end

local function isWithin(root: Instance, candidate: Instance): boolean
	if candidate == root then
		return true
	end
	return candidate:IsDescendantOf(root)
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

local function liftDragButton(slot: RenderSlot, mousePosition: Vector2, dragParent: Instance): DragLift
	local button = slot.refs.button
	local parent = button.Parent
	assert(parent, "Hotbar drag button must have a parent")
	local absoluteSize = button.AbsoluteSize
	local placeholder = Instance.new("Frame")
	placeholder.Name = button.Name .. "InsertionPlaceholder"
	placeholder.BackgroundColor3 = Config.Hotbar.DRAG_PLACEHOLDER_COLOR
	placeholder.BackgroundTransparency = Config.Hotbar.DRAG_PLACEHOLDER_TRANSPARENCY
	placeholder.Size = button.Size
	placeholder.LayoutOrder = button.LayoutOrder

	local placeholderCorner = Instance.new("UICorner")
	placeholderCorner.CornerRadius = UDim.new(1, 0)
	placeholderCorner.Parent = placeholder

	placeholder.Parent = parent

	local lift = {
		button = button,
		parent = parent,
		placeholder = placeholder,
		originalAnchorPoint = button.AnchorPoint,
		originalAutomaticSize = button.AutomaticSize,
		originalLayoutOrder = button.LayoutOrder,
		originalPosition = button.Position,
		originalSize = button.Size,
		originalZIndex = button.ZIndex,
	}

	button.Parent = dragParent
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.AutomaticSize = Enum.AutomaticSize.None
	button.Size = UDim2.fromOffset(absoluteSize.X, absoluteSize.Y)
	button.Position = UDim2.fromOffset(mousePosition.X, mousePosition.Y)
	button.ZIndex = Config.Hotbar.DRAG_LIFT_ZINDEX
	ensureScale(slot.refs).Scale = Config.Hotbar.DRAG_LIFT_SCALE

	return lift
end

local function restoreDragButton(lift: DragLift): ()
	lift.button.Parent = lift.parent
	lift.button.AnchorPoint = lift.originalAnchorPoint
	lift.button.AutomaticSize = lift.originalAutomaticSize
	lift.button.LayoutOrder = lift.originalLayoutOrder
	lift.button.Position = lift.originalPosition
	lift.button.Size = lift.originalSize
	lift.button.ZIndex = lift.originalZIndex
	lift.placeholder:Destroy()
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

local function renderToolSlot(slot: RenderSlot, viewModel: HotbarSlotViewModel): ()
	local refs = slot.refs
	slot.viewModel = viewModel
	refs.button:SetAttribute(HOTBAR_TOOL_KEY_ATTRIBUTE, viewModel.toolKey)
	refs.button.Visible = true
	refs.button.LayoutOrder = slot.originalLayoutOrder
	refs.button.BackgroundColor3 = if viewModel.isEquipped
		then Config.Hotbar.EQUIPPED_BACKGROUND_COLOR
		else slot.originalBackgroundColor
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
	inventoryDrag: any?,
}): any
	local self = setmetatable({}, HotbarUIBinder)

	self._refs = deps.refs
	self._store = deps.store
	self._log = deps.logger
	self._inventoryDrag = deps.inventoryDrag
	self._slots = buildRenderSlots(deps.refs.slots)
	self._connections = {} :: { RBXScriptConnection }
	self._unsubscribers = {} :: { () -> () }
	self._disabledStickerDragDetectors = {} :: { DisabledDragDetector }
	self._dragState = nil :: DragState?
	self._dragOverlay = nil :: ScreenGui?
	self._dragPreviewSlots = nil :: { HotbarSlotViewModel }?
	self._reorderRequested = nil :: ((string, number) -> ())?
	self._equipRequested = nil :: ((string) -> ())?
	self._stickerRequested = nil :: (() -> ())?
	self._lastStickerRequestClock = 0
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
	self._refs.stickerButtonWrapper.Visible = true

	self:_connectInput()
	self:_subscribeStore()
	self:_render(deps.store:get().hotbarSlots, deps.store:get().hasTools)

	if self._inventoryDrag then
		self._inventoryDrag:setHotbarSlots(self:_slotRefsList())
		for index, slot in ipairs(self._slots) do
			self._inventoryDrag:bindHotbarSlot(slot.refs, index)
		end
		if type(self._inventoryDrag.setDragEndedCallback) == "function" then
			self._inventoryDrag:setDragEndedCallback(function()
				self:_clearDragLift()
				self._dragState = nil
				self._dragPreviewSlots = nil
				if type(self._inventoryDrag.sweepArtifacts) == "function" then
					self._inventoryDrag:sweepArtifacts()
				end
				self:_render(self._store:get().hotbarSlots, self._store:get().hasTools)
			end)
		end
	end

	return self
end

function HotbarUIBinder:_slotRefsList(): { SlotRefs }
	local refsList = {} :: { SlotRefs }
	for _, slot in ipairs(self._slots) do
		table.insert(refsList, slot.refs)
	end
	return refsList
end

function HotbarUIBinder:_trackConnection(connection: RBXScriptConnection): ()
	table.insert(self._connections, connection)
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

function HotbarUIBinder:_clearDragLift(): ()
	if self._dragState and self._dragState.lift then
		restoreDragButton(self._dragState.lift)
		self._dragState.lift = nil
	end
end

function HotbarUIBinder:_findSlotByToolKey(toolKey: string): RenderSlot?
	for _, slot in ipairs(self._slots) do
		if slot.viewModel and slot.viewModel.toolKey == toolKey then
			return slot
		end
	end

	return nil
end

function HotbarUIBinder:_findViewModelByToolKey(slots: { HotbarSlotViewModel }, toolKey: string): HotbarSlotViewModel?
	for _, viewModel in ipairs(slots) do
		if viewModel.toolKey == toolKey then
			return viewModel
		end
	end

	return nil
end

function HotbarUIBinder:_movePreviewSlot(
	slots: { HotbarSlotViewModel },
	toolKey: string,
	targetIndex: number
): { HotbarSlotViewModel }
	local nextSlots = table.clone(slots)
	local fromIndex = nil :: number?
	for index, viewModel in ipairs(nextSlots) do
		if viewModel.toolKey == toolKey then
			fromIndex = index
			break
		end
	end

	if not fromIndex then
		return nextSlots
	end

	local clampedTarget = math.clamp(targetIndex, 1, #nextSlots)
	if fromIndex == clampedTarget then
		return nextSlots
	end

	local moved = table.remove(nextSlots, fromIndex)
	table.insert(nextSlots, clampedTarget, moved)

	for index, viewModel in ipairs(nextSlots) do
		local clone = table.clone(viewModel)
		clone.index = index
		clone.slotId = tostring(index)
		nextSlots[index] = clone
	end

	return nextSlots
end

function HotbarUIBinder:_getDragOverlay(): ScreenGui
	if self._dragOverlay then
		return self._dragOverlay
	end

	local overlay = Instance.new("ScreenGui")
	overlay.Name = Config.Hotbar.DRAG_OVERLAY_NAME
	overlay.DisplayOrder = self._refs.root.DisplayOrder + Config.Hotbar.DRAG_OVERLAY_DISPLAY_ORDER_OFFSET
	overlay.IgnoreGuiInset = self._refs.root.IgnoreGuiInset
	overlay.ResetOnSpawn = false
	overlay.ZIndexBehavior = self._refs.root.ZIndexBehavior
	overlay.Parent = self._refs.root.Parent
	self._dragOverlay = overlay

	return overlay
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

function HotbarUIBinder:_insertionIndexAtMouse(mousePosition: Vector2, excludedToolKey: string): number?
	local candidates = {} :: { { centerX: number } }
	for _, slot in ipairs(self._slots) do
		if slot.viewModel and slot.viewModel.toolKey == excludedToolKey then
			continue
		end

		local position = slot.refs.button.AbsolutePosition
		local size = slot.refs.button.AbsoluteSize
		table.insert(candidates, {
			centerX = position.X + (size.X * 0.5),
		})
	end

	table.sort(candidates, function(left: { centerX: number }, right: { centerX: number }): boolean
		return left.centerX < right.centerX
	end)

	if #candidates == 0 then
		return nil
	end

	for index, candidate in ipairs(candidates) do
		if mousePosition.X < candidate.centerX then
			return index
		end
	end

	return math.min(#candidates + 1, #self._slots)
end

function HotbarUIBinder:_requestLiveReorder(dragState: DragState): ()
	local targetIndex = self:_insertionIndexAtMouse(getGuiMousePosition(self._refs.root), dragState.toolKey)
	if not targetIndex then
		return
	end
	if targetIndex == dragState.currentIndex then
		return
	end

	dragState.currentIndex = targetIndex
	self._dragPreviewSlots =
		self:_movePreviewSlot(self._dragPreviewSlots or self._store:get().hotbarSlots, dragState.toolKey, targetIndex)
	self:_render(self._dragPreviewSlots, self._store:get().hasTools)

	if self._reorderRequested then
		self._reorderRequested(dragState.toolKey, targetIndex)
	end
end

function HotbarUIBinder:_connectInput(): ()
	local useExternalDrag = self._inventoryDrag ~= nil

	for index, slot in ipairs(self._slots) do
		local button = slot.refs.button

		if useExternalDrag then
			continue
		end

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

			self._dragState = {
				slotIndex = index,
				toolKey = viewModel.toolKey,
				currentIndex = viewModel.index,
				startPosition = getInputPosition(input),
				isDragging = false,
				lift = nil,
			}
			self._dragPreviewSlots = table.clone(self._store:get().hotbarSlots)
		end))
	end

	if useExternalDrag then
		-- Drag + tap-equip handled by InventoryDragController.
		self:_trackConnection(UserInputService.InputChanged:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				self._mouseReady = true
			end
		end))
	elseif Config.Hotbar.INVENTORY_DRAG_ENABLED == true or Config.Hotbar.DRAG_REORDER_ENABLED == true then
	self:_trackConnection(UserInputService.InputChanged:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			self._mouseReady = true
		end

		local dragState = self._dragState
		if not dragState then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		local distance = (getInputPosition(input) - dragState.startPosition).Magnitude
		if distance >= Config.Hotbar.DRAG_START_THRESHOLD then
			dragState.isDragging = true
			if not dragState.lift then
				local slot = self:_findSlotByToolKey(dragState.toolKey)
				if not slot then
					return
				end
				dragState.lift = liftDragButton(slot, getGuiMousePosition(self._refs.root), self:_getDragOverlay())
			end
		end

		if dragState.lift then
			local mousePosition = getGuiMousePosition(self._refs.root)
			dragState.lift.button.Position = UDim2.fromOffset(mousePosition.X, mousePosition.Y)
			self:_requestLiveReorder(dragState)
		end
	end))

	self:_trackConnection(UserInputService.InputEnded:Connect(function(input: InputObject)
		local dragState = self._dragState
		if not dragState then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		if not dragState.isDragging then
			self._dragState = nil
			if self._equipRequested then
				self._equipRequested(dragState.toolKey)
			end
			return
		end

		self:_clearDragLift()
		self._dragState = nil
		self._dragPreviewSlots = nil
		self:_render(self._store:get().hotbarSlots, self._store:get().hasTools)
	end))
	else
		for index, slot in ipairs(self._slots) do
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
	end

	-- Only connect the render step loop if tools are already present at mount time
	if self._store:get().hasTools then
		self:_ensureStepConnection()
	end

	if self._refs.stickerButton then
		self._refs.stickerButton.Visible = true
		self._refs.stickerButton.Active = true

		for _, descendant in ipairs(self._refs.stickerButton:GetDescendants()) do
			if descendant:IsA("UIDragDetector") then
				table.insert(self._disabledStickerDragDetectors, {
					detector = descendant,
					enabled = descendant.Enabled,
				})
				descendant.Enabled = false
			end
		end

		local function requestStickerPanel()
			local now = os.clock()
			if now - self._lastStickerRequestClock < 0.35 then
				return
			end
			self._lastStickerRequestClock = now

			if self._stickerRequested then
				self._stickerRequested()
			end
		end

		self:_trackConnection(self._refs.stickerButton.Activated:Connect(requestStickerPanel))
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
	if self._inventoryDrag then
		local preview = self._inventoryDrag:getDragPreviewSlots()
		if preview then
			slots = preview
		end
	end

	if self._dragState == nil then
		self:_clearDragLift()
	end
	if self._dragState and self._dragPreviewSlots then
		slots = self._dragPreviewSlots
	end

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

	local dragState = self._dragState
	local externalDragKey = if self._inventoryDrag then self._inventoryDrag:getActiveDragToolKey() else nil

	if dragState and dragState.lift then
		local draggedViewModel = self:_findViewModelByToolKey(slots, dragState.toolKey)
		if draggedViewModel then
			renderToolSlot({
				refs = {
					button = dragState.lift.button,
					imageLabel = dragState.lift.button:FindFirstChildWhichIsA("ImageLabel", true) :: ImageLabel?,
					textLabel = dragState.lift.button:FindFirstChildWhichIsA("TextLabel", true) :: TextLabel?,
					stroke = dragState.lift.button:FindFirstChildWhichIsA("UIStroke"),
					scale = dragState.lift.button:FindFirstChildWhichIsA("UIScale"),
					dragDetector = nil,
				},
				originalBackgroundColor = dragState.lift.button.BackgroundColor3,
				originalBackgroundTransparency = dragState.lift.button.BackgroundTransparency,
				originalDragDetectorEnabled = nil,
				originalLayoutOrder = dragState.lift.originalLayoutOrder,
				originalText = "",
				originalTextVisible = false,
				originalTextTransparency = 1,
				originalImage = "",
				originalImageVisible = false,
				originalStroke = 0,
				originalScale = 1,
				baseZIndex = dragState.lift.originalZIndex,
				currentScale = 1,
				currentStroke = 0,
				currentTextTransparency = 1,
				viewModel = draggedViewModel,
			}, draggedViewModel)
		end

		local renderIndex = 1
		local visualIndex = 1
		dragState.lift.placeholder.LayoutOrder = dragState.currentIndex * 10
		for _, renderSlot in ipairs(self._slots) do
			if renderSlot.refs.button == dragState.lift.button then
				continue
			end

			local viewModel = slots[renderIndex]
			while viewModel and viewModel.toolKey == dragState.toolKey do
				renderIndex += 1
				viewModel = slots[renderIndex]
			end

			-- Hide slot chrome when no tool is bound at this visual index.
			if not viewModel then
				renderSlot.refs.button.Visible = false
				renderIndex += 1
				continue
			end

			renderToolSlot(renderSlot, viewModel)
			if visualIndex == dragState.currentIndex then
				visualIndex += 1
			end
			renderSlot.refs.button.LayoutOrder = visualIndex * 10
			visualIndex += 1
			renderIndex += 1
		end
		return
	end

	-- Normal render: show only slots that have a tool view model.
	local visualIndex = 1
	for index, renderSlot in ipairs(self._slots) do
		local viewModel = slots[index]
		if not viewModel then
			renderSlot.refs.button.Visible = false
			continue
		end

		if externalDragKey and viewModel.toolKey == externalDragKey then
			renderSlot.refs.button.Visible = false
			continue
		end

		renderToolSlot(renderSlot, viewModel)
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

	local mousePosition = getGuiMousePosition(self._refs.root)
	local dtAlpha = clamp01(dt * Config.Hotbar.SMOOTHING)

	for _, slot in ipairs(self._slots) do
		local refs = slot.refs
		if not slot.viewModel then
			continue
		end
		if self._dragState and self._dragState.lift and refs.button == self._dragState.lift.button then
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
			if (self._dragState and self._dragState.isDragging)
				or (self._inventoryDrag and self._inventoryDrag:isDragging())
			then
				refs.textLabel.Visible = false
				continue
			end
			refs.textLabel.Visible = false
			refs.textLabel.TextTransparency = slot.currentTextTransparency
		end
	end
end

function HotbarUIBinder:bindReorderRequested(callback: (string, number) -> ()): ()
	self._reorderRequested = callback
end

function HotbarUIBinder:bindEquipRequested(callback: (string) -> ()): ()
	self._equipRequested = callback
end

function HotbarUIBinder:bindStickerRequested(callback: () -> ()): ()
	self._stickerRequested = callback
end

function HotbarUIBinder:renderHotbarSlots(slots: { HotbarSlotViewModel }, hasTools: boolean): ()
	self:_render(slots, hasTools)
end

function HotbarUIBinder:destroy(): ()
	self:_clearDragLift()
	self:_disconnectStep()

	for _, slot in ipairs(self._slots) do
		if slot.refs.dragDetector and slot.originalDragDetectorEnabled ~= nil then
			slot.refs.dragDetector.Enabled = slot.originalDragDetectorEnabled
		end
	end

	for _, entry in ipairs(self._disabledStickerDragDetectors) do
		if entry.detector and entry.detector.Parent then
			entry.detector.Enabled = entry.enabled
		end
	end
	table.clear(self._disabledStickerDragDetectors)

	for _, unsubscribe in ipairs(self._unsubscribers) do
		unsubscribe()
	end
	table.clear(self._unsubscribers)

	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)

	if self._dragOverlay then
		self._dragOverlay:Destroy()
		self._dragOverlay = nil
	end
end

return HotbarUIBinder
