--!strict
-- Server sample of group members for the Join Community modal (thumbnails + copy).
-- Pool = community members seen in this experience (no Http to *.roblox.com).
-- MemberCount via GroupService; O(k) random pick from in-memory (+ optional MemoryStore) pool.

local GroupService = game:GetService("GroupService")
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
	local memoryStoreEnabled = cfg.MEMORY_STORE_ENABLED ~= false
	local memoryStoreTtl = math.max(30, tonumber(cfg.MEMORY_STORE_TTL) or 86400)
	local memoryStoreName = tostring(
		cfg.MEMORY_STORE_NAME
			or ((tostring(KitProduct.MemoryStorePrefix or "HazastudioClubKit")) .. "JoinCommunityPool")
	)
	local limiter = RateLimiter.new(
		tonumber(cfg.REQUEST_RATE_MAX) or 4,
		tonumber(cfg.REQUEST_RATE_WINDOW) or 30
	)

	-- In-experience pool: members seen online in this place who are in GroupId.
	local poolByUserId: { [number]: MemberSample } = {}
	local poolOrder: { number } = {} -- FIFO for eviction when over cap
	local memberCountCache: { expiresAt: number, value: number }? = nil
	local memoryStore: any? = nil
	local memoryStoreDirty = false
	local memoryStoreWriteScheduled = false
	local connections: { RBXScriptConnection } = {}
	local destroyed = false

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

	local function resolveMemberCount(groupId: number): number
		local now = os.clock()
		if memberCountCache and memberCountCache.expiresAt > now then
			return memberCountCache.value
		end

		local okInfo, info = pcall(function()
			return GroupService:GetGroupInfoAsync(groupId)
		end)
		local count = 0
		if okInfo and type(info) == "table" then
			local raw = (info :: any).MemberCount or (info :: any).memberCount
			if type(raw) == "number" and raw > 0 then
				count = raw
			end
		end
		memberCountCache = {
			expiresAt = now + memberCountTtl,
			value = count,
		}
		return count
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
			-- Merged remote snapshot; avoid immediate rewrite storm.
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
		local memberCount = resolveMemberCount(groupId)
		local pool = poolAsArray()
		return {
			groupId = groupId,
			memberCount = memberCount,
			members = pickRandomSamples(pool, sampleLimit, excludeUserId),
		}
	end

	local function emptyPayload(groupId: number): MembersPayload
		return {
			groupId = groupId,
			memberCount = 0,
			members = {},
		}
	end

	local function payloadFromPool(groupId: number, excludeUserId: number): MembersPayload
		local memberCount = 0
		if memberCountCache then
			memberCount = memberCountCache.value
		end
		return {
			groupId = groupId,
			memberCount = memberCount,
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

		-- Opportunistic: requester may themselves be in-group (seed pool).
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
		-- Slight delay so group membership cache can settle on join.
		task.delay(2, function()
			if destroyed or not player.Parent then
				return
			end
			considerPlayer(player, groupId)
		end)
	end))

	-- Pre-warm: MemoryStore snapshot + currently online in-group (no Http).
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
		pcall(function()
			resolveMemberCount(groupId)
		end)
		log:info("JoinCommunityMembers pool warmed", {
			groupId = groupId,
			poolSize = #poolOrder,
			memberCount = if memberCountCache then memberCountCache.value else 0,
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
		limiter:destroy()
	end

	log:info("JoinCommunityMembersService ready", {
		request = requestName,
		response = responseName,
		poolCap = poolCap,
		memberCountTtl = memberCountTtl,
		memoryStore = memoryStoreEnabled,
	})

	return service
end

return createJoinCommunityMembersService
