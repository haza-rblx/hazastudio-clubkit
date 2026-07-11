--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local PermissionDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.PermissionDomain)
local RolesDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.RolesDomain)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)

type RoleKey = Types.RoleKey
type CommandLibraryEntry = Types.CommandLibraryEntry
type CommandLibraryVisibilityMap = Types.CommandLibraryVisibilityMap

local CommandLibraryDomain = {}

local ALL_ROLES: { RoleKey } = (function()
	local keys = {}
	if type(Config.Roles) == "table" and type(Config.Roles.ORDER) == "table" then
		for _, roleKey in ipairs(Config.Roles.ORDER) do
			table.insert(keys, roleKey :: RoleKey)
		end
	end
	local legacy = Config.Roles and Config.Roles.LEGACY_ALIASES
	if type(legacy) == "table" then
		for legacyKey in pairs(legacy) do
			table.insert(keys, legacyKey :: RoleKey)
		end
	end
	return keys
end)() :: { RoleKey }

local function buildVisibility(roles: {RoleKey}): CommandLibraryVisibilityMap
	local map = {} :: CommandLibraryVisibilityMap
	for index = 1, #roles do
		local role: RoleKey = roles[index]
		map[role] = true
	end
	return map
end

type PermissionGate = "public" | "canTeleport" | "canAnnounce" | "admin" | "owner"

local ENTRY_GATES: { [string]: PermissionGate } = {
	setbio = "public",
	clearbio = "public",
	status = "public",
	clearstatus = "public",
	setcommun = "public",
	clearcommun = "public",
	re = "public",
	rejoin = "public",
	bring = "canTeleport",
	to = "canTeleport",
	announce = "canAnnounce",
	gift = "admin",
	ungift = "admin",
	setrole = "admin",
	unsetrole = "admin",
	setrobux = "owner",
	removerobux = "owner",
	donatecash = "owner",
	addcash = "owner",
	removecash = "owner",
	donatebagibagi = "owner",
	addbagibagi = "owner",
	removebagibagi = "owner",
	testcash = "admin",
	testdonate = "admin",
	testrobux = "admin",
	testsaweria = "admin",
}

local function rolePassesGate(gate: PermissionGate, role: RoleKey, effectiveMembership: string?): boolean
	if gate == "public" then
		return true
	end
	if gate == "owner" then
		return RolesDomain.normalizeRoleKey(role) == "Owner"
	end
	if gate == "admin" then
		return PermissionDomain.canUseAdminPanel(role, nil)
	end
	if gate == "canAnnounce" then
		return PermissionDomain.canAnnounce(role, effectiveMembership)
	end
	if gate == "canTeleport" then
		return PermissionDomain.canTeleport(role, effectiveMembership)
	end
	return false
end

local function buildGateVisibility(gate: PermissionGate): CommandLibraryVisibilityMap
	local map = {} :: CommandLibraryVisibilityMap
	for index = 1, #ALL_ROLES do
		local role: RoleKey = ALL_ROLES[index]
		if rolePassesGate(gate, role, nil) then
			map[role] = true
		end
	end
	return map
end

local PUBLIC_VISIBILITY = buildVisibility(ALL_ROLES)

local function makeEntry(props: {
	id: string,
	alias: string,
	description: string,
	category: Types.CommandLibraryCategory,
	needsArguments: boolean,
	iconKey: string?,
	visibleToRoles: CommandLibraryVisibilityMap,
}): CommandLibraryEntry
	return table.freeze({
		id = props.id,
		alias = props.alias,
		display = "/" .. props.alias,
		description = props.description,
		category = props.category,
		needsArguments = props.needsArguments,
		needsTrailingSpace = props.needsArguments,
		iconKey = props.iconKey,
		visibleToRoles = props.visibleToRoles,
	}) :: CommandLibraryEntry
end

