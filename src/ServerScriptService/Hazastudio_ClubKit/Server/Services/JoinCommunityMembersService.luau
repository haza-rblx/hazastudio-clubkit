--!strict
-- Server sample of group members for the Join Community modal (thumbnails + copy).
--
-- REAL TOTAL (memberCount):
--   Prefer GroupService:GetGroupInfoAsync → MemberCount when present.
--   Official engine docs do NOT list MemberCount on that table; when missing we
--   do not invent a total from online/pool size. Next: game-data-api /community
--   (Secrets.GameDataApiSecret). MEMBER_INFO_URL / roproxy only when the worker
--   was skipped (no secret) or failed — never in the same resolve after a
--   successful worker response (even if some fields are missing).
--
-- AVATAR SAMPLES:
--   Prefer game-data-api GET /game/:gameKey/community/:groupId (members[] in one
--   response — no separate users fetch). MEMBER_USERS_URL / roproxy only when
--   the worker was skipped or failed. In-experience / MemoryStore pool is
--   secondary fill. Http to groups.roblox.com is blocked from game servers.
--   Studio without GameDataApiSecret falls back to roproxy.

local GroupService = game:GetService("GroupService")
local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local KitProduct = require(ReplicatedStorage.Hazastudio_ClubKit.KitProduct)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local Secrets = require(ServerScriptService.Hazastudio_ClubKitSecrets.Secrets)

export type MemberSample = {
	userId: number,
	displayName: string,
}

export type MembersPayload = {
	groupId: number,
	memberCount: number,
	memberCountKnown: boolean,
	emblemUrl: string?,
	members: { MemberSample },
}

export type Service = {
	destroy: (self: Service) -> (),
}

local function getCfg(): any
	return Config.JoinCommunityPrompt or {}
end

local function ensureRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing:IsA("RemoteEvent") then
			return existing
		end
		existing:Destroy()
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

-- Partial Fisher–Yates: pick up to `limit` random entries without shuffling the whole pool.
local function pickRandomSamples(
	pool: { MemberSample },
	limit: number,
	excludeUserId: number?
): { MemberSample }
	local n = #pool
	if n == 0 or limit <= 0 then
		return {}
	end

	local indices = table.create(n)
	for i = 1, n do
		indices[i] = i
	end

	local out: { MemberSample } = {}
	local write = 1
	while #out < limit and write <= n do
		local j = math.random(write, n)
		indices[write], indices[j] = indices[j], indices[write]
		local sample = pool[indices[write]]
		write += 1
		if sample and (excludeUserId == nil or sample.userId ~= excludeUserId) then
			table.insert(out, {
				userId = sample.userId,
				displayName = sample.displayName,
			})
		end
	end
	return out
end

local function extractMemberCount(info: any): number?
	if type(info) ~= "table" then
		return nil
	end
	local raw: any = (info :: any).MemberCount
	if raw == nil then
		raw = (info :: any).memberCount
	end
	local n = tonumber(raw)
	if type(n) == "number" and n == n and n >= 0 then
		return math.floor(n)
	end
	return nil
end

-- Emblem string fields only (no invented thumb). GroupIcon is applied by caller after a successful group lookup.
local function extractEmblemUrl(info: any): string?
	if type(info) ~= "table" then
		return nil
	end
	local raw: any = (info :: any).EmblemUrl
	if raw == nil then
		raw = (info :: any).emblemUrl
	end
	if raw == nil then
		raw = (info :: any).iconUrl
	end
	if raw == nil then
		raw = (info :: any).IconUrl
	end
	if type(raw) == "string" and raw ~= "" then
		return raw
	end
	return nil
end

local function groupIconThumbUrl(groupId: number): string
	return ("rbxthumb://type=GroupIcon&id=%d&w=150&h=150"):format(groupId)
end

local function isBlockedRobloxHost(url: string): boolean
	local lower = string.lower(url)
	return string.find(lower, "groups.roblox.com", 1, true) ~= nil
		or string.find(lower, "://roblox.com", 1, true) ~= nil
		or string.find(lower, "://www.roblox.com", 1, true) ~= nil
		or string.find(lower, "apis.roblox.com", 1, true) ~= nil
end

-- Roblox GET /v1/groups/{id}/users only accepts these page sizes (else HTTP 400).
local VALID_USERS_PAGE_LIMITS = { 10, 25, 50, 100 }
-- Prefer 50 for thumb sampling (valid + enough variety without maxing proxy load).
local DEFAULT_USERS_PAGE_LIMIT = 50

local function nearestUsersPageLimit(desired: number): number
	local target = if type(desired) == "number" and desired == desired then desired else DEFAULT_USERS_PAGE_LIMIT
	local best = DEFAULT_USERS_PAGE_LIMIT
	local bestDist = math.huge
	for _, allowed in ipairs(VALID_USERS_PAGE_LIMITS) do
		local dist = math.abs(allowed - target)
		-- Prefer larger page on ties (more thumbs to sample from).
		if dist < bestDist or (dist == bestDist and allowed > best) then
			best = allowed
			bestDist = dist
		end
	end
	return best
end

-- Clamp limit= to a Roblox-valid page size; normalize sortOrder to Asc (Desc 400s on some huge groups).
local function sanitizeMemberUsersUrl(url: string, preferredLimit: number): string
	local pageLimit = nearestUsersPageLimit(preferredLimit)
	local limitToken = "limit=" .. tostring(pageLimit)
	local out = url
	if string.find(string.lower(out), "limit=", 1, true) then
		out = (string.gsub(out, "[Ll][Ii][Mm][Ii][Tt]=%d+", limitToken, 1))
	else
		local sep = if string.find(out, "?", 1, true) then "&" else "?"
		out = out .. sep .. limitToken
	end
	if string.find(string.lower(out), "sortorder=", 1, true) then
		out = (string.gsub(out, "[Ss][Oo][Rr][Tt][Oo][Rr][Dd][Ee][Rr]=[^&]*", "sortOrder=Asc", 1))
	end
	return out
