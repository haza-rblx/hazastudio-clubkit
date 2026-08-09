--!strict

local function createStore(initialState: { [string]: any })
	local state = table.freeze(table.clone(initialState))
	local subscribers: { [string]: { (any, any) -> () } } = {}
	local store = {}

	function store:get()
		return state
	end

	-- Luau cannot put nil into a table literal/assignment map — `pending = nil` is a
	-- no-op (key absent). Pass `_clear = { "pendingAnimationName", ... }` to assign nil.
	function store:set(changes: { [string]: any })
		local previous = state
		local nextState = table.clone(state :: any) :: { [string]: any }

		local clearList = (changes :: any)._clear
		if type(clearList) == "table" then
			for _, clearKey in ipairs(clearList) do
				if type(clearKey) == "string" then
					nextState[clearKey] = nil
				end
			end
		end

		-- Use next() so empty-string values are applied (pairs is fine too; next matches legacy).
		local key = next(changes)
		while key ~= nil do
			if key ~= "_clear" then
				nextState[key] = changes[key]
			end
			key = next(changes, key)
		end

		state = table.freeze(nextState)

		for subscriberKey, callbacks in pairs(subscribers) do
			if (previous :: any)[subscriberKey] ~= (state :: any)[subscriberKey] then
				for _, callback in ipairs(callbacks) do
					task.spawn(callback, (state :: any)[subscriberKey], (previous :: any)[subscriberKey])
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
	isSyncing = false,
	leaderName = nil,
	leaderDisplay = nil,
	currentAnim = nil,
	visualAnim = nil,
	currentSpeed = 1.0,
	favoritedAnims = {},
	isInputLocked = false,
	isPanelOpen = false,
	isDancePreparing = false,
	isDanceReady = false,
	pendingAnimationName = nil,
	pendingAnimationObject = nil,
	syncTargetUserId = nil,
})
