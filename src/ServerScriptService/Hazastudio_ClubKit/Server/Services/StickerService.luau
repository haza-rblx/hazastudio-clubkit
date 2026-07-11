--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local Result = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Result)

local log = Logger.new("Server.StickerService")

local StickerService = {}
StickerService.__index = StickerService

local function normalizeImage(value: any): string
	if type(value) ~= "string" then
		return ""
	end

	local trimmed = value:match("^%s*(.-)%s*$") or ""
	local numericId = trimmed:match("^%d+$")
	if numericId and numericId ~= "0" then
		return "rbxassetid://" .. numericId
	end

	local assetId = trimmed:match("^rbxassetid://(%d+)$")
	if assetId and assetId ~= "0" then
		return "rbxassetid://" .. assetId
	end

	if trimmed == "" or trimmed == "rbxassetid://0" then
		return ""
	end

	return ""
end

local function findAdornee(character: Model): BasePart?
	for _, partName in ipairs(Config.Sticker.DEFAULT_ADORNEE_PRIORITY) do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			return part
		end
	end

	local fallback = character:FindFirstChildWhichIsA("BasePart")
	if fallback and fallback:IsA("BasePart") then
		return fallback
	end

	return nil
end

local function createStickerGui(): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = Config.Sticker.BILLBOARD_GUI_NAME
	gui.AlwaysOnTop = true
	gui.Enabled = false
	gui.LightInfluence = Config.Sticker.BILLBOARD_LIGHT_INFLUENCE
	gui.MaxDistance = Config.Sticker.BILLBOARD_MAX_DISTANCE
	gui.Size = Config.Sticker.BILLBOARD_SIZE
	gui.StudsOffset = Config.Sticker.BILLBOARD_STUDS_OFFSET
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local image = Instance.new("ImageLabel")
	image.Name = Config.Sticker.BILLBOARD_IMAGE_NAME
	image.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	-- Hidden until a sticker image is applied (prevents empty white replication flashes).
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Size = UDim2.fromScale(1, 1)
	image.ImageTransparency = Config.Sticker.IMAGE_TRANSPARENCY
	image.ScaleType = Enum.ScaleType.Stretch
	image.Parent = gui

	local aspectRatio = Instance.new("UIAspectRatioConstraint")
	aspectRatio.AspectRatio = 1
	aspectRatio.AspectType = Enum.AspectType.FitWithinMaxSize
	aspectRatio.DominantAxis = Enum.DominantAxis.Width
	aspectRatio.Parent = image

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.1, 0)
	corner.Parent = image

	return gui
end

local function containsImage(list: { string }, image: string): boolean
	for _, existing in ipairs(list) do
		if existing == image then
			return true
		end
	end
	return false
end

function StickerService.new(deps: {
	logger: any?,
	repository: any,
	profileLoader: any?,
}): any
	local self = setmetatable({}, StickerService)
	self._log = deps.logger or log
	self._repository = deps.repository
	self._profileLoader = deps.profileLoader
	self._connections = {} :: { RBXScriptConnection }
	self._currentImages = {} :: { [number]: string }
	self._activeGuis = {} :: { [number]: BillboardGui }
	self._displayTokens = {} :: { [number]: number }
	self._globalStickers = {} :: { string }
	self._personalByUserId = {} :: { [number]: { stickers: { string }, selectedSticker: string } }
	return self
end

function StickerService:_getPersonalData(userId: number): { stickers: { string }, selectedSticker: string }
	local cached = self._personalByUserId[userId]
	if cached then
		return cached
	end

	local empty = { stickers = {} :: { string }, selectedSticker = "" }
	local result = self._repository.load(userId)
	if result.ok and type(result.value) == "table" then
		empty = {
			stickers = if type(result.value.stickers) == "table" then result.value.stickers else {},
			selectedSticker = if type(result.value.selectedSticker) == "string"
				then result.value.selectedSticker
				else "",
		}
	end

	self._personalByUserId[userId] = empty
	return empty
end

