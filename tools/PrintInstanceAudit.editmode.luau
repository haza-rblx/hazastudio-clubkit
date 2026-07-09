--!strict
-- Run in Studio Command Bar while Play (Client).
-- Compares Stats.InstanceCount (overlay "Instances") vs Lua descendant counts.

local Stats = game:GetService("Stats")
local Players = game:GetService("Players")

local function countDescendants(root: Instance): number
	local n = 0
	for _ in root:GetDescendants() do
		n += 1
	end
	return n
end

local function safeCount(label: string, root: Instance?): number
	if not root then
		print(label, "n/a")
		return 0
	end
	local n = countDescendants(root)
	print(label, n)
	return n
end

print("========== INSTANCE AUDIT (Client) ==========")

-- Same number as Stats overlay "Instances" (World section).
local instanceCount = Stats.InstanceCount
print("Stats.InstanceCount (overlay)", instanceCount)

local gameTotal = safeCount("game:GetDescendants()", game)
safeCount("CoreGui", game:GetService("CoreGui"))

local lp = Players.LocalPlayer
local playerGui = lp and lp:FindFirstChildOfClass("PlayerGui")
local playerGuiTotal = safeCount("PlayerGui", playerGui)

safeCount("Workspace", workspace)
safeCount("ReplicatedStorage", game:GetService("ReplicatedStorage"))

-- Studio-only (may be 0 in live game).
local okPlugin, pluginGui = pcall(function()
	return game:GetService("PluginGuiService")
end)
if okPlugin and pluginGui then
	pcall(function()
		safeCount("PluginGuiService", pluginGui :: any)
	end)
end

-- PerformanceStats breakdown (what feeds the World panel).
local perf = Stats:FindFirstChild("PerformanceStats")
if perf then
	print("--- PerformanceStats.World ---")
	local world = perf:FindFirstChild("World")
	if world then
		for _, item in world:GetChildren() do
			if item:IsA("StatsItem") then
				local ok, value = pcall(function()
					return (item :: StatsItem):GetValue()
				end)
				if ok then
					print(("  %s = %s"):format(item.Name, tostring(value)))
				end
			end
		end
	end
end

local animatorAnim = 0
if lp and lp.Character then
	local hum = lp.Character:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if animator then
		for _, c in animator:GetChildren() do
			if c:IsA("Animation") then
				animatorAnim += 1
			end
		end
	end
end
print("Animator Animation children", animatorAnim)

-- PlayerGui is already included in gameTotal (under Players).
local gap = instanceCount - gameTotal
print("---")
print("Gap (InstanceCount - game descendants)", gap)
print("If Gap is huge: likely orphaned instances (Parent=nil still referenced),")
print("or Studio/server scope — run SERVER audit below in Server context.")

print("========== DONE ==========")
