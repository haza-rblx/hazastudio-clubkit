--!strict
-- Server/Net/BudgetTelemetry.luau
--
-- Budget telemetry to the VPS (production hardening P3, workstream F; ADR 0007 phase B, minimal).
-- Main.server's budget job rolls a BudgetMeter window every 60 s and hands it to `absorb`; every
-- Config.Telemetry.BUDGET_INTERVAL_SEC (15 min) the aggregate goes to the route that has been live
-- since ADR 0007 phase A:
--   POST {ApiUrl}/v3/telemetry  { kind = "budget", kit_version, payload }   (≤ 32 KB, 90 d retention)
-- at bulk priority through BackendClient (Authorization: Bearer). Aggregate counts only — never a
-- player id (BudgetMeter.aggregatePayload). Off when the buyer sets ClubKitConfig.Telemetry.Enabled
-- = false, when BackendClient is off (the P3 rollback), or when the donation API is not configured.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local BudgetMeter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetMeter)
local BackendClient = require(script.Parent.BackendClient)

local BudgetTelemetry = {}

local aggregate = BudgetMeter.newAggregate()
local aggregateStartedAt = os.clock()

local function telemetryConfig(): any
	local t = Config.Telemetry
	return if type(t) == "table" then t else {}
end

local function baseUrl(): string
	local base = Config.Donation and Config.Donation.SHEETS_WEB_APP_URL
	if type(base) ~= "string" or base == "" then
		return ""
	end
	return (string.gsub(base, "/+$", ""))
end

function BudgetTelemetry.isEnabled(): boolean
	return telemetryConfig().ENABLED == true and BackendClient.isEnabled() and baseUrl() ~= ""
end

local function kitVersion(): string
	local ok, kitProduct = pcall(function()
		return require(ReplicatedStorage.Hazastudio_ClubKit.KitProduct) :: any
	end)
	if ok and type(kitProduct) == "table" and type(kitProduct.KitVersion) == "string" then
		return kitProduct.KitVersion
	end
	return ""
end

local function send(payload: { [string]: any })
	local path = telemetryConfig().PATH or "/v3/telemetry"
	local encodeOk, body = pcall(function()
		return HttpService:JSONEncode({ kind = "budget", kit_version = kitVersion(), payload = payload })
	end)
	if not encodeOk then
		return
	end
	local ok, response = BackendClient.request({
		endpoint = "donation:v3/telemetry",
		url = baseUrl() .. path,
		method = "POST",
		auth = "donation",
		headers = { ["Content-Type"] = "application/json" },
		body = body,
		priority = "bulk",
		timeoutSec = 10,
	})
	if not ok or type(response) ~= "table" or response.Success ~= true then
		-- Best effort: the next aggregate carries on; nothing is retried or kept.
		BudgetMeter.recordEvent("telemetry_send_failed")
	end
end

--- One rolled window (`BudgetMeter.rollWindow()`). Sends the aggregate when the interval is up.
function BudgetTelemetry.absorb(snap: BudgetMeter.Snapshot)
	if not BudgetTelemetry.isEnabled() then
		return
	end
	BudgetMeter.absorb(aggregate, snap, #Players:GetPlayers())
	local interval = tonumber(telemetryConfig().BUDGET_INTERVAL_SEC) or 900
	if os.clock() - aggregateStartedAt < interval then
		return
	end
	local payload = BudgetMeter.aggregatePayload(aggregate)
	payload.endpoints = BackendClient.getStats()
	aggregate = BudgetMeter.newAggregate()
	aggregateStartedAt = os.clock()
	task.spawn(send, payload)
end

return BudgetTelemetry