end

local function stripSortOrder(url: string): string
	local out = (string.gsub(url, "[?&][Ss][Oo][Rr][Tt][Oo][Rr][Dd][Ee][Rr]=[^&]*", ""))
	out = (string.gsub(out, "%?&", "?"))
	out = (string.gsub(out, "&&+", "&"))
	out = (string.gsub(out, "%?$", ""))
	out = (string.gsub(out, "&$", ""))
	return out
end

-- Rebuild users URL variants for fallback attempts (same host/path, different query).
local function buildUsersUrlVariants(primaryUrl: string, preferredLimit: number): { string }
	local pageLimit = nearestUsersPageLimit(preferredLimit)
	local withAsc = sanitizeMemberUsersUrl(primaryUrl, pageLimit)
	local noSort = sanitizeMemberUsersUrl(stripSortOrder(withAsc), pageLimit)
	local sep = if string.find(noSort, "?", 1, true) then "&" else "?"
	local explicitAsc = sanitizeMemberUsersUrl(noSort .. sep .. "sortOrder=Asc", pageLimit)
	local limit100Asc = sanitizeMemberUsersUrl(noSort, 100)

	local variants: { string } = {}
	local seen: { [string]: boolean } = {}
	local function push(u: string)
		if u ~= "" and not seen[u] then
			seen[u] = true
			table.insert(variants, u)
		end
	end
	push(withAsc)
	push(noSort)
	push(explicitAsc)
	push(limit100Asc)
	return variants
end

local function truncateForLog(text: string, maxLen: number): string
	if #text <= maxLen then
		return text
	end
	return string.sub(text, 1, maxLen) .. "…"
end

local function bodyForLog(body: any): string
	if type(body) ~= "string" or body == "" then
		return "(empty)"
	end
	return truncateForLog(body, 220)
end

local function formatUrlTemplate(template: string, groupId: number): string?
	if template == "" then
		return nil
	end
	local url = template
	if string.find(url, "{groupId}", 1, true) then
		url = (string.gsub(url, "{groupId}", tostring(groupId)))
	elseif string.find(url, "%", 1, true) then
		local okFormat, formatted = pcall(function()
			return string.format(template, groupId)
		end)
		if okFormat and type(formatted) == "string" and formatted ~= "" then
			url = formatted
		end
	end
	if isBlockedRobloxHost(url) then
		return nil
	end
	return url
end

-- Derive .../v1/groups/{id}/roles from a users or group-info URL when possible.
local function buildGroupRolesUrl(groupId: number, usersOrInfoUrl: string?): string
	local fallback = string.format("https://groups.roproxy.com/v1/groups/%d/roles", groupId)
	if type(usersOrInfoUrl) ~= "string" or usersOrInfoUrl == "" then
		return fallback
	end
	local formatted = formatUrlTemplate(usersOrInfoUrl, groupId)
	if type(formatted) ~= "string" or formatted == "" then
		return fallback
	end
	local rolesUrl = (string.gsub(formatted, "/users%?.*$", "/roles"))
	rolesUrl = (string.gsub(rolesUrl, "/users$", "/roles"))
	if string.find(rolesUrl, "/roles", 1, true) and not string.find(rolesUrl, "/users", 1, true) then
		return rolesUrl
	end
	-- Group info URL: .../v1/groups/123 → append /roles
	local trimmed = (string.gsub(formatted, "/$", ""))
	if string.match(trimmed, "/v%d+/groups/%d+$") then
		return trimmed .. "/roles"
	end
	return fallback
end

local function buildRoleUsersUrl(rolesUrl: string, roleSetId: number, pageLimit: number): string
	local base = (string.gsub(rolesUrl, "/roles/?$", ""))
	local limit = nearestUsersPageLimit(pageLimit)
	return string.format("%s/roles/%d/users?limit=%d&sortOrder=Asc", base, roleSetId, limit)
end

local function pickBestRoleSetId(rolesDecoded: any): number?
	if type(rolesDecoded) ~= "table" then
		return nil
	end
	local roles = (rolesDecoded :: any).roles
	if type(roles) ~= "table" then
		return nil
	end
	local bestId: number? = nil
	local bestCount = -1
	local baseId: number? = nil
	for _, role in ipairs(roles) do
		if type(role) == "table" then
			local rank = tonumber((role :: any).rank) or -1
			local roleId = tonumber((role :: any).id) or 0
			local memberCount = tonumber((role :: any).memberCount) or 0
			if roleId > 0 and rank > 0 then
				if (role :: any).isBase == true then
					baseId = roleId
				end
				if memberCount > bestCount then
					bestCount = memberCount
					bestId = roleId
				end
			end
		end
	end
	return baseId or bestId
end

local function parseUserRowsFromProxy(decoded: any): { MemberSample }
	local samples: { MemberSample } = {}
	if type(decoded) ~= "table" then
		return samples
	end

	local function pushUser(userId: number, displayName: any)
		if userId <= 0 then
			return
		end
		local name = displayName
		if type(name) ~= "string" or name == "" then
			name = "User " .. tostring(userId)
		end
		table.insert(samples, {
			userId = userId,
			displayName = name,
		})
	end

	-- Flat members[] from custom workers / MEMBER_INFO_URL extras.
	local membersRaw = (decoded :: any).members
	if type(membersRaw) == "table" then
		for _, row in ipairs(membersRaw) do
			if type(row) == "table" then
				local userId = tonumber((row :: any).userId) or 0
				local displayName = (row :: any).displayName
				if type(displayName) ~= "string" or displayName == "" then
					displayName = (row :: any).username
				end
				pushUser(userId, displayName)
			end
		end
	end

	-- Official groups.v1 users page shape: { data: [ { user: { userId, displayName, username } } ] }
	local dataRaw = (decoded :: any).data
	if type(dataRaw) == "table" then
		for _, row in ipairs(dataRaw) do
			if type(row) == "table" then
				local user = (row :: any).user
				if type(user) == "table" then
					local userId = tonumber((user :: any).userId) or 0
					local displayName = (user :: any).displayName
					if type(displayName) ~= "string" or displayName == "" then
						displayName = (user :: any).username
					end
					pushUser(userId, displayName)
				else
					local userId = tonumber((row :: any).userId) or 0
					local displayName = (row :: any).displayName
					if type(displayName) ~= "string" or displayName == "" then
						displayName = (row :: any).username
					end
					pushUser(userId, displayName)
				end
			end
		end
	end

	return samples
