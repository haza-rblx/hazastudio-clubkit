--!strict
-- Server/Services/OverheadService.lua
-- Business logic: ambil Group rank + DataStore, merge, build payload.
-- Zero DataStore access langsung, hanya lewat repo.
-- Zero UI logic.
local GroupService = game:GetService("GroupService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
-- Gunakan ReplicatedStorage local variable, bukan game.ReplicatedStorage
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Secrets = require(ServerScriptService.Hazastudio_ClubKitSecrets.Secrets)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local RobloxPlatformIcons = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RobloxPlatformIcons)
local ResultUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Cache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cache)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local HttpApiCounter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApiCounter)
local HttpApi = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApi)
type Result<T> = Types.Result<T>
type CommunityData = Types.CommunityData
type CommunityLookupResult = Types.CommunityLookupResult
type OverheadPayload = Types.OverheadPayload
type OverheadStoredData = Types.OverheadStoredData
type AboutRosterEntry = Types.AboutRosterEntry
type IOverheadRepository = Types.IOverheadRepository
type RoleKey = Types.RoleKey
type MembershipTier = Types.MembershipTier
export type BroadcastSenderContext = {
	role: RoleKey,
	effectiveMembership: MembershipTier,
}
type RobloxGroupEntry = {
	Id: number,
	Name: string?,
	Rank: number,
	EmblemUrl: string?,
	IsPrimary: boolean?,
}
local GROUP_RANK_PREFIX = "grouprank:"
local GROUPS_PREFIX = "groups:"
local ROBUX_TOP_DONATE_PREFIX = "robux-top-donate:"
local SAWERIA_TOP_SPENDER_PREFIX = "saweria-top-spender:"
local WORKER_RANK_PREFIX = "worker-rank:"

-- Worker-based rank resolution (primary source, replaces GroupService)
local function fetchRankFromWorker(userId: number): number?
	local apiCfg = Config.GameDataApi
	if not apiCfg or apiCfg.GROUPS_ENDPOINT_ENABLED ~= true then
		return nil
	end
	local baseUrl = apiCfg.BASE_URL
	local gameKey = apiCfg.GAME_KEY
	if not baseUrl or baseUrl == "" or not gameKey or gameKey == "" then
		return nil
	end
	local secret = Secrets.GameDataApiSecret
	if type(secret) ~= "string" or secret == "" then
		return nil
	end

	-- Check short-lived in-memory cache to avoid spamming worker
	local workerCacheKey = WORKER_RANK_PREFIX .. userId
	local cached = Cache.get(workerCacheKey)
	if cached then
		return cached :: number
	end

	local url = baseUrl .. "/game/" .. gameKey .. "/groups/" .. tostring(userId) .. "?secret=" .. secret
	local ok, result = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "GET",
			Headers = { ["Accept"] = "application/json" },
		})
	end)

	if not ok or not result or not result.Success then
		return nil
	end

	local decodeOk, data = pcall(function()
		return HttpService:JSONDecode(result.Body)
	end)
	if not decodeOk or type(data) ~= "table" or data.ok ~= true then
		return nil
	end

	local rankId = tonumber(data.rankId)
	if rankId then
		-- Cache worker result in-memory (shorter TTL than KV cache to stay fresh)
		Cache.set(workerCacheKey, rankId, 30)
	end
	return rankId
