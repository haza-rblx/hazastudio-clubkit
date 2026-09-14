--!strict
-- BackpackUIBinder (UI): backpack grid; pairs with HotbarUIBinder via InventoryDragController.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BackpackGuiRefs = require(script.Parent.BackpackGuiRefs)
local MobilePanelManager = require(script.Parent.Parent.Services.MobilePanelManager)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local InventoryStore = require(script.Parent.Parent.State.InventoryStore)
local InventoryDragController = require(script.Parent.InventoryDragController)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local UIMotion = require(script.Parent.Parent.Utils.UIMotion)

type HotbarSlotViewModel = InventoryStore.HotbarSlotViewModel
type Refs = BackpackGuiRefs.Refs
type ILogger = Types.ILogger

type CellEntry = {
	button: GuiButton,
	toolKey: string?,
	connections: { RBXScriptConnection },
}

local BackpackUIBinder = {}
BackpackUIBinder.__index = BackpackUIBinder

local function renderToolOnButton(
	button: GuiButton,
	viewModel: HotbarSlotViewModel,
	equippedTransparency: number
): ()
	button.Visible = true
	button.BackgroundTransparency = 1

	if viewModel.isEquipped then
		-- Cells are rebuilt on every render, so the equipped highlight fades in on the fresh
		-- cell rather than tweening between two states it never sees.
		button.BackgroundColor3 = Config.Hotbar.EQUIPPED_BACKGROUND_COLOR
		UIMotion.tween(button, 0.22, { BackgroundTransparency = equippedTransparency })
	end

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
	self._wasOpen = false

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
		for _, connection in ipairs(cell.connections) do
			connection:Disconnect()
		end
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
	-- Rows cascade in when the panel opens, never on the rebuilds that follow (drag flush,
	-- inventory echo) — those repaint the same grid and must stay still.
	local animateRows = isOpen and self._wasOpen ~= true
	self._wasOpen = isOpen

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
	local rows = {} :: { GuiObject }
	local bases = {} :: { [GuiObject]: number }
	-- The template's own cell background is the equipped highlight's resting value; a fully
	-- transparent template gets a light wash so the highlight is visible at all.
	local designedBackground = self._refs.itemTemplate.BackgroundTransparency
	local equippedTransparency = if designedBackground < 1 then designedBackground else 0.4

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

		renderToolOnButton(button, viewModel, equippedTransparency)

		local refs = BackpackGuiRefs.slotRefsFromButton(button)
		if refs.dragDetector then
			refs.dragDetector.Enabled = false
		end

		local connections = {} :: { RBXScriptConnection }
		-- Grid cells are laid out, so the squash must land on the cell's icon, never on a
		-- UIScale added to the cell itself.
		if not UIMotion.canScale(button) then
			for _, connection in ipairs(UIMotion.bindPress(button)) do
				table.insert(connections, connection)
			end
			for _, connection in ipairs(UIMotion.bindHover(button)) do
				table.insert(connections, connection)
			end
		end

		if animateRows then
			local elements = { button :: GuiObject }
			for _, descendant in ipairs(button:GetDescendants()) do
				if descendant:IsA("GuiObject") then
					table.insert(elements, descendant :: GuiObject)
				end
			end
			UIMotion.captureBases(elements, bases)
			table.insert(rows, button :: GuiObject)
		end

		table.insert(self._cells, {
			button = button,
			toolKey = viewModel.toolKey,
			connections = connections,
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

	if animateRows and #rows > 0 then
		UIMotion.stagger(rows, bases, 0.025, 16)
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