function StickerService:_isAllowedStickerImage(userId: number, image: string): boolean
	if image == "" then
		return false
	end
	local personal = self:_getPersonalData(userId)
	return containsImage(self:_mergeVisibleStickers(personal.stickers), image)
end

function StickerService:_refreshGlobalPool()
	if type(self._repository.loadGlobalPool) ~= "function" then
		return
	end
	local result = self._repository.loadGlobalPool()
	if result.ok and type(result.value) == "table" and type(result.value.stickers) == "table" then
		self._globalStickers = result.value.stickers
	end
end

function StickerService:_mergeVisibleStickers(personalStickers: { string }): { string }
	local merged = {}
	local seen: { [string]: boolean } = {}

	local function append(images: { string })
		for _, image in ipairs(images) do
			if image ~= "" and not seen[image] then
				seen[image] = true
				table.insert(merged, image)
			end
		end
	end

	append(self._globalStickers)
	append(personalStickers)

	for _, image in ipairs(Config.Sticker.DEFAULT_COLLECTION) do
		local normalized = normalizeImage(image)
		if normalized ~= "" and not seen[normalized] then
			seen[normalized] = true
			table.insert(merged, normalized)
		end
	end

	if #merged > Config.Sticker.MAX_COLLECTION_SIZE then
		local trimmed = {}
		for i = 1, Config.Sticker.MAX_COLLECTION_SIZE do
			trimmed[i] = merged[i]
		end
		return trimmed
	end

	return merged
end

function StickerService:_track(connection: RBXScriptConnection)
	table.insert(self._connections, connection)
end

function StickerService:_clearConnections()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
end

function StickerService:_getCharacter(player: Player): Model?
	local character = player.Character
	if character and character.Parent then
		return character
	end
	return nil
end

function StickerService:_ensureGui(player: Player, character: Model): BillboardGui?
	local adornee = findAdornee(character)
	if not adornee then
		return nil
	end

	local existing = character:FindFirstChild(Config.Sticker.BILLBOARD_GUI_NAME, true)
	if existing and existing:IsA("BillboardGui") then
		local gui = existing :: BillboardGui
		gui.Adornee = adornee
		gui.Size = Config.Sticker.BILLBOARD_SIZE
		gui.StudsOffset = Config.Sticker.BILLBOARD_STUDS_OFFSET
		gui.MaxDistance = Config.Sticker.BILLBOARD_MAX_DISTANCE
		gui.LightInfluence = Config.Sticker.BILLBOARD_LIGHT_INFLUENCE
		return gui
	end

	local gui = createStickerGui()
	gui.Adornee = adornee
	gui.Parent = adornee
	self._activeGuis[player.UserId] = gui
	return gui
end

local function applyStickerVisual(gui: BillboardGui, image: string)
	local stickerImage = gui:FindFirstChild(Config.Sticker.BILLBOARD_IMAGE_NAME)
	if stickerImage and stickerImage:IsA("ImageLabel") then
		local label = stickerImage :: ImageLabel
		label.Image = image
		if image == "" then
			-- Prevent replicated empty Image + opaque white background from sticking for other clients.
			label.ImageTransparency = 1
			label.BackgroundTransparency = 1
		else
			label.ImageTransparency = Config.Sticker.IMAGE_TRANSPARENCY
			label.BackgroundTransparency = 0
		end
	end

	-- Authoritative visibility: always disable when cleared so observers never keep a white box.
	gui.Enabled = image ~= ""
end

function StickerService:_applySticker(player: Player, image: string)
	local character = self:_getCharacter(player)
	if not character then
		return
	end

	local gui = self:_ensureGui(player, character)
	if not gui then
		self._log:warn("Sticker billboard adornment not found", {
			player = player.Name,
		})
		return
	end

	applyStickerVisual(gui, image)
end

function StickerService:_bumpStickerClearSignal(player: Player)
	local previous = player:GetAttribute(Config.Sticker.STICKER_CLEAR_ATTRIBUTE)
	local nextToken = if type(previous) == "number" then previous + 1 else 1
	player:SetAttribute(Config.Sticker.STICKER_CLEAR_ATTRIBUTE, nextToken)
