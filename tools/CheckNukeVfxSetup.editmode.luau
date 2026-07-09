--!strict
-- PATH: tools/CheckNukeVfxSetup.editmode.luau
-- Run via Roblox Studio Command Bar:
--   dofile("ServerScriptService/../tools/CheckNukeVfxSetup.editmode.luau")
-- or copy-paste the contents into Command Bar.
--
-- Validates the world-position nuke VFX setup:
--   1. ReplicatedStorage.WorldEffects folder exists
--   2. All 4 expected models present (Nuke, Smite3, Smite4, BlackHole)
--   3. Each model has the expected BillboardGui path
--   4. Each model has ParticleEmitters + Sounds
--   5. DonationEffect RemoteEvent is in place
--
-- Purely read-only — never modifies the place.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REQUIRED_EFFECTS = { "Nuke", "Smite3", "Smite4", "BlackHole" }
local BILLBOARD_PATH = { "BillboardGuiAnimation", "Frame", "TextLabels" }
local BILLBOARD_LABELS = { "TopText", "MiddleText", "BottomText" }

local passCount = 0
local failCount = 0
local warnings: { string } = {}

local function ok(label: string, detail: string?)
	print(string.format("  [✓] %s%s", label, detail and (" — " .. detail) or ""))
	passCount += 1
end

local function fail(label: string, detail: string?)
	warn(string.format("  [✗] %s%s", label, detail and (" — " .. detail) or ""))
	failCount += 1
end

local function warnMsg(msg: string)
	warn("  [!] " .. msg)
	table.insert(warnings, msg)
end

print("========================================")
print("  NUKE VFX SETUP CHECK")
print("========================================")

-- 1. WorldEffects folder
print("\n[1] ReplicatedStorage.WorldEffects/")
local folder = ReplicatedStorage:FindFirstChild("WorldEffects")
if folder and folder:IsA("Folder") then
	ok("Folder 'WorldEffects' exists")
elseif folder then
	fail("'WorldEffects' exists but is a " .. folder.ClassName .. " (expected Folder)")
else
	fail("Folder 'WorldEffects' missing", "Create a Folder named 'WorldEffects' under ReplicatedStorage")
end

-- 2. Required models
print("\n[2] Required effect models")
if folder and folder:IsA("Folder") then
	for _, effectName in ipairs(REQUIRED_EFFECTS) do
		local model = folder:FindFirstChild(effectName)
		if not model then
			fail(("Model '%s' missing"):format(effectName), "Copy from LEGACY/NEW_SYSTEM Studio or recreate")
			continue
		end

		-- Class check
		if not (model:IsA("Model") or model:IsA("BasePart")) then
			warnMsg(("'%s' is a %s (expected Model or BasePart)"):format(effectName, model.ClassName))
		else
			ok(("Model '%s' present (%s)"):format(effectName, model.ClassName))
		end

		-- 3. Billboard structure. Two layouts exist:
		--   Nuke      : Frame > TextLabels > { TopText, ... }
		--   Smite/Blk : Frame > { TopText, ... } (no TextLabels wrapper)
		local bb = model:FindFirstChild(BILLBOARD_PATH[1], true)
		if not bb or not bb:IsA("BillboardGui") then
			fail(("'%s' missing BillboardGuiAnimation"):format(effectName))
		else
			local frame = bb:FindFirstChild(BILLBOARD_PATH[2])
			if not frame then
				fail(("'%s' BillboardGuiAnimation missing 'Frame'"):format(effectName))
			else
				-- Try wrapped first, fall back to direct
				local container = frame:FindFirstChild(BILLBOARD_PATH[3]) or frame
				local layoutNote = (container == frame) and " (labels direct under Frame)" or ""
				local missing: { string } = {}
				for _, label in ipairs(BILLBOARD_LABELS) do
					if not container:FindFirstChild(label) then
						table.insert(missing, label)
					end
				end
				if #missing > 0 then
					fail(("'%s' TextLabels missing: %s"):format(effectName, table.concat(missing, ", ")))
				else
					ok(("'%s' billboard path complete%s"):format(effectName, layoutNote))
				end
			end
		end

		-- 4. Particle + sound counts
		local particles = 0
		local sounds = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("ParticleEmitter") then particles += 1 end
			if d:IsA("Sound") then sounds += 1 end
		end
		if particles == 0 then
			fail(("'%s' has no ParticleEmitters"):format(effectName))
		else
			ok(("'%s' has %d ParticleEmitter(s)"):format(effectName, particles))
		end
		if sounds == 0 then
			warnMsg(("'%s' has no Sounds (effect will play silently)"):format(effectName))
		else
			ok(("'%s' has %d Sound(s)"):format(effectName, sounds))
		end
	end
end

-- 5. DonationEffect RemoteEvent
print("\n[3] DonationEffect RemoteEvent")
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
local remote: Instance? = nil
if remotesFolder then
	remote = remotesFolder:FindFirstChild("DonationEffect")
end
if not remote then
	remote = ReplicatedStorage:FindFirstChild("DonationEffect")
end
if not remote then
	fail("DonationEffect RemoteEvent not found", "Run Main.server.luau once or wait for boot")
elseif not remote:IsA("RemoteEvent") then
	fail("DonationEffect exists but is " .. remote.ClassName)
else
	ok(("DonationEffect RemoteEvent present at %s"):format(remote:GetFullName()))
end

-- 6. Config sanity
print("\n[4] Config sanity (best-effort)")
local okConfig, Config = pcall(require, ReplicatedStorage.Shared.Constants.Config)
if not okConfig then
	warnMsg("Could not require Config.luau — skipping config checks")
elseif Config and Config.Donation then
	local d = Config.Donation
	if d.NUKE_REMOTE == "DonationEffect" then
		ok("NUKE_REMOTE = 'DonationEffect'")
	else
		warnMsg("NUKE_REMOTE is '" .. tostring(d.NUKE_REMOTE) .. "' (expected 'DonationEffect')")
	end
	if typeof(d.NUKE_WORLD_POSITION) == "Vector3" then
		ok("NUKE_WORLD_POSITION set", tostring(d.NUKE_WORLD_POSITION))
	else
		warnMsg("NUKE_WORLD_POSITION is not a Vector3 (will fall back to Vector3.zero)")
	end
	if type(d.ROBUX_NUKE_TIERS) == "table" then
		if #d.ROBUX_NUKE_TIERS == 0 then
			ok("ROBUX_NUKE_TIERS empty (Robux uses aura only — expected)")
		else
			ok("ROBUX_NUKE_TIERS has " .. #d.ROBUX_NUKE_TIERS .. " entries")
		end
	else
		fail("ROBUX_NUKE_TIERS missing")
	end
	if type(d.SAWERIA_NUKE_TIERS) == "table" and #d.SAWERIA_NUKE_TIERS > 0 then
		ok("SAWERIA_NUKE_TIERS has " .. #d.SAWERIA_NUKE_TIERS .. " entries")
	else
		fail("SAWERIA_NUKE_TIERS missing or empty")
	end
else
	warnMsg("Config.Donation not found")
end

-- Summary
print("\n========================================")
print(string.format("  RESULT: %d passed, %d failed", passCount, failCount))
if #warnings > 0 then
	print(string.format("  %d warning(s):", #warnings))
	for _, w in ipairs(warnings) do
		print("    - " .. w)
	end
end
if failCount == 0 then
	print("  ✅ Setup looks good. Test with /setrobux 5000 (admin)")
else
	print("  ❌ Fix the items marked [✗] above.")
end
print("========================================")
