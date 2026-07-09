--!strict
--[[
  SHOWCASE SWITCH — file ini mengontrol demo vs live mode.

  File ADA     → showcase ON  (leaderboard demo untuk screenshot)
  File DIHAPUS → real mode   (tanpa demo leaderboard)
  ACTIVE=false → real mode   (tanpa hapus file)

  Donation.ApiUrl + Secrets tetap bisa diisi — live donasi & social API jalan
  bersamaan dengan showcase demo board (community/donor showcase).

  Community leaderboard demo = group milik ClubKitConfig.Group.OwnerUserId.
]]

local ACTIVE = true
if not ACTIVE then
	return nil
end

return {
	Donation = {
		MinAmount = 100,
		AuraTiers = {
			{ level = 1, min = 1, idrMin = 100, idrMax = 499, effect = "Level1", sound = "Level1", duration = 4, cameraDuration = 0 },
			{ level = 3, min = 5, idrMin = 500, idrMax = 999, effect = "Level3", sound = "Level3", duration = 4, cameraDuration = 0 },
			{ level = 4, min = 10, idrMin = 1000, idrMax = 1499, effect = "Level4", sound = "Level4", duration = 4, cameraDuration = 0 },
			{ level = 5, min = 15, idrMin = 1500, idrMax = 1999, effect = "Level5", sound = "Level5", duration = 5, cameraDuration = 0 },
			{ level = 6, min = 20, idrMin = 2000, idrMax = math.huge, effect = "Level6", sound = "Level6", duration = 5, cameraDuration = 6 },
		},
		WorldEffectTiers = {
			{ min = 2000, effect = "Nuke" },
			{ min = 5000, effect = "Smite4" },
			{ min = 10000, effect = "BlackHole" },
		},
	},
	Showcase = {
		LeaderboardUseOwnerOnly = false,
		SourceUserId = 0,
		MinAmount = 100000,
		MaxAmount = 10000000,
		RobuxMinAmount = 1,
		RobuxMaxAmount = 50000,
		LeaderboardLimit = 10,
		RefreshInterval = 300,
		-- Biarkan nil agar showcase donor board ambil player server + friend list.
		-- Isi manual hanya kalau memang ingin daftar demo custom.
		Profiles = nil,
	},
}
