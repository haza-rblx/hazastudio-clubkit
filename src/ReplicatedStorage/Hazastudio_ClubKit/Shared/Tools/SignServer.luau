--!strict
-- Server logic for membership Sign tools.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)
local TextFilterUtil = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.TextFilterUtil)

local SignServer = {}

-- Shared per-UserId rate limiter across all sign tools. Prevents a single
-- client from spamming RemoteFunction:InvokeServer with huge strings to
-- exhaust the server-global TextService quota (which would also degrade
-- chat/donation filtering for everyone).
local signLimiter = RateLimiter.new(5, 10)
local MAX_SIGN_LENGTH = 64

local function ensureRemoteFunction(tool: Tool): RemoteFunction
	local existing = tool:FindFirstChild("RemoteFunction")
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	local remote = Instance.new("RemoteFunction")
	remote.Name = "RemoteFunction"
	remote.Parent = tool
	return remote
end

local function ensureSignBoard(tool: Tool): TextLabel
	local textPart = tool:FindFirstChild("Text")
	if not textPart or not textPart:IsA("BasePart") then
		local created = Instance.new("Part")
		created.Name = "Text"
		created.Size = Vector3.new(4, 3, 0.2)
		created.CanCollide = false
		created.Anchored = false
		created.Parent = tool
		textPart = created
	end

	local surfaceGui = textPart:FindFirstChild("SurfaceGui")
	if not surfaceGui or not surfaceGui:IsA("SurfaceGui") then
		local createdGui = Instance.new("SurfaceGui")
		createdGui.Name = "SurfaceGui"
		createdGui.Face = Enum.NormalId.Front
		createdGui.Parent = textPart
		surfaceGui = createdGui
	end

	local textLabel = surfaceGui:FindFirstChildWhichIsA("TextLabel")
	if not textLabel then
		local createdLabel = Instance.new("TextLabel")
		createdLabel.Name = "TextLabel"
		createdLabel.Size = UDim2.fromScale(1, 1)
		createdLabel.BackgroundTransparency = 1
		createdLabel.TextColor3 = Color3.new(1, 1, 1)
		createdLabel.TextScaled = true
		createdLabel.Text = ""
		createdLabel.Parent = surfaceGui
		textLabel = createdLabel
	end

	return textLabel :: TextLabel
end

local function filterText(letters: string, userId: number): (boolean, string, string)
	-- Single attempt (retries = 1): a per-sign retry loop would multiply the
	-- TextService quota a spamming client can burn (see signLimiter note).
	local filtered = TextFilterUtil.filterForBroadcast(userId, letters, MAX_SIGN_LENGTH, 1)
	if filtered then
		return true, "", filtered
	end
	return false, "filter_failed", ""
end

function SignServer.bind(tool: Tool)
	local remote = ensureRemoteFunction(tool)
	local textLabel = ensureSignBoard(tool)

	remote.OnServerInvoke = function(player: Player, letters: any)
		-- Type + length validation. The Luau annotation `string` is NOT
		-- runtime-enforced, so a client can pass a table/Instance/number or a
		-- megabyte-sized string. Reject early to protect TextService quota.
		if type(letters) ~= "string" then
			return false, "invalid_input"
		end
		if #letters == 0 or #letters > MAX_SIGN_LENGTH then
			return false, "invalid_length"
		end
		if not signLimiter:check(player.UserId) then
			return false, "rate_limited"
		end
		local isSuccess, errorMessage, filteredText = filterText(letters, player.UserId)
		if isSuccess then
			textLabel.Text = filteredText
			return true
		end
		return false, errorMessage
	end
end

return SignServer
