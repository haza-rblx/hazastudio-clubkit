--!strict
-- Shared/Utils/BoundedLru.luau
--
-- A map with a fixed capacity: once full, setting a new key evicts the key that was
-- read or written least recently. For per-userId caches whose entries must outlive a
-- player's visit (donors seen in notifications, user info looked up by id) but must not
-- grow for the life of the server (production hardening 2026-09-24, H5).
--
-- Pure: no Roblox services, so lune specs can require it directly.
--   local lru = BoundedLru.new(1000)
--   lru:set(userId, value); lru:get(userId); lru:delete(userId); lru:size(); lru:clear()

type Node = {
	key: any,
	value: any,
	prev: Node?,
	next: Node?,
}

export type BoundedLru = {
	get: (self: BoundedLru, key: any) -> any,
	peek: (self: BoundedLru, key: any) -> any,
	has: (self: BoundedLru, key: any) -> boolean,
	set: (self: BoundedLru, key: any, value: any) -> (),
	delete: (self: BoundedLru, key: any) -> (),
	size: (self: BoundedLru) -> number,
	capacity: (self: BoundedLru) -> number,
	evictions: (self: BoundedLru) -> number,
	clear: (self: BoundedLru) -> (),
}

local BoundedLru = {}

function BoundedLru.new(capacity: number): BoundedLru
	local cap = math.max(1, math.floor(tonumber(capacity) or 1))
	local nodes: { [any]: Node } = {}
	local count = 0
	local evicted = 0
	-- head = most recently used, tail = least recently used
	local head: Node? = nil
	local tail: Node? = nil

	local function unlink(node: Node)
		local prev = node.prev
		local nextNode = node.next
		if prev then
			prev.next = nextNode
		else
			head = nextNode
		end
		if nextNode then
			nextNode.prev = prev
		else
			tail = prev
		end
		node.prev = nil
		node.next = nil
	end

	local function pushFront(node: Node)
		node.prev = nil
		node.next = head
		if head then
			head.prev = node
		end
		head = node
		if tail == nil then
			tail = node
		end
	end

	local self = {} :: BoundedLru

	function self:get(key: any): any
		local node = nodes[key]
		if not node then
			return nil
		end
		if head ~= node then
			unlink(node)
			pushFront(node)
		end
		return node.value
	end

	-- Read without refreshing recency.
	function self:peek(key: any): any
		local node = nodes[key]
		return if node then node.value else nil
	end

	function self:has(key: any): boolean
		return nodes[key] ~= nil
	end

	function self:set(key: any, value: any)
		if key == nil then
			return
		end
		if value == nil then
			self:delete(key)
			return
		end
		local node = nodes[key]
		if node then
			node.value = value
			if head ~= node then
				unlink(node)
				pushFront(node)
			end
			return
		end
		local fresh: Node = { key = key, value = value, prev = nil, next = nil }
		nodes[key] = fresh
		pushFront(fresh)
		count += 1
		while count > cap do
			local oldest = tail
			if not oldest then
				break
			end
			unlink(oldest)
			nodes[oldest.key] = nil
			count -= 1
			evicted += 1
		end
	end

	function self:delete(key: any)
		local node = nodes[key]
		if not node then
			return
		end
		unlink(node)
		nodes[key] = nil
		count -= 1
	end

	function self:size(): number
		return count
	end

	function self:capacity(): number
		return cap
	end

	function self:evictions(): number
		return evicted
	end

	function self:clear()
		table.clear(nodes)
		head = nil
		tail = nil
		count = 0
	end

	return self
end

return BoundedLru
