--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Cache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cache)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local BudgetGate = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetGate)
local HttpApiCounter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApiCounter)
local HttpApi = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApi)

type Result<T> = Types.Result<T>
type AvatarContextLikeAction = Types.AvatarContextLikeAction
type AvatarLikeTransition = Types.AvatarLikeTransition

type LikeShardData = {
	entries: {[string]: number},
	activeCount: number,
	_version: number,
}

type LikeSummaryData = {
	totalLikes: number,
	_version: number,
}

type ToggleResult = {
	previousState: number?,
	nextState: number?,
	delta: number,
	totalLikes: number,
	transition: AvatarLikeTransition,
}

local function createAvatarLikeRepository(deps: { logger: Types.ILogger? }?)
	local log = if deps and deps.logger then deps.logger else Logger.new("AvatarLikeRepository")
	local store = DataStoreService:GetDataStore(Config.AvatarContext.LIKE_DATASTORE_KEY)
	local leaderboardStore = DataStoreService:GetOrderedDataStore(Config.Leaderboards.LIKE_ORDERED_KEY)
	local metadataStore = DataStoreService:GetDataStore(Config.Leaderboards.METADATA_KEY)
	local shardCount = Config.AvatarContext.LIKE_SHARD_COUNT
	local lastBackfillAt = 0
	local budgetGate = BudgetGate.create({ logger = log, name = "AvatarLikeRepository" })
	-- Skip unchanged OrderedDataStore / metadata writes (Persistence Fabric Phase 4).
	local lastLeaderboardScore: { [number]: number } = {}
	local lastMetadataFingerprint: { [number]: string } = {}

	-- Server-side TTL cache untuk top leaderboard.
	-- Tanpa cache ini, getTopLeaderboard memicu syncOnlineLeaderboard
	-- (write per online player) + GetSortedAsync + per-entry GetAsync metadata.
	-- Dengan 70-80 player itu ratusan DataStore call per refresh.
	local LIKES_LEADERBOARD_CACHE_TTL = 60 -- detik
	local likesLeaderboardCache: { [number]: { value: any, exp: number } } = {}

	-- In-flight dedup untuk getSummary: cegah concurrent DataStore reads
	-- untuk userId yang sama saat refreshAll burst (30 CCU semua rebuild overhead).
	-- Key = userId, Value = BindableEvent yang di-Fire saat read selesai.
	local summaryInFlight: { [number]: BindableEvent } = {}

	local repo = {}

	local function getShardStoreKey(targetUserId: number, shardId: number): string
		return ("likes:target:%d:shard:%d"):format(targetUserId, shardId)
	end

	local function getSummaryStoreKey(targetUserId: number): string
		return ("likes:summary:%d"):format(targetUserId)
	end
	local function parseSummaryUserId(storeKey: string): number?
		return tonumber(string.match(storeKey, "^likes:summary:(%d+)$"))
	end

	local function getShardCacheKey(targetUserId: number, shardId: number): string
		return ("avatarLike:shard:%d:%d"):format(targetUserId, shardId)
	end

	local function getSummaryCacheKey(targetUserId: number): string
		return ("avatarLike:summary:%d"):format(targetUserId)
	end

	local function getUserMetadataStoreKey(targetUserId: number): string
		return ("user:%d"):format(targetUserId)
	end

	local function sanitizeText(value: any, maxLength: number): string
		if type(value) ~= "string" then
			return ""
		end
		return string.sub(value, 1, maxLength)
	end

	local function getUserIdentity(userId: number): (string, string)
		local userInfos = HttpApi.getUserInfosByUserIdsAsync({ userId })
		local info = userInfos[userId]
		if type(info) == "table" then
			local username = if type(info.Username) == "string" and info.Username ~= ""
				then info.Username
				else "User " .. tostring(userId)
			local displayName = if type(info.DisplayName) == "string" and info.DisplayName ~= ""
				then info.DisplayName
				else username
			return username, displayName
		end

		-- HTTP API telemetry counter (quota-efficiency-pass-2026-06, Phase 0).
		-- Only fire when wrapper disabled (when enabled, wrapper's internal counter handles it).
		if (not (Config.HttpApi and Config.HttpApi.ENABLED)) and Config.HttpApi and Config.HttpApi.COUNTERS_ENABLED then
			HttpApiCounter.record("like_getname_total")
		end
		local username = HttpApi.getNameFromUserIdAsync(userId)
		if type(username) == "string" and username ~= "" then
			return username, username
		end
		return "User " .. tostring(userId), "User " .. tostring(userId)
	end

	local function getUserThumbnail(userId: number): string
		-- Prefer rbxthumb to avoid Players thumbnail API storms under leaderboard rebuilds.
		return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
	end

	local function writeUserMetadata(userId: number, username: string, displayName: string, thumbnail: string): Result<nil>
		local sanitizedUsername = sanitizeText(username, 64)
		local sanitizedDisplay = sanitizeText(displayName, 64)
		local sanitizedThumb = sanitizeText(thumbnail, 512)
		local fp = sanitizedUsername .. "\0" .. sanitizedDisplay .. "\0" .. sanitizedThumb
		if lastMetadataFingerprint[userId] == fp then
			return Result.Ok(nil)
		end

		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return Result.withRetry(function()
				metadataStore:UpdateAsync(getUserMetadataStoreKey(userId), function(current: any): any
					if type(current) == "table"
						and current.username == sanitizedUsername
						and current.displayName == sanitizedDisplay
						and current.thumbnail == sanitizedThumb
					then
						return nil -- abort: identity unchanged
					end
					return {
						userId = userId,
						username = sanitizedUsername,
						displayName = sanitizedDisplay,
						thumbnail = sanitizedThumb,
						displayNameVerified = true,
						updatedAt = os.time(),
					}
				end)
				return nil
			end, Config.DataStore.RETRY_ATTEMPTS)
		end, "likes-meta::" .. tostring(userId))
		if not result.ok then
			log:warn("AvatarLikeRepository metadata write failed", {
				targetUserId = userId,
				error = result.error,
			})
			return Result.Err(result.error)
		end
		lastMetadataFingerprint[userId] = fp
		return Result.Ok(nil)
	end

	local function writeLikesLeaderboardScore(userId: number, totalLikes: number): Result<nil>
		local score = math.max(0, math.floor(totalLikes))
		if lastLeaderboardScore[userId] == score then
			return Result.Ok(nil)
		end
		-- OrderedDataStore: SetIncrementSortedAsync budget covers SetAsync calls.
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.SetIncrementSortedAsync, function()
			return Result.withRetry(function()
				leaderboardStore:SetAsync(tostring(userId), score)
				return nil
			end, Config.DataStore.RETRY_ATTEMPTS)
		end, "likes-lb::" .. tostring(userId))
		if not result.ok then
			log:warn("AvatarLikeRepository leaderboard write failed", {
				targetUserId = userId,
				totalLikes = score,
				error = result.error,
			})
			return Result.Err(result.error)
		end
		lastLeaderboardScore[userId] = score
		return Result.Ok(nil)
	end

	local function getShardId(giverUserId: number): number
		return (giverUserId % shardCount) + 1
	end

	local function sanitizeState(value: any): number?
		if value == 0 or value == 1 then
			return value
		end
		return nil
	end

	local function sanitizeShard(raw: any): LikeShardData
		local entries = {} :: {[string]: number}
		local activeCount = 0

		if type(raw) == "table" and type(raw.entries) == "table" then
			for giverKey, state in pairs(raw.entries) do
				if type(giverKey) == "string" then
					local normalizedState = sanitizeState(state)
					if normalizedState ~= nil then
						entries[giverKey] = normalizedState
						if normalizedState == 1 then
							activeCount += 1
						end
					end
				end
			end
		end

		return {
			entries = entries,
			activeCount = activeCount,
			_version = type(raw) == "table" and type(raw._version) == "number" and raw._version or 1,
		}
	end

	local function sanitizeSummary(raw: any): LikeSummaryData
		return {
			totalLikes = type(raw) == "table" and type(raw.totalLikes) == "number" and math.max(0, math.floor(raw.totalLikes)) or 0,
			_version = type(raw) == "table" and type(raw._version) == "number" and raw._version or 1,
		}
	end

	local function cloneEntries(entries: {[string]: number}): {[string]: number}
		local copy = {} :: {[string]: number}
		for giverKey, state in pairs(entries) do
			copy[giverKey] = state
		end
		return copy
	end

	local function applyAction(previousState: number?, action: AvatarContextLikeAction): (number?, number, AvatarLikeTransition)
		if action == "like" then
			if previousState == 1 then
				return 1, 0, "noop"
			end
			if previousState == 0 then
				return 1, 1, "reliked"
			end
			return 1, 1, "first_like"
		end

		if previousState == 1 then
			return 0, -1, "unliked"
		end
		if previousState == 0 then
			return 0, 0, "noop"
		end
		return nil, 0, "noop"
	end

	local function loadShard(targetUserId: number, shardId: number): Result<LikeShardData>
		local cacheKey = getShardCacheKey(targetUserId, shardId)
		local cached = Cache.get(cacheKey)
		if cached then
			return Result.Ok(cached :: LikeShardData)
		end

		local storeKey = getShardStoreKey(targetUserId, shardId)
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
			return Result.withRetry(function()
				return store:GetAsync(storeKey)
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)
		if not result.ok then
			log:warn("AvatarLikeRepository loadShard failed", {
				targetUserId = targetUserId,
				shardId = shardId,
				error = result.error,
			})
			return Result.Err(result.error)
		end

		local shard = sanitizeShard(result.value)
		Cache.set(cacheKey, shard, Config.DataStore.CACHE_TTL)
		return Result.Ok(shard)
	end

	local function writeSummary(targetUserId: number, totalLikes: number): Result<number>
		local storeKey = getSummaryStoreKey(targetUserId)
		local cacheKey = getSummaryCacheKey(targetUserId)

		local savedSummary: LikeSummaryData? = nil
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return Result.withRetry(function()
				return store:UpdateAsync(storeKey, function(oldData: any): any
					local current = sanitizeSummary(oldData)
					savedSummary = {
						totalLikes = math.max(0, totalLikes),
						_version = current._version + 1,
					}
					return savedSummary
				end)
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)

		if not result.ok or not savedSummary then
			local errorMessage = if result.ok then "missing summary" else result.error
			log:warn("AvatarLikeRepository writeSummary failed", {
				targetUserId = targetUserId,
				error = errorMessage,
			})
			return Result.Err(errorMessage)
		end

		Cache.set(cacheKey, savedSummary, Config.DataStore.CACHE_TTL)
		task.spawn(function()
			writeLikesLeaderboardScore(targetUserId, savedSummary.totalLikes)
		end)
		return Result.Ok(savedSummary.totalLikes)
	end

	local function updateSummaryDelta(targetUserId: number, delta: number): Result<number>
		local storeKey = getSummaryStoreKey(targetUserId)
		local cacheKey = getSummaryCacheKey(targetUserId)

		local savedSummary: LikeSummaryData? = nil
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return Result.withRetry(function()
				return store:UpdateAsync(storeKey, function(oldData: any): any
					local current = sanitizeSummary(oldData)
					savedSummary = {
						totalLikes = math.max(0, current.totalLikes + delta),
						_version = current._version + 1,
					}
					return savedSummary
				end)
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)

		if not result.ok or not savedSummary then
			local errorMessage = if result.ok then "missing summary" else result.error
			log:warn("AvatarLikeRepository updateSummaryDelta failed", {
				targetUserId = targetUserId,
				delta = delta,
				error = errorMessage,
			})
			return Result.Err(errorMessage)
		end

		Cache.set(cacheKey, savedSummary, Config.DataStore.CACHE_TTL)
		task.spawn(function()
			writeLikesLeaderboardScore(targetUserId, savedSummary.totalLikes)
		end)
		return Result.Ok(savedSummary.totalLikes)
	end

	function repo:getSummary(targetUserId: number): Result<number>
		local cacheKey = getSummaryCacheKey(targetUserId)
		if Cache.getNegative(cacheKey) then
			return Result.Err("budget_low")
		end
		local cached = Cache.get(cacheKey)
		if cached then
			return Result.Ok((cached :: LikeSummaryData).totalLikes)
		end

		-- In-flight dedup: kalau ada concurrent request untuk userId yang sama,
		-- tunggu hasil dari yang pertama (tanpa double DataStore read).
		if summaryInFlight[targetUserId] then
			-- Poll with a timeout instead of a bare BindableEvent.Event:Wait().
			-- If the in-flight requester's thread is cancelled or errors before
			-- reaching event:Fire(), a bare :Wait() would block this thread
			-- FOREVER, sticking every subsequent getSummary read for this userId
			-- until server restart. The poll exits as soon as the in-flight entry
			-- is cleared (success or failure); the 10s ceiling is a safety net.
			local inFlightEvent = summaryInFlight[targetUserId]
			local waited = 0
			while summaryInFlight[targetUserId] == inFlightEvent and waited < 10 do
				task.wait(0.1)
				waited += 0.1
			end
			local afterWait = Cache.get(cacheKey)
			if afterWait then
				return Result.Ok((afterWait :: LikeSummaryData).totalLikes)
			end
			-- Fallthrough kalau requester pertama gagal atau timeout tercapai.
		end

		-- Register in-flight
		local event = Instance.new("BindableEvent")
		summaryInFlight[targetUserId] = event

		local storeKey = getSummaryStoreKey(targetUserId)
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
			return Result.withRetry(function()
				return store:GetAsync(storeKey)
			end, Config.DataStore.JOIN_READ_RETRY_ATTEMPTS or 1)
		end)

		-- Clear in-flight BEFORE firing (same pattern as HttpApi.luau wrapper)
		summaryInFlight[targetUserId] = nil
		event:Fire()
		event:Destroy()

		if not result.ok then
			log:warn("AvatarLikeRepository getSummary failed", {
				targetUserId = targetUserId,
				error = result.error,
			})
			if result.error == "budget_low" or result.error == "budget_exhausted" then
				Cache.setNegative(cacheKey, Config.Budget.NEGATIVE_CACHE_TTL or 10)
			end
			return Result.Err(result.error)
		end

		if result.value == nil then
			local summary = {
				totalLikes = 0,
				_version = 1,
			}
			Cache.set(cacheKey, summary, Config.DataStore.LIKE_SUMMARY_CACHE_TTL or 300)
			return Result.Ok(0)
		end

		local summary = sanitizeSummary(result.value)
		Cache.set(cacheKey, summary, Config.DataStore.LIKE_SUMMARY_CACHE_TTL or 300)
		return Result.Ok(summary.totalLikes)
	end

	function repo:getViewerState(targetUserId: number, giverUserId: number): Result<number?>
		local shardId = getShardId(giverUserId)
		local result = loadShard(targetUserId, shardId)
		if not result.ok then
			return Result.Err(result.error)
		end

		return Result.Ok(result.value.entries[tostring(giverUserId)])
	end

	function repo:toggle(targetUserId: number, giverUserId: number, action: AvatarContextLikeAction): Result<ToggleResult>
		local shardId = getShardId(giverUserId)
		local storeKey = getShardStoreKey(targetUserId, shardId)
		local cacheKey = getShardCacheKey(targetUserId, shardId)
		local giverKey = tostring(giverUserId)

		local previousState: number? = nil
		local nextState: number? = nil
		local delta = 0
		local transition: AvatarLikeTransition = "noop"
		local updatedShard: LikeShardData? = nil

		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return Result.withRetry(function()
				return store:UpdateAsync(storeKey, function(oldData: any): any
					local current = sanitizeShard(oldData)
					local entries = cloneEntries(current.entries)

					previousState = entries[giverKey]
					nextState, delta, transition = applyAction(previousState, action)

					if nextState == nil then
						entries[giverKey] = nil
					else
						entries[giverKey] = nextState
					end

					updatedShard = {
						entries = entries,
						activeCount = math.max(0, current.activeCount + delta),
						_version = current._version + 1,
					}

					return updatedShard
				end)
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)

		if not result.ok or not updatedShard then
			local errorMessage = if result.ok then "missing shard" else result.error
			log:warn("AvatarLikeRepository toggle failed", {
				targetUserId = targetUserId,
				giverUserId = giverUserId,
				action = action,
				error = errorMessage,
			})
			return Result.Err(errorMessage)
		end

		Cache.set(cacheKey, updatedShard, Config.DataStore.CACHE_TTL)

		local totalLikesResult: Result<number>
		if delta ~= 0 then
			totalLikesResult = updateSummaryDelta(targetUserId, delta)
			if not totalLikesResult.ok then
				totalLikesResult = self:reconcileSummary(targetUserId)
			end
		else
			totalLikesResult = self:getSummary(targetUserId)
		end

		if not totalLikesResult.ok then
			return Result.Err(totalLikesResult.error)
		end

		return Result.Ok({
			previousState = previousState,
			nextState = nextState,
			delta = delta,
			totalLikes = totalLikesResult.value,
			transition = transition,
		})
	end

	function repo:reconcileSummary(targetUserId: number): Result<number>
		local totalLikes = 0

		for shardId = 1, shardCount do
			local shardResult = loadShard(targetUserId, shardId)
			if not shardResult.ok then
				return Result.Err(shardResult.error)
			end
			totalLikes += shardResult.value.activeCount
		end

		local writeResult = writeSummary(targetUserId, totalLikes)
		if not writeResult.ok then
			return Result.Err(writeResult.error)
		end

		return Result.Ok(writeResult.value)
	end

	function repo:invalidateTargetCache(targetUserId: number)
		Cache.invalidate(getSummaryCacheKey(targetUserId))
		for shardId = 1, shardCount do
			Cache.invalidate(getShardCacheKey(targetUserId, shardId))
		end
	end

	function repo:saveTargetMetadata(targetPlayer: Player)
		local thumbnail = getUserThumbnail(targetPlayer.UserId)
		local result = writeUserMetadata(targetPlayer.UserId, targetPlayer.Name, targetPlayer.DisplayName, thumbnail)
		if not result.ok then
			log:warn("AvatarLikeRepository saveTargetMetadata failed", {
				targetUserId = targetPlayer.UserId,
				error = result.error,
			})
		end
	end

	function repo:syncOnlineLeaderboard()
		for _, player in ipairs(Players:GetPlayers()) do
			local summaryResult = self:getSummary(player.UserId)
			if summaryResult.ok then
				local totalLikes = math.max(0, math.floor(summaryResult.value))
				if totalLikes > 0 then
					self:saveTargetMetadata(player)
					local leaderboardResult = writeLikesLeaderboardScore(player.UserId, totalLikes)
					if not leaderboardResult.ok then
						log:warn("AvatarLikeRepository syncOnlineLeaderboard failed", {
							targetUserId = player.UserId,
							error = leaderboardResult.error,
						})
					end
				end
			end
		end
	end

	function repo:backfillLeaderboardFromSummaries()
		local now = os.clock()
		if now - lastBackfillAt < Config.Leaderboards.LIKES_BACKFILL_COOLDOWN then
			return
		end
		lastBackfillAt = now

		local maxKeys = math.max(1, math.floor(Config.Leaderboards.LIKES_BACKFILL_MAX_KEYS))
		local scanned = 0
		local backfilled = 0
		-- Throttle: backfill issues 3 DataStore ops per entry (Get summary, Update
		-- metadata, Set leaderboard). Without per-iteration pacing the queue warns
		-- even with BudgetGate. 0.1s/iter caps the burst at ~30 ops/sec, well under
		-- per-server quota at 70 CCU.
		local BACKFILL_ITER_DELAY = 0.15
		-- Gate ListKeysAsync through scheduler (uses GetAsync budget as proxy — no dedicated enum).
		local listResult = budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
			return store:ListKeysAsync("likes:summary:", 100)
		end, "likes-backfill-list")
		if not listResult.ok then
			log:warn("AvatarLikeRepository likes backfill could not list keys", {
				error = tostring(listResult.error),
			})
			return
		end

		local pages = listResult.value
		while true do
			for _, keyInfo in ipairs(pages:GetCurrentPage()) do
				if scanned >= maxKeys then
					break
				end
				scanned += 1

				local keyName = if type(keyInfo) == "string" then keyInfo else keyInfo.KeyName
				local userId = type(keyName) == "string" and parseSummaryUserId(keyName) or nil
				if userId then
					local summaryResult = budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
						return Result.withRetry(function()
							return store:GetAsync(keyName)
						end, Config.DataStore.RETRY_ATTEMPTS)
					end)
					if summaryResult.ok then
						local summary = sanitizeSummary(summaryResult.value)
						if summary.totalLikes > 0 then
							local username, displayName = getUserIdentity(userId)
							local thumbnail = getUserThumbnail(userId)
							writeUserMetadata(userId, username, displayName, thumbnail)
							local leaderboardResult = writeLikesLeaderboardScore(userId, summary.totalLikes)
							if leaderboardResult.ok then
								backfilled += 1
							end
						end
					end
					-- Pace the loop so 21+ entries do not burst-fire 60+ DataStore
					-- ops in a single second.
					task.wait(BACKFILL_ITER_DELAY)
				end
			end

			if scanned >= maxKeys or pages.IsFinished then
				break
			end

			local advanceOk, advanceErr = pcall(function()
				pages:AdvanceToNextPageAsync()
			end)
			if not advanceOk then
				log:warn("AvatarLikeRepository likes backfill page advance failed", {
					error = tostring(advanceErr),
				})
				break
			end
		end

		log:info("AvatarLikeRepository likes backfill completed", {
			scanned = scanned,
			backfilled = backfilled,
		})
	end

	function repo:getTopLeaderboard(limit: number, forceRefresh: boolean?): Result<{ any }>
		local resolvedLimit = math.clamp(math.floor(limit), 1, Config.Leaderboards.MAX_LIMIT)

		-- Cache hit: skip sync + backfill + GetSortedAsync entirely.
		local cached = likesLeaderboardCache[resolvedLimit]
		if not forceRefresh and cached and os.clock() <= cached.exp then
			return Result.Ok(cached.value)
		end

		-- Full sync/backfill is expensive (hundreds of DataStore ops). Only run it when
		-- explicitly forced; normal reads rely on the cached leaderboard + background
		-- backfill. Individual like actions already update the leaderboard immediately.
		if forceRefresh then
			self:syncOnlineLeaderboard()
			self:backfillLeaderboardFromSummaries()
		end

		local sortedResult = budgetGate:executeAsync(Enum.DataStoreRequestType.GetSortedAsync, function()
			return Result.withRetry(function()
				return leaderboardStore:GetSortedAsync(false, resolvedLimit)
			end, Config.DataStore.LB_READ_RETRY_ATTEMPTS or 1)
		end)
		if not sortedResult.ok then
			return Result.Err(sortedResult.error)
		end

		-- Cap metadata GetAsync per call (same spirit as DonationLeaderboardRepository
		-- METADATA_READ_LIMIT). Ranks beyond the cap use Players API identity fallback
		-- so a likes board of 50 does not burn 50 Standard Reads on every cold build.
		local METADATA_READ_LIMIT = 20
		local page = sortedResult.value:GetCurrentPage()
		local entries = {}
		for index, item in ipairs(page) do
			local userId = tonumber(item.key) or 0
			local metadata: any = nil
			if index <= METADATA_READ_LIMIT then
				local metadataResult = budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
					return Result.withRetry(function()
						return metadataStore:GetAsync(getUserMetadataStoreKey(userId))
					end, Config.DataStore.RETRY_ATTEMPTS)
				end)
				if metadataResult.ok and type(metadataResult.value) == "table" then
					metadata = metadataResult.value
				end
			end

			local function looksLikeFallback(name: string?): boolean
				if not name then
					return true
				end
				return name:match("^User%s*%d+$") ~= nil or name == ""
			end
			local username = type(metadata) == "table" and type(metadata.username) == "string" and metadata.username
				or nil
			local displayName = type(metadata) == "table" and type(metadata.displayName) == "string" and metadata.displayName
				or nil
			-- Only hit identity API when metadata is missing / fallback — not every row.
			if looksLikeFallback(username) or looksLikeFallback(displayName) then
				local fallbackUsername, fallbackDisplayName = getUserIdentity(userId)
				if looksLikeFallback(username) then
					username = fallbackUsername
				end
				if looksLikeFallback(displayName) then
					displayName = fallbackDisplayName
				end
				-- Note: metadata write-back intentionally omitted from hot read path.
				-- Writing 10+ entries simultaneously floods DataStore queue in Studio.
				-- Metadata self-heals during backfillLeaderboardFromSummaries (throttled).
			end
			if not username then
				username = "User " .. tostring(userId)
			end
			if not displayName then
				displayName = username
			end
			local thumbnail = type(metadata) == "table" and type(metadata.thumbnail) == "string" and metadata.thumbnail
				or nil
			if not thumbnail or thumbnail == "" then
				thumbnail = getUserThumbnail(userId)
			end
			local displayNameVerified = type(metadata) == "table" and metadata.displayNameVerified == true
			table.insert(entries, {
				rank = index,
				userId = userId,
				username = username,
				displayName = displayName,
				thumbnail = thumbnail,
				displayNameVerified = displayNameVerified,
				total = tonumber(item.value) or 0,
			})
		end

		likesLeaderboardCache[resolvedLimit] = {
			value = entries,
			exp = os.clock() + LIKES_LEADERBOARD_CACHE_TTL,
		}
		return Result.Ok(entries)
	end

	return repo
end

return {
	new = createAvatarLikeRepository,
}
