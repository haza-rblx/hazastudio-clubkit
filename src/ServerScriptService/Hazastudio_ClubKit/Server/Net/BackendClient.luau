--!strict
-- Server/Net/BackendClient.luau
--
-- The one entry for the kit's calls to the ClubKit VPS (production hardening P3, workstream C;
-- plan §2 C1). Call sites keep their request/response handling; they hand the URL *without*
-- a secret to `request`, which returns what `pcall(HttpRequest.requestAsync, …)` returned
-- (ok, RequestAsync response | error string), so the switch below is the whole rollback.
--
-- Config.BackendClient.ENABLED = true:
--   * the secret goes in `Authorization: Bearer` only — never in the query string (the VPS
--     accepts both until P5, which will reject ?secret=; P2 logs who still sends it);
--   * one per-server token bucket (RATE_PER_MIN / BURST, well under Roblox's 500/min) with
--     priority floors — critical may drain it, normal stops at 25 % left, bulk at 50 % left and
--     waits (up to MAX_WAIT_SEC) instead of being dropped;
--   * a 429 `{error:"rate_limited", retry_after:N}` / Retry-After pauses every priority N s;
--   * a circuit breaker per endpoint group (Shared/Domain/HttpBudgetPolicy);
--   * `Timeout` is always a whole number of seconds.
-- Config.BackendClient.ENABLED = false: the pre-P3 request exactly (legacyQuerySecret call sites
-- put `?secret=` back, no bucket, no breaker).
-- Either way every request goes through Net/HttpRequest, so BudgetMeter counts it.
--
-- Not routed here on purpose: LicenseService and Init/IntegrityTripwire (ADR 0006 keeps the
-- licence and tripwire HTTP self-contained; < 1 request per 30 min, header auth already).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local BudgetMeter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetMeter)
local HttpBudgetPolicy = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.HttpBudgetPolicy)
local HttpRequest = require(script.Parent.HttpRequest)

export type Auth = "donation" | "gamedata" | "none"

export type Request = {
	endpoint: string, -- counter class, e.g. "donation:v2/notifications"
	url: string, -- full URL, never containing a secret
	method: string?,
	auth: Auth?,
	headers: { [string]: string }?,
	body: string?,
	priority: string?, -- "critical" | "normal" | "bulk" (default "normal")
	timeoutSec: number?,
	group: string?, -- breaker group (default: the endpoint prefix before ":")
	-- Legacy mode only: the pre-P3 call carried the secret as ?secret= (gamedata routes).
	legacyQuerySecret: boolean?,
}

type EndpointStats = {
	calls: number,
	failures: number,
	http429: number,
	timeouts: number,
	latencies: { number },
	latencyIndex: number,
}

local LATENCY_SAMPLES = 64

local BackendClient = {}

local bucket: HttpBudgetPolicy.Bucket? = nil
local breakers: { [string]: HttpBudgetPolicy.Breaker } = {}
local stats: { [string]: EndpointStats } = {}

local function cfg(): any
	local c = Config.BackendClient
	return if type(c) == "table" then c else {}
end

function BackendClient.isEnabled(): boolean
	return cfg().ENABLED == true
end

--- "donation" → Secrets.DonationApiSecret (game secret, {ApiUrl} routes);
--- "gamedata" → Secrets.GameDataApiSecret (social secret, /social routes). "" when unset.
function BackendClient.readSecret(auth: Auth?): string
	if auth == "none" or auth == nil then
		return ""
	end
	local ok, secrets = pcall(function()
		return require(ServerScriptService.Hazastudio_ClubKitSecrets.Secrets) :: any
	end)
	if not ok or type(secrets) ~= "table" then
		return ""
	end
	local value = if auth == "gamedata" then secrets.GameDataApiSecret else secrets.DonationApiSecret
	return if type(value) == "string" then value else ""
end

