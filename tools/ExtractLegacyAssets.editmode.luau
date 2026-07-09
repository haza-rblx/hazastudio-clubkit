--!nocheck
-- ============================================================
-- EXTRACT LEGACY ASSETS (TOOLS, GUIS, + DESCENDANTS)
-- ============================================================
-- Jalankan di LEGACY place, EDIT MODE, lewat Command Bar Studio
-- (atau drop sebagai Script sementara di ServerScriptService lalu hapus).
--
-- Tujuan:
--   Menarik aset legacy yang TIDAK ikut ter-pull ke source code (karena
--   visual/instance non-script tinggal di Studio): Tool di StarterPack,
--   ScreenGui di StarterGui, beserta SEMUA turunannya (Handle/Mesh/Part,
--   Frame/Label/Image, Script/LocalScript, Sound, Animation, dll).
--
-- Output:
--   ServerStorage > NUWA_LegacyAssets (Folder)
--     ├─ StarterPack (Folder)  -> GlowStick, Handphone, Sign  (Tool utuh)
--     ├─ StarterGui  (Folder)  -> ScreenGui + isinya
--     └─ <ServiceLain> (Folder) -> sesuai yang kamu daftarkan
--
--   Folder hasil otomatis di-Select. Klik kanan > Save to File... -> .rbxm
--   Di new system, drag isi tiap subfolder ke service yang sesuai.
--
-- CATATAN JUJUR (baca dulu):
--   - Script/LocalScript ikut ter-clone APA ADANYA dari legacy. Banyak di
--     antaranya require modul legacy (mis. ReplicatedStorage.Mods, Icon,
--     Packet). Dependency itu TIDAK ikut. Jadi anggap ini "bahan mentah
--     visual + logika referensi", bukan langsung plug-and-play di new system.
--   - GUI yang di-drive arsitektur lama mungkin perlu di-rewire ke pola
--     controller/UI new system. Visual & layout-nya yang paling berharga.
--   - Aset di bawah grup yang sama (mesh/image/sound/animation) aman lintas
--     place se-universe; ID-nya tetap valid.
-- ============================================================

local ServerStorage = game:GetService("ServerStorage")
local Selection = game:GetService("Selection")

-- ============================================================
-- CONFIG: daftar apa yang mau ditarik.
-- Tiap entry: { service = "<NamaService>", name = "<NamaInstance>" }
-- name opsional -> kalau nil, SEMUA anak service itu ditarik.
-- ============================================================
local TARGETS = {
	-- Tools
	{ service = "StarterPack", name = "GlowStick" },
	{ service = "StarterPack", name = "Handphone" },
	{ service = "StarterPack", name = "Sign" },

	-- GUIs (ScreenGui + turunannya: frame, label, image, localscript)
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

	-- Contoh: tarik SEMUA isi sebuah service (name = nil)
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
	-- fallback: cari child langsung di game (mis. Workspace child)
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
			-- semua anak service
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

	-- Buang subfolder kosong biar rapi.
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
		print(("[ExtractLegacy] %d MISSING (cek nama/lokasi):"):format(#report.missing))
		for _, line in ipairs(report.missing) do
			print("   - " .. line)
		end
	end
	print("--------------------------------------------------")
	print(("[ExtractLegacy] DONE. ServerStorage > %s sudah di-Select."):format(OUTPUT_NAME))
	print("[ExtractLegacy] Klik kanan > Save to File... -> simpan .rbxm")
	print("[ExtractLegacy] Di new system: drag isi tiap subfolder ke service-nya.")
	print("==================================================")

	Selection:Set({ wrapper })
end

run()
