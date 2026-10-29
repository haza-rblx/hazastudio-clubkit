--!strict
-- PATH: StarterPlayerScripts/Client/Controllers/Client_CoupleController.lua (ModuleScript)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TextChatService = game:GetService("TextChatService")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local InstanceState = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.InstanceState)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
local UIMotion = require(script.Parent.Parent.Utils.UIMotion)
local ChatTagStore = require(script.Parent.Parent.Services.ChatTagStore)
local log = Logger.new("Client.CoupleController")

local _connections: { RBXScriptConnection } = {}
-- Looping motion (UIMotion.pulse) hands back a stop function; they are stopped here so a
-- destroyed controller never leaves a tween breathing on a surviving instance.
local _cleanups: { () -> () } = {}

local function track(conn: RBXScriptConnection): RBXScriptConnection
	table.insert(_connections, conn)
	return conn
end

local function destroy()
	for _, stop in ipairs(_cleanups) do
		stop()
	end
	table.clear(_cleanups)
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)
end

-- Set once init has built the panel (avatar context menu entry points).
local _proposeTo: ((number) -> ())? = nil
local _hasPartner: (() -> boolean)? = nil

local function coupleTagText(partnerDisplayName: string): string
	local emoji = tostring(Config.Chat.COUPLE_TAG_EMOJI or "💕")
	return emoji .. " " .. partnerDisplayName
end

local function applyLocalCoupleChatTag(userId: number?, partnerDisplayName: string?)
	if type(userId) ~= "number" then
		return
	end
	if type(partnerDisplayName) == "string" and partnerDisplayName ~= "" then
		ChatTagStore.setCoupleTag(userId, coupleTagText(partnerDisplayName))
	else
		ChatTagStore.setCoupleTag(userId, nil)
	end
end

local localPlayer = Players.LocalPlayer
local SEARCH_HIGHLIGHT_COLOR = "#FF7EB6"
local EMPTY_STATE_DEFAULT_TITLE = "No one is on the list yet"
local EMPTY_STATE_DEFAULT_SUBTITLE = "When someone catches the moment, they'll appear here."
local EMPTY_STATE_SEARCH_TITLE = "No match this time"
local EMPTY_STATE_SEARCH_SUBTITLE = "Try another display name or username."
type PlayerListEntry = {
	button: TextButton,
	connection: RBXScriptConnection?,
}
local function escapeRichText(text: string): string
	return text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end
local function animateSlidingPill(backgroundPill: GuiObject, selectedButton: TextButton, allButtons: {TextButton})
	if not backgroundPill then
		return
	end
	
	-- Find selected button index
	local selectedIndex = 0
	local totalButtons = #allButtons
	for i, btn in ipairs(allButtons) do
		if btn == selectedButton then
			selectedIndex = i
			break
		end
	end
	
	if selectedIndex == 0 or totalButtons == 0 then
		return
	end
	
	-- Calculate normalized position (0 for first, 0.5 for middle, 1 for last)
	local normalizedPos = if totalButtons > 1 then (selectedIndex - 1) / (totalButtons - 1) else 0.5
	
	-- Target position and anchor point
	local targetAnchorPoint = Vector2.new(normalizedPos, 0.5)
	local targetPosition = UDim2.new(normalizedPos, 0, 0.5, 0)
	
	-- Couple-status echoes re-assert the active tab; the pill is already there, so do not replay.
	if backgroundPill.AnchorPoint == targetAnchorPoint and backgroundPill.Position == targetPosition then
		return
	end

	-- Set anchor point immediately, animate position with smooth easing
	backgroundPill.AnchorPoint = targetAnchorPoint
	-- Layout safety (ADR 0011): the pill is an absolutely positioned overlay sitting behind the
	-- laid-out tab buttons, so a Position tween is only meaningful while its parent has no layout.
	-- If a buyer design ever parents it under one, snap instead of tweening against that layout.
	local pillParent = backgroundPill.Parent
	if pillParent == nil or pillParent:FindFirstChildWhichIsA("UIGridStyleLayout") then
		backgroundPill.Position = targetPosition
		return
	end
	UIMotion.tween(backgroundPill, 0.32, { Position = targetPosition }, Enum.EasingStyle.Quint)
end
local function highlightFirstMatch(text: string, query: string): string
	local safeText = escapeRichText(text)
	if query == "" then
		return safeText
	end
	local lowerText = string.lower(text)
	local lowerQuery = string.lower(query)
	local startIndex = string.find(lowerText, lowerQuery, 1, true)
	if not startIndex then
		return safeText
	end
	local endIndex = startIndex + #query - 1
	local beforeText = escapeRichText(string.sub(text, 1, startIndex - 1))
	local matchText = escapeRichText(string.sub(text, startIndex, endIndex))
	local afterText = escapeRichText(string.sub(text, endIndex + 1))
	return string.format(
		'%s<font color="%s"><b>%s</b></font>%s',
		beforeText,
		SEARCH_HIGHLIGHT_COLOR,
		matchText,
		afterText
	)
end
local function setNotFoundCardText(card: GuiObject, titleText: string, subtitleText: string): ()
	local info = card:FindFirstChild("PlayerInformation") :: Frame?
	if not info then
		return
	end
	local titleLabel = info:FindFirstChild("1-Title") :: TextLabel?
	local subtitleLabel = info:FindFirstChild("2-SubTitle") :: TextLabel?
	if titleLabel then
		titleLabel.RichText = false
		titleLabel.Text = titleText
	end
	if subtitleLabel then
		subtitleLabel.RichText = false
		subtitleLabel.Text = subtitleText
	end
