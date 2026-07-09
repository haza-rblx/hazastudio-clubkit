--!nocheck
-- ============================================================
-- Remove blocked / broken Sound assets (Edit Mode)
-- ============================================================
-- Jalankan di NUWA place, Edit Mode, Command Bar.
-- ID list diambil dari ReplicatedStorage.Shared.Utils.SoundAssetSanitizer
--
-- Known paths (Smite3/Smite4 hammer):
--   WorldEffects.Smite3/4.DiamondHammer.Handle.MainChargeSound (8578316223)
--   WorldEffects.Smite3/4.DiamondHammer.Handle.ChargeSound* (9009370950)
--
-- Setelah jalan: File > Save to Roblox / publish place.
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local blockedSet: { [string]: boolean } = {}
local ok, sanitizer = pcall(function()
	return require(ReplicatedStorage.Shared.Utils.SoundAssetSanitizer)
end)
if ok and sanitizer.getBlockedSoundIds then
	for _, id in ipairs(sanitizer.getBlockedSoundIds()) do
		blockedSet[id] = true
	end
else
	warn("[RemoveBlockedSoundAssets] Sanitizer require failed — using fallback IDs")
	for _, id in ipairs({ "8578316223", "9009370950" }) do
		blockedSet[id] = true
	end
end

local function normalizeAssetId(soundId: string): string
	local id = string.match(soundId or "", "(%d+)")
	return id or ""
end

local removed = 0
local paths: { string } = {}

for _, inst in ipairs(game:GetDescendants()) do
	if inst:IsA("Sound") then
		local assetId = normalizeAssetId(inst.SoundId)
		if blockedSet[assetId] then
			table.insert(paths, inst:GetFullName())
			inst:Destroy()
			removed += 1
		end
	end
end

print(string.format("[RemoveBlockedSoundAssets] Removed %d Sound(s).", removed))
if #paths > 0 then
	print("[RemoveBlockedSoundAssets] Paths:")
	for _, path in ipairs(paths) do
		print("  - " .. path)
	end
else
	print("[RemoveBlockedSoundAssets] No blocked sounds found in place.")
end
