--!strict
-- Merges ClubKitConfig buyer values into kit Config before derived tables are built.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClubKitDefaults = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Config.ClubKitDefaults)
local ClubKitConfigSchema = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Config.ClubKitConfigSchema)
local ClubKitConfig = require(ReplicatedStorage.Hazastudio_ClubKitConfig.ClubKitConfig)
local DonationProviderDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.DonationProviderDomain)
local RoleCategoryBuilder = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Config.RoleCategoryBuilder)

local ConfigBootstrap = {}

local REQUIRED_SECTIONS = {
	"Branding",
	"Group",
	"Donation",
	"Carry",
	"Loading",
	"Shop",
	"PaidBroadcast",
	"Membership",
	"RoleCategories",
	"SpenderRoles",
	"SystemRoles",
	"LegacyAliases",
	"CommandAliases",
	"Features",
}

local function validateClubKitState(state: any)
	for _, key in ipairs(REQUIRED_SECTIONS) do
		if type(state[key]) ~= "table" then
			warn("[ConfigBootstrap] ClubKitConfig missing required section:", key)
		end
	end
	local shop = state.Shop
	if type(shop) == "table" and type(shop.Products) == "table" then
		for tierKey, product in pairs(shop.Products) do
			if type(product) == "table" then
				local buyPassId = product.BuyGamePassId
				if type(buyPassId) ~= "number" or buyPassId <= 0 then
					warn("[ConfigBootstrap] Shop.Products." .. tierKey .. ".BuyGamePassId belum diisi (Creator Dashboard → Game Passes)")
				end
				local giftId = product.GiftId
				if type(giftId) ~= "number" or giftId <= 0 then
					warn("[ConfigBootstrap] Shop.Products." .. tierKey .. ".GiftId belum diisi (Developer Product)")
				end
			end
		end
	end
	local paidBroadcast = state.PaidBroadcast
	if type(paidBroadcast) == "table" then
		local productId = tonumber(paidBroadcast.ProductId)
		if not productId or productId <= 0 then
			warn("[ConfigBootstrap] PaidBroadcast.ProductId belum diisi (Creator Dashboard)")
		end
	end
end

local function deepMerge(base: any, override: any): any
	if type(base) ~= "table" then
		return if override ~= nil then override else base
	end
	if type(override) ~= "table" then
		return base
	end
	local result = table.clone(base)
	for key, value in pairs(override) do
		if type(value) == "table" and type(result[key]) == "table" then
			result[key] = deepMerge(result[key], value)
		else
			result[key] = value
		end
	end
	return result
end

local function loadShowcaseOverlay(): any?
	-- Optional ModuleScript: inject manually under Shared/Config for demo places only.
	-- Not shipped via Update Engine / Rojo default tree (lives under tools/dev/).
	local showcaseModule = script.Parent:FindFirstChild("ClubKitShowcase")
	if not showcaseModule or not showcaseModule:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, showcaseModule)
	if not ok then
		warn("[ConfigBootstrap] ClubKitShowcase failed to load:", result)
		return nil
	end
	if result == nil then
		return nil
	end
	if type(result) ~= "table" then
		warn("[ConfigBootstrap] ClubKitShowcase must return a table or nil")
		return nil
	end
	if result.Enabled == false or (type(result.Showcase) == "table" and result.Showcase.Enabled == false) then
		return nil
	end
	return result
end

local function applyShowcaseMode(state: any, showcaseOverlay: any?)
	state.Showcase = if type(state.Showcase) == "table" then state.Showcase else {}
	state.Showcase.Enabled = showcaseOverlay ~= nil
end

