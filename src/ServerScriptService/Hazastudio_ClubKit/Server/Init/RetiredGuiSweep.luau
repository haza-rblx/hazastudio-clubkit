--!strict
-- Server/Init/RetiredGuiSweep.luau
-- Destroys GUIs the kit has retired from the StarterGui templates, once, at server boot, so an old
-- buyer place never copies them into PlayerGui. A player who spawned before this ran (Studio Play
-- Solo, an early joiner while the server modules load) already holds copies, so their PlayerGui is
-- swept too. Nothing yields, so no spawn can slip between the two passes. The buyer's place file is
-- not edited; this is runtime-only. Names live in Config: RETIRED_GUI_NAMES (StarterGui screens) and
-- Hotbar.RETIRED_CHILD_NAMES (children inside the hotbar screen templates).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local RetiredGuiSweep = {}

-- Destroys retired screens and retired hotbar children under one container (StarterGui or a
-- PlayerGui). Returns how many instances were destroyed.
local function sweep(container: Instance): number
	local removed = 0
	for _, name in ipairs(Config.RETIRED_GUI_NAMES) do
		local gui = container:FindFirstChild(name)
		if gui ~= nil then
			gui:Destroy()
			removed += 1
		end
	end
	for _, hotbarName in ipairs(Config.Hotbar.GUI_NAMES) do
		local hotbar = container:FindFirstChild(hotbarName)
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

-- Returns how many instances were destroyed.
function RetiredGuiSweep.run(): number
	local removed = sweep(StarterGui)
	for _, player in ipairs(Players:GetPlayers()) do
		local playerGui = player:FindFirstChildOfClass("PlayerGui")
		if playerGui ~= nil then
			removed += sweep(playerGui)
		end
	end
	return removed
end

return RetiredGuiSweep
