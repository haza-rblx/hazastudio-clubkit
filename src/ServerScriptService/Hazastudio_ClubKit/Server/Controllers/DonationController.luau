--!strict
-- Server/Controllers/DonationController.lua
-- Handle remote commands: /linkdonor, /claimdonor
-- Hanya admin yang bisa /linkdonor. Semua player bisa /claimdonor (with rate limit).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local IS_STUDIO = RunService:IsStudio()
local Config         = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger         = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local NetworkManager = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkManager)
local DonationProviderDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.DonationProviderDomain)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local PermissionDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.PermissionDomain)
local RateLimiter    = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local TTLSet         = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.TTLSet)
local Validator      = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Validator)
local DemoDataProvider = require(script.Parent.Parent.Services.DemoDataProvider)
local LeaderboardIdentity = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.LeaderboardIdentity)
local WorkspaceLeaderboardRenderService = require(script.Parent.Parent.Services.WorkspaceLeaderboardRenderService)
local WorkspaceLeaderboardRenderer = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Leaderboards.WorkspaceLeaderboardRenderer)
local LeaderboardScaleAudit = require(script.Parent.Parent.Debug.LeaderboardScaleAudit)
type INotify = {
	player: (Player, string, string?) -> (),
	all   : (string, string?) -> (),
}
local function createDonationController(deps: {
	donationService   : any,
	overheadService   : any,  -- untuk cek role admin
	commandExecutionService: any,
	notify            : INotify,
	remotes           : Folder,
	leaderboardRepository: any?,
	avatarLikeRepository: any?,
	leaderboardsRemote: RemoteEvent?,
	leaderboardsSnapshotRemote: RemoteEvent?,
	leaderboardsSnapshotResponseRemote: RemoteEvent?,
	workspaceLeaderboardRefresh: { refresh: (() -> ())? }?,
})
	local donationService    = deps.donationService
	local overheadService    = deps.overheadService
	local commandExecutionService = deps.commandExecutionService
	local notify             = deps.notify
	local remotesFolder      = deps.remotes
	local leaderboardRepository = deps.leaderboardRepository
	local avatarLikeRepository = deps.avatarLikeRepository
	local leaderboardsRemote = deps.leaderboardsRemote
	local leaderboardsSnapshotRemote = deps.leaderboardsSnapshotRemote
	local leaderboardsSnapshotResponseRemote = deps.leaderboardsSnapshotResponseRemote
	local log                = Logger.new("DonationController")
	local snapshotLimiter = RateLimiter.new(Config.Leaderboards.SNAPSHOT_RATE_MAX, Config.Leaderboards.SNAPSHOT_RATE_WINDOW)
	local adminCommandLimiter =
		RateLimiter.new(Config.Leaderboards.ADMIN_REFRESH_RATE_MAX, Config.Leaderboards.ADMIN_REFRESH_RATE_WINDOW)
	-- NetworkManagers batch per-Heartbeat. Donation broadcasts and snapshot
	-- responses both fire to viewers; batching ensures wire load grows with
	-- recipient count, not event count.
	local leaderboardsNetwork: any = nil
	if leaderboardsRemote then
		leaderboardsNetwork = NetworkManager.create({
			reliable = leaderboardsRemote,
			logger = log,
			isServer = true,
		})
	end
	local snapshotResponseNetwork: any = nil
	if leaderboardsSnapshotResponseRemote then
		snapshotResponseNetwork = NetworkManager.create({
			reliable = leaderboardsSnapshotResponseRemote,
			logger = log,
			isServer = true,
		})
	end
	local donorProfileNetwork: any = nil
	local processedSnapshotReqs = TTLSet.create({
		ttl = Config.Security.REQUEST_DEDUPE_WINDOW,
		maxSize = Config.Security.MAX_REQUEST_CACHE or 500,
	})
	local processedAdminCommands = TTLSet.create({
		ttl = Config.Security.REQUEST_DEDUPE_WINDOW,
		maxSize = 100,
	})
	local workspaceLeaderboardCache: { [string]: any }? = nil
	local workspaceLeaderboardCacheExpiresAt = 0
	local demoProvider: any = nil

	local function isDonationApiConfigured(): boolean
		local donation = Config.Donation
		local apiUrl = if type(donation) == "table" then donation.API_URL or donation.SHEETS_WEB_APP_URL else nil
		if type(apiUrl) ~= "string" or apiUrl == "" then
			return false
		end
		local secretsFolder = ServerScriptService:FindFirstChild("Hazastudio_ClubKitSecrets")
		local secretsModule = secretsFolder and secretsFolder:FindFirstChild("Secrets")
		if not secretsModule or not secretsModule:IsA("ModuleScript") then
			return false
		end
		local ok, secrets = pcall(require, secretsModule)
		return ok and type(secrets.DonationApiSecret) == "string" and secrets.DonationApiSecret ~= ""
	end

	local function resolveDatastoreBoardState(fetchOk: boolean, fetchResult: any, entryCount: number): string
		if entryCount > 0 then
			return "ready"
		end
		if not fetchOk then
			return "error"
		end
		if type(fetchResult) == "table" and fetchResult.ok == false then
			return "error"
		end
		return "empty"
	end

	local function attachBoardStates(payload: { [string]: any }, saweriaFetchOk: boolean?)
		local saweriaCount = if type(payload.saweria) == "table" then #payload.saweria else 0
		payload.boardStates = {
			robux = payload._robuxState or "empty",
			community = payload._communityState or "empty",
			likes = payload._likesState or "empty",
			saweria = if not isDonationApiConfigured() then "not_configured"
				elseif saweriaCount > 0 then "ready"
				elseif saweriaFetchOk == false then "error"
				else "empty",
		}
		payload._robuxState = nil
		payload._communityState = nil
		payload._likesState = nil
	end

	local function splitArgs(rawText: string): {string}
		local args = {} :: {string}
		for token in string.gmatch(rawText, "%S+") do
			table.insert(args, token)
		end
		table.remove(args, 1)
		return args
	end
	local function getProviderDonorLabel(): string
		return DonationProviderDomain.getDonorLabel()
	end

	local function getExternalProviderName(): string
		return DonationProviderDomain.getName()
	end

	local function isCashDonationEnabled(): boolean
		local cashEnabled = Config.FeatureFlags.DonationCashEnabled
		if cashEnabled == nil then
			cashEnabled = Config.FeatureFlags.DonationSaweriaEnabled ~= false
		end
		return cashEnabled ~= false
	end
	-- Remote: DonationAdminCommand
	local AdminCommandRemote = remotesFolder:FindFirstChild(Config.Donation.REMOTE_ADMIN_COMMAND) :: RemoteEvent?
	if not AdminCommandRemote then
		local created = Instance.new("RemoteEvent")
		created.Name = Config.Donation.REMOTE_ADMIN_COMMAND
		created.Parent = remotesFolder
		AdminCommandRemote = created
	end
	local adminCommandRemote = AdminCommandRemote :: RemoteEvent
	-- Helper: cek admin
	local function isAdmin(player: Player): boolean
		if overheadService and type(overheadService.getEffectivePayload) == "function" then
			local payloadResult = overheadService:getEffectivePayload(player)
			if payloadResult.ok then
				return PermissionDomain.canGift(payloadResult.value.role, player.UserId)
			end
		end
		return PermissionDomain.canGift(overheadService:getRawGroupRole(player), player.UserId)
	end
	local function isOwner(player: Player): boolean
		if PermissionDomain.isAdminUser(player.UserId) then
			return true
		end
		if overheadService and type(overheadService.getEffectivePayload) == "function" then
			local payloadResult = overheadService:getEffectivePayload(player)
			if payloadResult.ok then
				return payloadResult.value.role == "Owner"
			end
		end
		return overheadService:getRawGroupRole(player) == "Owner"
	end
	local leaderboardRevision = 0
	local lastWorkspaceBroadcastFingerprint: string? = nil
	-- Debounce state for the workspace leaderboard network fan-out (see
	-- broadcastWorkspaceLeaderboards). Coalesces donation-burst top-3 shifts.
	local lastWorkspaceNetBroadcastAt = 0
	local workspaceNetBroadcastPending = false

	local function workspacePayloadFingerprint(payload: { [string]: any }): string
		local parts = { tostring(payload.updatedAt or 0) }
		for _, key in { "robux", "community", "saweria", "dailySaweria", "dailyRobux", "likes" } do
			local list = payload[key]
			if type(list) == "table" then
				table.insert(parts, key .. ":" .. tostring(#list))
				for i = 1, math.min(3, #list) do
					local entry = list[i]
					if type(entry) == "table" then
						table.insert(
							parts,
							tostring(entry.userId or entry.username or "")
								.. ":"
								.. tostring(entry.amount or entry.total or entry.totalAmount or 0)
						)
					end
				end
			end
		end
		return table.concat(parts, "|")
	end

	local function invalidateWorkspaceLeaderboardCache()
		workspaceLeaderboardCache = nil
		workspaceLeaderboardCacheExpiresAt = 0
	end

	local function stampLeaderboardRevision(payload: { [string]: any })
		leaderboardRevision += 1
		payload.leaderboardRevision = leaderboardRevision
		workspace:SetAttribute(Config.Leaderboards.REVISION_ATTRIBUTE, leaderboardRevision)
		return payload
	end

	local function buildWorkspaceLeaderboardPayload(forceRefresh: boolean?)
		-- Demo mode: return fake data from friend list, skip all DataStore/API.
		if Config.Demo and Config.Demo.ENABLED == true then
			if not demoProvider then
				demoProvider = DemoDataProvider.create(Config.Demo)
			end
			return demoProvider:buildPayload()
		end

		local now = os.clock()
		if not forceRefresh and workspaceLeaderboardCache and now < workspaceLeaderboardCacheExpiresAt then
			return workspaceLeaderboardCache
		end

		local payload: { [string]: any } = {
			updatedAt = os.time(),
			robux = {},
			community = {},
			saweria = {},
			dailySaweria = {},
			dailyRobux = {},
			likes = {},
		}

		if leaderboardRepository then
			local robuxOk, robuxResult = pcall(function()
				return leaderboardRepository:getRobuxLeaderboard(Config.Leaderboards.ROBUX_LIMIT)
			end)
			if robuxOk and type(robuxResult) == "table" and robuxResult.ok then
				payload.robux = robuxResult.value
			elseif not robuxOk then
				log:warn("getRobuxLeaderboard error", { error = tostring(robuxResult) })
			elseif robuxOk and type(robuxResult) == "table" then
				log:debug("getRobuxLeaderboard returned Err", { error = tostring(robuxResult.error) })
			end
			payload._robuxState = resolveDatastoreBoardState(robuxOk, robuxResult, #payload.robux)

			local communityOk, communityResult = pcall(function()
				return leaderboardRepository:getCommunityLeaderboard(Config.Leaderboards.COMMUNITY_LIMIT)
			end)
			if communityOk and type(communityResult) == "table" and communityResult.ok then
				payload.community = communityResult.value
			elseif not communityOk then
				log:warn("getCommunityLeaderboard error", { error = tostring(communityResult) })
			elseif communityOk and type(communityResult) == "table" then
				log:debug("getCommunityLeaderboard returned Err", { error = tostring(communityResult.error) })
			end
			payload._communityState = resolveDatastoreBoardState(communityOk, communityResult, #payload.community)
		end

		if avatarLikeRepository and type(avatarLikeRepository.getTopLeaderboard) == "function" then
			local likesOk, likesResult = pcall(function()
				return avatarLikeRepository:getTopLeaderboard(Config.Leaderboards.LIKES_LIMIT)
			end)
			if likesOk and type(likesResult) == "table" and likesResult.ok then
				payload.likes = likesResult.value
			elseif not likesOk then
				log:warn("getTopLeaderboard error", { error = tostring(likesResult) })
			elseif likesOk and type(likesResult) == "table" then
				log:debug("getTopLeaderboard returned Err", { error = tostring(likesResult.error) })
			end
			payload._likesState = resolveDatastoreBoardState(likesOk, likesResult, #payload.likes)
		end
		local saweriaFetchOk = true
		if donationService and type(donationService.getWorkspaceSaweriaLeaderboard) == "function" then
			local sawOk, sawResult = pcall(donationService.getWorkspaceSaweriaLeaderboard, donationService, Config.Leaderboards.SAWERIA_LIMIT)
			saweriaFetchOk = sawOk
			if sawOk and type(sawResult) == "table" then
				payload.saweria = sawResult
			elseif not sawOk then
				log:warn("getWorkspaceSaweriaLeaderboard error", { error = tostring(sawResult) })
			end
		end
		if donationService and type(donationService.getWorkspaceDailySaweriaLeaderboard) == "function" then
			local dailyOk, dailyResult = pcall(donationService.getWorkspaceDailySaweriaLeaderboard, donationService, Config.Leaderboards.SAWERIA_LIMIT)
			if dailyOk and type(dailyResult) == "table" then
				payload.dailySaweria = dailyResult
			elseif not dailyOk then
				log:warn("getWorkspaceDailySaweriaLeaderboard error", { error = tostring(dailyResult) })
			end
		end
		if Config.Leaderboards.DAILY_ROBUX_ENABLED == true then
			if donationService and type(donationService.getWorkspaceDailyRobuxLeaderboard) == "function" then
				local drOk, drResult = pcall(donationService.getWorkspaceDailyRobuxLeaderboard, donationService, Config.Leaderboards.ROBUX_LIMIT)
				if drOk and type(drResult) == "table" then
					payload.dailyRobux = drResult
				elseif not drOk then
					log:warn("getWorkspaceDailyRobuxLeaderboard error", { error = tostring(drResult) })
				end
			end
		end

		-- Wrap enrichEntryList with pcall karena resolveUserIdentity bisa error (HTTP timeout dll)
		local enrichSafe = function(entries)
			local ok, result = pcall(LeaderboardIdentity.enrichEntryList, LeaderboardIdentity, entries)
			if not ok then
				log:warn("enrichEntryList error", { error = tostring(result) })
			end
			return entries
		end
		enrichSafe(payload.robux)
		enrichSafe(payload.community)
		enrichSafe(payload.saweria)
		enrichSafe(payload.likes)
		enrichSafe(payload.dailySaweria)
		if Config.Leaderboards.DAILY_ROBUX_ENABLED == true then
			enrichSafe(payload.dailyRobux)
		end

		-- Log payload summary buat debugging
		log:debug("Leaderboard payload built", {
			robux = #payload.robux,
			community = #payload.community,
			saweria = #payload.saweria,
			dailySaweria = #payload.dailySaweria,
			likes = #payload.likes,
		})

		attachBoardStates(payload, saweriaFetchOk)

		workspaceLeaderboardCache = payload
		workspaceLeaderboardCacheExpiresAt = now + Config.Leaderboards.WORKSPACE_CACHE_TTL
		return payload
	end
	local function paintWorkspaceLeaderboards(payload: any)
		if Config.Leaderboards.SERVER_PAINT_WORKSPACE == true then
			WorkspaceLeaderboardRenderService.apply(payload)
		end
	end

	local function broadcastWorkspaceLeaderboards(forceRefresh: boolean?)
		local buildStart = os.clock()
		local payload = buildWorkspaceLeaderboardPayload(forceRefresh)
		local buildMs = (os.clock() - buildStart) * 1000
		local fingerprint = workspacePayloadFingerprint(payload)
		local fingerprintChanged = fingerprint ~= lastWorkspaceBroadcastFingerprint
		if fingerprintChanged then
			stampLeaderboardRevision(payload)
		end
		local paintStart = os.clock()
		paintWorkspaceLeaderboards(payload)
		local paintMs = (os.clock() - paintStart) * 1000
		if leaderboardsNetwork and fingerprintChanged then
			lastWorkspaceBroadcastFingerprint = fingerprint
			-- Debounce the network fan-out: during a donation burst the top-3
			-- fingerprint can shift several times within a few seconds, and each
			-- shift would otherwise push the full ~180-entry payload to EVERY
			-- client. Coalesce rapid shifts into a single trailing broadcast so
			-- we cap wire cost at one full broadcast per MIN_INTERVAL. The
			-- trailing fire uses the latest cached payload so no update is lost.
			local WORKSPACE_BROADCAST_MIN_INTERVAL = 3
			local now = os.clock()
			if now - lastWorkspaceNetBroadcastAt < WORKSPACE_BROADCAST_MIN_INTERVAL then
				if not workspaceNetBroadcastPending then
					workspaceNetBroadcastPending = true
					task.delay(WORKSPACE_BROADCAST_MIN_INTERVAL, function()
						workspaceNetBroadcastPending = false
						lastWorkspaceNetBroadcastAt = os.clock()
						if leaderboardsNetwork and workspaceLeaderboardCache then
							leaderboardsNetwork:fireAllClients(workspaceLeaderboardCache)
						end
					end)
				end
			else
				lastWorkspaceNetBroadcastAt = now
				leaderboardsNetwork:fireAllClients(payload)
			end
		end
		local metrics = LeaderboardScaleAudit.metricsFromPayload(payload, buildMs, paintMs)
		LeaderboardScaleAudit.logBroadcast(metrics, not fingerprintChanged)
	end
	if leaderboardsSnapshotRemote then
		leaderboardsSnapshotRemote.OnServerEvent:Connect(function(player: Player, raw: any)
			if not Validator.checkSize(raw) then
				log:warn("Workspace leaderboard snapshot rejected: payload too large", { player = player.Name })
				return
			end
			if
				not leaderboardsSnapshotResponseRemote
				or type(raw) ~= "table"
				or type(raw.requestId) ~= "string"
				or raw.requestId == ""
			then
				return
			end
			if not snapshotLimiter:check(player.UserId) then
				log:warn("Workspace leaderboard snapshot rate limited", { player = player.Name })
				return
			end
			if processedSnapshotReqs:contains(raw.requestId) then
				if snapshotResponseNetwork then
					snapshotResponseNetwork:fireClient(player, {
						type = "workspace_leaderboards_snapshot_response",
						requestId = raw.requestId,
						ok = true,
						data = buildWorkspaceLeaderboardPayload(),
					})
				end
				return
			end
			processedSnapshotReqs:add(raw.requestId)

			task.spawn(function()
				if snapshotResponseNetwork then
					snapshotResponseNetwork:fireClient(player, {
						type = "workspace_leaderboards_snapshot_response",
						requestId = raw.requestId,
						ok = true,
						data = buildWorkspaceLeaderboardPayload(),
					})
				end
			end)
		end)
	end
	if donationService and type(donationService.onLeaderboardUpdated) == "function" then
		donationService:onLeaderboardUpdated(function()
			invalidateWorkspaceLeaderboardCache()
			broadcastWorkspaceLeaderboards(true)
		end)
	end

	-- Pre-warm the workspace leaderboard cache at controller init so the first
	-- client snapshot request hits a hot cache instead of yielding through cold
	-- DataStore calls. Without this, BudgetGate defers + GetSortedAsync latency
	-- can stack to >10s on first call, exceeding the client's snapshot timeout.
	task.spawn(function()
		WorkspaceLeaderboardRenderer.bootstrapLoadingUntilRevision()
	end)
	local function emptyWorkspaceLeaderboardPayload(): { [string]: any }
		local payload = {
			updatedAt = os.time(),
			robux = {},
			community = {},
			saweria = {},
			dailySaweria = {},
			dailyRobux = {},
			likes = {},
		}
		attachBoardStates(payload, true)
		return payload
	end

	task.spawn(function()
		local ok, payloadOrErr = pcall(buildWorkspaceLeaderboardPayload, false)
		if not ok then
			log:warn("Leaderboard cache pre-warm failed", { error = tostring(payloadOrErr) })
			local fallback = emptyWorkspaceLeaderboardPayload()
			stampLeaderboardRevision(fallback)
			paintWorkspaceLeaderboards(fallback)
			return
		end
		stampLeaderboardRevision(payloadOrErr)
		paintWorkspaceLeaderboards(payloadOrErr)
	end)

	-- Server-push leaderboard to new joiners. Replaces the cold-cache snapshot
	-- request roundtrip with a direct push using the cached payload, so the
	-- workspace SurfaceGui has data ready by the time the player can see it.
	-- Snapshot request remote stays wired as a fallback for explicit refresh.
	local function pushLeaderboardTo(player: Player)
		if not leaderboardsNetwork then
			return
		end
		if Config.Demo and Config.Demo.ENABLED == true then
			-- Showcase profile pool depends on who is currently in-server.
			-- Reset on join so a cold-start fallback payload does not stick.
			if demoProvider and type(demoProvider.reset) == "function" then
				demoProvider:reset()
			end
			invalidateWorkspaceLeaderboardCache()
		end
		local ok, payloadOrError = pcall(buildWorkspaceLeaderboardPayload, false)
		if not ok then
			log:warn("Leaderboard push to joiner failed", {
				player = player.Name,
				error = tostring(payloadOrError),
			})
			return
		end
		stampLeaderboardRevision(payloadOrError)
		paintWorkspaceLeaderboards(payloadOrError)
		leaderboardsNetwork:fireClient(player, payloadOrError)
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(pushLeaderboardTo, player)
	end)
	for _, existingPlayer in ipairs(Players:GetPlayers()) do
		task.spawn(pushLeaderboardTo, existingPlayer)
	end
	-- Chat commands
	-- /linkdonor <providerName> <robloxUsername> (owner only)
	commandExecutionService:registerRawHandler(Config.Donation.CMD_LINK_DONOR, function(player: Player, rawText: string)
		local args = splitArgs(rawText)
		if not isOwner(player) then
			notify.player(player, Config.Donation.MSG_LINK_NO_PERM, "ERROR")
			return
		end
		local saweriaName    = args[1]
		local robloxUsername = args[2]
		if not saweriaName or not robloxUsername then
			notify.player(player, "[Donation] Try /linkdonor <" .. getProviderDonorLabel() .. "> <robloxUsername>.", "WARNING")
			return
		end
		task.spawn(function()
			local ok, err = donationService:linkDonor(saweriaName, robloxUsername)
			if ok then
				notify.player(player, Config.Donation.MSG_LINK_SUCCESS:format(saweriaName, robloxUsername), "SUCCESS")
				log:info("linkdonor berhasil", { by = player.Name, donor = saweriaName, roblox = robloxUsername })
			else
				notify.player(player, Config.Donation.MSG_SHEETS_ERROR .. " (" .. err .. ")", "ERROR")
			end
		end)
	end)
	-- /claimdonor <providerName> (owner only)
	commandExecutionService:registerRawHandler(Config.Donation.CMD_CLAIM_DONOR, function(player: Player, rawText: string)
		local args = splitArgs(rawText)
		if not isOwner(player) then
			notify.player(player, Config.Donation.MSG_LINK_NO_PERM, "ERROR")
			return
		end
		local saweriaName = args[1]
		if not saweriaName then
			notify.player(player, "[Donation] Try /claimdonor <" .. getProviderDonorLabel() .. ">.", "WARNING")
			return
		end
		task.spawn(function()
			local ok, reason = donationService:claimDonor(player, saweriaName)
			if ok then
				notify.player(player, Config.Donation.MSG_CLAIM_SUCCESS:format(saweriaName), "SUCCESS")
				log:info("claimdonor berhasil", { player = player.Name, donor = saweriaName })
			elseif reason == "rate_limited" then
				notify.player(player, Config.Donation.MSG_CLAIM_RATE_LIMIT, "WARNING")
			elseif reason == "already_assigned" then
				notify.player(player, Config.Donation.MSG_CLAIM_NOT_FOUND:format(saweriaName), "WARNING")
			else
				notify.player(player, Config.Donation.MSG_CLAIM_NOT_FOUND:format(saweriaName), "ERROR")
			end
		end)
	end)
	commandExecutionService:registerRawHandler(Config.Leaderboards.CMD_REFRESH, function(player: Player, rawText: string)
		local args = splitArgs(rawText)
		local refreshType = string.lower(args[1] or "")
		if not isOwner(player) then
			notify.player(player, Config.Leaderboards.MSG_REFRESH_NO_PERM, "ERROR")
			return
		end
		if refreshType == "" then
			notify.player(player, Config.Leaderboards.MSG_REFRESH_USAGE, "WARNING")
			return
		end
		local valid = refreshType == "robux"
			or refreshType == "community"
			or refreshType == "saweria"
			or refreshType == "bagibagi"
			or refreshType == "likes"
			or refreshType == "all"
			or refreshType == "audit"
		if not valid then
			notify.player(player, Config.Leaderboards.MSG_REFRESH_USAGE, "WARNING")
			return
		end

		if refreshType == "audit" then
			task.spawn(function()
				invalidateWorkspaceLeaderboardCache()
				local cold = LeaderboardScaleAudit.run(
					function()
						return buildWorkspaceLeaderboardPayload(true)
					end,
					paintWorkspaceLeaderboards
				)
				local warm = LeaderboardScaleAudit.run(function()
					return buildWorkspaceLeaderboardPayload(false)
				end)
				broadcastWorkspaceLeaderboards(true)
				local summary = table.concat({
					"[Leaderboard Audit]",
					"cold: " .. LeaderboardScaleAudit.formatSummary(cold),
					"warm: " .. LeaderboardScaleAudit.formatSummary(warm),
					"Tip: compare egress@ccu at 120 players before go-live.",
				}, "\n")
				notify.player(player, summary, "INFO")
				log:info("Leaderboard scale audit", { cold = cold, warm = warm })
			end)
			return
		end

		task.spawn(function()
			if refreshType == "saweria" or refreshType == "bagibagi" or refreshType == "all" then
				donationService:forceRefresh()
			end
			invalidateWorkspaceLeaderboardCache()
			broadcastWorkspaceLeaderboards(true)
			notify.player(player, Config.Leaderboards.MSG_REFRESH_OK:format(refreshType), "SUCCESS")
		end)
	end)

	local function applyShowcaseMode(enabled: boolean)
		if type(Config.Demo) ~= "table" then
			return
		end
		Config.Demo.ENABLED = enabled
		if demoProvider and type(demoProvider.reset) == "function" then
			demoProvider:reset()
		end
		demoProvider = nil
		invalidateWorkspaceLeaderboardCache()
		local ok, payloadOrErr = pcall(buildWorkspaceLeaderboardPayload, true)
		if not ok then
			log:warn("Showcase mode refresh failed", { enabled = enabled, error = tostring(payloadOrErr) })
			return
		end
		stampLeaderboardRevision(payloadOrErr)
		paintWorkspaceLeaderboards(payloadOrErr)
		broadcastWorkspaceLeaderboards(true)
	end

	commandExecutionService:registerRawHandler(Config.Leaderboards.CMD_SHOWCASE, function(player: Player, rawText: string)
		local args = splitArgs(rawText)
		local mode = string.lower(args[1] or "")
		if not isOwner(player) then
			notify.player(player, Config.Leaderboards.MSG_SHOWCASE_NO_PERM, "ERROR")
			return
		end
		if mode == "" or mode == "status" then
			local state = (Config.Demo and Config.Demo.ENABLED == true) and "ON" or "OFF"
			notify.player(player, Config.Leaderboards.MSG_SHOWCASE_STATUS:format(state), "INFO")
			return
		end
		if mode ~= "on" and mode ~= "off" then
			notify.player(player, Config.Leaderboards.MSG_SHOWCASE_USAGE, "WARNING")
			return
		end
		local enabled = mode == "on"
		task.spawn(function()
			applyShowcaseMode(enabled)
			notify.player(
				player,
				if enabled then Config.Leaderboards.MSG_SHOWCASE_ON else Config.Leaderboards.MSG_SHOWCASE_OFF,
				"SUCCESS"
			)
		end)
	end)
	-- /verifyspender (owner only): force-sync top 10 spender Saweria + Robux ke overhead.
	-- Alurnya: 1) force refresh leaderboard data dari sumber, 2) clear rank cache di
	-- OverheadService (hapus cache negatif yang sticky), 3) re-assign top 10 Saweria
	-- via DonationService, 4) refresh overhead semua online player biar Robux top 10
	-- yang nggak overlap ikut ke-resolve. 5) verify hasilnya dengan baca ulang stored
	-- data dan report ke owner.
	-- /dumpbagibagi (alias: /dumpsaweria) — top IDR leaderboard snapshot
	local function runDumpExternalLeaderboard(player: Player)
		local providerName = getExternalProviderName()
		local tag = "[Dump" .. providerName:gsub("[^%w]", "") .. "]"
		if not IS_STUDIO and not isOwner(player) then
			notify.player(player, tag .. " Owner-only command.", "ERROR")
			return
		end
		if not adminCommandLimiter:check(player.UserId) then
			notify.player(player, tag .. " Slow down, try again in a moment.", "WARNING")
			return
		end
		task.spawn(function()
			local entries = donationService:getWorkspaceSaweriaLeaderboard(
				Config.Leaderboards.SAWERIA_LIMIT
			)
			if type(entries) ~= "table" or #entries == 0 then
				notify.player(player, tag .. " Leaderboard kosong / belum ke-fetch.", "WARNING")
				return
			end
			notify.player(player, string.format("%s Top %d %s:", tag, #entries, providerName), "INFO")
			for _, entry in ipairs(entries) do
				local rank = tonumber(entry.rank) or 0
				local username = tostring(entry.username or entry.saweriaName or "?")
				local userId = tonumber(entry.userId) or 0
				local total = tonumber(entry.total) or 0
				local line = string.format(
					"[%d] %s (userId=%d, total=%d IDR)",
					rank,
					username,
					userId,
					total
				)
				notify.player(player, line, "INFO")
				print(tag .. " " .. line)
			end
			print(tag .. " Leaderboard di atas sudah termasuk manual IDR adjustment (kalau ada).")
			notify.player(
				player,
				tag .. " Detail di-print ke server Output (Studio).",
				"SUCCESS"
			)
			log:info("DumpExternalLeaderboard executed", {
				caller = player.Name,
				provider = providerName,
				count = #entries,
			})
		end)
	end
	commandExecutionService:registerRawHandler("dumpbagibagi", function(player: Player, _rawText: string)
		runDumpExternalLeaderboard(player)
	end)
	commandExecutionService:registerRawHandler("dumpsaweria", function(player: Player, _rawText: string)
		runDumpExternalLeaderboard(player)
	end)
	commandExecutionService:registerRawHandler("verifyspender", function(player: Player, _rawText: string)
		-- Studio mode: bypass owner check biar bisa di-test pas playtest tanpa harus pakai
		-- akun owner. Live game tetap owner-only.
		if not IS_STUDIO and not isOwner(player) then
			notify.player(player, "[VerifySpender] Owner-only command.", "ERROR")
			return
		end
		if IS_STUDIO and not isOwner(player) then
			log:warn("VerifySpender: Studio bypass aktif (non-owner caller)", { player = player.Name })
		end
		if not adminCommandLimiter:check(player.UserId) then
			notify.player(player, "[VerifySpender] Slow down, try again in a moment.", "WARNING")
			return
		end
		task.spawn(function()
			notify.player(player, "[VerifySpender] Starting sync...", "INFO")

			-- Step 1: force refresh leaderboard data dari Saweria + sheets
			local okRefresh = pcall(function()
				donationService:forceRefresh()
			end)
			if not okRefresh then
				log:warn("VerifySpender: forceRefresh failed", { player = player.Name })
			end

			-- Step 2: clear cache rank di OverheadService (hapus cache negatif yang sticky)
			if overheadService and type(overheadService.invalidateAllRankCaches) == "function" then
				overheadService:invalidateAllRankCaches()
			elseif overheadService and type(overheadService.invalidateRankCaches) == "function" then
				overheadService:invalidateRankCaches(nil)
			end

			-- Step 3: re-assign top 10 Saweria spender
			local report: any = nil
			if type(donationService.forceReassignTopSpenders) == "function" then
				report = donationService:forceReassignTopSpenders()
			end

			-- Step 4: refresh overhead semua online player (cover Robux top 10 juga)
			local Players = game:GetService("Players")
			for _, p in ipairs(Players:GetPlayers()) do
				if type(donationService.refreshPlayerOverhead) == "function" then
					donationService:refreshPlayerOverhead(p)
				end
			end

			-- Tunggu 1 detik biar refreshPlayer task.spawn beres dan stored data ter-update
			task.wait(1)

			-- Step 5: verify dengan baca stored data + workspace leaderboard
			local saweriaEntries = donationService:getWorkspaceSaweriaLeaderboard(
				Config.Leaderboards.SAWERIA_LIMIT
			)
			local robuxEntries = {}
			if leaderboardRepository then
				local robuxResult = leaderboardRepository:getRobuxLeaderboard(
					Config.Leaderboards.ROBUX_LIMIT
				)
				if robuxResult.ok then
					robuxEntries = robuxResult.value
				end
			end

			local saweriaOk, saweriaMissing = 0, {}
			for _, entry in ipairs(saweriaEntries) do
				local username = type(entry.username) == "string" and entry.username or ""
				local targetPlayer: Player? = nil
				for _, p in ipairs(Players:GetPlayers()) do
					if p.Name:lower() == username:lower() then
						targetPlayer = p
						break
					end
				end
				if targetPlayer then
					local stored = overheadService:getStored(targetPlayer.UserId)
					if stored.ok and stored.value.topSpenderRank == entry.rank then
						saweriaOk += 1
					else
						table.insert(saweriaMissing, string.format("#%d %s", entry.rank, username))
					end
				end
			end

			local robuxOk, robuxMissing = 0, {}
			for _, entry in ipairs(robuxEntries) do
				local entryUserId = tonumber(entry.userId)
				local targetPlayer: Player? = nil
				if entryUserId and entryUserId > 0 then
					targetPlayer = Players:GetPlayerByUserId(entryUserId)
				end
				if not targetPlayer and type(entry.username) == "string" then
					local lower = entry.username:lower()
					for _, p in ipairs(Players:GetPlayers()) do
						if p.Name:lower() == lower then
							targetPlayer = p
							break
						end
					end
				end
				if targetPlayer then
					local stored = overheadService:getStored(targetPlayer.UserId)
					if stored.ok and stored.value.topDonateRank == entry.rank then
						robuxOk += 1
					else
						table.insert(
							robuxMissing,
							string.format("#%d %s", entry.rank, tostring(entry.username or entry.userId))
						)
					end
				end
			end

			local providerName = getExternalProviderName()
			local summary = string.format(
				"[VerifySpender] %s: %d/%d online OK | Robux: %d/%d online OK",
				providerName,
				saweriaOk,
				saweriaOk + #saweriaMissing,
				robuxOk,
				robuxOk + #robuxMissing
			)
			notify.player(player, summary, if (#saweriaMissing + #robuxMissing) == 0 then "SUCCESS" else "WARNING")
			if #saweriaMissing > 0 then
				notify.player(
					player,
					"[VerifySpender] " .. providerName .. " mismatch: " .. table.concat(saweriaMissing, ", "),
					"WARNING"
				)
			end
			if #robuxMissing > 0 then
				notify.player(
					player,
					"[VerifySpender] Robux mismatch: " .. table.concat(robuxMissing, ", "),
					"WARNING"
				)
			end
			log:info("VerifySpender complete", {
				caller = player.Name,
				saweriaOk = saweriaOk,
				saweriaMissing = #saweriaMissing,
				robuxOk = robuxOk,
				robuxMissing = #robuxMissing,
				report = report,
			})
		end)
	end)
	local testDonateDeprecationWarned = false

	local function runTestCashDonation(player: Player, amount: number, labelPrefix: string)
		if not isCashDonationEnabled() then
			notify.player(player, string.format("[%s] Cash donation disabled in config.", labelPrefix), "WARNING")
			return
		end
		if not isAdmin(player) then
			notify.player(player, string.format("[%s] Admin/Staff-only command.", labelPrefix), "ERROR")
			return
		end
		local testCash = donationService.testCashDonation
		if type(testCash) ~= "function" then
			notify.player(player, string.format("[%s] Service tidak tersedia.", labelPrefix), "ERROR")
			return
		end
		task.spawn(function()
			local ok, err = testCash(
				donationService,
				player.UserId,
				player.Name,
				math.floor(amount),
				"[Test Donation]"
			)
			if not ok then
				notify.player(player, string.format("[%s] Gagal: %s", labelPrefix, err), "ERROR")
				return
			end
			local extra = if err ~= "" then (" (" .. err .. ")") else ""
			notify.player(
				player,
				string.format(
					"[%s] Kamu +%d IDR -> notif + aura + world VFX (preview only, tidak persist).%s",
					labelPrefix,
					math.floor(amount),
					extra
				),
				"SUCCESS"
			)
		end)
	end

	local function runTestRobuxDonation(player: Player, amount: number)
		if not isAdmin(player) then
			notify.player(player, "[TestRobux] Admin/Staff-only command.", "ERROR")
			return
		end
		local testRobux = donationService.testRobuxDonation
		if type(testRobux) ~= "function" then
			notify.player(player, "[TestRobux] Service tidak tersedia.", "ERROR")
			return
		end
		task.spawn(function()
			local ok, err = testRobux(
				donationService,
				player.UserId,
				player.Name,
				math.floor(amount),
				"[Test Robux Donation]"
			)
			if not ok then
				notify.player(player, string.format("[TestRobux] Gagal: %s", err), "ERROR")
				return
			end
			local extra = if err ~= "" then (" (" .. err .. ")") else ""
			notify.player(
				player,
				string.format(
					"[TestRobux] Kamu +%d Robux -> notif + aura saja (preview only, tidak persist).%s",
					math.floor(amount),
					extra
				),
				"SUCCESS"
			)
		end)
	end

	-- /testcash <idr amount> (admin): test IDR donation flow (aura + world VFX).
	commandExecutionService:registerRawHandler(Config.Donation.CMD_TEST_CASH, function(player: Player, rawText: string)
		local args = splitArgs(rawText)
		local amountStr = args[1]
		if not amountStr then
			notify.player(player, "[TestCash] Usage: /testcash <idr amount>", "WARNING")
			return
		end
		local amount = tonumber(amountStr)
		if not amount or amount <= 0 then
			notify.player(player, "[TestCash] Amount harus angka positif (IDR).", "WARNING")
			return
		end
		runTestCashDonation(player, amount, "TestCash")
	end)

	-- /testsaweria <idr amount> (admin): deprecated alias for /testcash.
	commandExecutionService:registerRawHandler("testsaweria", function(player: Player, rawText: string)
		local args = splitArgs(rawText)
		local amountStr = args[1]
		if not amountStr then
			notify.player(player, "[TestSaweria] Usage: /testsaweria <idr amount> (deprecated — use /testcash)", "WARNING")
			return
		end
		local amount = tonumber(amountStr)
		if not amount or amount <= 0 then
			notify.player(player, "[TestSaweria] Amount harus angka positif (IDR).", "WARNING")
			return
		end
		runTestCashDonation(player, amount, "TestSaweria")
	end)

	-- /testrobux <robux amount> (admin): test Robux donation flow (aura only, no world VFX).
	commandExecutionService:registerRawHandler("testrobux", function(player: Player, rawText: string)
		local args = splitArgs(rawText)
		local amountStr = args[1]
		if not amountStr then
			notify.player(player, "[TestRobux] Usage: /testrobux <robux amount>", "WARNING")
			return
		end
		local amount = tonumber(amountStr)
		if not amount or amount <= 0 then
			notify.player(player, "[TestRobux] Amount harus angka positif (Robux).", "WARNING")
			return
		end
		runTestRobuxDonation(player, amount)
	end)

	-- /testdonate <idr amount> (admin): deprecated alias for /testcash.
	commandExecutionService:registerRawHandler("testdonate", function(player: Player, rawText: string)
		if not testDonateDeprecationWarned then
			testDonateDeprecationWarned = true
			log:warn("/testdonate is deprecated; use /testcash instead")
		end
		local args = splitArgs(rawText)
		local amountStr = args[1]
		if not amountStr then
			notify.player(player, "[TestDonate] Usage: /testdonate <idr amount> (deprecated — use /testcash)", "WARNING")
			return
		end
		local amount = tonumber(amountStr)
		if not amount or amount <= 0 then
			notify.player(player, "[TestDonate] Amount harus angka positif (IDR).", "WARNING")
			return
		end
		runTestCashDonation(player, amount, "TestDonate")
	end)
	-- Manual donation value adjustments (owner-only, Studio bypass).
	-- Robux → DataStore OrderedDataStore; Bagi-Bagi → cache + overhead sync.
	local donationCfg = Config.Donation

	-- Returns: userId, resolvedName, isSelfAlias ("me" / "@me")
	local function resolveUserIdFromArg(arg: string, caller: Player?): (number?, string?, boolean)
		local lower = string.lower(arg)
		if lower == "me" or lower == "@me" then
			if caller then
				return caller.UserId, caller.Name, true
			end
			return nil, nil, true
		end
		local asNumber = tonumber(arg)
		if asNumber and asNumber > 0 then
			return asNumber, nil, false
		end
		for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
			if p.Name:lower() == lower then
				return p.UserId, p.Name, false
			end
		end
		local ok, result = pcall(function()
			return game:GetService("Players"):GetUserIdFromNameAsync(arg)
		end)
		if ok and type(result) == "number" and result > 0 then
			return result, arg, false
		end
		return nil, nil, false
	end

	local function requireStudioForSelfAlias(player: Player, label: string, isSelfAlias: boolean): boolean
		if not isSelfAlias then
			return true
		end
		if IS_STUDIO then
			return true
		end
		notify.player(
			player,
			string.format(
				"[%s] `me` is Studio-only. Use /%s me in Studio Play to clear your own donation data.",
				label,
				label:lower()
			),
			"ERROR"
		)
		return false
	end

	local function refreshUserIfOnline(userId: number)
		if overheadService and type(overheadService.invalidateRankCaches) == "function" then
			overheadService:invalidateRankCaches(userId)
		end
		if donationService and type(donationService.invalidateDonorProfileCache) == "function" then
			donationService:invalidateDonorProfileCache(userId)
		end
		local target = game:GetService("Players"):GetPlayerByUserId(userId)
		if target and type(donationService.refreshPlayerOverhead) == "function" then
			donationService:refreshPlayerOverhead(target)
		end
	end

	local function requireOwnerOrStudio(player: Player, label: string): boolean
		if IS_STUDIO or isOwner(player) then
			return true
		end
		notify.player(player, ("[%s] Owner-only command."):format(label), "ERROR")
		return false
	end

	local function registerOwnerManualCommands(aliases: { string }, handler: (Player, string) -> ())
		for _, alias in ipairs(aliases) do
			if type(alias) == "string" and alias ~= "" then
				commandExecutionService:registerRawHandler(alias, function(player: Player, rawText: string)
					if not requireOwnerOrStudio(player, alias) then
						return
					end
					handler(player, rawText)
				end)
			end
		end
	end

	local function collectCommandAliases(primary: string, ...: string): { string }
		local seen = {} :: { [string]: boolean }
		local ordered = {} :: { string }
		local function add(name: string?)
			if type(name) ~= "string" or name == "" or seen[name] then
				return
			end
			seen[name] = true
			table.insert(ordered, name)
		end
		add(primary)
		for i = 1, select("#", ...) do
			add(select(i, ...))
		end
		local legacy = donationCfg.CMD_LEGACY_ALIASES
		if type(legacy) == "table" then
			for alias, canonical in pairs(legacy) do
				if canonical == primary then
					add(alias)
				end
			end
		end
		return ordered
	end

	local function listManualValueMap(player: Player, label: string, manualMap: { [number]: number }?, unit: string)
		if type(manualMap) ~= "table" then
			notify.player(player, string.format("[%s] Manual list tidak tersedia.", label), "ERROR")
			return
		end
		local sorted: { { userId: number, amount: number } } = {}
		for userId, amount in pairs(manualMap) do
			table.insert(sorted, { userId = userId, amount = math.floor(tonumber(amount) or 0) })
		end
		if #sorted == 0 then
			notify.player(player, string.format("[%s] Manual adjustment kosong.", label), "INFO")
			return
		end
		table.sort(sorted, function(a, b)
			return a.amount > b.amount
		end)
		notify.player(player, string.format("[%s] %d entry:", label, #sorted), "INFO")
		for _, item in ipairs(sorted) do
			local onlinePlayer = Players:GetPlayerByUserId(item.userId)
			local nameLabel = onlinePlayer and onlinePlayer.Name or ("userId=" .. tostring(item.userId))
			local status = onlinePlayer and " [online]" or ""
			notify.player(
				player,
				string.format("%s%s → %d %s", nameLabel, status, item.amount, unit),
				"INFO"
			)
		end
	end

	local function runAddRobux(player: Player, rawText: string, label: string)
		local args = splitArgs(rawText)
		local target = args[1]
		local amountStr = args[2]
		if not target or not amountStr then
			notify.player(
				player,
				string.format("[%s] Usage: /%s <username|userId> <robux amount>", label, label:lower()),
				"WARNING"
			)
			return
		end
		local amount = tonumber(amountStr)
		if not amount or amount <= 0 then
			notify.player(player, string.format("[%s] Amount harus angka positif (Robux).", label), "WARNING")
			return
		end
		task.spawn(function()
			local userId, resolvedName = resolveUserIdFromArg(target, player)
			if not userId then
				notify.player(player, string.format("[%s] Player '%s' nggak ketemu.", label, target), "ERROR")
				return
			end
			if type(donationService.addManualRobuxAdjustment) ~= "function" then
				notify.player(player, string.format("[%s] Service tidak tersedia.", label), "ERROR")
				return
			end
			local ok, err = donationService:addManualRobuxAdjustment(userId, resolvedName, resolvedName, math.floor(amount))
			if not ok then
				notify.player(player, string.format("[%s] Gagal: %s", label, err), "ERROR")
				return
			end
			refreshUserIfOnline(userId)
			invalidateWorkspaceLeaderboardCache()
			broadcastWorkspaceLeaderboards(true)
			notify.player(
				player,
				string.format(
					"[%s] %s +%d Robux → leaderboard DataStore di-update.",
					label,
					resolvedName or tostring(userId),
					math.floor(amount)
				),
				"SUCCESS"
			)
		end)
	end

	local function runRemoveRobux(player: Player, rawText: string, label: string)
		local args = splitArgs(rawText)
		local target = args[1]
		local amountStr = args[2]
		if not target then
			notify.player(
				player,
				string.format(
					"[%s] Usage: /%s <username|userId|me> [robux amount] — `me` = clear self (Studio only)",
					label,
					label:lower()
				),
				"WARNING"
			)
			return
		end
		task.spawn(function()
			local userId, resolvedName, isSelfAlias = resolveUserIdFromArg(target, player)
			if not requireStudioForSelfAlias(player, label, isSelfAlias) then
				return
			end
			if not userId then
				notify.player(player, string.format("[%s] Player '%s' nggak ketemu.", label, target), "ERROR")
				return
			end
			if type(donationService.removeManualRobuxAdjustment) ~= "function" then
				notify.player(player, string.format("[%s] Service tidak tersedia.", label), "ERROR")
				return
			end
			-- `me` without amount → wipe full Robux LB total for caller
			local amount = if isSelfAlias and (amountStr == nil or amountStr == "") then nil else tonumber(amountStr)
			local ok, err = donationService:removeManualRobuxAdjustment(userId, amount)
			if not ok then
				notify.player(player, string.format("[%s] Gagal: %s", label, err), "ERROR")
				return
			end
			refreshUserIfOnline(userId)
			invalidateWorkspaceLeaderboardCache()
			broadcastWorkspaceLeaderboards(true)
			notify.player(
				player,
				string.format(
					"[%s] %s Robux leaderboard %s.",
					label,
					resolvedName or tostring(userId),
					if isSelfAlias and amount == nil then "cleared (self)" else "dikurangi"
				),
				"SUCCESS"
			)
		end)
	end

	local function runDonateCash(player: Player, rawText: string, label: string)
		if not isCashDonationEnabled() then
			notify.player(player, string.format("[%s] Cash donation disabled in config.", label), "WARNING")
			return
		end
		local args = splitArgs(rawText)
		local target = args[1]
		local amountStr = args[2]
		if not target or not amountStr then
			notify.player(
				player,
				string.format(
					"[%s] Usage: /%s <username|userId> <idr amount> [optional message]",
					label,
					label:lower()
				),
				"WARNING"
			)
			return
		end
		local amount = tonumber(amountStr)
		if not amount or amount <= 0 then
			notify.player(player, string.format("[%s] Amount harus angka positif (IDR).", label), "WARNING")
			return
		end
		local messageParts = {}
		for i = 3, #args do
			table.insert(messageParts, args[i])
		end
		local message = if #messageParts > 0 then table.concat(messageParts, " ") else nil
		task.spawn(function()
			local userId, resolvedName = resolveUserIdFromArg(target, player)
			if not userId then
				notify.player(player, string.format("[%s] Player '%s' nggak ketemu.", label, target), "ERROR")
				return
			end
			local donateManual = donationService.donateCashManual or donationService.donateBagibagiManual
			if type(donateManual) ~= "function" then
				notify.player(player, string.format("[%s] Service tidak tersedia.", label), "ERROR")
				return
			end
			local ok, err, totalAdj = donateManual(
				donationService,
				userId,
				resolvedName,
				math.floor(amount),
				message
			)
			if not ok then
				notify.player(player, string.format("[%s] Gagal: %s", label, err), "ERROR")
				return
			end
			if overheadService and type(overheadService.invalidateRankCaches) == "function" then
				overheadService:invalidateRankCaches(userId)
			end
			refreshUserIfOnline(userId)
			invalidateWorkspaceLeaderboardCache()
			broadcastWorkspaceLeaderboards(true)
			local extra = if err ~= "" then (" (" .. err .. ")") else ""
			notify.player(
				player,
				string.format(
					"[%s] %s +%d IDR → notif + efek donasi (manual total=%d).%s",
					label,
					resolvedName or tostring(userId),
					math.floor(amount),
					totalAdj or 0,
					extra
				),
				"SUCCESS"
			)
		end)
	end

	local function runAddCash(player: Player, rawText: string, label: string)
		if not isCashDonationEnabled() then
			notify.player(player, string.format("[%s] Cash donation disabled in config.", label), "WARNING")
			return
		end
		local args = splitArgs(rawText)
		local target = args[1]
		local amountStr = args[2]
		if not target or not amountStr then
			notify.player(
				player,
				string.format("[%s] Usage: /%s <username|userId> <idr amount>", label, label:lower()),
				"WARNING"
			)
			return
		end
		local amount = tonumber(amountStr)
		if not amount or amount <= 0 then
			notify.player(player, string.format("[%s] Amount harus angka positif (IDR).", label), "WARNING")
			return
		end
		task.spawn(function()
			local userId, resolvedName = resolveUserIdFromArg(target, player)
			if not userId then
				notify.player(player, string.format("[%s] Player '%s' nggak ketemu.", label, target), "ERROR")
				return
			end
			local addManual = donationService.addManualCashAdjustment or donationService.addManualBagibagiAdjustment
			if type(addManual) ~= "function" then
				notify.player(player, string.format("[%s] Service tidak tersedia.", label), "ERROR")
				return
			end
			local ok, err, totalAdj = addManual(
				donationService,
				userId,
				resolvedName,
				math.floor(amount)
			)
			if not ok then
				notify.player(player, string.format("[%s] Gagal: %s", label, err), "ERROR")
				return
			end
			if overheadService and type(overheadService.invalidateRankCaches) == "function" then
				overheadService:invalidateRankCaches(userId)
			end
			refreshUserIfOnline(userId)
			invalidateWorkspaceLeaderboardCache()
			broadcastWorkspaceLeaderboards(true)
			notify.player(
				player,
				string.format(
					"[%s] %s +%d IDR (manual total=%d) → leaderboard & overhead sync.",
					label,
					resolvedName or tostring(userId),
					math.floor(amount),
					totalAdj or 0
				),
				"SUCCESS"
			)
		end)
	end

	local function runRemoveCash(player: Player, rawText: string, label: string)
		if not isCashDonationEnabled() then
			notify.player(player, string.format("[%s] Cash donation disabled in config.", label), "WARNING")
			return
		end
		local args = splitArgs(rawText)
		local target = args[1]
		local amountStr = args[2]
		if not target then
			notify.player(
				player,
				string.format(
					"[%s] Usage: /%s <username|userId|me> [idr amount] — `me` = clear self (Studio only)",
					label,
					label:lower()
				),
				"WARNING"
			)
			return
		end
		task.spawn(function()
			local userId, resolvedName, isSelfAlias = resolveUserIdFromArg(target, player)
			if not requireStudioForSelfAlias(player, label, isSelfAlias) then
				return
			end
			if not userId then
				notify.player(player, string.format("[%s] Player '%s' nggak ketemu.", label, target), "ERROR")
				return
			end
			local removeManual = donationService.removeManualCashAdjustment or donationService.removeManualBagibagiAdjustment
			if type(removeManual) ~= "function" then
				notify.player(player, string.format("[%s] Service tidak tersedia.", label), "ERROR")
				return
			end
			-- `me` without amount → wipe all manual cash adjustment for caller
			local amount = if isSelfAlias and (amountStr == nil or amountStr == "") then nil else tonumber(amountStr)
			local ok, err, remaining = removeManual(donationService, userId, amount)
			if not ok then
				notify.player(player, string.format("[%s] Gagal: %s", label, err), "ERROR")
				return
			end
			refreshUserIfOnline(userId)
			invalidateWorkspaceLeaderboardCache()
			broadcastWorkspaceLeaderboards(true)
			notify.player(
				player,
				string.format(
					"[%s] %s adjustment sekarang %d IDR%s.",
					label,
					resolvedName or tostring(userId),
					remaining or 0,
					if isSelfAlias and amount == nil then " (cleared self)" else ""
				),
				"SUCCESS"
			)
		end)
	end

	registerOwnerManualCommands(collectCommandAliases(donationCfg.CMD_ADD_ROBUX), function(player: Player, rawText: string)
		runAddRobux(player, rawText, "SetRobux")
	end)

	registerOwnerManualCommands({ donationCfg.CMD_REMOVE_ROBUX }, function(player: Player, rawText: string)
		runRemoveRobux(player, rawText, "RemoveRobux")
	end)

	registerOwnerManualCommands(collectCommandAliases(donationCfg.CMD_DONATE_CASH), function(player: Player, rawText: string)
		runDonateCash(player, rawText, "DonateCash")
	end)

	registerOwnerManualCommands(collectCommandAliases(donationCfg.CMD_ADD_CASH), function(player: Player, rawText: string)
		runAddCash(player, rawText, "AddCash")
	end)

	registerOwnerManualCommands(collectCommandAliases(donationCfg.CMD_REMOVE_CASH), function(player: Player, rawText: string)
		runRemoveCash(player, rawText, "RemoveCash")
	end)

	registerOwnerManualCommands({ donationCfg.CMD_LIST_BAGIBAGI }, function(player: Player, _rawText: string)
		listManualValueMap(player, "ListBagibagi", donationCfg.MANUAL_BAGIBAGI_ADJUSTMENTS, "IDR")
	end)

	registerOwnerManualCommands({ donationCfg.CMD_LIST_ROBUX }, function(player: Player, _rawText: string)
		listManualValueMap(player, "ListRobux", donationCfg.MANUAL_ROBUX_ADJUSTMENTS, "Robux")
	end)

	-- Admin force refresh remote handler.
	-- Five-gate pattern: envelope, size, rate, idempotency, authorization.
	adminCommandRemote.OnServerEvent:Connect(function(player: Player, raw: any)
		if type(raw) ~= "table" then return end
		if type(raw.requestId) ~= "string" or #raw.requestId < 8 then
			log:warn("Admin command rejected: missing requestId", { player = player.Name })
			return
		end
		if raw.action ~= "force_refresh" then return end

		if not Validator.checkSize(raw) then
			log:warn("Admin command rejected: payload too large", { player = player.Name })
			return
		end

		if not adminCommandLimiter:check(player.UserId) then
			log:warn("Admin command rate limited", { player = player.Name })
			notify.player(player, "[Donation] Too many refresh requests. Wait a moment.", "WARNING")
			return
		end

		if processedAdminCommands:contains(raw.requestId) then
			notify.player(player, "[Donation] Leaderboard refresh already in progress.", "INFO")
			return
		end
		processedAdminCommands:add(raw.requestId)

		if not isAdmin(player) then
			notify.player(player, Config.Donation.MSG_LINK_NO_PERM, "ERROR")
			return
		end

		task.spawn(function()
			donationService:forceRefresh()
			invalidateWorkspaceLeaderboardCache()
			broadcastWorkspaceLeaderboards(true)
			notify.player(player, "[Donation] Leaderboard di-refresh manual.", "SUCCESS")
		end)
	end)
	if deps.workspaceLeaderboardRefresh then
		deps.workspaceLeaderboardRefresh.refresh = function()
			invalidateWorkspaceLeaderboardCache()
			broadcastWorkspaceLeaderboards(true)
		end
	end

	local donorProfileRemote = remotesFolder:FindFirstChild(Config.Donation.REMOTE_DONOR_PROFILE)
		or remotesFolder:WaitForChild(Config.Donation.REMOTE_DONOR_PROFILE, 10)
	local donorProfileResponseRemote = remotesFolder:FindFirstChild(Config.Donation.REMOTE_DONOR_PROFILE_RESPONSE)
		or remotesFolder:WaitForChild(Config.Donation.REMOTE_DONOR_PROFILE_RESPONSE, 10)
	local donorProfileLimiter = RateLimiter.new(12, 15)

	if donorProfileResponseRemote and donorProfileResponseRemote:IsA("RemoteEvent") then
		donorProfileNetwork = NetworkManager.create({
			reliable = donorProfileResponseRemote :: RemoteEvent,
			logger = log,
			isServer = true,
		})
	end

	local function fireDonorProfileResponse(
		player: Player,
		requestId: string,
		ok: boolean,
		profile: any?,
		errorCode: string?
	)
		if not donorProfileNetwork then
			return
		end
		donorProfileNetwork:fireClient(player, {
			type = "donor_profile_response",
			requestId = requestId,
			ok = ok,
			profile = profile,
			error = errorCode,
		})
	end

	if donorProfileRemote and donorProfileRemote:IsA("RemoteEvent")
		and donorProfileResponseRemote and donorProfileResponseRemote:IsA("RemoteEvent")
	then
		donorProfileRemote.OnServerEvent:Connect(function(player: Player, raw: any)
			if type(raw) ~= "table" or raw.type ~= "donor_profile_request" then
				return
			end
			if type(raw.requestId) ~= "string" or #raw.requestId < 8 then
				return
			end
			if not Validator.checkSize(raw) then
				fireDonorProfileResponse(player, raw.requestId, false, nil, "invalid_request")
				return
			end
			if not donorProfileLimiter:check(player.UserId) then
				fireDonorProfileResponse(player, raw.requestId, false, nil, "rate_limited")
				return
			end
			if type(donationService.getDonorProfile) ~= "function" then
				fireDonorProfileResponse(player, raw.requestId, false, nil, "service_unavailable")
				return
			end

			local requestId = raw.requestId
			task.spawn(function()
				local ok, profileOrErr = pcall(function()
					return donationService:getDonorProfile(player)
				end)
				if not ok then
					log:warn("Donor profile build failed", {
						player = player.Name,
						error = tostring(profileOrErr),
					})
					fireDonorProfileResponse(player, requestId, false, nil, "build_failed")
					return
				end
				fireDonorProfileResponse(player, requestId, true, profileOrErr, nil)
			end)
		end)
	end

	log:info("DonationController initialized")
	return {}
end
return createDonationController