local REGISTRY = table.freeze({
	makeEntry({
		id = "setbio",
		alias = Config.AvatarContext.CMD_SET_BIO,
		description = "Set your profile bio. Type /setbio followed by your bio.",
		category = "Profile",
		needsArguments = true,
		iconKey = "profile_edit",
		visibleToRoles = PUBLIC_VISIBILITY,
	}),
	makeEntry({
		id = "clearbio",
		alias = Config.AvatarContext.CMD_CLEAR_BIO,
		description = "Remove your current profile bio.",
		category = "Profile",
		needsArguments = false,
		iconKey = "profile_clear",
		visibleToRoles = PUBLIC_VISIBILITY,
	}),
	makeEntry({
		id = "status",
		alias = Config.AvatarContext.CMD_SET_STATUS,
		description = "Set your profile status. Type /status followed by your status.",
		category = "Profile",
		needsArguments = true,
		iconKey = "status_edit",
		visibleToRoles = PUBLIC_VISIBILITY,
	}),
	makeEntry({
		id = "clearstatus",
		alias = Config.AvatarContext.CMD_CLEAR_STATUS,
		description = "Remove your current profile status.",
		category = "Profile",
		needsArguments = false,
		iconKey = "status_clear",
		visibleToRoles = PUBLIC_VISIBILITY,
	}),
	makeEntry({
		id = "setcommun",
		alias = Config.Community.CMD_ALIAS_SET,
		description = "Set your community badge. Type /setcommun followed by your favorite community name.",
		category = "Community",
		needsArguments = true,
		iconKey = "community_set",
		visibleToRoles = PUBLIC_VISIBILITY,
	}),
	makeEntry({
		id = "clearcommun",
		alias = Config.Community.CMD_ALIAS_CLEAR,
		description = "Remove your current community badge.",
		category = "Community",
		needsArguments = false,
		iconKey = "community_clear",
		visibleToRoles = PUBLIC_VISIBILITY,
	}),
	makeEntry({
		id = "re",
		alias = Config.Session.CMD_ALIAS_REFRESH,
		description = "Refresh your avatar without leaving this server.",
		category = "Session",
		needsArguments = false,
		iconKey = "session_refresh",
		visibleToRoles = PUBLIC_VISIBILITY,
	}),
	makeEntry({
		id = "rejoin",
		alias = Config.Session.CMD_ALIAS_REJOIN,
		description = "Rejoin this server and return to your last saved position.",
		category = "Session",
		needsArguments = false,
		iconKey = "session_rejoin",
		visibleToRoles = PUBLIC_VISIBILITY,
	}),
	makeEntry({
		id = "bring",
		alias = Config.Session.CMD_ALIAS_BRING,
		description = "Bring another player to your position. Type /bring followed by the player name.",
		category = "Session",
		needsArguments = true,
		iconKey = "session_bring",
		visibleToRoles = buildGateVisibility("canTeleport"),
	}),
	makeEntry({
		id = "to",
		alias = Config.Session.CMD_ALIAS_TO,
		description = "Move yourself to another player. Type /to followed by the player name.",
		category = "Session",
		needsArguments = true,
		iconKey = "session_to",
		visibleToRoles = buildGateVisibility("canTeleport"),
	}),
	makeEntry({
		id = "gravity",
		alias = Config.Gravity.CMD_ALIAS,
		description = "Restore normal gravity (turun). Shift+G also works.",
		category = "Session",
		needsArguments = false,
		iconKey = "session_refresh",
		visibleToRoles = PUBLIC_VISIBILITY,
	}),
	makeEntry({
		id = "ungravity",
		alias = Config.Gravity.CMD_ALIAS_UNGRAVITY,
		description = "Float upward (melayang). /ungravity 1-10 sets speed. Shift+U also works. /gravity or Shift+G to restore.",
		category = "Session",
		needsArguments = false,
		iconKey = "session_refresh",
		visibleToRoles = PUBLIC_VISIBILITY,
	}),
	makeEntry({
		id = "announce",
		alias = Config.Announcement.CMD_ALIAS_ANNOUNCE,
		description = "Broadcast a server announcement (Tier2+). Type /announce or /a followed by your message.",
		category = "Admin",
		needsArguments = true,
		iconKey = "admin_announce",
		visibleToRoles = buildGateVisibility("canAnnounce"),
	}),
	makeEntry({
		id = "gift",
		alias = Config.Gift.CMD_ALIAS_GIFT,
		description = "Give a membership to another player. Type /gift followed by the player name and membership tier, or /gift all <tier> to gift everyone.",
		category = "Admin",
		needsArguments = true,
		iconKey = "admin_gift",
		visibleToRoles = buildGateVisibility("admin"),
	}),
	makeEntry({
		id = "ungift",
		alias = Config.Gift.CMD_ALIAS_UNGIFT,
		description = "Remove a gifted membership from another player. Type /ungift followed by the player name and membership tier.",
		category = "Admin",
		needsArguments = true,
		iconKey = "admin_ungift",
		visibleToRoles = buildGateVisibility("admin"),
	}),
	makeEntry({
		id = "setrole",
		alias = Config.SetRole.CMD_ALIAS_SET,
		description = "Set a role override for another player. Type /setrole followed by the player name and role.",
		category = "Admin",
		needsArguments = true,
		iconKey = "admin_setrole",
		visibleToRoles = buildGateVisibility("admin"),
	}),
	makeEntry({
		id = "unsetrole",
		alias = Config.SetRole.CMD_ALIAS_UNSET,
		description = "Remove a role override from another player. Type /unsetrole followed by the player name.",
		category = "Admin",
		needsArguments = true,
		iconKey = "admin_unsetrole",
		visibleToRoles = buildGateVisibility("admin"),
	}),
	makeEntry({
		id = "setrobux",
		alias = Config.Donation.CMD_ADD_ROBUX,
		description = "Add Robux to a player's leaderboard total. /setrobux <player> <amount>",
		category = "Admin",
		needsArguments = true,
		iconKey = "admin_donation",
		visibleToRoles = buildGateVisibility("owner"),
	}),
	makeEntry({
		id = "removerobux",
		alias = Config.Donation.CMD_REMOVE_ROBUX,
		description = "Remove Robux from leaderboard total. /removerobux <player> [amount]",
		category = "Admin",
		needsArguments = true,
		iconKey = "admin_donation",
		visibleToRoles = buildGateVisibility("owner"),
	}),
	makeEntry({
		id = "donatecash",
		alias = Config.Donation.CMD_DONATE_CASH,
		description = "Manual IDR donation with notif + VFX. /donatecash <player> <amount> [message]",
		category = "Admin",
		needsArguments = true,
		iconKey = "admin_donation",
		visibleToRoles = buildGateVisibility("owner"),
	}),
	makeEntry({
		id = "addcash",
		alias = Config.Donation.CMD_ADD_CASH,
		description = "Add IDR to leaderboard only (no donation card/VFX). /addcash <player> <amount>",
		category = "Admin",
		needsArguments = true,
		iconKey = "admin_donation",
		visibleToRoles = buildGateVisibility("owner"),
	}),
	makeEntry({
		id = "removecash",
		alias = Config.Donation.CMD_REMOVE_CASH,
		description = "Remove IDR from manual cash adjustment. /removecash <player> [amount]",
		category = "Admin",
		needsArguments = true,
		iconKey = "admin_donation",
		visibleToRoles = buildGateVisibility("owner"),
	}),
	makeEntry({
		id = "donatebagibagi",
		alias = Config.Donation.CMD_DONATE_BAGIBAGI,
		description = "Deprecated alias for /donatecash.",
		category = "Admin",
		needsArguments = true,
		iconKey = "admin_donation",
		visibleToRoles = buildGateVisibility("owner"),
	}),
	makeEntry({
		id = "addbagibagi",
		alias = Config.Donation.CMD_ADD_BAGIBAGI,
		description = "Deprecated alias for /addcash.",
		category = "Admin",
		needsArguments = true,
		iconKey = "admin_donation",
		visibleToRoles = buildGateVisibility("owner"),
	}),
	makeEntry({
		id = "removebagibagi",
		alias = Config.Donation.CMD_REMOVE_BAGIBAGI,
		description = "Deprecated alias for /removecash.",
		category = "Admin",
		needsArguments = true,
		iconKey = "admin_donation",
		visibleToRoles = buildGateVisibility("owner"),
	}),
	makeEntry({
		id = "testcash",
		alias = Config.Donation.CMD_TEST_CASH,
		description = "Test IDR/cash donation preview (notif + aura + world VFX, no persist). /testcash <idr amount>",
		category = "Admin",
		needsArguments = true,
		iconKey = "admin_donation",
		visibleToRoles = buildGateVisibility("admin"),
	}),
	makeEntry({
		id = "testsaweria",
		alias = "testsaweria",
		description = "Deprecated alias for /testcash. /testsaweria <idr amount>",
		category = "Admin",
		needsArguments = true,
		iconKey = "admin_donation",
		visibleToRoles = buildGateVisibility("admin"),
	}),
	makeEntry({
		id = "testrobux",
		alias = "testrobux",
		description = "Test Robux donation preview (notif + aura only, no persist). /testrobux <robux amount>",
		category = "Admin",
		needsArguments = true,
		iconKey = "admin_donation",
		visibleToRoles = buildGateVisibility("admin"),
	}),
	makeEntry({
		id = "testdonate",
		alias = "testdonate",
		description = "Deprecated alias for /testcash. /testdonate <idr amount>",
		category = "Admin",
		needsArguments = true,
		iconKey = "admin_donation",
		visibleToRoles = buildGateVisibility("admin"),
	}),
})

