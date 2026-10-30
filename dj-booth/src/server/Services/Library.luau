--!strict
-- Library edits: tracks, playlists, the sounds list and the pads. Every function validates its
-- input and returns ok, message, new id.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.CosmicDJ.Shared
local Defaults = require(Shared.Defaults)
local Dict = require(Shared.Dict)
local QueueLogic = require(Shared.Queue)
local Types = require(Shared.Types)
local Probe = require(script.Parent.Probe)
local State = require(script.Parent.State)

local Library = {}

local MAX_TRACKS = 2000
local MAX_PLAYLISTS = 64
local MAX_SOUNDS = 64

local KEYS = {}
for n = 1, 12 do
	KEYS[n .. "A"] = true
	KEYS[n .. "B"] = true
end

local function newId(prefix: string): string
	return prefix .. string.lower(string.sub(string.gsub(HttpService:GenerateGUID(false), "-", ""), 1, 10))
end

local function clean(s: string, max: number): string
	s = string.gsub(s, "[%c]", "")
	s = string.match(s, "^%s*(.-)%s*$") or ""
	return string.sub(s, 1, max)
end

local function edit(fn: (Types.Library) -> Types.Library)
	State.update(State.library, fn)
end

local function setTrack(lib: Types.Library, id: string, patch: { [string]: any }): Types.Library
	return Dict.merge(lib, { tracks = Dict.set(lib.tracks, id, Dict.merge(lib.tracks[id], patch)) })
end

local function playlistIndex(lib: Types.Library, id: string): number?
	for i, p in lib.playlists do
		if p.id == id then
			return i
		end
	end
	return nil
end

local function addToLists(lib: Types.Library, trackId: string, lists: { string }): Types.Library
	local playlists = lib.playlists
	for _, pid in lists do
		local i = playlistIndex(lib, pid)
		if i and not table.find(playlists[i].tracks, trackId) then
			playlists =
				Dict.set(playlists, i, Dict.merge(playlists[i], { tracks = Dict.insert(playlists[i].tracks, trackId) }))
		end
	end
	return Dict.merge(lib, { playlists = playlists })
end

local function hasAsset(lib: Types.Library, assetId: number): boolean
	for _, t in lib.tracks do
		if t.assetId == assetId then
			return true
		end
	end
	return false
end

function Library.addTrack(c: any): (boolean, string?, string?)
	local lib = State.library()
	if hasAsset(lib, c.AssetId) then
		return false, "Already in the library."
	end
	local count = Dict.count(lib.tracks)
	if count >= MAX_TRACKS then
		return false, "The library is full."
	end
	local title = clean(c.Title, 120)
	if title == "" then
		return false, "Give the track a title."
	end
	local key = if c.Key and KEYS[c.Key] then c.Key else nil
	local id = newId("t")
	edit(function(l)
		local t: Types.Track = {
			id = id,
			assetId = c.AssetId,
			title = title,
			artist = if clean(c.Artist, 120) ~= "" then clean(c.Artist, 120) else "—",
			bpm = c.Bpm,
			key = key,
			len = c.Len,
			speed = math.floor(math.clamp(c.Speed, 0.5, 1.5) * 100 + 0.5) / 100,
			gain = 0,
			start = 0,
			status = "ready",
			added = l.nextAdded,
		}
		l = Dict.merge(l, { tracks = Dict.set(l.tracks, id, t), nextAdded = l.nextAdded + 1 })
		return addToLists(l, id, c.Lists)
	end)
	task.spawn(Probe.track, id)
	return true, nil, id
end

function Library.addBatch(c: any): (boolean, string?, string?)
	local last
	local added = 0
	for _, item in c.Items do
		local lib = State.library()
		if hasAsset(lib, item.AssetId) or Dict.count(lib.tracks) >= MAX_TRACKS then
			continue
		end
		local id = newId("t")
		local title = clean(item.Title, 120)
		edit(function(l)
			local t: Types.Track = {
				id = id,
				assetId = item.AssetId,
				title = if title ~= "" then title else tostring(item.AssetId),
				artist = if clean(item.Artist, 120) ~= "" then clean(item.Artist, 120) else "—",
				len = item.Len,
				speed = 1,
				gain = 0,
				start = 0,
				status = "ready",
				added = l.nextAdded,
			}
			l = Dict.merge(l, { tracks = Dict.set(l.tracks, id, t), nextAdded = l.nextAdded + 1 })
			return addToLists(l, id, c.Lists)
		end)
		task.spawn(Probe.track, id)
		last = id
		added += 1
	end
	if added == 0 then
		return false, "Nothing new to add."
	end
	return true, nil, last
end

