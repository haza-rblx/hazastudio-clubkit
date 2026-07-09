--!strict
-- Server/Repositories/ProfileLoader.lua
--
-- Serialize per-player DataStore loads triggered by PlayerAdded.
--
-- Why this exists:
-- A naive `Players.PlayerAdded:Connect(function(p) repo:loadAsync(p.UserId) end)`
-- fans out N concurrent DataStore reads at every join storm (up to 100 players
-- in a 60s window at the 100 CCU target). The Roblox request queue saturates,
-- reads are dropped, and the
-- "DataStore request was added to queue" warnings flood the log.
--
-- Capacity (perf-scaling R3.7 / R3.8 / R10.1): bound concurrent join-time reads
-- to Config.ProfileLoader.MAX_CONCURRENCY = 4 (global cap), with
-- PER_PLAYER_CONCURRENCY = 1 so each player's reads run sequentially, keeping
-- aggregate join-time reads within the ~80 reads/min budget at 100 CCU.
--
-- ProfileLoader fixes this by:
--   1. Accepting per-kind loader functions registered up front.
--   2. Enqueueing one job per (player, kind) on PlayerAdded.
--   3. Draining the queue serially (or with bounded concurrency).
--   4. Firing a "loaded" event so downstream services react without polling.
--
-- Pattern:
--   local loader = ProfileLoader.create({ logger = log, concurrency = 1 })
--   loader:register("profile", function(player) return profileRepo:loadAsync(player.UserId) end)
--   loader:register("settings", function(player) return settingsRepo:loadAsync(player.UserId) end)
--
--   loader:onLoaded(function(event)
--       if event.kind == "profile" and event.result.ok then
--           profileService:hydrate(event.player, event.result.value)
--       end
--   end)
--
--   Players.PlayerAdded:Connect(function(player) loader:enqueue(player) end)
--   Players.PlayerRemoving:Connect(function(player) loader:cancel(player) end)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cleaner = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cleaner)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)

type Result<T> = Types.Result<T>
type ILogger = Types.ILogger

export type LoadFn = (player: Player) -> Result<any>

export type LoadEvent = {
	player: Player,
	kind: string,
	result: Result<any>,
	latencyMs: number,
}

export type LoadListener = (event: LoadEvent) -> ()

export type ProfileLoaderOptions = {
	logger: ILogger?,
	concurrency: number?,
	perPlayerConcurrency: number?,
	pollInterval: number?,
}

export type ProfileLoader = {
	register: (self: ProfileLoader, kind: string, loadFn: LoadFn) -> (),
	enqueue: (self: ProfileLoader, player: Player) -> (),
	enqueueKind: (self: ProfileLoader, player: Player, kind: string) -> (),
	cancel: (self: ProfileLoader, player: Player) -> (),
	onLoaded: (self: ProfileLoader, listener: LoadListener) -> (() -> ()),
	pendingCount: (self: ProfileLoader) -> number,
	destroy: (self: ProfileLoader) -> (),
}

type Job = {
	player: Player,
	userId: number,
	kind: string,
	loadFn: LoadFn,
	enqueuedAt: number,
}

local DEFAULT_CONCURRENCY = 1
local DEFAULT_POLL_INTERVAL = 0.05

local ProfileLoader = {}
ProfileLoader.__index = ProfileLoader

local function notifyListeners(self: any, event: LoadEvent)
	-- Snapshot listeners so an unsubscribe inside a listener does not corrupt
	-- iteration.
	local snapshot = table.clone(self._listeners)
	for _, listener in snapshot do
		local ok, err = pcall(listener, event)
		if not ok and self._logger then
			self._logger:warn("ProfileLoader listener errored", {
				kind = event.kind,
				userId = event.player.UserId,
				error = tostring(err),
			})
		end
	end
end

