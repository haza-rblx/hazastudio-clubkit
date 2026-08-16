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

-- Client-side retry budget for one idle streak; reset by real user input.
-- Attempts are ALSO re-armed on server feedback (allowed / rejoin_failed) so
-- a no-input session never dead-ends on a transient denial.
export type ClientRetryState = {
	lastRequestAt: number?,
	attempts: number,
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

-- Pure decision for the client: may we fire a rejoin request on this Idled tick?
-- True only when at/above the rejoin threshold, under the attempt cap, and past
-- the backoff window since the last request. Returns the next state either way.
function AfkGuardDomain.canRequestRejoin(
	state: ClientRetryState,
	idleSec: number,
	nowSec: number
): (boolean, ClientRetryState)
	local cfg = getAfkConfig()
	local maxAttempts = tonumber(cfg.MAX_CLIENT_ATTEMPTS) or 3
	local backoffSec = tonumber(cfg.CLIENT_RETRY_BACKOFF_SEC) or 60

	if not AfkGuardDomain.isRejoinThreshold(idleSec) then
		return false, state
	end

	if state.attempts >= maxAttempts then
		return false, state
	end

	if state.lastRequestAt ~= nil and (nowSec - state.lastRequestAt) < backoffSec then
		return false, state
	end

	return true, {
		lastRequestAt = nowSec,
		attempts = state.attempts + 1,
	}
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

	if not AfkGuardDomain.validateRequestId(requestId) then
		return Result.Err("invalid_request_id")
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
