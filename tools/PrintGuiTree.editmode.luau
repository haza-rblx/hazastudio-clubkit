--!nocheck
-- ============================================================
-- PRINT GUI TREE — dump full hierarchy sampai leaf
-- ============================================================
-- Nge-print struktur lengkap sebuah instance (GUI atau apapun) ke
-- Output, lengkap dengan ClassName + properti penting per node.
-- Berguna buat dokumentasi / debugging layout GUI.
--
-- CARA PAKAI:
-- 1. Set TARGET_PATH ke path instance yang mau di-dump (lihat contoh
--    di bawah). Default: cari "OverheadGUIMainTemplateV3" di Workspace.
-- 2. Paste full content ke Command Bar Studio (Edit Mode OK, gak perlu
--    Play) -> Enter. Atau drop ke ServerScriptService & run.
-- 3. Output muncul di Output window. Copy dari situ.
--
-- CATATAN:
-- - Read-only, gak ngubah apapun. Aman di Edit Mode.
-- - MAX_DEPTH = 0 artinya unlimited (sampai leaf).
-- ============================================================

local Workspace = game:GetService("Workspace")

-- ============================================================
-- CONFIG
-- ============================================================

-- Cara A: kasih nama, dicari di SEARCH_ROOT secara rekursif.
local TARGET_NAME = "OverheadGUIMainTemplateV3"
local SEARCH_ROOT: Instance = Workspace

-- Cara B (opsional): kalau mau target instance spesifik, isi langsung.
-- Kalau di-set (bukan nil), ini menang dari TARGET_NAME.
-- Contoh: local TARGET_INSTANCE = workspace.SomeFolder.MyGui
local TARGET_INSTANCE: Instance? = nil

-- 0 = unlimited (sampai leaf). >0 = batasi kedalaman.
local MAX_DEPTH = 0

-- Tampilkan properti detail per node (Text, Image, Size, dst).
local SHOW_PROPERTIES = true

-- ============================================================
-- HELPERS
-- ============================================================

local LOG = {}

local function emit(line: string)
	table.insert(LOG, line)
end

local function safeGet(inst: Instance, prop: string): any
	local ok, val = pcall(function()
		return (inst :: any)[prop]
	end)
	if ok then
		return val
	end
	return nil
end

local function short(v: any, max: number?): string
	local s = tostring(v)
	local limit = max or 60
	s = s:gsub("[\r\n]+", " ")
	if #s > limit then
		s = s:sub(1, limit - 1) .. "…"
	end
	return s
end

