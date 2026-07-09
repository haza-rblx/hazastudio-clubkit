--!strict

export type CarryMode = "idle" | "selecting" | "waiting" | "pending" | "carrying"

type CarryState = {
	mode: CarryMode,
	selectedTargetUserId: number?,
	selectedTargetName: string?,
	pendingCarrierUserId: number?,
	pendingCarrierName: string?,
	pendingStyle: string?,
	partnerUserId: number?,
	partnerName: string?,
	currentStyle: string?,
	lastError: string?,
}

local initialState: CarryState = {
	mode = "idle",
	selectedTargetUserId = nil,
	selectedTargetName = nil,
	pendingCarrierUserId = nil,
	pendingCarrierName = nil,
	pendingStyle = nil,
	partnerUserId = nil,
	partnerName = nil,
	currentStyle = nil,
	lastError = nil,
}

local state = table.freeze(table.clone(initialState)) :: CarryState
local subscribers: { [string]: { (any, any) -> () } } = {}

local CarryStore = {}

function CarryStore:get(): CarryState
	return state
end

function CarryStore:set(changes: { [string]: any }): ()
	local previous = state
	local nextState = table.clone(state :: any)

	for key, value in pairs(changes) do
		nextState[key] = value
	end

	state = table.freeze(nextState) :: CarryState

	for key, callbacks in pairs(subscribers) do
		if (previous :: any)[key] ~= (state :: any)[key] then
			for _, callback in ipairs(callbacks) do
				task.spawn(callback, (state :: any)[key], (previous :: any)[key])
			end
		end
	end
end

function CarryStore:clear(keys: { string }): ()
	local previous = state
	local nextState = table.clone(state :: any)

	for _, key in ipairs(keys) do
		nextState[key] = nil
	end

	state = table.freeze(nextState) :: CarryState

	for key, callbacks in pairs(subscribers) do
		if (previous :: any)[key] ~= (state :: any)[key] then
			for _, callback in ipairs(callbacks) do
				task.spawn(callback, (state :: any)[key], (previous :: any)[key])
			end
		end
	end
end

function CarryStore:reset(): ()
	state = table.freeze(table.clone(initialState)) :: CarryState
	for key, callbacks in pairs(subscribers) do
		for _, callback in ipairs(callbacks) do
			task.spawn(callback, (state :: any)[key], nil)
		end
	end
end

function CarryStore:subscribe(key: string, callback: (any, any) -> ()): () -> ()
	subscribers[key] = subscribers[key] or {}
	table.insert(subscribers[key], callback)

	return function()
		local callbacks = subscribers[key]
		if callbacks == nil then
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

return CarryStore
