--!strict
-- Server/Services/EventBoardProvider.luau
-- Event board (ADR 0015): pulls the venue's posts and quests from {Donation.ApiUrl}/v3/event-board
-- and keeps polling (ETag, so an unchanged board is a bodyless 304). Boots from a DataStore copy of
-- the last good board, and only a well-formed 200 replaces it — an outage, a 403 or a broken body
-- keeps what players already see (the MusicLibraryProvider pattern, ADR 0010).

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local EventBoardDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.EventBoardDomain)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local BackendClient = require(script.Parent.Parent.Net.BackendClient)
local GlobalDocWriter = require(script.Parent.Parent.Persistence.GlobalDocWriter)

type Board = EventBoardDomain.Board

local CACHE_DOC = "board"
local FAILURE_LOG_INTERVAL_SECONDS = 300

local EventBoardProvider = {}
EventBoardProvider.__index = EventBoardProvider

local function readSecret(): string
	return BackendClient.readSecret("donation")
end

function EventBoardProvider.new(deps: { logger: any?, onBoard: (board: Board) -> () })
	return setmetatable({
		_log = deps.logger or Logger.new("EventBoardProvider"),
		_onBoard = deps.onBoard,
		_board = EventBoardDomain.emptyBoard(),
		_raw = nil :: any,
		_failures = 0,
		_lastWarnAt = {} :: { [string]: number },
		_thread = nil :: thread?,
		_destroyed = false,
		_store = nil :: DataStore?,
	}, EventBoardProvider)
end

function EventBoardProvider:getBoard(): Board
	return self._board
end

function EventBoardProvider:_warn(reason: string, fields: { [string]: any })
	local now = os.clock()
	local last = self._lastWarnAt[reason]
	if last and now - last < FAILURE_LOG_INTERVAL_SECONDS then
		return
	end
	self._lastWarnAt[reason] = now
	self._log:warn("Event board kept the current board", fields)
end

function EventBoardProvider:_cacheStore(): DataStore?
	if self._store then
		return self._store
	end
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(Config.EventBoard.CACHE_KEY)
	end)
	if ok then
		self._store = store
		return store
	end
	return nil
end

function EventBoardProvider:_apply(raw: any, fromCache: boolean): boolean
	local board = EventBoardDomain.readBoard(raw)
	if not board then
		return false
	end
	self._board = board
	self._raw = raw
	self._onBoard(board)
	if not fromCache then
		local fetchedAt = os.time()
		task.spawn(function()
			local store = self:_cacheStore()
			if not store then
				return
			end
			if GlobalDocWriter.isEnabled() then
				-- Production hardening P3 (B): the sanitized board in the VPS's raw shape, written once
				-- per revision per experience (other servers' attempts cancel).
				GlobalDocWriter.writeIfNewer({
					store = store :: DataStore,
					key = CACHE_DOC,
					value = EventBoardDomain.serializeBoard(board),
					revision = board.revision,
					fetchedAt = fetchedAt,
					label = "event_board",
				})
				return
			end
			pcall(function()
				(store :: DataStore):SetAsync(CACHE_DOC, raw)
			end)
		end)
	end
	return true
end

function EventBoardProvider:_loadCache()
	local store = self:_cacheStore()
	if not store then
		return
	end
	local ok, raw = pcall(function()
		return (store :: DataStore):GetAsync(CACHE_DOC)
	end)
	if ok and raw ~= nil then
		self:_apply(raw, true)
	end
end

function EventBoardProvider:_endpoint(): (string?, string?)
	local base = Config.Donation and Config.Donation.SHEETS_WEB_APP_URL
	local secret = readSecret()
	if type(base) ~= "string" or base == "" or secret == "" then
		return nil, nil
	end
	return (base:gsub("/+$", "")) .. Config.EventBoard.PATH, secret
end

-- "applied" | "unchanged" | "kept"
function EventBoardProvider:refresh(): string
	local url, secret = self:_endpoint()
	if not url or not secret or not HttpService.HttpEnabled then
		self._failures += 1
		self:_warn("not_configured", { reason = "not_configured" })
		return "kept"
	end
	local headers: { [string]: string } = { Accept = "application/json" }
	if self._board.revision ~= "" then
		headers["If-None-Match"] = '"' .. self._board.revision .. '"'
	end
	-- Secret as Authorization: Bearer (BackendClient adds it), normal priority.
	local ok, response = BackendClient.request({
		endpoint = "eventboard:board",
		url = url,
		method = "GET",
		auth = "donation",
		headers = headers,
		priority = "normal",
	})
	if not ok or type(response) ~= "table" then
		self._failures += 1
		self:_warn("request_failed", { reason = "request_failed", error = tostring(response) })
		return "kept"
	end
	local status = tonumber(response.StatusCode) or 0
	if status == 304 then
		self._failures = 0
		return "unchanged"
	end
	if status ~= 200 then
		self._failures += 1
		self:_warn("status_" .. status, { reason = "http_status", status = status })
		return "kept"
	end
	local decodeOk, body = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)
	if not decodeOk or type(body) ~= "table" or body.ok ~= true then
		self._failures += 1
		self:_warn("bad_body", { reason = "bad_body" })
		return "kept"
	end
	if body.revision == self._board.revision then
		self._failures = 0
		return "unchanged"
	end
	if not self:_apply(body, false) then
		self._failures += 1
		self:_warn("bad_shape", { reason = "bad_shape" })
		return "kept"
	end
	self._failures = 0
	self._log:info("Event board applied", {
		revision = self._board.revision,
		posts = #self._board.posts,
		quests = #self._board.quests,
	})
	return "applied"
end

function EventBoardProvider:_nextPollSeconds(): number
	local base = Config.EventBoard.POLL_SECONDS
	if self._failures <= 0 then
		return base
	end
	return math.min(Config.EventBoard.POLL_MAX_SECONDS, base * 2 ^ math.min(self._failures, 4))
end

function EventBoardProvider:start()
	if self._thread then
		return
	end
	self._thread = task.spawn(function()
		self:_loadCache()
		while not self._destroyed do
			local ok, err = pcall(function()
				self:refresh()
			end)
			if not ok then
				self._failures += 1
				self._log:error("Event board refresh threw", { error = tostring(err) })
			end
			if self._destroyed then
				break
			end
			task.wait(self:_nextPollSeconds())
		end
	end)
end

function EventBoardProvider:destroy()
	self._destroyed = true
	if self._thread then
		pcall(task.cancel, self._thread)
		self._thread = nil
	end
end

return EventBoardProvider