local function getBucket(): HttpBudgetPolicy.Bucket
	local current = bucket
	if current then
		return current
	end
	local c = cfg()
	local created = HttpBudgetPolicy.newBucket({
		ratePerMin = tonumber(c.RATE_PER_MIN) or 400,
		burst = tonumber(c.BURST) or 40,
		floors = if type(c.FLOORS) == "table" then c.FLOORS else { critical = 0, normal = 0.25, bulk = 0.5 },
	}, os.clock())
	bucket = created
	return created
end

local function getBreaker(group: string): HttpBudgetPolicy.Breaker
	local existing = breakers[group]
	if existing then
		return existing
	end
	local b = cfg().BREAKER
	local created = HttpBudgetPolicy.newBreaker({
		consecutive = if type(b) == "table" and b.consecutive then b.consecutive else 5,
		windowSec = if type(b) == "table" and b.windowSec then b.windowSec else 30,
		failRatio = if type(b) == "table" and b.failRatio then b.failRatio else 0.5,
		minSamples = if type(b) == "table" and b.minSamples then b.minSamples else 6,
		openSteps = if type(b) == "table" and type(b.openSteps) == "table" then b.openSteps else { 30, 60, 120 },
	})
	breakers[group] = created
	return created
end

local function statsFor(endpoint: string): EndpointStats
	local s = stats[endpoint]
	if not s then
		s = { calls = 0, failures = 0, http429 = 0, timeouts = 0, latencies = {}, latencyIndex = 0 }
		stats[endpoint] = s
	end
	return s
end

local function maxWaitFor(priority: string): number
	local waits = cfg().MAX_WAIT_SEC
	local value = if type(waits) == "table" then tonumber(waits[priority]) else nil
	return value or (if priority == "bulk" then 60 else if priority == "critical" then 10 else 15)
end

local function withQuerySecret(url: string, secret: string): string
	local separator = if string.find(url, "?", 1, true) then "&" else "?"
	return url .. separator .. "secret=" .. secret
end

local function legacyRequest(req: Request): (boolean, any)
	local secret = BackendClient.readSecret(req.auth)
	local headers = if req.headers then table.clone(req.headers) else {}
	local url = req.url
	if req.auth ~= "none" and req.auth ~= nil then
		if req.legacyQuerySecret then
			url = withQuerySecret(url, secret)
		else
			headers.Authorization = "Bearer " .. secret
		end
	end
	local requestTable: { [string]: any } = { Url = url, Method = req.method or "GET", Headers = headers }
	if req.body ~= nil then
		requestTable.Body = req.body
	end
	if req.timeoutSec ~= nil then
		requestTable.Timeout = req.timeoutSec
	end
	return pcall(HttpRequest.requestAsync, req.endpoint, requestTable)
end

--- Waits for a token for `priority`; false when the wait would exceed its MAX_WAIT_SEC.
local function admit(priority: string): boolean
	local maxWait = maxWaitFor(priority)
	local waited = 0
	local deferred = false
	while true do
		local ok, wait = HttpBudgetPolicy.tryTake(getBucket(), priority, os.clock())
		if ok then
			return true
		end
		if waited + wait > maxWait then
			BudgetMeter.recordEvent("http_local_refused")
			return false
		end
		if not deferred then
			deferred = true
			BudgetMeter.recordEvent("http_local_deferred")
		end
		local step = math.max(0.05, wait)
		task.wait(step)
		waited += step
	end
end

