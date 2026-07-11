--!strict
--[[
  Applies ClubKitConfig.Branding.LogoImage onto club brand ImageLabels/ImageButtons.

  Match rules (any one):
  1. Image still equals kit default asset id
  2. Attribute/tag ClubKitBrandLogo (previous apply)
  3. Instance name is LogoImage / ClubLogo / BrandLogo / ClubKitLogo

  One-shot / DescendantAdded — not per-frame.
]]

local CollectionService = game:GetService("CollectionService")

local BrandLogoApplier = {}

-- Baked into kit loading / posters / leaderboards.
local DEFAULT_KIT_LOGO = "rbxassetid://79426970537296"
local ATTR_MARK = "ClubKitBrandLogo"
local TAG_MARK = "ClubKitBrandLogo"
local NAME_MATCH: { [string]: boolean } = {
	LogoImage = true,
	ClubLogo = true,
	BrandLogo = true,
	ClubKitLogo = true,
	LoadingLogo = true,
}

export type ApplyStats = {
	matched: number,
	mutated: number,
	targetLogo: string,
	defaultLogo: string,
}

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

local function isBrandImageHolder(inst: Instance): boolean
	return inst:IsA("ImageLabel") or inst:IsA("ImageButton")
end

local function getImage(inst: Instance): string
	if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		return inst.Image
	end
	return ""
end

local function setImage(inst: Instance, image: string)
	if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		inst.Image = image
	end
end

local function shouldReplace(inst: Instance, defaultLogo: string): boolean
	if not isBrandImageHolder(inst) then
		return false
	end
	if inst:GetAttribute(ATTR_MARK) == true then
		return true
	end
	if CollectionService:HasTag(inst, TAG_MARK) then
		return true
	end
	if NAME_MATCH[inst.Name] == true then
		return true
	end
	local current = normalizeAsset(getImage(inst))
	return current == defaultLogo
end

local function applyToHolder(inst: Instance, targetLogo: string, defaultLogo: string): (boolean, boolean)
	if not shouldReplace(inst, defaultLogo) then
		return false, false
	end
	local mutated = false
	if normalizeAsset(getImage(inst)) ~= targetLogo then
		setImage(inst, targetLogo)
		mutated = true
	end
	inst:SetAttribute(ATTR_MARK, true)
	if not CollectionService:HasTag(inst, TAG_MARK) then
		CollectionService:AddTag(inst, TAG_MARK)
	end
	return true, mutated
end

function BrandLogoApplier.getDefaultKitLogo(): string
	return DEFAULT_KIT_LOGO
end

function BrandLogoApplier.resolveTargetLogo(config: any): string
	return resolveTargetLogo(config)
end

function BrandLogoApplier.applyToInstance(root: Instance, config: any): number
	return BrandLogoApplier.applyToInstanceDetailed(root, config).matched
end

function BrandLogoApplier.applyToInstanceDetailed(root: Instance, config: any): ApplyStats
	local targetLogo = resolveTargetLogo(config)
	local defaultLogo = resolveDefaultLogo(config)
	local matched = 0
	local mutated = 0
	if targetLogo == "" then
		return {
			matched = 0,
			mutated = 0,
			targetLogo = targetLogo,
			defaultLogo = defaultLogo,
		}
	end

	local function visit(inst: Instance)
		local didMatch, didMutate = applyToHolder(inst, targetLogo, defaultLogo)
		if didMatch then
			matched += 1
		end
		if didMutate then
			mutated += 1
		end
	end

	visit(root)
	for _, desc in ipairs(root:GetDescendants()) do
		visit(desc)
	end

	return {
		matched = matched,
		mutated = mutated,
		targetLogo = targetLogo,
		defaultLogo = defaultLogo,
	}
end

function BrandLogoApplier.applyRoots(roots: { Instance }, config: any): ApplyStats
	local total: ApplyStats = {
		matched = 0,
		mutated = 0,
		targetLogo = resolveTargetLogo(config),
		defaultLogo = resolveDefaultLogo(config),
	}
	for _, root in ipairs(roots) do
		local stats = BrandLogoApplier.applyToInstanceDetailed(root, config)
		total.matched += stats.matched
		total.mutated += stats.mutated
		total.targetLogo = stats.targetLogo
		total.defaultLogo = stats.defaultLogo
	end
	return total
end

function BrandLogoApplier.watch(root: Instance, config: any): RBXScriptConnection
	local targetLogo = resolveTargetLogo(config)
	local defaultLogo = resolveDefaultLogo(config)
	return root.DescendantAdded:Connect(function(desc)
		if isBrandImageHolder(desc) then
			applyToHolder(desc, targetLogo, defaultLogo)
		end
	end)
end

return BrandLogoApplier
