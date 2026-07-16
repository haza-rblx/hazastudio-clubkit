--!strict
-- Pure functions only. Zero Roblox service calls.

local Config = require(script.Parent.Parent.Constants.Config)
local RolesDomain = require(script.Parent.RolesDomain)
local PermissionDomain = require(script.Parent.PermissionDomain)
local TitleStyleDomain = require(script.Parent.TitleStyleDomain)
local TitleFontUtil = require(script.Parent.Parent.Utils.TitleFontUtil)
local Types = require(script.Parent.Types)
local LevelDomain = require(script.Parent.LevelDomain)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TitleColorPreset = require(ReplicatedStorage.Hazastudio_ClubKit.OverheadEffects.TitleColorPreset)
local AnimationModes = TitleColorPreset.AnimationModes

type RoleKey = Types.RoleKey
type MembershipTier = Types.MembershipTier
type GiftedMembershipEntry = Types.GiftedMembershipEntry
type TitleSizeKey = Types.TitleSizeKey
type TitleStyleData = Types.TitleStyleData
type CommunityData = Types.CommunityData
type OverheadPayload = Types.OverheadPayload
type OverheadStoredData = Types.OverheadStoredData
type ProfileRelationshipMode = Types.ProfileRelationshipMode

local OverheadDomain = {}

local function buildRoleFlagMap(flagName: string): { [string]: true }
	local map: { [string]: true } = {}
	local rolesConfig = Config.Roles
	if type(rolesConfig) == "table" and type(rolesConfig.DEFINITIONS) == "table" then
		for roleKey, definition in pairs(rolesConfig.DEFINITIONS) do
			if type(definition) ~= "table" then
				continue
			end
			local enabled = definition[flagName] == true
			if flagName == "giftable" and definition.setroleOnly == true and definition.giftable ~= false then
				enabled = true
			end
			if flagName == "canGift" and PermissionDomain.hasPermission(roleKey, "canGift") then
				enabled = true
			end
			if enabled then
				map[roleKey] = true
			end
		end
		if type(rolesConfig.LEGACY_ALIASES) == "table" then
			for legacyKey, canonical in pairs(rolesConfig.LEGACY_ALIASES) do
				if map[canonical] then
					map[legacyKey] = true
				end
			end
		end
	end
	return map
end

local VALID_ROLES: { [string]: true } = (function()
	local map: { [string]: true } = {}
	local rolesConfig = Config.Roles
	if type(rolesConfig) == "table" then
		if type(rolesConfig.DEFINITIONS) == "table" then
			for roleKey in pairs(rolesConfig.DEFINITIONS) do
				map[roleKey] = true
			end
		end
		if type(rolesConfig.LEGACY_ALIASES) == "table" then
			for legacyKey in pairs(rolesConfig.LEGACY_ALIASES) do
				map[legacyKey] = true
			end
		end
	end
	return map
end)()

local VALID_MEMBERSHIP_TIERS: { [string]: true } = {
	Tier3 = true,
	Tier2 = true,
	Tier1 = true,
	ELITEMember = true,
	VVIPMember = true,
	VIPMember = true,
	Member = true,
	Guest = true,
}

local VALID_FONTS: { [string]: true } = (function()
	local map: { [string]: true } = {}
	for _, fontName in ipairs(TitleFontUtil.getConfiguredFonts()) do
		map[fontName] = true
	end
	return map
end)()

local GIFTER_ROLES: { [string]: true } = buildRoleFlagMap("canGift")
local GIFTABLE_ROLES: { [string]: true } = buildRoleFlagMap("giftable")

local DEFAULT_PUBLIC_LAYER_VISIBLE: { [string]: boolean } = {
	SpecialTitle = true,
	BadgeGroup = true,
	Level = true,
	SpecialRank = true,
	SpecialStatus = true,
	TopSpender = true,
	TopDonate = true,
	Rank = true,
	DisplayName = true,
	CoupleName = false,
}

local DEFAULT_PUBLIC_BADGE_VISIBLE: { [string]: boolean } = {
	OwnerCoOwner = true,
	Developer = true,
	Admin = true,
	Member = true,
	VIP = true,
	VVIP = true,
	Elite = true,
	Streak = true,
	LikeCounter = true,
	Community = true,
}

local function sanitizeBoolMap(raw: any, defaults: { [string]: boolean }): { [string]: boolean }
	local result = table.clone(defaults)
	if type(raw) ~= "table" then
		return result
	end
	for key, defaultValue in pairs(defaults) do
		if type(raw[key]) == "boolean" then
			result[key] = raw[key]
		else
			result[key] = defaultValue
		end
	end
	return result
end

local function getTierConfig(tier: string?): any?
	if type(tier) ~= "string" then
		return nil
	end
	local tiers = Config.Membership and Config.Membership.Tiers
	if type(tiers) ~= "table" then
		return nil
	end
	return tiers[tier]
end

