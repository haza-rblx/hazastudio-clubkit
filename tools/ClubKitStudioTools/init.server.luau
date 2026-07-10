--!nocheck
-- ClubKit Studio Tools — plugin kecil untuk Command Bar.
-- Install: copy folder ini ke %LOCALAPPDATA%\Roblox\Plugins\ClubKitStudioTools\
-- Restart Studio → Command Bar: generate_tools_folder()

local toolbar = plugin:CreateToolbar("Hazastudio Club Kit")
local genButton = toolbar:CreateButton(
	"Gen Tools",
	"generate_tools_folder() — buat folder kosong ServerStorage.Tools dari role config",
	"rbxassetid://6035193736"
)

local function runGenerateToolsFolder()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local kit = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKit")
	local mod = kit
		and kit:FindFirstChild("Shared")
		and kit.Shared:FindFirstChild("Studio")
		and kit.Shared.Studio:FindFirstChild("GenerateRoleToolsFolder")

	if not mod or not mod:IsA("ModuleScript") then
		warn("[generate_tools_folder] Sync Rojo dulu — module belum ada di place.")
		return
	end

	local ok, err = pcall(function()
		require(mod).run()
	end)
	if not ok then
		warn("[generate_tools_folder] " .. tostring(err))
	end
end

local function registerGlobal()
	_G.generate_tools_folder = runGenerateToolsFolder
	if typeof(shared) == "table" then
		shared.generate_tools_folder = runGenerateToolsFolder
	end
end

registerGlobal()
genButton.Click:Connect(runGenerateToolsFolder)

print("[ClubKit Studio Tools] generate_tools_folder() siap di Command Bar.")
