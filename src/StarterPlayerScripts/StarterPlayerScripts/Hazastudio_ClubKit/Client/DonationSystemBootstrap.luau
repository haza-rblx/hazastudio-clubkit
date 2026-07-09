--!strict
-- Top-level donation client bootstrap (Main.client owns logger + calls start once).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local DonationNotificationController = require(script.Parent.Controllers.DonationNotificationController)
local DonationSystemController = require(script.Parent.Controllers.DonationSystemController)

export type BootstrapDeps = {
	icon: any?,
	service: any,
	logger: any,
	ensureGui: (playerGui: PlayerGui, guiName: string, timeout: number) -> Instance?,
}

local started = false
local api: any = nil

local DonationSystemBootstrap = {}

function DonationSystemBootstrap.start(deps: BootstrapDeps): any?
	if started then
		deps.logger:debug("bootstrap already started")
		return api
	end
	started = true

	deps.logger:info("bootstrap start")
	DonationNotificationController.init({})

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", 30) :: PlayerGui?
	if not playerGui then
		deps.logger:warn("PlayerGui tidak ditemukan; donation panel disabled")
		return nil
	end

	local guiExists = deps.ensureGui(playerGui, Config.Donation.GUI_NAME, 10)
	if not guiExists then
		deps.logger:warn("GUI tidak ditemukan; donation panel disabled", {
			name = Config.Donation.GUI_NAME,
		})
		return nil
	end

	api = DonationSystemController.init({
		icon = deps.icon,
		service = deps.service,
		logger = deps.logger,
	})
	if api then
		deps.logger:info("bootstrap complete")
	else
		deps.logger:warn("DonationSystemController.init returned nil")
	end
	return api
end

function DonationSystemBootstrap.getApi(): any?
	return api
end

return DonationSystemBootstrap
