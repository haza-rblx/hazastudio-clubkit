--!nocheck
-- Collect / unpack all Club Kit instances into the standard package structure.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SerializationService = game:GetService("SerializationService")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local StudioService = game:GetService("StudioService")
local Workspace = game:GetService("Workspace")

local Manifest = require(script.Parent.ClubKitManifest)

local PackagerCore = {}

export type ExportOptions = {
	includeConfig: boolean,
	includeSecrets: boolean,
}

export type SyncBhmsAddonExportOptions = {}

export type UnpackOptions = {
	replaceExisting: boolean,
	keepBuyerConfig: boolean,
	keepBuyerSecrets: boolean,
}

export type CollectReport = {
	ok: { string },
	missing: { string },
	warnings: { string },
	instanceCount: number,
}

export type UnpackReport = {
	ok: { string },
	skipped: { string },
	replaced: { string },
	missing: { string },
	warnings: { string },
}

local function getService(serviceName: string): Instance?
	if serviceName == "StarterPlayerScripts" then
		return StarterPlayer:FindFirstChild("StarterPlayerScripts")
	end
	if serviceName == "Workspace" then
		return workspace
	end

	local ok, svc = pcall(function()
		return game:GetService(serviceName)
	end)
	if ok and svc then
		return svc
	end
	return nil
end

local function removeExistingPackage(name: string)
	for _, parent in ipairs({ Workspace, ServerStorage }) do
		local old = parent:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
end

local function createPackageModel(name: string): Model
	local packageRoot = Instance.new("Model")
	packageRoot.Name = name
	return packageRoot
end

local function parentPackageModel(packageRoot: Model)
	packageRoot.Parent = Workspace
end

local function ensureServiceFolder(packageRoot: Instance, serviceName: string): Folder
	local existing = packageRoot:FindFirstChild(serviceName)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = serviceName
	folder.Parent = packageRoot
	return folder
end

local function countDescendants(root: Instance): number
	local n = 1
	for _ in root:GetDescendants() do
		n += 1
	end
	return n
end

local function logOk(report: CollectReport, line: string, inst: Instance?)
	table.insert(report.ok, line)
	if inst then
		report.instanceCount += countDescendants(inst)
	end
end

local function logMissing(report: CollectReport, line: string)
	table.insert(report.missing, line)
end

local function logWarn(report: CollectReport | UnpackReport, line: string)
	table.insert(report.warnings, line)
end

local function cloneInto(parent: Folder, source: Instance, destName: string?): Instance
	local clone = source:Clone()
	clone.Name = destName or source.Name
	clone.Parent = parent
	return clone
end

local function findWorkspaceModelRoot(name: string): Instance?
	local hit = workspace:FindFirstChild(name, true)
	if not hit then
		return nil
	end
	if hit:IsA("Model") then
		return hit
	end
	local ancestor = hit:FindFirstAncestorOfClass("Model")
	if ancestor then
		return ancestor
	end
	return hit
end

local bhmsExcludeSet: { [string]: boolean }? = nil

local function isBhmsExcluded(name: string): boolean
	if not bhmsExcludeSet then
		bhmsExcludeSet = {}
		for _, n in ipairs(Manifest.BHMS_EXCLUDE_NAMES or {}) do
			bhmsExcludeSet[n] = true
		end
	end
	return bhmsExcludeSet[name] == true
end

local function isCollectExcluded(serviceName: string, instanceName: string): boolean
	if isBhmsExcluded(instanceName) then
		return true
	end
	for _, block in ipairs(Manifest.COLLECT_EXCLUDE or {}) do
		if block.service == serviceName then
			for _, name in ipairs(block.names) do
				if name == instanceName then
					return true
				end
			end
		end
	end
	return false
end

local function isWorkspaceSkipped(name: string): boolean
	for _, skipName in ipairs(Manifest.WORKSPACE_SKIP or {}) do
		if skipName == name then
			return true
		end
	end
	return name == Manifest.PACKAGE_NAME or name == Manifest.SYNC_BHMS_ADDON_PACKAGE_NAME
