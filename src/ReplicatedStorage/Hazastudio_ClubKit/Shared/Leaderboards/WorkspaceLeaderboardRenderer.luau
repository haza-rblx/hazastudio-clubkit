--!strict
-- Static paint for workspace SurfaceGui leaderboards (boards + posters).
-- Safe on server (replicates) and client (optional fallback when CLIENT_PAINT_DATA).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local LeaderboardIdentity = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.LeaderboardIdentity)
local LeaderboardDisplayState = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Leaderboards.LeaderboardDisplayState)

export type BoardSpec = {
	rootPart: string,
	guiName: string,
	dataKey: string,
	limit: number,
	topCards: { string },
	templateName: string,
	kind: string,
}

export type PosterFieldPaths = {
	thumbnail: { string },
	footerThumbnail: { string }?,
	displayName: { string },
	username: { string },
	title: { string }?,
	amount: { string },
	lastUpdate: { string }?,
}

export type PosterSpec = {
	rootPart: string,
	guiName: string,
	dataKey: string,
	kind: string,
	rank: number,
	fields: PosterFieldPaths,
}

export type RenderResult = {
	ok: boolean,
	missingBoards: { string },
}

local BOARD_SPECS: { BoardSpec } = {
	{
		rootPart = "RobuxDonationBoard",
		guiName = "RobuxDonationBoardGUI",
		dataKey = "robux",
		limit = Config.Leaderboards.ROBUX_PAINT_LIMIT,
		topCards = { "1stPlaceWrapper", "2rdPlaceWrapper", "3rdPlaceWrapper" },
		templateName = "BasicCardTemplate",
		kind = "playerRobux",
	},
	{
		rootPart = "CommunityDonationBoard",
		guiName = "CommunityDonationBoardGUI",
		dataKey = "community",
		limit = Config.Leaderboards.COMMUNITY_LIMIT,
		topCards = { "1stPlaceCommunityWrapper", "2ndPlaceCommunityWrapper", "3rdPlaceCommunityWrapper" },
		templateName = "BasicCardTemplate",
		kind = "community",
	},
	{
		rootPart = "SaweriaDonationBoard",
		guiName = "SaweriaDonationBoardGUI",
		dataKey = "saweria",
		limit = Config.Leaderboards.SAWERIA_LIMIT,
		topCards = { "1stPlaceCard", "2ndPlaceCard", "3rdPlaceCard" },
		templateName = "BasicCardTemplate",
		kind = "saweria",
	},
	{
		rootPart = "LikesLeaderboard",
		guiName = "LikesLeaderboardGUI",
		dataKey = "likes",
		limit = Config.Leaderboards.LIKES_PAINT_LIMIT,
		topCards = { "1stPlaceWrapper", "2rdPlaceWrapper", "3rdPlaceWrapper" },
		templateName = "BasicCardTemplate",
		kind = "likes",
	},
}

local POSTER_GUI_NAME = "SurfaceGui"

-- Workspace.Folder.Top{1,2,3}{Cash,Robux} v2 layout (CanvasGroup > Wrapper > InformationsOverlay).
local POSTER_FIELDS_V2: PosterFieldPaths = {
	thumbnail = { "CanvasGroup", "Wrapper", "PlayerProfileThumbnail" },
	footerThumbnail = {
		"CanvasGroup",
		"Wrapper",
		"InformationsOverlay",
		"Footer",
		"PlayerProfileThumbnail",
	},
	displayName = {
		"CanvasGroup",
		"Wrapper",
		"InformationsOverlay",
		"Footer",
		"PlayerInformationsWrapper",
		"PlayerDisplayName",
	},
	username = {
		"CanvasGroup",
		"Wrapper",
		"InformationsOverlay",
		"Footer",
		"PlayerInformationsWrapper",
		"PlayerUsername",
	},
	title = { "CanvasGroup", "Wrapper", "InformationsOverlay", "Header", "Title" },
	amount = {
		"CanvasGroup",
		"Wrapper",
		"InformationsOverlay",
		"Footer",
		"TotalDonationsWrapper",
		"TotalDonations",
	},
	lastUpdate = { "CanvasGroup", "Wrapper", "InformationsOverlay", "Footer", "LastUpdateTextLabel" },
}

