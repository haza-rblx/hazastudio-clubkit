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
}

local _started = false
local log = Logger.new("MovementGuard")
local tracked: { [number]: Tracked } = {}
local softBanUntil: { [number]: number } = {}

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
	}
	local old = tracked[player.UserId]
	if old and old.stateConn then
		old.stateConn:Disconnect()
	end
	tracked[player.UserId] = entry

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		entry.stateConn = humanoid.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Jumping and humanoid.FloorMaterial == Enum.Material.Air then
				entry.airJump = true
			end
		end)
	end
end

local function sampleCharacter(deps: Deps, player: Player, entry: Tracked, now: number)
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
	-- Exclude EVERY character: another dancer's torso on the sampled chord is not a wall.
	local exclude = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			table.insert(exclude, other.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true

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
	if prev then
		local from = Vector3.new(prev.x, prev.y, prev.z)
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
		-- Expired soft bans are dropped here so the table stays bounded.
		for userId, until_ in pairs(softBanUntil) do
			if os.time() >= until_ then
				softBanUntil[userId] = nil
			end
		end
	end)

	local interval = tonumber(c.SAMPLE_INTERVAL) or 0.5
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < interval then
			return
		end
		acc -= interval
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local entry = tracked[player.UserId]
			if entry and not entry.kicked then
				local ok, err = pcall(sampleCharacter, deps, player, entry, now)
				if not ok then
					log:warn("Sample failed", { player = player.Name, err = tostring(err) })
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

return MovementGuard
