--!strict
-- Presents 99-NotificationCenter > GreetingNotifications join greetings.
-- Enter/exit + CountDownBar follow GenericBroadcastController (UIScale + GroupTransparency).
-- Message sequence (creative → fade → Welcome back) keeps TextTransparency crossfade
-- (same family as DonationNotificationController content fades) — no abrupt Visible toggles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

local log = Logger.new("JoinGreetingController")

local _connections: { RBXScriptConnection } = {}
local missingGuiWarned = false

local function track(conn: RBXScriptConnection): RBXScriptConnection
	table.insert(_connections, conn)
	return conn
end

local function destroyConnections()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)
end

type Payload = {
	userId: any,
	displayName: any,
	username: any,
	roleKey: any,
	categoryKind: any,
	chipText: any,
	message: any,
	roleBadge: any,
	rank: any,
	messageHold: any,
	messageFade: any,
	welcomeHold: any,
	exitDuration: any,
	enterDuration: any,
	duration: any,
}

type Refs = {
	rootGui: ScreenGui,
	wrapper: GuiObject,
	template: CanvasGroup,
}

-- Mirror GenericBroadcastController toast motion constants.
local ROOT_GUI_NAME = "99-NotificationCenter"
local WRAPPER_NAME = "GreetingNotifications"
local TEMPLATE_NAME = "GeneralGreetings"
local ENTER_DURATION = 0.28
local EXIT_DURATION = 0.22
local ENTER_START_SCALE = 0.84
local NORMAL_SCALE = 0.9
local EXIT_SCALE = 0.81

type ActiveCard = {
	card: CanvasGroup,
	scale: UIScale,
	dismissing: boolean,
}

local activeCards = {} :: { ActiveCard }
local presentQueue = {} :: { Payload }
local presenting = false
-- Hold until loading click + cinematic reveal finish (`enterGameplay` / notifyGameplayReady).
local gameplayReady = false
local heldUntilGameplay: { Payload } = {}
-- Belt-and-suspenders: ignore duplicate remotes for the same joiner this client session.
local seenGreetingUserIds: { [number]: boolean } = {}

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

local function tween(instance: Instance, info: TweenInfo, goals: { [string]: any }): Tween
	local created = TweenService:Create(instance, info, goals)
	created:Play()
	return created
end

local function tweenWait(instance: Instance, info: TweenInfo, goals: { [string]: any })
	local created = tween(instance, info, goals)
	created.Completed:Wait()
end

local function getCfg(): any
	return Config.JoinGreeting or {}
end

local function maxVisibleCards(): number
	return math.max(1, tonumber(getCfg().MAX_VISIBLE_CARDS) or 2)
end

-- Role accent helpers — same approach as GenericBroadcastController.
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
		if not missingGuiWarned then
			missingGuiWarned = true
			log:warn("99-NotificationCenter not found")
		end
		return nil
	end

	local wrapper = rootGui:FindFirstChild(WRAPPER_NAME)
	if not wrapper or not wrapper:IsA("GuiObject") then
		if not missingGuiWarned then
			missingGuiWarned = true
			log:warn("GreetingNotifications wrapper not found")
		end
		return nil
	end

	local template = wrapper:FindFirstChild(TEMPLATE_NAME)
	if not template or not template:IsA("CanvasGroup") then
		if not missingGuiWarned then
			missingGuiWarned = true
			log:warn("GeneralGreetings template must be a CanvasGroup (same as BroadcastMessageTemplate)")
		end
		return nil
	end

	template.Visible = false
	return {
		rootGui = rootGui,
		wrapper = wrapper,
		template = template,
	}
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

local function buildWelcomeText(payload: Payload): string
	local displayName = tostring(payload.displayName or "Unknown")
	local kind = tostring(payload.categoryKind or "")
	if kind == "Owner" then
		local prefix = tostring(getCfg().WELCOME_OWNER_PREFIX or "owner")
		return ("Welcome back, %s %s"):format(prefix, displayName)
	end
	return ("Welcome back, %s"):format(displayName)
end