local POSTER_SPECS: { PosterSpec } = {
	{
		rootPart = "Top1Robux",
		guiName = POSTER_GUI_NAME,
		dataKey = "robux",
		kind = "playerRobuxPoster",
		rank = 1,
		fields = POSTER_FIELDS_V2,
	},
	{
		rootPart = "Top2Robux",
		guiName = POSTER_GUI_NAME,
		dataKey = "robux",
		kind = "playerRobuxPoster",
		rank = 2,
		fields = POSTER_FIELDS_V2,
	},
	{
		rootPart = "Top3Robux",
		guiName = POSTER_GUI_NAME,
		dataKey = "robux",
		kind = "playerRobuxPoster",
		rank = 3,
		fields = POSTER_FIELDS_V2,
	},
	{
		rootPart = "Top1Cash",
		guiName = POSTER_GUI_NAME,
		dataKey = "saweria",
		kind = "saweriaPoster",
		rank = 1,
		fields = POSTER_FIELDS_V2,
	},
	{
		rootPart = "Top2Cash",
		guiName = POSTER_GUI_NAME,
		dataKey = "saweria",
		kind = "saweriaPoster",
		rank = 2,
		fields = POSTER_FIELDS_V2,
	},
	{
		rootPart = "Top3Cash",
		guiName = POSTER_GUI_NAME,
		dataKey = "saweria",
		kind = "saweriaPoster",
		rank = 3,
		fields = POSTER_FIELDS_V2,
	},
}

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

local GENERIC_GUI_NAMES: { [string]: boolean } = {
	SurfaceGui = true,
	ScreenGui = true,
	BillboardGui = true,
	[""] = true,
}

local resolverWarnedByKey: { [string]: boolean } = {}
local warnFn: ((key: string, message: string, payload: any?) -> ())? = nil
local loadingTextGenerationByLabel: { [TextLabel]: number } = setmetatable({}, { __mode = "k" })
local originalTextTransparencyByLabel: { [TextLabel]: number } = setmetatable({}, { __mode = "k" })
local originalTextStrokeTransparencyByLabel: { [TextLabel]: number } = setmetatable({}, { __mode = "k" })

local function warnOnce(key: string, message: string, payload: any?)
	if resolverWarnedByKey[key] then
		return
	end
	resolverWarnedByKey[key] = true
	if warnFn then
		warnFn(key, message, payload)
	end
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

local function isGenericGuiName(name: string): boolean
	return GENERIC_GUI_NAMES[name] == true
end

local function findSurfaceGuiByNameGlobal(name: string): SurfaceGui?
	local direct = workspace:FindFirstChild(name, true)
	if direct and direct:IsA("SurfaceGui") then
		return direct
	end
	return nil
end

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

local function findWorkspaceRoot(name: string): Instance?
	local hit = workspace:FindFirstChild(name, true)
	if not hit then
		return nil
	end
	if hit:IsA("Model") then
		return hit
	end
	local ancestor = hit:FindFirstAncestorOfClass("Model")
	if ancestor then
		return ancestor
	end
	return hit
end

local function resolveBoard(spec: BoardSpec): SurfaceGui?
	if not isGenericGuiName(spec.guiName) then
		local globalHit = findSurfaceGuiByNameGlobal(spec.guiName)
		if globalHit then
			return globalHit
		end
	end

	local part = findWorkspaceRoot(spec.rootPart)
	if part then
		local scoped, autoDiscovered = findSurfaceGuiInPart(part, spec.guiName)
		if scoped then
			if autoDiscovered then
				warnOnce("board:" .. spec.dataKey, "Board SurfaceGui auto-discovered (name mismatch)", {
					expected = spec.guiName,
					found = scoped.Name,
					part = spec.rootPart,
				})
			end
			return scoped
		end
	end

	return nil
