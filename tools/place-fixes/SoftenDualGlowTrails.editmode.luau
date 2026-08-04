-- Place-only: DualGlowStick trails = full stick length + soft fade.
-- Run in Edit via MCP / Command Bar.

local toolsRoot = game:GetService("ServerStorage"):FindFirstChild("Tools")
if not toolsRoot then
	return { error = "ServerStorage.Tools missing" }
end

local function restoreFullTrail(part: BasePart)
	local halfH = part.Size.Y * 0.5
	local tipY = halfH * 0.92
	local baseY = -halfH * 0.92
	local x = -math.max(part.Size.X, part.Size.Z) * 0.35

	local a0 = part:FindFirstChild("TrailA0")
	local a1 = part:FindFirstChild("TrailA1")
	if not a0 or not a0:IsA("Attachment") then
		a0 = Instance.new("Attachment")
		a0.Name = "TrailA0"
		a0.Parent = part
	end
	if not a1 or not a1:IsA("Attachment") then
		a1 = Instance.new("Attachment")
		a1.Name = "TrailA1"
		a1.Parent = part
	end
	a0.Position = Vector3.new(x, tipY, 0)
	a1.Position = Vector3.new(x, baseY, 0)

	local trail = part:FindFirstChildWhichIsA("Trail")
	if not trail then
		trail = Instance.new("Trail")
		trail.Name = "Trail"
		trail.Parent = part
	end
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Enabled = true
	trail.FaceCamera = true
	trail.Lifetime = 1.25
	trail.MinLength = 0.01
	trail.MaxLength = 14
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Brightness = 2.0
	trail.Texture = ""
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.5, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.7, 0.85),
		NumberSequenceKeypoint.new(1, 0),
	})
end

local n = 0
for _, role in ipairs(toolsRoot:GetChildren()) do
	if role:IsA("Folder") then
		local dual = role:FindFirstChild("DualGlowStick")
		if dual and dual:IsA("Tool") then
			for _, name in ipairs({ "Handle", "Handle2" }) do
				local part = dual:FindFirstChild(name)
				if part and part:IsA("BasePart") then
					restoreFullTrail(part)
				end
			end
			n += 1
		end
	end
end

return { softened = n }
