--!strict
-- The prototype's mock data (DJXTabs, 2026-10-23), as a demo fixture. Seeded only in Studio when
-- `workspace:SetAttribute("HazaDJ_Fixture", true)`, so the rebuild can be compared with the
-- prototype screen for screen. Never used in a live game.
local Types = require(script.Parent.Types)
local Defaults = require(script.Parent.Defaults)

local Fixture = {}

local PLAYLISTS = { "Warm up", "Peak time", "Closing", "Encore" }
local SEED = {
	{ "Midnight Static", "Kuro.wav", 124, "8A", 372, { "Peak time", "Encore" } },
	{ "Low Tide", "Lunalow", 118, "5A", 301, { "Warm up" } },
	{ "Glass Hallway", "Nightshift", 126, "11B", 415, { "Peak time" }, nil, 1.02 },
	{ "Pale Neon", "Sora Vex", 122, "2A", 338, { "Warm up" } },
	{ "Afterhours Bloom", "Kuro.wav", 120, "9A", 290, { "Closing" }, nil, 0.98 },
	{ "Velvet Engine", "Mono Atlas", 128, "4B", 402, { "Peak time" }, "unavailable" },
	{ "Saltwater Radio", "Lunalow", 116, "6A", 284, { "Warm up", "Closing" } },
	{ "Concrete Garden", "Hollow Pines", 125, "10A", 366, { "Peak time" } },
	{ "Slow Satellites", "Sora Vex", 110, "3B", 312, { "Closing" } },
	{ "Ultraviolet Hum", "Nightshift", 127, "8B", 391, { "Peak time" }, nil, 1.05 },
	{ "Paper Lanterns", "Mono Atlas", 121, "7A", 297, { "Encore" } },
	{ "Second Sunrise", "Hollow Pines", 112, "12A", 344, { "Closing" }, "unavailable" },
	{ "Tin Roof Echo", "Kuro.wav", 123, "1A", 326, { "Encore" } },
	{ "Mirror Lake", "Lunalow", 119, "5B", 308, { "Warm up" } },
}

function Fixture.library(): Types.Library
	local lib = Defaults.library()
	local playlists = {}
	for i, name in PLAYLISTS do
		playlists[i] = { id = "p" .. i, name = name, shuffle = false, tracks = {} } :: Types.Playlist
	end
	for i, s in SEED do
		local id = "t" .. i
		lib.tracks[id] = {
			id = id,
			assetId = 18400000 + i * 7919,
			title = s[1] :: string,
			artist = s[2] :: string,
			bpm = s[3] :: number,
			key = s[4] :: string,
			len = s[5] :: number,
			speed = (s[8] :: number?) or 1,
			gain = 0,
			start = 0,
			status = ((s[7] :: string?) or "ready") :: any,
			added = i,
		}
		for _, pl in playlists do
			if table.find(s[6] :: { string }, pl.name) then
				table.insert(pl.tracks, id)
			end
		end
	end
	lib.playlists = playlists
	lib.nextAdded = #SEED + 1
	return lib
end

-- people: the owner is whoever runs the test (41 sets, 63 h); these are the others
Fixture.OWNER_STATS = { sets = 41, seconds = 63 * 3600 }
function Fixture.access(now: number): Types.Access
	local a = Defaults.access()
	local day = 86400
	local function date(m: number, d: number): number
		return os.time({ year = 2026, month = m, day = d, hour = 12 })
	end
	a.people = {
		["-101"] = {
			userId = -101,
			name = "Kuro",
			handle = "kuro_wav",
			role = "Resident",
			since = date(10, 3),
			sets = 18,
			seconds = 27 * 3600,
			lastSet = now,
			added = 1,
		},
		["-102"] = {
			userId = -102,
			name = "Lunalow",
			handle = "lunalow",
			role = "Resident",
			since = date(9, 28),
			sets = 12,
			seconds = 19 * 3600,
			lastSet = now - 2 * day,
			added = 2,
		},
		["-103"] = {
			userId = -103,
			name = "Sora Vex",
			handle = "soravex",
			role = "Resident",
			since = date(9, 12),
			sets = 7,
			seconds = 9 * 3600,
			lastSet = now - 8 * day,
			added = 3,
		},
		["-104"] = {
			userId = -104,
			name = "Nightshift",
			handle = "nightshift_dj",
			role = "Guest",
			ends = 1,
			sets = 1,
			seconds = 3600,
			lastSet = now,
			added = 4,
		},
		["-105"] = {
			userId = -105,
			name = "Hollow Pines",
			handle = "hollowpines",
			role = "Guest",
			ends = 1,
			sets = 0,
			seconds = 0,
			added = 5,
		},
	}
	return a
end

-- the decks as the prototype draws them: A live mid-track, B cued
function Fixture.session(now: number): Types.Session
	local s = Defaults.session()
	s.live = -101
	s.automix = true
	s.online = { ["-101"] = true, ["-104"] = true }
	s.decks[1] = {
		trackId = "t1",
		playing = false,
		pos = 204,
		at = now,
		cue = 0,
		pitch = 0,
		synced = false,
		eq = { 0.5, 0.55, 0.42 },
		filter = 0.5,
		vol = 0.82,
		fx = { 0.6, 0.8, 0 },
		lastCue = 2,
	}
	s.decks[2] = {
		trackId = "t4",
		playing = false,
		pos = 37,
		at = now,
		cue = 0,
		pitch = 0.016,
		synced = false,
		eq = { 0.5, 0.5, 0.2 },
		filter = 0.3,
		vol = 0.35,
		fx = { 0, 0.3, 0.5 },
		lastCue = 2,
	}
	s.xfader = 0.7
	s.curve = 0.05
	s.master = 0.8
	return s
end

-- hot cues 1, 2 and 4 set on both fixture tracks
function Fixture.cues(lib: Types.Library): Types.Library
	for _, id in { "t1", "t4" } do
		local t = lib.tracks[id]
		if t then
			t.cues = { ["1"] = 12, ["2"] = 64, ["4"] = 180 }
		end
	end
	return lib
end

return Fixture
