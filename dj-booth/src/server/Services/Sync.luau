--!strict
-- CharmSync wiring. Every player gets their own `me`, the session, the settings and the stage (each
-- client plays the decks itself, ADR 0021); players who may open the panel also get the library and
-- the access list. Access changes add or drop those two.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharmSync = require(ReplicatedStorage.CosmicDJ.Packages.CharmSync)
local Net = require(script.Parent.Parent.Net)
local Roles = require(script.Parent.Roles)
local State = require(script.Parent.State)

local Sync = {}

local ready: { [Player]: boolean } = {}
local granted: { [Player]: boolean } = {}
-- owners also get the licence view (ADR 0022); nobody else ever does
local licensed: { [Player]: boolean } = {}

local PANEL_KEYS = { "library", "access" }
local ROOM_KEYS = { "session", "settings", "stage" }

local function grant(player: Player)
	if not ready[player] then
		return
	end
	if not licensed[player] and Roles.isOwner(player) then
		licensed[player] = true
		CharmSync.server.addSignalsToClient(player, { license = State.license })
	end
	local canOpen = State.me(player.UserId)().canOpen
	if canOpen and not granted[player] then
		granted[player] = true
		CharmSync.server.addSignalsToClient(player, {
			library = State.library,
			access = State.access,
		})
	elseif not canOpen and granted[player] then
		granted[player] = nil
		CharmSync.server.removeSignalsFromClient(player, table.unpack(PANEL_KEYS))
	end
end

function Sync.start()
	CharmSync.server.connect(function(player: Player, payloads)
		Net.Sync.Fire(player, payloads)
	end)
	Net.Ready.On(function(player: Player)
		if ready[player] then
			-- a repeat Ready (the client retries until it has state): forget what was sent, so
			-- CharmSync sends every key again as an init
			granted[player] = nil
			CharmSync.server.removeSignalsFromClient(player, `me-{player.UserId}`, table.unpack(PANEL_KEYS))
			CharmSync.server.removeSignalsFromClient(player, table.unpack(ROOM_KEYS))
			if licensed[player] then
				licensed[player] = nil
				CharmSync.server.removeSignalsFromClient(player, "license")
			end
		end
		ready[player] = true
		CharmSync.server.addSignalsToClient(player, {
			[`me-{player.UserId}`] = State.me(player.UserId),
			session = State.session,
			settings = State.settings,
			stage = State.stage,
		})
		grant(player)
	end)
	Roles.onChanged(grant)
	Players.PlayerRemoving:Connect(function(player)
		ready[player] = nil
		granted[player] = nil
		licensed[player] = nil
		CharmSync.server.removeClient(player)
	end)
end

return Sync
