--!nocheck
-- ============================================================
-- Tag venue folders for Settings graphics scaling (Edit Mode)
-- ============================================================
-- Jalankan di NUWA place, Edit Mode, Command Bar.
-- Sesuaikan GEOMETRY_ROOTS dan VFX_ROOTS dengan struktur place.
-- Setelah jalan: File > Save to Roblox / publish place.
-- ============================================================

local CollectionService = game:GetService("CollectionService")

-- === CONFIG: Sesuaikan dengan Explorer structure ===
local GEOMETRY_ROOTS = {
	-- Folder/Model yang berisi venue geometry (walls, floors, props)
	-- "Map",
	-- "Club",
	-- "Venue",
}

local VFX_ROOTS = {
	-- Folder yang berisi venue VFX (lasers, particles, beams)
	-- "VFX",
	-- "Effects",
}

local DONATION_ROOTS = {
	-- Folder yang berisi donation VFX roots (particles, beams) untuk graphics scaling
	-- "DonationVFX",
	-- "Effects/Donations",
}

local DONATION_DISPLAY_ROOTS = {
	-- Folder yang berisi donation notification display locations
	-- "DonationDisplays",
}
-- ===================================================

local GEOMETRY_TAG = "ScalableGeometry"
local VFX_TAG = "ScalableVfx"
local DONATION_EFFECT_TAG = "DonationEffect"
local DONATION_DISPLAY_TAG = "DonationDisplayRoot"

local function tagFolder(name: string, tag: string): boolean
	local inst = workspace:FindFirstChild(name)
	if not inst then
		warn(string.format("[TagScalableVenue] Folder '%s' not found in Workspace", name))
		return false
	end
	if CollectionService:HasTag(inst, tag) then
		print(string.format("[TagScalableVenue] '%s' already has tag '%s'", name, tag))
		return true
	end
	CollectionService:AddTag(inst, tag)
	print(string.format("[TagScalableVenue] Added '%s' to %s", tag, inst:GetFullName()))
	return true
end

print("=== TagScalableVenue ===")

local geoCount = 0
for _, name in ipairs(GEOMETRY_ROOTS) do
	if tagFolder(name, GEOMETRY_TAG) then
		geoCount += 1
	end
end

local vfxCount = 0
for _, name in ipairs(VFX_ROOTS) do
	if tagFolder(name, VFX_TAG) then
		vfxCount += 1
	end
end

local donationEffectCount = 0
for _, name in ipairs(DONATION_ROOTS) do
	if tagFolder(name, DONATION_EFFECT_TAG) then
		donationEffectCount += 1
	end
end

local donationDisplayCount = 0
for _, name in ipairs(DONATION_DISPLAY_ROOTS) do
	if tagFolder(name, DONATION_DISPLAY_TAG) then
		donationDisplayCount += 1
	end
end

print(string.format("[TagScalableVenue] Done. Geometry=%d, VFX=%d, DonationEffect=%d, DonationDisplay=%d", geoCount, vfxCount, donationEffectCount, donationDisplayCount))
print(string.format("[TagScalableVenue] Total ScalableGeometry: %d", #CollectionService:GetTagged(GEOMETRY_TAG)))
print(string.format("[TagScalableVenue] Total ScalableVfx: %d", #CollectionService:GetTagged(VFX_TAG)))
print(string.format("[TagScalableVenue] Total DonationEffect: %d", #CollectionService:GetTagged(DONATION_EFFECT_TAG)))
print(string.format("[TagScalableVenue] Total DonationDisplayRoot: %d", #CollectionService:GetTagged(DONATION_DISPLAY_TAG)))

if geoCount == 0 and vfxCount == 0 and donationEffectCount == 0 and donationDisplayCount == 0 then
	warn("[TagScalableVenue] No folders tagged! Edit GEOMETRY_ROOTS/VFX_ROOTS/DONATION_ROOTS/DONATION_DISPLAY_ROOTS in script.")
end
