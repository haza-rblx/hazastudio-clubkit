--!strict
-- Server/Repositories/OverheadRepository.luau
-- ONLY accessible from Service layer. Zero business logic here.
-- Persistence Fabric: PlayerSessionStore write-behind when enabled.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config         = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types          = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local ResultUtil     = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Cache          = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cache)
local Logger         = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local BudgetGate     = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetGate)
local CrossServerCache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.CrossServerCache)
local PlayerSessionStore = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.PlayerSessionStore)
local BoundedLru     = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BoundedLru)
local BudgetMeter    = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetMeter)
local FlushPolicy    = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.FlushPolicy)

local OVERHEAD_INVALIDATE_TOPIC = "OverheadInvalidate"
local SESSION_NS = "overhead"

type Result<T> = Types.Result<T>
type OverheadStoredData = Types.OverheadStoredData
type IOverheadRepository = Types.IOverheadRepository

local DEFAULT_XP_ONLY_FIELDS = { "xp", "_version" }

local function xpOnlyFields(): { string }
	local w = Config.PlayerDocWriter
	if type(w) == "table" and type(w.XP_ONLY_FIELDS) == "table" then
		return w.XP_ONLY_FIELDS
	end
	return DEFAULT_XP_ONLY_FIELDS
end

local function skipXpOnlyPublish(): boolean
	local bus = Config.InvalidateBus
	return type(bus) == "table" and bus.SKIP_XP_ONLY_PUBLISH == true
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = deepCopy(v)
	end
	return out
end

