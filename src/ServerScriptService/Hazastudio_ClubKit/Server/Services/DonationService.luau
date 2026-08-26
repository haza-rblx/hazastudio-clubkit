--!strict
-- Server/Services/DonationService.lua
-- Poll Donation API v2 (Cloudflare Worker) -> match donors -> update DataStore -> broadcast events.
-- Supports dual leaderboard: daily + all-time.
--
-- API v2: REST under {ApiUrl}/v2/* with Authorization: Bearer secret.
-- Reliability improvements:
-- - HTTP retry once before counting as failure (handle transient errors)
-- - Exponential backoff with lower cap -> faster recovery
-- - Batched leaderboard fetch (all-time + daily in one request)
-- - Cursor-based notification polling (no since drift)
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
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
local DonationEffectTierResolver = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DonationEffectTierResolver)
local TextFilterUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.TextFilterUtil)
type DonationEntry = Types.DonationEntry
type DonationNotifPayload = Types.DonationNotifPayload
type DonationLeaderboardPayload = Types.DonationLeaderboardPayload
type DonorProfilePayload = Types.DonorProfilePayload
type IOverheadRepository = Types.IOverheadRepository
type DonorCashCacheEntry = {
	total: number,
	rank: number?,
	expiresAt: number,
	-- Event-written entries (donation just applied / cross-server push) win over
	-- in-flight HTTP results that were issued before the donation landed. The
	-- monotonic guard in writeDonorCashCache uses these fields.
	source: string?,
	writtenAt: number?,
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
		notifAckRemote: RemoteEvent?,
		notifDisplayRemote: RemoteEvent?,
		notify: any,
		donationEffectService: any?,
		donationLeaderboardRepository: any?,
		profileRepository: any?,
		manualBagibagiRepository: any?,
		-- Optional: adaptive notif poll burst (setInterval on donation_poll).
		backgroundJobScheduler: any?,
		donationPollJobName: string?,
	}
)
	local repo = deps.repo
	local overheadController = deps.overheadController
	local overheadService = deps.overheadService
	local leaderboardNetwork = deps.leaderboardNetwork
	local notifNetwork = deps.notifNetwork
	local notifAckRemote = deps.notifAckRemote
	local notifDisplayRemote = deps.notifDisplayRemote
	local _notify = deps.notify
	local donationEffectService = deps.donationEffectService
	local donationLeaderboardRepository = deps.donationLeaderboardRepository
	local profileRepository = deps.profileRepository
	local manualBagibagiRepository = deps.manualBagibagiRepository
	local backgroundJobScheduler = deps.backgroundJobScheduler
	local donationPollJobName = if type(deps.donationPollJobName) == "string" and deps.donationPollJobName ~= ""
		then deps.donationPollJobName
		else "donation_poll"
	local log = Logger.new("DonationService")
	local donorCashCache: { [number]: DonorCashCacheEntry } = {}
	-- Phase 1: Negative cache for donor_profile when Worker is rate-limited.
	-- Without this, 1 fail = N attempts (each refreshAll/poll triggers next caller).
	-- Longer TTL than positive cache so Worker has time to recover.
	local donorFailureCache: { [number]: { expiresAt: number, failures: number? } } = {}
	local DONOR_PROFILE_FAILURE_CACHE_TTL = 120 -- seconds
	-- Exponential per-user failure backoff so a transient backend hiccup recovers
	-- in seconds instead of the flat 120s (which left joiners at Cash=0 for 2
	-- minutes), while a real outage still escalates to the full TTL fast.
	local DONOR_FAILURE_BACKOFF_STEPS = Config.Donation.DONOR_FAILURE_BACKOFF_STEPS or { 5, 10, 30, 120 }

	-- Single write point for donorCashCache. An event-driven entry (source="event",
	-- donation/cross-server push) must not be overwritten by a stale lower total
	-- from an in-flight HTTP/leaderboard result that was issued BEFORE the event
	-- landed — for a short window the max of the two wins (monotonic).
	local DONOR_EVENT_GUARD_WINDOW = 10
	local function writeDonorCashCache(
		userId: number,
		total: number,
		rank: number?,
		source: string?
	): DonorCashCacheEntry
		local now = os.clock()
		local existing = donorCashCache[userId]
		if
			existing
			and existing.source == "event"
			and (existing.writtenAt or 0) > now - DONOR_EVENT_GUARD_WINDOW
			and total < existing.total
			and source ~= "event"
		then
			-- Stale in-flight result: keep the fresh event total, refresh TTL only.
			existing.expiresAt = now + (Config.Donation.DONOR_PROFILE_CACHE_TTL or 45)
			return existing
		end
		local entry: DonorCashCacheEntry = {
			total = total,
			rank = rank,
			expiresAt = now + (Config.Donation.DONOR_PROFILE_CACHE_TTL or 45),
			source = source,
			writtenAt = now,
		}
		donorCashCache[userId] = entry
		return entry
	end

	-- Exponential failure TTL: 5s → 10s → 30s → 120s by consecutive failures,
	-- reset on success. A transient hiccup recovers in seconds; a real outage
	-- still escalates to the full cooldown.
	local function recordDonorFailure(userId: number, now: number)
		local prev = donorFailureCache[userId]
		local failures = if prev then (prev.failures or 0) + 1 else 1
		local step = DONOR_FAILURE_BACKOFF_STEPS[math.min(failures, #DONOR_FAILURE_BACKOFF_STEPS)]
			or DONOR_PROFILE_FAILURE_CACHE_TTL
		donorFailureCache[userId] = {
			expiresAt = now + step,
			failures = failures,
		}
	end

	-- Block /setrobux (add) while Studio writes live keys — accidental inflation risk.
	-- /removerobux is intentionally allowed so owners can clear live LB from Studio Play
	-- when USE_STUDIO_DATASTORE_ISOLATION=false.
	local function assertStudioManualDonationSafe(): (boolean, string?)
		if Config.DataStoreScope.writesToLive() then
			return false, Config.Donation.MSG_STUDIO_LIVE_DATASTORE_BLOCKED
		end
		return true, nil
	end

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
	-- Cold-start tip cursor: encode matches tools/donation-api encodeNotificationCursor
	-- (base64url of {"t":ISO,"i":id}). Empty cursor makes the Worker walk from 1970 ASC and
	-- would replay full donation history as "new" notifications on every server boot.
	local BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local function base64Char(index: number): string
		return string.sub(BASE64_ALPHABET, index + 1, index + 1)
	end
	local function base64EncodeAscii(data: string): string
		local out = table.create(math.ceil(#data / 3) * 4)
		local n = 0
		for i = 1, #data, 3 do
			local a = string.byte(data, i) :: number
			local b = string.byte(data, i + 1)
			local c = string.byte(data, i + 2)
			local bitmap = bit32.lshift(a, 16) + bit32.lshift(b or 0, 8) + (c or 0)
			n += 1
			out[n] = base64Char(bit32.rshift(bitmap, 18))
			n += 1
			out[n] = base64Char(bit32.band(bit32.rshift(bitmap, 12), 63))
			n += 1
			out[n] = if b == nil then "=" else base64Char(bit32.band(bit32.rshift(bitmap, 6), 63))
			n += 1
			out[n] = if c == nil then "=" else base64Char(bit32.band(bitmap, 63))
		end
		return table.concat(out)
	end
	local function buildColdStartNotificationCursor(unixTime: number): string
		local iso = os.date("!%Y-%m-%dT%H:%M:%S.000Z", unixTime)
		local payload = HttpService:JSONEncode({
			t = iso,
			i = 2147483647,
		})
		local encoded = base64EncodeAscii(payload)
		return (encoded:gsub("+", "-"):gsub("/", "_"):gsub("=+$", ""))
	end
	-- State
	local bootUnix = os.time()
	local notificationCursor: string = buildColdStartNotificationCursor(bootUnix)
	-- Defense in depth: never broadcast rows with received_at < boot, even if cursor slips.
	-- Kept for the whole server lifetime (do not clear after first successful poll).
	local notificationSkipBeforeUnix: number = bootUnix
	local lastNotifReceivedAt: number = 0 -- os.time() when last donation detected (burst mode)
	local processedNotifIds: { [string]: boolean } = {}
	local processedNotifIdOrder: { string } = {}
	local MAX_PROCESSED_NOTIF_IDS = 512
	local _pollRunning = false -- prevent overlapping HTTP calls during slow Worker response
	local _pollStartedAt = 0
	local POLL_WATCHDOG_TIMEOUT = 45

	-- ── Reliability v2 state ────────────────────────────────────────────────
	-- Tracks in-flight deliveries waiting for client ack. Key = "donationId:userId".
	-- Value = { donationId, userId, attempts, lastFiredAt, payload }. Entries are
	-- registered when the server fires a notification and removed on ack or when
	-- reported to the Worker DLQ after exhausting retries.
	type PendingDelivery = {
		donationId: number,
		userId: number,
		attempts: number,
		lastFiredAt: number,
		payload: DonationNotifPayload,
	}
	local pendingDeliveries: { [string]: PendingDelivery } = {}
	-- `skipped` (reliability v4): the client RECEIVED the notif but did not show
	-- it ("muted" = player disabled donation announce, "no_gui" = notif GUI
	-- missing in this place). Reported so the ledger records a non-failure and
	-- the server stops retrying — before v4 these looked identical to a lost
	-- notification and produced 1 DLQ row per muted player per donation.
	local _ackFlushQueue: { { donation_id: number, roblox_user_id: number, displayed_at: string, skipped: string? } } = {}
	-- Stage-2 display reports: the notification actually rendered on the
	-- player's screen (vs ack = it reached the client queue).
	local _displayFlushQueue: { { donation_id: number, roblox_user_id: number, displayed_at: string } } = {}

	-- Forward declarations: the bodies below reference helpers defined later in
	-- this module (isReliabilityV2Enabled, flushAckQueue, reportDlq). Declaring
	-- the locals here keeps the assignments (further down) in scope.
	local deliveryKey: (donationId: number, userId: number) -> string
	local handleNotifAck: (player: Player, payload: any) -> ()
	local handleNotifDisplay: (player: Player, payload: any) -> ()
	local sweepPendingDeliveries: () -> ()

	deliveryKey = function(donationId: number, userId: number): string
		return string.format("%d:%d", donationId, userId)
	end
	local _leaderboardRefreshQueued = false -- debounce flag for async leaderboard refresh
	local _lastLeaderboardRefreshAt = 0 -- timestamp of last leaderboard refresh
	local LEADERBOARD_REFRESH_DEBOUNCE = Config.Donation.LEADERBOARD_REFRESH_DEBOUNCE or 10 -- min seconds between refreshes
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
	-- Phase 3: Track userIds that have donated (from notif, manual adjustment, or cash stats > 0).
	-- Skip donor_profile API call for players who never donated — most players
	-- on overhead leaderboard not donor, so API call always returns cash_total=0.
	-- knownDonors sticky: sekali marked, still dikenal sampai module reload. Hot-reload safe
	-- because state reset = back to conservative "unknown" (just an extra API call).
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

	-- { [robloxUsername:lower()]: rank } for combined daily + alltime
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
	-- Failure tracking (consecutive — reset immediately after one success)
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

	local function buildV3Url(resourcePath: string): string
		local base = getDonationApiBase()
		if base == "" then
			return ""
		end
		local path = resourcePath:gsub("^/+", "")
		return base .. "/v3/" .. path
	end

	local function isReliabilityV2Enabled(): boolean
		return Config.Donation.RELIABILITY_V2_ENABLED == true
	end

	local function httpRequestOnce(method: string, url: string, body: string?): (boolean, string)
		if url == "" then
			return false, "Donation API not configured"
		end
		local secret = Secrets.DonationApiSecret
		if type(secret) ~= "string" or secret == "" then
			return false, "DonationApiSecret not configured"
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

	-- Filter author for provider-supplied text (donor name/message). Roblox
	-- requires the filter author to be CONNECTED to the current server
	-- (FilterStringAsync errors "sender must be connected" otherwise). Prefer the
	-- donor's own userId when they are ONLINE. When the donor is offline /
	-- unresolved, fall back to ANY currently-online player (the recipient counts)
	-- so filtering still succeeds. Returning nil (or an offline id such as the
	-- game owner when they are away) makes FilterStringAsync fail and every
	-- message censors to "#####".
	local function resolveTextFilterUserId(userId: number?): number?
		if type(userId) == "number" and userId > 0 and Players:GetPlayerByUserId(userId) then
			return userId
		end
		-- Donor not connected: use any online player as the broadcast author. The
		-- donor is rarely in-server, so without this every provider message fails
		-- filtering and renders as "#####".
		local online = Players:GetPlayers()
		if #online > 0 then
			return online[1].UserId
		end
		return nil
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
		local filtered = TextFilterUtil.filterForBroadcast(userId, message, maxLength)
		if not filtered and TextFilterUtil.normalize(message, maxLength) then
			log:warn("Donation provider text filter failed", {
				userId = userId,
				provider = getProviderName(),
			})
		end
		return filtered
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


	-- httpGetOnce: single HTTP GET attempt with RequestAsync + Bearer auth
	local function httpGetOnce(url: string): (boolean, string)
		return httpRequestOnce("GET", url, nil)
	end
	-- httpGet: one attempt + optional retry (handle transient network errors)
	local function httpGet(url: string): (boolean, string)
		if url == "" then
			return false, "Donation API not configured"
		end
		local ok, res = httpGetOnce(url)
		if ok then
			return true, res
		end
		-- Retry once if enabled in config
		if Config.Donation.NOTIF_RETRY_ENABLED then
			-- Phase 4: Downgrade to debug — caller (fetchDonorCashProfile, _pollNotifications, _pollLeaderboard)
			-- already logs more specific per-endpoint warning. This retry log is duplicate noise.
			log:debug("HTTP failed, retry in " .. Config.Donation.NOTIF_RETRY_DELAY .. "s", {
				url = url,
				error = res,
			})
			task.wait(Config.Donation.NOTIF_RETRY_DELAY)
			return httpGetOnce(url)
		end
		return false, res
	end
	-- Reliability v2: POST helper (v2 only had GET). Same Bearer auth, same retry.
	local function httpPost(url: string, payload: any): (boolean, string)
		if url == "" then
			return false, "Donation API not configured"
		end
		local body = HttpService:JSONEncode(payload)
		local ok, res = httpRequestOnce("POST", url, body)
		if ok then
			return true, res
		end
		if Config.Donation.NOTIF_RETRY_ENABLED then
			task.wait(Config.Donation.NOTIF_RETRY_DELAY)
			return httpRequestOnce("POST", url, body)
		end
		return false, res
	end

	-- Register intended recipients for a donation notification. Best-effort:
	-- a failure here never blocks the in-game notification — the ledger is for
	-- audit/retry, the live fire already happened.
	local function registerDeliveries(donationId: number, userIds: { number })
		if not isReliabilityV2Enabled() or donationId <= 0 or #userIds == 0 then
			return
		end
		task.spawn(function()
			local ok, err = httpPost(buildV3Url("deliveries"), {
				donation_id = donationId,
				roblox_user_ids = userIds,
			})
			if not ok then
				log:warn("Delivery registration failed (non-blocking)", {
					donationId = donationId,
					recipients = #userIds,
					error = tostring(err),
				})
			end
		end)
	end

	-- Flush queued client acks to the Worker ledger. Called from the ack
	-- listener (batched to one HTTP call per flush window).
	local function flushAckQueue()
		if #_ackFlushQueue == 0 then
			return
		end
		local batch = _ackFlushQueue
		_ackFlushQueue = {}
		task.spawn(function()
			local ok, err = httpPost(buildV3Url("delivery-ack"), { acks = batch })
			if not ok then
				log:warn("Delivery ack flush failed (non-blocking)", {
					acks = #batch,
					error = tostring(err),
				})
			end
		end)
	end

	-- Flush queued display reports to the Worker ledger (stage 2: on-screen).
	local function flushDisplayQueue()
		if #_displayFlushQueue == 0 then
			return
		end
		local batch = _displayFlushQueue
		_displayFlushQueue = {}
		task.spawn(function()
			local ok, err = httpPost(buildV3Url("delivery-display"), { displays = batch })
			if not ok then
				log:warn("Display report flush failed (non-blocking)", {
					reports = #batch,
					error = tostring(err),
				})
			end
		end)
	end

	-- Report deliveries the server gave up on. `reason` lets the ledger separate
	-- "player left" (not a failure) from "stayed, never answered" (real DLQ);
	-- `attempts` is the client re-fire count for diagnostics.
	type DlqEntry = { donation_id: number, roblox_user_id: number, reason: string?, attempts: number? }
	local function reportDlq(entries: { DlqEntry })
		if #entries == 0 then
			return
		end
		task.spawn(function()
			local ok, err = httpPost(buildV3Url("delivery-dlq"), { entries = entries })
			if not ok then
				log:warn("DLQ report failed (non-blocking)", {
					entries = #entries,
					error = tostring(err),
				})
			end
		end)
	end

	-- Reliability v2: a donation whose phase-2 resolve crashed (or produced no
	-- usable display name) never reaches fireCashDonationPresentation, so it would
	-- never appear in the delivery ledger at all — a silent loss. Report it with
	-- the roblox_user_id=0 sentinel so ops see status='failed_resolve' in the DLQ
	-- instead of the donation vanishing. Best-effort, never blocks the poll loop.
	local function reportResolveFailure(donationId: number)
		if not isReliabilityV2Enabled() or donationId <= 0 then
			return
		end
		task.spawn(function()
			local ok, err = httpPost(buildV3Url("delivery-dlq"), {
				entries = { { donation_id = donationId, roblox_user_id = 0, reason = "failed_resolve" } },
			})
			if not ok then
				log:warn("Resolve-failure report failed (non-blocking)", {
					donationId = donationId,
					error = tostring(err),
				})
			end
		end)
	end

	-- Reliability v2 bodies (locals forward-declared near the state tables above).
	-- Defined here so they can call isReliabilityV2Enabled/flushAckQueue/reportDlq.

	-- Client acks a displayed notification → drop from pending + queue ledger ack.
	handleNotifAck = function(player: Player, payload: any)
		if not isReliabilityV2Enabled() or type(payload) ~= "table" then
			return
		end
		local donationId = tonumber(payload.donationId) or 0
		if donationId <= 0 then
			return
		end
		local userId = player.UserId
		local key = deliveryKey(donationId, userId)
		if pendingDeliveries[key] == nil then
			return -- duplicate or untracked ack; harmless
		end
		pendingDeliveries[key] = nil
		-- Reliability v4: a client that received the notif but will not show it
		-- says so ("muted" / "no_gui"). Same effect on retry (stop), different
		-- ledger outcome (non-failure instead of dlq). Whitelisted so a client
		-- cannot write arbitrary strings into the ledger.
		local skipped: string? = nil
		if type(payload.skipped) == "string" then
			local s = string.lower(payload.skipped)
			if s == "muted" or s == "no_gui" or s == "disabled" then
				skipped = s
			else
				skipped = "other"
			end
		end
		table.insert(_ackFlushQueue, {
			donation_id = donationId,
			roblox_user_id = userId,
			displayed_at = os.date("!%Y-%m-%dT%H:%M:%S.000Z"),
			skipped = skipped,
		})
		flushAckQueue()
	end

	-- Client reports the notification actually rendered on screen (stage 2).
	-- Unlike acks, displays are not tracked in pendingDeliveries — they are a
	-- pure pass-through to the ledger. A display report implies delivery, so
	-- the backend promotes the row through 'acked' to 'displayed' in one step.
	handleNotifDisplay = function(player: Player, payload: any)
		if not isReliabilityV2Enabled() or type(payload) ~= "table" then
			return
		end
		local donationId = tonumber(payload.donationId) or 0
		if donationId <= 0 then
			return
		end
		table.insert(_displayFlushQueue, {
			donation_id = donationId,
			roblox_user_id = player.UserId,
			displayed_at = os.date("!%Y-%m-%dT%H:%M:%S.000Z"),
		})
		flushDisplayQueue()
	end

	-- Retry sweep: re-fire to players who haven't acked in time; after
	-- NOTIF_ACK_MAX_ATTEMPTS, report to the Worker DLQ and stop tracking.
	-- Player leaving the game also drops the entry (nothing to retry against).
	sweepPendingDeliveries = function()
		if not isReliabilityV2Enabled() then
			return
		end
		local now = os.clock()
		local retryAfter = math.max(1, tonumber(Config.Donation.NOTIF_ACK_RETRY_AFTER_SECS) or 5)
		local maxAttempts = math.max(1, tonumber(Config.Donation.NOTIF_ACK_MAX_ATTEMPTS) or 3)
		local dlqEntries: { DlqEntry } = {}
		for key, entry in pairs(pendingDeliveries) do
			local player = Players:GetPlayerByUserId(entry.userId)
			if player == nil then
				-- Recipient left before acking. Reliability v4: reported as
				-- reason="left" → ledger status 'left' (not a failure — there was
				-- no screen to show it on), then stop tracking.
				pendingDeliveries[key] = nil
				table.insert(dlqEntries, {
					donation_id = entry.donationId,
					roblox_user_id = entry.userId,
					reason = "left",
					attempts = entry.attempts,
				})
			elseif (now - entry.lastFiredAt) >= retryAfter then
				if entry.attempts >= maxAttempts then
					-- Player stayed the whole window and the client never
					-- answered at all — the only real per-player failure.
					pendingDeliveries[key] = nil
					table.insert(dlqEntries, {
						donation_id = entry.donationId,
						roblox_user_id = entry.userId,
						reason = "timeout",
						attempts = entry.attempts,
					})
					log:warn("Donation notification moved to DLQ (no ack)", {
						donationId = entry.donationId,
						userId = entry.userId,
						attempts = entry.attempts,
					})
				else
					entry.attempts += 1
					entry.lastFiredAt = now
					notifNetwork:fireClient(player, entry.payload)
					log:info("Donation notification retry", {
						donationId = entry.donationId,
						userId = entry.userId,
						attempt = entry.attempts,
					})
				end
			end
		end
		reportDlq(dlqEntries)
	end

	-- Exponential backoff: 5, 10, 20 (capped) seconds per consecutive failure
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

	-- Adaptive poll delay: burst after new donations, idle otherwise (+ failure backoff).
	local function getNotifPollDelay(): number
		local cfg = Config.Donation
		local timeSinceLast = os.time() - lastNotifReceivedAt
		local failureBackoff = getNotifFailureBackoff()
		if lastNotifReceivedAt > 0 and timeSinceLast < cfg.NOTIF_BURST_WINDOW then
			return math.max(cfg.NOTIF_BURST_INTERVAL, failureBackoff)
		end
		return math.max(cfg.NOTIF_POLL_INTERVAL, failureBackoff)
	end

	-- donation_poll is async (task.spawn); scheduler already scheduled next tick with
	-- idle interval when the thin callback returned. Pull nextRunAt earlier for burst.
	local function rescheduleNotifPollJob()
		if not backgroundJobScheduler or type(backgroundJobScheduler.setInterval) ~= "function" then
			return
		end
		local delay = getNotifPollDelay()
		backgroundJobScheduler:setInterval(donationPollJobName, delay, delay + 1)
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
	-- Patch #2 R2: Track userIds whose rank changed during applyLeaderboardDiff,
	-- used to invalidate rank cache per-user (not wipe all). Reset each call.
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
	-- Assign Saweria top spender tag to online player.
	local function assignPlayer(robloxUsername: string, rank: number)
		local cleanedUsername = cleanRobloxUsername(robloxUsername)
		if not cleanedUsername then
			return
		end
		local lower = cleanedUsername:lower()
		-- Find active player
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
					log:warn("Failed to update DataStore top spender", {
						player = player.Name,
						error = result.error,
					})
				end
				return
			end
		end
	end
	-- Clear Saweria top spender tag from players who left the leaderboard
	clearPlayer = function(userId: number, playerName: string)
		local result = repo:update(userId, function(current)
			return OverheadDomain.mergeStored(current, {
				topSpenderRank = OverheadDomain.NIL,
				topSpenderText = OverheadDomain.NIL,
			})
		end)
		if result.ok then
			markChangedUserId(userId)
			-- Refresh if still online
			local player = Players:GetPlayerByUserId(userId)
			if player then
				overheadController:refreshPlayer(player)
			end
			log:info("Cleared top spender tag", { player = playerName })
		end
	end
	-- Diff old vs new leaderboard, assign/clear changes
	local function applyLeaderboardDiff(newEntries: { DonationEntry })
		-- Reset changed set at start; assignPlayer/clearPlayer populate via markChangedUserId
		lastDiffChangedUserIds = {}
		local newRanks: { [string]: number } = {}
		for _, entry in ipairs(newEntries) do
			-- Chip-for-all: track ranks up to 100 (the polled leaderboard's fetchLimit
			-- ceiling). Rank >100 donors still get chips via the getPlayerCashStats
			-- fallback in OverheadService; this gate only bounds DataStore write churn.
			if entry.rank > 100 then
				continue
			end
			local username = cleanRobloxUsername(entry.robloxUsername)
			if username and username ~= "" then
				local lowerName = username:lower()
				newRanks[lowerName] = entry.rank
				local oldRank = assignedRanks[lowerName]
				if oldRank ~= entry.rank then
					-- Rank changed or new entry -> assign
					assignPlayer(username, entry.rank)
				end
			end
		end
		-- Clear players no longer on the leaderboard
		for lowerName, _ in pairs(assignedRanks) do
			if not newRanks[lowerName] then
				-- Resolve userId
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
		-- Patch #2 R2: invalidate per-user (changed ranks only), not wipe all
		invalidateOverheadRankCaches(drainChangedUserIds())
		broadcastSheetsLeaderboardSignal(forceBroadcast == true)
		service:notifyWorkspaceLeaderboardsUpdated()
		-- assignPlayer/clearPlayer already refreshPlayer for changed online users.
		-- Full refreshAll only on explicit force (admin / manual sync).
		if forceBroadcast == true and overheadController and type(overheadController.refreshAll) == "function" then
			task.defer(function()
				overheadController:refreshAll()
			end)
		end
	end

	-- Poll
	-- _pollLeaderboard: fetch all-time & daily in one v2 request
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
			log:warn("HTTP failed (leaderboards v2)", { error = res })
		end

		if not allTimeOk and previousCache and #previousCache.allTime > 0 then
			allTimeEntries = previousCache.allTime
			log:warn("Leaderboard all-time using cache (HTTP failed)", {
				cachedCount = #allTimeEntries,
			})
		end
		if not dailyOk and previousCache and #previousCache.daily > 0 then
			dailyEntries = previousCache.daily
			log:warn("Leaderboard daily using cache (HTTP failed)", {
				cachedCount = #dailyEntries,
			})
		end
		if not allTimeOk and not dailyOk then
			return
		end

		-- P0: When throttle lockout active, HTTP cache still updated but skip
		-- downstream DS cascade (applyLeaderboardDiff + refreshAll). DS writes/
		-- reads will short-circuit via repository lockout; explicit log here
		-- so operators can see in console without grepping server log.
		if DataStoreThrottleLockout.isLocked() then
			log:info("Leaderboard poll: skipping DS cascade (throttle lockout active)", {
				remainingSec = math.floor(DataStoreThrottleLockout.getRemainingSec() + 0.5),
			})
			-- Still update in-memory cache + broadcast signal so client UI stays
			-- up-to-date with HTTP state; only DS-bound ops are skipped.
			if allTimeOk then
				cachedLeaderboard = {
					daily = dailyEntries,
					allTime = allTimeEntries,
					updatedAt = os.time(),
				}
				applyLeaderboardDiff(allTimeEntries)
				invalidateOverheadRankCaches(drainChangedUserIds())
			end
			broadcastSheetsLeaderboardSignal(forceBroadcast == true)
			service:notifyWorkspaceLeaderboardsUpdated()
			return
		end

		-- Merge legacy Saweria snapshot with the live sheet data so old totals remain connected.
		-- Daily is not seeded because it resets.
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
		-- Apply diff based on all-time (overhead tag is based on all-time)
		applyLeaderboardDiff(allTimeEntries)
		-- Same as syncBagibagiLeaderboardFromCache: per-user invalidate after diff
		-- (refreshAll no longer runs on routine polls).
		invalidateOverheadRankCaches(drainChangedUserIds())
		broadcastSheetsLeaderboardSignal(forceBroadcast == true)
		service:notifyWorkspaceLeaderboardsUpdated()
		-- Rank tags already refreshed per-player in applyLeaderboardDiff.
		-- Full refreshAll only on explicit forceBroadcast.
		if forceBroadcast == true and overheadController and type(overheadController.refreshAll) == "function" then
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
		-- Reliability v2: donation id from the Worker (D1 donations.id). 0/nil
		-- means "untracked" (manual /fakecash, legacy paths) — no ack expected.
		donationId: number?,
	})
		local amount = math.floor(tonumber(args.amount) or 0)
		if amount <= 0 then
			return
		end

		-- Phase 3: Mark as known donor — broadcast always = valid userId becomes donor.
		-- Covers all caller: _pollNotifications, presentCashDonation, manual cash.
		if not args.testOnly then
			markKnownDonor(args.robloxUserId)
		end

		local worldEffect: string? = nil
		if Config.FeatureFlags.DonationWorldEffectsEnabled == true then
			worldEffect = DonationEffectTierResolver.resolveWorldByIdr(amount)
		end

		local donationId = tonumber(args.donationId) or 0
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
			worldEffect = worldEffect,
			-- Reliability v2: client echoes this back in the ack so the server can
			-- correlate "displayed" with the D1 donations row.
			donationId = if donationId > 0 then donationId else nil,
			-- NetworkManager coalesces same-frame fires by (target, data.kind) and
			-- keeps only the LAST one. Without a per-donation kind, two donation
			-- notifs to the same target in one Heartbeat (burst, or the retry
			-- sweep re-firing 2+ pending donations to one player) silently drop
			-- the older one — every single time, until it hits the DLQ.
			kind = if donationId > 0 then "donation:" .. tostring(donationId) else "donation:" .. tostring(os.clock()),
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
				worldEffect = payload.worldEffect,
				staggerMs = math.floor(staggerDelay * 1000),
				donationId = if donationId > 0 then donationId else nil,
			})

			-- Reliability v2: register the delivery in the Worker's ledger and
			-- track every online player as a pending recipient. The retry scheduler
			-- re-fires to players who don't ack within NOTIF_ACK_RETRY_AFTER_SECS.
			if isReliabilityV2Enabled() and donationId > 0 and not args.testOnly then
				local onlineUserIds: { number } = {}
				local now = os.clock()
				for _, player in ipairs(Players:GetPlayers()) do
					local userId = player.UserId
					table.insert(onlineUserIds, userId)
					pendingDeliveries[deliveryKey(donationId, userId)] = {
						donationId = donationId,
						userId = userId,
						attempts = 1,
						lastFiredAt = now,
						payload = payload,
					}
				end
				registerDeliveries(donationId, onlineUserIds)
			end

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
			-- Unique coalesce key — see the cash payload for why.
			kind = "donation:robux:" .. tostring(os.clock()),
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

	-- Instant cash-total sync for a donor whose donation just arrived. The
	-- backend feed carries an authoritative cumulative total (total_after) that
	-- already INCLUDES the donation being processed; pushing it into the donor
	-- cache + overhead fast cache + the in-server player's leaderstat makes the
	-- notif card, donation panel, overhead chip, and PlayerList Cash column all
	-- show the new total immediately instead of on the next cache expiry (45s).
	-- Unless suppressPublish, the absolute total is also pushed to other servers
	-- in this game via MessagingService (cross-server instant sync).
	local CROSS_SERVER_CASH_TOPIC = Config.Donation.CROSS_SERVER_CASH_TOPIC or "DonorCashSync_v1"
	-- Token bucket (~8/s, burst 16) so a donation storm cannot approach the
	-- MessagingService per-game publish cap (150 + 150x servers per minute).
	local cashPublishTokens = 16.0
	local cashPublishLastRefill = os.clock()
	local function tryConsumeCashPublishToken(): boolean
		local now = os.clock()
		cashPublishTokens = math.min(16.0, cashPublishTokens + (now - cashPublishLastRefill) * 8.0)
		cashPublishLastRefill = now
		if cashPublishTokens >= 1.0 then
			cashPublishTokens -= 1.0
			return true
		end
		return false
	end

	local function publishCashTotalCrossServer(userId: number, total: number)
		if Config.Donation.CROSS_SERVER_CASH_SYNC_ENABLED == false then
			return
		end
		if not tryConsumeCashPublishToken() then
			-- Storm guard: skip publishing; receivers fall back to the 45s TTL path.
			return
		end
		task.spawn(function()
			local ok, err = pcall(function()
				-- ABSOLUTE total (never a delta): idempotent + drop-safe. Receivers
				-- apply monotonically and simply drop stale/lower values.
				MessagingService:PublishAsync(CROSS_SERVER_CASH_TOPIC, {
					u = userId,
					t = total,
					j = game.JobId,
				})
			end)
			if not ok then
				log:debug("Cross-server cash publish failed (non-critical)", { error = tostring(err) })
			end
		end)
	end

	local function applyInstantCashTotal(userId: number?, totalAfter: number, suppressPublish: boolean?)
		if type(userId) ~= "number" or userId <= 0 then
			return
		end
		local total = math.max(0, math.floor(tonumber(totalAfter) or 0))
		if total <= 0 then
			return
		end
		-- Carry forward the prior rank (if any): a fresh total without rank
		-- would blank the chip rank until the next leaderboard poll.
		local priorRank = if donorCashCache[userId] then donorCashCache[userId].rank else nil
		writeDonorCashCache(userId, total, priorRank, "event")
		markKnownDonor(userId)
		if overheadService and type(overheadService.setCashDonated) == "function" then
			overheadService:setCashDonated(userId, total)
		end
		-- Direct leaderstat bump: the overhead broadcast rebuild will reuse the
		-- same cached value, so writing the IntValue here just makes it instant.
		local player = Players:GetPlayerByUserId(userId)
		if player then
			local leaderstats = player:FindFirstChild("leaderstats")
			local cashStat = if leaderstats
				then leaderstats:FindFirstChild(Config.PlayerList.CASH_STAT_NAME or "Cash")
				else nil
			if cashStat and cashStat:IsA("IntValue") then
				if cashStat.Value < total then
					cashStat.Value = total
				end
			end
		end
		if not suppressPublish then
			publishCashTotalCrossServer(userId, total)
		end
	end

	-- Forward declaration: _pollNotifications' phase-2 resolve calls this before
	-- its definition below. Without the forward local, the earlier call site
	-- resolves to a nil global at runtime ("attempt to call a nil value") for any
	-- donor missing from the leaderboard cache (first-ever donation / test names).
	local fetchDonorCashProfile: (userId: number, username: string) -> (number, number?)

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
				rescheduleNotifPollJob()
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
				log:warn("HTTP failed (notifications v2)", {
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
				-- Prefer received_at (unix_timestamp) for cold-start skip — matches Worker cursor.
				-- donation_unix_timestamp can be historical on late ingest; we still want live alerts.
				local ts = tonumber(item.unix_timestamp) or tonumber(item.received_at) or 0
				if notificationSkipBeforeUnix > 0 and ts > 0 and ts < notificationSkipBeforeUnix then
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
					totalAfter = tonumber(item.total_after) or tonumber(item.totalAfter) or 0,
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
						-- Backend total_after (window sum including THIS donation) is the
						-- authoritative total — the cached leaderboard and the 45s donor
						-- profile cache can both lag behind the donation being processed,
						-- which made the card show a stale total right after donating.
						-- When present it wins and also syncs the player's local stats.
						local backendTotalAfter = tonumber(info.totalAfter) or 0
						if backendTotalAfter > 0 then
							totalDonationAmount = backendTotalAfter
							applyInstantCashTotal(robloxUserId, backendTotalAfter)
						end
						-- Lapis-2 fix (2026-08-17): a first-ever donation arrives before the
						-- leaderboard cache includes the donor, so matchedEntry is nil and the
						-- old code fired the notif with totalDonationAmount=nil → client showed
						-- "Total: First donation" even when the donor had prior history in the
						-- backend. Fall back to the donor-profile API (cached 45s, failure
						-- negative-cached 120s) so the chip shows the real total.
						if totalDonationAmount == nil and robloxUserId and not isHiddenDonationUser(robloxUserId) then
							local apiTotal = fetchDonorCashProfile(robloxUserId, robloxUsername or info.donatorName)
							if type(apiTotal) == "number" and apiTotal > 0 then
								totalDonationAmount = apiTotal
							end
						end
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
							-- Reliability v2: propagate the donation id so the ack ledger
							-- can correlate this notification back to the D1 row.
							donationId = tonumber(info.item.id) or 0,
						}
					end)
					if not okResolve then
						log:warn("Notification resolve worker failed", {
							id = info.notifId,
							error = tostring(resolveErr),
						})
						-- Reliability v2: surface the loss to the ledger instead of
						-- dropping silently (was the 1-in-50 leak in load testing).
						reportResolveFailure(tonumber(info.item.id) or 0)
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
				elseif data and (tonumber(data.donationId) or 0) > 0 then
					-- Resolve succeeded but produced nothing displayable (e.g. filter
					-- returned nil for every field). Surface to the ledger rather than
					-- dropping silently.
					reportResolveFailure(tonumber(data.donationId) or 0)
				end
			end
		end)
		if not success then
			consecutiveFailures += 1
			log:warn("Failed to parse notifications response", {
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
		-- Keep notificationSkipBeforeUnix for the server lifetime — clearing it used to
		-- let subsequent cursor pages replay historical donations as live notifs.
		-- Pull any owner-dashboard commands (fake notif / manual adjust / retry) on
		-- the same poll cycle — no separate connection needed.
		do
			local cmdOk, cmdErr = pcall(function()
				service:_pollCommands()
			end)
			if not cmdOk then
				log:warn("Command poll failed (non-blocking)", { error = tostring(cmdErr) })
			end
		end
		-- On new donation: enable burst mode + refresh leaderboard immediately
		if hadNewDonations then
			lastNotifReceivedAt = os.time()
			log:debug("Burst mode activated — new donation detected")
			-- Trigger async leaderboard refresh with debounce so rank data is up-to-date quickly
			-- without blocking the next notification poll. Debounce prevents multiple rapid refreshes.
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

	fetchDonorCashProfile = function(userId: number, username: string): (number, number?)
		local now = os.clock()
		-- Phase 1: Negative cache check — skip silently if Worker just failed for this userId.
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
			-- Phase 1: Record fail so next callers (refreshAll, leaderboard poll, etc.) skip during TTL.
			recordDonorFailure(userId, now)
			log:warn("Donor profile API failed", { userId = userId, error = body })
			return 0, nil
		end

		local success, decoded = pcall(function()
			return HttpService:JSONDecode(body)
		end)
		if not success or type(decoded) ~= "table" or decoded.ok ~= true then
			-- Phase 1: Parse fail also cached (consistently malformed response = no need to retry every 3-5s).
			recordDonorFailure(userId, now)
			log:warn("Donor profile API parse failed", { userId = userId })
			return 0, nil
		end

		-- Phase 1: Success path — clear negative entry so next fail is recorded again.
		donorFailureCache[userId] = nil
		local total = math.max(0, math.floor(tonumber(decoded.cash_total) or 0))
		local rankValue = tonumber(decoded.cash_rank)
		local rank = if rankValue and rankValue >= 1 then math.floor(rankValue) else nil
		writeDonorCashCache(userId, total, rank, nil)
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
		-- Do not use rank-only cache with total 0: that makes panel/leaderstats
		-- stuck at #1 / 0 while overhead chip rank still shows.
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

		-- Phase 3: "unknown donor" must not suppress the API call.
		-- knownDonors only tracks donors seen *this server session* (notification/manual).
		-- A player who donated while this server was offline (or in a previous session)
		-- is in the backend but unknown here → the old early-return kept them at Cash=0
		-- forever (leaderstat/chip never updated; validated live on Atlantis).
		-- Hidden users still never hit HTTP, and the failure cache inside
		-- fetchDonorCashProfile already negative-caches true non-donors for 120s,
		-- so bulk non-donor joins cannot spam the API. We always fall through to the
		-- API attempt; the caches keep it cheap.
		if cashTotal <= 0 and isHiddenDonationUser(userId) then
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
		writeDonorCashCache(userId, cashTotal, cashRank, nil)
		-- Phase 3: Mark as known donor (cashTotal > 0 from any source).
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
		if type(cashRank) == "number" and cashRank <= 100 then -- chip-for-all: was LEADERBOARD_LIMIT(10)
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

	-- ── Owner dashboard commands (fake notif / manual adjust / retry) ────────
	-- The dashboard enqueues rows in the backend's game_commands table; the game
	-- pulls them here on the existing donation poll loop and executes them
	-- server-side, then acks. No new connection or remote — reuses the v2 poll.

	-- Fire a fake notification on behalf of a provider-style name. Resolves the
	-- Roblox identity (username → userId → display name) through the SAME path
	-- as a real donation so the notification shows the real display name and
	-- profile thumbnail, and the text filter runs under a real connected author
	-- (a `robloxUserId = 0` / authorId=1 placeholder produced a blank thumbnail
	-- and a `####` censored message). testOnly keeps stats/leaderboard untouched.
	-- Server already resolved the Roblox identity at enqueue time and it rides in
	-- the payload (userId/username/displayName). The game uses it directly — NO
	-- extra Roblox name-lookup here — which saves GetUserIdFromNameAsync /
	-- GetNameAsync budget. Only the thumbnail image itself is fetched client-side
	-- (Roblox blocks rbxthumb from server HTTP), and it goes straight from the id.
	local function fireFakeNotifPresentation(
		name: string,
		amount: number,
		message: string,
		userId: number?,
		username: string?,
		displayName: string?
	)
		-- Use the server-resolved identity as-is; only fall back to an in-game
		-- lookup when the server could not resolve anything (older backends).
		local resolvedUserId: number? = if type(userId) == "number" and userId > 0 then userId else nil
		if resolvedUserId == nil and (username == nil or username == "" or displayName == nil) then
			-- Legacy path: no identity came from the server — do the local lookup.
			resolvedUserId = resolveRobloxUserId(name)
		end

		local robloxUsername: string? = if type(username) == "string" and username ~= "" then username else nil
		local resolvedDisplayName: string? = if type(displayName) == "string" and displayName ~= "" then displayName else nil
		-- Live player data always wins for display name freshness (no extra HTTP).
		if resolvedUserId and resolvedUserId > 0 then
			local live = Players:GetPlayerByUserId(resolvedUserId)
			if live then
				robloxUsername = robloxUsername or live.Name
				resolvedDisplayName = live.DisplayName
			end
			-- If we have an id but no names yet (legacy), resolve them now.
			if robloxUsername == nil and resolvedDisplayName == nil then
				local uName, dName = getRobloxUserInfo(resolvedUserId)
				robloxUsername = uName
				resolvedDisplayName = dName
			end
		end
		robloxUsername = robloxUsername or name
		local filterAuthor = resolveTextFilterUserId(resolvedUserId)

		local filteredName = filterForBroadcast(filterAuthor, name, 64) or name
		local rawMessage = cleanOptionalMessage(message, 180)
		local filteredMessage = filterForBroadcast(filterAuthor, rawMessage, 180)
		if rawMessage and not filteredMessage then
			filteredMessage = censoredMessageFallback(rawMessage)
		end
		fireCashDonationPresentation({
			filteredDonatorName = filteredName,
			amount = amount,
			message = filteredMessage,
			newRank = nil,
			robloxUsername = robloxUsername,
			robloxUserId = resolvedUserId,
			robloxDisplayName = resolvedDisplayName,
			totalDonationAmount = nil,
			logDonor = name,
			testOnly = true,
		})
	end

	local function executeGameCommand(cmd: any): (boolean, string)
		local ctype = tostring(cmd and cmd.type or "")
		local payload = if type(cmd) == "table" and type(cmd.payload) == "table" then cmd.payload else {}
		if ctype == "fake_notif" then
			local amount = math.floor(tonumber(payload.amount) or 0)
			local name = tostring(payload.name or "")
			if amount <= 0 or name == "" then
				return false, "invalid_payload"
			end
			local userId = math.floor(tonumber(payload.user_id) or 0)
			fireFakeNotifPresentation(
				name,
				amount,
				tostring(payload.message or ""),
				userId > 0 and userId or nil,
				if type(payload.username) == "string" then payload.username else nil,
				if type(payload.display_name) == "string" then payload.display_name else nil
			)
			return true, ""
		elseif ctype == "manual_adjust" then
			local userId = math.floor(tonumber(payload.user_id) or 0)
			local delta = math.floor(tonumber(payload.delta) or 0)
			if userId <= 0 or delta == 0 then
				return false, "invalid_payload"
			end
			-- Silent: update leaderboard/stats/overhead WITHOUT firing a notif.
			local ok, err = service:addManualCashAdjustment(userId, tostring(payload.username or ""), delta)
			return ok, tostring(err or "")
		elseif ctype == "set_total" then
			-- Set a player's cash total to an ABSOLUTE value (easier than add/remove
			-- deltas). The backend resolved the userId from the leaderboard name, so
			-- a mis-typed donor name can be re-pointed by editing the link.
			local userId = math.floor(tonumber(payload.user_id) or 0)
			local total = math.floor(tonumber(payload.total) or -1)
			if userId <= 0 or total < 0 then
				return false, "invalid_payload"
			end
			local current = 0
			local okCur, cur = pcall(function()
				local total = service:getPlayerCashStats(userId, tostring(payload.username or ""))
				return total
			end)
			if okCur and type(cur) == "number" then
				current = math.floor(cur)
			end
			local delta = total - current
			if delta == 0 then
				return true, "no_change"
			end
			-- Reuse the silent adjustment path so leaderboard/stats/overhead update.
			local ok, err = service:addManualCashAdjustment(userId, tostring(payload.username or ""), delta)
			return ok, tostring(err or "")
		elseif ctype == "retry_donation" then
			local amount = math.floor(tonumber(payload.amount) or 0)
			local name = tostring(payload.saweria_name or payload.name or "")
			if amount <= 0 or name == "" then
				return false, "invalid_payload"
			end
			-- Re-broadcast the notification (presentation only, non-persisting).
			-- Use the server-resolved linked identity (userId/username/displayName)
			-- that rode along in the payload — no in-game lookup needed.
			local retryUserId = math.floor(tonumber(payload.user_id) or 0)
			fireFakeNotifPresentation(
				name,
				amount,
				tostring(payload.message or ""),
				retryUserId > 0 and retryUserId or nil,
				if type(payload.username) == "string" then payload.username else nil,
				if type(payload.display_name) == "string" then payload.display_name else nil
			)
			return true, ""
		end
		return false, "unknown_command_type"
	end

	function service:_pollCommands()
		if not isCashDonationEnabled() or not isDonationHttpReady() or not isLicenseDonationAllowed() then
			return
		end
		local url = buildV2Url("commands", { limit = "20" })
		if url == "" then
			return
		end
		local ok, res = httpGet(url)
		if not ok then
			return -- poll loop already logs donation HTTP failures; stay quiet here
		end
		local parseOk, json = pcall(function()
			return HttpService:JSONDecode(res)
		end)
		if not parseOk or type(json) ~= "table" or not json.ok or type(json.commands) ~= "table" then
			return
		end
		local ackIds: { number } = {}
		local ackResults: { { id: number, ok: boolean, result: string } } = {}
		for _, cmd in ipairs(json.commands) do
			local id = math.floor(tonumber(cmd.id) or 0)
			if id > 0 then
				-- pcall returns (callOk, fnOk, fnErr) — unpack all three.
				local callOk, fnOk, fnErr = pcall(function()
					return executeGameCommand(cmd)
				end)
				local success = callOk and fnOk == true
				local resultMsg = if not callOk then tostring(fnOk) else tostring(fnErr or "")
				table.insert(ackIds, id)
				table.insert(ackResults, { id = id, ok = success, result = resultMsg })
				if success then
					log:info("Game command executed", { id = id, type = tostring(cmd.type) })
				else
					log:warn("Game command failed", { id = id, type = tostring(cmd.type), error = resultMsg })
				end
			end
		end
		if #ackIds > 0 then
			task.spawn(function()
				local postOk, postErr = httpPost(buildV2Url("commands/ack"), { ids = ackIds, results = ackResults })
				if not postOk then
					log:warn("Game command ack failed (non-blocking)", { error = tostring(postErr) })
				end
			end)
		end
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
		-- Never fall back to the RAW name on filter failure (G5, ADR 0004):
		-- a Roblox username is platform-moderated and safe; raw display text is not.
		local filteredDonatorName = filterForBroadcast(userId, donorName, 64)
			or robloxUsername
			or ("User" .. tostring(userId))

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
		local safe, blockReason = assertStudioManualDonationSafe()
		if not safe then
			return false, blockReason or "studio_live_blocked"
		end
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
		-- Allowed even when Studio writes live (isolation=false); add stays blocked.
		if Config.DataStoreScope.writesToLive() then
			log:warn("[RemoveRobux] Studio → live DataStore keys. Confirm this is intentional.", {
				userId = userId,
			})
		end
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
		if overheadService and type(overheadService.invalidateRankCaches) == "function" then
			overheadService:invalidateRankCaches(userId)
		end
		local onlinePlayer = Players:GetPlayerByUserId(userId)
		if onlinePlayer and type(service.refreshPlayerOverhead) == "function" then
			service:refreshPlayerOverhead(onlinePlayer)
		end
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
				-- Prefer estimated rank API (page scan + estimate) over raw page miss → nil.
				if donationLeaderboardRepository
					and type(donationLeaderboardRepository.getPlayerRobuxRank) == "function"
				then
					local rankResult = donationLeaderboardRepository:getPlayerRobuxRank(userId, robuxTotal)
					if rankResult.ok then
						robuxRank = rankResult.value
					end
				else
					robuxRank = resolveRobuxDonationRank(userId, username)
				end
			end
		end
		local cashTotal, cashRank = service:getPlayerCashStats(userId, username)
		if robuxTotal <= 0 then
			robuxRank = nil
		end
		if cashTotal <= 0 then
			cashRank = nil
		end
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
			-- Unlinked donor: provider nickname shown RAW on the workspace board.
			-- Owner decision 2026-08-24 (overrides ADR 0004 filter-at-write for the
			-- unlinked board fallback): the cash donor board displays the provider
			-- nickname as-is (cleanOptionalMessage only trims + clamps length; no text filter).
			displayName = cleanOptionalMessage(displayName, 64) or displayName

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
			-- Unlinked donor: provider nickname shown RAW on the workspace board.
			-- Owner decision 2026-08-24 (overrides ADR 0004 filter-at-write for the
			-- unlinked board fallback): the cash donor board displays the provider
			-- nickname as-is (cleanOptionalMessage only trims + clamps length; no text filter).
			displayName = cleanOptionalMessage(displayName, 64) or displayName

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
	-- In-memory tracking; WIB window 00:01-23:59:59, auto-reset after WIB midnight.
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
	-- forceRefresh: poll notifications + leaderboard immediately (debug / admin tool)
	function service:forceRefresh()
		log:info("Force refresh donation called")
		local ok, err = pcall(function()
			self:_pollLeaderboard(true)
			self:_pollNotifications()
		end)
		if not ok then
			log:error("Force refresh error", { error = tostring(err) })
		end
	end
	-- Admin: link external provider name -> roblox username via POST to sheets NameMap
	function service:linkDonor(saweriaName: string, robloxUsername: string): (boolean, string)
		local url = buildV2Url("donor-links")
		if url == "" then
			return false, "Donation API or DonationApiSecret not configured"
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
			log:warn("linkDonor PUT failed", { error = res })
			return false, res
		end
		-- Trigger refresh so assignment updates immediately
		task.delay(1, function()
			self:forceRefresh()
		end)
		log:info("Donor linked", { provider = getProviderName(), donor = cleanedSaweriaName, roblox = cleanedRobloxUsername })
		return true, ""
	end
	-- Player self-claim: assign external provider name to self
	function service:claimDonor(player: Player, saweriaName: string): (boolean, string)
		local userId = player.UserId
		local nowEpoch = os.time()
		cleanupClaimCooldowns(nowEpoch)
		-- Rate limit: once per day
		local lastClaim = claimCooldowns[userId]
		if lastClaim and (nowEpoch - lastClaim) < Config.Donation.CLAIM_COOLDOWN then
			return false, "rate_limited"
		end
		-- Find unassigned leaderboard entry with matching name (case-insensitive)
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
	-- Force re-assign all top 10 Saweria currently online. Bypass deduplication
	-- assignedRanks so if a player is stuck (rank in DataStore differs from
	-- leaderboard), can be force-synced. Used by /verifyspender admin command.
	-- Returns: { checked, assigned, missing, entries } for reporting.
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
		-- Reset tracking so applyLeaderboardDiff/assignPlayer treat all as "new".
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
	-- Helper: trigger overhead refresh for player. Used by /verifyspender
	-- so Robux top 10 that does not overlap with Saweria top 10 also gets refreshed.
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
	-- Assign overhead tag to newly joined player (if they are on the leaderboard)
	function service:onPlayerAdded(player: Player)
		local lowerName = player.Name:lower()
		local rank = assignedRanks[lowerName]
		if rank then
			-- Short delay so player DataStore is ready
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

	-- ── Public wrappers ───────────────────────────────────────────────────────
	-- Required so BackgroundJobScheduler in Main.server.luau can register
	-- jobs via type-check `type(donationService.pollDonations) == "function"`.
	-- Without this, that guard is always false and the scheduler becomes dead code.
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

	-- ── Reliability v2 wiring ───────────────────────────────────────────────
	-- Ack listener + retry sweep run only when the buyer opts in via
	-- ClubKitConfig.Donation.ReliabilityV2 = true. The sweep is a lightweight
	-- 1-second loop over the in-memory pending table (typically 0–20 entries);
	-- it fires zero HTTP calls when there is nothing to retry or report.
	local _reliabilityWired = false
	local function wireReliabilityV2()
		if _reliabilityWired or not isReliabilityV2Enabled() then
			return
		end
		_reliabilityWired = true
		if notifAckRemote then
			notifAckRemote.OnServerEvent:Connect(handleNotifAck)
		else
			log:warn("ReliabilityV2 enabled but notifAckRemote missing — acks disabled")
		end
		if notifDisplayRemote then
			notifDisplayRemote.OnServerEvent:Connect(handleNotifDisplay)
		end
		task.spawn(function()
			while _reliabilityWired do
				sweepPendingDeliveries()
				task.wait(1)
			end
		end)
		log:info("DonationService reliability v2 wired", {
			retryAfterSecs = Config.Donation.NOTIF_ACK_RETRY_AFTER_SECS,
			maxAttempts = Config.Donation.NOTIF_ACK_MAX_ATTEMPTS,
		})
	end
	wireReliabilityV2()

	log:info("DonationService initialized", {
		reliabilityV2 = isReliabilityV2Enabled(),
		notifPollInterval = Config.Donation.NOTIF_POLL_INTERVAL,
		notifBurstInterval = Config.Donation.NOTIF_BURST_INTERVAL,
		notifBurstWindow = Config.Donation.NOTIF_BURST_WINDOW,
		burstSchedulerWired = backgroundJobScheduler ~= nil,
		leaderboardPollInterval = Config.Donation.POLL_INTERVAL,
		httpTimeout = Config.Donation.HTTP_TIMEOUT,
		retryEnabled = Config.Donation.NOTIF_RETRY_ENABLED,
		coldStartCursorSeeded = notificationCursor ~= "",
		skipBeforeUnix = notificationSkipBeforeUnix,
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


	-- Cross-server donor cash sync: apply the ABSOLUTE totals other servers in
	-- this game publish (see publishCashTotalCrossServer). Monotonic — stale or
	-- duplicate messages (lower/equal total than we already have) are dropped;
	-- messages originating from THIS server are skipped (already applied locally).
	-- Best-effort: dropped messages simply fall back to the 45s TTL cache path.
	if Config.Donation.CROSS_SERVER_CASH_SYNC_ENABLED ~= false then
		task.spawn(function()
			local okSub, subErr = pcall(function()
				MessagingService:SubscribeAsync(CROSS_SERVER_CASH_TOPIC, function(message: any)
					local data = if type(message) == "table" then message.Data else nil
					if type(data) ~= "table" then
						return
					end
					if type(data.j) == "string" and data.j ~= "" and data.j == game.JobId then
						return -- own message (live servers have unique JobIds)
					end
					local userId = tonumber(data.u)
					local total = tonumber(data.t)
					if type(userId) ~= "number" or userId <= 0 or type(total) ~= "number" or total <= 0 then
						return
					end
					local cached = donorCashCache[userId]
					if cached and cached.total >= total then
						return -- stale / already newer locally
					end
					applyInstantCashTotal(userId, total, true) -- suppress re-publish
					log:debug("Cross-server cash sync applied", { userId = userId, total = total })
				end)
			end)
			if okSub then
				log:info("Cross-server cash sync subscribed", { topic = CROSS_SERVER_CASH_TOPIC })
			else
				log:warn("Cross-server cash sync subscribe failed", { error = tostring(subErr) })
			end
		end)
	end

	return service
end
return createDonationService
