--!strict
-- PATH: StarterPlayerScripts/Client/Controllers/NotifController.lua (ModuleScript)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger       = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local NotifService = require(script.Parent.Parent.Services.NotifService)

local log = Logger.new("NotifController")

local _connections: { RBXScriptConnection } = {}

local function track(conn: RBXScriptConnection): RBXScriptConnection
	table.insert(_connections, conn)
	return conn
end

local function destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)
end

export type Deps = {
	notifyRemote : RemoteEvent,
}

local function init(deps: Deps): ()
	track(deps.notifyRemote.OnClientEvent:Connect(function(raw: any)
		if type(raw) ~= "table" then
			log:warn("Payload bukan table", { raw = tostring(raw) })
			return
		end
		if type(raw.message) ~= "string" or #raw.message == 0 then
			log:warn("Message tidak valid")
			return
		end

		NotifService.show({
			message   = raw.message,
			notifType = raw.notifType,
			title = if type(raw.title) == "string" then raw.title else nil,
			description = if type(raw.description) == "string" then raw.description else nil,
			domain = if type(raw.domain) == "string" then raw.domain else nil,
			dedupeKey = if type(raw.dedupeKey) == "string" then raw.dedupeKey else nil,
			duration = if type(raw.duration) == "number" then raw.duration else nil,
			iconImage = if type(raw.iconImage) == "string" then raw.iconImage else nil,
		})
	end))

	log:info("NotifController siap")
end

return { init = init, destroy = destroy }
