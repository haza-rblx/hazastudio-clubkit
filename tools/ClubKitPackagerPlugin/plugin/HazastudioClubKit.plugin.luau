--!nocheck
--[[
  Hazastudio Club Kit - Studio dock (Config / Diagnostics / Engine / Tools / Packager).
  Install: .\tools\ClubKitPackagerPlugin\build-plugin-rbxm.ps1

  Soft-update (buyers): Engine tab → Update Plugin fetches plugin/*.luau from GitHub
  tags and remounts via loadstring (this bootstrap file is NOT replaced).

  DEV HOT-RELOAD (iterate WITHOUT restarting Studio):
    1. Start:  .\tools\ClubKitPackagerPlugin\dev-serve.ps1  (http://127.0.0.1:8798)
    2. Edit plugin/*.luau and save.
    3. Click "Reload Panel" (or reload_clubkit_panel() in the command bar).

  Limits:
    - This bootstrap is NOT hot-reloaded. New ModuleScript names / bootstrap edits
      need build-plugin-rbxm.ps1 + one Studio restart.
]]

local DEV_BASE_URL = "http://127.0.0.1:8798"
local DEV_REQUIRE_PATTERN = "require%(%s*script%.Parent%.([%w_]+)%s*%)"
local DEV_REQUIRE_PRELUDE = "local __clubkitDevRequire = ...\n"

local HttpService = game:GetService("HttpService")

local function requirePluginModule(name: string)
	local mod = script:FindFirstChild(name) or (script.Parent and script.Parent:FindFirstChild(name))
	if not mod then
		error(("[ClubKitPackager] Missing module %s (child of Script or sibling Folder)"):format(name))
	end
	return require(mod)
end

local Manifest = requirePluginModule("ClubKitManifest")
local BundledPanel = requirePluginModule("ClubKitPanel")
local PluginSyncCore = requirePluginModule("PluginSyncCore")

local toolbar = plugin:CreateToolbar("Hazastudio Club Kit")
local openPanelButton = toolbar:CreateButton(
	"Open Panel",
	"Club Kit panel — Config, Diagnostics, Engine, Tools, Packager",
	"rbxassetid://99832044843928"
)
local reloadPanelButton = toolbar:CreateButton(
	"Reload Panel",
	"Rebuild the panel from dev-serve.ps1 sources (http://127.0.0.1:8798) - no Studio restart",
	"rbxassetid://99832044843928"
)
local genToolsButton = toolbar:CreateButton(
	"Gen Tools",
	"generate_tools_folder() — create empty ServerStorage.Tools folders from role config",
	"rbxassetid://96030964846916"
)

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	false,
	false,
	1020,
	700,
	720,
	520
)
local widget = plugin:CreateDockWidgetPluginGui("HazastudioClubKitPanel", widgetInfo)
widget.Title = "Hazastudio Club Kit"
widget.Name = "HazastudioClubKitPanel"

local function runGenerateToolsFolder()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local kit = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKit")
	local mod = kit
		and kit:FindFirstChild("Shared")
		and kit.Shared:FindFirstChild("Studio")
		and kit.Shared.Studio:FindFirstChild("GenerateRoleToolsFolder")
	if not mod or not mod:IsA("ModuleScript") then
		warn("[generate_tools_folder] Sync Rojo — GenerateRoleToolsFolder module not found yet.")
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

----------------------------------------------------------------
-- Panel mount / remount
----------------------------------------------------------------
local currentApi = nil
local softUpdateBusy = false

local panelOpts = {
	plugin = plugin,
	onDismiss = function()
		widget.Enabled = false
	end,
	onGenerateTools = runGenerateToolsFolder,
}

local function destroyPanelRoots()
	for _, child in widget:GetChildren() do
		if child.Name == "ClubKitRoot" then
			child:Destroy()
		end
	end
end

local function mountPanel(panelModule): boolean
	destroyPanelRoots()
	local ok, api = pcall(panelModule.create, widget, panelOpts)
	if not ok then
		warn("[ClubKitPackager] Panel mount failed: " .. tostring(api))
		return false
	end
	currentApi = api
	return true
end

----------------------------------------------------------------
-- Shared soft-load: sources table -> ClubKitPanel (dev + GitHub)
----------------------------------------------------------------
local function loadPanelFromSources(sources: { [string]: string })
	local cache = {}
	local loading = {}
	local loadModule
	loadModule = function(name: string)
		if cache[name] ~= nil then
			return cache[name]
		end
		if loading[name] then
			error("[ClubKitSoft] cyclic require of " .. name, 2)
		end
		local src = sources[name]
		if not src then
			error("[ClubKitSoft] module missing from soft sources: " .. name, 2)
		end
		local patched = DEV_REQUIRE_PRELUDE .. string.gsub(src, DEV_REQUIRE_PATTERN, '__clubkitDevRequire("%1")')
		local chunk, parseErr = loadstring(patched, "@ClubKitPlugin/" .. name .. ".luau")
		if not chunk then
			error("[ClubKitSoft] parse error in " .. name .. ": " .. tostring(parseErr), 2)
		end
		loading[name] = true
		local ok, result = pcall(chunk, loadModule)
		loading[name] = nil
		if not ok then
			error("[ClubKitSoft] " .. name .. " failed to load: " .. tostring(result), 2)
		end
		cache[name] = result
		return result
	end
	return loadModule("ClubKitPanel")
end

local function remountFromSources(sources: { [string]: string }): boolean
	local loadOk, panelOrErr = pcall(loadPanelFromSources, sources)
	if not loadOk or type(panelOrErr) ~= "table" or type(panelOrErr.create) ~= "function" then
		warn("[ClubKitPackager] Soft load failed: " .. tostring(panelOrErr))
		return false
	end
	return mountPanel(panelOrErr)
end

panelOpts.mountFromSources = remountFromSources
panelOpts.applyPluginSoftUpdate = function(tag: string, onProgress)
	if softUpdateBusy then
		return { ok = false, error = "Plugin update already in progress" }
	end
	softUpdateBusy = true
	local report
	local ok, err = pcall(function()
		report = PluginSyncCore.applySoftUpdate(
			plugin,
			tag,
			loadPanelFromSources,
			function(panelModule)
				return mountPanel(panelModule)
			end,
			onProgress
		)
	end)
	softUpdateBusy = false
	if not ok then
		return { ok = false, error = tostring(err) }
	end
	return report
end

----------------------------------------------------------------
-- Dev hot-reload from localhost
----------------------------------------------------------------
local function devFetch(path: string): (string?, string?)
	local ok, body = pcall(function()
		return HttpService:GetAsync(DEV_BASE_URL .. path)
	end)
	if not ok then
		return nil, tostring(body)
	end
	return body, nil
end

local function devFetchSources(): ({ [string]: string }?, any)
	local list, listErr = devFetch("/modules.txt")
	if not list then
		return nil, "server unreachable (" .. tostring(listErr) .. ")"
	end
	local sources = {}
	local count = 0
	for name in string.gmatch(list, "[%w_]+") do
		local src, fetchErr = devFetch("/source/" .. name .. ".luau")
		if not src then
			return nil, "fetch failed for " .. name .. " (" .. tostring(fetchErr) .. ")"
		end
		sources[name] = src
		count += 1
	end
	if count == 0 then
		return nil, "server returned an empty module list"
	end
	return sources, count
end

local reloading = false
local function reloadPanel()
	if reloading then
		return
	end
	reloading = true
	local ok, err = pcall(function()
		local sources, info = devFetchSources()
		if sources then
			if remountFromSources(sources) then
				widget.Enabled = true
				print(("[ClubKitPackager] Panel reloaded from dev server (%d modules) — %s"):format(
					info,
					os.date("%H:%M:%S")
				))
				return
			end
		else
			warn("[ClubKitPackager] " .. tostring(info))
		end
		if mountPanel(BundledPanel) then
			widget.Enabled = true
			print("[ClubKitPackager] Remounted bundled panel (start tools/ClubKitPackagerPlugin/dev-serve.ps1 for hot reload)")
		end
	end)
	if not ok then
		warn("[ClubKitPackager] Reload error: " .. tostring(err))
		pcall(function()
			if not currentApi then
				mountPanel(BundledPanel)
			end
		end)
	end
	reloading = false
end

_G.reload_clubkit_panel = reloadPanel
if typeof(shared) == "table" then
	shared.reload_clubkit_panel = reloadPanel
end
reloadPanelButton.Click:Connect(reloadPanel)

----------------------------------------------------------------
-- Boot: bundled first, then re-apply soft tag if needed
----------------------------------------------------------------
mountPanel(BundledPanel)

local function tryAutoSoftPluginUpdate()
	local check = PluginSyncCore.checkPluginUpdate(plugin)
	if check.error then
		-- Silent on boot if HTTP disabled / offline
		return
	end
	if not check.needsUpdate or not check.tag then
		return
	end
	print(("[ClubKitPackager] Soft-updating plugin → %s (local %s)"):format(
		tostring(check.remoteVersion or check.tag),
		check.localVersion
	))
	local report = panelOpts.applyPluginSoftUpdate(check.tag, nil)
	if report and report.ok then
		print(("[ClubKitPackager] Plugin soft-updated (%d modules) v%s"):format(
			report.moduleCount or 0,
			tostring(report.version or "?")
		))
	elseif report and report.error then
		warn("[ClubKitPackager] Plugin soft-update failed: " .. tostring(report.error))
	end
end

-- Once per Studio session — hot-reload remounts should not re-hit GitHub immediately.
if _G.__clubkitPluginAutoSoft ~= true then
	_G.__clubkitPluginAutoSoft = true
	task.defer(tryAutoSoftPluginUpdate)
end

openPanelButton.Click:Connect(function()
	widget.Enabled = true
	task.defer(function()
		if currentApi then
			currentApi.checkForUpdates()
			currentApi.runDiagnostics()
		end
	end)
end)

print(
	("[ClubKitPackager] Loaded kit v%s · plugin v%s — Swiss-knife panel"):format(
		Manifest.KIT_VERSION,
		Manifest.PLUGIN_VERSION or Manifest.KIT_VERSION
	)
)
print("[ClubKitPackager] Toolbar: Open Panel · Reload Panel · Gen Tools")
print("[ClubKitPackager] Command Bar: generate_tools_folder() · reload_clubkit_panel()")
print("[ClubKitPackager] Hot reload: run tools/ClubKitPackagerPlugin/dev-serve.ps1, then Reload Panel")
