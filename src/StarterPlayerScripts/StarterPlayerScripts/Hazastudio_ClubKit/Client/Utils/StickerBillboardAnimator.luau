--!strict
-- PATH: Client/Utils/StickerBillboardAnimator.luau
-- Client-side billboard sticker animator.
-- Handles pop-in bounce, gentle float + wobble idle, sparkles, and fade-out exit
-- for the ShoulderStickerGUI BillboardGui on all characters.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local CharacterReady = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.CharacterReady)

local StickerBillboardAnimator = {}

-- ============================================================
-- ANIMATION CONSTANTS (pulled from Config at init)
-- ============================================================
local ANIM = nil :: any -- resolved at init

-- ============================================================
-- INTERNAL TYPES
-- ============================================================
type ActiveSticker = {
	gui: BillboardGui,
	image: ImageLabel,
	scale: UIScale,
	idleTime: number,
	baseStudsOffsetY: number,
	entrancePlayed: boolean,
	exitPlaying: boolean,
	sparkles: { GuiObject },
}

-- ============================================================
-- PER-CHARACTER TRACKING
-- ============================================================
local activeStickers: { [Model]: ActiveSticker } = {}
local characterConns: { [Model]: { RBXScriptConnection } } = {}
local playerConns: { [Player]: { RBXScriptConnection } } = {}

-- ============================================================
-- SHARED HEARTBEAT (replaces per-sticker Heartbeat connections)
-- ============================================================
local sharedStickerHeartbeat: RBXScriptConnection? = nil

-- v2.2: throttle sticker float/wobble animation from 60Hz to 30Hz.
-- The float/wobble math uses idleTime accumulator so frequency is
-- independent of correctness. 30Hz is plenty for sin-based smooth motion
-- and halves the per-frame cost when many stickers are active.
local stickerHeartbeatAccum = 0
local STICKER_HEARTBEAT_INTERVAL = 0.033

local function updateAllActiveStickers(dt: number)
	stickerHeartbeatAccum += dt
	if stickerHeartbeatAccum < STICKER_HEARTBEAT_INTERVAL then
		return
	end
	local effectiveDt = stickerHeartbeatAccum
	stickerHeartbeatAccum = 0
	for character, active in pairs(activeStickers) do
		if active.exitPlaying then
			continue
		end
		active.idleTime += effectiveDt
		local floatOffset = math.sin(active.idleTime * ANIM.FLOAT_SPEED) * ANIM.FLOAT_AMPLITUDE
		active.gui.StudsOffset = Vector3.new(
			Config.Sticker.BILLBOARD_STUDS_OFFSET.X,
			active.baseStudsOffsetY + floatOffset,
			Config.Sticker.BILLBOARD_STUDS_OFFSET.Z
		)
		local wobble = math.sin(active.idleTime * ANIM.WOBBLE_SPEED) * ANIM.WOBBLE_AMPLITUDE
		active.image.Rotation = wobble
	end
	-- Auto-disconnect when no stickers remain active
	if next(activeStickers) == nil and sharedStickerHeartbeat then
		sharedStickerHeartbeat:Disconnect()
		sharedStickerHeartbeat = nil
	end
end

local function ensureSharedStickerHeartbeat()
	if sharedStickerHeartbeat then
		return
	end
	sharedStickerHeartbeat = RunService.Heartbeat:Connect(updateAllActiveStickers)
end

