--!strict
-- Coordinates GenericBroadcast wrapper position while donation notifications play.

local GenericBroadcastLayoutBridge = {}

type Listener = (active: boolean) -> ()

local listeners: { Listener } = {}
local donationNotifActive = false

function GenericBroadcastLayoutBridge.setDonationNotifActive(active: boolean): ()
	if donationNotifActive == active then
		return
	end
	donationNotifActive = active
	for _, listener in ipairs(listeners) do
		task.spawn(listener, active)
	end
end

function GenericBroadcastLayoutBridge.isDonationNotifActive(): boolean
	return donationNotifActive
end

function GenericBroadcastLayoutBridge.subscribe(listener: Listener): ()
	table.insert(listeners, listener)
	task.defer(function()
		listener(donationNotifActive)
	end)
end

return GenericBroadcastLayoutBridge
