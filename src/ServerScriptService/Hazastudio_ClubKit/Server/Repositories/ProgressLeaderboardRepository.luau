--!strict
-- Server/Repositories/ProgressLeaderboardRepository.luau
-- Level, streak and couple boards (2026-09-23). OrderedDataStores fed from the values the overhead
-- already holds — Overhead_v1 stays the source of truth, these only rank:
--   * LevelLeaderboard_v1  — score = level * LEVEL_SCORE_SCALE + xp within that level;
--   * StreakLeaderboard_v1 — score = current streakDays;
--   * CoupleLeaderboard_v1 — key "<lowerId>_<higherId>", value = when the pair was first recorded
--     (read ascending: longest together first). Written once per pair, never overwritten.
-- Writes come from `observe` (called wherever the overhead payload is synced to the player list),
-- deduplicated and throttled. Reads are cached. A streak only breaks when its owner logs in again,
-- so `getTop("streak")` checks the top rows' lastLoginAt and drops (and removes) broken ones.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local StreakDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.StreakDomain)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local BudgetGate = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetGate)
local BoundedLru = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BoundedLru)
local PlayerSessionStore = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.PlayerSessionStore)

type Result<T> = Types.Result<T>
export type Kind = "level" | "streak" | "couple"

local CACHE_TTL = 60

