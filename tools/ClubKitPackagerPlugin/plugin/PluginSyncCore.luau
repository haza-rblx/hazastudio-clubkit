--!nocheck
--[[
  Soft-update Studio plugin modules from GitHub tags (loadstring remount).
  Does NOT overwrite the installed .rbxm — bootstrap stays on disk; panel/*.luau remount.
]]

local Manifest = require(script.Parent.ClubKitManifest)
local SourceSyncCore = require(script.Parent.SourceSyncCore)

local PluginSyncCore = {}

local SETTING_KEY = Manifest.PLUGIN_APPLIED_TAG_SETTING or "ClubKit_PluginAppliedTag"

export type PluginCheckResult = {
	ok: boolean,
	localVersion: string,
	remoteVersion: string?,
	tag: string?,
	needsUpdate: boolean,
	error: string?,
}

export type SoftApplyReport = {
	ok: boolean,
	tag: string?,
	version: string?,
	moduleCount: number,
	error: string?,
}

function PluginSyncCore.getLocalPluginVersion(): string
	return tostring(Manifest.PLUGIN_VERSION or Manifest.KIT_VERSION or "0.0.0")
end

function PluginSyncCore.getAppliedTag(plugin): string?
	if not plugin or typeof(plugin.GetSetting) ~= "function" then
		return nil
	end
	local ok, value = pcall(function()
		return plugin:GetSetting(SETTING_KEY)
	end)
	if ok and type(value) == "string" and #value > 0 then
		return value
	end
	return nil
end

function PluginSyncCore.setAppliedTag(plugin, tag: string)
	if not plugin or typeof(plugin.SetSetting) ~= "function" then
		return
	end
	pcall(function()
		plugin:SetSetting(SETTING_KEY, tag)
	end)
end

function PluginSyncCore.fetchPluginVersionAtTag(tag: string): (string?, string?)
	local prefix = Manifest.PLUGIN_SOURCE_PREFIX or "tools/ClubKitPackagerPlugin/plugin/"
	local path = prefix .. "ClubKitManifest.luau"
	local source, err = SourceSyncCore.downloadFileAtTag(tag, path)
	if not source then
		return nil, err
	end
	local pluginVer = string.match(source, 'PLUGIN_VERSION%s*=%s*"(%d+%.%d+%.%d+)"')
	if pluginVer then
		return pluginVer, nil
	end
	local kitVer = string.match(source, 'KIT_VERSION%s*=%s*"(%d+%.%d+%.%d+)"')
	if kitVer then
		return kitVer, nil
	end
	return nil, "PLUGIN_VERSION / KIT_VERSION not found in remote ClubKitManifest"
end

function PluginSyncCore.moduleNameFromRepoPath(repoPath: string): string?
	local prefix = Manifest.PLUGIN_SOURCE_PREFIX or "tools/ClubKitPackagerPlugin/plugin/"
	if string.sub(repoPath, 1, #prefix) ~= prefix then
		return nil
	end
	local base = string.match(repoPath, "([^/]+)$")
	if not base then
		return nil
	end
	return string.match(base, "^([%w_]+)%.luau$")
end

function PluginSyncCore.fetchPluginSources(tag: string, onProgress): ({ [string]: string }?, string?)
	local prefix = Manifest.PLUGIN_SOURCE_PREFIX or "tools/ClubKitPackagerPlugin/plugin/"
	local bootstrap = Manifest.PLUGIN_BOOTSTRAP or "HazastudioClubKit.plugin.luau"
	local files, listErr = SourceSyncCore.listLuauFilesAtTag(tag, prefix, { bootstrap })
	if listErr or not files then
		return nil, listErr or "No plugin files"
	end
	if #files == 0 then
		return nil, "No plugin modules under " .. prefix
	end

	local sources: { [string]: string } = {}
	local total = #files
	for i, repoPath in files do
		if onProgress then
			onProgress(("Fetching %s"):format(repoPath), i, total)
		end
		local name = PluginSyncCore.moduleNameFromRepoPath(repoPath)
		if not name then
			continue
		end
		local source, dlErr = SourceSyncCore.downloadFileAtTag(tag, repoPath)
		if not source then
			return nil, repoPath .. ": " .. tostring(dlErr)
		end
		sources[name] = source
		if i % 3 == 0 then
			task.wait()
		end
	end

	if sources.ClubKitPanel == nil then
		return nil, "Remote tag missing ClubKitPanel.luau"
	end
	return sources, nil
end

function PluginSyncCore.checkPluginUpdate(plugin): PluginCheckResult
	local result: PluginCheckResult = {
		ok = false,
		localVersion = PluginSyncCore.getLocalPluginVersion(),
		needsUpdate = false,
	}

	local tag, tagErr = SourceSyncCore.fetchLatestTag()
	if tagErr or not tag then
		result.error = tagErr or "No tag"
		return result
	end
	result.tag = tag

	local remoteVer, verErr = PluginSyncCore.fetchPluginVersionAtTag(tag)
	if verErr or not remoteVer then
		result.error = verErr or "No remote plugin version"
		return result
	end
	result.remoteVersion = remoteVer
	result.ok = true

	-- Outdated if remote PLUGIN_VERSION is newer than the loaded Manifest.
	local cmp = SourceSyncCore.compareVersions(result.localVersion, remoteVer)
	result.needsUpdate = cmp < 0

	-- Also outdated if buyer previously soft-applied a newer tag than what is loaded now
	-- (e.g. Studio restarted back onto an older RBXM bundle).
	local applied = PluginSyncCore.getAppliedTag(plugin)
	if applied then
		local appliedVer = string.gsub(applied, "^[vV]", "")
		if SourceSyncCore.compareVersions(result.localVersion, appliedVer) < 0 then
			result.needsUpdate = true
			-- Prefer re-applying the latest tag (result.tag) rather than a stale applied one.
		end
	end

	return result
end

--[[
  Fetch + remount via callback. mountFromSources(sources) must return ClubKitPanel module table.
  onAfterMount(panelModule) should destroy and remount the dock UI.
]]
function PluginSyncCore.applySoftUpdate(
	plugin,
	tag: string,
	mountFromSources: (sources: { [string]: string }) -> any,
	onAfterMount: (panelModule: any) -> boolean,
	onProgress
): SoftApplyReport
	local report: SoftApplyReport = {
		ok = false,
		tag = tag,
		moduleCount = 0,
	}

	local remoteVer = PluginSyncCore.fetchPluginVersionAtTag(tag)
	report.version = remoteVer

	local sources, fetchErr = PluginSyncCore.fetchPluginSources(tag, onProgress)
	if not sources then
		report.error = fetchErr
		return report
	end

	local count = 0
	for _ in sources do
		count += 1
	end
	report.moduleCount = count

	local loadOk, panelOrErr = pcall(mountFromSources, sources)
	if not loadOk or type(panelOrErr) ~= "table" or type(panelOrErr.create) ~= "function" then
		report.error = "Failed to load soft-updated panel: " .. tostring(panelOrErr)
		return report
	end

	local mountOk = onAfterMount(panelOrErr)
	if not mountOk then
		report.error = "Panel remount failed after soft-update"
		return report
	end

	PluginSyncCore.setAppliedTag(plugin, tag)
	report.ok = true
	return report
end

return PluginSyncCore
