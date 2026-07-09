--!strict
-- PATH: StarterPlayerScripts/Client/Controllers/Client_CoupleController.lua (ModuleScript)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
local log = Logger.new("Client.CoupleController")

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
	
	-- Set anchor point immediately, animate position with smooth easing
	backgroundPill.AnchorPoint = targetAnchorPoint
	local tween = TweenService:Create(
		backgroundPill,
		TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = targetPosition }
	)
	tween:Play()
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
	local Remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	local RemoteSendRequest = Remotes:WaitForChild("CoupleSendRequest") :: RemoteEvent
	local RemoteRespond = Remotes:WaitForChild("CoupleRespond") :: RemoteEvent
	local RemoteBreakup = Remotes:WaitForChild("CoupleBreakup") :: RemoteEvent
	local RemoteOpenPanel = Remotes:WaitForChild("CoupleOpenPanel") :: RemoteEvent
	local RemoteNotifyRequest = Remotes:WaitForChild("CoupleNotifyRequest") :: RemoteEvent
	local RemoteNotifyResult = Remotes:WaitForChild("CoupleNotifyResult") :: RemoteEvent
	local RemoteAnnounce = Remotes:WaitForChild("CoupleAnnounce") :: RemoteEvent
	local RemotePanelData = Remotes:WaitForChild("CouplePanelData") :: RemoteEvent
	-- ============================================================
	-- Referensi GUI
	-- ============================================================
	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local coupleGui = playerGui:WaitForChild("01-CoupleSystemGUI", 30) :: ScreenGui?
	if not coupleGui then
		log:warn("01-CoupleSystemGUI tidak ditemukan, CoupleController tidak dijalankan")
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
			log:error("2-BreakupContent* frames tidak ditemukan")
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
		log:error("Request/BreakUp buttons tidak ditemukan di 2-SliderSelector")
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
		log:warn("Couple GUI close button tidak ditemukan — panel tetap jalan tanpa tombol close modal")
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
	-- BreakupContentSingle (belum couple)
	-- ============================================================
	local breakupSingleJumbotron = breakupSingle:FindFirstChild("JumbotronTextandImage") :: Frame?
	local breakupSingleProfil = breakupSingleJumbotron
		and breakupSingleJumbotron:FindFirstChild("ProfilPicture") :: Frame?
	local breakupSinglePlayerPfp = breakupSingleProfil
		and breakupSingleProfil:FindFirstChild("PlayerDisplayName") :: ImageLabel?
	-- ============================================================
	-- BreakupContentTaken (sudah couple)
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
	local allPlayers: { { userId: number, displayName: string, username: string } } = {}
	local playerCardPool = {} :: { PlayerListEntry }
	local ringHandle: AnimationHelper.ProgressRingHandle? = nil
	local confirmAcceptConn: RBXScriptConnection? = nil
	local confirmRejectConn: RBXScriptConnection? = nil
	local anim = AnimationHelper.new()
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
	-- Forward declaration: setTab didefinisikan setelah showPanel,
	-- tapi showPanel memanggilnya. Tanpa ini, Lua lookup ke global (nil).
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
		end
	end
	local function stopRing(): ()
		if ringHandle then
			ringHandle.stop()
			ringHandle = nil
		end
	end
	local function showNotif(frame: Frame): ()
		setOverlayVisible(true)
		notifWrapper.Visible = true
		confirmFrame.Visible = frame == confirmFrame
		rejectedFrame.Visible = frame == rejectedFrame
		waitingFrame.Visible = frame == waitingFrame
		if frame == confirmFrame then
			anim:swingIn(confirmFrame, notifWrapper, nil)
		elseif frame == waitingFrame then
			anim:scalePop(waitingFrame, nil)
			stopRing()
		elseif frame == rejectedFrame then
			anim:scalePop(rejectedFrame, nil)
		end
	end
	local disconnectConfirmButtons: () -> ()
	local function hideNotif(): ()
		stopRing()
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
			confirmAcceptConn = acceptBtn.Activated:Connect(function()
				disconnectConfirmButtons()
				RemoteRespond:FireServer({ requestId = requestId, accepted = true })
				hideNotif()
			end)
		end
		if rejectBtn then
			rejectBtn.Active = true
			rejectBtn.Selectable = true
			confirmRejectConn = rejectBtn.Activated:Connect(function()
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
		-- Single = tab breakup dibuka tapi belum punya couple
		-- Taken = sudah punya couple (apapun tabnya)
		breakupSingle.Visible = not showRequest and not isCoupled
		breakupTaken.Visible = isCoupled
		
		-- Animate background pill
		if backgroundPill then
			local selectedButton = if showRequest then requestButton else breakUpButton
			animateSlidingPill(backgroundPill, selectedButton, tabButtons)
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
			entry.button.BackgroundTransparency = playerCardDefaultTransparency
		end
	end
	refreshPlayerCardSelection = function(): ()
		for _, entry in ipairs(playerCardPool) do
			local userId = entry.button:GetAttribute("PlayerUserId")
			local isSelected = selectedUserId ~= nil and type(userId) == "number" and selectedUserId == userId
			entry.button.BackgroundTransparency = if isSelected
				then playerCardSelectedTransparency
				else playerCardDefaultTransparency
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
		for index, pd in ipairs(players) do
			local entry = ensurePlayerCard(index)
			local card = entry.button
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
				selectedUserId = uid
				selectedDisplayName = displayName
				-- Set displayName ke TextBox
				usernameBox.Text = displayName
				-- Foto target muncul dengan animasi scale pop
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
	-- Sembunyikan semua content panel dari awal supaya tidak flash
	-- template saat panel dibuka sebelum server data tiba
	requestContent.Visible = false
	selectPlayerFrame.Visible = false
	breakupSingle.Visible = false
	breakupTaken.Visible = false
	refreshLocalPlayerPhotos()
	clearSelectedTarget()
	-- Waiting CloseButton
	if waitingCloseBtn then
		waitingCloseBtn.Activated:Connect(function()
			hideNotif()
		end)
	end
	-- ============================================================
	-- Panel data dari server
	-- ============================================================
	track(RemotePanelData.OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" then
			return
		end
		isCoupled = data.isCoupled == true
		partnerName = type(data.partnerName) == "string" and data.partnerName or ""
		partnerId = type(data.partnerId) == "number" and data.partnerId or nil
		if isCoupled then
			currentCoupleLbl.Text = "Your current couple: " .. partnerName
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
	requestButton.Activated:Connect(function()
		if not isCoupled then
			setTab(true)
		end
	end)
	breakUpButton.Activated:Connect(function()
		setTab(false)
	end)
	if closeModalButton then
		closeModalButton.Activated:Connect(function()
			showPanel(false)
		end)
	end
	-- ============================================================
	-- Send request
	-- ============================================================
	sendButton.Activated:Connect(function()
		if not selectedUserId then
			return
		end
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
	-- ============================================================
	-- Breakup
	-- ============================================================
	breakupBtn.Activated:Connect(function()
		RemoteBreakup:FireServer({
			requestId = HttpService:GenerateGUID(false),
		})
		isCoupled = false
		partnerName = ""
		partnerId = nil
		hideNotif()
		showPanel(false)
	end)
	-- ============================================================
	-- Notifikasi request masuk (penerima)
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
	-- Notifikasi result
	-- ============================================================
	track(RemoteNotifyResult.OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" then
			return
		end
		hideNotif()
		if data.isBreakup == true then
			isCoupled = false
			partnerName = ""
			partnerId = nil
			return
		end
		if data.accepted == true then
			isCoupled = true
			partnerName = type(data.partnerName) == "string" and data.partnerName or ""
			partnerId = type(data.partnerId) == "number" and data.partnerId or nil
			currentCoupleLbl.Text = "Your current couple: " .. partnerName
			refreshPartnerPhoto()
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
					tryAgain.Activated:Once(function()
						hideNotif()
						showPanel(true)
					end)
				end
				if closeBtn then
					closeBtn.Activated:Once(function()
						hideNotif()
					end)
				end
			end
		end
	end))
	-- ============================================================
	-- Announce dari server
	-- ============================================================
	track(RemoteAnnounce.OnClientEvent:Connect(function(msg: any)
		if type(msg) ~= "string" then
			return
		end
		-- Hide flag: respect user's SettingsHideCoupleAnnounce preference.
		-- Sebelumnya couple announce write langsung ke RBXGeneral chat tanpa
		-- check flag → toggle di settings menu tidak ada efek.
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
	local topbarIcon = deps and deps.icon or nil
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
return { init = init, destroy = destroy }
