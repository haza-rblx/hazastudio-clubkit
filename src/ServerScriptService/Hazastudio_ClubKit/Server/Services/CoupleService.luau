--!strict
-- Server/Services/CoupleService.lua
-- Business logic couple. Zero DataStore langsung, zero UI, zero Remote.
local Players      = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
-- Gunakan ReplicatedStorage local variable, bukan game.ReplicatedStorage
local Config       = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types        = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local CoupleDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.CoupleDomain)
local ResultUtil   = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)
local Logger       = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
type Result<T>           = Types.Result<T>
type IOverheadRepository = Types.IOverheadRepository
type PendingRequest = {
	fromUserId   : number,
	fromName     : string,
	fromUsername : string,
	requestId    : string,
	expiredAt    : number,
}
local function createCoupleService(deps: {
	repo : IOverheadRepository,
	})
	local repo = deps.repo
	local log  = Logger.new("CoupleService")

	-- Flipped to true by service:destroy(). The long-background rollback/breakup
	-- retry chains (up to 80s) check this before each attempt so teardown does
	-- not keep hammering a repo that is already shutting down.
	local _destroyed = false

	-- Budget guard: cek apakah ada cukup budget UpdateAsync sebelum masuk
	-- transaksi 2-step. Tanpa ini, target sudah commit tapi sender drop di queue,
	-- bikin half-coupled state yang user laporkan sebagai "couple ilang abis refresh".
	local function hasUpdateBudget(minBudget: number): boolean
		local ok, budget = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
		end)
		return ok and type(budget) == "number" and budget >= minBudget
	end

	-- Robust rollback dengan exponential backoff yang panjang di background.
	-- repo:update sudah retry 3x (~14s), tapi saat queue saturated 14s sering
	-- belum cukup. Background retry sampai 4 attempts (10s, 20s, 40s, 80s)
	-- mencegah half-committed state permanen.
	local function rollbackCoupleAsync(userId: number, partnerName: string?)
		task.spawn(function()
			local delays = { 10, 20, 40, 80 }
			for attempt, waitSec in ipairs(delays) do
				if _destroyed then
					return
				end
				local result = repo:update(userId, function(current)
					return CoupleDomain.removeCouple(current)
				end)
				if result.ok then
					log:warn("Couple rollback eventually succeeded", {
						userId = userId,
						attempt = attempt,
					})
					return
				end
				if _destroyed then
					return
				end
				log:warn("Couple rollback retry pending", {
					userId = userId,
					attempt = attempt,
					nextDelay = waitSec,
					err = result.error,
				})
				task.wait(waitSec)
			end
			if not _destroyed then
				log:error("CRITICAL: Couple rollback gagal total, butuh intervensi manual", {
					userId = userId,
					partnerName = partnerName,
				})
			end
		end)
	end

	local function clearPartnerCoupleAsync(partnerUserId: number, context: string)
		task.spawn(function()
			local delays = { 2, 5, 10, 20 }
			for attempt, waitSec in ipairs(delays) do
				if _destroyed then
					return
				end
				local result = repo:update(partnerUserId, function(current)
					return CoupleDomain.removeCouple(current)
				end)
				if result.ok then
					if attempt > 1 then
						log:info("Partner breakup retry succeeded", {
							partnerId = partnerUserId,
							attempt = attempt,
							context = context,
						})
					end
					return
				end
				if _destroyed then
					return
				end
				log:warn("Partner breakup retry pending", {
					partnerId = partnerUserId,
					attempt = attempt,
					nextDelay = waitSec,
					context = context,
					err = result.error,
				})
				task.wait(waitSec)
			end
			if not _destroyed then
				log:error("CRITICAL: Partner breakup failed after retries", {
					partnerId = partnerUserId,
					context = context,
				})
			end
		end)
	end
	-- Pending requests di memory - tidak perlu disimpan ke DataStore
	-- Key: targetUserId, Value: { fromUserId, fromName, fromUsername, requestId, expiredAt }
	local pendingRequests: {[number]: PendingRequest} = {}
	-- Cleanup expired requests setiap 30 detik
	-- Thread disimpan agar bisa dibatalkan via service:destroy()
	local cleanupThread = task.spawn(function()
		while true do
			task.wait(30)
			local now = os.time()
			for targetId, req in pairs(pendingRequests) do
				if now >= req.expiredAt then
					pendingRequests[targetId] = nil
					log:debug("Request expired", { targetId = targetId })
				end
			end
		end
	end)
	local service = {}
	-- ----------------------------------------------------------
	-- sendRequest - kirim couple request dari sender ke target
	-- ----------------------------------------------------------
	function service:sendRequest(
		sender        : Player,
		target        : Player,
		requestId     : string
	): Result<nil>
		-- Tidak bisa couple dengan diri sendiri
		if sender.UserId == target.UserId then
			return ResultUtil.Err(Config.Couple.MSG_SELF)
		end
		-- Cek sender sudah punya couple
		local senderStored = repo:load(sender.UserId)
		if not senderStored.ok then
			return ResultUtil.Err("[Couple] I could not load your couple data. Try again.")
		end
		if CoupleDomain.isCoupled(senderStored.value) then
			return ResultUtil.Err(Config.Couple.MSG_ALREADY_COUPLED)
		end
		-- Cek sender sudah punya pending request
		for _, req in pairs(pendingRequests) do
			if req.fromUserId == sender.UserId then
				return ResultUtil.Err(Config.Couple.MSG_REQUEST_PENDING)
			end
		end
		-- Cek target sudah punya couple
		local targetStored = repo:load(target.UserId)
		if not targetStored.ok then
			return ResultUtil.Err("[Couple] I could not load that player's couple data. Try again.")
		end
		if CoupleDomain.isCoupled(targetStored.value) then
			return ResultUtil.Err(Config.Couple.MSG_TARGET_COUPLED)
		end
		-- Simpan pending request
		pendingRequests[target.UserId] = {
			fromUserId   = sender.UserId,
			fromName     = sender.DisplayName,
			fromUsername = sender.Name,
			requestId    = requestId,
			expiredAt    = os.time() + Config.Couple.REQUEST_TIMEOUT,
		}
		log:info("Request sent", { from = sender.Name, to = target.Name })
		return ResultUtil.Ok(nil)
	end
	-- ----------------------------------------------------------
	-- acceptRequest - target accept request dari sender
	-- Pindahkan semua validasi ke dalam UpdateAsync mutator
	-- agar atomic dan tidak ada race condition
	-- ----------------------------------------------------------
	function service:acceptRequest(
		target    : Player,
		requestId : string
	): Result<{ senderUserId: number, senderName: string }>
		local req = pendingRequests[target.UserId]
		if not req or req.requestId ~= requestId then
			return ResultUtil.Err("[Couple] That request is gone or already expired.")
		end
		if os.time() >= req.expiredAt then
			pendingRequests[target.UserId] = nil
			return ResultUtil.Err("[Couple] That request already expired.")
		end

		-- Refuse kalau budget terlalu rendah. acceptRequest butuh 2 UpdateAsync
		-- (target + sender) plus rollback budget kalau salah satu fail.
		-- Better gagal cepat dengan pesan jelas daripada masuk half-committed state.
		if not hasUpdateBudget(4) then
			log:warn("acceptRequest refused: low DataStore budget", {
				target = target.Name,
				sender = req.fromName,
			})
			return ResultUtil.Err("[Couple] Server is busy right now. Try again in a few seconds.")
		end

		local senderUserId = req.fromUserId
		local senderName   = req.fromName
		local targetName   = target.DisplayName
		-- Save target dengan validasi di dalam mutator (atomic)
		local saveTarget = repo:update(target.UserId, function(current)
			-- Validasi di dalam mutator agar atomic
			if CoupleDomain.isCoupled(current) then
				-- Jika sudah coupled, return current tanpa perubahan
				-- UpdateAsync akan return nil dan kita bisa detect ini
				return current
			end
			return CoupleDomain.applyCouple(current, senderName, senderUserId)
		end)

		if not saveTarget.ok then
			return ResultUtil.Err("[Couple] Could not save that player's couple data. Try again.")
		end
		-- Check apakah target sudah coupled (validasi gagal di mutator)
		if CoupleDomain.isCoupled(saveTarget.value) and saveTarget.value.couplePartnerId ~= senderUserId then
			-- Target sudah coupled dengan orang lain (race condition detected)
			return ResultUtil.Err(Config.Couple.MSG_TARGET_COUPLED)
		end
		-- Save sender dengan validasi di dalam mutator (atomic)
		local saveSender = repo:update(senderUserId, function(current)
			-- Validasi di dalam mutator agar atomic
			if CoupleDomain.isCoupled(current) then
				return current
			end
			return CoupleDomain.applyCouple(current, targetName, target.UserId)
		end)

		if not saveSender.ok then
			-- Rollback target jika sender gagal. Pakai background retry yang panjang
			-- supaya saat queue clear, rollback tetap commit dan state nggak
			-- kestuck di half-coupled.
			rollbackCoupleAsync(target.UserId, senderName)
			return ResultUtil.Err("[Couple] Could not save your couple data. Try again.")
		end
		-- Check apakah sender sudah coupled (validasi gagal di mutator)
		if CoupleDomain.isCoupled(saveSender.value) and saveSender.value.couplePartnerId ~= target.UserId then
			-- Sender sudah coupled dengan orang lain (race condition detected)
			-- Rollback target dengan retry panjang
			rollbackCoupleAsync(target.UserId, senderName)
			return ResultUtil.Err(Config.Couple.MSG_ALREADY_COUPLED)
		end
		-- Hapus pending request
		pendingRequests[target.UserId] = nil
		log:info("Couple formed", { sender = senderName, target = target.Name })
		return ResultUtil.Ok({ senderUserId = senderUserId, senderName = senderName })
	end
	-- ----------------------------------------------------------
	-- rejectRequest - target reject request
	-- ----------------------------------------------------------
	function service:rejectRequest(
		target    : Player,
		requestId : string
	): Result<{ senderUserId: number }>
		local req = pendingRequests[target.UserId]
		if not req or req.requestId ~= requestId then
			return ResultUtil.Err("[Couple] That request is no longer available.")
		end
		local senderUserId = req.fromUserId
		pendingRequests[target.UserId] = nil
		log:info("Request rejected", { from = req.fromName, by = target.Name })
		return ResultUtil.Ok({ senderUserId = senderUserId })
	end
	-- ----------------------------------------------------------
	-- breakup - hapus couple dari kedua player
	-- ----------------------------------------------------------
	function service:breakup(player: Player): Result<{ partnerUserId: number? }>
		local stored = repo:load(player.UserId)
		if not stored.ok then
			return ResultUtil.Err("[Couple] I could not load your couple data. Try again.")
		end
		if not CoupleDomain.isCoupled(stored.value) then
			return ResultUtil.Err(Config.Couple.MSG_NO_COUPLE)
		end

		local partnerIdFromStore = stored.value.couplePartnerId
		local partnerNameFromStore = stored.value.couplePartner

		local saveResult = repo:update(player.UserId, function(current)
			return CoupleDomain.removeCouple(current)
		end)
		if not saveResult.ok then
			return ResultUtil.Err("[Couple] Could not save the breakup. Try again.")
		end

		local resolvedPartnerId = partnerIdFromStore
		if not resolvedPartnerId and partnerNameFromStore then
			for _, p in ipairs(Players:GetPlayers()) do
				if p.Name == partnerNameFromStore or p.DisplayName == partnerNameFromStore then
					resolvedPartnerId = p.UserId
					break
				end
			end
		end
		if resolvedPartnerId ~= nil and resolvedPartnerId ~= player.UserId then
			local savePartner = repo:update(resolvedPartnerId, function(current)
				return CoupleDomain.removeCouple(current)
			end)
			if not savePartner.ok then
				log:warn("Breakup partner save failed — scheduling retry", {
					player = player.Name,
					partnerId = resolvedPartnerId,
					err = savePartner.error,
				})
				clearPartnerCoupleAsync(resolvedPartnerId, "breakup")
			end
		end

		log:info("Breakup", { player = player.Name, partnerId = resolvedPartnerId })
		return ResultUtil.Ok({ partnerUserId = resolvedPartnerId })
	end
	-- ----------------------------------------------------------
	-- breakupBoth - hapus couple dari kedua player sekaligus
	-- Pakai couplePartnerId dari DataStore agar bisa breakup meski partner offline
	-- ----------------------------------------------------------
	function service:breakupBoth(playerA: Player): Result<nil>
		local storedA = repo:load(playerA.UserId)
		if not storedA.ok then
			log:error("Gagal load data breakup", { err = storedA.error })
			return ResultUtil.Err("[Couple] I could not load your couple data. Try again.")
		end
		local partnerIdFromStore   = storedA.value.couplePartnerId
		local partnerNameFromStore = storedA.value.couplePartner
		-- Hapus couple dari player A
		local saveA = repo:update(playerA.UserId, function(current)
			return CoupleDomain.removeCouple(current)
		end)
		if not saveA.ok then
			log:error("Gagal save breakup playerA", { err = saveA.error })
		end
		-- Cari partnerId - prioritaskan couplePartnerId dari DataStore (primary key)
		-- Fallback ke pencarian nama hanya jika couplePartnerId nil (data lama)
		local resolvedPartnerId = partnerIdFromStore
		if not resolvedPartnerId and partnerNameFromStore then
			for _, p in ipairs(Players:GetPlayers()) do
				if p.Name == partnerNameFromStore or p.DisplayName == partnerNameFromStore then
					resolvedPartnerId = p.UserId
					break
				end
			end
		end
		if resolvedPartnerId ~= nil then
			local saveB = repo:update(resolvedPartnerId, function(current)
				return CoupleDomain.removeCouple(current)
			end)
			if not saveB.ok then
				log:error("Gagal save breakup partner — scheduling retry", {
					partnerId = resolvedPartnerId,
					err = saveB.error,
				})
				clearPartnerCoupleAsync(resolvedPartnerId, "breakupBoth")
			end
		else
			log:warn("Partner tidak ditemukan saat breakup", { partnerName = tostring(partnerNameFromStore) })
		end
		log:info("Breakup done", { playerA = playerA.Name })
		return ResultUtil.Ok(nil)
	end
	-- ----------------------------------------------------------
	-- getPendingRequest - cek apakah ada request pending untuk player
	-- ----------------------------------------------------------
	function service:getPendingRequest(userId: number): PendingRequest?
		local req = pendingRequests[userId]
		if not req or os.time() >= req.expiredAt then
			return nil
		end
		return req
	end
	-- ----------------------------------------------------------
	-- cancelPendingFrom - hapus semua pending request dari sender
	-- (dipakai saat sender leave)
	-- ----------------------------------------------------------
	function service:cancelPendingFrom(userId: number)
		for targetId, req in pairs(pendingRequests) do
			if req.fromUserId == userId then
				pendingRequests[targetId] = nil
			end
		end
	end
	-- Hentikan cleanup loop dan bersihkan state - untuk testing atau teardown
	function service:destroy()
		_destroyed = true
		task.cancel(cleanupThread)
		table.clear(pendingRequests)
	end
	return service
end
return createCoupleService
