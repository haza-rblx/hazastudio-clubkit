--!nocheck
-- Fetch engine Luau from GitHub tags and apply Source to place instances.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Manifest = require(script.Parent.ClubKitManifest)
local RojoPathMap = require(script.Parent.RojoPathMap)

local SourceSyncCore = {}

export type ApplyReport = {
	ok: { string },
	skipped: { string },
	errors: { string },
	tag: string?,
	version: string?,
}

export type CheckResult = {
	localVersion: string,
	latestTag: string?,
	latestVersion: string?,
	changelog: string?,
	updateAvailable: boolean,
	error: string?,
}

local function httpDisabledMessage(): string
	return "HttpService is disabled. Enable Game Settings → Security → Allow HTTP Requests, then retry."
end

local function requestAsync(url: string, method: string?): (boolean, any)
	if not HttpService.HttpEnabled then
		return false, httpDisabledMessage()
	end

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = method or "GET",
			Headers = {
				["Accept"] = "application/vnd.github+json",
			},
		})
	end)

	if not ok then
		return false, tostring(response)
	end

	if not response.Success then
		return false, ("HTTP %d: %s"):format(response.StatusCode, response.Body or "")
	end

	local decodeOk, body = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)
	if decodeOk then
		return true, body
	end
	return true, response.Body
end

local function requestText(url: string): (boolean, string)
	if not HttpService.HttpEnabled then
		return false, httpDisabledMessage()
	end

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "GET",
		})
	end)

	if not ok then
		return false, tostring(response)
	end
	if not response.Success then
		return false, ("HTTP %d: %s"):format(response.StatusCode, response.Body or "")
	end
	return true, response.Body or ""
end

local function parseSemver(version: string)
	local cleaned = string.gsub(version, "^[vV]", "")
	local major, minor, patch = string.match(cleaned, "^(%d+)%.(%d+)%.(%d+)")
	if not major then
		return nil
	end
	return tonumber(major), tonumber(minor), tonumber(patch)
end

function SourceSyncCore.compareVersions(a: string, b: string): number
	local am, an, ap = parseSemver(a)
	local bm, bn, bp = parseSemver(b)
	if not am or not bm then
		return string.lower(a) < string.lower(b) and -1 or (a == b and 0 or 1)
	end
	if am ~= bm then
		return if am < bm then -1 else 1
	end
	if an ~= bn then
		return if an < bn then -1 else 1
	end
	if ap ~= bp then
		return if ap < bp then -1 else 1
	end
	return 0
end

function SourceSyncCore.getLocalVersion(): string?
	local kit = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKit")
	local mod = kit and kit:FindFirstChild("KitProduct")
	if not mod or not mod:IsA("ModuleScript") then
		return nil
	end
	local ok, product = pcall(require, mod)
	if not ok or type(product) ~= "table" then
		return nil
	end
	return product.KitVersion
end

local function updaterConfig()
	return Manifest.UPDATER
end

local function apiUrl(path: string): string
	local cfg = updaterConfig()
	return ("https://api.github.com/repos/%s/%s%s"):format(cfg.githubOwner, cfg.githubRepo, path)
end

local function rawUrl(tag: string, path: string): string
	local cfg = updaterConfig()
	return ("https://raw.githubusercontent.com/%s/%s/%s/%s"):format(
		cfg.githubOwner,
		cfg.githubRepo,
		tag,
		path
	)
end

function SourceSyncCore.fetchLatestTag(): (string?, string?)
	local ok, data = requestAsync(apiUrl("/tags"))
	if not ok then
		return nil, data
	end
	if type(data) ~= "table" then
		return nil, "Unexpected tags response"
	end

	local bestTag: string? = nil
	local bestVersion: string? = nil
	for _, entry in data do
		local name = entry.name
		if type(name) == "string" then
			local _, _, patch = parseSemver(name)
			if patch then
				if not bestTag or SourceSyncCore.compareVersions(name, bestTag) > 0 then
					bestTag = name
					bestVersion = string.gsub(name, "^[vV]", "")
				end
			end
		end
	end

	if not bestTag then
		return nil, "No semver git tags found"
	end
	return bestTag, nil
end

function SourceSyncCore.fetchVersionAtTag(tag: string): (string?, string?)
	local cfg = updaterConfig()
	local ok, text = requestText(rawUrl(tag, cfg.versionFile))
	if not ok then
		return nil, text
	end
	local version = string.match(text, "(%d+%.%d+%.%d+)")
	if not version then
		return nil, "VERSION file missing semver"
	end
	return version, nil
end

function SourceSyncCore.fetchChangelogAtTag(tag: string): (string?, string?)
	local cfg = updaterConfig()
	local ok, text = requestText(rawUrl(tag, cfg.changelogFile))
	if not ok then
		return nil, text
	end

	local version, verErr = SourceSyncCore.fetchVersionAtTag(tag)
	if verErr or not version then
		version = string.gsub(tag, "^[vV]", "")
	end

	local header = "## [" .. version .. "]"
	local startPos = string.find(text, header, 1, true)
	if not startPos then
		return "(No changelog section for " .. version .. ")", nil
	end

	local sectionStart = startPos + #header
	local nextHeader = string.find(text, "\n## ", sectionStart, true)
	local section = if nextHeader
		then string.sub(text, sectionStart, nextHeader - 1)
		else string.sub(text, sectionStart)
	section = string.gsub(section, "^%s+", "")
	section = string.gsub(section, "%s+$", "")
	return section, nil
end

