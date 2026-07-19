--!strict
-- Hazastudio Clubkit product fingerprint (read-only -- do not edit in buyer places).
-- Venue branding lives in ReplicatedStorage.Hazastudio_ClubKitConfig.ClubKitConfig.

local KitProduct = {
	ProductId = "hazastudioclubkit",
	ProductName = "Hazastudio Clubkit",
	Vendor = "Hazastudio",
	KitVersion = "2.4.60",
	BuildId = "20260719",
	LicenseApiProduct = "clubkit",
	-- v1.3+: server polls donation-api /v2/license/verify. Older kit builds omit this flag.
	LicenseEnforcementEnabled = true,
	LogTag = "HazastudioClubkit",
	MemoryStorePrefix = "HazastudioClubKit",
	-- Tampil di F9 console banner (ConsoleBanner). Isi Discord/Website/Email sesuai branding.
	Support = {
		Discord = "", -- contoh: "discord.gg/your-invite"
		Website = "", -- contoh: "https://hazastudio.example"
		Roblox = "Hazastudio",
		Email = "",
		Note = "Club Kit by Hazastudio â€” issues? contact club staff or Hazastudio support.",
	},
}

return KitProduct
