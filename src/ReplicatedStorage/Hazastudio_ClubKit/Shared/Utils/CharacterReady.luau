--!strict
-- Shared character readiness for small maps (near-instant) and large/streamed maps.
-- Tiers:
--   parts — Humanoid + HumanoidRootPart
--   adorn — parts + stable Head (nametag / stickers / loading suppress)
--   anim  — parts + Animator under Humanoid (dance restore / sync) — does NOT need Head

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

export type Tier = "parts" | "adorn" | "anim"

export type Snapshot = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	head: BasePart?,
	animator: Animator?,
}

local DEFAULT_ADORNEE_PRIORITY = { "UpperTorso", "Torso", "HumanoidRootPart", "Head" }

local CharacterReady = {}

local function resolveCharacter(target: Player | Model): Model?
	if target:IsA("Player") then
		local character = target.Character
		if character and character.Parent then
			return character
		end
		return nil
	end
	if target:IsA("Model") and target.Parent then
		return target
	end
	return nil
end

local function stillCurrent(player: Player?, character: Model): boolean
	if not character.Parent then
		return false
	end
	if player and player.Character ~= character then
		return false
	end
	return true
end

local function headStableTimeout(): number
	return math.max(
		tonumber(Config.Overhead.HEAD_WAIT_TIMEOUT) or 5,
		tonumber(Config.Overhead.HEAD_STABLE_TIMEOUT) or 8
	)
end

local function headStableDebounce(): number
	return math.max(0.05, tonumber(Config.Overhead.HEAD_STABLE_DEBOUNCE) or 0.35)
end

local function partsTimeout(): number
	return math.max(1, tonumber(Config.Overhead.CHARACTER_PART_WAIT_TIMEOUT) or 5)
end

local function hasAppearanceLoaded(player: Player): boolean
	local ok, loaded = pcall(function()
		return player:HasAppearanceLoaded()
	end)
	return ok and loaded == true
end

local function findHead(character: Model): BasePart?
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return nil
end

--- Debounce fallback when AppearanceLoaded is unavailable / never fires (e.g. some StarterCharacters).
local function waitStableHeadDebounce(character: Model, deadline: number): BasePart?
	local remaining = math.max(0.05, deadline - os.clock())
	local head: Instance? = character:WaitForChild("Head", remaining)
	if not head or not head:IsA("BasePart") then
		return nil
	end
	local debounce = headStableDebounce()
	local stableSince = os.clock()
	while os.clock() < deadline do
		if not character.Parent then
			return nil
		end
		local current = character:FindFirstChild("Head")
		if current ~= head then
			head = current
			if not head or not head:IsA("BasePart") then
				remaining = deadline - os.clock()
				if remaining <= 0 then
					return nil
				end
				head = character:WaitForChild("Head", remaining)
				if not head or not head:IsA("BasePart") then
					return nil
				end
			end
			stableSince = os.clock()
		elseif (os.clock() - stableSince) >= debounce then
			return head :: BasePart
		end
		task.wait(0.05)
	end
	return findHead(character)
end

--- Non-yielding readiness check.
function CharacterReady.snapshot(target: Player | Model, tier: Tier): Snapshot?
	local character = resolveCharacter(target)
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or not humanoid.Parent then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local head: BasePart? = nil
	if tier == "adorn" then
		local h = findHead(character)
		if not h then
			return nil
		end
		head = h
	end
	local animator: Animator? = nil
	if tier == "anim" then
		local a = humanoid:FindFirstChildOfClass("Animator")
		if not a then
			return nil
		end
		animator = a
	end
	return {
		character = character,
		humanoid = humanoid,
		root = root,
		head = head,
		animator = animator,
	}
end

function CharacterReady.isReady(target: Player | Model, tier: Tier): boolean
	return CharacterReady.snapshot(target, tier) ~= nil
end

--- Wait until Head is final enough to parent adornments.
--- Prefers AppearanceLoaded (R15 package replace is done); debounce is fallback only.
function CharacterReady.waitStableHead(character: Model, timeoutSec: number?): BasePart?
	local timeout = timeoutSec or headStableTimeout()
	local deadline = os.clock() + timeout
	local player = Players:GetPlayerFromCharacter(character)

	if player then
		-- Fast path: appearance already final → Head is the package Head, not the temp baseline.
		if hasAppearanceLoaded(player) then
			local head = findHead(character)
			if head then
				return head
			end
		end

		local appearanceDone = false
		local conn = player.CharacterAppearanceLoaded:Connect(function()
			appearanceDone = true
		end)
		while os.clock() < deadline do
			if not stillCurrent(player, character) then
				conn:Disconnect()
				return nil
			end
			if appearanceDone or hasAppearanceLoaded(player) then
				conn:Disconnect()
				local head = findHead(character)
				if head then
					return head
				end
				-- Appearance flagged loaded but Head not yet present — fall through to debounce.
				break
			end
			task.wait(0.05)
		end
		conn:Disconnect()
	end

	return waitStableHeadDebounce(character, deadline)
