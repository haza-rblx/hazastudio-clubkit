--!strict
-- Server/Net/PlayerLookupBatcher.luau
--
-- Join lookups batched (production hardening P3, plan §2 C2). Cash total/rank, group rank and
-- connections count used to cost one VPS GET each per joining player (plus retries); now every
-- caller that asks within LOOKUP_WINDOW_SEC shares one `GET {ApiUrl}/v2/players/lookup` of up to
-- 50 ids (live on the VPS since P2). The call yields until the batch answers, so callers keep
-- their synchronous shape and their own caches (DonationService cash, OverheadService rank,
-- ProfileSocialService connections).
--
-- Falls back cleanly: `lookup` answers (false, "lookup_unavailable") when the batcher is off
-- (Config.BackendClient.LOOKUP_BATCH_ENABLED / ENABLED), the donation API is not configured, or
-- the VPS answered 404/405 (an older VPS) in the last LOOKUP_UNAVAILABLE_TTL_SEC — callers then
-- use their per-user routes exactly as before. Pure parts: Shared/Domain/PlayerLookupBatch.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local BudgetMeter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetMeter)
local PlayerLookupBatch = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.PlayerLookupBatch)
local BackendClient = require(script.Parent.BackendClient)

export type Record = PlayerLookupBatch.Record

type Pending = {
	username: string?,
	wants: { [string]: boolean },
	waiters: { thread },
	answered: boolean,
}

local PlayerLookupBatcher = {}

local pending: { [number]: Pending } = {}
local order: { number } = {}
local flushScheduled = false
-- Bumped by every flush: a timer armed before it no longer fires (no duplicate small batches).
local flushGeneration = 0
local immediateFlushQueued = false
local unavailableUntil = 0

local function cfg(): any
	local c = Config.BackendClient
	return if type(c) == "table" then c else {}
end

local function baseUrl(): string
	local base = Config.Donation and Config.Donation.SHEETS_WEB_APP_URL
	if type(base) ~= "string" or base == "" then
		return ""
	end
	return (string.gsub(base, "/+$", ""))
end

function PlayerLookupBatcher.isAvailable(): boolean
	if cfg().LOOKUP_BATCH_ENABLED ~= true or not BackendClient.isEnabled() then
		return false
	end
	if os.clock() < unavailableUntil then
		return false
	end
	return baseUrl() ~= "" and BackendClient.readSecret("donation") ~= ""
end

local function resumeAll(batch: { { userId: number, entry: Pending } }, answer: (userId: number) -> (boolean, any))
	for _, item in ipairs(batch) do
		if item.entry.answered then
			continue
		end
		item.entry.answered = true
		local ok, value = answer(item.userId)
		for _, waiter in ipairs(item.entry.waiters) do
			task.spawn(waiter, ok, value)
		end
	end
end

local scheduleFlush: (delaySec: number) -> ()

local function flush()
	flushScheduled = false
	flushGeneration += 1
	if #order == 0 then
		return
	end
	local maxIds = math.clamp(math.floor(tonumber(cfg().LOOKUP_MAX_IDS) or 50), 1, PlayerLookupBatch.MAX_IDS)
	local batch: { { userId: number, entry: Pending } } = {}
	local wants: { [string]: boolean } = {}
	while #order > 0 and #batch < maxIds do
		local userId = table.remove(order, 1) :: number
		local entry = pending[userId]
		pending[userId] = nil
		if entry then
			table.insert(batch, { userId = userId, entry = entry })
			for name in pairs(entry.wants) do
				wants[name] = true
			end
		end
	end
	if #order > 0 then
		scheduleFlush(if #order >= maxIds then 0 else (tonumber(cfg().LOOKUP_WINDOW_SEC) or 3))
	end
	if #batch == 0 then
		return
	end

	local entries = table.create(#batch)
	for i, item in ipairs(batch) do
		entries[i] = { userId = item.userId, username = item.entry.username }
	end
	local groupId = tonumber(Config.Group and Config.Group.GROUP_ID) or 0
	local query = PlayerLookupBatch.buildQuery(entries, wants, if wants.group then groupId else nil, BackendClient.urlEncode)
	BudgetMeter.recordEvent("lookup_batch")
	BudgetMeter.recordEvent("lookup_batch_ids", #batch)

	local answered, failure = pcall(function()
		local ok, response = BackendClient.request({
			endpoint = "donation:v2/players/lookup",
			url = baseUrl() .. "/v2/players/lookup?" .. query,
			method = "GET",
			auth = "donation",
			headers = { Accept = "application/json" },
			priority = "bulk",
			timeoutSec = 10,
		})
		if not ok or type(response) ~= "table" then
			local err = tostring(response)
			resumeAll(batch, function()
				return false, err
			end)
			return
		end
		local statusCode = tonumber(response.StatusCode) or 0
		if statusCode == 404 or statusCode == 405 then
			unavailableUntil = os.clock() + (tonumber(cfg().LOOKUP_UNAVAILABLE_TTL_SEC) or 1800)
			BudgetMeter.recordEvent("lookup_unavailable")
			resumeAll(batch, function()
				return false, "lookup_unavailable"
			end)
			return
		end
		if statusCode ~= 200 then
			resumeAll(batch, function()
				return false, "HTTP " .. tostring(statusCode)
			end)
			return
		end
		local decodeOk, decoded = pcall(function()
			return HttpService:JSONDecode(response.Body)
		end)
		local map, parseError = PlayerLookupBatch.parse(if decodeOk then decoded else nil, wants)
		if not map then
			local err = parseError or "bad_body"
			resumeAll(batch, function()
				return false, err
			end)
			return
		end
		resumeAll(batch, function(userId: number)
			local record = map[userId]
			if record then
				return true, record
			end
			return false, "missing"
		end)
	end)
	if not answered then
		-- Never leave a caller suspended: anything that threw above still gets an answer.
		local err = tostring(failure)
		resumeAll(batch, function()
			return false, err
		end)
	end
end

scheduleFlush = function(delaySec: number)
	if flushScheduled then
		return
	end
	flushScheduled = true
	local generation = flushGeneration
	task.delay(delaySec, function()
		if generation == flushGeneration then
			flush()
		end
	end)
end

--- One player's lookup, batched with every other caller in the window. `want` is "cash",
--- "group" or "connections". Yields. Returns (true, Record) or (false, errorString);
--- "lookup_unavailable" means: use the per-user route.
function PlayerLookupBatcher.lookup(userId: number, username: string?, want: string): (boolean, any)
	if not PlayerLookupBatch.isWant(want) or not PlayerLookupBatcher.isAvailable() then
		return false, "lookup_unavailable"
	end
	local entry = pending[userId]
	if not entry then
		entry = { username = nil, wants = {}, waiters = {}, answered = false }
		pending[userId] = entry
		table.insert(order, userId)
	end
	if type(username) == "string" and username ~= "" then
		entry.username = username
	end
	entry.wants[want] = true
	table.insert(entry.waiters, coroutine.running())
	local maxIds = math.clamp(math.floor(tonumber(cfg().LOOKUP_MAX_IDS) or 50), 1, PlayerLookupBatch.MAX_IDS)
	if #order >= maxIds then
		-- A full batch goes now (once); whatever is left waits for a new window. Deferred, so this
		-- caller has yielded before any answer can try to resume it.
		if not immediateFlushQueued then
			immediateFlushQueued = true
			task.defer(function()
				immediateFlushQueued = false
				flush()
			end)
		end
	else
		scheduleFlush(tonumber(cfg().LOOKUP_WINDOW_SEC) or 3)
	end
	return coroutine.yield()
end

return PlayerLookupBatcher
