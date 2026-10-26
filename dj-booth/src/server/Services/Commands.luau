--!strict
-- The one door in: every client request arrives here (Blink validates the shapes), is checked
-- against the sender's role and a rate limit, and is handed to the service that owns it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.HazaDJ.Shared
local Dict = require(Shared.Dict)
local QueueLogic = require(Shared.Queue)
local Rules = require(Shared.Rules)
local Types = require(Shared.Types)
local Booth = require(script.Parent.Booth)
local Decks = require(script.Parent.Decks)
local DeckBrakeConfig = require(Shared.DeckBrakeConfig)
local Library = require(script.Parent.Library)
local License = require(script.Parent.License)
local Net = require(script.Parent.Parent.Net)
local Pads = require(script.Parent.Pads)
local Probe = require(script.Parent.Probe)
local Roles = require(script.Parent.Roles)
local State = require(script.Parent.State)

local Commands = {}

type Result = { Ok: boolean, Message: string?, Id: string? }

-- a token bucket per player: 20 requests a second, bursts of 40
local buckets: { [Player]: { tokens: number, at: number } } = {}
local function allow(player: Player, cost: number?): boolean
	local b = buckets[player]
	local now = os.clock()
	if not b then
		b = { tokens = 40, at = now }
		buckets[player] = b
	end
	b.tokens = math.min(40, b.tokens + (now - b.at) * 20)
	b.at = now
	if b.tokens < (cost or 1) then
		return false
	end
	b.tokens -= cost or 1
	return true
end

local function ok(id: string?): Result
	return { Ok = true, Id = id }
end
local function no(message: string?): Result
	return { Ok = false, Message = message }
end
local function wrap(success: boolean, message: string?, id: string?): Result
	return { Ok = success, Message = message, Id = id }
end

local LIBRARY = {
	TrackAdd = true,
	TrackAddBatch = true,
	TrackEdit = true,
	TrackRemove = true,
	TrackInPlaylist = true,
	TrackMove = true,
	PlaylistCreate = true,
	PlaylistEdit = true,
	PlaylistDelete = true,
	SoundAdd = true,
	SoundRemove = true,
	PadEdit = true,
	PadAssign = true,
	PadClear = true,
	PadsReset = true,
}
-- the licence's own commands: the only ones a locked booth takes (License checks the owner)
local LICENSE = { Activate = true, RedeemGuest = true }
local ACCESS = { PersonAdd = true, PersonEdit = true, PersonRemove = true, GateEdit = true, TakeOverPolicy = true }
-- what plays: these claim the booth first (the queue feeds Auto mix, so it counts)
local DECKS = {
	Load = true,
	Deck = true,
	HotCue = true,
	Seek = true,
	PadPress = true,
	TakeBooth = true,
	QueueAdd = true,
	QueueRemove = true,
	QueueMove = true,
	QueueClear = true,
	QueueAll = true,
	Automix = true,
}

local function resolveUser(who: string): (number?, string?, string?)
	local text = string.match(who, "^%s*@?(.-)%s*$") or ""
	local id = tonumber(text)
	if id then
		local okName, name = pcall(Players.GetNameFromUserIdAsync, Players, id)
		if okName and name then
			return id, name, name
		end
		return nil
	end
	local okId, uid = pcall(Players.GetUserIdFromNameAsync, Players, text)
	if okId and uid then
		local okName, name = pcall(Players.GetNameFromUserIdAsync, Players, uid)
		return uid, if okName then name else text, if okName then name else text
	end
	return nil
end

local function displayName(userId: number, fallback: string): string
	local p = Players:GetPlayerByUserId(userId)
	return if p then p.DisplayName else fallback
end

local handlers: { [string]: (Player, any) -> Result } = {}

handlers.TrackAdd = function(_, c)
	return wrap(Library.addTrack(c))
end
handlers.TrackAddBatch = function(_, c)
	return wrap(Library.addBatch(c))
end
handlers.TrackEdit = function(_, c)
	return wrap(Library.editTrack(c))
end
handlers.TrackRemove = function(_, c)
	return wrap(Library.removeTrack(c.Id))
end
handlers.TrackInPlaylist = function(_, c)
	return wrap(Library.trackInPlaylist(c.Track, c.Playlist, c.On))
end
handlers.TrackMove = function(_, c)
	return wrap(Library.moveTrack(c.Playlist, c.Track, c.By))
end
handlers.PlaylistCreate = function()
	return wrap(Library.createPlaylist())
end
handlers.PlaylistEdit = function(_, c)
	return wrap(Library.editPlaylist(c))
end
handlers.PlaylistDelete = function(_, c)
	return wrap(Library.deletePlaylist(c.Id))
end
handlers.SoundAdd = function(_, c)
	return wrap(Library.addSound(c.AssetId))
end
handlers.SoundRemove = function(_, c)
	return wrap(Library.removeSound(c.Id))
end
handlers.PadEdit = function(_, c)
	return wrap(Library.editPad(c))
end
handlers.PadAssign = function(_, c)
	return wrap(Library.assignPad(c.Index))
