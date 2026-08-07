--!strict
-- Client/Utils/AvatarPrewarmPool.lua
--
-- Pre-loads 3D avatar models for nearby players + local player before viewport open.
-- When AvatarViewport3D needs a model, it checks the pool first — if hit,
-- the model is available instantly (no 2-8s CreateHumanoidModelFromUserId wait).
--
-- Architecture (Guidelines v3 aligned):
--   - Utility layer (Client/Utils). No business logic, no remotes.
--   - Bounded pool (MAX_POOL_SIZE). LRU eviction when full.
--   - Proximity check throttled (TICK_INTERVAL). No per-frame work.
--   - Cleanup on PlayerRemoving + destroy().
--   - Cleaner-managed connections.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cleaner = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cleaner)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

local log = Logger.new("AvatarPrewarmPool")

export type PoolEntry = {
	userId: number,
	model: Model,
	lastAccessedAt: number,
	loadedAt: number,
}

export type AvatarPrewarmPool = {
	get: (self: AvatarPrewarmPool, userId: number) -> Model?,
	take: (self: AvatarPrewarmPool, userId: number) -> Model?,
	isLoading: (self: AvatarPrewarmPool, userId: number) -> boolean,
	prewarmOnDemand: (self: AvatarPrewarmPool, userId: number) -> boolean,
	getPoolSize: (self: AvatarPrewarmPool) -> number,
	setActive: (self: AvatarPrewarmPool, active: boolean) -> (),
	destroy: (self: AvatarPrewarmPool) -> (),
	-- Event: fires once when model for userId finishes loading into pool.
	-- Used by UI to upgrade thumbnail → 3D seamlessly on pool miss
	-- on first click and prewarm finishes in background.
	subscribeModelReady: (self: AvatarPrewarmPool, userId: number, callback: () -> ()) -> (() -> ()),
}

export type PoolConfig = {
	maxPoolSize: number?,
	proximityRadius: number?,
	tickInterval: number?,
	loadCooldown: number?,
	prewarmSelf: boolean?,
}

local DEFAULT_MAX_POOL_SIZE = 15
local DEFAULT_PROXIMITY_RADIUS = 30
local DEFAULT_TICK_INTERVAL = 1.0
-- loadCooldown applies only to tick-based prewarm (proximity scan).
-- Event-driven prewarm (PlayerAdded/CharacterAdded/on-demand from controller)
-- always parallel because triggered by specific events, not loop.
local DEFAULT_LOAD_COOLDOWN = 0.1

local AvatarPrewarmPool = {}

