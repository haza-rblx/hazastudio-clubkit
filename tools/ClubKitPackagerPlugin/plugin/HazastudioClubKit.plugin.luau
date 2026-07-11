--!nocheck
-- Hazastudio Club Kit Packager — export / import RBXM + Git source sync.
-- Install: copy folder ini ke %LOCALAPPDATA%\Roblox\Plugins\
-- atau build rbxm dari Studio lalu drag ke folder Plugins.

local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")

local Manifest = require(script.Parent.ClubKitManifest)
local PackagerCore = require(script.Parent.PackagerCore)
local PackagerPanel = require(script.Parent.PackagerPanel)
local UpdaterPanel = require(script.Parent.UpdaterPanel)

local toolbar = plugin:CreateToolbar("Hazastudio Club Kit")
local exportButton = toolbar:CreateButton(
	"Export RBXM",
	"Kumpulkan semua aset Club Kit lalu simpan sebagai .rbxm",
	"rbxassetid://6035193736"
)
local importButton = toolbar:CreateButton(
	"Unpack RBXM",
	"Import file .rbxm Club Kit lalu unpack ke service yang benar",
	"rbxassetid://6035193736"
)
local unpackSelButton = toolbar:CreateButton(
	"Unpack Pilihan",
	"Unpack package yang sedang dipilih di Explorer",
	"rbxassetid://6035193736"
)
local checkUpdateButton = toolbar:CreateButton(
	"Check Update",
	"Cek versi engine terbaru dari GitHub tag",
	"rbxassetid://6035193736"
)
local updateEngineButton = toolbar:CreateButton(
	"Update Engine",
	"Download .luau engine dari tag terbaru dan tulis Source",
	"rbxassetid://6035193736"
)

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	true,
	false,
	380,
	580,
	340,
	440
)
local widget = plugin:CreateDockWidgetPluginGui("HazastudioClubKitPackagerOpts", widgetInfo)
widget.Title = "Hazastudio Club Kit"

local function openPanel()
	widget.Enabled = true
end

local DovetailUI = require(script.Parent.DovetailUI)
local _, content = DovetailUI.scrollRoot(widget)

DovetailUI.brandHeader(content, Manifest.KIT_VERSION, 0)

local updaterApi = UpdaterPanel.create(content)
local packagerApi = PackagerPanel.create(content)

local busy = false

local function runExport()
	if busy then
		return
	end
	busy = true

	local ok, err = pcall(function()
		local packageRoot, report = PackagerCore.collect(packagerApi.getExportOptions())
		PackagerCore.printCollectReport(report)

		if not packageRoot then
			warn("[ClubKitPackager] Export gagal — tidak ada package.")
			return
		end

		Selection:Set({ packageRoot })
		plugin:PromptSaveSelection(("HazastudioClubKit_v%s.rbxm"):format(Manifest.KIT_VERSION))

		print(("[ClubKitPackager] Package siap disimpan: ServerStorage > %s"):format(Manifest.PACKAGE_NAME))
	end)

	if not ok then
		warn("[ClubKitPackager] Export error: " .. tostring(err))
	end

	busy = false
end

local function runUnpackFromPackage(packageRoot: Instance)
	local ok, err = pcall(function()
		local report = PackagerCore.unpack(packageRoot, packagerApi.getUnpackOptions())
		PackagerCore.printUnpackReport(report)
		print("[ClubKitPackager] Unpack selesai. Cek Explorer + Output untuk item yang missing.")
	end)
	if not ok then
		warn("[ClubKitPackager] Unpack error: " .. tostring(err))
	end
end

local function runImportUnpack()
	if busy then
		return
	end
	busy = true

	local ok, err = pcall(function()
		local imported = plugin:PromptImportFile("rbxm")
		if not imported or #imported == 0 then
			print("[ClubKitPackager] Import dibatalkan.")
			return
		end

		local packageRoot = PackagerCore.findPackageRoot(imported)
		if not packageRoot then
			warn("[ClubKitPackager] File bukan package Club Kit yang valid.")
			return
		end

		packageRoot.Parent = ServerStorage
		runUnpackFromPackage(packageRoot)
		packageRoot:Destroy()
	end)

	if not ok then
		warn("[ClubKitPackager] Import error: " .. tostring(err))
	end

	busy = false
end

local function runUnpackSelection()
	if busy then
		return
	end
	busy = true

	local ok, err = pcall(function()
		local selected = Selection:Get()
		if #selected == 0 then
			warn("[ClubKitPackager] Pilih folder " .. Manifest.PACKAGE_NAME .. " di Explorer.")
			return
		end

		local packageRoot = PackagerCore.findPackageRoot(selected)
		if not packageRoot then
			warn("[ClubKitPackager] Selection bukan package Club Kit.")
			return
		end

		runUnpackFromPackage(packageRoot)
	end)

	if not ok then
		warn("[ClubKitPackager] Unpack selection error: " .. tostring(err))
	end

	busy = false
end

exportButton.Click:Connect(function()
	openPanel()
	runExport()
end)
importButton.Click:Connect(function()
	openPanel()
	runImportUnpack()
end)
unpackSelButton.Click:Connect(function()
	openPanel()
	runUnpackSelection()
end)
checkUpdateButton.Click:Connect(function()
	openPanel()
	updaterApi.checkForUpdates()
end)
updateEngineButton.Click:Connect(function()
	openPanel()
	updaterApi.runUpdate()
end)

local genToolsButton = toolbar:CreateButton(
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
print("[ClubKitPackager] Panel: View > Hazastudio Club Kit, or click any toolbar button")
print("[ClubKitPackager] Command Bar: generate_tools_folder()")
