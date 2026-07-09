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

function AfkGuardDomain.isBelowTeleportAbortIdle(reportedIdleSec: number): boolean
	return reportedIdleSec < (19 * 60)
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
