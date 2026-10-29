--!strict
-- Daily Robux donor totals shared by every server (the "THE DAILY SPENDERS" boards).
--
-- One MemoryStore SortedMap per WIB day: key = userId, sortKey = the day's total,
-- value = { t = total, a = last donation unix, u = username, d = displayName,
-- th = thumbnail, p = recent purchaseIds }. Before this the total lived only in the
-- memory of the server that processed the receipt: other servers never showed it and
-- a restart or publish wiped it. MemoryStore (not DataStore) because the combined board
-- also needs the time of the last donation, and the map expires by itself.
--
-- Every call is pcall-wrapped and reports failure; DonationService keeps its in-memory
-- copy as the fallback.

local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

export type DailyRobuxRow = {
	userId: number,
	total: number,
	lastDonationAt: number,
	username: string,
	displayName: string,
	thumbnail: string,
}

export type DailyRobuxRecord = {
	userId: number,
	amount: number,
	at: number,
	purchaseId: string?,
	username: string?,
	displayName: string?,
	thumbnail: string?,
}

-- Two days so a map outlives its own day, then disappears.
local EXPIRATION_SEC = 2 * 86400
-- Purchase ids kept per donor per day: a re-run of the same receipt is not counted twice.
local MAX_PURCHASE_IDS = 20
local MAX_TEXT = 512

local DailyRobuxRepository = {}

local function storePrefix(): string
	local name = (Config.Leaderboards :: any).DAILY_ROBUX_STORE_NAME
	return if type(name) == "string" and name ~= "" then name else "ClubKitDailyRobux_v1"
end

local function mapFor(dayNumber: number): any
	return MemoryStoreService:GetSortedMap(storePrefix() .. "_" .. tostring(dayNumber))
end

local function clampText(value: any): string
	if type(value) ~= "string" then
		return ""
	end
	return string.sub(value, 1, MAX_TEXT)
end

function DailyRobuxRepository.record(dayNumber: number, record: DailyRobuxRecord): (boolean, string?)
	local amount = math.floor(tonumber(record.amount) or 0)
	if record.userId <= 0 or amount <= 0 then
		return false, "invalid_record"
	end
	local ok, err = pcall(function()
		mapFor(dayNumber):UpdateAsync(tostring(record.userId), function(old: any, _oldSortKey: any): (any, any)
			local current = if type(old) == "table" then old else {}
			local purchaseIds: { string } = if type(current.p) == "table" then table.clone(current.p) else {}
			local purchaseId = record.purchaseId
			if type(purchaseId) == "string" and purchaseId ~= "" then
				if table.find(purchaseIds, purchaseId) then
					return nil -- already counted: abort the update
				end
				table.insert(purchaseIds, purchaseId)
				while #purchaseIds > MAX_PURCHASE_IDS do
					table.remove(purchaseIds, 1)
				end
			end
			local total = (tonumber(current.t) or 0) + amount
			local nextValue = {
				t = total,
				a = math.max(tonumber(current.a) or 0, math.floor(record.at)),
				u = if record.username and record.username ~= "" then clampText(record.username) else clampText(current.u),
				d = if record.displayName and record.displayName ~= ""
					then clampText(record.displayName)
					else clampText(current.d),
				th = if record.thumbnail and record.thumbnail ~= ""
					then clampText(record.thumbnail)
					else clampText(current.th),
				p = purchaseIds,
			}
			return nextValue, total
		end, EXPIRATION_SEC)
	end)
	if not ok then
		return false, tostring(err)
	end
	return true, nil
end

-- Highest totals first. Returns nil when MemoryStore could not be read.
function DailyRobuxRepository.list(dayNumber: number, limit: number): { DailyRobuxRow }?
	local count = math.clamp(math.floor(limit), 1, 200)
	local ok, items = pcall(function()
		return mapFor(dayNumber):GetRangeAsync(Enum.SortDirection.Descending, count)
	end)
	if not ok or type(items) ~= "table" then
		return nil
	end
	local rows: { DailyRobuxRow } = {}
	for _, item in ipairs(items) do
		local value = item.value
		local userId = tonumber(item.key) or 0
		if userId > 0 and type(value) == "table" then
			table.insert(rows, {
				userId = userId,
				total = tonumber(value.t) or 0,
				lastDonationAt = tonumber(value.a) or 0,
				username = clampText(value.u),
				displayName = clampText(value.d),
				thumbnail = clampText(value.th),
			})
		end
	end
	return rows
end

return DailyRobuxRepository
