--!strict
-- PATH: tools/InspectBillboardStructure.editmode.luau
-- Quick helper: prints the path of every TextLabel inside each VFX model
-- under ReplicatedStorage.WorldEffects so you can see what's actually there.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:FindFirstChild("WorldEffects")
if not folder then
	warn("WorldEffects folder not found")
	return
end

for _, model in ipairs(folder:GetChildren()) do
	print("\n========================================")
	print("Model: " .. model:GetFullName() .. " (" .. model.ClassName .. ")")
	print("========================================")

	-- All BillboardGuis at any depth
	local bbs = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BillboardGui") then
			table.insert(bbs, d)
		end
	end
	print("BillboardGuis found: " .. #bbs)

	-- All TextLabels with their full path
	local labels = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("TextLabel") then
			table.insert(labels, d)
		end
	end
	print("TextLabels found: " .. #labels)
	for _, l in ipairs(labels) do
		print("  - " .. l:GetFullName())
		print("      Text: " .. tostring(l.Text))
	end

	-- Print immediate children of the model (so we can see if BillboardGui is
	-- at root or wrapped in something)
	print("Immediate children:")
	for _, child in ipairs(model:GetChildren()) do
		print("  - " .. child.Name .. " (" .. child.ClassName .. ")")
	end
end
