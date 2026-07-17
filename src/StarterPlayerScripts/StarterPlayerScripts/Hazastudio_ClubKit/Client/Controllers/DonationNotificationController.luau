--!strict
-- Client/Controllers/DonationNotificationController.lua
-- Terima DonationNotification dari server, tampilkan GUI Studio donation.
-- Single active notification + queue + dedup guard.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextService = game:GetService("TextService")
local TextChatService = game:GetService("TextChatService")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local DonationProviderDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.DonationProviderDomain)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local DonationEffectTierResolver = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DonationEffectTierResolver)
local DonationExperiencePrefs = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DonationExperiencePrefs)
local HttpApiCounter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApiCounter)
local ClientThumbnailCache = require(script.Parent.Parent.Utils.ClientThumbnailCache)
local WorldEffectDispatch = require(script.Parent.Parent.Utils.WorldEffectDispatch)
local DonationVfxClientGate = require(script.Parent.Parent.Utils.DonationVfxClientGate)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local OverheadController = require(script.Parent.OverheadController)
local GenericBroadcastLayoutBridge = require(script.Parent.Parent.Services.GenericBroadcastLayoutBridge)
type DonationNotifPayload = Types.DonationNotifPayload
type TemplateRefs = {
	panel: CanvasGroup,
	panelScale: UIScale,
	senderProfpic: ImageLabel?,
	senderProfpicDefaultImage: string?,
	roleBadge: ImageLabel?,
	senderUsername: TextLabel?,
	senderDisplayName: TextLabel?,
	totalDonationsWrapper: GuiObject?,
	senderTotalDonations: TextLabel?,
	donationValue: TextLabel?,
	donationMessage: TextLabel?,
	countDownBar: Frame?,
}

type GuiRefs = {
	rootGui: ScreenGui,
	backgroundWrapper: GuiObject?,
	rotatingBackground: ImageLabel?,
	donationWrapper: Frame,
	-- active template (set saat showNotif berdasarkan payload.source)
	panel: CanvasGroup,
	panelScale: UIScale,
	senderProfpic: ImageLabel?,
	senderProfpicDefaultImage: string?,
	roleBadge: ImageLabel?,
	senderUsername: TextLabel?,
	senderDisplayName: TextLabel?,
	totalDonationsWrapper: GuiObject?,
	senderTotalDonations: TextLabel?,
	donationValue: TextLabel?,
	donationMessage: TextLabel?,
	countDownBar: Frame?,
	-- kedua template tersimpan untuk di-swap
	saweriaRefs: TemplateRefs,
	robuxRefs: TemplateRefs,
}

type WorkspaceSurfaceRefs = {
	liveChatGui: SurfaceGui?,
	liveDonatorInfoRoot: Frame?,
	liveDonatorInfoCard: Frame?,
	liveDonatorInfoTotal: Frame?,
	liveAvatar: ImageLabel?,
	liveCommunity: ImageLabel?,
	liveUsername: TextLabel?,
	liveDisplayName: TextLabel?,
	liveTotalDonations: TextLabel?,
	liveDonationMessage: TextLabel?,
	liveThanksMessage: TextLabel?,
	liveLastUpdate: TextLabel?,
	runningTextGui: SurfaceGui?,
	runningWrapper: Frame?,
	runningContent: Frame?,
	runningText: TextLabel?,
	runningLogo: ImageLabel?,
}

type WorkspaceSurfaceTemplate = {
	liveAvatarImage: string?,
	liveCommunityImage: string?,
	liveUsernameText: string?,
	liveDisplayNameText: string?,
	liveTotalDonationsText: string?,
	liveDonationMessageText: string?,
	liveThanksMessageText: string?,
	liveLastUpdateText: string?,
	runningText: string?,
	runningLogoImage: string?,
}
type WorkspaceSurfaceState = {
	refs: WorkspaceSurfaceRefs,
	template: WorkspaceSurfaceTemplate,
}

-- ANIMATION CONSTANTS
-- Entrance
local ENTER_SLIDE_OFFSET = -80 -- px di atas resting saat awal masuk (lebih dramatic)
local ENTER_OVERSHOOT_BELOW = 10 -- px lewat batas bawah resting (spring feel)
local ENTER_SCALE_FROM = 0.82 -- skala awal (lebih kecil -> pop lebih kentara)
local ENTER_SCALE_PEAK = 1.055 -- peak scale saat overshoot (lebih terasa)
local ENTER_PHASE1_DUR = 0.42 -- durasi slide masuk + peak scale (lebih smooth)
local ENTER_PHASE2_DUR = 0.16 -- durasi settle ke resting (lebih mulus)
-- Background
local BG_SPIN_PERIOD = 7 -- detik per 360 deg
local BG_FADE_IN_DUR = 0.3 -- bg muncul perlahan setelah panel settled
local BG_FADE_OUT_DUR = 0.18 -- bg hilang saat exit
-- Stagger reveals (elemen konten muncul bergiliran setelah panel settled)
local STAGGER_DELAY_SENDER = 0.05 -- offset setelah panel selesai animasi
local STAGGER_DELAY_VALUE = 0.13
local STAGGER_DELAY_MESSAGE = 0.22
local STAGGER_SLIDE_DIST = 14 -- px - slide dari samping
local STAGGER_FADE_DUR = 0.32 -- durasi fade+slide tiap elemen (lebih smooth)
-- Exit
local EXIT_ANTICIPATION_DUR = 0.12 -- detik "napas" sebelum kabur (lebih terasa)
local EXIT_ANTICIPATION_SCALE = 0.970 -- compress lebih dalam
local EXIT_LAUNCH_DUR = 0.30 -- durasi terbang ke atas (lebih dramatic)
local EXIT_SLIDE_ABOVE = -65 -- px ke atas dari resting saat exit (lebih jauh)
local LIVECHAT_POP_FROM = 0.82
local LIVECHAT_POP_PEAK = 1.04
local LIVECHAT_POP_IN_DUR = 0.20
local LIVECHAT_POP_SETTLE_DUR = 0.14
local LIVECHAT_POP_OUT_SCALE = 0.96
local LIVECHAT_POP_OUT_DUR = 0.16
-- Dedup guard: window (detik) untuk filter notif duplikat dari burst polling
local DEDUP_WINDOW_SECS = 2.5
-- HELPERS
local log = Logger.new("Client.DonationNotificationController")

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

local EMPTY_MESSAGE_TEXT = "Tanpa pesan"
local DEFAULT_SENDER_USERNAME = "@donatur"
local DEFAULT_TOTAL_DONATION = "Total : Donasi pertama"
local function getExternalProviderName(): string
	return DonationProviderDomain.getName()
end

local function applyExternalProviderText(root: Instance)
	DonationProviderDomain.applyDisplayText(root)
end

local function formatGrouped(amount: number): string
	local s = tostring(math.floor(math.max(amount, 0)))
	local result = ""
	local len = #s
	for i = 1, len do
		if i > 1 and (len - i + 1) % 3 == 0 then
			result = result .. "."
		end
		result = result .. s:sub(i, i)
	end
	return result
end
local function formatRupiah(amount: number): string
	return "Rp " .. formatGrouped(amount)
end

local function formatDonationAmount(payload: DonationNotifPayload): string
	if payload.source == "robux" then
		return formatGrouped(payload.amount) .. " Robux"
	end
	return formatRupiah(payload.amount)
end

local function formatTotalDonation(amount: number?, source: string?): string
	if type(amount) ~= "number" or amount <= 0 then
		return DEFAULT_TOTAL_DONATION
	end
	if source == "robux" then
		return "Total : " .. formatGrouped(amount) .. " Robux"
	end
	return "Total : " .. formatRupiah(amount)
end
local function normalizeMessage(message: string?): string?
	if type(message) ~= "string" then
		return nil
	end
	local trimmed = message:match("^%s*(.-)%s*$")
	return (trimmed and trimmed ~= "") and trimmed or nil
end

local function asRunningText(text: string?): string
	return string.upper(tostring(text or ""))
end

local function workspaceTimestampText(): string
	return "Latest update on " .. os.date("%d %b %Y, %H:%M", os.time()) .. "."
end

local function findImageLabel(root: Instance?, name: string): ImageLabel?
	if not root then
		return nil
	end
	local found = root:FindFirstChild(name, true)
	if found and found:IsA("ImageLabel") then
		return found
	end
	return nil
end

local function findTextLabel(root: Instance?, name: string): TextLabel?
	if not root then
		return nil
	end
	local found = root:FindFirstChild(name, true)
	if found and found:IsA("TextLabel") then
		return found
	end
	return nil
end

local function findSurfaceGuiByNames(root: Instance?, names: { string }): SurfaceGui?
	if not root then
		return nil
	end
	for _, name in ipairs(names) do
		local found = root:FindFirstChild(name, true)
		if found and found:IsA("SurfaceGui") then
			return found
		end
	end
	if root:IsA("SurfaceGui") then
		return root
	end
	local found = root:FindFirstChildWhichIsA("SurfaceGui", true)
	return found
end

local function collectWorkspaceRoots(rootName: string): { Instance }
	local roots = {}
	-- Primary: CollectionService tag applied by TagDonationDisplayRoots.server.luau.
	local taggedSet: { [Instance]: boolean } = {}
	for _, root in ipairs(CollectionService:GetTagged(Config.Donation.DISPLAY_ROOT_TAG)) do
		if root.Name == rootName and root.Parent ~= nil then
			table.insert(roots, root)
			taggedSet[root] = true
		end
	end
	-- Fallback: full workspace scan by name so instances that were not tagged
	-- (e.g., server tagger ran before the part was present) are still discovered.
	-- This function is only called on init and donation events, not per-frame,
	-- so the scan cost is acceptable.
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant.Name == rootName and not taggedSet[descendant] then
			table.insert(roots, descendant)
		end
	end
	return roots
