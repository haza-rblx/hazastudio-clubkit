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
--
-- Production hardening P4 (plan H3), Config.NetworkPerf.PROXIMITY_MODE = "incremental":
--   - subjects are evaluated in PROXIMITY_GROUPS staggered groups (userId % groups), one group
--     per PROXIMITY_TICK_INTERVAL, so each subject is re-evaluated every groups x interval;
--   - squared distances on plain numbers; a PROXIMITY_CELL_SIZE grid queried by bounding box;
--   - at most PROXIMITY_MAX_SUBSCRIBERS nearest viewers per subject (self not counted); once a
--     subject is full, only candidates nearer than (farthest member - PROXIMITY_SWAP_MARGIN)
--     are even looked at, and one displaces the farthest member only past that margin;
--   - at most PROXIMITY_MAX_ENTERS_PER_VIEWER new subscriptions per viewer per 0.5 s (each is a
--     full Snapshot-on-enter), nearest first per subject;
--   - recomputePlayer(player) (spawn) re-evaluates that player's row only, as subject and as
--     viewer, deduped per player within 0.1 s.
-- "legacy" keeps the pre-P4 full pass every RECOMPUTE_INTERVAL.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Cleaner = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cleaner)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local CharacterReady = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.CharacterReady)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

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
	-- P4 seams (crowd harness / specs): who is in the server, where they stand, and the clock.
	-- Defaults: Players:GetPlayers(), HumanoidRootPart.Position, os.clock. `perf` overrides
	-- Config.NetworkPerf. Positions only need .X / .Y / .Z in incremental mode.
	getPlayers: (() -> { Player })?,
	getPosition: ((player: Player) -> any?)?,
	clock: (() -> number)?,
	perf: any?,
}

