--!strict
-- Server sample of group members for the Join Community modal (thumbnails + copy).
--
-- REAL TOTAL (memberCount):
--   Prefer GroupService:GetGroupInfoAsync → MemberCount when present.
--   Official engine docs do NOT list MemberCount on that table; when missing we
--   do not invent a total from online/pool size. Optional MEMBER_INFO_URL
--   (non-*.roblox.com worker) can supply the real count + optional samples.
--
-- AVATAR SAMPLES:
--   Primary: 1 page via MEMBER_USERS_URL (default groups.roproxy.com users API),
--   O(k) random pick, CACHE_TTL. In-experience / MemoryStore pool is secondary fill.
--   Http to groups.roblox.com is blocked from game servers.

local GroupService = game:GetService("GroupService")
local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local KitProduct = require(ReplicatedStorage.Hazastudio_ClubKit.KitProduct)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)

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
	local memoryStore: any? = nil
	local memoryStoreDirty = false
	local memoryStoreWriteScheduled = false
	local connections: { RBXScriptConnection } = {}
	local destroyed = false
	local warnedGetGroupInfoFail = false
	local loggedMemberCountMissing = false
	local warnedProxyFail = false
	local warnedUsersProxyFail = false

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
		return url
	end

	local function tryFetchMemberInfoProxy(groupId: number): (number?, { MemberSample }?, string?)
		local url = buildMemberInfoUrl(groupId)
		if url == nil then
			return nil, nil, nil
		end
		local okHttp, bodyOrErr = pcall(function()
			return HttpService:GetAsync(url)
		end)
		if not okHttp then
			if not warnedProxyFail then
				warnedProxyFail = true
				log:warn("JoinCommunityMembers MEMBER_INFO_URL request failed", {
					groupId = groupId,
					err = tostring(bodyOrErr),
				})
			end
			return nil, nil, nil
		end
		local okJson, decoded = pcall(function()
			return HttpService:JSONDecode(bodyOrErr :: string)
		end)
		if not okJson or type(decoded) ~= "table" then
			if not warnedProxyFail then
				warnedProxyFail = true
				log:warn("JoinCommunityMembers MEMBER_INFO_URL returned invalid JSON", {
					groupId = groupId,
				})
			end
			return nil, nil, nil
		end

		local count = extractMemberCount(decoded)
		local emblem = extractEmblemUrl(decoded)
		local samples = parseUserRowsFromProxy(decoded)
		return count, if #samples > 0 then samples else nil, emblem
	end

	-- One page of group members via roproxy (or buyer MEMBER_USERS_URL). Cached CACHE_TTL.
	local function tryFetchGroupUsersPage(groupId: number): { MemberSample }?
		local url = buildMemberUsersUrl(groupId)
		if url == nil then
			return nil
		end
		local okHttp, bodyOrErr = pcall(function()
			return HttpService:GetAsync(url)
		end)
		if not okHttp then
			if not warnedUsersProxyFail then
				warnedUsersProxyFail = true
				log:warn("JoinCommunityMembers MEMBER_USERS_URL request failed", {
					groupId = groupId,
					err = tostring(bodyOrErr),
				})
			end
			return nil
		end
		local okJson, decoded = pcall(function()
			return HttpService:JSONDecode(bodyOrErr :: string)
		end)
		if not okJson or type(decoded) ~= "table" then
			if not warnedUsersProxyFail then
				warnedUsersProxyFail = true
				log:warn("JoinCommunityMembers MEMBER_USERS_URL returned invalid JSON", {
					groupId = groupId,
				})
			end
			return nil
		end
		local samples = parseUserRowsFromProxy(decoded)
		if #samples == 0 then
			return nil
		end
		return samples
	end

	local function resolveRemoteUsersPage(groupId: number): { MemberSample }
		local now = os.clock()
		if usersPageCache and usersPageCache.expiresAt > now then
			return usersPageCache.samples
		end

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

		-- 2) Optional MEMBER_INFO_URL / roproxy JSON emblem fields (same proxy as MemberCount).
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
					"JoinCommunityMembers GetGroupInfoAsync has no MemberCount (engine often omits it); falling back to MEMBER_INFO_URL",
					{
						groupId = groupId,
						memberInfoUrl = memberInfoUrlTemplate ~= "",
					}
				)
			end
		end

		-- 2) Optional buyer proxy (non-*.roblox.com) for real MemberCount + optional samples/emblem.
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
		limiter:destroy()
	end

	log:info("JoinCommunityMembersService ready", {
		request = requestName,
		response = responseName,
		poolCap = poolCap,
		memberCountTtl = memberCountTtl,
		memoryStore = memoryStoreEnabled,
		memberInfoUrl = memberInfoUrlTemplate ~= "",
		memberUsersUrl = memberUsersUrlTemplate ~= "",
	})

	return service
end

return createJoinCommunityMembersService
