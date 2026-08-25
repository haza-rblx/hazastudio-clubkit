--!strict
-- Pure validation and idle-threshold helpers for AFK Guard.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)

type Result<T> = Types.Result<T>

export type SyncRestorePayload = {
	wasSyncing: boolean,
	lastLeaderUserId: number?,
	animationName: string?,
	animationId: string?,
	timePosition: number,
	speed: number,
	isLeader: boolean?,
}

export type AfkRejoinRequest = {
	requestId: string,
	reportedIdleSec: number,
	-- Identifies the idle streak this request belongs to. Retries inside one
	-- cycle reuse it so the server does not charge a new rate token per rung.
	cycleId: string,
	-- Which ladder rung fired (1-based); decides same-server vs any-server.
	stepIndex: number,
}

export type LadderStep = {
	atIdleSec: number,
	sameServer: boolean,
}

-- Server -> client outcome for one rejoin request (REMOTE_RESPONSE).
-- Transient denials (rate/in-flight/carry/service) must NOT burn the client's
-- attempt budget — the client re-schedules using retryAfterSec instead.
export type RejoinOutcome =
	"allowed"
	| "denied_rate_limited"
	| "denied_in_flight"
	| "denied_carry_active"
	| "denied_service_unavailable"
	| "denied_invalid"
	| "rejoin_failed"

export type RejoinResponse = {
	requestId: string,
	outcome: RejoinOutcome,
	retryAfterSec: number?,
}

-- Client state for ONE idle streak. Rungs are scheduled by idle time (see
-- Config.AfkGuard.REJOIN_LADDER), not by a backoff counter, so a denial can
-- never dead-end the streak: the rung is simply un-fired and retried on a
-- later Idled tick.
--
-- `prevIdleSec` exists to detect that the ENGINE restarted its idle streak.
-- Measured 2026-08-25: mouse movement resets Roblox's idle clock but arrives via
-- UserInputService.InputChanged, never InputBegan — so input-event-based resets
-- alone leak stale state across streaks.
export type ClientCycleState = {
	cycleId: string?,
	firedSteps: { [number]: boolean },
	prevIdleSec: number?,
}

local ANIMATION_ID_PATTERN = "^rbxassetid://%d+$"
local MAX_ANIMATION_NAME_LEN = 128

local AfkGuardDomain = {}

local function getAfkConfig(): any
	return Config.AfkGuard or {}
end

function AfkGuardDomain.getMinAcceptableIdleSec(): number
	local cfg = getAfkConfig()
	local threshold = tonumber(cfg.IDLE_THRESHOLD_SEC) or (17 * 60)
	local tolerance = tonumber(cfg.IDLE_TOLERANCE_SEC) or 30
	return threshold - tolerance
end

function AfkGuardDomain.isWarnThreshold(idleSec: number): boolean
	local cfg = getAfkConfig()
	local warnSec = tonumber(cfg.IDLE_WARN_SEC) or 120
	return idleSec >= warnSec
end

function AfkGuardDomain.isRejoinThreshold(idleSec: number): boolean
	local cfg = getAfkConfig()
	local threshold = tonumber(cfg.IDLE_THRESHOLD_SEC) or (17 * 60)
	return idleSec >= threshold
end

-- Is this outcome a transient denial (worth retrying later without burning
-- the attempt budget)? Rate-limit / in-flight / carry all resolve on their own.
function AfkGuardDomain.isTransientDenial(outcome: RejoinOutcome): boolean
	return outcome == "denied_rate_limited"
		or outcome == "denied_in_flight"
		or outcome == "denied_carry_active"
end

-- Delay (seconds) before the client may fire the next request after `outcome`.
-- Uses the server-supplied hint when present; falls back to configured backoff.
function AfkGuardDomain.nextRetryDelaySec(outcome: RejoinOutcome, retryAfterSec: number?): number
	local cfg = getAfkConfig()
	local backoffSec = tonumber(cfg.CLIENT_RETRY_BACKOFF_SEC) or 60
	local base = retryAfterSec
	if type(base) ~= "number" or base <= 0 then
		base = backoffSec
	end
	-- Jitter +-10% so a burst of idle clients does not re-fire in lockstep.
	local jitter = base * (math.random() * 0.2 - 0.1)
	return math.max(1, base + jitter)
end

function AfkGuardDomain.isBelowTeleportAbortIdle(reportedIdleSec: number): boolean
	return reportedIdleSec < (19 * 60)
end

function AfkGuardDomain.getHardStopIdleSec(): number
	local cfg = getAfkConfig()
	return tonumber(cfg.HARD_STOP_IDLE_SEC) or (19 * 60)
end

-- Normalised, ascending escalation ladder. Falls back to a single rung at the
-- legacy threshold if a buyer config supplies nothing usable.
function AfkGuardDomain.getLadder(): { LadderStep }
	local cfg = getAfkConfig()
	local raw = cfg.REJOIN_LADDER
	local out: { LadderStep } = {}

	if type(raw) == "table" then
		for _, step in ipairs(raw) do
			if type(step) == "table" then
				local at = tonumber(step.atIdleSec)
				if at ~= nil and at > 0 then
					table.insert(out, { atIdleSec = at, sameServer = step.sameServer ~= false })
				end
			end
		end
	end

	if #out == 0 then
		local threshold = tonumber(cfg.IDLE_THRESHOLD_SEC) or (13 * 60)
		return { { atIdleSec = threshold, sameServer = true } }
	end

	table.sort(out, function(a, b)
		return a.atIdleSec < b.atIdleSec
	end)
	return out
