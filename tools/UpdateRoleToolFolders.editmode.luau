--!nocheck
-- ============================================================
-- Update Role Tool folders in ServerStorage (Edit Mode)
-- ============================================================
-- Sinkronkan ServerStorage.Tools — SATU folder per role (nama folder = chatTag role):
--   • rename folder legacy → nama canonical
--   • merge isi kalau folder target sudah ada
--   • buat folder yang belum ada
--   • pindahkan folder tidak dipakai ke Tools/_Archive (opsional)
--
-- CARA PAKAI:
-- 1. Buka place NUWA di Studio (Edit Mode).
-- 2. Sync Rojo supaya ReplicatedStorage.Shared.* ada.
-- 3. Set DRY_RUN = true, paste script ke Command Bar → Enter → baca Output.
-- 4. Kalau log OK, set DRY_RUN = false → jalankan lagi.
--
-- Lihat juga: tools/EnsureRoleToolFolders.editmode.luau (hanya create, tanpa migrate).
-- ============================================================

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Preview tanpa mengubah instance.
local DRY_RUN = false
-- Pindah folder yang tidak ada di config ke Tools/_Archive (bukan Destroy).
local ARCHIVE_OBSOLETE = true
local ARCHIVE_FOLDER_NAME = "_Archive"
-- Buat placeholder Tool di folder kosong (sama seperti EnsureRoleToolFolders).
local CREATE_PLACEHOLDER_TOOLS = false
local PLACEHOLDER_TOOL_NAME = "_RoleToolPlaceholder"

local LOG: { string } = {}

local function emit(line: string)
	table.insert(LOG, line)
	print(line)
end

-- Nama lama di legacy place → folder canonical (sesuai Roles.luau / chat tag).
local RENAME_TO_CANONICAL: { [string]: string } = {
	["CO-OWNER"] = "INVESTOR",
	["CoOwner"] = "INVESTOR",
	["CO OWNER"] = "INVESTOR",
	["COOWNER"] = "INVESTOR",
	["AFTER TEAM"] = "STAFF",
	["AfterTeam"] = "STAFF",
	["AFTER"] = "STAFF",
	["DEVELOPER"] = "STAFF",
	["DEV"] = "STAFF",
	["MOD"] = "STAFF",
	["MODERATOR"] = "STAFF",
	["ADMIN"] = "STAFF",
	["INFLUENCER"] = "STREAMER",
	["TOP DONOR"] = "ROYALE SPENDER",
	["TOPDONATE"] = "ROYALE SPENDER",
	["TOP DONATION"] = "ROYALE SPENDER",
	["TOP DONATOR"] = "ROYALE SPENDER",
	["TOP DONATE"] = "ROYALE SPENDER",
	["DONOR"] = "DONATUR",
	["DONATE"] = "DONATUR",
	["ELITE MEMBER"] = "EXCLUSIVE",
	["ELITEMEMBER"] = "EXCLUSIVE",
	["ELITE"] = "EXCLUSIVE",
	["VVIP MEMBER"] = "VVIP",
	["VIP MEMBER"] = "VIP",
	["LEAD"] = "LEAD DANCE",
	["LEADDANCE"] = "LEAD DANCE",
	["LEAD TEAM"] = "LEAD DANCE",
}