end

function StickerService:_scheduleAutoClear(player: Player, image: string)
	local userId = player.UserId
	local token = (self._displayTokens[userId] or 0) + 1
	self._displayTokens[userId] = token

	task.delay(Config.Sticker.DISPLAY_DURATION_SECONDS, function()
		if self._displayTokens[userId] ~= token then
			return
		end
		if self._currentImages[userId] ~= image then
			return
		end

		self:clearSticker(player)
	end)
end

function StickerService:buildSyncPayload(player: Player): any
	local personal = self:_getPersonalData(player.UserId)
	return {
		stickers = self:_mergeVisibleStickers(personal.stickers),
		selectedSticker = personal.selectedSticker,
	}
end

-- syncPlayer removed (Guidelines v3 N1). StickerController uses _syncNetwork + buildSyncPayload.

function StickerService:getCurrentImage(player: Player): string
	return self._currentImages[player.UserId] or ""
end

function StickerService:addSticker(player: Player, image: string): any
	local normalized = normalizeImage(image)
	if normalized == "" then
		return nil
	end

	if type(self._repository.addToGlobalPool) == "function" then
		local globalResult = self._repository.addToGlobalPool(normalized)
		if globalResult.ok and type(globalResult.value) == "table" then
			self._globalStickers = globalResult.value.stickers
			self._log:info("Sticker added to global pool", {
				player = player.Name,
				image = normalized,
				poolSize = #self._globalStickers,
			})
		else
			self._log:warn("Sticker global pool update failed", { player = player.Name })
		end
	end

	local result = self._repository.update(player.UserId, function(current)
		local nextStickers = table.clone(current.stickers)
		if not containsImage(nextStickers, normalized) and #nextStickers < Config.Sticker.MAX_COLLECTION_SIZE then
			table.insert(nextStickers, normalized)
		end

		return {
			stickers = nextStickers,
			selectedSticker = current.selectedSticker,
		}
	end)

	if result.ok and type(result.value) == "table" then
		self._personalByUserId[player.UserId] = {
			stickers = if type(result.value.stickers) == "table" then result.value.stickers else {},
			selectedSticker = if type(result.value.selectedSticker) == "string"
				then result.value.selectedSticker
				else "",
		}
		return {
			stickers = self:_mergeVisibleStickers(self._personalByUserId[player.UserId].stickers),
			selectedSticker = self._personalByUserId[player.UserId].selectedSticker,
		}
	end

	return {
		stickers = self:_mergeVisibleStickers({}),
		selectedSticker = "",
	}
end

function StickerService:setSticker(player: Player, image: string): any
	local normalized = normalizeImage(image)
	if normalized == "" then
		self:clearSticker(player)
		return nil
	end

	local allowed = self:_isAllowedStickerImage(player.UserId, normalized)
	if not allowed then
		self._log:warn("Sticker set rejected, not in visible pool", {
			player = player.Name,
			image = normalized,
		})
		return nil
	end

	self._currentImages[player.UserId] = normalized
	player:SetAttribute(Config.Sticker.STICKER_IMAGE_ATTRIBUTE, normalized)
	self:_applySticker(player, normalized)
	self:_scheduleAutoClear(player, normalized)

	local personal = self:_getPersonalData(player.UserId)
	return {
		stickers = self:_mergeVisibleStickers(personal.stickers),
		selectedSticker = normalized,
	}
end

function StickerService:clearSticker(player: Player): any
	self._currentImages[player.UserId] = ""
	self._displayTokens[player.UserId] = (self._displayTokens[player.UserId] or 0) + 1
	player:SetAttribute(Config.Sticker.STICKER_IMAGE_ATTRIBUTE, "")
	self:_bumpStickerClearSignal(player)
	self:_applySticker(player, "")

	local personal = self:_getPersonalData(player.UserId)
	return {
		stickers = self:_mergeVisibleStickers(personal.stickers),
		selectedSticker = "",
	}
