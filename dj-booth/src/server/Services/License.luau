--!strict
-- The game's licence (ADR 0022). Keeps the licence record in its own DataStore (the secret never
-- leaves the server, and a copied place file carries none of it), confirms it with the licence
-- server every 30 minutes, and lets the place owner activate a code or redeem a guest pass. The
-- rules live in LicensePolicy; State.license holds what owners may see.
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Janitor = require(ReplicatedStorage.HazaDJ.Packages.Janitor)
local LicensePolicy = require(ReplicatedStorage.HazaDJ.Shared.LicensePolicy)
local LicenseApi = require(script.Parent.LicenseApi)
local Roles = require(script.Parent.Roles)
local State = require(script.Parent.State)
local Stamp = require(script.Parent.Parent.Stamp)
local Store = require(script.Parent.Store)

type Record = LicensePolicy.Record
type View = LicensePolicy.View

local License = {}

local STORE_NAME = "HazaDJ_License_v1" -- versioned: a record format change gets a new name
local KEY = "license"
local TOPIC = "HazaDJ_License_v1_changed"
local TICK = 60 -- re-judge the record this often (a guest pass ends, the grace runs out)

local janitor = Janitor.new()
local store: DataStore? = nil
local record: Record? = nil
-- per userId, kept for the server's life: rejoining does not hand out a fresh budget
local attempts: { [number]: { number } } = {}
local changed: { (View) -> () } = {}
local busy = false
local started = false
-- set at start() when this download was stamped for another game; nil otherwise
local gameMismatch: string? = nil

export type Result = { Ok: boolean, Message: string? }

local MESSAGES: { [string]: string } = {
	invalid_code = "That code isn't valid. Copy it again from your dashboard.",
	code_used = "That code has already been used.",
	license_mismatch = "That code belongs to a different djX download.",
	universe_mismatch = "That code is linked to another experience.",
	owner_mismatch = "That code belongs to a different owner.",
	revoked = "That license has been revoked.",
	expired = "That guest pass has ended.",
	wrong_game = "This copy of djX was downloaded for a different experience. Download your own copy from your Hazastudio account.",
}

-- this place as the game check sees it
local function here(): LicensePolicy.GameIdentity
	return {
		universeId = game.GameId,
		ownerId = game.CreatorId,
		ownerType = if game.CreatorType == Enum.CreatorType.Group then "Group" else "User",
	}
end

local function view(): View
	if Store.fixture then
		-- the Studio demo fixture (parity checks) runs unlocked
		return { status = "active", kind = "full" }
	end
	if gameMismatch then
		return { status = "denied", reason = gameMismatch }
	end
	return LicensePolicy.evaluate(record, os.time())
end

-- re-judge and publish; listeners hear only real status changes
local function refresh()
	local v = view()
	-- a guest pass ends on the second, not on the next tick
	if v.status == "guest" and v.secondsLeft then
		janitor:Add(
			task.delay(v.secondsLeft + 0.5, function()
				janitor:RemoveNoClean("guestEnd") -- this thread is the one stored there
				refresh()
			end),
			true,
			"guestEnd"
		)
	else
		janitor:Remove("guestEnd")
	end
	local cur = State.license()
	if
		cur.status ~= v.status
		or cur.expiresAt ~= v.expiresAt
		or cur.reason ~= v.reason
		or (cur.secondsLeft or 0) // 60 ~= (v.secondsLeft or 0) // 60
	then
		State.license(v)
		if cur.status ~= v.status then
			for _, fn in changed do
				task.spawn(fn, v)
			end
		end
	end
end

local function read(): Record?
	if not store then
		return record
	end
	local ok, value = pcall(function()
		return (store :: DataStore):GetAsync(KEY)
	end)
	if not ok then
		warn("[HazaDJ] could not read the licence record: " .. tostring(value))
		return record
	end
	return if type(value) == "table" then value :: Record else nil
end

local function write(rec: Record)
	record = rec
	if not store then
		return
	end
	local ok, err = pcall(function()
		return (store :: DataStore):UpdateAsync(KEY, function(old: Record?)
			return LicensePolicy.merge(old, rec)
		end)
	end)
	if not ok then
		warn("[HazaDJ] could not save the licence record: " .. tostring(err))
		return
	end
	pcall(MessagingService.PublishAsync, MessagingService, TOPIC, { job = game.JobId })
end

local function verify()
	local rec = record
	if not rec then
		return
	end
	local answer = LicenseApi.verify(rec.secret)
	if answer.kind == "unreachable" then
		refresh()
		return
	end
	write(LicensePolicy.applyVerify(rec, answer, os.time()))
	refresh()
end