function OverheadDomain.normalizeMembershipTier(rawTier: any): MembershipTier?
	if type(rawTier) ~= "string" or rawTier == "" then
		return nil
	end

	local aliases = Config.Membership and Config.Membership.ALIASES
	local alias = if type(aliases) == "table"
		then aliases[rawTier] or aliases[string.lower(rawTier)]
		else nil
	local tier = if type(alias) == "string" then alias else rawTier
	if getTierConfig(tier) then
		return tier :: MembershipTier
	end

	local tiers = Config.Membership and Config.Membership.Tiers
	if type(tiers) == "table" then
		local lowered = string.lower(rawTier)
		for key, cfg in pairs(tiers) do
			if type(key) == "string" and type(cfg) == "table" then
				local label = cfg.label
				local chatTag = cfg.chatTag
				if type(label) == "string" and string.lower(label) == lowered then
					return key :: MembershipTier
				end
				if type(chatTag) == "string" and string.lower(chatTag) == lowered then
					return key :: MembershipTier
				end
			end
		end
	end
	return nil
end

function OverheadDomain.isPaidMembershipTier(tier: string): boolean
	local normalized = OverheadDomain.normalizeMembershipTier(tier)
	if not normalized then
		return false
	end
	local paid = Config.Membership and Config.Membership.PAID_TIERS
	return type(paid) == "table" and paid[normalized] == true
end

local function resolveRoleFromRankId(rankId: number, excludeRole: string?): RoleKey
	local direct = Config.Group.RANK_MAP[rankId]
	if direct and direct ~= excludeRole then
		return direct :: RoleKey
	end

	local bestRankId = -1
	local bestRole: RoleKey = "Guest"
	for rid, rkey in pairs(Config.Group.RANK_MAP) do
		if rkey ~= excludeRole and rid <= rankId and rid > bestRankId then
			bestRankId = rid
			bestRole = rkey :: RoleKey
		end
	end
	return bestRole
end

function OverheadDomain.resolveRole(rankId: number, userId: number?): RoleKey
	local ownerUserId = Config.Group.OWNER_USER_ID
	if type(ownerUserId) == "number" and ownerUserId > 0 and userId == ownerUserId then
		return "Owner"
	end

	local role = resolveRoleFromRankId(rankId, nil)
	if role == "Owner" and type(ownerUserId) == "number" and ownerUserId > 0 then
		return resolveRoleFromRankId(rankId, "Owner")
	end
	return role
end

function OverheadDomain.isValidRole(role: string): boolean
	if VALID_ROLES[role] then
		return true
	end
	return RolesDomain.isValidRole(role)
end

function OverheadDomain.isMembershipTier(tier: string): boolean
	return VALID_MEMBERSHIP_TIERS[tier] == true or OverheadDomain.normalizeMembershipTier(tier) ~= nil
end

function OverheadDomain.normalizeRoleKey(rawRole: any): RoleKey?
	if type(rawRole) ~= "string" or rawRole == "" then
		return nil
	end

	local canonical = RolesDomain.normalizeRoleKey(rawRole)
	if canonical then
		return canonical :: RoleKey
	end

	local membershipTier = OverheadDomain.normalizeMembershipTier(rawRole)
	if membershipTier and VALID_ROLES[membershipTier] then
		return membershipTier :: RoleKey
	end

	local lowered = string.lower(rawRole)
	local withoutMember = lowered:match("^(.-)%s+member$")
	if withoutMember and withoutMember ~= "" then
		membershipTier = OverheadDomain.normalizeMembershipTier(withoutMember)
		if membershipTier and VALID_ROLES[membershipTier] then
			return membershipTier :: RoleKey
		end
	end

	return nil
end

function OverheadDomain.getMembershipValue(tier: MembershipTier): number
	local normalized = OverheadDomain.normalizeMembershipTier(tier)
	local cfg = getTierConfig(normalized)
	return tonumber(cfg and cfg.value) or Config.MembershipTierValue[tier] or 0
end

function OverheadDomain.getMembershipChatLabel(tier: MembershipTier): string
	local normalized = OverheadDomain.normalizeMembershipTier(tier)
	local cfg = getTierConfig(normalized)
	return tostring((cfg and cfg.label) or Config.MembershipChatLabel[tier] or tier)
end

function OverheadDomain.getMembershipRankText(tier: MembershipTier): string
	local normalized = OverheadDomain.normalizeMembershipTier(tier)
	local cfg = getTierConfig(normalized)
	if cfg and Config.Membership and Config.Membership.USE_LABEL_FOR_RANK_TEXT == true then
		local label = tostring(cfg.label or normalized or tier)
		if normalized == "Tier1" or normalized == "Tier2" or normalized == "Tier3" then
			return string.upper(label) .. " MEMBER"
		end
		return string.upper(label)
	end
	return tostring((cfg and cfg.rankText) or (Config.RankDisplay[tier] and Config.RankDisplay[tier].text) or tier)
end

function OverheadDomain.getMembershipChatTag(tier: MembershipTier): string
	local normalized = OverheadDomain.normalizeMembershipTier(tier)
	local cfg = getTierConfig(normalized)
	if cfg and Config.Membership and Config.Membership.USE_LABEL_FOR_CHAT_TAG == true then
		return string.upper(tostring(cfg.label or normalized or tier))
	end
	return tostring((cfg and cfg.chatTag) or Config.ChatPrimaryTagLabel[tier] or OverheadDomain.getMembershipChatLabel(tier))
