--!strict

local RunService = game:GetService("RunService")
local SharedTick = require(script.Parent.SharedTick)

export type Connection = {
	Disconnect: (self: Connection) -> (),
}

local function connect(owner: any, tick: (dt: number) -> (), uiInstance: Instance): Connection
	local disconnected = false
	local legacyConnection: RBXScriptConnection? = nil

	if SharedTick.shouldUseShared() then
		SharedTick.register(owner, tick, uiInstance)
	else
		legacyConnection = RunService.Heartbeat:Connect(tick)
	end

	return {
		Disconnect = function()
			if disconnected then
				return
			end
			disconnected = true
			if legacyConnection then
				legacyConnection:Disconnect()
				legacyConnection = nil
			else
				SharedTick.unregister(owner)
			end
		end,
	}
end

return connect
