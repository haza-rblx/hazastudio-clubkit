--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local PermissionDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.PermissionDomain)
local CinematicCameraModes = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.CinematicCameraModes)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local CinematicCameraSystem = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.CinematicCameraSystem)
local DonationExperiencePrefs = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DonationExperiencePrefs)
local OverheadController = require(script.Parent.OverheadController)
local MobilePanelManager = require(script.Parent.Parent.Services.MobilePanelManager)

local log = Logger.new("Client.CinematicDockController")

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

type TargetOption = {
	type: string,
	name: string,
	id: string?,
	userId: number?,
	path: { string }?,
}

type MovementOption = {
	label: string,
	value: string,
	targetType: string,
}

-- Source movement list dari Config supaya server & client sinkron.
local MOVEMENT_OPTIONS_ALL: { MovementOption } = Config.CinematicDock.MOVEMENT_OPTIONS :: any

local FILTER_ROW_NAMES: { [string]: boolean } = {
	FavoritedState = true,
	FavoritedStateandPlayed = true,
	NormalState = true,
	PlayedState = true,
}

local FAVORITE_MOVEMENTS_ATTR = "CinematicDockFavoriteMovements"
local FAVORITE_TARGETS_ATTR = "CinematicDockFavoriteTargets"

type StateTemplateSet = {
	normal: GuiButton,
	favorited: GuiButton,
	played: GuiButton,
	favoritedPlayed: GuiButton,
	filterButtons: { GuiButton },
}

local function readFavoriteMap(attributeName: string): { [string]: boolean }
	local player = Players.LocalPlayer
	if not player then
		return {}
	end
	local raw = player:GetAttribute(attributeName)
	if type(raw) ~= "string" or raw == "" then
		return {}
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not ok or type(decoded) ~= "table" then
		return {}
	end
	local map: { [string]: boolean } = {}
	for key, value in pairs(decoded) do
		if type(key) == "string" and value == true then
			map[key] = true
		end
	end
	return map
end

local function writeFavoriteMap(attributeName: string, map: { [string]: boolean })
	local player = Players.LocalPlayer
	if not player then
		return
	end
	player:SetAttribute(attributeName, HttpService:JSONEncode(map))
end

local function getTargetKey(target: TargetOption): string
	if target.type == "player" then
		return "player:" .. tostring(target.userId or "")
	end
	return "cctv:" .. table.concat(target.path or {}, "/")
end

local function getTargetKeyFromRaw(target: any): string
	if type(target) ~= "table" then
		return ""
	end
	if target.type == "player" then
		return "player:" .. tostring(target.userId or "")
	end
	return "cctv:" .. table.concat(target.path or {}, "/")
end

local selectedMovement: string? = nil
local selectedMovementLabel: string? = nil
local selectedSpeed: number? = 1
local selectedTarget: TargetOption? = nil
local currentBarsGui: ScreenGui? = nil
local broadcastBound = false
local hideBars: () -> () = function() end
local operatorBroadcasting = false
local handleOperatorBroadcastEnded: (() -> ())? = nil

local function shouldShowViewerCinematicChrome(raw: any): boolean
	if type(raw) ~= "table" or raw.type ~= "play" then
		return false
	end
	local by = raw.by
	if type(by) ~= "string" or by == "" then
		return false
	end
	-- Donation / system auto-focus keeps letterbox + skip hint for viewers.
	return string.sub(by, 1, 1) == "["
end

-- Filter movement list: player -> character modes; CCTV wall -> part;
-- 360 venue rig -> part360 only (wide FOV family).
local function filterMovementOptions(target: TargetOption?): { MovementOption }
	local is360Cctv = CinematicCameraModes.is360CctvTarget(target)
	local mapped: string? = if target then target.type else nil
	if mapped == "player" then
		mapped = "character"
	elseif mapped == "cctv" then
		mapped = if is360Cctv then "part360" else "part"
	end
	local effectiveType = mapped or "character"
	local filtered = {}
	for _, option in ipairs(MOVEMENT_OPTIONS_ALL) do
		if option.targetType == "any" or option.targetType == effectiveType then
			table.insert(filtered, option)
		end
	end
	return filtered
end

type DockButtonState = {
	button: GuiObject,
	scale: UIScale,
	baseScale: number,
	currentScale: number,
}

local function ensureScale(guiObject: GuiObject): UIScale
	local scale = guiObject:FindFirstChildOfClass("UIScale")
	if scale then
		return scale
	end
	local created = Instance.new("UIScale")
	created.Scale = 1
	created.Parent = guiObject
	return created
end

local function tween(instance: Instance, info: TweenInfo, goals: { [string]: any }): Tween
	local created = TweenService:Create(instance, info, goals)
	created:Play()
	return created
end

local function findText(root: Instance, name: string): TextLabel?
	local found = root:FindFirstChild(name, true)
	return if found and found:IsA("TextLabel") then found else nil
end

local function findButton(root: Instance, name: string): GuiButton?
	local found = root:FindFirstChild(name, true)
	return if found and found:IsA("GuiButton") then found else nil
end

local function getPanelMainContent(panel: Instance): ScrollingFrame?
	for _, descendant in ipairs(panel:GetDescendants()) do
		if descendant.Name == "MainContent" and descendant:IsA("ScrollingFrame") then
			return descendant
		end
	end
	return nil
end