end
-- ============================================================
-- Factory: dependencies diinject, tidak hardcode
-- ============================================================
local function createOverheadService(deps: {
	repo: IOverheadRepository,
	avatarLikeRepository: any?,
	profileRepository: any?,
	profileCommandService: any?,
	aboutRosterRepository: Types.IAboutRosterRepository?,
	donationLeaderboardRepository: any?,
	donationService: any?,
})
	local repo = deps.repo
	local avatarLikeRepository = deps.avatarLikeRepository
	local profileRepository = deps.profileRepository
	local profileCommandService = deps.profileCommandService
	local aboutRosterRepository = deps.aboutRosterRepository
	local donationLeaderboardRepository = deps.donationLeaderboardRepository
	local donationService = deps.donationService
	local log = Logger.new("OverheadService")
	local service = {} :: Types.IOverheadService

	-- Cash donated cache: moved out of the synchronous buildPayload path.
	-- getPlayerCashStats can hit HTTP / workspace leaderboard enrichment and
	-- regularly exceeded the client loading-screen deadline. We keep a fast
	-- in-memory cache and fill it asynchronously; the initial payload uses 0
	-- (or the last known value) and a delta update is sent when the fetch lands.
	local cashDonatedCache: { [number]: number } = {}
	local cashStatsReadyCallback: ((userId: number) -> ())?
	local rankResolutionScheduled: { [number]: boolean } = {}

	function service:setDonationService(donationSvc: any)
		donationService = donationSvc
		log:info("DonationService wired into OverheadService")
	end

	function service:setCashStatsReadyCallback(callback: ((userId: number) -> ())?)
		cashStatsReadyCallback = callback
	end

	function service:setCashDonated(userId: number, amount: number?)
		if type(userId) ~= "number" or userId <= 0 then
			return
		end
		if amount == nil then
			cashDonatedCache[userId] = nil
			return
		end
		cashDonatedCache[userId] = math.max(0, math.floor(tonumber(amount) or 0))
	end

	local function scheduleCashStatsFetch(userId: number, username: string)
		if cashDonatedCache[userId] ~= nil then
			return
		end
		if not donationService or type(donationService.getPlayerCashStats) ~= "function" then
			return
		end
		-- Delay the fetch so it always lands AFTER the initial full overhead
		-- Snapshot/delta has been broadcast. Otherwise the cash delta could race
		-- with the join-time payload and the client might end up with cash=0.
		task.delay(1.5, function()
			if cashDonatedCache[userId] ~= nil then
				return
			end
			local ok, cashTotal = pcall(function()
				return donationService:getPlayerCashStats(userId, username)
			end)
			if ok and type(cashTotal) == "number" then
				local newAmount = math.max(0, math.floor(cashTotal))
				if cashDonatedCache[userId] ~= newAmount then
					cashDonatedCache[userId] = newAmount
					if cashStatsReadyCallback then
						cashStatsReadyCallback(userId)
					end
				end
			end
		end)
	end

	-- In-flight guard: cegah duplicate concurrent GroupService calls untuk userId yang sama.
	local inFlight: { [number]: boolean } = {}
	local function getGroups(userId: number): ({ RobloxGroupEntry }?, boolean)
		local cacheKey = GROUPS_PREFIX .. userId
		local cached = Cache.get(cacheKey)
		if cached then
			return cached :: { RobloxGroupEntry }, true
		end
		if inFlight[userId] then
			local waited = 0
			while inFlight[userId] and waited < Config.Overhead.INFLIGHT_WAIT_MAX do
				task.wait(0.1)
				waited += 0.1
			end
			local fresh = Cache.get(cacheKey)
			if fresh then
				return fresh :: { RobloxGroupEntry }, true
			end
			-- If the in-flight caller finished but cache is empty (fetch failed),
			-- fall through to retry ourselves. Only return empty if another caller
			-- is still fetching.
			if inFlight[userId] then
				log:debug("GroupService in-flight still running, return empty", { userId = userId })
				return nil, false
			end
			-- Fall through to retry
		end
		inFlight[userId] = true
		-- HTTP API telemetry counter (quota-efficiency-pass-2026-06, Phase 0).
		-- Only fire when wrapper disabled (when enabled, wrapper's internal counter handles it).
		if (not (Config.HttpApi and Config.HttpApi.ENABLED)) and Config.HttpApi and Config.HttpApi.COUNTERS_ENABLED then
			HttpApiCounter.record("overhead_getgroups_total")
		end
		local groupsResult = HttpApi.getGroupsAsync(userId)
		inFlight[userId] = nil
		if not groupsResult then
			log:warn("GroupService gagal, groups tidak di-cache", { userId = userId })
			return nil, false
		end
		-- Self-cache even when Config.HttpApi.ENABLED=false (HttpApi only writes
		-- this key when ENABLED). Keep key in sync with HttpApi.getGroupsAsync.
		local groupsTtl = (Config.HttpApi and Config.HttpApi.GET_GROUPS_TTL) or 300
		Cache.set(cacheKey, groupsResult, groupsTtl)
		return groupsResult, true
	end
	local function getGroupRank(userId: number): number
		local rankCacheKey = GROUP_RANK_PREFIX .. userId
		local cachedRank = Cache.get(rankCacheKey)
		if cachedRank then
			return cachedRank :: number
		end

		-- PRIMARY: Try Worker endpoint (Open Cloud API, dedicated rate limit)
		local workerRank = fetchRankFromWorker(userId)
		if workerRank then
			Cache.set(rankCacheKey, workerRank, Config.Group.RANK_CACHE_TTL)
			return workerRank
		end

		-- FALLBACK: GroupService direct (unreliable at high CCU)
		local rankId = 0
		local groups = select(1, getGroups(userId)) or {}
		for _, groupInfo in ipairs(groups) do
			if groupInfo.Id == Config.Group.GROUP_ID then
				rankId = groupInfo.Rank
				break
			end
		end
		-- LKG fallback: if GroupService returned nothing useful, use last known rank
		if rankId == 0 and #groups == 0 then
			local player = Players:GetPlayerByUserId(userId)
			if player then
				local lkgRank = player:GetAttribute("_LKG_RankId")
				if type(lkgRank) == "number" and lkgRank > 0 then
					log:debug("GroupService empty, using LKG rank", { userId = userId, lkgRank = lkgRank })
					return lkgRank
				end
			end
		end
		Cache.set(rankCacheKey, rankId, Config.Group.RANK_CACHE_TTL)
		return rankId
	end
	local function isHiddenDonationUser(userId: number): boolean
		local hiddenUserIds = Config.Leaderboards.HIDDEN_ROBUX_USER_IDS
		return type(hiddenUserIds) == "table" and hiddenUserIds[userId] == true
	end

	-- Forward declarations: scheduleRankResolution (defined below) calls these,
	-- but their `local function` definitions live further down. Without these
	-- forward declarations the earlier closure captures a nil global and throws
	-- "attempt to call a nil value" at runtime.
	-- Returns (rank?, lookupOk). lookupOk=false → transient failure; do not clear stored rank.
	local _resolveRobuxTopDonateRank: (userId: number, playerName: string?) -> (number?, boolean)
	local _resolveSaweriaTopSpenderRank: (userId: number, playerName: string?) -> (number?, boolean)
	-- Confirmed "no rank" negative cache — short TTL so post-donate retries aren't stuck on `#-`.
	local NEGATIVE_RANK_CACHE_TTL = 5

	-- Async rank resolution: we used to call these on the join-time critical path,
	-- but getRobuxLeaderboard / getWorkspaceSaweriaLeaderboard can hit DataStore or
	-- HTTP and blow the payload deadline. We resolve them after the initial broadcast.
	local function updateStoredRanksIfChanged(
		userId: number,
		robuxRank: number?,
		robuxLookupOk: boolean,
		saweriaRank: number?,
		saweriaLookupOk: boolean
	)
		if isHiddenDonationUser(userId) then
			return
		end
		local storedResult = repo:load(userId)
		if not storedResult.ok then
			return
		end
		local current = storedResult.value
		local merge: { [string]: any } = {}
		local activeRobuxRank = OverheadDomain.normalizeLeaderboardRank(robuxRank)
		if activeRobuxRank then
			if current.topDonateRank ~= activeRobuxRank then
				merge.topDonateRank = activeRobuxRank
				merge.topDonateText = "#" .. tostring(activeRobuxRank) .. " DONATION"
			end
		elseif current.topDonateRank ~= nil or current.topDonateText ~= nil then
			-- Clear only on confirmed miss / outside board, or confirmed total ≤ 0.
			-- Transient lookup failure must not wipe a known good rank (panel `#-` flicker).
			local shouldClearRobux = robuxLookupOk
			if not shouldClearRobux
				and donationLeaderboardRepository
				and type(donationLeaderboardRepository.getPlayerRobuxTotal) == "function"
			then
				local totalResult = donationLeaderboardRepository:getPlayerRobuxTotal(userId)
				if totalResult.ok and math.max(0, math.floor(tonumber(totalResult.value) or 0)) <= 0 then
					shouldClearRobux = true
				end
			end
			if shouldClearRobux then
				merge.topDonateRank = OverheadDomain.NIL
				merge.topDonateText = OverheadDomain.NIL
			end
		end
		local activeSaweriaRank = OverheadDomain.normalizeLeaderboardRank(saweriaRank)
		if activeSaweriaRank then
			if current.topSpenderRank ~= activeSaweriaRank then
				merge.topSpenderRank = activeSaweriaRank
				if Config.Donation.SHOW_LEGACY_TOP_SPENDER_ROW == true then
					merge.topSpenderText = Config.Donation.TOP_SPENDER_TEXTS[activeSaweriaRank]
						or ("#" .. tostring(activeSaweriaRank) .. " INVESTOR")
				else
					merge.topSpenderText = OverheadDomain.NIL
				end
			end
		elseif current.topSpenderRank ~= nil or current.topSpenderText ~= nil then
			if saweriaLookupOk then
				merge.topSpenderRank = OverheadDomain.NIL
				merge.topSpenderText = OverheadDomain.NIL
			end
		end
		if next(merge) == nil then
			return
		end
		local updateResult = repo:update(userId, function(currentData)
			return OverheadDomain.mergeStored(currentData, merge)
		end)
		if updateResult.ok and cashStatsReadyCallback then
			cashStatsReadyCallback(userId)
		end
	end

	local function scheduleRankResolution(userId: number, username: string)
		if isHiddenDonationUser(userId) then
			return
		end
		if rankResolutionScheduled[userId] then
			return
		end
		rankResolutionScheduled[userId] = true
		task.delay(2, function()
			-- Always clear the scheduling flag when this task finishes so a
			-- later scheduleRankResolution can run again. Previously the flag
			-- was set to true and never reset, so (a) rank resolution could
			-- never re-run for this user and (b) the per-UserId entry leaked
			-- for the entire server lifetime.
			local function finish()
				rankResolutionScheduled[userId] = nil
			end
			if isHiddenDonationUser(userId) then
				finish()
				return
			end
			local robuxRank: number? = nil
			local robuxLookupOk = false
			local saweriaRank: number? = nil
			local saweriaLookupOk = false
			local ok, err = pcall(function()
				robuxRank, robuxLookupOk = _resolveRobuxTopDonateRank(userId, username)
				saweriaRank, saweriaLookupOk = _resolveSaweriaTopSpenderRank(userId, username)
			end)
			if not ok then
				log:debug("Async rank resolution failed", { userId = userId, error = tostring(err) })
				finish()
				return
			end
			updateStoredRanksIfChanged(userId, robuxRank, robuxLookupOk, saweriaRank, saweriaLookupOk)
			finish()
		end)
	end

	function _resolveRobuxTopDonateRank(userId: number, playerName: string?): (number?, boolean)
		if isHiddenDonationUser(userId) then
			return nil, true
		end

		if
			not donationLeaderboardRepository
			or type(donationLeaderboardRepository.getRobuxLeaderboard) ~= "function"
		then
			return nil, false
		end

		local cacheKey = ROBUX_TOP_DONATE_PREFIX .. tostring(userId)
		local cached = Cache.get(cacheKey)
		if cached ~= nil then
			if cached == false then
				return nil, true
			end
			return OverheadDomain.normalizeLeaderboardRank(cached), true
		end

		local result = donationLeaderboardRepository:getRobuxLeaderboard(Config.Leaderboards.ROBUX_LIMIT)
		if not result.ok or type(result.value) ~= "table" then
			log:warn("Robux top donate rank lookup failed", {
				userId = userId,
				error = result.error,
			})
			-- Do not negative-cache failures — keep last known rank until a confirmed miss.
			return nil, false
		end

		-- Match userId dulu, fallback ke username biar konsisten dengan DonationService.assignPlayer
		-- yang match by username. Tanpa fallback ini, rank bisa hilang kalau metadata.username
		-- belum sync atau entry.userId belum di-resolve dengan benar.
		local lowerName = (type(playerName) == "string" and playerName ~= "") and playerName:lower() or nil
		local resolvedRank: number? = nil
		for rank, entry in ipairs(result.value) do
			local entryUserId = tonumber(entry.userId)
			if entryUserId and entryUserId == userId then
				resolvedRank = rank
				break
			end
			if lowerName then
				local entryUsername = type(entry.username) == "string" and entry.username or nil
				if entryUsername and entryUsername:lower() == lowerName then
					resolvedRank = rank
					break
				end
			end
		end

		local normalizedRank = OverheadDomain.normalizeLeaderboardRank(resolvedRank)
		if normalizedRank then
			Cache.set(cacheKey, normalizedRank, Config.Leaderboards.WORKSPACE_CACHE_TTL)
		else
			Cache.set(cacheKey, false, NEGATIVE_RANK_CACHE_TTL)
		end
		return normalizedRank, true
	end
	local function getManualTopSpenderRank(userId: number): number?
		local overrides = Config.TopSpenders
		if type(overrides) == "table" then
			local manualRank = overrides[userId]
			if type(manualRank) == "number" then
				return OverheadDomain.normalizeLeaderboardRank(manualRank)
			end
		end
		return nil
	end
	function _resolveSaweriaTopSpenderRank(userId: number, playerName: string?): (number?, boolean)
		if isHiddenDonationUser(userId) then
			return nil, true
		end
		local manualRank = getManualTopSpenderRank(userId)
		if manualRank then
			return manualRank, true
		end

		if not donationService or type(donationService.getWorkspaceSaweriaLeaderboard) ~= "function" then
			return nil, false
		end

		local cacheKey = SAWERIA_TOP_SPENDER_PREFIX .. tostring(userId)
		local cached = Cache.get(cacheKey)
		if cached ~= nil then
			if cached == false then
				return nil, true
			end
			return OverheadDomain.normalizeLeaderboardRank(cached), true
		end

		local ok, entriesOrErr = pcall(function()
			return donationService:getWorkspaceSaweriaLeaderboard(Config.Leaderboards.SAWERIA_LIMIT)
		end)
		if not ok or type(entriesOrErr) ~= "table" then
			log:warn("Bagibagi top spender rank lookup failed", {
				userId = userId,
				error = tostring(entriesOrErr),
			})
			return nil, false
		end

		-- Match userId dulu, fallback ke username. Saweria leaderboard sering punya entry
		-- dengan userId=0 kalau resolveRobloxUserId gagal/throttled, jadi tanpa fallback
		-- username, player rank #2-#10 yang baru join bisa nggak ke-detect.
		local lowerName = (type(playerName) == "string" and playerName ~= "") and playerName:lower() or nil
		local resolvedRank: number? = nil
		for index, entry in ipairs(entriesOrErr) do
			local entryUserId = tonumber(entry.userId)
			if entryUserId and entryUserId == userId then
				resolvedRank = tonumber(entry.rank) or index
				break
			end
			if lowerName then
				local entryUsername = type(entry.username) == "string" and entry.username or nil
				if entryUsername and entryUsername:lower() == lowerName then
					resolvedRank = tonumber(entry.rank) or index
					break
				end
			end
		end

		local normalizedRank = OverheadDomain.normalizeLeaderboardRank(resolvedRank)
		if normalizedRank then
			Cache.set(cacheKey, normalizedRank, Config.Leaderboards.WORKSPACE_CACHE_TTL)
		else
			Cache.set(cacheKey, false, NEGATIVE_RANK_CACHE_TTL)
		end
		return normalizedRank, true
	end
	local function resolveCommunityFromGroups(groups: { RobloxGroupEntry }, communityId: number): CommunityData?
		for _, groupInfo in ipairs(groups) do
			if groupInfo.Id == communityId then
				local logo = groupInfo.EmblemUrl
				if type(logo) ~= "string" or logo == "" then
					logo = ("rbxthumb://type=GroupIcon&id=%d&w=150&h=150"):format(communityId)
				end
				return {
					id = communityId,
					name = groupInfo.Name,
					logo = logo,
				}
			end
		end
		return nil
	end
	local function isPrimaryGroupEntry(groupInfo: RobloxGroupEntry): boolean
		if groupInfo.IsPrimary == true then
			return true
		end
		local legacy = groupInfo :: any
		return legacy.Primary == true or legacy.IsPrimaryGroup == true
	end
	local function resolvePrimaryCommunityFromGroups(groups: { RobloxGroupEntry }): CommunityData?
		for _, groupInfo in ipairs(groups) do
			if isPrimaryGroupEntry(groupInfo) then
				return resolveCommunityFromGroups(groups, groupInfo.Id)
			end
		end
		return nil
	end
	local function resolveEffectiveCommunityData(
		stored: OverheadStoredData,
		groups: { RobloxGroupEntry }
	): CommunityData?
		if stored.communityId then
			return resolveCommunityFromGroups(groups, stored.communityId)
		end
		if stored.suppressCommunityBadge == true or Config.Community.PRIMARY_FALLBACK_ENABLED ~= true then
			return nil
		end
		return resolvePrimaryCommunityFromGroups(groups)
	end
	local function normalizeCommunityQuery(query: string): string
		local lowered = string.lower(query)
		local trimmed = lowered:match("^%s*(.-)%s*$") or ""
		return trimmed
	end
	local function getCommunityCandidatesFromGroups(groups: { RobloxGroupEntry }, query: string): { CommunityData }
		local normalizedQuery = normalizeCommunityQuery(query)
		local exactMatches = {} :: { CommunityData }
		local partialMatches = {} :: { CommunityData }
		if normalizedQuery == "" then
			return partialMatches
		end
		for _, groupInfo in ipairs(groups) do
			local groupName = type(groupInfo.Name) == "string" and groupInfo.Name or tostring(groupInfo.Id)
			local normalizedName = normalizeCommunityQuery(groupName)
			local data = resolveCommunityFromGroups({ groupInfo }, groupInfo.Id)
			if data then
				if normalizedName == normalizedQuery then
					table.insert(exactMatches, data)
				elseif string.find(normalizedName, normalizedQuery, 1, true) then
					table.insert(partialMatches, data)
				end
			end
		end
		if #exactMatches > 0 then
			return exactMatches
		end
		return partialMatches
	end
	-- ----------------------------------------------------------
	-- buildPayload: fungsi utama, dipanggil saat player join
	-- dan saat data di-refresh
	-- ----------------------------------------------------------
	function service:buildPayloadWithMeta(player: Player): { result: Result<OverheadPayload>, usedFallback: boolean }
		local userId = player.UserId
		-- Phase 1: Load stored data (required before donation rank logic).
		local storedResult = repo:load(userId)
		local usedFallback = false
		local stored: OverheadStoredData
		if storedResult.ok then
			stored = storedResult.value
		else
			log:warn("Load gagal, pakai default data untuk broadcast", { userId = userId, err = storedResult.error })
			stored = OverheadDomain.defaultStoredData()
			usedFallback = true
		end
		stored = OverheadDomain.applyHardcoded(stored, userId)

		-- Phase 2: Parallel fetch — spawn independent async lookups concurrently.
		-- Results collected into locals; counter tracks completion.
		local groups: { RobloxGroupEntry } = {}
		local rankId: number = 0
		local resolvedDisplayName: string = player.DisplayName
		local relationshipMode: Types.ProfileRelationshipMode? = nil
		local statusText: string? = nil
		local likesCount: number = 0
		local robuxDonated: number = 0
		-- Hidden users never show cash/robux donation totals in the overhead.
		local cashDonated: number = if isHiddenDonationUser(userId) then 0 else (cashDonatedCache[userId] or 0)
		local robuxTopDonateRank: number? = nil
		local saweriaTopSpenderRank: number? = nil

		local remaining = 0
		local doneEvent = Instance.new("BindableEvent")

		local function spawnTask(fn: () -> ())
			remaining += 1
			task.spawn(function()
				fn()
				remaining -= 1
				if remaining == 0 then
					doneEvent:Fire()
				end
			end)
		end

		-- Task A: Groups + rank
		spawnTask(function()
			groups = select(1, getGroups(userId)) or {}
			rankId = getGroupRank(userId)
		end)

		-- Task B: Profile
		if profileRepository and type(profileRepository.load) == "function" then
			spawnTask(function()
				local profileResult = profileRepository:load(userId)
				if profileResult.ok then
					if
						type(profileResult.value.displayNameOverride) == "string"
						and profileResult.value.displayNameOverride ~= ""
					then
						resolvedDisplayName = profileResult.value.displayNameOverride
					end
					relationshipMode = profileResult.value.relationshipMode
					statusText = profileResult.value.statusText
				else
					log:warn("Profile display name lookup failed", {
						userId = userId,
						error = profileResult.error,
					})
				end
			end)
		end

		-- Task C: Likes
		if avatarLikeRepository and type(avatarLikeRepository.getSummary) == "function" then
			spawnTask(function()
				local likesResult = avatarLikeRepository:getSummary(userId)
				if likesResult.ok then
					likesCount = likesResult.value
				else
					log:warn("Like summary lookup failed", {
						userId = userId,
						error = likesResult.error,
					})
				end
			end)
		end

		-- Task D: Robux donated total
		spawnTask(function()
			if
				isHiddenDonationUser(userId)
				and donationService
				and type(donationService.getSessionRobuxTotal) == "function"
			then
				robuxDonated = donationService:getSessionRobuxTotal(userId)
			elseif
				donationLeaderboardRepository
				and type(donationLeaderboardRepository.getPlayerRobuxTotal) == "function"
			then
				local robuxResult = donationLeaderboardRepository:getPlayerRobuxTotal(userId)
				if robuxResult.ok then
					robuxDonated = robuxResult.value
				end
			end
		end)

		-- Task E: Donation ranks + cash — FAST PATH.
		-- We only read the cached/stored values here. Live resolution of
		-- robux/saweria ranks and cashDonated is moved to async tasks that run
		-- AFTER the initial overhead payload is broadcast. This prevents slow
		-- DataStore/HTTP calls from blowing the join-time and ACM deadlines.
		if not isHiddenDonationUser(userId) then
			spawnTask(function()
				robuxTopDonateRank = tonumber(stored.topDonateRank)
				saweriaTopSpenderRank = tonumber(stored.topSpenderRank)
				-- Fill cash cache asynchronously if we don't have a value yet.
				if cashDonatedCache[userId] == nil then
					scheduleCashStatsFetch(userId, player.Name)
				end
				-- Resolve live ranks asynchronously (non-blocking).
				scheduleRankResolution(userId, player.Name)
			end)
		end

		-- Wait for all parallel tasks to complete (with safety timeout)
		if remaining > 0 then
			local waited = 0
			-- 10s timeout: safety net untuk GroupService fetch + profile/likes/robux total.
			while remaining > 0 and waited < 10 do
				doneEvent.Event:Wait()
				waited += 1
			end
			if remaining > 0 then
				log:warn("buildPayload parallel tasks timed out", { userId = userId, remaining = remaining })
			end
		end
		doneEvent:Destroy()

		-- Phase 3: Post-process status text override
		if profileCommandService and type(profileCommandService.getStatus) == "function" then
			statusText = profileCommandService:getStatus(userId) or statusText
		end

		-- Phase 4: Merge donation rank data into stored
		if isHiddenDonationUser(userId) then
			stored = OverheadDomain.mergeStored(stored, {
				topDonateRank = OverheadDomain.NIL,
				topDonateText = OverheadDomain.NIL,
				topSpenderRank = OverheadDomain.NIL,
				topSpenderText = OverheadDomain.NIL,
			})
		else
			-- Rank chips must track live totals: 0 donated ⇒ no rank (don't keep stale DS ranks).
			if robuxDonated <= 0 then
				robuxTopDonateRank = nil
			end
			if cashDonated <= 0 then
				saweriaTopSpenderRank = nil
			end
			local activeRobuxRank = OverheadDomain.normalizeLeaderboardRank(robuxTopDonateRank)
			if activeRobuxRank then
				stored = OverheadDomain.mergeStored(stored, {
					topDonateRank = activeRobuxRank,
					topDonateText = "#" .. tostring(activeRobuxRank) .. " DONATION",
				})
			else
				stored = OverheadDomain.mergeStored(stored, {
					topDonateRank = OverheadDomain.NIL,
					topDonateText = OverheadDomain.NIL,
				})
			end
			local activeSaweriaRank = OverheadDomain.normalizeLeaderboardRank(saweriaTopSpenderRank)
			if activeSaweriaRank then
				local saweriaMerge: { [string]: any } = { topSpenderRank = activeSaweriaRank }
				if Config.Donation.SHOW_LEGACY_TOP_SPENDER_ROW == true then
					saweriaMerge.topSpenderText = stored.topSpenderText
						or Config.Donation.TOP_SPENDER_TEXTS[activeSaweriaRank]
						or ("#" .. tostring(activeSaweriaRank) .. " INVESTOR")
				else
					saweriaMerge.topSpenderText = OverheadDomain.NIL
				end
				stored = OverheadDomain.mergeStored(stored, saweriaMerge)
			else
				stored = OverheadDomain.mergeStored(stored, {
					topSpenderRank = OverheadDomain.NIL,
					topSpenderText = OverheadDomain.NIL,
				})
			end
		end

		-- Phase 5: Community resolution (depends on groups result)
		local communityData = resolveEffectiveCommunityData(stored, groups)
		local payload = OverheadDomain.buildPayload(
			userId,
			resolvedDisplayName,
			rankId,
			stored,
			communityData,
			likesCount,
			robuxDonated,
			cashDonated,
			relationshipMode,
			statusText,
			RobloxPlatformIcons.playerHasPaidRobloxSubscription(player)
		)
		log:debug("Payload built", { userId = userId, role = payload.role })

		-- LKG (Last Known Good): Store successful role resolution as player attribute.
		-- Downstream systems use this to reject stale "Guest" payloads.
		local targetPlayer = Players:GetPlayerByUserId(userId)
		if targetPlayer and payload.role and payload.role ~= "Guest" and payload.role ~= "" then
			targetPlayer:SetAttribute("_LKG_Role", payload.role)
			targetPlayer:SetAttribute("_LKG_RankId", rankId)
		end

		return { result = ResultUtil.Ok(payload), usedFallback = usedFallback }
	end
	function service:buildPayload(player: Player): Result<OverheadPayload>
		return self:buildPayloadWithMeta(player).result
	end
	function service:getStored(userId: number): Result<OverheadStoredData>
		return repo:load(userId)
	end
	function service:getRawGroupRole(player: Player): RoleKey
		local rankId = getGroupRank(player.UserId)
		return OverheadDomain.resolveRole(rankId, player.UserId)
	end
	function service:getEffectivePayload(player: Player): Result<OverheadPayload>
		return service:buildPayload(player)
	end

	-- Ringan untuk /announce & broadcast: tanpa leaderboard/profile/like lookup.
	function service:buildBroadcastSenderContext(player: Player): Result<BroadcastSenderContext>
		local userId = player.UserId
		local storedResult = repo:load(userId)
		local stored: OverheadStoredData
		if storedResult.ok then
			stored = storedResult.value
		else
			stored = OverheadDomain.defaultStoredData()
		end
		stored = OverheadDomain.applyHardcoded(stored, userId)

		local rankId = getGroupRank(userId)
		local role: RoleKey
		local storedGiftedRole = OverheadDomain.normalizeRoleKey(stored.giftedRole)
		if storedGiftedRole and OverheadDomain.isValidRole(storedGiftedRole) then
			role = storedGiftedRole
		else
			role = OverheadDomain.resolveRole(rankId, userId)
		end

		local effectiveMembership: MembershipTier = OverheadDomain.resolveEffectiveMembership(stored, rankId, userId)
		local roleMembership = OverheadDomain.normalizeMembershipTier(role)
		effectiveMembership = (
			OverheadDomain.getHigherMembership(effectiveMembership, roleMembership) or effectiveMembership
		) :: MembershipTier

		return ResultUtil.Ok({
			role = role,
			effectiveMembership = effectiveMembership,
		})
	end
	function service:resolveCommunity(player: Player, communityId: number): Result<CommunityData>
		local groups, ok = getGroups(player.UserId)
		if not ok or not groups then
			return ResultUtil.Err(Config.Community.MSG_LOOKUP_FAILED)
		end
		local communityData = resolveCommunityFromGroups(groups, communityId)
		if communityData then
			return ResultUtil.Ok(communityData)
		end
		return ResultUtil.Err(Config.Community.MSG_NOT_MEMBER)
	end

	-- Same resolution as overhead badge: stored /setcommun id, else primary group
	-- when PRIMARY_FALLBACK_ENABLED and badge not suppressed. Used for donation
	-- community leaderboard credit so donors without /setcommun still count.
	function service:resolveEffectiveCommunity(player: Player): Result<CommunityData?>
		local userId = player.UserId
		local storedResult = repo:load(userId)
		if not storedResult.ok then
			return ResultUtil.Err(storedResult.error)
		end
		local groups, ok = getGroups(userId)
		if not ok or not groups then
			return ResultUtil.Err(Config.Community.MSG_LOOKUP_FAILED)
		end
		local communityData = resolveEffectiveCommunityData(storedResult.value, groups)
		return ResultUtil.Ok(communityData)
	end

	function service:resolveCommunityByQuery(player: Player, query: string): Result<CommunityLookupResult>
		local groups, ok = getGroups(player.UserId)
		if not ok or not groups then
			return ResultUtil.Err(Config.Community.MSG_LOOKUP_FAILED)
		end
		local normalizedQuery = normalizeCommunityQuery(query)
		if normalizedQuery == "" then
			return ResultUtil.Ok({
				status = "not_found",
				query = query,
			} :: CommunityLookupResult)
		end
		local candidates = getCommunityCandidatesFromGroups(groups, normalizedQuery)
		if #candidates == 0 then
			return ResultUtil.Ok({
				status = "not_found",
				query = query,
			} :: CommunityLookupResult)
		end
		if #candidates == 1 then
			return ResultUtil.Ok({
				status = "found",
				community = candidates[1],
			} :: CommunityLookupResult)
		end
		return ResultUtil.Ok({
			status = "ambiguous",
			query = query,
			candidates = candidates,
		} :: CommunityLookupResult)
	end
	function service:getAboutRosterEntries(): Result<{ AboutRosterEntry }>
		if not aboutRosterRepository then
			return ResultUtil.Ok({} :: { AboutRosterEntry })
		end
		return aboutRosterRepository:loadEntries()
	end
	function service:isAboutRosterRole(role: string): boolean
		if not aboutRosterRepository then
			return false
		end
		return aboutRosterRepository:isRosterRole(role)
	end
	function service:syncAboutRosterEntry(player: Player, payload: OverheadPayload): Result<{ AboutRosterEntry }>
		if not aboutRosterRepository then
			return ResultUtil.Ok({} :: { AboutRosterEntry })
		end
		if not aboutRosterRepository:isRosterRole(payload.role) then
			return ResultUtil.Ok({} :: { AboutRosterEntry })
		end

		return aboutRosterRepository:upsertEntry({
			userId = payload.userId,
			displayName = payload.displayName,
			username = player.Name,
			role = payload.role,
			updatedAt = os.time(),
		})
	end
	function service:invalidateGroupCache(userId: number)
		Cache.invalidate(GROUPS_PREFIX .. userId)
		Cache.invalidate(GROUP_RANK_PREFIX .. userId)
		log:debug("Group cache invalidated", { userId = userId })
	end
	-- Invalidate cache rank Saweria & Robux. Dipakai oleh /verifyspender admin command
	-- supaya hasil cache negatif (false yang sticky 10 detik) langsung di-clear
	-- dan buildPayload berikutnya re-fetch dari leaderboard sumber.
	-- Patch #2 R2: Terima satu userId ATAU list of userId. Loop per-user agar cache
	-- miss hanya fire untuk player yang rank-nya beneran berubah, bukan 150 player
	-- seperti versi lama (yang wipe by prefix).
	function service:invalidateRankCaches(userIdOrList: number? | { number }?)
		local userIds: { number } = {}
		if type(userIdOrList) == "number" then
			userIds = { userIdOrList :: number }
		elseif type(userIdOrList) == "table" then
			for _, id in ipairs(userIdOrList :: { number }) do
				if type(id) == "number" then
					userIds[#userIds + 1] = id
				end
			end
		end
		if #userIds == 0 then
			-- Empty list = no-op (preserved safety; tidak wipe all).
			-- Sebelumnya no-arg wipe SEMUA rank cache — itu Amplifier A. Caller
			-- yang butuh wipe-all harus eksplisit pakai invalidateAllRankCaches().
			log:debug("invalidateRankCaches no-op (empty userIds)")
			return
		end
		for _, id in ipairs(userIds) do
			Cache.invalidate(ROBUX_TOP_DONATE_PREFIX .. tostring(id))
			Cache.invalidate(SAWERIA_TOP_SPENDER_PREFIX .. tostring(id))
		end
		log:debug("Rank caches invalidated (per-user)", { count = #userIds })
	end
	-- Opt-in: explicit wipe-all untuk kasus langka (hot-reload, admin reset).
	-- Dipisah supaya R2 default no-arg tidak accidentally wipe 150 cache entries.
	function service:invalidateAllRankCaches()
		Cache.invalidatePrefix(ROBUX_TOP_DONATE_PREFIX)
		Cache.invalidatePrefix(SAWERIA_TOP_SPENDER_PREFIX)
		log:debug("Rank caches invalidated (all)")
	end
	-- S1 (quota-efficiency-pass-2026-06, Phase 1): cheap hash of input cache state
	-- yang feed ke buildPayload. Kalau hash ini sama dengan hash sebelumnya, cached
	-- payload masih valid dan buildPayload bisa di-skip. Menghindari 1.5s CPU untuk
	-- 30-player refreshAll cycle (audit §5.5 C18 + C20).
	-- Note: Hanya hash cache state internal OverheadService. Profile/like/leaderboard
	-- modules punya cache masing-masing — asumsi cache miss/refresh sudah dihandle
	-- oleh invalidation events (invalidateGroupCache, invalidateRankCaches).
	function service:computeInputsFingerprint(userId: number): string
		local parts: { string } = {}

		-- 1. Stored data (DataStore cache) — hash key fields yang masuk ke payload
		local stored = Cache.get("overhead:" .. tostring(userId))
		if type(stored) == "table" then
			local gmHash = ""
			local giftedMemberships = (stored :: any).giftedMemberships
			if type(giftedMemberships) == "table" then
				local tierParts: { string } = {}
				for _, entry in ipairs(giftedMemberships) do
					if type(entry) == "table" then
						table.insert(
							tierParts,
							tostring(entry.tier or "")
								.. "@"
								.. tostring(entry.grantedAt or 0)
								.. "@"
								.. tostring(entry.grantedBy or 0)
						)
					end
				end
				table.sort(tierParts)
				gmHash = table.concat(tierParts, ",")
			end
			-- BUG FIX: hash stored.giftedRole + stored.ownedMembership + stored.membershipBadge
			-- (bukan stored.role yang tidak exist di schema). Sebelumnya fingerprint
			-- tidak berubah saat setrole/grantMembership → S1 short-circuit skip rebuild
			-- → client OverheadUI + leaderstat stuck di role lama.
			table.insert(
				parts,
				"s="
					.. tostring((stored :: any).giftedRole or "")
					.. "|"
					.. tostring((stored :: any).membershipBadge or "")
					.. "|"
					.. tostring((stored :: any).ownedMembership or "")
					.. "|"
					.. tostring((stored :: any).specialTitle or "")
					.. "|"
					.. tostring((stored :: any).specialTitlePreset or "")
					.. "|"
					.. tostring((stored :: any).specialTitleFont or "")
					.. "|"
					.. tostring((stored :: any).specialRank or "")
					.. "|"
					.. tostring((stored :: any).streakDays or "")
					.. "|"
					.. tostring((stored :: any).lastLoginAt or "")
					.. "|"
					.. tostring((stored :: any).showCoupleName == true and "1" or "0")
					.. "|"
					.. tostring((stored :: any).couplePartnerId or "")
					.. "|"
					.. tostring((stored :: any).topDonateRank or "")
					.. "|"
					.. tostring((stored :: any).topSpenderRank or "")
					.. "|"
					.. tostring((stored :: any).level or "")
					.. "|"
					.. tostring((stored :: any).xp or "")
					.. "|"
					.. tostring((stored :: any).communityId or "")
					.. "|gm="
					.. gmHash
			)
		else
			table.insert(parts, "s=none")
		end

		-- 2. Groups (cached array) — hash Id+Rank+count
		local groups = Cache.get(GROUPS_PREFIX .. userId)
		if type(groups) == "table" then
			local hash = 0
			local n = 0
			for _, g in ipairs(groups :: { any }) do
				n += 1
				hash = hash + (tonumber((g :: any).Id) or 0) + (tonumber((g :: any).Rank) or 0) * 7
			end
			table.insert(parts, "g=" .. tostring(hash) .. "/" .. tostring(n))
		else
			table.insert(parts, "g=none")
		end

		-- 3. Group rank (cached number)
		local rank = Cache.get(GROUP_RANK_PREFIX .. userId)
		table.insert(parts, "r=" .. tostring(rank or "none"))

		-- 4. Robux top donate rank
		local robuxRank = Cache.get(ROBUX_TOP_DONATE_PREFIX .. tostring(userId))
		table.insert(parts, "rr=" .. tostring(robuxRank or "none"))

		-- 5. Saweria top spender rank
		local saweriaRank = Cache.get(SAWERIA_TOP_SPENDER_PREFIX .. tostring(userId))
		table.insert(parts, "sr=" .. tostring(saweriaRank or "none"))

		-- 6. Cash donated cache (filled asynchronously by DonationService).
		-- Must be part of the fingerprint or S1 short-circuit would keep serving
		-- the initial 0 value after the async fetch lands.
		table.insert(parts, "c=" .. tostring(cashDonatedCache[userId] or "none"))

		local targetPlayer = Players:GetPlayerByUserId(userId)
		if targetPlayer then
			table.insert(
				parts,
				"p=" .. (if RobloxPlatformIcons.playerHasPaidRobloxSubscription(targetPlayer) then "1" else "0")
			)
		else
			table.insert(parts, "p=none")
		end

		return table.concat(parts, "|")
	end
	function service:onPlayerRemoving(player: Player)
		-- Clear per-UserId in-memory caches so they don't accumulate over the
		-- server lifetime at sustained CCU+churn. Without this, cashDonatedCache,
		-- rankResolutionScheduled and inFlight grew linearly with cumulative
		-- unique joiners for the whole server session.
		local userId = player.UserId
		cashDonatedCache[userId] = nil
		rankResolutionScheduled[userId] = nil
		inFlight[userId] = nil
	end

	return service
end
return createOverheadService
