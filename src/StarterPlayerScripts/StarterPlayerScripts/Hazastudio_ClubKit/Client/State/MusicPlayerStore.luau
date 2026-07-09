--!strict
-- PATH: StarterPlayerScripts/Client/State/MusicPlayerStore.lua
-- Reactive store untuk Music Player. Pattern: identik dengan SyncStore.

local NONE = newproxy(false) -- sentinel: store:set({ key = NONE }) sets key to nil

local function createStore(initialState: { [string]: any })
	local state = table.freeze(table.clone(initialState))
	local subscribers: { [string]: { (any, any) -> () } } = {}
	local store = {}
	store.NONE = NONE -- expose sentinel for callers

	function store:get()
		return state
	end

	function store:set(changes: { [string]: any })
		local previous = state
		local nextState = table.clone(state :: any)

		local key = next(changes)
		while key ~= nil do
			local value = changes[key]
			if value == NONE then
				(nextState :: any)[key] = nil
			else
				(nextState :: any)[key] = value
			end
			key = next(changes, key)
		end

		state = table.freeze(nextState)

		for k, callbacks in pairs(subscribers) do
			if (previous :: any)[k] ~= (state :: any)[k] then
				for _, callback in ipairs(callbacks) do
					task.spawn(callback, (state :: any)[k], (previous :: any)[k])
				end
			end
		end
	end

	function store:subscribe(key: string, callback: (any, any) -> ())
		subscribers[key] = subscribers[key] or {}
		table.insert(subscribers[key], callback)
		-- Mengembalikan unsubscribe function
		return function()
			local cbs = subscribers[key]
			if not cbs then return end
			for i, existing in ipairs(cbs) do
				if existing == callback then
					table.remove(cbs, i)
					break
				end
			end
		end
	end

	return store
end

-- ============================================================
-- INITIAL STATE
-- ============================================================

return createStore({
	-- Panel visibility
	isOpen    = false,
	activeTab = "nowplaying",  -- "nowplaying" | "request" | "manage"

	-- Music zone
	activeZoneId          = nil, -- string?
	activeZoneDisplayName = nil, -- string?

	-- Now Playing
	currentTrack    = nil,     -- TrackInfo?
	currentEntry    = nil,     -- QueueEntry?
	playbackTiming  = nil,     -- PlaybackTiming? (server-authoritative)
	startServerTime = 0,
	expectedEndServerTime = 0,
	isPlaying       = false,
	isDjMode        = false,
	djOwnerUserId   = nil,     -- number? userId yang menyalakan DJ mode
	volume          = 0.5,     -- 0..1 (client-side only)
	queue           = {},      -- { TrackInfo } user requests only (Next up)
	prefetchBuffer  = {},      -- { TrackInfo } hidden server auto buffer (preload only)

	-- Request Song tab
	playlists          = {},   -- { [id]: PlaylistInfo }
	selectedPlaylistId = nil,  -- string? playlistId atau special playlist id
	tracks             = {},   -- { [id]: TrackInfo } dari playlist yang dipilih
	favoriteTrackIds   = {},   -- { [trackId]: true } mirror dari Player attribute favorites
	searchQuery        = "",

	-- Manage tab
	manageSubView   = "idle",  -- "idle" | "edit_track" | "edit_playlist"
	editingTrack    = nil,     -- TrackInfo? (nil = create mode)
	editingPlaylist = nil,     -- PlaylistInfo? (nil = create mode)
	selectedTrackPlaylistId = nil, -- string? selected playlist in upload/edit track form
	isManageAllowed = false,
	isLoading       = false,   -- loading state untuk form submission

	-- Cover & Font customization state
	selectedCoverType  = "gradient",  -- "gradient" | "image"
	selectedCoverValue = 1,           -- gradient index (number) or image assetId (string)
	selectedFontFace   = "Original", -- font name from FONT_PRESETS
	selectedPlaylistVisibility = "public", -- "public" | "private"
	playlistNamePreview = "",         -- current playlist name for preview in gradient cards
})
