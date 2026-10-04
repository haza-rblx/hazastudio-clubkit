--!strict

export type Cache = {
	get: (self: Cache, key: string) -> number?,
	set: (self: Cache, key: string, value: number) -> (),
	clear: (self: Cache) -> (),
	count: (self: Cache) -> number,
}

local TextMeasurementCache = {}
TextMeasurementCache.__index = TextMeasurementCache

function TextMeasurementCache.new(maxEntries: number?): Cache
	local self = setmetatable({
		values = {},
		order = {},
		maxEntries = math.max(1, math.floor(maxEntries or 256)),
	}, TextMeasurementCache)
	return self
end

function TextMeasurementCache:get(key: string): number?
	return self.values[key]
end

function TextMeasurementCache:set(key: string, value: number)
	if self.values[key] == nil then
		table.insert(self.order, key)
	end
	self.values[key] = value

	while #self.order > self.maxEntries do
		local oldest = table.remove(self.order, 1)
		if oldest then
			self.values[oldest] = nil
		end
	end
end

function TextMeasurementCache:clear()
	table.clear(self.values)
	table.clear(self.order)
end

function TextMeasurementCache:count(): number
	return #self.order
end

return TextMeasurementCache
