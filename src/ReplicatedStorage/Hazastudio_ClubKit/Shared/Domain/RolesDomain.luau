--!strict
-- Builds derived Config tables from buyer RoleCategories (config.Roles).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LegacyRoles = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Config.Roles)

export type RoleDefinition = LegacyRoles.RoleDefinition
export type RoleColor = LegacyRoles.RoleColor

local RolesDomain = {}
local activeRoles: any = LegacyRoles

local function getRoles()
	return activeRoles
end

local function canonicalizeRoleKey(rawKey: string): string?
	local roles = getRoles()
	if roles.DEFINITIONS[rawKey] then
		return rawKey
	end
	local legacy = roles.LEGACY_ALIASES[rawKey]
	if legacy and roles.DEFINITIONS[legacy] then
		return legacy
	end
	return nil
end

function RolesDomain.getDefinition(roleKey: string): RoleDefinition?
	local canonical = canonicalizeRoleKey(roleKey)
	if not canonical then
		return nil
	end
	return getRoles().DEFINITIONS[canonical]
end

function RolesDomain.normalizeRoleKey(rawRole: any): string?
	if type(rawRole) ~= "string" or rawRole == "" then
		return nil
	end

	local roles = getRoles()
	local commandAlias = roles.COMMAND_ALIASES[rawRole] or roles.COMMAND_ALIASES[string.lower(rawRole)]
	if commandAlias == "none" then
		return nil
	end
	if type(commandAlias) == "string" and commandAlias ~= "none" then
		local fromCommand = canonicalizeRoleKey(commandAlias)
		if fromCommand then
			return fromCommand
		end
	end

	local fromLegacy = roles.LEGACY_ALIASES[rawRole]
	if type(fromLegacy) == "string" then
		local resolved = canonicalizeRoleKey(fromLegacy)
		if resolved then
			return resolved
		end
	end

	local direct = canonicalizeRoleKey(rawRole)
	if direct then
		return direct
	end

	local lowered = string.lower(rawRole)
	local fromLowerLegacy = roles.LEGACY_ALIASES[lowered]
	if type(fromLowerLegacy) == "string" then
		return canonicalizeRoleKey(fromLowerLegacy)
	end

	return nil
end

function RolesDomain.isValidRole(role: string): boolean
	return RolesDomain.normalizeRoleKey(role) ~= nil
end

function RolesDomain.getOrderedKeys(): { string }
	return table.clone(getRoles().ORDER)
end

function RolesDomain.getAllRoleKeysIncludingLegacy(): { string }
	local roles = getRoles()
	local seen: { [string]: boolean } = {}
	local result: { string } = {}
	local function add(key: string)
		if seen[key] then
			return
		end
		seen[key] = true
		table.insert(result, key)
	end
	for _, key in ipairs(roles.ORDER) do
		add(key)
	end
	for legacyKey in pairs(roles.LEGACY_ALIASES) do
		add(legacyKey)
	end
	for legacyKey in pairs(roles.DEFINITIONS) do
		add(legacyKey)
	end
	return result
end

function RolesDomain.isSetroleOnlyRole(role: string): boolean
	local canonical = RolesDomain.normalizeRoleKey(role)
	if not canonical then
		return false
	end
	local definition = getRoles().DEFINITIONS[canonical]
	return definition ~= nil and definition.setroleOnly == true
end

function RolesDomain.buildRankMap(): { [number]: string }
	if type(activeRoles) == "table" and type((activeRoles :: any).RANK_MAP) == "table" then
		return (activeRoles :: any).RANK_MAP
	end
	local rankMap: { [number]: string } = {}
	for roleKey, definition in pairs(getRoles().DEFINITIONS) do
		if definition.setroleOnly then
			continue
		end
		local ranks = definition.groupRanks
		if type(ranks) == "table" then
			for _, rankId in ipairs(ranks) do
				rankMap[rankId] = roleKey
			end
		end
	end
	if rankMap[0] == nil then
		rankMap[0] = "Guest"
	end
	return rankMap
end

function RolesDomain.buildChatPrimaryTagPriority(): { [string]: number }
	local roles = getRoles()
	local map: { [string]: number } = {}
	for roleKey, definition in pairs(roles.DEFINITIONS) do
		map[roleKey] = definition.priority
	end
	for legacyKey, canonical in pairs(roles.LEGACY_ALIASES) do
		local priority = map[canonical]
		if priority then
			map[legacyKey] = priority
		end
	end
	return map
