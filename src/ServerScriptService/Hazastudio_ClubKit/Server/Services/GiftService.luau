--!strict
-- Business logic untuk setrole/unsetrole via gifted role.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local PermissionDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.PermissionDomain)
local ResultUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

type Result<T> = Types.Result<T>
type RoleKey = Types.RoleKey
type IOverheadRepository = Types.IOverheadRepository
type IOverheadService = Types.IOverheadService

export type IGiftService = {
	giveRole: (self: IGiftService, giver: Player, target: Player, roleKey: RoleKey) -> Result<RoleKey>,
	removeRole: (self: IGiftService, giver: Player, target: Player) -> Result<string>,
}

local function createGiftService(deps: {
	repo: IOverheadRepository,
	overheadService: IOverheadService,
}): IGiftService
	local repo = deps.repo
	local overheadService = deps.overheadService
	local log = Logger.new("GiftService")
	local service = {} :: IGiftService

	local function isStudioBypass(): boolean
		return Config.FeatureFlags.STUDIO_GIFT_BYPASS == true
	end

	local function canManageRoles(player: Player): boolean
		if PermissionDomain.isAdminUser(player.UserId) then
			return true
		end
		if overheadService and type(overheadService.getEffectivePayload) == "function" then
			local payloadResult = overheadService:getEffectivePayload(player)
			if payloadResult.ok then
				return PermissionDomain.canGift(payloadResult.value.role, player.UserId)
			end
		end
		return PermissionDomain.canGift(overheadService:getRawGroupRole(player), player.UserId)
	end

	function service:giveRole(giver: Player, target: Player, roleKey: RoleKey): Result<RoleKey>
		local normalizedRole = OverheadDomain.normalizeRoleKey(roleKey)
		if not normalizedRole then
			return ResultUtil.Err(Config.SetRole.MSG_INVALID_ROLE:format(roleKey))
		end

		if isStudioBypass() then
			log:warn("Studio bypass aktif saat giveRole", {
				giver = giver.Name,
				target = target.Name,
				role = normalizedRole,
			})
		else
			if not OverheadDomain.isGiftableRole(normalizedRole) then
				return ResultUtil.Err(Config.SetRole.MSG_INVALID_ROLE:format(roleKey))
			end

			if not canManageRoles(giver) then
				log:warn("Permission denied", {
					giver = giver.Name,
				})
				return ResultUtil.Err(Config.SetRole.MSG_NO_PERM)
			end
		end

		local updateResult = repo:update(target.UserId, function(current)
			return OverheadDomain.applyGift(current, normalizedRole, giver.UserId)
		end)
		if not updateResult.ok then
			log:error("Gift role save failed", {
				target = target.Name,
				role = normalizedRole,
				error = updateResult.error,
			})
			return ResultUtil.Err(Config.SetRole.MSG_SAVE_FAILED)
		end

		overheadService:invalidateGroupCache(target.UserId)

		log:info("Gift role applied", {
			giver = giver.Name,
			target = target.Name,
			role = normalizedRole,
			bypass = isStudioBypass(),
		})
		return {
			ok = true,
			value = normalizedRole,
		} :: Result<RoleKey>
	end

	function service:removeRole(giver: Player, target: Player): Result<string>
		if not isStudioBypass() then
			if not canManageRoles(giver) then
				return ResultUtil.Err(Config.SetRole.MSG_NO_PERM)
			end
		else
			log:warn("Studio bypass aktif saat removeRole", {
				giver = giver.Name,
				target = target.Name,
			})
		end

		local storedResult = repo:loadStrict(target.UserId)
		if not storedResult.ok then
			log:error("Gift role load failed before remove", {
				target = target.Name,
				error = storedResult.error,
			})
			return ResultUtil.Err(Config.SetRole.MSG_SAVE_FAILED)
		end

		local oldRole = storedResult.value.giftedRole
		if not oldRole then
			return ResultUtil.Err(Config.SetRole.MSG_REMOVE_NONE:format(target.Name))
		end

		local updateResult = repo:update(target.UserId, function(current)
			return OverheadDomain.removeGift(current)
		end)
		if not updateResult.ok then
			log:error("Gift role remove save failed", {
				target = target.Name,
				error = updateResult.error,
			})
			return ResultUtil.Err(Config.SetRole.MSG_SAVE_FAILED)
		end

		overheadService:invalidateGroupCache(target.UserId)

		log:info("Gift role removed", {
			giver = giver.Name,
			target = target.Name,
			oldRole = oldRole,
			bypass = isStudioBypass(),
		})
		return ResultUtil.Ok(oldRole)
	end

	return service
end

return createGiftService
