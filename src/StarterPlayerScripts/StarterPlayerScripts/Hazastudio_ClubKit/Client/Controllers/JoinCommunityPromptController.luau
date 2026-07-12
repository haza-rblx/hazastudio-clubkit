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
local SERVER_SAMPLE_TIMEOUT = 8

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
-- true once CommunityLogo was set from group emblem (engine or server proxy) this open.
local communityLogoFromEmblem = false

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

-- Engine GetGroupInfoAsync often omits MemberCount (not in official docs).
-- Returns count only when the field is actually present; never invents from online size.
local function tryGetGroupMemberCountLocal(groupId: number): (number?, boolean)
	local okInfo, info = pcall(function()
		return GroupService:GetGroupInfoAsync(groupId)
	end)
	if not okInfo or type(info) ~= "table" then
		return nil, false
	end
	local raw = (info :: any).MemberCount
	if type(raw) ~= "number" then
		raw = (info :: any).memberCount
	end
	if type(raw) == "number" and raw == raw and raw >= 0 then
		return math.floor(raw), true
	end
	return nil, false
end

local function extractEmblemUrlFromInfo(info: any): string?
	if type(info) ~= "table" then
		return nil
	end
	local raw: any = (info :: any).EmblemUrl
	if raw == nil then
		raw = (info :: any).emblemUrl
	end
	if type(raw) == "string" and raw ~= "" then
		return raw
	end
	return nil
end

local function groupIconThumbUrl(groupId: number): string
	return ("rbxthumb://type=GroupIcon&id=%d&w=150&h=150"):format(groupId)
end

-- JoinCommun-only: group emblem → Branding.LogoImage → leave GUI default.
local function tryGetGroupEmblemLocal(groupId: number): string?
	local okInfo, info = pcall(function()
		return GroupService:GetGroupInfoAsync(groupId)
	end)
	if not okInfo or type(info) ~= "table" then
		return nil
	end
	return extractEmblemUrlFromInfo(info) or groupIconThumbUrl(groupId)
end

local function setCommunityLogoImage(r: Refs, image: string, fromEmblem: boolean)
	if not r.communityLogo or image == "" then
		return
	end
	r.communityLogo.Image = image
	if fromEmblem then
		communityLogoFromEmblem = true
	end
end

local function applyCommunityLogoFallbacks(r: Refs)
	-- Soft Branding fallback only (no BrandLogoApplier sweep of JoinCommun tree).
	local logoAsset = BrandLogoApplier.resolveTargetLogo(Config)
	if logoAsset ~= "" and r.communityLogo then
		r.communityLogo.Image = logoAsset
	end
	-- else leave Studio GUI Image as-is
end

local function applyCommunityLogo(r: Refs, groupId: number)
	communityLogoFromEmblem = false
	local emblem = tryGetGroupEmblemLocal(groupId)
	if type(emblem) == "string" and emblem ~= "" then
		setCommunityLogoImage(r, emblem, true)
		return
	end
	-- Defer Branding fallback until after server sample (may carry proxy emblemUrl).
end

local function applyEmblemFromServerIfNeeded(r: Refs, emblemUrl: string?)
	if communityLogoFromEmblem then
		return
	end
	if type(emblemUrl) == "string" and emblemUrl ~= "" then
		setCommunityLogoImage(r, emblemUrl, true)
		return
	end
	applyCommunityLogoFallbacks(r)
end

local function clearThumbClones()
	for _, clone in ipairs(thumbClones) do
		if clone.Parent then
			clone:Destroy()
		end
	end
	table.clear(thumbClones)
end

-- Compact social counts: 999 | 1k | 1.2k | 10.6M | 1.2B
local function formatCompactCount(n: number): string
	local value = math.floor(math.max(0, n))
	if value < 1000 then
		return tostring(value)
	end

	local div: number
	local suffix: string
	if value >= 1000000000 then
		div = 1000000000
		suffix = "B"
	elseif value >= 1000000 then
		div = 1000000
		suffix = "M"
	else
		div = 1000
		suffix = "k"
	end

	local scaled = value / div
	if scaled >= 100 then
		return string.format("%d%s", math.floor(scaled + 0.5), suffix)
	end
	local tenths = math.floor(scaled * 10 + 0.5) / 10
	if tenths == math.floor(tenths) then
		return string.format("%d%s", math.floor(tenths), suffix)
	end
	return string.format("%.1f%s", tenths, suffix)
end

-- Badge remainder after 8 thumbs: +N up to +99 (never k/M/B on CounterLeft).
local function formatCounterExtra(extra: number): string
	local value = math.floor(math.max(0, extra))
	if value > 99 then
		return "+99"
	end
	return "+" .. tostring(value)
end

local function setCounterVisible(visible: boolean, extra: number?)
	local r = refs
	if not r or not r.counterLeft then
		return
	end
	if visible and type(extra) == "number" and extra > 0 then
		if r.counterLabel then
			r.counterLabel.Text = formatCounterExtra(extra)
		end
		r.counterLeft.Visible = true
	else
		r.counterLeft.Visible = false
	end
end

local function joinPromptCfg(): any
	local cfg = Config.JoinCommunityPrompt
	return if type(cfg) == "table" then cfg else {}
end

