-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local SoundAssetSanitizer = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.SoundAssetSanitizer)
local DonationExperiencePrefs = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DonationExperiencePrefs)
local WorldEffectFlight = require(script.Parent.Parent.Parent.Utils.WorldEffectFlight)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

-- Stage anchor from ClubKitConfig.Donation.NukeWorldPosition (fallback = legacy hardcode).
local DEFAULT_SPAWN_POSITION = Vector3.new(17, 0.5, -100)
local AERIAL_Y_OFFSET = 242.298 -- legacy BLACKHOLE_POSITION.Y - SPAWN.Y approx

local function resolveNukeWorldPosition(): Vector3
	local pos = (Config.Donation :: any).NUKE_WORLD_POSITION
	if typeof(pos) == "Vector3" then
		return pos
	end
	return DEFAULT_SPAWN_POSITION
end

local SPAWN_POSITION = resolveNukeWorldPosition()
local BLACKHOLE_POSITION = Vector3.new(SPAWN_POSITION.X, SPAWN_POSITION.Y + AERIAL_Y_OFFSET, SPAWN_POSITION.Z)

-- Helper function to add commas to numbers
local function addCommasToNumber(number)
	local text = tostring(number)
	while true do
		local newText, replacements = string.gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2")
		text = newText
		if replacements == 0 then
			break
		end
	end
	return text
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

-- Helper function for tweening
local function createTween(object, duration, properties)
	TweenService:Create(object, TweenInfo.new(duration, Enum.EasingStyle.Quint), properties):Play()
end