local function fillCard(card: CanvasGroup, payload: Payload)
	local userId = tonumber(payload.userId) or 0
	local displayName = tostring(payload.displayName or "Unknown")
	local username = tostring(payload.username or "unknown")
	local chipText = tostring(payload.chipText or "")
	local roleBadge = tostring(payload.roleBadge or "")
	local message = tostring(payload.message or "")

	local displayLabel = findText(card, "SenderDisplayName")
	if displayLabel then
		displayLabel.Text = displayName
	end

	local usernameLabel = findText(card, "SenderUsername")
	if usernameLabel then
		usernameLabel.Text = "@" .. username
	end

	local chipLabel = findText(card, "Versatilechiptext")
	if chipLabel then
		chipLabel.Text = chipText
	end

	local messageLabel = findText(card, "Message")
	if messageLabel then
		messageLabel.Text = message
		messageLabel.TextTransparency = 0
	end

	local profileImage = findImage(card, "Profpic")
	if profileImage then
		local ok, err = pcall(function()
			profileImage.Image = if userId > 0 then avatarHeadshot(userId) else ""
		end)
		if not ok then
			log:warn("Failed to set greeting profpic", { error = tostring(err) })
			profileImage.Image = ""
		end
	end

	local roleImage = findImage(card, "RoleBadge")
	if roleImage then
		roleImage.Image = roleBadge
		roleImage.Visible = roleBadge ~= ""
	end

	card:SetAttribute("SenderRole", tostring(payload.roleKey or "Member"))
end

local function removeActive(active: ActiveCard)
	local index = table.find(activeCards, active)
	if index then
		table.remove(activeCards, index)
	end
end

local function hasActiveCards(wrapper: GuiObject): boolean
	for _, child in ipairs(wrapper:GetChildren()) do
		if child.Name == "GreetingCard" and child:IsA("GuiObject") then
			return true
		end
	end
	return false
end

local function setWrapperVisible(refs: Refs, visible: boolean)
	refs.wrapper.Visible = visible
end

