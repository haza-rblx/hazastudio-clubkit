--!strict
-- PATH: ReplicatedStorage/Hazastudio_ClubKitConfig/MusicCatalog.luau
--
-- Buyer-owned music library seed (bulk add via script).
-- Server merges into DataStore on boot (additive only). Manage UI can still
-- edit / move / delete tracks after seed — Manage wins; catalog will not overwrite.
--
-- Toggle master switch: ClubKitConfig.Features.MusicCatalogSeed
-- Local pause (keep data, skip merge): enabled = false below
--
-- Default playlist for tracks without playlistName / playlistId: "Legacy"
-- (auto-created if missing). Override per-track with playlistName or playlistId.
--
-- Track rows: keep EACH TRACK ON ONE LINE for easy paste of 200+.
-- Multi-part: put up to 9 asset IDs in parts = { "id1", "id2", ... }.
-- Asset IDs: raw digits, number, or "rbxassetid://..." (normalized to digits).

return {
	enabled = true,

	-- Optional playlists to ensure exist before tracks (besides default "Legacy").
	-- playlists = {
	-- 	{ name = "Chill", visibility = "public" },
	-- },

	tracks = {
		-- Examples (delete / replace with your library):
		-- { name = "Song A", creator = "Artist", parts = { "1234567890" } },
		-- { name = "Song B", creator = "Artist", parts = { "1111111111", "2222222222", "3333333333" }, playbackSpeed = 0.85 },
		-- { name = "Song C", creator = "Artist", playlistName = "Chill", parts = { "4444444444" } },
	},
}
