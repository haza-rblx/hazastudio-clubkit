--!strict
--[[
  ONE-TIME LEADERBOARD SEED DATA (third-party / standalone)
  ======================================================
  Edit tabel di bawah, lalu jalankan OneTimeLeaderboardSeeder.server.luau
  dari Play Mode (F5). Setelah commit sukses:
    - Set ENABLED = false di seeder, ATAU
    - Hapus folder OneTimeLeaderboardSeeder dari ServerScriptService.

  Entry format (pilih userId ATAU username):
    { userId = 123456789, idr = 500000 }   -- cash
    { username = "PlayerName", robux = 250 }
    { userId = 123456789, likes = 42 }

  Nilai idr / robux / likes = total absolut yang ingin ditulis (bukan delta),
  kecuali STRATEGY = "add" di seeder script.
]]

export type SeedEntry = {
	userId: number?,
	username: string?,
	idr: number?,
	robux: number?,
	likes: number?,
	amount: number?, -- alias: idr untuk cash, robux, atau likes
}

local LeaderboardSeedData = {}

-- =============================================================================
-- ISI DATA DI SINI (contoh — ganti / hapus sebelum production)
-- =============================================================================

LeaderboardSeedData.Cash = {
	-- { userId = 8842050215, idr = 1_500_000 },
	-- { username = "SomePlayer", idr = 750_000 },
} :: { SeedEntry }

LeaderboardSeedData.Robux = {
	-- { userId = 8842050215, robux = 500 },
} :: { SeedEntry }

LeaderboardSeedData.Likes = {
	-- { userId = 8842050215, likes = 120 },
} :: { SeedEntry }

return LeaderboardSeedData
