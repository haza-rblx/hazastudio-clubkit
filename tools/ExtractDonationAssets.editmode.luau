--!nocheck
-- ============================================================
-- EXTRACT DONATION ASSETS (LEGACY -> NEW SYSTEM)
-- ============================================================
-- Jalankan di LEGACY place, EDIT MODE, lewat Command Bar Studio
-- (atau drop sbagai Script sementara lalu hapus).
--
-- Apa yang dilakukan:
--   1. Cari folder efek donasi legacy (default "DonationEffect")
--      dan folder sound legacy (default "Sounds").
--   2. Clone tiap level effect + sound donasi.
--   3. Susun ulang ke struktur yang dibaca new system:
--        NUWA_DonationAssets (Model)
--          DonationEffects (Model)  -> Level1, Level3 ... (anak langsung)
--          DonationSounds  (Model)  -> Level1, Level3 ... (anak langsung)
--   4. Enable semua ParticleEmitter di efek (legacy nyalain via script,
--      new system clone apa adanya).
--   5. Pilih (Selection) model hasil -> tinggal klik kanan > Save to File
--      untuk dapat .rbxm, lalu import ke ServerStorage new system.
--
-- CATATAN PENTING soal LEVEL:
--   New system pakai tier: Level1, Level3, Level4, Level5, Level6,
--   Level7, Level8, Level9, Level10, Level11  (tidak ada Level2).
--   Legacy umumnya punya Level1..Level9.
--   Default map di bawah = identity (Level1->Level1, dst). Artinya:
--     - Level1, Level3..Level9 terisi dari legacy.
--     - Level2 (kalau ada) ikut ke-clone tapi diabaikan new system.
--     - Level10 & Level11 (donasi terbesar) TIDAK ada sumber legacy-nya;
--       script akan melaporkannya sebagai MISSING. Isi manual nanti
--       atau tambahkan ke EFFECT_LEVEL_MAP kalau kamu punya sumbernya.
-- ============================================================

local ServerStorage = game:GetService("ServerStorage")
local Selection = game:GetService("Selection")
local Workspace = game:GetService("Workspace")

-- ============================================================
-- CONFIG (sesuaikan kalau nama folder legacy beda)
-- ============================================================

-- Nama folder sumber di ServerStorage legacy.
local SOURCE_EFFECTS_NAMES = { "DonationEffect", "DonationEffects", "DonationEffek" }
local SOURCE_SOUNDS_NAMES = { "Sounds", "DonationSounds", "Sound" }

-- Nama wrapper output.
local OUTPUT_NAME = "NUWA_DonationAssets"

-- Taruh output di mana sementara biar gampang dilihat & disimpan.
-- "Workspace" atau "ServerStorage".
local OUTPUT_PARENT = "ServerStorage"

-- Nyalakan semua ParticleEmitter di efek hasil clone.
local ENABLE_PARTICLES = true

-- Tier yang diharapkan new system (untuk laporan MISSING).
local NEW_SYSTEM_LEVELS = {
	"Level1", "Level3", "Level4", "Level5", "Level6",
	"Level7", "Level8", "Level9", "Level10", "Level11",
}

-- Map nama EFEK legacy -> nama level new system.
-- Default identity. Edit kalau penamaan legacy beda atau mau remap.
-- Format: [namaAnakLegacy] = "LevelN"
local EFFECT_LEVEL_MAP = {
	Level1 = "Level1",
	Level2 = "Level2", -- diabaikan new system, tapi ikut biar tidak hilang
	Level3 = "Level3",
	Level4 = "Level4",
	Level5 = "Level5",
	Level6 = "Level6",
	Level7 = "Level7",
	Level8 = "Level8",
	Level9 = "Level9",
	-- Level10 = "Level10", -- isi kalau punya sumbernya
	-- Level11 = "Level11",
}

-- Map nama SOUND legacy -> nama level new system.
-- Legacy umumnya: DonationLevel1..DonationLevel5 (Level5+ pakai DonationLevel5).
-- Boleh map satu sumber ke beberapa level (akan di-clone berkali-kali).
-- Format: [namaSoundLegacy] = { "LevelN", ... }
local SOUND_LEVEL_MAP = {
	DonationLevel1 = { "Level1" },
	DonationLevel2 = { "Level2" },
	DonationLevel3 = { "Level3" },
	DonationLevel4 = { "Level4" },
	-- Legacy reuse DonationLevel5 untuk semua tier tinggi:
	DonationLevel5 = { "Level5", "Level6", "Level7", "Level8", "Level9", "Level10", "Level11" },
}

-- ============================================================
-- HELPERS
-- ============================================================

local report = {
	effectsFound = {},
	effectsPlaced = {},
	soundsFound = {},
	soundsPlaced = {},
	warnings = {},
}

local function warn2(msg)
	table.insert(report.warnings, msg)
	warn("[ExtractDonation] " .. msg)
end

local function findSourceFolder(names)
	for _, name in ipairs(names) do
		local direct = ServerStorage:FindFirstChild(name)
		if direct then
			return direct
		end
	end
	-- fallback: cari nested 1 level di ServerStorage
	for _, child in ipairs(ServerStorage:GetChildren()) do
		for _, name in ipairs(names) do
			local nested = child:FindFirstChild(name)
			if nested then
				return nested
			end
		end
	end
	return nil
