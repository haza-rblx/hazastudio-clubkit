--!strict
-- Local-player overhead payload fan-out for donation panel profile refresh.

local Players = game:GetService("Players")

local listeners: { (payload: any) -> () } = {}

local DonationPanelBridge = {}

function DonationPanelBridge.subscribe(callback: (payload: any) -> ()): ()
	table.insert(listeners, callback)
end

function DonationPanelBridge.notifyLocalPayload(payload: any): ()
	if type(payload) ~= "table" or type(payload.userId) ~= "number" then
		return
	end
	local localPlayer = Players.LocalPlayer
	if not localPlayer or payload.userId ~= localPlayer.UserId then
		return
	end
	for _, callback in ipairs(listeners) do
		task.spawn(callback, payload)
	end
end

return DonationPanelBridge
