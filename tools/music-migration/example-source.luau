--!nocheck
-- ============================================================
-- EXAMPLE SOURCE DATA buat MigrateMusic.server.luau
-- ============================================================
-- File ini cuma referensi format. Copy struktur tabel-nya, paste
-- ke SOURCE_DATA di MigrateMusic.server.luau, terus isi dgn data
-- dari sistem musik lama kamu.
--
-- Mapper di MigrateMusic.server.luau tolerant ke variasi field name,
-- jadi kalau sistem lama pake nama beda, mapper akan coba match.
-- ============================================================

return {
	-- ----------------------------------------------------------
	-- PLAYLISTS (opsional)
	-- ----------------------------------------------------------
	-- Kalau gak di-isi, playlist akan auto-dibikin dari track.playlistName,
	-- atau fallback ke "Imported" (DEFAULT_PLAYLIST_NAME).
	playlists = {
		{
			-- id = "abc-123",  -- opsional, auto-generate kalau nil
			name = "Amapiano and Afro Remix",
			coverType = "gradient", -- "gradient" | "image"
			coverValue = 1,         -- gradient index (1..N) atau "rbxassetid://..."
			fontFace = "Original",
		},
		{
			name = "Late Night Vibes",
			coverType = "image",
			coverValue = "rbxassetid://84494880468556",
		},
		{
			name = "Throwbacks",
			-- coverType + coverValue di-default ke gradient index 1
		},
	},

	-- ----------------------------------------------------------
	-- TRACKS (wajib)
	-- ----------------------------------------------------------
	tracks = {
		-- Format minimum: name + parts + (playlistName atau playlistId)
		{
			name = "Make You Mine",
			creator = "PUBLIC",
			playlistName = "Late Night Vibes", -- match by name (case-insensitive)
			parts = {
				"rbxassetid://1234567890",
				"rbxassetid://1234567891",
			},
			-- Per-track playback speed. Mapper accept:
			--   - field name: playbackSpeed | normalPlaybackSpeed | speed
			--   - format: number, "2.3", "2.3x", " 0.85 "
			normalPlaybackSpeed = 0.85,
		},

		-- Track tanpa playlist eksplisit \u2192 masuk "Imported"
		{
			name = "Untitled Drop",
			creator = "Anonymous",
			parts = { "rbxassetid://9876543210" },
		},

		-- Track dgn playlist baru yang belum ada di playlists[] di atas:
		-- mapper akan auto-create playlist "Drum & Bass" dgn default cover.
		{
			name = "Bass Therapy",
			creator = "DJ Example",
			playlistName = "Drum & Bass",
			parts = {
				"rbxassetid://1111111111",
				"rbxassetid://2222222222",
				"rbxassetid://3333333333",
			},
			playbackSpeed = 1.25, -- field name "playbackSpeed" juga didukung
		},

		-- Sistem lama yang pake field "assetIds" (array alternatif):
		{
			name = "Legacy Format Track",
			creator = "Old System",
			playlistName = "Throwbacks",
			assetIds = { "1234", "5678" }, -- mapper auto-add prefix rbxassetid://
		},

		-- Sistem lama yang flat assetId1..N (bukan array):
		{
			name = "Flat Field Track",
			creator = "Legacy",
			playlistName = "Throwbacks",
			assetId1 = "rbxassetid://4444444444",
			assetId2 = "rbxassetid://5555555555",
			-- assetId3..9 boleh kosong
		},

		-- Track dgn 9 parts (max sesuai Config.Music.MAX_TRACK_PARTS):
		{
			name = "Long Mix",
			creator = "Producer",
			playlistName = "Amapiano and Afro Remix",
			parts = {
				"rbxassetid://1001", "rbxassetid://1002", "rbxassetid://1003",
				"rbxassetid://1004", "rbxassetid://1005", "rbxassetid://1006",
				"rbxassetid://1007", "rbxassetid://1008", "rbxassetid://1009",
			},
			playbackSpeed = "2.3x", -- format string juga OK
		},
	},
}
