--!strict
-- Shared/Domain/CoupleDomain.lua
-- Pure functions only. Zero Roblox service calls.

local Types = require(script.Parent.Types)

type OverheadStoredData = Types.OverheadStoredData

local CoupleDomain = {}

function CoupleDomain.isCoupled(stored: OverheadStoredData): boolean
	return stored.couplePartnerId ~= nil or stored.couplePartner ~= nil
end

function CoupleDomain.applyCouple(
	stored: OverheadStoredData,
	partnerName: string,
	partnerId: number
): OverheadStoredData
	local OverheadDomain = require(script.Parent.OverheadDomain)
	local publicOverheadLayerVisible = table.clone(stored.publicOverheadLayerVisible or {})
	-- Coupling reveals the CoupleName row — unless the buyer switched that layer off for the
	-- whole venue. Storing a true there would be dead data: the payload build and the
	-- renderer both force it false again, so hard-off keeps storage honest too.
	if not OverheadDomain.isLayerDisabled("CoupleName") then
		publicOverheadLayerVisible.CoupleName = true
	end

	return OverheadDomain.mergeStored(stored, {
		couplePartner = partnerName,
		couplePartnerId = partnerId,
		showCoupleName = true,
		publicOverheadLayerVisible = publicOverheadLayerVisible,
	})
end

function CoupleDomain.removeCouple(stored: OverheadStoredData): OverheadStoredData
	local OverheadDomain = require(script.Parent.OverheadDomain)
	local NIL = OverheadDomain.NIL
	-- NIL sentinel: pairs() skips plain nil. Clear partner ids so chatCoupleTag
	-- and overhead CoupleName rebuild as uncoupled on next payload.
	return OverheadDomain.mergeStored(stored, {
		couplePartner = NIL,
		couplePartnerId = NIL,
	})
end

return CoupleDomain