end

--- Yielding readiness. Cancels if Player.Character changes mid-wait.
function CharacterReady.wait(target: Player | Model, tier: Tier, timeoutSec: number?): Snapshot?
	local player: Player? = if target:IsA("Player") then target else nil
	local defaultTimeout = if tier == "adorn" then headStableTimeout() else partsTimeout()
	local timeout = timeoutSec or defaultTimeout
	local deadline = os.clock() + timeout

	local character = resolveCharacter(target)
	if not character and player then
		local remaining = deadline - os.clock()
		if remaining <= 0 then
			return nil
		end
		-- Deadline-bound Character wait (CharacterAdded:Wait() alone can hang forever).
		local got: Model? = nil
		local conn = player.CharacterAdded:Connect(function(char)
			if typeof(char) == "Instance" and char:IsA("Model") then
				got = char
			end
		end)
		while not got and os.clock() < deadline and player.Parent do
			local existing = player.Character
			if existing and existing:IsA("Model") and existing.Parent then
				got = existing
				break
			end
			task.wait(0.05)
		end
		conn:Disconnect()
		character = got
	end
	if not character or not stillCurrent(player, character) then
		return nil
	end

	local remaining = math.max(0.05, deadline - os.clock())
	local humanoidInst = character:WaitForChild("Humanoid", remaining)
	if not humanoidInst or not humanoidInst:IsA("Humanoid") or not stillCurrent(player, character) then
		return nil
	end
	local humanoid = humanoidInst :: Humanoid

	remaining = math.max(0.05, deadline - os.clock())
	local rootInst = character:WaitForChild("HumanoidRootPart", remaining)
	if not rootInst or not rootInst:IsA("BasePart") or not stillCurrent(player, character) then
		return nil
	end
	local root = rootInst :: BasePart

	local head: BasePart? = nil
	if tier == "adorn" then
		remaining = math.max(0.05, deadline - os.clock())
		head = CharacterReady.waitStableHead(character, remaining)
		if not head or not stillCurrent(player, character) then
			return nil
		end
	end

	local animator: Animator? = nil
	if tier == "anim" then
		remaining = math.max(0.05, deadline - os.clock())
		local existing = humanoid:FindFirstChildOfClass("Animator")
		if existing then
			animator = existing
		else
			local waited = humanoid:WaitForChild("Animator", remaining)
			if waited and waited:IsA("Animator") then
				animator = waited
			end
		end
		if not animator or not stillCurrent(player, character) then
			return nil
		end
	end

	return {
		character = character,
		humanoid = humanoid,
		root = root,
		head = head,
		animator = animator,
	}
end

--- Rebind when Head is replaced (client overhead / loading suppress).
function CharacterReady.onHeadAdded(character: Model, callback: (head: BasePart) -> ()): RBXScriptConnection
	return character.ChildAdded:Connect(function(child)
		if child.Name == "Head" and child:IsA("BasePart") then
			callback(child)
		end
	end)
end

--- Sticker / adorn part resolution (matches StickerService priority).
function CharacterReady.findAdornee(character: Model, priorityNames: { string }?): BasePart?
	local priority = priorityNames or DEFAULT_ADORNEE_PRIORITY
	for _, partName in ipairs(priority) do
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

--- No-op when StreamingEnabled is false (keeps small maps lightning-fast).
function CharacterReady.streamAround(player: Player, position: Vector3)
	if not Workspace.StreamingEnabled then
		return
	end
	pcall(function()
		player:RequestStreamAroundAsync(position)
	end)
end

--- PivotTo with optional stream warm + one verify retry (large maps).
function CharacterReady.pivotTo(
	player: Player,
	character: Model,
	targetCFrame: CFrame,
	verifyStuds: number?
): boolean
	if not character.Parent then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Sit = false
	end
	CharacterReady.streamAround(player, targetCFrame.Position)
	character:PivotTo(targetCFrame)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
		local threshold = verifyStuds or 50
		if (hrp.Position - targetCFrame.Position).Magnitude > threshold then
			CharacterReady.streamAround(player, targetCFrame.Position)
			character:PivotTo(targetCFrame)
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
		end
	end
	return true
end

return CharacterReady
