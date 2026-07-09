wait(5)

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local SoundAssetSanitizer = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.SoundAssetSanitizer)
local DonationExperiencePrefs = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DonationExperiencePrefs)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local HttpApiCounter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.HttpApiCounter)
local ClientHttpApi = require(script.Parent.Parent.Parent.Utils.ClientHttpApi)

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

-- Camera shaker module
local CameraShaker = require(script.CameraShaker)

-- Giant spawn position
local GIANT_SPAWN_POSITION = Vector3.new(17.124, 242.798, 44.581)

-- Function to apply giant appearance to character
local function applyGiantAppearance(userId, character)
	-- HTTP API telemetry counter (quota-efficiency-pass-2026-06, Phase 0).
	-- Only fire when wrapper disabled (when enabled, wrapper's internal counter handles it).
	if (not (Config.ClientHttpApi and Config.ClientHttpApi.ENABLED)) and Config.HttpApi and Config.HttpApi.COUNTERS_ENABLED then
		HttpApiCounter.record("blossom_hd_total")
	end
	local humanoidDescription = ClientHttpApi.getHumanoidDescriptionFromUserIdAsync(userId)

	-- Scale up the character massively
	humanoidDescription.DepthScale = humanoidDescription.DepthScale * 53
	humanoidDescription.HeadScale = humanoidDescription.HeadScale * 53
	humanoidDescription.HeightScale = humanoidDescription.HeightScale * 53
	humanoidDescription.WidthScale = humanoidDescription.WidthScale * 53

	character.Humanoid:ApplyDescription(humanoidDescription)

	-- Make all parts transparent except HumanoidRootPart
	for _, part in pairs(character:GetDescendants()) do
		if (part:IsA("BasePart") or part:IsA("Decal")) and part.Name ~= "HumanoidRootPart" then
			part.Transparency = 1
		end
	end
end

-- Random rotation for effects
local randomRotation = math.random(-180, 180)

-- Main donation effect function
local function createDonationEffect(donorName, recipientName, donationAmount, donorUserId)
	-- Clone the main effect model
	local effectModel = ReplicatedStorage.WorldEffects.Smite4:Clone()
	SoundAssetSanitizer.removeBlockedSounds(effectModel)
	local diamondHammer = effectModel.DiamondHammer

	-- Make most parts transparent initially
	for _, part in pairs(effectModel:GetDescendants()) do
		if (part:IsA("BasePart") or part:IsA("Decal")) and
			part.Name ~= "HumanoidRootPart" and
			(not part:IsDescendantOf(diamondHammer) or not part:IsDescendantOf(effectModel.Objects)) then
			part.Transparency = 1
		end
	end

	-- Scale hammer effects
	scaleParticleEffect(diamondHammer.Handle.MainDiamondCenter.Shockwave, 60)
	scaleParticleEffect(diamondHammer.Handle.MainDiamondCenter.ChargeGlow, 50)
	scaleParticleEffect(diamondHammer.Handle.MainDiamondCenter.ChargeRays, 50)

	-- Configure hammer appearance
	diamondHammer.Handle.Transparency = 1
	diamondHammer.Handle.Diamonds.Transparency = 1
	diamondHammer.Handle.CanCollide = false

	effectModel.Parent = workspace
	scaleParticleEffect(diamondHammer.Handle.BaseFrontOffset.Shockwave, 10)

	-- Clone effect objects
	local meteorTemplate = effectModel.Objects.Meteor:Clone()
	local floorAmbiance = effectModel.Objects.FloorAmbiance:Clone()
	local ambiance = effectModel.Objects.Ambiance:Clone()
	local impactVisuals = effectModel.Objects.ImpactVisuals:Clone()
	local portalTemplate = effectModel.Objects.Portal:Clone()

	effectModel.Objects:Destroy()

	-- Move sounds to workspace
	local soundsFolder = effectModel.Sounds
	soundsFolder.Parent = workspace
	soundsFolder.Name = "1MDonationEffect_Sounds"

	-- Load animation
	local giantAnimation = effectModel.Humanoid:LoadAnimation(effectModel.Animations.Giant_MainAnimation)

	-- Create lighting effects
	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Enabled = true
	colorCorrection.Name = "SmiteColorCorrection"
	colorCorrection.Parent = game.Lighting

	local bloomEffect = Instance.new("BloomEffect")
	bloomEffect.Enabled = true
	bloomEffect.Name = "SmiteBloom"
	bloomEffect.Size = 20
	bloomEffect.Threshold = 0.1
	bloomEffect.Intensity = -1
	bloomEffect.Parent = game.Lighting

	-- Create camera shaker (disabled — no-op dummy)
	local cameraShaker = {
		Start = function() end,
		Stop = function() end,
		ShakeSustain = function() end,
		ShakeOnce = function() end,
		StopSustained = function() end,
	}

	-- Position the giant
	effectModel.PrimaryPart = effectModel.FloorLevel
	effectModel:SetPrimaryPartCFrame(CFrame.new(GIANT_SPAWN_POSITION.X, GIANT_SPAWN_POSITION.Y, GIANT_SPAWN_POSITION.Z))
	effectModel:SetPrimaryPartCFrame(effectModel.FloorLevel.CFrame:ToWorldSpace(CFrame.Angles(0, math.rad(math.random(-180, 180)), 0)))
	effectModel:SetPrimaryPartCFrame(effectModel.FloorLevel.CFrame:ToWorldSpace(CFrame.new(25, 0, 365)))
	effectModel.PrimaryPart = effectModel.HumanoidRootPart

	-- Create portal effect
	local portal = portalTemplate:Clone()
	portalTemplate.PortalAmbiance.Volume = 0
	portalTemplate.PortalAmbiance.PlaybackSpeed = 0
	portal.CFrame = effectModel.FloorLevel.CFrame
	portal.Parent = workspace
	effectModel.FloorLevel:Destroy()

	-- Store eye attachments for later use
	local leftEyeAttachment = effectModel.Head.LeftEyeAttachment
	local rightEyeAttachment = effectModel.Head.RightEyeAttachment
	leftEyeAttachment.Parent = nil
	rightEyeAttachment.Parent = nil
	diamondHammer.Parent = nil

	-- Apply giant appearance with error handling
	local success, errorMessage = pcall(function()
		local userId = donorUserId

		-- If userId is missing, try to look it up from the name
		if not userId or typeof(userId) ~= "number" then
			local successId, resultId = pcall(function()
				-- HTTP API telemetry counter (quota-efficiency-pass-2026-06, Phase 0)
				if Config.HttpApi and Config.HttpApi.COUNTERS_ENABLED then
					HttpApiCounter.record("blossom_uid_total")
				end
				return game.Players:GetUserIdFromNameAsync(donorName)
			end)
			if successId then
				userId = resultId
			else
				error("Could not find UserId for name: " .. tostring(donorName))
			end
		end

		applyGiantAppearance(userId, effectModel)
		effectModel.Humanoid.BodyDepthScale.Value = 50
		effectModel.Humanoid.HeadScale.Value = 50
		effectModel.Humanoid.BodyHeightScale.Value = 50
		effectModel.Humanoid.BodyWidthScale.Value = 50
	end)

	if not success then
		warn("Unable to set giant's appearance to donator (" .. tostring(donorName) .. ")  (" .. tostring(errorMessage) .. ")")
	end

	-- Reattach hammer and eye effects
	diamondHammer.Parent = effectModel
	diamondHammer.Weld.Attachment0 = effectModel.RightHand.RightGripAttachment
	leftEyeAttachment.Parent = effectModel.Head
	rightEyeAttachment.Parent = effectModel.Head
	leftEyeAttachment.Position = Vector3.new(-6, 11, -32)
	rightEyeAttachment.Position = Vector3.new(6, 11, -32)

	-- Start portal effects
	soundsFolder.Summon:Play()
	portal.Transparency = 0
	portal.Sparks.Enabled = true
	portal.Appearance.Enabled = true

	-- Animate portal opening
	TweenService:Create(portal.Sparks, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0), {
		Rate = 150
	}):Play()

	TweenService:Create(portal.Appearance, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0), {
		Rate = 200
	}):Play()

	TweenService:Create(portal, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0), {
		Size = Vector3.new(400, 1, 400)
	}):Play()

	TweenService:Create(portal.OuterLightBeam, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0), {
		Width0 = 400,
		Width1 = 600
	}):Play()

	TweenService:Create(portal.InnerLightBeam, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0), {
		Width0 = 200,
		Width1 = 300
	}):Play()

	portal.PortalAmbiance.Playing = true
	portal.PortalOpen1:Play()
	portal.PortalOpen2:Play()

	TweenService:Create(portal.PortalAmbiance, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0), {
		Volume = 1.5,
		PlaybackSpeed = 1.25
	}):Play()

	-- Meteor shower variables
	local meteorShowerActive = true
	local meteorStartTime = tick()
	local meteorSpawnDelay = 0.5

	-- Start meteor shower
	spawn(function()
		while meteorShowerActive do
			if tick() - meteorStartTime > 90 then
				break
			end
			wait(meteorSpawnDelay)
			spawn(function()
				local sizeMultiplier = math.random(100, 400) / 100
				local fallDuration = math.random(250, 400) / 100
				local fallHeight = math.random(500, 750)

				local meteor = meteorTemplate:Clone()
				meteor.Parent = workspace
				meteor.Transparency = 1
				meteor.Position = GIANT_SPAWN_POSITION + Vector3.new(math.random(-750, 750), 0, math.random(-750, 750))
				meteor.Size = meteor.Size * sizeMultiplier
				meteor.CFrame = meteor.CFrame:ToWorldSpace(CFrame.Angles(math.rad(math.random(-10, 10)), math.rad(randomRotation), 0.5235987755982988))
				meteor.Position = meteor.Position + meteor.CFrame.UpVector * fallHeight

				-- Configure meteor effects
				for _, effect in pairs(meteor:GetDescendants()) do
					if effect:IsA("ParticleEmitter") then
						scaleParticleEffect(effect, sizeMultiplier)
						if string.find(effect.Name, "Meteor_") then
							effect.Enabled = true
						end
					end
				end

				meteor.Glow.Range = meteor.Glow.Range * sizeMultiplier
				meteor.Glow.Enabled = true
				meteor.Trail0.Position = meteor.Trail0.Position * (sizeMultiplier / 2)
				meteor.Trail1.Position = meteor.Trail1.Position * (sizeMultiplier / 2)
				meteor.Trail.Enabled = true

				-- Configure meteor sounds
				meteor.Whoosh.Volume = 0
				meteor.Whoosh.TimePosition = math.random(0, meteor.Whoosh.TimeLength)
				meteor.Whoosh.PlaybackSpeed = 1.5 - sizeMultiplier * 0.15
				meteor.Impact.PlaybackSpeed = 1.5 - sizeMultiplier * 0.15
				meteor.Whoosh.Playing = true

				-- Animate meteor fall
				TweenService:Create(meteor, TweenInfo.new(fallDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.In, 0, false, 0), {
					Position = meteor.Position + meteor.CFrame.UpVector * -fallHeight,
					Orientation = Vector3.new(math.random(-180, 180) * 3, math.random(-180, 180) * 3, math.random(-180, 180) * 3)
				}):Play()

				TweenService:Create(meteor, TweenInfo.new(fallDuration * 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0), {
					Transparency = 0
				}):Play()

				TweenService:Create(meteor.Whoosh, TweenInfo.new(fallDuration * 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0), {
					Volume = 1
				}):Play()

				wait(fallDuration)

				-- Meteor impact
				meteor.Transparency = 1
				meteor.Orientation = Vector3.new(0, 0, 0)
				meteor.Glow.Range = meteor.Glow.Range * 1.5
				meteor.Glow.Brightness = meteor.Glow.Brightness * 3

				TweenService:Create(meteor.Glow, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0), {
					Brightness = 0,
					Range = meteor.Glow.Range / 2
				}):Play()

				-- Trigger explosion effects
				for _, effect in pairs(meteor:GetDescendants()) do
					if effect:IsA("ParticleEmitter") then
						if string.find(effect.Name, "Meteor_") then
							effect.Enabled = false
						end
						if string.find(effect.Name, "Explosion_") then
							effect:Emit(effect:GetAttribute("EmitCount"))
						end
					end
				end

				meteor.Trail.Enabled = false
				meteor.Whoosh.Playing = false
				meteor.Impact:Play()

				wait(3)
				meteor:Destroy()
			end)
		end
	end)

	-- Create floor and air ambiance
	local floorAmbianceClone = floorAmbiance:Clone()
	floorAmbianceClone.Position = GIANT_SPAWN_POSITION + Vector3.new(0, -0.5, 0)
	floorAmbianceClone.Parent = workspace

	TweenService:Create(floorAmbianceClone, TweenInfo.new(10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0), {
		Size = Vector3.new(2048, 1, 2048)
	}):Play()

	local airAmbiance = ambiance:Clone()
	airAmbiance.Position = GIANT_SPAWN_POSITION + Vector3.new(0, 0, 0)
	airAmbiance.Size = Vector3.new(1000, 1000, 1000)
	airAmbiance.CFrame = airAmbiance.CFrame:ToWorldSpace(CFrame.Angles(0, math.rad(randomRotation), 0.5235987755982988))
	airAmbiance.Position = airAmbiance.Position + airAmbiance.CFrame.UpVector * 600
	airAmbiance.Parent = workspace

	-- Start ambiance effects
	spawn(function()
		-- Floor ambiance
		for _, effect in pairs(floorAmbianceClone:GetChildren()) do
			if effect:IsA("ParticleEmitter") then
				scaleParticleEffect(effect, 1.25)
				effect.Enabled = true
			end
		end

		-- Air ambiance
		for _, effect in pairs(airAmbiance:GetChildren()) do
			if effect:IsA("ParticleEmitter") then
				scaleParticleEffect(effect, 1.75)
				effect.Enabled = true
			end
		end

		wait(30)

		-- Begin cleanup
		TweenService:Create(soundsFolder.FireLoop, TweenInfo.new(30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0), {
			Volume = 0,
			PlaybackSpeed = 0.5
		}):Play()

		meteorShowerActive = false

		-- Fade out floor effects
		for _, effect in pairs(floorAmbianceClone:GetChildren()) do
			if effect:IsA("ParticleEmitter") then
				TweenService:Create(effect, TweenInfo.new(60, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0), {
					Rate = 0
				}):Play()
			end
		end

		-- Fade out air effects
		for _, effect in pairs(airAmbiance:GetChildren()) do
			if effect:IsA("ParticleEmitter") then
				TweenService:Create(effect, TweenInfo.new(30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0), {
					Rate = 0
				}):Play()
			end
		end

		wait(20)
		floorAmbianceClone.Size = Vector3.new(0, 0, 0)
		airAmbiance.Size = Vector3.new(0, 0, 0)

		wait(20)
		floorAmbianceClone:Destroy()
		airAmbiance:Destroy()
	end)

	-- Apply lighting effects
	TweenService:Create(colorCorrection, TweenInfo.new(10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0), {
		TintColor = Color3.fromRGB(188, 163, 183),
		Brightness = 0.25,
		Saturation = 0.1,
		Contrast = 0.25
	}):Play()

	TweenService:Create(bloomEffect, TweenInfo.new(10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0), {
		Intensity = -0.85
	}):Play()

	-- Hammer flame effect function
	local function updateHammerFlameEffects(transparency)
		local transparencySequence = NumberSequence.new({
			NumberSequenceKeypoint.new(0, transparency),
			NumberSequenceKeypoint.new(1, 1)
		})

		for _, beam in pairs(diamondHammer.Effects.Beams:GetChildren()) do
			if beam:IsA("Beam") and string.find(beam.Name, "FlameEffect") then
				beam.Enabled = true
				beam.Transparency = transparencySequence
			end
		end
	end

	local hammerFlameConnection = effectModel.Values.Hammer_FlameEffectTransparency.Changed:Connect(updateHammerFlameEffects)
	updateHammerFlameEffects(1)

	-- Animation event handlers
	giantAnimation:GetMarkerReachedSignal("Eye lense flare"):Connect(function()
		soundsFolder.LenseFlareEyes:Play()
		effectModel.Head.LeftEyeAttachment.Flare.Enabled = true
		effectModel.Head.LeftEyeAttachment.FlareFlash:Emit(1)
		effectModel.Head.RightEyeAttachment.Flare.Enabled = true
		effectModel.Head.RightEyeAttachment.FlareFlash:Emit(1)
	end)

	giantAnimation:GetMarkerReachedSignal("HammerAppear"):Connect(function()
		diamondHammer.Handle.AppearSound.Playing = true
		diamondHammer.Handle.AppearSound.Volume = 0
		diamondHammer.Handle.AppearSound.PlaybackSpeed = 0.75

		TweenService:Create(diamondHammer.Handle.AppearSound, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true, 0), {
			Volume = 2
		}):Play()

		TweenService:Create(diamondHammer.Handle.AppearSound, TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0, false, 0), {
			PlaybackSpeed = 1.5
		}):Play()

		diamondHammer.Handle.HammerBaseOutline.Sparkles.Enabled = true
		diamondHammer.Handle.HammerBaseOutline.Appearance.Enabled = true
		diamondHammer.Handle.HammerHandleBase.Appearance.Enabled = true

		TweenService:Create(diamondHammer.Handle.HammerBaseOutline.Sparkles, TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0, false, 0), {
			Rate = 25
		}):Play()

		TweenService:Create(diamondHammer.Handle.HammerBaseOutline.Appearance, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true, 0), {
			Rate = 200
		}):Play()

		TweenService:Create(diamondHammer.Handle.HammerHandleBase.Appearance, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true, 0), {
			Rate = 100
		}):Play()

		TweenService:Create(diamondHammer.Handle, TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0, false, 0), {
			Transparency = 0
		}):Play()

		TweenService:Create(diamondHammer.Handle.Diamonds, TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0, false, 0), {
			Transparency = 0.1
		}):Play()
	end)

	giantAnimation:GetMarkerReachedSignal("ChargeSwing"):Connect(function()
		local handle = diamondHammer.Handle
		SoundAssetSanitizer.safePlay(handle:FindFirstChild("ChargeSound1"))
		SoundAssetSanitizer.safePlay(handle:FindFirstChild("ChargeSound2"))
		SoundAssetSanitizer.safePlay(handle:FindFirstChild("ChargeSound3"))
		SoundAssetSanitizer.safePlay(handle:FindFirstChild("MainChargeSound"))

		for _, attachment in pairs(diamondHammer.Handle:GetChildren()) do
			if attachment:IsA("Attachment") and string.find(attachment.Name, "DiamondCenter") then
				attachment.Flare.Enabled = true
			end
		end

		diamondHammer.Handle.MainDiamondCenter.Shockwave:Emit(1)
		diamondHammer.Handle.MainDiamondCenter.ChargeGlow.Enabled = true
		diamondHammer.Handle.MainDiamondCenter.ChargeRays.Enabled = true

		TweenService:Create(diamondHammer.Handle.MainDiamondCenter.ChargeRays, TweenInfo.new(4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0), {
			TimeScale = 1
		}):Play()

		TweenService:Create(diamondHammer.Handle.MainDiamondCenter.ChargeGlow, TweenInfo.new(4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0), {
			TimeScale = 1
		}):Play()
	end)

	giantAnimation:GetMarkerReachedSignal("SwingStart"):Connect(function()
		local handle = diamondHammer.Handle
		local mainChargeSound = handle:FindFirstChild("MainChargeSound")
		local baseCenter = handle:FindFirstChild("BaseCenter")
		local windSound = if baseCenter then baseCenter:FindFirstChild("Wind") else nil

		SoundAssetSanitizer.safePlay(handle:FindFirstChild("ChargeEndSound"))
		diamondHammer.Handle.MainDiamondCenter.Shockwave:Emit(3)
		diamondHammer.Handle.MainDiamondCenter.ChargeGlow.Enabled = false
		diamondHammer.Handle.MainDiamondCenter.ChargeRays.Enabled = false

		if mainChargeSound and mainChargeSound:IsA("Sound") then
			TweenService:Create(mainChargeSound, TweenInfo.new(4, Enum.EasingStyle.Quart, Enum.EasingDirection.In, 0, false, 0), {
				Volume = 0.25
			}):Play()
		end

		if windSound and windSound:IsA("Sound") then
			windSound.Volume = 0
			windSound.PlaybackSpeed = 0.5
			windSound.Playing = true

			TweenService:Create(windSound, TweenInfo.new(3.5, Enum.EasingStyle.Quart, Enum.EasingDirection.In, 0, false, 0), {
				Volume = 5,
				PlaybackSpeed = 2.5
			}):Play()
		end

		TweenService:Create(effectModel.Values.Hammer_FlameEffectTransparency, TweenInfo.new(4, Enum.EasingStyle.Quart, Enum.EasingDirection.In, 0, false, 0), {
			Value = 0
		}):Play()

		diamondHammer.Handle.HammerBase.Flames.Enabled = true
		diamondHammer.Handle.BaseFrontOffset.Shockwave.Enabled = true

		TweenService:Create(diamondHammer.Handle.HammerBase.Flames, TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.In, 0, false, 0), {
			Rate = 100
		}):Play()

		TweenService:Create(diamondHammer.Handle.BaseFrontOffset.Shockwave, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.In, 0, false, 0), {
			Rate = 15
		}):Play()

		for _, trail in pairs(diamondHammer.Effects.Trails:GetChildren()) do
			trail.Enabled = true
		end
	end)

	giantAnimation:GetMarkerReachedSignal("SwingEnd"):Connect(function()
		meteorSpawnDelay = 0.25
		SoundAssetSanitizer.safeStop(diamondHammer.Handle:FindFirstChild("MainChargeSound"))
		SoundAssetSanitizer.safePlay(soundsFolder:FindFirstChild("Rumble"))

		bloomEffect.Intensity = 0.75
		bloomEffect.Threshold = 0.05
		colorCorrection.Contrast = 0

		TweenService:Create(bloomEffect, TweenInfo.new(10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0), {
			Intensity = -0.9,
			Threshold = 0.1
		}):Play()

		TweenService:Create(colorCorrection, TweenInfo.new(10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0), {
			Contrast = 0.25
		}):Play()

		TweenService:Create(effectModel.Values.Hammer_FlameEffectTransparency, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0), {
			Value = 1
		}):Play()

		diamondHammer.Handle.BaseFrontOffset.Shockwave.Enabled = false

		TweenService:Create(diamondHammer.Handle.HammerBase.Flames, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0), {
			Rate = 0
		}):Play()

		for _, trail in pairs(diamondHammer.Effects.Trails:GetChildren()) do
			trail.Enabled = false
		end

		local windSound = diamondHammer.Handle:FindFirstChild("BaseCenter")
		windSound = if windSound then windSound:FindFirstChild("Wind") else nil
		if windSound and windSound:IsA("Sound") then
			windSound.Playing = false
		end

		for _, sound in pairs(diamondHammer.Handle.BaseCenter:GetChildren()) do
			if sound:IsA("Sound") and string.find(sound.Name, "Impact_") then
				sound:Play()
			end
		end

		for _, attachment in pairs(diamondHammer.Handle:GetChildren()) do
			if attachment:IsA("Attachment") and string.find(attachment.Name, "DiamondCenter") then
				attachment.Flare.Enabled = false
			end
		end

		cameraShaker:ShakeOnce(6, 6, 0.25, 5)

		local impactEffect = impactVisuals:Clone()
		impactEffect.Position = GIANT_SPAWN_POSITION
		impactEffect.Parent = workspace

		-- Scale impact effects
		scaleParticleEffect(impactEffect.EmitPoint.Impact_FractalBurst, 10)
		scaleParticleEffect(impactEffect.EmitPoint.Impact_RaysBurst, 25)
		scaleParticleEffect(impactEffect.EmitPoint.Impact_Shockwave, 30)
		scaleParticleEffect(impactEffect.EmitPoint.Impact_Spark1, 10)
		scaleParticleEffect(impactEffect.EmitPoint.Impact_Spark2, 10)
		scaleParticleEffect(impactEffect.EmitPoint.Impact_Spark3, 10)
		scaleParticleEffect(impactEffect.EmitPoint.Impact_SparkleExplosion, 10)
		scaleParticleEffect(impactEffect.EmitPoint.SparkleExplosion, 7.5)
		scaleParticleEffect(impactEffect.EmitPoint.Sparks, 5)

		for _, effect in pairs(impactEffect.EmitPoint:GetChildren()) do
			if effect:IsA("ParticleEmitter") and string.find(effect.Name, "Impact_") then
				effect:Emit(effect:GetAttribute("EmitCount"))
			end
		end

		-- Function to preserve the exact case of the username
		local function preserveExactCase(username)
			return username
		end

		if impactEffect:FindFirstChild("ApplauseLoop") then
			impactEffect.ApplauseLoop.Playing = true
		end
		impactEffect.ChimeLoop.Playing = true
		impactEffect.CoinsLoop.Playing = true

		local donationFrame = impactEffect.BillboardGuiAnimation.Frame
		donationFrame.TopText.Visible = true
		donationFrame.BottomText.Visible = true
		donationFrame.TopText.Text = "@" .. preserveExactCase(donorName) .. " DONATED"
		donationFrame.MiddleText.Text = "" .. tostring(donationAmount):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
		donationFrame.BottomText.Text = "TO @" .. preserveExactCase(recipientName)

		donationFrame.RobuxLogo.Size = UDim2.fromScale(0, 0)
		donationFrame.RobuxLogo.Rotation = -180
		donationFrame.Star.Size = UDim2.fromScale(0, 0)
		donationFrame.BottomText.Size = UDim2.fromScale(0, 0)
		donationFrame.BottomText.Position = UDim2.fromScale(0.5, 0.5)
		donationFrame.MiddleText.Size = UDim2.fromScale(0, 0)
		donationFrame.TopText.Position = UDim2.fromScale(0.5, 0.5)
		donationFrame.TopText.Size = UDim2.fromScale(0, 0)
		donationFrame.Parent.Enabled = true

		TweenService:Create(impactEffect, TweenInfo.new(20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0), {
			Position = GIANT_SPAWN_POSITION + Vector3.new(0, 400, 0)
		}):Play()

		TweenService:Create(donationFrame.RobuxLogo, TweenInfo.new(10, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out, 0, false, 0), {
			Size = UDim2.fromScale(1, 1)
		}):Play()

		TweenService:Create(donationFrame.RobuxLogo, TweenInfo.new(15, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out, 0, false, 0), {
			Rotation = 0
		}):Play()

		TweenService:Create(donationFrame.Star, TweenInfo.new(5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out, 0, false, 0), {
			Size = UDim2.fromScale(1.5, 1.5)
		}):Play()

		TweenService:Create(donationFrame.Star, TweenInfo.new(15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0), {
			Rotation = 360
		}):Play()

		TweenService:Create(donationFrame.BottomText, TweenInfo.new(5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out, 0, false, 0.6), {
			Size = UDim2.fromScale(1.5, 0.1),
			Position = UDim2.fromScale(0.5, 0.59)
		}):Play()

		TweenService:Create(donationFrame.MiddleText, TweenInfo.new(5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out, 0, false, 0.4), {
			Size = UDim2.fromScale(1, 1)
		}):Play()

		TweenService:Create(donationFrame.TopText, TweenInfo.new(5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out, 0, false, 0.2), {
			Size = UDim2.fromScale(1.5, 0.1),
			Position = UDim2.fromScale(0.5, 0.41)
		}):Play()

		TweenService:Create(donationFrame.Star, TweenInfo.new(10, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 5), {
			ImageTransparency = 1,
			ImageColor3 = Color3.fromRGB(0, 255, 255)
		}):Play()

		impactEffect.EmitPoint.Sparks.Enabled = true
		impactEffect.EmitPoint.SparkleExplosion.Enabled = true

		TweenService:Create(impactEffect.EmitPoint.Sparks, TweenInfo.new(45, Enum.EasingStyle.Quint, Enum.EasingDirection.In, 0, false, 0), {
			Rate = 0
		}):Play()

		TweenService:Create(impactEffect.EmitPoint.SparkleExplosion, TweenInfo.new(45, Enum.EasingStyle.Quint, Enum.EasingDirection.In, 0, false, 0), {
			Rate = 0
		}):Play()

		TweenService:Create(impactEffect.ChimeLoop, TweenInfo.new(55, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0), {
			Volume = 0,
			PlaybackSpeed = 0.75
		}):Play()

		if impactEffect:FindFirstChild("ApplauseLoop") then
			TweenService:Create(impactEffect.ApplauseLoop, TweenInfo.new(60, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0), {
				Volume = 0
			}):Play()
		end

		TweenService:Create(impactEffect.CoinsLoop, TweenInfo.new(50, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0), {
			Volume = 0,
			PlaybackSpeed = 1
		}):Play()

		wait(30)

		TweenService:Create(donationFrame.UIScale, TweenInfo.new(15, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0), {
			Scale = 0
		}):Play()

		wait(30)
		impactEffect:Destroy()
	end)

	giantAnimation:GetMarkerReachedSignal("Release"):Connect(function()
		effectModel.Head.LeftEyeAttachment.Flare.Enabled = false
		effectModel.Head.RightEyeAttachment.Flare.Enabled = false
	end)

	local appearanceParticle = effectModel.Particles.Appearance

	giantAnimation:GetMarkerReachedSignal("Fade"):Connect(function()
		local fadeSound = soundsFolder.GiantFade:Clone()
		fadeSound.Volume = 0
		fadeSound.PlaybackSpeed = 1.5
		fadeSound.Parent = effectModel.UpperTorso
		fadeSound.Playing = true

		TweenService:Create(fadeSound, TweenInfo.new(4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true, 0), {
			Volume = 3
		}):Play()

		TweenService:Create(fadeSound, TweenInfo.new(8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0, false, 0), {
			PlaybackSpeed = 0.5
		}):Play()

		for _, part in pairs(effectModel:GetDescendants()) do
			if (part:IsA("BasePart") or part:IsA("Decal")) and part.Name ~= "HumanoidRootPart" then
				if not part:IsA("Decal") then
					local appearanceEffect = appearanceParticle:Clone()
					appearanceEffect.Parent = part
					appearanceEffect.Enabled = true

					TweenService:Create(appearanceEffect, TweenInfo.new(5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true, 0), {
						Rate = 30
					}):Play()
				end

				TweenService:Create(part, TweenInfo.new(10, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0), {
					Transparency = 1
				}):Play()
			end
		end

		TweenService:Create(diamondHammer.Handle.HammerBaseOutline.Sparkles, TweenInfo.new(8, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0), {
			Rate = 0
		}):Play()

		TweenService:Create(diamondHammer.Handle.HammerBaseOutline.Appearance, TweenInfo.new(4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true, 0), {
			Rate = 200
		}):Play()

		TweenService:Create(diamondHammer.Handle.HammerHandleBase.Appearance, TweenInfo.new(4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true, 0), {
			Rate = 100
		}):Play()

		TweenService:Create(diamondHammer.Handle, TweenInfo.new(8, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0), {
			Transparency = 1
		}):Play()

		TweenService:Create(diamondHammer.Handle.Diamonds, TweenInfo.new(8, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0), {
			Transparency = 1
		}):Play()
	end)

	giantAnimation:GetMarkerReachedSignal("FadeEnd"):Connect(function()
		hammerFlameConnection:Disconnect()
		wait(5)
		effectModel:Destroy()
	end)

	wait(1)
	giantAnimation:Play()

	-- Start environmental effects
	spawn(function()
		soundsFolder.Earthquake:Play()
		soundsFolder.CrumbleLoop.Volume = 0
		soundsFolder.CrumbleLoop.Playing = true

		TweenService:Create(soundsFolder.CrumbleLoop, TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0), {
			Volume = 0.5
		}):Play()

		soundsFolder.FireLoop.Volume = 0
		soundsFolder.FireLoop.PlaybackSpeed = 0.5
		soundsFolder.FireLoop.Playing = true

		TweenService:Create(soundsFolder.FireLoop, TweenInfo.new(5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0), {
			Volume = 0.5,
			PlaybackSpeed = 1
		}):Play()

		cameraShaker:ShakeSustain(CameraShaker.Presets.Earthquake)

		for _, part in pairs(effectModel:GetDescendants()) do
			if (part:IsA("BasePart") or part:IsA("Decal")) and
				part.Name ~= "HumanoidRootPart" and
				not part:IsDescendantOf(diamondHammer) then
				TweenService:Create(part, TweenInfo.new(5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0), {
					Transparency = 0
				}):Play()
			end
		end

		wait(7)

		TweenService:Create(soundsFolder.CrumbleLoop, TweenInfo.new(10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0), {
			Volume = 0
		}):Play()

		cameraShaker:StopSustained(6)

		TweenService:Create(portal.Sparks, TweenInfo.new(5, Enum.EasingStyle.Sine, Enum.EasingDirection.In, 0, false, 0), {
			Rate = 0
		}):Play()

		TweenService:Create(portal.Appearance, TweenInfo.new(5, Enum.EasingStyle.Sine, Enum.EasingDirection.In, 0, false, 0), {
			Rate = 0
		}):Play()

		TweenService:Create(portal, TweenInfo.new(5, Enum.EasingStyle.Sine, Enum.EasingDirection.In, 0, false, 0), {
			Size = Vector3.new(0, 1, 0)
		}):Play()

		TweenService:Create(portal.OuterLightBeam, TweenInfo.new(5, Enum.EasingStyle.Sine, Enum.EasingDirection.In, 0, false, 0), {
			Width0 = 0,
			Width1 = 0
		}):Play()

		TweenService:Create(portal.InnerLightBeam, TweenInfo.new(5, Enum.EasingStyle.Sine, Enum.EasingDirection.In, 0, false, 0), {
			Width0 = 0,
			Width1 = 0
		}):Play()

		TweenService:Create(portal.PortalAmbiance, TweenInfo.new(5, Enum.EasingStyle.Sine, Enum.EasingDirection.In, 0, false, 0), {
			Volume = 0,
			PlaybackSpeed = 0
		}):Play()

		portal.PortalClose1.PlayOnRemove = true
		wait(5)
		portal:Destroy()
	end)

	wait(30)
	cameraShaker:Stop()

	TweenService:Create(colorCorrection, TweenInfo.new(30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0), {
		TintColor = Color3.fromRGB(255, 255, 255),
		Brightness = 0,
		Saturation = 0,
		Contrast = 0
	}):Play()

	TweenService:Create(bloomEffect, TweenInfo.new(30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0), {
		Intensity = -1
	}):Play()

	wait(30)
	colorCorrection:Destroy()
	bloomEffect:Destroy()
	soundsFolder:Destroy()
	hammerFlameConnection:Disconnect()
end


-- Connect the donation effect to the remote event
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
	or ReplicatedStorage:WaitForChild("Remotes", 30)
local DonationEffect = Remotes and Remotes:FindFirstChild("DonationEffect")
	or Remotes and Remotes:WaitForChild("DonationEffect", 30)
if not DonationEffect then
	warn("Blossom effect: DonationEffect remote not found")
	return
end
local donationEffectConn = DonationEffect.OnClientEvent:Connect(function(effectName, donorName, recipientName, donationAmount, userId)
	if effectName ~= "Smite4" then return end
	if not DonationExperiencePrefs.shouldShowWorldEffect() then
		return
	end
	pcall(createDonationEffect, donorName, recipientName, donationAmount, userId)
end)
script.Destroying:Connect(function()
	donationEffectConn:Disconnect()
end)