local function isTransientError(err: string): boolean
	-- Scaling 100→200 CCU Phase 3: detect transient errors that should be retried
	return err == "budget_exhausted"
		or err == "ds_throttled"
		or string.find(err, "Timeout") ~= nil
		or string.find(err, "InternalError") ~= nil
		or string.find(err, "ServiceUnavailable") ~= nil
		or string.find(err, "RequestThrottled") ~= nil
end

local function isRetryableResultError(err: string?): boolean
	if type(err) ~= "string" or err == "" then
		return false
	end
	return isTransientError(err)
end

local function processJob(self: any, job: Job)
	-- Drop jobs for players that left while queued.
	if job.player.Parent == nil then
		self._pending[job.userId] = (self._pending[job.userId] or 1) - 1
		return
	end

	-- Scaling 100→200 CCU Phase 3: retry with exponential backoff for transient errors
	local maxRetries = 3
	local backoffDelays = {0.5, 1, 2} -- seconds
	local result: Result<any>
	local latencyMs = 0
	local loadStartedAt = os.clock()

	for attempt = 1, maxRetries do
		loadStartedAt = os.clock()
		local ok, valueOrError = pcall(job.loadFn, job.player)
		latencyMs = (os.clock() - loadStartedAt) * 1000

		if not ok then
			local errMsg = tostring(valueOrError)
			-- Check if transient error and we have retries left
			if isTransientError(errMsg) and attempt < maxRetries then
				warn("[ProfileLoader] Transient error on attempt", attempt, "retrying after", backoffDelays[attempt], "s:", errMsg)
				task.wait(backoffDelays[attempt])
				-- Continue to next retry
			else
				-- Permanent error or exhausted retries
				result = Result.Err("loader_threw: " .. errMsg)
				break
			end
		elseif type(valueOrError) == "table" and valueOrError.ok ~= nil then
			result = valueOrError :: any
			if not result.ok and isRetryableResultError(result.error) and attempt < maxRetries then
				if self._logger then
					self._logger:warn("ProfileLoader retrying Result error", {
						kind = job.kind,
						userId = job.userId,
						attempt = attempt,
						error = result.error,
					})
				end
				task.wait(backoffDelays[attempt] or 1)
			else
				break
			end
		else
			result = Result.Ok(valueOrError)
			break
		end
	end

	if not result then
		result = Result.Err("loader_exhausted_retries")
	end

	if self._logger then
		self._logger:info("ProfileLoader load complete", {
			kind = job.kind,
			userId = job.userId,
			ok = result.ok,
			queueWaitMs = math.floor((loadStartedAt - job.enqueuedAt) * 1000),
			latencyMs = math.floor(latencyMs),
		})
	end

	self._pending[job.userId] = (self._pending[job.userId] or 1) - 1
	if (self._pending[job.userId] or 0) <= 0 then
		self._pending[job.userId] = nil
	end

	notifyListeners(self, {
		player = job.player,
		kind = job.kind,
		result = result,
		latencyMs = latencyMs,
	})
end

local function startWorker(self: any)
	if self._workerActive then
		return
	end
	self._workerActive = true

	task.spawn(function()
		while self._alive and #self._queue > 0 do
			-- Bounded concurrency: kick off up to `concurrency` jobs in
			-- parallel, wait for that batch, then loop.
			-- R10.1: at most one in-flight job per userId so a single player's
			-- overhead/profile/likes reads stay sequential within the global cap.
			local batch = {}
			local userIdsInBatch: { [number]: boolean } = {}
			local perPlayerLimit = math.max(1, self._perPlayerConcurrency or 1)
			local queueIndex = 1
			while #batch < self._concurrency and queueIndex <= #self._queue do
				local job = self._queue[queueIndex]
				if job and (userIdsInBatch[job.userId] or 0) < perPlayerLimit then
					table.remove(self._queue, queueIndex)
					table.insert(batch, job)
					userIdsInBatch[job.userId] = (userIdsInBatch[job.userId] or 0) + 1
				else
					queueIndex += 1
				end
			end

			if #batch == 0 then break end

			local threads = {}
			for _, job in batch do
				table.insert(threads, task.spawn(function()
					processJob(self, job)
				end))
			end

			for _, thread in threads do
				while coroutine.status(thread) ~= "dead" do
					task.wait(self._pollInterval)
				end
			end
		end

		self._workerActive = false
	end)
