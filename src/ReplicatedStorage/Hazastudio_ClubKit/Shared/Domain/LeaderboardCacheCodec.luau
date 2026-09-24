--!strict
-- Shared/Domain/LeaderboardCacheCodec.luau
--
-- MemoryStore leaderboard cache v2 (production hardening P3, A7). v1 (map "ClubKitLeaderboardCache")
-- stored every built board per limit with names and thumbnails — 15–25 KB per Robux top 100,
-- 60–100 KB in total, over the 64 KB + 1 KB/player quota at low player counts. v2 (map
-- "ClubKitLeaderboardCache_v2", so old and new row shapes never mix) stores one item per board:
--   { v = 2, n = <limit it was built for>, r = { id1, total1, id2, total2, … } }
-- ≤ maxBytes (4 KB), ids and totals only; names come from the server's own metadata cache.
-- An item built for limit n serves any limit ≤ n; a larger limit is a miss. When the byte cap
-- truncates, n drops to the rows kept. Pure; spec .tmp/leaderboard-cache-codec-spec.luau.

export type Row = { id: number, total: number }
export type Item = { v: number, n: number, r: { number } }

local VERSION = 2

local LeaderboardCacheCodec = {}

local function digits(n: number): number
	return #tostring(n)
end

function LeaderboardCacheCodec.encode(rows: { Row }, limit: number, maxBytes: number): Item
	local flat: { number } = {}
	-- {"v":2,"n":NNN,"r":[…]}
	local bytes = 20 + digits(limit)
	local kept = 0
	for _, row in ipairs(rows) do
		if kept >= limit then
			break
		end
		local id = math.floor(tonumber(row.id) or 0)
		local total = tonumber(row.total) or 0
		if total % 1 == 0 then
			total = math.floor(total)
		end
		-- +2 per number: some encoders write large integers as "9000000001.0".
		local add = digits(id) + 3 + #tostring(total) + 3
		if bytes + add > maxBytes then
			break
		end
		bytes += add
		table.insert(flat, id)
		table.insert(flat, total)
		kept += 1
	end
	local truncated = kept < limit and kept < #rows
	return { v = VERSION, n = if truncated then kept else limit, r = flat }
end

--- Rows for `limit`, or nil when the item cannot serve it (other version, malformed, built for
--- a smaller limit).
function LeaderboardCacheCodec.decode(item: any, limit: number): { Row }?
	if type(item) ~= "table" or item.v ~= VERSION or type(item.r) ~= "table" then
		return nil
	end
	local n = tonumber(item.n)
	if not n or n < limit then
		return nil
	end
	local flat = item.r
	if #flat % 2 ~= 0 then
		return nil
	end
	local out: { Row } = {}
	for i = 1, #flat, 2 do
		local id, total = flat[i], flat[i + 1]
		if type(id) ~= "number" or type(total) ~= "number" then
			return nil
		end
		if #out < limit then
			table.insert(out, { id = id, total = total })
		end
	end
	return out
end

return LeaderboardCacheCodec
