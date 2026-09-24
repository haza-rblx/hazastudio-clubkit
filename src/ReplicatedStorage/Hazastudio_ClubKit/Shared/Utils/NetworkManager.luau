--!strict
-- NetworkManager — Per-frame batched network transport (Guidelines v3 N1).
-- Controllers MUST use this instead of remote:FireClient / FireAllClients.
--
-- Default: queue fires and flush once per Heartbeat (reduces per-call overhead).
-- Latency-sensitive one-shots (announce, paid broadcast): fire*Immediate or flushNow().
--
-- R9 (P2): When Config.Network.ENABLE_SHARED_FLUSH is true, the flush is registered
-- with the shared NetworkFlushScheduler instead of opening a per-instance Heartbeat
-- connection. See: _non_rojo/Guidelines_v3/refs/REF_NETWORK.md
--
-- Frame coalesce (Config.Network.ENABLE_FRAME_COALESCE): same-key entries within one
-- flush window collapse to one. Key = (TargetKind, player UserId(s), data.kind,
-- data.userId). Delta kinds listed in Config.Network.COALESCE_MERGE_FIELDS (overhead
-- delta) are MERGED field by field (later wins); every other kind keeps the *last*
-- entry. Rules + spec: Shared/Utils/NetworkCoalesce. Do NOT rely on coalesce for
-- order-sensitive multi-message streams that share a key — use distinct `data.kind`
-- or Immediate. Immediate still goes through the queue then flushNow(); coalesce
-- applies within that same flush.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local NetworkFlushScheduler = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkFlushScheduler)
local NetworkCoalesce = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkCoalesce)

-- Global counter for unique instance IDs (R9.3–R9.5).
local nextInstanceId = 0

-- ── Types ─────────────────────────────────────────────────────

type TargetKind = "player" | "all" | "allExcept" | "list" | "server"

type OutboundEntry = {
	kind: TargetKind,
	player: Player?,
	players: { Player }?,
	data: any,
}

type NetworkManagerDeps = {
	reliable: RemoteEvent,
	unreliable: UnreliableRemoteEvent?,
	logger: any,
	isServer: boolean,
}

local function useFrameCoalesce(): boolean
	return Config.Network.ENABLE_FRAME_COALESCE == true
end

--- One entry per coalesce key, first-seen order. Delta kinds (Config.Network.COALESCE_MERGE_FIELDS)
--- are merged field by field; everything else keeps the last entry. Rules: NetworkCoalesce.
local function coalesceQueue(queue: { OutboundEntry }): { OutboundEntry }
	if #queue <= 1 or not useFrameCoalesce() then
		return queue
	end
	return NetworkCoalesce.coalesce(queue :: any, Config.Network.COALESCE_MERGE_FIELDS) :: any
end

-- ── Factory ───────────────────────────────────────────────────