end
local function init(deps: { icon: any? }?): ()
	-- ============================================================
	-- Tunggu Remotes
	-- ============================================================
	-- Bounded so a missing/disabled Couple feature on the server soft-disables
	-- this controller instead of hanging this boot task forever.
	local bootTimeout = Config.Loading.BOOTSTRAP_WAIT_TIMEOUT
	local Remotes = ReplicatedStorage:WaitForChild("Remotes", bootTimeout)
	local RemoteSendRequest = Remotes and Remotes:WaitForChild("CoupleSendRequest", bootTimeout)
	local RemoteRespond = Remotes and Remotes:WaitForChild("CoupleRespond", bootTimeout)
	local RemoteBreakup = Remotes and Remotes:WaitForChild("CoupleBreakup", bootTimeout)
	local RemoteOpenPanel = Remotes and Remotes:WaitForChild("CoupleOpenPanel", bootTimeout)
	local RemoteNotifyRequest = Remotes and Remotes:WaitForChild("CoupleNotifyRequest", bootTimeout)
	local RemoteNotifyResult = Remotes and Remotes:WaitForChild("CoupleNotifyResult", bootTimeout)
	local RemoteAnnounce = Remotes and Remotes:WaitForChild("CoupleAnnounce", bootTimeout)
	local RemotePanelData = Remotes and Remotes:WaitForChild("CouplePanelData", bootTimeout)
	if
		not (Remotes and Remotes:IsA("Folder"))
		or not (RemoteSendRequest and RemoteSendRequest:IsA("RemoteEvent"))
		or not (RemoteRespond and RemoteRespond:IsA("RemoteEvent"))
		or not (RemoteBreakup and RemoteBreakup:IsA("RemoteEvent"))
		or not (RemoteOpenPanel and RemoteOpenPanel:IsA("RemoteEvent"))
		or not (RemoteNotifyRequest and RemoteNotifyRequest:IsA("RemoteEvent"))
		or not (RemoteNotifyResult and RemoteNotifyResult:IsA("RemoteEvent"))
		or not (RemoteAnnounce and RemoteAnnounce:IsA("RemoteEvent"))
		or not (RemotePanelData and RemotePanelData:IsA("RemoteEvent"))
	then
		log:warn("Couple remotes not ready within timeout, CoupleController not started")
		return
	end
	-- Re-bind with explicit casts (matches coupleGuiSafe below) so the rest of
	-- this function doesn't rely on flow-narrowing across 700+ lines.
	local Remotes = Remotes :: Folder
	local RemoteSendRequest = RemoteSendRequest :: RemoteEvent
	local RemoteRespond = RemoteRespond :: RemoteEvent
	local RemoteBreakup = RemoteBreakup :: RemoteEvent
	local RemoteOpenPanel = RemoteOpenPanel :: RemoteEvent
	local RemoteNotifyRequest = RemoteNotifyRequest :: RemoteEvent
	local RemoteNotifyResult = RemoteNotifyResult :: RemoteEvent
	local RemoteAnnounce = RemoteAnnounce :: RemoteEvent
	local RemotePanelData = RemotePanelData :: RemoteEvent
	-- ============================================================
	-- Referensi GUI
	-- ============================================================
	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local coupleGui = playerGui:WaitForChild("01-CoupleSystemGUI", 30) :: ScreenGui?
	if not coupleGui then
		log:warn("01-CoupleSystemGUI not found, CoupleController not started")
		return
	end
	local coupleGuiSafe = coupleGui :: ScreenGui
	local mainWrapper = coupleGuiSafe:WaitForChild("MainWrapper") :: Frame
	local notifWrapper = coupleGuiSafe:WaitForChild("NotificationWrapper") :: Frame
	local overlayFrame = coupleGuiSafe:FindFirstChild("OverlayFrame") :: Frame?
	local headerWrapper = mainWrapper:WaitForChild("01-HeaderWrapper") :: Frame
	local contentWrapper = mainWrapper:WaitForChild("02-MainContentWrapper") :: Frame
	local requestContent = contentWrapper:WaitForChild("1-RequestContent") :: Frame
	
	-- Flexible breakup content: handle "2-BreakupContent" OR split frames
	local breakupSingle = contentWrapper:FindFirstChild("2-BreakupContentSingle") :: Frame?
	local breakupTaken = contentWrapper:FindFirstChild("2-BreakupContentTaken") :: Frame?
	if not breakupSingle and not breakupTaken then
		local breakupUnified = contentWrapper:FindFirstChild("2-BreakupContent") :: Frame?
		if breakupUnified then
			breakupTaken = breakupUnified
			breakupSingle = breakupUnified
		else
			log:error("2-BreakupContent* frames not found")
			return
		end
	end
	
	local selectPlayerFrame = contentWrapper:WaitForChild("3-SelectPlayerFrame") :: Frame
	
	-- Flexible selector: handle nested 2-SliderSelector
	local selectorOuter = headerWrapper:WaitForChild("2-SliderSelector") :: Frame
	local selectorInner = selectorOuter:FindFirstChild("2-SliderSelector") :: Frame?
	local selectorContainer = if selectorInner and selectorInner:IsA("Frame")
		then selectorInner else selectorOuter
	
	-- 3-pass button discovery (name → text → position)
	local requestButton: TextButton? = nil
	local breakUpButton: TextButton? = nil
	
	-- Pass 1: exact name
	requestButton = selectorContainer:FindFirstChild("Option1") :: TextButton?
	breakUpButton = selectorContainer:FindFirstChild("Option2") :: TextButton?
	
	-- Pass 2: text content
	if not requestButton or not breakUpButton then
		for _, child in ipairs(selectorContainer:GetChildren()) do
			if child:IsA("TextButton") then
				local btn = child :: TextButton
				local text = string.lower(btn.Text)
				if text:find("request") and not requestButton then
					requestButton = btn
				elseif (text:find("break") or text:find("up")) and not breakUpButton then
					breakUpButton = btn
				end
			end
		end
	end
	
	-- Pass 3: position (first two TextButtons)
	if not requestButton or not breakUpButton then
		local buttons: { TextButton } = {}
		for _, child in ipairs(selectorContainer:GetChildren()) do
			if child:IsA("TextButton") then
				table.insert(buttons, child :: TextButton)
			end
		end
		if #buttons >= 2 then
			requestButton = requestButton or buttons[1]
			breakUpButton = breakUpButton or buttons[2]
		end
	end
	
	if not requestButton or not breakUpButton then
		log:error("Request/BreakUp buttons not found di 2-SliderSelector")
		return
	end
	
	-- Capture BackgroundPill for animation (always in OUTER selector)
	local backgroundPill = selectorOuter:FindFirstChild("BackgroundPill") :: GuiObject?
	local tabButtons = {requestButton, breakUpButton}
	
	-- Set button text
	local requestLabel = requestButton:FindFirstChildWhichIsA("TextLabel", true) or requestButton
	local breakupLabel = breakUpButton:FindFirstChildWhichIsA("TextLabel", true) or breakUpButton
	if requestLabel:IsA("TextButton") or requestLabel:IsA("TextLabel") then
		(requestLabel :: TextLabel).Text = "Request"
	end
	if breakupLabel:IsA("TextButton") or breakupLabel:IsA("TextLabel") then
		(breakupLabel :: TextLabel).Text = "Break Up"
	end
	local closeModalButton = headerWrapper:FindFirstChild("3-CloseModalButton")
		or headerWrapper:FindFirstChild("03-CloseModalButton")
		or headerWrapper:FindFirstChild("CloseModalButton")
	if not closeModalButton or not closeModalButton:IsA("TextButton") then
		log:warn("Couple GUI close button not found — panel still runs without modal close button")
		closeModalButton = nil
	end
	local searchBox = selectPlayerFrame:FindFirstChild("01-SearchBox") :: TextBox?
	local scrollableList = selectPlayerFrame:WaitForChild("ScrollablePlayerList") :: ScrollingFrame
	local playerSelectorCard = scrollableList:WaitForChild("PlayerSelectorCard") :: TextButton
	local notFoundCard = scrollableList:FindFirstChild("NotFoundCard") :: TextButton?
	local playerCardDefaultTransparency = playerSelectorCard.BackgroundTransparency
	local playerCardSelectedTransparency = math.min(playerCardDefaultTransparency + 0.12, 0.85)
	-- ============================================================
	-- RequestContent
	-- ============================================================
	local inputWrapper = requestContent:WaitForChild("InputWrapper") :: Frame
	local sendButton = inputWrapper:WaitForChild("TextButton") :: TextButton
	local usernameBox = inputWrapper:WaitForChild("TextBox") :: TextBox
	local profilPicture = requestContent:WaitForChild("JumbotronTextandImage"):WaitForChild("ProfilPicture") :: Frame
	local requestPlayerPfp = profilPicture:FindFirstChild("PlayerDisplayName") :: ImageLabel?
	local targetPfp = profilPicture:FindFirstChild("CoupleDisplayName") :: ImageLabel?
	-- ============================================================
	-- BreakupContentSingle (not coupled yet)
	-- ============================================================
	local breakupSingleJumbotron = breakupSingle:FindFirstChild("JumbotronTextandImage") :: Frame?
	local breakupSingleProfil = breakupSingleJumbotron
		and breakupSingleJumbotron:FindFirstChild("ProfilPicture") :: Frame?
	local breakupSinglePlayerPfp = breakupSingleProfil
		and breakupSingleProfil:FindFirstChild("PlayerDisplayName") :: ImageLabel?
	-- ============================================================
	-- BreakupContentTaken (already coupled)
	-- ============================================================
	local breakupInputArea = breakupTaken:WaitForChild("InputArea") :: Frame
	local currentCoupleLbl = breakupInputArea:WaitForChild("1-CurrentCouple"):WaitForChild("TextLabel") :: TextLabel
	local breakupBtn = breakupInputArea:WaitForChild("2-BrokeupButton") :: TextButton
	local breakupJumbotron = breakupTaken:FindFirstChild("JumbotronTextandImage") :: Frame?
	local breakupProfilPic = breakupJumbotron and breakupJumbotron:FindFirstChild("ProfilPicture") :: Frame?
	local breakupPartnerPfp = breakupProfilPic and breakupProfilPic:FindFirstChild("CoupleDisplayName") :: ImageLabel?
	local breakupPlayerPfp = breakupProfilPic and breakupProfilPic:FindFirstChild("PlayerDisplayName") :: ImageLabel?
	-- ============================================================
	-- Notification frames
	-- ============================================================
	local notifMain = notifWrapper:WaitForChild("02-MainContentWrapper") :: Frame
	local confirmFrame = notifMain:WaitForChild("Confirmation") :: Frame
	local rejectedFrame = notifMain:WaitForChild("Rejected") :: Frame
	local waitingFrame = notifMain:WaitForChild("Waiting") :: Frame
	-- Confirmation
	local confirmJumbotron = confirmFrame:FindFirstChild("JumbotronTextandImage") :: Frame?
	local confirmPhotoWrapper = confirmJumbotron and confirmJumbotron:FindFirstChild("PhotoWrapper") :: Frame?
	local confirmSenderPfp = confirmPhotoWrapper
		and confirmPhotoWrapper:FindFirstChild("CoupleDisplayProfilePicture") :: ImageLabel?
	local confirmLocalPfp = confirmPhotoWrapper
		and confirmPhotoWrapper:FindFirstChild("PlayerDisplayProfilePicture") :: ImageLabel?
	local confirmTextLabel = confirmJumbotron and confirmJumbotron:FindFirstChild("TextLabel") :: TextLabel?
	-- Waiting
	local waitingJumbotron = waitingFrame:FindFirstChild("JumbotronTextandImage") :: Frame?
	local waitingPhotoWrapper = waitingJumbotron and waitingJumbotron:FindFirstChild("PhotoWrapper") :: Frame?
	local waitingTargetPfp = waitingPhotoWrapper
		and waitingPhotoWrapper:FindFirstChild("CoupleDisplayProfilePicture") :: ImageLabel?
	local waitingLocalPfp = waitingPhotoWrapper
		and waitingPhotoWrapper:FindFirstChild("PlayerDisplayProfilePicture") :: ImageLabel?
	local waitingTextLabel = waitingJumbotron and waitingJumbotron:FindFirstChild("TextLabel") :: TextLabel?
	local waitingInputArea = waitingFrame:FindFirstChild("InputArea") :: Frame?
	local waitingCloseBtn = waitingInputArea and waitingInputArea:FindFirstChild("CloseButton") :: TextButton?
	-- Rejected
	local rejectedJumbotron = rejectedFrame:FindFirstChild("JumbotronTextandImage") :: Frame?
	local rejectedProfileWrapper = rejectedJumbotron and rejectedJumbotron:FindFirstChild("ProfileWrapper") :: Frame?
	local rejectedPartnerPfp = rejectedProfileWrapper
		and rejectedProfileWrapper:FindFirstChild("CoupleDisplayProfilePicture") :: ImageLabel?
	local rejectedLocalPfp = rejectedProfileWrapper
		and rejectedProfileWrapper:FindFirstChild("PlayerDisplayProfilePicture") :: ImageLabel?
	local rejectedTextLabel = rejectedJumbotron and rejectedJumbotron:FindFirstChild("TextLabel") :: TextLabel?
	-- ============================================================
	-- State lokal
	-- ============================================================
	local selectedUserId: number? = nil
	local selectedDisplayName: string = ""
	local _currentRequestId: string? = nil
	local isCoupled = false
	local partnerName = ""
	local partnerId: number? = nil
	local panelOpen = false
	-- The panel can be closed by its own X (and by the breakup flow), not only by the topbar icon,
	-- so those paths must deselect the icon too: the icon's deselected handler is what tells
	-- MobilePanelManager to give the other GUIs back (2026-10-12 phone stale-UI bug).
	local topbarIcon = deps and deps.icon or nil
	local allPlayers: { { userId: number, displayName: string, username: string } } = {}
	local playerCardPool = {} :: { PlayerListEntry }
	local ringHandle: AnimationHelper.ProgressRingHandle? = nil
	local confirmAcceptConn: RBXScriptConnection? = nil
	local confirmRejectConn: RBXScriptConnection? = nil
	local anim = AnimationHelper.new()
	-- ============================================================
	-- Helpers - motion (ADR 0011)
	-- ============================================================
	-- Designed transparency of everything this panel fades, captured once before the first fade
	-- touches it. Strong keys on purpose (ADR 0011 addendum, 2026-09-17): a weak entry is dropped
	-- while the element is alive, and the next capture would then record a mid-cascade transparency
	-- as the design. Cards are pooled, never destroyed, so nothing accumulates here.
	local fadeBases = {} :: { [GuiObject]: number }
	-- Press/hover is bound once per instance; bindConfirmButtons and the pooled card list both
	-- re-enter with the same buttons. One STRONG record per button, reclaimed on its `Destroying`
	-- (InstanceState) — a weak key dropped the guard while the card lived and let a second bind through.
	local motionBound = InstanceState.new(function(): boolean
		return true
	end)
	-- Where each card's highlight is heading, so a running tween is not restarted by an echo.
	-- Weak on purpose: a pure cache. A lost entry only restarts the highlight tween toward the same
	-- target (UIMotion.tween replaces the channel), never a wrong value.
	local cardTargetTransparency = (setmetatable({}, { __mode = "k" }) :: any) :: { [Instance]: number }
	local activeTabPage: GuiObject? = nil
	local lastListSignature: string? = nil
	local waitingPulseStop: (() -> ())? = nil
	local function trackAll(conns: { RBXScriptConnection }): ()
		for _, conn in ipairs(conns) do
			track(conn)
		end
	end
	-- Press squash + hover lift on any kit button, with the connections owned by this controller.
	local function bindButtonMotion(button: Instance?): ()
		if not button or not button:IsA("GuiObject") or motionBound.get(button) then
			return
		end
		motionBound.of(button)
		trackAll(UIMotion.bindPress(button :: GuiObject))
		trackAll(UIMotion.bindHover(button :: GuiObject))
	end
	-- Text/images UIMotion can fade; Frames and layouts have no transparency channel.
	local function fadeTargetsOf(root: Instance): { GuiObject }
		local targets: { GuiObject } = {}
		for _, desc in ipairs(root:GetDescendants()) do
			if desc:IsA("TextLabel") or desc:IsA("ImageLabel") then
				table.insert(targets, desc :: GuiObject)
			end
		end
		return targets
	end
	local function captureOnce(elements: { GuiObject }): ()
		local pending: { GuiObject } = {}
		for _, element in ipairs(elements) do
			if fadeBases[element] == nil then
				table.insert(pending, element)
			end
		end
		if #pending > 0 then
			UIMotion.captureBases(pending, fadeBases)
		end
	end
	-- Fades a group's text/images in. `delay` lets the content land after the dialog has finished
	-- travelling (AnimationHelper still owns the arrival itself).
	local function fadeInGroup(root: Instance, delay: number?): ()
		local targets = fadeTargetsOf(root)
		captureOnce(targets)
		UIMotion.fadeIn(targets, fadeBases, delay)
	end
	local function setCurrentCoupleText(text: string): ()
		-- The server echoes full couple state on every sync; only a real change re-fades.
		if currentCoupleLbl.Text == text then
			return
		end
		currentCoupleLbl.Text = text
		captureOnce({ currentCoupleLbl :: GuiObject })
		UIMotion.fadeIn({ currentCoupleLbl :: GuiObject }, fadeBases)
	end
	-- ============================================================
	-- Helpers - foto
	-- ============================================================
	local function getThumbnail(userId: number): string
		return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=100&h=100", userId)
	end
	local function setThumbnailAsync(img: ImageLabel, userId: number): ()
		img.Image = getThumbnail(userId)
	end
	local function refreshLocalPlayerPhotos(): ()
		local uid = localPlayer.UserId
		if requestPlayerPfp then
			setThumbnailAsync(requestPlayerPfp, uid)
		end
		if breakupPlayerPfp then
			setThumbnailAsync(breakupPlayerPfp, uid)
		end
		if breakupSinglePlayerPfp then
			setThumbnailAsync(breakupSinglePlayerPfp, uid)
		end
		if waitingLocalPfp then
			setThumbnailAsync(waitingLocalPfp, uid)
		end
		if confirmLocalPfp then
			setThumbnailAsync(confirmLocalPfp, uid)
		end
		if rejectedLocalPfp then
			setThumbnailAsync(rejectedLocalPfp, uid)
		end
	end
	local function refreshPartnerPhoto(): ()
		if breakupPartnerPfp and partnerId then
			setThumbnailAsync(breakupPartnerPfp, partnerId)
		end
	end
	-- ============================================================
	-- Helpers - panel & notif
	-- ============================================================
	-- Forward declaration: setTab defined after showPanel,
	-- but showPanel calls it. Without this, Lua lookup hits global (nil).
	local setTab: (boolean) -> ()
	local function setOverlayVisible(visible: boolean): ()
		if not overlayFrame then
			return
		end
		overlayFrame.Visible = visible
		-- This backdrop is only visual. Keeping it Active/Interactable can swallow
		-- mobile taps before they reach the accept/reject buttons.
		overlayFrame.Active = false
		pcall(function()
			overlayFrame.Interactable = false
		end)
	end

	setOverlayVisible(false)

	local function showPanel(visible: boolean): ()
		panelOpen = visible
		setOverlayVisible(visible or notifWrapper.Visible)
		if visible then
			anim:presentCenterPanel(mainWrapper, function()
				-- Apply tab after panel is visible
				setTab(not isCoupled)
			end, {
				enableBlur = true,
				blurName = "CoupleUIBlur",
				enableZoom = true
			})
			RemoteOpenPanel:FireServer({
				requestId = HttpService:GenerateGUID(false),
			})
		else
			anim:dismissCenterPanel(mainWrapper, nil, {
				enableBlur = true,
				blurName = "CoupleUIBlur",
				enableZoom = true
			})
			task.defer(function()
				setOverlayVisible(notifWrapper.Visible)
			end)
			-- Closed: the next open is a real arrival again, so let the tab page and the player
			-- list replay their entrance.
			activeTabPage = nil
			lastListSignature = nil
		end
	end
	-- Every close that does not come from the icon itself goes through here: deselect is what
	-- tells MobilePanelManager to stop hiding every other GUI, and its deselected handler runs
	-- showPanel(false) — so this is the single dismiss, never two.
	local function requestClose(): ()
		if topbarIcon ~= nil and type(topbarIcon.deselect) == "function" and topbarIcon.isSelected == true then
			pcall(function()
				topbarIcon:deselect()
			end)
			return
		end
		showPanel(false)
	end
	local function stopRing(): ()
		if ringHandle then
			ringHandle.stop()
			ringHandle = nil
		end
	end
	local function stopWaitingPulse(): ()
		if waitingPulseStop then
			waitingPulseStop()
			waitingPulseStop = nil
		end
	end
	table.insert(_cleanups, stopWaitingPulse)
	local function showNotif(frame: Frame): ()
		setOverlayVisible(true)
		notifWrapper.Visible = true
		confirmFrame.Visible = frame == confirmFrame
		rejectedFrame.Visible = frame == rejectedFrame
		waitingFrame.Visible = frame == waitingFrame
		stopWaitingPulse()
		if frame == confirmFrame then
			anim:swingIn(confirmFrame, notifWrapper, nil)
		elseif frame == waitingFrame then
			anim:scalePop(waitingFrame, nil)
			stopRing()
		elseif frame == rejectedFrame then
			anim:scalePop(rejectedFrame, nil)
		end
		-- The dialog arrives first (swing/pop above, AnimationHelper's signature moment); its text
		-- and avatars fade up as it lands.
		fadeInGroup(frame, 0.12)
		if frame == confirmFrame then
			UIMotion.pop(confirmSenderPfp, 1.18)
			UIMotion.pop(confirmLocalPfp, 1.18)
		elseif frame == waitingFrame then
			UIMotion.pop(waitingTargetPfp, 1.15)
			if waitingTargetPfp then
				-- A slow wobble on the target's avatar for as long as we are waiting. Rotation is
				-- layout-neutral, so this is safe wherever the design puts the photo.
				waitingPulseStop = UIMotion.pulse(waitingTargetPfp, "Rotation", 4, 1.4)
			end
		elseif frame == rejectedFrame then
			UIMotion.wiggle(rejectedPartnerPfp, 10)
		end
	end
	local disconnectConfirmButtons: () -> ()
	local function hideNotif(): ()
		stopRing()
		stopWaitingPulse()
		disconnectConfirmButtons()
		if rejectedFrame.Visible then
			anim:scatterFragments(rejectedFrame, notifWrapper, function()
				notifWrapper.Visible = false
				confirmFrame.Visible = false
				rejectedFrame.Visible = false
				waitingFrame.Visible = false
				setOverlayVisible(panelOpen)
			end)
			return
		end
		notifWrapper.Visible = false
		confirmFrame.Visible = false
		rejectedFrame.Visible = false
		waitingFrame.Visible = false
		setOverlayVisible(panelOpen)
	end

	disconnectConfirmButtons = function(): ()
		if confirmAcceptConn then
			confirmAcceptConn:Disconnect()
			confirmAcceptConn = nil
		end
		if confirmRejectConn then
			confirmRejectConn:Disconnect()
			confirmRejectConn = nil
		end
	end

	local function bindConfirmButtons(requestId: string): ()
		disconnectConfirmButtons()
		local inputArea = confirmFrame:FindFirstChild("InputArea") :: Frame?
		if not inputArea then
			return
		end
		local acceptBtn = inputArea:FindFirstChild("AcceptCoupleButton") :: TextButton?
		local rejectBtn = inputArea:FindFirstChild("RejectButton") :: TextButton?
		if acceptBtn then
			acceptBtn.Active = true
			acceptBtn.Selectable = true
			bindButtonMotion(acceptBtn)
			local acceptIcon = UIMotion.scaleTargetOf(acceptBtn)
			confirmAcceptConn = acceptBtn.Activated:Connect(function()
				UIMotion.pop(acceptIcon, 1.3)
				disconnectConfirmButtons()
				RemoteRespond:FireServer({ requestId = requestId, accepted = true })
				hideNotif()
			end)
		end
		if rejectBtn then
			rejectBtn.Active = true
			rejectBtn.Selectable = true
			bindButtonMotion(rejectBtn)
			local rejectIcon = UIMotion.scaleTargetOf(rejectBtn)
			confirmRejectConn = rejectBtn.Activated:Connect(function()
				UIMotion.pop(rejectIcon, 1.18)
				disconnectConfirmButtons()
				RemoteRespond:FireServer({ requestId = requestId, accepted = false })
				hideNotif()
			end)
		end
	end

	setTab = function(showRequest: boolean): ()
		local reqOn = requestButton:FindFirstChild("UIGradientPinkEnabled") :: UIGradient?
		local reqOff = requestButton:FindFirstChild("UIGradientPinkDisabled") :: UIGradient?
		local brkOn = breakUpButton:FindFirstChild("GradientEnabled") :: UIGradient?
		local brkOff = breakUpButton:FindFirstChild("GradientDisabled") :: UIGradient?
		if reqOn then
			reqOn.Enabled = showRequest
		end
		if reqOff then
			reqOff.Enabled = not showRequest
		end
		if brkOn then
			brkOn.Enabled = not showRequest
		end
		if brkOff then
			brkOff.Enabled = showRequest
		end
		requestContent.Visible = showRequest and not isCoupled
		selectPlayerFrame.Visible = showRequest and not isCoupled
		-- Single = breakup tab open but no couple yet
		-- Taken = already has couple (any tab)
		breakupSingle.Visible = not showRequest and not isCoupled
		breakupTaken.Visible = isCoupled
		
		-- Animate background pill
		if backgroundPill then
			local selectedButton = if showRequest then requestButton else breakUpButton
			animateSlidingPill(backgroundPill, selectedButton, tabButtons)
		end

		-- The page now on top slides in through equal and opposite UIPadding, so the laid-out
		-- content wrapper never changes size (ADR 0011). Couple-status syncs re-assert the same
		-- tab on every echo; only a real switch animates.
		local page: GuiObject? = (
			if isCoupled then breakupTaken elseif showRequest then requestContent else breakupSingle
		) :: any
		if page ~= activeTabPage then
			activeTabPage = page
			if page and mainWrapper.Visible then
				UIMotion.slideIn(page, if showRequest then -1 else 1)
			end
		end
	end
	local refreshPlayerCardSelection: () -> ()
	local function clearSelectedTarget(): ()
		selectedUserId = nil
		selectedDisplayName = ""
		usernameBox.Text = ""
		if targetPfp then
			targetPfp.Visible = false
			targetPfp.Image = ""
		end
		refreshPlayerCardSelection()
	end
	local function rebuildLocalPlayerDirectory(): ()
		local nextPlayers: { { userId: number, displayName: string, username: string } } = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= localPlayer then
				table.insert(nextPlayers, {
					userId = player.UserId,
					displayName = player.DisplayName,
					username = player.Name,
				})
			end
		end
		allPlayers = nextPlayers
	end
	local function ensurePlayerCard(index: number): PlayerListEntry
		local entry = playerCardPool[index]
		if entry then
			if entry.button.Parent ~= scrollableList then
				entry.button.Parent = scrollableList
			end
			return entry
		end
		local button = playerSelectorCard:Clone() :: TextButton
		button.Visible = false
		button.Parent = scrollableList
		-- Fresh clone: its designed transparencies are captured here, before any stagger has
		-- touched them, and press/hover is bound once — after parenting, so UIMotion judges the
		-- card from its real ancestry (a CanvasGroup list must never receive a UIScale).
		captureOnce(fadeTargetsOf(button))
		bindButtonMotion(button)
		cardTargetTransparency[button] = button.BackgroundTransparency
		local newEntry: PlayerListEntry = {
			button = button,
			connection = nil,
		}
		playerCardPool[index] = newEntry
		return newEntry
	end
	local function hideUnusedPlayerCards(firstUnusedIndex: number): ()
		for index = firstUnusedIndex, #playerCardPool do
			local entry = playerCardPool[index]
			if entry.connection then
				entry.connection:Disconnect()
				entry.connection = nil
			end
			entry.button.Visible = false
			-- Retired row: drop any running highlight tween before resetting it by hand.
			UIMotion.cancel(entry.button)
			cardTargetTransparency[entry.button] = playerCardDefaultTransparency
			entry.button.BackgroundTransparency = playerCardDefaultTransparency
		end
	end
	refreshPlayerCardSelection = function(): ()
		for _, entry in ipairs(playerCardPool) do
			local userId = entry.button:GetAttribute("PlayerUserId")
			local isSelected = selectedUserId ~= nil and type(userId) == "number" and selectedUserId == userId
			local target = if isSelected then playerCardSelectedTransparency else playerCardDefaultTransparency
			-- Transparency only: the cards are laid out in the scrolling list, so nothing here may
			-- change their size (ADR 0011). Rows already heading there are left alone, so a couple
			-- status echo never restarts the tween.
			if cardTargetTransparency[entry.button] ~= target then
				cardTargetTransparency[entry.button] = target
				UIMotion.tween(entry.button, 0.18, { BackgroundTransparency = target })
			end
		end
	end
	local function isPlayerMatchingQuery(
		playerData: { userId: number, displayName: string, username: string },
		query: string
	): boolean
		if query == "" then
			return true
		end
		local normalizedQuery = string.lower(query)
		return string.find(string.lower(playerData.displayName), normalizedQuery, 1, true) ~= nil
			or string.find(string.lower(playerData.username), normalizedQuery, 1, true) ~= nil
	end
	local function updatePlayerList(players: { { userId: number, displayName: string, username: string } }): ()
		local selectedStillExists = false
		playerSelectorCard.Visible = false
		if notFoundCard then
			notFoundCard.Visible = (#players == 0)
			if #players == 0 then
				if #allPlayers == 0 then
					setNotFoundCardText(notFoundCard, EMPTY_STATE_DEFAULT_TITLE, EMPTY_STATE_DEFAULT_SUBTITLE)
				else
					setNotFoundCardText(notFoundCard, EMPTY_STATE_SEARCH_TITLE, EMPTY_STATE_SEARCH_SUBTITLE)
				end
			end
		end
		local currentQuery = ""
		if searchBox then
			currentQuery = string.gsub(searchBox.Text, "^%s*(.-)%s*$", "%1")
		end
		local renderedRows: { GuiObject } = {}
		local signatureParts: { string } = { currentQuery }
		for index, pd in ipairs(players) do
			local entry = ensurePlayerCard(index)
			local card = entry.button
			table.insert(renderedRows, card :: GuiObject)
			table.insert(signatureParts, tostring(pd.userId))
			if entry.connection then
				entry.connection:Disconnect()
				entry.connection = nil
			end
			card.Visible = true
			card.Parent = scrollableList
			card.LayoutOrder = index
			card:SetAttribute("PlayerUserId", pd.userId)
			local cardInfo = card:FindFirstChild("PlayerInformation") :: Frame?
			if cardInfo then
				local nameLabel = cardInfo:FindFirstChild("1-Title") :: TextLabel?
				local userLabel = cardInfo:FindFirstChild("2-SubTitle") :: TextLabel?
				if nameLabel then
					nameLabel.RichText = true
					nameLabel.Text = highlightFirstMatch(pd.displayName, currentQuery)
				end
				if userLabel then
					userLabel.RichText = true
					userLabel.Text = "@" .. highlightFirstMatch(pd.username, currentQuery)
				end
			end
			local pfp = card:FindFirstChild("PlayerProfilePicture") :: ImageLabel?
			if pfp then
				setThumbnailAsync(pfp, pd.userId)
			end
			local uid = pd.userId
			local displayName = pd.displayName
			entry.connection = card.Activated:Connect(function()
				-- The card's avatar (or whatever UIMotion deems scalable here) pops; under a
				-- CanvasGroup list it refuses and the highlight alone carries the choice.
				UIMotion.pop(UIMotion.scaleTargetOf(card), 1.18)
				selectedUserId = uid
				selectedDisplayName = displayName
				-- Set displayName on TextBox
				usernameBox.Text = displayName
				-- Foto target muncul with animasi scale pop
				if targetPfp then
					targetPfp.Visible = false
					setThumbnailAsync(targetPfp, uid)
					task.defer(function()
						anim:scalePop((targetPfp :: any) :: Frame, nil)
					end)
				end
				refreshPlayerCardSelection()
			end)
			if selectedUserId == uid then
				selectedStillExists = true
			end
		end
		hideUnusedPlayerCards(#players + 1)
		-- Cascade only on a real render. The server echoes full couple state on every sync and
		-- each echo re-runs the search; an unchanged roster must not replay its entrance.
		local signature = table.concat(signatureParts, "\0")
		if signature ~= lastListSignature then
			lastListSignature = signature
			UIMotion.stagger(renderedRows, fadeBases)
		end
		if selectedUserId and not selectedStillExists then
			clearSelectedTarget()
			return
		end
		refreshPlayerCardSelection()
	end
	local function applyPlayerSearch(): ()
		local query = ""
		if searchBox then
			query = string.gsub(searchBox.Text, "^%s*(.-)%s*$", "%1")
		end
		local filteredPlayers = table.create(#allPlayers)
		for _, pd in ipairs(allPlayers) do
			if isPlayerMatchingQuery(pd, query) then
				table.insert(filteredPlayers, pd)
			end
		end
		updatePlayerList(filteredPlayers)
	end
	-- ============================================================
	-- Init
	-- ============================================================
	-- Hide all content panels initially so they do not flash
	-- template when panel dibuka before server data tiba
	requestContent.Visible = false
	selectPlayerFrame.Visible = false
	breakupSingle.Visible = false
	breakupTaken.Visible = false
	refreshLocalPlayerPhotos()
	clearSelectedTarget()
	-- Waiting CloseButton
	if waitingCloseBtn then
		bindButtonMotion(waitingCloseBtn)
		waitingCloseBtn.Activated:Connect(function()
			hideNotif()
		end)
	end
	-- ============================================================
	-- Panel data from server
	-- ============================================================
	track(RemotePanelData.OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" then
			return
		end
		isCoupled = data.isCoupled == true
		partnerName = type(data.partnerName) == "string" and data.partnerName or ""
		partnerId = type(data.partnerId) == "number" and data.partnerId or nil
		if isCoupled then
			setCurrentCoupleText("Your current couple: " .. partnerName)
			refreshPartnerPhoto()
			setTab(false)
		else
			rebuildLocalPlayerDirectory()
			if searchBox then
				searchBox.Text = ""
			end
			clearSelectedTarget()
			setTab(true)
			applyPlayerSearch()
		end
	end))
	if searchBox then
		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			applyPlayerSearch()
		end)
	end
	Players.PlayerAdded:Connect(function()
		if panelOpen and not isCoupled then
			rebuildLocalPlayerDirectory()
			applyPlayerSearch()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if panelOpen and not isCoupled then
			rebuildLocalPlayerDirectory()
			applyPlayerSearch()
		end
	end)
	-- ============================================================
	-- Header buttons
	-- ============================================================
	bindButtonMotion(requestButton)
	bindButtonMotion(breakUpButton)
	requestButton.Activated:Connect(function()
		if isCoupled then
			-- Locked to the breakup tab: shake the tab the player pressed in vain.
			UIMotion.wiggle(requestButton, 6)
			return
		end
		setTab(true)
	end)
	breakUpButton.Activated:Connect(function()
		setTab(false)
	end)
	if closeModalButton then
		bindButtonMotion(closeModalButton)
		closeModalButton.Activated:Connect(function()
			requestClose()
		end)
	end
	-- ============================================================
	-- Send request
	-- ============================================================
	bindButtonMotion(sendButton)
	local sendIcon = UIMotion.scaleTargetOf(sendButton)
	sendButton.Activated:Connect(function()
		if not selectedUserId then
			-- Nothing picked: shake the button the player just pressed in vain.
			UIMotion.wiggle(sendButton, 6)
			return
		end
		UIMotion.pop(sendIcon, 1.25)
		local reqId = HttpService:GenerateGUID(false)
		_currentRequestId = reqId
		if waitingTargetPfp then
			setThumbnailAsync(waitingTargetPfp, selectedUserId)
		end
		if waitingTextLabel then
			waitingTextLabel.Text = "Wait a moment to " .. selectedDisplayName .. " accept request..."
		end
		RemoteSendRequest:FireServer({ requestId = reqId, targetUserId = selectedUserId })
		showNotif(waitingFrame)
	end)
	-- Avatar context menu "Propose Couple": same request + waiting notif, target picked there.
	_proposeTo = function(targetUserId: number)
		local target = Players:GetPlayerByUserId(targetUserId)
		selectedUserId = targetUserId
		selectedDisplayName = if target then target.DisplayName else "them"
		local reqId = HttpService:GenerateGUID(false)
		_currentRequestId = reqId
		if waitingTargetPfp then
			setThumbnailAsync(waitingTargetPfp, targetUserId)
		end
		if waitingTextLabel then
			waitingTextLabel.Text = "Wait a moment to " .. selectedDisplayName .. " accept request..."
		end
		RemoteSendRequest:FireServer({ requestId = reqId, targetUserId = targetUserId })
		showNotif(waitingFrame)
	end
	_hasPartner = function(): boolean
		return partnerId ~= nil
	end
	-- ============================================================
	-- Breakup
	-- ============================================================
	bindButtonMotion(breakupBtn)
	local breakupIcon = UIMotion.scaleTargetOf(breakupBtn)
	breakupBtn.Activated:Connect(function()
		UIMotion.pop(breakupIcon, 1.2)
		local previousPartnerId = partnerId
		RemoteBreakup:FireServer({
			requestId = HttpService:GenerateGUID(false),
		})
		isCoupled = false
		partnerName = ""
		partnerId = nil
		-- Optimistic chat-tag clear (server also publishes ChatTagSync).
		applyLocalCoupleChatTag(localPlayer.UserId, nil)
		applyLocalCoupleChatTag(previousPartnerId, nil)
		hideNotif()
		requestClose()
	end)
	-- ============================================================
	-- Incoming request notification (recipient)
	-- ============================================================
	track(RemoteNotifyRequest.OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" then
			return
		end
		if type(data.requestId) ~= "string" then
			return
		end
		local fromUserId = tonumber(data.fromUserId) or 0
		local fromName = tostring(data.fromName)
		if confirmSenderPfp then
			setThumbnailAsync(confirmSenderPfp, fromUserId)
		end
		if confirmTextLabel then
			confirmTextLabel.Text = fromName .. " has sent you a couple request!"
		end
		bindConfirmButtons(data.requestId)
		showNotif(confirmFrame)
	end))
	-- ============================================================
	-- Result notification
	-- ============================================================
	track(RemoteNotifyResult.OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" then
			return
		end
		hideNotif()
		if data.isBreakup == true then
			local otherId = tonumber(data.partnerId)
			isCoupled = false
			partnerName = ""
			partnerId = nil
			applyLocalCoupleChatTag(localPlayer.UserId, nil)
			applyLocalCoupleChatTag(otherId, nil)
			return
		end
		if data.accepted == true then
			isCoupled = true
			partnerName = type(data.partnerName) == "string" and data.partnerName or ""
			partnerId = type(data.partnerId) == "number" and data.partnerId or nil
			setCurrentCoupleText("Your current couple: " .. partnerName)
			refreshPartnerPhoto()
			-- Accepted: the two photos on the breakup tab celebrate the match.
			UIMotion.pop(breakupPartnerPfp, 1.3)
			UIMotion.pop(breakupPlayerPfp, 1.3)
			if partnerName ~= "" then
				applyLocalCoupleChatTag(localPlayer.UserId, partnerName)
			end
			if partnerId and localPlayer.DisplayName ~= "" then
				-- Partner's chat tag shows our name while server recovery refresh lands.
				applyLocalCoupleChatTag(partnerId, localPlayer.DisplayName)
			end
		else
			local rejectedName = tostring(data.partnerName)
			if rejectedPartnerPfp and selectedUserId then
				setThumbnailAsync(rejectedPartnerPfp, selectedUserId)
			end
			if rejectedTextLabel then
				rejectedTextLabel.Text = "NT! " .. rejectedName .. " has rejected your couple request!"
			end
			showNotif(rejectedFrame)
			local inputArea = rejectedFrame:FindFirstChild("InputArea") :: Frame?
			if inputArea then
				local tryAgain = inputArea:FindFirstChild("TryAgainButton") :: TextButton?
				local closeBtn = inputArea:FindFirstChild("CloseButton") :: TextButton?
				if tryAgain then
					bindButtonMotion(tryAgain)
					tryAgain.Activated:Once(function()
						hideNotif()
						showPanel(true)
					end)
				end
				if closeBtn then
					bindButtonMotion(closeBtn)
					closeBtn.Activated:Once(function()
						hideNotif()
					end)
				end
			end
		end
	end))
	-- ============================================================
	-- Announce from server
	-- ============================================================
	track(RemoteAnnounce.OnClientEvent:Connect(function(msg: any)
		if type(msg) ~= "string" then
			return
		end
		-- Hide flag: respect user's SettingsHideCoupleAnnounce preference.
		-- Previously couple announce wrote directly to RBXGeneral chat without
		-- check flag → toggle di settings menu had no effect.
		if localPlayer:GetAttribute("SettingsHideCoupleAnnounce") == true then
			return
		end
		task.spawn(function()
			local MAX_ATTEMPTS = Config.Couple.ANNOUNCE_MAX_ATTEMPTS
			for attempt = 1, MAX_ATTEMPTS do
				local channels = TextChatService:FindFirstChild("TextChannels")
				local channel = channels and channels:FindFirstChild("RBXGeneral") :: TextChannel?
				if channel then
					local ok, _ = pcall(function()
						channel:DisplaySystemMessage(
							'<font color="' .. Config.Couple.ANNOUNCE_COLOR .. '">' .. msg .. "</font>"
						)
					end)
					if ok then
						return
					end
				end
				if attempt < MAX_ATTEMPTS then
					task.wait(Config.Couple.ANNOUNCE_RETRY_WAIT)
				end
			end
		end)
	end))
	-- ============================================================
	-- TopbarPlus icon
	-- ============================================================
	if topbarIcon then
		topbarIcon.selected:Connect(function()
			showPanel(true)
		end)
		topbarIcon.deselected:Connect(function()
			showPanel(false)
		end)
	end
	-- Removed dead code suppressor `local _ = currentRequestId`
	-- Variable is actually used in sendButton.Activated handler
	log:info("Client CoupleController initialized")
end
return {
	init = init,
	destroy = destroy,
	proposeTo = function(targetUserId: number)
		if _proposeTo then
			_proposeTo(targetUserId)
		end
	end,
	hasPartner = function(): boolean
		return _hasPartner ~= nil and _hasPartner()
	end,
	isReady = function(): boolean
		return _proposeTo ~= nil
	end,
}
