--!nocheck
-- ============================================================
-- EXTRACT DONATION ASSETS (LEGACY -> NEW SYSTEM)
-- ============================================================
-- Run in the LEGACY place, EDIT MODE, via Studio Command Bar
-- (or drop as a temporary Script then delete).
--
-- What it does:
--   1. Find legacy donation effect folder (default "DonationEffect")
--      and legacy sound folder (default "Sounds").
--   2. Clone each effect level + donation sound.
--   3. Reorganize into the structure read by the new system:
--        NUWA_DonationAssets (Model)
--          DonationEffects (Model)  -> Level1, Level3 ... (direct children)
--          DonationSounds  (Model)  -> Level1, Level3 ... (direct children)
--   4. Enable all ParticleEmitters in effects (legacy enabled via script;
--      new system clones as-is).
--   5. Select the output model -> right-click > Save to File
--      for .rbxm, then import into ServerStorage in the new system.
--
-- IMPORTANT NOTES ON LEVELS:
--   New system tiers: Level1, Level3, Level4, Level5, Level6,
--   Level7, Level8, Level9, Level10, Level11  (no Level2).
--   Legacy usually has Level1..Level9.
--   Default map below = identity (Level1->Level1, etc.). Meaning:
--     - Level1, Level3..Level9 filled from legacy.
--     - Level2 (if present) is cloned but ignored by the new system.
--     - Level10 & Level11 (largest donations) have NO legacy source;
--       script reports them as MISSING. Fill manually later
--       or add to EFFECT_LEVEL_MAP if you have a source.
-- ============================================================

local ServerStorage = game:GetService("ServerStorage")
local Selection = game:GetService("Selection")
local Workspace = game:GetService("Workspace")

-- ============================================================
-- CONFIG (adjust if legacy folder names differ)
-- ============================================================

-- Source folder names in legacy ServerStorage.
local SOURCE_EFFECTS_NAMES = { "DonationEffect", "DonationEffects", "DonationEffek" }
local SOURCE_SOUNDS_NAMES = { "Sounds", "DonationSounds", "Sound" }

-- Output wrapper name.
local OUTPUT_NAME = "NUWA_DonationAssets"

-- Temporary output parent for easy viewing & saving.
-- "Workspace" or "ServerStorage".
local OUTPUT_PARENT = "ServerStorage"

-- Enable all ParticleEmitters in cloned effects.
local ENABLE_PARTICLES = true

-- Tiers expected by the new system (for MISSING report).
local NEW_SYSTEM_LEVELS = {
	"Level1", "Level3", "Level4", "Level5", "Level6",
	"Level7", "Level8", "Level9", "Level10", "Level11",
}

-- Map legacy EFFECT name -> new system level name.
-- Default identity. Edit if legacy naming differs or you want remapping.
-- Format: [legacyChildName] = "LevelN"
local EFFECT_LEVEL_MAP = {
	Level1 = "Level1",
	Level2 = "Level2", -- ignored by new system, but cloned so it is not lost
	Level3 = "Level3",
	Level4 = "Level4",
	Level5 = "Level5",
	Level6 = "Level6",
	Level7 = "Level7",
	Level8 = "Level8",
	Level9 = "Level9",
	-- Level10 = "Level10", -- fill in if you have a source
	-- Level11 = "Level11",
}

-- Map legacy SOUND name -> new system level name(s).
-- Legacy usually: DonationLevel1..DonationLevel5 (Level5+ reuse DonationLevel5).
-- One source may map to multiple levels (cloned multiple times).
-- Format: [legacySoundName] = { "LevelN", ... }
local SOUND_LEVEL_MAP = {
	DonationLevel1 = { "Level1" },
	DonationLevel2 = { "Level2" },
	DonationLevel3 = { "Level3" },
	DonationLevel4 = { "Level4" },
	-- Legacy reuses DonationLevel5 for all high tiers:
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
	-- fallback: search one level nested under ServerStorage
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

	-- Remove previous output if present (idempotent).
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
		warn2("Legacy effect folder not found (" .. table.concat(SOURCE_EFFECTS_NAMES, ", ") .. ").")
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
				warn2("Effect '" .. child.Name .. "' not in EFFECT_LEVEL_MAP, skipped.")
			end
		end
	end

	-- ---- SOUNDS ----
	local srcSounds = findSourceFolder(SOURCE_SOUNDS_NAMES)
	if not srcSounds then
		warn2("Legacy sound folder not found (" .. table.concat(SOURCE_SOUNDS_NAMES, ", ") .. ").")
	else
		print("[ExtractDonation] Sounds source: " .. srcSounds:GetFullName())
		for legacyName, targets in pairs(SOUND_LEVEL_MAP) do
			local src = srcSounds:FindFirstChild(legacyName)
			if src then
				table.insert(report.soundsFound, legacyName)
				for _, target in ipairs(targets) do
					-- pick Sound instance (direct or nested)
					local soundInstance = src:IsA("Sound") and src or src:FindFirstChildWhichIsA("Sound", true)
					if soundInstance then
						local clone = soundInstance:Clone()
						clone.Name = target
						clone.Parent = soundsModel
						table.insert(report.soundsPlaced, string.format("%s -> %s", legacyName, target))
					else
						warn2("'" .. legacyName .. "' is not / does not contain Sound, skipped.")
					end
				end
			else
				warn2("Sound '" .. legacyName .. "' not found in source folder.")
			end
		end
	end

	wrapper.Parent = parent

	-- ---- REPORT ----
	print("--------------------------------------------------")
	print("[ExtractDonation] Effects found  : " .. table.concat(report.effectsFound, ", "))
	print("[ExtractDonation] Effects placed : " .. table.concat(report.effectsPlaced, " | "))
	print("[ExtractDonation] Sounds found   : " .. table.concat(report.soundsFound, ", "))
	print("[ExtractDonation] Sounds placed  : " .. #report.soundsPlaced .. " clones")

	-- Check new-system tiers not yet satisfied.
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
		warn2("Missing EFFECT tiers: " .. table.concat(missingEffects, ", "))
	end
	if #missingSounds > 0 then
		warn2("Missing SOUND tiers: " .. table.concat(missingSounds, ", "))
	end

	print("--------------------------------------------------")
	print(string.format(
		"[ExtractDonation] DONE. Output '%s' in %s. Selected.",
		OUTPUT_NAME, OUTPUT_PARENT
	))
	print("[ExtractDonation] Right-click model -> Save to File... -> save .rbxm")
	print("==================================================")

	Selection:Set({ wrapper })
end

run()