end

local function buildWorkspaceSurfaceRefs(liveRoot: Instance?, runningRoot: Instance?): WorkspaceSurfaceRefs
	local liveChatGui = findSurfaceGuiByNames(liveRoot, { "LiveChatGUI", "SurfaceGui" })
	local liveDonatorInfoRoot = if liveChatGui
		then liveChatGui:FindFirstChild("DonatorInformationsWrapper", true)
		else nil
	local runningTextGui = findSurfaceGuiByNames(runningRoot, { "RunningTextGUI", "SurfaceGui" })
	local runningWrapper = if runningTextGui then runningTextGui:FindFirstChild("Wrapper", true) else nil
	local runningContent = if runningTextGui then runningTextGui:FindFirstChild("ContentWrapper", true) else nil

	return {
		liveChatGui = if liveChatGui and liveChatGui:IsA("SurfaceGui") then liveChatGui else nil,
		liveDonatorInfoRoot = if liveDonatorInfoRoot and liveDonatorInfoRoot:IsA("Frame")
			then liveDonatorInfoRoot
			else nil,
		liveDonatorInfoCard = if liveDonatorInfoRoot
			then liveDonatorInfoRoot:FindFirstChild("Wrapper") :: Frame?
			else nil,
		liveDonatorInfoTotal = if liveDonatorInfoRoot
			then liveDonatorInfoRoot:FindFirstChild("TotalDonationsWrapper") :: Frame?
			else nil,
		liveAvatar = findImageLabel(liveChatGui, "PlayerImageThumbnail"),
		liveCommunity = findImageLabel(liveChatGui, "PlayerCommunity"),
		liveUsername = findTextLabel(liveChatGui, "PlayerUsername"),
		liveDisplayName = findTextLabel(liveChatGui, "PlayerDisplayName"),
		liveTotalDonations = findTextLabel(liveChatGui, "TotalDonations"),
		liveDonationMessage = findTextLabel(liveChatGui, "DonationMessage"),
		liveThanksMessage = findTextLabel(liveChatGui, "ThanksMessage"),
		liveLastUpdate = findTextLabel(liveChatGui, "LastUpdateTextLabel"),
		runningTextGui = if runningTextGui and runningTextGui:IsA("SurfaceGui") then runningTextGui else nil,
		runningWrapper = if runningWrapper and runningWrapper:IsA("Frame") then runningWrapper else nil,
		runningContent = if runningContent and runningContent:IsA("Frame") then runningContent else nil,
		runningText = findTextLabel(runningTextGui, "CustomizeableText"),
		runningLogo = findImageLabel(runningTextGui, "LogoImage"),
	}
end

local function resolveWorkspaceSurfaceRefsList(): { WorkspaceSurfaceRefs }
	local refsList = {}
	for _, liveRoot in ipairs(collectWorkspaceRoots(Config.Donation.LIVE_CHAT_ROOT_NAME)) do
		local refs = buildWorkspaceSurfaceRefs(liveRoot, nil)
		if refs.liveChatGui then
			table.insert(refsList, refs)
		end
	end
	for _, runningRoot in ipairs(collectWorkspaceRoots(Config.Donation.RUNNING_TEXT_ROOT_NAME)) do
		local refs = buildWorkspaceSurfaceRefs(nil, runningRoot)
		if refs.runningTextGui then
			table.insert(refsList, refs)
		end
	end
	return refsList
end

