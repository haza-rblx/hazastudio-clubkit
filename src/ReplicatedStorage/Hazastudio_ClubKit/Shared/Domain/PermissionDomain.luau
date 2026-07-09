--!strict
-- Permission checks derived from RoleCategories and SpenderRoles config.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local RolesDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.RolesDomain)

local PermissionDomain = {}

local PERMISSION_ALIASES = {
	adminPanel = "adminPanel",
	canGift = "canGift",
	canAnnounce = "canAnnounce",
	canTeleport = "canTeleport",
	musicManage = "musicManage",
}

local function getRoleDefinition(roleKey: string): any?
	local roles = Config.Roles
	if type(roles) ~= "table" or type(roles.DEFINITIONS) ~= "table" then
		return nil
	end
	local canonical = RolesDomain.normalizeRoleKey(roleKey) or roleKey
	return roles.DEFINITIONS[canonical]
end

local function getCategoryPrivileges(roleKey: string): { [string]: boolean }?
	local privileges = Config.RolePrivileges
	if type(privileges) ~= "table" then
		return nil
	end
	local roleToCategory = privileges.ROLE_TO_CATEGORY
	local categoryPrivileges = privileges.CATEGORY_PRIVILEGES
	if type(roleToCategory) ~= "table" or type(categoryPrivileges) ~= "table" then
		return nil
	end
	local canonical = RolesDomain.normalizeRoleKey(roleKey) or roleKey
	local categoryId = roleToCategory[canonical]
	if type(categoryId) ~= "number" then
		return nil
	end
	return categoryPrivileges[categoryId]
end

local function getSpenderPrivileges(roleKey: string): { [string]: boolean }?
	local definition = getRoleDefinition(roleKey)
	if type(definition) ~= "table" then
		return nil
	end
	local spenderPrivileges = definition.spenderPrivileges
	if type(spenderPrivileges) == "table" then
		return spenderPrivileges
	end
	return nil
end

function PermissionDomain.hasPermission(roleKey: string?, permissionId: string): boolean
	if type(roleKey) ~= "string" or roleKey == "" then
		return false
	end
	local permission = PERMISSION_ALIASES[permissionId] or permissionId
	local canonical = RolesDomain.normalizeRoleKey(roleKey) or roleKey

	if canonical == "Owner" and permission == "canGift" then
		return true
	end
	if canonical == "Owner" and permission == "adminPanel" then
		return true
	end

	local definition = getRoleDefinition(canonical)
	if type(definition) == "table" then
		if permission == "canGift" and definition.canGift == true then
			return true
		end
	end

	local categoryPrivileges = getCategoryPrivileges(canonical)
	if type(categoryPrivileges) == "table" and categoryPrivileges[permission] == true then
		return true
	end

	local spenderPrivileges = getSpenderPrivileges(canonical)
	if type(spenderPrivileges) == "table" and spenderPrivileges[permission] == true then
		return true
	end

	return false
end

function PermissionDomain.isAdminUser(userId: number?): boolean
	if type(userId) ~= "number" or userId <= 0 then
		return false
	end
	local ownerUserId = Config.Group.OWNER_USER_ID
	if type(ownerUserId) == "number" and ownerUserId > 0 and userId == ownerUserId then
		return true
	end
	local adminUserIds = Config.AdminUserIds
	return type(adminUserIds) == "table" and adminUserIds[userId] == true
end

function PermissionDomain.canGift(roleKey: string?, userId: number?): boolean
	if PermissionDomain.isAdminUser(userId) then
		return true
	end
	return PermissionDomain.hasPermission(roleKey, "canGift")
end

function PermissionDomain.canUseAdminPanel(roleKey: string?, userId: number?): boolean
	if PermissionDomain.isAdminUser(userId) then
		return true
	end
	return PermissionDomain.hasPermission(roleKey, "adminPanel") or PermissionDomain.hasPermission(roleKey, "canGift")
end

function PermissionDomain.canAnnounce(roleKey: string?, effectiveMembership: string?): boolean
	if PermissionDomain.hasPermission(roleKey, "canAnnounce") then
		return true
	end
	local RolesDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.RolesDomain)
	local normalized = RolesDomain.normalizeRoleKey(roleKey)
	if normalized == "RoyaleSpender" or normalized == "TopSpender" or normalized == "Spender" then
		return true
	end
	local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
	return OverheadDomain.hasRolePriorityAtLeast(roleKey, "Staff")
		or OverheadDomain.hasMembershipAtLeast(effectiveMembership, "Tier2")
		or OverheadDomain.hasMembershipAtLeast(roleKey, "Tier2")
end

function PermissionDomain.canTeleport(roleKey: string?, effectiveMembership: string?): boolean
	if PermissionDomain.hasPermission(roleKey, "canTeleport") then
		return true
	end
	local RolesDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.RolesDomain)
	local normalized = RolesDomain.normalizeRoleKey(roleKey)
	if normalized == "RoyaleSpender" or normalized == "TopSpender" or normalized == "Spender" then
		return true
	end
	local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
	return OverheadDomain.hasRolePriorityAtLeast(roleKey, "Staff")
		or OverheadDomain.hasMembershipAtLeast(effectiveMembership, "Tier3")
		or OverheadDomain.hasMembershipAtLeast(roleKey, "Tier3")
end

function PermissionDomain.canManageMusic(roleKey: string?, userId: number?): boolean
	if PermissionDomain.isAdminUser(userId) then
		return true
	end
	return PermissionDomain.hasPermission(roleKey, "musicManage")
end

return PermissionDomain
