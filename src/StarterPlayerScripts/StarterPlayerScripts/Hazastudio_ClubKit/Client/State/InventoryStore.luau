--!strict

export type HotbarSlotViewModel = {
	slotId: string,
	index: number,
	toolKey: string?,
	displayName: string,
	iconAsset: string,
	isEquipped: boolean,
	isEmpty: boolean,
}

export type InventoryState = {
	hotbarSlots: { HotbarSlotViewModel },
	backpackSlots: { HotbarSlotViewModel },
	isBackpackOpen: boolean,
	inventoryChromeHidden: boolean,
	hasTools: boolean,
}

type Subscriber = (any, any) -> ()
type Store = {
	get: (self: Store) -> InventoryState,
	set: (self: Store, changes: { [string]: any }) -> (),
	subscribe: (self: Store, key: string, callback: Subscriber) -> () -> (),
}

local function cloneSlots(slots: { HotbarSlotViewModel }): { HotbarSlotViewModel }
	local nextSlots = {}
	for _, slot in ipairs(slots) do
		table.insert(nextSlots, table.freeze(table.clone(slot)))
	end
	return table.freeze(nextSlots)
end

local function createStore(initialState: InventoryState): Store
	local state = table.freeze({
		hotbarSlots = cloneSlots(initialState.hotbarSlots),
		backpackSlots = cloneSlots(initialState.backpackSlots),
		isBackpackOpen = initialState.isBackpackOpen,
		inventoryChromeHidden = initialState.inventoryChromeHidden,
		hasTools = initialState.hasTools,
	})
	local subscribers: { [string]: { Subscriber } } = {}
	local store = {} :: Store

	function store:get(): InventoryState
		return state
	end

	function store:set(changes: { [string]: any }): ()
		local previous = state
		local nextState = table.clone(state :: any)

		local key = next(changes)
		while key ~= nil do
			if key == "hotbarSlots" or key == "backpackSlots" then
				nextState[key] = cloneSlots(changes[key])
			else
				nextState[key] = changes[key]
			end
			key = next(changes, key)
		end

		state = table.freeze(nextState) :: InventoryState

		for subscriberKey, callbacks in pairs(subscribers) do
			if (previous :: any)[subscriberKey] ~= (state :: any)[subscriberKey] then
				for _, callback in ipairs(callbacks) do
					task.spawn(callback, (state :: any)[subscriberKey], (previous :: any)[subscriberKey])
				end
			end
		end
	end

	function store:subscribe(key: string, callback: Subscriber): () -> ()
		subscribers[key] = subscribers[key] or {}
		table.insert(subscribers[key], callback)

		return function()
			local callbacks = subscribers[key]
			if not callbacks then
				return
			end

			for index, existing in ipairs(callbacks) do
				if existing == callback then
					table.remove(callbacks, index)
					break
				end
			end
		end
	end

	return store
end

return createStore({
	hotbarSlots = {},
	backpackSlots = {},
	isBackpackOpen = false,
	inventoryChromeHidden = false,
	hasTools = false,
})
