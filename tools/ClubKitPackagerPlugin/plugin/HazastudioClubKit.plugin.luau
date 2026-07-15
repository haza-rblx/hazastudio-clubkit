--!nocheck
-- Hazastudio Club Kit Packager — Update Engine dock + Gen Tools.
-- Install: .\tools\ClubKitPackagerPlugin\build-plugin-rbxm.ps1

-- Nested .rbxm: modules are children of this Script (Parent = Plugin container).
-- Folder plugin-build: modules are siblings under the Folder (Parent = Folder).
local function requirePluginModule(name: string)
	local mod = script:FindFirstChild(name) or (script.Parent and script.Parent:FindFirstChild(name))
	if not mod then
		error(("[ClubKitPackager] Missing module %s (child of Script or sibling Folder)"):format(name))
	end
	return require(mod)
end

local Manifest = requirePluginModule("ClubKitManifest")
local UpdaterPanel = requirePluginModule("UpdaterPanel")

local toolbar = plugin:CreateToolbar("Hazastudio Club Kit")
local openPanelButton = toolbar:CreateButton(
	"Open Panel",
	"Buka panel Update Engine + auto check update",
	"rbxassetid://99832044843928"
)
local genToolsButton = toolbar:CreateButton(
	"Gen Tools",
	"generate_tools_folder() — buat folder kosong ServerStorage.Tools dari role config",
	"rbxassetid://96030964846916"
)

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	false,
	false,
	380,
	580,
	340,
	440
)
local widget = plugin:CreateDockWidgetPluginGui("HazastudioClubKitPackagerOpts", widgetInfo)
widget.Title = "Hazastudio Club Kit"
widget.Name = "HazastudioClubKitPackagerOpts"

local function openPanel()
	widget.Enabled = true
end

local updaterApi = UpdaterPanel.create(widget, {
	onDismiss = function()
		widget.Enabled = false
	end,
})

openPanelButton.Click:Connect(function()
	openPanel()
	task.defer(function()
		updaterApi.checkForUpdates()
	end)
end)

local function runGenerateToolsFolder()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local kit = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKit")
	local mod = kit
		and kit:FindFirstChild("Shared")
		and kit.Shared:FindFirstChild("Studio")
		and kit.Shared.Studio:FindFirstChild("GenerateRoleToolsFolder")
	if not mod or not mod:IsA("ModuleScript") then
		warn("[generate_tools_folder] Sync Rojo — module GenerateRoleToolsFolder belum ada.")
		return
	end
	local ok, err = pcall(function()
		require(mod).run()
	end)
	if not ok then
		warn("[generate_tools_folder] " .. tostring(err))
	end
end

_G.generate_tools_folder = runGenerateToolsFolder
if typeof(shared) == "table" then
	shared.generate_tools_folder = runGenerateToolsFolder
end
genToolsButton.Click:Connect(runGenerateToolsFolder)

print("[ClubKitPackager] Loaded v" .. Manifest.KIT_VERSION .. " - Hazastudio Club Kit")
print("[ClubKitPackager] Toolbar: Open Panel · Gen Tools")
print("[ClubKitPackager] Command Bar: generate_tools_folder()")
