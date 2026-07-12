--!strict
-- After loading/gameplay entry, show custom 16-JoinCommunPrompt (once per session),
-- then CoreGui PromptJoinAsync only when the player clicks Join.
-- Center-modal motion: AnimationHelper presentCenterPanel / dismissCenterPanel
-- (same family as ShopUI / GiftUI / PaidBroadcastUI — scale 0.96↔1 + PanelBlur + FOV zoom).

local GroupService = game:GetService("GroupService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)

local log = Logger.new("JoinCommunityPrompt")

local PROMPT_DELAY_SEC = 2
local GUI_WAIT_TIMEOUT = 8
local ROOT_GUI_NAME = "16-JoinCommunPrompt"
local MAX_THUMBNAILS = 8

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

type Refs = {
	root: ScreenGui,
	mainWrapper: Frame,
	closeButton: GuiButton,
	joinButton: GuiButton,
	thumbnailHost: Frame?,
	thumbnailTemplate: ImageLabel?,
	counterLeft: GuiObject?,
	counterLabel: TextLabel?,
}

local refs: Refs? = nil
local thumbClones: { ImageLabel } = {}

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

local function tryGetGroupMemberCount(groupId: number): number?
	local okInfo, info = pcall(function()
		return GroupService:GetGroupInfoAsync(groupId)
	end)
	if okInfo and type(info) == "table" then
		local count = (info :: any).MemberCount or (info :: any).memberCount
		if type(count) == "number" and count > 0 then
			return count
		end
	end

	local okHttp, body = pcall(function()
		return HttpService:GetAsync("https://groups.roblox.com/v1/groups/" .. tostring(groupId))
	end)
	if okHttp and type(body) == "string" and body ~= "" then
		local okJson, decoded = pcall(function()
			return HttpService:JSONDecode(body)
		end)
		if okJson and type(decoded) == "table" then
			local count = (decoded :: any).memberCount
			if type(count) == "number" and count > 0 then
				return count
			end
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
		thumbnailHost = if thumbnailHost and thumbnailHost:IsA("Frame") then thumbnailHost :: Frame else nil,
		thumbnailTemplate = thumbnailTemplate,
		counterLeft = counterLeft,
		counterLabel = counterLabel,
	}
end

local function fillMemberThumbnailsAsync(groupId: number)
	local r = refs
	if not r or not r.thumbnailHost or not r.thumbnailTemplate then
		return
	end

	local host = r.thumbnailHost
	local template = r.thumbnailTemplate
	template.Visible = false
	setCounterVisible(false)
	clearThumbClones()

	local userIds: { number } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if #userIds >= MAX_THUMBNAILS then
			break
		end
		if isPlayerInGroupAsync(player, groupId) then
			table.insert(userIds, player.UserId)
		end
	end

	for index, userId in ipairs(userIds) do
		local clone = template:Clone()
		clone.Name = "PlayerProfileThumbnail_" .. tostring(index)
		clone.Image = headshotUrl(userId)
		clone.Visible = true
		clone.LayoutOrder = index
		clone.Parent = host
		table.insert(thumbClones, clone)
	end

	local memberCount = tryGetGroupMemberCount(groupId)
	if type(memberCount) == "number" and memberCount > MAX_THUMBNAILS then
		setCounterVisible(true, memberCount - MAX_THUMBNAILS)
	else
		setCounterVisible(false)
	end
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

	wireButtons(groupId)

	isOpen = true
	isClosing = false
	anim:presentCenterPanel(r.mainWrapper, nil, MODAL_BLUR_OPTIONS)

	-- Thumbnails / member count are best-effort and must not block open.
	task.spawn(function()
		fillMemberThumbnailsAsync(groupId)
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
