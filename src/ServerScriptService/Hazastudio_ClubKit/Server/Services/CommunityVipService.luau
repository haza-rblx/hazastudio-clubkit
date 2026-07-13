--!strict
-- When FeatureFlags.VipOnCommunityJoinEnabled and player is in Config.Group.GROUP_ID,
-- grant Tier1 (VIP) via the same membershipBadge path as ShopService purchases.
-- Server-authoritative: join check + client recheck after PromptJoinAsync.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local ResultUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)

type Result<T> = Types.Result<T>
type IOverheadRepository = Types.IOverheadRepository

export type GrantOutcome = "granted" | "already" | "not_member" | "disabled" | "failed"

export type Service = {
	tryGrantForPlayer: (self: Service, player: Player) -> GrantOutcome,
	onPlayerReady: (self: Service, player: Player) -> (),
	destroy: (self: Service) -> (),
}

local VIP_TIER = "Tier1"
-- Roblox group membership often lags several seconds after PromptJoinAsync.
-- Keep polling long enough that a successful join still grants mid-session.
local MEMBERSHIP_PROPAGATION_RETRIES = 12
local MEMBERSHIP_PROPAGATION_DELAY = 2
-- Extra grant attempts after the immediate wait window (seconds).
local POST_JOIN_FOLLOWUP_DELAYS = { 10, 25, 45 }

