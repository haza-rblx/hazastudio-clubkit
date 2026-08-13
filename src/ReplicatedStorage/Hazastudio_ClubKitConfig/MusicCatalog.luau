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
-- PREFERRED — group tracks under each playlist (no playlistName per line):
--   playlists = {
--     { name = "Chill", tracks = {
--       { name = "Song A", creator = "Artist", parts = { "123" } },
--     }},
--   }
--
-- LEGACY — flat list still works (default playlist "Legacy" if no playlistName):
--   tracks = {
--     { name = "Song B", creator = "Artist", playlistName = "Chill", parts = { "456" } },
--   }
--
-- Both shapes can be used together. Multi-part: up to 9 IDs in parts = { ... }.
-- Asset IDs: raw digits, number, or "rbxassetid://..." (normalized to digits).

return {
	enabled = true,

	playlists = {
		-- Example grouped seed (delete / replace with your library):
		-- {
		-- 	name = "Chill",
		-- 	visibility = "public",
		-- 	tracks = {
		-- 		{ name = "Song A", creator = "Artist", parts = { "1234567890" } },
		-- 		{ name = "Song B", creator = "Artist", parts = { "1111111111", "2222222222" }, playbackSpeed = 0.85 },
		-- 	},
		-- },
		-- {
		-- 	name = "HIPHOP & RNB",
		-- 	tracks = {
		-- 		{ name = "Song C", creator = "Artist", parts = { "4444444444" } },
		-- 	},
		-- },
	},

	-- Optional flat list (legacy). Tracks without playlistName go to "Legacy".
	tracks = {
		-- { name = "Song D", creator = "Artist", playlistName = "Chill", parts = { "5555555555" } },
	},
}
