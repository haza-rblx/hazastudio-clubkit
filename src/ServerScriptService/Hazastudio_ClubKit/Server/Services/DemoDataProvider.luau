--!strict
-- Server/Services/DemoDataProvider.lua
--
-- Generates fake leaderboard data for demo/showcase mode.
-- Donor boards: friend list / Profiles. Community board: group milik Group.OwnerUserId.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local HttpApi = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApi)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

local log = Logger.new("DemoDataProvider")

export type DemoConfig = {
	SOURCE_USER_ID: number?,
	LEADERBOARD_USE_OWNER_ONLY: boolean?,
	MIN_AMOUNT: number?,
	MAX_AMOUNT: number?,
	ROBUX_MIN_AMOUNT: number?,
	ROBUX_MAX_AMOUNT: number?,
	LEADERBOARD_LIMIT: number?,
	REFRESH_INTERVAL: number?,
	SHOWCASE_PROFILES: { { userId: number, username: string, displayName: string } }?,
	SHOWCASE_COMMUNITIES: { { communityId: number, communityName: string, communityLogo: string } }?,
}

export type DemoDataProvider = {
	buildPayload: (self: DemoDataProvider) -> { [string]: any },
	isReady: (self: DemoDataProvider) -> boolean,
	reset: (self: DemoDataProvider) -> (),
}

local DemoDataProvider = {}

-- Fallback profiles when friend list is empty (solo Studio play). Real userIds for thumbnails.
local FALLBACK_PROFILES = {
	{ userId = 1, username = "Roblox", displayName = "Roblox" },
	{ userId = 156, username = "builderman", displayName = "Builderman" },
	{ userId = 261, username = "Shedletsky", displayName = "Shedletsky" },
	{ userId = 24813335, username = "Jandel", displayName = "Jandel" },
	{ userId = 1210210, username = "Sorcus", displayName = "Sorcus" },
	{ userId = 261, username = "JohnDoe", displayName = "John Doe" },
	{ userId = 712, username = "JaneClub", displayName = "Jane Club" },
	{ userId = 1138, username = "NeonVibes", displayName = "Neon Vibes" },
	{ userId = 2034992, username = "BassDrop", displayName = "Bass Drop" },
	{ userId = 80254, username = "NightOwl", displayName = "Night Owl" },
}

local function resolveCommunityLogo(groupInfo: any, groupId: number): string
	local logo = if type(groupInfo) == "table" then groupInfo.EmblemUrl else nil
	if type(logo) == "string" and logo ~= "" then
		return logo
	end
	return ("rbxthumb://type=GroupIcon&id=%d&w=150&h=150"):format(groupId)
end

local function fetchOwnerCommunities(
	ownerUserId: number,
	limit: number
): { { communityId: number, communityName: string, communityLogo: string } }
	if ownerUserId <= 0 then
		return {}
	end

	local groups = HttpApi.getGroupsAsync(ownerUserId)
	if type(groups) ~= "table" or #groups == 0 then
		log:warn("Owner has no groups for showcase community leaderboard", { ownerUserId = ownerUserId })
		return {}
	end

	local communities = {} :: { { communityId: number, communityName: string, communityLogo: string } }
	for _, groupInfo in ipairs(groups) do
		if #communities >= limit then
			break
		end
		local groupId = if type(groupInfo) == "table" then tonumber(groupInfo.Id) or 0 else 0
		if groupId > 0 then
			local groupName = if type(groupInfo) == "table" and type(groupInfo.Name) == "string" and groupInfo.Name ~= ""
				then groupInfo.Name
				else ("Group " .. tostring(groupId))
			table.insert(communities, {
				communityId = groupId,
				communityName = groupName,
				communityLogo = resolveCommunityLogo(groupInfo, groupId),
			})
		end
	end

	return communities
end

local function getUserThumbnail(userId: number): string
	local ok, thumbnail = pcall(function()
		return Players:GetUserThumbnailAsync(
			userId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size150x150
		)
	end)
	if ok and type(thumbnail) == "string" then
		return thumbnail
	end
	return ""
end

local function fetchFriends(sourceUserId: number, limit: number): { { userId: number, username: string, displayName: string } }
	local friends: { { userId: number, username: string, displayName: string } } = {}
	local ok, pages = pcall(function()
		return Players:GetFriendsAsync(sourceUserId)
	end)
	if not ok or not pages then
		log:warn("Failed to fetch friend list", { userId = sourceUserId })
		return friends
	end

	while true do
		for _, item in ipairs(pages:GetCurrentPage()) do
			if #friends >= limit then
				break
			end
			table.insert(friends, {
				userId = item.Id,
				username = item.Username or ("User" .. tostring(item.Id)),
				displayName = item.DisplayName or item.Username or ("User" .. tostring(item.Id)),
			})
		end
		if #friends >= limit or pages.IsFinished then
			break
		end
		local advanceOk = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if not advanceOk then
			break
		end
	end

	return friends
end

