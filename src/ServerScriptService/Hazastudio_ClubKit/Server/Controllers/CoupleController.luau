--!strict
-- PATH: ServerScriptService/Server/Controllers/CoupleController.lua
-- Handle RemoteEvents untuk couple system.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config      = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types       = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local Logger      = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local NetworkManager = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkManager)
local Validator   = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Validator)
type CoupleRequestPayload  = Types.CoupleRequestPayload
type CoupleResponsePayload = Types.CoupleResponsePayload
type INotify = {
	player: (Player, string, string?) -> (),
	all: (string, string?) -> (),
}
local function createCoupleController(deps: {
	coupleService      : any,
	overheadController : any,
	repo               : any,
	notify             : INotify,
	remotes            : Folder,   -- injected dari Main.server.lua
})
	local coupleService      = deps.coupleService
	local overheadController = deps.overheadController
	local repo               = deps.repo
	local notify             = deps.notify
	local remotesFolder      = deps.remotes
	local log                = Logger.new("CoupleController")
	local sendLimiter        = RateLimiter.new(Config.Couple.RATE_MAX, Config.Couple.RATE_WINDOW)
	local openLimiter        = RateLimiter.new(Config.Couple.RATE_MAX, Config.Couple.RATE_WINDOW)
	local respondLimiter     = RateLimiter.new(Config.Couple.RATE_MAX, Config.Couple.RATE_WINDOW)
	local breakupLimiter     = RateLimiter.new(Config.Couple.RATE_MAX, Config.Couple.RATE_WINDOW)
	-- TTL-based request dedup (nilai = expiry timestamp, bukan boolean)
	local processedReqs: {[string]: number} = {}
	local function rememberRequest(requestId: string): boolean
		-- Cleanup expired entries - cegah wipe-all yang merusak idempotency
		local now = os.clock()
		for key, expiresAt in pairs(processedReqs) do
			if expiresAt <= now then
				processedReqs[key] = nil
			end
		end
		if processedReqs[requestId] then
			return false
		end
		processedReqs[requestId] = now + Config.Security.REQUEST_DEDUPE_WINDOW
		return true
	end
	-- ============================================================
	-- Setup Remotes - dari injected folder, bukan WaitForChild
	-- ============================================================
	local function getOrCreate(name: string, class: string): Instance
		local existing = remotesFolder:FindFirstChild(name)
		if existing then return existing end
		local r = Instance.new(class)
		r.Name   = name
		r.Parent = remotesFolder
		return r
	end
	-- Client -> Server
	local RemoteSendRequest = getOrCreate("CoupleSendRequest", "RemoteEvent") :: RemoteEvent
	local RemoteRespond     = getOrCreate("CoupleRespond",     "RemoteEvent") :: RemoteEvent
	local RemoteBreakup     = getOrCreate("CoupleBreakup",     "RemoteEvent") :: RemoteEvent
	local RemoteOpenPanel   = getOrCreate("CoupleOpenPanel",   "RemoteEvent") :: RemoteEvent
	-- Server -> Client
	local RemoteNotifyRequest = getOrCreate("CoupleNotifyRequest", "RemoteEvent") :: RemoteEvent
	local RemoteNotifyResult  = getOrCreate("CoupleNotifyResult",  "RemoteEvent") :: RemoteEvent
	local RemoteAnnounce      = getOrCreate("CoupleAnnounce",      "RemoteEvent") :: RemoteEvent
	local RemotePanelData     = getOrCreate("CouplePanelData",     "RemoteEvent") :: RemoteEvent
	-- NetworkManagers batch per-Heartbeat. Couple flows are bursty (accept
	-- triggers fire-to-self + fire-to-partner + global announce in one frame),
	-- and batching keeps the wire load proportional to recipients, not events.
	local notifyRequestNetwork = NetworkManager.create({
		reliable = RemoteNotifyRequest,
		logger = log,
		isServer = true,
	})
	local notifyResultNetwork = NetworkManager.create({
		reliable = RemoteNotifyResult,
		logger = log,
		isServer = true,
	})
	local announceNetwork = NetworkManager.create({
		reliable = RemoteAnnounce,
		logger = log,
		isServer = true,
	})
	local panelDataNetwork = NetworkManager.create({
		reliable = RemotePanelData,
		logger = log,
		isServer = true,
	})
	-- ============================================================
	-- Helpers
	-- ============================================================
	local function announceToAll(msg: string)
		-- Couple announce reaches every player by design. NetworkManager still
		-- batches per Heartbeat so multiple accept events in the same frame
		-- coalesce instead of producing back-to-back wire fires.
		announceNetwork:fireAllClients(msg)
	end
	local function findPlayerById(userId: number): Player?
		for _, p in ipairs(Players:GetPlayers()) do
			if p.UserId == userId then return p end
		end
		return nil
	end
	-- ============================================================
	-- Client minta data panel
	-- ============================================================
	RemoteOpenPanel.OnServerEvent:Connect(function(player: Player, raw: any)
		local sizeOk = Validator.checkSize(raw)
		if not sizeOk then return end
		local validation = Validator.coupleOpenPanel(raw)
		if not validation.valid then return end
		if not openLimiter:check(player.UserId) then
			return
		end
		repo:invalidateCache(player.UserId)
		local storedResult  = repo:load(player.UserId)
		local isCoupled     = false
		local partnerName   = ""
		local partnerId: number? = nil
		if storedResult.ok then
			isCoupled   = storedResult.value.couplePartner ~= nil
			partnerName = storedResult.value.couplePartner or ""
			partnerId   = storedResult.value.couplePartnerId
		end
		panelDataNetwork:fireClient(player, {
			isCoupled   = isCoupled,
			partnerName = partnerName,
			partnerId   = partnerId,
		})
	end)
	-- ============================================================
	-- Client kirim couple request
	-- ============================================================
	RemoteSendRequest.OnServerEvent:Connect(function(player: Player, raw: any)
		local sizeOk = Validator.checkSize(raw)
		if not sizeOk then return end
		local validation = Validator.coupleRequest(raw)
		if not validation.valid then return end
		if not sendLimiter:check(player.UserId) then
			notify.player(player, Config.Couple.MSG_RATE_LIMIT, "WARNING")
			return
		end
		if not rememberRequest(raw.requestId) then return end
		local target = findPlayerById(raw.targetUserId)
		if not target then
			notify.player(player, Config.Couple.MSG_NOT_FOUND, "ERROR")
			return
		end
		task.spawn(function()
			local result = coupleService:sendRequest(player, target, raw.requestId)
			if not result.ok then
				notify.player(player, result.error, "ERROR")
				return
			end
			notifyRequestNetwork:fireClient(target, {
				requestId    = raw.requestId,
				fromUserId   = player.UserId,
				fromName     = player.DisplayName,
				fromUsername = player.Name,
			})
			log:info("Request sent", { from = player.Name, to = target.Name })
		end)
	end)
	-- ============================================================
	-- Client respond (accept/reject)
	-- ============================================================
	RemoteRespond.OnServerEvent:Connect(function(player: Player, raw: any)
		local sizeOk = Validator.checkSize(raw)
		if not sizeOk then return end
		local validation = Validator.coupleResponse(raw)
		if not validation.valid then return end
		if not respondLimiter:check(player.UserId) then
			notify.player(player, Config.Couple.MSG_RATE_LIMIT, "WARNING")
			return
		end
		if not rememberRequest(raw.requestId .. ":" .. tostring(raw.accepted)) then return end
		task.spawn(function()
			if raw.accepted then
				local result = coupleService:acceptRequest(player, raw.requestId)
				if not result.ok then
					notify.player(player, result.error, "ERROR")
					return
				end
				local senderUserId = result.value.senderUserId
				local senderName   = result.value.senderName
				notifyResultNetwork:fireClient(player, { accepted = true, partnerName = senderName })
				local sender = findPlayerById(senderUserId)
				if sender then
					notifyResultNetwork:fireClient(sender, { accepted = true, partnerName = player.DisplayName })
					repo:invalidateCache(senderUserId)
					overheadController:refreshPlayer(sender)
				end
				repo:invalidateCache(player.UserId)
				overheadController:refreshPlayer(player)
				announceToAll(Config.Couple.ANNOUNCE_COUPLED:format(senderName, player.DisplayName))
			else
				local result = coupleService:rejectRequest(player, raw.requestId)
				if not result.ok then return end
				local sender = findPlayerById(result.value.senderUserId)
				if sender then
					notifyResultNetwork:fireClient(sender, { accepted = false, partnerName = player.DisplayName })
				end
				log:info("Request rejected", { by = player.Name })
			end
		end)
	end)
	-- ============================================================
	-- Client breakup
	-- ============================================================
	RemoteBreakup.OnServerEvent:Connect(function(player: Player, raw: any)
		local sizeOk = Validator.checkSize(raw)
		if not sizeOk then return end
		local validation = Validator.coupleBreakup(raw)
		if not validation.valid then return end
		if not breakupLimiter:check(player.UserId) then
			notify.player(player, Config.Couple.MSG_RATE_LIMIT, "WARNING")
			return
		end
		if not rememberRequest(raw.requestId) then return end
		task.spawn(function()
			local storedResult = repo:load(player.UserId)
			if not storedResult.ok then return end
			local partnerName = storedResult.value.couplePartner
			local partnerId   = storedResult.value.couplePartnerId
			local partnerPlayer: Player? = partnerId and findPlayerById(partnerId) or nil
			local result = coupleService:breakupBoth(player)
			if not result.ok then
				notify.player(player, result.error, "ERROR")
				return
			end
			notify.player(player, Config.Couple.MSG_BREAKUP_DONE:format(partnerName or "your partner"), "WARNING")
			repo:invalidateCache(player.UserId)
			overheadController:refreshPlayer(player)
			-- Gunakan hanya partnerId (unik) untuk resolve partner.
			-- Tidak fallback ke DisplayName (tidak unik - bisa salah target).
			-- Jika partnerId nil (data lama), partner dianggap offline - overhead-nya
			-- akan di-refresh saat mereka login kembali.
			local resolvedPartner: Player? = partnerPlayer
			if resolvedPartner then
				repo:invalidateCache(resolvedPartner.UserId)
				overheadController:refreshPlayer(resolvedPartner)
				notifyResultNetwork:fireClient(resolvedPartner, {
					accepted    = false,
					partnerName = player.DisplayName,
					isBreakup   = true,
				})
				notify.player(resolvedPartner, "[Couple] " .. player.DisplayName .. " ended the couple.", "WARNING")
			end
			if partnerName then
				announceToAll(Config.Couple.ANNOUNCE_BREAKUP:format(player.DisplayName, partnerName))
			end
		end)
	end)
	-- ============================================================
	-- Cancel pending request saat player leave
	-- ============================================================
	Players.PlayerRemoving:Connect(function(player)
		coupleService:cancelPendingFrom(player.UserId)
	end)
	log:info("CoupleController initialized")
	return {}
end
return createCoupleController
