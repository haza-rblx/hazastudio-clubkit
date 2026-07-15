--!strict
-- Server/Controllers/ShopController.lua
-- Handles: MarketplaceService.ProcessReceipt (gift + legacy buy product + donations),
-- Game Pass self-buy (PromptGamePassPurchaseFinished + join ownership sync),
-- ShopGiftPending remote.
-- ProcessReceipt dibuat di sini - hanya satu script boleh set ini per game.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local ShopDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.ShopDomain)
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local NetworkManager = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.NetworkManager)
local Validator = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Validator)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
type ILogger = Types.ILogger
type INotify = {
	player: (player: Player, messageOrPayload: any, notifType: string?) -> (),
	all: (messageOrPayload: any, notifType: string?) -> (),
}
type DonationProduct = {
	key: string,
	name: string,
	price: number,
	productId: number,
}
local REMOTE_GRANT = Config.Shop.REMOTE_GRANT
local REMOTE_GIFT_INIT = Config.Shop.REMOTE_GIFT_INIT
local DONATION_PRODUCT_REFRESH_INTERVAL = 300
local DONATION_PRODUCT_FETCH_TIMEOUT = 25
export type IShopController = {
	init: (self: IShopController) -> (),
}
local function createShopController(
	deps: {
		shopService: any,
		overheadController: any, -- IOverheadController
		logger: ILogger,
		remotes: Folder,
		notify: INotify?,
		notifRemote: RemoteEvent?,
		leaderboardRepository: any?,
		donationEffectService: any?,
		donationService: any?,
		overheadRepository: any?,
		overheadService: any?,
		workspaceLeaderboardRefresh: { refresh: (() -> ())? }?,
		paidBroadcastController: any?,
		leaderboardNetwork: any?,
	}
): IShopController
	local log = deps.logger
	local shopService = deps.shopService
	local overheadController = deps.overheadController
	local remotes = deps.remotes
	local notify = deps.notify
	local notifRemote = deps.notifRemote
	local leaderboardRepository = deps.leaderboardRepository
	local donationEffectService = deps.donationEffectService
	local donationService = deps.donationService
	local overheadRepository = deps.overheadRepository
	local overheadService = deps.overheadService
	local workspaceLeaderboardRefresh = deps.workspaceLeaderboardRefresh
	local paidBroadcastController = deps.paidBroadcastController
	local leaderboardNetwork = deps.leaderboardNetwork
	local notifNetwork: any = nil
	local donationProductsNetwork: any = nil
	if notifRemote then
		notifNetwork = NetworkManager.create({
			reliable = notifRemote,
			logger = log,
			isServer = true,
		})
	end
	-- Lazy-cached for remotes fetched via FindFirstChild after init.
	local grantNetwork: any = nil
	local donationResultNetwork: any = nil
	local function ensureGrantNetwork(): any?
		if grantNetwork then
			return grantNetwork
		end
		local remote = remotes:FindFirstChild(REMOTE_GRANT)
		if not remote or not remote:IsA("RemoteEvent") then
			return nil
		end
		grantNetwork = NetworkManager.create({
			reliable = remote :: RemoteEvent,
			logger = log,
			isServer = true,
		})
		return grantNetwork
	end
	local function ensureDonationResultNetwork(): any?
		if donationResultNetwork then
			return donationResultNetwork
		end
		local remote = remotes:FindFirstChild(Config.Donation.REMOTE_ROBUX_RESULT)
		if not remote or not remote:IsA("RemoteEvent") then
			return nil
		end
		donationResultNetwork = NetworkManager.create({
			reliable = remote :: RemoteEvent,
			logger = log,
			isServer = true,
		})
		return donationResultNetwork
	end
	-- TTL-based gift request dedup (nilai = expiry timestamp)
	local giftLimiter = RateLimiter.new(Config.Shop.GIFT_RATE_MAX, Config.Shop.GIFT_RATE_WINDOW)
	local donationLimiter =
		RateLimiter.new(Config.Donation.ROBUX_PENDING_RATE_MAX, Config.Donation.ROBUX_PENDING_RATE_WINDOW)
	local donationProductsLimiter =
		RateLimiter.new(Config.Donation.ROBUX_PRODUCTS_RATE_MAX, Config.Donation.ROBUX_PRODUCTS_RATE_WINDOW)
	local processedGiftReqs: { [string]: number } = {}
	local processedDonationProductReqs: { [string]: number } = {}
	local pendingDonations: { [number]: { productId: number, message: string, expiresAt: number } } = {}
	local donationProducts: { DonationProduct } = {}
	local donationProductsById: { [number]: DonationProduct } = {}
	local donationProductsLastRefresh = 0
	local isRefreshingDonationProducts = false
	-- PurchaseId idempotency cache TTL-based - PURCHASE_DEDUPE_WINDOW = 3600s
	-- Tidak wipe-all saat penuh - hanya hapus yang sudah expired
	local processedPurchases: { [string]: number } = {}
	local controller = {} :: IShopController

	local function filterForBroadcast(userId: number, message: string): string
		local trimmed = message:match("^%s*(.-)%s*$") or ""
		if trimmed == "" then
			return ""
		end
		local ok, filtered = pcall(function()
			local result = TextService:FilterStringAsync(trimmed, userId)
			return result:GetNonChatStringForBroadcastAsync()
		end)
		if ok and type(filtered) == "string" then
			return string.sub(filtered, 1, Config.Donation.ROBUX_MESSAGE_MAX_LENGTH)
		end
		log:warn("Donation Robux message filter failed", {
			userId = userId,
		})
		return ""
	end

	-- Kirim notifikasi ke client setelah membership berhasil diberikan
	local function notifyClient(userId: number, tier: string, isGift: boolean, fromName: string?)
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			return
		end
		local network = ensureGrantNetwork()
		if not network then
			return
		end
		network:fireClient(player, {
			tier = tier,
			isGift = isGift,
			fromName = fromName or "",
		})
	end
	local function resolvePaidBroadcastProductId(): number?
		local fromConfig = tonumber(Config.PaidBroadcast and Config.PaidBroadcast.PRODUCT_ID)
		if fromConfig and fromConfig > 0 then
			return fromConfig
		end
		-- Fallback: read buyer ClubKitConfig directly (string IDs / late bootstrap).
		local ok, clubKit = pcall(function()
			return require(ReplicatedStorage.Hazastudio_ClubKitConfig.ClubKitConfig)
		end)
		if ok and type(clubKit) == "table" and type(clubKit.PaidBroadcast) == "table" then
			local fromBuyer = tonumber(clubKit.PaidBroadcast.ProductId)
			if fromBuyer and fromBuyer > 0 then
				return fromBuyer
			end
		end
		return nil
	end

	local function getShopProductIdSet(): { [number]: boolean }
		-- Exclude gift + legacy buy + PaidBroadcast Developer Products from donation catalog.
		local excluded: { [number]: boolean } = {}
		for _, product in pairs(Config.Shop.PRODUCTS) do
			if type(product) == "table" then
				local legacyBuyId = tonumber(product.BUY_ID)
				local giftId = tonumber(product.GIFT_ID)
				if legacyBuyId and legacyBuyId > 0 then
					excluded[legacyBuyId] = true
				end
				if giftId and giftId > 0 then
					excluded[giftId] = true
				end
			end
		end
		local paidBroadcastId = resolvePaidBroadcastProductId()
		if paidBroadcastId then
			excluded[paidBroadcastId] = true
		end
		local donationCfg = Config.Donation
		local extraExcluded = donationCfg and donationCfg.EXCLUDED_ROBUX_PRODUCT_IDS
		if type(extraExcluded) == "table" then
			for _, rawId in ipairs(extraExcluded) do
				local id = tonumber(rawId)
				if id and id > 0 then
					excluded[id] = true
				end
			end
		end
		return excluded
	end

	-- Cache IsForSale lookups across refresh cycles (same TTL as product refresh).
	local forSaleCache: { [number]: { forSale: boolean, checkedAt: number } } = {}

	local function isDeveloperProductForSale(productId: number, rawHint: any?): boolean
		local donationCfg = Config.Donation
		if donationCfg and donationCfg.HIDE_OFFSALE_ROBUX_PRODUCTS == false then
			return true
		end
		if type(rawHint) == "table" and type(rawHint.IsForSale) == "boolean" then
			forSaleCache[productId] = { forSale = rawHint.IsForSale == true, checkedAt = os.clock() }
			return rawHint.IsForSale == true
		end
		local cached = forSaleCache[productId]
		local now = os.clock()
		if cached and (now - cached.checkedAt) < DONATION_PRODUCT_REFRESH_INTERVAL then
			return cached.forSale
		end
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
		end)
		-- Fail-open on API errors so a blip does not wipe the donation list.
		local forSale = true
		if ok and type(info) == "table" then
			forSale = info.IsForSale == true
		elseif not ok then
			log:warn("GetProductInfo failed for donation product sale check", {
				productId = productId,
				error = tostring(info),
			})
		end
		forSaleCache[productId] = { forSale = forSale, checkedAt = now }
		return forSale
	end

	local function syncOwnedGamePasses(player: Player)
		local shopTiers = Config.Membership.SHOP_TIERS
		if type(shopTiers) ~= "table" then
			return
		end
		local grantedAny = false
		for _, tierKey in ipairs(shopTiers) do
			local product = Config.Shop.PRODUCTS[tierKey]
			if type(product) == "table" then
				local passId = tonumber(product.BUY_GAMEPASS_ID)
				if passId and passId > 0 then
					local ok, owns = pcall(function()
						return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
					end)
					if ok and owns == true then
						local parsed = ShopDomain.parseShopTier(tierKey)
						if parsed then
							local result = shopService:grantMembershipIfHigher(player.UserId, parsed)
							if result.ok and result.value == true then
								grantedAny = true
							end
						end
					elseif not ok then
						log:warn("UserOwnsGamePassAsync failed", {
							player = player.Name,
							gamePassId = passId,
							error = owns,
						})
					end
				end
			end
		end
		if grantedAny then
			overheadController:refreshPlayer(player)
			log:info("Game Pass membership synced", { userId = player.UserId })
		end
	end
	local function normalizeDeveloperProduct(raw: any): DonationProduct?
		if type(raw) ~= "table" then
			return nil
		end

		local productId = tonumber(
			raw.ProductId or raw.productId or raw.DeveloperProductId or raw.developerProductId or raw.Id or raw.id
		)
		if not productId or productId <= 0 then
			return nil
		end

		local name = tostring(raw.Name or raw.name or "Donation")
		local price = tonumber(raw.PriceInRobux or raw.priceInRobux or raw.Price or raw.price) or 0
		return {
			key = tostring(productId),
			name = name,
			price = price,
			productId = productId,
		}
	end
	local function loadConfiguredDonationProducts(
		excludedIds: { [number]: boolean }
	): ({ DonationProduct }, { [number]: DonationProduct })
		local products: { DonationProduct } = {}
		local byId: { [number]: DonationProduct } = {}
		local configured = Config.Donation and Config.Donation.ROBUX_PRODUCTS
		if type(configured) ~= "table" then
			return products, byId
		end
		for _, entry in ipairs(configured) do
			if type(entry) ~= "table" then
				continue
			end
			local product = normalizeDeveloperProduct(entry)
			if
				product
				and not excludedIds[product.productId]
				and isDeveloperProductForSale(product.productId, entry)
			then
				byId[product.productId] = product
				table.insert(products, product)
			end
		end
		table.sort(products, function(a, b)
			if a.price == b.price then
				return a.productId < b.productId
			end
			return a.price < b.price
		end)
		return products, byId
	end
	local function refreshDonationProducts(force: boolean?)
		local now = os.clock()
		if
			not force
			and donationProductsLastRefresh > 0
			and #donationProducts > 0
			and now - donationProductsLastRefresh < DONATION_PRODUCT_REFRESH_INTERVAL
		then
			return
		end

		-- Cegah fetch barengan; kalau force, tunggu fetch yang sedang jalan selesai lalu coba lagi.
		if isRefreshingDonationProducts then
			if not force then
				return
			end
			while isRefreshingDonationProducts do
				task.wait(0.05)
			end
			if #donationProducts > 0 then
				return
			end
		end
		isRefreshingDonationProducts = true

		local excludedIds = getShopProductIdSet()
		local nextProducts: { DonationProduct } = {}
		local nextProductsById: { [number]: DonationProduct } = {}
		local skippedOffsale = 0
		local configuredProducts, configuredById = loadConfiguredDonationProducts(excludedIds)
		for _, product in ipairs(configuredProducts) do
			nextProductsById[product.productId] = product
			table.insert(nextProducts, product)
		end
		local hadSuccessfulPage = #configuredProducts > 0
		local ok, pagesOrError = pcall(function()
			return MarketplaceService:GetDeveloperProductsAsync()
		end)
		if not ok then
			-- PENTING: JANGAN stempel donationProductsLastRefresh saat gagal.
			-- Jangan timpa cache yang sudah ada dengan list kosong.
			isRefreshingDonationProducts = false
			if #nextProducts > 0 then
				donationProducts = nextProducts
				donationProductsById = nextProductsById
				donationProductsLastRefresh = os.clock()
				log:info("Donation Robux products loaded from config (API fetch failed)", {
					count = #nextProducts,
					error = tostring(pagesOrError),
				})
				return
			end
			log:warn("Gagal fetch Developer Products", {
				error = tostring(pagesOrError),
			})
			return
		end

		local pages = pagesOrError
		while true do
			local pageOk, page = pcall(function()
				return pages:GetCurrentPage()
			end)
			if not pageOk or type(page) ~= "table" then
				log:warn("Gagal baca halaman Developer Products", {
					error = tostring(page),
				})
				break
			end
			hadSuccessfulPage = true

			for _, rawProduct in ipairs(page) do
				local product = normalizeDeveloperProduct(rawProduct)
				if product and not excludedIds[product.productId] and not nextProductsById[product.productId] then
					if isDeveloperProductForSale(product.productId, rawProduct) then
						nextProductsById[product.productId] = product
						table.insert(nextProducts, product)
					else
						skippedOffsale += 1
					end
				end
			end

			if pages.IsFinished then
				break
			end

			local advanceOk, advanceError = pcall(function()
				pages:AdvanceToNextPageAsync()
			end)
			if not advanceOk then
				log:warn("Gagal lanjut halaman Developer Products", {
					error = tostring(advanceError),
				})
				break
			end
		end

		isRefreshingDonationProducts = false
		if not hadSuccessfulPage and #nextProducts == 0 then
			log:warn("Donation products refresh tanpa halaman valid; cache lama dipertahankan", {
				cachedCount = #donationProducts,
			})
			return
		end

		-- Final sweep: never ship PaidBroadcast / shop IDs even if excluded set was stale at insert.
		local stripIds = getShopProductIdSet()
		local filteredProducts: { DonationProduct } = {}
		local filteredById: { [number]: DonationProduct } = {}
		for _, product in ipairs(nextProducts) do
			if not stripIds[product.productId] then
				table.insert(filteredProducts, product)
				filteredById[product.productId] = product
			end
		end
		nextProducts = filteredProducts
		nextProductsById = filteredById

		table.sort(nextProducts, function(a, b)
			if a.price ~= b.price then
				return a.price < b.price
			end
			return a.name < b.name
		end)

		donationProducts = nextProducts
		donationProductsById = nextProductsById
		donationProductsLastRefresh = os.clock()
		local paidBroadcastId = resolvePaidBroadcastProductId()
		log:info("Donation Robux products refreshed", {
			count = #donationProducts,
			skippedOffsale = skippedOffsale,
			paidBroadcastExcluded = paidBroadcastId,
			excludedShopProducts = table.concat(
				(function()
					local ids = {}
					for id in pairs(excludedIds) do
						table.insert(ids, tostring(id))
					end
					for id in pairs(stripIds) do
						if not excludedIds[id] then
							table.insert(ids, tostring(id))
						end
					end
					table.sort(ids)
					return ids
				end)(),
				","
			),
		})
	end
	local function waitForDonationProducts(maxWaitSeconds: number?): { DonationProduct }
		local deadline = os.clock() + (maxWaitSeconds or DONATION_PRODUCT_FETCH_TIMEOUT)
		while os.clock() < deadline do
			while isRefreshingDonationProducts do
				task.wait(0.05)
			end
			if #donationProducts > 0 then
				return table.clone(donationProducts)
			end
			refreshDonationProducts(true)
			while isRefreshingDonationProducts do
				task.wait(0.05)
			end
			if #donationProducts > 0 then
				return table.clone(donationProducts)
			end
			task.wait(0.35)
		end
		if #donationProducts == 0 then
			log:warn("Donation products masih kosong setelah menunggu refresh", {
				timeout = maxWaitSeconds or DONATION_PRODUCT_FETCH_TIMEOUT,
				isRefreshing = isRefreshingDonationProducts,
			})
		end
		return table.clone(donationProducts)
	end

	local function getDonationProducts(): { DonationProduct }
		return waitForDonationProducts(DONATION_PRODUCT_FETCH_TIMEOUT)
	end
	local function getDonationProduct(productId: number): any?
		if productId <= 0 then
			return nil
		end
		local product = donationProductsById[productId]
		if product then
			return product
		end
		refreshDonationProducts(true)
		return donationProductsById[productId]
	end
	local function fireDonationResult(player: Player?, payload: { [string]: any })
		if not player then
			return
		end
		local network = ensureDonationResultNetwork()
		if network then
			network:fireClient(player, payload)
		end
	end
	local function getUserThumbnail(userId: number): string
		local ok, thumbnail = pcall(function()
			local content =
				Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
			return content
		end)
		if ok and type(thumbnail) == "string" then
			return thumbnail
		end
		return ""
	end
	local function refreshWorkspaceLeaderboards()
		if workspaceLeaderboardRefresh and workspaceLeaderboardRefresh.refresh then
			task.spawn(workspaceLeaderboardRefresh.refresh)
			return
		end
		log:warn("Workspace leaderboard refresh hook missing; Robux donation UI may be stale")
	end
	local function assignRobuxTopDonate(player: Player)
		if not leaderboardRepository or not overheadRepository or not overheadController then
			return
		end
		local hiddenUserIds = Config.Leaderboards.HIDDEN_ROBUX_USER_IDS
		if type(hiddenUserIds) == "table" and hiddenUserIds[player.UserId] == true then
			local updateResult = overheadRepository:update(player.UserId, function(current)
				return OverheadDomain.mergeStored(current, {
					topDonateRank = OverheadDomain.NIL,
					topDonateText = OverheadDomain.NIL,
					topSpenderRank = OverheadDomain.NIL,
					topSpenderText = OverheadDomain.NIL,
				})
			end)
			if updateResult.ok then
				overheadController:refreshPlayer(player, "recovery")
			end
			return
		end

		task.spawn(function()
			-- Flush dirty leaderboard caches so post-donate resolve sees the write
			-- (background ticker only flushes every ~1s).
			if type(leaderboardRepository.flushDirtyCaches) == "function" then
				leaderboardRepository:flushDirtyCaches()
			end

			local robuxResult = leaderboardRepository:getRobuxLeaderboard(Config.Leaderboards.ROBUX_LIMIT)
			if not robuxResult.ok or type(robuxResult.value) ~= "table" then
				-- Fetch failed: keep previous chip; do not NIL.
				return
			end

			-- Align with donor-profile / overhead lookup (100), not Donation.LEADERBOARD_LIMIT (10).
			local leaderboardLimit = Config.Leaderboards.ROBUX_LIMIT or 100
			local matchedRank: number? = nil
			for rank, entry in ipairs(robuxResult.value) do
				local userId = tonumber(entry.userId) or 0
				if userId == player.UserId then
					matchedRank = rank
					break
				end
			end

			-- Miss / outside board: skip update (keep previous). Clear-on-zero is handled
			-- by overhead refresh when total is confirmed 0 — not here.
			if not matchedRank or matchedRank < 1 or matchedRank > leaderboardLimit then
				return
			end

			local merge = {
				topDonateRank = matchedRank,
				topDonateText = "#" .. tostring(matchedRank) .. " DONATION",
			}

			local updateResult = overheadRepository:update(player.UserId, function(current)
				if current.topDonateRank == matchedRank then
					return current
				end
				return OverheadDomain.mergeStored(current, merge)
			end)
			if updateResult.ok then
				overheadController:refreshPlayer(player, "recovery")
			else
				log:warn("Donation Robux top donate overhead update failed", {
					player = player.Name,
					error = updateResult.error,
				})
			end
		end)
	end
	local function resolveDonationCommunity(player: Player?, userId: number): Types.CommunityData?
		if not player or not overheadService then
			return nil
		end
		-- Prefer the same effective community as overhead badge (/setcommun, else
		-- primary Roblox group when PRIMARY_FALLBACK_ENABLED and not cleared).
		if type(overheadService.resolveEffectiveCommunity) == "function" then
			local effectiveResult = overheadService:resolveEffectiveCommunity(player)
			if effectiveResult.ok then
				return effectiveResult.value
			end
			log:debug("Donation community effective resolve failed", {
				userId = userId,
				error = effectiveResult.error,
			})
		end
		-- Legacy fallback if older OverheadService without resolveEffectiveCommunity.
		if type(overheadService.getStored) ~= "function" or type(overheadService.resolveCommunity) ~= "function" then
			return nil
		end
		local storedResult = overheadService:getStored(userId)
		if not storedResult.ok or not storedResult.value.communityId then
			return nil
		end
		local communityResult = overheadService:resolveCommunity(player, storedResult.value.communityId)
		if communityResult.ok then
			return communityResult.value
		end
		return {
			id = storedResult.value.communityId,
			name = "Community " .. tostring(storedResult.value.communityId),
			logo = "",
		}
	end
	-- ProcessReceipt - dipanggil Roblox Engine setelah purchase berhasil
	-- WAJIB return Enum.ProductPurchaseDecision
	MarketplaceService.ProcessReceipt = function(receiptInfo: {
		PlayerId: number,
		ProductId: number,
		PurchaseId: string,
		[string]: any,
	}): Enum.ProductPurchaseDecision
		local purchaseId = receiptInfo.PurchaseId
		local userId = receiptInfo.PlayerId
		local productId = receiptInfo.ProductId
		-- Idempotency TTL-based - cleanup expired, lalu cek
		local now = os.clock()
		for pid, expiresAt in pairs(processedPurchases) do
			if expiresAt <= now then
				processedPurchases[pid] = nil
			end
		end
		if processedPurchases[purchaseId] then
			log:warn("Duplicate ProcessReceipt skipped", { purchaseId = purchaseId, userId = userId })
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		local function markPurchaseProcessed()
			processedPurchases[purchaseId] = os.clock() + Config.Security.PURCHASE_DEDUPE_WINDOW
		end

		local paidProductId = Config.PaidBroadcast.PRODUCT_ID
		if
			paidProductId > 0
			and productId == paidProductId
			and paidBroadcastController
			and type(paidBroadcastController.processReceipt) == "function"
		then
			local decision = paidBroadcastController:processReceipt(receiptInfo)
			if decision == Enum.ProductPurchaseDecision.PurchaseGranted then
				markPurchaseProcessed()
			end
			return decision
		end

		-- Legacy self-buy Developer Product (kept so in-flight / old BuyId still grant)
		local isBuy, buyTier = ShopDomain.isBuyProduct(productId)
		if isBuy and buyTier then
			local result = shopService:grantMembership(userId, buyTier)
			if result.ok then
				notifyClient(userId, buyTier, false, nil)
				local player = Players:GetPlayerByUserId(userId)
				if player then
					overheadController:refreshPlayer(player)
				end
				log:info("Legacy buy product processed", { userId = userId, tier = buyTier, productId = productId })
				markPurchaseProcessed()
				return Enum.ProductPurchaseDecision.PurchaseGranted
			else
				log:error("Legacy buy grant fail", { userId = userId, error = result.error })
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
		end
		-- Cek gift product — peek pending, grant, then consume (so grant fail keeps pending for retry)
		local isGift, giftTier = ShopDomain.isGiftProduct(productId)
		if isGift and giftTier then
			local toId = shopService:resolvePendingGift(userId)
			if not toId then
				log:warn("Gift processed but no pending found — deferring for retry", {
					userId = userId,
					purchaseId = purchaseId,
				})
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
			local result = shopService:grantMembership(toId, giftTier)
			if result.ok then
				shopService:consumePendingGift(userId)
				-- Ambil nama pengirim untuk notif giftee
				local sender = Players:GetPlayerByUserId(userId)
				local fromName = sender and sender.DisplayName or "Someone"
				notifyClient(toId, giftTier, true, fromName)
				-- Refresh overhead giftee
				local giftee = Players:GetPlayerByUserId(toId)
				if giftee then
					overheadController:refreshPlayer(giftee)
				end
				log:info("Gift processed", { from = userId, to = toId, tier = giftTier })
				markPurchaseProcessed()
				return Enum.ProductPurchaseDecision.PurchaseGranted
			else
				log:error("Gift grant fail", { to = toId, error = result.error })
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
		end
		local donationProduct = getDonationProduct(productId)
		if donationProduct then
			local player = Players:GetPlayerByUserId(userId)
			local pending = pendingDonations[userId]
			pendingDonations[userId] = nil
			local message = ""
			if pending and pending.productId == productId and pending.expiresAt > os.clock() then
				message = pending.message
			end
			local price = tonumber(donationProduct.price) or 0
			local donorName = player and player.DisplayName or ("User " .. tostring(userId))
			local hiddenUserIds = Config.Leaderboards.HIDDEN_ROBUX_USER_IDS
			local isHiddenRobuxDonor = type(hiddenUserIds) == "table" and hiddenUserIds[userId] == true
			local isDuplicateReceipt = false
			if isHiddenRobuxDonor then
				if donationService and type(donationService.recordRobuxDonationDaily) == "function" then
					local okSession, errSession = pcall(function()
						donationService:recordRobuxDonationDaily({
							userId = userId,
							username = player and player.Name or ("User" .. tostring(userId)),
							displayName = donorName,
							thumbnail = getUserThumbnail(userId),
							amount = price,
						})
					end)
					if not okSession then
						log:warn("Hidden Robux session tracking failed", {
							userId = userId,
							error = tostring(errSession),
						})
					end
				end
				if donationService and type(donationService.invalidateDonorProfileCache) == "function" then
					donationService:invalidateDonorProfileCache(userId)
				end
				if player and overheadService and type(overheadService.invalidateRankCaches) == "function" then
					overheadService:invalidateRankCaches(userId)
				end
				if player and overheadController then
					overheadController:refreshPlayer(player, "recovery")
				end
				if player then
					assignRobuxTopDonate(player)
				end
			elseif leaderboardRepository and type(leaderboardRepository.recordRobuxDonation) == "function" then
				local recordResult = leaderboardRepository:recordRobuxDonation({
					purchaseId = purchaseId,
					userId = userId,
					username = player and player.Name or ("User" .. tostring(userId)),
					displayName = donorName,
					thumbnail = getUserThumbnail(userId),
					amount = price,
					productId = productId,
					community = resolveDonationCommunity(player, userId),
				}, { receiptMode = true })
				if not recordResult.ok then
					log:error("Donation Robux leaderboard write failed", {
						userId = userId,
						productId = productId,
						price = price,
						error = recordResult.error,
					})
					return Enum.ProductPurchaseDecision.NotProcessedYet
				end
				isDuplicateReceipt = recordResult.value == "duplicate"
				if isDuplicateReceipt then
					log:info("Duplicate Robux donation receipt — skipping side effects", {
						purchaseId = purchaseId,
						userId = userId,
					})
				else
					if donationService and type(donationService.invalidateDonorProfileCache) == "function" then
						donationService:invalidateDonorProfileCache(userId)
					end
					if player and overheadService and type(overheadService.invalidateRankCaches) == "function" then
						overheadService:invalidateRankCaches(userId)
					end
					if player and overheadController then
						overheadController:refreshPlayer(player, "recovery")
					end
					if player and leaderboardNetwork then
						leaderboardNetwork:fireClient(player, { type = "donation_sheets_refresh" })
					end
					refreshWorkspaceLeaderboards()
					if player then
						assignRobuxTopDonate(player)
					end
					if donationService and type(donationService.recordRobuxDonationDaily) == "function" then
						local okDaily, errDaily = pcall(function()
							donationService:recordRobuxDonationDaily({
								userId = userId,
								username = player and player.Name or ("User" .. tostring(userId)),
								displayName = donorName,
								thumbnail = getUserThumbnail(userId),
								amount = price,
							})
						end)
						if not okDaily then
							log:warn("Daily Robux tracking failed", {
								userId = userId,
								error = tostring(errDaily),
							})
						end
					end
				end
			end
			if not isDuplicateReceipt and player and donationEffectService and type(donationEffectService.playRobuxDonation) == "function" then
				local effectOk, effectResult = pcall(function()
					return donationEffectService:playRobuxDonation(player, price)
				end)
				if not effectOk then
					log:warn("Donation Robux effect failed", {
						userId = userId,
						productId = productId,
						price = price,
						error = tostring(effectResult),
					})
				elseif not effectResult.ok then
					log:warn("Donation Robux effect skipped", {
						userId = userId,
						productId = productId,
						price = price,
						error = effectResult.error,
					})
				end
			end



			if not isDuplicateReceipt then
				local description = if message ~= ""
					then string.format("%s donated %d Robux: %s", donorName, price, message)
					else string.format("%s donated %d Robux.", donorName, price)
				if notifRemote then
					local notifPayload = {
						saweriaName = donorName,
						amount = price,
						message = message ~= "" and message or nil,
						newRank = nil,
						robloxUsername = player and player.Name or nil,
						robloxUserId = userId,
						totalDonationAmount = price,
						source = "robux",
					}
					log:info("Donation Robux notification broadcast", {
						userId = userId,
						productId = productId,
						amount = price,
						username = notifPayload.robloxUsername,
					})
					if notifNetwork then
						notifNetwork:fireAllClients(notifPayload)
					end
				end
				if notify then
					local delaySec = Config.Donation.NOTIF_SHOW_DURATION + 10
					task.delay(delaySec, function()
						log:debug("Firing delayed general notif", { delay = delaySec, purchaseId = purchaseId })
						notify.all({
							message = description,
							title = "Donation",
							description = description,
							notifType = "SUCCESS",
							domain = "donation",
							dedupeKey = "donation-robux-" .. purchaseId,
						}, "SUCCESS")
					end)
				end
				fireDonationResult(player, {
					ok = true,
					productId = productId,
					price = price,
					message = message,
				})
			end
			log:info("Donation Robux processed", {
				userId = userId,
				productId = productId,
				price = price,
			})
			markPurchaseProcessed()
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		-- ProductId tidak dikenal oleh shop - mungkin sistem lain
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	function controller.init(_self: IShopController)
		-- Game Pass self-buy completion + join ownership sync (does not wipe legacy membershipBadge)
		MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gamePassId: number, wasPurchased: boolean)
			if not wasPurchased then
				return
			end
			local isPass, tier = ShopDomain.isBuyGamePass(gamePassId)
			if not isPass or not tier then
				return
			end
			local result = shopService:grantMembershipIfHigher(player.UserId, tier)
			if result.ok then
				notifyClient(player.UserId, tier, false, nil)
				overheadController:refreshPlayer(player)
				log:info("Game Pass buy processed", { userId = player.UserId, tier = tier, gamePassId = gamePassId })
			else
				log:error("Game Pass buy grant fail", { userId = player.UserId, tier = tier, error = result.error })
			end
		end)

		local function onPlayerForGamePassSync(player: Player)
			task.defer(function()
				if player.Parent then
					syncOwnedGamePasses(player)
				end
			end)
		end
		Players.PlayerAdded:Connect(onPlayerForGamePassSync)
		for _, player in ipairs(Players:GetPlayers()) do
			onPlayerForGamePassSync(player)
		end

		-- ShopGiftPending: Client memberi tahu server siapa yang akan di-gift
		-- sebelum PromptProductPurchase dipanggil di client
		local giftRemote = remotes:FindFirstChild(REMOTE_GIFT_INIT)
		if not giftRemote then
			log:warn("Remote tidak ditemukan: " .. REMOTE_GIFT_INIT, {})
			return
		end
		(giftRemote :: RemoteEvent).OnServerEvent:Connect(function(player: Player, raw: any)
			local sizeOk = Validator.checkSize(raw)
			if not sizeOk then
				log:warn("Gift payload rejected: too large", { player = player.Name })
				return
			end
			local validation = Validator.shopGiftPending(raw)
			if not validation.valid then
				log:warn("Gift payload rejected: invalid schema", {
					player = player.Name,
					errors = validation.errors,
				})
				return
			end
			-- Rate limit
			local allowed = giftLimiter:check(player.UserId)
			if not allowed then
				log:warn("Gift rate limited", { player = player.Name })
				return
			end
			-- TTL-based dedup - cleanup expired, lalu cek
			local now2 = os.clock()
			for key, expiresAt in pairs(processedGiftReqs) do
				if expiresAt <= now2 then
					processedGiftReqs[key] = nil
				end
			end
			if processedGiftReqs[raw.requestId] then
				return
			end
			processedGiftReqs[raw.requestId] = now2 + Config.Security.REQUEST_DEDUPE_WINDOW
			-- Validasi tier
			if not ShopDomain.isShopTier(raw.tier) then
				log:warn("Invalid gift tier", { player = player.Name, tier = raw.tier })
				return
			end
			if raw.toId == player.UserId then
				log:warn("Gift target rejected: self target", { player = player.Name })
				return
			end
			if not Players:GetPlayerByUserId(raw.toId) then
				log:warn("Gift target rejected: offline or missing", {
					player = player.Name,
					targetUserId = raw.toId,
				})
				return
			end
			-- Simpan pending
			local result = shopService:storePendingGift(player.UserId, raw.toId)
			if not result.ok then
				log:error("storePendingGift fail", { error = result.error })
				return
			end
		end)
		local donationProductsRemote = remotes:FindFirstChild(Config.Donation.REMOTE_ROBUX_PRODUCTS)
		local donationProductsResponseRemote = remotes:FindFirstChild(Config.Donation.REMOTE_ROBUX_PRODUCTS_RESPONSE)
		if
			donationProductsRemote
			and donationProductsRemote:IsA("RemoteEvent")
			and donationProductsResponseRemote
			and donationProductsResponseRemote:IsA("RemoteEvent")
		then
			donationProductsNetwork = NetworkManager.create({
				reliable = donationProductsResponseRemote :: RemoteEvent,
				logger = log,
				isServer = true,
			})
			local function fireDonationProductsResponse(
				player: Player,
				requestId: string,
				products: { DonationProduct },
				errorCode: string?
			)
				donationProductsNetwork:fireClient(player, {
					type = "donation_products_response",
					requestId = requestId,
					ok = #products > 0,
					data = products,
					error = if #products > 0 then nil else (errorCode or "products_not_ready"),
				})
			end

			donationProductsRemote.OnServerEvent:Connect(function(player: Player, raw: any)
				if not Validator.checkSize(raw) then
					log:warn("Donation products payload rejected: too large", { player = player.Name })
					return
				end
				if type(raw) ~= "table" or type(raw.requestId) ~= "string" or raw.requestId == "" then
					return
				end
				local requestId = raw.requestId
				local rateOk = donationProductsLimiter:check(player.UserId)
				if not rateOk then
					log:warn("Donation products request rate limited", { player = player.Name })
					fireDonationProductsResponse(player, requestId, {}, "rate_limited")
					return
				end
				local now = os.clock()
				for key, expiresAt in pairs(processedDonationProductReqs) do
					if expiresAt <= now then
						processedDonationProductReqs[key] = nil
					end
				end
				if processedDonationProductReqs[requestId] then
					return
				end
				processedDonationProductReqs[requestId] = now + Config.Security.REQUEST_DEDUPE_WINDOW

				task.spawn(function()
					local products = waitForDonationProducts(DONATION_PRODUCT_FETCH_TIMEOUT)
					fireDonationProductsResponse(player, requestId, products)
				end)
			end)
		else
			log:warn("Donation products remote tidak ditemukan", {
				remote = Config.Donation.REMOTE_ROBUX_PRODUCTS,
				responseRemote = Config.Donation.REMOTE_ROBUX_PRODUCTS_RESPONSE,
			})
		end
		task.spawn(function()
			refreshDonationProducts(true)
		end)

		local donationRemote = remotes:FindFirstChild(Config.Donation.REMOTE_ROBUX_INIT)
		if donationRemote and donationRemote:IsA("RemoteEvent") then
			donationRemote.OnServerEvent:Connect(function(player: Player, raw: any)
				if not Validator.checkSize(raw) then
					log:warn("Donation pending payload rejected: too large", { player = player.Name })
					return
				end
				if type(raw) ~= "table" then
					return
				end
				if not donationLimiter:check(player.UserId) then
					log:warn("Donation pending rate limited", { player = player.Name })
					return
				end
				local productId = tonumber(raw.productId)
				if not productId or not getDonationProduct(productId) then
					log:warn("Donation pending rejected: unknown product", {
						player = player.Name,
						productId = productId,
					})
					return
				end
				local message = if type(raw.message) == "string" then raw.message else ""
				message = string.sub(message, 1, Config.Donation.ROBUX_MESSAGE_MAX_LENGTH)
				message = filterForBroadcast(player.UserId, message)
				pendingDonations[player.UserId] = {
					productId = productId,
					message = message,
					expiresAt = os.clock() + Config.Donation.ROBUX_PENDING_TIMEOUT,
				}
			end)
		else
			log:warn("Donation pending remote tidak ditemukan", {
				remote = Config.Donation.REMOTE_ROBUX_INIT,
			})
		end
		log:info("ShopController initialized", {})
	end
	return controller
end
return createShopController
