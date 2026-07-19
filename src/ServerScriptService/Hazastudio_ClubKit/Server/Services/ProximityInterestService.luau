--!strict
-- Server/Services/ProximityInterestService.luau
--
-- Owns the single View_Range recompute loop and drives subscribe/unsubscribe
-- on the shared InterestManager. It does NOT fire any remotes — it only
-- maintains channel membership and emits enter/leave events that controllers
-- (OverheadController, SyncService) react to.
--
-- Membership model (Requirement 1.9–1.11):
--   - Recompute runs at a fixed cadence no greater than 1s.
--   - A viewer B becomes a subscriber of subject A when the straight-line
--     distance between their characters is within VIEW_RANGE_RADIUS.
--   - Hysteresis: once B is a member of A, B stays a member until the distance
--     exceeds VIEW_RANGE_RADIUS + HYSTERESIS_BUFFER. While the distance lies in
--     the buffer band, membership never toggles.
--   - If either player in a pair has no live character at recompute time, the
--     pair is treated as not visible and the affected player is removed from the
--     other's set until both have live characters.
--
-- Channel naming convention (feature:subjectUserId), one set drives both:
--   overhead:<subjectUserId>   viewers who can see the subject's nametag
--   sync:<subjectUserId>       viewers who receive the subject's sync updates
--
-- Layer rules:
--   - Pure spatial coordinator. No DataStore, no remote fires.
--   - Calls InterestManager API only; emits events for consumers.
--   - Owns connections + per-pair membership state, cleans up via Cleaner.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Cleaner = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cleaner)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local CharacterReady = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.CharacterReady)

type ILogger = Types.ILogger

-- Minimal structural type for the shared InterestManager (reused as-is).
type InterestManager = {
	subscribe: (self: InterestManager, player: Player, channel: string) -> () -> (),
	getSubscribers: (self: InterestManager, channel: string) -> { Player },
	isSubscribed: (self: InterestManager, player: Player, channel: string) -> boolean,
	removePlayer: (self: InterestManager, player: Player) -> (),
}

export type SubscriberEvent = {
	subject: Player,
	viewer: Player,
	channelPrefix: string,
}

type SubscriberListener = (event: SubscriberEvent) -> ()

export type ProximityInterestDeps = {
	interest: InterestManager,
	config: any?, -- Config.Interest { VIEW_RANGE_RADIUS, HYSTERESIS_BUFFER, RECOMPUTE_INTERVAL }
	logger: ILogger?,
}

export type ProximityInterestService = {
	onStart: (self: ProximityInterestService) -> (),
	onDestroy: (self: ProximityInterestService) -> (),
	getSubscribers: (self: ProximityInterestService, channelPrefix: string, subject: Player) -> { Player },
	onSubscriberAdded: (self: ProximityInterestService, listener: SubscriberListener) -> () -> (),
	onSubscriberRemoved: (self: ProximityInterestService, listener: SubscriberListener) -> () -> (),
	removePlayer: (self: ProximityInterestService, player: Player) -> (),
	--- Force an immediate membership pass (respawn / PartsReady). No-op-cheap when
	--- positions unchanged; restores self+nearby that the HRP gap pruned.
	recomputeNow: (self: ProximityInterestService) -> (),
}

-- A single membership entry: holds the player refs (for events) and the
-- InterestManager unsubscribe closures for every managed channel prefix.
type PairEntry = {
	subject: Player,
	viewer: Player,
	unsubs: { () -> () },
}

-- The recompute drives both the overhead and sync channels from one set.
local CHANNEL_PREFIXES = { "overhead:", "sync:" }

-- Tunable defaults; overridable via Config.Interest. The cadence is clamped to
-- the Requirement 1.9 ceiling of 1 second regardless of config.
local DEFAULT_VIEW_RANGE_RADIUS = 55
local DEFAULT_HYSTERESIS_BUFFER = 15
local DEFAULT_RECOMPUTE_INTERVAL = 0.5
local MIN_RECOMPUTE_INTERVAL = 0.05
local MAX_RECOMPUTE_INTERVAL = 1.0

