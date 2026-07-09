--!strict
-- Server logic for membership Rope tools.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RateLimiter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.RateLimiter)

local RopeServer = {}

-- Shared per-UserId rate limiter across all rope tools. A holder could
-- otherwise spam hundreds of rope create/destroy events per second, churning
-- RopeConstraint/Attachment instantiation and the physics engine for everyone
-- near the tool.
local ropeLimiter = RateLimiter.new(8, 2)

local function getHumanoidRootPart(tool: Tool): BasePart?
	local character = tool.Parent
	if not character or not character:IsA("Model") then
		return nil
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp :: BasePart
	end
	return nil
end

local function ensureRemoteEvent(tool: Tool): RemoteEvent
	local existing = tool:FindFirstChild("RemoteEvent")
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = "RemoteEvent"
	remote.Parent = tool
	return remote
end

function RopeServer.bind(tool: Tool)
	local remote = ensureRemoteEvent(tool)

	local rope: RopeConstraint? = nil
	local att0: Attachment? = nil
	local att1: Attachment? = nil
	local newRope: BasePart? = nil

	local function cleanupRope()
		if rope then
			rope:Destroy()
			rope = nil
		end
		if att0 then
			att0:Destroy()
			att0 = nil
		end
		if att1 then
			att1:Destroy()
			att1 = nil
		end
		if newRope then
			newRope:Destroy()
			newRope = nil
		end
	end

	remote.OnServerEvent:Connect(function(_plr: Player, target: Instance?, hit: CFrame?)
		-- Assert the firing player actually holds the tool. The remote is a
		-- child of the tool, so a client that obtains a reference (e.g. via a
		-- leaked parent path) could otherwise trigger it without owning the tool.
		if _plr.Character ~= tool.Parent then
			return
		end
		if not ropeLimiter:check(_plr.UserId) then
			return
		end
		if rope == nil then
			if target == nil then
				return
			end
			if target:IsA("Sky") or target:IsA("Atmosphere") then
				return
			end
			local hrp = getHumanoidRootPart(tool)
			if not hrp then
				return
			end
			if target.Name ~= "Baseplate" then
				if not target:IsA("BasePart") then
					return
				end
				if (hrp.Position - target.Position).Magnitude > 30 then
					return
				end
				local createdRope = Instance.new("RopeConstraint")
				local createdAtt0 = Instance.new("Attachment")
				local createdAtt1 = Instance.new("Attachment")
				createdAtt0.Parent = target
				createdAtt1.Parent = hrp
				createdRope.Visible = true
				createdRope.Parent = hrp
				createdRope.Attachment0 = createdAtt0
				createdRope.Attachment1 = createdAtt1
				createdRope.Length = (hrp.Position - target.Position).Magnitude
				rope = createdRope
				att0 = createdAtt0
				att1 = createdAtt1
			else
				local forRope = ServerStorage:FindFirstChild("ForRope")
				if not forRope or not forRope:IsA("BasePart") or hit == nil then
					return
				end
				local cloned = forRope:Clone()
				cloned.Parent = workspace
				cloned.CFrame = hit
				task.wait(0.05)
				if (hrp.Position - cloned.Position).Magnitude > 30 then
					cloned:Destroy()
					return
				end
				newRope = cloned
				local createdRope = Instance.new("RopeConstraint")
				local createdAtt0 = Instance.new("Attachment")
				local createdAtt1 = Instance.new("Attachment")
				createdAtt0.Parent = cloned
				createdAtt1.Parent = hrp
				createdRope.Visible = true
				createdRope.Parent = hrp
				createdRope.Attachment0 = createdAtt0
				createdRope.Attachment1 = createdAtt1
				createdRope.Length = (hrp.Position - cloned.Position).Magnitude
				rope = createdRope
				att0 = createdAtt0
				att1 = createdAtt1
			end
		else
			cleanupRope()
		end
	end)

	tool.Unequipped:Connect(cleanupRope)
end

return RopeServer
