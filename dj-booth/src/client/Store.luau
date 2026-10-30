--!strict
-- The client's view of the DJ deck: the signals CharmSync patches from the server, wrapped as Vide
-- sources for the UI, plus local UI state that is only this player's (which tab, view mode).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.CosmicDJ.Packages
local Charm = require(Packages.Charm)
local CharmSync = require(Packages.CharmSync)
local Vide = require(Packages.Vide)
local VideCharm = require(Packages.VideCharm)
local Shared = ReplicatedStorage.CosmicDJ.Shared
local Defaults = require(Shared.Defaults)
local LicensePolicy = require(Shared.LicensePolicy)
local Types = require(Shared.Types)
local Net = require(script.Parent.Net)

local Store = {}

local player = Players.LocalPlayer

-- synced from the server
Store.libraryAtom = Charm.atom(Defaults.library())
Store.accessAtom = Charm.atom(Defaults.access())
Store.settingsAtom = Charm.atom(Defaults.settings())
Store.sessionAtom = Charm.atom(Defaults.session())
Store.stageAtom = Charm.atom(Defaults.stage())
Store.meAtom = Charm.atom({
	role = nil,
	canOpen = false,
	canEditLibrary = false,
	canEditAccess = false,
	canEditSettings = false,
	prefs = Defaults.prefs(),
} :: Types.Me)
-- the licence view (ADR 0022): only the owner is ever sent it; everyone else keeps "locked"
Store.licenseAtom = Charm.atom({ status = "locked" } :: LicensePolicy.View)
-- true once the first full state has arrived
Store.readyAtom = Charm.atom(false)

-- Vide sources for the UI (created once, inside the app's root scope)
Store.library = (nil :: any) :: () -> Types.Library
Store.access = (nil :: any) :: () -> Types.Access
Store.settings = (nil :: any) :: () -> Types.Settings
Store.session = (nil :: any) :: () -> Types.Session
Store.me = (nil :: any) :: () -> Types.Me
Store.license = (nil :: any) :: () -> LicensePolicy.View
Store.ready = (nil :: any) :: () -> boolean

function Store.bind()
	Store.library = VideCharm.useSignalState(Store.libraryAtom)
	Store.access = VideCharm.useSignalState(Store.accessAtom)
	Store.settings = VideCharm.useSignalState(Store.settingsAtom)
	Store.session = VideCharm.useSignalState(Store.sessionAtom)
	Store.me = VideCharm.useSignalState(Store.meAtom)
	Store.license = VideCharm.useSignalState(Store.licenseAtom)
	Store.ready = VideCharm.useSignalState(Store.readyAtom)
end

function Store.start()
	CharmSync.client.addSignals({
		library = Store.libraryAtom,
		access = Store.accessAtom,
		settings = Store.settingsAtom,
		session = Store.sessionAtom,
		stage = Store.stageAtom,
		license = Store.licenseAtom,
		[`me-{player.UserId}`] = Store.meAtom,
	})
	Net.Sync.On(function(payloads)
		CharmSync.client.patch(payloads)
		if not Store.readyAtom() then
			Store.readyAtom(true)
		end
	end)
	-- the server answers Ready with the full state; until one lands, ask again every 3 s
	task.spawn(function()
		while not Store.readyAtom() do
			Net.Ready.Fire(nil)
			task.wait(3)
		end
	end)
end

-- ── local UI state (this player only) ──
Store.tab = Vide.source("Decks") -- "Decks" | "Tracks" | "Access" | "Settings"
Store.view = Vide.source("window") -- "deck" | "window" | "full"
Store.open = Vide.source(false)

-- continuous controls being dragged here: shown from the local value until the server catches up
local liveLocal = Vide.source({} :: { [string]: { v: number, t: number } })
function Store.setLocal(key: string, v: number)
	local cur = Vide.untrack(liveLocal)
	local nextT = table.clone(cur)
	nextT[key] = { v = v, t = os.clock() }
	liveLocal(nextT)
end
-- a synced value, or the local one while it is fresh (0.5 s after the last drag step)
function Store.localOr(key: string, synced: number): number
	local l = liveLocal()[key]
	if l and os.clock() - l.t < 0.5 then
		return l.v
	end
	return synced
end

function Store.now(): number
	return workspace:GetServerTimeNow()
end

-- a deck's position right now (seconds into the track)
function Store.position(d: Types.Deck, t: Types.Track?): number
	if d.playing and t then
		return d.pos + (Store.now() - d.at) * t.speed * (1 + d.pitch)
	end
	return d.pos
end

return Store
