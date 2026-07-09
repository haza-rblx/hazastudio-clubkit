--!strict
-- Paste into a Script under ServerScriptService, Play once, read Server Output.
-- Or run via Command Bar on SERVER: game:GetService("Stats").InstanceCount

local Stats = game:GetService("Stats")

local function countDescendants(root: Instance): number
	local n = 0
	for _ in root:GetDescendants() do
		n += 1
	end
	return n
end

local gameTotal = countDescendants(game)
print("========== INSTANCE AUDIT (Server) ==========")
print("Stats.InstanceCount", Stats.InstanceCount)
print("game:GetDescendants()", gameTotal)
print("Gap", Stats.InstanceCount - gameTotal)
print("Workspace", countDescendants(workspace))
print("ReplicatedStorage", countDescendants(game:GetService("ReplicatedStorage")))
print("========== DONE ==========")
