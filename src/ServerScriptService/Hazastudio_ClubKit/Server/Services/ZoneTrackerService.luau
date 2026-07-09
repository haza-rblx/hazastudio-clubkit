--!strict
-- Server/Services/ZoneTrackerService.lua
--
-- Detects which Music zone each player is currently inside (zone mode only).
-- Calls musicService:enterZone / musicService:leaveZone when membership changes.
--
-- Uses periodic Region3-style bounds check on the player's HumanoidRootPart
-- against tagged BaseParts. Avoids Touched events because they fire per-frame
-- per-contact and tax the network thread at high CCU.
--
-- Layer rules:
--   - Pure spatial coordinator. No DataStore, no remote fires.
--   - Calls musicService API only. Doesn't manipulate music state directly.
--   - Owns connections + per-player state, cleans up via Cleaner.
--   - No-op when Config.Music.MODE is not "zone".
--
-- Tagged BasePart contract:
--   - CollectionService tag: Config.Music.ZONE_TAG (default "MusicZone")
--   - Optional attribute: Config.Music.ZONE_ID_ATTRIBUTE (default "ZoneId")
--     Falls back to part:GetFullName() if attribute missing.
--   - BasePart.CanCollide and Transparency don't matter; tracker only cares
--     about position + size.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Cleaner = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cleaner)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)

type ILogger = Types.ILogger

export type ZoneTrackerDeps = {
	musicService: any,
	logger: ILogger?,
}

export type ZoneTrackerService = {
	onInit: (self: ZoneTrackerService) -> (),
	onStart: (self: ZoneTrackerService) -> (),
	onDestroy: (self: ZoneTrackerService) -> (),
	getZoneCount: (self: ZoneTrackerService) -> number,
	getActiveZones: (self: ZoneTrackerService) -> { string },
}

-- Tunable defaults; overridable via Config.Music.
local DEFAULT_TICK_INTERVAL = 0.2
local MIN_TICK_INTERVAL = 0.05

local ZoneTrackerService = {}

-- Resolve zone id for a tagged BasePart. Prefer attribute, fall back to
-- full instance path so unattributed zones still work in Studio testing.
local function resolveZoneId(part: BasePart, attributeName: string): string
	local attr = part:GetAttribute(attributeName)
	if type(attr) == "string" and attr ~= "" then
		return attr
	end
	return part:GetFullName()
end

-- Cheap point-in-OBB test. Transforms world position into the part's local
-- frame and compares against half-extents.
local function pointInPart(point: Vector3, part: BasePart): boolean
	local cf = part.CFrame
	local size = part.Size
	local relative = cf:PointToObjectSpace(point)
	local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
	return math.abs(relative.X) <= hx
		and math.abs(relative.Y) <= hy
		and math.abs(relative.Z) <= hz
end