end

function OverheadDomain.getMembershipBadgeFrame(tier: MembershipTier): string?
	local normalized = OverheadDomain.normalizeMembershipTier(tier)
	local cfg = getTierConfig(normalized)
	local frame = (cfg and cfg.badgeFrame) or Config.MembershipBadgeFrame[tier]
	return if type(frame) == "string" and frame ~= "" then frame else nil
end

function OverheadDomain.getMembershipGradientName(tier: MembershipTier): string?
	local normalized = OverheadDomain.normalizeMembershipTier(tier)
	local cfg = getTierConfig(normalized)
	local gradient = cfg and cfg.gradientName
	return if type(gradient) == "string" and gradient ~= "" then gradient else nil
end

function OverheadDomain.getMembershipBadgeSettingKey(tier: MembershipTier): string?
	local normalized = OverheadDomain.normalizeMembershipTier(tier)
	local cfg = getTierConfig(normalized)
	local key = cfg and cfg.badgeSettingKey
	return if type(key) == "string" and key ~= "" then key else nil
end

function OverheadDomain.getRoleDisplayName(role: string): string
	local membershipTier = OverheadDomain.normalizeMembershipTier(role)
	if membershipTier then
		return OverheadDomain.getMembershipChatLabel(membershipTier)
	end
	return Config.ChatPrimaryTagLabel[role] or role
end

function OverheadDomain.getChatPrimaryTag(role: RoleKey, effectiveMembership: MembershipTier): string
	local rolePriority = Config.ChatPrimaryTagPriority[role] or 0
	local membershipPriority = Config.ChatPrimaryTagPriority[effectiveMembership] or 0

	if rolePriority >= membershipPriority then
		local roleMembership = OverheadDomain.normalizeMembershipTier(role)
		if roleMembership then
			return OverheadDomain.getMembershipChatTag(roleMembership)
		end
		return Config.ChatPrimaryTagLabel[role] or role
	end

	return OverheadDomain.getMembershipChatTag(effectiveMembership)
end

function OverheadDomain.getHigherMembership(left: MembershipTier?, right: MembershipTier?): MembershipTier?
	if not left then
		return right
	end
	if not right then
		return left
	end
	if OverheadDomain.getMembershipValue(right) > OverheadDomain.getMembershipValue(left) then
		return right
	end
	return left
end

function OverheadDomain.isGiftableRole(role: string): boolean
	local normalized = OverheadDomain.normalizeRoleKey(role) or role
	return GIFTABLE_ROLES[normalized] == true
end

function OverheadDomain.canGift(role: RoleKey): boolean
	return PermissionDomain.canGift(role, nil)
end

function OverheadDomain.hasMembershipAtLeast(tier: any, requiredTier: any): boolean
	local normalizedTier = OverheadDomain.normalizeMembershipTier(tier)
	local normalizedRequired = OverheadDomain.normalizeMembershipTier(requiredTier)
	if not normalizedTier or not normalizedRequired then
		return false
	end
	return OverheadDomain.getMembershipValue(normalizedTier) >= OverheadDomain.getMembershipValue(normalizedRequired)
end

function OverheadDomain.hasRolePriorityAtLeast(role: any, requiredRole: any): boolean
	local normalizedRole = OverheadDomain.normalizeRoleKey(role)
	local normalizedRequired = OverheadDomain.normalizeRoleKey(requiredRole)
	if not normalizedRole or not normalizedRequired then
		return false
	end
	return (Config.ChatPrimaryTagPriority[normalizedRole] or 0) >= (Config.ChatPrimaryTagPriority[normalizedRequired] or 0)
end

function OverheadDomain.canAnnounce(role: any, effectiveMembership: any): boolean
	return PermissionDomain.canAnnounce(role, effectiveMembership)
end



function OverheadDomain.canTeleportCommand(role: any, effectiveMembership: any): boolean
	return PermissionDomain.canTeleport(role, effectiveMembership)
end

function OverheadDomain.normalizeGiftedMemberships(stored: OverheadStoredData): { GiftedMembershipEntry }
	local result = {} :: { GiftedMembershipEntry }
	local rawEntries = stored.giftedMemberships or {}

	for _, entry in ipairs(rawEntries) do
		local normalizedTier = if type(entry) == "table" then OverheadDomain.normalizeMembershipTier(entry.tier) else nil
		if type(entry) == "table" and normalizedTier then
			table.insert(result, {
				tier = normalizedTier,
				grantedBy = type(entry.grantedBy) == "number" and entry.grantedBy or nil,
				grantedAt = type(entry.grantedAt) == "number" and entry.grantedAt or 0,
				source = type(entry.source) == "string" and entry.source or nil,
			})
		end
	end

	return result
end

function OverheadDomain.getHighestGiftedMembership(stored: OverheadStoredData): MembershipTier?
	local highest: MembershipTier? = nil
	for _, entry in ipairs(OverheadDomain.normalizeGiftedMemberships(stored)) do
		highest = OverheadDomain.getHigherMembership(highest, entry.tier)
	end
	return highest
end

