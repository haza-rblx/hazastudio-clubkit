--!strict
-- PATH: StarterPlayerScripts/Client/Services/NotifService.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local GeneralNotificationCenterService = require(script.Parent.GeneralNotificationCenterService)

local log = Logger.new("NotifService")

export type NotifType = "INFO" | "SUCCESS" | "WARNING" | "ERROR" | "SYSTEM"

export type NotifPayload = {
	message: string,
	notifType: NotifType?,
	title: string?,
	description: string?,
	domain: string?,
	dedupeKey: string?,
	duration: number?,
	iconImage: string?,
}

local NotifService = {}

function NotifService.show(payload: NotifPayload): ()
	if type(payload.message) ~= "string" or #payload.message == 0 then
		log:warn("show dipanggil dengan message kosong")
		return
	end

	GeneralNotificationCenterService.show({
		message = payload.message,
		notifType = payload.notifType,
		title = payload.title,
		description = payload.description,
		domain = payload.domain,
		dedupeKey = payload.dedupeKey,
		duration = payload.duration,
		iconImage = payload.iconImage,
	})
end

function NotifService.info(message: string): ()
	NotifService.show({ message = message, notifType = "INFO" })
end

function NotifService.success(message: string): ()
	NotifService.show({ message = message, notifType = "SUCCESS" })
end

function NotifService.warn(message: string): ()
	NotifService.show({ message = message, notifType = "WARNING" })
end

function NotifService.error(message: string): ()
	NotifService.show({ message = message, notifType = "ERROR" })
end

function NotifService.system(message: string): ()
	NotifService.show({ message = message, notifType = "SYSTEM" })
end

return NotifService
