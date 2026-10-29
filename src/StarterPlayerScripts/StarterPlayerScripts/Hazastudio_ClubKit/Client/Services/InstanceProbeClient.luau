--!strict
-- Client/Services/InstanceProbeClient.luau
--
-- Instance-diet probe, client side (docs/plans/instance-diet-2026-10-09.md, phase 1). TEMPORARY.
-- Every Config.Telemetry.INSTANCES_SAMPLE_SEC it samples this client's instance count and what the
-- other players add to it. Every INSTANCES_CLIENT_BATCH_SEC the pending samples go to the server over
-- the InstanceProbeReport RemoteEvent. The server validates them and posts aggregates
-- (Server/Net/InstanceTelemetry). Off when INSTANCES_ENABLED or Config.Telemetry.ENABLED is false.
-- Reads of other players are pcall-wrapped: a player can leave in the middle of the loop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stats = game:GetService("Stats")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local InstanceProbeClient = {}

type Sample = { [string]: number }

local REMOTE_NAME = "InstanceProbeReport"
-- The server accepts at most 10 entries per batch.
local MAX_PENDING = 10

local function telemetryConfig(): any
	local t = Config.Telemetry
	return if type(t) == "table" then t else {}
end

local function positiveSeconds(value: any, default: number): number
	local n = tonumber(value)
	if n ~= nil and n > 0 then
		return n
	end
	return default
end

local function enabled(): boolean
	local t = telemetryConfig()
	return t.INSTANCES_ENABLED == true and t.ENABLED == true
end

-- Descendant count of the container that `getContainer` returns. A missing container or a failed
-- read counts as 0.
local function safeDescendants(getContainer: () -> Instance?): number
	local ok, count = pcall(function()
		local container = getContainer()
		if container == nil then
			return 0
		end
		return #container:GetDescendants()
	end)
	return if ok then count else 0
end

local function takeSample(localPlayer: Player): Sample
	local others, backpack, character = 0, 0, 0
	for _, player in Players:GetPlayers() do
		if player ~= localPlayer then
			others += 1
			backpack += safeDescendants(function()
				return player.Backpack
			end)
			character += safeDescendants(function()
				return player.Character
			end)
		end
	end
	return {
		clientIC = (Stats :: any).InstanceCount or 0,
		memMb = Stats:GetTotalMemoryUsageMb(),
		others = others,
		othersBackpack = backpack,
		othersCharacter = character,
		ownPlayerGui = safeDescendants(function()
			return localPlayer:FindFirstChildOfClass("PlayerGui")
		end),
	}
end

local function findRemote(): RemoteEvent?
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 60)
	local remote = if remotes then remotes:WaitForChild(REMOTE_NAME, 60) else nil
	if remote ~= nil and remote:IsA("RemoteEvent") then
		return remote :: RemoteEvent
	end
	return nil
end

--- Starts the sampler. Does nothing when the probe is off in the config.
function InstanceProbeClient.start()
	if not enabled() then
		return
	end
	local t = telemetryConfig()
	local sampleSec = positiveSeconds(t.INSTANCES_SAMPLE_SEC, 60)
	local batchSec = positiveSeconds(t.INSTANCES_CLIENT_BATCH_SEC, 300)
	local localPlayer = Players.LocalPlayer
	task.spawn(function()
		local remote = findRemote()
		if remote == nil then
			return
		end
		local pending: { Sample } = {}
		local sinceBatch = 0
		while true do
			task.wait(sampleSec)
			table.insert(pending, takeSample(localPlayer))
			if #pending > MAX_PENDING then
				table.remove(pending, 1)
			end
			sinceBatch += sampleSec
			if sinceBatch >= batchSec then
				sinceBatch = 0
				remote:FireServer(pending)
				pending = {}
			end
		end
	end)
end

return InstanceProbeClient
