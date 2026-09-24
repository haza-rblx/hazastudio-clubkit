--!strict
-- Movement cheat guard (ADR 0008 Layer 2b), server half.
--
-- The client owns its character physics, so this only OBSERVES replicated results:
-- sample every character on a fixed interval, hand (prev, cur, flags) to the pure
-- MovementPolicy, and act on the strike ledger it returns. Kit-created states (gravity
-- float, carry, server teleports via CharacterReady.pivotTo, spawn) are exempt before any
-- rule runs; laggy samples are dropped, not judged.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local MovementPolicy = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.MovementPolicy)

local MovementGuard = {}

type Deps = {
	licenseService: any?,
	notify: any?,
	gravityService: any?,
	carryService: any?,
	playerSnapshotService: any?,
}

type Tracked = {
	prev: MovementPolicy.Sample?,
	state: MovementPolicy.State,
	ledger: MovementPolicy.Ledger,
	spawnedAt: number,
	airJump: boolean,
	stateConn: RBXScriptConnection?,
	kicked: boolean,
	-- P4 (H4) spread mode: os.clock() of each mid-air jump since the last sample (the policy's
	-- 3-in-3 s window needs them when samples are 2 s apart), and the position-only lead
	-- sample taken one tick before this player's full sample (the noclip chord starts there).
	airJumpStamps: { number },
	leadPos: Vector3?,
	leadT: number?,
}

local _started = false
local log = Logger.new("MovementGuard")
local tracked: { [number]: Tracked } = {}
local softBanUntil: { [number]: number } = {}

-- P4 (H4): one RaycastParams for every sample; its exclude list (every player's character, so
-- another dancer's torso on the chord is not a wall) is rebuilt only when a character is
-- added or removed. Strong table keyed by Player, cleared on CharacterRemoving / leave.
local excludeCharacters: { [Player]: Model } = {}
local sharedParams: RaycastParams? = nil
local excludeDirty = true
local MAX_AIRJUMP_STAMPS = 8

local function setExcludedCharacter(player: Player, character: Model?)
	excludeCharacters[player] = character
	excludeDirty = true
end

local function sharedRaycastParams(): RaycastParams
	local params = sharedParams
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.RespectCanCollide = true
		sharedParams = params
	end
	if excludeDirty then
		local list = {}
		for _, character in excludeCharacters do
			if character.Parent then
				table.insert(list, character)
			end
		end
		params.FilterDescendantsInstances = list
		excludeDirty = false
	end
	return params
end

local function cfg(): any
	return Config.MovementGuard
end

local function beacon(deps: Deps, kind: string, extra: { [string]: any }?)
	local ls = deps.licenseService
	if ls and type(ls.reportTamper) == "function" then
		pcall(function()
			ls.reportTamper("runtime:" .. kind, extra)
		end)
	end
end

local function roleOf(deps: Deps, userId: number): string?
	local svc = deps.playerSnapshotService
	if svc and type(svc.getSnapshot) == "function" then
		local ok, snap = pcall(function()
			return svc:getSnapshot(userId)
		end)
		if ok and type(snap) == "table" then
			return (snap :: any).role
		end
	end
	return nil
end

local function isExempt(deps: Deps, player: Player): boolean
	local role = roleOf(deps, player.UserId)
	if type(role) ~= "string" then
		return false
	end
	for _, exemptRole in ipairs(cfg().EXEMPT_ROLES or {}) do
		if exemptRole == role then
			return true
		end
	end
	return false
end

local function isFloating(deps: Deps, userId: number): boolean
	local g = deps.gravityService
	if not g then
		return false
	end
	local ok, result = pcall(function()
		if type(g.isServerModeActive) == "function" and g:isServerModeActive() then
			return true
		end
		return type(g.isActive) == "function" and g:isActive(userId) == true
	end)
	return ok and result == true
end

local function isCarried(deps: Deps, userId: number): boolean
	local c = deps.carryService
	if not c or type(c.getPartnerId) ~= "function" then
		return false
	end
	local ok, partner = pcall(function()
		return c:getPartnerId(userId)
	end)
	return ok and partner ~= nil
end

local function bindCharacter(player: Player, character: Model)
	local entry: Tracked = {
		prev = nil,
		state = MovementPolicy.newState(),
		ledger = tracked[player.UserId] and tracked[player.UserId].ledger or MovementPolicy.newLedger(),
		spawnedAt = os.clock(),
		airJump = false,
		stateConn = nil,
		kicked = false,
		airJumpStamps = {},
		leadPos = nil,
		leadT = nil,
	}
	local old = tracked[player.UserId]
	if old and old.stateConn then
		old.stateConn:Disconnect()
	end
	tracked[player.UserId] = entry
	setExcludedCharacter(player, character)

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		entry.stateConn = humanoid.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Jumping and humanoid.FloorMaterial == Enum.Material.Air then
				entry.airJump = true
				if #entry.airJumpStamps < MAX_AIRJUMP_STAMPS then
					table.insert(entry.airJumpStamps, os.clock())
				end
			end
		end)
	end
