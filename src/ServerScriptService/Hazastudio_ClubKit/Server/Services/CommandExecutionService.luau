--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)

type Result<T> = Types.Result<T>
type MembershipTier = Types.MembershipTier
type RoleKey = Types.RoleKey

local function createCommandExecutionService(deps: {
	profileCommandService: any,
	communityCommandService: any,
	membershipCommandService: any,
	giftService: any,
	playerLookupService: any,
	overheadController: any,
	sessionCommandService: any,
	overheadService: any,
	notify: any,
	avatarContextController: any?,
	genericBroadcastService: any?,
	grantNetwork: any?,
})
	local profileCommandService = deps.profileCommandService
	local communityCommandService = deps.communityCommandService
	local membershipCommandService = deps.membershipCommandService
	local giftService = deps.giftService
	local playerLookupService = deps.playerLookupService
	local overheadController = deps.overheadController
	local sessionCommandService = deps.sessionCommandService
	local overheadService = deps.overheadService
	local notify = deps.notify
	local avatarContextController = deps.avatarContextController
	local genericBroadcastService = deps.genericBroadcastService
	local grantNetwork = deps.grantNetwork
	local log = Logger.new("CommandExecutionService")
	local giftLimiter = RateLimiter.new(Config.Gift.RATE_MAX, Config.Gift.RATE_WINDOW)
	local communityLimiter = RateLimiter.new(Config.Community.RATE_MAX, Config.Community.RATE_WINDOW)
	local announceLimiter = RateLimiter.new(Config.Announcement.RATE_MAX, Config.Announcement.RATE_WINDOW)

	local service = {}
	local rawHandlers: { [string]: (Player, string) -> () } = {}

	local function trim(text: string): string
		return text:match("^%s*(.-)%s*$") or ""
	end

	local function shortenForNotification(text: string, maxLen: number): string
		local normalized = trim(text)
		if #normalized <= maxLen then
			return normalized
		end
		return normalized:sub(1, maxLen - 3) .. "..."
	end

	local function buildProfileUpdateNotification(kind: "bio" | "status", value: string): { [string]: any }
		local preview = shortenForNotification(value, 90)
		if kind == "bio" then
			return {
				message = "[Profile] Bio updated.",
				notifType = "SUCCESS",
				domain = "profile",
				title = "Bio is live",
				description = string.format('Your profile now opens with "%s".', preview),
			}
		end

		return {
			message = "[Profile] Status updated.",
			notifType = "SUCCESS",
			domain = "profile",
			title = "Status set",
			description = string.format('You are showing "%s" for now.', preview),
		}
	end

	local function buildProfileClearedNotification(kind: "bio" | "status"): { [string]: any }
		if kind == "bio" then
			return {
				message = "[Profile] Bio cleared.",
				notifType = "SUCCESS",
				domain = "profile",
				title = "Bio cleared",
				description = "Fresh slate. Your bio is empty now.",
			}
		end

		return {
			message = "[Profile] Status cleared.",
			notifType = "SUCCESS",
			domain = "profile",
			title = "Status cleared",
			description = "No status showing right now.",
		}
	end

	local function resolveGiftTierAlias(tierAlias: string): MembershipTier?
		local tierKey = Config.Gift.TIER_ALIASES[string.lower(tierAlias)]
		if type(tierKey) ~= "string" then
			tierKey = tierAlias
		end

		local normalizedTier = OverheadDomain.normalizeMembershipTier(tierKey)
		if normalizedTier and OverheadDomain.isPaidMembershipTier(normalizedTier) then
			return normalizedTier
		end
		return nil
	end

	-- Removed normalize() wrapper, use trim() directly

	local function splitCommandText(commandText: string): (string?, string)
		local trimmed = trim(commandText)
		if trimmed == "" then
			return nil, ""
		end

		if string.sub(trimmed, 1, 1) ~= "/" then
			return nil, ""
		end

		local alias, args = trimmed:match("^/(%S+)%s*(.*)$")
		if not alias then
			return nil, ""
		end
		return string.lower(alias), args or ""
	end

	local function resolveTargetOrNotify(player: Player, query: string, notFoundMessage: string, queryShortMessage: string, ambiguousMessage: string): Player?
		local resolveResult = playerLookupService:resolveDetailed(query)
		if not resolveResult.ok then
			notify.player(player, resolveResult.error, "ERROR")
			return nil
		end

		local payload = resolveResult.value
		if payload.kind == "found" then
			return payload.player
		end

		if payload.kind == "too_short" then
			notify.player(player, queryShortMessage, "WARNING")
			return nil
		end

		if payload.kind == "ambiguous" then
			notify.player(
				player,
				ambiguousMessage:format(query, playerLookupService:describePlayers(payload.matches or {})),
				"WARNING"
			)
			return nil
		end

		notify.player(player, notFoundMessage:format(query), "ERROR")
		return nil
	end

	local function executeSetBio(player: Player, args: string): Result<nil>
		local bio = trim(args)
		if bio == "" then
			notify.player(player, "[Profile] Add a little text after /" .. Config.AvatarContext.CMD_SET_BIO .. ".", "ERROR")
			return Result.Err("missing bio")
		end

		local result = profileCommandService:setBio(player.UserId, bio)
		if result.ok then
			if avatarContextController and type(avatarContextController.pushProfileUpdate) == "function" then
				avatarContextController:pushProfileUpdate(player.UserId)
			end
			notify.player(player, buildProfileUpdateNotification("bio", bio))
			return Result.Ok(nil)
		end
		notify.player(player, result.error, "ERROR")
		return Result.Err(result.error)
	end

	local function executeClearBio(player: Player): Result<nil>
		local result = profileCommandService:clearBio(player.UserId)
		if result.ok then
			if avatarContextController and type(avatarContextController.pushProfileUpdate) == "function" then
				avatarContextController:pushProfileUpdate(player.UserId)
			end
			notify.player(player, buildProfileClearedNotification("bio"))
			return Result.Ok(nil)
		end
		notify.player(player, result.error, "ERROR")
		return Result.Err(result.error)
	end

	local function executeStatus(player: Player, args: string): Result<nil>
		local statusText = trim(args)
		if statusText == "" then
			notify.player(player, "[Profile] Add a status after /" .. Config.AvatarContext.CMD_SET_STATUS .. ".", "ERROR")
			return Result.Err("missing status")
		end

		local result = profileCommandService:setStatus(player.UserId, statusText)
		if result.ok then
			if avatarContextController and type(avatarContextController.pushProfileUpdate) == "function" then
				avatarContextController:pushProfileUpdate(player.UserId)
			end
			notify.player(player, buildProfileUpdateNotification("status", statusText))
			return Result.Ok(nil)
		end
		notify.player(player, result.error, "ERROR")
		return Result.Err(result.error)
	end

	local function executeClearStatus(player: Player): Result<nil>
		local result = profileCommandService:clearStatus(player.UserId)
		if result.ok then
			if avatarContextController and type(avatarContextController.pushProfileUpdate) == "function" then
				avatarContextController:pushProfileUpdate(player.UserId)
			end
			notify.player(player, buildProfileClearedNotification("status"))
			return Result.Ok(nil)
		end
		notify.player(player, result.error, "ERROR")
		return Result.Err(result.error)
	end

	local function fireGrantNetwork(target: Player, tier: string, fromName: string)
		if grantNetwork then
			grantNetwork:fireClient(target, {
				tier = tier,
				isGift = true,
				fromName = fromName,
			})
		end
	end

	local function executeSetCommunity(player: Player, args: string): Result<nil>
		if not communityLimiter:check(player.UserId) then
			notify.player(player, Config.Community.MSG_RATE_LIMIT, "WARNING")
			return Result.Err("rate_limited")
		end

		local input = trim(args)
		if input == "" then
			notify.player(player, Config.Community.MSG_USAGE, "WARNING")
			return Result.Err("missing community input")
		end

		local resolveResult = communityCommandService:resolveInput(player, input)
		if not resolveResult.ok then
			local notifType = resolveResult.error == Config.Community.MSG_NOT_MEMBER and "WARNING" or "ERROR"
			notify.player(player, resolveResult.error, notifType)
			return Result.Err(resolveResult.error)
		end

		local resolved = resolveResult.value
		if resolved.status == "not_found" then
			notify.player(player, Config.Community.MSG_NOT_FOUND:format(resolved.query), "WARNING")
			return Result.Err("community not found")
		end

		if resolved.status == "ambiguous" then
			local candidates = {}
			for index, candidate in ipairs(resolved.candidates) do
				if index > 3 then
					break
				end
				table.insert(candidates, candidate.name or tostring(candidate.id))
			end
			notify.player(
				player,
				Config.Community.MSG_AMBIGUOUS:format(resolved.query, table.concat(candidates, ", ")),
				"WARNING"
			)
			return Result.Err("community ambiguous")
		end

		local result = communityCommandService:setCommunity(player, resolved.community.id)
		if not result.ok then
			local notifType = result.error == Config.Community.MSG_NOT_MEMBER and "WARNING" or "ERROR"
			notify.player(player, result.error, notifType)
			return Result.Err(result.error)
		end

		overheadController:refreshPlayer(player)
		notify.player(player, Config.Community.MSG_SET_SUCCESS:format(result.value.communityName or tostring(result.value.communityId)), "SUCCESS")
		return Result.Ok(nil)
	end

	local function executeClearCommunity(player: Player): Result<nil>
		if not communityLimiter:check(player.UserId) then
			notify.player(player, Config.Community.MSG_RATE_LIMIT, "WARNING")
			return Result.Err("rate_limited")
		end

		local result = communityCommandService:clearCommunity(player)
		if not result.ok then
			local notifType = result.error == Config.Community.MSG_CLEAR_NONE and "WARNING" or "ERROR"
			notify.player(player, result.error, notifType)
			return Result.Err(result.error)
		end

		overheadController:refreshPlayer(player)
		notify.player(player, Config.Community.MSG_CLEAR_SUCCESS, "SUCCESS")
		return Result.Ok(nil)
	end

	local function executeGiftAll(player: Player, tierAlias: string): Result<nil>
		if not giftLimiter:check(player.UserId) then
			notify.player(player, Config.Gift.MSG_RATE_LIMIT, "WARNING")
			return Result.Err("rate_limited")
		end

		local tierKey = resolveGiftTierAlias(tierAlias)
		if not tierKey then
			notify.player(player, Config.Gift.MSG_INVALID:format(tierAlias), "ERROR")
			return Result.Err("invalid tier")
		end

		local result = membershipCommandService:grantMembershipToAll(player, tierKey)
		if not result.ok then
			notify.player(player, result.error, "ERROR")
			return Result.Err(result.error)
		end

		local summary = result.value
		local grantedCount = #summary.granted
		local skippedCount = #summary.skipped
		local failedCount = #summary.failed

		if grantedCount == 0 and skippedCount == 0 and failedCount == 0 then
			notify.player(player, Config.Gift.MSG_ALL_NO_TARGETS, "WARNING")
			return Result.Ok(nil)
		end

		local tierLabel = Config.MembershipChatLabel[summary.tier] or summary.tier
		for _, outcome in ipairs(summary.granted) do
			local target = outcome.player
			overheadController:refreshPlayer(target)
			fireGrantNetwork(target, outcome.giftTier, player.DisplayName)
			notify.player(
				target,
				Config.Gift.MSG_TARGET_GOT_GIFT:format(
					Config.MembershipChatLabel[outcome.giftTier] or outcome.giftTier,
					player.Name,
					Config.MembershipChatLabel[outcome.effectiveMembership] or outcome.effectiveMembership
				),
				"SUCCESS"
			)
		end

		if grantedCount > 0 then
			notify.player(
				player,
				Config.Gift.MSG_ALL_SUMMARY:format(tierLabel, grantedCount, skippedCount, failedCount),
				"SUCCESS"
			)
		else
			notify.player(
				player,
				Config.Gift.MSG_ALL_NO_GRANTS:format(tierLabel, skippedCount, failedCount),
				"WARNING"
			)
		end

		return Result.Ok(nil)
	end

	local function executeGift(player: Player, args: string): Result<nil>
		local targetQuery, tierAlias = args:match("^(.+)%s+(%S+)$")
		if not targetQuery or not tierAlias then
			notify.player(player, "[Gift] Try /gift <player> <tier>.", "WARNING")
			return Result.Err("invalid gift usage")
		end

		local allAlias = Config.Gift.ALL_TARGET_ALIAS
		if type(allAlias) == "string" and allAlias ~= "" and string.lower(trim(targetQuery)) == string.lower(allAlias) then
			return executeGiftAll(player, tierAlias)
		end

		if not giftLimiter:check(player.UserId) then
			notify.player(player, Config.Gift.MSG_RATE_LIMIT, "WARNING")
			return Result.Err("rate_limited")
		end

		local tierKey = resolveGiftTierAlias(tierAlias)
		if not tierKey then
			notify.player(player, Config.Gift.MSG_INVALID:format(tierAlias), "ERROR")
			return Result.Err("invalid tier")
		end

		local target = resolveTargetOrNotify(player, targetQuery, Config.Gift.MSG_NOT_FOUND, Config.Gift.MSG_QUERY_SHORT, Config.Gift.MSG_AMBIGUOUS)
		if not target then
			return Result.Err("target not found")
		end

		local result = membershipCommandService:grantMembership(player, target, tierKey)
		if not result.ok then
			notify.player(player, result.error, "ERROR")
			return Result.Err(result.error)
		end

		overheadController:refreshPlayer(target)
		fireGrantNetwork(target, result.value.giftTier, player.DisplayName)
		notify.player(
			player,
			Config.Gift.MSG_SUCCESS:format(
				Config.MembershipChatLabel[result.value.giftTier] or result.value.giftTier,
				target.DisplayName,
				Config.MembershipChatLabel[result.value.effectiveMembership] or result.value.effectiveMembership
			),
			"SUCCESS"
		)
		notify.player(
			target,
			Config.Gift.MSG_TARGET_GOT_GIFT:format(
				Config.MembershipChatLabel[result.value.giftTier] or result.value.giftTier,
				player.Name,
				Config.MembershipChatLabel[result.value.effectiveMembership] or result.value.effectiveMembership
			),
			"SUCCESS"
		)

		return Result.Ok(nil)
	end

	local function executeUngift(player: Player, args: string): Result<nil>
		if not giftLimiter:check(player.UserId) then
			notify.player(player, Config.Gift.MSG_RATE_LIMIT, "WARNING")
			return Result.Err("rate_limited")
		end

		local targetQuery, tierAlias = args:match("^(.+)%s+(%S+)$")
		if not targetQuery or not tierAlias then
			notify.player(player, Config.Gift.MSG_UNGIFT_USAGE, "WARNING")
			return Result.Err("invalid ungift usage")
		end

		local tierKey = resolveGiftTierAlias(tierAlias)
		if not tierKey then
			notify.player(player, Config.Gift.MSG_INVALID:format(tierAlias), "ERROR")
			return Result.Err("invalid tier")
		end

		local target = resolveTargetOrNotify(player, targetQuery, Config.Gift.MSG_NOT_FOUND, Config.Gift.MSG_QUERY_SHORT, Config.Gift.MSG_AMBIGUOUS)
		if not target then
			return Result.Err("target not found")
		end

		local result = membershipCommandService:removeMembership(player, target, tierKey)
		if not result.ok then
			notify.player(player, result.error, "ERROR")
			return Result.Err(result.error)
		end

		overheadController:refreshPlayer(target)
		notify.player(
			player,
			Config.Gift.MSG_UNGIFT:format(
				Config.MembershipChatLabel[result.value.removedTier] or result.value.removedTier,
				target.DisplayName,
				Config.MembershipChatLabel[result.value.effectiveMembership] or result.value.effectiveMembership
			),
			"SUCCESS"
		)
		notify.player(
			target,
			Config.Gift.MSG_TARGET_GIFT_REMOVED:format(
				Config.MembershipChatLabel[result.value.removedTier] or result.value.removedTier,
				Config.MembershipChatLabel[result.value.effectiveMembership] or result.value.effectiveMembership
			),
			"WARNING"
		)

		return Result.Ok(nil)
	end

	local function executeSetRole(player: Player, args: string): Result<nil>
		local targetQuery, roleAlias = args:match("^(.+)%s+(%S+)$")
		if not targetQuery or not roleAlias then
			notify.player(player, "[SetRole] Try /setrole <player> <role>.", "WARNING")
			return Result.Err("invalid setrole usage")
		end

		local roleKey = OverheadDomain.normalizeRoleKey(roleAlias)
		if not roleKey then
			notify.player(player, Config.SetRole.MSG_INVALID_ROLE:format(roleAlias), "ERROR")
			return Result.Err("invalid role")
		end

		local target = resolveTargetOrNotify(player, targetQuery, Config.SetRole.MSG_NOT_FOUND, Config.SetRole.MSG_QUERY_SHORT, Config.SetRole.MSG_AMBIGUOUS)
		if not target then
			return Result.Err("target not found")
		end

		local result = giftService:giveRole(player, target, roleKey)
		if not result.ok then
			notify.player(player, result.error, "ERROR")
			return Result.Err(result.error)
		end

		overheadController:refreshPlayer(target)
		notify.player(
			player,
			Config.SetRole.MSG_SUCCESS:format(OverheadDomain.getRoleDisplayName(result.value), target.Name),
			"SUCCESS"
		)
		return Result.Ok(nil)
	end

	local function executeUnsetRole(player: Player, args: string): Result<nil>
		local targetQuery = trim(args)
		if targetQuery == "" then
			notify.player(player, "[SetRole] Try /unsetrole <player>.", "WARNING")
			return Result.Err("invalid unsetrole usage")
		end

		local target = resolveTargetOrNotify(player, targetQuery, Config.SetRole.MSG_NOT_FOUND, Config.SetRole.MSG_QUERY_SHORT, Config.SetRole.MSG_AMBIGUOUS)
		if not target then
			return Result.Err("target not found")
		end

		local result = giftService:removeRole(player, target)
		if not result.ok then
			notify.player(player, result.error, "ERROR")
			return Result.Err(result.error)
		end

		overheadController:refreshPlayer(target)
		notify.player(
			player,
			Config.SetRole.MSG_REMOVED:format(OverheadDomain.getRoleDisplayName(result.value), target.Name),
			"SUCCESS"
		)
		return Result.Ok(nil)
	end

	local function executeRefresh(player: Player, args: string): Result<nil>
		if trim(args) ~= "" then
			notify.player(player, Config.Session.MSG_USAGE_REFRESH, "WARNING")
			return Result.Err("invalid refresh usage")
		end
		return sessionCommandService:handleRefresh(player)
	end

	local function executeRejoin(player: Player, args: string): Result<nil>
		if trim(args) ~= "" then
			notify.player(player, Config.Session.MSG_USAGE_REJOIN, "WARNING")
			return Result.Err("invalid rejoin usage")
		end
		return sessionCommandService:handleRejoin(player)
	end

	local function canUseTeleport(player: Player): boolean
		if overheadService and type(overheadService.getEffectivePayload) == "function" then
			local payloadResult = overheadService:getEffectivePayload(player)
			if payloadResult.ok then
				return OverheadDomain.canTeleportCommand(payloadResult.value.role, payloadResult.value.effectiveMembership)
			end
		end
		return false
	end

	local function executeTeleport(player: Player, args: string, usageMessage: string, methodName: string): Result<nil>
		local targetQuery = trim(args)
		if targetQuery == "" then
			notify.player(player, usageMessage, "WARNING")
			return Result.Err("invalid teleport usage")
		end
		if not canUseTeleport(player) then
			notify.player(player, Config.Session.MSG_TELEPORT_NO_PERM, "WARNING")
			return Result.Err("teleport permission denied")
		end
		local target = resolveTargetOrNotify(player, targetQuery, "[Teleport] I could not find '%s' in this server.", "[Teleport] Give me at least 3 letters, or use the full name.", "[Teleport] '%s' matches a few people. Be more specific: %s.")
		if not target then
			return Result.Err("target not found")
		end
		if type(sessionCommandService[methodName]) ~= "function" then
			return Result.Err("teleport handler unavailable")
		end
		return sessionCommandService[methodName](sessionCommandService, player, target)
	end

	local function executeAnnounce(player: Player, args: string): Result<nil>
		local message = trim(args)
		if message == "" then
			notify.player(player, Config.Announcement.MSG_USAGE, "WARNING")
			return Result.Err("missing message")
		end
		if not announceLimiter:check(player.UserId) then
			notify.player(player, Config.Announcement.MSG_RATE_LIMIT, "WARNING")
			return Result.Err("rate_limited")
		end
		if not genericBroadcastService then
			return Result.Err("announce_unavailable")
		end

		local clipped = string.sub(message, 1, Config.Announcement.MAX_MESSAGE_LENGTH)
		local ok, err = genericBroadcastService:broadcastFromPlayer(player, clipped, Config.Announcement.MAX_MESSAGE_LENGTH)
		if not ok then
			if err == "no_perm" then
				notify.player(player, Config.Announcement.MSG_NO_PERM, "WARNING")
			else
				notify.player(player, Config.Announcement.MSG_FILTER_FAILED, "ERROR")
			end
			return Result.Err(err or "broadcast_failed")
		end

		notify.player(player, Config.Announcement.MSG_SENT, "SUCCESS")
		log:info("Announcement broadcast", { player = player.Name })
		return Result.Ok(nil)
	end

	local handlers = {
		[Config.AvatarContext.CMD_SET_BIO] = executeSetBio,
		[Config.AvatarContext.CMD_CLEAR_BIO] = function(player: Player, _args: string)
			return executeClearBio(player)
		end,
		[Config.AvatarContext.CMD_SET_STATUS] = executeStatus,
		[Config.AvatarContext.CMD_CLEAR_STATUS] = function(player: Player, _args: string)
			return executeClearStatus(player)
		end,
		[Config.Community.CMD_ALIAS_SET] = executeSetCommunity,
		[Config.Community.CMD_ALIAS_CLEAR] = function(player: Player, _args: string)
			return executeClearCommunity(player)
		end,
		[Config.Gift.CMD_ALIAS_GIFT] = executeGift,
		[Config.Gift.CMD_ALIAS_UNGIFT] = executeUngift,
		[Config.SetRole.CMD_ALIAS_SET] = executeSetRole,
		[Config.SetRole.CMD_ALIAS_UNSET] = executeUnsetRole,
		[Config.Session.CMD_ALIAS_REFRESH] = executeRefresh,
		[Config.Session.CMD_ALIAS_REJOIN] = executeRejoin,
		[Config.Session.CMD_ALIAS_BRING] = function(player: Player, args: string)
			return executeTeleport(player, args, Config.Session.MSG_USAGE_BRING, "handleBring")
		end,
		[Config.Session.CMD_ALIAS_TO] = function(player: Player, args: string)
			return executeTeleport(player, args, Config.Session.MSG_USAGE_TO, "handleTo")
		end,
		[Config.Announcement.CMD_ALIAS_ANNOUNCE] = executeAnnounce,
		[Config.Announcement.CMD_ALIAS_ANNOUNCE_SHORT] = executeAnnounce,
	}

	function service:registerRawHandler(alias: string, handler: (Player, string) -> ())
		if type(alias) ~= "string" or alias == "" then
			return
		end
		rawHandlers[string.lower(alias)] = handler
	end

	function service:bindChatCommands(chatCommandService: any)
		local bound = {} :: { [string]: boolean }
		local function bindAlias(alias: string)
			local key = string.lower(alias)
			if key == "" or bound[key] then
				return
			end
			bound[key] = true
			chatCommandService:register(alias, function(player: Player, unfilteredText: string, _requestId: string)
				local rawHandler = rawHandlers[key]
				if rawHandler then
					rawHandler(player, unfilteredText)
					return
				end
				service:execute(player, unfilteredText)
			end)
		end

		for alias, _ in pairs(handlers) do
			bindAlias(alias)
		end
		for alias, _ in pairs(rawHandlers) do
			bindAlias(alias)
		end
	end

	function service:execute(player: Player, commandText: string): Result<nil>
		local alias, args = splitCommandText(commandText)
		if not alias then
			return Result.Err("Invalid command format.")
		end

		local rawHandler = rawHandlers[alias]
		if rawHandler then
			rawHandler(player, commandText)
			return Result.Ok(nil)
		end

		local handler = handlers[alias]
		if not handler then
			notify.player(player, "[Command] I do not know that command yet.", "ERROR")
			return Result.Err("Unknown command.")
		end

		log:info("Executing command", {
			player = player.Name,
			alias = alias,
		})

		return handler(player, args)
	end

	return service
end

return createCommandExecutionService
