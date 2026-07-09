--!strict

local function createStore(initialState: { [string]: any })
	local state = table.freeze(table.clone(initialState))
	local subscribers: { [string]: { (any, any) -> () } } = {}
	local store = {}

	function store:get()
		return state
	end

	function store:set(changes: { [string]: any })
		local previous = state
		local nextState = table.clone(state :: any)
		for key, value in pairs(changes) do
			nextState[key] = value
		end
		state = table.freeze(nextState)

		for key, callbacks in pairs(subscribers) do
			if (previous :: any)[key] ~= (state :: any)[key] then
				for _, callback in ipairs(callbacks) do
					task.spawn(callback, (state :: any)[key], (previous :: any)[key])
				end
			end
		end
	end

	function store:subscribe(key: string, callback: (any, any) -> ())
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
	isOpen = false,
	rawInput = "/",
	normalizedQuery = "",
	visibleCommands = {},
	bestSuggestion = nil,
	isMobile = false,
	canExecute = false,
	transientClickedId = nil,
})
