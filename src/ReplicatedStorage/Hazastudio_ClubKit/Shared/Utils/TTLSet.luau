--!strict
-- Shared/Utils/TTLSet.lua
--
-- Bounded set with per-entry TTL eviction.
--
-- Used by Controllers to dedupe processed `requestId`s without leaking memory.
-- Each entry expires after `ttl` seconds. The set is hard-capped at `maxSize`
-- entries; oldest entries evict first when full.
--
-- Pattern:
--   local processed = TTLSet.create({ ttl = 60, maxSize = 500 })
--   if processed:contains(requestId) then return end
--   processed:add(requestId)
--
-- Why this exists:
-- The codebase previously used plain `{}` tables keyed by requestId, never
-- evicted. At sustained traffic that table grows linearly with cumulative
-- requests across server lifetime. TTLSet caps both age and size.

export type TTLSetOptions = {
	ttl: number,
	maxSize: number?,
}

export type TTLSet = {
	add: (self: TTLSet, key: string) -> (),
	contains: (self: TTLSet, key: string) -> boolean,
	remove: (self: TTLSet, key: string) -> (),
	clear: (self: TTLSet) -> (),
	size: (self: TTLSet) -> number,
}

local DEFAULT_MAX_SIZE = 500

local TTLSet = {}
TTLSet.__index = TTLSet

local function evictExpired(self: any, now: number)
	for key, expiresAt in self._entries do
		if now >= expiresAt then
			self._entries[key] = nil
			self._count -= 1
		end
	end
end

local function evictOldest(self: any)
	local oldestKey: string? = nil
	local oldestExp = math.huge
	for key, expiresAt in self._entries do
		if expiresAt < oldestExp then
			oldestExp = expiresAt
			oldestKey = key
		end
	end
	if oldestKey ~= nil then
		self._entries[oldestKey] = nil
		self._count -= 1
	end
end

--- Construct a TTLSet. `ttl` is in seconds. `maxSize` defaults to 500.
function TTLSet.create(options: TTLSetOptions): TTLSet
	assert(type(options.ttl) == "number" and options.ttl > 0, "TTLSet requires ttl > 0")
	local self = setmetatable({
		_ttl = options.ttl,
		_maxSize = options.maxSize or DEFAULT_MAX_SIZE,
		_entries = {} :: { [string]: number },
		_count = 0,
	}, TTLSet)
	return (self :: any) :: TTLSet
end

--- Add a key. Resets the TTL if the key is already present.
function TTLSet:add(key: string)
	local now = os.clock()
	local expiresAt = now + self._ttl

	if self._entries[key] ~= nil then
		self._entries[key] = expiresAt
		return
	end

	-- Lazy expiry sweep before checking the size cap. Keeps the cap honest
	-- without a background timer.
	evictExpired(self, now)

	if self._count >= self._maxSize then
		evictOldest(self)
	end

	self._entries[key] = expiresAt
	self._count += 1
end

--- Check membership. Lazily evicts the entry if it has expired.
function TTLSet:contains(key: string): boolean
	local expiresAt = self._entries[key]
	if expiresAt == nil then
		return false
	end
	if os.clock() >= expiresAt then
		self._entries[key] = nil
		self._count -= 1
		return false
	end
	return true
end

--- Remove a key explicitly.
function TTLSet:remove(key: string)
	if self._entries[key] ~= nil then
		self._entries[key] = nil
		self._count -= 1
	end
end

--- Drop every entry.
function TTLSet:clear()
	self._entries = {}
	self._count = 0
end

function TTLSet:size(): number
	return self._count
end

return TTLSet
