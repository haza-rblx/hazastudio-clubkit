--!nocheck
-- PATH: tools/PrintJoinCommunityAndGreetingGuiTree.editmode.luau
-- Run via Roblox Studio Command Bar (Edit Mode OK — no Play needed):
--   1. Open the place that has StarterGui UI assets.
--   2. Copy this entire file → paste into Command Bar → Enter.
--   Or (if tools are synced into the place): dofile("…/PrintJoinCommunityAndGreetingGuiTree.editmode.luau")
--
-- Dumps the recursive GUI tree for:
--   1. 16-JoinCommunPrompt  (often under a 03-GuiSystem* ScreenGui in StarterGui)
--   2. GreetingNotifications (under StarterGui.99-NotificationCenter)
--
-- Purely read-only — never modifies the place.
-- ============================================================

local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")

-- Prefer exact child under preferredParent when set; else recursive FindFirstChild under StarterGui.
local TARGETS = {
	{
		name = "16-JoinCommunPrompt",
		preferredParentName = nil, -- unknown exact parent; search StarterGui recursively
		hint = "StarterGui (often nested under a 03-GuiSystem* ScreenGui)",
	},
	{
		name = "GreetingNotifications",
		preferredParentName = "99-NotificationCenter",
		hint = "StarterGui.99-NotificationCenter",
	},
}

local MAX_DEPTH = 0 -- 0 = unlimited (to leaf)
local SHOW_PROPERTIES = true
local FALLBACK_PLAYER_GUI = true -- if missing in StarterGui and LocalPlayer exists (Play)

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
	local limit = max or 72
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
	end

	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		add("Text", string.format("%q", tostring(safeGet(inst, "Text") or "")))
		add("TextScaled", safeGet(inst, "TextScaled"))
		if safeGet(inst, "TextScaled") ~= true then
			add("TextSize", safeGet(inst, "TextSize"))
		end
	end

	if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		add("Image", safeGet(inst, "Image"))
	end

	if inst:IsA("GuiObject") then
		add("Visible", safeGet(inst, "Visible"))
		add("Size", fmtUDim2(safeGet(inst, "Size")))
		add("Position", fmtUDim2(safeGet(inst, "Position")))
		local z = safeGet(inst, "ZIndex")
		if z and z ~= 1 then
			add("ZIndex", z)
		end
		local lo = safeGet(inst, "LayoutOrder")
		if lo and lo ~= 0 then
			add("LayoutOrder", lo)
		end
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

local function walk(inst: Instance, depth: number, prefix: string, isLast: boolean, stats: { nodes: number, maxDepth: number })
	stats.nodes += 1
	if depth > stats.maxDepth then
		stats.maxDepth = depth
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

	local children = sortChildren(inst:GetChildren())
	local childPrefix
	if depth == 0 then
		childPrefix = ""
	elseif isLast then
		childPrefix = prefix .. "   "
	else
		childPrefix = prefix .. "│  "
	end

	for i, child in ipairs(children) do
		walk(child, depth + 1, childPrefix, i == #children, stats)
	end
end

local function findInRoot(root: Instance, name: string, preferredParentName: string?): Instance?
	if preferredParentName then
		local parent = root:FindFirstChild(preferredParentName)
		if parent then
			local nested = parent:FindFirstChild(name, true)
			if nested then
				return nested
			end
		end
	end
	return root:FindFirstChild(name, true)
end

local function resolveTarget(name: string, preferredParentName: string?): (Instance?, string)
	local found = findInRoot(StarterGui, name, preferredParentName)
	if found then
		return found, "StarterGui"
	end

	if FALLBACK_PLAYER_GUI then
		local lp = Players.LocalPlayer
		if lp then
			local pg = lp:FindFirstChild("PlayerGui")
			if pg then
				found = findInRoot(pg, name, preferredParentName)
				if found then
					return found, "PlayerGui"
				end
			end
		end
	end

	return nil, "StarterGui"
end

local function dumpTarget(targetInfo: { name: string, preferredParentName: string?, hint: string }): boolean
	local name = targetInfo.name
	local found, where = resolveTarget(name, targetInfo.preferredParentName)

	emit("")
	emit("============================================================")
	emit(string.format("ROOT: %s", name))
	emit(string.format("Hint: %s", targetInfo.hint))
	emit("============================================================")

	if not found then
		local detail = string.format(
			"[PrintJoinCommunityAndGreetingGuiTree] FAIL — '%s' not found under %s%s.",
			name,
			where,
			targetInfo.preferredParentName and (" (preferred parent '" .. targetInfo.preferredParentName .. "')") or ""
		)
		warn(detail)
		emit(detail)
		emit("============================================================")
		return false
	end

	local stats = { nodes = 0, maxDepth = 0 }
	emit(string.format("Found: %s", found:GetFullName()))
	emit(string.format("Via: %s | ClassName: %s | depth=%s", where, found.ClassName, MAX_DEPTH == 0 and "unlimited" or tostring(MAX_DEPTH)))
	emit("------------------------------------------------------------")

	walk(found, 0, "", true, stats)

	emit("------------------------------------------------------------")
	emit(string.format("Stats [%s]: nodes=%d | maxDepth=%d", name, stats.nodes, stats.maxDepth))
	emit("============================================================")
	return true
end

-- ============================================================
-- MAIN
-- ============================================================

emit("============================================================")
emit("JOIN COMMUNITY + GREETING NOTIFICATIONS — GUI TREE DUMP")
emit("Edit Mode / Command Bar — read-only")
emit("============================================================")

local foundCount = 0
for _, info in ipairs(TARGETS) do
	if dumpTarget(info) then
		foundCount += 1
	end
end

emit("")
emit("============================================================")
emit(string.format("Done. Found %d / %d roots.", foundCount, #TARGETS))
emit("============================================================")
emit("END DUMP")

print(table.concat(LOG, "\n"))