end

local function stripShowcase(root: Instance): number
	local stripped = 0
	for _, desc in root:GetDescendants() do
		if desc.Name == "ClubKitShowcase" and desc:IsA("ModuleScript") then
			desc:Destroy()
			stripped += 1
		end
	end
	return stripped
end

local function blankTemplateConfigSource(source: string): string
	local src = source
	src = src:gsub("OwnerUserId%s*=%s*%d+", "OwnerUserId = 0")
	-- Swallow an existing `:: { [number]: boolean }` when the buyer source already
	-- carries the annotation — replacing only the table literal would leave the old
	-- annotation behind and chain a second one, which is a Luau syntax error.
	local annotated: number
	src, annotated = src:gsub(
		"AdminUserIds%s*=%s*{[^}]*}%s*::%s*{[^}]*}",
		"AdminUserIds = {} :: { [number]: boolean }"
	)
	if annotated == 0 then
		src = src:gsub("AdminUserIds%s*=%s*{[^}]*}", "AdminUserIds = {} :: { [number]: boolean }")
	end
	src = src:gsub("LegacySyncBhms%s*=%s*true", "LegacySyncBhms = false")
	src = src:gsub("HierapolisCustom%s*=%s*true", "HierapolisCustom = false")
	return src
end

-- Secrets are always blanked before packaging, even when the dev's own place has
-- real values filled in — a distributed package must never carry live API secrets.
-- Matches "Secrets.<FieldName> = "..."" assignments; leaves everything else intact.
local function blankTemplateSecretsSource(source: string): string
	local src = source:gsub('(Secrets%.%w+%s*=%s*)"[^"]*"', '%1""')
	return src
end

local function shouldSkipMainPackChild(serviceName: string, instanceName: string, options: ExportOptions): (boolean, string?)
	if isBhmsExcluded(instanceName) then
		return true, "bhms"
	end
	if serviceName == "Workspace" and isWorkspaceSkipped(instanceName) then
		return true, "skip"
	end
	if not options.includeSecrets and serviceName == "ServerScriptService" and instanceName == "Hazastudio_ClubKitSecrets" then
		return true, "secrets"
	end
	if options.includeConfig and serviceName == "ReplicatedStorage" and instanceName == "Hazastudio_ClubKitConfig" then
		return true, "config_later"
	end
	if not options.includeConfig and serviceName == "ReplicatedStorage" and instanceName == "Hazastudio_ClubKitConfig" then
		return true, "no_config"
	end
	return false, nil
end

local function cloneServiceChildrenForPack(
	svc: Instance,
	dest: Folder,
	serviceName: string,
	options: ExportOptions,
	report: CollectReport
)
	for _, child in ipairs(svc:GetChildren()) do
		local skip, reason = shouldSkipMainPackChild(serviceName, child.Name, options)
		if skip then
			if reason == "bhms" then
				logWarn(report, ("Excluded (BHMS): %s/%s"):format(serviceName, child.Name))
			end
			continue
		end
		local okClone, clone = pcall(function()
			return cloneInto(dest, child)
		end)
		if not okClone then
			logWarn(report, ("Cannot clone %s/%s"):format(serviceName, child.Name))
			continue
		end
		if child.Name == "Hazastudio_ClubKit" then
			local stripped = stripShowcase(clone)
			if stripped > 0 then
				logWarn(report, ("Stripped ClubKitShowcase x%d"):format(stripped))
			end
		end
		logOk(report, ("%s/%s"):format(serviceName, child.Name), clone)
	end
end

local function isUnderWorkspaceBoardFolder(inst: Instance): boolean
	local folderName = Manifest.WORKSPACE_BOARD_FOLDER
	if type(folderName) ~= "string" or folderName == "" then
		return false
	end
	local boardFolder = workspace:FindFirstChild(folderName)
	if not boardFolder then
		return false
	end
	return inst == boardFolder or inst:IsDescendantOf(boardFolder)
