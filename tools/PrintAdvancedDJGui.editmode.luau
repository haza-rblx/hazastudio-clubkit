--!nocheck
-- ============================================================
-- PRINT ADVANCED DJ GUI — dump hierarchy sampai leaf (detail)
-- ============================================================
-- Utility Command Bar (Edit Mode, read-only) untuk dokumentasi /
-- validasi struktur GUI Advanced DJ.
--
-- CARA PAKAI:
-- 1. Paste SELURUH file ini ke Studio Command Bar (Edit Mode).
-- 2. Enter, lalu copy output dari Output window.
--
-- Output:
--   - Tree ASCII lengkap (ClassName + properti penting) sampai leaf
--   - Daftar leaf path (relatif ke node target)
--   - Stats total node / leaf / depth
-- ============================================================

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

-- ============================================================
-- CONFIG
-- ============================================================

local TARGET_NAME = "100-AdvancedDJ"

-- 0 = unlimited (sampai leaf)
local MAX_DEPTH = 0
local SHOW_PROPERTIES = true
local MAX_TREE_LINES = 4000
local PRINT_LEAF_PATHS = true
local LEAF_PATH_LIMIT = 0
local COLLAPSE_REPEATED_SIBLINGS = true
local REPEAT_SIBLING_THRESHOLD = 12
local REPEAT_SIBLING_PREVIEW = 3

-- Cari di root-root ini (urutan prioritas).
local SEARCH_ROOTS: { Instance } = {
	StarterGui,
	StarterPlayer,
	ReplicatedStorage,
	ServerStorage,
	Workspace,
}

-- Kalau Play test & node hanya ada di PlayerGui, set true.
local INCLUDE_PLAYER_GUI = true

-- ============================================================
-- HELPERS
-- ============================================================

local LOG: { string } = {}
local LEAF_PATHS: { string } = {}
local STATS = {
	nodes = 0,
	leaves = 0,
	maxDepth = 0,
	treeLines = 0,
	treeLinesSkipped = 0,
	repeatedGroupsCollapsed = 0,
}

local function emit(line: string)
	table.insert(LOG, line)
end

local function emitTree(line: string)
	if MAX_TREE_LINES > 0 and STATS.treeLines >= MAX_TREE_LINES then
		STATS.treeLinesSkipped += 1
		return
	end
	STATS.treeLines += 1
	emit(line)
end

local function safeGet(inst: Instance, prop: string): any
	local ok, value = pcall(function()
		return (inst :: any)[prop]
	end)
	if ok then
		return value
	end
	return nil
end

local function shorten(value: any, maxLen: number?): string
	local text = tostring(value)
	local limit = maxLen or 70
	text = text:gsub("[\r\n]+", " ")
	if #text > limit then
		text = text:sub(1, limit - 1) .. "…"
	end
	return text
end

local function relativePath(root: Instance, inst: Instance): string
	if inst == root then
		return root.Name
	end

	local parts: { string } = {}
	local current: Instance? = inst
	while current and current ~= root do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end

	if current ~= root then
		return inst:GetFullName()
	end

	return table.concat(parts, ".")
end

