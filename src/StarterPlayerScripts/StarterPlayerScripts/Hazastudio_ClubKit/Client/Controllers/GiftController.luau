--!strict
-- Client/Controllers/GiftController.lua
-- Wire GiftUI events ke ShopService.
-- Handles: tab switch, player list, username resolve, gift send, notif routing.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local GiftUIModule = require(script.Parent.Parent.UI.GiftUI)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
type ShopService = {
	promptGift: (self: any, tier: string, toUserId: number) -> (),
	onGranted: (self: any, callback: (payload: any) -> ()) -> (),
}
local TIERS = Config.Membership.SHOP_TIERS
local function init(
	deps: {
		shopService: ShopService,
		remotes: Folder,
		icon: any?, -- TopbarPlus icon (opsional, bisa nil)
	}
)
	local shopService = deps.shopService
	local topbarIcon = deps.icon
	local log = Logger.new("Client.GiftController")
	local connections: { RBXScriptConnection } = {}
	local function track(conn: RBXScriptConnection): RBXScriptConnection
		table.insert(connections, conn)
		return conn
	end
	-- Buat UI
	local localPlayer = Players.LocalPlayer
	local gui = localPlayer.PlayerGui:WaitForChild(Config.Gift.GUI_NAME, 30) :: ScreenGui?
	if not gui then
		log:warn("GUI " .. Config.Gift.GUI_NAME .. " tidak ditemukan")
		return {
			show = function() end,
			hide = function() end,
			destroy = function() end,
		}
	end
	local ui = GiftUIModule.new(gui)
	-- Resolve username -> userId secara async lalu promptGift
	-- Mengembalikan feedback ke UI jika username tidak ditemukan
	local function resolveAndGift(tier: string, username: string)
		task.spawn(function()
			-- Beri visual loading state
			ui:setInputText("Mencari " .. username .. "...")
			local ok, userId = pcall(function()
				return Players:GetUserIdFromNameAsync(username)
			end)
			if not ok or type(userId) ~= "number" then
				-- Tampilkan error di input field
				ui:setInputText("Username tidak ditemukan: " .. username)
				task.delay(2, function()
					ui:clearInput()
				end)
				return
			end
			shopService:promptGift(tier, userId)
			ui:clearInput()
		end)
	end
	-- ============================================================
	-- Bind tab buttons
	-- ============================================================
	for _, tier in ipairs(TIERS) do
		local t = tier -- capture
		ui:bindTabButton(t, function()
			ui:setTab(t)
		end)
	end
	-- ============================================================
	-- Bind gift buttons
	-- ============================================================
	for _, tier in ipairs(TIERS) do
		local t = tier
		ui:bindGiftButton(t, function()
			local userId, username = ui:getTarget()
			if userId then
				-- Player dipilih dari list
				shopService:promptGift(t, userId)
				ui:clearInput()
			elseif username and #username > 0 then
				-- Username diketik manual - perlu async lookup
				resolveAndGift(t, username)
			else
				log:warn("Tidak ada target gift")
			end
		end)
	end
	-- ============================================================
	-- Bind close
	-- ============================================================
	ui:bindClose(function()
		ui:hide()
		if topbarIcon then
			topbarIcon:deselect()
		end
	end)
	-- ============================================================
	-- Bind notif close ("Wow, thanks!")
	-- ============================================================
	ui:bindNotifClose(function()
		ui:hideNotification()
	end)
	-- ============================================================
	-- Populate player list (online players kecuali diri sendiri)
	-- ============================================================
	local function refreshPlayerList(forceRefresh: boolean?)
		if not forceRefresh and not ui:isVisible() then
			return
		end
		local list: { { userId: number, displayName: string, username: string } } = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= localPlayer then
				table.insert(list, {
					userId = p.UserId,
					displayName = p.DisplayName,
					username = p.Name,
				})
			end
		end
		ui:populatePlayers(list)
	end
	if ui:isVisible() then
		refreshPlayerList(true)
	end
	track(Players.PlayerAdded:Connect(function()
		refreshPlayerList(false)
	end))
	track(Players.PlayerRemoving:Connect(function()
		refreshPlayerList(false)
	end))
	-- ============================================================
	-- Listen ShopGrantNotif - route gift notifications ke GiftUI
	-- ============================================================
	shopService:onGranted(function(payload: any)
		if payload.isGift then
			ui:showNotification(payload.tier, payload.fromName)
		end
		-- Self-purchase notifications are handled by ShopController
	end)
	-- ============================================================
	-- TopbarPlus icon
	-- ============================================================
	if topbarIcon then
		track(topbarIcon.selected:Connect(function()
			refreshPlayerList(true)
			ui:show()
		end))
		track(topbarIcon.deselected:Connect(function()
			ui:hide()
		end))
	end
	local api = {}

	function api.show(selfOrTier: any, maybeTier: string?)
		local tier = if type(selfOrTier) == "table" then maybeTier else selfOrTier
		if tier ~= nil and type(tier) ~= "string" then
			tier = nil
		end
		refreshPlayerList(true)
		ui:show(tier)
	end

	function api.openForTarget(selfOrTargetUserId: any, maybeTargetUserId: any, maybeTier: string?)
		local targetUserId = if type(selfOrTargetUserId) == "table" then maybeTargetUserId else selfOrTargetUserId
		local tier = if type(selfOrTargetUserId) == "table" then maybeTier else maybeTargetUserId

		if type(targetUserId) ~= "number" then
			log:warn("Gift target invalid", { targetUserId = targetUserId })
			return
		end
		if tier ~= nil and type(tier) ~= "string" then
			tier = nil
		end

		refreshPlayerList(true)
		ui:show(tier)
		if not ui:selectPlayerByUserId(targetUserId) then
			log:warn("Gift target not found in player list", { targetUserId = targetUserId })
		end
	end

	function api.hide()
		ui:hide()
	end

	function api.destroy()
		for _, conn in ipairs(connections) do
			conn:Disconnect()
		end
		table.clear(connections)
	end

	return api
end
return { init = init }
