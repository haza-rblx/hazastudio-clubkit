--!nocheck
-- ============================================================
-- EXTRACT LEGACY ASSETS (TOOLS, GUIS, + DESCENDANTS)
-- ============================================================
-- Run in LEGACY place, EDIT MODE, via Studio Command Bar
-- (or drop as a temporary Script under ServerScriptService then delete).
--
-- Purpose:
--   Pull legacy assets that were NOT pulled into source code (because
--   visual/non-script instances stay in Studio): Tools in StarterPack,
--   ScreenGuis in StarterGui, and ALL descendants (Handle/Mesh/Part,
--   Frame/Label/Image, Script/LocalScript, Sound, Animation, etc.).
--
-- Output:
--   ServerStorage > NUWA_LegacyAssets (Folder)
--     ├─ StarterPack (Folder)  -> GlowStick, Handphone, Sign  (full Tool)
--     ├─ StarterGui  (Folder)  -> ScreenGui + contents
--     └─ <OtherService> (Folder) -> as you register below
--
--   Result folder is auto-Selected. Right-click > Save to File... -> .rbxm
--   In the new system, drag each subfolder's contents to the matching service.
--
-- HONEST NOTES (read first):
--   - Script/LocalScript are cloned AS-IS from legacy. Many require legacy
--     modules (e.g. ReplicatedStorage.Mods, Icon, Packet). Those deps do
--     NOT come along. Treat this as "raw visual + reference logic", not
--     plug-and-play in the new system.
--   - GUIs driven by old architecture may need re-wiring to new controller/UI
--     patterns. Visual & layout are the most valuable parts.
--   - Assets under the same group (mesh/image/sound/animation) are safe across
--     same-universe places; IDs remain valid.
-- ============================================================

local ServerStorage = game:GetService("ServerStorage")
local Selection = game:GetService("Selection")

-- ============================================================
-- CONFIG: list what to extract.
-- Each entry: { service = "<ServiceName>", name = "<InstanceName>" }
-- name optional -> if nil, ALL children of that service are extracted.
-- ============================================================
local TARGETS = {
	-- Tools
	{ service = "StarterPack", name = "GlowStick" },
	{ service = "StarterPack", name = "Handphone" },
	{ service = "StarterPack", name = "Sign" },

	-- GUIs (ScreenGui + descendants: frame, label, image, localscript)
	{ service = "StarterGui", name = "MenuHandphone" },
	{ service = "StarterGui", name = "CarryGui" },
	{ service = "StarterGui", name = "Freecam" },
	{ service = "StarterGui", name = "MobileFreecam" },
	{ service = "StarterGui", name = "DonationUI" },
	{ service = "StarterGui", name = "ServerListGui" },
	{ service = "StarterGui", name = "SettingGui" },
	{ service = "StarterGui", name = "ScreenGui1" },
	{ service = "StarterGui", name = "AlertFrame" },
	{ service = "StarterGui", name = "AnnounceFrame" },
	{ service = "StarterGui", name = "Message" },

	-- Example: extract ALL children of a service (name = nil)
	-- { service = "StarterPack" },
}

local OUTPUT_NAME = "NUWA_LegacyAssets"

-- ============================================================
-- HELPERS
-- ============================================================
local report = { ok = {}, missing = {}, warn = {} }

local function logOk(s) table.insert(report.ok, s) end
local function logMissing(s) table.insert(report.missing, s); warn("[ExtractLegacy] MISSING: " .. s) end
local function logWarn(s) table.insert(report.warn, s); warn("[ExtractLegacy] " .. s) end

local function getServiceSafe(name)
	local ok, svc = pcall(function()
		return game:GetService(name)
	end)
	if ok and svc then
		return svc
	end
	-- fallback: find direct child under game (e.g. Workspace child)
	return game:FindFirstChild(name)
end

local function ensureSubfolder(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function countDescendants(inst)
	local scripts, guis, parts, sounds, other = 0, 0, 0, 0, 0
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			scripts += 1
		elseif d:IsA("GuiObject") or d:IsA("LayerCollector") then
			guis += 1
		elseif d:IsA("BasePart") then
			parts += 1
		elseif d:IsA("Sound") then
			sounds += 1
		else
			other += 1
		end
	end
	return scripts, guis, parts, sounds, other
end

-- ============================================================
-- MAIN
-- ============================================================
local function run()
	print("==================================================")
	print("[ExtractLegacy] START")

	local old = ServerStorage:FindFirstChild(OUTPUT_NAME)
	if old then
		old:Destroy()
		print("[ExtractLegacy] Removed previous output.")
	end

	local wrapper = Instance.new("Folder")
	wrapper.Name = OUTPUT_NAME

	for _, target in ipairs(TARGETS) do
		local svc = getServiceSafe(target.service)
		if not svc then
			logMissing(("service '%s'"):format(target.service))
			continue
		end

		local subfolder = ensureSubfolder(wrapper, target.service)

		if target.name == nil then
			-- all children of the service
			for _, child in ipairs(svc:GetChildren()) do
				local clone = child:Clone()
				clone.Parent = subfolder
				local s, g, p, snd = countDescendants(clone)
				logOk(("%s/%s  [scripts:%d gui:%d parts:%d sounds:%d]"):format(
					target.service, child.Name, s, g, p, snd))
			end
		else
			local src = svc:FindFirstChild(target.name)
			if not src then
				logMissing(("%s/%s"):format(target.service, target.name))
				continue
			end
			local clone = src:Clone()
			clone.Parent = subfolder
			local s, g, p, snd = countDescendants(clone)
			logOk(("%s/%s  [scripts:%d gui:%d parts:%d sounds:%d]"):format(
				target.service, target.name, s, g, p, snd))
		end
	end

	-- Remove empty subfolders for a tidy output.
	for _, sub in ipairs(wrapper:GetChildren()) do
		if #sub:GetChildren() == 0 then
			sub:Destroy()
		end
	end

	wrapper.Parent = ServerStorage

	print("--------------------------------------------------")
	print(("[ExtractLegacy] Extracted %d item(s):"):format(#report.ok))
	for _, line in ipairs(report.ok) do
		print("   + " .. line)
	end
	if #report.missing > 0 then
		print(("[ExtractLegacy] %d MISSING (check name/location):"):format(#report.missing))
		for _, line in ipairs(report.missing) do
			print("   - " .. line)
		end
	end
	print("--------------------------------------------------")
	print(("[ExtractLegacy] DONE. ServerStorage > %s is now Selected."):format(OUTPUT_NAME))
	print("[ExtractLegacy] Right-click > Save to File... -> save .rbxm")
	print("[ExtractLegacy] In the new system: drag each subfolder's contents to its service.")
	print("==================================================")

	Selection:Set({ wrapper })
end

run()