local function buildClubKitState(): any
	-- Schema fill-forward (buyer wins) → ClubKitDefaults → optional ClubKitShowcase overlay.
	local filledPaths: { string } = {}
	local buyerFilled = ClubKitConfigSchema.fillForward(ClubKitConfigSchema.defaults, ClubKitConfig, filledPaths)
	if #filledPaths > 0 then
		print("[ConfigBootstrap] fillForward filled " .. tostring(#filledPaths) .. " path(s): " .. table.concat(filledPaths, ", "))
	end
	local state = deepMerge(ClubKitDefaults, buyerFilled)
	local showcaseOverlay = loadShowcaseOverlay()
	if showcaseOverlay then
		state = deepMerge(state, showcaseOverlay)
		local showcaseDonation = showcaseOverlay.Donation
		if type(showcaseDonation) == "table" then
			if type(showcaseDonation.AuraTiers) == "table" and #showcaseDonation.AuraTiers > 0 then
				state.Donation.AuraTiers = showcaseDonation.AuraTiers
			elseif type(showcaseDonation.RobuxAuraTiers) == "table" and #showcaseDonation.RobuxAuraTiers > 0 then
				state.Donation.AuraTiers = showcaseDonation.RobuxAuraTiers
			end
			if type(showcaseDonation.WorldEffectTiers) == "table" and #showcaseDonation.WorldEffectTiers > 0 then
				state.Donation.WorldEffectTiers = showcaseDonation.WorldEffectTiers
			elseif type(showcaseDonation.SaweriaWorldTiers) == "table" and #showcaseDonation.SaweriaWorldTiers > 0 then
				state.Donation.WorldEffectTiers = showcaseDonation.SaweriaWorldTiers
			end
		end
	end
	applyShowcaseMode(state, showcaseOverlay)
	validateClubKitState(state)
	return state
end

function ConfigBootstrap.apply(config: any)
	local clubKit = buildClubKitState()
	config.ClubKit = clubKit
	config.ClubKitShowcaseActive = clubKit.Showcase and clubKit.Showcase.Enabled == true
	config.KitProduct = require(ReplicatedStorage.Hazastudio_ClubKit.KitProduct)

	local branding = clubKit.Branding or {}
	if type(config.Loading) == "table" then
		if type(branding.WelcomeMessage) == "string" and branding.WelcomeMessage ~= "" then
			config.Loading.WELCOME_DISMISS_FORMAT = branding.WelcomeMessage
		end
		if type(branding.Greeting) == "string" and branding.Greeting ~= "" then
			config.Loading.PRIMARY_GREETING = branding.Greeting
		end
	end
	if type(branding.GameName) == "string" and branding.GameName ~= "" then
		config.Branding = config.Branding or {}
		config.Branding.GAME_NAME = branding.GameName
	end
	if type(branding.LogoImage) == "string" and branding.LogoImage ~= "" then
		config.Branding = config.Branding or {}
		config.Branding.LOGO_IMAGE = branding.LogoImage
	end
	if type(config.Branding) == "table" and type(config.Branding.DEFAULT_LOGO_IMAGE) ~= "string" then
		config.Branding.DEFAULT_LOGO_IMAGE = "rbxassetid://79426970537296"
	end

	local group = clubKit.Group or {}
	if type(config.Group) == "table" then
		if type(group.GroupId) == "number" and group.GroupId > 0 then
			config.Group.GROUP_ID = group.GroupId
		end
		if type(group.OwnerUserId) == "number" and group.OwnerUserId > 0 then
			config.Group.OWNER_USER_ID = group.OwnerUserId
		end
		config.Group.OWNER_GROUP_RANK = group.OwnerGroupRank or 255
	end

	local joinCommunity = clubKit.JoinCommunity
	if type(config.JoinCommunityPrompt) == "table" and type(joinCommunity) == "table" then
		local memberInfoUrl = joinCommunity.MemberInfoUrl or joinCommunity.MEMBER_INFO_URL
		if type(memberInfoUrl) == "string" then
			config.JoinCommunityPrompt.MEMBER_INFO_URL = memberInfoUrl
		end
	end

	config.AdminUserIds = clubKit.AdminUserIds or {}
	config.TopSpenders = clubKit.TopSpenders or {}

	local gameDataApi = clubKit.GameDataApi
	if type(config.GameDataApi) == "table" and type(gameDataApi) == "table" then
		if type(gameDataApi.GameKey) == "string" and gameDataApi.GameKey ~= "" then
			config.GameDataApi.GAME_KEY = gameDataApi.GameKey
		end
	end

	local donation = clubKit.Donation
	if type(config.Donation) == "table" and type(donation) == "table" then
		local providerKey = DonationProviderDomain.inferProviderKey(donation)
		DonationProviderDomain.applyToConfig(config.Donation, providerKey)
		if type(donation.ProviderLink) == "string" then
			config.Donation.PROVIDER_LINK = donation.ProviderLink
			config.Donation.SAWERIA_LINK = donation.ProviderLink
			config.Donation.BAGIBAGI_LINK = donation.ProviderLink
		end
		if type(donation.ApiUrl) == "string" then
			config.Donation.API_URL = donation.ApiUrl
			config.Donation.SHEETS_WEB_APP_URL = donation.ApiUrl
		end
		if type(donation.RobuxProducts) == "table" then
			config.Donation.ROBUX_PRODUCTS = donation.RobuxProducts
		end
		if type(donation.MinAmount) == "number" and donation.MinAmount >= 0 then
			config.Donation.MIN_AMOUNT = donation.MinAmount
		end
		local auraTiers = donation.AuraTiers or donation.RobuxAuraTiers
		if type(auraTiers) == "table" and #auraTiers > 0 then
			config.Donation.AURA_TIERS = auraTiers
			config.Donation.ROBUX_EFFECT_TIERS = auraTiers
		end
		local worldTiers = donation.WorldEffectTiers or donation.SaweriaWorldTiers
		if type(worldTiers) == "table" and #worldTiers > 0 then
			config.Donation.WORLD_EFFECT_TIERS = worldTiers
			config.Donation.SAWERIA_NUKE_TIERS = worldTiers
		end
		if typeof(donation.NukeWorldPosition) == "Vector3" then
			config.Donation.NUKE_WORLD_POSITION = donation.NukeWorldPosition
		end
	end

	local carry = clubKit.Carry
	if type(config.Carry) == "table" and type(carry) == "table" then
		if type(carry.StyleOrder) == "table" and #carry.StyleOrder > 0 then
			config.Carry.STYLE_ORDER = carry.StyleOrder
		end
		if type(carry.MaxDistance) == "number" and carry.MaxDistance > 0 then
			config.Carry.MAX_DISTANCE = carry.MaxDistance
		end
		if type(carry.Styles) == "table" then
			for styleName, styleOverride in pairs(carry.Styles) do
				if type(styleOverride) ~= "table" then
					continue
				end
				local baseStyle = config.Carry.STYLES[styleName]
				if type(baseStyle) == "table" then
					config.Carry.STYLES[styleName] = deepMerge(baseStyle, styleOverride)
				else
					config.Carry.STYLES[styleName] = styleOverride
				end
			end
		end
	end

	local loading = clubKit.Loading
	if type(config.Loading) == "table" and type(loading) == "table" then
		if type(loading.CinematicAnimationId) == "string" and loading.CinematicAnimationId ~= "" then
			if type(config.Loading.CINEMATIC) == "table" then
				config.Loading.CINEMATIC.ANIMATION_ID = loading.CinematicAnimationId
			end
		end
	end

	local membership = clubKit.Membership
	if type(config.Membership) == "table" and type(membership) == "table" then
		for tierKey, tierOverride in pairs(membership) do
			if type(tierOverride) == "table" and type(config.Membership.Tiers[tierKey]) == "table" then
				if type(tierOverride.Label) == "string" and tierOverride.Label ~= "" then
					config.Membership.Tiers[tierKey].label = tierOverride.Label
					config.Membership.Tiers[tierKey].rankText = string.upper(tierOverride.Label)
					config.Membership.Tiers[tierKey].chatTag = string.upper(tierOverride.Label)
					if type(config.MembershipChatLabel) == "table" then
						config.MembershipChatLabel[tierKey] = tierOverride.Label
					end
				end
				if type(tierOverride.Priority) == "number" then
					config.Membership.Tiers[tierKey].priority = tierOverride.Priority
				end
			end
			if type(config.Membership.PAID_TIERS) == "table" and type(tierOverride) == "table" then
				if tierOverride.Enabled == false then
					config.Membership.PAID_TIERS[tierKey] = false
				elseif tierOverride.Enabled == true then
					config.Membership.PAID_TIERS[tierKey] = true
				end
			end
		end
	end

	local shop = clubKit.Shop
	if type(config.Shop) == "table" and type(shop) == "table" and type(shop.Products) == "table" then
		for tierKey, product in pairs(shop.Products) do
			if type(config.Shop.PRODUCTS[tierKey]) == "table" and type(product) == "table" then
				-- Prefer BuyGamePassId (self-buy). BuyId kept as legacy Dev Product for ProcessReceipt.
				if type(product.BuyGamePassId) == "number" and product.BuyGamePassId > 0 then
					config.Shop.PRODUCTS[tierKey].BUY_GAMEPASS_ID = product.BuyGamePassId
				end
				if type(product.BuyId) == "number" and product.BuyId > 0 then
					config.Shop.PRODUCTS[tierKey].BUY_ID = product.BuyId
				end
				if type(product.GiftId) == "number" and product.GiftId > 0 then
					config.Shop.PRODUCTS[tierKey].GIFT_ID = product.GiftId
				end
				if type(config.Shop.CATALOG[tierKey]) == "table" then
					if type(product.Price) == "number" and product.Price > 0 then
						config.Shop.CATALOG[tierKey].price = product.Price
					end
					local tierLabel = config.Membership.Tiers[tierKey] and config.Membership.Tiers[tierKey].label
					if type(tierLabel) == "string" and tierLabel ~= "" then
						config.Shop.CATALOG[tierKey].name = tierLabel
					end
				end
			end
		end
	end

	local paidBroadcast = clubKit.PaidBroadcast
	if type(config.PaidBroadcast) == "table" and type(paidBroadcast) == "table" then
		local productId = tonumber(paidBroadcast.ProductId)
		if productId and productId > 0 then
			config.PaidBroadcast.PRODUCT_ID = productId
		end
	end

	local features = clubKit.Features
	if type(config.FeatureFlags) == "table" and type(features) == "table" then
		local map = {
			MusicPlayer = "MusicPlayerEnabled",
			SyncDance = "SyncDanceEnabled",
			Hotbar = "HotbarEnabled",
			LoadingScreen = "LoadingScreenEnabled",
			LevelSystem = "LevelSystemEnabled",
			Settings = "SettingsEnabled",
			Shop = "ShopEnabled",
			Couples = "CouplesEnabled",
			Stickers = "StickersEnabled",
			Leaderboards = "LeaderboardEnabled",
			DonationCash = "DonationCashEnabled",
			DonationSaweria = "DonationSaweriaEnabled",
			DonationRobux = "DonationRobuxEnabled",
			Gravity = "GravityEnabled",
			PromptJoinCommunityOnLoad = "PromptJoinCommunityOnLoadEnabled",
			VipOnCommunityJoin = "VipOnCommunityJoinEnabled",
			JoinGreetings = "JoinGreetingsEnabled",
		}
		for sourceKey, targetKey in pairs(map) do
			if type(features[sourceKey]) == "boolean" then
				config.FeatureFlags[targetKey] = features[sourceKey]
			end
		end
		-- Overhead donation chip gradient anim (not a FeatureFlags module kill-switch).
		if type(features.DonationRankGradientAnim) == "boolean" and type(config.Overhead) == "table" then
			config.Overhead.ANIMATE_DONATION_RANK_GRADIENT = features.DonationRankGradientAnim
		end
	end

	if type(donation) == "table" then
		local cashDisabled = false
		if type(donation.Cash) == "table" and donation.Cash.Enabled == false then
			cashDisabled = true
		end
		if type(donation.Saweria) == "table" and donation.Saweria.Enabled == false then
			cashDisabled = true
		end
		if type(features) == "table" then
			if features.DonationCash == false or features.DonationSaweria == false then
				cashDisabled = true
			end
		end
		if cashDisabled then
			config.FeatureFlags.DonationCashEnabled = false
			config.FeatureFlags.DonationSaweriaEnabled = false
		elseif type(config.FeatureFlags.DonationCashEnabled) == "boolean" then
			config.FeatureFlags.DonationSaweriaEnabled = config.FeatureFlags.DonationCashEnabled
		end
		if type(donation.Robux) == "table" and donation.Robux.Enabled == false then
			config.FeatureFlags.DonationRobuxEnabled = false
		end
	end

	local showcase = clubKit.Showcase
	if type(config.Demo) == "table" and type(showcase) == "table" then
		if type(showcase.Enabled) == "boolean" then
			config.Demo.ENABLED = showcase.Enabled
		end
		if type(showcase.SourceUserId) == "number" then
			config.Demo.SOURCE_USER_ID = showcase.SourceUserId
		end
		if type(showcase.LeaderboardUseOwnerOnly) == "boolean" then
			config.Demo.LEADERBOARD_USE_OWNER_ONLY = showcase.LeaderboardUseOwnerOnly
		end
		if type(showcase.MinAmount) == "number" then
			config.Demo.MIN_AMOUNT = showcase.MinAmount
		end
		if type(showcase.MaxAmount) == "number" then
			config.Demo.MAX_AMOUNT = showcase.MaxAmount
		end
		if type(showcase.RobuxMinAmount) == "number" then
			config.Demo.ROBUX_MIN_AMOUNT = showcase.RobuxMinAmount
		end
		if type(showcase.RobuxMaxAmount) == "number" then
			config.Demo.ROBUX_MAX_AMOUNT = showcase.RobuxMaxAmount
		end
		if type(showcase.LeaderboardLimit) == "number" then
			config.Demo.LEADERBOARD_LIMIT = showcase.LeaderboardLimit
		end
		if type(showcase.RefreshInterval) == "number" then
			config.Demo.REFRESH_INTERVAL = showcase.RefreshInterval
		end
		if type(showcase.Profiles) == "table" then
			local profiles = {}
			for _, profile in ipairs(showcase.Profiles) do
				if type(profile) == "table" and type(profile.UserId) == "number" and profile.UserId > 0 then
					table.insert(profiles, {
						userId = profile.UserId,
						username = profile.Username or ("User" .. tostring(profile.UserId)),
						displayName = profile.DisplayName or profile.Username or ("User" .. tostring(profile.UserId)),
					})
				end
			end
			if #profiles > 0 then
				config.Demo.SHOWCASE_PROFILES = profiles
			end
		end
		if type(showcase.Communities) == "table" then
			local communities = {}
			for _, community in ipairs(showcase.Communities) do
				if type(community) == "table" and type(community.CommunityId) == "number" then
					table.insert(communities, {
						communityId = community.CommunityId,
						communityName = community.CommunityName or ("Community " .. tostring(community.CommunityId)),
						communityLogo = community.CommunityLogo or "",
					})
				end
			end
			if #communities > 0 then
				config.Demo.SHOWCASE_COMMUNITIES = communities
			end
		end
	end

	local builtRoles = RoleCategoryBuilder.build(clubKit)
	config.RoleCategories = clubKit.RoleCategories
	config.SpenderRoles = clubKit.SpenderRoles
	config.Roles = builtRoles
	config.Group.RANK_MAP = RoleCategoryBuilder.buildRankMap(
		builtRoles.DEFINITIONS,
		(group :: any).OwnerGroupRank
	)
	config.RolePrivileges = {
		ROLE_TO_CATEGORY = builtRoles.ROLE_TO_CATEGORY,
		CATEGORY_PRIVILEGES = builtRoles.CATEGORY_PRIVILEGES,
	}
end

return ConfigBootstrap
