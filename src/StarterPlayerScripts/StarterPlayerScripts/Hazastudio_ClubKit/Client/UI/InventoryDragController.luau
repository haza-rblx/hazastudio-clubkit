--!strict
-- InventoryDragController (UI)
--
-- Touch/mouse drag between hotbar and backpack; commits via Main.client callbacks.
-- No remotes. Hotbar reorder snapshots order; backpack→backpack preview is not committed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local HotbarGuiRefs = require(script.Parent.HotbarGuiRefs)
local InventoryStore = require(script.Parent.Parent.State.InventoryStore)

type HotbarSlotViewModel = InventoryStore.HotbarSlotViewModel
type SlotRefs = HotbarGuiRefs.SlotRefs

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

type DragSource = "hotbar" | "backpack"

type DragState = {
	source: DragSource,
	toolKey: string,
	currentHotbarIndex: number?,
	currentBackpackIndex: number?,
	startPosition: Vector2,
	lastPosition: Vector2,
	screenGrabOffset: Vector2,
	startedWithTouch: boolean,
	activeTouch: InputObject?,
	isDragging: boolean,
	lift: DragLift?,
	orderSnapshot: { string }?,
	scrollWasEnabled: boolean?,
}

export type BackpackCell = {
	refs: SlotRefs,
	toolKey: string?,
}

local InventoryDragController = {}
InventoryDragController.__index = InventoryDragController

local TOOL_KEY_ATTRIBUTE = "InventoryToolKey"

-- Returns position in the same space as GuiObject.AbsolutePosition
-- (viewport/inset coords; Y=0 at viewport top, below CoreGui).
-- Both InputObject.Position and GetMouseLocation() already use this system.
local function getAbsoluteScreenPointer(input: InputObject?): Vector2
	if input then
		return Vector2.new(input.Position.X, input.Position.Y)
	end
	return UserInputService:GetMouseLocation()
end

local function screenCenterForDrag(screenPosition: Vector2, grabOffset: Vector2): Vector2
	return screenPosition - grabOffset
end

local function findHotbarViewModel(slots: { HotbarSlotViewModel }, toolKey: string): HotbarSlotViewModel?
	for _, viewModel in ipairs(slots) do
		if viewModel.toolKey == toolKey then
			return viewModel
		end
	end
	return nil
end

local function isDragEndInput(input: InputObject, dragState: DragState): boolean
	if dragState.startedWithTouch then
		if dragState.activeTouch then
			return input == dragState.activeTouch
		end
		return input.UserInputType == Enum.UserInputType.Touch
	end
	return input.UserInputType == Enum.UserInputType.MouseButton1
end

local function liftDragButton(button: GuiButton, mousePosition: Vector2, dragParent: Instance): DragLift
	local parent = button.Parent
	assert(parent, "Inventory drag button must have a parent")
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

	return lift
end

local function cleanupDragPlaceholder(lift: DragLift): ()
	if lift.placeholder and lift.placeholder.Parent then
		lift.placeholder:Destroy()
	end
end

local PLACEHOLDER_SUFFIX = "InsertionPlaceholder"