local function collectServerProfiles(limit: number): { { userId: number, username: string, displayName: string } }
	local profiles = {} :: { { userId: number, username: string, displayName: string } }
	for _, player in ipairs(Players:GetPlayers()) do
		if #profiles >= limit then
			break
		end
		table.insert(profiles, {
			userId = player.UserId,
			username = player.Name,
			displayName = player.DisplayName,
		})
	end
	return profiles
end

local function buildProfilePool(
	sourceUserId: number,
	limit: number,
	customProfiles: { { userId: number, username: string, displayName: string } }?
): { { userId: number, username: string, displayName: string } }
	local pool = {} :: { { userId: number, username: string, displayName: string } }
	local seen: { [number]: boolean } = {}

	local function addProfile(profile: { userId: number, username: string, displayName: string })
		if seen[profile.userId] then
			return
		end
		seen[profile.userId] = true
		table.insert(pool, profile)
	end

	for _, profile in ipairs(collectServerProfiles(limit)) do
		addProfile(profile)
	end

	local resolvedUserId = sourceUserId
	if resolvedUserId <= 0 and #pool > 0 then
		resolvedUserId = pool[1].userId
	end
	if resolvedUserId > 0 then
		for _, profile in ipairs(fetchFriends(resolvedUserId, limit * 2)) do
			addProfile(profile)
			if #pool >= limit * 2 then
				break
			end
		end
	end

	if #pool > 0 then
		return pool
	end

	local fallbackProfiles = if type(customProfiles) == "table" and #customProfiles > 0
		then customProfiles
		else FALLBACK_PROFILES
	for _, profile in ipairs(fallbackProfiles) do
		addProfile(profile)
		if #pool >= limit * 2 then
			break
		end
	end

	return pool
end

local function resolveUserProfile(userId: number): { userId: number, username: string, displayName: string }?
	if userId <= 0 then
		return nil
	end

	local username = "User" .. tostring(userId)
	local displayName = username
	pcall(function()
		username = Players:GetNameFromUserIdAsync(userId)
		displayName = username
	end)

	local ok, infos = pcall(function()
		return Players:GetUserInfosByUserIdsAsync({ userId })
	end)
	if ok and type(infos) == "table" and infos[1] then
		local info = infos[1]
		if type(info.Username) == "string" and info.Username ~= "" then
			username = info.Username
		end
		if type(info.DisplayName) == "string" and info.DisplayName ~= "" then
			displayName = info.DisplayName
		end
	end

	return {
		userId = userId,
		username = username,
		displayName = displayName,
	}
end

local function buildOwnerOnlyProfilePool(sourceUserId: number, limit: number): { { userId: number, username: string, displayName: string } }
	local pool = {} :: { { userId: number, username: string, displayName: string } }
	local seen: { [number]: boolean } = {}

	local function addProfile(profile: { userId: number, username: string, displayName: string }?)
		if not profile or seen[profile.userId] then
			return
		end
		seen[profile.userId] = true
		table.insert(pool, profile)
	end

	addProfile(resolveUserProfile(sourceUserId))
	for _, profile in ipairs(fetchFriends(sourceUserId, limit * 2)) do
		addProfile(profile)
		if #pool >= limit * 2 then
			break
		end
	end

	return pool
end

local function randomAmount(min: number, max: number): number
	return math.random(min, max)
end

local function generateUserSorted(
	profiles: any,
	min: number,
	max: number,
	limit: number,
	withSaweriaName: boolean?
): { any }
	local entries = {}
	for i, profile in ipairs(profiles) do
		if i > limit then
			break
		end
		local amount = randomAmount(min, max)
		amount = amount + (limit - i) * math.floor((max - min) / math.max(limit, 1))
		local entry: any = {
			rank = i,
			userId = profile.userId,
			username = profile.username,
			displayName = profile.displayName,
			thumbnail = getUserThumbnail(profile.userId),
			total = amount,
			lastDonationAt = os.time() - math.random(0, 86400),
			isLinked = true,
		}
		if withSaweriaName == true then
			entry.saweriaName = profile.displayName
		end
		table.insert(entries, entry)
	end
	table.sort(entries, function(a, b)
		return a.total > b.total
	end)
	for i, entry in ipairs(entries) do
		entry.rank = i
	end
	return entries
end

local function generateCommunitySorted(
	communities: { { communityId: number, communityName: string, communityLogo: string } },
	min: number,
	max: number,
	limit: number
): { any }
	local entries = {}
	for i, community in ipairs(communities) do
		if i > limit then
			break
		end
		local amount = randomAmount(min, max)
		amount = amount + (limit - i) * math.floor((max - min) / math.max(limit, 1))
		table.insert(entries, {
			rank = i,
			communityId = community.communityId,
			communityName = community.communityName,
			communityLogo = community.communityLogo,
			total = amount,
		})
	end
	table.sort(entries, function(a, b)
		return a.total > b.total
	end)
	for i, entry in ipairs(entries) do
		entry.rank = i
	end
	return entries
end

