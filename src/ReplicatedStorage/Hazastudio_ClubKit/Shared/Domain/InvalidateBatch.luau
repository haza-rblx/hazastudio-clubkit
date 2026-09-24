--!strict
-- Shared/Domain/InvalidateBatch.luau
--
-- Splits one coalesced CrossServerCache invalidation into MessagingService messages of at most
-- `maxIds` ids and `maxBytes` of JSON (platform limit 1 KB) — production hardening P3, A9.
-- Every message keeps the legacy single `userId` (first id) so servers on an older kit, which
-- read only that field, still drop at least one cache entry. Pure; spec
-- .tmp/invalidate-batch-spec.luau.

export type Options = { maxIds: number, maxBytes: number, originJobId: string, t: number }

export type Message = { originJobId: string, userIds: { number }, userId: number, t: number }

local InvalidateBatch = {}

local function digits(n: number): number
	return #tostring(math.floor(n))
end

--- Upper bound of the JSON size of one message:
--- {"originJobId":"<job>","userIds":[a,b],"userId":a,"t":T}
function InvalidateBatch.estimateBytes(ids: { number }, originJobId: string, t: number): number
	local bytes = 16 + #originJobId + 3 -- {"originJobId":"…",
	bytes += 11 -- "userIds":[
	for i, id in ipairs(ids) do
		-- +2: some encoders write large integers as "1234567890.0"
		bytes += digits(id) + 2 + (if i > 1 then 1 else 0)
	end
	bytes += 2 -- ],
	bytes += 9 + (if ids[1] then digits(ids[1]) else 1) + 1 -- "userId":a,
	bytes += 4 + digits(t) + 1 -- "t":T}
	return bytes + 8 -- slack for encoder differences
end

function InvalidateBatch.buildMessages(ids: { number }, options: Options): { Message }
	local maxIds = math.max(1, math.floor(options.maxIds))
	local messages: { Message } = {}
	local current: { number } = {}
	local function emit()
		if #current > 0 then
			table.insert(messages, {
				originJobId = options.originJobId,
				userIds = current,
				userId = current[1],
				t = options.t,
			})
			current = {}
		end
	end
	for _, id in ipairs(ids) do
		table.insert(current, id)
		local tooBig = InvalidateBatch.estimateBytes(current, options.originJobId, options.t) > options.maxBytes
		if tooBig and #current > 1 then
			table.remove(current)
			emit()
			table.insert(current, id)
		end
		if #current >= maxIds then
			emit()
		end
	end
	emit()
	return messages
end

return InvalidateBatch