end

local function verifyKitFingerprint(): (boolean, string?)
	local kitFolder = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKit")
	if not kitFolder then
		return false, "Hazastudio_ClubKit not found in ReplicatedStorage"
	end
	local kitProduct = kitFolder:FindFirstChild("KitProduct")
	if not kitProduct or not kitProduct:IsA("ModuleScript") then
		return false, "KitProduct not found"
	end
	local ok, product = pcall(require, kitProduct)
	if not ok or type(product) ~= "table" then
		return false, "KitProduct failed to require"
	end
	if product.ProductId ~= Manifest.PRODUCT_ID then
		return false, ("ProductId mismatch (expected %s)"):format(Manifest.PRODUCT_ID)
	end
	return true, product.KitVersion
end

local function writeManifestModule(packageRoot: Instance, version: string?, exportOptions: ExportOptions)
	local old = packageRoot:FindFirstChild(Manifest.MANIFEST_NAME)
	if old then
		old:Destroy()
	end

	local lines = {
		"-- Generated by Hazastudio Club Kit Packager. Do not edit manually.",
		"return {",
		('\tproductId = "%s",'):format(Manifest.PRODUCT_ID),
		('\tkitVersion = "%s",'):format(version or Manifest.KIT_VERSION),
		("\texportedAt = %d,"):format(os.time()),
		("\tincludeConfig = %s,"):format(tostring(exportOptions.includeConfig)),
		("\tincludeSecrets = %s,"):format(tostring(exportOptions.includeSecrets)),
		'\tcollectMode = "full_service",',
		"}",
	}

	local mod = Instance.new("ModuleScript")
	mod.Name = Manifest.MANIFEST_NAME
	mod.Source = table.concat(lines, "\n")
	mod.Parent = packageRoot
end

local function readManifest(packageRoot: Instance): { [string]: any }?
	local mod = packageRoot:FindFirstChild(Manifest.MANIFEST_NAME)
	if mod and mod:IsA("ModuleScript") then
		local ok, data = pcall(require, mod)
		if ok and type(data) == "table" then
			return data
		end
	end
	return nil
end

function PackagerCore.collect(options: ExportOptions): (Model?, CollectReport)
	local report: CollectReport = {
		ok = {},
		missing = {},
		warnings = {},
		instanceCount = 0,
	}

	local valid, versionOrErr = verifyKitFingerprint()
	if not valid then
		logWarn(report, versionOrErr :: string)
	end

	removeExistingPackage(Manifest.PACKAGE_NAME)

	local packageRoot = createPackageModel(Manifest.PACKAGE_NAME)

	for _, serviceName in ipairs(Manifest.FULL_SERVICE_PACK or {}) do
		local svc = getService(serviceName)
		if not svc then
			logMissing(report, ("service %s"):format(serviceName))
			continue
		end
		local dest = ensureServiceFolder(packageRoot, serviceName)
		cloneServiceChildrenForPack(svc, dest, serviceName, options, report)
	end

	local starterPlayerScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	if starterPlayerScripts then
		local dest = ensureServiceFolder(packageRoot, "StarterPlayerScripts")
		cloneServiceChildrenForPack(starterPlayerScripts, dest, "StarterPlayerScripts", options, report)
	else
		logMissing(report, "StarterPlayerScripts")
	end

	if options.includeSecrets then
		local serverScriptFolder = packageRoot:FindFirstChild("ServerScriptService")
		local secretsPkg = serverScriptFolder and serverScriptFolder:FindFirstChild("Hazastudio_ClubKitSecrets")
		local secretsMod = secretsPkg and secretsPkg:FindFirstChild("Secrets")
		if secretsMod and secretsMod:IsA("ModuleScript") then
			secretsMod.Source = blankTemplateSecretsSource(secretsMod.Source)
			logOk(report, "ServerScriptService/Hazastudio_ClubKitSecrets (blank template)", secretsPkg)
		end
	end

	if options.includeConfig then
		local configSrc = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKitConfig")
		if configSrc then
			local dest = ensureServiceFolder(packageRoot, "ReplicatedStorage")
			local clone = cloneInto(dest, configSrc)
			local configMod = clone:FindFirstChild("ClubKitConfig")
			if configMod and configMod:IsA("ModuleScript") then
				configMod.Source = blankTemplateConfigSource(configMod.Source)
			end
			-- Place-pack overlays are buyer-specific; never ship them in the product package.
			local hierapolis = clone:FindFirstChild("HierapolisCustom")
			if hierapolis then
				hierapolis:Destroy()
				logWarn(report, "Stripped Hazastudio_ClubKitConfig.HierapolisCustom (place-pack overlay)")
			end
			logOk(report, "ReplicatedStorage/Hazastudio_ClubKitConfig (blank template)", clone)
		else
			logMissing(report, "ReplicatedStorage/Hazastudio_ClubKitConfig")
		end
	end

	-- Remove empty service folders.
	for _, child in ipairs(packageRoot:GetChildren()) do
		if child:IsA("Folder") and #child:GetChildren() == 0 and child.Name ~= Manifest.MANIFEST_NAME then
			child:Destroy()
		end
	end

	writeManifestModule(packageRoot, if valid then versionOrErr else nil, options)
	parentPackageModel(packageRoot)

	return packageRoot, report