local function pickBodyEmptyWithCountTemplate(cfg: any): string
	local alts = cfg.BODY_EMPTY_WITH_COUNT_ALT
	if type(alts) == "table" and #alts > 0 then
		local pick = alts[math.random(1, #alts)]
		if type(pick) == "string" and pick ~= "" then
			return pick
		end
	end
	return tostring(cfg.BODY_EMPTY_WITH_COUNT or "Over %s players already joined.")
end

-- Subtitle stays qualitative (no huge number). Count lives in body once when no names.
local function formatSubtitle(memberCount: number, memberCountKnown: boolean, hasSampleNames: boolean): string
	local cfg = joinPromptCfg()
	if hasSampleNames then
		return tostring(cfg.SUBTITLE_WITH_SAMPLE or "Players already in this community.")
	end
	if memberCountKnown and memberCount > 0 then
		return tostring(cfg.SUBTITLE_WITH_COUNT or "Players already in this community.")
	end
	return tostring(cfg.SUBTITLE_FALLBACK or "Join players already here.")
end

local function formatBody(names: { string }, memberCount: number, memberCountKnown: boolean): string
	local cfg = joinPromptCfg()
	if #names == 0 then
		if memberCountKnown and memberCount > 0 then
			local template = pickBodyEmptyWithCountTemplate(cfg)
			return string.format(template, formatCompactCount(memberCount))
		end
		-- Only claim "first to join" when the real total is known to be zero.
		if memberCountKnown and memberCount == 0 then
			return tostring(cfg.BODY_EMPTY or "Be among the first to join this community.")
		end
		return tostring(cfg.BODY_NO_COUNT or "Join players already in this community.")
	end

	local listed = {}
	for i = 1, math.min(BODY_NAME_LIMIT, #names) do
		table.insert(listed, names[i])
	end

	local listedCount = #listed
	local remaining = if memberCountKnown then math.max(0, memberCount - listedCount) else 0
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

	-- "Name1, Name2, and Name3 and 10.6M others already joined this community."
	local listedJoined: string
	if listedCount == 1 then
		listedJoined = listed[1]
	elseif listedCount == 2 then
		listedJoined = listed[1] .. " and " .. listed[2]
	else
		listedJoined = string.format("%s, %s, and %s", listed[1], listed[2], listed[3])
	end
	local template = tostring(
		cfg.BODY_WITH_NAMES
			or cfg.BODY_WITH_EXTRA
			or "%s and %s others already joined this community."
	)
	return string.format(template, listedJoined, formatCompactCount(remaining))
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

local function applyCopy(memberCount: number, memberCountKnown: boolean, displayNames: { string })
	local r = refs
	if not r then
		return
	end
	applyHeadlineCopy()
	if r.subtitleLabel then
		r.subtitleLabel.Text = formatSubtitle(memberCount, memberCountKnown, #displayNames > 0)
	end
	if r.bodyLabel then
		r.bodyLabel.Text = formatBody(displayNames, memberCount, memberCountKnown)
	end
end

local function requestServerMembersAsync(groupId: number): {
	memberCount: number,
	memberCountKnown: boolean,
	emblemUrl: string?,
	members: { MemberSample },
}?
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
	local memberCountKnown = (payload :: any).memberCountKnown == true
	local emblemRaw = (payload :: any).emblemUrl
	local emblemUrl: string? = nil
	if type(emblemRaw) == "string" and emblemRaw ~= "" then
		emblemUrl = emblemRaw
	end
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
		memberCountKnown = memberCountKnown,
		emblemUrl = emblemUrl,
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

	-- Prefer random community roster (already joined), then fill with online in-group.
	for _, sample in ipairs(serverMembers) do
		tryAdd(sample)
	end
	for _, sample in ipairs(online) do
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
	-- Neutral loading copy — never flash "Be among the first..." before count resolves.
	applyCopy(0, false, {})

	-- Server-first (real MemberCount + bonus in-experience sample). Avoid N× IsInGroupAsync up front.
	local serverPayload = requestServerMembersAsync(groupId)
	if generation ~= fillGeneration or refs ~= r then
		return
	end

	local serverMembers: { MemberSample } = {}
	local memberCount = 0
	local memberCountKnown = false
	if serverPayload then
		serverMembers = serverPayload.members
		memberCount = serverPayload.memberCount
		memberCountKnown = serverPayload.memberCountKnown
		applyEmblemFromServerIfNeeded(r, serverPayload.emblemUrl)
	elseif not communityLogoFromEmblem then
		-- No server payload — Branding then GUI default.
		applyCommunityLogoFallbacks(r)
	end

	local online: { MemberSample } = {}
	if #serverMembers < MAX_THUMBNAILS then
		online = collectOnlineInGroup(groupId)
		if generation ~= fillGeneration or refs ~= r then
			return
		end
	end

	-- Client fallback for real total only — never use online/#thumbs as community size.
	if not memberCountKnown then
		local localCount, localKnown = tryGetGroupMemberCountLocal(groupId)
		if localKnown and type(localCount) == "number" then
			memberCount = localCount
			memberCountKnown = true
		end
	end

	local merged = mergeMemberSamples(online, serverMembers, localUserId)

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

	-- CounterLeft = remainder after 8 thumb slots (memberCount - 8), capped display +99.
	if memberCountKnown and memberCount > MAX_THUMBNAILS then
		setCounterVisible(true, memberCount - MAX_THUMBNAILS)
	else
		setCounterVisible(false)
	end

	local displayNames: { string } = {}
	for _, sample in ipairs(merged) do
		table.insert(displayNames, sample.displayName)
	end
	applyCopy(memberCount, memberCountKnown, displayNames)
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
	applyCommunityLogo(r, groupId)
	applyCopy(0, false, {})

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