local function collectFilterButtons(content: ScrollingFrame): { GuiButton }
	local buttons: { GuiButton } = {}
	for name in pairs(FILTER_ROW_NAMES) do
		local child = content:FindFirstChild(name, true)
		if child and child:IsA("GuiButton") then
			table.insert(buttons, child)
		end
	end
	table.sort(buttons, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	return buttons
end

local function setFilterRowHighlight(filters: { GuiButton }, active: GuiButton?)
	local activeBg = Color3.fromRGB(65, 65, 65)
	local idleBg = Color3.fromRGB(22, 22, 22)
	for _, button in ipairs(filters) do
		if button == active then
			button.BackgroundColor3 = activeBg
		else
			button.BackgroundColor3 = idleBg
		end
	end
end

local function findRowStyleTemplate(content: ScrollingFrame, name: string): GuiButton?
	-- Template row styles are direct children of MainContent (same as DancePanelGuiRefs).
	local child = content:FindFirstChild(name)
	if child and child:IsA("GuiButton") then
		return child
	end
	return nil
end

local function collectStateTemplateSet(content: ScrollingFrame): StateTemplateSet?
	local normal = findRowStyleTemplate(content, "NormalState")
	local favorited = findRowStyleTemplate(content, "FavoritedState")
	local played = findRowStyleTemplate(content, "PlayedState")
	local favoritedPlayed = findRowStyleTemplate(content, "FavoritedStateandPlayed")
	if not (normal and favorited and played and favoritedPlayed) then
		return nil
	end
	if not (normal:IsA("GuiButton") and favorited:IsA("GuiButton") and played:IsA("GuiButton") and favoritedPlayed:IsA("GuiButton")) then
		return nil
	end
	return {
		normal = normal,
		favorited = favorited,
		played = played,
		favoritedPlayed = favoritedPlayed,
		filterButtons = collectFilterButtons(content),
	}
end

-- Cinematic dock row styles: NormalState = selected highlight, PlayedState = default/history row.
-- (Dance panel uses the opposite node names; do not copy that mapping here.)
local function pickRowTemplate(
	set: StateTemplateSet,
	isFavorited: boolean,
	isPlayed: boolean,
	isSelected: boolean
): GuiButton
	if isFavorited and isSelected then
		return set.favoritedPlayed
	end
	if isFavorited then
		return set.favorited
	end
	if isSelected then
		return set.normal
	end
	if isPlayed then
		return set.played
	end
	return set.played
end

local function passesListFilter(filterMode: string, isFavorited: boolean, isPlayed: boolean, isActive: boolean): boolean
	if filterMode == "FavoritedState" then
		return isFavorited
	end
	if filterMode == "PlayedState" then
		return isPlayed or isActive
	end
	if filterMode == "FavoritedStateandPlayed" then
		return isFavorited and (isPlayed or isActive)
	end
	return true
end

local function getFavoriteButton(row: GuiButton): ImageButton?
	local button = row:FindFirstChild("2-ImageButton", true)
	return if button and button:IsA("ImageButton") then button else nil
end

local function syncFavoriteBadge(row: GuiButton, isFavorited: boolean)
	local badge = row:FindFirstChild("Badge", true)
	if badge and badge:IsA("ImageLabel") then
		badge.ImageTransparency = if isFavorited then 0 else 0.8
	end
end

local function buildKeepRowsForTemplateSet(set: StateTemplateSet): { [Instance]: boolean }
	local keep: { [Instance]: boolean } = {
		[set.normal] = true,
		[set.favorited] = true,
		[set.played] = true,
		[set.favoritedPlayed] = true,
	}
	set.normal.Visible = false
	set.favorited.Visible = false
	set.played.Visible = false
	set.favoritedPlayed.Visible = false
	for _, filterButton in ipairs(set.filterButtons) do
		keep[filterButton] = true
	end
	return keep
end

local function setButtonLabel(button: Instance?, text: string)
	if button and button:IsA("GuiButton") then
		local label = button:FindFirstChildWhichIsA("TextLabel", true)
		if label then
			label.Text = text
		elseif button:IsA("TextButton") then
			button.Text = text
		end
	end
end

local PANEL_BASE_SCALE = 0.8

local function setPanelVisible(panel: CanvasGroup?, visible: boolean)
	if not panel then
		return
	end
	panel.Visible = visible
	local scale = ensureScale(panel)
	if visible then
		panel.GroupTransparency = 1
		scale.Scale = PANEL_BASE_SCALE * 0.94
		tween(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			GroupTransparency = 0,
		})
		tween(scale, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Scale = PANEL_BASE_SCALE,
		})
	else
		panel.GroupTransparency = 0
		scale.Scale = PANEL_BASE_SCALE
	end
end

local function setIconEnabled(icon: any?, enabled: boolean)
	if not icon then
		return
	end
	if type(icon.setEnabled) == "function" then
		pcall(function()
			icon:setEnabled(enabled)
		end)
	end
end

local function deselectIcon(icon: any?)
	if icon and type(icon.deselect) == "function" then
		pcall(function()
			icon:deselect()
		end)
	end
end

local function bindIcon(icon: any?, onOpen: () -> (), onClose: () -> ())
	if not icon then
		return
	end
	if icon.selected and type(icon.selected.Connect) == "function" then
		icon.selected:Connect(onOpen)
	elseif type(icon.onSelected) == "function" then
		icon:onSelected(onOpen)
	end
	if icon.deselected and type(icon.deselected.Connect) == "function" then
		icon.deselected:Connect(onClose)
	elseif type(icon.onDeselected) == "function" then
		icon:onDeselected(onClose)
	end
end

local DENY_TOAST_COOLDOWN = 2.5
local lastDenyToastAt = 0

local function roleCanUseDock(): boolean
	local player = Players.LocalPlayer
	local role = OverheadController.getPlayerRole(player.UserId)
	return PermissionDomain.canUseAdminPanel(role, player.UserId)
end

-- Server-authoritative deny toast (Notify). Local check only avoids opening the dock.
local function denyDockAccess(requestRemote: RemoteEvent?, topbarIcon: any?)
	deselectIcon(topbarIcon)
	local now = os.clock()
	if now - lastDenyToastAt < DENY_TOAST_COOLDOWN then
		return
	end
	lastDenyToastAt = now
	if requestRemote then
		requestRemote:FireServer({ action = "authorize" })
	end
end

local function pathToInstance(path: { string }?): Instance?
	if type(path) ~= "table" then
		return nil
	end
	local current: Instance = workspace
	for _, segment in ipairs(path) do
		if type(segment) ~= "string" or segment == "" then
			return nil
		end
		local child = current:FindFirstChild(segment)
		if not child then
			return nil
		end
		current = child
	end
	return current
end

local function resolveTarget(rawTarget: any): Instance?
	if type(rawTarget) ~= "table" then
		return nil
	end
	if rawTarget.type == "player" then
		local userId = tonumber(rawTarget.userId)
		local player = if userId then Players:GetPlayerByUserId(userId) else nil
		return player and player.Character or nil
	end
	if rawTarget.type == "cctv" then
		local instance = pathToInstance(rawTarget.path)
		return if instance and instance:IsA("BasePart") then instance else nil
	end
	return nil
end

