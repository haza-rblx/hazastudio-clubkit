--!strict
-- Server/Services/ShopService.lua
-- Business logic: grant membership, manage pending gift.
-- No DataStore directly - via OverheadRepository.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config         = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local LicenseService = require(script.Parent.LicenseService)
local ShopDomain     = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.ShopDomain)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local Types          = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local ResultUtil     = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
type Result<T>           = Types.Result<T>
type IOverheadRepository = Types.IOverheadRepository
type ILogger             = Types.ILogger
type ShopMembershipTier  = Types.ShopMembershipTier
export type IShopService = {
	grantMembership   : (self: IShopService, userId: number, tier: ShopMembershipTier) -> Result<nil>,
	storePendingGift  : (self: IShopService, fromId: number, toId: number) -> Result<nil>,
	resolvePendingGift: (self: IShopService, fromId: number) -> (number?),
}
type PendingEntry = {
	toId : number,
	at   : number,
}
local function createShopService(deps: {
	repo   : IOverheadRepository,
	logger : ILogger,
	giftPendingRepository: any?,
}): IShopService
	local log     = deps.logger
	local repo    = deps.repo
	local giftPendingRepository = deps.giftPendingRepository
	local pending: {[number]: PendingEntry} = {}
	local self = {} :: IShopService
	-- Bersihkan pending yang sudah expired
	local function cleanupPending()
		local now = os.time()
		for fromId, entry in pairs(pending) do
			if now - entry.at > Config.Shop.GIFT_PENDING_TIMEOUT then
				pending[fromId] = nil
			end
		end
	end
	function self:grantMembership(userId: number, tier: ShopMembershipTier): Result<nil>
		if not LicenseService.isFeatureEnabled("shop_grant") then
			log:warn("grantMembership blocked — license inactive", { userId = userId, tier = tier })
			return ResultUtil.Err("license_inactive")
		end
		local parsedTier = ShopDomain.parseShopTier(tier)
		if not parsedTier then
			return { ok = false, error = "Invalid tier: " .. tier }
		end
		local updated = repo:update(userId, function(current)
			return OverheadDomain.mergeStored(current, { membershipBadge = parsedTier })
		end)
		if not updated.ok then
			log:error("grantMembership update fail", { userId = userId, error = updated.error })
			return ResultUtil.Err(updated.error)
		else
			log:info("Membership granted", { userId = userId, tier = parsedTier })
			return ResultUtil.Ok(nil)
		end
	end
	function self:storePendingGift(fromId: number, toId: number): Result<nil>
		cleanupPending()
		pending[fromId] = { toId = toId, at = os.time() }
		if giftPendingRepository and type(giftPendingRepository.store) == "function" then
			local persistResult = giftPendingRepository:store(fromId, toId)
			if not persistResult.ok then
				log:warn("Gift pending persist failed", {
					from = fromId,
					to = toId,
					error = persistResult.error,
				})
				return ResultUtil.Err(persistResult.error)
			end
		end
		log:info("Gift pending stored", { from = fromId, to = toId })
		return ResultUtil.Ok(nil)
	end
	-- Ambil dan hapus pending gift milik fromId.
	-- Return targetUserId atau nil kalau tidak ada / expired.
	function self:resolvePendingGift(fromId: number): (number?)
		cleanupPending()
		local entry = pending[fromId]
		if entry and os.time() - entry.at <= Config.Shop.GIFT_PENDING_TIMEOUT then
			pending[fromId] = nil
			return entry.toId
		end
		if giftPendingRepository and type(giftPendingRepository.consume) == "function" then
			local consumeResult = giftPendingRepository:consume(fromId)
			if consumeResult.ok and type(consumeResult.value) == "number" and consumeResult.value > 0 then
				pending[fromId] = nil
				return consumeResult.value
			end
			if not consumeResult.ok then
				log:warn("Gift pending consume failed", {
					from = fromId,
					error = consumeResult.error,
				})
			end
		end
		return nil
	end
	return self
end
return createShopService
