--!strict

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local OverheadController = require(script.Parent.Parent.Controllers.OverheadController)

type DonorProfilePayload = Types.DonorProfilePayload

export type DonationProduct = {
	key: string,
	name: string,
	price: number,
	productId: number,
}

export type DonationResultPayload = {
	ok: boolean,
	productId: number?,
	price: number?,
	message: string?,
	error: string?,
}

export type Service = {
	getProducts: (self: Service) -> { DonationProduct },
	refreshProducts: (self: Service) -> { DonationProduct },
	promptDonate: (self: Service, product: DonationProduct, message: string) -> (),
	onResult: (self: Service, callback: (payload: DonationResultPayload) -> ()) -> (),
	requestDonorProfile: (self: Service) -> DonorProfilePayload?,
	invalidateDonorProfileCache: (self: Service) -> (),
}

local function trim(text: string): string
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function truncateUtf8(text: string, maxChars: number): string
	if maxChars <= 0 then
		return ""
	end

	local ok, length = pcall(utf8.len, text)
	if not ok or type(length) ~= "number" or length <= maxChars then
		return text
	end

	local byteIndex = utf8.offset(text, maxChars + 1)
	if not byteIndex then
		return text
	end
	return string.sub(text, 1, byteIndex - 1)
end

local function createDonationRobuxService(deps: {
	remotes: Folder,
	logger: any?,
}): Service
	local remotes = deps.remotes
	local localPlayer = Players.LocalPlayer
	local log = deps.logger or Logger.new("DonationSystem")
	local resultCallbacks = {} :: { (payload: DonationResultPayload) -> () }
	local pendingProductRequests = {} :: { [string]: any }
	local pendingProfileRequests = {} :: { [string]: any }
	local productResponseConnection = nil :: RBXScriptConnection?
	local profileResponseConnection = nil :: RBXScriptConnection?
	local resultResponseConnection = nil :: RBXScriptConnection?
	local cachedProducts: { DonationProduct } = {}
	local productsRefreshInFlight = false
	local productsRefreshWaiters = {} :: { BindableEvent }
	local cachedServerDonorProfile: DonorProfilePayload? = nil
	local serverDonorProfileExpiresAt = 0
	local serverDonorProfileFetchInFlight = false
	local serverDonorProfileFetchWaiters = {} :: { BindableEvent }
	-- Circuit breaker: after donor profile remote timeouts / rate-limits, skip
	-- the next remote call and fall back to overhead cached data.
	local donorProfileRemoteCooldownUntil = 0
	local service = {} :: Service

	local function sanitizeDonorProfile(profile: DonorProfilePayload?): DonorProfilePayload?
		if type(profile) ~= "table" then
			return nil
		end
		local robuxTotal = math.max(0, math.floor(tonumber(profile.robuxTotal) or 0))
		local cashTotal = math.max(0, math.floor(tonumber(profile.cashTotal) or 0))
		local robuxRank = tonumber(profile.robuxRank)
		local cashRank = tonumber(profile.cashRank)
		if robuxTotal <= 0 then
			robuxRank = nil
		end
		if cashTotal <= 0 then
			cashRank = nil
		end
		local sanitized = table.clone(profile)
		sanitized.robuxTotal = robuxTotal
		sanitized.robuxRank = robuxRank
		sanitized.cashTotal = cashTotal
		sanitized.cashRank = cashRank
		return sanitized
	end

	local function mergeDonorProfiles(
		overheadProfile: DonorProfilePayload?,
		serverProfile: DonorProfilePayload?
	): DonorProfilePayload?
		local merged: DonorProfilePayload? = nil
		for _, profile in ipairs({ overheadProfile, serverProfile }) do
			if type(profile) ~= "table" then
				continue
			end
			if not merged then
				merged = table.clone(profile)
				continue
			end
			local overheadRobux = merged.robuxTotal or 0
			local serverRobux = profile.robuxTotal or 0
			local overheadCash = merged.cashTotal or 0
			local serverCash = profile.cashTotal or 0
			-- Trust a zero from either side so clears sync; otherwise keep the higher live total.
			if overheadRobux <= 0 or serverRobux <= 0 then
				merged.robuxTotal = math.min(overheadRobux, serverRobux)
			elseif serverRobux > overheadRobux then
				merged.robuxTotal = serverRobux
			end
			if overheadCash <= 0 or serverCash <= 0 then
				merged.cashTotal = math.min(overheadCash, serverCash)
			elseif serverCash > overheadCash then
				merged.cashTotal = serverCash
			end
			if (merged.robuxTotal or 0) > 0 then
				-- Nil rank from one side must not drop a known numeric rank (total > 0).
				if type(profile.robuxRank) == "number" then
					if type(merged.robuxRank) == "number" then
						merged.robuxRank = math.min(merged.robuxRank, profile.robuxRank)
					else
						merged.robuxRank = profile.robuxRank
					end
				end
			else
				merged.robuxRank = nil
			end
			if (merged.cashTotal or 0) > 0 then
				if type(profile.cashRank) == "number" then
					if type(merged.cashRank) == "number" then
						merged.cashRank = math.min(merged.cashRank, profile.cashRank)
					else
						merged.cashRank = profile.cashRank
					end
				end
			else
				merged.cashRank = nil
			end
			if type(profile.displayName) == "string" and profile.displayName ~= "" then
				merged.displayName = profile.displayName
			end
		end
		return sanitizeDonorProfile(merged)
	end

	local function profileFromOverheadCache(): DonorProfilePayload?
		local payload = OverheadController.getCachedPayload(localPlayer.UserId)
		if not payload then
			return nil
		end
		local robuxRank = tonumber(payload.topDonateRank)
		local cashRank = tonumber(payload.topSpenderRank)
		local robuxTotal = math.max(0, math.floor(tonumber(payload.robuxDonated) or 0))
		local cashTotal = math.max(0, math.floor(tonumber(payload.cashDonated) or 0))
		return sanitizeDonorProfile({
			userId = localPlayer.UserId,
			username = localPlayer.Name,
			displayName = if type(payload.displayName) == "string" and payload.displayName ~= ""
				then payload.displayName
				else localPlayer.DisplayName,
			robuxTotal = robuxTotal,
			robuxRank = robuxRank,
			cashTotal = cashTotal,
			cashRank = cashRank,
		})
	end

	local function connectProductsResponse(responseRemote: RemoteEvent)
		if productResponseConnection then
			return
		end

		productResponseConnection = responseRemote.OnClientEvent:Connect(function(raw: any)
			if type(raw) ~= "table" or raw.type ~= "donation_products_response" then
				return
			end

			local requestId = raw.requestId
			if type(requestId) ~= "string" then
				return
			end

			local pending = pendingProductRequests[requestId]
			if not pending then
				return
			end

			pending.response = raw
			pending.event:Fire()
		end)
	end

	local function fetchProductsOnce(): ({ DonationProduct }, string?)
		local products = {} :: { DonationProduct }
		local productsRemote = remotes:FindFirstChild(Config.Donation.REMOTE_ROBUX_PRODUCTS)
			or remotes:WaitForChild(Config.Donation.REMOTE_ROBUX_PRODUCTS, 5)
		local responseRemote = remotes:FindFirstChild(Config.Donation.REMOTE_ROBUX_PRODUCTS_RESPONSE)
			or remotes:WaitForChild(Config.Donation.REMOTE_ROBUX_PRODUCTS_RESPONSE, 5)
		if not productsRemote or not productsRemote:IsA("RemoteEvent") then
			log:warn("Donation products remote tidak ditemukan", {
				remote = Config.Donation.REMOTE_ROBUX_PRODUCTS,
			})
			return products, "remote_missing"
		end
		if not responseRemote or not responseRemote:IsA("RemoteEvent") then
			log:warn("Donation products response remote tidak ditemukan", {
				remote = Config.Donation.REMOTE_ROBUX_PRODUCTS_RESPONSE,
			})
			return products, "remote_missing"
		end

		connectProductsResponse(responseRemote)

		local requestId = HttpService:GenerateGUID(false)
		local pending = {
			event = Instance.new("BindableEvent"),
			response = nil,
		}
		pendingProductRequests[requestId] = pending

		local timeoutSeconds = tonumber(Config.Donation.REMOTE_REQUEST_TIMEOUT) or 10
		task.delay(timeoutSeconds, function()
			local activePending = pendingProductRequests[requestId]
			if activePending ~= pending or pending.response ~= nil then
				return
			end

			pending.response = {
				ok = false,
				error = "timeout",
				requestId = requestId,
			}
			pending.event:Fire()
		end)

		local fireOk, fireError = pcall(function()
			(productsRemote :: RemoteEvent):FireServer({
				requestId = requestId,
			})
		end)
		if not fireOk then
			pending.response = {
				ok = false,
				error = tostring(fireError),
				requestId = requestId,
			}
			pending.event:Fire()
		end

		if pending.response == nil then
			pending.event.Event:Wait()
		end

		if pendingProductRequests[requestId] == pending then
			pendingProductRequests[requestId] = nil
		end

		local response = pending.response
		pending.event:Destroy()
		local result = type(response) == "table" and response.data or nil
		if type(response) ~= "table" or response.ok ~= true or type(result) ~= "table" then
			local err = if type(response) == "table" then response.error else response
			log:warn("Gagal mengambil donation products", {
				error = tostring(err),
			})
			return products, if type(err) == "string" then err else "request_failed"
		end

		for _, raw in ipairs(result) do
			if type(raw) == "table" and type(raw.productId) == "number" then
				local price = if type(raw.price) == "number" then raw.price else 0
				local productId = raw.productId
				table.insert(products, {
					key = tostring(raw.key or productId),
					name = if type(raw.name) == "string" and raw.name ~= "" then raw.name else "Donation",
					price = price,
					productId = productId,
				})
			end
		end
		return products, nil
	end

	local function notifyProductsRefreshWaiters()
		local waiters = productsRefreshWaiters
		productsRefreshWaiters = {}
		for _, waiter in ipairs(waiters) do
			waiter:Fire()
			waiter:Destroy()
		end
	end

	function service.getProducts(_self: Service): { DonationProduct }
		if #cachedProducts > 0 then
			return table.clone(cachedProducts)
		end
		return service:refreshProducts()
	end

	function service.refreshProducts(_self: Service): { DonationProduct }
		if productsRefreshInFlight then
			local waiter = Instance.new("BindableEvent")
			table.insert(productsRefreshWaiters, waiter)
			waiter.Event:Wait(35)
			if #cachedProducts > 0 then
				return table.clone(cachedProducts)
			end
		end

		productsRefreshInFlight = true
		table.clear(cachedProducts)

		local maxAttempts = 5
		local lastError: string? = nil
		for attempt = 1, maxAttempts do
			local products, err = fetchProductsOnce()
			lastError = err
			if #products > 0 then
				cachedProducts = products
				productsRefreshInFlight = false
				notifyProductsRefreshWaiters()
				return table.clone(cachedProducts)
			end
			if attempt < maxAttempts then
				local delay = if err == "rate_limited" then 2.5 else (0.5 * attempt)
				task.wait(delay)
			end
		end

		productsRefreshInFlight = false
		notifyProductsRefreshWaiters()
		log:warn("Donation products tetap kosong setelah retry", {
			attempts = maxAttempts,
			error = lastError,
		})
		return {}
	end

	function service.promptDonate(_self: Service, product: DonationProduct, message: string)
		if product.productId <= 0 then
			log:warn("Donation productId belum diisi", {
				key = product.key,
				price = product.price,
			})
			for _, callback in ipairs(resultCallbacks) do
				task.spawn(callback, {
					ok = false,
					productId = product.productId,
					price = product.price,
					error = "Donation product belum dikonfigurasi.",
				})
			end
			return
		end

		local pendingRemote = remotes:FindFirstChild(Config.Donation.REMOTE_ROBUX_INIT) :: RemoteEvent?
		if not pendingRemote then
			log:warn("Donation pending remote tidak ditemukan", {
				remote = Config.Donation.REMOTE_ROBUX_INIT,
			})
			return
		end

		local cleanedMessage = truncateUtf8(trim(message), Config.Donation.ROBUX_MESSAGE_MAX_LENGTH)

		pendingRemote:FireServer({
			requestId = HttpService:GenerateGUID(false),
			productId = product.productId,
			message = cleanedMessage,
		})

		task.delay(Config.Donation.ROBUX_PROMPT_DELAY, function()
			MarketplaceService:PromptProductPurchase(localPlayer, product.productId)
		end)
	end

	function service.onResult(_self: Service, callback: (payload: DonationResultPayload) -> ())
		table.insert(resultCallbacks, callback)
	end

	local function parseDonorProfileResponse(raw: any): DonorProfilePayload?
		if type(raw) ~= "table" or raw.ok ~= true or type(raw.profile) ~= "table" then
			return nil
		end
		local profile = raw.profile
		return {
			userId = tonumber(profile.userId) or localPlayer.UserId,
			username = if type(profile.username) == "string" then profile.username else localPlayer.Name,
			displayName = if type(profile.displayName) == "string" then profile.displayName else localPlayer.DisplayName,
			robuxTotal = math.max(0, math.floor(tonumber(profile.robuxTotal) or 0)),
			robuxRank = tonumber(profile.robuxRank),
			cashTotal = math.max(0, math.floor(tonumber(profile.cashTotal) or 0)),
			cashRank = tonumber(profile.cashRank),
		}
	end

	local function ensureProfileResponseListener(responseRemote: RemoteEvent)
		if profileResponseConnection then
			return
		end
		profileResponseConnection = responseRemote.OnClientEvent:Connect(function(raw: any)
			if type(raw) ~= "table" or raw.type ~= "donor_profile_response" then
				return
			end
			local requestId = raw.requestId
			if type(requestId) ~= "string" then
				return
			end
			local pending = pendingProfileRequests[requestId]
			if not pending then
				return
			end
			pending.response = raw
			pending.event:Fire()
		end)
	end

	local function requestDonorProfileOnce(profileRemote: RemoteEvent, responseRemote: RemoteEvent): (DonorProfilePayload?, string?)
		ensureProfileResponseListener(responseRemote)

		local requestId = HttpService:GenerateGUID(false)
		local bindable = Instance.new("BindableEvent")
		local pending = {
			event = bindable,
			response = nil,
		}
		pendingProfileRequests[requestId] = pending

		local timeout = tonumber(Config.Donation.REMOTE_REQUEST_TIMEOUT) or 30
		local deadline = os.clock() + timeout

		-- Defer FireServer so OnClientEvent listener is always registered before the reply.
		task.defer(function()
			profileRemote:FireServer({
				type = "donor_profile_request",
				requestId = requestId,
			})
		end)

		while type(pending.response) ~= "table" and os.clock() < deadline do
			local remaining = deadline - os.clock()
			if remaining <= 0 then
				break
			end
			pending.event.Event:Wait(math.min(remaining, 0.5))
		end

		pendingProfileRequests[requestId] = nil
		bindable:Destroy()

		if type(pending.response) ~= "table" then
			return nil, "timeout"
		end
		if pending.response.ok ~= true then
			local err = if type(pending.response.error) == "string" then pending.response.error else "request_failed"
			return nil, err
		end
		local profile = parseDonorProfileResponse(pending.response)
		if not profile then
			return nil, "invalid_profile"
		end
		return profile, nil
	end

	local function notifyServerDonorProfileWaiters()
		local waiters = serverDonorProfileFetchWaiters
		serverDonorProfileFetchWaiters = {}
		for _, waiter in ipairs(waiters) do
			waiter:Fire()
			waiter:Destroy()
		end
	end

	local function fetchServerDonorProfile(): DonorProfilePayload?
		local now = os.clock()
		local cacheTtl = tonumber(Config.Donation.DONOR_PROFILE_CACHE_TTL) or 45
		if cachedServerDonorProfile and serverDonorProfileExpiresAt > now then
			return cachedServerDonorProfile
		end

		if serverDonorProfileFetchInFlight then
			local waiter = Instance.new("BindableEvent")
			table.insert(serverDonorProfileFetchWaiters, waiter)
			waiter.Event:Wait(cacheTtl + 5)
			return cachedServerDonorProfile
		end

		if donorProfileRemoteCooldownUntil > now then
			local remaining = math.max(0, donorProfileRemoteCooldownUntil - now)
			log:debug("donor profile remote cooldown active; skipping remote request", {
				userId = localPlayer.UserId,
				remainingSeconds = remaining,
			})
			return nil
		end

		serverDonorProfileFetchInFlight = true
		local serverProfile: DonorProfilePayload? = nil
		local lastRemoteError: string? = nil
		local profileRemote = remotes:FindFirstChild(Config.Donation.REMOTE_DONOR_PROFILE)
			or remotes:WaitForChild(Config.Donation.REMOTE_DONOR_PROFILE, 5)
		local responseRemote = remotes:FindFirstChild(Config.Donation.REMOTE_DONOR_PROFILE_RESPONSE)
			or remotes:WaitForChild(Config.Donation.REMOTE_DONOR_PROFILE_RESPONSE, 5)
		if profileRemote and profileRemote:IsA("RemoteEvent")
			and responseRemote and responseRemote:IsA("RemoteEvent")
		then
			local maxAttempts = 2
			for attempt = 1, maxAttempts do
				local profile, err = requestDonorProfileOnce(profileRemote, responseRemote)
				if profile then
					serverProfile = profile
					log:debug("Donor profile remote received", {
						robuxTotal = profile.robuxTotal,
						robuxRank = profile.robuxRank,
						attempt = attempt,
					})
					donorProfileRemoteCooldownUntil = 0
					break
				end
				lastRemoteError = err
				if attempt < maxAttempts then
					local delay = if err == "rate_limited" then 2.5 else (0.6 * attempt)
					task.wait(delay)
				else
					log:warn("Donor profile remote failed; using overhead fallback", {
						attempts = maxAttempts,
						error = err,
					})
				end
			end
		else
			log:warn("Donor profile remotes missing; using overhead fallback")
		end

		if serverProfile then
			cachedServerDonorProfile = serverProfile
			serverDonorProfileExpiresAt = os.clock() + cacheTtl
		elseif lastRemoteError == "timeout" or lastRemoteError == "rate_limited" then
			-- Start cooldown only for timeout / rate-limited errors, to avoid remote call storms.
			local cooldownSeconds = 45
			donorProfileRemoteCooldownUntil = os.clock() + cooldownSeconds
			cachedServerDonorProfile = nil
			serverDonorProfileExpiresAt = 0
			log:info("donor profile remote cooldown started", {
				userId = localPlayer.UserId,
				cooldownSeconds = cooldownSeconds,
				reason = lastRemoteError,
			})
		end

		serverDonorProfileFetchInFlight = false
		notifyServerDonorProfileWaiters()
		return serverProfile
	end

	function service.invalidateDonorProfileCache(_self: Service)
		cachedServerDonorProfile = nil
		serverDonorProfileExpiresAt = 0
		log:debug("donor profile cache invalidated", {
			userId = localPlayer.UserId,
		})
	end

	function service.requestDonorProfile(_self: Service): DonorProfilePayload?
		local overheadProfile = profileFromOverheadCache()
		local serverProfile = fetchServerDonorProfile()
		local merged = mergeDonorProfiles(overheadProfile, serverProfile)
		if merged then
			log:debug("donor profile merged", {
				userId = localPlayer.UserId,
				robuxTotal = merged.robuxTotal,
				robuxRank = merged.robuxRank,
				cashTotal = merged.cashTotal,
				cashRank = merged.cashRank,
				hasOverhead = overheadProfile ~= nil,
				hasServer = serverProfile ~= nil,
			})
			return merged
		end
		log:debug("donor profile empty after merge", {
			userId = localPlayer.UserId,
			hasOverhead = overheadProfile ~= nil,
			hasServer = serverProfile ~= nil,
		})
		return overheadProfile or serverProfile
	end

	task.spawn(function()
		local productsResponseRemote = remotes:WaitForChild(Config.Donation.REMOTE_ROBUX_PRODUCTS_RESPONSE, 30)
		if productsResponseRemote and productsResponseRemote:IsA("RemoteEvent") then
			connectProductsResponse(productsResponseRemote)
		end
	end)

	task.spawn(function()
		local responseRemote = remotes:WaitForChild(Config.Donation.REMOTE_DONOR_PROFILE_RESPONSE, 30)
		if responseRemote and responseRemote:IsA("RemoteEvent") then
			ensureProfileResponseListener(responseRemote)
		end
	end)

	task.spawn(function()
		local resultRemote = remotes:WaitForChild(Config.Donation.REMOTE_ROBUX_RESULT, 30) :: RemoteEvent?
		if not resultRemote then
			log:warn("Donation result remote tidak ditemukan", {
				remote = Config.Donation.REMOTE_ROBUX_RESULT,
			})
			return
		end

		resultResponseConnection = resultRemote.OnClientEvent:Connect(function(raw: any)
			if type(raw) ~= "table" then
				return
			end

			local payload: DonationResultPayload = {
				ok = raw.ok == true,
				productId = if type(raw.productId) == "number" then raw.productId else nil,
				price = if type(raw.price) == "number" then raw.price else nil,
				message = if type(raw.message) == "string" then raw.message else nil,
				error = if type(raw.error) == "string" then raw.error else nil,
			}

			for _, callback in ipairs(resultCallbacks) do
				task.spawn(callback, payload)
			end
		end)
	end)

	function service:destroy()
		if productResponseConnection then
			productResponseConnection:Disconnect()
			productResponseConnection = nil
		end
		if profileResponseConnection then
			profileResponseConnection:Disconnect()
			profileResponseConnection = nil
		end
		if resultResponseConnection then
			resultResponseConnection:Disconnect()
			resultResponseConnection = nil
		end
	end

	return service
end

return createDonationRobuxService
