--!strict
-- HazaDJ server: starts the booth's services in dependency order.
local Services = script.Services

local Store = require(Services.Store)
local Roles = require(Services.Roles)
local Sync = require(Services.Sync)
local Booth = require(Services.Booth)
local Decks = require(Services.Decks)
local Probe = require(Services.Probe)
local Show = require(Services.Show)
local Commands = require(Services.Commands)

Store.start() -- loads the booth document (or the Studio fixture) before anyone joins the state
Roles.start()
Sync.start()
Booth.start()
Decks.start()
Probe.start()
Show.start()
Commands.start()

print(`[HazaDJ] booth ready ({Store.status()})`)
