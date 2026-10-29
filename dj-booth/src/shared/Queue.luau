--!strict
-- The play queue (owner, 2026-10-24): one shared line of { trackId, key }, in order. With auto mix
-- on, the next entry loads onto the idle deck and the crossfader moves to it; with it off the line
-- is only a prep list (a deck that ends just ejects, as before).
local Types = require(script.Parent.Types)
local Dict = require(script.Parent.Dict)

local Queue = {}

local counter = 0
local function newKey(): string
	counter += 1
	return string.format("%x-%d", os.clock() * 1e6 // 1, counter)
end

function Queue.add(q: { Types.QueueEntry }, trackId: string): { Types.QueueEntry }
	return Dict.insert(q, { trackId = trackId, key = newKey() })
end

-- several tracks at once, in the order given
function Queue.addMany(q: { Types.QueueEntry }, trackIds: { string }): { Types.QueueEntry }
	local c = table.clone(q)
	for _, id in trackIds do
		table.insert(c, { trackId = id, key = newKey() })
	end
	return c
end

function Queue.remove(q: { Types.QueueEntry }, key: string): { Types.QueueEntry }
	for i, e in q do
		if e.key == key then
			return Dict.removeAt(q, i)
		end
	end
	return q
end

-- move an entry by `by` places, clamped to the line; q itself when nothing moves
function Queue.move(q: { Types.QueueEntry }, key: string, by: number): { Types.QueueEntry }
	for i, e in q do
		if e.key == key then
			local j = math.clamp(i + by, 1, #q)
			if j == i then
				return q
			end
			local c = table.clone(q)
			table.remove(c, i)
			table.insert(c, j, e)
			return c
		end
	end
	return q
end

-- the first entry and the queue without it
function Queue.pop(q: { Types.QueueEntry }): (Types.QueueEntry?, { Types.QueueEntry })
	if #q == 0 then
		return nil, q
	end
	return q[1], Dict.removeAt(q, 1)
end

-- drop entries whose track no longer exists
function Queue.prune(q: { Types.QueueEntry }, tracks: { [string]: Types.Track }): { Types.QueueEntry }
	local out = {}
	for _, e in q do
		if tracks[e.trackId] then
			table.insert(out, e)
		end
	end
	return if #out == #q then q else out
end

-- a shuffled copy (Fisher-Yates); the input is left alone
function Queue.shuffled(ids: { string }): { string }
	local out = table.clone(ids)
	local rng = Random.new()
	for i = #out, 2, -1 do
		local j = rng:NextInteger(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

return Queue
