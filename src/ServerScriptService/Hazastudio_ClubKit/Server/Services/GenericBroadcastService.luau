--!strict
-- Shared filter + GenericBroadcast payload fire for /announce and paid broadcast.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

export type BroadcastSenderContext = {
	role: string,
	effectiveMembership: string,
}

export type Service = {
	filterMessage: (self: Service, player: Player, rawMessage: string, maxLength: number?) -> string?,
	getOverheadPayload: (self: Service, player: Player) -> any?,
	getBroadcastSenderContext: (self: Service, player: Player) -> BroadcastSenderContext?,
	buildBroadcastPayload: (self: Service, player: Player, filteredMessage: string) -> { [string]: any }?,
	buildBroadcastPayloadFromContext: (
		self: Service,
		player: Player,
		filteredMessage: string,
		context: BroadcastSenderContext
	) -> { [string]: any },
	fireAll: (self: Service, player: Player, filteredMessage: string, senderContext: BroadcastSenderContext?) -> boolean,
	broadcastFromPlayer: (self: Service, player: Player, rawMessage: string, maxLength: number?) -> (boolean, string?),
	broadcastFiltered: (self: Service, player: Player, filteredMessage: string) -> (boolean, string?),
}

local function runParallel<A, B>(jobA: () -> A, jobB: () -> B): (A, B)
	local resultA: A? = nil
	local resultB: B? = nil
	local doneA = false
	local doneB = false
	task.spawn(function()
		resultA = jobA()
		doneA = true
	end)
	task.spawn(function()
		resultB = jobB()
		doneB = true
	end)
	while not doneA or not doneB do
		task.wait()
	end
	return resultA :: A, resultB :: B
end

local function createGenericBroadcastService(deps: {
	broadcastNetwork: any,
	overheadService: any?,
	logger: any?,
}): Service
	local broadcastNetwork = deps.broadcastNetwork
	local overheadService = deps.overheadService
	local log = deps.logger or Logger.new("GenericBroadcastService")

	local service = {} :: Service

	function service.getOverheadPayload(_self: Service, player: Player): any?
		if overheadService and type(overheadService.getEffectivePayload) == "function" then
			local payloadResult = overheadService:getEffectivePayload(player)
			if payloadResult.ok then
				return payloadResult.value
			end
		elseif overheadService and type(overheadService.buildPayload) == "function" then
			local payloadResult = overheadService:buildPayload(player)
			if payloadResult.ok then
				return payloadResult.value
			end
		end
		return nil
	end

	function service.getBroadcastSenderContext(_self: Service, player: Player): BroadcastSenderContext?
		if overheadService and type(overheadService.buildBroadcastSenderContext) == "function" then
			local contextResult = overheadService:buildBroadcastSenderContext(player)
			if contextResult.ok then
				return contextResult.value
			end
			return nil
		end

		local payload = service:getOverheadPayload(player)
		if not payload then
			return nil
		end
		return {
			role = if type(payload.role) == "string" then payload.role else "Member",
			effectiveMembership = if type(payload.effectiveMembership) == "string"
				then payload.effectiveMembership
				else "Guest",
		}
	end

	function service.filterMessage(_self: Service, player: Player, rawMessage: string, maxLength: number?): string?
		local trimmed = rawMessage:match("^%s*(.-)%s*$") or ""
		if trimmed == "" then
			return nil
		end
		local limit = maxLength or Config.Announcement.MAX_MESSAGE_LENGTH
		trimmed = string.sub(trimmed, 1, limit)

		local ok, filteredOrErr = pcall(function()
			local filtered = TextService:FilterStringAsync(trimmed, player.UserId)
			return filtered:GetNonChatStringForBroadcastAsync()
		end)
		if not ok or type(filteredOrErr) ~= "string" or filteredOrErr == "" then
			log:warn("Generic broadcast filter failed", {
				player = player.Name,
				error = tostring(filteredOrErr),
			})
			return nil
		end
		return filteredOrErr
	end

	function service.buildBroadcastPayloadFromContext(
		_self: Service,
		player: Player,
		filteredMessage: string,
		context: BroadcastSenderContext
	): { [string]: any }
		local roleName = context.role
		return {
			message = filteredMessage,
			senderUserId = player.UserId,
			senderDisplayName = player.DisplayName,
			senderUsername = player.Name,
			senderRole = roleName,
			senderRoleBadge = Config.Donation.ROLE_BADGE_IMAGE[roleName]
				or Config.Donation.ROLE_BADGE_IMAGE.Member,
			duration = Config.Announcement.SHOW_DURATION,
			sentAt = os.time(),
		}
	end

	function service.buildBroadcastPayload(_self: Service, player: Player, filteredMessage: string): { [string]: any }?
		local context = service:getBroadcastSenderContext(player)
		if not context then
			return nil
		end
		return service:buildBroadcastPayloadFromContext(player, filteredMessage, context)
	end

	function service.fireAll(
		_self: Service,
		player: Player,
		filteredMessage: string,
		senderContext: BroadcastSenderContext?
	): boolean
		local context = senderContext or service:getBroadcastSenderContext(player)
		if not context then
			return false
		end
		local broadcastPayload = service:buildBroadcastPayloadFromContext(player, filteredMessage, context)
		-- Documented v3 exception: latency-sensitive one-shot; still via NetworkManager + flushNow.
		broadcastNetwork:fireAllClientsImmediate(broadcastPayload)
		return true
	end

	function service.broadcastFromPlayer(
		_self: Service,
		player: Player,
		rawMessage: string,
		maxLength: number?
	): (boolean, string?)
		local filteredMessage, context = runParallel(
			function()
				return service:filterMessage(player, rawMessage, maxLength)
			end,
			function()
				return service:getBroadcastSenderContext(player)
			end
		)

		if not context or not OverheadDomain.canAnnounce(context.role, context.effectiveMembership) then
			return false, "no_perm"
		end
		if not filteredMessage then
			return false, "filter_failed"
		end
		if not service:fireAll(player, filteredMessage, context) then
			return false, "broadcast_failed"
		end
		return true, nil
	end

	function service.broadcastFiltered(_self: Service, player: Player, filteredMessage: string): (boolean, string?)
		local context = service:getBroadcastSenderContext(player)
		if not context or not OverheadDomain.canAnnounce(context.role, context.effectiveMembership) then
			return false, "no_perm"
		end
		if not service:fireAll(player, filteredMessage, context) then
			return false, "broadcast_failed"
		end
		return true, nil
	end

	return service
end

return createGenericBroadcastService
