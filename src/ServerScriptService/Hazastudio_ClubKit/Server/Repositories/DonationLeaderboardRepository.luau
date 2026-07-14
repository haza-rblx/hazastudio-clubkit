--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local BudgetGate = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetGate)
local DataStoreThrottleLockout = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DataStoreThrottleLockout)
local LeaderboardIdentity = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.LeaderboardIdentity)
local HttpApiCounter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApiCounter)
local HttpApi = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApi)
local MemoryStoreCache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.MemoryStoreCache)
local CrossServerCache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.CrossServerCache)

local LEADERBOARD_INVALIDATE_TOPIC = "DonationLeaderboardInvalidate"

-- P0: Detect throttle/queue errors di pcall catch dan propagate ke global lockout
-- supaya repository-wide operations short-circuit selama cooldown. Roblox
-- error wording untuk DS throttle bervariasi antar versi; pattern "throttled",
-- "queue", dan "Throttled" cukup longgar untuk menangkap semua varian umum.
local THROTTLE_ERROR_PATTERNS = { "throttled", "queue", "Throttled" }
local function maybeMarkThrottledFromError(err: any)
	if err == nil then
		return
	end
	local msg = tostring(err):lower()
	for _, pattern in ipairs(THROTTLE_ERROR_PATTERNS) do
		if string.find(msg, pattern, 1, true) then
			DataStoreThrottleLockout.markThrottled(nil)
			return
		end
	end
end

-- Server-side TTL cache untuk hasil leaderboard.
-- DataStore GetSortedAsync + per-entry GetAsync sangat mahal saat 70-80 player
-- join bersamaan (assignRobuxTopDonate dipanggil per join). Cache ini
-- menurunkan ratusan DataStore call per menit menjadi ~1 per TTL window.
local LEADERBOARD_CACHE_TTL = 60 -- detik
local PLAYER_TOTAL_CACHE_TTL = 90 -- detik
local METADATA_CACHE_TTL = 300 -- detik (R10.2, R10.3)
local leaderboardCache: { [string]: { value: any, exp: number } } = {}
local metadataCache: { [string]: { value: any, exp: number } } = {}

local function cacheGet(key: string): any?
	local entry = leaderboardCache[key]
	if not entry then
		return nil
	end
	if os.clock() > entry.exp then
		leaderboardCache[key] = nil
		return nil
	end
	return entry.value
end

local function cacheSet(key: string, value: any, ttl: number)
	leaderboardCache[key] = { value = value, exp = os.clock() + ttl }
end

