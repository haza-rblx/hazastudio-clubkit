--!strict
-- Hazastudio Clubkit product fingerprint (read-only — do not edit in buyer places).
-- Venue branding lives in ReplicatedStorage.Hazastudio_ClubKitConfig.ClubKitConfig.

local KitProduct = {
	ProductId = "hazastudioclubkit",
	ProductName = "Hazastudio Clubkit",
	Vendor = "Hazastudio",
	KitVersion = "2.1.0",
	BuildId = "20260706",
	LicenseApiProduct = "clubkit",
	-- v1.3+: server polls donation-api /v2/license/verify. Older kit builds omit this flag.
	LicenseEnforcementEnabled = true,
	LogTag = "HazastudioClubkit",
	MemoryStorePrefix = "HazastudioClubKit",
}

return KitProduct