end

function RolesDomain.buildChatPrimaryTagLabel(): { [string]: string }
	local roles = getRoles()
	local map: { [string]: string } = {}
	for roleKey, definition in pairs(roles.DEFINITIONS) do
		map[roleKey] = definition.chatTag
	end
	for legacyKey, canonical in pairs(roles.LEGACY_ALIASES) do
		local def = roles.DEFINITIONS[canonical]
		if def then
			map[legacyKey] = def.chatTag
		end
	end
	return map
end

function RolesDomain.buildRoleColorPalette(): { [string]: RoleColor }
	local roles = getRoles()
	local map = {}
	for roleKey, definition in pairs(roles.DEFINITIONS) do
		map[roleKey] = definition.roleColor
	end
	for legacyKey, canonical in pairs(roles.LEGACY_ALIASES) do
		local def = roles.DEFINITIONS[canonical]
		if def then
			map[legacyKey] = def.roleColor
		end
	end
	return map
end

function RolesDomain.buildChatPrimaryTagColor(roleColorPalette: { [string]: any }): { [string]: string }
	local map: { [string]: string } = {}
	for roleKey, colors in pairs(roleColorPalette) do
		if type(colors) == "table" and type(colors.primary) == "string" then
			map[roleKey] = colors.primary
		end
	end
	return map
end

function RolesDomain.buildSpecialRank(): { [string]: { text: string, gradient: boolean } }
	local roles = getRoles()
	local map = {}
	for roleKey, definition in pairs(roles.DEFINITIONS) do
		if definition.specialRank then
			map[roleKey] = definition.specialRank
		end
	end
	for legacyKey, canonical in pairs(roles.LEGACY_ALIASES) do
		local special = map[canonical]
		if special then
			map[legacyKey] = special
		end
	end
	return map
end

local function warnDuplicateRoleColors()
	local roles = getRoles()
	local seenTeam: { [string]: string } = {}
	local seenPrimary: { [string]: string } = {}
	for roleKey, definition in pairs(roles.DEFINITIONS) do
		local teamColor = definition.teamColor
		if seenTeam[teamColor] then
			warn(
				string.format(
					"[Roles] Duplicate teamColor %q on %s and %s — leaderboard teams may merge visually",
					teamColor,
					roleKey,
					seenTeam[teamColor]
				)
			)
		else
			seenTeam[teamColor] = roleKey
		end
		local primary = definition.roleColor.primary
		if seenPrimary[primary] then
			warn(
				string.format(
					"[Roles] Duplicate roleColor.primary %q on %s and %s — chat tags may look identical",
					primary,
					roleKey,
					seenPrimary[primary]
				)
			)
		else
			seenPrimary[primary] = roleKey
		end
	end
end

local function syncMembershipChatColors(config: any)
	local palette = config.RoleColorPalette
	if type(palette) ~= "table" then
		return
	end
	local tierToRole = {
		Guest = "Guest",
		Tier1 = "VIP",
		Tier2 = "VVIP",
		Tier3 = "Supreme",
	}
	for tierKey, roleKey in pairs(tierToRole) do
		local colors = palette[roleKey]
		if type(colors) == "table" and type(colors.primary) == "string" then
			config.ChatPrimaryTagColor[tierKey] = colors.primary
		end
	end
	local memberTier = config.Membership and config.Membership.Tiers and config.Membership.Tiers.Member
	if memberTier and type(memberTier.roleColor) == "table" and type(memberTier.roleColor.primary) == "string" then
		config.ChatPrimaryTagColor.Member = memberTier.roleColor.primary
	end
	local vipPrimary = palette.VIP and palette.VIP.primary
	if type(vipPrimary) == "string" then
		config.ChatPrimaryTagColor.VIP = vipPrimary
		config.ChatPrimaryTagColor.VIPMember = vipPrimary
	end
	local vvipPrimary = palette.VVIP and palette.VVIP.primary
	if type(vvipPrimary) == "string" then
		config.ChatPrimaryTagColor.VVIP = vvipPrimary
		config.ChatPrimaryTagColor.VVIPMember = vvipPrimary
	end
	local supremePrimary = (palette.Supreme and palette.Supreme.primary)
		or (palette.Exclusive and palette.Exclusive.primary)
	if type(supremePrimary) == "string" then
		config.ChatPrimaryTagColor.Supreme = supremePrimary
		config.ChatPrimaryTagColor.Exclusive = supremePrimary
		config.ChatPrimaryTagColor.ELITEMember = supremePrimary
		config.ChatPrimaryTagColor.Tier3 = supremePrimary
	end
