--!strict
-- Server sample of group members for the Join Community modal (thumbnails + copy).
-- Efficient: 1 HTTP page max, GroupService for count, cached pool, O(k) random pick.

local GroupService = game:GetService("GroupService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)

export type MemberSample = {
	userId: number,
	displayName: string,
}

export type MembersPayload = {
	groupId: number,
	memberCount: number,
	members: { MemberSample },
}

export type Service = {
	destroy: (self: Service) -> (),
}

type CacheEntry = {
	expiresAt: number,
	memberCount: number,
	members: { MemberSample },
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
	-- One API page is 100 max; keep a modest pool for random picks (not multi-page crawl).
	local poolSize = math.clamp(tonumber(cfg.POOL_SIZE) or 40, sampleLimit, 100)
	local cacheTtl = math.max(60, tonumber(cfg.CACHE_TTL) or 300)
	local limiter = RateLimiter.new(
		tonumber(cfg.REQUEST_RATE_MAX) or 4,
		tonumber(cfg.REQUEST_RATE_WINDOW) or 30
	)

	local cacheByGroup: { [number]: CacheEntry } = {}
	local inFlight: { [number]: BindableEvent? } = {}
	local connections: { RBXScriptConnection } = {}

	local function track(conn: RBXScriptConnection): RBXScriptConnection
		table.insert(connections, conn)
		return conn
	end

	local function resolveMemberCount(groupId: number): number
		-- Prefer engine API (no Http budget).
		local okInfo, info = pcall(function()
			return GroupService:GetGroupInfoAsync(groupId)
		end)
		if okInfo and type(info) == "table" then
			local count = (info :: any).MemberCount or (info :: any).memberCount
			if type(count) == "number" and count > 0 then
				return count
			end
		end
		return 0
	end

	-- Single page only (limit<=100). Enough entropy for 8 random thumbs.
	local function fetchRosterPage(groupId: number, limit: number): { MemberSample }
		local url = string.format(
			"https://groups.roblox.com/v1/groups/%d/users?limit=%d&sortOrder=Desc",
			groupId,
			math.clamp(limit, 1, 100)
		)
		local okHttp, bodyOrErr = pcall(function()
			return HttpService:GetAsync(url)
		end)
		if not okHttp or type(bodyOrErr) ~= "string" or bodyOrErr == "" then
			log:warn("JoinCommunityMembers roster HTTP failed", {
				groupId = groupId,
				err = tostring(bodyOrErr),
				hint = "Enable HttpService.HttpEnabled",
			})
			return {}
		end

		local okJson, decoded = pcall(function()
			return HttpService:JSONDecode(bodyOrErr)
		end)
		if not okJson or type(decoded) ~= "table" then
			log:warn("JoinCommunityMembers roster JSON failed", { groupId = groupId })
			return {}
		end

		local data = (decoded :: any).data
		if type(data) ~= "table" then
			return {}
		end

		local out: { MemberSample } = {}
		local seen: { [number]: boolean } = {}
		for _, row in ipairs(data) do
			if #out >= limit then
				break
			end
			if type(row) == "table" then
				local user = (row :: any).user
				if type(user) == "table" then
					local userId = tonumber(user.userId) or 0
					if userId > 0 and not seen[userId] then
						seen[userId] = true
						local displayName = user.displayName
						if type(displayName) ~= "string" or displayName == "" then
							displayName = if type(user.username) == "string" and user.username ~= ""
								then user.username
								else ("User " .. tostring(userId))
						end
						table.insert(out, {
							userId = userId,
							displayName = displayName,
						})
					end
				end
			end
		end
		return out
	end

	local function loadCache(groupId: number): CacheEntry
		local now = os.clock()
		local cached = cacheByGroup[groupId]
		if cached and cached.expiresAt > now then
			return cached
		end

		local waitEvent = inFlight[groupId]
		if waitEvent then
			waitEvent.Event:Wait()
			local after = cacheByGroup[groupId]
			if after then
				return after
			end
		end

		local gate = Instance.new("BindableEvent")
		inFlight[groupId] = gate

		-- Parallel-ish: count via GroupService, roster via one Http get.
		local members: { MemberSample } = {}
		local memberCount = 0
		local rosterDone = false
		local countDone = false

		task.spawn(function()
			members = fetchRosterPage(groupId, poolSize)
			rosterDone = true
		end)
		task.spawn(function()
			memberCount = resolveMemberCount(groupId)
			countDone = true
		end)

		local deadline = os.clock() + 8
		while (not rosterDone or not countDone) and os.clock() < deadline do
			task.wait(0.05)
		end

		if memberCount <= 0 then
			memberCount = #members
		end

		if #members == 0 then
			log:warn("JoinCommunityMembers roster empty", {
				groupId = groupId,
				memberCount = memberCount,
			})
		else
			log:info("JoinCommunityMembers roster cached", {
				groupId = groupId,
				poolSize = #members,
				memberCount = memberCount,
			})
		end

		local entry: CacheEntry = {
			expiresAt = now + cacheTtl,
			memberCount = memberCount,
			members = members,
		}
		cacheByGroup[groupId] = entry
		inFlight[groupId] = nil
		gate:Fire()
		gate:Destroy()
		return entry
	end

	local function buildPayload(groupId: number, excludeUserId: number?): MembersPayload
		local entry = loadCache(groupId)
		return {
			groupId = groupId,
			memberCount = entry.memberCount,
			members = pickRandomSamples(entry.members, sampleLimit, excludeUserId),
		}
	end

	local function emptyPayload(groupId: number): MembersPayload
		return {
			groupId = groupId,
			memberCount = 0,
			members = {},
		}
	end

	local function payloadFromCache(groupId: number, excludeUserId: number): MembersPayload?
		local cached = cacheByGroup[groupId]
		if not cached then
			return nil
		end
		return {
			groupId = groupId,
			memberCount = cached.memberCount,
			members = pickRandomSamples(cached.members, sampleLimit, excludeUserId),
		}
	end

	track(requestRemote.OnServerEvent:Connect(function(player: Player, raw: any)
		local groupId = 0
		if type(raw) == "number" then
			groupId = raw
		elseif type(raw) == "table" then
			groupId = tonumber((raw :: any).groupId) or 0
		end

		local configured = Config.Group.GROUP_ID
		if type(configured) ~= "number" or configured <= 0 then
			responseRemote:FireClient(player, emptyPayload(groupId))
			return
		end
		if groupId ~= configured then
			groupId = configured
		end

		-- Serve cache immediately when rate-limited (still random sample).
		local allowed = limiter:check(player.UserId)
		if not allowed then
			local fromCache = payloadFromCache(groupId, player.UserId)
			responseRemote:FireClient(player, fromCache or emptyPayload(groupId))
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
			local fromCache = payloadFromCache(groupId, player.UserId)
			responseRemote:FireClient(player, fromCache or emptyPayload(groupId))
			return
		end
		responseRemote:FireClient(player, payload)
	end))

	-- Pre-warm after boot settles (avoid competing with join DataStore storm).
	task.delay(12, function()
		local groupId = Config.Group.GROUP_ID
		if type(groupId) == "number" and groupId > 0 then
			pcall(function()
				loadCache(groupId)
			end)
		end
	end)

	local service = {}

	function service:destroy()
		for _, conn in ipairs(connections) do
			conn:Disconnect()
		end
		table.clear(connections)
		table.clear(cacheByGroup)
		limiter:destroy()
	end

	log:info("JoinCommunityMembersService ready", {
		request = requestName,
		response = responseName,
		poolSize = poolSize,
		cacheTtl = cacheTtl,
	})

	return service
end

return createJoinCommunityMembersService