export type ProximityStats = {
	mode: string,
	subjects: number,
	pairs: number,
	lastTickMs: number,
	lastTickEvaluations: number,
	lastTickCandidates: number,
	adds: number,
	removes: number,
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
	--- P4: O(1) — is `viewer` subscribed to `subject`'s channels?
	isSubscriber: (self: ProximityInterestService, subject: Player, viewer: Player) -> boolean,
	--- P4: re-evaluate one player's row (spawn). Falls back to recomputeNow in legacy mode.
	recomputePlayer: (self: ProximityInterestService, player: Player) -> (),
	--- P4: advance the recompute clock by `dt` (the Heartbeat handler; harness/spec driver).
	step: (self: ProximityInterestService, dt: number) -> (),
	stats: (self: ProximityInterestService) -> ProximityStats,
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
	local getPlayers: () -> { Player } = deps.getPlayers or function()
		return Players:GetPlayers()
	end
	local getPosition: (Player) -> any? = deps.getPosition or getPlayerPosition
	local clock: () -> number = deps.clock or os.clock

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

	-- P4 (H3) incremental mode settings (Config.NetworkPerf, overridable via deps.perf).
	local perf = deps.perf or (Config :: any).NetworkPerf
	local incremental = type(perf) == "table" and perf.PROXIMITY_MODE == "incremental"
	local function perfNumber(key: string, default: number): number
		local value = if type(perf) == "table" then tonumber(perf[key]) else nil
		return if value ~= nil then value else default
	end
	local tickInterval = math.clamp(perfNumber("PROXIMITY_TICK_INTERVAL", 0.25), MIN_RECOMPUTE_INTERVAL, MAX_RECOMPUTE_INTERVAL)
	local groupCount = math.max(1, math.floor(perfNumber("PROXIMITY_GROUPS", 4)))
	local gridCellSize = math.max(4, perfNumber("PROXIMITY_CELL_SIZE", 16))
	local subscriberCap = math.max(0, math.floor(perfNumber("PROXIMITY_MAX_SUBSCRIBERS", 0)))
	local swapMargin = math.max(0, perfNumber("PROXIMITY_SWAP_MARGIN", 0))
	local maxEnters = math.max(0, math.floor(perfNumber("PROXIMITY_MAX_ENTERS_PER_VIEWER", 0)))
	local ENTER_WINDOW = 0.5
	local RECOMPUTE_PLAYER_DEDUPE = 0.1
	local radius2 = radius * radius
	local leave2 = leaveRadius * leaveRadius

	local cleaner = Cleaner.new()

	-- subjectUserId -> viewerUserId -> PairEntry
	local members: { [number]: { [number]: PairEntry } } = {}
	-- P4: viewerUserId -> set of subjectUserIds (O(k) leave), non-self member count per subject.
	local viewerIndex: { [number]: { [number]: boolean } } = {}
	local memberCount: { [number]: number } = {}
	local pairTotal = 0
	local addTotal = 0
	local removeTotal = 0

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
		local subjects = viewerIndex[viewerId]
		if not subjects then
			subjects = {}
			viewerIndex[viewerId] = subjects
		end
		subjects[subjectId] = true
		if viewerId ~= subjectId then
			memberCount[subjectId] = (memberCount[subjectId] or 0) + 1
		end
		pairTotal += 1
		addTotal += 1

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
		local subjects = viewerIndex[viewerId]
		if subjects then
			subjects[subjectId] = nil
			if not next(subjects) then
				viewerIndex[viewerId] = nil
			end
		end
		if viewerId ~= subjectId then
			local count = (memberCount[subjectId] or 1) - 1
			memberCount[subjectId] = if count > 0 then count else nil
		end
		pairTotal -= 1
		removeTotal += 1

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
		for _, player in getPlayers() do
			local pos = getPosition(player)
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

	-- ── Incremental recompute (P4, plan H3) ───────────────────
	-- Snapshot of live positions (plain numbers) + a bounding-box-queried grid, rebuilt per tick.
	local snapPlayers: { [number]: Player } = {}
	local px: { [number]: number } = {}
	local py: { [number]: number } = {}
	local pz: { [number]: number } = {}
	local grid: { [number]: { number } } = {}
	local enterWindowStart = -math.huge
	local entersByViewer: { [number]: number } = {}
	local lastRecomputeAt: { [number]: number } = {}
	local tickIndex = 0
	local lastTickMs = 0
	local lastTickEvaluations = 0
	local lastTickCandidates = 0
	local candidatesThisPass = 0

	local function gridKey(cx: number, cz: number): number
		return cx * 1048576 + cz
	end

	local function snapshotPositions()
		table.clear(snapPlayers)
		table.clear(px)
		table.clear(py)
		table.clear(pz)
		table.clear(grid)
		for _, player in getPlayers() do
			local pos = getPosition(player)
			if pos then
				local id = player.UserId
				local x, z = pos.X, pos.Z
				snapPlayers[id] = player
				px[id] = x
				py[id] = pos.Y
				pz[id] = z
				local key = gridKey(math.floor(x / gridCellSize), math.floor(z / gridCellSize))
				local cell = grid[key]
				if not cell then
					cell = {}
					grid[key] = cell
				end
				cell[#cell + 1] = id
			end
		end
	end

	local function distance2(a: number, b: number): number
		local dx, dy, dz = px[a] - px[b], py[a] - py[b], pz[a] - pz[b]
		return dx * dx + dy * dy + dz * dz
	end

	-- Ids within sqrt(r2) of `centerId` (3D), excluding `centerId` and ids in `skip` (current
	-- members: in a full dense row most of the box is already subscribed); d2 into `d2Out`.
	local function queryNear(centerId: number, r2: number, out: { number }, d2Out: { [number]: number }, skip: { [number]: any }?)
		local r = math.sqrt(r2)
		local cx, cy, cz = px[centerId], py[centerId], pz[centerId]
		for gx = math.floor((cx - r) / gridCellSize), math.floor((cx + r) / gridCellSize) do
			for gz = math.floor((cz - r) / gridCellSize), math.floor((cz + r) / gridCellSize) do
				local cell = grid[gridKey(gx, gz)]
				if cell then
					for _, id in cell do
						if id ~= centerId and not (skip and skip[id]) then
							candidatesThisPass += 1
							local dx, dy, dz = px[id] - cx, py[id] - cy, pz[id] - cz
							local d2 = dx * dx + dy * dy + dz * dz
							if d2 <= r2 then
								out[#out + 1] = id
								d2Out[id] = d2
							end
						end
					end
				end
			end
		end
	end

	local function enterAllowed(viewerId: number): boolean
		if maxEnters <= 0 then
			return true
		end
		local now = clock()
		if now - enterWindowStart >= ENTER_WINDOW then
			enterWindowStart = now
			table.clear(entersByViewer)
		end
		return (entersByViewer[viewerId] or 0) < maxEnters
	end

	local function noteEnter(viewerId: number)
		if maxEnters > 0 then
			entersByViewer[viewerId] = (entersByViewer[viewerId] or 0) + 1
		end
	end

	-- Farthest non-self member of a subject (members all have snapshot positions after pruning).
	local function subjectCapFull(subjectId: number): boolean
		return subscriberCap > 0 and (memberCount[subjectId] or 0) >= subscriberCap
	end

	local function findFarthest(subjectId: number): (number?, number)
		local bySubject = members[subjectId]
		local farId: number? = nil
		local farD2 = -1
		if bySubject then
			for viewerId in bySubject do
				if viewerId ~= subjectId and px[viewerId] ~= nil then
					local d2 = distance2(subjectId, viewerId)
					if d2 > farD2 then
						farD2 = d2
						farId = viewerId
					end
				end
			end
		end
		return farId, farD2
	end

	local function dropSubject(subjectId: number)
		local bySubject = members[subjectId]
		if not bySubject then
			return
		end
		local viewerIds: { number } = {}
		for viewerId in bySubject do
			table.insert(viewerIds, viewerId)
		end
		for _, viewerId in viewerIds do
			removeMember(subjectId, viewerId)
		end
	end

	-- `viewerId` wants in to `subjectId` (distance² d2): add under the cap, or displace the
	-- farthest member when clearly nearer. Returns false once the subject is full and this
	-- candidate does not beat the farthest (callers iterating nearest-first can stop).
	local function tryAdd(subjectId: number, viewerId: number, d2: number): boolean
		if not enterAllowed(viewerId) then
			return true
		end
		local subject = snapPlayers[subjectId]
		local viewer = snapPlayers[viewerId]
		if subjectCapFull(subjectId) then
			local farId, farD2 = findFarthest(subjectId)
			if farId == nil or math.sqrt(d2) + swapMargin >= math.sqrt(farD2) then
				return false
			end
			removeMember(subjectId, farId)
		end
		addMember(subject, viewer)
		noteEnter(viewerId)
		return true
	end

	-- One subject's row: self, prune past the leave radius / lost characters, then admit the
	-- nearest candidates (only those that could beat the farthest member once full).
	local function evaluateSubject(subjectId: number)
		if px[subjectId] == nil then
			dropSubject(subjectId)
			return
		end
		local subject = snapPlayers[subjectId]
		if not isMember(subjectId, subjectId) then
			addMember(subject, subject)
		end
		local bySubject = members[subjectId]
		local drop: { number }? = nil
		local farD2 = -1
		local sx, sy, sz = px[subjectId], py[subjectId], pz[subjectId]
		if bySubject then
			for viewerId in bySubject do
				if viewerId ~= subjectId then
					local vx = px[viewerId]
					if vx == nil then
						drop = drop or {}
						table.insert(drop :: { number }, viewerId)
					else
						local dx, dy, dz = vx - sx, py[viewerId] - sy, pz[viewerId] - sz
						local d2 = dx * dx + dy * dy + dz * dz
						if d2 > leave2 then
							drop = drop or {}
							table.insert(drop :: { number }, viewerId)
						elseif d2 > farD2 then
							farD2 = d2
						end
					end
				end
			end
		end
		if drop then
			for _, viewerId in drop do
				removeMember(subjectId, viewerId)
			end
		end
		local searchR2 = radius2
		if subjectCapFull(subjectId) then
			if farD2 < 0 then
				return
			end
			local reach = math.sqrt(farD2) - swapMargin
			if reach <= 0 then
				return
			end
			searchR2 = math.min(radius2, reach * reach)
		end
		local fresh: { number } = {}
		local candidateD2: { [number]: number } = {}
		queryNear(subjectId, searchR2, fresh, candidateD2, members[subjectId])
		if #fresh == 0 then
			return
		end
		-- Nearest-first only matters when not every candidate fits.
		if subscriberCap > 0 and #fresh > math.max(1, subscriberCap - (memberCount[subjectId] or 0)) then
			table.sort(fresh, function(a: number, b: number): boolean
				return candidateD2[a] < candidateD2[b]
			end)
		end
		for _, viewerId in fresh do
			if not tryAdd(subjectId, viewerId, candidateD2[viewerId]) then
				break
			end
		end
	end

	-- A spawned player as VIEWER: offer it to every subject within the enter radius.
	local function evaluateAsViewer(viewerId: number)
		if px[viewerId] == nil then
			return
		end
		local near: { number } = {}
		local nearD2: { [number]: number } = {}
		queryNear(viewerId, radius2, near, nearD2, viewerIndex[viewerId])
		table.sort(near, function(a: number, b: number): boolean
			return nearD2[a] < nearD2[b]
		end)
		for _, subjectId in near do
			if not isMember(subjectId, viewerId) then
				tryAdd(subjectId, viewerId, nearD2[subjectId])
			end
		end
	end

	-- Subjects of one group (userId % groupCount), plus that group's subjects that lost their
	-- character (no snapshot position) so their pairs are pruned.
	local function evaluateGroup(group: number?)
		local evaluations = 0
		for subjectId in snapPlayers do
			if group == nil or subjectId % groupCount == group then
				evaluateSubject(subjectId)
				evaluations += 1
			end
		end
		local gone: { number }? = nil
		for subjectId in members do
			if px[subjectId] == nil and (group == nil or subjectId % groupCount == group) then
				gone = gone or {}
				table.insert(gone :: { number }, subjectId)
			end
		end
		if gone then
			for _, subjectId in gone do
				dropSubject(subjectId)
			end
		end
		return evaluations
	end

	local function incrementalPass(group: number?)
		local t0 = os.clock()
		candidatesThisPass = 0
		snapshotPositions()
		lastTickEvaluations = evaluateGroup(group)
		lastTickCandidates = candidatesThisPass
		lastTickMs = (os.clock() - t0) * 1000
	end

	-- ── Public API ────────────────────────────────────────────
	function self:getSubscribers(channelPrefix: string, subject: Player): { Player }
		return interest:getSubscribers(channelPrefix .. tostring(subject.UserId))
	end

	function self:isSubscriber(subject: Player, viewer: Player): boolean
		return isMember(subject.UserId, viewer.UserId)
	end

	function self:recomputePlayer(player: Player)
		if not incremental then
			self:recomputeNow()
			return
		end
		local userId = player.UserId
		local now = clock()
		local last = lastRecomputeAt[userId]
		if last and now - last < RECOMPUTE_PLAYER_DEDUPE then
			return
		end
		lastRecomputeAt[userId] = now
		local t0 = os.clock()
		candidatesThisPass = 0
		snapshotPositions()
		evaluateSubject(userId)
		evaluateAsViewer(userId)
		lastTickEvaluations = 1
		lastTickCandidates = candidatesThisPass
		lastTickMs = (os.clock() - t0) * 1000
	end

	function self:step(dt: number)
		tickAccumulator += dt
		local interval = if incremental then tickInterval else recomputeInterval
		if tickAccumulator + 1e-9 < interval then
			return
		end
		tickAccumulator = 0
		if incremental then
			local group = tickIndex % groupCount
			tickIndex += 1
			incrementalPass(group)
		else
			recompute()
		end
	end

	function self:stats(): ProximityStats
		local subjects = 0
		for _ in members do
			subjects += 1
		end
		return {
			mode = if incremental then "incremental" else "legacy",
			subjects = subjects,
			pairs = pairTotal,
			lastTickMs = lastTickMs,
			lastTickEvaluations = lastTickEvaluations,
			lastTickCandidates = lastTickCandidates,
			adds = addTotal,
			removes = removeTotal,
		}
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

	-- One CharacterAdded connection per player, disconnected on leave. It used to go into the
	-- module-lifetime cleaner: one dead connection per visit (production hardening P1, H5).
	local characterConnections: { [number]: RBXScriptConnection } = {}

	function self:removePlayer(player: Player)
		local userId = player.UserId
		local characterConnection = characterConnections[userId]
		if characterConnection then
			characterConnection:Disconnect()
			characterConnections[userId] = nil
		end

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

		-- Remove as viewer: drop this viewer from every subject's channels (P4: O(k) via the
		-- viewer index instead of a scan over every subject).
		local subjectIds: { number } = {}
		for subjectId in viewerIndex[userId] or {} do
			table.insert(subjectIds, subjectId)
		end
		for _, subjectId in subjectIds do
			removeMember(subjectId, userId)
		end
		lastRecomputeAt[userId] = nil
		entersByViewer[userId] = nil

		-- Safety net (R1.7): clear any residual channel membership the manager
		-- still holds for this player as a subscriber.
		interest:removePlayer(player)
	end

	function self:recomputeNow()
		tickAccumulator = 0
		if incremental then
			incrementalPass(nil) -- every group at once
			return
		end
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
			-- P4 (H3): this player's row only (legacy mode: full pass).
			self:recomputePlayer(player)
		end)
	end

	local function watchPlayerCharacter(player: Player)
		local previous = characterConnections[player.UserId]
		if previous then
			previous:Disconnect()
		end
		characterConnections[player.UserId] = player.CharacterAdded:Connect(function(character)
			if character:IsA("Model") then
				schedulePartsReadyRecompute(player, character)
			end
		end)
		local existing = player.Character
		if existing and existing:IsA("Model") then
			schedulePartsReadyRecompute(player, existing)
		end
	end

	function self:onStart()
		cleaner:add(RunService.Heartbeat:Connect(function(dt)
			self:step(dt)
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
			recomputeInterval = if incremental then tickInterval else recomputeInterval,
			algorithm = if incremental then "incremental_staggered" else "spatial_grid_partitioning",
			cellSize = if incremental then gridCellSize else leaveRadius,
			groups = if incremental then groupCount else 1,
			subscriberCap = if incremental then subscriberCap else 0,
		})
	end

	function self:onDestroy()
		cleaner:clean()
		for _, connection in characterConnections do
			connection:Disconnect()
		end
		table.clear(characterConnections)
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
		table.clear(viewerIndex)
		table.clear(memberCount)
		table.clear(lastRecomputeAt)
		table.clear(entersByViewer)
		pairTotal = 0
		table.clear(addedListeners)
		table.clear(removedListeners)
	end

	return self
end

return ProximityInterestService