function Library.editTrack(c: any): (boolean, string?)
	local lib = State.library()
	local t = lib.tracks[c.Id]
	if not t then
		return false, "That track is gone."
	end
	local f = c.Field
	local patch: { [string]: any } = {}
	if f == "Title" then
		local v = clean(c.Text or "", 120)
		if v == "" then
			return false, "A title can't be empty."
		end
		patch.title = v
	elseif f == "Artist" then
		local v = clean(c.Text or "", 120)
		patch.artist = if v ~= "" then v else "—"
	elseif f == "Bpm" then
		patch.bpm = if c.Number then math.clamp(math.floor(c.Number + 0.5), 40, 220) else Dict.None
	elseif f == "Key" then
		patch.key = if c.Text and KEYS[c.Text] then c.Text else Dict.None
	elseif f == "Speed" then
		patch.speed = math.floor(math.clamp(c.Number or 1, 0.5, 1.5) * 100 + 0.5) / 100
	elseif f == "Gain" then
		patch.gain = math.floor(math.clamp(c.Number or 0, -6, 6) * 2 + 0.5) / 2
	elseif f == "Start" then
		local maxStart = if t.len then math.max(0, math.floor(t.len) - 30) else 120
		patch.start = math.clamp(math.floor((c.Number or 0) / 5 + 0.5) * 5, 0, maxStart)
	elseif f == "AssetId" then
		local n = c.Number
		if not n or n < 1 or n ~= math.floor(n) then
			return false, "That isn't an asset ID."
		end
		if n ~= t.assetId and hasAsset(lib, n) then
			return false, "Already in the library."
		end
		patch.assetId = n
		patch.status = "checking"
	end
	edit(function(l)
		return if l.tracks[c.Id] then setTrack(l, c.Id, patch) else l
	end)
	if f == "AssetId" then
		task.spawn(Probe.track, c.Id)
	end
	return true
end

function Library.removeTrack(id: string): (boolean, string?)
	if not State.library().tracks[id] then
		return false, "That track is gone."
	end
	edit(function(l)
		local playlists = {}
		for i, p in l.playlists do
			playlists[i] = if table.find(p.tracks, id)
				then Dict.merge(p, { tracks = Dict.removeValue(p.tracks, id) })
				else p
		end
		return Dict.merge(l, { tracks = Dict.set(l.tracks, id, nil), playlists = playlists })
	end)
	State.update(State.session, function(s)
		return Dict.merge(s, { queue = QueueLogic.prune(s.queue, State.library().tracks) })
	end)
	return true
end

function Library.trackInPlaylist(trackId: string, pid: string, on: boolean): (boolean, string?)
	local lib = State.library()
	local i = playlistIndex(lib, pid)
	if not lib.tracks[trackId] or not i then
		return false, "That track or playlist is gone."
	end
	edit(function(l)
		local j = playlistIndex(l, pid) :: number
		local p = l.playlists[j]
		local has = table.find(p.tracks, trackId) ~= nil
		if has == on then
			return l
		end
		local tracks = if on then Dict.insert(p.tracks, trackId) else Dict.removeValue(p.tracks, trackId)
		return Dict.merge(l, { playlists = Dict.set(l.playlists, j, Dict.merge(p, { tracks = tracks })) })
	end)
	return true
end

function Library.moveTrack(pid: string, trackId: string, by: number): (boolean, string?)
	local lib = State.library()
	local i = playlistIndex(lib, pid)
	if not i then
		return false, "That playlist is gone."
	end
	local p = lib.playlists[i]
	local at = table.find(p.tracks, trackId)
	if not at or not p.tracks[at + by] or by == 0 then
		return false
	end
	local tracks = table.clone(p.tracks)
	tracks[at], tracks[at + by] = tracks[at + by], tracks[at]
	edit(function(l)
		return Dict.merge(l, { playlists = Dict.set(l.playlists, i, Dict.merge(p, { tracks = tracks })) })
	end)
	return true
end

function Library.createPlaylist(): (boolean, string?, string?)
	local lib = State.library()
	if #lib.playlists >= MAX_PLAYLISTS then
		return false, "That's the most playlists the DJ deck keeps."
	end
	local function taken(name: string): boolean
		for _, p in lib.playlists do
			if p.name == name then
				return true
			end
		end
		return false
	end
	local n, name = 1, "New playlist"
	while taken(name) do
		n += 1
		name = "New playlist " .. n
	end
	local id = newId("p")
	edit(function(l)
		return Dict.merge(
			l,
			{ playlists = Dict.insert(l.playlists, { id = id, name = name, shuffle = false, tracks = {} }) }
		)
	end)
	return true, nil, id
end

function Library.editPlaylist(c: any): (boolean, string?)
	local lib = State.library()
	local i = playlistIndex(lib, c.Id)
	if not i then
		return false, "That playlist is gone."
	end
	local patch: { [string]: any } = {}
	local f = c.Field
	if f == "Name" then
		local v = clean(c.Text or "", 60)
		if v == "" then
			return false, "A playlist needs a name."
		end
		patch.name = v
	elseif f == "CoverText" then
		local v = clean(c.Text or "", 40)
		patch.coverText = if v ~= "" then v else Dict.None
	elseif f == "Image" then
		patch.image = if c.Number and c.Number >= 1 then math.floor(c.Number) else Dict.None
	elseif f == "Color" then
		local v = c.Text and string.match(string.lower(c.Text), "^#?(%x%x%x%x%x%x)$")
		patch.color = v or Dict.None
	elseif f == "Shuffle" then
		patch.shuffle = c.Flag == true
	end
	edit(function(l)
		local j = playlistIndex(l, c.Id)
		return if j
			then Dict.merge(l, { playlists = Dict.set(l.playlists, j, Dict.merge(l.playlists[j], patch)) })
			else l
	end)
	return true
