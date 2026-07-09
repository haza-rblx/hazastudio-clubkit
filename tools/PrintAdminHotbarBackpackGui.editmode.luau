--!nocheck
-- ============================================================
-- PRINT GUI TREE: AdminPanel + Hotbar + Backpack (StarterGui) → leaf
-- ============================================================
-- Dump hierarki lengkap 3 ScreenGui ke Output Studio.
--
-- Targets:
--   StarterGui.04-AdminPanel
--   StarterGui.10-HotbarGUI
--   StarterGui.14-BackpackGUI
--
-- CARA PAKAI:
-- 1. Buka place NUWA di Studio (Edit Mode cukup, tidak perlu Play).
-- 2. Copy seluruh file ini → paste ke Command Bar → Enter.
-- 3. Salin output dari jendela Output.
--
-- Read-only — tidak mengubah instance apa pun.
-- ============================================================

local StarterGui = game:GetService("StarterGui")

local GUI_NAMES = {
	"04-AdminPanel",
	"10-HotbarGUI",
	"14-BackpackGUI",
}

local MAX_DEPTH = 0 -- 0 = unlimited (sampai leaf)
local SHOW_PROPERTIES = true
local SHOW_LEAF_PATHS = true

local LOG: { string } = {}

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
	local limit = max or 80
	s = s:gsub("[\r\n]+", " ")
	if #s > limit then
		s = s:sub(1, limit - 1) .. "…"
	end
	return s
end

local function fmtUDim2(value: any): string
	if typeof(value) ~= "UDim2" then
		return short(value)
	end
	return string.format(
		"{x={s=%s,o=%s},y={s=%s,o=%s}}",
		short(value.X.Scale, 12),
		short(value.X.Offset, 12),
		short(value.Y.Scale, 12),
		short(value.Y.Offset, 12)
	)
end

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

	if inst:IsA("ScreenGui") then
		add("Enabled", safeGet(inst, "Enabled"))
		add("DisplayOrder", safeGet(inst, "DisplayOrder"))
		add("IgnoreGuiInset", safeGet(inst, "IgnoreGuiInset"))
		add("ResetOnSpawn", safeGet(inst, "ResetOnSpawn"))
		add("ZIndexBehavior", safeGet(inst, "ZIndexBehavior"))
	end

	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		add("Text", string.format("%q", tostring(safeGet(inst, "Text") or "")))
		add("TextSize", safeGet(inst, "TextSize"))
		add("TextScaled", safeGet(inst, "TextScaled"))
	end

	if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		add("Image", safeGet(inst, "Image"))
		add("ScaleType", safeGet(inst, "ScaleType"))
	end

	if inst:IsA("GuiObject") then
		add("Visible", safeGet(inst, "Visible"))
		add("Active", safeGet(inst, "Active"))
		add("LayoutOrder", (safeGet(inst, "LayoutOrder") ~= 0) and safeGet(inst, "LayoutOrder") or nil)
		add("ZIndex", (safeGet(inst, "ZIndex") ~= 1) and safeGet(inst, "ZIndex") or nil)
		add("Size", fmtUDim2(safeGet(inst, "Size")))
		add("Position", fmtUDim2(safeGet(inst, "Position")))
		if inst:IsA("GuiBase2d") then
			add("AbsSize", safeGet(inst, "AbsoluteSize"))
			add("AbsPos", safeGet(inst, "AbsolutePosition"))
		end
	end

	if inst:IsA("UIListLayout") then
		add("FillDirection", safeGet(inst, "FillDirection"))
		add("Padding", safeGet(inst, "Padding"))
		add("SortOrder", safeGet(inst, "SortOrder"))
	elseif inst:IsA("UIGridLayout") then
		add("CellSize", fmtUDim2(safeGet(inst, "CellSize")))
		add("CellPadding", fmtUDim2(safeGet(inst, "CellPadding")))
	elseif inst:IsA("UIPadding") then
		add("PaddingTop", safeGet(inst, "PaddingTop"))
		add("PaddingBottom", safeGet(inst, "PaddingBottom"))
	elseif inst:IsA("UIScale") then
		add("Scale", safeGet(inst, "Scale"))
	elseif inst:IsA("UICorner") then
		add("CornerRadius", safeGet(inst, "CornerRadius"))
	elseif inst:IsA("ScrollingFrame") then
		add("ScrollingEnabled", safeGet(inst, "ScrollingEnabled"))
		add("CanvasSize", fmtUDim2(safeGet(inst, "CanvasSize")))
	elseif inst:IsA("UIStroke") then
		add("Thickness", safeGet(inst, "Thickness"))
		add("Transparency", safeGet(inst, "Transparency"))
	end

	local attrs = inst:GetAttributes()
	local attrKeys: { string } = {}
	for key in pairs(attrs) do
		table.insert(attrKeys, key)
	end
	table.sort(attrKeys)
	for _, key in ipairs(attrKeys) do
		add("attr." .. key, attrs[key])
	end

	if #parts == 0 then
		return ""
	end
	return "  { " .. table.concat(parts, ", ") .. " }"
