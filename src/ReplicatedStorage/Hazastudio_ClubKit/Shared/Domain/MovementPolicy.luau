--!strict
-- Pure rules for MovementGuard (ADR 0008 Layer 2b). No Roblox globals: the guard samples
-- characters and does the raycasts; this module turns (previous sample, current sample,
-- exemption flags) into violations, and keeps the strike ledger arithmetic.
--
-- Whitelist first: kit-created states (gravity float, carry, server teleports, spawn) and
-- laggy samples are excluded before any rule runs. Every rule needs either a client-set
-- property no legitimate player can have, or several consecutive impossible samples.

local MovementPolicy = {}

export type Sample = {
	t: number, -- os.clock() at sample time
	x: number,
	y: number,
	z: number,
	vy: number, -- vertical velocity (studs/s)
	floorAir: boolean, -- Humanoid.FloorMaterial == Air
	groundDist: number?, -- downward raycast hit distance, nil = nothing within clearance
	state: string, -- Humanoid state name
	walkSpeed: number,
	jumpPower: number,
	ping: number, -- ms
	seated: boolean,
	platformStand: boolean,
	airJump: boolean, -- Jumping state entered while airborne since the previous sample
	blockedPath: boolean, -- raycast prev→cur crossed a CanCollide part
}

export type Flags = {
	exempt: boolean, -- role in EXEMPT_ROLES
	floating: boolean, -- kit GravityService float active
	carried: boolean, -- kit CarryService participant
	spawnAge: number, -- seconds since CharacterAdded
	teleportAge: number, -- seconds since the last server teleport stamp
}

export type Violation = { rule: string, weight: number }

export type State = {
	speedStreak: number,
	flyStreak: number,
	lastFloorY: number?,
	highJumpFired: boolean,
	airJumpTimes: { number },
	noclipTimes: { number },
}

export type Ledger = {
	strikes: number,
	anchor: number?, -- decay anchor (os.clock)
	warned: boolean,
}

MovementPolicy.DEFAULTS = {
	GRAVITY = 196.2,
	MAX_PING_MS = 600,
	SPAWN_GRACE = 5,
	TELEPORT_GRACE = 2,
	SPEED_TOLERANCE_MULT = 1.6,
	SPEED_TOLERANCE_ADD = 4,
	SPEED_STREAK = 3,
	MAX_WALKSPEED = 32,
	MAX_JUMPPOWER = 75,
	FLY_STREAK = 4,
	FLY_GROUND_CLEARANCE = 8,
	HIGHJUMP_MULT = 1.8,
	HIGHJUMP_ADD = 5,
	NOCLIP_EVENTS = 3,
	NOCLIP_WINDOW = 10,
	TELEPORT_MIN_STUDS = 60,
	TELEPORT_SPEED_MULT = 3,
	AIRJUMP_COUNT = 3,
	AIRJUMP_WINDOW = 3,
	STRIKE_DECAY_SEC = 20,
	WARN_AT = 3,
	KICK_AT = 5,
}

local NO_FLY_STATES: { [string]: boolean } = {
	Seated = true,
	PlatformStanding = true,
	Climbing = true,
	Swimming = true,
	Dead = true,
}

function MovementPolicy.newState(): State
	return {
		speedStreak = 0,
		flyStreak = 0,
		lastFloorY = nil,
		highJumpFired = false,
		airJumpTimes = {},
		noclipTimes = {},
	}
end

function MovementPolicy.newLedger(): Ledger
	return { strikes = 0, anchor = nil, warned = false }
end

local function cfgNum(cfg: any, key: string): number
	local v = if type(cfg) == "table" then cfg[key] else nil
	return if type(v) == "number" then v else (MovementPolicy.DEFAULTS :: any)[key]
end

function MovementPolicy.speedCap(walkSpeed: number, cfg: any): number
	return math.max(walkSpeed, 16) * cfgNum(cfg, "SPEED_TOLERANCE_MULT") + cfgNum(cfg, "SPEED_TOLERANCE_ADD")
end

function MovementPolicy.jumpApex(jumpPower: number, cfg: any): number
	local g = cfgNum(cfg, "GRAVITY")
	return (jumpPower * jumpPower) / (2 * g)
end

local function pruneTimes(times: { number }, now: number, window: number)
	local keep = {}
	for _, t in ipairs(times) do
		if now - t <= window then
			table.insert(keep, t)
		end
	end
	return keep
end

local function resetStreaks(state: State)
	state.speedStreak = 0
	state.flyStreak = 0
	state.highJumpFired = false
end