function OverheadDomain.getHighestStoredMembership(stored: OverheadStoredData): MembershipTier?
	local highest: MembershipTier? = nil

	local ownedMembership = OverheadDomain.normalizeMembershipTier(stored.ownedMembership)
	if ownedMembership then
		highest = OverheadDomain.getHigherMembership(highest, ownedMembership)
	end

	-- Legacy compatibility for older data and current shop flow.
	local membershipBadge = OverheadDomain.normalizeMembershipTier(stored.membershipBadge)
	if membershipBadge then
		highest = OverheadDomain.getHigherMembership(highest, membershipBadge)
	end

	return OverheadDomain.getHigherMembership(highest, OverheadDomain.getHighestGiftedMembership(stored))
end

function OverheadDomain.resolveEffectiveMembership(stored: OverheadStoredData, rankId: number, userId: number?): MembershipTier
	local highestStored: MembershipTier? = OverheadDomain.getHighestStoredMembership(stored)
	if highestStored then
		return highestStored
	end
	return "Guest"
end

function OverheadDomain.hasStoredMembershipAtLeast(stored: OverheadStoredData, tier: MembershipTier): boolean
	local highest: MembershipTier? = OverheadDomain.getHighestStoredMembership(stored)
	if not highest then
		return false
	end
	return OverheadDomain.getMembershipValue(highest) >= OverheadDomain.getMembershipValue(tier)
end

local ELITE_MEMBER_BADGE_FRAME = "07-ELITEMemberBadge"

local function getLeaderboardBadgeLimit(spenderType: string?): number
	local maxRank = 0
	local spenderRoles = Config.SpenderRoles
	if type(spenderRoles) == "table" then
		if type(spenderType) == "string" then
			local spender = spenderRoles[spenderType]
			if type(spender) == "table" and spender.Enabled ~= false then
				maxRank = tonumber(spender.MaxRank) or 0
			end
		else
			for _, key in ipairs({ "CashSpender", "RobuxSpender" }) do
				local spender = spenderRoles[key]
				if type(spender) == "table" and spender.Enabled ~= false then
					maxRank = math.max(maxRank, tonumber(spender.MaxRank) or 0)
				end
			end
		end
	end
	if maxRank > 0 then
		return maxRank
	end
	local limit = Config.Donation and Config.Donation.LEADERBOARD_LIMIT
	if type(limit) ~= "number" or limit < 1 then
		return 10
	end
	return limit
end

local function isActiveLeaderboardRank(rank: number?, spenderType: string?): boolean
	return type(rank) == "number" and rank >= 1 and rank <= getLeaderboardBadgeLimit(spenderType)
end

function OverheadDomain.shouldShowEliteMemberBadge(stored: OverheadStoredData, role: RoleKey): boolean
	-- Elite/Tier3 badge is granted ONLY by an actual Tier3 membership (stored) or
	-- the equivalent Exclusive/Supreme role. Top Robux/Rupiah leaderboard rank
	-- (topDonateRank/topSpenderRank) intentionally does NOT grant this badge.
	if role == "Supreme" or role == "Exclusive" then
		return true
	end
	return OverheadDomain.hasStoredMembershipAtLeast(stored, "Tier3")
end

function OverheadDomain.normalizeLeaderboardRank(rank: any, spenderType: string?): number?
	if isActiveLeaderboardRank(rank, spenderType) then
		return rank :: number
	end
	return nil
end

function OverheadDomain.hasGiftedMembership(stored: OverheadStoredData, tier: MembershipTier): boolean
	local normalizedTier = OverheadDomain.normalizeMembershipTier(tier) or tier
	for _, entry in ipairs(OverheadDomain.normalizeGiftedMemberships(stored)) do
		if entry.tier == normalizedTier then
			return true
		end
	end
	return false
end

function OverheadDomain.addGiftedMembership(
	stored: OverheadStoredData,
	tier: MembershipTier,
	grantedBy: number,
	source: string
): OverheadStoredData
	local normalizedTier = OverheadDomain.normalizeMembershipTier(tier) or tier
	local copy = table.clone(stored :: any) :: OverheadStoredData
	local entries = OverheadDomain.normalizeGiftedMemberships(stored)
	table.insert(entries, {
		tier = normalizedTier,
		grantedBy = grantedBy,
		grantedAt = os.time(),
		source = source,
	})
	copy.giftedMemberships = entries
	copy._version = stored._version + 1
	return copy
end

function OverheadDomain.removeGiftedMembership(
	stored: OverheadStoredData,
	tier: MembershipTier
): (OverheadStoredData, boolean)
	local normalizedTier = OverheadDomain.normalizeMembershipTier(tier) or tier
	local entries = OverheadDomain.normalizeGiftedMemberships(stored)
	local removed = false
	local remaining = {} :: { GiftedMembershipEntry }

	for _, entry in ipairs(entries) do
		if not removed and entry.tier == normalizedTier then
			removed = true
		else
			table.insert(remaining, entry)
		end
	end

	if not removed then
		return stored, false
	end

	local copy = table.clone(stored :: any) :: OverheadStoredData
	copy.giftedMemberships = #remaining > 0 and remaining or nil
	copy._version = stored._version + 1
	return copy, true
end