end

-- Did the engine restart its idle streak since the previous tick? `idleTime`
-- is engine-authoritative and monotonic within a streak, so a drop means real
-- input happened — including input that never reaches InputBegan.
function AfkGuardDomain.isIdleRegression(prevIdleSec: number?, idleSec: number): boolean
	if prevIdleSec == nil then
		return false
	end
	-- 1s slack so float jitter is never mistaken for a new streak.
	return idleSec < (prevIdleSec - 1)
end

-- Which rung should fire on this tick? Picks the HIGHEST rung whose time has
-- passed and that has not fired yet, so a client that was blocked for a while
-- escalates straight to the most urgent rung instead of replaying stale ones.
-- Returns nil past the hard stop — teleporting into the kick window is worse
-- than letting the disconnect happen cleanly.
function AfkGuardDomain.resolveLadderStep(
	idleSec: number,
	firedSteps: { [number]: boolean }
): (number?, LadderStep?)
	if idleSec > AfkGuardDomain.getHardStopIdleSec() then
		return nil, nil
	end

	local ladder = AfkGuardDomain.getLadder()
	local chosenIndex: number? = nil
	for index, step in ipairs(ladder) do
		if idleSec >= step.atIdleSec and not firedSteps[index] then
			chosenIndex = index
		end
	end

	if chosenIndex ~= nil then
		return chosenIndex, ladder[chosenIndex]
	end
	return nil, nil
end

function AfkGuardDomain.validateRequestId(requestId: any): boolean
	return type(requestId) == "string" and #requestId > 0 and #requestId <= 64
end

function AfkGuardDomain.validateRejoinRequest(raw: any): Result<AfkRejoinRequest>
	if type(raw) ~= "table" then
		return Result.Err("invalid_payload")
	end

	local requestId = raw.requestId
	local reportedIdleSec = raw.reportedIdleSec
	local cycleId = raw.cycleId
	local stepIndex = raw.stepIndex

	if not AfkGuardDomain.validateRequestId(requestId) then
		return Result.Err("invalid_request_id")
	end

	if not AfkGuardDomain.validateRequestId(cycleId) then
		return Result.Err("invalid_cycle_id")
	end

	if type(stepIndex) ~= "number" or stepIndex ~= stepIndex then
		return Result.Err("invalid_step_index")
	end
	stepIndex = math.floor(stepIndex)
	if stepIndex < 1 or stepIndex > #AfkGuardDomain.getLadder() then
		return Result.Err("invalid_step_index")
	end

	if type(reportedIdleSec) ~= "number" or reportedIdleSec ~= reportedIdleSec then
		return Result.Err("invalid_idle_time")
	end

	if reportedIdleSec < AfkGuardDomain.getMinAcceptableIdleSec() then
		return Result.Err("idle_too_low")
	end

	if reportedIdleSec > 3600 then
		return Result.Err("idle_too_high")
	end

	return Result.Ok({
		requestId = requestId,
		reportedIdleSec = reportedIdleSec,
		cycleId = cycleId,
		stepIndex = stepIndex,
	})
end

function AfkGuardDomain.validateSyncRestorePayload(raw: any): Result<SyncRestorePayload>
	if type(raw) ~= "table" then
		return Result.Err("invalid_sync_restore")
	end

	for key in pairs(raw) do
		if key ~= "wasSyncing"
			and key ~= "lastLeaderUserId"
			and key ~= "animationName"
			and key ~= "animationId"
			and key ~= "timePosition"
			and key ~= "speed"
			and key ~= "isLeader"
		then
			return Result.Err("unknown_sync_field")
		end
	end

	if type(raw.wasSyncing) ~= "boolean" then
		return Result.Err("invalid_was_syncing")
	end

	local lastLeaderUserId: number? = nil
	if raw.lastLeaderUserId ~= nil then
		if type(raw.lastLeaderUserId) ~= "number" or raw.lastLeaderUserId <= 0 then
			return Result.Err("invalid_last_leader")
		end
		lastLeaderUserId = raw.lastLeaderUserId
	end

	local animationName: string? = nil
	if raw.animationName ~= nil then
		if type(raw.animationName) ~= "string" or raw.animationName == "" or #raw.animationName > MAX_ANIMATION_NAME_LEN then
			return Result.Err("invalid_animation_name")
		end
		animationName = raw.animationName
	end

	local animationId: string? = nil
	if raw.animationId ~= nil then
		if type(raw.animationId) ~= "string" or not string.match(raw.animationId, ANIMATION_ID_PATTERN) then
			return Result.Err("invalid_animation_id")
		end
		animationId = raw.animationId
	end

	local timePosition = raw.timePosition
	if type(timePosition) ~= "number" or timePosition < 0 or timePosition > 3600 then
		return Result.Err("invalid_time_position")
	end

	local speed = raw.speed
	if type(speed) ~= "number" or speed < 0.1 or speed > 4 then
		return Result.Err("invalid_speed")
	end

	local isLeader: boolean? = nil
	if raw.isLeader ~= nil then
		if type(raw.isLeader) ~= "boolean" then
			return Result.Err("invalid_is_leader")
		end
		isLeader = raw.isLeader
	end

	return Result.Ok({
		wasSyncing = raw.wasSyncing,
		lastLeaderUserId = lastLeaderUserId,
		animationName = animationName,
		animationId = animationId,
		timePosition = timePosition,
		speed = speed,
		isLeader = isLeader,
	})
end

return AfkGuardDomain
