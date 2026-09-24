--!strict
-- Server/Net/HttpRequest.luau
--
-- Thin counting wrapper around HttpService (production hardening P1, workstream F). Every kit
-- call to the VPS / Roblox proxies goes through here so BudgetMeter can report HTTP requests by
-- endpoint class against the 500/min per-server limit.
--
-- Behaviour is deliberately unchanged: same request table, same return value, and a failing
-- call raises the same error message (callers already pcall). Rate limiting, priorities and
-- header-only secrets belong to the P3 BackendClient, which will replace this module.
--
-- Not routed here on purpose: LicenseService and IntegrityTripwire (ADR 0006 keeps the license
-- and tripwire HTTP sites self-contained; together they send < 1 request per 30 min).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BudgetMeter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetMeter)

local HttpRequest = {}

--- Endpoint class from a URL path for callers that share one request helper (DonationService):
--- "https://api.hazastudio.id/game/<key>/v2/players/123/cash?secret=…" → "donation:v2/players/:id/cash".
--- Only the path is used (query string, and so any secret in it, is dropped); the venue key segment
--- after /game/ is dropped; numbers become :id.
function HttpRequest.classFromUrl(prefix: string, url: string): string
	local path = string.match(url, "^%a+://[^/]+(/[^?#]*)") or ""
	path = string.gsub(path, "^/game/[^/]+", "")
	path = string.gsub(path, "/%d+", "/:id")
	path = string.gsub(path, "^/+", "")
	path = string.gsub(path, "/+$", "")
	if path == "" then
		path = "root"
	end
	return prefix .. ":" .. string.sub(path, 1, 48)
end

--- HttpService:RequestAsync, counted under `endpointClass` (e.g. "donation_notifications").
function HttpRequest.requestAsync(endpointClass: string, request: any): any
	local ok, response = pcall(function()
		return HttpService:RequestAsync(request)
	end)
	if not ok then
		BudgetMeter.recordHttp(endpointClass, false, nil)
		error(response, 0)
	end
	local statusCode = if type(response) == "table" then tonumber(response.StatusCode) else nil
	-- RequestAsync sets Success only for 2xx; a 304 (ETag poll, unchanged board/library) is the
	-- healthy answer for those callers, so it is not a failure here.
	local success = (type(response) == "table" and response.Success == true) or statusCode == 304
	BudgetMeter.recordHttp(endpointClass, success, statusCode)
	return response
end

--- HttpService:GetAsync, counted under `endpointClass`.
function HttpRequest.getAsync(endpointClass: string, url: string, nocache: boolean?, headers: any?): string
	local ok, body = pcall(function()
		return HttpService:GetAsync(url, nocache == true, headers)
	end)
	BudgetMeter.recordHttp(endpointClass, ok, nil)
	if not ok then
		error(body, 0)
	end
	return body
end

return HttpRequest
