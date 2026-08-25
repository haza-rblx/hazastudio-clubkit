--!strict
-- Client AFK detection via Player.Idled; warns then requests server-authoritative rejoin.
--
-- Measured Player.Idled behaviour (2026-08-25, empirical): first fires at ~129s
-- of idle, then EXACTLY every 30s, and `idleTime` tracks real seconds since the
-- last input. Roblox disconnects at 20:00. Rungs therefore land on the first
-- tick at/after their configured time (e.g. the 780s rung fires at ~789s).
--
-- Escalation is scheduled by IDLE TIME (Config.AfkGuard.REJOIN_LADDER), not by
-- an attempt counter with a backoff. That matters: the previous counter model
-- could dead-end a streak permanently after 3 denials, and its state survived
-- across streaks because it only reset on UserInputService.InputBegan — which
-- never fires for mouse movement even though mouse movement DOES reset the
-- engine's idle clock. Here a denied rung is simply un-fired and retried on a
-- later tick, and any drop in `idleTime` resets the whole cycle.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local AfkGuardDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.AfkGuardDomain)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local NotifService = require(script.Parent.Parent.Services.NotifService)

local log = Logger.new("AfkGuardController")

local _connections: { RBXScriptConnection } = {}
local warnShown = false
local cycle: AfkGuardDomain.ClientCycleState = { cycleId = nil, firedSteps = {}, prevIdleSec = nil }
-- Set on the first Idled tick after a spawn; logs the surviving idle counter
-- to answer "does a same-server teleport reset the AFK idle clock?" empirically.
local loggedIdleAfterRespawn = false

local function track(conn: RBXScriptConnection): RBXScriptConnection
	table.insert(_connections, conn)
	return conn
end

-- Idempotent and allocation-free once clean: InputChanged fires every frame the
-- mouse moves, so this must stay cheap enough to sit on that path.
local function resetIdleState()
	warnShown = false
	if cycle.cycleId == nil and cycle.prevIdleSec == nil and next(cycle.firedSteps) == nil then
		return
	end
	cycle = { cycleId = nil, firedSteps = {}, prevIdleSec = nil }
end

-- Notifications are cosmetic and must NEVER be able to abort the safety path:
-- NotifService -> GeneralNotificationCenterService is unprotected and touches
-- the notification-center GUI, which buyers reshape.
local function notifySafe(fn: (string) -> (), message: string?)
	if type(message) ~= "string" or message == "" then
		return
	end
	local ok, err = pcall(fn, message)
	if not ok then
		log:warn("afk_notify_failed", { error = tostring(err) })
	end
end

local function destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)
	resetIdleState()
end

local function init(deps: { remotes: Folder })
	local afkConfig = Config.AfkGuard
	if not afkConfig or afkConfig.ENABLED ~= true then
		return
	end
	if Config.FeatureFlags.AfkGuardEnabled == false then
		return
	end

	local remotes = deps.remotes
	local remoteName = afkConfig.REMOTE_REQUEST or "AfkRejoinRequest"
	local requestRemote = remotes:WaitForChild(remoteName, 30) :: RemoteEvent?
	if not requestRemote then
		log:warn("AfkRejoinRequest remote missing; AFK guard disabled", { remote = remoteName })
		return
	end
	local responseRemote = remotes:WaitForChild(afkConfig.REMOTE_RESPONSE or "AfkRejoinResponse", 30) :: RemoteEvent?

	local player = Players.LocalPlayer

	-- Fast-path resets. InputBegan misses mouse movement, so InputChanged is
	-- wired too; the authoritative reset is the idleTime regression check below.
	track(UserInputService.InputBegan:Connect(resetIdleState))
	track(UserInputService.InputChanged:Connect(resetIdleState))

	-- Reset the "idle after respawn" probe every time a fresh character loads.
	track(player.CharacterAdded:Connect(function()
		loggedIdleAfterRespawn = false
	end))

	-- Server -> client outcome channel. A transient denial un-fires the rung so
	-- the same rung retries on the next tick; a hard denial leaves it fired and
	-- lets the ladder escalate to the next rung on schedule.
	if responseRemote then
		track(responseRemote.OnClientEvent:Connect(function(payload: any)
			if type(payload) ~= "table" then
				return
			end
			local outcome = payload.outcome
			local stepIndex = tonumber(payload.stepIndex)
			log:info("afk_rejoin_result", {
				outcome = outcome,
				stepIndex = stepIndex,
				retryAfterSec = payload.retryAfterSec,
			})
			if outcome == nil then
				return
			end
			if AfkGuardDomain.isTransientDenial(outcome) and stepIndex ~= nil then
				cycle.firedSteps[stepIndex] = nil
			end
		end))
	end

	track(player.Idled:Connect(function(idleTime: number)
		if not loggedIdleAfterRespawn then
			loggedIdleAfterRespawn = true
			log:info("afk_idle_after_rejoin", { idleSec = idleTime })
		end

		-- Engine restarted its idle streak (real input, incl. mouse movement).
		if AfkGuardDomain.isIdleRegression(cycle.prevIdleSec, idleTime) then
			log:info("afk_cycle_reset_by_input", { prevIdleSec = cycle.prevIdleSec, idleSec = idleTime })
			resetIdleState()
		end
		cycle.prevIdleSec = idleTime

		if AfkGuardDomain.isWarnThreshold(idleTime) and not warnShown then
			warnShown = true
			log:info("afk_warn_shown", { idleTime = idleTime })
			notifySafe(NotifService.warn, afkConfig.MSG_WARN)
		end

		local stepIndex, step = AfkGuardDomain.resolveLadderStep(idleTime, cycle.firedSteps)
		if stepIndex == nil or step == nil then
			return
		end

		if cycle.cycleId == nil then
			cycle.cycleId = HttpService:GenerateGUID(false)
		end

		local requestId = HttpService:GenerateGUID(false)
		-- Mark fired BEFORE sending so a throw below cannot cause a tight retry
		-- loop; a transient denial un-fires it via the response handler.
		cycle.firedSteps[stepIndex] = true

		log:info("afk_rejoin_requested", {
			requestId = requestId,
			cycleId = cycle.cycleId,
			stepIndex = stepIndex,
			sameServer = step.sameServer,
			reportedIdleSec = idleTime,
		})

		-- Fire FIRST, notify after: the request must not depend on GUI health.
		local ok, err = pcall(function()
			requestRemote:FireServer({
				requestId = requestId,
				reportedIdleSec = idleTime,
				cycleId = cycle.cycleId,
				stepIndex = stepIndex,
			})
		end)
		if not ok then
			cycle.firedSteps[stepIndex] = nil
			log:warn("afk_rejoin_fire_failed", { error = tostring(err) })
			notifySafe(NotifService.error, afkConfig.MSG_REJOIN_FAILED)
			return
		end

		notifySafe(NotifService.info, afkConfig.MSG_REJOINING)
	end))
end

return { init = init, destroy = destroy }
