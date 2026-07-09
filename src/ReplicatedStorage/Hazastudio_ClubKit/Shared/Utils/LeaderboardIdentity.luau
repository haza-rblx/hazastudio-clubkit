--!strict
-- Resolve Roblox username / display name / headshot for leaderboard rows.
-- Metadata sering menyimpan username di field displayName; helper ini memaksa
-- display name asli dari UserInfos + thumbnail headshot.

local Players = game:GetService("Players")
local UserService = game:GetService("UserService")

export type ResolvedIdentity = {
	username: string,
	displayName: string,
	thumbnail: string,
}

local LeaderboardIdentity = {}

function LeaderboardIdentity.normalizeUsername(value: string?): string
	if type(value) ~= "string" then
		return ""
	end
	return value:gsub("^@", ""):lower()
end

function LeaderboardIdentity.looksLikeFallbackName(name: string?): boolean
	if type(name) ~= "string" or name == "" then
		return true
	end
	return name:match("^User%s*%d+$") ~= nil
end

-- Metadata lama sering isi username di kolom displayName. Bukan berarti
-- DisplayName == Username dari API invalid (Roblox boleh sama).
function LeaderboardIdentity.isStaleDisplayName(displayName: string?, username: string?): boolean
	local normalizedDisplay = LeaderboardIdentity.normalizeUsername(displayName)
	local normalizedUsername = LeaderboardIdentity.normalizeUsername(username)
	if normalizedDisplay == "" or normalizedUsername == "" then
		return false
	end
	return normalizedDisplay == normalizedUsername
end

function LeaderboardIdentity.fetchUserInfos(userIds: { number }): { any }
	if #userIds == 0 then
		return {}
	end

	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(userIds)
	end)
	if ok and type(infos) == "table" then
		return infos
	end

	local legacyOk, legacyInfos = pcall(function()
		return (Players :: any):GetUserInfosByUserIdsAsync(userIds)
	end)
	if legacyOk and type(legacyInfos) == "table" then
		return legacyInfos
	end

	return {}
end

function LeaderboardIdentity.readInfoUserId(info: any): number?
	if type(info) ~= "table" then
		return nil
	end
	return tonumber(info.Id or info.UserId)
end

function LeaderboardIdentity.getUserThumbnail(userId: number, size: number?): string
	local thumbSize = if size == 420 then Enum.ThumbnailSize.Size420x420 else Enum.ThumbnailSize.Size150x150
	local ok, thumbnail = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, thumbSize)
	end)
	if ok and type(thumbnail) == "string" and thumbnail ~= "" then
		return thumbnail
	end
	return string.format(
		"rbxthumb://type=AvatarHeadShot&id=%d&w=%d&h=%d",
		userId,
		size or 150,
		size or 150
	)
end

function LeaderboardIdentity.resolveUserIdentity(userId: number): ResolvedIdentity
	local fallbackUsername = "User " .. tostring(userId)
	local username = fallbackUsername
	local displayName = fallbackUsername

	local player = Players:GetPlayerByUserId(userId)
	if player then
		username = player.Name
		displayName = player.DisplayName
	else
		local infos = LeaderboardIdentity.fetchUserInfos({ userId })
		for _, info in ipairs(infos) do
			if LeaderboardIdentity.readInfoUserId(info) == userId then
				if type(info.Username) == "string" and info.Username ~= "" then
					username = info.Username
				end
				if type(info.DisplayName) == "string" and info.DisplayName ~= "" then
					displayName = info.DisplayName
				else
					displayName = username
				end
				break
			end
		end
	end

	if displayName == fallbackUsername then
		local nameOk, resolvedName = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		if nameOk and type(resolvedName) == "string" and resolvedName ~= "" then
			username = resolvedName
			if LeaderboardIdentity.looksLikeFallbackName(displayName) then
				displayName = resolvedName
			end
		end
	end

	return {
		username = username,
		displayName = displayName,
		thumbnail = LeaderboardIdentity.getUserThumbnail(userId, 150),
	}
end

function LeaderboardIdentity.enrichPlayerEntry(entry: any): any
	if type(entry) ~= "table" then
		return entry
	end

	local userId = tonumber(entry.userId)
	if not userId or userId <= 0 then
		return entry
	end

	local username = if type(entry.username) == "string" then entry.username else ""
	local displayName = if type(entry.displayName) == "string" then entry.displayName else ""
	local thumbnail = if type(entry.thumbnail) == "string" then entry.thumbnail else ""

	local needsResolve = LeaderboardIdentity.looksLikeFallbackName(username)
		or LeaderboardIdentity.looksLikeFallbackName(displayName)
		or LeaderboardIdentity.isStaleDisplayName(displayName, username)
		or thumbnail == ""

	if not needsResolve then
		return entry
	end

	local resolved = LeaderboardIdentity.resolveUserIdentity(userId)
	if LeaderboardIdentity.looksLikeFallbackName(username) then
		username = resolved.username
	end
	if LeaderboardIdentity.looksLikeFallbackName(displayName)
		or LeaderboardIdentity.isStaleDisplayName(displayName, username) then
		displayName = resolved.displayName
	end
	if thumbnail == "" then
		thumbnail = resolved.thumbnail
	end

	entry.username = username
	entry.displayName = displayName
	entry.thumbnail = thumbnail
	return entry
end

function LeaderboardIdentity.enrichEntryList(entries: any): any
	if type(entries) ~= "table" then
		return entries
	end
	for index, entry in ipairs(entries) do
		if type(entry) == "table" then
			entries[index] = LeaderboardIdentity.enrichPlayerEntry(entry)
		end
	end
	return entries
end

return LeaderboardIdentity
