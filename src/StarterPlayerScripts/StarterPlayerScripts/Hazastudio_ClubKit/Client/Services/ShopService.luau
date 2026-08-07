--!strict
-- Client/Services/ShopService.lua
-- Trigger MarketplaceService purchase (Game Pass buy / Developer Product gift),
-- listen for ShopGrantNotif from server.

local MarketplaceService = game:GetService("MarketplaceService")
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local HttpService        = game:GetService("HttpService")

local Config     = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local ShopDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.ShopDomain)
local Logger     = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

local REMOTE_GRANT     = Config.Shop.REMOTE_GRANT
local REMOTE_GIFT_INIT = Config.Shop.REMOTE_GIFT_INIT

export type GrantPayload = {
	tier     : string,
	isGift   : boolean,
	fromName : string,
}

export type IShopService = {
	promptBuy  : (self: IShopService, tier: string) -> (),
	promptGift : (self: IShopService, tier: string, toUserId: number) -> (),
	onGranted  : (self: IShopService, callback: (payload: GrantPayload) -> ()) -> (),
}

local function createShopService(deps: {
	remotes: Folder,
}): IShopService

	local remotes         = deps.remotes
	local grantCallbacks  = {} :: {(payload: GrantPayload) -> ()}
	local localPlayer     = Players.LocalPlayer
	local log             = Logger.new("Client.ShopService")

	local self = {} :: IShopService & { destroy: (self: any) -> () }
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

	-- Call all registered callbacks
	local function fireGranted(payload: GrantPayload)
		for _, cb in ipairs(grantCallbacks) do
			task.spawn(cb, payload)
		end
	end

	-- Listen ShopGrantNotif from server
	-- Pakai task.spawn + WaitForChild so not miss event when server not yet ready
	task.spawn(function()
		local grantRemote = remotes:WaitForChild(REMOTE_GRANT, Config.Shop.REMOTE_READY_TIMEOUT) :: RemoteEvent?
		if not grantRemote then
			log:warn("ShopGrantNotif remote not found", {
				timeout = Config.Shop.REMOTE_READY_TIMEOUT,
			})
			return
		end
		track(grantRemote.OnClientEvent:Connect(function(data: any)
			if type(data) ~= "table"          then return end
			if type(data.tier) ~= "string"    then return end
			fireGranted({
				tier     = data.tier,
				isGift   = data.isGift   == true,
				fromName = type(data.fromName) == "string" and data.fromName or "",
			})
		end))
	end)

	-- Beli for diri sendiri (Game Pass — one-time)
	function self:promptBuy(tier: string)
		local parsedTier = ShopDomain.parseShopTier(tier)
		if not parsedTier then return end

		local product = Config.Shop.PRODUCTS[parsedTier]
		if type(product) ~= "table" then return end
		local gamePassId = tonumber(product.BUY_GAMEPASS_ID)
		if not gamePassId or gamePassId <= 0 then
			log:warn("BUY_GAMEPASS_ID not yet set", { tier = parsedTier })
			return
		end

		MarketplaceService:PromptGamePassPurchase(localPlayer, gamePassId)
	end

	-- Beli sebagai gift for player lain
	-- Flow: send pending to server first, then prompt purchase
	function self:promptGift(tier: string, toUserId: number)
		local parsedTier = ShopDomain.parseShopTier(tier)
		if not parsedTier then return end

		local product = Config.Shop.PRODUCTS[parsedTier]
		if type(product) ~= "table" then return end
		local productId = product.GIFT_ID
		if productId == 0 then
			log:warn("GIFT_ID not yet set", { tier = parsedTier })
			return
		end

		local giftRemote = remotes:FindFirstChild(REMOTE_GIFT_INIT) :: RemoteEvent?
		if not giftRemote then
			log:warn("Gift init remote not found", { remote = REMOTE_GIFT_INIT })
			return
		end

		local requestId = HttpService:GenerateGUID(false)

		-- Tell server: "I want to gift this tier to toUserId"
		giftRemote:FireServer({
			tier      = parsedTier,
			toId      = toUserId,
			requestId = requestId,
		})

		-- Give server time to store pending before purchase prompt
		task.delay(Config.Gift.GIFT_PROMPT_DELAY, function()
			MarketplaceService:PromptProductPurchase(localPlayer, productId)
		end)
	end

	-- Register callback called when membership is granted
	function self:onGranted(callback: (payload: GrantPayload) -> ())
		table.insert(grantCallbacks, callback)
	end

	return self
end

return createShopService
