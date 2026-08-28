--!strict
-- Server-only license verification for Club Kit v1.3+.
-- Older kit builds without LicenseEnforcementEnabled are unaffected.
--
-- Fail policy (ADR 0006 Pillar 2):
--   * The server answered and said NO with a definitive reason (universe_mismatch
--     / revoked / expired) -> HARD DENY: features off, and sticky (a later network
--     blip cannot re-open it). This is what catches a copied place pointed at the
--     real VPS with a stolen secret.
--   * Previously verified OK, now unreachable -> keep the last verdict for
--     OFFLINE_GRACE_SECONDS (24h), then close.
--   * Never got a definitive answer (timeout / DNS / no ApiUrl / Studio flake) ->
--     stay optimistic: we cannot tell a flaky-network or non-donation legit buyer
--     from a thief who firewalled the endpoint. The VPS-side universe check
--     (Pillar 1) + leak beacon (Pillar 3) are what close that gap, not a guess here.

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KitProduct = require(ReplicatedStorage.Hazastudio_ClubKit.KitProduct)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

export type LicenseStatus =
	"active" | "grace" | "expired" | "revoked" | "unlicensed" | "unknown" | "offline"

export type LicenseFeatures = {
	donation_http: boolean,
	shop_grant: boolean,
	admin_commands: boolean,
}

export type LicenseState = {
	status: LicenseStatus,
	features: LicenseFeatures,
	checkedAt: number,
	lastError: string?,
	enforcementActive: boolean,
}

local log = Logger.new("LicenseService")

local OFFLINE_GRACE_SECONDS = 86400 -- 24h (ADR 0006 decision)
local DEFAULT_POLL_SECONDS = 1800

local _started = false
local _apiUrl = ""
local _secret = ""
local _pollInterval = DEFAULT_POLL_SECONDS
local _lastSuccessWallClock = 0
-- Sticky: set when the server gave a definitive denial. Cleared only by a later
-- successful (ok=true) verify. Overrides the optimistic offline path.
local _hardDenied = false
-- Leak beacon fires at most once per server (ADR 0006 Pillar 3).
local _beaconSent = false
-- Live tamper reports (ADR 0006 Pillar 5) — deduped per reason.
local _tamperReported: { [string]: boolean } = {}
local _state: LicenseState = {
	status = "unknown",
	features = { donation_http = true, shop_grant = true, admin_commands = true },
	checkedAt = 0,
	lastError = nil,
	enforcementActive = false,
}

local function isEnforcementEnabled(): boolean
	return (KitProduct :: any).LicenseEnforcementEnabled == true
end

local function deriveVerifyUrl(apiBase: string): string
	local trimmed = apiBase:gsub("/+$", "")
	return trimmed .. "/v2/license/verify"
end

-- Leak beacon (ADR 0006 Pillar 3): when this server learns it is running in an
-- unlicensed universe, it reports the infringing place + owner to the VPS, which
-- forwards a Discord alert from an allowed IP (the game server itself cannot
-- reach Discord). Best-effort and fire-once; never blocks or errors the caller.
local function postBeacon(reason: string, extra: { [string]: any }?)
	if _apiUrl == "" or _secret == "" then
		return
	end
	local url = _apiUrl:gsub("/+$", "") .. "/v2/beacon"
	local creatorType = if game.CreatorType == Enum.CreatorType.Group then "Group" else "User"
	local payload: { [string]: any } = {
		reason = reason,
		universe_id = game.GameId,
		place_id = game.PlaceId,
		creator_id = game.CreatorId,
		creator_type = creatorType,
		job_id = game.JobId,
		kit_version = KitProduct.KitVersion,
		build_id = KitProduct.BuildId,
		player_count = #game:GetService("Players"):GetPlayers(),
	}
	if extra then
		for k, v in extra do
			payload[k] = v
		end
	end
	task.spawn(function()
		pcall(function()
			HttpService:RequestAsync({
				Url = url,
				Method = "POST",
				Headers = {
					Authorization = "Bearer " .. _secret,
					["Content-Type"] = "application/json",
				},
				Body = HttpService:JSONEncode(payload),
				Timeout = 10,
			})
		end)
	end)
end

local function sendBeacon(reason: string)
	if _beaconSent then
		return
	end
	_beaconSent = true
	postBeacon(reason)
end