local function describeProps(inst: Instance): string
	if not SHOW_PROPERTIES then
		return ""
	end

	local out: { string } = {}
	local function add(label: string, value: any, skipIfNil: boolean?)
		if value == nil and (skipIfNil == nil or skipIfNil) then
			return
		end
		table.insert(out, string.format("%s=%s", label, shorten(value)))
	end

	if inst:IsA("GuiObject") then
		add("Visible", safeGet(inst, "Visible"))
		add("Active", safeGet(inst, "Active"))
		add("Size", safeGet(inst, "Size"))
		add("Position", safeGet(inst, "Position"))
		add("AnchorPoint", safeGet(inst, "AnchorPoint"))
		add("ZIndex", safeGet(inst, "ZIndex"))
		add("LayoutOrder", safeGet(inst, "LayoutOrder"))
		add("BackgroundTransparency", safeGet(inst, "BackgroundTransparency"))
	end

	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		add("Text", string.format("%q", tostring(safeGet(inst, "Text") or "")))
		add("PlaceholderText", string.format("%q", tostring(safeGet(inst, "PlaceholderText") or "")))
		add("Font", safeGet(inst, "Font"))
		add("TextSize", safeGet(inst, "TextSize"))
		add("TextScaled", safeGet(inst, "TextScaled"))
		add("TextColor3", safeGet(inst, "TextColor3"))
	end

	if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		add("Image", safeGet(inst, "Image"))
		add("ScaleType", safeGet(inst, "ScaleType"))
		add("ImageColor3", safeGet(inst, "ImageColor3"))
		add("ImageTransparency", safeGet(inst, "ImageTransparency"))
	end

	if inst:IsA("ScrollingFrame") then
		add("CanvasSize", safeGet(inst, "CanvasSize"))
		add("AutomaticCanvasSize", safeGet(inst, "AutomaticCanvasSize"))
		add("ScrollBarImageTransparency", safeGet(inst, "ScrollBarImageTransparency"))
	end

	if inst:IsA("UIListLayout") then
		add("FillDirection", safeGet(inst, "FillDirection"))
		add("Padding", safeGet(inst, "Padding"))
		add("HorizontalAlignment", safeGet(inst, "HorizontalAlignment"))
		add("VerticalAlignment", safeGet(inst, "VerticalAlignment"))
		add("SortOrder", safeGet(inst, "SortOrder"))
	elseif inst:IsA("UIGridLayout") then
		add("CellSize", safeGet(inst, "CellSize"))
		add("CellPadding", safeGet(inst, "CellPadding"))
		add("FillDirectionMaxCells", safeGet(inst, "FillDirectionMaxCells"))
	elseif inst:IsA("UIPadding") then
		add("PaddingLeft", safeGet(inst, "PaddingLeft"))
		add("PaddingRight", safeGet(inst, "PaddingRight"))
		add("PaddingTop", safeGet(inst, "PaddingTop"))
		add("PaddingBottom", safeGet(inst, "PaddingBottom"))
	elseif inst:IsA("UIScale") then
		add("Scale", safeGet(inst, "Scale"))
	elseif inst:IsA("UICorner") then
		add("CornerRadius", safeGet(inst, "CornerRadius"))
	elseif inst:IsA("UIAspectRatioConstraint") then
		add("AspectRatio", safeGet(inst, "AspectRatio"))
	elseif inst:IsA("UIStroke") then
		add("Thickness", safeGet(inst, "Thickness"))
		add("Transparency", safeGet(inst, "Transparency"))
		add("Color", safeGet(inst, "Color"))
	end

	if #out == 0 then
		return ""
	end
	return "  { " .. table.concat(out, ", ") .. " }"
end

local function findTarget(): (Instance?, string?)
	for _, root in ipairs(SEARCH_ROOTS) do
		local found = root:FindFirstChild(TARGET_NAME, true)
		if found then
			return found, root:GetFullName()
		end
	end

	if INCLUDE_PLAYER_GUI then
		local localPlayer = Players.LocalPlayer
		if localPlayer then
			local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
			if playerGui then
				local found = playerGui:FindFirstChild(TARGET_NAME, true)
				if found then
					return found, playerGui:GetFullName()
				end
			end
		end
	end

	return nil, nil
end

local function sortChildren(children: { Instance })
	table.sort(children, function(a, b)
		local la = (a:IsA("GuiObject") and a.LayoutOrder) or 0
		local lb = (b:IsA("GuiObject") and b.LayoutOrder) or 0
		if la ~= lb then
			return la < lb
		end
		return a.Name < b.Name
	end)
end

