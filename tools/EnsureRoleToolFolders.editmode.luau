--!nocheck
-- Wrapper lama → pakai module repo (Command Bar: generate_tools_folder)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function resolveModule(): ModuleScript?
	local kit = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKit")
	local shared = kit and kit:FindFirstChild("Shared")
	local studio = shared and shared:FindFirstChild("Studio")
	return studio and studio:FindFirstChild("GenerateRoleToolsFolder") :: ModuleScript?
end

local moduleScript = resolveModule()
if not moduleScript then
	warn("[EnsureRoleToolFolders] Sync Rojo — module GenerateRoleToolsFolder belum ada.")
	return
end

require(moduleScript).run()