end

local function resolvePosterGui(spec: PosterSpec): SurfaceGui?
	if not isGenericGuiName(spec.guiName) then
		local globalHit = findSurfaceGuiByNameGlobal(spec.guiName)
		if globalHit then
			return globalHit
		end
	end

	local part = findWorkspaceRoot(spec.rootPart)
	if part then
		local scoped, autoDiscovered = findSurfaceGuiInPart(part, spec.guiName)
		if scoped then
			if autoDiscovered then
				warnOnce(
					"poster:" .. spec.dataKey .. ":" .. tostring(spec.rank),
					"Poster SurfaceGui auto-discovered (name mismatch)",
					{
						expected = spec.guiName,
						found = scoped.Name,
						part = spec.rootPart,
					}
				)
			end
			return scoped
		end
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

local function setFirstImage(root: Instance, names: { string }, image: string)
	local imageLabel = findDescendant(root, names, "ImageLabel")
	if imageLabel and imageLabel:IsA("ImageLabel") then
		imageLabel.Image = image
		imageLabel.Visible = image ~= ""
	end
end

local function setTextAtPath(root: Instance, path: { string }, text: string)
	local label = findPath(root, path, "TextLabel")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function setImageAtPath(root: Instance, path: { string }, image: string)
	local imageLabel = findPath(root, path, "ImageLabel")
	if imageLabel and imageLabel:IsA("ImageLabel") then
		imageLabel.Image = image
		imageLabel.Visible = image ~= ""
	end
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

local function setValueStatic(root: Instance, kind: string, value: number)
	local label = findValueLabel(root, kind)
	if label then
		local normalizedValue = math.floor(math.max(value, 0))
		label.Text = formatDonationValue(kind, normalizedValue)
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

local function getPosterEntryImage(entry: any, kind: string): string
	if kind == "community" then
		return tostring(entry.communityLogo or "")
	end
	local userId = tonumber(entry and entry.userId)
	if userId and userId > 0 then
		return LeaderboardIdentity.getUserThumbnail(userId, 420)
	end
	return tostring(entry.thumbnail or "")
end

local function updateTimestamp(gui: SurfaceGui, updatedAt: number)
	local formatted = os.date("%d %b %Y, %H:%M", updatedAt)
	local text = "Latest update on " .. formatted .. "."
	for _, descendant in ipairs(gui:GetDescendants()) do
		if
			descendant:IsA("TextLabel")
			and (descendant.Name == "LastUpdateText" or descendant.Text:find("Latest update"))
		then
			descendant.Text = text
		end
	end
end

local function getPosterTitleText(spec: PosterSpec): string
	local currencyLabel = if spec.kind == "saweriaPoster" then "CASH" else "ROBUX"
	return ("TOP #%d %s\nDONATION"):format(spec.rank, currencyLabel)
end

local function getPosterFooterImage(entry: any, kind: string): string
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

local function getPosterFallbackName(spec: PosterSpec): string
	return if spec.rank == 1 then "COMING SOON" else "NEXT STAR"
end

local function getPosterFallbackSubtext(spec: PosterSpec): string
	return if spec.kind == "saweriaPoster" then "Waiting for linked donor" else "Waiting for donor"
end

local function getPosterFallbackValue(spec: PosterSpec): string
	return if spec.kind == "saweriaPoster" then "RP.0" else "0"
end

local function hasLeaderboardEntries(entries: any): boolean
	if type(entries) ~= "table" then
		return false
	end
	for _, entry in ipairs(entries) do
		if entry ~= nil then
			return true
		end
	end
	for _, entry in pairs(entries) do
		if entry ~= nil then
			return true
		end
	end
	return false
end

local function countTopEntries(entries: any, maxRank: number): number
	if type(entries) ~= "table" then
		return 0
	end
	local count = 0
	for rank = 1, maxRank do
		if entries[rank] then
			count += 1
		end
	end
	return count