local function showBars(duration: number)
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	if currentBarsGui then
		currentBarsGui:Destroy()
		currentBarsGui = nil
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CinematicDockBarsGui"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 80
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local top = Instance.new("Frame")
	top.Name = "TopBar"
	top.BackgroundColor3 = Color3.new(0, 0, 0)
	top.BorderSizePixel = 0
	top.AnchorPoint = Vector2.new(0, 0)
	top.Position = UDim2.fromScale(0, 0)
	top.Size = UDim2.fromScale(1, 0)
	top.Parent = gui

	local bottom = top:Clone()
	bottom.Name = "BottomBar"
	bottom.AnchorPoint = Vector2.new(0, 1)
	bottom.Position = UDim2.fromScale(0, 1)
	bottom.Parent = gui

	-- Skip hint label di atas bottom bar. Anchor ke bottom bar supaya selalu
	-- nempel di atas bar walaupun tinggi bar berubah saat tween.
	local skipLabel = Instance.new("TextLabel")
	skipLabel.Name = "SkipHint"
	skipLabel.AnchorPoint = Vector2.new(0.5, 1)
	skipLabel.Position = UDim2.new(0.5, 0, 0, -8)
	skipLabel.Size = UDim2.new(1, 0, 0, 22)
	skipLabel.BackgroundTransparency = 1
	skipLabel.Text = "Click anywhere to skip donation effects"
	skipLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
	skipLabel.TextTransparency = 1
	skipLabel.TextSize = 16
	skipLabel.FontFace = Font.new("rbxassetid://12187365977", Enum.FontWeight.Medium, Enum.FontStyle.Normal)
	skipLabel.TextXAlignment = Enum.TextXAlignment.Center
	skipLabel.TextYAlignment = Enum.TextYAlignment.Bottom
	skipLabel.TextStrokeTransparency = 0.65
	skipLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	skipLabel.Parent = bottom

	-- Click-anywhere-to-skip overlay. Transparent fullscreen button supaya
	-- klik dimana saja men-stop cinematic lokal (bars + camera) tanpa nunggu
	-- server broadcast. Camera trigger server-side tetap auto-stop sesuai duration.
	local skipButton = Instance.new("TextButton")
	skipButton.Name = "SkipOverlay"
	skipButton.Size = UDim2.fromScale(1, 1)
	skipButton.BackgroundTransparency = 1
	skipButton.Text = ""
	skipButton.AutoButtonColor = false
	skipButton.Modal = false
	skipButton.ZIndex = 1
	skipButton.Parent = gui
	top.ZIndex = 2
	bottom.ZIndex = 2
	skipLabel.ZIndex = 3

	currentBarsGui = gui
	tween(top, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 0.12) })
	tween(bottom, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 0.12) })
	tween(skipLabel, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0.05 })

	skipButton.Activated:Connect(function()
		if currentBarsGui ~= gui then
			return
		end
		CinematicCameraSystem.stopCinematic()
		hideBars()
		lastTargetId = nil
	end)

	task.delay(math.max(duration - 0.45, 0.5), function()
		if currentBarsGui ~= gui then
			return
		end
		tween(skipLabel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 })
		tween(top, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.fromScale(1, 0) })
		local out = tween(bottom, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.fromScale(1, 0) })
		out.Completed:Connect(function()
			if currentBarsGui == gui then
				currentBarsGui = nil
			end
			if gui.Parent then
				gui:Destroy()
			end
		end)
	end)
end

-- Hide bars early when the cinematic stops before the configured duration.
hideBars = function()
	local gui = currentBarsGui
	if not gui then
		return
	end
	currentBarsGui = nil
	local top = gui:FindFirstChild("TopBar")
	local bottom = gui:FindFirstChild("BottomBar")
	if top and top:IsA("GuiObject") then
		tween(top, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.fromScale(1, 0) })
	end
	if bottom and bottom:IsA("GuiObject") then
		local out = tween(bottom, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.fromScale(1, 0) })
		out.Completed:Connect(function()
			if gui.Parent then
				gui:Destroy()
			end
		end)
	else
		if gui.Parent then
			gui:Destroy()
		end
	end
end

-- Dual Shutter transition: dua panel hitam dari atas & bawah slam ke tengah
-- (kayak shutter kamera mekanik), hold sebentar, lalu buka lagi.
-- Total ~0.1s. Mechanical, premium feel.
local shutterBlinkGui: ScreenGui? = nil
local function doShutterBlink(onMidpoint: () -> ())
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		onMidpoint()
		return
	end

	-- Cleanup previous blink kalau masih ada
	if shutterBlinkGui and shutterBlinkGui.Parent then
		shutterBlinkGui:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CinematicDualShutter"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 200
	gui.ResetOnSpawn = false
	gui.Parent = playerGui
	shutterBlinkGui = gui

	-- Top shutter blade
	local top = Instance.new("Frame")
	top.Name = "TopBlade"
	top.BackgroundColor3 = Color3.new(0, 0, 0)
	top.BorderSizePixel = 0
	top.AnchorPoint = Vector2.new(0, 1)
	top.Position = UDim2.fromScale(0, 0)
	top.Size = UDim2.fromScale(1, 0)
	top.ZIndex = 2
	top.Parent = gui

	-- Bottom shutter blade
	local bottom = Instance.new("Frame")
	bottom.Name = "BottomBlade"
	bottom.BackgroundColor3 = Color3.new(0, 0, 0)
	bottom.BorderSizePixel = 0
	bottom.AnchorPoint = Vector2.new(0, 0)
	bottom.Position = UDim2.fromScale(0, 1)
	bottom.Size = UDim2.fromScale(1, 0)
	bottom.ZIndex = 2
	bottom.Parent = gui

	-- Thin highlight strip di edge blade (subtle metallic sheen)
	local sheen = Instance.new("Frame")
	sheen.Name = "Sheen"
	sheen.BackgroundColor3 = Color3.fromRGB(180, 180, 180)
	sheen.BackgroundTransparency = 0.6
	sheen.BorderSizePixel = 0
	sheen.AnchorPoint = Vector2.new(0, 0.5)
	sheen.Position = UDim2.fromScale(0, 0.5)
	sheen.Size = UDim2.new(1, 0, 0, 2)
	sheen.ZIndex = 3
	sheen.Visible = false
	sheen.Parent = gui

	-- Phase 1: blades slam shut (0.12s) — Back easing untuk mechanical snap
	local slamInfo = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	local topSlam = TweenService:Create(top, slamInfo, {
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(1, 0.5),
	})
	local bottomSlam = TweenService:Create(bottom, slamInfo, {
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(1, 0.5),
	})

	topSlam:Play()
	bottomSlam:Play()

	bottomSlam.Completed:Connect(function()
		-- Phase 2: hold + sheen flash + switch camera
		sheen.Visible = true
		local sheenFade = TweenService:Create(sheen, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		})
		sheenFade:Play()

		onMidpoint()

		-- Phase 3: blades open (0.18s) — Quint out untuk smooth, satisfying reveal
		task.delay(0.08, function()
			local openInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			local topOpen = TweenService:Create(top, openInfo, {
				Position = UDim2.fromScale(0, 0),
				Size = UDim2.fromScale(1, 0),
			})
			local bottomOpen = TweenService:Create(bottom, openInfo, {
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.fromScale(1, 0),
			})
			topOpen:Play()
			bottomOpen:Play()
			bottomOpen.Completed:Connect(function()
				if gui.Parent then
					gui:Destroy()
				end
				if shutterBlinkGui == gui then
					shutterBlinkGui = nil
				end
			end)
		end)
	end)
end

