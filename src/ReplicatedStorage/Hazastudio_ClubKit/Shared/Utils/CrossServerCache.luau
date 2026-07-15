--!strict
-- Shared/Utils/CrossServerCache.luau
-- InvalidateBus (Persistence Fabric Phase 3): coalesced MessagingService invalidation.
--
-- Public API unchanged for repos:
--   CrossServerCache.publish(topic, userId)
--   CrossServerCache.subscribe(topic, onMessage: (userId) -> ())
--
-- Fabric behavior (default):
--   - Coalesce many userIds into one publish per topic / window
--   - Payload: { originJobId, userIds, t } (also accepts legacy { userId, t })
--   - Skip callbacks when originJobId == this server (publisher already Cache.set)
--   - Local token bucket soft-caps publish rate
--
-- Kill switch: Config.Persistence.USE_LEGACY_CROSS_SERVER_CACHE = true

local MessagingService = game:GetService("MessagingService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local CrossServerCache = {}

local LEGACY_DEBOUNCE_WINDOW = 1.0
local lastPublishedAt: { [string]: number } = {}

local pendingByTopic: { [string]: { [number]: boolean } } = {}
local flushScheduled: { [string]: boolean } = {}

local tokens = 0
local lastTokenRefill = os.clock()
local metrics = {
	published = 0,
	coalesced = 0,
	throttled = 0,
	skippedOrigin = 0,
	subscribeFanout = 0,
}

local function isPublishAvailable(): boolean
	return RunService:IsServer()
end

local function persistenceConfig()
	local p = Config.Persistence
	if type(p) ~= "table" then
		return {
			USE_LEGACY_CROSS_SERVER_CACHE = false,
			INVALIDATE_COALESCE_SEC = 0.75,
			INVALIDATE_TOKEN_BUCKET_RATE = 8,
			INVALIDATE_TOKEN_BUCKET_BURST = 12,
			INVALIDATE_SKIP_ORIGIN = true,
		}
	end
	return p
end

local function useLegacy(): boolean
	return persistenceConfig().USE_LEGACY_CROSS_SERVER_CACHE == true
end

local function refillTokens()
	local cfg = persistenceConfig()
	local rate = cfg.INVALIDATE_TOKEN_BUCKET_RATE or 8
	local burst = cfg.INVALIDATE_TOKEN_BUCKET_BURST or 12
	local now = os.clock()
	local elapsed = now - lastTokenRefill
	lastTokenRefill = now
	tokens = math.min(burst, tokens + elapsed * rate)
end

local function tryConsumeToken(): boolean
	refillTokens()
	if tokens >= 1 then
		tokens -= 1
		return true
	end
	return false
end

--- Soft universe lease via MemoryStore (best-effort). Failure = allow publish.
local function tryUniverseLease(topic: string): boolean
	local ok, allowed = pcall(function()
		local map = MemoryStoreService:GetSortedMap("ClubKit_InvalidateBus_v1")
		local key = topic .. ":" .. tostring(math.floor(os.time()))
		local current = map:GetAsync(key)
		local count = if type(current) == "number" then current else 0
		local cfg = persistenceConfig()
		local maxPerSec = (cfg.INVALIDATE_TOKEN_BUCKET_RATE or 8) * 2 -- soft multi-server share
		if count >= maxPerSec then
			return false
		end
		map:SetAsync(key, count + 1, 2)
		return true
	end)
	if not ok then
		return true
	end
	return allowed == true
end

local function publishRaw(topic: string, payload: { [string]: any })
	if not tryConsumeToken() then
		metrics.throttled += 1
		-- Re-queue userIds for a later coalesce flush
		local userIds = payload.userIds
		if type(userIds) == "table" then
			local pending = pendingByTopic[topic]
			if not pending then
				pending = {}
				pendingByTopic[topic] = pending
			end
			for _, id in ipairs(userIds) do
				local n = tonumber(id)
				if n then
					pending[n] = true
				end
			end
			CrossServerCache._scheduleFlush(topic)
		end
		return
	end
	if not tryUniverseLease(topic) then
		metrics.throttled += 1
		local userIds = payload.userIds
		if type(userIds) == "table" then
			local pending = pendingByTopic[topic]
			if not pending then
				pending = {}
				pendingByTopic[topic] = pending
			end
			for _, id in ipairs(userIds) do
				local n = tonumber(id)
				if n then
					pending[n] = true
				end
			end
			CrossServerCache._scheduleFlush(topic)
		end
		return
	end

	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:PublishAsync(topic, payload)
		end)
		if ok then
			metrics.published += 1
		else
			metrics.throttled += 1
			warn(string.format(
				"[CrossServerCache] publish gagal topic=%s err=%s",
				topic,
				tostring(err)
			))
		end
	end)