end

function StickerService:_hookCharacter(player: Player, character: Model)
	self:_ensureGui(player, character)

	local current = self._currentImages[player.UserId]
	if current then
		self:_applySticker(player, current)
	end
end

function StickerService:onStart()
	self:_refreshGlobalPool()

	-- Per-player connection pool: hanya CharacterAdded yang perlu per-player tracking.
	-- _connections tetap dipakai untuk koneksi global (PlayerAdded, PlayerRemoving).
	local playerConnections: { [number]: RBXScriptConnection } = {}

	local function connectCharacterAdded(player: Player)
		-- Disconnect koneksi lama jika ada (e.g. rejoin handling)
		local old = playerConnections[player.UserId]
		if old then
			old:Disconnect()
		end
		playerConnections[player.UserId] = player.CharacterAdded:Connect(function(character: Model)
			self:_hookCharacter(player, character)
		end)
	end

	local function applyJoinStickerState(player: Player)
		if not player.Parent then
			return
		end
		local payload = self:buildSyncPayload(player)
		self._currentImages[player.UserId] = normalizeImage(payload.selectedSticker)
		player:SetAttribute(Config.Sticker.STICKER_IMAGE_ATTRIBUTE, self._currentImages[player.UserId])
	end

	local profileLoader = self._profileLoader
	if profileLoader and type(profileLoader.register) == "function" and type(profileLoader.enqueueKind) == "function" then
		-- Fold personal sticker GetAsync into SharedProfileLoader so join does not
		-- free-fire a parallel read against overhead/profile/likes.
		profileLoader:register("stickers", function(player: Player)
			applyJoinStickerState(player)
			return Result.Ok(true)
		end)
		self:_track(Players.PlayerAdded:Connect(function(player: Player)
			profileLoader:enqueueKind(player, "stickers")
			connectCharacterAdded(player)
			if player.Character then
				self:_hookCharacter(player, player.Character)
			end
		end))
		for _, player in ipairs(Players:GetPlayers()) do
			profileLoader:enqueueKind(player, "stickers")
			connectCharacterAdded(player)
			if player.Character then
				self:_hookCharacter(player, player.Character)
			end
		end
	else
		self:_track(Players.PlayerAdded:Connect(function(player: Player)
			task.spawn(function()
				applyJoinStickerState(player)
			end)

			connectCharacterAdded(player)

			if player.Character then
				self:_hookCharacter(player, player.Character)
			end
		end))

		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(function()
				applyJoinStickerState(player)
			end)

			connectCharacterAdded(player)

			if player.Character then
				self:_hookCharacter(player, player.Character)
			end
		end
	end

	self:_track(Players.PlayerRemoving:Connect(function(player: Player)
		-- Cleanup per-player CharacterAdded connection
		local conn = playerConnections[player.UserId]
		if conn then
			conn:Disconnect()
			playerConnections[player.UserId] = nil
		end
		self._currentImages[player.UserId] = nil
		self._activeGuis[player.UserId] = nil
		self._displayTokens[player.UserId] = nil
		self._personalByUserId[player.UserId] = nil
	end))

	-- Simpan referensi playerConnections agar destroy() bisa cleanup
	self._playerConnections = playerConnections

	self._log:info("Sticker service initialized")
end

function StickerService:destroy()
	-- Cleanup per-player CharacterAdded connections
	if self._playerConnections then
		for _, conn in pairs(self._playerConnections) do
			conn:Disconnect()
		end
		table.clear(self._playerConnections)
	end
	-- Cleanup global service connections (PlayerAdded, PlayerRemoving)
	self:_clearConnections()
	-- Cleanup active GUIs
	for _, gui in pairs(self._activeGuis) do
		if gui and gui.Parent then
			gui:Destroy()
		end
	end
	table.clear(self._activeGuis)
	table.clear(self._currentImages)
	table.clear(self._displayTokens)
end

return StickerService

