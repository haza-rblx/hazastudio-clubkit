--!strict
-- Shared freecam session: one pilot streams camera; server broadcasts to spectators.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

export type DroneFrame = {
	c: { number },
	fov: number,
}

local function createDroneService(deps: {
	stateRemote: RemoteEvent,
	logger: any?,
})
	local stateRemote = deps.stateRemote
	local log = deps.logger
	local droneConfig = Config.Drone

	local pilot: Player? = nil
	local lastBroadcastAt = 0

	local service = {}

	function service:isActive(): boolean
		return pilot ~= nil
	end

	function service:getPilot(): Player?
		return pilot
	end

	function service:getPilotUserId(): number?
		return if pilot then pilot.UserId else nil
	end

	local function broadcast(payload: { [string]: any })
		stateRemote:FireAllClients(payload)
	end

	function service:start(pilotPlayer: Player): (boolean, string?)
		if pilot ~= nil then
			local name = if pilot.Parent then pilot.DisplayName else "?"
			return false, string.format(droneConfig.MSG_ALREADY, name)
		end
		pilot = pilotPlayer
		broadcast({
			phase = "start",
			pilotUserId = pilotPlayer.UserId,
			pilotName = pilotPlayer.DisplayName,
		})
		if log then
			log:info("Drone started", { pilot = pilotPlayer.Name, userId = pilotPlayer.UserId })
		end
		return true, nil
	end

	function service:stop(reason: string?): boolean
		if pilot == nil then
			return false
		end
		local previous = pilot
		pilot = nil
		broadcast({
			phase = "stop",
			pilotUserId = previous.UserId,
			reason = reason or "stop",
		})
		if log then
			log:info("Drone stopped", { pilot = previous.Name, reason = reason })
		end
		return true
	end

	function service:pushFrame(fromPlayer: Player, frame: DroneFrame): boolean
		if pilot == nil or fromPlayer ~= pilot then
			return false
		end
		if type(frame) ~= "table" or type(frame.c) ~= "table" or #frame.c < 12 then
			return false
		end
		local fov = tonumber(frame.fov)
		if fov == nil then
			return false
		end
		local now = os.clock()
		local minInterval = 1 / math.max(1, tonumber(droneConfig.STREAM_HZ) or 15)
		if now - lastBroadcastAt < minInterval then
			return true -- accept but don't fan-out yet
		end
		lastBroadcastAt = now
		local components: { number } = {}
		for i = 1, 12 do
			local n = tonumber(frame.c[i])
			if n == nil then
				return false
			end
			components[i] = n
		end
		broadcast({
			phase = "frame",
			pilotUserId = fromPlayer.UserId,
			c = components,
			fov = math.clamp(fov, 1, 120),
		})
		return true
	end

	function service:onPlayerRemoving(player: Player)
		if pilot == player then
			service:stop("pilot_left")
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		service:onPlayerRemoving(player)
	end)

	return service
end

return createDroneService
