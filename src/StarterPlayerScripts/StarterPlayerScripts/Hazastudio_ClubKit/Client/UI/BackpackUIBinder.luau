--!strict
-- BackpackUIBinder (UI): backpack grid; pairs with HotbarUIBinder via InventoryDragController.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BackpackGuiRefs = require(script.Parent.BackpackGuiRefs)
local MobilePanelManager = require(script.Parent.Parent.Services.MobilePanelManager)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local InventoryStore = require(script.Parent.Parent.State.InventoryStore)
local InventoryDragController = require(script.Parent.InventoryDragController)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)

type HotbarSlotViewModel = InventoryStore.HotbarSlotViewModel
type Refs = BackpackGuiRefs.Refs
type ILogger = Types.ILogger

type CellEntry = {
	button: GuiButton,
	toolKey: string?,
}

local BackpackUIBinder = {}
BackpackUIBinder.__index = BackpackUIBinder

local function renderToolOnButton(button: GuiButton, viewModel: HotbarSlotViewModel): ()
	button.Visible = true
	button.BackgroundTransparency = 1

	local imageLabel = button:FindFirstChildWhichIsA("ImageLabel", true)
	if imageLabel and imageLabel:IsA("ImageLabel") then
		imageLabel.Image = viewModel.iconAsset
		imageLabel.Visible = viewModel.iconAsset ~= ""
	end

	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			descendant.Text = viewModel.displayName
			descendant.Visible = false
		end
	end
end

function BackpackUIBinder.new(deps: {
	refs: Refs,
	store: any,
	logger: ILogger,
	inventoryDrag: any?,
}): any
	local self = setmetatable({}, BackpackUIBinder)

	self._refs = deps.refs
	self._store = deps.store
	self._log = deps.logger
	self._inventoryDrag = deps.inventoryDrag
	self._cells = {} :: { CellEntry }
	self._unsubscribers = {} :: { () -> () }
	self._pendingSlots = nil :: { HotbarSlotViewModel }?
	self._pendingOpen = nil :: boolean?

	self._refs.itemTemplate.Visible = false
	self._refs.wrapper.Visible = false
	self._refs.root.Enabled = true

	self:_subscribeStore()

	if deps.inventoryDrag and type(deps.inventoryDrag.setDragEndedCallback) == "function" then
		deps.inventoryDrag:setDragEndedCallback(function()
			self:flushPendingRender()
		end)
	end

	local initial = self._store:get()
	MobilePanelManager.setBackpackOpen(initial.isBackpackOpen)
	self:_render(initial.backpackSlots, initial.isBackpackOpen, initial.inventoryChromeHidden == true)

	return self
end

function BackpackUIBinder:flushPendingRender(): ()
	if not self._pendingSlots then
		return
	end
	local slots = self._pendingSlots
	local isOpen = self._pendingOpen == true
	self._pendingSlots = nil
	self._pendingOpen = nil
	self:_renderNow(slots, isOpen)
end

function BackpackUIBinder:_trackUnsubscriber(unsubscribe: () -> ()): ()
	table.insert(self._unsubscribers, unsubscribe)
end

function BackpackUIBinder:_clearCells(): ()
	for _, cell in ipairs(self._cells) do
		if cell.button and cell.button.Parent then
			cell.button:Destroy()
		end
	end
	table.clear(self._cells)
end

function BackpackUIBinder:_subscribeStore(): ()
	self:_trackUnsubscriber(self._store:subscribe("backpackSlots", function(slots: { HotbarSlotViewModel })
		local state = self._store:get()
		self:_render(slots, state.isBackpackOpen, state.inventoryChromeHidden == true)
	end))

	self:_trackUnsubscriber(self._store:subscribe("isBackpackOpen", function(isOpen: boolean)
		MobilePanelManager.setBackpackOpen(isOpen)
		local state = self._store:get()
		self:_render(state.backpackSlots, isOpen, state.inventoryChromeHidden == true)
	end))

	self:_trackUnsubscriber(self._store:subscribe("inventoryChromeHidden", function(chromeHidden: boolean)
		local state = self._store:get()
		self:_render(state.backpackSlots, state.isBackpackOpen, chromeHidden == true)
	end))
end

function BackpackUIBinder:_render(slots: { HotbarSlotViewModel }, isOpen: boolean, chromeHidden: boolean?): ()
	local effectiveOpen = isOpen and chromeHidden ~= true
	self._refs.root.Enabled = true
	if effectiveOpen then
		self._refs.root.DisplayOrder = Config.Hotbar.DISPLAY_ORDER + 2
	else
		self._refs.root.DisplayOrder = Config.Hotbar.DISPLAY_ORDER
	end
	if self._inventoryDrag and self._inventoryDrag:hasActiveDragSession() then
		self._pendingSlots = slots
		self._pendingOpen = isOpen
		return
	end

	self:_renderNow(slots, isOpen)
end

function BackpackUIBinder:_renderNow(slots: { HotbarSlotViewModel }, isOpen: boolean): ()
	if not isOpen then
		if self._inventoryDrag then
			self._inventoryDrag:onBackpackGridRebuilding()
		end
		return
	end

	if self._inventoryDrag then
		self._inventoryDrag:onBackpackGridRebuilding()
	end
	self:_clearCells()

	local maxSlots = math.max(1, math.floor(tonumber(Config.Backpack.MAX_GRID_SLOTS) or 48))
	local limit = math.min(#slots, maxSlots)
	local dragCells = {} :: { any }

	for index = 1, limit do
		local viewModel = slots[index]
		if not viewModel or not viewModel.toolKey then
			continue
		end

		local button = self._refs.itemTemplate:Clone() :: GuiButton
		button.Name = "BackpackItem_" .. viewModel.toolKey
		button.LayoutOrder = index
		button.Visible = true
		button.Parent = self._refs.scrollFrame

		renderToolOnButton(button, viewModel)

		local refs = BackpackGuiRefs.slotRefsFromButton(button)
		if refs.dragDetector then
			refs.dragDetector.Enabled = false
		end

		table.insert(self._cells, {
			button = button,
			toolKey = viewModel.toolKey,
		})

		table.insert(dragCells, {
			refs = refs,
			toolKey = viewModel.toolKey,
		})

		if self._inventoryDrag then
			self._inventoryDrag:bindBackpackCell(dragCells[#dragCells], index)
		end
	end

	if self._inventoryDrag then
		self._inventoryDrag:setBackpackCells(dragCells)
	end
end

function BackpackUIBinder:destroy(): ()
	self:_clearCells()

	for _, unsubscribe in ipairs(self._unsubscribers) do
		unsubscribe()
	end
	table.clear(self._unsubscribers)
end

return BackpackUIBinder