end

-- `spread` (P4, H4): samples are PERF_SPREAD_WINDOW apart; the noclip chord starts at the lead
-- sample and stamped air jumps go straight into the policy window. `sharedParams`: the reused
-- RaycastParams (nil = build one excluding every character, the pre-P4 path).
local function sampleCharacter(deps: Deps, player: Player, entry: Tracked, now: number, spread: boolean?, reusedParams: RaycastParams?)
	local character = player.Character
	if not character or not character.Parent then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (hrp and hrp:IsA("BasePart") and humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	if humanoid.Health <= 0 then
		return
	end

	local c = cfg()
	local pos = hrp.Position
	local params = reusedParams
	if not params then
		-- Exclude EVERY character: another dancer's torso on the sampled chord is not a wall.
		local exclude = {}
		for _, other in ipairs(Players:GetPlayers()) do
			if other.Character then
				table.insert(exclude, other.Character)
			end
		end
		local built = RaycastParams.new()
		built.FilterType = Enum.RaycastFilterType.Exclude
		built.FilterDescendantsInstances = exclude
		built.RespectCanCollide = true
		params = built
	end

	-- Ground under the feet (fly rule).
	local clearance = (tonumber(c.FLY_GROUND_CLEARANCE) or 8) + humanoid.HipHeight + 3
	local down = workspace:Raycast(pos, Vector3.new(0, -clearance, 0), params)
	local groundDist: number? = if down then (pos.Y - down.Position.Y) - humanoid.HipHeight - 1 else nil
	if groundDist and groundDist < 0 then
		groundDist = 0
	end

	-- Solid geometry between the previous and current position (noclip rule).
	local blockedPath = false
	local prev = entry.prev
	local chordFrom: Vector3? = if prev then Vector3.new(prev.x, prev.y, prev.z) else nil
	if spread then
		-- Spread mode: a 2 s chord would cut through every pillar an honest dancer walks
		-- around; chord from the lead sample instead (one SAMPLE_INTERVAL ago).
		local leadPos, leadT = entry.leadPos, entry.leadT
		local interval = tonumber(c.SAMPLE_INTERVAL) or 0.5
		chordFrom = if leadPos and leadT and now - leadT <= interval * 1.5 then leadPos else nil
	end
	entry.leadPos = nil
	entry.leadT = nil
	if chordFrom then
		local from = chordFrom
		local delta = pos - from
		if delta.Magnitude > 1 then
			local hit = workspace:Raycast(from, delta, params)
			if hit and hit.Instance and hit.Instance.CanCollide then
				local tag = c.IGNORE_COLLECTION_TAG
				if not (type(tag) == "string" and CollectionService:HasTag(hit.Instance, tag)) then
					-- Genuinely THROUGH the part, not a cut corner: the reverse ray from the
					-- destination must hit the same part too (a corner cut exits into open air).
					if (hit.Position - pos).Magnitude > 1.5 then
						local back = workspace:Raycast(pos, -delta, params)
						if back and back.Instance == hit.Instance and (back.Position - from).Magnitude > 1.5 then
							blockedPath = true
						end
					end
				end
			end
		end
	end

	local ping = 0
	pcall(function()
		ping = player:GetNetworkPing() * 1000
	end)

	local cur: MovementPolicy.Sample = {
		t = now,
		x = pos.X,
		y = pos.Y,
		z = pos.Z,
		vy = hrp.AssemblyLinearVelocity.Y,
		floorAir = humanoid.FloorMaterial == Enum.Material.Air,
		groundDist = groundDist,
		state = humanoid:GetState().Name,
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = if humanoid.UseJumpPower then humanoid.JumpPower else math.sqrt(2 * workspace.Gravity * humanoid.JumpHeight),
		ping = ping,
		seated = humanoid.Sit or humanoid.SeatPart ~= nil,
		platformStand = humanoid.PlatformStand,
		airJump = entry.airJump,
		blockedPath = blockedPath,
	}
	entry.airJump = false
	if spread then
		-- 2 s between samples: feed every stamped air jump into the policy's 3-in-3 s window
		-- (a boolean per sample could never reach 3 within 3 s).
		for _, stamp in entry.airJumpStamps do
			table.insert(entry.state.airJumpTimes, stamp)
		end
		cur.airJump = false
	end
	table.clear(entry.airJumpStamps)

	local stampAt = tonumber(character:GetAttribute(c.TELEPORT_STAMP_ATTRIBUTE or "ClubKitTeleportAt"))
	local flags: MovementPolicy.Flags = {
		exempt = isExempt(deps, player),
		floating = isFloating(deps, player.UserId),
		carried = isCarried(deps, player.UserId),
		spawnAge = now - entry.spawnedAt,
		teleportAge = if stampAt then now - stampAt else 999,
	}

	local violations = MovementPolicy.evaluate(prev, cur, flags, c, entry.state)
	entry.prev = cur
	if #violations == 0 and entry.ledger.strikes == 0 then
		return
	end

	local ledger, action = MovementPolicy.applyStrikes(entry.ledger, violations, now, c)
	entry.ledger = ledger
	if #violations > 0 then
		local names = {}
		for _, v in ipairs(violations) do
			table.insert(names, v.rule)
		end
		log:warn("Movement violation", {
			player = player.Name,
			rules = table.concat(names, ","),
			strikes = ledger.strikes,
			ping = math.floor(ping),
			walkSpeed = cur.walkSpeed,
			enforce = c.ENFORCE,
		})
	end

	if action == "warn" then
		beacon(deps, "movement_warn", { actor_id = player.UserId, strikes = ledger.strikes })
		if c.ENFORCE == "kick" and deps.notify and type(deps.notify.player) == "function" then
			pcall(function()
				deps.notify.player(player, c.MSG_WARN, "WARNING")
			end)
		end
	elseif action == "kick" and not entry.kicked then
		local rules = {}
		for _, v in ipairs(violations) do
			table.insert(rules, v.rule)
		end
		local why = if #rules > 0 then table.concat(rules, ", ") else "repeated violations"
		beacon(deps, "movement_kick", { actor_id = player.UserId, actor_name = player.Name, rules = why, strikes = ledger.strikes, ping = math.floor(ping) })
		if c.ENFORCE == "kick" then
			entry.kicked = true
			local minutes = tonumber(c.SOFT_BAN_MINUTES) or 0
			if minutes > 0 then
				softBanUntil[player.UserId] = os.time() + minutes * 60
			end
			log:warn("Movement kick", { player = player.Name, rules = why })
			pcall(function()
				player:Kick(string.format(c.MSG_KICK, why, minutes))
			end)
		else
			entry.ledger = MovementPolicy.newLedger()
			log:warn("Movement kick suppressed (ENFORCE=log)", { player = player.Name, rules = why })
		end
	end
end

function MovementGuard.start(deps: Deps)
	if _started then
		return
	end
	_started = true
	local c = cfg()
	if c.ENABLED ~= true then
		return
	end

	local function bindPlayer(player: Player)
		local until_ = softBanUntil[player.UserId]
		if until_ and os.time() < until_ and c.ENFORCE == "kick" then
			local left = math.max(1, math.ceil((until_ - os.time()) / 60))
			player:Kick(string.format(c.MSG_SOFT_BAN, left))
			return
		end
		player.CharacterAdded:Connect(function(character)
			bindCharacter(player, character)
		end)
		player.CharacterRemoving:Connect(function(character)
			if excludeCharacters[player] == character then
				setExcludedCharacter(player, nil)
			end
		end)
		if player.Character then
			bindCharacter(player, player.Character)
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(function(player)
		local entry = tracked[player.UserId]
		if entry and entry.stateConn then
			entry.stateConn:Disconnect()
		end
		tracked[player.UserId] = nil
		setExcludedCharacter(player, nil)
		-- Expired soft bans are dropped here so the table stays bounded.
		for userId, until_ in pairs(softBanUntil) do
			if os.time() >= until_ then
				softBanUntil[userId] = nil
			end
		end
	end)

	local interval = tonumber(c.SAMPLE_INTERVAL) or 0.5
	local acc = 0
	local tickNo = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < interval then
			return
		end
		acc -= interval
		local now = os.clock()
		local players = Players:GetPlayers()
		-- P4 (H4): above PERF_SPREAD_ABOVE_PLAYERS, one slice of players per tick (each player
		-- every PERF_SPREAD_WINDOW s) plus a position-only lead sample for the next slice.
		local slices = MovementPolicy.sampleSlices(#players, c, interval)
		local spread = slices > 1
		local params = if c.PERF_SHARED_RAYCAST_PARAMS == true then sharedRaycastParams() else nil
		local slice = tickNo
		tickNo += 1
		for _, player in ipairs(players) do
			local entry = tracked[player.UserId]
			if entry and not entry.kicked then
				if MovementPolicy.inSlice(player.UserId, slice, slices) then
					local ok, err = pcall(sampleCharacter, deps, player, entry, now, spread, params)
					if not ok then
						log:warn("Sample failed", { player = player.Name, err = tostring(err) })
					end
				elseif spread and MovementPolicy.inSlice(player.UserId, slice + 1, slices) then
					local character = player.Character
					local hrp = character and character:FindFirstChild("HumanoidRootPart")
					if hrp and hrp:IsA("BasePart") then
						entry.leadPos = hrp.Position
						entry.leadT = now
					end
				end
			end
		end
	end)
	log:info("MovementGuard armed", { enforce = c.ENFORCE, interval = interval, exempt = table.concat(c.EXEMPT_ROLES or {}, ",") })
end

-- Buyer scripts (teleport pads, elevators, cutscenes) call this right before moving a
-- character so the displacement is not judged. Equivalent to setting the attribute directly.
function MovementGuard.stampTeleport(character: Instance)
	local attr = cfg().TELEPORT_STAMP_ATTRIBUTE or "ClubKitTeleportAt"
	character:SetAttribute(attr, os.clock())
end

-- Test/ops hook: current ledger for a player (nil when untracked).
function MovementGuard.getLedger(userId: number): MovementPolicy.Ledger?
	local entry = tracked[userId]
	return if entry then entry.ledger else nil
end

-- Crowd-harness hook (production hardening P4, .tmp/crowd-harness-server.luau): time the real
-- sampleCharacter over stand-ins `{ UserId, Name, Character }` (no module state touched). Two
-- passes so the second one also casts the noclip chord. `shared` = one reused RaycastParams
-- (P4) vs a new one excluding every character per sample (pre-P4). Returns milliseconds.
function MovementGuard.benchSample(subjects: { any }, shared: boolean): { firstPassMs: number, secondPassMs: number, samples: number }
	local params: RaycastParams? = nil
	if shared then
		local list = {}
		for _, s in subjects do
			if s.Character then
				table.insert(list, s.Character)
			end
		end
		local p = RaycastParams.new()
		p.FilterType = Enum.RaycastFilterType.Exclude
		p.RespectCanCollide = true
		p.FilterDescendantsInstances = list
		params = p
	end
	local entries: { [any]: Tracked } = {}
	for _, s in subjects do
		entries[s] = {
			prev = nil,
			state = MovementPolicy.newState(),
			ledger = MovementPolicy.newLedger(),
			spawnedAt = os.clock(),
			airJump = false,
			stateConn = nil,
			kicked = false,
			airJumpStamps = {},
			leadPos = nil,
			leadT = nil,
		}
	end
	local function pass(): number
		local t0 = os.clock()
		local now = os.clock()
		for _, s in subjects do
			local p = params
			if not shared then
				-- Pre-P4 cost: a fresh exclude list of every character + new params per sample.
				local list = {}
				for _, other in subjects do
					if other.Character then
						table.insert(list, other.Character)
					end
				end
				local built = RaycastParams.new()
				built.FilterType = Enum.RaycastFilterType.Exclude
				built.RespectCanCollide = true
				built.FilterDescendantsInstances = list
				p = built
			end
			pcall(sampleCharacter, {}, s, entries[s], now, false, p)
		end
		return (os.clock() - t0) * 1000
	end
	local first = pass()
	for _, s in subjects do
		local prev = entries[s].prev
		if prev then
			prev.x += 3 -- make the second pass cast a chord
		end
	end
	local second = pass()
	return { firstPassMs = first, secondPassMs = second, samples = #subjects }
end

return MovementGuard
