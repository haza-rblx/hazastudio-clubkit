--!strict
-- Shared/Utils/Lifecycle.lua

local Types = require(script.Parent.Parent.Domain.Types)

type ILogger = Types.ILogger

type LifecycleEntry = {
	name: string,
	module: any,
}

export type LifecycleRegistry = {
	register: (self: LifecycleRegistry, name: string, module: any) -> any,
	initAll: (self: LifecycleRegistry) -> (),
	startAll: (self: LifecycleRegistry) -> (),
	destroyAll: (self: LifecycleRegistry) -> (),
	size: (self: LifecycleRegistry) -> number,
}

local Lifecycle = {}
Lifecycle.__index = Lifecycle

local function callMethod(logger: ILogger?, entry: LifecycleEntry, methodName: string)
	local method = entry.module[methodName]
	if type(method) ~= "function" then
		return
	end

	local ok, err = xpcall(function()
		method(entry.module)
	end, debug.traceback)

	if not ok and logger then
		logger:error("Lifecycle method failed", {
			module = entry.name,
			method = methodName,
			error = tostring(err),
		})
	end
end

function Lifecycle.new(logger: ILogger?): LifecycleRegistry
	local self = setmetatable({
		_entries = {} :: { LifecycleEntry },
		_logger = logger,
	}, Lifecycle)

	return (self :: any) :: LifecycleRegistry
end

function Lifecycle:register(name: string, module: any): any
	if module == nil then
		return module
	end

	table.insert(self._entries, {
		name = name,
		module = module,
	})

	return module
end

function Lifecycle:initAll()
	for _, entry in ipairs(self._entries) do
		callMethod(self._logger, entry, "onInit")
	end
end

function Lifecycle:startAll()
	for _, entry in ipairs(self._entries) do
		callMethod(self._logger, entry, "onStart")
	end
end

function Lifecycle:destroyAll()
	for index = #self._entries, 1, -1 do
		local entry = self._entries[index]
		local hasOnDestroy = type(entry.module.onDestroy) == "function"
		if hasOnDestroy then
			callMethod(self._logger, entry, "onDestroy")
		else
			callMethod(self._logger, entry, "destroy")
		end
	end
	table.clear(self._entries)
end

function Lifecycle:size(): number
	return #self._entries
end

return Lifecycle
