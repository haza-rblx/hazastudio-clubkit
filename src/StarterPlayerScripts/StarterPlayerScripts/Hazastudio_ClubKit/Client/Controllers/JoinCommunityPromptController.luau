--!strict
-- After loading/gameplay entry, show custom 16-JoinCommunPrompt (once per session),
-- then CoreGui PromptJoinAsync only when the player clicks Join.
-- Center-modal motion: AnimationHelper presentCenterPanel / dismissCenterPanel
-- (same family as ShopUI / GiftUI / PaidBroadcastUI — scale 0.96↔1 + PanelBlur + FOV zoom).

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local BrandLogoApplier = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BrandLogoApplier)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)

local log = Logger.new("JoinCommunityPrompt")

local PROMPT_DELAY_SEC = 2
local GUI_WAIT_TIMEOUT = 8
local ROOT_GUI_NAME = "16-JoinCommunPrompt"
local MAX_THUMBNAILS = 8
local BODY_NAME_LIMIT = 3
local SERVER_SAMPLE_TIMEOUT = 6

-- Shop / Gift / PaidBroadcast blur+zoom options (not Couple, which skips backdrop).
local MODAL_BLUR_OPTIONS = {
	enableBlur = true,
	blurName = "JoinCommunityPromptBlur",
	enableZoom = true,
}

local promptedThisSession = false
local missingGuiWarned = false
local wired = false
local isOpen = false
local isClosing = false

local anim = AnimationHelper.new()

type MemberSample = {
	userId: number,
	displayName: string,
}

type Refs = {
	root: ScreenGui,
	mainWrapper: Frame,
	closeButton: GuiButton,
	joinButton: GuiButton,
	communityLogo: ImageLabel?,
	thumbnailHost: Frame?,
	thumbnailTemplate: ImageLabel?,
	counterLeft: GuiObject?,
	counterLabel: TextLabel?,
	titleLabel: TextLabel?,
	subheadlineLabel: TextLabel?,
	subtitleLabel: TextLabel?,
	bodyLabel: TextLabel?,
}

local refs: Refs? = nil
local thumbClones: { ImageLabel } = {}
local fillGeneration = 0

local function findGuiObject(root: Instance, name: string): GuiObject?
	local found = root:FindFirstChild(name, true)
	if found and found:IsA("GuiObject") then
		return found
	end
	return nil
end

local function findGuiButton(root: Instance, name: string): GuiButton?
	local found = root:FindFirstChild(name, true)
	if found and found:IsA("GuiButton") then
		return found
	end
	return nil
end

local function findTextLabel(root: Instance, name: string): TextLabel?
	local found = root:FindFirstChild(name, true)
	if found and found:IsA("TextLabel") then
		return found
	end
	return nil
end

local function headshotUrl(userId: number): string
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
end

local function isPlayerInGroupAsync(player: Player, groupId: number): boolean
	local ok, result = pcall(function()
		return player:IsInGroupAsync(groupId)
	end)
	if ok and result == true then
		return true
	end
	if not ok then
		local okSync, syncResult = pcall(function()
			return player:IsInGroup(groupId)
		end)
		return okSync and syncResult == true
	end
	return false
end

local function tryGetGroupMemberCountLocal(groupId: number): number?
	local okInfo, info = pcall(function()
		return GroupService:GetGroupInfoAsync(groupId)
	end)
	if okInfo and type(info) == "table" then
		local count = (info :: any).MemberCount or (info :: any).memberCount
		if type(count) == "number" and count > 0 then
			return count
		end
	end
	return nil
end

local function clearThumbClones()
	for _, clone in ipairs(thumbClones) do
		if clone.Parent then
			clone:Destroy()
		end
	end
	table.clear(thumbClones)
end

local function setCounterVisible(visible: boolean, extra: number?)
	local r = refs
	if not r or not r.counterLeft then
		return
	end
	if visible and type(extra) == "number" and extra > 0 then
		if r.counterLabel then
			r.counterLabel.Text = "+" .. tostring(extra)
		end
		r.counterLeft.Visible = true
	else
		r.counterLeft.Visible = false
	end