function OverheadDomain.resolveVisibleBadges(role: RoleKey, membershipTier: MembershipTier?): { string }
	local badges = Config.BadgeVisibility[role] or {}
	local result = table.clone(badges)

	local normalizedTier = OverheadDomain.normalizeMembershipTier(membershipTier)
	if normalizedTier and normalizedTier ~= "Guest" then
		local badgeFrame = OverheadDomain.getMembershipBadgeFrame(normalizedTier)
		if badgeFrame then
			local alreadyHas = false
			for _, badgeName in ipairs(result) do
				if badgeName == badgeFrame then
					alreadyHas = true
					break
				end
			end
			if not alreadyHas then
				table.insert(result, badgeFrame)
			end
		end
	end

	return result
end

function OverheadDomain.defaultStoredData(): OverheadStoredData
	return {
		specialTitle = nil,
		specialTitlePreset = nil,
		specialTitleSize = nil,
		specialTitleFont = nil,
		specialTitleStyle = nil,
		specialTitlePosition = Config.Admin.DEFAULT_SPECIAL_TITLE_POSITION or "Top",
		specialRank = nil,
		specialSubRole = nil,
		giftedRole = nil,
		membershipBadge = nil,
		ownedMembership = nil,
		giftedMemberships = nil,
		giftedBy = nil,
		giftedAt = nil,
		coupleData = nil,
		couplePartner = nil,
		couplePartnerId = nil,
		showCoupleName = true,
		publicOverheadLayerVisible = table.clone(DEFAULT_PUBLIC_LAYER_VISIBLE),
		publicOverheadBadgeVisible = table.clone(DEFAULT_PUBLIC_BADGE_VISIBLE),
		topDonateRank = nil,
		topDonateText = nil,
		topSpenderRank = nil,
		topSpenderText = nil,
		communityId = nil,
		suppressCommunityBadge = false,
		streakDays = 0,
		lastLoginAt = 0,
		level = 1,
		xp = 0,
		_version = 1,
	}
end

function OverheadDomain.applyHardcoded(stored: OverheadStoredData, userId: number): OverheadStoredData
	local hardcoded = Config.Hardcoded[userId]
	if not hardcoded then
		return stored
	end

	return {
		specialTitle = hardcoded.specialTitle or stored.specialTitle,
		specialTitlePreset = nil,
		specialTitleSize = stored.specialTitleSize,
		specialTitleFont = stored.specialTitleFont,
		specialTitleStyle = stored.specialTitleStyle,
		specialTitlePosition = stored.specialTitlePosition,
		specialRank = hardcoded.specialRank or stored.specialRank,
		giftedRole = stored.giftedRole,
		membershipBadge = stored.membershipBadge,
		ownedMembership = stored.ownedMembership,
		giftedMemberships = stored.giftedMemberships,
		giftedBy = stored.giftedBy,
		giftedAt = stored.giftedAt,
		coupleData = stored.coupleData,
		couplePartner = stored.couplePartner,
		couplePartnerId = stored.couplePartnerId,
		showCoupleName = stored.showCoupleName,
		publicOverheadLayerVisible = sanitizeBoolMap(stored.publicOverheadLayerVisible, DEFAULT_PUBLIC_LAYER_VISIBLE),
		publicOverheadBadgeVisible = sanitizeBoolMap(stored.publicOverheadBadgeVisible, DEFAULT_PUBLIC_BADGE_VISIBLE),
		topDonateRank = stored.topDonateRank,
		topDonateText = stored.topDonateText,
		topSpenderRank = stored.topSpenderRank,
		topSpenderText = stored.topSpenderText,
		communityId = stored.communityId,
		suppressCommunityBadge = stored.suppressCommunityBadge,
		streakDays = stored.streakDays,
		lastLoginAt = stored.lastLoginAt,
		level = stored.level,
		xp = stored.xp,
		_version = stored._version,
	}
end

function OverheadDomain.applyGift(stored: OverheadStoredData, roleKey: RoleKey, giftedBy: number): OverheadStoredData
	local normalizedRole = OverheadDomain.normalizeRoleKey(roleKey) or roleKey
	local copy = table.clone(stored :: any) :: OverheadStoredData
	copy.giftedRole = normalizedRole
	copy.giftedBy = giftedBy
	copy.giftedAt = os.time()
	copy._version = stored._version + 1
	return copy
end

function OverheadDomain.removeGift(stored: OverheadStoredData): OverheadStoredData
	local copy = table.clone(stored :: any) :: OverheadStoredData
	copy.giftedRole = nil
	copy.giftedBy = nil
	copy.giftedAt = nil
	copy._version = stored._version + 1
	return copy
end