local function parseFeatures(raw: any): LicenseFeatures
	if type(raw) ~= "table" then
		return { donation_http = false, shop_grant = false, admin_commands = false }
	end
	return {
		donation_http = raw.donation_http == true,
		shop_grant = raw.shop_grant == true,
		admin_commands = raw.admin_commands == true,
	}
end

local function allFeaturesDisabled(): LicenseFeatures
	return { donation_http = false, shop_grant = false, admin_commands = false }
end

local function allFeaturesEnabled(): LicenseFeatures
	return { donation_http = true, shop_grant = true, admin_commands = true }
end

-- Mark a definitive denial from the server. Sticky until a later ok=true verify.
local function markHardDenied(status: LicenseStatus, reason: string)
	_hardDenied = true
	_state.status = status
	_state.features = allFeaturesDisabled()
	_state.lastError = reason
	_state.checkedAt = os.clock()
end

local function applyOfflinePolicy()
	if _lastSuccessWallClock <= 0 then
		-- Never got a definitive answer. Stay optimistic here (see file header);
		-- definitive denials are handled by _hardDenied, not this path.
		_state.status = "unknown"
		_state.features = allFeaturesEnabled()
		return
	end
	if os.time() - _lastSuccessWallClock > OFFLINE_GRACE_SECONDS then
		_state.status = "offline"
		_state.features = allFeaturesDisabled()
	end
	-- Within grace: leave the last known-good features untouched.
end

local function isDefiniteDenialStatus(statusRaw: string): boolean
	return statusRaw == "revoked" or statusRaw == "expired" or statusRaw == "unlicensed"
end

local function refreshOnce(): boolean
	if not isEnforcementEnabled() then
		_hardDenied = false
		_state.enforcementActive = false
		_state.status = "active"
		_state.features = allFeaturesEnabled()
		_state.checkedAt = os.clock()
		_state.lastError = nil
		return true
	end

	if _apiUrl == "" or _secret == "" then
		-- No license endpoint configured. Cannot verify -> cannot enforce in-kit
		-- (a non-donation buyer legitimately has no ApiUrl). Not a hard denial.
		_state.enforcementActive = true
		_state.lastError = "missing_api_config"
		_state.status = "unknown"
		_state.features = allFeaturesEnabled()
		_state.checkedAt = os.clock()
		return false
	end

	_state.enforcementActive = true
	local body = HttpService:JSONEncode({
		universe_id = game.GameId,
		place_id = game.PlaceId,
		job_id = game.JobId,
		kit_version = KitProduct.KitVersion,
		build_id = KitProduct.BuildId,
	})

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = deriveVerifyUrl(_apiUrl),
			Method = "POST",
			Headers = {
				Authorization = "Bearer " .. _secret,
				["Content-Type"] = "application/json",
			},
			Body = body,
			Timeout = 10,
		})
	end)

	if not ok or type(response) ~= "table" then
		-- Network/DNS/timeout: no answer from the server. Offline policy.
		_state.lastError = tostring(response)
		_state.checkedAt = os.clock()
		applyOfflinePolicy()
		return false
	end

	if response.Success ~= true then
		local bodyStr = if type(response.Body) == "string" then response.Body else ""
		_state.lastError = if bodyStr ~= "" then bodyStr else ("HTTP " .. tostring(response.StatusCode))
		_state.checkedAt = os.clock()
		-- A 403 naming universe_mismatch is a definitive denial: this universe is
		-- not the licensed one (a copied place). Fail closed and stick.
		if
			response.StatusCode == 403
			and string.find(string.lower(bodyStr), "universe_mismatch", 1, true) ~= nil
		then
			markHardDenied("unlicensed", "universe_mismatch")
			log:warn("License denied: universe mismatch (unlicensed place)", {
				universeId = game.GameId,
				placeId = game.PlaceId,
			})
			sendBeacon("universe_mismatch")
			return false
		end
		-- Any other non-success (5xx, transient 4xx) -> offline policy, not sticky.
		applyOfflinePolicy()
		return false
	end

	local decodeOk, parsed = pcall(function()
		return HttpService:JSONDecode(if type(response.Body) == "string" then response.Body else "{}")
	end)
	if not decodeOk or type(parsed) ~= "table" then
		_state.lastError = "invalid_json"
		_state.checkedAt = os.clock()
		applyOfflinePolicy()
		return false
	end

	local statusRaw = tostring(parsed.status or "unknown")
	if
		statusRaw == "active"
		or statusRaw == "grace"
		or statusRaw == "expired"
		or statusRaw == "revoked"
		or statusRaw == "unlicensed"
	then
		_state.status = statusRaw :: LicenseStatus
	else
		_state.status = "unknown"
	end

	_state.checkedAt = os.clock()

	if parsed.ok == true then
		-- Licensed. Apply server features and clear any prior denial.
		_hardDenied = false
		_state.features = parseFeatures(parsed.features)
		_state.lastError = nil
		_lastSuccessWallClock = os.time()
	elseif isDefiniteDenialStatus(statusRaw) then
		-- Server answered and definitively said no. Fail closed and stick.
		markHardDenied(_state.status, tostring(parsed.error or statusRaw))
	else
		-- ok=false but not a definitive status (e.g. transient server-side issue).
		_state.features = parseFeatures(parsed.features)
		_state.lastError = tostring(parsed.error or "license_invalid")
	end

	local nextCheck = tonumber(parsed.next_check_seconds)
	if type(nextCheck) == "number" and nextCheck >= 60 then
		_pollInterval = math.floor(nextCheck)
	end

	return parsed.ok == true
