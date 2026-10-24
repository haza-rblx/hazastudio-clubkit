--!strict
-- Who each player is to the booth: Owner (the experience's creator), a listed Resident or Guest,
-- or a guest let in by a group rank / game pass. Keeps each player's `me` signal (role, abilities,
-- panel prefs from ProfileStore) and the online list current.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Charm = require(ReplicatedStorage.HazaDJ.Packages.Charm)
local Shared = ReplicatedStorage.HazaDJ.Shared
local Defaults = require(Shared.Defaults)
local Dict = require(Shared.Dict)
local Fixture = require(Shared.Fixture)
local Rules = require(Shared.Rules)
local Types = require(Shared.Types)
local ProfileStore = require(script.Parent.Parent.ServerPackages.ProfileStore)
local State = require(script.Parent.State)
local Store = require(script.Parent.Store)

local Roles = {}

local PrefsStore = ProfileStore.New("HazaDJ_Prefs_v1", { prefs = Defaults.prefs() })
local profiles: { [Player]: any } = {}
local gateCache: { [number]: boolean } = {}
local changed: { (Player) -> () } = {}

function Roles.onChanged(fn: (Player) -> ())
	table.insert(changed, fn)
end

local ownerCache: { [number]: boolean } = {}

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
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
		return ok and rank == 255
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

function Roles.caps(player: Player): Rules.Caps
	return Rules.caps(Roles.roleOf(player))
end

local function refresh(player: Player)
	local role = Roles.roleOf(player)
	local caps = Rules.caps(role)
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
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
	end)
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end
	profiles[player] = profile
	setPrefs(player, Dict.merge(Defaults.prefs(), profile.Data.prefs or {}))
end

local function join(player: Player)
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
	local profile = profiles[player]
	if profile then
		profile:EndSession()
	end
	gateCache[player.UserId] = nil
	ownerCache[player.UserId] = nil
	State.dropMe(player.UserId)
end

function Roles.start()
	for _, p in Players:GetPlayers() do
		task.spawn(join, p)
	end
	Players.PlayerAdded:Connect(join)
	Players.PlayerRemoving:Connect(leave)

	-- people or gates changed: everyone's role may have too
	Charm.subscribe(function()
		return State.access().people
	end, Roles.refreshAll)
	Charm.subscribe(function()
		return State.access().gates
	end, Roles.recheckGates)

	-- guests whose time ran out lose access
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
	end)
end

function Roles.player(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

return Roles
