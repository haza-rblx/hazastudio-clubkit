--!strict
-- Shared/Utils/CrossServerCache.luau
-- Wrapper tipis di atas MessagingService untuk invalidate cache antar server.
--
-- Pattern:
--   - Kalau Server A nulis perubahan ke DataStore (admin set title, couple,
--     gift, dll), broadcast { topic, userId } via MessagingService.
--   - Semua server (termasuk publisher) subscribe topic yang sama dan
--     panggil callback yang clear cache lokal untuk userId itu.
--
-- Kenapa perlu:
--   - Cache.luau punya TTL 60s. Kalau Server B punya cached overhead lama
--     dan user-nya kebetulan online di B saat admin set title di A, B akan
--     terus serve data lama sampai TTL expired -> "title ilang" report.
--   - Roblox DataStore sendiri ada eventual consistency window 4-6s.
--     Invalidation message biasanya sampai dalam 1-3s, jadi kita delay
--     read di subscriber sedikit untuk hindari race read-before-replicate.
--
-- Catatan reliability:
--   - MessagingService punya rate limit per topic. Kita debounce per userId
--     supaya burst write (misal admin set title 5x cepat) cuma fire 1 publish.
--   - PublishAsync bisa throw saat throttled. Selalu di-pcall, kegagalan
--     publish bukan blocker (cache akhirnya ke-evict via TTL).

local MessagingService = game:GetService("MessagingService")
local RunService = game:GetService("RunService")

local CrossServerCache = {}

-- Debounce untuk hindari spam publish ke MessagingService.
-- Key: topic .. ":" .. userId, value: os.clock() saat terakhir publish.
local DEBOUNCE_WINDOW = 1.0 -- detik
local lastPublishedAt: { [string]: number } = {}

-- Kalau dijalankan di studio tanpa publish API real, log saja.
local function isPublishAvailable(): boolean
	return RunService:IsServer()
end

--- Publish invalidation ke semua server.
--- Aman dipanggil berulang dengan userId sama dalam 1 detik (debounced).
function CrossServerCache.publish(topic: string, userId: number)
	if not isPublishAvailable() then
		return
	end
	local key = topic .. ":" .. tostring(userId)
	local now = os.clock()
	local lastAt = lastPublishedAt[key]
	if lastAt and (now - lastAt) < DEBOUNCE_WINDOW then
		return
	end
	lastPublishedAt[key] = now

	-- Cleanup debounce map secara opportunistic supaya nggak grow tak terbatas
	if math.random() < 0.05 then
		local cutoff = now - 60
		for k, v in pairs(lastPublishedAt) do
			if v < cutoff then
				lastPublishedAt[k] = nil
			end
		end
	end

	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:PublishAsync(topic, { userId = userId, t = os.time() })
		end)
		if not ok then
			-- Throttled atau service down. Cache akhirnya evict via TTL,
			-- jadi ini non-fatal.
			warn(string.format(
				"[CrossServerCache] publish gagal topic=%s userId=%d err=%s",
				topic,
				userId,
				tostring(err)
			))
		end
	end)
end

--- Subscribe topic. Callback dipanggil dengan userId saat ada invalidation.
--- Kalau onMessage error, error di-log saja, tidak menghentikan subscription.
function CrossServerCache.subscribe(topic: string, onMessage: (userId: number) -> ()): RBXScriptConnection?
	if not isPublishAvailable() then
		return nil
	end
	local ok, conn = pcall(function()
		return MessagingService:SubscribeAsync(topic, function(message: any)
			if type(message) ~= "table" or type(message.Data) ~= "table" then
				return
			end
			local userId = tonumber(message.Data.userId)
			if not userId then
				return
			end
			-- Delay kecil untuk biarin DataStore replicate dulu.
			-- Tanpa delay, subscriber bisa read-before-replicate dan re-cache
			-- data lama.
			task.delay(2, function()
				local successCb, errCb = pcall(onMessage, userId)
				if not successCb then
					warn(string.format(
						"[CrossServerCache] subscriber callback error topic=%s userId=%d err=%s",
						topic,
						userId,
						tostring(errCb)
					))
				end
			end)
		end)
	end)
	if not ok then
		warn(string.format("[CrossServerCache] subscribe gagal topic=%s err=%s", topic, tostring(conn)))
		return nil
	end
	return conn
end

return CrossServerCache