function DemoDataProvider.create(config: DemoConfig?): DemoDataProvider
	local cfg = config or {}
	local useOwnerOnly = cfg.LEADERBOARD_USE_OWNER_ONLY == true
	local sourceUserId = if useOwnerOnly
		then math.max(0, tonumber(Config.Group.OWNER_USER_ID) or 0)
		else (tonumber(cfg.SOURCE_USER_ID) or 0)
	local minAmount = math.max(1000, tonumber(cfg.MIN_AMOUNT) or 100000)
	local maxAmount = math.max(minAmount + 1, tonumber(cfg.MAX_AMOUNT) or 10000000)
	local robuxMin = math.max(1, tonumber(cfg.ROBUX_MIN_AMOUNT) or 100)
	local robuxMax = math.max(robuxMin + 1, tonumber(cfg.ROBUX_MAX_AMOUNT) or 50000)
	local limit = math.clamp(tonumber(cfg.LEADERBOARD_LIMIT) or 10, 1, 50)
	local refreshInterval = math.max(10, tonumber(cfg.REFRESH_INTERVAL) or 300)
	local showcaseProfiles = cfg.SHOWCASE_PROFILES
	local ownerUserId = math.max(0, tonumber(Config.Group.OWNER_USER_ID) or 0)
	local customCommunities = if type(cfg.SHOWCASE_COMMUNITIES) == "table" and #cfg.SHOWCASE_COMMUNITIES > 0
		then cfg.SHOWCASE_COMMUNITIES
		else nil

	local cachedProfiles: { any } = {}
	local cachedCommunities: { { communityId: number, communityName: string, communityLogo: string } } = {}
	local cachedPayload: { [string]: any }? = nil
	local lastBuildAt = 0
	local profilesFetched = false
	local communitiesFetched = false

	local self = {} :: DemoDataProvider

	local function ensureProfiles()
		if profilesFetched then
			return
		end
		if useOwnerOnly then
			if sourceUserId <= 0 then
				log:warn("Showcase owner-only mode enabled but Group.OWNER_USER_ID is unset")
				cachedProfiles = {}
			else
				cachedProfiles = buildOwnerOnlyProfilePool(sourceUserId, limit)
			end
		else
			cachedProfiles = buildProfilePool(sourceUserId, limit, showcaseProfiles)
		end
		profilesFetched = true
		log:info("Showcase profiles ready", {
			count = #cachedProfiles,
			source = sourceUserId,
			ownerOnly = useOwnerOnly,
		})
	end

	local function ensureCommunities()
		if communitiesFetched then
			return
		end
		if customCommunities then
			cachedCommunities = customCommunities
		else
			cachedCommunities = fetchOwnerCommunities(ownerUserId, limit)
		end
		communitiesFetched = true
		log:info("Showcase communities ready", {
			count = #cachedCommunities,
			ownerUserId = ownerUserId,
			source = if customCommunities then "config" else "owner_groups",
		})
	end

	function self:reset()
		cachedProfiles = {}
		cachedCommunities = {}
		cachedPayload = nil
		lastBuildAt = 0
		profilesFetched = false
		communitiesFetched = false
	end

	function self:isReady(): boolean
		ensureProfiles()
		return #cachedProfiles > 0
	end

	function self:buildPayload(): { [string]: any }
		ensureProfiles()
		ensureCommunities()

		local now = os.clock()
		if cachedPayload and (now - lastBuildAt) < refreshInterval then
			return cachedPayload
		end

		if #cachedProfiles == 0 then
			return {
				updatedAt = os.time(),
				robux = {},
				community = {},
				saweria = {},
				dailySaweria = {},
				dailyRobux = {},
				likes = {},
				boardStates = {
					robux = "empty",
					community = "empty",
					saweria = "empty",
					likes = "empty",
				},
			}
		end

		local robuxEntries = generateUserSorted(cachedProfiles, robuxMin, robuxMax, limit, false)
		local saweriaEntries = generateUserSorted(cachedProfiles, minAmount, maxAmount, limit, true)
		local communityEntries = generateCommunitySorted(cachedCommunities, robuxMin, robuxMax, limit)
		local likesEntries = generateUserSorted(cachedProfiles, 10, 500, limit, false)
		local dailySaweria = generateUserSorted(cachedProfiles, 10000, 500000, math.min(4, limit), true)
		local dailyRobux = if Config.Leaderboards.DAILY_ROBUX_ENABLED == true
			then generateUserSorted(cachedProfiles, robuxMin, math.min(robuxMax, 2000), math.min(4, limit), false)
			else {}

		cachedPayload = {
			updatedAt = os.time(),
			robux = robuxEntries,
			community = communityEntries,
			saweria = saweriaEntries,
			dailySaweria = dailySaweria,
			dailyRobux = dailyRobux,
			likes = likesEntries,
			boardStates = {
				robux = if #robuxEntries > 0 then "ready" else "empty",
				community = if #communityEntries > 0 then "ready" else "empty",
				saweria = if #saweriaEntries > 0 then "ready" else "empty",
				likes = if #likesEntries > 0 then "ready" else "empty",
			},
		}
		lastBuildAt = now
		log:info("Showcase payload built", {
			robux = #robuxEntries,
			community = #communityEntries,
			saweria = #saweriaEntries,
		})
		return cachedPayload
	end

	return self
end

return DemoDataProvider