local function getOrCreateLiveChatScale(frame: Frame): UIScale
	local existing = frame:FindFirstChild("RuntimePopScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end

	local scale = Instance.new("UIScale")
	scale.Name = "RuntimePopScale"
	scale.Scale = 1
	scale.Parent = frame
	return scale
end

local function resetLiveChatInfoVisibility(refs: WorkspaceSurfaceRefs)
	if refs.liveDonatorInfoCard then
		refs.liveDonatorInfoCard.Visible = false
		getOrCreateLiveChatScale(refs.liveDonatorInfoCard).Scale = 1
	end
	if refs.liveDonatorInfoTotal then
		refs.liveDonatorInfoTotal.Visible = false
		getOrCreateLiveChatScale(refs.liveDonatorInfoTotal).Scale = 1
	end
end

local function popLiveChatInfo(refs: WorkspaceSurfaceRefs)
	if refs.liveDonatorInfoRoot then
		local rootScale = getOrCreateLiveChatScale(refs.liveDonatorInfoRoot)
		refs.liveDonatorInfoRoot.Visible = true
		rootScale.Scale = 0.98
		TweenService:Create(
			rootScale,
			TweenInfo.new(LIVECHAT_POP_IN_DUR, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end

	local function popFrame(frame: Frame?, delaySec: number)
		if not frame then
			return
		end

		local scale = getOrCreateLiveChatScale(frame)
		frame.Visible = true
		scale.Scale = LIVECHAT_POP_FROM

		task.delay(delaySec, function()
			if not frame.Parent then
				return
			end
			local grow = TweenService:Create(
				scale,
				TweenInfo.new(LIVECHAT_POP_IN_DUR, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = LIVECHAT_POP_PEAK }
			)
			grow:Play()
			grow.Completed:Connect(function()
				if scale.Parent then
					TweenService:Create(
						scale,
						TweenInfo.new(LIVECHAT_POP_SETTLE_DUR, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Scale = 1 }
					):Play()
				end
			end)
		end)
	end

	popFrame(refs.liveDonatorInfoCard, 0)
	popFrame(refs.liveDonatorInfoTotal, 0.05)
end

local function popOutLiveChatInfo(refs: WorkspaceSurfaceRefs, onDone: (() -> ())?)
	local longestTween: Tween? = nil

	for _, frame in ipairs({ refs.liveDonatorInfoTotal, refs.liveDonatorInfoCard }) do
		if frame and frame.Parent and frame.Visible then
			local scale = getOrCreateLiveChatScale(frame)
			local tweenOut = TweenService:Create(
				scale,
				TweenInfo.new(LIVECHAT_POP_OUT_DUR, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Scale = LIVECHAT_POP_OUT_SCALE }
			)
			longestTween = tweenOut
			tweenOut.Completed:Once(function()
				if frame.Parent then
					frame.Visible = false
					scale.Scale = 1
				end
			end)
			tweenOut:Play()
		end
	end

	if refs.liveDonatorInfoRoot and refs.liveDonatorInfoRoot.Parent then
		local rootScale = getOrCreateLiveChatScale(refs.liveDonatorInfoRoot)
		local rootTween = TweenService:Create(
			rootScale,
			TweenInfo.new(LIVECHAT_POP_OUT_DUR, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Scale = LIVECHAT_POP_OUT_SCALE }
		)
		longestTween = rootTween
		rootTween.Completed:Once(function()
			if rootScale.Parent then
				rootScale.Scale = 1
			end
		end)
		rootTween:Play()
	end

	if longestTween then
		longestTween.Completed:Once(function()
			if onDone then
				onDone()
			end
		end)
	elseif onDone then
		onDone()
	end
end

local function refreshWorkspaceTimestamp(refs: WorkspaceSurfaceRefs)
	if refs.liveLastUpdate then
		refs.liveLastUpdate.Text = workspaceTimestampText()
	end
end

local function resolveDisplayIdentity(payload: DonationNotifPayload): (string, string, string?)
	local source = tostring(payload.source or "")
	local isRobux = source == "robux"
	local saweriaName = payload.saweriaName or ""

	-- 3A fix: Resolve Roblox identity untuk BOTH Robux dan Bagibagi donations.
	-- Sebelumnya non-Robux early-return `payload.saweriaName, ""` yang discard
	-- robloxUsername/robloxDisplayName → username always "" → fallback "@donatur"
	-- → thumbnail benar (pakai robloxUserId langsung) tapi name salah.
	local username = if type(payload.robloxUsername) == "string" and payload.robloxUsername ~= ""
		then payload.robloxUsername else ""
	local displayName = if type((payload :: any).robloxDisplayName) == "string"
			and (payload :: any).robloxDisplayName ~= ""
		then (payload :: any).robloxDisplayName else ""

	-- Check live player for real-time DisplayName
	if type(payload.robloxUserId) == "number" then
		local livePlayer = Players:GetPlayerByUserId(payload.robloxUserId)
		if livePlayer then
			displayName = livePlayer.DisplayName
			if username == "" then
				username = livePlayer.Name
			end
		end
	end

	-- Fix: untuk Bagibagi (non-Robux), kalau robloxDisplayName sama persis dengan
	-- robloxUsername (user belum set custom DisplayName), prefer pakai saweriaName
	-- sebagai displayName supaya notif tidak terlihat redundant "Username @username".
	if not isRobux and displayName ~= "" and username ~= "" and displayName:lower() == username:lower() then
		displayName = ""
	end

	-- Fallbacks: if no Roblox identity, use saweriaName
	if displayName == "" then
		displayName = if saweriaName ~= "" then saweriaName else "Donor"
	end

	-- For non-Robux (Bagibagi/Saweria): return saweriaName as subtitle (third
	-- return value) supaya UI bisa show both — Roblox display name primary,
	-- external Saweria name secondary. Hanya return subtitle kalau saweriaName
	-- berbeda dari displayName (avoid redundant display).
	local subtitle: string? = nil
	if not isRobux and saweriaName ~= "" and saweriaName ~= displayName then
		subtitle = saweriaName
	end

	return displayName, username, subtitle
end

local function buildRunningText(
	payload: DonationNotifPayload,
	displayName: string,
	username: string,
	subtitle: string?
): string
	local parts = {
		string.upper(displayName) .. " DONATED " .. string.upper(formatDonationAmount(payload)),
	}

	-- 3B fix: include saweriaName subtitle untuk Bagibagi donations
	if subtitle and subtitle ~= "" then
		table.insert(parts, "via " .. subtitle)
	end

	local normalizedMessage = normalizeMessage(payload.message)
	if username ~= "" then
		table.insert(parts, "@" .. username:gsub("^@", ""))
	end
	if normalizedMessage then
		table.insert(parts, '"' .. normalizedMessage .. '"')
	end

	return asRunningText(table.concat(parts, "   •   "))
end

local function _easeInOutSine(t: number): number
	return -(math.cos(math.pi * math.clamp(t, 0, 1)) - 1) * 0.5
end

-- Camera and cinematic bars are server-authoritative via CinematicDockController.
-- Only Level 7+ donations trigger the camera (per the tier ladder in Config.Donation).

-- Resolves the per-tier notification duration from the payload.
-- Bagi-Bagi (IDR) uses idrMin/idrMax ranges, Robux uses the min threshold.
-- Falls back to NOTIF_SHOW_DURATION when no tier matches.
local function resolveNotifDuration(payload: DonationNotifPayload): number
	local amount = tonumber(payload.amount) or 0
	local source = tostring(payload.source or DonationProviderDomain.getKey())
	return DonationEffectTierResolver.resolveNotifDuration(source, amount)
end

local function setCoreTopbarVisible(isVisible: boolean)
	pcall(function()
		StarterGui:SetCore("TopbarEnabled", isVisible)
	end)
end

local function setDonationHudHidden(playerGui: PlayerGui, hidden: boolean)
	local hiddenAttribute = "DonationRuntimeHidden"
	for _, guiName in ipairs(Config.Hotbar.GUI_NAMES or {}) do
		local gui = playerGui:FindFirstChild(guiName)
		if gui and gui:IsA("ScreenGui") then
			local key = hiddenAttribute .. "_Enabled"
			if hidden then
				if gui:GetAttribute(key) == nil then
					gui:SetAttribute(key, gui.Enabled)
				end
				gui.Enabled = false
			else
				local previous = gui:GetAttribute(key)
				if type(previous) == "boolean" then
					gui.Enabled = previous
				else
					gui.Enabled = true
				end
				gui:SetAttribute(key, nil)
			end
		end
	end
	setCoreTopbarVisible(not hidden)
end

local function setVisible(obj: GuiObject?, v: boolean)
	if obj then
		obj.Visible = v
	end
end
-- Buat tween, play, dan return - shorthand
local function tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local t = TweenService:Create(instance, info, goal)
	t:Play()
	return t
end
local function tweenWait(instance: Instance, info: TweenInfo, goal: { [string]: any })
	tween(instance, info, goal).Completed:Wait()
end

-- GUI RESOLVER
local function getOrCreatePanelScale(panel: CanvasGroup): UIScale
	local ex = panel:FindFirstChild("RuntimeUIScale")
	if ex and ex:IsA("UIScale") then
		return ex
	end
	local s = Instance.new("UIScale")
	s.Name = "RuntimeUIScale"
	s.Scale = 1
	s.Parent = panel
	return s
end
local function resolveTemplateRefs(panel: CanvasGroup, isSaweria: boolean): TemplateRefs
	local mainContent = panel:FindFirstChild("MainContent")

	-- Profile pic + RoleBadge
	local profPicContainer: Instance? = nil
	if isSaweria then
		-- SaweriaDonationTemplate: MainContent > DonatorInfo > SenderProfPicWrapper
		local donatorInfo = mainContent and mainContent:FindFirstChild("DonatorInfo")
		profPicContainer = donatorInfo and donatorInfo:FindFirstChild("SenderProfPicWrapper")
	else
		-- RobuxDonationTemplate: MainContent > DonationInformation > SenderProfPicWrapper
		local donationInfo = mainContent and mainContent:FindFirstChild("DonationInformation")
		profPicContainer = donationInfo and donationInfo:FindFirstChild("SenderProfPicWrapper")
	end
	local senderProfpic = profPicContainer and profPicContainer:FindFirstChild("SenderProfpic")
	local roleBadge = profPicContainer and profPicContainer:FindFirstChild("RoleBadge")

	-- DonationValue
	local donationValue: TextLabel? = nil
	if isSaweria then
		-- MainContent > DonationInfo > MainInfoWrapper > DonationValue
		local donationInfoFrame = mainContent and mainContent:FindFirstChild("DonationInfo")
		local mainInfoWrapper = donationInfoFrame and donationInfoFrame:FindFirstChild("MainInfoWrapper")
		donationValue = mainInfoWrapper and mainInfoWrapper:FindFirstChild("DonationValue") :: TextLabel?
	else
		-- MainContent > DonationInfoWrapper > DonarionInfo > DonationValue
		local donationInfoWrapper = mainContent and mainContent:FindFirstChild("DonationInfoWrapper")
		local donarionInfo = donationInfoWrapper and donationInfoWrapper:FindFirstChild("DonarionInfo")
		donationValue = donarionInfo and donarionInfo:FindFirstChild("DonationValue") :: TextLabel?
	end

	-- SenderInformations container name differs per template
	local msgWrapper = mainContent and mainContent:FindFirstChild("DonationMessageWrapper")
	local senderInfoWrapper = msgWrapper and msgWrapper:FindFirstChild("SenderInformationWrapper")
	local senderContainer: Instance? = nil
	if isSaweria then
		-- SenderInformationWrapper > SenderInformations
		senderContainer = senderInfoWrapper and senderInfoWrapper:FindFirstChild("SenderInformations")
	else
		-- SenderInformationWrapper > DonatorInfo
		senderContainer = senderInfoWrapper and senderInfoWrapper:FindFirstChild("DonatorInfo")
	end
	local totalDonationsWrapper = senderInfoWrapper and senderInfoWrapper:FindFirstChild("TotalDonationsWrapper")

	-- DonatorMessage frame
	local donatorMsgFrame: Instance? = nil
	if isSaweria then
		-- DonationMessageWrapper > DonatorMessage (Frame) > DonatorMessage (TextLabel)
		donatorMsgFrame = msgWrapper and msgWrapper:FindFirstChild("DonatorMessage")
	else
		-- DonationMessageWrapper > DonatorMessageWrapper (Frame) > DonatorMessage (TextLabel)
		donatorMsgFrame = msgWrapper and msgWrapper:FindFirstChild("DonatorMessageWrapper")
	end

	local countDownBar = mainContent and mainContent:FindFirstChild("CountDownBar") :: Frame?

	return {
		panel = panel,
		panelScale = getOrCreatePanelScale(panel),
		senderProfpic = if senderProfpic and senderProfpic:IsA("ImageLabel") then senderProfpic :: ImageLabel else nil,
		senderProfpicDefaultImage = if senderProfpic and senderProfpic:IsA("ImageLabel")
			then (senderProfpic :: ImageLabel).Image
			else nil,
		roleBadge = if roleBadge and roleBadge:IsA("ImageLabel") then roleBadge :: ImageLabel else nil,
		senderDisplayName = if senderContainer
			then senderContainer:FindFirstChild("SenderDisplayName") :: TextLabel?
			else nil,
		senderUsername = if senderContainer
			then senderContainer:FindFirstChild("SenderUsername") :: TextLabel?
			else nil,
		totalDonationsWrapper = totalDonationsWrapper :: GuiObject?,
		senderTotalDonations = if totalDonationsWrapper
			then totalDonationsWrapper:FindFirstChild("SenderTotalDonations") :: TextLabel?
			else nil,
		donationValue = donationValue,
		donationMessage = if donatorMsgFrame
			then donatorMsgFrame:FindFirstChild("DonatorMessage") :: TextLabel?
			else nil,
		countDownBar = if countDownBar and countDownBar:IsA("Frame") then countDownBar :: Frame else nil,
	}
end

local function resolveGuiRefs(playerGui: PlayerGui): GuiRefs?
	local rootGui: Instance? = playerGui:FindFirstChild("99-NotificationCenter")
	if not rootGui then
		rootGui = playerGui:WaitForChild("99-NotificationCenter", 10)
	end
	if not rootGui or not rootGui:IsA("ScreenGui") then
		log:warn("99-NotificationCenter tidak ditemukan di PlayerGui")
		return nil
	end

	local donationWrapper = rootGui:FindFirstChild("DonationWrapper")
	if not donationWrapper or not donationWrapper:IsA("Frame") then
		log:warn("DonationWrapper tidak ditemukan di 99-NotificationCenter")
		return nil
	end

	local saweriaPanel = donationWrapper:FindFirstChild("SaweriaDonationTemplate")
	if not saweriaPanel or not saweriaPanel:IsA("CanvasGroup") then
		log:warn("SaweriaDonationTemplate tidak ditemukan di DonationWrapper")
		return nil
	end
	local robuxPanel = donationWrapper:FindFirstChild("RobuxDonationTemplate")
	if not robuxPanel or not robuxPanel:IsA("CanvasGroup") then
		log:warn("RobuxDonationTemplate tidak ditemukan di DonationWrapper")
		return nil
	end

	local saweriaRefs = resolveTemplateRefs(saweriaPanel :: CanvasGroup, true)
	local robuxRefs = resolveTemplateRefs(robuxPanel :: CanvasGroup, false)
	applyExternalProviderText(saweriaPanel)

	local bgWrapper = rootGui:FindFirstChild("RotatingBackgroundWrappe") :: GuiObject?
	local rotBg: ImageLabel? = bgWrapper and bgWrapper:FindFirstChild("RotatingBackground") :: ImageLabel?

	-- Default active template = Saweria
	return {
		rootGui = rootGui :: ScreenGui,
		backgroundWrapper = bgWrapper,
		rotatingBackground = rotBg,
		donationWrapper = donationWrapper :: Frame,
		panel = saweriaRefs.panel,
		panelScale = saweriaRefs.panelScale,
		senderProfpic = saweriaRefs.senderProfpic,
		senderProfpicDefaultImage = saweriaRefs.senderProfpicDefaultImage,
		roleBadge = saweriaRefs.roleBadge,
		senderUsername = saweriaRefs.senderUsername,
		senderDisplayName = saweriaRefs.senderDisplayName,
		totalDonationsWrapper = saweriaRefs.totalDonationsWrapper,
		senderTotalDonations = saweriaRefs.senderTotalDonations,
		donationValue = saweriaRefs.donationValue,
		donationMessage = saweriaRefs.donationMessage,
		countDownBar = saweriaRefs.countDownBar,
		saweriaRefs = saweriaRefs,
		robuxRefs = robuxRefs,
	}
end

-- Swap active template refs in GuiRefs based on payload source
local function switchTemplate(refs: GuiRefs, source: string?)
	local isRobux = source == "robux"
	local active: TemplateRefs = if isRobux then refs.robuxRefs else refs.saweriaRefs
	local inactive: TemplateRefs = if isRobux then refs.saweriaRefs else refs.robuxRefs
	-- Hide inactive panel immediately
	inactive.panel.Visible = false
	-- Copy active refs into GuiRefs working fields
	refs.panel = active.panel
	refs.panelScale = active.panelScale
	refs.senderProfpic = active.senderProfpic
	refs.senderProfpicDefaultImage = active.senderProfpicDefaultImage
	refs.roleBadge = active.roleBadge
	refs.senderUsername = active.senderUsername
	refs.senderDisplayName = active.senderDisplayName
	refs.totalDonationsWrapper = active.totalDonationsWrapper
	refs.senderTotalDonations = active.senderTotalDonations
	refs.donationValue = active.donationValue
	refs.donationMessage = active.donationMessage
	refs.countDownBar = active.countDownBar
end
-- STATE RESET
local function resetGuiState(refs: GuiRefs, restingPosition: UDim2)
	refs.panel.Visible = false
	refs.panel.GroupTransparency = 1
	refs.panel.Position = restingPosition
	refs.panelScale.Scale = 1
	refs.donationWrapper.Visible = false
	if refs.countDownBar then
		refs.countDownBar.Size = UDim2.new(1, 0, refs.countDownBar.Size.Y.Scale, refs.countDownBar.Size.Y.Offset)
	end
	if refs.rotatingBackground then
		refs.rotatingBackground.Rotation = 0
		refs.rotatingBackground.ImageTransparency = 1
	end
	setVisible(refs.backgroundWrapper, false)
	setVisible(refs.totalDonationsWrapper, false)
	setVisible(refs.senderUsername, false)
end
-- POPULATE / CLEAR
local function populateGui(refs: GuiRefs, payload: DonationNotifPayload)
	local msgText = normalizeMessage(payload.message)
	-- DisplayName: prefer live player DisplayName, fallback saweriaName
	-- 3B fix: resolveDisplayIdentity sekarang return 3 values (displayName,
	-- username, subtitle). subtitle = saweriaName untuk Bagibagi donations
	-- supaya UI show both names. Append ke displayName kalau ada.
	local displayName, username, subtitle = resolveDisplayIdentity(payload)
	if displayName == nil or displayName == "" then
		displayName = payload.saweriaName
	end
	if subtitle and subtitle ~= "" then
		displayName = displayName .. " (" .. subtitle .. ")"
	end
	if refs.senderDisplayName then
		refs.senderDisplayName.Text = displayName
	end
	if refs.senderUsername then
		-- 3A fix: username sekarang di-resolve dari robloxUsername untuk both
		-- Robux dan Bagibagi. DEFAULT_SENDER_USERNAME hanya fallback terakhir.
		local hasUsername = username ~= ""
		refs.senderUsername.Text = if hasUsername
			then "@" .. username
			else DEFAULT_SENDER_USERNAME
		refs.senderUsername.Visible = true
	end
	if refs.donationValue then
		local isRobux = payload.source == "robux"
		refs.donationValue.Text = if isRobux then formatGrouped(payload.amount) else formatRupiah(payload.amount)
		refs.donationValue.TextSize = if payload.amount >= 1_000_000
			then 31
			elseif payload.amount >= 100_000 then 38
			else 40
	end
	if refs.donationMessage then
		refs.donationMessage.Text = msgText and ('"' .. msgText .. '"') or EMPTY_MESSAGE_TEXT
	end
	if refs.senderTotalDonations then
		refs.senderTotalDonations.Text = formatTotalDonation(payload.totalDonationAmount, payload.source)
	end
	if refs.totalDonationsWrapper then
		refs.totalDonationsWrapper.Visible = true
	end
	if refs.senderProfpic then
		refs.senderProfpic.ImageTransparency = 0
		refs.senderProfpic.Image = refs.senderProfpicDefaultImage or refs.senderProfpic.Image
	end
	-- RoleBadge: set image sesuai role dari overhead cache, hide untuk Guest/tidak dikenal
	if refs.roleBadge then
		local badgeImage: string? = nil
		if type(payload.robloxUserId) == "number" then
			local role = OverheadController.getPlayerRole(payload.robloxUserId)
			if role then
				badgeImage = Config.Donation.ROLE_BADGE_IMAGE[role]
			end
		end
		if badgeImage then
			refs.roleBadge.Image = badgeImage
			refs.roleBadge.Visible = true
		else
			refs.roleBadge.Visible = false
		end
	end
end
local function clearGuiContent(refs: GuiRefs)
	if refs.senderDisplayName then
		refs.senderDisplayName.Text = ""
	end
	if refs.donationValue then
		refs.donationValue.Text = ""
	end
	if refs.donationMessage then
		refs.donationMessage.Text = ""
	end
	if refs.senderUsername then
		refs.senderUsername.Text = ""
	end
	if refs.senderTotalDonations then
		refs.senderTotalDonations.Text = ""
	end
	if refs.senderProfpic and refs.senderProfpicDefaultImage then
		refs.senderProfpic.Image = refs.senderProfpicDefaultImage
	end
end
local function applySenderThumbnail(refs: GuiRefs, payload: DonationNotifPayload)
	if not refs.senderProfpic then
		return
	end
	local img = refs.senderProfpic
	local requesterId = payload.robloxUserId
	if type(requesterId) ~= "number" and type(payload.robloxUsername) == "string" and payload.robloxUsername ~= "" then
		local ok, uid = pcall(Players.GetUserIdFromNameAsync, Players, payload.robloxUsername :: string)
		if ok and type(uid) == "number" then
			requesterId = uid
		end
	end
	if type(requesterId) ~= "number" then
		return
	end
	-- HTTP API telemetry counter (quota-efficiency-pass-2026-06, Phase 0).
	-- Only fire when wrapper disabled (when enabled, wrapper's internal counter handles it).
	if (not (Config.ClientHttpApi and Config.ClientHttpApi.ENABLED)) and Config.HttpApi and Config.HttpApi.COUNTERS_ENABLED then
		HttpApiCounter.record("donation_notif_thumb_total")
	end
	task.spawn(function()
		local thumb = ClientThumbnailCache.getOrFetch(
			requesterId :: number,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size100x100
		)
		if thumb and img.Parent then
			img.Image = thumb
		end
	end)
end

local function applyWorkspaceThumbnail(imageLabel: ImageLabel?, payload: DonationNotifPayload)
	if not imageLabel then
		return
	end
	local requesterId = payload.robloxUserId
	if type(requesterId) ~= "number" and type(payload.robloxUsername) == "string" and payload.robloxUsername ~= "" then
		local ok, uid = pcall(Players.GetUserIdFromNameAsync, Players, payload.robloxUsername :: string)
		if ok and type(uid) == "number" then
			requesterId = uid
		end
	end
	if type(requesterId) ~= "number" then
		return
	end
	-- HTTP API telemetry counter (quota-efficiency-pass-2026-06, Phase 0).
	-- Only fire when wrapper disabled (when enabled, wrapper's internal counter handles it).
	if (not (Config.ClientHttpApi and Config.ClientHttpApi.ENABLED)) and Config.HttpApi and Config.HttpApi.COUNTERS_ENABLED then
		HttpApiCounter.record("donation_notif_thumb_total")
	end
	task.spawn(function()
		local thumb = ClientThumbnailCache.getOrFetch(
			requesterId :: number,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size420x420
		)
		if thumb and imageLabel.Parent then
			imageLabel.Image = thumb
		end
	end)
end

local function populateWorkspaceSurfaces(refs: WorkspaceSurfaceRefs, payload: DonationNotifPayload)
	-- 3B fix: handle subtitle (saweriaName) dari resolveDisplayIdentity
	local displayName, username, subtitle = resolveDisplayIdentity(payload)
	local normalizedMessage = normalizeMessage(payload.message)
	local messageText = normalizedMessage or "YOUR DONATION MESSAGE WILL SHOW UP HERE"
	-- 3A fix: username sekarang di-resolve dari robloxUsername. "@donatur"
	-- hanya fallback kalau tidak ada Roblox identity sama sekali.
	local usernameText = if username ~= "" then "@" .. username:gsub("^@", "") else "@donatur"
	-- Append subtitle ke displayName untuk workspace live board juga
	if subtitle and subtitle ~= "" then
		displayName = displayName .. " (" .. subtitle .. ")"
	end

	if refs.liveDisplayName then
		refs.liveDisplayName.Text = string.upper(displayName) .. " DONATED"
	end
	if refs.liveUsername then
		refs.liveUsername.Text = usernameText
	end
	if refs.liveTotalDonations then
		refs.liveTotalDonations.Text = formatGrouped(payload.amount)
	end
	if refs.liveDonationMessage then
		refs.liveDonationMessage.Text = string.upper(messageText)
	end
	if refs.liveThanksMessage then
		refs.liveThanksMessage.Text = "THANKS FOR YOUR SUPPORT " .. usernameText
	end
	if refs.liveLastUpdate then
		refs.liveLastUpdate.Text = workspaceTimestampText()
	end
	if refs.runningText then
		-- 3B fix: pass subtitle ke buildRunningText
		-- Note: displayName sudah include subtitle di-append di atas, jadi
		-- untuk running text kita pakai displayName tanpa append ulang.
		-- Build running text dari original displayName + subtitle terpisah.
		local rawDisplayName, rawUsername, rawSubtitle = resolveDisplayIdentity(payload)
		refs.runningText.Text = buildRunningText(payload, rawDisplayName, rawUsername, rawSubtitle)
	end

	applyWorkspaceThumbnail(refs.liveAvatar, payload)
	popLiveChatInfo(refs)
end

local function captureWorkspaceSurfaceTemplate(refs: WorkspaceSurfaceRefs): WorkspaceSurfaceTemplate
	return {
		liveAvatarImage = refs.liveAvatar and refs.liveAvatar.Image or nil,
		liveCommunityImage = refs.liveCommunity and refs.liveCommunity.Image or nil,
		liveUsernameText = refs.liveUsername and refs.liveUsername.Text or nil,
		liveDisplayNameText = refs.liveDisplayName and refs.liveDisplayName.Text or nil,
		liveTotalDonationsText = refs.liveTotalDonations and refs.liveTotalDonations.Text or nil,
		liveDonationMessageText = refs.liveDonationMessage and refs.liveDonationMessage.Text or nil,
		liveThanksMessageText = refs.liveThanksMessage and refs.liveThanksMessage.Text or nil,
		liveLastUpdateText = refs.liveLastUpdate and refs.liveLastUpdate.Text or nil,
		runningText = refs.runningText and refs.runningText.Text or nil,
		runningLogoImage = refs.runningLogo and refs.runningLogo.Image or nil,
	}
end

local function restoreWorkspaceSurfaces(refs: WorkspaceSurfaceRefs, template: WorkspaceSurfaceTemplate)
	if refs.liveAvatar and template.liveAvatarImage then
		refs.liveAvatar.Image = template.liveAvatarImage
	end
	if refs.liveCommunity and template.liveCommunityImage then
		refs.liveCommunity.Image = template.liveCommunityImage
	end
	if refs.liveUsername and template.liveUsernameText then
		refs.liveUsername.Text = template.liveUsernameText
	end
	if refs.liveDisplayName and template.liveDisplayNameText then
		refs.liveDisplayName.Text = template.liveDisplayNameText
	end
	if refs.liveTotalDonations and template.liveTotalDonationsText then
		refs.liveTotalDonations.Text = template.liveTotalDonationsText
	end
	if refs.liveDonationMessage and template.liveDonationMessageText then
		refs.liveDonationMessage.Text = template.liveDonationMessageText
	end
	if refs.liveThanksMessage and template.liveThanksMessageText then
		refs.liveThanksMessage.Text = template.liveThanksMessageText
	end
	if refs.liveLastUpdate and template.liveLastUpdateText then
		refs.liveLastUpdate.Text = template.liveLastUpdateText
	end
	if refs.runningText and template.runningText then
		refs.runningText.Text = asRunningText(template.runningText)
	end
	if refs.runningLogo and template.runningLogoImage then
		refs.runningLogo.Image = template.runningLogoImage
	end
	resetLiveChatInfoVisibility(refs)
end

local function buildWorkspaceSurfaceStates(): { WorkspaceSurfaceState }
	local states = {}
	for _, refs in ipairs(resolveWorkspaceSurfaceRefsList()) do
		table.insert(states, {
			refs = refs,
			template = captureWorkspaceSurfaceTemplate(refs),
		})
		resetLiveChatInfoVisibility(refs)
	end
	return states
end

local function hasLiveWorkspaceSurface(refs: WorkspaceSurfaceRefs): boolean
	return (refs.liveChatGui ~= nil and refs.liveChatGui.Parent ~= nil)
		or (refs.runningTextGui ~= nil and refs.runningTextGui.Parent ~= nil)
end

local function resetLiveChatInfoVisibilityForStates(states: { WorkspaceSurfaceState })
	for _, state in ipairs(states) do
		resetLiveChatInfoVisibility(state.refs)
	end
end

local function refreshWorkspaceTimestampForStates(states: { WorkspaceSurfaceState })
	for _, state in ipairs(states) do
		refreshWorkspaceTimestamp(state.refs)
	end
end

local function populateWorkspaceSurfaceStates(states: { WorkspaceSurfaceState }, payload: DonationNotifPayload)
	for _, state in ipairs(states) do
		populateWorkspaceSurfaces(state.refs, payload)
	end
end

local function restoreWorkspaceSurfaceStates(states: { WorkspaceSurfaceState })
	for _, state in ipairs(states) do
		restoreWorkspaceSurfaces(state.refs, state.template)
	end
end

local function popOutLiveChatInfoForStates(states: { WorkspaceSurfaceState }, onDone: (() -> ())?)
	local pending = 0
	local completed = false

	local function markDone()
		pending -= 1
		if pending <= 0 and not completed then
			completed = true
			if onDone then
				onDone()
			end
		end
	end

	for _, state in ipairs(states) do
		if state.refs.liveChatGui and state.refs.liveChatGui.Parent then
			pending += 1
			popOutLiveChatInfo(state.refs, markDone)
		end
	end

	if pending == 0 and onDone then
		onDone()
	end
end

local RUNNING_STRIP_MAX = 8
local LEGACY_RUNTIME_STRIP_NAMES = {
	"RuntimeContentWrapperB",
	"RuntimeContentWrapperC",
	"RuntimeContentWrapperD",
}

local function isRunningTextDebugEnabled(): boolean
	return Config.Donation.RUNNING_TEXT_DEBUG == true
end

local function getRuntimeStripCloneName(slotIndex: number): string
	if slotIndex == 2 then
		return "RuntimeContentWrapperB"
	end
	if slotIndex == 3 then
		return "RuntimeContentWrapperC"
	end
	if slotIndex == 4 then
		return "RuntimeContentWrapperD"
	end
	return "RuntimeContentWrapper_" .. tostring(slotIndex)
end

local function getRunningClipSize(wrapper: Frame, gui: SurfaceGui): (number, number)
	local clipWidth = math.max(wrapper.AbsoluteSize.X, 1)
	local clipHeight = math.max(wrapper.AbsoluteSize.Y, gui.AbsoluteSize.Y, 1)
	if clipWidth < 8 then
		clipWidth = math.max(gui.AbsoluteSize.X, 1)
	end
	return clipWidth, clipHeight
end

type SuspendedWrapperLayout = {
	layout: Instance,
	parent: Instance,
}

-- UIListLayout has no .Enabled in Roblox. Only suspend layouts parented directly under Wrapper
-- (ContentWrapper's internal list layout must stay for logo + text).
local function suspendWrapperStripLayouts(wrapper: Frame, bucket: { SuspendedWrapperLayout })
	for _, child in ipairs(wrapper:GetChildren()) do
		if child:IsA("UIListLayout") or child:IsA("UITableLayout") then
			table.insert(bucket, {
				layout = child,
				parent = wrapper,
			})
			child.Parent = nil
		end
	end
end

local function restoreWrapperStripLayouts(bucket: { SuspendedWrapperLayout })
	for _, item in ipairs(bucket) do
		if item.layout.Parent == nil and item.parent.Parent then
			item.layout.Parent = item.parent
		end
	end
	table.clear(bucket)
end

local function syncRunningStripText(strip: Frame, text: string)
	local label = findTextLabel(strip, "CustomizeableText")
	if label then
		label.Text = text
	end
end

local function getRunningTextStripPool(refs: WorkspaceSurfaceRefs, stripCount: number): { Frame }
	local wrapper = refs.runningWrapper
	local content = refs.runningContent
	local pool: { Frame } = {}
	if not wrapper or not content or stripCount < 1 then
		return pool
	end

	table.insert(pool, content)
	for slotIndex = 2, stripCount do
		local cloneName = getRuntimeStripCloneName(slotIndex)
		local strip = wrapper:FindFirstChild(cloneName)
		if not strip then
			strip = content:Clone()
			strip.Name = cloneName
			strip.Parent = wrapper
		end
		if strip:IsA("Frame") then
			table.insert(pool, strip)
		end
	end

	local activeStrips: { [Frame]: boolean } = {}
	for _, strip in ipairs(pool) do
		activeStrips[strip] = true
	end
	for _, child in ipairs(wrapper:GetChildren()) do
		if child:IsA("Frame") and child ~= content and child.Name:match("^RuntimeContentWrapper") then
			child.Visible = activeStrips[child :: Frame] == true
		end
	end
	for _, legacyName in ipairs(LEGACY_RUNTIME_STRIP_NAMES) do
		local legacy = wrapper:FindFirstChild(legacyName)
		if legacy and legacy:IsA("Frame") and not activeStrips[legacy :: Frame] then
			legacy.Visible = false
		end
	end
	for _, strip in ipairs(pool) do
		strip.Visible = true
	end
	return pool
end

-- Strip count from viewport / spacing — NOT from contentWidth <= viewportWidth.
-- One strip (~1957px) on a ~4583px board still needs 4 tiles to fill + seamless scroll.
local function computeRunningStripCount(viewportWidth: number, contentWidth: number, gap: number): number
	local spacing = contentWidth + gap
	if spacing <= 0 then
		return 2
	end
	local needed = math.ceil(viewportWidth / spacing) + 2
	return math.clamp(needed, 2, RUNNING_STRIP_MAX)
end

local function getRightmostStripX(positions: { number }, excludeIndex: number?): number
	local rightmost = -math.huge
	for index, x in ipairs(positions) do
		if index ~= excludeIndex and x > rightmost then
			rightmost = x
		end
	end
	if rightmost == -math.huge then
		return 0
	end
	return rightmost
end

-- Pre-fill the wide viewport so tiles scroll in from the right edge, not pop in mid-board.
local function buildInitialRunningStripPositions(
	viewportWidth: number,
	spacing: number,
	stripCount: number
): { number }
	local positions: { number } = {}
	for index = 1, stripCount do
		positions[index] = viewportWidth - (stripCount - index) * spacing
	end
	local leftmost = positions[1]
	if leftmost > 0 then
		for index = 1, stripCount do
			positions[index] -= leftmost
		end
	end
	return positions
end

local function measureTextWidth(label: TextLabel, text: string): number
	local params = Instance.new("GetTextBoundsParams")
	params.Text = text
	params.Font = label.FontFace
	params.Size = label.TextSize
	params.Width = math.huge

	local ok, result = pcall(function()
		return TextService:GetTextBoundsAsync(params)
	end)
	if ok then
		return result.X
	end

	return label.TextBounds.X
end

local function getRunningTextContentWidth(
	content: Frame,
	textLabel: TextLabel,
	clipHeight: number,
	text: string
): number
	local contentHeight = math.max(clipHeight, 1)
	local textWidth = math.ceil(measureTextWidth(textLabel, text)) + 72
	local logoWidth = 0
	local logo = findImageLabel(content, "LogoImage")
	if logo and logo.Visible then
		logoWidth = math.max(logo.AbsoluteSize.X, 56)
	end

	local layoutPadding = 32
	local layout = content:FindFirstChildWhichIsA("UIListLayout")
	if layout then
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layoutPadding = math.max(layout.Padding.Offset + layout.Padding.Scale * contentHeight, layoutPadding)
	end

	textLabel.AutomaticSize = Enum.AutomaticSize.None
	textLabel.TextWrapped = false
	textLabel.Size = UDim2.fromOffset(textWidth, contentHeight)
	return math.max(textWidth + logoWidth + layoutPadding + 32, 1)
end

local function prepareRunningTextStrip(strip: Frame, text: string, contentWidth: number, contentHeight: number)
	strip.AnchorPoint = Vector2.new(0, 0.5)
	strip.Size = UDim2.fromOffset(contentWidth, contentHeight)
	strip.ClipsDescendants = false

	local label = findTextLabel(strip, "CustomizeableText")
	if label then
		label.Text = text
		label.AutomaticSize = Enum.AutomaticSize.None
		label.TextWrapped = false
		label.Size = UDim2.fromOffset(math.ceil(measureTextWidth(label, text)) + 72, contentHeight)
	end
end

local function startRunningTextMarquee(refs: WorkspaceSurfaceRefs, isTokenCurrent: () -> boolean)
	local wrapper = refs.runningWrapper
	local content = refs.runningContent
	local textLabel = refs.runningText
	local gui = refs.runningTextGui
	if not wrapper or not content or not textLabel or not gui then
		return
	end

	task.spawn(function()
		task.wait(0.2)
		local speed = 140
		local strips: { Frame } = {}
		local positions: { number } = {}
		local spacing = 0
		local contentWidth = 0
		local clipWidth = 0
		local contentHeight = 0
		local y = 0
		local lastLayoutKey = ""
		local debugAccum = 0
		local marqueeAccum = 0
		local MARQUEE_INTERVAL = 0.033
		local suspendedLayouts: { SuspendedWrapperLayout } = {}

		while isTokenCurrent() and content.Parent and textLabel.Parent and gui.Parent and wrapper.Parent do
			textLabel.Text = asRunningText(textLabel.Text)

			clipWidth, contentHeight = getRunningClipSize(wrapper, gui)
			if clipWidth < 8 then
				RunService.Heartbeat:Wait()
				continue
			end

			wrapper.ClipsDescendants = true
			content.ClipsDescendants = false
			if #suspendedLayouts == 0 then
				suspendWrapperStripLayouts(wrapper, suspendedLayouts)
			end

			RunService.Heartbeat:Wait()
			local text = asRunningText(textLabel.Text)
			if text == "" then
				RunService.Heartbeat:Wait()
				continue
			end

			local measuredWidth = getRunningTextContentWidth(content, textLabel, contentHeight, text)
			local gap = math.max(28, math.min(clipWidth * 0.04, 120))
			local newSpacing = measuredWidth + gap
			local stripCount = computeRunningStripCount(clipWidth, measuredWidth, gap)
			local layoutKey = string.format(
				"%d|%d|%d|%s",
				math.floor(clipWidth),
				math.floor(measuredWidth),
				stripCount,
				text
			)

			if layoutKey ~= lastLayoutKey then
				lastLayoutKey = layoutKey
				spacing = newSpacing
				contentWidth = measuredWidth
				y = math.floor(contentHeight * 0.5)
				strips = getRunningTextStripPool(refs, stripCount)
				if #strips == 0 then
					RunService.Heartbeat:Wait()
					continue
				end
				for _, strip in ipairs(strips) do
					syncRunningStripText(strip, text)
					prepareRunningTextStrip(strip, text, contentWidth, contentHeight)
					strip.ClipsDescendants = false
				end
				positions = buildInitialRunningStripPositions(clipWidth, spacing, #strips)
				if isRunningTextDebugEnabled() then
					log:warn("RunningText layout applied", {
						clipWidth = clipWidth,
						contentWidth = contentWidth,
						spacing = spacing,
						stripCount = #strips,
						positions = table.concat(positions, ","),
						guiPath = gui:GetFullName(),
					})
				end
			end

			if #strips == 0 or #positions == 0 then
				RunService.Heartbeat:Wait()
				continue
			end

			local dt = RunService.Heartbeat:Wait()
			marqueeAccum += dt
			if marqueeAccum < MARQUEE_INTERVAL then
				continue
			end
			marqueeAccum = 0
			for index, strip in ipairs(strips) do
				if not strip.Parent then
					continue
				end
				positions[index] -= speed * dt
				if positions[index] <= -contentWidth then
					local rightmost = getRightmostStripX(positions, index)
					positions[index] = math.max(clipWidth, rightmost + spacing)
				end
				strip.Position = UDim2.fromOffset(math.floor(positions[index]), y)
			end

			if isRunningTextDebugEnabled() then
				debugAccum += dt
				if debugAccum >= 2 then
					debugAccum = 0
					local posParts: { string } = {}
					for _, x in ipairs(positions) do
						table.insert(posParts, tostring(math.floor(x)))
					end
					log:warn("RunningText tick", {
						clipWidth = clipWidth,
						contentWidth = contentWidth,
						spacing = spacing,
						stripCount = #strips,
						positions = table.concat(posParts, ","),
					})
				end
			end
		end

		restoreWrapperStripLayouts(suspendedLayouts)
	end)
end

local function startRunningTextMarquees(states: { WorkspaceSurfaceState }, isTokenCurrent: () -> boolean)
	for _, state in ipairs(states) do
		startRunningTextMarquee(state.refs, isTokenCurrent)
	end
end
-- CHAT BROADCAST
local function displayInGeneralChat(payload: DonationNotifPayload)
	local ok, err = pcall(function(): boolean
		local channels = TextChatService:FindFirstChild("TextChannels")
		if not channels then
			return true
		end
		local general = channels:FindFirstChild("RBXGeneral") :: TextChannel?
		if not general then
			return true
		end
		local msgText = normalizeMessage(payload.message)
		local rankInfo = ""
		if payload.newRank then
			rankInfo = " - " .. (Config.Donation.TOP_SPENDER_TEXTS[payload.newRank] or ("Top #" .. payload.newRank))
		end
		local msgInfo = msgText and (' - "' .. msgText .. '"') or ""
		-- 3B fix: pakai Roblox displayName + username (konsisten dengan notif card)
		-- Sebelumnya pakai payload.saweriaName langsung → always "donatur"/"Bagibagi Donor"
		local displayName, username, subtitle = resolveDisplayIdentity(payload)
		local nameSegment = displayName
		if username and username ~= "" then
			nameSegment = nameSegment .. " @" .. username:gsub("^@", "")
		end
		if subtitle and subtitle ~= "" then
			nameSegment = nameSegment .. " (via " .. subtitle .. ")"
		end
		general:DisplaySystemMessage(
			string.format(
				'<font color="#FFD700">[DONASI] DONASI MASUK</font>  <b>%s</b> <font color="#B4FFB4">%s</font>%s%s',
				nameSegment,
				formatDonationAmount(payload),
				rankInfo,
				msgInfo
			)
		)
		return true
	end)
	if not ok then
		log:debug("Chat display error (non-critical)", { err = tostring(err) })
	end
end
-- INIT
local function init(_deps: {}?)
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local guiRefs: GuiRefs? = resolveGuiRefs(playerGui)
	local workspaceSurfaceStates: { WorkspaceSurfaceState } = buildWorkspaceSurfaceStates()
	if not guiRefs then
		return
	end
	-- Capture resting position dari Studio sebelum kita animasikan apapun
	local restingPosition: UDim2 = guiRefs.panel.Position
	resetGuiState(guiRefs :: GuiRefs, restingPosition)
	local queue: { DonationNotifPayload } = {}
	local isShowingNotif = false
	local isProcessingQueue = false
	local function syncDonationBroadcastLayout()
		local active = isShowingNotif or isProcessingQueue or #queue > 0
		GenericBroadcastLayoutBridge.setDonationNotifActive(active)
	end
	local maxPendingQueue = math.max(1, Config.Donation.NOTIF_MAX_QUEUE)
	local backlogDisplayScale = math.clamp(tonumber(Config.Donation.NOTIF_BACKLOG_DISPLAY_SCALE) or 0.6, 0.25, 1)
	local backlogThreshold = math.max(1, math.floor(maxPendingQueue * 0.5))
	-- Token untuk membatalkan loop background spin & heartbeat
	local animToken = 0
	local runningTextToken = 0
	local workspaceRestoreToken = 0
	-- Dedup guard state
	-- 3D fix: dedup key pakai robloxUserId (bukan saweriaName) supaya donor
	-- berbeda dengan nama sama/"donatur" tidak di-collapse sebagai duplicate.
	-- Fallback ke saweriaName kalau robloxUserId nil (edge case).
	local lastEnqueuedDedupKey: string = ""
	local lastEnqueuedAmount: number = 0
	local lastEnqueuedAt: number = 0
	-- Re-resolve refs bila stale (handle ResetOnSpawn setelah respawn)
	local function getGuiRefs(): GuiRefs?
		local current = guiRefs
		if current and current.panel and current.panel.Parent then
			return current
		end
		log:debug("GUI refs stale — re-resolving")
		local fresh = resolveGuiRefs(playerGui)
		guiRefs = fresh
		if fresh then
			resetGuiState(fresh, restingPosition)
		end
		return fresh
	end
	local function getWorkspaceSurfaceStates(): { WorkspaceSurfaceState }
		local current = workspaceSurfaceStates
		local allAlive = #current > 0
		for _, state in ipairs(current) do
			if not hasLiveWorkspaceSurface(state.refs) then
				allAlive = false
				break
			end
		end
		if allAlive and #resolveWorkspaceSurfaceRefsList() == #current then
			return current
		end
		workspaceSurfaceStates = buildWorkspaceSurfaceStates()
		return workspaceSurfaceStates
	end
	local function restartIdleRunningText()
		runningTextToken += 1
		local token = runningTextToken
		local states = getWorkspaceSurfaceStates()
		resetLiveChatInfoVisibilityForStates(states)
		refreshWorkspaceTimestampForStates(states)
		startRunningTextMarquees(states, function()
			return runningTextToken == token
		end)
	end
	local function scheduleWorkspaceRestore(expectedToken: number)
		task.delay(Config.Donation.WORKSPACE_RESTORE_DELAY, function()
			if workspaceRestoreToken ~= expectedToken then
				return
			end

			local states = getWorkspaceSurfaceStates()
			popOutLiveChatInfoForStates(states, function()
				if workspaceRestoreToken ~= expectedToken then
					return
				end
				restoreWorkspaceSurfaceStates(states)
				restartIdleRunningText()
			end)
		end)
	end
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	if not remotes then
		log:warn("Remotes folder tidak ditemukan")
		return
	end
	local notifRemote = remotes:WaitForChild(Config.Donation.REMOTE_NOTIFICATION, 15) :: RemoteEvent?
	if not notifRemote then
		log:warn("DonationNotification remote tidak ditemukan")
		return
	end
	-- BACKGROUND SPIN LOOP
	-- Dipanggil setelah panel selesai animate masuk.
	-- Loop berjalan sampai token berubah (saat exit dipanggil).
	local function startBackgroundSpin(refs: GuiRefs, token: number)
		local bg = refs.rotatingBackground
		if not bg then
			return
		end
		-- Wrapper sudah visible, kita fade-in bg secara terpisah
		bg.Rotation = 0
		bg.ImageTransparency = 1
		-- Fade in background
		tween(bg, TweenInfo.new(BG_FADE_IN_DUR, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			ImageTransparency = 0.9,
		})
		-- Spin loop - setiap iterasi 360 deg linear
		task.spawn(function()
			local currentRotation = 0
			while animToken == token do
				if not bg.Parent then
					break
				end
				local spinTween = TweenService:Create(
					bg,
					TweenInfo.new(BG_SPIN_PERIOD, Enum.EasingStyle.Linear, Enum.EasingDirection.In),
					{
						Rotation = currentRotation + 360,
					}
				)
				spinTween:Play()
				spinTween.Completed:Wait()
				-- Hanya update jika token masih valid
				if animToken == token and bg.Parent then
					-- Pakai modulo agar angka tidak terus menumpuk
					currentRotation = (currentRotation + 360) % 36000
					bg.Rotation = currentRotation % 360
				end
			end
		end)
	end
	-- STAGGER CONTENT REVEAL
	-- Elemen konten muncul bergiliran setelah panel settled.
	-- Setiap elemen: slide in from side + fade opacity.
	local function staggerReveal(refs: GuiRefs, token: number)
		task.spawn(function()
			-- Helper: slide+fade untuk satu GuiObject
			local function revealElement(elem: GuiObject?, delaySec: number)
				if not elem or animToken ~= token then
					return
				end
				task.wait(delaySec)
				if animToken ~= token or not elem.Parent then
					return
				end
				-- Simpan posisi asli
				local origPos = elem.Position
				-- Mulai dari sedikit ke kanan + transparan
				elem.Position = origPos + UDim2.fromOffset(STAGGER_SLIDE_DIST, 0)
				-- Jika TextLabel, fade TextTransparency juga
				local isTextLabel = elem:IsA("TextLabel")
				if isTextLabel then
					(elem :: TextLabel).TextTransparency = 1
				end
				-- Tween posisi kembali ke origi
				tween(
					elem,
					TweenInfo.new(STAGGER_FADE_DUR, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
					{ Position = origPos }
				)
				-- Fade in opacity (terpisah agar bisa tween bersamaan)
				if isTextLabel then
					tweenWait(
						elem :: TextLabel,
						TweenInfo.new(STAGGER_FADE_DUR, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
						{ TextTransparency = 0 }
					)
				end
			end
			revealElement(refs.senderDisplayName :: GuiObject?, STAGGER_DELAY_SENDER)
			revealElement(refs.donationValue :: GuiObject?, STAGGER_DELAY_VALUE)
			revealElement(refs.donationMessage :: GuiObject?, STAGGER_DELAY_MESSAGE)
		end)
	end
	-- SHOW NOTIFICATION - sequence lengkap entrance
	local function showNotif(payload: DonationNotifPayload)
		local refs = getGuiRefs()
		local surfaceStates = getWorkspaceSurfaceStates()
		if not refs then
			log:warn("GUI refs tidak valid saat showNotif dipanggil")
			return
		end
		isShowingNotif = true
		syncDonationBroadcastLayout()

		-- World VFX follows notif show cadence (abort previous via WorldEffectFlight).
		local worldEffect = payload.worldEffect
		if type(worldEffect) == "string" and worldEffect ~= "" then
			if DonationExperiencePrefs.shouldShowWorldEffect() and DonationVfxClientGate.shouldPlayWorldEffect() then
				local donorName = if type(payload.robloxUsername) == "string" and payload.robloxUsername ~= ""
					then payload.robloxUsername
					elseif type(payload.robloxDisplayName) == "string" and payload.robloxDisplayName ~= ""
					then payload.robloxDisplayName
					else payload.saweriaName
				local recipientName = "Club"
				if type(Config.Branding) == "table" and type(Config.Branding.GAME_NAME) == "string" and Config.Branding.GAME_NAME ~= "" then
					recipientName = Config.Branding.GAME_NAME
				end
				WorldEffectDispatch.fire(
					worldEffect,
					donorName,
					recipientName,
					tonumber(payload.amount) or 0,
					payload.robloxUserId
				)
			end
		end

		animToken += 1
		runningTextToken += 1
		workspaceRestoreToken += 1
		local token = animToken
		local marqueeToken = runningTextToken
		local restoreToken = workspaceRestoreToken
		setDonationHudHidden(playerGui, true)
		-- Camera and bars are server-authoritative; only Level 7+ tiers trigger them.
		switchTemplate(refs, payload.source)
		-- Reset bersih
		resetGuiState(refs, restingPosition)
		populateGui(refs, payload)
		applySenderThumbnail(refs, payload)
		populateWorkspaceSurfaceStates(surfaceStates, payload)
		startRunningTextMarquees(surfaceStates, function()
			return runningTextToken == marqueeToken
		end)
		scheduleWorkspaceRestore(restoreToken)
		-- Siapkan state awal animasi entrance
		-- Panel: di atas resting, kecil, transparan penuh
		refs.panel.Position = restingPosition + UDim2.fromOffset(0, ENTER_SLIDE_OFFSET)
		refs.panelScale.Scale = ENTER_SCALE_FROM
		refs.panel.GroupTransparency = 1
		refs.panel.Visible = true
		refs.donationWrapper.Visible = true
		setVisible(refs.backgroundWrapper, true) -- wrapper visible tapi bg masih transparan
		-- Phase 1: slide masuk + pop scale (spring overshoot)
		-- Panel meluncur ke bawah restingPos + sedikit overshoot
		local targetPhase1 = restingPosition + UDim2.fromOffset(0, ENTER_OVERSHOOT_BELOW)
		-- Play serentak: posisi + skala + fade-in
		tween(refs.panel, TweenInfo.new(ENTER_PHASE1_DUR, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = targetPhase1,
			GroupTransparency = 0,
		})
		tweenWait(refs.panelScale, TweenInfo.new(ENTER_PHASE1_DUR, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = ENTER_SCALE_PEAK,
		})
		-- Phase 2: Settle ke posisi resting
		tween(refs.panel, TweenInfo.new(ENTER_PHASE2_DUR, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = restingPosition,
		})
		tweenWait(refs.panelScale, TweenInfo.new(ENTER_PHASE2_DUR, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1,
		})
		-- Panel sudah settled, mulai efek background dan reveal konten
		startBackgroundSpin(refs, token)
		staggerReveal(refs, token)
		-- CountDownBar: tween width 100% -> 0% selama durasi tampil (per-tier).
		local notifDuration = resolveNotifDuration(payload)
		-- Drain faster when more notifs are waiting (no drops).
		if #queue >= backlogThreshold then
			notifDuration = notifDuration * backlogDisplayScale
		end
		if refs.countDownBar then
			refs.countDownBar.Size = UDim2.new(1, 0, refs.countDownBar.Size.Y.Scale, refs.countDownBar.Size.Y.Offset)
			tween(
				refs.countDownBar,
				TweenInfo.new(notifDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
				{ Size = UDim2.new(0, 0, refs.countDownBar.Size.Y.Scale, refs.countDownBar.Size.Y.Offset) }
			)
		end
		-- Tunggu durasi tampil sesuai tier.
		task.wait(notifDuration)
		-- EXIT SEQUENCE
		-- Stop semua loop dengan invalidate token
		animToken += 1
		-- Fade out background dulu
		if refs.rotatingBackground and refs.rotatingBackground.Parent then
			tween(
				refs.rotatingBackground,
				TweenInfo.new(BG_FADE_OUT_DUR, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ ImageTransparency = 1 }
			)
		end
		-- Anticipation: sedikit compress dulu (seperti "napas" sebelum lompat)
		tweenWait(
			refs.panelScale,
			TweenInfo.new(EXIT_ANTICIPATION_DUR, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = EXIT_ANTICIPATION_SCALE }
		)
		-- Launch ke atas: panel terbang + mengecil + transparan
		local exitTarget = restingPosition + UDim2.fromOffset(0, EXIT_SLIDE_ABOVE)
		tween(
			refs.panelScale,
			TweenInfo.new(EXIT_LAUNCH_DUR, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
			{ Scale = ENTER_SCALE_FROM }
		)
		tweenWait(
			refs.panel,
			TweenInfo.new(EXIT_LAUNCH_DUR, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
			{ Position = exitTarget, GroupTransparency = 1 }
		)
		-- Cleanup after exit. Camera and bars are managed server-side.
		setDonationHudHidden(playerGui, false)
		resetGuiState(refs, restingPosition)
		clearGuiContent(refs)
		isShowingNotif = false
		syncDonationBroadcastLayout()
		if #queue > 0 then
			task.wait(Config.Donation.NOTIF_GAP_DURATION)
		end
	end
	-- QUEUE PROCESSOR
	local function processQueue()
		if isProcessingQueue or isShowingNotif then
			return
		end
		isProcessingQueue = true
		while #queue > 0 do
			local nextPayload = table.remove(queue, 1)
			if not nextPayload then
				continue
			end
			log:debug("Donation notification dequeue", {
				remainingQueue = #queue,
				saweriaName = tostring(nextPayload.saweriaName),
			})
			local ok, err = pcall(function(): boolean
				showNotif(nextPayload)
				return true
			end)
			if not ok then
				isShowingNotif = false
				syncDonationBroadcastLayout()
				animToken += 1 -- invalidate semua loop
				local refs = guiRefs
				if refs then
					pcall(setDonationHudHidden, playerGui, false)
					pcall(resetGuiState, refs, restingPosition)
					pcall(clearGuiContent, refs)
				end
				log:warn("Donation notification gagal diproses", {
					err = tostring(err),
					saweriaName = tostring(nextPayload.saweriaName),
				})
				task.wait(Config.Donation.NOTIF_GAP_DURATION)
			end
		end
		isProcessingQueue = false
		syncDonationBroadcastLayout()
	end
	local function startIdleRunningTextWhenReady()
		task.spawn(function()
			for _ = 1, 60 do
				local ready = false
				for _, state in ipairs(getWorkspaceSurfaceStates()) do
					local w = state.refs.runningWrapper
					local g = state.refs.runningTextGui
					if w and g and w.AbsoluteSize.X >= 64 then
						ready = true
						break
					end
				end
				if ready then
					break
				end
				RunService.Heartbeat:Wait()
			end
			restartIdleRunningText()
		end)
	end
	startIdleRunningTextWhenReady()
	task.delay(4, restartIdleRunningText)
	-- REMOTE EVENT HANDLER
	track(notifRemote.OnClientEvent:Connect(function(payload: any)
		log:info("Donation notification remote received", {
			saweriaName = type(payload) == "table" and payload.saweriaName or nil,
			amount = type(payload) == "table" and payload.amount or nil,
			robloxUsername = type(payload) == "table" and payload.robloxUsername or nil,
		})
		if type(payload) ~= "table" then
			return
		end
		if type(payload.saweriaName) ~= "string" then
			return
		end
		if type(payload.amount) ~= "number" then
			return
		end
		if not DonationExperiencePrefs.shouldShowAnnounce() then
			return
		end
		local notifPayload = payload :: DonationNotifPayload
		displayInGeneralChat(notifPayload)
		-- Dedup guard: filter payload identik dari burst polling (dalam DEDUP_WINDOW_SECS)
		-- 3D fix: dedup key pakai robloxUserId (bukan saweriaName) supaya donor
		-- berbeda dengan nama sama/"donatur" tidak di-collapse sebagai duplicate.
		-- Fallback ke saweriaName kalau robloxUserId nil.
		local now = os.clock()
		local dedupKey = if type(notifPayload.robloxUserId) == "number"
			then "uid:" .. tostring(notifPayload.robloxUserId)
			else "name:" .. tostring(notifPayload.saweriaName)
		local isDuplicate = (
			dedupKey == lastEnqueuedDedupKey
			and notifPayload.amount == lastEnqueuedAmount
			and (now - lastEnqueuedAt) < DEDUP_WINDOW_SECS
		)
		if isDuplicate then
			log:debug("Donation notification duplicate discarded", {
				dedupKey = dedupKey,
				amount = notifPayload.amount,
			})
			return
		end
		local pendingCount = #queue + (if isShowingNotif then 1 else 0)
		if pendingCount >= maxPendingQueue then
			-- Evict lowest-amount queued item to make room (never drop incoming solely for being new).
			local evictIdx: number? = nil
			local evictAmount = math.huge
			for i, queued in ipairs(queue) do
				local amt = tonumber(queued.amount) or 0
				if amt < evictAmount then
					evictAmount = amt
					evictIdx = i
				end
			end
			if evictIdx == nil then
				log:warn("Donation notification queue penuh, notif dibuang", {
					dedupKey = dedupKey,
					queueSize = #queue,
					isShowing = isShowingNotif,
				})
				return
			end
			local evicted = table.remove(queue, evictIdx)
			log:warn("Donation notification queue eviction (lowest amount)", {
				evictedAmount = evicted and evicted.amount or nil,
				evictedName = evicted and evicted.saweriaName or nil,
				incomingAmount = notifPayload.amount,
				queueSize = #queue,
			})
			syncDonationBroadcastLayout()
		end
		table.insert(queue, notifPayload)
		syncDonationBroadcastLayout()
		lastEnqueuedDedupKey = dedupKey
		lastEnqueuedAmount = notifPayload.amount
		lastEnqueuedAt = now
		log:debug("Donation notification queued", {
			queueSize = #queue,
			saweriaName = notifPayload.saweriaName,
			isShowing = isShowingNotif,
		})
		if not isProcessingQueue then
			task.spawn(processQueue)
		end
	end))
	log:info("DonationNotificationController initialized")
end
return { init = init, destroy = destroy }
