--!strict
-- PATH: ServerScriptService/Server/Services/MusicAssetProbe.luau
-- Server-side audio asset probe. Asks the engine whether a music asset is loadable,
-- using ContentProvider:PreloadAsync on a Sound parented under ServerStorage.
-- Rules (verified in Studio):
--   * String ids passed to PreloadAsync on the server hang forever, so only Sounds are used.
--   * An unparented Sound gives a false Success and poisons the engine status cache,
--     so the probe Sound is parented under ServerStorage before it is preloaded.
--   * Only Success / Failure are cached. Timeouts and exhausted retries end as "Unknown",
--     which callers must never treat as a skip. Network slowness must not skip a track.

local ContentProvider = game:GetService("ContentProvider")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

local MusicAssetProbe = {}

local log = Logger.new("MusicAssetProbe")

local PROBE_FOLDER_NAME = "__MusicAssetProbe"
local MAX_CONCURRENT = 3
local ATTEMPT_TIMEOUT = 20
local RETRY_DELAYS = { 3, 8 } -- wait before attempt 2, then before attempt 3
local MAX_ATTEMPTS = 3
local UNKNOWN_COOLDOWN = 60 -- seconds before an inconclusive id may be probed again

local cache: { [string]: string } = {}
local lastUnknownAt: { [string]: number } = {}
local inflight: { [string]: { waiters: { thread }, result: string? } } = {}
local running = 0
local slotQueue: { thread } = {}

local function isValidId(assetId: any): boolean
	return type(assetId) == "string" and string.match(assetId, "^[1-9]%d*$") ~= nil
end

-- Track parts are numbers or strings; normalise to the canonical id string.
local function normalizeId(part: any): string?
	local n = tonumber(part)
	if not n or n <= 0 then
		return nil
	end
	return tostring(math.floor(n))
end

local function trackParts(track: any): { any }?
	if type(track) ~= "table" then
		return nil
	end
	local parts = track.parts
	if type(parts) ~= "table" or #parts == 0 then
		return nil
	end
	return parts
end

local function getFolder(): Folder
	local folder = ServerStorage:FindFirstChild(PROBE_FOLDER_NAME)
	if not folder then
		local created = Instance.new("Folder")
		created.Name = PROBE_FOLDER_NAME
		created.Parent = ServerStorage
		folder = created
	end
	return folder :: Folder
end

local function acquireSlot()
	if running < MAX_CONCURRENT then
		running += 1
		return
	end
	table.insert(slotQueue, coroutine.running())
	coroutine.yield() -- releaseSlot() hands its slot to us
end

local function releaseSlot()
	if #slotQueue > 0 then
		local nextThread = table.remove(slotQueue, 1) :: thread
		task.spawn(nextThread) -- slot passes over, running count unchanged
	else
		running -= 1
	end
end

-- One PreloadAsync attempt. Returns "Success" | "Failure" | "TimedOut".
local function attemptOnce(assetId: string): string
	local folder = getFolder()
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. assetId
	sound.Volume = 0
	sound.Parent = folder

	local resolved = false
	local result = "TimedOut"
	local waiter = coroutine.running()
	local suspended = false

	local function resolve(value: string)
		if resolved then
			return
		end
		resolved = true
		result = value
		if suspended then
			task.spawn(waiter)
		end
	end

	task.delay(ATTEMPT_TIMEOUT, function()
		resolve("TimedOut")
	end)
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ sound }, function(_, status)
				if status == Enum.AssetFetchStatus.Success then
					resolve("Success")
				elseif status == Enum.AssetFetchStatus.Failure then
					resolve("Failure")
				end
			end)
		end)
		resolve("TimedOut") -- PreloadAsync returned (or errored) without a verdict
	end)

	if not resolved then
		suspended = true
		coroutine.yield()
	end
	sound:Destroy()
	return result
end

local function probeWithRetries(assetId: string): string
	for attemptNo = 1, MAX_ATTEMPTS do
		if attemptNo > 1 then
			task.wait(RETRY_DELAYS[attemptNo - 1])
		end
		acquireSlot()
		local ok, outcome = pcall(attemptOnce, assetId)
		releaseSlot()
		if ok and (outcome == "Success" or outcome == "Failure") then
			return outcome
		end
	end
	return "Unknown"