-- Main Black Hole effect function
local function createBlackHoleEffect(donatorName, recipientName, donationAmount)
	-- Abort any prior world VFX first so Lighting restore runs before we snapshot.
	local gen = WorldEffectFlight:begin()
	local savedLighting = {
		ClockTime = Lighting.ClockTime,
		Brightness = Lighting.Brightness,
		FogColor = Lighting.FogColor,
	}

	local cleaned = false
	local meteorShowerActive = true
	local effectModel = nil
	local floorAmbianceClone = nil
	local airAmbiance = nil
	local soundsFolder = nil
	local colorCorrection = nil
	local bloomEffect = nil
	local blackHoleOrb = nil
	local heavenBallClone = nil
	local impactVisuals = nil
	local ambianceSound = nil
	local whiteHole1, whiteHole2, whiteHole3, whiteHole4 = nil, nil, nil, nil
	local tickSound = nil

	local function safeDestroy(inst)
		if inst and typeof(inst) == "Instance" and inst.Parent then
			inst:Destroy()
		end
	end

	local function cleanup()
		if cleaned then
			return
		end
		cleaned = true
		meteorShowerActive = false
		safeDestroy(tickSound)
		safeDestroy(impactVisuals)
		safeDestroy(heavenBallClone)
		safeDestroy(blackHoleOrb)
		safeDestroy(whiteHole1)
		safeDestroy(whiteHole2)
		safeDestroy(whiteHole3)
		safeDestroy(whiteHole4)
		safeDestroy(ambianceSound)
		safeDestroy(soundsFolder)
		safeDestroy(floorAmbianceClone)
		safeDestroy(airAmbiance)
		safeDestroy(colorCorrection)
		safeDestroy(bloomEffect)
		safeDestroy(effectModel)
		Lighting.Brightness = savedLighting.Brightness
		Lighting.ClockTime = savedLighting.ClockTime
		Lighting.FogColor = savedLighting.FogColor
	end
	WorldEffectFlight:setCleanup(gen, cleanup)

	local function wait(seconds)
		if not WorldEffectFlight:wait(gen, seconds) then
			error("WorldEffectAborted")
		end
	end

	local ok, err = pcall(function()
	-- Clone effect model
	effectModel = ReplicatedStorage.WorldEffects.BlackHole:Clone()
	SoundAssetSanitizer.removeBlockedSounds(effectModel)

	-- Clone objects before destroying the Objects folder
	local npcModel = effectModel.Objects.NPC:Clone()
	local floorAmbiance = effectModel.Objects.FloorAmbiance:Clone()
	local ambiance = effectModel.Objects.Ambiance:Clone()
	impactVisuals = effectModel.Objects.ImpactVisuals:Clone()
	local heavenBall = effectModel.Objects.Heavenball:Clone()
	whiteHole1 = effectModel.Objects.Whitehole:Clone()
	whiteHole2 = effectModel.Objects.Whitehole2:Clone()
	whiteHole3 = effectModel.Objects.Whitehole3:Clone()
	whiteHole4 = effectModel.Objects.Whitehole4:Clone()
	local orb = effectModel.Objects.Orb:Clone()
	local meteorTemplate = effectModel.Objects.Meteor:Clone()
	-- Unused clone — destroy immediately so it cannot leak if Objects linger.
	npcModel:Destroy()

	-- Setup floor ambiance
	floorAmbianceClone = floorAmbiance:Clone()
	floorAmbianceClone.Position = SPAWN_POSITION + Vector3.new(0, -0.5, 0)
	floorAmbianceClone.Parent = workspace

	-- Setup air ambiance
	airAmbiance = ambiance:Clone()
	airAmbiance.Position = SPAWN_POSITION
	airAmbiance.Size = Vector3.new(1000, 1000, 1000)
	local randomRotation = math.random(-180, 180)
	airAmbiance.CFrame = airAmbiance.CFrame:ToWorldSpace(CFrame.Angles(0, math.rad(randomRotation), 0.5235987755982988))
	airAmbiance.Position = airAmbiance.Position + airAmbiance.CFrame.UpVector * 600
	airAmbiance.Parent = workspace

	-- Animate floor
	TweenService:Create(floorAmbianceClone, TweenInfo.new(10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(2048, 1, 2048)
	}):Play()

	-- Setup sounds
	soundsFolder = effectModel.Sounds:Clone()
	SoundAssetSanitizer.removeBlockedSounds(soundsFolder)
	soundsFolder.Parent = workspace

	-- Setup camera shaker (disabled — no-op dummy)
	local CameraShaker = require(script.CameraShaker)
	local cameraShaker = {
		Start = function() end,
		Stop = function() end,
		ShakeSustain = function() end,
		ShakeOnce = function() end,
		StopSustained = function() end,
	}

	-- Create lighting effects
	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Enabled = true
	colorCorrection.Name = "EventColorCorrection"
	colorCorrection.Parent = Lighting

	bloomEffect = Instance.new("BloomEffect")
	bloomEffect.Enabled = true
	bloomEffect.Name = "SmiteBloom"
	bloomEffect.Size = 20
	bloomEffect.Threshold = 0.1
	bloomEffect.Intensity = -1
	bloomEffect.Parent = Lighting

	-- Apply color correction
	TweenService:Create(colorCorrection, TweenInfo.new(10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TintColor = Color3.fromRGB(255, 128, 255),
		Brightness = 0.25,
		Saturation = 0.1,
		Contrast = 0.25
	}):Play()

	-- Create black hole orb
	blackHoleOrb = orb:Clone()
	blackHoleOrb.Parent = workspace
	blackHoleOrb.Position = BLACKHOLE_POSITION

	cameraShaker:Start()
	cameraShaker:ShakeSustain(CameraShaker.Presets.Earthquake)

	-- Play ambient sounds
	ambianceSound = soundsFolder.Ambiance:Clone()
	ambianceSound.Parent = workspace
	ambianceSound:Play()

	-- Enable black hole particles
	for _, effect in pairs(blackHoleOrb.Attachment:GetChildren()) do
		if effect:IsA("ParticleEmitter") then
			scaleParticleEffect(effect, 1.75)
			effect.Enabled = true
		end
	end

	-- Enable floor particles
	for _, effect in pairs(floorAmbianceClone:GetChildren()) do
		if effect:IsA("ParticleEmitter") then
			scaleParticleEffect(effect, 1.75)
			effect.Enabled = true
		end
	end

	-- Enable air particles
	for _, effect in pairs(airAmbiance:GetChildren()) do
		if effect:IsA("ParticleEmitter") then
			scaleParticleEffect(effect, 2.5)
			effect.Enabled = true
		end
	end

	-- Meteor shower system
	local meteorStartTime = tick()
	local meteorSpawnDelay = 0.5

	spawn(function()
		while meteorShowerActive and WorldEffectFlight:isActive(gen) do
			if tick() - meteorStartTime > 90 then
				break
			end
			if not WorldEffectFlight:wait(gen, meteorSpawnDelay) then
				break
			end
			spawn(function()
				if not WorldEffectFlight:isActive(gen) then
					return
				end
				local sizeMultiplier = math.random(100, 400) / 100
				local fallDuration = math.random(250, 400) / 100
				local fallHeight = math.random(500, 750)

				local meteor = meteorTemplate:Clone()
				meteor.Parent = workspace
				meteor.Transparency = 1
				meteor.Position = SPAWN_POSITION + Vector3.new(math.random(-750, 750), 0, math.random(-750, 750))
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
				TweenService:Create(meteor, TweenInfo.new(fallDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
					Position = meteor.Position + meteor.CFrame.UpVector * -fallHeight,
					Orientation = Vector3.new(math.random(-180, 180) * 3, math.random(-180, 180) * 3, math.random(-180, 180) * 3)
				}):Play()

				TweenService:Create(meteor, TweenInfo.new(fallDuration * 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = 0
				}):Play()

				TweenService:Create(meteor.Whoosh, TweenInfo.new(fallDuration * 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Volume = 1
				}):Play()

				if not WorldEffectFlight:wait(gen, fallDuration) then
					meteor:Destroy()
					return
				end

				-- Meteor impact
				meteor.Transparency = 1
				meteor.Orientation = Vector3.new(0, 0, 0)
				meteor.Glow.Range = meteor.Glow.Range * 1.5
				meteor.Glow.Brightness = meteor.Glow.Brightness * 3

				TweenService:Create(meteor.Glow, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
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

				if not WorldEffectFlight:wait(gen, 3) then
					meteor:Destroy()
					return
				end
				meteor:Destroy()
			end)
		end
	end)

	-- Portal opening sequence
	spawn(function()
		soundsFolder.Summon:Play()
		soundsFolder.Earthquake:Play()
		blackHoleOrb.PortalAmbiance.Playing = true
		blackHoleOrb.PortalOpen1:Play()
		blackHoleOrb.PortalOpen2:Play()

		TweenService:Create(blackHoleOrb.PortalAmbiance, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Volume = 1.5,
			PlaybackSpeed = 1.25
		}):Play()

		TweenService:Create(blackHoleOrb, TweenInfo.new(7, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Size = Vector3.new(50, 50, 50)
		}):Play()

		soundsFolder.CrumbleLoop.Playing = true
		TweenService:Create(soundsFolder.CrumbleLoop, TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Volume = 0.5
		}):Play()

		soundsFolder.FireLoop.Playing = true
		TweenService:Create(soundsFolder.FireLoop, TweenInfo.new(5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Volume = 0.5,
			PlaybackSpeed = 1
		}):Play()

		cameraShaker:ShakeSustain(CameraShaker.Presets.Earthquake)

		wait(7)

		TweenService:Create(soundsFolder.CrumbleLoop, TweenInfo.new(10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Volume = 0
		}):Play()

		cameraShaker:StopSustained(6)

		TweenService:Create(blackHoleOrb.PortalAmbiance, TweenInfo.new(5, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
			Volume = 0,
			PlaybackSpeed = 0
		}):Play()
	end)

	-- Main sequence
	wait(math.random(14, 19))

	-- Spawn white holes
	whiteHole1.Parent = workspace
	whiteHole2.Parent = workspace
	whiteHole3.Parent = workspace
	whiteHole4.Parent = workspace

	-- Setup heaven ball
	heavenBallClone = heavenBall:Clone()
	local chargeSound = soundsFolder.Charge_2:Clone()
	chargeSound.Parent = heavenBallClone
	heavenBallClone.Parent = workspace
	chargeSound:Play()

	wait(1.25)

	-- Heaven ball appearance
	createTween(heavenBallClone, 6, {Transparency = 0})

	local endingSound = soundsFolder.ChargeEndSound:Clone()
	endingSound.Parent = heavenBallClone
	endingSound:Play()

	wait(1.5)

	-- Cleanup white holes
	whiteHole1:Destroy()
	whiteHole2:Destroy()
	whiteHole3:Destroy()
	whiteHole4:Destroy()
	chargeSound:Destroy()
	endingSound:Destroy()

	soundsFolder.Twinkle:Play()

	TweenService:Create(heavenBallClone, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Position = BLACKHOLE_POSITION
	}):Play()

	wait(1.25)

	-- Heaven ball expansion
	TweenService:Create(heavenBallClone, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Size = Vector3.new(50, 50, 50)
	}):Play()

	soundsFolder.CrumbleLoop.Playing = true
	TweenService:Create(soundsFolder.CrumbleLoop, TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Volume = 0.5
	}):Play()

	soundsFolder.Sparkle:Play()
	cameraShaker:ShakeSustain(CameraShaker.Presets.Earthquake)

	wait(3)

	-- Time distortion effect
	tickSound = soundsFolder.Tick:Clone()
	tickSound.Parent = workspace
	tickSound.Playing = true

	for i = 1, 8 do
		Lighting.ClockTime = 10
		Lighting.FogColor = Color3.fromRGB(144, 228, 248)
		wait(1)
		Lighting.ClockTime = 0
		Lighting.FogColor = Color3.fromRGB(0, 0, 0)
		wait(1)
	end

	tickSound:Stop()
	tickSound:Destroy()
	tickSound = nil
	wait(5)

	-- Final sequence
	cameraShaker:StopSustained(6)

	TweenService:Create(soundsFolder.CrumbleLoop, TweenInfo.new(10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Volume = 0
	}):Play()

	wait(1)

	TweenService:Create(blackHoleOrb, TweenInfo.new(10, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Size = Vector3.new(75, 75, 75)
	}):Play()

	TweenService:Create(heavenBallClone, TweenInfo.new(10, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Size = Vector3.new(74, 74, 74)
	}):Play()

	-- Scale black hole particles
	for _, effect in pairs(blackHoleOrb.Attachment:GetChildren()) do
		if effect:IsA("ParticleEmitter") then
			scaleParticleEffect(effect, 2)
		end
	end

	wait(10)

	-- Disable particles
	for _, effect in pairs(blackHoleOrb.Attachment:GetChildren()) do
		if effect:IsA("ParticleEmitter") then
			effect.Rate = 0
		end
	end

	cameraShaker:ShakeOnce(8, 20, 1, 6)

	-- Beam effects
	local beams = {"FlameEffect1", "FlameEffect2", "FlameEffect3", "FlameEffect4", "FlameEffect5",
		"FlameEffect6", "FlameEffect7", "FlameEffect8", "FlameEffect9", "FlameEffect10",
		"FlameEffect11", "FlameEffect12"}

	for _, beamName in pairs(beams) do
		TweenService:Create(blackHoleOrb.Beams[beamName], TweenInfo.new(1.7, Enum.EasingStyle.Linear), {
			Brightness = 1.57
		}):Play()
	end

	TweenService:Create(Lighting, TweenInfo.new(1.7), {Brightness = 5}):Play()

	TweenService:Create(blackHoleOrb, TweenInfo.new(1.7, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
		Position = SPAWN_POSITION
	}):Play()

	TweenService:Create(heavenBallClone, TweenInfo.new(1.7, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
		Position = SPAWN_POSITION
	}):Play()

	-- Enable flame effects
	blackHoleOrb.FlameEffect1_0.BrightFlare.Enabled = true
	blackHoleOrb.Flames.Enabled = true
	blackHoleOrb.FlameEffect1_0.FlameRing.Enabled = true
	blackHoleOrb.FlameEffect1_0.Flames1.Enabled = true
	blackHoleOrb.FlameEffect1_0.Flames2.Enabled = true
	blackHoleOrb.FlameEffect1_0.Flames3.Enabled = true

	soundsFolder.Drop1:Play()
	soundsFolder.Drop2:Play()
	blackHoleOrb.LaunchSound:Play()

	wait(1.7)

	-- Final explosion
	soundsFolder.ExplosionSound:Play()
	soundsFolder.Sparkle:Stop()
	ambianceSound:Destroy()

	bloomEffect.Intensity = 0.75
	bloomEffect.Threshold = 0.05
	colorCorrection.Contrast = 0

	TweenService:Create(bloomEffect, TweenInfo.new(10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Intensity = -0.9,
		Threshold = 0.1
	}):Play()

	TweenService:Create(colorCorrection, TweenInfo.new(10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Contrast = 0.25
	}):Play()

	cameraShaker:ShakeOnce(12, 4, 1, 6)

	blackHoleOrb.SelectionSphere:Destroy()

	-- Disable flame effects
	blackHoleOrb.FlameEffect1_0.BrightFlare.Enabled = false
	blackHoleOrb.Flames.Enabled = false
	blackHoleOrb.FlameEffect1_0.FlameRing.Enabled = false
	blackHoleOrb.FlameEffect1_0.Flames1.Enabled = false
	blackHoleOrb.FlameEffect1_0.Flames2.Enabled = false
	blackHoleOrb.FlameEffect1_0.Flames3.Enabled = false

	-- Reset beam brightness
	for _, beamName in pairs(beams) do
		TweenService:Create(blackHoleOrb.Beams[beamName], TweenInfo.new(0.01, Enum.EasingStyle.Linear), {
			Brightness = 0
		}):Play()
	end

	TweenService:Create(Lighting, TweenInfo.new(0.2), {Brightness = 150}):Play()
	TweenService:Create(colorCorrection, TweenInfo.new(0.05), {Brightness = 1.2}):Play()

	wait(0.05)

	TweenService:Create(colorCorrection, TweenInfo.new(3), {Brightness = 0.05}):Play()
	TweenService:Create(Lighting, TweenInfo.new(7), {Brightness = 2.66}):Play()

	-- Create impact visuals
	SoundAssetSanitizer.removeBlockedSounds(impactVisuals)
	impactVisuals.Parent = workspace
	impactVisuals.Anchored = true  -- tambah ini
	impactVisuals.Position = SPAWN_POSITION

	TweenService:Create(impactVisuals, TweenInfo.new(30), {
		Position = Vector3.new(SPAWN_POSITION.X, 500, SPAWN_POSITION.Z)
	}):Play()

	if impactVisuals:FindFirstChild("ApplauseLoop") then impactVisuals.ApplauseLoop:Play() end
	impactVisuals.CoinsLoop:Play()
	impactVisuals.ChimeLoop:Play()

	-- Emit impact particles
	impactVisuals.EmitPoint.Impact_Spark1:Emit(45)
	impactVisuals.EmitPoint.Impact_Spark2:Emit(75)
	impactVisuals.EmitPoint.Impact_Spark3:Emit(35)
	impactVisuals.EmitPoint.Explosion_Glow:Emit(25)
	impactVisuals.EmitPoint.Explosion_Rays:Emit(45)
	impactVisuals.EmitPoint.Explosion_Ring:Emit(5)
	impactVisuals.EmitPoint.Explosion_Flare:Emit(50)
	impactVisuals.EmitPoint.Explosion_ThinRays:Emit(35)
	impactVisuals.EmitPoint.Explosion_Shockwave:Emit(15)

	-- Setup donation GUI
	local donationFrame = impactVisuals.BillboardGuiAnimation.Frame

	-- Function to preserve the exact case of the username
	local function preserveExactCase(username)
		return username
	end

	donationFrame.RobuxLogo.Size = UDim2.fromScale(0, 0)
	donationFrame.Star.Size = UDim2.fromScale(0, 0)
	donationFrame.BottomText.Size = UDim2.fromScale(0, 0)
	donationFrame.MiddleText.Size = UDim2.fromScale(0, 0)
	donationFrame.TopText.Size = UDim2.fromScale(0, 0)
	donationFrame.RobuxLogo.Rotation = -180
	donationFrame.Star.Rotation = 0
	donationFrame.Star.ImageTransparency = 0.9
	donationFrame.TopText.Text = "@" .. preserveExactCase(donatorName) .. " DONATED"
	donationFrame.MiddleText.Text = addCommasToNumber(donationAmount)
	donationFrame.BottomText.Text = "TO @" .. preserveExactCase(recipientName)

	TweenService:Create(donationFrame.RobuxLogo, TweenInfo.new(15, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1, 1)
	}):Play()

	TweenService:Create(donationFrame.RobuxLogo, TweenInfo.new(10, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
		Rotation = 0
	}):Play()

	TweenService:Create(donationFrame.Star, TweenInfo.new(10), {Rotation = 360}):Play()
	TweenService:Create(donationFrame.Star, TweenInfo.new(10), {ImageTransparency = 1}):Play()

	wait(0.25)
	TweenService:Create(donationFrame.TopText, TweenInfo.new(5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1.5, 0.1)
	}):Play()

	wait(0.25)
	TweenService:Create(donationFrame.MiddleText, TweenInfo.new(5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1, 1)
	}):Play()

	wait(0.25)
	TweenService:Create(donationFrame.BottomText, TweenInfo.new(5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1.5, 0.1)
	}):Play()

	TweenService:Create(blackHoleOrb, TweenInfo.new(0.4, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
		Transparency = 1
	}):Play()

	TweenService:Create(heavenBallClone, TweenInfo.new(0.4, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
		Transparency = 1
	}):Play()

	impactVisuals.EmitPoint.Sparks.Enabled = true
	impactVisuals.EmitPoint.SparkleExplosion.Enabled = true

	wait(5)

	-- Fade out sounds
	TweenService:Create(impactVisuals.ChimeLoop, TweenInfo.new(60), {Volume = 0}):Play()
	if impactVisuals:FindFirstChild("ApplauseLoop") then
		TweenService:Create(impactVisuals.ApplauseLoop, TweenInfo.new(60), {Volume = 0}):Play()
	end
	TweenService:Create(impactVisuals.CoinsLoop, TweenInfo.new(30), {Volume = 0}):Play()

	heavenBallClone:Destroy()

	wait(5)
	blackHoleOrb:Destroy()

	TweenService:Create(donationFrame, TweenInfo.new(14, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
		Size = UDim2.fromScale(0, 0)
	}):Play()

	for _, effect in pairs(impactVisuals.EmitPoint:GetChildren()) do
		if effect:IsA("ParticleEmitter") then
			TweenService:Create(effect, TweenInfo.new(14), {Rate = 0}):Play()
		end
	end

	wait(5)
	donationFrame:Destroy()

	wait(10)
	impactVisuals.CoinsLoop:Stop()
	if impactVisuals:FindFirstChild("ApplauseLoop") then impactVisuals.ApplauseLoop:Stop() end
	impactVisuals.ChimeLoop:Stop()

	meteorShowerActive = false

	TweenService:Create(soundsFolder.FireLoop, TweenInfo.new(30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Volume = 0,
		PlaybackSpeed = 0.5
	}):Play()

	-- Fade out floor and air particles
	for _, effect in pairs(floorAmbianceClone:GetChildren()) do
		if effect:IsA("ParticleEmitter") then
			TweenService:Create(effect, TweenInfo.new(60, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Rate = 0
			}):Play()
		end
	end

	for _, effect in pairs(airAmbiance:GetChildren()) do
		if effect:IsA("ParticleEmitter") then
			TweenService:Create(effect, TweenInfo.new(30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Rate = 0
			}):Play()
		end
	end

	-- Reset lighting
	TweenService:Create(colorCorrection, TweenInfo.new(30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TintColor = Color3.fromRGB(255, 255, 255),
		Brightness = 0,
		Saturation = 0,
		Contrast = 0
	}):Play()

	TweenService:Create(bloomEffect, TweenInfo.new(30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Intensity = -1
	}):Play()

	wait(10)

	colorCorrection:Destroy()
	colorCorrection = nil
	bloomEffect:Destroy()
	bloomEffect = nil
	soundsFolder:Destroy()
	soundsFolder = nil

	floorAmbianceClone.Size = Vector3.new(0, 0, 0)
	airAmbiance.Size = Vector3.new(0, 0, 0)

	wait(5)

	-- Restore place lighting (effect used to hardcode ClockTime=14 and left the map stuck daytime).
	Lighting.Brightness = savedLighting.Brightness
	Lighting.ClockTime = savedLighting.ClockTime
	Lighting.FogColor = savedLighting.FogColor

	floorAmbianceClone:Destroy()
	floorAmbianceClone = nil
	airAmbiance:Destroy()
	airAmbiance = nil
	impactVisuals:Destroy()
	impactVisuals = nil
	end)

	cleanup()
	WorldEffectFlight:finish(gen)
	if not ok and tostring(err) ~= "WorldEffectAborted" then
		warn("BlackHole effect failed:", err)
	end
end


-- Connect to JPass event
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
	or ReplicatedStorage:WaitForChild("Remotes", 30)
local DonationEffect = Remotes and Remotes:FindFirstChild("DonationEffect")
	or Remotes and Remotes:WaitForChild("DonationEffect", 30)
if not DonationEffect then
	warn("BlackHole effect: DonationEffect remote not found")
	return
end
local donationEffectConn = DonationEffect.OnClientEvent:Connect(function(effectName, donatorName, recipientName, donationAmount)
	if effectName ~= "BlackHole" then return end
	if not DonationExperiencePrefs.shouldShowWorldEffect() then
		return
	end
	createBlackHoleEffect(donatorName, recipientName, donationAmount)
end)
script.Destroying:Connect(function()
	donationEffectConn:Disconnect()
end)
