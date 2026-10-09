--!strict
-- Server/Net/InstanceTelemetry.luau
--
-- Instance-diet probe (docs/plans/instance-diet-2026-10-09.md, phase 1). TEMPORARY: remove it when the
-- owner closes the instance diet. It measures how many instances the kit adds per player from live
-- servers, instead of multi-client Studio tests (memory no-multiplayer-playtest).
--   - Server: samples Stats.InstanceCount every Config.Telemetry.INSTANCES_SAMPLE_SEC.
--   - Clients: InstanceProbeClient sends its samples over the InstanceProbeReport RemoteEvent every
--     INSTANCES_CLIENT_BATCH_SEC. A batch is dropped silently unless it is an array of at most 10
--     entries with sane finite numbers, and only one batch per player per 240 s is looked at.
--   - Flush every INSTANCES_FLUSH_SEC: POST {ApiUrl}/v3/telemetry { kind = "instances", kit_version,
--     payload } at bulk priority, the same route and send path as BudgetTelemetry (ADR 0007 phase B).
--     Aggregates only: no UserIds, no names. The body is kept under 32 KB.
-- Off when INSTANCES_ENABLED is false, when Config.Telemetry.ENABLED is false (buyer opt-out), or when
-- BudgetTelemetry.isEnabled() is false. Then no loop starts and no remote listener is connected.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stats = game:GetService("Stats")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local BudgetMeter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetMeter)
local BackendClient = require(script.Parent.BackendClient)
local BudgetTelemetry = require(script.Parent.BudgetTelemetry)

local InstanceTelemetry = {}

type Sample = { [string]: number }

local MAX_BATCH_ENTRIES = 10
local PLAYER_BATCH_GAP_SEC = 240
local MAX_BODY_BYTES = 32 * 1024
local MAX_SERVER_SAMPLES = 200
local MAX_CLIENT_SAMPLES = 2000
local MAX_BUCKETS = 100
local MAX_OTHERS = 1000

-- Client fields and their sane ceilings. A value above its ceiling makes the whole batch invalid.
local SAMPLE_FIELDS: { { name: string, max: number } } = {
	{ name = "clientIC", max = 5000000 },
	{ name = "memMb", max = 100000 },
	{ name = "othersBackpack", max = 5000000 },
	{ name = "othersCharacter", max = 5000000 },
	{ name = "ownPlayerGui", max = 500000 },
}

local serverSamples: { Sample } = {}
local clientSamples: { Sample } = {}
local lastBatchAt: { [Player]: number } = {}

local function telemetryConfig(): any
	local t = Config.Telemetry
	return if type(t) == "table" then t else {}
end

local function positiveSeconds(value: any, default: number): number
	local n = tonumber(value)
	if n ~= nil and n > 0 then
		return n
	end
	return default
end

local function intervals(): (number, number, number)
	local t = telemetryConfig()
	return positiveSeconds(t.INSTANCES_SAMPLE_SEC, 60),
		positiveSeconds(t.INSTANCES_CLIENT_BATCH_SEC, 300),
		positiveSeconds(t.INSTANCES_FLUSH_SEC, 900)
end

local function enabled(): boolean
	local t = telemetryConfig()
	return t.INSTANCES_ENABLED == true and t.ENABLED == true and BudgetTelemetry.isEnabled()
end

local function baseUrl(): string
	local base = Config.Donation and Config.Donation.SHEETS_WEB_APP_URL
	if type(base) ~= "string" or base == "" then
		return ""
	end
	return (string.gsub(base, "/+$", ""))
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

local function round1(x: number): number
	return math.floor(x * 10 + 0.5) / 10
end

-- NaN fails both comparisons and infinity fails the ceiling, so one check covers "finite and sane".
local function isSaneNumber(value: any, max: number): boolean
	return type(value) == "number" and value >= 0 and value <= max
end

local function validBatch(batch: any): { any }?
	if type(batch) ~= "table" then
		return nil
	end
	local count = 0
	for _ in pairs(batch) do
		count += 1
	end
	if count < 1 or count > MAX_BATCH_ENTRIES or count ~= #batch then
		return nil
	end
	for i = 1, count do
		local entry = batch[i]
		if type(entry) ~= "table" or not isSaneNumber(entry.others, MAX_OTHERS) then
			return nil
		end
		for _, field in SAMPLE_FIELDS do
			if not isSaneNumber(entry[field.name], field.max) then
				return nil
			end
		end
	end
	return batch
end

