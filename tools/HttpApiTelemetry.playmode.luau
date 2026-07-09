--!nocheck
-- ============================================================
-- HttpApiTelemetry — Studio Command Bar helper
-- (quota-efficiency-pass-2026-06, Phase 0 telemetry)
-- ============================================================
-- Run via Roblox Studio Command Bar in SERVER context:
--   1. Open Command Bar (View > Command Bar)
--   2. Left dropdown: pilih "Server"
--   3. Paste the WHOLE script below > Enter
--   4. The script returns an HttpApiTelemetry table you can call later.
--
-- Or save this file in `tools/` and require it from a one-shot ServerScript.
--
-- Commands:
--   HttpApiTelemetry.Status()    -- current state
--   HttpApiTelemetry.Enable()    -- flip COUNTERS_ENABLED = true
--   HttpApiTelemetry.Disable()   -- flip COUNTERS_ENABLED = false
--   HttpApiTelemetry.Print()     -- dump snapshot table with COUNT + RATE/s
--   HttpApiTelemetry.Reset()     -- clear all counters
--   HttpApiTelemetry.RunFor(seconds: number) -- prints every N seconds until done
--
-- Typical Phase 0 telemetry flow:
--   HttpApiTelemetry.Enable()
--   HttpApiTelemetry.Reset()
--   -- ... run 30 CCU baseline 10 min ...
--   HttpApiTelemetry.Print()
--   HttpApiTelemetry.Disable()
-- ============================================================

local RunService = game:GetService("RunService")
if not RunService:IsServer() then
	warn("[HttpApiTelemetry] WRONG CONTEXT — pick 'Server' in the Command Bar dropdown (not Client/All)")
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local okConfig, Config = pcall(require, ReplicatedStorage.Shared.Constants.Config)
if not okConfig or not Config then
	warn("[HttpApiTelemetry] Failed to require Config: " .. tostring(okConfig == false and Config or "nil"))
	return
end

local okCounter, HttpApiCounter = pcall(require, ReplicatedStorage.Shared.Utils.HttpApiCounter)
if not okCounter or not HttpApiCounter then
	warn("[HttpApiTelemetry] Failed to require HttpApiCounter: " .. tostring(okCounter == false and HttpApiCounter or "nil"))
	return
end

-- Snapshot diff state for rate calculation
local lastSnapshot: { [string]: number }? = nil
local lastSnapshotAt: number = 0

local HttpApiTelemetry = {}

function HttpApiTelemetry.Status()
	print("========================================")
	print("  HTTP API TELEMETRY STATUS")
	print("  " .. os.date("%Y-%m-%d %H:%M:%S"))
	print("========================================")
	local enabled = Config.HttpApi and Config.HttpApi.COUNTERS_ENABLED or false
	print("  COUNTERS_ENABLED = " .. tostring(enabled))
	local snap = HttpApiCounter.snapshot()
	local totalBuckets = 0
	for _ in pairs(snap) do
		totalBuckets += 1
	end
	print("  active buckets   = " .. totalBuckets)
	print("========================================")
end

function HttpApiTelemetry.Enable()
	if not Config.HttpApi then
		Config.HttpApi = {}
	end
	Config.HttpApi.COUNTERS_ENABLED = true
	print("[HttpApiTelemetry] COUNTERS_ENABLED = true — counters now recording")
	HttpApiTelemetry.Status()
end

function HttpApiTelemetry.Disable()
	if not Config.HttpApi then
		Config.HttpApi = {}
	end
	Config.HttpApi.COUNTERS_ENABLED = false
	print("[HttpApiTelemetry] COUNTERS_ENABLED = false — counters paused")
end

function HttpApiTelemetry.Reset()
	HttpApiCounter.reset()
	lastSnapshot = nil
	lastSnapshotAt = 0
	print("[HttpApiTelemetry] All counters reset")
end

function HttpApiTelemetry.Print()
	local snap = HttpApiCounter.snapshot()
	local now = os.clock()
	print("========================================")
	print("  HTTP API COUNTER SNAPSHOT")
	print("  " .. os.date("%Y-%m-%d %H:%M:%S"))
	print("========================================")
	if not (Config.HttpApi and Config.HttpApi.COUNTERS_ENABLED) then
		print("  (COUNTERS_ENABLED = false — counters may be empty)")
	end
	-- Sort buckets by count desc
	local entries: { { bucket: string, count: number } } = {}
	for k, v in pairs(snap) do
		table.insert(entries, { bucket = k, count = v })
	end
	table.sort(entries, function(a, b)
		return a.count > b.count
	end)
	-- Compute rate vs last snapshot
	local rate: { [string]: number } = {}
	if lastSnapshot and lastSnapshotAt > 0 then
		local elapsed = now - lastSnapshotAt
		if elapsed > 0 then
			for _, e in ipairs(entries) do
				local prev = lastSnapshot[e.bucket] or 0
				rate[e.bucket] = (e.count - prev) / elapsed
			end
		end
	end
	-- Print table
	print(string.format("  %-32s  %10s  %12s", "BUCKET", "COUNT", "RATE/s"))
	print("  ----------------------------------------------------------")
	if #entries == 0 then
		print("  (no buckets recorded yet — wait for traffic)")
	else
		for _, e in ipairs(entries) do
			local r = rate[e.bucket]
			print(string.format("  %-32s  %10d  %12s", e.bucket, e.count, r and string.format("%.2f", r) or "-"))
		end
	end
	print("========================================")
	lastSnapshot = snap
	lastSnapshotAt = now
end

function HttpApiTelemetry.RunFor(seconds: number)
	print(string.format("[HttpApiTelemetry] Auto-Print every 60s for %ds. Call HttpApiTelemetry.Disable() to stop early.", seconds))
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		task.wait(60)
		HttpApiTelemetry.Print()
	end
	print("[HttpApiTelemetry] RunFor complete")
end

-- Initial status report
print("[HttpApiTelemetry] Module loaded. Available commands:")
print("  HttpApiTelemetry.Status()")
print("  HttpApiTelemetry.Enable()")
print("  HttpApiTelemetry.Disable()")
print("  HttpApiTelemetry.Print()")
print("  HttpApiTelemetry.Reset()")
print("  HttpApiTelemetry.RunFor(600)")
HttpApiTelemetry.Status()

return HttpApiTelemetry
