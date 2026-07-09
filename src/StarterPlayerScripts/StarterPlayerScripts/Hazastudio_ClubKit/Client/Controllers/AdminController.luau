--!strict
-- Client/Controllers/AdminController.lua
-- Wire AdminPanelUI -> AdminService -> Server remotes.
-- Controller hanya routing: tidak ada logic, tidak ada retry, tidak ada string parsing.
local HttpService       = game:GetService("HttpService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config         = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local ShopDomain     = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.ShopDomain)
local PermissionDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.PermissionDomain)
local Logger         = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local DeltaCompressor = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DeltaCompressor)
local AdminPanelUI   = require(script.Parent.Parent.UI.AdminPanelUI)
local MobileScaleService = require(script.Parent.Parent.Services.MobileScaleService)
local createAdminService = require(script.Parent.Parent.Services.AdminService)
type OverheadSnapshot = {
	specialTitle: string?,
	specialTitlePreset: string?,
	specialTitleFont: string?,
	specialTitleSize: string?,
}
local log = Logger.new("Client.AdminController")

local _connections: { RBXScriptConnection } = {}

local function track(conn: RBXScriptConnection): RBXScriptConnection
	table.insert(_connections, conn)
	return conn
end

local function destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)
end

local function init(deps: {
	remotes: Folder,
	icon: any?,
})
	local remotes      = deps.remotes
	local topbarIcon   = deps.icon
	local localPlayer  = Players.LocalPlayer
	-- Resolve admin GUI (v2 preferred, v1 fallback)
	local gui: ScreenGui? = nil
	local candidates = Config.Admin.GUI_NAME_CANDIDATES or { Config.Admin.GUI_NAME }
	for _, guiName in ipairs(candidates) do
		local found = localPlayer.PlayerGui:FindFirstChild(guiName)
		if found and found:IsA("ScreenGui") then
			gui = found
			break
		end
	end
	if not gui then
		gui = localPlayer.PlayerGui:WaitForChild(
			Config.Admin.GUI_NAME,
			Config.Admin.GUI_WAIT_TIMEOUT
		) :: ScreenGui?
	end
	if not gui then
		log:warn("GUI tidak ditemukan, AdminController tidak diinisialisasi", {
			guiName = Config.Admin.GUI_NAME,
			timeout = Config.Admin.GUI_WAIT_TIMEOUT,
		})
		return {}
	end
	local ui           = AdminPanelUI.new(gui)
	MobileScaleService.applyAdminPanelLayout(gui)
	local adminService = createAdminService({ remotes = remotes })
	local setTitleRemote   : RemoteEvent? = nil
	local resetTitleRemote : RemoteEvent? = nil
	local isAdmin            = false
	local overheadCache: {[number]: OverheadSnapshot} = {}
	local confirmedTier   : string? = nil
	local confirmedTarget : { userId: number, username: string, displayName: string }? = nil
	-- Forward declaration - didefinisikan setelah task.spawn di bawah
	local updateSelectedSnapshot: () -> ()
	-- Remote setup (non-blocking)
	task.spawn(function()
		local timeout = Config.Shop.REMOTE_READY_TIMEOUT
		setTitleRemote   = remotes:WaitForChild(Config.Admin.REMOTE_SET_TITLE,  timeout) :: RemoteEvent?
		resetTitleRemote = remotes:WaitForChild(Config.Admin.REMOTE_RESET_TITLE, timeout) :: RemoteEvent?
		if setTitleRemote then
			log:info("Admin remotes ready")
		else
			log:warn("Admin remotes TIMEOUT — server AdminController mungkin tidak berjalan")
		end
	end)
	-- ============================================================
	-- OverheadUpdate listener
	--
	-- Server pakai wire format dengan kind=DELTA atau kind=BATCH; payload.role
	-- ada di dalam payload.delta atau di tiap entry payload.payloads. Tanpa
	-- unwrap proper, isAdmin selalu false dan topbar icon gak pernah di-enable.
	-- Pattern di sini mirror ChatTagsController + client OverheadController:
	-- maintain baseline per userId, merge delta, atau iterate batch.
	-- ============================================================
	local payloadBaselines: { [number]: any } = {}
	local NIL_SENTINEL = DeltaCompressor.NIL_SENTINEL

	local function mergeDelta(base: any, delta: any): any
		local result: any = if base then table.clone(base) else {}
		for field, value in delta do
			if value == NIL_SENTINEL then
				result[field] = nil
			else
				result[field] = value
			end
		end
		return result
	end

	local function applyResolvedPayload(payload: any)
		if type(payload) ~= "table" or type(payload.userId) ~= "number" then
			return
		end
		overheadCache[payload.userId] = {
			specialTitle = type(payload.specialTitle) == "string" and payload.specialTitle or nil,
			specialTitlePreset = type(payload.specialTitlePreset) == "string" and payload.specialTitlePreset or nil,
			specialTitleFont = type(payload.specialTitleFont) == "string" and payload.specialTitleFont or nil,
			specialTitleSize = type(payload.specialTitleSize) == "string" and payload.specialTitleSize or nil,
		}
		if payload.userId == localPlayer.UserId then
			local role = tostring(payload.role)
			local wasAdmin = isAdmin
			isAdmin = PermissionDomain.canUseAdminPanel(role, localPlayer.UserId)
			log:debug("Role detected", { role = role, isAdmin = isAdmin })
			if topbarIcon and isAdmin ~= wasAdmin then
				if isAdmin then
					topbarIcon:setEnabled(true)
				else
					topbarIcon:setEnabled(false)
					ui:hide()
				end
			end
		end
		local selectedPlayer = ui:getSelectedPlayer()
		if selectedPlayer and selectedPlayer.userId == payload.userId then
			updateSelectedSnapshot()
		end
	end

	local function ingestFullPayload(payload: any)
		if type(payload) ~= "table" or type(payload.userId) ~= "number" then
			return
		end
		payloadBaselines[payload.userId] = payload
		applyResolvedPayload(payload)
	end

	local function ingestDelta(message: any)
		local userId = if type(message) == "table" then message.userId else nil
		local delta = if type(message) == "table" then message.delta else nil
		if type(userId) ~= "number" or type(delta) ~= "table" then
			return
		end
		local base = payloadBaselines[userId]
		if not base then
			-- First delta untuk userId ini biasanya full state karena force-reset.
			if type(delta.userId) == "number" and type(delta.role) == "string" then
				ingestFullPayload(delta)
			end
			return
		end
		local merged = mergeDelta(base, delta)
		merged.userId = userId
		payloadBaselines[userId] = merged
		applyResolvedPayload(merged)
	end

	local function handleIncoming(payload: any)
		if type(payload) ~= "table" then
			return
		end

		if payload.kind == Config.Overhead.BATCH_MESSAGE_KIND then
			local payloads = payload.payloads
			if type(payloads) ~= "table" then
				return
			end
			for _, item in ipairs(payloads) do
				ingestFullPayload(item)
			end
			return
		end

		if payload.kind == Config.Overhead.DELTA_MESSAGE_KIND then
			ingestDelta(payload)
			return
		end

		-- Legacy non-delta full-payload path.
		ingestFullPayload(payload)
	end

	track(Players.PlayerRemoving:Connect(function(player)
		payloadBaselines[player.UserId] = nil
		overheadCache[player.UserId] = nil
	end))

	-- Attach listener segera kalau remote sudah ada (yang umum karena server
	-- bikin RemoteEvent saat startup, jauh sebelum AdminController.init dipanggil).
	-- Fallback ke task.spawn + WaitForChild kalau belum ada.
	local existingRemote = remotes:FindFirstChild("OverheadUpdate") :: RemoteEvent?
	if existingRemote then
		track(existingRemote.OnClientEvent:Connect(handleIncoming))
	else
		task.spawn(function()
			local remote = remotes:WaitForChild("OverheadUpdate", Config.Shop.REMOTE_READY_TIMEOUT) :: RemoteEvent?
			if not remote then
				log:warn("OverheadUpdate remote tidak tersedia, role detection disabled")
				return
			end
			track(remote.OnClientEvent:Connect(handleIncoming))
		end)
	end
	-- ============================================================
	-- Helpers
	-- ============================================================
	local function refreshPlayerList(forceRefresh: boolean?)
		if not forceRefresh and not ui:isVisible() then
			return
		end
		local players = {}
		for _, player in ipairs(Players:GetPlayers()) do
			table.insert(players, {
				userId      = player.UserId,
				displayName = player.DisplayName,
				username    = player.Name,
			})
		end
		ui:populatePlayers(players)
	end
	-- Definisi sebenarnya - mengisi forward declaration di atas
	updateSelectedSnapshot = function()
		local selectedPlayer = ui:getSelectedPlayer()
		if not selectedPlayer then
			ui:updateSelectedPlayerSnapshot(nil, nil)
			return
		end
		ui:updateSelectedPlayerSnapshot(selectedPlayer, overheadCache[selectedPlayer.userId])
	end
	-- ============================================================
	-- Tab buttons
	-- ============================================================
	ui:bindTabButton("GiveTitle", function()
		ui:setTab("GiveTitle")
	end)
	ui:bindTabButton("Giftcard", function()
		ui:setTab("Giftcard")
		local selectedPlayer = ui:getSelectedPlayer()
		local selectedPackage = ui:getSelectedPackage()
		if selectedPlayer then
			if selectedPackage then
				ui:transitionToConfirmation(selectedPlayer, selectedPackage)
			else
				ui:transitionToPlayerSelected(selectedPlayer)
			end
		else
			ui:transitionToIdle()
		end
	end)
	-- ============================================================
	-- Player selected / deselected
	-- ============================================================
	ui:bindPlayerSelected(function(playerData)
		confirmedTier = nil
		confirmedTarget = nil
		updateSelectedSnapshot()
		if ui:getActiveTab() == "Giftcard" then
			ui:transitionToPlayerSelected(playerData)
		end
	end)
	ui:bindPlayerDeselected(function()
		confirmedTier = nil
		confirmedTarget = nil
		ui:updateSelectedPlayerSnapshot(nil, nil)
		if ui:getActiveTab() == "Giftcard" then
			ui:transitionToIdle()
		end
	end)
	-- ============================================================
	-- GiveTitle: Apply
	-- ============================================================
	ui:bindApplyTitle(function()
		local target = ui:getSelectedPlayer()
		if not target then
			ui:setTitleInputText(Config.Admin.MSG_TITLE_NO_TARGET)
			task.delay(1.5, function()
				if ui:getTitleText() == Config.Admin.MSG_TITLE_NO_TARGET then
					ui:setTitleInputText("")
				end
			end)
			return
		end
		local title = string.gsub(ui:getTitleText(), "^%s*(.-)%s*$", "%1")
		if #title == 0 then
			ui:setTitleInputText("A custom title deserves actual words.")
			task.delay(1.6, function()
				if ui:getTitleText() == "A custom title deserves actual words." then
					ui:setTitleInputText("")
				end
			end)
			return
		end
		if #title > Config.Admin.TITLE_MAX_LENGTH then
			ui:setTitleInputText("Keep it shorter. Premium still fits in one line.")
			task.delay(1.8, function()
				if ui:getTitleText() == "Keep it shorter. Premium still fits in one line." then
					ui:setTitleInputText("")
				end
			end)
			return
		end
		local presetMode = ui:getSelectedPresetMode()
		if not presetMode or presetMode == "" then
			return
		end
		if not setTitleRemote then
			log:warn("setTitleRemote belum siap")
			return
		end
		setTitleRemote:FireServer({
			requestId      = HttpService:GenerateGUID(false),
			targetUsername = target.username,
			title          = title,
			titleSize      = ui:getSelectedSize(),
			presetMode     = presetMode,
			titleFont      = ui:getSelectedFont(),
		})
	end)
	-- ============================================================
	-- GiveTitle: Delete / Reset
	-- ============================================================
	ui:bindDeleteTitle(function()
		local target = ui:getSelectedPlayer()
		if not target or not resetTitleRemote then return end
		resetTitleRemote:FireServer({
			requestId      = HttpService:GenerateGUID(false),
			targetUsername = target.username,
		})
	end)
	ui:bindEditTitle(function()
		ui:loadCurrentTitleIntoEditor()
	end)
	-- ============================================================
	-- Giftcard: Package selected
	-- Bind sekali saja saat init - tidak di dalam callback (mencegah multi-bind)
	-- ============================================================
	ui:bindPackageSelected(function(tier: string)
		local selectedPlayer = ui:getSelectedPlayer()
		if not selectedPlayer then return end
		confirmedTier   = tier
		confirmedTarget = selectedPlayer
		ui:transitionToConfirmation(selectedPlayer, tier)
	end)
	-- Send gift dipanggil dari confirmation dialog (yes button)
	local function onSendGiftConfirmed()
		local tier   = confirmedTier
		local target = confirmedTarget
		if not tier or not target then return end
		ui:transitionToSending()
		adminService:sendGiftcard(target.username, tier, function(result)
			local catalogEntry = ShopDomain.getCatalogEntry(tier)
			local tierName = catalogEntry and catalogEntry.name or tier
			if result.success then
				local successMsg = Config.Admin.MSG_GIFT_SUCCESS:format(tierName, target.displayName)
				ui:transitionToSuccess(successMsg)
			else
				-- Map error code ke pesan user-friendly
				local errMsg: string
				if result.error == "already_has_tier" then
					errMsg = Config.Admin.MSG_GIFT_ALREADY_HAS:format(
						target.displayName,
						tierName
					)
				elseif result.error == "not_found" then
					errMsg = Config.Admin.MSG_GIFT_NOT_FOUND:format(target.username)
				elseif result.error == "network_error" then
					errMsg = "Network error. Coba lagi."
				else
					errMsg = Config.Admin.MSG_GIFT_FAILED
				end
				ui:transitionToConfirmationWithError(errMsg)
			end
		end)
	end
	-- Bind confirmation dialog - dilakukan sekali, callback closed-over
	ui:bindConfirmationSendGift(function()
		local tier   = confirmedTier
		local target = confirmedTarget
		if not tier or not target then return end
		local catalogEntry = ShopDomain.getCatalogEntry(tier)
		local tierName = catalogEntry and catalogEntry.name or tier
		local message = string.format(
			Config.Admin.CONFIRM_GIFT_MESSAGE,
			tierName,
			target.displayName
		)
		ui:transitionToConfirmDialog(
			message,
			onSendGiftConfirmed,
			function()
				ui:transitionBackToConfirmation()
			end
		)
	end)
	-- ============================================================
	-- Close
	-- ============================================================
	ui:bindClose(function()
		ui:hide()
		if topbarIcon then
			topbarIcon:deselect()
		end
	end)
	-- ============================================================
	-- Topbar icon
	-- ============================================================
	if topbarIcon then
		topbarIcon:setEnabled(false)
		topbarIcon.selected:Connect(function()
			refreshPlayerList(true)
			ui:generateTitleStyles(os.clock() * 1000 + localPlayer.UserId)
			updateSelectedSnapshot()
			ui:show()
		end)
		topbarIcon.deselected:Connect(function()
			ui:hide()
		end)
	end
	track(Players.PlayerAdded:Connect(function()
		refreshPlayerList(false)
	end))
	track(Players.PlayerRemoving:Connect(function()
		refreshPlayerList(false)
	end))
	if ui:isVisible() then
		refreshPlayerList(true)
	end
	log:info("AdminController initialized")
	return {
		show = function()
			refreshPlayerList(true)
			ui:generateTitleStyles(os.clock() * 1000 + localPlayer.UserId)
			updateSelectedSnapshot()
			ui:show()
		end,
		hide = function()
			ui:hide()
		end,
	}
end
return { init = init, destroy = destroy }