end
handlers.PadClear = function(_, c)
	return wrap(Library.clearPad(c.Index))
end
handlers.PadsReset = function()
	return wrap(Library.resetPads())
end

handlers.PersonAdd = function(_, c)
	local id, name, handle = resolveUser(c.Who)
	if not id then
		return no("No Roblox user by that name or ID.")
	end
	local key = tostring(id)
	local a = State.access()
	if a.people[key] then
		return no("@" .. a.people[key].handle .. " is already on the list.")
	end
	local maxAdded = 0
	for _, p in a.people do
		maxAdded = math.max(maxAdded, p.added)
	end
	local now = os.time()
	local person: Types.Person = {
		userId = id,
		name = displayName(id, name :: string),
		handle = handle :: string,
		role = c.Role,
		since = now,
		ends = if c.Role == "Guest" then c.Ends else nil,
		endsAt = if c.Role == "Guest" then Rules.guestEndsAt(c.Ends, now) else nil,
		sets = 0,
		seconds = 0,
		added = maxAdded + 1,
	}
	State.update(State.access, function(cur)
		return Dict.merge(cur, { people = Dict.set(cur.people, key, person) })
	end)
	return ok(key)
end
handlers.PersonEdit = function(_, c)
	local key = tostring(c.UserId)
	local p = State.access().people[key]
	if not p or p.role == "Owner" then
		return no("That person isn't on the list.")
	end
	local patch: { [string]: any } = {}
	if c.Role then
		patch.role = c.Role
		patch.since = p.since or os.time()
		if c.Role == "Guest" then
			patch.ends = p.ends or 1
			patch.endsAt = Rules.guestEndsAt(p.ends or 1, os.time()) or Dict.None
		else
			patch.ends = Dict.None
			patch.endsAt = Dict.None
		end
	end
	if c.Ends and (c.Role or p.role) == "Guest" then
		patch.ends = c.Ends
		patch.endsAt = Rules.guestEndsAt(c.Ends, os.time()) or Dict.None
	end
	State.update(State.access, function(cur)
		return Dict.merge(cur, { people = Dict.set(cur.people, key, Dict.merge(cur.people[key], patch)) })
	end)
	return ok()
end
handlers.PersonRemove = function(_, c)
	local key = tostring(c.UserId)
	local p = State.access().people[key]
	if not p or p.role == "Owner" then
		return no("That person isn't on the list.")
	end
	State.update(State.access, function(cur)
		return Dict.merge(cur, { people = Dict.set(cur.people, key, nil) })
	end)
	Booth.release(c.UserId)
	return ok()
end
handlers.GateEdit = function(_, c)
	State.update(State.access, function(cur)
		local key = if c.Gate == "Group" then "group" else "pass"
		local g = table.clone(cur.gates[key]) :: any
		if c.On ~= nil then
			g.on = c.On
		end
		if c.Value ~= nil then
			g.id = string.gsub(c.Value, "%D", "")
		end
		if c.Rank ~= nil and key == "group" then
			g.rank = string.gsub(c.Rank, "%D", "")
		end
		return Dict.merge(cur, { gates = Dict.set(cur.gates, key, g) })
	end)
	return ok()
end
handlers.TakeOverPolicy = function(_, c)
	State.update(State.access, function(cur)
		return Dict.merge(cur, { gates = Dict.merge(cur.gates, { takeOver = c.Policy }) })
	end)
	return ok()
end

handlers.SettingsSave = function(_, c)
	local v = table.clone(c.Values)
	-- a brake preset must exist (or "" = instant stop); anything else falls back to the default
	if v.deckOff ~= "" and DeckBrakeConfig.Presets[v.deckOff] == nil then
		v.deckOff = DeckBrakeConfig.Preset
	end
	State.settings(v)
	return ok()
end

handlers.PrefsSet = function(player, c)
	local patch: { [string]: any } = {}
	if c.PanelSize then
		patch.panelSize = c.PanelSize
	end
	if c.ReduceMotion ~= nil then
		patch.reduceMotion = c.ReduceMotion
	end
	if c.Hotkey then
		patch.hotkey = c.Hotkey
	end
	if c.View == "deck" or c.View == "window" or c.View == "full" then
		patch.view = c.View
	end
	Roles.setPrefs(player, patch)
	return ok()
end

-- a loaded track starts playing straight away (owner, 2026-10-23)
handlers.Load = function(_, c)
	local loaded, err = Decks.load(c.Deck, c.Track)
	if not loaded then
		return wrap(loaded, err)
	end
	return wrap(Decks.play(c.Deck))
end
handlers.QueueAdd = function(_, c)
	if not State.library().tracks[c.Track] then
		return no("That track is gone.")
	end
	State.update(State.session, function(s)
		return Dict.merge(s, { queue = QueueLogic.add(s.queue, c.Track) })
	end)
	return ok()
end
handlers.QueueRemove = function(_, c)
	State.update(State.session, function(s)
		return Dict.merge(s, { queue = QueueLogic.remove(s.queue, c.Key) })
	end)
	return ok()
