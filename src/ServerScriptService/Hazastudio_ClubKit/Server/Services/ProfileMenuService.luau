--!strict

local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)

type Result<T> = Types.Result<T>
type ProfileMenuPayload = Types.ProfileMenuPayload
type ProfileRelationshipMode = Types.ProfileRelationshipMode
type ProfileStoredData = Types.ProfileStoredData
type OverheadStoredData = Types.OverheadStoredData
type ILogger = Types.ILogger

local function trim(text: string): string
	return text:match("^%s*(.-)%s*$") or ""
end

local function getRelationshipMode(rawMode: any, isCoupled: boolean): ProfileRelationshipMode
	if rawMode == "Fun" then
		return "Fun"
	end
	if rawMode == "Taken" and isCoupled then
		return "Taken"
	end
	if rawMode == "Single" then
		return "Single"
	end
	return if isCoupled then "Taken" else "Single"
end

local function createProfileMenuService(deps: {
	logger: ILogger,
	profileRepository: any,
	overheadRepository: any,
	profileCommandService: any,
})
	local _log = deps.logger
	local profileRepository = deps.profileRepository
	local overheadRepository = deps.overheadRepository
	local profileCommandService = deps.profileCommandService

	local service = {}

	local function filterBroadcastText(text: string, userId: number): Result<string>
		local ok, filteredResult = pcall(function()
			return TextService:FilterStringAsync(text, userId)
		end)
		if not ok or not filteredResult then
			return Result.Err(Config.AvatarContext.MSG_FILTER_FAILED)
		end

		local success, filtered = pcall(function()
			return filteredResult:GetNonChatStringForBroadcastAsync()
		end)
		if not success or type(filtered) ~= "string" then
			return Result.Err(Config.AvatarContext.MSG_FILTER_FAILED)
		end

		local normalized = trim(filtered)
		if normalized == "" then
			return Result.Err(Config.AvatarContext.MSG_FILTER_FAILED)
		end

		return Result.Ok(normalized)
	end

	local function loadStored(userId: number): Result<{ profile: ProfileStoredData, overhead: OverheadStoredData }>
		local profileResult = profileRepository:load(userId)
		if not profileResult.ok then
			return Result.Err(profileResult.error)
		end

		local overheadResult = overheadRepository:load(userId)
		if not overheadResult.ok then
			return Result.Err(overheadResult.error)
		end

		return Result.Ok({
			profile = profileResult.value,
			overhead = overheadResult.value,
		})
	end

	local function buildPayload(player: Player, profile: ProfileStoredData, overhead: OverheadStoredData): ProfileMenuPayload
		local isCoupled = overhead.couplePartner ~= nil or overhead.couplePartnerId ~= nil
		local relationshipMode = getRelationshipMode(profile.relationshipMode, isCoupled)
		local displayNameOverride = type(profile.displayNameOverride) == "string" and profile.displayNameOverride ~= "" and profile.displayNameOverride or nil
		local statusText = if profileCommandService and type(profileCommandService.getStatus) == "function"
			then profileCommandService:getStatus(player.UserId)
			else nil

		return {
			displayName = displayNameOverride or player.DisplayName,
			displayNameOverride = displayNameOverride,
			bio = profile.bio,
			statusText = statusText,
			specialTitle = overhead.specialTitle,
			canEditSpecialTitle = overhead.specialTitle ~= nil,
			relationshipMode = relationshipMode,
			isCoupled = isCoupled,
			couplePartner = overhead.couplePartner,
			showCoupleName = overhead.showCoupleName ~= false,
		}
	end

	local function refreshPayload(player: Player): Result<ProfileMenuPayload>
		local loaded = loadStored(player.UserId)
		if not loaded.ok then
			return Result.Err(loaded.error)
		end
		return Result.Ok(buildPayload(player, loaded.value.profile, loaded.value.overhead))
	end

	function service:load(player: Player): Result<ProfileMenuPayload>
		return refreshPayload(player)
	end

	function service:updateField(player: Player, field: string, value: any): Result<ProfileMenuPayload>
		if field == "displayNameOverride" then
			if type(value) ~= "string" then
				return Result.Err(Config.ProfileMenu.MSG_DISPLAY_NAME_TOO_LONG)
			end

			local nextValue = trim(value)
			if #nextValue > Config.ProfileMenu.DISPLAY_NAME_MAX_LENGTH then
				return Result.Err(Config.ProfileMenu.MSG_DISPLAY_NAME_TOO_LONG)
			end

			local filtered: string? = nil
			if nextValue ~= "" then
				local filteredResult = filterBroadcastText(nextValue, player.UserId)
				if not filteredResult.ok then
					return filteredResult
				end
				filtered = filteredResult.value
				if filtered == player.DisplayName then
					filtered = nil
				end
			end

			local saved = profileRepository:update(player.UserId, function(current: ProfileStoredData): ProfileStoredData
				local nextProfile = table.clone(current)
				nextProfile.displayNameOverride = filtered
				return nextProfile
			end)
			if not saved.ok then
				return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
			end

			return refreshPayload(player)
		end

		if field == "bio" then
			if type(value) ~= "string" then
				return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
			end

			local saved = profileCommandService:setBio(player.UserId, value)
			if not saved.ok then
				return saved
			end
			return refreshPayload(player)
		end

		if field == "statusText" then
			if type(value) ~= "string" then
				return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
			end

			local saved = profileCommandService:setStatus(player.UserId, value)
			if not saved.ok then
				return saved
			end
			return refreshPayload(player)
		end

		if field == "relationshipMode" then
			if value ~= "Single" and value ~= "Taken" and value ~= "Fun" then
				return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
			end

			local loaded = loadStored(player.UserId)
			if not loaded.ok then
				return Result.Err(loaded.error)
			end

			local isCoupled = loaded.value.overhead.couplePartner ~= nil or loaded.value.overhead.couplePartnerId ~= nil
			if value == "Taken" and not isCoupled then
				return Result.Err(Config.ProfileMenu.MSG_SINGLE_DUMB)
			end

			local saved = profileRepository:update(player.UserId, function(current: ProfileStoredData): ProfileStoredData
				local nextProfile = table.clone(current)
				nextProfile.relationshipMode = value
				return nextProfile
			end)
			if not saved.ok then
				return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
			end

			return refreshPayload(player)
		end

		if field == "showCoupleName" then
			if type(value) ~= "boolean" then
				return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
			end

			local loaded = loadStored(player.UserId)
			if not loaded.ok then
				return Result.Err(loaded.error)
			end

			local isCoupled = loaded.value.overhead.couplePartner ~= nil or loaded.value.overhead.couplePartnerId ~= nil
			if not isCoupled then
				return Result.Err(Config.ProfileMenu.MSG_SINGLE_DUMB)
			end

			local saved = overheadRepository:update(player.UserId, function(current: OverheadStoredData): OverheadStoredData
				return OverheadDomain.mergeStored(current, {
					showCoupleName = value,
				})
			end)
			if not saved.ok then
				return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
			end

			return refreshPayload(player)
		end

		if field == "specialTitle" then
			if type(value) ~= "string" then
				return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
			end

			local loaded = loadStored(player.UserId)
			if not loaded.ok then
				return Result.Err(loaded.error)
			end

			if loaded.value.overhead.specialTitle == nil then
				return Result.Err(Config.ProfileMenu.MSG_TITLE_LOCKED)
			end

			local nextValue = trim(value)
			if nextValue == "" then
				return Result.Err(Config.ProfileMenu.MSG_TITLE_EMPTY)
			end
			if #nextValue > Config.Admin.TITLE_MAX_LENGTH then
				return Result.Err(Config.ProfileMenu.MSG_TITLE_TOO_LONG)
			end

			local filteredResult = filterBroadcastText(nextValue, player.UserId)
			if not filteredResult.ok then
				return filteredResult
			end

			local saved = overheadRepository:update(player.UserId, function(current: OverheadStoredData): OverheadStoredData
				return OverheadDomain.mergeStored(current, {
					specialTitle = filteredResult.value,
				})
			end)
			if not saved.ok then
				return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
			end

			return refreshPayload(player)
		end

		return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
	end

	return service
end

return createProfileMenuService
