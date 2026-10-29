--!strict
-- The Library tab's local state (what is open, searched, selected) and the derived track list.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vide = require(ReplicatedStorage.HazaDJ.Packages.Vide)
local Shared = ReplicatedStorage.HazaDJ.Shared
local Format = require(Shared.Format)
local Types = require(Shared.Types)
local Store = require(script.Parent.Parent.Parent.Store)

local source = Vide.source

export type Draft = {
	id: number?,
	idText: string?,
	title: string,
	artist: string,
	bpm: number?,
	key: string?,
	speed: number,
	probe: string?, -- "checking" | "ok" | "dead" | "bad" | "dupe"
	len: number?,
	lists: { [string]: boolean },
	batch: { { id: number, probe: string, name: string?, creator: string?, len: number? } }?,
	capped: boolean?,
}

local State = {}

function State.new()
	local S = {
		view = source("all" :: string), -- "all" | "attention" | "pads" | a playlist id
		query = source(""),
		sort = source(1),
		selected = source(nil :: string?),
		adding = source(false),
		draft = source(nil :: Draft?),
		focusName = source(false), -- a new playlist opens with its name field focused
		coverOpen = source(false),
		padSelected = source(1),
		previewing = source(nil :: number?), -- the sound asset id being previewed
	}

	function S.playlist(id: string): Types.Playlist?
		for _, p in Store.library().playlists do
			if p.id == id then
				return p
			end
		end
		return nil
	end

	function S.isPlaylist(v: string): boolean
		return v ~= "all" and v ~= "attention" and v ~= "pads"
	end

	function S.attention(): number
		local n = 0
		for _, t in Store.library().tracks do
			if t.status == "unavailable" then
				n += 1
			end
		end
		return n
	end

	-- the rows the table shows, in order
	function S.visibleTracks(): { Types.Track }
		local lib = Store.library()
		local v, q, sort = S.view(), string.lower(S.query()), S.sort()
		local out = {}
		local function consider(t: Types.Track)
			local inView = v ~= "attention" or t.status == "unavailable"
			local hit = q == ""
				or string.find(string.lower(t.title), q, 1, true) ~= nil
				or string.find(string.lower(t.artist), q, 1, true) ~= nil
			if inView and hit then
				table.insert(out, t)
			end
		end
		local p = if S.isPlaylist(v) then S.playlist(v) else nil
		if p then
			for _, id in p.tracks do
				local t = lib.tracks[id]
				if t then
					consider(t)
				end
			end
		else
			for _, t in lib.tracks do
				consider(t)
			end
		end
		if sort == 2 then
			table.sort(out, function(a, b)
				return a.title < b.title
			end)
		elseif sort == 3 then
			table.sort(out, function(a, b)
				return (Format.effectiveBpm(a.bpm, a.speed) or 0) < (Format.effectiveBpm(b.bpm, b.speed) or 0)
			end)
		elseif not p then
			table.sort(out, function(a, b)
				return a.added > b.added
			end)
		end -- sort 1 in a playlist = the playlist's own order
		return out
	end

	function S.newDraft()
		local lists = {}
		local v = Vide.untrack(S.view)
		if S.isPlaylist(v) then
			lists[v] = true
		end
		S.draft({ title = "", artist = "", speed = 1, lists = lists })
	end

	return S
end

export type S = typeof(State.new())

return State
