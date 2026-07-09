-- Strips blocked Sound assets from WorldEffects before donation VFX clone/play.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundAssetSanitizer = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.SoundAssetSanitizer)

local function sanitizeSoundInstance(sound: Sound)
	if SoundAssetSanitizer.isBlockedSoundId(sound.SoundId) then
		sound:Destroy()
	end
end

local function sanitizeTree(root: Instance?)
	if not root then
		return
	end
	SoundAssetSanitizer.removeBlockedSounds(root)
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
