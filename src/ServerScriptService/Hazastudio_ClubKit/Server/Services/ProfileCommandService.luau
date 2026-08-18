--!strict
-- ServerScriptService/Server/Services/ProfileCommandService.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local TextFilterUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.TextFilterUtil)

type Result<T> = Types.Result<T>
type ProfileStoredData = Types.ProfileStoredData
type ILogger = Types.ILogger

local function createProfileCommandService(deps: {
	logger: ILogger,
	profileRepository: any,
})
	local _log = deps.logger
	local repo = deps.profileRepository
	local sessionStatuses: {[number]: string} = {}
	local sessionStatusUpdatedAt: {[number]: number} = {}
	
	local service = {}
	
	function service:setBio(userId: number, bio: string): Result<nil>
		-- Trim whitespace
		bio = bio:match("^%s*(.-)%s*$") or ""

		-- Validate length
		if #bio > Config.AvatarContext.BIO_MAX_LENGTH then
			return Result.Err(string.format(Config.AvatarContext.MSG_TOO_LONG, Config.AvatarContext.BIO_MAX_LENGTH))
		end

		-- Empty after trim = clear
		if #bio == 0 then
			return service:clearBio(userId)
		end

		-- Filter at write: raw text must never reach DataStore or the
		-- overhead/ACM displays (ADR 0004). Yielding — callers run in
		-- yieldable remote/chat-command contexts.
		local filteredBio = TextFilterUtil.filterForBroadcast(userId, bio, Config.AvatarContext.BIO_MAX_LENGTH)
		if not filteredBio then
			return Result.Err(Config.AvatarContext.MSG_FILTER_FAILED)
		end

		-- Check rate limit
		local loadResult = repo:load(userId)
		if loadResult.ok then
			local profile = loadResult.value
			if profile.lastBioUpdate then
				local elapsed = os.time() - profile.lastBioUpdate
				if elapsed < Config.AvatarContext.BIO_UPDATE_COOLDOWN then
					return Result.Err(Config.AvatarContext.MSG_RATE_LIMIT)
				end
			end
		end

		-- Update
		local updateResult = repo:update(userId, function(current: ProfileStoredData): ProfileStoredData
			local nextProfile = table.clone(current)
			nextProfile.bio = filteredBio
			nextProfile.lastBioUpdate = os.time()
			nextProfile.lastStatusUpdate = current.lastStatusUpdate
			return nextProfile
		end)
		
		if not updateResult.ok then
			return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
		end
		
		return Result.Ok(nil)
	end
	
	function service:clearBio(userId: number): Result<nil>
		local updateResult = repo:update(userId, function(current: ProfileStoredData): ProfileStoredData
			local nextProfile = table.clone(current)
			nextProfile.bio = nil
			nextProfile.lastBioUpdate = current.lastBioUpdate
			nextProfile.lastStatusUpdate = current.lastStatusUpdate
			return nextProfile
		end)
		
		if not updateResult.ok then
			return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
		end
		
		return Result.Ok(nil)
	end
	
	function service:setStatus(userId: number, statusText: string): Result<nil>
		-- Trim whitespace
		statusText = statusText:match("^%s*(.-)%s*$") or ""

		-- Validate length
		if #statusText > Config.AvatarContext.STATUS_MAX_LENGTH then
			return Result.Err(string.format(Config.AvatarContext.MSG_TOO_LONG, Config.AvatarContext.STATUS_MAX_LENGTH))
		end

		-- Empty after trim = clear
		if #statusText == 0 then
			return service:clearStatus(userId)
		end

		-- Filter at write: statusText renders on the overhead billboard above
		-- the player's head for EVERYONE — raw text must never be stored or
		-- broadcast (ADR 0004, gap G1). Yielding — callers are yieldable.
		local filteredStatus = TextFilterUtil.filterForBroadcast(userId, statusText, Config.AvatarContext.STATUS_MAX_LENGTH)
		if not filteredStatus then
			return Result.Err(Config.AvatarContext.MSG_FILTER_FAILED)
		end

		local loadResult = repo:load(userId)
		if loadResult.ok and loadResult.value.lastStatusUpdate then
			local elapsed = os.time() - loadResult.value.lastStatusUpdate
			if elapsed < Config.AvatarContext.STATUS_UPDATE_COOLDOWN then
				return Result.Err(Config.AvatarContext.MSG_RATE_LIMIT)
			end
		end

		local now = os.time()
		local updateResult = repo:update(userId, function(current: ProfileStoredData): ProfileStoredData
			local nextProfile = table.clone(current)
			nextProfile.statusText = filteredStatus
			nextProfile.lastStatusUpdate = now
			return nextProfile
		end)
		if not updateResult.ok then
			return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
		end

		sessionStatuses[userId] = filteredStatus
		sessionStatusUpdatedAt[userId] = now

		return Result.Ok(nil)
	end
	
	function service:clearStatus(userId: number): Result<nil>
		sessionStatuses[userId] = nil
		sessionStatusUpdatedAt[userId] = nil

		local updateResult = repo:update(userId, function(current: ProfileStoredData): ProfileStoredData
			local nextProfile = table.clone(current)
			nextProfile.statusText = nil
			nextProfile.lastStatusUpdate = current.lastStatusUpdate
			return nextProfile
		end)
		if not updateResult.ok then
			return Result.Err(Config.AvatarContext.MSG_SAVE_FAILED)
		end
		
		return Result.Ok(nil)
	end

	function service:getStatus(userId: number): string?
		local sessionStatus = sessionStatuses[userId]
		if sessionStatus ~= nil then
			return sessionStatus
		end

		local loadResult = repo:load(userId)
		if loadResult.ok then
			return loadResult.value.statusText
		end
		return nil
	end

	function service:onPlayerRemoving(player: Player)
		sessionStatuses[player.UserId] = nil
		sessionStatusUpdatedAt[player.UserId] = nil
	end
	
	return service
end

return createProfileCommandService
