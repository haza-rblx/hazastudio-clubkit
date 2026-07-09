--!nocheck
-- ============================================================
-- PRINT GUI TREE: Music Player — DJ section → leaf (Play Mode)
-- ============================================================
-- Dump hierarki 6-DJTab (+ header 3-DJTab) dari PlayerGui saat Play.
--
-- CARA PAKAI:
-- 1. Play di Studio (client/local).
-- 2. Buka music panel kalau perlu supaya GUI di-clone ke PlayerGui.
-- 3. Copy seluruh file ini → paste ke Command Bar → Enter.
-- 4. Salin output dari jendela Output.
--
-- Snapshot referensi (client Play): _non_rojo/docs/music-player/MUSIC_PLAYER_DJ_GUI_CLIENT_PLAYMODE_DUMP.md
--
-- Read-only — tidak mengubah instance apa pun.
-- ============================================================

local Players = game:GetService("Players")

local ROOT_NAMES = { "06-MusicPlayerGUI", "MusicPlayerGUI", "MusicPlayer" }
local MAIN_WRAPPER_NAMES = { "MainWrapper", "Main" }
local DJ_TAB_CONTENT_NAMES = { "6-DJTab" }
local DJ_TAB_HEADER_NAMES = { "3-DJTab" }
local SELECTOR_NAMES = { "Selector", "01-HeaderWrapper", "HeaderWrapper" }

local MAX_DEPTH = 0 -- 0 = unlimited (sampai leaf)
local SHOW_PROPERTIES = true
local SHOW_LEAF_PATHS = true
local DUMP_HEADER_DJ_TAB = true

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
	end

	if inst:IsA("UIListLayout") then
		add("FillDirection", safeGet(inst, "FillDirection"))
		add("Padding", safeGet(inst, "Padding"))
		add("SortOrder", safeGet(inst, "SortOrder"))
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

local function walk(
	inst: Instance,
	depth: number,
	prefix: string,
	isLast: boolean,
	stats: { nodes: number, leaves: number, maxDepth: number },
	leafPaths: { string }
)
	stats.nodes += 1
	if depth > stats.maxDepth then
		stats.maxDepth = depth
	end

	local children = sortChildren(inst:GetChildren())
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

local function dumpRoot(label: string, target: Instance)
	local stats = { nodes = 0, leaves = 0, maxDepth = 0 }
	local leafPaths: { string } = {}

	emit("")
	emit("============================================================")
	emit(string.format("GUI TREE: %s", label))
	emit(string.format("Root: %s | depth=%s", target:GetFullName(), MAX_DEPTH == 0 and "unlimited" or tostring(MAX_DEPTH)))
	emit("============================================================")

	walk(target, 0, "", true, stats, leafPaths)

	emit("------------------------------------------------------------")
	emit(string.format("Stats [%s]: nodes=%d | leaves=%d | maxDepth=%d", label, stats.nodes, stats.leaves, stats.maxDepth))
	emit("------------------------------------------------------------")

	if SHOW_LEAF_PATHS then
		emit("")
		emit(string.format("LEAF PATHS — %s (%d):", label, #leafPaths))
		emit("------------------------------------------------------------")
		for _, path in ipairs(leafPaths) do
			emit(path)
		end
		emit("------------------------------------------------------------")
	end
end

local function findFirstByNames(parent: Instance?, names: { string }): Instance?
	if not parent then
		return nil
	end
	for _, name in ipairs(names) do
		local child = parent:FindFirstChild(name)
		if child then
			return child
		end
	end
	return nil
end

local function findMusicRoot(container: Instance): (Instance?, string?)
	for _, name in ipairs(ROOT_NAMES) do
		local child = container:FindFirstChild(name)
		if child then
			return child, name
		end
	end
	return nil, nil
end

local function resolveDjTargets(musicRoot: Instance): (Instance?, Instance?)
	local mainWrapper = findFirstByNames(musicRoot, MAIN_WRAPPER_NAMES)
	if not mainWrapper then
		return nil, nil
	end

	local djTab = findFirstByNames(mainWrapper, DJ_TAB_CONTENT_NAMES)
	local djHeader: Instance? = nil
	if DUMP_HEADER_DJ_TAB then
		local headerWrapper = findFirstByNames(mainWrapper, SELECTOR_NAMES)
		local selector = headerWrapper and findFirstByNames(headerWrapper, { "Selector" }) or headerWrapper
		if selector then
			djHeader = findFirstByNames(selector, DJ_TAB_HEADER_NAMES)
		end
		if not djHeader then
			djHeader = musicRoot:FindFirstChild("3-DJTab", true)
		end
	end

	return djTab, djHeader
end

-- ============================================================
-- MAIN (Play Mode — PlayerGui)
-- ============================================================

local player = Players.LocalPlayer
if not player then
	warn("[PrintMusicPlayerDjGui] LocalPlayer tidak ada — jalankan saat Play.")
	return
end

local playerGui = player:FindFirstChildOfClass("PlayerGui")
if not playerGui then
	warn("[PrintMusicPlayerDjGui] PlayerGui tidak ditemukan.")
	return
end

emit("============================================================")
emit("MUSIC PLAYER DJ DUMP (Play Mode)")
emit("Source: PlayerGui")
emit("============================================================")

local musicRoot, matchedRoot = findMusicRoot(playerGui)
if not musicRoot then
	warn("[PrintMusicPlayerDjGui] Root tidak ditemukan di PlayerGui. Coba: " .. table.concat(ROOT_NAMES, ", "))
	emit("")
	emit("PlayerGui children:")
	for _, child in ipairs(sortChildren(playerGui:GetChildren())) do
		emit(string.format("  [%s] %s", child.ClassName, child.Name))
	end
	print(table.concat(LOG, "\n"))
	return
end

emit(string.format("Matched root: %s (%s)", matchedRoot, musicRoot:GetFullName()))

local djTab, djHeader = resolveDjTargets(musicRoot)
if not djTab then
	warn("[PrintMusicPlayerDjGui] 6-DJTab tidak ditemukan di bawah MainWrapper.")
	emit("")
	emit("MainWrapper children:")
	local mainWrapper = findFirstByNames(musicRoot, MAIN_WRAPPER_NAMES)
	if mainWrapper then
		for _, child in ipairs(sortChildren(mainWrapper:GetChildren())) do
			local vis = if child:IsA("GuiObject") then string.format(" Visible=%s", tostring((child :: GuiObject).Visible)) else ""
			emit(string.format("  [%s] %s%s", child.ClassName, child.Name, vis))
		end
	end
	print(table.concat(LOG, "\n"))
	return
end

if djHeader then
	emit("")
	emit("Header tab (konteks):")
	emit(string.format("  %s [%s] Visible=%s", djHeader:GetFullName(), djHeader.ClassName, tostring((djHeader :: GuiObject).Visible)))
	dumpRoot("3-DJTab (header)", djHeader)
end

dumpRoot("6-DJTab (content)", djTab)

emit("")
emit("============================================================")
emit("END DUMP")
emit("============================================================")

print(table.concat(LOG, "\n"))
