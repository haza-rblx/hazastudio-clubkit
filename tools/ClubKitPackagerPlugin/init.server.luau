--!nocheck
-- Hazastudio Club Kit Packager — export / import RBXM satu klik.
-- Install: copy folder ini ke %LOCALAPPDATA%\Roblox\Plugins\
-- atau build rbxm dari Studio lalu drag ke folder Plugins.

local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")

local Manifest = require(script.Parent.ClubKitManifest)
local PackagerCore = require(script.Parent.PackagerCore)

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

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	false,
	false,
	320,
	280,
	280,
	220
)
local widget = plugin:CreateDockWidgetPluginGui("HazastudioClubKitPackagerOpts", widgetInfo)
widget.Title = "Club Kit Packager"

local function makeCheckbox(parent: Instance, label: string, default: boolean, layoutOrder: number): BoolValue
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 24)
	row.LayoutOrder = layoutOrder
	row.Parent = parent

	local check = Instance.new("TextButton")
	check.Size = UDim2.new(0, 22, 0, 22)
	check.Position = UDim2.new(0, 0, 0, 1)
	check.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	check.Text = default and "✓" or ""
	check.TextColor3 = Color3.new(1, 1, 1)
	check.Font = Enum.Font.GothamBold
	check.TextSize = 14
	check.Parent = row

	local flag = Instance.new("BoolValue")
	flag.Name = "Flag"
	flag.Value = default
	flag.Parent = check

	check.MouseButton1Click:Connect(function()
		flag.Value = not flag.Value
		check.Text = flag.Value and "✓" or ""
	end)

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Position = UDim2.new(0, 30, 0, 0)
	text.Size = UDim2.new(1, -30, 1, 0)
	text.Font = Enum.Font.Gotham
	text.TextSize = 13
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextColor3 = Color3.fromRGB(230, 230, 230)
	text.Text = label
	text.Parent = row

	return flag
end

local root = Instance.new("Frame")
root.Size = UDim2.new(1, 0, 1, 0)
root.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
root.BorderSizePixel = 0
root.Parent = widget

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.Parent = root

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = root

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, 0, 0, 22)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.new(1, 1, 1)
title.Text = "Opsi Export / Unpack"
title.LayoutOrder = 0
title.Parent = root

local includeConfig = makeCheckbox(root, "Sertakan Hazastudio_ClubKitConfig", true, 1)
local includeSecrets = makeCheckbox(root, "Sertakan template Secrets", true, 2)
local replaceExisting = makeCheckbox(root, "Ganti instance yang sudah ada", true, 3)
local keepBuyerConfig = makeCheckbox(root, "Jangan timpa ClubKitConfig buyer", true, 4)
local keepBuyerSecrets = makeCheckbox(root, "Jangan timpa Secrets buyer", true, 5)

local hint = Instance.new("TextLabel")
hint.BackgroundTransparency = 1
hint.Size = UDim2.new(1, 0, 0, 72)
hint.Font = Enum.Font.Gotham
hint.TextSize = 12
hint.TextWrapped = true
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.TextYAlignment = Enum.TextYAlignment.Top
hint.TextColor3 = Color3.fromRGB(170, 170, 170)
hint.Text = "Export: klik Export RBXM → pilih lokasi simpan.\nUnpack: klik Unpack RBXM → pilih file .rbxm.\nTarget place cukup unpack — tidak perlu Rojo."
hint.LayoutOrder = 10
hint.Parent = root

local function getExportOptions()
	return {
		includeConfig = includeConfig.Value,
		includeSecrets = includeSecrets.Value,
	}
end

local function getUnpackOptions()
	return {
		replaceExisting = replaceExisting.Value,
		keepBuyerConfig = keepBuyerConfig.Value,
		keepBuyerSecrets = keepBuyerSecrets.Value,
	}
end

local busy = false

local function runExport()
	if busy then
		return
	end
	busy = true

	local ok, err = pcall(function()
		local packageRoot, report = PackagerCore.collect(getExportOptions())
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
		local report = PackagerCore.unpack(packageRoot, getUnpackOptions())
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

		-- Parent sementara supaya clone aman selama unpack.
		packageRoot.Parent = ServerStorage
		runUnpackFromPackage(packageRoot)

		-- Bersihkan staging import (aset sudah di tempatkan).
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

exportButton.Click:Connect(runExport)
importButton.Click:Connect(runImportUnpack)
unpackSelButton.Click:Connect(runUnpackSelection)

print("[ClubKitPackager] Loaded v" .. Manifest.KIT_VERSION .. " — toolbar: Hazastudio Club Kit")
