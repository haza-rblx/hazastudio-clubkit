--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

local log = Logger.new("GeneralNotificationCenterService")

export type NotifType = "INFO" | "SUCCESS" | "WARNING" | "ERROR" | "SYSTEM"

export type Payload = {
	message: string?,
	notifType: NotifType?,
	title: string?,
	description: string?,
	domain: string?,
	dedupeKey: string?,
	duration: number?,
	iconImage: string?,
}

type ResolvedPayload = {
	notifType: NotifType,
	title: string,
	description: string,
	domain: string?,
	dedupeKey: string,
	duration: number,
	iconImage: string?,
}

type Refs = {
	rootGui: ScreenGui,
	panel: Frame,
	wrapper: Frame,
	icon: ImageLabel,
	title: TextLabel,
	description: TextLabel,
	stroke: UIStroke?,
	scale: UIScale,
	basePosition: UDim2,
	baseBackgroundTransparency: number,
	baseStrokeTransparency: number?,
	baseStrokeColor: Color3?,
	baseIconTransparency: number,
	baseIconColor: Color3,
	baseIconImage: string,
	baseTitleTransparency: number,
	baseTitleColor: Color3,
	baseDescriptionTransparency: number,
	baseDescriptionColor: Color3,
}

local ROOT_GUI_NAME = "99-NotificationCenter"
local PANEL_NAME = "GeneralNotificationCenter"
local WRAPPER_NAME = "NotificationWrapper"
local ICON_NAME = "NotificationIcon"
local TITLE_NAME = "NotificationTitle"
local DESCRIPTION_NAME = "NotificationDescription"

local PANEL_ENTRY_OFFSET = -16
local PANEL_EXIT_OFFSET = -12
local PANEL_ENTRY_DURATION = 0.22
local PANEL_EXIT_DURATION = 0.18
local PANEL_SETTLE_SCALE = 1
local PANEL_START_SCALE = 0.96
local ANIMATION_SETTLE_BUFFER = 0.06
local MAX_PENDING = 20
local DEDUPE_WINDOW_SECS = 1.2
local RESOLVE_ATTEMPTS = 40
local RESOLVE_RETRY_DELAY = 0.25

local DURATION_BY_TYPE: { [NotifType]: number } = {
	INFO = 3.1,
	SUCCESS = 3.0,
	WARNING = 3.8,
	ERROR = 4.2,
	SYSTEM = 3.0,
}

local DOMAIN_TITLE_MAP: { [string]: string } = {
	admin = "Admin",
	community = "Community",
	couple = "Couple",
	donation = "Donation",
	gift = "Gift",
	music = "Music",
	profile = "Profile",
	session = "Session",
	setrole = "Set Role",
	settings = "Settings",
	sync = "Sync",
}

local queue = {} :: { ResolvedPayload }
local dedupeTimestamps = {} :: { [string]: number }

local cachedRefs: Refs? = nil
local isProcessing = false

local function getLocalBoolAttribute(name: string): boolean
	local player = Players.LocalPlayer
	if not player then
		return false
	end
	return player:GetAttribute(name) == true
end

local function shouldSuppress(payload: ResolvedPayload): boolean
	if payload.domain == "admin" and getLocalBoolAttribute("SettingsHideAdminAnnounce") then
		return true
	end
	if payload.domain == "couple" and getLocalBoolAttribute("SettingsHideCoupleAnnounce") then
		return true
	end
	if payload.domain == "donation" and getLocalBoolAttribute("SettingsHideDonationAnnounce") then
		return true
	end
	-- System Messages: suppress semua notification yang bukan admin/couple/donation.
	-- Sebelumnya hanya check notifType=="SYSTEM" → INFO/SUCCESS/WARNING/ERROR
	-- tidak ter-suppress. Sekarang catch-all untuk system-style messages.
	if payload.domain ~= "admin" and payload.domain ~= "couple" and payload.domain ~= "donation"
		and getLocalBoolAttribute("SettingsHideSystemAnnounce") then
		return true
	end
	return false
end

local function trim(text: string): string
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function invalidateCachedRefs(refs: Refs?)
	if refs == nil or cachedRefs == refs then
		cachedRefs = nil
	end
end

local function normalizeType(notifType: string?): NotifType
	local normalized = string.upper(tostring(notifType or "INFO"))
	if normalized == "SUCCESS" then
		return "SUCCESS"
	elseif normalized == "WARNING" then
		return "WARNING"
	elseif normalized == "ERROR" then
		return "ERROR"
	elseif normalized == "SYSTEM" then
		return "SYSTEM"
	end
	return "INFO"
