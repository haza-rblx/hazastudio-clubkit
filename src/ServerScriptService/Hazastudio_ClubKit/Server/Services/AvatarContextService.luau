--!strict
-- ServerScriptService/Server/Services/AvatarContextService.lua
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
type Result<T> = Types.Result<T>
type AvatarContextPayload = Types.AvatarContextPayload
type ProfileRelationshipMode = Types.ProfileRelationshipMode
type ILogger = Types.ILogger
type IOverheadService = Types.IOverheadService

local function getRelationshipMode(rawMode: any, isCoupled: boolean): ProfileRelationshipMode
	if rawMode == "Fun" then
		return "Fun"
	end
	if rawMode == "Taken" and isCoupled then
		return "Taken"
	end
	if rawMode == "Single" then
		return "Single"
	end
	return if isCoupled then "Taken" else "Single"
end

local function buildRelationshipText(
	mode: ProfileRelationshipMode,
	isCoupled: boolean,
	showCoupleName: boolean,
	couplePartner: string?
): string
	if mode == "Fun" then
		return "Status : Fun"
	end
	if mode == "Taken" and isCoupled then
		if showCoupleName and type(couplePartner) == "string" and couplePartner ~= "" then
			return "Status : Taken by " .. couplePartner
		end
		return "Status : Taken"
	end
	return "Status : Single"
end

local function canSendFriendRequest(viewerPlayer: Player, targetPlayer: Player, log: ILogger): boolean
	if viewerPlayer.UserId == targetPlayer.UserId then
		return false
	end

	local ok, isFriend = pcall(function()
		return viewerPlayer:IsFriendsWith(targetPlayer.UserId)
	end)
	if not ok then
		log:warn("AvatarContextService friend status lookup failed", {
			viewerUserId = viewerPlayer.UserId,
			targetUserId = targetPlayer.UserId,
			error = tostring(isFriend),
		})
		return false
	end

	return isFriend ~= true
end