function OverheadDomain.buildPayload(
	userId: number,
	displayName: string,
	rankId: number,
	stored: OverheadStoredData,
	communityData: CommunityData?,
	likesCount: number,
	robuxDonated: number,
	cashDonated: number,
	relationshipMode: ProfileRelationshipMode?,
	statusText: string?,
	hasRobloxPremium: boolean?
): OverheadPayload
	local role: RoleKey
	local storedGiftedRole = OverheadDomain.normalizeRoleKey(stored.giftedRole)
	if storedGiftedRole and OverheadDomain.isValidRole(storedGiftedRole) then
		role = storedGiftedRole
	else
		role = OverheadDomain.resolveRole(rankId, userId)
	end

	local specialRankCfg = Config.SpecialRank[role]
	local specialRankText: string? = nil
	local specialRankGradient = false
	local roleCanShowSpecialStatus = RolesDomain.roleShowsSpecialStatus(role)
	local specialStatusText = if roleCanShowSpecialStatus and statusText and statusText ~= "" then statusText else nil

	if stored.specialRank then
		specialRankText = stored.specialRank
		specialRankGradient = true
	elseif specialRankCfg then
		specialRankText = specialRankCfg.text
		specialRankGradient = specialRankCfg.gradient
	end

	local effectiveMembership: MembershipTier = OverheadDomain.resolveEffectiveMembership(stored, rankId, userId)
	local roleMembership = OverheadDomain.normalizeMembershipTier(role)
	effectiveMembership = (OverheadDomain.getHigherMembership(effectiveMembership, roleMembership) or effectiveMembership) :: MembershipTier
	if communityData then
		effectiveMembership = (OverheadDomain.getHigherMembership(effectiveMembership, "Tier1") or effectiveMembership) :: MembershipTier
	end
	local membershipLabel = OverheadDomain.getMembershipChatLabel(effectiveMembership)
	local membershipRankText = OverheadDomain.getMembershipRankText(effectiveMembership)
	local membershipChatTag = OverheadDomain.getMembershipChatTag(effectiveMembership)
	local membershipBadgeFrame = OverheadDomain.getMembershipBadgeFrame(effectiveMembership)
	local membershipGradientName = OverheadDomain.getMembershipGradientName(effectiveMembership)
	local rankText = membershipRankText
	local rankCfg = Config.RankDisplay[effectiveMembership]
	local rankGradient = if rankCfg then rankCfg.gradient == true else false

	local highestMembership: MembershipTier? = OverheadDomain.getHighestStoredMembership(stored)
	local visibleMembership = OverheadDomain.getHigherMembership(highestMembership, roleMembership)
	if communityData then
		visibleMembership = OverheadDomain.getHigherMembership(visibleMembership, "Tier1")
	end
	local visibleBadges: { string } = OverheadDomain.resolveVisibleBadges(role, visibleMembership)
	if stored.specialSubRole == "DJ" then
		local copy = table.clone(visibleBadges)
		table.insert(copy, "11-DJBadge")
		visibleBadges = copy
	elseif stored.specialSubRole == "Influencer" then
		local copy = table.clone(visibleBadges)
		table.insert(copy, "12-InfluencerBadge")
		visibleBadges = copy
	end

	if not visibleMembership and rankId > 0 then
		local memberFrame = OverheadDomain.getMembershipBadgeFrame("Member")
		if memberFrame then
			local alreadyHas = false
			for _, badgeName in ipairs(visibleBadges) do
				if badgeName == memberFrame then
					alreadyHas = true
					break
				end
			end
			if not alreadyHas then
				local copy = table.clone(visibleBadges)
				table.insert(copy, memberFrame)
				visibleBadges = copy
			end
		end
	end

	if stored.streakDays >= Config.Streak.MIN_DAYS then
		local hasStreak = false
		for _, badgeName in ipairs(visibleBadges) do
			if badgeName == "08-StreakBadge" then
				hasStreak = true
				break
			end
		end
		if not hasStreak then
			local copy = table.clone(visibleBadges)
			table.insert(copy, "08-StreakBadge")
			visibleBadges = copy
		end
	end

	if communityData and communityData.logo and communityData.logo ~= "" then
		local hasCommunityBadge = false
		for _, badgeName in ipairs(visibleBadges) do
			if badgeName == "10-CommunityBadge" then
				hasCommunityBadge = true
				break
			end
		end
		if not hasCommunityBadge then
			local copy = table.clone(visibleBadges)
			table.insert(copy, "10-CommunityBadge")
			visibleBadges = copy
		end
	end

	if likesCount > 0 then
		local hasLikeBadge = false
		for _, badgeName in ipairs(visibleBadges) do
			if badgeName == "09-LikeCounterBadge" then
				hasLikeBadge = true
				break
			end
		end
		if not hasLikeBadge then
			local copy = table.clone(visibleBadges)
			table.insert(copy, "09-LikeCounterBadge")
			visibleBadges = copy
		end
	end

	-- Elite badge: membership Tier3 (stored / role Exclusive) only — not from top Robux/Rupiah rank.
	-- Selalu strip dulu dari resolveVisibleBadges/BadgeVisibility supaya tidak bocor ke rank lain.
	do
		local filtered: { string } = {}
		for _, badgeName in ipairs(visibleBadges) do
			if badgeName ~= ELITE_MEMBER_BADGE_FRAME then
				table.insert(filtered, badgeName)
			end
		end
		visibleBadges = filtered
		if OverheadDomain.shouldShowEliteMemberBadge(stored, role) then
			table.insert(visibleBadges, ELITE_MEMBER_BADGE_FRAME)
		end
	end


	local isCoupled = stored.couplePartner ~= nil or stored.couplePartnerId ~= nil
	local showCoupleName = stored.showCoupleName ~= false
	local publicLayerVisible = sanitizeBoolMap(stored.publicOverheadLayerVisible, DEFAULT_PUBLIC_LAYER_VISIBLE)
	local publicBadgeVisible = sanitizeBoolMap(stored.publicOverheadBadgeVisible, DEFAULT_PUBLIC_BADGE_VISIBLE)
	local resolvedRelationshipMode = if relationshipMode == "Fun"
		then "Fun"
		elseif relationshipMode == "Single" then "Single"
		elseif relationshipMode == "Taken" and isCoupled then "Taken"
		else if isCoupled then "Taken" else "Single"

	local resolvedLevel = if Config.FeatureFlags.LevelSystemEnabled == true
		then OverheadDomain.normalizeLevel(stored.level)
		else nil
	local resolvedXp = if Config.FeatureFlags.LevelSystemEnabled == true
		then OverheadDomain.normalizeXp(stored.xp, resolvedLevel)
		else nil
	local xpNeeded = if resolvedLevel then LevelDomain.xpNeeded(resolvedLevel) else nil
	local xpProgress = if resolvedLevel and resolvedXp ~= nil
		then LevelDomain.progress(resolvedLevel, resolvedXp)
		else nil
	local levelText = if resolvedLevel
		then string.format(Config.Level.OVERHEAD_TEXT or "Lv.%d", resolvedLevel)
		else nil

	-- Leaderboard roles: Top Spender (Saweria) / Royale Spender (Robux top donate).
	local isSpender = stored.topSpenderRank ~= nil or stored.topDonateRank ~= nil
	local chatRole: RoleKey
	local leaderboardRank: number?
	chatRole, leaderboardRank = RolesDomain.resolveDynamicChatRole(
		role,
		stored.topSpenderRank,
		stored.topDonateRank,
		Config.ChatPrimaryTagPriority
	) :: any

	local baseChatPrimaryTag = OverheadDomain.getChatPrimaryTag(chatRole, effectiveMembership)
	local finalChatPrimaryTag = baseChatPrimaryTag
	if
		leaderboardRank
		and (chatRole == "TopSpender" or chatRole == "RoyaleSpender" or chatRole == "Spender")
	then
		finalChatPrimaryTag = baseChatPrimaryTag .. " #" .. tostring(leaderboardRank)
	end

	return {
		userId = userId,
		displayName = displayName,
		hasRobloxPremium = hasRobloxPremium == true,
		role = role,
		specialTitle = stored.specialTitle,
		specialTitlePreset = stored.specialTitlePreset,
		specialTitleSize = stored.specialTitleSize,
		specialTitleFont = stored.specialTitleFont,
		specialTitleStyle = stored.specialTitleStyle,
		specialTitlePosition = stored.specialTitlePosition
			or Config.Admin.DEFAULT_SPECIAL_TITLE_POSITION
			or "Top",
		specialRank = specialRankText,
		specialRankGradient = specialRankGradient,
		statusText = specialStatusText,
		rankText = rankText,
		rankGradient = rankGradient,
		effectiveMembership = effectiveMembership,
		membershipLabel = membershipLabel,
		membershipRankText = membershipRankText,
		membershipChatTag = membershipChatTag,
		membershipBadgeFrame = membershipBadgeFrame,
		membershipGradientName = membershipGradientName,
		chatPrimaryTag = finalChatPrimaryTag,
		chatCoupleTag = isCoupled
				and showCoupleName
				and stored.couplePartner
				and (Config.Chat.COUPLE_TAG_EMOJI .. " " .. stored.couplePartner)
			or nil,
		streakDays = stored.streakDays,
		level = resolvedLevel,
		xp = resolvedXp,
		xpProgress = xpProgress,
		xpNeeded = xpNeeded,
		levelText = levelText,
		isCoupled = isCoupled,
		relationshipMode = resolvedRelationshipMode,
		showCoupleName = showCoupleName,
		couplePartner = stored.couplePartner,
		topDonateRank = stored.topDonateRank,
		topDonateText = stored.topDonateText,
		topSpenderRank = stored.topSpenderRank,
		topSpenderText = stored.topSpenderText,
		communityId = communityData and communityData.id or nil,
		communityName = communityData and communityData.name or nil,
		communityLogo = communityData and communityData.logo or nil,
		likesCount = math.max(0, likesCount),
		robuxDonated = math.max(0, robuxDonated),
		cashDonated = math.max(0, cashDonated),
		visibleBadges = visibleBadges,
		publicOverheadLayerVisible = publicLayerVisible,
		publicOverheadBadgeVisible = publicBadgeVisible,
	} :: OverheadPayload