local function normalizeFolderKey(name: string): string
	return string.upper((name:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")))
end

local function getConfig()
	local ok, cfg = pcall(function()
		return require(ReplicatedStorage.Shared.Constants.Config)
	end)
	if not ok or type(cfg) ~= "table" or type(cfg.RoleTools) ~= "table" then
		return nil
	end
	return cfg.RoleTools
end

local function collectExpectedFolderNames(): ({ string }, { [string]: boolean })
	local ok, RolesDomain = pcall(function()
		return require(ReplicatedStorage.Shared.Domain.RolesDomain)
	end)
	local ordered: { string }
	if ok and type(RolesDomain.buildStudioToolFolderList) == "function" then
		ordered = RolesDomain.buildStudioToolFolderList()
	else
		ordered = {
			"OWNER",
			"INVESTOR",
			"STAFF",
			"LEAD DANCE",
			"DJ",
			"STREAMER",
			"EXCLUSIVE",
			"ROYALE SPENDER",
			"TOP SPENDER",
			"VVIP",
			"VIP",
			"DONATUR",
		}
	end
	local seen = {} :: { [string]: boolean }
	for _, name in ipairs(ordered) do
		seen[name] = true
	end
	seen[ARCHIVE_FOLDER_NAME] = true
	return ordered, seen
end

local function resolveCanonicalRename(folderName: string): string?
	if RENAME_TO_CANONICAL[folderName] then
		return RENAME_TO_CANONICAL[folderName]
	end
	local upper = normalizeFolderKey(folderName)
	for legacy, target in pairs(RENAME_TO_CANONICAL) do
		if normalizeFolderKey(legacy) == upper then
			return target
		end
	end
	return nil
end

local function mergeFolderContents(source: Folder, target: Folder, dryRun: boolean): number
	local moved = 0
	for _, child in ipairs(source:GetChildren()) do
		if dryRun then
			moved += 1
		else
			child.Parent = target
			moved += 1
		end
	end
	return moved
end

local function ensureFolder(parent: Folder, name: string, dryRun: boolean): (Folder?, boolean)
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing :: Folder, false
	end
	if existing then
		emit(("  [SKIP] %s exists but is %s"):format(name, existing.ClassName))
		return nil, false
	end
	if dryRun then
		emit(("  [DRY CREATE] %s"):format(name))
		return nil, true
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder, true
end

local function ensureArchiveRoot(toolsRoot: Folder, dryRun: boolean): Folder?
	local existing = toolsRoot:FindFirstChild(ARCHIVE_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing :: Folder
	end
	if dryRun then
		emit(("  [DRY CREATE] %s"):format(ARCHIVE_FOLDER_NAME))
		return nil
	end
	local archive = Instance.new("Folder")
	archive.Name = ARCHIVE_FOLDER_NAME
	archive.Parent = toolsRoot
	return archive
end

local function ensurePlaceholderTool(folder: Folder, dryRun: boolean): boolean
	if not CREATE_PLACEHOLDER_TOOLS then
		return false
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Tool") then
			return false
		end
	end
	if dryRun then
		return true
	end
	local tool = Instance.new("Tool")
	tool.Name = PLACEHOLDER_TOOL_NAME
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.ToolTip = "Placeholder — ganti dengan Tool asli"
	tool:SetAttribute("KitRoleTool", true)
	tool:SetAttribute("KitRoleToolSource", folder.Name)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.2)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	tool.Parent = folder
	return true
end

local function renameOrMergeFolder(toolsRoot: Folder, child: Folder, targetName: string, dryRun: boolean): string
	local target = toolsRoot:FindFirstChild(targetName)
	if target and target:IsA("Folder") and target ~= child then
		local n = mergeFolderContents(child, target :: Folder, dryRun)
		if dryRun then
			emit(("  [DRY MERGE] %s → %s (%d children)"):format(child.Name, targetName, n))
			return "merged"
		end
		child:Destroy()
		emit(("  [MERGE] %s → %s (%d children)"):format(child.Name, targetName, n))
		return "merged"
	end
	if dryRun then
		emit(("  [DRY RENAME] %s → %s"):format(child.Name, targetName))
		return "renamed"
	end
	child.Name = targetName
	emit(("  [RENAME] → %s"):format(targetName))
	return "renamed"
end

-- ─── Main ───────────────────────────────────────────────────

emit("=== UpdateRoleToolFolders ===")
emit(("DRY_RUN = %s | ARCHIVE_OBSOLETE = %s"):format(tostring(DRY_RUN), tostring(ARCHIVE_OBSOLETE)))

local cfg = getConfig()
if not cfg then
	emit("[ERROR] Config.RoleTools tidak bisa di-require. Sync Rojo dulu.")
	return
end

local rootName = tostring(cfg.ROOT_FOLDER or "Tools")
local toolsRoot = ServerStorage:FindFirstChild(rootName)
if not toolsRoot then
	if DRY_RUN then
		emit(("[DRY] ServerStorage.%s belum ada — akan dibuat saat DRY_RUN=false"):format(rootName))
	else
		toolsRoot = Instance.new("Folder")
		toolsRoot.Name = rootName
		toolsRoot.Parent = ServerStorage
		emit(("[CREATE] ServerStorage.%s"):format(rootName))
	end
elseif not toolsRoot:IsA("Folder") then
	emit(("[ERROR] ServerStorage.%s class=%s (harus Folder)"):format(rootName, toolsRoot.ClassName))
	return
else
	emit(("[OK] ServerStorage.%s"):format(rootName))
end

if not toolsRoot or not toolsRoot:IsA("Folder") then
	if DRY_RUN then
		toolsRoot = nil
	else
		return
	end
end

local expectedList, expectedSet = collectExpectedFolderNames()
emit("Target: satu folder per role (+ DONATUR untuk donasi umum):")
expectedSet[ARCHIVE_FOLDER_NAME] = true
emit(("Expected folders from config: %d"):format(#expectedList))
for _, name in ipairs(expectedList) do
	emit(("  • %s"):format(name))
end

local stats = {
	renamed = 0,
	merged = 0,
	created = 0,
	archived = 0,
	placeholders = 0,
	skipped = 0,
}

if toolsRoot then
	-- Pass 1: rename / merge legacy names
	for _, child in ipairs(toolsRoot:GetChildren()) do
		if not child:IsA("Folder") or child.Name == ARCHIVE_FOLDER_NAME then
			continue
		end
		local targetName = resolveCanonicalRename(child.Name)
		if targetName and targetName ~= child.Name then
			local action = renameOrMergeFolder(toolsRoot, child :: Folder, targetName, DRY_RUN)
			if action == "renamed" then
				stats.renamed += 1
			elseif action == "merged" then
				stats.merged += 1
			end
		end
	end

	-- Pass 2: ensure canonical folders exist
	for _, folderName in ipairs(expectedList) do
		if DRY_RUN then
			local exists = toolsRoot:FindFirstChild(folderName)
			if exists and exists:IsA("Folder") then
				emit(("  [OK] %s"):format(folderName))
			else
				emit(("  [DRY CREATE] %s"):format(folderName))
				stats.created += 1
			end
		else
			local folder, wasCreated = ensureFolder(toolsRoot, folderName, false)
			if wasCreated then
				stats.created += 1
				emit(("  [CREATE] %s"):format(folderName))
			else
				emit(("  [OK] %s"):format(folderName))
			end
			if folder and ensurePlaceholderTool(folder, DRY_RUN) then
				stats.placeholders += 1
			end
		end
	end

	-- Pass 3: archive obsolete folders
	if ARCHIVE_OBSOLETE then
		local archiveRoot = ensureArchiveRoot(toolsRoot, DRY_RUN)
		for _, child in ipairs(toolsRoot:GetChildren()) do
			if not child:IsA("Folder") then
				continue
			end
			if child.Name == ARCHIVE_FOLDER_NAME or expectedSet[child.Name] then
				continue
			end
			if DRY_RUN then
				emit(("  [DRY ARCHIVE] %s"):format(child.Name))
				stats.archived += 1
			elseif archiveRoot then
				child.Parent = archiveRoot
				emit(("  [ARCHIVE] %s"):format(child.Name))
				stats.archived += 1
			end
		end
	end
end

emit("")
emit("--- Summary ---")
emit(("Renamed: %d | Merged: %d | Created: %d | Archived: %d | Placeholders: %d"):format(
	stats.renamed,
	stats.merged,
	stats.created,
	stats.archived,
	stats.placeholders
))
if DRY_RUN then
	emit("DRY_RUN aktif — tidak ada perubahan. Set DRY_RUN = false lalu jalankan lagi.")
else
	emit("Selesai. Isi folder dengan Tool (bukan Model). Cek Tools/_Archive sebelum hapus permanen.")
end
