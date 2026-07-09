-- Konfigurasi
local FIREWORK_COUNT = 140
local SPAWN_DELAY = 0.75
local EXPLOSION_DELAY_MIN = 0.75
local EXPLOSION_DELAY_MAX = 2.0
local FLARE_COUNT = 20
local FLARE_LIFETIME = 4
local FLARE_CLEANUP_DELAY = 3
local FIREWORK_CLEANUP_DELAY = 5

-- Referensi
-- Defensive guard: FireworksRocket template is a Studio-authored model
-- that lives as a child of this script. If the asset hasn't been migrated
-- into the place (or was stripped during cleanup), bail silently rather
-- than spam "X is not a valid member of LocalScript" every nuke.
local fireworkTemplate = script:FindFirstChild("FireworksRocket")
if not fireworkTemplate then
	return
end
fireworkTemplate = fireworkTemplate:Clone() :: BasePart
script.FireworksRocket:Destroy()
local spawnPosition = Vector3.new(0, 0, 0)
local spreadDistance =  500

-- Daftar sound ID untuk ledakan
local explosionSounds = {
	138080762, 269146157, 160248505, 242458749,
	160248459, 160248479, 160248493, 4583102108
}

-- Folder untuk organisasi (PENTING!)
local fireworksFolder = Instance.new("Folder")
fireworksFolder.Name = "ActiveFireworks"
fireworksFolder.Parent = workspace

-- Fungsi untuk membuat firework flare
local function createFlare(parentFirework, index)
	local flare = Instance.new("Part")
	flare.CastShadow = false
	flare.Color = parentFirework.Color
	flare.Material = Enum.Material.Neon
	flare.Name = "FireworkFlare"
	flare.Shape = Enum.PartType.Ball
	flare.Size = Vector3.new(3, 3, 3)
	flare.Transparency = 1
	flare.Anchored = true
	flare.CanCollide = false
	flare.TopSurface = Enum.SurfaceType.Smooth
	flare.BottomSurface = Enum.SurfaceType.Smooth

	-- Posisi dan arah
	flare.CFrame = parentFirework.CFrame * CFrame.Angles(math.rad(index * 18), 0, 0)
	flare.Position = parentFirework.Position
	flare.Velocity = flare.CFrame.LookVector * 50
	flare.Parent = fireworksFolder  -- Masukkan ke folder

	-- Attachment untuk trail
	local topAttachment = Instance.new("Attachment")
	topAttachment.Parent = flare
	topAttachment.Position = Vector3.new(0, flare.Size.Y * 0.5, 0)

	local bottomAttachment = Instance.new("Attachment")
	bottomAttachment.Parent = flare
	bottomAttachment.Position = Vector3.new(0, flare.Size.Y * -0.5, 0)

	-- Trail
	local trail = parentFirework.Trail:Clone()
	trail.Parent = flare
	trail.Attachment0 = topAttachment
	trail.Attachment1 = bottomAttachment
	trail.Lifetime = 2.5
	trail.Enabled = true

	-- BodyForce untuk gravitasi
	local bodyForce = Instance.new("BodyForce")
	bodyForce.Parent = flare
	bodyForce.Force = Vector3.new(0, flare:GetMass() * workspace.Gravity - 40, 0)

	flare.Anchored = false

	-- Particle effect
	local flareParticle = parentFirework.Particles.Flare:Clone()
	flareParticle.Parent = flare
	flareParticle.Enabled = true

	-- Cleanup yang lebih cepat
	task.delay(FLARE_LIFETIME, function()
		if flare and flare.Parent then
			trail.Enabled = false
			flareParticle.Enabled = false
			flare.Anchored = true

			task.wait(FLARE_CLEANUP_DELAY)
			flare:Destroy()
		end
	end)
end

-- Fungsi untuk meluncurkan firework
local function launchFirework()
	local firework = fireworkTemplate:Clone()

	-- Set warna random
	firework.Color = Color3.fromHSV(
		math.random(0, 100) / 100,
		math.random(75, 100) / 100,
		1
	)

	-- Set posisi spawn random
	firework.Position = spawnPosition + Vector3.new(
		math.random(-spreadDistance, spreadDistance),
		0,
		math.random(-spreadDistance, spreadDistance)
	)

	-- Set kecepatan
	firework.Velocity = Vector3.new(0, math.random(250, 400), 0)
	firework.Parent = fireworksFolder  -- Masukkan ke folder

	task.spawn(function()
		-- Terapkan warna ke semua particle effects
		local colorSequence = ColorSequence.new(firework.Color)
		firework.Trail.Color = colorSequence
		firework.Flares1.Color = colorSequence
		firework.Flares2.Color = colorSequence
		firework.Flares3.Color = colorSequence
		firework.SparkleExplosion.Color = colorSequence
		firework.EmitPoint.Flames.Color = colorSequence
		firework.Particles.Flare.Color = colorSequence
		firework.ExplosionFlare.Color = colorSequence
		firework.ExplosionFlare.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 200, 100),
			NumberSequenceKeypoint.new(1, 50, 25)
		})

		-- BodyForce untuk gravitasi
		firework.BodyForce.Force = Vector3.new(0, firework:GetMass() * workspace.Gravity, 0)

		-- Sound efek peluncuran
		local launchSound = Instance.new("Sound")
		launchSound.Name = "Launch"
		launchSound.Parent = firework
		launchSound.RollOffMinDistance = 20
		launchSound.PlaybackSpeed = math.random(90, 110) / 100
		launchSound.SoundId = "rbxassetid://947384308"
		launchSound.Volume = 1.15

		-- Sound efek ledakan
		local explosionSound = Instance.new("Sound")
		explosionSound.Name = "Bang"
		explosionSound.Parent = firework
		explosionSound.RollOffMinDistance = 50
		explosionSound.PlaybackSpeed = math.random(90, 110) / 100
		explosionSound.SoundId = "rbxassetid://" .. explosionSounds[math.random(1, #explosionSounds)]
		explosionSound.Volume = 3

		-- Mulai peluncuran
		firework.Anchored = false
		launchSound:Play()

		-- Tunggu sebelum meledak
		task.wait(math.random(EXPLOSION_DELAY_MIN * 100, EXPLOSION_DELAY_MAX * 100) / 100)

		-- Cek apakah firework masih ada
		if not firework or not firework.Parent then
			return
		end

		-- Ledakan
		firework.Transparency = 1
		firework.Anchored = true
		firework.CanCollide = true
		firework.Trail.Enabled = false
		firework.EmitPoint.Flames.Enabled = false
		firework.Orientation = Vector3.new(
			math.random(-180, 180),
			math.random(-180, 180),
			math.random(-180, 180)
		)

		-- Buat flares
		for i = 1, FLARE_COUNT do
			createFlare(firework, i)
		end

		-- Emit particles
		firework.Flares1:Emit(20)
		firework.Flares2:Emit(15)
		firework.Flares3:Emit(10)
		firework.ExplosionFlare:Emit(5)
		firework.SparkleExplosion:Emit(25)
		explosionSound:Play()

		-- Cleanup lebih cepat
		task.wait(FIREWORK_CLEANUP_DELAY)
		if firework and firework.Parent then
			firework:Destroy()
		end
	end)
end

-- Main loop
task.spawn(function()
	for i = 1, FIREWORK_COUNT do
		launchFirework()
		task.wait(SPAWN_DELAY)
	end

	-- Cleanup folder setelah semua selesai
	task.wait(30)
	if fireworksFolder and fireworksFolder.Parent then
		fireworksFolder:Destroy()
	end
end)
