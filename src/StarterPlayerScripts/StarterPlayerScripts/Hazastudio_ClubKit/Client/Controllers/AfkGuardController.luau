--!strict
-- Client AFK detection via Player.Idled; warns then requests server-authoritative rejoin.

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
-- Retry budget for one idle streak; Idled keeps firing (~every 30s) while idle,
-- so a denied/failed request retries on a later tick after the backoff window.
local retryState: AfkGuardDomain.ClientRetryState = { lastRequestAt = nil, attempts = 0 }

local function track(conn: RBXScriptConnection): RBXScriptConnection
	table.insert(_connections, conn)
	return conn
end

local function resetIdleState()
	warnShown = false
	retryState = { lastRequestAt = nil, attempts = 0 }
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

	local player = Players.LocalPlayer

	track(UserInputService.InputBegan:Connect(function()
		resetIdleState()
	end))

	track(player.Idled:Connect(function(idleTime: number)
		if AfkGuardDomain.isWarnThreshold(idleTime) and not warnShown then
			warnShown = true
			log:info("afk_warn_shown", { idleTime = idleTime })
			NotifService.warn(afkConfig.MSG_WARN or "[Session] You're AFK. Move to stay connected.")
		end

		local canRequest, nextState = AfkGuardDomain.canRequestRejoin(retryState, idleTime, os.clock())
		retryState = nextState
		if not canRequest then
			return
		end

		local requestId = HttpService:GenerateGUID(false)
		log:info("afk_rejoin_requested", {
			requestId = requestId,
			reportedIdleSec = idleTime,
			attempt = retryState.attempts,
		})
		NotifService.info(afkConfig.MSG_REJOINING or "[Session] AFK rejoin in progress...")

		local ok, err = pcall(function()
			requestRemote:FireServer({
				requestId = requestId,
				reportedIdleSec = idleTime,
			})
		end)
		if not ok then
			log:warn("afk_rejoin_fire_failed", { error = tostring(err) })
			NotifService.error(afkConfig.MSG_REJOIN_FAILED or "[Session] AFK rejoin failed.")
		end
	end))
end

return { init = init, destroy = destroy }
