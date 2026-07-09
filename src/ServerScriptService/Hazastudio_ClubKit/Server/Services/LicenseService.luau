--!strict
-- Server-only license verification for Club Kit v1.3+.
-- Older kit builds without LicenseEnforcementEnabled are unaffected.

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KitProduct = require(ReplicatedStorage.Hazastudio_ClubKit.KitProduct)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

export type LicenseStatus = "active" | "grace" | "expired" | "revoked" | "unknown" | "offline"

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

local OFFLINE_GRACE_SECONDS = 86400
local DEFAULT_POLL_SECONDS = 1800

local _started = false
local _apiUrl = ""
local _secret = ""
local _pollInterval = DEFAULT_POLL_SECONDS
local _lastSuccessWallClock = 0
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

local function applyOfflinePolicy()
	if _lastSuccessWallClock <= 0 then
		_state.status = "unknown"
		_state.features = allFeaturesDisabled()
		return
	end
	if os.time() - _lastSuccessWallClock > OFFLINE_GRACE_SECONDS then
		_state.status = "offline"
		_state.features = allFeaturesDisabled()
	end
end

local function refreshOnce(): boolean
	if not isEnforcementEnabled() then
		_state.enforcementActive = false
		_state.status = "active"
		_state.features = allFeaturesEnabled()
		_state.checkedAt = os.clock()
		_state.lastError = nil
		return true
	end

	if _apiUrl == "" or _secret == "" then
		_state.enforcementActive = true
		_state.lastError = "missing_api_config"
		_state.status = "unknown"
		_state.features = allFeaturesDisabled()
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
		_state.lastError = tostring(response)
		_state.checkedAt = os.clock()
		applyOfflinePolicy()
		return false
	end

	if response.Success ~= true then
		_state.lastError = if type(response.Body) == "string" then response.Body else ("HTTP " .. tostring(response.StatusCode))
		_state.checkedAt = os.clock()
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
	if statusRaw == "active" or statusRaw == "grace" or statusRaw == "expired" or statusRaw == "revoked" then
		_state.status = statusRaw :: LicenseStatus
	else
		_state.status = "unknown"
	end

	_state.features = parseFeatures(parsed.features)
	_state.checkedAt = os.clock()
	_lastSuccessWallClock = os.time()
	_state.lastError = if parsed.ok == true then nil else tostring(parsed.error or "license_invalid")

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

	if _state.checkedAt <= 0 then
		return false
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

function LicenseService.stop(): ()
	_started = false
end

return LicenseService