end

local function parseDomainFromMessage(message: string): (string?, string)
	local rawDomain, remainder = string.match(message, "^%[([^%]]+)%]%s*(.*)$")
	if not rawDomain then
		return nil, message
	end

	local domainKey = string.lower(string.gsub(trim(rawDomain), "%s+", ""))
	return domainKey, trim(remainder)
end

local function getTitleFromDomain(domain: string?, notifType: NotifType): string
	if domain and DOMAIN_TITLE_MAP[domain] then
		return DOMAIN_TITLE_MAP[domain]
	end

	if notifType == "SUCCESS" then
		return "Success"
	elseif notifType == "WARNING" then
		return "Warning"
	elseif notifType == "ERROR" then
		return "Error"
	elseif notifType == "SYSTEM" then
		return "System"
	end

	return "Notification"
end

local function getAccentColor(notifType: NotifType): Color3
	if notifType == "SUCCESS" then
		return Config.Notify.COLOR_SUCCESS
	elseif notifType == "WARNING" then
		return Config.Notify.COLOR_WARNING
	elseif notifType == "ERROR" then
		return Config.Notify.COLOR_ERROR
	elseif notifType == "SYSTEM" then
		return Config.Notify.COLOR_SYSTEM
	end

	return Config.Notify.COLOR_INFO
end

