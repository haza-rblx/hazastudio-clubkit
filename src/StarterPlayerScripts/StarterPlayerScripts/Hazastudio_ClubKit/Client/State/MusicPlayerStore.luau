--!strict
-- PATH: StarterPlayerScripts/Client/State/MusicPlayerStore.lua
-- Reactive store for Music Player. Pattern: identik with SyncStore.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

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

-- Full volume until SettingsController publishes the player's own SettingsMusicVolume. Must be
-- the same number the 100% slider produces, otherwise a track that starts before settings arrive
-- would play quiet and then jump when the attribute lands.
local DEFAULT_VOLUME = math.clamp(
	(if type((Config :: any).Music) == "table" then tonumber((Config :: any).Music.MAX_VOLUME) else nil) or 4,
	0,
	10
)

return createStore({
	-- Panel visibility
	isOpen    = false,
	activeTab = "nowplaying",  -- "nowplaying" | "request" | "dj"

	-- Now Playing
	currentTrack    = nil,     -- TrackInfo?
	currentEntry    = nil,     -- QueueEntry?
	playbackTiming  = nil,     -- PlaybackTiming? (server-authoritative)
	startServerTime = 0,
	expectedEndServerTime = 0,
	isPlaying       = false,
	isDjMode        = false,
	djOwnerUserId   = nil,     -- number? userId who enabled DJ mode
	volume          = DEFAULT_VOLUME, -- Sound.Volume, 0..Config.Music.MAX_VOLUME (client-side only)
	queue           = {},      -- { TrackInfo } user requests only (Next up)
	prefetchBuffer  = {},      -- { TrackInfo } hidden server auto buffer (preload only)

	-- Request Song tab
	playlists          = {},   -- { [id]: PlaylistInfo }
	selectedPlaylistId = nil,  -- string? playlistId or special playlist id
	tracks             = {},   -- { [id]: TrackInfo } from playlist yang dipilih
	allTracks          = {},   -- { [id]: TrackInfo } every track this player may see (v3 DJ Sets)
	djSets             = {},   -- { MusicLibraryModel.DjSet } derived once per allTracks load
	favoriteTrackIds   = {},   -- { [trackId]: true } mirror from Player attribute favorites
	searchQuery        = "",

	-- Privileges and request state (the library is edited only in the customer area, ADR 0010)
	isControlAllowed = false,  -- live control: DJ tab, DJ-mode bypass (ADR 0010)
	isPlayOnceAllowed = false, -- Request From ID box (play-once, 3.0); the server decides per player
	isLoading       = false,   -- a Request From ID lookup is in flight
})
