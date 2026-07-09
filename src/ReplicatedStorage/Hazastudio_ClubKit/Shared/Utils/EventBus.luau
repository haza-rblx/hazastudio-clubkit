--!strict

local EventBus = {}
EventBus.__index = EventBus

export type Subscription = () -> ()

export type EventBus = {
	on: (self: EventBus, eventName: string, callback: (any) -> ()) -> Subscription,
	emit: (self: EventBus, eventName: string, payload: any) -> (),
}

function EventBus.new(): EventBus
	local self = setmetatable({}, EventBus)
	self._listeners = {} :: {[string]: {(any) -> ()}}
	return (self :: any) :: EventBus
end

function EventBus:on(eventName: string, callback: (any) -> ()): Subscription
	local listeners = (self :: any)._listeners
	listeners[eventName] = listeners[eventName] or {}
	table.insert(listeners[eventName], callback)

	return function()
		local existing = listeners[eventName]
		if not existing then
			return
		end
		for index, registered in ipairs(existing) do
			if registered == callback then
				table.remove(existing, index)
				break
			end
		end
	end
end

function EventBus:emit(eventName: string, payload: any)
	local listeners = ((self :: any)._listeners :: {[string]: {(any) -> ()}})[eventName]
	if not listeners or #listeners == 0 then
		return
	end

	-- Clone before iterating: prevents skipped/double-fired callbacks
	-- when a listener unsubscribes mid-emit via task.spawn re-entrancy.
	local snapshot = table.clone(listeners)
	for _, callback in ipairs(snapshot) do
		task.spawn(callback, payload)
	end
end

return EventBus
