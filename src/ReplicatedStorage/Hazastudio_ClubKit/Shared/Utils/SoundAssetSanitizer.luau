--!strict
-- Strips Sound instances that use asset IDs blocked for this experience.

local BLOCKED_SOUND_IDS: { [string]: boolean } = {
	["8578316223"] = true, -- not approved for requester (Smite3/4 MainChargeSound)
	["9009370950"] = true, -- file not found (Smite3/4 hammer charge sounds)
}

local SoundAssetSanitizer = {}

local function normalizeAssetId(soundId: string): string
	local id = string.match(soundId, "(%d+)")
	return if id then id else ""
end

function SoundAssetSanitizer.getBlockedSoundIds(): { string }
	local ids: { string } = {}
	for id in pairs(BLOCKED_SOUND_IDS) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

function SoundAssetSanitizer.isBlockedSoundId(soundId: string): boolean
	local normalized = normalizeAssetId(soundId)
	return normalized ~= "" and BLOCKED_SOUND_IDS[normalized] == true
end

function SoundAssetSanitizer.safePlay(sound: Instance?)
	if not sound or not sound:IsA("Sound") or not sound.Parent then
		return
	end
	if SoundAssetSanitizer.isBlockedSoundId(sound.SoundId) then
		return
	end
	pcall(function()
		sound:Play()
	end)
end

function SoundAssetSanitizer.safeStop(sound: Instance?)
	if not sound or not sound:IsA("Sound") or not sound.Parent then
		return
	end
	pcall(function()
		sound:Stop()
	end)
end

function SoundAssetSanitizer.sanitizeClone(root: Instance)
	SoundAssetSanitizer.removeBlockedSounds(root)
end

function SoundAssetSanitizer.removeBlockedSounds(root: Instance): number
	local removed = 0

	local function maybeRemove(sound: Sound)
		if SoundAssetSanitizer.isBlockedSoundId(sound.SoundId) then
			sound:Destroy()
			removed += 1
		end
	end

	if root:IsA("Sound") then
		maybeRemove(root)
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Sound") then
			maybeRemove(descendant)
		end
	end

	return removed
end

return SoundAssetSanitizer
