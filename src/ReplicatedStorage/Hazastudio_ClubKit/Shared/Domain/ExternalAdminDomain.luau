--!strict
-- Pure helpers for the External Admin Bridge (Adonis / Kohl's).
-- No Roblox services referenced: the external-admin config table is always
-- passed in by the caller (facade reads Config.ExternalAdmin) so this module
-- stays headless-testable.

local ExternalAdminDomain = {}

export type Provider = "Adonis" | "Kohls" | "None"

export type RankMapEntry = {
	adonis: number?,
	kohls: string?,
}

export type ExternalAdminConfig = {
	Provider: string?,
	SyncStaffRoles: boolean?,
	SyncContentRoles: boolean?,
	RankMap: { [string]: RankMapEntry? }?,
}

local PROVIDER_ALIASES: { [string]: Provider } = {
	adonis = "Adonis",
	kohls = "Kohls",
	["kohl's"] = "Kohls",
	kohl = "Kohls",
	none = "None",
	[""] = "None",
}

-- Staff roles eligible for rank sync when SyncStaffRoles = true.
local STAFF_ROLES: { [string]: boolean } = {
	Owner = true,
	CoOwner = true,
	Staff = true,
	Moderator = true,
}

-- Membership + Spender roles never touch external admin ranks
-- (Kohl's "vip" collision + volatile leaderboard-driven roles).
local NEVER_SYNC_ROLES: { [string]: boolean } = {
	vip = true,
	vvip = true,
	supreme = true,
	spender = true,
	topspender = true,
	royalespender = true,
}

function ExternalAdminDomain.normalizeProvider(provider: string?): Provider
	local key = string.lower(tostring(provider or ""))
	key = string.gsub(key, "%s+", "")
	return PROVIDER_ALIASES[key] or "None"
end

function ExternalAdminDomain.isNeverSyncRole(roleKey: string?): boolean
	if type(roleKey) ~= "string" or roleKey == "" then
		return false
	end
	return NEVER_SYNC_ROLES[string.lower(roleKey)] == true
end

function ExternalAdminDomain.isStaffRole(roleKey: string?): boolean
	if type(roleKey) ~= "string" or roleKey == "" then
		return false
	end
	return STAFF_ROLES[roleKey] == true
end

-- A role syncs to the external admin when: not never-sync, present in RankMap,
-- and its class toggle is on (staff roles → SyncStaffRoles, anything else a
-- buyer added to RankMap → SyncContentRoles).
function ExternalAdminDomain.shouldSyncRole(config: ExternalAdminConfig?, roleKey: string?): boolean
	if type(config) ~= "table" or type(roleKey) ~= "string" or roleKey == "" then
		return false
	end
	if ExternalAdminDomain.isNeverSyncRole(roleKey) then
		return false
	end
	local rankMap = config.RankMap
	if type(rankMap) ~= "table" or type(rankMap[roleKey]) ~= "table" then
		return false
	end
	if ExternalAdminDomain.isStaffRole(roleKey) then
		return config.SyncStaffRoles == true
	end
	return config.SyncContentRoles == true
end

-- External rank target for the given role + provider (Adonis level number or
-- Kohl's role key). Nil when the role must not sync or has no mapping.
function ExternalAdminDomain.resolveRankTarget(config: ExternalAdminConfig?, roleKey: string?): (number | string)?
	if not ExternalAdminDomain.shouldSyncRole(config, roleKey) then
		return nil
	end
	local cfg = config :: ExternalAdminConfig
	local provider = ExternalAdminDomain.normalizeProvider(cfg.Provider)
	if provider == "None" then
		return nil
	end
	local entry = (cfg.RankMap :: { [string]: RankMapEntry? })[roleKey :: string]
	if type(entry) ~= "table" then
		return nil
	end
	if provider == "Adonis" then
		return if type(entry.adonis) == "number" then entry.adonis else nil
	end
	return if type(entry.kohls) == "string" and entry.kohls ~= "" then entry.kohls else nil
end

return ExternalAdminDomain