end

function Library.deletePlaylist(id: string): (boolean, string?)
	local i = playlistIndex(State.library(), id)
	if not i then
		return false, "That playlist is gone."
	end
	edit(function(l)
		local j = playlistIndex(l, id)
		return if j then Dict.merge(l, { playlists = Dict.removeAt(l.playlists, j) }) else l
	end)
	return true
end

function Library.addSound(assetId: number): (boolean, string?, string?)
	local lib = State.library()
	if #lib.sounds >= MAX_SOUNDS then
		return false, "That's the most sounds the DJ deck keeps."
	end
	for _, s in lib.sounds do
		if s.assetId == assetId then
			return false, "Already in the Sounds list."
		end
	end
	local id = newId("s")
	edit(function(l)
		return Dict.merge(l, {
			sounds = Dict.insert(
				l.sounds,
				{ id = id, assetId = assetId, name = "Sound " .. string.format("%d", assetId), status = "checking" }
			),
		})
	end)
	task.spawn(function()
		local r = Probe.one(assetId)
		edit(function(l)
			for i, s in l.sounds do
				if s.id == id then
					return Dict.merge(l, {
						sounds = Dict.set(
							l.sounds,
							i,
							Dict.merge(s, {
								name = r.Name or s.name,
								len = r.Len or Dict.None,
								status = if r.Ok then Dict.None elseif r.Pending then "checking" else "unavailable",
							})
						),
					})
				end
			end
			return l
		end)
	end)
	return true, nil, id
end

function Library.removeSound(id: string): (boolean, string?)
	edit(function(l)
		local sounds = l.sounds
		for i, s in l.sounds do
			if s.id == id then
				sounds = Dict.removeAt(l.sounds, i)
			end
		end
		local pads = {}
		for i, p in l.pads do
			pads[i] = if p.sound == id then Dict.merge(p, { sound = Dict.None }) else p
		end
		return Dict.merge(l, { sounds = sounds, pads = pads })
	end)
	return true
end

local function setPad(i: number, pad: Types.Pad)
	edit(function(l)
		return Dict.merge(l, { pads = Dict.set(l.pads, i, pad) })
	end)
end

function Library.editPad(c: any): (boolean, string?)
	local lib = State.library()
	local p = lib.pads[c.Index]
	if not p then
		return false
	end
	local f = c.Field
	local patch: { [string]: any } = {}
	if f == "Label" then
		patch.label = clean(c.Text or "", 40)
	elseif f == "Kind" then
		local kind = if c.Text == "world" then "world" else "sfx"
		patch.kind = kind
		patch.sound = p.sound or (lib.sounds[1] and lib.sounds[1].id) or Dict.None
		patch.effect = p.effect or 1
		patch.volume = p.volume or 80
		patch.reach = p.reach or 1
		patch.intensity = p.intensity or 50
		patch.duration = p.duration or 3
	elseif f == "Sound" then
		local ok = false
		for _, s in lib.sounds do
			if s.id == c.Text then
				ok = true
			end
		end
		if not ok then
			return false, "That sound is gone."
		end
		patch.sound = c.Text
	elseif f == "Effect" then
		patch.effect = math.clamp(math.floor(c.Number or 1), 1, #Defaults.EFFECTS)
	elseif f == "Volume" then
		patch.volume = math.clamp(math.floor((c.Number or 80) / 5 + 0.5) * 5, 0, 100)
	elseif f == "Reach" then
		patch.reach = if c.Number == 2 then 2 else 1
	elseif f == "Intensity" then
		patch.intensity = math.clamp(math.floor((c.Number or 50) / 10 + 0.5) * 10, 0, 100)
	elseif f == "Duration" then
		patch.duration = math.clamp(math.floor(c.Number or 3), 1, 15)
	elseif f == "Cooldown" then
		patch.cooldown = math.clamp(math.floor(c.Number or 3), 0, 60)
	end
	setPad(c.Index, Dict.merge(p, patch))
	return true
end

function Library.assignPad(i: number): (boolean, string?)
	local lib = State.library()
	if lib.pads[i] and lib.pads[i].kind then
		return true
	end
	setPad(i, {
		label = "New pad",
		kind = "sfx",
		sound = lib.sounds[1] and lib.sounds[1].id,
		cooldown = 3,
		volume = 80,
		reach = 1,
	})
	return true
end

function Library.clearPad(i: number): (boolean, string?)
	setPad(i, { label = "", cooldown = 0 })
	return true
end

function Library.resetPads(): (boolean, string?)
	-- the default pads point at the default sounds: put any that went missing back
	edit(function(l)
		local sounds = l.sounds
		for _, d in Defaults.sounds() do
			local has = false
			for _, s in sounds do
				if s.id == d.id then
					has = true
				end
			end
			if not has then
				sounds = Dict.insert(sounds, d)
			end
		end
		return Dict.merge(l, { pads = Defaults.pads(), sounds = sounds })
	end)
	return true
end

return Library
