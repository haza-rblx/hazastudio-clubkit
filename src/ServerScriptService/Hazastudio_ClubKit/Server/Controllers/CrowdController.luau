--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local PermissionDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.PermissionDomain)
local TextFilterUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.TextFilterUtil)

local function createCrowdController(deps: {
	commandExecutionService: any?,
	overheadService: any?,
	notify: any,
	logger: any,
	rateLimiter: any,
	remotes: Folder,
})
	local commandExecutionService = deps.commandExecutionService
	local overheadService = deps.overheadService
	local notify = deps.notify
	local logger = deps.logger
	local rateLimiter = deps.rateLimiter
	local remotes = deps.remotes
	local crowdConfig = Config.Crowd

	local sayRemote = remotes:FindFirstChild(crowdConfig.REMOTE_SAY) :: RemoteEvent?

	local function canUse(player: Player): boolean
		if overheadService and type(overheadService.getEffectivePayload) == "function" then
			local payloadResult = overheadService:getEffectivePayload(player)
			if payloadResult.ok then
				return PermissionDomain.canUseAdminPanel(payloadResult.value.role, player.UserId)
			end
		end
		if overheadService and type(overheadService.getRawGroupRole) == "function" then
			return PermissionDomain.canUseAdminPanel(overheadService:getRawGroupRole(player), player.UserId)
		end
		return PermissionDomain.canUseAdminPanel(nil, player.UserId)
	end

	local function extractMessage(rawText: string): string
		local rest = string.match(rawText, "^/?[Cc][Rr][Oo][Ww][Dd]%s*(.*)$")
		if rest == nil then
			rest = string.match(rawText, "^%s*/?%S+%s*(.*)$") or ""
		end
		rest = string.gsub(rest, "^%s+", "")
		rest = string.gsub(rest, "%s+$", "")
		return rest
	end

	local function filterForBroadcast(fromPlayer: Player, text: string): (boolean, string?)
		local filtered = TextFilterUtil.filterForBroadcast(fromPlayer.UserId, text)
		if not filtered then
			return false, nil
		end
		local cleaned = string.gsub(filtered, "^%s+", "")
		cleaned = string.gsub(cleaned, "%s+$", "")
		if cleaned == "" then
			return false, nil
		end
		return true, cleaned
	end

	local function handleCrowd(player: Player, rawText: string)
		if not canUse(player) then
			notify.player(player, crowdConfig.MSG_NO_PERM, "WARNING")
			return
		end
		if not rateLimiter:check(player.UserId) then
			notify.player(player, crowdConfig.MSG_RATE_LIMIT, "WARNING")
			return
		end

		local message = extractMessage(rawText)
		if message == "" then
			notify.player(player, crowdConfig.MSG_EMPTY, "WARNING")
			return
		end
		local maxLen = tonumber(crowdConfig.MAX_LEN) or 120
		if #message > maxLen then
			notify.player(player, crowdConfig.MSG_TOO_LONG, "WARNING")
			return
		end

		local filterOk, filtered = filterForBroadcast(player, message)
		if not filterOk or filtered == nil then
			notify.player(player, crowdConfig.MSG_FILTER_FAILED, "WARNING")
			return
		end

		if sayRemote == nil or not sayRemote:IsA("RemoteEvent") then
			logger:warn("CrowdSay remote missing")
			return
		end

		local speakers: { number } = {}
		for _, p in ipairs(Players:GetPlayers()) do
			local character = p.Character
			if character and character:FindFirstChild("Head") then
				table.insert(speakers, p.UserId)
			end
		end

		sayRemote:FireAllClients({
			text = filtered,
			speakerUserIds = speakers,
			byUserId = player.UserId,
		})
		notify.player(player, crowdConfig.MSG_OK, "SUCCESS")
		logger:info("Crowd say", { by = player.Name, len = #filtered, speakers = #speakers })
	end

	local controller = {}

	function controller:init()
		if Config.FeatureFlags.CrowdEnabled ~= true then
			logger:info("Crowd disabled by feature flag")
			return
		end
		if commandExecutionService then
			commandExecutionService:registerRawHandler(crowdConfig.CMD_ALIAS, handleCrowd)
		end
		logger:info("CrowdController ready")
	end

	return controller
end

return createCrowdController
