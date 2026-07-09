--!strict
-- Client motion for workspace SurfaceGui leaderboards (server paints static data).
-- LiveChatDonations is intentionally not handled here yet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local LeaderboardIdentity = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.LeaderboardIdentity)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local WorkspaceLeaderboardRenderer = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Leaderboards.WorkspaceLeaderboardRenderer)

local log = Logger.new("Client.WorkspaceLeaderboards")

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

type BoardSpec = WorkspaceLeaderboardRenderer.BoardSpec

local BOARD_SPECS = WorkspaceLeaderboardRenderer.BOARD_SPECS
local resolveBoard = WorkspaceLeaderboardRenderer.resolveBoard

local latestPayload: any = nil
local lastLeaderboardRevisionSeen = -1

type DailySpec = {
	rootPart: string,
	guiName: string,
	dataKey: string,
	kind: string,
	warnKey: string,
}

local DAILY_SAWERIA_SPEC: DailySpec = {
	rootPart = "DailyDonations",
	guiName = "DailyDonationsWrapper",
	dataKey = "dailySaweria",
	kind = "saweria",
	warnKey = "dailySaweria",
}

local DAILY_ROBUX_SPEC: DailySpec = {
	rootPart = "DailyDonationsRobux",
	guiName = "DailyRobuxDonationsWrapper",
	dataKey = "dailyRobux",
	kind = "playerRobux",
	warnKey = "dailyRobux",
}

-- Daily board specs; Robux wrapper omitted when Config.Leaderboards.DAILY_ROBUX_ENABLED is false.
local function buildDailySpecs(): { DailySpec }
	local specs = { DAILY_SAWERIA_SPEC }
	if Config.Leaderboards.DAILY_ROBUX_ENABLED == true then
		table.insert(specs, DAILY_ROBUX_SPEC)
	end
	return specs
end

local DAILY_SPECS: { DailySpec } = buildDailySpecs()

