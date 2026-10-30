--!strict
-- Studio-only test hook: a BindableFunction the parity checks drive (switch tabs, open views).
-- Features register small setters here; nothing is created outside Studio.
local RunService = game:GetService("RunService")

local Debug = {}

local handlers: { [string]: (...any) -> any } = {}

function Debug.on(name: string, fn: (...any) -> any)
	if RunService:IsStudio() then
		handlers[name] = fn
	end
end

function Debug.mount(parent: Instance)
	if not RunService:IsStudio() then
		return
	end
	local f = Instance.new("BindableFunction")
	f.Name = "CosmicDJ_Test"
	f.OnInvoke = function(name: string, ...)
		local h = handlers[name]
		if not h then
			return "no handler " .. tostring(name)
		end
		return h(...)
	end
	f.Parent = parent
end

return Debug