end

function RolesDomain.buildTeamColors(): { [string]: string }
	local roles = getRoles()
	local map: { [string]: string } = {}
	for roleKey, definition in pairs(roles.DEFINITIONS) do
		map[roleKey] = definition.teamColor
	end
	for legacyKey, canonical in pairs(roles.LEGACY_ALIASES) do
		local color = map[canonical]
		if color then
			map[legacyKey] = color
		end
	end
	return map
end

function RolesDomain.buildBadgeVisibility(membershipBadgeFrames: { [string]: string? }): { [string]: { string } }
	local roles = getRoles()
	local map: { [string]: { string } } = {}
	for roleKey, definition in pairs(roles.DEFINITIONS) do
		if definition.badgeFrames then
			map[roleKey] = table.clone(definition.badgeFrames)
		else
			map[roleKey] = {}
		end
	end
	for legacyKey, canonical in pairs(roles.LEGACY_ALIASES) do
		if map[canonical] then
			map[legacyKey] = table.clone(map[canonical])
		end
	end
	for tierKey, frame in pairs(membershipBadgeFrames) do
		if type(frame) == "string" and frame ~= "" then
			map[tierKey] = { frame }
		end
	end
	return map
end

function RolesDomain.getRoleToolFolderName(roleKey: string): string?
	if roleKey == "Guest" then
		return nil
	end
	local definition = RolesDomain.getDefinition(roleKey)
	if not definition then
		return nil
	end
	if type(definition.toolFolder) == "string" and definition.toolFolder ~= "" then
		return definition.toolFolder
	end
	if definition.chatTag == "" then
		return nil
	end
	return definition.chatTag
end

function RolesDomain.buildStudioToolFolderList(): { string }
	local roles = getRoles()
	local seen = {} :: { [string]: boolean }
	local ordered = {} :: { string }

	local function add(name: string?)
		if type(name) ~= "string" or name == "" or seen[name] then
			return
		end
		seen[name] = true
		table.insert(ordered, name)
	end

	for _, roleKey in ipairs(roles.ORDER) do
		add(RolesDomain.getRoleToolFolderName(roleKey))
	end
	for _, name in ipairs(roles.EXTRA_TOOL_FOLDERS) do
		add(name)
	end

	return ordered
end

function RolesDomain.buildRoleToolFolders(): { [string]: { string } }
	local roles = getRoles()
	local map: { [string]: { string } } = {}
	for roleKey in pairs(roles.DEFINITIONS) do
		local folder = RolesDomain.getRoleToolFolderName(roleKey)
		if folder then
			map[roleKey] = { folder }
		end
	end
	for legacyKey, canonical in pairs(roles.LEGACY_ALIASES) do
		if map[canonical] then
			map[legacyKey] = table.clone(map[canonical])
		end
	end
	return map
end

function RolesDomain.buildMembershipToolFolders(): { [string]: { string } }
	return {
		Tier3 = { "SUPREME" },
		Supreme = { "SUPREME" },
		ELITEMember = { "SUPREME" },
		Exclusive = { "SUPREME" },
		Tier2 = { "VVIP" },
		VVIPMember = { "VVIP" },
		VVIP = { "VVIP" },
		Tier1 = { "VIP" },
		VIPMember = { "VIP" },
		VIP = { "VIP" },
	}
end

function RolesDomain.buildFolderPriority(): { [string]: number }
	local roles = getRoles()
	local map: { [string]: number } = {}
	for roleKey, definition in pairs(roles.DEFINITIONS) do
		local folder = RolesDomain.getRoleToolFolderName(roleKey)
		if folder then
			map[folder] = definition.priority
		end
	end
	for _, folderName in ipairs(roles.EXTRA_TOOL_FOLDERS) do
		if folderName == "DONOR" or folderName == "DONATUR" then
			map[folderName] = 15
		end
	end
	map.ADMIN = map.STAFF or 75
	map.MODERATOR = map.Moderator or 70
	map.COOWNER = map.STAFF or 95
	map.SUPREME = map.Supreme or 60
	map.EXCLUSIVE = map.Supreme or 60
	map.ELITE = map.Supreme or 60
	map.LEAD = map["LEAD DANCE"] or map.LeadDance or 68
	map["TOP DONOR"] = map.TopSpender or 55
	map["TOP DONATE"] = map.RoyaleSpender or map.TopSpender or 55
	map["TOP SUPPORTER"] = map.RoyaleSpender or 55
	map["ROYALE SPENDER"] = map.RoyaleSpender or 55
	map["TOP SPENDER"] = map.TopSpender or 55
	return map