end

local function isSaweriaBoardSpec(spec: BoardSpec): boolean
	return spec.dataKey == "saweria" or spec.kind == "saweria"
end

local function isSaweriaPosterSpec(spec: PosterSpec): boolean
	return spec.dataKey == "saweria" or spec.kind == "saweriaPoster"
end

local function hasSaweriaLeaderboardData(entries: any): boolean
	return hasLeaderboardEntries(entries)
end

local function normalizeLoadingText(message: string): string
	return (message:gsub("%.+$", ""):gsub("%s+$", ""))
end

local function resolveMessageCycle(primary: string?, cycles: { string }?): { string }
	local result: { string } = {}
	local seen: { [string]: boolean } = {}

	local function add(message: string?)
		if type(message) ~= "string" then
			return
		end
		local cleaned = normalizeLoadingText(message)
		if cleaned == "" or seen[cleaned] then
			return
		end
		seen[cleaned] = true
		table.insert(result, cleaned)
	end

	add(primary)
	if type(cycles) == "table" then
		for _, message in ipairs(cycles) do
			add(message)
		end
	end

	if #result == 0 then
		add(Config.Leaderboards.DEFAULT_LOADING_MESSAGE or "Loading leaderboard")
	end

	return result
end

local function getBoardLoadingCycle(spec: BoardSpec, entries: any?): { string }
	if type(entries) == "table" and not hasLeaderboardEntries(entries) then
		if isSaweriaBoardSpec(spec) then
			local waitingMessages = Config.Leaderboards.SAWERIA_WAITING_MESSAGES
			local waitingCycles = Config.Leaderboards.SAWERIA_WAITING_CYCLES
			local primary = if type(waitingMessages) == "table" then waitingMessages.board else nil
			local cycles = if type(waitingCycles) == "table" then waitingCycles.board else nil
			return resolveMessageCycle(primary, cycles)
		end
	end

	local messages = Config.Leaderboards.LOADING_MESSAGES
	local cycles = Config.Leaderboards.LOADING_MESSAGE_CYCLES
	local primary = if type(messages) == "table" then messages[spec.dataKey] else nil
	local cycle = if type(cycles) == "table" then cycles[spec.dataKey] else nil
	return resolveMessageCycle(primary, cycle)
end

local function getPosterLoadingCycle(spec: PosterSpec, allTopEmpty: boolean?): { string }
	if allTopEmpty == true then
		if isSaweriaPosterSpec(spec) then
			local waitingMessages = Config.Leaderboards.SAWERIA_WAITING_MESSAGES
			local waitingCycles = Config.Leaderboards.SAWERIA_WAITING_CYCLES
			local primary = if type(waitingMessages) == "table" then waitingMessages.poster else nil
			local cycles = if type(waitingCycles) == "table" then waitingCycles.poster else nil
			return resolveMessageCycle(primary, cycles)
		end
	end

	local messages = Config.Leaderboards.POSTER_LOADING_MESSAGES
	local cycles = Config.Leaderboards.POSTER_LOADING_CYCLES
	local primary = if type(messages) == "table" then messages[spec.dataKey] else nil
	if not primary or primary == "" then
		primary = Config.Leaderboards.DEFAULT_POSTER_LOADING_MESSAGE
	end
	local cycle = if type(cycles) == "table" then cycles[spec.dataKey] else nil
	return resolveMessageCycle(primary, cycle)
end

local function ensureLabelFadeBaseline(label: TextLabel)
	if originalTextTransparencyByLabel[label] == nil then
		originalTextTransparencyByLabel[label] = label.TextTransparency
	end
	if originalTextStrokeTransparencyByLabel[label] == nil then
		originalTextStrokeTransparencyByLabel[label] = label.TextStrokeTransparency
	end
end

