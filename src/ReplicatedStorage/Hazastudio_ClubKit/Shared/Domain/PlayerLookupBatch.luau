--!strict
-- Shared/Domain/PlayerLookupBatch.luau
--
-- Pure half of Server/Net/PlayerLookupBatcher (production hardening P3, C2). Builds the query of
-- `GET {ApiUrl}/v2/players/lookup` for a window of joins and reads the answer back per player.
-- Contract (live since P2, 2026-09-24): docs/plans/hardening-2026-09-24/p2-deploy-steps.md §8.
--   ids ≤ 50 per request (422 too_many_ids_max_50 beyond), usernames positional ("a,,c"),
--   want = cash,group,connections, groupId optional. Only requested fields come back.
-- No Roblox services: the caller passes the URL encoder (HttpService:UrlEncode in game).

export type Entry = { userId: number, username: string? }

export type GroupAnswer = { ok: boolean, rankId: number?, error: string? }

export type Record = {
	cashKnown: boolean,
	cashTotal: number,
	cashRank: number?,
	groupKnown: boolean,
	group: GroupAnswer?,
	connectionsKnown: boolean,
	connectionsCount: number?,
}

local WANT_ORDER = { "cash", "group", "connections" }
local WANTS: { [string]: boolean } = { cash = true, group = true, connections = true }

local PlayerLookupBatch = {}

PlayerLookupBatch.MAX_IDS = 50

function PlayerLookupBatch.isWant(name: string): boolean
	return WANTS[name] == true
end

--- Splits `ids` into lists of at most `max`, keeping order.
function PlayerLookupBatch.chunk(ids: { number }, max: number): { { number } }
	local size = math.max(1, math.floor(max))
	local out: { { number } } = {}
	local current: { number } = {}
	for _, id in ipairs(ids) do
		table.insert(current, id)
		if #current >= size then
			table.insert(out, current)
			current = {}
		end
	end
	if #current > 0 then
		table.insert(out, current)
	end
	return out
end

--- Query string (no leading "?"). `wants` is a set; `urlEncode` escapes one value.
function PlayerLookupBatch.buildQuery(
	entries: { Entry },
	wants: { [string]: boolean },
	groupId: number?,
	urlEncode: (string) -> string
): string
	local ids = table.create(#entries)
	local names = table.create(#entries)
	local anyName = false
	for i, entry in ipairs(entries) do
		ids[i] = tostring(math.floor(entry.userId))
		local name = entry.username
		if type(name) == "string" and name ~= "" then
			names[i] = urlEncode(name)
			anyName = true
		else
			names[i] = ""
		end
	end
	local parts = { "ids=" .. table.concat(ids, ",") }
	if anyName then
		table.insert(parts, "usernames=" .. table.concat(names, ","))
	end
	local wantList = {}
	for _, name in ipairs(WANT_ORDER) do
		if wants[name] then
			table.insert(wantList, name)
		end
	end
	if #wantList > 0 then
		table.insert(parts, "want=" .. table.concat(wantList, ","))
	end
	if type(groupId) == "number" and groupId > 0 then
		table.insert(parts, "groupId=" .. tostring(math.floor(groupId)))
	end
	return table.concat(parts, "&")
end

local function readGroup(raw: any): GroupAnswer?
	if type(raw) ~= "table" then
		return nil
	end
	return {
		ok = raw.ok == true,
		rankId = tonumber(raw.rankId),
		error = if type(raw.error) == "string" then raw.error else nil,
	}
end

--- Decoded JSON body → map userId → Record, or (nil, errorCode).
--- A field asked for but answered JSON null (absent after decode) is known-empty: the VPS has
--- no value (connectionsCount not pushed yet); a field not asked for is never known.
function PlayerLookupBatch.parse(decoded: any, wants: { [string]: boolean }): ({ [number]: Record }?, string?)
	if type(decoded) ~= "table" then
		return nil, "bad_body"
	end
	if decoded.ok ~= true then
		return nil, if type(decoded.error) == "string" then decoded.error else "bad_body"
	end
	if type(decoded.players) ~= "table" then
		return nil, "bad_body"
	end
	local out: { [number]: Record } = {}
	for _, row in ipairs(decoded.players) do
		if type(row) ~= "table" then
			continue
		end
		local userId = tonumber(row.user_id)
		if not userId or userId <= 0 then
			continue
		end
		local total = tonumber(row.cash_total)
		local rank = tonumber(row.cash_rank)
		local group = readGroup(row.group)
		local count = tonumber(row.connectionsCount)
		out[userId] = {
			cashKnown = wants.cash == true and total ~= nil,
			cashTotal = if total and total > 0 then math.floor(total) else 0,
			cashRank = if rank and rank >= 1 then math.floor(rank) else nil,
			groupKnown = wants.group == true and group ~= nil,
			group = group,
			connectionsKnown = wants.connections == true,
			connectionsCount = count,
		}
	end
	return out, nil
end

return PlayerLookupBatch
