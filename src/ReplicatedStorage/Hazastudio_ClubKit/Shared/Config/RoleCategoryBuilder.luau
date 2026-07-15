--!strict
-- Builds flat Roles registry + privilege maps from RoleCategories and SpenderRoles.

local RoleCategoryBuilder = {}

export type BuiltRoles = {
	ORDER: { string },
	DEFINITIONS: { [string]: any },
	SETROLE_ONLY: { string },
	STAFF_PLUS: { string },
	EXTRA_TOOL_FOLDERS: { string },
	LEGACY_ALIASES: { [string]: string },
	COMMAND_ALIASES: { [string]: string },
	ROLE_TO_CATEGORY: { [string]: number },
	CATEGORY_PRIVILEGES: { [number]: { [string]: boolean } },
}

local MEMBERSHIP_DISPLAY_ROLES = {
	VIP = {
		label = "VIP",
		chatTag = "VIP",
		priority = 40,
		membershipTier = "Tier1",
		roleColor = { primary = "#F97316", secondary = "#FDBA74" },
		teamColor = "Bright orange",
		giftable = true,
	},
	VVIP = {
		label = "VVIP",
		chatTag = "VVIP",
		priority = 50,
		membershipTier = "Tier2",
		roleColor = { primary = "#94A3B8", secondary = "#CBD5E1" },
		teamColor = "Light stone grey",
		giftable = true,
	},
	Supreme = {
		label = "Supreme",
		chatTag = "SUPREME",
		priority = 60,
		membershipTier = "Tier3",
		roleColor = { primary = "#EF4444", secondary = "#FCA5A5" },
		teamColor = "Dark orange",
		giftable = true,
	},
}

local function cloneTable<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in pairs(value :: any) do
		if type(item) == "table" then
			copy[key] = cloneTable(item)
		else
			copy[key] = item
		end
	end
	return copy :: any
end

local function addUnique(list: { string }, value: string)
	if not table.find(list, value) then
		table.insert(list, value)
	end
end

