--!strict
-- Server/Controllers/AdminController.lua
-- Handles: AdminSetTitle, AdminSendGiftcard, AdminResetTitle remotes.
-- Access: canGift only (Owner/CoOwner/Admin).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local Config            = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types              = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local OverheadDomain     = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local PermissionDomain   = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.PermissionDomain)
local TitleStyleDomain   = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.TitleStyleDomain)
local TitleFontUtil      = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.TitleFontUtil)
local TitleColorPreset    = require(ReplicatedStorage.Hazastudio_ClubKit.OverheadEffects.TitleColorPreset)
local AnimationModes     = TitleColorPreset.AnimationModes
local ShopDomain         = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.ShopDomain)
local RateLimiter        = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local Logger             = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local NetworkManager     = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkManager)
local Validator          = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Validator)
local MembershipCommandService = require(script.Parent.Parent.Services.MembershipCommandService)
local PlayerLookupService = require(script.Parent.Parent.Services.PlayerLookupService)
type IOverheadRepository = Types.IOverheadRepository
type MembershipTier = Types.MembershipTier
type INotify = {
	player: (Player, string, string?) -> (),
}
type IMembershipCommandService = MembershipCommandService.IMembershipCommandService
type IPlayerLookupService = PlayerLookupService.IPlayerLookupService
local function createAdminController(deps: {
	repo                    : IOverheadRepository,
	overheadService         : any,
	overheadController      : any,
	grantRemote             : RemoteEvent,
	notify                  : INotify,
	remotes                 : Folder,
	membershipCommandService: IMembershipCommandService,
	playerLookupService     : IPlayerLookupService,
	profileMenuSync         : { syncPlayer: ((Player) -> ())? }?,
})
	local repo                    = deps.repo
	local overheadService         = deps.overheadService
	local overheadController      = deps.overheadController
	local grantRemote             = deps.grantRemote
	local notify                  = deps.notify
	local remotesFolder           = deps.remotes
	local membershipCommandService = deps.membershipCommandService
	local playerLookupService     = deps.playerLookupService
	local profileMenuSync         = deps.profileMenuSync

	-- Live-refresh the target's profile menu (if online) after an overhead-backed
	-- profile field (specialTitle) changes, so an open profile panel updates
	-- without requiring a rejoin/server restart.
	local function refreshProfileMenu(userId: number)
		if not profileMenuSync or not profileMenuSync.syncPlayer then
			return
		end
		local onlineTarget = Players:GetPlayerByUserId(userId)
		if onlineTarget then
			profileMenuSync.syncPlayer(onlineTarget)
		end
	end
	local log                     = Logger.new("AdminController")
	local limiter                 = RateLimiter.new(Config.Admin.RATE_MAX, Config.Admin.RATE_WINDOW)
	-- NetworkManager batches per-Heartbeat. Admin flows fire result + grant
	-- in the same frame on success; batching coalesces them onto one wire flush.
	local grantNetwork = NetworkManager.create({
		reliable = grantRemote,
		logger = log,
		isServer = true,
	})
	-- ============================================================
	-- Helpers
	-- ============================================================
	local function isAdmin(player: Player): boolean
		if PermissionDomain.isAdminUser(player.UserId) then
			return true
		end
		if overheadService and type(overheadService.getEffectivePayload) == "function" then
			local payloadResult = overheadService:getEffectivePayload(player)
			if payloadResult.ok then
				return PermissionDomain.canUseAdminPanel(payloadResult.value.role, player.UserId)
			end
		end
		return PermissionDomain.canUseAdminPanel(overheadService:getRawGroupRole(player), player.UserId)
	end
	local function checkRate(player: Player): boolean
		local allowed = limiter:check(player.UserId)
		return allowed
	end
	local function rememberRequest(cache: {[string]: number}, requestId: string): boolean
		-- TTL-based cleanup
		local now = os.clock()
		for key, expiresAt in pairs(cache) do
			if expiresAt <= now then
				cache[key] = nil
			end
		end
		if cache[requestId] then
			return false
		end
		cache[requestId] = now + Config.Security.REQUEST_DEDUPE_WINDOW
		return true
	end
	local function getOrCreateRemote(name: string): RemoteEvent
		local existing = remotesFolder:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotesFolder
		return remote
	end
	-- ============================================================
	-- Remote: AdminSetTitle
	-- Payload: { targetUsername, title, titleSize, presetMode, titleFont, requestId }
	-- Legacy: titleStyle still accepted for old clients; new admin sends presetMode only.
	-- ============================================================
	local SetTitleRemote = getOrCreateRemote(Config.Admin.REMOTE_SET_TITLE)
	local processedSetTitle: {[string]: number} = {}
	SetTitleRemote.OnServerEvent:Connect(function(player: Player, data: any)
		local sizeOk = Validator.checkSize(data)
		if not sizeOk then return end
		local validation = Validator.adminSetTitleByUsername(data)
		if not validation.valid then return end
		local requestId  = data.requestId :: string
		local targetUser = data.targetUsername :: string
		local title      = data.title :: string
		local titleSize  = data.titleSize :: string
		local presetMode = if type(data.presetMode) == "string" then data.presetMode else nil
		local titleFont = if type(data.titleFont) == "string" then data.titleFont else nil
		local titleStyle = data.titleStyle
		-- Auth dan rate limit SEBELUM idempotency
		if not isAdmin(player) then
			notify.player(player, Config.Admin.MSG_TITLE_INVALID_STYLE, "ERROR")
			return
		end
		if not checkRate(player) then
			notify.player(player, Config.Admin.MSG_GIFT_RATE_LIMIT, "WARNING")
			return
		end
		if not rememberRequest(processedSetTitle, requestId) then return end
		if #title == 0 then
			notify.player(player, Config.Admin.MSG_TITLE_EMPTY, "ERROR")
			return
		end
		if #title > Config.Admin.TITLE_MAX_LENGTH then
			notify.player(player, Config.Admin.MSG_TITLE_TOO_LONG, "ERROR")
			return
		end
		if not TitleStyleDomain.isValidTitleSize(titleSize) then
			notify.player(player, Config.Admin.MSG_TITLE_INVALID_SIZE, "ERROR")
			return
		end
		local usePreset = type(presetMode) == "string" and presetMode ~= ""
		if usePreset and not AnimationModes.IsPreset(presetMode :: string) then
			notify.player(player, Config.Admin.MSG_TITLE_INVALID_STYLE, "ERROR")
			return
		end
		local sanitizedStyle = if usePreset then nil else TitleStyleDomain.sanitizeStyle(titleStyle)
		if not usePreset and not sanitizedStyle then
			notify.player(player, Config.Admin.MSG_TITLE_INVALID_STYLE, "ERROR")
			return
		end
		if type(titleFont) == "string" and titleFont ~= "" then
			if not TitleFontUtil.isValidName(titleFont) then
				notify.player(player, Config.Admin.MSG_TITLE_INVALID_STYLE, "ERROR")
				return
			end
		else
			titleFont = nil
		end
		local lookupResult = playerLookupService:resolve(targetUser)
		if not lookupResult.ok then
			notify.player(player, Config.Admin.MSG_TITLE_NOT_FOUND:format(targetUser), "ERROR")
			return
		end
		local target = lookupResult.value
		local updatedResult = repo:update(target.UserId, function(current)
			return OverheadDomain.mergeStored(current, {
			specialTitle       = title,
			specialTitlePreset = if usePreset then presetMode else OverheadDomain.NIL,
			specialTitleSize   = titleSize,
			specialTitleFont   = titleFont,
			specialTitleStyle  = if usePreset then OverheadDomain.NIL else sanitizedStyle,
			specialTitlePosition = Config.Admin.DEFAULT_SPECIAL_TITLE_POSITION or "Top",
			specialSubRole = OverheadDomain.NIL,
			-- Ensure custom title is visible in Overhead v3 even if the player
			-- previously hid the SpecialTitle layer from settings.
			publicOverheadLayerVisible = (function()
				local base = type(current.publicOverheadLayerVisible) == "table"
					and table.clone(current.publicOverheadLayerVisible)
					or {}
				base.SpecialTitle = true
				return base
			end)(),
		})
		end)
		if not updatedResult.ok then
			notify.player(player, Config.Admin.MSG_TITLE_SAVE_FAILED, "ERROR")
			return
		end
		overheadController:refreshPlayer(target)
		refreshProfileMenu(target.UserId)
		notify.player(player, Config.Admin.MSG_TITLE_SUCCESS:format(target.DisplayName), "SUCCESS")
		log:info("Set title", {
			by     = player.Name,
			target = target.Name,
			title  = title,
			size   = titleSize,
			preset = if usePreset then presetMode else nil,
			family = if sanitizedStyle then sanitizedStyle.family else nil,
		})
	end)
	-- ============================================================
	-- Remote: AdminSendGiftcard
	-- Payload: { targetUsername, tier, requestId }
	-- Result fires AdminGiftcardResult -> Client
	-- ============================================================
	local SendGiftcardRemote   = getOrCreateRemote(Config.Admin.REMOTE_SEND_GIFTCARD)
	local GiftcardResultRemote = getOrCreateRemote(Config.Admin.REMOTE_GIFTCARD_RESULT)
	local resultNetwork = NetworkManager.create({
		reliable = GiftcardResultRemote,
		logger = log,
		isServer = true,
	})
	local processedGiftcard: {[string]: number} = {}
	SendGiftcardRemote.OnServerEvent:Connect(function(player: Player, data: any)
		local sizeOk = Validator.checkSize(data)
		if not sizeOk then return end
		local validation = Validator.adminSendGiftcardByUsername(data)
		if not validation.valid then return end
		local requestId  = data.requestId :: string
		local targetUser = data.targetUsername :: string
		local parsedTier = if type(data.tier) == "string" then ShopDomain.parseShopTier(data.tier) else nil
		local tier: MembershipTier? = if parsedTier then ((parsedTier :: any) :: MembershipTier) else nil
		if not isAdmin(player) then
			resultNetwork:fireClient(player, { success = false, error = "no_permission", requestId = requestId })
			return
		end
		if not checkRate(player) then
			resultNetwork:fireClient(player, { success = false, error = "rate_limited", requestId = requestId })
			return
		end
		if not tier then
			resultNetwork:fireClient(player, { success = false, error = "invalid_tier", requestId = requestId })
			return
		end
		local resolvedTier = (tier :: any) :: MembershipTier
		if not rememberRequest(processedGiftcard, requestId) then
			-- Idempotent: sudah diproses sebelumnya, kirim success agar client tidak retry
			resultNetwork:fireClient(player, { success = true, tier = resolvedTier, requestId = requestId })
			return
		end
		local lookupResult = playerLookupService:resolve(targetUser)
		if not lookupResult.ok then
			resultNetwork:fireClient(player, { success = false, error = "not_found", requestId = requestId })
			return
		end
		local target = lookupResult.value
		local grantResult = (membershipCommandService :: any):grantMembership(player, target, resolvedTier)
		if not grantResult.ok then
			local errorMsg = grantResult.error
			if errorMsg:find("sudah punya") or errorMsg:find("already has") then
				local _tierLabel = (OverheadDomain.getMembershipChatLabel :: any)(resolvedTier)
				resultNetwork:fireClient(player, { success = false, error = "already_has_tier", requestId = requestId })
			else
				resultNetwork:fireClient(player, { success = false, error = "save_failed", requestId = requestId })
			end
			log:warn("Gift failed", { by = player.Name, target = target.Name, tier = resolvedTier, error = errorMsg })
			return
		end
		local giftSuccess = grantResult.value
		local tierLabel   = (OverheadDomain.getMembershipChatLabel :: any)(resolvedTier)
		overheadController:refreshPlayer(target)
		-- Notif ke giftee via ShopGrantNotif
		grantNetwork:fireClient(target, {
			tier     = resolvedTier,
			isGift   = true,
			fromName = player.DisplayName,
		})
		-- Result ke admin (untuk FSM client + routing di AdminService)
		resultNetwork:fireClient(player, {
			success    = true,
			tier       = tier,
			tierLabel  = tierLabel,
			targetName = target.DisplayName,
			requestId  = requestId,
		})
		log:info("Send giftcard", {
			by                  = player.Name,
			target              = target.Name,
			tier                = tier,
			effectiveMembership = giftSuccess.effectiveMembership,
		})
	end)
	-- ============================================================
	-- Remote: AdminResetTitle
	-- ============================================================
	local ResetTitleRemote     = getOrCreateRemote(Config.Admin.REMOTE_RESET_TITLE)
	local processedResetTitle: {[string]: number} = {}
	ResetTitleRemote.OnServerEvent:Connect(function(player: Player, data: any)
		local sizeOk = Validator.checkSize(data)
		if not sizeOk then return end
		local validation = Validator.adminResetTitle(data)
		if not validation.valid then return end
		local requestId  = data.requestId :: string
		local targetUser = data.targetUsername :: string
		-- Auth dan rate limit SEBELUM idempotency
		if not isAdmin(player) then return end
		if not checkRate(player) then return end
		if not rememberRequest(processedResetTitle, requestId) then return end
		local lookupResult = playerLookupService:resolve(targetUser)
		if not lookupResult.ok then
			notify.player(player, Config.Admin.MSG_TITLE_RESET_NOT_FOUND:format(targetUser), "ERROR")
			return
		end
		local target = lookupResult.value
		local updatedResult = repo:update(target.UserId, function(current)
			return OverheadDomain.mergeStored(current, {
				specialTitle       = OverheadDomain.NIL,
				specialTitlePreset = OverheadDomain.NIL,
				specialTitleSize   = OverheadDomain.NIL,
				specialTitleFont   = OverheadDomain.NIL,
				specialTitleStyle  = OverheadDomain.NIL,
				specialSubRole     = OverheadDomain.NIL,
			})
		end)
		if not updatedResult.ok then
			notify.player(player, Config.Admin.MSG_TITLE_SAVE_FAILED, "ERROR")
			return
		end
		overheadController:refreshPlayer(target)
		refreshProfileMenu(target.UserId)
		notify.player(player, Config.Admin.MSG_TITLE_RESET_SUCCESS:format(target.DisplayName), "SUCCESS")
		log:info("Reset title", { by = player.Name, target = target.Name })
	end)
	log:info("AdminController initialized")
	return {}
end
return createAdminController