local function createAvatarContextService(deps: {
	logger: ILogger,
	overheadService: IOverheadService,
	profileSocialService: any,
	profileRepository: any,
	profileCommandService: any,
	avatarLikeRepository: any?,
	playerSnapshotService: any?,
})
	local log = deps.logger
	local overheadService = deps.overheadService
	local profileSocialService = deps.profileSocialService
	local profileRepository = deps.profileRepository
	local profileCommandService = deps.profileCommandService
	local avatarLikeRepository = deps.avatarLikeRepository
	local playerSnapshotService = deps.playerSnapshotService
	local service = {}

	-- Per (target, viewer) payload cache.
	-- Mengurangi spam DataStore + GroupService + GetFriendsAsync saat player
	-- buka/tutup avatar context yang sama berulang (sumber rate-limit hit).
	local PAYLOAD_CACHE_TTL = 15 -- detik
	local payloadCache: { [string]: { value: any, exp: number } } = {}
	local function makeKey(targetUserId: number, viewerUserId: number): string
		return tostring(targetUserId) .. ":" .. tostring(viewerUserId)
	end
	local function invalidateForTarget(targetUserId: number)
		local prefix = tostring(targetUserId) .. ":"
		for key in pairs(payloadCache) do
			if string.sub(key, 1, #prefix) == prefix then
				payloadCache[key] = nil
			end
		end
	end
	local function invalidateForViewer(viewerUserId: number)
		local suffix = ":" .. tostring(viewerUserId)
		local slen = #suffix
		for key in pairs(payloadCache) do
			if #key >= slen and string.sub(key, -slen) == suffix then
				payloadCache[key] = nil
			end
		end
	end
	function service:invalidateForTarget(targetUserId: number)
		invalidateForTarget(targetUserId)
	end
	function service:invalidateForViewer(viewerUserId: number)
		invalidateForViewer(viewerUserId)
	end
	function service:buildPayload(targetPlayer: Player, viewerPlayer: Player): Result<AvatarContextPayload>
		local startTime = os.clock()

		-- Cache check: payload (target, viewer) yang masih fresh dipakai ulang.
		local cacheKey = makeKey(targetPlayer.UserId, viewerPlayer.UserId)
		local cached = payloadCache[cacheKey]
		if cached and os.clock() <= cached.exp then
			local elapsedMs = math.floor((os.clock() - startTime) * 1000)
			log:debug("ACM_OPEN_MS cache hit", { elapsedMs = elapsedMs, targetUserId = targetPlayer.UserId })
			return Result.Ok(cached.value)
		end

		-- ============================================================
		-- FAST PATH: Use PlayerSnapshotService if available
		-- Only fetch viewer-specific data (viewerHasLiked) at request time
		-- ============================================================
		-- Guard: snapshot hanya valid untuk fast path kalau sudah di-populate
		-- dari overhead (punya visibleBadges). Kalau snapshot dibuat duluan
		-- oleh updateFromSocial/updateLikesCount sebelum broadcastPayload
		-- pertama, visibleBadges masih nil → badge membership tidak muncul.
		local rawSnapshot = if playerSnapshotService and type(playerSnapshotService.getSnapshot) == "function"
			then playerSnapshotService:getSnapshot(targetPlayer.UserId)
			else nil
		local snapshot = if rawSnapshot and rawSnapshot.visibleBadges then rawSnapshot else nil

		local timingBreakdown: { [string]: number } = {}
		local results: { [string]: any } = {}
		local pending = 0
		local barrier = Instance.new("BindableEvent")

		local function spawnFetch(key: string, fn: () -> any)
			pending += 1
			task.spawn(function()
				local fetchStart = os.clock()
				local ok, val = pcall(fn)
				timingBreakdown[key] = math.floor((os.clock() - fetchStart) * 1000)
				if ok then
					results[key] = val
				else
					log:warn("AvatarContextService parallel fetch error", { key = key, err = tostring(val) })
					results[key] = nil
				end
				pending -= 1
				if pending == 0 then
					barrier:Fire()
				end
			end)
		end

		-- Snapshot is in-memory and cleaned up on PlayerRemoving.
		-- No TTL needed — it's always as fresh as the last EventBus update.
		local useSnapshot = snapshot ~= nil

		if useSnapshot then
			-- Fast path: only viewer-specific + lightweight profile bio.
			-- Social proof is NOT fetched on the hot path — GetFriendsAsync pagination
			-- can take 10s+ and was causing ACM timeouts. Use snapshot/cache only.
			spawnFetch("likeState", function()
				if avatarLikeRepository and type(avatarLikeRepository.getViewerState) == "function" then
					return avatarLikeRepository:getViewerState(targetPlayer.UserId, viewerPlayer.UserId)
				end
				return nil
			end)
			spawnFetch("profile", function()
				return profileRepository:load(targetPlayer.UserId)
			end)
		else
			-- Slow path: full parallel fetch
			spawnFetch("overhead", function()
				return overheadService:buildPayload(targetPlayer)
			end)
			spawnFetch("profile", function()
				return profileRepository:load(targetPlayer.UserId)
			end)
			spawnFetch("social", function()
				return profileSocialService:fetch(targetPlayer.UserId)
			end)
			spawnFetch("likeState", function()
				if avatarLikeRepository and type(avatarLikeRepository.getViewerState) == "function" then
					return avatarLikeRepository:getViewerState(targetPlayer.UserId, viewerPlayer.UserId)
				end
				return nil
			end)
		end

		if pending > 0 then
			local buildDeadline = os.clock() + (Config.AvatarContext.BUILD_DEADLINE or 5)
			while pending > 0 and os.clock() < buildDeadline do
				task.wait(0.05)
			end
			if pending > 0 then
				log:warn("ACM build deadline exceeded; returning partial payload", {
					targetUserId = targetPlayer.UserId,
					pending = pending,
					usedSnapshot = useSnapshot,
				})
			end
		end
		barrier:Destroy()

		-- ============================================================
		-- ASSEMBLE: process results
		-- ============================================================
		local bio: string? = nil
		local statusText: string? = nil
		local relationshipMode: ProfileRelationshipMode
		local followersCount: number? = nil
		local connectionsCount: number? = nil
		local overhead: any = nil

		if useSnapshot and snapshot then
			-- Fast path: build from snapshot
			overhead = {
				displayName = snapshot.displayName or targetPlayer.DisplayName,
				role = snapshot.role or "Guest",
				effectiveMembership = snapshot.effectiveMembership or "Guest",
				visibleBadges = snapshot.visibleBadges or {},
				streakDays = snapshot.streakDays or 0,
				couplePartner = snapshot.couplePartner,
				isCoupled = snapshot.isCoupled or false,
				showCoupleName = snapshot.showCoupleName or false,
				communityId = snapshot.communityId,
				communityName = snapshot.communityName,
				communityLogo = snapshot.communityLogo,
				likesCount = snapshot.likesCount or 0,
			}
			relationshipMode = getRelationshipMode(snapshot.relationshipMode, overhead.isCoupled)
			followersCount = snapshot.followersCount
			connectionsCount = snapshot.connectionsCount
			if connectionsCount == nil and profileSocialService and type(profileSocialService.getCached) == "function" then
				local cachedSocial = profileSocialService:getCached(targetPlayer.UserId)
				if cachedSocial and cachedSocial.connectionsCount ~= nil then
					connectionsCount = cachedSocial.connectionsCount
					followersCount = cachedSocial.followersCount
				end
			end
			statusText = snapshot.statusText

			local profileResult = results["profile"]
			if profileResult and profileResult.ok then
				local profile = profileResult.value
				if profile.bio then
					bio = service:_filterText(profile.bio, viewerPlayer.UserId)
				end
				relationshipMode = getRelationshipMode(profile.relationshipMode, overhead.isCoupled)
			end
		else
			-- Slow path: process parallel fetch results
			local overheadResult = results["overhead"]
			if not overheadResult or not overheadResult.ok then
				local elapsedMs = math.floor((os.clock() - startTime) * 1000)
				log:warn("ACM_OPEN_MS failed", { elapsedMs = elapsedMs, error = "overhead_failed" })
				return Result.Err("Failed to get overhead data")
			end
			overhead = overheadResult.value

			local profileResult = results["profile"]
			if profileResult and profileResult.ok then
				local profile = profileResult.value
				if profile.bio then
					bio = service:_filterText(profile.bio, viewerPlayer.UserId)
				end
				relationshipMode = getRelationshipMode(profile.relationshipMode, overhead.isCoupled)
			else
				relationshipMode = getRelationshipMode(nil, overhead.isCoupled)
			end

			local socialResult = results["social"]
			if socialResult and socialResult.ok then
				followersCount = socialResult.value.followersCount
				connectionsCount = socialResult.value.connectionsCount

				-- Push social data into snapshot so fast path hits have it too
				if playerSnapshotService and type(playerSnapshotService.updateFromSocial) == "function" then
					playerSnapshotService:updateFromSocial(targetPlayer.UserId, socialResult.value)
				end
			end
		end

		-- Session status (in-memory, always check)
		if profileCommandService and type(profileCommandService.getStatus) == "function" then
			local sessionStatus = profileCommandService:getStatus(targetPlayer.UserId)
			if sessionStatus then
				statusText = service:_filterText(sessionStatus, viewerPlayer.UserId)
			end
		end

		-- Like state (always fetch for viewer-specific data)
		local likesCount = overhead.likesCount
		local viewerHasLiked = false
		local likeStateResult = results["likeState"]
		if likeStateResult then
			if likeStateResult.ok then
				viewerHasLiked = likeStateResult.value == 1
			else
				log:warn("AvatarContextService like state lookup failed", {
					targetUserId = targetPlayer.UserId,
					viewerUserId = viewerPlayer.UserId,
					error = likeStateResult.error,
				})
			end
		end

		-- Build payload
		local payload: AvatarContextPayload = {
			userId = targetPlayer.UserId,
			displayName = overhead.displayName,
			username = targetPlayer.Name,
			role = overhead.role,
			effectiveMembership = overhead.effectiveMembership,
			visibleBadges = overhead.visibleBadges,
			streakDays = overhead.streakDays,
			couplePartner = overhead.couplePartner,
			communityId = overhead.communityId,
			communityName = overhead.communityName,
			communityLogo = overhead.communityLogo,
			relationshipText = buildRelationshipText(
				relationshipMode,
				overhead.isCoupled,
				overhead.showCoupleName,
				overhead.couplePartner
			),
			bio = bio,
			statusText = statusText,
			followersCount = followersCount,
			connectionsCount = connectionsCount,
			likesCount = likesCount,
			viewerHasLiked = viewerHasLiked,
			canSendGift = true,
			canSendFriendRequest = true,
			canInvestigateAvatar = true,
			canLike = true,
			canCarry = true,
			canSyncDance = true,
		}
		-- Jangan cache payload dengan visibleBadges kosong untuk non-Guest players.
		-- Ini bisa terjadi karena race condition dimana snapshot belum ter-populate
		-- saat pertama kali build. Cache payload incomplete akan serve data salah
		-- selama 15 detik (TTL). Better re-fetch daripada serve badge kosong.
		local shouldCache = true
		if #payload.visibleBadges == 0 and payload.role ~= "Guest" then
			log:debug("ACM payload has empty visibleBadges for non-Guest; skipping cache", {
				targetUserId = targetPlayer.UserId,
				role = payload.role,
			})
			shouldCache = false
		end
		if shouldCache then
			payloadCache[cacheKey] = { value = payload, exp = os.clock() + PAYLOAD_CACHE_TTL }
		end

		-- Log timing instrumentation
		local elapsedMs = math.floor((os.clock() - startTime) * 1000)
		log:info("ACM_OPEN_MS", {
			elapsedMs = elapsedMs,
			targetUserId = targetPlayer.UserId,
			usedSnapshot = useSnapshot,
			breakdown = timingBreakdown,
		})

		return Result.Ok(payload)
	end
	-- Kedua pcall melindungi dari network error di TextService
	function service:_filterText(text: string, viewerUserId: number): string?
		local ok, result = pcall(function()
			return TextService:FilterStringAsync(text, viewerUserId)
		end)
		if not ok or not result then
			log:warn("Text filtering failed", { text = text })
			return nil
		end
		-- GetNonChatStringForUserAsync juga bisa throw saat network error
		local filterOk, filtered = pcall(function()
			return result:GetNonChatStringForUserAsync(viewerUserId)
		end)
		if not filterOk then
			log:warn("GetNonChatStringForUserAsync failed", { userId = viewerUserId })
			return nil
		end
		return filtered
	end
	return service
end
return createAvatarContextService
