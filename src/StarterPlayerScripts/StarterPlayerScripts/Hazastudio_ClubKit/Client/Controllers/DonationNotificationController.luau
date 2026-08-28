--!strict
-- Client/Controllers/DonationNotificationController.lua
-- Receive DonationNotification from server; display Studio donation GUI.
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
local DonationAmountFormat = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DonationAmountFormat)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local DonationEffectTierResolver = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DonationEffectTierResolver)
local DonationExperiencePrefs = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DonationExperiencePrefs)
local HttpApiCounter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApiCounter)
local ClientThumbnailCache = require(script.Parent.Parent.Utils.ClientThumbnailCache)
local WorldEffectDispatch = require(script.Parent.Parent.Utils.WorldEffectDispatch)
local DonationVfxClientGate = require(script.Parent.Parent.Utils.DonationVfxClientGate)
local GroupMotion = require(script.Parent.Parent.Utils.GroupMotion)
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
	-- active template (set in showNotif based on payload.source)
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
	-- both templates stored for swapping
	saweriaRefs: TemplateRefs,
	robuxRefs: TemplateRefs,
}

type WorkspaceSurfaceRefs = {
	liveChatGui: SurfaceGui?,
	liveDonatorInfoRoot: Frame?,
	liveDonatorInfoCard: Frame?,
	liveDonatorInfoTotal: Frame?,
	liveFooter: Frame?,
	liveMessageWrapper: Frame?,
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
local ENTER_SLIDE_OFFSET = -80 -- px above resting on initial entrance (more dramatic)
local ENTER_OVERSHOOT_BELOW = 10 -- px past lower resting bound (spring feel)
local ENTER_SCALE_FROM = 0.82 -- initial scale (smaller -> pop more noticeable)
local ENTER_SCALE_PEAK = 1.055 -- peak scale on overshoot (more noticeable)
local ENTER_PHASE1_DUR = 0.42 -- slide-in + peak scale duration (smoother)
local ENTER_PHASE2_DUR = 0.16 -- settle-to-resting duration (smoother)
-- Background
local BG_SPIN_PERIOD = 7 -- seconds per 360 deg
local BG_FADE_IN_DUR = 0.3 -- bg fades in slowly after panel settled
local BG_FADE_OUT_DUR = 0.18 -- bg fades out on exit
-- Stagger reveals (content elements appear in sequence after panel settled)
local STAGGER_DELAY_SENDER = 0.05 -- offset after panel finishes animation
local STAGGER_DELAY_VALUE = 0.13
local STAGGER_DELAY_MESSAGE = 0.22
local STAGGER_SLIDE_DIST = 14 -- px - slide from side
local STAGGER_FADE_DUR = 0.32 -- fade+slide duration per element (smoother)
-- Exit
local EXIT_ANTICIPATION_DUR = 0.12 -- seconds "breath" before exit (more noticeable)
local EXIT_ANTICIPATION_SCALE = 0.970 -- compress deeper
local EXIT_LAUNCH_DUR = 0.30 -- fly-upward duration (more dramatic)
local EXIT_SLIDE_ABOVE = -65 -- px above resting on exit (farther)
local LIVECHAT_POP_FROM = 0.86
local LIVECHAT_POP_PEAK = 1.045
local LIVECHAT_POP_IN_DUR = 0.34
local LIVECHAT_POP_SETTLE_DUR = 0.2
local LIVECHAT_POP_OUT_SCALE = 0.9
local LIVECHAT_POP_OUT_DUR = 0.24
local LIVECHAT_FOOTER_IN_DUR = 0.28
local LIVECHAT_FOOTER_OUT_DUR = 0.18
local LIVECHAT_MSG_SETTLE_DUR = 0.28
local LIVECHAT_STAGGER_CARD = 0.02
local LIVECHAT_STAGGER_TOTAL = 0.1
local LIVECHAT_STAGGER_FOOTER = 0.14
-- Dedup guard: window (seconds) to filter duplicate notifs from burst polling
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

local EMPTY_MESSAGE_TEXT = "No message"
local DEFAULT_SENDER_USERNAME = "@donor"
local DEFAULT_TOTAL_DONATION = "Total: First donation"
local function getExternalProviderName(): string
	return DonationProviderDomain.getName()
end

local function applyExternalProviderText(root: Instance)
	DonationProviderDomain.applyDisplayText(root)
end

local function formatDonationAmount(payload: DonationNotifPayload): string
	if payload.source == "robux" then
		return DonationAmountFormat.formatGrouped(payload.amount) .. " Robux"
	end
	return DonationAmountFormat.formatCash(payload.amount)
end

local function formatTotalDonation(amount: number?, source: string?): string
	if type(amount) ~= "number" or amount <= 0 then
		return DEFAULT_TOTAL_DONATION
	end
	if source == "robux" then
		return "Total : " .. DonationAmountFormat.formatGrouped(amount) .. " Robux"
	end
	return "Total : " .. DonationAmountFormat.formatCash(amount)
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
	local liveFooter = if liveChatGui then liveChatGui:FindFirstChild("Footer", true) else nil
	local liveMessageWrapper = if liveChatGui then liveChatGui:FindFirstChild("MessageWrapper", true) else nil
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
		liveFooter = if liveFooter and liveFooter:IsA("Frame") then liveFooter else nil,
		liveMessageWrapper = if liveMessageWrapper and liveMessageWrapper:IsA("Frame") then liveMessageWrapper else nil,
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

local function setGroupTransparency(gui: GuiObject, value: number)
	pcall(function()
		gui.GroupTransparency = value
	end)
end

local function tweenGroupTransparency(gui: GuiObject, value: number, info: TweenInfo): Tween?
	local ok, tw = pcall(function()
		return TweenService:Create(gui, info, { GroupTransparency = value })
	end)
	if ok and tw then
		tw:Play()
		return tw
	end
	return nil
end

local function settleMessageWrapper(refs: WorkspaceSurfaceRefs, towardIdle: boolean)
	local frame = refs.liveMessageWrapper
	if not frame or not frame.Parent then
		return
	end
	local scale = getOrCreateLiveChatScale(frame)
	-- ADR 0005: live-chat wrappers may be CanvasGroups — keep them size-stable.
	scale.Scale = GroupMotion.scaleTarget(frame, if towardIdle then 0.96 else 0.97)
	TweenService:Create(
		scale,
		TweenInfo.new(LIVECHAT_MSG_SETTLE_DUR, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

local function showLiveChatFooter(refs: WorkspaceSurfaceRefs, delaySec: number)
	local footer = refs.liveFooter
	if not footer then
		return
	end
	task.delay(delaySec, function()
		if not footer.Parent then
			return
		end
		local scale = getOrCreateLiveChatScale(footer)
		footer.Visible = true
		scale.Scale = GroupMotion.scaleTarget(footer, 0.94)
		setGroupTransparency(footer, 1)
		TweenService:Create(
			scale,
			TweenInfo.new(LIVECHAT_FOOTER_IN_DUR, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
		tweenGroupTransparency(
			footer,
			0,
			TweenInfo.new(LIVECHAT_FOOTER_IN_DUR, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		)
	end)
end

local function hideLiveChatFooter(refs: WorkspaceSurfaceRefs, animated: boolean)
	local footer = refs.liveFooter
	if not footer then
		return
	end
	if not animated or not footer.Visible then
		footer.Visible = false
		setGroupTransparency(footer, 0)
		local scale = footer:FindFirstChild("RuntimePopScale")
		if scale and scale:IsA("UIScale") then
			scale.Scale = 1
		end
		return
	end
	local scale = getOrCreateLiveChatScale(footer)
	local outInfo = TweenInfo.new(LIVECHAT_FOOTER_OUT_DUR, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(scale, outInfo, { Scale = GroupMotion.scaleTarget(footer, 0.94) }):Play()
	local fade = tweenGroupTransparency(footer, 1, outInfo)
	local function finish()
		if footer.Parent then
			footer.Visible = false
			setGroupTransparency(footer, 0)
			scale.Scale = 1
		end
	end
	if fade then
		fade.Completed:Once(finish)
	else
		task.delay(LIVECHAT_FOOTER_OUT_DUR, finish)
	end
end

local function resetLiveChatInfoVisibility(refs: WorkspaceSurfaceRefs)
	if refs.liveDonatorInfoCard then
		refs.liveDonatorInfoCard.Visible = false
		getOrCreateLiveChatScale(refs.liveDonatorInfoCard).Scale = 1
		setGroupTransparency(refs.liveDonatorInfoCard, 0)
	end
	if refs.liveDonatorInfoTotal then
		refs.liveDonatorInfoTotal.Visible = false
		getOrCreateLiveChatScale(refs.liveDonatorInfoTotal).Scale = 1
		setGroupTransparency(refs.liveDonatorInfoTotal, 0)
	end
	-- Hide donor stack entirely while idle so MainWrapper UIListLayout can
	-- vertically center MessageWrapper (Footer is also hidden idle).
	if refs.liveDonatorInfoRoot then
		refs.liveDonatorInfoRoot.Visible = false
		getOrCreateLiveChatScale(refs.liveDonatorInfoRoot).Scale = 1
		setGroupTransparency(refs.liveDonatorInfoRoot, 0)
	end
	hideLiveChatFooter(refs, false)
end

local function popLiveChatInfo(refs: WorkspaceSurfaceRefs)
	settleMessageWrapper(refs, false)

	if refs.liveDonatorInfoRoot then
		local rootScale = getOrCreateLiveChatScale(refs.liveDonatorInfoRoot)
		refs.liveDonatorInfoRoot.Visible = true
		rootScale.Scale = GroupMotion.scaleTarget(refs.liveDonatorInfoRoot, 0.94)
		setGroupTransparency(refs.liveDonatorInfoRoot, 0.35)
		TweenService:Create(
			rootScale,
			TweenInfo.new(LIVECHAT_POP_IN_DUR, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
		tweenGroupTransparency(
			refs.liveDonatorInfoRoot,
			0,
			TweenInfo.new(LIVECHAT_POP_IN_DUR * 0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		)
	end

	local function popFrame(frame: Frame?, delaySec: number)
		if not frame then
			return
		end

		local scale = getOrCreateLiveChatScale(frame)
		frame.Visible = true
		scale.Scale = GroupMotion.scaleTarget(frame, LIVECHAT_POP_FROM)
		setGroupTransparency(frame, 0.55)

		task.delay(delaySec, function()
			if not frame.Parent then
				return
			end
			local grow = TweenService:Create(
				scale,
				TweenInfo.new(LIVECHAT_POP_IN_DUR, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = GroupMotion.scaleTarget(frame, LIVECHAT_POP_PEAK) }
			)
			tweenGroupTransparency(
				frame,
				0,
				TweenInfo.new(LIVECHAT_POP_IN_DUR * 0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			)
			grow:Play()
			grow.Completed:Connect(function()
				if scale.Parent then
					TweenService:Create(
						scale,
						TweenInfo.new(LIVECHAT_POP_SETTLE_DUR, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
						{ Scale = 1 }
					):Play()
				end
			end)
		end)
	end

	popFrame(refs.liveDonatorInfoCard, LIVECHAT_STAGGER_CARD)
	popFrame(refs.liveDonatorInfoTotal, LIVECHAT_STAGGER_TOTAL)
	showLiveChatFooter(refs, LIVECHAT_STAGGER_FOOTER)
end

local function popOutLiveChatInfo(refs: WorkspaceSurfaceRefs, onDone: (() -> ())?)
	hideLiveChatFooter(refs, true)
	local longestTween: Tween? = nil

	for _, frame in ipairs({ refs.liveDonatorInfoTotal, refs.liveDonatorInfoCard }) do
		if frame and frame.Parent and frame.Visible then
			local scale = getOrCreateLiveChatScale(frame)
			local outInfo = TweenInfo.new(LIVECHAT_POP_OUT_DUR, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			local tweenOut = TweenService:Create(scale, outInfo, { Scale = GroupMotion.scaleTarget(frame, LIVECHAT_POP_OUT_SCALE) })
			tweenGroupTransparency(frame, 1, outInfo)
			longestTween = tweenOut
			tweenOut.Completed:Once(function()
				if frame.Parent then
					frame.Visible = false
					scale.Scale = 1
					setGroupTransparency(frame, 0)
				end
			end)
			tweenOut:Play()
		end
	end

	if refs.liveDonatorInfoRoot and refs.liveDonatorInfoRoot.Parent then
		local rootScale = getOrCreateLiveChatScale(refs.liveDonatorInfoRoot)
		local outInfo = TweenInfo.new(LIVECHAT_POP_OUT_DUR, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		local rootTween = TweenService:Create(rootScale, outInfo, { Scale = GroupMotion.scaleTarget(refs.liveDonatorInfoRoot, LIVECHAT_POP_OUT_SCALE) })
		tweenGroupTransparency(refs.liveDonatorInfoRoot, 1, outInfo)
		longestTween = rootTween
		rootTween.Completed:Once(function()
			if rootScale.Parent then
				rootScale.Scale = 1
			end
			if refs.liveDonatorInfoRoot and refs.liveDonatorInfoRoot.Parent then
				refs.liveDonatorInfoRoot.Visible = false
				setGroupTransparency(refs.liveDonatorInfoRoot, 0)
			end
			settleMessageWrapper(refs, true)
		end)
		rootTween:Play()
	else
		settleMessageWrapper(refs, true)
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

	-- 3A fix: Resolve Roblox identity for BOTH Robux and Bagibagi donations.
	-- Previously non-Robux early-return `payload.saweriaName, ""` discarded
	-- robloxUsername/robloxDisplayName → username always "" → fallback "@donor"
	-- → thumbnail correct (uses robloxUserId directly) but name wrong.
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

	-- Fix: for Bagibagi (non-Robux), if robloxDisplayName exactly matches
	-- robloxUsername (user not yet set custom DisplayName), prefer use saweriaName
	-- as displayName so notification does not look redundant "Username @username".
	if not isRobux and displayName ~= "" and username ~= "" and displayName:lower() == username:lower() then
		displayName = ""
	end

	-- Fallbacks: if no Roblox identity, use saweriaName
	if displayName == "" then
		displayName = if saweriaName ~= "" then saweriaName else "Donor"
	end

	-- For non-Robux (Bagibagi/Saweria): return saweriaName as subtitle (third
	-- return value) so the UI can show both — Roblox display name primary,
	-- external Saweria name secondary. Only return subtitle when saweriaName
	-- differs from displayName (avoid redundant display).
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

	-- 3B fix: include saweriaName subtitle for Bagibagi donations
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
-- Create tween, play, and return — shorthand
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
		log:warn("99-NotificationCenter not found in PlayerGui")
		return nil
	end

	local donationWrapper = rootGui:FindFirstChild("DonationWrapper")
	if not donationWrapper or not donationWrapper:IsA("Frame") then
		log:warn("DonationWrapper not found in 99-NotificationCenter")
		return nil
	end

	local saweriaPanel = donationWrapper:FindFirstChild("SaweriaDonationTemplate")
	if not saweriaPanel or not saweriaPanel:IsA("CanvasGroup") then
		log:warn("SaweriaDonationTemplate not found in DonationWrapper")
		return nil
	end
	local robuxPanel = donationWrapper:FindFirstChild("RobuxDonationTemplate")
	if not robuxPanel or not robuxPanel:IsA("CanvasGroup") then
		log:warn("RobuxDonationTemplate not found in DonationWrapper")
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
	-- 3B fix: resolveDisplayIdentity now returns 3 values (displayName,
	-- username, subtitle). subtitle = saweriaName for Bagibagi donations
	-- so the UI shows both names. Append to displayName when present.
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
		-- 3A fix: username is now resolved from robloxUsername for both
		-- Robux and Bagibagi. DEFAULT_SENDER_USERNAME is only the last fallback.
		local hasUsername = username ~= ""
		refs.senderUsername.Text = if hasUsername
			then "@" .. username
			else DEFAULT_SENDER_USERNAME
		refs.senderUsername.Visible = true
	end
	if refs.donationValue then
		local isRobux = payload.source == "robux"
		refs.donationValue.Text = if isRobux
			then DonationAmountFormat.formatGrouped(payload.amount)
			else DonationAmountFormat.formatCash(payload.amount)
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
	-- RoleBadge: set image per role from overhead cache, hide for Guest/unknown
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
	-- 3B fix: handle subtitle (saweriaName) from resolveDisplayIdentity
	local displayName, username, subtitle = resolveDisplayIdentity(payload)
	local normalizedMessage = normalizeMessage(payload.message)
	local messageText = normalizedMessage or "YOUR DONATION MESSAGE WILL SHOW UP HERE"
	-- 3A fix: username is now resolved from robloxUsername. "@donor"
	-- is only a fallback when there is no Roblox identity at all.
	local usernameText = if username ~= "" then "@" .. username:gsub("^@", "") else "@donor"
	-- Append subtitle to displayName for workspace live board too
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
		refs.liveTotalDonations.Text = DonationAmountFormat.formatGrouped(payload.amount)
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
		-- 3B fix: pass subtitle to buildRunningText
		-- Note: displayName already includes the appended subtitle above, so
		-- for running text we use displayName without appending again.
		-- Build running text from original displayName + subtitle separate.
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
		-- 3B fix: use Roblox displayName + username (consistent with notif card)
		-- Previously used payload.saweriaName directly → always "donor"/"Bagibagi Donor"
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
				'<font color="#FFD700">[DONATION] DONATION RECEIVED</font>  <b>%s</b> <font color="#B4FFB4">%s</font>%s%s',
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
		-- Reliability v4: the notif GUI is missing in this place, so nothing can
		-- be shown — but the server must still hear from us. Without this the
		-- server re-fires 20x and files a DLQ row for EVERY player, and the
		-- owner sees "gagal" with no hint that the GUI itself is broken. Answer
		-- every notif with skipped="no_gui" and fall back to the chat line.
		log:warn("Donation notification GUI not found — replying no_gui, chat fallback only")
		task.spawn(function()
			local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 15)
			if not remotesFolder then
				return
			end
			local remote = remotesFolder:WaitForChild(Config.Donation.REMOTE_NOTIFICATION, 15) :: RemoteEvent?
			local ackRemote = remotesFolder:WaitForChild(Config.Donation.REMOTE_NOTIF_ACK or "DonationNotifAck", 10) :: RemoteEvent?
			if not remote then
				return
			end
			track(remote.OnClientEvent:Connect(function(payload: any)
				if type(payload) ~= "table" then
					return
				end
				local id = tonumber(payload.donationId) or 0
				if id > 0 and ackRemote then
					ackRemote:FireServer({ donationId = id, skipped = "no_gui" })
				end
				if type(payload.saweriaName) == "string" and type(payload.amount) == "number" then
					displayInGeneralChat(payload :: DonationNotifPayload)
				end
			end))
		end)
		return
	end
	-- Capture resting position from Studio before we animate anything
	local restingPosition: UDim2 = guiRefs.panel.Position
	resetGuiState(guiRefs :: GuiRefs, restingPosition)
	local queue: { DonationNotifPayload } = {}
	local isShowingNotif = false
	local isProcessingQueue = false
	-- Reliability v2: the payload currently on screen, so the retry-dedup guard can
	-- recognize a re-fire for the notif being displayed (and skip re-queueing it).
	local showingNotifPayload: DonationNotifPayload? = nil
	local function syncDonationBroadcastLayout()
		local active = isShowingNotif or isProcessingQueue or #queue > 0
		GenericBroadcastLayoutBridge.setDonationNotifActive(active)
	end
	local maxPendingQueue = math.max(1, Config.Donation.NOTIF_MAX_QUEUE)
	local backlogDisplayScale = math.clamp(tonumber(Config.Donation.NOTIF_BACKLOG_DISPLAY_SCALE) or 0.6, 0.25, 1)
	local backlogThreshold = math.max(1, math.floor(maxPendingQueue * 0.5))
	-- Token to cancel background spin & heartbeat loops
	local animToken = 0
	local runningTextToken = 0
	local workspaceRestoreToken = 0
	-- Dedup guard state
	-- 3D fix: dedup key use robloxUserId (not saweriaName) so donor
	-- with different names but same/"donor" not collapsed as duplicate.
	-- Fallback to saweriaName if robloxUserId is nil (edge case).
	local lastEnqueuedDedupKey: string = ""
	local lastEnqueuedAmount: number = 0
	local lastEnqueuedAt: number = 0
	-- Re-resolve refs if stale (handle ResetOnSpawn after respawn)
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
		log:warn("Remotes folder not found")
		return
	end
	local notifRemote = remotes:WaitForChild(Config.Donation.REMOTE_NOTIFICATION, 15) :: RemoteEvent?
	if not notifRemote then
		log:warn("DonationNotification remote not found")
		return
	end
	-- Reliability v2: ack channel. Optional — nil when the server runs an older
	-- engine or the buyer has ReliabilityV2 off; acks are simply skipped.
	-- WaitForChild (short timeout), not FindFirstChild: the first player of a
	-- fresh server can arrive before Main.server has created these remotes, and
	-- a nil here silently disabled acks for that player's whole session.
	local notifAckRemote = remotes:WaitForChild(Config.Donation.REMOTE_NOTIF_ACK or "DonationNotifAck", 10) :: RemoteEvent?
	-- Stage-2 display channel: fired when the notification actually starts
	-- rendering on screen. Optional — nil on older servers; reports are skipped.
	local notifDisplayRemote = remotes:WaitForChild(Config.Donation.REMOTE_NOTIF_DISPLAY or "DonationNotifDisplay", 10) :: RemoteEvent?
	-- BACKGROUND SPIN LOOP
	-- Called after panel finish entrance animation.
	-- Loop runs until token changes (when exit is called).
	local function startBackgroundSpin(refs: GuiRefs, token: number)
		local bg = refs.rotatingBackground
		if not bg then
			return
		end
		-- Wrapper already visible; fade in bg separately
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
				-- Only update if token still valid
				if animToken == token and bg.Parent then
					-- Use modulo so value does not keep accumulating
					currentRotation = (currentRotation + 360) % 36000
					bg.Rotation = currentRotation % 360
				end
			end
		end)
	end
	-- STAGGER CONTENT REVEAL
	-- Content elements appear in sequence after panel settled.
	-- Each element: slide in from the side and fade opacity.
	local function staggerReveal(refs: GuiRefs, token: number)
		task.spawn(function()
			-- Helper: slide+fade for one GuiObject
			local function revealElement(elem: GuiObject?, delaySec: number)
				if not elem or animToken ~= token then
					return
				end
				task.wait(delaySec)
				if animToken ~= token or not elem.Parent then
					return
				end
				-- Save original position
				local origPos = elem.Position
				-- Start slightly to the right + transparent
				elem.Position = origPos + UDim2.fromOffset(STAGGER_SLIDE_DIST, 0)
				-- For TextLabel, fade TextTransparency as well
				local isTextLabel = elem:IsA("TextLabel")
				if isTextLabel then
					(elem :: TextLabel).TextTransparency = 1
				end
				-- Tween position back to the original
				tween(
					elem,
					TweenInfo.new(STAGGER_FADE_DUR, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
					{ Position = origPos }
				)
				-- Fade in opacity (separate so tweens can run together)
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
	-- SHOW NOTIFICATION — full entrance sequence
	local function showNotif(payload: DonationNotifPayload)
		local refs = getGuiRefs()
		local surfaceStates = getWorkspaceSurfaceStates()
		if not refs then
			log:warn("GUI refs invalid when showNotif called")
			return
		end
		isShowingNotif = true
		showingNotifPayload = payload
		syncDonationBroadcastLayout()

		-- Reliability v2 stage 2: the notification is NOW rendering on this
		-- player's screen. Report the display so the dashboard can distinguish
		-- "reached the client" (acked at enqueue) from "actually shown". This
		-- fires once per display, at animation start — not per frame.
		local displayDonationId = tonumber((payload :: any).donationId) or 0
		if displayDonationId > 0 and notifDisplayRemote then
			notifDisplayRemote:FireServer({ donationId = displayDonationId })
		end


		-- World VFX follows notif show cadence (abort previous via WorldEffectFlight).
		local worldEffect = payload.worldEffect
		if type(worldEffect) == "string" and worldEffect ~= "" then
			local prefsOk = DonationExperiencePrefs.shouldShowWorldEffect()
			local gateOk = DonationVfxClientGate.shouldPlayWorldEffect()
			if prefsOk and gateOk then
				local donorName = if type(payload.robloxUsername) == "string" and payload.robloxUsername ~= ""
					then payload.robloxUsername
					elseif type(payload.robloxDisplayName) == "string" and payload.robloxDisplayName ~= ""
					then payload.robloxDisplayName
					else payload.saweriaName
				local recipientName = "Club"
				if type(Config.Branding) == "table" and type(Config.Branding.GAME_NAME) == "string" and Config.Branding.GAME_NAME ~= "" then
					recipientName = Config.Branding.GAME_NAME
				end
				log:debug("World effect dispatch", {
					effect = worldEffect,
					amount = tonumber(payload.amount) or 0,
					donor = donorName,
				})
				WorldEffectDispatch.fire(
					worldEffect,
					donorName,
					recipientName,
					tonumber(payload.amount) or 0,
					payload.robloxUserId
				)
			else
				log:debug("World effect skipped", {
					effect = worldEffect,
					prefsOk = prefsOk,
					gateOk = gateOk,
					hideWorld = not prefsOk,
					vfxScale = DonationVfxClientGate.getVfxScale(),
				})
			end
		else
			log:debug("World effect none on payload", {
				amount = tonumber(payload.amount) or 0,
				worldEffect = worldEffect,
			})
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
		-- Prepare initial entrance animation state
		-- Panel: above resting, small, fully transparent
		refs.panel.Position = restingPosition + UDim2.fromOffset(0, ENTER_SLIDE_OFFSET)
		-- ADR 0005: panel is a CanvasGroup — scale keyframes collapse to 1 (size-stable);
		-- slide + GroupTransparency carry the entrance/exit instead.
		refs.panelScale.Scale = GroupMotion.scaleTarget(refs.panel, ENTER_SCALE_FROM)
		refs.panel.GroupTransparency = 1
		refs.panel.Visible = true
		refs.donationWrapper.Visible = true
		setVisible(refs.backgroundWrapper, true) -- wrapper visible but bg still transparent
		-- Phase 1: slide in + pop scale (spring overshoot)
		-- Panel slides down to restingPos + slight overshoot
		local targetPhase1 = restingPosition + UDim2.fromOffset(0, ENTER_OVERSHOOT_BELOW)
		-- Play position, scale, and fade-in together
		tween(refs.panel, TweenInfo.new(ENTER_PHASE1_DUR, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = targetPhase1,
			GroupTransparency = 0,
		})
		tweenWait(refs.panelScale, TweenInfo.new(ENTER_PHASE1_DUR, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = GroupMotion.scaleTarget(refs.panel, ENTER_SCALE_PEAK),
		})
		-- Phase 2: settle to resting position
		tween(refs.panel, TweenInfo.new(ENTER_PHASE2_DUR, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = restingPosition,
		})
		tweenWait(refs.panelScale, TweenInfo.new(ENTER_PHASE2_DUR, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1,
		})
		-- Panel settled; start background effects and content reveal
		startBackgroundSpin(refs, token)
		staggerReveal(refs, token)
		-- CountDownBar: tween width 100% -> 0% for display duration (per-tier).
		local notifDuration = resolveNotifDuration(payload)
		-- Drain faster when more notifs are waiting (no drops).
		if #queue >= backlogThreshold then
			notifDuration = notifDuration * backlogDisplayScale
		end
		-- Reliability v2 (b): hard backpressure floor. Beyond half the soft queue cap
		-- (default >50 queued) we clamp every notification to a short floor so a deep
		-- burst drains in bounded time instead of piling up for many minutes. The
		-- notification still shows — just briefly — so nothing is ever dropped.
		local hardFloor = tonumber(Config.Donation.NOTIF_BACKLOG_HARD_FLOOR_SECS) or 2
		if #queue > backlogThreshold then
			notifDuration = math.min(notifDuration, hardFloor)
		end
		if refs.countDownBar then
			refs.countDownBar.Size = UDim2.new(1, 0, refs.countDownBar.Size.Y.Scale, refs.countDownBar.Size.Y.Offset)
			tween(
				refs.countDownBar,
				TweenInfo.new(notifDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
				{ Size = UDim2.new(0, 0, refs.countDownBar.Size.Y.Scale, refs.countDownBar.Size.Y.Offset) }
			)
		end
		-- Wait for display duration per tier.
		task.wait(notifDuration)
		-- EXIT SEQUENCE
		-- Stop all loops by invalidating token
		animToken += 1
		-- Fade out background first
		if refs.rotatingBackground and refs.rotatingBackground.Parent then
			tween(
				refs.rotatingBackground,
				TweenInfo.new(BG_FADE_OUT_DUR, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ ImageTransparency = 1 }
			)
		end
		-- Anticipation: slight compress first (like a "breath" before jump)
		tweenWait(
			refs.panelScale,
			TweenInfo.new(EXIT_ANTICIPATION_DUR, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = GroupMotion.scaleTarget(refs.panel, EXIT_ANTICIPATION_SCALE) }
		)
		-- Launch upward: panel flies up + shrinks + fades
		local exitTarget = restingPosition + UDim2.fromOffset(0, EXIT_SLIDE_ABOVE)
		tween(
			refs.panelScale,
			TweenInfo.new(EXIT_LAUNCH_DUR, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
			{ Scale = GroupMotion.scaleTarget(refs.panel, ENTER_SCALE_FROM) }
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
		showingNotifPayload = nil
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
				showingNotifPayload = nil
				syncDonationBroadcastLayout()
				animToken += 1 -- invalidate all loop
				local refs = guiRefs
				if refs then
					pcall(setDonationHudHidden, playerGui, false)
					pcall(resetGuiState, refs, restingPosition)
					pcall(clearGuiContent, refs)
				end
				log:warn("Donation notification failed to process", {
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
			-- Reliability v4: the player muted donation announcements. Tell the
			-- server we RECEIVED it so it stops retrying and the ledger records
			-- 'muted' — not a lost notification. Before this, every muted player
			-- produced 20 useless re-fires and one DLQ row per donation.
			local mutedId = tonumber((payload :: any).donationId) or 0
			if mutedId > 0 and notifAckRemote then
				notifAckRemote:FireServer({ donationId = mutedId, skipped = "muted" })
			end
			return
		end
		local notifPayload = payload :: DonationNotifPayload
		displayInGeneralChat(notifPayload)
		-- Reliability v2: idempotent retry guard. The server re-fires a notification
		-- until the client acks it. If this donationId is already queued (or currently
		-- showing), a retry must be a no-op — otherwise a burst would enqueue the same
		-- donation many times and flood the queue. This check runs BEFORE the legacy
		-- burst dedup below.
		local incomingDonationId = tonumber((notifPayload :: any).donationId) or 0
		if incomingDonationId > 0 then
			local showingId = if showingNotifPayload ~= nil
				then tonumber((showingNotifPayload :: any).donationId)
				else nil
			if showingId ~= nil and showingId == incomingDonationId then
				log:debug("Donation notification retry deduped (currently showing)", { donationId = incomingDonationId })
				return
			end
			for _, queued in ipairs(queue) do
				if tonumber((queued :: any).donationId) == incomingDonationId then
					log:debug("Donation notification retry deduped (already queued)", { donationId = incomingDonationId })
					return
				end
			end
		end
		-- Dedup guard: filter identical payloads from burst polling (within DEDUP_WINDOW_SECS)
		-- 3D fix: dedup key use robloxUserId (not saweriaName) so donor
		-- with different names but same/"donor" not collapsed as duplicate.
		-- Fallback to saweriaName if robloxUserId is nil.
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
		-- Reliability v2: NO EVICTION. A donor paid real money — their notification is
		-- never dropped to make room for another. The queue is a soft cap: beyond
		-- maxPendingQueue we still enqueue and rely on backlog display scaling (see
		-- resolveNotifDuration + NOTIF_BACKLOG_DISPLAY_SCALE) to drain faster. This
		-- replaces the old lowest-amount eviction that silently discarded small
		-- donations under burst — a direct violation of the no-silent-loss guarantee.
		table.insert(queue, notifPayload)
		syncDonationBroadcastLayout()
		-- Reliability v2: ack DELIVERY (not display). The notification is now safely
		-- in the client queue and WILL be shown — that is the delivery guarantee the
		-- server ledger tracks. Display timing depends on queue depth (a burst drains
		-- over minutes), which is expected behavior, not a failure — so we ack here,
		-- at enqueue, not after the animation. The server dedups retries by donationId,
		-- so a late duplicate ack is harmless.
		local deliveryId = tonumber((notifPayload :: any).donationId) or 0
		if deliveryId > 0 and notifAckRemote then
			notifAckRemote:FireServer({ donationId = deliveryId })
		end
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
