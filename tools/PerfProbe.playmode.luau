--!nocheck
-- PerfProbe (client, play mode). Paste into the client command bar during a playtest, or run it via
-- MCP eval_client_runtime. Samples for SAMPLE_SECONDS and returns a plain-text report:
--   • PlayerGui: instances per ScreenGui (enabled / disabled) and the total
--   • Workspace SurfaceGui/BillboardGui instance counts (world boards, overheads)
--   • Developer memory tags (MB)
--   • RemoteEvent traffic per remote (fires and approx. payload bytes) while sampling
--   • Frame time (avg / p95 Heartbeat dt) and per-frame connection hints
-- Read-only: it only listens and counts; nothing is changed.
local SAMPLE_SECONDS = 20
local TOP_N = 12

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local out = {}
local function line(s)
	table.insert(out, s)
end
local function pad(s, n)
	s = tostring(s)
	return if #s >= n then s else s .. string.rep(" ", n - #s)
end

-- ===== PlayerGui =====
local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
local guis, guiTotal = {}, 0
for _, g in pg:GetChildren() do
	local n = #g:GetDescendants() + 1
	guiTotal += n
	table.insert(guis, { name = g.Name, n = n, on = (not g:IsA("LayerCollector")) or g.Enabled })
end
table.sort(guis, function(a, b)
	return a.n > b.n
end)
line(("PlayerGui: %d instances in %d children"):format(guiTotal, #guis))
for i = 1, math.min(TOP_N, #guis) do
	local g = guis[i]
	line(("  %s %6d  %s"):format(pad(g.name, 34), g.n, if g.on then "enabled" else "disabled"))
end
local disabledTotal = 0
for _, g in guis do
	if not g.on then
		disabledTotal += g.n
	end
end
line(("  disabled ScreenGuis hold %d instances (%.0f%%)"):format(disabledTotal, 100 * disabledTotal / math.max(guiTotal, 1)))

-- ===== world GUIs =====
local surf, surfN, bill, billN = 0, 0, 0, 0
for _, d in workspace:GetDescendants() do
	if d:IsA("SurfaceGui") then
		surf += 1
		surfN += #d:GetDescendants() + 1
	elseif d:IsA("BillboardGui") then
		bill += 1
		billN += #d:GetDescendants() + 1
	end
end
line(("World: %d SurfaceGuis (%d instances), %d BillboardGuis (%d instances)"):format(surf, surfN, bill, billN))
line(("Client DataModel total: %d instances"):format(#game:GetDescendants()))

-- ===== memory =====
local tags = {
	"Instances",
	"Gui",
	"GraphicsTexture",
	"GraphicsMeshParts",
	"LuaHeap",
	"Script",
	"Animation",
	"Sounds",
	"PhysicsParts",
}
local mem = {}
for _, t in tags do
	local ok, v = pcall(function()
		return Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag[t])
	end)
	if ok then
		table.insert(mem, ("%s %.1f"):format(t, v))
	end
end
line("Memory MB: " .. table.concat(mem, " · ") .. (" · total %.0f"):format(Stats:GetTotalMemoryUsageMb()))

-- ===== remote traffic + frame time (sampled together) =====
local counts, bytes, conns = {}, {}, {}
for _, r in ReplicatedStorage:GetDescendants() do
	if r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent") then
		local key = r:GetFullName():gsub("^ReplicatedStorage%.", "")
		table.insert(conns, r.OnClientEvent:Connect(function(...)
			counts[key] = (counts[key] or 0) + 1
			local ok, s = pcall(HttpService.JSONEncode, HttpService, { ... })
			bytes[key] = (bytes[key] or 0) + (if ok then #s else 0)
		end))
	end
end
local dts = {}
table.insert(conns, RunService.Heartbeat:Connect(function(dt)
	table.insert(dts, dt)
end))
task.wait(SAMPLE_SECONDS)
for _, c in conns do
	c:Disconnect()
end

local rows, fires, total = {}, 0, 0
for k, n in counts do
	fires += n
	total += bytes[k] or 0
	table.insert(rows, { k = k, n = n, b = bytes[k] or 0 })
end
table.sort(rows, function(a, b)
	return a.b > b.b
end)
line(("Remotes (%ds): %d fires, ~%.1f KB JSON-equivalent, %d remotes active"):format(SAMPLE_SECONDS, fires, total / 1024, #rows))
for i = 1, math.min(TOP_N, #rows) do
	local r = rows[i]
	line(("  %s %5d fires  %7.1f KB"):format(pad(r.k, 52), r.n, r.b / 1024))
end

table.sort(dts)
local sum = 0
for _, d in dts do
	sum += d
end
local avg = sum / math.max(#dts, 1)
local p95 = dts[math.max(1, math.floor(#dts * 0.95))] or 0
line(("Frame: avg %.2f ms (%.0f fps) · p95 %.2f ms · %d samples"):format(avg * 1000, 1 / math.max(avg, 1e-6), p95 * 1000, #dts))

local report = table.concat(out, "\n")
print(report)
return report
