--!nocheck
-- ============================================================
-- Tag donation assets for CollectionService-based performance
-- (Replaces global Workspace.DescendantAdded listeners)
-- ============================================================
-- Jalankan di NUWA place, Edit Mode, Command Bar.
-- Sesuaikan DONATION_EFFECT_ROOTS dan DONATION_DISPLAY_ROOTS
-- dengan struktur place.
-- Setelah jalan: File > Save to Roblox / publish place.
-- ============================================================

local CollectionService = game:GetService("CollectionService")

-- === CONFIG: Sesuaikan dengan Explorer structure ===
-- Donation VFX roots (particles, beams) for graphics scaling
local DONATION_EFFECT_ROOTS = {
	-- "DonationVFX",
	-- "Effects/Donations",
}

-- Donation notification display root locations
local DONATION_DISPLAY_ROOTS = {
	-- "DonationDisplays",
}
-- ===================================================

local DONATION_EFFECT_TAG = "DonationEffect"
local DONATION_DISPLAY_TAG = "DonationDisplayRoot"

local function tagFolder(name: string, tag: string): boolean
	local inst = workspace:FindFirstChild(name)
	if not inst then
		warn(string.format("[TagDonationAssets] Folder '%s' not found in Workspace", name))
		return false
	end
	if CollectionService:HasTag(inst, tag) then
		print(string.format("[TagDonationAssets] '%s' already has tag '%s'", name, tag))
		return true
	end
	CollectionService:AddTag(inst, tag)
	print(string.format("[TagDonationAssets] Added '%s' to %s", tag, inst:GetFullName()))
	return true
end

print("=== TagDonationAssets ===")

local effectCount = 0
for _, name in ipairs(DONATION_EFFECT_ROOTS) do
	if tagFolder(name, DONATION_EFFECT_TAG) then
		effectCount += 1
	end
end

local displayCount = 0
for _, name in ipairs(DONATION_DISPLAY_ROOTS) do
	if tagFolder(name, DONATION_DISPLAY_TAG) then
		displayCount += 1
	end
end

print(string.format("[TagDonationAssets] Done. DonationEffect=%d, DonationDisplayRoot=%d", effectCount, displayCount))
print(string.format("[TagDonationAssets] Total DonationEffect: %d", #CollectionService:GetTagged(DONATION_EFFECT_TAG)))
print(string.format("[TagDonationAssets] Total DonationDisplayRoot: %d", #CollectionService:GetTagged(DONATION_DISPLAY_TAG)))

if effectCount == 0 and displayCount == 0 then
	warn("[TagDonationAssets] No folders tagged! Edit DONATION_EFFECT_ROOTS/DONATION_DISPLAY_ROOTS in script.")
end