local ProximityInterestService = {}

local function getPlayerPosition(player: Player): Vector3?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	return root.Position
end

function ProximityInterestService.create(deps: ProximityInterestDeps): ProximityInterestService
	assert(deps and deps.interest, "ProximityInterestService requires deps.interest")
	local interest = deps.interest
	local log: ILogger = deps.logger or Logger.new("ProximityInterestService")

	local cfg = deps.config or {}
	local useLegacy = cfg.USE_LEGACY_VIEW_RANGE == true
	local radius = if useLegacy
		then (tonumber(cfg.LEGACY_VIEW_RANGE_RADIUS) or 80)
		else (tonumber(cfg.VIEW_RANGE_RADIUS) or DEFAULT_VIEW_RANGE_RADIUS)
	local buffer = if useLegacy
		then (tonumber(cfg.LEGACY_HYSTERESIS_BUFFER) or 20)
		else (tonumber(cfg.HYSTERESIS_BUFFER) or DEFAULT_HYSTERESIS_BUFFER)
	local recomputeInterval = math.clamp(
		tonumber(cfg.RECOMPUTE_INTERVAL) or DEFAULT_RECOMPUTE_INTERVAL,
		MIN_RECOMPUTE_INTERVAL,
		MAX_RECOMPUTE_INTERVAL
	)
	-- The outer boundary at which an existing member is dropped (hysteresis).
	local leaveRadius = radius + buffer

	if not deps.config then
		log:warn("Config.Interest missing; using built-in defaults", {
			radius = radius,
			buffer = buffer,
			recomputeInterval = recomputeInterval,
		})
	elseif useLegacy then
		log:info("ProximityInterest using legacy view range", {
			radius = radius,
			buffer = buffer,
			leaveRadius = leaveRadius,
		})
	end

	local cleaner = Cleaner.new()

	-- subjectUserId -> viewerUserId -> PairEntry
	local members: { [number]: { [number]: PairEntry } } = {}

	local addedListeners: { SubscriberListener } = {}
	local removedListeners: { SubscriberListener } = {}

	local tickAccumulator = 0

	local self = {} :: ProximityInterestService

	-- ── Event emission ────────────────────────────────────────
	local function emit(listeners: { SubscriberListener }, subject: Player, viewer: Player)
		if #listeners == 0 then
			return
		end
		for _, prefix in CHANNEL_PREFIXES do
			local event: SubscriberEvent = { subject = subject, viewer = viewer, channelPrefix = prefix }
			-- Snapshot listeners so a listener that unsubscribes during dispatch
			-- does not perturb the in-flight iteration.
			for _, listener in table.clone(listeners) do
				local ok, err = pcall(listener, event)
				if not ok then
					log:error("Subscriber listener errored", { channelPrefix = prefix, err = tostring(err) })
				end
			end
		end
	end

	-- ── Membership primitives ─────────────────────────────────
	local function isMember(subjectId: number, viewerId: number): boolean
		local bySubject = members[subjectId]
		return bySubject ~= nil and bySubject[viewerId] ~= nil
	end

	local function addMember(subject: Player, viewer: Player)
		local subjectId, viewerId = subject.UserId, viewer.UserId
		local bySubject = members[subjectId]
		if not bySubject then
			bySubject = {}
			members[subjectId] = bySubject
		end
		if bySubject[viewerId] then
			return
		end

		local unsubs: { () -> () } = {}
		for _, prefix in CHANNEL_PREFIXES do
			table.insert(unsubs, interest:subscribe(viewer, prefix .. tostring(subjectId)))
		end
		bySubject[viewerId] = { subject = subject, viewer = viewer, unsubs = unsubs }

		emit(addedListeners, subject, viewer)
	end

	local function removeMember(subjectId: number, viewerId: number)
		local bySubject = members[subjectId]
		if not bySubject then
			return
		end
		local entry = bySubject[viewerId]
		if not entry then
			return
		end

		bySubject[viewerId] = nil
		if not next(bySubject) then
			members[subjectId] = nil
		end

		for _, unsub in entry.unsubs do
			pcall(unsub)
		end

		emit(removedListeners, entry.subject, entry.viewer)
	end

	-- ── Spatial Grid Helpers ─────────────────────────────────
	-- Spatial grid partitioning to reduce O(N²) to O(N × average_cell_density).
	-- Grid cell size = leaveRadius ensures all potential neighbors are in
	-- the same cell or adjacent 8 cells (9 cells total in 2D).
	local function getCellKey(position: Vector3, cellSize: number): string
		local x = math.floor(position.X / cellSize)
		local z = math.floor(position.Z / cellSize)
		return string.format("%d,%d", x, z)
	end

	local function getNeighborCells(cellKey: string): { string }
		local x, z = string.match(cellKey, "([^,]+),([^,]+)")
		x, z = tonumber(x), tonumber(z)
		if not x or not z then
			return { cellKey }
		end
		-- Return 9 cells: center + 8 neighbors
		return {
			string.format("%d,%d", x - 1, z - 1),
			string.format("%d,%d", x, z - 1),
			string.format("%d,%d", x + 1, z - 1),
			string.format("%d,%d", x - 1, z),
			cellKey, -- center
			string.format("%d,%d", x + 1, z),
			string.format("%d,%d", x - 1, z + 1),
			string.format("%d,%d", x, z + 1),
			string.format("%d,%d", x + 1, z + 1),
		}
	end

	-- ── Recompute (Requirement 1.9–1.11) ──────────────────────
	local function recompute()
		-- Snapshot positions of players with a LIVE character only. Players with
		-- no live character are absent here, so any pair involving them is
		-- pruned below and never (re)added (R1.11).
		local positions: { [number]: Vector3 } = {}
		local playerById: { [number]: Player } = {}
		for _, player in Players:GetPlayers() do
			local pos = getPlayerPosition(player)
			if pos then
				positions[player.UserId] = pos
				playerById[player.UserId] = player
			end
		end

		-- Prune pass: drop memberships that lost a live character (R1.11) or
		-- crossed the outer hysteresis boundary (R1.10 leave).
		for subjectId, bySubject in members do
			for viewerId in bySubject do
				local subjectPos = positions[subjectId]
				local viewerPos = positions[viewerId]
				if subjectId == viewerId then
					-- Self membership is retained while the player is live.
					if not subjectPos then
						removeMember(subjectId, viewerId)
					end
				elseif not subjectPos or not viewerPos then
					removeMember(subjectId, viewerId)
				else
					local distance = (subjectPos - viewerPos).Magnitude
					if distance > leaveRadius then
						removeMember(subjectId, viewerId)
					end
				end
			end
		end

		-- Build spatial grid: cellKey -> { userId1, userId2, ... }
		-- Cell size = leaveRadius ensures neighbors are within 1 cell away.
		local grid: { [string]: { number } } = {}
		local cellSize = leaveRadius
		for userId, position in positions do
			local cellKey = getCellKey(position, cellSize)
			if not grid[cellKey] then
				grid[cellKey] = {}
			end
			table.insert(grid[cellKey], userId)
		end

		-- Add pass: self membership plus distance-based joins (R1.9).
		-- Only check players in same cell + 8 neighbor cells instead of all players.
		for subjectId, subjectPos in positions do
			local subject = playerById[subjectId]
			-- A player is always a member of their own channel so they see their
			-- own nametag (matches the legacy broadcastPayload(self) behavior).
			if not isMember(subjectId, subjectId) then
				addMember(subject, subject)
			end

			-- Get subject's cell and neighbors
			local subjectCellKey = getCellKey(subjectPos, cellSize)
			local neighborCells = getNeighborCells(subjectCellKey)

			-- Only check players in nearby cells
			for _, cellKey in neighborCells do
				local cellPlayers = grid[cellKey]
				if cellPlayers then
					for _, viewerId in cellPlayers do
						if subjectId ~= viewerId and not isMember(subjectId, viewerId) then
							local viewerPos = positions[viewerId]
							local distance = (subjectPos - viewerPos).Magnitude
							if distance <= radius then
								addMember(subject, playerById[viewerId])
							end
						end
					end
				end
			end
		end
	end

	-- ── Public API ────────────────────────────────────────────
	function self:getSubscribers(channelPrefix: string, subject: Player): { Player }
		return interest:getSubscribers(channelPrefix .. tostring(subject.UserId))
	end

	function self:onSubscriberAdded(listener: SubscriberListener): () -> ()
		table.insert(addedListeners, listener)
		return function()
			local index = table.find(addedListeners, listener)
			if index then
				table.remove(addedListeners, index)
			end
		end
	end

	function self:onSubscriberRemoved(listener: SubscriberListener): () -> ()
		table.insert(removedListeners, listener)
		return function()
			local index = table.find(removedListeners, listener)
			if index then
				table.remove(removedListeners, index)
			end
		end
	end

	function self:removePlayer(player: Player)
		local userId = player.UserId

		-- Remove as subject: drop every viewer of this subject's channels.
		local bySubject = members[userId]
		if bySubject then
			-- Collect first; removeMember mutates `members` during iteration.
			local viewerIds: { number } = {}
			for viewerId in bySubject do
				table.insert(viewerIds, viewerId)
			end
			for _, viewerId in viewerIds do
				removeMember(userId, viewerId)
			end
		end

		-- Remove as viewer: drop this viewer from every subject's channels.
		local subjectIds: { number } = {}
		for subjectId, subs in members do
			if subs[userId] then
				table.insert(subjectIds, subjectId)
			end
		end
		for _, subjectId in subjectIds do
			removeMember(subjectId, userId)
		end

		-- Safety net (R1.7): clear any residual channel membership the manager
		-- still holds for this player as a subscriber.
		interest:removePlayer(player)
	end

	function self:recomputeNow()
		tickAccumulator = 0
		recompute()
	end

	local function schedulePartsReadyRecompute(player: Player, character: Model)
		task.spawn(function()
			if not CharacterReady.isReady(character, "parts") then
				local snap = CharacterReady.wait(character, "parts")
				if not snap then
					return
				end
			end
			if player.Character ~= character or not player.Parent then
				return
			end
			-- Immediate self+nearby restore after HRP gap (respawn / LoadCharacter).
			-- Heartbeat alone can leave a ≤RECOMPUTE_INTERVAL blank-tag window.
			self:recomputeNow()
		end)
	end

	local function watchPlayerCharacter(player: Player)
		cleaner:add(player.CharacterAdded:Connect(function(character)
			if character:IsA("Model") then
				schedulePartsReadyRecompute(player, character)
			end
		end))
		local existing = player.Character
		if existing and existing:IsA("Model") then
			schedulePartsReadyRecompute(player, existing)
		end
	end

	function self:onStart()
		cleaner:add(RunService.Heartbeat:Connect(function(dt)
			tickAccumulator += dt
			if tickAccumulator < recomputeInterval then
				return
			end
			tickAccumulator = 0
			recompute()
		end))

		cleaner:add(Players.PlayerRemoving:Connect(function(player)
			self:removePlayer(player)
		end))

		cleaner:add(Players.PlayerAdded:Connect(function(player)
			watchPlayerCharacter(player)
		end))
		for _, player in Players:GetPlayers() do
			watchPlayerCharacter(player)
		end

		log:info("ProximityInterestService started (spatial grid optimized)", {
			radius = radius,
			buffer = buffer,
			leaveRadius = leaveRadius,
			useLegacy = useLegacy,
			recomputeInterval = recomputeInterval,
			algorithm = "spatial_grid_partitioning",
			cellSize = leaveRadius,
		})
	end

	function self:onDestroy()
		cleaner:clean()
		-- Release every outstanding InterestManager subscription.
		for subjectId, bySubject in members do
			for viewerId, entry in bySubject do
				for _, unsub in entry.unsubs do
					pcall(unsub)
				end
				bySubject[viewerId] = nil
			end
			members[subjectId] = nil
		end
		table.clear(addedListeners)
		table.clear(removedListeners)
	end

	return self
end

return ProximityInterestService
