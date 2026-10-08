--!strict
-- General toasts as a notification island (owner, 2026-10-07: "aku suka yang D ... kek dynamic
-- island ... ngebesar jadi D, trs ngecil jadi A"). Card D = the Event card family: letter-spaced
-- domain in the type colour + "now", a Bold 18 headline, the detail. Pill A = type badge, domain,
-- headline. GeneralNotificationCenterService routes here while
-- Config.NotificationIsland.TOAST_ENABLED is on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local KitLook = require(script.Parent.KitLook)
local NotificationIsland = require(script.Parent.NotificationIsland)

local ToastIsland = {}

local C = KitLook.COLOR
local SOCIAL = Color3.fromHex("ff6fae")
-- With this many islands already waiting, a toast skips its card and shows as a pill only.
local BUSY_THRESHOLD = 2
local MAX_WAITING = 20

export type Toast = {
	notifType: string,
	title: string,
	description: string,
	domain: string?,
	domainLabel: string?,
	duration: number,
	iconImage: string?,
}

local baseIcon: string? = nil

-- The toast GUI's own icon (place data), so the badge matches what buyers designed.
local function defaultIcon(): string
	if baseIcon then
		return baseIcon
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local panel = playerGui and playerGui:FindFirstChild("GeneralNotificationCenter", true)
	local icon = panel and panel:FindFirstChild("NotificationIcon", true)
	if icon and icon:IsA("ImageLabel") and icon.Image ~= "" then
		baseIcon = icon.Image
	end
	return baseIcon or ""
end

local function typeColor(toast: Toast): Color3
	if toast.domain == "couple" then
		return SOCIAL
	end
	local notify = Config.Notify
	local kind = toast.notifType
	if kind == "SUCCESS" then
		return notify.COLOR_SUCCESS
	elseif kind == "WARNING" then
		return notify.COLOR_WARNING
	elseif kind == "ERROR" then
		return notify.COLOR_ERROR
	elseif kind == "SYSTEM" then
		return notify.COLOR_SYSTEM
	end
	return notify.COLOR_INFO
end

local function letterSpaced(text: string): string
	return (string.gsub(string.gsub(string.upper(text), ".", "%0 "), " $", ""))
end

-- "Music" + "Now playing" + detail, or, when the title is only the domain name, the message
-- becomes the headline and there is no detail line.
local function parts(toast: Toast): (string, string, string)
	local label = toast.domainLabel or toast.title
	if toast.title == label then
		return label, toast.description, ""
	end
	local detail = if toast.description == toast.title then "" else toast.description
	return label, toast.title, detail
end

local function badge(parent: Instance, toast: Toast, size: number): Frame
	local color = typeColor(toast)
	local frame = KitLook.box(parent, "Badge", UDim2.fromOffset(size, size), 0, color, 0.82)
	KitLook.corner(frame, UDim.new(1, 0))
	local image = if toast.iconImage and toast.iconImage ~= "" then toast.iconImage else defaultIcon()
	if image ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.Image = image
		icon.ImageColor3 = color
		icon.Size = UDim2.fromOffset(math.floor(size * 0.56), math.floor(size * 0.56))
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Parent = frame
	end
	return frame
end

local function compact(toast: Toast): NotificationIsland.Builder
	return function(content: Frame)
		local label, headline = parts(toast)
		KitLook.padding(content, 6, 0, 16, 0)
		KitLook.list(content, Enum.FillDirection.Horizontal, 10, nil, Enum.VerticalAlignment.Center)
		badge(content, toast, 32)
		local column = KitLook.box(content, "Lines", UDim2.new(0, 0, 1, 0), 1)
		local flex = Instance.new("UIFlexItem")
		flex.FlexMode = Enum.UIFlexMode.Fill
		flex.Parent = column
		KitLook.list(column, Enum.FillDirection.Vertical, 0, nil, Enum.VerticalAlignment.Center)
		KitLook.text(column, label, 12, Enum.FontWeight.SemiBold, C.sub, 0, { truncate = true })
		KitLook.text(column, headline, 14, Enum.FontWeight.Bold, C.white, 1, { truncate = true })
		return nil
	end
end

local function card(toast: Toast): NotificationIsland.Builder
	return function(content: Frame)
		local label, headline, detail = parts(toast)
		KitLook.padding(content, 14)
		KitLook.list(content, Enum.FillDirection.Vertical, 4)
		local top = KitLook.box(content, "Top", UDim2.new(1, 0, 0, 16), 0)
		KitLook.list(top, Enum.FillDirection.Horizontal, 6, nil, Enum.VerticalAlignment.Center)
		KitLook.text(top, letterSpaced(label), 12, Enum.FontWeight.Bold, typeColor(toast), 0)
		KitLook.spacer(top, 1)
		KitLook.text(top, "now", 13, Enum.FontWeight.SemiBold, C.sub, 2)
		KitLook.text(content, headline, 18, Enum.FontWeight.Bold, C.white, 1, { wrap = true })
		if detail ~= "" then
			KitLook.text(content, detail, 14, Enum.FontWeight.SemiBold, C.bodyText, 2, { wrap = true })
		end
		return nil
	end
end

function ToastIsland.show(toast: Toast)
	local waiting = NotificationIsland.pending()
	if waiting >= MAX_WAITING then
		return
	end
	local busy = waiting >= BUSY_THRESHOLD
	NotificationIsland.show({
		key = "toast",
		compact = compact(toast),
		card = if busy then nil else card(toast),
		cardHold = toast.duration,
		endHold = if busy then toast.duration else 2.2,
	})
end

return ToastIsland