local function createProgressLeaderboardRepository(deps: { logger: Types.ILogger? }?)
	local cfg = Config.Leaderboards
	local log = if deps and deps.logger then deps.logger else Logger.new("ProgressLeaderboardRepository")
	local stores = {
		level = DataStoreService:GetOrderedDataStore(cfg.LEVEL_ORDERED_KEY),
		streak = DataStoreService:GetOrderedDataStore(cfg.STREAK_ORDERED_KEY),
		couple = DataStoreService:GetOrderedDataStore(cfg.COUPLE_ORDERED_KEY),
	}
	-- Read-only access to the overhead documents, for the lastLoginAt of players who are offline.
	-- Deliberately not through OverheadRepository, whose loads hydrate the session store.
	local overheadStore = DataStoreService:GetDataStore(Config.DataStore.OVERHEAD_KEY)
	local budgetGate = BudgetGate.create({ logger = log, name = "ProgressLeaderboardRepository" })

	local lastWritten: { [string]: { [number]: number } } = { level = {}, streak = {} }
	local lastLevelWriteAt: { [number]: number } = {}
	local cache: { [string]: { value: { any }, exp: number } } = {}
	-- Pairs already recorded by this server, by player, so the overhead sync asks for a player's
	-- partner once rather than on every payload.
	local couplePairOf: { [number]: string } = {}

	local repo = {}

	local function write(kind: Kind, userId: number, score: number)
		lastWritten[kind][userId] = score
		task.spawn(function()
			local result = budgetGate:executeAsync(Enum.DataStoreRequestType.SetIncrementSortedAsync, function()
				return Result.withRetry(function()
					stores[kind]:SetAsync(tostring(userId), score)
				end, Config.DataStore.RETRY_ATTEMPTS)
			end, kind .. "-lb::" .. tostring(userId))
			if not result.ok then
				-- Forget the dedupe entry so the next observe retries.
				if lastWritten[kind][userId] == score then
					lastWritten[kind][userId] = nil
				end
				log:debug("Progress leaderboard write failed", { kind = kind, userId = userId, err = result.error })
			end
		end)
	end

	-- Latest level/xp/streak of a player. Level: written at once when the level changes, an
	-- xp-only change at most every PROGRESS_XP_WRITE_INTERVAL s. Streak: written when it changes.
	function repo:observe(userId: number, level: number?, xp: number?, streakDays: number?)
		if userId <= 0 then
			return
		end
		if type(level) == "number" and level >= 1 then
			local lvl = math.floor(level)
			local score = lvl * cfg.LEVEL_SCORE_SCALE + math.clamp(math.floor(tonumber(xp) or 0), 0, cfg.LEVEL_SCORE_SCALE - 1)
			local previous = lastWritten.level[userId]
			local levelChanged = previous == nil or math.floor(previous / cfg.LEVEL_SCORE_SCALE) ~= lvl
			local due = os.clock() - (lastLevelWriteAt[userId] or -math.huge) >= cfg.PROGRESS_XP_WRITE_INTERVAL
			if previous ~= score and (levelChanged or due) then
				lastLevelWriteAt[userId] = os.clock()
				write("level", userId, score)
			end
		end
		if type(streakDays) == "number" and streakDays >= 0 then
			local days = math.floor(streakDays)
			if lastWritten.streak[userId] ~= days then
				write("streak", userId, days)
			end
		end
	end

	-- A departed player's dedupe state is dropped so a rejoin writes their current values again.
	-- Called on PlayerRemoving (below; until P3 nothing called it, so these maps only grew).
	function repo:forget(userId: number)
		lastWritten.level[userId] = nil
		lastWritten.streak[userId] = nil
		lastLevelWriteAt[userId] = nil
		couplePairOf[userId] = nil
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		repo:forget(player.UserId)
	end)

	local function pairKey(a: number, b: number): string
		return if a < b then (tostring(a) .. "_" .. tostring(b)) else (tostring(b) .. "_" .. tostring(a))
	end

	-- True when this server has not yet recorded the couple this player is in.
	function repo:needsCouple(userId: number): boolean
		return couplePairOf[userId] == nil
	end

	-- Records the pair if it is not in the store yet; an existing entry keeps its earlier time.
	function repo:observeCouple(userId: number, partnerId: number?)
		if userId <= 0 or type(partnerId) ~= "number" or partnerId <= 0 or partnerId == userId then
			return
		end
		local key = pairKey(userId, partnerId)
		if couplePairOf[userId] == key then
			return
		end
		couplePairOf[userId] = key
		couplePairOf[partnerId] = key
		task.spawn(function()
			local now = os.time()
			local result = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
				return Result.withRetry(function()
					stores.couple:UpdateAsync(key, function(old: any): any
						if type(old) == "number" and old > 0 then
							return nil -- keep the earlier time
						end
						return now
					end)
				end, Config.DataStore.RETRY_ATTEMPTS)
			end, "couple-lb::" .. key)
			if not result.ok then
				if couplePairOf[userId] == key then
					couplePairOf[userId] = nil
				end
				log:debug("Couple leaderboard write failed", { pair = key, err = result.error })
			end
		end)
	end

	function repo:removeCouple(userId: number, partnerId: number?)
		if type(partnerId) ~= "number" or partnerId <= 0 then
			return
		end
		local key = pairKey(userId, partnerId)
		if couplePairOf[userId] == key then
			couplePairOf[userId] = nil
		end
		if couplePairOf[partnerId] == key then
			couplePairOf[partnerId] = nil
		end
		for cacheKey in pairs(cache) do
			if string.sub(cacheKey, 1, 7) == "couple:" then
				cache[cacheKey] = nil
			end
		end
		task.spawn(function()
			budgetGate:executeAsync(Enum.DataStoreRequestType.SetIncrementSortedAsync, function()
				return Result.withRetry(function()
					stores.couple:RemoveAsync(key)
				end, Config.DataStore.RETRY_ATTEMPTS)
			end, "couple-lb::" .. key)
		end)
	end

	local function readSorted(kind: Kind, limit: number): Result<{ any }>
		-- Couples rank by the earliest time, the others by the highest score.
		local ascending = kind == "couple"
		local sorted = budgetGate:executeAsync(Enum.DataStoreRequestType.GetSortedAsync, function()
			return Result.withRetry(function()
				return stores[kind]:GetSortedAsync(ascending, limit)
			end, Config.DataStore.LB_READ_RETRY_ATTEMPTS or 1)
		end)
		if not sorted.ok then
			return Result.Err(sorted.error)
		end
		local entries = {}
		for _, item in ipairs(sorted.value:GetCurrentPage()) do
			if kind == "couple" then
				local a, b = string.match(tostring(item.key), "^(%d+)_(%d+)$")
				local userId, partnerId = tonumber(a) or 0, tonumber(b) or 0
				if userId > 0 and partnerId > 0 then
					table.insert(entries, { rank = #entries + 1, userId = userId, partnerId = partnerId, total = tonumber(item.value) or 0 })
				end
			else
				local userId = tonumber(item.key) or 0
				if userId > 0 then
					table.insert(entries, { rank = #entries + 1, userId = userId, total = tonumber(item.value) or 0 })
				end
			end
		end
		return Result.Ok(entries)
	end

	-- Verify reads (production hardening P3, A4, Config.VerifyCache): a player online here is read
	-- from the session store (the freshest copy, no request); offline documents are cached in an
	-- LRU (256 × 600 s) — the boards refresh every 120 s, so the old 60 s cache always missed.
	local verifyCfg = Config.VerifyCache
	local verifyEnabled = type(verifyCfg) == "table" and verifyCfg.ENABLED == true
	local offlineDocs = BoundedLru.new(if verifyEnabled then (tonumber(verifyCfg.OVERHEAD_LRU) or 256) else 1)
	local offlineTtl = if verifyEnabled then (tonumber(verifyCfg.OVERHEAD_TTL_SEC) or 600) else 0

	local function readOverhead(userId: number): any?
		if verifyEnabled then
			local live = PlayerSessionStore.get("overhead", userId)
			if type(live) == "table" then
				return live
			end
			local cached = offlineDocs:get(userId)
			if cached and os.clock() < cached.exp then
				return cached.doc
			end
		end
		local doc = budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
			return Result.withRetry(function()
				return overheadStore:GetAsync(tostring(userId))
			end, 1)
		end)
		local value = if doc.ok and type(doc.value) == "table" then doc.value else nil
		if verifyEnabled and doc.ok then
			offlineDocs:set(userId, { doc = value, exp = os.clock() + offlineTtl })
		end
		return value
	end

	-- A pair stays only while both documents still name each other; one that broke up (an online
	-- breakup removes itself, this catches offline and older ones) is dropped and removed.
	local function dropEndedCouples(entries: { any }): { any }
		local kept = {}
		for index, entry in ipairs(entries) do
			local keep = true
			if index <= cfg.COUPLE_VERIFY_TOP then
				local a, b = readOverhead(entry.userId), readOverhead(entry.partnerId)
				if a and b and (a.couplePartnerId ~= entry.partnerId or b.couplePartnerId ~= entry.userId) then
					keep = false
					repo:removeCouple(entry.userId, entry.partnerId)
				end
			end
			if keep then
				table.insert(kept, entry)
			end
		end
		for rank, entry in ipairs(kept) do
			entry.rank = rank
		end
		return kept
	end

	-- Rows whose owner has not logged in for long enough that their streak is already broken
	-- (the same rule StreakDomain applies at their next login) are dropped here and removed from
	-- the ordered store. Online players are current by definition and skip the read.
	local function dropBrokenStreaks(entries: { any }): { any }
		local now = os.time()
		local checked = 0
		local kept = {}
		for _, entry in ipairs(entries) do
			local keep = true
			if checked < cfg.STREAK_VERIFY_TOP and not Players:GetPlayerByUserId(entry.userId) then
				checked += 1
				local stored = readOverhead(entry.userId)
				if stored then
					local days = tonumber(stored.streakDays) or 0
					local last = tonumber(stored.lastLoginAt) or 0
					if days <= 0 or StreakDomain.evaluateStreak(days, last, now).didReset then
						keep = false
						local userId = entry.userId
						task.spawn(function()
							budgetGate:executeAsync(Enum.DataStoreRequestType.SetIncrementSortedAsync, function()
								return Result.withRetry(function()
									stores.streak:RemoveAsync(tostring(userId))
								end, 1)
							end, "streak-lb::" .. tostring(userId))
						end)
					end
				end
			end
			if keep then
				table.insert(kept, entry)
			end
		end
		for rank, entry in ipairs(kept) do
			entry.rank = rank
		end
		return kept
	end

	function repo:getTop(kind: Kind, limit: number): Result<{ any }>
		local resolvedLimit = math.clamp(math.floor(limit), 1, cfg.MAX_LIMIT)
		local cacheKey = kind .. ":" .. resolvedLimit
		local cached = cache[cacheKey]
		if cached and os.clock() <= cached.exp then
			return Result.Ok(cached.value)
		end
		local read = readSorted(kind, resolvedLimit)
		if not read.ok then
			return read
		end
		local entries = read.value
		if kind == "streak" then
			entries = dropBrokenStreaks(entries)
		elseif kind == "couple" then
			entries = dropEndedCouples(entries)
		end
		cache[cacheKey] = { value = entries, exp = os.clock() + CACHE_TTL }
		return Result.Ok(entries)
	end

	-- Memory-gate surface (plan H5): per-user table counts. The gate harness diffs these
	-- around join/leave cycles; `forget` is the documented leave path.
	function repo:gateCounts(): { [string]: number }
		local function count(t): number
			local n = 0
			for _ in pairs(t) do
				n += 1
			end
			return n
		end
		return {
			lastWrittenLevel = count(lastWritten.level),
			lastWrittenStreak = count(lastWritten.streak),
			lastLevelWriteAt = count(lastLevelWriteAt),
			couplePairOf = count(couplePairOf),
			cache = count(cache),
		}
	end

	return repo
end

return {
	new = createProgressLeaderboardRepository,
}