local VALUE_PULSE_UP = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local VALUE_PULSE_DOWN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local IMAGE_PULSE_UP = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local IMAGE_PULSE_DOWN = TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CARD_ENTER = TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FOOTER_BLINK = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local PODIUM_RISE = TweenInfo.new(0.9, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local VALUE_COUNTER_DURATION = 0.9
local PODIUM_SEQUENCE_GAP = 0.2
local PODIUM_LOOP_INTERVAL = 30
local SUPPORTING_CARD_FADE = TweenInfo.new(0.32, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local DAILY_CARD_LIMIT = 3
-- Organic easing curves: Sine/Cubic for smoothness, low-amplitude Back to avoid overshoot.
local DAILY_TITLE_POP = TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local DAILY_TITLE_MOVE = TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local DAILY_LIST_POP = TweenInfo.new(0.6, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
local DAILY_CARD_POP = TweenInfo.new(0.55, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
local DAILY_CARD_OUT = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local DAILY_CARD_STAGGER = 0.09 -- delay between card entries for the domino effect
local DAILY_BATCH_HOLD = 5.2
local DAILY_SEQUENCE_RESTART_DELAY = 0.6

local function weakKeyTable<T>(): T
	return setmetatable({}, { __mode = "k" }) :: any
end

local lastValueTextByLabel: { [TextLabel]: string } = weakKeyTable()
local valueNumberByLabel: { [TextLabel]: number } = weakKeyTable()
local valueCounterGenerationByLabel: { [TextLabel]: number } = weakKeyTable()
local supportingCardFingerprintByCard: { [GuiObject]: string } = weakKeyTable()
local supportingCardFadeGenerationByCard: { [GuiObject]: number } = weakKeyTable()
local originalTextSizeByLabel: { [TextLabel]: number } = weakKeyTable()
local lastTimestampTextByLabel: { [TextLabel]: string } = weakKeyTable()
local originalTextTransparencyByLabel: { [TextLabel]: number } = weakKeyTable()
local originalTextStrokeTransparencyByLabel: { [TextLabel]: number } = weakKeyTable()
local originalImageSizeByLabel: { [ImageLabel]: UDim2 } = weakKeyTable()
local originalImageTransparencyByLabel: { [ImageLabel]: number } = weakKeyTable()
local originalBackgroundTransparencyByGui: { [GuiObject]: number } = weakKeyTable()
local originalStrokeTransparencyByStroke: { [UIStroke]: number } = weakKeyTable()
local avatarPulsedByImage: { [ImageLabel]: boolean } = weakKeyTable()
local cardEntered: { [GuiObject]: boolean } = weakKeyTable()
local originalCardRotation: { [GuiObject]: number } = weakKeyTable()
local originalPodiumSize: { [GuiObject]: UDim2 } = weakKeyTable()
local podiumLoopStartedByGui: { [SurfaceGui]: boolean } = weakKeyTable()
local dailyShowcaseStateByGui: { [SurfaceGui]: any } = weakKeyTable()
local dailyResolverWarnedByKey: { [string]: boolean } = {}
local dailyOriginalAnchorByGui: { [GuiObject]: Vector2 } = weakKeyTable()
local dailyOriginalPositionByGui: { [GuiObject]: UDim2 } = weakKeyTable()

local animatePodiumValueCounter: (podium: GuiObject, spec: BoardSpec) -> ()
local playAttentionShake: (guiObject: GuiObject, scaleAmount: number?) -> ()

local function playTween(instance: Instance, info: TweenInfo, goals: { [string]: any }): Tween
	local tween = TweenService:Create(instance, info, goals)
	tween:Play()
	return tween
end

local function ensureUIScale(guiObject: GuiObject): UIScale
	local existing = guiObject:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = guiObject
	return scale
end

local function scaleUDim2(size: UDim2, scale: number): UDim2
	return UDim2.new(
		size.X.Scale * scale,
		math.round(size.X.Offset * scale),
		size.Y.Scale * scale,
		math.round(size.Y.Offset * scale)
	)
end

local function pulseValueLabel(label: TextLabel)
	local originalSize = originalTextSizeByLabel[label] or label.TextSize
	originalTextSizeByLabel[label] = originalSize
	label.TextSize = originalSize

	local up = playTween(label, VALUE_PULSE_UP, {
		TextSize = originalSize + math.max(2, originalSize * 0.12),
	})
	up.Completed:Once(function()
		if label.Parent then
			playTween(label, VALUE_PULSE_DOWN, { TextSize = originalSize })
		end
	end)
end

local function blinkFooterLabel(label: TextLabel)
	local originalTransparency = originalTextTransparencyByLabel[label] or label.TextTransparency
	originalTextTransparencyByLabel[label] = originalTransparency
	label.TextTransparency = originalTransparency

	local blinkTransparency = math.clamp(originalTransparency + 0.45, 0, 0.85)
	local out = playTween(label, FOOTER_BLINK, { TextTransparency = blinkTransparency })
	out.Completed:Once(function()
		if label.Parent then
			playTween(label, FOOTER_BLINK, { TextTransparency = originalTransparency })
		end
	end)
end

local function pulseImage(imageLabel: ImageLabel)
	if imageLabel.Image == "" then
		return
	end

	local originalSize = originalImageSizeByLabel[imageLabel] or imageLabel.Size
	originalImageSizeByLabel[imageLabel] = originalSize
	imageLabel.Size = originalSize

	local up = playTween(imageLabel, IMAGE_PULSE_UP, { Size = scaleUDim2(originalSize, 1.06) })
	up.Completed:Once(function()
		if imageLabel.Parent then
			playTween(imageLabel, IMAGE_PULSE_DOWN, { Size = originalSize })
		end
	end)
end

local function animateCardEntrance(card: GuiObject, rank: number)
	if cardEntered[card] then
		return
	end

	cardEntered[card] = true
	local originalRotation = originalCardRotation[card] or card.Rotation
	originalCardRotation[card] = originalRotation
	card.Rotation = originalRotation + if rank % 2 == 0 then -1.5 else 1.5

	task.delay(math.min((rank - 1) * 0.035, 0.35), function()
		if card.Parent then
			playTween(card, CARD_ENTER, { Rotation = originalRotation })
		end
	end)
end

local function animatePodiumRise(podium: GuiObject, spec: BoardSpec)
	local originalSize = originalPodiumSize[podium] or podium.Size
	originalPodiumSize[podium] = originalSize
	podium.Size = UDim2.new(originalSize.X.Scale, originalSize.X.Offset, 0, 0)
	animatePodiumValueCounter(podium, spec)
	playTween(podium, PODIUM_RISE, { Size = originalSize })
end

local function findPodiumInCard(card: GuiObject): GuiObject?
	local podium = card:FindFirstChild("Podium", true)
	if podium and podium:IsA("GuiObject") then
		return podium
	end
	return nil
end

local function playPodiumSequence(gui: SurfaceGui, spec: BoardSpec)
	for rank = 1, 3 do
		if not gui.Parent then
			return
		end

		local card = gui:FindFirstChild(spec.topCards[rank], true)
		if card and card:IsA("GuiObject") and card.Visible then
			local podium = findPodiumInCard(card)
			if podium and podium.Visible then
				animatePodiumRise(podium, spec)
				task.wait(PODIUM_RISE.Time + PODIUM_SEQUENCE_GAP)
			end
		end
	end
end

local function ensurePodiumLoop(gui: SurfaceGui, spec: BoardSpec)
	if podiumLoopStartedByGui[gui] then
		return
	end

	podiumLoopStartedByGui[gui] = true
	task.spawn(function()
		task.wait(2)
		while gui.Parent do
			local startedAt = os.clock()
			playPodiumSequence(gui, spec)
			task.wait(math.max(1, PODIUM_LOOP_INTERVAL - (os.clock() - startedAt)))
		end
		podiumLoopStartedByGui[gui] = nil
	end)
end

local function formatGrouped(value: number): string
	local raw = tostring(math.floor(math.max(value, 0)))
	local result = ""
	local len = #raw
	for index = 1, len do
		if index > 1 and (len - index + 1) % 3 == 0 then
			result ..= "."
		end
		result ..= raw:sub(index, index)
	end
	return result
end

local function formatDonationValue(kind: string, value: number): string
	local grouped = formatGrouped(value)
	if kind == "saweria" or kind == "saweriaPoster" then
		return "RP." .. grouped
	end
	return grouped
end

-- Generic GUI names that should not be used for global lookup; they are too
-- common and would collide with unrelated SurfaceGuis in the workspace.
local GENERIC_GUI_NAMES: { [string]: boolean } = {
	SurfaceGui = true,
	ScreenGui = true,
	BillboardGui = true,
	[""] = true,
}

local function isGenericGuiName(name: string): boolean
	return GENERIC_GUI_NAMES[name] == true
end

-- Find a SurfaceGui by name anywhere in workspace (part rename does not break lookup).
local function findSurfaceGuiByNameGlobal(name: string): SurfaceGui?
	local direct = workspace:FindFirstChild(name, true)
	if direct and direct:IsA("SurfaceGui") then
		return direct
	end
	return nil
end

-- Find SurfaceGui under a named root part (legacy fallback when global lookup misses).
local function findSurfaceGuiInPart(part: Instance, expectedName: string): (SurfaceGui?, boolean)
	local gui = part:FindFirstChild(expectedName, true)
	if gui and gui:IsA("SurfaceGui") then
		return gui, false
	end
	for _, descendant in ipairs(part:GetDescendants()) do
		if descendant:IsA("SurfaceGui") then
			return descendant, true
		end
	end
	return nil, false
end

-- Anti-spam logger: warns once per (kind, key) pair.
local resolverWarnedByKey: { [string]: boolean } = {}
local function warnOnce(key: string, message: string, payload: any)
	if resolverWarnedByKey[key] then
		return
	end
	resolverWarnedByKey[key] = true
	log:warn(message, payload)
end

local function resolveDailyDonationsGui(spec: DailySpec): SurfaceGui?
	-- Strategy 1: global search by SurfaceGui name.
	local globalHit = findSurfaceGuiByNameGlobal(spec.guiName)
	if globalHit then
		return globalHit
	end

	-- Strategy 2: part-scoped search (backward compatible).
	local part = workspace:FindFirstChild(spec.rootPart)
	if part then
		local scoped, autoDiscovered = findSurfaceGuiInPart(part, spec.guiName)
		if scoped then
			if autoDiscovered then
				warnOnce("daily:" .. spec.warnKey, "Daily SurfaceGui auto-discovered (name mismatch)", {
					expected = spec.guiName,
					found = scoped.Name,
					part = spec.rootPart,
				})
			end
			return scoped
		end
	end

	if not dailyResolverWarnedByKey[spec.warnKey] then
		dailyResolverWarnedByKey[spec.warnKey] = true
		log:warn(spec.guiName .. " SurfaceGui not found")
	end
	return nil
end

local function findDescendant(root: Instance, names: { string }, className: string?): Instance?
	for _, name in ipairs(names) do
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant.Name == name and (not className or descendant.ClassName == className) then
				return descendant
			end
		end
	end
	return nil
end

local function findPath(root: Instance, path: { string }, className: string?): Instance?
	local current: Instance? = root
	for _, segment in ipairs(path) do
		if not current then
			return nil
		end
		current = current:FindFirstChild(segment)
	end

	if current and (not className or current.ClassName == className) then
		return current
	end

	return nil
end

local function setFirstText(root: Instance, names: { string }, text: string)
	local label = findDescendant(root, names, "TextLabel")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

-- Set every TextLabel matching any of the given names (podium cards may duplicate names).
local function setAllNamedTexts(root: Instance, names: { string }, text: string)
	local nameSet: { [string]: boolean } = {}
	for _, name in ipairs(names) do
		nameSet[name] = true
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("TextLabel") and nameSet[descendant.Name] then
			descendant.Text = text
		end
	end
end

local function setAllNamedImages(root: Instance, names: { string }, image: string)
	local nameSet: { [string]: boolean } = {}
	for _, name in ipairs(names) do
		nameSet[name] = true
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ImageLabel") and nameSet[descendant.Name] then
			descendant.Image = image
			descendant.Visible = image ~= ""
		end
	end
end

local DISPLAY_NAME_LABEL_NAMES = { "PlayerDisplayName", "CommunityName" }
local USERNAME_LABEL_NAMES = { "PlayerUsername", "Username", "CommunityID" }
local THUMBNAIL_IMAGE_NAMES = {
	"PlayerImageThumbnail",
	"PlayerThumbnailImage",
	"PlayerThumbnailIcon",
	"PlayerThumbnail",
	"PlayerThumbnailPic",
	"PlayerProfileThumbnail",
	"PlayerProfilePicture",
	"ProfilePicture",
	"CommunityIcon",
}

local function setFirstImage(root: Instance, names: { string }, image: string): (ImageLabel?, boolean)
	local imageLabel = findDescendant(root, names, "ImageLabel")
	if imageLabel and imageLabel:IsA("ImageLabel") then
		local changed = image ~= "" and imageLabel.Image ~= image
		imageLabel.Image = image
		return imageLabel, changed
	end
	return nil, false
end

local function setFirstImageVisible(root: Instance, names: { string }, visible: boolean)
	local imageLabel = findDescendant(root, names, "ImageLabel")
	if imageLabel and imageLabel:IsA("ImageLabel") then
		imageLabel.Visible = visible
	end
end

local function setTextAtPath(root: Instance, path: { string }, text: string): TextLabel?
	local label = findPath(root, path, "TextLabel")
	if label and label:IsA("TextLabel") then
		label.Text = text
		return label
	end
	return nil
end

local function setImageAtPath(root: Instance, path: { string }, image: string): (ImageLabel?, boolean)
	local imageLabel = findPath(root, path, "ImageLabel")
	if imageLabel and imageLabel:IsA("ImageLabel") then
		local changed = image ~= "" and imageLabel.Image ~= image
		imageLabel.Image = image
		return imageLabel, changed
	end
	return nil, false
end

local function resolveRowThumbnail(card: Instance, kind: string): ImageLabel?
	local preferredPaths = if kind == "saweria"
		then {
			{ "Wrapper", "PlayerThumbnailImage" },
			{ "Wrapper", "PlayerThumbnail" },
			{ "Wrapper", "PlayerThumbnailPic" },
			{ "Wrapper", "PlayerProfileThumbnail" },
			{ "Wrapper", "PlayerProfilePicture" },
			{ "Wrapper", "ProfilePicture" },
		}
		elseif kind == "community" then {
			{ "Wrapper", "PlayerThumbnailImage" },
			{ "Wrapper", "CommunityIcon" },
		}
		else {
			{ "Wrapper", "PlayerThumbnailImage" },
		}

	for _, path in ipairs(preferredPaths) do
		local image = findPath(card, path, "ImageLabel")
		if image and image:IsA("ImageLabel") then
			return image
		end
	end

	return findDescendant(card, {
		"PlayerImageThumbnail",
		"PlayerThumbnailImage",
		"PlayerThumbnailIcon",
		"PlayerThumbnail",
		"PlayerThumbnailPic",
		"PlayerProfileThumbnail",
		"PlayerProfilePicture",
		"ProfilePicture",
		"CommunityIcon",
	}, "ImageLabel") :: ImageLabel?
end

local function findValueLabel(root: Instance, kind: string): TextLabel?
	local valueNames = if kind == "likes"
		then { "TotalLikesValue" }
		elseif kind == "community" then { "DonationTotalValue", "TotalDonationValue", "TotalDonationsValue" }
		elseif kind == "saweria" then { "TotalValue", "TotalDonationValue", "TotalDonation" }
		else { "RobuxTotalValue", "TotalDonationsValue", "TotalValue" }

	local named = findDescendant(root, valueNames, "TextLabel")
	if named and named:IsA("TextLabel") then
		return named
	end

	local wrapperNames = if kind == "likes"
		then { "TotalLikesWrapper" }
		elseif kind == "community" then { "DonationTotal", "TotalDonationWrapper", "TotalLikesWrapper" }
		elseif kind == "saweria" then { "TotalDonoWrapper", "TotalDonationWrapper", "TotalDonation" }
		else { "TotalDonationsWrapper", "TotalDonationWrapper" }

	local wrapper = findDescendant(root, wrapperNames, nil)
	if wrapper then
		for _, descendant in ipairs(wrapper:GetDescendants()) do
			if descendant:IsA("TextLabel") then
				return descendant
			end
		end
	end
	return nil
end

local function nextValueCounterGeneration(label: TextLabel): number
	local generation = (valueCounterGenerationByLabel[label] or 0) + 1
	valueCounterGenerationByLabel[label] = generation
	return generation
end

local function isTopCardName(spec: BoardSpec, name: string): boolean
	for _, topCardName in ipairs(spec.topCards) do
		if topCardName == name then
			return true
		end
	end

	return false
end

local function findPodiumValueLabel(podium: GuiObject, spec: BoardSpec): TextLabel?
	local current: Instance? = podium
	for _ = 1, 8 do
		if not current then
			break
		end

		if isTopCardName(spec, current.Name) then
			return findValueLabel(current, spec.kind)
		end
		current = current.Parent
	end

	return if podium.Parent then findValueLabel(podium.Parent, spec.kind) else findValueLabel(podium, spec.kind)
end

animatePodiumValueCounter = function(podium: GuiObject, spec: BoardSpec)
	local label = findPodiumValueLabel(podium, spec)
	if not label or not label.Visible then
		return
	end

	local finalValue = valueNumberByLabel[label]
	if finalValue == nil then
		finalValue = tonumber((label.Text:gsub("[^%d]", ""))) or 0
	end

	finalValue = math.floor(math.max(finalValue, 0))
	if finalValue <= 0 then
		label.Text = formatDonationValue(spec.kind, 0)
		return
	end

	local generation = nextValueCounterGeneration(label)
	local startedAt = os.clock()
	label.Text = formatDonationValue(spec.kind, 0)

	task.spawn(function()
		while label.Parent and valueCounterGenerationByLabel[label] == generation do
			local alpha = math.clamp((os.clock() - startedAt) / VALUE_COUNTER_DURATION, 0, 1)
			local easedAlpha = 1 - ((1 - alpha) ^ 3)
			label.Text = formatDonationValue(spec.kind, finalValue * easedAlpha)

			if alpha >= 1 then
				break
			end

			RunService.Heartbeat:Wait()
		end

		if label.Parent and valueCounterGenerationByLabel[label] == generation then
			label.Text = formatDonationValue(spec.kind, finalValue)
		end
	end)
end

local function nextSupportingCardFadeGeneration(card: GuiObject): number
	local generation = (supportingCardFadeGenerationByCard[card] or 0) + 1
	supportingCardFadeGenerationByCard[card] = generation
	return generation
end

local function applySupportingFadeStart(instance: Instance)
	if instance:IsA("GuiObject") then
		originalBackgroundTransparencyByGui[instance] = originalBackgroundTransparencyByGui[instance]
			or instance.BackgroundTransparency
		instance.BackgroundTransparency = 1
	end

	if instance:IsA("TextLabel") then
		originalTextTransparencyByLabel[instance] = originalTextTransparencyByLabel[instance]
			or instance.TextTransparency
		originalTextStrokeTransparencyByLabel[instance] = originalTextStrokeTransparencyByLabel[instance]
			or instance.TextStrokeTransparency
		instance.TextTransparency = 1
		instance.TextStrokeTransparency = 1
	end

	if instance:IsA("ImageLabel") then
		originalImageTransparencyByLabel[instance] = originalImageTransparencyByLabel[instance]
			or instance.ImageTransparency
		instance.ImageTransparency = 1
	end

	if instance:IsA("UIStroke") then
		originalStrokeTransparencyByStroke[instance] = originalStrokeTransparencyByStroke[instance]
			or instance.Transparency
		instance.Transparency = 1
	end
end

local function tweenSupportingFadeTarget(instance: Instance)
	if instance:IsA("GuiObject") then
		playTween(instance, SUPPORTING_CARD_FADE, {
			BackgroundTransparency = originalBackgroundTransparencyByGui[instance] or instance.BackgroundTransparency,
		})
	end

	if instance:IsA("TextLabel") then
		playTween(instance, SUPPORTING_CARD_FADE, {
			TextTransparency = originalTextTransparencyByLabel[instance] or instance.TextTransparency,
			TextStrokeTransparency = originalTextStrokeTransparencyByLabel[instance] or instance.TextStrokeTransparency,
		})
	end

	if instance:IsA("ImageLabel") then
		playTween(instance, SUPPORTING_CARD_FADE, {
			ImageTransparency = originalImageTransparencyByLabel[instance] or instance.ImageTransparency,
		})
	end

	if instance:IsA("UIStroke") then
		playTween(instance, SUPPORTING_CARD_FADE, {
			Transparency = originalStrokeTransparencyByStroke[instance] or instance.Transparency,
		})
	end
end

local function animateSupportingCardFade(card: GuiObject, rank: number)
	local generation = nextSupportingCardFadeGeneration(card)
	local delaySeconds = math.min(math.max(rank - 4, 0) * 0.035, 0.35)

	task.delay(delaySeconds, function()
		if not card.Parent or supportingCardFadeGenerationByCard[card] ~= generation then
			return
		end

		local fadeInstances: { Instance } = { card }
		for _, descendant in ipairs(card:GetDescendants()) do
			table.insert(fadeInstances, descendant)
		end

		for _, instance in ipairs(fadeInstances) do
			if instance.Parent or instance == card then
				applySupportingFadeStart(instance)
			end
		end

		if not card.Parent or supportingCardFadeGenerationByCard[card] ~= generation then
			return
		end

		for _, instance in ipairs(fadeInstances) do
			if instance.Parent or instance == card then
				tweenSupportingFadeTarget(instance)
			end
		end
	end)
end

local function setValue(root: Instance, kind: string, value: number, shouldPulse: boolean?)
	local label = findValueLabel(root, kind)
	if label then
		local normalizedValue = math.floor(math.max(value, 0))
		local text = formatGrouped(normalizedValue)
		local previous = lastValueTextByLabel[label]
		valueNumberByLabel[label] = normalizedValue
		nextValueCounterGeneration(label)
		label.Text = text
		if shouldPulse ~= false and previous and previous ~= text then
			pulseValueLabel(label)
		end
		lastValueTextByLabel[label] = text
	end
end

local function setRankText(root: Instance, rank: number)
	local rankText = "#" .. tostring(rank)
	local named = findDescendant(root, { "Rank", "PlayerRank", "CommunityRank" }, "TextLabel")
	if named and named:IsA("TextLabel") then
		named.Text = rankText
		return
	end

	local wrapper = findDescendant(root, { "RankWrapper", "PlayerRankWrapper", "CommunityRankWrapper" }, nil)
	if wrapper then
		for _, descendant in ipairs(wrapper:GetDescendants()) do
			if descendant:IsA("TextLabel") then
				descendant.Text = rankText
				return
			end
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("TextLabel") and descendant.Text:match("^#%d+$") then
			descendant.Text = rankText
			return
		end
	end
end

local function getEntryDisplayName(entry: any, kind: string): string
	if kind == "community" then
		return tostring(entry.communityName or ("Community " .. tostring(entry.communityId or "")))
	end

	local username = if type(entry.username) == "string" then entry.username else ""
	local displayName = if type(entry.displayName) == "string" then entry.displayName else ""

	if displayName ~= "" and not LeaderboardIdentity.looksLikeFallbackName(displayName) then
		return displayName
	end

	if kind == "saweria" or kind == "saweriaPoster" then
		local saweriaName = if type(entry.saweriaName) == "string" then entry.saweriaName else ""
		if saweriaName ~= "" then
			return saweriaName
		end
	end

	if username ~= "" and not LeaderboardIdentity.looksLikeFallbackName(username) then
		return username
	end

	return "Unknown"
end

local function getEntryUsernameText(entry: any, kind: string): string
	if kind == "community" then
		return "ID : " .. tostring(entry.communityId or "")
	end

	local username = if type(entry.username) == "string" then entry.username else ""
	username = username:gsub("^@", "")
	if username == "" then
		return if kind == "saweria" or kind == "saweriaPoster" then "Unlinked donor" else ""
	end
	return "@" .. username
end

local function getEntryImage(entry: any, kind: string): string
	if kind == "community" then
		return tostring(entry.communityLogo or "")
	end

	local thumbnail = if type(entry.thumbnail) == "string" then entry.thumbnail else ""
	if thumbnail ~= "" then
		return thumbnail
	end

	local userId = tonumber(entry and entry.userId)
	if userId and userId > 0 then
		return LeaderboardIdentity.getUserThumbnail(userId, 150)
	end
	return ""
end

local function getCardFingerprint(entry: any, rank: number, kind: string): string
	return table.concat({
		tostring(rank),
		kind,
		tostring(entry.userId or ""),
		tostring(entry.communityId or ""),
		tostring(entry.username or ""),
		tostring(entry.saweriaName or ""),
		tostring(entry.displayName or ""),
		tostring(entry.communityName or ""),
		tostring(entry.total or 0),
		tostring(entry.thumbnail or ""),
		tostring(entry.communityLogo or ""),
	}, "|")
end

local updateTimestamp: (gui: SurfaceGui, updatedAt: number) -> ()

local function updateCard(
	card: GuiObject,
	entry: any?,
	rank: number,
	kind: string,
	shouldSetLayoutOrder: boolean?,
	forceBasicStyle: boolean?
)
	-- When forceBasicStyle is set, ranks 1-3 are treated as supporting cards.
	local isBasicCard = forceBasicStyle == true or rank >= 4

	if not entry then
		supportingCardFingerprintByCard[card] = nil
		nextSupportingCardFadeGeneration(card)
		card.Visible = false
		return
	end

	local shouldFadeSupportingCard = false
	if isBasicCard then
		local fingerprint = getCardFingerprint(entry, rank, kind)
		shouldFadeSupportingCard = supportingCardFingerprintByCard[card] ~= fingerprint
		supportingCardFingerprintByCard[card] = fingerprint
	end

	card.Visible = true
	if shouldSetLayoutOrder then
		card.LayoutOrder = rank
	end
	setRankText(card, rank)
	setAllNamedTexts(card, DISPLAY_NAME_LABEL_NAMES, getEntryDisplayName(entry, kind))
	setAllNamedTexts(card, USERNAME_LABEL_NAMES, getEntryUsernameText(entry, kind))
	local portraitImage = getEntryImage(entry, kind)
	setAllNamedImages(card, THUMBNAIL_IMAGE_NAMES, portraitImage)
	local imageLabel: ImageLabel? = nil
	local imageChanged = false
	if isBasicCard then
		imageLabel, imageChanged =
			setImageAtPath(card, { "Wrapper", "PlayerThumbnailImage" }, getEntryImage(entry, kind))
		if not imageLabel then
			imageLabel, imageChanged =
				setImageAtPath(card, { "Wrapper", "PlayerThumbnail" }, getEntryImage(entry, kind))
		end
		if not imageLabel then
			imageLabel, imageChanged =
				setImageAtPath(card, { "Wrapper", "PlayerThumbnailPic" }, getEntryImage(entry, kind))
		end
		if not imageLabel then
			imageLabel, imageChanged = setImageAtPath(card, { "Wrapper", "ProfilePicture" }, getEntryImage(entry, kind))
		end
	end
	if not imageLabel then
		imageLabel, imageChanged = setFirstImage(card, THUMBNAIL_IMAGE_NAMES, portraitImage)
	end
	local amountValue = tonumber(entry.total) or 0
	if kind == "saweria" then
		local label = findValueLabel(card, kind)
		if label then
			local normalizedValue = math.floor(math.max(amountValue, 0))
			local text = formatDonationValue(kind, normalizedValue)
			local previous = lastValueTextByLabel[label]
			valueNumberByLabel[label] = normalizedValue
			nextValueCounterGeneration(label)
			label.Text = text
			if previous and previous ~= text then
				pulseValueLabel(label)
			end
			lastValueTextByLabel[label] = text
		end
	else
		setValue(card, kind, amountValue, not isBasicCard)
	end
	if not isBasicCard then
		animateCardEntrance(card, rank)
	elseif shouldFadeSupportingCard then
		animateSupportingCardFade(card, rank)
	end

	if isBasicCard and imageLabel == nil then
		local resolvedRowThumbnail = resolveRowThumbnail(card, kind)
		if resolvedRowThumbnail then
			local nextImage = getEntryImage(entry, kind)
			imageChanged = nextImage ~= "" and resolvedRowThumbnail.Image ~= nextImage
			resolvedRowThumbnail.Image = nextImage
			imageLabel = resolvedRowThumbnail
		end
	end

	if imageLabel and (imageChanged or not avatarPulsedByImage[imageLabel]) and not isBasicCard then
		imageLabel.Visible = true
		avatarPulsedByImage[imageLabel] = true
		task.delay(math.min(rank * 0.04, 0.4), function()
			if imageLabel.Parent then
				pulseImage(imageLabel)
			end
		end)
	elseif imageLabel then
		imageLabel.Visible = true
	end
end

local function getRow(template: GuiObject, rank: number): GuiObject
	if rank == 4 then
		template.LayoutOrder = rank
		return template
	end

	local parent = template.Parent
	local rowName = "GeneratedLeaderboardRow" .. tostring(rank)
	local existing = parent and parent:FindFirstChild(rowName)
	if existing and existing:IsA("GuiObject") then
		return existing
	end

	local clone = template:Clone()
	clone.Name = rowName
	clone.LayoutOrder = rank
	clone.Parent = parent
	return clone
end

local function collectDailyRows(list: GuiObject): { GuiObject }
	local rows = {}
	local template: GuiObject? = nil
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") and (child.Name == "BasicCardTemplate" or child.Name:match("^DailyGeneratedRow")) then
			if child.Name == "BasicCardTemplate" and not template then
				template = child
			end
			table.insert(rows, child)
		end
	end

	if not template and #rows > 0 then
		template = rows[1]
	end

	if template then
		while #rows < DAILY_CARD_LIMIT do
			local clone = template:Clone()
			clone.Name = "DailyGeneratedRow" .. tostring(#rows + 1)
			clone.Parent = list
			table.insert(rows, clone)
		end
	end

	table.sort(rows, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)

	while #rows > DAILY_CARD_LIMIT do
		local row = table.remove(rows)
		if row then
			row.Visible = false
		end
	end

	for index, row in ipairs(rows) do
		row.LayoutOrder = index
	end

	return rows
end

local function playAttentionShake(guiObject: GuiObject, scaleAmount: number?)
	local scale = ensureUIScale(guiObject)
	local originalRotation = guiObject.Rotation
	guiObject.Rotation = originalRotation

	task.spawn(function()
		local amount = scaleAmount or 1.12
		playTween(scale, TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Scale = amount })
		playTween(guiObject, TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Rotation = originalRotation + 3,
		})
		task.wait(0.23)

		for _, angle in ipairs({ -3, 2.5, -1.5, 0 }) do
			if not guiObject.Parent then
				return
			end
			playTween(guiObject, TweenInfo.new(0.11, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Rotation = originalRotation + angle,
			})
			task.wait(0.115)
		end

		if guiObject.Parent then
			playTween(scale, TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Scale = 1 })
			playTween(guiObject, TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Rotation = originalRotation,
			})
		end
	end)
end

local function waitForShowcase(state: any, generation: number, seconds: number): boolean
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		if state.generation ~= generation then
			return false
		end
		task.wait(math.min(0.1, deadline - os.clock()))
	end
	return state.generation == generation
end

local function getDailyShowcaseParts(gui: SurfaceGui): (GuiObject?, GuiObject?, GuiObject?, { GuiObject })
	local wrapper = gui:FindFirstChild("Wrapper")
	if not wrapper then
		return nil, nil, nil, {}
	end

	local title = wrapper:FindFirstChild("Title")
	local list = wrapper:FindFirstChild("DailyDonatorList")
	local footer = wrapper:FindFirstChild("Footer", true)
	local rows = if list and list:IsA("GuiObject") then collectDailyRows(list) else {}

	return if title and title:IsA("GuiObject") then title else nil,
		if list and list:IsA("GuiObject") then list else nil,
		if footer and footer:IsA("GuiObject") then footer else nil,
		rows
end

local function resetDailyShowcase(gui: SurfaceGui, entries: { any }, kind: string)
	local title, list, footer, rows = getDailyShowcaseParts(gui)
	if not title or not list or #rows == 0 then
		log:warn("Daily showcase layout incomplete", {
			gui = gui.Name,
			hasTitle = title ~= nil,
			hasList = list ~= nil,
			rowCount = #rows,
		})
	end
	if title then
		title.Visible = true
		title.AnchorPoint = Vector2.new(0.5, 0.5)
		title.Position = UDim2.fromScale(0.5, 0.5)
		title.Size = UDim2.fromScale(0.82, 1)
		title.Rotation = 0
		ensureUIScale(title).Scale = 0.82
	end
	if list then
		dailyOriginalAnchorByGui[list] = dailyOriginalAnchorByGui[list] or list.AnchorPoint
		dailyOriginalPositionByGui[list] = dailyOriginalPositionByGui[list] or list.Position
		list.Visible = false
		-- Alternating layout: list fills the whole board using its original transform.
		list.AnchorPoint = dailyOriginalAnchorByGui[list]
		list.Position = dailyOriginalPositionByGui[list]
		ensureUIScale(list).Scale = 0.82
	end
	if footer then
		footer.Visible = true
		ensureUIScale(footer).Scale = 0.92
	end
	for _, row in ipairs(rows) do
		row.Visible = false
		ensureUIScale(row).Scale = 0.9
	end

	for index, entry in ipairs(entries) do
		if index > #rows then
			break
		end
		updateCard(rows[index], entry, index, kind, false)
		rows[index].LayoutOrder = index
		rows[index].Visible = false
	end
end

local function playDailyCardBatch(state: any, generation: number, rows: { GuiObject }, entries: { any }, startIndex: number, kind: string): boolean
	-- Stagger via task.delay so tweens overlap (domino) instead of running sequentially.
	local lastDelay = 0
	for localIndex, row in ipairs(rows) do
		local entryIndex = startIndex + localIndex - 1
		local entry = entries[entryIndex]
		if not entry then
			row.Visible = false
			continue
		end

		row.LayoutOrder = localIndex
		updateCard(row, entry, entryIndex, kind, false)
		row.Visible = false
		local scale = ensureUIScale(row)
		scale.Scale = 0.92
		row.Rotation = if localIndex % 2 == 0 then -0.5 else 0.5

		local myDelay = (localIndex - 1) * DAILY_CARD_STAGGER
		lastDelay = myDelay
		local capturedRow = row
		local capturedScale = scale
		task.delay(myDelay, function()
			if state.generation ~= generation or not capturedRow.Parent then
				return
			end
			capturedRow.Visible = true
			playTween(capturedScale, DAILY_CARD_POP, { Scale = 1 })
			playTween(capturedRow, DAILY_CARD_POP, { Rotation = 0 })
		end)
	end

	-- Tunggu sampe kartu terakhir selesai pop in.
	local entranceTotal = lastDelay + DAILY_CARD_POP.Time
	if not waitForShowcase(state, generation, entranceTotal) then
		return false
	end

	if not waitForShowcase(state, generation, DAILY_BATCH_HOLD) then
		return false
	end

	-- Stagger fade out juga, dari atas ke bawah (reverse domino).
	for localIndex, row in ipairs(rows) do
		if row.Visible then
			local myDelay = (localIndex - 1) * DAILY_CARD_STAGGER * 0.6
			local capturedRow = row
			local capturedScale = ensureUIScale(row)
			task.delay(myDelay, function()
				if state.generation ~= generation or not capturedRow.Parent then
					return
				end
				playTween(capturedScale, DAILY_CARD_OUT, { Scale = 0.94 })
				playTween(capturedRow, DAILY_CARD_OUT, { Rotation = capturedRow.Rotation + 0.4 })
			end)
		end
	end

	local exitTotal = (#rows - 1) * DAILY_CARD_STAGGER * 0.6 + DAILY_CARD_OUT.Time
	if not waitForShowcase(state, generation, exitTotal + 0.05) then
		return false
	end

	for _, row in ipairs(rows) do
		row.Visible = false
		row.Rotation = 0
	end
	return true
end

local function startDailyShowcaseLoop(gui: SurfaceGui, entries: { any }, kind: string)
	local fingerprintParts = {}
	for index, entry in ipairs(entries) do
		table.insert(fingerprintParts, getCardFingerprint(entry, index, kind))
	end
	local fingerprint = table.concat(fingerprintParts, "\n")

	local state = dailyShowcaseStateByGui[gui]
	if not state then
		state = {
			generation = 0,
			thread = nil,
			fingerprint = nil,
		}
		dailyShowcaseStateByGui[gui] = state
	end

	if state.fingerprint == fingerprint and state.thread ~= nil then
		return
	end
	state.fingerprint = fingerprint

	state.generation += 1
	local generation = state.generation
	if state.thread then
		task.cancel(state.thread)
		state.thread = nil
	end

	resetDailyShowcase(gui, entries, kind)

	state.thread = task.spawn(function()
		while gui.Parent and state.generation == generation do
			local title, list, footer, rows = getDailyShowcaseParts(gui)
			if not title then
				return
			end

			resetDailyShowcase(gui, entries, kind)

			-- No donors today: loop title animation only (no all-time fallback list).
			if #entries == 0 then
				if list then
					list.Visible = false
				end
				if footer then
					footer.Visible = false
				end
				for _, row in ipairs(rows) do
					row.Visible = false
				end

				title.Visible = true
				ensureUIScale(title).Scale = 0.92
				playTween(ensureUIScale(title), DAILY_TITLE_POP, { Scale = 1 })
				if not waitForShowcase(state, generation, 2.0) then
					return
				end
				playAttentionShake(title, 1.06)
				if not waitForShowcase(state, generation, DAILY_BATCH_HOLD) then
					return
				end
				playTween(ensureUIScale(title), DAILY_CARD_OUT, { Scale = 0.9 })
				if not waitForShowcase(state, generation, DAILY_CARD_OUT.Time + DAILY_SEQUENCE_RESTART_DELAY) then
					return
				end
				continue
			end

			if not list or #rows == 0 then
				return
			end

			-- Phase 1: title appears alone (full board; list hidden).
			list.Visible = false
			title.Visible = true
			ensureUIScale(title).Scale = 0.92
			playTween(ensureUIScale(title), DAILY_TITLE_POP, { Scale = 1 })

			if not waitForShowcase(state, generation, 2.0) then
				return
			end

			-- Phase 2: crossfade title out while list scales in (0.25s overlap).
			playTween(ensureUIScale(title), DAILY_CARD_OUT, { Scale = 0.9 })
			-- Pre-scale list before making it visible for the crossfade.
			ensureUIScale(list).Scale = 0.92
			local CROSSFADE_OVERLAP = 0.25
			if not waitForShowcase(state, generation, DAILY_CARD_OUT.Time - CROSSFADE_OVERLAP) then
				return
			end
			-- List enters while the title finishes fading out (overlap).
			list.Visible = true
			playTween(ensureUIScale(list), DAILY_LIST_POP, { Scale = 1 })
			if footer then
				footer.Visible = true
				ensureUIScale(footer).Scale = 0.92
				playTween(ensureUIScale(footer), DAILY_LIST_POP, { Scale = 1 })
			end
			if not waitForShowcase(state, generation, CROSSFADE_OVERLAP + 0.05) then
				return
			end
			title.Visible = false

			-- Phase 3: Play card batches.
			local startIndex = 1
			while startIndex <= #entries and state.generation == generation do
				if not playDailyCardBatch(state, generation, rows, entries, startIndex, kind) then
					return
				end
				startIndex += DAILY_CARD_LIMIT
			end

			-- Phase 4: crossfade list out while title returns.
			playTween(ensureUIScale(list), DAILY_CARD_OUT, { Scale = 0.92 })
			if footer then
				playTween(ensureUIScale(footer), DAILY_CARD_OUT, { Scale = 0.92 })
			end
			if not waitForShowcase(state, generation, DAILY_CARD_OUT.Time + DAILY_SEQUENCE_RESTART_DELAY) then
				return
			end
			list.Visible = false
		end

		if dailyShowcaseStateByGui[gui] == state then
			dailyShowcaseStateByGui[gui] = nil
		end
	end)
end

local function renderDailyDonations(payload: any): boolean
	local renderedAny = false
	for _, spec in ipairs(DAILY_SPECS) do
		local gui = resolveDailyDonationsGui(spec)
		if gui then
			local entries = payload[spec.dataKey]
			if type(entries) ~= "table" then
				entries = {}
			end

			startDailyShowcaseLoop(gui, entries, spec.kind)
			renderedAny = true
		end
	end
	return renderedAny
end

updateTimestamp = function(gui: SurfaceGui, updatedAt: number)
	local formatted = os.date("%d %b %Y, %H:%M", updatedAt)
	local text = "Latest update on " .. formatted .. "."
	for _, descendant in ipairs(gui:GetDescendants()) do
		if
			descendant:IsA("TextLabel")
			and (descendant.Name == "LastUpdateText" or descendant.Text:find("Latest update"))
		then
			local previous = lastTimestampTextByLabel[descendant]
			descendant.Text = text
			if previous == nil or previous ~= text then
				blinkFooterLabel(descendant)
			end
			lastTimestampTextByLabel[descendant] = text
		end
	end
end

local lastAnimationRevision: number? = nil

local function playWorkspaceAnimations(payload: any)
	if Config.Leaderboards.CLIENT_PLAY_ANIMATIONS ~= true then
		return
	end

	if type(payload) == "table" then
		renderDailyDonations(payload)
	end

	local revision = tonumber(workspace:GetAttribute(Config.Leaderboards.REVISION_ATTRIBUTE))
	local revisionChanged = revision == nil or revision ~= lastAnimationRevision
	if not revisionChanged then
		return
	end
	if revision then
		lastAnimationRevision = revision
	end

	for _, spec in ipairs(BOARD_SPECS) do
		local gui = resolveBoard(spec)
		if gui then
			ensurePodiumLoop(gui, spec)
		end
	end
end

local function init(_deps: {}?)
	local Remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	if not Remotes then
		log:warn("Remotes folder not found")
		return
	end

	local updateRemote = Remotes:WaitForChild(Config.Leaderboards.REMOTE_UPDATED, 15) :: RemoteEvent?
	local snapshotRemote = Remotes:WaitForChild(Config.Leaderboards.REMOTE_SNAPSHOT, 15) :: RemoteEvent?
	local snapshotResponseRemote =
		Remotes:WaitForChild(Config.Leaderboards.REMOTE_SNAPSHOT_RESPONSE, 15) :: RemoteEvent?
	if not updateRemote then
		log:warn("Workspace leaderboard update remote not found")
		return
	end

	WorkspaceLeaderboardRenderer.bootstrapLoadingUntilRevision()

	local function applyWorkspaceLeaderboards(payload: any): boolean
		local renderedAll = true

		if Config.Leaderboards.CLIENT_PAINT_DATA == true then
			local paintResult = WorkspaceLeaderboardRenderer.renderPayload(payload)
			renderedAll = paintResult.ok
		end

		playWorkspaceAnimations(payload)
		return renderedAll
	end

	local function render(payload: any)
		if type(payload) ~= "table" then
			return
		end
		latestPayload = payload

		local revision = workspace:GetAttribute(Config.Leaderboards.REVISION_ATTRIBUTE)
		if type(revision) == "number" then
			lastLeaderboardRevisionSeen = revision
		end

		local function scheduleRetryIfNeeded(renderedAll: boolean)
			if Config.Leaderboards.CLIENT_PAINT_DATA ~= true or renderedAll then
				return
			end
			task.delay(5, function()
				if latestPayload == payload then
					render(payload)
				end
			end)
		end

		scheduleRetryIfNeeded(applyWorkspaceLeaderboards(payload))
	end

	task.defer(function()
		if latestPayload ~= nil then
			return
		end
		local revision = tonumber(workspace:GetAttribute(Config.Leaderboards.REVISION_ATTRIBUTE))
		if type(revision) == "number" then
			lastLeaderboardRevisionSeen = revision
		end
		playWorkspaceAnimations({
			dailySaweria = {},
			dailyRobux = {},
			updatedAt = os.time(),
		})
	end)

	track(updateRemote.OnClientEvent:Connect(render))

	track(workspace:GetAttributeChangedSignal(Config.Leaderboards.REVISION_ATTRIBUTE):Connect(function()
		local revision = tonumber(workspace:GetAttribute(Config.Leaderboards.REVISION_ATTRIBUTE))
		if type(revision) ~= "number" or revision == lastLeaderboardRevisionSeen then
			return
		end
		lastLeaderboardRevisionSeen = revision
		local payload = latestPayload
		if type(payload) ~= "table" then
			payload = {
				dailySaweria = {},
				dailyRobux = {},
				updatedAt = os.time(),
			}
		end
		playWorkspaceAnimations(payload)
	end))

	-- Snapshot fallback removed: server does not handle the remote, making it dead code.
	-- Leaderboard data arrives via REMOTE_UPDATED broadcast from the server.
end

return { init = init, destroy = destroy }
