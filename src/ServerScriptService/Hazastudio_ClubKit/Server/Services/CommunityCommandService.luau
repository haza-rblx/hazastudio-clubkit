--!strict
-- Business logic untuk /setcommun dan /clearcommun.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local ResultUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

type Result<T> = Types.Result<T>
type CommunityData = Types.CommunityData
type CommunityLookupResult = Types.CommunityLookupResult
type IOverheadRepository = Types.IOverheadRepository
type IOverheadService = Types.IOverheadService

export type SetCommunitySuccess = {
	communityId: number,
	communityName: string?,
	communityLogo: string?,
}

export type ResolveCommunityInputResult = {
	status: "found",
	community: CommunityData,
} | {
	status: "not_found",
	query: string,
} | {
	status: "ambiguous",
	query: string,
	candidates: {CommunityData},
}

export type ICommunityCommandService = {
	setCommunity: (self: ICommunityCommandService, player: Player, communityId: number) -> Result<SetCommunitySuccess>,
	resolveInput: (self: ICommunityCommandService, player: Player, rawInput: string) -> Result<ResolveCommunityInputResult>,
	clearCommunity: (self: ICommunityCommandService, player: Player) -> Result<nil>,
}

local function createCommunityCommandService(deps: {
	repo: IOverheadRepository,
	overheadService: IOverheadService,
}): ICommunityCommandService
	local repo = deps.repo
	local overheadService = deps.overheadService
	local log = Logger.new("CommunityCommandService")
	local self = {} :: ICommunityCommandService

	local function normalizeInput(rawInput: string): string
		return rawInput:match("^%s*(.-)%s*$") or ""
	end

	function self:setCommunity(player: Player, communityId: number): Result<SetCommunitySuccess>
		if communityId <= 0 then
			return ResultUtil.Err(Config.Community.MSG_INVALID_ID)
		end

		local storedResult = repo:loadStrict(player.UserId)
		if not storedResult.ok then
			log:error("Community load failed before set", {
				player = player.Name,
				error = storedResult.error,
			})
			return ResultUtil.Err(Config.Community.MSG_SAVE_FAILED)
		end

		if storedResult.value.communityId == communityId then
			return ResultUtil.Err(Config.Community.MSG_ALREADY_ACTIVE)
		end

		local communityResult = overheadService:resolveCommunity(player, communityId)
		if not communityResult.ok then
			log:warn("Community resolve failed", {
				player = player.Name,
				communityId = communityId,
				error = communityResult.error,
			})
			return ResultUtil.Err(communityResult.error)
		end

		local updateResult = repo:update(player.UserId, function(current)
			return OverheadDomain.mergeStored(current, {
				communityId = communityId,
				suppressCommunityBadge = false,
			})
		end)
		if not updateResult.ok then
			log:error("Community save failed", {
				player = player.Name,
				communityId = communityId,
				error = updateResult.error,
			})
			return ResultUtil.Err(Config.Community.MSG_SAVE_FAILED)
		end

		log:info("Community set by player", {
			player = player.Name,
			communityId = communityId,
		})

		local communityData: CommunityData = communityResult.value
		return ResultUtil.Ok({
			communityId = communityData.id,
			communityName = communityData.name,
			communityLogo = communityData.logo,
		})
	end

	function self:clearCommunity(player: Player): Result<nil>
		local storedResult = repo:loadStrict(player.UserId)
		if not storedResult.ok then
			log:error("Community load failed before clear", {
				player = player.Name,
				error = storedResult.error,
			})
			return ResultUtil.Err(Config.Community.MSG_SAVE_FAILED)
		end

		if storedResult.value.suppressCommunityBadge == true and not storedResult.value.communityId then
			return ResultUtil.Err(Config.Community.MSG_CLEAR_NONE)
		end

		local updateResult = repo:update(player.UserId, function(current)
			return OverheadDomain.mergeStored(current, {
				communityId = OverheadDomain.NIL,
				suppressCommunityBadge = true,
			})
		end)
		if not updateResult.ok then
			log:error("Community clear failed", {
				player = player.Name,
				error = updateResult.error,
			})
			return ResultUtil.Err(Config.Community.MSG_SAVE_FAILED)
		end

		log:info("Community cleared by player", {
			player = player.Name,
		})

		return ResultUtil.Ok(nil)
	end

	function self:resolveInput(player: Player, rawInput: string): Result<ResolveCommunityInputResult>
		local input = normalizeInput(rawInput)
		if input == "" then
			return ResultUtil.Err(Config.Community.MSG_USAGE)
		end

		local asNumber = tonumber(input)
		if asNumber then
			if asNumber <= 0 or asNumber % 1 ~= 0 then
				return ResultUtil.Err(Config.Community.MSG_INVALID_ID)
			end

			local communityResult = overheadService:resolveCommunity(player, asNumber)
			if not communityResult.ok then
				return ResultUtil.Err(communityResult.error)
			end

				return ResultUtil.Ok({
					status = "found",
					community = communityResult.value,
				} :: ResolveCommunityInputResult)
		end

		local lookupResult = overheadService:resolveCommunityByQuery(player, input)
		if not lookupResult.ok then
			return ResultUtil.Err(lookupResult.error)
		end

		local value: CommunityLookupResult = lookupResult.value
		if value.status == "found" then
				return ResultUtil.Ok({
					status = "found",
					community = value.community,
				} :: ResolveCommunityInputResult)
			end

			if value.status == "ambiguous" then
				return ResultUtil.Ok({
					status = "ambiguous",
					query = value.query,
					candidates = value.candidates,
				} :: ResolveCommunityInputResult)
			end

			return ResultUtil.Ok({
				status = "not_found",
				query = value.query,
			} :: ResolveCommunityInputResult)
		end

	return self
end

return createCommunityCommandService