function ZoneTrackerService.create(deps: ZoneTrackerDeps): ZoneTrackerService
	assert(deps and deps.musicService, "ZoneTrackerService requires deps.musicService")
	local musicService = deps.musicService
	local log = (deps and deps.logger) or Logger.new("ZoneTrackerService")

	local cfg = Config.Music
	local zoneTag = if type(cfg.ZONE_TAG) == "string" then cfg.ZONE_TAG else "MusicZone"
	local zoneIdAttr = if type(cfg.ZONE_ID_ATTRIBUTE) == "string" then cfg.ZONE_ID_ATTRIBUTE else "ZoneId"
	local tickInterval = math.max(
		MIN_TICK_INTERVAL,
		tonumber(cfg.ZONE_TICK_INTERVAL) or DEFAULT_TICK_INTERVAL
	)

	local cleaner = Cleaner.new()
	local trackedZones: { BasePart } = {}
	local zoneIdByPart: { [BasePart]: string } = {}
	local lastZoneByPlayer: { [number]: string? } = {}
	local tickAccumulator = 0

	local self = {} :: ZoneTrackerService

	local function registerZone(part: BasePart)
		if zoneIdByPart[part] then
			return
		end
		local id = resolveZoneId(part, zoneIdAttr)
		zoneIdByPart[part] = id
		table.insert(trackedZones, part)
		log:debug("Zone registered", { zoneId = id, partName = part.Name })
	end

	local function unregisterZone(part: BasePart)
		local id = zoneIdByPart[part]
		if not id then
			return
		end
		zoneIdByPart[part] = nil
		for index, candidate in trackedZones do
			if candidate == part then
				table.remove(trackedZones, index)
				break
			end
		end
		log:debug("Zone unregistered", { zoneId = id, partName = part.Name })
	end

	-- Find which zone (if any) contains the player's current position.
	-- Linear scan — zone count expected < 50 in typical games.
	local function findZoneForPosition(position: Vector3): string?
		for _, part in trackedZones do
			if part.Parent and pointInPart(position, part) then
				return zoneIdByPart[part]
			end
		end
		return nil
	end

	local function getPlayerPosition(player: Player): Vector3?
		local character = player.Character
		if not character then return nil end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then return nil end
		return root.Position
	end

	-- Per-tick: walk online players, compute current zone, dispatch transition.
	local function onTick()
		for _, player in Players:GetPlayers() do
			local position = getPlayerPosition(player)
			if not position then
				-- Character not loaded yet. If they were previously in a zone,
				-- treat as "left" so audio stops.
				local previous = lastZoneByPlayer[player.UserId]
				if previous then
					lastZoneByPlayer[player.UserId] = nil
					musicService:leaveZone(player)
				end
				continue
			end

			local currentZone = findZoneForPosition(position)
			local previousZone = lastZoneByPlayer[player.UserId]

			if currentZone == previousZone then
				continue
			end

			if currentZone then
				lastZoneByPlayer[player.UserId] = currentZone
				musicService:enterZone(player, currentZone)
			else
				lastZoneByPlayer[player.UserId] = nil
				musicService:leaveZone(player)
			end
		end
	end

	function self:onInit(): ()
		-- Skip wiring entirely if mode is not zone. Saves Heartbeat overhead.
		if type(musicService.getMode) ~= "function" or musicService:getMode() ~= "zone" then
			log:info("ZoneTracker: music mode is not 'zone'; tracker disabled")
			return
		end

		-- Seed initial zones from already-tagged parts.
		for _, instance in CollectionService:GetTagged(zoneTag) do
			if instance:IsA("BasePart") then
				registerZone(instance)
			end
		end

		-- React to dynamic tagging (zones added/removed at runtime).
		cleaner:add(CollectionService:GetInstanceAddedSignal(zoneTag):Connect(function(instance)
			if instance:IsA("BasePart") then
				registerZone(instance)
			end
		end))
		cleaner:add(CollectionService:GetInstanceRemovedSignal(zoneTag):Connect(function(instance)
			if instance:IsA("BasePart") then
				unregisterZone(instance)
			end
		end))

		log:info("ZoneTracker initialized", {
			zoneTag = zoneTag,
			zonesFound = #trackedZones,
			tickInterval = tickInterval,
		})
	end

	function self:onStart(): ()
		if type(musicService.getMode) ~= "function" or musicService:getMode() ~= "zone" then
			return
		end

		-- Heartbeat-driven tick with fixed interval. We could use task.wait
		-- in a spawned loop, but Heartbeat lets us throttle deterministically
		-- and shares the scheduler bucket with other server logic.
		cleaner:add(RunService.Heartbeat:Connect(function(dt)
			tickAccumulator += dt
			if tickAccumulator < tickInterval then
				return
			end
			tickAccumulator = 0
			onTick()
		end))

		-- Force player out of any zone on disconnect.
		cleaner:add(Players.PlayerRemoving:Connect(function(player)
			lastZoneByPlayer[player.UserId] = nil
			-- musicService:leaveZone is idempotent; no harm if player wasn't in a zone.
			musicService:leaveZone(player)
		end))
	end

	function self:onDestroy(): ()
		cleaner:clean()
		table.clear(trackedZones)
		table.clear(zoneIdByPart)
		table.clear(lastZoneByPlayer)
	end

	function self:getZoneCount(): number
		return #trackedZones
	end

	function self:getActiveZones(): { string }
		local ids: { string } = {}
		for _, id in zoneIdByPart do
			table.insert(ids, id)
		end
		return ids
	end

	return self
end

return ZoneTrackerService