function MovementPolicy.evaluate(prev: Sample?, cur: Sample, flags: Flags, cfg: any, state: State): { Violation }
	local violations: { Violation } = {}

	if flags.exempt or flags.carried then
		resetStreaks(state)
		state.lastFloorY = if cur.floorAir then state.lastFloorY else cur.y
		return violations
	end
	if cur.ping > cfgNum(cfg, "MAX_PING_MS") then
		return violations -- laggy sample: judged neither way, streaks untouched
	end
	if flags.spawnAge < cfgNum(cfg, "SPAWN_GRACE") then
		resetStreaks(state)
		state.lastFloorY = cur.y
		return violations
	end

	-- Client-set properties: visible directly, no physics needed.
	if cur.walkSpeed > cfgNum(cfg, "MAX_WALKSPEED") or cur.jumpPower > cfgNum(cfg, "MAX_JUMPPOWER") then
		table.insert(violations, { rule = "speed_property", weight = 2 })
	end

	-- Floor bookkeeping (shared by fly + high jump).
	if not cur.floorAir then
		state.lastFloorY = cur.y
		state.highJumpFired = false
	end

	local airborneOk = cur.floorAir
		and not cur.seated
		and not cur.platformStand
		and not NO_FLY_STATES[cur.state]

	-- Fly: hovering with nothing under the feet, sample after sample.
	if not flags.floating then
		local hovering = airborneOk
			and cur.vy >= 0
			and (cur.groundDist == nil or cur.groundDist > cfgNum(cfg, "FLY_GROUND_CLEARANCE"))
		if hovering then
			state.flyStreak += 1
			if state.flyStreak >= cfgNum(cfg, "FLY_STREAK") then
				table.insert(violations, { rule = "fly", weight = 1 })
			end
		else
			state.flyStreak = 0
		end

		-- High jump: rose further from the last floor contact than JumpPower allows.
		if airborneOk and cur.vy >= 0 and state.lastFloorY ~= nil and not state.highJumpFired then
			local limit = MovementPolicy.jumpApex(cur.jumpPower, cfg) * cfgNum(cfg, "HIGHJUMP_MULT") + cfgNum(cfg, "HIGHJUMP_ADD")
			if (cur.y - (state.lastFloorY :: number)) > limit then
				state.highJumpFired = true
				table.insert(violations, { rule = "high_jump", weight = 2 })
			end
		end
	end

	-- Infinite jump: Jumping state entered mid-air, repeatedly.
	if cur.airJump then
		table.insert(state.airJumpTimes, cur.t)
	end
	state.airJumpTimes = pruneTimes(state.airJumpTimes, cur.t, cfgNum(cfg, "AIRJUMP_WINDOW"))
	if #state.airJumpTimes >= cfgNum(cfg, "AIRJUMP_COUNT") then
		table.insert(violations, { rule = "infinite_jump", weight = 1 })
		state.airJumpTimes = {}
	end

	-- Noclip: path between samples crossed solid geometry, repeatedly (never while seated —
	-- vehicles clip through their own doors).
	if cur.blockedPath and not cur.seated then
		table.insert(state.noclipTimes, cur.t)
	end
	state.noclipTimes = pruneTimes(state.noclipTimes, cur.t, cfgNum(cfg, "NOCLIP_WINDOW"))
	if #state.noclipTimes >= cfgNum(cfg, "NOCLIP_EVENTS") then
		table.insert(violations, { rule = "noclip", weight = 2 })
		state.noclipTimes = {}
	end

	-- Seated = vehicle / seat / elevator moves the player; displacement rules do not apply.
	if prev == nil or cur.seated then
		state.speedStreak = 0
		return violations
	end
	local dt = cur.t - prev.t
	if dt <= 0 then
		return violations
	end

	local dx, dy, dz = cur.x - prev.x, cur.y - prev.y, cur.z - prev.z
	local displacement = math.sqrt(dx * dx + dy * dy + dz * dz)
	local horizontalSpeed = math.sqrt(dx * dx + dz * dz) / dt
	local cap = MovementPolicy.speedCap(cur.walkSpeed, cfg)

	-- Teleport: one sample, impossible distance, no server stamp.
	local teleportLimit = math.max(cfgNum(cfg, "TELEPORT_MIN_STUDS"), cap * dt * cfgNum(cfg, "TELEPORT_SPEED_MULT"))
	if displacement > teleportLimit then
		state.speedStreak = 0
		if flags.teleportAge >= cfgNum(cfg, "TELEPORT_GRACE") then
			table.insert(violations, { rule = "teleport", weight = 3 })
		end
		return violations
	end

	-- Speed: sustained horizontal speed above what WalkSpeed allows.
	if not flags.floating then
		if horizontalSpeed > cap then
			state.speedStreak += 1
			if state.speedStreak >= cfgNum(cfg, "SPEED_STREAK") then
				table.insert(violations, { rule = "speed", weight = 1 })
			end
		else
			state.speedStreak = 0
		end
	end

	return violations
end

-- Strike ledger: whole strikes decay every STRIKE_DECAY_SEC; warn once per climb past
-- WARN_AT; kick at KICK_AT. Returns the ledger and the action to take.
function MovementPolicy.applyStrikes(ledger: Ledger, violations: { Violation }, now: number, cfg: any): (Ledger, string)
	local decay = cfgNum(cfg, "STRIKE_DECAY_SEC")
	if ledger.anchor == nil then
		ledger.anchor = now
	end
	local elapsed = now - (ledger.anchor :: number)
	if elapsed >= decay then
		local steps = math.floor(elapsed / decay)
		ledger.strikes = math.max(0, ledger.strikes - steps)
		ledger.anchor = (ledger.anchor :: number) + steps * decay
	end

	for _, v in ipairs(violations) do
		ledger.strikes += v.weight
	end

	local warnAt = cfgNum(cfg, "WARN_AT")
	local kickAt = cfgNum(cfg, "KICK_AT")
	if ledger.strikes < warnAt then
		ledger.warned = false
		return ledger, "none"
	end
	if ledger.strikes >= kickAt then
		return ledger, "kick"
	end
	if not ledger.warned then
		ledger.warned = true
		return ledger, "warn"
	end
	return ledger, "none"
end

return MovementPolicy