local function restoreLabelFade(label: TextLabel)
	ensureLabelFadeBaseline(label)
	label.TextTransparency = originalTextTransparencyByLabel[label]
	label.TextStrokeTransparency = originalTextStrokeTransparencyByLabel[label]
end

local function stopLoadingTextAnimation(label: TextLabel)
	loadingTextGenerationByLabel[label] = (loadingTextGenerationByLabel[label] or 0) + 1
	restoreLabelFade(label)
end

local function tweenLabelFade(label: TextLabel, fadeIn: boolean, duration: number): boolean
	ensureLabelFadeBaseline(label)
	local goals = if fadeIn
		then {
			TextTransparency = originalTextTransparencyByLabel[label],
			TextStrokeTransparency = originalTextStrokeTransparencyByLabel[label],
		}
		else {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	local tween = TweenService:Create(
		label,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		goals
	)
	tween:Play()
	tween.Completed:Wait()
	return label.Parent ~= nil
end

local function startLoadingTextAnimation(label: TextLabel, messages: { string })
	stopLoadingTextAnimation(label)
	local generation = (loadingTextGenerationByLabel[label] or 0) + 1
	loadingTextGenerationByLabel[label] = generation

	local cycle: { string } = {}
	for _, message in ipairs(messages) do
		local cleaned = normalizeLoadingText(message)
		if cleaned ~= "" then
			table.insert(cycle, cleaned)
		end
	end
	if #cycle == 0 then
		table.insert(cycle, "Loading")
	end

	local fadeDuration = tonumber(Config.Leaderboards.LOADING_TEXT_FADE_DURATION) or 0.38
	local holdDuration = tonumber(Config.Leaderboards.LOADING_TEXT_HOLD_DURATION) or 2.4

	task.spawn(function()
		local index = 1
		local isFirstMessage = true

		while label.Parent and loadingTextGenerationByLabel[label] == generation do
			local nextText = cycle[index]

			if not isFirstMessage then
				if not tweenLabelFade(label, false, fadeDuration) then
					break
				end
				if loadingTextGenerationByLabel[label] ~= generation then
					break
				end
			end

			label.Text = nextText
			label.TextTransparency = 1
			label.TextStrokeTransparency = 1
			if not tweenLabelFade(label, true, fadeDuration) then
				break
			end
			if loadingTextGenerationByLabel[label] ~= generation then
				break
			end

			isFirstMessage = false
			task.wait(holdDuration)
			index = (index % #cycle) + 1
		end
	end)
end

local function toMessageCycle(message: string | { string }?): { string }
	if type(message) == "table" then
		return message
	end
	if type(message) == "string" then
		return resolveMessageCycle(message, nil)
	end
	return { "Loading" }
end

local function findBoardChromeChild(gui: Instance, childName: string): GuiObject?
	local direct = gui:FindFirstChild(childName)
	if direct and direct:IsA("GuiObject") then
		return direct
	end
	local descendant = gui:FindFirstChild(childName, true)
	if descendant and descendant:IsA("GuiObject") then
		return descendant
	end
	return nil
end

local function findOverlayLabel(overlay: Instance): TextLabel?
	local named = overlay:FindFirstChild("TextLabel", true)
	if named and named:IsA("TextLabel") then
		return named
	end
	for _, descendant in ipairs(overlay:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			return descendant
		end
	end
	return nil
end

local function findPosterContentWrapper(gui: SurfaceGui): GuiObject?
	local path = Config.Leaderboards.POSTER_CONTENT_WRAPPER_PATH
	if type(path) == "table" then
		local wrapper = findPath(gui, path, nil)
		if wrapper and wrapper:IsA("GuiObject") then
			return wrapper
		end
	end
	return findBoardChromeChild(gui, "Wrapper")
end

local function findPosterContentRoot(gui: SurfaceGui): GuiObject?
	local path = Config.Leaderboards.POSTER_CONTENT_ROOT_PATH
	if type(path) == "table" then
		local root = findPath(gui, path, nil)
		if root and root:IsA("GuiObject") then
			return root
		end
	end
	return findPosterContentWrapper(gui)
end

local function setPosterContentVisible(gui: SurfaceGui, visible: boolean)
	local wrapper = findPosterContentWrapper(gui)
	if wrapper then
		wrapper.Visible = visible
	end
end

local function revealPosterContent(gui: SurfaceGui)
	local root = findPosterContentRoot(gui)
	local wrapper = findPosterContentWrapper(gui)

	if root then
		root.Visible = true
		if root:IsA("CanvasGroup") then
			root.GroupTransparency = 0
		end
	end
	if wrapper then
		wrapper.Visible = true
	end
end

local function setBoardContentVisible(gui: SurfaceGui, visible: boolean)
	local contentName = Config.Leaderboards.MAIN_CONTENT_WRAPPER_NAME or "MainContentWrapper"
	local mainContent = findBoardChromeChild(gui, contentName)
	if mainContent then
		mainContent.Visible = visible
	end
end

local function setLoadingChrome(gui: SurfaceGui, isLoading: boolean, message: string | { string }?, contentWrapper: GuiObject?)
	local overlayName = Config.Leaderboards.LOADING_OVERLAY_NAME or "LoadingOverlay"
	local overlay = findBoardChromeChild(gui, overlayName)

	if overlay then
		local label = findOverlayLabel(overlay)
		if isLoading then
			overlay.Visible = true
			if label and message then
				startLoadingTextAnimation(label, toMessageCycle(message))
			end
		else
			overlay.Visible = false
			if label then
				stopLoadingTextAnimation(label)
			end
		end
	end

	if contentWrapper then
		contentWrapper.Visible = not isLoading
	end
end

local function setBoardChrome(gui: SurfaceGui, isLoading: boolean, message: string | { string }?)
	local contentName = Config.Leaderboards.MAIN_CONTENT_WRAPPER_NAME or "MainContentWrapper"
	local mainContent = findBoardChromeChild(gui, contentName)
	setLoadingChrome(gui, isLoading, message, mainContent)
end

local function setPosterChrome(gui: SurfaceGui, isLoading: boolean, message: string | { string }?)
	local wrapper = findPosterContentWrapper(gui)
	setLoadingChrome(gui, isLoading, message, wrapper)
	if not isLoading then
		revealPosterContent(gui)
	elseif wrapper then
		wrapper.Visible = false
	end
end

local function updatePoster(spec: PosterSpec, payload: any): boolean
	local gui = resolvePosterGui(spec)
	if not gui then
		return false
	end

	local entries = payload[spec.dataKey]
	if type(entries) ~= "table" then
		setPosterChrome(gui, true, getPosterLoadingCycle(spec))
		return true
	end

	local entry = entries[spec.rank]
	if not entry then
		local state = LeaderboardDisplayState.getBoardState(payload, spec.dataKey, entries)
		setPosterChrome(gui, true, LeaderboardDisplayState.getPosterMessageCycle(spec.dataKey, state))
		setPosterContentVisible(gui, false)
		local root = findPosterContentRoot(gui)
		if root then
			root.Visible = true
		end
		return true
	end

	setPosterContentVisible(gui, false)

	local displayName = getEntryDisplayName(entry, spec.kind)
	local username = getEntryUsernameText(entry, spec.kind)
	local amountText = formatDonationValue(spec.kind, tonumber(entry.total) or 0)

	setTextAtPath(gui, spec.fields.displayName, displayName)
	setTextAtPath(gui, spec.fields.username, username)
	setTextAtPath(gui, spec.fields.amount, amountText)

	if spec.fields.title then
		setTextAtPath(gui, spec.fields.title, getPosterTitleText(spec))
	end

	local portraitImage = getPosterEntryImage(entry, spec.kind)
	setImageAtPath(gui, spec.fields.thumbnail, portraitImage)
	if spec.fields.footerThumbnail then
		local footerImage = getPosterFooterImage(entry, spec.kind)
		if footerImage == "" then
			footerImage = portraitImage
		end
		setImageAtPath(gui, spec.fields.footerThumbnail, footerImage)
	end

	local updatedAt = tonumber(payload.updatedAt) or os.time()
	local formatted = os.date("%d %b %Y, %H:%M", updatedAt)
	local lastUpdateText = "Latest update on " .. formatted .. "."
	if spec.fields.lastUpdate then
		setTextAtPath(gui, spec.fields.lastUpdate, lastUpdateText)
	else
		updateTimestamp(gui, updatedAt)
	end

	setPosterChrome(gui, false)
	return true
end

local function updateCard(card: GuiObject, entry: any?, rank: number, kind: string, shouldSetLayoutOrder: boolean?)
	if not entry then
		card.Visible = false
		return
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
	setFirstImage(card, THUMBNAIL_IMAGE_NAMES, portraitImage)

	if rank >= 4 then
		local imageLabel = findPath(card, { "Wrapper", "PlayerThumbnailImage" }, "ImageLabel")
			or findPath(card, { "Wrapper", "PlayerThumbnail" }, "ImageLabel")
			or findPath(card, { "Wrapper", "PlayerThumbnailPic" }, "ImageLabel")
			or findPath(card, { "Wrapper", "ProfilePicture" }, "ImageLabel")
		if imageLabel and imageLabel:IsA("ImageLabel") then
			imageLabel.Image = portraitImage
			imageLabel.Visible = portraitImage ~= ""
		end
	end

	setValueStatic(card, kind, tonumber(entry.total) or 0)
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

local function renderBoardIdle(gui: SurfaceGui, spec: BoardSpec, payload: any)
	setBoardContentVisible(gui, false)
	for rank = 1, 3 do
		local card = gui:FindFirstChild(spec.topCards[rank], true)
		if card and card:IsA("GuiObject") then
			updateCard(card, nil, rank, spec.kind, false)
		end
	end

	local template = gui:FindFirstChild(spec.templateName, true)
	if template and template:IsA("GuiObject") then
		template.Visible = false
		local listParent = template.Parent
		if listParent then
			for _, child in ipairs(listParent:GetChildren()) do
				if child:IsA("GuiObject") and child.Name:match("^GeneratedLeaderboardRow%d+$") then
					child.Visible = false
				end
			end
		end
	end

	local entries = payload[spec.dataKey]
	local state = LeaderboardDisplayState.getBoardState(payload, spec.dataKey, entries)
	local messages = LeaderboardDisplayState.getBoardMessageCycle(spec.dataKey, state)
	setBoardChrome(gui, true, messages)
end

local function renderBoard(spec: BoardSpec, payload: any): boolean
	local gui = resolveBoard(spec)
	if not gui then
		return false
	end

	local entries = payload[spec.dataKey]
	if type(entries) ~= "table" then
		setBoardChrome(gui, true, getBoardLoadingCycle(spec, entries))
		return true
	end

	if not hasLeaderboardEntries(entries) then
		renderBoardIdle(gui, spec, payload)
		return true
	end

	setBoardContentVisible(gui, false)

	for rank = 1, 3 do
		local card = gui:FindFirstChild(spec.topCards[rank], true)
		if card and card:IsA("GuiObject") then
			updateCard(card, entries[rank], rank, spec.kind, false)
		end
	end

	local template = gui:FindFirstChild(spec.templateName, true)
	if template and template:IsA("GuiObject") then
		for rank = 4, spec.limit do
			updateCard(getRow(template, rank), entries[rank], rank, spec.kind, true)
		end
		local listParent = template.Parent
		if listParent then
			for _, child in ipairs(listParent:GetChildren()) do
				if child:IsA("GuiObject") and child.Name:match("^GeneratedLeaderboardRow%d+$") then
					local rowRank = tonumber(child.Name:match("%d+$"))
					if rowRank and rowRank > spec.limit then
						child.Visible = false
					end
				end
			end
		end
	end

	updateTimestamp(gui, tonumber(payload.updatedAt) or os.time())
	setBoardChrome(gui, false)
	return true
end

local WorkspaceLeaderboardRenderer = {}

WorkspaceLeaderboardRenderer.BOARD_SPECS = BOARD_SPECS
WorkspaceLeaderboardRenderer.POSTER_SPECS = POSTER_SPECS

function WorkspaceLeaderboardRenderer.getBoardSpecs(): { BoardSpec }
	return BOARD_SPECS
end

function WorkspaceLeaderboardRenderer.getPosterSpecs(): { PosterSpec }
	return POSTER_SPECS
end

function WorkspaceLeaderboardRenderer.resolveBoard(spec: BoardSpec): SurfaceGui?
	return resolveBoard(spec)
end

function WorkspaceLeaderboardRenderer.resolvePosterGui(spec: PosterSpec): SurfaceGui?
	return resolvePosterGui(spec)
end

function WorkspaceLeaderboardRenderer.setWarnHandler(handler: (key: string, message: string, payload: any?) -> ())
	warnFn = handler
end

function WorkspaceLeaderboardRenderer.setBoardLoading(spec: BoardSpec, message: string | { string }?)
	local gui = resolveBoard(spec)
	if gui then
		setBoardChrome(gui, true, message or getBoardLoadingCycle(spec))
	end
end

function WorkspaceLeaderboardRenderer.setAllBoardsLoading()
	for _, spec in ipairs(BOARD_SPECS) do
		WorkspaceLeaderboardRenderer.setBoardLoading(spec)
	end
	for _, spec in ipairs(POSTER_SPECS) do
		WorkspaceLeaderboardRenderer.setPosterLoading(spec)
	end
end

function WorkspaceLeaderboardRenderer.setPosterLoading(spec: PosterSpec, message: string | { string }?)
	local gui = resolvePosterGui(spec)
	if gui then
		setPosterChrome(gui, true, message or getPosterLoadingCycle(spec))
	end
end

function WorkspaceLeaderboardRenderer.setAllBoardsReady()
	for _, spec in ipairs(BOARD_SPECS) do
		local gui = resolveBoard(spec)
		if gui then
			setBoardChrome(gui, false)
		end
	end
	for _, spec in ipairs(POSTER_SPECS) do
		local gui = resolvePosterGui(spec)
		if gui then
			setPosterChrome(gui, false)
		end
	end
end

function WorkspaceLeaderboardRenderer.bootstrapLoadingUntilRevision()
	if tonumber(workspace:GetAttribute(Config.Leaderboards.REVISION_ATTRIBUTE)) ~= nil then
		return
	end

	WorkspaceLeaderboardRenderer.setAllBoardsLoading()

	task.spawn(function()
		while tonumber(workspace:GetAttribute(Config.Leaderboards.REVISION_ATTRIBUTE)) == nil do
			WorkspaceLeaderboardRenderer.setAllBoardsLoading()
			task.wait(2)
		end
	end)
end

function WorkspaceLeaderboardRenderer.renderPayload(payload: any): RenderResult
	local missingBoards: { string } = {}
	if type(payload) ~= "table" then
		WorkspaceLeaderboardRenderer.setAllBoardsLoading()
		return { ok = false, missingBoards = missingBoards }
	end

	local renderedAll = true
	for _, spec in ipairs(BOARD_SPECS) do
		local ok = renderBoard(spec, payload)
		if not ok then
			table.insert(missingBoards, spec.dataKey)
		end
		renderedAll = ok and renderedAll
	end

	for _, spec in ipairs(POSTER_SPECS) do
		local ok = updatePoster(spec, payload)
		if not ok then
			table.insert(missingBoards, "poster:" .. spec.dataKey .. ":" .. tostring(spec.rank))
		end
		renderedAll = ok and renderedAll
	end

	return {
		ok = renderedAll,
		missingBoards = missingBoards,
	}
end

return WorkspaceLeaderboardRenderer
