--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

local DonationSystemController = {}

local _connections: { RBXScriptConnection } = {}

local function track(conn: RBXScriptConnection): RBXScriptConnection
	table.insert(_connections, conn)
	return conn
end

function DonationSystemController.destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)
end

local function connectLeaderboardRefresh(remotes: Folder, onRefresh: () -> ())
	local remote = remotes:FindFirstChild(Config.Donation.REMOTE_LEADERBOARD_UPDATED)
	if not remote or not remote:IsA("RemoteEvent") then
		return
	end
	track(remote.OnClientEvent:Connect(function()
		onRefresh()
	end))
end
local DonationSystemGuiRefs = require(script.Parent.Parent.UI.DonationSystemGuiRefs)
local DonationSystemUI = require(script.Parent.Parent.UI.DonationSystemUI)
local DonationPanelBridge = require(script.Parent.Parent.DonationPanelBridge)
local OverheadController = require(script.Parent.OverheadController)

function DonationSystemController.init(deps: {
	icon: any?,
	service: any,
	logger: any?,
}): any
	local log = deps.logger or Logger.new("DonationSystem")
	log:info("init starting")
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local gui = playerGui:WaitForChild(Config.Donation.GUI_NAME, 15) :: ScreenGui?
	if not gui then
		log:warn("Donation GUI tidak ditemukan", {
			guiName = Config.Donation.GUI_NAME,
		})
		return nil
	end

	local refsOk, refsOrError = pcall(function()
		return DonationSystemGuiRefs.resolve(playerGui, Config.Donation.GUI_NAME)
	end)
	if not refsOk then
		log:warn("Donation GUI structure tidak lengkap; donation panel disabled", {
			error = tostring(refsOrError),
		})
		return nil
	end

	local uiOk, uiOrError = pcall(function()
		return DonationSystemUI.new(refsOrError)
	end)
	if not uiOk then
		log:warn("Donation UI gagal dibuat; donation panel disabled", {
			error = tostring(uiOrError),
		})
		return nil
	end

	local ui = uiOrError
	local refs = refsOrError
	local service = deps.service
	local icon = deps.icon
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 15) :: Folder?
	local donationPanelOpen = false
	local function setDonationPanelOpen(open: boolean)
		if donationPanelOpen == open then
			return
		end
		donationPanelOpen = open
		log:debug("donation panel open state changed", { open = open })
	end

	local function mergeDonorProfiles(existing: any?, incoming: any?): any?
		if type(incoming) ~= "table" then
			return existing
		end
		if type(existing) ~= "table" then
			return incoming
		end
		local function bestRank(a: number?, b: number?): number?
			if type(a) == "number" and type(b) == "number" then
				return math.min(a, b)
			end
			return a or b
		end
		return {
			userId = localPlayer.UserId,
			username = localPlayer.Name,
			displayName = if type(incoming.displayName) == "string" and incoming.displayName ~= ""
				then incoming.displayName
				else existing.displayName,
			robuxTotal = math.max(existing.robuxTotal or 0, incoming.robuxTotal or 0),
			robuxRank = bestRank(existing.robuxRank, incoming.robuxRank),
			cashTotal = math.max(existing.cashTotal or 0, incoming.cashTotal or 0),
			cashRank = bestRank(existing.cashRank, incoming.cashRank),
		}
	end

	local lastDonorProfile: any? = nil

	local function profileFromOverheadPayload(overheadPayload: any): any?
		if type(overheadPayload) ~= "table" then
			return nil
		end
		return {
			userId = localPlayer.UserId,
			username = localPlayer.Name,
			displayName = if type(overheadPayload.displayName) == "string"
					and overheadPayload.displayName ~= ""
				then overheadPayload.displayName
				else localPlayer.DisplayName,
			robuxTotal = math.max(0, math.floor(tonumber(overheadPayload.robuxDonated) or 0)),
			robuxRank = tonumber(overheadPayload.topDonateRank),
			cashTotal = math.max(0, math.floor(tonumber(overheadPayload.cashDonated) or 0)),
			cashRank = tonumber(overheadPayload.topSpenderRank),
		}
	end

	local function profileFromOverheadOnly(): any?
		return profileFromOverheadPayload(OverheadController.getCachedPayload(localPlayer.UserId))
	end

	local function applyOverheadProfile(overheadPayload: any)
		local profile = profileFromOverheadPayload(overheadPayload)
		if not profile then
			return
		end
		local merged = mergeDonorProfiles(lastDonorProfile, profile)
		lastDonorProfile = merged
		ui:applyDonorProfile(merged)
		log:debug("overhead profile applied to donation panel", {
			userId = localPlayer.UserId,
			robuxRank = merged.robuxRank,
			robuxTotal = merged.robuxTotal,
			cashRank = merged.cashRank,
			cashTotal = merged.cashTotal,
		})
	end

	local function fetchDonorProfile()
		local overheadProfile = profileFromOverheadOnly()
		local remoteProfile = if type(service.requestDonorProfile) == "function"
			then service:requestDonorProfile()
			else nil
		local merged = if overheadProfile and remoteProfile
			then mergeDonorProfiles(overheadProfile, remoteProfile)
			else (remoteProfile or overheadProfile)
		if merged then
			lastDonorProfile = mergeDonorProfiles(lastDonorProfile, merged)
			return lastDonorProfile
		end
		return nil
	end

	local function refreshProducts()
		if type(service.refreshProducts) == "function" then
			return service:refreshProducts()
		end
		return service:getProducts()
	end

	ui:bindProfileRefresh(fetchDonorProfile)
	ui:bindProductRefresh(refreshProducts)
	DonationPanelBridge.subscribe(applyOverheadProfile)
	local cachedOverhead = OverheadController.getCachedPayload(localPlayer.UserId)
	if cachedOverhead then
		applyOverheadProfile(cachedOverhead)
	end
	if remotes then
		local leaderboardRefreshDebounceToken = 0
		connectLeaderboardRefresh(remotes, function()
			leaderboardRefreshDebounceToken += 1
			local token = leaderboardRefreshDebounceToken
			task.delay(2, function()
				if token ~= leaderboardRefreshDebounceToken then
					return
				end
				if type(service.invalidateDonorProfileCache) == "function" then
					log:debug("leaderboard push: invalidating donor profile cache", {
						userId = localPlayer.UserId,
					})
					service:invalidateDonorProfileCache()
				end
				if donationPanelOpen then
					log:debug("leaderboard push: refreshing donor profile", {
						userId = localPlayer.UserId,
					})
					ui:refreshDonorProfile()
				end
			end)
		end)
	end
	ui:bindDonateRequested(function(product, message)
		service:promptDonate(product, message)
	end)
	ui:bindClose(function()
		if icon then
			icon:deselect()
		end
	end)
	service:onResult(function(payload: any)
		if payload.ok then
			if type(service.invalidateDonorProfileCache) == "function" then
				service:invalidateDonorProfileCache()
			end
			local priceText = if type(payload.price) == "number" then tostring(payload.price) .. " Robux" else "Robux"
			ui:refreshDonorProfile()
			ui:setDonationResult(true, "Thank you for donating " .. priceText .. ".")
			ui:closeAll()
			setDonationPanelOpen(false)
			if icon then
				icon:deselect()
			end
		else
			ui:setDonationResult(false, payload.error or "Donation product is not ready yet.")
		end
	end)

	if icon then
		icon.selected:Connect(function()
			local overheadPayload = OverheadController.getCachedPayload(localPlayer.UserId)
			if overheadPayload then
				applyOverheadProfile(overheadPayload)
			end
			setDonationPanelOpen(true)
			ui:show()
		end)
		icon.deselected:Connect(function()
			setDonationPanelOpen(false)
			ui:hide()
		end)
	end

	return {
		show = function()
			setDonationPanelOpen(true)
			ui:show()
		end,
		hide = function()
			setDonationPanelOpen(false)
			ui:hide()
		end,
	}
end

return DonationSystemController
