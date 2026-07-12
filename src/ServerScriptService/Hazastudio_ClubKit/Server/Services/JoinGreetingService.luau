--!strict
-- Once-per-session join greetings for Owner / Leadership / Content / top-N spenders.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local RolesDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.RolesDomain)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

export type CategoryKind = "Owner" | "Leadership" | "Content" | "SpenderRobux" | "SpenderCash"

export type Match = {
	roleKey: string,
	categoryKind: CategoryKind,
	rank: number?,
}

export type Service = {
	onPlayerReady: (self: Service, player: Player) -> (),
	onPayloadUpdated: (self: Service, player: Player) -> (),
	onPlayerRemoving: (self: Service, player: Player) -> (),
	destroy: (self: Service) -> (),
}

local function getRoleToCategory(): { [string]: number }
	local privileges = Config.RolePrivileges
	if type(privileges) == "table" and type(privileges.ROLE_TO_CATEGORY) == "table" then
		return privileges.ROLE_TO_CATEGORY
	end
	local roles = Config.Roles
	if type(roles) == "table" and type(roles.ROLE_TO_CATEGORY) == "table" then
		return roles.ROLE_TO_CATEGORY
	end
	return {}
end

local function getGreetingCfg(): any
	return Config.JoinGreeting or {}
end

local function getCategoryIds(): (number, number)
	local cfg = getGreetingCfg()
	local ids = cfg.GREETING_CATEGORY_IDS
	if type(ids) == "table" then
		return tonumber(ids.Leadership) or 1, tonumber(ids.Content) or 3
	end
	return 1, 3
end

local function getSpenderTopN(): number
	return math.max(1, tonumber(getGreetingCfg().SPENDER_TOP_N) or 10)
end

local function getSpenderKeys(): (string, string)
	local spenderRoles = Config.SpenderRoles
	local robuxKey = "RoyaleSpender"
	local cashKey = "TopSpender"
	if type(spenderRoles) == "table" then
		local robux = spenderRoles.RobuxSpender
		if type(robux) == "table" and type(robux.Key) == "string" and robux.Key ~= "" then
			robuxKey = robux.Key
		end
		local cash = spenderRoles.CashSpender
		if type(cash) == "table" and type(cash.Key) == "string" and cash.Key ~= "" then
			cashKey = cash.Key
		end
	end
	return robuxKey, cashKey
end

local function fillPlaceholders(template: string, rank: number?): string
	local text = template
	if rank ~= nil then
		-- Replace #{N} before {N} so "#3" wins over leaving a stray "#".
		text = string.gsub(text, "#{N}", "#" .. tostring(rank))
		text = string.gsub(text, "{N}", tostring(rank))
	end
	return text
end

