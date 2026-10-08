--!strict
-- Server/Services/EventQuestBackend.luau
-- Quest milestones (docs/plans/quest-milestones-2026-10-08.md): the VPS side of a milestone claim
-- and of the daily check-in log, under {Donation.ApiUrl}:
--   GET  /v3/event-quota            slots claimed per quota milestone (polled while one is running)
--   POST /v3/event-claims           records a claim; the VPS owns quota + one-Robux-per-quest
--   POST /v3/event-claims/release   undoes a recorded claim whose in-game grant failed
--   POST /v3/event-checkins         batched daily check-ins for the dashboard log
-- Same auth as the event board (the donation secret as Bearer).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local BackendClient = require(script.Parent.Parent.Net.BackendClient)

export type QuotaEntry = { claimed: number, quota: number }
export type ClaimResult = { ok: boolean, slot: number?, reason: string? }
export type CheckInEntry = {
	questId: number,
	userId: number,
	username: string,
	displayName: string,
	day: string,
	streak: number,
}

local EventQuestBackend = {}
EventQuestBackend.__index = EventQuestBackend

function EventQuestBackend.new(deps: { logger: any?, onQuota: (() -> ())? })
	return setmetatable({
		_log = deps.logger or Logger.new("EventQuestBackend"),
		_onQuota = deps.onQuota,
		_quota = {} :: { [number]: QuotaEntry },
		_queue = {} :: { CheckInEntry },
		_destroyed = false,
		_threads = {} :: { thread },
		_wantQuota = false,
		_lastWarnAt = {} :: { [string]: number },
	}, EventQuestBackend)
end

function EventQuestBackend:_warn(reason: string, fields: { [string]: any })
	local now = os.clock()
	local last = self._lastWarnAt[reason]
	if last and now - last < 300 then
		return
	end
	self._lastWarnAt[reason] = now
	self._log:warn("Event quest backend: " .. reason, fields)
end

local function url(path: string): string?
	local base = Config.Donation and Config.Donation.SHEETS_WEB_APP_URL
	if type(base) ~= "string" or base == "" or BackendClient.readSecret("donation") == "" then
		return nil
	end
	return (base:gsub("/+$", "")) .. path
end

-- (ok, decoded body | error) — ok only for a 2xx with a JSON object body.
function EventQuestBackend:_call(endpoint: string, path: string, method: string, payload: any?, priority: string?): (boolean, any)
	local target = url(path)
	if not target or not HttpService.HttpEnabled then
		return false, "not_configured"
	end
	local ok, response = BackendClient.request({
		endpoint = endpoint,
		url = target,
		method = method,
		auth = "donation",
		headers = { Accept = "application/json", ["Content-Type"] = "application/json" },
		body = if payload ~= nil then HttpService:JSONEncode(payload) else nil,
		priority = priority or "normal",
	})
	if not ok or type(response) ~= "table" then
		return false, tostring(response)
	end
	local status = tonumber(response.StatusCode) or 0
	local decodeOk, body = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)
	if status < 200 or status >= 300 then
		return false, if decodeOk and type(body) == "table" then body else "http_" .. status
	end
	if not decodeOk or type(body) ~= "table" then
		return false, "bad_body"
	end
	return true, body
end

-- Slots left on a quota milestone as last heard, or nil (no quota / not heard yet).
function EventQuestBackend:remaining(milestoneId: number): number?
	local entry = self._quota[milestoneId]
	if not entry then
		return nil
	end
	return math.max(0, entry.quota - entry.claimed)
end

function EventQuestBackend:quotaOf(milestoneId: number): QuotaEntry?
	return self._quota[milestoneId]
end

-- Main calls this on every board change: poll only while a running quest has a quota.
function EventQuestBackend:setQuotaWanted(wanted: boolean)
	self._wantQuota = wanted
end

