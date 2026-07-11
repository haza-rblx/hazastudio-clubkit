--!strict
-- Server/Services/DonationService.lua
-- Polling Donation API v2 (Cloudflare Worker) -> match donatur -> update DataStore -> broadcast events.
-- Mendukung dual leaderboard: daily + all-time.
--
-- API v2: REST under {ApiUrl}/v2/* with Authorization: Bearer secret.
-- Reliability improvements:
-- - HTTP retry sekali sebelum dihitung failure (handle transient errors)
-- - Exponential backoff dengan cap lebih rendah -> recovery lebih cepat
-- - Batched leaderboard fetch (all-time + daily dalam satu request)
-- - Cursor-based notification polling (no since drift)
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TextService = game:GetService("TextService")
local UserService = game:GetService("UserService")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Secrets = require(ServerScriptService.Hazastudio_ClubKitSecrets.Secrets)
local LicenseService = require(script.Parent.LicenseService)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local HttpApiCounter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApiCounter)
local HttpApi = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApi)
local DataStoreThrottleLockout = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DataStoreThrottleLockout)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local StreakDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.StreakDomain)
type DonationEntry = Types.DonationEntry
type DonationNotifPayload = Types.DonationNotifPayload
type DonationLeaderboardPayload = Types.DonationLeaderboardPayload
type DonorProfilePayload = Types.DonorProfilePayload
type IOverheadRepository = Types.IOverheadRepository
type DonorCashCacheEntry = {
	total: number,
	rank: number?,
	expiresAt: number,
}
type UserIdCacheEntry = {
	userId: number,
	lastUsedAt: number,
}
type UserInfoCacheEntry = {
	username: string,
	displayName: string,
	lastUsedAt: number,
}
-- ============================================================
-- FACTORY
-- ============================================================
local function createDonationService(
	deps: {
		repo: IOverheadRepository,
		overheadController: any,
		overheadService: any?,
		leaderboardNetwork: any,
		notifNetwork: any,
		notify: any,
		donationEffectService: any?,
		donationLeaderboardRepository: any?,
		profileRepository: any?,
		manualBagibagiRepository: any?,
	}
)
	local repo = deps.repo
	local overheadController = deps.overheadController
	local overheadService = deps.overheadService
	local leaderboardNetwork = deps.leaderboardNetwork
	local notifNetwork = deps.notifNetwork
	local _notify = deps.notify
	local donationEffectService = deps.donationEffectService
	local donationLeaderboardRepository = deps.donationLeaderboardRepository
	local profileRepository = deps.profileRepository
	local manualBagibagiRepository = deps.manualBagibagiRepository
	local log = Logger.new("DonationService")
	local donorCashCache: { [number]: DonorCashCacheEntry } = {}
	-- Phase 1: Negative cache untuk donor_profile saat Worker rate-limited.
	-- Tanpa ini, 1 fail = N attempts (tiap refreshAll/poll trigger caller berikutnya).
	-- TTL lebih panjang dari positive cache biar Worker punya waktu recover.
	local donorFailureCache: { [number]: { expiresAt: number } } = {}
	local DONOR_PROFILE_FAILURE_CACHE_TTL = 120 -- detik

	local function invalidateDonorCashCache(userId: number?)
		if userId then
			donorCashCache[userId] = nil
			donorFailureCache[userId] = nil
			return
		end
		table.clear(donorCashCache)
		table.clear(donorFailureCache)
	end
	local service = {}
	local USER_ID_CACHE_TTL = 30 * 60
	local MAX_USER_ID_CACHE = 512
	-- State
	local notificationCursor: string = ""
	local notificationSkipBeforeUnix: number = os.time() -- cold start: skip backlog seperti v1 since=os.time()
	local lastNotifReceivedAt: number = 0 -- os.time() saat terakhir ada donasi terdeteksi (burst mode)
	local processedNotifIds: { [string]: boolean } = {}
	local processedNotifIdOrder: { string } = {}
	local MAX_PROCESSED_NOTIF_IDS = 512
	local _pollRunning = false -- prevent overlapping HTTP calls during slow Worker response
	local _pollStartedAt = 0
	local POLL_WATCHDOG_TIMEOUT = 45
	local _leaderboardRefreshQueued = false -- debounce flag for async leaderboard refresh
	local _lastLeaderboardRefreshAt = 0 -- timestamp of last leaderboard refresh
	local LEADERBOARD_REFRESH_DEBOUNCE = 10 -- min seconds between refreshes
	-- Server-side notification rate limit: max 1 broadcast per 2 seconds.
	-- Prevents client queue flood at high CCU when many donations arrive in one poll cycle.
	-- Stagger index for notification broadcast delay at high CCU
	local notifStaggerIndex = 0
	local cachedLeaderboard: DonationLeaderboardPayload = {
		daily = {},
		allTime = {},
		updatedAt = 0,
	}
	local sheetsBroadcastRevision = 0
	local lastSheetsBroadcastFingerprint: string? = nil
	-- Phase 2: Debounce state untuk overheadController:refreshAll().
	-- Skip kalau leaderboard fingerprint unchanged dalam window REFRESH_ALL_MIN_INTERVAL detik.
	local lastRefreshAllFingerprint: string? = nil
	local lastRefreshAllAt: number = 0
	local REFRESH_ALL_MIN_INTERVAL = 8 -- detik, lebih longgar dari poll interval (5-10s)
	-- Phase 3: Track userId yang pernah donasi (dari notif, manual adjustment, atau cash stats > 0).
	-- Skip API call ke donor_profile untuk player yang belum pernah donasi — kebanyakan player
	-- di leaderboard overhead bukan donor, jadi API call selalu return cash_total=0.
	-- knownDonors sticky: sekali marked, tetap dikenal sampai module reload. Hot-reload safe
	-- karena state reset = back to "unknown" yang konservatif (cuma extra API call).
	local knownDonors: { [number]: true } = {}
	local function markKnownDonor(userId: number)
		if userId and userId > 0 then
			knownDonors[userId] = true
		end
	end

	local function computeSheetsFingerprint(payload: DonationLeaderboardPayload): string
		local parts = {
			tostring(payload.updatedAt),
			tostring(#payload.daily),
			tostring(#payload.allTime),
		}
		local topN = 5
		for i = 1, math.min(topN, #payload.allTime) do
			local entry = payload.allTime[i]
			parts[#parts + 1] = string.format(
				"%d:%s:%s",
				entry.rank,
				tostring(entry.totalAmount),
				tostring(entry.robloxUsername or entry.saweriaName or "")
			)
		end
		for i = 1, math.min(topN, #payload.daily) do
			local entry = payload.daily[i]
			parts[#parts + 1] = string.format(
				"d%d:%s:%s",
				entry.rank,
				tostring(entry.totalAmount),
				tostring(entry.robloxUsername or entry.saweriaName or "")
			)
		end
		return table.concat(parts, "|")
	end

	local function broadcastSheetsLeaderboardSignal(force: boolean?)
		local fingerprint = computeSheetsFingerprint(cachedLeaderboard)
		if not force and fingerprint == lastSheetsBroadcastFingerprint then
			return
		end
		if fingerprint ~= lastSheetsBroadcastFingerprint then
			lastSheetsBroadcastFingerprint = fingerprint
			sheetsBroadcastRevision += 1
		end
		local signalOnly = Config.Donation.SHEETS_REFRESH_SIGNAL_ONLY ~= false
		if signalOnly then
			leaderboardNetwork:fireAllClients({
				type = "donation_sheets_refresh",
				revision = sheetsBroadcastRevision,
				updatedAt = cachedLeaderboard.updatedAt,
			})
		else
			leaderboardNetwork:fireAllClients(cachedLeaderboard)
		end
	end

	-- Phase 2: Debounce helper untuk overheadController:refreshAll().
	-- Return true kalau fingerprint berubah (atau force=true), false kalau skip.
	-- Min interval 8s sebagai safety net kalau fingerprint computation mahal.
	local function shouldRefreshAll(force: boolean?): boolean
		if force == true then
			return true
		end
		local now = os.clock()
		if now - lastRefreshAllAt < REFRESH_ALL_MIN_INTERVAL then
			return false
		end
		local fingerprint = computeSheetsFingerprint(cachedLeaderboard)
		if fingerprint == lastRefreshAllFingerprint then
			return false
		end
		lastRefreshAllFingerprint = fingerprint
		lastRefreshAllAt = now
		return true
	end
	-- { [robloxUsername:lower()]: rank } untuk daily + alltime gabungan
	local assignedRanks: { [string]: number } = {}
	-- Daily Robux tracking (in-memory). Reset tiap tengah malam WIB; window 00:01-23:59:59.
	-- { [userId]: { userId, username, displayName, thumbnail, total } }
	local cachedDailyRobux: { [number]: any } = {}
	local sessionRobuxTotals: { [number]: number } = {}
	local currentRobuxDayBucket: number = -1
	local function getWibDayBucket(): number
		return StreakDomain.toDayNumber(os.time())
	end
	local function ensureRobuxDailyFresh()
		local bucket = getWibDayBucket()
		if bucket ~= currentRobuxDayBucket then
			cachedDailyRobux = {}
			currentRobuxDayBucket = bucket
		end
	end
	local function isHiddenRobuxUser(userId: number): boolean
		local hiddenUserIds = Config.Leaderboards.HIDDEN_ROBUX_USER_IDS
		return type(hiddenUserIds) == "table" and hiddenUserIds[userId] == true
	end
	local leaderboardUpdatedCallbacks: { () -> () } = {}
	-- Claim cooldown: { [userId]: lastClaimAt (os.time) }
	local claimCooldowns: { [number]: number } = {}
	-- Failure tracking (consecutive - reset segera setelah 1x sukses)
	local consecutiveFailures = 0
	-- Helpers
	local DonationProviderDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.DonationProviderDomain)

	local function getProviderKey(): string
		return DonationProviderDomain.getKey()
	end

	local function getProviderName(): string
		return DonationProviderDomain.getName()
	end

	local function getProviderDonorFallback(): string
		return getProviderName() .. " Donor"
	end

	local function isHiddenDonationUser(userId: number): boolean
		local hiddenUserIds = Config.Leaderboards.HIDDEN_ROBUX_USER_IDS
		return type(hiddenUserIds) == "table" and hiddenUserIds[userId] == true
	end

	local function isDonationHttpReady(): boolean
		local base = Config.Donation.SHEETS_WEB_APP_URL
		local secret = Secrets.DonationApiSecret
		return type(base) == "string" and base ~= "" and type(secret) == "string" and secret ~= ""
	end

	local function isLicenseDonationAllowed(): boolean
		return LicenseService.isFeatureEnabled("donation_http")
	end

	local function isCashDonationEnabled(): boolean
		local cashEnabled = Config.FeatureFlags.DonationCashEnabled
		if cashEnabled == nil then
			cashEnabled = Config.FeatureFlags.DonationSaweriaEnabled ~= false
		end
		return cashEnabled ~= false
	end

	local function getDonationApiBase(): string
		local base = Config.Donation.SHEETS_WEB_APP_URL
		if type(base) ~= "string" or base == "" then
			return ""
		end
		return (base:gsub("/+$", ""))
	end

	local function buildV2Url(resourcePath: string, query: { [string]: string }?): string
		local base = getDonationApiBase()
		if base == "" then
			return ""
		end
		local path = resourcePath:gsub("^/+", "")
		local url = base .. "/v2/" .. path
		if not query then
			return url
		end
		local params: { string } = {}
		for key, value in pairs(query) do
			if value ~= "" then
				table.insert(params, HttpService:UrlEncode(key) .. "=" .. HttpService:UrlEncode(value))
			end
		end
		if #params > 0 then
			url ..= "?" .. table.concat(params, "&")
		end
		return url
	end

	local function httpRequestOnce(method: string, url: string, body: string?): (boolean, string)
		if url == "" then
			return false, "Donation API belum dikonfigurasi"
		end
		local secret = Secrets.DonationApiSecret
		if type(secret) ~= "string" or secret == "" then
			return false, "DonationApiSecret belum dikonfigurasi"
		end
		local timeout = Config.Donation.HTTP_TIMEOUT
		local ok, response = pcall(function()
			return HttpService:RequestAsync({
				Url = url,
				Method = method,
				Headers = {
					Authorization = "Bearer " .. secret,
					["Content-Type"] = "application/json",
				},
				Body = body,
				Timeout = timeout,
			})
		end)
		if not ok or type(response) ~= "table" then
			return false, tostring(response)
		end
		if response.Success ~= true then
			local statusCode = tonumber(response.StatusCode) or 0
			local responseBody = if type(response.Body) == "string" then response.Body else ""
			return false, string.format("HTTP %d: %s", statusCode, responseBody)
		end
		return true, if type(response.Body) == "string" then response.Body else ""
	end

	local function resolveTextFilterUserId(userId: number?): number
		if type(userId) == "number" and userId > 0 and Players:GetPlayerByUserId(userId) then
			return userId
		end
		return 1
	end

	local function markNotifProcessed(notifId: string)
		if notifId == "" or processedNotifIds[notifId] then
			return
		end
		processedNotifIds[notifId] = true
		table.insert(processedNotifIdOrder, notifId)
		if #processedNotifIdOrder > MAX_PROCESSED_NOTIF_IDS then
			local oldest = table.remove(processedNotifIdOrder, 1)
			if oldest then
				processedNotifIds[oldest] = nil
			end
		end
	end

	local function filterForBroadcast(userId: number?, message: string?, maxLength: number?): string?
		if not userId or userId <= 0 or type(message) ~= "string" then
			return nil
		end
		local trimmed = message:match("^%s*(.-)%s*$") or ""
		if trimmed == "" then
			return nil
		end
		if maxLength and maxLength > 0 then
			trimmed = string.sub(trimmed, 1, maxLength)
		end
		local lastError: any = nil
		for attempt = 1, 3 do
			local ok, filtered = pcall(function()
				local result = TextService:FilterStringAsync(trimmed, userId, Enum.TextFilterContext.PublicChat)
				return result:GetNonChatStringForBroadcastAsync()
			end)
			if ok and type(filtered) == "string" then
				return filtered
			end
			lastError = filtered
			if attempt < 3 then
				task.wait(0.35 * attempt)
			end
		end
		log:warn("Donation provider text filter failed", {
			userId = userId,
			provider = getProviderName(),
			error = tostring(lastError),
		})
		return nil
	end

	local function cleanOptionalMessage(value: any, maxLength: number?): string?
		if type(value) ~= "string" then
			return nil
		end
		local trimmed = value:match("^%s*(.-)%s*$") or ""
		if trimmed == "" then
			return nil
		end
		if maxLength and maxLength > 0 then
			trimmed = string.sub(trimmed, 1, maxLength)
		end
		return trimmed
	end

	local function censoredMessageFallback(message: string): string
		local length = math.clamp(#message, 5, 24)
		return string.rep("#", length)
	end

	-- httpGetOnce: satu percobaan HTTP GET dengan RequestAsync + Bearer auth
	local function httpGetOnce(url: string): (boolean, string)
		return httpRequestOnce("GET", url, nil)
	end
	-- httpGet: satu percobaan + optional retry (handle transient network errors)
	local function httpGet(url: string): (boolean, string)
		if url == "" then
			return false, "Donation API belum dikonfigurasi"
		end
		local ok, res = httpGetOnce(url)
		if ok then
			return true, res
		end
		-- Retry sekali jika diaktifkan di config
		if Config.Donation.NOTIF_RETRY_ENABLED then
			-- Phase 4: Downgrade ke debug — caller (fetchDonorCashProfile, _pollNotifications, _pollLeaderboard)
			-- sudah log warning yang lebih spesifik per-endpoint. Retry log ini duplicate noise.
			log:debug("HTTP gagal, retry dalam " .. Config.Donation.NOTIF_RETRY_DELAY .. "s", {
				url = url,
				error = res,
			})
			task.wait(Config.Donation.NOTIF_RETRY_DELAY)
			return httpGetOnce(url)
		end
		return false, res
	end
	-- Exponential backoff: 5, 10, 20 (capped) detik per consecutive failure
	local function getNotifFailureBackoff(): number
		if consecutiveFailures <= 0 then
			return 0
		end
		local step = math.min(consecutiveFailures, 4)
		local baseDelay = Config.Donation.NOTIF_FAILURE_BACKOFF_STEP
		local maxDelay = Config.Donation.NOTIF_FAILURE_BACKOFF_MAX
		-- Exponential: baseDelay * 2^(step-1) -> 5, 10, 20, 20 (capped)
		return math.min(baseDelay * (2 ^ (step - 1)), maxDelay)
	end

	local function cleanProviderName(value: any): string
		if value == nil then
			return ""
		end
		return (tostring(value):match("^%s*(.-)%s*$") or "")
	end

	local function cleanRobloxUsername(value: any): string?
		if value == nil then
			return nil
		end
		local username = (tostring(value):match("^%s*(.-)%s*$") or ""):gsub("^@", "")
		if username == "" then
			return nil
		end
		return username
	end

	local function getItemProviderName(item: any): string
		return cleanProviderName(
			item.bagibagi_name
				or item.provider_name
				or item.donor_name
				or item.saweria_name
				or item.donator_name
				or item.name
		)
	end

	local function getItemRobloxUsername(item: any): string?
		return cleanRobloxUsername(
			item.roblox_username
				or item.robloxUsername
				or item.roblox_name
				or item.robloxName
				or item.username
				or item.user_name
				or item.player_name
		)
	end

	local function getItemRobloxUsernameOrProviderName(item: any): string?
		return getItemRobloxUsername(item) or cleanRobloxUsername(getItemProviderName(item))
	end

	local function parseEntries(raw: any): { DonationEntry }
		local result: { DonationEntry } = {}
		if type(raw) ~= "table" then
			return result
		end
		for _, item in ipairs(raw) do
			if type(item) == "table" then
				local providerName = getItemProviderName(item)
				table.insert(result, {
					rank = tonumber(item.rank) or 0,
					saweriaName = providerName,
					robloxUsername = getItemRobloxUsername(item) or cleanRobloxUsername(providerName),
					robloxUserId = tonumber(item.roblox_user_id or item.robloxUserId or item.userId),
					totalAmount = tonumber(item.total) or 0,
					lastDonationAt = tostring(item.last_at or ""),
				})
			end
		end
		return result
	end
	local userIdCache: { [string]: UserIdCacheEntry } = {}
	local userInfoCache: { [number]: UserInfoCacheEntry } = {}

	local function pruneUserIdCache(nowClock: number)
		local entries = {} :: { { key: string, lastUsedAt: number } }

		for lowerName, entry in pairs(userIdCache) do
			if (nowClock - entry.lastUsedAt) > USER_ID_CACHE_TTL then
				userIdCache[lowerName] = nil
			else
				table.insert(entries, {
					key = lowerName,
					lastUsedAt = entry.lastUsedAt,
				})
			end
		end

		if #entries <= MAX_USER_ID_CACHE then
			return
		end

		table.sort(entries, function(a, b)
			return a.lastUsedAt > b.lastUsedAt
		end)

		for index = MAX_USER_ID_CACHE + 1, #entries do
			userIdCache[entries[index].key] = nil
		end
	end
	local function rememberResolvedUserId(lowerName: string, userId: number, nowClock: number): number
		userIdCache[lowerName] = {
			userId = userId,
			lastUsedAt = nowClock,
		}
		pruneUserIdCache(nowClock)
		return userId
	end
	local function resolveRobloxUserId(username: string?): number?
		local normalizedUsername = cleanRobloxUsername(username)
		if not normalizedUsername then
			return nil
		end
		local lowerName = normalizedUsername:lower()
		local nowClock = os.clock()
		pruneUserIdCache(nowClock)
		local cached = userIdCache[lowerName]
		if cached then
			cached.lastUsedAt = nowClock
			return cached.userId
		end
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Name:lower() == lowerName then
				return rememberResolvedUserId(lowerName, player.UserId, nowClock)
			end
		end
		local userId = HttpApi.getUserIdFromNameAsync(normalizedUsername)
		if type(userId) == "number" then
			return rememberResolvedUserId(lowerName, userId, nowClock)
		end
		return nil
	end
	local function getRobloxUserInfo(userId: number): (string?, string?)
		if userId <= 0 then
			return nil, nil
		end
		local nowClock = os.clock()
		local cached = userInfoCache[userId]
		if cached and (nowClock - cached.lastUsedAt) <= USER_ID_CACHE_TTL then
			cached.lastUsedAt = nowClock
			return cached.username, cached.displayName
		end

		local player = Players:GetPlayerByUserId(userId)
		if player then
			userInfoCache[userId] = {
				username = player.Name,
				displayName = player.DisplayName,
				lastUsedAt = nowClock,
			}
			return player.Name, player.DisplayName
		end

		local userInfos = HttpApi.getUserInfosByUserIdsAsync({ userId })
		local info = userInfos[userId]
		if type(info) == "table" then
			local username = if type(info.Username) == "string" and info.Username ~= "" then info.Username else nil
			local displayName = if type(info.DisplayName) == "string" and info.DisplayName ~= "" then info.DisplayName else username
			if username or displayName then
				userInfoCache[userId] = {
					username = username or "",
					displayName = displayName or username or "",
					lastUsedAt = nowClock,
				}
				return username, displayName
			end
		end

		return nil, nil
	end
	local function getUserThumbnail(userId: number): string
		-- HTTP API telemetry counter (quota-efficiency-pass-2026-06, Phase 0)
		if Config.HttpApi and Config.HttpApi.COUNTERS_ENABLED then
			HttpApiCounter.record("donation_thumbnail_total")
		end
		local ok, thumbnail = pcall(function()
			-- Size150x150 default. Top 1-3 posters fetch 420 client-side via rbxthumb URL.
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and type(thumbnail) == "string" then
			return thumbnail
		end
		return ""
	end

	local function rerankEntriesByTotal(entries: { DonationEntry })
		table.sort(entries, function(a, b)
			return (tonumber(a.totalAmount) or 0) > (tonumber(b.totalAmount) or 0)
		end)
		for index, entry in ipairs(entries) do
			entry.rank = index
		end
	end

	local function findAllTimeEntryByUserId(userId: number, username: string?): DonationEntry?
		local lowerName = if type(username) == "string" then username:lower() else nil
		for _, entry in ipairs(cachedLeaderboard.allTime) do
			local entryUserId = entry.robloxUserId
			if not entryUserId and type(entry.robloxUsername) == "string" then
				entryUserId = resolveRobloxUserId(entry.robloxUsername)
			end
			if entryUserId == userId then
				return entry
			end
			if lowerName and type(entry.robloxUsername) == "string" and entry.robloxUsername:lower() == lowerName then
				return entry
			end
		end
		return nil
	end

	local function resolveUsernameForUserId(userId: number, fallback: string?): string
		local player = Players:GetPlayerByUserId(userId)
		if player then
			return player.Name
		end
		if type(fallback) == "string" and fallback ~= "" then
			return fallback
		end
		local name = HttpApi.getNameFromUserIdAsync(userId)
		if type(name) == "string" and name ~= "" then
			return name
		end
		return "userId:" .. tostring(userId)
	end

	local function applyManualBagibagiAdjustments(entries: { DonationEntry })
		local adjMap = Config.Donation and Config.Donation.MANUAL_BAGIBAGI_ADJUSTMENTS
		if type(adjMap) ~= "table" then
			return
		end

		for rawUserId, rawDelta in pairs(adjMap) do
			local userId = tonumber(rawUserId)
			local delta = math.floor(tonumber(rawDelta) or 0)
			if not userId or userId <= 0 or delta == 0 then
				continue
			end

			local found = false
			for _, entry in ipairs(entries) do
				local entryUserId = entry.robloxUserId
				if not entryUserId and type(entry.robloxUsername) == "string" then
					entryUserId = resolveRobloxUserId(entry.robloxUsername)
					if entryUserId then
						entry.robloxUserId = entryUserId
					end
				end
				if entryUserId == userId then
					entry.totalAmount = math.max(
						math.floor(tonumber(entry.totalAmount) or 0),
						math.floor(tonumber(delta) or 0)
					)
					found = true
					break
				end
			end

			if not found and delta > 0 then
				local username = resolveUsernameForUserId(userId, nil)
				table.insert(entries, {
					rank = 0,
					saweriaName = username,
					robloxUsername = username,
					robloxUserId = userId,
					totalAmount = delta,
					lastDonationAt = "",
				})
			end
		end
	end

	local function mergeLegacySaweriaEntries(entries: { DonationEntry }): { DonationEntry }
		local seeds = Config.Donation.LEGACY_SAWERIA_SEED
		if type(seeds) ~= "table" then
			rerankEntriesByTotal(entries)
			return entries
		end

		local mergedByName: { [string]: DonationEntry } = {}
		local ordered: { DonationEntry } = {}

		local function upsert(entry: DonationEntry, shouldAddAmount: boolean)
			local key = cleanProviderName(entry.saweriaName):lower()
			if key == "" then
				return
			end

			local existing = mergedByName[key]
			if existing then
				if shouldAddAmount then
					existing.totalAmount = (tonumber(existing.totalAmount) or 0) + (tonumber(entry.totalAmount) or 0)
				else
					existing.totalAmount = math.max(tonumber(existing.totalAmount) or 0, tonumber(entry.totalAmount) or 0)
				end
				existing.robloxUsername = entry.robloxUsername or existing.robloxUsername
				existing.robloxUserId = entry.robloxUserId or existing.robloxUserId
				existing.lastDonationAt = entry.lastDonationAt or existing.lastDonationAt
				return
			end

			local copy: DonationEntry = {
				rank = tonumber(entry.rank) or 0,
				saweriaName = cleanProviderName(entry.saweriaName),
				robloxUsername = cleanRobloxUsername(entry.robloxUsername),
				robloxUserId = entry.robloxUserId,
				totalAmount = tonumber(entry.totalAmount) or 0,
				lastDonationAt = entry.lastDonationAt,
			}
			mergedByName[key] = copy
			table.insert(ordered, copy)
		end

		for _, entry in ipairs(entries) do
			upsert(entry, false)
		end

		local addedLegacy = 0
		for _, seed in ipairs(seeds) do
			local seedName = cleanProviderName(seed.saweriaName)
			if seedName == "" then
				continue
			end
			local resolvedUserId = tonumber(seed.robloxUserId) or resolveRobloxUserId(seed.robloxUsername or seedName)
			local resolvedUsername = cleanRobloxUsername(seed.robloxUsername)
			if not resolvedUsername and resolvedUserId then
				resolvedUsername = seedName
			end
			upsert({
				rank = tonumber(seed.rank) or 0,
				saweriaName = seedName,
				robloxUsername = resolvedUsername,
				robloxUserId = resolvedUserId,
				totalAmount = tonumber(seed.totalAmount) or 0,
				lastDonationAt = nil,
			}, true)
			addedLegacy += 1
		end

		rerankEntriesByTotal(ordered)
		log:info("Saweria legacy seed merged", {
			legacyCount = addedLegacy,
			newCount = #entries,
			mergedCount = #ordered,
		})
		return ordered
	end

	local function cleanupClaimCooldowns(nowEpoch: number)
		for userId, lastClaimAt in pairs(claimCooldowns) do
			if (nowEpoch - lastClaimAt) >= Config.Donation.CLAIM_COOLDOWN then
				claimCooldowns[userId] = nil
			end
		end
	end
	-- Patch #2 R2: Track userIds yang rank-nya berubah selama applyLeaderboardDiff,
	-- dipakai untuk invalidate rank cache per-user (bukan wipe all). Di-reset setiap call.
	local lastDiffChangedUserIds: { [number]: true } = {}
	local function markChangedUserId(userId: number)
		if type(userId) == "number" and userId > 0 then
			lastDiffChangedUserIds[userId] = true
		end
	end
	local function drainChangedUserIds(): { number }
		local out: { number } = {}
		for id in pairs(lastDiffChangedUserIds) do
			out[#out + 1] = id
		end
		lastDiffChangedUserIds = {}
		return out
	end
	local clearPlayer: (number, string) -> ()
	-- Assign Saweria top spender tag ke player online.
	local function assignPlayer(robloxUsername: string, rank: number)
		local cleanedUsername = cleanRobloxUsername(robloxUsername)
		if not cleanedUsername then
			return
		end
		local lower = cleanedUsername:lower()
		-- Cari player aktif
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Name:lower() == lower then
				if isHiddenDonationUser(player.UserId) then
					clearPlayer(player.UserId, player.Name)
					return
				end
				local topText = Config.Donation.TOP_SPENDER_TEXTS[rank] or ("#" .. rank .. " INVESTOR")
				local mergeTopSpender: { [string]: any } = { topSpenderRank = rank }
				if Config.Donation.SHOW_LEGACY_TOP_SPENDER_ROW == true then
					mergeTopSpender.topSpenderText = topText
				else
					mergeTopSpender.topSpenderText = OverheadDomain.NIL
				end
				local result = repo:update(player.UserId, function(current)
					return OverheadDomain.mergeStored(current, mergeTopSpender)
				end)
				if result.ok then
					markChangedUserId(player.UserId)
					service:refreshPlayerOverhead(player)
					log:info("Assigned top spender tag", {
						player = player.Name,
						rank = rank,
						text = topText,
					})
				else
					log:warn("Gagal update DataStore top spender", {
						player = player.Name,
						error = result.error,
					})
				end
				return
			end
		end
	end
	-- Clear Saweria top spender tag dari player yang keluar leaderboard
	clearPlayer = function(userId: number, playerName: string)
		local result = repo:update(userId, function(current)
			return OverheadDomain.mergeStored(current, {
				topSpenderRank = OverheadDomain.NIL,
				topSpenderText = OverheadDomain.NIL,
			})
		end)
		if result.ok then
			markChangedUserId(userId)
			-- Refresh jika masih online
			local player = Players:GetPlayerByUserId(userId)
			if player then
				overheadController:refreshPlayer(player)
			end
			log:info("Cleared top spender tag", { player = playerName })
		end
	end
	-- Diff leaderboard lama vs baru, assign/clear perubahan
	local function applyLeaderboardDiff(newEntries: { DonationEntry })
		-- Reset changed set di awal; assignPlayer/clearPlayer populate via markChangedUserId
		lastDiffChangedUserIds = {}
		local newRanks: { [string]: number } = {}
		for _, entry in ipairs(newEntries) do
			if entry.rank > Config.Donation.LEADERBOARD_LIMIT then
				continue
			end
			local username = cleanRobloxUsername(entry.robloxUsername)
			if username and username ~= "" then
				local lowerName = username:lower()
				newRanks[lowerName] = entry.rank
				local oldRank = assignedRanks[lowerName]
				if oldRank ~= entry.rank then
					-- Rank berubah atau baru masuk -> assign
					assignPlayer(username, entry.rank)
				end
			end
		end
		-- Clear player yang tidak lagi di leaderboard
		for lowerName, _ in pairs(assignedRanks) do
			if not newRanks[lowerName] then
				-- Cari userId
				for _, player in ipairs(Players:GetPlayers()) do
					if player.Name:lower() == lowerName then
						clearPlayer(player.UserId, player.Name)
						break
					end
				end
			end
		end
		assignedRanks = newRanks
	end

	local function invalidateOverheadRankCaches(userId: number?)
		if overheadService and type(overheadService.invalidateRankCaches) == "function" then
			overheadService:invalidateRankCaches(userId)
		end
	end

	local function syncBagibagiLeaderboardFromCache(forceBroadcast: boolean?)
		rerankEntriesByTotal(cachedLeaderboard.allTime)
		cachedLeaderboard.updatedAt = os.time()
		applyLeaderboardDiff(cachedLeaderboard.allTime)
		-- Patch #2 R2: invalidate per-user (rank yang berubah saja), bukan wipe all
		invalidateOverheadRankCaches(drainChangedUserIds())
		broadcastSheetsLeaderboardSignal(forceBroadcast == true)
		service:notifyWorkspaceLeaderboardsUpdated()
		-- Phase 2: Skip refreshAll kalau leaderboard fingerprint unchanged.
		if shouldRefreshAll(forceBroadcast == true) and overheadController and type(overheadController.refreshAll) == "function" then
			task.defer(function()
				overheadController:refreshAll()
			end)
		end
	end

	-- Poll
	-- _pollLeaderboard: fetch all-time & daily dalam satu request v2
	function service:_pollLeaderboard(forceBroadcast: boolean?)
		if not isCashDonationEnabled() then
			return
		end
		if not isDonationHttpReady() then
			return
		end
		if not isLicenseDonationAllowed() then
			return
		end
		local cfg = Config.Donation
		local fetchLimit = math.max(cfg.LEADERBOARD_LIMIT, Config.Leaderboards.MAX_LIMIT or cfg.LEADERBOARD_LIMIT)
		local previousCache = cachedLeaderboard
		local allTimeEntries: { DonationEntry } = {}
		local dailyEntries: { DonationEntry } = {}
		local allTimeOk = false
		local dailyOk = false

		local url = buildV2Url("leaderboards", {
			boards = "alltime,daily",
			limit = tostring(fetchLimit),
		})
		local ok, res = httpGet(url)
		if ok then
			local decodeOk = pcall(function()
				local json = HttpService:JSONDecode(res)
				if json and json.ok and type(json.boards) == "table" then
					if type(json.boards.alltime) == "table" then
						allTimeEntries = parseEntries(json.boards.alltime)
						allTimeOk = true
					end
					if type(json.boards.daily) == "table" then
						dailyEntries = parseEntries(json.boards.daily)
						dailyOk = true
					end
				end
			end)
			if not decodeOk then
				log:warn("Leaderboard v2 parse failed")
			end
		else
			log:warn("HTTP gagal (leaderboards v2)", { error = res })
		end

		if not allTimeOk and previousCache and #previousCache.allTime > 0 then
			allTimeEntries = previousCache.allTime
			log:warn("Leaderboard all-time pakai cache (HTTP gagal)", {
				cachedCount = #allTimeEntries,
			})
		end
		if not dailyOk and previousCache and #previousCache.daily > 0 then
			dailyEntries = previousCache.daily
			log:warn("Leaderboard daily pakai cache (HTTP gagal)", {
				cachedCount = #dailyEntries,
			})
		end
		if not allTimeOk and not dailyOk then
			return
		end

		-- P0: Saat throttle lockout aktif, HTTP cache tetap di-update tapi skip
		-- downstream DS cascade (applyLeaderboardDiff + refreshAll). DS writes/
		-- reads akan short-circuit via repository lockout; explicit log di sini
		-- supaya operator bisa lihat di console tanpa harus grep server log.
		if DataStoreThrottleLockout.isLocked() then
			log:info("Leaderboard poll: skipping DS cascade (throttle lockout aktif)", {
				remainingSec = math.floor(DataStoreThrottleLockout.getRemainingSec() + 0.5),
			})
			-- Tetap update in-memory cache + broadcast signal so client UI tetap
			-- up-to-date dengan HTTP state; hanya DS-bound ops yang di-skip.
			if allTimeOk then
				cachedLeaderboard = {
					daily = dailyEntries,
					allTime = allTimeEntries,
					updatedAt = os.time(),
				}
				applyLeaderboardDiff(allTimeEntries)
			end
			broadcastSheetsLeaderboardSignal(forceBroadcast == true)
			service:notifyWorkspaceLeaderboardsUpdated()
			return
		end

		-- Merge legacy Saweria snapshot with the live sheet data so old totals remain connected.
		-- Daily tidak di-seed karena resets.
		if allTimeOk then
			allTimeEntries = mergeLegacySaweriaEntries(allTimeEntries)
			applyManualBagibagiAdjustments(allTimeEntries)
			rerankEntriesByTotal(allTimeEntries)
		end
		rerankEntriesByTotal(dailyEntries)
		-- Update cache & diff
		cachedLeaderboard = {
			daily = dailyEntries,
			allTime = allTimeEntries,
			updatedAt = os.time(),
		}
		if type(self.invalidateDonorProfileCache) == "function" then
			self:invalidateDonorProfileCache()
		end
		-- Apply diff berdasarkan all-time (overhead tag berdasarkan all-time)
		applyLeaderboardDiff(allTimeEntries)
		broadcastSheetsLeaderboardSignal(forceBroadcast == true)
		service:notifyWorkspaceLeaderboardsUpdated()
		-- Phase 2: Skip refreshAll kalau leaderboard fingerprint unchanged.
		if shouldRefreshAll(forceBroadcast == true) and overheadController and type(overheadController.refreshAll) == "function" then
			task.defer(function()
				overheadController:refreshAll()
			end)
		end
		log:debug("Leaderboard di-broadcast", {
			allTimeCount = #allTimeEntries,
			dailyCount = #dailyEntries,
		})
	end

	local function fireCashDonationPresentation(args: {
		filteredDonatorName: string,
		amount: number,
		message: string?,
		newRank: number?,
		robloxUsername: string?,
		robloxUserId: number?,
		robloxDisplayName: string?,
		totalDonationAmount: number?,
		logDonor: string?,
		testOnly: boolean?,
	})
		local amount = math.floor(tonumber(args.amount) or 0)
		if amount <= 0 then
			return
		end

		-- Phase 3: Mark as known donor — broadcast selalu = userId sah jadi donatur.
		-- Covers semua caller: _pollNotifications, presentCashDonation, manual cash.
		if not args.testOnly then
			markKnownDonor(args.robloxUserId)
		end

		local payload: DonationNotifPayload = {
			saweriaName = args.filteredDonatorName,
			amount = amount,
			message = args.message,
			newRank = args.newRank,
			robloxUsername = args.robloxUsername,
			robloxUserId = args.robloxUserId,
			robloxDisplayName = args.robloxDisplayName,
			totalDonationAmount = args.totalDonationAmount,
			source = "cash",
		}
		-- Stagger broadcast: delay between notifications to prevent client queue flood.
		-- At high CCU, multiple donations arrive in one poll cycle. Without staggering,
		-- all notifications hit the client simultaneously, filling the 20-item queue
		-- and causing dropped notifications.
		local staggerDelay = notifStaggerIndex * 0.5
		notifStaggerIndex += 1
		-- Reset stagger index after 5 seconds of no new notifications
		task.delay(5, function()
			notifStaggerIndex = math.max(0, notifStaggerIndex - 1)
		end)
		
		task.delay(staggerDelay, function()
			notifNetwork:fireAllClients(payload)
			log:info("Donation notification broadcast", {
				donor = args.logDonor or args.filteredDonatorName,
				amount = amount,
				rank = args.newRank,
				staggerMs = math.floor(staggerDelay * 1000),
			})

			local robloxUserId = args.robloxUserId
			if robloxUserId and donationEffectService then
				local playCash = donationEffectService.playCashDonation or donationEffectService.playSaweriaDonation
				if type(playCash) == "function" then
					local donor = Players:GetPlayerByUserId(robloxUserId)
					if donor then
						local okEffect, errEffect = pcall(function()
							return playCash(donationEffectService, donor, amount)
						end)
						if not okEffect then
							log:warn("External donation effect failed", {
								player = donor.Name,
								amount = amount,
								provider = getProviderName(),
								error = tostring(errEffect),
							})
						end
					end
				end
			end
		end)


	end

	local function fireRobuxDonationPresentation(args: {
		filteredDonatorName: string,
		amount: number,
		message: string?,
		newRank: number?,
		robloxUsername: string?,
		robloxUserId: number?,
		robloxDisplayName: string?,
		totalDonationAmount: number?,
		logDonor: string?,
		testOnly: boolean?,
	})
		local amount = math.floor(tonumber(args.amount) or 0)
		if amount <= 0 then
			return
		end

		if not args.testOnly then
			markKnownDonor(args.robloxUserId)
		end

		local payload: DonationNotifPayload = {
			saweriaName = args.filteredDonatorName,
			amount = amount,
			message = args.message,
			newRank = args.newRank,
			robloxUsername = args.robloxUsername,
			robloxUserId = args.robloxUserId,
			robloxDisplayName = args.robloxDisplayName,
			totalDonationAmount = args.totalDonationAmount,
			source = "robux",
		}
		local staggerDelay = notifStaggerIndex * 0.5
		notifStaggerIndex += 1
		task.delay(5, function()
			notifStaggerIndex = math.max(0, notifStaggerIndex - 1)
		end)

		task.delay(staggerDelay, function()
			notifNetwork:fireAllClients(payload)
			log:info("Robux donation notification broadcast", {
				donor = args.logDonor or args.filteredDonatorName,
				amount = amount,
				rank = args.newRank,
				staggerMs = math.floor(staggerDelay * 1000),
			})

			local robloxUserId = args.robloxUserId
			if robloxUserId and donationEffectService and type(donationEffectService.playRobuxDonation) == "function" then
				local donor = Players:GetPlayerByUserId(robloxUserId)
				if donor then
					local okEffect, errEffect = pcall(function()
						return donationEffectService:playRobuxDonation(donor, amount)
					end)
					if not okEffect then
						log:warn("Robux donation effect failed", {
							player = donor.Name,
							amount = amount,
							error = tostring(errEffect),
						})
					end
				end
			end
		end)
	end

	function service:_pollNotifications()
		if not isCashDonationEnabled() then
			return
		end
		if not isDonationHttpReady() then
			return
		end
		if not isLicenseDonationAllowed() then
			return
		end
		if _pollRunning then
			if os.clock() - _pollStartedAt > POLL_WATCHDOG_TIMEOUT then
				log:error("Notification poll watchdog reset stuck poll", {
					elapsed = os.clock() - _pollStartedAt,
				})
				_pollRunning = false
			else
				return
			end
		end
		_pollRunning = true
		_pollStartedAt = os.clock()

		task.spawn(function()
			local function finishPoll()
				_pollRunning = false
			end
			local cursorQuery: { [string]: string } = {
				limit = "50",
			}
			if notificationCursor ~= "" then
				cursorQuery.cursor = notificationCursor
			end
			local url = buildV2Url("notifications", cursorQuery)
			local ok, res = httpGet(url)
			if not ok then
				consecutiveFailures += 1
				local backoff = getNotifFailureBackoff()
				log:warn("HTTP gagal (notifications v2)", {
					error = res,
					consecutiveFailures = consecutiveFailures,
					backoff = backoff,
					nextPollDelay = math.max(Config.Donation.NOTIF_POLL_INTERVAL, backoff),
				})
				finishPoll()
				return
			end
			local hadNewDonations = false
			local success = pcall(function()
			local json = HttpService:JSONDecode(res)
			local items = if type(json) == "table" and json.ok then (json.items or json.data) else nil
			if type(items) ~= "table" then
				return
			end
			if type(json.next_cursor) == "string" and json.next_cursor ~= "" then
				notificationCursor = json.next_cursor
			end
			-- Phase 1: Filter valid items + do fast ops (no yield)
			local validItems = {}
			for _, item in ipairs(items) do
				if type(item) ~= "table" then
					continue
				end
				local notifId = tostring(item.id or "")
				local ts = tonumber(item.unix_timestamp) or 0
				if notificationSkipBeforeUnix > 0 and ts < notificationSkipBeforeUnix then
					if notifId ~= "" then
						markNotifProcessed(notifId)
					end
					continue
				end
				if notifId ~= "" and processedNotifIds[notifId] then
					continue
				end
				local amount = tonumber(item.amount_raw) or 0
				if amount < Config.Donation.MIN_AMOUNT then
					if notifId ~= "" then
						markNotifProcessed(notifId)
					end
					continue
				end
				-- Fast: leaderboard search (no yield)
				local donatorName = getItemProviderName(item)
				local providerRobloxUsername = getItemRobloxUsernameOrProviderName(item)
				local providerRobloxUserId = tonumber(item.roblox_user_id)
				local newRank: number? = nil
				local matchedEntry: DonationEntry? = nil
				for _, entry in ipairs(cachedLeaderboard.allTime) do
					local rn = entry.robloxUsername
					if providerRobloxUsername and rn and rn:lower() == providerRobloxUsername:lower() then
						newRank = entry.rank
						matchedEntry = entry
						break
					end
					if rn and rn:lower() == donatorName:lower() then
						newRank = entry.rank
						matchedEntry = entry
						break
					end
					if entry.saweriaName:lower() == donatorName:lower() then
						newRank = entry.rank
						matchedEntry = entry
						break
					end
				end
				table.insert(validItems, {
					item = item,
					notifId = notifId,
					ts = ts,
					amount = amount,
					donatorName = donatorName,
					providerRobloxUsername = providerRobloxUsername,
					providerRobloxUserId = providerRobloxUserId,
					newRank = newRank,
					matchedEntry = matchedEntry,
				})
			end

			-- Phase 2: Parallelize slow ops (filter + resolve) for all valid items
			local resolved = {}
			local pending = #validItems
			for i, info in ipairs(validItems) do
				resolved[i] = {}
				task.spawn(function()
					local okResolve, resolveErr = pcall(function()
						local robloxUsername = (info.matchedEntry and info.matchedEntry.robloxUsername) or info.providerRobloxUsername
						local robloxUserId = info.providerRobloxUserId
							or (info.matchedEntry and info.matchedEntry.robloxUserId)
							or resolveRobloxUserId(robloxUsername)
						local totalDonationAmount = info.matchedEntry and info.matchedEntry.totalAmount or nil
						local textFilterUserId = resolveTextFilterUserId(robloxUserId)
						local filteredDonatorName = filterForBroadcast(textFilterUserId, info.donatorName, 64)
							or getProviderDonorFallback()
						local resolvedUsername, resolvedDisplayName = nil, nil
						if robloxUserId then
							resolvedUsername, resolvedDisplayName = getRobloxUserInfo(robloxUserId)
							robloxUsername = robloxUsername or resolvedUsername
						end
						local rawMessage = cleanOptionalMessage(info.item.message, 180)
						local filteredMessage = filterForBroadcast(textFilterUserId, rawMessage, 180)
						if rawMessage and not filteredMessage then
							filteredMessage = censoredMessageFallback(rawMessage)
							log:warn("Donation message filter failed; using censored fallback", {
								id = info.notifId,
								donor = info.donatorName,
								userId = textFilterUserId,
							})
						end
						resolved[i] = {
							filteredDonatorName = filteredDonatorName,
							amount = info.amount,
							message = filteredMessage,
							newRank = info.newRank,
							robloxUsername = robloxUsername,
							robloxUserId = robloxUserId,
							robloxDisplayName = resolvedDisplayName,
							totalDonationAmount = totalDonationAmount,
							logDonor = info.donatorName,
							notifId = info.notifId,
							ts = info.ts,
						}
					end)
					if not okResolve then
						log:warn("Notification resolve worker failed", {
							id = info.notifId,
							error = tostring(resolveErr),
						})
					end
					pending -= 1
				end)
			end
			-- Wait for all parallel resolves to complete
			while pending > 0 do
				task.wait()
			end

			-- Phase 3: Fire notifications in order (staggered by fireCashDonationPresentation)
			for i, data in ipairs(resolved) do
				if data and data.filteredDonatorName then
					fireCashDonationPresentation(data)
					if data.notifId ~= "" then
						markNotifProcessed(data.notifId)
					end
					hadNewDonations = true
				end
			end
		end)
		if not success then
			consecutiveFailures += 1
			log:warn("Gagal parse notifications response", {
				consecutiveFailures = consecutiveFailures,
			})
			finishPoll()
			return
		end
		-- Sukses -> reset consecutive failures segera
		if consecutiveFailures > 0 then
			log:info("Notifications endpoint recovered", {
				recoveredAfter = consecutiveFailures .. " consecutive failures",
			})
		end
		consecutiveFailures = 0
		notificationSkipBeforeUnix = 0
		-- Jika ada donasi baru: aktifkan burst mode + refresh leaderboard segera
		if hadNewDonations then
			lastNotifReceivedAt = os.time()
			log:debug("Burst mode activated — new donation detected")
			-- Trigger leaderboard refresh async dengan debounce agar rank data segera up-to-date
			-- tanpa blocking notification poll berikutnya. Debounce prevents multiple rapid refreshes.
			local now = os.time()
			if not _leaderboardRefreshQueued and (now - _lastLeaderboardRefreshAt) >= LEADERBOARD_REFRESH_DEBOUNCE then
				_leaderboardRefreshQueued = true
				task.spawn(function()
					local lbOk, lbErr = pcall(function()
						service:_pollLeaderboard()
					end)
					if not lbOk then
						log:warn("Async leaderboard refresh failed", { error = tostring(lbErr) })
					end
					_lastLeaderboardRefreshAt = os.time()
					_leaderboardRefreshQueued = false
				end)
			else
				log:debug("Leaderboard refresh skipped (debounced)", {
					timeSinceLastRefresh = now - _lastLeaderboardRefreshAt,
					debounceWindow = LEADERBOARD_REFRESH_DEBOUNCE,
				})
			end
		end
		finishPoll()
		end)
	end
	-- Public API
	function service:getLeaderboard(): DonationLeaderboardPayload
		return cachedLeaderboard
	end
	local function resolveDisplayName(player: Player): string
		local displayName = player.DisplayName
		if profileRepository and type(profileRepository.load) == "function" then
			local profileResult = profileRepository:load(player.UserId)
			if profileResult.ok then
				local override = profileResult.value.displayNameOverride
				if type(override) == "string" and override ~= "" then
					displayName = override
				end
			end
		end
		return displayName
	end

	local function fetchDonorCashProfile(userId: number, username: string): (number, number?)
		local now = os.clock()
		-- Phase 1: Negative cache check — skip silently kalau Worker baru saja fail untuk userId ini.
		local failEntry = donorFailureCache[userId]
		if failEntry then
			if failEntry.expiresAt > now then
				return 0, nil
			end
			donorFailureCache[userId] = nil
		end

		local cached = donorCashCache[userId]
		if cached and cached.expiresAt > now then
			return cached.total, cached.rank
		end

		local url = buildV2Url(string.format("players/%d/cash", userId), {
			username = username,
		})
		if url == "" then
			return 0, nil
		end

		local ok, body = httpGet(url)
		if not ok then
			-- Phase 1: Catat fail supaya caller berikutnya (refreshAll, leaderboard poll, dll) skip selama TTL.
			donorFailureCache[userId] = {
				expiresAt = now + DONOR_PROFILE_FAILURE_CACHE_TTL,
			}
			log:warn("Donor profile API failed", { userId = userId, error = body })
			return 0, nil
		end

		local success, decoded = pcall(function()
			return HttpService:JSONDecode(body)
		end)
		if not success or type(decoded) ~= "table" or decoded.ok ~= true then
			-- Phase 1: Parse fail juga di-cache (response yang konsisten malformed = gak perlu retry tiap 3-5s).
			donorFailureCache[userId] = {
				expiresAt = now + DONOR_PROFILE_FAILURE_CACHE_TTL,
			}
			log:warn("Donor profile API parse failed", { userId = userId })
			return 0, nil
		end

		-- Phase 1: Success path — bersihkan negative entry biar next fail akan di-record lagi.
		donorFailureCache[userId] = nil
		local total = math.max(0, math.floor(tonumber(decoded.cash_total) or 0))
		local rankValue = tonumber(decoded.cash_rank)
		local rank = if rankValue and rankValue >= 1 then math.floor(rankValue) else nil
		donorCashCache[userId] = {
			total = total,
			rank = rank,
			expiresAt = now + (Config.Donation.DONOR_PROFILE_CACHE_TTL or 45),
		}
		return total, rank
	end

	local function resolveRobuxDonationRank(userId: number, username: string): number?
		if not donationLeaderboardRepository or type(donationLeaderboardRepository.getRobuxLeaderboard) ~= "function" then
			return nil
		end
		local lookupLimit = Config.Donation.DONOR_PROFILE_RANK_LOOKUP_LIMIT or 100
		local result = donationLeaderboardRepository:getRobuxLeaderboard(lookupLimit)
		if not result.ok or type(result.value) ~= "table" then
			return nil
		end
		local lowerName = username:lower()
		for rank, entry in ipairs(result.value) do
			local entryUserId = tonumber(entry.userId)
			if entryUserId and entryUserId == userId then
				return rank
			end
			local entryUsername = type(entry.username) == "string" and entry.username or nil
			if entryUsername and entryUsername:lower() == lowerName then
				return rank
			end
		end
		return nil
	end

	-- Same data path as workspace leaderboard + assignRobuxTopDonate (GetSortedAsync page).
	local function resolveRobuxFromLeaderboard(userId: number, username: string): (number, number?)
		if not donationLeaderboardRepository or type(donationLeaderboardRepository.getRobuxLeaderboard) ~= "function" then
			return 0, nil
		end
		local limit = math.max(Config.Leaderboards.ROBUX_LIMIT, Config.Donation.DONOR_PROFILE_RANK_LOOKUP_LIMIT or 100)
		local result = donationLeaderboardRepository:getRobuxLeaderboard(limit)
		if not result.ok or type(result.value) ~= "table" then
			return 0, nil
		end
		local lowerName = username:lower()
		for rank, entry in ipairs(result.value) do
			local entryUserId = tonumber(entry.userId)
			if (entryUserId and entryUserId == userId)
				or (
					type(entry.username) == "string"
					and entry.username:lower() == lowerName
				)
			then
				return math.max(0, math.floor(tonumber(entry.total) or 0)), rank
			end
		end
		return 0, nil
	end

	local function matchLeaderboardEntryToPlayer(
		entry: DonationEntry,
		userId: number,
		lowerName: string
	): boolean
		local resolvedUserId = entry.robloxUserId
		if not resolvedUserId then
			local robloxName = cleanRobloxUsername(entry.robloxUsername)
			if robloxName then
				resolvedUserId = resolveRobloxUserId(robloxName)
			end
		end
		if resolvedUserId and resolvedUserId == userId then
			return true
		end
		for _, candidate in ipairs({
			cleanRobloxUsername(entry.robloxUsername),
			cleanRobloxUsername(entry.saweriaName),
		}) do
			if candidate and candidate:lower() == lowerName then
				return true
			end
		end
		return false
	end

	local function resolveSaweriaFromCachedLeaderboard(userId: number, username: string): (number, number?)
		local lowerName = username:lower()
		for rank, entry in ipairs(cachedLeaderboard.allTime) do
			if matchLeaderboardEntryToPlayer(entry, userId, lowerName) then
				return math.max(0, math.floor(tonumber(entry.totalAmount) or 0)), rank
			end
		end
		return 0, nil
	end

	local function resolveCashFromWorkspaceLeaderboard(userId: number, username: string): (number, number?)
		local lowerName = username:lower()
		local limit = math.max(
			Config.Leaderboards.SAWERIA_LIMIT,
			Config.Donation.DONOR_PROFILE_RANK_LOOKUP_LIMIT or 100
		)
		local ok, entriesOrErr = pcall(function()
			return service:getWorkspaceSaweriaLeaderboard(limit)
		end)
		if not ok or type(entriesOrErr) ~= "table" then
			return 0, nil
		end
		for index, entry in ipairs(entriesOrErr) do
			if type(entry) ~= "table" then
				continue
			end
			local entryUserId = tonumber(entry.userId)
			local entryUsername = type(entry.username) == "string" and entry.username or nil
			local matched = (entryUserId and entryUserId == userId)
				or (entryUsername and entryUsername:lower() == lowerName)
			if matched then
				local total = math.max(0, math.floor(tonumber(entry.total) or 0))
				local rank = math.floor(tonumber(entry.rank) or index)
				return total, rank
			end
		end
		return 0, nil
	end

	local function resolveManualBagibagiTotal(userId: number): number
		local adjMap = Config.Donation and Config.Donation.MANUAL_BAGIBAGI_ADJUSTMENTS
		if type(adjMap) ~= "table" then
			return 0
		end
		return math.max(0, math.floor(tonumber(adjMap[userId]) or 0))
	end

	-- Shared path for donation panel, overhead payload, and leaderstats Cash column.
	function service:getPlayerCashStats(userId: number, username: string): (number, number?)
		local cached = donorCashCache[userId]
		-- Jangan pakai cache rank-only dengan total 0: itu bikin panel/leaderstats
		-- stuck di #1 / 0 sementara overhead chip rank tetap tampil.
		if cached and cached.expiresAt > os.clock() and cached.total > 0 then
			return cached.total, cached.rank
		end

		local cashTotal, cashRank = resolveSaweriaFromCachedLeaderboard(userId, username)
		if cashTotal <= 0 then
			local workspaceTotal, workspaceRank = resolveCashFromWorkspaceLeaderboard(userId, username)
			cashTotal = workspaceTotal
			cashRank = cashRank or workspaceRank
		end

		-- Manual adjustment: local, cheap source — check BEFORE any API call.
		-- Prevents slow HTTP fetchDonorCashProfile blocking overhead payload build
		-- when player has manual donations (e.g. /donatebagi).
		local manualTotal = resolveManualBagibagiTotal(userId)
		if manualTotal > cashTotal then
			cashTotal = manualTotal
		end

		-- Phase 3: Skip API call kalau player belum pernah donasi DAN local lookup juga miss.
		if
			cashTotal <= 0
			and Config.Donation.SKIP_API_FOR_UNKNOWN_DONORS ~= false
			and not knownDonors[userId]
		then
			return 0, nil
		end
		if cashTotal <= 0 then
			local apiTotal, apiRank = fetchDonorCashProfile(userId, username)
			cashTotal = apiTotal
			if not cashRank then
				cashRank = apiRank
			end
		end

		if cashTotal > 0 then
			donorCashCache[userId] = {
				total = cashTotal,
				rank = cashRank,
				expiresAt = os.clock() + (Config.Donation.DONOR_PROFILE_CACHE_TTL or 45),
			}
			-- Phase 3: Mark as known donor (cashTotal > 0 dari any source).
			markKnownDonor(userId)
		end

		-- Push cash value to OverheadService's fast cache so leaderstats/overhead
		-- update without blocking on the next buildPayload.
		if overheadService and type(overheadService.setCashDonated) == "function" then
			overheadService:setCashDonated(userId, cashTotal)
		end

		return cashTotal, cashRank
	end

	function service:addManualCashAdjustment(
		userId: number,
		username: string?,
		deltaIdr: number
	): (boolean, string, number?)
		local delta = math.floor(tonumber(deltaIdr) or 0)
		if userId <= 0 or delta == 0 then
			return false, "invalid_amount", nil
		end

		local adjMap = Config.Donation and Config.Donation.MANUAL_BAGIBAGI_ADJUSTMENTS
		if type(adjMap) ~= "table" then
			return false, "config_missing", nil
		end

		local nextValue = 0
		if manualBagibagiRepository and type(manualBagibagiRepository.adjust) == "function" then
			local persistResult = manualBagibagiRepository:adjust(userId, delta)
			if not persistResult.ok then
				return false, tostring(persistResult.error), nil
			end
			nextValue = persistResult.value
		else
			nextValue = math.max(0, math.floor(tonumber(adjMap[userId]) or 0) + delta)
		end

		if nextValue <= 0 then
			adjMap[userId] = nil
		else
			adjMap[userId] = nextValue
		end
		-- Phase 3: Admin/owner manual adjust = mark as known donor (skip API on future lookups).
		markKnownDonor(userId)
		local resolvedUsername = resolveUsernameForUserId(userId, username)
		local entry = findAllTimeEntryByUserId(userId, resolvedUsername)
		if entry then
			entry.totalAmount = math.max(0, math.floor((tonumber(entry.totalAmount) or 0) + delta))
			if not entry.robloxUserId then
				entry.robloxUserId = userId
			end
			if type(entry.robloxUsername) ~= "string" or entry.robloxUsername == "" then
				entry.robloxUsername = resolvedUsername
			end
		else
			table.insert(cachedLeaderboard.allTime, {
				rank = 0,
				saweriaName = resolvedUsername,
				robloxUsername = resolvedUsername,
				robloxUserId = userId,
				totalAmount = adjMap[userId],
				lastDonationAt = "",
			})
		end

		syncBagibagiLeaderboardFromCache(true)
		invalidateDonorCashCache(userId)
		invalidateOverheadRankCaches(userId)
		if overheadService and type(overheadService.setCashDonated) == "function" then
			overheadService:setCashDonated(userId, adjMap[userId])
		end
		local cashRank = select(2, service:getPlayerCashStats(userId, resolvedUsername))
		if type(cashRank) == "number" and cashRank <= Config.Donation.LEADERBOARD_LIMIT then
			assignPlayer(resolvedUsername, cashRank)
		end
		local onlinePlayer = Players:GetPlayerByUserId(userId)
		if onlinePlayer then
			service:refreshPlayerOverhead(onlinePlayer)
		end
		return true, "", adjMap[userId]
	end

	function service:removeManualCashAdjustment(
		userId: number,
		amountIdr: number?
	): (boolean, string, number?)
		if userId <= 0 then
			return false, "invalid_user", nil
		end

		local adjMap = Config.Donation and Config.Donation.MANUAL_BAGIBAGI_ADJUSTMENTS
		if type(adjMap) ~= "table" then
			return false, "config_missing", nil
		end

		local current = math.floor(tonumber(adjMap[userId]) or 0)
		if current <= 0 and manualBagibagiRepository and type(manualBagibagiRepository.loadAll) == "function" then
			local loaded = manualBagibagiRepository:loadAll()
			if loaded.ok and type(loaded.value[userId]) == "number" then
				current = loaded.value[userId]
				adjMap[userId] = current
			end
		end
		if current <= 0 then
			return false, "no_adjustment", nil
		end

		local removeAmount = if amountIdr == nil then current else math.floor(tonumber(amountIdr) or 0)
		if removeAmount <= 0 then
			return false, "invalid_amount", nil
		end

		local nextValue = 0
		if manualBagibagiRepository and type(manualBagibagiRepository.remove) == "function" then
			local persistResult = manualBagibagiRepository:remove(userId, removeAmount)
			if not persistResult.ok then
				return false, tostring(persistResult.error), nil
			end
			nextValue = persistResult.value
		else
			nextValue = math.max(0, current - removeAmount)
		end

		if nextValue <= 0 then
			adjMap[userId] = nil
		else
			adjMap[userId] = nextValue
		end

		local entry = findAllTimeEntryByUserId(userId, nil)
		if entry then
			entry.totalAmount = math.max(0, math.floor((tonumber(entry.totalAmount) or 0) - removeAmount))
		end

		syncBagibagiLeaderboardFromCache(true)
		invalidateDonorCashCache(userId)
		if overheadService and type(overheadService.setCashDonated) == "function" then
			overheadService:setCashDonated(userId, nextValue)
		end
		return true, "", nextValue
	end

	type PresentDonationOpts = {
		testOnly: boolean?,
	}

	-- Owner manual: leaderboard entry + full donation card/VFX (unlike addcash).
	function service:presentCashDonation(
		userId: number,
		username: string?,
		amount: number,
		message: string?,
		opts: PresentDonationOpts?
	): (boolean, string)
		local delta = math.floor(tonumber(amount) or 0)
		if userId <= 0 or delta <= 0 then
			return false, "invalid_amount"
		end
		local testOnly = opts ~= nil and opts.testOnly == true

		local resolvedUsername = resolveUsernameForUserId(userId, username)
		local resolvedUsernameInfo, resolvedDisplayName = getRobloxUserInfo(userId)
		local robloxUsername = resolvedUsernameInfo or resolvedUsername
		local matchedEntry = findAllTimeEntryByUserId(userId, robloxUsername)
		local newRank = if testOnly then nil else matchedEntry and matchedEntry.rank or nil
		local baseTotal = math.floor(tonumber(matchedEntry and matchedEntry.totalAmount) or 0)
		local totalDonationAmount = if testOnly then baseTotal + delta else matchedEntry and matchedEntry.totalAmount or nil

		local onlinePlayer = Players:GetPlayerByUserId(userId)
		if onlinePlayer and onlinePlayer.DisplayName ~= "" then
			resolvedDisplayName = onlinePlayer.DisplayName
		end

		-- For manual donations, use the resolved Roblox identity as the donor name
		-- instead of the generic "Bagibagi Donor" fallback.
		local donorName = resolvedDisplayName or robloxUsername or getProviderDonorFallback()
		local filteredDonatorName = filterForBroadcast(userId, donorName, 64)
			or donorName

		local rawMessage = cleanOptionalMessage(message, 180)
		local filteredMessage = filterForBroadcast(userId, rawMessage, 180)
		if rawMessage and not filteredMessage then
			filteredMessage = censoredMessageFallback(rawMessage)
		end

		fireCashDonationPresentation({
			filteredDonatorName = filteredDonatorName,
			amount = delta,
			message = filteredMessage,
			newRank = newRank,
			robloxUsername = robloxUsername,
			robloxUserId = userId,
			robloxDisplayName = resolvedDisplayName,
			totalDonationAmount = totalDonationAmount,
			logDonor = robloxUsername,
			testOnly = testOnly,
		})
		return true, ""
	end

	function service:testCashDonation(
		userId: number,
		username: string?,
		amount: number,
		message: string?
	): (boolean, string)
		return self:presentCashDonation(userId, username, amount, message, { testOnly = true })
	end

	function service:donateCashManual(
		userId: number,
		username: string?,
		deltaIdr: number,
		message: string?
	): (boolean, string, number?)
		local ok, err, totalAdj = service:addManualCashAdjustment(userId, username, deltaIdr)
		if not ok then
			return false, err, nil
		end
		local presentOk, presentErr = service:presentCashDonation(userId, username, deltaIdr, message)
		if not presentOk then
			return true, presentErr, totalAdj
		end
		return true, "", totalAdj
	end

	function service:addManualBagibagiAdjustment(
		userId: number,
		username: string?,
		deltaIdr: number
	): (boolean, string, number?)
		return self:addManualCashAdjustment(userId, username, deltaIdr)
	end

	function service:removeManualBagibagiAdjustment(userId: number, amountIdr: number?): (boolean, string, number?)
		return self:removeManualCashAdjustment(userId, amountIdr)
	end

	function service:presentBagibagiDonation(
		userId: number,
		username: string?,
		amount: number,
		message: string?
	): (boolean, string)
		return self:presentCashDonation(userId, username, amount, message)
	end

	function service:donateBagibagiManual(
		userId: number,
		username: string?,
		deltaIdr: number,
		message: string?
	): (boolean, string, number?)
		return self:donateCashManual(userId, username, deltaIdr, message)
	end

	function service:presentRobuxDonation(
		userId: number,
		username: string?,
		amount: number,
		message: string?,
		opts: PresentDonationOpts?
	): (boolean, string)
		local delta = math.floor(tonumber(amount) or 0)
		if userId <= 0 or delta <= 0 then
			return false, "invalid_amount"
		end
		local testOnly = opts ~= nil and opts.testOnly == true

		local resolvedUsername = resolveUsernameForUserId(userId, username)
		local resolvedUsernameInfo, resolvedDisplayName = getRobloxUserInfo(userId)
		local robloxUsername = resolvedUsernameInfo or resolvedUsername
		local baseTotal, currentRank = resolveRobuxFromLeaderboard(userId, robloxUsername)
		local totalDonationAmount = if testOnly then baseTotal + delta else baseTotal
		local newRank = if testOnly then nil else currentRank

		local onlinePlayer = Players:GetPlayerByUserId(userId)
		if onlinePlayer and onlinePlayer.DisplayName ~= "" then
			resolvedDisplayName = onlinePlayer.DisplayName
		end

		local donorName = resolvedDisplayName or robloxUsername or ("User" .. tostring(userId))
		local filteredDonatorName = filterForBroadcast(userId, donorName, 64) or donorName

		local rawMessage = cleanOptionalMessage(message, 180)
		local filteredMessage = filterForBroadcast(userId, rawMessage, 180)
		if rawMessage and not filteredMessage then
			filteredMessage = censoredMessageFallback(rawMessage)
		end

		fireRobuxDonationPresentation({
			filteredDonatorName = filteredDonatorName,
			amount = delta,
			message = filteredMessage,
			newRank = newRank,
			robloxUsername = robloxUsername,
			robloxUserId = userId,
			robloxDisplayName = resolvedDisplayName,
			totalDonationAmount = totalDonationAmount,
			logDonor = robloxUsername,
			testOnly = testOnly,
		})
		return true, ""
	end

	function service:testRobuxDonation(
		userId: number,
		username: string?,
		amount: number,
		message: string?
	): (boolean, string)
		return self:presentRobuxDonation(userId, username, amount, message, { testOnly = true })
	end

	function service:donateRobuxManual(
		userId: number,
		username: string?,
		deltaRobux: number,
		message: string?
	): (boolean, string, number?)
		local ok, err = service:addManualRobuxAdjustment(userId, username, nil, deltaRobux)
		if not ok then
			return false, err, nil
		end
		markKnownDonor(userId)
		local presentOk, presentErr = service:presentRobuxDonation(userId, username, deltaRobux, message)
		local resolvedUsername = resolveUsernameForUserId(userId, username)
		local totalDonationAmount = select(1, resolveRobuxFromLeaderboard(userId, resolvedUsername))
		if not presentOk then
			return true, presentErr, totalDonationAmount
		end
		return true, "", totalDonationAmount
	end

	function service:addManualRobuxAdjustment(
		userId: number,
		username: string?,
		displayName: string?,
		deltaRobux: number
	): (boolean, string)
		local delta = math.floor(tonumber(deltaRobux) or 0)
		if userId <= 0 or delta == 0 then
			return false, "invalid_amount"
		end
		if not donationLeaderboardRepository or type(donationLeaderboardRepository.adjustRobuxTotal) ~= "function" then
			return false, "repository_unavailable"
		end

		local resolvedUsername = resolveUsernameForUserId(userId, username)
		local resolvedDisplayName = if type(displayName) == "string" and displayName ~= ""
			then displayName
			else resolvedUsername
		local player = Players:GetPlayerByUserId(userId)
		local thumbnail = if player then getUserThumbnail(userId) else ""

		local result = donationLeaderboardRepository:adjustRobuxTotal({
			userId = userId,
			username = resolvedUsername,
			displayName = resolvedDisplayName,
			thumbnail = thumbnail,
			amount = delta,
		})
		if not result.ok then
			return false, tostring(result.error)
		end

		local adjMap = Config.Donation and Config.Donation.MANUAL_ROBUX_ADJUSTMENTS
		if type(adjMap) == "table" and delta > 0 then
			adjMap[userId] = math.max(0, math.floor(tonumber(adjMap[userId]) or 0) + delta)
		end

		service:notifyWorkspaceLeaderboardsUpdated()
		return true, ""
	end

	function service:removeManualRobuxAdjustment(
		userId: number,
		amountRobux: number?
	): (boolean, string)
		if userId <= 0 then
			return false, "invalid_user"
		end
		if not donationLeaderboardRepository or type(donationLeaderboardRepository.adjustRobuxTotal) ~= "function" then
			return false, "repository_unavailable"
		end

		local removeAmount = math.floor(tonumber(amountRobux) or 0)
		if removeAmount <= 0 then
			local adjMap = Config.Donation and Config.Donation.MANUAL_ROBUX_ADJUSTMENTS
			if type(adjMap) == "table" and adjMap[userId] then
				removeAmount = math.floor(tonumber(adjMap[userId]) or 0)
			end
			if removeAmount <= 0
				and type(donationLeaderboardRepository.getPlayerRobuxTotal) == "function"
			then
				local totalResult = donationLeaderboardRepository:getPlayerRobuxTotal(userId)
				if totalResult.ok then
					removeAmount = math.max(0, math.floor(tonumber(totalResult.value) or 0))
				end
			end
		end
		if removeAmount <= 0 then
			return false, "nothing_to_remove"
		end

		local player = Players:GetPlayerByUserId(userId)
		local resolvedUsername = resolveUsernameForUserId(userId, if player then player.Name else nil)
		local result = donationLeaderboardRepository:adjustRobuxTotal({
			userId = userId,
			username = resolvedUsername,
			displayName = resolvedUsername,
			thumbnail = if player then getUserThumbnail(userId) else "",
			amount = -removeAmount,
		})
		if not result.ok then
			return false, tostring(result.error)
		end

		local adjMap = Config.Donation and Config.Donation.MANUAL_ROBUX_ADJUSTMENTS
		if type(adjMap) == "table" then
			local nextValue = math.max(0, math.floor(tonumber(adjMap[userId]) or 0) - removeAmount)
			if nextValue <= 0 then
				adjMap[userId] = nil
			else
				adjMap[userId] = nextValue
			end
		end

		service:notifyWorkspaceLeaderboardsUpdated()
		return true, ""
	end

	function service:getPlayerCashTotal(userId: number): number
		local player = Players:GetPlayerByUserId(userId)
		if player then
			return select(1, service:getPlayerCashStats(userId, player.Name))
		end
		for _, entry in ipairs(cachedLeaderboard.allTime) do
			local resolvedUserId = entry.robloxUserId or resolveRobloxUserId(entry.robloxUsername or entry.saweriaName)
			if resolvedUserId == userId then
				return tonumber(entry.totalAmount) or 0
			end
		end
		return 0
	end

	function service:getDonorProfile(player: Player): DonorProfilePayload
		local userId = player.UserId
		local username = player.Name
		local robuxTotal = 0
		local robuxRank: number? = nil
		if isHiddenRobuxUser(userId) then
			robuxTotal = service:getSessionRobuxTotal(userId)
		else
			robuxTotal, robuxRank = resolveRobuxFromLeaderboard(userId, username)
			if robuxTotal <= 0 and donationLeaderboardRepository
				and type(donationLeaderboardRepository.getPlayerRobuxTotal) == "function"
			then
				local robuxResult = donationLeaderboardRepository:getPlayerRobuxTotal(userId)
				if robuxResult.ok then
					robuxTotal = math.max(0, math.floor(tonumber(robuxResult.value) or 0))
				end
			end
			if not robuxRank and robuxTotal > 0 then
				robuxRank = resolveRobuxDonationRank(userId, username)
			end
		end
		local cashTotal, cashRank = service:getPlayerCashStats(userId, username)
		local profile = {
			userId = userId,
			username = username,
			displayName = resolveDisplayName(player),
			robuxTotal = robuxTotal,
			robuxRank = robuxRank,
			cashTotal = cashTotal,
			cashRank = cashRank,
		}
		log:debug("donor profile built", {
			userId = userId,
			robuxTotal = robuxTotal,
			robuxRank = robuxRank,
			cashTotal = cashTotal,
			cashRank = cashRank,
		})
		return profile
	end

	function service:invalidateDonorProfileCache(userId: number?)
		invalidateDonorCashCache(userId)
	end
	function service:onLeaderboardUpdated(callback: () -> ())
		table.insert(leaderboardUpdatedCallbacks, callback)
	end
	function service:notifyWorkspaceLeaderboardsUpdated()
		for _, callback in ipairs(leaderboardUpdatedCallbacks) do
			task.spawn(callback)
		end
	end
	function service:getWorkspaceSaweriaLeaderboard(limit: number?): { any }
		local resolvedLimit = math.clamp(
			math.floor(tonumber(limit) or Config.Leaderboards.SAWERIA_LIMIT),
			1,
			Config.Leaderboards.MAX_LIMIT
		)
		local sortedAllTime = table.clone(cachedLeaderboard.allTime)
		table.sort(sortedAllTime, function(a, b)
			return (tonumber(a.totalAmount) or 0) > (tonumber(b.totalAmount) or 0)
		end)
		local entries = {}
		for _, entry in ipairs(sortedAllTime) do
			if #entries >= resolvedLimit then
				break
			end

			local username = cleanRobloxUsername(entry.robloxUsername) or cleanRobloxUsername(entry.saweriaName) or ""
			local userId = entry.robloxUserId or resolveRobloxUserId(username)
			if userId and isHiddenDonationUser(userId) then
				continue
			end
			local displayName = if type(entry.saweriaName) == "string" and entry.saweriaName ~= ""
				then entry.saweriaName
				else "Unknown donor"
			local thumbnail = ""
			if userId then
				local resolvedUsername, resolvedDisplayName = getRobloxUserInfo(userId)
				username = resolvedUsername or username
				displayName = resolvedDisplayName or displayName
				thumbnail = getUserThumbnail(userId)
			end

			table.insert(entries, {
				rank = #entries + 1,
				saweriaName = entry.saweriaName,
				userId = userId or 0,
				username = username,
				displayName = displayName,
				thumbnail = thumbnail,
				total = entry.totalAmount,
				lastDonationAt = entry.lastDonationAt,
				isLinked = userId ~= nil,
			})
		end
		return entries
	end
	function service:getWorkspaceDailySaweriaLeaderboard(limit: number?): { any }
		local resolvedLimit = math.clamp(
			math.floor(tonumber(limit) or Config.Leaderboards.SAWERIA_LIMIT),
			1,
			Config.Leaderboards.MAX_LIMIT
		)
		local entries = {}
		for _, entry in ipairs(cachedLeaderboard.daily) do
			if #entries >= resolvedLimit then
				break
			end

			local username = cleanRobloxUsername(entry.robloxUsername) or cleanRobloxUsername(entry.saweriaName) or ""
			local userId = entry.robloxUserId or resolveRobloxUserId(username)
			if userId and isHiddenDonationUser(userId) then
				continue
			end
			local displayName = if type(entry.saweriaName) == "string" and entry.saweriaName ~= ""
				then entry.saweriaName
				else "Unknown donor"
			local thumbnail = ""
			if userId then
				local resolvedUsername, resolvedDisplayName = getRobloxUserInfo(userId)
				username = resolvedUsername or username
				displayName = resolvedDisplayName or displayName
				thumbnail = getUserThumbnail(userId)
			end

			table.insert(entries, {
				rank = #entries + 1,
				saweriaName = entry.saweriaName,
				userId = userId or 0,
				username = username,
				displayName = displayName,
				thumbnail = thumbnail,
				total = entry.totalAmount,
				lastDonationAt = entry.lastDonationAt,
				isLinked = userId ~= nil,
			})
		end
		return entries
	end
	-- Called from ShopController on a successful Robux donation.
	-- In-memory tracking; window WIB 00:01-23:59:59, reset otomatis setelah tengah malam WIB.
	function service:recordRobuxDonationDaily(record: {
		userId: number,
		username: string?,
		displayName: string?,
		thumbnail: string?,
		amount: number,
	})
		ensureRobuxDailyFresh()
		local now = os.time()
		if not StreakDomain.isWithinWibDailyDonationWindow(now) then
			return
		end
		local userId = tonumber(record.userId) or 0
		if userId <= 0 then
			return
		end
		if isHiddenRobuxUser(userId) then
			local hiddenAmount = tonumber(record.amount) or 0
			if hiddenAmount > 0 then
				sessionRobuxTotals[userId] = (sessionRobuxTotals[userId] or 0) + hiddenAmount
			end
			return
		end
		local amount = tonumber(record.amount) or 0
		if amount <= 0 then
			return
		end
		local existing = cachedDailyRobux[userId]
		if existing then
			existing.total = (tonumber(existing.total) or 0) + amount
			if record.username and record.username ~= "" then
				existing.username = record.username
			end
			if record.displayName and record.displayName ~= "" then
				existing.displayName = record.displayName
			end
			if record.thumbnail and record.thumbnail ~= "" then
				existing.thumbnail = record.thumbnail
			end
			existing.lastDonationAt = now
		else
			cachedDailyRobux[userId] = {
				userId = userId,
				username = record.username or "",
				displayName = record.displayName or record.username or "",
				thumbnail = record.thumbnail or "",
				total = amount,
				lastDonationAt = now,
			}
		end
	end
	function service:getSessionRobuxTotal(userId: number): number
		if not isHiddenRobuxUser(userId) then
			return 0
		end
		return math.max(0, math.floor(tonumber(sessionRobuxTotals[userId]) or 0))
	end

	function service:getWorkspaceDailyRobuxLeaderboard(limit: number?): { any }
		ensureRobuxDailyFresh()
		local windowStart, windowEnd = StreakDomain.getWibDailyDonationWindow(os.time())
		local resolvedLimit = math.clamp(
			math.floor(tonumber(limit) or Config.Leaderboards.ROBUX_LIMIT),
			1,
			Config.Leaderboards.MAX_LIMIT
		)
		local sorted = {}
		for _, entry in pairs(cachedDailyRobux) do
			if isHiddenRobuxUser(tonumber(entry.userId) or 0) then
				continue
			end
			local lastAt = tonumber(entry.lastDonationAt) or 0
			if lastAt < windowStart or lastAt > windowEnd then
				continue
			end
			table.insert(sorted, entry)
		end
		table.sort(sorted, function(a, b)
			local aTotal = tonumber(a.total) or 0
			local bTotal = tonumber(b.total) or 0
			if aTotal == bTotal then
				return (tonumber(a.lastDonationAt) or 0) < (tonumber(b.lastDonationAt) or 0)
			end
			return aTotal > bTotal
		end)
		local result = {}
		for _, entry in ipairs(sorted) do
			if #result >= resolvedLimit then
				break
			end
			table.insert(result, {
				rank = #result + 1,
				userId = entry.userId,
				username = entry.username,
				displayName = entry.displayName,
				thumbnail = entry.thumbnail,
				total = entry.total,
				lastDonationAt = entry.lastDonationAt,
			})
		end
		return result
	end
	-- forceRefresh: poll notif + leaderboard sekarang juga (debug / admin tool)
	function service:forceRefresh()
		log:info("Force refresh donasi dipanggil")
		local ok, err = pcall(function()
			self:_pollLeaderboard(true)
			self:_pollNotifications()
		end)
		if not ok then
			log:error("Force refresh error", { error = tostring(err) })
		end
	end
	-- Admin: link external provider name -> roblox username via POST ke sheets NameMap
	function service:linkDonor(saweriaName: string, robloxUsername: string): (boolean, string)
		local url = buildV2Url("donor-links")
		if url == "" then
			return false, "Donation API atau DonationApiSecret belum dikonfigurasi"
		end
		local cleanedSaweriaName = cleanProviderName(saweriaName)
		local cleanedRobloxUsername = cleanRobloxUsername(robloxUsername)
		if cleanedSaweriaName == "" or not cleanedRobloxUsername then
			return false, "missing_name"
		end
		local body = HttpService:JSONEncode({
			provider = getProviderKey(),
			provider_name = cleanedSaweriaName,
			bagibagi_name = cleanedSaweriaName,
			saweria_name = cleanedSaweriaName,
			roblox_username = cleanedRobloxUsername,
		})
		local ok, res = httpRequestOnce("PUT", url, body)
		if not ok then
			log:warn("linkDonor PUT gagal", { error = res })
			return false, res
		end
		-- Trigger refresh agar assignment langsung update
		task.delay(1, function()
			self:forceRefresh()
		end)
		log:info("Donor linked", { provider = getProviderName(), donor = cleanedSaweriaName, roblox = cleanedRobloxUsername })
		return true, ""
	end
	-- Player self-claim: assign external provider name ke diri sendiri
	function service:claimDonor(player: Player, saweriaName: string): (boolean, string)
		local userId = player.UserId
		local nowEpoch = os.time()
		cleanupClaimCooldowns(nowEpoch)
		-- Rate limit: 1x per hari
		local lastClaim = claimCooldowns[userId]
		if lastClaim and (nowEpoch - lastClaim) < Config.Donation.CLAIM_COOLDOWN then
			return false, "rate_limited"
		end
		-- Cari entry di leaderboard yang belum ter-assign dan namanya cocok (case-insensitive)
		local found = false
		local cleanedSaweriaName = cleanProviderName(saweriaName)
		for _, entry in ipairs(cachedLeaderboard.allTime) do
			if cleanProviderName(entry.saweriaName):lower() == cleanedSaweriaName:lower() then
				if entry.robloxUsername ~= nil then
					return false, "already_assigned"
				end
				found = true
				break
			end
		end
		if not found then
			return false, "not_found"
		end
		-- Link via sheets
		local ok, err = self:linkDonor(cleanedSaweriaName, player.Name)
		if not ok then
			return false, err
		end
		claimCooldowns[userId] = nowEpoch
		self:invalidateDonorProfileCache(userId)
		return true, ""
	end
	-- Force re-assign semua top 10 Saweria yang online sekarang. Bypass deduplication
	-- assignedRanks supaya kalau ada player yang stuck (rank di DataStore beda dari
	-- leaderboard), bisa dipaksa sync ulang. Dipakai oleh /verifyspender admin command.
	-- Returns: { checked, assigned, missing, entries } untuk reporting.
	function service:forceReassignTopSpenders(): {
		checked: number,
		assigned: number,
		missing: number,
		entries: { { rank: number, username: string, online: boolean } },
	}
		local cfg = Config.Donation
		local limit = cfg.LEADERBOARD_LIMIT
		local entries: { { rank: number, username: string, online: boolean } } = {}
		local assigned = 0
		local missing = 0
		-- Reset tracking biar applyLeaderboardDiff/assignPlayer treat semua sebagai "new".
		assignedRanks = {}
		for _, entry in ipairs(cachedLeaderboard.allTime) do
			if entry.rank > limit then
				continue
			end
			local username = cleanRobloxUsername(entry.robloxUsername)
			if not username or username == "" then
				continue
			end
			local lowerName = username:lower()
			local isOnline = false
			for _, p in ipairs(Players:GetPlayers()) do
				if p.Name:lower() == lowerName then
					isOnline = true
					break
				end
			end
			table.insert(entries, { rank = entry.rank, username = username, online = isOnline })
			if isOnline then
				assignedRanks[lowerName] = entry.rank
				assignPlayer(username, entry.rank)
				assigned += 1
			else
				missing += 1
			end
		end
		log:info("Force reassign top spenders", {
			checked = #entries,
			assigned = assigned,
			missing = missing,
		})
		return {
			checked = #entries,
			assigned = assigned,
			missing = missing,
			entries = entries,
		}
	end
	-- Helper: trigger overhead refresh untuk player. Dipakai oleh /verifyspender
	-- supaya Robux top 10 yang nggak overlap dengan Saweria top 10 ikut ke-refresh.
	function service:refreshPlayerOverhead(player: Player)
		-- Refresh cash cache first so the overhead rebuild sees the latest value
		-- (cashDonated is now fetched asynchronously, not in buildPayload).
		if overheadService and type(overheadService.setCashDonated) == "function" then
			local cashTotal = select(1, service:getPlayerCashStats(player.UserId, player.Name))
			overheadService:setCashDonated(player.UserId, cashTotal)
		end
		if overheadController and type(overheadController.refreshPlayer) == "function" then
			overheadController:refreshPlayer(player)
		end
	end
	-- Assign overhead tag ke player yang baru join (jika mereka ada di leaderboard)
	function service:onPlayerAdded(player: Player)
		local lowerName = player.Name:lower()
		local rank = assignedRanks[lowerName]
		if rank then
			-- Delay sedikit agar DataStore player sudah siap
			task.delay(3, function()
				if player and player.Parent then
					assignPlayer(player.Name, rank)
				end
			end)
		end
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		claimCooldowns[player.UserId] = nil
	end)
	-- Adaptive polling helper
	-- Saat ada donasi baru terdeteksi, poll dipercepat ke NOTIF_BURST_INTERVAL
	-- selama NOTIF_BURST_WINDOW detik, lalu kembali ke NOTIF_POLL_INTERVAL normal.
	local function getNotifPollDelay(): number
		local cfg = Config.Donation
		local timeSinceLast = os.time() - lastNotifReceivedAt
		local failureBackoff = getNotifFailureBackoff()
		if timeSinceLast < cfg.NOTIF_BURST_WINDOW then
			return math.max(cfg.NOTIF_BURST_INTERVAL, failureBackoff)
		end
		return math.max(cfg.NOTIF_POLL_INTERVAL, failureBackoff)
	end

	-- ── Public wrappers ───────────────────────────────────────────────────────
	-- Diperlukan agar BackgroundJobScheduler di Main.server.luau bisa register
	-- jobs via type-check `type(donationService.pollDonations) == "function"`.
	-- Tanpa ini, guard tersebut selalu false dan scheduler jadi dead code.
	function service:pollDonations()
		return service:_pollNotifications()
	end

	function service:refreshLeaderboard()
		return service:_pollLeaderboard()
	end

	function service:keepWarmPing()
		local pingUrl = buildV2Url("health")
		if pingUrl ~= "" then
			local ok, _ = httpGetOnce(pingUrl)
			if ok then
				log:debug("Keep-warm ping OK")
			else
				log:debug("Keep-warm ping failed (non-critical)")
			end
		end
	end

	-- ── Polling ownership guard (R2.1–R2.6) ─────────────────────────────────
	-- Polling is driven exclusively by the BackgroundJobScheduler jobs registered
	-- in Main.server.luau (donation_poll, leaderboard_refresh, keep_warm).
	-- Inline while-loops have been removed so there is exactly one owner per loop.
	-- _pollingStarted guards against a second start (hot-reload safety, R2.3/R2.4).
	local _pollingStarted = false

	-- startPolling: mark service as active. Rejects a second call so a hot-reload
	-- or duplicate require never spawns a second set of scheduler registrations
	-- (R2.3, R2.4). Returns false (already started) or true (started fresh).
	-- On scheduler start failure the caller logs an error and MUST NOT fall back
	-- to an inline loop (R2.6).
	function service:startPolling(): boolean
		if _pollingStarted then
			log:warn("startPolling called twice; ignoring — existing scheduler jobs preserved", {})
			return false
		end
		_pollingStarted = true
		log:info("DonationService polling started (scheduler-owned)")
		return true
	end

	-- stopPolling: clear the started flag for hot-reload teardown (R2.5).
	-- Scheduler teardown is handled by Main.server.luau (backgroundJobScheduler:stop()).
	-- No inline threads exist, so there is nothing to cancel here.
	function service:stopPolling()
		_pollingStarted = false
		log:info("DonationService polling stopped")
	end

	log:info("DonationService initialized", {
		notifPollInterval = Config.Donation.NOTIF_POLL_INTERVAL,
		notifBurstInterval = Config.Donation.NOTIF_BURST_INTERVAL,
		notifBurstWindow = Config.Donation.NOTIF_BURST_WINDOW,
		leaderboardPollInterval = Config.Donation.POLL_INTERVAL,
		httpTimeout = Config.Donation.HTTP_TIMEOUT,
		retryEnabled = Config.Donation.NOTIF_RETRY_ENABLED,
		keepWarmEnabled = Config.Donation.KEEP_WARM_ENABLED,
	})

	if manualBagibagiRepository and type(manualBagibagiRepository.loadAll) == "function" then
		task.spawn(function()
			local loaded = manualBagibagiRepository:loadAll()
			if not loaded.ok then
				log:warn("Manual Bagibagi hydrate failed", { error = loaded.error })
				return
			end
			local adjMap = Config.Donation and Config.Donation.MANUAL_BAGIBAGI_ADJUSTMENTS
			if type(adjMap) ~= "table" then
				return
			end
			local count = 0
			for userId, amount in pairs(loaded.value) do
				adjMap[userId] = amount
				count += 1
			end
			if count > 0 then
				syncBagibagiLeaderboardFromCache(true)
				log:info("Manual Bagibagi adjustments hydrated", { count = count })
			end
		end)
	end

	return service
end
return createDonationService
