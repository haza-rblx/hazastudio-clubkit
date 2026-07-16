-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DonationExperiencePrefs = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DonationExperiencePrefs)
local WorldEffectFlight = require(script.Parent.Parent.Parent.Utils.WorldEffectFlight)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local LocalPlayer = game.Players.LocalPlayer
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")

-- Camera shaker and constants
local CameraShaker = require(script.CameraShaker)
local SoundAssetSanitizer = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.SoundAssetSanitizer)
-- Fallback only — buyer sets ClubKitConfig.Donation.NukeWorldPosition → NUKE_WORLD_POSITION.
local DEFAULT_SPAWN_POSITION = Vector3.new(-60.5, 1.5, -44.891)

local function resolveNukeWorldPosition(): Vector3
	local pos = (Config.Donation :: any).NUKE_WORLD_POSITION
	if typeof(pos) == "Vector3" then
		return pos
	end
	return DEFAULT_SPAWN_POSITION
end

-- Optional legacy launch pad in the place. If missing, launch from the configured impact spot.
local function resolveLaunchCFrame(impactPosition: Vector3): CFrame
	local nukeModel = workspace:FindFirstChild("NukeModel")
	if nukeModel then
		local cfValue = nukeModel:FindFirstChild("CFrame")
		if cfValue and cfValue:IsA("CFrameValue") then
			return cfValue.Value
		end
		if nukeModel:IsA("BasePart") then
			return nukeModel.CFrame
		end
		if nukeModel:IsA("Model") then
			return nukeModel:GetPivot()
		end
	end
	return CFrame.new(impactPosition)
end

-- Helper function to scale particle effects
local function scaleParticleEffect(particleEmitter, scaleFactor)
	particleEmitter.Speed = NumberRange.new(
		particleEmitter.Speed.Min * scaleFactor,
		particleEmitter.Speed.Max * scaleFactor
	)
	particleEmitter.Acceleration = particleEmitter.Acceleration * scaleFactor

	local keypoints = particleEmitter.Size.Keypoints
	local newKeypoints = {}

	for i = 1, #keypoints do
		table.insert(newKeypoints, NumberSequenceKeypoint.new(
			keypoints[i].Time,
			keypoints[i].Value * scaleFactor,
			keypoints[i].Envelope * scaleFactor
			))
	end

	particleEmitter.Size = NumberSequence.new(newKeypoints)
end