-- Track last target supaya bisa bedain "ganti movement" vs "ganti target".
local lastTargetId: string? = nil

local function getTargetId(rawTarget: any): string?
	if type(rawTarget) ~= "table" then
		return nil
	end
	if rawTarget.type == "player" then
		return "player:" .. tostring(rawTarget.userId or "")
	end
	if rawTarget.type == "cctv" then
		return "cctv:" .. table.concat(rawTarget.path or {}, "/")
	end
	return nil
end

local function isCctvTargetKey(targetId: string?): boolean
	return type(targetId) == "string" and string.sub(targetId, 1, 5) == "cctv:"
end

local function applyPartCinematic(
	targetPart: BasePart,
	movementName: string?,
	speedValue: number,
	instantCut: boolean
)
	if CinematicCameraSystem.isActive() then
		CinematicCameraSystem.switchPartCinematic(targetPart, movementName, speedValue, instantCut)
	else
		CinematicCameraSystem.startPartCinematic(targetPart, movementName, speedValue)
	end
end

local function playRemoteCinematic(raw: any)
	if type(raw) ~= "table" then
		return
	end
	if raw.type == "stop" then
		local by = raw.by
		if type(by) == "string" and string.find(by, "Donation", 1, true)
			and not DonationExperiencePrefs.shouldShowDonatorHighlight() then
			return
		end
		CinematicCameraSystem.stopCinematic()
		hideBars()
		lastTargetId = nil
		if handleOperatorBroadcastEnded then
			handleOperatorBroadcastEnded()
		end
		return
	end
	if raw.type ~= "play" then
		return
	end

	if raw.by == "[Donation]" and not DonationExperiencePrefs.shouldShowDonatorHighlight() then
		return
	end

	local speed = tonumber(raw.speed) or 1
	local target = resolveTarget(raw.target)
	if not target then
		return
	end

	local movement = if type(raw.movement) == "string" then raw.movement else nil
	local currentTargetId = getTargetId(raw.target)
	local previousTargetId = lastTargetId
	local targetChanged = currentTargetId ~= lastTargetId
	lastTargetId = currentTargetId

	-- Show cinematic bars while the camera is active; they auto-hide when the
	-- duration elapses.
	local duration = tonumber(raw.duration) or 12
	if shouldShowViewerCinematicChrome(raw) then
		showBars(duration)
	end

	local isDonationCinematic = raw.by == "[Donation]"
	local cinematicOptions = if isDonationCinematic
		then { transitionProfile = "snappy" :: "snappy" }
		else nil

	local function applyCinematicWithSpring(targetInstance: Instance, movementName: string?, speedValue: number)
		if targetInstance:IsA("Model") then
			if CinematicCameraSystem.isActive() then
				CinematicCameraSystem.switchCinematic(targetInstance, movementName, speedValue, cinematicOptions)
			else
				CinematicCameraSystem.startCinematic(targetInstance, movementName, speedValue, cinematicOptions)
			end
		elseif targetInstance:IsA("BasePart") then
			applyPartCinematic(targetInstance, movementName, speedValue, false)
		end
	end

	local cctvToCctvCut = target:IsA("BasePart")
		and isCctvTargetKey(previousTargetId)
		and isCctvTargetKey(currentTargetId)

	if not CinematicCameraSystem.isActive() then
		applyCinematicWithSpring(target, movement, speed)
	elseif targetChanged then
		if target:IsA("BasePart") then
			-- CCTV -> CCTV: hard cut (no fly glide). Player/part lain tetap transisi aman.
			applyPartCinematic(target, movement, speed, cctvToCctvCut)
		else
			applyCinematicWithSpring(target, movement, speed)
		end
	elseif target:IsA("BasePart") then
		-- CCTV sama, ganti movement/speed: cut langsung (tanpa shutter / fly).
		applyPartCinematic(target, movement, speed, true)
	else
		-- Target sama (player), movement/speed beda: shutter blink (punchy cut)
		doShutterBlink(function()
			if CinematicCameraSystem.isActive() then
				if target:IsA("Model") then
					CinematicCameraSystem.switchCinematic(target, movement, speed, cinematicOptions)
				end
			elseif target:IsA("Model") then
				CinematicCameraSystem.startCinematic(target, movement, speed, cinematicOptions)
			end
		end)
	end
end

local function clearDynamicRows(content: Instance, keep: { [Instance]: boolean })
	for _, child in ipairs(content:GetChildren()) do
		if child:IsA("GuiButton") and not keep[child] then
			child:Destroy()
		end
	end
end

