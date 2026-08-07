--!strict
-- Client/Controllers/ShopController.lua
-- Wiring: UI events -> Service, Service events -> UI.
-- No logic here - only routing.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config            = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger            = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local ShopUIModule      = require(script.Parent.Parent.UI.ShopUI)
local TIERS = Config.Membership.SHOP_TIERS
export type IShopController = {
	init: (self: IShopController) -> (),
	destroy: (self: IShopController) -> (),
}
local function createShopController(deps: {
	gui            : ScreenGui,
	remotes        : Folder,
	shopService    : any,        -- shared IShopService instance from Main.client.lua
	giftController : any?,
	icon           : any,
}): IShopController
	local shopService    = deps.shopService
	local self           = {} :: IShopController
	local giftController = deps.giftController
	local icon           = deps.icon
	local log            = Logger.new("Client.ShopController")
	-- UI is created inside init() so WaitForChild does not block
	-- when createShopController() called from Main.client.lua
	local ui: any = nil
	local _connections: { RBXScriptConnection } = {}
	function self:init()
		-- Initialize UI (WaitForChild happens here, not on require/construct)
		ui = ShopUIModule.new(deps.gui)
		local localPlayer = Players.LocalPlayer
		table.insert(_connections, icon.selected:Connect(function() ui:show() end))
		table.insert(_connections, icon.deselected:Connect(function() ui:hide() end))
		-- Bind close modal — also deselect icon so state stays in sync
		ui:bindClose(function()
			ui:hide()
			icon:deselect()
		end)
		-- Bind buy + gift per tier
		for _, tier in ipairs(TIERS) do
			local t = tier -- capture for closure
			ui:bindBuyButton(t, function()
				shopService:promptBuy(t)
			end)
			-- Gift: close shop panel first, then open GiftUI with selected tier
			ui:bindGiftButton(t, function()
				icon:deselect()  -- close shop panel
				if giftController then
					giftController.show(t)
				else
					log:warn("GiftController not yet diinject", { tier = t })
				end
			end)
			-- Bind "Wow, thanks!" button in notification
			ui:bindNotifClose(t, function()
				ui:hideNotification()
			end)
		end
		-- After server confirms membership granted, show notification
		shopService:onGranted(function(payload: any)
			-- Gift notifications handled by GiftController
			if payload.isGift then return end
			-- Self-purchase: close shop panel first, then show notification
			icon:deselect()
			local displayName = localPlayer.DisplayName
			task.delay(Config.Shop.NOTIF_SHOW_DELAY, function()
				ui:showNotification(payload.tier, displayName)
			end)
		end)
	end
	function self:destroy()
		for _, conn in ipairs(_connections) do
			conn:Disconnect()
		end
		table.clear(_connections)
	end
	return self
end
return createShopController