-- Kumpulin properti menarik berdasarkan ClassName.
local function describeProps(inst: Instance): string
	if not SHOW_PROPERTIES then
		return ""
	end

	local parts: { string } = {}
	local function add(label: string, value: any)
		if value == nil then
			return
		end
		table.insert(parts, string.format("%s=%s", label, short(value)))
	end

	-- Teks
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		add("Text", string.format("%q", tostring(safeGet(inst, "Text") or "")))
		add("Font", safeGet(inst, "Font"))
		local ts = safeGet(inst, "TextScaled")
		if ts == true then
			add("TextScaled", true)
		else
			add("TextSize", safeGet(inst, "TextSize"))
		end
		add("TextColor3", safeGet(inst, "TextColor3"))
	end

	-- Gambar
	if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		add("Image", safeGet(inst, "Image"))
		add("ScaleType", safeGet(inst, "ScaleType"))
		add("ImageColor3", safeGet(inst, "ImageColor3"))
	end

	-- Layout / posisi umum untuk GuiObject
	if inst:IsA("GuiObject") then
		add("Size", safeGet(inst, "Size"))
		add("Position", safeGet(inst, "Position"))
		local anchor = safeGet(inst, "AnchorPoint")
		if anchor and (anchor.X ~= 0 or anchor.Y ~= 0) then
			add("AnchorPoint", anchor)
		end
		local zindex = safeGet(inst, "ZIndex")
		if zindex and zindex ~= 1 then
			add("ZIndex", zindex)
		end
		local vis = safeGet(inst, "Visible")
		if vis == false then
			add("Visible", false)
		end
		local bgt = safeGet(inst, "BackgroundTransparency")
		if bgt ~= nil and bgt < 1 then
			add("BackgroundColor3", safeGet(inst, "BackgroundColor3"))
		end
		add("LayoutOrder", (safeGet(inst, "LayoutOrder") ~= 0) and safeGet(inst, "LayoutOrder") or nil)
	end

	-- UI constraints / layouts
	if inst:IsA("UIListLayout") then
		add("FillDirection", safeGet(inst, "FillDirection"))
		add("Padding", safeGet(inst, "Padding"))
		add("HorizontalAlignment", safeGet(inst, "HorizontalAlignment"))
		add("VerticalAlignment", safeGet(inst, "VerticalAlignment"))
		add("SortOrder", safeGet(inst, "SortOrder"))
	elseif inst:IsA("UIPadding") then
		add("Left", safeGet(inst, "PaddingLeft"))
		add("Right", safeGet(inst, "PaddingRight"))
		add("Top", safeGet(inst, "PaddingTop"))
		add("Bottom", safeGet(inst, "PaddingBottom"))
	elseif inst:IsA("UIScale") then
		add("Scale", safeGet(inst, "Scale"))
	elseif inst:IsA("UICorner") then
		add("CornerRadius", safeGet(inst, "CornerRadius"))
	elseif inst:IsA("UIGradient") then
		add("Rotation", safeGet(inst, "Rotation"))
	elseif inst:IsA("UIAspectRatioConstraint") then
		add("AspectRatio", safeGet(inst, "AspectRatio"))
	end

	if #parts == 0 then
		return ""
	end
	return "  { " .. table.concat(parts, ", ") .. " }"
end

local stats = { nodes = 0, maxDepth = 0 }

local function walk(inst: Instance, depth: number, prefix: string, isLast: boolean)
	stats.nodes += 1
	if depth > stats.maxDepth then
		stats.maxDepth = depth
	end

	local connector = if depth == 0 then "" elseif isLast then "└─ " else "├─ "
	local line = string.format(
		"%s%s[%s] %s%s",
		prefix,
		connector,
		inst.ClassName,
		inst.Name,
		describeProps(inst)
	)
	emit(line)

	if MAX_DEPTH > 0 and depth >= MAX_DEPTH then
		return
	end

	local children = inst:GetChildren()
	-- Urutkan biar output stabil: by LayoutOrder (kalau GuiObject) lalu Name.
	table.sort(children, function(a, b)
		local la = (a:IsA("GuiObject") and a.LayoutOrder) or 0
		local lb = (b:IsA("GuiObject") and b.LayoutOrder) or 0
		if la ~= lb then
			return la < lb
		end
		return a.Name < b.Name
	end)

	local childPrefix
	if depth == 0 then
		childPrefix = ""
	elseif isLast then
		childPrefix = prefix .. "   "
	else
		childPrefix = prefix .. "│  "
	end

	for i, child in ipairs(children) do
		walk(child, depth + 1, childPrefix, i == #children)
	end
end

-- ============================================================
-- MAIN
-- ============================================================

local target: Instance? = TARGET_INSTANCE
if not target then
	target = SEARCH_ROOT:FindFirstChild(TARGET_NAME, true)
end

if not target then
	warn(string.format("[PrintGuiTree] Target '%s' gak ketemu di %s.", TARGET_NAME, SEARCH_ROOT:GetFullName()))
	return
end

emit("============================================================")
emit(string.format("GUI TREE DUMP: %s", target:GetFullName()))
emit(string.format("Root ClassName: %s | MAX_DEPTH=%s", target.ClassName, (MAX_DEPTH == 0 and "unlimited" or tostring(MAX_DEPTH))))
emit("============================================================")

walk(target, 0, "", true)

emit("============================================================")
emit(string.format("Total nodes: %d | Max depth: %d", stats.nodes, stats.maxDepth))
emit("============================================================")

print(table.concat(LOG, "\n"))
