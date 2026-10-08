-- Strips blocked Sound assets from WorldEffects before donation VFX clone/play, and (when
-- Config.ClientFootprint.DEFER_EFFECT_SOUNDS) unloads the templates' audio until a clone needs it
-- (SoundAssetSanitizer.sanitizeClone puts the ids back).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundAssetSanitizer = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.SoundAssetSanitizer)

local deferSounds = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config).ClientFootprint.DEFER_EFFECT_SOUNDS
	== true

local function sanitizeSoundInstance(sound: Sound)
	if SoundAssetSanitizer.isBlockedSoundId(sound.SoundId) then
		sound:Destroy()
	elseif deferSounds then
		SoundAssetSanitizer.deferSound(sound)
	end
end

local function sanitizeTree(root: Instance?)
	if not root then
		return
	end
	SoundAssetSanitizer.removeBlockedSounds(root)
	if deferSounds then
		SoundAssetSanitizer.deferSounds(root)
	end
	root.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Sound") then
			sanitizeSoundInstance(descendant)
		end
	end)
end

local worldEffects = ReplicatedStorage:FindFirstChild("WorldEffects")
if not worldEffects then
	worldEffects = ReplicatedStorage:WaitForChild("WorldEffects", 30)
end
sanitizeTree(worldEffects)