function EventQuestBackend:refreshQuota(): boolean
	local ok, body = self:_call("eventboard:quota", Config.EventBoard.QUOTA_PATH, "GET", nil, "normal")
	if not ok or type(body.milestones) ~= "table" then
		self:_warn("quota_failed", { error = if type(body) == "string" then body else "bad_shape" })
		return false
	end
	local next: { [number]: QuotaEntry } = {}
	local changed = false
	for key, raw in pairs(body.milestones) do
		local id = tonumber(key)
		if id and type(raw) == "table" and type(raw.claimed) == "number" and type(raw.quota) == "number" then
			next[id] = { claimed = math.max(0, math.floor(raw.claimed)), quota = math.max(0, math.floor(raw.quota)) }
			local before = self._quota[id]
			if not before or before.claimed ~= next[id].claimed or before.quota ~= next[id].quota then
				changed = true
			end
		end
	end
	for id in pairs(self._quota) do
		if not next[id] then
			changed = true
		end
	end
	self._quota = next
	if changed and self._onQuota then
		self._onQuota()
	end
	return true
end

-- Records one claim. `reason` on refusal: "quota_full" | "robux_taken" | "inactive" |
-- "not_found" | "unavailable" (VPS unreachable or a broken answer — the player may retry).
function EventQuestBackend:claim(questId: number, milestoneId: number, player: Player): ClaimResult
	local ok, body = self:_call("eventboard:claim", Config.EventBoard.CLAIM_PATH, "POST", {
		questId = questId,
		milestoneId = milestoneId,
		userId = player.UserId,
		username = player.Name,
		displayName = player.DisplayName,
	}, "critical")
	if type(body) == "table" and body.ok == false and type(body.reason) == "string" then
		local reason = body.reason
		-- Keep the cached count honest after a refusal for a full quota.
		if reason == "quota_full" then
			local entry = self._quota[milestoneId]
			if entry then
				entry.claimed = math.max(entry.claimed, entry.quota)
			end
		end
		return { ok = false, reason = reason }
	end
	if not ok or type(body) ~= "table" or body.ok ~= true then
		self:_warn("claim_failed", { questId = questId, milestoneId = milestoneId, error = tostring(body) })
		return { ok = false, reason = "unavailable" }
	end
	local slot = if type(body.slot) == "number" then math.floor(body.slot) else nil
	if type(body.claimed) == "number" and type(body.quota) == "number" then
		self._quota[milestoneId] = { claimed = math.floor(body.claimed), quota = math.floor(body.quota) }
	end
	return { ok = true, slot = slot }
end

function EventQuestBackend:release(questId: number, milestoneId: number, userId: number): boolean
	local ok = self:_call("eventboard:release", Config.EventBoard.CLAIM_RELEASE_PATH, "POST", {
		questId = questId,
		milestoneId = milestoneId,
		userId = userId,
	}, "critical")
	return ok
end

function EventQuestBackend:logCheckIn(entry: CheckInEntry)
	table.insert(self._queue, entry)
	local extra = #self._queue - Config.EventBoard.CHECKIN_LOG_MAX_QUEUE
	if extra > 0 then
		table.move(self._queue, extra + 1, #self._queue, 1)
		for index = #self._queue, #self._queue - extra + 1, -1 do
			self._queue[index] = nil
		end
	end
end

function EventQuestBackend:flushCheckIns(): boolean
	if #self._queue == 0 then
		return true
	end
	local count = math.min(#self._queue, Config.EventBoard.CHECKIN_LOG_MAX_BATCH)
	local batch = table.move(self._queue, 1, count, 1, {})
	local ok = self:_call("eventboard:checkins", Config.EventBoard.CHECKIN_LOG_PATH, "POST", { entries = batch }, "bulk")
	if not ok then
		self:_warn("checkin_log_failed", { pending = #self._queue })
		return false
	end
	table.move(self._queue, count + 1, #self._queue + count, 1)
	return #self._queue == 0
end

function EventQuestBackend:start()
	table.insert(self._threads, task.spawn(function()
		while not self._destroyed do
			if self._wantQuota then
				pcall(function()
					self:refreshQuota()
				end)
			end
			task.wait(Config.EventBoard.QUOTA_POLL_SECONDS)
		end
	end))
	table.insert(self._threads, task.spawn(function()
		while not self._destroyed do
			task.wait(Config.EventBoard.CHECKIN_LOG_FLUSH_SECONDS)
			pcall(function()
				self:flushCheckIns()
			end)
		end
	end))
end

-- Shutdown: one last attempt at the check-in log.
function EventQuestBackend:destroy()
	self._destroyed = true
	for _, thread in ipairs(self._threads) do
		pcall(task.cancel, thread)
	end
	table.clear(self._threads)
	pcall(function()
		self:flushCheckIns()
	end)
end

return EventQuestBackend
