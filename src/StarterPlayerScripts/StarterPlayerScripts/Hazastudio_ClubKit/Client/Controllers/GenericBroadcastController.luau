--!strict
-- Presents 99-NotificationCenter > GenericBroadcast announcements.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local GenericBroadcastLayoutBridge = require(script.Parent.Parent.Services.GenericBroadcastLayoutBridge)

local log = Logger.new("GenericBroadcastController")

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

type Payload = {
	message: any,
	senderUserId: any,
	senderDisplayName: any,
	senderUsername: any,
	senderRole: any,
	senderRoleBadge: any,
	duration: any,
}

type Refs = {
	rootGui: ScreenGui,
	wrapper: CanvasGroup,
	template: CanvasGroup,
}

local ROOT_GUI_NAME = "99-NotificationCenter"
local WRAPPER_NAME = "GenericBroadcast"
local TEMPLATE_NAME = "BroadcastMessageTemplate"
local ENTER_DURATION = 0.28
local EXIT_DURATION = 0.22
local RESTACK_DURATION = 0.2
local NORMAL_SCALE = 0.9
local ENTER_START_SCALE = 0.84
local EXIT_SCALE = 0.81
local MAX_VISIBLE_CARDS = 3

type ActiveCard = {
	card: CanvasGroup,
	scale: UIScale,
	createdAt: number,
	dismissing: boolean,
}

local activeCards = {} :: { ActiveCard }
local basicWrapperPosition: UDim2? = nil
local basicWrapperAnchorPoint: Vector2? = nil

local function avatarHeadshot(userId: number): string
	return ("rbxthumb://type=AvatarHeadShot&id=%d&w=420&h=420"):format(userId)
end

local function findText(root: Instance, name: string): TextLabel?
	local found = root:FindFirstChild(name, true)
	return if found and found:IsA("TextLabel") then found else nil
end

local function findImage(root: Instance, name: string): ImageLabel?
	local found = root:FindFirstChild(name, true)
	return if found and found:IsA("ImageLabel") then found else nil
end

local function findFrame(root: Instance, name: string): GuiObject?
	local found = root:FindFirstChild(name, true)
	return if found and found:IsA("GuiObject") then found else nil
end

local function playEnterSound()
	local soundId = tostring(Config.Announcement.ENTER_SOUND_ID or "")
	if soundId == "" or soundId == "rbxassetid://0" then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "GenericBroadcastEnter"
	sound.SoundId = soundId
	sound.Volume = math.clamp(tonumber(Config.Announcement.ENTER_SOUND_VOLUME) or 0.65, 0, 1)
	sound.RollOffMaxDistance = 0
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	local lifetime = sound.TimeLength
	Debris:AddItem(sound, if lifetime > 0 then lifetime + 1 else 8)
end

local function colorFromHex(hex: string): Color3?
	local value = string.gsub(hex, "#", "")
	if #value ~= 6 then
		return nil
	end

	local r = tonumber(string.sub(value, 1, 2), 16)
	local g = tonumber(string.sub(value, 3, 4), 16)
	local b = tonumber(string.sub(value, 5, 6), 16)
	if not r or not g or not b then
		return nil
	end

	return Color3.fromRGB(r, g, b)
end

local function getRoleAccentColor(role: string): Color3
	local palette = Config.RoleColorPalette
	local rolePalette = if type(palette) == "table" then palette[role] or palette.Member else nil
	local rawColor = if type(rolePalette) == "table" then rolePalette.primary else nil
	if rawColor == nil then
		local roleColors = Config.ChatPrimaryTagColor
		rawColor = if type(roleColors) == "table" then roleColors[role] or roleColors.Member else nil
	end
	if type(rawColor) == "string" then
		return colorFromHex(rawColor) or Color3.fromRGB(77, 132, 255)
	end
	if typeof(rawColor) == "Color3" then
		return rawColor
	end
	return Color3.fromRGB(77, 132, 255)
end

local function getRoleSecondaryColor(role: string, primary: Color3): Color3
	local palette = Config.RoleColorPalette
	local rolePalette = if type(palette) == "table" then palette[role] or palette.Member else nil
	local rawColor = if type(rolePalette) == "table" then rolePalette.secondary else nil
	if type(rawColor) == "string" then
		return colorFromHex(rawColor) or primary:Lerp(Color3.new(0, 0, 0), 0.22)
	end
	if typeof(rawColor) == "Color3" then
		return rawColor
	end
	return primary:Lerp(Color3.new(0, 0, 0), 0.22)
end