local function cacheInvalidatePrefix(prefix: string)
	for key in pairs(leaderboardCache) do
		if string.sub(key, 1, #prefix) == prefix then
			leaderboardCache[key] = nil
		end
	end
end

-- Patch #2 R3: Coalesce leaderboard cache invalidation per detik.
-- Tanpa ini, setiap donasi burst -> N invalidations (O(N) cache iter per donation).
-- Dengan ini, N donasi dalam 1 detik -> 1 invalidation di akhir window.
-- Trade-off: ~1s staleness window setelah donasi sebelum cache dibersihkan.
-- Acceptable karena LEADERBOARD_CACHE_TTL=60s (1s << 60s) dan DataStore sudah write
-- sebelum mark-dirty, jadi DataStore state selalu lebih baru dari cache TTL.
local robuxLeaderboardDirty: boolean = false
local communityLeaderboardDirty: boolean = false
local playerTotalDirty: { [number]: true } = {}

local DIRTY_FLUSH_INTERVAL = 1 -- detik

local function flushDirtyCaches()
	if robuxLeaderboardDirty then
		cacheInvalidatePrefix("robux:")
		robuxLeaderboardDirty = false
	end
	if communityLeaderboardDirty then
		cacheInvalidatePrefix("community:")
		communityLeaderboardDirty = false
	end
	if next(playerTotalDirty) ~= nil then
		for userId in pairs(playerTotalDirty) do
			leaderboardCache["playerTotal:" .. tostring(userId)] = nil
		end
		playerTotalDirty = {}
	end
end

-- R10.2, R10.3: Per-user metadata cache (username, displayName, thumbnail).
-- Serves reads up to METADATA_CACHE_TTL without a DataStore call.
local function metadataCacheGet(key: string): any?
	local entry = metadataCache[key]
	if not entry then
		return nil
	end
	if os.clock() > entry.exp then
		metadataCache[key] = nil
		return nil
	end
	return entry.value
end

local function metadataCacheSet(key: string, value: any)
	metadataCache[key] = { value = value, exp = os.clock() + METADATA_CACHE_TTL }
end

local function metadataCacheInvalidate(key: string)
	metadataCache[key] = nil
end

type Result<T> = Types.Result<T>
type CommunityData = Types.CommunityData
type RecordStatus = "processed" | "duplicate"

export type PlayerLeaderboardEntry = {
	rank: number,
	userId: number,
	username: string,
	displayName: string,
	thumbnail: string,
	total: number,
}

export type CommunityLeaderboardEntry = {
	rank: number,
	communityId: number,
	communityName: string,
	communityLogo: string,
	total: number,
}

export type RobuxDonationRecord = {
	purchaseId: string,
	userId: number,
	username: string,
	displayName: string,
	thumbnail: string,
	amount: number,
	productId: number,
	community: CommunityData?,
}

local function createRepository(deps: { logger: Types.ILogger? }?)
	local log = if deps and deps.logger then deps.logger else Logger.new("DonationLeaderboardRepository")
	local cfg = Config.Leaderboards
	local robuxStore = DataStoreService:GetOrderedDataStore(cfg.ROBUX_USER_ORDERED_KEY)
	local communityStore = DataStoreService:GetOrderedDataStore(cfg.ROBUX_COMMUNITY_ORDERED_KEY)
	local metadataStore = DataStoreService:GetDataStore(cfg.METADATA_KEY)
	local receiptStore = DataStoreService:GetDataStore(cfg.RECEIPT_KEY)
	local budgetGate = BudgetGate.create({ logger = log, name = "DonationLeaderboardRepository" })

	-- Budget protection: reject donation writes when budget is critically low.
	-- At 150 CCU, each donation consumes ~10 credits (receipt + leaderboard + metadata + overhead).
	-- Budget is 26/sec for writes. Without this gate, a burst of 3+ donations
	-- within 1 second exhausts the budget for the next 10+ seconds.
	-- This gate refuses the write early, allowing the donation to be retried
	-- on next poll cycle when budget has recovered.
	local MIN_BUDGET_FOR_DONATION = Config.Donation.MIN_BUDGET_FOR_DONATION or 8

	local function hasBudgetForDonation(): boolean
		local ok, budget = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementAsync)
		end)
		return ok and type(budget) == "number" and budget >= MIN_BUDGET_FOR_DONATION
	end

	local repo = {}

	-- Patch #2 R3: Mark-dirty API. Dipanggil dari write path (recordRobuxDonation,
	-- adjustRobuxTotal). Background ticker spawned di akhir createRepository flush
	-- semua dirty flag sekaligus per detik (1 write batch = 1 invalidation).
	function repo:markRobuxLeaderboardDirty()
		robuxLeaderboardDirty = true
	end

	function repo:markCommunityLeaderboardDirty()
		communityLeaderboardDirty = true
	end

	function repo:markPlayerTotalDirty(userId: number)
		if type(userId) == "number" and userId > 0 then
			playerTotalDirty[userId] = true
		end
	end

	-- Immediate flush for post-donate rank resolve (avoid ~1s stale GetSortedAsync page).
	function repo:flushDirtyCaches()
		flushDirtyCaches()
	end

	-- R7.4, R7.5: Defer/retry wrapper — when BudgetGate returns budget_exhausted,
	-- retry at ≤6s intervals over a 60s window. On expiry, return failure.
	local DEFER_RETRY_INTERVAL = 6
	local DEFER_RETRY_WINDOW = 60

	local function executeWithDeferRetry(incrementFn: () -> Result<nil>, label: string): Result<nil>
		local startedAt = os.clock()
		local attempt = 0
		while true do
			attempt += 1
			local result = incrementFn()
			if result.ok then
				if attempt > 1 then
					log:info("Deferred increment succeeded after retry", {
						label = label,
						attempt = attempt,
						deferredMs = math.floor((os.clock() - startedAt) * 1000),
					})
				end
				return result
			end

			-- Only retry on budget exhaustion; other errors are terminal.
			if result.error ~= "budget_exhausted" then
				return result
			end

			local elapsed = os.clock() - startedAt
			if elapsed >= DEFER_RETRY_WINDOW then
				log:error("Deferred increment exhausted retry window", {
					label = label,
					attempt = attempt,
					elapsedMs = math.floor(elapsed * 1000),
				})
				return Result.Err("defer_window_exhausted")
			end

			log:warn("Increment deferred — retrying", {
				label = label,
				attempt = attempt,
				elapsedMs = math.floor(elapsed * 1000),
			})
			task.wait(DEFER_RETRY_INTERVAL)
		end
	end

	-- Patch #2 R4: Defer/retry wrapper untuk reads. Sama seperti
	-- executeWithDeferRetry (writes), tapi window lebih pendek (30s vs 60s)
	-- karena caller bisa dapat fallback dari cache (TTL 60s) atau join-time
	-- pre-fetch yang lain. Retry hanya on budget_exhausted (transient) -
	-- terminal error langsung return. Budget biasanya recover <1s setelah
	-- exhaustion di Roblox, jadi 2s interval + 30s window = max 15 attempts
	-- untuk handle transient storms saat high-load.
	local DEFER_RETRY_READ_INTERVAL = 2 -- detik
	local DEFER_RETRY_READ_WINDOW = 30 -- detik

	local function executeWithDeferRetryRead<T>(readFn: () -> Result<T>, label: string): Result<T>
		local startedAt = os.clock()
		local attempt = 0
		while true do
			attempt += 1
			local result = readFn()
			if result.ok then
				if attempt > 1 then
					log:info("Deferred read succeeded after retry", {
						label = label,
						attempt = attempt,
						deferredMs = math.floor((os.clock() - startedAt) * 1000),
					})
				end
				return result
			end

			-- Only retry on budget exhaustion; other errors are terminal.
			if result.error ~= "budget_exhausted" then
				return result
			end

			local elapsed = os.clock() - startedAt
			if elapsed >= DEFER_RETRY_READ_WINDOW then
				log:error("Deferred read exhausted retry window", {
					label = label,
					attempt = attempt,
					elapsedMs = math.floor(elapsed * 1000),
				})
				return Result.Err("defer_window_exhausted")
			end

			log:warn("Read deferred — retrying", {
				label = label,
				attempt = attempt,
				elapsedMs = math.floor(elapsed * 1000),
			})
			task.wait(DEFER_RETRY_READ_INTERVAL)
		end
	end

	local function sanitizeText(value: any, maxLength: number): string
		if type(value) ~= "string" then
			return ""
		end
		return string.sub(value, 1, maxLength)
	end

	local function sanitizeLimit(limit: number?): number
		local resolved = tonumber(limit) or cfg.DEFAULT_LIMIT
		return math.clamp(math.floor(resolved), 1, cfg.MAX_LIMIT)
	end

	local function getUserThumbnail(userId: number): string
		-- Prefer rbxthumb — avoids Players:GetUserThumbnailAsync storms on rebuild.
		-- Top 1-3 posters can still use 420 client-side via rbxthumb URL.
		return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
	end

	local function isHiddenRobuxUser(userId: number): boolean
		local hiddenUserIds = cfg.HIDDEN_ROBUX_USER_IDS
		return type(hiddenUserIds) == "table" and hiddenUserIds[userId] == true
	end

	local function metadataKey(kind: string, id: number): string
		return ("%s:%d"):format(kind, id)
	end

	local function receiptKey(purchaseId: string): string
		return "receipt:" .. purchaseId
	end

	local function isReceiptProcessed(record: any): boolean
		return type(record) == "table"
			and (record.status == "processed" or record.processed == true)
	end

	local function invalidateMemoryStoreLeaderboards()
		if cfg.MEMORY_STORE_CACHE_ENABLED ~= true then
			return
		end
		local storeName = cfg.MEMORY_STORE_STORE_NAME
		for _, prefix in ipairs({ "robux:", "community:" }) do
			for _, limit in ipairs({ cfg.DEFAULT_LIMIT, cfg.ROBUX_LIMIT, cfg.COMMUNITY_LIMIT, cfg.ROBUX_PAINT_LIMIT }) do
				if type(limit) == "number" and limit > 0 then
					MemoryStoreCache.remove(storeName, prefix .. tostring(limit))
				end
			end
		end
	end

	local function invalidateLocalLeaderboardCaches()
		cacheInvalidatePrefix("robux:")
		cacheInvalidatePrefix("community:")
		invalidateMemoryStoreLeaderboards()
	end

	-- Other servers drop local+MS LB cache after a write on this server.
	CrossServerCache.subscribe(LEADERBOARD_INVALIDATE_TOPIC, function(_userId: number)
		invalidateLocalLeaderboardCaches()
	end)

	local function publishLeaderboardInvalidation()
		CrossServerCache.publish(LEADERBOARD_INVALIDATE_TOPIC, 0)
	end

	type ReceiptState = {
		status: string,
		userId: number,
		productId: number,
		amount: number,
		userIncremented: boolean?,
		communityIncremented: boolean?,
		userIncrementStarted: boolean?,
		communityIncrementStarted: boolean?,
		communityId: number?,
		claimedAt: number?,
		processedAt: number?,
		processed: boolean?,
	}

	type ReceiptClaimResult = {
		kind: "new" | "resume" | "duplicate",
		state: ReceiptState?,
	}

	local function claimReceipt(record: RobuxDonationRecord): Result<ReceiptClaimResult>
		local claimed: ReceiptClaimResult? = nil
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return Result.withRetry(function()
				receiptStore:UpdateAsync(receiptKey(record.purchaseId), function(current: any): any
					if isReceiptProcessed(current) then
						claimed = { kind = "duplicate", state = current :: ReceiptState }
						return current
					end
					if type(current) == "table" and current.status == "pending" then
						claimed = { kind = "resume", state = current :: ReceiptState }
						return current
					end
					local pending: ReceiptState = {
						status = "pending",
						userId = record.userId,
						productId = record.productId,
						amount = math.max(0, math.floor(record.amount)),
						userIncremented = false,
						communityIncremented = false,
						userIncrementStarted = false,
						communityIncrementStarted = false,
						communityId = if record.community then record.community.id else nil,
						claimedAt = os.time(),
					}
					claimed = { kind = "new", state = pending }
					return pending
				end)
				return claimed
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)
		if not result.ok then
			maybeMarkThrottledFromError(result.error)
			return Result.Err(result.error)
		end
		if type(result.value) ~= "table" then
			return Result.Err("receipt_claim_failed")
		end
		return Result.Ok(result.value :: ReceiptClaimResult)
	end

	local function persistReceiptProgress(
		purchaseId: string,
		flags: {
			userIncremented: boolean?,
			communityIncremented: boolean?,
			userIncrementStarted: boolean?,
			communityIncrementStarted: boolean?,
		}
	): Result<ReceiptState>
		local saved: ReceiptState? = nil
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return Result.withRetry(function()
				receiptStore:UpdateAsync(receiptKey(purchaseId), function(current: any): any
					if type(current) ~= "table" or current.status ~= "pending" then
						return nil
					end
					local nextState = table.clone(current) :: ReceiptState
					if flags.userIncrementStarted == true then
						nextState.userIncrementStarted = true
					end
					if flags.communityIncrementStarted == true then
						nextState.communityIncrementStarted = true
					end
					if flags.userIncremented == true then
						nextState.userIncremented = true
						nextState.userIncrementStarted = true
					end
					if flags.communityIncremented == true then
						nextState.communityIncremented = true
						nextState.communityIncrementStarted = true
					end
					saved = nextState
					return nextState
				end)
				return nil
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)
		if not result.ok then
			maybeMarkThrottledFromError(result.error)
			return Result.Err(result.error)
		end
		if not saved then
			return Result.Err("receipt_progress_lost")
		end
		return Result.Ok(saved)
	end

	local function finalizeReceiptProcessed(record: RobuxDonationRecord): Result<nil>
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return Result.withRetry(function()
				receiptStore:UpdateAsync(receiptKey(record.purchaseId), function(current: any): any
					if isReceiptProcessed(current) then
						return current
					end
					if type(current) ~= "table" or current.status ~= "pending" then
						return nil
					end
					return {
						status = "processed",
						processed = true,
						userId = record.userId,
						productId = record.productId,
						amount = math.max(0, math.floor(record.amount)),
						userIncremented = true,
						communityIncremented = if record.community then true else current.communityIncremented == true,
						communityId = if record.community then record.community.id else current.communityId,
						claimedAt = current.claimedAt or os.time(),
						processedAt = os.time(),
					}
				end)
				return nil
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)
		if not result.ok then
			maybeMarkThrottledFromError(result.error)
			return Result.Err(result.error)
		end
		return Result.Ok(nil)
	end

	local function readMetadata(kind: string, id: number): any
		-- R10.2: Serve from metadata cache if present and within TTL.
		local cacheKey = string.format("%s:%d", kind, id)
		local cached = metadataCacheGet(cacheKey)
		if cached ~= nil then
			return cached
		end

		-- R10.3: Cache miss or expiry — read through BudgetGate and refresh timestamp.
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
			return Result.withRetry(function()
				return metadataStore:GetAsync(metadataKey(kind, id))
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)
		if result.ok and type(result.value) == "table" then
			metadataCacheSet(cacheKey, result.value)
			return result.value
		end
		return nil
	end

	-- Max metadata entries to read from DataStore per call.
	-- Entries beyond this limit return nil; callers already have HTTP API
	-- fallback (Players:GetNameFromUserIdAsync) that resolves names without
	-- touching DataStore. Set conservatively to stay within Standard Read
	-- budget even at 1 player (70/min ≈ 1.17/sec). 20 sequential reads
	-- through BudgetGate take ~10s on cold start — acceptable because
	-- metadata cache (TTL=300s) makes subsequent reads instant, and the
	-- workspace cache (TTL=60s) prevents repeated cold builds.
	local METADATA_READ_LIMIT = 20

	local function batchReadMetadata(kind: string, ids: { number }): { any }
		local results: { any } = {}
		local n = #ids
		if n == 0 then
			return results
		end
		-- Sequential reads through BudgetGate. Each read defers if budget is
		-- low (BudgetGate polls at 0.5s intervals, times out at 5s). This
		-- prevents the parallel-burst pattern that exhausted Standard Read
		-- budget at cold start (100 concurrent GetAsync → 70 budget → throttle).
		local readCount = math.min(n, METADATA_READ_LIMIT)
		for i = 1, readCount do
			results[i] = readMetadata(kind, ids[i])
		end
		return results
	end

	local function writeMetadata(kind: string, id: number, data: { [string]: any }): Result<nil>
		local mk = metadataKey(kind, id)
		local cacheKey = string.format("%s:%d", kind, id)
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return Result.withRetry(function()
				metadataStore:UpdateAsync(mk, function(current: any): any
					if kind == "community" then
						return {
							communityId = id,
							communityName = sanitizeText(data.communityName, 80),
							communityLogo = sanitizeText(data.communityLogo, 512),
							updatedAt = tonumber(data.updatedAt) or os.time(),
						}
					end

					local existing = if type(current) == "table" then current else {}
					local verified = existing.displayNameVerified == true
					if data.displayNameVerified == true then
						verified = true
					elseif data.displayNameVerified == false then
						verified = false
					end

					return {
						userId = id,
						username = sanitizeText(data.username or existing.username, 64),
						displayName = sanitizeText(data.displayName or existing.displayName, 64),
						thumbnail = sanitizeText(data.thumbnail or existing.thumbnail, 512),
						displayNameVerified = verified,
						updatedAt = tonumber(data.updatedAt) or os.time(),
					}
				end)
				return nil
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)
		if not result.ok then
			log:warn("Leaderboard metadata write failed", {
				kind = kind,
				id = id,
				error = result.error,
			})
			maybeMarkThrottledFromError(result.error)
			return Result.Err(result.error)
		end
		-- R10.3: Invalidate metadata cache on write so next read picks up fresh data.
		metadataCacheInvalidate(cacheKey)
		return Result.Ok(nil)
	end

	local function hasProcessedReceipt(purchaseId: string): Result<boolean>
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
			return Result.withRetry(function()
				return receiptStore:GetAsync(receiptKey(purchaseId))
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)
		if not result.ok then
			maybeMarkThrottledFromError(result.error)
			return Result.Err(result.error)
		end
		return Result.Ok(isReceiptProcessed(result.value))
	end

	local function markReceiptProcessed(record: RobuxDonationRecord): Result<nil>
		return finalizeReceiptProcessed(record)
	end

	function repo:recordRobuxDonation(
		record: RobuxDonationRecord,
		opts: { receiptMode: boolean? }?
	): Result<RecordStatus>
		-- P0: Skip DS writes saat throttle lockout aktif. Purchase receipt
		-- tetap akan diproses via HTTP path (Cloudflare Worker) di DonationService;
		-- DataStore leaderboard increment akan di-reconcile via mark-dirty +
		-- eventual re-poll saat lockout expire.
		if DataStoreThrottleLockout.isLocked() then
			return Result.Err("ds_throttled")
		end
		-- Budget protection: refuse if not enough budget for full donation cycle.
		-- The donation will be retried on next poll cycle (5-15s) when budget recovers.
		if not hasBudgetForDonation() then
			log:warn("Donation write refused: low budget", {
				userId = record.userId,
				amount = record.amount,
			})
			return Result.Err("budget_exhausted")
		end
		if record.purchaseId == "" then
			return Result.Err("missing purchaseId")
		end
		if record.userId <= 0 or record.amount <= 0 then
			return Result.Err("invalid donation record")
		end
		if isHiddenRobuxUser(record.userId) then
			return Result.Ok("processed")
		end

		local claimResult = claimReceipt(record)
		if not claimResult.ok then
			return Result.Err(claimResult.error)
		end
		local claim = claimResult.value
		if claim.kind == "duplicate" then
			return Result.Ok("duplicate")
		end

		local receiptState = claim.state
		local needsUserIncrement = not (receiptState and receiptState.userIncremented == true)

		-- Community credit is frozen at claim time (receiptState.communityId).
		-- Retries must not re-resolve /setcommun or primary-group — wrong or lost credit.
		local frozenCommunityId = if receiptState then receiptState.communityId else nil
		local effectiveCommunity: CommunityData? = nil
		if type(frozenCommunityId) == "number" and frozenCommunityId > 0 then
			if record.community and record.community.id == frozenCommunityId then
				effectiveCommunity = record.community
			else
				effectiveCommunity = {
					id = frozenCommunityId,
					name = "Community " .. tostring(frozenCommunityId),
					logo = "",
				}
			end
		end
		local needsCommunityIncrement = effectiveCommunity ~= nil
			and not (receiptState and receiptState.communityIncremented == true)

		local receiptMode = opts and opts.receiptMode == true

		-- R7.1-R7.3: Route community IncrementAsync through BudgetGate (2 credits).
		-- R7.4, R7.5: Outer defer/retry loop — retries at ≤6s intervals up to 60s.
		-- receiptMode skips defer/retry so ProcessReceipt cannot block for up to 60s.
		local function gatedCommunityIncrement(communityId: number, amount: number): Result<nil>
			local function incrementOnce(): Result<nil>
				if Config.Donation.ENABLE_GATED_INCREMENTS then
					return budgetGate:executeAsync(Enum.DataStoreRequestType.SetIncrementAsync, function()
						return Result.withRetry(function()
							communityStore:IncrementAsync(tostring(communityId), amount)
							return nil
						end, Config.DataStore.RETRY_ATTEMPTS)
					end)
				end
				return Result.withRetry(function()
					communityStore:IncrementAsync(tostring(communityId), amount)
					return nil
				end, Config.DataStore.RETRY_ATTEMPTS)
			end
			if receiptMode then
				return incrementOnce()
			end
			return executeWithDeferRetry(incrementOnce, "community:" .. tostring(communityId))
		end

		-- R7.1-R7.3: Route user IncrementAsync through BudgetGate (2 credits).
		-- R7.4, R7.5: Outer defer/retry loop.
		local function gatedUserIncrement(userId: number, amount: number): Result<nil>
			local function incrementOnce(): Result<nil>
				if Config.Donation.ENABLE_GATED_INCREMENTS then
					return budgetGate:executeAsync(Enum.DataStoreRequestType.SetIncrementAsync, function()
						return Result.withRetry(function()
							robuxStore:IncrementAsync(tostring(userId), amount)
							return nil
						end, Config.DataStore.RETRY_ATTEMPTS)
					end)
				end
				return Result.withRetry(function()
					robuxStore:IncrementAsync(tostring(userId), amount)
					return nil
				end, Config.DataStore.RETRY_ATTEMPTS)
			end
			if receiptMode then
				return incrementOnce()
			end
			return executeWithDeferRetry(incrementOnce, "user:" .. tostring(userId))
		end

		-- Intent-before-Increment: prefer under-credit over double-credit if progress
		-- fails after IncrementAsync (or crash between intent and Increment).
		if needsUserIncrement then
			local userStarted = receiptState and receiptState.userIncrementStarted == true
			if not userStarted then
				local intentResult = persistReceiptProgress(record.purchaseId, { userIncrementStarted = true })
				if not intentResult.ok then
					return Result.Err(intentResult.error)
				end
				receiptState = intentResult.value
				local incrementResult = gatedUserIncrement(record.userId, record.amount)
				if not incrementResult.ok then
					return Result.Err(incrementResult.error)
				end
			else
				log:warn("Resuming Robux receipt after userIncrementStarted — skipping Increment to avoid double credit", {
					purchaseId = record.purchaseId,
					userId = record.userId,
				})
			end
			local progressResult = persistReceiptProgress(record.purchaseId, { userIncremented = true })
			if not progressResult.ok then
				return Result.Err(progressResult.error)
			end
			receiptState = progressResult.value
		end

		if needsCommunityIncrement and effectiveCommunity then
			local community = effectiveCommunity
			local communityStarted = receiptState and receiptState.communityIncrementStarted == true
			if not communityStarted then
				local intentResult = persistReceiptProgress(record.purchaseId, { communityIncrementStarted = true })
				if not intentResult.ok then
					return Result.Err(intentResult.error)
				end
				receiptState = intentResult.value
				local communityResult = gatedCommunityIncrement(community.id, record.amount)
				if not communityResult.ok then
					return Result.Err(communityResult.error)
				end
			else
				log:warn("Resuming Robux receipt after communityIncrementStarted — skipping Increment to avoid double credit", {
					purchaseId = record.purchaseId,
					communityId = community.id,
				})
			end
			local progressResult = persistReceiptProgress(record.purchaseId, { communityIncremented = true })
			if not progressResult.ok then
				return Result.Err(progressResult.error)
			end
			writeMetadata("community", community.id, {
				communityId = community.id,
				communityName = community.name or ("Community " .. tostring(community.id)),
				communityLogo = community.logo or "",
				updatedAt = os.time(),
			})
		end

		writeMetadata("user", record.userId, {
			userId = record.userId,
			username = record.username,
			displayName = record.displayName,
			thumbnail = record.thumbnail,
			displayNameVerified = true,
			updatedAt = os.time(),
		})

		-- finalizeReceiptProcessed still uses record.community for communityIncremented flag;
		-- pass frozen community so finalize matches credit path.
		local finalizeRecord = record
		if effectiveCommunity then
			finalizeRecord = table.clone(record)
			finalizeRecord.community = effectiveCommunity
		elseif frozenCommunityId == nil then
			finalizeRecord = table.clone(record)
			finalizeRecord.community = nil
		end

		local markResult = finalizeReceiptProcessed(finalizeRecord)
		if not markResult.ok then
			log:error("Donation receipt finalize failed after leaderboard increment", {
				purchaseId = record.purchaseId,
				userId = record.userId,
				error = markResult.error,
			})
			return Result.Err(markResult.error)
		end

		-- Patch #2 R3: Mark-dirty (coalesced) instead of direct invalidation.
		repo:markRobuxLeaderboardDirty()
		repo:markCommunityLeaderboardDirty()
		repo:markPlayerTotalDirty(record.userId)
		invalidateMemoryStoreLeaderboards()
		publishLeaderboardInvalidation()

		return Result.Ok("processed")
	end

	-- Admin/manual Robux adjustment (no purchase receipt). Syncs OrderedDataStore leaderboard.
	-- R7.6: Idempotency via processed-set to prevent duplicate increments on retry/replay.
	local processedAdjustments: { [string]: boolean } = {}

	function repo:adjustRobuxTotal(record: {
		userId: number,
		username: string?,
		displayName: string?,
		thumbnail: string?,
		amount: number,
	}): Result<nil>
		local userId = math.floor(tonumber(record.userId) or 0)
		local amount = math.floor(tonumber(record.amount) or 0)
		if userId <= 0 or amount == 0 then
			return Result.Err("invalid robux adjustment")
		end
		if isHiddenRobuxUser(userId) then
			return Result.Ok(nil)
		end

		-- P0: Skip DS writes saat throttle lockout aktif.
		if DataStoreThrottleLockout.isLocked() then
			return Result.Err("ds_throttled")
		end

		-- R7.1-R7.3: Route IncrementAsync through BudgetGate (2 credits).
		-- R7.6: Idempotency key includes timestamp to allow legitimate repeat adjustments
		-- of the same amount while still preventing rapid double-submit within 60s.
		local nowBucket = math.floor(os.time() / 60) -- 1-minute buckets
		local idempotencyKey = string.format("%d:%d:%d", userId, amount, nowBucket)
		if processedAdjustments[idempotencyKey] then
			return Result.Ok(nil)
		end

		local incrementResult: Result<nil>
		if Config.Donation.ENABLE_GATED_INCREMENTS then
			incrementResult = executeWithDeferRetry(function()
				return budgetGate:executeAsync(Enum.DataStoreRequestType.SetIncrementAsync, function()
					return Result.withRetry(function()
						robuxStore:IncrementAsync(tostring(userId), amount)
						return nil
					end, Config.DataStore.RETRY_ATTEMPTS)
				end)
			end, "adjust:" .. tostring(userId))
		else
			incrementResult = Result.withRetry(function()
				robuxStore:IncrementAsync(tostring(userId), amount)
				return nil
			end, Config.DataStore.RETRY_ATTEMPTS)
		end
		if not incrementResult.ok then
			return Result.Err(incrementResult.error)
		end

		processedAdjustments[idempotencyKey] = true

		local username = sanitizeText(record.username, 32)
		local displayName = sanitizeText(record.displayName or record.username, 64)
		local thumbnail = if type(record.thumbnail) == "string" and record.thumbnail ~= ""
			then record.thumbnail
			else getUserThumbnail(userId)
		writeMetadata("user", userId, {
			userId = userId,
			username = username,
			displayName = displayName,
			thumbnail = thumbnail,
			displayNameVerified = true,
			updatedAt = os.time(),
		})

		-- Patch #2 R3: Mark-dirty (coalesced) instead of direct invalidation.
		repo:markRobuxLeaderboardDirty()
		repo:markPlayerTotalDirty(userId)
		invalidateMemoryStoreLeaderboards()
		publishLeaderboardInvalidation()
		return Result.Ok(nil)
	end

	function repo:getRobuxLeaderboard(limit: number?): Result<{ PlayerLeaderboardEntry }>
		-- P0: Short-circuit kalau global throttle lockout aktif. Caller fall
		-- back ke TTL cache (LEADERBOARD_CACHE_TTL=60s) atau empty leaderboard.
		if DataStoreThrottleLockout.isLocked() then
			return Result.Err("ds_throttled")
		end
		local resolvedLimit = sanitizeLimit(limit)
		local cacheKey = "robux:" .. tostring(resolvedLimit)
		local cached = cacheGet(cacheKey)
		if cached ~= nil then
			return Result.Ok(cached)
		end

		-- P1.1: MemoryStore cross-server cache. Hit => skip DataStore GetSortedAsync
		-- sepenuhnya (drop terbesar di DS quota). Miss => fallback ke DS path.
		local memoryStoreName = cfg.MEMORY_STORE_STORE_NAME
		local memoryStoreKey = cacheKey
		local msCached = MemoryStoreCache.get(memoryStoreName, memoryStoreKey)
		if type(msCached) == "table" then
			cacheSet(cacheKey, msCached, LEADERBOARD_CACHE_TTL)
			return Result.Ok(msCached :: { PlayerLeaderboardEntry })
		end

		local fetchLimit = cfg.MAX_LIMIT
		-- Patch #2 R4: Wrap read with defer/retry on budget_exhausted.
		local result = executeWithDeferRetryRead(function()
			return budgetGate:executeAsync(Enum.DataStoreRequestType.GetSortedAsync, function()
				return Result.withRetry(function()
					return robuxStore:GetSortedAsync(false, fetchLimit)
				end, Config.DataStore.RETRY_ATTEMPTS)
			end)
		end, "getRobuxLeaderboard")
		if not result.ok then
			maybeMarkThrottledFromError(result.error)
			return Result.Err(result.error)
		end

		local page = result.value:GetCurrentPage()
		-- P1.2: Collect userIds dulu, lalu batch read metadata (parallel).
		-- Cache hidden-user filtering di sini; yang lolos akan dapat metadata.
		local pageIds: { number } = {}
		local pageItems: { any } = {}
		for _, item in ipairs(page) do
			local userId = tonumber(item.key) or 0
			if userId > 0 and not isHiddenRobuxUser(userId) then
				table.insert(pageIds, userId)
				table.insert(pageItems, item)
				if #pageIds >= resolvedLimit then
					break
				end
			end
		end
		local metadataList = batchReadMetadata("user", pageIds)
		local entries = {} :: { PlayerLeaderboardEntry }
		for i, item in ipairs(pageItems) do
			local userId = pageIds[i]
			local metadata = metadataList[i]
			local username = type(metadata) == "table" and type(metadata.username) == "string" and metadata.username
				or nil
			local displayName = type(metadata) == "table"
					and type(metadata.displayName) == "string"
					and metadata.displayName
				or nil
			-- Detect stale fallback names ("User 12345") persisted from earlier
			-- writes when the player was offline. Treat as unresolved.
			local function looksLikeFallback(name: string?): boolean
				if not name then return true end
				return name:match("^User%s*%d+$") ~= nil or name == ""
			end
			if looksLikeFallback(username) or looksLikeFallback(displayName) then
				username = nil
				displayName = nil
			end
			-- Fallback: resolve username via Roblox API if metadata missing or stale.
			if not username then
				-- HTTP API telemetry counter (quota-efficiency-pass-2026-06, Phase 0).
				-- Only fire when wrapper disabled (when enabled, wrapper's internal counter handles it).
				if (not (Config.HttpApi and Config.HttpApi.ENABLED)) and Config.HttpApi and Config.HttpApi.COUNTERS_ENABLED then
					HttpApiCounter.record("leaderboard_getname_total")
				end
				local resolvedName = HttpApi.getNameFromUserIdAsync(userId)
				if type(resolvedName) == "string" and resolvedName ~= "" then
					username = resolvedName
					if not displayName then
						displayName = resolvedName
					end
					-- Note: metadata write-back intentionally omitted from hot read path.
					-- Writing 10+ entries simultaneously floods DataStore queue in Studio.
					-- Metadata self-heals at next donation event (ShopController writes it).
				else
					username = "User " .. tostring(userId)
				end
			end
			-- DisplayName == Username is valid on Roblox; only resolve when missing.
			if not displayName then
				local userInfos = HttpApi.getUserInfosByUserIdsAsync({ userId })
				local info = userInfos[userId]
				if type(info) == "table" then
					if type(info.DisplayName) == "string" and info.DisplayName ~= "" then
						displayName = info.DisplayName
					end
					if type(info.Username) == "string" and info.Username ~= "" then
						username = info.Username
					end
				end
			end
			if not displayName then
				displayName = username
			end
			local thumbnail = type(metadata) == "table" and type(metadata.thumbnail) == "string" and metadata.thumbnail
				or getUserThumbnail(userId)
			local displayNameVerified = type(metadata) == "table" and metadata.displayNameVerified == true
			table.insert(entries, {
				rank = #entries + 1,
				userId = userId,
				username = username,
				displayName = displayName,
				thumbnail = thumbnail,
				displayNameVerified = displayNameVerified,
				total = tonumber(item.value) or 0,
			})
		end
		cacheSet(cacheKey, entries, LEADERBOARD_CACHE_TTL)
		-- P1.1: Populate MemoryStore (cross-server cache). Best-effort — kalau
		-- MemoryStore error/disabled, DS result tetap dipakai local cache.
		MemoryStoreCache.set(memoryStoreName, memoryStoreKey, entries, cfg.MEMORY_STORE_LEADERBOARD_TTL)
		return Result.Ok(entries)
	end

	function repo:getPlayerRobuxTotal(userId: number): Result<number>
		if isHiddenRobuxUser(userId) then
			return Result.Ok(0)
		end
		-- P0: Short-circuit kalau global throttle lockout aktif.
		if DataStoreThrottleLockout.isLocked() then
			return Result.Err("ds_throttled")
		end

		local cacheKey = "playerTotal:" .. tostring(userId)
		local cached = cacheGet(cacheKey)
		if cached ~= nil then
			return Result.Ok(cached)
		end

		-- Patch #2 R4: Wrap read with defer/retry on budget_exhausted.
		local result = executeWithDeferRetryRead(function()
			return budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
				return Result.withRetry(function()
					return robuxStore:GetAsync(tostring(userId))
				end, Config.DataStore.RETRY_ATTEMPTS)
			end)
		end, "getPlayerRobuxTotal")
		if not result.ok then
			maybeMarkThrottledFromError(result.error)
			return Result.Err(result.error)
		end
		local total = tonumber(result.value) or 0
		cacheSet(cacheKey, total, PLAYER_TOTAL_CACHE_TTL)
		return Result.Ok(total)
	end

	-- Rank for donor profile panel. Uses cached leaderboard + player total from DataStore.
	function repo:getPlayerRobuxRank(userId: number, knownTotal: number?): Result<number?>
		if isHiddenRobuxUser(userId) then
			return Result.Ok(nil)
		end

		local total = math.max(0, math.floor(tonumber(knownTotal) or 0))
		if total <= 0 then
			local totalResult = repo:getPlayerRobuxTotal(userId)
			if not totalResult.ok then
				return Result.Err(totalResult.error)
			end
			total = totalResult.value
		end
		if total <= 0 then
			return Result.Ok(nil)
		end

		local lookupLimit = math.max(
			Config.Donation.DONOR_PROFILE_RANK_LOOKUP_LIMIT or 100,
			cfg.MAX_LIMIT
		)
		local leaderboardResult = repo:getRobuxLeaderboard(lookupLimit)
		if not leaderboardResult.ok then
			return Result.Err(leaderboardResult.error)
		end

		local entries = leaderboardResult.value
		for rank, entry in ipairs(entries) do
			if entry.userId == userId then
				return Result.Ok(rank)
			end
		end

		-- Not in the fetched page: estimate rank from totals (descending sort).
		local estimatedRank = 1
		for _, entry in ipairs(entries) do
			if entry.total > total then
				estimatedRank += 1
			end
		end
		if #entries >= lookupLimit and estimatedRank > #entries then
			return Result.Ok(nil)
		end
		return Result.Ok(estimatedRank)
	end

	function repo:getCommunityLeaderboard(limit: number?): Result<{ CommunityLeaderboardEntry }>
		-- P0: Short-circuit kalau global throttle lockout aktif.
		if DataStoreThrottleLockout.isLocked() then
			return Result.Err("ds_throttled")
		end
		local resolvedLimit = sanitizeLimit(limit)
		local cacheKey = "community:" .. tostring(resolvedLimit)
		local cached = cacheGet(cacheKey)
		if cached ~= nil then
			return Result.Ok(cached)
		end

		-- P1.1: MemoryStore cross-server cache.
		local memoryStoreName = cfg.MEMORY_STORE_STORE_NAME
		local memoryStoreKey = cacheKey
		local msCached = MemoryStoreCache.get(memoryStoreName, memoryStoreKey)
		if type(msCached) == "table" then
			cacheSet(cacheKey, msCached, LEADERBOARD_CACHE_TTL)
			return Result.Ok(msCached :: { CommunityLeaderboardEntry })
		end

		-- Patch #2 R4: Wrap read with defer/retry on budget_exhausted.
		local result = executeWithDeferRetryRead(function()
			return budgetGate:executeAsync(Enum.DataStoreRequestType.GetSortedAsync, function()
				return Result.withRetry(function()
					return communityStore:GetSortedAsync(false, resolvedLimit)
				end, Config.DataStore.RETRY_ATTEMPTS)
			end)
		end, "getCommunityLeaderboard")
		if not result.ok then
			maybeMarkThrottledFromError(result.error)
			return Result.Err(result.error)
		end

		local page = result.value:GetCurrentPage()
		-- P1.2: Batch read metadata parallel.
		local pageIds: { number } = {}
		local pageItems: { any } = {}
		for _, item in ipairs(page) do
			local communityId = tonumber(item.key) or 0
			if communityId > 0 then
				table.insert(pageIds, communityId)
				table.insert(pageItems, item)
				if #pageIds >= resolvedLimit then
					break
				end
			end
		end
		local metadataList = batchReadMetadata("community", pageIds)
		local entries = {} :: { CommunityLeaderboardEntry }
		for i, item in ipairs(pageItems) do
			local communityId = pageIds[i]
			local metadata = metadataList[i]
			table.insert(entries, {
				rank = #entries + 1,
				communityId = communityId,
				communityName = type(metadata) == "table"
						and type(metadata.communityName) == "string"
						and metadata.communityName
					or ("Community " .. tostring(communityId)),
				communityLogo = type(metadata) == "table"
						and type(metadata.communityLogo) == "string"
						and metadata.communityLogo
					or "",
				total = tonumber(item.value) or 0,
			})
		end
		cacheSet(cacheKey, entries, LEADERBOARD_CACHE_TTL)
		-- P1.1: Populate MemoryStore.
		MemoryStoreCache.set(memoryStoreName, memoryStoreKey, entries, cfg.MEMORY_STORE_LEADERBOARD_TTL)
		return Result.Ok(entries)
	end

	function repo:saveUserMetadata(
		userId: number,
		username: string,
		displayName: string,
		thumbnail: string?
	): Result<nil>
		return writeMetadata("user", userId, {
			userId = userId,
			username = username,
			displayName = displayName,
			thumbnail = thumbnail or getUserThumbnail(userId),
			displayNameVerified = true,
			updatedAt = os.time(),
		})
	end

	-- One-shot paint-path heal: persist UserService-resolved identity so DN==username
	-- metadata from bad seeders stops needing resolve every rebuild/TTL.
	function repo:healUserDisplayName(
		userId: number,
		username: string,
		displayName: string,
		thumbnail: string?
	): Result<nil>
		local uid = math.floor(tonumber(userId) or 0)
		if uid <= 0 then
			return Result.Err("invalid userId")
		end
		local function looksLikeFallback(name: string?): boolean
			if type(name) ~= "string" or name == "" then
				return true
			end
			return name:match("^User%s*%d+$") ~= nil
		end
		if looksLikeFallback(username) or looksLikeFallback(displayName) then
			return Result.Ok(nil)
		end
		return writeMetadata("user", uid, {
			userId = uid,
			username = username,
			displayName = displayName,
			thumbnail = thumbnail or getUserThumbnail(uid),
			displayNameVerified = true,
			updatedAt = os.time(),
		})
	end

	-- Patch #2 R3: Background ticker flush dirty cache flags per detik.
	-- Coalesce N donasi burst menjadi 1 invalidation per detik. Tanpa ini,
	-- setiap donasi trigger cacheInvalidatePrefix() (O(N) iter over leaderboardCache).
	local dirtyFlushActive = true
	local dirtyFlushThread = task.spawn(function()
		while dirtyFlushActive do
			task.wait(DIRTY_FLUSH_INTERVAL)
			if dirtyFlushActive then
				flushDirtyCaches()
			end
		end
	end)

	function repo:destroy()
		dirtyFlushActive = false
		if dirtyFlushThread then
			task.cancel(dirtyFlushThread)
			dirtyFlushThread = nil :: any
		end
		if type(budgetGate.destroy) == "function" then
			budgetGate:destroy()
		end
	end

	return repo
end

return {
	new = createRepository,
}