end

function CrossServerCache._scheduleFlush(topic: string)
	if flushScheduled[topic] then
		return
	end
	flushScheduled[topic] = true
	local coalesce = persistenceConfig().INVALIDATE_COALESCE_SEC or 0.75
	task.delay(coalesce, function()
		flushScheduled[topic] = nil
		local pending = pendingByTopic[topic]
		pendingByTopic[topic] = nil
		if not pending then
			return
		end
		local userIds = {}
		for userId in pairs(pending) do
			table.insert(userIds, userId)
		end
		if #userIds == 0 then
			return
		end
		metrics.coalesced += #userIds
		publishRaw(topic, {
			originJobId = game.JobId,
			userIds = userIds,
			-- Legacy single-id for mixed-fleet: first id
			userId = userIds[1],
			t = os.time(),
		})
	end)
end

function CrossServerCache.getMetrics()
	return {
		published = metrics.published,
		coalesced = metrics.coalesced,
		throttled = metrics.throttled,
		skippedOrigin = metrics.skippedOrigin,
		subscribeFanout = metrics.subscribeFanout,
		tokens = tokens,
	}
end

function CrossServerCache.resetMetrics()
	metrics.published = 0
	metrics.coalesced = 0
	metrics.throttled = 0
	metrics.skippedOrigin = 0
	metrics.subscribeFanout = 0
end

--- Publish invalidation (coalesced unless legacy kill-switch).
function CrossServerCache.publish(topic: string, userId: number)
	if not isPublishAvailable() then
		return
	end

	if useLegacy() then
		local key = topic .. ":" .. tostring(userId)
		local now = os.clock()
		local lastAt = lastPublishedAt[key]
		if lastAt and (now - lastAt) < LEGACY_DEBOUNCE_WINDOW then
			return
		end
		lastPublishedAt[key] = now
		if math.random() < 0.05 then
			local cutoff = now - 60
			for k, v in pairs(lastPublishedAt) do
				if v < cutoff then
					lastPublishedAt[k] = nil
				end
			end
		end
		task.spawn(function()
			local ok, err = pcall(function()
				MessagingService:PublishAsync(topic, { userId = userId, t = os.time() })
			end)
			if not ok then
				warn(string.format(
					"[CrossServerCache] publish gagal topic=%s userId=%d err=%s",
					topic,
					userId,
					tostring(err)
				))
			end
		end)
		return
	end

	local pending = pendingByTopic[topic]
	if not pending then
		pending = {}
		pendingByTopic[topic] = pending
	end
	pending[userId] = true
	CrossServerCache._scheduleFlush(topic)
end

--- Subscribe. Callback receives each userId (batch fan-out). Skips origin server.
function CrossServerCache.subscribe(topic: string, onMessage: (userId: number) -> ()): RBXScriptConnection?
	if not isPublishAvailable() then
		return nil
	end
	local ok, conn = pcall(function()
		return MessagingService:SubscribeAsync(topic, function(message: any)
			if type(message) ~= "table" or type(message.Data) ~= "table" then
				return
			end
			local data = message.Data
			local cfg = persistenceConfig()
			local skipOrigin = cfg.INVALIDATE_SKIP_ORIGIN ~= false
			if skipOrigin and type(data.originJobId) == "string" and data.originJobId == game.JobId then
				metrics.skippedOrigin += 1
				return
			end

			local ids: { number } = {}
			if type(data.userIds) == "table" then
				for _, id in ipairs(data.userIds) do
					local n = tonumber(id)
					if n then
						table.insert(ids, n)
					end
				end
			else
				local userId = tonumber(data.userId)
				if userId then
					table.insert(ids, userId)
				end
			end
			if #ids == 0 then
				return
			end

			task.delay(2, function()
				for _, userId in ipairs(ids) do
					metrics.subscribeFanout += 1
					local successCb, errCb = pcall(onMessage, userId)
					if not successCb then
						warn(string.format(
							"[CrossServerCache] subscriber callback error topic=%s userId=%d err=%s",
							topic,
							userId,
							tostring(errCb)
						))
					end
				end
			end)
		end)
	end)
	if not ok then
		warn(string.format("[CrossServerCache] subscribe gagal topic=%s err=%s", topic, tostring(conn)))
		return nil
	end
	return conn
end

-- Seed token bucket at burst capacity.
tokens = (persistenceConfig().INVALIDATE_TOKEN_BUCKET_BURST or 12)

return CrossServerCache