end

-- SyncBhms add-on: legacy BHMS dance pack (extras/place-packs/SyncBhms). Ship separately from main template.
function PackagerCore.collectSyncBhmsAddon(_options: SyncBhmsAddonExportOptions?): (Model?, CollectReport)
	local report: CollectReport = {
		ok = {},
		missing = {},
		warnings = {},
		instanceCount = 0,
	}

	local valid, versionOrErr = verifyKitFingerprint()
	if not valid then
		logWarn(report, versionOrErr :: string)
	end

	removeExistingPackage(Manifest.SYNC_BHMS_ADDON_PACKAGE_NAME)

	local packageRoot = createPackageModel(Manifest.SYNC_BHMS_ADDON_PACKAGE_NAME)

	local bhmsServices = {
		"ReplicatedStorage",
		"ServerScriptService",
		"StarterGui",
		"StarterPlayerScripts",
		"Workspace",
	}

	for _, serviceName in ipairs(bhmsServices) do
		local svc = getService(serviceName)
		if not svc then
			logMissing(report, ("service %s"):format(serviceName))
			continue
		end
		local dest = ensureServiceFolder(packageRoot, serviceName)
		local foundAny = false
		for _, child in ipairs(svc:GetChildren()) do
			if not isBhmsExcluded(child.Name) then
				continue
			end
			local okClone, clone = pcall(function()
				return cloneInto(dest, child)
			end)
			if not okClone then
				logWarn(report, ("Cannot clone %s/%s"):format(serviceName, child.Name))
				continue
			end
			foundAny = true
			if child.Name == "SyncBhms" then
				logOk(report, ("Workspace/SyncBhms (full place-pack model) [%d instances]"):format(countDescendants(clone)), clone)
			else
				logOk(report, ("%s/%s"):format(serviceName, child.Name), clone)
			end
		end
		if not foundAny and #dest:GetChildren() == 0 then
			dest:Destroy()
		end
	end

	if #packageRoot:GetChildren() == 0 then
		logMissing(report, "No SyncBhms instances found in place (see extras/place-packs/SyncBhms/)")
	end

	local mod = Instance.new("ModuleScript")
	mod.Name = Manifest.MANIFEST_NAME
	mod.Source = table.concat({
		"-- Generated by Hazastudio Club Kit Packager (SyncBhms add-on). Do not edit manually.",
		"return {",
		('\tproductId = "%s",'):format(Manifest.PRODUCT_ID),
		('\tkitVersion = "%s",'):format(if valid then versionOrErr else Manifest.KIT_VERSION),
		("\texportedAt = %d,"):format(os.time()),
		'\tpackageKind = "sync_bhms_addon",',
		'\tcollectMode = "bhms_only",',
		"}",
	}, "\n")
	mod.Parent = packageRoot

	parentPackageModel(packageRoot)
	logWarn(report, "SyncBhms add-on = BHMS dance pack only. Set ClubKitConfig.Features.LegacySyncBhms = true after unpack.")

	return packageRoot, report