end

function OverheadDomain.normalizeLevel(rawLevel: any): number
	local maxLevel = tonumber(Config.Level and Config.Level.MAX_LEVEL) or 0
	local level = if type(rawLevel) == "number" then math.floor(rawLevel) else 1
	level = math.max(1, level)
	if maxLevel > 0 then
		level = math.min(level, maxLevel)
	end
	return level
end

function OverheadDomain.normalizeXp(rawXp: any, level: number): number
	local xp = if type(rawXp) == "number" then math.max(0, math.floor(rawXp)) else 0
	local maxLevel = tonumber(Config.Level and Config.Level.MAX_LEVEL) or 0
	if maxLevel > 0 and level >= maxLevel then
		local cap = LevelDomain.xpNeeded(level)
		if cap > 0 then
			xp = math.min(xp, cap - 1)
		end
	end
	return xp
end

function OverheadDomain.sanitize(raw: any): OverheadStoredData
	if type(raw) ~= "table" then
		return OverheadDomain.defaultStoredData()
	end

	local ownedMembership: MembershipTier? = OverheadDomain.normalizeMembershipTier(raw.ownedMembership)
	local membershipBadge: MembershipTier? = OverheadDomain.normalizeMembershipTier(raw.membershipBadge)
	local giftedRole: RoleKey? = OverheadDomain.normalizeRoleKey(raw.giftedRole)
	local giftedMemberships = if type(raw.giftedMemberships) == "table"
		then OverheadDomain.normalizeGiftedMemberships(raw :: OverheadStoredData)
		else nil
	local normalizedLevel = OverheadDomain.normalizeLevel(raw.level)
	local normalizedXp = OverheadDomain.normalizeXp(raw.xp, normalizedLevel)

	return {
		specialTitle = type(raw.specialTitle) == "string" and raw.specialTitle or nil,
		specialTitlePreset = if type(raw.specialTitlePreset) == "string"
				and AnimationModes.IsPreset(raw.specialTitlePreset)
			then raw.specialTitlePreset
			else nil,
		specialTitleSize = if type(raw.specialTitleSize) == "string"
				and TitleStyleDomain.isValidTitleSize(raw.specialTitleSize)
			then raw.specialTitleSize :: TitleSizeKey
			else nil,
		specialTitleFont = if type(raw.specialTitleFont) == "string" and VALID_FONTS[raw.specialTitleFont]
			then raw.specialTitleFont
			else nil,
		specialTitleStyle = TitleStyleDomain.sanitizeStyle(raw.specialTitleStyle),
		specialTitlePosition = type(raw.specialTitlePosition) == "string"
				and (raw.specialTitlePosition == "Top" or raw.specialTitlePosition == "Stacked")
				and raw.specialTitlePosition
			or (Config.Admin.DEFAULT_SPECIAL_TITLE_POSITION or "Top"),
		specialRank = type(raw.specialRank) == "string" and raw.specialRank or nil,
		specialSubRole = if raw.specialSubRole == "DJ" or raw.specialSubRole == "Influencer"
			then raw.specialSubRole
			else nil,
		giftedRole = giftedRole,
		membershipBadge = membershipBadge,
		ownedMembership = ownedMembership,
		giftedMemberships = giftedMemberships,
		giftedBy = type(raw.giftedBy) == "number" and raw.giftedBy or nil,
		giftedAt = type(raw.giftedAt) == "number" and raw.giftedAt or nil,
		coupleData = type(raw.coupleData) == "table" and raw.coupleData or nil,
		couplePartner = type(raw.couplePartner) == "string" and raw.couplePartner or nil,
		couplePartnerId = type(raw.couplePartnerId) == "number" and raw.couplePartnerId or nil,
		showCoupleName = if type(raw.showCoupleName) == "boolean" then raw.showCoupleName else true,
		publicOverheadLayerVisible = sanitizeBoolMap(raw.publicOverheadLayerVisible, DEFAULT_PUBLIC_LAYER_VISIBLE),
		publicOverheadBadgeVisible = sanitizeBoolMap(raw.publicOverheadBadgeVisible, DEFAULT_PUBLIC_BADGE_VISIBLE),
		topDonateRank = OverheadDomain.normalizeLeaderboardRank(raw.topDonateRank, "RobuxSpender"),
		topDonateText = type(raw.topDonateText) == "string" and raw.topDonateText or nil,
		topSpenderRank = OverheadDomain.normalizeLeaderboardRank(raw.topSpenderRank, "CashSpender"),
		topSpenderText = type(raw.topSpenderText) == "string" and raw.topSpenderText or nil,
		communityId = type(raw.communityId) == "number" and raw.communityId > 0 and math.floor(raw.communityId) or nil,
		suppressCommunityBadge = raw.suppressCommunityBadge == true,
		streakDays = type(raw.streakDays) == "number" and math.max(0, raw.streakDays) or 0,
		lastLoginAt = type(raw.lastLoginAt) == "number" and math.max(0, raw.lastLoginAt) or 0,
		level = normalizedLevel,
		xp = normalizedXp,
		_version = type(raw._version) == "number" and raw._version or 1,
	} :: OverheadStoredData
end

local NIL = "__NIL__"
OverheadDomain.NIL = NIL

function OverheadDomain.mergeStored(stored: OverheadStoredData, changes: { [string]: any }): OverheadStoredData
	local copy = table.clone(stored :: any)
	for key, value in pairs(changes) do
		if value == NIL then
			copy[key] = nil
		else
			copy[key] = value
		end
	end
	copy._version = stored._version + 1
	return copy :: OverheadStoredData
end

return OverheadDomain