function CommandLibraryDomain.getRegistry(): {CommandLibraryEntry}
	return REGISTRY
end

function CommandLibraryDomain.ensureLeadingSlash(text: string): string
	if text == "" then
		return "/"
	end

	local withoutLeadingWhitespace = text:gsub("^%s+", "")
	if withoutLeadingWhitespace == "" then
		return "/"
	end

	if string.sub(withoutLeadingWhitespace, 1, 1) == "/" then
		return withoutLeadingWhitespace
	end

	return "/" .. withoutLeadingWhitespace
end

function CommandLibraryDomain.stripLeadingSlash(text: string): string
	if string.sub(text, 1, 1) == "/" then
		return string.sub(text, 2)
	end
	return text
end

function CommandLibraryDomain.normalizeInput(text: string): string
	return CommandLibraryDomain.ensureLeadingSlash(text)
end

function CommandLibraryDomain.getTypedAlias(text: string): string
	local normalized = CommandLibraryDomain.stripLeadingSlash(text)
	local alias = normalized:match("^(%S*)")
	return string.lower(alias or "")
end

function CommandLibraryDomain.canRoleSeeEntry(
	entry: CommandLibraryEntry,
	role: RoleKey,
	effectiveMembership: string?
): boolean
	local gate = ENTRY_GATES[entry.id]
	if gate then
		return rolePassesGate(gate, role, effectiveMembership)
	end
	return entry.visibleToRoles[role] == true