function AvatarPrewarmPool.create(config: PoolConfig?): AvatarPrewarmPool
	local cfg = config or {}
	local maxPoolSize = math.max(1, cfg.maxPoolSize or DEFAULT_MAX_POOL_SIZE)
	local proximityRadius = math.max(5, cfg.proximityRadius or DEFAULT_PROXIMITY_RADIUS)
	local tickInterval = math.max(0.2, cfg.tickInterval or DEFAULT_TICK_INTERVAL)
	local loadCooldown = math.max(0.5, cfg.loadCooldown or DEFAULT_LOAD_COOLDOWN)
	local prewarmSelf = cfg.prewarmSelf ~= false

	local cleaner = Cleaner.new()
	local pool: { [number]: PoolEntry } = {}
	local loading: { [number]: boolean } = {}
	local loadGeneration: { [number]: number } = {}
	local pinnedUserIds: { [number]: boolean } = {}
	local poolSize = 0
	local lastLoadAt = 0
	local alive = true
	local scanActive = false
	local tickAccum = 0
	-- Per-userId list of callbacks. Fired once when model is ready.
	-- After fire, callback removed to avoid memory leak for player
	-- clicked frequently.
	local modelReadyListeners: { [number]: { () -> () } } = {}

	local function bumpLoadGeneration(userId: number): number
		local nextGen = (loadGeneration[userId] or 0) + 1
		loadGeneration[userId] = nextGen
		return nextGen
	end

	local function notifyModelReady(userId: number)
		local list = modelReadyListeners[userId]
		if not list then return end
		modelReadyListeners[userId] = nil
		for _, cb in ipairs(list) do
			task.defer(cb)
		end
	end

	local localPlayer = Players.LocalPlayer
	if prewarmSelf and localPlayer then
		pinnedUserIds[localPlayer.UserId] = true
	end

	local self = {} :: AvatarPrewarmPool

	-- ── Helpers ───────────────────────────────────────────────

	local function getLocalPosition(): Vector3?
		local character = localPlayer and localPlayer.Character
		if not character then return nil end
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return root.Position
		end
		return nil
	end

	local function getNearbyPlayers(position: Vector3): { Player }
		local nearby: { Player } = {}
		for _, player in Players:GetPlayers() do
			if player == localPlayer then continue end
			local character = player.Character
			if not character then continue end
			local root = character:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") then continue end
			if (root.Position - position).Magnitude <= proximityRadius then
				table.insert(nearby, player)
			end
		end
		-- Sort by distance (nearest first)
		table.sort(nearby, function(a, b)
			local aRoot = a.Character and a.Character:FindFirstChild("HumanoidRootPart")
			local bRoot = b.Character and b.Character:FindFirstChild("HumanoidRootPart")
			if not aRoot or not bRoot then return false end
			return (aRoot.Position - position).Magnitude < (bRoot.Position - position).Magnitude
		end)
		return nearby
	end

	local function evictLRU()
		local oldestUserId: number? = nil
		local oldestTime = math.huge
		for userId, entry in pool do
			if not pinnedUserIds[userId] and entry.lastAccessedAt < oldestTime then
				oldestTime = entry.lastAccessedAt
				oldestUserId = userId
			end
		end
		if oldestUserId then
			local entry = pool[oldestUserId]
			if entry and entry.model then
				entry.model:Destroy()
			end
			pool[oldestUserId] = nil
			poolSize -= 1
		end
	end

	-- ── Concurrency Limiter ───────────────────────────────────
	-- Limit concurrent CreateHumanoidModelFromUserId calls
	-- so we do not flood the CPU with many simultaneous API calls.
	local MAX_CONCURRENT_LOADS = 2
	local activeLoads = 0
	local loadQueue: { () -> () } = {}

	local function drainQueue()
		while activeLoads < MAX_CONCURRENT_LOADS and #loadQueue > 0 do
			local nextFn = table.remove(loadQueue, 1)
			if nextFn then
				nextFn()
			end
		end
	end

	local function loadModel(userId: number, force: boolean?)
		if not force and (pool[userId] or loading[userId]) then
			return
		end
		local gen = bumpLoadGeneration(userId)
		loading[userId] = true

		local function executeLoad()
			activeLoads += 1
			task.spawn(function()
				local success, model = pcall(function()
					return Players:CreateHumanoidModelFromUserId(userId)
				end)

				activeLoads -= 1
				if loadGeneration[userId] == gen then
					loading[userId] = nil
				end

				-- Drain next queue item after slot frees
				drainQueue()

				if not alive then
					if success and model then
						model:Destroy()
					end
					return
				end
				-- Stale completion (respawn / force reload / destroy) — drop orphan.
				if loadGeneration[userId] ~= gen then
					if success and model then
						model:Destroy()
					end
					return
				end
				if not success or not model then
					return
				end
				-- Player may already leave when loading
				if not Players:GetPlayerByUserId(userId) then
					model:Destroy()
					return
				end
				-- Destroy displaced model before overwrite (fixes poolSize double-count).
				local existing = pool[userId]
				if existing then
					if existing.model then
						existing.model:Destroy()
					end
					pool[userId] = nil
					poolSize -= 1
				end
				-- Evict if pool full
				if poolSize >= maxPoolSize then
					evictLRU()
				end
				-- Normalize at origin before anchoring (matches AvatarViewport3D.load prep).
				local hrp = model:FindFirstChild("HumanoidRootPart")
				if hrp and hrp:IsA("BasePart") then
					model.PrimaryPart = hrp
					model:MoveTo(Vector3.new(0, 0, 0))
				end
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						part.Anchored = true
						part.CanCollide = false
					end
				end
				pool[userId] = {
					userId = userId,
					model = model,
					lastAccessedAt = os.clock(),
					loadedAt = os.clock(),
				}
				poolSize += 1
				log:debug("Model pre-warmed", { userId = userId, poolSize = poolSize })
				notifyModelReady(userId)
			end)
		end

		-- If slot available, run directly. Otherwise enqueue FIFO.
		if activeLoads < MAX_CONCURRENT_LOADS then
			executeLoad()
		else
			table.insert(loadQueue, executeLoad)
		end
	end

	local function tryPrewarmUserId(userId: number, now: number): boolean
		if pool[userId] or loading[userId] then
			return false
		end
		if poolSize >= maxPoolSize and not pool[userId] then
			return false
		end
		lastLoadAt = now
		loadModel(userId)
		return true
	end

	local function onTick()
		if not scanActive then
			return
		end
		local now = os.clock()
		if (now - lastLoadAt) < loadCooldown then
			return
		end

		if localPlayer and pinnedUserIds[localPlayer.UserId] then
			if tryPrewarmUserId(localPlayer.UserId, now) then
				return
			end
		end

		local position = getLocalPosition()
		if not position then
			return
		end

		local nearby = getNearbyPlayers(position)
		for _, player in nearby do
			if poolSize >= maxPoolSize and not pool[player.UserId] then
				-- Pool full and this player isn't cached — check if they're
				-- closer than the LRU entry (worth evicting for).
				break
			end
			if tryPrewarmUserId(player.UserId, now) then
				break -- One load per tick to avoid burst
			end
		end
	end

	-- ── Public API ────────────────────────────────────────────

	--- Get a pre-warmed model WITHOUT removing it from pool.
	--- Returns nil if not cached. Caller should clone if needed.
	function self:get(userId: number): Model?
		local entry = pool[userId]
		if entry then
			entry.lastAccessedAt = os.clock()
			return entry.model
		end
		return nil
	end

	--- Take a pre-warmed model and REMOVE it from pool (transfer ownership).
	--- Caller is responsible for destroying it. Returns nil if not cached.
	function self:take(userId: number): Model?
		local entry = pool[userId]
		if entry then
			pool[userId] = nil
			poolSize -= 1
			if pinnedUserIds[userId] then
				task.defer(function()
					if alive then
						loadModel(userId)
					end
				end)
			end
			return entry.model
		end
		return nil
	end

	--- Check if a model is currently being loaded for this userId.
	function self:isLoading(userId: number): boolean
		return loading[userId] == true
	end

	--- Trigger prewarm on demand (e.g. when user clicks avatar).
	--- Idempotent: if already in pool / loading, return false without re-trigger.
	--- Return true means new prewarm started (for logging).
	function self:prewarmOnDemand(userId: number): boolean
		if not alive then return false end
		if pool[userId] or loading[userId] then return false end
		if poolSize >= maxPoolSize and not pool[userId] then
			evictLRU()
		end
		loadModel(userId)
		return true
	end

	--- Subscribe callback fired ONCE when model for userId
	--- finishes loading into pool. UI uses this for thumbnail → 3D upgrade
	--- on first click for not-yet-prewarmed user.
	--- Return an unsubscribe function.
	function self:subscribeModelReady(userId: number, callback: () -> ()): () -> ()
		if not alive then return function() end end
		-- If already ready, fire directly (defer to caller thread).
		if pool[userId] then
			task.defer(callback)
			return function() end
		end
		if not modelReadyListeners[userId] then
			modelReadyListeners[userId] = {}
		end
		table.insert(modelReadyListeners[userId], callback)
		return function()
			local list = modelReadyListeners[userId]
			if not list then return end
			local idx = table.find(list, callback)
			if idx then
				table.remove(list, idx)
			end
			if #list == 0 then
				modelReadyListeners[userId] = nil
			end
		end
	end

	function self:getPoolSize(): number
		return poolSize
	end

	function self:setActive(active: boolean)
		scanActive = active == true
	end

	-- ── Lifecycle ─────────────────────────────────────────────

	-- Track CharacterAdded connections per player for disconnect
	-- when the player leaves (prevents memory leak).
	local characterAddedConns: { [number]: RBXScriptConnection } = {}

	-- Debounce delay for re-warm on respawn (seconds).
	-- Prevent instant destroy+reload flooding CPU.
	local REWARM_DEBOUNCE = 1.5

	function self:destroy()
		alive = false
		cleaner:clean()
		-- Disconnect all CharacterAdded connections
		for userId, conn in characterAddedConns do
			conn:Disconnect()
			characterAddedConns[userId] = nil
		end
		for userId, entry in pool do
			if entry.model then
				entry.model:Destroy()
			end
			pool[userId] = nil
		end
		poolSize = 0
		table.clear(loading)
		table.clear(loadGeneration)
		-- Clear load queue that never started.
		table.clear(loadQueue)
		-- Clear listeners that never fired (panel closed while loading).
		table.clear(modelReadyListeners)
	end

	cleaner:add(RunService.Heartbeat:Connect(function(dt)
		tickAccum += dt
		if tickAccum < tickInterval then return end
		tickAccum = 0
		onTick()
	end))

	cleaner:add(Players.PlayerRemoving:Connect(function(player)
		-- Disconnect CharacterAdded connection for player ini
		local conn = characterAddedConns[player.UserId]
		if conn then
			conn:Disconnect()
			characterAddedConns[player.UserId] = nil
		end

		local entry = pool[player.UserId]
		if entry then
			if entry.model then
				entry.model:Destroy()
			end
			pool[player.UserId] = nil
			poolSize -= 1
		end
		loading[player.UserId] = nil
		loadGeneration[player.UserId] = nil
	end))

	if prewarmSelf and localPlayer then
		task.defer(function()
			if alive then
				loadModel(localPlayer.UserId)
			end
		end)
	end

	-- Helper: setup CharacterAdded listener for satu player.
	-- Debounce re-warm so not directly destroy+reload when respawn.
	local function setupCharacterAddedListener(player: Player)
		if player == localPlayer then return end
		if characterAddedConns[player.UserId] then return end

		local conn = player.CharacterAdded:Connect(function()
			if not alive then return end
			-- Debounce: brief wait before re-warm to avoid burst
			task.delay(REWARM_DEBOUNCE, function()
				if not alive then return end
				-- Check player still valid after delay
				if not Players:GetPlayerByUserId(player.UserId) then return end

				-- Invalidate old model + bump generation so in-flight loads are stale.
				bumpLoadGeneration(player.UserId)
				local entry = pool[player.UserId]
				if entry and entry.model then
					entry.model:Destroy()
					pool[player.UserId] = nil
					poolSize -= 1
				end
				loading[player.UserId] = nil
				loadModel(player.UserId, true)
			end)
		end)
		characterAddedConns[player.UserId] = conn
	end

	-- Event-driven prewarm: each joining player immediately starts
	-- background prewarm + CharacterAdded listener setup.
	-- When user clicks, model likely already ready.
	cleaner:add(Players.PlayerAdded:Connect(function(player)
		if player == localPlayer then return end
		if not alive then return end
		-- Setup listener for re-warm on respawn (tracked, disconnected on leave)
		setupCharacterAddedListener(player)
		task.defer(function()
			if alive then
				loadModel(player.UserId)
			end
		end)
	end))

	-- Setup CharacterAdded for players already on server when pool is created
	for _, player in Players:GetPlayers() do
		setupCharacterAddedListener(player)
	end

	log:info("AvatarPrewarmPool initialized", {
		maxPoolSize = maxPoolSize,
		proximityRadius = proximityRadius,
		tickInterval = tickInterval,
		prewarmSelf = prewarmSelf,
	})

	return self
end

return AvatarPrewarmPool
