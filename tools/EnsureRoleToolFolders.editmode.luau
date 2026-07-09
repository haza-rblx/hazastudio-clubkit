--!nocheck
-- ============================================================
-- Ensure Role Tool folders in ServerStorage (Edit Mode)
-- ============================================================
-- Membuat struktur folder `ServerStorage.Tools` — SATU folder per role (nama = chatTag).
-- Opsional: placeholder Tool per folder kosong (untuk uji hotbar).
--
-- CARA PAKAI:
-- 1. Buka place NUWA di Studio (Edit Mode).
-- 2. Pastikan ReplicatedStorage sudah sync (Rojo).
-- 3. Copy seluruh file → Command Bar → Enter.
-- 4. Cek Output.
--
-- Set CREATE_PLACEHOLDER_TOOLS = false jika hanya mau folder kosong.
--
-- Migrasi dari nama folder lama + archive obsolete:
--   tools/UpdateRoleToolFolders.editmode.luau
-- ============================================================

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CREATE_PLACEHOLDER_TOOLS = true
local PLACEHOLDER_TOOL_NAME = "_RoleToolPlaceholder"

local LOG: { string } = {}

local function emit(line: string)
	table.insert(LOG, line)
	print(line)
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

local function collectFolderNames(): { string }
	local ok, RolesDomain = pcall(function()
		return require(ReplicatedStorage.Shared.Domain.RolesDomain)
	end)
	if ok and type(RolesDomain.buildStudioToolFolderList) == "function" then
		return RolesDomain.buildStudioToolFolderList()
	end
	-- Fallback kalau RolesDomain belum sync
	return {
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

local function ensureFolder(parent: Instance, name: string): (Folder, boolean)
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing :: Folder, false
	end
	if existing then
		emit(("  [SKIP] %s exists but is %s (not Folder)"):format(name, existing.ClassName))
		return existing :: Folder, false
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder, true
end

local function ensurePlaceholderTool(folder: Folder): boolean
	if not CREATE_PLACEHOLDER_TOOLS then
		return false
	end

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Tool") then
			return false
		end
	end

	local tool = Instance.new("Tool")
	tool.Name = PLACEHOLDER_TOOL_NAME
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.ToolTip = "Placeholder — ganti dengan Tool asli di Studio"
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

-- ─── Main ───────────────────────────────────────────────────

emit("=== EnsureRoleToolFolders ===")
emit(("CREATE_PLACEHOLDER_TOOLS = %s"):format(tostring(CREATE_PLACEHOLDER_TOOLS)))

local cfg = getConfig()
if not cfg then
	emit("[ERROR] Config.RoleTools tidak bisa di-require. Sync Rojo / cek ReplicatedStorage.Shared.Constants.Config")
	return
end

local rootName = tostring(cfg.ROOT_FOLDER or "Tools")
local toolsRoot = ServerStorage:FindFirstChild(rootName)
local createdRoot = false
if not toolsRoot then
	toolsRoot = Instance.new("Folder")
	toolsRoot.Name = rootName
	toolsRoot.Parent = ServerStorage
	createdRoot = true
	emit(("[CREATE] ServerStorage.%s"):format(rootName))
elseif not toolsRoot:IsA("Folder") then
	emit(("[ERROR] ServerStorage.%s ada tapi class=%s"):format(rootName, toolsRoot.ClassName))
	return
else
	emit(("[OK] ServerStorage.%s"):format(rootName))
end

local folderNames = collectFolderNames()
emit("Satu folder per role (nama = chat tag di game):")
emit(("Folders from config: %d"):format(#folderNames))

local createdFolders = 0
local existingFolders = 0
local createdPlaceholders = 0

for _, folderName in ipairs(folderNames) do
	local folder, wasCreated = ensureFolder(toolsRoot :: Folder, folderName)
	if wasCreated then
		createdFolders += 1
		emit(("  [CREATE] %s.%s"):format(rootName, folderName))
	else
		existingFolders += 1
		emit(("  [OK] %s.%s"):format(rootName, folderName))
	end

	if ensurePlaceholderTool(folder) then
		createdPlaceholders += 1
		emit(("  [PLACEHOLDER] %s/%s"):format(folderName, PLACEHOLDER_TOOL_NAME))
	end
end

emit("")
emit("--- Membership mapping (RoleTools) ---")
if type(cfg.FOLDERS_BY_MEMBERSHIP) == "table" then
	for tier, list in pairs(cfg.FOLDERS_BY_MEMBERSHIP) do
		emit(("  %s → %s"):format(tostring(tier), type(list) == "table" and table.concat(list, ", ") or "?"))
	end
end

emit("")
emit("--- Summary ---")
emit(("Root created: %s"):format(tostring(createdRoot)))
emit(("Folders created: %d | already existed: %d"):format(createdFolders, existingFolders))
emit(("Placeholder tools added: %d"):format(createdPlaceholders))
emit("Selesai. Isi tiap folder dengan Tool (bukan Model); hapus _RoleToolPlaceholder jika tidak perlu.")
emit("Untuk rename folder legacy + archive yang tidak dipakai → jalankan UpdateRoleToolFolders.editmode.luau")