end

-- Cached verdict for an id, or nil if not yet known. Never yields.
function MusicAssetProbe.getCached(assetId: string): string?
	if not isValidId(assetId) then
		return nil
	end
	return cache[assetId]
end

-- Probes one asset id. Yields. Concurrent calls for the same id share one probe.
function MusicAssetProbe.probeAsync(assetId: string): string
	if not isValidId(assetId) then
		return "Failure"
	end
	local cached = cache[assetId]
	if cached then
		return cached
	end
	local lastUnknown = lastUnknownAt[assetId]
	if lastUnknown and tick() - lastUnknown < UNKNOWN_COOLDOWN then
		return "Unknown"
	end

	local flight = inflight[assetId]
	if flight then
		table.insert(flight.waiters, coroutine.running())
		coroutine.yield()
		return flight.result or "Unknown"
	end

	local newFlight = { waiters = {} :: { thread }, result = nil :: string? }
	inflight[assetId] = newFlight
	local outcome = probeWithRetries(assetId)
	newFlight.result = outcome
	inflight[assetId] = nil

	if outcome == "Success" or outcome == "Failure" then
		cache[assetId] = outcome
		if outcome == "Failure" then
			log:warn("Audio asset unavailable (probe Failure)", { assetId = assetId })
		end
	else
		lastUnknownAt[assetId] = tick()
		log:warn("Audio asset probe inconclusive, not cached", { assetId = assetId })
	end

	for _, waiter in ipairs(newFlight.waiters) do
		task.spawn(waiter)
	end
	return outcome
end

-- Non-yielding check for a whole track. "Failure" if any part is cached Failure,
-- "Success" if every part is cached Success, otherwise nil.
function MusicAssetProbe.getTrackStatus(track: any): string?
	local parts = trackParts(track)
	if not parts then
		return nil
	end
	local allSuccess = true
	for _, part in ipairs(parts) do
		local id = normalizeId(part)
		local st = if id then cache[id] else "Failure"
		if st == "Failure" then
			return "Failure"
		elseif st ~= "Success" then
			allSuccess = false
		end
	end
	return if allSuccess then "Success" else nil
end

-- Probes every part of a track in parallel (capped by MAX_CONCURRENT). Yields.
-- Returns "Failure" as soon as any part fails, "Success" if all succeed, else "Unknown".
function MusicAssetProbe.probeTrackAsync(track: any): string
	local parts = trackParts(track)
	if not parts then
		return "Unknown"
	end
	local ids: { string } = {}
	for _, part in ipairs(parts) do
		local id = normalizeId(part)
		if not id then
			return "Failure"
		end
		table.insert(ids, id)
	end

	local results: { [number]: string } = {}
	local pending = #ids
	local decided: string? = nil
	local woken = false
	local suspended = false
	local waiter = coroutine.running()
	for i, id in ipairs(ids) do
		task.spawn(function()
			local st = MusicAssetProbe.probeAsync(id)
			results[i] = st
			pending -= 1
			if st == "Failure" then
				decided = "Failure"
			end
			if not woken and suspended and (decided ~= nil or pending == 0) then
				woken = true
				task.spawn(waiter)
			end
		end)
	end
	if decided == nil and pending > 0 then
		suspended = true
		coroutine.yield()
	end

	if decided == "Failure" then
		return "Failure"
	end
	local allSuccess = true
	for i = 1, #ids do
		local st = results[i]
		if st == "Failure" then
			return "Failure"
		elseif st ~= "Success" then
			allSuccess = false
		end
	end
	return if allSuccess then "Success" else "Unknown"
end

-- Fire-and-forget warm-up. Safe to call with nil or malformed tracks.
function MusicAssetProbe.prefetchTrack(track: any)
	if not trackParts(track) then
		return
	end
	task.spawn(MusicAssetProbe.probeTrackAsync, track)
end

return MusicAssetProbe