local function applyCountDownBarAccent(countDownBar: GuiObject, role: string)
	local accent = getRoleAccentColor(role)
	local secondary = getRoleSecondaryColor(role, accent)
	local gradient = countDownBar:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Parent = countDownBar
	end

	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, accent),
		ColorSequenceKeypoint.new(1, secondary),
	})
	gradient.Rotation = 0
	gradient.Enabled = true
	countDownBar.BackgroundColor3 = accent
end

local function resolveRefs(): Refs?
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end

	local rootGui = playerGui:FindFirstChild(ROOT_GUI_NAME)
	if not rootGui then
		rootGui = playerGui:WaitForChild(ROOT_GUI_NAME, 10)
	end
	if not rootGui or not rootGui:IsA("ScreenGui") then
		log:warn("99-NotificationCenter not found")
		return nil
	end

	local wrapper = rootGui:FindFirstChild(WRAPPER_NAME)
	if not wrapper or not wrapper:IsA("CanvasGroup") then
		log:warn("GenericBroadcast wrapper not found")
		return nil
	end

	local template = wrapper:FindFirstChild(TEMPLATE_NAME)
	if not template or not template:IsA("CanvasGroup") then
		log:warn("BroadcastMessageTemplate not found")
		return nil
	end

	template.Visible = false
	return {
		rootGui = rootGui,
		wrapper = wrapper,
		template = template,
	}
end

local function tween(instance: Instance, info: TweenInfo, goals: { [string]: any }): Tween
	local created = TweenService:Create(instance, info, goals)
	created:Play()
	return created
end

local function tweenWait(instance: Instance, info: TweenInfo, goals: { [string]: any })
	local created = tween(instance, info, goals)
	created.Completed:Wait()
end

local function normalizePayload(raw: any): Payload?
	if type(raw) ~= "table" then
		return nil
	end
	if type(raw.message) ~= "string" or raw.message == "" then
		return nil
	end
	return raw :: Payload
end

local function fillCard(card: CanvasGroup, payload: Payload)
	local userId = tonumber(payload.senderUserId) or 0
	local displayName = tostring(payload.senderDisplayName or "Unknown")
	local username = tostring(payload.senderUsername or "unknown")
	local role = tostring(payload.senderRole or "Member")
	local roleBadge = tostring(payload.senderRoleBadge or "")

	local senderLabel = findText(card, "SenderNameandUsername")
	if senderLabel then
		senderLabel.Text = ("%s @%s :"):format(displayName, username)
	end

	local messageLabel = findText(card, "TheMessage")
	if messageLabel then
		messageLabel.Text = tostring(payload.message)
	end

	local profileImage = findImage(card, "SenderProfileImage")
	if profileImage then
		profileImage.Image = if userId > 0 then avatarHeadshot(userId) else ""
	end

	local roleImage = findImage(card, "SenderRole")
	if roleImage then
		roleImage.Image = roleBadge
		roleImage.Visible = roleBadge ~= ""
	end

	card:SetAttribute("SenderRole", role)
end

local function hasActiveBroadcastCard(wrapper: CanvasGroup): boolean
	for _, child in ipairs(wrapper:GetChildren()) do
		if child.Name == "BroadcastMessage" and child:IsA("GuiObject") then
			return true
		end
	end
	return false
end

local function removeActive(active: ActiveCard)
	local index = table.find(activeCards, active)
	if index then
		table.remove(activeCards, index)
	end
end

