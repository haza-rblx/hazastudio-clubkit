--!nocheck
-- Studio Edit Mode: generate empty ServerStorage.Tools folders from role config.
--
-- Command Bar (tanpa plugin) — SATU baris, selalu jalan:
--   require(game.ReplicatedStorage.Hazastudio_ClubKit.Shared.Studio.GenerateRoleToolsFolder).run()
--
-- Dengan plugin ClubKit Studio Tools terpasang:
--   generate_tools_folder()

local RunService = game:GetService("RunService")

local StudioToolsCommand = require(script.Parent.StudioToolsCommand)

export type GenerateOptions = {
	archiveFolder: boolean?,
	rootName: string?,
}

local ServerStorage = game:GetService("ServerStorage")

local GenerateRoleToolsFolder = {}

local function collectFolderNames(): ({ string }, any?)
	local mod = StudioToolsCommand.resolveModule()
	if not mod then
		return {}, nil
	end
	local shared = mod.Parent.Parent
	local constants = shared:FindFirstChild("Constants")
	local domain = shared:FindFirstChild("Domain")
	if not constants or not domain then
		return {}, nil
	end

	local configModule = constants:FindFirstChild("Config")
	local rolesDomainModule = domain:FindFirstChild("RolesDomain")
	if not configModule or not rolesDomainModule then
		return {}, nil
	end

	local okConfig, config = pcall(require, configModule)
	local okDomain, RolesDomain = pcall(require, rolesDomainModule)
	if not okConfig or not okDomain or type(config) ~= "table" or type(RolesDomain) ~= "table" then
		return {}, nil
	end

	local folderNames: { string } = {}
	if type(RolesDomain.buildStudioToolFolderList) == "function" then
		folderNames = RolesDomain.buildStudioToolFolderList()
	end

	return folderNames, config.RoleTools
end

local function ensureFolder(parent: Instance, name: string): (Folder, boolean)
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing :: Folder, false
	end
	if existing then
		warn(("[generate_tools_folder] Skip %s — sudah ada (%s)"):format(name, existing.ClassName))
		return existing :: Folder, false
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder, true
end

function GenerateRoleToolsFolder.run(options: GenerateOptions?): { created: number, existing: number, folders: { string } }
	if not RunService:IsStudio() then
		warn("[generate_tools_folder] Hanya untuk Roblox Studio.")
		return { created = 0, existing = 0, folders = {} }
	end
	if RunService:IsRunning() then
		warn("[generate_tools_folder] Stop Play dulu — hanya Edit Mode.")
		return { created = 0, existing = 0, folders = {} }
	end

	options = options or {}
	local includeArchive = if options.archiveFolder == nil then true else options.archiveFolder

	local folderNames, roleToolsCfg = collectFolderNames()
	if #folderNames == 0 then
		warn("[generate_tools_folder] Tidak ada folder dari config. Sync Rojo / cek ClubKitConfig.")
		return { created = 0, existing = 0, folders = {} }
	end

	local rootName = tostring((roleToolsCfg and roleToolsCfg.ROOT_FOLDER) or options.rootName or "Tools")
	local toolsRoot = ServerStorage:FindFirstChild(rootName)
	local createdRoot = false
	if not toolsRoot then
		toolsRoot = Instance.new("Folder")
		toolsRoot.Name = rootName
		toolsRoot.Parent = ServerStorage
		createdRoot = true
	elseif not toolsRoot:IsA("Folder") then
		warn(("[generate_tools_folder] ServerStorage.%s bukan Folder"):format(rootName))
		return { created = 0, existing = 0, folders = {} }
	end

	print("=== generate_tools_folder ===")
	print(("Root: ServerStorage.%s%s"):format(rootName, if createdRoot then " (created)" else ""))
	print(("Folders from config: %d"):format(#folderNames))

	local created = 0
	local existing = 0

	for _, folderName in ipairs(folderNames) do
		local _, wasCreated = ensureFolder(toolsRoot :: Folder, folderName)
		if wasCreated then
			created += 1
			print(("  [CREATE] %s"):format(folderName))
		else
			existing += 1
			print(("  [OK] %s"):format(folderName))
		end
	end

	if includeArchive then
		local _, wasCreated = ensureFolder(toolsRoot :: Folder, "_Archive")
		if wasCreated then
			created += 1
			print("  [CREATE] _Archive")
		else
			existing += 1
			print("  [OK] _Archive")
		end
	end

	print(("Selesai — created: %d | existed: %d | isi Tool manual per folder"):format(created, existing))
	return {
		created = created,
		existing = existing,
		folders = folderNames,
	}
end

function GenerateRoleToolsFolder.install()
	StudioToolsCommand.registerCommandBarGlobal()
	print("[ClubKit] generate_tools_folder() siap (plugin / shared _G).")
end

return GenerateRoleToolsFolder