-- ============================================================
-- HELPERS
-- ============================================================
local function ensureUIScale(parent: GuiObject): UIScale
	local existing = parent:FindFirstChild("_StickerAnimScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end

	local scale = Instance.new("UIScale")
	scale.Name = "_StickerAnimScale"
	scale.Scale = 0
	scale.Parent = parent
	return scale
end

local function findStickerGui(character: Model): (BillboardGui?, ImageLabel?)
	local gui = character:FindFirstChild(Config.Sticker.BILLBOARD_GUI_NAME, true)
	if not gui or not gui:IsA("BillboardGui") then
		return nil, nil
	end

	local imageLabel = gui:FindFirstChild(Config.Sticker.BILLBOARD_IMAGE_NAME)
	if not imageLabel or not imageLabel:IsA("ImageLabel") then
		return nil, nil
	end

	return gui :: BillboardGui, imageLabel :: ImageLabel
end

local function getActiveStickerImage(player: Player): string
	local imageAttr = player:GetAttribute(Config.Sticker.STICKER_IMAGE_ATTRIBUTE)
	if type(imageAttr) == "string" and imageAttr ~= "" then
		return imageAttr
	end
	return ""
end

local function playerHasActiveSticker(player: Player): boolean
	return getActiveStickerImage(player) ~= ""
end

-- Hard hide: runs even when animator state was never created (remote replication races).
local function forceHideStickerBillboard(character: Model)
	local gui, imageLabel = findStickerGui(character)
	if not gui then
		return
	end

	gui.Enabled = false
	if imageLabel then
		imageLabel.ImageTransparency = 1
		imageLabel.BackgroundTransparency = 1
		local scaleObj = imageLabel:FindFirstChild("_StickerAnimScale")
		if scaleObj and scaleObj:IsA("UIScale") then
			(scaleObj :: UIScale).Scale = 0
		end
	end
end

local function cleanupSticker(character: Model)
	local active = activeStickers[character]
	if active then
		for _, sparkle in ipairs(active.sparkles) do
			if sparkle and sparkle.Parent then
				sparkle:Destroy()
			end
		end
		table.clear(active.sparkles)

		local scaleObj = active.image:FindFirstChild("_StickerAnimScale")
		if scaleObj and scaleObj:IsA("UIScale") then
			scaleObj:Destroy()
		end

		activeStickers[character] = nil
	end

	forceHideStickerBillboard(character)
end

local function cleanupCharacter(character: Model)
	cleanupSticker(character)
	local conns = characterConns[character]
	if conns then
		for _, conn in ipairs(conns) do
			conn:Disconnect()
		end
		characterConns[character] = nil
	end
end

-- ============================================================
-- SPARKLE EFFECT
-- ============================================================
local SPARKLE_CHARS = { "✦", "✧", "⋆", "✶", "✷", "❋" }

local function _spawnSparkles(active: ActiveSticker)
	if not ANIM then
		return
	end

	local parent = active.image
	local count = ANIM.SPARKLE_COUNT
	local sparkles = active.sparkles

	for i = 1, count do
		local label = Instance.new("TextLabel")
		label.Name = "_Sparkle_" .. tostring(i)
		label.BackgroundTransparency = 1
		label.Text = SPARKLE_CHARS[math.random(1, #SPARKLE_CHARS)]
		label.TextColor3 = Color3.fromHSV(
			math.random() * 0.15 + 0.1, -- warm golden-white range
			math.random() * 0.3 + 0.1,
			1
		)
		label.TextTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = math.random(ANIM.SPARKLE_SIZE_MIN, ANIM.SPARKLE_SIZE_MAX)
		label.TextScaled = false
		label.Size = UDim2.fromOffset(20, 20)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.ZIndex = 10 + i

		-- Random start position around the sticker
		local angle = math.random() * math.pi * 2
		local dist = math.random() * 0.25 + 0.15
		label.Position = UDim2.fromScale(0.5 + math.cos(angle) * dist, 0.5 + math.sin(angle) * dist)
		label.Parent = parent
		table.insert(sparkles, label)

		-- Stagger animation
		local delay = math.random() * ANIM.SPARKLE_DELAY_MAX
		task.delay(delay, function()
			if not label.Parent then
				return
			end

			-- Fade in + move outward
			local endDist = dist + 0.15 + math.random() * 0.1
			local endPos = UDim2.fromScale(0.5 + math.cos(angle) * endDist, 0.5 + math.sin(angle) * endDist - 0.15)
			local tweenIn = TweenService:Create(
				label,
				TweenInfo.new(ANIM.SPARKLE_FADE_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ TextTransparency = 0.1, Position = endPos }
			)
			tweenIn:Play()
			tweenIn.Completed:Once(function()
				if not label.Parent then
					return
				end

				-- Hold briefly then fade out
				task.delay(ANIM.SPARKLE_HOLD, function()
					if not label.Parent then
						return
					end
					local tweenOut = TweenService:Create(
						label,
						TweenInfo.new(ANIM.SPARKLE_FADE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
						{ TextTransparency = 1 }
					)
					tweenOut:Play()
					tweenOut.Completed:Once(function()
						if label.Parent then
							label:Destroy()
						end
					end)
				end)
			end)
		end)
	end
end

-- ============================================================
-- ENTRANCE ANIMATION (pop-in bounce)
-- ============================================================
local function playEntrance(active: ActiveSticker)
	if not ANIM then
		return
	end

	active.entrancePlayed = true
	active.exitPlaying = false
	local scale = active.scale
	local image = active.image

	-- Initial state
	scale.Scale = 0
	image.ImageTransparency = 1
	image.BackgroundTransparency = 1
	active.gui.Enabled = true

	-- Phase 1: Scale 0 -> overshoot
	local tweenBounce = TweenService:Create(
		scale,
		TweenInfo.new(ANIM.ENTRANCE_DURATION * 0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = ANIM.ENTRANCE_OVERSHOOT }
	)
	local tweenFadeIn = TweenService:Create(
		image,
		TweenInfo.new(ANIM.ENTRANCE_DURATION * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ ImageTransparency = Config.Sticker.IMAGE_TRANSPARENCY, BackgroundTransparency = 0 }
	)

	tweenBounce:Play()
	tweenFadeIn:Play()

	tweenBounce.Completed:Once(function()
		if active.exitPlaying then
			return
		end

		-- Phase 2: Settle to 1.0
		local tweenSettle = TweenService:Create(
			scale,
			TweenInfo.new(ANIM.ENTRANCE_DURATION * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1 }
		)
		tweenSettle:Play()
	end)
end

-- ============================================================
-- EXIT ANIMATION (fade-out + scale down)
-- ============================================================
local function playExit(active: ActiveSticker, onComplete: (() -> ())?)
	if not ANIM then
		return
	end

	active.exitPlaying = true
	local scale = active.scale
	local image = active.image

	-- Stop idle
	if active.heartbeatConn then
		active.heartbeatConn:Disconnect()
		active.heartbeatConn = nil
	end

	-- Reset studs offset to base (stop float)
	active.gui.StudsOffset = Vector3.new(
		Config.Sticker.BILLBOARD_STUDS_OFFSET.X,
		active.baseStudsOffsetY,
		Config.Sticker.BILLBOARD_STUDS_OFFSET.Z
	)

	-- Animate out
	local tweenScale = TweenService:Create(
		scale,
		TweenInfo.new(ANIM.EXIT_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.In),
		{ Scale = ANIM.EXIT_SCALE }
	)
	local tweenFade = TweenService:Create(
		image,
		TweenInfo.new(ANIM.EXIT_DURATION * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ ImageTransparency = 1, BackgroundTransparency = 1 }
	)

	tweenScale:Play()
	tweenFade:Play()

	local finished = false
	local function finishExit()
		if finished then
			return
		end
		finished = true
		active.gui.Enabled = false
		active.entrancePlayed = false
		active.exitPlaying = false
		scale.Scale = 0
		image.ImageTransparency = 1
		image.BackgroundTransparency = 1
		if onComplete then
			onComplete()
		end
	end

	tweenScale.Completed:Once(finishExit)
	if ANIM then
		task.delay(ANIM.EXIT_DURATION + 0.35, function()
			if active.exitPlaying then
				finishExit()
			end
		end)
	end
end

-- ============================================================
-- IDLE ANIMATION (gentle float + subtle wobble)
-- ============================================================
local function startIdle(active: ActiveSticker)
	if not ANIM then
		return
	end

	-- Random phase so multiple stickers don't animate in sync
	active.idleTime = math.random() * math.pi * 2
	-- Register into the shared per-frame loop instead of a per-sticker connection
	ensureSharedStickerHeartbeat()
end

-- ============================================================
-- STICKER APPEAR / DISAPPEAR HANDLER
-- ============================================================
local function onStickerAppear(character: Model, gui: BillboardGui, imageLabel: ImageLabel)
	-- Cleanup any previous active state
	cleanupSticker(character)

	local scale = ensureUIScale(imageLabel)
	local active: ActiveSticker = {
		gui = gui,
		image = imageLabel,
		scale = scale,
		idleTime = 0,
		baseStudsOffsetY = Config.Sticker.BILLBOARD_STUDS_OFFSET.Y,
		entrancePlayed = false,
		exitPlaying = false,
		sparkles = {},
	}
	activeStickers[character] = active

	-- Prevent server's Enabled = true from showing raw sticker
	gui.Enabled = false
	scale.Scale = 0
	imageLabel.ImageTransparency = 1
	imageLabel.BackgroundTransparency = 1

	-- Scale origin = bottom-left so the pop-in expands from that corner
	imageLabel.AnchorPoint = Vector2.new(0, 1)
	imageLabel.Position = UDim2.fromScale(0, 1)

	-- Small delay so server replication settles
	task.defer(function()
		if activeStickers[character] ~= active then
			return
		end
		playEntrance(active)

		-- Start idle after entrance settles
		if ANIM then
			task.delay(ANIM.ENTRANCE_DURATION + 0.05, function()
				if activeStickers[character] == active and not active.exitPlaying then
					startIdle(active)
				end
			end)
		end
	end)
end

local function onStickerDisappear(character: Model)
	local active = activeStickers[character]
	if active and active.entrancePlayed and not active.exitPlaying then
		playExit(active, function()
			cleanupSticker(character)
		end)
		return
	end

	forceHideStickerBillboard(character)
	cleanupSticker(character)
end

-- ============================================================
-- CHARACTER WATCHER
-- ============================================================

local function hookCharacter(character: Model, player: Player)
	cleanupCharacter(character)
	local conns = {} :: { RBXScriptConnection }
	characterConns[character] = conns

	-- Watch for the BillboardGui arriving (may not exist yet)
	local function tryHook()
		local gui, imageLabel = findStickerGui(character)
		if not gui or not imageLabel then
			return
		end

		local function syncStickerFromState()
			local g, il = findStickerGui(character)
			if not g or not il then
				return
			end

			local imageAttr = getActiveStickerImage(player)
			if imageAttr ~= "" and il.Image ~= imageAttr then
				il.Image = imageAttr
			end

			local active = playerHasActiveSticker(player)
			if active then
				if not activeStickers[character] then
					onStickerAppear(character, g, il)
				end
			else
				onStickerDisappear(character)
			end
		end

		syncStickerFromState()

		table.insert(
			conns,
			player:GetAttributeChangedSignal(Config.Sticker.STICKER_IMAGE_ATTRIBUTE):Connect(syncStickerFromState)
		)

		table.insert(
			conns,
			player:GetAttributeChangedSignal(Config.Sticker.STICKER_CLEAR_ATTRIBUTE):Connect(function()
				onStickerDisappear(character)
			end)
		)

		table.insert(
			conns,
			imageLabel:GetPropertyChangedSignal("Image"):Connect(syncStickerFromState)
		)

		table.insert(
			conns,
			gui:GetPropertyChangedSignal("Enabled"):Connect(function()
				if gui.Enabled then
					syncStickerFromState()
					return
				end
				-- Entrance animation sets Enabled=false before playEntrance; do not treat that as clear.
				if playerHasActiveSticker(player) then
					return
				end
				onStickerDisappear(character)
			end)
		)
	end

	-- Try immediately
	tryHook()

	-- Watch adornee parts in the same priority as StickerService (UpperTorso first, not Head-only).
	local priority = Config.Sticker.DEFAULT_ADORNEE_PRIORITY
	local function watchAdorneePart(part: BasePart)
		table.insert(
			conns,
			part.ChildAdded:Connect(function(child: Instance)
				if child.Name == Config.Sticker.BILLBOARD_GUI_NAME and child:IsA("BillboardGui") then
					task.defer(tryHook)
				end
			end)
		)
	end

	for _, partName in ipairs(priority) do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			watchAdorneePart(part)
		end
	end

	table.insert(
		conns,
		character.ChildAdded:Connect(function(child: Instance)
			if not child:IsA("BasePart") then
				return
			end
			for _, partName in ipairs(priority) do
				if child.Name == partName then
					watchAdorneePart(child)
					task.defer(tryHook)
					break
				end
			end
		end)
	)

	-- If adornee already exists but GUI arrives later via replication, one deferred retry helps.
	task.defer(function()
		if character.Parent and CharacterReady.findAdornee(character, priority) then
			tryHook()
		end
	end)
end

local function hookPlayer(player: Player)
	local conns = {} :: { RBXScriptConnection }
	playerConns[player] = conns

	local function onCharacterAdded(character: Model)
		hookCharacter(character, player)
	end

	table.insert(conns, player.CharacterAdded:Connect(onCharacterAdded))

	if player.Character then
		task.defer(function()
			if player.Character then
				onCharacterAdded(player.Character)
			end
		end)
	end
end

local function unhookPlayer(player: Player)
	-- Clean up character
	if player.Character then
		cleanupCharacter(player.Character)
	end

	-- Disconnect player connections
	local conns = playerConns[player]
	if conns then
		for _, conn in ipairs(conns) do
			conn:Disconnect()
		end
		playerConns[player] = nil
	end
end

-- ============================================================
-- PUBLIC API
-- ============================================================
local globalConns: { RBXScriptConnection } = {}
local isInitialized = false

function StickerBillboardAnimator.init(deps: { logger: any? })
	if isInitialized then
		return
	end
	isInitialized = true

	-- Resolve animation config
	local cfg = (Config :: any).StickerAnim
	if not cfg then
		-- Fallback defaults if config section is missing
		ANIM = {
			ENTRANCE_DURATION = 0.38,
			ENTRANCE_OVERSHOOT = 1.18,
			EXIT_DURATION = 0.32,
			EXIT_SCALE = 0.7,
			FLOAT_SPEED = 2.2,
			FLOAT_AMPLITUDE = 0.12,
			WOBBLE_SPEED = 1.8,
			WOBBLE_AMPLITUDE = 2.5,
			SPARKLE_COUNT = 5,
			SPARKLE_SIZE_MIN = 10,
			SPARKLE_SIZE_MAX = 16,
			SPARKLE_DELAY_MAX = 0.2,
			SPARKLE_FADE_IN = 0.25,
			SPARKLE_HOLD = 0.3,
			SPARKLE_FADE_OUT = 0.35,
		}
	else
		ANIM = cfg
	end

	-- Hook existing players
	for _, player in ipairs(Players:GetPlayers()) do
		hookPlayer(player)
	end

	table.insert(globalConns, Players.PlayerAdded:Connect(hookPlayer))
	table.insert(globalConns, Players.PlayerRemoving:Connect(unhookPlayer))
end

function StickerBillboardAnimator.destroy()
	for _, conn in ipairs(globalConns) do
		conn:Disconnect()
	end
	table.clear(globalConns)

	for _, player in ipairs(Players:GetPlayers()) do
		unhookPlayer(player)
	end

	table.clear(activeStickers)
	table.clear(characterConns)
	table.clear(playerConns)
	isInitialized = false
end

return StickerBillboardAnimator
