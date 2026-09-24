--!strict
-- Shared/Utils/NetworkCoalesce.luau
--
-- Per-frame coalescing rules for NetworkManager (pure; lune-testable).
--
-- Key = (target kind, player UserId(s), data.kind, data.userId). Two queued entries with the
-- same key inside one flush collapse into one:
--   * kinds listed in `mergeFields` ({ [data.kind] = fieldName }) are DELTAS: the named table
--     field is merged field by field (later fields win, DeltaCompressor's "__NIL__" removal
--     sentinel included), every other envelope field comes from the later entry. Dropping the
--     first delta (the pre-2026-09-24 behaviour) lost its fields for good, because the server's
--     per-pair baseline had already advanced (perf audit 8b / plan H6).
--   * an entry whose data carries `full = true` replaces whatever was queued (a full snapshot);
--   * every other kind keeps the last entry (last wins).
-- The collapsed entry keeps the position of the first entry with that key.

export type Entry = {
	kind: string,
	player: any?,
	players: { any }?,
	data: any,
}

local NetworkCoalesce = {}

function NetworkCoalesce.messageKind(data: any): string
	if type(data) ~= "table" then
		return "_"
	end
	-- Include subject userId when present so Overhead (and similar) per-player
	-- deltas to the same viewer do not collapse across subjects.
	local kind = if type(data.kind) == "string" and data.kind ~= "" then data.kind else "_"
	local userId = data.userId
	if type(userId) == "number" then
		return string.format("%s:u%d", kind, userId)
	end
	return kind
end

local function listIdentity(players: { any }?): string
	if not players or #players == 0 then
		return "list:"
	end
	local ids = table.create(#players)
	for i, player in ipairs(players) do
		ids[i] = player.UserId
	end
	table.sort(ids)
	return "list:" .. table.concat(ids, ",")
end

function NetworkCoalesce.key(entry: Entry): string
	local msgKind = NetworkCoalesce.messageKind(entry.data)
	if entry.kind == "player" and entry.player then
		return string.format("player:%d:%s", entry.player.UserId, msgKind)
	elseif entry.kind == "all" then
		return "all:" .. msgKind
	elseif entry.kind == "allExcept" and entry.player then
		return string.format("allExcept:%d:%s", entry.player.UserId, msgKind)
	elseif entry.kind == "list" then
		return listIdentity(entry.players) .. ":" .. msgKind
	elseif entry.kind == "server" then
		return "server:" .. msgKind
	end
	return entry.kind .. ":" .. msgKind
end

local function mergeFieldFor(data: any, mergeFields: { [string]: string }?): string?
	if not mergeFields or type(data) ~= "table" or data.full == true then
		return nil
	end
	local kind = data.kind
	if type(kind) ~= "string" then
		return nil
	end
	return mergeFields[kind]
end

-- New entry; never mutates either input (the first delta for a key can be the subject's shared
-- payload table itself).
local function merge(earlier: Entry, later: Entry, field: string): Entry
	local before = earlier.data[field]
	local after = later.data[field]
	if type(before) ~= "table" or type(after) ~= "table" then
		return later
	end
	local combined = table.clone(before)
	for name, value in pairs(after) do
		combined[name] = value
	end
	local envelope = table.clone(later.data)
	envelope[field] = combined
	if type(earlier.data) == "table" and earlier.data.full == true then
		envelope.full = true -- a full snapshot plus a delta is still a full snapshot
	end
	return {
		kind = later.kind,
		player = later.player,
		players = later.players,
		data = envelope,
	}
end

--- Collapse same-key entries of one flush. Returns `queue` itself when nothing collapsed.
function NetworkCoalesce.coalesce(queue: { Entry }, mergeFields: { [string]: string }?): { Entry }
	if #queue <= 1 then
		return queue
	end
	local byKey: { [string]: Entry } = {}
	local order: { string } = {}
	for _, entry in ipairs(queue) do
		local key = NetworkCoalesce.key(entry)
		local existing = byKey[key]
		if existing == nil then
			table.insert(order, key)
			byKey[key] = entry
		else
			-- Merge when the LATER entry is a delta of a merge kind; the earlier one may be a
			-- delta or a full snapshot of the same kind. A later full snapshot replaces.
			local field = mergeFieldFor(entry.data, mergeFields)
			if field and type(existing.data) == "table" and existing.data.kind == entry.data.kind then
				byKey[key] = merge(existing, entry, field)
			else
				byKey[key] = entry
			end
		end
	end
	if #order == #queue then
		return queue
	end
	local compacted = table.create(#order)
	for i, key in ipairs(order) do
		compacted[i] = byKey[key]
	end
	return compacted
end

return NetworkCoalesce
