--!strict
-- Owns persistence for the About team roster shown in settings/about UI.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local ResultUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local BudgetGate = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetGate)
local CrossServerCache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.CrossServerCache)

local ABOUT_ROSTER_INVALIDATE_TOPIC = "AboutRosterInvalidate"

type Result<T> = Types.Result<T>
type AboutRosterEntry = Types.AboutRosterEntry
type IAboutRosterRepository = Types.IAboutRosterRepository

local ABOUT_ROLE_KEYS: { [string]: true } = {
	Owner = true,
	Investor = true,
	Staff = true,
	CoOwner = true, -- legacy persisted keys
	Developer = true,
	Admin = true,
}

local function sanitizeAboutRoster(raw: any): any
	local roster = { roles = {} }
	if type(raw) ~= "table" or type(raw.roles) ~= "table" then
		return roster
	end

	for roleKey in pairs(ABOUT_ROLE_KEYS) do
		local rawRoleEntries = raw.roles[roleKey]
		local roleEntries = {}
		if type(rawRoleEntries) == "table" then
			for rawUserId, rawEntry in pairs(rawRoleEntries) do
				if type(rawEntry) == "table" and type(rawEntry.userId) == "number" then
					local key = tostring(rawEntry.userId)
					roleEntries[key] = {
						userId = rawEntry.userId,
						displayName = tostring(rawEntry.displayName or rawEntry.username or ""),
						username = tostring(rawEntry.username or ""),
						role = roleKey,
						updatedAt = if type(rawEntry.updatedAt) == "number" then rawEntry.updatedAt else 0,
					}
				elseif type(rawUserId) == "string" then
					local userId = tonumber(rawUserId)
					if userId then
						roleEntries[tostring(userId)] = {
							userId = userId,
							displayName = "",
							username = "",
							role = roleKey,
							updatedAt = 0,
						}
					end
				end
			end
		end
		roster.roles[roleKey] = roleEntries
	end

	return roster
end

local function flattenAboutRoster(roster: any): { AboutRosterEntry }
	local entries = {} :: { AboutRosterEntry }
	local roles = type(roster) == "table" and roster.roles or {}
	for roleKey in pairs(ABOUT_ROLE_KEYS) do
		local roleEntries = type(roles) == "table" and roles[roleKey] or nil
		if type(roleEntries) == "table" then
			for _, entry in pairs(roleEntries) do
				table.insert(entries, entry :: AboutRosterEntry)
			end
		end
	end
	return entries
end

local function createAboutRosterRepository(datastoreKey: string?): IAboutRosterRepository
	local key = datastoreKey or Config.DataStore.ABOUT_ROSTER_KEY
	local store = DataStoreService:GetDataStore(key)
	local log = Logger.new("AboutRosterRepository")
	local budgetGate = BudgetGate.create({ logger = log, name = "AboutRosterRepository" })
	local cache: any? = nil
	local cacheExpiresAt: number = 0
	local CACHE_TTL = 120 -- 2 minutes
	local repo = {} :: IAboutRosterRepository

	CrossServerCache.subscribe(ABOUT_ROSTER_INVALIDATE_TOPIC, function(_userId: number)
		repo:invalidateCache()
	end)

	function repo:isRosterRole(role: string): boolean
		return ABOUT_ROLE_KEYS[role] == true
	end

	function repo:loadEntries(): Result<{ AboutRosterEntry }>
		if cache and os.clock() < cacheExpiresAt then
			return ResultUtil.Ok(flattenAboutRoster(cache))
		end

		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.GetAsync, function()
			return ResultUtil.withRetry(function()
				return store:GetAsync(Config.DataStore.ABOUT_ROSTER_ENTRY_KEY)
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)
		if not result.ok then
			log:warn("About roster load failed", { error = result.error })
			cache = sanitizeAboutRoster(nil)
			cacheExpiresAt = os.clock() + CACHE_TTL
			return ResultUtil.Err(result.error)
		end

		cache = sanitizeAboutRoster(result.value)
		cacheExpiresAt = os.clock() + CACHE_TTL
		return ResultUtil.Ok(flattenAboutRoster(cache))
	end

	function repo:upsertEntry(entry: AboutRosterEntry): Result<{ AboutRosterEntry }>
		if not self:isRosterRole(entry.role) then
			return self:loadEntries()
		end

		local updatedRoster: any? = nil
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			return ResultUtil.withRetry(function()
				return store:UpdateAsync(Config.DataStore.ABOUT_ROSTER_ENTRY_KEY, function(current: any): any
					local roster = sanitizeAboutRoster(current)
					for _, roleEntries in pairs(roster.roles) do
						if type(roleEntries) == "table" then
							roleEntries[tostring(entry.userId)] = nil
						end
					end

					local roleEntries = roster.roles[entry.role]
					if type(roleEntries) ~= "table" then
						roleEntries = {}
						roster.roles[entry.role] = roleEntries
					end

					roleEntries[tostring(entry.userId)] = {
						userId = entry.userId,
						displayName = entry.displayName,
						username = entry.username,
						role = entry.role,
						updatedAt = entry.updatedAt,
					}
					updatedRoster = roster
					return roster
				end)
			end, Config.DataStore.RETRY_ATTEMPTS)
		end)
		if not result.ok then
			log:warn("About roster update failed", { userId = entry.userId, error = result.error })
			return ResultUtil.Err(result.error)
		end

		cache = sanitizeAboutRoster(updatedRoster or result.value)
		cacheExpiresAt = os.clock() + CACHE_TTL
		CrossServerCache.publish(ABOUT_ROSTER_INVALIDATE_TOPIC, 0)
		return ResultUtil.Ok(flattenAboutRoster(cache))
	end

	function repo:invalidateCache()
		cache = nil
		cacheExpiresAt = 0
	end

	return repo
end

return createAboutRosterRepository
