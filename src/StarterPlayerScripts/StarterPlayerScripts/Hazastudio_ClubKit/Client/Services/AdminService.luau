--!strict
-- Client/Services/AdminService.lua
-- Encapsulates sendGiftcard logic: retry, backoff, response handling.
-- Controller hanya call sendGiftcard() dan bind callback - tidak ada retry di controller.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
export type GiftcardResult = {
	success    : boolean,
	tier       : string?,
	tierLabel  : string?,
	targetName : string?,
	error      : string?,   -- "no_permission" | "rate_limited" | "invalid_tier" | "not_found" | "already_has_tier" | "save_failed" | "network_error"
}
export type IAdminService = {
	sendGiftcard: (
		self       : IAdminService,
		targetUsername : string,
		tier           : string,
		onResult       : (result: GiftcardResult) -> ()
	) -> (),
}
local function createAdminService(deps: {
	remotes: Folder,
}): IAdminService
	local remotes = deps.remotes
	local log     = Logger.new("Client.AdminService")
	local self    = {} :: IAdminService & { destroy: (self: any) -> () }
	local _connections: { RBXScriptConnection } = {}

	local function track(conn: RBXScriptConnection): RBXScriptConnection
		table.insert(_connections, conn)
		return conn
	end

	function self:destroy()
		for _, conn in ipairs(_connections) do
			conn:Disconnect()
		end
		table.clear(_connections)
	end

	-- Listen untuk AdminGiftcardResult remote (Server->Client)
	-- Dilakukan saat construct agar tidak miss event
	local pendingCallbacks: {[string]: (result: GiftcardResult) -> ()} = {}
	task.spawn(function()
		local remote = remotes:WaitForChild(
			Config.Admin.REMOTE_GIFTCARD_RESULT,
			Config.Shop.REMOTE_READY_TIMEOUT
		) :: RemoteEvent?
		if not remote then
			log:warn("AdminGiftcardResult remote tidak ditemukan", {
				timeout = Config.Shop.REMOTE_READY_TIMEOUT,
			})
			return
		end
		track(remote.OnClientEvent:Connect(function(data: any)
			if type(data) ~= "table" then return end
			-- requestId dipakai untuk route ke callback yang benar
			local reqId = data.requestId
			if type(reqId) ~= "string" then return end
			local cb = pendingCallbacks[reqId]
			if not cb then return end
			pendingCallbacks[reqId] = nil
			cb({
				success    = data.success == true,
				tier       = type(data.tier)       == "string" and data.tier       or nil,
				tierLabel  = type(data.tierLabel)  == "string" and data.tierLabel  or nil,
				targetName = type(data.targetName) == "string" and data.targetName or nil,
				error      = type(data.error)      == "string" and data.error      or nil,
			})
		end))
		log:info("AdminService ready — giftcard result remote connected")
	end)
	function self:sendGiftcard(
		targetUsername : string,
		tier           : string,
		onResult       : (result: GiftcardResult) -> ()
	)
		local HttpService = game:GetService("HttpService")
		-- Satu requestId untuk semua retry - idempotency dijamin server
		local requestId = HttpService:GenerateGUID(false)
		local maxAttempts  = Config.Admin.RETRY_MAX_ATTEMPTS
		local backoffTable = Config.Admin.RETRY_BACKOFF
		local timeout      = Config.Admin.NETWORK_TIMEOUT
		local done          = false
		local attemptNumber = 0
		local timeoutThread: thread? = nil
		-- Daftarkan callback untuk requestId ini
		pendingCallbacks[requestId] = function(result: GiftcardResult)
			if done then return end
			done = true
			if timeoutThread then
				task.cancel(timeoutThread)
				timeoutThread = nil
			end
			pendingCallbacks[requestId] = nil
			onResult(result)
		end
		local sendGiftcardRemote = remotes:FindFirstChild(Config.Admin.REMOTE_SEND_GIFTCARD) :: RemoteEvent?
		local function attempt()
			if done then return end
			attemptNumber += 1
			if not sendGiftcardRemote then
				-- Coba cari sekali lagi (mungkin baru saja dibuat server)
				sendGiftcardRemote = remotes:FindFirstChild(Config.Admin.REMOTE_SEND_GIFTCARD) :: RemoteEvent?
			end
			if not sendGiftcardRemote then
				log:warn("sendGiftcardRemote tidak ditemukan", { attempt = attemptNumber })
				if not done then
					done = true
					pendingCallbacks[requestId] = nil
					onResult({ success = false, error = "network_error" })
				end
				return
			end
			log:debug("Mengirim giftcard", {
				attempt   = attemptNumber,
				target    = targetUsername,
				tier      = tier,
				requestId = requestId,
			})
			-- Kirim ke server - requestId sama untuk semua attempt (idempotent)
			sendGiftcardRemote:FireServer({
				requestId      = requestId,
				targetUsername = targetUsername,
				tier           = tier,
			})
			-- Set timeout untuk attempt ini
			if timeoutThread then
				task.cancel(timeoutThread)
			end
			timeoutThread = task.delay(timeout, function()
				if done then return end
				if attemptNumber < maxAttempts then
					local delay = backoffTable[attemptNumber] or timeout
					log:debug("Timeout, retry", { attempt = attemptNumber, nextDelay = delay })
					task.wait(delay)
					attempt()
				else
					-- Semua attempt habis
					if not done then
						done = true
						pendingCallbacks[requestId] = nil
						log:warn("Semua retry habis, giftcard gagal", {
							target = targetUsername,
							tier   = tier,
						})
						onResult({ success = false, error = "network_error" })
					end
				end
			end)
		end
		attempt()
	end
	return self
end
return createAdminService
