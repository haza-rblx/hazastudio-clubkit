--!nocheck
-- ============================================================
-- PRINT CINEMATIC DOCK GUI — dump hierarchy sampai leaf
-- ============================================================
-- Utility Command Bar (Edit Mode, read-only) untuk dokumentasi /
-- update binding CinematicDockController.
--
-- CARA PAKAI:
-- 1. Pastikan `12-CinematicDockGUI` ada di place (biasanya StarterGui
--    atau clone ke PlayerGui saat Play).
-- 2. Paste SELURUH file ini ke Command Bar Studio -> Enter.
-- 3. Copy output dari Output window.
--
-- Output:
--   - Tree ASCII (ClassName + properti penting) sampai leaf
--   - Daftar leaf path (relatif ke root GUI) buat wiring script
--   - Checklist node yang dipakai CinematicDockController saat ini
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

local GUI_NAME = "12-CinematicDockGUI"

-- 0 = unlimited (sampai leaf)
local MAX_DEPTH = 0

local SHOW_PROPERTIES = true

-- Cari di root-root ini (urutan prioritas). Edit kalau GUI kamu di tempat lain.
local SEARCH_ROOTS: { Instance } = {
	StarterGui,
	StarterPlayer,
	ReplicatedStorage,
	ServerStorage,
	Workspace,
}

-- Kalau Play test & GUI cuma di PlayerGui, set true.
local INCLUDE_PLAYER_GUI = true

-- Node yang CinematicDockController expect (untuk checklist di akhir output).
local EXPECTED_TOP_LEVEL: { { name: string, classHint: string?, optional: boolean? } } = {
	{ name = "CinematicDock", classHint = "Frame" },
	{ name = "OverlayTrigger", classHint = "ImageButton", optional = true },
	{ name = "01-MovementType", classHint = "CanvasGroup" },
	{ name = "02-TargetList", classHint = "CanvasGroup" },
	{ name = "CentralStartandStopButton", classHint = "TextButton" },
}

local EXPECTED_DEEP: { { path: string, note: string? } } = {
	{ path = "CinematicDock.SelectMovementWrapper.SelectMovementButton", note = "deep find by name OK" },
	{ path = "CinematicDock.SelectTargetWrapper.SelectTargetButton", note = "deep find by name OK" },
	{ path = "CinematicDock.SpeedChanger.Wrapper", note = "speed buttons 1-5 di dalam Wrapper" },
	{ path = "01-MovementType.01-MovementType.MainContent", note = "ScrollingFrame + filter tabs" },
	{ path = "02-TargetList.01-MovementType.MainContent", note = "ScrollingFrame + filter tabs" },
	{ path = "01-MovementType.01-MovementType.SearchMovement", note = "TextBox filter" },
	{ path = "02-TargetList.01-MovementType.SearchTarget", note = "TextBox filter" },
}

-- ============================================================
-- HELPERS
-- ============================================================

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
	local limit = max or 60
	s = s:gsub("[\r\n]+", " ")
	if #s > limit then
		s = s:sub(1, limit - 1) .. "…"
	end
	return s
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

	if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		add("Image", safeGet(inst, "Image"))
		add("ScaleType", safeGet(inst, "ScaleType"))
		add("ImageColor3", safeGet(inst, "ImageColor3"))
	end

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
	elseif inst:IsA("UIAspectRatioConstraint") then
		add("AspectRatio", safeGet(inst, "AspectRatio"))
	end

	if #parts == 0 then
		return ""
	end
	return "  { " .. table.concat(parts, ", ") .. " }"
end

local stats = { nodes = 0, maxDepth = 0, leaves = 0 }
local leafPaths: { string } = {}

local function relativePath(root: Instance, inst: Instance): string
	if inst == root then
		return root.Name
	end
	local segments: { string } = {}
	local current: Instance? = inst
	while current and current ~= root do
		table.insert(segments, 1, current.Name)
		current = current.Parent
	end
	if current ~= root then
		return inst:GetFullName()
	end
	return table.concat(segments, ".")
end