local function setCardContentVisible(card: CanvasGroup, visible: boolean)
	for _, child in ipairs(card:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "CountDownBar" then
			child.Visible = visible
		end
	end
end

local function captureBasicWrapperLayout(wrapper: CanvasGroup)
	basicWrapperPosition = wrapper.Position
	basicWrapperAnchorPoint = wrapper.AnchorPoint
end

local function applyWrapperLayoutForDonation(active: boolean)
	local refs = resolveRefs()
	if not refs then
		return
	end
	local wrapper = refs.wrapper
	if active then
		wrapper.AnchorPoint = Config.Announcement.BROADCAST_WRAPPER_ANCHOR_DURING_DONATION
		wrapper.Position = Config.Announcement.BROADCAST_WRAPPER_POSITION_DURING_DONATION
		return
	end
	if basicWrapperPosition then
		wrapper.Position = basicWrapperPosition
	end
	if basicWrapperAnchorPoint then
		wrapper.AnchorPoint = basicWrapperAnchorPoint
	end
end

local function restackActiveCards()
	for index, active in ipairs(activeCards) do
		if active.card.Parent and not active.dismissing then
			active.card.LayoutOrder = index
			setCardContentVisible(active.card, true)
			tween(active.scale, TweenInfo.new(RESTACK_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Scale = NORMAL_SCALE,
			})
		end
	end
end

local function dismissCard(refs: Refs, active: ActiveCard)
	if active.dismissing then
		return
	end
	active.dismissing = true
	removeActive(active)
	restackActiveCards()

	local card = active.card
	local scale = active.scale
	if card.Parent then
		tween(card, TweenInfo.new(EXIT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			GroupTransparency = 1,
		})
		tweenWait(scale, TweenInfo.new(EXIT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Scale = EXIT_SCALE,
		})
		card:Destroy()
	end

	if not hasActiveBroadcastCard(refs.wrapper) then
		refs.wrapper.Visible = false
	end
end

local function trimVisibleCards(refs: Refs)
	while #activeCards > MAX_VISIBLE_CARDS do
		dismissCard(refs, activeCards[1])
	end
end

local function playBroadcast(refs: Refs, payload: Payload)
	local wrapper = refs.wrapper
	local card = refs.template:Clone()
	card.Name = "BroadcastMessage"
	card.Visible = true
	card.GroupTransparency = 1
	card.LayoutOrder = os.clock() * 1000
	card.Parent = wrapper
	fillCard(card, payload)

	local scale = card:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = card
	end
	scale.Scale = ENTER_START_SCALE

	local countDownBar = findFrame(card, "CountDownBar")
	if countDownBar then
		countDownBar.Size = UDim2.new(1, 0, countDownBar.Size.Y.Scale, countDownBar.Size.Y.Offset)
		applyCountDownBarAccent(countDownBar, tostring(payload.senderRole or "Member"))
	end

	local active = {
		card = card,
		scale = scale,
		createdAt = os.clock(),
		dismissing = false,
	}
	table.insert(activeCards, active)

	wrapper.Visible = true
	restackActiveCards()
	trimVisibleCards(refs)
	playEnterSound()

	tween(card, TweenInfo.new(ENTER_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		GroupTransparency = 0,
	})
	tweenWait(scale, TweenInfo.new(ENTER_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = NORMAL_SCALE,
	})
	restackActiveCards()

	local duration = math.max(tonumber(payload.duration) or Config.Announcement.SHOW_DURATION, 1)
	if countDownBar then
		tween(countDownBar, TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 0, countDownBar.Size.Y.Scale, countDownBar.Size.Y.Offset),
		})
	end

	task.spawn(function()
		task.wait(duration)
		dismissCard(refs, active)
	end)
end

local function presentPayload(payload: Payload)
	local refs = resolveRefs()
	if not refs then
		return
	end

	local ok, err = xpcall(function()
		playBroadcast(refs, payload)
	end, debug.traceback)
	if not ok then
		log:warn("Generic broadcast presenter failed", {
			error = tostring(err),
		})
	end
end

local function clearActiveCards()
	for index = #activeCards, 1, -1 do
		local active = activeCards[index]
		if active.card.Parent then
			active.card:Destroy()
		end
		table.remove(activeCards, index)
	end
end

local GenericBroadcastController = {}

function GenericBroadcastController.init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	if not remotes then
		log:warn("Remotes folder not found")
		return
	end

	local remote = remotes:WaitForChild(Config.Announcement.REMOTE_BROADCAST, 15) :: RemoteEvent?
	if not remote then
		log:warn("GenericBroadcast remote not found")
		return
	end

	local refs = resolveRefs()
	if refs then
		captureBasicWrapperLayout(refs.wrapper)
		clearActiveCards()
		refs.wrapper.Visible = false
		refs.template.Visible = false
	end

	GenericBroadcastLayoutBridge.subscribe(function(donationActive: boolean)
		applyWrapperLayoutForDonation(donationActive)
	end)

	track(remote.OnClientEvent:Connect(function(raw: any)
		local payload = normalizePayload(raw)
		if not payload then
			return
		end
		-- Hide flag: respect user's SettingsHideAdminAnnounce preference.
		-- Sebelumnya admin /announce bypass notification center jadi flag
		-- SettingsHideAdminAnnounce tidak pernah di-check → toggle di settings
		-- menu tidak ada efek.
		if Players.LocalPlayer:GetAttribute("SettingsHideAdminAnnounce") == true then
			return
		end
		task.spawn(presentPayload, payload)
	end))

	log:info("GenericBroadcastController initialized")
end

function GenericBroadcastController.destroy()
	destroy()
end

return GenericBroadcastController