end

function PackagerCore.collectGroupAddon(options: SyncBhmsAddonExportOptions?): (Model?, CollectReport)
	return PackagerCore.collectSyncBhmsAddon(options)
end

function PackagerCore.findPackageRoot(instances: { Instance }): Instance?
	for _, inst in ipairs(instances) do
		if inst.Name == Manifest.PACKAGE_NAME or inst.Name == Manifest.SYNC_BHMS_ADDON_PACKAGE_NAME then
			return inst
		end
	end
	for _, inst in ipairs(instances) do
		if inst:FindFirstChild(Manifest.MANIFEST_NAME) then
			return inst
		end
	end
	for _, inst in ipairs(instances) do
		if (inst:IsA("Folder") or inst:IsA("Model"))
			and inst:FindFirstChild("ReplicatedStorage")
			and inst:FindFirstChild("ServerScriptService")
		then
			return inst
		end
	end
	return instances[1]
end

local function shouldPreserveOnUnpack(instanceName: string, serviceName: string, options: UnpackOptions): boolean
	if options.keepBuyerConfig and serviceName == "ReplicatedStorage" and instanceName == "Hazastudio_ClubKitConfig" then
		return true
	end
	if options.keepBuyerSecrets and serviceName == "ServerScriptService" and instanceName == "Hazastudio_ClubKitSecrets" then
		return true
	end
	return false
end

local function isWorkspaceMultiPackedName(name: string): boolean
	for _, base in ipairs(Manifest.WORKSPACE_MULTI) do
		if name == base or string.match(name, "^" .. base .. "__%d+$") then
			return true
		end
	end
	return false
end

local function placeChild(
	targetService: Instance,
	child: Instance,
	serviceName: string,
	options: UnpackOptions,
	report: UnpackReport
)
	local allowDuplicate = serviceName == "Workspace" and isWorkspaceMultiPackedName(child.Name)

	if shouldPreserveOnUnpack(child.Name, serviceName, options) then
		if targetService:FindFirstChild(child.Name) then
			table.insert(report.skipped, ("%s/%s (buyer preserved)"):format(serviceName, child.Name))
			return
		end
	end

	if not allowDuplicate then
		local existing = targetService:FindFirstChild(child.Name)
		if existing then
			if not options.replaceExisting then
				table.insert(report.skipped, ("%s/%s (already exists)"):format(serviceName, child.Name))
				return
			end
			existing:Destroy()
			table.insert(report.replaced, ("%s/%s"):format(serviceName, child.Name))
		end
	end

	local clone = child:Clone()

	-- Workspace multi-instance: restore original name (RunningText__2 -> RunningText).
	if serviceName == "Workspace" then
		local baseName = string.match(child.Name, "^(.+)__%d+$")
		if baseName then
			clone.Name = baseName
		end
	end

	clone.Parent = targetService
	table.insert(report.ok, ("%s/%s"):format(serviceName, clone.Name))
end