end

--- Construct a ProfileLoader. Register loader functions and listeners after
--- creation; call `enqueue` on PlayerAdded.
function ProfileLoader.create(options: ProfileLoaderOptions?): ProfileLoader
	local opts = options or {}
	local self = setmetatable({
		_logger = opts.logger or Logger.new("ProfileLoader"),
		_concurrency = math.max(1, opts.concurrency or DEFAULT_CONCURRENCY),
		_perPlayerConcurrency = math.max(1, opts.perPlayerConcurrency or 1),
		_pollInterval = opts.pollInterval or DEFAULT_POLL_INTERVAL,
		_loaders = {} :: { [string]: LoadFn },
		_kindOrder = {} :: { string },
		_queue = {} :: { Job },
		_listeners = {} :: { LoadListener },
		_pending = {} :: { [number]: number },
		_cleaner = Cleaner.new(),
		_alive = true,
		_workerActive = false,
	}, ProfileLoader)

	self._cleaner:add(Players.PlayerRemoving:Connect(function(player)
		(self :: any):cancel(player)
	end))

	return (self :: any) :: ProfileLoader
end

--- Register a loader for a kind. Calling twice with the same kind replaces.
function ProfileLoader:register(kind: string, loadFn: LoadFn)
	assert(type(kind) == "string" and #kind > 0, "ProfileLoader.register requires a kind string")
	assert(type(loadFn) == "function", "ProfileLoader.register requires a loadFn")
	self._loaders[kind] = loadFn
	if not table.find(self._kindOrder, kind) then
		table.insert(self._kindOrder, kind)
	end
end

--- Enqueue every registered kind for a player. Idempotent across joins because
--- already-queued (player, kind) pairs are skipped.
function ProfileLoader:enqueue(player: Player)
	for _, kind in ipairs(self._kindOrder) do
		if self._loaders[kind] then
			(self :: any):enqueueKind(player, kind)
		end
	end
end

--- Enqueue a single (player, kind). Skips if a job for that pair is already queued.
function ProfileLoader:enqueueKind(player: Player, kind: string)
	local loadFn = self._loaders[kind]
	if not loadFn then
		if self._logger then
			self._logger:warn("ProfileLoader.enqueueKind: unknown kind", { kind = kind })
		end
		return
	end

	local userId = player.UserId
	for _, job in self._queue do
		if job.userId == userId and job.kind == kind then
			return
		end
	end

	table.insert(self._queue, {
		player = player,
		userId = userId,
		kind = kind,
		loadFn = loadFn,
		enqueuedAt = os.clock(),
	})
	self._pending[userId] = (self._pending[userId] or 0) + 1
	startWorker(self)
end

--- Cancel pending jobs for a player. Called automatically on PlayerRemoving.
function ProfileLoader:cancel(player: Player)
	local userId = player.UserId
	for index = #self._queue, 1, -1 do
		if self._queue[index].userId == userId then
			table.remove(self._queue, index)
		end
	end
	self._pending[userId] = nil
end

--- Subscribe to load completion. Returns an unsubscribe function.
function ProfileLoader:onLoaded(listener: LoadListener): () -> ()
	table.insert(self._listeners, listener)
	return function()
		for index, candidate in self._listeners do
			if candidate == listener then
				table.remove(self._listeners, index)
				return
			end
		end
	end
end

--- Total pending jobs across all players.
function ProfileLoader:pendingCount(): number
	return #self._queue
end

function ProfileLoader:destroy()
	self._alive = false
	self._cleaner:clean()
	table.clear(self._queue)
	table.clear(self._loaders)
	table.clear(self._kindOrder)
	table.clear(self._listeners)
	table.clear(self._pending)
end

return ProfileLoader
