--!strict
-- PATH: StarterPlayer/StarterPlayerScripts/Client/Utils/NukeEffectController.luau
-- Listens to the DonationEffect remote (server broadcast) and clones the
-- matching VFX model from ReplicatedStorage.WorldEffects into workspace at
-- the configured world position. Self-cleans via Debris after NUKE_DEFAULT_DURATION.
--
-- Remote payload (server -> all clients):
--   effectName    : "Nuke" | "Smite" | "BlackHole" | ...
--   donorName     : string
--   recipientName : string
--   amount        : number

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local NukeEffectController = {}
local initialized = false
local connection: RBXScriptConnection? = nil

-- All world-position VFX models share the same BillboardGui template (LEGACY
-- layout). Two slightly different layouts exist:
--   Nuke      : BillboardGuiAnimation > Frame > TextLabels > { TopText, ... }
--   Smite/Blk : Objects > ImpactVisuals > BillboardGuiAnimation > Frame > { TopText, ... }
-- We look up the BillboardGui recursively, then look for either Frame >
-- TextLabels > {label} (Nuke) or Frame > {label} direct (Smite/BlackHole).
-- Models that don't follow either convention still play particles/sounds —
-- only the on-screen text is skipped.
local BILLBOARD_TEXT = {
	{ labelName = "TopText",    format = "@%s DONATED" },
	{ labelName = "MiddleText", format = "\u{E002}%s" },
	{ labelName = "BottomText", format = "TO @%s" },
}

local function getEffectsFolder(): Folder?
	local folderName = (Config.Donation :: any).NUKE_EFFECTS_FOLDER or "WorldEffects"
	local folder = ReplicatedStorage:FindFirstChild(folderName)
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

-- Apply text to a known TextLabel, formatted with donor/recipient.
-- Locates the BillboardGui at any depth, then resolves the label container
-- (Frame > TextLabels for Nuke, Frame direct for Smite/BlackHole). Skips
-- silently if any expected child is missing.
local function applyBillboardText(effectRoot: Instance, donorName: string, recipientName: string)
	local bb = effectRoot:FindFirstChild("BillboardGuiAnimation", true)
	if not bb or not bb:IsA("BillboardGui") then
		return
	end
	local frame = bb:FindFirstChild("Frame")
	if not frame then
		return
	end
	-- Nuke wraps labels in a "TextLabels" Frame; Smite/BlackHole put them
	-- directly under Frame. Try the wrapped form first, fall back to direct.
	local container = frame:FindFirstChild("TextLabels") or frame

	for _, entry in ipairs(BILLBOARD_TEXT) do
		local label = container:FindFirstChild(entry.labelName)
		if label and label:IsA("TextLabel") then
			local source = if entry.labelName == "BottomText" then recipientName else donorName
			if entry.format then
				label.Text = entry.format:format(source)
			else
				label.Text = source
			end
		end
	end
end

-- Walk the cloned VFX model and (a) enable ParticleEmitters, (b) play Sounds.
local function activateVfx(effect: Instance, duration: number)
	for _, descendant in ipairs(effect:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = true
		elseif descendant:IsA("Sound") then
			descendant:Play()
			-- Keep the sound alive at least until Debris removes its parent.
			Debris:AddItem(descendant, math.max(duration, (descendant.TimeLength or 0) + 1))
		end
	end
end

-- Position the cloned VFX at the configured world spot. Works for both Model
-- and standalone BasePart (Nuke in LEGACY is a MeshPart). Anchors parts so
-- the client doesn't need to claim network ownership.
local function positionEffect(effect: Instance, position: Vector3)
	if effect:IsA("Model") then
		effect:PivotTo(CFrame.new(position))
	elseif effect:IsA("BasePart") then
		effect.CFrame = CFrame.new(position)
	end

	for _, descendant in ipairs(effect:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end
end

local function playNuke(effectName: string, donorName: string, recipientName: string, amount: number)
	local folder = getEffectsFolder()
	if not folder then
		return
	end

	local template = folder:FindFirstChild(effectName)
	if not template then
		return
	end

	local clone = template:Clone()
	clone.Name = "HazastudioNukeEffect_" .. effectName

	local duration = (Config.Donation :: any).NUKE_DEFAULT_DURATION or 20
	local position = (Config.Donation :: any).NUKE_WORLD_POSITION :: Vector3? or Vector3.zero

	-- Parent to workspace BEFORE positioning so any descendants that look up
	-- ancestry (e.g. a Weld that expects the parent) don't NPE.
	clone.Parent = workspace
	positionEffect(clone, position)
	applyBillboardText(clone, donorName, recipientName)
	activateVfx(clone, duration)

	Debris:AddItem(clone, duration + 5)
end

function NukeEffectController.init(deps: {
	logger: any?,
	remote: (RemoteEvent | UnreliableRemoteEvent)?,
})
	if initialized then
		return
	end
	initialized = true

	local logger = deps.logger
	local remote = deps.remote
	if not remote then
		local remoteName = (Config.Donation :: any).NUKE_REMOTE or "DonationEffect"
		-- Server pre-creates the remote under the shared "Remotes" folder in
		-- ReplicatedStorage (see Main.server.luau). Fall back to a top-level
		-- lookup so the controller still works if the folder is missing.
		local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
		local resolved: Instance? = nil
		if remotesFolder then
			resolved = remotesFolder:WaitForChild(remoteName, 30)
		end
		if not resolved then
			resolved = ReplicatedStorage:WaitForChild(remoteName, 30)
		end
		if not resolved or (not resolved:IsA("RemoteEvent") and not resolved:IsA("UnreliableRemoteEvent")) then
			if logger and type(logger.warn) == "function" then
				logger:warn("NukeEffectController: remote not found", { name = remoteName })
			end
			return
		end
		remote = resolved :: RemoteEvent | UnreliableRemoteEvent
	end

	local nukeRemote = remote :: RemoteEvent | UnreliableRemoteEvent
	if connection then
		connection:Disconnect()
	end

	connection = nukeRemote.OnClientEvent:Connect(function(...)
		local args = { ... }
		local effectName = args[1]
		local donorName = args[2]
		local recipientName = args[3]
		local amount = args[4]

		if type(effectName) ~= "string" or effectName == "" then
			return
		end
		if type(donorName) ~= "string" then
			donorName = ""
		end
		if type(recipientName) ~= "string" then
			recipientName = ""
		end
		if type(amount) ~= "number" then
			amount = 0
		end

		-- Run in a separate thread so a slow VFX setup can't block the
		-- remote dispatcher (multiple nuke broadcasts can land back-to-back).
		task.spawn(playNuke, effectName, donorName, recipientName, amount)
	end)
end

function NukeEffectController.destroy()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	initialized = false
end

return NukeEffectController
