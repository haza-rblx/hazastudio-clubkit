--!strict
-- Paid broadcast: menu modal submit.
-- canAnnounce senders broadcast free; others require Robux purchase -> GenericBroadcast.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local Validator = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Validator)
local GenericBroadcastService = require(script.Parent.Parent.Services.GenericBroadcastService)

type INotify = {
	player: (Player, string, string?) -> (),
	all: (string, string?) -> (),
}

type GenericBroadcastSvc = GenericBroadcastService.Service

export type IPaidBroadcastController = {
	init: (self: IPaidBroadcastController) -> (),
	processReceipt: (self: IPaidBroadcastController, receiptInfo: { [string]: any }) -> Enum.ProductPurchaseDecision,
}

local function createPaidBroadcastController(deps: {
	remotes: Folder,
	notify: INotify,
	genericBroadcastService: GenericBroadcastSvc,
	resultNetwork: any,
}): IPaidBroadcastController
	local remotes = deps.remotes
	local notify = deps.notify
	local broadcastService = deps.genericBroadcastService
	local resultNetwork = deps.resultNetwork
	local log = Logger.new("PaidBroadcastController")
	local cfg = Config.PaidBroadcast

	local paidLimiter = RateLimiter.new(cfg.RATE_MAX, cfg.RATE_WINDOW)
	local pendingPaid: { [number]: { message: string, expiresAt: number } } = {}

	local controller = {} :: IPaidBroadcastController

	local function fireResult(player: Player, payload: { [string]: any })
		resultNetwork:fireClientImmediate(player, payload)
	end

	function controller.processReceipt(
		_self: IPaidBroadcastController,
		receiptInfo: { PlayerId: number, ProductId: number, PurchaseId: string, [string]: any }
	): Enum.ProductPurchaseDecision
		local productId = cfg.PRODUCT_ID
		if productId <= 0 or receiptInfo.ProductId ~= productId then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local userId = receiptInfo.PlayerId
		local player = Players:GetPlayerByUserId(userId)
		local pending = pendingPaid[userId]
		-- NOTE: do NOT clear pendingPaid[userId] yet. If fireAll fails (or the
		-- player is offline) we return NotProcessedYet so Roblox retries; the
		-- pending must survive so the retry can re-attempt the broadcast.
		-- Previously clearing before fireAll meant a transient filter/network
		-- failure permanently lost the player's PAID broadcast — the retry hit
		-- "no valid pending" and returned NotProcessedYet forever.

		if not pending or pending.expiresAt <= os.clock() then
			log:warn("Paid broadcast receipt without valid pending", { userId = userId })
			pendingPaid[userId] = nil
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		if not player then
			log:warn("Paid broadcast receipt player offline", { userId = userId })
			-- Keep pending so a later retry (when the player rejoins) can still fire.
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		if not broadcastService:fireAll(player, pending.message) then
			-- Keep pending so Roblox's retry can re-attempt the broadcast.
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		-- Clear only after the broadcast succeeded.
		pendingPaid[userId] = nil

		notify.player(player, cfg.MSG_SENT, "SUCCESS")
		fireResult(player, { ok = true, mode = "purchased" })
		log:info("Paid broadcast purchased", {
			player = player.Name,
			purchaseId = receiptInfo.PurchaseId,
		})
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	function controller.init(_self: IPaidBroadcastController)
		local submitRemote = remotes:FindFirstChild(cfg.REMOTE_SUBMIT)
		if not submitRemote or not submitRemote:IsA("RemoteEvent") then
			log:warn("Paid broadcast submit remote missing", { remote = cfg.REMOTE_SUBMIT })
			return
		end

		(submitRemote :: RemoteEvent).OnServerEvent:Connect(function(player: Player, raw: any)
			if not Validator.checkSize(raw) then
				log:warn("Paid broadcast payload too large", { player = player.Name })
				return
			end
			if type(raw) ~= "table" or type(raw.message) ~= "string" then
				fireResult(player, { ok = false, error = "invalid_payload" })
				return
			end

			local filtered = broadcastService:filterMessage(player, raw.message, cfg.MAX_MESSAGE_LENGTH)
			if not filtered then
				notify.player(player, cfg.MSG_FILTER_FAILED, "ERROR")
				fireResult(player, { ok = false, error = "filter_failed" })
				return
			end

			if not paidLimiter:check(player.UserId) then
				notify.player(player, cfg.MSG_RATE_LIMIT, "WARNING")
				fireResult(player, { ok = false, error = "rate_limited" })
				return
			end

			-- Staff / canAnnounce: free send (server authority — client UI is cosmetic only).
			local freeOk, freeErr = broadcastService:broadcastFiltered(player, filtered)
			if freeOk then
				pendingPaid[player.UserId] = nil
				notify.player(player, cfg.MSG_SENT, "SUCCESS")
				fireResult(player, { ok = true, mode = "sent" })
				log:info("Paid broadcast sent free (canAnnounce)", { player = player.Name })
				return
			end
			if freeErr ~= "no_perm" then
				notify.player(player, cfg.MSG_FILTER_FAILED, "ERROR")
				fireResult(player, { ok = false, error = freeErr or "broadcast_failed" })
				return
			end

			if cfg.PRODUCT_ID <= 0 then
				notify.player(player, cfg.MSG_PRODUCT_NOT_CONFIGURED, "WARNING")
				fireResult(player, { ok = false, error = "product_not_configured" })
				return
			end

			pendingPaid[player.UserId] = {
				message = filtered,
				expiresAt = os.clock() + cfg.PENDING_TIMEOUT,
			}
			fireResult(player, { ok = true, mode = "purchase_required" })
		end)

		log:info("PaidBroadcastController initialized")
	end

	return controller
end

return createPaidBroadcastController