end

local function createJoinCommunityMembersService(deps: {
	remotes: Folder,
	logger: any?,
}): Service
	local log = deps.logger or Logger.new("JoinCommunityMembersService")
	local remotes = deps.remotes
	local cfg = getCfg()

	local requestName = tostring(cfg.REMOTE_REQUEST or "JoinCommunityMembersRequest")
	local responseName = tostring(cfg.REMOTE_RESPONSE or "JoinCommunityMembersResponse")
	local requestRemote = ensureRemoteEvent(remotes, requestName)
	local responseRemote = ensureRemoteEvent(remotes, responseName)

	local sampleLimit = math.clamp(tonumber(cfg.SAMPLE_LIMIT) or 8, 1, 8)
	local poolCap = math.clamp(tonumber(cfg.POOL_SIZE) or 40, sampleLimit, 100)
	local memberCountTtl = math.max(60, tonumber(cfg.CACHE_TTL) or 300)
	local failCacheTtl = math.max(15, tonumber(cfg.MEMBER_COUNT_FAIL_TTL) or 45)
	local memoryStoreEnabled = cfg.MEMORY_STORE_ENABLED ~= false
	local memoryStoreTtl = math.max(30, tonumber(cfg.MEMORY_STORE_TTL) or 86400)
	local memoryStoreName = tostring(
		cfg.MEMORY_STORE_NAME
			or ((tostring(KitProduct.MemoryStorePrefix or "HazastudioClubKit")) .. "JoinCommunityPool")
	)
	local memberInfoUrlTemplate = ""
	if type(cfg.MEMBER_INFO_URL) == "string" then
		memberInfoUrlTemplate = cfg.MEMBER_INFO_URL
	elseif type(cfg.MEMBER_COUNT_URL) == "string" then
		-- Alias kept for older drafts.
		memberInfoUrlTemplate = cfg.MEMBER_COUNT_URL
	end
	local memberUsersUrlTemplate = ""
	if type(cfg.MEMBER_USERS_URL) == "string" then
		memberUsersUrlTemplate = cfg.MEMBER_USERS_URL
	end
	local limiter = RateLimiter.new(
		tonumber(cfg.REQUEST_RATE_MAX) or 4,
		tonumber(cfg.REQUEST_RATE_WINDOW) or 30
	)

	-- In-experience pool: members seen online in this place who are in GroupId (bonus thumbs only).
	local poolByUserId: { [number]: MemberSample } = {}
	local poolOrder: { number } = {}
	local memberCountCache: { expiresAt: number, value: number, known: boolean }? = nil
	local emblemCache: { expiresAt: number, value: string? }? = nil
	local usersPageCache: { expiresAt: number, samples: { MemberSample } }? = nil
	-- Unified game-data-api /community cache (count + members + emblem in one response).
	local communityWorkerCache: {
		expiresAt: number,
		memberCount: number?,
		memberCountKnown: boolean,
		emblemUrl: string?,
		samples: { MemberSample },
		ok: boolean,
	}? = nil
	local memoryStore: any? = nil
	local memoryStoreDirty = false
	local memoryStoreWriteScheduled = false
	local connections: { RBXScriptConnection } = {}
	local destroyed = false
	local warnedGetGroupInfoFail = false
	local loggedMemberCountMissing = false
	local warnedProxyFail = false
	local loggedProxy429 = false
	local warnedUsersProxyFail = false
	local warnedCommunityWorkerFail = false
	local loggedCommunityWorkerSkip = false
	-- Skip MEMBER_INFO_URL briefly after HTTP 429 (or any hard fail) to avoid spam.
	local memberInfoBackoffUntil = 0

	local function track(conn: RBXScriptConnection): RBXScriptConnection
		table.insert(connections, conn)
		return conn
	end

	local function getConfiguredGroupId(): number
		local groupId = Config.Group.GROUP_ID
		if type(groupId) == "number" and groupId > 0 then
			return groupId
		end
		return 0
	end

	local function poolAsArray(): { MemberSample }
		local out: { MemberSample } = table.create(#poolOrder)
		for _, userId in ipairs(poolOrder) do
			local sample = poolByUserId[userId]
			if sample then
				table.insert(out, sample)
			end
		end
		return out
	end

	local function upsertPoolMember(userId: number, displayName: string)
		if userId <= 0 then
			return
		end
		local name = displayName
		if type(name) ~= "string" or name == "" then
			name = "User " .. tostring(userId)
		end

		local existing = poolByUserId[userId]
		if existing then
			if existing.displayName ~= name then
				existing.displayName = name
				memoryStoreDirty = true
			end
			return
		end

		poolByUserId[userId] = {
			userId = userId,
			displayName = name,
		}
		table.insert(poolOrder, userId)
		memoryStoreDirty = true

		while #poolOrder > poolCap do
			local evicted = table.remove(poolOrder, 1)
			if evicted then
				poolByUserId[evicted] = nil
			end
		end
	end

	local function mergeSamplesIntoPool(samples: { MemberSample })
		for _, sample in ipairs(samples) do
			if type(sample) == "table" then
				local userId = tonumber(sample.userId) or 0
				if userId > 0 then
					local displayName = sample.displayName
					if type(displayName) ~= "string" or displayName == "" then
						displayName = "User " .. tostring(userId)
					end
					upsertPoolMember(userId, displayName)
				end
			end
		end
	end

	local function buildMemberInfoUrl(groupId: number): string?
		local url = formatUrlTemplate(memberInfoUrlTemplate, groupId)
		if memberInfoUrlTemplate ~= "" and url == nil and isBlockedRobloxHost(memberInfoUrlTemplate) then
			if not warnedProxyFail then
				warnedProxyFail = true
				log:warn("JoinCommunityMembers MEMBER_INFO_URL points at roblox.com (blocked); use a non-roblox proxy/worker", {
					groupId = groupId,
				})
			end
		end
		return url
	end

	local function buildMemberUsersUrl(groupId: number): string?
		local url = formatUrlTemplate(memberUsersUrlTemplate, groupId)
		if memberUsersUrlTemplate ~= "" and url == nil and isBlockedRobloxHost(memberUsersUrlTemplate) then
			if not warnedUsersProxyFail then
				warnedUsersProxyFail = true
				log:warn("JoinCommunityMembers MEMBER_USERS_URL points at roblox.com (blocked); use a non-roblox proxy", {
					groupId = groupId,
				})
			end
		end
		if url == nil then
			return nil
		end
		-- Clamp limit= to Roblox-valid page size; force Asc. Do NOT use POOL_SIZE (40) as the API limit.
		return sanitizeMemberUsersUrl(url, DEFAULT_USERS_PAGE_LIMIT)
	end

	local function getGameDataApiConfig(): (string?, string?, string?, boolean)
		local apiCfg = Config.GameDataApi
		if type(apiCfg) ~= "table" then
			return nil, nil, nil, false
		end
		if apiCfg.COMMUNITY_ENDPOINT_ENABLED == false then
			return nil, nil, nil, false
		end
		local baseUrl = apiCfg.BASE_URL
		local gameKey = apiCfg.GAME_KEY
		if type(baseUrl) ~= "string" or baseUrl == "" or type(gameKey) ~= "string" or gameKey == "" then
			return nil, nil, nil, false
		end
		local secret = Secrets.GameDataApiSecret
		if type(secret) ~= "string" or secret == "" then
			if not loggedCommunityWorkerSkip then
				loggedCommunityWorkerSkip = true
				log:debug(
					"JoinCommunityMembers GameDataApiSecret kosong — community worker di-skip (normal di Studio); fallback roproxy",
					{ gameKey = gameKey }
				)
			end
			return nil, nil, nil, false
		end
		return baseUrl, gameKey, secret, true
	end

	-- Prefer game-data-api /community (one Http → count + members + emblem). Cached CACHE_TTL.
	local function resolveCommunityWorker(groupId: number): {
		ok: boolean,
		memberCount: number?,
		memberCountKnown: boolean,
		emblemUrl: string?,
		samples: { MemberSample },
	}
		local now = os.clock()
		if communityWorkerCache and communityWorkerCache.expiresAt > now then
			return {
				ok = communityWorkerCache.ok,
				memberCount = communityWorkerCache.memberCount,
				memberCountKnown = communityWorkerCache.memberCountKnown,
				emblemUrl = communityWorkerCache.emblemUrl,
				samples = communityWorkerCache.samples,
			}
		end

		local baseUrl, gameKey, secret, enabled = getGameDataApiConfig()
		if not enabled or type(baseUrl) ~= "string" or type(gameKey) ~= "string" or type(secret) ~= "string" then
			communityWorkerCache = {
				expiresAt = now + failCacheTtl,
				memberCount = nil,
				memberCountKnown = false,
				emblemUrl = nil,
				samples = {},
				ok = false,
			}
			return {
				ok = false,
				memberCount = nil,
				memberCountKnown = false,
				emblemUrl = nil,
				samples = {},
			}
		end

		local url = string.format(
			"%s/game/%s/community/%d?secret=%s",
			baseUrl,
			gameKey,
			groupId,
			secret
		)
		local timeout = 5
		if type(Config.GameDataApi) == "table" and type(Config.GameDataApi.HTTP_TIMEOUT) == "number" then
			timeout = Config.GameDataApi.HTTP_TIMEOUT
		end

		local okHttp, responseOrErr = pcall(function()
			return HttpService:RequestAsync({
				Url = url,
				Method = "GET",
				Headers = { Accept = "application/json" },
				Timeout = timeout,
			})
		end)
		if not okHttp or type(responseOrErr) ~= "table" or responseOrErr.Success ~= true then
			if not warnedCommunityWorkerFail then
				warnedCommunityWorkerFail = true
				local statusCode = if type(responseOrErr) == "table" then tonumber(responseOrErr.StatusCode) else nil
				log:warn("JoinCommunityMembers game-data community request failed", {
					groupId = groupId,
					gameKey = gameKey,
					statusCode = statusCode or 0,
					err = if okHttp then "HTTP fail" else tostring(responseOrErr),
				})
			end
			communityWorkerCache = {
				expiresAt = now + failCacheTtl,
				memberCount = nil,
				memberCountKnown = false,
				emblemUrl = nil,
				samples = {},
				ok = false,
			}
			return {
				ok = false,
				memberCount = nil,
				memberCountKnown = false,
				emblemUrl = nil,
				samples = {},
			}
		end

		local body = if type(responseOrErr.Body) == "string" then responseOrErr.Body else ""
		local okJson, decoded = pcall(function()
			return HttpService:JSONDecode(body)
		end)
		if not okJson or type(decoded) ~= "table" or (decoded :: any).ok ~= true then
			if not warnedCommunityWorkerFail then
				warnedCommunityWorkerFail = true
				log:warn("JoinCommunityMembers game-data community returned invalid payload", {
					groupId = groupId,
					gameKey = gameKey,
					body = bodyForLog(body),
				})
			end
			communityWorkerCache = {
				expiresAt = now + failCacheTtl,
				memberCount = nil,
				memberCountKnown = false,
				emblemUrl = nil,
				samples = {},
				ok = false,
			}
			return {
				ok = false,
				memberCount = nil,
				memberCountKnown = false,
				emblemUrl = nil,
				samples = {},
			}
		end

		local count = extractMemberCount(decoded)
		local emblem = extractEmblemUrl(decoded)
		local samples = parseUserRowsFromProxy(decoded)
		if #samples > 0 then
			mergeSamplesIntoPool(samples)
		end

		-- Also warm dedicated caches so emblem/count resolvers stay consistent.
		if count ~= nil then
			memberCountCache = {
				expiresAt = now + memberCountTtl,
				value = count,
				known = true,
			}
		end
		if type(emblem) == "string" and emblem ~= "" then
			emblemCache = {
				expiresAt = now + memberCountTtl,
				value = emblem,
			}
		end
		if #samples > 0 then
			usersPageCache = {
				expiresAt = now + memberCountTtl,
				samples = samples,
			}
		end

		communityWorkerCache = {
			expiresAt = now + memberCountTtl,
			memberCount = count,
			memberCountKnown = count ~= nil,
			emblemUrl = emblem,
			samples = samples,
			ok = true,
		}

		log:debug("JoinCommunityMembers game-data community ok", {
			groupId = groupId,
			gameKey = gameKey,
			memberCount = count,
			members = #samples,
			fromCache = (decoded :: any).fromCache == true,
		})

		return {
			ok = true,
			memberCount = count,
			memberCountKnown = count ~= nil,
			emblemUrl = emblem,
			samples = samples,
		}
	end

	local function isHttp429(err: string): boolean
		return string.find(err, "429", 1, true) ~= nil
	end

	local function tryFetchMemberInfoProxy(groupId: number): (number?, { MemberSample }?, string?)
		local now = os.clock()
		if now < memberInfoBackoffUntil then
			return nil, nil, nil
		end
		local url = buildMemberInfoUrl(groupId)
		if url == nil then
			return nil, nil, nil
		end
		local okHttp, bodyOrErr = pcall(function()
			return HttpService:GetAsync(url)
		end)
		if not okHttp then
			local errStr = tostring(bodyOrErr)
			memberInfoBackoffUntil = now + failCacheTtl
			if isHttp429(errStr) then
				if not loggedProxy429 then
					loggedProxy429 = true
					log:debug("JoinCommunityMembers MEMBER_INFO_URL rate limited (429)", {
						groupId = groupId,
						url = url,
						err = errStr,
						backoffSec = failCacheTtl,
					})
				end
			elseif not warnedProxyFail then
				warnedProxyFail = true
				log:warn("JoinCommunityMembers MEMBER_INFO_URL request failed", {
					groupId = groupId,
					url = url,
					err = errStr,
				})
			end
			return nil, nil, nil
		end
		local okJson, decoded = pcall(function()
			return HttpService:JSONDecode(bodyOrErr :: string)
		end)
		if not okJson or type(decoded) ~= "table" then
			memberInfoBackoffUntil = now + failCacheTtl
			if not warnedProxyFail then
				warnedProxyFail = true
				log:warn("JoinCommunityMembers MEMBER_INFO_URL returned invalid JSON", {
					groupId = groupId,
					url = url,
				})
			end
			return nil, nil, nil
		end

		local count = extractMemberCount(decoded)
		local emblem = extractEmblemUrl(decoded)
		local samples = parseUserRowsFromProxy(decoded)
		return count, if #samples > 0 then samples else nil, emblem
	end

	-- GET JSON via RequestAsync. User-Agent is locked by Roblox HttpService (cannot set).
	local function httpGetJson(url: string): (boolean, number?, string, any?)
		local okHttp, responseOrErr = pcall(function()
			return HttpService:RequestAsync({
				Url = url,
				Method = "GET",
				Headers = {
					Accept = "application/json",
				},
			})
		end)
		if not okHttp then
			return false, nil, tostring(responseOrErr), nil
		end
		local response = responseOrErr
		if type(response) ~= "table" then
			return false, nil, "invalid response", nil
		end
		local statusCode = tonumber(response.StatusCode)
		local body = if type(response.Body) == "string" then response.Body else ""
		if response.Success ~= true then
			return false, statusCode, body, nil
		end
		local okJson, decoded = pcall(function()
			return HttpService:JSONDecode(body)
		end)
		if not okJson or type(decoded) ~= "table" then
			return false, statusCode, body, nil
		end
		return true, statusCode, body, decoded
	end

	local function logUsersFetchFail(groupId: number, url: string, statusCode: number?, bodyOrErr: string, attempt: string)
		if warnedUsersProxyFail then
			return
		end
		warnedUsersProxyFail = true
		log:warn("JoinCommunityMembers MEMBER_USERS_URL request failed", {
			groupId = groupId,
			url = url,
			err = if statusCode then ("HTTP " .. tostring(statusCode)) else truncateForLog(bodyOrErr, 120),
			statusCode = statusCode or 0,
			body = bodyForLog(bodyOrErr),
			pageLimit = nearestUsersPageLimit(DEFAULT_USERS_PAGE_LIMIT),
			attempt = attempt,
			kitVersion = tostring(KitProduct.KitVersion),
		})
	end

	-- Fallback: roles list → base/largest role → /roles/{roleSetId}/users (flat user rows).
	local function tryFetchRoleUsersPage(groupId: number, seedUrl: string?): { MemberSample }?
		local seed = seedUrl
		if type(seed) ~= "string" or seed == "" then
			if memberInfoUrlTemplate ~= "" then
				seed = memberInfoUrlTemplate
			elseif memberUsersUrlTemplate ~= "" then
				seed = memberUsersUrlTemplate
			end
		end
		local rolesUrl = buildGroupRolesUrl(groupId, seed)
		if isBlockedRobloxHost(rolesUrl) then
			return nil
		end
		local okRoles, _statusRoles, _bodyRoles, decodedRoles = httpGetJson(rolesUrl)
		if not okRoles or type(decodedRoles) ~= "table" then
			return nil
		end
		local roleSetId = pickBestRoleSetId(decodedRoles)
		if roleSetId == nil then
			return nil
		end
		local roleUsersUrl = buildRoleUsersUrl(rolesUrl, roleSetId, DEFAULT_USERS_PAGE_LIMIT)
		local okUsers, _statusUsers, _bodyUsers, decodedUsers = httpGetJson(roleUsersUrl)
		if not okUsers or type(decodedUsers) ~= "table" then
			return nil
		end
		local samples = parseUserRowsFromProxy(decodedUsers)
		if #samples == 0 then
			return nil
		end
		return samples
	end

	-- One page of group members via roproxy (or buyer MEMBER_USERS_URL). Cached CACHE_TTL.
	-- Retries Asc / no-sort / limit=100, then roles/{id}/users for huge groups when /users 400s.
	local function tryFetchGroupUsersPage(groupId: number): { MemberSample }?
		local primary = buildMemberUsersUrl(groupId)
		if primary == nil then
			return nil
		end

		local variants = buildUsersUrlVariants(primary, DEFAULT_USERS_PAGE_LIMIT)
		local lastUrl = primary
		local lastStatus: number? = nil
		local lastBody = ""

		for _, url in ipairs(variants) do
			lastUrl = url
			local ok, statusCode, body, decoded = httpGetJson(url)
			lastStatus = statusCode
			lastBody = body
			if ok and type(decoded) == "table" then
				local samples = parseUserRowsFromProxy(decoded)
				if #samples > 0 then
					return samples
				end
			end
		end

		local roleSamples = tryFetchRoleUsersPage(groupId, primary)
		if roleSamples and #roleSamples > 0 then
			return roleSamples
		end

		logUsersFetchFail(groupId, lastUrl, lastStatus, lastBody, "users+roles-exhausted")
		return nil
	end

	local function resolveRemoteUsersPage(groupId: number): { MemberSample }
		local now = os.clock()
		if usersPageCache and usersPageCache.expiresAt > now then
			return usersPageCache.samples
		end

		-- 1) game-data-api /community (members[] — no separate users fetch).
		-- On worker success, never call MEMBER_USERS_URL in the same resolve
		-- (even if members[] is empty — secondary fill uses in-experience pool).
		local worker = resolveCommunityWorker(groupId)
		if worker.ok then
			usersPageCache = {
				expiresAt = now + (if #worker.samples > 0 then memberCountTtl else failCacheTtl),
				samples = worker.samples,
			}
			return worker.samples
		end

		-- 2) MEMBER_USERS_URL / roproxy only when worker skipped or failed
		local fetched = tryFetchGroupUsersPage(groupId)
		if fetched then
			usersPageCache = {
				expiresAt = now + memberCountTtl,
				samples = fetched,
			}
			mergeSamplesIntoPool(fetched)
			return fetched
		end

		-- Short negative cache so we do not hammer a dead proxy every request.
		usersPageCache = {
			expiresAt = now + failCacheTtl,
			samples = {},
		}
		return {}
	end

	local function pickMembersForPayload(groupId: number, excludeUserId: number?): { MemberSample }
		local remoteRoster = resolveRemoteUsersPage(groupId)
		local fromRemote = pickRandomSamples(remoteRoster, sampleLimit, excludeUserId)
		if #fromRemote >= sampleLimit then
			return fromRemote
		end

		-- Secondary fill: in-experience / MemoryStore pool.
		local seen: { [number]: boolean } = {}
		for _, sample in ipairs(fromRemote) do
			seen[sample.userId] = true
		end
		local need = sampleLimit - #fromRemote
		local poolFill = pickRandomSamples(poolAsArray(), need + 4, excludeUserId)
		for _, sample in ipairs(poolFill) do
			if #fromRemote >= sampleLimit then
				break
			end
			if not seen[sample.userId] then
				seen[sample.userId] = true
				table.insert(fromRemote, sample)
			end
		end
		return fromRemote
	end

	local function resolveEmblemUrl(groupId: number): string?
		local now = os.clock()
		if emblemCache and emblemCache.expiresAt > now then
			return emblemCache.value
		end

		-- 1) Engine GroupService EmblemUrl (or GroupIcon thumb when info succeeded but field omitted).
		local okInfo, infoOrErr = pcall(function()
			return GroupService:GetGroupInfoAsync(groupId)
		end)
		if okInfo and type(infoOrErr) == "table" then
			local emblem = extractEmblemUrl(infoOrErr) or groupIconThumbUrl(groupId)
			emblemCache = {
				expiresAt = now + memberCountTtl,
				value = emblem,
			}
			return emblem
		end

		-- 2) Prefer game-data community emblem (single worker call).
		-- On worker success, do not call MEMBER_INFO_URL for emblem.
		local worker = resolveCommunityWorker(groupId)
		if type(worker.emblemUrl) == "string" and worker.emblemUrl ~= "" then
			emblemCache = {
				expiresAt = now + memberCountTtl,
				value = worker.emblemUrl,
			}
			return worker.emblemUrl
		end
		if worker.ok then
			emblemCache = {
				expiresAt = now + failCacheTtl,
				value = nil,
			}
			return nil
		end

		-- 3) MEMBER_INFO_URL / roproxy only when worker skipped or failed
		local _proxyCount, proxySamples, proxyEmblem = tryFetchMemberInfoProxy(groupId)
		if proxySamples then
			mergeSamplesIntoPool(proxySamples)
		end
		if type(proxyEmblem) == "string" and proxyEmblem ~= "" then
			emblemCache = {
				expiresAt = now + memberCountTtl,
				value = proxyEmblem,
			}
			return proxyEmblem
		end

		emblemCache = {
			expiresAt = now + failCacheTtl,
			value = nil,
		}
		return nil
	end

	local function resolveMemberCount(groupId: number): (number, boolean)
		local now = os.clock()
		if memberCountCache and memberCountCache.expiresAt > now then
			return memberCountCache.value, memberCountCache.known
		end

		-- 1) Engine GroupService — real total IF MemberCount is present (often absent per docs).
		local okInfo, infoOrErr = pcall(function()
			return GroupService:GetGroupInfoAsync(groupId)
		end)
		if not okInfo then
			if not warnedGetGroupInfoFail then
				warnedGetGroupInfoFail = true
				log:warn("JoinCommunityMembers GetGroupInfoAsync failed", {
					groupId = groupId,
					err = tostring(infoOrErr),
				})
			end
		else
			-- Warm emblem cache from the same successful group info call.
			if not (emblemCache and emblemCache.expiresAt > now and type(emblemCache.value) == "string") then
				local emblem = extractEmblemUrl(infoOrErr) or groupIconThumbUrl(groupId)
				emblemCache = {
					expiresAt = now + memberCountTtl,
					value = emblem,
				}
			end
			local count = extractMemberCount(infoOrErr)
			if count ~= nil then
				memberCountCache = {
					expiresAt = now + memberCountTtl,
					value = count,
					known = true,
				}
				return count, true
			end
			-- Expected: engine docs omit MemberCount — not a buyer misconfig.
			if not loggedMemberCountMissing then
				loggedMemberCountMissing = true
				log:debug(
					"JoinCommunityMembers GetGroupInfoAsync has no MemberCount (engine often omits it); falling back to game-data community (roproxy only if worker skipped/failed)",
					{
						groupId = groupId,
						memberInfoUrl = memberInfoUrlTemplate ~= "",
					}
				)
			end
		end

		-- 2) game-data-api /community (preferred over roproxy when secret is set).
		-- On worker success, never call MEMBER_INFO_URL — even if count is missing
		-- (members/emblem from the same response are enough for the modal).
		local worker = resolveCommunityWorker(groupId)
		if worker.ok then
			if worker.memberCountKnown and worker.memberCount ~= nil then
				return worker.memberCount, true
			end
			memberCountCache = {
				expiresAt = now + failCacheTtl,
				value = 0,
				known = false,
			}
			return 0, false
		end

		-- 3) MEMBER_INFO_URL / roproxy only when worker skipped or failed
		local proxyCount, proxySamples, proxyEmblem = tryFetchMemberInfoProxy(groupId)
		if proxySamples then
			mergeSamplesIntoPool(proxySamples)
		end
		if type(proxyEmblem) == "string" and proxyEmblem ~= "" then
			if not (emblemCache and emblemCache.expiresAt > now and type(emblemCache.value) == "string") then
				emblemCache = {
					expiresAt = now + memberCountTtl,
					value = proxyEmblem,
				}
			end
		end
		if proxyCount ~= nil then
			memberCountCache = {
				expiresAt = now + memberCountTtl,
				value = proxyCount,
				known = true,
			}
			return proxyCount, true
		end

		-- Unknown — short negative cache. Never treat pool/online size as the community total.
		memberCountCache = {
			expiresAt = now + failCacheTtl,
			value = 0,
			known = false,
		}
		return 0, false
	end

	local function tryGetMemoryStore(): any?
		if not memoryStoreEnabled then
			return nil
		end
		if memoryStore ~= nil then
			return memoryStore
		end
		local ok, store = pcall(function()
			return MemoryStoreService:GetHashMap(memoryStoreName)
		end)
		if ok and store ~= nil then
			memoryStore = store
			return store
		end
		return nil
	end

	local function memoryStoreKey(groupId: number): string
		return "g" .. tostring(groupId)
	end

	local function loadPoolFromMemoryStore(groupId: number)
		local store = tryGetMemoryStore()
		if store == nil then
			return
		end
		local ok, value = pcall(function()
			return store:GetAsync(memoryStoreKey(groupId))
		end)
		if not ok or type(value) ~= "table" then
			return
		end
		local samples: { MemberSample } = {}
		for _, row in ipairs(value) do
			if type(row) == "table" then
				local userId = tonumber((row :: any).userId) or 0
				if userId > 0 then
					local displayName = (row :: any).displayName
					if type(displayName) ~= "string" or displayName == "" then
						displayName = "User " .. tostring(userId)
					end
					table.insert(samples, {
						userId = userId,
						displayName = displayName,
					})
				end
			end
		end
		if #samples > 0 then
			mergeSamplesIntoPool(samples)
			memoryStoreDirty = false
			log:info("JoinCommunityMembers MemoryStore pool loaded", {
				groupId = groupId,
				loaded = #samples,
				poolSize = #poolOrder,
			})
		end
	end

	local function flushPoolToMemoryStore(groupId: number)
		if not memoryStoreDirty or destroyed then
			return
		end
		local store = tryGetMemoryStore()
		if store == nil then
			return
		end
		local snapshot = poolAsArray()
		local ok = pcall(function()
			store:SetAsync(memoryStoreKey(groupId), snapshot, memoryStoreTtl)
		end)
		if ok then
			memoryStoreDirty = false
			log:debug("JoinCommunityMembers MemoryStore pool saved", {
				groupId = groupId,
				poolSize = #snapshot,
			})
		end
	end

	local function scheduleMemoryStoreWrite(groupId: number)
		if not memoryStoreEnabled or memoryStoreWriteScheduled or not memoryStoreDirty then
			return
		end
		memoryStoreWriteScheduled = true
		task.delay(15, function()
			memoryStoreWriteScheduled = false
			if destroyed then
				return
			end
			flushPoolToMemoryStore(groupId)
		end)
	end

	local function playerDisplayName(player: Player): string
		local displayName = player.DisplayName
		if type(displayName) == "string" and displayName ~= "" then
			return displayName
		end
		return player.Name
	end

	local function isPlayerInGroupAsync(player: Player, groupId: number): boolean
		local okAsync, inGroup = pcall(function()
			return player:IsInGroupAsync(groupId)
		end)
		if okAsync and type(inGroup) == "boolean" then
			return inGroup
		end
		local okSync, inGroupSync = pcall(function()
			return player:IsInGroup(groupId)
		end)
		return okSync and inGroupSync == true
	end

	local function considerPlayer(player: Player, groupId: number)
		if destroyed or groupId <= 0 then
			return
		end
		if not isPlayerInGroupAsync(player, groupId) then
			return
		end
		upsertPoolMember(player.UserId, playerDisplayName(player))
		scheduleMemoryStoreWrite(groupId)
	end

	local function seedFromOnlinePlayers(groupId: number)
		for _, player in ipairs(Players:GetPlayers()) do
			considerPlayer(player, groupId)
		end
	end

	local function buildPayload(groupId: number, excludeUserId: number?): MembersPayload
		local memberCount, known = resolveMemberCount(groupId)
		local emblemUrl = resolveEmblemUrl(groupId)
		return {
			groupId = groupId,
			memberCount = memberCount,
			memberCountKnown = known,
			emblemUrl = emblemUrl,
			members = pickMembersForPayload(groupId, excludeUserId),
		}
	end

	local function emptyPayload(groupId: number): MembersPayload
		return {
			groupId = groupId,
			memberCount = 0,
			memberCountKnown = false,
			emblemUrl = nil,
			members = {},
		}
	end

	local function payloadFromPool(groupId: number, excludeUserId: number): MembersPayload
		local memberCount = 0
		local known = false
		if memberCountCache then
			memberCount = memberCountCache.value
			known = memberCountCache.known
		end
		local emblemUrl: string? = nil
		if emblemCache and type(emblemCache.value) == "string" and emblemCache.value ~= "" then
			emblemUrl = emblemCache.value
		end
		return {
			groupId = groupId,
			memberCount = memberCount,
			memberCountKnown = known,
			emblemUrl = emblemUrl,
			members = pickRandomSamples(poolAsArray(), sampleLimit, excludeUserId),
		}
	end

	track(requestRemote.OnServerEvent:Connect(function(player: Player, raw: any)
		local groupId = 0
		if type(raw) == "number" then
			groupId = raw
		elseif type(raw) == "table" then
			groupId = tonumber((raw :: any).groupId) or 0
		end

		local configured = getConfiguredGroupId()
		if configured <= 0 then
			responseRemote:FireClient(player, emptyPayload(groupId))
			return
		end
		if groupId ~= configured then
			groupId = configured
		end

		task.spawn(function()
			considerPlayer(player, groupId)
		end)

		local allowed = limiter:check(player.UserId)
		if not allowed then
			responseRemote:FireClient(player, payloadFromPool(groupId, player.UserId))
			return
		end

		local ok, payload = pcall(function()
			return buildPayload(groupId, player.UserId)
		end)
		if not ok or type(payload) ~= "table" then
			log:warn("JoinCommunityMembers build failed", {
				player = player.Name,
				groupId = groupId,
				err = tostring(payload),
			})
			responseRemote:FireClient(player, payloadFromPool(groupId, player.UserId))
			return
		end
		responseRemote:FireClient(player, payload)
	end))

	track(Players.PlayerAdded:Connect(function(player: Player)
		local groupId = getConfiguredGroupId()
		if groupId <= 0 then
			return
		end
		task.delay(2, function()
			if destroyed or not player.Parent then
				return
			end
			considerPlayer(player, groupId)
		end)
	end))

	task.delay(8, function()
		if destroyed then
			return
		end
		local groupId = getConfiguredGroupId()
		if groupId <= 0 then
			return
		end
		pcall(function()
			loadPoolFromMemoryStore(groupId)
		end)
		seedFromOnlinePlayers(groupId)
		local remoteUsers = 0
		pcall(function()
			remoteUsers = #resolveRemoteUsersPage(groupId)
		end)
		local memberCount, known = 0, false
		pcall(function()
			memberCount, known = resolveMemberCount(groupId)
		end)
		log:info("JoinCommunityMembers pool warmed", {
			groupId = groupId,
			poolSize = #poolOrder,
			remoteUsers = remoteUsers,
			memberCount = memberCount,
			memberCountKnown = known,
		})
	end)

	local service = {}

	function service:destroy()
		destroyed = true
		local groupId = getConfiguredGroupId()
		if groupId > 0 and memoryStoreDirty then
			flushPoolToMemoryStore(groupId)
		end
		for _, conn in ipairs(connections) do
			conn:Disconnect()
		end
		table.clear(connections)
		table.clear(poolByUserId)
		table.clear(poolOrder)
		memberCountCache = nil
		emblemCache = nil
		usersPageCache = nil
		communityWorkerCache = nil
		limiter:destroy()
	end

	local _, _, _, communityWorkerEnabled = getGameDataApiConfig()
	log:info("JoinCommunityMembersService ready", {
		request = requestName,
		response = responseName,
		poolCap = poolCap,
		memberCountTtl = memberCountTtl,
		memoryStore = memoryStoreEnabled,
		memberInfoUrl = memberInfoUrlTemplate ~= "",
		memberUsersUrl = memberUsersUrlTemplate ~= "",
		gameDataCommunity = communityWorkerEnabled,
	})

	return service
end

return createJoinCommunityMembersService