-- the owner pasted a code (an activation code, or a guest pass when `guest`)
local function submit(player: Player, raw: string, guest: boolean): Result
	if not Roles.isOwner(player) then
		return { Ok = false, Message = "Only the place owner can activate the DJ deck." }
	end
	if gameMismatch then
		return { Ok = false, Message = MESSAGES.wrong_game }
	end
	if game.GameId == 0 then
		return { Ok = false, Message = "Publish the place first, then activate it." }
	end
	local okAttempt, kept = LicensePolicy.allowAttempt(attempts[player.UserId] or {}, os.time())
	attempts[player.UserId] = kept
	if not okAttempt then
		return { Ok = false, Message = "Too many tries. Wait a few minutes and try again." }
	end
	local code = LicensePolicy.normalizeCode(raw)
	if not code then
		return { Ok = false, Message = MESSAGES.invalid_code }
	end
	local current = view()
	if guest and current.status == "active" then
		return { Ok = false, Message = "This game already has a full license." }
	end
	if busy then
		return { Ok = false, Message = "Already checking a code. One moment." }
	end
	busy = true
	local called, result = pcall(function()
		return if guest then LicenseApi.redeem(code, player.UserId) else LicenseApi.activate(code, player.UserId)
	end)
	busy = false
	local answer: LicensePolicy.Answer = if called then result else { kind = "unreachable", detail = tostring(result) }
	if answer.kind == "denied" then
		return { Ok = false, Message = MESSAGES[answer.reason] or MESSAGES.invalid_code }
	elseif answer.kind == "unreachable" then
		return { Ok = false, Message = "Couldn't reach Hazastudio. Try again in a minute." }
	end
	local rec = LicensePolicy.fromActivation(answer, os.time())
	if not rec then
		return { Ok = false, Message = "The license server sent an unexpected answer. Try again." }
	end
	if guest ~= (rec.kind == "guest") then
		return { Ok = false, Message = MESSAGES.invalid_code }
	end
	write(rec)
	refresh()
	return { Ok = true }
end

function License.activate(player: Player, code: string): Result
	return submit(player, code, false)
end

function License.redeem(player: Player, code: string): Result
	return submit(player, code, true)
end

function License.view(): View
	return State.license()
end

function License.unlocked(): boolean
	return LicensePolicy.unlocked(State.license())
end

-- called with the new view whenever the status changes (locked → active, guest → expired, …)
function License.onChanged(fn: (View) -> ())
	table.insert(changed, fn)
end

-- Studio only: a hook for testing from the command bar (the running server's own instance)
local function mountTestHook()
	if not RunService:IsStudio() then
		return
	end
	local f = Instance.new("BindableFunction")
	f.Name = "HazaDJ_LicenseTest"
	f.OnInvoke = function(cmd: string, arg: any): any
		if cmd == "view" then
			return State.license()
		elseif cmd == "activate" or cmd == "redeem" then
			local owner = Players:GetPlayers()[1]
			if not owner then
				return { Ok = false, Message = "no player" }
			end
			return if cmd == "activate" then License.activate(owner, arg) else License.redeem(owner, arg)
		elseif cmd == "verify" then
			verify()
			return State.license()
		elseif cmd == "reset" then
			record = nil
			if store then
				pcall(function()
					(store :: DataStore):RemoveAsync(KEY)
				end)
			end
			refresh()
			return State.license()
		elseif cmd == "age" then
			-- pretend the last confirmation was `arg` seconds ago (grace tests)
			if record then
				local r = table.clone(record)
				r.lastOkAt = os.time() - (tonumber(arg) or 0)
				record = r
			end
			refresh()
			return State.license()
		end
		return "unknown command"
	end
	f.Parent = ServerStorage
	janitor:Add(f, "Destroy")
end

function License.start()
	if started then
		return
	end
	started = true
	if not Store.fixture then
		local ok, ds = pcall(DataStoreService.GetDataStore, DataStoreService, STORE_NAME)
		if ok then
			store = ds
		else
			warn("[HazaDJ] DataStores unavailable; an activation only lasts this session")
		end
		record = read()
	end
	-- an unpublished Studio place cannot activate anyway, so it is not checked
	if not Store.fixture and not (RunService:IsStudio() and game.GameId == 0) then
		gameMismatch = LicensePolicy.gameMismatch(Stamp, here())
		if gameMismatch then
			warn("[HazaDJ] this download was made for another game: " .. gameMismatch)
			LicenseApi.beacon(gameMismatch)
		end
	end
	refresh()
	if LicenseApi.usingStub() then
		print("[HazaDJ] licence: using the Studio stand-in")
	end

	-- another server activated, redeemed or got a verdict: read the record again
	pcall(function()
		janitor:Add(
			MessagingService:SubscribeAsync(TOPIC, function(msg)
				local data = msg.Data
				if type(data) == "table" and data.job ~= game.JobId then
					task.spawn(function()
						record = read()
						refresh()
					end)
				end
			end),
			"Disconnect"
		)
	end)

	-- a download stamped for another game is never verified (the beacon already went out)
	if not gameMismatch then
		janitor:Add(
			task.spawn(function()
				if record then
					verify()
				end
				while true do
					task.wait(LicensePolicy.VERIFY_EVERY)
					verify()
				end
			end),
			true
		)
	end
	janitor:Add(
		task.spawn(function()
			while true do
				task.wait(TICK)
				refresh()
			end
		end),
		true
	)
	mountTestHook()
end

function License.stop()
	janitor:Cleanup()
	started = false
end

return License