end

local function enableParticles(root)
	if not ENABLE_PARTICLES then
		return
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			d.Enabled = true
		end
	end
	if root:IsA("ParticleEmitter") then
		root.Enabled = true
	end
end

local function setOf(list)
	local s = {}
	for _, v in ipairs(list) do
		s[v] = true
	end
	return s
end

-- ============================================================
-- MAIN
-- ============================================================

local function run()
	print("==================================================")
	print("[ExtractDonation] START")

	-- Bersihkan output lama kalau ada (idempotent).
	local parent = (OUTPUT_PARENT == "Workspace") and Workspace or ServerStorage
	local old = parent:FindFirstChild(OUTPUT_NAME)
	if old then
		old:Destroy()
		print("[ExtractDonation] Removed previous output.")
	end

	local wrapper = Instance.new("Model")
	wrapper.Name = OUTPUT_NAME

	local effectsModel = Instance.new("Model")
	effectsModel.Name = "DonationEffects"
	effectsModel.Parent = wrapper

	local soundsModel = Instance.new("Model")
	soundsModel.Name = "DonationSounds"
	soundsModel.Parent = wrapper

	-- ---- EFFECTS ----
	local srcEffects = findSourceFolder(SOURCE_EFFECTS_NAMES)
	if not srcEffects then
		warn2("Folder efek legacy tidak ditemukan (" .. table.concat(SOURCE_EFFECTS_NAMES, ", ") .. ").")
	else
		print("[ExtractDonation] Effects source: " .. srcEffects:GetFullName())
		for _, child in ipairs(srcEffects:GetChildren()) do
			table.insert(report.effectsFound, child.Name)
			local target = EFFECT_LEVEL_MAP[child.Name]
			if target then
				local clone = child:Clone()
				clone.Name = target
				enableParticles(clone)
				clone.Parent = effectsModel
				table.insert(report.effectsPlaced, string.format("%s -> %s", child.Name, target))
			else
				warn2("Efek '" .. child.Name .. "' tidak ada di EFFECT_LEVEL_MAP, di-skip.")
			end
		end
	end

	-- ---- SOUNDS ----
	local srcSounds = findSourceFolder(SOURCE_SOUNDS_NAMES)
	if not srcSounds then
		warn2("Folder sound legacy tidak ditemukan (" .. table.concat(SOURCE_SOUNDS_NAMES, ", ") .. ").")
	else
		print("[ExtractDonation] Sounds source: " .. srcSounds:GetFullName())
		for legacyName, targets in pairs(SOUND_LEVEL_MAP) do
			local src = srcSounds:FindFirstChild(legacyName)
			if src then
				table.insert(report.soundsFound, legacyName)
				for _, target in ipairs(targets) do
					-- ambil instance Sound (langsung atau nested)
					local soundInstance = src:IsA("Sound") and src or src:FindFirstChildWhichIsA("Sound", true)
					if soundInstance then
						local clone = soundInstance:Clone()
						clone.Name = target
						clone.Parent = soundsModel
						table.insert(report.soundsPlaced, string.format("%s -> %s", legacyName, target))
					else
						warn2("'" .. legacyName .. "' bukan/tidak mengandung Sound, di-skip.")
					end
				end
			else
				warn2("Sound '" .. legacyName .. "' tidak ditemukan di sumber.")
			end
		end
	end

	wrapper.Parent = parent

	-- ---- LAPORAN ----
	print("--------------------------------------------------")
	print("[ExtractDonation] Effects found  : " .. table.concat(report.effectsFound, ", "))
	print("[ExtractDonation] Effects placed : " .. table.concat(report.effectsPlaced, " | "))
	print("[ExtractDonation] Sounds found   : " .. table.concat(report.soundsFound, ", "))
	print("[ExtractDonation] Sounds placed  : " .. #report.soundsPlaced .. " clones")

	-- Cek tier new system yang belum terpenuhi.
	local placedEffectLevels = {}
	for _, m in ipairs(effectsModel:GetChildren()) do
		placedEffectLevels[m.Name] = true
	end
	local placedSoundLevels = {}
	for _, s in ipairs(soundsModel:GetChildren()) do
		placedSoundLevels[s.Name] = true
	end
	local missingEffects, missingSounds = {}, {}
	for _, lvl in ipairs(NEW_SYSTEM_LEVELS) do
		if not placedEffectLevels[lvl] then
			table.insert(missingEffects, lvl)
		end
		if not placedSoundLevels[lvl] then
			table.insert(missingSounds, lvl)
		end
	end
	if #missingEffects > 0 then
		warn2("EFEK belum ada untuk tier: " .. table.concat(missingEffects, ", "))
	end
	if #missingSounds > 0 then
		warn2("SOUND belum ada untuk tier: " .. table.concat(missingSounds, ", "))
	end

	print("--------------------------------------------------")
	print(string.format(
		"[ExtractDonation] DONE. Output '%s' di %s. Sudah di-Select.",
		OUTPUT_NAME, OUTPUT_PARENT
	))
	print("[ExtractDonation] Klik kanan model -> Save to File... -> simpan .rbxm")
	print("==================================================")

	Selection:Set({ wrapper })
end

run()