end

function RolesDomain.buildSetRoleAliases(): { [string]: string }
	local merged: { [string]: string } = {}
	for alias, target in pairs(getRoles().COMMAND_ALIASES) do
		merged[alias] = target
	end
	return merged
end

function RolesDomain.buildSetroleHelpText(): string
	local roles = getRoles()
	local manualLabels = {} :: { string }
	for _, roleKey in ipairs(roles.SETROLE_ONLY) do
		local definition = roles.DEFINITIONS[roleKey]
		if definition then
			table.insert(manualLabels, string.lower(definition.label))
		end
	end
	return "owner, staff, moderator, "
		.. table.concat(manualLabels, ", ")
		.. ", supreme, vvip, vip, or none"
end

local ConfigRef: any = nil

local function getSpenderConfig()
	local spenderRoles = ConfigRef and ConfigRef.SpenderRoles
	if type(spenderRoles) ~= "table" then
		return nil
	end
	return spenderRoles
end

function RolesDomain.resolveDynamicChatRole(
	baseRole: string,
	topSpenderRank: number?,
	topDonateRank: number?,
	chatPriorities: { [string]: number }
): (string, number?)
	local chatRole = RolesDomain.normalizeRoleKey(baseRole) or baseRole
	local bestLeaderboardRank: number? = nil
	local spenderRoles = getSpenderConfig()

	local function isWithinMaxRank(spenderType: string, rank: number?): boolean
		if rank == nil then
			return false
		end
		if type(spenderRoles) ~= "table" then
			return rank >= 1
		end
		local config = spenderRoles[spenderType]
		if type(config) ~= "table" then
			return false
		end
		local spenderEntry = config :: { Enabled: boolean?, MaxRank: number? }
		if spenderEntry.Enabled == false then
			return false
		end
		local maxRank = tonumber(spenderEntry.MaxRank) or 1
		return rank >= 1 and rank <= maxRank
	end

	local function tryPromote(targetRole: string, rank: number?)
		local canonical = RolesDomain.normalizeRoleKey(targetRole)
		if not canonical or rank == nil then
			return
		end
		local currentPriority = chatPriorities[chatRole] or 0
		local targetPriority = chatPriorities[canonical] or 0
		if targetPriority > currentPriority then
			chatRole = canonical
			bestLeaderboardRank = rank
		elseif canonical == chatRole then
			bestLeaderboardRank = if bestLeaderboardRank then math.min(bestLeaderboardRank, rank) else rank
		end
	end

	local cashKey = "TopSpender"
	local robuxKey = "RoyaleSpender"
	if type(spenderRoles) == "table" then
		local cash = spenderRoles.CashSpender
		if type(cash) == "table" and type(cash.Key) == "string" then
			cashKey = cash.Key
		end
		local robux = spenderRoles.RobuxSpender
		if type(robux) == "table" and type(robux.Key) == "string" then
			robuxKey = robux.Key
		end
	end

	if isWithinMaxRank("CashSpender", topSpenderRank) then
		tryPromote(cashKey, topSpenderRank)
	end
	if isWithinMaxRank("RobuxSpender", topDonateRank) then
		tryPromote(robuxKey, topDonateRank)
	end

	if chatRole == cashKey or chatRole == robuxKey or chatRole == "Spender" then
		if topSpenderRank and topDonateRank then
			bestLeaderboardRank = math.min(topSpenderRank, topDonateRank)
		elseif topSpenderRank then
			bestLeaderboardRank = topSpenderRank
		elseif topDonateRank then
			bestLeaderboardRank = topDonateRank
		end
	end

	return chatRole, bestLeaderboardRank
end

function RolesDomain.roleShowsSpecialStatus(role: string): boolean
	local def = RolesDomain.getDefinition(role)
	return def ~= nil and def.showSpecialStatus == true
end

function RolesDomain.isStaffPlus(role: string): boolean
	local canonical = RolesDomain.normalizeRoleKey(role) or role
	for _, allowed in ipairs(getRoles().STAFF_PLUS) do
		if canonical == allowed then
			return true
		end
	end
	local legacyStaff = { CoOwner = "Staff", AfterTeam = "Staff", Developer = "Staff", Admin = "Staff", Investor = "Staff" }
	return legacyStaff[canonical] ~= nil or legacyStaff[role] ~= nil
