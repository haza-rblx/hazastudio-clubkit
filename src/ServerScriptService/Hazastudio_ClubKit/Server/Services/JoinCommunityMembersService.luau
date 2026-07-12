--!strict
-- Server sample of group members for the Join Community modal (thumbnails + copy).
-- Client Http to groups.roblox.com is blocked; this owns the fetch + short TTL cache.

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
	local cacheTtl = math.max(30, tonumber(cfg.CACHE_TTL) or 120)
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
		local okInfo, info = pcall(function()
			return GroupService:GetGroupInfoAsync(groupId)
		end)
		if okInfo and type(info) == "table" then
			local count = (info :: any).MemberCount or (info :: any).memberCount
			if type(count) == "number" and count > 0 then
				return count
			end
		end

		local okHttp, body = pcall(function()
			return HttpService:GetAsync("https://groups.roblox.com/v1/groups/" .. tostring(groupId))
		end)
		if okHttp and type(body) == "string" and body ~= "" then
			local okJson, decoded = pcall(function()
				return HttpService:JSONDecode(body)
			end)
			if okJson and type(decoded) == "table" then
				local count = (decoded :: any).memberCount
				if type(count) == "number" and count > 0 then
					return count
				end
			end
		end

		return 0
	end

	local function fetchRosterFromApi(groupId: number, limit: number): { MemberSample }
		local url = string.format(
			"https://groups.roblox.com/v1/groups/%d/users?limit=100&sortOrder=Desc",
			groupId
		)
		local okHttp, body = pcall(function()
			return HttpService:GetAsync(url)
		end)
		if not okHttp or type(body) ~= "string" or body == "" then
			log:debug("JoinCommunityMembers roster HTTP failed", { groupId = groupId })
			return {}
		end

		local okJson, decoded = pcall(function()
			return HttpService:JSONDecode(body)
		end)
		if not okJson or type(decoded) ~= "table" then
			return {}
		end

		local data = (decoded :: any).data
		if type(data) ~= "table" then
			return {}
		end

		local out: { MemberSample } = {}
		for _, row in ipairs(data) do
			if #out >= limit then
				break
			end
			if type(row) == "table" then
				local user = (row :: any).user
				if type(user) == "table" then
					local userId = tonumber(user.userId) or 0
					if userId > 0 then
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

		local fetchLimit = math.max(sampleLimit * 3, 24)
		local members = fetchRosterFromApi(groupId, fetchLimit)
		local memberCount = resolveMemberCount(groupId)
		if memberCount <= 0 then
			memberCount = #members
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
		local members: { MemberSample } = {}
		for _, sample in ipairs(entry.members) do
			if #members >= sampleLimit then
				break
			end
			if excludeUserId == nil or sample.userId ~= excludeUserId then
				table.insert(members, {
					userId = sample.userId,
					displayName = sample.displayName,
				})
			end
		end
		return {
			groupId = groupId,
			memberCount = entry.memberCount,
			members = members,
		}
	end

	local function emptyPayload(groupId: number): MembersPayload
		return {
			groupId = groupId,
			memberCount = 0,
			members = {},
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
		-- Only allow the place's configured community id (ignore client spoof).
		if groupId ~= configured then
			groupId = configured
		end

		local allowed = limiter:check(player.UserId)
		if not allowed then
			local cached = cacheByGroup[groupId]
			if cached then
				local members: { MemberSample } = {}
				for _, sample in ipairs(cached.members) do
					if #members >= sampleLimit then
						break
					end
					if sample.userId ~= player.UserId then
						table.insert(members, {
							userId = sample.userId,
							displayName = sample.displayName,
						})
					end
				end
				responseRemote:FireClient(player, {
					groupId = groupId,
					memberCount = cached.memberCount,
					members = members,
				})
			else
				responseRemote:FireClient(player, emptyPayload(groupId))
			end
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
			responseRemote:FireClient(player, emptyPayload(groupId))
			return
		end
		responseRemote:FireClient(player, payload)
	end))

	-- Pre-warm once at boot so first modal open is fast (best-effort).
	task.defer(function()
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
	})

	return service
end

return createJoinCommunityMembersService
