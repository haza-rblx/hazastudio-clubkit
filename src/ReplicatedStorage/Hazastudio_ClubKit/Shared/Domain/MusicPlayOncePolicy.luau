--!strict
-- PATH: ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/MusicPlayOncePolicy.luau
-- Pure rules for a play-once request (3.0, ADR 0010 addendum 2026-09-14): a pasted Roblox audio
-- asset ID queued for one play and never written to the library. No Roblox APIs.

local MusicPlayOncePolicy = {}

export type Limits = { maxPending: number, maxPerWindow: number, windowSeconds: number }

export type Input = {
	mode: string?, -- ClubKitConfig.Music.PlayOnceRequest: "everyone" | "control" | "off"
	isControl: boolean, -- holds musicControl
	pendingCount: number, -- this player's play-once tracks still waiting in the queue
	recentRequestTimes: { number }, -- this player's accepted requests, any age
	now: number,
	limits: Limits,
}

export type Decision = { allowed: boolean, reason: string, retryAfter: number? }

function MusicPlayOncePolicy.evaluate(input: Input): Decision
	local mode = input.mode
	if mode == "off" then
		return { allowed = false, reason = "disabled" }
	end
	if mode == "control" and not input.isControl then
		return { allowed = false, reason = "control_only" }
	end
	-- Holders of musicControl are exempt from both limits (owner, 2026-09-14).
	if input.isControl then
		return { allowed = true, reason = "" }
	end

	local limits = input.limits
	if input.pendingCount >= limits.maxPending then
		return { allowed = false, reason = "pending_limit" }
	end

	-- A request counts while it is younger than the window; one exactly windowSeconds old has aged out.
	local inWindow = 0
	local oldest: number? = nil
	for _, requestedAt in ipairs(input.recentRequestTimes) do
		if input.now - requestedAt < limits.windowSeconds then
			inWindow += 1
			if oldest == nil or requestedAt < oldest then
				oldest = requestedAt
			end
		end
	end
	if inWindow >= limits.maxPerWindow then
		local retryAfter = if oldest then math.max(0, oldest + limits.windowSeconds - input.now) else limits.windowSeconds
		return { allowed = false, reason = "rate_limited", retryAfter = retryAfter }
	end

	return { allowed = true, reason = "" }
end

-- Whether a player sees the Request From ID box at all; the limits are checked per request.
function MusicPlayOncePolicy.isOffered(mode: string?, isControl: boolean): boolean
	if mode == "off" then
		return false
	end
	if mode == "control" then
		return isControl == true
	end
	return true
end

local AUDIO_ASSET_TYPE_ID = 3 -- Enum.AssetType.Audio.Value (checked in a live server, 2026-09-14)
local ID_PREFIX = "playonce:"

export type BuildInput = {
	assetId: string,
	productInfo: any?, -- MarketplaceService:GetProductInfoAsync(assetId, Enum.InfoType.Asset), nil when it failed
	guid: string,
	now: number,
}

function MusicPlayOncePolicy.isPlayOnceId(trackId: string?): boolean
	return type(trackId) == "string" and string.sub(trackId, 1, #ID_PREFIX) == ID_PREFIX
end

-- The in-memory track a play-once request plays. Returns (nil, reason) when it must not be played.
function MusicPlayOncePolicy.buildTrack(input: BuildInput): (any?, string)
	local assetId = input.assetId
	if type(assetId) ~= "string" or not string.match(assetId, "^%d+$") then
		return nil, "invalid_asset_id"
	end
	local info = input.productInfo
	-- Every player may request, so an asset whose type cannot be confirmed is not played.
	if type(info) ~= "table" then
		return nil, "asset_unverified"
	end
	if info.AssetTypeId ~= AUDIO_ASSET_TYPE_ID then
		return nil, "asset_not_audio"
	end

	local name = if type(info.Name) == "string" and info.Name ~= "" then info.Name else "Audio " .. assetId
	local creatorInfo = info.Creator
	local creator = if type(creatorInfo) == "table" and type(creatorInfo.Name) == "string" and creatorInfo.Name ~= ""
		then creatorInfo.Name
		else "Unknown"

	return {
		id = ID_PREFIX .. input.guid,
		name = name,
		creator = creator,
		playlistId = "",
		parts = { assetId },
		totalDuration = 0,
		-- ADR 0010: an asset that never went through a bypass recipe plays at 1.0, stated explicitly.
		playbackSpeed = 1,
		coverType = "image",
		coverValue = ("rbxthumb://type=Asset&id=%s&w=150&h=150"):format(assetId),
		createdAt = input.now,
		updatedAt = input.now,
	}, ""
end

return MusicPlayOncePolicy
