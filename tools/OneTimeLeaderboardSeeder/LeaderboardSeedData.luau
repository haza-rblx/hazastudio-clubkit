--!strict
--[[
  ONE-TIME LEADERBOARD SEED DATA (third-party / standalone)
  ======================================================
  Edit the tables below, then run OneTimeLeaderboardSeeder.server.luau
  from Play Mode (F5). After a successful commit:
    - Set ENABLED = false in the seeder, OR
    - Remove the OneTimeLeaderboardSeeder folder from ServerScriptService.

  Entry format (use userId OR username):
    { userId = 123456789, idr = 500000 }   -- cash
    { username = "PlayerName", robux = 250 }
    { userId = 123456789, likes = 42 }

  idr / robux / likes values = absolute totals to write (not delta),
  unless STRATEGY = "add" in the seeder script.
]]

export type SeedEntry = {
	userId: number?,
	username: string?,
	idr: number?,
	robux: number?,
	likes: number?,
	amount: number?, -- alias: idr for cash, robux, or likes
}

local LeaderboardSeedData = {}

-- =============================================================================
-- FILL DATA HERE (examples — replace / remove before production)
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