function PackagerCore.unpack(packageRoot: Instance, options: UnpackOptions): UnpackReport
	local report: UnpackReport = {
		ok = {},
		skipped = {},
		replaced = {},
		missing = {},
		warnings = {},
	}

	local meta = readManifest(packageRoot)
	if meta and meta.productId and meta.productId ~= Manifest.PRODUCT_ID then
		logWarn(report, ("Manifest ProductId mismatch: %s"):format(tostring(meta.productId)))
	end

	local serviceNames = {
		"ReplicatedFirst",
		"ReplicatedStorage",
		"ServerScriptService",
		"StarterPlayerScripts",
		"StarterGui",
		"ServerStorage",
		"Workspace",
		"Lighting",
	}

	for _, serviceName in ipairs(serviceNames) do
		local bucket = packageRoot:FindFirstChild(serviceName)
		if not bucket or not bucket:IsA("Folder") then
			continue
		end
		local targetService = getService(serviceName)
		if not targetService then
			table.insert(report.missing, ("service %s"):format(serviceName))
			continue
		end
		for _, child in ipairs(bucket:GetChildren()) do
			placeChild(targetService, child, serviceName, options, report)
		end
	end

	-- Never leave demo ClubKitShowcase on buyer places after unpack.
	local rs = getService("ReplicatedStorage")
	local kit = rs and rs:FindFirstChild("Hazastudio_ClubKit")
	if kit then
		local stripped = 0
		for _, desc in kit:GetDescendants() do
			if desc.Name == "ClubKitShowcase" and desc:IsA("ModuleScript") then
				desc:Destroy()
				stripped += 1
			end
		end
		if stripped > 0 then
			logWarn(report, ("Stripped ClubKitShowcase x%d after unpack"):format(stripped))
		end
	end

	-- Stale Rojo `init` twins (see SourceSyncCore for the full note). A Script/
	-- ModuleScript that still holds a CHILD named `init` is pre-Rojo cruft: Rojo
	-- collapses `Folder/init.luau` into the folder, so the parent already IS the init.
	-- The EffectDonate ones are LocalScripts and therefore auto-run, throwing
	-- "Utils is not a valid member" from a frozen copy of an old require path.
	-- Swept here too so a fresh install from an older .rbxm self-heals.
	do
		local initTwins = 0
		-- Scope from the manifest (includes the vendored ReplicatedStorage.Icon,
		-- which the kit ships and source-syncs) so this never drifts from
		-- SERVICE_ROOTS, and never reaches buyer or third-party content.
		for _, entry in ipairs(Manifest.SERVICE_ROOTS or {}) do
			local svc = getService(entry.service)
			local root = svc and svc:FindFirstChild(entry.name)
			if root then
				for _, desc in root:GetDescendants() do
					if desc:IsA("LuaSourceContainer") and desc.Name == "init" then
						local holder = desc.Parent
						if holder and holder:IsA("LuaSourceContainer") then
							desc:Destroy()
							initTwins += 1
						end
					end
				end
			end
		end
		if initTwins > 0 then
			logWarn(report, ("Stripped stale Rojo init twins x%d after unpack"):format(initTwins))
		end
	end

	-- Ensure donation display root tags are applied (CollectionService tags persist in rbxm).
	local displayTag = "DonationDisplayRoot"
	for _, tagName in ipairs(Manifest.WORKSPACE_MULTI) do
		for _, inst in ipairs(workspace:GetDescendants()) do
			if inst.Name == tagName and not CollectionService:HasTag(inst, displayTag) then
				CollectionService:AddTag(inst, displayTag)
				table.insert(report.ok, ("Tagged %s"):format(inst:GetFullName()))
			end
		end
	end

	return report
end

