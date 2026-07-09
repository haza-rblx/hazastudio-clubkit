--!strict
-- Client-side thumbnail cache (quota-efficiency-pass-2026-06, Phase 2, task 2.3).
-- Wrap Cache.luau dengan API specialized untuk thumbnail, plus in-flight dedup.
--
-- Cache key: "thumb:" .. userId .. ":" .. thumbType.Name .. ":" .. thumbSize.Name
-- TTL: 600s default (Config.ClientHttpApi.GET_THUMB_TTL)
-- In-flight dedup: BindableEvent per cache key (mirrors HttpApi.luau pattern).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Cache = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Cache)

local inFlight: { [string]: BindableEvent } = {}

local ClientThumbnailCache = {}

local function makeKey(userId: number, thumbType: Enum.ThumbnailType, thumbSize: Enum.ThumbnailSize): string
	return ("thumb:%d:%s:%s"):format(userId, thumbType.Name, thumbSize.Name)
end

local function getInflightWaitSec(): number
	if type(Config.ClientHttpApi) == "table" then
		return math.max(1, tonumber(Config.ClientHttpApi.THUMB_INFLIGHT_WAIT_SEC) or 15)
	end
	return 15
end

local function waitForInflight(key: string): string?
	local deadline = os.clock() + getInflightWaitSec()
	while inFlight[key] and os.clock() < deadline do
		local cached = Cache.get(key)
		if cached ~= nil then
			return cached :: string
		end
		task.wait(0.05)
	end
	return Cache.get(key) :: string?
end

-- Get cached thumbnail URL/content. If ENABLED=false, returns nil (caller falls back
-- to direct Players:GetUserThumbnailAsync). If ENABLED=true, returns cached or
-- triggers fetch with in-flight dedup.
--
-- Return shape: (string?, boolean) — (content, fromCache)
--   - (nil, false) when ENABLED=false or no cache + no fetch
--   - (cachedContent, true) when cache hit
--   - (fetchedContent, false) when fetched + cached
function ClientThumbnailCache.get(
	userId: number,
	thumbType: Enum.ThumbnailType,
	thumbSize: Enum.ThumbnailSize
): (string?, boolean)
	if not (Config.ClientHttpApi and Config.ClientHttpApi.ENABLED) then
		return nil, false
	end

	local key = makeKey(userId, thumbType, thumbSize)

	-- Cache check
	local cached = Cache.get(key)
	if cached ~= nil then
		return cached :: string, true
	end

	-- In-flight dedup (bounded wait — avoids permanent yield if leader hangs)
	if inFlight[key] then
		local afterWait = waitForInflight(key)
		if afterWait ~= nil then
			return afterWait, true
		end
	end

	-- Register in-flight
	local event = Instance.new("BindableEvent")
	inFlight[key] = event

	local Players = game:GetService("Players")
	local ok, content = pcall(function()
		return Players:GetUserThumbnailAsync(userId, thumbType, thumbSize)
	end)

	if inFlight[key] == event then
		inFlight[key] = nil
	end
	event:Fire()
	event:Destroy()

	if ok and type(content) == "string" and content ~= "" then
		Cache.set(key, content, Config.ClientHttpApi.GET_THUMB_TTL)
		return content, false
	end
	return nil, false
end

-- Direct get-or-fetch: returns the URL string whenever possible.
-- Path A (ENABLED=true): cache → fallback ke direct fetch kalau cache miss/fail.
-- Path B (ENABLED=false): cache layer off → langsung direct fetch.
-- Returns nil hanya kalau direct fetch juga gagal (invalid userId / API throttled).
function ClientThumbnailCache.getOrFetch(
	userId: number,
	thumbType: Enum.ThumbnailType,
	thumbSize: Enum.ThumbnailSize
): string?
	local url = ClientThumbnailCache.get(userId, thumbType, thumbSize)
	if url then
		return url
	end
	-- Fallback ke direct fetch. get() bisa return nil di dua kondisi:
	--   1. ENABLED=false (cache layer off)
	--   2. ENABLED=true tapi API call di pcall gagal
	-- Tanpa fallback ini, caller (mis. DonationNotificationController)
	-- akan dapat nil dan thumbnail ImageLabel kosong.
	local Players = game:GetService("Players")
	local ok, content = pcall(function()
		return Players:GetUserThumbnailAsync(userId, thumbType, thumbSize)
	end)
	if ok and type(content) == "string" and content ~= "" then
		return content
	end
	return nil
end

-- Invalidate specific user's thumbnail cache (e.g. after avatar change)
function ClientThumbnailCache.invalidate(_userId: number)
	-- Best effort: prefix invalidation not supported by Cache.luau, scan keys
	-- Not implemented here — relies on TTL expiry. Add explicit invalidation if needed.
end

return ClientThumbnailCache
