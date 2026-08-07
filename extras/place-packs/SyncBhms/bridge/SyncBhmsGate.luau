--!strict
-- Place-pack gate: BHMS scripts must no-op unless ClubKitConfig.Features.LegacySyncBhms == true.
-- Parent: ReplicatedStorage.SyncBhmsGate (ModuleScript)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SyncBhmsGate = {}

function SyncBhmsGate.isEnabled(): boolean
	local folder = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKitConfig")
	local mod = folder and folder:FindFirstChild("ClubKitConfig")
	if not (mod and mod:IsA("ModuleScript")) then
		return false
	end
	local ok, cfg = pcall(require, mod)
	if not ok or type(cfg) ~= "table" then
		return false
	end
	local features = (cfg :: any).Features
	return type(features) == "table" and features.LegacySyncBhms == true
end

return SyncBhmsGate