local function dismissCard(refs: Refs, active: ActiveCard, exitDuration: number)
	if active.dismissing then
		return
	end
	active.dismissing = true
	removeActive(active)

	local card = active.card
	local scale = active.scale
	if not card.Parent then
		if not hasActiveCards(refs.wrapper) then
			setWrapperVisible(refs, false)
		end
		return
	end

	-- Same exit family as GenericBroadcast: GroupTransparency + scale shrink.
	local exitInfo = TweenInfo.new(exitDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(card, exitInfo, { GroupTransparency = 1 })
	tweenWait(scale, exitInfo, { Scale = EXIT_SCALE })

	if card.Parent then
		card:Destroy()
	end

	if not hasActiveCards(refs.wrapper) then
		setWrapperVisible(refs, false)
	end
end

local function playGreeting(refs: Refs, payload: Payload)
	local wrapper = refs.wrapper
	local card = refs.template:Clone()
	card.Name = "GreetingCard"
	card.Visible = true
	card.GroupTransparency = 1
	card.Parent = wrapper
	fillCard(card, payload)

	local scale = card:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = card
	end
	scale.Scale = ENTER_START_SCALE

	local enterDuration = math.max(tonumber(payload.enterDuration) or getCfg().ENTER or ENTER_DURATION, 0.05)
	local messageHold = math.max(tonumber(payload.messageHold) or getCfg().MESSAGE_HOLD or 8.0, 0.1)
	local messageFade = math.max(tonumber(payload.messageFade) or getCfg().MESSAGE_FADE or 0.35, 0.05)
	local welcomeHold = math.max(tonumber(payload.welcomeHold) or getCfg().WELCOME_HOLD or 6.3, 0.1)
	local exitDuration = math.max(tonumber(payload.exitDuration) or getCfg().EXIT or EXIT_DURATION, 0.05)
	-- Show window only (bar depletes, then exit anim — same order as GenericBroadcast/Donation).
	local showDuration = messageHold + (messageFade * 2) + welcomeHold

	local countDownBar = findFrame(card, "CountDownBar")
	if countDownBar then
		countDownBar.Size = UDim2.new(1, 0, countDownBar.Size.Y.Scale, countDownBar.Size.Y.Offset)
		applyCountDownBarAccent(countDownBar, tostring(payload.roleKey or "Member"))
	end

	local active: ActiveCard = {
		card = card,
		scale = scale,
		dismissing = false,
	}
	table.insert(activeCards, active)

	while #activeCards > maxVisibleCards() do
		local oldest = activeCards[1]
		if oldest then
			dismissCard(refs, oldest, exitDuration)
		else
			break
		end
	end

	setWrapperVisible(refs, true)

	-- Enter: GroupTransparency 1→0 + scale ENTER_START→NORMAL (GenericBroadcast).
	local enterInfo = TweenInfo.new(enterDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	tween(card, enterInfo, { GroupTransparency = 0 })
	tweenWait(scale, enterInfo, { Scale = NORMAL_SCALE })

	if countDownBar then
		tween(countDownBar, TweenInfo.new(showDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 0, countDownBar.Size.Y.Scale, countDownBar.Size.Y.Offset),
		})
	end

	local messageLabel = findText(card, "Message")
	task.wait(messageHold)

	if active.dismissing or not card.Parent then
		return
	end

	-- Crossfade creative → Welcome back via TextTransparency (not Visible toggles).
	if messageLabel then
		local fadeInfo = TweenInfo.new(messageFade, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		tweenWait(messageLabel, fadeInfo, { TextTransparency = 1 })
		if active.dismissing or not card.Parent then
			return
		end
		messageLabel.Text = buildWelcomeText(payload)
		tweenWait(messageLabel, fadeInfo, { TextTransparency = 0 })
	else
		task.wait(messageFade * 2)
	end

	if active.dismissing or not card.Parent then
		return
	end

	task.wait(welcomeHold)
	dismissCard(refs, active, exitDuration)
end

local function pumpQueue()
	if presenting then
		return
	end
	presenting = true

	while #presentQueue > 0 do
		local payload = table.remove(presentQueue, 1)
		if not payload then
			break
		end
		local refs = resolveRefs()
		if not refs then
			break
		end
		local ok, err = xpcall(function()
			playGreeting(refs, payload)
		end, debug.traceback)
		if not ok then
			log:warn("Join greeting presenter failed", {
				error = tostring(err),
			})
		end
	end

	presenting = false
end

local function claimGreetingUserId(payload: Payload): boolean
	local userId = tonumber(payload.userId)
	if not userId or userId <= 0 then
		return true
	end
	if seenGreetingUserIds[userId] then
		return false
	end
	seenGreetingUserIds[userId] = true
	return true
end

local function presentPayload(payload: Payload)
	if not claimGreetingUserId(payload) then
		return
	end
	if not gameplayReady then
		table.insert(heldUntilGameplay, payload)
		return
	end
	table.insert(presentQueue, payload)
	task.spawn(pumpQueue)
end

local function flushHeldUntilGameplay()
	if #heldUntilGameplay == 0 then
		return
	end
	local held = heldUntilGameplay
	heldUntilGameplay = {}
	for _, payload in ipairs(held) do
		table.insert(presentQueue, payload)
	end
	task.spawn(pumpQueue)
end

local function clearActiveCards()
	for index = #activeCards, 1, -1 do
		local active = activeCards[index]
		if active.card.Parent then
			active.card:Destroy()
		end
		table.remove(activeCards, index)
	end
	table.clear(presentQueue)
	table.clear(heldUntilGameplay)
	table.clear(seenGreetingUserIds)
end

local JoinGreetingController = {}

-- Called from Main.client enterGameplay after loading dismiss + camera reveal.
function JoinGreetingController.notifyGameplayReady()
	if gameplayReady then
		return
	end
	gameplayReady = true
	flushHeldUntilGameplay()
end

function JoinGreetingController.init()
	if Config.FeatureFlags.JoinGreetingsEnabled ~= true then
		log:info("JoinGreetingController skipped (feature disabled)")
		return
	end

	local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	if not remotes then
		log:warn("Remotes folder not found")
		return
	end

	local remoteName = tostring((Config.JoinGreeting and Config.JoinGreeting.REMOTE) or "JoinGreeting")
	local remote = remotes:WaitForChild(remoteName, 15) :: RemoteEvent?
	if not remote then
		log:warn("JoinGreeting remote not found")
		return
	end

	local refs = resolveRefs()
	if refs then
		clearActiveCards()
		refs.wrapper.Visible = false
		refs.template.Visible = false
	end

	track(remote.OnClientEvent:Connect(function(raw: any)
		local payload = normalizePayload(raw)
		if not payload then
			return
		end
		presentPayload(payload)
	end))

	-- If enterGameplay already ran before init (no loading / early finish), flush now.
	if gameplayReady then
		flushHeldUntilGameplay()
	end

	log:info("JoinGreetingController initialized", {
		gameplayReady = gameplayReady,
	})
end

function JoinGreetingController.destroy()
	clearActiveCards()
	destroyConnections()
end

return JoinGreetingController
