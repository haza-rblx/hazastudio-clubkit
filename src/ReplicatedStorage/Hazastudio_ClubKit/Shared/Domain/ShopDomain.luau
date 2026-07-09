--!strict
-- Shared/Domain/ShopDomain.lua
-- Pure functions only. Zero Roblox service calls.

local Config = require(script.Parent.Parent.Constants.Config)
local Types = require(script.Parent.Types)
local OverheadDomain = require(script.Parent.OverheadDomain)

local ShopDomain = {}

type ShopMembershipTier = Types.ShopMembershipTier

local VALID_SHOP_TIERS: {[string]: true} = {}
for _, tier in ipairs(Config.Membership.SHOP_TIERS or {}) do
	VALID_SHOP_TIERS[tier] = true
end

export type MembershipCatalogEntry = {
	name: string,
	price: number,
	image: string,
}

function ShopDomain.parseShopTier(tier: string): ShopMembershipTier?
	local normalized = OverheadDomain.normalizeMembershipTier(tier)
	if normalized and VALID_SHOP_TIERS[normalized] then
		return normalized :: ShopMembershipTier
	end
	return nil
end

function ShopDomain.isShopTier(tier: string): boolean
	return ShopDomain.parseShopTier(tier) ~= nil
end

function ShopDomain.getCatalogEntry(tier: string): MembershipCatalogEntry?
	local parsedTier = ShopDomain.parseShopTier(tier)
	if not parsedTier then
		return nil
	end

	local entry = Config.Shop.CATALOG[parsedTier]
	if not entry then
		return nil
	end

	return {
		name = entry.name,
		price = entry.price,
		image = entry.image,
	}
end

-- Cari tier berdasarkan BUY_ID
function ShopDomain.tierFromBuyId(productId: number): ShopMembershipTier?
	for tier, cfg in pairs(Config.Shop.PRODUCTS) do
		if cfg.BUY_ID ~= 0 and cfg.BUY_ID == productId then
			local parsedTier: ShopMembershipTier? = ShopDomain.parseShopTier(tier)
			if parsedTier then
				return parsedTier
			end
		end
	end
	return nil
end

-- Cari tier berdasarkan GIFT_ID
function ShopDomain.tierFromGiftId(productId: number): ShopMembershipTier?
	for tier, cfg in pairs(Config.Shop.PRODUCTS) do
		if cfg.GIFT_ID ~= 0 and cfg.GIFT_ID == productId then
			local parsedTier: ShopMembershipTier? = ShopDomain.parseShopTier(tier)
			if parsedTier then
				return parsedTier
			end
		end
	end
	return nil
end

function ShopDomain.isBuyProduct(productId: number): (boolean, ShopMembershipTier?)
	local tier: ShopMembershipTier? = ShopDomain.tierFromBuyId(productId)
	return tier ~= nil, tier
end

function ShopDomain.isGiftProduct(productId: number): (boolean, ShopMembershipTier?)
	local tier: ShopMembershipTier? = ShopDomain.tierFromGiftId(productId)
	return tier ~= nil, tier
end

function ShopDomain.getBenefitCount(tier: string): number
	local parsedTier = ShopDomain.parseShopTier(tier)
	if not parsedTier then
		return 0
	end

	local benefits = Config.Shop.BENEFITS[parsedTier]
	return benefits and #benefits or 0
end

-- Label display tier untuk notifikasi
function ShopDomain.tierDisplayName(tier: string): string
	local entry = ShopDomain.getCatalogEntry(tier)
	if entry then
		return entry.name .. " Membership"
	end
	return tier
end

return ShopDomain
