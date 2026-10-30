--!strict
-- The server's state: Charm signals the rest of the server mutates and CharmSync replicates.
-- Values are frozen in Studio (Charm's `frozen` flag), so every write goes through Dict helpers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.CosmicDJ.Shared
local Charm = require(ReplicatedStorage.CosmicDJ.Packages.Charm)
local Types = require(Shared.Types)
local Defaults = require(Shared.Defaults)

local State = {}

State.library = Charm.atom(Defaults.library())
State.access = Charm.atom(Defaults.access())
State.settings = Charm.atom(Defaults.settings())
State.session = Charm.atom(Defaults.session())
-- the tracks on the decks and in the queue, for every player: each client plays the decks itself
-- (ADR 0021), so listeners who never open the panel still need those tracks' asset, length and gain
State.stage = Charm.atom(Defaults.stage())
-- the licence as owners may see it (ADR 0022): a LicensePolicy.View, never the secret
State.license = Charm.atom({ status = "locked" } :: any)

-- tracks the live DJ is about to play (Net.Hint), newest first; reach everyone through the stage
State.hints = Charm.atom({} :: { string })
State.HINT_MAX = 3

Charm.effect(function()
	local s = State.session()
	local lib = State.library()
	local hints = State.hints()
	local tracks: { [string]: Types.Track } = {}
	local function add(id: string?)
		local t = if id then lib.tracks[id] else nil
		if t then
			tracks[t.id] = t
		end
	end
	for _, d in s.decks do
		add(d.trackId)
	end
	for _, e in s.queue do
		add(e.trackId)
	end
	local live = {}
	for _, id in hints do
		if lib.tracks[id] then
			add(id)
			table.insert(live, id)
		end
	end
	State.stage({ tracks = tracks, hints = live })
end)

-- per-player "me" (role, abilities, prefs), keyed by userId
local mes: { [number]: any } = {}

function State.me(userId: number): any
	local a = mes[userId]
	if not a then
		a = Charm.atom({
			role = nil,
			canOpen = false,
			canEditLibrary = false,
			canEditAccess = false,
			canEditSettings = false,
			prefs = Defaults.prefs(),
		} :: Types.Me)
		mes[userId] = a
	end
	return a
end

function State.dropMe(userId: number)
	mes[userId] = nil
end

-- shorthand updaters
function State.update<T>(atom: any, fn: (T) -> T)
	atom(fn(atom()))
end

function State.now(): number
	return workspace:GetServerTimeNow()
end

return State
