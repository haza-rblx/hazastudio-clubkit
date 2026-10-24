--!strict
-- Immutable table helpers. Charm signals hold frozen tables, so every write makes a new copy of
-- the path it touches and shares the rest.
local Dict = {}

function Dict.set<K, V>(t: { [K]: V }, k: K, v: V?): { [K]: V }
	local c = table.clone(t)
	c[k] = v :: any
	return c
end

-- a value that means "remove this key" in a merge (nil can't be stored in a patch table)
Dict.None = table.freeze({ __none = true })

function Dict.merge<T>(t: T, patch: { [string]: any }): T
	local c = table.clone(t :: any)
	for k, v in patch do
		if v == Dict.None then
			c[k] = nil
		else
			c[k] = v
		end
	end
	return c :: any
end

-- set a value at a path: Dict.setIn(state, { "decks", 1, "vol" }, 0.5)
function Dict.setIn(t: any, path: { any }, v: any): any
	if #path == 0 then
		return v
	end
	local c = table.clone(t)
	local head = path[1]
	if #path == 1 then
		c[head] = v
	else
		c[head] = Dict.setIn(c[head] or {}, table.move(path, 2, #path, 1, {}), v)
	end
	return c
end

function Dict.updateIn(t: any, path: { any }, fn: (any) -> any): any
	local cur = t
	for _, k in path do
		cur = if cur then cur[k] else nil
	end
	return Dict.setIn(t, path, fn(cur))
end

function Dict.insert<V>(list: { V }, v: V, at: number?): { V }
	local c = table.clone(list)
	if at then
		table.insert(c, at, v)
	else
		table.insert(c, v)
	end
	return c
end

function Dict.removeAt<V>(list: { V }, i: number): { V }
	local c = table.clone(list)
	table.remove(c, i)
	return c
end

function Dict.removeValue<V>(list: { V }, v: V): { V }
	local i = table.find(list, v)
	return if i then Dict.removeAt(list, i) else list
end

-- a deep copy that is not frozen (for editing drafts)
function Dict.deepCopy<T>(t: T): T
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in t :: any do
		c[k] = Dict.deepCopy(v)
	end
	return c :: any
end

function Dict.count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

return Dict
