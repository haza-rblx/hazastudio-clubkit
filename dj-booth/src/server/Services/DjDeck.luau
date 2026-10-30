--!strict
-- Who is on the decks. The first player with access who touches a deck or a pad becomes the live
-- DJ; others can take over per the DJ deck's rule. Ends a set after the idle limit or the longest-set
-- limit, and keeps the stats (sets, time on the decks, last set).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.CosmicDJ.Shared
local Dict = require(Shared.Dict)
local Rules = require(Shared.Rules)
local Net = require(script.Parent.Parent.Net)
local Roles = require(script.Parent.Roles)
local State = require(script.Parent.State)

local DjDeck = {}

local MAX_SET = { 0, 30 * 60, 3600, 2 * 3600 }
local IDLE = { 0, 5 * 60, 10 * 60, 15 * 60 }

local lastInput = 0
local liveChanged: { (number?, number?) -> () } = {}

function DjDeck.onLiveChanged(fn: (number?, number?) -> ())
	table.insert(liveChanged, fn)
end

local function stats(userId: number, since: number?)
	if not since then
		return
	end
	local key = tostring(userId)
	State.update(State.access, function(a)
		local p = a.people[key]
		if not p then
			return a
		end
		return Dict.merge(a, {
			people = Dict.set(
				a.people,
				key,
				Dict.merge(p, {
					seconds = p.seconds + math.max(0, os.time() - since),
					lastSet = os.time(),
				})
			),
		})
	end)
end

local function setLive(userId: number?)
	local s = State.session()
	if s.live == userId then
		return
	end
	local prev = s.live
	if prev then
		stats(prev, s.liveSince)
	end
	State.session(Dict.merge(s, { live = userId, liveSince = if userId then os.time() else nil }))
	if userId then
		local key = tostring(userId)
		State.update(State.access, function(a)
			local p = a.people[key]
			if not p then
				return a
			end
			return Dict.merge(
				a,
				{ people = Dict.set(a.people, key, Dict.merge(p, { sets = p.sets + 1, lastSet = os.time() })) }
			)
		end)
	end
	for _, fn in liveChanged do
		task.spawn(fn, userId, prev)
	end
end

-- a player wants to use the decks or pads: returns whether they may, and why not
function DjDeck.claim(player: Player): (boolean, string?)
	local role = Roles.roleOf(player)
	if not Rules.caps(role).canOpen then
		return false, "You don't have access to the DJ deck."
	end
	local live = State.session().live
	if live == player.UserId then
		lastInput = os.clock()
		return true
	end
	local liveHere = live and Players:GetPlayerByUserId(live)
	if liveHere and not Rules.canTakeOver(role, State.access().gates.takeOver) then
		return false, liveHere.DisplayName .. " is on the decks."
	end
	if liveHere then
		Net.Toast.Fire(liveHere, player.DisplayName .. " took over the DJ deck.")
	end
	setLive(player.UserId)
	lastInput = os.clock()
	return true
end

function DjDeck.release(userId: number)
	if State.session().live == userId then
		setLive(nil)
	end
end

function DjDeck.touch()
	lastInput = os.clock()
end

function DjDeck.start()
	Players.PlayerRemoving:Connect(function(p)
		DjDeck.release(p.UserId)
	end)
	-- idle and longest-set limits
	task.spawn(function()
		while true do
			task.wait(5)
			local s = State.session()
			local settings = State.settings()
			if s.live and Players:GetPlayerByUserId(s.live) then
				local idle = IDLE[settings.idle] or 0
				local maxSet = MAX_SET[settings.maxSet] or 0
				local p = Players:GetPlayerByUserId(s.live) :: Player
				if idle > 0 and os.clock() - lastInput > idle then
					setLive(nil)
				elseif maxSet > 0 and s.liveSince and os.time() - s.liveSince > maxSet then
					Net.Toast.Fire(p, "Your set reached the DJ deck's time limit.")
					setLive(nil)
				end
			end
		end
	end)
end

return DjDeck