-- Copies only the known fields, so nothing else from the client is ever stored.
local function ingest(batch: { any })
	if #clientSamples + #batch > MAX_CLIENT_SAMPLES then
		return
	end
	for _, entry in batch do
		local sample: Sample = { others = math.floor(entry.others) }
		for _, field in SAMPLE_FIELDS do
			sample[field.name] = entry[field.name]
		end
		table.insert(clientSamples, sample)
	end
end

local function onProbeReport(player: Player, batch: any)
	local now = os.clock()
	local last = lastBatchAt[player]
	if last ~= nil and now - last < PLAYER_BATCH_GAP_SEC then
		return
	end
	lastBatchAt[player] = now
	local valid = validBatch(batch)
	if valid ~= nil then
		ingest(valid)
	end
end

local function sampleServer()
	table.insert(serverSamples, {
		t = os.time(),
		players = #Players:GetPlayers(),
		serverIC = (Stats :: any).InstanceCount or 0,
		serverMemMb = Stats:GetTotalMemoryUsageMb(),
	})
	if #serverSamples > MAX_SERVER_SAMPLES then
		table.remove(serverSamples, 1)
	end
end

-- Median and max of one field over a bucket, rounded to 0.1.
local function summarize(list: { Sample }, name: string): { number }
	local values: { number } = {}
	for i, sample in list do
		values[i] = sample[name]
	end
	table.sort(values)
	local n = #values
	local mid = math.floor((n + 1) / 2)
	local median = if n % 2 == 1 then values[mid] else (values[mid] + values[mid + 1]) / 2
	return { round1(median), round1(values[n]) }
end

-- One bucket per distinct `others` value: { others, n, <field> = { median, max } }.
local function bucketize(samples: { Sample }): { { [string]: any } }
	local groups: { [number]: { Sample } } = {}
	local keys: { number } = {}
	for _, sample in samples do
		local key = sample.others
		local list = groups[key]
		if list == nil then
			list = {}
			groups[key] = list
			table.insert(keys, key)
		end
		table.insert(list, sample)
	end
	table.sort(keys)
	local buckets: { { [string]: any } } = {}
	for _, key in keys do
		if #buckets >= MAX_BUCKETS then
			break
		end
		local list = groups[key]
		local bucket: { [string]: any } = { others = key, n = #list }
		for _, field in SAMPLE_FIELDS do
			bucket[field.name] = summarize(list, field.name)
		end
		table.insert(buckets, bucket)
	end
	return buckets
end

-- Encodes the body and trims it to MAX_BODY_BYTES: the largest `others` buckets go first, then the
-- oldest server samples. Returns nil only if the body still does not fit with nothing left to drop.
local function encodeCapped(payload: { [string]: any }): string?
	local function encode(): string?
		local ok, body = pcall(function()
			return HttpService:JSONEncode({ kind = "instances", kit_version = kitVersion(), payload = payload })
		end)
		return if ok then body else nil
	end
	local body = encode()
	while body ~= nil and #body > MAX_BODY_BYTES do
		payload.truncated = true
		if #payload.clients > 0 then
			table.remove(payload.clients)
		elseif #payload.server > 0 then
			table.remove(payload.server, 1)
		else
			return nil
		end
		body = encode()
	end
	return body
end

local function send(payload: { [string]: any })
	local body = encodeCapped(payload)
	if body == nil then
		return
	end
	local path = telemetryConfig().PATH or "/v3/telemetry"
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
		-- Best effort, as in BudgetTelemetry: the next flush carries on; nothing is retried or kept.
		BudgetMeter.recordEvent("telemetry_send_failed")
	end
end

local function flush()
	if not enabled() then
		serverSamples = {}
		clientSamples = {}
		return
	end
	if #serverSamples == 0 and #clientSamples == 0 then
		return
	end
	local sampleSec, batchSec, flushSec = intervals()
	local payload: { [string]: any } = {
		server = serverSamples,
		clients = bucketize(clientSamples),
		clientSampleCount = #clientSamples,
		interval = { sampleSec = sampleSec, clientBatchSec = batchSec, flushSec = flushSec },
	}
	serverSamples = {}
	clientSamples = {}
	task.spawn(send, payload)
end

--- Starts the probe. `remote` is the InstanceProbeReport RemoteEvent that Main.server creates.
function InstanceTelemetry.start(remote: RemoteEvent)
	if not enabled() then
		return
	end
	local sampleSec, _, flushSec = intervals()
	remote.OnServerEvent:Connect(onProbeReport)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastBatchAt[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(sampleSec)
			sampleServer()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(flushSec)
			flush()
		end
	end)
end

return InstanceTelemetry