local function collectDockButtons(dock: GuiObject): { DockButtonState }
	local states = {}
	for _, descendant in ipairs(dock:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			if descendant.Name == "SelectMovementButton" or descendant.Name == "SelectTargetButton" then
				continue
			end
			local scale = ensureScale(descendant)
			table.insert(states, {
				button = descendant,
				scale = scale,
				baseScale = scale.Scale,
				currentScale = scale.Scale,
			})
		end
	end
	return states
end

local function startDockMagnifier(dock: GuiObject): () -> ()
	local states = collectDockButtons(dock)
	local alive = true
	local conn = RunService.RenderStepped:Connect(function(dt)
		if not alive or not dock.Visible then
			return
		end
		local mouse = UserInputService:GetMouseLocation()
		local alpha = math.clamp(dt * 14, 0, 1)
		for _, state in ipairs(states) do
			if not state.button.Parent then
				continue
			end
			local pos = state.button.AbsolutePosition
			local size = state.button.AbsoluteSize
			local center = pos + (size * 0.5)
			local distance = (Vector2.new(mouse.X, mouse.Y) - center).Magnitude
			local influence = math.clamp(1 - (distance / 95), 0, 1) ^ 2
			local targetScale = state.baseScale + (influence * 0.14)
			state.currentScale += (targetScale - state.currentScale) * alpha
			state.scale.Scale = state.currentScale
		end
	end)
	return function()
		alive = false
		conn:Disconnect()
	end
end

local function init(_deps: {}?)
	local deps = _deps or {}
	local topbarIcon = (deps :: any).icon
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	if not remotes then
		return
	end
	local broadcastRemote = remotes:WaitForChild(Config.CinematicDock.REMOTE_BROADCAST, 15) :: RemoteEvent?
	if broadcastRemote and broadcastRemote:IsA("RemoteEvent") and not broadcastBound then
		broadcastBound = true
		track(broadcastRemote.OnClientEvent:Connect(playRemoteCinematic))
	end

	local gui = playerGui:WaitForChild(Config.CinematicDock.GUI_NAME, 20) :: ScreenGui?
	if not gui then
		log:warn("Cinematic dock GUI not found; donation cinematic listener remains active")
		return
	end

	local requestRemote = remotes:WaitForChild(Config.CinematicDock.REMOTE_REQUEST, 15) :: RemoteEvent?
	local targetsRemote = remotes:WaitForChild(Config.CinematicDock.REMOTE_TARGETS, 15) :: RemoteEvent?
	if not requestRemote or not broadcastRemote or not targetsRemote then
		log:warn("Cinematic dock remotes not ready")
		return
	end

	local dock = gui:FindFirstChild("CinematicDock") :: Frame?
	local trigger = gui:FindFirstChild("OverlayTrigger") :: ImageButton?
	local movementPanel = gui:FindFirstChild("01-MovementType") :: CanvasGroup?
	local targetPanel = gui:FindFirstChild("02-TargetList") :: CanvasGroup?
	local broadcastButton = gui:FindFirstChild("CentralStartandStopButton") :: TextButton?
	if not dock or not movementPanel or not targetPanel then
		log:warn("Cinematic dock structure incomplete; donation cinematic listener remains active")
		return
	end

	local selectMovement = findButton(dock, "SelectMovementButton")
	local selectTarget = findButton(dock, "SelectTargetButton")
	local targetContent = getPanelMainContent(targetPanel)
	local movementContent = getPanelMainContent(movementPanel)
	local movementTemplateSet = if movementContent then collectStateTemplateSet(movementContent) else nil
	local targetTemplateSet = if targetContent then collectStateTemplateSet(targetContent) else nil
	local movementFilters = if movementTemplateSet then movementTemplateSet.filterButtons else {}
	local targetFilters = if targetTemplateSet then targetTemplateSet.filterButtons else {}
	local movementSearch = movementPanel:FindFirstChild("SearchMovement", true) :: TextBox?
	local targetSearch = targetPanel:FindFirstChild("SearchTarget", true) :: TextBox?
	local closeTargetModal = targetPanel:FindFirstChild("CloseModalButton", true) :: GuiButton?
	local movementFilterMode = "NormalState"
	local targetFilterMode = "NormalState"
	local movementSearchQuery = ""
	local targetSearchQuery = ""
	local lastTargetList: { any } = {}
	local favoritedMovements = readFavoriteMap(FAVORITE_MOVEMENTS_ATTR)
	local favoritedTargets = readFavoriteMap(FAVORITE_TARGETS_ATTR)
	local playedMovementsSession: { [string]: boolean } = {}
	local playedTargetsSession: { [string]: boolean } = {}

	-- Forward declaration: rebuildMovementRows dipanggil dari target handler saat
	-- target type berubah, jadi panelnya di-repopulate dengan opsi yang relevant.
	local rebuildMovementRows: () -> () = function() end
	local rebuildTargetRows: (targets: { any }) -> () = function() end

	local dockAnim = Config.CinematicDock
	local dockHideDuration = dockAnim.DOCK_CHROME_HIDE_DURATION or 0.18
	local dockShowDuration = dockAnim.DOCK_CHROME_SHOW_DURATION or 0.28
	local dockSlideOffsetY = dockAnim.DOCK_CHROME_SLIDE_OFFSET_Y or 70
	local dockStartScale = dockAnim.DOCK_CHROME_START_SCALE or 0.96

	local dockShown = false
	local dockTween: Tween? = nil
	local dockPosition = dock.Position
	local dockHiddenPosition = dockPosition + UDim2.fromOffset(0, dockSlideOffsetY)
	local setupActive = false
	local startedThisSetup = false
	local speedChanger: Instance? = nil
	local speedButtons: { TextButton } = {}
	type SpeedStrokeStyle = {
		color: Color3,
		transparency: number,
		thickness: number,
		enabled: boolean,
	}
	type SpeedButtonVisual = {
		bg: Color3,
		text: Color3,
		strokes: { SpeedStrokeStyle },
	}
	local speedIdleStyle: SpeedButtonVisual? = nil
	local speedActiveStyle: SpeedButtonVisual? = nil

	local function parseSpeedFromButton(button: TextButton): number?
		local text = button.Text:lower():gsub("x", ""):gsub("%s", "")
		return tonumber(text)
	end

	local function collectSpeedButtonStrokes(button: TextButton): { UIStroke }
		local strokes: { UIStroke } = {}
		local direct = button:FindFirstChildOfClass("UIStroke")
		if direct then
			table.insert(strokes, direct)
		end
		for _, descendant in ipairs(button:GetDescendants()) do
			if descendant:IsA("UIStroke") and descendant ~= direct then
				table.insert(strokes, descendant)
			end
		end
		return strokes
	end

	local function captureSpeedButtonVisual(button: TextButton): SpeedButtonVisual
		local strokes: { SpeedStrokeStyle } = {}
		for _, stroke in ipairs(collectSpeedButtonStrokes(button)) do
			table.insert(strokes, {
				color = stroke.Color,
				transparency = stroke.Transparency,
				thickness = stroke.Thickness,
				enabled = stroke.Enabled,
			})
		end
		return {
			bg = button.BackgroundColor3,
			text = button.TextColor3,
			strokes = strokes,
		}
	end

	local function applySpeedButtonVisual(button: TextButton, style: SpeedButtonVisual)
		button.BackgroundColor3 = style.bg
		button.TextColor3 = style.text
		local strokes = collectSpeedButtonStrokes(button)
		for index, stroke in ipairs(strokes) do
			local snapshot = style.strokes[index]
			if snapshot then
				stroke.Enabled = snapshot.enabled
				stroke.Color = snapshot.color
				stroke.Transparency = snapshot.transparency
				stroke.Thickness = snapshot.thickness
			elseif #style.strokes == 0 then
				stroke.Enabled = false
				stroke.Transparency = 1
			end
		end
	end
	local broadcastFillSnapshots: { { object: GuiObject, bg: Color3 } } = {}
	local broadcastStartText: Color3? = nil
	local broadcastStrokeSnapshots: { { stroke: UIStroke, color: Color3 } } = {}
	local BROADCAST_STOP_BG = Color3.fromRGB(176, 42, 42)
	local BROADCAST_STOP_STROKE = Color3.fromRGB(120, 28, 28)
	if broadcastButton then
		broadcastStartText = broadcastButton.TextColor3
		local function captureFill(object: GuiObject)
			if object.BackgroundTransparency >= 0.99 then
				return
			end
			table.insert(broadcastFillSnapshots, {
				object = object,
				bg = object.BackgroundColor3,
			})
		end
		captureFill(broadcastButton)
		for _, descendant in ipairs(broadcastButton:GetDescendants()) do
			if descendant:IsA("Frame") or descendant:IsA("ImageButton") or descendant:IsA("ImageLabel") then
				captureFill(descendant :: GuiObject)
			elseif descendant:IsA("UIStroke") then
				table.insert(broadcastStrokeSnapshots, {
					stroke = descendant,
					color = descendant.Color,
				})
			end
		end
		local buttonStroke = broadcastButton:FindFirstChildOfClass("UIStroke")
		if buttonStroke then
			table.insert(broadcastStrokeSnapshots, {
				stroke = buttonStroke,
				color = buttonStroke.Color,
			})
		end
	end
	dock.Visible = false
	dock.Position = dockHiddenPosition
	if trigger then
		trigger.Visible = false
	end
	if broadcastButton then
		broadcastButton.Visible = false
		broadcastButton.Text = "Start Broadcast"
	end
	setPanelVisible(movementPanel, false)
	setPanelVisible(targetPanel, false)
	local stopMagnifier: (() -> ())? = nil
	local function ensureMagnifierRunning()
		if Config.CinematicDock.DOCK_MAGNIFIER_ENABLED ~= true or stopMagnifier then
			return
		end
		stopMagnifier = startDockMagnifier(dock)
	end
	local function releaseMagnifier()
		if stopMagnifier then
			stopMagnifier()
			stopMagnifier = nil
		end
	end

	local DOCK_HIDE_DURATION = dockHideDuration
	local dockChromeHidden = false
	local dockChromeReleaseToken = 0

	local function setOperatorChromeHidden(hidden: boolean)
		if hidden then
			dockChromeReleaseToken += 1
			if dockChromeHidden then
				return
			end
			dockChromeHidden = true
			MobilePanelManager.notifyInventoryChromeHide("cinematic")
		else
			if not dockChromeHidden then
				return
			end
			dockChromeHidden = false
			MobilePanelManager.notifyInventoryChromeShow("cinematic")
		end
	end

	local function releaseOperatorChromeAfterDockHide()
		if not dockChromeHidden then
			return
		end
		dockChromeReleaseToken += 1
		local releaseToken = dockChromeReleaseToken
		task.delay(DOCK_HIDE_DURATION, function()
			if releaseToken ~= dockChromeReleaseToken or not dockChromeHidden then
				return
			end
			dockChromeHidden = false
			MobilePanelManager.notifyCinematicSessionEnd()
		end)
	end

	local function setDockVisible(visible: boolean)
		if dockShown == visible then
			return
		end
		dockShown = visible
		if dockTween then
			dockTween:Cancel()
			dockTween = nil
		end
		if visible then
			dock.Visible = true
			ensureMagnifierRunning()
			dock.Position = dockHiddenPosition
			local scale = ensureScale(dock)
			scale.Scale = dockStartScale
			dockTween = tween(dock, TweenInfo.new(dockShowDuration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				Position = dockPosition,
			})
			tween(scale, TweenInfo.new(dockShowDuration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				Scale = 1,
			})
		else
			releaseMagnifier()
			local scale = ensureScale(dock)
			dockTween = tween(dock, TweenInfo.new(dockHideDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = dockHiddenPosition,
			})
			tween(scale, TweenInfo.new(dockHideDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Scale = dockStartScale,
			})
			local activeTween = dockTween
			activeTween.Completed:Connect(function()
				if dockTween == activeTween and not dockShown then
					dock.Visible = false
				end
			end)
		end
	end

	local function setOverlayTriggerVisible(visible: boolean)
		if trigger then
			trigger.Visible = visible
		end
	end

	local function refreshSpeedHighlight()
		if not speedActiveStyle or not speedIdleStyle then
			return
		end
		local activeSpeed = selectedSpeed or Config.CinematicDock.DEFAULT_SPEED or 1
		for _, button in ipairs(speedButtons) do
			local parsed = parseSpeedFromButton(button)
			local isActive = parsed ~= nil and math.abs(parsed - activeSpeed) < 0.001
			if isActive then
				applySpeedButtonVisual(button, speedActiveStyle)
			else
				applySpeedButtonVisual(button, speedIdleStyle)
			end
		end
	end

	local function refreshDockSelections()
		if selectTarget then
			if selectedTarget then
				setButtonLabel(selectTarget, tostring(selectedTarget.name or "Target"))
			else
				setButtonLabel(selectTarget, "Select target")
			end
		end

		if selectMovement then
			if selectedMovementLabel then
				setButtonLabel(selectMovement, selectedMovementLabel)
			else
				setButtonLabel(selectMovement, "Select movement")
			end
		end

		refreshSpeedHighlight()
	end

	local function refreshBroadcastButton()
		if not broadcastButton or not broadcastButton.Visible then
			return
		end
		local isStop = startedThisSetup
		broadcastButton.Text = if isStop then "Stop Broadcast" else "Start Broadcast"
		if isStop then
			for _, snapshot in ipairs(broadcastFillSnapshots) do
				snapshot.object.BackgroundColor3 = BROADCAST_STOP_BG
			end
			broadcastButton.TextColor3 = Color3.new(1, 1, 1)
			for _, snapshot in ipairs(broadcastStrokeSnapshots) do
				snapshot.stroke.Color = BROADCAST_STOP_STROKE
			end
		else
			for _, snapshot in ipairs(broadcastFillSnapshots) do
				snapshot.object.BackgroundColor3 = snapshot.bg
			end
			if broadcastStartText then
				broadcastButton.TextColor3 = broadcastStartText
			end
			for _, snapshot in ipairs(broadcastStrokeSnapshots) do
				snapshot.stroke.Color = snapshot.color
			end
		end
	end

	local function pushBroadcastStateToServer()
		if not selectedTarget or not selectedMovement then
			return
		end
		local target = selectedTarget :: TargetOption
		local speed = selectedSpeed or Config.CinematicDock.DEFAULT_SPEED or 1
		requestRemote:FireServer({
			targetType = target.type,
			userId = target.userId,
			path = target.path,
			movement = selectedMovement,
			speed = speed,
		})
	end

	local function maybePushLiveBroadcast()
		if not startedThisSetup or not selectedTarget or not selectedMovement then
			return
		end
		pushBroadcastStateToServer()
	end

	handleOperatorBroadcastEnded = function()
		if not startedThisSetup then
			return
		end
		startedThisSetup = false
		operatorBroadcasting = false
		refreshBroadcastButton()
		refreshDockSelections()
	end

	local function setBroadcastButtonVisible(visible: boolean)
		if not broadcastButton then
			return
		end
		broadcastButton.Visible = visible
		if visible then
			refreshBroadcastButton()
		end
	end

	refreshDockSelections()

	local function showOperatorSession()
		setOverlayTriggerVisible(false)
		setOperatorChromeHidden(true)
		setDockVisible(true)
		setBroadcastButtonVisible(true)
	end

	local function hideOperatorSurfaces(showTrigger: boolean)
		setDockVisible(false)
		setPanelVisible(movementPanel, false)
		setPanelVisible(targetPanel, false)
		setBroadcastButtonVisible(false)
		setOverlayTriggerVisible(showTrigger)
		releaseOperatorChromeAfterDockHide()
	end

	local function resetSetup()
		setupActive = false
		startedThisSetup = false
		operatorBroadcasting = false
		selectedMovement = nil
		selectedMovementLabel = nil
		selectedSpeed = Config.CinematicDock.DEFAULT_SPEED or 1
		selectedTarget = nil
		refreshDockSelections()
		refreshBroadcastButton()
	end

	local function stopDockCinematic()
		if not startedThisSetup then
			return
		end
		requestRemote:FireServer({
			action = "stop",
		})
		startedThisSetup = false
		operatorBroadcasting = false
		CinematicCameraSystem.stopCinematic()
		hideBars()
		refreshBroadcastButton()
		refreshDockSelections()
	end

	local function refreshAccess()
		local canUse = roleCanUseDock()
		-- Cinematic is menu-only; never show on the topbar strip.
		setIconEnabled(topbarIcon, false)
		if not canUse then
			hideOperatorSurfaces(false)
			resetSetup()
			deselectIcon(topbarIcon)
		end
	end

	local overheadRemote = remotes:WaitForChild("OverheadUpdate", 15) :: RemoteEvent?
	if overheadRemote then
		track(overheadRemote.OnClientEvent:Connect(function(payload: any)
			if type(payload) == "table" and payload.userId == player.UserId then
				task.defer(refreshAccess)
			end
		end))
	end
	task.defer(refreshAccess)
	task.delay(5, refreshAccess)

	local function enterBroadcastMode()
		startedThisSetup = true
		operatorBroadcasting = true
		refreshBroadcastButton()
		refreshDockSelections()
		setOperatorChromeHidden(true)
		maybePushLiveBroadcast()
	end

	local function openOperatorSession()
		if not roleCanUseDock() then
			denyDockAccess(requestRemote, topbarIcon)
			return
		end
		setupActive = true
		showOperatorSession()
		refreshDockSelections()
	end

	if trigger then
		trigger.MouseEnter:Connect(function()
			if roleCanUseDock() then
				openOperatorSession()
			end
		end)
		trigger.Activated:Connect(function()
			if not roleCanUseDock() then
				denyDockAccess(requestRemote, topbarIcon)
				return
			end
			if setupActive then
				if startedThisSetup then
					stopDockCinematic()
				end
				hideOperatorSurfaces(true)
				setupActive = false
			else
				openOperatorSession()
			end
		end)
	end

	if broadcastButton then
		broadcastButton.Activated:Connect(function()
			if not roleCanUseDock() then
				denyDockAccess(requestRemote, topbarIcon)
				return
			end
			if startedThisSetup then
				stopDockCinematic()
				return
			end
			enterBroadcastMode()
		end)
	end

	if closeTargetModal then
		closeTargetModal.Activated:Connect(function()
			setPanelVisible(targetPanel, false)
		end)
	end

	bindIcon(topbarIcon, function()
		if not roleCanUseDock() then
			denyDockAccess(requestRemote, topbarIcon)
			return
		end
		if not startedThisSetup then
			resetSetup()
		end
		openOperatorSession()
	end, function()
		if startedThisSetup then
			stopDockCinematic()
		end
		hideOperatorSurfaces(false)
		resetSetup()
	end)

	if selectMovement then
		selectMovement.Activated:Connect(function()
			showOperatorSession()
			local willShow = not movementPanel.Visible
			setPanelVisible(movementPanel, willShow)
			if willShow then
				rebuildMovementRows()
			end
		end)
	end

	local function movementPassesSearch(option: MovementOption): boolean
		local query = movementSearchQuery:lower()
		if query == "" then
			return true
		end
		return string.find(option.label:lower(), query, 1, true) ~= nil
			or string.find(option.value:lower(), query, 1, true) ~= nil
	end

	local function targetPassesSearch(target: any): boolean
		local query = targetSearchQuery:lower()
		if query == "" then
			return true
		end
		local name = tostring(target.name or target.type or "")
		return string.find(name:lower(), query, 1, true) ~= nil
	end

	local function wireFilterTabs(
		filters: { GuiButton },
		getMode: () -> string,
		setMode: (string) -> (),
		rebuild: () -> ()
	)
		for _, button in ipairs(filters) do
			button.Activated:Connect(function()
				setMode(button.Name)
				setFilterRowHighlight(filters, button)
				rebuild()
			end)
		end
		for _, button in ipairs(filters) do
			if button.Name == getMode() then
				setFilterRowHighlight(filters, button)
				break
			end
		end
	end

	if movementSearch then
		movementSearch:GetPropertyChangedSignal("Text"):Connect(function()
			movementSearchQuery = movementSearch.Text
			rebuildMovementRows()
		end)
	end

	if targetSearch then
		targetSearch:GetPropertyChangedSignal("Text"):Connect(function()
			targetSearchQuery = targetSearch.Text
			if #lastTargetList > 0 then
				rebuildTargetRows(lastTargetList)
			end
		end)
	end

	if movementContent and movementTemplateSet then
		local movementKeepRows = buildKeepRowsForTemplateSet(movementTemplateSet)
		clearDynamicRows(movementContent, movementKeepRows)
		rebuildMovementRows = function()
			clearDynamicRows(movementContent, movementKeepRows)
			local options = filterMovementOptions(selectedTarget)
			if selectedMovement then
				local stillValid = false
				for _, option in ipairs(options) do
					if option.value == selectedMovement then
						stillValid = true
						break
					end
				end
				if not stillValid then
					selectedMovement = nil
					selectedMovementLabel = nil
				end
			end
			refreshDockSelections()
			local movementLayoutIndex = 0
			for _, option in ipairs(options) do
				if not movementPassesSearch(option) then
					continue
				end
				local movementKey = option.value
				local isFavorited = favoritedMovements[movementKey] == true
				local isActive = selectedMovement == movementKey
				local isPlayed = playedMovementsSession[movementKey] == true
				if not passesListFilter(movementFilterMode, isFavorited, isPlayed, isActive) then
					continue
				end
				movementLayoutIndex += 1
				local row = pickRowTemplate(movementTemplateSet, isFavorited, isPlayed, isActive):Clone()
				row.Name = "MovementRow" .. tostring(movementLayoutIndex)
				row.Visible = true
				row.LayoutOrder = movementLayoutIndex + 20
				row.Parent = movementContent
				local label = row:FindFirstChildWhichIsA("TextLabel", true)
				if label then
					label.Text = option.label
				elseif row:IsA("TextButton") then
					row.Text = option.label
				end
				syncFavoriteBadge(row, isFavorited)
				local favoriteButton = getFavoriteButton(row)
				if favoriteButton then
					favoriteButton.Activated:Connect(function()
						if favoritedMovements[movementKey] then
							favoritedMovements[movementKey] = nil
						else
							favoritedMovements[movementKey] = true
						end
						writeFavoriteMap(FAVORITE_MOVEMENTS_ATTR, favoritedMovements)
						rebuildMovementRows()
					end)
				end
				row.Activated:Connect(function()
					playedMovementsSession[movementKey] = true
					selectedMovement = option.value
					selectedMovementLabel = option.label
					showOperatorSession()
					refreshDockSelections()
					rebuildMovementRows()
					maybePushLiveBroadcast()
				end)
			end
		end
		wireFilterTabs(movementFilters, function()
			return movementFilterMode
		end, function(mode: string)
			movementFilterMode = mode
		end, rebuildMovementRows)
		rebuildMovementRows()
	elseif movementContent then
		log:warn("Movement state templates incomplete in MainContent")
	else
		log:warn("Movement panel MainContent not found", {
			movementPanelChildren = (function()
				local names = {}
				for _, child in ipairs(movementPanel:GetChildren()) do
					table.insert(names, child.Name .. "(" .. child.ClassName .. ")")
				end
				return table.concat(names, ", ")
			end)(),
		})
	end

	if selectTarget then
		selectTarget.Activated:Connect(function()
			showOperatorSession()
			local willShow = not targetPanel.Visible
			if willShow then
				targetsRemote:FireServer()
			end
			setPanelVisible(targetPanel, willShow)
		end)
	end

	speedChanger = dock:FindFirstChild("SpeedChanger", true)
	if speedChanger then
		local allowedSpeeds: { number } = Config.CinematicDock.ALLOWED_SPEEDS :: any
		local allowedLookup: { [number]: boolean } = {}
		for _, value in ipairs(allowedSpeeds) do
			allowedLookup[value] = true
		end
		table.clear(speedButtons)
		local defaultSpeed = Config.CinematicDock.DEFAULT_SPEED or 1
		for _, child in ipairs(speedChanger:GetDescendants()) do
			if child:IsA("TextButton") then
				table.insert(speedButtons, child)
			end
		end
		table.sort(speedButtons, function(a, b)
			if a.LayoutOrder == b.LayoutOrder then
				return a.Name < b.Name
			end
			return a.LayoutOrder < b.LayoutOrder
		end)
		for _, button in ipairs(speedButtons) do
			local parsed = parseSpeedFromButton(button)
			if parsed and math.abs(parsed - defaultSpeed) < 0.001 then
				speedActiveStyle = captureSpeedButtonVisual(button)
			end
		end
		for _, button in ipairs(speedButtons) do
			local parsed = parseSpeedFromButton(button)
			if parsed and math.abs(parsed - defaultSpeed) >= 0.001 then
				speedIdleStyle = captureSpeedButtonVisual(button)
				break
			end
		end
		if not speedIdleStyle and #speedButtons > 0 then
			speedIdleStyle = captureSpeedButtonVisual(speedButtons[1])
		end
		for _, child in ipairs(speedButtons) do
			child.Activated:Connect(function()
				local parsed = parseSpeedFromButton(child)
				if parsed and allowedLookup[parsed] then
					selectedSpeed = parsed
					refreshDockSelections()
					if CinematicCameraSystem.isActive() then
						CinematicCameraSystem.setSpeed(parsed)
					end
					maybePushLiveBroadcast()
				end
			end)
		end
		refreshSpeedHighlight()
	end

	rebuildTargetRows = function(targets: { any })
		if not targetContent or not targetTemplateSet then
			return
		end
		local targetKeepRows = buildKeepRowsForTemplateSet(targetTemplateSet)
		clearDynamicRows(targetContent, targetKeepRows)

		local layoutIndex = 0
		for _, target in ipairs(targets) do
			if not targetPassesSearch(target) then
				continue
			end
			local targetKey = getTargetKeyFromRaw(target)
			local isFavorited = favoritedTargets[targetKey] == true
			local isActive = selectedTarget ~= nil
				and selectedTarget.type == target.type
				and selectedTarget.userId == target.userId
				and table.concat(selectedTarget.path or {}, "/") == table.concat(target.path or {}, "/")
			local isPlayed = playedTargetsSession[targetKey] == true
			if not passesListFilter(targetFilterMode, isFavorited, isPlayed, isActive) then
				continue
			end
			layoutIndex += 1
			local row = pickRowTemplate(targetTemplateSet, isFavorited, isPlayed, isActive):Clone()
			row.Name = "TargetRow" .. tostring(layoutIndex)
			row.Visible = true
			row.LayoutOrder = layoutIndex + 20
			row.Parent = targetContent
			local label = row:FindFirstChildWhichIsA("TextLabel", true)
			if label then
				label.Text = tostring(target.name or target.type or "Target")
			end
			syncFavoriteBadge(row, isFavorited)
			local favoriteButton = getFavoriteButton(row)
			if favoriteButton then
				favoriteButton.Activated:Connect(function()
					if favoritedTargets[targetKey] then
						favoritedTargets[targetKey] = nil
					else
						favoritedTargets[targetKey] = true
					end
					writeFavoriteMap(FAVORITE_TARGETS_ATTR, favoritedTargets)
					rebuildTargetRows(targets)
				end)
			end
			row.Activated:Connect(function()
				local previousType: string? = if selectedTarget then selectedTarget.type else nil
				local previous360 = CinematicCameraModes.is360CctvTarget(selectedTarget)
				playedTargetsSession[targetKey] = true
				selectedTarget = target
				local newType: string? = selectedTarget.type
				local new360 = CinematicCameraModes.is360CctvTarget(selectedTarget)
				if newType ~= previousType or new360 ~= previous360 then
					selectedMovement = nil
					selectedMovementLabel = nil
					rebuildMovementRows()
				end
				showOperatorSession()
				refreshDockSelections()
				rebuildTargetRows(targets)
				maybePushLiveBroadcast()
			end)
		end
	end

	track(targetsRemote.OnClientEvent:Connect(function(raw: any)
		if type(raw) ~= "table" or raw.type ~= "targets" or type(raw.targets) ~= "table" then
			return
		end
		if not targetContent or not targetTemplateSet then
			log:warn("Target panel state templates incomplete")
			return
		end

		lastTargetList = raw.targets
		rebuildTargetRows(raw.targets)
	end))

	if targetContent and #targetFilters > 0 then
		wireFilterTabs(targetFilters, function()
			return targetFilterMode
		end, function(mode: string)
			targetFilterMode = mode
		end, function()
			targetsRemote:FireServer()
		end)
	end

	log:info("CinematicDockController initialized")
end

return { init = init, destroy = destroy }
