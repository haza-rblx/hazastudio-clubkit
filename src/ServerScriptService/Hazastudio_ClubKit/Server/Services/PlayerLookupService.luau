--!strict
-- Resolve player dari username/display name dengan exact dan prefix match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types      = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local ResultUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)

type Result<T> = Types.Result<T>

export type LookupErrorCode = "too_short" | "ambiguous" | "not_found"
export type LookupSuccess = {
	kind: "found",
	player: Player,
}
export type LookupFailure = {
	kind: LookupErrorCode,
	query: string,
	matches: {Player}?,
}

export type IPlayerLookupService = {
	resolve: (self: IPlayerLookupService, query: string) -> Result<Player>,
	resolveDetailed: (self: IPlayerLookupService, query: string) -> Result<LookupSuccess | LookupFailure>,
	describePlayers: (self: IPlayerLookupService, players: {Player}, maxCount: number?) -> string,
}

local function normalize(text: string): string
	local trimmed = string.gsub(text, "^%s*(.-)%s*$", "%1")
	return string.lower(trimmed)
end

local function found(player: Player): LookupSuccess
	return {
		kind = "found",
		player = player,
	}
end

local function failure(kind: LookupErrorCode, query: string, matches: {Player}?): LookupFailure
	return {
		kind = kind,
		query = query,
		matches = matches,
	}
end

local function startsWith(text: string, prefix: string): boolean
	return string.sub(text, 1, #prefix) == prefix
end

local function addUnique(list: {Player}, seen: {[number]: boolean}, player: Player)
	if seen[player.UserId] then
		return
	end

	seen[player.UserId] = true
	table.insert(list, player)
end

local function createPlayerLookupService(): IPlayerLookupService
	local self = {} :: IPlayerLookupService

	function self:describePlayers(players: {Player}, maxCount: number?): string
		local limit = maxCount or 3
		local parts = table.create(math.min(#players, limit))

		for index, player in ipairs(players) do
			if index > limit then
				break
			end

			table.insert(parts, ("%s (@%s)"):format(player.DisplayName, player.Name))
		end

		if #players > limit then
			table.insert(parts, ("+%d more"):format(#players - limit))
		end

		return table.concat(parts, ", ")
	end

	function self:resolveDetailed(query: string): Result<LookupSuccess | LookupFailure>
		local normalizedQuery = normalize(query)
		if normalizedQuery == "" then
			return ResultUtil.Ok(failure("not_found", query, nil))
		end

		local exactMatches = {} :: {Player}
		local prefixMatches = {} :: {Player}
		local exactSeen = {} :: {[number]: boolean}
		local prefixSeen = {} :: {[number]: boolean}

		for _, player in ipairs(Players:GetPlayers()) do
			local username = string.lower(player.Name)
			local displayName = string.lower(player.DisplayName)

			if username == normalizedQuery or displayName == normalizedQuery then
				addUnique(exactMatches, exactSeen, player)
			end
		end

		if #exactMatches == 1 then
			return ResultUtil.Ok(found(exactMatches[1]))
		end

		if #exactMatches > 1 then
			return ResultUtil.Ok(failure("ambiguous", query, exactMatches))
		end

		if #normalizedQuery < 3 then
			return ResultUtil.Ok(failure("too_short", query, nil))
		end

		for _, player in ipairs(Players:GetPlayers()) do
			local username = string.lower(player.Name)
			local displayName = string.lower(player.DisplayName)

			if startsWith(username, normalizedQuery) or startsWith(displayName, normalizedQuery) then
				addUnique(prefixMatches, prefixSeen, player)
			end
		end

		if #prefixMatches == 1 then
			return ResultUtil.Ok(found(prefixMatches[1]))
		end

		if #prefixMatches > 1 then
			return ResultUtil.Ok(failure("ambiguous", query, prefixMatches))
		end

		return ResultUtil.Ok(failure("not_found", query, nil))
	end

	function self:resolve(query: string): Result<Player>
		local detailedResult = self:resolveDetailed(query)
		if not detailedResult.ok then
			return ResultUtil.Err(detailedResult.error)
		end

		local value = detailedResult.value
		if value.kind == "found" then
			return ResultUtil.Ok(value.player)
		end

		return ResultUtil.Err((value :: LookupFailure).kind)
	end

	return self
end

return createPlayerLookupService
