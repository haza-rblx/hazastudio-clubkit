--!strict
-- Roblox replicates StarterGui to every client, so each kit GUI exists twice on the client: the
-- template here and the live copy in PlayerGui (~4,200 instances in Experiment Area, 2026-10-07).
-- Main.client hardens every template to ResetOnSpawn = false, so after boot nothing clones them
-- again. Once gameplay has started this empties the template of every GUI that already has its
-- PlayerGui copy. Measured: -4,218 instances; respawn left every PlayerGui GUI intact, 0 warnings.
--
-- What stays:
-- - each ScreenGui shell, because ForeignGuiGuardService asks StarterGui:FindFirstChild(name);
-- - templates that are cloned on demand (Sticker, PaidBroadcast) plus Config.ClientFootprint.STARTER_GUI_KEEP;
-- - any template whose PlayerGui copy is missing, because the ensure*/fallback paths clone it.
-- Every fallback in the kit (TopMenuGuiRefs, StickerController, PaidBroadcastController,
-- Main.client ensurePlayerGuiChild) checks PlayerGui first, so it never reaches an emptied template.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local StarterGuiTrimService = {}

local function keepNames(): { [string]: boolean }
	local keep: { [string]: boolean } = {}
	for _, name in ipairs(Config.ClientFootprint.STARTER_GUI_KEEP) do
		keep[name] = true
	end
	local sticker = Config.Sticker and Config.Sticker.GUI_NAME
	local broadcast = Config.PaidBroadcast and Config.PaidBroadcast.GUI_NAME
	if type(sticker) == "string" then
		keep[sticker] = true
	end
	if type(broadcast) == "string" then
		keep[broadcast] = true
	end
	return keep
end

-- Returns how many instances were removed.
function StarterGuiTrimService.run(): number
	if Config.ClientFootprint.TRIM_STARTER_GUI ~= true then
		return 0
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return 0
	end
	local keep = keepNames()
	local removed = 0
	for _, template in ipairs(StarterGui:GetChildren()) do
		if template:IsA("LayerCollector") and not keep[template.Name] then
			local live = playerGui:FindFirstChild(template.Name)
			if live and live.ClassName == template.ClassName then
				for _, child in ipairs(template:GetChildren()) do
					removed += #child:GetDescendants() + 1
					child:Destroy()
				end
			end
		end
	end
	return removed
end

return StarterGuiTrimService