local function pickFromPool(poolKey: string, rank: number?): string?
	local pools = getGreetingCfg().MESSAGE_POOLS
	if type(pools) ~= "table" then
		return nil
	end

	local pool = pools[poolKey]
	if rank == 1 then
		local rankOne = pools[poolKey .. "#1"]
		if type(rankOne) == "table" and #rankOne > 0 then
			pool = rankOne
		end
	end
	if type(pool) ~= "table" or #pool == 0 then
		return nil
	end

	local picked = pool[math.random(1, #pool)]
	if type(picked) ~= "string" or picked == "" then
		return nil
	end
	return fillPlaceholders(picked, rank)
end

local function resolveMessage(match: Match): string
	local roleKey = match.roleKey
	local kind = match.categoryKind
	local rank = match.rank

	local message = pickFromPool(roleKey, rank)
	if message then
		return message
	end

	if kind == "Leadership" then
		message = pickFromPool("_Leadership", rank)
	elseif kind == "Content" then
		message = pickFromPool("_Content", rank)
	elseif kind == "SpenderRobux" then
		local robuxKey = getSpenderKeys()
		message = pickFromPool(robuxKey, rank) or pickFromPool("RoyaleSpender", rank)
	elseif kind == "SpenderCash" then
		local _, cashKey = getSpenderKeys()
		message = pickFromPool(cashKey, rank) or pickFromPool("TopSpender", rank)
	elseif kind == "Owner" then
		message = pickFromPool("Owner", rank)
	end

	return message or "Welcome to the club."
end

local function resolveChip(match: Match): string
	local labels = getGreetingCfg().CHIP_LABELS
	if type(labels) ~= "table" then
		labels = {}
	end

	local rank = match.rank
	local roleKey = match.roleKey
	local kind = match.categoryKind

	if kind == "SpenderRobux" or kind == "SpenderCash" then
		local templateKey = if kind == "SpenderRobux" then "RoyaleSpender" else "TopSpender"
		local template = labels[templateKey]
		if type(template) == "string" and template ~= "" then
			return fillPlaceholders(template, rank)
		end
		if kind == "SpenderRobux" then
			return ("Top Supporter #%d"):format(rank or 0)
		end
		return ("Top Donor #%d"):format(rank or 0)
	end

	local labeled = labels[roleKey]
	if type(labeled) == "string" and labeled ~= "" then
		return labeled
	end

	local definition = RolesDomain.getDefinition(roleKey)
	if definition then
		if type(definition.label) == "string" and definition.label ~= "" then
			return definition.label
		end
		if type(definition.chatTag) == "string" and definition.chatTag ~= "" then
			return definition.chatTag
		end
	end

	if kind == "Leadership" then
		local fallback = labels._Leadership
		if type(fallback) == "string" and fallback ~= "" then
			return fallback
		end
		return "Staff"
	end
	if kind == "Content" then
		local fallback = labels._Content
		if type(fallback) == "string" and fallback ~= "" then
			return fallback
		end
		return "Content"
	end
	if kind == "Owner" then
		local ownerChip = labels.Owner
		if type(ownerChip) == "string" and ownerChip ~= "" then
			return ownerChip
		end
		return "The Owner"
	end
	return roleKey
end

local function resolveRoleBadge(roleKey: string): string
	local badges = Config.Donation and Config.Donation.ROLE_BADGE_IMAGE
	if type(badges) ~= "table" then
		return ""
	end
	local image = badges[roleKey]
	if type(image) == "string" then
		return image
	end
	return ""
end

local function isOwnerPlayer(player: Player, roleKey: string): boolean
	if roleKey == "Owner" then
		return true
	end
	local ownerUserId = Config.Group.OWNER_USER_ID
	return type(ownerUserId) == "number" and ownerUserId > 0 and player.UserId == ownerUserId
end

local function evaluateMatch(player: Player, payload: any): Match?
	if type(payload) ~= "table" then
		return nil
	end

	local roleKey = if type(payload.role) == "string" and payload.role ~= "" then payload.role else "Guest"
	local leadershipId, contentId = getCategoryIds()
	local roleToCategory = getRoleToCategory()
	local topN = getSpenderTopN()
	local robuxKey, cashKey = getSpenderKeys()

	if isOwnerPlayer(player, roleKey) then
		return {
			roleKey = "Owner",
			categoryKind = "Owner",
			rank = nil,
		}
	end

	local categoryId = roleToCategory[roleKey]
	if categoryId == leadershipId then
		return {
			roleKey = roleKey,
			categoryKind = "Leadership",
			rank = nil,
		}
	end
	if categoryId == contentId then
		return {
			roleKey = roleKey,
			categoryKind = "Content",
			rank = nil,
		}
	end

	local donateRank = tonumber(payload.topDonateRank)
	if donateRank and donateRank >= 1 and donateRank <= topN then
		return {
			roleKey = robuxKey,
			categoryKind = "SpenderRobux",
			rank = donateRank,
		}
	end

	local spendRank = tonumber(payload.topSpenderRank)
	if spendRank and spendRank >= 1 and spendRank <= topN then
		return {
			roleKey = cashKey,
			categoryKind = "SpenderCash",
			rank = spendRank,
		}
	end

	return nil
end

local function ranksMayStillSettle(payload: any): boolean
	if type(payload) ~= "table" then
		return true
	end
	local donateRank = tonumber(payload.topDonateRank)
	local spendRank = tonumber(payload.topSpenderRank)
	local donateMissing = donateRank == nil or donateRank <= 0
	local spendMissing = spendRank == nil or spendRank <= 0
	return donateMissing or spendMissing
end

local function createJoinGreetingService(deps: {
	broadcastNetwork: any,
	overheadService: any?,
	logger: any?,
}): Service
	local broadcastNetwork = deps.broadcastNetwork
	local overheadService = deps.overheadService
	local log = deps.logger or Logger.new("JoinGreetingService")

	-- Once-per-session: fired userIds. Also gate concurrent evaluates — getPayload
	-- yields (OverheadService.buildPayload waits on GroupService/DataStore), so
	-- onPlayerReady + onPayloadUpdated (~cash settle) can both pass a post-check
	-- guard and double-fire the same RoyaleSpender greeting ~1s apart.
	local greetedUserIds: { [number]: boolean } = {}
	local evaluationInFlight: { [number]: boolean } = {}
	local settleScheduled: { [number]: boolean } = {}
	local evaluationComplete: { [number]: boolean } = {}

	local service = {} :: Service

	local function getPayload(player: Player): any?
		if not overheadService then
			return nil
		end
		if type(overheadService.getEffectivePayload) == "function" then
			local result = overheadService:getEffectivePayload(player)
			if result and result.ok then
				return result.value
			end
		end
		if type(overheadService.buildPayload) == "function" then
			local result = overheadService:buildPayload(player)
			if result and result.ok then
				return result.value
			end
		end
		return nil
	end

	local function fireGreeting(player: Player, match: Match)
		local message = resolveMessage(match)
		local chipText = resolveChip(match)
		local cfg = getGreetingCfg()
		-- Show window = hold + fade-out + fade-in + welcome (exit anim is after bar, like broadcast).
		local messageFade = tonumber(cfg.MESSAGE_FADE) or 0.35
		local showDuration = (tonumber(cfg.MESSAGE_HOLD) or 8.0)
			+ (messageFade * 2)
			+ (tonumber(cfg.WELCOME_HOLD) or 6.3)

		local payload = {
			userId = player.UserId,
			displayName = player.DisplayName,
			username = player.Name,
			roleKey = match.roleKey,
			categoryKind = match.categoryKind,
			chipText = chipText,
			message = message,
			roleBadge = resolveRoleBadge(match.roleKey),
			rank = match.rank,
			messageHold = tonumber(cfg.MESSAGE_HOLD) or 8.0,
			messageFade = messageFade,
			welcomeHold = tonumber(cfg.WELCOME_HOLD) or 6.3,
			exitDuration = tonumber(cfg.EXIT) or 0.22,
			enterDuration = tonumber(cfg.ENTER) or 0.28,
			duration = showDuration,
			sentAt = os.time(),
		}

		broadcastNetwork:fireAllClientsImmediate(payload)
		log:info("Join greeting fired", {
			userId = player.UserId,
			categoryKind = match.categoryKind,
			roleKey = match.roleKey,
			rank = match.rank,
		})
	end

	local function tryEvaluate(player: Player, allowScheduleSettle: boolean)
		if Config.FeatureFlags.JoinGreetingsEnabled ~= true then
			return
		end
		if not player.Parent then
			return
		end

		local userId = player.UserId
		if greetedUserIds[userId] or evaluationComplete[userId] or evaluationInFlight[userId] then
			return
		end
		-- Claim before getPayload yields so concurrent onPlayerReady / onPayloadUpdated
		-- cannot both fire the same session greeting.
		evaluationInFlight[userId] = true

		local ok, err = pcall(function()
			local payload = getPayload(player)
			local match = evaluateMatch(player, payload)
			if match then
				greetedUserIds[userId] = true
				evaluationComplete[userId] = true
				fireGreeting(player, match)
				return
			end

			if allowScheduleSettle and not settleScheduled[userId] and ranksMayStillSettle(payload) then
				settleScheduled[userId] = true
				local baseDelay = tonumber(Config.Overhead and Config.Overhead.GROUP_RANK_SETTLE_DELAY) or 5
				-- Match OverheadController's final settle rebroadcast window.
				local delaySec = baseDelay * 2
				task.delay(delaySec, function()
					if not player.Parent then
						evaluationComplete[userId] = true
						return
					end
					if greetedUserIds[userId] or evaluationComplete[userId] then
						return
					end
					-- Final settle pass: ranks may have arrived via overhead rebroadcast.
					tryEvaluate(player, false)
					if not greetedUserIds[userId] then
						evaluationComplete[userId] = true
					end
				end)
				return
			end

			-- Ready path with ranks already present (or nil settle not needed): stop retrying.
			if allowScheduleSettle and not ranksMayStillSettle(payload) then
				evaluationComplete[userId] = true
			end
			-- onPayloadUpdated before settle completes: leave incomplete so a late rank can still greet.
		end)

		evaluationInFlight[userId] = nil
		if not ok then
			log:warn("Join greeting evaluate failed", {
				userId = userId,
				error = tostring(err),
			})
		end
	end

	function service.onPlayerReady(_self: Service, player: Player)
		tryEvaluate(player, true)
	end

	function service.onPayloadUpdated(_self: Service, player: Player)
		-- Rank rebroadcast / cash settle: re-check only if not yet greeted / in-flight.
		tryEvaluate(player, false)
	end

	function service.onPlayerRemoving(_self: Service, player: Player)
		local userId = player.UserId
		greetedUserIds[userId] = nil
		evaluationInFlight[userId] = nil
		settleScheduled[userId] = nil
		evaluationComplete[userId] = nil
	end

	function service.destroy(_self: Service)
		table.clear(greetedUserIds)
		table.clear(evaluationInFlight)
		table.clear(settleScheduled)
		table.clear(evaluationComplete)
	end

	return service
end

return createJoinGreetingService