local function walk(inst: Instance, root: Instance, depth: number, prefix: string, isLast: boolean)
	stats.nodes += 1
	if depth > stats.maxDepth then
		stats.maxDepth = depth
	end

	local children = inst:GetChildren()
	local isLeaf = #children == 0
	if isLeaf then
		stats.leaves += 1
		table.insert(leafPaths, relativePath(root, inst))
	end

	local connector = if depth == 0 then "" elseif isLast then "└─ " else "├─ "
	emit(string.format(
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
		walk(child, root, depth + 1, childPrefix, i == #children)
	end
end

local function findGui(): (Instance?, string?)
	for _, searchRoot in ipairs(SEARCH_ROOTS) do
		local found = searchRoot:FindFirstChild(GUI_NAME, true)
		if found then
			return found, searchRoot:GetFullName()
		end
	end

	if INCLUDE_PLAYER_GUI then
		local localPlayer = Players.LocalPlayer
		if localPlayer then
			local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
			if playerGui then
				local found = playerGui:FindFirstChild(GUI_NAME, true)
				if found then
					return found, playerGui:GetFullName()
				end
			end
		end
	end

	return nil, nil
end

local function resolvePath(root: Instance, dotted: string): Instance?
	local current: Instance = root
	for segment in string.gmatch(dotted, "[^%.]+") do
		local nextInst = current:FindFirstChild(segment)
		if not nextInst then
			nextInst = current:FindFirstChild(segment, true)
		end
		if not nextInst then
			return nil
		end
		current = nextInst
	end
	return current
end

local function findByNameDeep(root: Instance, name: string): Instance?
	return root:FindFirstChild(name, true)
end

-- ============================================================
-- MAIN
-- ============================================================

local target, foundUnder = findGui()
if not target then
	warn(string.format("[PrintCinematicDockGui] '%s' tidak ketemu. Cek StarterGui / PlayerGui.", GUI_NAME))
	return
end

emit("============================================================")
emit(string.format("CINEMATIC DOCK GUI DUMP: %s", target:GetFullName()))
emit(string.format("Ditemukan di bawah: %s", foundUnder or "?"))
emit(string.format("Root ClassName: %s | MAX_DEPTH=%s", target.ClassName, (MAX_DEPTH == 0 and "unlimited (leaf)" or tostring(MAX_DEPTH))))
emit("============================================================")
emit("")

walk(target, target, 0, "", true)

emit("")
emit("============================================================")
emit(string.format("Stats: %d nodes | %d leaves | max depth %d", stats.nodes, stats.leaves, stats.maxDepth))
emit("============================================================")
emit("")
emit("--- LEAF PATHS (relatif ke root, untuk wiring script) ---")
table.sort(leafPaths)
for _, path in ipairs(leafPaths) do
	emit("  " .. path)
end

emit("")
emit("--- CONTROLLER CHECKLIST (CinematicDockController) ---")
for _, item in ipairs(EXPECTED_TOP_LEVEL) do
	local child = target:FindFirstChild(item.name)
	local status = if child then "OK" elseif item.optional then "OPTIONAL (missing)" else "MISSING"
	local classInfo = ""
	if child and item.classHint and not child:IsA(item.classHint) then
		classInfo = string.format(" (class=%s, expected %s)", child.ClassName, item.classHint)
	elseif child then
		classInfo = string.format(" (%s)", child.ClassName)
	end
	emit(string.format("  [%s] %s%s", status, item.name, classInfo))
end

for _, item in ipairs(EXPECTED_DEEP) do
	local resolved = resolvePath(target, item.path)
	if not resolved then
		local leafName = string.match(item.path, "[^%.]+$")
		if leafName then
			resolved = findByNameDeep(target, leafName)
		end
	end
	local status = if resolved then "OK" else "MISSING"
	local note = if item.note then " — " .. item.note else ""
	emit(string.format("  [%s] %s%s", status, item.path, note))
	if resolved and resolved:GetFullName() ~= (target:GetFullName() .. "." .. item.path) then
		emit(string.format("       -> actual: %s", resolved:GetFullName()))
	end
end

emit("")
emit("--- IMMEDIATE CHILDREN (quick reference) ---")
local topChildren = target:GetChildren()
table.sort(topChildren, function(a, b)
	return a.Name < b.Name
end)
for _, child in ipairs(topChildren) do
	emit(string.format("  - %s (%s)", child.Name, child.ClassName))
end

emit("============================================================")

print(table.concat(LOG, "\n"))
