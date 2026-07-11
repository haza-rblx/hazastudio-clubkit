--!strict
--[[
  Applies ClubKitConfig.Branding.LogoImage onto ImageLabels that still use the
  kit default logo asset (or were previously marked by this applier).

  One-shot / DescendantAdded — not per-frame.
]]

local CollectionService = game:GetService("CollectionService")

local BrandLogoApplier = {}

-- Baked into kit loading / posters / leaderboards (ImageLabel.Image).
local DEFAULT_KIT_LOGO = "rbxassetid://79426970537296"
local ATTR_MARK = "ClubKitBrandLogo"
local TAG_MARK = "ClubKitBrandLogo"

local function digitsOnly(asset: string): string
	return (string.gsub(asset, "%D", ""))
end

local function normalizeAsset(asset: string): string
	local digits = digitsOnly(asset)
	if digits == "" then
		return ""
	end
	return "rbxassetid://" .. digits
end

local function resolveTargetLogo(config: any): string
	local branding = if type(config) == "table" then config.Branding else nil
	if type(branding) == "table" then
		if type(branding.LOGO_IMAGE) == "string" and branding.LOGO_IMAGE ~= "" then
			return normalizeAsset(branding.LOGO_IMAGE)
		end
	end
	local clubKit = if type(config) == "table" then config.ClubKit else nil
	local ckBranding = if type(clubKit) == "table" then clubKit.Branding else nil
	if type(ckBranding) == "table" and type(ckBranding.LogoImage) == "string" and ckBranding.LogoImage ~= "" then
		return normalizeAsset(ckBranding.LogoImage)
	end
	return normalizeAsset(DEFAULT_KIT_LOGO)
end

local function resolveDefaultLogo(config: any): string
	local branding = if type(config) == "table" then config.Branding else nil
	if type(branding) == "table" and type(branding.DEFAULT_LOGO_IMAGE) == "string" and branding.DEFAULT_LOGO_IMAGE ~= "" then
		return normalizeAsset(branding.DEFAULT_LOGO_IMAGE)
	end
	return normalizeAsset(DEFAULT_KIT_LOGO)
end

local function shouldReplace(label: ImageLabel, defaultLogo: string): boolean
	if label:GetAttribute(ATTR_MARK) == true then
		return true
	end
	if CollectionService:HasTag(label, TAG_MARK) then
		return true
	end
	local current = normalizeAsset(label.Image)
	return current == defaultLogo
end

local function applyToLabel(label: ImageLabel, targetLogo: string, defaultLogo: string): boolean
	if not shouldReplace(label, defaultLogo) then
		return false
	end
	if normalizeAsset(label.Image) ~= targetLogo then
		label.Image = targetLogo
	end
	label:SetAttribute(ATTR_MARK, true)
	if not CollectionService:HasTag(label, TAG_MARK) then
		CollectionService:AddTag(label, TAG_MARK)
	end
	return true
end

function BrandLogoApplier.getDefaultKitLogo(): string
	return DEFAULT_KIT_LOGO
end

function BrandLogoApplier.applyToInstance(root: Instance, config: any): number
	local targetLogo = resolveTargetLogo(config)
	local defaultLogo = resolveDefaultLogo(config)
	if targetLogo == "" then
		return 0
	end
	local changed = 0
	if root:IsA("ImageLabel") then
		if applyToLabel(root, targetLogo, defaultLogo) then
			changed += 1
		end
	end
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("ImageLabel") then
			if applyToLabel(desc, targetLogo, defaultLogo) then
				changed += 1
			end
		end
	end
	return changed
end

function BrandLogoApplier.applyRoots(roots: { Instance }, config: any): number
	local total = 0
	for _, root in ipairs(roots) do
		total += BrandLogoApplier.applyToInstance(root, config)
	end
	return total
end

--[[
  Watch late-cloned UI (PlayerGui clones, board templates). Cheap: only ImageLabel + id/mark check.
]]
function BrandLogoApplier.watch(root: Instance, config: any): RBXScriptConnection
	local targetLogo = resolveTargetLogo(config)
	local defaultLogo = resolveDefaultLogo(config)
	return root.DescendantAdded:Connect(function(desc)
		if desc:IsA("ImageLabel") then
			applyToLabel(desc, targetLogo, defaultLogo)
		end
	end)
end

return BrandLogoApplier