local function pathAllowed(repoPath: string): boolean
	for _, prefix in Manifest.PROTECTED_SOURCE_PREFIXES do
		if string.sub(repoPath, 1, #prefix) == prefix then
			return false
		end
	end
	local excludes = Manifest.ENGINE_SOURCE_EXCLUDES
	if type(excludes) == "table" then
		for _, excluded in excludes do
			if repoPath == excluded or string.sub(repoPath, 1, #excluded) == excluded then
				return false
			end
		end
	end
	for _, prefix in Manifest.ENGINE_SOURCE_PREFIXES do
		if string.sub(repoPath, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

local function getTreeShaForRef(ref: string): (string?, string?)
	local ok, data = requestAsync(apiUrl("/commits/" .. HttpService:UrlEncode(ref)))
	if not ok then
		return nil, data
	end
	if type(data) ~= "table" or type(data.commit) ~= "table" or type(data.commit.tree) ~= "table" then
		return nil, "Could not resolve commit tree for " .. ref
	end
	return data.commit.tree.sha, nil
end

function SourceSyncCore.listEngineFilesAtTag(tag: string): ({ string }?, string?)
	local treeSha, treeErr = getTreeShaForRef(tag)
	if treeErr or not treeSha then
		return nil, treeErr or "Missing tree sha"
	end

	local ok, data = requestAsync(apiUrl("/git/trees/" .. treeSha .. "?recursive=1"))
	if not ok then
		return nil, data
	end
	if type(data) ~= "table" or type(data.tree) ~= "table" then
		return nil, "Unexpected tree response"
	end

	local files: { string } = {}
	for _, entry in data.tree do
		local path = entry.path
		if type(path) == "string" and entry.type == "blob" and string.match(path, "%.luau$") then
			local repoPath = path
			if pathAllowed(repoPath) then
				table.insert(files, repoPath)
			end
		end
	end

	-- init.luau first within each folder so ModuleScript containers exist before children.
	table.sort(files, function(a, b)
		local aInit = string.match(a, "/init%.[^/]+$") ~= nil
		local bInit = string.match(b, "/init%.[^/]+$") ~= nil
		if aInit ~= bInit then
			return aInit
		end
		return a < b
	end)
	return files, nil
end

function SourceSyncCore.downloadFileAtTag(tag: string, path: string): (string?, string?)
	local ok, body = requestText(rawUrl(tag, path))
	if not ok then
		return nil, body
	end
	return body, nil
end

function SourceSyncCore.applyFile(repoPath: string, source: string): (boolean, string?)
	local parsed = RojoPathMap.parseRepoPath(repoPath)
	if not parsed then
		return false, "Unmapped path: " .. repoPath
	end

	local serviceRoot = RojoPathMap.getServiceRoot(parsed.serviceKey)
	if not serviceRoot then
		return false, "Service missing: " .. parsed.serviceKey
	end

	local ok, err = pcall(function()
		local inst = RojoPathMap.findOrCreateScriptInstance(
			serviceRoot,
			parsed.folderSegments,
			parsed.instanceName,
			parsed.className
		)
		inst.Source = source
	end)

	if not ok then
		return false, tostring(err)
	end
	return true, nil
end

function SourceSyncCore.applyEngineUpdate(tag: string, onProgress)
	local report: ApplyReport = {
		ok = {},
		skipped = {},
		errors = {},
		tag = tag,
	}

	local version, verErr = SourceSyncCore.fetchVersionAtTag(tag)
	if verErr then
		table.insert(report.errors, verErr)
		return report
	end
	report.version = version

	local files, listErr = SourceSyncCore.listEngineFilesAtTag(tag)
	if listErr or not files then
		table.insert(report.errors, listErr or "No files")
		return report
	end

	local total = #files
	for i, repoPath in files do
		if onProgress then
			onProgress(("Applying %s"):format(repoPath), i, total)
		end

		local source, dlErr = SourceSyncCore.downloadFileAtTag(tag, repoPath)
		if not source then
			table.insert(report.errors, repoPath .. ": " .. tostring(dlErr))
			continue
		end

		local applied, applyErr = SourceSyncCore.applyFile(repoPath, source)
		if applied then
			table.insert(report.ok, repoPath)
		else
			local errText = tostring(applyErr)
			if #errText > 200 then
				errText = string.sub(errText, 1, 200) .. "..."
			end
			table.insert(report.errors, repoPath .. ": " .. errText)
		end

		if i % 5 == 0 then
			task.wait()
		end
	end

	-- Dev/demo showcase must not remain on buyer places after engine update.
	local rs = game:GetService("ReplicatedStorage")
	local kit = rs:FindFirstChild("Hazastudio_ClubKit")
	local shared = kit and kit:FindFirstChild("Shared")
	local cfg = shared and shared:FindFirstChild("Config")
	local showcase = cfg and cfg:FindFirstChild("ClubKitShowcase")
	if showcase then
		showcase:Destroy()
		table.insert(report.ok, "(removed) Shared/Config/ClubKitShowcase")
	end

	return report
end

function SourceSyncCore.checkForUpdates(): CheckResult
	local result: CheckResult = {
		localVersion = SourceSyncCore.getLocalVersion() or "unknown",
		updateAvailable = false,
	}

	local tag, tagErr = SourceSyncCore.fetchLatestTag()
	if tagErr or not tag then
		result.error = tagErr or "No tag"
		return result
	end
	result.latestTag = tag

	local version, verErr = SourceSyncCore.fetchVersionAtTag(tag)
	if verErr or not version then
		result.error = verErr
		return result
	end
	result.latestVersion = version

	local changelog, clErr = SourceSyncCore.fetchChangelogAtTag(tag)
	if not clErr then
		result.changelog = changelog
	end

	if result.localVersion ~= "unknown" then
		result.updateAvailable = SourceSyncCore.compareVersions(result.localVersion, version) < 0
	end

	return result
end

return SourceSyncCore