local function create(deps: NetworkManagerDeps)
	local reliable = deps.reliable
	local unreliable = deps.unreliable
	local log = deps.logger
	local isServer = deps.isServer

	-- Generate a unique instance ID for scheduler registration (R9.3).
	nextInstanceId += 1
	local instanceId = string.format("NetworkManager_%d_%s", nextInstanceId, reliable.Name)

	-- Outbound queues — flushed once per Heartbeat
	local reliableQueue: { OutboundEntry } = {}
	local unreliableQueue: { OutboundEntry } = {}
	local connections: { RBXScriptConnection } = {}

	-- ── Flush Logic ───────────────────────────────────────────

	local function dispatchServer(entry: OutboundEntry, remote: RemoteEvent | UnreliableRemoteEvent)
		if entry.kind == "all" then
			remote:FireAllClients(entry.data)
		elseif entry.kind == "allExcept" and entry.player then
			for _, player in Players:GetPlayers() do
				if player ~= entry.player then
					remote:FireClient(player, entry.data)
				end
			end
		elseif entry.kind == "player" and entry.player then
			remote:FireClient(entry.player, entry.data)
		elseif entry.kind == "list" and entry.players then
			for _, player in entry.players do
				remote:FireClient(player, entry.data)
			end
		end
	end

	local function flushQueue(queue: { OutboundEntry }, remote: RemoteEvent | UnreliableRemoteEvent)
		if #queue == 0 then
			return
		end

		local toSend = coalesceQueue(queue)

		if isServer then
			for _, entry in toSend do
				dispatchServer(entry, remote)
			end
		else
			for _, entry in toSend do
				remote:FireServer(entry.data)
			end
		end

		table.clear(queue)
	end

	-- R9: Register with shared scheduler instead of opening per-instance Heartbeat (R9.1, R9.2, R9.5).
	-- Per-instance FIFO and empty-queue skipping are preserved by the per-instance flush queue
	-- design; the scheduler only fans out the per-frame tick (R9.3, R9.4).
	if Config.Network.ENABLE_SHARED_FLUSH then
		local function sharedFlush()
			if #reliableQueue > 0 then
				flushQueue(reliableQueue, reliable)
			end
			if unreliable and #unreliableQueue > 0 then
				flushQueue(unreliableQueue, unreliable)
			end
		end
		NetworkFlushScheduler.register(instanceId, sharedFlush)
		log:info("NetworkManager registered with shared flush scheduler", { instanceId = instanceId })
	else
		-- Legacy: per-instance Heartbeat connection
		table.insert(connections, RunService.Heartbeat:Connect(function()
			flushQueue(reliableQueue, reliable)
			if unreliable then
				flushQueue(unreliableQueue, unreliable)
			end
		end))
	end

	-- ── Public API ────────────────────────────────────────────

	local self = {}

	--- Queue a reliable fire to a single player.
	--- Flushed automatically on next Heartbeat.
	function self:fireClient(player: Player, data: any)
		table.insert(reliableQueue, {
			kind = "player",
			player = player,
			data = data,
		})
	end

	--- Queue a reliable fire to all players.
	function self:fireAllClients(data: any)
		table.insert(reliableQueue, {
			kind = "all",
			data = data,
		})
	end

	--- Queue a reliable fire to all players except one.
	function self:fireAllExcept(exclude: Player, data: any)
		table.insert(reliableQueue, {
			kind = "allExcept",
			player = exclude,
			data = data,
		})
	end

	--- Queue a reliable fire to a list of players.
	function self:fireList(players: { Player }, data: any)
		table.insert(reliableQueue, {
			kind = "list",
			players = players,
			data = data,
		})
	end

	--- Queue an unreliable fire to a single player.
	--- Use for cosmetic/visual-only data. May be dropped under congestion.
	function self:fireClientUnreliable(player: Player, data: any)
		if not unreliable then
			log:warn("Unreliable remote not configured, falling back to reliable")
			self:fireClient(player, data)
			return
		end
		table.insert(unreliableQueue, {
			kind = "player",
			player = player,
			data = data,
		})
	end

	--- Queue an unreliable fire to all players.
	--- Use for cosmetic/visual-only data. May be dropped under congestion.
	function self:fireAllClientsUnreliable(data: any)
		if not unreliable then
			log:warn("Unreliable remote not configured, falling back to reliable")
			self:fireAllClients(data)
			return
		end
		table.insert(unreliableQueue, {
			kind = "all",
			data = data,
		})
	end

	--- Client: queue a fire to server (reliable).
	function self:fireServer(data: any)
		table.insert(reliableQueue, {
			kind = "server",
			data = data,
		})
	end

	--- Flush queued reliable (and unreliable) fires immediately.
	function self:flushNow()
		flushQueue(reliableQueue, reliable)
		if unreliable then
			flushQueue(unreliableQueue, unreliable)
		end
	end

	--- Queue then flush in the same call (announce / paid broadcast UX).
	--- Note: coalesce still applies if multiple same-key entries sit in the queue;
	--- a single Immediate call is unaffected. Prefer distinct data.kind for fan-outs
	--- that must not merge within the same frame.
	function self:fireClientImmediate(player: Player, data: any)
		self:fireClient(player, data)
		self:flushNow()
	end

	function self:fireAllClientsImmediate(data: any)
		self:fireAllClients(data)
		self:flushNow()
	end

	function self:fireListImmediate(players: { Player }, data: any)
		self:fireList(players, data)
		self:flushNow()
	end

	--- Cleanup — disconnect Heartbeat (or unregister from shared scheduler), clear queues.
	--- MUST be called in onDestroy() or BindToClose().
	function self:destroy()
		-- R9: Unregister from shared scheduler if registered (R9.5, R9.6).
		if Config.Network.ENABLE_SHARED_FLUSH then
			NetworkFlushScheduler.unregister(instanceId)
		else
			for _, conn in connections do
				conn:Disconnect()
			end
			table.clear(connections)
		end
		table.clear(reliableQueue)
		table.clear(unreliableQueue)
	end

	log:info("NetworkManager initialized", {
		isServer = isServer,
		hasUnreliable = unreliable ~= nil,
		frameCoalesce = useFrameCoalesce(),
	})

	return self
end

return { create = create }
