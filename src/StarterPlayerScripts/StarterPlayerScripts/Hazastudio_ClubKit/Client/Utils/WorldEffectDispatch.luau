--!strict
-- Client-local dispatch for donation world VFX (Nuke / Smite4 / BlackHole).
-- Fired when a donation notification actually starts showing, so world effects
-- follow the notif queue cadence instead of a long server serial wait.

local WorldEffectDispatch = {}

local bindable: BindableEvent? = nil

local function getEvent(): BindableEvent
	local existing = bindable
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("BindableEvent")
	created.Name = "ClubKitWorldEffectDispatch"
	-- Parentless BindableEvent is fine for same-VM listeners.
	bindable = created
	return created
end

export type WorldEffectListener = (
	effectName: string,
	donorName: string,
	recipientName: string,
	amount: number,
	donorUserId: number?
) -> ()

function WorldEffectDispatch.connect(listener: WorldEffectListener): RBXScriptConnection
	return getEvent().Event:Connect(function(
		effectName: any,
		donorName: any,
		recipientName: any,
		amount: any,
		donorUserId: any
	)
		if type(effectName) ~= "string" or effectName == "" then
			return
		end
		listener(
			effectName,
			if type(donorName) == "string" then donorName else "",
			if type(recipientName) == "string" then recipientName else "",
			tonumber(amount) or 0,
			if type(donorUserId) == "number" then donorUserId else nil
		)
	end)
end

function WorldEffectDispatch.fire(
	effectName: string,
	donorName: string,
	recipientName: string,
	amount: number,
	donorUserId: number?
)
	if type(effectName) ~= "string" or effectName == "" then
		return
	end
	getEvent():Fire(effectName, donorName, recipientName, amount, donorUserId)
end

return WorldEffectDispatch
