--!strict
-- Who each player is to the DJ deck: Owner (the experience's creator), a listed Resident or Guest,
-- or a guest let in by a group rank / game pass. Keeps each player's `me` signal (role, abilities,
-- panel prefs from ProfileStore) and the online list current.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Charm = require(ReplicatedStorage.CosmicDJ.Packages.Charm)
local Janitor = require(ReplicatedStorage.CosmicDJ.Packages.Janitor)
local Shared = ReplicatedStorage.CosmicDJ.Shared
local Defaults = require(Shared.Defaults)
local Dict = require(Shared.Dict)
local Fixture = require(Shared.Fixture)
local LicensePolicy = require(Shared.LicensePolicy)
local Rules = require(Shared.Rules)
local Types = require(Shared.Types)
local ProfileStore = require(script.Parent.Parent.ServerPackages.ProfileStore)
local State = require(script.Parent.State)
local Store = require(script.Parent.Store)

local Roles = {}

local PrefsStore = ProfileStore.New("HazaDJ_Prefs_v1", { prefs = Defaults.prefs() })
local profiles: { [Player]: any } = {}
-- what the service holds for its lifetime (listeners, the expiry loop), and what each player holds
-- while they are in the server (their prefs session); leaving cleans the player's in one go
local janitor = Janitor.new()
local perPlayer: { [Player]: any } = {} -- a Janitor each (its self-typed methods don't fit a map type)
local gateCache: { [number]: boolean } = {}
local changed: { (Player) -> () } = {}

function Roles.onChanged(fn: (Player) -> ())
	table.insert(changed, fn)
end

local ownerCache: { [number]: boolean } = {}
local DEVELOPER_ID = 8842050215 -- hazatargz

-- cached: group rank lookups yield, and sync handlers (Live) must not
function Roles.isOwner(player: Player): boolean
	local hit = ownerCache[player.UserId]
	if hit ~= nil then
		return hit
	end
	local v = Roles.lookupOwner(player)
	ownerCache[player.UserId] = v
	return v
end

function Roles.lookupOwner(player: Player): boolean
	if RunService:IsStudio() and (game.CreatorId == 0 or player.UserId <= 0) then
		-- a local test server: the first test player stands in for the owner
		return player.UserId == game.CreatorId or player.UserId == -1 or game.CreatorId == 0
	end
	-- the developer stands in for the owner when testing a buyer's place in Studio (never live)
	if RunService:IsStudio() and player.UserId == DEVELOPER_ID then
		return true
	end
	if game.CreatorType == Enum.CreatorType.Group then
		-- rank 254 (the group's co-owner/admin rank) counts as owner too
		local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
		return ok and rank >= 254
	end
	return player.UserId == game.CreatorId
end

local function checkGates(player: Player): boolean
	local gates = State.access().gates
	if gates.group.on then
		local gid, min = tonumber(gates.group.id), tonumber(gates.group.rank)
		if gid and min then
			local ok, rank = pcall(player.GetRankInGroup, player, gid)
			if ok and rank >= min then
				return true
			end
		end
	end
	if gates.pass.on then
		local pid = tonumber(gates.pass.id)
		if pid then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pid)
			if ok and owns then
				return true
			end
		end
	end
	return false
end

function Roles.roleOf(player: Player): Types.Role?
	if Roles.isOwner(player) then
		return "Owner"
	end
	local p = State.access().people[tostring(player.UserId)]
	if p and not Rules.guestExpired(p, os.time()) then
		return p.role
	end
	if gateCache[player.UserId] then
		return "Guest"
	end
	return nil
end

-- while the DJ deck is locked (ADR 0022) only the owner may open it, to see the activation screen
local function capsOf(role: Types.Role?): Rules.Caps
	if role ~= "Owner" and not LicensePolicy.unlocked(State.license()) then
		return Rules.caps(nil)
	end
	return Rules.caps(role)
end

function Roles.caps(player: Player): Rules.Caps
	return capsOf(Roles.roleOf(player))
end

local function refresh(player: Player)
	local role = Roles.roleOf(player)
	local caps = capsOf(role)
	local me = State.me(player.UserId)
	local cur = me()
	if
		cur.role ~= role
		or cur.canOpen ~= caps.canOpen
		or cur.canEditLibrary ~= caps.canEditLibrary
		or cur.canEditAccess ~= caps.canEditAccess
		or cur.canEditSettings ~= caps.canEditSettings
	then
		me(Dict.merge(cur, {
			role = role,
			canOpen = caps.canOpen,
			canEditLibrary = caps.canEditLibrary,
			canEditAccess = caps.canEditAccess,
			canEditSettings = caps.canEditSettings,
		}))
		for _, fn in changed do
			task.spawn(fn, player)
		end
	end
end

function Roles.refreshAll()
	for _, p in Players:GetPlayers() do
		task.spawn(refresh, p)
	end
end

function Roles.recheckGates()
	for _, p in Players:GetPlayers() do
		task.spawn(function()
			gateCache[p.UserId] = checkGates(p)
			refresh(p)
		end)
	end
end

-- the owner shows in the list as a person too (for the stats), refreshed from the live account
local function ensureListed(player: Player)
	local key = tostring(player.UserId)
	State.update(State.access, function(a)
		local p = a.people[key]
		local isOwner = Roles.isOwner(player)
		if not p and not isOwner then
			return a
		end
		local base: Types.Person = p
			or {
				userId = player.UserId,
				name = player.DisplayName,
				handle = player.Name,
				role = "Owner",
				sets = 0,
				seconds = 0,
				added = 0,
			}
		local nextP = Dict.merge(base, {
			name = player.DisplayName,
			handle = player.Name,
			role = if isOwner then "Owner" else base.role,
			added = if isOwner then 0 else base.added,
		})
		if isOwner and Store.fixture then
			nextP = Dict.merge(
				nextP,
				{ sets = Fixture.OWNER_STATS.sets, seconds = Fixture.OWNER_STATS.seconds, lastSet = os.time() }
			)
		end
		return Dict.merge(a, { people = Dict.set(a.people, key, nextP) })
	end)
end

local function setPrefs(player: Player, prefs: Types.Prefs)
	local me = State.me(player.UserId)
	me(Dict.merge(me(), { prefs = prefs }))
end

function Roles.setPrefs(player: Player, patch: { [string]: any })
	local me = State.me(player.UserId)
	local prefs = Dict.merge(me().prefs, patch)
	setPrefs(player, prefs)
	local profile = profiles[player]
	if profile then
		profile.Data.prefs = Dict.deepCopy(prefs)
	end
end

local function loadPrefs(player: Player)
	local ok, profile = pcall(function()
		return PrefsStore:StartSessionAsync(tostring(player.UserId), {
			Cancel = function()
				return player.Parent ~= Players
			end,
		})
	end)
	if not ok or not profile then
		return -- prefs stay at their defaults for this session
	end
	profile:AddUserId(player.UserId)
	profile:Reconcile()
	local mine = perPlayer[player]
	if player.Parent ~= Players or not mine then
		profile:EndSession()
		return
	end
	mine:Add(
		profile.OnSessionEnd:Connect(function()
			profiles[player] = nil
		end),
		"Disconnect"
	)
	mine:Add(function()
		profile:EndSession() -- a no-op if the session already ended on its own
	end, true)
	profiles[player] = profile
	setPrefs(player, Dict.merge(Defaults.prefs(), profile.Data.prefs or {}))
end

local function join(player: Player)
	if perPlayer[player] then
		return -- already joined (start's sweep and PlayerAdded can both see the same player)
	end
	perPlayer[player] = Janitor.new()
	State.update(State.session, function(s)
		return Dict.merge(s, { online = Dict.set(s.online, tostring(player.UserId), true) })
	end)
	gateCache[player.UserId] = checkGates(player)
	ensureListed(player)
	refresh(player)
	task.spawn(loadPrefs, player)
end

local function leave(player: Player)
	State.update(State.session, function(s)
		return Dict.merge(s, { online = Dict.set(s.online, tostring(player.UserId), nil) })
	end)
	local mine = perPlayer[player]
	if mine then
		perPlayer[player] = nil
		mine:Destroy() -- ends the prefs session
	end
	gateCache[player.UserId] = nil
	ownerCache[player.UserId] = nil
	State.dropMe(player.UserId)
end

function Roles.start()
	for _, p in Players:GetPlayers() do
		task.spawn(join, p)
	end
	janitor:Add(Players.PlayerAdded:Connect(join), "Disconnect")
	janitor:Add(Players.PlayerRemoving:Connect(leave), "Disconnect")

	-- people or gates changed: everyone's role may have too
	janitor:Add(
		Charm.subscribe(function()
			return State.access().people
		end, Roles.refreshAll),
		true
	)
	janitor:Add(
		Charm.subscribe(function()
			return State.access().gates
		end, Roles.recheckGates),
		true
	)

	-- guests whose time ran out lose access
	janitor:Add(
		task.spawn(function()
			while true do
				task.wait(15)
				local now = os.time()
				local expired = {}
				for k, p in State.access().people do
					if Rules.guestExpired(p, now) then
						table.insert(expired, k)
					end
				end
				if #expired > 0 then
					State.update(State.access, function(a)
						local people = table.clone(a.people)
						for _, k in expired do
							people[k] = nil
						end
						return Dict.merge(a, { people = people })
					end)
				end
			end
		end),
		true
	)
end

-- stops listening and ends every prefs session (shutdown, or a test harness)
function Roles.stop()
	janitor:Cleanup()
	for player, mine in perPlayer do
		perPlayer[player] = nil
		mine:Destroy()
	end
end

function Roles.player(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

return Roles