local function createOverheadRepository(datastoreKey: string?): IOverheadRepository
	local key   = datastoreKey or Config.DataStore.OVERHEAD_KEY
	local log   = Logger.new("OverheadRepository")
	local Store = DataStoreService:GetDataStore(key)
	local KEY_PREFIX = "overhead:"
	local budgetGate = BudgetGate.create({ logger = log, name = "OverheadRepository" })
	local repo = {} :: IOverheadRepository

	local function mutexFor(userId: number): string
		return key .. "::" .. tostring(userId)
	end

	local function useSession(): boolean
		return PlayerSessionStore.isEnabled()
	end

	CrossServerCache.subscribe(OVERHEAD_INVALIDATE_TOPIC, function(userId)
		Cache.invalidate(KEY_PREFIX .. userId)
		-- A dirty session is kept (marked stale) instead of dropped: its unsaved changes are
		-- replayed onto the stored document at the next flush (production hardening P1).
		local outcome = PlayerSessionStore.invalidate(SESSION_NS, userId)
		log:debug("Cross-server cache invalidated", { userId = userId, session = outcome })
	end)

	local function publishInvalidation(userId: number)
		CrossServerCache.publish(OVERHEAD_INVALIDATE_TOPIC, userId)
	end

	-- Identity-visible changes not yet told to other servers (production hardening P3, A9): an
	-- XP-only write is not published — a player is only ever in one server, and other servers'
	-- copies of an offline doc expire with the cache TTL. seq counts identity changes; published is
	-- the seq the last successful write covered. Evicted/unknown users publish (safe default).
	local identityState = BoundedLru.new(2000)
	-- Every session update registers the player (XP-only: seq unchanged), so "no state" at write
	-- time really means evicted/unknown → publish.
	local function noteUpdate(userId: number, identityChanged: boolean)
		local state = identityState:get(userId)
		if not state then
			state = { seq = 0, published = 0 }
			identityState:set(userId, state)
		end
		if identityChanged then
			state.seq += 1
		end
	end
	local function identitySeq(userId: number): number?
		local state = identityState:peek(userId)
		return if state then state.seq else nil
	end
	local function shouldPublish(userId: number, seqAtStart: number?): boolean
		if not skipXpOnlyPublish() then
			return true
		end
		local state = identityState:peek(userId)
		if not state or seqAtStart == nil then
			return true
		end
		return seqAtStart ~= state.published
	end
	local function markPublished(userId: number, seqAtStart: number?)
		local state = identityState:peek(userId)
		if state and seqAtStart ~= nil and seqAtStart > state.published then
			state.published = seqAtStart
		end
	end

	-- `context` comes from PlayerSessionStore flushes. When the session is stale or the stored
	-- `_version` is newer than ours, the session's unsaved mutators are replayed onto the stored
	-- document inside the transform (no lost writes on either side). Returns Ok(replayedDoc)
	-- when it wrote a replay, Ok(nil) when it wrote `data`.
	local function durableWrite(
		userId: number,
		data: OverheadStoredData,
		context: PlayerSessionStore.FlushContext?
	): Result<OverheadStoredData?>
		local versionConflict = false
		local replayed: OverheadStoredData? = nil
		local seqAtStart = identitySeq(userId)
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return ResultUtil.withRetry(function(): boolean
				versionConflict = false
				replayed = nil
				Store:UpdateAsync(tostring(userId), function(oldData: any): any
					local base = oldData or {}
					local storedIsNewer = base._version and data._version and base._version > data._version
					local replay = if context then context.replay else nil
					if oldData ~= nil and replay and (storedIsNewer or (context :: any).stale) then
						local merged = OverheadDomain.sanitize(replay(OverheadDomain.sanitize(oldData)))
						replayed = merged
						return merged
					end
					if storedIsNewer then
						versionConflict = true
						return nil
					end
					return data
				end)
				return true
			end, Config.DataStore.RETRY_ATTEMPTS)
		end, mutexFor(userId))
		if versionConflict then
			-- No replay available (legacy save or too many unsaved steps): the stored copy wins.
			Cache.invalidate(KEY_PREFIX .. userId)
			PlayerSessionStore.clear(SESSION_NS, userId)
			return ResultUtil.Err("version_conflict")
		end
		if not result.ok then
			return ResultUtil.Err(result.error or "write_failed")
		end
		Cache.set(KEY_PREFIX .. userId, replayed or data, Config.DataStore.CACHE_TTL)
		-- A direct save (no context) or a replayed write always publishes.
		if context == nil or replayed ~= nil or shouldPublish(userId, seqAtStart) then
			publishInvalidation(userId)
		else
			BudgetMeter.recordEvent("invalidate_xp_skipped")
		end
		markPublished(userId, seqAtStart)
		return ResultUtil.Ok(replayed)
	end

	PlayerSessionStore.registerFlush(SESSION_NS, function(userId: number, data: any, context)
		return durableWrite(userId, data :: OverheadStoredData, context)
	end)

	function repo:loadStrict(userId: number): Result<OverheadStoredData>
		if useSession() then
			local sessionData = PlayerSessionStore.get(SESSION_NS, userId)
			if sessionData ~= nil then
				return ResultUtil.Ok(sessionData :: OverheadStoredData)
			end
		end

		local cacheKey = KEY_PREFIX .. userId
		if Cache.getNegative(cacheKey) then
			return ResultUtil.Err("budget_low")
		end
		local cached = Cache.get(cacheKey)
		if cached then
			local data = cached :: OverheadStoredData
			if useSession() then
				PlayerSessionStore.hydrate(SESSION_NS, userId, data)
			end
			return ResultUtil.Ok(data)
		end
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
			return ResultUtil.withRetry(function()
				return Store:GetAsync(tostring(userId))
			end, Config.DataStore.JOIN_READ_RETRY_ATTEMPTS or 1)
		end, mutexFor(userId))
		if not result.ok then
			log:error("Load failed", { userId = userId, err = result.error })
			-- Only poison on real Roblox budget pressure — never on inflight_saturated.
			if result.error == "budget_low" or result.error == "budget_exhausted" then
				Cache.setNegative(cacheKey, Config.Budget.NEGATIVE_CACHE_TTL or 10)
			end
			return ResultUtil.Err(result.error)
		end
		local raw = result.value
		local data = raw and OverheadDomain.sanitize(raw) or OverheadDomain.defaultStoredData()
		Cache.set(cacheKey, data, Config.DataStore.CACHE_TTL)
		if useSession() then
			PlayerSessionStore.hydrate(SESSION_NS, userId, data)
		end
		log:debug("Load OK", { userId = userId })
		return ResultUtil.Ok(data)
	end

	function repo:load(userId: number): Result<OverheadStoredData>
		return self:loadStrict(userId)
	end

	function repo:update(
		userId: number,
		mutator: (current: OverheadStoredData) -> OverheadStoredData
	): Result<OverheadStoredData>
		if useSession() then
			if PlayerSessionStore.get(SESSION_NS, userId) == nil then
				local loaded = self:loadStrict(userId)
				if not loaded.ok then
					return loaded
				end
			end
			local before: any = nil
			local nextData, changed = PlayerSessionStore.applyMutator(SESSION_NS, userId, function(current)
				-- Copied first: a mutator may edit `current` in place.
				before = deepCopy(current)
				return OverheadDomain.sanitize(mutator(current :: OverheadStoredData))
			end)
			if nextData == nil then
				return ResultUtil.Err("session_missing")
			end
			local finalData = nextData :: OverheadStoredData
			Cache.set(KEY_PREFIX .. userId, finalData, Config.DataStore.CACHE_TTL)
			if not changed then
				log:debug("Update no-op (session fingerprint)", { userId = userId })
				return ResultUtil.Ok(finalData)
			end
			-- XP ticks wait for the player's 90 s slot; anything else is urgent and is published to
			-- other servers after the write (Config.PlayerDocWriter, production hardening P3).
			local xpOnly = FlushPolicy.isOnlyFields(before, finalData, xpOnlyFields())
			noteUpdate(userId, not xpOnly)
			PlayerSessionStore.scheduleFlush(SESSION_NS, userId, if xpOnly then "normal" else "urgent")
			log:debug("Update deferred to session flush", { userId = userId })
			return ResultUtil.Ok(finalData)
		end

		local updatedData: OverheadStoredData? = nil
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return ResultUtil.withRetry(function()
				return Store:UpdateAsync(tostring(userId), function(oldData: any): any
					local current = oldData and OverheadDomain.sanitize(oldData) or OverheadDomain.defaultStoredData()
					local nextData = OverheadDomain.sanitize(mutator(current))
					updatedData = nextData
					return nextData
				end)
			end, Config.DataStore.RETRY_ATTEMPTS)
		end, mutexFor(userId))
		if not result.ok then
			log:error("Update failed", { userId = userId, err = result.error })
			return ResultUtil.Err(result.error)
		end
		local finalData = updatedData
		if not finalData then
			log:error("Update failed: updatedData nil", { userId = userId })
			return ResultUtil.Err("Update failed: no data produced")
		end
		Cache.set(KEY_PREFIX .. userId, finalData, Config.DataStore.CACHE_TTL)
		publishInvalidation(userId)
		log:debug("Update OK", { userId = userId })
		return ResultUtil.Ok(finalData)
	end

	function repo:save(userId: number, data: OverheadStoredData): Result<nil>
		local sanitized = OverheadDomain.sanitize(data)
		local writeResult = durableWrite(userId, sanitized, nil)
		if not writeResult.ok then
			return ResultUtil.Err(writeResult.error)
		end
		if useSession() then
			PlayerSessionStore.markClean(SESSION_NS, userId, sanitized)
		end
		return ResultUtil.Ok(nil)
	end

	function repo:flushSession(userId: number): Result<nil>
		if not useSession() then
			return ResultUtil.Ok(nil)
		end
		return PlayerSessionStore.flushNow(SESSION_NS, userId)
	end

	function repo:invalidateCache(userId: number)
		Cache.invalidate(KEY_PREFIX .. userId)
		-- Keeps a dirty session: it is the newest copy and still has to be written.
		PlayerSessionStore.dropIfClean(SESSION_NS, userId)
	end

	return repo
end

return createOverheadRepository()
