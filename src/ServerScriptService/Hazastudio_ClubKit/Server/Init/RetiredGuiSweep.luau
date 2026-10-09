--!strict
-- Server/Init/RetiredGuiSweep.luau
-- Destroys GUIs the kit has retired from the StarterGui templates, once, at server boot (before any
-- player spawns), so an old buyer place never copies them into PlayerGui. The buyer's place file is
-- not edited; this is runtime-only. Names live in Config: RETIRED_GUI_NAMES (StarterGui screens) and
-- Hotbar.RETIRED_CHILD_NAMES (children inside the hotbar screen templates).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local RetiredGuiSweep = {}

-- Returns how many instances were destroyed.
function RetiredGuiSweep.run(): number
	local removed = 0
	for _, name in ipairs(Config.RETIRED_GUI_NAMES) do
		local gui = StarterGui:FindFirstChild(name)
		if gui ~= nil then
			gui:Destroy()
			removed += 1
		end
	end
	for _, hotbarName in ipairs(Config.Hotbar.GUI_NAMES) do
		local hotbar = StarterGui:FindFirstChild(hotbarName)
		if hotbar ~= nil then
			for _, childName in ipairs(Config.Hotbar.RETIRED_CHILD_NAMES) do
				for _, descendant in ipairs(hotbar:GetDescendants()) do
					if descendant.Name == childName then
						descendant:Destroy()
						removed += 1
					end
				end
			end
		end
	end
	return removed
end

return RetiredGuiSweep