function RoleCategoryBuilder.build(clubKit: any): BuiltRoles
	local definitions: { [string]: any } = {}
	local order: { string } = {}
	local setroleOnly: { string } = {}
	local staffPlus: { string } = {}
	local roleToCategory: { [string]: number } = {}
	local categoryPrivileges: { [number]: { [string]: boolean } } = {}
	local extraToolFolders: { string } = {}
	local legacyAliases = cloneTable(clubKit.LegacyAliases or {})
	local commandAliases = cloneTable(clubKit.CommandAliases or {})
	-- Co-Owner is a first-class kit role (not a Staff alias).
	if legacyAliases.CoOwner == "Staff" then
		legacyAliases.CoOwner = nil
	end
	legacyAliases["Co-Owner"] = "CoOwner"
	legacyAliases["co-owner"] = "CoOwner"
	legacyAliases.coowner = "CoOwner"
	commandAliases.coowner = "CoOwner"
	commandAliases["co-owner"] = "CoOwner"

	local systemRoles = clubKit.SystemRoles or {}
	for roleKey, definition in pairs(systemRoles) do
		definitions[roleKey] = cloneTable(definition)
		addUnique(order, roleKey)
	end

	local categories = clubKit.RoleCategories
	if type(categories) == "table" then
		table.sort(categories, function(a, b)
			return (a.priority or 0) > (b.priority or 0)
		end)

		for _, category in ipairs(categories) do
			if category.enabled == false then
				continue
			end
			local categoryId = category.id
			if type(categoryId) == "number" then
				categoryPrivileges[categoryId] = cloneTable(category.privileges or {})
			end
			local basePriority = tonumber(category.priority) or 0
			local roles = category.roles
			if type(roles) ~= "table" then
				continue
			end
			for roleIndex, role in ipairs(roles) do
				if role.enabled == false then
					continue
				end
				local roleKey = role.key
				if type(roleKey) ~= "string" or roleKey == "" then
					continue
				end
				if roleKey == "Owner" or roleKey == "Guest" then
					continue
				end

				local privileges = category.privileges or {}
				-- First role in array = highest priority within the category block.
				local priority = basePriority * 100 + (#roles - roleIndex)
				definitions[roleKey] = {
					label = role.label or roleKey,
					chatTag = role.chatTag or string.upper(roleKey),
					priority = priority,
					setroleOnly = true,
					giftable = role.giftable ~= false,
					canGift = privileges.canGift == true,
					roleColor = role.roleColor or { primary = "#FFFFFF", secondary = "#CCCCCC" },
					teamColor = role.teamColor or "Medium stone grey",
					badgeFrames = role.badgeFrames,
					specialRank = role.specialRank,
					showSpecialStatus = role.showSpecialStatus == true,
					toolFolder = role.toolFolder or role.chatTag or string.upper(roleKey),
					categoryId = categoryId,
				}
				addUnique(order, roleKey)
				addUnique(setroleOnly, roleKey)
				if type(categoryId) == "number" then
					roleToCategory[roleKey] = categoryId
				end
				if privileges.canGift == true or privileges.adminPanel == true then
					addUnique(staffPlus, roleKey)
				end
			end
		end
	end

	-- Kit default: Co-Owner (Owner-tier badge/perms, /setrole only — no groupRanks).
	if definitions["CoOwner"] == nil then
		local leadershipId: number? = nil
		if type(categories) == "table" then
			for _, category in ipairs(categories) do
				if category.enabled ~= false and type(category.id) == "number" and category.label == "Leadership" then
					leadershipId = category.id
					break
				end
			end
			if leadershipId == nil then
				for _, category in ipairs(categories) do
					if category.enabled ~= false and type(category.id) == "number" then
						leadershipId = category.id
						break
					end
				end
			end
		end
		definitions["CoOwner"] = {
			label = "Co-Owner",
			chatTag = "CO-OWNER",
			priority = 14099,
			setroleOnly = true,
			giftable = true,
			canGift = true,
			roleColor = { primary = "#FBBF24", secondary = "#FDE68A" },
			teamColor = "New Yeller",
			badgeFrames = { "01-OwnerCoOwnerBadge" },
			specialRank = { text = "CO-OWNER", gradient = true },
			toolFolder = "STAFF",
			categoryId = leadershipId,
		}
		addUnique(order, "CoOwner")
		addUnique(setroleOnly, "CoOwner")
		addUnique(staffPlus, "CoOwner")
		if type(leadershipId) == "number" then
			roleToCategory["CoOwner"] = leadershipId
		end
	end

	for roleKey, definition in pairs(MEMBERSHIP_DISPLAY_ROLES) do
		local membershipTier = definition.membershipTier
		local membership = clubKit.Membership
		if type(membership) == "table" and type(membershipTier) == "string" then
			local tierOverride = membership[membershipTier]
			if type(tierOverride) == "table" and tierOverride.Enabled == false then
				continue
			end
		end

		local roleDefinition = cloneTable(definition)
		if type(membership) == "table" and type(membershipTier) == "string" then
			local tierOverride = membership[membershipTier]
			if type(tierOverride) == "table" and type(tierOverride.Label) == "string" and tierOverride.Label ~= "" then
				roleDefinition.label = tierOverride.Label
				roleDefinition.chatTag = string.upper(tierOverride.Label)
			end
			if type(tierOverride) == "table" and type(tierOverride.Priority) == "number" then
				roleDefinition.priority = tierOverride.Priority
			end
		end

		if not definitions[roleKey] then
			roleDefinition.setroleOnly = true
			definitions[roleKey] = roleDefinition
			addUnique(order, roleKey)
			addUnique(setroleOnly, roleKey)
		end
	end

	local spenderRoles = clubKit.SpenderRoles
	if type(spenderRoles) == "table" then
		local donatur = spenderRoles.Donatur
		if type(donatur) == "table" and donatur.Enabled ~= false then
			local folder = donatur.ToolFolder or "DONOR"
			addUnique(extraToolFolders, folder)
		end

		local function addSpenderRole(configKey: string, fallbackKey: string)
			local spender = spenderRoles[configKey]
			if type(spender) ~= "table" or spender.Enabled == false then
				return
			end
			local roleKey = spender.Key or fallbackKey
			definitions[roleKey] = {
				label = spender.Label or roleKey,
				chatTag = spender.ChatTag or string.upper(roleKey),
				priority = tonumber(spender.Priority) or 50,
				setroleOnly = true,
				dynamicLeaderboard = true,
				giftable = spender.giftable == true,
				roleColor = spender.roleColor or { primary = "#FFFFFF", secondary = "#CCCCCC" },
				teamColor = spender.TeamColor or "Medium stone grey",
				specialRank = spender.SpecialRank,
				toolFolder = spender.ToolFolder or spender.ChatTag,
				spenderType = configKey,
				maxRank = tonumber(spender.MaxRank) or 1,
				spenderPrivileges = cloneTable(spender.Privileges or {}),
			}
			addUnique(order, roleKey)
			addUnique(setroleOnly, roleKey)
		end

		addSpenderRole("Donatur", "Donatur")
		addSpenderRole("CashSpender", "TopSpender")
		addSpenderRole("RobuxSpender", "RoyaleSpender")
	end

	addUnique(order, "Owner")
	addUnique(order, "Guest")
	addUnique(staffPlus, "Owner")
	addUnique(staffPlus, "CoOwner")

	-- Prefer Owner → CoOwner near top of ORDER when CoOwner was injected late.
	local preferredOrder = { "Owner", "CoOwner" }
	local reordered: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, key in ipairs(preferredOrder) do
		if definitions[key] then
			table.insert(reordered, key)
			seen[key] = true
		end
	end
	for _, key in ipairs(order) do
		if not seen[key] then
			table.insert(reordered, key)
			seen[key] = true
		end
	end

	return {
		ORDER = reordered,
		DEFINITIONS = definitions,
		SETROLE_ONLY = setroleOnly,
		STAFF_PLUS = staffPlus,
		EXTRA_TOOL_FOLDERS = if #extraToolFolders > 0 then extraToolFolders else { "DONOR" },
		LEGACY_ALIASES = legacyAliases,
		COMMAND_ALIASES = commandAliases,
		ROLE_TO_CATEGORY = roleToCategory,
		CATEGORY_PRIVILEGES = categoryPrivileges,
	}
end

function RoleCategoryBuilder.buildRankMap(definitions: { [string]: any }, ownerGroupRank: number): { [number]: string }
	local rankMap: { [number]: string } = {
		[0] = "Guest",
	}
	local ownerRank = if type(ownerGroupRank) == "number" and ownerGroupRank > 0 then ownerGroupRank else 255
	rankMap[ownerRank] = "Owner"
	return rankMap
end

return RoleCategoryBuilder