-- Main nuke effect function
local function createNukeEffect(nukeModel, donatorName, recipientName, donationAmount)
	local gen = WorldEffectFlight:begin()
	local cleaned = false
	local nukeClone = nil
	local bloomEffect = nil
	local heartbeatConnection = nil
	local confettiClone = nil

	local function cleanup()
		if cleaned then
			return
		end
		cleaned = true
		if heartbeatConnection then
			heartbeatConnection:Disconnect()
			heartbeatConnection = nil
		end
		local alarmSound = script:FindFirstChild("Alarm")
		if alarmSound and alarmSound:IsA("Sound") then
			alarmSound:Stop()
		end
		local activeFireworks = workspace:FindFirstChild("ActiveFireworks")
		if activeFireworks then
			activeFireworks:Destroy()
		end
		if bloomEffect then
			bloomEffect:Destroy()
			bloomEffect = nil
		end
		if confettiClone then
			confettiClone:Destroy()
			confettiClone = nil
		end
		if nukeClone then
			nukeClone:Destroy()
			nukeClone = nil
		end
	end
	WorldEffectFlight:setCleanup(gen, cleanup)

	local function wait(seconds)
		if not WorldEffectFlight:wait(gen, seconds) then
			error("WorldEffectAborted")
		end
	end

	local ok, err = pcall(function()
	-- Impact / descent target: ClubKitConfig.Donation.NukeWorldPosition
	local SPAWN_POSITION = resolveNukeWorldPosition()

	nukeClone = nukeModel:Clone()
	SoundAssetSanitizer.removeBlockedSounds(nukeClone)
	local nukeCFrame = nukeClone.NukeValues.NukeCFrame
	local donationFrame = nukeClone.BillboardGuiAnimation.Frame

	-- Sembunyikan billboard dulu — nanti muncul setelah impact
	donationFrame.Parent.Enabled = false

	local centerEmitPoint = nukeClone.CenterEmitPoint
	local thrustEmitPoint = nukeClone.ThrustEmitPoint

	-- Create bloom effect
	bloomEffect = Instance.new("BloomEffect")
	bloomEffect.Enabled = true
	bloomEffect.Name = "NukeBloom"
	bloomEffect.Size = 15
	bloomEffect.Threshold = 0.25
	bloomEffect.Intensity = -1
	bloomEffect.Parent = game.Lighting

	-- Get confetti box
	local objectsFolder = nukeClone.Objects
	local confettiBox = objectsFolder.ConfettiBox:Clone()
	objectsFolder.ConfettiBox:Destroy()
	objectsFolder:Destroy()

	-- Setup camera shaker (disabled — no-op dummy)
	local cameraShaker = {
		Start = function() end,
		Stop = function() end,
		ShakeSustain = function() end,
		ShakeOnce = function() end,
		StopSustained = function() end,
	}

	-- Scale all particle effects
	scaleParticleEffect(thrustEmitPoint.Flame, 5)
	scaleParticleEffect(thrustEmitPoint.Shockwave, 15)
	scaleParticleEffect(thrustEmitPoint.BigShockwave, 50)
	scaleParticleEffect(thrustEmitPoint.Flame2, 5)
	scaleParticleEffect(thrustEmitPoint.Flame3, 5)
	scaleParticleEffect(thrustEmitPoint.Flame4, 5)
	scaleParticleEffect(thrustEmitPoint.Flame5, 10)
	scaleParticleEffect(thrustEmitPoint.Smoke, 1.5)
	scaleParticleEffect(thrustEmitPoint.SmokePreLaunch, 3)
	scaleParticleEffect(thrustEmitPoint.SmokeLaunch, 4)
	scaleParticleEffect(thrustEmitPoint.SmokeRing, 4)
	scaleParticleEffect(nukeClone.Sparkles, 2.5)
	scaleParticleEffect(nukeClone.Sparks, 3)
	scaleParticleEffect(centerEmitPoint.Rays1, 25)
	scaleParticleEffect(centerEmitPoint.Rays2, 25)
	scaleParticleEffect(centerEmitPoint.Rays3, 25)
	scaleParticleEffect(centerEmitPoint.SmoothRaysBig, 7.5)
	scaleParticleEffect(centerEmitPoint.RaysBig, 8)
	scaleParticleEffect(centerEmitPoint.SparkleExplosion, 4)
	scaleParticleEffect(centerEmitPoint.Spark3, 25)

	-- Launch pad: optional workspace.NukeModel; else stage (NUKE_WORLD_POSITION).
	-- Descent / impact always targets NUKE_WORLD_POSITION (SPAWN_POSITION below).
	nukeClone.CFrame = resolveLaunchCFrame(SPAWN_POSITION)
	nukeClone.AlignPosition.Position = nukeClone.Position
	nukeClone.AlignOrientation.CFrame = nukeClone.CFrame
	nukeCFrame.Value = nukeClone.CFrame
	nukeClone.Anchored = false
	nukeClone.Parent = workspace

	-- Position tracking
	heartbeatConnection = RunService.Heartbeat:Connect(function()
		nukeClone.AlignPosition.Position = nukeCFrame.Value.Position
		nukeClone.AlignOrientation.CFrame = nukeCFrame.Value
	end)

	wait(1)

	-- Alarm phase
	local alarmSound = script:FindFirstChild("Alarm")
	if alarmSound and alarmSound:IsA("Sound") then
		alarmSound:Play()
	end
	nukeClone.Sparkles.Enabled = false
	nukeClone.ThrustEmitPoint.SmokePreLaunch.Enabled = true
	nukeClone.ThrustEmitPoint.SmokePreLaunch.Rate = 0
	nukeClone.PreThruster:Play()
	nukeClone.PreThruster.Volume = 0
	nukeClone.PreThruster.PlaybackSpeed = 0.1

	TweenService:Create(nukeClone.PreThruster, TweenInfo.new(5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Volume = 1,
		PlaybackSpeed = 0.5
	}):Play()

	TweenService:Create(nukeClone.ThrustEmitPoint.SmokePreLaunch, TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Rate = 100
	}):Play()

	wait(5)

	-- Launch preparation
	cameraShaker:ShakeSustain(CameraShaker.Presets.Earthquake)
	nukeClone.Sparkles.Enabled = true
	nukeClone.ThrustEmitPoint.SmokePreLaunch.Enabled = false
	thrustEmitPoint.SmokeLaunch:Emit(50)
	nukeClone.AlignPosition.Responsiveness = 25
	nukeClone.AlignOrientation.Responsiveness = 25
	nukeClone.PreLaunch:Play()
	nukeClone.Thruster2:Play()

	TweenService:Create(nukeClone.Thruster2, TweenInfo.new(4, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
		PlaybackSpeed = 1.5,
		Volume = 3
	}):Play()

	TweenService:Create(nukeClone.PreThruster, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Volume = 1,
		PlaybackSpeed = 1
	}):Play()

	-- Enable thrust effects
	for _, effect in pairs(thrustEmitPoint:GetChildren()) do
		if not string.find(effect.Name, "Flame") then
			effect.Enabled = true
		end
	end

	thrustEmitPoint.SmokeRing.Enabled = false
	thrustEmitPoint.SmokeLaunch.Enabled = false
	thrustEmitPoint.Shockwave.Enabled = false
	thrustEmitPoint.BigShockwave.Enabled = false
	thrustEmitPoint.Flare.Enabled = false

	centerEmitPoint.Rays1.Enabled = true
	centerEmitPoint.Rays2.Enabled = true
	centerEmitPoint.Rays3.Enabled = true

	-- Ascending phase
	for i = 1, 10 do
		nukeCFrame.Value = nukeCFrame.Value:ToWorldSpace(CFrame.Angles(0, 0, 0.17453292519943295))
		nukeCFrame.Value = nukeCFrame.Value:ToWorldSpace(CFrame.new(0, 25, 0))
		wait(i * 0.0125)
	end

	nukeClone.AlignPosition.Responsiveness = 10
	nukeClone.AlignOrientation.Responsiveness = 10
	nukeCFrame.Value = CFrame.new(nukeCFrame.Value.Position, SPAWN_POSITION):ToWorldSpace(CFrame.Angles(-1.5707963267948966, 0, 0))

	wait(0.5)

	-- Flash effect
	bloomEffect.Intensity = 1
	bloomEffect.Size = 20
	TweenService:Create(bloomEffect, TweenInfo.new(1, Enum.EasingStyle.Circular, Enum.EasingDirection.Out), {
		Intensity = -1,
		Size = 10
	}):Play()

	nukeClone.AlignPosition.Responsiveness = 50
	nukeClone.AlignOrientation.Responsiveness = 50

	-- Launch effects
	thrustEmitPoint.SmokeRing:Emit(50)
	thrustEmitPoint.Flame:Emit(25)
	thrustEmitPoint.Flame2:Emit(25)
	thrustEmitPoint.Flame3:Emit(25)
	thrustEmitPoint.Flame4:Emit(25)
	thrustEmitPoint.Flame5:Emit(25)
	thrustEmitPoint.Shockwave.Enabled = true
	thrustEmitPoint.BigShockwave:Emit(1)

	nukeClone.Launch:Play()
	nukeClone.Thruster:Play()

	for _, effect in pairs(thrustEmitPoint:GetChildren()) do
		effect.Enabled = true
	end

	thrustEmitPoint.SmokeRing.Enabled = false
	thrustEmitPoint.SmokeLaunch.Enabled = false
	thrustEmitPoint.BigShockwave.Enabled = false
	thrustEmitPoint.Flare:Emit(10)

	-- Descent to target
	TweenService:Create(nukeCFrame, TweenInfo.new(2.5, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Value = CFrame.new(SPAWN_POSITION + Vector3.new(0, -1, 0), SPAWN_POSITION):ToWorldSpace(CFrame.Angles(1.5707963267948966, 0, 0))
	}):Play()

	wait(2.6)

	-- Impact sequence
	cameraShaker:StopSustained(0)
	cameraShaker:ShakeOnce(4, 6, 0.25, 4)
	alarmSound = script:FindFirstChild("Alarm")
	if alarmSound and alarmSound:IsA("Sound") then
		alarmSound:Stop()
	end

	bloomEffect.Intensity = 1
	bloomEffect.Size = 30
	TweenService:Create(bloomEffect, TweenInfo.new(5, Enum.EasingStyle.Circular, Enum.EasingDirection.Out), {
		Intensity = -1,
		Size = 10
	}):Play()

	nukeClone.Anchored = true
	nukeClone.Transparency = 1
	nukeClone.Size = Vector3.new(0, 0, 0)
	nukeClone.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	nukeClone.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	nukeClone.CFrame = nukeCFrame.Value

	nukeClone.PreThruster:Stop()
	nukeClone.Thruster:Stop()
	nukeClone.Thruster2:Stop()
	nukeClone.Explosion.TimePosition = 0.75
	nukeClone.Explosion:Play()
	nukeClone.ChimeLoop:Play()
	if nukeClone:FindFirstChild("ApplauseLoop") then
		nukeClone.ApplauseLoop:Play()
	end
	nukeClone.CoinsLoop:Play()

	-- Function to preserve the exact case of the username
	local function preserveExactCase(username)
		return username
	end

	-- Setup donation GUI text
	donationFrame.TextLabels.TopText.Text = "@" .. preserveExactCase(donatorName) .. " DONATED"
	donationFrame.TextLabels.MiddleText.Text = "" .. tostring(donationAmount):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	donationFrame.TextLabels.BottomText.Text = "TO @" .. preserveExactCase(recipientName)

	donationFrame.RobuxLogo.Size = UDim2.fromScale(0, 0)
	donationFrame.RobuxLogo.Rotation = -180
	donationFrame.Star.Size = UDim2.fromScale(0, 0)
	donationFrame.TextLabels.BottomText.Size = UDim2.fromScale(0, 0)
	donationFrame.TextLabels.BottomText.Position = UDim2.fromScale(0.5, 0.5)
	donationFrame.TextLabels.MiddleText.Size = UDim2.fromScale(0, 0)
	donationFrame.TextLabels.TopText.Position = UDim2.fromScale(0.5, 0.5)
	donationFrame.TextLabels.TopText.Size = UDim2.fromScale(0, 0)
	-- Billboard muncul setelah impact
	donationFrame.TextLabels.TopText.Visible = true
	donationFrame.TextLabels.BottomText.Visible = true
	donationFrame.Parent.Enabled = true

	TweenService:Create(nukeClone, TweenInfo.new(20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = SPAWN_POSITION + Vector3.new(0, 250, 0)
	}):Play()

	TweenService:Create(donationFrame.RobuxLogo, TweenInfo.new(10, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1, 1)
	}):Play()

	TweenService:Create(donationFrame.RobuxLogo, TweenInfo.new(15, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
		Rotation = 0
	}):Play()

	TweenService:Create(donationFrame.Star, TweenInfo.new(5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1.5, 1.5)
	}):Play()

	TweenService:Create(donationFrame.Star, TweenInfo.new(15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Rotation = 360
	}):Play()

	TweenService:Create(donationFrame.Star, TweenInfo.new(10, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 5), {
		ImageTransparency = 1,
		ImageColor3 = Color3.fromRGB(255, 255, 0)
	}):Play()

	-- Disable thrust effects
	for _, effect in pairs(thrustEmitPoint:GetChildren()) do
		effect.Enabled = false
	end

	nukeClone.Sparkles.Enabled = false

	-- Disable center effects and emit final bursts
	for _, effect in pairs(centerEmitPoint:GetChildren()) do
		effect.Enabled = false
	end

	centerEmitPoint.SparkleExplosion:Emit(100)
	centerEmitPoint.Shockwave:Emit(15)
	centerEmitPoint.FractalBurst:Emit(3)
	centerEmitPoint.RaysBig:Emit(20)
	centerEmitPoint.Spark1:Emit(100)
	centerEmitPoint.Spark2:Emit(100)
	centerEmitPoint.Spark3:Emit(50)

	-- Create confetti effect
	confettiClone = confettiBox:Clone()
	confettiClone.Position = SPAWN_POSITION + Vector3.new(0, 250, 0)
	confettiClone.Parent = workspace

	TweenService:Create(confettiClone, TweenInfo.new(10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(1000, 100, 1000)
	}):Play()

	spawn(function()
		local ownedConfetti = confettiClone
		if not ownedConfetti or not WorldEffectFlight:isActive(gen) then
			return
		end
		local confettiEffects = ownedConfetti:GetChildren()
		for _, effect in pairs(confettiEffects) do
			if effect:IsA("ParticleEmitter") then
				effect.Enabled = true
			end
		end

		if not WorldEffectFlight:wait(gen, 60) then
			return
		end

		for _, effect in pairs(confettiEffects) do
			if effect:IsA("ParticleEmitter") then
				TweenService:Create(effect, TweenInfo.new(60, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Rate = 0
				}):Play()
			end
		end

		if not WorldEffectFlight:wait(gen, 60) then
			return
		end
		if ownedConfetti.Parent then
			ownedConfetti.Size = Vector3.new(0, 0, 0)
		end
		if not WorldEffectFlight:wait(gen, 30) then
			return
		end
		if ownedConfetti.Parent then
			ownedConfetti:Destroy()
		end
	end)

	-- Enable fireworks
	local spawnFireworksScript = script:FindFirstChild("Scripts") and script.Scripts:FindFirstChild("SpawnFireworks")
	if spawnFireworksScript and spawnFireworksScript:IsA("Script") then
		local spawnPos = spawnFireworksScript:FindFirstChild("SpawnPosition")
		if spawnPos then
			spawnPos.Value = SPAWN_POSITION
		end
		spawnFireworksScript.Disabled = false
	end

	nukeClone.Sparks.Enabled = true
	centerEmitPoint.SparkleExplosion.Enabled = true

	TweenService:Create(nukeClone.Sparks, TweenInfo.new(45, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
		Rate = 0
	}):Play()

	TweenService:Create(centerEmitPoint.SparkleExplosion, TweenInfo.new(45, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
		Rate = 0
	}):Play()

	TweenService:Create(nukeClone.ChimeLoop, TweenInfo.new(55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Volume = 0,
		PlaybackSpeed = 0.75
	}):Play()

	if nukeClone:FindFirstChild("ApplauseLoop") then
		TweenService:Create(nukeClone.ApplauseLoop, TweenInfo.new(60, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Volume = 0
		}):Play()
	end

	TweenService:Create(nukeClone.CoinsLoop, TweenInfo.new(50, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Volume = 0,
		PlaybackSpeed = 1
	}):Play()

	wait(30)

	TweenService:Create(donationFrame.UIScale, TweenInfo.new(15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Scale = 0
	}):Play()

	wait(15)
	donationFrame.Parent.Enabled = false

	wait(30)
	cameraShaker:Stop()
	end)

	cleanup()
	WorldEffectFlight:finish(gen)
	if not ok and tostring(err) ~= "WorldEffectAborted" then
		warn("LocalNuke effect failed:", err)
	end
end

-- Main function that checks user settings
local function handleNukeEffect(donatorName, recipientName, donationAmount)
	if not DonationExperiencePrefs.shouldShowWorldEffect() then
		return
	end
	local DonationVfxClientGate = require(
		script.Parent.Parent.Parent.Parent.Utils.DonationVfxClientGate
	)
	if not DonationVfxClientGate.shouldPlayWorldEffect() then
		return
	end
	createNukeEffect(ReplicatedStorage.WorldEffects.Nuke, donatorName, recipientName, donationAmount)
end


local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
	or ReplicatedStorage:WaitForChild("Remotes", 30)
local DonationEffect = Remotes and Remotes:FindFirstChild("DonationEffect")
	or Remotes and Remotes:WaitForChild("DonationEffect", 30)
if not DonationEffect then
	warn("LocalNuke effect: DonationEffect remote not found")
	return
end
local donationEffectConn = DonationEffect.OnClientEvent:Connect(function(effectName, donatorName, recipientName, donationAmount)
	if effectName ~= "Nuke" then return end
	handleNukeEffect(donatorName, recipientName, donationAmount)
end)
script.Destroying:Connect(function()
	donationEffectConn:Disconnect()
end)
