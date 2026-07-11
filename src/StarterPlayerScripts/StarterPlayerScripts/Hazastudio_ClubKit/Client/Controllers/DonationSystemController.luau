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

	-- Prefer latest snapshot (no sticky max-total / min-rank). Rank must match total.
	local function sanitizeDonorProfile(profile: any?): any?
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
		return {
			userId = localPlayer.UserId,
			username = localPlayer.Name,
			displayName = if type(profile.displayName) == "string" and profile.displayName ~= ""
				then profile.displayName
				else localPlayer.DisplayName,
			robuxTotal = robuxTotal,
			robuxRank = robuxRank,
			cashTotal = cashTotal,
			cashRank = cashRank,
		}
	end

	-- Combine overhead + server into one snapshot, then sanitize.
	-- Totals: prefer higher while both positive (race during donate).
	-- Ranks: prefer better (lower) only when that side's total > 0; never keep rank with 0 total.
	local function mergeDonorProfiles(existing: any?, incoming: any?): any?
		if type(incoming) ~= "table" then
			return sanitizeDonorProfile(existing)
		end
		if type(existing) ~= "table" then
			return sanitizeDonorProfile(incoming)
		end
		local robuxTotal = math.max(existing.robuxTotal or 0, incoming.robuxTotal or 0)
		local cashTotal = math.max(existing.cashTotal or 0, incoming.cashTotal or 0)
		-- If either side reports 0, trust the clear (sync after /removerobux etc.).
		if (existing.robuxTotal or 0) <= 0 or (incoming.robuxTotal or 0) <= 0 then
			robuxTotal = math.min(existing.robuxTotal or 0, incoming.robuxTotal or 0)
		end
		if (existing.cashTotal or 0) <= 0 or (incoming.cashTotal or 0) <= 0 then
			cashTotal = math.min(existing.cashTotal or 0, incoming.cashTotal or 0)
		end
		local function pickRank(total: number, a: number?, b: number?, totalA: number, totalB: number): number?
			if total <= 0 then
				return nil
			end
			local candidates = {}
			if type(a) == "number" and totalA > 0 then
				table.insert(candidates, a)
			end
			if type(b) == "number" and totalB > 0 then
				table.insert(candidates, b)
			end
			if #candidates == 0 then
				return nil
			end
			local best = candidates[1]
			for i = 2, #candidates do
				if candidates[i] < best then
					best = candidates[i]
				end
			end
			return best
		end
		return sanitizeDonorProfile({
			displayName = if type(incoming.displayName) == "string" and incoming.displayName ~= ""
				then incoming.displayName
				else existing.displayName,
			robuxTotal = robuxTotal,
			robuxRank = pickRank(
				robuxTotal,
				tonumber(existing.robuxRank),
				tonumber(incoming.robuxRank),
				existing.robuxTotal or 0,
				incoming.robuxTotal or 0
			),
			cashTotal = cashTotal,
			cashRank = pickRank(
				cashTotal,
				tonumber(existing.cashRank),
				tonumber(incoming.cashRank),
				existing.cashTotal or 0,
				incoming.cashTotal or 0
			),
		})
	end

	local lastDonorProfile: any? = nil

	local function profileFromOverheadPayload(overheadPayload: any): any?
		if type(overheadPayload) ~= "table" then
			return nil
		end
		return sanitizeDonorProfile({
			displayName = if type(overheadPayload.displayName) == "string"
					and overheadPayload.displayName ~= ""
				then overheadPayload.displayName
				else localPlayer.DisplayName,
			robuxTotal = math.max(0, math.floor(tonumber(overheadPayload.robuxDonated) or 0)),
			robuxRank = tonumber(overheadPayload.topDonateRank),
			cashTotal = math.max(0, math.floor(tonumber(overheadPayload.cashDonated) or 0)),
			cashRank = tonumber(overheadPayload.topSpenderRank),
		})
	end

	local function profileFromOverheadOnly(): any?
		return profileFromOverheadPayload(OverheadController.getCachedPayload(localPlayer.UserId))
	end

	local function applyOverheadProfile(overheadPayload: any)
		local profile = profileFromOverheadPayload(overheadPayload)
		if not profile then
			return
		end
		-- Replace sticky session state with latest overhead snapshot (sanitized).
		lastDonorProfile = profile
		ui:applyDonorProfile(profile)
		log:debug("overhead profile applied to donation panel", {
			userId = localPlayer.UserId,
			robuxRank = profile.robuxRank,
			robuxTotal = profile.robuxTotal,
			cashRank = profile.cashRank,
			cashTotal = profile.cashTotal,
		})
	end

	local function fetchDonorProfile()
		local overheadProfile = profileFromOverheadOnly()
		local remoteProfile = if type(service.requestDonorProfile) == "function"
			then service:requestDonorProfile()
			else nil
		local merged = if overheadProfile and remoteProfile
			then mergeDonorProfiles(overheadProfile, remoteProfile)
			else sanitizeDonorProfile(remoteProfile or overheadProfile)
		if merged then
			lastDonorProfile = merged
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