local function isInsertionPlaceholder(instance: Instance): boolean
	return string.sub(instance.Name, -#PLACEHOLDER_SUFFIX) == PLACEHOLDER_SUFFIX
end

local function destroyOrphanOverlayButtons(overlay: ScreenGui?, preserveButton: GuiButton?): ()
	if not overlay then
		return
	end
	for _, child in ipairs(overlay:GetChildren()) do
		if child:IsA("GuiButton") and child ~= preserveButton then
			child:Destroy()
		end
	end
end

local function sweepInsertionPlaceholdersUnder(root: Instance?): ()
	if not root then
		return
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if isInsertionPlaceholder(descendant) then
			descendant:Destroy()
		end
	end
end

local function sweepDragArtifacts(
	hotbarWrapper: Frame,
	overlay: ScreenGui?,
	preserveButton: GuiButton?,
	backpackScroll: Instance?
): ()
	sweepInsertionPlaceholdersUnder(hotbarWrapper)
	sweepInsertionPlaceholdersUnder(backpackScroll)
	destroyOrphanOverlayButtons(overlay, preserveButton)
end

local function countVisibleHotbarTools(self: any, excludedToolKey: string): number
	local count = 0
	local slots = self._getHotbarSlots()
	for index, refs in ipairs(self._hotbarSlots) do
		local vm = slots[index]
		if not vm or not vm.toolKey or vm.toolKey == excludedToolKey then
			continue
		end
		if refs.button.Visible then
			count += 1
		end
	end
	return count
end

local function clampedHotbarPlaceholderOrder(targetIndex: number, visibleToolCount: number): number
	local maxIndex = math.max(1, visibleToolCount + 1)
	return math.clamp(targetIndex, 1, maxIndex) * 10
end

local function setPlaceholderVisible(lift: DragLift, visible: boolean): ()
	local placeholder = lift.placeholder
	if not placeholder or not placeholder.Parent then
		return
	end
	placeholder.Visible = visible
end

local function restoreDragButton(lift: DragLift): boolean
	local button = lift.button
	if not button then
		cleanupDragPlaceholder(lift)
		return false
	end

	local parent = lift.parent
	if not parent or not parent.Parent then
		cleanupDragPlaceholder(lift)
		if button.Parent then
			button:Destroy()
		end
		return false
	end

	local ok = pcall(function()
		button.Parent = parent
		button.AnchorPoint = lift.originalAnchorPoint
		button.AutomaticSize = lift.originalAutomaticSize
		button.LayoutOrder = lift.originalLayoutOrder
		button.Position = lift.originalPosition
		button.Size = lift.originalSize
		button.ZIndex = lift.originalZIndex
	end)
	cleanupDragPlaceholder(lift)
	if not ok and button.Parent then
		button:Destroy()
	end
	return ok
end

function InventoryDragController.new(deps: {
		root: ScreenGui,
		hotbarWrapper: Frame,
		backpackScroll: ScrollingFrame?,
		getHotbarSlots: () -> { HotbarSlotViewModel },
		getBackpackSlots: () -> { HotbarSlotViewModel },
		onReorderHotbar: (string, number) -> (),
		onAssignToHotbar: (string, number) -> boolean,
		onRemoveFromHotbar: (string) -> (),
		onEquip: (string) -> (),
		onUnequipAll: (() -> ())?,
		onSnapshotOrder: (() -> { string })?,
		onRestoreOrder: (({ string }) -> ())?,
		onHotbarPreview: (({ HotbarSlotViewModel }) -> ())?,
		onHotbarAssignRejected: (() -> ())?,
	}): any
		local self = setmetatable({}, InventoryDragController)

		self._root = deps.root
		self._hotbarWrapper = deps.hotbarWrapper
		self._backpackScroll = deps.backpackScroll
		self._getHotbarSlots = deps.getHotbarSlots
		self._getBackpackSlots = deps.getBackpackSlots
		self._onReorderHotbar = deps.onReorderHotbar
		self._onAssignToHotbar = deps.onAssignToHotbar
		self._onRemoveFromHotbar = deps.onRemoveFromHotbar
		self._onEquip = deps.onEquip
		self._onUnequipAll = deps.onUnequipAll
		self._onSnapshotOrder = deps.onSnapshotOrder
		self._onRestoreOrder = deps.onRestoreOrder
		self._onHotbarPreview = deps.onHotbarPreview
		self._onHotbarAssignRejected = deps.onHotbarAssignRejected

		self._hotbarSlots = {} :: { SlotRefs }
		self._backpackCells = {} :: { BackpackCell }
		self._connections = {} :: { RBXScriptConnection }
		self._dragState = nil :: DragState?
		self._dragOverlay = nil :: ScreenGui?
		self._dragPreviewSlots = nil :: { HotbarSlotViewModel }?
		self._boundButtons = {} :: { [GuiButton]: boolean }
		self._onDragEndedCallbacks = {} :: { () -> () }
		self._touchStepConn = nil :: RBXScriptConnection?
		self._isBackpackOpen = false

		self:_connectGlobalInput()

		return self
	end

function InventoryDragController:setBackpackOpen(isOpen: boolean): ()
	if self._isBackpackOpen == isOpen then
		return
	end
	self._isBackpackOpen = isOpen

	if isOpen then
		-- Entering reorder mode: cancel any active drag, unequip all tools
		if self._dragState then
			self:_cancelDragSilently()
		end
		if self._onUnequipAll then
			self._onUnequipAll()
		end
	end
end

function InventoryDragController:setHotbarPreviewCallback(callback: (({ HotbarSlotViewModel }) -> ())?): ()
	self._onHotbarPreview = callback
end

function InventoryDragController:_track(connection: RBXScriptConnection): ()
	table.insert(self._connections, connection)
end

function InventoryDragController:_getDragOverlay(): ScreenGui
	if self._dragOverlay then
		return self._dragOverlay
	end

	local overlay = Instance.new("ScreenGui")
	overlay.Name = Config.Hotbar.DRAG_OVERLAY_NAME
	overlay.DisplayOrder = self._root.DisplayOrder + Config.Hotbar.DRAG_OVERLAY_DISPLAY_ORDER_OFFSET
	overlay.IgnoreGuiInset = false
	overlay.ResetOnSpawn = false
	overlay.ZIndexBehavior = self._root.ZIndexBehavior
	overlay.Parent = self._root.Parent
	self._dragOverlay = overlay

	return overlay
end

function InventoryDragController:setDragEndedCallback(callback: (() -> ())?): ()
	if not callback then
		return
	end
	table.insert(self._onDragEndedCallbacks, callback)
end

function InventoryDragController:_notifyDragEnded(): ()
	for _, callback in ipairs(self._onDragEndedCallbacks) do
		callback()
	end
end

function InventoryDragController:hasActiveDragSession(): boolean
	return self._dragState ~= nil
end

function InventoryDragController:_disposeDragLift(dragState: DragState): ()
	self:_restoreBackpackScroll(dragState)
	self:_disconnectTouchStepLoop()
	local lift = dragState.lift
	if lift then
		restoreDragButton(lift)
		dragState.lift = nil
	end
	local preserveButton = if lift then lift.button else nil
	sweepDragArtifacts(self._hotbarWrapper, self._dragOverlay, preserveButton, self._backpackScroll)
end

function InventoryDragController:sweepArtifacts(): ()
	local preserveButton = if self._dragState and self._dragState.lift then self._dragState.lift.button else nil
	sweepDragArtifacts(self._hotbarWrapper, self._dragOverlay, preserveButton, self._backpackScroll)
end

function InventoryDragController:_resolveDragPosition(dragState: DragState, input: InputObject?): Vector2
	if dragState.startedWithTouch then
		if dragState.activeTouch then
			dragState.lastPosition = getAbsoluteScreenPointer(dragState.activeTouch)
		end
	elseif input then
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.MouseMovement or inputType == Enum.UserInputType.MouseButton1 then
			dragState.lastPosition = getAbsoluteScreenPointer(input)
		end
	end
	return dragState.lastPosition
end

function InventoryDragController:_restoreBackpackScroll(dragState: DragState?): ()
	if not dragState or dragState.scrollWasEnabled == nil or not self._backpackScroll then
		return
	end
	self._backpackScroll.ScrollingEnabled = dragState.scrollWasEnabled
	dragState.scrollWasEnabled = nil
end

function InventoryDragController:_findBackpackViewModel(toolKey: string): HotbarSlotViewModel?
	for _, viewModel in ipairs(self._getBackpackSlots()) do
		if viewModel.toolKey == toolKey then
			return viewModel
		end
	end
	return nil
end

function InventoryDragController:_buildHotbarAssignPreview(toolKey: string, targetIndex: number): { HotbarSlotViewModel }
	local preview = table.clone(self._getHotbarSlots())
	for index = #preview, 1, -1 do
		if preview[index].toolKey == toolKey then
			table.remove(preview, index)
		end
	end

	local sourceViewModel = self:_findBackpackViewModel(toolKey)
	if not sourceViewModel then
		return self._getHotbarSlots()
	end

	local insertIndex = math.clamp(targetIndex, 1, #preview + 1)
	local inserted = table.clone(sourceViewModel)
	inserted.index = insertIndex
	inserted.slotId = tostring(insertIndex)
	table.insert(preview, insertIndex, inserted)

	for index, viewModel in ipairs(preview) do
		local clone = table.clone(viewModel)
		clone.index = index
		clone.slotId = tostring(index)
		preview[index] = clone
	end

	return preview
end

function InventoryDragController:_setHotbarPreview(slots: { HotbarSlotViewModel }): ()
	if self._onHotbarPreview then
		self._onHotbarPreview(slots)
	end
end

function InventoryDragController:_ensureTouchStepLoop(): ()
	if self._touchStepConn then
		return
	end
	self._touchStepConn = RunService.RenderStepped:Connect(function()
		local dragState = self._dragState
		if not dragState or not dragState.startedWithTouch or not dragState.isDragging or not dragState.lift then
			return
		end

		self:_resolveDragPosition(dragState, nil)
		local liftedButton = dragState.lift.button
		if liftedButton and liftedButton.Parent then
			local center = screenCenterForDrag(dragState.lastPosition, dragState.screenGrabOffset)
			liftedButton.Position = UDim2.fromOffset(center.X, center.Y)
			self:_updateDragPreview(dragState)
		end
	end)
end

function InventoryDragController:_disconnectTouchStepLoop(): ()
	if self._touchStepConn then
		self._touchStepConn:Disconnect()
		self._touchStepConn = nil
	end
end

function InventoryDragController:_revertOrderIfNeeded(dragState: DragState, committed: boolean): ()
	if committed or dragState.source ~= "hotbar" then
		return
	end
	if not dragState.orderSnapshot or not self._onRestoreOrder then
		return
	end
	self._onRestoreOrder(dragState.orderSnapshot)
end

function InventoryDragController:_finishDragSession(): ()
	self._dragState = nil
	self._dragPreviewSlots = nil
	if self._onHotbarPreview then
		self._onHotbarPreview(self._getHotbarSlots())
	end
	self:_notifyDragEnded()
end

function InventoryDragController:_cancelDragSilently(): ()
	local dragState = self._dragState
	if not dragState then
		return
	end

	self:_revertOrderIfNeeded(dragState, false)
	self:_disposeDragLift(dragState)
	self:_finishDragSession()
end

function InventoryDragController:setHotbarSlots(slots: { SlotRefs }): ()
	if self._dragState then
		self:_cancelDragSilently()
	end
	sweepDragArtifacts(self._hotbarWrapper, self._dragOverlay, nil, self._backpackScroll)
	self:_rebindHotbarSlots(slots)
end

function InventoryDragController:setBackpackCells(cells: { BackpackCell }): ()
	local dragState = self._dragState
	if dragState and dragState.source == "backpack" and dragState.isDragging then
		self:_rebindBackpackCells(cells)
		return
	end
	if dragState then
		self:_cancelDragSilently()
	end
	self:_rebindBackpackCells(cells)
end

function InventoryDragController:onBackpackGridRebuilding(): ()
	local dragState = self._dragState
	if dragState and dragState.source == "backpack" and dragState.isDragging then
		return
	end
	if dragState then
		self:_cancelDragSilently()
	end
end

function InventoryDragController:_findHotbarButton(toolKey: string): GuiButton?
	for _, refs in ipairs(self._hotbarSlots) do
		local vm = self:_viewModelForHotbarButton(refs.button)
		if vm and vm.toolKey == toolKey then
			return refs.button
		end
	end
	return nil
end

function InventoryDragController:_findBackpackButton(toolKey: string): GuiButton?
	for _, cell in ipairs(self._backpackCells) do
		if cell.toolKey == toolKey then
			return cell.refs.button
		end
	end
	return nil
end

function InventoryDragController:_viewModelForHotbarButton(button: GuiButton): HotbarSlotViewModel?
	local toolKey = button:GetAttribute(TOOL_KEY_ATTRIBUTE)
	if type(toolKey) ~= "string" or toolKey == "" then
		return nil
	end
	return findHotbarViewModel(self._getHotbarSlots(), toolKey)
end

function InventoryDragController:_hotbarInsertionIndex(mousePosition: Vector2, excludedToolKey: string): number?
	local candidates = {} :: { { centerX: number } }
	local slots = self._getHotbarSlots()
	for index, refs in ipairs(self._hotbarSlots) do
		local vm = slots[index]
		if not vm or not vm.toolKey or vm.toolKey == excludedToolKey then
			continue
		end
		if not refs.button.Visible then
			continue
		end

		local position = refs.button.AbsolutePosition
		local size = refs.button.AbsoluteSize
		table.insert(candidates, {
			centerX = position.X + (size.X * 0.5),
		})
	end

	table.sort(candidates, function(left, right)
		return left.centerX < right.centerX
	end)

	if #candidates == 0 then
		return 1
	end

	for index, candidate in ipairs(candidates) do
		if mousePosition.X < candidate.centerX then
			return index
		end
	end

	return #candidates + 1
end

function InventoryDragController:_backpackInsertionIndex(mousePosition: Vector2): number?
	if not self._backpackScroll then
		return nil
	end

	local bestIndex = nil :: number?
	local bestDistance = math.huge

	for index, cell in ipairs(self._backpackCells) do
		if not cell.toolKey or not cell.refs.button.Visible then
			continue
		end

		local position = cell.refs.button.AbsolutePosition
		local size = cell.refs.button.AbsoluteSize
		local center = position + size / 2
		local distance = (center - mousePosition).Magnitude
		if distance < bestDistance then
			bestDistance = distance
			bestIndex = index
		end
	end

	return bestIndex
end

function InventoryDragController:_isOverHotbar(mousePosition: Vector2): boolean
	local position = self._hotbarWrapper.AbsolutePosition
	local size = self._hotbarWrapper.AbsoluteSize
	return mousePosition.X >= position.X
		and mousePosition.X <= position.X + size.X
		and mousePosition.Y >= position.Y
		and mousePosition.Y <= position.Y + size.Y
end

function InventoryDragController:_isOverBackpack(mousePosition: Vector2): boolean
	if not self._backpackScroll then
		return false
	end
	local position = self._backpackScroll.AbsolutePosition
	local size = self._backpackScroll.AbsoluteSize
	return mousePosition.X >= position.X
		and mousePosition.X <= position.X + size.X
		and mousePosition.Y >= position.Y
		and mousePosition.Y <= position.Y + size.Y
end

function InventoryDragController:_movePreviewSlot(
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

function InventoryDragController:_updateDragPreview(dragState: DragState): ()
	local dragPosition = dragState.lastPosition

	if self:_isOverHotbar(dragPosition) then
		local targetIndex = self:_hotbarInsertionIndex(dragPosition, dragState.toolKey)
		if targetIndex and dragState.lift then
			dragState.currentHotbarIndex = targetIndex
			dragState.currentBackpackIndex = nil
			local visibleCount = countVisibleHotbarTools(self, dragState.toolKey)
			dragState.lift.placeholder.Parent = self._hotbarWrapper
			dragState.lift.placeholder.LayoutOrder =
				clampedHotbarPlaceholderOrder(targetIndex, visibleCount)
			setPlaceholderVisible(dragState.lift, true)

			if dragState.source == "hotbar" then
				self._dragPreviewSlots = self:_movePreviewSlot(
					self._dragPreviewSlots or self._getHotbarSlots(),
					dragState.toolKey,
					targetIndex
				)
				self:_setHotbarPreview(self._dragPreviewSlots)
			elseif dragState.source == "backpack" then
				self:_setHotbarPreview(self:_buildHotbarAssignPreview(dragState.toolKey, targetIndex))
			end
		end
		return
	end

	if dragState.source == "backpack" and dragState.isDragging then
		self:_setHotbarPreview(self._getHotbarSlots())
	end

	if self:_isOverBackpack(dragPosition) and dragState.lift and self._backpackScroll then
		local targetIndex = self:_backpackInsertionIndex(dragPosition)
		dragState.currentBackpackIndex = targetIndex
		dragState.currentHotbarIndex = nil
		if targetIndex then
			local cell = self._backpackCells[targetIndex]
			if cell then
				dragState.lift.placeholder.Parent = cell.refs.button.Parent
				dragState.lift.placeholder.LayoutOrder = cell.refs.button.LayoutOrder
				setPlaceholderVisible(dragState.lift, true)
			end
		end
		return
	end

	if dragState.lift then
		setPlaceholderVisible(dragState.lift, false)
	end
end

function InventoryDragController:_commitDrag(dragState: DragState): boolean
	local dragPosition = dragState.lastPosition

	if self:_isOverHotbar(dragPosition) then
		local targetIndex = dragState.currentHotbarIndex
			or self:_hotbarInsertionIndex(dragPosition, dragState.toolKey)
		if not targetIndex then
			return false
		end

		if dragState.source == "hotbar" then
			self._onReorderHotbar(dragState.toolKey, targetIndex)
			return true
		end
		local assigned = self._onAssignToHotbar(dragState.toolKey, targetIndex)
		if not assigned and self._onHotbarAssignRejected then
			self._onHotbarAssignRejected()
		end
		return assigned
	end

	if self:_isOverBackpack(dragPosition) and dragState.source == "hotbar" then
		self._onRemoveFromHotbar(dragState.toolKey)
		return true
	end

	return false
end

function InventoryDragController:_beginDrag(
	source: DragSource,
	toolKey: string,
	button: GuiButton,
	hotbarIndex: number?,
	backpackIndex: number?,
	startPosition: Vector2,
	startedWithTouch: boolean,
	beginInput: InputObject?
): ()
	if self._dragState then
		self:_cancelDragSilently()
	end

	local orderSnapshot = if source == "hotbar" and self._onSnapshotOrder
		then self._onSnapshotOrder()
		else nil
	local lastPosition = getAbsoluteScreenPointer(beginInput)
	local activeTouch = if startedWithTouch
		and beginInput
		and beginInput.UserInputType == Enum.UserInputType.Touch
		then beginInput
		else nil
	self._dragState = {
		source = source,
		toolKey = toolKey,
		currentHotbarIndex = hotbarIndex,
		currentBackpackIndex = backpackIndex,
		startPosition = lastPosition,
		lastPosition = lastPosition,
		screenGrabOffset = Vector2.zero,
		startedWithTouch = startedWithTouch,
		activeTouch = activeTouch,
		isDragging = false,
		lift = nil,
		orderSnapshot = orderSnapshot,
		scrollWasEnabled = nil,
	}
	if source == "backpack" and self._backpackScroll then
		self._dragState.scrollWasEnabled = self._backpackScroll.ScrollingEnabled
		self._backpackScroll.ScrollingEnabled = false
	end
	self._dragPreviewSlots = if source == "hotbar" then table.clone(self._getHotbarSlots()) else nil
end

function InventoryDragController:_rebindHotbarSlots(slots: { SlotRefs }): ()
	self._hotbarSlots = slots
end

function InventoryDragController:_rebindBackpackCells(cells: { BackpackCell }): ()
	self._backpackCells = cells
end

function InventoryDragController:_connectGlobalInput(): ()
	local dragEnabled = Config.Hotbar.INVENTORY_DRAG_ENABLED == true
		or Config.Hotbar.DRAG_REORDER_ENABLED == true
	if not dragEnabled then
		return
	end

	self:_track(UserInputService.InputChanged:Connect(function(input: InputObject)
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
		if dragState.startedWithTouch then
			if input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			if dragState.activeTouch and input ~= dragState.activeTouch then
				return
			end
		end

		local dragPosition = self:_resolveDragPosition(dragState, input)
		local distance = (dragPosition - dragState.startPosition).Magnitude
		if distance >= Config.Hotbar.DRAG_START_THRESHOLD then
			dragState.isDragging = true
			if not dragState.lift then
				local button = if dragState.source == "hotbar"
					then self:_findHotbarButton(dragState.toolKey)
					else self:_findBackpackButton(dragState.toolKey)
				if not button or not button.Parent then
					self:_cancelDragSilently()
					return
				end
				sweepDragArtifacts(self._hotbarWrapper, self._dragOverlay, nil, self._backpackScroll)
				local buttonCenter = button.AbsolutePosition + (button.AbsoluteSize / 2)
				dragState.screenGrabOffset = dragPosition - buttonCenter
				local liftCenter = screenCenterForDrag(dragPosition, dragState.screenGrabOffset)
				dragState.lift = liftDragButton(button, liftCenter, self:_getDragOverlay())
				if dragState.startedWithTouch then
					self:_ensureTouchStepLoop()
				end
			end
		end

		if dragState.lift and not dragState.startedWithTouch then
			local liftedButton = dragState.lift.button
			if not liftedButton or not liftedButton.Parent then
				self:_cancelDragSilently()
				return
			end
			local center = screenCenterForDrag(dragPosition, dragState.screenGrabOffset)
			liftedButton.Position = UDim2.fromOffset(center.X, center.Y)
			self:_updateDragPreview(dragState)
		end
	end))

	self:_track(UserInputService.WindowFocusReleased:Connect(function()
		if self._dragState then
			self:_cancelDragSilently()
		end
	end))

	self:_track(UserInputService.InputEnded:Connect(function(input: InputObject)
		local dragState = self._dragState
		if not dragState then
			return
		end
		if not isDragEndInput(input, dragState) then
			return
		end

		-- For touch, only end if it's the specific touch that started the drag.
		-- Prevents accidental cancellation from other touches (palm, second finger, etc.).
		if dragState.startedWithTouch and dragState.activeTouch and input ~= dragState.activeTouch then
			return
		end

		self:_resolveDragPosition(dragState, input)

		if not dragState.isDragging then
			self:_restoreBackpackScroll(dragState)
			if self._isBackpackOpen then
				-- Reorder mode: tap = move between hotbar and backpack
				if dragState.source == "hotbar" then
					self._onRemoveFromHotbar(dragState.toolKey)
				elseif dragState.source == "backpack" then
					local targetIndex = #self._getHotbarSlots() + 1
					self._onAssignToHotbar(dragState.toolKey, targetIndex)
				end
			else
				self._onEquip(dragState.toolKey)
			end
			self:_finishDragSession()
			return
		end

		if dragState.lift and (not dragState.lift.button or not dragState.lift.button.Parent) then
			self:_cancelDragSilently()
			return
		end

		local committed = self:_commitDrag(dragState)
		if not committed then
			self:_revertOrderIfNeeded(dragState, false)
		end
		self:_disposeDragLift(dragState)
		self:_finishDragSession()
	end))
end

function InventoryDragController:bindHotbarSlot(refs: SlotRefs, index: number): ()
	local dragEnabled = Config.Hotbar.INVENTORY_DRAG_ENABLED == true
		or Config.Hotbar.DRAG_REORDER_ENABLED == true
	if not dragEnabled then
		return
	end
	if refs.button.Name == Config.Hotbar.BACKPACK_BUTTON_NAME then
		return
	end
	if self._boundButtons[refs.button] then
		return
	end
	self._boundButtons[refs.button] = true

	-- Disable native UIDragDetector so our custom drag logic is the only handler
	if refs.dragDetector then
		refs.dragDetector.Enabled = false
	end

	self:_track(refs.button.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		local toolKey = refs.button:GetAttribute(TOOL_KEY_ATTRIBUTE)
		if type(toolKey) ~= "string" or toolKey == "" then
			return
		end
		local viewModel = findHotbarViewModel(self._getHotbarSlots(), toolKey)
		if not viewModel or viewModel.isEmpty then
			return
		end

		local startedWithTouch = input.UserInputType == Enum.UserInputType.Touch
		local startPosition = getAbsoluteScreenPointer(input)
		self:_beginDrag(
			"hotbar",
			viewModel.toolKey,
			refs.button,
			viewModel.index,
			nil,
			startPosition,
			startedWithTouch,
			input
		)
	end))
end

function InventoryDragController:bindBackpackCell(cell: BackpackCell, index: number): ()
	local dragEnabled = Config.Hotbar.INVENTORY_DRAG_ENABLED == true
		or Config.Hotbar.DRAG_REORDER_ENABLED == true
	if not dragEnabled or not cell.toolKey then
		return
	end
	if self._boundButtons[cell.refs.button] then
		return
	end
	self._boundButtons[cell.refs.button] = true

	-- Disable native UIDragDetector so our custom drag logic is the only handler
	if cell.refs.dragDetector then
		cell.refs.dragDetector.Enabled = false
	end

	self:_track(cell.refs.button.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		if not cell.toolKey then
			return
		end

		local startedWithTouch = input.UserInputType == Enum.UserInputType.Touch
		local startPosition = getAbsoluteScreenPointer(input)
		self:_beginDrag(
			"backpack",
			cell.toolKey,
			cell.refs.button,
			nil,
			index,
			startPosition,
			startedWithTouch,
			input
		)
	end))
end

function InventoryDragController:getDragPreviewSlots(): { HotbarSlotViewModel }?
	return self._dragPreviewSlots
end

function InventoryDragController:isDragging(): boolean
	return self._dragState ~= nil and self._dragState.isDragging == true
end

function InventoryDragController:getActiveDragToolKey(): string?
	if self._dragState and self._dragState.isDragging then
		return self._dragState.toolKey
	end
	return nil
end

function InventoryDragController:destroy(): ()
	if self._dragState then
		self:_revertOrderIfNeeded(self._dragState, false)
		self:_disposeDragLift(self._dragState)
	end
	self._dragState = nil
	sweepDragArtifacts(self._hotbarWrapper, self._dragOverlay, nil, self._backpackScroll)

	self:_disconnectTouchStepLoop()

	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)

	if self._dragOverlay then
		self._dragOverlay:Destroy()
		self._dragOverlay = nil
	end
end

return InventoryDragController
