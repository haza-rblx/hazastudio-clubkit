--!strict
-- PATH: ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/MusicActiveSet.luau
-- Active set (docs/plans/active-set.md): pure rules for the one server-side set source.
-- Holds the resolved play order, the cursor (set tracks already played), the page slice with its
-- query filter and the interleave position. No Roblox APIs, so it runs under plain Luau tests.

local MusicActiveSet = {}

local PAGE_QUERY_MAX_CHARS = 64
local UP_NEXT_COUNT = 3

export type Item = {
	id: string,
	name: string?,
	creator: string?,
	totalDuration: number?,
}

export type ActiveSet = {
	id: string,
	title: string,
	sourceKind: string,
	sourceId: string?,
	starterUserId: number,
	starterName: string,
	shuffle: boolean,
	order: { Item },
	played: number,
}

export type Random = (upper: number) -> number

export type PageResult = {
	ok: boolean,
	reason: string,
	offset: number?,
	total: number?,
	tracks: { Item }?,
}

local function lowerText(value: any): string
	return string.lower(tostring(value or ""))
end

-- Fisher-Yates over order[first..#order]; the played prefix (before first) never moves.
local function shuffleTail(order: { Item }, first: number, random: Random)
	local last = #order
	for i = last, first + 1, -1 do
		local k = math.clamp(math.floor(random(i - first + 1)), 1, i - first + 1)
		local j = first + k - 1
		order[i], order[j] = order[j], order[i]
	end
end

local function cleanItem(item: Item): Item
	return {
		id = item.id,
		name = item.name,
		creator = item.creator,
		totalDuration = item.totalDuration,
	}
end

-- Resolved list -> cap -> optional shuffle (contract order). nil when nothing is left to play.
function MusicActiveSet.create(opts: {
	id: string,
	title: string,
	sourceKind: string,
	sourceId: string?,
	starterUserId: number,
	starterName: string,
	items: { Item },
	cap: number,
	shuffle: boolean,
	random: Random,
}): ActiveSet?
	local cap = math.max(1, math.floor(opts.cap))
	local order: { Item } = {}
	for _, item in ipairs(opts.items) do
		if #order >= cap then
			break
		end
		if type(item.id) == "string" and item.id ~= "" then
			table.insert(order, cleanItem(item))
		end
	end
	if #order == 0 then
		return nil
	end
	if opts.shuffle then
		shuffleTail(order, 1, opts.random)
	end
	return {
		id = opts.id,
		title = opts.title,
		sourceKind = opts.sourceKind,
		sourceId = opts.sourceId,
		starterUserId = opts.starterUserId,
		starterName = opts.starterName,
		shuffle = opts.shuffle == true,
		order = order,
		played = 0,
	}
end

function MusicActiveSet.total(set: ActiveSet): number
	return #set.order
end

function MusicActiveSet.remainingCount(set: ActiveSet): number
	return math.max(0, #set.order - set.played)
end

-- The set track that is materialised next (order[cursor + 1]), or nil when the set is done.
function MusicActiveSet.nextItem(set: ActiveSet): Item?
	return set.order[set.played + 1]
end

-- A set track started playing. Only the item at the cursor moves it, so a stale id changes nothing.
function MusicActiveSet.markPlayed(set: ActiveSet, trackId: string): boolean
	local nextItem = set.order[set.played + 1]
	if nextItem == nil or nextItem.id ~= trackId then
		return false
	end
	set.played += 1
	return true
end

-- Inverse of markPlayed (Previous put a set track back in the queue). Only the last played item
-- moves the cursor back, so a stale id (e.g. from a set that was replaced) changes nothing.
function MusicActiveSet.unmarkPlayed(set: ActiveSet, trackId: string): boolean
	local lastItem = set.order[set.played]
	if set.played <= 0 or lastItem == nil or lastItem.id ~= trackId then
		return false
	end
	set.played -= 1
	return true
end

-- Drops the item at the cursor without playing it (track gone from the library, asset unplayable).
function MusicActiveSet.skipNext(set: ActiveSet): boolean
	if set.order[set.played + 1] == nil then
		return false
	end
	set.played += 1
	return true
end

-- Shuffles the remaining order only; played tracks keep their place.
function MusicActiveSet.reshuffle(set: ActiveSet, random: Random, newId: string)
	shuffleTail(set.order, set.played + 1, random)
	set.id = newId
	set.shuffle = true
end

-- Removes unplayed items whose ids are in lookup (deleted tracks). Returns how many were removed.
function MusicActiveSet.dropIds(set: ActiveSet, lookup: { [string]: true }): number
	local kept: { Item } = {}
	local removed = 0
	for index, item in ipairs(set.order) do
		if index > set.played and lookup[item.id] == true then
			removed += 1
		else
			table.insert(kept, item)
		end
	end
	if removed > 0 then
		set.order = kept
	end
	return removed
end

-- Remaining items (cursor tail) as clean copies, optionally filtered by a case-insensitive
-- substring of name or creator.
local function filteredRemaining(set: ActiveSet, query: string): { Item }
	local needle = lowerText(query)
	local out: { Item } = {}
	for index = set.played + 1, #set.order do
		local item = set.order[index]
		if needle == "" or string.find(lowerText(item.name), needle, 1, true) ~= nil
			or string.find(lowerText(item.creator), needle, 1, true) ~= nil then
			table.insert(out, cleanItem(item))
		end
	end
	return out
end

function MusicActiveSet.upNext(set: ActiveSet): { Item }
	local out: { Item } = {}
	for index = set.played + 1, math.min(#set.order, set.played + UP_NEXT_COUNT) do
		table.insert(out, cleanItem(set.order[index]))
	end
	return out
end

-- Page of the REMAINING order. offset is 0-based into the (filtered) remaining list.
function MusicActiveSet.page(set: ActiveSet, opts: { offset: any, limit: any?, query: any?, pageSize: number }): PageResult
	local offset = opts.offset
	if type(offset) ~= "number" or offset ~= offset or offset < 0 or offset % 1 ~= 0 then
		return { ok = false, reason = "invalid_offset", tracks = {} }
	end
	local pageSize = math.max(1, math.floor(opts.pageSize))
	local requested = opts.limit
	local limit = if type(requested) == "number" and requested == requested
		then math.floor(requested)
		else pageSize
	limit = math.clamp(limit, 1, pageSize)
	local query = if type(opts.query) == "string" then string.sub(opts.query, 1, PAGE_QUERY_MAX_CHARS) else ""
	local filtered = filteredRemaining(set, query)
	local total = #filtered
	local tracks: { Item } = {}
	for index = offset + 1, math.min(total, offset + limit) do
		table.insert(tracks, filtered[index])
	end
	return { ok = true, reason = "", offset = offset, total = total, tracks = tracks }
end

-- Where the next set track goes in the queue. Entries with fromSet are set tracks, the rest are
-- requests. Requests are the only thing that can play between two set tracks: after the
-- `interleave`-th waiting request when more than `interleave` wait, otherwise at the end.
function MusicActiveSet.insertIndex(queue: { { fromSet: boolean? } }, interleave: number): number
	local n = math.max(0, math.floor(interleave))
	if n == 0 then
		return 1
	end
	local requests = 0
	local cut: number? = nil
	for index, entry in ipairs(queue) do
		if entry.fromSet ~= true then
			requests += 1
			if requests == n then
				cut = index
			end
		end
	end
	if requests > n and cut ~= nil then
		return cut + 1
	end
	return #queue + 1
end

return MusicActiveSet
