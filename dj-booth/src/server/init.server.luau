--!strict
-- HazaDJ server: starts the DJ deck's services in dependency order. The licence (ADR 0022) gates
-- them at the edges: a locked DJ deck takes only the owner's activation, opens for no one else, and
-- plays nothing; the background asset checks wait until the DJ deck is first unlocked.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LicensePolicy = require(ReplicatedStorage.HazaDJ.Shared.LicensePolicy)
local Services = script.Services

local Store = require(Services.Store)
local Roles = require(Services.Roles)
local License = require(Services.License)
local State = require(Services.State)
local Sync = require(Services.Sync)
local DjDeck = require(Services.DjDeck)
local Decks = require(Services.Decks)
local Probe = require(Services.Probe)
local Show = require(Services.Show)
local Commands = require(Services.Commands)

Store.start() -- loads the DJ deck document (or the Studio fixture) before anyone joins the state
Roles.start()
License.start() -- reads the licence record before anyone can open the DJ deck
Sync.start()
DjDeck.start()
Decks.start()
Show.start()
Commands.start()

local function onLicence(view: LicensePolicy.View)
	-- who may open the DJ deck follows the licence
	Roles.refreshAll()
	if LicensePolicy.unlocked(view) then
		Probe.start() -- runs once
	else
		-- locked again (a guest pass ended, a denial, the grace ran out): the room fades out
		task.spawn(Decks.fadeOutAll)
		local live = State.session().live
		if live then
			DjDeck.release(live)
		end
	end
end
License.onChanged(onLicence)
if License.unlocked() then
	Probe.start()
end

print(`[HazaDJ] DJ deck ready ({Store.status()}, licence {License.view().status})`)