end

function RolesDomain.applyDerivedConfig(config: any)
	ConfigRef = config
	if type(config.Roles) == "table" then
		activeRoles = config.Roles
	else
		activeRoles = LegacyRoles
	end

	if type(config.Group.RANK_MAP) ~= "table" or next(config.Group.RANK_MAP) == nil then
		config.Group.RANK_MAP = RolesDomain.buildRankMap()
	end

	config.ChatPrimaryTagPriority = RolesDomain.buildChatPrimaryTagPriority()
	config.ChatPrimaryTagLabel = RolesDomain.buildChatPrimaryTagLabel()
	config.RoleColorPalette = RolesDomain.buildRoleColorPalette()
	config.ChatPrimaryTagColor = RolesDomain.buildChatPrimaryTagColor(config.RoleColorPalette)
	config.SpecialRank = RolesDomain.buildSpecialRank()
	config.PlayerList.TEAM_COLORS = RolesDomain.buildTeamColors()
	warnDuplicateRoleColors()
	syncMembershipChatColors(config)

	local membershipFrames = {
		Tier3 = config.Membership.Tiers.Tier3.badgeFrame,
		Tier2 = config.Membership.Tiers.Tier2.badgeFrame,
		Tier1 = config.Membership.Tiers.Tier1.badgeFrame,
		ELITEMember = config.Membership.Tiers.Tier3.badgeFrame,
		VVIPMember = config.Membership.Tiers.Tier2.badgeFrame,
		VIPMember = config.Membership.Tiers.Tier1.badgeFrame,
		Member = config.Membership.Tiers.Member.badgeFrame,
		Exclusive = config.Membership.Tiers.Tier3.badgeFrame,
		Supreme = config.Membership.Tiers.Tier3.badgeFrame,
		VVIP = config.Membership.Tiers.Tier2.badgeFrame,
		VIP = config.Membership.Tiers.Tier1.badgeFrame,
	}
	config.BadgeVisibility = RolesDomain.buildBadgeVisibility(membershipFrames)

	if type(config.SetRole) == "table" then
		config.SetRole.ROLE_ALIASES = RolesDomain.buildSetRoleAliases()
		config.SetRole.MSG_INVALID_ROLE = "[SetRole] '%s' is not a role I can use. Try "
			.. RolesDomain.buildSetroleHelpText()
			.. "."
	end

	if type(config.RoleTools) == "table" then
		config.RoleTools.FOLDERS_BY_ROLE = RolesDomain.buildRoleToolFolders()
		config.RoleTools.FOLDERS_BY_MEMBERSHIP = RolesDomain.buildMembershipToolFolders()
		config.RoleTools.FOLDER_PRIORITY = RolesDomain.buildFolderPriority()
		local royale = RolesDomain.getRoleToolFolderName("RoyaleSpender")
		local top = RolesDomain.getRoleToolFolderName("TopSpender")
		local spenderRoles = config.SpenderRoles
		if type(spenderRoles) == "table" then
			local robux = spenderRoles.RobuxSpender
			if type(robux) == "table" and robux.Enabled ~= false then
				royale = robux.ToolFolder or royale
			end
			local cash = spenderRoles.CashSpender
			if type(cash) == "table" and cash.Enabled ~= false then
				top = cash.ToolFolder or top
			end
			local donatur = spenderRoles.Donatur
			if type(donatur) == "table" and donatur.Enabled ~= false then
				config.RoleTools.DONOR_FOLDER = donatur.ToolFolder or config.RoleTools.DONOR_FOLDER
			end
		end
		if royale then
			config.RoleTools.ROYALE_SPENDER_FOLDER = royale
			config.RoleTools.TOP_DONATE_FOLDER = royale
		end
		if top then
			config.RoleTools.TOP_SPENDER_FOLDER = top
		end
	end

	local aliases = config.Membership.ALIASES
	if type(aliases) == "table" then
		aliases.VIP = "Tier1"
		aliases.vip = "Tier1"
		aliases.VVIP = "Tier2"
		aliases.vvip = "Tier2"
		aliases.Supreme = "Tier3"
		aliases.supreme = "Tier3"
		aliases.Exclusive = "Tier3"
		aliases.exclusive = "Tier3"
	end
end

return RolesDomain
