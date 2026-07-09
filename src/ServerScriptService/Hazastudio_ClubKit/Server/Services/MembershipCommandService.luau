--!strict
-- Business logic untuk /gift dan /ungift membership via chat command.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local PermissionDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.PermissionDomain)
local ResultUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

type Result<T> = Types.Result<T>
type MembershipTier = Types.MembershipTier
type IOverheadRepository = Types.IOverheadRepository

export type GiftMembershipSuccess = {
	giftTier: MembershipTier,
	effectiveMembership: MembershipTier,
}

export type UngiftMembershipSuccess = {
	removedTier: MembershipTier,
	effectiveMembership: MembershipTier,
}

export type GrantAllOutcome = {
	player: Player,
	kind: "granted" | "skipped" | "failed",
	giftTier: MembershipTier?,
	effectiveMembership: MembershipTier?,
	error: string?,
}

export type GrantAllSummary = {
	tier: MembershipTier,
	granted: { GrantAllOutcome },
	skipped: { GrantAllOutcome },
	failed: { GrantAllOutcome },
}

export type IMembershipCommandService = {
	grantMembership: (self: IMembershipCommandService, giver: Player, target: Player, tier: MembershipTier) -> Result<GiftMembershipSuccess>,
	removeMembership: (self: IMembershipCommandService, giver: Player, target: Player, tier: MembershipTier) -> Result<UngiftMembershipSuccess>,
	grantMembershipToAll: (self: IMembershipCommandService, giver: Player, tier: MembershipTier) -> Result<GrantAllSummary>,
}

