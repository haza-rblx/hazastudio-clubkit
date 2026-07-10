--!nocheck
-- Shared helper — dipanggil dari module + plugin Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StudioToolsCommand = {}

function StudioToolsCommand.resolveModule(): ModuleScript?
	local kit = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKit")
	if kit then
		local shared = kit:FindFirstChild("Shared")
		local studio = shared and shared:FindFirstChild("Studio")
		local mod = studio and studio:FindFirstChild("GenerateRoleToolsFolder")
		if mod and mod:IsA("ModuleScript") then
			return mod
		end
	end

	local legacyShared = ReplicatedStorage:FindFirstChild("Shared")
	local legacyStudio = legacyShared and legacyShared:FindFirstChild("Studio")
	local legacyMod = legacyStudio and legacyStudio:FindFirstChild("GenerateRoleToolsFolder")
	if legacyMod and legacyMod:IsA("ModuleScript") then
		return legacyMod
	end

	return nil
end

function StudioToolsCommand.runGenerateToolsFolder()
	local mod = StudioToolsCommand.resolveModule()
	if not mod then
		warn(
			"[generate_tools_folder] Module tidak ditemukan. Sync Rojo → ReplicatedStorage.Hazastudio_ClubKit.Shared.Studio.GenerateRoleToolsFolder"
		)
		return nil
	end

	local ok, result = pcall(function()
		return require(mod).run()
	end)
	if not ok then
		warn("[generate_tools_folder] Error: " .. tostring(result))
		return nil
	end
	return result
end

function StudioToolsCommand.registerCommandBarGlobal()
	local fn = function()
		return StudioToolsCommand.runGenerateToolsFolder()
	end

	_G.generate_tools_folder = fn
	if typeof(shared) == "table" then
		shared.generate_tools_folder = fn
	end

	return fn
end

return StudioToolsCommand
