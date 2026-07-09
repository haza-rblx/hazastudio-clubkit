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
	publicOverheadLayerVisible.CoupleName = true

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
	-- Pakai NIL sentinel karena pairs() skip nil values
	return OverheadDomain.mergeStored(stored, {
		couplePartner = NIL,
		couplePartnerId = NIL,
	})
end

return CoupleDomain