local function createMembershipCommandService(deps: {
	repo: IOverheadRepository,
	overheadService: any,
}): IMembershipCommandService
	local repo = deps.repo
	local overheadService = deps.overheadService
	local log = Logger.new("MembershipCommandService")
	local self = {} :: IMembershipCommandService

	local function canManageMembership(player: Player): boolean
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

	local function getRankIdForMembershipFallback(player: Player): number
		local role = overheadService:getRawGroupRole(player)
		return role == "Guest" and 0 or 1
	end

	function self:grantMembership(giver: Player, target: Player, tier: MembershipTier): Result<GiftMembershipSuccess>
		if not canManageMembership(giver) then
			return ResultUtil.Err(Config.Gift.MSG_NO_PERM)
		end

		local normalizedTier = OverheadDomain.normalizeMembershipTier(tier)
		if not normalizedTier or not OverheadDomain.isPaidMembershipTier(normalizedTier) then
			return ResultUtil.Err(Config.Gift.MSG_INVALID:format(tier))
		end

		local storedResult = repo:loadStrict(target.UserId)
		if not storedResult.ok then
			log:error("Membership load failed before grant", {
				by = giver.Name,
				target = target.Name,
				error = storedResult.error,
			})
			return ResultUtil.Err(Config.Gift.MSG_SAVE_FAILED)
		end

		local current = storedResult.value
		if OverheadDomain.hasStoredMembershipAtLeast(current, normalizedTier) then
			return ResultUtil.Err(Config.Gift.MSG_ALREADY_HAS:format(target.DisplayName, OverheadDomain.getMembershipChatLabel(normalizedTier)))
		end

		local updatedResult = repo:update(target.UserId, function(latest)
			return OverheadDomain.addGiftedMembership(latest, normalizedTier, giver.UserId, "chat_command")
		end)
		if not updatedResult.ok then
			log:error("Membership grant failed", {
				by = giver.Name,
				target = target.Name,
				tier = normalizedTier,
				error = updatedResult.error,
			})
			return ResultUtil.Err(Config.Gift.MSG_SAVE_FAILED)
		end

		local effectiveMembership = (OverheadDomain.resolveEffectiveMembership(updatedResult.value, getRankIdForMembershipFallback(target)) :: any) :: MembershipTier
		log:info("Membership granted by command", {
			by = giver.Name,
			target = target.Name,
			tier = normalizedTier,
			effective = effectiveMembership,
		})

		return ResultUtil.Ok({
			giftTier = normalizedTier,
			effectiveMembership = effectiveMembership,
		} :: GiftMembershipSuccess)
	end

	function self:removeMembership(giver: Player, target: Player, tier: MembershipTier): Result<UngiftMembershipSuccess>
		if not canManageMembership(giver) then
			return ResultUtil.Err(Config.Gift.MSG_NO_PERM)
		end
		local normalizedTier = OverheadDomain.normalizeMembershipTier(tier)
		if not normalizedTier or not OverheadDomain.isPaidMembershipTier(normalizedTier) then
			return ResultUtil.Err(Config.Gift.MSG_INVALID:format(tier))
		end

		local storedResult = repo:loadStrict(target.UserId)
		if not storedResult.ok then
			log:error("Membership load failed before remove", {
				by = giver.Name,
				target = target.Name,
				error = storedResult.error,
			})
			return ResultUtil.Err(Config.Gift.MSG_SAVE_FAILED)
		end

		if not OverheadDomain.hasGiftedMembership(storedResult.value, normalizedTier) then
			return ResultUtil.Err(Config.Gift.MSG_UNGIFT_NONE:format(target.DisplayName, OverheadDomain.getMembershipChatLabel(normalizedTier)))
		end

		local updatedResult = repo:update(target.UserId, function(latest)
			local updated, _ = OverheadDomain.removeGiftedMembership(latest, normalizedTier)
			return updated
		end)
		if not updatedResult.ok then
			log:error("Membership remove failed", {
				by = giver.Name,
				target = target.Name,
				tier = normalizedTier,
				error = updatedResult.error,
			})
			return ResultUtil.Err(Config.Gift.MSG_SAVE_FAILED)
		end

		local effectiveMembership = (OverheadDomain.resolveEffectiveMembership(updatedResult.value, getRankIdForMembershipFallback(target)) :: any) :: MembershipTier
		log:info("Membership removed by command", {
			by = giver.Name,
			target = target.Name,
			tier = normalizedTier,
			effective = effectiveMembership,
		})

		return ResultUtil.Ok({
			removedTier = normalizedTier,
			effectiveMembership = effectiveMembership,
		} :: UngiftMembershipSuccess)
	end

	function self:grantMembershipToAll(giver: Player, tier: MembershipTier): Result<GrantAllSummary>
		if not canManageMembership(giver) then
			return ResultUtil.Err(Config.Gift.MSG_NO_PERM)
		end

		local normalizedTier = OverheadDomain.normalizeMembershipTier(tier)
		if not normalizedTier or not OverheadDomain.isPaidMembershipTier(normalizedTier) then
			return ResultUtil.Err(Config.Gift.MSG_INVALID:format(tier))
		end

		local granted: { GrantAllOutcome } = {}
		local skipped: { GrantAllOutcome } = {}
		local failed: { GrantAllOutcome } = {}

		for _, target in ipairs(Players:GetPlayers()) do
			if target == giver then
				continue
			end

			local grantResult = self:grantMembership(giver, target, normalizedTier)
			if grantResult.ok then
				table.insert(granted, {
					player = target,
					kind = "granted",
					giftTier = grantResult.value.giftTier,
					effectiveMembership = grantResult.value.effectiveMembership,
				} :: GrantAllOutcome)
			else
				local errMsg = grantResult.error
				local isAlready = type(errMsg) == "string"
					and string.find(errMsg, "already has", 1, true) ~= nil
				local bucket = if isAlready then skipped else failed
				table.insert(bucket, {
					player = target,
					kind = if isAlready then "skipped" else "failed",
					error = errMsg,
				} :: GrantAllOutcome)
			end
		end

		log:info("Bulk membership grant", {
			by = giver.Name,
			tier = normalizedTier,
			granted = #granted,
			skipped = #skipped,
			failed = #failed,
		})

		return ResultUtil.Ok({
			tier = normalizedTier,
			granted = granted,
			skipped = skipped,
			failed = failed,
		} :: GrantAllSummary)
	end

	return self
end

return createMembershipCommandService