--- Prompt for a .rbxm/.rbxmx Club Kit package, deserialize into Workspace, unpack into services.
-- Temporary package model is removed after unpack. Returns (report, errMessage).
-- errMessage is "cancelled" when the user closes the file dialog.
function PackagerCore.promptAndUnpackFromRbxm(options: UnpackOptions): (UnpackReport?, string?)
	local file: File?
	local promptOk, promptResult = pcall(function()
		if type((StudioService :: any).PromptImportFileAsync) == "function" then
			return (StudioService :: any):PromptImportFileAsync({ "rbxm", "rbxmx" })
		end
		return StudioService:PromptImportFile({ "rbxm", "rbxmx" })
	end)
	if not promptOk then
		return nil, ("File prompt failed: %s"):format(tostring(promptResult))
	end
	file = promptResult
	if file == nil then
		return nil, "cancelled"
	end

	local binaryOk, binaryOrErr = pcall(function()
		return file:GetBinaryContents()
	end)
	if not binaryOk or type(binaryOrErr) ~= "string" or binaryOrErr == "" then
		return nil, ("Could not read file contents: %s"):format(tostring(binaryOrErr))
	end

	local buf = buffer.fromstring(binaryOrErr :: string)
	local deserOk, instancesOrErr = pcall(function()
		if type((SerializationService :: any).DeserializeInstancesAsync) == "function" then
			return (SerializationService :: any):DeserializeInstancesAsync(buf)
		end
		return (SerializationService :: any):DeserializeInstances(buf)
	end)
	if not deserOk then
		return nil, ("RBXM deserialize failed: %s"):format(tostring(instancesOrErr))
	end
	local instances = instancesOrErr :: { Instance }
	if type(instances) ~= "table" or #instances == 0 then
		return nil, "RBXM contained no instances"
	end

	-- Parent under a disposable folder so we can clean up even if findPackageRoot fails.
	local staging = Instance.new("Folder")
	staging.Name = "_ClubKitUnpackStaging"
	staging.Parent = Workspace
	for _, inst in ipairs(instances) do
		inst.Parent = staging
	end

	local packageRoot = PackagerCore.findPackageRoot(instances)
	if not packageRoot or packageRoot == staging then
		staging:Destroy()
		return nil, "No Club Kit package model found inside RBXM (expected HazastudioClubKit_Package)"
	end
	local looksLikePackage = packageRoot.Name == Manifest.PACKAGE_NAME
		or packageRoot.Name == Manifest.SYNC_BHMS_ADDON_PACKAGE_NAME
		or packageRoot:FindFirstChild(Manifest.MANIFEST_NAME) ~= nil
		or (packageRoot:FindFirstChild("ReplicatedStorage") ~= nil and packageRoot:FindFirstChild("ServerScriptService") ~= nil)
	if not looksLikePackage then
		staging:Destroy()
		return nil, "RBXM does not look like a Club Kit package"
	end

	local report = PackagerCore.unpack(packageRoot, options)
	staging:Destroy()
	return report, nil
end

function PackagerCore.printCollectReport(report: CollectReport)
	print("==================================================")
	print("[ClubKitPackager] EXPORT")
	print(("  OK: %d | Missing: %d | Warnings: %d | ~%d instances"):format(
		#report.ok,
		#report.missing,
		#report.warnings,
		report.instanceCount
	))
	for _, line in ipairs(report.ok) do
		print("   + " .. line)
	end
	for _, line in ipairs(report.missing) do
		warn("   - MISSING: " .. line)
	end
	for _, line in ipairs(report.warnings) do
		warn("   ! " .. line)
	end
	print("==================================================")
end

function PackagerCore.printUnpackReport(report: UnpackReport)
	print("==================================================")
	print("[ClubKitPackager] UNPACK")
	print(("  Placed: %d | Replaced: %d | Skipped: %d | Missing svc: %d"):format(
		#report.ok,
		#report.replaced,
		#report.skipped,
		#report.missing
	))
	for _, line in ipairs(report.replaced) do
		print("   ~ replaced " .. line)
	end
	for _, line in ipairs(report.skipped) do
		print("   = skipped " .. line)
	end
	for _, line in ipairs(report.missing) do
		warn("   - " .. line)
	end
	for _, line in ipairs(report.warnings) do
		warn("   ! " .. line)
	end
	print("==================================================")
end

return PackagerCore
