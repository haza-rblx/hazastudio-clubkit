--!strict
-- Studio Command Bar (while Play): paste & run, or run as Edit-mode plugin script.
-- Prints instance counts by ClassName + top services + local Animator animation children.

local function countDescendants(root: Instance): { [string]: number }
	local counts: { [string]: number } = {}
	local total = 0
	for _, inst in ipairs(root:GetDescendants()) do
		local cn = inst.ClassName
		counts[cn] = (counts[cn] or 0) + 1
		total += 1
	end
	return counts, total
end

local function printTop(counts: { [string]: number }, label: string, total: number)
	local rows = {}
	for cn, n in pairs(counts) do
		table.insert(rows, { cn = cn, n = n })
	end
	table.sort(rows, function(a, b)
		return a.n > b.n
	end)
	print(("========== %s (total descendants: %d) =========="):format(label, total))
	for i = 1, math.min(25, #rows) do
		local row = rows[i]
		local pct = if total > 0 then (row.n / total * 100) else 0
		print(string.format("  %6d  (%5.1f%%)  %s", row.n, pct, row.cn))
	end
end

local services = {
	{ "game", game },
	{ "Workspace", workspace },
	{ "ReplicatedStorage", game:GetService("ReplicatedStorage") },
	{ "ReplicatedFirst", game:GetService("ReplicatedFirst") },
	{ "StarterGui", game:GetService("StarterGui") },
}

for _, entry in ipairs(services) do
	local name, root = entry[1], entry[2]
	local counts, total = countDescendants(root)
	printTop(counts, name, total)
end

local players = game:GetService("Players")
local localPlayer = players.LocalPlayer
if localPlayer and localPlayer.Character then
	local char = localPlayer.Character
	local counts, total = countDescendants(char)
	printTop(counts, "LocalCharacter", total)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if animator then
		local animChildren = 0
		for _, c in ipairs(animator:GetChildren()) do
			if c:IsA("Animation") then
				animChildren += 1
			end
		end
		print(
			("Local Animator: %d children (%d Animation instances)"):format(
				#animator:GetChildren(),
				animChildren
			)
		)
	end
end

print("Done. Compare before/after opening dance panel or enabling warmup.")
