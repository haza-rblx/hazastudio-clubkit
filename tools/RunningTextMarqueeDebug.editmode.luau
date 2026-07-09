-- Paste in Studio Command Bar (Play mode) to dump RunningText layout + enable client debug logs.
-- Also set Config.Donation.RUNNING_TEXT_DEBUG = true in Config.luau for live marquee metrics.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("=== RunningText marquee debug ===")
print("Enable Config.Donation.RUNNING_TEXT_DEBUG = true then re-run Play for client warn logs.")

local function findRunningRoots(): { Instance }
	local roots = {}
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst.Name == "RunningText" and (inst:IsA("Model") or inst:IsA("Folder") or inst:IsA("BasePart")) then
			table.insert(roots, inst)
		end
	end
	return roots
end

local function dumpGuiTree(gui: Instance, indent: string)
	for _, child in ipairs(gui:GetChildren()) do
		local line = indent .. child.ClassName .. " " .. child.Name
		if child:IsA("GuiObject") then
			local g = child :: GuiObject
			line ..= string.format(
				" | Size=%s Pos=%s Visible=%s",
				tostring(g.Size),
				tostring(g.Position),
				tostring(g.Visible)
			)
			if child:IsA("TextLabel") then
				line ..= ' Text="' .. (child :: TextLabel).Text:sub(1, 40) .. '"'
			end
		end
		if child:IsA("UIListLayout") then
			local layout = child :: UIListLayout
			line ..= string.format(
				" | ListLayout Fill=%s Pad=%s Parent=%s",
				tostring(layout.FillDirection),
				tostring(layout.Padding),
				layout.Parent and layout.Parent.Name or "nil"
			)
		end
		print(line)
		if indent:len() < 12 then
			dumpGuiTree(child, indent .. "  ")
		end
	end
end

local roots = findRunningRoots()
print("RunningText roots:", #roots)
for _, root in ipairs(roots) do
	print("\n-- Root:", root:GetFullName())
	local gui = root:FindFirstChild("RunningTextGUI", true) or root:FindFirstChild("SurfaceGui", true)
	if not gui or not gui:IsA("SurfaceGui") then
		warn("  No SurfaceGui under this root")
		continue
	end
	print(string.format(
		"  SurfaceGui AbsoluteSize=%s CanvasSize=%s Adornee=%s",
		tostring((gui :: SurfaceGui).AbsoluteSize),
		tostring((gui :: SurfaceGui).CanvasSize),
		tostring((gui :: SurfaceGui).Adornee)
	))
	local wrapper = gui:FindFirstChild("Wrapper", true)
	if wrapper and wrapper:IsA("Frame") then
		print(string.format("  Wrapper AbsoluteSize=%s Clips=%s", tostring(wrapper.AbsoluteSize), tostring(wrapper.ClipsDescendants)))
		local wrapperLayouts = 0
		for _, child in ipairs(wrapper:GetChildren()) do
			if child:IsA("UIListLayout") or child:IsA("UITableLayout") then
				wrapperLayouts += 1
				print("  Wrapper direct layout:", child.ClassName, child.Name)
			end
		end
		if wrapperLayouts == 0 then
			print("  Wrapper has NO direct UIListLayout (marquee moves ContentWrapper frames; internal layout is inside each strip)")
		end
	end
	dumpGuiTree(gui, "  ")
end

local ok, cfg = pcall(function()
	return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"):WaitForChild("Config"))
end)
if ok and cfg and cfg.Donation then
	print("Config.Donation.RUNNING_TEXT_DEBUG =", cfg.Donation.RUNNING_TEXT_DEBUG)
end

print("=== end ===")