end
handlers.QueueMove = function(_, c)
	State.update(State.session, function(s)
		return Dict.merge(s, { queue = QueueLogic.move(s.queue, c.Key, c.By) })
	end)
	return ok()
end
handlers.QueueClear = function()
	State.update(State.session, function(s)
		return Dict.merge(s, { queue = {} })
	end)
	return ok()
end
-- a playlist's tracks in order, or shuffled when the playlist says so; tracks that are gone are skipped
handlers.QueueAll = function(_, c)
	local lib = State.library()
	local found = nil
	for _, pl in lib.playlists do
		if pl.id == c.Playlist then
			found = pl
			break
		end
	end
	if not found then
		return no("That playlist is gone.")
	end
	local ids = {}
	for _, id in found.tracks do
		if lib.tracks[id] then
			table.insert(ids, id)
		end
	end
	if #ids == 0 then
		return no("That playlist is empty.")
	end
	if found.shuffle then
		ids = QueueLogic.shuffled(ids)
	end
	State.update(State.session, function(s)
		return Dict.merge(s, { queue = QueueLogic.addMany(s.queue, ids) })
	end)
	return ok()
end
handlers.Automix = function(_, c)
	State.update(State.session, function(s)
		return Dict.merge(s, { automix = c.On })
	end)
	return ok()
end
handlers.Deck = function(_, c)
	local n, a = c.Deck, c.Action
	if a == "Play" then
		return wrap(Decks.play(n))
	elseif a == "Pause" then
		return wrap(Decks.pause(n, true))
	elseif a == "CueDown" then
		return wrap(Decks.cueDown(n, true))
	elseif a == "CueUp" then
		return wrap(Decks.cueUp(n))
	elseif a == "Sync" then
		return wrap(Decks.sync(n))
	elseif a == "Eject" then
		return wrap(Decks.eject(n, true))
	end
	return no()
end
handlers.HotCue = function(_, c)
	return wrap(Decks.hotCue(c.Deck, c.N, c.Clear))
end
handlers.Seek = function(_, c)
	return wrap(Decks.seek(c.Deck, c.Seconds))
end
handlers.PadPress = function(_, c)
	return wrap(Pads.press(c.Index))
end
handlers.TakeBooth = function()
	return ok()
end
handlers.EndSet = function(player)
	if State.session().live ~= player.UserId and not Roles.caps(player).canEditAccess then
		return no("Only the live DJ can end the set.")
	end
	task.spawn(Decks.fadeOutAll)
	Booth.release(State.session().live or player.UserId)
	return ok()
end

handlers.Activate = function(player, c)
	local r = License.activate(player, c.Code)
	return wrap(r.Ok, r.Message)
end
handlers.RedeemGuest = function(player, c)
	local r = License.redeem(player, c.Code)
	return wrap(r.Ok, r.Message)
end

function Commands.run(player: Player, c: any): Result
	if not allow(player) then
		return no("Slow down a little.")
	end
	local kind = c.Kind
	-- the licence's own commands go straight to License, which only lets the place owner through
	if not LICENSE[kind] then
		if not License.unlocked() then
			return no("The booth isn't activated yet.")
		end
		local caps = Roles.caps(player)
		-- anyone may keep their own panel prefs; everything else needs the booth
		if kind ~= "PrefsSet" and not caps.canOpen then
			return no("You don't have access to the booth.")
		elseif LIBRARY[kind] and not caps.canEditLibrary then
			return no("Only residents and the owner can edit the library.")
		elseif ACCESS[kind] and not caps.canEditAccess then
			return no("Only the owner can change who has access.")
		elseif kind == "SettingsSave" and not caps.canEditSettings then
			return no("Only the owner can change the booth's settings.")
		elseif DECKS[kind] then
			local okClaim, why = Booth.claim(player)
			if not okClaim then
				return no(why)
			end
		end
	end
	local h = handlers[kind]
	if not h then
		return no("Unknown request.")
	end
	local success, result = pcall(h, player, c)
	if not success then
		warn("[HazaDJ] " .. kind .. " failed: " .. tostring(result))
		return no("Something went wrong.")
	end
	return result
end

function Commands.start()
	Net.Do.On(Commands.run)
	Net.Probe.On(function(player, ids)
		if not License.unlocked() or not Roles.caps(player).canEditLibrary or not allow(player, 4) then
			return {}
		end
		return Probe.many(ids)
	end)
	Net.Live.On(function(player, deck, param, value)
		if not License.unlocked() or not allow(player, 0.25) then
			return
		end
		if not Booth.claim(player) then
			return
		end
		Decks.live(deck, param, value)
	end)
	Net.Nudge.On(function(player, deck, delta)
		if not License.unlocked() or State.session().live ~= player.UserId then
			return
		end
		Booth.touch()
		Decks.nudge(deck, delta)
	end)
	Players.PlayerRemoving:Connect(function(p)
		buckets[p] = nil
	end)
end

return Commands
