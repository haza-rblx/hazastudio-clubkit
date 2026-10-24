--!strict
-- The server's state: Charm signals the rest of the server mutates and CharmSync replicates.
-- Values are frozen in Studio (Charm's `frozen` flag), so every write goes through Dict helpers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.HazaDJ.Shared
local Charm = require(ReplicatedStorage.HazaDJ.Packages.Charm)
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

Charm.effect(function()
	local s = State.session()
	local lib = State.library()
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
	State.stage({ tracks = tracks })
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
