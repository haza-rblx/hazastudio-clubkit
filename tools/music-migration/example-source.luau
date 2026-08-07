--!nocheck
-- ============================================================
-- EXAMPLE SOURCE DATA for MigrateMusic.server.luau
-- ============================================================
-- Reference format only. Copy the table structure and paste
-- into SOURCE_DATA in MigrateMusic.server.luau, then fill with
-- data from your legacy music system.
--
-- MigrateMusic.server.luau mapper tolerates field name variations,
-- so if the old system uses different names, the mapper will try to match.
-- ============================================================

return {
	-- ----------------------------------------------------------
	-- PLAYLISTS (optional)
	-- ----------------------------------------------------------
	-- If omitted, playlists are auto-created from track.playlistName,
	-- or fallback to "Imported" (DEFAULT_PLAYLIST_NAME).
	playlists = {
		{
			-- id = "abc-123",  -- optional, auto-generated if nil
			name = "Amapiano and Afro Remix",
			coverType = "gradient", -- "gradient" | "image"
			coverValue = 1,         -- gradient index (1..N) or "rbxassetid://..."
			fontFace = "Original",
		},
		{
			name = "Late Night Vibes",
			coverType = "image",
			coverValue = "rbxassetid://84494880468556",
		},
		{
			name = "Throwbacks",
			-- coverType + coverValue default to gradient index 1
		},
	},

	-- ----------------------------------------------------------
	-- TRACKS (required)
	-- ----------------------------------------------------------
	tracks = {
		-- Minimum format: name + parts + (playlistName or playlistId)
		{
			name = "Make You Mine",
			creator = "PUBLIC",
			playlistName = "Late Night Vibes", -- match by name (case-insensitive)
			parts = {
				"rbxassetid://1234567890",
				"rbxassetid://1234567891",
			},
			-- Per-track playback speed. Mapper accepts:
			--   - field name: playbackSpeed | normalPlaybackSpeed | speed
			--   - format: number, "2.3", "2.3x", " 0.85 "
			normalPlaybackSpeed = 0.85,
		},

		-- Track without explicit playlist → goes to "Imported"
		{
			name = "Untitled Drop",
			creator = "Anonymous",
			parts = { "rbxassetid://9876543210" },
		},

		-- Track with new playlist not in playlists[] above:
		-- mapper auto-creates playlist "Drum & Bass" with default cover.
		{
			name = "Bass Therapy",
			creator = "DJ Example",
			playlistName = "Drum & Bass",
			parts = {
				"rbxassetid://1111111111",
				"rbxassetid://2222222222",
				"rbxassetid://3333333333",
			},
			playbackSpeed = 1.25, -- field name "playbackSpeed" also supported
		},

		-- Legacy system using "assetIds" (alternate array):
		{
			name = "Legacy Format Track",
			creator = "Old System",
			playlistName = "Throwbacks",
			assetIds = { "1234", "5678" }, -- mapper auto-adds rbxassetid:// prefix
		},

		-- Legacy system with flat assetId1..N (not an array):
		{
			name = "Flat Field Track",
			creator = "Legacy",
			playlistName = "Throwbacks",
			assetId1 = "rbxassetid://4444444444",
			assetId2 = "rbxassetid://5555555555",
			-- assetId3..9 may be empty
		},

		-- Track with 9 parts (max per Config.Music.MAX_TRACK_PARTS):
		{
			name = "Long Mix",
			creator = "Producer",
			playlistName = "Amapiano and Afro Remix",
			parts = {
				"rbxassetid://1001", "rbxassetid://1002", "rbxassetid://1003",
				"rbxassetid://1004", "rbxassetid://1005", "rbxassetid://1006",
				"rbxassetid://1007", "rbxassetid://1008", "rbxassetid://1009",
			},
			playbackSpeed = "2.3x", -- string format also OK
		},
	},
}