end

function CommandLibraryDomain.getVisibleEntries(role: RoleKey, effectiveMembership: string?): {CommandLibraryEntry}
	local visible = {}
	for _, entry in ipairs(REGISTRY) do
		if CommandLibraryDomain.canRoleSeeEntry(entry, role, effectiveMembership) then
			table.insert(visible, entry)
		end
	end
	return visible
end

function CommandLibraryDomain.isPrefixMatch(entry: CommandLibraryEntry, text: string): boolean
	local query = CommandLibraryDomain.getTypedAlias(text)
	if query == "" then
		return true
	end
	return string.sub(entry.alias, 1, #query) == query
end

function CommandLibraryDomain.sortEntries(entries: {CommandLibraryEntry}): {CommandLibraryEntry}
	table.sort(entries, function(a, b)
		if #a.alias ~= #b.alias then
			return #a.alias < #b.alias
		end
		return a.alias < b.alias
	end)
	return entries
end

function CommandLibraryDomain.filterEntries(entries: {CommandLibraryEntry}, text: string): {CommandLibraryEntry}
	local filtered = {}
	for _, entry in ipairs(entries) do
		if CommandLibraryDomain.isPrefixMatch(entry, text) then
			table.insert(filtered, entry)
		end
	end
	return CommandLibraryDomain.sortEntries(filtered)
end

function CommandLibraryDomain.getBestSuggestion(entries: {CommandLibraryEntry}, text: string): string?
	local query = CommandLibraryDomain.getTypedAlias(text)
	if query == "" then
		return nil
	end

	local filtered = CommandLibraryDomain.filterEntries(entries, text)
	local first = filtered[1]
	if not first then
		return nil
	end

	if first.alias == query then
		return nil
	end

	return "/" .. first.alias
end

function CommandLibraryDomain.formatFillText(entry: CommandLibraryEntry): string
	if entry.needsTrailingSpace then
		return entry.display .. " "
	end
	return entry.display
end

return CommandLibraryDomain