end

local function applyCommunityLogo(r: Refs)
	local logoAsset = BrandLogoApplier.resolveTargetLogo(Config)
	if logoAsset == "" then
		return
	end

	-- Always set CommunityLogo from Branding (NAME_MATCH + explicit Image).
	BrandLogoApplier.applyToInstance(r.root, Config)
	if r.communityLogo then
		r.communityLogo.Image = logoAsset
	end
end

local function joinPromptCfg(): any
	local cfg = Config.JoinCommunityPrompt
	return if type(cfg) == "table" then cfg else {}
end

local function formatSubtitle(memberCount: number): string
	local cfg = joinPromptCfg()
	if memberCount > 0 then
		local template = tostring(cfg.SUBTITLE_WITH_COUNT or "Join with other %d players.")
		return string.format(template, memberCount)
	end
	return tostring(cfg.SUBTITLE_FALLBACK or "Join with other players.")
end

local function formatBody(names: { string }, memberCount: number): string
	local cfg = joinPromptCfg()
	if #names == 0 then
		if memberCount > 0 then
			local template = tostring(cfg.BODY_EMPTY_WITH_COUNT or "%d players already joined this community.")
			return string.format(template, memberCount)
		end
		return tostring(cfg.BODY_EMPTY or "Be among the first to join this community.")
	end

	local listed = {}
	for i = 1, math.min(BODY_NAME_LIMIT, #names) do
		table.insert(listed, names[i])
	end

	local listedCount = #listed
	local remaining = math.max(0, memberCount - listedCount)
	if remaining <= 0 then
		if listedCount == 1 then
			local template = tostring(cfg.BODY_ONE or "%s already joined this community.")
			return string.format(template, listed[1])
		end
		if listedCount == 2 then
			local template = tostring(cfg.BODY_TWO or "%s and %s already joined this community.")
			return string.format(template, listed[1], listed[2])
		end
		local template = tostring(cfg.BODY_THREE or "%s, %s, and %s already joined this community.")
		return string.format(template, listed[1], listed[2], listed[3])
	end

	local listedJoined = table.concat(listed, ", ")
	local template = tostring(cfg.BODY_WITH_EXTRA or "%s, and %d other players already joined this community.")
	return string.format(template, listedJoined, remaining)
end

local function applyHeadlineCopy()
	local r = refs
	if not r then
		return
	end
	local cfg = joinPromptCfg()
	if r.titleLabel then
		r.titleLabel.Text = tostring(cfg.TITLE or "Join our community.")
	end
	if r.subheadlineLabel then
		r.subheadlineLabel.Text = tostring(cfg.SUBHEADLINE or "Stay connected with the club.")
	end
end

local function applyCopy(memberCount: number, displayNames: { string })
	local r = refs
	if not r then
		return
	end
	applyHeadlineCopy()
	if r.subtitleLabel then
		r.subtitleLabel.Text = formatSubtitle(memberCount)
	end
	if r.bodyLabel then
		r.bodyLabel.Text = formatBody(displayNames, memberCount)
	end
end

local function requestServerMembersAsync(groupId: number): { memberCount: number, members: { MemberSample } }?
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes or not remotes:IsA("Folder") then
		return nil
	end

	local cfg = Config.JoinCommunityPrompt or {}
	local requestName = tostring(cfg.REMOTE_REQUEST or "JoinCommunityMembersRequest")
	local responseName = tostring(cfg.REMOTE_RESPONSE or "JoinCommunityMembersResponse")

	local requestRemote = remotes:FindFirstChild(requestName)
	local responseRemote = remotes:FindFirstChild(responseName)
	if not requestRemote then
		requestRemote = remotes:WaitForChild(requestName, 3)
	end
	if not responseRemote then
		responseRemote = remotes:WaitForChild(responseName, 3)
	end
	if not requestRemote or not requestRemote:IsA("RemoteEvent") then
		return nil
	end
	if not responseRemote or not responseRemote:IsA("RemoteEvent") then
		return nil
	end

	local done = false
	local payload: any = nil
	local conn: RBXScriptConnection? = nil
	conn = (responseRemote :: RemoteEvent).OnClientEvent:Connect(function(raw: any)
		if done then
			return
		end
		if type(raw) ~= "table" then
			return
		end
		local rawGroupId = tonumber((raw :: any).groupId)
		if rawGroupId ~= nil and rawGroupId ~= groupId then
			return
		end
		done = true
		payload = raw
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end)

	;(requestRemote :: RemoteEvent):FireServer({ groupId = groupId })

	local deadline = os.clock() + SERVER_SAMPLE_TIMEOUT
	while not done and os.clock() < deadline do
		task.wait(0.05)
	end
	if conn then
		conn:Disconnect()
	end
	if type(payload) ~= "table" then
		return nil
	end

	local memberCount = tonumber((payload :: any).memberCount) or 0
	local membersRaw = (payload :: any).members
	local members: { MemberSample } = {}
	if type(membersRaw) == "table" then
		for _, row in ipairs(membersRaw) do
			if type(row) == "table" then
				local userId = tonumber((row :: any).userId) or 0
				if userId > 0 then
					local displayName = (row :: any).displayName
					if type(displayName) ~= "string" or displayName == "" then
						displayName = "Player"
					end
					table.insert(members, {
						userId = userId,
						displayName = displayName,
					})
				end
			end
		end
	end

	return {
		memberCount = memberCount,
		members = members,
	}
end

local function collectOnlineInGroup(groupId: number): { MemberSample }
	local localPlayer = Players.LocalPlayer
	local out: { MemberSample } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if #out >= MAX_THUMBNAILS then
			break
		end
		local isLocal = localPlayer ~= nil and player.UserId == localPlayer.UserId
		if not isLocal and isPlayerInGroupAsync(player, groupId) then
			local displayName = player.DisplayName
			if type(displayName) ~= "string" or displayName == "" then
				displayName = player.Name
			end
			table.insert(out, {
				userId = player.UserId,
				displayName = displayName,
			})
		end
	end
	return out
end

local function mergeMemberSamples(
	online: { MemberSample },
	serverMembers: { MemberSample },
	localUserId: number?
): { MemberSample }
	local seen: { [number]: boolean } = {}
	local out: { MemberSample } = {}

	local function tryAdd(sample: MemberSample)
		if #out >= MAX_THUMBNAILS then
			return
		end
		if localUserId ~= nil and sample.userId == localUserId then
			return
		end
		if seen[sample.userId] then
			return
		end
		seen[sample.userId] = true
		table.insert(out, sample)
	end

	for _, sample in ipairs(online) do
		tryAdd(sample)
	end
	for _, sample in ipairs(serverMembers) do
		tryAdd(sample)
	end
	return out
end

local function resolveRefs(): Refs?
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return nil
	end

	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		playerGui = localPlayer:WaitForChild("PlayerGui", GUI_WAIT_TIMEOUT) :: PlayerGui?
	end
	if not playerGui or not playerGui:IsA("PlayerGui") then
		return nil
	end

	local rootInst = playerGui:FindFirstChild(ROOT_GUI_NAME)
	if not rootInst then
		rootInst = playerGui:WaitForChild(ROOT_GUI_NAME, GUI_WAIT_TIMEOUT)
	end
	if not rootInst or not rootInst:IsA("ScreenGui") then
		-- Nested under another ScreenGui in some places
		rootInst = playerGui:FindFirstChild(ROOT_GUI_NAME, true)
	end
	if not rootInst or not rootInst:IsA("ScreenGui") then
		return nil
	end

	local mainWrapper = rootInst:FindFirstChild("MainWrapper")
	if not mainWrapper or not mainWrapper:IsA("Frame") then
		mainWrapper = findGuiObject(rootInst, "MainWrapper")
	end
	if not mainWrapper or not mainWrapper:IsA("Frame") then
		return nil
	end

	local closeButton = findGuiButton(mainWrapper, "3-CloseModalButton")
	local joinButton = findGuiButton(mainWrapper, "JoinCommunityButton")
	if not closeButton or not joinButton then
		return nil
	end

	local communityLogoInst = mainWrapper:FindFirstChild("CommunityLogo", true)
	local communityLogo: ImageLabel? = nil
	if communityLogoInst and communityLogoInst:IsA("ImageLabel") then
		communityLogo = communityLogoInst
	end

	local thumbnailHost = findGuiObject(mainWrapper, "CommunityMemberThumbnail")
	local thumbnailTemplate: ImageLabel? = nil
	local counterLeft: GuiObject? = nil
	local counterLabel: TextLabel? = nil

	if thumbnailHost then
		local template = thumbnailHost:FindFirstChild("PlayerProfileThumbnail")
		if template and template:IsA("ImageLabel") then
			thumbnailTemplate = template
		end
		local counter = thumbnailHost:FindFirstChild("CounterLeft")
		if counter and counter:IsA("GuiObject") then
			counterLeft = counter
			local label = counter:FindFirstChild("TextLabel")
			if label and label:IsA("TextLabel") then
				counterLabel = label
			end
		end
	end

	return {
		root = rootInst :: ScreenGui,
		mainWrapper = mainWrapper :: Frame,
		closeButton = closeButton,
		joinButton = joinButton,
		communityLogo = communityLogo,
		thumbnailHost = if thumbnailHost and thumbnailHost:IsA("Frame") then thumbnailHost :: Frame else nil,
		thumbnailTemplate = thumbnailTemplate,
		counterLeft = counterLeft,
		counterLabel = counterLabel,
		subtitleLabel = findTextLabel(mainWrapper, "Subtitle"),
		bodyLabel = findTextLabel(mainWrapper, "Body"),
		titleLabel = findTextLabel(mainWrapper, "1-Title"),
		subheadlineLabel = findTextLabel(mainWrapper, "2-SubTitle"),
	}
end

local function fillMemberThumbnailsAsync(groupId: number, generation: number)
	local r = refs
	if not r then
		return
	end

	local localPlayer = Players.LocalPlayer
	local localUserId = if localPlayer then localPlayer.UserId else nil

	if r.thumbnailHost and r.thumbnailTemplate then
		r.thumbnailTemplate.Visible = false
	end
	setCounterVisible(false)
	clearThumbClones()
	applyCopy(0, {})

	local online = collectOnlineInGroup(groupId)
	if generation ~= fillGeneration or refs ~= r then
		return
	end

	-- Optimistic copy from online-only while server sample loads.
	local optimisticCount = #online
	local optimisticNames: { string } = {}
	for _, sample in ipairs(online) do
		table.insert(optimisticNames, sample.displayName)
	end
	applyCopy(optimisticCount, optimisticNames)

	local serverPayload = requestServerMembersAsync(groupId)
	if generation ~= fillGeneration or refs ~= r then
		return
	end

	local serverMembers: { MemberSample } = {}
	local memberCount = optimisticCount
	if serverPayload then
		serverMembers = serverPayload.members
		if serverPayload.memberCount > 0 then
			memberCount = serverPayload.memberCount
		end
	else
		local localCount = tryGetGroupMemberCountLocal(groupId)
		if type(localCount) == "number" and localCount > 0 then
			memberCount = localCount
		end
	end

	local merged = mergeMemberSamples(online, serverMembers, localUserId)
	if memberCount < #merged then
		memberCount = #merged
	end

	if r.thumbnailHost and r.thumbnailTemplate then
		local host = r.thumbnailHost
		local template = r.thumbnailTemplate
		for index, sample in ipairs(merged) do
			local clone = template:Clone()
			clone.Name = "PlayerProfileThumbnail_" .. tostring(index)
			clone.Image = headshotUrl(sample.userId)
			clone.Visible = true
			clone.LayoutOrder = index
			clone.Parent = host
			table.insert(thumbClones, clone)
		end
	end

	if memberCount > MAX_THUMBNAILS then
		setCounterVisible(true, memberCount - MAX_THUMBNAILS)
	else
		setCounterVisible(false)
	end

	local displayNames: { string } = {}
	for _, sample in ipairs(merged) do
		table.insert(displayNames, sample.displayName)
	end
	applyCopy(memberCount, displayNames)
end

local function dismissModal(onDone: (() -> ())?)
	local r = refs
	if not r then
		if onDone then
			onDone()
		end
		return
	end
	if isClosing then
		return
	end
	if not isOpen and not r.mainWrapper.Visible then
		if onDone then
			onDone()
		end
		return
	end

	isClosing = true
	isOpen = false
	anim:dismissCenterPanel(r.mainWrapper, function()
		isClosing = false
		if not isOpen then
			r.root.Enabled = false
		end
		if onDone then
			onDone()
		end
	end, MODAL_BLUR_OPTIONS)
end

local function promptJoinCoreGui(groupId: number)
	pcall(function()
		GroupService:PromptJoinAsync(groupId)
	end)
end

local function wireButtons(groupId: number)
	if wired or not refs then
		return
	end
	wired = true
	local r = refs

	r.closeButton.MouseButton1Click:Connect(function()
		dismissModal(nil)
	end)

	r.joinButton.MouseButton1Click:Connect(function()
		if isClosing then
			return
		end
		dismissModal(function()
			promptJoinCoreGui(groupId)
		end)
	end)
end

local function showModal(groupId: number)
	local resolved = resolveRefs()
	if not resolved then
		if not missingGuiWarned then
			missingGuiWarned = true
			log:warn("16-JoinCommunPrompt not found — skipping join modal (no auto CoreGui fallback)")
		end
		return
	end

	refs = resolved
	local r = resolved
	-- Gift / PaidBroadcast: enable ScreenGui, hide panel, then presentCenterPanel
	-- (UIScale open 0.96→1 Sine Out + blur/zoom via MODAL_BLUR_OPTIONS).
	r.root.Enabled = true
	anim:cancelPanel(r.mainWrapper)
	r.mainWrapper.Visible = false
	setCounterVisible(false)
	if r.thumbnailTemplate then
		r.thumbnailTemplate.Visible = false
	end
	applyCommunityLogo(r)
	applyCopy(0, {})

	wireButtons(groupId)

	isOpen = true
	isClosing = false
	anim:presentCenterPanel(r.mainWrapper, nil, MODAL_BLUR_OPTIONS)

	-- Thumbnails / member count are best-effort and must not block open.
	fillGeneration += 1
	local generation = fillGeneration
	task.spawn(function()
		fillMemberThumbnailsAsync(groupId, generation)
	end)
end

local function tryPromptAfterGameplay()
	if promptedThisSession then
		return
	end
	if Config.FeatureFlags.PromptJoinCommunityOnLoadEnabled ~= true then
		return
	end
	local groupId = Config.Group.GROUP_ID
	if type(groupId) ~= "number" or groupId <= 0 then
		return
	end

	promptedThisSession = true

	local localPlayer = Players.LocalPlayer
	if localPlayer and isPlayerInGroupAsync(localPlayer, groupId) then
		return
	end

	task.delay(PROMPT_DELAY_SEC, function()
		local player = Players.LocalPlayer
		if not player then
			return
		end
		-- Re-check in case membership changed during the delay.
		if isPlayerInGroupAsync(player, groupId) then
			return
		end
		showModal(groupId)
	end)
end

return {
	tryPromptAfterGameplay = tryPromptAfterGameplay,
}