local function createCommunityVipService(deps: {
	repo: IOverheadRepository,
	overheadController: any,
	overheadService: any?,
	remotes: Folder,
	logger: any?,
}): Service
	local repo = deps.repo
	local overheadController = deps.overheadController
	local overheadService = deps.overheadService
	local remotes = deps.remotes
	local log = deps.logger or Logger.new("CommunityVipService")

	local promptCfg = Config.JoinCommunityPrompt or {}
	local recheckRemoteName = tostring(promptCfg.REMOTE_VIP_RECHECK or "CommunityVipRecheck")
	local rateMax = tonumber(promptCfg.VIP_RECHECK_RATE_MAX) or 8
	local rateWindow = tonumber(promptCfg.VIP_RECHECK_RATE_WINDOW) or 60

	local limiter = RateLimiter.new(rateMax, rateWindow)
	local connections: { RBXScriptConnection } = {}
	local inFlight: { [number]: boolean } = {}
	local followUpsScheduled: { [number]: boolean } = {}
	local destroyed = false

	local function track(conn: RBXScriptConnection): RBXScriptConnection
		table.insert(connections, conn)
		return conn
	end

	local function ensureRemote(): RemoteEvent
		local existing = remotes:FindFirstChild(recheckRemoteName)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = recheckRemoteName
		remote.Parent = remotes
		return remote
	end

	local function isFeatureEnabled(): boolean
		return Config.FeatureFlags.VipOnCommunityJoinEnabled == true
	end

	local function getConfiguredGroupId(): number
		local group = Config.Group
		local id = if type(group) == "table" then tonumber(group.GROUP_ID) else nil
		if type(id) == "number" and id > 0 then
			return id
		end
		return 0
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

	local function waitUntilInGroup(player: Player, groupId: number): boolean
		if isPlayerInGroupAsync(player, groupId) then
			return true
		end
		-- Membership can lag briefly after PromptJoinAsync succeeds.
		for _ = 1, MEMBERSHIP_PROPAGATION_RETRIES do
			task.wait(MEMBERSHIP_PROPAGATION_DELAY)
			if destroyed or not player.Parent then
				return false
			end
			if isPlayerInGroupAsync(player, groupId) then
				return true
			end
		end
		return false
	end

	local function grantVipMembership(userId: number): Result<boolean>
		-- Same storage as ShopService.grantMembership (membershipBadge = Tier1 / VIP).
		local storedResult = repo:loadStrict(userId)
		if storedResult.ok and OverheadDomain.hasStoredMembershipAtLeast(storedResult.value, VIP_TIER) then
			return ResultUtil.Ok(false)
		end

		local already = false
		local updated = repo:update(userId, function(current)
			if OverheadDomain.hasStoredMembershipAtLeast(current, VIP_TIER) then
				already = true
				return current
			end
			return OverheadDomain.mergeStored(current, { membershipBadge = VIP_TIER })
		end)
		if not updated.ok then
			return ResultUtil.Err(updated.error)
		end
		return ResultUtil.Ok(not already)
	end

	local service = {} :: Service

	function service:tryGrantForPlayer(player: Player): GrantOutcome
		if destroyed or not player.Parent then
			return "failed"
		end
		if not isFeatureEnabled() then
			return "disabled"
		end
		local groupId = getConfiguredGroupId()
		if groupId <= 0 then
			return "disabled"
		end
		if not isPlayerInGroupAsync(player, groupId) then
			return "not_member"
		end

		local result = grantVipMembership(player.UserId)
		if not result.ok then
			log:warn("Community VIP grant failed", {
				userId = player.UserId,
				error = result.error,
			})
			return "failed"
		end
		if result.value == false then
			return "already"
		end

		-- Fresh group membership must not keep a stale groups:/rank cache, and
		-- mid-session VIP needs a full Snapshot so OverheadUI + chat tags update
		-- without requiring place rejoin.
		if overheadService and type(overheadService.invalidateGroupCache) == "function" then
			overheadService:invalidateGroupCache(player.UserId)
		end
		if overheadController and type(overheadController.refreshPlayer) == "function" then
			overheadController:refreshPlayer(player, "recovery")
		end
		log:info("Community VIP granted", {
			userId = player.UserId,
			groupId = groupId,
			tier = VIP_TIER,
		})
		return "granted"
	end

	function service:onPlayerReady(player: Player)
		if destroyed or not player.Parent then
			return
		end
		if not isFeatureEnabled() then
			return
		end
		task.spawn(function()
			self:tryGrantForPlayer(player)
		end)
	end

	local function handleRecheck(player: Player)
		if destroyed or not player.Parent then
			return
		end
		if not isFeatureEnabled() then
			return
		end
		local groupId = getConfiguredGroupId()
		if groupId <= 0 then
			return
		end

		local allowed = limiter:check(player.UserId)
		if not allowed then
			return
		end

		local userId = player.UserId
		if inFlight[userId] then
			return
		end
		inFlight[userId] = true
		task.spawn(function()
			local ok, err = pcall(function()
				if waitUntilInGroup(player, groupId) then
					local outcome = service:tryGrantForPlayer(player)
					if outcome == "granted" or outcome == "already" then
						followUpsScheduled[userId] = nil
					end
					return
				end
				-- Membership still lagging after the primary wait window — keep
				-- trying on a longer cadence so VIP still lands without rejoin.
				if followUpsScheduled[userId] then
					return
				end
				followUpsScheduled[userId] = true
				log:debug("Community VIP recheck: not in group yet, scheduling follow-ups", {
					userId = userId,
					groupId = groupId,
				})
				for _, delaySec in ipairs(POST_JOIN_FOLLOWUP_DELAYS) do
					task.delay(delaySec, function()
						if destroyed or not player.Parent then
							return
						end
						if inFlight[userId] then
							return
						end
						inFlight[userId] = true
						local followOk, followErr = pcall(function()
							local outcome = service:tryGrantForPlayer(player)
							if outcome == "granted" or outcome == "already" then
								followUpsScheduled[userId] = nil
							end
						end)
						inFlight[userId] = nil
						if not followOk then
							log:warn("Community VIP follow-up error", {
								userId = userId,
								error = tostring(followErr),
							})
						end
					end)
				end
			end)
			inFlight[userId] = nil
			if not ok then
				log:warn("Community VIP recheck error", {
					userId = userId,
					error = tostring(err),
				})
			end
		end)
	end

	local remote = ensureRemote()
	track(remote.OnServerEvent:Connect(function(player: Player)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return
		end
		handleRecheck(player)
	end))

	track(Players.PlayerRemoving:Connect(function(player: Player)
		inFlight[player.UserId] = nil
		followUpsScheduled[player.UserId] = nil
	end))

	log:info("CommunityVipService ready", {
		enabled = isFeatureEnabled(),
		groupId = getConfiguredGroupId(),
		remote = recheckRemoteName,
	})

	function service:destroy()
		destroyed = true
		for _, conn in ipairs(connections) do
			conn:Disconnect()
		end
		table.clear(connections)
		table.clear(inFlight)
		table.clear(followUpsScheduled)
		if type((limiter :: any).destroy) == "function" then
			(limiter :: any):destroy()
		end
	end

	return service
end

return createCommunityVipService