end

local function sortChildren(children: { Instance }): { Instance }
	table.sort(children, function(a, b)
		local la = (a:IsA("GuiObject") and (a :: GuiObject).LayoutOrder) or 0
		local lb = (b:IsA("GuiObject") and (b :: GuiObject).LayoutOrder) or 0
		if la ~= lb then
			return la < lb
		end
		if a.ClassName ~= b.ClassName then
			return a.ClassName < b.ClassName
		end
		return a.Name < b.Name
	end)
	return children
end

local function walk(inst: Instance, depth: number, prefix: string, isLast: boolean, stats: { nodes: number, leaves: number, maxDepth: number }, leafPaths: { string })
	stats.nodes += 1
	if depth > stats.maxDepth then
		stats.maxDepth = depth
	end

	local children = inst:GetChildren()
	local isLeaf = #children == 0
	if isLeaf then
		stats.leaves += 1
		table.insert(leafPaths, inst:GetFullName())
	end

	local connector = if depth == 0 then "" elseif isLast then "└─ " else "├─ "
	local leafTag = if isLeaf then " [leaf]" else ""
	emit(string.format(
		"%s%s[%s] %s%s%s",
		prefix,
		connector,
		inst.ClassName,
		inst.Name,
		describeProps(inst),
		leafTag
	))

	if MAX_DEPTH > 0 and depth >= MAX_DEPTH then
		return
	end

	children = sortChildren(children)

	local childPrefix
	if depth == 0 then
		childPrefix = ""
	elseif isLast then
		childPrefix = prefix .. "   "
	else
		childPrefix = prefix .. "│  "
	end

	for i, child in ipairs(children) do
		walk(child, depth + 1, childPrefix, i == #children, stats, leafPaths)
	end
end

local function dumpGui(guiName: string): boolean
	local target = StarterGui:FindFirstChild(guiName)
	if not target then
		warn(string.format("[PrintAdminHotbarBackpackGui] '%s' tidak ditemukan di StarterGui.", guiName))
		return false
	end

	local stats = { nodes = 0, leaves = 0, maxDepth = 0 }
	local leafPaths: { string } = {}

	emit("")
	emit("============================================================")
	emit(string.format("GUI TREE: %s", target:GetFullName()))
	emit(string.format("Root: %s | depth=%s", target.ClassName, MAX_DEPTH == 0 and "unlimited" or tostring(MAX_DEPTH)))
	emit("============================================================")

	walk(target, 0, "", true, stats, leafPaths)

	emit("------------------------------------------------------------")
	emit(string.format("Stats [%s]: nodes=%d | leaves=%d | maxDepth=%d", guiName, stats.nodes, stats.leaves, stats.maxDepth))
	emit("------------------------------------------------------------")

	if SHOW_LEAF_PATHS then
		emit("")
		emit(string.format("LEAF PATHS — %s (%d):", guiName, #leafPaths))
		emit("------------------------------------------------------------")
		for _, path in ipairs(leafPaths) do
			emit(path)
		end
		emit("------------------------------------------------------------")
	end

	return true
end

-- ============================================================
-- MAIN
-- ============================================================

emit("============================================================")
emit("STARTERGUI DUMP: AdminPanel + HotbarGUI + BackpackGUI")
emit(string.format("Targets: %s", table.concat(GUI_NAMES, ", ")))
emit("============================================================")

local found = 0
for _, guiName in ipairs(GUI_NAMES) do
	if dumpGui(guiName) then
		found += 1
	end
end

emit("")
emit("============================================================")
emit(string.format("Done. Found %d / %d ScreenGui.", found, #GUI_NAMES))
emit("============================================================")
emit("END DUMP")

print(table.concat(LOG, "\n"))