local function makeScale(panel: Frame): UIScale
	local existing = panel:FindFirstChild("RuntimeNotificationScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end

	local scale = Instance.new("UIScale")
	scale.Name = "RuntimeNotificationScale"
	scale.Scale = PANEL_SETTLE_SCALE
	scale.Parent = panel
	return scale
end

local function isRefsAlive(refs: Refs?): boolean
	return refs ~= nil
		and refs.rootGui.Parent ~= nil
		and refs.panel.Parent ~= nil
		and refs.wrapper.Parent ~= nil
		and refs.title.Parent ~= nil
		and refs.description.Parent ~= nil
		and refs.icon.Parent ~= nil
		and refs.scale.Parent ~= nil
end

local function resolveRefsOnce(): Refs?
	local player = Players.LocalPlayer
	if not player then
		return nil
	end

	local playerGui = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui", 2)
	if not playerGui or not playerGui:IsA("PlayerGui") then
		return nil
	end

	local rootGui = playerGui:FindFirstChild(ROOT_GUI_NAME)
	if not rootGui or not rootGui:IsA("ScreenGui") then
		return nil
	end

	local panel = rootGui:FindFirstChild(PANEL_NAME)
	if not panel or not panel:IsA("Frame") then
		return nil
	end

	local wrapper = panel:FindFirstChild(WRAPPER_NAME)
	local icon = wrapper and wrapper:FindFirstChild(ICON_NAME)
	local title = wrapper and wrapper:FindFirstChild(TITLE_NAME)
	local description = wrapper and wrapper:FindFirstChild(DESCRIPTION_NAME)

	if not wrapper or not wrapper:IsA("Frame") then
		return nil
	end
	if not icon or not icon:IsA("ImageLabel") then
		return nil
	end
	if not title or not title:IsA("TextLabel") then
		return nil
	end
	if not description or not description:IsA("TextLabel") then
		return nil
	end

	local stroke = panel:FindFirstChildWhichIsA("UIStroke")
	local scale = makeScale(panel)

	local refs: Refs = {
		rootGui = rootGui,
		panel = panel,
		wrapper = wrapper,
		icon = icon,
		title = title,
		description = description,
		stroke = stroke,
		scale = scale,
		basePosition = panel.Position,
		baseBackgroundTransparency = panel.BackgroundTransparency,
		baseStrokeTransparency = if stroke then stroke.Transparency else nil,
		baseStrokeColor = if stroke then stroke.Color else nil,
		baseIconTransparency = icon.ImageTransparency,
		baseIconColor = icon.ImageColor3,
		baseIconImage = icon.Image,
		baseTitleTransparency = title.TextTransparency,
		baseTitleColor = title.TextColor3,
		baseDescriptionTransparency = description.TextTransparency,
		baseDescriptionColor = description.TextColor3,
	}

	panel.Visible = false
	scale.Scale = PANEL_SETTLE_SCALE

	return refs
end

local function resolveRefs(): Refs?
	if isRefsAlive(cachedRefs) then
		return cachedRefs
	end

	invalidateCachedRefs(cachedRefs)

	for _ = 1, RESOLVE_ATTEMPTS do
		local refs = resolveRefsOnce()
		if refs then
			cachedRefs = refs
			return refs
		end
		task.wait(RESOLVE_RETRY_DELAY)
	end

	return nil
end

local function normalizePayload(payload: Payload): ResolvedPayload?
	local notifType = normalizeType(payload.notifType)
	local domain = payload.domain
	local message = trim(tostring(payload.message or ""))

	if domain then
		domain = string.lower(trim(domain))
	end

	if not domain and message ~= "" then
		local parsedDomain, remainder = parseDomainFromMessage(message)
		domain = parsedDomain
		message = remainder
	end

	local title = trim(tostring(payload.title or ""))
	local description = trim(tostring(payload.description or ""))

	if title == "" then
		title = getTitleFromDomain(domain, notifType)
	end

	if description == "" then
		description = message
	end

	if description == "" then
		description = title
	end

	if title == "" then
		return nil
	end

	local dedupeKey = payload.dedupeKey
	if not dedupeKey or dedupeKey == "" then
		dedupeKey = string.lower(table.concat({
			domain or "generic",
			notifType,
			title,
			description,
		}, "|"))
	end

	return {
		notifType = notifType,
		title = title,
		description = description,
		domain = domain,
		dedupeKey = dedupeKey,
		duration = payload.duration or DURATION_BY_TYPE[notifType],
		iconImage = payload.iconImage,
	}
end

local function cleanupDedupe(nowClock: number)
	for key, timestamp in pairs(dedupeTimestamps) do
		if (nowClock - timestamp) > DEDUPE_WINDOW_SECS then
			dedupeTimestamps[key] = nil
		end
	end
end

local function enqueue(payload: ResolvedPayload)
	local nowClock = os.clock()
	cleanupDedupe(nowClock)

	local lastTimestamp = dedupeTimestamps[payload.dedupeKey]
	if lastTimestamp and (nowClock - lastTimestamp) <= DEDUPE_WINDOW_SECS then
		return
	end

	dedupeTimestamps[payload.dedupeKey] = nowClock

	if #queue >= MAX_PENDING then
		table.remove(queue, 1)
	end

	table.insert(queue, payload)
end

local function tween(instance: Instance, tweenInfo: TweenInfo, goal: { [string]: any }): Tween
	local createdTween = TweenService:Create(instance, tweenInfo, goal)
	createdTween:Play()
	return createdTween
end

local function applyHiddenState(refs: Refs)
	refs.panel.Position = refs.basePosition
	refs.panel.BackgroundTransparency = 1
	refs.scale.Scale = PANEL_START_SCALE
	refs.icon.ImageTransparency = 1
	refs.title.TextTransparency = 1
	refs.description.TextTransparency = 1

	if refs.stroke then
		refs.stroke.Transparency = 1
		if refs.baseStrokeColor then
			refs.stroke.Color = refs.baseStrokeColor
		end
	end
end

local function cleanupDisplay(refs: Refs?)
	if not isRefsAlive(refs) then
		invalidateCachedRefs(refs)
		return
	end

	local currentRefs = refs :: Refs
	applyHiddenState(currentRefs)
	currentRefs.panel.Visible = false
	currentRefs.panel.Position = currentRefs.basePosition
	currentRefs.scale.Scale = PANEL_SETTLE_SCALE
	currentRefs.icon.Image = currentRefs.baseIconImage
	currentRefs.icon.ImageColor3 = currentRefs.baseIconColor
	currentRefs.title.TextColor3 = currentRefs.baseTitleColor
	currentRefs.description.TextColor3 = currentRefs.baseDescriptionColor

	if currentRefs.stroke then
		currentRefs.stroke.Transparency = if currentRefs.baseStrokeTransparency ~= nil
			then currentRefs.baseStrokeTransparency
			else currentRefs.stroke.Transparency
		if currentRefs.baseStrokeColor then
			currentRefs.stroke.Color = currentRefs.baseStrokeColor
		end
	end
end

local function applyContent(refs: Refs, payload: ResolvedPayload)
	refs.title.Text = payload.title
	refs.description.Text = payload.description
	refs.description.Visible = payload.description ~= ""
	refs.icon.Image = if payload.iconImage and payload.iconImage ~= "" then payload.iconImage else refs.baseIconImage

	local accent = getAccentColor(payload.notifType)
	refs.icon.ImageColor3 = accent
	refs.title.TextColor3 = refs.baseTitleColor
	refs.description.TextColor3 = refs.baseDescriptionColor

	if refs.stroke then
		refs.stroke.Color = accent
	end
end

local function playNotification(refs: Refs, payload: ResolvedPayload)
	if not isRefsAlive(refs) then
		invalidateCachedRefs(refs)
		return
	end

	applyContent(refs, payload)
	applyHiddenState(refs)

	refs.rootGui.Enabled = true
	refs.panel.Visible = true
	refs.panel.Position = UDim2.new(
		refs.basePosition.X.Scale,
		refs.basePosition.X.Offset,
		refs.basePosition.Y.Scale,
		refs.basePosition.Y.Offset + PANEL_ENTRY_OFFSET
	)

	local enterInfo = TweenInfo.new(PANEL_ENTRY_DURATION, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

	local _enterTweens = {
		tween(refs.panel, enterInfo, {
			Position = refs.basePosition,
			BackgroundTransparency = refs.baseBackgroundTransparency,
		}),
		tween(refs.scale, enterInfo, {
			Scale = PANEL_SETTLE_SCALE,
		}),
		tween(refs.icon, enterInfo, {
			ImageTransparency = refs.baseIconTransparency,
		}),
		tween(refs.title, enterInfo, {
			TextTransparency = refs.baseTitleTransparency,
		}),
		tween(refs.description, enterInfo, {
			TextTransparency = refs.baseDescriptionTransparency,
		}),
	}

	if refs.stroke and refs.baseStrokeTransparency ~= nil then
		table.insert(_enterTweens, tween(refs.stroke, enterInfo, {
			Transparency = refs.baseStrokeTransparency,
		}))
	end

	task.wait(PANEL_ENTRY_DURATION + ANIMATION_SETTLE_BUFFER)

	if not isRefsAlive(refs) then
		invalidateCachedRefs(refs)
		return
	end

	task.wait(payload.duration)

	if not isRefsAlive(refs) then
		invalidateCachedRefs(refs)
		return
	end

	local exitInfo = TweenInfo.new(PANEL_EXIT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local exitPosition = UDim2.new(
		refs.basePosition.X.Scale,
		refs.basePosition.X.Offset,
		refs.basePosition.Y.Scale,
		refs.basePosition.Y.Offset + PANEL_EXIT_OFFSET
	)

	local _exitTweens = {
		tween(refs.panel, exitInfo, {
			Position = exitPosition,
			BackgroundTransparency = 1,
		}),
		tween(refs.scale, exitInfo, {
			Scale = PANEL_START_SCALE,
		}),
		tween(refs.icon, exitInfo, {
			ImageTransparency = 1,
		}),
		tween(refs.title, exitInfo, {
			TextTransparency = 1,
		}),
		tween(refs.description, exitInfo, {
			TextTransparency = 1,
		}),
	}

	if refs.stroke then
		table.insert(_exitTweens, tween(refs.stroke, exitInfo, {
			Transparency = 1,
		}))
	end

	task.wait(PANEL_EXIT_DURATION + ANIMATION_SETTLE_BUFFER)

	cleanupDisplay(refs)
end

local function processQueue()
	if isProcessing then
		return
	end

	isProcessing = true

	task.spawn(function()
		while #queue > 0 do
			local nextPayload = table.remove(queue, 1)
			if not nextPayload then
				continue
			end

			local refs = resolveRefs()
			if not refs then
				log:warn("GeneralNotificationCenter GUI tidak ditemukan; notif dibuang")
				table.clear(queue)
				break
			end

			local ok, err = xpcall(function()
				playNotification(refs, nextPayload)
			end, debug.traceback)

			if not ok then
				log:warn("GeneralNotificationCenter presenter error", {
					error = tostring(err),
					title = nextPayload.title,
					description = nextPayload.description,
				})
			end

			pcall(cleanupDisplay, refs)
		end

		isProcessing = false
		if #queue > 0 then
			processQueue()
		end
	end)
end

local GeneralNotificationCenterService = {}

function GeneralNotificationCenterService.show(payload: Payload)
	local normalized = normalizePayload(payload)
	if not normalized then
		return
	end
	if shouldSuppress(normalized) then
		return
	end

	enqueue(normalized)
	processQueue()
end

return GeneralNotificationCenterService
