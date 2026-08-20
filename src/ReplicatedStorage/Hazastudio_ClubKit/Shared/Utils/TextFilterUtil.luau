--!strict
-- TextFilterUtil — canonical Roblox text filtering for the Club Kit.
--
-- EVERY free-form text that is stored or replicated for display to other
-- players MUST pass through this module (Roblox ToS / moderation safety).
-- Policy details: docs/adr/0004-text-filtering-policy.md.
--
-- Rules encoded here:
--   * Server-side only (all calls yield; never call from client code).
--   * Author userId must be the player who WROTE the text (age context),
--     not the viewer.
--   * filterForBroadcast = one filtered string safe for everyone
--     (GetNonChatStringForBroadcastAsync).
--   * filterForUser = per-recipient string (GetNonChatStringForUserAsync)
--     for re-displaying stored text to a specific viewer.
--   * Returns nil when input is empty/invalid or filtering fails — callers
--     decide the fallback (reject, hashFallback, or drop). Log at the caller
--     so each surface keeps its own context tags.
--
-- Roblox DisplayName/Username are platform-moderated at source and are
-- intentionally NOT routed through here (ADR 0004, decision D1).

local TextService = game:GetService("TextService")
local GroupService = game:GetService("GroupService")

local TextFilterUtil = {}

local DEFAULT_RETRIES = 3
local RETRY_BACKOFF_SEC = 0.35

-- Cached place-owner userId for filter author context (group-owned places).
local cachedOwnerUserId: number? = nil

-- Yielding: resolve a VALID filter-author userId for owner-published text.
-- `game.CreatorId` is a GROUP id on group-owned places, and passing a group id to
-- FilterStringAsync makes filtering fail (every name falls back to "#####").
-- For user-owned places the creator IS the user; for group-owned places we resolve
-- the group owner's userId via GroupService (memoized). Returns nil if unresolvable.
function TextFilterUtil.resolveFilterAuthorUserId(): number?
	if game.CreatorType == Enum.CreatorType.User then
		local id = tonumber(game.CreatorId) or 0
		return if id > 0 then id else nil
	end
	-- Group-owned place
	if cachedOwnerUserId and cachedOwnerUserId > 0 then
		return cachedOwnerUserId
	end
	local ok, info = pcall(function()
		return GroupService:GetGroupInfoAsync(game.CreatorId)
	end)
	if ok and type(info) == "table" and type(info.Owner) == "table" then
		local ownerId = tonumber(info.Owner.Id) or 0
		if ownerId > 0 then
			cachedOwnerUserId = ownerId
			return ownerId
		end
	end
	return nil
end

-- Pure: trim + clamp. Returns nil when empty after trim.
function TextFilterUtil.normalize(text: string?, maxLength: number?): string?
	if type(text) ~= "string" then
		return nil
	end
	local trimmed = text:match("^%s*(.-)%s*$") or ""
	if trimmed == "" then
		return nil
	end
	if maxLength and maxLength > 0 then
		trimmed = string.sub(trimmed, 1, maxLength)
	end
	if trimmed == "" then
		return nil
	end
	return trimmed
end

-- Pure: '#' fallback so a filter failure never leaks raw text
-- (port of DonationService.censoredMessageFallback).
function TextFilterUtil.hashFallback(text: string): string
	local length = math.clamp(#text, 5, 24)
	return string.rep("#", length)
end

-- Yielding: filter text authored by `authorUserId` for broadcast to ALL players.
-- Returns the filtered string, or nil when input is empty or filtering failed
-- after `retries` attempts (with linear backoff).
function TextFilterUtil.filterForBroadcast(
	authorUserId: number?,
	text: string?,
	maxLength: number?,
	retries: number?
): string?
	local trimmed = TextFilterUtil.normalize(text, maxLength)
	if not trimmed or not authorUserId or authorUserId <= 0 then
		return nil
	end
	local attempts = math.max(1, math.floor(tonumber(retries) or DEFAULT_RETRIES))
	for attempt = 1, attempts do
		local ok, filtered = pcall(function()
			local result = TextService:FilterStringAsync(
				trimmed :: string,
				authorUserId :: number,
				Enum.TextFilterContext.PublicChat
			)
			return result:GetNonChatStringForBroadcastAsync()
		end)
		if ok and type(filtered) == "string" and filtered ~= "" then
			return filtered
		end
		if attempt < attempts then
			task.wait(RETRY_BACKOFF_SEC * attempt)
		end
	end
	return nil
end

-- Yielding: filter text authored by `authorUserId` for display to ONE viewer.
-- Author must be the writer (not the viewer) so age-appropriateness follows
-- the writer's account settings.
-- Returns the filtered string, or nil when input is empty or filtering failed.
function TextFilterUtil.filterForUser(
	authorUserId: number?,
	viewerUserId: number,
	text: string?,
	maxLength: number?,
	retries: number?
): string?
	local trimmed = TextFilterUtil.normalize(text, maxLength)
	if not trimmed then
		return nil
	end
	local author = if authorUserId and authorUserId > 0 then authorUserId else viewerUserId
	local attempts = math.max(1, math.floor(tonumber(retries) or DEFAULT_RETRIES))
	for attempt = 1, attempts do
		local okFilter, filterResult = pcall(function()
			return TextService:FilterStringAsync(trimmed :: string, author)
		end)
		if not okFilter or filterResult == nil then
			if attempt < attempts then
				task.wait(RETRY_BACKOFF_SEC * attempt)
			end
			continue
		end
		local okGet, filtered = pcall(function()
			return (filterResult :: any):GetNonChatStringForUserAsync(viewerUserId)
		end)
		if okGet and type(filtered) == "string" and filtered ~= "" then
			return filtered
		end
		if attempt < attempts then
			task.wait(RETRY_BACKOFF_SEC * attempt)
		end
	end
	return nil
end

return TextFilterUtil
