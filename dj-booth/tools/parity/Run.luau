--!nocheck
-- Drives the panel through the Studio test hook, then compares it with a golden.
-- run("library_all", { { "tab", "Tracks" } }, ignoreRegions, maxList)
local T = script.Parent
local Parity = require(T.Parity)

return function(goldenName, steps, ignore, maxList)
	local g = game.Players.LocalPlayer.PlayerGui:WaitForChild("HazaDJ", 10)
	if not g then
		return "no HazaDJ gui"
	end
	local hook = g:WaitForChild("HazaDJ_Test", 10)
	for _, s in steps or {} do
		hook:Invoke(table.unpack(s))
		task.wait(0.15)
	end
	-- labels built before the font finished loading keep their fallback width until something
	-- re-lays them out (a minimised Studio never renders): nudge every one to re-measure
	for _, d in g:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
			local size = d.TextSize
			d.TextSize = size + 1
			d.TextSize = size
		end
	end
	task.wait(0.5)
	local panel = g.Panel
	panel:FindFirstChildOfClass("UIScale").Scale = 1
	task.wait(0.2)
	local golden = require(T.Golden["golden_" .. goldenName])
	local items = Parity.dump(g, panel, 1250)
	local report = Parity.compare(golden.items, items, ignore, 1, maxList or 15)
	return goldenName .. ": " .. report
end