local function walk(root: Instance, inst: Instance, depth: number, prefix: string, isLast: boolean)
	STATS.nodes += 1
	if depth > STATS.maxDepth then
		STATS.maxDepth = depth
	end

	local children = inst:GetChildren()
	local isLeaf = #children == 0
	if isLeaf then
		STATS.leaves += 1
		table.insert(LEAF_PATHS, relativePath(root, inst))
	end

	local connector = if depth == 0 then "" elseif isLast then "└─ " else "├─ "
	emitTree(string.format(
		"%s%s[%s] %s%s",
		prefix,
		connector,
		inst.ClassName,
		inst.Name,
		describeProps(inst)
	))

	if MAX_DEPTH > 0 and depth >= MAX_DEPTH then
		return
	end

	sortChildren(children)
	local childPrefix
	if depth == 0 then
		childPrefix = ""
	elseif isLast then
		childPrefix = prefix .. "   "
	else
		childPrefix = prefix .. "│  "
	end

	local i = 1
	while i <= #children do
		local child = children[i]
		local j = i + 1
		while j <= #children do
			local nextChild = children[j]
			if nextChild.Name ~= child.Name or nextChild.ClassName ~= child.ClassName then
				break
			end
			j += 1
		end

		local runCount = j - i
		local shouldCollapse = COLLAPSE_REPEATED_SIBLINGS and runCount >= REPEAT_SIBLING_THRESHOLD
		if shouldCollapse then
			STATS.repeatedGroupsCollapsed += 1
			local previewCount = math.min(REPEAT_SIBLING_PREVIEW, runCount)
			for idx = 0, previewCount - 1 do
				local current = children[i + idx]
				local lastFromPreview = (i + idx == #children) or (idx == previewCount - 1)
				walk(root, current, depth + 1, childPrefix, lastFromPreview and (previewCount == runCount))
			end
			emitTree(string.format(
				"%s%s… (%d sibling '%s' [%s] disingkat, tampil %d pertama)",
				childPrefix,
				(j - 1 == #children) and "└─ " or "├─ ",
				runCount,
				child.Name,
				child.ClassName,
				previewCount
			))
			for idx = previewCount, runCount - 1 do
				local current = children[i + idx]
				STATS.nodes += 1
				local grandChildren = current:GetChildren()
				local isLeaf = #grandChildren == 0
				if isLeaf then
					STATS.leaves += 1
					table.insert(LEAF_PATHS, relativePath(root, current))
				end
			end
		else
			for idx = i, j - 1 do
				walk(root, children[idx], depth + 1, childPrefix, idx == #children)
			end
		end

		i = j
	end
end

-- ============================================================
-- MAIN
-- ============================================================

local target, foundIn = findTarget()
if not target then
	warn(string.format(
		"[PrintAdvancedDJGui] Node '%s' tidak ketemu. Cek StarterGui / PlayerGui.",
		TARGET_NAME
	))
	return
end

emit("============================================================")
emit(string.format("ADVANCED DJ GUI DUMP: %s", target:GetFullName()))
emit(string.format("Ditemukan dari root: %s", foundIn or "?"))
emit(string.format(
	"Target ClassName: %s | MAX_DEPTH=%s",
	target.ClassName,
	(MAX_DEPTH == 0 and "unlimited (leaf)" or tostring(MAX_DEPTH))
))
emit("============================================================")
emit("")

walk(target, target, 0, "", true)

emit("")
emit("============================================================")
emit(string.format(
	"Stats: %d nodes | %d leaves | max depth %d | tree lines %d",
	STATS.nodes,
	STATS.leaves,
	STATS.maxDepth,
	STATS.treeLines
))
if STATS.treeLinesSkipped > 0 then
	emit(string.format(
		"Tree output dipotong: %d line tidak ditampilkan (MAX_TREE_LINES=%d).",
		STATS.treeLinesSkipped,
		MAX_TREE_LINES
	))
end
if STATS.repeatedGroupsCollapsed > 0 then
	emit(string.format(
		"Repeated sibling group disingkat: %d group (threshold=%d).",
		STATS.repeatedGroupsCollapsed,
		REPEAT_SIBLING_THRESHOLD
	))
end
emit("============================================================")
emit("")

if PRINT_LEAF_PATHS then
	emit("--- LEAF PATHS (relatif ke 100-AdvancedDJ) ---")
	table.sort(LEAF_PATHS)
	local limit = if LEAF_PATH_LIMIT > 0 then math.min(LEAF_PATH_LIMIT, #LEAF_PATHS) else #LEAF_PATHS
	for idx = 1, limit do
		emit("  " .. LEAF_PATHS[idx])
	end
	if LEAF_PATH_LIMIT > 0 and #LEAF_PATHS > LEAF_PATH_LIMIT then
		emit(string.format(
			"  ... (%d leaf path tidak ditampilkan; naikkan LEAF_PATH_LIMIT / set 0)",
			#LEAF_PATHS - LEAF_PATH_LIMIT
		))
	end
	emit("")
end

emit("--- IMMEDIATE CHILDREN (quick reference) ---")
local topChildren = target:GetChildren()
sortChildren(topChildren)
for _, child in ipairs(topChildren) do
	emit(string.format("  - %s (%s)", child.Name, child.ClassName))
end

emit("============================================================")
print(table.concat(LOG, "\n"))
warn("[PrintAdvancedDJGui] Done. Copy output untuk mapping/wiring detail.")
