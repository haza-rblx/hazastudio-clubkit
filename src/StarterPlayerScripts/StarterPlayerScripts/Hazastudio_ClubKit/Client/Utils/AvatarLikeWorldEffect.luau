--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local EFFECT_FOLDER_NAME = "AvatarLikeEffects"
local HEART_TEXT = "<3"

local AvatarLikeWorldEffect = {}
local initialized = false
local _connections: { RBXScriptConnection } = {}

local function track(conn: RBXScriptConnection): RBXScriptConnection
	table.insert(_connections, conn)
	return conn
end

function AvatarLikeWorldEffect.destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)
	initialized = false
end

local function getEffectFolder(): Folder
	local existing = workspace:FindFirstChild(EFFECT_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = EFFECT_FOLDER_NAME
	folder.Parent = workspace
	return folder
end

local function resolveRoot(userId: number): BasePart?
	local player = Players:GetPlayerByUserId(userId)
	if not player or not player.Character then
		return nil
	end

	local root = player.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	return nil
end

local function quadraticBezier(a: Vector3, b: Vector3, c: Vector3, t: number): Vector3
	local inv = 1 - t
	return (inv * inv * a) + (2 * inv * t * b) + (t * t * c)
end

local function createHeartVisual(sizePx: number): (Part, BillboardGui)
	local part = Instance.new("Part")
	part.Name = "AvatarLikeHeart"
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Transparency = 1
	part.Parent = getEffectFolder()

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HeartBillboard"
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	billboard.Size = UDim2.fromOffset(sizePx, sizePx)
	billboard.StudsOffset = Vector3.new(0, 0.35, 0)
	billboard.Adornee = part
	billboard.Parent = part

	if Config.AvatarContext.LIKE_HEART_IMAGE ~= "" then
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.Image = Config.AvatarContext.LIKE_HEART_IMAGE
		image.ImageColor3 = Color3.fromRGB(255, 96, 142)
		image.Parent = billboard
	else
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Font = Enum.Font.GothamBold
		text.Text = HEART_TEXT
		text.TextScaled = true
		text.TextColor3 = Color3.fromRGB(255, 96, 142)
		text.TextStrokeTransparency = 0.25
		text.TextStrokeColor3 = Color3.fromRGB(255, 225, 235)
		text.Parent = billboard
	end

	return part, billboard
end

local function animateBillboardSize(billboard: BillboardGui, alpha: number, baseSize: number)
	local pulse = 1 + (math.sin(alpha * math.pi) * 0.22)
	local size = math.max(12, math.floor(baseSize * pulse))
	billboard.Size = UDim2.fromOffset(size, size)
end

local function playTravelHeart(fromPos: Vector3, toPos: Vector3, delaySeconds: number)
	task.delay(delaySeconds, function()
		local baseSize = math.random(18, 28)
		local part, billboard = createHeartVisual(baseSize)
		local control = ((fromPos + toPos) / 2) + Vector3.new(
			(math.random() - 0.5) * 4,
			math.random(5, 8),
			(math.random() - 0.5) * 4
		)
		local startTime = os.clock()
		local duration = Config.AvatarContext.LIKE_TRAVEL_TIME + (math.random() * 0.16)

		while part.Parent do
			local alpha = math.clamp((os.clock() - startTime) / duration, 0, 1)
			part.Position = quadraticBezier(fromPos, control, toPos, alpha)
			animateBillboardSize(billboard, alpha, baseSize)
			if alpha >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end

		if part.Parent then
			part:Destroy()
		end
	end)
end

local function playBurst(centerPos: Vector3)
	for index = 1, 6 do
		task.delay((index - 1) * 0.025, function()
			local baseSize = math.random(14, 22)
			local part, billboard = createHeartVisual(baseSize)
			local direction = Vector3.new(
				(math.random() - 0.5) * 2.6,
				(math.random() * 1.8) + 1.2,
				(math.random() - 0.5) * 2.6
			)
			local startTime = os.clock()
			local duration = 0.38 + (math.random() * 0.12)

			while part.Parent do
				local alpha = math.clamp((os.clock() - startTime) / duration, 0, 1)
				part.Position = centerPos + (direction * alpha)
				animateBillboardSize(billboard, 1 - alpha, baseSize)
				if alpha >= 1 then
					break
				end
				RunService.Heartbeat:Wait()
			end

			if part.Parent then
				part:Destroy()
			end
		end)
	end
end

function AvatarLikeWorldEffect.play(payload: {
	fromUserId: number,
	toUserId: number,
	heartCount: number?,
})
	local fromRoot = resolveRoot(payload.fromUserId)
	local toRoot = resolveRoot(payload.toUserId)
	if not fromRoot or not toRoot then
		return
	end

	local fromPos = fromRoot.Position + Vector3.new(0, 2.4, 0)
	local toPos = toRoot.Position + Vector3.new(0, 2.8, 0)
	local heartCount = math.max(4, payload.heartCount or Config.AvatarContext.LIKE_HEART_COUNT)

	for index = 1, heartCount do
		local delaySeconds = ((index - 1) * 0.035) + (math.random() * 0.04)
		playTravelHeart(fromPos, toPos, delaySeconds)
	end

	task.delay(Config.AvatarContext.LIKE_TRAVEL_TIME + (heartCount * 0.035), function()
		playBurst(toPos)
	end)
end

function AvatarLikeWorldEffect.init(deps: {
	logger: any?,
	remote: RemoteEvent?,
})
	if initialized then
		return
	end
	initialized = true

	local logger = deps.logger
	local remote = deps.remote
	if not remote then
		local resolved = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Config.AvatarContext.REMOTE_LIKE_EFFECT)
		remote = resolved :: RemoteEvent
	end
	local likeEffectRemote = remote :: RemoteEvent

	track(likeEffectRemote.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			if logger and type(logger.warn) == "function" then
				logger:warn("AvatarLikeWorldEffect invalid payload")
			end
			return
		end
		if type(payload.fromUserId) ~= "number" or type(payload.toUserId) ~= "number" then
			if logger and type(logger.warn) == "function" then
				logger:warn("AvatarLikeWorldEffect missing user ids")
			end
			return
		end

		AvatarLikeWorldEffect.play(payload)
	end))
end

return AvatarLikeWorldEffect