--- Sends one VPS request. Returns (ok, response) like pcall(HttpRequest.requestAsync, …):
--- ok=false carries an error string ("backend_client:*" for local refusals).
function BackendClient.request(req: Request): (boolean, any)
	if not BackendClient.isEnabled() then
		return legacyRequest(req)
	end
	local auth = req.auth or "none"
	local secret = ""
	if auth ~= "none" then
		secret = BackendClient.readSecret(auth)
		if secret == "" then
			return false, "backend_client:secret_missing"
		end
	end
	local priority = req.priority or "normal"
	local group = req.group or string.match(req.endpoint, "^([^:]+)") or "other"
	local breaker = getBreaker(group)
	if HttpBudgetPolicy.breakerState(breaker, os.clock()) == "open" then
		BudgetMeter.recordEvent("http_breaker_refused")
		return false, "backend_client:breaker_open"
	end
	if not admit(priority) then
		return false, "backend_client:rate_limited"
	end
	if not HttpBudgetPolicy.breakerAllow(breaker, os.clock()) then
		BudgetMeter.recordEvent("http_breaker_refused")
		return false, "backend_client:breaker_open"
	end
	BudgetMeter.observeBudget("HttpBucketPct", math.floor(HttpBudgetPolicy.fill(getBucket(), os.clock()) * 100))

	local headers = if req.headers then table.clone(req.headers) else {}
	if auth ~= "none" then
		headers.Authorization = "Bearer " .. secret
	end
	local requestTable: { [string]: any } = {
		Url = req.url,
		Method = req.method or "GET",
		Headers = headers,
		Timeout = HttpBudgetPolicy.timeoutSeconds(req.timeoutSec, tonumber(cfg().DEFAULT_TIMEOUT_SEC) or 5),
	}
	if req.body ~= nil then
		requestTable.Body = req.body
	end

	local startedAt = os.clock()
	local ok, response = pcall(HttpRequest.requestAsync, req.endpoint, requestTable)
	local now = os.clock()
	local s = statsFor(req.endpoint)
	s.calls += 1
	s.latencyIndex = (s.latencyIndex % LATENCY_SAMPLES) + 1
	s.latencies[s.latencyIndex] = now - startedAt

	local statusCode = if ok and type(response) == "table" then (tonumber(response.StatusCode) or 0) else 0
	if not ok then
		s.failures += 1
		local message = string.lower(tostring(response))
		if string.find(message, "timed out", 1, true) or string.find(message, "timeout", 1, true) then
			s.timeouts += 1
			BudgetMeter.recordEvent("http_timeout")
		end
	elseif statusCode == 429 then
		s.http429 += 1
		local body = if type(response.Body) == "string" then response.Body else nil
		local seconds = HttpBudgetPolicy.parseRetryAfter(response.Headers, body) or 30
		HttpBudgetPolicy.pause(getBucket(), now, seconds, tonumber(cfg().MAX_RETRY_AFTER_SEC) or 300)
		BudgetMeter.recordEvent("http_429_pause")
	elseif HttpBudgetPolicy.isFailureStatus(statusCode) then
		s.failures += 1
	end
	local wasOpen = HttpBudgetPolicy.breakerState(breaker, now) ~= "closed"
	HttpBudgetPolicy.breakerRecord(breaker, now, ok and not HttpBudgetPolicy.isFailureStatus(statusCode))
	if not wasOpen and HttpBudgetPolicy.breakerState(breaker, now) == "open" then
		BudgetMeter.recordEvent("http_breaker_open")
		warn(string.format("[BackendClient] circuit open for %s (VPS failing); calls refused for a while", group))
	end
	return ok, response
end

--- Counters per endpoint class (calls, failures, 429s, timeouts, p95 latency in ms).
function BackendClient.getStats(): { [string]: any }
	local out: { [string]: any } = {}
	for endpoint, s in pairs(stats) do
		local sorted = table.clone(s.latencies)
		table.sort(sorted)
		local p95 = if #sorted > 0 then sorted[math.max(1, math.ceil(#sorted * 0.95))] else 0
		out[endpoint] = {
			calls = s.calls,
			failures = s.failures,
			http429 = s.http429,
			timeouts = s.timeouts,
			p95Ms = math.floor(p95 * 1000),
		}
	end
	return out
end

function BackendClient.bucketFill(): number
	return HttpBudgetPolicy.fill(getBucket(), os.clock())
end

--- UrlEncode for call sites that build query strings (kept here so Net owns URL building).
function BackendClient.urlEncode(value: string): string
	return HttpService:UrlEncode(value)
end

return BackendClient