end

local LicenseService = {}

function LicenseService.isEnforcementEnabled(): boolean
	return isEnforcementEnabled()
end

function LicenseService.isEnforcementActive(): boolean
	return isEnforcementEnabled() and _state.enforcementActive
end

function LicenseService.isFeatureEnabled(feature: string): boolean
	if not isEnforcementEnabled() then
		return true
	end

	-- Definitive denial overrides everything, including the boot window.
	if _hardDenied then
		return false
	end

	-- Optimistic while the first verify is still in flight — otherwise donation_poll
	-- no-ops for the whole boot window (and forever if verify hangs/times out first).
	-- awaitInitialCheck() blocks boot up to 10s, so this window is short and a
	-- definitive denial (which arrives fast) has already flipped _hardDenied.
	if _state.checkedAt <= 0 then
		return true
	end

	if _state.status == "offline" or _state.status == "unknown" then
		applyOfflinePolicy()
	end

	local features = _state.features
	if feature == "donation_http" then
		return features.donation_http
	elseif feature == "shop_grant" then
		return features.shop_grant
	elseif feature == "admin_commands" then
		return features.admin_commands
	end
	return false
end

function LicenseService.getState(): LicenseState
	return _state
end

function LicenseService.forceRefresh(): boolean
	return refreshOnce()
end

function LicenseService.awaitInitialCheck(timeoutSeconds: number): ()
	if not isEnforcementEnabled() then
		return
	end
	if RunService:IsStudio() and _secret == "" then
		return
	end

	local deadline = os.clock() + timeoutSeconds
	while _state.checkedAt <= 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end

function LicenseService.start(config: { apiUrl: string, secret: string }): ()
	if _started then
		return
	end
	_started = true

	if not isEnforcementEnabled() then
		log:info("License enforcement disabled for this kit build")
		_hardDenied = false
		_state.status = "active"
		_state.enforcementActive = false
		_state.features = allFeaturesEnabled()
		_state.checkedAt = os.clock()
		return
	end

	_apiUrl = config.apiUrl
	_secret = config.secret

	if RunService:IsStudio() and _secret == "" then
		log:info("Studio without DonationApiSecret — license verify skipped")
		_hardDenied = false
		_state.status = "active"
		_state.enforcementActive = false
		_state.features = allFeaturesEnabled()
		_state.checkedAt = os.clock()
		return
	end

	task.spawn(function()
		refreshOnce()
	end)

	task.spawn(function()
		while _started do
			task.wait(_pollInterval)
			if _started then
				refreshOnce()
			end
		end
	end)

	log:info("LicenseService started", { pollInterval = _pollInterval })
end

-- Report a live tamper / exploit signal (ADR 0006 Pillar 5), e.g. a saveinstance
-- probe detected on a client. Separate from the once-only universe_mismatch
-- beacon; lightly deduped per reason so a spamming exploiter cannot flood the
-- endpoint. Best-effort — never blocks or errors the caller.
function LicenseService.reportTamper(reason: string, extra: { [string]: any }?): ()
	local key = tostring(reason)
	if _tamperReported[key] then
		return
	end
	_tamperReported[key] = true
	postBeacon("tamper:" .. key, extra)
end

function LicenseService.stop(): ()
	_started = false
end

return LicenseService
